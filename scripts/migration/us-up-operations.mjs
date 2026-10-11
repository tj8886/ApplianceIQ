export function migrateUpOperations(s){
 function between(a,b,value){const x=s.indexOf(a),y=s.indexOf(b,x);if(x<0||y<0)throw Error('UP operations contract changed: '+a);s=s.slice(0,x)+value+s.slice(y);}
 s=s.replace('>Save All Settings</button>','>Save Floor Settings</button>');
 s=s.replace("d.status==='open'?`<button class=\"btn btn-sm btn-ghost\" data-resolve=","d.status==='open'&&['owner','admin','manager'].includes(userRole)?`<button class=\"btn btn-sm btn-ghost\" data-resolve=");
 const helper=`async function upOperations(body){const r=await sb.rpc('up_operations',{p_body:{organization_id:currentOrg.id,store_id:currentStore?.id,...body}});if(r.error||!r.data?.ok)throw Error(r.data?.error==='manager_required'?'A manager must make this change.':'The update could not be completed. Check your entries and retry.');return r.data;}
`;
 s=s.replace('async function upRotation(body){',helper+'\nasync function upRotation(body){');
 between('async function syncFloorMetricsToCommandCenter(', '\nfunction openClockInModal',`async function syncFloorMetricsToCommandCenter(storeId){return upOperations({action:'refresh_reports',store_id:storeId});}
`);
 // Stable dispute ID makes retries harmless; filed-by is always the verified caller.
 between("  $('#dp_save').onclick=async()=>{",'\n}\n\n// ===== CUSTOMERS',`  const disputeId=crypto.randomUUID();
  $('#dp_by').value=currentUser.id;$('#dp_by').disabled=true;
  $('#dp_save').onclick=async()=>{
   const button=$('#dp_save');if(button.disabled)return;button.disabled=true;
   try{await upOperations({action:'file_dispute',dispute_id:disputeId,affected_profile_id:$('#dp_aff').value||null,reason:$('#dp_reason').value.trim()});closeModal();await render();}
   catch(e){formErr(e.message);}finally{button.disabled=false;}
  };`);
 s=s.replace('<div class="field"><label>Manager notes</label><textarea id="rv_notes"', '<div class="field"><label><input type="checkbox" id="rv_priority" style="width:auto"> Restore affected rep to front of available queue</label></div><div class="field"><label>Manager notes</label><textarea id="rv_notes"');
 between("    $('#rv_save').onclick=async()=>{",'\n  };});\n}\n\n// ===== MISSED UPS',`    $('#rv_save').onclick=async()=>{
     const button=$('#rv_save');if(button.disabled)return;button.disabled=true;
     try{await upOperations({action:'resolve_dispute',dispute_id:b.dataset.resolve,decision:$('#rv_dec').value,notes:$('#rv_notes').value.trim(),restore_queue_priority:$('#rv_priority').checked});closeModal();await render();}
     catch(e){formErr(e.message);}finally{button.disabled=false;}
    };`);
 const start=s.indexOf("  $('#ss_save')?.addEventListener"),rowStart=s.indexOf('    const row=',start),rowEnd=s.indexOf('\n',rowStart);
 if(start<0||rowStart<0||rowEnd<0)throw Error('UP settings changed');const row=s.slice(rowStart,rowEnd);
 between("  $('#ss_save')?.addEventListener",'\n  // Kiosk / TV launch',`  $('#ss_save')?.addEventListener('click',async()=>{
   const button=$('#ss_save');if(button.disabled)return;button.disabled=true;
   const greeterUser=$('#ss_greeter_user').value||null;
${row}
   try{await upOperations({action:'save_settings',settings:row});await render();}catch(e){alert(e.message);}finally{button.disabled=false;}
  });
`);
 // Membership rows use source IDs; floor-name dictionaries use profile IDs.
 s=s.replace("const name=profiles[m.user_id]||m.user_id.slice(0,8)+'…';const isMe=m.user_id===currentUser.id;", "const name=memberProfiles[m.user_id]||'Staff';const isMe=m.user_id===currentUser.source_user_id;");
 s=s.replace("  const isAdmin=['admin','owner'].includes(userRole);\n  const[{data:settings}","  const {data:staffNames}=await sb.rpc('get_org_member_profiles',{p_org_id:currentOrg.id});const memberProfiles=Object.fromEntries((staffNames||[]).map(p=>[p.user_id,p.display_name||'Staff']));\n  const isAdmin=['admin','owner'].includes(userRole);\n  const[{data:settings}");
 return s;
}
