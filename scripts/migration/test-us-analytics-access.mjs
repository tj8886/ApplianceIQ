import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import {summarizeCachedRequests,migrateAnalyticsAccess,omitDemoJoin} from './us-analytics-access.mjs';
const turns=[{role:'assistant',persona_name:'TJ',metadata:{tier:'cached',deterministic_type:'product'},content:'PRIVATE_RESPONSE'},{role:'assistant',persona_name:'TJ',metadata:{tier:'cached',deterministic_type:'product',cache_key:'PRIVATE_KEY'}},{role:'user',metadata:{tier:'cached'}},{role:'assistant',metadata:{tier:'fast'}},{role:'assistant',persona_name:'<img>',metadata:{tier:'cached',deterministic_type:'<script>'}}];
const before=JSON.stringify(turns),summary=summarizeCachedRequests(turns);assert.equal(summary.length,2);assert.equal(summary[0].request_count,2);assert.equal(summary.reduce((a,b)=>a+b.request_count,0),3);assert(!JSON.stringify(summary).includes('PRIVATE'));assert.equal(JSON.stringify(turns),before);assert.deepEqual(summarizeCachedRequests([]),[]);
const source=readFileSync(new URL('../../apps/ai-coach/analytics.html',import.meta.url),'utf8');
const html=migrateAnalyticsAccess(source);assert(!html.includes("from('ai_response_cache')"));assert(source.includes("from('ai_response_cache')"));
const script=html.match(/<script type="module">([\s\S]*?)<\/script>/)[1].replace(/^import.*$/gm,'').replace(/^const sb=.*$/m,'').replace(/^loadData\(\);$/m,'').replace(/^setInterval.*$/m,'');
async function render(failure=false){
 const content={},timeBar={},tables=[];
 const document={getElementById:n=>n==='content'?content:timeBar,createElement:()=>({set textContent(v){this.innerHTML=String(v).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;');}})};
 const sb={from:table=>{tables.push(table);const chain={select:()=>chain,gte:()=>chain,eq:()=>chain,order:()=>chain,limit:async()=>({data:table==='ai_conversation_turns'&&tables.length===1?turns:[],error:failure?{message:'PRIVATE_ERROR'}:null})};return chain;}};
 const context={sb,document,window:{},Date};vm.createContext(context);vm.runInContext(script,context);await vm.runInContext('loadData()',context);return {content,tables};
}
const success=await render();assert(success.content.innerHTML.includes('Cached Requests'));assert(success.content.innerHTML.includes('loaded visible conversation sample'));assert(success.content.innerHTML.includes('&lt;img&gt;'));assert(success.content.innerHTML.includes('&lt;script&gt;'));assert(!success.content.innerHTML.includes('PRIVATE_KEY'));const cacheCard=success.content.innerHTML.slice(success.content.innerHTML.indexOf('Cached Use by Persona')).split('<div class="card">')[0];assert(!cacheCard.includes('PRIVATE_RESPONSE'));assert.deepEqual(success.tables,['ai_conversation_turns','ai_conversation_turns','ai_audit_events']);
const failed=await render(true);assert.match(failed.content.textContent,/could not be loaded/);assert(!failed.content.textContent.includes('PRIVATE_ERROR'));
for(const path of ['../../apps/command-center/index.html','../../apps/intelligence-group/command-center/index.html']){
 const original=readFileSync(new URL(path,import.meta.url),'utf8'),migrated=omitDemoJoin(original);assert(original.includes("rpc('join_demo_org')"));assert(!migrated.includes("rpc('join_demo_org')"));
 const start=migrated.indexOf('async function bootApp(){'),end=migrated.indexOf('\nasync function renderCC',start),elements=new Map();
 const context={currentOrg:null,$:id=>{if(!elements.has(id))elements.set(id,{style:{}});return elements.get(id);},sb:{from:()=>({select:()=>({eq:async()=>({data:[]})})}),rpc:()=>{throw Error('No demo RPC permitted');}},renderCC:()=>{throw Error('No member-only render permitted');}};
 vm.createContext(context);vm.runInContext(migrated.slice(start,end),context);await vm.runInContext('bootApp()',context);assert.match(elements.get('#ccMain').innerHTML,/Ask your admin for an invite/);assert.equal(context.currentOrg,null);
}
assert.throws(()=>migrateAnalyticsAccess('changed'),/source contract changed/);
console.log('PASS: visible cached-request grouping, privacy, escaping, real analytics rendering/error flow, private-cache query removal and command-center invite empty states');
