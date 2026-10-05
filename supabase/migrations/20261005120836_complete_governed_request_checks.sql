CREATE OR REPLACE FUNCTION tj_private.ai_submit_request(p_organization_id uuid DEFAULT NULL::uuid, p_assistant_key text DEFAULT NULL::text, p_prompt text DEFAULT NULL::text, p_context jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid := tj_private.current_source_user_id();
  v_org uuid;
  v_assistant tj.ai_assistants%rowtype;
  v_session uuid;
  v_request uuid;
  v_grounded jsonb;
  v_action uuid;
begin
  if v_user is null then
    raise exception 'Authentication required.' USING ERRCODE='42501';
  end if;
  if p_assistant_key is null or length(p_assistant_key)>120 or coalesce(length(trim(p_prompt)),0) NOT BETWEEN 3 AND 16000 OR jsonb_typeof(p_context) IS DISTINCT FROM 'object' OR octet_length(p_context::text)>32000 then
    raise exception 'Invalid request payload.' USING ERRCODE='22023';
  end if;

  if p_organization_id is not null then
    if not tj_private.can_read_runtime_org(p_organization_id) then
      raise exception 'Access denied for organization.' USING ERRCODE='42501';
    end if;
    v_org := p_organization_id;
  else
    select organization_id into v_org
      from tj.organization_members
     where user_id = v_user and status = 'active' AND tj_private.can_read_runtime_org(organization_id)
     order by created_at limit 1;
    if v_org is null then
      raise exception 'Access denied: no active organization membership.';
    end if;
  end if;

  IF v_org IS NULL OR NOT tj_private.can_read_runtime_org(v_org) THEN RAISE EXCEPTION 'Organization access denied' USING ERRCODE='42501'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('tj-ai-request:'||v_user::text,0));
  IF (SELECT count(*) FROM tj.ai_requests WHERE user_id=v_user AND created_at>now()-interval '1 minute')>=60 OR (SELECT count(*) FROM tj.ai_requests WHERE user_id=v_user AND created_at>now()-interval '1 hour')>=500 THEN RAISE EXCEPTION 'Request rate limit exceeded' USING ERRCODE='54000'; END IF;
  select * into v_assistant from tj.ai_assistants
   where assistant_key = p_assistant_key and status = 'active';
  if not found then
    raise exception 'Unknown or inactive assistant.';
  end if;
  if v_assistant.organization_id is not null and v_assistant.organization_id <> v_org then
    raise exception 'Access denied: assistant not available for this organization.';
  end if;

  IF v_assistant.required_feature_key IS NOT NULL OR v_assistant.required_entitlement_key IS NOT NULL OR v_assistant.required_permission_name IS NOT NULL THEN RAISE EXCEPTION 'Assistant entitlement checks are not enabled for this configuration' USING ERRCODE='42501'; END IF;
  insert into tj.ai_sessions (organization_id, user_id, assistant_key)
  values (v_org, v_user, p_assistant_key)
  returning id into v_session;

  v_grounded := jsonb_build_object(
    'record_counts', jsonb_build_object(
      'companies', (select count(*) from tj.companies c where c.organization_id = v_org),
      'contacts', (select count(*) from tj.contacts c where c.organization_id = v_org),
      'deals', (select count(*) from tj.crm_deals d where d.organization_id = v_org),
      'open_tasks', (select count(*) from tj.crm_tasks t where t.organization_id = v_org and t.completed_at is null),
      'products', (select count(*) from tj.products p where p.organization_id = v_org)
    ),
    'pipeline', (select coalesce(jsonb_object_agg(stage, cnt), '{}'::jsonb)
                 from (select stage, count(*) cnt from tj.crm_deals d
                       where d.organization_id = v_org and d.closed_at is null
                       group by stage) s),
    'generated_at', now()
  );

  insert into tj.ai_requests
    (organization_id, session_id, user_id, assistant_key, request_status, prompt, context, grounded_context,
     output, explanation, model_provider, model_name, completed_at)
  values
    (v_org, v_session, v_user, p_assistant_key, 'pending', p_prompt, coalesce(p_context,'{}'::jsonb), v_grounded,
     jsonb_build_object('mode','foundation','assistant_key',p_assistant_key,
       'notice','Governed request recorded. Model layer produces the final answer.'),
     'Foundation envelope: auth, tenancy, assistant visibility, grounded context, and audit recorded at the database layer.',
     'foundation','deterministic', NULL)
  returning id into v_request;

  if v_assistant.approval_required then
    insert into tj.ai_proposed_actions (organization_id, request_id, assistant_key, action_type, action_payload)
    values (v_org, v_request, p_assistant_key, 'advisory_output_review',
            jsonb_build_object('prompt_preview', left(p_prompt, 200)))
    returning id into v_action;
  end if;

  insert into tj.ai_audit_events (organization_id, request_id, assistant_key, event_type, event_payload)
  values (v_org, v_request, p_assistant_key, 'ai.request.submitted',
          jsonb_build_object('approval_required', v_assistant.approval_required));

  insert into tj.ai_usage_meter (organization_id, assistant_key, request_id, usage_kind, quantity, limit_key)
  values (v_org, p_assistant_key, v_request, 'request', 1, 'ai.requests.monthly');

  return jsonb_build_object(
    'request_id', v_request,
    'session_id', v_session,
    'organization_id', v_org,
    'approval_required', v_assistant.approval_required,
    'proposed_action_id', v_action,
    'output', (select output from tj.ai_requests where id = v_request)
  );
end $function$;


NOTIFY pgrst,'reload schema';
