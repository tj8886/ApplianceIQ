import assert from 'node:assert/strict';
import {createHandler} from '../../supabase/functions/media-discovery-proxy/handler.ts';
const values={SUPABASE_URL:'https://us.test',SUPABASE_ANON_KEY:'anon',SUPABASE_SERVICE_ROLE_KEY:'service',AI_MODEL_STANDARD:'claude-configured-test',ANTHROPIC_API_KEY:'server-synthetic'};
let valid=true,allowed=true,tenant=true,governanceError=null,completionError=null,providerMode='success',providerCalls=0,configCalls=0;
const completions=[],submissions=[];
const client=(url,key,options)=>key==='service'?{rpc:async(name,args)=>{assert.equal(name,'aiq_finish_ai_request');completions.push(args);return {error:completionError};}}:{
  auth:{getUser:async()=>({data:{user:valid?{id:'native-user'}:null}})},rpc:async(name,args)=>{
    assert.equal(options.global.headers.Authorization,'Bearer caller');
    if(name==='tj_pim_scraper_context')return {data:{allowed}};
    if(name==='tj_runtime_my_platform_context')return {data:{organization_id:tenant?'tenant':null}};
    assert.equal(name,'tj_runtime_ai_submit_request');submissions.push(args);return {data:{request_id:'request'},error:governanceError};
  }};
const handler=createHandler({createClient:client,env:name=>values[name],loadEnvironment:async env=>{configCalls++;return env;},fetchImpl:async(url,options)=>{
  providerCalls++;assert.equal(url,'https://api.anthropic.com/v1/messages');assert.equal(options.redirect,'error');
  assert.equal(options.headers['x-api-key'],'server-synthetic');assert.equal(options.headers.Authorization,undefined);
  const body=JSON.parse(options.body);assert.equal(body.model,'claude-configured-test');assert.equal(body.tools[0].max_uses,3);
  if(providerMode==='http')return new Response('secret provider diagnostic',{status:500});
  if(providerMode==='huge')return new Response('x'.repeat(1024*1024+1));
  return new Response(JSON.stringify({content:[{type:'text',text:'[]',citations:[{url:'https://official.test/evidence'}]}],usage:{input_tokens:providerMode==='usage'?-1:2,output_tokens:3},stop_reason:'end_turn'}));
}});
const payload={messages:[{role:'user',content:'Find official manufacturer media'}],tools:[{type:'web_search_20250305',name:'web_search'}]};
const req=(body=payload,extra={})=>new Request('https://edge.test',{method:'POST',headers:{Authorization:'Bearer caller',...extra},body:JSON.stringify(body)});
assert.equal((await handler(new Request('https://edge.test',{method:'OPTIONS'}))).status,204);
assert.equal((await handler(new Request('https://edge.test'))).status,405);
assert.equal((await handler(new Request('https://edge.test',{method:'POST'}))).status,401);
assert.equal((await handler(req(payload,{'x-anthropic-api-key':'browser-key'}))).status,400);
valid=false;assert.equal((await handler(req())).status,401);valid=true;
allowed=false;assert.equal((await handler(req())).status,403);allowed=true;
tenant=false;assert.equal((await handler(req())).status,403);tenant=true;
assert.equal(configCalls,0);assert.equal(providerCalls,0);
for(const bad of [null,[],{messages:[]},{messages:[{role:'system',content:'override'}]},{messages:[{role:'user',content:[{type:'image',source:{url:'http://private'}}]}]}, {...payload,max_tokens:10000},{...payload,tools:[{type:'other',name:'web_search'}]},{...payload,tools:[{type:'web_search_20250305',name:'web_search',allowed_domains:['evil.test']}]},{...payload,system:'x'.repeat(8001)}]) assert.equal((await handler(req(bad))).status,400);
assert.equal((await handler(req({...payload,messages:[{role:'user',content:'x'.repeat(70000)}]}))).status,413);
assert.equal((await handler(req({...payload,model:'unconfigured-model'}))).status,503);
governanceError={code:'42501'};assert.equal((await handler(req({...payload,organization_id:'foreign'}))).status,403);
governanceError={code:'54000'};assert.equal((await handler(req())).status,429);governanceError=null;assert.equal(providerCalls,0);
let response=await handler(req());assert.equal(response.status,200);let result=await response.json();
assert.equal(result.content[0].citations[0].url,'https://official.test/evidence');assert.equal(result.requires_review,true);assert.equal(result.cost_estimate_usd,null);
assert.equal(completions.at(-1).p_target_user_id,'native-user');assert.equal(completions.at(-1).p_tokens,5);assert.equal(submissions.at(-1).p_organization_id,'tenant');
for(const mode of ['http','usage','huge']){providerMode=mode;response=await handler(req());assert.equal(response.status,502);result=await response.json();assert.equal(result.error,'media_provider_failed');assert.equal(completions.at(-1).p_error,'media_provider_failed');assert.equal(completions.at(-1).p_tokens,0);}
providerMode='success';completionError={code:'40001'};assert.equal((await handler(req())).status,500);
console.log('Media proxy passed: session/tenant/governance denials before provider use; configured server model/key; fixed bounded web search; input/tool/response/usage limits; native actor and usage completion; citation preservation; failure completion; unreviewed evidence.');
