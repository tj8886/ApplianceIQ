-- Remaining reviewed reads; retain private invite credentials and unscoped AI cache.
CREATE TABLE tj_private.approved_staffing_prediction_ids(prediction_id uuid PRIMARY KEY REFERENCES tj.iq_staffing_predictions(id) ON DELETE CASCADE,approved_at timestamptz NOT NULL DEFAULT now(),basis text NOT NULL CHECK(basis='verified_canada_source'));
ALTER TABLE tj_private.approved_staffing_prediction_ids ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj_private.approved_staffing_prediction_ids FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj_private.approved_staffing_ids() RETURNS uuid[] LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT CASE WHEN tj_private.has_active_mapped_org() THEN coalesce(array_agg(prediction_id),'{}'::uuid[]) ELSE '{}'::uuid[] END FROM tj_private.approved_staffing_prediction_ids;
$$;
REVOKE ALL ON FUNCTION tj_private.approved_staffing_ids() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.approved_staffing_ids() TO authenticated;
DO $guard$ BEGIN IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='tj.academy_content_suggestions'::regclass) OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj.academy_content_suggestions'::regclass) THEN RAISE EXCEPTION 'Review existing RLS: academy_content_suggestions'; END IF; END $guard$;
CREATE POLICY consolidation_remaining_read ON tj.academy_content_suggestions FOR SELECT TO authenticated USING((SELECT tj_private.is_product_governance_admin()));
GRANT SELECT ON tj.academy_content_suggestions TO authenticated;
DO $guard$ BEGIN IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='tj.aiq_product_versions'::regclass) OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj.aiq_product_versions'::regclass) THEN RAISE EXCEPTION 'Review existing RLS: aiq_product_versions'; END IF; END $guard$;
CREATE POLICY consolidation_remaining_read ON tj.aiq_product_versions FOR SELECT TO authenticated USING(tj_private.can_read_runtime_org(organization_id) AND tj.is_org_admin(organization_id) AND EXISTS(SELECT 1 FROM tj.aiq_products p WHERE p.id=product_id AND p.organization_id=aiq_product_versions.organization_id));
GRANT SELECT (id,organization_id,product_id,version_number,created_at) ON tj.aiq_product_versions TO authenticated;
DO $guard$ BEGIN IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='tj.crm_postmortems'::regclass) OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj.crm_postmortems'::regclass) THEN RAISE EXCEPTION 'Review existing RLS: crm_postmortems'; END IF; END $guard$;
CREATE POLICY consolidation_remaining_read ON tj.crm_postmortems FOR SELECT TO authenticated USING(tj_private.can_read_runtime_org(organization_id) AND EXISTS(SELECT 1 FROM tj.profiles p WHERE p.id=salesperson_id AND tj.aiq_scope_allows(crm_postmortems.organization_id,p.user_id) AND (is_private IS FALSE OR tj_private.is_source_self(p.user_id))) AND EXISTS(SELECT 1 FROM tj.crm_deals d WHERE d.id=deal_id AND d.organization_id=crm_postmortems.organization_id) AND (recording_id IS NULL OR EXISTS(SELECT 1 FROM tj.sales_recordings r WHERE r.id=recording_id AND r.organization_id=crm_postmortems.organization_id AND r.consent_confirmed IS TRUE)));
GRANT SELECT ON tj.crm_postmortems TO authenticated;
DO $guard$ BEGIN IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='tj.iq_staffing_predictions'::regclass) OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj.iq_staffing_predictions'::regclass) THEN RAISE EXCEPTION 'Review existing RLS: iq_staffing_predictions'; END IF; END $guard$;
CREATE POLICY consolidation_remaining_read ON tj.iq_staffing_predictions FOR SELECT TO authenticated USING(id=ANY((SELECT tj_private.approved_staffing_ids())::uuid[]) AND tj_private.can_read_runtime_org(organization_id) AND tj.aiq_store_allows(organization_id,store_id));
GRANT SELECT ON tj.iq_staffing_predictions TO authenticated;
DO $guard$ BEGIN IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='tj.performance_metric_competency_map'::regclass) OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj.performance_metric_competency_map'::regclass) THEN RAISE EXCEPTION 'Review existing RLS: performance_metric_competency_map'; END IF; END $guard$;
CREATE POLICY consolidation_remaining_read ON tj.performance_metric_competency_map FOR SELECT TO authenticated USING((organization_id IS NULL AND (SELECT tj_private.has_active_mapped_org())) OR tj_private.can_read_runtime_org(organization_id));
GRANT SELECT ON tj.performance_metric_competency_map TO authenticated;
CREATE POLICY consolidation_parent_scope ON tj.activities AS RESTRICTIVE FOR SELECT TO authenticated USING(tj_private.can_read_runtime_org(organization_id) AND tj.aiq_scope_allows(organization_id,user_id));
CREATE POLICY consolidation_parent_scope ON tj.sales_recordings AS RESTRICTIVE FOR SELECT TO authenticated USING(tj_private.can_read_runtime_org(organization_id) AND tj.aiq_scope_allows(organization_id,user_id));
CREATE POLICY consolidation_parent_scope ON tj.recording_transcripts AS RESTRICTIVE FOR SELECT TO authenticated USING(tj_private.can_read_runtime_org(organization_id) AND EXISTS(SELECT 1 FROM tj.sales_recordings r WHERE r.id=recording_id AND r.organization_id=recording_transcripts.organization_id AND r.consent_confirmed IS TRUE));
CREATE POLICY consolidation_parent_scope ON tj.ai_coaching_reviews AS RESTRICTIVE FOR SELECT TO authenticated USING(tj_private.can_read_runtime_org(organization_id) AND (activity_id IS NULL OR EXISTS(SELECT 1 FROM tj.activities a WHERE a.id=activity_id AND a.organization_id=ai_coaching_reviews.organization_id)) AND (recording_id IS NULL OR EXISTS(SELECT 1 FROM tj.sales_recordings r WHERE r.id=recording_id AND r.organization_id=ai_coaching_reviews.organization_id AND r.consent_confirmed IS TRUE)));
CREATE POLICY consolidation_parent_scope ON tj.metric_snapshots AS RESTRICTIVE FOR SELECT TO authenticated USING(tj_private.can_read_runtime_org(organization_id) AND tj.aiq_scope_allows(organization_id,user_id) AND tj.aiq_store_allows(organization_id,location_id));
CREATE POLICY consolidation_parent_scope ON tj.iq_customer_interactions AS RESTRICTIVE FOR SELECT TO authenticated USING(tj_private.can_read_runtime_org(organization_id) AND tj.aiq_scope_allows(organization_id,salesperson_user_id));
CREATE FUNCTION tj_private.redacted_product_version(p_version uuid) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT v.snapshot-'dealer_cost' FROM tj.aiq_product_versions v JOIN tj.aiq_products p ON p.id=v.product_id AND p.organization_id=v.organization_id WHERE v.id=p_version AND tj_private.can_read_runtime_org(v.organization_id) AND tj.is_org_admin(v.organization_id);
$$;
REVOKE ALL ON FUNCTION tj_private.redacted_product_version(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.redacted_product_version(uuid) TO authenticated;
CREATE VIEW tj.aiq_product_versions_app WITH(security_invoker=true,security_barrier=true) AS SELECT id,organization_id,product_id,version_number,tj_private.redacted_product_version(id) snapshot,created_at FROM tj.aiq_product_versions;
REVOKE ALL ON tj.aiq_product_versions_app FROM PUBLIC,anon,authenticated;
GRANT SELECT ON tj.aiq_product_versions_app TO authenticated;
CREATE OR REPLACE VIEW tj.crm_conversation_records WITH(security_invoker=true,security_barrier=true) AS SELECT a.id AS activity_id,
    a.organization_id,
    a.user_id,
    a.entity_type AS crm_record_type,
    a.entity_id AS crm_record_id,
    a.activity_type,
    a.title,
    a.summary,
    a.source,
    a.related_file_path,
    a.created_at,
    r.id AS recording_id,
    r.kind AS recording_kind,
    r.file_path AS recording_path,
    r.status AS recording_status,
    t.id AS transcript_id,
    t.content AS transcript,
    cr.id AS coaching_review_id,
    cr.kpi_scores,
    cr.overall_score
   FROM tj.activities a
     LEFT JOIN tj.sales_recordings r ON r.id = a.related_recording_id AND r.organization_id=a.organization_id AND r.user_id=a.user_id AND r.consent_confirmed IS TRUE
     LEFT JOIN tj.recording_transcripts t ON t.recording_id = r.id AND t.organization_id=a.organization_id
     LEFT JOIN LATERAL ( SELECT x.id,
            x.organization_id,
            x.activity_id,
            x.recording_id,
            x.review_kind,
            x.analysis,
            x.kpi_scores,
            x.overall_score,
            x.model,
            x.created_at
           FROM tj.ai_coaching_reviews x
          WHERE x.activity_id = a.id AND x.organization_id=a.organization_id
          ORDER BY x.created_at DESC
         LIMIT 1) cr ON true
  WHERE a.activity_type = ANY (ARRAY['voice_call'::text, 'sales_pitch_recording'::text, 'email'::text, 'spec_presentation'::text, 'ai_coaching_review'::text, 'ai_summary'::text, 'note'::text]);
REVOKE ALL ON tj.crm_conversation_records FROM PUBLIC,anon,authenticated;
GRANT SELECT ON tj.crm_conversation_records TO authenticated;
CREATE OR REPLACE VIEW tj.performance_metric_diagnostics WITH(security_invoker=true,security_barrier=true) AS WITH latest AS (
         SELECT DISTINCT ON (ms.organization_id, ms.user_id, ms.metric_key, (COALESCE(ms.metric_subtype, ''::text))) ms.id,
            ms.organization_id,
            ms.location_id,
            ms.user_id,
            ms.period_type,
            ms.period_key,
            ms.metric_key,
            ms.actual_value,
            ms.target_value,
            ms.variance_value,
            ms.variance_pct,
            ms.prior_year_value,
            ms.yoy_change_pct,
            ms.computed_at,
            ms.metric_subtype
           FROM tj.metric_snapshots ms
          WHERE ms.user_id IS NOT NULL
          ORDER BY ms.organization_id, ms.user_id, ms.metric_key, (COALESCE(ms.metric_subtype, ''::text)), ms.computed_at DESC
        )
 SELECT l.organization_id,
    l.user_id,
    l.metric_key,
    l.metric_subtype,
    l.period_type,
    l.period_key,
    l.actual_value,
    l.target_value,
    l.variance_pct,
    l.computed_at,
    m.competency_id,
    c.code AS competency_code,
    c.name AS competency_name,
    m.causal_weight,
    m.direction,
    m.rationale,
        CASE
            WHEN l.target_value IS NULL OR l.target_value = 0::numeric THEN NULL::numeric
            WHEN m.direction = 'lower_better'::text THEN round((l.target_value - l.actual_value) / abs(l.target_value) * 100::numeric, 2)
            ELSE round((l.actual_value - l.target_value) / abs(l.target_value) * 100::numeric, 2)
        END AS target_gap_pct
   FROM latest l
     JOIN tj.performance_metric_competency_map m ON m.metric_key = l.metric_key AND m.active = true AND (m.organization_id IS NULL OR m.organization_id = l.organization_id)
     JOIN tj.performance_competencies c ON c.id = m.competency_id;
REVOKE ALL ON tj.performance_metric_diagnostics FROM PUBLIC,anon,authenticated;
GRANT SELECT ON tj.performance_metric_diagnostics TO authenticated;
CREATE OR REPLACE VIEW tj.v_commercial_project_timelines WITH(security_invoker=true,security_barrier=true) AS SELECT organization_id,
    owner_user_id,
    record_type,
    stage,
    value_amount,
    created_at AS lead_created_at,
    quote_sent_at,
    purchase_date,
    delivery_date,
    closed_at,
    EXTRACT(day FROM quote_sent_at - created_at) AS lead_to_quote_days,
        CASE
            WHEN purchase_date IS NOT NULL AND delivery_date IS NOT NULL THEN delivery_date - purchase_date
            ELSE NULL::integer
        END AS sale_to_delivery_days,
    EXTRACT(day FROM closed_at - created_at) AS lead_to_close_days
   FROM tj.crm_deals d
  WHERE (record_type = ANY (ARRAY['commercial'::text, 'builder_designer'::text, 'trade'::text])) AND deleted_at IS NULL;
REVOKE ALL ON tj.v_commercial_project_timelines FROM PUBLIC,anon,authenticated;
GRANT SELECT ON tj.v_commercial_project_timelines TO authenticated;
CREATE OR REPLACE VIEW tj.v_crm_accountability WITH(security_invoker=true,security_barrier=true) AS SELECT ci.organization_id,
    ci.store_id,
    ci.salesperson_user_id,
    ci.client_type,
    ci.outcome,
    ci.id AS interaction_id,
    ci.started_at,
    ci.ended_at,
    ci.contact_id,
    c.crm_completeness,
    c.deleted_at AS contact_deleted_at,
    c.full_name AS contact_name,
    c.email::text AS contact_email,
    c.phone AS contact_phone,
    d.id AS deal_id,
    d.stage AS deal_stage,
    d.deleted_at AS deal_deleted_at,
    d.is_archived AS deal_archived,
    ci.follow_up_date,
    ci.no_follow_up,
    ci.follow_up_type,
        CASE
            WHEN ci.contact_id IS NULL THEN true
            ELSE false
        END AS no_crm_created,
        CASE
            WHEN c.deleted_at IS NOT NULL THEN true
            ELSE false
        END AS contact_was_deleted,
        CASE
            WHEN d.deleted_at IS NOT NULL THEN true
            ELSE false
        END AS deal_was_deleted
   FROM tj.iq_customer_interactions ci
     LEFT JOIN tj.aicrm_contacts c ON c.id = ci.contact_id AND c.organization_id=ci.organization_id
     LEFT JOIN tj.crm_deals d ON d.up_interaction_id = ci.id AND d.organization_id=ci.organization_id AND d.deleted_at IS NULL;
REVOKE ALL ON tj.v_crm_accountability FROM PUBLIC,anon,authenticated;
GRANT SELECT ON tj.v_crm_accountability TO authenticated;
CREATE OR REPLACE VIEW tj.v_floor_analytics WITH(security_invoker=true,security_barrier=true) AS SELECT ci.organization_id,
    ci.store_id,
    ci.salesperson_user_id,
    ci.client_type,
    ci.outcome,
    ci.started_at,
    ci.ended_at,
    ci.accepted_at,
    ci.sale_amount,
    EXTRACT(epoch FROM ci.ended_at - ci.started_at) / 60.0 AS interaction_minutes,
    EXTRACT(epoch FROM cwq.greeted_at - cwq.arrival_time) AS greeting_seconds,
    EXTRACT(epoch FROM ci.ended_at - COALESCE(cwq.greeted_at, ci.started_at)) / 60.0 AS greeting_to_end_minutes,
    cwq.greeted_by IS NOT NULL AS had_greeter,
    cwq.arrival_time,
    cwq.greeted_at,
    cwq.greeted_by
   FROM tj.iq_customer_interactions ci
     LEFT JOIN tj.iq_customer_waiting_queue cwq ON cwq.id = ci.customer_waiting_id AND cwq.organization_id=ci.organization_id AND cwq.store_id=ci.store_id;
REVOKE ALL ON tj.v_floor_analytics FROM PUBLIC,anon,authenticated;
GRANT SELECT ON tj.v_floor_analytics TO authenticated;
NOTIFY pgrst,'reload schema';
