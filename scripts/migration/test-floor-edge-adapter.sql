-- Read-only analytics checks; session settings and all fixtures roll back.
BEGIN;
SET LOCAL statement_timeout='25s';
DO $$ DECLARE u uuid; src uuid; org uuid; foreign_org uuid; BEGIN
 SELECT im.target_user_id,im.source_user_id,m.organization_id INTO u,src,org
 FROM tj.source_user_identity_map im JOIN tj.organization_members m ON m.user_id=im.source_user_id
 JOIN tj.organizations o ON o.id=m.organization_id AND o.deleted_at IS NULL
 WHERE im.activation_status='activated' AND m.status='active'
 AND NOT EXISTS(SELECT 1 FROM tj.platform_admins a WHERE a.user_id=im.source_user_id)
 ORDER BY (SELECT count(*) FROM tj.field_floor_displays d WHERE d.organization_id=m.organization_id) DESC LIMIT 1;
 SELECT o.id INTO foreign_org FROM tj.organizations o WHERE o.deleted_at IS NULL AND o.id<>org
 AND NOT EXISTS(SELECT 1 FROM tj.organization_members m WHERE m.user_id=src AND m.organization_id=o.id AND m.status='active') LIMIT 1;
 IF u IS NULL OR foreign_org IS NULL THEN RAISE EXCEPTION 'Member fixtures unavailable'; END IF;
 PERFORM set_config('request.jwt.claim.sub',u::text,true);
 PERFORM set_config('test.org',org::text,true);
 PERFORM set_config('test.foreign',foreign_org::text,true);
 PERFORM set_config('test.floor.units',(SELECT coalesce(sum(floor_units),0)::text FROM tj.field_floor_displays WHERE organization_id=org AND is_active),true);
 PERFORM set_config('test.floor.displays',(SELECT count(*)::text FROM tj.field_floor_displays WHERE organization_id=org AND is_active),true);
 PERFORM set_config('test.floor.skus',(SELECT count(*)::text FROM tj.field_floor_display_skus WHERE organization_id=org AND is_active),true);
END $$;
SET LOCAL ROLE authenticated;
DO $$ DECLARE org uuid:=current_setting('test.org')::uuid; r jsonb; BEGIN
 -- Explicitly test org-wide access only if this fixture is unrestricted.
 IF EXISTS(SELECT 1 FROM tj_private.unrestricted_store_organizations() o WHERE o=org) THEN
  r:=public.tj_floor_recommendation_data(org);
  IF jsonb_typeof(r->'categories')<>'array' OR (r->>'total_floor_units')::numeric<>current_setting('test.floor.units')::numeric THEN RAISE EXCEPTION 'recommendation totals mismatch'; END IF;
 ELSE
  BEGIN PERFORM public.tj_floor_recommendation_data(org); RAISE EXCEPTION 'Restricted caller accepted whole org'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END IF;
 BEGIN PERFORM public.tj_floor_recommendation_data(current_setting('test.foreign')::uuid); RAISE EXCEPTION 'Cross-org accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM public.tj_floor_recommendation_data(org,gen_random_uuid()); RAISE EXCEPTION 'Unknown store accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 BEGIN PERFORM public.tj_floor_recommendation_data(org); RAISE EXCEPTION 'Unmapped accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
DO $$ BEGIN
 IF has_function_privilege('anon','public.tj_floor_recommendation_data(uuid,uuid)','execute') THEN RAISE EXCEPTION 'Anonymous privilege'; END IF;
 RAISE NOTICE 'Floor Edge adapter: totals/scope, cross-org, unknown-store, unmapped and anonymous checks passed';
END $$;
ROLLBACK;
