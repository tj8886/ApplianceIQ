-- Appliance IQ AI layer — ported from Elev8 Phase 5 governance architecture.

create table public.ai_assistants (
  id uuid primary key default gen_random_uuid(),
  assistant_key text unique not null,
  label text not null,
  category text not null,
  description text,
  status text not null default 'active' check (status in ('active','inactive','archived')),
  approval_policy text not null default 'approval_required',
  approval_required boolean not null default true,
  organization_id uuid references public.organizations(id) on delete cascade,
  retrieval_scopes text[] not null default array['crm','knowledge'],
  safety_controls jsonb not null default '{}'::jsonb,
  response_contract jsonb not null default '{}'::jsonb,
  required_feature_key text,
  required_entitlement_key text,
  required_permission_name text,
  config jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index ai_assistants_org_idx on public.ai_assistants (organization_id);

create table public.ai_prompt_templates (
  id uuid primary key default gen_random_uuid(),
  template_key text unique not null,
  tool_type text not null,
  label text not null,
  organization_id uuid references public.organizations(id) on delete cascade,
  status text not null default 'active' check (status in ('active','inactive','archived')),
  system_prompt text not null,
  user_prompt_template text not null,
  tone_guidance text,
  output_schema jsonb,
  version int not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.ai_knowledge_sources (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  source_key text unique not null,
  title text not null,
  source_type text not null,
  authority_level text not null default 'reference',
  visibility text not null default 'global' check (visibility in ('global','organization')),
  status text not null default 'active' check (status in ('active','inactive','archived')),
  version int not null default 1,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.ai_knowledge_chunks (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references public.ai_knowledge_sources(id) on delete cascade,
  organization_id uuid references public.organizations(id) on delete cascade,
  chunk_key text unique not null,
  title text,
  content text not null,
  citation jsonb not null default '{}'::jsonb,
  status text not null default 'active' check (status in ('active','inactive','archived')),
  visibility text not null default 'global' check (visibility in ('global','organization')),
  embedding vector(1024),
  embedding_model text,
  source_hash text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index ai_chunks_org_idx on public.ai_knowledge_chunks (organization_id, status);
create index ai_chunks_embedding_idx on public.ai_knowledge_chunks using hnsw (embedding vector_cosine_ops);

create table public.ai_sessions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  assistant_key text not null references public.ai_assistants(assistant_key),
  status text not null default 'active',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  last_activity_at timestamptz not null default now()
);
create index ai_sessions_org_idx on public.ai_sessions (organization_id, user_id);

create table public.ai_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  session_id uuid references public.ai_sessions(id) on delete set null,
  user_id uuid not null references auth.users(id) on delete cascade,
  assistant_key text not null references public.ai_assistants(assistant_key),
  request_status text not null default 'received',
  prompt text not null,
  context jsonb not null default '{}'::jsonb,
  grounded_context jsonb,
  output jsonb,
  explanation text,
  model_provider text,
  model_name text,
  token_estimate int,
  error_message text,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);
create index ai_requests_org_idx on public.ai_requests (organization_id, created_at desc);

create table public.ai_proposed_actions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  request_id uuid references public.ai_requests(id) on delete cascade,
  assistant_key text not null,
  action_type text not null,
  action_payload jsonb not null default '{}'::jsonb,
  status text not null default 'pending' check (status in ('pending','approved','rejected','executed','expired')),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
create index ai_actions_org_idx on public.ai_proposed_actions (organization_id, status);

create table public.ai_audit_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  request_id uuid,
  assistant_key text,
  event_type text not null,
  event_status text not null default 'recorded',
  event_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index ai_audit_org_idx on public.ai_audit_events (organization_id, created_at desc);

create table public.ai_usage_meter (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  assistant_key text,
  request_id uuid,
  usage_kind text not null,
  quantity numeric not null,
  limit_key text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index ai_usage_org_idx on public.ai_usage_meter (organization_id, created_at desc);

create table public.embedding_worker_runs (
  id uuid primary key default gen_random_uuid(),
  batch_requested int not null,
  triggered_by text,
  status text not null default 'running',
  rows_embedded int default 0,
  rows_failed int default 0,
  model text,
  error_message text,
  metadata jsonb not null default '{}'::jsonb,
  started_at timestamptz not null default now(),
  finished_at timestamptz
);

alter table public.ai_assistants enable row level security;
alter table public.ai_prompt_templates enable row level security;
alter table public.ai_knowledge_sources enable row level security;
alter table public.ai_knowledge_chunks enable row level security;
alter table public.ai_sessions enable row level security;
alter table public.ai_requests enable row level security;
alter table public.ai_proposed_actions enable row level security;
alter table public.ai_audit_events enable row level security;
alter table public.ai_usage_meter enable row level security;
alter table public.embedding_worker_runs enable row level security;

create policy assistants_visible on public.ai_assistants for select
  using (organization_id is null or public.is_org_member(organization_id));
create policy templates_visible on public.ai_prompt_templates for select
  using (organization_id is null or public.is_org_member(organization_id));
create policy ksources_visible on public.ai_knowledge_sources for select
  using (visibility = 'global' or public.is_org_member(organization_id));
create policy kchunks_visible on public.ai_knowledge_chunks for select
  using (visibility = 'global' or public.is_org_member(organization_id));
create policy sessions_own on public.ai_sessions for select using (user_id = auth.uid());
create policy requests_own on public.ai_requests for select
  using (user_id = auth.uid() or public.is_org_admin(organization_id));
create policy actions_org on public.ai_proposed_actions for select using (public.is_org_member(organization_id));
create policy actions_review on public.ai_proposed_actions for update using (public.is_org_admin(organization_id));
create policy audit_admin on public.ai_audit_events for select using (public.is_org_admin(organization_id));
create policy usage_admin on public.ai_usage_meter for select using (public.is_org_admin(organization_id));

create or replace function public.list_available_assistants(p_organization_id uuid)
returns setof public.ai_assistants
language sql stable set search_path to '' as $$
  select * from public.ai_assistants
   where status = 'active'
     and (organization_id is null or organization_id = p_organization_id)
   order by category, label;
$$;

create or replace function public.ai_submit_request(
  p_organization_id uuid default null,
  p_assistant_key text default null,
  p_prompt text default null,
  p_context jsonb default '{}'::jsonb)
returns jsonb
language plpgsql security definer set search_path to '' as $$
declare
  v_user uuid := auth.uid();
  v_org uuid;
  v_assistant public.ai_assistants%rowtype;
  v_session uuid;
  v_request uuid;
  v_grounded jsonb;
  v_action uuid;
begin
  if v_user is null then
    raise exception 'Authentication required.';
  end if;
  if p_assistant_key is null or coalesce(length(trim(p_prompt)),0) < 3 then
    raise exception 'assistant_key and prompt are required.';
  end if;

  if p_organization_id is not null then
    if not public.is_org_member(p_organization_id) then
      raise exception 'Access denied for organization.';
    end if;
    v_org := p_organization_id;
  else
    select organization_id into v_org
      from public.organization_members
     where user_id = v_user and status = 'active'
     order by created_at limit 1;
    if v_org is null then
      raise exception 'Access denied: no active organization membership.';
    end if;
  end if;

  select * into v_assistant from public.ai_assistants
   where assistant_key = p_assistant_key and status = 'active';
  if not found then
    raise exception 'Unknown or inactive assistant.';
  end if;
  if v_assistant.organization_id is not null and v_assistant.organization_id <> v_org then
    raise exception 'Access denied: assistant not available for this organization.';
  end if;

  insert into public.ai_sessions (organization_id, user_id, assistant_key)
  values (v_org, v_user, p_assistant_key)
  returning id into v_session;

  v_grounded := jsonb_build_object(
    'record_counts', jsonb_build_object(
      'companies', (select count(*) from public.companies c where c.organization_id = v_org),
      'contacts', (select count(*) from public.contacts c where c.organization_id = v_org),
      'deals', (select count(*) from public.crm_deals d where d.organization_id = v_org),
      'open_tasks', (select count(*) from public.crm_tasks t where t.organization_id = v_org and t.completed_at is null),
      'products', (select count(*) from public.products p where p.organization_id = v_org)
    ),
    'pipeline', (select coalesce(jsonb_object_agg(stage, cnt), '{}'::jsonb)
                 from (select stage, count(*) cnt from public.crm_deals d
                       where d.organization_id = v_org and d.closed_at is null
                       group by stage) s),
    'generated_at', now()
  );

  insert into public.ai_requests
    (organization_id, session_id, user_id, assistant_key, request_status, prompt, context, grounded_context,
     output, explanation, model_provider, model_name, completed_at)
  values
    (v_org, v_session, v_user, p_assistant_key, 'completed', p_prompt, coalesce(p_context,'{}'::jsonb), v_grounded,
     jsonb_build_object('mode','foundation','assistant_key',p_assistant_key,
       'notice','Governed request recorded. Model layer produces the final answer.'),
     'Foundation envelope: auth, tenancy, assistant visibility, grounded context, and audit recorded at the database layer.',
     'foundation','deterministic', now())
  returning id into v_request;

  if v_assistant.approval_required then
    insert into public.ai_proposed_actions (organization_id, request_id, assistant_key, action_type, action_payload)
    values (v_org, v_request, p_assistant_key, 'advisory_output_review',
            jsonb_build_object('prompt_preview', left(p_prompt, 200)))
    returning id into v_action;
  end if;

  insert into public.ai_audit_events (organization_id, request_id, assistant_key, event_type, event_payload)
  values (v_org, v_request, p_assistant_key, 'ai.request.submitted',
          jsonb_build_object('approval_required', v_assistant.approval_required));

  insert into public.ai_usage_meter (organization_id, assistant_key, request_id, usage_kind, quantity, limit_key)
  values (v_org, p_assistant_key, v_request, 'request', 1, 'ai.requests.monthly');

  return jsonb_build_object(
    'request_id', v_request,
    'session_id', v_session,
    'organization_id', v_org,
    'approval_required', v_assistant.approval_required,
    'proposed_action_id', v_action,
    'output', (select output from public.ai_requests where id = v_request)
  );
end $$;

create or replace function public.start_embedding_worker_run(p_batch_requested int, p_triggered_by text)
returns uuid language sql security definer set search_path to '' as $$
  insert into public.embedding_worker_runs (batch_requested, triggered_by)
  values (p_batch_requested, p_triggered_by) returning id;
$$;

create or replace function public.list_pending_embeddings(p_batch_size int default 50)
returns table(table_name text, row_id uuid, source_text text, source_hash text)
language sql security definer set search_path to '' as $$
  (select 'ai_knowledge_chunks'::text, c.id,
          coalesce(c.title,'') || E'\n' || c.content,
          md5(coalesce(c.title,'') || c.content)
     from public.ai_knowledge_chunks c
    where c.status = 'active'
      and (c.embedding is null or c.source_hash is distinct from md5(coalesce(c.title,'') || c.content))
    limit p_batch_size)
  union all
  (select 'products'::text, p.id,
          p.brand || ' ' || p.model || ' ' || p.name || ' ' || coalesce(p.category,'') || E'\n' || coalesce(p.description,''),
          md5(p.brand || p.model || p.name || coalesce(p.category,'') || coalesce(p.description,''))
     from public.products p
    where p.embedding is null
       or p.source_hash is distinct from md5(p.brand || p.model || p.name || coalesce(p.category,'') || coalesce(p.description,''))
    limit p_batch_size)
  limit p_batch_size;
$$;

create or replace function public.write_embedding(
  p_table_name text, p_row_id uuid, p_embedding public.vector, p_model text, p_source_hash text)
returns boolean language plpgsql security definer set search_path to '' as $$
begin
  if p_table_name = 'ai_knowledge_chunks' then
    update public.ai_knowledge_chunks
       set embedding = p_embedding, embedding_model = p_model, source_hash = p_source_hash
     where id = p_row_id;
  elsif p_table_name = 'products' then
    update public.products
       set embedding = p_embedding, embedding_model = p_model, source_hash = p_source_hash
     where id = p_row_id;
  else
    return false;
  end if;
  return found;
end $$;

create or replace function public.complete_embedding_worker_run(
  p_run_id uuid, p_status text, p_rows_embedded int, p_rows_failed int,
  p_model text, p_error_message text default null, p_metadata jsonb default '{}'::jsonb)
returns void language sql security definer set search_path to '' as $$
  update public.embedding_worker_runs
     set status = p_status, rows_embedded = p_rows_embedded, rows_failed = p_rows_failed,
         model = p_model, error_message = p_error_message, metadata = p_metadata, finished_at = now()
   where id = p_run_id;
$$;

create or replace function public.match_products(p_organization_id uuid, p_query_embedding public.vector, p_limit int default 10)
returns table(product_id uuid, brand text, model text, name text, category text, msrp numeric, similarity float)
language sql stable security definer set search_path to '' as $$
  select p.id, p.brand, p.model, p.name, p.category, p.msrp,
         1 - (p.embedding operator(public.<=>) p_query_embedding) as similarity
    from public.products p
   where p.organization_id = p_organization_id and p.embedding is not null
   order by p.embedding operator(public.<=>) p_query_embedding
   limit p_limit;
$$;

revoke execute on function public.start_embedding_worker_run(int, text) from public, anon, authenticated;
revoke execute on function public.list_pending_embeddings(int) from public, anon, authenticated;
revoke execute on function public.write_embedding(text, uuid, public.vector, text, text) from public, anon, authenticated;
revoke execute on function public.complete_embedding_worker_run(uuid, text, int, int, text, text, jsonb) from public, anon, authenticated;
