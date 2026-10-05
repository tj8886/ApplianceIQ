import assert from 'node:assert/strict';
import {createHandler} from '../../supabase/functions/crm-scheduled-tasks/handler.ts';
let valid=true,error=null,calls=0;
const organization_id='11111111-1111-1111-1111-111111111111';
const handler=createHandler({env:n=>({SUPABASE_URL:'https://us.test',SUPABASE_ANON_KEY:'anon'}[n]),createClient:(url,key,options)=>{assert.equal(key,'anon');assert.equal(options.global.headers.Authorization,'Bearer native');return {auth:{getUser:async()=>({data:{user:valid?{id:'native',is_anonymous:false}:null}})},rpc:async(name,args)=>{calls++;assert.equal(name,'tj_run_crm_outreach_tasks');assert.deepEqual(args,{p_org:organization_id});return {data:{ok:true,anniversaries_created:1},error};}};}});
const req=body=>new Request('https://edge.test',{method:'POST',headers:{Authorization:'Bearer native'},body});
assert.equal((await handler(new Request('https://edge.test',{method:'POST'}))).status,401);
valid=false;assert.equal((await handler(req('{}'))).status,401);valid=true;
for(const [body,status] of [['{}',400],['{',400],['[]',400],['x'.repeat(2049),413]])assert.equal((await handler(req(body))).status,status);
assert.equal(calls,0);assert.equal((await handler(req(JSON.stringify({organization_id})))).status,200);
for(const [code,status] of [['42501',403],['XX000',500]]){error={code,message:'private record detail'};const response=await handler(req(JSON.stringify({organization_id})));assert.equal(response.status,status);assert.ok(!(await response.text()).includes('private record detail'));}
console.log('CRM housekeeping handler: native identity, tenant payload, size limits and safe failures passed.');
