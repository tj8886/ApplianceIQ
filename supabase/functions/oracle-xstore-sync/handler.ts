import {boundedText,fetchAccessToken} from './provider.ts';
import {runStep} from './runner.ts';
type Environment=(n:string)=>string|undefined;
const headers={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS','Content-Type':'application/json','Cache-Control':'no-store'};
export function approvedUrl(value:string,origins:string|undefined){const u=new URL(value),allow=JSON.parse(origins??'[]');if(!Array.isArray(allow)||!allow.includes(u.origin)||u.protocol!=='https:'||u.username||u.password||u.search||u.hash||u.port&&u.port!=='443'||u.hostname==='localhost'||u.hostname.includes(':')||/^\d+\.\d+\.\d+\.\d+$/.test(u.hostname))throw Error('origin_not_approved');return u.toString();}
export function createHandler({createClient,env,fetchImpl=fetch,loadEnvironment=async(e:Environment)=>e}:{createClient:any;env:Environment;fetchImpl?:typeof fetch;loadEnvironment?:(e:Environment,f:typeof fetch)=>Promise<Environment>}){
 const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers});
 const failure=(e:any)=>reply({error:e.code==='42501'?'connection_access_denied':e.code==='40001'?'connection_not_ready':'xstore_operation_failed'},e.code==='42501'?403:e.code==='40001'?409:['22023','22P02'].includes(e.code)?400:500);
 return async(req:Request)=>{
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers});if(req.method!=='POST')return reply({error:'method_not_allowed'},405);
  const auth=req.headers.get('Authorization')??'';if(!/^Bearer \S+$/i.test(auth))return reply({error:'unauthorized'},401);
  try{
   const user=createClient(env('SUPABASE_URL'),env('SUPABASE_ANON_KEY'),{global:{headers:{Authorization:auth}},auth:{persistSession:false,autoRefreshToken:false}});
   const identity=await user.auth.getUser();if(identity.error||!identity.data?.user||identity.data.user.is_anonymous)return reply({error:'unauthorized'},401);
   const raw=await req.text();if(new TextEncoder().encode(raw).length>16384)return reply({error:'body_too_large'},413);let body;try{body=JSON.parse(raw);}catch{return reply({error:'invalid_json'},400);}
   if(!body||typeof body!=='object'||Array.isArray(body)||!['status','configure','test','sync'].includes(body.action??'status')||typeof body.connection_id!=='string'||!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(body.connection_id))return reply({error:'invalid_request'},400);
   const scope=await user.rpc('tj_xstore_setup',{p_body:body});if(scope.error)return failure(scope.error);if(scope.data?.ok===false)return reply(scope.data,409);if(body.action==='sync'&&scope.data?.done)return reply(scope.data);if(!['test','sync'].includes(body.action))return reply(scope.data);
   const runtime=await loadEnvironment(env,fetchImpl),cfg=scope.data.configuration;let tokenUrl,endpoint;
   try{tokenUrl=approvedUrl(cfg.token_url,runtime('XSTORE_ALLOWED_ORIGINS'));const path=body.action==='sync'&&scope.data.phase==='fetch'?cfg.endpoints?.[scope.data.resource]:Object.values(cfg.endpoints??{})[0];if(typeof path!=='string'||!/^\/?[A-Za-z0-9_/-]+$/.test(path)||path.includes('//'))throw Error('unsafe_path');endpoint=approvedUrl(cfg.base_url.replace(/\/$/,'')+'/'+path.replace(/^\//,''),runtime('XSTORE_ALLOWED_ORIGINS'));}catch{return reply({error:'xstore_origins_not_approved',...(body.action==='sync'?{job_id:scope.data.job_id,resumable:true}:{})},503);}
   const service=createClient(env('SUPABASE_URL'),env('SUPABASE_SERVICE_ROLE_KEY'),{auth:{persistSession:false,autoRefreshToken:false}});
   if(body.action==='sync'){
    const result=await runStep({user,service,native:identity.data.user.id,body,scope:scope.data,endpoint,tokenUrl,fetchImpl});
    if(result.error){if(result.error.code==='502')return reply({error:'xstore_step_failed',job_id:scope.data.job_id,resumable:result.error.resumable,done:result.error.done,status:result.error.status},502);return failure(result.error);}
    return reply(result.data,result.data?.done?200:202);
   }
   const loaded=await service.rpc('aiq_xstore_test_context',{p_connection_id:body.connection_id,p_native_user:identity.data.user.id,p_version:scope.data.version});if(loaded.error)return failure(loaded.error);
   const current=loaded.data.configuration;if(current.base_url!==cfg.base_url||current.token_url!==cfg.token_url||JSON.stringify(current.endpoints)!==JSON.stringify(cfg.endpoints))return reply({error:'configuration_changed'},409);
   try{
    const token=await fetchAccessToken(tokenUrl,loaded.data.credential,fetchImpl);
    const response=await fetchImpl(endpoint,{method:'GET',redirect:'error',signal:AbortSignal.timeout(10000),headers:{Authorization:'Bearer '+token,Accept:'application/json, application/xml, text/xml'}});
    const ct=response.headers.get('content-type')?.split(';')[0].trim().toLowerCase();if(!['application/json','application/xml','text/xml'].includes(ct??'')){await response.body?.cancel();throw Error('invalid_response_type');}
    const text=await boundedText(response,1048576);if(ct==='application/json'){const data=JSON.parse(text);if(!data||typeof data!=='object')throw Error('invalid_json');}else if(!text.trim().startsWith('<')||/<!DOCTYPE|<!ENTITY/i.test(text))throw Error('unsafe_xml');
    return reply({ok:true,status:response.status,content_type:ct,verification:'endpoint_reachable',sync_ready:false,requires_import_verification:true});
   }catch{return reply({error:'xstore_test_failed'},502);}
  }catch{return reply({error:'xstore_operation_failed'},500);}
 };
}
