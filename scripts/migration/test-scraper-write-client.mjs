import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const html=fs.readFileSync(new URL('../../apps/pim-scraper/index.html',import.meta.url),'utf8');
const source=html.slice(html.indexOf('async function _proxyWrite('),html.indexOf('// Proxy the sb object'));
assert(!html.includes('PROXY_KEY'));assert(!source.includes('currentSession'));
let requests=[],sessions=0,fail=false;
const context=vm.createContext({_rawSb:{auth:{getSession:async()=>{sessions++;return {data:{session:{access_token:'fresh-'+sessions}}};}}},SB_URL:'https://jdxslqmgjsuzoisuhvlc.supabase.co',WRITE_PROXY_URL:'https://edge.test',SB_KEY:'public',fetch:async(url,opts)=>{
 const body=JSON.parse(opts.body);requests.push(body);assert.equal(opts.headers.Authorization,'Bearer fresh-'+sessions);assert(!('x-proxy-key' in opts.headers));
 if(fail&&requests.length===2)return {ok:false,json:async()=>({error:'governed_catalog_write_required'})};
 const rows=Array.isArray(body.data)?body.data:[body.data];return {ok:true,json:async()=>({ok:true,count:rows.length,data:rows})};
}});
vm.runInContext(source,context);
const result=await context._createWriteChain('raw').insert(Array.from({length:101},(_,id)=>({id}))).select('*');
assert.equal(result.data.length,101);assert.equal(result.data[0].id,0);assert.equal(result.count,101);assert.deepEqual(requests.map(x=>x.data.length),[100,1]);assert.equal(sessions,2);
requests=[];fail=true;const partial=await context._createWriteChain('raw').insert(Array.from({length:101},(_,id)=>({id})));
assert.equal(partial.count,100);assert.equal(partial.partial,true);assert.match(partial.error.message,/100 rows were saved/);
requests=[];fail=false;for(const method of ['neq','not','or','gte','filter','limit']){
 const result=await context._createWriteChain('raw').update({price:1})[method]('price',2);assert(result.error);assert.equal(requests.length,0);
}
assert.equal((await context._createWriteChain('raw').insert([{id:1},{id:2}]).single()).error.message,'Expected a single returned row');
console.log('Scraper client passed: fresh auth, 100-row chunks, accurate partial saves, select(*), cardinality and fail-closed filters.');

requests=[];context.SB_URL='https://fumwwhyozeouoqscolke.supabase.co';assert.match((await context._proxyWrite('raw','insert',{id:1})).error.message,/migrated US workspace/);assert.equal(requests.length,0);
const crm=fs.readFileSync(new URL('../../apps/crm/index.html',import.meta.url),'utf8');const button=crm.slice(crm.indexOf("    toast('Previewing due sequence steps…'"),crm.indexOf('// Team roles grid'));assert(button.indexOf("if(SUPABASE_URL!==")<button.indexOf('await fetch'));
