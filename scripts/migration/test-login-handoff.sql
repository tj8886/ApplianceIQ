BEGIN;
SET LOCAL statement_timeout='20s';
DO $$ DECLARE target_u uuid; source_u uuid; org uuid; other_org uuid; unmapped uuid; i integer; BEGIN
 SELECT im.target_user_id,im.source_user_id,m.organization_id INTO target_u,source_u,org
 FROM tj.source_user_identity_map im JOIN tj.organization_members m ON m.user_id=im.source_user_id
 JOIN tj.organizations o ON o.id=m.organization_id AND o.deleted_at IS NULL
 WHERE im.activation_status='activated' AND m.status='active'
 AND NOT EXISTS(SELECT 1 FROM tj.platform_admins a WHERE a.user_id=im.source_user_id)
 ORDER BY im.source_user_id LIMIT 1;
 SELECT o.id INTO other_org FROM tj.organizations o WHERE o.id<>org AND NOT EXISTS(
 SELECT 1 FROM tj.organization_members m WHERE m.user_id=source_u AND m.organization_id=o.id AND m.status='active') LIMIT 1;
 SELECT u.id INTO unmapped FROM auth.users u WHERE NOT EXISTS(
 SELECT 1 FROM tj.source_user_identity_map m WHERE m.target_user_id=u.id AND m.activation_status='activated') LIMIT 1;
 IF target_u IS NULL OR other_org IS NULL OR unmapped IS NULL THEN RAISE EXCEPTION 'Handoff fixtures unavailable'; END IF;
 PERFORM set_config('test.target',target_u::text,true);
 PERFORM set_config('test.source',source_u::text,true);
 PERFORM set_config('test.org',org::text,true);
 PERFORM set_config('test.other_org',other_org::text,true);
 PERFORM set_config('test.unmapped',unmapped::text,true);
 FOR i IN 1..5 LOOP PERFORM set_config('test.hash'||i,md5(gen_random_uuid()::text)||md5(gen_random_uuid()::text),true); END LOOP;
END $$;
SET LOCAL ROLE service_role;
DO $$ DECLARE uid uuid:=current_setting('test.target')::uuid;
 ctx jsonb:=jsonb_build_object('organization_id',current_setting('test.org'),'location_id',NULL);
 result jsonb; i integer; BEGIN
 FOR i IN 1..4 LOOP
 IF NOT public.issue_tj_platform_handoff(uid,current_setting('test.hash'||i),'crm',ctx)
 THEN RAISE EXCEPTION 'Authorized ticket issue failed'; END IF;
 END LOOP;
 IF public.issue_tj_platform_handoff(uid,current_setting('test.hash5'),'crm',jsonb_build_object('organization_id',current_setting('test.other_org')))
 THEN RAISE EXCEPTION 'Foreign organization ticket issued'; END IF;
 IF public.issue_tj_platform_handoff(uid,current_setting('test.hash5'),'crm',ctx||jsonb_build_object('location_id','00000000-0000-0000-0000-000000000000'))
 THEN RAISE EXCEPTION 'Invalid location ticket issued'; END IF;
 IF public.issue_tj_platform_handoff(current_setting('test.unmapped')::uuid,current_setting('test.hash5'),'crm',ctx)
 THEN RAISE EXCEPTION 'Unmapped ticket issued'; END IF;
 IF public.consume_tj_platform_handoff(current_setting('test.hash1'),'academy') IS NOT NULL
 THEN RAISE EXCEPTION 'Wrong-module ticket redeemed'; END IF;
 result:=public.consume_tj_platform_handoff(current_setting('test.hash1'),'crm');
 IF result->>'user_id' IS DISTINCT FROM uid::text OR result->'context'->>'organization_id' IS DISTINCT FROM current_setting('test.org')
 THEN RAISE EXCEPTION 'Correct-module redemption failed'; END IF;
 IF public.consume_tj_platform_handoff(current_setting('test.hash1'),'crm') IS NOT NULL
 THEN RAISE EXCEPTION 'Ticket replay accepted'; END IF;
END $$;
RESET ROLE;
UPDATE tj_private.platform_handoff_tickets SET created_at=clock_timestamp()-interval '4 minutes',
 expires_at=clock_timestamp()-interval '2 minutes' WHERE ticket_hash=current_setting('test.hash2');
SET LOCAL ROLE service_role;
DO $$ BEGIN IF public.consume_tj_platform_handoff(current_setting('test.hash2'),'crm') IS NOT NULL
 THEN RAISE EXCEPTION 'Expired ticket accepted'; END IF; END $$;
RESET ROLE;
UPDATE tj.organization_members SET status='suspended'
WHERE user_id=current_setting('test.source')::uuid AND organization_id=current_setting('test.org')::uuid;
SET LOCAL ROLE service_role;
DO $$ BEGIN IF public.consume_tj_platform_handoff(current_setting('test.hash3'),'crm') IS NOT NULL
 THEN RAISE EXCEPTION 'Revoked membership ticket accepted'; END IF; END $$;
RESET ROLE;
UPDATE tj.organization_members SET status='active'
WHERE user_id=current_setting('test.source')::uuid AND organization_id=current_setting('test.org')::uuid;
UPDATE auth.users SET banned_until=now()+interval '1 day' WHERE id=current_setting('test.target')::uuid;
SET LOCAL ROLE service_role;
DO $$ BEGIN IF public.consume_tj_platform_handoff(current_setting('test.hash4'),'crm') IS NOT NULL
 THEN RAISE EXCEPTION 'Banned-account ticket accepted'; END IF; END $$;
RESET ROLE;
DO $$ DECLARE r record; BEGIN
 FOR r IN SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE (n.nspname='tj_private' AND p.proname IN ('handoff_source_user','issue_platform_handoff','consume_platform_handoff'))
 OR (n.nspname='public' AND p.proname IN ('issue_tj_platform_handoff','consume_tj_platform_handoff')) LOOP
 IF has_function_privilege('anon',r.oid,'EXECUTE') OR has_function_privilege('authenticated',r.oid,'EXECUTE')
 THEN RAISE EXCEPTION 'Handoff service RPC exposed to user roles'; END IF;
 END LOOP;
 IF has_table_privilege('service_role','tj_private.platform_handoff_tickets','SELECT')
 OR has_table_privilege('authenticated','tj_private.platform_handoff_tickets','SELECT')
 THEN RAISE EXCEPTION 'Private handoff tickets readable'; END IF;
END $$;
ROLLBACK;
SELECT 'Handoff issue/redemption/isolation checks passed; all writes rolled back' result;
