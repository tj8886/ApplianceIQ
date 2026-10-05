import assert from 'node:assert/strict';
import {createHandler} from '../../supabase/functions/connector-runtime/handler.ts';
let authenticated=true,calls=0,error=null;
const createClient=(url,key,opts)=>{assert.equal(key,'anon');assert.equal(opts.global.headers.Authorization,'Bearer native');return {auth:{getUser:async()=>({data:{user:authenticated?{id:'native'}:null}})},rpc:async(name,args)=>{calls++;assert.equal(name,'tj_connector_runtime');return {data:{action:args.p_body.action??'catalog'},error};}};};
const env=n=>({SUPABASE_URL:'https://us.test',SUPABASE_ANON_KEY:'anon'}[n]);const handler=createHandler({createClient,env});
const request=(body,method='POST')=>new Request('https://edge.test',{method,headers:{Authorization:'Bearer native'},...(method==='POST'?{body}: {})});
assert.equal((await handler(new Request('https://edge.test',{method:'POST'}))).status,401);
authenticated=false;assert.equal((await handler(request('{}'))).status,401);assert.equal(calls,0);authenticated=true;
assert.equal((await handler(request('[]'))).status,400);assert.equal((await handler(request('x'.repeat(16385)))).status,413);assert.equal((await handler(request('{'))).status,400);
assert.equal((await handler(request('{"action":"worker"}'))).status,400);assert.equal(calls,0);
assert.equal((await handler(request('{}','GET'))).status,200);
assert.equal((await handler(request('{"action":"prepare_connection"}'))).status,201);
for(const [code,status] of [['42501',403],['P0002',404],['22023',400],['40001',409],['XX000',500]]){error={code,message:'scoped_failure'};const r=await handler(request('{}'));assert.equal(r.status,status);if(status===500)assert.equal((await r.json()).error,'connector_operation_failed');}
console.log('Connector runtime handlers passed native login, caller-only RPC, body/action bounds, response shapes and scoped error handling.');
