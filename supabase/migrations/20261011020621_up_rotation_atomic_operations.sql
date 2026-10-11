-- Store-level serialization keeps shifts, availability and offers consistent.
CREATE FUNCTION tj_private.up_recalc_queue(p_org uuid,p_store uuid) RETURNS void
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE first_id uuid;second_id uuid;
BEGIN
 WITH ranked AS (SELECT q.id,row_number() OVER(ORDER BY q.queue_position,q.join_order,q.id)::int n FROM tj.iq_up_queue_entries q WHERE q.organization_id=p_org AND q.store_id=p_store AND q.is_in_queue)
 UPDATE tj.iq_up_queue_entries q SET queue_position=r.n FROM ranked r WHERE q.id=r.id;
 SELECT q.id INTO first_id FROM tj.iq_up_queue_entries q JOIN tj.iq_shift_records s ON s.id=q.shift_id AND s.is_active
 WHERE q.organization_id=p_org AND q.store_id=p_store AND q.is_in_queue AND q.is_available_for_assignment AND NOT q.is_suspended AND q.status_code::text NOT IN('with_customer','ended_shift') AND NOT EXISTS(SELECT 1 FROM tj.iq_store_settings st WHERE st.organization_id=p_org AND st.store_id=p_store AND st.queue_skip_statuses ? q.status_code::text) ORDER BY q.queue_position,q.id LIMIT 1;
 SELECT q.id INTO second_id FROM tj.iq_up_queue_entries q JOIN tj.iq_shift_records s ON s.id=q.shift_id AND s.is_active
 WHERE q.organization_id=p_org AND q.store_id=p_store AND q.is_in_queue AND q.is_available_for_assignment AND NOT q.is_suspended AND q.status_code::text NOT IN('with_customer','ended_shift') AND q.id IS DISTINCT FROM first_id AND NOT EXISTS(SELECT 1 FROM tj.iq_store_settings st WHERE st.organization_id=p_org AND st.store_id=p_store AND st.queue_skip_statuses ? q.status_code::text) ORDER BY q.queue_position,q.id LIMIT 1;
 UPDATE tj.iq_up_queue_entries SET up_offered_at=CASE WHEN id=first_id THEN CASE WHEN is_current_up THEN up_offered_at ELSE now() END ELSE NULL END,is_current_up=coalesce(id=first_id,false),is_next_in_line=coalesce(id=second_id,false) WHERE organization_id=p_org AND store_id=p_store;
END $$;
REVOKE ALL ON FUNCTION tj_private.up_recalc_queue(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION tj_private.up_rotation(p_body jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=tj_private.current_source_user_id();prof uuid;org uuid;sid uuid;rep uuid;role_text text;act text;shift tj.iq_shift_records;q tj.iq_up_queue_entries;st tj.iq_store_settings;status_text text;pos int;joins boolean;boss boolean;prior_status text;next_q uuid;expected timestamptz;
BEGIN
 IF auth.uid() IS NULL OR actor IS NULL THEN RETURN jsonb_build_object('ok',false,'error','identity_required');END IF;
 IF jsonb_typeof(p_body) IS DISTINCT FROM 'object' OR octet_length(p_body::text)>4096 THEN RAISE EXCEPTION 'invalid_request';END IF;
 org:=(p_body->>'organization_id')::uuid;sid:=(p_body->>'store_id')::uuid;act:=p_body->>'action';
 SELECT id INTO prof FROM tj.profiles WHERE user_id=actor;
 IF prof IS NULL OR org IS NULL OR NOT tj_private.can_read_runtime_org(org) OR NOT EXISTS(SELECT 1 FROM tj.organization_members WHERE organization_id=org AND user_id=actor AND status='active' AND role IN('owner','admin','manager','member')) THEN RETURN jsonb_build_object('ok',false,'error','organization_write_required');END IF;
 IF act='profiles' THEN RETURN jsonb_build_object('ok',true,'profiles',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',p.id,'display_name',coalesce(nullif(p.full_name,''),p.email,'Staff'))),'[]'::jsonb) FROM tj.profiles p JOIN tj.organization_members m ON m.user_id=p.user_id WHERE m.organization_id=org AND m.status='active'));END IF;
 IF sid IS NULL OR NOT EXISTS(SELECT 1 FROM tj.org_locations WHERE id=sid AND organization_id=org) OR NOT tj.aiq_store_allows(org,sid) THEN RETURN jsonb_build_object('ok',false,'error','store_unavailable');END IF;
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
REVOKE ALL ON FUNCTION tj_private.up_rotation(jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION tj_private.up_rotation(jsonb) TO authenticated;
CREATE FUNCTION public.tj_runtime_up_rotation(p_body jsonb) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.up_rotation(p_body); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_up_rotation(jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.tj_runtime_up_rotation(jsonb) TO authenticated;

CREATE FUNCTION tj_private.up_release_rep(p_org uuid,p_store uuid,p_rep uuid,p_actor uuid) RETURNS void
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE v_shift uuid;pos int;
BEGIN
 IF p_rep IS NULL OR EXISTS(SELECT 1 FROM tj.iq_customer_interactions WHERE organization_id=p_org AND store_id=p_store AND salesperson_user_id=p_rep AND ended_at IS NULL) THEN RETURN;END IF;
 SELECT id INTO v_shift FROM tj.iq_shift_records WHERE organization_id=p_org AND store_id=p_store AND user_id=p_rep AND is_active ORDER BY login_at DESC LIMIT 1;
 IF v_shift IS NULL THEN RETURN;END IF;
 UPDATE tj.iq_status_sessions SET ended_at=now() WHERE organization_id=p_org AND shift_id=v_shift AND ended_at IS NULL;
 INSERT INTO tj.iq_status_sessions(shift_id,organization_id,store_id,user_id,status,created_by) VALUES(v_shift,p_org,p_store,p_rep,'available',p_actor);
 SELECT coalesce(max(queue_position),0)+1 INTO pos FROM tj.iq_up_queue_entries WHERE organization_id=p_org AND store_id=p_store AND is_in_queue;
 UPDATE tj.iq_up_queue_entries SET queue_position=pos,status_code='available',is_available_for_assignment=true,is_current_up=false,up_offered_at=NULL,updated_by=p_actor WHERE organization_id=p_org AND shift_id=v_shift AND is_in_queue;
END $$;
REVOKE ALL ON FUNCTION tj_private.up_release_rep(uuid,uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

-- Correct floor lifecycle while retaining the handoff API and historical records.
-- Atomic, scoped floor handoff; direct client writes remain restricted.
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
 IF sid IS NULL OR NOT EXISTS(SELECT 1 FROM tj.org_locations WHERE id=sid AND organization_id=org) OR NOT tj.aiq_store_allows(org,sid) THEN RETURN jsonb_build_object('ok',false,'error','store_unavailable');END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('up-floor:'||sid::text,0));
 PERFORM pg_advisory_xact_lock(hashtextextended('up-handoff:'||wid::text,0));
 SELECT * INTO w FROM tj.iq_customer_waiting_queue WHERE id=wid FOR UPDATE;
 IF NOT FOUND THEN
  IF act<>'log' THEN RAISE EXCEPTION 'waiting_unavailable';END IF;
  row_data:=p_body->'waiting';sid:=(row_data->>'store_id')::uuid;
  IF jsonb_typeof(row_data) IS DISTINCT FROM 'object' OR sid IS NULL OR NOT EXISTS(SELECT 1 FROM tj.org_locations WHERE id=sid AND organization_id=org) OR NOT tj.aiq_store_allows(org,sid) THEN RAISE EXCEPTION 'store_unavailable';END IF;
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
