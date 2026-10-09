const headers={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS','Content-Type':'application/json','Cache-Control':'no-store'};
export function createHandler({createClient,env}:{createClient:any;env:(name:string)=>string|undefined}){
  const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers});
  return async(req:Request)=>{
    if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
    if(req.method!=='POST')return reply({error:'method_not_allowed'},405);
    const auth=req.headers.get('Authorization')??'';
    if(!/^Bearer \S+$/i.test(auth))return reply({error:'unauthorized'},401);
    try{
      const client=createClient(env('SUPABASE_URL'),env('SUPABASE_ANON_KEY'),{global:{headers:{Authorization:auth}},auth:{persistSession:false,autoRefreshToken:false}});
      const identity=await client.auth.getUser();
      if(identity.error||!identity.data?.user?.id||identity.data.user.is_anonymous)return reply({error:'unauthorized'},401);
      const reader=req.body?.getReader();let length=0;const chunks:Uint8Array[]=[];
      if(reader){for(;;){const {done,value}=await reader.read();if(done)break;length+=value.length;if(length>8192){await reader.cancel();return reply({error:'body_too_large'},413);}chunks.push(value);}}
      const bytes=new Uint8Array(length);let at=0;for(const part of chunks){bytes.set(part,at);at+=part.length;}
      let body;try{body=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));}catch{return reply({error:'invalid_json'},400);}
      if(!body||typeof body!=='object'||Array.isArray(body))return reply({error:'invalid_request'},400);
      const {data,error}=await client.rpc('tj_shopify_draft_order',{p_body:body});
      if(error){const forbidden=error.code==='42501',invalid=['22023','22P02','22003','54000'].includes(error.code);return reply({error:forbidden?'package_access_denied':invalid?'invalid_request':'operation_failed'},forbidden?403:invalid?400:500);}
      if(data?.ok===false)return reply(data,409);
      if(data?.ok!==true)return reply({error:'operation_failed'},500);
      return reply(data);
    }catch{return reply({error:'operation_failed'},500);}
  };
}
