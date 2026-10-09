// Applied only to generated US bundles. Canada source app is retained.
export const draftHelpers=`
let speciqDraftAttempt=null;
async function speciqDraftApi(body){
 let result;try{result=await sb.rpc('speciq_drafts',{p_body:body});}catch{throw Error('The draft request could not be completed. Retry to check whether it was saved.');}
 if(result?.error||!result?.data)throw Error('The draft request could not be completed. Retry to check whether it was saved.');
 const data=result.data;if(!data.ok)throw Error(({identity_review_required:'Your account needs identity approval.',email_confirmation_required:'Confirm your email, then sign in.',organization_write_required:'Active organization edit access is required.',invalid_request:'Check customer, product, price and warranty details. The draft was not saved.',package_unavailable:'This package is unavailable for your account.',package_not_editable:'This package cannot be revised as a draft.',revision_conflict:'This package changed. Reload it before editing.',request_conflict:'The retry differs from the original save.'})[data.error]||'The draft could not be saved.');
 return data;
}
function speciqDraftRequest(body){
 const fingerprint=JSON.stringify(body);
 if(!speciqDraftAttempt||speciqDraftAttempt.fingerprint!==fingerprint)speciqDraftAttempt={fingerprint,request_id:crypto.randomUUID()};
 return {...body,request_id:speciqDraftAttempt.request_id};
}
function draftPrice(value){const text=String(value??'');if(!/^[0-9]{1,8}(\\.[0-9]{1,2})?$/.test(text))throw Error('Enter a nonnegative price with at most two decimal places.');return text;}
`;
export function migrateSpeciqDrafts(source){
 let s=source;
 function block(start,end,value){const a=s.indexOf(start),b=s.indexOf(end,a+start.length);if(a<0||b<0)throw Error('Spec IQ source contract changed: '+start);s=s.slice(0,a)+value+'\n\n'+s.slice(b);}
 block('async function resolveOrg(){','function isManager(){',draftHelpers+`
async function resolveOrg(){
 userOrgId=null;userRole=null;
 const data=await speciqDraftApi({action:'context'}),orgs=data.organizations;
 if(!orgs.length)throw Error('Your account needs an active organization invitation.');
 const chosen=orgs[0];userOrgId=chosen.id;userRole=chosen.role;
 let select=document.getElementById('speciq-org');
 if(!select){select=document.createElement('select');select.id='speciq-org';select.setAttribute('aria-label','Organization');el('user-email').parentNode.appendChild(select);}
 select.replaceChildren(...orgs.map(o=>{const opt=document.createElement('option');opt.value=o.id;opt.textContent=o.name;return opt;}));
 select.value=userOrgId;select.onchange=()=>{const o=orgs.find(o=>o.id===select.value);userOrgId=o.id;userRole=o.role;speciqDraftAttempt=null;resetBuilder();loadDashboardStats();loadProjects();loadPackages();loadRetailerSettings();loadWarrantyCatalog();loadTaxRules();};
}
`);
 s=s.replace("['sales_manager','store_manager','admin','owner'].includes(userRole)","['manager','admin','owner'].includes(userRole)");
 const old="resolveOrg().then(()=>{loadDashboardStats();loadProjects();loadRetailerSettings();loadPendingCount();loadWarrantyCatalog();loadTaxRules()})";
 if(!s.includes(old))throw Error('Spec IQ boot contract changed');
 s=s.replace(old,old+".catch(e=>{userOrgId=null;userRole=null;hide('app');show('auth-page');alert(e.message)})");
 block('window.savePackage=async(status)=>{','/* ==================== PACKAGES LIST ==================== */',`
window.savePackage=async(status)=>{
 if(_savingPackage)return;
 if(!['draft','generated'].includes(status)){alert('Save a draft first. Review and customer sending are not yet available on US East.');return;}
 _savingPackage=true;
 try{
 if(!userOrgId)throw Error('Choose an active organization.');
 if(selectedCrmContactId||selectedCrmDealId)throw Error('Linked CRM drafts require the next integration step. Clear the link to save a standalone draft.');
 const existing=window._editingPackageId?allPackages.find(p=>p.id===window._editingPackageId):null;
 if(window._editingPackageId&&!existing)throw Error('Reload this package before revising it.');
 const customer={name:el('b-cust-name').value.trim(),email:el('b-cust-email').value.trim(),phone:el('b-cust-phone').value.trim(),project_name:el('b-proj-name').value.trim()||el('b-pkg-name').value.trim()||'Untitled Project',address:el('b-address').value.trim(),room:el('b-room').value.trim()};
 if(!customer.name||!builderProducts.length)throw Error('Enter a customer name and add at least one appliance.');
 const body={action:'save',organization_id:userOrgId,customer,package_name:el('b-pkg-name').value.trim()||customer.project_name,include_pricing:el('b-pricing').checked,
 ...(existing?{previous_package_id:existing.id,expected_version:existing.version,expected_updated_at:existing.updated_at}:{}),
 products:builderProducts.map(p=>({aiq_product_id:p.aiq_product_id||null,product_name:p.product_name,brand:p.brand||'',model_number:p.model_number||'',category:p.category||'',msrp:draftPrice(p.msrp),quantity:p.quantity||1,warranty_id:p.warranty_id||null})),
 services:builderServices.map(p=>({service_type:p.service_type==='accessory'?'accessories':p.service_type,description:p.description||'',amount:draftPrice(p.amount),taxable:p.taxable!==false}))};
 const saved=await speciqDraftApi(speciqDraftRequest(body));
 speciqDraftAttempt=null;builderProducts=[];builderServices=[];window._editingPackageId=null;selectedCrmContactId=null;selectedCrmDealId=null;
 alert('Draft saved. Prices are draft entries; final tax, approval and sending are pending.');
 try{await loadPackages();navigate('packages');loadDashboardStats();if(status==='generated')await openPackageDetail(saved.package_id);}catch{alert('The draft was saved, but the view could not refresh. Reload packages.');}
 }catch(e){alert(e.message||'The draft could not be saved.');}
 finally{_savingPackage=false;}
};
`);
 s=s.replace('<button class="btn btn-s" onclick="savePackage', '<p style="font-size:12px">US drafts: prices are entered estimates. Final tax, manager approval, CRM links and customer sending are pending. Revisions retain the prior package.</p><button class="btn btn-s" onclick="savePackage');
 s=s.replace('Generate Package</button>','Save Draft &amp; Preview</button>');
 s=s.replace("onclick=\"savePackage('pending_approval')\"","disabled title=\"Manager review is pending migration\"").replace("onclick=\"savePackage('sent')\"","disabled title=\"Customer sending is pending migration\"");
 s=s.replace(".select('*, speciq_projects(customer_name, project_name, property_address)').order('created_at'", ".select('*, speciq_projects(customer_name, customer_email, customer_phone, project_name, property_address, room_name)').eq('organization_id',userOrgId).is('deleted_at',null).is('superseded_by',null).order('created_at'");
 s=s.replace(".eq('active',true).order('sort_order');warrantyCatalog", ".eq('active',true).eq('organization_id',userOrgId).order('sort_order');warrantyCatalog");
 s=s.replace(".from('speciq_tax_rules').select('*').order('is_default'", ".from('speciq_tax_rules').select('*').eq('organization_id',userOrgId).order('is_default'");
 s=s.replace("return s.service_type!=='warranty'","return !['warranty','extended_warranty'].includes(s.service_type)");
 s=s.replace("msrp:parseFloat(p.msrp)||0,width_inches:","msrp:parseFloat(p.msrp)||0,quantity:p.quantity||1,width_inches:");
 s=s.replace('<div id="view-builder"', '<div id="view-builder"');
 return s;
}
