const headers={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS','Content-Type':'application/json'};
export function createHandler({createClient,env,fetchImpl=fetch}:{createClient:any;env:(name:string)=>string|undefined;fetchImpl?:typeof fetch}){
 const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers});
 return async(req:Request)=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers});if(req.method!=='POST')return reply({error:'method_not_allowed'},405);
  const authorization=req.headers.get('Authorization')??'';if(!authorization.startsWith('Bearer '))return reply({error:'authentication_required'},401);
  try{
   const url=env('SUPABASE_URL')??'',anon=env('SUPABASE_ANON_KEY')??'';
   const user=createClient(url,anon,{global:{headers:{Authorization:authorization}},auth:{persistSession:false,autoRefreshToken:false}});
   const identity=await user.auth.getUser();if(identity.error||!identity.data?.user)return reply({error:'invalid_session'},401);
   const context=await user.rpc('tj_runtime_my_platform_context');if(context.error||!context.data?.organization_id||!context.data.source_user_id)return reply({error:'active_mapped_organization_required'},403);
   const raw=await req.text();if(raw.length>65536)return reply({error:'request_too_large'},413);
   let body;try{body=JSON.parse(raw);}catch{return reply({error:'invalid_json'},400);}
   if(!body||typeof body!=='object'||Array.isArray(body)||typeof body.message!=='string'||body.message.trim().length<3||body.message.length>12000)return reply({error:'invalid_request'},400);
   const org=body.organization_id??context.data.organization_id;let cid=body.conversation_id??null;
   if(!cid){const latest=await user.rpc('tj_latest_product_conversation',{p_organization_id:org});if(latest.error)return reply({error:'conversation_lookup_failed'},latest.error.code==='42501'?403:503);cid=latest.data??null;}
   const payload={...body,message:body.message.trim(),organization_id:org,conversation_id:cid,mode:body.mode??'auto',history:body.history??[],country:body.country??'CA'};
   const r=await fetchImpl(url+'/functions/v1/ai-intelligence-router',{method:'POST',headers:{'Content-Type':'application/json',Authorization:authorization,apikey:anon},body:JSON.stringify(payload),signal:AbortSignal.timeout(120000)});
   return reply(await r.json(),r.status);
  }catch{return reply({error:'assistant_failed'},503);}
 };
}
