export function migrateAcademyActivity(s){
 const load="var { data: prog } = await sb.from('academy_progress').select('chapter_id').eq('user_id', S.user.id);";
 if(!s.includes(load))throw Error('Academy progress loader changed');
 s=s.replace(load,"var activity=await sb.rpc('academy_activity',{p_payload:{action:'load'}});if(activity.error)throw activity.error;var prog=(activity.data?.progress||[]).filter(r=>r.completed_at!=null);");
 s=s.replace("var { data: qs } = await sb.from('academy_quiz_scores').select('*').eq('user_id', S.user.id);","var qs=activity.data?.quiz_scores||[];");
 const a=s.indexOf('async function toggleChapterComplete(chId, slug) {'),b=s.indexOf('\nwindow.toggleChapterComplete',a);
 if(a<0||b<0)throw Error('Academy completion handler changed');
 return s.slice(0,a)+`async function toggleChapterComplete(chId, slug) {
  chId=Number(chId);var btn=document.getElementById('complete-btn');if(btn?.disabled)return;if(btn)btn.disabled=true;
  try{
   var complete=!S.completedChapterIds.has(chId);var r=await sb.rpc('academy_activity',{p_payload:{action:'set_lesson',chapter_id:chId,completed:complete}});if(r.error)throw r.error;
   if(r.data?.completed_at){S.completedChapterIds.add(chId);}else{S.completedChapterIds.delete(chId);}
   if(btn){btn.textContent=S.completedChapterIds.has(chId)?'✓ Completed':'Mark as Complete';btn.classList.toggle('done',S.completedChapterIds.has(chId));}
   updateCurrProgressPill();renderCurrSidebar();var item=document.querySelector('.ch-item[data-slug="'+slug+'"]');if(item)item.classList.toggle('completed',S.completedChapterIds.has(chId));
  }catch(e){showToast(e.message||'Progress could not be saved. Please retry.');}finally{if(btn)btn.disabled=false;}
}
`+s.slice(b);
}
