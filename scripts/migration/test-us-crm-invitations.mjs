import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import {migrateCrmInvitations} from './us-crm-invitations.mjs';
import {installUsRuntimeRpc} from '../../apps/_shared/us-runtime-rpc.mjs';
const source=readFileSync(new URL('../../apps/crm/index.html',import.meta.url),'utf8');
const migrated=migrateCrmInvitations(source);
const accept=migrated.match(/async function acceptInvite\(code\)\{[\s\S]*?\n\}/)[0];
const start=migrated.indexOf('async function boot(){'),end=migrated.indexOf('  // Load visibility scope',start);
const boot=migrated.slice(start,end)+'return {currentOrg,currentRole};}';
async function run({result={data:{ok:true,organization_id:'invited'}},invite=true,members=[{role:'member',organizations:{id:'existing'}},{role:'admin',organizations:{id:'invited'}}]}={}){
 const calls=[],alerts=[],replaced=[];
 const client=installUsRuntimeRpc({supabaseUrl:'https://jdxslqmgjsuzoisuhvlc.supabase.co',auth:{getSession:async()=>({data:{session:{user:{id:'native'}}}})},rpc:async(name,args)=>{calls.push({kind:'rpc',name,args});return result;},from:name=>({select:()=>({eq:async()=>{calls.push({kind:'members',name});return {data:members};}})})});
 const context={sb:client,location:{search:invite?'?invite=capability&view=pipeline':'?view=pipeline',href:invite?'https://crm.example/?invite=capability&view=pipeline':'https://crm.example/?view=pipeline'},history:{replaceState:(_a,_b,u)=>replaced.push(String(u))},URL,URLSearchParams,alert:m=>alerts.push(m),mainEl:{},showApp(){},showLanding(){},currentUser:null,currentOrg:null,currentRole:null,orgs:[]};
 vm.createContext(context);vm.runInContext(accept+'\n'+boot,context);const output=await vm.runInContext('boot()',context);
 return {calls,alerts,replaced,output,context};
}
const success=await run();assert.equal(success.calls[0].name,'tj_runtime_accept_org_invite');assert.equal(success.calls[0].args.p_code,'capability');assert.equal(success.calls[1].kind,'members');assert.equal(success.output.currentOrg.id,'invited');assert.equal(success.output.currentRole,'admin');assert.equal(success.alerts.length,0);assert.equal(new URL(success.replaced[0]).searchParams.get('invite'),null);assert.equal(new URL(success.replaced[0]).searchParams.get('view'),'pipeline');
for(const error of ['email_mismatch','expired','identity_review_required','membership_review_required','invalid_or_used']){const failed=await run({result:{data:{ok:false,error}}});assert.equal(failed.calls.length,1);assert.equal(failed.replaced.length,0);assert.equal(failed.alerts.length,1);assert.equal(failed.context.mainEl.textContent,failed.alerts[0]);}
const transport=await run({result:{error:{message:'PRIVATE_DATABASE_DETAIL'}}});assert(!transport.alerts[0].includes('PRIVATE'));assert.equal(transport.replaced.length,0);
const empty=await run({invite:false,members:[]});assert.equal(empty.calls.length,1);assert.equal(empty.calls[0].kind,'members');assert.match(empty.context.mainEl.innerHTML,/administrator/);assert(!empty.context.mainEl.innerHTML.includes('Create Organization'));
assert.throws(()=>migrateCrmInvitations('changed'),/contract changed/);assert(source.includes("sb.rpc('accept_invite'"));assert(!migrated.includes("sb.rpc('join_demo_org'"));
console.log('PASS: native invitation route, acceptance before membership read, invited organization selection, failure URL retention, private-error redaction and no automatic demo/self-owner fallback');
