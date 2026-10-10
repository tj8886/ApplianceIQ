-- Tenant-scoped metadata and atomic operator actions; no external connector execution.
CREATE OR REPLACE FUNCTION tj_private.connector_diagnostics(p_body jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=tj_private.current_source_user_id(); action text:=coalesce(p_body->>'action','summary'); org uuid; role_name text; cid uuid; qid uuid; aid uuid; months int; since timestamptz;
 c tj.platform_connector_connections%rowtype;v_quarantine tj.platform_connector_quarantine%rowtype; rows_json jsonb;alerts_json jsonb;result jsonb;incidents_json jsonb;
BEGIN
 IF actor IS NULL THEN RAISE EXCEPTION 'access_denied' USING ERRCODE='42501';END IF;
 IF jsonb_typeof(p_body) IS DISTINCT FROM 'object' OR octet_length(p_body::text)>8192 THEN RAISE EXCEPTION 'invalid_body' USING ERRCODE='22023';END IF;
 IF action IN ('org_summary','org_reliability') THEN org:=nullif(p_body->>'organization_id','')::uuid;
 ELSE cid:=nullif(p_body->>'connection_id','')::uuid;SELECT * INTO c FROM tj.platform_connector_connections WHERE id=cid;org:=c.organization_id;END IF;
 SELECT m.role INTO role_name FROM tj.organization_members m JOIN tj.organizations o ON o.id=m.organization_id WHERE m.organization_id=org AND m.user_id=actor AND m.status='active' AND o.status='active' AND o.deleted_at IS NULL;
 IF role_name IS NULL OR role_name NOT IN ('owner','admin','super_admin','manager') OR (action NOT IN ('org_summary','org_reliability') AND role_name='manager') THEN RAISE EXCEPTION 'access_denied' USING ERRCODE='42501';END IF;
 IF action='org_reliability' THEN
  months:=coalesce((p_body->>'months')::int,12);IF months<1 OR months>24 THEN RAISE EXCEPTION 'invalid_months' USING ERRCODE='22023';END IF;
  since:=date_trunc('month',now())-make_interval(months=>months-1);
  SELECT coalesce(jsonb_agg(x ORDER BY x.report_month DESC),'[]'::jsonb) INTO rows_json FROM tj.platform_connector_monthly_reliability x WHERE x.organization_id=org AND x.report_month>=since;
  SELECT coalesce(jsonb_agg(to_jsonb(x)-'fingerprint'-'organization_id'-'updated_at'),'[]'::jsonb) INTO incidents_json FROM (SELECT i.* FROM tj.platform_connector_incident_metrics i JOIN tj.platform_connector_connections pc ON pc.id=i.connection_id WHERE i.organization_id=org AND pc.organization_id=org AND i.detected_at>=since ORDER BY i.detected_at DESC LIMIT 500) x;
  WITH r AS (SELECT * FROM tj.platform_connector_monthly_reliability WHERE organization_id=org AND report_month>=since),agg AS (SELECT connection_id,display_name,jsonb_agg(r ORDER BY report_month DESC) months,round(avg(avg_health_score),2) avg_health_score,round(avg(healthy_sample_pct),2) healthy_sample_pct,sum(incidents) incidents,sum(critical_incidents) critical_incidents,sum(repeat_incidents) repeat_incidents FROM r GROUP BY connection_id,display_name)
  SELECT coalesce(jsonb_agg(agg),'[]'::jsonb) INTO rows_json FROM agg;
  WITH ii AS (SELECT * FROM jsonb_to_recordset(incidents_json) AS x(severity text,occurrence_number int,acknowledged_at timestamptz,resolved_at timestamptz,time_to_ack_minutes numeric,time_to_resolve_minutes numeric,ack_sla_met boolean,resolve_sla_met boolean))
  SELECT jsonb_build_object('connections',jsonb_array_length(rows_json),'incidents',count(*),'critical_incidents',count(*) FILTER(WHERE severity='critical'),'repeat_incidents',count(*) FILTER(WHERE occurrence_number>1),'avg_time_to_ack_minutes',round(avg(time_to_ack_minutes) FILTER(WHERE acknowledged_at IS NOT NULL),2),'avg_time_to_resolve_minutes',round(avg(time_to_resolve_minutes) FILTER(WHERE resolved_at IS NOT NULL),2),'ack_sla_pct',round(100.0*count(*) FILTER(WHERE ack_sla_met)/nullif(count(ack_sla_met) FILTER(WHERE acknowledged_at IS NOT NULL),0),2),'resolve_sla_pct',round(100.0*count(*) FILTER(WHERE resolve_sla_met)/nullif(count(resolve_sla_met) FILTER(WHERE resolved_at IS NOT NULL),0),2)) INTO result FROM ii;
  RETURN jsonb_build_object('ok',true,'organization_id',org,'period_months',months,'summary',result,'connectors',rows_json,'incidents',(SELECT coalesce(jsonb_agg(x),'[]'::jsonb) FROM (SELECT value x FROM jsonb_array_elements(incidents_json) LIMIT 100) z));
 ELSIF action='org_summary' THEN
  SELECT coalesce(jsonb_agg(row_data ORDER BY created_at DESC),'[]'::jsonb) INTO rows_json FROM (
   SELECT pc.created_at,jsonb_build_object('id',pc.id,'display_name',pc.display_name,'status',pc.status,'auth_status',pc.auth_status,'last_sync_at',pc.last_sync_at,'last_success_at',pc.last_success_at,'connector_id',pc.connector_id,'platform_connectors',jsonb_build_object('key',co.key,'name',co.name),
    'health',(SELECT to_jsonb(h)-'details' FROM tj.platform_connector_health_snapshots h WHERE h.connection_id=pc.id ORDER BY h.captured_at DESC LIMIT 1),
    'open_alerts',(SELECT count(*) FROM tj.platform_connector_alerts a WHERE a.connection_id=pc.id AND a.status='open'),
    'critical_alerts',(SELECT count(*) FROM tj.platform_connector_alerts a WHERE a.connection_id=pc.id AND a.status='open' AND a.severity='critical'),
    'quarantine_count',(SELECT count(*) FROM tj.platform_connector_quarantine q WHERE q.connection_id=pc.id AND q.status IN ('quarantined','retrying','dead_letter')),
    'unresolved_matches',(SELECT count(*) FROM tj.platform_connector_match_queue m WHERE m.connection_id=pc.id AND m.status IN ('pending','review')),
    'latest_reconciliation',(SELECT to_jsonb(r)-'discrepancies' FROM tj.platform_connector_reconciliation_runs r WHERE r.connection_id=pc.id ORDER BY r.started_at DESC LIMIT 1)) row_data
   FROM tj.platform_connector_connections pc JOIN tj.platform_connectors co ON co.id=pc.connector_id WHERE pc.organization_id=org) z;
  SELECT coalesce(jsonb_agg(to_jsonb(a)-'details'-'message'-'fingerprint'),'[]'::jsonb) INTO alerts_json FROM (SELECT a.* FROM tj.platform_connector_alerts a JOIN tj.platform_connector_connections pc ON pc.id=a.connection_id WHERE pc.organization_id=org AND a.status IN ('open','acknowledged') ORDER BY a.last_seen_at DESC LIMIT 100) a;
  SELECT jsonb_build_object('connections',count(*),'overall_health_score',round(avg(nullif(x#>>'{health,health_score}','')::numeric)),'open_alerts',coalesce(sum((x->>'open_alerts')::int),0),'critical_alerts',coalesce(sum((x->>'critical_alerts')::int),0),'quarantined',coalesce(sum((x->>'quarantine_count')::int),0),'unresolved_matches',coalesce(sum((x->>'unresolved_matches')::int),0)) INTO result FROM jsonb_array_elements(rows_json) x;
  RETURN jsonb_build_object('ok',true,'organization_id',org,'summary',result,'connections',rows_json,'alerts',alerts_json);
 ELSIF action='summary' THEN
  RETURN jsonb_build_object('ok',true,'connection',jsonb_build_object('id',c.id,'organization_id',org,'connector_id',c.connector_id,'status',c.status,'auth_status',c.auth_status,'last_sync_at',c.last_sync_at,'last_success_at',c.last_success_at,'display_name',c.display_name,'platform_connectors',(SELECT jsonb_build_object('key',key,'name',name) FROM tj.platform_connectors WHERE id=c.connector_id)),
   'health',(SELECT to_jsonb(h)-'details' FROM tj.platform_connector_health_snapshots h WHERE h.connection_id=cid ORDER BY captured_at DESC LIMIT 1),
   'jobs',(SELECT coalesce(jsonb_agg(to_jsonb(j)-'cursor'-'stats'-'error_details'-'health_metadata'),'[]'::jsonb) FROM (SELECT * FROM tj.platform_sync_jobs WHERE connection_id=cid ORDER BY created_at DESC LIMIT 25) j),
   'quarantine',(SELECT coalesce(jsonb_agg(to_jsonb(q)-'payload'-'error_message'-'resolution'),'[]'::jsonb) FROM (SELECT * FROM tj.platform_connector_quarantine WHERE connection_id=cid ORDER BY last_seen_at DESC LIMIT 100) q),
   'reconciliation',(SELECT coalesce(jsonb_agg(to_jsonb(r)-'discrepancies'),'[]'::jsonb) FROM (SELECT * FROM tj.platform_connector_reconciliation_runs WHERE connection_id=cid ORDER BY started_at DESC LIMIT 10) r),
   'alerts',(SELECT coalesce(jsonb_agg(to_jsonb(a)-'details'-'message'-'fingerprint'),'[]'::jsonb) FROM (SELECT * FROM tj.platform_connector_alerts WHERE connection_id=cid ORDER BY last_seen_at DESC LIMIT 100) a),
   'unresolved_matches',(SELECT count(*) FROM tj.platform_connector_match_queue WHERE connection_id=cid AND status IN ('pending','review')));
 END IF;
 PERFORM 1 FROM tj.platform_connector_connections WHERE id=cid AND organization_id=org FOR UPDATE;
 IF action IN ('retry','resolve','ignore') THEN
  qid:=nullif(p_body->>'quarantine_id','')::uuid;SELECT * INTO v_quarantine FROM tj.platform_connector_quarantine WHERE id=qid AND connection_id=cid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'quarantine_not_found' USING ERRCODE='P0002';END IF;
  IF action='retry' THEN
   IF NOT v_quarantine.retryable OR v_quarantine.status NOT IN ('quarantined','retrying') THEN RAISE EXCEPTION 'record_not_retryable' USING ERRCODE='40001';END IF;
   UPDATE tj.platform_connector_quarantine SET status='retrying',last_seen_at=now() WHERE id=qid;
   INSERT INTO tj.platform_connector_retry_queue(quarantine_id,connection_id,available_at,locked_at,last_error) VALUES(qid,cid,now(),NULL,NULL) ON CONFLICT(quarantine_id) DO UPDATE SET available_at=excluded.available_at,locked_at=NULL,last_error=NULL;
   RETURN jsonb_build_object('ok',true,'status','retrying');
  END IF;
  IF length(coalesce(p_body->>'note',''))>2000 THEN RAISE EXCEPTION 'note_too_long' USING ERRCODE='22023';END IF;
  UPDATE tj.platform_connector_quarantine SET status=CASE action WHEN 'ignore' THEN 'ignored' ELSE 'resolved' END,resolved_at=now(),resolution=jsonb_build_object('action',action,'note',coalesce(p_body->>'note',''),'user_id',actor) WHERE id=qid;
  DELETE FROM tj.platform_connector_retry_queue WHERE quarantine_id=qid AND connection_id=cid;
  PERFORM tj_private.platform_calculate_connector_health(cid);
  RETURN jsonb_build_object('ok',true,'status',CASE action WHEN 'ignore' THEN 'ignored' ELSE 'resolved' END);
 ELSIF action IN ('acknowledge_alert','reopen_alert') THEN
  aid:=nullif(p_body->>'alert_id','')::uuid;
  UPDATE tj.platform_connector_alerts SET status=CASE action WHEN 'acknowledge_alert' THEN 'acknowledged' ELSE 'open' END,acknowledged_at=CASE action WHEN 'acknowledge_alert' THEN now() ELSE NULL END,acknowledged_by=CASE action WHEN 'acknowledge_alert' THEN actor ELSE NULL END WHERE id=aid AND connection_id=cid AND status=CASE action WHEN 'acknowledge_alert' THEN 'open' ELSE 'acknowledged' END;
  IF NOT FOUND THEN RAISE EXCEPTION 'alert_not_available' USING ERRCODE='40001';END IF;
  RETURN jsonb_build_object('ok',true,'status',CASE action WHEN 'acknowledge_alert' THEN 'acknowledged' ELSE 'open' END);
 ELSIF action='recalculate_health' THEN RETURN jsonb_build_object('ok',true,'health',tj_private.platform_calculate_connector_health(cid));END IF;
 RAISE EXCEPTION 'unknown_action' USING ERRCODE='22023';
END $$;
