BEGIN;SET LOCAL statement_timeout='30s';
DO $$DECLARE u uuid;src uuid;org uuid;b uuid;BEGIN
 SELECT im.target_user_id,im.source_user_id,m.organization_id INTO u,src,org FROM tj.source_user_identity_map im JOIN tj.organization_members m ON m.user_id=im.source_user_id JOIN tj.organizations o ON o.id=m.organization_id JOIN auth.users au ON au.id=im.target_user_id WHERE im.activation_status='activated' AND m.status='active' AND m.role IN ('owner','admin','manager') AND o.status='active' AND o.deleted_at IS NULL AND au.email_confirmed_at IS NOT NULL LIMIT 1;
 IF u IS NULL THEN RAISE EXCEPTION 'Fixture unavailable';END IF;
 INSERT INTO tj.ai_manager_briefs(organization_id,headline,executive_summary) VALUES(org,'Rollback delivery fixture','Synthetic brief; never emailed') RETURNING id INTO b;
 PERFORM set_config('request.jwt.claim.sub',u::text,true);PERFORM set_config('test.native',u::text,true);PERFORM set_config('test.org',org::text,true);PERFORM set_config('test.brief',b::text,true);
END $$;
SET LOCAL ROLE authenticated;
DO $$DECLARE c jsonb;BEGIN
 c:=public.tj_brief_delivery_context(current_setting('test.org')::uuid,current_setting('test.brief')::uuid,'[]');IF jsonb_array_length(c->'recipients')<1 THEN RAISE EXCEPTION 'Eligible managers missing';END IF;
 PERFORM set_config('test.recipients',(c->'recipients')::text,true);
 BEGIN PERFORM public.tj_brief_delivery_context(current_setting('test.org')::uuid,current_setting('test.brief')::uuid,'["outsider@example.invalid"]');RAISE EXCEPTION 'External recipient accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN PERFORM public.tj_brief_delivery_context(gen_random_uuid(),current_setting('test.brief')::uuid,'[]');RAISE EXCEPTION 'Foreign org accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN PERFORM public.tj_brief_delivery_context(current_setting('test.org')::uuid,gen_random_uuid(),'[]');RAISE EXCEPTION 'Foreign brief accepted';EXCEPTION WHEN no_data_found THEN NULL;END;
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 BEGIN PERFORM public.tj_brief_delivery_context(current_setting('test.org')::uuid,current_setting('test.brief')::uuid,'[]');RAISE EXCEPTION 'Unmapped user accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END $$;
RESET ROLE;SET LOCAL ROLE service_role;
DO $$DECLARE r jsonb;prior_sub text:=current_setting('request.jwt.claim.sub',true);BEGIN
 r:=public.aiq_finish_brief_delivery(current_setting('test.native')::uuid,current_setting('test.org')::uuid,current_setting('test.brief')::uuid,current_setting('test.recipients')::jsonb,1,jsonb_array_length(current_setting('test.recipients')::jsonb)-1);
 IF NOT (r->>'ok')::boolean THEN RAISE EXCEPTION 'Accepted status failed';END IF;
 IF current_setting('request.jwt.claim.sub',true) IS DISTINCT FROM prior_sub THEN RAISE EXCEPTION 'Claims not restored';END IF;
 BEGIN PERFORM public.aiq_finish_brief_delivery(gen_random_uuid(),current_setting('test.org')::uuid,current_setting('test.brief')::uuid,current_setting('test.recipients')::jsonb,1,0);RAISE EXCEPTION 'Unmapped completion accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END $$;
RESET ROLE;
DO $$BEGIN
 IF NOT EXISTS(SELECT 1 FROM tj.ai_manager_briefs WHERE id=current_setting('test.brief')::uuid AND delivery_channels ? 'email' AND delivery_status='delivered') THEN RAISE EXCEPTION 'Status not recorded';END IF;
 IF has_function_privilege('authenticated','public.aiq_finish_brief_delivery(uuid,uuid,uuid,jsonb,int,int)','EXECUTE') OR has_function_privilege('anon','public.tj_brief_delivery_context(uuid,uuid,jsonb)','EXECUTE') THEN RAISE EXCEPTION 'Privileged grant leak';END IF;
END $$;
ROLLBACK;
