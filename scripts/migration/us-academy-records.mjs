export function migrateAcademyRecords(s){
 const read="var { data } = await sb.from('academy_daily_metrics').select('*').eq('user_id', S.user.id).eq('metric_date', today).maybeSingle();\n    row = data;";
 if(!s.includes(read))throw Error('Daily Five loader changed');
 s=s.replace(read,"var r=await sb.rpc('academy_records',{p_payload:{action:'daily_load'}});if(r.error)throw r.error;today=r.data.metric_date;row=r.data.metrics;");
 const start=s.indexOf('async function renderDailyFive('),end=s.indexOf('window.updateDailyMetric = updateDailyMetric;',start);
 if(start<0||end<0)throw Error('Daily Five handler changed');
 var part=s.slice(start,end);
 part=part.replace('} catch(e) {}',"} catch(e) {el.innerHTML='<p>Daily Five could not be loaded.</p><button onclick=\"renderDailyFive(document.getElementById(\'main-content\'))\">Retry</button>';showToast(e.message||'Please retry.');return;}");
 // Retry uses the original render target, without relying on a guessed DOM ID.
 part=part.replace("<button onclick=\"renderDailyFive(document.getElementById(\'main-content\'))\">Retry</button>","<button id=\"daily-five-retry\">Retry</button>");
 part=part.replace("showToast(e.message||'Please retry.');return;","el.querySelector('#daily-five-retry').onclick=function(){renderDailyFive(el);};showToast(e.message||'Please retry.');return;");
 const a=part.indexOf('async function updateDailyMetric(');
 part=part.slice(0,a)+`var dailyMetricPending={};
async function updateDailyMetric(field,delta){
 if(dailyMetricPending[field])return;var el=document.getElementById('sc-'+field);if(!el)return;
 var row=el.parentElement;var buttons=row.querySelectorAll('button');dailyMetricPending[field]=true;buttons.forEach(b=>b.disabled=true);
 try{var req=el._saveRequest;if(!req||req.field!==field||req.delta!==delta)req={action:'daily_delta',field:field,delta:delta,request_id:crypto.randomUUID()};el._saveRequest=req;
 var r=await sb.rpc('academy_records',{p_payload:req});if(r.error)throw r.error;
 var day=r.data.metric_date;if(el.dataset.metricDate&&el.dataset.metricDate!==day){showToast('A new day has started. Reloading Daily Five.');navTo('scorecard');return;}
 el.textContent=r.data.metrics[field];el.dataset.metricDate=day;delete el._saveRequest;
 }catch(e){showToast(e.message||'Activity was not saved. Please retry.');}finally{dailyMetricPending[field]=false;buttons.forEach(b=>b.disabled=false);}
}
`;
 part=part.replace("' id=\"sc-'", "' id=\"sc-'");
 part=part.replace("id=\"sc-' + f[0] + '\"", "id=\"sc-' + f[0] + '\" data-metric-date=\"' + today + '\"");
 s=s.slice(0,start)+part+s.slice(end);
 const old=s.slice(s.indexOf('function checkQuiz(el, correct)'),s.indexOf('\nfunction nextCard()',s.indexOf('function checkQuiz(el, correct)')));
 s=s.replace(old,`async function checkQuiz(el, correct){
 var ps=window._playerState;if(!ps||ps.quizSaving)return;var card=ps.cards[ps.cardIndex];var options=el.parentElement.querySelectorAll('.quiz-opt');ps.quizSaving=true;options.forEach(o=>o.classList.add('disabled'));
 try{var answer=el.textContent;ps.quizRequests=ps.quizRequests||{};var req=ps.quizRequests[card.id];if(!req||req.answer!==answer)req={action:'card_answer',card_id:card.id,answer:answer,request_id:crypto.randomUUID()};ps.quizRequests[card.id]=req;
 var r=await sb.rpc('academy_records',{p_payload:req});if(r.error)throw r.error;
 options.forEach(o=>{if(o.textContent===r.data.correct_option)o.classList.add('correct');else if(o===el)o.classList.add('wrong');});showToast('Quiz answer saved');
 }catch(e){options.forEach(o=>o.classList.remove('disabled'));showToast(e.message||'Quiz answer was not saved. Please retry.');}finally{ps.quizSaving=false;}
}`);
 s=s.replace("function nextCard() { var ps = window._playerState;", "function nextCard() { var ps = window._playerState;if(ps.quizSaving)return;");
 s=s.replace("function prevCard() { var ps = window._playerState;", "function prevCard() { var ps = window._playerState;if(ps.quizSaving)return;");
 s=s.replace("async function loadCurriculum() {", "async function loadAcademyTracks(){var r=await sb.rpc('academy_records',{p_payload:{action:'tracks_load'}});if(r.error)throw r.error;S.learningTracks=r.data.tracks;}\nasync function loadCurriculum() {");
 s=s.replace('  updateCurrProgressPill();\n}', '  await loadAcademyTracks();updateCurrProgressPill();\n}');
 s=s.replace('   updateCurrProgressPill();renderCurrSidebar();', "   try{await loadAcademyTracks();}catch(e){showToast('Lesson saved; track display could not refresh.');}updateCurrProgressPill();renderCurrSidebar();");
 s=s.replace('  nav.innerHTML = S.volumes.map(function(vol) {', `  nav.innerHTML = '<div style="padding:12px"><strong>Learning tracks</strong>'+(S.learningTracks||[]).map(t=>'<div>'+esc(t.name)+': '+(t.completed_at?'Completed':t.started_at?'In progress':'Not started')+'</div>').join('')+'</div>'+S.volumes.map(function(vol) {`);
 return s;
}
