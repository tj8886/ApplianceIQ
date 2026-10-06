-- Readiness only: no global or cross-tenant selection and no scrape/product writes.
create function tj_private.product_video_preflight(p_body jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=tj_private.current_source_user_id();org uuid;action text;
begin
 if actor is null then raise exception using errcode='42501',message='product_access_denied';end if;
 if jsonb_typeof(p_body) is distinct from 'object' or octet_length(p_body::text)>8192
  or exists(select 1 from jsonb_object_keys(p_body)k where k not in ('organization_id','action'))
  or exists(select 1 from jsonb_each(p_body)e where jsonb_typeof(e.value)<>'string') then raise exception using errcode='22023',message='invalid_request';end if;
 org:=(p_body->>'organization_id')::uuid;
 if org is null or not exists(select 1 from tj.organization_members m join tj.organizations o on o.id=m.organization_id
  where o.id=org and o.status='active' and o.deleted_at is null and m.user_id=actor and m.status='active' and m.role in ('owner','admin','super_admin')) then raise exception using errcode='42501',message='product_access_denied';end if;
 action:=coalesce(p_body->>'action','run');
 if action not in ('status','run') then raise exception using errcode='22023',message='invalid_action';end if;
 -- Tenant admin readiness does not confer global publishing authority or assert product provenance.
 return jsonb_build_object('ok',action='status','error',case when action<>'status' then 'product_video_verification_required' else null end,
  'organization_id',org,'preflight_only',true,'discovery_enabled',false,'scraping_enabled',false,'worker_enabled',false,'global_publishing_enabled',false,'scheduler_enabled',false,'executed',false,'provider_requests',0,'jobs_processed',0,'jobs_claimed',0,'videos_created',0,
  'blockers',jsonb_build_array('tenant_scoped_job_product_and_video_ownership_required','reviewed_least_privilege_worker_authority_required','approved_source_origins_redirects_and_bounded_fetch_required','exact_model_variant_region_and_video_provenance_required','strict_video_platform_host_id_and_safe_embed_validation_required','atomic_job_claims_retries_and_video_finalization_required','truthful_partial_failure_reconciliation_and_deduplication_required','reviewed_scheduling_and_source_rate_limits_required'));

end $$;
revoke all on function tj_private.product_video_preflight(jsonb) from public,anon,service_role;
grant execute on function tj_private.product_video_preflight(jsonb) to authenticated;
create function public.tj_product_video_preflight(p_body jsonb) returns jsonb language sql security invoker set search_path='' as $$select tj_private.product_video_preflight(p_body);$$;
revoke all on function public.tj_product_video_preflight(jsonb) from public,anon,service_role;
grant execute on function public.tj_product_video_preflight(jsonb) to authenticated;
notify pgrst,'reload schema';
