import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';
import {escapeHtml, moduleAllowed, creditsRemaining, safeAppUrl, handoffUrl} from '../../apps/platform/platform-core.mjs';
const org={organization_id:'fixture-org',organization_name:'<img src=x onerror=alert(1)>',organization_role:'admin'};
assert.equal(moduleAllowed({key:'spec-iq'},['spec_iq'],org),true);
assert.equal(moduleAllowed({key:'spec-iq'},[],org),false);
assert.equal(moduleAllowed({key:'unmapped'},['unmapped'],org),false);
assert.equal(moduleAllowed({key:'crm'},null,org),false);
assert.equal(moduleAllowed({key:'crm'},['crm'],{}),false);
assert.equal(moduleAllowed({key:'intelligence_group'},[],{...org,organization_role:'member'}),false);
assert.equal(creditsRemaining(null),null);
assert.equal(creditsRemaining({credits_included:5,credits_used_this_period:8}),0);
assert.throws(()=>safeAppUrl('javascript:alert(1)','https://platform.test'));
assert.throws(()=>safeAppUrl('//user:password@external.test','https://platform.test'));
assert.throws(()=>handoffUrl('https://app.test','invalid','https://platform.test'));
assert.ok(!escapeHtml(org.organization_name).includes('<img'));
const html=readFileSync(new URL('../../apps/platform/index.html',import.meta.url),'utf8');
const source=[...html.matchAll(/<script type="module">([\s\S]*?)<\/script>/g)][0][1].replace(/^import .*$/gm,'');
const elements=new Map();
function el(id){if(!elements.has(id))elements.set(id,{style:{},value:'',textContent:'',innerHTML:'',disabled:false,classList:{add(){},remove(){},toggle(){}},addEventListener(){}});return elements.get(id)}
let failTable=null, session=null, popup=null, requestBody=null, queryLog=[];
const tables={platform_modules:[{id:'crm',key:'crm',name:org.organization_name,description:'<script>bad</script>',icon:'x',app_url:'https://app.test',visibility:'public'}],platform_plans:[],platform_plan_modules:[],platform_seat_tiers:[],platform_ai_credit_packs:[],org_app_entitlements:[],platform_subscriptions:[],platform_ai_credits:[]};
const sb={auth:{async getSession(){return {data:{session}}},async signUp(){return {data:{user:{id:'pending'},session:null}}},async signOut(){session=null;return {}},onAuthStateChange(){}},from(table){const filters=[];const builder={select(){return builder},eq(...args){filters.push(args);return builder},in(){return builder},order(){return builder},limit(){return builder},then(resolve){queryLog.push({table,filters});return Promise.resolve({data:tables[table],error:failTable===table?{message:'fixture failure'}:null}).then(resolve)}};return builder}};
const bridge={async init(){return org},async organizations(){return [org]},async locations(){return []},async setContext(){return org}};
const context={createClient:()=>sb,createAIQContextBridge:()=>bridge,esc:escapeHtml,moduleAllowed,creditsRemaining,safeAppUrl,handoffUrl,
 document:{getElementById:el,querySelectorAll:()=>[],querySelector:()=>el('nav')},location:{origin:'https://platform.test'},
 window:{open(){popup={opener:'fixture',location:{replace(url){popup.url=url}},close(){popup.closed=true}};return popup}},
 alert(){},setTimeout,fetch:async(url,options)=>{requestBody=JSON.parse(options.body);return {ok:true,json:async()=>({ticket:'a'.repeat(64)})}}};
vm.createContext(context);vm.runInContext(source,context);await new Promise(r=>setTimeout(r,0));
el('auth-email').value='fixture@example.test';el('auth-password').value='test password';
vm.runInContext('isSignup=true',context);await context.window.handleAuth();
assert.equal(vm.runInContext('state.user',context),null);
assert.equal(el('auth-notice').style.display,'block');assert.equal(el('auth-submit').disabled,false);
vm.runInContext("state.user={id:'fixture'}",context);await vm.runInContext('initPlatform()',context);
assert.equal(el('platform').style.display,'block');assert.equal(vm.runInContext('getActiveModules().length',context),0);
assert.equal(el('credits-count').textContent,'Credits not configured');
assert.equal(el('seat-count').textContent,'Seat allocation not configured');
assert.ok(el('module-grid').innerHTML.includes('&lt;img'));assert.ok(!el('module-grid').innerHTML.includes('<script>bad'));
for(const table of ['org_app_entitlements','platform_subscriptions','platform_ai_credits'])assert.ok(queryLog.find(q=>q.table===table).filters.some(([column,value])=>['org_id','organization_id'].includes(column)&&value===org.organization_id));
tables.org_app_entitlements=[{app_key:'crm'}];await vm.runInContext('initPlatform()',context);assert.equal(vm.runInContext('getActiveModules().length',context),1);
session={access_token:'fixture-access',refresh_token:'never-relay-this',user:{id:'fixture'}};
await context.window.loadModule('crm');assert.equal(popup.opener,null);assert.equal(popup.url,'https://app.test/#aiq_ticket='+'a'.repeat(64));
assert.equal(requestBody.organization_id,org.organization_id);assert.equal(requestBody.refresh_token,undefined);
failTable='org_app_entitlements';await vm.runInContext('initPlatform()',context);assert.equal(el('platform').style.display,'none');assert.equal(vm.runInContext('getActiveModules().length',context),0);
await context.window.handleLogout();assert.equal(vm.runInContext('state.user',context),null);assert.equal(vm.runInContext('state.subscription',context),null);
for(const p of ['index.html','workspace.html']){const text=readFileSync(new URL('../../apps/platform/'+p,import.meta.url),'utf8');for(const m of text.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/g))new vm.Script('(async()=>{'+m[1].replace(/^import .*$/gm,'')+'})()')}
console.log('Platform shell checks passed: confirmation, company filters, denied entitlements, billing truth, escaping, ticket handoff and logout');
