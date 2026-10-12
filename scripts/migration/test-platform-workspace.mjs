import assert from 'node:assert/strict';import vm from 'node:vm';import {readFileSync} from 'node:fs';
import {escapeHtml,moduleAllowed,safeAppUrl,handoffUrl} from '../../apps/platform/platform-core.mjs';
const html=readFileSync(new URL('../../apps/platform/workspace.html',import.meta.url),'utf8');
const source=[...html.matchAll(/<script type="module">([\s\S]*?)<\/script>/g)][0][1].replace(/^import .*$/gm,'').replace(/^boot\(\)\.catch.*$/m,'');
const nodes=new Map();function el(id){if(!nodes.has(id))nodes.set(id,{innerHTML:'',textContent:'',style:{},dataset:{},classList:{add(){},remove(){}},focus(){}});return nodes.get(id)}
let popup,failEntitlements=false;const calls=[];
const org={organization_id:'org-one',organization_name:'Company',organization_role:'member'};
const modules=[{key:'crm',name:'<img src=x onerror=alert(1)>',description:'<script>bad</script>',visibility:'public',app_url:'https://crm.test'}, {key:'spec-iq',name:'Spec',visibility:'public'}, {key:'intelligence_group',name:'Admin',visibility:'private'}];
const sb={auth:{async getSession(){return {data:{session:{user:{id:'new-auth-id',email:'fixture@example.test'},access_token:'fixture-access'}}}},onAuthStateChange(){}},from(table){let builder={select(){return builder},eq(...args){calls.push({table,filter:args});return builder},in(){return builder},order(){return builder},limit(){return builder},then(resolve){const data=table==='platform_modules'?modules:table==='org_app_entitlements'?[{app_key:'crm'}]:[{id:'note-one',organization_id:org.organization_id,user_id:'migrated-source-id',title:'<script>note</script>',body:'<img src=x>',action_url:'javascript:alert(1)'}];return Promise.resolve({data,error:table==='org_app_entitlements'&&failEntitlements?{message:'fixture'}:null}).then(resolve)}};return builder}};
const bridge={async init(){return org},async organizations(){return [{...org,organization_name:'<img src=x>'}]},async locations(){return []}};
const context={createClient:()=>sb,createAIQContextBridge:()=>bridge,esc:escapeHtml,moduleAllowed,safeAppUrl,handoffUrl,document:{getElementById:el,querySelectorAll:()=>[],body:el('body')},location:{origin:'https://platform.test'},window:{open(){popup={location:{replace(url){popup.url=url}},close(){popup.closed=true}};return popup}},alert(){},setTimeout,clearTimeout,console,
 fetch:async()=>({ok:true,json:async()=>({ticket:'b'.repeat(64)})})};vm.createContext(context);vm.runInContext(source,context);
await vm.runInContext('boot()',context);
assert.ok(el('apps').innerHTML.includes('&lt;img'));assert.ok(!el('apps').innerHTML.includes('<script>bad'));
assert.ok(!el('apps').innerHTML.includes('data-key="spec-iq"'));assert.equal(el('ops').innerHTML,'');
assert.ok(el('notifications').innerHTML.includes('&lt;script&gt;note'));
assert.ok(el('orgSelect').innerHTML.includes('&lt;img'));
assert.equal(calls.some(c=>c.table==='crm_notifications'&&c.filter[0]==='user_id'),false);
await vm.runInContext("openModule('spec-iq')",context);assert.equal(popup,undefined);
await vm.runInContext("openModule('crm')",context);assert.equal(popup.url,'https://crm.test/#aiq_ticket='+'b'.repeat(64));
failEntitlements=true;await assert.rejects(vm.runInContext('loadCompanyData()',context),/Company apps/);
console.log('Workspace checks passed: company entitlements, migrated notifications, escaped content and permitted ticket launches');
