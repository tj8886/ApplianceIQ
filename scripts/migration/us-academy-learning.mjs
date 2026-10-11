export function migrateAcademyLearning(s){
 const a=s.indexOf('function trackEvent(type, data) {'),b=s.indexOf('\n// ═',a);if(a<0||b<0)throw Error('Learning event handler changed');
 s=s.slice(0,a)+`var learningSaveQueue=[];var learningSaveRunning=false;
function learningSaveNotice(message){var box=document.getElementById('learning-save-notice');if(!box){box=document.createElement('div');box.id='learning-save-notice';box.setAttribute('role','status');box.style.cssText='position:fixed;bottom:20px;left:20px;z-index:9999;background:white;color:#15243b;padding:12px;border:1px solid #b45309;border-radius:8px;max-width:360px';box.innerHTML='<span></span> <button type="button">Retry saving</button>';box.querySelector('button').onclick=flushLearningSaves;document.body.appendChild(box);}box.querySelector('span').textContent=message;box.style.display='block';}
async function flushLearningSaves(){if(learningSaveRunning)return;learningSaveRunning=true;
 try{var count=0;while(learningSaveQueue.length&&count<20){var item=learningSaveQueue[0];if(!S.user||item.actor!==S.user.id){learningSaveNotice('Sign in with the original account to retry activity saves.');return;}var r=await sb.rpc('academy_learning',{p_payload:item.payload});if(r.error)throw r.error;if(r.data?.saved!==true)throw Error('Activity save was not confirmed');learningSaveQueue.shift();count++;}var box=document.getElementById('learning-save-notice');if(box)box.style.display='none';}
 catch(e){learningSaveNotice('Learning activity was not saved. Retry before leaving this page.');}finally{learningSaveRunning=false;}
}
function trackEvent(type,data){if(!S.user)return;if(learningSaveQueue.length>=20){learningSaveNotice('Activity saves are waiting. Retry before opening more courses or submitting more questions.');return;}
 learningSaveQueue.push({actor:S.user.id,payload:{action:'record',request_id:crypto.randomUUID(),event_type:type,course_key:data.course_key||null,content:data.content||null}});flushLearningSaves();
}
`+s.slice(b);
 s=s.replace("sb.from('academy_learning_events').select('event_type,pillar,content,metadata,created_at').order('created_at', { ascending: false }).limit(100)","sb.rpc('academy_learning',{p_payload:{action:'feed'}})");
 s=s.replace('  var events = eventsRes.data || [];',"  if(eventsRes.error){el.innerHTML='<p>Learning analytics could not be loaded. Please retry.</p>';return;}var events=eventsRes.data?.events||[];");
 s=s.replace('Last 100 tracked',"Last 100 received · '+esc(eventsRes.data?.scope||'Your activity')+'");
 s=s.replace("sb.from('academy_progress').select('chapter_id')", "sb.from('academy_progress').select('chapter_id').not('completed_at','is',null)");
 s=s.replace('Across all users','Your recorded completions');
 return s;
}
