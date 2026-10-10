BEGIN;SET LOCAL statement_timeout='30s';
DO $$DECLARE u uuid;s uuid;o uuid;code text;BEGIN
 SELECT im.target_user_id,im.source_user_id,m.organization_id INTO u,s,o FROM tj.source_user_identity_map im JOIN tj.platform_admins pa ON pa.user_id=im.source_user_id JOIN tj.organization_members m ON m.user_id=im.source_user_id JOIN tj.organizations org ON org.id=m.organization_id WHERE im.activation_status='activated' AND pa.role='super_admin' AND org.status='active' AND org.deleted_at IS NULL LIMIT 1;
 IF u IS NULL THEN RAISE EXCEPTION 'Admin fixture missing';END IF;
 PERFORM set_config('request.jwt.claim.sub',u::text,true);PERFORM set_config('test.native',u::text,true);PERFORM set_config('test.source',s::text,true);PERFORM set_config('test.org',o::text,true);
 INSERT INTO tj.org_invites(organization_id,invited_email,invited_by,invite_code) VALUES(o,'rollback-invite@example.invalid',s,gen_random_uuid()::text) RETURNING invite_code INTO code;PERFORM set_config('test.code',code,true);
 PERFORM set_config('test.email','rollback-admin-'||gen_random_uuid()::text||'@example.invalid',true);
END $$;
SET LOCAL ROLE authenticated;
DO $$DECLARE r jsonb;BEGIN
 r:=public.tj_invite_delivery_context(current_setting('test.code'),false);IF r->>'invited_email'<>'rollback-invite@example.invalid' THEN RAISE EXCEPTION 'Recipient mismatch';END IF;
 r:=public.tj_invite_delivery_context(current_setting('test.code'),true);IF NOT (r->>'reserved')::boolean THEN RAISE EXCEPTION 'Reservation failed';END IF;
 r:=public.tj_invite_delivery_context(current_setting('test.code'),true);IF (r->>'reserved')::boolean THEN RAISE EXCEPTION 'Duplicate send accepted';END IF;
 r:=public.tj_prepare_admin_provision(current_setting('test.email'),'Rollback admin fixture');PERFORM set_config('test.intent',r->>'intent_id',true);
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 BEGIN PERFORM public.tj_invite_delivery_context(current_setting('test.code'),false);RAISE EXCEPTION 'Unmapped invite access';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN PERFORM public.tj_prepare_admin_provision('outsider@example.invalid','');RAISE EXCEPTION 'Unmapped admin access';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END $$;
RESET ROLE;
DO $$DECLARE new_id uuid:=gen_random_uuid();BEGIN
 INSERT INTO auth.users(id,email,aud,role,email_confirmed_at,created_at,updated_at,is_anonymous) VALUES(new_id,current_setting('test.email'),'authenticated','authenticated',now(),now(),now(),false);PERFORM set_config('test.target',new_id::text,true);
END $$;
SET LOCAL ROLE service_role;
DO $$DECLARE r jsonb;old_sub text:=current_setting('request.jwt.claim.sub',true);BEGIN
 BEGIN PERFORM public.aiq_finish_admin_provision(current_setting('test.intent')::uuid,gen_random_uuid());RAISE EXCEPTION 'Wrong target accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 r:=public.aiq_finish_admin_provision(current_setting('test.intent')::uuid,current_setting('test.target')::uuid);IF NOT (r->>'ok')::boolean THEN RAISE EXCEPTION 'Provision completion failed';END IF;
 r:=public.aiq_finish_admin_provision(current_setting('test.intent')::uuid,current_setting('test.target')::uuid);IF NOT (r->>'already_completed')::boolean THEN RAISE EXCEPTION 'Completion not idempotent';END IF;
 IF current_setting('request.jwt.claim.sub',true) IS DISTINCT FROM old_sub THEN RAISE EXCEPTION 'Claims leaked';END IF;
END $$;
RESET ROLE;
DO $$BEGIN
 IF NOT EXISTS(SELECT 1 FROM tj.platform_admins WHERE user_id=current_setting('test.target')::uuid AND role='super_admin') THEN RAISE EXCEPTION 'Admin grant missing';END IF;
 PERFORM set_config('request.jwt.claim.sub',current_setting('test.target'),true);IF tj_private.current_source_user_id() IS DISTINCT FROM current_setting('test.target')::uuid THEN RAISE EXCEPTION 'Provisioned identity unusable';END IF;
 UPDATE tj.org_invites SET expires_at=now()-interval '1 second' WHERE invite_code=current_setting('test.code');
 PERFORM set_config('request.jwt.claim.sub',current_setting('test.native'),true);
 BEGIN PERFORM public.tj_invite_delivery_context(current_setting('test.code'),false);RAISE EXCEPTION 'Expired invitation accepted';EXCEPTION WHEN no_data_found THEN NULL;END;
 IF has_function_privilege('anon','public.tj_invite_delivery_context(text,boolean)','EXECUTE') OR has_function_privilege('authenticated','public.aiq_finish_admin_provision(uuid,uuid)','EXECUTE') THEN RAISE EXCEPTION 'Grant leak';END IF;
END $$;
DO $$BEGIN
 UPDATE tj.platform_admins SET role='platform_admin' WHERE user_id=current_setting('test.source')::uuid;
END $$;
SET LOCAL ROLE authenticated;
DO $$BEGIN
 BEGIN PERFORM public.tj_prepare_admin_provision('denied@example.invalid','');RAISE EXCEPTION 'Non-super administrator escalated';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END $$;
RESET ROLE;
DO $$DECLARE r jsonb;BEGIN
 UPDATE tj.platform_admins SET role='super_admin' WHERE user_id=current_setting('test.source')::uuid;
 r:=public.tj_prepare_admin_provision(current_setting('test.email'),'Existing fixture');
 IF r->>'existing_user_id'<>current_setting('test.target') THEN RAISE EXCEPTION 'Existing mapped account not resolved';END IF;
 PERFORM set_config('test.existing_intent',r->>'intent_id',true);
END $$;
SET LOCAL ROLE service_role;
DO $$BEGIN
 PERFORM public.aiq_finish_admin_provision(current_setting('test.existing_intent')::uuid,current_setting('test.target')::uuid);
END $$;
RESET ROLE;
ROLLBACK;
