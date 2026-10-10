export const trainingHelpers=`
let trainingContext=null,trainingBusy=false,trainingSequence=0,trainingAttempt=null;
async function trainingApi(body){const r=await sb.rpc('brand_training',{p_body:body});if(r?.error||!r?.data?.ok)throw Error(({brand_link_required:'This vendor needs a stored brand link.',revision_conflict:'This card changed. Reload it before saving.',independent_saved_review_required:'A different authorized reviewer must approve saved edits.',forbidden:'Your current organization/brand permissions do not allow this action.',invalid_request:'Check field lengths and complete each objection and response.'})[r?.data?.error]||'Training request failed. Try again.');return r.data;}
function trainingScope(){return ACTIVE_VENDOR?.id+'|'+trainingContext?.organization_id;}
async function loadTrainingEditor(org){
 const ticket=++trainingSequence,vendor=ACTIVE_VENDOR?.id,wrap=document.getElementById('training-editor');if(!vendor){wrap.textContent='No brand selected.';return;}
 trainingContext=null;TRAINING_CARD=null;BRAND_CATALOG_ENTRY=null;wrap.textContent='Loading training card…';
 try{const data=await trainingApi({action:'get',vendor_id:vendor,...((org||ASSET_ORG)?{organization_id:org||ASSET_ORG}:{})});if(ticket!==trainingSequence||vendor!==ACTIVE_VENDOR?.id)return;
 trainingContext=data;TRAINING_CARD=data.card;BRAND_CATALOG_ENTRY=data.brand;renderTrainingEditor();
 }catch(e){if(ticket===trainingSequence&&vendor===ACTIVE_VENDOR?.id){trainingContext=null;TRAINING_CARD=null;wrap.textContent=e.message;}}
}
function decorateTrainingEditor(){
 const wrap=document.getElementById('training-editor'),data=trainingContext;if(!data)return;
 const select=document.createElement('select');select.id='training-org';select.disabled=trainingBusy;const placeholder=document.createElement('option');placeholder.value='';placeholder.textContent='Choose organization';select.appendChild(placeholder);
 (data.organizations||[]).forEach(o=>{const option=document.createElement('option');option.value=o.id;option.textContent=o.name;option.selected=o.id===data.organization_id;select.appendChild(option);});select.onchange=()=>loadTrainingEditor(select.value);wrap.prepend(select);
 wrap.querySelectorAll('input,textarea,button').forEach(e=>{e.disabled=trainingBusy||!data.can_write;});wrap.querySelectorAll('button[onclick="approveTrainingCard()"]').forEach(e=>e.disabled=trainingBusy||!data.can_review);
}
async function trainingWrite(action,fields){
 if(trainingBusy||!trainingContext?.organization_id)return;
 const scope=trainingScope(),org=trainingContext.organization_id,vendor=ACTIVE_VENDOR.id;
 const body={action,organization_id:org,vendor_id:vendor,expected_updated_at:TRAINING_CARD?.updated_at||null,...(fields?{fields}:{})};const key=JSON.stringify(body);
 if(trainingAttempt?.key!==key)trainingAttempt={key,body:{...body,request_id:crypto.randomUUID()}};trainingBusy=true;decorateTrainingButtons();
 try{await trainingApi(trainingAttempt.body);trainingAttempt=null;if(scope===trainingScope()){await loadTrainingEditor(org);showToast(action==='approve'?'Reviewed card published.':'Card saved as a draft for independent review.');}}
 catch(e){if(scope===trainingScope())showToast(e.message);}finally{trainingBusy=false;decorateTrainingButtons();}
}
function decorateTrainingButtons(){const wrap=document.getElementById('training-editor');wrap.querySelectorAll('input,textarea,button,select').forEach(e=>{e.disabled=trainingBusy||(e.id!=='training-org'&&!trainingContext?.can_write);});wrap.querySelectorAll('button[onclick="approveTrainingCard()"]').forEach(e=>e.disabled=trainingBusy||!trainingContext?.can_review);}
async function saveTrainingCard(){
 const fields={};['heritage','brand_positioning','customer_profile','price_position','competitive_advantage','competitive_weakness','known_for','parent_company','country_of_origin','founded_year'].forEach(k=>fields[k]=document.getElementById('tc-'+k)?.value.trim()||null);
 fields.floor_talking_points=[...document.querySelectorAll('#tc-talking-points textarea')].map(e=>e.value.trim()).filter(Boolean);
 fields.common_objections=[...document.querySelectorAll('input[id^="tc-obj-q-"]')].map(e=>({objection:e.value.trim(),response:document.getElementById('tc-obj-a-'+e.id.replace('tc-obj-q-',''))?.value.trim()||''})).filter(o=>o.objection||o.response);
 await trainingWrite('save',fields);
}
async function approveTrainingCard(){await trainingWrite('approve');}
async function createTrainingCard(){await trainingWrite('create');}
`;
export function migrateBrandTraining(source){let s=source;
 const a=s.indexOf('async function loadTrainingEditor()'),b=s.indexOf('function renderTrainingEditor()',a);if(a<0||b<0)throw Error('Training load contract changed');s=s.slice(0,a)+trainingHelpers+'\n'+s.slice(b);
 const start=s.indexOf('async function saveTrainingCard()',s.indexOf('function addObjection()')),end=s.indexOf('function esc(s)',start);if(start<0||end<0)throw Error('Training write contract changed');s=s.slice(0,start)+s.slice(end);
 const ra=s.indexOf('function renderTrainingEditor()'),rb=s.indexOf('function addTalkingPoint()',ra);let render=s.slice(ra,rb).replaceAll('esc(', 'assetEscape(').replace('${ACTIVE_VENDOR.name} Training Card','${assetEscape(ACTIVE_VENDOR.name)} Training Card').replace('    return;','    decorateTrainingEditor();return;');render=render.replace('    </div>`;','    </div>`;\n  decorateTrainingEditor();');s=s.slice(0,ra)+render+s.slice(rb);
 if(/from\(['"]brand_training_cards['"]\)/.test(s))throw Error('Direct training access remains');return s;}
