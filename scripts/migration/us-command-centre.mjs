export function migrateCommandCentre(s,page){
 const requireText=(t)=>{if(!s.includes(t))throw Error('Command centre contract changed: '+t);};
 if(page==='index.html'){
  requireText("async function loadAll(period='2026-06')");
  s=s.replace("let currentOrg=null,currentView='overview';",`let currentOrg=null,currentView='overview';
const monthParts=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Toronto',year:'numeric',month:'2-digit'}).formatToParts(new Date());
let selectedPeriod=monthParts.find(p=>p.type==='year').value+'-'+monthParts.find(p=>p.type==='month').value;
function periodLabel(){return new Intl.DateTimeFormat('en-CA',{month:'long',year:'numeric',timeZone:'UTC'}).format(new Date(selectedPeriod+'-01T12:00:00Z'));}`);
  s=s.replaceAll("'2026-06'",'selectedPeriod');
  const moduleStart=s.indexOf('<script type="module">');
  s=s.slice(0,moduleStart).replace('Live Dashboard — June 2026 · All Stores','Illustrative dashboard — example values')+s.slice(moduleStart).replaceAll('June 2026','${periodLabel()}').replace("'June budget: '","periodLabel()+' budget: '");
  const start=s.indexOf('async function renderCC(){'),end=s.indexOf('// Event delegation',start);
  if(start<0||end<0)throw Error('Command centre render contract changed');
  s=s.slice(0,start)+`async function renderCC(){
 const m=$('#ccMain');m.textContent='Loading…';
 try{
  const views={overview:renderOverview,iqscore:renderIQScore,revenue:renderRevenue,warranty:renderWarranty,brands:renderBrands,stores:renderStores,reps:renderReps,coaching:renderCoaching,training:renderTraining,floor:renderFloor,accountability:renderAccountability,leaderboard:renderLeaderboard,ai:renderAI,settings:renderSettings};
  await views[currentView]?.();
  m.insertAdjacentHTML('afterbegin','<div style="margin-bottom:16px"><label>Reporting month <input id="ccReportingMonth" type="month" value="'+selectedPeriod+'"></label><a style="margin-left:16px" href="executive.html">Executive source freshness</a><p style="font-size:12px">Historical months retain their source dates. Missing metrics are shown as —.</p></div>');
  $('#ccReportingMonth').onchange=e=>{if(/^[0-9]{4}-(0[1-9]|1[0-2])$/.test(e.target.value)){selectedPeriod=e.target.value;renderCC();}};
 }catch(e){m.innerHTML='<div style="padding:24px">'+esc(e.message||'Dashboard data could not be loaded.')+'</div>';}
}

`+s.slice(end);
  s=s.replace("allLocs=locR.data??[];","if(locR.error)throw Error('Store access could not be loaded.');allLocs=locR.data??[];");
  s=s.replace('  const corp=corpR.data??[],stores=storeR.data??[];',"  if(corpR.error||storeR.error||repR.error)throw Error('Reporting metrics could not be loaded. Sign in and retry.');\n  const corp=corpR.data??[],stores=storeR.data??[];");
  s=s.replace(".select('user_id').eq('location_id',lv.id)",".select('user_id').eq('location_id',lv.id).eq('is_active',true)");
  // Navigate to the reviewed predictions workflow without fabricating browser forecasts.
  const ai=s.indexOf("  // Run AI button handler"),aiEnd=s.indexOf('\n  bindAckButtons();',ai);
  if(ai<0||aiEnd<0)throw Error('Command centre AI contract changed');
  s=s.slice(0,ai)+`  const predictionButton=document.getElementById('ccRunAI');
  predictionButton.textContent='Open Predictions';predictionButton.onclick=()=>{window.location.href='predictions.html';};
`+s.slice(aiEnd);
  s=s.replace("function iqTotal(rows){return rows.reduce((s,r)=>s+Number(r.earned_points||0),0);}","function iqTotal(rows){return rows.some(r=>r.actual_value!=null&&r.target_value>0)?rows.reduce((s,r)=>s+Number(r.earned_points||0),0):null;}");
  s=s.replace('function iqColor(score){',"function iqColor(score){if(score==null)return 'var(--steel)';").replace('function iqGrade(score){',"function iqGrade(score){if(score==null)return '—';");
  s=s.replaceAll('iqScore.toFixed(1)',"(iqScore==null?'—':iqScore.toFixed(1))").replaceAll('rs.score.toFixed(0)',"(rs.score==null?'—':rs.score.toFixed(0))");
  s=s.replace("${iqScore>=80?'Strong overall performance'", "${iqScore==null?'Insufficient score evidence':iqScore>=80?'Strong overall performance'");
  s=s.replace('function iqRing(score,size,label){',"function iqRing(score,size,label){if(score==null)return '<div style=\"padding:24px;text-align:center\">—<br>Insufficient score evidence</div>';");
 }else if(page==='executive.html'){
  s=s.replace('The connected operating systems are reporting without a currently ranked critical risk.','Observed source records are shown below. Missing evidence is not a clean bill of health.');
  requireText('snapshot.health_score??snapshot.score??50');
  s=s.replace("metric('Training knowledge',training.average_knowledge_score==null?'—':num(training.average_knowledge_score,1), 'Average assessed score')", "metric('Training knowledge',training.average_knowledge_score==null?'—':num(training.average_knowledge_score,1), 'Current-month assessed score'),metric('Lesson completions',num(training.lesson_completions),'Recorded completions; assignment percentage unknown'),metric('Completed tracks',num(training.completed_tracks),`${num(training.started_uncompleted_tracks)} recorded started without completion`)");
  s=s.replace(";$('#riskCount').textContent", ";const integrationRows=metrics.integrations?.connections||[];$('#metrics').innerHTML+='<article class=\"metric\" style=\"grid-column:1/-1\"><div class=\"metric-label\">Integration evidence</div><p>Configuration, completed jobs and received transactions are separate. Cron dispatch does not prove an import.</p>'+ (integrationRows.length?integrationRows.map(c=>'<p><strong>'+esc(c.provider)+'</strong> · Connection: '+esc(c.connection_status)+' · Authentication: '+esc(c.authentication)+' · Recorded completed successful jobs: '+num(c.completed_successful_jobs)+' · Last completed success: '+esc(c.last_completed_success_at||'not recorded')+' · Received POS transactions: '+num(c.received_pos_transactions)+' · Job states: '+esc(JSON.stringify(c.job_status_counts||{}))+(c.has_connection_error?' · Connection error recorded':'')+'</p>').join(''):'<p>No configured connections returned.</p>')+'</article>';$('#riskCount').textContent");

  s=s.replace("metric('Store execution',field.average_store_score==null?'—':num(field.average_store_score,1),`${num(field.critical_open_findings)} critical findings open`)","metric('Store execution',field.average_store_score==null?'—':num(field.average_store_score,1),`Latest recorded 0–100 checklist scores · ${field.latest_score_date||'no score date'}`),metric('Field visits',num(field.visits_total),`Latest inspection: ${field.latest_visit_date||'not recorded'}`)");
  s=s.replace("`${num(field.open_actions)} open actions`", "`${num(field.open_actions)} open · ${num(field.resolved_actions)} recorded resolved/closed; verification not inferred`");
  s=s.replace('Number(snapshot.health_score??snapshot.score??50)','(snapshot.overall_health_score??snapshot.health_score??snapshot.score??null)');
  s=s.replace('Math.max(0,Math.min(100,score))','score==null?0:Math.max(0,Math.min(100,score))');
  s=s.replace('snapshot.evidence_coverage||snapshot.coverage||snapshot.metadata?.evidence_coverage', 'snapshot.coverage_status||snapshot.evidence_coverage||snapshot.coverage||snapshot.metadata?.evidence_coverage');
  s=s.replace('snapshot.confidence_score??snapshot.confidence??snapshot.metadata?.confidence_score','(snapshot.evidence_summary?.confidence_assessed===false?null:snapshot.confidence_score??snapshot.confidence??snapshot.metadata?.confidence_score)');
  s=s.replace("new Date(snapshot.calculated_at||snapshot.created_at||Date.now()).toLocaleString('en-CA')","(snapshot.generated_at||snapshot.calculated_at||snapshot.created_at?new Date(snapshot.generated_at||snapshot.calculated_at||snapshot.created_at).toLocaleString('en-CA'):'not generated')");
  s=s.replace("${esc(snapshot.executive_summary||snapshot.summary||buildSummary(metrics,risks))}","${esc(snapshot.executive_summary||snapshot.summary||buildSummary(metrics,risks))}<div class=\"coverage\">${Object.entries(metrics.sources||{}).map(([name,source])=>esc(name.toUpperCase())+': '+(source.latest_source_at?esc(new Date(source.latest_source_at).toLocaleString('en-CA')):'No received data')+' — '+esc(source.scope||'')).join('<br>')}</div>");
 }
 return s;
}
