-- Product IQ does not rely on the legacy boolean mfr_user_roles.is_admin.
begin;

drop policy if exists "admin write vendors" on public.mfr_vendors;
create policy "product iq platform manages vendors" on public.mfr_vendors
  for all to authenticated
  using ((select private.product_iq_is_platform_admin()))
  with check ((select private.product_iq_is_platform_admin()));

commit;
