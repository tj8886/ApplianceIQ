import assert from 'node:assert/strict';
import {createHandler} from '../../supabase/functions/connector-onboarding/handler.ts';
let valid=true,anonymous=false,error=null,data={ok:true,queue:[],summary:{ready:false}},calls=0;
const handler=createHandler({env:name=>({SUPABASE_URL:'https://us.test',SUPABASE_ANON_KEY:'anon'}[name]),createClient:(url,key,opts)=>{
 assert.equal(url,'https://us.test');assert.equal(key,'anon');assert.equal(opts.global.headers.Authorization,'Bearer caller');
 return{auth:{getUser:async()=>({data:{user:valid?{id:'native',is_anonymous:anonymous}:null}})},rpc:async(name,args)=>{calls++;assert.equal(name,'tj_connector_onboarding');assert.equal(args.p_body.connection_id,'00000000-0000-0000-0000-000000000001');return {data,error};}};
}});
const body={connection_id:'00000000-0000-0000-0000-000000000001'};
const req=(payload=body)=>new Request('https://edge.test',{method:'POST',headers:{Authorization:'Bearer caller'},body:JSON.stringify(payload)});
assert.equal((await handler(new Request('https://edge.test',{method:'POST'}))).status,401);
assert.equal((await handler(new Request('https://edge.test'))).status,405);
valid=false;assert.equal((await handler(req())).status,401);valid=true;anonymous=true;assert.equal((await handler(req())).status,401);anonymous=false;
for(const payload of [null,[],{}, {...body,action:'delete'}, {...body,connection_id:'not-uuid'}])assert.equal((await handler(req(payload))).status,400);
assert.equal((await handler(req({...body,extra:'x'.repeat(20000)}))).status,413);assert.equal(calls,0);
for(const action of ['status','auto_match','resolve_employee','resolve_location','reject','activate'])assert.equal((await handler(req({...body,action}))).status,200);
for(const [code,status] of [['42501',403],['P0002',404],['22023',400],['40001',409],['23505',409],['54000',409],['XX000',500]]){error={code,message:'diagnostic'};const result=await handler(req());assert.equal(result.status,status);if(status===500)assert.equal((await result.json()).error,'onboarding_operation_failed');}
error=null;data={ok:false,error:'onboarding_review_incomplete',summary:{ready:false}};assert.equal((await handler(req({...body,action:'activate'}))).status,409);
console.log('Onboarding handler passed: native JWT forwarding, anonymous denial, bounded JSON/UUID/actions, guarded RPC-only access, safe error/status mapping and incomplete activation response.');
