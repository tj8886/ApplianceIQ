import {previewOrder} from './normalize.js';
const headers={'Content-Type':'application/json','Cache-Control':'no-store','Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS'};
export function createHandler({createClient,env}){
 const reply=(body,status=200)=>new Response(JSON.stringify(body),{status,headers});
 return async req=>{
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
  if(req.method!=='POST')return reply({error:'method_not_allowed'},405);
  const auth=req.headers.get('Authorization')??'';if(!/^Bearer \S+$/i.test(auth))return reply({error:'unauthorized'},401);
  try{
   if(env('SUPABASE_URL')!=='https://jdxslqmgjsuzoisuhvlc.supabase.co')return reply({error:'destination_not_configured'},503);
   const caller=createClient(env('SUPABASE_URL'),env('SUPABASE_ANON_KEY'),{global:{headers:{Authorization:auth}},auth:{persistSession:false,autoRefreshToken:false}});
   const identity=await caller.auth.getUser();if(identity.error||!identity.data?.user||identity.data.user.is_anonymous)return reply({error:'unauthorized'},401);
   const reader=req.body?.getReader();let size=0;const chunks=[];
   if(reader){try{for(;;){const part=await reader.read();if(part.done)break;size+=part.value.length;if(size>262144){await reader.cancel();return reply({error:'body_too_large'},413);}chunks.push(part.value);}}finally{reader.releaseLock();}}
   const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
   let body;try{body=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));}catch{return reply({error:'invalid_json'},400);}
   if(!body||typeof body!=='object'||Array.isArray(body)||Object.keys(body).some(k=>!['action','connection_id','order'].includes(k))||typeof body.connection_id!=='string'||!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(body.connection_id))return reply({error:'invalid_request'},400);
   const scoped=await caller.rpc('tj_shopify_initial_sync',{p_body:{connection_id:body.connection_id,action:'status'}});
   if(scoped.error)return reply({error:scoped.error.code==='42501'?'connection_access_denied':'connection_validation_failed'},scoped.error.code==='42501'?403:400);
   if(scoped.data?.ok!==true||scoped.data.connection_id!==body.connection_id||scoped.data.preflight_only!==true)return reply({error:'connection_validation_failed'},503);
   if(body.action!=='preview')return reply({error:'shopify_performance_reconciliation_required',executed:false,records_written:0},409);
   let preview;try{preview=previewOrder(body.order);}catch{return reply({error:'invalid_or_unreconciled_order',executed:false},422);}
   return reply({ok:true,connection_id:body.connection_id,preview_only:true,provider_verified:false,executed:false,records_written:0,refund_processing_ready:false,preview});
  }catch{return reply({error:'bridge_operation_failed',executed:false},503);}
 };
}
