DO $$
DECLARE native uuid;actor uuid;prof uuid;org uuid;sid uuid;wid uuid:=gen_random_uuid();r jsonb;r2 jsonb;payload jsonb;other_org uuid;before_n bigint;
BEGIN
 SELECT im.target_user_id,im.source_user_id,p.id,m.organization_id,l.id INTO native,actor,prof,org,sid
 FROM tj.source_user_identity_map im JOIN tj.profiles p ON p.user_id=im.source_user_id JOIN tj.organization_members m ON m.user_id=im.source_user_id JOIN tj.organizations o ON o.id=m.organization_id JOIN tj.org_locations l ON l.organization_id=o.id
 WHERE im.activation_status='activated' AND m.status='active' AND m.role IN('owner','admin') AND o.status='active' AND o.deleted_at IS NULL LIMIT 1;
 IF sid IS NULL THEN RAISE EXCEPTION 'fixture_unavailable';END IF;
 PERFORM set_config('request.jwt.claim.sub',native::text,true);
 INSERT INTO tj.iq_shift_records(organization_id,store_id,user_id,is_active,created_by,updated_by) VALUES(org,sid,prof,true,actor,actor);
 payload:=jsonb_build_object('action','log','organization_id',org,'waiting_id',wid,'waiting',jsonb_build_object('store_id',sid,'customer_display_name','Rollback UP Customer','customer_email','fixture@example.test','customer_group_size',1,'requested_employee_user_id',prof),'products',jsonb_build_array(jsonb_build_object('product_name','Fixture appliance','category','dishwasher','price',123.45)));
 EXECUTE 'SET LOCAL ROLE authenticated';
 r:=public.tj_runtime_up_crm_handoff(payload);
 EXECUTE 'RESET ROLE';
 IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'handoff failed: %',r;END IF;
 IF NOT EXISTS(SELECT 1 FROM tj.iq_customer_waiting_queue w JOIN tj.contacts c ON c.id=w.crm_contact_id JOIN tj.crm_deals d ON d.id=w.crm_deal_id JOIN tj.speciq_projects p ON p.deal_id=d.id JOIN tj.speciq_packages k ON k.project_id=p.id WHERE w.id=wid AND c.assigned_salesperson_id=prof AND d.owner_user_id=actor AND d.location_id=sid AND d.value_amount=123.45 AND k.status='draft' AND k.total_final IS NULL) THEN RAISE EXCEPTION 'link/identity/pricing failure';END IF;
 r2:=public.tj_runtime_up_crm_handoff(payload);IF r2->>'deal_id'<>r->>'deal_id' OR r2->>'package_id'<>r->>'package_id' OR (SELECT count(*) FROM tj.iq_customer_product_interest WHERE customer_waiting_id=wid)<>1 THEN RAISE EXCEPTION 'duplicate retry';END IF;
 r2:=public.tj_runtime_up_crm_handoff(jsonb_build_object('action','assign','organization_id',org,'waiting_id',wid,'rep_profile_id',prof));IF r2->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'assignment failed: %',r2;END IF;
 r2:=public.tj_runtime_up_crm_handoff(jsonb_build_object('action','after_sale','organization_id',org,'waiting_id',wid,'closed',true));
 IF r2->>'ok'<>'true' OR NOT EXISTS(SELECT 1 FROM tj.crm_deals WHERE id=(r->>'deal_id')::uuid AND stage='Closed Won') THEN RAISE EXCEPTION 'outcome failed';END IF;
 SELECT id INTO other_org FROM tj.organizations WHERE id<>org LIMIT 1;
 r2:=public.tj_runtime_up_crm_handoff(payload||jsonb_build_object('organization_id',other_org,'action','sync'));IF r2->>'ok'='true' THEN RAISE EXCEPTION 'foreign org allowed';END IF;
 SELECT count(*) INTO before_n FROM tj.iq_customer_waiting_queue;
 r2:=public.tj_runtime_up_crm_handoff(payload||jsonb_build_object('waiting_id',gen_random_uuid(),'products',jsonb_build_array(jsonb_build_object('price',-1))));
 IF r2->>'ok'='true' OR (SELECT count(*) FROM tj.iq_customer_waiting_queue)<>before_n THEN RAISE EXCEPTION 'failed handoff left partial row';END IF;
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 r2:=public.tj_runtime_up_crm_handoff(payload);IF r2->>'ok'='true' THEN RAISE EXCEPTION 'unmapped permitted';END IF;
END $$;
SELECT jsonb_build_object('passed',true,'test','Atomic UP CRM Spec IQ linkage, retries, sale outcome, scope denial and failure rollback','persisted_fixture_rows',0) AS verification;
