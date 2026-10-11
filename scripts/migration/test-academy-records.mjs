import assert from 'node:assert/strict';import fs from 'node:fs';import vm from 'node:vm';import {migrateAcademyActivity} from './us-academy-activity.mjs';import {migrateAcademyRecords} from './us-academy-records.mjs';
const html=migrateAcademyRecords(migrateAcademyActivity(fs.readFileSync('apps/iq-training/index.html','utf8')));
for(const m of html.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/g)){const code=m[1].replace(/^import .*$/gm,'');new vm.Script('(async()=>{'+code+'})()');}
assert.ok(html.includes('data-metric-date="'));assert.ok(!html.includes("from('academy_daily_metrics').upsert"));
const notices=[];const buttons=[{}];const el={textContent:'3',dataset:{metricDate:'2026-10-11'},parentElement:{querySelectorAll:()=>buttons}};let fail=true;let requests=[];
const ctx=vm.createContext({document:{getElementById:()=>el},crypto:{randomUUID:()=> 'request-fixture'},showToast:m=>notices.push(m),navTo(){},sb:{rpc:async(n,a)=>{requests.push(a.p_payload);return fail?{error:{message:'Save failed'}}:{data:{metric_date:'2026-10-11',metrics:{touches:4}}};}}});
new vm.Script(html.slice(html.indexOf('var dailyMetricPending='),html.indexOf('window.updateDailyMetric = updateDailyMetric;'))).runInContext(ctx);
await new vm.Script("updateDailyMetric('touches',1)").runInContext(ctx);assert.equal(el.textContent,'3');assert.equal(buttons[0].disabled,false);const req=el._saveRequest;
fail=false;await new vm.Script("updateDailyMetric('touches',1)").runInContext(ctx);assert.equal(el.textContent,4);assert.equal(requests[1].request_id,req.request_id);assert.ok(!('user_id' in requests[1]));
const options=['wrong','correct'].map(textContent=>({textContent,classList:{v:new Set(),add(x){this.v.add(x)},remove(x){this.v.delete(x)}}}));options[0].parentElement={querySelectorAll:()=>options};let quizFail=true;
Object.assign(ctx,{window:{_playerState:{cardIndex:0,cards:[{id:7}]}},sb:{rpc:async()=>quizFail?{error:{message:'Quiz failed'}}:{data:{correct:false,correct_option:'correct'}}}});
new vm.Script(html.slice(html.indexOf('async function checkQuiz('),html.indexOf('\nfunction nextCard()',html.indexOf('async function checkQuiz(')))).runInContext(ctx);
ctx.choice=options[0];await new vm.Script("checkQuiz(choice,'client-supplied-answer')").runInContext(ctx);assert.ok(!options[0].classList.v.has('disabled'));assert.ok(!options[0].classList.v.has('wrong'));
quizFail=false;await new vm.Script("checkQuiz(choice,'client-supplied-answer')").runInContext(ctx);assert.ok(options[0].classList.v.has('wrong'));assert.ok(options[1].classList.v.has('correct'));
assert.ok(html.includes('Learning tracks'));assert.ok(html.includes("await loadAcademyTracks()"));console.log('Academy records: generated syntax, confirmed metric saves, safe retries, failed quiz retry and server grading, track display passed');
