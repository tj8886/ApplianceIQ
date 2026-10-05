type Configuration={mode:'export'|'ingest';nonceHash:string;expiresAt:number;sourceUrl:string;destinationUrl:string;names:string[]};
export function createHandler(config:Configuration,{env,fetchImpl=fetch}:{env:(name:string)=>string|undefined;fetchImpl?:typeof fetch}){
 return async(req:Request)=>{
  if(Date.now()>config.expiresAt)return json({error:'gone'},410);
  if(req.method!=='POST')return json({error:'method_not_allowed'},405);
  const nonce=req.headers.get('x-migration-token')??'';
  if(!nonce || await hash(nonce)!==config.nonceHash)return json({error:'unauthorized'},401);
  const own=env('SUPABASE_URL')??'';
  if(own!==(config.mode==='export'?config.sourceUrl:config.destinationUrl))return json({error:'wrong_project'},403);
  try{
   const body=await req.json();if(!body||typeof body!=='object'||Array.isArray(body))return json({error:'invalid_body'},400);
   if(config.mode==='export'){
    if(typeof body.destination_token!=='string'||body.destination_token.length<32)return json({error:'invalid_destination_token'},400);
    const values:Record<string,string>={};const missing:string[]=[];
    for(const name of config.names){const v=env(name);if(v)values[name]=v.replaceAll(config.sourceUrl,config.destinationUrl);else missing.push(name);}
    const r=await fetchImpl(config.destinationUrl+'/functions/v1/consolidation-runtime-transfer',{method:'POST',headers:{'Content-Type':'application/json','x-migration-token':body.destination_token},body:JSON.stringify({values}),signal:AbortSignal.timeout(20000)});
    if(!r.ok)return json({error:'destination_transfer_failed'},502);
    const result=await r.json();
    for(const [name,value] of Object.entries(values)){if(result.hashes?.[name]!==await hash(value))return json({error:'transfer_verification_failed'},502);}
    return json({copied_names:Object.keys(values),verified_count:Object.keys(values).length,missing_names:missing});
   }
   const values=body.values;
   if(!values || typeof values!=='object'||Array.isArray(values)||Object.entries(values).some(([n,v])=>!config.names.includes(n)||typeof v!=='string'||!v||v.length>10000))return json({error:'invalid_environment'},400);
   const service=env('SUPABASE_SERVICE_ROLE_KEY')??'';
   const r=await fetchImpl(config.destinationUrl+'/rest/v1/rpc/aiq_ingest_migrated_runtime_environment',{method:'POST',headers:{'Content-Type':'application/json',apikey:service,Authorization:'Bearer '+service},body:JSON.stringify({p_values:values}),signal:AbortSignal.timeout(20000)});
   if(!r.ok)return json({error:'environment_storage_failed'},502);
   return json({hashes:await r.json()});
  }catch{return json({error:'transfer_failed'},502);}
 };
}
async function hash(text:string){return [...new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(text)))].map(b=>b.toString(16).padStart(2,'0')).join('');}
function json(data:unknown,status=200){return new Response(JSON.stringify(data),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});}
