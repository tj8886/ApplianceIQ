type Environment=(name:string)=>string|undefined;
export const BC_SCOPE='openid profile offline_access https://api.businesscentral.dynamics.com/user_impersonation';
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const headers={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'GET, POST, OPTIONS','Content-Type':'application/json','Cache-Control':'no-store','Referrer-Policy':'no-referrer'};
export function approvedReturn(value:unknown,origins:string|undefined){
 if(typeof value!=='string'||value.length>2048)throw Error('invalid_return');const url=new URL(value),allow=JSON.parse(origins??'[]');
 if(url.protocol!=='https:'||url.username||url.password||url.hash||!Array.isArray(allow)||!allow.includes(url.origin))throw Error('unapproved_return');
 for(const k of ['code','state','dynamics_code','dynamics_state','microsoft'])url.searchParams.delete(k);
 return url.toString();
}
const random=()=>Array.from(crypto.getRandomValues(new Uint8Array(32)),x=>x.toString(16).padStart(2,'0')).join('');
export async function digest(value:string){return new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value)));}
export async function stateHash(value:string){return Array.from(await digest(value),x=>x.toString(16).padStart(2,'0')).join('');}
async function responseJson(r:Response){if(!r.ok){await r.body?.cancel();throw Error('token_exchange_failed');}let text='',size=0;const reader=r.body?.getReader(),decoder=new TextDecoder();if(!reader)throw Error('empty_response');try{for(;;){const n=await reader.read();if(n.done)break;size+=n.value.length;if(size>65536)throw Error('token_response_too_large');text+=decoder.decode(n.value,{stream:true});}text+=decoder.decode();return JSON.parse(text);}catch(e){await reader.cancel();throw e;}}
export function createHandler({createClient,env,loadEnvironment=async(e:Environment)=>e,fetchImpl=fetch,verifyIdentity}:{createClient:any;env:Environment;loadEnvironment?:(e:Environment,f:typeof fetch)=>Promise<Environment>;fetchImpl?:typeof fetch;verifyIdentity:(t:string,c:any)=>Promise<any>}){
 const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers});
 const failure=(e:any)=>reply({error:e.code==='42501'?'connection_access_denied':e.code==='40001'?'oauth_state_or_destination_not_ready':'oauth_operation_failed'},e.code==='42501'?403:e.code==='40001'?409:500);
 return async(req:Request)=>{
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers});if(!['POST','GET'].includes(req.method))return reply({error:'method_not_allowed'},405);
  try{
   let user:any,identity:any,body:any;
   if(req.method==='POST'){
    const auth=req.headers.get('Authorization')??'';if(!/^Bearer \S+$/i.test(auth))return reply({error:'unauthorized'},401);
    user=createClient(env('SUPABASE_URL'),env('SUPABASE_ANON_KEY'),{global:{headers:{Authorization:auth}},auth:{persistSession:false,autoRefreshToken:false}});
    identity=await user.auth.getUser();if(identity.error||!identity.data?.user||identity.data.user.is_anonymous)return reply({error:'unauthorized'},401);
    const raw=await req.text();if(new TextEncoder().encode(raw).length>16384)return reply({error:'body_too_large'},413);try{body=JSON.parse(raw);}catch{return reply({error:'invalid_json'},400);}
    if(!body||typeof body!=='object'||Array.isArray(body)||!['authorize','complete'].includes(body.action)||!uuid.test(body.connection_id??'')||Object.keys(body).some(k=>!(body.action==='authorize'?['action','connection_id','return_url']:['action','connection_id','code','state']).includes(k)))return reply({error:'invalid_request'},400);
   }
   const runtime=await loadEnvironment(env,fetchImpl),client=runtime('MICROSOFT_CLIENT_ID'),secret=runtime('MICROSOFT_CLIENT_SECRET'),redirect=env('SUPABASE_URL')+'/functions/v1/microsoft-dynamics-auth';
   if(!uuid.test(client??'')||!secret||runtime('MICROSOFT_REDIRECT_URI')!==redirect)return reply({error:'destination_microsoft_registration_required'},503);
   const service=createClient(env('SUPABASE_URL'),env('SUPABASE_SERVICE_ROLE_KEY'),{auth:{persistSession:false,autoRefreshToken:false}});
   if(req.method==='POST'&&body.action==='authorize'){
    let returnUrl;try{returnUrl=approvedReturn(body.return_url,runtime('MICROSOFT_RETURN_ORIGINS'));}catch{return reply({error:'return_origin_not_approved'},400);}
    const state=random(),nonce=random(),verifier=random();const begun=await user.rpc('tj_microsoft_oauth_begin',{p_body:{connection_id:body.connection_id,state_hash:await stateHash(state),nonce,verifier,client_id:client,redirect_uri:redirect,return_url:returnUrl}});if(begun.error)return failure(begun.error);
    if(!uuid.test(begun.data?.tenant_id))return reply({error:'destination_tenant_review_required'},409);
    const challenge=btoa(String.fromCharCode(...await digest(verifier))).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');
    const query=new URLSearchParams({client_id:client!,response_type:'code',redirect_uri:redirect,response_mode:'query',scope:BC_SCOPE,state,nonce,prompt:'select_account',code_challenge:challenge,code_challenge_method:'S256'});
    return reply({ok:true,authorization_url:'https://login.microsoftonline.com/'+begun.data.tenant_id+'/oauth2/v2.0/authorize?'+query});
   }
   const url=new URL(req.url),state=req.method==='GET'?url.searchParams.get('state'):body.state,code=req.method==='GET'?url.searchParams.get('code'):body.code;
   if(typeof state!=='string'||!/^[0-9a-f]{64}$/.test(state)||typeof code!=='string'||!code||code.length>8192||/[\r\n]/.test(code)||req.method==='GET'&&url.searchParams.has('error'))return reply({error:'invalid_oauth_callback'},400);
   const hash=await stateHash(state),context=await service.rpc('aiq_microsoft_oauth_context',{p_hash:hash,p_native:req.method==='POST'?identity.data.user.id:null,p_claim:req.method==='POST'});if(context.error)return failure(context.error);const ctx=context.data;
   let returnUrl;try{returnUrl=approvedReturn(ctx.return_url,runtime('MICROSOFT_RETURN_ORIGINS'));}catch{return reply({error:'return_origin_not_approved'},400);}
   if(ctx.client_id!==client||ctx.redirect_uri!==redirect||!uuid.test(ctx.tenant_id))return reply({error:'oauth_configuration_changed'},409);
   if(req.method==='GET'){
    // Transport the short-lived code only. The signed-in initiating user completes the exchange.
    const target=new URL(returnUrl);target.searchParams.set('dynamics_code',code);target.searchParams.set('dynamics_state',state);target.searchParams.set('connection_id',ctx.connection_id);
    return new Response(null,{status:303,headers:{Location:target.toString(),'Cache-Control':'no-store','Referrer-Policy':'no-referrer'}});
   }
   if(ctx.connection_id!==body.connection_id)return reply({error:'connection_access_denied'},403);
   try{
    const form=new URLSearchParams({client_id:client!,client_secret:secret,grant_type:'authorization_code',code,redirect_uri:redirect,scope:BC_SCOPE,code_verifier:ctx.verifier});
    const tokens=await responseJson(await fetchImpl('https://login.microsoftonline.com/'+ctx.tenant_id+'/oauth2/v2.0/token',{method:'POST',redirect:'error',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:form,signal:AbortSignal.timeout(15000)}));
    if(tokens.token_type!=='Bearer'||typeof tokens.access_token!=='string'||!tokens.access_token||tokens.access_token.length>16000||typeof tokens.refresh_token!=='string'||!tokens.refresh_token||tokens.refresh_token.length>16000||typeof tokens.id_token!=='string'||tokens.id_token.length>16000||!Number.isInteger(tokens.expires_in)||tokens.expires_in<1||tokens.expires_in>86400||typeof tokens.scope!=='string'||!tokens.scope.split(' ').includes('https://api.businesscentral.dynamics.com/user_impersonation'))throw Error('invalid_token_response');
    const claims=await verifyIdentity(tokens.id_token,ctx);
    const credential={access_token:tokens.access_token,refresh_token:tokens.refresh_token,token_type:'Bearer',scope:tokens.scope,tenant_id:ctx.tenant_id,subject:claims.sub,obtained_at:new Date().toISOString(),expires_at:new Date(Date.now()+tokens.expires_in*1000).toISOString()};
    const saved=await service.rpc('aiq_microsoft_oauth_finish',{p_hash:hash,p_native:identity.data.user.id,p_credential:credential});if(saved.error)return failure(saved.error);
    return reply(saved.data);
   }catch{return reply({error:'microsoft_token_validation_failed'},502);}
  }catch{return reply({error:'microsoft_oauth_failed'},500);}
 };
}
