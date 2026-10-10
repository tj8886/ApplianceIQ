export const projectDetailHelpers=`
const draftProjectDetailFields={'b-builder-name':'builder_name','b-designer-name':'designer_name','b-purchase-date':'expected_purchase_date','b-delivery-date':'delivery_date','b-project-notes':'notes'};
function populateDraftProjectDetails(project={}){Object.entries(draftProjectDetailFields).forEach(([id,key])=>el(id).value=project?.[key]||'');}
function draftProjectDetailsPreview(project={}){return '<dl>'+Object.entries({builder_name:'Builder',designer_name:'Designer',expected_purchase_date:'Expected purchase',delivery_date:'Delivery',notes:'Internal project notes'}).filter(([key])=>project?.[key]).map(([key,label])=>'<dt>'+label+'</dt><dd>'+esc(project[key])+'</dd>').join('')+'</dl>';}
`;
export function migrateSpeciqProjectDetails(source){
 let s=source;
 const anchor='<div><label>Salesperson</label><input id="b-salesperson" placeholder="Your name" /></div>';
 if(!s.includes(anchor))throw Error('Spec IQ project builder contract changed');
 s=s.replace(anchor,anchor+'<div><label>Builder</label><input id="b-builder-name" maxlength="200" /></div><div><label>Designer</label><input id="b-designer-name" maxlength="200" /></div><div><label>Expected Purchase Date</label><input id="b-purchase-date" type="date" /></div><div><label>Delivery Date</label><input id="b-delivery-date" type="date" /></div><div><label>Internal Project Notes</label><textarea id="b-project-notes" maxlength="4000"></textarea></div>');
 s=s.replace('function resetBuilder(){','function resetBuilder(){populateDraftProjectDetails();');
 const customer="room:el('b-room').value.trim()};";if(!s.includes(customer))throw Error('Spec IQ customer draft contract changed');s=s.replace(customer,"room:el('b-room').value.trim(),...Object.fromEntries(Object.entries(draftProjectDetailFields).map(([id,key])=>[key,el(id).value.trim()||null]))};");
 const relation='customer_phone, project_name, property_address, room_name)';if(!s.includes(relation))throw Error('Spec IQ project read contract changed');s=s.replaceAll(relation,'customer_phone, project_name, property_address, room_name, builder_name, designer_name, expected_purchase_date, delivery_date, notes)');
 s=s.replace("  el('b-room').value=pkg.speciq_projects?.room_name||'';", "  el('b-room').value=pkg.speciq_projects?.room_name||'';populateDraftProjectDetails(pkg.speciq_projects);");
 s=s.replace("button('Build draft copy',()=>{navigate('builder');", "button('Build draft copy',()=>{navigate('builder');populateDraftProjectDetails(p);");
 s=s.replace("buildPrintHTML({...p,customer_name:project.customer_name}","buildPrintHTML({...p,customer_name:project.customer_name,speciq_projects:project}");
 s=s.replace("'+preview+decisions","'+preview+draftProjectDetailsPreview(project)+decisions");
 const preview='<table><thead><tr><th>Product</th>';if(!s.includes(preview))throw Error('Spec IQ draft preview contract changed');s=s.replace(preview,"'+draftProjectDetailsPreview(pkg.speciq_projects||{})+'<table><thead><tr><th>Product</th>");
 s=s.replace('let speciqDraftAttempt=null;',projectDetailHelpers+'\nlet speciqDraftAttempt=null;');return s;
}
