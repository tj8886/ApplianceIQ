import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import {migrateUpCrmHandoff} from './us-up-crm-handoff.mjs';
const s=migrateUpCrmHandoff(readFileSync('apps/up-system/index.html','utf8'));
for(const match of s.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g)){if(match[1].trim())new vm.Script(match[1]);}
assert.ok(s.includes("const handoffId=crypto.randomUUID()"));assert.ok(!s.includes("sb.from('contacts').insert"));assert.ok(!s.includes("sb.from('speciq_projects').insert"));
const a=s.indexOf('async function upHandoff('),b=s.indexOf('async function syncFloorMetrics',a);let calls=[];
const ctx=vm.createContext({sb:{rpc:async(n,args)=>{calls.push([n,args]);return {data:{ok:true,deal_id:'deal'}}}},currentOrg:{id:'org'}});
vm.runInContext(s.slice(a,b),ctx);
assert.equal((await ctx.syncWalkInToCRM({id:'waiting'})).deal_id,'deal');assert.equal(calls[0][0],'up_crm_handoff');assert.equal(calls[0][1].p_body.waiting_id,'waiting');
await ctx.syncAfterSaleToCRM('waiting',false,'price','2026-10-12',false);assert.equal(calls[1][1].p_body.action,'after_sale');
ctx.sb.rpc=async()=>({data:{ok:false}});await assert.rejects(ctx.syncWalkInToCRM({id:'waiting'}),/could not be completed/);
console.log('UP handoff client: atomic RPC routing, stable retry ID, visible failure and script syntax passed');
