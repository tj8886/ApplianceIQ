const headers={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS','Content-Type':'application/json'};
export function createHandler({createClient,env}:{createClient:any;env:(name:string)=>string|undefined}){
 const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers});
 return async(req:Request)=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers});
  if(req.method!=='POST')return reply({ok:false,detail:'method_not_allowed'},405);
  const auth=req.headers.get('Authorization')??'';if(!auth.startsWith('Bearer '))return reply({ok:false,detail:'authentication_required'},401);
  try{
   const user=createClient(env('SUPABASE_URL'),env('SUPABASE_ANON_KEY'),{global:{headers:{Authorization:auth}},auth:{persistSession:false,autoRefreshToken:false}});
   const identity=await user.auth.getUser();if(identity.error||!identity.data?.user)return reply({ok:false,detail:'invalid_session'},401);
   const raw=await req.text();if(raw.length>65536)return reply({ok:false,detail:'request_too_large'},413);
   let body;try{body=JSON.parse(raw);}catch{return reply({ok:false,detail:'invalid_json'},400);}
   if(!body||typeof body!=='object'||Array.isArray(body))return reply({ok:false,detail:'invalid_json'},400);
   const signals=Array.isArray(body.signals)?body.signals:[body];
   if(!signals.length||signals.length>20)return reply({ok:false,detail:'invalid_batch'},400);
   const {data,error}=await user.rpc('tj_submit_ai_feedback',{p_signals:signals});
   if(error)return reply({ok:false,detail:error.code==='42501'?'feedback_access_denied':'feedback_rejected'},error.code==='42501'?403:['22023','22P02','23514'].includes(error.code)?400:500);
   return reply(data);
  }catch{return reply({ok:false,detail:'feedback_failed'},500);}
 };
}
