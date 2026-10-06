const headers={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS','Content-Type':'application/json','Cache-Control':'no-store'};
export function createHandler({createClient,env}:{createClient:any;env:(name:string)=>string|undefined}){
 const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers});
 return async(req:Request)=>{
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
  if(req.method!=='POST')return reply({error:'method_not_allowed'},405);
  const auth=req.headers.get('Authorization')??'';if(!/^Bearer \S+$/i.test(auth))return reply({error:'unauthorized'},401);
  try{
   const client=createClient(env('SUPABASE_URL'),env('SUPABASE_ANON_KEY'),{global:{headers:{Authorization:auth}},auth:{persistSession:false,autoRefreshToken:false}});
   const identity=await client.auth.getUser();if(identity.error||!identity.data?.user||identity.data.user.is_anonymous)return reply({error:'unauthorized'},401);
   const raw=await req.text();if(new TextEncoder().encode(raw).length>16384)return reply({error:'body_too_large'},413);
   let body;try{body=JSON.parse(raw);}catch{return reply({error:'invalid_json'},400);}
   if(!body||typeof body!=='object'||Array.isArray(body))return reply({error:'invalid_body'},400);
   if(!['status','auto_match','resolve_employee','resolve_location','reject','activate'].includes(body.action??'status'))return reply({error:'unknown_action'},400);
   if(typeof body.connection_id!=='string'||!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(body.connection_id))return reply({error:'connection_id_required'},400);
   const result=await client.rpc('tj_connector_onboarding',{p_body:body});
   if(result.error){const status=({42501:403,P0002:404,22023:400,'22P02':400,'40001':409,'23505':409,'54000':409} as Record<string,number>)[result.error.code]??500;
    return reply({error:status===500?'onboarding_operation_failed':result.error.code==='23505'?'employee_mapping_conflict':result.error.message},status);}
   if(result.data?.ok===false)return reply(result.data,409);
   return reply(result.data);
  }catch{return reply({error:'onboarding_operation_failed'},500);}
 };
}
