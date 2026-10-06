-- Tenant-admin readiness does not authorize database-wide DDL export. No catalog/DDL snapshot read.
create function tj_private.schema_export_preflight(p_body jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=tj_private.current_source_user_id();org uuid;action text;
begin
 if actor is null then raise exception using errcode='42501',message='schema_export_access_denied';end if;
 if jsonb_typeof(p_body) is distinct from 'object' or octet_length(p_body::text)>8192
  or exists(select 1 from jsonb_object_keys(p_body)k where k not in ('organization_id','action'))
  or exists(select 1 from jsonb_each(p_body)e where jsonb_typeof(e.value)<>'string') then raise exception using errcode='22023',message='invalid_request';end if;
 org:=(p_body->>'organization_id')::uuid;
 if org is null or not exists(select 1 from tj.organization_members m join tj.organizations o on o.id=m.organization_id
  where o.id=org and o.status='active' and o.deleted_at is null and m.user_id=actor and m.status='active' and m.role in ('owner','admin','super_admin')) then raise exception using errcode='42501',message='schema_export_access_denied';end if;
 action:=coalesce(p_body->>'action','export');
 if action not in ('status','export') then raise exception using errcode='22023',message='invalid_action';end if;
 -- No fixed URL key, historical counts or incomplete snapshots confer operator/export authority.
 return jsonb_build_object('ok',action='status','error',case when action<>'status' then 'schema_export_verification_required' else null end,
  'organization_id',org,'preflight_only',true,'export_enabled',false,'operator_authority_verified',false,'snapshot_verified',false,'scheduler_enabled',false,'executed',false,'ddl_sections_read',0,'bytes_exported',0,'download_created',false,
  'blockers',jsonb_build_array('verified_destination_database_operator_authority_required','approved_schema_scope_and_private_metadata_redaction_required','complete_live_catalog_or_verified_snapshot_source_required','dependency_ordered_schema_export_and_manifest_required','fail_closed_section_integrity_and_bounded_artifact_required','restore_test_and_versioned_backup_validation_required'));

end $$;
revoke all on function tj_private.schema_export_preflight(jsonb) from public,anon,service_role;
grant execute on function tj_private.schema_export_preflight(jsonb) to authenticated;
create function public.tj_schema_export_preflight(p_body jsonb) returns jsonb language sql security invoker set search_path='' as $$select tj_private.schema_export_preflight(p_body);$$;
revoke all on function public.tj_schema_export_preflight(jsonb) from public,anon,service_role;
grant execute on function public.tj_schema_export_preflight(jsonb) to authenticated;
notify pgrst,'reload schema';
