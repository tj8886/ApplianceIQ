-- No legacy CHQ recipient, Stripe account or booking facts can establish tenant ownership.
create function tj_private.chq_payment_preflight(p_body jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=tj_private.current_source_user_id();org uuid;action text;
begin
 if actor is null then raise exception using errcode='42501',message='payment_access_denied';end if;
 if jsonb_typeof(p_body) is distinct from 'object' or octet_length(p_body::text)>8192
  or exists(select 1 from jsonb_object_keys(p_body)k where k not in ('organization_id','action','booking_id','contractor_id','tier'))
  or exists(select 1 from jsonb_each(p_body)e where jsonb_typeof(e.value)<>'string') then raise exception using errcode='22023',message='invalid_request';end if;
 org:=(p_body->>'organization_id')::uuid;
 if org is null or not exists(select 1 from tj.organization_members m join tj.organizations o on o.id=m.organization_id
  where o.id=org and o.status='active' and o.deleted_at is null and m.user_id=actor and m.status='active' and m.role in ('owner','admin','super_admin')) then raise exception using errcode='42501',message='payment_access_denied';end if;
 action:=coalesce(p_body->>'action','status');
 if action not in ('status','create_checkout','contractor_subscription','connect_onboarding','connect_status','process_payout','process_all_payouts') then raise exception using errcode='22023',message='invalid_action';end if;
 -- IDs and tiers are unused untrusted request metadata. No lookup, quote or eligibility assertion.
 return jsonb_build_object('ok',action='status','error',case when action<>'status' then 'chq_payment_verification_required' else null end,
  'organization_id',org,'preflight_only',true,'executed',false,'payment_enabled',false,'checkout_enabled',false,'subscription_enabled',false,'connect_enabled',false,'payout_enabled',false,'scheduler_enabled',false,
  'provider_verified',false,'payment_records_created',0,'provider_requests',0,
  'blockers',jsonb_build_array('chq_explicit_record_tenant_ownership_required','stripe_destination_account_and_mode_verification_required','server_authoritative_booking_price_and_currency_required','approved_prices_tax_and_payment_contract_required','verified_signed_webhook_and_payment_reconciliation_required','idempotent_payment_and_payout_ledger_required','authorized_customer_and_contractor_ownership_required','verified_connect_payee_and_payout_eligibility_required','approved_app_return_origins_required'));
end $$;
revoke all on function tj_private.chq_payment_preflight(jsonb) from public,anon,service_role;
grant execute on function tj_private.chq_payment_preflight(jsonb) to authenticated;
create function public.tj_chq_payment_preflight(p_body jsonb) returns jsonb language sql security invoker set search_path='' as $$select tj_private.chq_payment_preflight(p_body);$$;
revoke all on function public.tj_chq_payment_preflight(jsonb) from public,anon,service_role;
grant execute on function public.tj_chq_payment_preflight(jsonb) to authenticated;
notify pgrst,'reload schema';
