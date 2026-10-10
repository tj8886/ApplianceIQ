import assert from 'node:assert/strict';
import {createHandler as ai} from '../../supabase/functions/ai-roleplay/handler.ts';
import {createHandler as performance} from '../../supabase/functions/performance-roleplay/handler.ts';
const org='11111111-1111-4111-8111-111111111111';const native='native';const source='source';
let mapped=true,governed=true,stale=false,providerCalls=0,commits=[],finished=[],sessions=new Map();
const persona={persona_name:'TJ',persona_role:'Coach',tone:'clear',prompt_prefix:'Advisory coach',organization_id:org};
const scenario={id:'scenario',code:'discovery',title:'Discovery',difficulty:2,context:'Synthetic training',competency_weights:{discovery:1},opening_line:'Synthetic opening',hidden_facts:[],objections:[],customer_profile:{}};
const db={from:table=>{let filters=[],single=false;const q={};for(const m of ['select','order','limit','in','ilike','or','is'])q[m]=()=>q;q.eq=(k,v)=>{filters.push([k,v]);return q;};for(const m of ['maybeSingle','single'])q[m]=()=>{single=true;return q;};q.then=resolve=>{let rows=table==='ai_roleplay_sessions'?[...sessions.values()].map(s=>structuredClone(s)):table==='organization_members'?[{id:'member',organization_id:org,user_id:source,status:'active'}]:table==='ai_personas'?[persona]:table==='performance_roleplay_links'?[{scenario_id:'scenario',ai_roleplay_session_id:'perf',organization_id:org,user_id:source}]:table==='performance_scenarios'?[scenario]:[];rows=rows.filter(r=>filters.every(([k,v])=>r[k]===undefined||r[k]===v));return resolve({data:single?rows[0]??null:rows,error:null});};return q;}};
const client=(url,key)=>key==='service'?{rpc:async(name,args)=>{
 if(name==='aiq_finish_ai_request'){finished.push(args);assert.equal(args.p_target_user_id,native);return{data:{}};}
 assert.equal(name,'aiq_commit_roleplay_session');assert.equal(args.p_native_user,native);
 if(stale)return{error:{code:'40001'}};let id=args.p_session_id;if(!id){id='started';sessions.set(id,{id,organization_id:org,user_id:source,status:'active',total_turns:0,transcript:[],scenario_type:args.p_patch.scenario_type});}
 else assert.deepEqual(args.p_expected_transcript,sessions.get(id).transcript??[]);
 Object.assign(sessions.get(id),structuredClone(args.p_patch));commits.push(args);return{data:{id}};
}}:{auth:{getUser:async()=>({data:{user:{id:native}}})},schema:()=>db,rpc:async name=>name==='tj_runtime_my_platform_context'?{data:mapped?{organization_id:org,source_user_id:source}:{} }:name==='tj_runtime_ai_submit_request'?governed?{data:{request_id:'request'}}:{error:{code:'42501'}}:{data:{}}};
const env=n=>({SUPABASE_URL:'https://us.test',SUPABASE_ANON_KEY:'anon',SUPABASE_SERVICE_ROLE_KEY:'service',AI_MODEL_STANDARD:'claude-configured-test',ANTHROPIC_API_KEY:'synthetic'}[n]);
const fetchImpl=async(url,opts)=>{providerCalls++;assert.equal(url,'https://api.anthropic.com/v1/messages');const body=JSON.parse(opts.body);assert.equal(body.messages[0].role,'user');let text=body.system.includes('Score the rep')?'{"kpi_scores":{"Discovery":8,"forged":99},"coaching_tip":"Ask a discovery question"}':body.system.includes('Performance Brain')?'{"scores":{"discovery":80,"forged":999},"feedback":"Synthetic feedback"}':'Synthetic customer response';return new Response(JSON.stringify({content:[{type:'text',text}],usage:{input_tokens:2,output_tokens:3}}));};
const a=ai({createClient:client,env,fetchImpl});const p=performance({createClient:client,env,fetchImpl});
const req=body=>new Request('https://edge.test',{method:'POST',headers:{Authorization:'Bearer caller'},body:JSON.stringify(body)});
assert.equal((await a(new Request('https://edge.test',{method:'POST'}))).status,401);
mapped=false;assert.equal((await a(req({action:'start',scenario_type:'cold_call',organization_id:org}))).status,403);mapped=true;assert.equal(providerCalls,0);
governed=false;assert.equal((await a(req({action:'start',scenario_type:'cold_call',organization_id:org}))).status,403);governed=true;assert.equal(providerCalls,0);
let r=await a(req({action:'start',scenario_type:'cold_call',organization_id:org}));assert.equal(r.status,200);assert.equal((await r.json()).session_id,'started');
r=await a(req({action:'message',session_id:'started',rep_message:'How can I help?'}));assert.equal(r.status,200);assert.deepEqual((await r.json()).kpi_scores,{Discovery:8});assert.equal(sessions.get('started').transcript.length,3);
r=await a(req({action:'end',session_id:'started'}));assert.equal(r.status,200);assert.equal(sessions.get('started').status,'completed');const before=providerCalls;assert.equal((await a(req({action:'end',session_id:'started'}))).status,200);assert.equal(providerCalls,before);
sessions.set('perf',{id:'perf',organization_id:org,user_id:source,scenario_type:'discovery',status:'active',transcript:[],mode:'you_sell'});
r=await p(req({action:'opening',session_id:'perf'}));assert.equal(r.status,200);assert.equal((await r.json()).customer_response,'Synthetic opening');
r=await p(req({action:'message',session_id:'perf',message:'What do you need?'}));assert.equal(r.status,200);assert.equal(sessions.get('perf').transcript.length,3);
stale=true;assert.equal((await p(req({action:'message',session_id:'perf',message:'Concurrent response'}))).status,409);stale=false;
r=await p(req({action:'end',session_id:'perf'}));assert.equal(r.status,200);const data=await r.json();assert.deepEqual(data.scores,{discovery:80});assert.equal(data.session_score,80);assert.equal(sessions.get('perf').status,'completed');
assert.equal(commits.some(c=>c.p_patch.user_id||c.p_patch.organization_id),false);assert.ok(finished.length>0);
console.log('Both roleplay handlers passed: mapped identity, governance denial before provider, source-compatible start/message/end, native finalizer, caller-scoped reads, expected transcript commits, stale denial, score validation and completed-session idempotency.');
