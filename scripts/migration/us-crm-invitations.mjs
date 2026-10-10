// Transform only the unpublished US bundle; Canadian source behavior is preserved.
export function migrateCrmInvitations(source) {
  const anchor='  currentUser=session.user;showApp();';
  const legacy="  const ic=new URLSearchParams(location.search).get('invite');if(ic)await acceptInvite(ic);";
  if(!source.includes(anchor)||!source.includes(legacy)||!source.includes("sb.rpc('accept_invite'"))throw Error('CRM invitation source contract changed');
  source=source.replace(anchor,anchor+`\n  let invitedOrg=null;\n  const inviteCode=new URLSearchParams(location.search).get('invite');\n  if(inviteCode){const accepted=await acceptInvite(inviteCode);if(!accepted)return;invitedOrg=accepted.organization_id;}`);
  source=source.replace(legacy,'');
  source=source.replace(/^  if\(!orgs.length\)\{await sb.rpc\('join_demo_org'\);.*$/m,'');
  source=source.replace(/^  if\(!orgs.length\)\{mainEl.innerHTML=.*$/m,`  if(!orgs.length){mainEl.innerHTML='<div class="empty" style="max-width:400px;margin:60px auto;text-align:center"><h2>Welcome to ApplianceIQ CRM</h2><p>Ask your organization administrator for an invitation link, then sign in with the invited email address.</p></div>';return;}`);
  source=source.replace('  currentOrg=orgs[0];','  currentOrg=orgs.find(o=>o.id===invitedOrg)||orgs[0];');
  const replacement=`async function acceptInvite(code){
  const{data,error}=await sb.rpc('accept_org_invite',{p_code:code});
  if(error||data?.ok!==true){
    const messages={email_confirmation_required:'Confirm your email address, then open this invitation again.',email_mismatch:'Sign in with the email address this invitation was sent to.',expired:'This invitation has expired. Ask your administrator for a new link.',invalid_or_used:'This invitation is invalid or has already been used.',identity_review_required:'Your account needs administrator review before joining.',membership_review_required:'Your membership needs administrator review before joining.',invite_no_longer_authorized:'This invitation is no longer authorized. Ask your administrator for a new link.'};
    const message=error?'Unable to accept the invitation. Please try again.':messages[data?.error]||'Unable to accept the invitation. Ask your administrator for help.';
    alert(message);mainEl.textContent=message;return null;
  }
  const u=new URL(location.href);u.searchParams.delete('invite');history.replaceState(null,'',u);
  return data;
}`;
  source=source.replace(/^async function acceptInvite\(code\)\{.*$/m,()=>replacement);
  if(source.includes("sb.rpc('accept_invite'")||source.includes("sb.rpc('join_demo_org'"))throw Error('Legacy CRM onboarding RPC remains');
  return source;
}
