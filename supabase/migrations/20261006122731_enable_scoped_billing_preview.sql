-- Read-only entitlement preview. No Stripe calls or financial mutations.
create function tj_private.billing_preview(p_body jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=tj_private.current_source_user_id();org tj.organizations%rowtype;act text;items jsonb;total bigint;valid boolean;currency text;
begin
 if actor is null then raise exception using errcode='42501',message='billing_access_denied';end if;
 if jsonb_typeof(p_body) is distinct from 'object' or octet_length(p_body::text)>8192
  or exists(select 1 from jsonb_object_keys(p_body)k where k not in ('action','organization_id','success_url','cancel_url','return_url')) then raise exception using errcode='22023',message='invalid_request';end if;
 select * into org from tj.organizations where id=(p_body->>'organization_id')::uuid;
 if org.id is null or org.status<>'active' or org.deleted_at is not null or not exists(select 1 from tj.organization_members m
  where m.organization_id=org.id and m.user_id=actor and m.status='active' and m.role in ('owner','admin','super_admin')) then raise exception using errcode='42501',message='billing_access_denied';end if;
 act:=coalesce(p_body->>'action','status');
 if act in ('create_checkout','create_portal','sync_subscription') then
  return jsonb_build_object('ok',false,'error','stripe_destination_verification_required','billing_enabled',false,'configured',false,'synced',false,'executed',false);
 elsif act not in ('status','preview') then raise exception using errcode='22023',message='unknown_action';end if;
 currency:=lower(org.billing_currency);
 select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'app_key',left(e.app_key,128),'tier',left(e.tier,128),'seats_included',e.seats_included,'seats_used',e.seats_used,'price_cents_monthly',e.price_cents_monthly) order by e.id),'[]'),
  coalesce(sum(e.price_cents_monthly::bigint),0),coalesce(bool_and(e.price_cents_monthly is not null and e.price_cents_monthly>=0),true)
 into items,total,valid from (select * from tj.org_app_entitlements where organization_id=org.id and status='active' and canceled_at is null order by id limit 101)e;
 if jsonb_array_length(items)>100 then raise exception using errcode='54000',message='too_many_entitlements';end if;
 valid:=valid and coalesce(currency in ('cad','usd'),false);
 return jsonb_build_object('ok',true,'organization_id',org.id,'preview_only',true,'configured',false,'billing_enabled',false,'checkout_enabled',false,'portal_enabled',false,'subscription_updates_enabled',false,'synced',false,'executed',false,
  'customer_link_recorded',org.stripe_customer_id is not null,'subscription_link_recorded',org.stripe_subscription_id is not null,
  'pricing_valid',valid,'currency',case when currency in ('cad','usd') then currency else null end,'monthly_cents',case when valid then total else null end,
  'items',jsonb_array_length(items),'entitlements',items,'amount_basis','recorded_entitlements_before_tax','stripe_verified',false,
  'dependencies',jsonb_build_array('stripe_account_and_mode_verification','destination_webhook_verification','approved_prices_and_subscription_contract','idempotent_billing_adapter'));
end $$;
revoke all on function tj_private.billing_preview(jsonb) from public,anon,service_role;
grant execute on function tj_private.billing_preview(jsonb) to authenticated;
create function public.tj_billing_preview(p_body jsonb) returns jsonb language sql security invoker set search_path='' as $$select tj_private.billing_preview(p_body);$$;
revoke all on function public.tj_billing_preview(jsonb) from public,anon,service_role;
grant execute on function public.tj_billing_preview(jsonb) to authenticated;
notify pgrst,'reload schema';
