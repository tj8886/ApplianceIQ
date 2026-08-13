function waitForAIQ(){return new Promise(resolve=>{if(window.ApplianceIQ)return resolve(window.ApplianceIQ);const done=()=>{if(window.ApplianceIQ){window.removeEventListener('aiq:intelligence-ready',done);resolve(window.ApplianceIQ)}};window.addEventListener('aiq:intelligence-ready',done)})}

async function requireOrg(aiq){const ctx=await aiq.getContext();if(!ctx?.organization_id)throw new Error('No active ApplianceIQ organization context');return ctx.organization_id}

waitForAIQ().then(aiq=>{
  const sb=aiq.supabase;
  aiq.adaptive={
    async refreshProfile({userId}){const org=await requireOrg(aiq);const {data,error}=await sb.rpc('phase5_refresh_profile',{p_organization_id:org,p_user_id:userId});if(error)throw error;return data||{}},
    async selectStrategy({userId,metricKey=null,skillId=null}){const org=await requireOrg(aiq);const {data,error}=await sb.rpc('phase5_select_strategy',{p_organization_id:org,p_user_id:userId,p_metric_key:metricKey,p_skill_id:skillId});if(error)throw error;return data||{}},
    async generate({userId,date=null}){const org=await requireOrg(aiq);const args={p_organization_id:org,p_user_id:userId};if(date)args.p_focus_date=date;const {data,error}=await sb.rpc('phase5_generate_adaptive_coaching',args);if(error)throw error;return data||{}},
    async generateOrganization({date=null,limit=25}={}){const org=await requireOrg(aiq);const args={p_organization_id:org,p_limit:limit};if(date)args.p_focus_date=date;const {data,error}=await sb.rpc('phase5_generate_org_adaptive_coaching',args);if(error)throw error;return data||[]},
    async repPlan({userId}){const org=await requireOrg(aiq);const {data,error}=await sb.rpc('phase5_rep_plan',{p_organization_id:org,p_user_id:userId});if(error)throw error;return data||{}},
    async managerDashboard(){const org=await requireOrg(aiq);const {data,error}=await sb.rpc('phase5_manager_dashboard',{p_organization_id:org});if(error)throw error;return data||{}},
    async managerRecommendations({limit=25}={}){const org=await requireOrg(aiq);const {data,error}=await sb.rpc('phase5_manager_recommendations',{p_organization_id:org,p_limit:limit});if(error)throw error;return data||[]}
  };
  window.dispatchEvent(new CustomEvent('aiq:adaptive-ready',{detail:{phase5:true}}));
});
