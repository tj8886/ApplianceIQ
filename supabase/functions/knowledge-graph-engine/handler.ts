const CORS={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
export function createHandler({env,fetchImpl=fetch}:{env:(name:string)=>string|undefined;fetchImpl?:typeof fetch}) {
 return async(req:Request)=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:CORS});
  if(req.method!=="POST")return reply({ok:false,error:"method_not_allowed"},405);
  const auth=req.headers.get("Authorization")??"";
  if(!auth.startsWith("Bearer "))return reply({ok:false,error:"authentication_required"},401);
  let body:any;try{body=await req.json();if(!body||typeof body!=="object"||Array.isArray(body))throw new Error("body");}catch{return reply({ok:false,error:"invalid_json"},400);}
  const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if(typeof body.organization_id!=="string"||!uuid.test(body.organization_id))return reply({ok:false,error:"invalid_organization_id"},400);
  const ids=body.product_ids??[],models=body.models??[],query=body.query??"",limit=body.limit??100;
  if(!Array.isArray(ids)||ids.length>25||ids.some(id=>typeof id!=="string"||!uuid.test(id))||!Array.isArray(models)||models.length>25||models.some(m=>typeof m!=="string"||m.length>120)||typeof query!=="string"||query.length>100||!Number.isInteger(limit)||limit<1||limit>250)return reply({ok:false,error:"invalid_graph_query"},400);
  const url=env("SUPABASE_URL")??"",headers={Authorization:auth,apikey:env("SUPABASE_ANON_KEY")??"","Content-Type":"application/json"};
  try{
   const user=await fetchImpl(`${url}/auth/v1/user`,{headers,signal:AbortSignal.timeout(20000)});
   if(!user.ok)return reply({ok:false,error:"invalid_session"},401);
   const sync=body.sync===true;
   const rpc=sync?"tj_sync_product_graph":"tj_product_graph_lookup";
   const payload=sync?{p_org:body.organization_id}:{p_org:body.organization_id,p_product_ids:ids,p_models:models,p_query:query,p_limit:limit};
   const r=await fetchImpl(`${url}/rest/v1/rpc/${rpc}`,{method:"POST",headers,body:JSON.stringify(payload),signal:AbortSignal.timeout(20000)});
   const data=await r.json();
   if(!r.ok)return reply({ok:false,error:sync?"graph_sync_failed":"graph_lookup_failed"},data.code==="42501"?403:500);
   return reply(sync?{ok:true,mode:"sync",result:data}:data);
  }catch{return reply({ok:false,error:"graph_workflow_unavailable"},502);}
 };
}
function reply(body:unknown,status=200){return new Response(JSON.stringify(body),{status,headers:{...CORS,"Content-Type":"application/json"}});}
