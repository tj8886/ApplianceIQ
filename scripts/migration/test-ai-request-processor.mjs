import assert from 'node:assert/strict';
import {createHandler} from '../../supabase/functions/ai-request-processor/handler.ts';
const req=body=>new Request('https://edge.test',{method:'POST',headers:{Authorization:'Bearer caller'},body:JSON.stringify(body)});
let calls=[],finished=[],governed=0;
const env=n=>({SUPABASE_URL:'https://us.test',SUPABASE_ANON_KEY:'native-anon',SUPABASE_SERVICE_ROLE_KEY:'native-service',ANTHROPIC_API_KEY:'synthetic-provider',AI_MODEL_FAST:'claude-configured-test'}[n]);
function client(url,key,opts){
 if(key==='native-service')return {rpc:async(name,args)=>{assert.equal(name,'aiq_finish_ai_request');assert.equal(args.p_target_user_id,'verified-native');finished.push(args);return {data:{completed:true}};}};
 assert.equal(key,'native-anon');assert.equal(opts.global.headers.Authorization,'Bearer caller');
 return {auth:{getUser:async()=>({data:{user:{id:'verified-native'}}})},rpc:async(name,args)=>{calls.push(name);if(name==='tj_runtime_ai_submit_request'){governed++;return {data:{request_id:'request',session_id:'session',approval_required:true}};}return {data:{assistant:{label:'Test',config:{model_tier:'light'}},knowledge:[],template:null,grounded_context:{}}};},schema:name=>{assert.equal(name,'tj');return {from:()=>({select:()=>({eq:()=>({limit:async()=>({data:[]})})})})};}};
}
let providerCalls=0;
const handler=createHandler({env,createClient:client,fetchImpl:async(url,opts)=>{providerCalls++;assert.equal(url,'https://api.anthropic.com/v1/messages');assert.equal(opts.headers.Authorization,undefined);assert.equal(opts.headers['x-api-key'],'synthetic-provider');const body=JSON.parse(opts.body);assert.equal(body.model,'claude-configured-test');return new Response(JSON.stringify({content:[{type:'text',text:'Advisory answer'}],usage:{input_tokens:20,output_tokens:10}}));}});
assert.equal((await handler(new Request('https://edge.test',{method:'POST'}))).status,401);
assert.equal((await handler(req({assistant_key:'test',prompt:'valid',max_tokens:-1}))).status,400);
const result=await (await handler(req({assistant_key:'test',prompt:'Product question'}))).json();assert.equal(result.output.answer,'Advisory answer');assert.equal(result.output.human_governance.may_execute_without_approval,false);assert.equal(finished[0].p_tokens,30);assert.equal(providerCalls,1);
const noConfig=createHandler({env:n=>n.startsWith('AI_MODEL')?undefined:env(n),createClient:client,fetchImpl:async()=>{throw Error('must not call');}});assert.equal((await noConfig(req({assistant_key:'test',prompt:'Product question'}))).status,503);assert.equal(finished.at(-1).p_error,'model_configuration_unavailable');
const rejected=createHandler({env,createClient:()=>({auth:{getUser:async()=>({data:{user:{id:'user'}}})},rpc:async()=>({error:{code:'42501',message:'private detail'}})}),fetchImpl:async()=>{throw Error('must not call');}});assert.equal((await rejected(req({assistant_key:'test',prompt:'Product question'}))).status,403);
console.log('Governed processor checks passed: caller-scoped context, configured model only, controlled provider request, service-only finalizer, native identity, usage, advisory output and configuration/permission denial.');
