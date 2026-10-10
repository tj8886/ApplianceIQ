import assert from 'node:assert/strict';
import {createHandler as scoring} from '../../supabase/functions/recommendation-scoring-engine/handler.ts';
import {createHandler as comparison} from '../../supabase/functions/product-comparison-engine/handler.ts';
const env=n=>({SUPABASE_URL:'https://destination.invalid',SUPABASE_ANON_KEY:'public-key'})[n];
const ids=['11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222'];
const request=(body,auth=true)=>new Request('https://example.invalid',{method:'POST',headers:{'Content-Type':'application/json',...(auth?{Authorization:'Bearer native-session'}:{})},body:JSON.stringify(body)});
function mock({mapped=true,signedIn=true,products=null,fail=false}={}) {
 const calls=[];
 const fetchImpl=async(url,options)=>{
  calls.push({url,options});assert.equal(options.headers.Authorization,'Bearer native-session');assert.equal(options.headers.apikey,'public-key');
  if(url.includes('/auth/v1/user')) return new Response(JSON.stringify({id:'native-user'}),{status:signedIn?200:401});
  if(url.includes('/rpc/')) return new Response(JSON.stringify(mapped?{organization_id:'organization'}:{}));
  if(url.includes('/functions/')) return new Response(JSON.stringify({products:(products??[{id:ids[0],model:'MISSING',width_inches:null,sale_price:null,lowest_price:null,msrp:null}]).map(product=>({product,features:[],documents:[],dimensions:[],retailer_prices:[]}))}),{status:fail?500:200});
  assert.equal(options.headers['Accept-Profile'],'tj');assert.equal(options.headers['Content-Profile'],'tj');assert(!url.includes('user_id=eq.native-user'));
  if(fail) return new Response('{}',{status:403});
  if(url.includes('ai_conversation_memory')) return new Response(JSON.stringify([{profile:{budget_max:1500}}]));
  if(url.includes('aiq_products_app')) return new Response(JSON.stringify(products??ids.map((id,i)=>({id,model:'MODEL'+i,width_inches:null,sale_price:null,lowest_price:null,msrp:null}))));
  if(url.includes('ai_product_comparisons')) {const body=JSON.parse(options.body);assert(!('user_id' in body));assert.equal(body.organization_id,'organization');return new Response(JSON.stringify([{id:ids[0]}]));}
  return new Response('[]');
 };
 return {fetchImpl,calls};
}
for(const engine of [scoring,comparison]) {
 let m=mock();assert.equal((await engine({...m,env})(request({},false))).status,401);assert.equal((await engine({...m,env})(request(null))).status,400);
 m=mock({signedIn:false});assert.equal((await engine({...m,env})(request({query:'fridge'}))).status,401);
 m=mock({mapped:false});assert.equal((await engine({...m,env})(request({query:'fridge'}))).status,403);
 m=mock();assert.equal((await engine({...m,env})(request({organization_id:'wrong'}))).status,403);
 assert.equal((await engine({...m,env})(request({conversation_id:'invalid'}))).status,400);
}
let m=mock();let h=scoring({...m,env});assert.equal((await h(request({query:'fridge',weights:{physical_fit:-1}}))).status,400);
let r=await h(request({query:'fridge',profile:{opening_width:30,budget_max:1500}}));assert.equal(r.status,200);let body=await r.json();assert(body.recommendations[0].missing_information.includes('width dimension'));assert(body.recommendations[0].missing_information.includes('verified price'));assert(!body.recommendations[0].strengths.includes('price is within budget'));assert.equal(body.labelled_recommendations.best_value,null);assert.equal(body.labelled_recommendations.best_installation_fit,null);
m=mock({products:[{id:ids[0],model:'TOO-WIDE',width_inches:50,sale_price:1200}]});body=await (await scoring({...m,env})(request({query:'fridge',profile:{opening_width:30}}))).json();assert.deepEqual(body.labelled_recommendations,{});
m=mock();r=await comparison({...m,env})(request({product_ids:ids,profile:{opening_width:30,budget_max:1500}}));assert.equal(r.status,200);body=await r.json();assert.equal(body.comparison_id,ids[0]);assert.equal(body.labelled_results.best_value,null);assert.equal(body.labelled_results.best_installation_fit,null);assert(body.products.every(p=>p.component_scores.physical_fit===70 && p.missing_information.includes('verified price')));
assert(m.calls.some(c=>c.url.includes('aiq_products_app')));assert.equal((await comparison({...m,env})(request({models:['unsafe),x','okay']}))).status,400);
m=mock({fail:true});assert.equal((await comparison({...m,env})(request({product_ids:ids}))).status,502);
console.log('Scoring/comparison tests passed: auth, organization, selection, RLS routing, safe save, missing values, failed dependencies, hard rejection labels.');
