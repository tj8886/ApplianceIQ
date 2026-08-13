import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';

const SB_URL='https://fumwwhyozeouoqscolke.supabase.co';
const SB_KEY='sb_publishable_wiP3ouBdS_Qub9EMIYJK7w_eiltZHKV';
const sb=createClient(SB_URL,SB_KEY);
const script=document.currentScript || [...document.scripts].find(s=>s.src.includes('aiq-module-adapter.js'));
const moduleKey=script?.dataset?.aiqModule || document.documentElement.dataset.aiqModule || 'unknown';
let currentContext=null;

function decodeB64(v){try{return JSON.parse(decodeURIComponent(escape(atob(v))))}catch{try{return JSON.parse(atob(v))}catch{return null}}}
function parseHash(){const raw=location.hash.replace(/^#/,'');const p=new URLSearchParams(raw);return {ticket:p.get('aiq_ticket'),relay:p.get('aiq_relay'),context:p.get('aiq_context')}}
async function redeemTicket(ticket){
  const res=await fetch(`${SB_URL}/functions/v1/platform-handoff`,{method:'POST',headers:{'Content-Type':'application/json',apikey:SB_KEY},body:JSON.stringify({action:'redeem',ticket,target_module_key:moduleKey})});
  if(!res.ok)return null;
  const data=await res.json();
  if(!data?.token_hash)return null;
  const verified=await sb.auth.verifyOtp({token_hash:data.token_hash,type:'magiclink'});
  if(verified.error)return null;
  return {session:verified.data.session,context:data.context||null};
}
async function ensureSession(){
  const {data:{session}}=await sb.auth.getSession();
  const h=parseHash();
  if(h.ticket){const redeemed=await redeemTicket(h.ticket);if(redeemed?.session)return redeemed;}
  if(session)return {session,context:null};
  if(!h.relay)return {session:null,context:null};
  const r=decodeB64(h.relay);if(!r?.access_token||!r?.refresh_token)return {session:null,context:null};
  const {data,error}=await sb.auth.setSession({access_token:r.access_token,refresh_token:r.refresh_token});
  if(error){console.warn('[AIQ] legacy session relay failed',error.message);return {session:null,context:null}}
  return {session:data.session,context:null};
}
async function getContext(){const {data,error}=await sb.rpc('my_platform_context');if(error){console.warn('[AIQ] context read failed',error.message);return null}currentContext=data;return data}
async function setContext(patch){const args={p_organization_id:patch.organization_id??null,p_location_id:patch.location_id??null,p_entity_type:patch.entity_type??null,p_entity_id:patch.entity_id??null,p_entity_label:patch.entity_label??null,p_source_module_key:moduleKey,p_context:patch.context??{}};const {data,error}=await sb.rpc('set_platform_context',args);if(error)throw error;dispatch(data);return data}
function dispatch(ctx){currentContext=ctx;window.AIQ_CONTEXT=ctx;window.dispatchEvent(new CustomEvent('aiq:context',{detail:ctx}));document.dispatchEvent(new CustomEvent('aiq:context',{detail:ctx}));}
function cleanHash(){const p=new URLSearchParams(location.hash.replace(/^#/,''));p.delete('aiq_ticket');p.delete('aiq_relay');p.delete('aiq_context');const h=p.toString();history.replaceState(null,'',location.pathname+location.search+(h?'#'+h:''));}
function contextFromHash(){const {context}=parseHash();return context?decodeB64(decodeURIComponent(context)):null}
function entitySelectors(ctx){if(!ctx?.entity_id)return[];const id=CSS.escape(String(ctx.entity_id));const type=String(ctx.entity_type||'').toLowerCase();const attrs={contact:['data-contact-id','data-customer-id'],customer:['data-customer-id','data-contact-id'],product:['data-product-id','data-model-id'],transaction:['data-transaction-id','data-order-id'],order:['data-order-id','data-transaction-id'],employee:['data-employee-id','data-user-id','data-rep-id'],store:['data-store-id','data-location-id'],location:['data-location-id','data-store-id']};return (attrs[type]||['data-entity-id']).map(a=>`[${a}="${id}"]`).concat([`a[href*="${id}"]`,`button[value="${id}"]`])}
function tryFocus(ctx){if(!ctx?.entity_id)return false;for(const s of entitySelectors(ctx)){try{const el=document.querySelector(s);if(el){el.scrollIntoView({block:'center'});el.click?.();el.setAttribute('data-aiq-focused','true');return true}}catch{}}return false}
function installFocusObserver(ctx){if(tryFocus(ctx))return;let tries=0;const mo=new MutationObserver(()=>{tries++;if(tryFocus(ctx)||tries>40)mo.disconnect()});mo.observe(document.documentElement,{childList:true,subtree:true});setTimeout(()=>mo.disconnect(),12000)}
function installEntityCapture(){document.addEventListener('click',e=>{const el=e.target.closest?.('[data-contact-id],[data-customer-id],[data-product-id],[data-model-id],[data-transaction-id],[data-order-id],[data-employee-id],[data-rep-id],[data-store-id],[data-location-id]');if(!el)return;const map=[['contact','contactId'],['customer','customerId'],['product','productId'],['product','modelId'],['transaction','transactionId'],['order','orderId'],['employee','employeeId'],['employee','repId'],['store','storeId'],['location','locationId']];for(const [type,key] of map){const v=el.dataset[key];if(v){setContext({entity_type:type,entity_id:v,entity_label:(el.dataset.aiqLabel||el.textContent||'').trim().slice(0,160),context:{captured_by:'dom'}}).catch(()=>{});break}}},true)}

async function requireOrg(){const ctx=currentContext||await getContext();if(!ctx?.organization_id)throw new Error('No active ApplianceIQ organization context');return ctx.organization_id}
const intelligence={
  async feed({since=null,limit=200,eventTypes=null}={}){const org=await requireOrg();const {data,error}=await sb.rpc('platform_intelligence_feed',{p_organization_id:org,p_since:since,p_limit:limit,p_event_types:eventTypes});if(error)throw error;return data||[]},
  async summary({since=null}={}){const org=await requireOrg();const {data,error}=await sb.rpc('platform_intelligence_summary',{p_organization_id:org,p_since:since});if(error)throw error;return data||{}},
  async stores({since=null}={}){const org=await requireOrg();const {data,error}=await sb.rpc('platform_intelligence_store_rollup',{p_organization_id:org,p_since:since});if(error)throw error;return data||[]},
  async employees({since=null}={}){const org=await requireOrg();const {data,error}=await sb.rpc('platform_intelligence_employee_rollup',{p_organization_id:org,p_since:since});if(error)throw error;return data||[]},
  async resolveIdentity({entityType,sourceSystem=null,externalId=null,sourceRecordId=null}){const org=await requireOrg();const {data,error}=await sb.rpc('platform_resolve_identity',{p_organization_id:org,p_entity_type:entityType,p_source_system:sourceSystem,p_external_id:externalId,p_source_record_id:sourceRecordId});if(error)throw error;return data||[]}
};

window.ApplianceIQ={supabase:sb,moduleKey,getContext,setContext,focus:(type,id,label,context={})=>setContext({entity_type:type,entity_id:id,entity_label:label,context}),clearFocus:()=>setContext({entity_type:null,entity_id:null,entity_label:null,context:{}}),intelligence};

(async()=>{
  const auth=await ensureSession();
  if(!auth.session){window.dispatchEvent(new CustomEvent('aiq:auth-missing'));return}
  const incoming=auth.context||contextFromHash();
  let ctx;
  if(incoming?.organization_id){ctx=await setContext({organization_id:incoming.organization_id,location_id:incoming.location_id||null,entity_type:incoming.entity_type||null,entity_id:incoming.entity_id||null,entity_label:incoming.entity_label||null,context:{handoff:true,source:incoming.source_module_key||'platform'}}).catch(()=>null)}
  if(!ctx)ctx=await getContext();
  if(ctx){dispatch(ctx);installFocusObserver(ctx)}
  installEntityCapture();cleanHash();
  window.dispatchEvent(new CustomEvent('aiq:intelligence-ready',{detail:{moduleKey,organization_id:ctx?.organization_id||null}}));
})();
