const headers={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS','Content-Type':'application/json','Cache-Control':'no-store'};
export function approvedEpassEndpoint(base:string,path:string,origins:string|undefined){
 let allow;try{allow=JSON.parse(origins??'[]');}catch{throw new Error('epass_origin_not_approved');}
 const url=new URL(base);if(!Array.isArray(allow)||!allow.includes(url.origin)||url.protocol!=='https:'||url.port&&url.port!=='443'||url.username||url.password||url.search||url.hash||url.hostname==='localhost'||url.hostname.endsWith('.localhost')||url.hostname.includes(':')||/^\d+\.\d+\.\d+\.\d+$/.test(url.hostname)||!/^\/?[A-Za-z0-9_/-]{1,500}$/.test(path)||path.includes('//'))throw new Error('epass_origin_not_approved');
 return new URL(url.toString().replace(/\/$/,'')+'/'+path.replace(/^\//,'')).toString();
}
export function createHandler({createClient,env,fetchImpl=fetch}:{createClient:any;env:(n:string)=>string|undefined;fetchImpl?:typeof fetch}){
 const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers});
 const failure=(e:any)=>reply({error:({'42501':'organization_access_denied','40001':'epass_not_ready','22023':'invalid_request','22P02':'invalid_request'} as Record<string,string>)[e.code]??'epass_operation_failed'},({'42501':403,'40001':409,'22023':400,'22P02':400} as Record<string,number>)[e.code]??500);
 return async(req:Request)=>{
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers});if(req.method!=='POST')return reply({error:'method_not_allowed'},405);
  const auth=req.headers.get('Authorization')??'';if(!/^Bearer \S+$/i.test(auth))return reply({error:'unauthorized'},401);
  try{
   const user=createClient(env('SUPABASE_URL'),env('SUPABASE_ANON_KEY'),{global:{headers:{Authorization:auth}},auth:{persistSession:false,autoRefreshToken:false}});
   const identity=await user.auth.getUser();if(identity.error||!identity.data?.user||identity.data.user.is_anonymous)return reply({error:'unauthorized'},401);
   const raw=await req.text();if(new TextEncoder().encode(raw).length>16384)return reply({error:'body_too_large'},413);
   let body;try{body=JSON.parse(raw);}catch{return reply({error:'invalid_json'},400);}
   if(!body||typeof body!=='object'||Array.isArray(body)||!['status','configure','test','sync'].includes(body.action??'status')||typeof body.connection_id!=='string'||!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(body.connection_id))return reply({error:'invalid_request'},400);
   const scope=await user.rpc('tj_epass_setup',{p_body:body});if(scope.error)return failure(scope.error);if(scope.data?.ok===false)return reply(scope.data,409);
   if(body.action!=='test')return reply(scope.data);
   const cfg=scope.data.configuration;let endpoint;
   try{const paths=Object.values(cfg.endpoints??{});endpoint=approvedEpassEndpoint(cfg.base_url,String(paths[0]??''),env('EPASS_ALLOWED_ORIGINS'));}catch{return reply({error:'epass_origin_not_approved'},503);}
   const service=createClient(env('SUPABASE_URL'),env('SUPABASE_SERVICE_ROLE_KEY'),{auth:{persistSession:false,autoRefreshToken:false}});
   const loaded=await service.rpc('aiq_epass_test_context',{p_connection_id:body.connection_id,p_native_user:identity.data.user.id,p_version:scope.data.version});if(loaded.error)return failure(loaded.error);
   if(JSON.stringify(loaded.data.configuration.endpoints)!==JSON.stringify(cfg.endpoints)||loaded.data.configuration.base_url!==cfg.base_url)return reply({error:'configuration_changed'},409);
   const credential=loaded.data.credential;const upstream:Record<string,string>={Accept:'application/json'};
   for(const [key,value] of Object.entries(credential)){if(!['api_key','api_secret','token'].includes(key)||typeof value!=='string'||value.length>4096||/[\r\n]/.test(value))return reply({error:'invalid_credential'},409);}
   for(const name of [loaded.data.configuration.api_key_header,loaded.data.configuration.api_secret_header])if(typeof name!=='string'||!/^[A-Za-z][A-Za-z0-9-]{0,63}$/.test(name)||['host','authorization','cookie','accept','content-type','connection','proxy-authorization'].includes(name.toLowerCase()))return reply({error:'invalid_credential_header'},409);
   if(credential.api_key)upstream[loaded.data.configuration.api_key_header]=credential.api_key;if(credential.api_secret)upstream[loaded.data.configuration.api_secret_header]=credential.api_secret;if(credential.token)upstream.Authorization='Bearer '+credential.token;
   try{
    const response=await fetchImpl(endpoint,{method:'GET',headers:upstream,redirect:'error',signal:AbortSignal.timeout(10000)});
    if(!response.ok||!response.headers.get('content-type')?.toLowerCase().includes('application/json')){await response.body?.cancel();return reply({error:'epass_test_failed'},502);}
    const reader=response.body?.getReader();let size=0,text='';const decoder=new TextDecoder();if(reader){try{for(;;){const n=await reader.read();if(n.done)break;size+=n.value.length;if(size>1024*1024)throw new Error('response_too_large');text+=decoder.decode(n.value,{stream:true});}text+=decoder.decode();}catch(e){await reader.cancel();throw e;}}
    const data=JSON.parse(text);if(!data||typeof data!=='object')throw new Error('invalid_response');
    // Reachability is not complete import or onboarding verification. No activation/last_success mutation.
    return reply({ok:true,status:response.status,sync_ready:false,verification:'endpoint_reachable',requires_import_verification:true});
   }catch{return reply({error:'epass_test_failed'},502);}
  }catch{return reply({error:'epass_operation_failed'},500);}
 };
}
