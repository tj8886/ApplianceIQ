-- Fixed paths use schemas that anon/authenticated cannot CREATE in; preserve all current function grants and bodies.
ALTER FUNCTION public.category_price_ceiling(text) SET search_path TO pg_catalog, public, extensions, pg_temp;
ALTER FUNCTION public.count_model_tokens(text) SET search_path TO pg_catalog, public, extensions, pg_temp;
ALTER FUNCTION public.model_discovery_chain_cap() SET search_path TO pg_catalog, public, extensions, pg_temp;
ALTER FUNCTION public.model_discovery_lease_interval() SET search_path TO pg_catalog, public, extensions, pg_temp;
ALTER FUNCTION public.observation_title_matches_model(text,text) SET search_path TO pg_catalog, public, extensions, pg_temp;
ALTER FUNCTION public.observation_title_static_filters_ok(text,text) SET search_path TO pg_catalog, public, extensions, pg_temp;
ALTER FUNCTION public.pim_audit_ledger_append_only() SET search_path TO pg_catalog, public, extensions, pg_temp;
ALTER FUNCTION public.pimlane_num(text) SET search_path TO pg_catalog, public, extensions, pg_temp;
ALTER FUNCTION public.pimlane_truthy(text) SET search_path TO pg_catalog, public, extensions, pg_temp;
ALTER FUNCTION public.price_check_shard_histogram(integer) SET search_path TO pg_catalog, public, extensions, pg_temp;
ALTER FUNCTION public.price_check_tail_shard(uuid,integer) SET search_path TO pg_catalog, public, extensions, pg_temp;
ALTER FUNCTION public.price_check_today_shard(integer) SET search_path TO pg_catalog, public, extensions, pg_temp;
ALTER FUNCTION public.spec_convert_unit(numeric,text,text) SET search_path TO pg_catalog, public, extensions, pg_temp;
ALTER FUNCTION public.spec_key_encoded_unit(text) SET search_path TO pg_catalog, public, extensions, pg_temp;
ALTER FUNCTION public.spec_name_agrees(text,text,text) SET search_path TO pg_catalog, public, extensions, pg_temp;
ALTER FUNCTION public.spec_name_is_accessory(text) SET search_path TO pg_catalog, public, extensions, pg_temp;
ALTER FUNCTION public.spec_name_is_quarantine_marker(text) SET search_path TO pg_catalog, public, extensions, pg_temp;
ALTER FUNCTION public.spec_normalize_text(text) SET search_path TO pg_catalog, public, extensions, pg_temp;
ALTER FUNCTION public.spec_read_number(text) SET search_path TO pg_catalog, public, extensions, pg_temp;
ALTER FUNCTION public.spec_read_unit(text) SET search_path TO pg_catalog, public, extensions, pg_temp;
ALTER FUNCTION public.spec_unit_dimension(text) SET search_path TO pg_catalog, public, extensions, pg_temp;
ALTER FUNCTION public.spec_unit_remainder(text) SET search_path TO pg_catalog, public, extensions, pg_temp;
ALTER FUNCTION public.tj_map_category(text) SET search_path TO pg_catalog, public, extensions, pg_temp;
ALTER FUNCTION public.tj_skip_reason(text,text,text) SET search_path TO pg_catalog, public, extensions, pg_temp;
ALTER FUNCTION public.enforce_observation_integrity() SET search_path TO pg_catalog, public, extensions, pg_temp;
ALTER FUNCTION public.get_priority_refresh_median_staleness_hours() SET search_path TO pg_catalog, public, extensions, pg_temp;
ALTER FUNCTION public.media_rights_withdrawal_proof(uuid) SET search_path TO pg_catalog, public, extensions, pg_temp;
-- These four public projections passed role-visibility parity under invoker semantics.
ALTER VIEW public.eligible_public_observations SET (security_invoker=true);
ALTER VIEW public.homepage_luxury SET (security_invoker=true);
ALTER VIEW public.homepage_popular SET (security_invoker=true);
ALTER VIEW public.homepage_spreads SET (security_invoker=true);
-- Trigger-only integrity code is not a browser RPC. PostgreSQL trigger execution remains available.
REVOKE EXECUTE ON FUNCTION public.pim_coverage_verified_needs_artifact() FROM PUBLIC, anon, authenticated;
