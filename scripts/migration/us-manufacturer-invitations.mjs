// Applied to generated US bundles only; Canadian source remains unchanged.
export function migrateManufacturerInvitations(source){
 let s=source;
 function block(start,end,replacement){const a=s.indexOf(start),b=s.indexOf(end,a+start.length);if(a<0||b<0)throw Error('Manufacturer source contract changed: '+start);s=s.slice(0,a)+replacement+'\n\n'+s.slice(b);}
 const helper=`function mfrEscape(value){return String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));}
async function manufacturerApi(body){
 let result;try{result=await sb.rpc('manufacturer_invites',{p_body:body});}catch{throw Error('Manufacturer access could not be checked. Try again.');}
 const {data,error}=result||{};
 if(error||!data)throw Error('Manufacturer access could not be checked. Try again.');
 if(!data.ok)throw Error(({identity_review_required:'Your account needs identity approval before manufacturer access can be activated.',email_confirmation_required:'Confirm your email, then sign in.',invite_unavailable:'This invitation cannot be accepted. Check the code and invited email, or request a new invitation.',membership_review_required:'Your existing brand membership needs an administrator review.',forbidden:'Administrator access is required.',vendor_unavailable:'Select an active brand.',invalid_request:'Check the invitation details.'})[data.error]||'This request could not be completed.');
 return data;
}
async function acceptManufacturerCode(){
 const code=(document.getElementById('si-code')?.value||document.getElementById('rg-code')?.value||'').trim();
 if(!code)return;
 await manufacturerApi({action:'accept',code});
 document.getElementById('si-code').value='';document.getElementById('rg-code').value='';
}
async function submitManufacturerCode(){
 document.getElementById('si-code').value=document.getElementById('brand-invite-code').value;
 await boot();
}`;
 block('async function loadVendorOptions(){','async function signIn(){',helper);
 block('async function signIn(){','async function register(){',`async function signIn(){
 msg('');const email=document.getElementById('si-email').value.trim(),password=document.getElementById('si-pass').value;
 if(!email||!password){msg('Enter your email and password.');return;}
 const {error}=await sb.auth.signInWithPassword({email,password});
 if(error){msg('Sign in failed. Check your email and password.');return;}
 await boot();
}`);
 block('async function register(){','async function signOut(){',`async function register(){
 msg('');const name=document.getElementById('rg-name').value.trim(),email=document.getElementById('rg-email').value.trim(),password=document.getElementById('rg-pass').value,code=document.getElementById('rg-code').value.trim();
 if(!name||!email||!password||!code){msg('Enter your name, email, password and invitation code.');return;}
 const {data,error}=await sb.auth.signUp({email,password,options:{data:{full_name:name}}});
 if(error){msg('Account creation failed. Try signing in or check your details.');return;}
 document.getElementById('si-email').value=email;
 document.getElementById('si-code').value=code;
 if(!data?.session){switchTab('signin');msg('Confirm your email, then sign in with the invited email. Your brand access also requires identity approval.','ok');return;}
 await boot();
}`);
 block('async function boot(){','function render(){',`async function boot(){
 try{
 const {data:{user},error}=await sb.auth.getUser();
 if(error||!user){document.getElementById('auth-screen').style.display='flex';document.getElementById('app').style.display='none';return;}
 ME=user;await acceptManufacturerCode();
 const context=await manufacturerApi({action:'context'});MYROLE=context.role;MYVENDORS=context.vendors;ACTIVE_VENDOR=MYVENDORS[0]||null;
 CATS=await (await fetch('mfr_categories.json')).json();
 document.getElementById('auth-screen').style.display='none';document.getElementById('app').style.display='block';render();
 }catch(e){document.getElementById('auth-screen').style.display='flex';document.getElementById('app').style.display='none';switchTab('signin');msg(mfrEscape(e.message||'Manufacturer access could not be loaded.'));}
}`);
 block('function renderAdminShell(){','// ---------- TRAINING EDITOR ----------',`function renderAdminShell(){return '<h1 class="page-title">Vendors & Invitations</h1><p class="page-sub">Invite an approved account to an active brand as a product editor. Share the new code directly with the invited recipient. Codes expire after seven days.</p><div id="admin-content"></div>';}
async function loadAdmin(){
 const el=document.getElementById('admin-content');
 try{const data=await manufacturerApi({action:'list'});
 el.innerHTML='<div class="admin-card"><h3>Create an Invitation</h3><div class="field"><label>Email</label><input type="email" id="inv-email"></div><div class="field"><label>Brand</label><select id="inv-vendor"><option value="">Select an active brand</option>'+data.vendors.map(v=>'<option value="'+mfrEscape(v.id)+'">'+mfrEscape(v.name)+'</option>').join('')+'</select></div><button class="btn" onclick="sendInvite()">Create Invite</button><div id="inv-msg"></div></div><div class="admin-card"><h3>Recent Invitations (up to 100)</h3><table><thead><tr><th>Email</th><th>Brand</th><th>Status</th><th>Expires</th><th></th></tr></thead><tbody>'+data.invites.map(i=>'<tr><td>'+mfrEscape(i.email)+'</td><td>'+mfrEscape(i.vendor_name)+'</td><td>'+mfrEscape(i.status)+'</td><td>'+mfrEscape(i.expires_at)+'</td><td>'+(i.status==='pending'?'<button data-invite-id="'+mfrEscape(i.id)+'">Revoke</button>':'')+'</td></tr>').join('')+'</tbody></table></div>';
 el.querySelectorAll('[data-invite-id]').forEach(b=>b.onclick=async()=>{try{await manufacturerApi({action:'revoke',invite_id:b.dataset.inviteId});await loadAdmin();}catch(e){document.getElementById('inv-msg').textContent=e.message;}});
 }catch(e){el.textContent=e.message;}
}
async function sendInvite(){
 const m=document.getElementById('inv-msg'),email=document.getElementById('inv-email').value.trim(),vendor_id=document.getElementById('inv-vendor').value;
 m.textContent='';if(!email||!vendor_id){m.textContent='Enter an email and select a brand.';return;}
 try{const data=await manufacturerApi({action:'create',email,vendor_id});await loadAdmin();
 document.getElementById('inv-msg').innerHTML='<div class="msg ok">Share this code with '+mfrEscape(data.email)+' for '+mfrEscape(data.vendor_name)+': <code>'+mfrEscape(data.code)+'</code><br>Expires '+mfrEscape(data.expires_at)+'. Copy it now; it will not be shown again.</div>';
 }catch(e){document.getElementById('inv-msg').textContent=e.message;}
}`);
 s=s.replace('<button class="btn" onclick="signIn()">Sign In</button>','<div class="field"><label>Invitation code (if invited)</label><input id="si-code" autocomplete="off"></div><button class="btn" onclick="signIn()">Sign In</button>');
 block('      <div class="field">\n        <label>Your brand</label>','      <div class="field"><label>Invite code', '      <p class="hint">Brand access is assigned by your invitation after email confirmation and identity approval.</p>');
 s=s.replace('(optional)</span></label><input type="text" id="rg-code"','(required)</span></label><input type="text" id="rg-code"');
 s=s.replace('By registering you can upload and manage content for your brand only.','An approved invitation grants product-editor access to its brand.');
 s=s.replace("You're not linked to a brand yet. If you registered, your brand may be pending setup. Contact the ApplianceIQ team.","You have no active brand membership. Enter an invitation code or contact the ApplianceIQ team.<div class=\"field\"><input id=\"brand-invite-code\" autocomplete=\"off\"></div><button class=\"btn\" onclick=\"submitManufacturerCode()\">Accept Invitation</button>");
 s=s.replace('approveTrainingCard,approveVendor,','approveTrainingCard,submitManufacturerCode,');
 if(/from\(['"](?:mfr_invites|mfr_members|mfr_user_roles)['"]\)/.test(s)||s.includes('approveVendor(')||s.includes('Math.random()'))throw Error('Legacy manufacturer onboarding remains');
 return s;
}
