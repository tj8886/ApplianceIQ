const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, content-type, x-client-info, apikey','Access-Control-Allow-Methods':'POST, OPTIONS','Content-Type':'application/json'};
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:cors});
export function createHandler({createClient,env}:{createClient:any;env:(n:string)=>string|undefined}){
 return async(req:Request)=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:cors});if(req.method!=='POST')return json({error:'method_not_allowed'},405);
  const auth=req.headers.get('Authorization')??'';if(!/^Bearer \S+$/i.test(auth))return json({error:'auth_required'},401);
  try{
   const client=createClient(env('SUPABASE_URL'),env('SUPABASE_ANON_KEY'),{global:{headers:{Authorization:auth}}});const {data,error}=await client.auth.getUser();if(error||!data?.user||data.user.is_anonymous)return json({error:'auth_required'},401);
   const raw=await req.text();if(new TextEncoder().encode(raw).length>2048)return json({error:'body_too_large'},413);let body:any;try{body=JSON.parse(raw);}catch{return json({error:'invalid_json'},400);}
   if(!body||typeof body.organization_id!=='string'||!/^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(body.organization_id))return json({error:'organization_id_required'},400);
   const {data:result,error:failure}=await client.rpc('tj_run_crm_outreach_tasks',{p_org:body.organization_id});if(failure)return json({error:failure.code==='42501'?'access_denied':'crm_housekeeping_failed'},failure.code==='42501'?403:500);return json(result);
  }catch{return json({error:'crm_housekeeping_failed'},500);}
 };
}
