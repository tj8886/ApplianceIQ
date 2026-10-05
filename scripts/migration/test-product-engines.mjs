import assert from 'node:assert/strict';
import {createHandler as product} from '../../supabase/functions/product-intelligence/handler.ts';
import {createHandler as orchestrator} from '../../supabase/functions/intelligence-orchestrator/handler.ts';
const env = name => ({SUPABASE_URL:'https://destination.invalid',SUPABASE_ANON_KEY:'public-test-key'})[name];
const req = (body,auth=true) => new Request('https://example.invalid', {method:'POST',headers:{'Content-Type':'application/json',...(auth?{Authorization:'Bearer test'}:{})},body:JSON.stringify(body)});
function client({signedIn=true,mapped=true,errorTable=null}={}) {
 const calls=[];
 const createClient=(url,key,opts)=>{
  assert.equal(url,'https://destination.invalid'); assert.equal(key,'public-test-key'); assert.equal(opts.global.headers.Authorization,'Bearer test');
  return {auth:{getUser:async()=>({data:{user:signedIn?{id:'native-user'}:null},error:null})},rpc:async name=>{assert.equal(name,'tj_runtime_my_platform_context');return {data:mapped?{organization_id:'org'}:{},error:null}},schema:s=>{
   assert.equal(s,'tj');return {from:table=>{
    const call={table,steps:[]};calls.push(call);
    const b=new Proxy({}, {get(_,k){if(k==='then') return resolve=>resolve({data:table==='aiq_products_app'?[{id:'product',model:'KNOWN',sale_price:1200,category:'refrigeration',width_inches:30,source_confidence:80}]:[],error:table===errorTable?{code:'denied'}:null});return (...args)=>{call.steps.push([k,...args]);return b}}});return b;
   }};
  }};
 };
 return {createClient,calls};
}
for(const engine of [product,orchestrator]) {
 let c=client();const h=engine({...c,env});assert.equal((await h(req({query:'fridge'},false))).status,401);assert.equal((await h(req(null))).status,400);
 c=client({signedIn:false});assert.equal((await engine({...c,env})(req({query:'fridge'}))).status,401);
 c=client({mapped:false});assert.equal((await engine({...c,env})(req({query:'fridge'}))).status,403);
}
let c=client();let h=product({...c,env,fetchImpl:()=>{throw new Error('No AI call without configured model')}});
assert.equal((await h(req({filters:{required_terms:'bad'}}))).status,400);
assert.equal((await h(req({filters:{max_width:-1}}))).status,400);
let response=await h(req({query:'fridge',filters:{max_price:1500}}));assert.equal(response.status,200);let body=await response.json();assert.equal(body.products.length,1);assert.equal(body.answer,null);
assert.equal(c.calls[0].table,'aiq_products_app');assert(c.calls.every(x=>x.steps.every(step=>!JSON.stringify(step).includes('dealer_cost'))));
c=client({errorTable:'pim_product_images'});assert.equal((await product({...c,env})(req({query:'fridge'}))).status,500);
c=client();let downstream=0;h=orchestrator({...c,env,fetchImpl:async(url,options)=>{downstream++;assert.equal(url,'https://destination.invalid/functions/v1/product-intelligence');assert.equal(options.headers.Authorization,'Bearer test');return new Response(JSON.stringify({products:[]}));}});
body=await (await h(req({message:'fridge model RF263BEAESR'}))).json();assert.equal(body.mode,'discovery');assert.equal(body.state.constraints.max_price,undefined);
body=await (await h(req({message:'find a fridge under $1500 in a 30 inch opening'}))).json();assert.equal(body.mode,'recommend');assert.equal(downstream,1);
assert.equal((await h(req({message:'hello',state:{models:{bad:true}}}))).status,400);
console.log('Product engine tests passed: session, mapped org, filters, RLS client, enrichment failure, discovery and downstream routing.');
