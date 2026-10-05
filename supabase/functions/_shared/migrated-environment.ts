// Only migrated functions load this encrypted configuration. Existing US workers
// continue using their original managed environment and are not changed.
let cached:Record<string,string>={};let cachedAt=0;
export async function migratedEnvironment(env:(name:string)=>string|undefined,fetchImpl:typeof fetch=fetch){
 const url=env('SUPABASE_URL'),service=env('SUPABASE_SERVICE_ROLE_KEY');
 if(!url||!service)return env;
 if(Date.now()-cachedAt>60000){
  const r=await fetchImpl(url+'/rest/v1/rpc/aiq_migrated_runtime_environment',{method:'POST',headers:{'Content-Type':'application/json',apikey:service,Authorization:'Bearer '+service},body:'{}',signal:AbortSignal.timeout(15000)});
  if(!r.ok)throw new Error('migrated_runtime_configuration_unavailable');
  const values=await r.json();
  if(!values||typeof values!=='object'||Array.isArray(values)||Object.entries(values).some(([name,value])=>name.startsWith('SUPABASE_')||typeof value!=='string'))throw new Error('invalid_migrated_runtime_configuration');
  cached=values;cachedAt=Date.now();
 }
 return (name:string)=>name.startsWith('SUPABASE_')?env(name):cached[name]??env(name);
}
