-- Visit/client/store scope and media linkage only; no storage access or detection writes.
create function tj_private.field_photo_preflight(p_body jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=tj_private.current_source_user_id();org uuid;v record;m record;mode text;eligible boolean;
begin
 if actor is null then raise exception using errcode='42501',message='photo_access_denied';end if;
 if jsonb_typeof(p_body) is distinct from 'object' or octet_length(p_body::text)>8192
  or exists(select 1 from jsonb_object_keys(p_body)k where k not in ('organization_id','visit_id','media_id','mode'))
  or exists(select 1 from jsonb_each(p_body)e where jsonb_typeof(e.value)<>'string') then raise exception using errcode='22023',message='invalid_request';end if;
 select id,client_id,store_id,rep_user_id into v from tj.field_visits where id=(p_body->>'visit_id')::uuid;
 select c.organization_id into org from tj.field_clients c where c.id=v.client_id;
 if v.id is null or org is null or not tj_private.can_read_field_record(v.client_id,v.store_id,v.rep_user_id)
  or not exists(select 1 from tj.organization_members n where n.organization_id=org and n.user_id=actor and n.status='active'
   and (v.rep_user_id=actor or n.role in ('owner','admin','super_admin')))
  or (p_body ? 'organization_id' and (p_body->>'organization_id')::uuid<>org) then raise exception using errcode='42501',message='photo_access_denied';end if;
 select id,media_type,mime_type,file_size,ai_processed into m from tj.field_media where id=(p_body->>'media_id')::uuid and visit_id=v.id;
 if m.id is null then raise exception using errcode='42501',message='photo_access_denied';end if;
 mode:=coalesce(p_body->>'mode','analyze');
 if mode not in ('status','analyze') then raise exception using errcode='22023',message='invalid_mode';end if;
 eligible:=coalesce(m.media_type='photo' and m.mime_type in ('image/jpeg','image/png','image/webp') and m.file_size between 1 and 10485760,false);
 return jsonb_build_object('ok',mode='status','error',case when mode<>'status' then case when eligible then 'field_photo_verification_required' else 'photo_metadata_not_eligible' end else null end,
  'organization_id',org,'visit_id',v.id,'media_id',m.id,'preflight_only',true,'executed',false,'analysis_enabled',false,'mock_writes_enabled',false,
  'metadata_eligible',eligible,'storage_verified',false,'recorded_processed',coalesce(m.ai_processed,false),'detections_created',0,
  'blockers',jsonb_build_array('destination_storage_object_ownership_and_scan_required','verified_image_type_size_and_pixel_bounds_required','photo_processing_privacy_and_authority_required','tier_model_provider_and_cost_governance_required','validated_evidence_based_detections_without_mock_fallback_required','atomic_idempotent_result_finalization_required'));
end $$;
revoke all on function tj_private.field_photo_preflight(jsonb) from public,anon,service_role;
grant execute on function tj_private.field_photo_preflight(jsonb) to authenticated;
create function public.tj_field_photo_preflight(p_body jsonb) returns jsonb language sql security invoker set search_path='' as $$select tj_private.field_photo_preflight(p_body);$$;
revoke all on function public.tj_field_photo_preflight(jsonb) from public,anon,service_role;
grant execute on function public.tj_field_photo_preflight(jsonb) to authenticated;
notify pgrst,'reload schema';
