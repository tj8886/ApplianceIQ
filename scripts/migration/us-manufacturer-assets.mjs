// Native US asset workflow. API resolves source actor and organization/vendor authority.
export const assetClientHelpers=`
const ASSET_BUCKET='tj-mfr-assets';
function assetEscape(v){return String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));}
async function assetsApi(body){
 let result;try{result=await sb.rpc('manufacturer_assets',{p_body:body});}catch{throw Error('The asset request could not be completed. Try again.');}
 if(result?.error||!result?.data)throw Error('The asset request could not be completed. Try again.');
 const data=result.data;if(!data.ok)throw Error(({identity_review_required:'Your account needs identity approval.',email_confirmation_required:'Confirm your email, then sign in.',organization_access_required:'Your account needs active organization and brand access.',trade_access_required:'Your account needs approved builder or designer access.',forbidden:'You do not have permission for this asset action.',asset_unavailable:'This asset is unavailable.',vendor_unavailable:'This brand is unavailable.',upload_incomplete:'The file upload is incomplete. Try uploading again.',invalid_request:'Check the title, category, audiences, HTTPS link or supported file (maximum 20 MB).'})[data.error]||'The asset request could not be completed.');
 return data;
}
async function downloadNativeAsset(asset){
 if(asset.external_url){const u=new URL(asset.external_url);if(u.protocol!=='https:'||u.username||u.password)throw Error('This link is unavailable.');window.open(u.href,'_blank','noopener,noreferrer');return;}
 const {data,error}=await sb.storage.from(ASSET_BUCKET).download(asset.storage_path);
 if(error||!data)throw Error('The file could not be downloaded. Your access may have changed.');
 const url=URL.createObjectURL(data),a=document.createElement('a');a.href=url;a.download=asset.file_name||'asset';document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),60000);
}
`;
export function migrateManufacturerAssets(source){
 let s=source;
 function block(start,end,text){const a=s.indexOf(start),b=s.indexOf(end,a+start.length);if(a<0||b<0)throw Error('Manufacturer asset source contract changed: '+start);s=s.slice(0,a)+text+'\n\n'+s.slice(b);}
 block('let ASSETS=[];','// ---------- UPLOAD MODAL ----------',assetClientHelpers+`
let ASSETS=[],ASSET_ORG=null,ASSET_CAN_WRITE=false,ASSET_CAN_REVIEW=false;
async function loadAssets(org){
 const vendor_id=ACTIVE_VENDOR.id;
 try{const data=await assetsApi({action:'list',vendor_id,...((org||ASSET_ORG)?{organization_id:org||ASSET_ORG}:{})});
 if(ACTIVE_VENDOR.id!==vendor_id)return;
 ASSET_ORG=data.organization_id;ASSET_CAN_WRITE=data.can_write;ASSET_CAN_REVIEW=data.can_review;ASSETS=data.assets;
 renderCatGroups(data.organizations);
 }catch(e){ASSETS=[];document.getElementById('cat-groups').textContent=e.message;}
}
function renderCatGroups(organizations){
 const wrap=document.getElementById('cat-groups');
 wrap.innerHTML='<div class="field"><label>Organization</label><select id="asset-org">'+organizations.map(o=>'<option value="'+assetEscape(o.id)+'" '+(o.id===ASSET_ORG?'selected':'')+'>'+assetEscape(o.name)+'</option>').join('')+'</select></div><p class="hint">Up to 200 recent items. New items require review before trade publication.</p>'+CATS.groups.map(g=>'<div class="cat-group"><div class="cat-group-title">'+assetEscape(g.group)+'</div><div class="cat-grid">'+g.cats.map(c=>{
 const files=ASSETS.filter(a=>a.category===c.key);
 return '<div class="cat-card"><div class="cat-card-head"><div class="cat-name">'+assetEscape(c.label)+'</div><span class="cat-count">'+files.length+'</span></div><div class="cat-files">'+(files.length?files.map(f=>'<div class="file-row"><span class="fn">'+assetEscape(f.title)+' <small>'+(f.upload_state!=='ready'?'Upload incomplete':f.is_published?'Published':'Awaiting review')+'</small></span>'+(f.upload_state==='ready'?'<button data-open="'+f.id+'">Open</button>':'')+(ASSET_CAN_REVIEW&&f.upload_state==='ready'&&!f.is_published?'<button data-review="'+f.id+'">Publish</button>':'')+(ASSET_CAN_WRITE?'<button data-archive="'+f.id+'">Archive</button>':'')+'</div>').join(''):'<div class="hint">Nothing uploaded yet.</div>')+'</div>'+(ASSET_CAN_WRITE?'<button class="btn-add" data-category="'+assetEscape(c.key)+'">+ Add</button>':'')+'</div>';
 }).join('')+'</div></div>').join('');
 document.getElementById('asset-org').onchange=e=>{ASSET_ORG=e.target.value;loadAssets();};
 wrap.querySelectorAll('[data-category]').forEach(b=>b.onclick=()=>openUpload(b.dataset.category));
 wrap.querySelectorAll('[data-open]').forEach(b=>b.onclick=()=>openNativeAsset(b.dataset.open));
 wrap.querySelectorAll('[data-review]').forEach(b=>b.onclick=()=>publishNativeAsset(b.dataset.review));
 wrap.querySelectorAll('[data-archive]').forEach(b=>b.onclick=()=>delAsset(b.dataset.archive));
}
async function openNativeAsset(id){try{await downloadNativeAsset(ASSETS.find(a=>a.id===id));}catch(e){showToast(e.message);}}
async function publishNativeAsset(id){if(!confirm('Publish this reviewed item to its selected trade audiences?'))return;try{await assetsApi({action:'publish',asset_id:id});await loadAssets();}catch(e){showToast(e.message);}}
`);
 block('async function saveAsset(){','// ---------- ADMIN ----------',`async function saveAsset(){
 umMsg('');if(!ASSET_CAN_WRITE||!ASSET_ORG){umMsg('Organization and brand edit access are required.');return;}
 const title=document.getElementById('um-t').value.trim();if(!title||!UM_AUD.length){umMsg('Enter a title and select at least one audience.');return;}
 const btn=document.getElementById('um-save');btn.disabled=true;btn.textContent='Saving…';
 try{
 const body={organization_id:ASSET_ORG,vendor_id:ACTIVE_VENDOR.id,category:UM_CAT.key,title,description:document.getElementById('um-desc').value.trim(),model:document.getElementById('um-model').value.trim(),audiences:UM_AUD};
 if(UM_SRC==='link'){
 const url=new URL(document.getElementById('um-link').value.trim());if(url.protocol!=='https:'||url.username||url.password)throw Error('Use an HTTPS link without embedded credentials.');
 await assetsApi({...body,action:'create_link',external_url:url.href});
 }else{
 const file=document.getElementById('um-file').files[0];if(!file||file.size<1||file.size>20971520)throw Error('Choose a supported file up to 20 MB.');
 const file_name=file.name.replace(/[^A-Za-z0-9._-]/g,'_').replace(/^[^A-Za-z0-9]+/,'').slice(-124);
 const mime_type=file.type||'application/octet-stream';
 const reserved=await assetsApi({...body,action:'reserve_upload',file_name,mime_type,file_size_bytes:file.size});
 const {error}=await sb.storage.from(ASSET_BUCKET).upload(reserved.storage_path,file,{upsert:false,contentType:mime_type});
 if(error)throw Error('The file upload failed. The incomplete item can be archived, then uploaded again.');
 await assetsApi({action:'finalize',asset_id:reserved.asset_id});
 }
 closeUpload();await loadAssets();showToast('Saved for review.');
 }catch(e){umMsg(assetEscape(e.message||'The asset could not be saved.'));}
 finally{btn.disabled=false;btn.textContent='Save';}
}
async function delAsset(id){
 if(!confirm('Archive this item and close access? The stored file will be retained.'))return;
 try{await assetsApi({action:'archive',asset_id:id});await loadAssets();}catch(e){showToast(e.message);}
}
`);
 s=s.replace("function setVendor(id){ ACTIVE_VENDOR=MYVENDORS.find(v=>v.id===id); render(); }","function setVendor(id){ ACTIVE_VENDOR=MYVENDORS.find(v=>v.id===id); ASSET_ORG=null; render(); }");
 if(s.includes("from('mfr_assets')")||s.includes('.getPublicUrl(')||s.includes('.storage.from(STORAGE_BUCKET)'))throw Error('Legacy manufacturer asset access remains');
 return s;
}
export function migrateTradeAssets(source){
 if(source.includes("const ASSET_BUCKET="))throw Error("Trade asset source contract changed: already transformed");
 let s=source;
 function block(start,end,text){const a=s.indexOf(start),b=s.indexOf(end,a+start.length);if(a<0||b<0)throw Error('Trade asset source contract changed: '+start);s=s.slice(0,a)+text+'\n\n'+s.slice(b);}
 block('async function register(){','async function signOut(){',`async function register(){
 msg('');const name=document.getElementById('rg-name').value.trim(),firm=document.getElementById('rg-firm').value.trim(),email=document.getElementById('rg-email').value.trim(),password=document.getElementById('rg-pass').value;
 if(!name||!email||!password){msg('Enter your name, email and password.');return;}
 const {data,error}=await sb.auth.signUp({email,password,options:{data:{full_name:name,firm}}});
 if(error){msg('Account creation failed. Check your details or sign in.');return;}
 if(!data?.session){switchTab('signin');msg('Confirm your email, then sign in. Trade access also requires identity, organization and role approval.','ok');return;}
 await boot();
}`);
 block('async function boot(){','function initials(name){',assetClientHelpers+`
async function boot(){
 try{const {data:{user},error}=await sb.auth.getUser();
 if(error||!user){document.getElementById('auth-screen').style.display='flex';document.getElementById('app').style.display='none';return;}
 ME=user;const context=await assetsApi({action:'trade'});MYAUD=context.audience;VENDORS=context.vendors;ASSETS=context.assets;
 CATS=await (await fetch('mfr_categories.json')).json();
 document.getElementById('auth-screen').style.display='none';document.getElementById('app').style.display='block';render();
 }catch(e){document.getElementById('auth-screen').style.display='flex';document.getElementById('app').style.display='none';msg(assetEscape(e.message));}
}
async function openTradeAsset(id){try{await downloadNativeAsset(ASSETS.find(a=>a.id===id));}catch(e){document.getElementById('vendor-list').textContent=e.message;}}
`);
 block('function render(){','[signIn,signOut,register,',`
function render(){
 document.getElementById('role-chip').textContent=MYAUD;
 const body=document.getElementById('app-body');
 body.innerHTML='<h1 class="page-title">'+(MYAUD==='builder'?'Builder':'Designer')+' Resource Portal</h1><p class="page-sub">Approved resources available to your organizations. Up to 200 recent items.</p><input class="search" id="search" placeholder="Search brands, models and documents"><div id="vendor-list"></div>';
 document.getElementById('search').oninput=e=>onSearch(e.target.value);renderList();
}
function onSearch(value){SEARCH=value.toLowerCase();renderList();}
function setFilter(value){FILTER=value;renderList();}
function renderList(){
 const wrap=document.getElementById('vendor-list');
 wrap.innerHTML=VENDORS.filter(v=>FILTER==='All'||v.tier===FILTER).map(v=>{
 const items=ASSETS.filter(a=>a.vendor_id===v.id&&(!SEARCH||[v.name,a.title,a.model,a.description].join(' ').toLowerCase().includes(SEARCH)));
 if(!items.length)return '';
 return '<div class="v-section open"><h2>'+assetEscape(v.name)+'</h2>'+items.map(a=>'<div class="asset"><div class="asset-info"><div class="asset-title">'+assetEscape(a.title)+'</div><div class="asset-note">'+assetEscape(CAT_LABEL[a.category]||a.category)+' '+assetEscape(a.model||'')+'</div></div><button class="btn" data-asset-id="'+a.id+'">'+(a.external_url?'Open Link':'Download')+'</button></div>').join('')+'</div>';
 }).join('')||'<div class="empty">No approved resources match your access and search.</div>';
 wrap.querySelectorAll('[data-asset-id]').forEach(b=>b.onclick=()=>openTradeAsset(b.dataset.assetId));
}
`);
 if(/from\(['"](?:mfr_assets|mfr_user_roles)['"]\)/.test(s)||s.includes('file_url'))throw Error('Legacy trade asset access remains');
 return s;
}
