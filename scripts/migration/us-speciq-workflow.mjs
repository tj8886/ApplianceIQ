export const workflowHelpers=`
const speciqWorkflowAttempts=new Map();let speciqWorkflowBusy=false;let speciqReview=null;
async function speciqWorkflowApi(body){
 let r;try{r=await sb.rpc('speciq_workflow',{p_body:body});}catch{throw Error('The workflow request could not be completed. Retry the same action.');}
 if(r?.error||!r?.data)throw Error('The workflow request could not be completed. Retry the same action.');
 if(!r.data.ok)throw Error(({organization_access_required:'Active organization access is required.',package_unavailable:'This native draft is unavailable to your account.',independent_manager_required:'A different authorized manager must review this draft.',invalid_transition:'The package is no longer in the required state. Reload it.',revision_conflict:'This package changed. Reload it before continuing.',package_not_editable:'This package cannot be changed through the draft workflow.',forbidden:'You do not have permission for this action.',invalid_request:'Check the decision, comments and conditions.',request_conflict:'The retry differs from the saved request.'})[r.data.error]||'The workflow action could not be completed.');
 return r.data;
}
async function speciqWorkflowMutation(action,pkg,fields={}){
 const body={action,organization_id:userOrgId,package_id:pkg.id,expected_version:pkg.version,expected_updated_at:pkg.updated_at,...fields};
 const key=JSON.stringify(body);if(!speciqWorkflowAttempts.has(key))speciqWorkflowAttempts.set(key,crypto.randomUUID());
 const result=await speciqWorkflowApi({...body,request_id:speciqWorkflowAttempts.get(key)});speciqWorkflowAttempts.delete(key);return result;
}
async function refreshSpeciqWorkflow(){await loadPackages();await loadApprovals();loadDashboardStats();loadPendingCount();}
window.submitNativeDraft=async function(id){
 if(speciqWorkflowBusy)return;speciqWorkflowBusy=true;
 try{const current=await speciqWorkflowApi({action:'get',organization_id:userOrgId,package_id:id});if(!current.can_submit)throw Error('This draft cannot be submitted.');await speciqWorkflowMutation('submit',current.package);closePackageDetail();alert('Draft submitted for independent manager review. Final tax and customer sending remain pending.');await refreshSpeciqWorkflow();}catch(e){alert(e.message);}finally{speciqWorkflowBusy=false;}
};
`;
export function migrateSpeciqWorkflow(source){
 let s=source;
 function block(start,end,value){const a=s.indexOf(start),b=s.indexOf(end,a+start.length);if(a<0||b<0)throw Error('Spec IQ workflow source contract changed: '+start);s=s.slice(0,a)+value+'\n\n'+s.slice(b);}
 block('async function deletePackage(pkgId,pkgName){','window.deletePackage=deletePackage;',workflowHelpers+`
async function deletePackage(id,name){
 if(speciqWorkflowBusy)return;
 if(!confirm('Archive this package? Its records and history will be retained.'))return;
 speciqWorkflowBusy=true;
 try{const current=await speciqWorkflowApi({action:'get',organization_id:userOrgId,package_id:id});await speciqWorkflowMutation('archive',current.package);alert('Package archived. Records and history retained.');await refreshSpeciqWorkflow();}catch(e){alert(e.message);}finally{speciqWorkflowBusy=false;}
}
`);
 block('async function deleteProject(projId,projName,siblingCount){','window.deleteProject=deleteProject;',`async function deleteProject(){alert('Project archive will follow in a separate migration step. Package records can be archived from the package list.');}`);
 block('async function loadApprovals(){','function renderApprovalsList(){',`async function loadApprovals(){
 try{const r=await speciqWorkflowApi({action:'list',organization_id:userOrgId});allApprovals=r.packages.filter(p=>p.approval_status!=='not_required');}catch(e){allApprovals=[];alert(e.message);}
 renderApprovalsList();
}`);
 block('window.openApprovalReview=async function(pkgId){','window.closeApprovalReview=function()',`
window.openApprovalReview=async function(id){
 try{
 const r=await speciqWorkflowApi({action:'get',organization_id:userOrgId,package_id:id});speciqReview=r;
 const p=r.package,snapshot=r.snapshot||{},project=snapshot.project||{};
 const preview=buildPrintHTML({...p,customer_name:project.customer_name},snapshot.products||[],null,snapshot.services||[],snapshot.warranties||[]);
 const decisions=r.can_decide&&p.approval_status==='pending'?'<label>Comments</label><textarea id="mgr-comments" maxlength="2000"></textarea><label>Conditions</label><input id="mgr-conditions" maxlength="2000"><div>'+[['approved','Approve draft'],['approved_with_conditions','Approve draft with conditions'],['returned','Return for changes'],['rejected','Reject draft']].map(([value,label])=>'<button data-decision="'+value+'">'+label+'</button>').join('')+'</div>':'<p>Review status: '+esc(p.approval_status)+'. An independent authorized manager is required for a decision.</p>';
 const history=r.history.map(h=>'<p>'+esc(h.manager_decision||'Submitted')+' '+esc(h.comments||'')+' '+esc(h.conditions||'')+'</p>').join('');
 el('approval-modal').innerHTML='<div class="modal-overlay"><div class="modal-panel" style="max-width:1000px;padding:24px"><h2>Draft content review</h2><p>Approval records a manager decision on this draft. Final pricing, tax and customer sending remain pending.</p>'+preview+decisions+'<h3>History</h3>'+history+'<button id="native-review-close">Close</button></div></div>';
 el('approval-modal').classList.remove('hidden');document.body.style.overflow='hidden';
 el('native-review-close').onclick=closeApprovalReview;
 el('approval-modal').querySelectorAll('[data-decision]').forEach(b=>b.onclick=()=>managerDecision(id,b.dataset.decision));
 }catch(e){alert(e.message);}
};
`);
 block('window.managerDecision=async function(pkgId,decision){','/* ==================== PRINT HANDLER ==================== */',`
window.managerDecision=async function(id,decision){
 if(speciqWorkflowBusy)return;speciqWorkflowBusy=true;
 try{
 if(!speciqReview||speciqReview.package.id!==id)throw Error('Reload this review.');
 const comments=el('mgr-comments')?.value.trim()||'',conditions=el('mgr-conditions')?.value.trim()||'';
 if(['returned','rejected'].includes(decision)&&!comments)throw Error('Enter a reason.');
 if(decision==='approved_with_conditions'&&!conditions)throw Error('Enter the approval conditions.');
 await speciqWorkflowMutation('decide',speciqReview.package,{decision,comments,conditions});
 closeApprovalReview();speciqReview=null;alert('Draft decision recorded. Final tax and customer sending remain pending.');await refreshSpeciqWorkflow();
 }catch(e){alert(e.message);}finally{speciqWorkflowBusy=false;}
};
`);
 s=s.replace("if(pkg.status==='draft'&&pkg.total_tax==null)","if(pkg.total_tax==null)");
 s=s.replace("pkg.status===\'draft\'&&pkg.total_tax==null?", "pkg.total_tax==null?");
 // Draft content review is separate from customer sending and final financial review.
 s=s.replace('Final tax, manager approval, CRM links and customer sending are pending.', 'Final tax, CRM links and customer sending are pending. Submit a saved draft from its preview for manager content review.');
 s=s.replace('Final tax, approval, expiry and customer sending are pending.', 'Final tax, expiry and customer sending are pending. Draft review status: '+"'+esc(pkg.approval_status)+'"+'.');
 s=s.replace("  if(canSend&&!isPending)","  if(pkg.status==='draft'&&!isLocked)html+='<button class=\"btn btn-purple\" onclick=\"submitNativeDraft(\\''+pkgId+'\\')\">Submit draft for review</button>';\n  if(canSend&&!isPending)");
 s=s.replace("pkg.status==='changes_requested'","pkg.approval_status==='returned'");
 s=s.replace("p.approval_status===currentApprovalFilter||", "p.approval_status===(currentApprovalFilter==='changes_requested'?'returned':currentApprovalFilter)||");
 s=s.replaceAll('title="Delete package"','title="Archive package"');
 s=s.replaceAll('title="Delete project"','title="Project archive pending"');
 return s;
}
