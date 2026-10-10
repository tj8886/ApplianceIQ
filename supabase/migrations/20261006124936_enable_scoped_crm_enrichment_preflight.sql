-- Read-only CRM enrichment readiness. No provider, mock, cache or job mutations.
create function tj_private.crm_enrichment_preflight(p_body jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=tj_private.current_source_user_id();org uuid;account uuid;job uuid;
 job_type text;provider text;job_status text;mock boolean;mode text;
 types text[]:=array['company_summary','executive_brief','product_fit','next_action','outreach_recommendation','full_account_intelligence','revenue_estimate','employee_estimate','category_classification','buying_group_detection','contact_role_recommendation','website_discovery','linkedin_discovery','duplicate_detection','score_explanation','next_action_recommendation','campaign_recommendation','full_account_enrichment'];
begin
 if actor is null then raise exception using errcode='42501',message='enrichment_access_denied';end if;
 if jsonb_typeof(p_body) is distinct from 'object' or octet_length(p_body::text)>8192
  or exists(select 1 from jsonb_object_keys(p_body)k where k not in ('mode','organization_id','account_id','existing_job_id','job_type','provider'))
  or exists(select 1 from jsonb_each(p_body)e where jsonb_typeof(e.value)<>'string') then raise exception using errcode='22023',message='invalid_request';end if;
 mode:=coalesce(p_body->>'mode','run');
 if mode not in ('run','retry','status','preflight') then raise exception using errcode='22023',message='invalid_mode';end if;
 job:=(p_body->>'existing_job_id')::uuid;
 if job is not null then
  select a.id,a.organization_id,j.job_type,j.provider,j.status,j.mock_mode into account,org,job_type,provider,job_status,mock
  from tj.aicrm_ai_enrichment_jobs j join tj.aicrm_accounts a on a.id=j.account_id and a.organization_id=j.organization_id where j.id=job;
 else
  select a.id,a.organization_id into account,org from tj.aicrm_accounts a where a.id=(p_body->>'account_id')::uuid;
  job_type:=p_body->>'job_type';provider:=p_body->>'provider';
 end if;
 if account is null or not exists(select 1 from tj.organizations o join tj.organization_members m on m.organization_id=o.id
  where o.id=org and o.status='active' and o.deleted_at is null and m.user_id=actor and m.status='active' and m.role in ('owner','admin','super_admin'))
  or (p_body ? 'organization_id' and (p_body->>'organization_id')::uuid<>org)
  or (p_body ? 'account_id' and (p_body->>'account_id')::uuid<>account) then raise exception using errcode='42501',message='enrichment_access_denied';end if;
 if job is not null and ((p_body ? 'job_type' and p_body->>'job_type' is distinct from job_type)
  or (p_body ? 'provider' and p_body->>'provider' is distinct from provider)) then raise exception using errcode='22023',message='job_context_mismatch';end if;
 if job_type is not null and not(job_type=any(types)) then raise exception using errcode='22023',message='unsupported_job_type';end if;
 if provider is not null and provider not in ('mock','anthropic') then raise exception using errcode='22023',message='unsupported_provider';end if;
 if mode in ('run','retry') and job_type is null then raise exception using errcode='22023',message='job_type_required';end if;
 if mode='retry' and job is null then raise exception using errcode='22023',message='existing_job_required';end if;
 if mode in ('run','retry') then
  return jsonb_build_object('ok',false,'error',case when job is not null and job_status is distinct from 'failed' then 'only_failed_jobs_can_retry' else 'crm_enrichment_verification_required' end,
   'executed',false,'enrichment_enabled',false,'mock_writes_enabled',false,'job_created',false,'organization_id',org,'account_id',account);
 end if;
 return jsonb_build_object('ok',true,'organization_id',org,'account_id',account,'preflight_only',true,'executed',false,'enrichment_enabled',false,'mock_writes_enabled',false,
  'job',case when job is not null then jsonb_build_object('id',job,'job_type',job_type,'provider',provider,'status',case when job_status in ('queued','running','completed','failed','cancelled','mock_completed') then job_status else 'unknown' end,'mock_mode',mock,'retry_eligible',job_status='failed') else null end,
  'research_recorded',exists(select 1 from tj.aicrm_ai_research r where r.account_id=account and r.organization_id=org),
  'dependencies',jsonb_build_array('tier_model_and_provider_verification','tenant_scoped_prompt_selection','evidence_and_output_validation','provider_failure_without_mock_fallback','atomic_idempotent_result_finalization','bounded_rate_limits_and_cost_governance'));
end $$;
revoke all on function tj_private.crm_enrichment_preflight(jsonb) from public,anon,service_role;
grant execute on function tj_private.crm_enrichment_preflight(jsonb) to authenticated;
create function public.tj_crm_enrichment_preflight(p_body jsonb) returns jsonb language sql security invoker set search_path='' as $$select tj_private.crm_enrichment_preflight(p_body);$$;
revoke all on function public.tj_crm_enrichment_preflight(jsonb) from public,anon,service_role;
grant execute on function public.tj_crm_enrichment_preflight(jsonb) to authenticated;
notify pgrst,'reload schema';
