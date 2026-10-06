-- MDF email/org IDs and imported Stripe references do not establish tenant identity or provider ownership.
create function tj_private.mdf_billing_preflight(p_body jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=tj_private.current_source_user_id();org uuid;action text;
begin
 if actor is null then raise exception using errcode='42501',message='payment_access_denied';end if;
 if jsonb_typeof(p_body) is distinct from 'object' or octet_length(p_body::text)>8192
  or exists(select 1 from jsonb_object_keys(p_body)k where k not in ('organization_id','action'))
  or exists(select 1 from jsonb_each(p_body)e where jsonb_typeof(e.value)<>'string') then raise exception using errcode='22023',message='invalid_request';end if;
 org:=(p_body->>'organization_id')::uuid;
 if org is null or not exists(select 1 from tj.organization_members m join tj.organizations o on o.id=m.organization_id
  where o.id=org and o.status='active' and o.deleted_at is null and m.user_id=actor and m.status='active' and m.role in ('owner','admin','super_admin')) then raise exception using errcode='42501',message='payment_access_denied';end if;
 action:=coalesce(p_body->>'action','status');
 if action not in ('status','get_status','create_checkout','billing_portal','webhook') then raise exception using errcode='22023',message='invalid_action';end if;
 -- No MDF lookup, usage count, price, entitlement or subscription assertion until explicit tenant/identity mapping is verified.
 return jsonb_build_object('ok',action in ('status','get_status'),'error',case when action not in ('status','get_status') then 'mdf_billing_verification_required' else null end,
  'organization_id',org,'preflight_only',true,'executed',false,'payment_enabled',false,'checkout_enabled',false,'subscription_enabled',false,'portal_enabled',false,'webhook_enabled',false,'processed',false,'recorded',false,'scheduler_enabled',false,
  'provider_verified',false,'payment_records_created',0,'provider_requests',0,
  'blockers',jsonb_build_array('mdf_explicit_core_tenant_mapping_required','mdf_verified_native_user_membership_required','tenant_scoped_usage_and_entitlements_required','stripe_destination_account_and_mode_verification_required','approved_server_prices_currency_tax_and_trial_policy_required','authorized_customer_subscription_ownership_required','raw_signed_webhook_account_and_event_verification_required','atomic_replay_receipts_and_subscription_reconciliation_required','idempotent_customer_price_and_checkout_operations_required','approved_app_return_origins_required'));
end $$;
revoke all on function tj_private.mdf_billing_preflight(jsonb) from public,anon,service_role;
grant execute on function tj_private.mdf_billing_preflight(jsonb) to authenticated;
create function public.tj_mdf_billing_preflight(p_body jsonb) returns jsonb language sql security invoker set search_path='' as $$select tj_private.mdf_billing_preflight(p_body);$$;
revoke all on function public.tj_mdf_billing_preflight(jsonb) from public,anon,service_role;
grant execute on function public.tj_mdf_billing_preflight(jsonb) to authenticated;
notify pgrst,'reload schema';
