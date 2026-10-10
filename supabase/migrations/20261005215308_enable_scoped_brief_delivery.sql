CREATE FUNCTION tj_private.brief_delivery_context(p_org uuid,p_brief uuid,p_recipients jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=tj_private.current_source_user_id();brief tj.ai_manager_briefs%rowtype;eligible jsonb;selected jsonb;
BEGIN
 IF actor IS NULL OR NOT EXISTS(SELECT 1 FROM tj.organization_members m JOIN tj.organizations o ON o.id=m.organization_id WHERE m.organization_id=p_org AND m.user_id=actor AND m.status='active' AND m.role IN ('owner','admin','manager','super_admin') AND o.status='active' AND o.deleted_at IS NULL) THEN RAISE EXCEPTION 'access_denied' USING ERRCODE='42501';END IF;
 IF jsonb_typeof(p_recipients) IS DISTINCT FROM 'array' OR jsonb_array_length(p_recipients)>20 OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_recipients) v WHERE jsonb_typeof(v)<>'string' OR length(v#>>'{}')>254) THEN RAISE EXCEPTION 'invalid_recipients' USING ERRCODE='22023';END IF;
 SELECT * INTO brief FROM tj.ai_manager_briefs WHERE organization_id=p_org AND (p_brief IS NULL OR id=p_brief) ORDER BY generated_at DESC LIMIT 1;
 IF NOT FOUND THEN RAISE EXCEPTION 'no_brief_found' USING ERRCODE='P0002';END IF;
 SELECT coalesce(jsonb_agg(email ORDER BY email),'[]'::jsonb) INTO eligible FROM (
  SELECT DISTINCT lower(u.email) email FROM tj.organization_members m JOIN tj.source_user_identity_map im ON im.source_user_id=m.user_id JOIN auth.users u ON u.id=im.target_user_id JOIN tj.source_auth_users s ON s.id=im.source_user_id
  WHERE m.organization_id=p_org AND m.status='active' AND m.role IN ('owner','admin','manager','super_admin') AND im.identity_verified AND im.mapping_status IN ('approved_map','approved_create','approved_invite') AND im.approved_at IS NOT NULL AND nullif(btrim(im.approved_by),'') IS NOT NULL AND im.activation_status='activated' AND im.activated_at IS NOT NULL
   AND u.email_confirmed_at IS NOT NULL AND u.deleted_at IS NULL AND s.deleted_at IS NULL AND NOT coalesce(u.is_anonymous,false) AND NOT coalesce(s.is_anonymous,false) AND (u.banned_until IS NULL OR u.banned_until<=now()) AND (s.banned_until IS NULL OR s.banned_until<=now()) AND u.email IS NOT NULL) r;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements_text(p_recipients) e WHERE NOT eligible ? lower(btrim(e))) THEN RAISE EXCEPTION 'recipient_not_active_org_manager' USING ERRCODE='42501';END IF;
 selected:=CASE WHEN jsonb_array_length(p_recipients)=0 THEN eligible ELSE (SELECT jsonb_agg(e ORDER BY e) FROM (SELECT DISTINCT lower(btrim(e)) e FROM jsonb_array_elements_text(p_recipients) e) r) END;
 IF jsonb_array_length(selected)=0 THEN RAISE EXCEPTION 'no_recipients' USING ERRCODE='22023';END IF;
 IF jsonb_array_length(selected)>20 THEN RAISE EXCEPTION 'select_up_to_20_recipients' USING ERRCODE='22023';END IF;
 IF octet_length(to_jsonb(brief)::text)>131072 THEN RAISE EXCEPTION 'brief_too_large' USING ERRCODE='22023';END IF;
 RETURN jsonb_build_object('brief',to_jsonb(brief),'recipients',selected);
END $$;
REVOKE ALL ON FUNCTION tj_private.brief_delivery_context(uuid,uuid,jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION tj_private.brief_delivery_context(uuid,uuid,jsonb) TO authenticated;
CREATE FUNCTION public.tj_brief_delivery_context(p_org uuid,p_brief uuid DEFAULT NULL,p_recipients jsonb DEFAULT '[]') RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.brief_delivery_context(p_org,p_brief,p_recipients); $$;
REVOKE ALL ON FUNCTION public.tj_brief_delivery_context(uuid,uuid,jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.tj_brief_delivery_context(uuid,uuid,jsonb) TO authenticated;

CREATE FUNCTION tj_private.finish_brief_delivery(p_native uuid,p_org uuid,p_brief uuid,p_recipients jsonb,p_sent int,p_failed int) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE previous_sub text:=current_setting('request.jwt.claim.sub',true);context jsonb;
BEGIN
 IF p_sent<0 OR p_failed<0 OR p_sent IS NULL OR p_failed IS NULL OR p_sent+p_failed<1 OR p_sent+p_failed>20 THEN RAISE EXCEPTION 'invalid_delivery_counts' USING ERRCODE='22023';END IF;
 PERFORM set_config('request.jwt.claim.sub',p_native::text,true);
 context:=tj_private.brief_delivery_context(p_org,p_brief,p_recipients);
 PERFORM set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true);
 IF p_sent+p_failed<>jsonb_array_length(context->'recipients') THEN RAISE EXCEPTION 'recipient_count_mismatch' USING ERRCODE='22023';END IF;
 UPDATE tj.ai_manager_briefs SET delivery_status=CASE WHEN p_sent>0 THEN 'delivered' ELSE 'failed' END,delivery_channels=CASE WHEN p_sent>0 THEN '["in_app","email"]'::jsonb ELSE CASE WHEN delivery_channels ? 'email' THEN delivery_channels ELSE '["in_app"]'::jsonb END END,delivered_at=CASE WHEN p_sent>0 THEN now() ELSE delivered_at END WHERE id=p_brief AND organization_id=p_org;
 RETURN jsonb_build_object('ok',true,'accepted',p_sent,'failed',p_failed);
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true);RAISE;
END $$;
REVOKE ALL ON FUNCTION tj_private.finish_brief_delivery(uuid,uuid,uuid,jsonb,int,int) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj_private.finish_brief_delivery(uuid,uuid,uuid,jsonb,int,int) TO service_role;
CREATE FUNCTION public.aiq_finish_brief_delivery(p_native uuid,p_org uuid,p_brief uuid,p_recipients jsonb,p_sent int,p_failed int) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.finish_brief_delivery(p_native,p_org,p_brief,p_recipients,p_sent,p_failed); $$;
REVOKE ALL ON FUNCTION public.aiq_finish_brief_delivery(uuid,uuid,uuid,jsonb,int,int) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.aiq_finish_brief_delivery(uuid,uuid,uuid,jsonb,int,int) TO service_role;
NOTIFY pgrst,'reload schema';
