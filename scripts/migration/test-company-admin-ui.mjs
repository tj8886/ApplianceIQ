import assert from 'node:assert/strict';import vm from 'node:vm';import {readFileSync} from 'node:fs';
const html=readFileSync(new URL('../../apps/intelligence-group/admin.html',import.meta.url),'utf8');
let source=[...html.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/g)].map(m=>m[1]).join('\n');
source=source.replace(/if\(!new URLSearchParams\(location.hash.slice\(1\)\)\).has\('aiq_ticket'\)\)boot\(\);/,'');
const orgId='11111111-1111-1111-1111-111111111111',memberId='22222222-2222-2222-2222-222222222222';
const nodes=new Map();function el(id){if(!nodes.has(id))nodes.set(id,{value:'',textContent:'',innerHTML:'',style:{},checked:false});return nodes.get(id)}
const network=[];const context={URL,URLSearchParams,location:{origin:'https://admin.test',hash:'#aiq_ticket=fixture'},localStorage:{getItem(){return 'fixture-token'},removeItem(){}},setInterval(){},setTimeout,alert(){},confirm(){return true},console,
 window:{addEventListener(){},ApplianceIQ:{supabase:{auth:{onAuthStateChange(){return {data:{subscription:{}}}},async setSession(args){return {data:{session:args}}},async getSession(){return {data:{session:{access_token:'shared-session',user:{id:'new-auth'}}}}}}}}},
 document:{getElementById:el,querySelector(){return null}},fetch:async(url,opts)=>{const args=JSON.parse(opts.body||'{}');network.push({url,args});let result=args.p_action==='bootstrap'?{platform_admin:true,source_user_id:'old-source',organizations:[{id:orgId,name:'Test'}]}:args.p_action==='snapshot'?{mems:[],roles:[],ents:[],invs:[],locs:[],locmems:[]}:{ok:true,record:{id:memberId},organization_id:orgId};return {ok:true,text:async()=>JSON.stringify(result)}}};
vm.createContext(context);vm.runInContext(source,context);
vm.runInContext(`S.org={id:'${orgId}'};S.user={id:'new-auth'};`,context);await vm.runInContext('postLogin()',context);assert.equal(vm.runInContext('S.sourceUserId',context),'old-source');assert.equal(vm.runInContext('S.super',context),true);
await vm.runInContext(`api('/rest/v1/organization_members?id=eq.${memberId}',{method:'PATCH',body:JSON.stringify({status:'removed'})})`,context);
assert.equal(network.at(-1).args.p_action,'member_save');assert.equal(network.at(-1).args.p_payload.id,memberId);assert.equal(network.at(-1).args.p_organization_id,orgId);
await vm.runInContext(`api('/rest/v1/organizations',{method:'POST',body:JSON.stringify({name:'Company',organization_id:'ignored'})})`,context);assert.equal(network.at(-1).args.p_action,'company_create');assert.equal(network.at(-1).args.p_organization_id,null);assert.equal(network.at(-1).args.p_payload.organization_id,undefined);
await assert.rejects(vm.runInContext(`api('/rest/v1/platform_admins?id=eq.${memberId}',{method:'DELETE'})`,context),/not available/);
await vm.runInContext(`rpc('provision_standard_roles',{p_org:'${orgId}'})`,context);assert.equal(network.at(-1).args.p_action,'provision_roles');
vm.runInContext(`S.orgData={locs:[{id:'${memberId}',location_type:'store',is_active:true}],mems:[{user_id:'source-user',_name:'Test'}]};`,context);el('sp-'+memberId).checked=true;
await vm.runInContext("saveStorePicker('source-user')",context);const assignment=network.find(x=>x.args.p_action==='member_locations');assert.deepEqual(assignment.args.p_payload.location_ids,[memberId]);assert.equal(assignment.args.p_payload.primary_location_id,memberId);
assert.equal(network.some(x=>x.url.includes('/rest/v1/org_location_members')),false);
assert.ok(!vm.runInContext(`esc('"<img>')`,context).includes('"'));assert.ok(html.includes('manager_id:this.value||null'));assert.ok(html.includes('aiq:intelligence-ready'));
await vm.runInContext("adoptAdminSession({access_token:'direct-password-session',refresh_token:'fixture-refresh'})",context);assert.equal(vm.runInContext('S.sharedSession.access_token',context),'direct-password-session');
console.log('Admin UI checks passed: mapped identities, scoped mutations, blocked root-admin writes, role provisioning and atomic assignments');
