const headers={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS','Content-Type':'application/json','Cache-Control':'no-store'};
export function createHandler({createClient,env}:{createClient:any;env:(n:string)=>string|undefined}){
 const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers});
 return async(req:Request)=>{
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers});if(req.method!=='POST')return reply({error:'method_not_allowed'},405);
  const auth=req.headers.get('Authorization')??'';if(!/^Bearer \S+$/i.test(auth))return reply({error:'unauthorized'},401);
  try{
   const user=createClient(env('SUPABASE_URL'),env('SUPABASE_ANON_KEY'),{global:{headers:{Authorization:auth}},auth:{persistSession:false,autoRefreshToken:false}});
   const identity=await user.auth.getUser();if(identity.error||!identity.data?.user||identity.data.user.is_anonymous)return reply({error:'unauthorized'},401);
   const raw=await req.text();if(new TextEncoder().encode(raw).length>8192)return reply({error:'body_too_large'},413);
   let body;try{body=JSON.parse(raw);}catch{return reply({error:'invalid_json'},400);}
   if(!body||typeof body!=='object'||Array.isArray(body))return reply({error:'invalid_body'},400);
   const result=await user.rpc('tj_epass_performance_bridge',{p_body:body});
   if(result.error){const status=({'42501':403,'40001':409,'22023':400,'22P02':400,'22007':400,'22008':400} as Record<string,number>)[result.error.code]??500;return reply({error:status===403?'organization_access_denied':status===409?'connection_not_ready':status===400?'invalid_record':'bridge_operation_failed'},status);}
   return reply(result.data,result.data?.ok===false?207:200);
  }catch{return reply({error:'bridge_operation_failed'},500);}
 };
}
