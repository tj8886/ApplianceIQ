export const projectHelpers=`
let projectEditing=null,projectAttempt=null,projectSaving=false,projectSequence=0;
const projectFields={'pj-name':'project_name','pj-customer':'customer_name','pj-email':'customer_email','pj-phone':'customer_phone','pj-address':'property_address','pj-room':'room_name','pj-builder':'builder_name','pj-designer':'designer_name','pj-date':'expected_purchase_date','pj-delivery':'delivery_date','pj-notes':'notes'};
async function speciqProjectsApi(body){
 let r;try{r=await sb.rpc('speciq_projects',{p_body:body});}catch{throw Error('Project request could not be completed. Try again.');}
 if(r?.error||!r?.data)throw Error('Project request could not be completed. Try again.');
 if(!r.data.ok)throw Error(({revision_conflict:'Project changed. Reload it before trying again.',package_revision_required:'Revise the package to change a project used by a package.',archive_packages_first:'Archive the attached packages first.',historical_project_read_only:'Imported projects are read only. Create a new project for changes.',invalid_request:'Check project names, email, dates and field lengths.',organization_write_required:'Your organization role cannot change projects.'})[r.data.error]||'Project is unavailable. Check your current organization access.');return r.data;
}
function clearProjectForm(){projectEditing=null;projectAttempt=null;Object.keys(projectFields).forEach(id=>el(id).value='');el('project-form-title').textContent='Create Project';el('project-save-button').textContent='Create Project';}
function toggleNewProject(){if(projectSaving)return;clearProjectForm();el('new-project-form').classList.toggle('hidden');}
async function loadProjects(){
 const sequence=++projectSequence,org=userOrgId,list=el('projects-list');if(!list)return;
 try{const r=await speciqProjectsApi({action:'list',organization_id:org});if(sequence!==projectSequence||org!==userOrgId)return;projects=r.projects;renderNativeProjects();}
 catch(e){if(sequence===projectSequence&&org===userOrgId){projects=[];list.replaceChildren();list.textContent=e.message;}}
}
function renderNativeProjects(){
 const list=el('projects-list');list.replaceChildren();const q=(el('project-search')?.value||'').toLowerCase(),archived=el('project-show-archived')?.checked;
 const visible=projects.filter(p=>(archived||p.status!=='archived')&&[p.project_name,p.customer_name].some(v=>(v||'').toLowerCase().includes(q)));
 if(!visible.length){list.textContent='No matching projects. Create a project or include archived projects.';return;}
 const note=document.createElement('p');note.textContent='Latest 200 projects. Building creates a separate draft copy; saved package details stay unchanged.';list.appendChild(note);
 visible.forEach(p=>{const row=document.createElement('div');row.className='card';const title=document.createElement('h3');title.textContent=p.project_name;row.appendChild(title);const details=document.createElement('p');details.textContent=[p.customer_name,p.room_name,p.property_address,p.status].filter(Boolean).join(' · ');row.appendChild(details);
 const button=(label,handler)=>{const b=document.createElement('button');b.type='button';b.className='btn btn-s';b.textContent=label;b.onclick=handler;row.appendChild(b);};
 if(p.status!=='archived')button('Build draft copy',()=>{navigate('builder');[['b-proj-name',p.project_name],['b-cust-name',p.customer_name],['b-cust-email',p.customer_email],['b-cust-phone',p.customer_phone],['b-address',p.property_address],['b-room',p.room_name]].forEach(([id,v])=>{if(el(id))el(id).value=v||'';});});
 if(p.can_edit)button('Edit',()=>{if(projectSaving)return;projectEditing={id:p.id,updated_at:p.updated_at,organization_id:userOrgId};projectAttempt=null;Object.entries(projectFields).forEach(([id,key])=>el(id).value=p[key]||'');el('project-form-title').textContent='Edit Project';el('project-save-button').textContent='Save Project';el('new-project-form').classList.remove('hidden');});
 if(p.can_archive)button('Archive',()=>deleteProject(p.id));list.appendChild(row);});
}
async function deleteProject(id){
 const p=projects.find(p=>p.id===id);if(!p?.can_archive||projectSaving)return;projectSaving=true;
 try{const body={action:'archive',organization_id:userOrgId,project_id:id,expected_updated_at:p.updated_at};const fingerprint=JSON.stringify(body);if(projectAttempt?.fingerprint!==fingerprint)projectAttempt={fingerprint,request_id:crypto.randomUUID()};await speciqProjectsApi({...body,request_id:projectAttempt.request_id});projectAttempt=null;await loadProjects();await loadDashboardStats();}catch(e){alert(e.message);}finally{projectSaving=false;}
}
window.createProject=async e=>{
 e.preventDefault();if(projectSaving)return;projectSaving=true;el('project-save-button').disabled=true;
 try{if(projectEditing&&projectEditing.organization_id!==userOrgId)throw Error('Organization changed. Reopen the project.');const project={};Object.entries(projectFields).forEach(([id,key])=>project[key]=el(id).value.trim()||null);
 const body={action:projectEditing?'update':'create',organization_id:userOrgId,project,...(projectEditing?{project_id:projectEditing.id,expected_updated_at:projectEditing.updated_at}:{})};const fingerprint=JSON.stringify(body);if(projectAttempt?.fingerprint!==fingerprint)projectAttempt={fingerprint,request_id:crypto.randomUUID()};
 await speciqProjectsApi({...body,request_id:projectAttempt.request_id});clearProjectForm();el('new-project-form').classList.add('hidden');await loadProjects();await loadDashboardStats();
 }catch(e){alert(e.message);}finally{projectSaving=false;el('project-save-button').disabled=false;}
};
window._loadProjects=loadProjects;window.renderProjects=renderNativeProjects;window.deleteProject=deleteProject;
`;
export function migrateSpeciqProjects(source){
 let s=source;const a=s.indexOf('async function loadProjects(){'),b=s.indexOf('// ---- CRM contact linking',a);if(a<0||b<0)throw Error('Spec IQ project list contract changed');s=s.slice(0,a)+projectHelpers+'\n'+s.slice(b);
 const c=s.indexOf('window.createProject=async(e)=>{'),d=s.indexOf('/* ==================== SAVE PACKAGE',c);if(c<0||d<0)throw Error('Spec IQ project write contract changed');s=s.slice(0,c)+s.slice(d);
 s=s.replace("function toggleNewProject(){el('new-project-form').classList.toggle('hidden')}",'');
 s=s.replace('<h3 style="margin-bottom:16px">Create Project</h3>','<h3 id="project-form-title" style="margin-bottom:16px">Create Project</h3>');
 s=s.replace('<button type="submit" class="btn btn-p">Create Project</button>','<button id="project-save-button" type="submit" class="btn btn-p">Create Project</button>');
 s=s.replace('<div><label>Expected Purchase Date</label><input id="pj-date" type="date" /></div>','<div><label>Expected Purchase Date</label><input id="pj-date" type="date" /></div><div><label>Customer Phone</label><input id="pj-phone" maxlength="50" /></div><div><label>Delivery Date</label><input id="pj-delivery" type="date" /></div><div><label>Notes</label><textarea id="pj-notes" maxlength="4000"></textarea></div>');
 s=s.replace('<div id="projects-list"></div>','<label><input id="project-show-archived" type="checkbox" onchange="renderProjects()" /> Include archived projects</label><div id="projects-list"></div>');return s;
}
