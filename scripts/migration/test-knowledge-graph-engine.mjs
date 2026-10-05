import assert from 'node:assert/strict';
import {createHandler} from '../../supabase/functions/knowledge-graph-engine/handler.ts';
const org='11111111-1111-4111-8111-111111111111';
const env=n=>({SUPABASE_URL:'https://destination.invalid',SUPABASE_ANON_KEY:'public-key'})[n];
const req=(body,auth=true)=>new Request('https://example.invalid',{method:'POST',headers:{'Content-Type':'application/json',...(auth?{Authorization:'Bearer native-session'}:{})},body:JSON.stringify(body)});
function mock({signedIn=true,denied=false}={}){
 const calls=[];const fetchImpl=async(url,options)=>{
  calls.push({url,options});assert(url.startsWith('https://destination.invalid/'));assert.equal(options.headers.Authorization,'Bearer native-session');assert.equal(options.headers.apikey,'public-key');
  if(url.includes('/auth/v1/user'))return new Response('{}',{status:signedIn?200:401});
  assert(url.includes('/rpc/'));const body=JSON.parse(options.body);assert.equal(body.p_org,org);assert(!('user_id' in body));
  return new Response(JSON.stringify(denied?{code:'42501'}:url.endsWith('tj_sync_product_graph')?{nodes:2,edges:1}:{ok:true,mode:'lookup',nodes:[],relationships:[]}),{status:denied?403:200});
 };return{fetchImpl,calls};
}
let m=mock(),h=createHandler({...m,env});assert.equal((await h(req({},false))).status,401);assert.equal((await h(req(null))).status,400);assert.equal((await h(req({organization_id:'invalid'}))).status,400);assert.equal((await h(req({organization_id:org,limit:-1}))).status,400);assert.equal((await h(req({organization_id:org,product_ids:['bad']}))).status,400);
let r=await h(req({organization_id:org,query:'fridge'}));assert.equal(r.status,200);assert(m.calls[1].url.endsWith('tj_product_graph_lookup'));
r=await h(req({organization_id:org,sync:true}));assert.equal((await r.json()).mode,'sync');assert(m.calls[3].url.endsWith('tj_sync_product_graph'));
m=mock({denied:true});assert.equal((await createHandler({...m,env})(req({organization_id:org,sync:true}))).status,403);
m=mock({signedIn:false});assert.equal((await createHandler({...m,env})(req({organization_id:org}))).status,401);
console.log('Knowledge graph handler tests passed: auth, request validation, guarded RPC lookup/sync, caller forwarding and access denial.');
