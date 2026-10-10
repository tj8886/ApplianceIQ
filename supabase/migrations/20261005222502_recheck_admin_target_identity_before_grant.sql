-- Historical or revoked identities require explicit review; no email-based reassignment.
CREATE OR REPLACE FUNCTION tj_private.prepare_admin_provision(p_email text,p_full_name text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=tj_private.current_source_user_id();native uuid;intent uuid;BEGIN
 IF actor IS NULL OR NOT EXISTS(SELECT 1 FROM tj.platform_admins WHERE user_id=actor AND role='super_admin') THEN RAISE EXCEPTION 'access_denied' USING ERRCODE='42501';END IF;
 p_email:=lower(btrim(p_email));p_full_name:=btrim(coalesce(p_full_name,''));
 IF p_email IS NULL OR length(p_email)>254 OR p_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' OR length(p_full_name)>120 THEN RAISE EXCEPTION 'invalid_request' USING ERRCODE='22023';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('admin_provision:'||actor::text,0));
 IF (SELECT count(*) FROM tj_private.admin_provision_intents WHERE actor_source=actor AND created_at>now()-interval '1 minute')>=5 THEN RAISE EXCEPTION 'rate_limited' USING ERRCODE='54000';END IF;
 SELECT id INTO native FROM auth.users WHERE lower(email)=p_email AND deleted_at IS NULL;
 IF native IS NULL AND EXISTS(SELECT 1 FROM tj.source_auth_users WHERE lower(email)=p_email) THEN RAISE EXCEPTION 'identity_review_required' USING ERRCODE='40001';END IF;
 IF native IS NOT NULL AND (SELECT count(*) FROM tj.source_user_identity_map WHERE target_user_id=native)<>1 THEN RAISE EXCEPTION 'identity_review_required' USING ERRCODE='40001';END IF;
 IF native IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.source_user_identity_map im JOIN tj.source_auth_users s ON s.id=im.source_user_id JOIN auth.users u ON u.id=im.target_user_id WHERE im.target_user_id=native AND im.identity_verified AND im.mapping_status IN('approved_map','approved_create','approved_invite') AND im.approved_at IS NOT NULL AND im.approved_by<>'' AND im.activation_status='activated' AND im.activated_at IS NOT NULL AND s.deleted_at IS NULL AND u.deleted_at IS NULL AND u.email_confirmed_at IS NOT NULL AND NOT coalesce(u.is_anonymous,false) AND NOT coalesce(s.is_anonymous,false) AND (u.banned_until IS NULL OR u.banned_until<=now()) AND (s.banned_until IS NULL OR s.banned_until<=now())) THEN RAISE EXCEPTION 'identity_review_required' USING ERRCODE='40001';END IF;
 INSERT INTO tj_private.admin_provision_intents(actor_native,actor_source,email,full_name,existing_native) VALUES(auth.uid(),actor,p_email,p_full_name,native) RETURNING id INTO intent;
 RETURN jsonb_build_object('intent_id',intent,'existing_user_id',native);
END $$;
CREATE OR REPLACE FUNCTION tj_private.finish_admin_provision(p_intent uuid,p_native uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
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
 IF i.existing_native IS NOT NULL AND (SELECT count(*) FROM tj.source_user_identity_map WHERE target_user_id=p_native)<>1 THEN RAISE EXCEPTION 'identity_review_required' USING ERRCODE='40001';END IF;
 SELECT im.source_user_id INTO src FROM tj.source_user_identity_map im JOIN tj.source_auth_users s ON s.id=im.source_user_id WHERE im.target_user_id=p_native AND im.identity_verified AND im.mapping_status IN('approved_map','approved_create','approved_invite') AND im.approved_at IS NOT NULL AND im.approved_by<>'' AND im.activation_status='activated' AND im.activated_at IS NOT NULL AND s.deleted_at IS NULL AND NOT coalesce(s.is_anonymous,false) AND (s.banned_until IS NULL OR s.banned_until<=now());
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
