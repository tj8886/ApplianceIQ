BEGIN;
SET LOCAL statement_timeout='10s';
DO $$DECLARE native uuid;actor uuid;org uuid;conn uuid;connector uuid;BEGIN
 SELECT im.target_user_id,im.source_user_id,m.organization_id INTO native,actor,org FROM tj.source_user_identity_map im JOIN tj.organization_members m ON m.user_id=im.source_user_id JOIN tj.organizations o ON o.id=m.organization_id WHERE im.activation_status='activated' AND m.status='active' AND m.role IN('owner','admin') AND o.status='active' AND o.deleted_at IS NULL LIMIT 1;
 SELECT id INTO connector FROM tj.platform_connectors WHERE key='shopify';
 INSERT INTO tj.platform_connector_connections(organization_id,connector_id,display_name,created_by,external_account_id) VALUES(org,connector,'Rollback Shopify bridge preview',actor,gen_random_uuid()::text) RETURNING id INTO conn;
 PERFORM set_config('request.jwt.claim.sub',native::text,true);PERFORM set_config('test.bridge.connection',conn::text,true);
END $$;
SET LOCAL ROLE authenticated;
DO $$DECLARE r jsonb;BEGIN
 r:=public.tj_shopify_initial_sync(jsonb_build_object('connection_id',current_setting('test.bridge.connection'),'action','status'));
 IF r->>'ok'<>'true' OR r->>'preflight_only'<>'true' OR r->>'executed'<>'false' OR r->>'connection_id'<>current_setting('test.bridge.connection') THEN RAISE EXCEPTION 'scoped_read_contract_failed';END IF;
 BEGIN PERFORM public.tj_shopify_initial_sync(jsonb_build_object('connection_id',gen_random_uuid(),'action','status'));RAISE EXCEPTION 'foreign_connection_accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END $$;
ROLLBACK;
SELECT 'PASS: live native tenant-admin read-only connection scope; foreign connection denied; fixture rolled back' result;
