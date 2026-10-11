// Restore the legacy tracker through a tenant-checked US gateway.
export function migrateMdfTracker(s){
 const replace=(a,b)=>{if(!s.includes(a))throw Error('MDF source contract changed: '+a.slice(0,60));s=s.replace(a,b);};
 const start=s.indexOf('const sb = {'),end=s.indexOf('\nconst fmt =',start);if(start<0||end<0)throw Error('MDF client changed');
 s=s.slice(0,start)+`const {createClient}=window.supabase;
const mdfAuth=createClient(SUPABASE_URL,SUPABASE_KEY);
async function mdfRpc(action,table,id,data,params){const r=await mdfAuth.rpc('mdf_tracker',{p_action:action,p_table:table||null,p_id:id||null,p_data:data||{},p_params:params||{}});if(r.error)throw Error('The operation could not be completed. '+(r.error.message||'Please retry.'));return r.data;}
async function mdfContext(){return mdfRpc('context');}
const sb={
 async get(table,params='',token){const options=Object.fromEntries(new URLSearchParams(params));delete options.limit;let all=[];for(let offset=0;offset<=10000;offset+=1000){const page=await mdfRpc('read',table,null,null,{...options,limit:1000,offset});all.push(...page);if(page.length<1000)return all;}throw Error('The report is too large to load completely. Narrow the export before continuing.');},
 async post(table,data){return mdfRpc('insert',table,null,data);},
 async patch(table,id,data){return mdfRpc('update',table,id,data);},
 async del(){throw Error('Source records are retained. Use a reviewed correction or ledger adjustment.');}
};
const authApi={
 async signIn(email,password){const r=await mdfAuth.auth.signInWithPassword({email,password});if(r.error)return {error_description:r.error.message,error:true};return {...r.data.session,user:r.data.user};},
 async getUser(){const r=await mdfAuth.auth.getUser();return r.error?null:r.data.user;},
 async resetPassword(email){const r=await mdfAuth.auth.resetPasswordForEmail(email,{redirectTo:location.origin+'/password-reset.html'});return !r.error;}
};
window.addEventListener('unhandledrejection',event=>{event.preventDefault();window.dispatchEvent(new CustomEvent('mdf:error',{detail:event.reason?.message||'The operation failed. Please retry.'}));});
`+s.slice(end);
 replace('const fmt = (n) => new Intl.NumberFormat("en-CA", { style: "currency", currency: "CAD" }).format(n || 0);','const fmt = (n) => n==null ? "—" : new Intl.NumberFormat("en-CA", { style: "currency", currency: "CAD" }).format(n);');
 const l=s.indexOf('  const handleLogin = async'),le=s.indexOf('  const handleReset =',l);if(l<0||le<0)throw Error('MDF login changed');
 s=s.slice(0,l)+`  const handleLogin=async(e)=>{e?.preventDefault();setError('');setLoading(true);try{const res=await authApi.signIn(email,password);if(res.error)throw Error(res.error_description||'Sign in failed');const ctx=await mdfContext();onLogin({...res,platformUser:ctx.profile,mdfContext:ctx});}catch(e){setError(e.message||'Sign in failed');}finally{setLoading(false);}};
  const handleSignup=async()=>{setError('Account access is managed through your ApplianceIQ organization.');setLoading(false);};
`+s.slice(le);
 replace('const [mode, setMode] = useState(startSignup ? "signup" : "login");','const [mode, setMode] = useState("login");');
 replace('<button type="button" onClick={()=>{setMode("signup");setError("");}} className="text-xs text-violet-600 hover:text-violet-800 font-medium">Create account →</button>','<span className="text-xs text-slate-500">Organization account required</span>');
 replace('if(ok)setResetSent(true);','if(ok)setResetSent(true);');
 // SDK storage is authoritative; neither legacy browser profile nor role is trusted.
 const boot=s.indexOf('  useEffect(()=>{try{const s=JSON.parse(localStorage.getItem("mdf_session"))');const bootEnd=s.indexOf('\n  const showToast=',boot);if(boot<0||bootEnd<0)throw Error('MDF startup changed');
 s=s.slice(0,boot)+`  useEffect(()=>{let active=true;async function boot(){try{const {data:{session:s}}=await mdfAuth.auth.getSession();if(s){const ctx=await mdfContext();if(active)setSession({...s,platformUser:ctx.profile,mdfContext:ctx});}}catch(e){if(active){setSession(null);setToast({message:e.message,type:'error'});}}finally{if(active)setLoading(false);}}boot();const ready=()=>boot();window.addEventListener('aiq:intelligence-ready',ready);const {data:{subscription}}=mdfAuth.auth.onAuthStateChange((event,s)=>{if(event==='SIGNED_OUT'&&active){setSession(null);setLoading(false);}});return()=>{active=false;subscription.unsubscribe();window.removeEventListener('aiq:intelligence-ready',ready);};},[]);
  useEffect(()=>{const fail=event=>{setToast({message:event.detail,type:'error'});setLoading(false);};window.addEventListener('mdf:error',fail);return()=>window.removeEventListener('mdf:error',fail);},[]);
  const currentUser=session?.platformUser;const role=currentUser?.role||'viewer';const token=session?.access_token;
  const handleLogin=s=>setSession(s);
  const handleLogout=async()=>{await mdfAuth.auth.signOut({scope:'local'});setSession(null);setTab('dashboard');};
`+s.slice(bootEnd);
 const log=s.indexOf('  const logAction=useCallback('),logEnd=s.indexOf('\n\n  const loadAll=',log);s=s.slice(0,log)+"  const logAction=useCallback(async()=>{},[]); // Atomic audit entries are recorded by the gateway.\n"+s.slice(logEnd);
 replace('const loadAll=useCallback(async()=>{if(!token)return;setLoading(true);','const loadAll=useCallback(async()=>{if(!token)return;setLoading(true);const fresh=await mdfContext();if(fresh.profile.role!==role){setSession({...session,platformUser:fresh.profile,mdfContext:fresh});return;}');
 replace('`owner_email=eq.${encodeURIComponent(currentUser?.email)}`','`id=eq.${session.mdfContext.organization_id}`');
 const exp=s.indexOf('    // Auto-run expiry checks'),expe=s.indexOf('\n  },[token,role]);',exp);if(exp<0||expe<0)throw Error('Expiry startup changed');s=s.slice(0,exp)+s.slice(expe);
 // Provider operations remain visibly unavailable until delivery/payment verification.
 s=s.replace(/const hasEmail=[^;]+;/g,'const hasEmail=false;');
 s=s.replace('showToast(status==="denied"?"Denied — submitter notified":`${status.replace(/_/g," ")} — notified`);','showToast(status==="denied"?"Denied":status.replace(/_/g," "));');
 const notify=s.indexOf('const sendNotification = async'),notifyEnd=s.indexOf('\nconst emailTemplates',notify);s=s.slice(0,notify)+"const sendNotification=async()=>{throw Error('Email delivery is not enabled for this workspace.');};\n"+s.slice(notifyEnd);
 s=s.replace('if(bd.ok)setBillingStatus(bd);','if(bd.ok)setBillingStatus({...bd,features:{email_notifications:false},email_delivery_enabled:false,billing_execution_enabled:false});');
 s=s.replace(/const startCheckout=async[\s\S]*?\n\n  const openPortal=async[^\n]+;/,"const startCheckout=async()=>showToast('Billing checkout is awaiting provider verification.','info');\n\n  const openPortal=async()=>showToast('Billing portal is awaiting provider verification.','info');");
 s=s.replace('sb.get("mdf_platform_users",','sb.get("mdf_platform_users",');
 // Keep zero-valued recorded evidence rather than falling back to gross sales/budgets.
 s=s.replaceAll('s.net_sales||s.gross_sales||0','s.net_sales??s.gross_sales??0').replaceAll('s.net_sales || s.gross_sales || 0','s.net_sales ?? s.gross_sales ?? 0');
 s=s.replace('remaining_amount:mf.remaining_amount?parseFloat(mf.remaining_amount):t','remaining_amount:mf.remaining_amount!==""&&mf.remaining_amount!=null?parseFloat(mf.remaining_amount):t');
 s=s.replace('const t=await fetch(`${SUPABASE_URL}/rest/v1/mdf_subscription_tiers?is_active=eq.true&order=price_monthly`,{headers:{apikey:SUPABASE_KEY,Authorization:`Bearer ${token}`}});if(t.ok)setTiers(await t.json());', 'setTiers(await sb.get("mdf_subscription_tiers","is_active=eq.true&order=price_monthly",token));');
 s=s.replace('<button type="button" onClick={()=>setMode("reset")} className="text-xs text-slate-500 hover:text-slate-700">Forgot password?</button>','<a href="/password-reset.html" className="text-xs text-slate-500 hover:text-slate-700">Forgot password?</a>');
 s=s.replace('const r=await sb.post("mdf_sales_data",{...mapped[i],import_batch_id:bid},token);if(r)ok++;else{fail++;errs.push(`Row ${i+2}`);}', 'try{await sb.post("mdf_sales_data",{...mapped[i],import_batch_id:bid,import_row_num:i+2},token);ok++;}catch(e){fail++;errs.push(`Row ${i+2}: ${e.message}`);}');
 s=s.replace('const mapped=getMapped();const bid=crypto.randomUUID();','const mapped=getMapped();if(mapped.length>200){showToast("Import at most 200 rows at a time.","error");setImporting(false);return;}const bid=crypto.randomUUID();');
 s=s.replace('{selected.size>0&&<Btn variant="danger" size="sm" onClick={bulkDelete}>Delete {selected.size}</Btn>}','');
 s=s.replaceAll('<button onClick={()=>setConfirmDel(s.id)}','<button disabled title="Recorded source retained" onClick={()=>setConfirmDel(s.id)}');
 s=s.replaceAll('<button onClick={()=>openEdit(s)}','<button disabled title="Recorded source retained" onClick={()=>openEdit(s)}');
 s=s.replace('{tab==="billing"&&<BillingPage {...ctx}/>}','{tab==="billing"&&<div className="bg-white p-6 rounded-xl"><h2 className="font-semibold">Recorded subscription information</h2><p className="text-sm mt-2">{org?.name} — recorded plan: {org?.tier_id||"Unknown"}; recorded status: {org?.subscription_status||"Unknown"}</p><p className="text-sm text-slate-600 mt-2">Billing checkout and email delivery await provider verification. Existing subscription evidence is retained.</p></div>}');
 s=s.replace('const ex=activeContracts[selectedBrand];if(ex)await sb.patch("mdf_brand_contracts",ex.id,{end_date:cf.effective_date},token);','');
 s=s.replace('if(!c){setRes({error:"No contract"});return;}','if(!c||!c.vr_enabled){setRes({error:"No enabled rebate contract"});return;}');
 s=s.replace('showToast(`VR: ${fmt(res.amt)}`);','showToast(`Recorded VR: ${fmt(r?.[0]?.rebate_amount)}`);');
 // User roles require explicit source identity binding: do not pretend adding an email grants access.
 s=s.replace('canManageUsers: (r) => ["super_admin","admin"].includes(r),','canManageUsers: (r) => ["super_admin","admin"].includes(r),');
 s=s.replace('{tab==="users"&&<UserManager {...ctx}/>}','{tab==="users"&&<div className="bg-white p-6 rounded-xl"><h2 className="font-semibold">Workspace access</h2><p className="text-sm text-slate-600 mt-2">Access uses verified ApplianceIQ accounts and active organization memberships.</p>{platformUsers.map(u=><p key={u.id} className="text-sm mt-2">{u.display_name} — {ROLE_LABELS[u.role]} — {u.is_active?"Active":"Inactive"}</p>)}</div>}');
 // Receipts/funds belong in the PDF as well as the dashboard.
 replace('  // Footer\n  const pages =',`  if(mdfFunds.length){if(y>210){doc.addPage();y=20;}doc.setFontSize(12);doc.text('MDF Funds — Recorded Amounts',14,y);y+=8;doc.autoTable({startY:y,head:[['Fund','Total','Remaining','Expires','Status']],body:mdfFunds.map(f=>[f.fund_label||'',fmt(f.total_amount),fmt(f.remaining_amount),f.expiry_date||'',f.status||'']),styles:{fontSize:8},margin:{left:14,right:14}});}
  // Footer
  const pages =`);
 // Failure notice clears component save spinners as well as the global loader.
 s=s.replace('function App() {','function App() {');
 return s;
}
