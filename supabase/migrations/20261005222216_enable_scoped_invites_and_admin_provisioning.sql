CREATE TABLE tj_private.invite_delivery_limits(invite_id uuid PRIMARY KEY REFERENCES tj.org_invites(id) ON DELETE CASCADE,last_attempt timestamptz NOT NULL);
ALTER TABLE tj_private.invite_delivery_limits ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj_private.invite_delivery_limits FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj_private.invite_delivery_context(p_code text,p_reserve boolean DEFAULT false) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=tj_private.current_source_user_id();i tj.org_invites;org_name text;sender text;recent timestamptz;BEGIN
 IF actor IS NULL THEN RAISE EXCEPTION 'access_denied' USING ERRCODE='42501';END IF;
 IF p_code IS NULL OR length(p_code)>128 THEN RAISE EXCEPTION 'invalid_code' USING ERRCODE='22023';END IF;
 SELECT * INTO i FROM tj.org_invites WHERE invite_code=p_code AND status='pending' AND expires_at>now();
 IF NOT FOUND THEN RAISE EXCEPTION 'invite_not_found' USING ERRCODE='P0002';END IF;
 SELECT o.name INTO org_name FROM tj.organizations o WHERE o.id=i.organization_id AND o.status='active' AND o.deleted_at IS NULL AND (tj_private.is_platform_admin() OR EXISTS(SELECT 1 FROM tj.organization_members m WHERE m.organization_id=o.id AND m.user_id=actor AND m.status='active' AND m.role IN('owner','admin')));
 IF NOT FOUND THEN RAISE EXCEPTION 'access_denied' USING ERRCODE='42501';END IF;
 SELECT email INTO sender FROM tj.source_auth_users WHERE id=i.invited_by;
 IF p_reserve THEN
  PERFORM pg_advisory_xact_lock(hashtextextended('invite_mail:'||i.id::text,0));
  SELECT last_attempt INTO recent FROM tj_private.invite_delivery_limits WHERE invite_id=i.id;
  IF recent>now()-interval '5 minutes' THEN RETURN jsonb_build_object('reserved',false);END IF;
  INSERT INTO tj_private.invite_delivery_limits VALUES(i.id,now()) ON CONFLICT(invite_id) DO UPDATE SET last_attempt=excluded.last_attempt;
 END IF;
 RETURN jsonb_build_object('reserved',p_reserve,'id',i.id,'invite_code',i.invite_code,'invited_email',i.invited_email,'org_name',org_name,'role',i.role,'inviter_email',sender,'expires_at',i.expires_at);
END $$;
REVOKE ALL ON FUNCTION tj_private.invite_delivery_context(text,boolean) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION tj_private.invite_delivery_context(text,boolean) TO authenticated;
CREATE FUNCTION public.tj_invite_delivery_context(p_code text,p_reserve boolean DEFAULT false) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.invite_delivery_context(p_code,p_reserve); $$;
REVOKE ALL ON FUNCTION public.tj_invite_delivery_context(text,boolean) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.tj_invite_delivery_context(text,boolean) TO authenticated;
CREATE TABLE tj_private.admin_provision_intents(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),actor_native uuid NOT NULL,actor_source uuid NOT NULL,email text NOT NULL,full_name text NOT NULL,existing_native uuid,created_at timestamptz NOT NULL DEFAULT now(),completed_native uuid);
ALTER TABLE tj_private.admin_provision_intents ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj_private.admin_provision_intents FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj_private.prepare_admin_provision(p_email text,p_full_name text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=tj_private.current_source_user_id();native uuid;intent uuid;BEGIN
 IF actor IS NULL OR NOT EXISTS(SELECT 1 FROM tj.platform_admins WHERE user_id=actor AND role='super_admin') THEN RAISE EXCEPTION 'access_denied' USING ERRCODE='42501';END IF;
 p_email:=lower(btrim(p_email));p_full_name:=btrim(coalesce(p_full_name,''));
 IF p_email IS NULL OR length(p_email)>254 OR p_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' OR length(p_full_name)>120 THEN RAISE EXCEPTION 'invalid_request' USING ERRCODE='22023';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('admin_provision:'||actor::text,0));
 IF (SELECT count(*) FROM tj_private.admin_provision_intents WHERE actor_source=actor AND created_at>now()-interval '1 minute')>=5 THEN RAISE EXCEPTION 'rate_limited' USING ERRCODE='54000';END IF;
 SELECT id INTO native FROM auth.users WHERE lower(email)=p_email AND deleted_at IS NULL;
 IF native IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.source_user_identity_map im JOIN tj.source_auth_users s ON s.id=im.source_user_id JOIN auth.users u ON u.id=im.target_user_id WHERE im.target_user_id=native AND im.identity_verified AND im.mapping_status IN('approved_map','approved_create','approved_invite') AND im.approved_at IS NOT NULL AND im.approved_by<>'' AND im.activation_status='activated' AND im.activated_at IS NOT NULL AND s.deleted_at IS NULL AND u.deleted_at IS NULL AND u.email_confirmed_at IS NOT NULL AND NOT coalesce(u.is_anonymous,false) AND NOT coalesce(s.is_anonymous,false) AND (u.banned_until IS NULL OR u.banned_until<=now()) AND (s.banned_until IS NULL OR s.banned_until<=now())) THEN RAISE EXCEPTION 'identity_review_required' USING ERRCODE='40001';END IF;
 INSERT INTO tj_private.admin_provision_intents(actor_native,actor_source,email,full_name,existing_native) VALUES(auth.uid(),actor,p_email,p_full_name,native) RETURNING id INTO intent;
 RETURN jsonb_build_object('intent_id',intent,'existing_user_id',native);
END $$;
REVOKE ALL ON FUNCTION tj_private.prepare_admin_provision(text,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION tj_private.prepare_admin_provision(text,text) TO authenticated;
CREATE FUNCTION public.tj_prepare_admin_provision(p_email text,p_full_name text) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.prepare_admin_provision(p_email,p_full_name); $$;
REVOKE ALL ON FUNCTION public.tj_prepare_admin_provision(text,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.tj_prepare_admin_provision(text,text) TO authenticated;
CREATE FUNCTION tj_private.finish_admin_provision(p_intent uuid,p_native uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE i tj_private.admin_provision_intents;u auth.users;src uuid;actor uuid;old_sub text:=current_setting('request.jwt.claim.sub',true);BEGIN
 SELECT * INTO i FROM tj_private.admin_provision_intents WHERE id=p_intent FOR UPDATE;
 IF NOT FOUND OR i.created_at<now()-interval '5 minutes' THEN RAISE EXCEPTION 'invalid_intent' USING ERRCODE='42501';END IF;
 PERFORM set_config('request.jwt.claim.sub',i.actor_native::text,true);actor:=tj_private.current_source_user_id();PERFORM set_config('request.jwt.claim.sub',coalesce(old_sub,''),true);
 IF actor IS DISTINCT FROM i.actor_source OR NOT EXISTS(SELECT 1 FROM tj.platform_admins WHERE user_id=actor AND role='super_admin') THEN RAISE EXCEPTION 'access_denied' USING ERRCODE='42501';END IF;
 IF i.completed_native IS NOT NULL THEN
  IF i.completed_native<>p_native THEN RAISE EXCEPTION 'intent_already_used' USING ERRCODE='42501';END IF;
  RETURN jsonb_build_object('ok',true,'user_id',p_native,'already_completed',true);
 END IF;
 SELECT * INTO u FROM auth.users WHERE id=p_native AND deleted_at IS NULL AND (banned_until IS NULL OR banned_until<=now()) AND NOT coalesce(is_anonymous,false) AND email_confirmed_at IS NOT NULL;
 IF NOT FOUND OR lower(u.email)<>i.email OR (i.existing_native IS NOT NULL AND i.existing_native<>p_native) OR (i.existing_native IS NULL AND u.created_at<i.created_at) THEN RAISE EXCEPTION 'target_identity_mismatch' USING ERRCODE='42501';END IF;
 SELECT source_user_id INTO src FROM tj.source_user_identity_map WHERE target_user_id=p_native AND identity_verified AND mapping_status IN('approved_map','approved_create','approved_invite') AND approved_at IS NOT NULL AND approved_by<>'' AND activation_status='activated' AND activated_at IS NOT NULL;
 IF src IS NULL THEN
  IF i.existing_native IS NOT NULL OR EXISTS(SELECT 1 FROM tj.source_auth_users WHERE id=p_native OR lower(email)=i.email) OR EXISTS(SELECT 1 FROM tj.source_user_identity_map WHERE target_user_id=p_native OR source_user_id=p_native) THEN RAISE EXCEPTION 'identity_review_required' USING ERRCODE='40001';END IF;
  src:=p_native;
  INSERT INTO tj.source_auth_users(id,email,aud,role,created_at,updated_at,email_confirmed_at,confirmed_at,is_anonymous,source_profile_exists) VALUES(src,i.email,'authenticated','authenticated',u.created_at,now(),u.email_confirmed_at,u.email_confirmed_at,false,true);
  INSERT INTO tj.source_user_identity_map(source_user_id,target_user_id,mapping_status,mapping_reason,identity_verified,verified_by,approved_at,approved_by,activation_status,activated_at) VALUES(src,p_native,'approved_create','Created through authorized US East platform provisioning',true,actor::text,now(),actor::text,'activated',now());
 END IF;
 INSERT INTO tj.profiles(id,user_id,email,full_name) VALUES(src,src,i.email,coalesce(nullif(i.full_name,''),split_part(i.email,'@',1))) ON CONFLICT(user_id) DO NOTHING;
 INSERT INTO tj.platform_admins(user_id,email,full_name,role,created_by) VALUES(src,i.email,nullif(i.full_name,''),'super_admin',actor) ON CONFLICT(user_id) DO UPDATE SET role='super_admin';
 UPDATE tj_private.admin_provision_intents SET completed_native=p_native WHERE id=i.id;
 RETURN jsonb_build_object('ok',true,'user_id',p_native);
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claim.sub',coalesce(old_sub,''),true);RAISE;
END $$;
REVOKE ALL ON FUNCTION tj_private.finish_admin_provision(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj_private.finish_admin_provision(uuid,uuid) TO service_role;
CREATE FUNCTION public.aiq_finish_admin_provision(p_intent uuid,p_native uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.finish_admin_provision(p_intent,p_native); $$;
REVOKE ALL ON FUNCTION public.aiq_finish_admin_provision(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.aiq_finish_admin_provision(uuid,uuid) TO service_role;
NOTIFY pgrst,'reload schema';
