import { createClient } from "jsr:@supabase/supabase-js@2";

const J=(b:any,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{"Content-Type":"application/json"}});
const backoff=(attempt:number)=>Math.min(360,Math.max(5,5*Math.pow(2,Math.max(0,attempt-1))));

Deno.serve(async(req:Request)=>{
  if(req.method!=="POST") return J({error:"method_not_allowed"},405);
  const url=Deno.env.get("SUPABASE_URL")??"", anon=Deno.env.get("SUPABASE_ANON_KEY")??"", service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")??"";
  const auth=req.headers.get("Authorization")??"";
  const userClient=createClient(url,anon,{global:{headers:{Authorization:auth}}});
  const admin=createClient(url,service);
  let body:any={}; try{body=await req.json()}catch{}
  const mode=String(body.mode??"manual");

  if(mode==="scheduled"){
    const token=req.headers.get("x-cron-token")??"";
    const {data:ok,error}=await admin.rpc("platform_validate_connector_dispatch_token",{p_token:token});
    if(error||ok!==true) return J({error:"invalid_cron_token"},403);
  } else {
    const {data:{user}}=await userClient.auth.getUser();
    if(!user) return J({error:"authentication_required"},401);
    const {data:m}=await admin.from("organization_members").select("role,status").eq("user_id",user.id).eq("status","active").in("role",["owner","admin","super_admin"]).limit(1);
    if(!m?.length) return J({error:"admin_required"},403);
  }

  const now=new Date();
  const {data:critical}=await admin.from("platform_connector_alerts").select("id,connection_id,severity,status,title,message,first_seen_at,acknowledged_at").eq("severity","critical").eq("status","open").is("acknowledged_at",null).lte("first_seen_at",new Date(now.getTime()-30*60000).toISOString());
  for(const a of critical??[]){
    const {data:c}=await admin.from("platform_connector_connections").select("organization_id").eq("id",a.connection_id).maybeSingle(); if(!c) continue;
    const {data:owners}=await admin.from("organization_members").select("user_id").eq("organization_id",c.organization_id).eq("status","active").eq("role","owner");
    for(const o of owners??[]){
      await admin.from("platform_connector_alert_deliveries").upsert({alert_id:a.id,organization_id:c.organization_id,user_id:o.user_id,channel:"email_escalation",status:"pending",next_attempt_at:new Date().toISOString(),escalation_level:1,escalated_at:new Date().toISOString()},{onConflict:"alert_id,user_id,channel",ignoreDuplicates:true});
    }
  }

  const {data:due,error:de}=await admin.from("platform_connector_alert_deliveries").select("*").in("status",["pending","failed"]).lte("next_attempt_at",now.toISOString()).order("created_at",{ascending:true}).limit(100);
  if(de) return J({error:de.message},500);
  let sent=0,failed=0,skipped=0;
  for(const d of due??[]){
    if((d.attempt_count??0)>=(d.max_attempts??5)){await admin.from("platform_connector_alert_deliveries").update({status:"skipped",last_error:"max_attempts_exceeded",updated_at:new Date().toISOString()}).eq("id",d.id); skipped++; continue;}
    const attempt=(d.attempt_count??0)+1;
    const {data:a}=await admin.from("platform_connector_alerts").select("id,title,message,severity,status,connection_id").eq("id",d.alert_id).maybeSingle();
    if(!a||a.status==="resolved"){await admin.from("platform_connector_alert_deliveries").update({status:"skipped",last_error:"alert_resolved_or_missing",updated_at:new Date().toISOString()}).eq("id",d.id); skipped++; continue;}
    try{
      if(d.channel==="in_app"){
        await admin.from("crm_notifications").insert({organization_id:d.organization_id,user_id:d.user_id,title:a.title,body:a.message??"Connector requires attention",severity:a.severity==="critical"?"critical":"warning",category:"integration_health",entity_type:"connector_alert",entity_id:a.id,action_url:`/integration-health.html?connection_id=${a.connection_id}`,is_read:false});
        await admin.from("platform_connector_alert_deliveries").update({status:"sent",attempt_count:attempt,sent_at:new Date().toISOString(),last_error:null,updated_at:new Date().toISOString()}).eq("id",d.id); sent++; continue;
      }
      const {data:u}=await admin.auth.admin.getUserById(d.user_id); const email=u?.user?.email;
      if(!email) throw new Error("recipient_email_missing");
      const resend=Deno.env.get("RESEND_API_KEY")??""; if(!resend) throw new Error("resend_api_key_not_configured");
      const from=Deno.env.get("EMAIL_FROM")??"ApplianceIQ <onboarding@resend.dev>";
      const escalation=d.channel==="email_escalation";
      const subject=`${escalation?"ESCALATION: ":""}[ApplianceIQ] ${a.title}`;
      const text=`${escalation?"Critical integration alert has remained unacknowledged for at least 30 minutes.\n\n":""}${a.message??"Connector requires attention."}\n\nOpen Integration Health: /integration-health.html?connection_id=${a.connection_id}`;
      const r=await fetch("https://api.resend.com/emails",{method:"POST",headers:{"Content-Type":"application/json",Authorization:`Bearer ${resend}`},body:JSON.stringify({from,to:[email],subject,text})});
      const rb=await r.json().catch(()=>({})); if(!r.ok) throw new Error(String(rb?.message??`resend_${r.status}`));
      await admin.from("platform_connector_alert_deliveries").update({status:"sent",attempt_count:attempt,provider_message_id:String(rb?.id??""),sent_at:new Date().toISOString(),last_error:null,updated_at:new Date().toISOString()}).eq("id",d.id); sent++;
    }catch(e){
      const mins=backoff(attempt); const terminal=attempt>=(d.max_attempts??5);
      await admin.from("platform_connector_alert_deliveries").update({status:terminal?"skipped":"failed",attempt_count:attempt,last_error:String((e as any)?.message??e).slice(0,500),next_attempt_at:new Date(Date.now()+mins*60000).toISOString(),updated_at:new Date().toISOString()}).eq("id",d.id); failed++;
    }
  }
  return J({ok:true,processed:(due??[]).length,sent,failed,skipped,escalations_queued:(critical??[]).length});
});
