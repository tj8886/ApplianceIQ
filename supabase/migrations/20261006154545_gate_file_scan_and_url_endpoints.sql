-- Source and destination both lack file registry/access/nonce schema. Never infer file ownership.
create function tj_private.file_governance_preflight(p_kind text,p_body jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=tj_private.current_source_user_id();org uuid;action text;
begin
 if actor is null then raise exception using errcode='42501',message='file_access_denied';end if;
 if jsonb_typeof(p_body) is distinct from 'object' or octet_length(p_body::text)>8192
  or exists(select 1 from jsonb_object_keys(p_body)k where k not in ('organization_id','action'))
  or exists(select 1 from jsonb_each(p_body)e where jsonb_typeof(e.value)<>'string') then raise exception using errcode='22023',message='invalid_request';end if;
 org:=(p_body->>'organization_id')::uuid;
 if org is null or not exists(select 1 from tj.organization_members m join tj.organizations o on o.id=m.organization_id
  where o.id=org and o.status='active' and o.deleted_at is null and m.user_id=actor and m.status='active' and m.role in ('owner','admin','super_admin')) then raise exception using errcode='42501',message='file_access_denied';end if;
 if p_kind is null or p_kind not in ('scanner','signed_url') then raise exception using errcode='22023',message='invalid_kind';end if;
 action:=coalesce(p_body->>'action',case when p_kind='scanner' then 'scan' else 'mint' end);
 if action<>'status' and action<>(case when p_kind='scanner' then 'scan' else 'mint' end) then raise exception using errcode='22023',message='invalid_action';end if;
 return jsonb_build_object('ok',action='status','error',case when action<>'status' then 'file_governance_verification_required' else null end,
  'organization_id',org,'kind',p_kind,'preflight_only',true,'executed',false,'scan_enabled',false,'url_issuance_enabled',false,'scheduler_enabled',false,
  'storage_verified',false,'files_processed',0,'nonces_consumed',0,'urls_issued',0,
  'blockers',jsonb_build_array('tenant_owned_file_registry_and_access_schema_required','destination_object_and_bucket_ownership_verification_required','authorized_file_owner_and_visibility_contract_required','trusted_malware_scan_and_quarantine_evidence_required','immutable_object_version_and_atomic_scan_finalization_required')
   ||case when p_kind='signed_url' then jsonb_build_array('actor_org_file_version_bound_one_use_nonce_required','clean_scan_revalidation_at_url_issuance_required','purpose_ttl_and_atomic_access_audit_contract_required')
   else jsonb_build_array('bounded_least_privilege_scan_claim_and_retry_contract_required') end);
end $$;
revoke all on function tj_private.file_governance_preflight(text,jsonb) from public,anon,service_role;
grant execute on function tj_private.file_governance_preflight(text,jsonb) to authenticated;
create function public.tj_file_scan_preflight(p_body jsonb) returns jsonb language sql security invoker set search_path='' as $$select tj_private.file_governance_preflight('scanner',p_body);$$;
create function public.tj_file_url_preflight(p_body jsonb) returns jsonb language sql security invoker set search_path='' as $$select tj_private.file_governance_preflight('signed_url',p_body);$$;
revoke all on function public.tj_file_scan_preflight(jsonb),public.tj_file_url_preflight(jsonb) from public,anon,service_role;
grant execute on function public.tj_file_scan_preflight(jsonb),public.tj_file_url_preflight(jsonb) to authenticated;
notify pgrst,'reload schema';
