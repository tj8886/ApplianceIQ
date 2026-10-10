-- Imported platform roles alone do not authorize governance execution; readiness only.
create function tj_private.product_governance_preflight(p_body jsonb) returns jsonb
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
 action:=coalesce(p_body->>'action','status');
 if action not in ('status','search_relationship_products','create_product','update_product','validate_product','update_specifications','create_product_relationship','update_product_relationship','archive_product_relationship','restore_product_relationship','update_document_metadata','archive_document','restore_document','update_image_metadata','set_primary_image','archive_image','restore_image','reorder_images') then raise exception using errcode='22023',message='invalid_action';end if;
 -- Tenant admin readiness does not confer global publishing authority or assert product provenance.
 return jsonb_build_object('ok',action='status','error',case when action<>'status' then 'product_governance_verification_required' else null end,
  'organization_id',org,'preflight_only',true,'governance_enabled',false,'editing_enabled',false,'validation_enabled',false,'search_enabled',false,'global_publishing_enabled',false,'scheduler_enabled',false,'executed',false,'provider_requests',0,'products_processed',0,'products_updated',0,'audit_records_created',0,'related_records_updated',0,
  'blockers',jsonb_build_array('verified_destination_platform_role_and_brand_scope_required','missing_tenant_owned_spec_document_asset_relationship_quality_schema_required','explicit_edit_review_and_publish_transition_authority_required','strict_typed_field_unit_and_evidence_validation_required','atomic_version_guarded_product_and_related_record_transaction_required','atomic_immutable_audit_and_idempotency_required','bounded_tenant_scoped_search_and_private_metadata_rules_required'));

end $$;
revoke all on function tj_private.product_governance_preflight(jsonb) from public,anon,service_role;
grant execute on function tj_private.product_governance_preflight(jsonb) to authenticated;
create function public.tj_product_governance_preflight(p_body jsonb) returns jsonb language sql security invoker set search_path='' as $$select tj_private.product_governance_preflight(p_body);$$;
revoke all on function public.tj_product_governance_preflight(jsonb) from public,anon,service_role;
grant execute on function public.tj_product_governance_preflight(jsonb) to authenticated;
notify pgrst,'reload schema';
