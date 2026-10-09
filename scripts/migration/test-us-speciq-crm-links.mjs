import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import {migrateSpeciqDrafts} from './us-speciq-drafts.mjs';
import {migrateSpeciqWorkflow} from './us-speciq-workflow.mjs';
import {migrateSpeciqCrmLinks,crmLinkHelpers} from './us-speciq-crm-links.mjs';
const source=readFileSync(new URL('../../apps/spec-iq/index.html',import.meta.url),'utf8'),out=migrateSpeciqCrmLinks(migrateSpeciqWorkflow(migrateSpeciqDrafts(source)));
const module=out.match(/<script type="module">([\s\S]*?)<\/script>/)[1].replace(/^import[^;]+;/m,'');new vm.Script('(async()=>{'+module+'})()');
assert.ok(!out.includes('Linked CRM drafts require the next integration step'));assert.ok(out.includes('contact_id:selectedCrmContactId,deal_id:selectedCrmDealId'));assert.ok(out.includes('salesperson_name:'));assert.ok(!out.includes('first_name.ilike.%${q}%'));assert.ok(out.includes('window.clearSpeciqCrmLink)window.clearSpeciqCrmLink()'));
function node(){return {value:'',textContent:'',style:{},children:[],setAttribute(){},appendChild(x){this.children.push(x);},replaceChildren(...xs){this.children=xs;this.textContent='';}};}
const fields={},calls=[];for(const id of ['b-contact-results','b-contact-linked','b-contact-search','b-cust-name','b-cust-email','b-cust-phone'])fields[id]=node();
let resolveSearch;
const c={window:{},userOrgId:'org',selectedCrmContactId:null,selectedCrmDealId:null,el:id=>fields[id],document:{createElement:()=>node()},sb:{rpc:async(name,{p_body})=>{calls.push({name,p_body});if(p_body.action==='search')return new Promise(r=>resolveSearch=r);return {data:{ok:true,contact:{id:'contact',name:'<img>',email:null,phone:null},deals:[{id:'deal1',title:'<script>'},{id:'deal2',title:'Other'}]}};}}};vm.createContext(c);vm.runInContext(crmLinkHelpers+';globalThis.selectContact=selectNativeCrmContact;',c);c.clearSpeciqCrmLink=c.window.clearSpeciqCrmLink;
await c.selectContact('contact','org');assert.equal(c.selectedCrmContactId,'contact');assert.equal(c.selectedCrmDealId,null);assert.equal(fields['b-cust-name'].value,'<img>');const select=fields['b-contact-linked'].children[1];assert.equal(select.children.length,3);assert.equal(select.children[1].textContent,'<script>');select.value='deal2';select.onchange();assert.equal(c.selectedCrmDealId,'deal2');c.window.clearSpeciqCrmLink();assert.equal(c.selectedCrmContactId,null);assert.equal(c.selectedCrmDealId,null);
const pending=c.window.searchCrmContacts('Contact');c.userOrgId='different';resolveSearch({data:{ok:true,contacts:[{id:'stale',first_name:'Stale'}]}});await pending;assert.equal(fields['b-contact-results'].children.length,0);
console.log('PASS: complete transformed script parses; native contact search, literal query strings, canonical selection, explicit open deal choice, text-only labels, link clearing and stale organization search suppression; draft sends contact/deal/salesperson fields');
