const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, content-type, x-client-info, apikey','Access-Control-Allow-Methods':'POST, OPTIONS','Content-Type':'application/json','Cache-Control':'no-store'};
const json=(b:unknown,status=200)=>new Response(JSON.stringify(b),{status,headers:cors});
export function createHandler({createClient,env}:{createClient:any;env:any}){
 return async(req:Request)=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:cors});if(req.method!=='POST')return json({ok:false,error:'method_not_allowed'},405);
  const auth=req.headers.get('Authorization')??'';if(!/^Bearer \S+$/i.test(auth))return json({ok:false,error:'not_authenticated'},401);
  try{
   const caller=createClient(env('SUPABASE_URL'),env('SUPABASE_ANON_KEY'),{global:{headers:{Authorization:auth}}});const {data,error}=await caller.auth.getUser();if(error||!data?.user||data.user.is_anonymous)return json({ok:false,error:'not_authenticated'},401);
   const raw=await req.text();if(new TextEncoder().encode(raw).length>4096)return json({ok:false,error:'body_too_large'},413);let body:any;try{body=JSON.parse(raw);}catch{return json({ok:false,error:'bad_json'},400);}
   if(body?.action!=='create_admin'||typeof body.email!=='string'||(body.full_name!==undefined&&typeof body.full_name!=='string'))return json({ok:false,error:'invalid_request'},400);
   const email=body.email.trim().toLowerCase(),full_name=(body.full_name??'').trim();if(email.length>254||!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)||full_name.length>120)return json({ok:false,error:'invalid_request'},400);
   const {data:intent,error:denied}=await caller.rpc('tj_prepare_admin_provision',{p_email:email,p_full_name:full_name});if(denied)return json({ok:false,error:denied.code==='42501'?'forbidden':denied.code==='40001'?'identity_review_required':denied.code==='54000'?'rate_limited':'invalid_request'},denied.code==='42501'?403:denied.code==='40001'?409:denied.code==='54000'?429:400);
   const service=createClient(env('SUPABASE_URL'),env('SUPABASE_SERVICE_ROLE_KEY'),{auth:{persistSession:false,autoRefreshToken:false}});
   let user_id=intent.existing_user_id,password:string|null=null,created=false;
   if(!user_id){password=Array.from(crypto.getRandomValues(new Uint8Array(24))).map(x=>x.toString(16).padStart(2,'0')).join('')+'Aa!';
    const {data:newUser,error:createFailure}=await service.auth.admin.createUser({email,password,email_confirm:true,user_metadata:{full_name}});if(createFailure||!newUser?.user?.id)return json({ok:false,error:'user_create_failed'},409);user_id=newUser.user.id;created=true;
   }
   const {data:result,error:grantFailure}=await service.rpc('aiq_finish_admin_provision',{p_intent:intent.intent_id,p_native:user_id});
   if(grantFailure||!result?.ok)return json({ok:false,error:created?'account_created_grant_incomplete':'grant_failed'},409);
   return json({ok:true,created_account:created,user_id,temp_password:password});
  }catch{return json({ok:false,error:'admin_provision_failed'},500);}
 };
}
