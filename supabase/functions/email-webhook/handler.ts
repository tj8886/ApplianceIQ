const MAX_BODY=262144;
const types=new Set(['email.sent','email.delivered','email.delivery_delayed','email.opened','email.clicked','email.bounced','email.complained','email.failed','email.received']);
function decode(value:string){
 if(!/^[A-Za-z0-9+/_-]+={0,2}$/.test(value)||value.length>128)throw new Error('invalid_base64');
 const normalized=value.replace(/-/g,'+').replace(/_/g,'/').replace(/=+$/,'');
 const binary=atob(normalized.padEnd(Math.ceil(normalized.length/4)*4,'='));
 if(btoa(binary).replace(/=+$/,'')!==normalized)throw new Error('invalid_base64');
 return Uint8Array.from(binary,c=>c.charCodeAt(0));
}
export function createHandler({env,now=()=>Date.now()}:{env:(n:string)=>string|undefined;now?:()=>number}){
 const reply=(body:unknown,status:number)=>new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});
 return async(req:Request)=>{
  if(req.method!=='POST')return reply({error:'method_not_allowed'},405);
  const id=req.headers.get('svix-id')??'',timestamp=req.headers.get('svix-timestamp')??'',signatures=req.headers.get('svix-signature')??'';
  if(!/^[A-Za-z0-9_-]{1,256}$/.test(id)||!/^[1-9]\d{8,11}$/.test(timestamp)||!signatures||signatures.length>2048
   ||Math.abs(Math.floor(now()/1000)-Number(timestamp))>300)return reply({error:'invalid_webhook_signature'},401);
  const candidates=signatures.trim().split(/\s+/);if(candidates.length>8)return reply({error:'invalid_webhook_signature'},401);
  // A fresh destination endpoint secret is required; never adopt the Canada signing key.
  const secret=env('RESEND_US_WEBHOOK_SECRET');
  if(!secret?.startsWith('whsec_'))return reply({error:'webhook_destination_not_configured',processed:false},503);
  let key;try{const bytes=decode(secret.slice(6));if(bytes.length<16||bytes.length>64)throw new Error();key=await crypto.subtle.importKey('raw',bytes,{name:'HMAC',hash:'SHA-256'},false,['verify']);}
  catch{return reply({error:'webhook_destination_not_configured',processed:false},503);}
  try{
   const length=req.headers.get('content-length');
   if(length!==null&&(!/^\d+$/.test(length)||Number(length)>MAX_BODY))return reply({error:'body_too_large'},413);
   const reader=req.body?.getReader();let size=0;const chunks:Uint8Array[]=[];
   if(reader){try{while(true){const part=await reader.read();if(part.done)break;size+=part.value.length;if(size>MAX_BODY){await reader.cancel();return reply({error:'body_too_large'},413);}chunks.push(part.value);}}finally{reader.releaseLock();}}
   const body=new Uint8Array(size);let offset=0;for(const chunk of chunks){body.set(chunk,offset);offset+=chunk.length;}
   const prefix=new TextEncoder().encode(`${id}.${timestamp}.`),signed=new Uint8Array(prefix.length+size);signed.set(prefix);signed.set(body,prefix.length);
   let verified=false;
   for(const candidate of candidates){if(!candidate.startsWith('v1,'))continue;try{const bytes=decode(candidate.slice(3));if(bytes.length===32&&await crypto.subtle.verify('HMAC',key,bytes,signed)){verified=true;break;}}catch{/* Ignore malformed candidates; never log signatures or body. */}}
   if(!verified)return reply({error:'invalid_webhook_signature'},401);
   let payload;try{payload=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(body));}catch{return reply({error:'invalid_event_payload'},400);}
   if(!payload||typeof payload!=='object'||Array.isArray(payload)||!types.has(payload.type)||!payload.data||typeof payload.data!=='object'||Array.isArray(payload.data)
    ||typeof payload.data.email_id!=='string'||payload.data.email_id.length<1||payload.data.email_id.length>128)return reply({error:'unsupported_event_payload',processed:false},422);
   // Never acknowledge an event as consumed before durable, tenant-bound atomic processing exists.
   // No database client, email/thread/contact lookup, body storage or provider request is reachable.
   return reply({error:'email_webhook_destination_verification_required',processed:false,recorded:false,associated:false},503);
  }catch{return reply({error:'webhook_processing_unavailable',processed:false},503);}
 };
}
