-- Source training reads remain scoped to active mapped identity and organization.
ALTER TABLE tj.ai_roleplay_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY consolidation_owned_roleplay_read ON tj.ai_roleplay_sessions FOR SELECT TO authenticated USING(tj_private.is_source_self(user_id) AND tj_private.can_read_runtime_org(organization_id));
GRANT SELECT ON tj.ai_roleplay_sessions TO authenticated;
ALTER TABLE tj.performance_roleplay_links ENABLE ROW LEVEL SECURITY;
CREATE POLICY consolidation_owned_roleplay_links ON tj.performance_roleplay_links FOR SELECT TO authenticated USING(tj_private.is_source_self(user_id) AND tj_private.can_read_runtime_org(organization_id));
GRANT SELECT ON tj.performance_roleplay_links TO authenticated;
ALTER TABLE tj.performance_scenarios ENABLE ROW LEVEL SECURITY;
CREATE POLICY consolidation_visible_active_scenarios ON tj.performance_scenarios FOR SELECT TO authenticated USING(active AND ((organization_id IS NULL AND (SELECT tj_private.has_active_mapped_org())) OR tj_private.can_read_runtime_org(organization_id)));
GRANT SELECT ON tj.performance_scenarios TO authenticated;

CREATE FUNCTION tj_private.commit_roleplay_session(p_native_user uuid,p_session_id uuid,p_organization_id uuid,p_expected_transcript jsonb,p_patch jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid;sess tj.ai_roleplay_sessions%rowtype;org uuid;new_transcript jsonb;val jsonb;BEGIN
 IF current_setting('role',true)<>'service_role' THEN RAISE EXCEPTION 'Service role required' USING ERRCODE='42501';END IF;
 SELECT CASE WHEN count(*)=1 THEN min(im.source_user_id::text)::uuid END INTO actor FROM tj.source_user_identity_map im JOIN tj.source_auth_users s ON s.id=im.source_user_id JOIN auth.users u ON u.id=im.target_user_id WHERE im.target_user_id=p_native_user AND im.identity_verified AND im.mapping_status IN ('approved_map','approved_create','approved_invite') AND im.approved_at IS NOT NULL AND nullif(btrim(im.approved_by),'') IS NOT NULL AND im.activation_status='activated' AND im.activated_at IS NOT NULL AND s.deleted_at IS NULL AND u.deleted_at IS NULL AND (s.banned_until IS NULL OR s.banned_until<=now()) AND (u.banned_until IS NULL OR u.banned_until<=now()) AND NOT coalesce(s.is_anonymous,false) AND NOT coalesce(u.is_anonymous,false);
 IF actor IS NULL THEN RAISE EXCEPTION 'Mapped identity required' USING ERRCODE='42501';END IF;
 IF jsonb_typeof(p_patch) IS DISTINCT FROM 'object' OR octet_length(p_patch::text)>120000 OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_patch) k WHERE k NOT IN('scenario_type','transcript','total_turns','status','session_score','kpi_scores','feedback','scoring_breakdown','coach_summary','scoring_version','completed_at')) THEN RAISE EXCEPTION 'Invalid session patch' USING ERRCODE='22023';END IF;
 IF p_session_id IS NULL THEN org:=p_organization_id;ELSE SELECT * INTO sess FROM tj.ai_roleplay_sessions WHERE id=p_session_id AND user_id=actor FOR UPDATE;IF NOT FOUND THEN RAISE EXCEPTION 'Session access denied' USING ERRCODE='42501';END IF;org:=sess.organization_id;END IF;
 IF org IS NULL OR NOT EXISTS(SELECT 1 FROM tj.organizations WHERE id=org AND status='active' AND deleted_at IS NULL) OR NOT(EXISTS(SELECT 1 FROM tj.organization_members WHERE organization_id=org AND user_id=actor AND status='active') OR EXISTS(SELECT 1 FROM tj.platform_admins WHERE user_id=actor)) THEN RAISE EXCEPTION 'Organization access denied' USING ERRCODE='42501';END IF;
 IF p_session_id IS NOT NULL AND (sess.status<>'active' OR coalesce(sess.transcript,'[]') IS DISTINCT FROM coalesce(p_expected_transcript,'[]')) THEN RAISE EXCEPTION 'Session changed' USING ERRCODE='40001';END IF;
 IF p_patch?'status' AND p_patch->>'status' NOT IN('active','completed') OR p_patch?'feedback' AND length(p_patch->>'feedback')>10000 OR p_patch?'scoring_version' AND length(p_patch->>'scoring_version')>80 OR p_patch?'session_score' AND p_patch->'session_score'<>'null' AND ((p_patch->>'session_score')::numeric NOT BETWEEN 0 AND 100) OR p_patch?'total_turns' AND ((p_patch->>'total_turns')::integer NOT BETWEEN 0 AND 100) THEN RAISE EXCEPTION 'Invalid session values' USING ERRCODE='22023';END IF;
 new_transcript:=coalesce(p_patch->'transcript',sess.transcript,'[]');
 IF jsonb_typeof(new_transcript) IS DISTINCT FROM 'array' OR jsonb_array_length(new_transcript)>100 OR octet_length(new_transcript::text)>100000 OR EXISTS(SELECT 1 FROM jsonb_array_elements(new_transcript) t WHERE jsonb_typeof(t) IS DISTINCT FROM 'object' OR t->>'role' IS NULL OR t->>'role' NOT IN('customer','rep','ai_rep') OR jsonb_typeof(t->'content') IS DISTINCT FROM 'string' OR length(t->>'content') NOT BETWEEN 1 AND 12000) THEN RAISE EXCEPTION 'Invalid transcript' USING ERRCODE='22023';END IF;
 FOR val IN SELECT value FROM jsonb_each(p_patch) WHERE key IN('kpi_scores','scoring_breakdown','coach_summary') LOOP IF jsonb_typeof(val) IS DISTINCT FROM 'object' OR octet_length(val::text)>20000 THEN RAISE EXCEPTION 'Invalid score payload' USING ERRCODE='22023';END IF;END LOOP;
 IF p_session_id IS NULL THEN
  IF p_patch->>'scenario_type' IS NULL OR p_patch->>'scenario_type' !~ '^[a-z][a-z0-9_]{1,79}$' THEN RAISE EXCEPTION 'Invalid scenario' USING ERRCODE='22023';END IF;
  INSERT INTO tj.ai_roleplay_sessions(organization_id,user_id,scenario_type,transcript,kpi_scores,status) VALUES(org,actor,p_patch->>'scenario_type',new_transcript,coalesce(p_patch->'kpi_scores','{}'),'active') RETURNING * INTO sess;
 ELSE
  UPDATE tj.ai_roleplay_sessions SET transcript=new_transcript,total_turns=coalesce((p_patch->>'total_turns')::integer,total_turns),status=coalesce(p_patch->>'status',status),session_score=CASE WHEN p_patch?'session_score' THEN (p_patch->>'session_score')::numeric ELSE session_score END,kpi_scores=coalesce(p_patch->'kpi_scores',kpi_scores),feedback=coalesce(p_patch->>'feedback',feedback),scoring_breakdown=coalesce(p_patch->'scoring_breakdown',scoring_breakdown),coach_summary=coalesce(p_patch->'coach_summary',coach_summary),scoring_version=coalesce(p_patch->>'scoring_version',scoring_version),completed_at=CASE WHEN p_patch->>'status'='completed' THEN now() ELSE completed_at END WHERE id=sess.id RETURNING * INTO sess;
 END IF;
 INSERT INTO tj.ai_audit_events(organization_id,event_type,event_payload) VALUES(org,CASE WHEN sess.status='completed' THEN 'crm.roleplay.completed' ELSE 'crm.roleplay.saved' END,jsonb_build_object('session_id',sess.id,'source_actor',actor,'session_score',sess.session_score,'turns',sess.total_turns));
 RETURN jsonb_build_object('id',sess.id,'status',sess.status,'total_turns',sess.total_turns);
END $$;
REVOKE ALL ON FUNCTION tj_private.commit_roleplay_session(uuid,uuid,uuid,jsonb,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj_private.commit_roleplay_session(uuid,uuid,uuid,jsonb,jsonb) TO service_role;
CREATE FUNCTION public.aiq_commit_roleplay_session(p_native_user uuid,p_session_id uuid,p_organization_id uuid,p_expected_transcript jsonb,p_patch jsonb) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.commit_roleplay_session(p_native_user,p_session_id,p_organization_id,p_expected_transcript,p_patch);$$;
REVOKE ALL ON FUNCTION public.aiq_commit_roleplay_session(uuid,uuid,uuid,jsonb,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.aiq_commit_roleplay_session(uuid,uuid,uuid,jsonb,jsonb) TO service_role;
NOTIFY pgrst,'reload schema';
