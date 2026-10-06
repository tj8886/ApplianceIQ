-- MDF queue has no tenant ownership; do not select recipients, send messages or run global expiry functions.
create function tj_private.mdf_email_preflight(p_body jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=tj_private.current_source_user_id();org uuid;action text;
begin
 if actor is null then raise exception using errcode='42501',message='notification_access_denied';end if;
 if jsonb_typeof(p_body) is distinct from 'object' or octet_length(p_body::text)>8192
  or exists(select 1 from jsonb_object_keys(p_body)k where k not in ('organization_id','action'))
  or exists(select 1 from jsonb_each(p_body)e where jsonb_typeof(e.value)<>'string') then raise exception using errcode='22023',message='invalid_request';end if;
 org:=(p_body->>'organization_id')::uuid;
 if org is null or not exists(select 1 from tj.organization_members m join tj.organizations o on o.id=m.organization_id
  where o.id=org and o.status='active' and o.deleted_at is null and m.user_id=actor and m.status='active' and m.role in ('owner','admin','super_admin')) then raise exception using errcode='42501',message='notification_access_denied';end if;
 action:=coalesce(p_body->>'action','send');
 if action not in ('status','test','send','send_test','process_queue','check_expiry') then raise exception using errcode='22023',message='invalid_action';end if;
 -- Readiness is not a delivery test or provider/credential assertion; no recipient/body/queue lookup.
 return jsonb_build_object('ok',action in ('status','test'),'error',case when action not in ('status','test') then 'mdf_email_verification_required' else null end,
  'organization_id',org,'preflight_only',true,'notification_enabled',false,'recipient_selection_enabled',false,'queue_processing_enabled',false,'expiry_updates_enabled',false,'scheduler_enabled',false,
  'provider_verified',false,'delivery_verified',false,'executed',false,'sent',0,'processed',0,'queued',0,'delivery_attempts',0,'notification_records_created',0,'expiry_alerts_created',0,'funds_expired',0,
  'blockers',jsonb_build_array('mdf_explicit_core_tenant_and_native_membership_mapping_required','queue_and_related_records_explicit_tenant_ownership_required','authorized_events_and_recipient_eligibility_required','verified_destination_sender_and_provider_required','escaped_templates_and_approved_app_links_required','atomic_outbox_claims_provider_idempotency_and_result_reconciliation_required','bounded_retry_dead_letter_and_privacy_controls_required','tenant_scoped_atomic_expiry_alerts_and_date_rules_required','reviewed_worker_identity_and_schedule_required'));

end $$;
revoke all on function tj_private.mdf_email_preflight(jsonb) from public,anon,service_role;
grant execute on function tj_private.mdf_email_preflight(jsonb) to authenticated;
create function public.tj_mdf_email_preflight(p_body jsonb) returns jsonb language sql security invoker set search_path='' as $$select tj_private.mdf_email_preflight(p_body);$$;
revoke all on function public.tj_mdf_email_preflight(jsonb) from public,anon,service_role;
grant execute on function public.tj_mdf_email_preflight(jsonb) to authenticated;
notify pgrst,'reload schema';
