-- Custom KPI definitions per organization
create table if not exists public.org_kpis (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  kpi_name text not null,
  description text,
  weight numeric default 1.0,
  target_score numeric default 8.0,
  active boolean default true,
  created_at timestamptz not null default now(),
  unique(organization_id, kpi_name)
);
alter table public.org_kpis enable row level security;
create policy org_kpis_select on public.org_kpis for select using (is_org_member(organization_id));
create policy org_kpis_write on public.org_kpis for insert with check (is_org_admin(organization_id));
create policy org_kpis_update on public.org_kpis for update using (is_org_admin(organization_id));
create policy org_kpis_delete on public.org_kpis for delete using (is_org_admin(organization_id));
create index org_kpis_org_idx on public.org_kpis (organization_id);

-- AI Roleplay sessions (reps practice against AI customer)
create table if not exists public.ai_roleplay_sessions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  scenario_type text not null check (scenario_type in ('cold_call','follow_up','objection_handling','product_demo')),
  status text not null default 'active' check (status in ('active','completed','abandoned')),
  total_turns integer default 0,
  session_score numeric,
  kpi_scores jsonb,
  transcript jsonb,
  feedback text,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);
alter table public.ai_roleplay_sessions enable row level security;
create policy ai_roleplay_sessions_select on public.ai_roleplay_sessions for select using (is_org_member(organization_id) or user_id = auth.uid());
create policy ai_roleplay_sessions_insert on public.ai_roleplay_sessions for insert with check (user_id = auth.uid());
create policy ai_roleplay_sessions_update on public.ai_roleplay_sessions for update using (user_id = auth.uid());
create index ai_roleplay_sessions_org_user_idx on public.ai_roleplay_sessions (organization_id, user_id, created_at desc);

-- Daily coaching focus (what to practice today based on yesterday's scores)
create table if not exists public.daily_coaching_focus (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  focus_date date not null default current_date,
  primary_kpi_id uuid references public.org_kpis(id),
  primary_kpi_name text,
  previous_score numeric,
  target_score numeric,
  insight text,
  created_at timestamptz not null default now(),
  unique(organization_id, user_id, focus_date)
);
alter table public.daily_coaching_focus enable row level security;
create policy daily_coaching_focus_select on public.daily_coaching_focus for select using (is_org_member(organization_id) or user_id = auth.uid());
create index daily_coaching_focus_date_idx on public.daily_coaching_focus (focus_date desc);

-- Helper: initialize default KPIs for new orgs
create or replace function public.init_default_kpis(p_organization_id uuid)
returns void
language sql security definer set search_path = public as $$
  insert into public.org_kpis (organization_id, kpi_name, description, weight, target_score)
  values
    (p_organization_id, 'Discovery', 'Asking the right questions to understand customer needs', 1.0, 8.0),
    (p_organization_id, 'Objection Handling', 'Responding effectively to customer concerns', 1.0, 8.0),
    (p_organization_id, 'Product Knowledge', 'Explaining features and benefits clearly', 1.0, 8.0),
    (p_organization_id, 'Closing', 'Moving toward the sale', 1.0, 8.0),
    (p_organization_id, 'Follow-up', 'Maintaining momentum and commitment', 1.0, 8.0)
  on conflict (organization_id, kpi_name) do nothing;
$$;

-- Generate daily coaching brief
create or replace function public.generate_daily_coaching_brief(p_organization_id uuid, p_user_id uuid)
returns table(primary_kpi text, previous_score numeric, target_score numeric, insight text)
language plpgsql security definer set search_path = public as $$
declare
  v_yesterday date := current_date - interval '1 day';
  v_lowest_kpi_id uuid;
  v_lowest_score numeric;
  v_target_score numeric;
  v_insight text;
begin
  -- Get yesterday's coaching reviews for this user
  with yesterday_scores as (
    select
      k.id,
      k.kpi_name,
      k.target_score,
      avg(case
        when ar.coaching_data->'kpi_scores' ? k.kpi_name
        then (ar.coaching_data->'kpi_scores'->>k.kpi_name)::numeric
        else null
      end) as avg_score
    from public.ai_coaching_reviews ar
    join public.org_kpis k on k.organization_id = p_organization_id
    where ar.organization_id = p_organization_id
      and ar.user_id = p_user_id
      and date(ar.created_at) = v_yesterday
      and k.active = true
    group by k.id, k.kpi_name, k.target_score
  )
  select
    s.id, s.avg_score
    into v_lowest_kpi_id, v_lowest_score
  from yesterday_scores s
  where s.avg_score is not null
  order by s.avg_score asc
  limit 1;

  if v_lowest_kpi_id is null then
    -- No coaching yesterday, pick the first active KPI
    select id, target_score into v_lowest_kpi_id, v_target_score
    from public.org_kpis
    where organization_id = p_organization_id and active = true
    limit 1;
    v_lowest_score := null;
    v_insight := 'Get started with your first coaching session today!';
  else
    select target_score into v_target_score from public.org_kpis where id = v_lowest_kpi_id;
    v_insight := 'Your ' || (select kpi_name from org_kpis where id = v_lowest_kpi_id) || ' score was ' || v_lowest_score::text || '/10 yesterday. Focus on improving this today.';
  end if;

  -- Upsert into daily_coaching_focus
  insert into public.daily_coaching_focus (
    organization_id, user_id, focus_date, primary_kpi_id, primary_kpi_name, previous_score, target_score, insight
  )
  select p_organization_id, p_user_id, current_date, v_lowest_kpi_id, (select kpi_name from org_kpis where id = v_lowest_kpi_id), v_lowest_score, v_target_score, v_insight
  on conflict (organization_id, user_id, focus_date) do update set
    primary_kpi_id = v_lowest_kpi_id,
    primary_kpi_name = (select kpi_name from org_kpis where id = v_lowest_kpi_id),
    previous_score = v_lowest_score,
    insight = v_insight;

  return query
  select
    (select kpi_name from org_kpis where id = v_lowest_kpi_id) as primary_kpi,
    v_lowest_score,
    v_target_score,
    v_insight;
end;
$$;
