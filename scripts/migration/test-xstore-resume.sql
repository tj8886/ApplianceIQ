BEGIN; SET LOCAL statement_timeout='30s';
DO $$ DECLARE native uuid;source_actor uuid;org uuid;connector uuid;conn uuid;BEGIN
 SELECT im.target_user_id,im.source_user_id,m.organization_id INTO native,source_actor,org FROM tj.source_user_identity_map im JOIN tj.organization_members m ON m.user_id=im.source_user_id JOIN tj.organizations o ON o.id=m.organization_id WHERE im.activation_status='activated' AND m.status='active' AND m.role IN('owner','admin') AND o.status='active' AND o.deleted_at IS NULL LIMIT 1;
 SELECT id INTO connector FROM tj.platform_connectors WHERE key='oracle_xstore';IF native IS NULL OR connector IS NULL THEN RAISE EXCEPTION 'fixture_missing';END IF;
 INSERT INTO tj.platform_connector_connections(organization_id,connector_id,display_name,created_by,settings) VALUES(org,connector,'Rollback Xstore test',source_actor,'{"private":"must-not-return"}') RETURNING id INTO conn;
 PERFORM set_config('request.jwt.claim.sub',native::text,true);PERFORM set_config('test.xstore.native',native::text,true);PERFORM set_config('test.xstore.actor',source_actor::text,true);PERFORM set_config('test.xstore.connection',conn::text,true);PERFORM set_config('test.xstore.org',org::text,true);
END $$;
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb;conn text:=current_setting('test.xstore.connection');bad jsonb;BEGIN
 r:=public.tj_xstore_setup(jsonb_build_object('connection_id',conn));IF r::text LIKE '%must-not-return%' OR r::text LIKE '%credential_ref%' OR r->>'sync_ready'<>'false' THEN RAISE EXCEPTION 'unsafe_status';END IF;
 BEGIN PERFORM public.tj_xstore_setup(jsonb_build_object('connection_id',gen_random_uuid()));RAISE EXCEPTION 'foreign_connection_accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN PERFORM public.tj_xstore_setup(jsonb_build_object('action','test','connection_id',conn));RAISE EXCEPTION 'unconfigured_test_accepted';EXCEPTION WHEN serialization_failure THEN NULL;END;
 FOR bad IN SELECT * FROM jsonb_array_elements('[{"base_url":"https://xstore.example/a/../credentials","token_url":"https://identity.example/token","endpoints":{"customers":"customers"}},{"base_url":"https://xstore.example/api","token_url":"https://identity.example/a/../token","endpoints":{"customers":"customers"}},{"base_url":"http://xstore.example","endpoints":{"customers":"customers"}},{"base_url":"https://xstore.example","endpoints":{"customers":"https://evil.example"}},{"base_url":"https://xstore.example","endpoints":{"unknown":"rows"}},{"base_url":"https://xstore.example","endpoints":{"customers":"customers"},"api_key_header":"Authorization"},{"base_url":"https://xstore.example","endpoints":{"customers":"customers"},"credential":{"password":"synthetic"}}]'::jsonb) LOOP
  BEGIN PERFORM public.tj_xstore_setup(bad||jsonb_build_object('action','configure','connection_id',conn));RAISE EXCEPTION 'invalid_config_accepted';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 END LOOP;
 r:=public.tj_xstore_setup(jsonb_build_object('action','configure','connection_id',conn,'base_url','https://xstore.example/api','token_url','https://identity.example/oauth2/v1/token','endpoints',jsonb_build_object('customers','customers'),'client_id','synthetic-client','client_secret','rollback-synthetic','scope','synthetic-scope'));IF r->>'ok'<>'true' THEN RAISE EXCEPTION 'configure_failed';END IF;
 r:=public.tj_xstore_setup(jsonb_build_object('connection_id',conn));IF r::text LIKE '%rollback-synthetic%' OR r#>>'{configuration,configured}'<>'true' THEN RAISE EXCEPTION 'credential_leak_or_missing';END IF;PERFORM set_config('test.xstore.version',r->>'version',true);
 r:=public.tj_xstore_setup(jsonb_build_object('action','sync','connection_id',conn));IF r->>'ok'<>'false' OR r->>'error'<>'xstore_destination_verification_required' THEN RAISE EXCEPTION 'sync_false_ready';END IF;
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);BEGIN PERFORM public.tj_xstore_setup(jsonb_build_object('connection_id',conn));RAISE EXCEPTION 'unmapped_accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 PERFORM set_config('request.jwt.claim.sub',current_setting('test.xstore.native'),true);
END $$;
RESET ROLE;
DO $$ DECLARE c tj.platform_connector_connections%rowtype;BEGIN
 SELECT * INTO c FROM tj.platform_connector_connections WHERE id=current_setting('test.xstore.connection')::uuid;IF c.status<>'pending' OR c.settings->>'destination_connection_verified'<>'false' THEN RAISE EXCEPTION 'false_activation';END IF;
 UPDATE tj.organization_members SET role='member' WHERE organization_id=c.organization_id AND user_id=current_setting('test.xstore.actor')::uuid;
END $$;
SET LOCAL ROLE authenticated;
DO $$ BEGIN
 BEGIN PERFORM public.tj_xstore_setup(jsonb_build_object('connection_id',current_setting('test.xstore.connection')));RAISE EXCEPTION 'nonadmin_accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END $$;
RESET ROLE;
UPDATE tj.organization_members SET role='admin' WHERE organization_id=current_setting('test.xstore.org')::uuid AND user_id=current_setting('test.xstore.actor')::uuid;
SET LOCAL ROLE service_role;
DO $$ DECLARE r jsonb;BEGIN
 r:=public.aiq_xstore_test_context(current_setting('test.xstore.connection')::uuid,current_setting('test.xstore.native')::uuid,current_setting('test.xstore.version')::timestamptz);IF r#>>'{credential,client_secret}'<>'rollback-synthetic' THEN RAISE EXCEPTION 'service_credential_load_failed';END IF;
 BEGIN PERFORM public.aiq_xstore_test_context(current_setting('test.xstore.connection')::uuid,gen_random_uuid(),current_setting('test.xstore.version')::timestamptz);RAISE EXCEPTION 'foreign_actor_secret_accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN PERFORM public.aiq_xstore_test_context(current_setting('test.xstore.connection')::uuid,current_setting('test.xstore.native')::uuid,now()-interval '1 day');RAISE EXCEPTION 'stale_config_accepted';EXCEPTION WHEN serialization_failure THEN NULL;END;
END $$;
RESET ROLE;
DO $$ BEGIN
 IF has_function_privilege('anon','public.tj_xstore_setup(jsonb)','EXECUTE') OR has_function_privilege('authenticated','public.aiq_xstore_test_context(uuid,uuid,timestamptz)','EXECUTE') OR has_function_privilege('service_role','public.tj_xstore_setup(jsonb)','EXECUTE') THEN RAISE EXCEPTION 'unsafe_grants';END IF;
 IF EXISTS(SELECT 1 FROM tj.platform_sync_jobs WHERE connection_id=current_setting('test.xstore.connection')::uuid) THEN RAISE EXCEPTION 'premature_job';END IF;
END $$;
-- The setup fixture above made no real request or persisted approval.
INSERT INTO tj_private.xstore_sync_contracts(connection_id,organization_id,config_version,config_digest,approved_by,expires_at)
 SELECT id,organization_id,updated_at,encode(sha256(convert_to((settings->'xstore_api')::text,'UTF8')),'hex'),current_setting('test.xstore.actor')::uuid,clock_timestamp()+interval '1 hour'
 FROM tj.platform_connector_connections WHERE id=current_setting('test.xstore.connection')::uuid;
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb;BEGIN
 r:=public.tj_xstore_setup(jsonb_build_object('action','sync','connection_id',current_setting('test.xstore.connection')));
 IF r->>'phase'<>'fetch' OR r->>'resource'<>'customers' OR r->>'done'<>'false' OR r::text LIKE '%rollback-synthetic%' THEN RAISE EXCEPTION 'claim_failed_or_leaked';END IF;
 PERFORM set_config('test.xstore.job',r->>'job_id',true);PERFORM set_config('test.xstore.lease',r->>'lease',true);
 BEGIN PERFORM public.tj_xstore_setup(jsonb_build_object('action','sync','connection_id',current_setting('test.xstore.connection')));RAISE EXCEPTION 'concurrent_claim_accepted';EXCEPTION WHEN serialization_failure THEN NULL;END;
 BEGIN PERFORM public.tj_xstore_setup(jsonb_build_object('action','sync','connection_id',current_setting('test.xstore.connection'),'job_id',gen_random_uuid()));RAISE EXCEPTION 'foreign_job_accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END $$;
SET LOCAL ROLE service_role;
DO $$ DECLARE r jsonb;BEGIN
 BEGIN PERFORM public.aiq_xstore_sync_context(current_setting('test.xstore.connection')::uuid,current_setting('test.xstore.native')::uuid,current_setting('test.xstore.job')::uuid,gen_random_uuid());RAISE EXCEPTION 'wrong_lease_accepted';EXCEPTION WHEN serialization_failure THEN NULL;END;
 BEGIN PERFORM public.aiq_xstore_sync_context(current_setting('test.xstore.connection')::uuid,gen_random_uuid(),current_setting('test.xstore.job')::uuid,current_setting('test.xstore.lease')::uuid);RAISE EXCEPTION 'foreign_actor_accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 r:=public.aiq_xstore_sync_context(current_setting('test.xstore.connection')::uuid,current_setting('test.xstore.native')::uuid,current_setting('test.xstore.job')::uuid,current_setting('test.xstore.lease')::uuid);
 IF r#>>'{credential,client_secret}'<>'rollback-synthetic' THEN RAISE EXCEPTION 'context_failed';END IF;
 r:=public.aiq_xstore_sync_finish(current_setting('test.xstore.connection')::uuid,current_setting('test.xstore.native')::uuid,current_setting('test.xstore.job')::uuid,current_setting('test.xstore.lease')::uuid,'{"kind":"page","processed":2,"failed":0,"page_url":"https://xstore.example/api/customers","next_url":"https://xstore.example/api/customers?page=2"}');
 IF r->>'done'<>'false' OR r->>'processed'<>'2' THEN RAISE EXCEPTION 'page_checkpoint_failed';END IF;
 BEGIN PERFORM public.aiq_xstore_sync_finish(current_setting('test.xstore.connection')::uuid,current_setting('test.xstore.native')::uuid,current_setting('test.xstore.job')::uuid,current_setting('test.xstore.lease')::uuid,'{"kind":"retry"}');RAISE EXCEPTION 'duplicate_finish_accepted';EXCEPTION WHEN serialization_failure THEN NULL;END;
END $$;
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb;BEGIN
 r:=public.tj_xstore_setup(jsonb_build_object('action','sync','connection_id',current_setting('test.xstore.connection'),'job_id',current_setting('test.xstore.job')));
 IF r->>'next_url'<>'https://xstore.example/api/customers?page=2' THEN RAISE EXCEPTION 'resume_cursor_lost';END IF;PERFORM set_config('test.xstore.lease',r->>'lease',true);
END $$;
SET LOCAL ROLE service_role;
DO $$ BEGIN
 BEGIN PERFORM public.aiq_xstore_sync_finish(current_setting('test.xstore.connection')::uuid,current_setting('test.xstore.native')::uuid,current_setting('test.xstore.job')::uuid,current_setting('test.xstore.lease')::uuid,'{"kind":"page","processed":1,"failed":0,"page_url":"https://xstore.example/api/customers?page=2","next_url":"https://xstore.example/api/customers"}');RAISE EXCEPTION 'pagination_cycle_accepted';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 PERFORM public.aiq_xstore_sync_finish(current_setting('test.xstore.connection')::uuid,current_setting('test.xstore.native')::uuid,current_setting('test.xstore.job')::uuid,current_setting('test.xstore.lease')::uuid,'{"kind":"retry"}');
END $$;
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb;BEGIN
 r:=public.tj_xstore_setup(jsonb_build_object('action','sync','connection_id',current_setting('test.xstore.connection')));IF r->>'job_id'<>current_setting('test.xstore.job') OR r->>'next_url'<>'https://xstore.example/api/customers?page=2' THEN RAISE EXCEPTION 'retry_lost_job_or_cursor';END IF;
 PERFORM set_config('test.xstore.lease',r->>'lease',true);
END $$;
SET LOCAL ROLE service_role;
DO $$ DECLARE r jsonb;BEGIN
 r:=public.aiq_xstore_sync_finish(current_setting('test.xstore.connection')::uuid,current_setting('test.xstore.native')::uuid,current_setting('test.xstore.job')::uuid,current_setting('test.xstore.lease')::uuid,'{"kind":"page","processed":1,"failed":1,"page_url":"https://xstore.example/api/customers?page=2","next_url":null}');
 IF r->>'done'<>'true' OR r->>'status'<>'partial' OR r->>'processed'<>'3' OR r->>'failed'<>'1' OR r->>'metrics_refreshed'<>'false' THEN RAISE EXCEPTION 'partial_completion_failed';END IF;
END $$;
RESET ROLE;
DO $$ BEGIN
 IF (SELECT last_success_at IS NOT NULL OR status<>'pending' OR settings->>'destination_connection_verified'<>'false' FROM tj.platform_connector_connections WHERE id=current_setting('test.xstore.connection')::uuid) THEN RAISE EXCEPTION 'false_activation_or_success';END IF;
 UPDATE tj.platform_connector_connections SET settings=jsonb_set(settings,'{xstore_api,endpoints}','{"transactions":"transactions"}') WHERE id=current_setting('test.xstore.connection')::uuid;
END $$;
UPDATE tj_private.xstore_sync_contracts SET config_digest=(SELECT encode(sha256(convert_to((settings->'xstore_api')::text,'UTF8')),'hex') FROM tj.platform_connector_connections WHERE id=current_setting('test.xstore.connection')::uuid) WHERE connection_id=current_setting('test.xstore.connection')::uuid;
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb;BEGIN
 r:=public.tj_xstore_setup(jsonb_build_object('action','sync','connection_id',current_setting('test.xstore.connection')));PERFORM set_config('test.xstore.job',r->>'job_id',true);PERFORM set_config('test.xstore.lease',r->>'lease',true);
END $$;
SET LOCAL ROLE service_role;
SELECT public.aiq_xstore_sync_finish(current_setting('test.xstore.connection')::uuid,current_setting('test.xstore.native')::uuid,current_setting('test.xstore.job')::uuid,current_setting('test.xstore.lease')::uuid,'{"kind":"page","processed":1,"failed":0,"page_url":"https://xstore.example/api/transactions","next_url":null}');
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb;BEGIN
 r:=public.tj_xstore_setup(jsonb_build_object('action','sync','connection_id',current_setting('test.xstore.connection')));IF r->>'phase'<>'bridge' THEN RAISE EXCEPTION 'bridge_phase_skipped';END IF;PERFORM set_config('test.xstore.lease',r->>'lease',true);
END $$;
SET LOCAL ROLE service_role;
SELECT public.aiq_xstore_sync_finish(current_setting('test.xstore.connection')::uuid,current_setting('test.xstore.native')::uuid,current_setting('test.xstore.job')::uuid,current_setting('test.xstore.lease')::uuid,'{"kind":"bridge","processed":0,"failed":30,"next_cursor":"Z","has_more":true}');
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb;BEGIN
 r:=public.tj_xstore_setup(jsonb_build_object('action','sync','connection_id',current_setting('test.xstore.connection')));PERFORM set_config('test.xstore.lease',r->>'lease',true);
END $$;
SET LOCAL ROLE service_role;
DO $$ DECLARE r jsonb;BEGIN
 r:=public.aiq_xstore_sync_context(current_setting('test.xstore.connection')::uuid,current_setting('test.xstore.native')::uuid,current_setting('test.xstore.job')::uuid,current_setting('test.xstore.lease')::uuid);IF r->>'bridge_cursor'<>'Z' THEN RAISE EXCEPTION 'bridge_cursor_lost';END IF;
 r:=public.aiq_xstore_sync_finish(current_setting('test.xstore.connection')::uuid,current_setting('test.xstore.native')::uuid,current_setting('test.xstore.job')::uuid,current_setting('test.xstore.lease')::uuid,'{"kind":"bridge","processed":0,"failed":0,"next_cursor":null,"has_more":false}');
 IF r->>'done'<>'true' OR r->>'status'<>'partial' OR r->>'failed'<>'30' THEN RAISE EXCEPTION 'bridge_partial_hidden';END IF;
END $$;
RESET ROLE;
UPDATE tj_private.xstore_sync_contracts SET expires_at=clock_timestamp()-interval '1 second' WHERE connection_id=current_setting('test.xstore.connection')::uuid;
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb;BEGIN
 r:=public.tj_xstore_setup(jsonb_build_object('action','sync','connection_id',current_setting('test.xstore.connection')));IF r->>'error'<>'xstore_destination_verification_required' THEN RAISE EXCEPTION 'expired_review_accepted';END IF;
END $$;
RESET ROLE;
UPDATE tj_private.xstore_sync_contracts SET expires_at=clock_timestamp()+interval '1 hour' WHERE connection_id=current_setting('test.xstore.connection')::uuid;
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb;BEGIN
 r:=public.tj_xstore_setup(jsonb_build_object('action','sync','connection_id',current_setting('test.xstore.connection')));PERFORM set_config('test.xstore.job',r->>'job_id',true);PERFORM set_config('test.xstore.lease',r->>'lease',true);
 r:=public.tj_xstore_setup(jsonb_build_object('action','sync','connection_id',current_setting('test.xstore.connection'),'job_id',current_setting('test.xstore.job'),'cancel',true));IF r->>'status'<>'canceled' THEN RAISE EXCEPTION 'cancel_failed';END IF;
END $$;
SET LOCAL ROLE service_role;
DO $$ BEGIN
 BEGIN PERFORM public.aiq_xstore_sync_context(current_setting('test.xstore.connection')::uuid,current_setting('test.xstore.native')::uuid,current_setting('test.xstore.job')::uuid,current_setting('test.xstore.lease')::uuid);RAISE EXCEPTION 'canceled_lease_accepted';EXCEPTION WHEN serialization_failure THEN NULL;END;
END $$;
RESET ROLE;
DO $$ BEGIN
 IF has_function_privilege('anon','public.aiq_xstore_sync_context(uuid,uuid,uuid,uuid)','EXECUTE') OR has_function_privilege('authenticated','public.aiq_xstore_sync_finish(uuid,uuid,uuid,uuid,jsonb)','EXECUTE') OR has_table_privilege('authenticated','tj_private.xstore_sync_contracts','SELECT') OR has_table_privilege('service_role','tj_private.xstore_sync_runs','UPDATE') THEN RAISE EXCEPTION 'unsafe_sync_grants';END IF;
END $$;

-- Lease expiry, exact configuration binding, cancellation without current approval.
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb;BEGIN
 r:=public.tj_xstore_setup(jsonb_build_object('action','sync','connection_id',current_setting('test.xstore.connection')));PERFORM set_config('test.xstore.job',r->>'job_id',true);PERFORM set_config('test.xstore.oldlease',r->>'lease',true);
END $$;
RESET ROLE;
UPDATE tj_private.xstore_sync_runs SET lease_until=clock_timestamp()-interval '1 second' WHERE job_id=current_setting('test.xstore.job')::uuid;
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb;BEGIN
 r:=public.tj_xstore_setup(jsonb_build_object('action','sync','connection_id',current_setting('test.xstore.connection'),'job_id',current_setting('test.xstore.job')));IF r->>'lease'=current_setting('test.xstore.oldlease') THEN RAISE EXCEPTION 'expired_lease_reused';END IF;PERFORM set_config('test.xstore.lease',r->>'lease',true);
END $$;
SET LOCAL ROLE service_role;
DO $$ BEGIN
 BEGIN PERFORM public.aiq_xstore_sync_context(current_setting('test.xstore.connection')::uuid,current_setting('test.xstore.native')::uuid,current_setting('test.xstore.job')::uuid,current_setting('test.xstore.oldlease')::uuid);RAISE EXCEPTION 'reclaimed_old_lease_accepted';EXCEPTION WHEN serialization_failure THEN NULL;END;
END $$;
RESET ROLE;
UPDATE tj.platform_connector_connections SET settings=jsonb_set(settings,'{xstore_api,org_id}','"NEW-ORG"') WHERE id=current_setting('test.xstore.connection')::uuid;
SET LOCAL ROLE service_role;
DO $$ BEGIN
 BEGIN PERFORM public.aiq_xstore_sync_context(current_setting('test.xstore.connection')::uuid,current_setting('test.xstore.native')::uuid,current_setting('test.xstore.job')::uuid,current_setting('test.xstore.lease')::uuid);RAISE EXCEPTION 'unreviewed_config_change_accepted';EXCEPTION WHEN serialization_failure THEN NULL;END;
END $$;
SET LOCAL ROLE authenticated;
SELECT public.tj_xstore_setup(jsonb_build_object('action','sync','connection_id',current_setting('test.xstore.connection'),'job_id',current_setting('test.xstore.job'),'cancel',true));
RESET ROLE;
UPDATE tj.platform_connector_connections SET settings=jsonb_set(settings,'{xstore_api,org_id}','"DEFAULT"') WHERE id=current_setting('test.xstore.connection')::uuid;

SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb;BEGIN
 r:=public.tj_xstore_setup(jsonb_build_object('action','sync','connection_id',current_setting('test.xstore.connection')));PERFORM set_config('test.xstore.job',r->>'job_id',true);PERFORM set_config('test.xstore.lease',r->>'lease',true);
END $$;
SET LOCAL ROLE service_role;
SELECT public.aiq_xstore_sync_finish(current_setting('test.xstore.connection')::uuid,current_setting('test.xstore.native')::uuid,current_setting('test.xstore.job')::uuid,current_setting('test.xstore.lease')::uuid,'{"kind":"retry"}');

SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb;BEGIN
 r:=public.tj_xstore_setup(jsonb_build_object('action','sync','connection_id',current_setting('test.xstore.connection')));PERFORM set_config('test.xstore.job',r->>'job_id',true);PERFORM set_config('test.xstore.lease',r->>'lease',true);
END $$;
SET LOCAL ROLE service_role;
SELECT public.aiq_xstore_sync_finish(current_setting('test.xstore.connection')::uuid,current_setting('test.xstore.native')::uuid,current_setting('test.xstore.job')::uuid,current_setting('test.xstore.lease')::uuid,'{"kind":"retry"}');

SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb;BEGIN
 r:=public.tj_xstore_setup(jsonb_build_object('action','sync','connection_id',current_setting('test.xstore.connection')));PERFORM set_config('test.xstore.job',r->>'job_id',true);PERFORM set_config('test.xstore.lease',r->>'lease',true);
END $$;
SET LOCAL ROLE service_role;
SELECT public.aiq_xstore_sync_finish(current_setting('test.xstore.connection')::uuid,current_setting('test.xstore.native')::uuid,current_setting('test.xstore.job')::uuid,current_setting('test.xstore.lease')::uuid,'{"kind":"retry"}');

SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb;BEGIN
 r:=public.tj_xstore_setup(jsonb_build_object('action','sync','connection_id',current_setting('test.xstore.connection')));PERFORM set_config('test.xstore.job',r->>'job_id',true);PERFORM set_config('test.xstore.lease',r->>'lease',true);
END $$;
SET LOCAL ROLE service_role;
SELECT public.aiq_xstore_sync_finish(current_setting('test.xstore.connection')::uuid,current_setting('test.xstore.native')::uuid,current_setting('test.xstore.job')::uuid,current_setting('test.xstore.lease')::uuid,'{"kind":"retry"}');

SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb;BEGIN
 r:=public.tj_xstore_setup(jsonb_build_object('action','sync','connection_id',current_setting('test.xstore.connection')));PERFORM set_config('test.xstore.job',r->>'job_id',true);PERFORM set_config('test.xstore.lease',r->>'lease',true);
END $$;
SET LOCAL ROLE service_role;
SELECT public.aiq_xstore_sync_finish(current_setting('test.xstore.connection')::uuid,current_setting('test.xstore.native')::uuid,current_setting('test.xstore.job')::uuid,current_setting('test.xstore.lease')::uuid,'{"kind":"retry"}');

RESET ROLE;
DO $$ BEGIN
 IF (SELECT status FROM tj.platform_sync_jobs WHERE id=current_setting('test.xstore.job')::uuid)<>'failed' THEN RAISE EXCEPTION 'retry_limit_not_terminal';END IF;
END $$;
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb;BEGIN
 r:=public.tj_xstore_setup(jsonb_build_object('action','sync','connection_id',current_setting('test.xstore.connection')));PERFORM set_config('test.xstore.job',r->>'job_id',true);PERFORM set_config('test.xstore.lease',r->>'lease',true);
END $$;
RESET ROLE;
UPDATE tj_private.xstore_sync_runs SET pages=999 WHERE job_id=current_setting('test.xstore.job')::uuid;
SET LOCAL ROLE service_role;
DO $$ DECLARE r jsonb;BEGIN
 r:=public.aiq_xstore_sync_finish(current_setting('test.xstore.connection')::uuid,current_setting('test.xstore.native')::uuid,current_setting('test.xstore.job')::uuid,current_setting('test.xstore.lease')::uuid,'{"kind":"page","processed":1,"failed":0,"page_url":"https://xstore.example/api/transactions","next_url":"https://xstore.example/api/transactions?page=2"}');
 IF r->>'done'<>'true' OR r->>'status'<>'failed' THEN RAISE EXCEPTION 'page_limit_not_terminal';END IF;
END $$;
RESET ROLE;

-- Resource order is canonical; loss of native mapping verification denies both caller and service.
UPDATE tj.platform_connector_connections SET settings=jsonb_set(settings,'{xstore_api,endpoints}','{"customers":"customers","transactions":"transactions"}') WHERE id=current_setting('test.xstore.connection')::uuid;
UPDATE tj_private.xstore_sync_contracts SET config_digest=(SELECT encode(sha256(convert_to((settings->'xstore_api')::text,'UTF8')),'hex') FROM tj.platform_connector_connections WHERE id=current_setting('test.xstore.connection')::uuid) WHERE connection_id=current_setting('test.xstore.connection')::uuid;
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb;BEGIN
 r:=public.tj_xstore_setup(jsonb_build_object('action','sync','connection_id',current_setting('test.xstore.connection'),'resources','["transactions","customers"]'::jsonb));
 IF r->>'resource'<>'customers' THEN RAISE EXCEPTION 'resource_order_not_canonical';END IF;
 PERFORM set_config('test.xstore.job',r->>'job_id',true);PERFORM set_config('test.xstore.lease',r->>'lease',true);
END $$;
SET LOCAL ROLE service_role;
SELECT public.aiq_xstore_sync_finish(current_setting('test.xstore.connection')::uuid,current_setting('test.xstore.native')::uuid,current_setting('test.xstore.job')::uuid,current_setting('test.xstore.lease')::uuid,'{"kind":"retry"}');
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb;BEGIN
 r:=public.tj_xstore_setup(jsonb_build_object('action','sync','connection_id',current_setting('test.xstore.connection'),'job_id',current_setting('test.xstore.job'),'resources','["customers","transactions"]'::jsonb));
 IF r->>'resource'<>'customers' THEN RAISE EXCEPTION 'reordered_resource_resume_failed';END IF;
 PERFORM set_config('test.xstore.lease',r->>'lease',true);
END $$;
RESET ROLE;
UPDATE tj.source_user_identity_map SET identity_verified=false WHERE target_user_id=current_setting('test.xstore.native')::uuid;
SET LOCAL ROLE authenticated;
DO $$ BEGIN
 BEGIN PERFORM public.tj_xstore_setup(jsonb_build_object('action','sync','connection_id',current_setting('test.xstore.connection')));RAISE EXCEPTION 'unverified_identity_claim_accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END $$;
SET LOCAL ROLE service_role;
DO $$ BEGIN
 BEGIN PERFORM public.aiq_xstore_sync_context(current_setting('test.xstore.connection')::uuid,current_setting('test.xstore.native')::uuid,current_setting('test.xstore.job')::uuid,current_setting('test.xstore.lease')::uuid);RAISE EXCEPTION 'unverified_identity_secret_accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END $$;
RESET ROLE;
ROLLBACK;
