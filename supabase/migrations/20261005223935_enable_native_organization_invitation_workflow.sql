-- Invitation capability preview plus native verified-email acceptance.
-- No anonymous table reads or direct membership/identity writes are introduced.
CREATE FUNCTION tj_private.validate_invite_authority(p_org uuid,p_actor uuid,p_role text,p_position uuid,p_manager uuid,p_location uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE owner_access boolean;BEGIN
 IF p_actor IS NULL OR NOT EXISTS(SELECT 1 FROM tj.organizations WHERE id=p_org AND status='active' AND deleted_at IS NULL) OR
  (SELECT count(*) FROM tj.source_user_identity_map im JOIN tj.source_auth_users s ON s.id=im.source_user_id JOIN auth.users u ON u.id=im.target_user_id WHERE im.source_user_id=p_actor AND im.identity_verified AND im.mapping_status IN('approved_map','approved_create','approved_invite') AND im.approved_at IS NOT NULL AND im.approved_by<>'' AND im.activation_status='activated' AND im.activated_at IS NOT NULL AND s.deleted_at IS NULL AND u.deleted_at IS NULL AND (s.banned_until IS NULL OR s.banned_until<=now()) AND (u.banned_until IS NULL OR u.banned_until<=now()) AND NOT coalesce(s.is_anonymous,false) AND NOT coalesce(u.is_anonymous,false) AND u.email_confirmed_at IS NOT NULL)<>1 THEN RAISE EXCEPTION 'access_denied' USING ERRCODE='42501';END IF;
 owner_access:=EXISTS(SELECT 1 FROM tj.platform_admins WHERE user_id=p_actor) OR EXISTS(SELECT 1 FROM tj.organization_members WHERE organization_id=p_org AND user_id=p_actor AND role='owner' AND status='active');
 IF NOT owner_access AND NOT EXISTS(SELECT 1 FROM tj.organization_members WHERE organization_id=p_org AND user_id=p_actor AND role='admin' AND status='active') THEN RAISE EXCEPTION 'access_denied' USING ERRCODE='42501';END IF;
 IF p_role IS NULL OR p_role NOT IN('owner','admin','member') OR (p_role='owner' AND NOT owner_access) THEN RAISE EXCEPTION 'role_not_allowed' USING ERRCODE='42501';END IF;
 IF p_position IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.org_roles WHERE id=p_position AND organization_id=p_org AND active IS TRUE AND role_level>=CASE p_role WHEN 'owner' THEN 1 WHEN 'admin' THEN 2 ELSE 3 END) THEN RAISE EXCEPTION 'position_not_allowed' USING ERRCODE='42501';END IF;
 IF p_manager IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.organization_members WHERE user_id=p_manager AND organization_id=p_org AND status='active') THEN RAISE EXCEPTION 'manager_not_allowed' USING ERRCODE='42501';END IF;
 IF p_location IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.org_locations WHERE id=p_location AND organization_id=p_org AND is_active) THEN RAISE EXCEPTION 'location_not_allowed' USING ERRCODE='42501';END IF;
END $$;
REVOKE ALL ON FUNCTION tj_private.validate_invite_authority(uuid,uuid,text,uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj_private.create_org_invite(p_org uuid,p_email text,p_role text DEFAULT 'member',p_position uuid DEFAULT NULL,p_location uuid DEFAULT NULL,p_manager uuid DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=tj_private.current_source_user_id();i tj.org_invites;BEGIN
 PERFORM tj_private.validate_invite_authority(p_org,actor,p_role,p_position,p_manager,p_location);
 p_email:=lower(btrim(p_email));IF p_email IS NULL OR length(p_email)>254 OR p_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN RAISE EXCEPTION 'invalid_email' USING ERRCODE='22023';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('invite_create:'||p_org::text,0));
 IF (SELECT count(*) FROM tj.org_invites WHERE organization_id=p_org AND created_at>now()-interval '1 minute')>=100 THEN RAISE EXCEPTION 'rate_limited' USING ERRCODE='54000';END IF;
 INSERT INTO tj.org_invites(organization_id,invited_email,role,org_role_id,location_id,manager_id,invited_by,invite_code) VALUES(p_org,p_email,p_role,p_position,p_location,p_manager,actor,encode(extensions.gen_random_bytes(16),'hex')) RETURNING * INTO i;
 RETURN to_jsonb(i);
END $$;
CREATE FUNCTION tj_private.revoke_org_invite(p_id uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE i tj.org_invites;actor uuid:=tj_private.current_source_user_id();BEGIN
 SELECT * INTO i FROM tj.org_invites WHERE id=p_id FOR UPDATE;IF NOT FOUND THEN RAISE EXCEPTION 'invite_not_found' USING ERRCODE='P0002';END IF;
 -- Revoke is allowed even if an invite's assigned role/store is no longer valid.
 PERFORM tj_private.validate_invite_authority(i.organization_id,actor,'member',NULL,NULL,NULL);
 IF i.status='accepted' THEN RAISE EXCEPTION 'invite_already_accepted' USING ERRCODE='40001';END IF;
 UPDATE tj.org_invites SET status='revoked' WHERE id=i.id;RETURN jsonb_build_object('ok',true);
END $$;
CREATE OR REPLACE FUNCTION tj_private.get_invite_preview(p_code text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE i tj.org_invites;org_name text;BEGIN
 IF p_code IS NULL OR p_code !~ '^[a-fA-F0-9]{32}$' THEN RETURN jsonb_build_object('ok',false);END IF;
 SELECT * INTO i FROM tj.org_invites WHERE invite_code=p_code AND status='pending' AND expires_at>now();IF NOT FOUND THEN RETURN jsonb_build_object('ok',false);END IF;
 BEGIN PERFORM tj_private.validate_invite_authority(i.organization_id,i.invited_by,i.role,i.org_role_id,i.manager_id,i.location_id);EXCEPTION WHEN insufficient_privilege THEN RETURN jsonb_build_object('ok',false);END;
 SELECT name INTO org_name FROM tj.organizations WHERE id=i.organization_id;
 RETURN jsonb_build_object('ok',true,'status','pending','expired',false,'invited_email',i.invited_email,'organization_name',org_name,'role',i.role,'expires_at',i.expires_at);
END $$;
CREATE OR REPLACE FUNCTION tj_private.accept_org_invite(p_code text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE native uuid:=auth.uid();actor uuid;u auth.users;i tj.org_invites;m tj.organization_members;manager_member uuid;org_name text;BEGIN
 IF native IS NULL THEN RETURN jsonb_build_object('ok',false,'error','not_authenticated');END IF;
 IF p_code IS NULL OR p_code !~ '^[a-fA-F0-9]{32}$' THEN RETURN jsonb_build_object('ok',false,'error','invalid_or_used');END IF;
 SELECT * INTO u FROM auth.users WHERE id=native AND deleted_at IS NULL AND email_confirmed_at IS NOT NULL AND NOT coalesce(is_anonymous,false) AND (banned_until IS NULL OR banned_until<=now()) FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','email_confirmation_required');END IF;
 SELECT * INTO i FROM tj.org_invites WHERE invite_code=p_code AND status='pending' FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','invalid_or_used');END IF;
 IF i.expires_at<=now() THEN RETURN jsonb_build_object('ok',false,'error','expired');END IF;
 IF lower(i.invited_email)<>lower(coalesce(u.email,'')) THEN RETURN jsonb_build_object('ok',false,'error','email_mismatch','expected',i.invited_email);END IF;
 BEGIN PERFORM tj_private.validate_invite_authority(i.organization_id,i.invited_by,i.role,i.org_role_id,i.manager_id,i.location_id);EXCEPTION WHEN insufficient_privilege THEN RETURN jsonb_build_object('ok',false,'error','invite_no_longer_authorized');END;
 actor:=tj_private.current_source_user_id();
 IF actor IS NULL THEN
  -- Only a genuinely new staged identity is enrolled. Never bind a historical source user by email.
  IF EXISTS(SELECT 1 FROM tj.source_user_identity_map WHERE target_user_id=native OR source_user_id=native) OR EXISTS(SELECT 1 FROM tj.source_auth_users WHERE id=native OR lower(email)=lower(u.email)) THEN RETURN jsonb_build_object('ok',false,'error','identity_review_required');END IF;
  actor:=native;
  INSERT INTO tj.source_auth_users(id,email,aud,role,created_at,updated_at,email_confirmed_at,confirmed_at,is_anonymous,source_profile_exists) VALUES(actor,u.email,'authenticated','authenticated',u.created_at,now(),u.email_confirmed_at,u.email_confirmed_at,false,true);
  INSERT INTO tj.source_user_identity_map(source_user_id,target_user_id,mapping_status,mapping_reason,identity_verified,verified_by,approved_at,approved_by,activation_status,activated_at) VALUES(actor,native,'approved_invite','Verified native email accepted authorized organization invitation',true,native::text,now(),i.invited_by::text,'activated',now());
 END IF;
 SELECT * INTO m FROM tj.organization_members WHERE organization_id=i.organization_id AND user_id=actor FOR UPDATE;
 IF FOUND AND m.status IN('suspended','removed') THEN RETURN jsonb_build_object('ok',false,'error','membership_review_required');END IF;
 IF NOT FOUND OR m.status='invited' THEN
  IF i.manager_id IS NOT NULL THEN SELECT id INTO manager_member FROM tj.organization_members WHERE organization_id=i.organization_id AND user_id=i.manager_id AND status='active';END IF;
  INSERT INTO tj.organization_members(organization_id,user_id,role,org_role_id,manager_id,status) VALUES(i.organization_id,actor,i.role,i.org_role_id,manager_member,'active') ON CONFLICT(organization_id,user_id) DO UPDATE SET role=excluded.role,org_role_id=excluded.org_role_id,manager_id=excluded.manager_id,status='active' RETURNING * INTO m;
  IF i.location_id IS NOT NULL THEN INSERT INTO tj.org_location_members(organization_id,location_id,user_id,is_primary) VALUES(i.organization_id,i.location_id,actor,true) ON CONFLICT(location_id,user_id) DO NOTHING;END IF;
 END IF;
 -- Existing active memberships retain their role, position, manager and store assignments.
 INSERT INTO tj.profiles(id,user_id,email,full_name) VALUES(actor,actor,u.email,split_part(u.email,'@',1)) ON CONFLICT(user_id) DO NOTHING;
 UPDATE tj.org_invites SET status='accepted',accepted_at=now() WHERE id=i.id;
 SELECT name INTO org_name FROM tj.organizations WHERE id=i.organization_id;
 RETURN jsonb_build_object('ok',true,'organization_id',i.organization_id,'organization_name',org_name,'role',m.role);
END $$;
REVOKE ALL ON FUNCTION tj_private.create_org_invite(uuid,text,text,uuid,uuid,uuid),tj_private.revoke_org_invite(uuid),tj_private.accept_org_invite(text),tj_private.get_invite_preview(text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.create_org_invite(uuid,text,text,uuid,uuid,uuid),tj_private.revoke_org_invite(uuid),tj_private.accept_org_invite(text),tj_private.get_invite_preview(text) TO authenticated;
GRANT EXECUTE ON FUNCTION tj_private.get_invite_preview(text) TO anon;
CREATE FUNCTION public.tj_runtime_create_org_invite(p_org uuid,p_email text,p_role text DEFAULT 'member',p_position uuid DEFAULT NULL,p_location uuid DEFAULT NULL,p_manager uuid DEFAULT NULL) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.create_org_invite(p_org,p_email,p_role,p_position,p_location,p_manager); $$;
CREATE FUNCTION public.tj_runtime_revoke_org_invite(p_id uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.revoke_org_invite(p_id); $$;
CREATE FUNCTION public.tj_runtime_get_invite_preview(p_code text) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.get_invite_preview(p_code); $$;
CREATE FUNCTION public.tj_runtime_accept_org_invite(p_code text) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.accept_org_invite(p_code); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_create_org_invite(uuid,text,text,uuid,uuid,uuid),public.tj_runtime_revoke_org_invite(uuid),public.tj_runtime_accept_org_invite(text),public.tj_runtime_get_invite_preview(text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tj_runtime_create_org_invite(uuid,text,text,uuid,uuid,uuid),public.tj_runtime_revoke_org_invite(uuid),public.tj_runtime_accept_org_invite(text),public.tj_runtime_get_invite_preview(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_get_invite_preview(text) TO anon;
NOTIFY pgrst,'reload schema';
