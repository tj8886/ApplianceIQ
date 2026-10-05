CREATE FUNCTION tj_private.append_router_assistant_turn(p_conversation_id uuid,p_target_user_id uuid,p_expected_version integer,p_content text,p_persona text,p_metadata jsonb DEFAULT '{}') RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; c tj.ai_conversations%rowtype; m tj.ai_conversation_memory%rowtype; result uuid;BEGIN
 IF current_setting('role',true)<>'service_role' THEN RAISE EXCEPTION 'Service role required' USING ERRCODE='42501';END IF;
 SELECT CASE WHEN count(*)=1 THEN min(m.source_user_id::text)::uuid END INTO actor FROM tj.source_user_identity_map m JOIN tj.source_auth_users s ON s.id=m.source_user_id JOIN auth.users u ON u.id=m.target_user_id WHERE m.target_user_id=p_target_user_id AND m.identity_verified AND m.mapping_status IN ('approved_map','approved_create','approved_invite') AND m.approved_at IS NOT NULL AND nullif(btrim(m.approved_by),'') IS NOT NULL AND m.activation_status='activated' AND m.activated_at IS NOT NULL AND s.deleted_at IS NULL AND u.deleted_at IS NULL AND (s.banned_until IS NULL OR s.banned_until<=now()) AND (u.banned_until IS NULL OR u.banned_until<=now()) AND NOT coalesce(s.is_anonymous,false) AND NOT coalesce(u.is_anonymous,false);

 SELECT * INTO c FROM tj.ai_conversations WHERE id=p_conversation_id AND user_id=actor;
 IF actor IS NULL OR NOT FOUND OR NOT EXISTS(SELECT 1 FROM tj.organizations WHERE id=c.organization_id AND status='active' AND deleted_at IS NULL) OR NOT (EXISTS(SELECT 1 FROM tj.organization_members WHERE organization_id=c.organization_id AND user_id=actor AND status='active') OR EXISTS(SELECT 1 FROM tj.platform_admins WHERE user_id=actor)) THEN RAISE EXCEPTION 'Conversation access denied' USING ERRCODE='42501';END IF;
 SELECT * INTO m FROM tj.ai_conversation_memory WHERE conversation_id=c.id FOR UPDATE;
 IF NOT FOUND OR p_expected_version IS NULL OR m.memory_version<>p_expected_version THEN RAISE EXCEPTION 'Conversation changed' USING ERRCODE='40001';END IF;
 IF p_content IS NULL OR length(p_content) NOT BETWEEN 1 AND 100000 OR length(p_persona)>120 OR jsonb_typeof(p_metadata) IS DISTINCT FROM 'object' OR octet_length(p_metadata::text)>8000 THEN RAISE EXCEPTION 'Invalid assistant turn' USING ERRCODE='22023';END IF;
 INSERT INTO tj.ai_conversation_turns(conversation_id,user_id,role,content,persona_name,metadata) VALUES(c.id,actor,'assistant',p_content,p_persona,p_metadata) RETURNING id INTO result;
 UPDATE tj.ai_conversations SET last_message_at=now(),updated_at=now() WHERE id=c.id;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION tj_private.append_router_assistant_turn(uuid,uuid,integer,text,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj_private.append_router_assistant_turn(uuid,uuid,integer,text,text,jsonb) TO service_role;
CREATE FUNCTION public.aiq_append_router_assistant_turn(p_conversation_id uuid,p_target_user_id uuid,p_expected_version integer,p_content text,p_persona text,p_metadata jsonb DEFAULT '{}') RETURNS uuid LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$SELECT tj_private.append_router_assistant_turn(p_conversation_id,p_target_user_id,p_expected_version,p_content,p_persona,p_metadata);$$;
REVOKE ALL ON FUNCTION public.aiq_append_router_assistant_turn(uuid,uuid,integer,text,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.aiq_append_router_assistant_turn(uuid,uuid,integer,text,text,jsonb) TO service_role;
NOTIFY pgrst,'reload schema';
