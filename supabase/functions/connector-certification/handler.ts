const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'GET, POST, OPTIONS','Content-Type':'application/json'};
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:cors});
export function createHandler({createClient,env}:{createClient:any;env:(n:string)=>string|undefined}){
 return async(req:Request)=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:cors});
  if(!['POST'].includes(req.method))return json({error:'method_not_allowed'},405);
  const auth=req.headers.get('Authorization')??'';if(!/^Bearer \S+$/i.test(auth))return json({error:'unauthorized'},401);
  try{
   const client=createClient(env('SUPABASE_URL'),env('SUPABASE_ANON_KEY'),{global:{headers:{Authorization:auth}}});
   const {data,error}=await client.auth.getUser();if(error||!data?.user||data.user.is_anonymous)return json({error:'unauthorized'},401);
   let body:Record<string,unknown>={};if(req.method==='POST'){
    const raw=await req.text();if(new TextEncoder().encode(raw).length>16384)return json({error:'body_too_large'},413);
    try{body=JSON.parse(raw);}catch{return json({error:'invalid_json'},400);}
    if(!body||Array.isArray(body)||typeof body!=='object')return json({error:'invalid_body'},400);
   }
   const action=String(body.action??'summary');if(!['summary','evaluate','run_automation','evidence','set_check'].includes(action))return json({error:'unknown_action'},400);
   const {data:result,error:failure}=await client.rpc('tj_connector_certification',{p_body:body});
   if(failure){const status=({42501:403,P0002:404,22023:400,'22P02':400,'40001':409,'23505':409} as Record<string,number>)[failure.code]??500;return json({error:status===500?'connector_operation_failed':failure.code==='23505'?'connection_already_exists':failure.message},status);}
   return json(result,200);
  }catch{return json({error:'connector_operation_failed'},500);}
 };
}
