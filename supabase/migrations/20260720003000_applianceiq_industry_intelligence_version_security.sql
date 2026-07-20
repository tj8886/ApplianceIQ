-- ApplianceIQ AIQ version-table RLS hardening.
-- Additive security fix for version tables queried by the frontend.

alter table public.aiq_product_versions enable row level security;
alter table public.aiq_product_specification_versions enable row level security;
alter table public.aiq_document_versions enable row level security;
alter table public.aiq_competitive_comparison_versions enable row level security;
alter table public.aiq_product_training_asset_versions enable row level security;
alter table public.aiq_product_relationship_versions enable row level security;
alter table public.aiq_industry_news_versions enable row level security;

drop policy if exists "aiq product versions select" on public.aiq_product_versions;
create policy "aiq product versions select" on public.aiq_product_versions
for select
to authenticated
using (private.user_can_access_organization(organization_id, 'crm.view'));

drop policy if exists "aiq product versions write" on public.aiq_product_versions;
create policy "aiq product versions write" on public.aiq_product_versions
for all
to authenticated
using (private.user_can_access_organization(organization_id, 'crm.manage'))
with check (private.user_can_access_organization(organization_id, 'crm.manage'));

drop policy if exists "aiq product specification versions select" on public.aiq_product_specification_versions;
create policy "aiq product specification versions select" on public.aiq_product_specification_versions
for select
to authenticated
using (private.user_can_access_organization(organization_id, 'crm.view'));

drop policy if exists "aiq product specification versions write" on public.aiq_product_specification_versions;
create policy "aiq product specification versions write" on public.aiq_product_specification_versions
for all
to authenticated
using (private.user_can_access_organization(organization_id, 'crm.manage'))
with check (private.user_can_access_organization(organization_id, 'crm.manage'));

drop policy if exists "aiq document versions select" on public.aiq_document_versions;
create policy "aiq document versions select" on public.aiq_document_versions
for select
to authenticated
using (private.user_can_access_organization(organization_id, 'crm.view'));

drop policy if exists "aiq document versions write" on public.aiq_document_versions;
create policy "aiq document versions write" on public.aiq_document_versions
for all
to authenticated
using (private.user_can_access_organization(organization_id, 'crm.manage'))
with check (private.user_can_access_organization(organization_id, 'crm.manage'));

drop policy if exists "aiq competitive comparison versions select" on public.aiq_competitive_comparison_versions;
create policy "aiq competitive comparison versions select" on public.aiq_competitive_comparison_versions
for select
to authenticated
using (private.user_can_access_organization(organization_id, 'crm.view'));

drop policy if exists "aiq competitive comparison versions write" on public.aiq_competitive_comparison_versions;
create policy "aiq competitive comparison versions write" on public.aiq_competitive_comparison_versions
for all
to authenticated
using (private.user_can_access_organization(organization_id, 'crm.manage'))
with check (private.user_can_access_organization(organization_id, 'crm.manage'));

drop policy if exists "aiq product training asset versions select" on public.aiq_product_training_asset_versions;
create policy "aiq product training asset versions select" on public.aiq_product_training_asset_versions
for select
to authenticated
using (private.user_can_access_organization(organization_id, 'crm.view'));

drop policy if exists "aiq product training asset versions write" on public.aiq_product_training_asset_versions;
create policy "aiq product training asset versions write" on public.aiq_product_training_asset_versions
for all
to authenticated
using (private.user_can_access_organization(organization_id, 'crm.manage'))
with check (private.user_can_access_organization(organization_id, 'crm.manage'));

drop policy if exists "aiq product relationship versions select" on public.aiq_product_relationship_versions;
create policy "aiq product relationship versions select" on public.aiq_product_relationship_versions
for select
to authenticated
using (private.user_can_access_organization(organization_id, 'crm.view'));

drop policy if exists "aiq product relationship versions write" on public.aiq_product_relationship_versions;
create policy "aiq product relationship versions write" on public.aiq_product_relationship_versions
for all
to authenticated
using (private.user_can_access_organization(organization_id, 'crm.manage'))
with check (private.user_can_access_organization(organization_id, 'crm.manage'));

drop policy if exists "aiq industry news versions select" on public.aiq_industry_news_versions;
create policy "aiq industry news versions select" on public.aiq_industry_news_versions
for select
to authenticated
using (private.user_can_access_organization(organization_id, 'crm.view'));

drop policy if exists "aiq industry news versions write" on public.aiq_industry_news_versions;
create policy "aiq industry news versions write" on public.aiq_industry_news_versions
for all
to authenticated
using (private.user_can_access_organization(organization_id, 'crm.manage'))
with check (private.user_can_access_organization(organization_id, 'crm.manage'));
