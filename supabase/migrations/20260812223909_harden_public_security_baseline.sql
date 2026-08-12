begin;

alter table public.pim_image_requirements enable row level security;
alter table public.crm_replacement_cycles enable row level security;

revoke insert, update, delete, truncate, references, trigger on table public.pim_image_requirements from anon, authenticated;
revoke insert, update, delete, truncate, references, trigger on table public.crm_replacement_cycles from anon, authenticated;

drop policy if exists pim_image_requirements_read on public.pim_image_requirements;
create policy pim_image_requirements_read on public.pim_image_requirements
for select to anon, authenticated using (true);

drop policy if exists crm_replacement_cycles_read on public.crm_replacement_cycles;
create policy crm_replacement_cycles_read on public.crm_replacement_cycles
for select to anon, authenticated using (true);

alter view public.v_active_retailer_listings set (security_invoker = true);
alter view public.v_model_price_spread set (security_invoker = true);
alter view public.retailer_product_catalog set (security_invoker = true);

alter function public.fn_calc_savings() set search_path = public, pg_temp;
alter function public.lookup_product(text, text) set search_path = public, pg_temp;
alter function public.get_invite_preview(text) set search_path = public, pg_temp;
alter function public.sync_seats_used() set search_path = public, pg_temp;
alter function public.run_retention_cleanup() set search_path = public, pg_temp;

revoke execute on function public.sync_seats_used() from anon, authenticated;
revoke execute on function public.run_retention_cleanup() from anon, authenticated;
grant execute on function public.sync_seats_used() to service_role;
grant execute on function public.run_retention_cleanup() to service_role;

commit;
