CREATE FUNCTION tj_private.up_refresh_reports(p_org uuid,p_store uuid) RETURNS jsonb
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE tz text;day_key text;day_start timestamptz;day_end timestamptz;walks int;sales int;wait_avg numeric;metric record;bucket timestamptz;
BEGIN
 SELECT coalesce(timezone,'America/Toronto') INTO tz FROM tj.org_locations WHERE id=p_store AND organization_id=p_org;
 IF tz IS NULL THEN RAISE EXCEPTION 'store_unavailable';END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=tz) THEN tz:='America/Toronto';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('up-floor:'||p_store::text,0));
 day_key:=(now() AT TIME ZONE tz)::date::text;day_start:=day_key::date::timestamp AT TIME ZONE tz;day_end:=(day_key::date+1)::timestamp AT TIME ZONE tz;
 SELECT count(*),count(*) FILTER(WHERE EXISTS(SELECT 1 FROM tj.iq_customer_interactions i WHERE i.organization_id=p_org AND i.customer_waiting_id=w.id AND i.outcome='sale' AND i.ended_at IS NOT NULL)) INTO walks,sales FROM tj.iq_customer_waiting_queue w WHERE w.organization_id=p_org AND w.store_id=p_store AND w.arrival_time>=day_start AND w.arrival_time<day_end;
 SELECT avg(extract(epoch FROM a.first_accept-w.arrival_time)) INTO wait_avg FROM tj.iq_customer_waiting_queue w JOIN LATERAL(SELECT min(accepted_at) first_accept FROM tj.iq_customer_interactions WHERE organization_id=p_org AND customer_waiting_id=w.id) a ON a.first_accept>=w.arrival_time WHERE w.organization_id=p_org AND w.store_id=p_store AND w.arrival_time>=day_start AND w.arrival_time<day_end;
 FOR metric IN SELECT * FROM (VALUES('walk_ins'::text,walks::numeric),('floor_conversion',CASE WHEN walks>0 THEN round(sales::numeric*100/walks,2) ELSE NULL END),('greeting_time',round(wait_avg))) m(k,v) LOOP
  -- Unknown averages/ratios are omitted rather than published as fabricated zeroes.
  IF metric.v IS NULL THEN CONTINUE;END IF;
  UPDATE tj.metric_snapshots SET actual_value=metric.v,computed_at=now(),variance_value=metric.v-target_value,variance_pct=CASE WHEN target_value<>0 THEN (metric.v-target_value)*100/target_value ELSE NULL END WHERE organization_id=p_org AND location_id=p_store AND user_id IS NULL AND period_type='daily' AND period_key=day_key AND metric_key=metric.k;
  IF NOT FOUND THEN INSERT INTO tj.metric_snapshots(organization_id,location_id,period_type,period_key,metric_key,actual_value,computed_at) VALUES(p_org,p_store,'daily',day_key,metric.k,metric.v,now());END IF;
 END LOOP;
 FOR bucket IN SELECT generate_series(day_start,least(date_trunc('hour',now()),day_end-interval '1 hour'),interval '1 hour') LOOP
  INSERT INTO tj.iq_hourly_traffic_summaries(organization_id,store_id,bucket_start,raw_traffic,adjusted_traffic,customer_groups,ups_created,customers_served,avg_wait_seconds,staffing_minimum,staffing_recommended)
  SELECT p_org,p_store,bucket,count(*),count(*),count(*),count(*) FILTER(WHERE w.assigned_user_id IS NOT NULL),count(*) FILTER(WHERE w.assigned_user_id IS NOT NULL),round(avg(extract(epoch FROM a.first_accept-w.arrival_time)) FILTER(WHERE a.first_accept>=w.arrival_time))::int,greatest(1,ceil(count(*)::numeric/3)::int),greatest(1,ceil(count(*)::numeric/2)::int)
  FROM tj.iq_customer_waiting_queue w LEFT JOIN LATERAL(SELECT min(accepted_at) first_accept FROM tj.iq_customer_interactions WHERE organization_id=p_org AND customer_waiting_id=w.id) a ON true WHERE w.organization_id=p_org AND w.store_id=p_store AND w.arrival_time>=bucket AND w.arrival_time<bucket+interval '1 hour'
  ON CONFLICT(organization_id,store_id,bucket_start) DO UPDATE SET raw_traffic=excluded.raw_traffic,adjusted_traffic=CASE WHEN tj.iq_hourly_traffic_summaries.adjusted_traffic IS DISTINCT FROM tj.iq_hourly_traffic_summaries.raw_traffic THEN tj.iq_hourly_traffic_summaries.adjusted_traffic ELSE excluded.adjusted_traffic END,customer_groups=excluded.customer_groups,ups_created=excluded.ups_created,customers_served=excluded.customers_served,avg_wait_seconds=excluded.avg_wait_seconds,staffing_minimum=excluded.staffing_minimum,staffing_recommended=excluded.staffing_recommended,updated_at=now();
 END LOOP;
 RETURN jsonb_build_object('ok',true,'period_key',day_key,'walk_ins',walks,'closed_visits',sales);
END $$;
REVOKE ALL ON FUNCTION tj_private.up_refresh_reports(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION tj_private.up_operations(p_body jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=tj_private.current_source_user_id();prof uuid;org uuid;sid uuid;act text;boss boolean;s tj.iq_store_settings;v jsonb;greeter uuid;r jsonb;did uuid;d tj.iq_up_disputes;decision text;affected uuid;snap jsonb;
BEGIN
 IF auth.uid() IS NULL OR actor IS NULL THEN RETURN jsonb_build_object('ok',false,'error','identity_required');END IF;
 IF jsonb_typeof(p_body) IS DISTINCT FROM 'object' OR octet_length(p_body::text)>12000 THEN RAISE EXCEPTION 'invalid_request';END IF;
 org:=(p_body->>'organization_id')::uuid;sid:=(p_body->>'store_id')::uuid;act:=p_body->>'action';SELECT id INTO prof FROM tj.profiles WHERE user_id=actor;
 IF prof IS NULL OR NOT tj_private.can_read_runtime_org(org) OR NOT EXISTS(SELECT 1 FROM tj.organization_members WHERE organization_id=org AND user_id=actor AND status='active' AND role IN('owner','admin','manager','member')) THEN RETURN jsonb_build_object('ok',false,'error','organization_write_required');END IF;
 IF sid IS NULL OR NOT EXISTS(SELECT 1 FROM tj.org_locations WHERE id=sid AND organization_id=org) OR NOT tj.aiq_store_allows(org,sid) THEN RETURN jsonb_build_object('ok',false,'error','store_unavailable');END IF;
 boss:=EXISTS(SELECT 1 FROM tj.organization_members WHERE organization_id=org AND user_id=actor AND status='active' AND role IN('owner','admin','manager'));
 PERFORM pg_advisory_xact_lock(hashtextextended('up-floor:'||sid::text,0));
 IF act='refresh_reports' THEN RETURN tj_private.up_refresh_reports(org,sid);END IF;
 IF act='save_settings' THEN
  IF NOT boss THEN RETURN jsonb_build_object('ok',false,'error','manager_required');END IF;
  v:=p_body->'settings';
  IF jsonb_typeof(v) IS DISTINCT FROM 'object' OR length(btrim(coalesce(v->>'queue_name','')))<1 OR length(v->>'queue_name')>100 OR coalesce((v->>'break_max_per_shift')::int,-1) NOT BETWEEN 0 AND 12 OR coalesce((v->>'paid_break_minutes')::int,-1) NOT BETWEEN 0 AND 120 OR coalesce((v->>'lunch_minutes')::int,-1) NOT BETWEEN 0 AND 180 OR coalesce((v->>'accept_up_timeout_seconds')::int,-1) NOT BETWEEN 5 AND 600 OR coalesce(v->>'missed_up_queue_rule','') NOT IN('back_of_queue','hold_position','skip_once') OR coalesce(v->>'accept_up_action','') NOT IN('next_in_line','back_of_queue') OR jsonb_typeof(v->'greeter_enabled') IS DISTINCT FROM 'boolean' OR jsonb_typeof(v->'is_open_rotation_enabled') IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'invalid_settings';END IF;
  SELECT * INTO s FROM tj.iq_store_settings WHERE organization_id=org AND store_id=sid FOR UPDATE;
  greeter:=CASE WHEN (v->>'greeter_enabled')::boolean THEN nullif(v->>'greeter_user_id','')::uuid ELSE NULL END;
  IF greeter IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.iq_shift_records sh JOIN tj.profiles p ON p.id=sh.user_id JOIN tj.organization_members m ON m.user_id=p.user_id WHERE sh.organization_id=org AND sh.store_id=sid AND sh.user_id=greeter AND sh.is_active AND m.organization_id=org AND m.status='active') THEN RAISE EXCEPTION 'greeter_must_be_clocked_in';END IF;
  IF s.greeter_user_id IS DISTINCT FROM greeter THEN
   IF s.greeter_user_id IS NOT NULL AND EXISTS(SELECT 1 FROM tj.iq_shift_records WHERE organization_id=org AND store_id=sid AND user_id=s.greeter_user_id AND is_active) THEN r:=tj_private.up_rotation(jsonb_build_object('organization_id',org,'store_id',sid,'action','greeter_end','rep_profile_id',s.greeter_user_id));IF r->>'ok'<>'true' THEN RAISE EXCEPTION 'greeter_change_failed';END IF;END IF;
   UPDATE tj.iq_store_settings SET greeter_user_id=NULL WHERE organization_id=org AND store_id=sid;
   IF greeter IS NOT NULL THEN r:=tj_private.up_rotation(jsonb_build_object('organization_id',org,'store_id',sid,'action','greeter_start','rep_profile_id',greeter));IF r->>'ok'<>'true' THEN RAISE EXCEPTION 'greeter_change_failed';END IF;END IF;
  END IF;
  INSERT INTO tj.iq_store_settings(organization_id,store_id,queue_name,missed_up_queue_rule,break_max_per_shift,paid_break_minutes,lunch_minutes,is_open_rotation_enabled,accept_up_timeout_seconds,accept_up_action,greeter_enabled,greeter_user_id,created_by,updated_by)
  VALUES(org,sid,btrim(v->>'queue_name'),v->>'missed_up_queue_rule',(v->>'break_max_per_shift')::int,(v->>'paid_break_minutes')::int,(v->>'lunch_minutes')::int,(v->>'is_open_rotation_enabled')::boolean,(v->>'accept_up_timeout_seconds')::int,v->>'accept_up_action',(v->>'greeter_enabled')::boolean,greeter,actor,actor)
  ON CONFLICT(organization_id,store_id) DO UPDATE SET queue_name=excluded.queue_name,missed_up_queue_rule=excluded.missed_up_queue_rule,break_max_per_shift=excluded.break_max_per_shift,paid_break_minutes=excluded.paid_break_minutes,lunch_minutes=excluded.lunch_minutes,is_open_rotation_enabled=excluded.is_open_rotation_enabled,accept_up_timeout_seconds=excluded.accept_up_timeout_seconds,accept_up_action=excluded.accept_up_action,greeter_enabled=excluded.greeter_enabled,greeter_user_id=excluded.greeter_user_id,updated_by=actor,updated_at=now();
  PERFORM tj_private.up_recalc_queue(org,sid);RETURN jsonb_build_object('ok',true);
 END IF;
 IF act IN('file_dispute','resolve_dispute') THEN
  did:=(p_body->>'dispute_id')::uuid;IF did IS NULL THEN RAISE EXCEPTION 'dispute_id_required';END IF;
  SELECT * INTO d FROM tj.iq_up_disputes WHERE id=did FOR UPDATE;
  SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'user_id',user_id,'queue_position',queue_position,'status_code',status_code,'is_current_up',is_current_up) ORDER BY queue_position),'[]'::jsonb) INTO snap FROM tj.iq_up_queue_entries WHERE organization_id=org AND store_id=sid AND is_in_queue;
  IF act='file_dispute' THEN
   IF d.id IS NOT NULL THEN IF d.organization_id<>org OR d.store_id<>sid OR d.disputed_by<>prof THEN RAISE EXCEPTION 'dispute_unavailable';END IF;RETURN jsonb_build_object('ok',true,'dispute_id',did,'changed',false);END IF;
   affected:=nullif(p_body->>'affected_profile_id','')::uuid;
   IF affected IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.profiles p JOIN tj.organization_members m ON m.user_id=p.user_id WHERE p.id=affected AND m.organization_id=org AND m.status='active') THEN RAISE EXCEPTION 'affected_rep_unavailable';END IF;
   IF length(btrim(coalesce(p_body->>'reason','')))<1 OR length(p_body->>'reason')>4000 THEN RAISE EXCEPTION 'invalid_reason';END IF;
   INSERT INTO tj.iq_up_disputes(id,organization_id,store_id,disputed_by,affected_employee_id,reason,status,queue_snapshot_before,updated_by) VALUES(did,org,sid,prof,affected,btrim(p_body->>'reason'),'open',snap,actor);
  ELSE
   IF NOT boss THEN RETURN jsonb_build_object('ok',false,'error','manager_required');END IF;
   IF d.id IS NULL OR d.organization_id<>org OR d.store_id<>sid THEN RAISE EXCEPTION 'dispute_unavailable';END IF;
   IF d.status='resolved' THEN RETURN jsonb_build_object('ok',true,'changed',false);END IF;
   decision:=p_body->>'decision';IF decision IS NULL OR decision NOT IN('upheld','dismissed','partial') OR length(coalesce(p_body->>'notes',''))>4000 THEN RAISE EXCEPTION 'invalid_decision';END IF;
   IF coalesce((p_body->>'restore_queue_priority')::boolean,false) THEN
    IF decision='dismissed' OR d.affected_employee_id IS NULL OR NOT EXISTS(SELECT 1 FROM tj.iq_up_queue_entries WHERE organization_id=org AND store_id=sid AND user_id=d.affected_employee_id AND is_in_queue AND is_available_for_assignment AND NOT is_suspended AND status_code<>'with_customer') THEN RAISE EXCEPTION 'queue_correction_unavailable';END IF;
    r:=tj_private.up_rotation(jsonb_build_object('organization_id',org,'store_id',sid,'action','bump','rep_profile_id',d.affected_employee_id));IF r->>'ok'<>'true' THEN RAISE EXCEPTION 'queue_correction_failed';END IF;
    SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'user_id',user_id,'queue_position',queue_position,'status_code',status_code,'is_current_up',is_current_up) ORDER BY queue_position),'[]'::jsonb) INTO snap FROM tj.iq_up_queue_entries WHERE organization_id=org AND store_id=sid AND is_in_queue;
   END IF;
   UPDATE tj.iq_up_disputes SET status='resolved',manager_decision=decision,manager_notes=nullif(btrim(p_body->>'notes'),''),manager_id=prof,resolved_at=now(),queue_snapshot_after=snap,updated_by=actor,updated_at=now() WHERE id=did;
  END IF;
  RETURN jsonb_build_object('ok',true,'dispute_id',did);
 END IF;
 RAISE EXCEPTION 'invalid_action';
EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('ok',false,'error','operation_failed','sqlstate',SQLSTATE);
END $$;
REVOKE ALL ON FUNCTION tj_private.up_operations(jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION tj_private.up_operations(jsonb) TO authenticated;
CREATE FUNCTION public.tj_runtime_up_operations(p_body jsonb) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.up_operations(p_body); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_up_operations(jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.tj_runtime_up_operations(jsonb) TO authenticated;

CREATE FUNCTION tj_private.up_report_change() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM tj_private.up_refresh_reports(NEW.organization_id,NEW.store_id);RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION tj_private.up_report_change() FROM PUBLIC,anon,authenticated,service_role;
-- The final waiting-row update occurs after the handoff's interaction and CRM writes.
CREATE TRIGGER up_report_waiting_change AFTER INSERT OR UPDATE OF status,assigned_user_id,crm_deal_id ON tj.iq_customer_waiting_queue FOR EACH ROW EXECUTE FUNCTION tj_private.up_report_change();
