BEGIN; SET LOCAL statement_timeout='30s';
DO $$ DECLARE native uuid;source_actor uuid;org uuid;connector uuid;conn uuid;second uuid;loc uuid;code text;BEGIN
 SELECT im.target_user_id,im.source_user_id,m.organization_id INTO native,source_actor,org FROM tj.source_user_identity_map im JOIN tj.organization_members m ON m.user_id=im.source_user_id JOIN tj.organizations o ON o.id=m.organization_id WHERE im.activation_status='activated' AND m.status='active' AND m.role IN('owner','admin') AND o.status='active' AND o.deleted_at IS NULL LIMIT 1;
 SELECT id INTO connector FROM tj.platform_connectors WHERE key='epass';IF native IS NULL OR connector IS NULL THEN RAISE EXCEPTION 'fixture_missing';END IF;
 INSERT INTO tj.org_locations(organization_id,location_type,name,code) VALUES(org,'store','Bridge rollback store','bridge-'||gen_random_uuid()::text) RETURNING id INTO loc;
 INSERT INTO tj.platform_connector_connections(organization_id,connector_id,store_id,external_account_id,created_by) VALUES(org,connector,loc,'bridge-'||gen_random_uuid()::text,source_actor) RETURNING id INTO conn;
 INSERT INTO tj.platform_connector_connections(organization_id,connector_id,store_id,external_account_id,created_by) VALUES(org,connector,loc,'bridge-'||gen_random_uuid()::text,source_actor) RETURNING id INTO second;
 code:='rollback-'||gen_random_uuid()::text;
 INSERT INTO tj.iq_pos_employee_map(organization_id,store_id,salesperson_user_id,pos_employee_id,pos_system) VALUES(org,loc,source_actor,code,'epass') ON CONFLICT(organization_id,salesperson_user_id,pos_system) DO UPDATE SET pos_employee_id=excluded.pos_employee_id,store_id=loc,is_active=true;
 INSERT INTO tj.platform_connector_match_queue(connection_id,organization_id,external_entity_type,external_id,external_code,candidate_type,candidate_id,status,reviewed_by,reviewed_at,metadata) VALUES(conn,org,'employee',code,code,'user',source_actor,'confirmed',source_actor,now(),'{"us_onboarding_reviewed":true}');
 INSERT INTO tj.platform_connector_entity_map(connection_id,external_entity_type,external_id,local_entity_type,local_id,metadata) VALUES(conn,'location','reviewed-store','org_location',loc,'{"us_onboarding_reviewed":true}');
 PERFORM set_config('request.jwt.claim.sub',native::text,true);PERFORM set_config('test.bridge.native',native::text,true);PERFORM set_config('test.bridge.actor',source_actor::text,true);PERFORM set_config('test.bridge.connection',conn::text,true);PERFORM set_config('test.bridge.second',second::text,true);PERFORM set_config('test.bridge.org',org::text,true);PERFORM set_config('test.bridge.employee',code,true);PERFORM set_config('test.bridge.store',loc::text,true);
END $$;
SET LOCAL ROLE authenticated;
DO $$ DECLARE conn text:=current_setting('test.bridge.connection');r jsonb;row jsonb;BEGIN
 r:=public.tj_connector_ingest(jsonb_build_object('connection_id',conn,'external_entity_type','invoice','external_id','a','payload',jsonb_build_object('invoice_number','METRIC-A','invoice_date','2001-03-10T12:00:00Z','salesperson_id',current_setting('test.bridge.employee'),'location_id','reviewed-store','total',120,'items',jsonb_build_array(jsonb_build_object('id','A','description','Appliance','qty',1,'unit_price',100,'unit_cost',50),jsonb_build_object('id','W','description','Warranty','unit_price',20,'unit_cost',0)))));IF r->>'ok'<>'true' THEN RAISE EXCEPTION 'fixture_a_failed';END IF;
 r:=public.tj_connector_ingest(jsonb_build_object('connection_id',conn,'external_entity_type','invoice','external_id','b','payload',jsonb_build_object('invoice_number','METRIC-B','invoice_date','2001-03-11T03:30:00Z','salesperson_id',current_setting('test.bridge.employee'),'location_id','reviewed-store','total',80,'items',jsonb_build_array(jsonb_build_object('id','B','description','Appliance','unit_price',80,'unit_cost',40)))));IF r->>'ok'<>'true' THEN RAISE EXCEPTION 'fixture_b_failed';END IF;
 r:=public.tj_connector_ingest(jsonb_build_object('connection_id',conn,'external_entity_type','invoice','external_id','c','payload',jsonb_build_object('invoice_number','METRIC-C','invoice_date','2001-03-10T15:00:00Z','total',10,'items',jsonb_build_array(jsonb_build_object('id','C','unit_price',10)))));IF r->>'ok'<>'true' THEN RAISE EXCEPTION 'fixture_c_failed';END IF;
 r:=public.tj_epass_performance_bridge(jsonb_build_object('connection_id',conn));IF r->>'processed'<>'3' THEN RAISE EXCEPTION 'bridge_fixture_failed: %',r;END IF;
 r:=public.tj_epass_metric_refresh(jsonb_build_object('connection_id',conn,'from','2001-03-10','to','2001-03-10','timezone','America/Toronto'));IF r->>'metrics_refreshed'<>'false' OR r->>'verified_receipts'<>'3' OR r->>'complete_scope'<>'true' THEN RAISE EXCEPTION 'preview_failed: %',r;END IF;
 SELECT value INTO row FROM jsonb_array_elements(r->'metrics') WHERE value->>'user_id'=current_setting('test.bridge.actor') AND value->>'metric_key'='revenue';IF (row->>'actual_value')::numeric<>200 THEN RAISE EXCEPTION 'timezone_or_double_count_failed';END IF;
 SELECT value INTO row FROM jsonb_array_elements(r->'metrics') WHERE value->>'user_id'=current_setting('test.bridge.actor') AND value->>'metric_key'='margin_pct';IF (row->>'actual_value')::numeric<>55 THEN RAISE EXCEPTION 'margin_failed';END IF;
 SELECT value INTO row FROM jsonb_array_elements(r->'metrics') WHERE value->>'user_id'=current_setting('test.bridge.actor') AND value->>'metric_key'='warranty_attach';IF (row->>'actual_value')::numeric<>50 THEN RAISE EXCEPTION 'attach_failed';END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(r->'metrics') WHERE value->>'user_id' IS NULL AND value->>'metric_key' IN('margin_dollars','margin_pct')) THEN RAISE EXCEPTION 'unknown_margin_invented';END IF;
 PERFORM set_config('test.metric.digest',r->>'source_digest',true);PERFORM set_config('test.metric.count',r->>'metrics_count',true);
 BEGIN PERFORM public.tj_epass_metric_refresh(jsonb_build_object('connection_id',conn,'from','2001-03-10','to','2001-03-10','timezone','America/Toronto','apply',true));RAISE EXCEPTION 'unapproved_write_accepted';EXCEPTION WHEN serialization_failure THEN NULL;END;
 BEGIN PERFORM public.tj_epass_metric_refresh(jsonb_build_object('connection_id',conn,'from','2001-01-01','to','2001-03-10'));RAISE EXCEPTION 'wide_window_accepted';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 BEGIN PERFORM public.tj_epass_metric_refresh(jsonb_build_object('connection_id',gen_random_uuid(),'from','2001-03-10','to','2001-03-10'));RAISE EXCEPTION 'foreign_connection_accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END $$;
RESET ROLE;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM tj.metric_snapshots WHERE organization_id=current_setting('test.bridge.org')::uuid AND period_key='2001-03-10' AND metric_subtype='connector_transaction') THEN RAISE EXCEPTION 'preview_wrote_snapshots';END IF;
 INSERT INTO tj_private.epass_metric_reconciliation(organization_id,from_date,to_date,timezone,source_digest,approved_by,expires_at) VALUES(current_setting('test.bridge.org')::uuid,'2001-03-10','2001-03-10','America/Toronto',current_setting('test.metric.digest'),current_setting('test.bridge.actor')::uuid,now()+interval '1 hour');
 INSERT INTO tj.metric_snapshots(organization_id,location_id,user_id,period_type,period_key,metric_key,metric_subtype,actual_value) VALUES(current_setting('test.bridge.org')::uuid,current_setting('test.bridge.store')::uuid,current_setting('test.bridge.actor')::uuid,'daily','2001-03-10','revenue','manual_target',777);
END $$;
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb;BEGIN
 r:=public.tj_epass_metric_refresh(jsonb_build_object('connection_id',current_setting('test.bridge.connection'),'from','2001-03-10','to','2001-03-10','timezone','America/Toronto','apply',true));IF r->>'metrics_refreshed'<>'true' OR r->>'written'<>current_setting('test.metric.count') THEN RAISE EXCEPTION 'approved_apply_failed';END IF;
 r:=public.tj_epass_metric_refresh(jsonb_build_object('connection_id',current_setting('test.bridge.connection'),'from','2001-03-10','to','2001-03-10','timezone','America/Toronto','apply',true));IF r->>'written'<>current_setting('test.metric.count') THEN RAISE EXCEPTION 'repeat_apply_failed';END IF;
END $$;
RESET ROLE;
DO $$ BEGIN
 IF (SELECT count(*) FROM tj.metric_snapshots WHERE organization_id=current_setting('test.bridge.org')::uuid AND period_key='2001-03-10' AND metric_subtype='connector_transaction')<>current_setting('test.metric.count')::integer THEN RAISE EXCEPTION 'snapshot_deduplication_failed';END IF;
 IF NOT EXISTS(SELECT 1 FROM tj.metric_snapshots WHERE organization_id=current_setting('test.bridge.org')::uuid AND period_key='2001-03-10' AND metric_subtype='manual_target' AND actual_value=777) THEN RAISE EXCEPTION 'unrelated_snapshot_modified';END IF;
 IF EXISTS(SELECT 1 FROM tj.metric_snapshots WHERE organization_id=current_setting('test.bridge.org')::uuid AND period_key='2001-03-10' AND metric_subtype='connector_transaction' AND target_value IS NOT NULL) THEN RAISE EXCEPTION 'invented_target';END IF;
 UPDATE tj.iq_pos_transactions SET transaction_amount=transaction_amount+1 WHERE source_connection_id=current_setting('test.bridge.connection')::uuid AND pos_transaction_id='epass:'||current_setting('test.bridge.connection')||':a';
END $$;
SET LOCAL ROLE authenticated;
DO $$ BEGIN BEGIN PERFORM public.tj_epass_metric_refresh(jsonb_build_object('connection_id',current_setting('test.bridge.connection'),'from','2001-03-10','to','2001-03-10','timezone','America/Toronto','apply',true));RAISE EXCEPTION 'stale_digest_accepted';EXCEPTION WHEN serialization_failure THEN NULL;END;END $$;
RESET ROLE;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM tj.metric_snapshots WHERE organization_id=current_setting('test.bridge.org')::uuid AND period_key='2001-03-10' AND metric_subtype='connector_transaction' AND user_id=current_setting('test.bridge.actor')::uuid AND metric_key='revenue' AND actual_value=200) THEN RAISE EXCEPTION 'rejected_apply_modified_snapshot';END IF;
 UPDATE tj.organization_members SET role='member' WHERE organization_id=current_setting('test.bridge.org')::uuid AND user_id=current_setting('test.bridge.actor')::uuid;
 IF has_function_privilege('anon','public.tj_epass_metric_refresh(jsonb)','EXECUTE') OR has_function_privilege('service_role','public.tj_epass_metric_refresh(jsonb)','EXECUTE') OR has_table_privilege('authenticated','tj_private.epass_metric_reconciliation','SELECT') THEN RAISE EXCEPTION 'unsafe_grants';END IF;
END $$;
SET LOCAL ROLE authenticated;
DO $$ BEGIN BEGIN PERFORM public.tj_epass_metric_refresh(jsonb_build_object('connection_id',current_setting('test.bridge.connection'),'from','2001-03-10','to','2001-03-10'));RAISE EXCEPTION 'nonadmin_accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;END $$;
RESET ROLE;
ROLLBACK;
