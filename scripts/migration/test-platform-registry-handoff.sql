BEGIN;
DO $$ DECLARE u uuid; org uuid; h text; k text; result jsonb; BEGIN
 SELECT im.target_user_id,m.organization_id INTO u,org FROM tj.source_user_identity_map im
 JOIN tj.organization_members m ON m.user_id=im.source_user_id AND m.status='active'
 JOIN tj.organizations o ON o.id=m.organization_id AND o.deleted_at IS NULL
 WHERE im.activation_status='activated' AND tj_private.handoff_source_user(im.target_user_id) IS NOT NULL LIMIT 1;
 IF u IS NULL THEN RAISE EXCEPTION 'No activated handoff fixture'; END IF;
 FOR k IN SELECT unnest(ARRAY['intelligence-group','iq-field','field-report-analytics','applianceiq-platform']) LOOP
 h:=md5(gen_random_uuid()::text)||md5(gen_random_uuid()::text);
 IF NOT tj_private.issue_platform_handoff(u,h,k,jsonb_build_object('organization_id',org))
 THEN RAISE EXCEPTION 'Registry key % rejected',k; END IF;
 IF tj_private.consume_platform_handoff(h,'incorrect-module') IS NOT NULL
 THEN RAISE EXCEPTION 'Wrong module accepted'; END IF;
 result:=tj_private.consume_platform_handoff(h,k);
 IF result->>'user_id' IS DISTINCT FROM u::text THEN RAISE EXCEPTION 'Registry redemption failed'; END IF;
 IF tj_private.consume_platform_handoff(h,k) IS NOT NULL THEN RAISE EXCEPTION 'Replay accepted'; END IF;
 END LOOP;
 h:=md5(gen_random_uuid()::text)||md5(gen_random_uuid()::text);
 IF tj_private.issue_platform_handoff(u,h,'unknown-module',jsonb_build_object('organization_id',org)) THEN RAISE EXCEPTION 'Unknown key accepted'; END IF;
END $$;
ROLLBACK;
SELECT 'Registry key handoff checks passed; all writes rolled back' AS result;
