import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import {omitObsoleteWarrantyCleanup,routeLegacyProductIq,surfaceManufacturerAssetErrors} from './us-app-reference-fixes.mjs';
import {migrateManufacturerInvitations} from './us-manufacturer-invitations.mjs';
const spec=readFileSync(new URL('../../apps/spec-iq/index.html',import.meta.url),'utf8'),fixed=omitObsoleteWarrantyCleanup(spec);
assert.equal((spec.match(/from\('speciq_package_warranties'\)/g)||[]).length,3);assert(!fixed.includes("from('speciq_package_warranties')"));assert(fixed.includes("from('speciq_product_warranties').insert"));assert(fixed.includes("from('speciq_product_warranties').select"));
const packageFn=fixed.slice(fixed.indexOf('async function deletePackage('),fixed.indexOf('window.deletePackage='));
const projectFn=fixed.slice(fixed.indexOf('async function deleteProject('),fixed.indexOf('window.deleteProject='));
async function runDelete(approved,kind){
 const calls=[];
 const sb={from(table){return {
  select(){return {eq:async()=>({data:[{id:'package-fixture'}]})};},
  delete(){return {eq:async(column,id)=>{calls.push({table,column,id});return {error:null};}};}
 };}};
 const sandbox={confirm:()=>approved,sb,allPackages:[{id:'package-fixture'},{id:'keep'}],projects:[{id:'project-fixture'},{id:'keep'}],renderPackagesList(){},loadProjects(){},loadDashboardStats(){},console,alert(){throw Error('Unexpected deletion failure');}};
 vm.createContext(sandbox);vm.runInContext(packageFn+'\n'+projectFn,sandbox);await vm.runInContext(kind==='project'?"deleteProject('project-fixture','Test',1)":"deletePackage('package-fixture','Test')",sandbox);return {calls,sandbox};
}
for(const kind of ['package','project']){assert.equal((await runDelete(false,kind)).calls.length,0);const r=await runDelete(true,kind);assert(!r.calls.some(x=>x.table==='speciq_package_warranties'));assert(r.calls.some(x=>x.table==='speciq_package_products'));assert(r.calls.some(x=>x.table==='speciq_packages'));assert.equal((kind==='package'?r.sandbox.allPackages:r.sandbox.projects).length,1);}
const legacy=readFileSync(new URL('../../apps/product-iq/apps/product-iq/index.html',import.meta.url),'utf8'),redirect=routeLegacyProductIq(legacy);
assert(legacy.includes("from('aiq_product_specifications')"));assert(!redirect.includes("from('aiq_product_specifications')"));assert(!redirect.includes("from('aiq_product_relationships')"));assert(redirect.includes('<a href="/pim.html">'));
const script=redirect.match(/<script>([\s\S]*?)<\/script>/)[1];
for(const hash of ['#aiq_ticket=single-use-ticket','#aiq_relay=old-token','#old-section','']){const targets=[],context={URL,location:{origin:'https://product.example',search:'?view=catalog',hash,replace:x=>targets.push(x)}};vm.createContext(context);vm.runInContext(script,context);const u=new URL(targets[0]);assert.equal(u.pathname,'/pim.html');assert.equal(u.search,'?view=catalog');assert.equal(u.hash,hash.startsWith('#aiq_ticket=')?hash:'');}
const categories=JSON.parse(readFileSync(new URL('./us-manufacturer-categories.json',import.meta.url),'utf8')),cats=categories.groups.flatMap(x=>x.cats),trade=readFileSync(new URL('../../apps/iq-training/trade.html',import.meta.url),'utf8'),catSandbox={};vm.createContext(catSandbox);vm.runInContext(trade.match(/const CAT_LABEL=([^;]+);/)[0]+'\nglobalThis.labels=CAT_LABEL;',catSandbox);
assert.equal(cats.length,24);assert.equal(new Set(cats.map(x=>x.key)).size,24);assert.deepEqual(cats.map(x=>x.key).sort(),Object.keys(catSandbox.labels).sort());for(const c of cats){assert.equal(c.label,catSandbox.labels[c.key]);assert(['file','video'].includes(c.type));assert(c.audiences.length>0);assert(c.audiences.every(a=>['retailer','builder','designer'].includes(a)));}
const manufacturer=surfaceManufacturerAssetErrors(migrateManufacturerInvitations(readFileSync(new URL('../../apps/iq-training/manufacturer.html',import.meta.url),'utf8')));
const a=manufacturer.indexOf('async function loadAssets(){'),b=manufacturer.indexOf('// ---------- UPLOAD MODAL ----------',a),assetScript=manufacturer.slice(a,b);
async function renderLibrary({error=false,throwNetwork=false}={}){const el={innerHTML:'',textContent:''},context={ASSETS:[],ACTIVE_VENDOR:{id:'vendor'},CATS:categories,mfrEscape:s=>String(s).replaceAll('<','&lt;').replaceAll('>','&gt;'),document:{getElementById:()=>el},sb:{from:()=>({select:()=>({eq:()=>({order:async()=>{if(throwNetwork)throw Error('PRIVATE');return {error:error?{message:'PRIVATE'}:null,data:[{id:'asset-id',title:'<img src=x onerror=1>',category:'spec_sheet'}]};}})})})}};vm.createContext(context);vm.runInContext(assetScript,context);await vm.runInContext('loadAssets()',context);return el;}
const rendered=await renderLibrary();assert(rendered.innerHTML.includes('Spec / Cut Sheets'));assert(rendered.innerHTML.includes('&lt;img'));assert(!rendered.innerHTML.includes('<img src=x'));
for(const failure of [{error:true},{throwNetwork:true}]){const el=await renderLibrary(failure);assert.match(el.textContent,/could not be loaded/);assert(!el.textContent.includes('PRIVATE'));assert(!el.innerHTML.includes('Nothing uploaded'));}
for(const fn of [omitObsoleteWarrantyCleanup,routeLegacyProductIq,surfaceManufacturerAssetErrors])assert.throws(()=>fn('changed'),/contract changed/);
if(process.argv[2]){const out=process.argv[2];const built=readFileSync(out+'/academy/mfr_categories.json','utf8');assert.deepEqual(JSON.parse(built),categories);const h=readFileSync(out+'/academy/manufacturer.html','utf8');assert(h.includes('mfr_categories.json'));assert(h.includes('could not be loaded'));assert(!readFileSync(out+'/spec-iq/index.html','utf8').includes("from('speciq_package_warranties')"));assert(!readFileSync(out+'/product-iq/apps/product-iq/index.html','utf8').includes("from('aiq_product_specifications')"));}
console.log('PASS: obsolete warranty cleanup omitted; existing create/read and confirmed delete handlers retained; legacy Product IQ routes to PIM with ticket-only hash; 24 source-matched categories bundled; actual library rendering escapes titles and surfaces read failures');
