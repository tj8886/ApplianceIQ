export const crmLinkHelpers=`
let speciqContactSearch=0;
async function speciqCrmApi(body){
 let r;try{r=await sb.rpc('speciq_crm_links',{p_body:body});}catch{throw Error('CRM contacts could not be loaded. Try again.');}
 if(r?.error||!r?.data||!r.data.ok)throw Error('CRM contacts could not be loaded. Check your organization access.');return r.data;
}
window.clearSpeciqCrmLink=function(){selectedCrmContactId=null;selectedCrmDealId=null;speciqContactSearch++;el('b-contact-linked').replaceChildren();if(el('b-contact-search'))el('b-contact-search').value='';};
window.searchCrmContacts=async function(q){
 const sequence=++speciqContactSearch,org=userOrgId,box=el('b-contact-results');
 box.replaceChildren();if(!q||q.trim().length<2){box.style.display='none';return;}
 try{
 const r=await speciqCrmApi({action:'search',organization_id:org,query:q.trim()});if(sequence!==speciqContactSearch||org!==userOrgId)return;
 box.style.display='block';if(!r.contacts.length){box.textContent='No matching contacts';return;}
 r.contacts.forEach(c=>{const row=document.createElement('button');row.type='button';row.className='rowbtn';row.textContent=[c.first_name,c.last_name,c.email||c.phone].filter(Boolean).join(' ');row.onclick=()=>selectNativeCrmContact(c.id,org);box.appendChild(row);});
 }catch(e){if(sequence===speciqContactSearch&&org===userOrgId){box.style.display='block';box.textContent=e.message;}}
};
async function selectNativeCrmContact(id,org){
 const sequence=++speciqContactSearch;selectedCrmContactId=null;selectedCrmDealId=null;el('b-contact-linked').replaceChildren();
 try{
 const r=await speciqCrmApi({action:'select',organization_id:org,contact_id:id});if(sequence!==speciqContactSearch||org!==userOrgId)return;
 selectedCrmContactId=r.contact.id;el('b-cust-name').value=r.contact.name;el('b-cust-email').value=r.contact.email||'';el('b-cust-phone').value=r.contact.phone||'';el('b-contact-search').value=r.contact.name;el('b-contact-results').style.display='none';
 const linked=el('b-contact-linked');linked.textContent='Linked CRM contact. ';
 const clear=document.createElement('button');clear.type='button';clear.textContent='Clear link';clear.onclick=clearSpeciqCrmLink;linked.appendChild(clear);
 if(r.deals.length){const select=document.createElement('select');select.setAttribute('aria-label','Open CRM deal');const none=document.createElement('option');none.value='';none.textContent='Contact only (no deal)';select.appendChild(none);r.deals.forEach(d=>{const o=document.createElement('option');o.value=d.id;o.textContent=d.title;select.appendChild(o);});select.onchange=()=>{selectedCrmDealId=select.value||null;};linked.appendChild(select);}
 }catch(e){if(sequence===speciqContactSearch&&org===userOrgId)el('b-contact-linked').textContent=e.message;}
}
`;
export function migrateSpeciqCrmLinks(source){
 let s=source;const a=s.indexOf('window.searchCrmContacts=async(q)=>{'),b=s.indexOf('window.createProject=async',a);
 if(a<0||b<0)throw Error('Spec IQ CRM picker contract changed');s=s.slice(0,a)+crmLinkHelpers+'\n'+s.slice(b);
 const blocked=" if(selectedCrmContactId||selectedCrmDealId)throw Error('Linked CRM drafts require the next integration step. Clear the link to save a standalone draft.');";
 if(!s.includes(blocked))throw Error('Spec IQ draft link contract changed');s=s.replace(blocked,'');
 s=s.replace("const body={action:'save',organization_id:userOrgId,customer,", "const body={action:'save',organization_id:userOrgId,customer,contact_id:selectedCrmContactId,deal_id:selectedCrmDealId,salesperson_name:el('b-salesperson')?.value.trim()||'',");
 s=s.replace("function resetBuilder(){builderProducts=[];", "function resetBuilder(){if(window.clearSpeciqCrmLink)window.clearSpeciqCrmLink();builderProducts=[];");
 s=s.replace("  el('b-cust-email').value=pkg.speciq_projects?.customer_email||'';", "  el('b-cust-email').value=pkg.speciq_projects?.customer_email||'';el('b-cust-phone').value=pkg.speciq_projects?.customer_phone||'';");
 s=s.replace('Final tax, CRM links and customer sending are pending.', 'Final tax and customer sending are pending. CRM links are checked when saving.');
 s=s.replace("if(selectedCrmContactId)el('b-contact-linked').textContent='✓ Linked to CRM contact';", "if(selectedCrmContactId){const linked=el('b-contact-linked');linked.textContent='Linked CRM contact. ';const clear=document.createElement('button');clear.type='button';clear.textContent='Clear link';clear.onclick=clearSpeciqCrmLink;linked.appendChild(clear);}");
 s=s.replace("invalid_request:'Check customer,", "crm_link_unavailable:'This contact or open deal is unavailable. Choose another link or clear it.',invalid_request:'Check customer,");
 return s;
}
