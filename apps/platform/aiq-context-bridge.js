import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';

const SB_URL = 'https://fumwwhyozeouoqscolke.supabase.co';
const SB_KEY = 'sb_publishable_wiP3ouBdS_Qub9EMIYJK7w_eiltZHKV';

export function createAIQContextBridge(options = {}) {
  const sb = options.supabase || createClient(SB_URL, SB_KEY);
  const moduleKey = options.moduleKey || document.documentElement.dataset.aiqModule || 'unknown';
  let current = null;
  const listeners = new Set();

  async function getContext() {
    const { data, error } = await sb.rpc('my_platform_context');
    if (error) throw error;
    current = data || {};
    return current;
  }

  async function setContext(patch = {}) {
    const base = current || await getContext();
    const args = {
      p_organization_id: patch.organization_id ?? base.organization_id ?? null,
      p_location_id: Object.prototype.hasOwnProperty.call(patch, 'location_id') ? patch.location_id : (base.location_id ?? null),
      p_entity_type: Object.prototype.hasOwnProperty.call(patch, 'entity_type') ? patch.entity_type : (base.entity_type ?? null),
      p_entity_id: Object.prototype.hasOwnProperty.call(patch, 'entity_id') ? patch.entity_id : (base.entity_id ?? null),
      p_entity_label: Object.prototype.hasOwnProperty.call(patch, 'entity_label') ? patch.entity_label : (base.entity_label ?? null),
      p_source_module_key: patch.source_module_key || moduleKey,
      p_context: patch.context ?? base.context ?? {}
    };
    const { data, error } = await sb.rpc('set_platform_context', args);
    if (error) throw error;
    current = data || {};
    dispatch();
    return current;
  }

  async function focus(entityType, entityId, entityLabel = null, context = {}) {
    return setContext({ entity_type: entityType, entity_id: String(entityId), entity_label: entityLabel, context, source_module_key: moduleKey });
  }

  async function clearEntity() {
    return setContext({ entity_type: null, entity_id: null, entity_label: null, context: {}, source_module_key: moduleKey });
  }

  async function organizations() {
    const { data, error } = await sb.rpc('my_platform_organizations');
    if (error) throw error;
    return data || [];
  }

  async function locations(organizationId = null) {
    const orgId = organizationId || current?.organization_id;
    if (!orgId) return [];
    const { data, error } = await sb.rpc('my_platform_locations', { p_organization_id: orgId });
    if (error) throw error;
    return data || [];
  }

  function dispatch() {
    const detail = current || {};
    window.dispatchEvent(new CustomEvent('aiq:context-changed', { detail }));
    listeners.forEach(fn => { try { fn(detail); } catch (_) {} });
  }

  function onChange(fn) { listeners.add(fn); return () => listeners.delete(fn); }
  function value() { return current; }

  async function init() {
    current = await getContext();
    dispatch();
    return current;
  }

  return { sb, init, getContext, setContext, focus, clearEntity, organizations, locations, onChange, value };
}

window.createAIQContextBridge = createAIQContextBridge;
