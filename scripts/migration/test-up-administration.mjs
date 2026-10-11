import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import {migrateUpCrmHandoff} from './us-up-crm-handoff.mjs';
import {migrateUpRotation} from './us-up-rotation.mjs';
import {migrateUpOperations} from './us-up-operations.mjs';
import {migrateUpAdministration} from './us-up-administration.mjs';
const s=migrateUpAdministration(migrateUpOperations(migrateUpRotation(migrateUpCrmHandoff(readFileSync('apps/up-system/index.html','utf8')))));
for(const m of s.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g))if(m[1].trim())new vm.Script(m[1]);
for(const table of ['organization_members','org_invites','org_locations'])for(const op of ['insert','update','delete']){
 const a=s.indexOf('async function renderSettings(');assert.ok(!s.slice(a).includes("sb.from('"+table+"')."+op),'settings '+table+' '+op);
}
assert.ok(s.includes("sb.rpc('accept_org_invite'"));assert.ok(s.includes("sb.rpc('create_org_invite'"));assert.ok(s.includes("sb.rpc('revoke_org_invite'"));
assert.ok(s.includes('Existing store access is retained.'));assert.ok(s.includes("action:'report_missed'"));assert.ok(s.includes("action:'review_missed'"));assert.ok(s.includes("const id=crypto.randomUUID()"));
const calls=[];const ctx=vm.createContext({sb:{rpc:async(n,a)=>{calls.push([n,a]);return{data:{ok:true}}}},currentOrg:{id:'org'},currentStore:{id:'store'}});
vm.runInContext(s.slice(s.indexOf('async function upAdministration('),s.indexOf('async function reloadUpStores(')),ctx);
await ctx.upAdministration({action:'set_role',member_id:'member',role:'manager'});assert.equal(calls[0][0],'up_administration');assert.equal(calls[0][1].p_body.organization_id,'org');
ctx.sb.rpc=async()=>({data:{ok:false,error:'last_owner_required'}});await assert.rejects(ctx.upAdministration({action:'deactivate_member'}),/active owner/);
console.log('UP administration: generated syntax, scoped RPC routes, invitation flow, preserved store access, stable manual-report IDs and last-owner error passed');
