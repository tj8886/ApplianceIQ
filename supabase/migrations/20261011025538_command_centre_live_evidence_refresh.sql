-- Old snapshots and metric rows are retained. Missing evidence is nullable.
ALTER TABLE tj.executive_intelligence_snapshots ALTER COLUMN overall_health_score DROP NOT NULL;
CREATE TABLE tj_private.command_centre_refresh_queue(
 organization_id uuid PRIMARY KEY REFERENCES tj.organizations(id), requested_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 processed_at timestamptz, attempts integer NOT NULL DEFAULT 0, last_error text, next_attempt_at timestamptz NOT NULL DEFAULT now());
ALTER TABLE tj_private.command_centre_refresh_queue ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj_private.command_centre_refresh_queue FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION tj_private.command_centre_rebuild(p_org uuid,p_actor uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE day date:=(now() AT TIME ZONE 'America/Toronto')::date; first_day date; period text; sid uuid; v_id uuid;
 crm jsonb; floor_data jsonb; training jsonb; sources jsonb; metrics jsonb; item record; row_metric record;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM tj.organizations WHERE id=p_org AND status='active' AND deleted_at IS NULL) THEN RAISE EXCEPTION 'organization_unavailable';END IF;
 IF p_actor IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.organization_members WHERE organization_id=p_org AND user_id=p_actor AND status='active' AND role IN('owner','admin')) THEN RAISE EXCEPTION 'administrator_required';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('command_centre_rebuild:'||p_org::text,0));
 first_day:=date_trunc('month',day)::date;period:=to_char(day,'YYYY-MM');
 -- Retain unsupported managed values as withheld evidence rather than exposing stale money/counts.
 UPDATE tj.metric_snapshots SET metric_subtype='command_centre_withheld' WHERE organization_id=p_org AND period_type='monthly' AND period_key=period AND metric_subtype='command_centre_live';
 SELECT jsonb_build_object('deals_total',count(*),'deals_won',count(*) FILTER(WHERE lower(stage) IN('closed won','won','sold','completed','purchased')),
 'deals_lost',count(*) FILTER(WHERE lower(stage) IN('closed lost','lost','cancelled','rejected','expired')),
 'open_deals',count(*) FILTER(WHERE closed_at IS NULL AND NOT coalesce(is_archived,false)),
 'pipeline_value_cad',NULL,'pricing_evidence','CRM deal currency is not recorded; monetary totals withheld',
 'closed_conversion_pct',round(100.0*count(*) FILTER(WHERE lower(stage) IN('closed won','won','sold','completed','purchased'))/nullif(count(*) FILTER(WHERE lower(stage) IN('closed won','won','sold','completed','purchased','closed lost','lost','cancelled','rejected','expired')),0),2))
 INTO crm FROM tj.crm_deals WHERE organization_id=p_org AND deleted_at IS NULL;
 SELECT jsonb_build_object('walk_ins',count(*),'interactions',count(*) FILTER(WHERE EXISTS(SELECT 1 FROM tj.iq_customer_interactions i WHERE i.organization_id=p_org AND i.customer_waiting_id=w.id)),
 'sales',count(*) FILTER(WHERE EXISTS(SELECT 1 FROM tj.iq_customer_interactions i WHERE i.organization_id=p_org AND i.customer_waiting_id=w.id AND i.outcome='sale' AND i.ended_at IS NOT NULL)),
 'left_unserved',count(*) FILTER(WHERE w.status='left_unserved'),
 'conversion_pct',round(100.0*count(*) FILTER(WHERE EXISTS(SELECT 1 FROM tj.iq_customer_interactions i WHERE i.organization_id=p_org AND i.customer_waiting_id=w.id AND i.outcome='sale' AND i.ended_at IS NOT NULL))/nullif(count(*),0),2),
 'served_score',round(100.0*count(*) FILTER(WHERE w.status<>'left_unserved')/nullif(count(*),0),2))
 INTO floor_data FROM tj.iq_customer_waiting_queue w WHERE w.organization_id=p_org AND (w.arrival_time AT TIME ZONE 'America/Toronto')::date BETWEEN first_day AND day;
 -- Served score counts actual interaction evidence, not still-waiting visitors.
 floor_data:=jsonb_set(floor_data,'{served_score}',coalesce(to_jsonb(round(100.0*(floor_data->>'interactions')::numeric/nullif((floor_data->>'walk_ins')::numeric,0),2)),'null'::jsonb));
 SELECT jsonb_build_object('average_knowledge_score',round(avg(100.0*q.score/nullif(q.total,0)) FILTER(WHERE q.total>0 AND q.score BETWEEN 0 AND q.total),2),'assessments',count(*) FILTER(WHERE q.total>0 AND q.score BETWEEN 0 AND q.total)) INTO training
 FROM tj.academy_quiz_scores q WHERE EXISTS(SELECT 1 FROM tj.organization_members m WHERE m.organization_id=p_org AND m.user_id=q.user_id AND m.status='active') AND (q.updated_at AT TIME ZONE 'America/Toronto')::date BETWEEN first_day AND day;
 sources:=jsonb_build_object(
 'crm',jsonb_build_object('latest_source_at',(SELECT max(updated_at) FROM tj.crm_deals WHERE organization_id=p_org AND deleted_at IS NULL),'scope','current pipeline; recorded closed outcomes'),
 'up',jsonb_build_object('latest_source_at',(SELECT max(arrival_time) FROM tj.iq_customer_waiting_queue WHERE organization_id=p_org),'scope','current month; distinct source visits'),
 'academy',jsonb_build_object('latest_source_at',(SELECT max(q.updated_at) FROM tj.academy_quiz_scores q WHERE EXISTS(SELECT 1 FROM tj.organization_members m WHERE m.organization_id=p_org AND m.user_id=q.user_id AND m.status='active')),'scope','current-month quizzes of active members; completion percentage not inferred'),
 'pos',jsonb_build_object('latest_source_at',(SELECT max(transaction_date) FROM tj.iq_pos_transactions WHERE organization_id=p_org),'records',(SELECT count(*) FROM tj.iq_pos_transactions WHERE organization_id=p_org),'scope','received POS records; no assumed currency or prices'),
 'pim',jsonb_build_object('latest_source_at',(SELECT max(updated_at) FROM tj.aiq_products WHERE organization_id=p_org),'records',(SELECT count(*) FROM tj.aiq_products WHERE organization_id=p_org),'scope','organization-owned catalog; ingestion date is not manufacturer verification'));
 metrics:=jsonb_build_object('crm',crm,'retail_floor',floor_data,'training',training,'sources',sources,'period_key',period,
 'field','{}'::jsonb,'learning','{}'::jsonb,'data_volume',jsonb_build_object('events',(SELECT count(*) FROM tj.intelligence_events WHERE organization_id=p_org),'outcomes',(SELECT count(*) FROM tj.intelligence_outcomes WHERE organization_id=p_org),'signals',(SELECT count(*) FROM tj.intelligence_learning_signals WHERE organization_id=p_org)));
 -- A composite health score needs validated evidence across its stated domains.
 INSERT INTO tj.executive_intelligence_snapshots(organization_id,snapshot_type,period_start,period_end,overall_health_score,health_status,metrics,evidence_summary,generated_by,data_confidence,coverage_status,generated_at)
 VALUES(p_org,'current',first_day,day,NULL,'unknown',metrics,jsonb_build_object('calculation','source counts and observed ratios; composite score withheld','source_dates',sources,'confidence_assessed',false,'missing_domains',jsonb_build_array('verified revenue/margin currency','field execution','coaching','complete training assignments')),p_actor,0,CASE WHEN (crm->>'deals_total')::int+(floor_data->>'walk_ins')::int+(training->>'assessments')::int>0 THEN 'partial' ELSE 'insufficient' END,clock_timestamp()) RETURNING id INTO v_id;
 -- Roll up current-month UP rows at organization/store scope. Preserve targets and other producers.
 FOR item IN SELECT x.organization_id,x.store_id,count(*) visits,count(*) FILTER(WHERE EXISTS(SELECT 1 FROM tj.iq_customer_interactions i WHERE i.organization_id=p_org AND i.customer_waiting_id=x.id AND i.outcome='sale' AND i.ended_at IS NOT NULL)) sales
 FROM tj.iq_customer_waiting_queue x WHERE x.organization_id=p_org AND (x.arrival_time AT TIME ZONE 'America/Toronto')::date BETWEEN first_day AND day GROUP BY GROUPING SETS((x.organization_id,x.store_id),(x.organization_id)) HAVING grouping(x.store_id)=1 OR x.store_id IS NOT NULL LOOP
  FOR row_metric IN SELECT * FROM (VALUES('walk_ins',item.visits::numeric),('floor_conversion',100.0*item.sales/nullif(item.visits,0))) v(key,val) WHERE val IS NOT NULL LOOP
   UPDATE tj.metric_snapshots SET metric_subtype='command_centre_live',actual_value=row_metric.val,computed_at=now(),variance_value=CASE WHEN target_value IS NOT NULL THEN row_metric.val-target_value END,variance_pct=CASE WHEN target_value<>0 THEN 100.0*(row_metric.val-target_value)/abs(target_value) END
   WHERE organization_id=p_org AND location_id IS NOT DISTINCT FROM item.store_id AND user_id IS NULL AND period_type='monthly' AND period_key=period AND metric_key=row_metric.key AND metric_subtype IN('command_centre_live','command_centre_withheld');
   IF NOT EXISTS(SELECT 1 FROM tj.metric_snapshots WHERE organization_id=p_org AND location_id IS NOT DISTINCT FROM item.store_id AND user_id IS NULL AND period_type='monthly' AND period_key=period AND metric_key=row_metric.key) THEN
    INSERT INTO tj.metric_snapshots(organization_id,location_id,period_type,period_key,metric_key,metric_subtype,actual_value) VALUES(p_org,item.store_id,'monthly',period,row_metric.key,'command_centre_live',row_metric.val);
   END IF;
  END LOOP;
 END LOOP;
 -- Monetary rollups require explicit CAD and complete recorded amounts in each scope.
 FOR item IN SELECT t.organization_id,t.store_id,sum(t.transaction_amount) revenue,count(*) transactions,
 bool_and(coalesce(t.currency_code='CAD',false) AND t.transaction_amount IS NOT NULL) priced,
 sum(t.gross_margin_amount) margin,bool_and(t.gross_margin_amount IS NOT NULL) margined
 FROM tj.iq_pos_transactions t WHERE t.organization_id=p_org AND (t.transaction_date AT TIME ZONE 'America/Toronto')::date BETWEEN first_day AND day
 GROUP BY GROUPING SETS((t.organization_id,t.store_id),(t.organization_id)) HAVING grouping(t.store_id)=1 OR t.store_id IS NOT NULL LOOP
  FOR row_metric IN SELECT * FROM (VALUES('transactions',item.transactions::numeric),('revenue',CASE WHEN item.priced THEN item.revenue END),('avg_order',CASE WHEN item.priced THEN item.revenue/nullif(item.transactions,0) END),('margin_dollars',CASE WHEN item.priced AND item.margined THEN item.margin END),('margin_pct',CASE WHEN item.priced AND item.margined THEN 100.0*item.margin/nullif(item.revenue,0) END)) v(key,val) WHERE val IS NOT NULL LOOP
   UPDATE tj.metric_snapshots SET metric_subtype='command_centre_live',actual_value=row_metric.val,computed_at=now(),variance_value=CASE WHEN target_value IS NOT NULL THEN row_metric.val-target_value END,variance_pct=CASE WHEN target_value<>0 THEN 100.0*(row_metric.val-target_value)/abs(target_value) END
   WHERE organization_id=p_org AND location_id IS NOT DISTINCT FROM item.store_id AND user_id IS NULL AND period_type='monthly' AND period_key=period AND metric_key=row_metric.key AND metric_subtype IN('command_centre_live','command_centre_withheld');
   IF NOT EXISTS(SELECT 1 FROM tj.metric_snapshots WHERE organization_id=p_org AND location_id IS NOT DISTINCT FROM item.store_id AND user_id IS NULL AND period_type='monthly' AND period_key=period AND metric_key=row_metric.key) THEN
    INSERT INTO tj.metric_snapshots(organization_id,location_id,period_type,period_key,metric_key,metric_subtype,actual_value) VALUES(p_org,item.store_id,'monthly',period,row_metric.key,'command_centre_live',row_metric.val);
   END IF;
  END LOOP;
 END LOOP;
 RETURN v_id;
END $$;
REVOKE ALL ON FUNCTION tj_private.command_centre_rebuild(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION tj_private.executive_refresh_command_centre(p_organization_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=tj_private.current_source_user_id(); result uuid;
BEGIN
 PERFORM tj_private.assert_runtime_org(p_organization_id);
 IF NOT tj.is_org_admin(p_organization_id) THEN RAISE EXCEPTION 'admin_required' USING ERRCODE='42501';END IF;
 INSERT INTO tj_private.command_centre_refresh_queue(organization_id) VALUES(p_organization_id) ON CONFLICT DO NOTHING;
 PERFORM 1 FROM tj_private.command_centre_refresh_queue WHERE organization_id=p_organization_id FOR UPDATE;
 result:=tj_private.command_centre_rebuild(p_organization_id,actor);
 UPDATE tj_private.command_centre_refresh_queue SET processed_at=clock_timestamp(),last_error=NULL,attempts=0 WHERE organization_id=p_organization_id;
 RETURN result;
END $$;

CREATE FUNCTION tj_private.command_centre_enqueue() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE org uuid; u uuid;
BEGIN
 IF TG_TABLE_NAME IN('academy_quiz_scores','academy_progress','academy_track_progress') THEN
  u:=NEW.user_id;
  INSERT INTO tj_private.command_centre_refresh_queue(organization_id,requested_at,next_attempt_at)
  SELECT DISTINCT organization_id,clock_timestamp(),clock_timestamp() FROM tj.organization_members WHERE user_id=u AND status='active'
  ON CONFLICT(organization_id) DO UPDATE SET requested_at=excluded.requested_at,next_attempt_at=excluded.next_attempt_at;
 ELSE
  org:=NEW.organization_id;
  IF org IS NOT NULL THEN INSERT INTO tj_private.command_centre_refresh_queue(organization_id) VALUES(org)
  ON CONFLICT(organization_id) DO UPDATE SET requested_at=clock_timestamp(),next_attempt_at=now();END IF;
 END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION tj_private.command_centre_enqueue() FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj_private.command_centre_refresh_worker(p_limit integer DEFAULT 10) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE q record; done int:=0; failed int:=0;
BEGIN
 FOR q IN SELECT r.organization_id FROM tj_private.command_centre_refresh_queue r JOIN tj.organizations o ON o.id=r.organization_id AND o.status='active' AND o.deleted_at IS NULL
 WHERE (r.processed_at IS NULL OR r.requested_at>r.processed_at OR r.processed_at<date_trunc('day',now())) AND r.next_attempt_at<=now()
 ORDER BY r.processed_at NULLS FIRST,r.requested_at LIMIT greatest(1,least(coalesce(p_limit,10),20)) FOR UPDATE OF r SKIP LOCKED LOOP
  BEGIN
   PERFORM tj_private.command_centre_rebuild(q.organization_id,NULL);
   UPDATE tj_private.command_centre_refresh_queue SET processed_at=clock_timestamp(),last_error=NULL,attempts=0 WHERE organization_id=q.organization_id;done:=done+1;
  EXCEPTION WHEN OTHERS THEN
   UPDATE tj_private.command_centre_refresh_queue SET attempts=attempts+1,last_error=SQLSTATE,next_attempt_at=now()+interval '10 minutes' WHERE organization_id=q.organization_id;failed:=failed+1;
  END;
 END LOOP;
 RETURN jsonb_build_object('processed',done,'failed',failed);
END $$;
REVOKE ALL ON FUNCTION tj_private.command_centre_refresh_worker(integer) FROM PUBLIC,anon,authenticated,service_role;

CREATE TRIGGER command_centre_refresh AFTER INSERT OR UPDATE ON tj.crm_deals FOR EACH ROW EXECUTE FUNCTION tj_private.command_centre_enqueue();
CREATE TRIGGER command_centre_refresh AFTER INSERT OR UPDATE ON tj.iq_customer_waiting_queue FOR EACH ROW EXECUTE FUNCTION tj_private.command_centre_enqueue();
CREATE TRIGGER command_centre_refresh AFTER INSERT OR UPDATE ON tj.iq_customer_interactions FOR EACH ROW EXECUTE FUNCTION tj_private.command_centre_enqueue();
CREATE TRIGGER command_centre_refresh AFTER INSERT OR UPDATE ON tj.iq_pos_transactions FOR EACH ROW EXECUTE FUNCTION tj_private.command_centre_enqueue();
CREATE TRIGGER command_centre_refresh AFTER INSERT OR UPDATE ON tj.aiq_products FOR EACH ROW EXECUTE FUNCTION tj_private.command_centre_enqueue();
CREATE TRIGGER command_centre_refresh AFTER INSERT OR UPDATE ON tj.academy_quiz_scores FOR EACH ROW EXECUTE FUNCTION tj_private.command_centre_enqueue();
CREATE TRIGGER command_centre_refresh AFTER INSERT OR UPDATE ON tj.academy_progress FOR EACH ROW EXECUTE FUNCTION tj_private.command_centre_enqueue();
CREATE TRIGGER command_centre_refresh AFTER INSERT OR UPDATE ON tj.academy_track_progress FOR EACH ROW EXECUTE FUNCTION tj_private.command_centre_enqueue();
INSERT INTO tj_private.command_centre_refresh_queue(organization_id)
SELECT DISTINCT m.organization_id FROM tj.organization_members m JOIN tj.source_user_identity_map i ON i.source_user_id=m.user_id AND i.activation_status='activated'
JOIN tj.organizations o ON o.id=m.organization_id AND o.status='active' AND o.deleted_at IS NULL WHERE m.status='active' ON CONFLICT DO NOTHING;
SELECT cron.schedule('aiq-command-centre-evidence-refresh','*/5 * * * *','SELECT tj_private.command_centre_refresh_worker(10);');
NOTIFY pgrst,'reload schema';
CREATE OR REPLACE FUNCTION tj_private.executive_get_command_centre(p_organization_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$ BEGIN PERFORM tj_private.assert_runtime_org(p_organization_id); IF NOT tj.is_org_admin(p_organization_id) THEN RAISE EXCEPTION 'admin_required' USING ERRCODE='42501';END IF; RETURN (with latest as (
  select * from executive_intelligence_snapshots
  where organization_id=p_organization_id
  order by generated_at desc limit 1
)
select jsonb_build_object(
  'snapshot',coalesce((select to_jsonb(l) from latest l),'{}'::jsonb),
  'top_risks',coalesce((select jsonb_agg(to_jsonb(i) order by i.priority_score desc,i.created_at desc) from (select * from executive_intelligence_insights where organization_id=p_organization_id and snapshot_id=(select id from latest) and status in ('open','acknowledged','in_progress') and insight_type='risk' order by priority_score desc,created_at desc limit 10) i),'[]'::jsonb),
  'top_opportunities',coalesce((select jsonb_agg(to_jsonb(i) order by i.priority_score desc,i.created_at desc) from (select * from executive_intelligence_insights where organization_id=p_organization_id and snapshot_id=(select id from latest) and status in ('open','acknowledged','in_progress') and insight_type='opportunity' order by priority_score desc,created_at desc limit 10) i),'[]'::jsonb),
  'priority_actions',coalesce((select jsonb_agg(to_jsonb(i) order by i.priority_score desc,i.created_at desc) from (select * from executive_intelligence_insights where organization_id=p_organization_id and snapshot_id=(select id from latest) and status in ('open','acknowledged','in_progress') and insight_type in ('action','performance') order by priority_score desc,created_at desc limit 10) i),'[]'::jsonb),
  'generated_at',now()
)); END $function$
;

-- Retained withheld rows are excluded from application reads.
CREATE POLICY command_centre_withheld_read_guard ON tj.metric_snapshots AS RESTRICTIVE FOR SELECT TO authenticated USING (metric_subtype IS DISTINCT FROM 'command_centre_withheld');
CREATE OR REPLACE FUNCTION tj_private.compute_iq_score(p_org_id uuid, p_period text DEFAULT NULL::text, p_location_id uuid DEFAULT NULL::uuid, p_user_id uuid DEFAULT NULL::uuid)
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
  p_period:=coalesce(p_period,to_char(now() AT TIME ZONE 'America/Toronto','YYYY-MM'));

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
    AND to_char(ca.started_at AT TIME ZONE 'America/Toronto','YYYY-MM')=p_period
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
        AND ms.metric_subtype IS DISTINCT FROM 'command_centre_withheld'
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
        v_actual := NULL;
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
CREATE OR REPLACE FUNCTION tj.compute_iq_score(p_org_id uuid,p_period text DEFAULT NULL,p_location_id uuid DEFAULT NULL,p_user_id uuid DEFAULT NULL) RETURNS TABLE(metric_key text,metric_label text,max_points numeric,actual_value numeric,target_value numeric,pct_of_target numeric,earned_points numeric,sort_order integer) LANGUAGE sql SET search_path='' AS $$SELECT * FROM tj_private.compute_iq_score(p_org_id,p_period,p_location_id,p_user_id);$$;
