-- Atomic, scoped floor handoff; direct client writes remain restricted.
CREATE FUNCTION tj_private.up_crm_handoff(p_body jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=tj_private.current_source_user_id(); org uuid; sid uuid; wid uuid;
 prof uuid; rep uuid; owner_id uuid; w tj.iq_customer_waiting_queue; c uuid; d uuid; proj uuid; pkg uuid;
 row_data jsonb; product jsonb; name_text text; amount numeric; cats text[]; act text; v_shift_id uuid; changed integer;
BEGIN
 IF auth.uid() IS NULL OR actor IS NULL THEN RETURN jsonb_build_object('ok',false,'error','identity_required');END IF;
 IF jsonb_typeof(p_body) IS DISTINCT FROM 'object' OR octet_length(p_body::text)>32768 THEN RAISE EXCEPTION 'invalid_request';END IF;
 act:=p_body->>'action';org:=(p_body->>'organization_id')::uuid;wid:=(p_body->>'waiting_id')::uuid;
 IF act IS NULL OR act NOT IN('log','sync','assign','after_sale') OR org IS NULL OR wid IS NULL THEN RAISE EXCEPTION 'invalid_request';END IF;
 IF NOT tj_private.can_read_runtime_org(org) OR NOT EXISTS(SELECT 1 FROM tj.organization_members m WHERE m.organization_id=org AND m.user_id=actor AND m.status='active' AND m.role IN('owner','admin','manager','member')) THEN RETURN jsonb_build_object('ok',false,'error','organization_write_required');END IF;
 SELECT id INTO prof FROM tj.profiles WHERE user_id=actor;
 IF prof IS NULL THEN RAISE EXCEPTION 'profile_required';END IF;
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
 IF act='assign' THEN
  rep:=(p_body->>'rep_profile_id')::uuid;
  IF NOT EXISTS(SELECT 1 FROM tj.profiles p JOIN tj.organization_members m ON m.user_id=p.user_id WHERE p.id=rep AND m.organization_id=org AND m.status='active' AND m.role IN('owner','admin','manager','member')) THEN RAISE EXCEPTION 'rep_unavailable';END IF;
  IF w.assigned_user_id IS DISTINCT FROM rep OR w.status::text<>'with_salesperson' THEN
   SELECT id INTO v_shift_id FROM tj.iq_shift_records WHERE organization_id=org AND store_id=w.store_id AND user_id=rep AND is_active=true ORDER BY login_at DESC LIMIT 1;
   UPDATE tj.iq_customer_waiting_queue SET assigned_user_id=rep,status='with_salesperson',updated_by=actor WHERE id=wid RETURNING * INTO w;
   UPDATE tj.iq_customer_interactions SET ended_at=now() WHERE customer_waiting_id=wid AND organization_id=org AND ended_at IS NULL;
   INSERT INTO tj.iq_customer_interactions(organization_id,store_id,shift_id,customer_waiting_id,salesperson_user_id,interaction_source,started_at,accepted_at,created_by,updated_by) VALUES(org,w.store_id,v_shift_id,wid,rep,'walk_in',now(),now(),actor,actor);
   UPDATE tj.iq_up_queue_entries SET status_code='with_customer',is_available_for_assignment=false WHERE organization_id=org AND store_id=w.store_id AND user_id=rep AND is_in_queue=true;
   IF v_shift_id IS NOT NULL THEN
    UPDATE tj.iq_status_sessions SET ended_at=now() WHERE shift_id=v_shift_id AND organization_id=org AND user_id=rep AND ended_at IS NULL;
    INSERT INTO tj.iq_status_sessions(shift_id,organization_id,store_id,user_id,status,started_at,created_by) VALUES(v_shift_id,org,w.store_id,rep,'with_customer',now(),actor);
    UPDATE tj.iq_shift_records SET ups_accepted=coalesce(ups_accepted,0)+CASE WHEN coalesce((p_body->>'counts_as_up')::boolean,true) THEN 1 ELSE 0 END,customers_served=coalesce(customers_served,0)+1 WHERE id=v_shift_id;
   END IF;
  END IF;
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
 RETURN jsonb_build_object('ok',true,'waiting',to_jsonb(w)||jsonb_build_object('crm_contact_id',c,'crm_deal_id',d),'contact_id',c,'deal_id',d,'project_id',proj,'package_id',pkg);
EXCEPTION WHEN OTHERS THEN
 -- PL/pgSQL subtransaction rolls back every part of a failed handoff.
 RETURN jsonb_build_object('ok',false,'error','handoff_failed','sqlstate',SQLSTATE);
END $$;
REVOKE ALL ON FUNCTION tj_private.up_crm_handoff(jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION tj_private.up_crm_handoff(jsonb) TO authenticated;
CREATE FUNCTION public.tj_runtime_up_crm_handoff(p_body jsonb) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.up_crm_handoff(p_body); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_up_crm_handoff(jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.tj_runtime_up_crm_handoff(jsonb) TO authenticated;
