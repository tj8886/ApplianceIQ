BEGIN; SET LOCAL statement_timeout='30s';
DO $$ DECLARE native uuid;source_actor uuid;org uuid;connector uuid;conn uuid;BEGIN
 SELECT im.target_user_id,im.source_user_id,m.organization_id INTO native,source_actor,org FROM tj.source_user_identity_map im JOIN tj.organization_members m ON m.user_id=im.source_user_id JOIN tj.organizations o ON o.id=m.organization_id WHERE im.activation_status='activated' AND m.status='active' AND m.role IN('owner','admin') AND o.status='active' AND o.deleted_at IS NULL LIMIT 1;
 SELECT id INTO connector FROM tj.platform_connectors WHERE key='epass';IF native IS NULL OR connector IS NULL THEN RAISE EXCEPTION 'fixture_missing';END IF;
 INSERT INTO tj.platform_connector_connections(organization_id,connector_id,display_name,created_by,settings) VALUES(org,connector,'Rollback ePASS test',source_actor,'{"private":"must-not-return"}') RETURNING id INTO conn;
 PERFORM set_config('request.jwt.claim.sub',native::text,true);PERFORM set_config('test.epass.native',native::text,true);PERFORM set_config('test.epass.actor',source_actor::text,true);PERFORM set_config('test.epass.connection',conn::text,true);PERFORM set_config('test.epass.org',org::text,true);
END $$;
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb;conn text:=current_setting('test.epass.connection');bad jsonb;BEGIN
 r:=public.tj_epass_setup(jsonb_build_object('connection_id',conn));IF r::text LIKE '%must-not-return%' OR r::text LIKE '%credential_ref%' OR r->>'sync_ready'<>'false' THEN RAISE EXCEPTION 'unsafe_status';END IF;
 BEGIN PERFORM public.tj_epass_setup(jsonb_build_object('connection_id',gen_random_uuid()));RAISE EXCEPTION 'foreign_connection_accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN PERFORM public.tj_epass_setup(jsonb_build_object('action','test','connection_id',conn));RAISE EXCEPTION 'unconfigured_test_accepted';EXCEPTION WHEN serialization_failure THEN NULL;END;
 FOR bad IN SELECT * FROM jsonb_array_elements('[{"base_url":"http://epass.example","endpoints":{"customers":"customers"}},{"base_url":"https://epass.example","endpoints":{"customers":"https://evil.example"}},{"base_url":"https://epass.example","endpoints":{"unknown":"rows"}},{"base_url":"https://epass.example","endpoints":{"customers":"customers"},"api_key_header":"Authorization"},{"base_url":"https://epass.example","endpoints":{"customers":"customers"},"credential":{"password":"synthetic"}}]'::jsonb) LOOP
  BEGIN PERFORM public.tj_epass_setup(bad||jsonb_build_object('action','configure','connection_id',conn));RAISE EXCEPTION 'invalid_config_accepted';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 END LOOP;
 r:=public.tj_epass_setup(jsonb_build_object('action','configure','connection_id',conn,'base_url','https://epass.example/api','endpoints',jsonb_build_object('customers','customers'),'credential',jsonb_build_object('api_key','rollback-synthetic')));IF r->>'ok'<>'true' THEN RAISE EXCEPTION 'configure_failed';END IF;
 r:=public.tj_epass_setup(jsonb_build_object('connection_id',conn));IF r::text LIKE '%rollback-synthetic%' OR r#>>'{configuration,configured}'<>'true' THEN RAISE EXCEPTION 'credential_leak_or_missing';END IF;PERFORM set_config('test.epass.version',r->>'version',true);
 r:=public.tj_epass_setup(jsonb_build_object('action','sync','connection_id',conn));IF r->>'ok'<>'false' OR r->>'error'<>'epass_import_dependencies_pending' THEN RAISE EXCEPTION 'sync_false_ready';END IF;
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);BEGIN PERFORM public.tj_epass_setup(jsonb_build_object('connection_id',conn));RAISE EXCEPTION 'unmapped_accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 PERFORM set_config('request.jwt.claim.sub',current_setting('test.epass.native'),true);
END $$;
RESET ROLE;
DO $$ DECLARE c tj.platform_connector_connections%rowtype;BEGIN
 SELECT * INTO c FROM tj.platform_connector_connections WHERE id=current_setting('test.epass.connection')::uuid;IF c.status<>'pending' OR c.settings->>'destination_connection_verified'<>'false' THEN RAISE EXCEPTION 'false_activation';END IF;
 UPDATE tj.organization_members SET role='member' WHERE organization_id=c.organization_id AND user_id=current_setting('test.epass.actor')::uuid;
END $$;
SET LOCAL ROLE authenticated;
DO $$ BEGIN
 BEGIN PERFORM public.tj_epass_setup(jsonb_build_object('connection_id',current_setting('test.epass.connection')));RAISE EXCEPTION 'nonadmin_accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END $$;
RESET ROLE;
UPDATE tj.organization_members SET role='admin' WHERE organization_id=current_setting('test.epass.org')::uuid AND user_id=current_setting('test.epass.actor')::uuid;
SET LOCAL ROLE service_role;
DO $$ DECLARE r jsonb;BEGIN
 r:=public.aiq_epass_test_context(current_setting('test.epass.connection')::uuid,current_setting('test.epass.native')::uuid,current_setting('test.epass.version')::timestamptz);IF r#>>'{credential,api_key}'<>'rollback-synthetic' THEN RAISE EXCEPTION 'service_credential_load_failed';END IF;
 BEGIN PERFORM public.aiq_epass_test_context(current_setting('test.epass.connection')::uuid,gen_random_uuid(),current_setting('test.epass.version')::timestamptz);RAISE EXCEPTION 'foreign_actor_secret_accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN PERFORM public.aiq_epass_test_context(current_setting('test.epass.connection')::uuid,current_setting('test.epass.native')::uuid,now()-interval '1 day');RAISE EXCEPTION 'stale_config_accepted';EXCEPTION WHEN serialization_failure THEN NULL;END;
END $$;
RESET ROLE;
DO $$ BEGIN
 IF has_function_privilege('anon','public.tj_epass_setup(jsonb)','EXECUTE') OR has_function_privilege('authenticated','public.aiq_epass_test_context(uuid,uuid,timestamptz)','EXECUTE') OR has_function_privilege('service_role','public.tj_epass_setup(jsonb)','EXECUTE') THEN RAISE EXCEPTION 'unsafe_grants';END IF;
 IF EXISTS(SELECT 1 FROM tj.platform_sync_jobs WHERE connection_id=current_setting('test.epass.connection')::uuid) THEN RAISE EXCEPTION 'premature_job';END IF;
END $$;
ROLLBACK;
