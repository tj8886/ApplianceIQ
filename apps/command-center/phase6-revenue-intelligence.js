import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';

const sb = createClient('https://fumwwhyozeouoqscolke.supabase.co','sb_publishable_wiP3ouBdS_Qub9EMIYJK7w_eiltZHKV');
const money = v => v == null ? 'Not yet quantified' : new Intl.NumberFormat('en-CA',{style:'currency',currency:'CAD',maximumFractionDigits:0}).format(Number(v||0));
const esc = s => String(s ?? '').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const pct = v => `${Math.round(Number(v||0))}%`;

function installStyles(){
  if(document.getElementById('phase6-styles')) return;
  const s=document.createElement('style'); s.id='phase6-styles'; s.textContent=`
    .p6-head{background:linear-gradient(135deg,#0f1f3d,#123b54);color:#fff;border:0}.p6-head .muted{color:#cbd5e1}
    .p6-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:12px;margin-top:14px}
    .p6-mini{background:rgba(255,255,255,.09);padding:14px;border-radius:12px}.p6-mini strong{display:block;font-size:25px;margin-top:3px}
    .p6-action{display:grid;grid-template-columns:1.35fr .8fr auto;gap:16px;align-items:center}.p6-money{font-size:20px;font-weight:850}.p6-confidence{font-size:11px;color:#64748b;margin-top:4px}
    .p6-rank{font-weight:900;font-size:18px}.p6-model{font-size:11px;color:#64748b;margin-top:7px}.p6-toolbar{display:flex;gap:8px;align-items:center;flex-wrap:wrap}
    @media(max-width:900px){.p6-action{grid-template-columns:1fr}}
  `; document.head.appendChild(s);
}

function installShell(){
  if(document.getElementById('phase6Revenue')) return;
  const coaching=document.getElementById('coaching'); if(!coaching) return;
  const wrap=document.createElement('div'); wrap.id='phase6Revenue';
  wrap.innerHTML=`
    <div class="section-title"><div><h2>Revenue Intelligence</h2><div class="muted">The highest-impact things a manager can do next, ranked by evidence and financial effect</div></div><div class="p6-toolbar"><button class="secondary" id="p6Refresh">Refresh opportunities</button></div></div>
    <div id="p6Summary"></div><div id="p6Actions"></div>`;
  coaching.insertAdjacentElement('afterend',wrap);
  document.getElementById('p6Refresh').onclick=()=>loadPhase6(true);
}

function currentOrg(){ return document.getElementById('org')?.value || null; }

function render(data){
  const s=data?.summary||{};
  document.getElementById('p6Summary').innerHTML=`<div class="card p6-head"><strong style="font-size:18px">Manager Opportunity Engine</strong><div class="muted">Financial estimates are shown only when the underlying evidence supports a defensible calculation.</div><div class="p6-grid"><div class="p6-mini"><span>Open actions</span><strong>${s.open_actions||0}</strong></div><div class="p6-mini"><span>High priority</span><strong>${s.high_priority||0}</strong></div><div class="p6-mini"><span>Revenue opportunity</span><strong>${money(s.estimated_revenue_impact||0)}</strong></div><div class="p6-mini"><span>Margin opportunity</span><strong>${money(s.estimated_margin_impact||0)}</strong></div><div class="p6-mini"><span>Dollar-quantified</span><strong>${s.financially_quantified||0}</strong></div></div></div>`;
  const actions=data?.actions||[];
  document.getElementById('p6Actions').innerHTML=actions.map((a,i)=>{
    const dollars=a.estimated_margin_impact!=null?a.estimated_margin_impact:a.estimated_revenue_impact;
    const impactLabel=a.estimated_margin_impact!=null?'Estimated margin impact':a.estimated_revenue_impact!=null?'Estimated revenue impact':'Financial impact';
    const model=a.financial_model?.method==='severity_only'?'Awaiting enough POS/CRM evidence for a defensible dollar estimate':(a.financial_model?.method||'evidence-based');
    const pri=Number(a.priority_score||0); const cls=pri>=70?'critical':pri>=45?'high':pri>=25?'medium':'low';
    return `<div class="card p6-action"><div><span class="badge ${cls}">#${i+1} · ${Math.round(pri)} priority</span><h3 style="margin:8px 0 5px">${esc(a.title)}</h3><div>${esc(a.diagnosis)}</div><div class="coach-action">${esc(a.recommended_action)}</div><div class="p6-model">${esc(model)} · confidence ${pct(Number(a.impact_confidence||0)*100)}</div></div><div><div class="muted">${esc(impactLabel)}</div><div class="p6-money">${money(dollars)}</div>${a.actual_value!=null?`<div class="metric">Actual ${esc(a.actual_value)} · Target ${esc(a.target_value)} · Gap ${pct(a.severity_pct)}</div>`:''}</div><div class="actions"><button class="secondary" data-p6-open="${a.id}" data-module="${esc(a.action_module)}" data-subject="${a.subject_id||''}" data-type="${esc(a.subject_type)}">Open ${esc(a.action_module)}</button><button class="primary" data-p6-accept="${a.id}">${a.manager_assignment_id?'Assigned':'Create manager action'}</button></div></div>`;
  }).join('') || '<div class="card empty">No open revenue opportunities. Either everything is perfect, which would be suspicious, or more operating evidence needs to arrive.</div>';
  document.querySelectorAll('[data-p6-accept]').forEach(b=>b.onclick=()=>acceptAction(b.dataset.p6Accept));
  document.querySelectorAll('[data-p6-open]').forEach(b=>b.onclick=()=>openModule(b.dataset.module,b.dataset.type,b.dataset.subject));
}

async function loadPhase6(refresh=false){
  const org=currentOrg(); if(!org) return;
  const {data:{session}}=await sb.auth.getSession(); if(!session) return;
  if(refresh){ const r=await sb.rpc('phase6_refresh_revenue_opportunities',{p_organization_id:org}); if(r.error){console.error(r.error);return;} }
  const {data,error}=await sb.rpc('phase6_command_center',{p_organization_id:org,p_limit:25});
  if(error){ console.error('Phase 6',error); document.getElementById('p6Actions').innerHTML=`<div class="card notice error">${esc(error.message)}</div>`; return; }
  render(data||{});
}

async function acceptAction(id){
  const {data,error}=await sb.rpc('phase6_accept_action',{p_opportunity_id:id});
  if(error){alert(error.message);return;}
  await loadPhase6(false);
  if(typeof window.load==='function') window.load();
  else location.reload();
}

async function openModule(module,subjectType,subjectId){
  const org=currentOrg();
  if(subjectId){ await sb.rpc('set_platform_context',{p_organization_id:org,p_location_id:null,p_entity_type:subjectType||null,p_entity_id:subjectId,p_entity_label:null,p_source_module_key:'command-center',p_context:{intent:'revenue_action',source:'phase6',module}}); }
  const urls={
    'ai-coach':'https://ai-iq-coach.netlify.app/',
    'academy':'https://iqacademy-appliance-training.netlify.app/',
    'crm':'https://applianceiq-crm.netlify.app/',
    'up-system':'https://applianceiq-up-system.netlify.app/',
    'product-iq':'https://applianceiq-product-iq-pim.netlify.app/'
  };
  window.open(urls[module]||'./','_blank','noopener');
}

async function boot(){
  installStyles(); installShell();
  const org=document.getElementById('org'); if(org) org.addEventListener('change',()=>setTimeout(()=>loadPhase6(true),50));
  for(let i=0;i<20;i++){ if(currentOrg()){await loadPhase6(true);return;} await new Promise(r=>setTimeout(r,250)); }
}

document.readyState==='loading'?document.addEventListener('DOMContentLoaded',boot):boot();
