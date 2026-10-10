-- Reviewed Command Centre entry points; prediction supersets remain withheld.
CREATE TABLE tj_private.approved_prediction_ids(prediction_id uuid PRIMARY KEY REFERENCES tj.decision_predictions(id) ON DELETE CASCADE,approved_at timestamptz NOT NULL DEFAULT now(),basis text NOT NULL DEFAULT 'source_catalog');
ALTER TABLE tj_private.approved_prediction_ids ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj_private.approved_prediction_ids FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj_private.assert_runtime_org(p_org uuid) RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $guard$
BEGIN IF p_org IS NULL OR NOT tj.is_org_member(p_org) OR NOT EXISTS(SELECT 1 FROM tj.organizations WHERE id=p_org AND deleted_at IS NULL) THEN RAISE EXCEPTION 'access_denied' USING ERRCODE='42501'; END IF; END $guard$;
REVOKE ALL ON FUNCTION tj_private.assert_runtime_org(uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.decision_get_feed(p_organization_id uuid, p_limit integer DEFAULT 25) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='tj','extensions','pg_temp' AS $function$ BEGIN PERFORM tj_private.assert_runtime_org(p_organization_id); RETURN (select coalesce(jsonb_agg(to_jsonb(x) order by x.priority_score desc,x.created_at desc),'[]'::jsonb)
from (
 select c.id,c.module,c.title,c.summary,c.recommendation,c.consequence_if_ignored,c.decision_type,c.status,c.severity,c.financial_impact_cad,c.priority_score,c.confidence,c.evidence_quality,c.owner_id,c.due_at,c.created_at,
   (select count(*) from tj.decision_evidence e where e.decision_case_id=c.id and e.organization_id=p_organization_id) as evidence_count,
   (select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'text',a.action_text,'status',a.status,'owner_id',a.owner_id,'due_at',a.due_at) order by a.created_at),'[]'::jsonb) from tj.decision_actions a where a.decision_case_id=c.id and a.organization_id=p_organization_id) as actions,
   (select coalesce(jsonb_agg(jsonb_build_object('type',p.prediction_type,'predicted_value',p.predicted_value,'delta',p.predicted_delta,'unit',p.unit,'probability',p.probability,'horizon',p.horizon) order by p.generated_at desc),'[]'::jsonb) from tj.decision_predictions p where p.decision_case_id=c.id and p.organization_id=p_organization_id and exists(select 1 from tj_private.approved_prediction_ids approved where approved.prediction_id=p.id)) as predictions
 from tj.decision_cases c
 where c.organization_id=p_organization_id and c.status not in ('completed','dismissed','expired')
 order by c.priority_score desc,c.created_at desc
 limit greatest(1,least(coalesce(p_limit,25),100))
) x); END $function$;
REVOKE ALL ON FUNCTION tj_private.decision_get_feed(uuid,integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.decision_get_feed(uuid,integer) TO authenticated;
CREATE OR REPLACE FUNCTION tj.decision_get_feed(p_organization_id uuid, p_limit integer DEFAULT 25) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $adapter$ SELECT tj_private.decision_get_feed(p_organization_id,p_limit); $adapter$;
REVOKE ALL ON FUNCTION tj.decision_get_feed(uuid,integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj.decision_get_feed(uuid,integer) TO authenticated;
CREATE OR REPLACE FUNCTION tj_private.decision_get_prediction_dashboard(p_organization_id uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='tj','extensions','pg_temp' AS $function$ BEGIN PERFORM tj_private.assert_runtime_org(p_organization_id); RETURN (select case when tj.is_org_member(p_organization_id) then jsonb_build_object(
  'summary',jsonb_build_object('active_predictions',count(*) filter(where p.status='active'),'total_predicted_impact_cad',coalesce(sum(p.financial_impact_cad) filter(where p.status='active'),0),'total_cost_of_inaction_cad',coalesce(sum(p.cost_of_inaction_cad) filter(where p.status='active'),0),'measured_predictions',count(*) filter(where p.status='measured')),
  'predictions',coalesce(jsonb_agg(jsonb_build_object('id',p.id,'case_id',c.id,'title',c.title,'module',c.module,'priority_score',c.priority_score,'prediction_type',p.prediction_type,'horizon',p.horizon,'baseline_value',p.baseline_value,'predicted_value',p.predicted_value,'predicted_delta',p.predicted_delta,'unit',p.unit,'probability',p.probability,'lower_bound',p.lower_bound,'upper_bound',p.upper_bound,'financial_impact_cad',p.financial_impact_cad,'cost_of_inaction_cad',p.cost_of_inaction_cad,'assumptions',p.assumptions,'model_name',p.model_name,'model_version',p.model_version,'status',p.status,'actual_value',p.actual_value,'absolute_error',p.absolute_error,'percent_error',p.percent_error,'generated_at',p.generated_at) order by c.priority_score desc),'[]'::jsonb)
 ) else jsonb_build_object('error','Not authorized') end
 from tj.decision_predictions p join tj.decision_cases c on c.id=p.decision_case_id and c.organization_id=p_organization_id where p.organization_id=p_organization_id and exists(select 1 from tj_private.approved_prediction_ids approved where approved.prediction_id=p.id)); END $function$;
REVOKE ALL ON FUNCTION tj_private.decision_get_prediction_dashboard(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.decision_get_prediction_dashboard(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION tj.decision_get_prediction_dashboard(p_organization_id uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $adapter$ SELECT tj_private.decision_get_prediction_dashboard(p_organization_id); $adapter$;
REVOKE ALL ON FUNCTION tj.decision_get_prediction_dashboard(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj.decision_get_prediction_dashboard(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION tj_private.decision_update_action(p_action_id uuid, p_status text, p_owner_id uuid DEFAULT NULL::uuid, p_due_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_outcome_success boolean DEFAULT NULL::boolean, p_outcome_value numeric DEFAULT NULL::numeric, p_outcome_unit text DEFAULT NULL::text, p_outcome_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_action tj.decision_actions; v_case_status text;
begin

 SELECT * INTO v_action FROM tj.decision_actions WHERE id=p_action_id FOR UPDATE;
 PERFORM tj_private.assert_runtime_org(v_action.organization_id);
 IF NOT EXISTS(SELECT 1 FROM tj.decision_cases WHERE id=v_action.decision_case_id AND organization_id=v_action.organization_id) THEN RAISE EXCEPTION 'access_denied' USING ERRCODE='42501'; END IF;
 IF p_owner_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.organization_members WHERE organization_id=v_action.organization_id AND user_id=p_owner_id AND status='active') THEN RAISE EXCEPTION 'owner_not_in_organization'; END IF;
 IF p_status IS NULL OR p_status NOT IN('recommended','accepted','rejected','assigned','in_progress','completed','cancelled','measured') THEN RAISE EXCEPTION 'invalid_status'; END IF;
 update tj.decision_actions set
   status=p_status,
   owner_id=coalesce(p_owner_id,owner_id), due_at=coalesce(p_due_at,due_at),
   accepted_at=case when p_status='accepted' and accepted_at is null then now() else accepted_at end,
   started_at=case when p_status='in_progress' and started_at is null then now() else started_at end,
   completed_at=case when p_status in ('completed','measured') and completed_at is null then now() else completed_at end,
   outcome_success=coalesce(p_outcome_success,outcome_success), outcome_value=coalesce(p_outcome_value,outcome_value), outcome_unit=coalesce(p_outcome_unit,outcome_unit), outcome_notes=coalesce(p_outcome_notes,outcome_notes), updated_at=now()
 where id=p_action_id returning * into v_action;
 if v_action.id is null then raise exception 'Decision action not found or unavailable'; end if;
 v_case_status:=case p_status when 'accepted' then 'accepted' when 'assigned' then 'accepted' when 'in_progress' then 'in_progress' when 'completed' then 'completed' when 'measured' then 'completed' when 'rejected' then 'rejected' when 'cancelled' then 'dismissed' else null end;
 if v_case_status is not null then update tj.decision_cases set status=v_case_status,owner_id=coalesce(p_owner_id,owner_id),due_at=coalesce(p_due_at,due_at),updated_by=(select tj_private.current_source_user_id()) where id=v_action.decision_case_id AND organization_id=v_action.organization_id; end if;
 return to_jsonb(v_action);
end $function$;
REVOKE ALL ON FUNCTION tj_private.decision_update_action(uuid,text,uuid,timestamptz,boolean,numeric,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.decision_update_action(uuid,text,uuid,timestamptz,boolean,numeric,text,text) TO authenticated;
CREATE OR REPLACE FUNCTION tj.decision_update_action(p_action_id uuid, p_status text, p_owner_id uuid DEFAULT NULL::uuid, p_due_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_outcome_success boolean DEFAULT NULL::boolean, p_outcome_value numeric DEFAULT NULL::numeric, p_outcome_unit text DEFAULT NULL::text, p_outcome_notes text DEFAULT NULL::text) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $adapter$ SELECT tj_private.decision_update_action(p_action_id,p_status,p_owner_id,p_due_at,p_outcome_success,p_outcome_value,p_outcome_unit,p_outcome_notes); $adapter$;
REVOKE ALL ON FUNCTION tj.decision_update_action(uuid,text,uuid,timestamptz,boolean,numeric,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj.decision_update_action(uuid,text,uuid,timestamptz,boolean,numeric,text,text) TO authenticated;
CREATE OR REPLACE FUNCTION tj_private.executive_get_command_centre(p_organization_id uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='tj','extensions','pg_temp' AS $function$ BEGIN PERFORM tj_private.assert_runtime_org(p_organization_id); RETURN (with latest as (
  select * from executive_intelligence_snapshots
  where organization_id=p_organization_id
  order by generated_at desc limit 1
)
select jsonb_build_object(
  'snapshot',coalesce((select to_jsonb(l) from latest l),'{}'::jsonb),
  'top_risks',coalesce((select jsonb_agg(to_jsonb(i) order by i.priority_score desc,i.created_at desc) from (select * from executive_intelligence_insights where organization_id=p_organization_id and status in ('open','acknowledged','in_progress') and insight_type='risk' order by priority_score desc,created_at desc limit 10) i),'[]'::jsonb),
  'top_opportunities',coalesce((select jsonb_agg(to_jsonb(i) order by i.priority_score desc,i.created_at desc) from (select * from executive_intelligence_insights where organization_id=p_organization_id and status in ('open','acknowledged','in_progress') and insight_type='opportunity' order by priority_score desc,created_at desc limit 10) i),'[]'::jsonb),
  'priority_actions',coalesce((select jsonb_agg(to_jsonb(i) order by i.priority_score desc,i.created_at desc) from (select * from executive_intelligence_insights where organization_id=p_organization_id and status in ('open','acknowledged','in_progress') and insight_type in ('action','performance') order by priority_score desc,created_at desc limit 10) i),'[]'::jsonb),
  'generated_at',now()
)); END $function$;
REVOKE ALL ON FUNCTION tj_private.executive_get_command_centre(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.executive_get_command_centre(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION tj.executive_get_command_centre(p_organization_id uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $adapter$ SELECT tj_private.executive_get_command_centre(p_organization_id); $adapter$;
REVOKE ALL ON FUNCTION tj.executive_get_command_centre(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj.executive_get_command_centre(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION tj_private.compute_iq_score(p_org_id uuid, p_period text DEFAULT '2026-06'::text, p_location_id uuid DEFAULT NULL::uuid, p_user_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(metric_key text, metric_label text, max_points numeric, actual_value numeric, target_value numeric, pct_of_target numeric, earned_points numeric, sort_order integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
DECLARE
  w RECORD;
  v_actual NUMERIC;
  v_target NUMERIC;
  v_pct NUMERIC;
  v_earned NUMERIC;
  v_total_interactions BIGINT;
  v_complete_contacts BIGINT;
  v_no_sale_total BIGINT;
  v_has_followup BIGINT;
BEGIN

 PERFORM tj_private.assert_runtime_org(p_org_id);
 IF p_user_id IS NULL AND p_org_id NOT IN(SELECT tj_private.unrestricted_store_organizations()) THEN RAISE EXCEPTION 'access_denied' USING ERRCODE='42501'; END IF;
 IF p_user_id IS NOT NULL AND (NOT tj.aiq_scope_allows(p_org_id,p_user_id) OR NOT EXISTS(SELECT 1 FROM tj.organization_members WHERE organization_id=p_org_id AND user_id=p_user_id AND status='active')) THEN RAISE EXCEPTION 'access_denied' USING ERRCODE='42501'; END IF;
 IF p_location_id IS NOT NULL AND (NOT tj.aiq_store_allows(p_org_id,p_location_id) OR NOT EXISTS(SELECT 1 FROM tj.org_locations WHERE id=p_location_id AND organization_id=p_org_id AND is_active)) THEN RAISE EXCEPTION 'access_denied' USING ERRCODE='42501'; END IF;
  -- Pre-compute CRM accountability metrics for this scope
  SELECT
    count(*),
    count(*) FILTER (WHERE NOT no_crm_created AND crm_completeness = 'complete'),
    count(*) FILTER (WHERE outcome != 'sale'),
    count(*) FILTER (WHERE outcome != 'sale' AND follow_up_date IS NOT NULL)
  INTO v_total_interactions, v_complete_contacts, v_no_sale_total, v_has_followup
  FROM v_crm_accountability ca
  WHERE ca.organization_id = p_org_id
    AND (p_location_id IS NULL OR ca.store_id = p_location_id)
    AND (p_user_id IS NULL OR ca.salesperson_user_id = p_user_id);

  FOR w IN
    SELECT sw.metric_key, sw.metric_label, sw.max_points, sw.source_type, sw.direction, sw.sort_order
    FROM iq_score_weights sw
    WHERE sw.organization_id = p_org_id AND sw.is_active = true
    ORDER BY sw.sort_order
  LOOP
    v_actual := NULL;
    v_target := NULL;
    v_pct := 0;
    v_earned := 0;

    IF w.source_type = 'metric_snapshot' THEN
      -- Pull from metric_snapshots
      SELECT ms.actual_value, ms.target_value
      INTO v_actual, v_target
      FROM metric_snapshots ms
      WHERE ms.organization_id = p_org_id
        AND ms.period_type = 'monthly'
        AND ms.period_key = p_period
        AND ms.metric_key = w.metric_key
        AND (
          (p_user_id IS NOT NULL AND ms.user_id = p_user_id) OR
          (p_user_id IS NULL AND p_location_id IS NOT NULL AND ms.location_id = p_location_id AND ms.user_id IS NULL) OR
          (p_user_id IS NULL AND p_location_id IS NULL AND ms.location_id IS NULL AND ms.user_id IS NULL)
        )
      LIMIT 1;

      IF v_actual IS NOT NULL AND v_target IS NOT NULL AND v_target > 0 THEN
        IF w.direction = 'lower_is_better' THEN
          v_pct := LEAST(v_target / NULLIF(v_actual, 0), 1.0);
        ELSE
          v_pct := LEAST(v_actual / v_target, 1.0);
        END IF;
        v_earned := ROUND(v_pct * w.max_points, 1);
      END IF;

    ELSIF w.metric_key = 'crm_completion' THEN
      -- CRM Completion Rate
      v_target := 100;
      IF v_total_interactions > 0 THEN
        v_actual := ROUND((v_complete_contacts::numeric / v_total_interactions) * 100, 1);
        v_pct := LEAST(v_actual / 100.0, 1.0);
        v_earned := ROUND(v_pct * w.max_points, 1);
      ELSE
        v_actual := 0;
      END IF;

    ELSIF w.metric_key = 'follow_up_compliance' THEN
      -- Follow-up rate on no-sale
      v_target := 100;
      IF v_no_sale_total > 0 THEN
        v_actual := ROUND((v_has_followup::numeric / v_no_sale_total) * 100, 1);
        v_pct := LEAST(v_actual / 100.0, 1.0);
        v_earned := ROUND(v_pct * w.max_points, 1);
      ELSE
        v_actual := 0;
      END IF;
    END IF;

    metric_key := w.metric_key;
    metric_label := w.metric_label;
    max_points := w.max_points;
    actual_value := v_actual;
    target_value := v_target;
    pct_of_target := ROUND(COALESCE(v_pct, 0) * 100, 1);
    earned_points := COALESCE(v_earned, 0);
    sort_order := w.sort_order;
    RETURN NEXT;
  END LOOP;
END $function$;
REVOKE ALL ON FUNCTION tj_private.compute_iq_score(uuid,text,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.compute_iq_score(uuid,text,uuid,uuid) TO authenticated;
CREATE OR REPLACE FUNCTION tj.compute_iq_score(p_org_id uuid, p_period text DEFAULT '2026-06'::text, p_location_id uuid DEFAULT NULL::uuid, p_user_id uuid DEFAULT NULL::uuid) RETURNS TABLE(metric_key text, metric_label text, max_points numeric, actual_value numeric, target_value numeric, pct_of_target numeric, earned_points numeric, sort_order integer) LANGUAGE sql SECURITY INVOKER SET search_path='' AS $adapter$ SELECT * FROM tj_private.compute_iq_score(p_org_id,p_period,p_location_id,p_user_id); $adapter$;
REVOKE ALL ON FUNCTION tj.compute_iq_score(uuid,text,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj.compute_iq_score(uuid,text,uuid,uuid) TO authenticated;
CREATE FUNCTION tj_private.decision_record_prediction_outcome(p_prediction_id uuid,p_actual_value numeric,p_actual_financial_impact_cad numeric DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $function$
DECLARE v_pred tj.decision_predictions%ROWTYPE; v_error_pct numeric; v_abs_error numeric; v_direction text; v_module text;
BEGIN
 SELECT * INTO v_pred FROM tj.decision_predictions WHERE id=p_prediction_id FOR UPDATE;
 PERFORM tj_private.assert_runtime_org(v_pred.organization_id);
 IF NOT EXISTS(SELECT 1 FROM tj_private.approved_prediction_ids WHERE prediction_id=p_prediction_id)
 OR NOT EXISTS(SELECT 1 FROM tj.decision_cases WHERE id=v_pred.decision_case_id AND organization_id=v_pred.organization_id)
 THEN RAISE EXCEPTION 'access_denied' USING ERRCODE='42501'; END IF;
 IF p_actual_value IS NULL OR p_actual_value::text IN('NaN','Infinity','-Infinity') OR p_actual_financial_impact_cad::text IN('NaN','Infinity','-Infinity') THEN RAISE EXCEPTION 'invalid_actual_value'; END IF;
 v_module:=coalesce(v_pred.model_name,'unknown');
 PERFORM pg_advisory_xact_lock(hashtextextended(v_pred.organization_id::text||'/'||v_module||'/'||v_pred.prediction_type,0));
 v_abs_error:=abs(p_actual_value-v_pred.predicted_value);
 IF v_pred.predicted_value IS NOT NULL AND v_pred.predicted_value<>0 THEN
 v_error_pct:=round(100*(p_actual_value-v_pred.predicted_value)/abs(v_pred.predicted_value),2);
 v_direction:=CASE WHEN v_error_pct>0 THEN 'over' WHEN v_error_pct<0 THEN 'under' ELSE 'exact' END;
 END IF;
 UPDATE tj.decision_predictions SET actual_value=p_actual_value,actual_financial_impact_cad=coalesce(p_actual_financial_impact_cad,p_actual_value),absolute_error=v_abs_error,percent_error=v_error_pct,error_pct=v_error_pct,status='measured',measured_at=now() WHERE id=p_prediction_id;
 INSERT INTO tj.decision_model_performance(organization_id,module,prediction_type,sample_count,mean_absolute_error,mean_absolute_percentage_error,last_measured_at,updated_at)
 SELECT v_pred.organization_id,v_module,v_pred.prediction_type,count(*),round(avg(p.absolute_error),2),round(avg(abs(p.percent_error)),2),now(),now()
 FROM tj.decision_predictions p JOIN tj_private.approved_prediction_ids a ON a.prediction_id=p.id
 WHERE p.organization_id=v_pred.organization_id AND coalesce(p.model_name,'unknown')=v_module AND p.prediction_type=v_pred.prediction_type AND p.status='measured'
 ON CONFLICT(organization_id,module,prediction_type) DO UPDATE SET sample_count=excluded.sample_count,mean_absolute_error=excluded.mean_absolute_error,mean_absolute_percentage_error=excluded.mean_absolute_percentage_error,last_measured_at=excluded.last_measured_at,updated_at=excluded.updated_at;
 RETURN jsonb_build_object('prediction_id',p_prediction_id,'predicted',v_pred.predicted_value,'actual',p_actual_value,'error_pct',v_error_pct,'direction',v_direction);
END $function$;
REVOKE ALL ON FUNCTION tj_private.decision_record_prediction_outcome(uuid,numeric,numeric) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.decision_record_prediction_outcome(uuid,numeric,numeric) TO authenticated;
CREATE OR REPLACE FUNCTION tj.decision_record_prediction_outcome(p_prediction_id uuid,p_actual_value numeric,p_actual_financial_impact_cad numeric DEFAULT NULL) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $adapter$ SELECT tj_private.decision_record_prediction_outcome(p_prediction_id,p_actual_value,p_actual_financial_impact_cad); $adapter$;
REVOKE ALL ON FUNCTION tj.decision_record_prediction_outcome(uuid,numeric,numeric) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj.decision_record_prediction_outcome(uuid,numeric,numeric) TO authenticated;
NOTIFY pgrst,'reload schema';
