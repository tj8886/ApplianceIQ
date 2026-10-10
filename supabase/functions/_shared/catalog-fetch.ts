const CORS = {'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS','Content-Type':'application/json'};
export const CATALOG_HOSTS: Record<string,string[]> = {
 'cas-fetch':['canadianappliance.ca'],
 'trail-fetch':['trailappliances.com'],
 'apex-fetch':['bestbrandappliance.ca','premiumappliances.ca','quanappliances.com'],
 'shopify-proxy':['appliancecanada.com','dufresne.ca','futureappliances.ca','futuresappliances.ca','leons.ca','merrithewsappliance.com','secondshop.ca','taappliance.com','thebrick.com','avantiproducts.com','blombergappliances.com','elmirastoveworks.com','empava.com','faberonline.com','forno.ca','kalamazoogourmet.com','thorkitchen.com','uniqueappliances.com','zlinekitchen.com'],
};
export function allowedCatalogUrl(value: unknown, kind:string): URL {
 if(typeof value!=='string'||value.length>2048)throw new Error('url_not_allowed');
 const u=new URL(value);
 if(u.protocol!=='https:'||u.port&&u.port!=='443'||u.username||u.password||u.hash||!CATALOG_HOSTS[kind]?.some(h=>u.hostname===h||u.hostname==='www.'+h))throw new Error('url_not_allowed');
 if(kind==='shopify-proxy'&&!/^\/(?:products\.json|products\/[^/]+\.json|search\/suggest\.json)$/.test(u.pathname))throw new Error('url_not_allowed');
 return u;
}
async function boundedText(response:Response):Promise<string> {
 const max=2*1024*1024;
 if(Number(response.headers.get('content-length'))>max){await response.body?.cancel();throw new Error('upstream_response_too_large');}
 const reader=response.body?.getReader();if(!reader)return '';
 const chunks:Uint8Array[]=[];let size=0;
 try{for(;;){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>max)throw new Error('upstream_response_too_large');chunks.push(value);}}
 catch(e){await reader.cancel();throw e;}
 const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}return new TextDecoder().decode(bytes);
}
export function createCatalogFetchHandler({kind,createClient,env,fetchImpl=fetch}:{kind:string;createClient:any;env:(name:string)=>string|undefined;fetchImpl?:typeof fetch}) {
 const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:CORS});
 return async(req:Request)=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:CORS});
  if(req.method!=='POST')return reply({error:'method_not_allowed'},405);
  const auth=req.headers.get('Authorization')??'';if(!auth.startsWith('Bearer '))return reply({error:'authentication_required'},401);
  try{
   const user=createClient(env('SUPABASE_URL'),env('SUPABASE_ANON_KEY'),{global:{headers:{Authorization:auth}},auth:{persistSession:false,autoRefreshToken:false}});
   const identity=await user.auth.getUser();if(identity.error||!identity.data?.user)return reply({error:'invalid_session'},401);
   const context=await user.rpc('tj_runtime_my_platform_context');if(context.error||!context.data?.organization_id)return reply({error:'active_mapped_organization_required'},403);
   const raw=await req.text();if(raw.length>8192)return reply({error:'request_too_large'},413);
   let body;try{body=JSON.parse(raw);}catch{return reply({error:'invalid_json'},400);}
   if(!body||typeof body!=='object'||Array.isArray(body))return reply({error:'invalid_json'},400);
   if(body.organization_id&&body.organization_id!==context.data.organization_id)return reply({error:'organization_access_denied'},403);
   const batch=!body.url&&Array.isArray(body.urls)&&['cas-fetch','trail-fetch'].includes(kind);
   const urls=batch?body.urls:[body.url];if(!urls.length||urls.length>5)return reply({error:'provide_one_to_five_urls'},400);
   try{urls.forEach((u:unknown)=>allowedCatalogUrl(u,kind));}catch{return reply({error:'url_not_allowed'},403);}
   const results=[];
   for(const original of urls){
    let url=allowedCatalogUrl(original,kind);let response:Response|undefined;
    const signal=AbortSignal.timeout(15000);
    for(let hop=0;hop<=3;hop++){
     response=await fetchImpl(url.toString(),{redirect:'manual',signal,headers:{'User-Agent':'ApplianceIQ/1.0 (catalog retrieval)','Accept':kind==='shopify-proxy'?'application/json':'text/html,application/xml;q=0.9'}});
     if(![301,302,303,307,308].includes(response.status))break;
     const location=response.headers.get('location');await response.body?.cancel();
     if(!location||hop===3)return reply({error:'upstream_redirect_rejected'},502);
     try{url=allowedCatalogUrl(new URL(location,url).toString(),kind);}catch{return reply({error:'upstream_redirect_rejected'},502);}
    }
    if(!response)return reply({error:'upstream_fetch_failed'},502);
    if(!response.ok){await response.body?.cancel();if(kind==='shopify-proxy')return reply({error:'upstream_fetch_failed',status:response.status},502);results.push({url:original,html:null,ok:false,status:response.status});continue;}
    const text=await boundedText(response);
    if(kind==='shopify-proxy'){try{return reply(JSON.parse(text));}catch{return reply({error:'invalid_upstream_json'},502);}}
    const blocked=kind==='cas-fetch'&&((text.includes('Just a moment')&&text.includes('challenge-platform'))||text.includes('Attention Required!')||text.includes('cf-error-details'));
    results.push({url:original,html:blocked?null:text,ok:!blocked&&!!text,...(kind==='cas-fetch'?{blocked}:{})});
   }
   return reply(batch?{results}:results[0]);
  }catch{return reply({error:'catalog_fetch_failed'},502);}
 };
}
