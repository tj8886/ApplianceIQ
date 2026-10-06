import assert from 'node:assert/strict';
import {parsePage,safePageUrl,runStep} from '../../supabase/functions/epass-sync/runner.ts';
import {createHandler} from '../../supabase/functions/epass-sync/handler.ts';
const endpoint='https://epass.example/api/invoices';
assert.equal(safePageUrl(endpoint,'?page=2'),endpoint+'?page=2');
for(const link of ['https://evil.example/api/invoices','https://epass.example/api/secrets','https://user:pass@epass.example/api/invoices','#hash','http://epass.example/api/invoices'])assert.throws(()=>safePageUrl(endpoint,link));
for(const payload of [{},null,{items:[],data:[]},{items:[null]},{items:[],next:{}},{items:[],next:'?a=1',nextLink:'?a=2'},{items:Array(101).fill({})}])assert.throws(()=>parsePage(payload));
for(const key of ['items','value','data','results'])assert.deepEqual(parsePage({[key]:[{id:1}]}).rows,[{id:1}]);
let saved=[],ingested=[],mode='page',contextError=null,origin='https://epass.example/api/invoices',lease='lease';
const cfg={base_url:'https://epass.example/api',endpoints:{invoices:'invoices'},api_key_header:'X-API-Key',api_secret_header:'X-API-Secret'};
let scope={job_id:'job',lease,version:'v1',phase:'fetch',resource:'invoices',next_url:null,configuration:cfg};
const service={rpc:async(name,args)=>{assert.equal(args.p_native_user,'native');assert.equal(args.p_lease,lease);if(name==='aiq_epass_sync_context')return {data:{...scope,credential:{api_key:'private-synthetic'},bridge_cursor:'A'},error:contextError};assert.equal(name,'aiq_epass_sync_finish');saved.push(args.p_result);return {data:{ok:true,done:false,job_id:'job'}};}};
const user={rpc:async(name,args)=>{if(name==='tj_epass_performance_bridge'){assert.equal(args.p_body.after_external_id,'A');return {data:{processed:2,failed:30,errors:[{error:'bounded'}],next_cursor:'Z'}};}assert.equal(name,'tj_connector_ingest');ingested.push(args.p_body);if(mode==='scope')return {error:{code:'42501'}};return {data:{ok:args.p_body.external_id!=='bad'}};}};
const step=()=>runStep({user,service,native:'native',body:{connection_id:'connection'},scope,endpoint,fetchImpl:async(url,opts)=>{assert.equal(url,origin);assert.equal(opts.redirect,'error');assert.equal(opts.headers['X-API-Key'],'private-synthetic');if(mode==='throw')throw Error('private-secret');return new Response(JSON.stringify({items:[{invoice_id:'zero',amount:0},{invoice_id:'bad'},{}],next:mode==='cycle'?endpoint:'?page=2'}),{headers:{'content-type':'application/json'}});}});
await step();assert.deepEqual(saved.at(-1),{kind:'page',processed:1,failed:2,next_url:endpoint+'?page=2',page_url:endpoint});assert.equal(ingested[0].payload.amount,0);assert.equal(ingested[0].sync_job_id,'job');
for(mode of ['throw','scope','cycle']){const r=await step();assert.equal(r.error.code,'502');assert.deepEqual(saved.at(-1),{kind:'retry'});}
contextError={code:'40001'};let count=ingested.length;assert.equal((await step()).error.code,'40001');assert.equal(ingested.length,count);contextError=null;
scope={...scope,phase:'bridge',resource:null};await step();assert.equal(saved.at(-1).failed,30);assert.equal(saved.at(-1).next_cursor,'Z');assert.equal(saved.at(-1).has_more,true);
let next=false,fetches=0;
const clients=(url,key,opts)=>key==='service'?{rpc:async(name,args)=>{
 if(name==='aiq_epass_sync_context')return {data:{...hScope,credential:{api_key:'private-synthetic'}}};
 assert.equal(name,'aiq_epass_sync_finish');assert.equal(args.p_result.processed,1);next=true;return {data:{ok:true,job_id:'job',done:false,status:'running'}};
}}:{auth:{getUser:async()=>({data:{user:{id:'native'}}})},rpc:async(name,args)=>{
 assert.equal(opts.global.headers.Authorization,'Bearer caller');if(name==='tj_epass_setup')return {data:next?{done:true,status:'success',job_id:'job'}:hScope};assert.equal(name,'tj_connector_ingest');return {data:{ok:true}};
}};
const hScope={job_id:'job',lease:'lease',version:'v1',phase:'fetch',resource:'invoices',next_url:null,configuration:cfg};
const handler=createHandler({createClient:clients,env:n=>({SUPABASE_URL:'https://us.test',SUPABASE_ANON_KEY:'anon',SUPABASE_SERVICE_ROLE_KEY:'service',EPASS_ALLOWED_ORIGINS:'["https://epass.example"]'}[n]),fetchImpl:async()=>{fetches++;return new Response('{"items":[{"invoice_id":"one"}]}',{headers:{'content-type':'application/json'}});}});
const request=()=>new Request('https://edge.test',{method:'POST',headers:{Authorization:'Bearer caller'},body:JSON.stringify({action:'sync',connection_id:'11111111-1111-4111-8111-111111111111'})});
assert.equal((await handler(request())).status,202);assert.equal((await handler(request())).status,200);assert.equal(fetches,1);
console.log('Resumable ePASS runner passed: strict bounded page shapes, same endpoint pagination, server-only credentials, scoped ingestion, cursor-preserving retries, scope rechecks and full bridge failure counts/cursors.');
