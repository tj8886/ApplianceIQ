BEGIN;
SET LOCAL statement_timeout='20s';
DO $$
DECLARE admin_actor uuid;admin_native uuid;recipient_actor uuid;recipient_native uuid;recipient_email text;
 vendor uuid;result jsonb;code text;invite uuid;original_expiry timestamptz;member_count integer;
BEGIN
 SELECT im.source_user_id,im.target_user_id INTO admin_actor,admin_native
 FROM tj.source_user_identity_map im JOIN auth.users u ON u.id=im.target_user_id
 JOIN tj.organization_members m ON m.user_id=im.source_user_id JOIN tj.organizations o ON o.id=m.organization_id
 WHERE tj_private.microsoft_actor(u.id)=im.source_user_id AND u.email_confirmed_at IS NOT NULL
 AND m.status='active' AND m.role IN('owner','admin') AND o.status='active' AND o.deleted_at IS NULL LIMIT 1;
 SELECT im.source_user_id,im.target_user_id,lower(btrim(u.email)) INTO recipient_actor,recipient_native,recipient_email
 FROM tj.source_user_identity_map im JOIN auth.users u ON u.id=im.target_user_id
 WHERE tj_private.microsoft_actor(u.id)=im.source_user_id AND u.email_confirmed_at IS NOT NULL AND im.source_user_id<>admin_actor LIMIT 1;
 IF admin_native IS NULL OR recipient_native IS NULL THEN RAISE EXCEPTION 'missing identity fixture';END IF;
 INSERT INTO tj.product_iq_platform_roles(user_id,role,status)
 SELECT admin_actor,'product_iq_super_admin','active' WHERE NOT EXISTS(SELECT 1 FROM tj.product_iq_platform_roles WHERE user_id=admin_actor AND organization_id IS NULL AND role='product_iq_super_admin');
 UPDATE tj.product_iq_platform_roles SET status='active',expires_at=NULL WHERE user_id=admin_actor AND organization_id IS NULL AND role='product_iq_super_admin';
 -- The recipient cannot inherit any global governance role for this fixture.
 UPDATE tj.product_iq_platform_roles SET status='revoked' WHERE user_id=recipient_actor AND organization_id IS NULL AND role IN('super_admin','product_iq_super_admin');
 INSERT INTO tj.mfr_vendors(slug,name,status) VALUES('us-rollback-'||gen_random_uuid()::text,'Rollback manufacturer brand','active') RETURNING id INTO vendor;
 PERFORM set_config('request.jwt.claim.sub',recipient_native::text,true);
 result:=public.tj_runtime_manufacturer_invites(jsonb_build_object('action','create','email',recipient_email,'vendor_id',vendor));
 IF result->>'error'<>'forbidden' THEN RAISE EXCEPTION 'non-admin create allowed';END IF;
 result:=public.tj_runtime_manufacturer_invites('{"action":"list"}');IF result->>'error'<>'forbidden' THEN RAISE EXCEPTION 'non-admin list allowed';END IF;
 PERFORM set_config('request.jwt.claim.sub',admin_native::text,true);
 result:=public.tj_runtime_manufacturer_invites(jsonb_build_object('action','create','email',recipient_email,'vendor_id',vendor));
 IF result->>'ok'<>'true' OR result->>'code' !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'create failed: %',result;END IF;
 code:=result->>'code';invite:=(result->>'id')::uuid;original_expiry:=(result->>'expires_at')::timestamptz;
 IF EXISTS(SELECT 1 FROM tj.mfr_invites WHERE id=invite AND code=code) THEN RAISE EXCEPTION 'raw code stored';END IF;
 result:=public.tj_runtime_manufacturer_invites('{"action":"list"}');
 IF result::text LIKE '%'||code||'%' OR result::text LIKE '%code_hash%' OR result::text LIKE '%created_actor%' THEN RAISE EXCEPTION 'list leaked secret or actor';END IF;
 result:=public.tj_runtime_manufacturer_invites(jsonb_build_object('action','accept','code',code));
 IF result->>'error'<>'invite_unavailable' THEN RAISE EXCEPTION 'wrong email accepted';END IF;
 PERFORM set_config('request.jwt.claim.sub',recipient_native::text,true);
 result:=public.tj_runtime_manufacturer_invites(jsonb_build_object('action','accept','code','IMPORTED-LEGACY-CODE'));
 IF result->>'error'<>'invite_unavailable' THEN RAISE EXCEPTION 'legacy code accepted';END IF;
 UPDATE tj_private.manufacturer_invite_registry SET expires_at=now()-interval '1 minute' WHERE invite_id=invite;
 UPDATE tj.mfr_invites SET expires_at=now()-interval '1 minute' WHERE id=invite;
 result:=public.tj_runtime_manufacturer_invites(jsonb_build_object('action','accept','code',code));
 IF result->>'error'<>'invite_unavailable' THEN RAISE EXCEPTION 'expired code accepted';END IF;
 UPDATE tj_private.manufacturer_invite_registry SET expires_at=original_expiry WHERE invite_id=invite;
 UPDATE tj.mfr_invites SET expires_at=original_expiry WHERE id=invite;
 -- An inviter losing current authority invalidates their pending capabilities.
 UPDATE tj.product_iq_platform_roles SET status='revoked' WHERE user_id=admin_actor AND organization_id IS NULL AND role IN('super_admin','product_iq_super_admin');
 result:=public.tj_runtime_manufacturer_invites(jsonb_build_object('action','accept','code',code));
 IF result->>'error'<>'invite_unavailable' THEN RAISE EXCEPTION 'revoked inviter accepted';END IF;
 UPDATE tj.product_iq_platform_roles SET status='active',expires_at=NULL WHERE user_id=admin_actor AND organization_id IS NULL AND role='product_iq_super_admin';
 -- Tampering with the archived-table representation cannot change the approved role.
 UPDATE tj.mfr_invites SET invite_role='vendor_owner' WHERE id=invite;
 result:=public.tj_runtime_manufacturer_invites(jsonb_build_object('action','accept','code',code));
 IF result->>'error'<>'invite_unavailable' THEN RAISE EXCEPTION 'tampered role accepted';END IF;
 UPDATE tj.mfr_invites SET invite_role='product_editor' WHERE id=invite;
 result:=public.tj_runtime_manufacturer_invites(jsonb_build_object('action','accept','code',upper(code)));
 IF result->>'ok'<>'true' THEN RAISE EXCEPTION 'accept failed: %',result;END IF;
 IF NOT EXISTS(SELECT 1 FROM tj.mfr_members WHERE user_id=recipient_actor AND vendor_id=vendor AND role='product_editor' AND status='active' AND invitation_id=invite AND approved_by=admin_actor) THEN RAISE EXCEPTION 'wrong role or actor';END IF;
 IF NOT EXISTS(SELECT 1 FROM tj.mfr_invites WHERE id=invite AND status='accepted' AND accepted_by=recipient_actor) THEN RAISE EXCEPTION 'invite not consumed';END IF;
 result:=public.tj_runtime_manufacturer_invites('{"action":"context"}');
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(result->'vendors') v WHERE v->>'id'=vendor::text) THEN RAISE EXCEPTION 'mapped context missed brand';END IF;
 result:=public.tj_runtime_manufacturer_invites(jsonb_build_object('action','accept','code',code));IF result->>'error'<>'invite_unavailable' THEN RAISE EXCEPTION 'replay allowed';END IF;
 -- Fresh invite preserves an already approved owner rather than downgrading them.
 UPDATE tj.mfr_members SET role='vendor_owner',member_role='owner' WHERE user_id=recipient_actor AND vendor_id=vendor;
 PERFORM set_config('request.jwt.claim.sub',admin_native::text,true);
 result:=public.tj_runtime_manufacturer_invites(jsonb_build_object('action','create','email',recipient_email,'vendor_id',vendor));code:=result->>'code';invite:=(result->>'id')::uuid;
 PERFORM set_config('request.jwt.claim.sub',recipient_native::text,true);
 result:=public.tj_runtime_manufacturer_invites(jsonb_build_object('action','accept','code',code));
 IF result->>'ok'<>'true' OR NOT EXISTS(SELECT 1 FROM tj.mfr_members WHERE user_id=recipient_actor AND vendor_id=vendor AND role='vendor_owner') THEN RAISE EXCEPTION 'approved owner downgraded';END IF;
 UPDATE tj.mfr_members SET status='suspended' WHERE user_id=recipient_actor AND vendor_id=vendor;
 PERFORM set_config('request.jwt.claim.sub',admin_native::text,true);
 result:=public.tj_runtime_manufacturer_invites(jsonb_build_object('action','create','email',recipient_email,'vendor_id',vendor));code:=result->>'code';invite:=(result->>'id')::uuid;
 PERFORM set_config('request.jwt.claim.sub',recipient_native::text,true);
 result:=public.tj_runtime_manufacturer_invites(jsonb_build_object('action','accept','code',code));
 IF result->>'error'<>'membership_review_required' OR NOT EXISTS(SELECT 1 FROM tj.mfr_invites WHERE id=invite AND status='pending') THEN RAISE EXCEPTION 'suspended member reactivated';END IF;
 result:=public.tj_runtime_manufacturer_invites(jsonb_build_object('action','revoke','invite_id',invite));IF result->>'error'<>'forbidden' THEN RAISE EXCEPTION 'non-admin revoke allowed';END IF;
 PERFORM set_config('request.jwt.claim.sub',admin_native::text,true);
 result:=public.tj_runtime_manufacturer_invites(jsonb_build_object('action','revoke','invite_id',invite));IF result->>'status'<>'revoked' THEN RAISE EXCEPTION 'revoke failed';END IF;
 PERFORM set_config('request.jwt.claim.sub',recipient_native::text,true);
 result:=public.tj_runtime_manufacturer_invites(jsonb_build_object('action','accept','code',code));IF result->>'error'<>'invite_unavailable' THEN RAISE EXCEPTION 'revoked code accepted';END IF;
 UPDATE tj.mfr_vendors SET status='pending' WHERE id=vendor;
 PERFORM set_config('request.jwt.claim.sub',admin_native::text,true);
 result:=public.tj_runtime_manufacturer_invites(jsonb_build_object('action','create','email',recipient_email,'vendor_id',vendor));IF result->>'error'<>'vendor_unavailable' THEN RAISE EXCEPTION 'pending vendor invited';END IF;
 result:=public.tj_runtime_manufacturer_invites('{"action":"context","unexpected":true}');IF result->>'error'<>'invalid_request' THEN RAISE EXCEPTION 'unknown fields accepted';END IF;
 UPDATE auth.users SET email_confirmed_at=NULL WHERE id=recipient_native;
 PERFORM set_config('request.jwt.claim.sub',recipient_native::text,true);
 result:=public.tj_runtime_manufacturer_invites('{"action":"context"}');IF result->>'error'<>'email_confirmation_required' THEN RAISE EXCEPTION 'unconfirmed account allowed';END IF;
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 result:=public.tj_runtime_manufacturer_invites('{"action":"context"}');IF result->>'error'<>'identity_review_required' THEN RAISE EXCEPTION 'unmapped account allowed';END IF;
 IF has_function_privilege('anon','public.tj_runtime_manufacturer_invites(jsonb)','EXECUTE') OR has_function_privilege('service_role','public.tj_runtime_manufacturer_invites(jsonb)','EXECUTE') OR NOT has_function_privilege('authenticated','public.tj_runtime_manufacturer_invites(jsonb)','EXECUTE') THEN RAISE EXCEPTION 'RPC grants incorrect';END IF;
 IF has_table_privilege('authenticated','tj.mfr_invites','SELECT') OR has_table_privilege('authenticated','tj.mfr_invites','INSERT') OR has_table_privilege('authenticated','tj_private.manufacturer_invite_registry','SELECT') THEN RAISE EXCEPTION 'direct invite table access opened';END IF;
 PERFORM set_config('test.manufacturer.native',admin_native::text,true);
END $$;
SET LOCAL ROLE authenticated;
DO $$DECLARE result jsonb;BEGIN
 PERFORM set_config('request.jwt.claim.sub',current_setting('test.manufacturer.native'),true);
 result:=public.tj_runtime_manufacturer_invites('{"action":"context"}');
 IF result->>'ok'<>'true' OR result->'role'->>'is_admin'<>'true' THEN RAISE EXCEPTION 'authenticated wrapper inaccessible';END IF;
END $$;
ROLLBACK;
SELECT 'PASS: create/list/accept/revoke, correct source actor, editor role, owner preserved, suspended member denied, wrong email/legacy/expiry/replay/revoked inviter/tampered role/unmapped/unconfirmed denied, private grants, authenticated wrapper; all fixtures rolled back' result;
