import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const J=(b:any,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{'Content-Type':'application/json'}});
const BOT_EMAIL='connector-recovery@applianceiq.internal';
const ROUTES:Record<string,string>={
  microsoft_dynamics_365:'business-central-sync',
  storis:'storis-sync',
  epass:'epass-sync',
  shopify:'shopify-initial-sync',
  oracle_xstore:'oracle-xstore-sync',
  retailvantage:'retailvantage-sync',
  windward:'windward-sync'
};

Deno.serve(async(req:Request)=>{
  if(req.method!=='POST')return J({error:'POST required'},405);

  const su=Deno.env.get('SUPABASE_URL')!;
  const anon=Deno.env.get('SUPABASE_ANON_KEY')!;
  const service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const admin=createClient(su,service,{auth:{persistSession:false,autoRefreshToken:false}});
  const supplied=req.headers.get('x-connector-dispatch-token')??'';

  const {data:valid}=await admin.rpc('platform_validate_connector_dispatch_token',{p_token:supplied});
  if(!valid)return J({error:'invalid_dispatch_token'},401);

  const {data:secret,error:se}=await admin.rpc('platform_get_connector_recovery_secret');
  if(se||!secret)return J({error:'recovery_secret_unavailable'},500);
  const password=String(secret);

  let bot:any=null;
  for(let page=1;page<=5&&!bot;page++){
    const {data,error}=await admin.auth.admin.listUsers({page,perPage:200});
    if(error)break;
    bot=data.users.find((u:any)=>String(u.email??'').toLowerCase()===BOT_EMAIL);
    if(data.users.length<200)break;
  }

  if(!bot){
    const {data,error}=await admin.auth.admin.createUser({
      email:BOT_EMAIL,
      password,
      email_confirm:true,
      app_metadata:{internal_service:true,service:'connector_recovery'}
    });
    if(error||!data.user)return J({error:'recovery_bot_create_failed',detail:error?.message},500);
    bot=data.user;
  }else{
    await admin.auth.admin.updateUserById(bot.id,{
      password,
      app_metadata:{...(bot.app_metadata??{}),internal_service:true,service:'connector_recovery'}
    });
  }

  const authClient=createClient(su,anon,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:session,error:le}=await authClient.auth.signInWithPassword({email:BOT_EMAIL,password});
  if(le||!session.session)return J({error:'recovery_bot_login_failed',detail:le?.message},500);
  const jwt=session.session.access_token;

  const {data:queue,error:qe}=await admin
    .from('platform_connector_job_recovery_queue')
    .select('id,failed_job_id,connection_id,reason,status,attempt_count,max_attempts,available_at')
    .eq('status','pending')
    .lte('available_at',new Date().toISOString())
    .order('created_at',{ascending:true})
    .limit(10);
  if(qe)return J({error:qe.message},500);

  const out:any[]=[];
  for(const item of queue??[]){
    const {data:claimed}=await admin
      .from('platform_connector_job_recovery_queue')
      .update({status:'dispatching',updated_at:new Date().toISOString()})
      .eq('id',item.id)
      .eq('status','pending')
      .select('id')
      .maybeSingle();
    if(!claimed)continue;

    let tempMembership=false;
    let orgId:string|null=null;

    try{
      const {data:conn}=await admin
        .from('platform_connector_connections')
        .select('id,organization_id,connector_id')
        .eq('id',item.connection_id)
        .maybeSingle();
      if(!conn)throw new Error('connection_not_found');
      orgId=conn.organization_id;

      const {data:connector}=await admin
        .from('platform_connectors')
        .select('key')
        .eq('id',conn.connector_id)
        .maybeSingle();
      const key=String(connector?.key??'');
      const slug=ROUTES[key];
      if(!slug)throw new Error(`unsupported_connector:${key}`);

      const {data:failed}=await admin
        .from('platform_sync_jobs')
        .select('id,job_type,stats,cursor,attempt_count')
        .eq('id',item.failed_job_id)
        .maybeSingle();

      const {data:existing}=await admin
        .from('organization_members')
        .select('id,role,status')
        .eq('organization_id',orgId)
        .eq('user_id',bot.id)
        .maybeSingle();

      if(existing){
        if(existing.status!=='active'||!['owner','admin'].includes(String(existing.role))){
          throw new Error('recovery_bot_membership_not_admin');
        }
      }else{
        const {error}=await admin.from('organization_members').insert({
          organization_id:orgId,
          user_id:bot.id,
          role:'admin',
          status:'active',
          visibility_scope:'all'
        });
        if(error)throw new Error(`temporary_membership_failed:${error.message}`);
        tempMembership=true;
      }

      let body:any={connection_id:conn.id};
      if(key!=='shopify'){
        body.action='sync';
        const jt=String(failed?.job_type??'incremental');
        body.sync_type=jt.startsWith('business_central_')?jt.replace('business_central_',''):jt;
        const resources=failed?.stats?.resources&&typeof failed.stats.resources==='object'
          ?Object.keys(failed.stats.resources):[];
        if(resources.length)body.resources=resources;
      }

      if(key==='microsoft_dynamics_365'&&failed?.cursor){
        if(failed.cursor.company_id)body.company_id=failed.cursor.company_id;
        if(failed.cursor.environment)body.environment=failed.cursor.environment;
      }

      const r=await fetch(`${su}/functions/v1/${slug}`,{
        method:'POST',
        headers:{
          'Content-Type':'application/json',
          'Authorization':`Bearer ${jwt}`,
          'apikey':anon
        },
        body:JSON.stringify(body)
      });
      const detail=await r.json().catch(()=>({status:r.status}));
      if(!r.ok)throw new Error(`${slug}:${r.status}:${detail?.error??detail?.detail??'failed'}`);

      await admin.from('platform_connector_job_recovery_queue').update({
        status:'completed',
        attempt_count:item.attempt_count+1,
        last_error:null,
        updated_at:new Date().toISOString()
      }).eq('id',item.id);
      out.push({id:item.id,connector:key,status:'completed',http_status:r.status});
    }catch(e){
      const attempts=item.attempt_count+1;
      const dead=attempts>=item.max_attempts;
      const delay=Math.min(60,Math.pow(2,attempts));
      await admin.from('platform_connector_job_recovery_queue').update({
        status:dead?'dead_letter':'pending',
        attempt_count:attempts,
        last_error:String((e as any)?.message??e),
        available_at:new Date(Date.now()+delay*60000).toISOString(),
        updated_at:new Date().toISOString()
      }).eq('id',item.id);
      out.push({id:item.id,status:dead?'dead_letter':'retry_scheduled',attempts,error:String((e as any)?.message??e)});
    }finally{
      if(tempMembership&&orgId){
        await admin.from('organization_members').delete().eq('organization_id',orgId).eq('user_id',bot.id);
      }
    }
  }

  await authClient.auth.signOut();
  return J({ok:true,processed:out.length,results:out});
});
