import assert from 'node:assert/strict';
import {createHandler} from '../../supabase/functions/connector-ingest/handler.ts';
let valid=true,anonymous=false,error=null,output={ok:true,deduped:false,http_status:201},calls=0;
const handler=createHandler({env:n=>n==='SUPABASE_ANON_KEY'?'anon':'https://us.test',createClient:(url,key,options)=>{assert.equal(key,'anon');assert.equal(options.global.headers.Authorization,'Bearer caller');return {auth:{getUser:async()=>({data:{user:valid?{id:'native',is_anonymous:anonymous}:null}})},rpc:async(name,args)=>{calls++;assert.equal(name,'tj_connector_ingest');assert(args.p_body);return {data:output,error};}};}});
const req=(body={connection_id:'id',payload:{name:'synthetic'}})=>new Request('https://edge.test',{method:'POST',headers:{Authorization:'Bearer caller'},body:JSON.stringify(body)});
assert.equal((await handler(new Request('https://edge.test',{method:'OPTIONS'}))).status,204);assert.equal((await handler(new Request('https://edge.test'))).status,405);assert.equal((await handler(new Request('https://edge.test',{method:'POST'}))).status,401);
valid=false;assert.equal((await handler(req())).status,401);valid=true;anonymous=true;assert.equal((await handler(req())).status,401);anonymous=false;
for(const body of [null,[]])assert.equal((await handler(req(body))).status,400);assert.equal((await handler(req({payload:'x'.repeat(262145)}))).status,413);assert.equal(calls,0);
for(const [code,status] of [['42501',403],['40001',409],['22023',400],['22P02',400],['22007',400],['XX000',500]]){error={code,message:'private diagnostic'};const r=await handler(req());assert.equal(r.status,status);assert(!JSON.stringify(await r.json()).includes('diagnostic'));}error=null;
for(const status of [201,422,500,503]){output={ok:status===201,http_status:status};const r=await handler(req());assert.equal(r.status,status);assert.equal((await r.json()).http_status,undefined);}
output={ok:true,deduped:true};assert.equal((await handler(req())).status,200);
console.log('Connector ingest handler passed: native session, anonymous denial, caller-only broker, bounded input, sanitized auth/date/database errors, ingestion/quarantine/dedupe response status contracts.');
