export function migrateUpCrmHandoff(s){
 const start=s.indexOf('async function syncWalkInToCRM('),end=s.indexOf('\nasync function syncFloorMetricsToCommandCenter',start);
 if(start<0||end<0)throw Error('UP handoff contract changed');
 s=s.slice(0,start)+`async function upHandoff(body){
 const r=await sb.rpc('up_crm_handoff',{p_body:body});
 if(r.error||!r.data?.ok)throw Error('CRM / Spec IQ handoff could not be completed. Please retry.');
 return r.data;
}
async function syncWalkInToCRM(waitingRow){
 return upHandoff({action:'sync',organization_id:currentOrg.id,waiting_id:waitingRow.id});
}
async function syncAfterSaleToCRM(waitingId,closed,reasonNotPurchased,followUpDate,noFollowUp){
 return upHandoff({action:'after_sale',organization_id:currentOrg.id,waiting_id:waitingId,closed,reason:reasonNotPurchased||null,follow_up_date:followUpDate||null,no_follow_up:!!noFollowUp});
}
`+s.slice(end);
 const before="    const{data:newRow,error}=await sb.from('iq_customer_waiting_queue').insert(row).select().single();\n    if(error)return formErr(error.message);";
 if(!s.includes(before))throw Error('UP log contract changed');
 s=s.replace(before,'');
 const interest="      await sb.from('iq_customer_product_interest').insert({organization_id:currentOrg.id,store_id:currentStore.id,customer_waiting_id:newRow.id,...p});";
 if(!s.includes(interest))throw Error('UP interests contract changed');s=s.replace(interest,'');
 s=s.replace("  $('#wi_save').onclick=async()=>{", "  const handoffId=crypto.randomUUID();\n  let handoffSaving=false;\n  $('#wi_save').onclick=async()=>{\n    if(handoffSaving)return;\n    handoffSaving=true;$('#wi_save').disabled=true;\n    try{");
 s=s.replace('    await syncWalkInToCRM(newRow,products);', "    await upHandoff({action:'log',organization_id:currentOrg.id,waiting_id:handoffId,waiting:row,products});");
 const close='    closeModal();render();\n  };\n}\n\n// ===== CROSS-APP SYNC';
 if(!s.includes(close))throw Error('UP save completion changed');
 s=s.replace(close,"    closeModal();render();\n    }catch(e){formErr(e.message||'Handoff failed. Please retry.');}\n    finally{handoffSaving=false;const button=$('#wi_save');if(button)button.disabled=false;}\n  };\n}\n\n// ===== CROSS-APP SYNC");
 const kiosk="    const{data:newRow,error}=await sb.from('iq_customer_waiting_queue').insert(row).select().single();\n    if(error)return alert(error.message);\n    await syncWalkInToCRM(newRow,[]);";
 if(!s.includes(kiosk))throw Error('UP kiosk contract changed');
 s=s.replace("  $('#kw_save').onclick=async()=>{", "  const kioskHandoffId=crypto.randomUUID();\n  $('#kw_save').onclick=async()=>{\n    $('#kw_save').disabled=true;\n    try{");
 s=s.replace(kiosk,"    await upHandoff({action:'log',organization_id:currentOrg.id,waiting_id:kioskHandoffId,waiting:row,products:[]});");
 s=s.replace("    renderKiosk();\n  };\n}\n\n// ===== TV RENDERER", "    renderKiosk();\n    }catch(e){alert(e.message);}finally{const button=$('#kw_save');if(button)button.disabled=false;}\n  };\n}\n\n// ===== TV RENDERER");
 const assignStart=s.indexOf('async function assignCustomerToRep('),assignEnd=s.indexOf('\n// Reassign an active customer',assignStart);
 if(assignStart<0||assignEnd<0)throw Error('UP assignment contract changed');
 s=s.slice(0,assignStart)+`async function assignCustomerToRep(waitingId,repId,opts={}){
 try{await upHandoff({action:'assign',organization_id:currentOrg.id,waiting_id:waitingId,rep_profile_id:repId,counts_as_up:opts.countsAsUp!==false});}
 catch(e){alert(e.message);throw e;}
}
`+s.slice(assignEnd);
 s=s.replace('    await syncAfterSaleToCRM(activeCust.id,closed,reasonNotPurchased,followUpDate,noFollowUp);',"    try{await syncAfterSaleToCRM(activeCust.id,closed,reasonNotPurchased,followUpDate,noFollowUp);}catch(e){return formErr(e.message);}");
 return s;
}
