-- Live access fixture: synthetic parents, all writes rolled back.
BEGIN; SET LOCAL statement_timeout='45s';
DO $$ DECLARE u uuid; src uuid; org uuid; foreign_org uuid; retailer uuid; c uuid:=gen_random_uuid(); l uuid:=gen_random_uuid(); s uuid:=gen_random_uuid(); v uuid:=gen_random_uuid(); h uuid:=gen_random_uuid(); BEGIN
 SELECT im.target_user_id,im.source_user_id,m.organization_id INTO u,src,org FROM tj.source_user_identity_map im JOIN tj.organization_members m ON m.user_id=im.source_user_id JOIN tj.organizations o ON o.id=m.organization_id WHERE im.activation_status='activated' AND m.status='active' AND m.role IN('owner','admin') AND o.status='active' AND o.deleted_at IS NULL AND NOT EXISTS(SELECT 1 FROM tj.platform_admins a WHERE a.user_id=im.source_user_id) LIMIT 1;
 SELECT id INTO foreign_org FROM tj.organizations o WHERE NOT EXISTS(SELECT 1 FROM tj.organization_members m WHERE m.organization_id=o.id AND m.user_id=src AND m.status='active') LIMIT 1;
 SELECT id INTO retailer FROM tj.field_retailers LIMIT 1;
 IF u IS NULL OR retailer IS NULL OR foreign_org IS NULL THEN RAISE EXCEPTION 'Fixture unavailable'; END IF;
 PERFORM set_config('request.jwt.claim.sub',u::text,true); PERFORM set_config('test.user',u::text,true); PERFORM set_config('test.source',src::text,true); PERFORM set_config('test.org',org::text,true); PERFORM set_config('test.client',c::text,true); PERFORM set_config('test.store',s::text,true); PERFORM set_config('test.visit',v::text,true); PERFORM set_config('test.hidden',h::text,true);
 INSERT INTO tj.field_clients(id,organization_id,client_name,status) VALUES(c,org,'Rollback fixture','active');
 INSERT INTO tj.org_locations(id,organization_id,location_type,name,is_active) VALUES(l,org,'store','Rollback fixture',true);
 INSERT INTO tj.field_stores(id,retailer_id,org_location_id,store_name,status) VALUES(s,retailer,l,'Rollback fixture','active');
 INSERT INTO tj.field_visits(id,client_id,store_id,rep_user_id,status) VALUES(v,c,s,src,'scheduled');
 INSERT INTO tj.field_media(visit_id,media_type,storage_path) VALUES(v,'photo','rollback/fixture');
 INSERT INTO tj.field_action_comments(visit_id,author_user_id,visibility,comment_text) VALUES(v,src,'all','Rollback fixture');
 INSERT INTO tj.field_clients(id,organization_id,client_name,status) VALUES(h,foreign_org,'Hidden fixture','active');
 INSERT INTO tj.field_visits(id,client_id,store_id,rep_user_id,status) VALUES(h,h,s,src,'scheduled');
 INSERT INTO tj.field_media(visit_id,media_type,storage_path) VALUES(h,'photo','rollback/hidden');
 INSERT INTO tj.field_action_comments(visit_id,author_user_id,visibility,comment_text) VALUES(h,src,'all','Hidden fixture');
END $$;
SET LOCAL ROLE authenticated;
DO $$ DECLARE t text; has_rows boolean; BEGIN
 IF NOT EXISTS(SELECT 1 FROM tj.field_visits WHERE id=current_setting('test.visit')::uuid) OR NOT EXISTS(SELECT 1 FROM tj.field_stores WHERE id=current_setting('test.store')::uuid) OR NOT EXISTS(SELECT 1 FROM tj.field_media WHERE visit_id=current_setting('test.visit')::uuid) OR NOT EXISTS(SELECT 1 FROM tj.field_action_comments WHERE visit_id=current_setting('test.visit')::uuid) THEN RAISE EXCEPTION 'Parent read fixture missing'; END IF;
 IF EXISTS(SELECT 1 FROM tj.field_visits WHERE id=current_setting('test.hidden')::uuid) OR EXISTS(SELECT 1 FROM tj.field_media WHERE visit_id=current_setting('test.hidden')::uuid) OR EXISTS(SELECT 1 FROM tj.field_action_comments WHERE visit_id=current_setting('test.hidden')::uuid) THEN RAISE EXCEPTION 'Foreign parent read'; END IF;
 FOREACH t IN ARRAY ARRAY['field_assignments','field_visits','field_stores','field_checklist_responses','field_competitive_intel','field_media','field_action_status_history','field_action_comments','brand_training_cards','iq_notifications','mfr_vendors'] LOOP EXECUTE format('SELECT EXISTS(SELECT 1 FROM tj.%I)',t) INTO has_rows; END LOOP;
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 FOREACH t IN ARRAY ARRAY['field_assignments','field_visits','field_stores','field_checklist_responses','field_competitive_intel','field_media','field_action_status_history','field_action_comments','brand_training_cards','iq_notifications','mfr_vendors'] LOOP
 EXECUTE format('SELECT EXISTS(SELECT 1 FROM tj.%I)',t) INTO has_rows;
 IF has_rows THEN RAISE EXCEPTION 'Unmapped read: %',t; END IF;
 END LOOP;
END $$;
RESET ROLE;
-- Paused client invalidates parent and child visibility.
UPDATE tj.field_clients SET status='paused' WHERE id=current_setting('test.client')::uuid;
SELECT set_config('request.jwt.claim.sub',current_setting('test.user'),true) IS NOT NULL AS identity_reset;
SET LOCAL ROLE authenticated;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM tj.field_visits WHERE id=current_setting('test.visit')::uuid) OR EXISTS(SELECT 1 FROM tj.field_media WHERE visit_id=current_setting('test.visit')::uuid) THEN RAISE EXCEPTION 'Paused client readable'; END IF; END $$;
RESET ROLE;
DO $$ DECLARE t text; BEGIN FOREACH t IN ARRAY ARRAY['field_assignments','field_visits','field_stores','field_checklist_responses','field_competitive_intel','field_media','field_action_status_history','field_action_comments','brand_training_cards','iq_notifications','mfr_vendors'] LOOP IF has_table_privilege('anon',format('tj.%I',t),'SELECT') OR has_table_privilege('authenticated',format('tj.%I',t),'INSERT,UPDATE,DELETE') THEN RAISE EXCEPTION 'Unexpected write/anonymous grant: %',t; END IF; END LOOP; RAISE NOTICE '11 read paths, parent inheritance, foreign parent, paused client and unmapped denial passed'; END $$;
ROLLBACK;
