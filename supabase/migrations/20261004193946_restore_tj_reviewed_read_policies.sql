-- Reviewed SELECT permissions only. No self-join, anonymous read or write rules restored.
-- MDF requires separate row-organization review; the two retained-extra tables stay private.
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."activities"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: activities'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."activities"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: activities'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."activities" FOR SELECT TO authenticated USING((tj.is_org_member(organization_id)));
GRANT SELECT ON tj."activities" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."ai_audit_events"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: ai_audit_events'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."ai_audit_events"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: ai_audit_events'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."ai_audit_events" FOR SELECT TO authenticated USING((tj.is_org_admin(organization_id)));
GRANT SELECT ON tj."ai_audit_events" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."ai_budget_predictions"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: ai_budget_predictions'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."ai_budget_predictions"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: ai_budget_predictions'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."ai_budget_predictions" FOR SELECT TO authenticated USING((tj.is_org_member(organization_id)));
GRANT SELECT ON tj."ai_budget_predictions" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."ai_coaching_reviews"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: ai_coaching_reviews'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."ai_coaching_reviews"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: ai_coaching_reviews'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."ai_coaching_reviews" FOR SELECT TO authenticated USING((tj.is_org_member(organization_id)));
GRANT SELECT ON tj."ai_coaching_reviews" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."ai_personas"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: ai_personas'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."ai_personas"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: ai_personas'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."ai_personas" FOR SELECT TO authenticated USING((tj.is_org_member(organization_id)));
GRANT SELECT ON tj."ai_personas" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."ai_proposed_actions"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: ai_proposed_actions'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."ai_proposed_actions"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: ai_proposed_actions'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."ai_proposed_actions" FOR SELECT TO authenticated USING((tj.is_org_member(organization_id)));
GRANT SELECT ON tj."ai_proposed_actions" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."ai_token_limits"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: ai_token_limits'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."ai_token_limits"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: ai_token_limits'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."ai_token_limits" FOR SELECT TO authenticated USING((tj.is_org_member(organization_id)));
GRANT SELECT ON tj."ai_token_limits" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."ai_usage_meter"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: ai_usage_meter'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."ai_usage_meter"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: ai_usage_meter'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."ai_usage_meter" FOR SELECT TO authenticated USING((tj.is_org_admin(organization_id)));
GRANT SELECT ON tj."ai_usage_meter" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."attribution_exceptions"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: attribution_exceptions'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."attribution_exceptions"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: attribution_exceptions'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."attribution_exceptions" FOR SELECT TO authenticated USING((tj.is_org_member(organization_id)));
GRANT SELECT ON tj."attribution_exceptions" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."brand_catalog"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: brand_catalog'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."brand_catalog"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: brand_catalog'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."brand_catalog" FOR SELECT TO authenticated USING((tj.is_org_member(organization_id)));
GRANT SELECT ON tj."brand_catalog" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."budget_nodes"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: budget_nodes'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."budget_nodes"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: budget_nodes'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."budget_nodes" FOR SELECT TO authenticated USING((tj.is_org_member(organization_id)));
GRANT SELECT ON tj."budget_nodes" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."budget_plans"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: budget_plans'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."budget_plans"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: budget_plans'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."budget_plans" FOR SELECT TO authenticated USING((tj.is_org_member(organization_id)));
GRANT SELECT ON tj."budget_plans" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."companies"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: companies'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."companies"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: companies'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."companies" FOR SELECT TO authenticated USING((tj.is_org_member(organization_id)));
GRANT SELECT ON tj."companies" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."contacts"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: contacts'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."contacts"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: contacts'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."contacts" FOR SELECT TO authenticated USING((tj.is_org_member(organization_id)));
GRANT SELECT ON tj."contacts" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."dashboard_metric_settings"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: dashboard_metric_settings'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."dashboard_metric_settings"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: dashboard_metric_settings'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."dashboard_metric_settings" FOR SELECT TO authenticated USING((tj.is_org_member(organization_id)));
GRANT SELECT ON tj."dashboard_metric_settings" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."field_actions"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: field_actions'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."field_actions"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: field_actions'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."field_actions" FOR SELECT TO authenticated USING((tj.is_field_client_member(client_id)));
GRANT SELECT ON tj."field_actions" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."field_assets"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: field_assets'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."field_assets"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: field_assets'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."field_assets" FOR SELECT TO authenticated USING((tj.is_field_client_member(client_id)));
GRANT SELECT ON tj."field_assets" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."field_findings"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: field_findings'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."field_findings"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: field_findings'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."field_findings" FOR SELECT TO authenticated USING((tj.is_field_client_member(client_id)));
GRANT SELECT ON tj."field_findings" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."field_floor_audit"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: field_floor_audit'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."field_floor_audit"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: field_floor_audit'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."field_floor_audit" FOR SELECT TO authenticated USING((tj.is_org_member(organization_id)));
GRANT SELECT ON tj."field_floor_audit" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."field_floor_config"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: field_floor_config'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."field_floor_config"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: field_floor_config'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."field_floor_config" FOR SELECT TO authenticated USING((tj.is_org_member(organization_id)));
GRANT SELECT ON tj."field_floor_config" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."field_floor_display_skus"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: field_floor_display_skus'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."field_floor_display_skus"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: field_floor_display_skus'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."field_floor_display_skus" FOR SELECT TO authenticated USING((tj.is_org_member(organization_id)));
GRANT SELECT ON tj."field_floor_display_skus" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."field_floor_displays"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: field_floor_displays'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."field_floor_displays"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: field_floor_displays'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."field_floor_displays" FOR SELECT TO authenticated USING((tj.is_org_member(organization_id)));
GRANT SELECT ON tj."field_floor_displays" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."field_floor_hole_sla"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: field_floor_hole_sla'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."field_floor_hole_sla"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: field_floor_hole_sla'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."field_floor_hole_sla" FOR SELECT TO authenticated USING((tj.is_org_member(organization_id)));
GRANT SELECT ON tj."field_floor_hole_sla" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."field_floor_holes"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: field_floor_holes'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."field_floor_holes"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: field_floor_holes'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."field_floor_holes" FOR SELECT TO authenticated USING((tj.is_org_member(organization_id)));
GRANT SELECT ON tj."field_floor_holes" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."field_floor_snapshots"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: field_floor_snapshots'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."field_floor_snapshots"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: field_floor_snapshots'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."field_floor_snapshots" FOR SELECT TO authenticated USING((tj.is_org_member(organization_id)));
GRANT SELECT ON tj."field_floor_snapshots" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."field_manufacturer_users"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: field_manufacturer_users'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."field_manufacturer_users"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: field_manufacturer_users'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."field_manufacturer_users" FOR SELECT TO authenticated USING((tj.is_field_client_member(client_id)));
GRANT SELECT ON tj."field_manufacturer_users" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."field_programs"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: field_programs'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."field_programs"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: field_programs'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."field_programs" FOR SELECT TO authenticated USING((tj.is_field_client_member(client_id)));
GRANT SELECT ON tj."field_programs" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."field_replacement_requests"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: field_replacement_requests'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."field_replacement_requests"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: field_replacement_requests'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."field_replacement_requests" FOR SELECT TO authenticated USING((tj.is_field_client_member(client_id)));
GRANT SELECT ON tj."field_replacement_requests" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."field_service_requests"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: field_service_requests'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."field_service_requests"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: field_service_requests'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."field_service_requests" FOR SELECT TO authenticated USING((tj.is_field_client_member(client_id)));
GRANT SELECT ON tj."field_service_requests" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."field_store_scores"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: field_store_scores'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."field_store_scores"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: field_store_scores'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."field_store_scores" FOR SELECT TO authenticated USING((tj.is_field_client_member(client_id)));
GRANT SELECT ON tj."field_store_scores" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."field_training_sessions"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: field_training_sessions'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."field_training_sessions"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: field_training_sessions'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."field_training_sessions" FOR SELECT TO authenticated USING((tj.is_field_client_member(client_id)));
GRANT SELECT ON tj."field_training_sessions" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."intelligence_events_archive"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: intelligence_events_archive'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."intelligence_events_archive"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: intelligence_events_archive'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."intelligence_events_archive" FOR SELECT TO authenticated USING(((SELECT tj.is_platform_admin())));
GRANT SELECT ON tj."intelligence_events_archive" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."iq_audit_events"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: iq_audit_events'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."iq_audit_events"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: iq_audit_events'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."iq_audit_events" FOR SELECT TO authenticated USING((organization_id IN (SELECT tj.my_org_ids())));
GRANT SELECT ON tj."iq_audit_events" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."iq_card_completions"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: iq_card_completions'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."iq_card_completions"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: iq_card_completions'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."iq_card_completions" FOR SELECT TO authenticated USING(((SELECT tj.is_admin())));
GRANT SELECT ON tj."iq_card_completions" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."iq_customer_interactions"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: iq_customer_interactions'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."iq_customer_interactions"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: iq_customer_interactions'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."iq_customer_interactions" FOR SELECT TO authenticated USING((organization_id IN (SELECT tj.my_org_ids()) AND tj.aiq_store_allows(organization_id,store_id)) OR (organization_id IN (SELECT tj.my_org_ids())));
CREATE POLICY consolidation_store_scope ON tj."iq_customer_interactions" AS RESTRICTIVE FOR SELECT TO authenticated USING(tj.aiq_store_allows(organization_id,store_id));
GRANT SELECT ON tj."iq_customer_interactions" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."iq_customer_product_interest"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: iq_customer_product_interest'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."iq_customer_product_interest"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: iq_customer_product_interest'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."iq_customer_product_interest" FOR SELECT TO authenticated USING((organization_id IN (SELECT tj.my_org_ids())));
GRANT SELECT ON tj."iq_customer_product_interest" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."iq_customer_waiting_queue"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: iq_customer_waiting_queue'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."iq_customer_waiting_queue"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: iq_customer_waiting_queue'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."iq_customer_waiting_queue" FOR SELECT TO authenticated USING((organization_id IN (SELECT tj.my_org_ids()) AND tj.aiq_store_allows(organization_id,store_id)) OR (organization_id IN (SELECT tj.my_org_ids())));
CREATE POLICY consolidation_store_scope ON tj."iq_customer_waiting_queue" AS RESTRICTIVE FOR SELECT TO authenticated USING(tj.aiq_store_allows(organization_id,store_id));
GRANT SELECT ON tj."iq_customer_waiting_queue" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."iq_deck_completions"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: iq_deck_completions'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."iq_deck_completions"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: iq_deck_completions'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."iq_deck_completions" FOR SELECT TO authenticated USING(((SELECT tj.is_admin())));
GRANT SELECT ON tj."iq_deck_completions" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."iq_floor_managers"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: iq_floor_managers'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."iq_floor_managers"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: iq_floor_managers'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."iq_floor_managers" FOR SELECT TO authenticated USING((organization_id IN (SELECT tj.my_org_ids())));
GRANT SELECT ON tj."iq_floor_managers" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."iq_gate_attempts"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: iq_gate_attempts'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."iq_gate_attempts"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: iq_gate_attempts'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."iq_gate_attempts" FOR SELECT TO authenticated USING(((SELECT tj.is_admin())));
GRANT SELECT ON tj."iq_gate_attempts" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."iq_hourly_traffic_summaries"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: iq_hourly_traffic_summaries'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."iq_hourly_traffic_summaries"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: iq_hourly_traffic_summaries'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."iq_hourly_traffic_summaries" FOR SELECT TO authenticated USING((organization_id IN (SELECT tj.my_org_ids())) OR (organization_id IN (SELECT tj.my_org_ids()) AND tj.aiq_store_allows(organization_id,store_id)));
CREATE POLICY consolidation_store_scope ON tj."iq_hourly_traffic_summaries" AS RESTRICTIVE FOR SELECT TO authenticated USING(tj.aiq_store_allows(organization_id,store_id));
GRANT SELECT ON tj."iq_hourly_traffic_summaries" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."iq_integration_links"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: iq_integration_links'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."iq_integration_links"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: iq_integration_links'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."iq_integration_links" FOR SELECT TO authenticated USING((organization_id IN (SELECT tj.my_org_ids())));
GRANT SELECT ON tj."iq_integration_links" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."iq_intelligence_events"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: iq_intelligence_events'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."iq_intelligence_events"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: iq_intelligence_events'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."iq_intelligence_events" FOR SELECT TO authenticated USING((organization_id IN (SELECT tj.my_org_ids())));
GRANT SELECT ON tj."iq_intelligence_events" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."iq_missed_and_potential_missed_ups"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: iq_missed_and_potential_missed_ups'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."iq_missed_and_potential_missed_ups"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: iq_missed_and_potential_missed_ups'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."iq_missed_and_potential_missed_ups" FOR SELECT TO authenticated USING((organization_id IN (SELECT tj.my_org_ids()) AND tj.aiq_store_allows(organization_id,store_id)) OR (organization_id IN (SELECT tj.my_org_ids())));
CREATE POLICY consolidation_store_scope ON tj."iq_missed_and_potential_missed_ups" AS RESTRICTIVE FOR SELECT TO authenticated USING(tj.aiq_store_allows(organization_id,store_id));
GRANT SELECT ON tj."iq_missed_and_potential_missed_ups" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."iq_open_rotation_sessions"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: iq_open_rotation_sessions'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."iq_open_rotation_sessions"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: iq_open_rotation_sessions'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."iq_open_rotation_sessions" FOR SELECT TO authenticated USING((organization_id IN (SELECT tj.my_org_ids()) AND tj.aiq_store_allows(organization_id,store_id)) OR (organization_id IN (SELECT tj.my_org_ids())));
CREATE POLICY consolidation_store_scope ON tj."iq_open_rotation_sessions" AS RESTRICTIVE FOR SELECT TO authenticated USING(tj.aiq_store_allows(organization_id,store_id));
GRANT SELECT ON tj."iq_open_rotation_sessions" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."iq_queue_notifications"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: iq_queue_notifications'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."iq_queue_notifications"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: iq_queue_notifications'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."iq_queue_notifications" FOR SELECT TO authenticated USING((organization_id IN (SELECT tj.my_org_ids())));
GRANT SELECT ON tj."iq_queue_notifications" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."iq_queue_snapshots"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: iq_queue_snapshots'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."iq_queue_snapshots"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: iq_queue_snapshots'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."iq_queue_snapshots" FOR SELECT TO authenticated USING((organization_id IN (SELECT tj.my_org_ids()) AND tj.aiq_store_allows(organization_id,store_id)) OR (organization_id IN (SELECT tj.my_org_ids())));
CREATE POLICY consolidation_store_scope ON tj."iq_queue_snapshots" AS RESTRICTIVE FOR SELECT TO authenticated USING(tj.aiq_store_allows(organization_id,store_id));
GRANT SELECT ON tj."iq_queue_snapshots" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."iq_shift_records"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: iq_shift_records'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."iq_shift_records"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: iq_shift_records'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."iq_shift_records" FOR SELECT TO authenticated USING((organization_id IN (SELECT tj.my_org_ids()) AND tj.aiq_store_allows(organization_id,store_id)) OR (organization_id IN (SELECT tj.my_org_ids())));
CREATE POLICY consolidation_store_scope ON tj."iq_shift_records" AS RESTRICTIVE FOR SELECT TO authenticated USING(tj.aiq_store_allows(organization_id,store_id));
GRANT SELECT ON tj."iq_shift_records" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."iq_status_sessions"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: iq_status_sessions'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."iq_status_sessions"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: iq_status_sessions'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."iq_status_sessions" FOR SELECT TO authenticated USING((organization_id IN (SELECT tj.my_org_ids())) OR (organization_id IN (SELECT tj.my_org_ids()) AND tj.aiq_store_allows(organization_id,store_id)));
CREATE POLICY consolidation_store_scope ON tj."iq_status_sessions" AS RESTRICTIVE FOR SELECT TO authenticated USING(tj.aiq_store_allows(organization_id,store_id));
GRANT SELECT ON tj."iq_status_sessions" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."iq_store_settings"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: iq_store_settings'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."iq_store_settings"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: iq_store_settings'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."iq_store_settings" FOR SELECT TO authenticated USING((organization_id IN (SELECT tj.my_org_ids())));
GRANT SELECT ON tj."iq_store_settings" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."iq_traffic_events"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: iq_traffic_events'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."iq_traffic_events"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: iq_traffic_events'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."iq_traffic_events" FOR SELECT TO authenticated USING((organization_id IN (SELECT tj.my_org_ids()) AND tj.aiq_store_allows(organization_id,store_id)) OR (organization_id IN (SELECT tj.my_org_ids())));
CREATE POLICY consolidation_store_scope ON tj."iq_traffic_events" AS RESTRICTIVE FOR SELECT TO authenticated USING(tj.aiq_store_allows(organization_id,store_id));
GRANT SELECT ON tj."iq_traffic_events" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."iq_traffic_sources"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: iq_traffic_sources'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."iq_traffic_sources"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: iq_traffic_sources'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."iq_traffic_sources" FOR SELECT TO authenticated USING((organization_id IN (SELECT tj.my_org_ids())));
GRANT SELECT ON tj."iq_traffic_sources" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."iq_transaction_line_facts"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: iq_transaction_line_facts'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."iq_transaction_line_facts"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: iq_transaction_line_facts'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."iq_transaction_line_facts" FOR SELECT TO authenticated USING((tj.is_org_member(organization_id)));
GRANT SELECT ON tj."iq_transaction_line_facts" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."iq_up_disputes"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: iq_up_disputes'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."iq_up_disputes"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: iq_up_disputes'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."iq_up_disputes" FOR SELECT TO authenticated USING((organization_id IN (SELECT tj.my_org_ids())));
GRANT SELECT ON tj."iq_up_disputes" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."iq_up_queue_entries"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: iq_up_queue_entries'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."iq_up_queue_entries"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: iq_up_queue_entries'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."iq_up_queue_entries" FOR SELECT TO authenticated USING((organization_id IN (SELECT tj.my_org_ids())) OR (organization_id IN (SELECT tj.my_org_ids()) AND tj.aiq_store_allows(organization_id,store_id)));
CREATE POLICY consolidation_store_scope ON tj."iq_up_queue_entries" AS RESTRICTIVE FOR SELECT TO authenticated USING(tj.aiq_store_allows(organization_id,store_id));
GRANT SELECT ON tj."iq_up_queue_entries" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."kpi_events"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: kpi_events'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."kpi_events"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: kpi_events'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."kpi_events" FOR SELECT TO authenticated USING((tj.is_org_member(organization_id)));
GRANT SELECT ON tj."kpi_events" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."metric_definitions"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: metric_definitions'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."metric_definitions"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: metric_definitions'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."metric_definitions" FOR SELECT TO authenticated USING((tj.is_org_member(organization_id)));
GRANT SELECT ON tj."metric_definitions" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."metric_snapshots"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: metric_snapshots'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."metric_snapshots"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: metric_snapshots'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."metric_snapshots" FOR SELECT TO authenticated USING((tj.is_org_member(organization_id)));
GRANT SELECT ON tj."metric_snapshots" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."notification_archive"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: notification_archive'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."notification_archive"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: notification_archive'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."notification_archive" FOR SELECT TO authenticated USING(((SELECT tj.is_platform_admin())));
GRANT SELECT ON tj."notification_archive" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."org_app_entitlements"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: org_app_entitlements'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."org_app_entitlements"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: org_app_entitlements'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."org_app_entitlements" FOR SELECT TO authenticated USING((tj.is_org_member(organization_id)));
GRANT SELECT ON tj."org_app_entitlements" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."org_invites"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: org_invites'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."org_invites"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: org_invites'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."org_invites" FOR SELECT TO authenticated USING((tj.is_org_member(organization_id)));
GRANT SELECT ON tj."org_invites" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."org_kpis"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: org_kpis'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."org_kpis"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: org_kpis'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."org_kpis" FOR SELECT TO authenticated USING((tj.is_org_member(organization_id)));
GRANT SELECT ON tj."org_kpis" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."org_location_members"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: org_location_members'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."org_location_members"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: org_location_members'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."org_location_members" FOR SELECT TO authenticated USING((tj.is_org_member(organization_id)));
GRANT SELECT ON tj."org_location_members" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."org_locations"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: org_locations'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."org_locations"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: org_locations'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."org_locations" FOR SELECT TO authenticated USING((tj.is_org_member(organization_id)));
GRANT SELECT ON tj."org_locations" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."org_roles"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: org_roles'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."org_roles"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: org_roles'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."org_roles" FOR SELECT TO authenticated USING((tj.is_org_member(organization_id)));
GRANT SELECT ON tj."org_roles" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."org_targets"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: org_targets'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."org_targets"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: org_targets'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."org_targets" FOR SELECT TO authenticated USING((tj.is_org_member(organization_id)));
GRANT SELECT ON tj."org_targets" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."organization_members"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: organization_members'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."organization_members"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: organization_members'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."organization_members" FOR SELECT TO authenticated USING((tj.is_org_member(organization_id)));
GRANT SELECT ON tj."organization_members" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."organizations"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: organizations'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."organizations"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: organizations'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."organizations" FOR SELECT TO authenticated USING((tj.is_org_member(id)));
GRANT SELECT ON tj."organizations" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."persona_communication_protocol"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: persona_communication_protocol'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."persona_communication_protocol"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: persona_communication_protocol'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."persona_communication_protocol" FOR SELECT TO authenticated USING((tj.is_org_member(organization_id)));
GRANT SELECT ON tj."persona_communication_protocol" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."pipeline_stages"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: pipeline_stages'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."pipeline_stages"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: pipeline_stages'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."pipeline_stages" FOR SELECT TO authenticated USING((tj.is_org_member(organization_id)));
GRANT SELECT ON tj."pipeline_stages" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."platform_app_installations"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: platform_app_installations'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."platform_app_installations"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: platform_app_installations'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."platform_app_installations" FOR SELECT TO authenticated USING((tj.is_org_member(organization_id)));
GRANT SELECT ON tj."platform_app_installations" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."platform_connector_connections"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: platform_connector_connections'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."platform_connector_connections"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: platform_connector_connections'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."platform_connector_connections" FOR SELECT TO authenticated USING((tj.is_org_member(organization_id)));
GRANT SELECT ON tj."platform_connector_connections" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."products"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: products'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."products"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: products'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."products" FOR SELECT TO authenticated USING((tj.is_org_member(organization_id)));
GRANT SELECT ON tj."products" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."recording_transcripts"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: recording_transcripts'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."recording_transcripts"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: recording_transcripts'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."recording_transcripts" FOR SELECT TO authenticated USING((tj.is_org_member(organization_id)));
GRANT SELECT ON tj."recording_transcripts" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."retailer_products"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: retailer_products'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."retailer_products"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: retailer_products'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."retailer_products" FOR SELECT TO authenticated USING((tj.is_org_member(organization_id)));
GRANT SELECT ON tj."retailer_products" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."sales_recordings"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: sales_recordings'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."sales_recordings"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: sales_recordings'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."sales_recordings" FOR SELECT TO authenticated USING((tj.is_org_member(organization_id)));
GRANT SELECT ON tj."sales_recordings" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."sales_transactions"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: sales_transactions'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."sales_transactions"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: sales_transactions'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."sales_transactions" FOR SELECT TO authenticated USING((tj.is_org_member(organization_id)));
GRANT SELECT ON tj."sales_transactions" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."speciq_approval_history"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: speciq_approval_history'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."speciq_approval_history"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: speciq_approval_history'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."speciq_approval_history" FOR SELECT TO authenticated USING((organization_id IN (SELECT tj.my_org_ids())));
GRANT SELECT ON tj."speciq_approval_history" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."speciq_extension_requests"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: speciq_extension_requests'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."speciq_extension_requests"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: speciq_extension_requests'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."speciq_extension_requests" FOR SELECT TO authenticated USING((organization_id IN (SELECT tj.my_org_ids())));
GRANT SELECT ON tj."speciq_extension_requests" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."speciq_followup_sequences"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: speciq_followup_sequences'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."speciq_followup_sequences"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: speciq_followup_sequences'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."speciq_followup_sequences" FOR SELECT TO authenticated USING((organization_id IN (SELECT tj.my_org_ids())));
GRANT SELECT ON tj."speciq_followup_sequences" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."speciq_package_products"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: speciq_package_products'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."speciq_package_products"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: speciq_package_products'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."speciq_package_products" FOR SELECT TO authenticated USING((organization_id IN (SELECT tj.my_org_ids())));
GRANT SELECT ON tj."speciq_package_products" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."speciq_package_services"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: speciq_package_services'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."speciq_package_services"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: speciq_package_services'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."speciq_package_services" FOR SELECT TO authenticated USING((organization_id IN (SELECT tj.my_org_ids())));
GRANT SELECT ON tj."speciq_package_services" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."speciq_packages"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: speciq_packages'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."speciq_packages"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: speciq_packages'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."speciq_packages" FOR SELECT TO authenticated USING((organization_id IN (SELECT tj.my_org_ids())));
GRANT SELECT ON tj."speciq_packages" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."speciq_pricing_rules"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: speciq_pricing_rules'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."speciq_pricing_rules"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: speciq_pricing_rules'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."speciq_pricing_rules" FOR SELECT TO authenticated USING((organization_id IN (SELECT tj.my_org_ids())));
GRANT SELECT ON tj."speciq_pricing_rules" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."speciq_product_warranties"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: speciq_product_warranties'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."speciq_product_warranties"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: speciq_product_warranties'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."speciq_product_warranties" FOR SELECT TO authenticated USING((organization_id IN (SELECT tj.my_org_ids())));
GRANT SELECT ON tj."speciq_product_warranties" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."speciq_projects"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: speciq_projects'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."speciq_projects"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: speciq_projects'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."speciq_projects" FOR SELECT TO authenticated USING((organization_id IN (SELECT tj.my_org_ids())));
GRANT SELECT ON tj."speciq_projects" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."speciq_subscriptions"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: speciq_subscriptions'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."speciq_subscriptions"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: speciq_subscriptions'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."speciq_subscriptions" FOR SELECT TO authenticated USING((organization_id IN (SELECT tj.my_org_ids())));
GRANT SELECT ON tj."speciq_subscriptions" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."speciq_tax_rules"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: speciq_tax_rules'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."speciq_tax_rules"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: speciq_tax_rules'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."speciq_tax_rules" FOR SELECT TO authenticated USING((organization_id IN (SELECT tj.my_org_ids())));
GRANT SELECT ON tj."speciq_tax_rules" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."speciq_templates"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: speciq_templates'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."speciq_templates"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: speciq_templates'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."speciq_templates" FOR SELECT TO authenticated USING((organization_id IN (SELECT tj.my_org_ids())));
GRANT SELECT ON tj."speciq_templates" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."speciq_warranty_catalog"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: speciq_warranty_catalog'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."speciq_warranty_catalog"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: speciq_warranty_catalog'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."speciq_warranty_catalog" FOR SELECT TO authenticated USING((organization_id IN (SELECT tj.my_org_ids())));
GRANT SELECT ON tj."speciq_warranty_catalog" TO authenticated;
DO $guard$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='tj."stripe_events"'::regclass AND relrowsecurity) THEN RAISE EXCEPTION 'RLS required: stripe_events'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj."stripe_events"'::regclass) THEN RAISE EXCEPTION 'Review existing policies: stripe_events'; END IF;
END $guard$;
CREATE POLICY consolidation_reviewed_read ON tj."stripe_events" FOR SELECT TO authenticated USING(((SELECT tj.is_platform_admin())));
GRANT SELECT ON tj."stripe_events" TO authenticated;
