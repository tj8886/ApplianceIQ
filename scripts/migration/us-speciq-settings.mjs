export const settingsHelpers=`
let speciqSettingsSnapshot=null,speciqSettingsAttempt=null,speciqSettingsSaving=false,speciqSettingsSequence=0;
const settingFields={'s-name':'store_name','s-phone':'store_phone','s-email':'store_email','s-website':'store_website','s-address':'store_address','s-city':'store_city','s-province':'store_province','s-postal':'store_postal','s-welcome':'default_welcome_message','s-disclaimer':'default_disclaimer','s-color1-hex':'primary_color','s-color2-hex':'secondary_color','s-validity-days':'default_validity_days','s-max-rep-days':'max_rep_validity_days','s-max-mgr-days':'max_manager_validity_days','s-max-sm-days':'max_store_manager_validity_days','s-validity-disclaimer':'validity_disclaimer','s-commercial-disclaimer':'commercial_disclaimer'};
async function speciqSettingsApi(body){
 let r;try{r=await sb.rpc('speciq_settings',{p_body:body});}catch{throw Error('Settings request could not be completed. Try again to check the save.');}
 if(r?.error||!r?.data)throw Error('Settings request could not be completed. Try again to check the save.');
 if(!r.data.ok)throw Error(({revision_conflict:'Settings changed. Reload Settings before saving again.',organization_admin_required:'An organization owner or admin must save settings.',invalid_request:'Check field lengths, email, HTTPS website, hex colors and ordered validity limits (1–365 days).',request_conflict:'This retry differs from the original save.'})[r.data.error]||'Settings are unavailable. Check your current organization access.');return r.data;
}
function showSettingsStatus(text){el('settings-saved-msg').textContent=text;el('settings-saved-msg').classList.remove('hidden');}
function renderNativeSettings(data,canEdit){
 Object.entries(settingFields).forEach(([id,key])=>{el(id).value=data[key]??'';el(id).disabled=!canEdit;});
 [['s-color1','primary_color'],['s-color2','secondary_color']].forEach(([id,key])=>{el(id).value=data[key]||'#0f1f3d';el(id).disabled=!canEdit;el(id).oninput=()=>el(id+'-hex').value=el(id).value;});
 el('save-settings-btn').disabled=!canEdit||speciqSettingsSaving;el('clear-settings-logo').disabled=!canEdit||speciqSettingsSaving;
 renderNativeSettingsLogo(data);
}
function renderNativeSettingsLogo(data){const logo=el('logo-preview');logo.src='';logo.classList.add('hidden');if(typeof data.logo_url==='string'&&data.logo_url.startsWith('https://')){logo.src=data.logo_url;logo.classList.remove('hidden');}}
async function loadRetailerSettings(){
 const sequence=++speciqSettingsSequence,org=userOrgId;retailerSettings=null;speciqSettingsSnapshot=null;speciqSettingsAttempt=null;renderNativeSettings({},false);
 if(!org){showSettingsStatus('Choose an organization to load settings.');return;}
 try{const r=await speciqSettingsApi({action:'get',organization_id:org});if(sequence!==speciqSettingsSequence||org!==userOrgId)return;
 retailerSettings=r.settings;speciqSettingsSnapshot={organization_id:org,updated_at:r.settings.updated_at??null,can_edit:r.can_edit};renderNativeSettings(r.settings,r.can_edit);
 showSettingsStatus(r.can_edit?(r.stored?'Stored settings loaded.':'Defaults shown; nothing is saved until an owner or admin saves.'):'Read only. An organization owner or admin can save settings.');
 }catch(e){if(sequence===speciqSettingsSequence&&org===userOrgId)showSettingsStatus(e.message);}
}
async function saveNativeSettings(action){
 if(speciqSettingsSaving)return;
 if(!speciqSettingsSnapshot?.can_edit||speciqSettingsSnapshot.organization_id!==userOrgId){showSettingsStatus('Load settings with organization owner or admin access first.');return;}
 speciqSettingsSaving=true;Object.keys(settingFields).concat(['s-color1','s-color2']).forEach(id=>el(id).disabled=true);el('save-settings-btn').disabled=true;el('clear-settings-logo').disabled=true;const org=userOrgId,sequence=speciqSettingsSequence;
 try{
 const body={action,organization_id:org,expected_updated_at:speciqSettingsSnapshot.updated_at};
 if(action==='save'){const settings={};Object.entries(settingFields).forEach(([id,key])=>{const value=String(el(id).value).trim();if(key.endsWith('_days')){if(!/^[0-9]{1,3}$/.test(value))throw Error('Validity limits must be whole days between 1 and 365.');settings[key]=Number(value);}else settings[key]=value||null;});body.settings=settings;}
 const fingerprint=JSON.stringify(body);if(speciqSettingsAttempt?.fingerprint!==fingerprint)speciqSettingsAttempt={fingerprint,request_id:crypto.randomUUID()};
 const r=await speciqSettingsApi({...body,request_id:speciqSettingsAttempt.request_id});
 if(org!==userOrgId||sequence!==speciqSettingsSequence)return;
 retailerSettings=r.settings;speciqSettingsSnapshot.updated_at=r.settings.updated_at;speciqSettingsAttempt=null;if(action==='clear_logo')renderNativeSettingsLogo(r.settings);else renderNativeSettings(r.settings,true);showSettingsStatus(action==='clear_logo'?'Logo reference cleared; the file is retained.':'Settings saved. Final quote enforcement remains pending.');
 }catch(e){if(org===userOrgId&&sequence===speciqSettingsSequence)showSettingsStatus(e.message);}
 finally{speciqSettingsSaving=false;const enabled=speciqSettingsSnapshot?.can_edit&&speciqSettingsSnapshot.organization_id===userOrgId;Object.keys(settingFields).concat(['s-color1','s-color2']).forEach(id=>el(id).disabled=!enabled);el('save-settings-btn').disabled=!enabled;el('clear-settings-logo').disabled=!enabled;}
}
window.saveRetailerSettings=()=>saveNativeSettings('save');
window.removeLogo=()=>saveNativeSettings('clear_logo');
window.handleLogoUpload=()=>showSettingsStatus('Native logo upload is pending the verified storage workflow.');
`;
export function migrateSpeciqSettings(source){
 let s=source;const a=s.indexOf('async function loadRetailerSettings(){'),b=s.indexOf('/* ==================== TEAM MANAGEMENT',a);if(a<0||b<0)throw Error('Spec IQ settings contract changed');s=s.slice(0,a)+settingsHelpers+'\n'+s.slice(b);
 s=s.replace('Configure your store branding, quote defaults, and approval rules.','Save organization branding and quote defaults. Final quote enforcement remains pending.');
 s=s.replace('id="logo-zone" onclick="document.getElementById(\'logo-input\').click()"','id="logo-zone"');
 s=s.replace('Click to upload','Logo upload pending');s=s.replace('id="logo-input" accept="image/*"','id="logo-input" disabled accept="image/*"');
 s=s.replace('Upload your store logo for cover pages.','Existing logos are retained. Native logo upload requires the verified storage workflow.');
 s=s.replace('<button class="btn btn-g" style="font-size:13px;color:var(--danger)" onclick="removeLogo()">Remove logo</button>','<button id="clear-settings-logo" class="btn btn-g" disabled style="font-size:13px;color:var(--danger)" onclick="removeLogo()">Clear logo reference</button>');
 s=s.replace('id="save-settings-btn" onclick','id="save-settings-btn" disabled onclick');
 s=s.replace('id="s-website" placeholder="www.yourstore.com"','id="s-website" placeholder="https://yourstore.com"');
 const old="if(!retailerSettings){const{data:rs}=await sb.from('speciq_retailer_settings').select('*').eq('organization_id',userOrgId).single();retailerSettings=rs}";s=s.replaceAll(old,'if(!retailerSettings)await loadRetailerSettings();');return s;
}
