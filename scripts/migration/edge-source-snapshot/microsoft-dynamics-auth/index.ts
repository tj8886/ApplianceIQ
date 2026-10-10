import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"GET, POST, OPTIONS"};
const BC_SCOPE="openid profile offline_access https://api.businesscentral.dynamics.com/user_impersonation";
function json(b:unknown,s=200){return new Response(JSON.stringify(b),{status:s,headers:{...cors,"Content-Type":"application/json"}})}
function b64url(s:string){return s.replace(/-/g,'+').replace(/_/g,'/').padEnd(Math.ceil(s.length/4)*4,'=')}
function claims(t?:string){try{return JSON.parse(atob(b64url((t||'').split('.')[1])))}catch{return {}}}
function rand(){const a=new Uint8Array(32);crypto.getRandomValues(a);return Array.from(a).map(x=>x.toString(16).padStart(2,'0')).join('')}
function safeReturn(u:string|null){if(!u)return null;try{const x=new URL(u);return x.protocol==='https:'||x.hostname==='localhost'?x.toString():null}catch{return null}}
function donePage(ok:boolean,msg:string){return new Response(`<!doctype html><html><body style="font-family:system-ui;padding:40px"><h2>${ok?'Microsoft connected':'Connection failed'}</h2><p>${msg.replace(/[<>&]/g,'')}</p><script>setTimeout(()=>window.close(),1200)</script></body></html>`,{status:ok?200:400,headers:{"Content-Type":"text/html; charset=utf-8"}})}
Deno.serve(async(req:Request)=>{
 if(req.method==='OPTIONS')return new Response('ok',{headers:cors});
 const supabaseUrl=Deno.env.get('SUPABASE_URL')!;const anon=Deno.env.get('SUPABASE_ANON_KEY')!;const service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;const clientId=Deno.env.get('MICROSOFT_CLIENT_ID');const clientSecret=Deno.env.get('MICROSOFT_CLIENT_SECRET');
 if(!clientId||!clientSecret)return req.method==='GET'?donePage(false,'Microsoft application credentials are not configured.'):json({error:'microsoft_client_credentials_not_configured'},503);
 const redirectUri=Deno.env.get('MICROSOFT_REDIRECT_URI')||`${supabaseUrl}/functions/v1/microsoft-dynamics-auth`;const admin=createClient(supabaseUrl,service);
 if(req.method==='POST'){
   const auth=req.headers.get('Authorization')??'';const userClient=createClient(supabaseUrl,anon,{global:{headers:{Authorization:auth}}});const {data:{user}}=await userClient.auth.getUser();if(!user)return json({error:'unauthorized'},401);
   let body:any;try{body=await req.json()}catch{return json({error:'invalid_json'},400)}const connectionId=String(body.connection_id??'');if(!connectionId)return json({error:'connection_id_required'},400);
   const {data:conn}=await admin.from('platform_connector_connections').select('id,organization_id,connector_id,variant_id').eq('id',connectionId).maybeSingle();if(!conn)return json({error:'connection_not_found'},404);
   const {data:member}=await admin.from('organization_members').select('role,status').eq('organization_id',conn.organization_id).eq('user_id',user.id).eq('status','active').maybeSingle();if(!member||!['owner','admin','super_admin'].includes(String(member.role)))return json({error:'admin_required'},403);
   const {data:c}=await admin.from('platform_connectors').select('key').eq('id',conn.connector_id).single();const {data:v}=await admin.from('platform_connector_variants').select('key').eq('id',conn.variant_id).single();if(c?.key!=='microsoft_dynamics_365')return json({error:'not_microsoft_dynamics_connection'},400);
   if(v?.key!=='business_central')return json({error:'oauth_scope_not_implemented_for_variant',variant:v?.key},400);
   const state=rand();const returnUrl=safeReturn(body.return_url?String(body.return_url):null);
   const {error}=await admin.from('platform_oauth_states').insert({provider:'microsoft_dynamics_365',state_token:state,organization_id:conn.organization_id,connection_id:connectionId,user_id:user.id,return_url:returnUrl,metadata:{variant:'business_central',scope:BC_SCOPE}});if(error)return json({error:error.message},500);
   const q=new URLSearchParams({client_id:clientId,response_type:'code',redirect_uri:redirectUri,response_mode:'query',scope:BC_SCOPE,state,prompt:'select_account'});
   return json({ok:true,authorization_url:`https://login.microsoftonline.com/organizations/oauth2/v2.0/authorize?${q.toString()}`,scope:BC_SCOPE});
 }
 if(req.method!=='GET')return json({error:'method_not_allowed'},405);
 const u=new URL(req.url);const code=u.searchParams.get('code');const state=u.searchParams.get('state');const oauthError=u.searchParams.get('error');const oauthDesc=u.searchParams.get('error_description');
 if(oauthError)return donePage(false,oauthDesc||oauthError);if(!code||!state)return donePage(false,'Missing OAuth code or state.');
 const {data:st}=await admin.from('platform_oauth_states').select('*').eq('provider','microsoft_dynamics_365').eq('state_token',state).is('consumed_at',null).gt('expires_at',new Date().toISOString()).maybeSingle();if(!st)return donePage(false,'The authorization request expired or was already used.');
 await admin.from('platform_oauth_states').update({consumed_at:new Date().toISOString()}).eq('id',st.id);
 const form=new URLSearchParams({client_id:clientId,client_secret:clientSecret,grant_type:'authorization_code',code,redirect_uri:redirectUri,scope:String(st.metadata?.scope||BC_SCOPE)});
 const tr=await fetch('https://login.microsoftonline.com/organizations/oauth2/v2.0/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:form});const tok=await tr.json();if(!tr.ok)return donePage(false,tok.error_description||tok.error||`Token exchange failed (${tr.status}).`);
 const cl=claims(tok.access_token);const idc=claims(tok.id_token);const tenant=String(cl.tid||idc.tid||'');const credential={...tok,tenant_id:tenant,obtained_at:new Date().toISOString(),scope:String(tok.scope||st.metadata?.scope||BC_SCOPE)};
 const {data:existing}=await admin.from('platform_connector_connections').select('credential_ref,auth_metadata').eq('id',st.connection_id).single();let credentialRef=existing?.credential_ref;
 if(credentialRef){const {error:e}=await admin.rpc('platform_update_connector_secret',{p_id:credentialRef,p_secret:JSON.stringify(credential)});if(e)return donePage(false,'Could not securely update the Microsoft credential.')}else{const {data:newRef,error:e}=await admin.rpc('platform_store_connector_secret',{p_name:`microsoft_bc_${st.connection_id}`,p_secret:JSON.stringify(credential),p_description:`Microsoft Business Central OAuth tokens for connector ${st.connection_id}`});if(e||!newRef)return donePage(false,'Could not securely store the Microsoft credential.');credentialRef=newRef}
 await admin.from('platform_connector_connections').update({credential_ref:String(credentialRef),auth_status:'valid',status:'pending',auth_metadata:{...(existing?.auth_metadata||{}),provider:'microsoft',variant:'business_central',tenant_id:tenant,identity_connected:true,api_consent_pending:false,scope:credential.scope,connected_at:new Date().toISOString()},last_error:null,updated_at:new Date().toISOString()}).eq('id',st.connection_id);
 const ret=safeReturn(st.return_url);if(ret){const ru=new URL(ret);ru.searchParams.set('microsoft','connected');ru.searchParams.set('connection_id',st.connection_id);return Response.redirect(ru.toString(),302)}
 return donePage(true,'Business Central authorization succeeded. You can return to ApplianceIQ and discover the company/environment.');
});
