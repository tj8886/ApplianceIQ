-- No subscription endpoints/keys or notification content read. Delivery remains blocked.
create function tj_private.push_delivery_preflight(p_body jsonb) returns jsonb
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
 if action not in ('status','send') then raise exception using errcode='22023',message='invalid_action';end if;
 -- Active tenant administration alone is not recipient eligibility or delivery verification.
 return jsonb_build_object('ok',action='status','error',case when action<>'status' then 'push_delivery_verification_required' else null end,
  'organization_id',org,'preflight_only',true,'push_enabled',false,'recipient_selection_enabled',false,'provider_verified',false,'scheduler_enabled',false,'executed',false,'attempted',0,'sent',0,'delivery_attempts_created',0,'subscriptions_updated',0,'notifications_updated',0,
  'blockers',jsonb_build_array('tenant_owned_notification_subscription_attempt_schema_required','verified_destination_vapid_and_subscription_registration_required','notification_recipient_org_and_app_exact_match_required','active_recipient_membership_and_consent_required','strict_endpoint_key_expiry_revocation_and_safe_action_url_rules_required','bounded_atomic_delivery_claims_and_idempotency_required','truthful_aggregate_delivery_result_and_expiry_reconciliation_required'));

end $$;
revoke all on function tj_private.push_delivery_preflight(jsonb) from public,anon,service_role;
grant execute on function tj_private.push_delivery_preflight(jsonb) to authenticated;
create function public.tj_push_delivery_preflight(p_body jsonb) returns jsonb language sql security invoker set search_path='' as $$select tj_private.push_delivery_preflight(p_body);$$;
revoke all on function public.tj_push_delivery_preflight(jsonb) from public,anon,service_role;
grant execute on function public.tj_push_delivery_preflight(jsonb) to authenticated;
notify pgrst,'reload schema';
