CREATE FUNCTION tj_private.command_centre_academy_evidence(p_org uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
WITH members AS (SELECT DISTINCT user_id FROM tj.organization_members WHERE organization_id=p_org AND status='active'),
 lessons AS (SELECT p.* FROM tj.academy_progress p JOIN members m USING(user_id)),
 tracks AS (SELECT p.* FROM tj.academy_track_progress p JOIN members m USING(user_id)),
 quizzes AS (SELECT q.* FROM tj.academy_quiz_scores q JOIN members m USING(user_id)),
 dates AS (SELECT greatest((SELECT max(completed_at) FROM lessons),(SELECT max(greatest(started_at,completed_at)) FROM tracks),(SELECT max(updated_at) FROM quizzes)) source_at)
SELECT jsonb_build_object('active_members',(SELECT count(*) FROM members),'lesson_records',(SELECT count(*) FROM lessons),'track_records',(SELECT count(*) FROM tracks),
 'lesson_completions',CASE WHEN EXISTS(SELECT 1 FROM lessons) THEN (SELECT count(DISTINCT(user_id,chapter_id)) FROM lessons WHERE completed_at IS NOT NULL) END,
 'lesson_completions_this_month',CASE WHEN EXISTS(SELECT 1 FROM lessons) THEN (SELECT count(DISTINCT(user_id,chapter_id)) FROM lessons WHERE (completed_at AT TIME ZONE 'America/Toronto')::date BETWEEN date_trunc('month',now() AT TIME ZONE 'America/Toronto')::date AND (now() AT TIME ZONE 'America/Toronto')::date) END,
 'completed_tracks',CASE WHEN EXISTS(SELECT 1 FROM tracks) THEN (SELECT count(DISTINCT(user_id,track_key)) FROM tracks WHERE completed_at IS NOT NULL) END,
 'started_uncompleted_tracks',CASE WHEN EXISTS(SELECT 1 FROM tracks) THEN (SELECT count(DISTINCT(user_id,track_key)) FROM tracks WHERE started_at IS NOT NULL AND completed_at IS NULL) END,
 'completion_pct',NULL,'completion_basis','Recorded lesson/track counts of active organization members; assignment denominator is not recorded, so completion percentage is unknown',
 'source',jsonb_build_object('latest_source_at',source_at,'scope','Active-member dated quizzes, lesson completions and track starts/completions; absent progress is unknown')) FROM dates;
$$;
REVOKE ALL ON FUNCTION tj_private.command_centre_academy_evidence(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION tj_private.command_centre_integration_evidence(p_org uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
SELECT jsonb_build_object('connections',coalesce(jsonb_agg(jsonb_build_object('id',c.id,'provider',p.name,'catalog_status',p.status,'connection_status',c.status,'authentication',c.auth_status,
 'last_sync_at',c.last_sync_at,'last_recorded_success_at',c.last_success_at,'recorded_initial_sync_at',c.initial_sync_completed_at,'has_connection_error',c.last_error IS NOT NULL,
 'completed_successful_jobs',(SELECT count(*) FROM tj.platform_sync_jobs j WHERE j.connection_id=c.id AND j.status='success' AND j.completed_at IS NOT NULL),
 'last_completed_success_at',(SELECT max(completed_at) FROM tj.platform_sync_jobs j WHERE j.connection_id=c.id AND j.status='success' AND j.completed_at IS NOT NULL),
 'job_status_counts',coalesce((SELECT jsonb_object_agg(x.status,x.n) FROM (SELECT j.status,count(*) n FROM tj.platform_sync_jobs j WHERE j.connection_id=c.id GROUP BY j.status) x),'{}'::jsonb),
 'received_pos_transactions',(SELECT count(*) FROM tj.iq_pos_transactions t WHERE t.organization_id=p_org AND t.source_connection_id=c.id),
 'latest_received_pos_at',(SELECT max(synced_at) FROM tj.iq_pos_transactions t WHERE t.organization_id=p_org AND t.source_connection_id=c.id)
 ) ORDER BY p.name,c.id),'[]'::jsonb),'basis','Connection/authentication state, recorded completed job statuses and received POS rows are separate evidence. Catalog active/beta or cron dispatch does not establish a completed import; other imported data domains are not certified by POS counts.')
FROM tj.platform_connector_connections c JOIN tj.platform_connectors p ON p.id=c.connector_id WHERE c.organization_id=p_org;
$$;
REVOKE ALL ON FUNCTION tj_private.command_centre_integration_evidence(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION tj_private.command_centre_activity_enqueue() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE old_org uuid;new_org uuid;
BEGIN
 IF TG_TABLE_NAME='platform_sync_jobs' THEN
  SELECT organization_id INTO new_org FROM tj.platform_connector_connections WHERE id=NEW.connection_id;
  IF TG_OP='UPDATE' THEN SELECT organization_id INTO old_org FROM tj.platform_connector_connections WHERE id=OLD.connection_id;END IF;
 ELSE new_org:=NEW.organization_id; IF TG_OP='UPDATE' THEN old_org:=OLD.organization_id;END IF;
 END IF;
 INSERT INTO tj_private.command_centre_refresh_queue(organization_id,requested_at,next_attempt_at)
 SELECT org,clock_timestamp(),clock_timestamp() FROM (SELECT DISTINCT org FROM (VALUES(old_org),(new_org)) x(org) WHERE org IS NOT NULL) s
 ON CONFLICT(organization_id) DO UPDATE SET requested_at=excluded.requested_at,next_attempt_at=excluded.next_attempt_at;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION tj_private.command_centre_activity_enqueue() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER command_centre_activity_refresh AFTER INSERT OR UPDATE ON tj.organization_members FOR EACH ROW EXECUTE FUNCTION tj_private.command_centre_activity_enqueue();
CREATE TRIGGER command_centre_activity_refresh AFTER INSERT OR UPDATE ON tj.platform_connector_connections FOR EACH ROW EXECUTE FUNCTION tj_private.command_centre_activity_enqueue();
CREATE TRIGGER command_centre_activity_refresh AFTER INSERT OR UPDATE ON tj.platform_sync_jobs FOR EACH ROW EXECUTE FUNCTION tj_private.command_centre_activity_enqueue();
UPDATE tj_private.command_centre_refresh_queue SET requested_at=clock_timestamp(),next_attempt_at=clock_timestamp();
NOTIFY pgrst,'reload schema';
CREATE OR REPLACE FUNCTION tj_private.command_centre_rebuild(p_org uuid, p_actor uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE day date:=(now() AT TIME ZONE 'America/Toronto')::date; first_day date; period text; sid uuid; v_id uuid;
 crm jsonb; floor_data jsonb; training jsonb; sources jsonb; metrics jsonb; field_data jsonb; academy_data jsonb; item record; row_metric record;
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
 academy_data:=tj_private.command_centre_academy_evidence(p_org);
 training:=training||(academy_data-'source');
 sources:=sources||jsonb_build_object('academy',academy_data->'source');
 field_data:=tj_private.command_centre_field_evidence(p_org);
 sources:=sources||jsonb_build_object('field',field_data->'source');
 metrics:=jsonb_build_object('crm',crm,'retail_floor',floor_data,'training',training,'integrations',tj_private.command_centre_integration_evidence(p_org),'sources',sources,'period_key',period,
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
