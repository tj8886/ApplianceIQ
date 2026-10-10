BEGIN; SET LOCAL statement_timeout='30s';
DO $$ DECLARE u uuid;src uuid;org uuid;connector_key text;BEGIN
 SELECT im.target_user_id,im.source_user_id,m.organization_id INTO u,src,org FROM tj.source_user_identity_map im JOIN tj.organization_members m ON m.user_id=im.source_user_id JOIN tj.organizations o ON o.id=m.organization_id WHERE im.activation_status='activated' AND m.status='active' AND m.role IN ('owner','admin') AND o.status='active' AND o.deleted_at IS NULL LIMIT 1;
 connector_key:='migration-rollback-'||gen_random_uuid()::text; INSERT INTO tj.platform_connectors(key,name,vendor_name) VALUES(connector_key,'Rollback connector fixture','Synthetic');
 IF u IS NULL OR connector_key IS NULL THEN RAISE EXCEPTION 'Fixture unavailable';END IF;
 PERFORM set_config('request.jwt.claim.sub',u::text,true);PERFORM set_config('test.source',src::text,true);PERFORM set_config('test.org',org::text,true);PERFORM set_config('test.connector',connector_key,true);
END $$;
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb;c uuid;BEGIN
 r:=public.tj_connector_runtime('{}');IF jsonb_array_length(r->'connectors')=0 THEN RAISE EXCEPTION 'Catalog unavailable';END IF;
 r:=public.tj_connector_runtime(jsonb_build_object('action','prepare_connection','organization_id',current_setting('test.org'),'connector_key',current_setting('test.connector'),'settings',jsonb_build_object('source','rollback_test')));c:=(r#>>'{connection,id}')::uuid;PERFORM set_config('test.connection',c::text,true);
 r:=public.tj_connector_runtime(jsonb_build_object('action','queue_sync','organization_id',current_setting('test.org'),'connection_id',c));IF r#>>'{job,requested_by}'<>current_setting('test.source') THEN RAISE EXCEPTION 'Actor mismatch';END IF;
 BEGIN PERFORM public.tj_connector_runtime(jsonb_build_object('action','queue_sync','organization_id',current_setting('test.org'),'connection_id',c));RAISE EXCEPTION 'Duplicate sync accepted';EXCEPTION WHEN serialization_failure THEN NULL;END;
 BEGIN PERFORM public.tj_connector_runtime(jsonb_build_object('action','connections','organization_id',gen_random_uuid()));RAISE EXCEPTION 'Foreign org accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN PERFORM public.tj_connector_runtime(jsonb_build_object('action','prepare_connection','organization_id',current_setting('test.org'),'connector_key',current_setting('test.connector'),'store_id',gen_random_uuid()));RAISE EXCEPTION 'Foreign store accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN PERFORM public.tj_connector_runtime(jsonb_build_object('action','prepare_connection','organization_id',current_setting('test.org'),'connector_key',current_setting('test.connector'),'settings',jsonb_build_object('api_key','synthetic')));RAISE EXCEPTION 'Inline credential accepted';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 BEGIN PERFORM public.tj_connector_runtime('{}');RAISE EXCEPTION 'Unmapped identity accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END $$;
RESET ROLE;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM tj.platform_connector_connections WHERE id=current_setting('test.connection')::uuid AND created_by=current_setting('test.source')::uuid) THEN RAISE EXCEPTION 'Prepared actor mismatch';END IF;
 IF has_function_privilege('anon','public.tj_connector_runtime(jsonb)','EXECUTE') OR has_function_privilege('service_role','public.tj_connector_runtime(jsonb)','EXECUTE') THEN RAISE EXCEPTION 'Unauthenticated broker grants';END IF;
END $$;
ROLLBACK;
