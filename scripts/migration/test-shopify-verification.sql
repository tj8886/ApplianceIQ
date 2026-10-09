begin;set local statement_timeout='30s';
do $$declare native uuid;actor uuid;org uuid;connector uuid;conn uuid;begin
 select im.target_user_id,im.source_user_id,m.organization_id into native,actor,org from tj.source_user_identity_map im
 join tj.organization_members m on m.user_id=im.source_user_id join tj.organizations o on o.id=m.organization_id
 where im.activation_status='activated' and m.status='active' and m.role in ('owner','admin') and o.status='active' and o.deleted_at is null limit 1;
 select id into connector from tj.platform_connectors where key='shopify';if native is null or connector is null then raise exception 'missing_fixture';end if;
 insert into tj.platform_connector_connections(organization_id,connector_id,display_name,created_by,credential_ref,settings,external_account_id) values(org,connector,'Rollback Shopify preflight',actor,'PRIVATE-CREDENTIAL-REF','{"private":"NEVER-RETURN","destination_connection_verified":true}',gen_random_uuid()::text) returning id into conn;
 perform set_config('request.jwt.claim.sub',native::text,true);perform set_config('test.shopify.native',native::text,true);perform set_config('test.shopify.actor',actor::text,true);perform set_config('test.shopify.org',org::text,true);perform set_config('test.shopify.connection',conn::text,true);
end $$;
SET LOCAL ROLE service_role;
DO $$ BEGIN
 BEGIN PERFORM public.aiq_shopify_verify_begin(current_setting('test.shopify.native')::uuid,current_setting('test.shopify.connection')::uuid);RAISE EXCEPTION 'imported_credential_ref_accepted';EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;END;
END $$;
RESET ROLE;
DO $$ DECLARE shop text:='fixture-'||gen_random_uuid()||'.myshopify.com';sid uuid;BEGIN
 sid:=vault.create_secret(jsonb_build_object('shop',shop,'access_token','PRIVATE-SYNTHETIC-TOKEN','scope','read_products','expires_at',clock_timestamp()+interval '1 hour')::text);
 INSERT INTO tj_private.shopify_credentials VALUES(current_setting('test.shopify.connection')::uuid,current_setting('test.shopify.org')::uuid,shop,sid);
 UPDATE tj.platform_connector_connections SET external_account_id=shop,credential_ref=sid::text WHERE id=current_setting('test.shopify.connection')::uuid;
 PERFORM set_config('test.shopify.shop',shop,true);PERFORM set_config('test.shopify.secret',sid::text,true);
END $$;
SET LOCAL ROLE service_role;
DO $$ DECLARE ctx jsonb;r jsonb;result jsonb;BEGIN
 ctx:=public.aiq_shopify_verify_begin(current_setting('test.shopify.native')::uuid,current_setting('test.shopify.connection')::uuid);
 IF ctx->>'access_token'<>'PRIVATE-SYNTHETIC-TOKEN' THEN RAISE EXCEPTION 'fresh_vault_context_missing';END IF;
 result:=jsonb_build_object('shop_id','gid://shopify/Shop/999999999999999999999','shop',current_setting('test.shopify.shop'),'currency','CAD','scopes',jsonb_build_array('read_products'));
 BEGIN PERFORM public.aiq_shopify_verify_finish(current_setting('test.shopify.native')::uuid,(ctx->>'session_id')::uuid,result||jsonb_build_object('shop','different.myshopify.com'));RAISE EXCEPTION 'wrong_shop_accepted';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 r:=public.aiq_shopify_verify_finish(current_setting('test.shopify.native')::uuid,(ctx->>'session_id')::uuid,result);
 IF r->>'shop_identity_verified'<>'true' OR r->>'currency'<>'CAD' OR r->>'draft_order_scope_granted'<>'false' OR r->>'draft_creation_enabled'<>'false' OR r->>'connection_activated'<>'false' OR r::text LIKE '%PRIVATE%' THEN RAISE EXCEPTION 'false_scope_or_activation_or_secret_disclosure';END IF;
 BEGIN PERFORM public.aiq_shopify_verify_finish(current_setting('test.shopify.native')::uuid,(ctx->>'session_id')::uuid,result);RAISE EXCEPTION 'session_replay_accepted';EXCEPTION WHEN serialization_failure THEN NULL;END;
 ctx:=public.aiq_shopify_verify_begin(current_setting('test.shopify.native')::uuid,current_setting('test.shopify.connection')::uuid);
 PERFORM set_config('test.shopify.session',ctx->>'session_id',true);
 BEGIN PERFORM public.aiq_shopify_verify_begin(gen_random_uuid(),current_setting('test.shopify.connection')::uuid);RAISE EXCEPTION 'unmapped_user_accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END $$;
RESET ROLE;
-- Rotate through the supported Vault API. The rollback fixture models a captured
-- older version because now() stays fixed within this single test transaction.
SELECT vault.update_secret(current_setting('test.shopify.secret')::uuid,jsonb_build_object('shop',current_setting('test.shopify.shop'),'access_token','ROTATED-SYNTHETIC-TOKEN','scope','write_draft_orders','expires_at',clock_timestamp()+interval '1 hour')::text);
UPDATE tj_private.shopify_verification_sessions SET secret_updated_at=secret_updated_at-interval '1 second' WHERE id=current_setting('test.shopify.session')::uuid;
SET LOCAL ROLE service_role;
DO $$ DECLARE result jsonb;ctx jsonb;r jsonb;BEGIN
 result:=jsonb_build_object('shop_id','gid://shopify/Shop/999999999999999999999','shop',current_setting('test.shopify.shop'),'currency','CAD','scopes',jsonb_build_array('write_draft_orders'));
 BEGIN PERFORM public.aiq_shopify_verify_finish(current_setting('test.shopify.native')::uuid,current_setting('test.shopify.session')::uuid,result);RAISE EXCEPTION 'rotated_credential_accepted_stale_result';EXCEPTION WHEN serialization_failure THEN NULL;END;
 ctx:=public.aiq_shopify_verify_begin(current_setting('test.shopify.native')::uuid,current_setting('test.shopify.connection')::uuid);
 r:=public.aiq_shopify_verify_finish(current_setting('test.shopify.native')::uuid,(ctx->>'session_id')::uuid,result);
 IF r->>'draft_order_scope_granted'<>'true' OR r->>'draft_creation_enabled'<>'false' THEN RAISE EXCEPTION 'grant_validation_or_false_enablement';END IF;
 ctx:=public.aiq_shopify_verify_begin(current_setting('test.shopify.native')::uuid,current_setting('test.shopify.connection')::uuid);PERFORM set_config('test.shopify.session',ctx->>'session_id',true);
END $$;
RESET ROLE;
UPDATE tj_private.shopify_verification_sessions SET expires_at=clock_timestamp()-interval '1 second' WHERE id=current_setting('test.shopify.session')::uuid;
SET LOCAL ROLE service_role;
DO $$ BEGIN
 BEGIN PERFORM public.aiq_shopify_verify_finish(current_setting('test.shopify.native')::uuid,current_setting('test.shopify.session')::uuid,jsonb_build_object('shop_id','gid://shopify/Shop/123','shop',current_setting('test.shopify.shop'),'currency','CAD','scopes','[]'::jsonb));RAISE EXCEPTION 'expired_session_accepted';EXCEPTION WHEN serialization_failure THEN NULL;END;
END $$;
RESET ROLE;
DO $$ DECLARE f text;r text;BEGIN
 FOREACH f IN ARRAY ARRAY['public.aiq_shopify_verify_begin(uuid,uuid)','public.aiq_shopify_verify_finish(uuid,uuid,jsonb)'] LOOP FOREACH r IN ARRAY ARRAY['anon','authenticated'] LOOP IF has_function_privilege(r,f,'EXECUTE') THEN RAISE EXCEPTION 'unsafe_client_grants';END IF;END LOOP;END LOOP;
 IF EXISTS(SELECT 1 FROM tj.platform_connector_connections WHERE id=current_setting('test.shopify.connection')::uuid AND status<>'pending') THEN RAISE EXCEPTION 'premature_activation';END IF;
END $$;
ROLLBACK;
SELECT 'PASS: fresh Vault-only credentials, scope truth, exact shop/currency, replay/expiry/rotation denial, privacy, private grants and no activation; fixtures rolled back' result;
