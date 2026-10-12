// Shared presentation and access rules. Database RLS remains authoritative.
export function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
}
const APP_KEYS = {'crm':'crm','academy':'iq_academy','field':'iq_field','iq-field':'iq_field',
 'spec-iq':'spec_iq','spec_iq':'spec_iq','up-system':'iq_up_system','up_system':'iq_up_system',
 'command-center':'command_center','command_center':'command_center','product-iq':'product_iq',
 'product_iq':'product_iq','pim-scraper':'pim_scraper','scraper':'pim_scraper',
 'ai-coach':'ai_coach','ai_coach':'ai_coach','mdf-coop':'mdf-coop','iq-build':'iq-build',
 'brand_marketing':'field-report-analytics','platform':'platform'};
export function moduleAllowed(module, entitlements, context = {}) {
  if (!context.organization_id || !Array.isArray(entitlements)) return false;
  const admin = ['owner','admin'].includes(context.organization_role);
  if (module.key === 'intelligence_group') return admin;
  if (module.visibility === 'internal') return admin && !!APP_KEYS[module.key] && entitlements.includes(APP_KEYS[module.key]);
  if (module.manifest?.registry_key === 'applianceiq-platform' || module.key === 'platform') return true;
  const appKey = APP_KEYS[module.key];
  return !!appKey && entitlements.includes(appKey);
}
export function creditsRemaining(credits) {
  if (!credits) return null;
  return Math.max(0, Number(credits.credits_included || 0) + Number(credits.credits_bonus || 0) - Number(credits.credits_used_this_period || 0));
}
export function safeAppUrl(value, origin) {
  if (typeof value !== 'string' || !value.trim()) throw Error('This app has no launch URL.');
  const url = new URL(value, origin);
  if (url.username || url.password || (url.origin !== origin && url.protocol !== 'https:') || !['https:','http:'].includes(url.protocol)) throw Error('This app has an invalid launch URL.');
  return url;
}
export function handoffUrl(value, ticket, origin) {
  if (!/^[a-f0-9]{64}$/.test(ticket || '')) throw Error('Unable to create secure app handoff.');
  const url = safeAppUrl(value, origin);
  url.hash = 'aiq_ticket=' + encodeURIComponent(ticket);
  return url.href;
}
