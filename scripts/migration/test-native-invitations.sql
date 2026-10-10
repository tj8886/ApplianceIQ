BEGIN;SET LOCAL statement_timeout='30s';
DO $$DECLARE owner_id uuid:=gen_random_uuid();target uuid:=gen_random_uuid();wrong uuid:=gen_random_uuid();unconfirmed uuid:=gen_random_uuid();o uuid;other uuid;position uuid;foreign_position uuid;location uuid;foreign_location uuid;BEGIN
 INSERT INTO auth.users(id,email,aud,role,email_confirmed_at,created_at,updated_at,is_anonymous) VALUES(owner_id,'owner-'||owner_id||'@example.invalid','authenticated','authenticated',now(),now(),now(),false),(target,'target-'||target||'@example.invalid','authenticated','authenticated',now(),now(),now(),false),(wrong,'wrong-'||wrong||'@example.invalid','authenticated','authenticated',now(),now(),now(),false),(unconfirmed,'pending-'||unconfirmed||'@example.invalid','authenticated','authenticated',NULL,now(),now(),false);
 INSERT INTO tj.source_auth_users(id,email,is_anonymous,email_confirmed_at) VALUES(owner_id,'owner-'||owner_id||'@example.invalid',false,now());
 INSERT INTO tj.source_user_identity_map(source_user_id,target_user_id,mapping_status,identity_verified,verified_by,approved_at,approved_by,activation_status,activated_at) VALUES(owner_id,owner_id,'approved_create',true,'rollback-fixture',now(),'rollback-fixture','activated',now());
 INSERT INTO tj.organizations(name,slug) VALUES('Rollback invite organization','rollback-'||gen_random_uuid()) RETURNING id INTO o;
 INSERT INTO tj.organizations(name,slug) VALUES('Rollback foreign organization','rollback-'||gen_random_uuid()) RETURNING id INTO other;
 INSERT INTO tj.organization_members(organization_id,user_id,role) VALUES(o,owner_id,'owner');
 INSERT INTO tj.org_roles(organization_id,role_name,role_level) VALUES(o,'Rollback position',3) RETURNING id INTO position;
 INSERT INTO tj.org_roles(organization_id,role_name,role_level) VALUES(other,'Rollback foreign position',3) RETURNING id INTO foreign_position;
 INSERT INTO tj.org_locations(organization_id,location_type,name) VALUES(o,'store','Rollback store') RETURNING id INTO location;
 INSERT INTO tj.org_locations(organization_id,location_type,name) VALUES(other,'store','Rollback foreign store') RETURNING id INTO foreign_location;
 PERFORM set_config('test.owner',owner_id::text,true);PERFORM set_config('test.target',target::text,true);PERFORM set_config('test.wrong',wrong::text,true);PERFORM set_config('test.unconfirmed',unconfirmed::text,true);PERFORM set_config('test.org',o::text,true);PERFORM set_config('test.other',other::text,true);PERFORM set_config('test.position',position::text,true);PERFORM set_config('test.foreign_position',foreign_position::text,true);PERFORM set_config('test.location',location::text,true);PERFORM set_config('test.foreign_location',foreign_location::text,true);PERFORM set_config('test.email','target-'||target||'@example.invalid',true);PERFORM set_config('request.jwt.claim.sub',owner_id::text,true);
END $$;
SET LOCAL ROLE authenticated;
DO $$DECLARE r jsonb;BEGIN
 BEGIN PERFORM public.tj_runtime_create_org_invite(current_setting('test.other')::uuid,'outside@example.invalid');RAISE EXCEPTION 'Foreign organization accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN PERFORM public.tj_runtime_create_org_invite(current_setting('test.org')::uuid,'outside@example.invalid','member',current_setting('test.foreign_position')::uuid);RAISE EXCEPTION 'Foreign position accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN PERFORM public.tj_runtime_create_org_invite(current_setting('test.org')::uuid,'outside@example.invalid','member',NULL,current_setting('test.foreign_location')::uuid);RAISE EXCEPTION 'Foreign location accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 r:=public.tj_runtime_create_org_invite(current_setting('test.org')::uuid,current_setting('test.email'),'member',current_setting('test.position')::uuid,current_setting('test.location')::uuid,current_setting('test.owner')::uuid);
 PERFORM set_config('test.code',r->>'invite_code',true);PERFORM set_config('test.invite',r->>'id',true);
END $$;
SET LOCAL ROLE anon;
DO $$DECLARE r jsonb;BEGIN
 r:=public.tj_runtime_get_invite_preview(current_setting('test.code'));IF NOT (r->>'ok')::boolean OR r->>'invited_email'<>current_setting('test.email') THEN RAISE EXCEPTION 'Capability preview failed';END IF;
 r:=public.tj_runtime_get_invite_preview('bad');IF (r->>'ok')::boolean THEN RAISE EXCEPTION 'Invalid capability preview';END IF;
 IF has_schema_privilege('anon','tj_private','USAGE') OR has_function_privilege('anon','public.tj_runtime_accept_org_invite(text)','EXECUTE') THEN RAISE EXCEPTION 'Anonymous grant leak';END IF;
END $$;
SET LOCAL ROLE authenticated;
DO $$DECLARE r jsonb;BEGIN
 PERFORM set_config('request.jwt.claim.sub',current_setting('test.unconfirmed'),true);r:=public.tj_runtime_accept_org_invite(current_setting('test.code'));IF r->>'error'<>'email_confirmation_required' THEN RAISE EXCEPTION 'Unconfirmed identity accepted';END IF;
 PERFORM set_config('request.jwt.claim.sub',current_setting('test.wrong'),true);r:=public.tj_runtime_accept_org_invite(current_setting('test.code'));IF r->>'error'<>'email_mismatch' THEN RAISE EXCEPTION 'Wrong recipient accepted';END IF;
 PERFORM set_config('request.jwt.claim.sub',current_setting('test.target'),true);r:=public.tj_runtime_accept_org_invite(current_setting('test.code'));IF NOT (r->>'ok')::boolean OR r->>'role'<>'member' THEN RAISE EXCEPTION 'Native invitation acceptance failed';END IF;
 r:=public.tj_runtime_accept_org_invite(current_setting('test.code'));IF r->>'error'<>'invalid_or_used' THEN RAISE EXCEPTION 'Invite replay accepted';END IF;
END $$;
RESET ROLE;
DO $$BEGIN
 IF NOT EXISTS(SELECT 1 FROM tj.organization_members m JOIN tj.organization_members manager ON manager.id=m.manager_id WHERE m.organization_id=current_setting('test.org')::uuid AND m.user_id=current_setting('test.target')::uuid AND manager.user_id=current_setting('test.owner')::uuid AND manager.organization_id=m.organization_id) THEN RAISE EXCEPTION 'Manager membership conversion failed';END IF;
 IF NOT EXISTS(SELECT 1 FROM tj.org_location_members WHERE user_id=current_setting('test.target')::uuid AND location_id=current_setting('test.location')::uuid AND organization_id=current_setting('test.org')::uuid) THEN RAISE EXCEPTION 'Store assignment failed';END IF;
 IF tj_private.current_source_user_id() IS DISTINCT FROM current_setting('test.target')::uuid THEN RAISE EXCEPTION 'New identity not usable';END IF;
 UPDATE tj.organization_members SET role='owner' WHERE user_id=current_setting('test.target')::uuid AND organization_id=current_setting('test.org')::uuid;
 PERFORM set_config('request.jwt.claim.sub',current_setting('test.owner'),true);
END $$;
SET LOCAL ROLE authenticated;
DO $$DECLARE r jsonb;BEGIN
 r:=public.tj_runtime_create_org_invite(current_setting('test.org')::uuid,current_setting('test.email'),'member');PERFORM set_config('test.second_code',r->>'invite_code',true);
 PERFORM set_config('request.jwt.claim.sub',current_setting('test.target'),true);r:=public.tj_runtime_accept_org_invite(current_setting('test.second_code'));IF r->>'role'<>'owner' THEN RAISE EXCEPTION 'Existing owner was downgraded';END IF;
 PERFORM set_config('request.jwt.claim.sub',current_setting('test.owner'),true);r:=public.tj_runtime_create_org_invite(current_setting('test.org')::uuid,current_setting('test.email'),'member');PERFORM set_config('test.revoke_code',r->>'invite_code',true);PERFORM public.tj_runtime_revoke_org_invite((r->>'id')::uuid);
END $$;
SET LOCAL ROLE anon;
DO $$DECLARE r jsonb;BEGIN
 r:=public.tj_runtime_get_invite_preview(current_setting('test.revoke_code'));IF (r->>'ok')::boolean THEN RAISE EXCEPTION 'Revoked invite previewed';END IF;
END $$;
RESET ROLE;
DO $$BEGIN
 UPDATE tj.organization_members SET role='admin' WHERE user_id=current_setting('test.owner')::uuid AND organization_id=current_setting('test.org')::uuid;
 PERFORM set_config('request.jwt.claim.sub',current_setting('test.owner'),true);
END $$;
SET LOCAL ROLE authenticated;
DO $$DECLARE r jsonb;BEGIN
 BEGIN PERFORM public.tj_runtime_create_org_invite(current_setting('test.org')::uuid,'owner-upgrade@example.invalid','owner');RAISE EXCEPTION 'Admin escalated owner';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 r:=public.tj_runtime_create_org_invite(current_setting('test.org')::uuid,current_setting('test.email'),'member');PERFORM set_config('test.suspended_code',r->>'invite_code',true);
END $$;
RESET ROLE;
DO $$BEGIN UPDATE tj.organization_members SET status='suspended' WHERE user_id=current_setting('test.target')::uuid AND organization_id=current_setting('test.org')::uuid;END $$;
SET LOCAL ROLE authenticated;
DO $$DECLARE r jsonb;BEGIN
 PERFORM set_config('request.jwt.claim.sub',current_setting('test.target'),true);r:=public.tj_runtime_accept_org_invite(current_setting('test.suspended_code'));IF r->>'error'<>'membership_review_required' THEN RAISE EXCEPTION 'Suspended member reactivated';END IF;
END $$;
RESET ROLE;
DO $$BEGIN PERFORM set_config('request.jwt.claim.sub',current_setting('test.owner'),true);END $$;
SET LOCAL ROLE authenticated;
DO $$DECLARE r jsonb;BEGIN
 r:=public.tj_runtime_create_org_invite(current_setting('test.org')::uuid,current_setting('test.email'),'member');PERFORM set_config('test.expired_code',r->>'invite_code',true);
 r:=public.tj_runtime_create_org_invite(current_setting('test.org')::uuid,'wrong-'||current_setting('test.wrong')||'@example.invalid','member');PERFORM set_config('test.collision_code',r->>'invite_code',true);
END $$;
RESET ROLE;
DO $$BEGIN
 UPDATE tj.org_invites SET expires_at=now()-interval '1 second' WHERE invite_code=current_setting('test.expired_code');
 INSERT INTO tj.source_auth_users(id,email,is_anonymous) VALUES(gen_random_uuid(),'wrong-'||current_setting('test.wrong')||'@example.invalid',false);
END $$;
SET LOCAL ROLE authenticated;
DO $$DECLARE r jsonb;BEGIN
 PERFORM set_config('request.jwt.claim.sub',current_setting('test.target'),true);r:=public.tj_runtime_accept_org_invite(current_setting('test.expired_code'));IF r->>'error'<>'expired' THEN RAISE EXCEPTION 'Expired invite accepted';END IF;
 PERFORM set_config('request.jwt.claim.sub',current_setting('test.wrong'),true);r:=public.tj_runtime_accept_org_invite(current_setting('test.collision_code'));IF r->>'error'<>'identity_review_required' THEN RAISE EXCEPTION 'Historical identity auto-linked';END IF;
END $$;
RESET ROLE;
DO $$BEGIN UPDATE tj.organization_members SET status='removed' WHERE user_id=current_setting('test.owner')::uuid AND organization_id=current_setting('test.org')::uuid;END $$;
SET LOCAL ROLE authenticated;
DO $$DECLARE r jsonb;BEGIN
 PERFORM set_config('request.jwt.claim.sub',current_setting('test.target'),true);r:=public.tj_runtime_accept_org_invite(current_setting('test.suspended_code'));IF r->>'error'<>'invite_no_longer_authorized' THEN RAISE EXCEPTION 'Revoked inviter authority honored';END IF;
END $$;
SET LOCAL ROLE anon;
DO $$DECLARE r jsonb;BEGIN
 r:=public.tj_runtime_get_invite_preview(current_setting('test.collision_code'));IF (r->>'ok')::boolean THEN RAISE EXCEPTION 'Revoked inviter preview allowed';END IF;
END $$;
ROLLBACK;
