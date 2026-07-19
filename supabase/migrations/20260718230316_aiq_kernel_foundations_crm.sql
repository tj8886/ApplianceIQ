-- Appliance IQ kernel v1 — ported from the Elev8 framework.
-- Same table and column names as Elev8 Web so the frontend repoints via env vars.

create extension if not exists pgcrypto;
create extension if not exists vector;

-- Enums (identical values to Elev8 for portability)
create type public.company_status as enum ('prospect','active_client','past_client','employer','partner','vendor','do_not_contact','duplicate');
create type public.lifecycle_stage as enum ('lead','marketing_qualified','sales_qualified','opportunity','customer','renewal','churn');

-- ============ TENANCY ============
create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text unique not null,
  tenant_type text not null default 'retail_company'
    check (tenant_type in ('appliance_iq_internal','retail_company','independent_seller','demo')),
  status text not null default 'active' check (status in ('active','suspended','archived')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  email text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.organization_members (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner','admin','manager','member','viewer')),
  status text not null default 'active' check (status in ('invited','active','suspended','removed')),
  created_at timestamptz not null default now(),
  unique (organization_id, user_id)
);

-- Membership helpers (SECURITY DEFINER to avoid RLS recursion)
create or replace function public.is_org_member(p_org uuid)
returns boolean language sql stable security definer set search_path to '' as $$
  select exists (select 1 from public.organization_members m
    where m.organization_id = p_org and m.user_id = auth.uid() and m.status = 'active');
$$;

create or replace function public.is_org_admin(p_org uuid)
returns boolean language sql stable security definer set search_path to '' as $$
  select exists (select 1 from public.organization_members m
    where m.organization_id = p_org and m.user_id = auth.uid() and m.status = 'active'
      and m.role in ('owner','admin'));
$$;

-- ============ CRM CORE ============
create table public.companies (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  display_name text,
  legal_name text,
  industry text,
  website text,
  city text,
  region text,
  country_code text default 'CA',
  status public.company_status not null default 'prospect',
  lifecycle_stage public.lifecycle_stage not null default 'lead',
  source text,
  custom_fields jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index companies_org_idx on public.companies (organization_id);
create index companies_org_name_idx on public.companies (organization_id, lower(name));

create table public.contacts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  company_id uuid references public.companies(id) on delete set null,
  first_name text not null,
  last_name text,
  title text,
  email text,
  phone text,
  linkedin_url text,
  country_code text default 'CA',
  source text,
  lifecycle_stage public.lifecycle_stage not null default 'lead',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index contacts_org_idx on public.contacts (organization_id);
create index contacts_company_idx on public.contacts (company_id);

create table public.pipeline_stages (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  sort_order int not null default 0,
  is_terminal boolean not null default false,
  is_default boolean not null default false,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index pipeline_stages_org_idx on public.pipeline_stages (organization_id, sort_order);

create table public.crm_deals (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  company_id uuid references public.companies(id) on delete set null,
  contact_id uuid references public.contacts(id) on delete set null,
  owner_user_id uuid references auth.users(id) on delete set null,
  title text not null,
  stage text not null default 'Lead',
  value_amount numeric(14,2),
  value_currency text default 'CAD',
  expected_close_date date,
  closed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index crm_deals_org_idx on public.crm_deals (organization_id, stage);

create table public.crm_tasks (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  deal_id uuid references public.crm_deals(id) on delete cascade,
  company_id uuid references public.companies(id) on delete set null,
  contact_id uuid references public.contacts(id) on delete set null,
  assignee_user_id uuid references auth.users(id) on delete set null,
  title text not null,
  description text,
  due_at timestamptz,
  completed_at timestamptz,
  priority text default 'normal' check (priority in ('low','normal','high','urgent')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index crm_tasks_org_idx on public.crm_tasks (organization_id, due_at);

create table public.activities (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  actor_user_id uuid references auth.users(id) on delete set null,
  entity_type text not null,
  entity_id uuid,
  activity_type text not null,
  summary text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index activities_org_idx on public.activities (organization_id, created_at desc);

-- ============ RETAIL VERTICAL ============
create table public.products (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  brand text not null,
  model text not null,
  name text not null,
  category text,
  msrp numeric(12,2),
  cost numeric(12,2),
  margin_pct numeric(5,2),
  warranty_months int,
  in_stock boolean not null default true,
  description text,
  embedding vector(1024),
  embedding_model text,
  source_hash text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index products_org_idx on public.products (organization_id, category);
create index products_embedding_idx on public.products using hnsw (embedding vector_cosine_ops);

-- ============ RLS ============
alter table public.organizations enable row level security;
alter table public.organization_members enable row level security;
alter table public.profiles enable row level security;
alter table public.companies enable row level security;
alter table public.contacts enable row level security;
alter table public.pipeline_stages enable row level security;
alter table public.crm_deals enable row level security;
alter table public.crm_tasks enable row level security;
alter table public.activities enable row level security;
alter table public.products enable row level security;

create policy org_select on public.organizations for select using (public.is_org_member(id));
create policy org_update on public.organizations for update using (public.is_org_admin(id));

create policy members_select on public.organization_members for select using (public.is_org_member(organization_id));
create policy members_admin on public.organization_members for all using (public.is_org_admin(organization_id));

create policy profiles_self on public.profiles for all using (user_id = auth.uid());

-- Uniform org-scoped policies for CRM tables
do $$
declare t text;
begin
  foreach t in array array['companies','contacts','pipeline_stages','crm_deals','crm_tasks','activities','products']
  loop
    execute format('create policy %I_org_select on public.%I for select using (public.is_org_member(organization_id));', t, t);
    execute format('create policy %I_org_insert on public.%I for insert with check (public.is_org_member(organization_id));', t, t);
    execute format('create policy %I_org_update on public.%I for update using (public.is_org_member(organization_id));', t, t);
    execute format('create policy %I_org_delete on public.%I for delete using (public.is_org_admin(organization_id));', t, t);
  end loop;
end $$;

-- updated_at maintenance
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

do $$
declare t text;
begin
  foreach t in array array['organizations','profiles','companies','contacts','crm_deals','crm_tasks','products']
  loop
    execute format('create trigger %I_touch before update on public.%I for each row execute function public.touch_updated_at();', t, t);
  end loop;
end $$;
