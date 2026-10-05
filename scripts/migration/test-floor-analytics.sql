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
DO $$ DECLARE org uuid:=current_setting('test.org')::uuid; other uuid:=current_setting('test.foreign')::uuid; r jsonb; f text; BEGIN
 r:=tj.get_floor_vs_sales(org);
 IF (r->>'total_floor_units')::numeric<>current_setting('test.floor.units')::numeric
 OR (r->>'total_displays')::bigint<>current_setting('test.floor.displays')::bigint
 OR (r->>'total_skus')::bigint<>current_setting('test.floor.skus')::bigint THEN RAISE EXCEPTION 'Floor totals mismatch'; END IF;
 IF jsonb_typeof(tj.get_floor_by_store(org))<>'array'
 OR jsonb_typeof(tj.get_floor_gaps(org)->'sku_detail')<>'array'
 OR jsonb_typeof(tj.get_floor_holes(org)->'holes')<>'array'
 THEN RAISE EXCEPTION 'Floor response shape mismatch'; END IF;
 FOREACH f IN ARRAY ARRAY['get_floor_vs_sales','get_floor_by_store','get_floor_gaps','get_floor_holes'] LOOP
 BEGIN EXECUTE format('SELECT tj.%I($1)',f) USING other;
 RAISE EXCEPTION 'Foreign organization accepted: %',f;
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 FOREACH f IN ARRAY ARRAY['get_floor_vs_sales','get_floor_by_store','get_floor_gaps','get_floor_holes'] LOOP
 BEGIN EXECUTE format('SELECT tj.%I($1)',f) USING org;
 RAISE EXCEPTION 'Unmapped caller accepted: %',f;
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
END $$;
RESET ROLE;
DO $$ DECLARE f text; sig text; BEGIN
 FOREACH f IN ARRAY ARRAY['get_floor_vs_sales','get_floor_by_store','get_floor_gaps','get_floor_holes'] LOOP
 sig:=CASE WHEN f='get_floor_holes' THEN 'uuid,uuid' ELSE 'uuid' END;
 IF has_function_privilege('anon',format('tj.%I(%s)',f,sig),'EXECUTE')
 OR has_function_privilege('anon',format('tj_private.%I(%s)',f,sig),'EXECUTE')
 THEN RAISE EXCEPTION 'Anonymous floor privilege'; END IF;
 END LOOP;
 RAISE NOTICE 'Four floor analytics passed totals, response, foreign-organization and unmapped/anonymous checks';
END $$;
ROLLBACK;
