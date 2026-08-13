begin;

create table if not exists public.platform_connector_event_archive (
  id uuid primary key default gen_random_uuid(),
  connection_id uuid not null references public.platform_connector_connections(id) on delete cascade,
  sync_job_id uuid references public.platform_sync_jobs(id) on delete set null,
  correlation_id uuid not null default gen_random_uuid(),
  external_entity_type text not null,
  external_id text,
  event_type text not null,
  source_api_version text,
  schema_fingerprint text,
  payload_hash text not null,
  payload jsonb not null,
  processing_status text not null default 'received' check (processing_status in ('received','processed','quarantined','failed','replayed')),
  replay_of_archive_id uuid references public.platform_connector_event_archive(id) on delete set null,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  retention_until timestamptz not null default (now() + interval '90 days'),
  metadata jsonb not null default '{}'::jsonb
);
create index if not exists idx_connector_event_archive_connection_received on public.platform_connector_event_archive(connection_id, received_at desc);
create index if not exists idx_connector_event_archive_correlation on public.platform_connector_event_archive(correlation_id);
create index if not exists idx_connector_event_archive_replay on public.platform_connector_event_archive(replay_of_archive_id) where replay_of_archive_id is not null;
create index if not exists idx_connector_event_archive_retention on public.platform_connector_event_archive(retention_until);

create table if not exists public.platform_connector_schema_fingerprints (
  id uuid primary key default gen_random_uuid(),
  connector_id uuid not null references public.platform_connectors(id) on delete cascade,
  variant_id uuid references public.platform_connector_variants(id) on delete cascade,
  external_entity_type text not null,
  api_version text,
  fingerprint text not null,
  observed_shape jsonb not null default '{}'::jsonb,
  status text not null default 'observed' check (status in ('baseline','observed','changed','approved','rejected')),
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  occurrence_count bigint not null default 1,
  metadata jsonb not null default '{}'::jsonb,
  unique(connector_id, variant_id, external_entity_type, api_version, fingerprint)
);
create index if not exists idx_connector_schema_fingerprint_lookup on public.platform_connector_schema_fingerprints(connector_id, variant_id, external_entity_type, api_version, last_seen_at desc);

create table if not exists public.platform_connector_trace_events (
  id uuid primary key default gen_random_uuid(),
  correlation_id uuid not null,
  connection_id uuid not null references public.platform_connector_connections(id) on delete cascade,
  sync_job_id uuid references public.platform_sync_jobs(id) on delete set null,
  archive_event_id uuid references public.platform_connector_event_archive(id) on delete set null,
  stage text not null,
  status text not null,
  latency_ms integer,
  attempt integer not null default 1,
  error_code text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists idx_connector_trace_correlation on public.platform_connector_trace_events(correlation_id, created_at);
create index if not exists idx_connector_trace_connection on public.platform_connector_trace_events(connection_id, created_at desc);
create index if not exists idx_connector_trace_job on public.platform_connector_trace_events(sync_job_id, created_at) where sync_job_id is not null;

alter table public.platform_connector_event_archive enable row level security;
alter table public.platform_connector_schema_fingerprints enable row level security;
alter table public.platform_connector_trace_events enable row level security;
revoke all on table public.platform_connector_event_archive from anon, authenticated;
revoke all on table public.platform_connector_schema_fingerprints from anon, authenticated;
revoke all on table public.platform_connector_trace_events from anon, authenticated;
grant all on table public.platform_connector_event_archive to service_role;
grant all on table public.platform_connector_schema_fingerprints to service_role;
grant all on table public.platform_connector_trace_events to service_role;

create or replace function public.connector_payload_fingerprint(p_payload jsonb)
returns text language sql immutable set search_path = public, pg_temp
as $$
  select md5(coalesce((
    select string_agg(key || ':' || jsonb_typeof(value), '|' order by key)
    from jsonb_each(coalesce(p_payload,'{}'::jsonb))
  ), ''));
$$;
revoke execute on function public.connector_payload_fingerprint(jsonb) from public, anon, authenticated;
grant execute on function public.connector_payload_fingerprint(jsonb) to service_role;

create or replace function public.archive_connector_event(
  p_connection_id uuid,
  p_external_entity_type text,
  p_event_type text,
  p_payload jsonb,
  p_external_id text default null,
  p_sync_job_id uuid default null,
  p_source_api_version text default null,
  p_correlation_id uuid default null,
  p_metadata jsonb default '{}'::jsonb
) returns uuid
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_id uuid;
  v_correlation uuid := coalesce(p_correlation_id, gen_random_uuid());
  v_fingerprint text := public.connector_payload_fingerprint(p_payload);
  v_connector_id uuid;
  v_variant_id uuid;
begin
  select connector_id, variant_id into v_connector_id, v_variant_id
  from public.platform_connector_connections where id=p_connection_id;
  if v_connector_id is null then raise exception 'Unknown connector connection'; end if;

  insert into public.platform_connector_event_archive(
    connection_id,sync_job_id,correlation_id,external_entity_type,external_id,event_type,
    source_api_version,schema_fingerprint,payload_hash,payload,metadata
  ) values (
    p_connection_id,p_sync_job_id,v_correlation,p_external_entity_type,p_external_id,p_event_type,
    p_source_api_version,v_fingerprint,md5(coalesce(p_payload::text,'')),p_payload,coalesce(p_metadata,'{}'::jsonb)
  ) returning id into v_id;

  insert into public.platform_connector_schema_fingerprints(
    connector_id,variant_id,external_entity_type,api_version,fingerprint,observed_shape
  ) values (
    v_connector_id,v_variant_id,p_external_entity_type,p_source_api_version,v_fingerprint,
    coalesce((select jsonb_object_agg(key,jsonb_typeof(value)) from jsonb_each(coalesce(p_payload,'{}'::jsonb))),'{}'::jsonb)
  ) on conflict(connector_id,variant_id,external_entity_type,api_version,fingerprint)
    do update set last_seen_at=now(), occurrence_count=platform_connector_schema_fingerprints.occurrence_count+1;

  insert into public.platform_connector_trace_events(correlation_id,connection_id,sync_job_id,archive_event_id,stage,status,details)
  values(v_correlation,p_connection_id,p_sync_job_id,v_id,'ingestion.archive','received',jsonb_build_object('entity_type',p_external_entity_type,'event_type',p_event_type));

  return v_id;
end;
$$;
revoke execute on function public.archive_connector_event(uuid,text,text,jsonb,text,uuid,text,uuid,jsonb) from public, anon, authenticated;
grant execute on function public.archive_connector_event(uuid,text,text,jsonb,text,uuid,text,uuid,jsonb) to service_role;

create or replace view public.v_platform_connector_schema_drift
with (security_invoker=true) as
with ranked as (
  select sf.*, row_number() over(partition by connector_id,variant_id,external_entity_type order by last_seen_at desc) rn,
         count(*) over(partition by connector_id,variant_id,external_entity_type) fingerprint_count
  from public.platform_connector_schema_fingerprints sf
)
select connector_id,variant_id,external_entity_type,api_version,fingerprint,status,first_seen_at,last_seen_at,occurrence_count,
       (fingerprint_count > 1) as drift_detected
from ranked where rn=1;
revoke all on public.v_platform_connector_schema_drift from anon, authenticated;
grant select on public.v_platform_connector_schema_drift to service_role;

commit;
