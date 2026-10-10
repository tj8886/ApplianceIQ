import assert from 'node:assert/strict';
import {createHandler} from '../../supabase/functions/conversation-memory-engine/handler.ts';
const org='11111111-1111-4111-8111-111111111111',id='22222222-2222-4222-8222-222222222222';
const env=n=>({SUPABASE_URL:'https://destination.invalid',SUPABASE_ANON_KEY:'public-key',ANTHROPIC_API_KEY:'provider-test'})[n];
const req=(body,auth=true)=>new Request('https://example.invalid',{method:'POST',headers:{'Content-Type':'application/json',...(auth?{Authorization:'Bearer native-session'}:{})},body:JSON.stringify(body)});
function mock({mapped=true,signedIn=true,foreign=false,conflict=false}={}) {
 const calls=[];
 const fetchImpl=async(url,options)=>{
  calls.push({url,options});assert(url.startsWith('https://destination.invalid/'));assert.equal(options.headers.Authorization,'Bearer native-session');assert.equal(options.headers.apikey,'public-key');
  if(url.includes('/auth/v1/user'))return new Response('{}',{status:signedIn?200:401});
  const body=JSON.parse(options.body);assert(!('user_id' in body));
  if(url.endsWith('tj_runtime_my_platform_context'))return new Response(JSON.stringify(mapped?{organization_id:org}:{}));
  if(url.endsWith('tj_product_conversation_state'))return new Response(JSON.stringify(foreign?{code:'42501'}:{conversation_id:id,memory_version:3,profile:{},stage:'discovery'}),{status:foreign?403:200});
  assert(url.endsWith('tj_commit_product_conversation'));assert.equal(body.p_expected_version,3);
  return new Response(JSON.stringify(conflict?{code:'40001'}:{conversation_id:id,memory_version:4,profile:body.p_facts,stage:'discovery',completeness_score:40,contradictions:[]}),{status:conflict?400:200});
 };
 return {fetchImpl,calls};
}
let m=mock(),h=createHandler({...m,env});assert.equal((await h(req({},false))).status,401);assert.equal((await h(req(null))).status,400);assert.equal((await h(req({message:'fridge',conversation_id:'invalid'}))).status,400);
for(const [settings,status] of [[{signedIn:false},401],[{mapped:false},403],[{foreign:true},403],[{conflict:true},409]]) {m=mock(settings);assert.equal((await createHandler({...m,env})(req({message:'fridge'}))).status,status);}
m=mock();h=createHandler({...m,env});let r=await h(req({message:'black stainless fridge budget $1500 opening 30 inches MODEL123'}));assert.equal(r.status,200);let body=await r.json();assert.equal(body.profile.budget_max,1500);assert.equal(body.profile.opening_width,30);assert.equal(body.profile.finish,'black stainless');assert.equal(body.memory_version,4);assert.equal(m.calls.length,4);
r=await h(req({message:'fridge under 36 inches RF263BEAESR'}));body=await r.json();assert.equal(body.profile.budget_max,undefined);
assert.equal((await h(req({message:'fridge',stage:'forged'}))).status,400);assert.equal((await h(req({message:'fridge',crm_record_id:id}))).status,400);
console.log('Conversation handler tests passed: auth, mapped org, ownership, conflict, deterministic extraction, model routing and atomic save contract.');
