type Env=(name:string)=>string|undefined;
export const SCOPES='read_customers,read_orders,read_products,read_inventory,read_locations,write_customers';
export const DRAFT_SCOPES=SCOPES+',write_draft_orders';
const shopPattern=/^[a-z0-9][a-z0-9-]{0,62}\.myshopify\.com$/;
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const headers={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'GET, POST, OPTIONS','Content-Type':'application/json','Cache-Control':'no-store','Referrer-Policy':'no-referrer'};
export async function stateHash(value:string){return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value))),x=>x.toString(16).padStart(2,'0')).join('');}
export function approvedReturn(value:unknown,origins:string|undefined){
 if(typeof value!=='string'||value.length>2048)throw Error('invalid_return');const u=new URL(value),allow=JSON.parse(origins??'[]');
 if(u.protocol!=='https:'||u.username||u.password||u.hash||!Array.isArray(allow)||!allow.includes(u.origin))throw Error('unapproved_return');
 for(const key of ['shopify_callback','code','state','hmac'])u.searchParams.delete(key);return u.toString();
}
export async function verifyCallback(query:string,secret:string,now=Date.now()){
 if(query.length>16384)throw Error('invalid_callback');const params=new URLSearchParams(query);
 const keys=[...params.keys()];if(new Set(keys).size!==keys.length)throw Error('duplicate_parameters');
 const shop=params.get('shop')??'',state=params.get('state')??'',code=params.get('code')??'',hmac=params.get('hmac')??'',timestamp=params.get('timestamp')??'';
 if(!shopPattern.test(shop)||!/^[0-9a-f]{64}$/.test(state)||!code||code.length>8192||/[\r\n]/.test(code)||!/^[0-9a-f]{64}$/.test(hmac)||!/^\d{10}$/.test(timestamp)||Math.abs(now/1000-Number(timestamp))>600)throw Error('invalid_callback');
 // Shopify's reference implementation signs sorted, decoded key=value pairs.
 const message=[...params.entries()].filter(([k])=>k!=='hmac').sort(([a],[b])=>a<b?-1:a>b?1:0).map(([k,v])=>`${k}=${v}`).join('&');
 const key=await crypto.subtle.importKey('raw',new TextEncoder().encode(secret),{name:'HMAC',hash:'SHA-256'},false,['verify']);
 const sig=new Uint8Array(hmac.match(/../g)!.map(x=>parseInt(x,16)));
 if(!await crypto.subtle.verify('HMAC',key,sig,new TextEncoder().encode(message)))throw Error('invalid_signature');
 return {shop,state,code};
}
async function boundedText(input:Request|Response,max:number){const reader=input.body?.getReader();if(!reader)return '';let size=0;const chunks:Uint8Array[]=[];try{for(;;){const p=await reader.read();if(p.done)break;size+=p.value.length;if(size>max){await reader.cancel();throw Error('body_too_large');}chunks.push(p.value);}}finally{reader.releaseLock();}const bytes=new Uint8Array(size);let offset=0;for(const c of chunks){bytes.set(c,offset);offset+=c.length;}return new TextDecoder('utf-8',{fatal:true}).decode(bytes);}
export function createHandler({createClient,env,loadEnvironment=async(e:Env)=>e,fetchImpl=fetch}:{createClient:any;env:Env;loadEnvironment?:(e:Env,f:typeof fetch)=>Promise<Env>;fetchImpl?:typeof fetch}){
 const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers});
 const failure=(e:any)=>reply({error:e.code==='42501'?'connection_access_denied':e.code==='40001'?'oauth_state_or_connection_changed':e.code==='54000'?'authorization_rate_limit':['22023','22P02'].includes(e.code)?'invalid_request':'oauth_operation_failed'},e.code==='42501'?403:e.code==='40001'?409:e.code==='54000'?429:['22023','22P02'].includes(e.code)?400:500);
 return async(req:Request)=>{
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
  const url=new URL(req.url),callback=url.pathname.endsWith('/shopify-auth/callback');
  if(req.method==='GET'&&!callback)return reply({error:'authenticated_install_required'},401);
  if(!['GET','POST'].includes(req.method)||req.method==='POST'&&callback)return reply({error:'method_not_allowed'},405);
  try{
   let body:any,identity:any;
   if(req.method==='POST'){
    const auth=req.headers.get('Authorization')??'';if(!/^Bearer \S+$/i.test(auth))return reply({error:'unauthorized'},401);
    const caller=createClient(env('SUPABASE_URL'),env('SUPABASE_ANON_KEY'),{global:{headers:{Authorization:auth}},auth:{persistSession:false,autoRefreshToken:false}});
    identity=await caller.auth.getUser();if(identity.error||!identity.data?.user||identity.data.user.is_anonymous)return reply({error:'unauthorized'},401);
    let raw;try{raw=await boundedText(req,16384);}catch{return reply({error:'body_too_large'},413);}
    try{body=JSON.parse(raw);}catch{return reply({error:'invalid_json'},400);}
    if(!body||typeof body!=='object'||Array.isArray(body)||!['authorize','complete'].includes(body.action)||!uuid.test(body.connection_id??'')||Object.keys(body).some(k=>!(body.action==='authorize'?['action','connection_id','shop','return_url','draft_orders']:['action','connection_id','callback_query']).includes(k)))return reply({error:'invalid_request'},400);
    if(body.action==='authorize'&&Object.hasOwn(body,'draft_orders')&&typeof body.draft_orders!=='boolean')return reply({error:'invalid_request'},400);
   }
   const runtime=await loadEnvironment(env,fetchImpl),client=runtime('SHOPIFY_API_KEY'),secret=runtime('SHOPIFY_API_SECRET'),redirect=env('SUPABASE_URL')+'/functions/v1/shopify-auth/callback';
   if(!/^[A-Za-z0-9_-]{8,128}$/.test(client??'')||!secret||runtime('SHOPIFY_REDIRECT_URI')!==redirect)return reply({error:'destination_shopify_registration_required'},503);
   const service=createClient(env('SUPABASE_URL'),env('SUPABASE_SERVICE_ROLE_KEY'),{auth:{persistSession:false,autoRefreshToken:false}});
   if(req.method==='POST'&&body.action==='authorize'){
    const shop=typeof body.shop==='string'?body.shop.toLowerCase():'';if(!shopPattern.test(shop))return reply({error:'invalid_shop'},400);
    let returnUrl;try{returnUrl=approvedReturn(body.return_url,runtime('SHOPIFY_RETURN_ORIGINS'));}catch{return reply({error:'return_origin_not_approved'},400);}
    const scopes=body.draft_orders===true?DRAFT_SCOPES:SCOPES;
    const state=Array.from(crypto.getRandomValues(new Uint8Array(32)),x=>x.toString(16).padStart(2,'0')).join('');
    const begun=await service.rpc('aiq_shopify_oauth_begin',{p_native:identity.data.user.id,p_body:{connection_id:body.connection_id,shop,state_hash:await stateHash(state),client_id:client,redirect_uri:redirect,return_url:returnUrl,scopes,draft_orders:body.draft_orders===true}});if(begun.error)return failure(begun.error);if(begun.data?.ok!==true)return reply({error:'oauth_operation_failed'},500);
    return reply({ok:true,requested_scopes:scopes.split(','),draft_order_permission_requested:body.draft_orders===true,draft_creation_enabled:false,authorization_url:`https://${shop}/admin/oauth/authorize?`+new URLSearchParams({client_id:client!,scope:scopes,redirect_uri:redirect,state})});
   }
   const query=req.method==='GET'?url.search.slice(1):body.callback_query;
   let signed;try{if(typeof query!=='string')throw Error();signed=await verifyCallback(query,secret);}catch{return reply({error:'invalid_shopify_callback'},403);}
   const hash=await stateHash(signed.state);
   // Load without consuming first: validate binding/configuration before a claim.
   const context=await service.rpc('aiq_shopify_oauth_context',{p_hash:hash,p_native:null,p_claim:false});if(context.error)return failure(context.error);const ctx=context.data;
   if(!ctx||ctx.shop!==signed.shop||ctx.client_id!==client||ctx.redirect_uri!==redirect||![SCOPES,DRAFT_SCOPES].includes(ctx.scopes))return reply({error:'oauth_configuration_or_shop_changed'},409);
   let returnUrl;try{returnUrl=approvedReturn(ctx.return_url,runtime('SHOPIFY_RETURN_ORIGINS'));}catch{return reply({error:'return_origin_not_approved'},400);}
   if(req.method==='GET'){
    // No token exchange during anonymous callback. The initiating native user must complete it.
    const target=new URL(returnUrl);target.searchParams.set('shopify_callback',query);
    return new Response(null,{status:303,headers:{Location:target.toString(),'Cache-Control':'no-store','Referrer-Policy':'no-referrer'}});
   }
   if(ctx.connection_id!==body.connection_id)return reply({error:'connection_access_denied'},403);
   const claimed=await service.rpc('aiq_shopify_oauth_context',{p_hash:hash,p_native:identity.data.user.id,p_claim:true});if(claimed.error)return failure(claimed.error);
   if(JSON.stringify(claimed.data)!==JSON.stringify(ctx))return reply({error:'oauth_configuration_changed'},409);
   try{
    const response=await fetchImpl(`https://${signed.shop}/admin/oauth/access_token`,{method:'POST',redirect:'error',headers:{'Content-Type':'application/x-www-form-urlencoded',Accept:'application/json'},body:new URLSearchParams({client_id:client!,client_secret:secret,code:signed.code,expiring:'1'}),signal:AbortSignal.timeout(15000)});
    if(!response.ok){await response.body?.cancel();throw Error('token_exchange_failed');}
    const tokens=JSON.parse(await boundedText(response,40000));
    if(typeof tokens.access_token!=='string'||!tokens.access_token||tokens.access_token.length>16000||typeof tokens.refresh_token!=='string'||!tokens.refresh_token||tokens.refresh_token.length>16000||typeof tokens.scope!=='string'||tokens.scope.length>2000||!/^[a-z_]+(,[a-z_]+)*$/.test(tokens.scope)||!Number.isInteger(tokens.expires_in)||tokens.expires_in<1||tokens.expires_in>31536000||!Number.isInteger(tokens.refresh_token_expires_in)||tokens.refresh_token_expires_in<1||tokens.refresh_token_expires_in>31536000)throw Error('invalid_token_response');
    const granted=new Set(tokens.scope.split(','));for(const scope of ctx.scopes.split(',')){if(!granted.has(scope)&&!(scope.startsWith('read_')&&granted.has('write_'+scope.slice(5))))throw Error('missing_scope');}
    const credential={shop:signed.shop,access_token:tokens.access_token,refresh_token:tokens.refresh_token,scope:tokens.scope,obtained_at:new Date().toISOString(),expires_at:new Date(Date.now()+tokens.expires_in*1000).toISOString(),refresh_expires_at:new Date(Date.now()+tokens.refresh_token_expires_in*1000).toISOString()};
    const saved=await service.rpc('aiq_shopify_oauth_finish',{p_hash:hash,p_native:identity.data.user.id,p_credential:credential});if(saved.error)return failure(saved.error);if(saved.data?.ok!==true)return reply({error:'oauth_operation_failed'},500);return reply(saved.data);
   }catch{return reply({error:'shopify_token_exchange_failed'},502);}
  }catch{return reply({error:'shopify_oauth_failed'},500);}
 };
}
