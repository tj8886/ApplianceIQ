BEGIN; SET LOCAL statement_timeout='60s';
DO $$ DECLARE u uuid; src uuid; org uuid; other_src uuid; foreign_org uuid; p uuid:=gen_random_uuid(); p2 uuid:=gen_random_uuid(); hidden uuid:=gen_random_uuid(); c uuid:=gen_random_uuid(); foreign_c uuid:=gen_random_uuid(); BEGIN
 SELECT im.target_user_id,im.source_user_id,m.organization_id INTO u,src,org FROM tj.source_user_identity_map im JOIN tj.organization_members m ON m.user_id=im.source_user_id JOIN tj.organizations o ON o.id=m.organization_id WHERE im.activation_status='activated' AND m.status='active' AND m.role IN('owner','admin') AND o.status='active' AND o.deleted_at IS NULL AND NOT EXISTS(SELECT 1 FROM tj.product_iq_platform_roles r WHERE r.user_id=im.source_user_id AND r.status='active') LIMIT 1;
 SELECT id INTO other_src FROM tj.source_auth_users WHERE id<>src LIMIT 1;
 SELECT id INTO foreign_org FROM tj.organizations o WHERE o.status='active' AND o.deleted_at IS NULL AND NOT EXISTS(SELECT 1 FROM tj.organization_members m WHERE m.organization_id=o.id AND m.user_id=src AND m.status='active') LIMIT 1;
 IF u IS NULL OR other_src IS NULL OR foreign_org IS NULL THEN RAISE EXCEPTION 'Fixture unavailable'; END IF;
 PERFORM set_config('request.jwt.claim.sub',u::text,true); PERFORM set_config('test.product',p::text,true);PERFORM set_config('test.product2',p2::text,true);PERFORM set_config('test.hidden',hidden::text,true);PERFORM set_config('test.org',org::text,true);PERFORM set_config('test.foreign_org',foreign_org::text,true);PERFORM set_config('test.conversation',c::text,true);PERFORM set_config('test.foreign_conversation',foreign_c::text,true);PERFORM set_config('test.source',src::text,true);
 INSERT INTO tj.aiq_products(id,organization_id,manufacturer_name,brand_name,model,status) VALUES(p,org,'Rollback','Rollback',p::text,'draft'),(p2,org,'Rollback','Rollback',p2::text,'draft'),(hidden,foreign_org,'Rollback','Rollback',hidden::text,'draft');
 INSERT INTO tj.ai_conversations(id,user_id,organization_id,title) VALUES(c,src,org,'Rollback'),(foreign_c,other_src,org,'Rollback other owner');
 INSERT INTO tj.ai_conversation_memory(conversation_id,user_id) VALUES(c,src),(foreign_c,other_src);
 INSERT INTO tj.ai_product_comparisons(organization_id,user_id,title,selected_product_ids) VALUES(org,other_src,'Rollback other owner',ARRAY[p,p2]);
END $$;
SET LOCAL ROLE authenticated;
DO $$ DECLARE comparison uuid; n integer; BEGIN
 IF EXISTS(SELECT 1 FROM tj.ai_product_comparisons WHERE user_id<>current_setting('test.source')::uuid) THEN RAISE EXCEPTION 'Foreign comparison read'; END IF;
 IF NOT EXISTS(SELECT 1 FROM tj.ai_conversation_memory WHERE conversation_id=current_setting('test.conversation')::uuid) OR EXISTS(SELECT 1 FROM tj.ai_conversation_memory WHERE conversation_id=current_setting('test.foreign_conversation')::uuid) THEN RAISE EXCEPTION 'Memory owner guard'; END IF;
 UPDATE tj.ai_conversation_memory SET recommendations='[{"model":"Rollback"}]',outstanding_questions='["width"]' WHERE conversation_id=current_setting('test.conversation')::uuid; GET DIAGNOSTICS n=ROW_COUNT; IF n<>1 THEN RAISE EXCEPTION 'Own memory update'; END IF;
 UPDATE tj.ai_conversation_memory SET recommendations='[]' WHERE conversation_id=current_setting('test.foreign_conversation')::uuid; GET DIAGNOSTICS n=ROW_COUNT; IF n<>0 THEN RAISE EXCEPTION 'Foreign memory writable'; END IF;
 BEGIN UPDATE tj.ai_conversation_memory SET profile='{}' WHERE conversation_id=current_setting('test.conversation')::uuid; RAISE EXCEPTION 'Profile editing exposed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 INSERT INTO tj.ai_product_comparisons(organization_id,conversation_id,title,selected_product_ids,winner_product_id,comparison_snapshot)
 VALUES(current_setting('test.org')::uuid,current_setting('test.conversation')::uuid,'Rollback',ARRAY[current_setting('test.product')::uuid,current_setting('test.product2')::uuid],current_setting('test.product')::uuid,'{"advisory":true}') RETURNING id INTO comparison;
 IF NOT EXISTS(SELECT 1 FROM tj.ai_product_comparisons WHERE id=comparison AND user_id=current_setting('test.source')::uuid) THEN RAISE EXCEPTION 'Comparison source identity'; END IF;
 UPDATE tj.ai_product_comparisons SET title='Updated' WHERE id=comparison;GET DIAGNOSTICS n=ROW_COUNT;IF n<>1 THEN RAISE EXCEPTION 'Own comparison update'; END IF;
 BEGIN UPDATE tj.ai_product_comparisons SET organization_id=current_setting('test.foreign_org')::uuid WHERE id=comparison;RAISE EXCEPTION 'Tenant movement allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN INSERT INTO tj.ai_product_comparisons(organization_id,conversation_id,title,selected_product_ids) VALUES(current_setting('test.org')::uuid,current_setting('test.foreign_conversation')::uuid,'Bad',ARRAY[current_setting('test.product')::uuid,current_setting('test.product2')::uuid]);RAISE EXCEPTION 'Foreign conversation allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN UPDATE tj.ai_product_comparisons SET selected_product_ids=ARRAY[current_setting('test.product')::uuid,current_setting('test.hidden')::uuid] WHERE id=comparison;RAISE EXCEPTION 'Hidden product accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN UPDATE tj.ai_product_comparisons SET winner_product_id=current_setting('test.hidden')::uuid WHERE id=comparison;RAISE EXCEPTION 'Invalid winner accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN DELETE FROM tj.ai_product_comparisons WHERE id=comparison;RAISE EXCEPTION 'Hard delete exposed';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 IF EXISTS(SELECT 1 FROM tj.ai_conversation_memory) OR EXISTS(SELECT 1 FROM tj.ai_product_comparisons) THEN RAISE EXCEPTION 'Unmapped read'; END IF;
END $$;
ROLLBACK;
