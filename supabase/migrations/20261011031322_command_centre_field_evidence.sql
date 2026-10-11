CREATE FUNCTION tj_private.command_centre_field_evidence(p_org uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
WITH visits AS (
 SELECT v.* FROM tj.field_visits v JOIN tj.field_clients c ON c.id=v.client_id WHERE c.organization_id=p_org
), findings AS (
 SELECT f.* FROM tj.field_findings f JOIN visits v ON v.id=f.visit_id AND v.client_id=f.client_id AND v.store_id=f.store_id
), actions AS (
 SELECT a.* FROM tj.field_actions a JOIN findings f ON f.id=a.finding_id AND f.visit_id=a.visit_id AND f.client_id=a.client_id AND f.store_id=a.store_id
), scored AS (
 SELECT s.* FROM tj.field_store_scores s JOIN visits v ON v.id=s.visit_id AND v.client_id=s.client_id AND v.store_id=s.store_id
 WHERE v.status='completed' AND s.overall_score BETWEEN 0 AND 100
), latest_scores AS (
 SELECT DISTINCT ON(client_id,store_id) * FROM scored ORDER BY client_id,store_id,score_date DESC,created_at DESC NULLS LAST,id DESC
), counts AS (
 SELECT (SELECT count(*) FROM findings WHERE severity='critical' AND coalesce(status,'new') NOT IN('resolved','closed','rejected')) critical,
 (SELECT count(*) FROM actions WHERE status NOT IN('resolved','closed','rejected')) open_actions,
 (SELECT count(*) FROM actions WHERE status IN('resolved','closed')) resolved_actions,
 (SELECT count(*) FROM actions WHERE status IS NULL) unknown_actions,
 (SELECT count(*) FROM actions WHERE status NOT IN('resolved','closed','rejected') AND due_date<(now() AT TIME ZONE 'America/Toronto')::date) overdue_actions
), dates AS (
 SELECT greatest((SELECT max(updated_at) FROM visits),(SELECT max(updated_at) FROM findings),(SELECT max(updated_at) FROM actions),(SELECT max(created_at) FROM scored)) source_at
)
SELECT jsonb_build_object(
 'visits_total',(SELECT count(*) FROM visits),'completed_visits',(SELECT count(*) FROM visits WHERE status='completed'),
 'visits_this_month',(SELECT count(*) FROM visits WHERE visit_date BETWEEN date_trunc('month',now() AT TIME ZONE 'America/Toronto')::date AND (now() AT TIME ZONE 'America/Toronto')::date),
 'critical_open_findings',critical,'open_actions',open_actions,'resolved_actions',resolved_actions,'unknown_status_actions',unknown_actions,'overdue_actions',overdue_actions,
 'resolution_pct',round(100.0*resolved_actions/nullif(open_actions+resolved_actions,0),2),
 'resolution_basis','Recorded resolved/closed statuses among known non-rejected actions; verification is not inferred',
 'average_store_score',(SELECT round(avg(overall_score),2) FROM latest_scores),'scored_stores',(SELECT count(*) FROM latest_scores),
 'score_basis','Latest recorded 0–100 checklist score per client/store from a completed visit; original inspection dates retained',
 'latest_score_date',(SELECT max(score_date) FROM latest_scores),'latest_visit_date',(SELECT max(visit_date) FROM visits),
 'source',jsonb_build_object('latest_source_at',source_at,'latest_inspection_date',(SELECT max(visit_date) FROM visits),'scope','Organization-owned field visits; current unresolved workflow and latest completed checklist per client/store'),
 'risks',CASE WHEN critical>0 THEN jsonb_build_array(jsonb_build_object('insight_type','risk','domain','field','severity','critical','priority_score',100,'title','Recorded critical field findings remain unresolved','summary',format('%s critical finding(s) remain unresolved in received field records.',critical),'recommended_action','Review the recorded finding dates, assign owners and verify resolution evidence.','evidence',jsonb_build_object('critical_open_findings',critical,'latest_source_at',source_at))) ELSE '[]'::jsonb END,
 'priority_actions',coalesce((SELECT jsonb_agg(x.payload ORDER BY x.rank DESC,x.due_date NULLS LAST,x.updated_at DESC) FROM (
 SELECT jsonb_build_object('id',a.id,'insight_type','action','domain','field','severity',CASE WHEN a.priority IN('critical','high','low') THEN a.priority ELSE 'info' END,'title',a.title,'summary',format('Recorded status: %s. Due: %s. Last source update: %s.',a.status,coalesce(a.due_date::text,'not recorded'),coalesce(a.updated_at::text,'not recorded')),'recommended_action',coalesce(nullif(a.description,''),'Review this recorded field action and confirm its owner and next step.'),'evidence',jsonb_build_object('action_id',a.id,'finding_id',a.finding_id,'visit_id',a.visit_id,'store_id',a.store_id,'status',a.status,'due_date',a.due_date,'source_updated_at',a.updated_at)) payload,
 CASE a.priority WHEN 'critical' THEN 100 WHEN 'high' THEN 80 WHEN 'low' THEN 25 ELSE 50 END rank,a.due_date,a.updated_at
 FROM actions a WHERE a.status NOT IN('resolved','closed','rejected') ORDER BY rank DESC,a.due_date NULLS LAST,a.updated_at DESC LIMIT 10
 ) x),'[]'::jsonb)) FROM counts CROSS JOIN dates;
$$;
REVOKE ALL ON FUNCTION tj_private.command_centre_field_evidence(uuid) FROM PUBLIC,anon,authenticated,service_role;
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
  'top_risks',coalesce((select l.metrics#>'{field,risks}' from latest l),'[]'::jsonb)||coalesce((select jsonb_agg(to_jsonb(i) order by i.priority_score desc,i.created_at desc) from (select * from executive_intelligence_insights where organization_id=p_organization_id and snapshot_id=(select id from latest) and status in ('open','acknowledged','in_progress') and insight_type='risk' order by priority_score desc,created_at desc limit 10) i),'[]'::jsonb),
  'top_opportunities',coalesce((select jsonb_agg(to_jsonb(i) order by i.priority_score desc,i.created_at desc) from (select * from executive_intelligence_insights where organization_id=p_organization_id and snapshot_id=(select id from latest) and status in ('open','acknowledged','in_progress') and insight_type='opportunity' order by priority_score desc,created_at desc limit 10) i),'[]'::jsonb),
  'priority_actions',coalesce((select l.metrics#>'{field,priority_actions}' from latest l),'[]'::jsonb)||coalesce((select jsonb_agg(to_jsonb(i) order by i.priority_score desc,i.created_at desc) from (select * from executive_intelligence_insights where organization_id=p_organization_id and snapshot_id=(select id from latest) and status in ('open','acknowledged','in_progress') and insight_type in ('action','performance') order by priority_score desc,created_at desc limit 10) i),'[]'::jsonb),
  'generated_at',now()
)); END $function$;

CREATE FUNCTION tj_private.command_centre_field_enqueue() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE old_org uuid; new_org uuid;
BEGIN
 IF TG_TABLE_NAME='field_clients' THEN
  new_org:=NEW.organization_id; IF TG_OP='UPDATE' THEN old_org:=OLD.organization_id; END IF;
 ELSE
  SELECT organization_id INTO new_org FROM tj.field_clients WHERE id=NEW.client_id;
  IF TG_OP='UPDATE' THEN SELECT organization_id INTO old_org FROM tj.field_clients WHERE id=OLD.client_id; END IF;
 END IF;
 INSERT INTO tj_private.command_centre_refresh_queue(organization_id,requested_at,next_attempt_at)
 SELECT x.org,clock_timestamp(),clock_timestamp() FROM (SELECT DISTINCT org FROM (VALUES(old_org),(new_org)) v(org) WHERE org IS NOT NULL) x
 ON CONFLICT(organization_id) DO UPDATE SET requested_at=excluded.requested_at,next_attempt_at=excluded.next_attempt_at;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION tj_private.command_centre_field_enqueue() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER command_centre_field_refresh AFTER INSERT OR UPDATE ON tj.field_clients FOR EACH ROW EXECUTE FUNCTION tj_private.command_centre_field_enqueue();
CREATE TRIGGER command_centre_field_refresh AFTER INSERT OR UPDATE ON tj.field_visits FOR EACH ROW EXECUTE FUNCTION tj_private.command_centre_field_enqueue();
CREATE TRIGGER command_centre_field_refresh AFTER INSERT OR UPDATE ON tj.field_findings FOR EACH ROW EXECUTE FUNCTION tj_private.command_centre_field_enqueue();
CREATE TRIGGER command_centre_field_refresh AFTER INSERT OR UPDATE ON tj.field_actions FOR EACH ROW EXECUTE FUNCTION tj_private.command_centre_field_enqueue();
CREATE TRIGGER command_centre_field_refresh AFTER INSERT OR UPDATE ON tj.field_store_scores FOR EACH ROW EXECUTE FUNCTION tj_private.command_centre_field_enqueue();
-- Existing native organizations receive the field evidence on the next bounded worker run.
UPDATE tj_private.command_centre_refresh_queue SET requested_at=clock_timestamp(),next_attempt_at=clock_timestamp();
NOTIFY pgrst,'reload schema';
CREATE OR REPLACE FUNCTION tj_private.command_centre_rebuild(p_org uuid, p_actor uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE day date:=(now() AT TIME ZONE 'America/Toronto')::date; first_day date; period text; sid uuid; v_id uuid;
 crm jsonb; floor_data jsonb; training jsonb; sources jsonb; metrics jsonb; field_data jsonb; item record; row_metric record;
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
 field_data:=tj_private.command_centre_field_evidence(p_org);
 sources:=sources||jsonb_build_object('field',field_data->'source');
 metrics:=jsonb_build_object('crm',crm,'retail_floor',floor_data,'training',training,'sources',sources,'period_key',period,
 'field',field_data,'learning','{}'::jsonb,'data_volume',jsonb_build_object('events',(SELECT count(*) FROM tj.intelligence_events WHERE organization_id=p_org),'outcomes',(SELECT count(*) FROM tj.intelligence_outcomes WHERE organization_id=p_org),'signals',(SELECT count(*) FROM tj.intelligence_learning_signals WHERE organization_id=p_org)));
 -- A composite health score needs validated evidence across its stated domains.
 INSERT INTO tj.executive_intelligence_snapshots(organization_id,snapshot_type,period_start,period_end,overall_health_score,health_status,metrics,evidence_summary,generated_by,data_confidence,coverage_status,generated_at)
 VALUES(p_org,'current',first_day,day,NULL,'unknown',metrics,jsonb_build_object('calculation','source counts and observed ratios; composite score withheld','source_dates',sources,'confidence_assessed',false,'missing_domains',jsonb_build_array('verified revenue/margin currency','coaching','complete training assignments')),p_actor,0,CASE WHEN (crm->>'deals_total')::int+(floor_data->>'walk_ins')::int+(training->>'assessments')::int>0 THEN 'partial' ELSE 'insufficient' END,clock_timestamp()) RETURNING id INTO v_id;
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
END $function$;
