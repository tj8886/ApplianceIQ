import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
const competencies=["discovery","product_knowledge","recommendation","value_building","objection_handling","closing","attachment","communication","trust","process_discipline"];

Deno.serve(async(req:Request)=>{
  if(req.method==="OPTIONS") return new Response("ok",{headers:corsHeaders});
  if(req.method!=="POST") return json({error:"method_not_allowed"},405);
  const auth=req.headers.get("authorization")??"";
  if(!auth.startsWith("Bearer ")) return json({error:"unauthorized"},401);
  const url=Deno.env.get("SUPABASE_URL")??"", anon=Deno.env.get("SUPABASE_ANON_KEY")??"", service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")??"";
  const apiKey=Deno.env.get("ANTHROPIC_API_KEY")??"", model=Deno.env.get("AI_MODEL_STANDARD")??Deno.env.get("AI_MODEL")??"";
  if(!url||!anon||!service||!apiKey||!model) return json({error:"server_not_configured"},503);
  const sb=createClient(url,anon,{global:{headers:{authorization:auth}}});
  const admin=createClient(url,service);
  const {data:{user},error:userErr}=await sb.auth.getUser();
  if(userErr||!user) return json({error:"auth_failed"},401);
  let body:any; try{body=await req.json()}catch{return json({error:"invalid_json"},400)}
  const recordingId=String(body.recording_id??"");
  if(!recordingId) return json({error:"recording_id_required"},400);

  const {data:rec}=await admin.from("sales_recordings").select("id,organization_id,user_id,consent_confirmed,transcript_id,kind,recording_source").eq("id",recordingId).maybeSingle();
  if(!rec) return json({error:"recording_not_found"},404);
  if(rec.user_id!==user.id){
    const {data:member}=await sb.from("organization_members").select("role").eq("organization_id",rec.organization_id).eq("user_id",user.id).eq("status","active").maybeSingle();
    if(!member||!["owner","admin","manager"].includes(String(member.role))) return json({error:"forbidden"},403);
  }
  if(rec.consent_confirmed!==true) return json({error:"consent_required"},409);

  let transcript:any=null;
  if(rec.transcript_id){const r=await admin.from("recording_transcripts").select("id,content,status").eq("id",rec.transcript_id).maybeSingle(); transcript=r.data}
  if(!transcript){const r=await admin.from("recording_transcripts").select("id,content,status").eq("recording_id",recordingId).eq("status","completed").order("created_at",{ascending:false}).limit(1).maybeSingle(); transcript=r.data}
  if(!transcript?.content?.trim()) return json({error:"completed_transcript_required"},409);

  const system=`You are ApplianceIQ's evidence-based sales coach. Analyze a REAL appliance retail sales conversation. Score observable salesperson behavior only. Never invent facts that are not in the transcript. Use 0-100 scores for these exact competencies: ${competencies.join(", ")}. Also return strongest_moment, weakest_moment, missed_opportunities (array), evidence (object keyed by competency with a short transcript-grounded reason), and summary. Respond JSON only.`;
  const prompt=`Transcript:\n${transcript.content.slice(0,45000)}\n\nReturn: {"scores":{"discovery":0,"product_knowledge":0,"recommendation":0,"value_building":0,"objection_handling":0,"closing":0,"attachment":0,"communication":0,"trust":0,"process_discipline":0},"strongest_moment":"","weakest_moment":"","missed_opportunities":[],"evidence":{},"summary":""}`;
  const resp=await fetch("https://api.anthropic.com/v1/messages",{method:"POST",headers:{"content-type":"application/json","x-api-key":apiKey,"anthropic-version":"2023-06-01"},body:JSON.stringify({model,max_tokens:1800,system,messages:[{role:"user",content:prompt}]})});
  if(!resp.ok) return json({error:"ai_request_failed",detail:await resp.text()},502);
  const ai=await resp.json();
  const text=(ai.content??[]).filter((b:any)=>b.type==="text").map((b:any)=>b.text).join("").replace(/```json|```/g,"").trim();
  let parsed:any; try{parsed=JSON.parse(text)}catch{return json({error:"invalid_ai_response"},502)}
  const cleanScores:Record<string,number>={};
  for(const key of competencies){const n=Number(parsed.scores?.[key]); if(Number.isFinite(n)) cleanScores[key]=Math.max(0,Math.min(100,n))}
  const nums=Object.values(cleanScores); const overall=nums.length?nums.reduce((a,b)=>a+b,0)/nums.length:0;
  const analysis={summary:String(parsed.summary??""),strongest_moment:String(parsed.strongest_moment??""),weakest_moment:String(parsed.weakest_moment??""),missed_opportunities:Array.isArray(parsed.missed_opportunities)?parsed.missed_opportunities:[],evidence:parsed.evidence??{}};
  const {data:review,error:insertErr}=await admin.from("ai_coaching_reviews").insert({organization_id:rec.organization_id,recording_id:recordingId,review_kind:"performance_brain_real_sale",analysis,kpi_scores:cleanScores,overall_score:Number(overall.toFixed(2)),model}).select("id").single();
  if(insertErr||!review) return json({error:"review_insert_failed",detail:insertErr?.message},500);
  await admin.from("sales_recordings").update({coaching_review_id:review.id,status:"reviewed",updated_at:new Date().toISOString()}).eq("id",recordingId);
  return json({ok:true,review_id:review.id,overall_score:Number(overall.toFixed(1)),scores:cleanScores,...analysis});
});

function json(body:unknown,status=200){return new Response(JSON.stringify(body),{status,headers:{...corsHeaders,"content-type":"application/json"}})}
