import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import {migrateCommandCentre} from './us-command-centre.mjs';
for(const page of ['index.html','executive.html']){
 const s=migrateCommandCentre(readFileSync('apps/command-center/'+page,'utf8'),page);
 for(const m of s.matchAll(/<script type="module">([\s\S]*?)<\/script>/g)){let js=m[1].replace(/^import.*;\s*$/gm,'');if(js.trim())new vm.Script('(async()=>{'+js+'})');}
 if(page==='index.html'){
  assert.ok(!s.includes("'2026-06'"));assert.ok(s.includes('ccReportingMonth'));assert.ok(s.includes('Illustrative dashboard'));
  assert.ok(!s.includes("from('ai_budget_predictions').insert"));assert.ok(!s.includes("model:'gpt-5.6-luna'"));assert.ok(s.includes("location.href='predictions.html'"));
 }else{
  assert.ok(s.includes('snapshot.overall_health_score'));assert.ok(!s.includes('??50'));assert.ok(!s.includes('||Date.now()'));assert.ok(s.includes('metrics.sources'));
  const elements=new Map();const $=key=>{if(!elements.has(key))elements.set(key,{});return elements.get(key);};
  const ctx=vm.createContext({$,currentOrg:{name:'Fixture'},unpack:x=>x,esc:String,statusText:x=>x,num:x=>x==null?'—':String(x),pct:x=>x==null?'—':String(x)+'%',money:x=>x==null?'—':String(x),metric:()=>'',insightCard:()=>'',buildSummary:()=>'',Date,Object,Math,Number});
  const render=s.slice(s.indexOf('function render(raw)'),s.indexOf('function buildSummary'));
  new vm.Script(render).runInContext(ctx);
  ctx.input={snapshot:{overall_health_score:null,health_status:'unknown',generated_at:'2026-07-30T02:14:54Z',evidence_summary:{confidence_assessed:false},coverage_status:'insufficient',metrics:{sources:{up:{latest_source_at:'2026-07-25T12:00:00Z',scope:'source visits'}}}}};
  new vm.Script('render(input)').runInContext(ctx);
  assert.ok(elements.get('#hero').innerHTML.includes('<strong>—</strong>'));
  assert.ok(elements.get('#hero').innerHTML.includes('UP:'));
  assert.ok(elements.get('#hero').innerHTML.includes('Confidence: —'));
  assert.ok(elements.get('#subtitle').textContent.includes('2026'));
 }
}
console.log('Command centre: current/historical month control, generated syntax, observed score/source dates and prediction navigation passed');
