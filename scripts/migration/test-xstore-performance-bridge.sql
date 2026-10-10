BEGIN; SET LOCAL statement_timeout='30s';
DO $$ DECLARE native uuid;source_actor uuid;org uuid;connector uuid;conn uuid;second uuid;loc uuid;code text;BEGIN
 SELECT im.target_user_id,im.source_user_id,m.organization_id INTO native,source_actor,org FROM tj.source_user_identity_map im JOIN tj.organization_members m ON m.user_id=im.source_user_id JOIN tj.organizations o ON o.id=m.organization_id WHERE im.activation_status='activated' AND m.status='active' AND m.role IN('owner','admin') AND o.status='active' AND o.deleted_at IS NULL LIMIT 1;
 SELECT id INTO connector FROM tj.platform_connectors WHERE key='oracle_xstore';IF native IS NULL OR connector IS NULL THEN RAISE EXCEPTION 'fixture_missing';END IF;
 INSERT INTO tj.org_locations(organization_id,location_type,name,code) VALUES(org,'store','Xstore bridge rollback store','xstore-bridge-'||gen_random_uuid()::text) RETURNING id INTO loc;
 INSERT INTO tj.platform_connector_connections(organization_id,connector_id,store_id,external_account_id,created_by) VALUES(org,connector,loc,'xstore-bridge-'||gen_random_uuid()::text,source_actor) RETURNING id INTO conn;
 INSERT INTO tj.platform_connector_connections(organization_id,connector_id,store_id,external_account_id,created_by) VALUES(org,connector,loc,'xstore-bridge-'||gen_random_uuid()::text,source_actor) RETURNING id INTO second;
 code:='rollback-'||gen_random_uuid()::text;
 INSERT INTO tj.iq_pos_employee_map(organization_id,store_id,salesperson_user_id,pos_employee_id,pos_system) VALUES(org,loc,source_actor,code,'oracle_xstore') ON CONFLICT(organization_id,salesperson_user_id,pos_system) DO UPDATE SET pos_employee_id=excluded.pos_employee_id,store_id=loc,is_active=true;
 INSERT INTO tj.platform_connector_match_queue(connection_id,organization_id,external_entity_type,external_id,external_code,candidate_type,candidate_id,status,reviewed_by,reviewed_at,metadata) VALUES(conn,org,'employee',code,code,'user',source_actor,'confirmed',source_actor,now(),'{"us_onboarding_reviewed":true}');
 INSERT INTO tj.platform_connector_match_queue(connection_id,organization_id,external_entity_type,external_id,candidate_type,candidate_id,status,reviewed_by,reviewed_at,metadata) VALUES(conn,org,'location','reviewed-store','location',loc,'confirmed',source_actor,now(),'{"us_onboarding_reviewed":true}');
 INSERT INTO tj.platform_connector_entity_map(connection_id,external_entity_type,external_id,local_entity_type,local_id,metadata) VALUES(conn,'location','reviewed-store','org_location',loc,'{"us_onboarding_reviewed":true}');
 PERFORM set_config('request.jwt.claim.sub',native::text,true);PERFORM set_config('test.bridge.native',native::text,true);PERFORM set_config('test.bridge.actor',source_actor::text,true);PERFORM set_config('test.bridge.connection',conn::text,true);PERFORM set_config('test.bridge.second',second::text,true);PERFORM set_config('test.bridge.org',org::text,true);PERFORM set_config('test.bridge.employee',code,true);PERFORM set_config('test.bridge.store',loc::text,true);
END $$;
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb;payload jsonb;body jsonb;conn text:=current_setting('test.bridge.connection');BEGIN
 r:=public.tj_xstore_performance_bridge(jsonb_build_object('connection_id',conn));IF r->>'processed'<>'0' THEN RAISE EXCEPTION 'empty_batch_failed';END IF;
 payload:=jsonb_build_object('transactionId','a','transactionDate','2026-09-01T12:00:00Z','employeeId',current_setting('test.bridge.employee'),'storeId','reviewed-store','total',120,'items',jsonb_build_array(jsonb_build_object('id','A','description','Appliance','qty',1,'unitPrice',100,'unitCost',50),jsonb_build_object('id','W','description','Warranty','qty',1,'unitPrice',20,'unitCost',0)));
 body:=jsonb_build_object('connection_id',conn,'external_entity_type','transaction','external_id','a','payload',payload);
 r:=public.tj_connector_ingest(body);IF r->>'ok'<>'true' THEN RAISE EXCEPTION 'fixture_ingest_failed: %',r;END IF;
 r:=public.tj_xstore_performance_bridge(jsonb_build_object('connection_id',conn));IF r->>'processed'<>'1' OR r->>'lines'<>'2' OR r->>'mapped_reps'<>'1' OR r->>'metrics_refreshed'<>'false' THEN RAISE EXCEPTION 'initial_bridge_failed: %',r;END IF;
 r:=public.tj_xstore_performance_bridge(jsonb_build_object('connection_id',conn));IF r->>'processed'<>'1' THEN RAISE EXCEPTION 'repeat_failed: %',r;END IF;
 -- Revised explicit zero total and one remaining line must replace all prior facts.
 payload:=jsonb_build_object('transactionId','a','transactionDate','2026-09-01T12:00:00Z','employeeId',current_setting('test.bridge.employee'),'storeId','reviewed-store','total',0,'items',jsonb_build_array(jsonb_build_object('id','A','description','Appliance','qty',1,'unitPrice',100,'unitCost',0)));
 r:=public.tj_connector_ingest(body||jsonb_build_object('payload',payload));IF r->>'ok'<>'true' THEN RAISE EXCEPTION 'revision_ingest_failed';END IF;
 r:=public.tj_xstore_performance_bridge(jsonb_build_object('connection_id',conn));IF r->>'processed'<>'1' OR r->>'lines'<>'1' THEN RAISE EXCEPTION 'revision_bridge_failed: %',r;END IF;
 r:=public.tj_connector_ingest(body||jsonb_build_object('connection_id',current_setting('test.bridge.second'),'payload',jsonb_build_object('transactionId','a','transactionDate','2026-09-01T12:00:00Z','total',10,'items',jsonb_build_array(jsonb_build_object('id','A','description','Appliance','unitPrice',10)))));IF r->>'ok'<>'true' THEN RAISE EXCEPTION 'second_ingest_failed';END IF;
 r:=public.tj_xstore_performance_bridge(jsonb_build_object('connection_id',current_setting('test.bridge.second')));IF r->>'processed'<>'1' THEN RAISE EXCEPTION 'second_bridge_failed: %',r;END IF;
 -- Numeric rejection is per invoice and does not abort other valid invoices in the page.
 r:=public.tj_connector_ingest(body||jsonb_build_object('external_id','b','payload',jsonb_build_object('transactionId','b','transactionDate','2026-09-01T12:00:00Z','items',jsonb_build_array(jsonb_build_object('id','A','description','Appliance','unitPrice','nonsense')))));IF r->>'ok'<>'true' THEN RAISE EXCEPTION 'invalid_numeric_fixture_ingest_failed';END IF;
 r:=public.tj_xstore_performance_bridge(jsonb_build_object('connection_id',conn,'limit',1));IF r->>'next_cursor'<>'a' OR r->>'processed'<>'1' THEN RAISE EXCEPTION 'pagination_failed: %',r;END IF;
 r:=public.tj_xstore_performance_bridge(jsonb_build_object('connection_id',conn,'after_external_id','a'));IF r->>'failed'<>'1' OR r->>'processed'<>'0' THEN RAISE EXCEPTION 'numeric_guard_failed: %',r;END IF;
 BEGIN PERFORM public.tj_xstore_performance_bridge(jsonb_build_object('connection_id',gen_random_uuid()));RAISE EXCEPTION 'foreign_connection_accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);BEGIN PERFORM public.tj_xstore_performance_bridge(jsonb_build_object('connection_id',conn));RAISE EXCEPTION 'unmapped_accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;PERFORM set_config('request.jwt.claim.sub',current_setting('test.bridge.native'),true);
END $$;
RESET ROLE;
DO $$ DECLARE conn uuid:=current_setting('test.bridge.connection')::uuid;tx uuid;BEGIN
 SELECT id INTO tx FROM tj.iq_pos_transactions WHERE source_connection_id=conn;IF tx IS NULL OR (SELECT count(*) FROM tj.iq_pos_transactions WHERE source_connection_id=conn)<>1 THEN RAISE EXCEPTION 'duplicate_invoice_or_partial_bad_row';END IF;
 IF (SELECT transaction_amount FROM tj.iq_pos_transactions WHERE id=tx)<>0 OR (SELECT cost_amount FROM tj.iq_pos_transactions WHERE id=tx)<>0 THEN RAISE EXCEPTION 'explicit_zero_lost';END IF;
 IF (SELECT count(*) FROM tj.iq_transaction_line_facts WHERE transaction_id=tx)<>1 THEN RAISE EXCEPTION 'stale_line_facts';END IF;
 IF (SELECT count(*) FROM tj.sales_transactions WHERE metadata->>'source_connection_id'=conn::text)<>1 OR NOT EXISTS(SELECT 1 FROM tj.sales_transactions WHERE metadata->>'source_connection_id'=conn::text AND user_id=current_setting('test.bridge.actor')::uuid AND warranty_offered IS NULL AND warranty_value=0) THEN RAISE EXCEPTION 'sales_or_reviewed_mapping_failed';END IF;
 IF (SELECT cost_amount FROM tj.iq_pos_transactions WHERE source_connection_id=current_setting('test.bridge.second')::uuid) IS NOT NULL THEN RAISE EXCEPTION 'unknown_cost_invented';END IF;
 -- A later failed revision must not delete the existing transaction or its lines.
 UPDATE tj.intelligence_events SET payload=payload||jsonb_build_object('storeId','unreviewed-store') WHERE id=(SELECT ev.id FROM tj.platform_connector_ingestion_keys k JOIN tj.intelligence_events ev ON ev.id=k.intelligence_event_id WHERE k.connection_id=conn AND k.external_id='a' ORDER BY ev.created_at DESC,ev.id DESC LIMIT 1);
END $$;
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb;BEGIN r:=public.tj_xstore_performance_bridge(jsonb_build_object('connection_id',current_setting('test.bridge.connection')));IF r->>'failed'<>'2' THEN RAISE EXCEPTION 'unreviewed_location_accepted: %',r;END IF;END $$;
RESET ROLE;
DO $$ BEGIN
 INSERT INTO tj.sales_transactions(organization_id,invoice_number,order_total,metadata) VALUES(current_setting('test.bridge.org')::uuid,'oracle_xstore:'||current_setting('test.bridge.connection')||':c',7,jsonb_build_object('source_connection_id',current_setting('test.bridge.second')));
END $$;
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb;BEGIN
 r:=public.tj_connector_ingest(jsonb_build_object('connection_id',current_setting('test.bridge.connection'),'external_entity_type','transaction','external_id','c','payload',jsonb_build_object('transactionId','c','transactionDate','2026-09-01T12:00:00Z','items',jsonb_build_array(jsonb_build_object('id','C','unitPrice',30,'unitCost',0)))));IF r->>'ok'<>'true' THEN RAISE EXCEPTION 'conflict_fixture_failed';END IF;
 r:=public.tj_xstore_performance_bridge(jsonb_build_object('connection_id',current_setting('test.bridge.connection'),'after_external_id','b'));IF r->>'failed'<>'1' OR r#>>'{errors,0,error}'<>'transaction_mapping_or_scope_rejected' THEN RAISE EXCEPTION 'sales_scope_conflict_accepted: %',r;END IF;
END $$;
RESET ROLE;
DO $$ BEGIN
 IF (SELECT count(*) FROM tj.iq_pos_transactions WHERE source_connection_id=current_setting('test.bridge.connection')::uuid)<>1 OR (SELECT order_total FROM tj.sales_transactions WHERE organization_id=current_setting('test.bridge.org')::uuid AND invoice_number='oracle_xstore:'||current_setting('test.bridge.connection')||':c')<>7 THEN RAISE EXCEPTION 'post_pos_failure_not_atomic';END IF;
END $$;

-- Oracle-specific strict dates/identity, single-object lines, zero amounts and header cost.
DO $$ DECLARE ev uuid;original jsonb;bad jsonb;r jsonb;second uuid:=current_setting('test.bridge.second')::uuid;BEGIN
 SELECT e.id,e.payload INTO ev,original FROM tj.platform_connector_ingestion_keys k JOIN tj.intelligence_events e ON e.id=k.intelligence_event_id WHERE k.connection_id=second AND k.external_id='a' ORDER BY e.created_at DESC LIMIT 1;
 FOR bad IN SELECT value FROM jsonb_array_elements(jsonb_build_array(
  original-'transactionDate',
  original||'{"transactionDate":"2026-09-01T12:00:00"}',
  original||'{"transactionDate":"2026-02-30"}',
  original||'{"transactionId":"wrong"}',
  original-'transactionId',
  original||jsonb_build_object('connector_connection_id',gen_random_uuid()),
  original||'{"items":[{"unitPrice":10,"qty":0.5}]}',
  original||'{"items":[{"id":"dup","unitPrice":10},{"id":"dup","unitPrice":10}]}',
  original||'{"RetailTransaction":{"Sale":{"ItemID":"nested"}},"items":[]}'
 )) LOOP
  UPDATE tj.intelligence_events SET payload=bad WHERE id=ev;
  r:=public.tj_xstore_performance_bridge(jsonb_build_object('connection_id',second));IF r->>'failed'<>'1' OR r->>'processed'<>'0' THEN RAISE EXCEPTION 'oracle_invalid_contract_accepted: %',r;END IF;
  IF (SELECT transaction_amount FROM tj.iq_pos_transactions WHERE source_connection_id=second)<>10 THEN RAISE EXCEPTION 'bad_revision_changed_prior_facts';END IF;
 END LOOP;
 UPDATE tj.intelligence_events SET payload=original||jsonb_build_object('total',0,'subtotal',0,'costAmount',5,'employeeId',current_setting('test.bridge.employee'),'items',jsonb_build_object('id','zero','amount',0,'unitPrice',10,'unitCost',0)) WHERE id=ev;
 r:=public.tj_xstore_performance_bridge(jsonb_build_object('connection_id',second));IF r->>'processed'<>'1' OR r->>'lines'<>'1' OR r->>'mapped_reps'<>'0' THEN RAISE EXCEPTION 'oracle_object_or_cross_connection_mapping_failed: %',r;END IF;
 IF NOT EXISTS(SELECT 1 FROM tj.iq_pos_transactions WHERE source_connection_id=second AND transaction_amount=0 AND subtotal=0 AND cost_amount=5) OR NOT EXISTS(SELECT 1 FROM tj.iq_transaction_line_facts WHERE source_connection_id=second AND line_amount=0 AND unit_cost=0 AND line_cost=0) THEN RAISE EXCEPTION 'oracle_zero_or_header_cost_failed';END IF;
END $$;
DO $$ BEGIN
 IF (SELECT count(*) FROM tj.iq_transaction_line_facts WHERE source_connection_id=current_setting('test.bridge.connection')::uuid)<>1 THEN RAISE EXCEPTION 'failed_revision_not_atomic';END IF;
 UPDATE tj.organization_members SET role='member' WHERE organization_id=current_setting('test.bridge.org')::uuid AND user_id=current_setting('test.bridge.actor')::uuid;
 IF has_function_privilege('anon','public.tj_xstore_performance_bridge(jsonb)','EXECUTE') OR has_function_privilege('service_role','public.tj_xstore_performance_bridge(jsonb)','EXECUTE') THEN RAISE EXCEPTION 'unsafe_grants';END IF;
END $$;
SET LOCAL ROLE authenticated;
DO $$ BEGIN BEGIN PERFORM public.tj_xstore_performance_bridge(jsonb_build_object('connection_id',current_setting('test.bridge.connection')));RAISE EXCEPTION 'nonadmin_accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;END $$;
RESET ROLE;
ROLLBACK;
