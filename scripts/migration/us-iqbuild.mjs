export function migrateIqBuild(s){
 const marker='const supabase = createClient(SB_URL, SB_KEY);';if(!s.includes(marker))throw Error('IQ Build client changed');
 s=s.replace(marker,marker+`
const iqbuildOriginalFrom=supabase.from.bind(supabase);
function iqbuildQuery(query){return new Proxy(query,{get(target,key){if(key==='then')return(resolve,reject)=>Promise.resolve(target).then(r=>{if(r.error)throw Error('Project data could not be loaded or saved. Please retry.');return r;}).then(resolve,reject);var value=target[key];if(typeof value!=='function')return value;return(...args)=>{var next=value.apply(target,args);return next&&typeof next==='object'&&(typeof next.select==='function'||typeof next.eq==='function')?iqbuildQuery(next):next;};}});}
supabase.from=(table)=>iqbuildQuery(iqbuildOriginalFrom(table));
window.addEventListener('unhandledrejection',event=>{if(event.reason?.message?.startsWith('Project data could not')){event.preventDefault();toast(event.reason.message);}});
let iqbuildContext=null;
function iqbuildRecordedPrice(value){if(value==null||String(value).trim()==='')return null;const price=Number(value);if(!Number.isFinite(price))throw Error('Enter a valid recorded price.');return price;}
async function resolveIqBuildContext(){const r=await supabase.rpc('my_platform_context');if(r.error||!r.data?.organization_id||!r.data?.source_user_id)throw Error('An active organization is required for IQ Build.');iqbuildContext=r.data;return r.data;}
`);
 s=s.replace('    currentUser = session.user;','    currentUser = session.user;\n    await resolveIqBuildContext();');
 s=s.replace('  currentUser = data.user;','  currentUser = data.user;\n  try{await resolveIqBuildContext();}catch(e){return e.message;}');
 s=s.replaceAll('created_by: currentUser.id','created_by: iqbuildContext.source_user_id, organization_id: iqbuildContext.organization_id');
 s=s.replace('record.created_by = currentUser.id;','record.created_by = iqbuildContext.source_user_id;record.organization_id=iqbuildContext.organization_id;');
 s=s.replaceAll('formatCurrency(it.negotiated_price || it.unit_cost)','formatCurrency(it.negotiated_price ?? it.unit_cost)');
 s=s.replace('original_cost: Number(it.negotiated_price || it.unit_cost || 0)','original_cost: iqbuildRecordedPrice(it.negotiated_price ?? it.unit_cost)');
 s=s.replace('id="m-pkcost" value="0"','id="m-pkcost" value="" placeholder="Unknown"');
 s=s.replace("base_cost: parseFloat(document.getElementById('m-pkcost').value) || 0","base_cost: iqbuildRecordedPrice(document.getElementById('m-pkcost').value)");
 const importStart=s.indexOf("  const { data: newProject, error: projError }",s.indexOf('async function executeImport('));const importEnd=s.indexOf('\nfunction mapCategory(',importStart);
 if(importStart<0||importEnd<0)throw Error('IQ Build import changed');
 s=s.slice(0,importStart)+`  const r=await supabase.rpc('iqbuild_import',{p_deal_id:deal.id,p_project:projectRecord});if(r.error){toast('Project import failed. No partial import was saved.');return false;}
 toast(r.data.already_imported?'This deal already has a project.':\`Imported! \${r.data.packages} packages, \${r.data.items} products\`);currentProject=await loadProjectDetail(r.data.project_id);currentView='project-detail';render();return true;
}
`+s.slice(importEnd);
 // Scope the initial project and template lists to the selected, validated context.
 s=s.replace("from('iqbuild_projects').select('*').order", "from('iqbuild_projects').select('*').eq('organization_id',iqbuildContext.organization_id).order");
 s=s.replace("from('iqbuild_milestone_templates').select('*').order", "from('iqbuild_milestone_templates').select('*').eq('organization_id',iqbuildContext.organization_id).order");
 s=s.replace("    .in('stage', ['Closed Won', 'Delivery Scheduled'])", "    .eq('organization_id',iqbuildContext.organization_id).in('stage', ['Closed Won', 'Delivery Scheduled'])");
 s=s.replace('checkAuth();\n</script>',"checkAuth().catch(e=>{renderLogin();toast(e.message||'IQ Build could not load. Please sign in again.');});\nwindow.addEventListener('aiq:intelligence-ready',()=>checkAuth().catch(e=>toast(e.message)));\n</script>");
 return s;
}
