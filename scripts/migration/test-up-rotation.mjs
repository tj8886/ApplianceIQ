import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import {migrateUpCrmHandoff} from './us-up-crm-handoff.mjs';
import {migrateUpRotation} from './us-up-rotation.mjs';
const source=readFileSync('apps/up-system/index.html','utf8');
const s=migrateUpRotation(migrateUpCrmHandoff(source));
for(const m of s.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g))if(m[1].trim())new vm.Script(m[1]);
assert.ok(s.includes('id:profile.id,source_user_id:identity.source_user_id'));
assert.ok(s.includes("eq('user_id',currentUser.source_user_id)"));
assert.ok(!s.includes('profiles[u.user_id]'));
assert.ok(!s.includes("sb.from('profiles').upsert"));
for(const fn of ['openClockInModal','openStatusModal','recalcQueueOrder','rotateToBackOfQueue','acceptUp','handleAcceptUpTimeout','openReassignModal','openEndVisitModal','takeGreeterDuty','endGreeterDuty']){
 const a=s.indexOf('function '+fn+'('),b=s.indexOf('\n}',a)+2;
 assert.ok(a>=0&&b>a,fn);assert.ok(!/\.from\([^)]*\)\.(?:insert|update|delete)/.test(s.slice(a,b)),fn+' direct writes');
}
let calls=[];const ctx=vm.createContext({sb:{rpc:async(n,args)=>{calls.push([n,args]);return {data:{ok:true}}}},currentOrg:{id:'org'},currentStore:{id:'store'}});
vm.runInContext(s.slice(s.indexOf('async function upRotation('),s.indexOf('async function loadUpProfiles(')),ctx);
vm.runInContext(s.slice(s.indexOf('async function handleAcceptUpTimeout('),s.indexOf('// Shared assignment pipeline')),ctx);
await ctx.handleAcceptUpTimeout('store',{id:'entry',up_offered_at:'2026-10-11T00:00:00Z'});
assert.equal(calls[0][0],'up_rotation');assert.equal(calls[0][1].p_body.expected_offered_at,'2026-10-11T00:00:00Z');
ctx.sb.rpc=async()=>({data:{ok:false,error:'end_or_reassign_visit_first'}});
await assert.rejects(ctx.upRotation({action:'clock_out'}),/End or reassign/);
console.log('UP rotation client: identity mapping, RPC-only floor actions, dated timeout, visible errors and generated script syntax passed');
