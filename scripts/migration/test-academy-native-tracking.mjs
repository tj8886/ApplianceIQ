import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';import vm from 'node:vm';import {migrateAcademyActivity} from './us-academy-activity.mjs';
const s=migrateAcademyActivity(readFileSync('apps/iq-training/index.html','utf8'));
assert.ok(!s.includes("from('academy_progress').delete()"));assert.ok(!s.includes("from('academy_progress').insert("));assert.ok(s.includes("rpc('academy_activity'"));
const button={disabled:false,classList:{toggle(){}},textContent:''};let fail=false;let requests=[];const context=vm.createContext({Number,S:{user:{id:'native-id'},completedChapterIds:new Set()},document:{getElementById:()=>button,querySelector:()=>null},sb:{rpc:async(name,args)=>{requests.push({name,args});return fail?{error:{message:'Source save failed'}}:{data:{completed_at:args.p_payload.completed?'2026-10-11T00:00:00Z':null}};}},updateCurrProgressPill(){},renderCurrSidebar(){},showToast(){}});
const fn=s.slice(s.indexOf('async function toggleChapterComplete('),s.indexOf('\nwindow.toggleChapterComplete'));new vm.Script(fn).runInContext(context);
await new vm.Script("toggleChapterComplete('1','fixture')").runInContext(context);assert.ok(context.S.completedChapterIds.has(1));assert.equal(requests[0].args.p_payload.chapter_id,1);assert.ok(!('user_id' in requests[0].args.p_payload));
fail=true;await new vm.Script("toggleChapterComplete('1','fixture')").runInContext(context);assert.ok(context.S.completedChapterIds.has(1));assert.equal(button.disabled,false);
fail=false;await new vm.Script("toggleChapterComplete('1','fixture')").runInContext(context);assert.ok(!context.S.completedChapterIds.has(1));
console.log('Native lesson UI: mapped RPC, numeric IDs, confirmed state, failure preservation and unmark without delete passed');
