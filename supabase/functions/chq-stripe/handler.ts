const headers={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS','Content-Type':'application/json','Cache-Control':'no-store'};
export function createHandler({createClient,env}:{createClient:any;env:(n:string)=>string|undefined}){
 const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers});
 return async(req:Request)=>{
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
  if(req.method!=='POST')return reply({error:'method_not_allowed'},405);
  const auth=req.headers.get('Authorization')??'';
  if(!/^Bearer \S+$/i.test(auth))return reply({error:'unauthorized'},401);
  try{
   const caller=createClient(env('SUPABASE_URL'),env('SUPABASE_ANON_KEY'),{global:{headers:{Authorization:auth}},auth:{persistSession:false,autoRefreshToken:false}});
   const identity=await caller.auth.getUser();
   if(identity.error||!identity.data?.user||identity.data.user.is_anonymous)return reply({error:'unauthorized'},401);
   const max=8192;
   if(Number(req.headers.get('content-length')??0)>max)return reply({error:'body_too_large'},413);
   const reader=req.body?.getReader();let size=0;const chunks:Uint8Array[]=[];
   if(reader){try{while(true){const part=await reader.read();if(part.done)break;size+=part.value.length;if(size>max){await reader.cancel();return reply({error:'body_too_large'},413);}chunks.push(part.value);}}finally{reader.releaseLock();}}
   const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
   let body;try{body=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));}catch{return reply({error:'invalid_json'},400);}
   if(!body||typeof body!=='object'||Array.isArray(body))return reply({error:'invalid_request'},400);
   const result=await caller.rpc('tj_chq_payment_preflight',{p_body:body});
   if(result.error){
    const code=result.error.code;
    return reply({error:code==='42501'?'payment_access_denied':['22023','22P02','22003','22007','22008','54000'].includes(code)?'invalid_request':['23502','23503','23505','23514'].includes(code)?'staging_constraint_failed':'operation_failed'},
     code==='42501'?403:['22023','22P02','22003','22007','22008','54000'].includes(code)?400:['23502','23503','23505','23514'].includes(code)?422:500);
   }
   if(result.data?.ok===false)return reply(result.data,409);
   if(result.data?.ok!==true)return reply({error:'operation_failed'},500);
   return reply(result.data);
  }catch{return reply({error:'operation_failed'},500);}
 };
}
