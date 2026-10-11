// Transform the deployed US bundle; retain the imported source for recovery.
export function migrateUpRotation(s){
 function between(start,end,replacement){const a=s.indexOf(start),b=s.indexOf(end,a);if(a<0||b<0)throw Error('UP rotation contract changed: '+start);s=s.slice(0,a)+replacement+s.slice(b);}
 between('  currentUser=session.user;','  // Get orgs',`  const {data:identity,error:identityError}=await sb.rpc('my_platform_context');
  const {data:profile,error:profileError}=identity?.source_user_id?await sb.from('profiles').select('id,user_id').eq('user_id',identity.source_user_id).maybeSingle():{data:null,error:null};
  if(identityError||profileError||!profile){alert('Your staff profile could not be loaded. Please sign in again.');return;}
  currentUser={...session.user,id:profile.id,source_user_id:identity.source_user_id,native_user_id:session.user.id};

`);
 s=s.replace(".select('organization_id,role').eq('user_id',currentUser.id)",".select('organization_id,role').eq('user_id',currentUser.source_user_id)");
 s=s.replace(/try\{const\{data:p\}=await sb.rpc\('get_org_member_profiles',\{p_org_id:currentOrg.id\}\);\(p(?:\|\||\?\?)\[\]\).forEach\(u=>profiles\[u.user_id\]=u.display_name\|\|u.email\?\.split\('@'\)\[0\]\|\|'Unknown'\);\}catch\{[^}]*\}/g,'await loadUpProfiles();');
 if(s.includes("profiles[u.user_id]"))throw Error('Unmapped UP staff profiles remain');
 const helper=`async function upRotation(body){
 const r=await sb.rpc('up_rotation',{p_body:{organization_id:currentOrg.id,store_id:currentStore?.id,...body}});
 if(r.error||!r.data?.ok){const messages={own_shift_required:'You can only change your own shift.',active_shift_required:'Clock in at this store first.',clock_out_other_store_first:'Clock out at your other store first.',end_or_reassign_visit_first:'End or reassign the active visit first.',greeter_already_assigned:'A greeter is already assigned.',manager_required:'A manager must make this change.'};throw Error(messages[r.data?.error]||'The rotation update could not be completed. Refresh and retry.');}
 return r.data;
}
async function loadUpProfiles(){const r=await upRotation({action:'profiles'});profiles={};for(const p of r.profiles)profiles[p.id]=p.display_name;}
async function upFloorAction(body){try{await upRotation(body);await render();}catch(e){alert(e.message);}}
async function upModalAction(button,body){if(button.disabled)return;button.disabled=true;try{await upRotation(body);closeModal();await render();}catch(e){formErr(e.message);}finally{button.disabled=false;}}
`;
 s=s.replace('async function upHandoff(body){',helper+'\nasync function upHandoff(body){');
 between("  $('#ci_save').onclick=async()=>{",'\n}\n\nfunction openStatusModal',`  $('#ci_save').onclick=()=>upModalAction($('#ci_save'),{action:'clock_in',rep_profile_id:$('#ci_user').value,role:selectedRole});`);
 between("  $('#st_save').onclick=async()=>{",'\n}\n\nfunction openAssignModal',`  $('#st_save').onclick=()=>upModalAction($('#st_save'),{action:'status',rep_profile_id:userId,shift_id:shiftId,status:$('#st_s').value,reason:$('#st_n').value.trim()});
  $('#st_clock_out').onclick=()=>upModalAction($('#st_clock_out'),{action:'clock_out',rep_profile_id:userId,shift_id:shiftId});`);
 between("  $$('[data-mybreak]').forEach",'\n  // Accept-up watchdog',`  $$('[data-mybreak]').forEach(b=>{b.onclick=()=>upFloorAction({action:'status',rep_profile_id:currentUser.id,status:b.dataset.mybreak});});
  $$('[data-bump]').forEach(b=>{b.onclick=()=>upFloorAction({action:'bump',rep_profile_id:b.dataset.bump});});
  $$('[data-goaway]').forEach(b=>{b.onclick=()=>upFloorAction({action:'status',rep_profile_id:b.dataset.goaway,status:'temporarily_unavailable'});});
  $$('[data-goback]').forEach(b=>{b.onclick=()=>upFloorAction({action:'status',rep_profile_id:b.dataset.goback,status:'available'});});
`);
 s=s.replace("handleAcceptUpTimeout(sid,currentUpEntry).then(()=>{window._toHandling=false;render();});","handleAcceptUpTimeout(sid,currentUpEntry).catch(e=>console.warn(e.message)).finally(()=>{window._toHandling=false;render();});");
 between('async function recalcQueueOrder(', '\n// Shared assignment pipeline',`async function recalcQueueOrder(storeId){return upRotation({action:'recalc',store_id:storeId});}
async function rotateToBackOfQueue(storeId,userId){return upRotation({action:'rotate_back',store_id:storeId,rep_profile_id:userId});}
async function acceptUp(entryId){await upFloorAction({action:'accept_up',entry_id:entryId});}
async function handleAcceptUpTimeout(storeId,entry){return upRotation({action:'timeout',store_id:storeId,entry_id:entry.id,expected_offered_at:entry.up_offered_at});}
`);
 between('async function takeGreeterDuty(', '\n// ===== ONBOARDING WIZARD',`async function takeGreeterDuty(){try{await upRotation({action:'greeter_start'});currentView='greeter';$$('.nav-btn').forEach(b=>b.classList.toggle('active',b.dataset.view==='greeter'));await render();}catch(e){alert(e.message);}}
async function endGreeterDuty(){try{await upRotation({action:'greeter_end'});currentView='floor';$$('.nav-btn').forEach(b=>b.classList.toggle('active',b.dataset.view==='floor'));await render();}catch(e){alert(e.message);}}
`);
 s=s.replace("    await assignCustomerToRep(waitingId,$('#as_rep').value,{source:'walk_in'});","    try{await assignCustomerToRep(waitingId,$('#as_rep').value,{source:'walk_in'});}catch(e){return formErr(e.message);}");
 const rs=s.indexOf('async function openReassignModal('),ra=s.indexOf('    const now=new Date().toISOString();',rs),rb=s.indexOf('    await assignCustomerToRep(activeCust.id,toRep',ra);
 if(ra<0||rb<0)throw Error('UP reassign changed');s=s.slice(0,ra)+s.slice(rb);
 s=s.replace("counts_as_up:opts.countsAsUp!==false}","counts_as_up:opts.countsAsUp!==false,reason:opts.reason||null}");
 s=s.replace("await assignCustomerToRep(activeCust.id,toRep,{countsAsUp:false,source:'reassign',handoffFrom:fromUserId});", "try{await assignCustomerToRep(activeCust.id,toRep,{countsAsUp:false,source:'reassign',handoffFrom:fromUserId,reason});}catch(e){return formErr(e.message);}");
 const ea=s.indexOf("    await sb.from('iq_customer_interactions').update(patch)"),eb=s.indexOf('    try{await syncAfterSaleToCRM',ea);
 if(ea<0||eb<0)throw Error('UP end visit changed');s=s.slice(0,ea)+s.slice(eb);
 // The imported public-schema subscriptions have no US publication. Refresh reads every
 // five seconds instead, with one in-flight refresh and no refresh through open forms.
 between('function setupRealtime(){','\n// ===== MODE MANAGEMENT',`let upPollId=null,upPollBusy=false;
function setupRealtime(){
 if(realtimeChannel){sb.removeChannel(realtimeChannel);realtimeChannel=null;}
 if(upPollId)clearInterval(upPollId);
 if(!currentStore)return;
 upPollId=setInterval(async()=>{
  if(upPollBusy||document.hidden||$('#ovl')||!currentStore)return;
  upPollBusy=true;
  try{if(activeMode==='kiosk')await renderKiosk();else if(activeMode==='tv')await renderTV();else if(currentView==='floor')await render();}
  catch(e){console.warn('Floor refresh could not complete');}finally{upPollBusy=false;}
 },5000);
}
`);
 return s;
}
