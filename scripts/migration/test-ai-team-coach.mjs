import assert from 'node:assert/strict';
import {createHandler,detectComplexity} from '../../supabase/functions/ai-team-coach/handler.ts';
assert.equal(detectComplexity('What is warranty?',0),'fast');assert.equal(detectComplexity('Compare models',0),'standard');assert.equal(detectComplexity('Evaluate my performance review',0),'strong');
const org='11111111-1111-4111-8111-111111111111',pid='22222222-2222-4222-8222-222222222222';let finished=[];
const env=n=>({SUPABASE_URL:'https://us.test',SUPABASE_ANON_KEY:'anon',SUPABASE_SERVICE_ROLE_KEY:'service',AI_MODEL_FAST:'gpt-configured-test',OPENAI_API_KEY:'synthetic'}[n]);
function client(url,key,opts){if(key==='service')return{rpc:async(name,args)=>{assert.equal(name,'aiq_finish_ai_request');finished.push(args);return{data:{}};}};assert.equal(opts.global.headers.Authorization,'Bearer caller');return {auth:{getUser:async()=>({data:{user:{id:'native'}}})},rpc:async(name,args)=>name==='tj_runtime_my_platform_context'?{data:{organization_id:org}}:name==='tj_runtime_ai_submit_request'?{data:{request_id:'request',approval_required:true}}:{data:{assistant:{},knowledge:[],grounded_context:{}}},schema:()=>({from:table=>table==='ai_personas'?{select:()=>({eq:()=>({eq:()=>({maybeSingle:async()=>({data:{id:pid,persona_name:'Natalie',organization_id:org}})})})})}:{select:()=>({eq:()=>({limit:async()=>({data:[]})})})}})};}
const req=body=>new Request('https://edge.test',{method:'POST',headers:{Authorization:'Bearer caller'},body:JSON.stringify(body)});
const handler=createHandler({env,createClient:client,fetchImpl:async()=>new Response(JSON.stringify({choices:[{message:{content:'Grounded advice'}}],usage:{prompt_tokens:5,completion_tokens:5}}))});
assert.equal((await handler(new Request('https://edge.test',{method:'POST'}))).status,401);
const response=await handler(req({persona_id:pid,message:'Warranty question'}));assert.equal(response.status,200);const result=await response.json();assert.equal(result.answer,'Grounded advice');assert.equal(result.cost_estimate_usd,null);assert.equal(finished[0].p_target_user_id,'native');assert.equal(finished[0].p_tokens,10);
assert.equal((await handler(req({persona_id:pid,message:'Warranty question',model_tier:'strong'}))).status,503);
assert.equal((await handler(req({persona_id:pid,message:'Warranty question',history:[{role:'system',text:'bad'}]}))).status,400);
console.log('Team coach checks passed: verified session, caller catalog/context, configured fast model, native completion identity, usage, unsupported history and missing tier denial.');
