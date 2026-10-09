export function createHandler({createClient,env,fetchImpl=fetch}:{createClient:any;env:(name:string)=>string|undefined;fetchImpl?:typeof fetch}){
 const headers={'Content-Type':'application/json','Cache-Control':'no-store','Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS'};
 const reply=(value:unknown,status=200)=>new Response(JSON.stringify(value),{status,headers});
 const failure=(error:any)=>reply({error:error.code==='42501'?'connection_access_denied':error.code==='55000'?'fresh_shopify_authorization_required':error.code==='40001'?'verification_context_changed':'verification_failed'},error.code==='42501'?403:['55000','40001'].includes(error.code)?409:500);
 return async(req:Request)=>{
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers});if(req.method!=='POST')return reply({error:'method_not_allowed'},405);
  const auth=req.headers.get('authorization')??'';if(!/^Bearer \S+$/i.test(auth))return reply({error:'unauthorized'},401);
  try{
   const url=env('SUPABASE_URL'),anon=env('SUPABASE_ANON_KEY'),key=env('SUPABASE_SERVICE_ROLE_KEY');
   if(url!=='https://jdxslqmgjsuzoisuhvlc.supabase.co'||!anon||!key)return reply({error:'runtime_unavailable'},503);
   const user=createClient(url,anon,{global:{headers:{Authorization:auth}},auth:{persistSession:false,autoRefreshToken:false}});
   const identity=await user.auth.getUser();if(identity.error||!identity.data?.user?.id||identity.data.user.is_anonymous)return reply({error:'unauthorized'},401);
   const reader=req.body?.getReader();let count=0;const chunks:Uint8Array[]=[];
   if(reader)for(;;){const {done,value}=await reader.read();if(done)break;count+=value.length;if(count>1024){await reader.cancel();return reply({error:'body_too_large'},413);}chunks.push(value);}
   const bytes=new Uint8Array(count);let offset=0;for(const part of chunks){bytes.set(part,offset);offset+=part.length;}
   let body;try{body=JSON.parse(new TextDecoder().decode(bytes));}catch{return reply({error:'invalid_json'},400);}
   if(!body||typeof body!=='object'||Array.isArray(body)||Object.keys(body).length!==1||typeof body.connection_id!=='string'||! /^[0-9a-f-]{36}$/i.test(body.connection_id))return reply({error:'invalid_request'},400);
   const service=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
   const begun=await service.rpc('aiq_shopify_verify_begin',{p_native:identity.data.user.id,p_connection:body.connection_id});if(begun.error)return failure(begun.error);
   const ctx=begun.data;
   if(!ctx||typeof ctx.shop!=='string'||! /^[a-z0-9][a-z0-9-]{0,62}\.myshopify\.com$/.test(ctx.shop)||typeof ctx.access_token!=='string'||!ctx.access_token||ctx.access_token.length>16000||typeof ctx.session_id!=='string')return reply({error:'invalid_verification_context'},500);
   let verified;
   try{
    const response=await fetchImpl(`https://${ctx.shop}/admin/api/2026-10/graphql.json`,{method:'POST',redirect:'error',headers:{'Content-Type':'application/json','X-Shopify-Access-Token':ctx.access_token},body:JSON.stringify({query:'query ApplianceIQConnectionVerification { shop { id myshopifyDomain currencyCode } currentAppInstallation { accessScopes { handle } } }'}),signal:AbortSignal.timeout(10000)});
    if(!response.ok)throw Error('provider_failure');
    const responseReader=response.body?.getReader();let size=0;const parts:Uint8Array[]=[];
    if(responseReader)for(;;){const {done,value}=await responseReader.read();if(done)break;size+=value.length;if(size>32768){await responseReader.cancel();throw Error('oversized_response');}parts.push(value);}
    const dataBytes=new Uint8Array(size);let at=0;for(const part of parts){dataBytes.set(part,at);at+=part.length;}
    const result=JSON.parse(new TextDecoder().decode(dataBytes)),shop=result?.data?.shop,scopes=result?.data?.currentAppInstallation?.accessScopes;
    if((result.errors!==undefined&&(!Array.isArray(result.errors)||result.errors.length))||!shop||shop.myshopifyDomain!==ctx.shop||typeof shop.id!=='string'||! /^gid:\/\/shopify\/Shop\/[1-9][0-9]{0,24}$/.test(shop.id)||typeof shop.currencyCode!=='string'||! /^[A-Z]{3}$/.test(shop.currencyCode)||!Array.isArray(scopes)||scopes.length>128||scopes.some(s=>!s||typeof s.handle!=='string'||! /^[a-z_]{1,100}$/.test(s.handle)))throw Error('invalid_provider_result');
    verified={shop_id:shop.id,shop:shop.myshopifyDomain,currency:shop.currencyCode,scopes:[...new Set(scopes.map(s=>s.handle))].sort()};
   }catch{return reply({error:'provider_verification_failed'},502);}
   const finished=await service.rpc('aiq_shopify_verify_finish',{p_native:identity.data.user.id,p_session:ctx.session_id,p_result:verified});if(finished.error)return failure(finished.error);
   if(finished.data?.ok!==true)return reply({error:'verification_failed'},500);
   return reply(finished.data);
  }catch{return reply({error:'verification_failed'},500);}
 };
}
