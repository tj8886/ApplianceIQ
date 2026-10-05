CREATE FUNCTION tj_private.ai_request_context(p_request_id uuid,p_template_key text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=tj_private.current_source_user_id(); r tj.ai_requests%rowtype; a tj.ai_assistants%rowtype; chunks jsonb; template jsonb;BEGIN
 SELECT * INTO r FROM tj.ai_requests WHERE id=p_request_id AND user_id=actor;
 IF actor IS NULL OR NOT FOUND OR NOT tj_private.can_read_runtime_org(r.organization_id) THEN RAISE EXCEPTION 'Request access denied' USING ERRCODE='42501';END IF;
 IF r.request_status<>'pending' THEN RAISE EXCEPTION 'Request already finalized' USING ERRCODE='40001';END IF;
 SELECT * INTO a FROM tj.ai_assistants WHERE assistant_key=r.assistant_key AND status='active' AND (organization_id IS NULL OR organization_id=r.organization_id);
 IF NOT FOUND OR a.required_feature_key IS NOT NULL OR a.required_entitlement_key IS NOT NULL OR a.required_permission_name IS NOT NULL THEN RAISE EXCEPTION 'Assistant access denied' USING ERRCODE='42501';END IF;
 SELECT coalesce(jsonb_agg(q.row),'[]') INTO chunks FROM (
  SELECT jsonb_build_object('chunk_key',k.chunk_key,'title',k.title,'content',left(k.content,12000),'citation',k.citation,'score',(SELECT count(*) FROM (SELECT DISTINCT term FROM regexp_split_to_table(lower(r.prompt),'[^a-z0-9]+') term WHERE length(term)>3) terms WHERE position(term IN lower(coalesce(k.title,'')||' '||coalesce(k.content,'')))>0)) AS row
  FROM tj.ai_knowledge_chunks k WHERE k.status='active' AND k.visibility='global' AND (k.organization_id IS NULL OR k.organization_id=r.organization_id)
  ORDER BY (SELECT count(*) FROM (SELECT DISTINCT term FROM regexp_split_to_table(lower(r.prompt),'[^a-z0-9]+') term WHERE length(term)>3) terms WHERE position(term IN lower(coalesce(k.title,'')||' '||coalesce(k.content,'')))>0) DESC,k.id LIMIT 12
 ) q;
 IF p_template_key IS NOT NULL THEN
  IF length(p_template_key)>120 THEN RAISE EXCEPTION 'Invalid template' USING ERRCODE='22023';END IF;
  SELECT jsonb_build_object('system_prompt',system_prompt,'user_prompt_template',user_prompt_template,'tone_guidance',tone_guidance,'output_schema',output_schema) INTO template FROM tj.ai_prompt_templates WHERE template_key=p_template_key AND status='active' AND (organization_id IS NULL OR organization_id=r.organization_id) ORDER BY organization_id NULLS LAST,version DESC LIMIT 1;
 END IF;
 RETURN jsonb_build_object('assistant',jsonb_build_object('assistant_key',a.assistant_key,'label',a.label,'category',a.category,'description',a.description,'retrieval_scopes',a.retrieval_scopes,'safety_controls',a.safety_controls,'response_contract',a.response_contract,'config',a.config,'approval_required',a.approval_required),'knowledge',chunks,'template',template,'grounded_context',r.grounded_context);
END $$;
REVOKE ALL ON FUNCTION tj_private.ai_request_context(uuid,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION tj_private.ai_request_context(uuid,text) TO authenticated;
CREATE FUNCTION public.tj_ai_request_context(p_request_id uuid,p_template_key text DEFAULT NULL) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$SELECT tj_private.ai_request_context(p_request_id,p_template_key);$$;
REVOKE ALL ON FUNCTION public.tj_ai_request_context(uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.tj_ai_request_context(uuid,text) TO authenticated;
CREATE FUNCTION tj_private.finish_ai_request(p_request_id uuid,p_target_user_id uuid,p_output jsonb,p_provider text,p_model text,p_tokens integer DEFAULT 0,p_error text DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; r tj.ai_requests%rowtype;BEGIN
 IF current_setting('role',true)<>'service_role' THEN RAISE EXCEPTION 'Service role required' USING ERRCODE='42501';END IF;
 SELECT CASE WHEN count(*)=1 THEN min(m.source_user_id::text)::uuid END INTO actor FROM tj.source_user_identity_map m JOIN tj.source_auth_users s ON s.id=m.source_user_id JOIN auth.users u ON u.id=m.target_user_id WHERE m.target_user_id=p_target_user_id AND m.identity_verified AND m.mapping_status IN ('approved_map','approved_create','approved_invite') AND m.approved_at IS NOT NULL AND nullif(btrim(m.approved_by),'') IS NOT NULL AND m.activation_status='activated' AND m.activated_at IS NOT NULL AND s.deleted_at IS NULL AND u.deleted_at IS NULL AND (s.banned_until IS NULL OR s.banned_until<=now()) AND (u.banned_until IS NULL OR u.banned_until<=now()) AND NOT coalesce(s.is_anonymous,false) AND NOT coalesce(u.is_anonymous,false);
 SELECT * INTO r FROM tj.ai_requests WHERE id=p_request_id AND user_id=actor FOR UPDATE;
 IF actor IS NULL OR NOT FOUND OR NOT EXISTS(SELECT 1 FROM tj.organizations o WHERE o.id=r.organization_id AND o.status='active' AND o.deleted_at IS NULL) OR NOT (EXISTS(SELECT 1 FROM tj.organization_members m WHERE m.organization_id=r.organization_id AND m.user_id=actor AND m.status='active') OR EXISTS(SELECT 1 FROM tj.platform_admins WHERE user_id=actor)) THEN RAISE EXCEPTION 'Request access denied' USING ERRCODE='42501';END IF;
 IF r.request_status<>'pending' THEN RAISE EXCEPTION 'Request already finalized' USING ERRCODE='40001';END IF;
 IF jsonb_typeof(p_output) IS DISTINCT FROM 'object' OR octet_length(p_output::text)>200000 OR p_tokens IS NULL OR p_tokens NOT BETWEEN 0 AND 1000000 OR length(p_provider)>40 OR length(p_model)>120 OR length(p_error)>500 THEN RAISE EXCEPTION 'Invalid completion payload' USING ERRCODE='22023';END IF;
 UPDATE tj.ai_requests SET request_status=CASE WHEN p_error IS NULL THEN 'completed' ELSE 'failed' END,output=p_output,model_provider=p_provider,model_name=p_model,token_estimate=p_tokens,error_message=p_error,completed_at=now(),explanation='Advisory model response over verified tenant context; no operational action executed.' WHERE id=r.id;
 INSERT INTO tj.ai_audit_events(organization_id,request_id,assistant_key,event_type,event_status,event_payload) VALUES(r.organization_id,r.id,r.assistant_key,CASE WHEN p_error IS NULL THEN 'ai.model.response_generated' ELSE 'ai.model.call_failed' END,CASE WHEN p_error IS NULL THEN 'recorded' ELSE 'error' END,jsonb_build_object('provider',p_provider,'model',p_model,'tokens',p_tokens));
 IF p_tokens>0 THEN INSERT INTO tj.ai_usage_meter(organization_id,assistant_key,request_id,usage_kind,quantity,limit_key) VALUES(r.organization_id,r.assistant_key,r.id,'token',p_tokens,'ai.tokens.monthly');END IF;
 RETURN jsonb_build_object('request_id',r.id,'completed',p_error IS NULL);
END $$;
REVOKE ALL ON FUNCTION tj_private.finish_ai_request(uuid,uuid,jsonb,text,text,integer,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj_private.finish_ai_request(uuid,uuid,jsonb,text,text,integer,text) TO service_role;
CREATE FUNCTION public.aiq_finish_ai_request(p_request_id uuid,p_target_user_id uuid,p_output jsonb,p_provider text,p_model text,p_tokens integer DEFAULT 0,p_error text DEFAULT NULL) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$SELECT tj_private.finish_ai_request(p_request_id,p_target_user_id,p_output,p_provider,p_model,p_tokens,p_error);$$;
REVOKE ALL ON FUNCTION public.aiq_finish_ai_request(uuid,uuid,jsonb,text,text,integer,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.aiq_finish_ai_request(uuid,uuid,jsonb,text,text,integer,text) TO service_role;
NOTIFY pgrst,'reload schema';
