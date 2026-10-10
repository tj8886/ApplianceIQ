export const logoHelpers=`
let speciqLogoSequence=0,speciqLogoBlob=null,speciqLogoAttempt=null,speciqLogoBusy=false;
async function speciqLogoApi(body){const r=await sb.rpc('speciq_logos',{p_body:body});if(r?.error||!r?.data?.ok)throw Error('Logo request failed. Reload settings if they changed, or retry the same file.');return r.data;}
async function renderNativeSettingsLogo(data){
 const ticket=++speciqLogoSequence,sequence=speciqSettingsSequence,org=userOrgId,logo=el('logo-preview');if(speciqLogoBlob){URL.revokeObjectURL(speciqLogoBlob);speciqLogoBlob=null;}logo.src='';logo.classList.add('hidden');
 if(typeof data.logo_url!=='string')return;
 if(data.logo_url.startsWith('https://')){logo.src=data.logo_url;logo.classList.remove('hidden');return;}
 if(!data.logo_url.startsWith('storage://tj-speciq-logos/'))return;
 try{const r=await speciqLogoApi({action:'read',organization_id:org});if(!r.storage_path)return;const downloaded=await sb.storage.from(r.bucket).download(r.storage_path);if(downloaded.error)throw Error('Logo download failed.');if(org!==userOrgId||sequence!==speciqSettingsSequence||ticket!==speciqLogoSequence)return;speciqLogoBlob=URL.createObjectURL(downloaded.data);logo.src=speciqLogoBlob;logo.classList.remove('hidden');if(retailerSettings)retailerSettings.logo_url=speciqLogoBlob;}catch(e){if(org===userOrgId&&sequence===speciqSettingsSequence)showSettingsStatus(e.message);}
}
window.handleLogoUpload=async e=>{
 const file=e.target.files?.[0];if(!file||speciqLogoBusy||speciqSettingsSaving)return;
 if(!speciqSettingsSnapshot?.can_edit||speciqSettingsSnapshot.organization_id!==userOrgId||!speciqSettingsSnapshot.updated_at){showSettingsStatus('Save settings as an owner/admin before uploading a logo.');return;}
 if(!['image/png','image/jpeg','image/webp'].includes(file.type)||file.size<1||file.size>2097152){showSettingsStatus('Choose a PNG, JPEG or WebP logo up to 2 MB.');return;}
 const pendingFields=Object.fromEntries(Object.keys(settingFields).map(id=>[id,el(id).value]));const org=userOrgId,stamp=speciqSettingsSnapshot.updated_at;speciqLogoBusy=true;el('logo-input').disabled=true;
 try{if(!speciqLogoAttempt||speciqLogoAttempt.file!==file||speciqLogoAttempt.org!==org)speciqLogoAttempt={file,org,stamp,request_id:crypto.randomUUID()};
 speciqLogoAttempt.bytes=await file.arrayBuffer();const r=await speciqLogoApi({action:'reserve',organization_id:org,request_id:speciqLogoAttempt.request_id,expected_updated_at:speciqLogoAttempt.stamp,mime_type:file.type,file_size:file.size});
 if(!r.completed){const uploaded=await sb.storage.from(r.bucket).upload(r.storage_path,file,{upsert:false,contentType:file.type});if(uploaded.error){const existing=await sb.storage.from(r.bucket).download(r.storage_path);const expected=new Uint8Array(speciqLogoAttempt.bytes),actual=existing.error?null:new Uint8Array(await existing.data.arrayBuffer());if(existing.error||existing.data.size!==file.size||!actual.every((v,i)=>v===expected[i]))throw Error('Logo upload failed; retry the same selected file.');}}
 await speciqLogoApi({action:'finalize',organization_id:org,upload_id:r.upload_id});speciqLogoAttempt=null;if(org===userOrgId){await loadRetailerSettings();Object.entries(pendingFields).forEach(([id,value])=>el(id).value=value);showSettingsStatus('Logo saved. Earlier files are retained.');}
 }catch(err){if(org===userOrgId)showSettingsStatus(err.message);}finally{speciqLogoBusy=false;el('logo-input').disabled=!speciqSettingsSnapshot?.can_edit;}
};
`;
export function migrateSpeciqLogos(source){let s=source;const a=s.indexOf('function renderNativeSettingsLogo(data){'),b=s.indexOf('async function loadRetailerSettings(){',a);if(a<0||b<0)throw Error('Logo renderer contract changed');s=s.slice(0,a)+logoHelpers+'\n'+s.slice(b);s=s.replace("window.handleLogoUpload=()=>showSettingsStatus('Native logo upload is pending the verified storage workflow.');",'');s=s.replace('id="logo-input" disabled accept="image/*"','id="logo-input" disabled accept="image/png,image/jpeg,image/webp"');s=s.replace('id="logo-zone"','id="logo-zone" onclick="el(\'logo-input\').click()"');s=s.replace('Logo upload pending','Upload logo (PNG/JPEG/WebP, 2 MB)');s=s.replace('Existing logos are retained. Native logo upload requires the verified storage workflow.','Upload a private organization logo. Earlier files are retained.');s=s.replace("el('save-settings-btn').disabled=!canEdit||speciqSettingsSaving;", "el('logo-input').disabled=!canEdit||speciqLogoBusy;el('save-settings-btn').disabled=!canEdit||speciqSettingsSaving;");return s;}
