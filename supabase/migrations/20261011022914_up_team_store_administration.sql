CREATE FUNCTION tj_private.up_administration(p_body jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=tj_private.current_source_user_id();org uuid;sid uuid;act text;myrole text;m tj.organization_members;newrole text;storeid uuid;prof uuid;mid uuid;mr tj.iq_missed_and_potential_missed_ups;q tj.iq_up_queue_entries;rule text;counted boolean;decision text;otherq uuid;position int;
BEGIN
 IF auth.uid() IS NULL OR actor IS NULL THEN RETURN jsonb_build_object('ok',false,'error','identity_required');END IF;
 IF jsonb_typeof(p_body) IS DISTINCT FROM 'object' OR octet_length(p_body::text)>8000 THEN RAISE EXCEPTION 'invalid_request';END IF;
 org:=(p_body->>'organization_id')::uuid;sid:=nullif(p_body->>'store_id','')::uuid;act:=p_body->>'action';
 SELECT role INTO myrole FROM tj.organization_members WHERE organization_id=org AND user_id=actor AND status='active';
 IF myrole IS NULL OR NOT tj_private.can_read_runtime_org(org) THEN RETURN jsonb_build_object('ok',false,'error','organization_required');END IF;
 SELECT id INTO prof FROM tj.profiles WHERE user_id=actor;
 IF act IN('report_missed','review_missed') THEN
  IF sid IS NULL OR NOT EXISTS(SELECT 1 FROM tj.org_locations WHERE id=sid AND organization_id=org AND is_active) OR NOT tj.aiq_store_allows(org,sid) THEN RAISE EXCEPTION 'store_unavailable';END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('up-floor:'||sid::text,0));
  mid:=(p_body->>'missed_id')::uuid;IF mid IS NULL OR prof IS NULL THEN RAISE EXCEPTION 'invalid_record';END IF;
  SELECT * INTO mr FROM tj.iq_missed_and_potential_missed_ups WHERE id=mid FOR UPDATE;
  IF act='report_missed' THEN
   IF myrole NOT IN('owner','admin','manager','member') THEN RAISE EXCEPTION 'member_required';END IF;
   IF mr.id IS NOT NULL THEN IF mr.organization_id<>org OR mr.store_id<>sid OR mr.reported_by<>prof THEN RAISE EXCEPTION 'record_unavailable';END IF;RETURN jsonb_build_object('ok',true,'changed',false);END IF;
   IF length(btrim(coalesce(p_body->>'reason','')))<1 OR length(p_body->>'reason')>2000 THEN RAISE EXCEPTION 'reason_required';END IF;
   SELECT qe.* INTO q FROM tj.iq_up_queue_entries qe JOIN tj.iq_shift_records sh ON sh.id=qe.shift_id AND sh.is_active JOIN tj.profiles p ON p.id=qe.user_id JOIN tj.organization_members mem ON mem.user_id=p.user_id AND mem.organization_id=org AND mem.status='active' WHERE qe.organization_id=org AND qe.store_id=sid AND qe.user_id=(p_body->>'rep_profile_id')::uuid ORDER BY sh.login_at DESC LIMIT 1;
   IF q.id IS NULL THEN RAISE EXCEPTION 'active_shift_required';END IF;
   INSERT INTO tj.iq_missed_and_potential_missed_ups(id,organization_id,store_id,queue_entry_id,reported_by,employee_user_id,reason,is_potential,affects_kpi) VALUES(mid,org,sid,q.id,prof,q.user_id,btrim(p_body->>'reason'),true,false);
  ELSE
   IF myrole NOT IN('owner','admin','manager') THEN RETURN jsonb_build_object('ok',false,'error','manager_required');END IF;
   IF mr.id IS NULL OR mr.organization_id<>org OR mr.store_id<>sid THEN RAISE EXCEPTION 'record_unavailable';END IF;
   decision:=p_body->>'decision';IF decision IS NULL OR decision NOT IN('confirm','excuse','potential') OR length(coalesce(p_body->>'notes',''))>2000 THEN RAISE EXCEPTION 'invalid_decision';END IF;
   SELECT * INTO q FROM tj.iq_up_queue_entries WHERE id=mr.queue_entry_id AND organization_id=org AND store_id=sid;
   counted:=decision='confirm';IF counted AND q.id IS NULL THEN RAISE EXCEPTION 'shift_evidence_required';END IF;
   IF coalesce(mr.affects_kpi,false) IS DISTINCT FROM counted AND q.id IS NOT NULL THEN UPDATE tj.iq_shift_records SET ups_missed=greatest(0,ups_missed+CASE WHEN counted THEN 1 ELSE -1 END),updated_by=actor WHERE id=q.shift_id AND organization_id=org;END IF;
   IF counted AND NOT coalesce(mr.affects_kpi,false) AND q.is_in_queue THEN
    SELECT missed_up_queue_rule INTO rule FROM tj.iq_store_settings WHERE organization_id=org AND store_id=sid;
    IF coalesce(rule,'back_of_queue')='back_of_queue' THEN SELECT coalesce(max(queue_position),0)+1 INTO position FROM tj.iq_up_queue_entries WHERE organization_id=org AND store_id=sid AND is_in_queue;UPDATE tj.iq_up_queue_entries SET queue_position=position,is_current_up=false,up_offered_at=NULL,updated_by=actor WHERE id=q.id;
    ELSIF rule='skip_once' THEN SELECT id,queue_position INTO otherq,position FROM tj.iq_up_queue_entries WHERE organization_id=org AND store_id=sid AND is_in_queue AND is_available_for_assignment AND queue_position>q.queue_position ORDER BY queue_position LIMIT 1;IF otherq IS NOT NULL THEN UPDATE tj.iq_up_queue_entries SET queue_position=q.queue_position WHERE id=otherq;UPDATE tj.iq_up_queue_entries SET queue_position=position,is_current_up=false,up_offered_at=NULL,updated_by=actor WHERE id=q.id;END IF;END IF;
    PERFORM tj_private.up_recalc_queue(org,sid);
   END IF;
   UPDATE tj.iq_missed_and_potential_missed_ups SET is_potential=decision='potential',is_excused=decision='excuse',affects_kpi=counted,manager_reviewed=true,reviewed_at=now(),reviewed_by=prof,notes=nullif(btrim(p_body->>'notes'),''),queue_consequence=coalesce(queue_consequence,'{}'::jsonb)||jsonb_build_object('decision',decision,'rule',rule,'position_before',q.queue_position,'position_after',(SELECT queue_position FROM tj.iq_up_queue_entries WHERE id=q.id)) WHERE id=mid;
  END IF;
  RETURN jsonb_build_object('ok',true,'missed_id',mid);
 END IF;
 IF myrole NOT IN('owner','admin') THEN RETURN jsonb_build_object('ok',false,'error','administrator_required');END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('up-org-admin:'||org::text,0));
 IF act='team_roster' THEN RETURN jsonb_build_object('ok',true,'members',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',mem.id,'user_id',mem.user_id,'role',mem.role,'status',mem.status,'display_name',coalesce(p.full_name,p.email,'Staff'),'stores',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',loc.id,'name',loc.name,'primary',lm.is_primary)),'[]'::jsonb) FROM tj.org_location_members lm JOIN tj.org_locations loc ON loc.id=lm.location_id WHERE lm.organization_id=org AND lm.user_id=mem.user_id))),'[]'::jsonb) FROM tj.organization_members mem LEFT JOIN tj.profiles p ON p.user_id=mem.user_id WHERE mem.organization_id=org AND mem.status IN('active','suspended')));END IF;
 IF act IN('set_role','deactivate_member','activate_member','assign_store') THEN
  SELECT * INTO m FROM tj.organization_members WHERE id=(p_body->>'member_id')::uuid AND organization_id=org FOR UPDATE;
  IF m.id IS NULL THEN RAISE EXCEPTION 'member_unavailable';END IF;
  IF m.role IN('owner','admin') AND myrole<>'owner' THEN RAISE EXCEPTION 'owner_required';END IF;
  IF act='set_role' THEN
   newrole:=p_body->>'role';IF newrole IS NULL OR newrole NOT IN('member','manager','admin','owner') OR (myrole<>'owner' AND newrole IN('admin','owner')) THEN RAISE EXCEPTION 'role_not_allowed';END IF;
  END IF;
  IF m.role='owner' AND m.status='active' AND (act='deactivate_member' OR (act='set_role' AND newrole<>'owner')) AND (SELECT count(*) FROM tj.organization_members WHERE organization_id=org AND status='active' AND role='owner')<=1 THEN RETURN jsonb_build_object('ok',false,'error','last_owner_required');END IF;
  SELECT id INTO prof FROM tj.profiles WHERE user_id=m.user_id;
  IF act='deactivate_member' AND EXISTS(SELECT 1 FROM tj.iq_shift_records WHERE organization_id=org AND user_id=prof AND is_active) THEN RETURN jsonb_build_object('ok',false,'error','clock_out_member_first');END IF;
  IF act='set_role' THEN UPDATE tj.organization_members SET role=newrole WHERE id=m.id;
  ELSIF act='deactivate_member' THEN UPDATE tj.organization_members SET status='suspended' WHERE id=m.id;
  ELSIF act='activate_member' THEN IF m.status NOT IN('active','suspended') THEN RAISE EXCEPTION 'membership_review_required';END IF;UPDATE tj.organization_members SET status='active' WHERE id=m.id;
  ELSE
   IF m.status<>'active' OR sid IS NULL OR NOT EXISTS(SELECT 1 FROM tj.org_locations WHERE id=sid AND organization_id=org AND is_active) THEN RAISE EXCEPTION 'active_member_store_required';END IF;
   IF coalesce((p_body->>'primary')::boolean,false) THEN UPDATE tj.org_location_members SET is_primary=false WHERE organization_id=org AND user_id=m.user_id;END IF;
   INSERT INTO tj.org_location_members(organization_id,location_id,user_id,is_primary) VALUES(org,sid,m.user_id,coalesce((p_body->>'primary')::boolean,false)) ON CONFLICT(location_id,user_id) DO UPDATE SET is_primary=excluded.is_primary;
  END IF;
 ELSIF act='add_store' THEN
  IF length(btrim(coalesce(p_body->>'name','')))<1 OR length(p_body->>'name')>150 OR length(coalesce(p_body->>'city',''))>150 THEN RAISE EXCEPTION 'invalid_store';END IF;
  storeid:=(p_body->>'new_store_id')::uuid;IF storeid IS NULL THEN RAISE EXCEPTION 'store_id_required';END IF;
  IF EXISTS(SELECT 1 FROM tj.org_locations WHERE id=storeid AND organization_id<>org) THEN RAISE EXCEPTION 'store_unavailable';END IF;
  INSERT INTO tj.org_locations(id,organization_id,location_type,name,city,timezone,is_active) VALUES(storeid,org,'store',btrim(p_body->>'name'),nullif(btrim(p_body->>'city'),''),'America/Toronto',true) ON CONFLICT(id) DO NOTHING;
 ELSIF act IN('deactivate_store','activate_store') THEN
  IF sid IS NULL OR NOT EXISTS(SELECT 1 FROM tj.org_locations WHERE id=sid AND organization_id=org AND location_type='store') THEN RAISE EXCEPTION 'store_unavailable';END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('up-floor:'||sid::text,0));
  IF act='deactivate_store' AND (EXISTS(SELECT 1 FROM tj.iq_shift_records WHERE organization_id=org AND store_id=sid AND is_active) OR EXISTS(SELECT 1 FROM tj.iq_customer_interactions WHERE organization_id=org AND store_id=sid AND ended_at IS NULL)) THEN RETURN jsonb_build_object('ok',false,'error','active_store_work_required');END IF;
  IF act='deactivate_store' AND (SELECT count(*) FROM tj.org_locations WHERE organization_id=org AND location_type='store' AND is_active)<=1 THEN RETURN jsonb_build_object('ok',false,'error','last_active_store_required');END IF;
  UPDATE tj.org_locations SET is_active=act='activate_store',closed_at=CASE WHEN act='deactivate_store' THEN coalesce(closed_at,now()) ELSE NULL END,updated_at=now() WHERE id=sid;
 ELSE RAISE EXCEPTION 'invalid_action';END IF;
 RETURN jsonb_build_object('ok',true);
EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('ok',false,'error','administration_failed','sqlstate',SQLSTATE);
END $$;
REVOKE ALL ON FUNCTION tj_private.up_administration(jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION tj_private.up_administration(jsonb) TO authenticated;
CREATE FUNCTION public.tj_runtime_up_administration(p_body jsonb) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.up_administration(p_body); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_up_administration(jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.tj_runtime_up_administration(jsonb) TO authenticated;

-- Archived stores remain readable but cannot receive new UP operations.
CREATE OR REPLACE FUNCTION tj_private.up_rotation(p_body jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=tj_private.current_source_user_id();prof uuid;org uuid;sid uuid;rep uuid;role_text text;act text;shift tj.iq_shift_records;q tj.iq_up_queue_entries;st tj.iq_store_settings;status_text text;pos int;joins boolean;boss boolean;prior_status text;next_q uuid;expected timestamptz;
BEGIN
 IF auth.uid() IS NULL OR actor IS NULL THEN RETURN jsonb_build_object('ok',false,'error','identity_required');END IF;
 IF jsonb_typeof(p_body) IS DISTINCT FROM 'object' OR octet_length(p_body::text)>4096 THEN RAISE EXCEPTION 'invalid_request';END IF;
 org:=(p_body->>'organization_id')::uuid;sid:=(p_body->>'store_id')::uuid;act:=p_body->>'action';
 SELECT id INTO prof FROM tj.profiles WHERE user_id=actor;
 IF prof IS NULL OR org IS NULL OR NOT tj_private.can_read_runtime_org(org) OR NOT EXISTS(SELECT 1 FROM tj.organization_members WHERE organization_id=org AND user_id=actor AND status='active' AND role IN('owner','admin','manager','member')) THEN RETURN jsonb_build_object('ok',false,'error','organization_write_required');END IF;
 IF act='profiles' THEN RETURN jsonb_build_object('ok',true,'profiles',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',p.id,'display_name',coalesce(nullif(p.full_name,''),p.email,'Staff'))),'[]'::jsonb) FROM tj.profiles p JOIN tj.organization_members m ON m.user_id=p.user_id WHERE m.organization_id=org AND m.status='active'));END IF;
 IF sid IS NULL OR NOT EXISTS(SELECT 1 FROM tj.org_locations WHERE id=sid AND organization_id=org AND is_active) OR NOT tj.aiq_store_allows(org,sid) THEN RETURN jsonb_build_object('ok',false,'error','store_unavailable');END IF;
 boss:=EXISTS(SELECT 1 FROM tj.organization_members WHERE organization_id=org AND user_id=actor AND status='active' AND role IN('owner','admin','manager'));
 PERFORM pg_advisory_xact_lock(hashtextextended('up-floor:'||sid::text,0));
 IF act='recalc' THEN PERFORM tj_private.up_recalc_queue(org,sid);RETURN jsonb_build_object('ok',true);END IF;
 SELECT * INTO st FROM tj.iq_store_settings WHERE organization_id=org AND store_id=sid;
 IF act IN('accept_up','timeout') THEN
  SELECT * INTO q FROM tj.iq_up_queue_entries WHERE id=(p_body->>'entry_id')::uuid AND organization_id=org AND store_id=sid FOR UPDATE;
  IF q.id IS NULL OR NOT q.is_current_up OR NOT q.is_in_queue OR NOT q.is_available_for_assignment OR q.is_suspended OR NOT EXISTS(SELECT 1 FROM tj.iq_shift_records WHERE id=q.shift_id AND organization_id=org AND store_id=sid AND is_active) THEN RETURN jsonb_build_object('ok',false,'error','offer_unavailable');END IF;
  IF act='accept_up' THEN
   IF q.user_id<>prof AND NOT boss THEN RETURN jsonb_build_object('ok',false,'error','own_offer_required');END IF;
   UPDATE tj.iq_up_queue_entries SET up_offered_at=NULL,updated_by=actor WHERE id=q.id;
  ELSE
   expected:=(p_body->>'expected_offered_at')::timestamptz;
   IF expected IS NULL OR q.up_offered_at IS DISTINCT FROM expected OR now()<q.up_offered_at+make_interval(secs=>greatest(5,coalesce(st.accept_up_timeout_seconds,60))) THEN RETURN jsonb_build_object('ok',true,'changed',false);END IF;
   SELECT id INTO next_q FROM tj.iq_up_queue_entries WHERE organization_id=org AND store_id=sid AND is_in_queue AND is_next_in_line ORDER BY queue_position LIMIT 1;
   INSERT INTO tj.iq_missed_and_potential_missed_ups(organization_id,store_id,queue_entry_id,reported_by,employee_user_id,reason,is_potential,affects_kpi) VALUES(org,sid,q.id,prof,q.user_id,'Did not accept UP within configured time limit',false,true);
   UPDATE tj.iq_shift_records SET ups_missed=ups_missed+1,updated_by=actor WHERE id=q.shift_id AND organization_id=org AND is_active;
   IF coalesce(st.accept_up_action,'next_in_line')='back_of_queue' THEN
    SELECT coalesce(max(queue_position),0)+1 INTO pos FROM tj.iq_up_queue_entries WHERE organization_id=org AND store_id=sid AND is_in_queue;
    UPDATE tj.iq_up_queue_entries SET queue_position=pos,is_current_up=false,up_offered_at=NULL,updated_by=actor WHERE id=q.id;
   ELSIF next_q IS NOT NULL THEN
    UPDATE tj.iq_up_queue_entries SET queue_position=q.queue_position WHERE id=next_q;
    UPDATE tj.iq_up_queue_entries SET queue_position=q.queue_position+1,is_current_up=false,up_offered_at=NULL,updated_by=actor WHERE id=q.id;
   ELSE
    -- One eligible rep: retain position and mark offer handled without repeated KPI penalties.
    UPDATE tj.iq_up_queue_entries SET up_offered_at=NULL,updated_by=actor WHERE id=q.id;
   END IF;
   PERFORM tj_private.up_recalc_queue(org,sid);
  END IF;
  RETURN jsonb_build_object('ok',true,'changed',true);
 END IF;
 rep:=coalesce(nullif(p_body->>'rep_profile_id','')::uuid,prof);
 IF rep<>prof AND NOT boss THEN RETURN jsonb_build_object('ok',false,'error','own_shift_required');END IF;
 IF NOT EXISTS(SELECT 1 FROM tj.profiles p JOIN tj.organization_members m ON m.user_id=p.user_id WHERE p.id=rep AND m.organization_id=org AND m.status='active' AND m.role IN('owner','admin','manager','member')) THEN RAISE EXCEPTION 'rep_unavailable';END IF;
 -- Also serialize a rep across stores to avoid concurrent duplicate clock-ins.
 PERFORM pg_advisory_xact_lock(hashtextextended('up-rep:'||rep::text,0));
 SELECT * INTO shift FROM tj.iq_shift_records WHERE organization_id=org AND user_id=rep AND is_active ORDER BY login_at DESC LIMIT 1 FOR UPDATE;
 IF shift.id IS NOT NULL AND shift.store_id<>sid THEN RETURN jsonb_build_object('ok',false,'error','clock_out_other_store_first');END IF;
 IF act='clock_in' THEN
  IF shift.id IS NOT NULL THEN RETURN jsonb_build_object('ok',true,'shift_id',shift.id,'changed',false);END IF;
  role_text:=coalesce(p_body->>'role','salesperson');
  IF role_text NOT IN('salesperson','manager','greeter','support') OR (role_text='manager' AND NOT boss) THEN RAISE EXCEPTION 'invalid_role';END IF;
  IF role_text='greeter' AND st.greeter_user_id IS NOT NULL AND st.greeter_user_id<>rep THEN RETURN jsonb_build_object('ok',false,'error','greeter_already_assigned');END IF;
  joins:=role_text IN('salesperson','manager');status_text:=CASE WHEN role_text='support' THEN 'administrative_work' ELSE 'available' END;
  INSERT INTO tj.iq_shift_records(organization_id,store_id,user_id,role_name,initial_status,is_active,is_greeter,created_by,updated_by) VALUES(org,sid,rep,role_text,status_text::public.iq_status_type,true,role_text='greeter',actor,actor) RETURNING * INTO shift;
  SELECT coalesce(max(queue_position),0)+1 INTO pos FROM tj.iq_up_queue_entries WHERE organization_id=org AND store_id=sid AND is_in_queue;
  INSERT INTO tj.iq_up_queue_entries(organization_id,store_id,shift_id,user_id,queue_position,is_in_queue,status_code,is_available_for_assignment,created_by,updated_by) VALUES(org,sid,shift.id,rep,pos,joins,status_text::public.iq_status_type,joins,actor,actor);
  INSERT INTO tj.iq_status_sessions(shift_id,organization_id,store_id,user_id,status,created_by) VALUES(shift.id,org,sid,rep,status_text::public.iq_status_type,actor);
  IF role_text='greeter' THEN
   IF st.id IS NULL THEN INSERT INTO tj.iq_store_settings(organization_id,store_id,greeter_enabled,greeter_user_id,created_by,updated_by) VALUES(org,sid,true,rep,actor,actor);
   ELSE UPDATE tj.iq_store_settings SET greeter_enabled=true,greeter_user_id=rep,updated_by=actor WHERE id=st.id;END IF;
  END IF;
 ELSE
  IF shift.id IS NULL THEN
   IF act='clock_out' THEN RETURN jsonb_build_object('ok',true,'changed',false);END IF;
   RETURN jsonb_build_object('ok',false,'error','active_shift_required');
  END IF;
  IF nullif(p_body->>'shift_id','') IS NOT NULL AND (p_body->>'shift_id')::uuid<>shift.id THEN RETURN jsonb_build_object('ok',false,'error','shift_changed');END IF;
  IF EXISTS(SELECT 1 FROM tj.iq_customer_interactions WHERE organization_id=org AND store_id=sid AND salesperson_user_id=rep AND ended_at IS NULL) AND act IN('status','clock_out','greeter_start','greeter_end') THEN RETURN jsonb_build_object('ok',false,'error','end_or_reassign_visit_first');END IF;
  IF act='clock_out' THEN
   UPDATE tj.iq_status_sessions SET ended_at=now() WHERE shift_id=shift.id AND organization_id=org AND ended_at IS NULL;
   UPDATE tj.iq_shift_records SET is_active=false,logout_at=now(),closed_at=now(),shift_end_reason='normal',updated_by=actor WHERE id=shift.id;
   UPDATE tj.iq_up_queue_entries SET is_in_queue=false,is_current_up=false,is_next_in_line=false,up_offered_at=NULL,updated_by=actor WHERE shift_id=shift.id AND organization_id=org;
   UPDATE tj.iq_store_settings SET greeter_user_id=NULL,updated_by=actor WHERE organization_id=org AND store_id=sid AND greeter_user_id=rep;
  ELSIF act='status' THEN
   status_text:=p_body->>'status';
   IF status_text IS NULL OR status_text IN('ended_shift','current_up','next_in_line','with_customer') THEN RAISE EXCEPTION 'invalid_status';END IF;
   PERFORM status_text::public.iq_status_type;
   SELECT status::text INTO prior_status FROM tj.iq_status_sessions WHERE shift_id=shift.id AND organization_id=org AND ended_at IS NULL ORDER BY started_at DESC LIMIT 1;
   IF prior_status IS DISTINCT FROM status_text THEN
    UPDATE tj.iq_status_sessions SET ended_at=now() WHERE shift_id=shift.id AND organization_id=org AND ended_at IS NULL;
    INSERT INTO tj.iq_status_sessions(shift_id,organization_id,store_id,user_id,status,reason_note,created_by) VALUES(shift.id,org,sid,rep,status_text::public.iq_status_type,left(p_body->>'reason',1000),actor);
    SELECT coalesce(max(queue_position),0)+1 INTO pos FROM tj.iq_up_queue_entries WHERE organization_id=org AND store_id=sid AND is_in_queue;
    UPDATE tj.iq_up_queue_entries SET status_code=status_text::public.iq_status_type,is_available_for_assignment=status_text IN('available','scheduled_appointment','client_meeting','follow_up_activity'),queue_position=CASE WHEN status_text='available' THEN pos ELSE queue_position END,updated_by=actor WHERE organization_id=org AND shift_id=shift.id;
   END IF;
  ELSIF act IN('rotate_back','bump') THEN
   IF act='bump' AND NOT boss THEN RETURN jsonb_build_object('ok',false,'error','manager_required');END IF;
   SELECT coalesce(max(queue_position),0)+1 INTO pos FROM tj.iq_up_queue_entries WHERE organization_id=org AND store_id=sid AND is_in_queue;
   UPDATE tj.iq_up_queue_entries SET queue_position=CASE WHEN act='bump' THEN 0 ELSE pos END,is_current_up=false,up_offered_at=NULL,updated_by=actor WHERE organization_id=org AND shift_id=shift.id AND is_in_queue;
  ELSIF act IN('greeter_start','greeter_end') THEN
   IF act='greeter_start' AND st.greeter_user_id IS NOT NULL AND st.greeter_user_id<>rep THEN RETURN jsonb_build_object('ok',false,'error','greeter_already_assigned');END IF;
   IF act='greeter_end' AND st.greeter_user_id IS DISTINCT FROM rep THEN RETURN jsonb_build_object('ok',false,'error','own_greeter_required');END IF;
   IF st.id IS NULL THEN INSERT INTO tj.iq_store_settings(organization_id,store_id,greeter_enabled,greeter_user_id,created_by,updated_by) VALUES(org,sid,true,rep,actor,actor);
   ELSE UPDATE tj.iq_store_settings SET greeter_enabled=true,greeter_user_id=CASE WHEN act='greeter_start' THEN rep ELSE NULL END,updated_by=actor WHERE id=st.id;END IF;
   SELECT coalesce(max(queue_position),0)+1 INTO pos FROM tj.iq_up_queue_entries WHERE organization_id=org AND store_id=sid AND is_in_queue;
   UPDATE tj.iq_up_queue_entries SET is_in_queue=act='greeter_end',queue_position=pos,status_code='available',is_available_for_assignment=act='greeter_end',is_current_up=false,up_offered_at=NULL,updated_by=actor WHERE organization_id=org AND shift_id=shift.id;
   UPDATE tj.iq_shift_records SET is_greeter=act='greeter_start',updated_by=actor WHERE id=shift.id;
  ELSE RAISE EXCEPTION 'invalid_action';END IF;
 END IF;
 PERFORM tj_private.up_recalc_queue(org,sid);
 RETURN jsonb_build_object('ok',true,'shift_id',shift.id,'changed',true);
EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('ok',false,'error','rotation_failed','sqlstate',SQLSTATE);
END $$;

-- Archived stores remain readable but cannot receive new UP operations.
CREATE OR REPLACE FUNCTION tj_private.up_operations(p_body jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=tj_private.current_source_user_id();prof uuid;org uuid;sid uuid;act text;boss boolean;s tj.iq_store_settings;v jsonb;greeter uuid;r jsonb;did uuid;d tj.iq_up_disputes;decision text;affected uuid;snap jsonb;
BEGIN
 IF auth.uid() IS NULL OR actor IS NULL THEN RETURN jsonb_build_object('ok',false,'error','identity_required');END IF;
 IF jsonb_typeof(p_body) IS DISTINCT FROM 'object' OR octet_length(p_body::text)>12000 THEN RAISE EXCEPTION 'invalid_request';END IF;
 org:=(p_body->>'organization_id')::uuid;sid:=(p_body->>'store_id')::uuid;act:=p_body->>'action';SELECT id INTO prof FROM tj.profiles WHERE user_id=actor;
 IF prof IS NULL OR NOT tj_private.can_read_runtime_org(org) OR NOT EXISTS(SELECT 1 FROM tj.organization_members WHERE organization_id=org AND user_id=actor AND status='active' AND role IN('owner','admin','manager','member')) THEN RETURN jsonb_build_object('ok',false,'error','organization_write_required');END IF;
 IF sid IS NULL OR NOT EXISTS(SELECT 1 FROM tj.org_locations WHERE id=sid AND organization_id=org AND is_active) OR NOT tj.aiq_store_allows(org,sid) THEN RETURN jsonb_build_object('ok',false,'error','store_unavailable');END IF;
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

-- Archived stores remain readable but cannot receive new UP operations.
CREATE OR REPLACE FUNCTION tj_private.up_crm_handoff(p_body jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=tj_private.current_source_user_id(); org uuid; sid uuid; wid uuid;
 prof uuid; rep uuid; owner_id uuid; w tj.iq_customer_waiting_queue; c uuid; d uuid; proj uuid; pkg uuid;
 row_data jsonb; product jsonb; name_text text; amount numeric; cats text[]; act text; v_shift_id uuid; changed integer; old_rep uuid; old_status text;
BEGIN
 IF auth.uid() IS NULL OR actor IS NULL THEN RETURN jsonb_build_object('ok',false,'error','identity_required');END IF;
 IF jsonb_typeof(p_body) IS DISTINCT FROM 'object' OR octet_length(p_body::text)>32768 THEN RAISE EXCEPTION 'invalid_request';END IF;
 act:=p_body->>'action';org:=(p_body->>'organization_id')::uuid;wid:=(p_body->>'waiting_id')::uuid;
 IF act IS NULL OR act NOT IN('log','sync','assign','after_sale') OR org IS NULL OR wid IS NULL THEN RAISE EXCEPTION 'invalid_request';END IF;
 IF NOT tj_private.can_read_runtime_org(org) OR NOT EXISTS(SELECT 1 FROM tj.organization_members m WHERE m.organization_id=org AND m.user_id=actor AND m.status='active' AND m.role IN('owner','admin','manager','member')) THEN RETURN jsonb_build_object('ok',false,'error','organization_write_required');END IF;
 SELECT id INTO prof FROM tj.profiles WHERE user_id=actor;
 IF prof IS NULL THEN RAISE EXCEPTION 'profile_required';END IF;
 SELECT store_id INTO sid FROM tj.iq_customer_waiting_queue WHERE id=wid AND organization_id=org;
 sid:=coalesce(sid,nullif(p_body->'waiting'->>'store_id','')::uuid);
 IF sid IS NULL OR NOT EXISTS(SELECT 1 FROM tj.org_locations WHERE id=sid AND organization_id=org AND is_active) OR NOT tj.aiq_store_allows(org,sid) THEN RETURN jsonb_build_object('ok',false,'error','store_unavailable');END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('up-floor:'||sid::text,0));
 PERFORM pg_advisory_xact_lock(hashtextextended('up-handoff:'||wid::text,0));
 SELECT * INTO w FROM tj.iq_customer_waiting_queue WHERE id=wid FOR UPDATE;
 IF NOT FOUND THEN
  IF act<>'log' THEN RAISE EXCEPTION 'waiting_unavailable';END IF;
  row_data:=p_body->'waiting';sid:=(row_data->>'store_id')::uuid;
  IF jsonb_typeof(row_data) IS DISTINCT FROM 'object' OR sid IS NULL OR NOT EXISTS(SELECT 1 FROM tj.org_locations WHERE id=sid AND organization_id=org AND is_active) OR NOT tj.aiq_store_allows(org,sid) THEN RAISE EXCEPTION 'store_unavailable';END IF;
  rep:=nullif(row_data->>'requested_employee_user_id','')::uuid;
  IF rep IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.profiles p JOIN tj.organization_members m ON m.user_id=p.user_id WHERE p.id=rep AND m.organization_id=org AND m.status='active' AND m.role IN('owner','admin','manager','member')) THEN RAISE EXCEPTION 'rep_unavailable';END IF;
  IF length(coalesce(row_data->>'customer_display_name',''))>200 OR length(coalesce(row_data->>'customer_needs',''))>4000 OR length(coalesce(row_data->>'customer_email',''))>254 OR length(coalesce(row_data->>'customer_phone',''))>50 OR coalesce((row_data->>'customer_group_size')::int,1) NOT BETWEEN 1 AND 30 THEN RAISE EXCEPTION 'invalid_request';END IF;
  INSERT INTO tj.iq_customer_waiting_queue(id,organization_id,store_id,entered_by,created_by,updated_by,customer_display_name,customer_phone,customer_email,customer_group_size,customer_category,lead_source,purchase_timeframe,customer_needs,requested_employee_user_id,status)
  VALUES(wid,org,sid,prof,actor,actor,nullif(row_data->>'customer_display_name',''),nullif(row_data->>'customer_phone',''),nullif(row_data->>'customer_email',''),coalesce((row_data->>'customer_group_size')::int,1),left(row_data->>'customer_category',100),left(row_data->>'lead_source',100),left(row_data->>'purchase_timeframe',100),row_data->>'customer_needs',rep,CASE WHEN rep IS NULL THEN 'waiting_for_assignment'::public.iq_customer_wait_status ELSE 'requested_employee'::public.iq_customer_wait_status END) RETURNING * INTO w;
  IF jsonb_typeof(p_body->'products') IS DISTINCT FROM 'array' OR jsonb_array_length(p_body->'products')>20 THEN RAISE EXCEPTION 'invalid_products';END IF;
  FOR product IN SELECT value FROM jsonb_array_elements(p_body->'products') LOOP
   IF jsonb_typeof(product)<>'object' OR length(coalesce(product->>'product_name',''))>500 OR length(coalesce(product->>'brand',''))>200 THEN RAISE EXCEPTION 'invalid_product';END IF;
   amount:=nullif(product->>'price','')::numeric;
   IF amount IS NOT NULL AND (amount<0 OR amount>99999999 OR amount::text IN('NaN','Infinity','-Infinity')) THEN RAISE EXCEPTION 'invalid_price';END IF;
   INSERT INTO tj.iq_customer_product_interest(organization_id,store_id,customer_waiting_id,category,brand,product_name,price,stock_status,delivery_date)
   VALUES(org,sid,wid,left(product->>'category',100),product->>'brand',product->>'product_name',amount,left(product->>'stock_status',100),nullif(product->>'delivery_date','')::date);
  END LOOP;
 END IF;
 IF w.organization_id<>org OR w.store_id IS NULL OR NOT tj.aiq_store_allows(org,w.store_id) OR (w.entered_by IS DISTINCT FROM prof AND w.assigned_user_id IS DISTINCT FROM prof AND w.requested_employee_user_id IS DISTINCT FROM prof AND NOT tj.is_org_admin(org)) THEN RETURN jsonb_build_object('ok',false,'error','waiting_unavailable');END IF;
 old_rep:=w.assigned_user_id;old_status:=w.status::text;
 IF act IN('assign','after_sale') AND old_status='completed' THEN
  IF act='after_sale' THEN RETURN jsonb_build_object('ok',true,'changed',false,'waiting',to_jsonb(w));END IF;
  RETURN jsonb_build_object('ok',false,'error','visit_completed');
 END IF;
 IF act='assign' THEN
  rep:=(p_body->>'rep_profile_id')::uuid;
  IF NOT EXISTS(SELECT 1 FROM tj.profiles p JOIN tj.organization_members m ON m.user_id=p.user_id WHERE p.id=rep AND m.organization_id=org AND m.status='active' AND m.role IN('owner','admin','manager','member')) THEN RAISE EXCEPTION 'rep_unavailable';END IF;
  IF w.assigned_user_id IS DISTINCT FROM rep OR w.status::text<>'with_salesperson' THEN
   SELECT id INTO v_shift_id FROM tj.iq_shift_records WHERE organization_id=org AND store_id=w.store_id AND user_id=rep AND is_active=true ORDER BY login_at DESC LIMIT 1;
   IF v_shift_id IS NULL THEN RETURN jsonb_build_object('ok',false,'error','active_shift_required');END IF;
   IF EXISTS(SELECT 1 FROM tj.iq_customer_interactions WHERE organization_id=org AND store_id=w.store_id AND salesperson_user_id=rep AND customer_waiting_id<>wid AND ended_at IS NULL) THEN RETURN jsonb_build_object('ok',false,'error','rep_with_customer');END IF;
   UPDATE tj.iq_customer_waiting_queue SET assigned_user_id=rep,status='with_salesperson',updated_by=actor WHERE id=wid RETURNING * INTO w;
   UPDATE tj.iq_customer_interactions SET ended_at=now(),outcome='reassigned',notes=left(p_body->>'reason',1000),updated_by=actor WHERE customer_waiting_id=wid AND organization_id=org AND ended_at IS NULL;
   INSERT INTO tj.iq_customer_interactions(organization_id,store_id,shift_id,customer_waiting_id,salesperson_user_id,interaction_source,started_at,accepted_at,created_by,updated_by) VALUES(org,w.store_id,v_shift_id,wid,rep,'walk_in',now(),now(),actor,actor);
   UPDATE tj.iq_up_queue_entries SET status_code='with_customer',is_available_for_assignment=false WHERE organization_id=org AND store_id=w.store_id AND user_id=rep AND is_in_queue=true;
   IF v_shift_id IS NOT NULL THEN
    UPDATE tj.iq_status_sessions SET ended_at=now() WHERE shift_id=v_shift_id AND organization_id=org AND user_id=rep AND ended_at IS NULL;
    INSERT INTO tj.iq_status_sessions(shift_id,organization_id,store_id,user_id,status,started_at,created_by) VALUES(v_shift_id,org,w.store_id,rep,'with_customer',now(),actor);
    UPDATE tj.iq_shift_records SET ups_accepted=coalesce(ups_accepted,0)+CASE WHEN coalesce((p_body->>'counts_as_up')::boolean,true) THEN 1 ELSE 0 END,customers_served=coalesce(customers_served,0)+1 WHERE id=v_shift_id;
   END IF;
  END IF;
  IF old_rep IS DISTINCT FROM rep THEN PERFORM tj_private.up_release_rep(org,w.store_id,old_rep,actor);END IF;
 END IF;
 -- Profile IDs belong to floor records; source user IDs belong to CRM ownership.
 SELECT user_id INTO owner_id FROM tj.profiles WHERE id=coalesce(w.assigned_user_id,w.requested_employee_user_id,w.entered_by);
 IF owner_id IS NULL OR NOT EXISTS(SELECT 1 FROM tj.organization_members WHERE organization_id=org AND user_id=owner_id AND status='active' AND role IN('owner','admin','manager','member')) THEN RAISE EXCEPTION 'owner_unavailable';END IF;
 c:=w.crm_contact_id;d:=w.crm_deal_id;
 IF c IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.contacts WHERE id=c AND organization_id=org AND deleted_at IS NULL) THEN RAISE EXCEPTION 'contact_unavailable';END IF;
 IF d IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.crm_deals WHERE id=d AND organization_id=org AND contact_id=c AND deleted_at IS NULL) THEN RAISE EXCEPTION 'deal_unavailable';END IF;
 name_text:=coalesce(nullif(btrim(w.customer_display_name),''),'Walk-in Customer');
 IF c IS NULL THEN
  INSERT INTO tj.contacts(organization_id,first_name,last_name,email,phone,mobile_phone,source,lifecycle_stage,assigned_salesperson_id,notes,contact_consent,metadata)
  VALUES(org,split_part(name_text,' ',1),nullif(btrim(substr(name_text,length(split_part(name_text,' ',1))+1)),''),w.customer_email,w.customer_phone,w.customer_phone,coalesce(w.lead_source,'walk_in'),'lead',coalesce(w.assigned_user_id,w.requested_employee_user_id,w.entered_by),w.customer_needs,false,jsonb_build_object('up_system_waiting_id',wid)) RETURNING id INTO c;
 END IF;
 IF d IS NULL THEN
  SELECT sum(price),array_agg(DISTINCT category) FILTER(WHERE category IS NOT NULL) INTO amount,cats FROM tj.iq_customer_product_interest WHERE customer_waiting_id=wid AND organization_id=org;
  INSERT INTO tj.crm_deals(organization_id,contact_id,owner_user_id,location_id,title,stage,value_amount,product_categories,source,traffic_source,stage_entered_at,metadata)
  VALUES(org,c,owner_id,w.store_id,name_text||' — Walk-In','Floor Visit / Demo',amount,cats,'walk_in',w.lead_source,now(),jsonb_build_object('up_system_waiting_id',wid,'store_id',w.store_id)) RETURNING id INTO d;
  INSERT INTO tj.crm_stage_history(deal_id,organization_id,to_stage,changed_by,notes) VALUES(d,org,'Floor Visit / Demo',prof,'Created from IQ Up System walk-in');
 END IF;
 IF act='assign' THEN
  UPDATE tj.crm_deals SET owner_user_id=owner_id WHERE id=d AND organization_id=org AND closed_at IS NULL;
  UPDATE tj.contacts SET assigned_salesperson_id=w.assigned_user_id WHERE id=c AND organization_id=org;
 END IF;
 IF act='after_sale' THEN
  IF jsonb_typeof(p_body->'closed') IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'invalid_outcome';END IF;
  UPDATE tj.iq_customer_interactions SET ended_at=now(),outcome=CASE WHEN (p_body->>'closed')::boolean THEN 'sale' ELSE 'no_sale' END,reason_not_purchased=CASE WHEN (p_body->>'closed')::boolean THEN NULL ELSE left(p_body->>'reason',1000) END,follow_up_date=nullif(p_body->>'follow_up_date','')::date,no_follow_up=coalesce((p_body->>'no_follow_up')::boolean,false),updated_by=actor WHERE organization_id=org AND customer_waiting_id=wid AND salesperson_user_id=w.assigned_user_id AND ended_at IS NULL;
  GET DIAGNOSTICS changed=ROW_COUNT;
  IF changed=0 THEN RAISE EXCEPTION 'active_visit_required';END IF;
  IF (p_body->>'closed')::boolean THEN UPDATE tj.iq_shift_records SET closed_sales=closed_sales+1,updated_by=actor WHERE organization_id=org AND store_id=w.store_id AND user_id=w.assigned_user_id AND is_active;END IF;
  UPDATE tj.iq_customer_waiting_queue SET status='completed',updated_by=actor WHERE id=wid RETURNING * INTO w;
  PERFORM tj_private.up_release_rep(org,w.store_id,w.assigned_user_id,actor);
  IF (p_body->>'closed')::boolean THEN UPDATE tj.crm_deals SET stage='Closed Won',closed_at=coalesce(closed_at,now()),purchase_date=coalesce(purchase_date,current_date) WHERE id=d AND organization_id=org;
  ELSE UPDATE tj.crm_deals SET next_action_date=CASE WHEN coalesce((p_body->>'no_follow_up')::boolean,false) THEN NULL ELSE nullif(p_body->>'follow_up_date','')::date END,follow_up_status=CASE WHEN coalesce((p_body->>'no_follow_up')::boolean,false) THEN 'no_follow_up' WHEN nullif(p_body->>'follow_up_date','') IS NOT NULL THEN 'scheduled' ELSE 'none' END,lost_reason=left(p_body->>'reason',1000),next_action=CASE WHEN coalesce((p_body->>'no_follow_up')::boolean,false) THEN NULL ELSE 'Follow up — '||left(coalesce(p_body->>'reason',''),1000) END WHERE id=d AND organization_id=org AND closed_at IS NULL;END IF;
 END IF;
 SELECT id INTO proj FROM tj.speciq_projects WHERE organization_id=org AND deal_id=d AND contact_id=c AND deleted_at IS NULL ORDER BY created_at,id LIMIT 1;
 IF proj IS NULL THEN INSERT INTO tj.speciq_projects(organization_id,customer_name,customer_email,customer_phone,project_name,contact_id,deal_id,created_by,notes) VALUES(org,name_text,w.customer_email,w.customer_phone,name_text||' — Walk-In Package',c,d,owner_id,'Auto-created from IQ Up System') RETURNING id INTO proj;END IF;
 SELECT id INTO pkg FROM tj.speciq_packages WHERE organization_id=org AND project_id=proj AND contact_id=c AND deal_id=d AND deleted_at IS NULL ORDER BY created_at,id LIMIT 1;
 IF pkg IS NULL THEN INSERT INTO tj.speciq_packages(organization_id,project_id,package_name,status,contact_id,deal_id,created_by,updated_by,total_msrp,total_promo,total_negotiated,total_tax,total_final,total_savings,total_services,volume_discount) VALUES(org,proj,name_text||' — Walk-In Package','draft',c,d,owner_id,actor,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL) RETURNING id INTO pkg;END IF;
 UPDATE tj.iq_customer_waiting_queue SET crm_contact_id=c,crm_deal_id=d,updated_by=actor WHERE id=wid;
 INSERT INTO tj.iq_integration_links(organization_id,store_id,iq_system_record_type,iq_system_record_id,crmai_record_type,crmai_record_id,external_system,sync_status,last_synced_at,updated_by,payload)
 VALUES(org,w.store_id,'customer_waiting',wid,'deal',d,'crm','synced',now(),actor,jsonb_build_object('project_id',proj,'package_id',pkg)) ON CONFLICT(organization_id,iq_system_record_type,iq_system_record_id,external_system) DO UPDATE SET sync_status='synced',crmai_record_id=excluded.crmai_record_id,last_synced_at=excluded.last_synced_at,payload=excluded.payload,updated_by=actor,last_error=NULL;
 PERFORM tj_private.up_recalc_queue(org,w.store_id);
 RETURN jsonb_build_object('ok',true,'waiting',to_jsonb(w)||jsonb_build_object('crm_contact_id',c,'crm_deal_id',d),'contact_id',c,'deal_id',d,'project_id',proj,'package_id',pkg);
EXCEPTION WHEN OTHERS THEN
 -- PL/pgSQL subtransaction rolls back every part of a failed handoff.
 RETURN jsonb_build_object('ok',false,'error','handoff_failed','sqlstate',SQLSTATE);
END $$;
