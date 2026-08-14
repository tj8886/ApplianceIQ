async function renderAI(){
  const m=$('#ccMain');
  const lv=viewLevel;
  const scopeLabel=lv.level==='corporate'?'All Stores':esc(lv.name);
  m.innerHTML=`<h2 class="cc-page-title">🤖 AI Insights</h2>
    <p class="cc-page-sub">Governed intelligence, decisions, forecasts and manager actions · ${scopeLabel}</p>
    <div class="cc-panel" style="margin-bottom:16px">
      <div style="display:flex;justify-content:space-between;gap:12px;align-items:center;flex-wrap:wrap">
        <div><h3 style="margin:0 0 5px">Intelligence Cycle</h3><p style="color:var(--steel);font-size:13px;margin:0">Uses the shared Intelligence → Decision → AI Manager pipeline. Operational insights are no longer written to the legacy budget-prediction cache.</p></div>
        <button id="ccRunGovernedAI" style="background:var(--accent);color:#fff;border:none;padding:9px 18px;border-radius:8px;cursor:pointer;font-weight:700">⚡ Refresh governed intelligence</button>
      </div>
    </div>
    <div id="ccGovernedAIResults"><div class="cc-panel"><p style="color:var(--steel);text-align:center;padding:20px">Loading governed intelligence…</p></div></div>`;

  async function loadGoverned(refresh=false){
    const out=document.getElementById('ccGovernedAIResults');
    if(refresh){
      const btn=document.getElementById('ccRunGovernedAI');
      btn.disabled=true;btn.textContent='🔄 Refreshing…';btn.style.opacity='.65';
      const sync=await sb.rpc('decision_sync_executive_insights',{p_organization_id:currentOrg.id});
      if(sync.error){btn.disabled=false;btn.textContent='⚡ Refresh governed intelligence';throw sync.error;}
      const rev=await sb.rpc('phase6_refresh_revenue_opportunities',{p_organization_id:currentOrg.id});
      if(rev.error)console.warn('Revenue refresh',rev.error);
      btn.disabled=false;btn.textContent='⚡ Refresh governed intelligence';btn.style.opacity='1';
    }

    const [feedR,revR,autoR,predR,coachR]=await Promise.all([
      sb.rpc('decision_get_feed',{p_organization_id:currentOrg.id,p_limit:50}),
      sb.rpc('phase6_command_center',{p_organization_id:currentOrg.id,p_limit:20}),
      sb.rpc('phase7_command_center',{p_organization_id:currentOrg.id,p_limit:20}),
      sb.rpc('decision_get_prediction_dashboard',{p_organization_id:currentOrg.id}),
      sb.rpc('phase5_manager_recommendations',{p_organization_id:currentOrg.id,p_limit:10})
    ]);
    const firstErr=[feedR,revR,autoR,predR,coachR].find(r=>r.error)?.error;
    if(firstErr)throw firstErr;

    let decisions=feedR.data||[];
    if(lv.level==='store')decisions=decisions.filter(x=>!x.entity_id||x.entity_id===lv.id||x.metadata?.location_id===lv.id||x.metadata?.store_id===lv.id);
    if(lv.level==='rep')decisions=decisions.filter(x=>!x.entity_id||x.entity_id===lv.id||x.metadata?.user_id===lv.id||x.metadata?.employee_id===lv.id);
    const revenue=revR.data||{};
    const automation=autoR.data||{};
    const predictions=predR.data||{};
    const coaching=coachR.data||[];

    const critical=decisions.filter(x=>x.severity==='critical').length;
    const high=decisions.filter(x=>x.severity==='high').length;
    const quantified=(revenue.actions||[]).filter(x=>x.estimated_revenue_impact!=null||x.estimated_margin_impact!=null);
    const quantifiedImpact=quantified.reduce((sum,x)=>sum+Number(x.estimated_margin_impact??x.estimated_revenue_impact??0),0);
    const pending=automation.summary?.pending_approval||0;
    const activeForecasts=predictions.summary?.active_predictions||0;

    const stat=(label,value,note)=>`<div class="cc-stat"><div class="cc-stat-label">${esc(label)}</div><div class="cc-stat-value">${esc(value)}</div><div class="cc-stat-note">${esc(note)}</div></div>`;
    const money0=v=>new Intl.NumberFormat('en-CA',{style:'currency',currency:'CAD',maximumFractionDigits:0}).format(Number(v||0));
    out.innerHTML=`<div class="cc-stat-grid">
      ${stat('Open decisions',String(decisions.length),`${critical} critical · ${high} high`)}
      ${stat('Quantified opportunity',money0(quantifiedImpact),`${quantified.length} evidence-backed cases`)}
      ${stat('Pending approvals',String(pending),'Phase 7 policy queue')}
      ${stat('Active forecasts',String(activeForecasts),'Measured through Decision Intelligence')}
    </div>
    <div class="cc-panel" style="margin-bottom:16px"><div style="display:flex;justify-content:space-between;align-items:center;gap:12px"><h3 style="margin:0">Highest-priority decisions</h3><a href="./decisions.html" style="font-size:12px;color:var(--accent);font-weight:700">Open Decision Intelligence →</a></div>
      ${decisions.slice(0,10).map(c=>`<div style="padding:13px 0;border-top:1px solid var(--line)"><div style="display:flex;justify-content:space-between;gap:12px"><div><b>${esc(c.title||'Decision')}</b><div style="font-size:12px;color:var(--steel);margin-top:3px">${esc(c.summary||'')}</div><div style="font-size:12px;margin-top:6px">💡 ${esc(c.recommendation||'Review evidence and decide next action.')}</div></div><div style="text-align:right;min-width:85px"><span class="cc-badge ${c.severity==='critical'||c.severity==='high'?'dn':'flat'}">${esc(c.severity||'info')}</span><div style="font-size:18px;font-weight:800;margin-top:5px">${Math.round(Number(c.priority_score||0))}</div><div style="font-size:10px;color:var(--steel)">priority</div></div></div></div>`).join('')||'<p style="color:var(--steel)">No open governed decisions.</p>'}
    </div>
    <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:14px">
      <div class="cc-panel"><h3>Revenue Intelligence</h3><div style="font-size:28px;font-weight:800">${money0(revenue.summary?.estimated_margin_impact||revenue.summary?.estimated_revenue_impact||0)}</div><div style="font-size:12px;color:var(--steel)">${revenue.summary?.open_actions||0} open actions · ${revenue.summary?.financially_quantified||0} quantified</div><a href="./manager.html" style="display:inline-block;margin-top:12px;color:var(--accent);font-weight:700;font-size:12px">Open AI Manager →</a></div>
      <div class="cc-panel"><h3>Coaching Intelligence</h3><div style="font-size:28px;font-weight:800">${coaching.length}</div><div style="font-size:12px;color:var(--steel)">adaptive coaching priorities surfaced from Phase 5</div><a href="./manager.html" style="display:inline-block;margin-top:12px;color:var(--accent);font-weight:700;font-size:12px">Open coaching priorities →</a></div>
      <div class="cc-panel"><h3>Automation & Approvals</h3><div style="font-size:28px;font-weight:800">${pending}</div><div style="font-size:12px;color:var(--steel)">actions waiting for retailer-approved execution</div><a href="./manager.html" style="display:inline-block;margin-top:12px;color:var(--accent);font-weight:700;font-size:12px">Review approvals →</a></div>
      <div class="cc-panel"><h3>Predictive Intelligence</h3><div style="font-size:28px;font-weight:800">${activeForecasts}</div><div style="font-size:12px;color:var(--steel)">active governed forecasts · ${money0(predictions.summary?.total_cost_of_inaction_cad||0)} cost of inaction</div><a href="./predictions.html" style="display:inline-block;margin-top:12px;color:var(--accent);font-weight:700;font-size:12px">Open forecasts →</a></div>
    </div>`;
  }

  document.getElementById('ccRunGovernedAI').onclick=async()=>{try{await loadGoverned(true)}catch(e){document.getElementById('ccGovernedAIResults').innerHTML=`<div class="cc-panel"><p style="color:var(--danger)">Governed intelligence refresh failed: ${esc(e.message)}</p></div>`}};
  try{await loadGoverned(false)}catch(e){document.getElementById('ccGovernedAIResults').innerHTML=`<div class="cc-panel"><p style="color:var(--danger)">Unable to load governed intelligence: ${esc(e.message)}</p></div>`}
}