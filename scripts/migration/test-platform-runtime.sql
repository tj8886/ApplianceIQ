-- Run against US East after the platform runtime migration. All writes roll back.
BEGIN;
DO $$ DECLARE u uuid; source_u uuid; org uuid; own_note uuid:=gen_random_uuid(); other_note uuid:=gen_random_uuid(); BEGIN
 SELECT im.target_user_id,im.source_user_id,m.organization_id INTO u,source_u,org
 FROM tj.source_user_identity_map im JOIN tj.organization_members m ON m.user_id=im.source_user_id
 JOIN tj.organizations o ON o.id=m.organization_id AND o.deleted_at IS NULL
 WHERE im.activation_status='activated' AND m.status='active'
 AND NOT EXISTS(SELECT 1 FROM tj.platform_admins a WHERE a.user_id=im.source_user_id)
 ORDER BY im.source_user_id,m.created_at LIMIT 1;
 IF u IS NULL THEN RAISE EXCEPTION 'Fixture requires an activated non-platform member'; END IF;
 PERFORM set_config('request.jwt.claim.sub',u::text,true);
 PERFORM set_config('test.source_user',source_u::text,true);
 PERFORM set_config('test.org',org::text,true);
 PERFORM set_config('test.own_note',own_note::text,true);
 PERFORM set_config('test.other_note',other_note::text,true);
 INSERT INTO tj.crm_notifications(id,organization_id,user_id,title,body)
 VALUES(own_note,org,source_u,'Migration rollback fixture','Not delivered'),
 (other_note,org,(SELECT id FROM tj.source_auth_users WHERE id<>source_u LIMIT 1),'Migration rollback fixture','Not delivered');
END $$;
SET LOCAL ROLE authenticated;
DO $$ DECLARE org uuid:=current_setting('test.org')::uuid; result jsonb; BEGIN
 IF NOT EXISTS(SELECT 1 FROM tj.my_platform_organizations() x WHERE x.organization_id=org)
 THEN RAISE EXCEPTION 'Own organization missing'; END IF;
 IF EXISTS(SELECT 1 FROM tj.my_platform_locations('00000000-0000-0000-0000-000000000000'))
 THEN RAISE EXCEPTION 'Unauthorized locations exposed'; END IF;
 PERFORM tj.my_entitled_apps();
 result:=tj.set_platform_context(p_organization_id=>org,p_source_module_key=>'migration-test',p_context=>'{}');
 IF result->>'organization_id' IS DISTINCT FROM org::text OR result->>'user_id' IS DISTINCT FROM auth.uid()::text
 THEN RAISE EXCEPTION 'Context roundtrip failed'; END IF;
 BEGIN
 PERFORM tj.set_platform_context(p_organization_id=>'00000000-0000-0000-0000-000000000000');
 RAISE EXCEPTION 'Unauthorized organization accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'organization_access_denied' THEN RAISE; END IF; END;
 BEGIN
 PERFORM tj.set_platform_context(p_organization_id=>org,p_location_id=>'00000000-0000-0000-0000-000000000000');
 RAISE EXCEPTION 'Unauthorized location accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'location_access_denied' THEN RAISE; END IF; END;
 IF NOT tj.platform_mark_notification_read(current_setting('test.own_note')::uuid)
 THEN RAISE EXCEPTION 'Own notification update failed'; END IF;
 IF tj.platform_mark_notification_read(current_setting('test.other_note')::uuid)
 THEN RAISE EXCEPTION 'Another user notification updated'; END IF;
 IF (SELECT count(*) FROM tj.crm_notifications WHERE id=current_setting('test.own_note')::uuid)<>1
 OR EXISTS(SELECT 1 FROM tj.crm_notifications WHERE id=current_setting('test.other_note')::uuid)
 THEN RAISE EXCEPTION 'Notification read isolation failed'; END IF;
 IF EXISTS(SELECT 1 FROM tj.platform_global_search('ap',50) x WHERE x.organization_id<>org)
 THEN RAISE EXCEPTION 'Search crossed organization boundary'; END IF;
 IF EXISTS(SELECT 1 FROM tj.platform_global_search('a',50))
 THEN RAISE EXCEPTION 'Short search query not rejected'; END IF;
 IF has_table_privilege(current_user,'tj.platform_user_context','INSERT')
 OR has_table_privilege(current_user,'tj.crm_notifications','UPDATE')
 THEN RAISE EXCEPTION 'Unnecessary direct write privileges'; END IF;
END $$;
RESET ROLE;
UPDATE tj.organization_members SET status='suspended'
WHERE user_id=current_setting('test.source_user')::uuid AND organization_id=current_setting('test.org')::uuid;
SET LOCAL ROLE authenticated;
DO $$ DECLARE result jsonb:=tj.my_platform_context(); BEGIN
 IF result->>'organization_id'=current_setting('test.org') THEN RAISE EXCEPTION 'Revoked saved context exposed'; END IF;
 IF tj.platform_mark_notification_read(current_setting('test.own_note')::uuid)
 THEN RAISE EXCEPTION 'Revoked organization notification updated'; END IF;
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000000',true);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
 IF tj.my_entitled_apps()<>'[]'::jsonb OR EXISTS(SELECT 1 FROM tj.my_platform_organizations())
 THEN RAISE EXCEPTION 'Unmapped caller exposed data'; END IF;
 IF EXISTS(SELECT 1 FROM tj.platform_modules) OR EXISTS(SELECT 1 FROM tj.crm_notifications)
 OR EXISTS(SELECT 1 FROM tj.platform_user_context) OR EXISTS(SELECT 1 FROM tj.iq_pos_transactions)
 THEN RAISE EXCEPTION 'Unmapped table read exposed data'; END IF;
 BEGIN PERFORM tj.my_platform_context(); RAISE EXCEPTION 'Unmapped caller accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'authentication_required' THEN RAISE; END IF; END;
 BEGIN PERFORM tj.set_platform_context(); RAISE EXCEPTION 'Unmapped writer accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'authentication_required' THEN RAISE; END IF; END;
END $$;
RESET ROLE;
DO $$ DECLARE r record; BEGIN
 FOR r IN SELECT p.oid,n.nspname,p.prosecdef,p.proconfig FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('tj','tj_private') AND p.proname IN ('my_entitled_apps','my_platform_organizations',
 'my_platform_locations','my_platform_context','set_platform_context','platform_mark_notification_read','platform_global_search','owns_source_user') LOOP
 IF has_function_privilege('anon',r.oid,'EXECUTE') THEN RAISE EXCEPTION 'Anonymous RPC execute grant'; END IF;
 IF r.nspname='tj' AND r.prosecdef THEN RAISE EXCEPTION 'Privileged API adapter'; END IF;
 IF NOT coalesce(r.proconfig @> ARRAY['search_path=""'],false) THEN RAISE EXCEPTION 'Unfixed function search path'; END IF;
 END LOOP;
END $$;
ROLLBACK;
SELECT 'Platform runtime checks passed; all test writes rolled back' AS result;
