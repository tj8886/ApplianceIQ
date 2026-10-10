BEGIN; SET LOCAL statement_timeout='30s';
DO $$ DECLARE native uuid; actor uuid; org uuid; foreign_org uuid; project uuid:=gen_random_uuid(); package uuid:=gen_random_uuid(); product uuid:=gen_random_uuid(); BEGIN
  SELECT im.target_user_id,im.source_user_id,m.organization_id INTO native,actor,org FROM tj.source_user_identity_map im JOIN tj.organization_members m ON m.user_id=im.source_user_id JOIN tj.organizations o ON o.id=m.organization_id WHERE im.activation_status='activated' AND m.status='active' AND m.role IN('owner','admin') AND o.status='active' AND o.deleted_at IS NULL LIMIT 1;
  SELECT id INTO foreign_org FROM tj.organizations WHERE id<>org LIMIT 1;
  IF native IS NULL OR foreign_org IS NULL THEN RAISE EXCEPTION 'missing_fixture'; END IF;
  INSERT INTO tj.speciq_projects(id,organization_id,customer_name,project_name) VALUES(project,org,'PRIVATE-ROLLBACK-CUSTOMER','Rollback draft preview');
  INSERT INTO tj.speciq_packages(id,organization_id,project_id,package_name,created_by,volume_discount) VALUES(package,org,project,'Rollback quote',actor,7.50);
  INSERT INTO tj.speciq_package_products(id,package_id,organization_id,product_name,quantity,negotiated_price,promo_price,msrp) VALUES(product,package,org,'Rollback product',2,119.95,150.00,200.00);
  INSERT INTO tj.speciq_package_services(package_id,organization_id,service_type,description,amount,cost) VALUES(package,org,'delivery','Delivery',25.50,12.00);
  PERFORM set_config('request.jwt.claim.sub',native::text,true);PERFORM set_config('test.draft.native',native::text,true);PERFORM set_config('test.draft.actor',actor::text,true);PERFORM set_config('test.draft.org',org::text,true);PERFORM set_config('test.draft.foreign',foreign_org::text,true);PERFORM set_config('test.draft.package',package::text,true);PERFORM set_config('test.draft.product',product::text,true);
END $$;
DO $$ DECLARE connection uuid:=gen_random_uuid();second_package uuid:=gen_random_uuid();BEGIN
 INSERT INTO tj.platform_connector_connections(id,organization_id,connector_id,display_name,created_by,external_account_id) VALUES(connection,current_setting('test.draft.org')::uuid,(SELECT id FROM tj.platform_connectors WHERE key='shopify'),'Rollback draft claim',current_setting('test.draft.actor')::uuid,gen_random_uuid()::text);
 INSERT INTO tj.speciq_packages(id,organization_id,project_id,package_name) SELECT second_package,organization_id,project_id,'Rollback second claim' FROM tj.speciq_packages WHERE id=current_setting('test.draft.package')::uuid;
 PERFORM set_config('test.draft.connection',connection::text,true);PERFORM set_config('test.draft.second',second_package::text,true);
END $$;
SET LOCAL ROLE service_role;
DO $$ DECLARE native uuid:=current_setting('test.draft.native')::uuid;body jsonb;event jsonb;a jsonb;b jsonb;f text;BEGIN
 body:=jsonb_build_object('action','prepare','organization_id',current_setting('test.draft.org'),'package_id',current_setting('test.draft.package'),'connection_id',current_setting('test.draft.connection'),'request_id',gen_random_uuid(),'payload_hash',repeat('a',64));
 a:=public.aiq_shopify_draft_attempt(native,body);b:=public.aiq_shopify_draft_attempt(native,body);
 IF a->>'state'<>'prepared' OR a->>'attempt_id'<>b->>'attempt_id' OR a->>'fence'<>b->>'fence' OR a->>'provider_execution_enabled'<>'false' THEN RAISE EXCEPTION 'retry_not_idempotent';END IF;
 BEGIN PERFORM public.aiq_shopify_draft_attempt(native,body||jsonb_build_object('payload_hash',repeat('b',64)));RAISE EXCEPTION 'request_key_reuse_accepted';EXCEPTION WHEN serialization_failure THEN NULL;END;
 BEGIN PERFORM public.aiq_shopify_draft_attempt(native,body||jsonb_build_object('request_id',gen_random_uuid()));RAISE EXCEPTION 'duplicate_package_claim';EXCEPTION WHEN serialization_failure THEN NULL;END;
 BEGIN PERFORM public.aiq_shopify_draft_attempt(gen_random_uuid(),body);RAISE EXCEPTION 'unmapped_actor_accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN PERFORM public.aiq_shopify_draft_attempt(native,body||jsonb_build_object('organization_id',current_setting('test.draft.foreign')));RAISE EXCEPTION 'foreign_org_accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 event:=(body-'request_id'-'payload_hash')||jsonb_build_object('attempt_id',a->>'attempt_id','fence',a->>'fence','action','start');
 BEGIN PERFORM public.aiq_shopify_draft_attempt(native,event||jsonb_build_object('fence',gen_random_uuid()));RAISE EXCEPTION 'stale_worker_accepted';EXCEPTION WHEN serialization_failure THEN NULL;END;
 b:=public.aiq_shopify_draft_attempt(native,event);IF b->>'state'<>'dispatched' THEN RAISE EXCEPTION 'dispatch_missing';END IF;
 BEGIN PERFORM public.aiq_shopify_draft_attempt(native,event);RAISE EXCEPTION 'dispatch_replayed';EXCEPTION WHEN serialization_failure THEN NULL;END;
 b:=public.aiq_shopify_draft_attempt(native,event||jsonb_build_object('action','uncertain'));IF b->>'state'<>'unknown' THEN RAISE EXCEPTION 'uncertainty_not_retained';END IF;
 FOREACH f IN ARRAY ARRAY['start','cancel','reject'] LOOP
  BEGIN PERFORM public.aiq_shopify_draft_attempt(native,event||jsonb_build_object('action',f,'response_hash',repeat('c',64)));RAISE EXCEPTION 'unknown_attempt_released';EXCEPTION WHEN serialization_failure THEN NULL;END;
 END LOOP;
 BEGIN PERFORM public.aiq_shopify_draft_attempt(native,body||jsonb_build_object('request_id',gen_random_uuid()));RAISE EXCEPTION 'unknown_retry_created_duplicate';EXCEPTION WHEN serialization_failure THEN NULL;END;
 b:=public.aiq_shopify_draft_attempt(native,event||jsonb_build_object('action','confirm','draft_id','gid://shopify/DraftOrder/999999999999999999999','response_hash',repeat('c',64)));
 IF b->>'state'<>'succeeded' OR b->>'provider_draft_id'<>'gid://shopify/DraftOrder/999999999999999999999' THEN RAISE EXCEPTION 'reconciliation_or_id_precision_failed';END IF;
 b:=public.aiq_shopify_draft_attempt(native,event||jsonb_build_object('action','confirm','draft_id','gid://shopify/DraftOrder/999999999999999999999','response_hash',repeat('c',64)));
 BEGIN PERFORM public.aiq_shopify_draft_attempt(native,event||jsonb_build_object('action','confirm','draft_id','gid://shopify/DraftOrder/123','response_hash',repeat('c',64)));RAISE EXCEPTION 'conflicting_completion_accepted';EXCEPTION WHEN serialization_failure THEN NULL;END;
 body:=body||jsonb_build_object('package_id',current_setting('test.draft.second'),'request_id',gen_random_uuid());
 a:=public.aiq_shopify_draft_attempt(native,body);
 PERFORM set_config('test.draft.attempt',a->>'attempt_id',true);PERFORM set_config('test.draft.fence',a->>'fence',true);PERFORM set_config('test.draft.request',body->>'request_id',true);
END $$;
RESET ROLE;
UPDATE tj_private.shopify_draft_attempts SET expires_at=clock_timestamp()-interval '1 minute' WHERE id=current_setting('test.draft.attempt')::uuid;
SET LOCAL ROLE service_role;
DO $$ DECLARE body jsonb;native uuid:=current_setting('test.draft.native')::uuid;r jsonb;BEGIN
 body:=jsonb_build_object('action','start','organization_id',current_setting('test.draft.org'),'package_id',current_setting('test.draft.second'),'connection_id',current_setting('test.draft.connection'),'attempt_id',current_setting('test.draft.attempt'),'fence',current_setting('test.draft.fence'));
 BEGIN PERFORM public.aiq_shopify_draft_attempt(native,body);RAISE EXCEPTION 'expired_dispatch_accepted';EXCEPTION WHEN serialization_failure THEN NULL;END;
 r:=public.aiq_shopify_draft_attempt(native,body||jsonb_build_object('action','cancel'));IF r->>'state'<>'cancelled' THEN RAISE EXCEPTION 'predispatch_cancel_failed';END IF;
 r:=public.aiq_shopify_draft_attempt(native,(body-'attempt_id'-'fence')||jsonb_build_object('action','prepare','request_id',gen_random_uuid(),'payload_hash',repeat('d',64)));
 PERFORM set_config('test.draft.attempt',r->>'attempt_id',true);PERFORM set_config('test.draft.fence',r->>'fence',true);
END $$;
RESET ROLE;
UPDATE tj.speciq_packages SET package_name='Changed after claim' WHERE id=current_setting('test.draft.second')::uuid;
SET LOCAL ROLE service_role;
DO $$ BEGIN
 BEGIN PERFORM public.aiq_shopify_draft_attempt(current_setting('test.draft.native')::uuid,jsonb_build_object('action','start','organization_id',current_setting('test.draft.org'),'package_id',current_setting('test.draft.second'),'connection_id',current_setting('test.draft.connection'),'attempt_id',current_setting('test.draft.attempt'),'fence',current_setting('test.draft.fence')));RAISE EXCEPTION 'changed_package_dispatched';EXCEPTION WHEN serialization_failure THEN NULL;END;
END $$;
RESET ROLE;
DO $$ DECLARE f text;r text;BEGIN
 FOREACH f IN ARRAY ARRAY['public.aiq_shopify_draft_attempt(uuid,jsonb)','tj_private.shopify_draft_attempt(uuid,jsonb)'] LOOP FOREACH r IN ARRAY ARRAY['anon','authenticated'] LOOP IF has_function_privilege(r,f,'EXECUTE') THEN RAISE EXCEPTION 'unsafe_client_rpc_grant';END IF;END LOOP;END LOOP;
 IF EXISTS(SELECT 1 FROM tj.speciq_packages WHERE id IN(current_setting('test.draft.package')::uuid,current_setting('test.draft.second')::uuid) AND (shopify_draft_order_id IS NOT NULL OR shopify_pushed_at IS NOT NULL)) THEN RAISE EXCEPTION 'journal_wrote_business_marker';END IF;
 IF (SELECT count(*) FROM tj_private.shopify_draft_events WHERE attempt_id IN(SELECT id FROM tj_private.shopify_draft_attempts WHERE package_id=current_setting('test.draft.package')::uuid))<>4 THEN RAISE EXCEPTION 'audit_not_idempotent';END IF;
END $$;
ROLLBACK;
SELECT 'PASS: idempotent claims, one package slot, fencing, no dispatch replay, uncertainty retained, reconciliation, exact provider IDs, expiry/cancellation, stale-package denial, private grants and audit; fixtures rolled back' result;
