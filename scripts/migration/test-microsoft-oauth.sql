BEGIN;SET LOCAL statement_timeout='30s';
DO $$ DECLARE native uuid;actor uuid;org uuid;connector uuid;variant uuid;conn uuid;BEGIN
 SELECT im.target_user_id,im.source_user_id,m.organization_id INTO native,actor,org FROM tj.source_user_identity_map im JOIN tj.organization_members m ON m.user_id=im.source_user_id JOIN tj.organizations o ON o.id=m.organization_id WHERE im.activation_status='activated' AND m.status='active' AND m.role IN('owner','admin') AND o.status='active' AND o.deleted_at IS NULL LIMIT 1;
 SELECT c.id,v.id INTO connector,variant FROM tj.platform_connectors c JOIN tj.platform_connector_variants v ON v.connector_id=c.id WHERE c.key='microsoft_dynamics_365' AND v.key='business_central';
 INSERT INTO tj.platform_connector_connections(organization_id,connector_id,variant_id,display_name,created_by) VALUES(org,connector,variant,'Rollback Microsoft auth',actor) RETURNING id INTO conn;
 PERFORM set_config('request.jwt.claim.sub',native::text,true);PERFORM set_config('test.ms.native',native::text,true);PERFORM set_config('test.ms.actor',actor::text,true);PERFORM set_config('test.ms.org',org::text,true);PERFORM set_config('test.ms.conn',conn::text,true);
END $$;
SET LOCAL ROLE authenticated;
DO $$ DECLARE b jsonb:=jsonb_build_object('connection_id',current_setting('test.ms.conn'),'state_hash',repeat('a',64),'nonce',repeat('b',64),'verifier',repeat('c',64),'client_id','22222222-2222-4222-8222-222222222222','redirect_uri','https://us.test/functions/v1/microsoft-dynamics-auth','return_url','https://app.example/integrations.html');BEGIN
 PERFORM set_config('test.ms.body',b::text,true);
 BEGIN PERFORM public.tj_microsoft_oauth_begin(b);RAISE EXCEPTION 'unreviewed_tenant_accepted';EXCEPTION WHEN serialization_failure THEN NULL;END;
 BEGIN PERFORM public.tj_microsoft_oauth_begin(b||jsonb_build_object('connection_id',gen_random_uuid()));RAISE EXCEPTION 'foreign_connection_accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END $$;
RESET ROLE;
INSERT INTO tj_private.microsoft_oauth_review VALUES(current_setting('test.ms.conn')::uuid,current_setting('test.ms.org')::uuid,'11111111-1111-4111-8111-111111111111',current_setting('test.ms.actor')::uuid,clock_timestamp()+interval '1 hour');
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb;BEGIN
 r:=public.tj_microsoft_oauth_begin(current_setting('test.ms.body')::jsonb);IF r->>'tenant_id'<>'11111111-1111-4111-8111-111111111111' THEN RAISE EXCEPTION 'begin_failed';END IF;
END $$;
SET LOCAL ROLE service_role;
DO $$ DECLARE r jsonb;BEGIN
 r:=public.aiq_microsoft_oauth_context(repeat('a',64),NULL,false);IF r->>'verifier' IS NOT NULL OR r->>'nonce' IS NOT NULL THEN RAISE EXCEPTION 'callback_transport_secret_leak';END IF;
 BEGIN PERFORM public.aiq_microsoft_oauth_context(repeat('a',64),gen_random_uuid(),true);RAISE EXCEPTION 'foreign_actor_accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 r:=public.aiq_microsoft_oauth_context(repeat('a',64),current_setting('test.ms.native')::uuid,true);IF r->>'verifier'<>repeat('c',64) THEN RAISE EXCEPTION 'verifier_load_failed';END IF;
 BEGIN PERFORM public.aiq_microsoft_oauth_context(repeat('a',64),current_setting('test.ms.native')::uuid,true);RAISE EXCEPTION 'state_replay_accepted';EXCEPTION WHEN serialization_failure THEN NULL;END;
 BEGIN PERFORM public.aiq_microsoft_oauth_finish(repeat('a',64),current_setting('test.ms.native')::uuid,'{"tenant_id":"foreign","token_type":"Bearer","access_token":"synthetic","refresh_token":"synthetic","subject":"synthetic"}');RAISE EXCEPTION 'foreign_tenant_credential_accepted';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 r:=public.aiq_microsoft_oauth_finish(repeat('a',64),current_setting('test.ms.native')::uuid,'{"tenant_id":"11111111-1111-4111-8111-111111111111","token_type":"Bearer","access_token":"synthetic-access","refresh_token":"synthetic-refresh","subject":"synthetic-subject","scope":"https://api.businesscentral.dynamics.com/user_impersonation"}');
 IF r->>'status'<>'pending' OR r->>'requires_api_verification'<>'true' OR r::text LIKE '%synthetic-access%' THEN RAISE EXCEPTION 'finish_failed_or_leaked';END IF;
 BEGIN PERFORM public.aiq_microsoft_oauth_finish(repeat('a',64),current_setting('test.ms.native')::uuid,'{}');RAISE EXCEPTION 'double_completion_accepted';EXCEPTION WHEN serialization_failure THEN NULL;END;
END $$;
RESET ROLE;
DO $$ BEGIN
 IF (SELECT status<>'pending' OR auth_status<>'valid' OR settings->>'destination_connection_verified'<>'false' FROM tj.platform_connector_connections WHERE id=current_setting('test.ms.conn')::uuid) THEN RAISE EXCEPTION 'false_connection_activation';END IF;
 IF NOT EXISTS(SELECT 1 FROM tj_private.microsoft_credentials c JOIN vault.decrypted_secrets v ON v.id=c.secret_id WHERE c.connection_id=current_setting('test.ms.conn')::uuid AND c.organization_id=current_setting('test.ms.org')::uuid AND v.decrypted_secret::jsonb->>'access_token'='synthetic-access') THEN RAISE EXCEPTION 'vault_provenance_failed';END IF;
 IF has_function_privilege('authenticated','public.aiq_microsoft_oauth_context(text,uuid,boolean)','EXECUTE') OR has_function_privilege('anon','public.tj_microsoft_oauth_begin(jsonb)','EXECUTE') OR has_table_privilege('service_role','tj_private.microsoft_oauth_sessions','SELECT') THEN RAISE EXCEPTION 'unsafe_grants';END IF;
END $$;
SET LOCAL ROLE authenticated;
SELECT public.tj_microsoft_oauth_begin(current_setting('test.ms.body')::jsonb||jsonb_build_object('state_hash',repeat('d',64)));
RESET ROLE;
UPDATE tj.platform_connector_connections SET updated_at=clock_timestamp()+interval '1 second' WHERE id=current_setting('test.ms.conn')::uuid;
SET LOCAL ROLE service_role;
DO $$ BEGIN
 BEGIN PERFORM public.aiq_microsoft_oauth_context(repeat('d',64),current_setting('test.ms.native')::uuid,true);RAISE EXCEPTION 'stale_connection_accepted';EXCEPTION WHEN serialization_failure THEN NULL;END;
END $$;
RESET ROLE;
UPDATE tj.organization_members SET role='member' WHERE organization_id=current_setting('test.ms.org')::uuid AND user_id=current_setting('test.ms.actor')::uuid;
SET LOCAL ROLE authenticated;
DO $$ BEGIN
 BEGIN PERFORM public.tj_microsoft_oauth_begin(current_setting('test.ms.body')::jsonb||jsonb_build_object('state_hash',repeat('e',64)));RAISE EXCEPTION 'nonadmin_accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END $$;
ROLLBACK;
