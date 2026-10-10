BEGIN;
SET LOCAL statement_timeout='30s';
DO $$DECLARE native uuid;actor uuid;org uuid;connector uuid;conn uuid;BEGIN
 SELECT im.target_user_id,im.source_user_id,m.organization_id INTO native,actor,org FROM tj.source_user_identity_map im JOIN tj.organization_members m ON m.user_id=im.source_user_id JOIN tj.organizations o ON o.id=m.organization_id WHERE im.activation_status='activated' AND m.status='active' AND m.role IN('owner','admin') AND o.status='active' AND o.deleted_at IS NULL LIMIT 1;
 IF native IS NULL THEN RAISE EXCEPTION 'missing_native_admin_fixture';END IF;
 SELECT id INTO connector FROM tj.platform_connectors WHERE key='shopify';
 INSERT INTO tj.platform_connector_connections(organization_id,connector_id,display_name,created_by,status,external_account_id) VALUES(org,connector,'Rollback Shopify OAuth',actor,'pending','migration-rollback.myshopify.com') RETURNING id INTO conn;
 PERFORM set_config('test.shopify.native',native::text,true);PERFORM set_config('test.shopify.actor',actor::text,true);PERFORM set_config('test.shopify.org',org::text,true);PERFORM set_config('test.shopify.conn',conn::text,true);
 PERFORM set_config('test.shopify.body',jsonb_build_object('connection_id',conn,'shop','migration-rollback.myshopify.com','state_hash',repeat('a',64),'client_id','synthetic-client-key','redirect_uri','https://jdxslqmgjsuzoisuhvlc.supabase.co/functions/v1/shopify-auth/callback','return_url','https://app.example/integrations','scopes','read_customers,read_orders,read_products,read_inventory,read_locations,write_customers')::text,true);
END $$;
SET LOCAL ROLE service_role;
DO $$DECLARE b jsonb:=current_setting('test.shopify.body')::jsonb;r jsonb;BEGIN
 BEGIN PERFORM public.aiq_shopify_oauth_begin(gen_random_uuid(),b);RAISE EXCEPTION 'unmapped_accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN PERFORM public.aiq_shopify_oauth_begin(current_setting('test.shopify.native')::uuid,b||jsonb_build_object('connection_id',gen_random_uuid()));RAISE EXCEPTION 'foreign_connection_accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN PERFORM public.aiq_shopify_oauth_begin(current_setting('test.shopify.native')::uuid,b||jsonb_build_object('shop','evil.example'));RAISE EXCEPTION 'foreign_host_accepted';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 r:=public.aiq_shopify_oauth_begin(current_setting('test.shopify.native')::uuid,b);IF r->>'ok'<>'true' THEN RAISE EXCEPTION 'begin_failed';END IF;
 r:=public.aiq_shopify_oauth_context(repeat('a',64),NULL,false);IF r->>'shop'<>'migration-rollback.myshopify.com' OR r::text LIKE '%token%' THEN RAISE EXCEPTION 'context_failed';END IF;
 BEGIN PERFORM public.aiq_shopify_oauth_context(repeat('a',64),gen_random_uuid(),true);RAISE EXCEPTION 'foreign_claim_accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 PERFORM public.aiq_shopify_oauth_context(repeat('a',64),current_setting('test.shopify.native')::uuid,true);
 BEGIN PERFORM public.aiq_shopify_oauth_context(repeat('a',64),current_setting('test.shopify.native')::uuid,true);RAISE EXCEPTION 'replay_accepted';EXCEPTION WHEN serialization_failure THEN NULL;END;
 BEGIN PERFORM public.aiq_shopify_oauth_finish(repeat('a',64),current_setting('test.shopify.native')::uuid,'{"shop":"foreign.myshopify.com","access_token":"synthetic","scope":"read_customers,read_orders,read_products,read_inventory,read_locations,write_customers"}');RAISE EXCEPTION 'wrong_shop_saved';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 r:=public.aiq_shopify_oauth_finish(repeat('a',64),current_setting('test.shopify.native')::uuid,'{"shop":"migration-rollback.myshopify.com","access_token":"synthetic-access","refresh_token":"synthetic-refresh","scope":"read_customers,read_orders,read_products,read_inventory,read_locations,write_customers"}');IF r->>'status'<>'pending' OR r->>'requires_api_verification'<>'true' OR r->>'webhooks_registered'<>'false' OR r::text LIKE '%synthetic-access%' THEN RAISE EXCEPTION 'finish_false_activation_or_leak';END IF;
 BEGIN PERFORM public.aiq_shopify_oauth_finish(repeat('a',64),current_setting('test.shopify.native')::uuid,'{}');RAISE EXCEPTION 'double_completion';EXCEPTION WHEN serialization_failure THEN NULL;END;
END $$;
RESET ROLE;
DO $$BEGIN
 IF NOT EXISTS(SELECT 1 FROM tj_private.shopify_credentials c JOIN vault.decrypted_secrets v ON v.id=c.secret_id WHERE c.connection_id=current_setting('test.shopify.conn')::uuid AND c.organization_id=current_setting('test.shopify.org')::uuid AND v.decrypted_secret::jsonb->>'access_token'='synthetic-access') THEN RAISE EXCEPTION 'vault_provenance_failed';END IF;
 IF NOT EXISTS(SELECT 1 FROM tj.platform_connector_connections WHERE id=current_setting('test.shopify.conn')::uuid AND status='pending' AND auth_status='valid' AND settings->>'destination_connection_verified'='false') THEN RAISE EXCEPTION 'false_activation';END IF;
 IF has_function_privilege('authenticated','public.aiq_shopify_oauth_begin(uuid,jsonb)','EXECUTE') OR has_function_privilege('anon','public.aiq_shopify_oauth_context(text,uuid,boolean)','EXECUTE') OR has_table_privilege('service_role','tj_private.shopify_credentials','SELECT') OR has_table_privilege('authenticated','tj_private.shopify_oauth_sessions','SELECT') THEN RAISE EXCEPTION 'unsafe_grants';END IF;
END $$;
DO $$DECLARE c tj.platform_connector_connections%rowtype;sid uuid;v timestamptz;BEGIN
 SELECT * INTO c FROM tj.platform_connector_connections WHERE id=current_setting('test.shopify.conn')::uuid;
 SELECT secret_id INTO sid FROM tj_private.shopify_credentials WHERE connection_id=c.id;
 SELECT updated_at INTO v FROM vault.decrypted_secrets WHERE id=sid;
 INSERT INTO tj_private.shopify_verified_connections(connection_id,organization_id,secret_id,secret_updated_at,connection_version,shop_id,shop_domain,currency,scopes,expires_at) VALUES(c.id,c.organization_id,sid,v,c.updated_at,'gid://shopify/Shop/123','migration-rollback.myshopify.com','CAD','[]',clock_timestamp()+interval '15 minutes');
 INSERT INTO tj_private.shopify_verification_sessions(organization_id,connection_id,native_user,secret_id,secret_updated_at,connection_version,shop_domain) VALUES(c.organization_id,c.id,current_setting('test.shopify.native')::uuid,sid,v,c.updated_at,'migration-rollback.myshopify.com');
END $$;
SET LOCAL ROLE service_role;
DO $$DECLARE b jsonb:=current_setting('test.shopify.body')::jsonb;native uuid:=current_setting('test.shopify.native')::uuid;r jsonb;BEGIN
 BEGIN PERFORM public.aiq_shopify_oauth_begin(native,b||jsonb_build_object('scopes',b->>'scopes'||',write_draft_orders'));RAISE EXCEPTION 'draft_scope_without_optin';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 BEGIN PERFORM public.aiq_shopify_oauth_begin(native,b||'{"draft_orders":"true"}'::jsonb);RAISE EXCEPTION 'string_optin_accepted';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 BEGIN PERFORM public.aiq_shopify_oauth_begin(native,b||'{"draft_orders":true}'::jsonb);RAISE EXCEPTION 'scope_flag_mismatch';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 b:=b||jsonb_build_object('state_hash',repeat('d',64),'draft_orders',true,'scopes',b->>'scopes'||',write_draft_orders');
 PERFORM public.aiq_shopify_oauth_begin(native,b);
 r:=public.aiq_shopify_oauth_context(repeat('d',64),native,true);IF r->>'scopes' IS DISTINCT FROM b->>'scopes' THEN RAISE EXCEPTION 'draft_intent_not_bound';END IF;
 BEGIN PERFORM public.aiq_shopify_oauth_finish(repeat('d',64),native,jsonb_build_object('shop',b->>'shop','access_token','synthetic-rotated','scope',current_setting('test.shopify.body')::jsonb->>'scopes'));RAISE EXCEPTION 'missing_draft_grant_accepted';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 r:=public.aiq_shopify_oauth_finish(repeat('d',64),native,jsonb_build_object('shop',b->>'shop','access_token','synthetic-rotated','scope',replace(b->>'scopes','read_customers,','')));
 IF r->>'draft_order_permission_granted'<>'true' OR r->>'draft_creation_enabled'<>'false' OR r->>'status'<>'pending' THEN RAISE EXCEPTION 'false_activation';END IF;
END $$;
RESET ROLE;
DO $$BEGIN
 IF EXISTS(SELECT 1 FROM tj_private.shopify_verified_connections WHERE connection_id=current_setting('test.shopify.conn')::uuid) OR EXISTS(SELECT 1 FROM tj_private.shopify_verification_sessions WHERE connection_id=current_setting('test.shopify.conn')::uuid AND completed_at IS NULL AND expires_at>clock_timestamp()) THEN RAISE EXCEPTION 'old_provider_proof_or_session_survived_reauthorization';END IF;
END $$;
SET LOCAL ROLE service_role;
SELECT public.aiq_shopify_oauth_begin(current_setting('test.shopify.native')::uuid,current_setting('test.shopify.body')::jsonb||jsonb_build_object('state_hash',repeat('b',64)));
RESET ROLE;
UPDATE tj.platform_connector_connections SET updated_at=clock_timestamp()+interval '1 second' WHERE id=current_setting('test.shopify.conn')::uuid;
SET LOCAL ROLE service_role;
DO $$BEGIN
 BEGIN PERFORM public.aiq_shopify_oauth_context(repeat('b',64),current_setting('test.shopify.native')::uuid,true);RAISE EXCEPTION 'stale_connection_accepted';EXCEPTION WHEN serialization_failure THEN NULL;END;
END $$;
RESET ROLE;
UPDATE tj.organization_members SET role='member' WHERE organization_id=current_setting('test.shopify.org')::uuid AND user_id=current_setting('test.shopify.actor')::uuid;
SET LOCAL ROLE service_role;
DO $$BEGIN
 BEGIN PERFORM public.aiq_shopify_oauth_begin(current_setting('test.shopify.native')::uuid,current_setting('test.shopify.body')::jsonb||jsonb_build_object('state_hash',repeat('c',64)));RAISE EXCEPTION 'nonadmin_accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END $$;
ROLLBACK;

SELECT 'PASS: explicit scope intent, missing grant/forged flag denial, write-implies-read, proof invalidation, replay/admin/version/grants regression; fixtures rolled back' result;
