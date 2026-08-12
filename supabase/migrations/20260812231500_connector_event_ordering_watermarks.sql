create table if not exists public.platform_connector_event_watermarks (
  connection_id uuid not null references public.platform_connector_connections(id) on delete cascade,
  external_entity_type text not null,
  external_id text not null,
  last_occurred_at timestamptz not null,
  payload_hash text not null,
  last_topic text,
  accepted_count bigint not null default 1,
  duplicate_count bigint not null default 0,
  stale_count bigint not null default 0,
  updated_at timestamptz not null default now(),
  primary key(connection_id,external_entity_type,external_id)
);
alter table public.platform_connector_event_watermarks enable row level security;
revoke all on public.platform_connector_event_watermarks from anon,authenticated;
grant select,insert,update,delete on public.platform_connector_event_watermarks to service_role;

create or replace function public.platform_accept_connector_event(
  p_connection_id uuid,
  p_external_entity_type text,
  p_external_id text,
  p_occurred_at timestamptz,
  p_payload_hash text,
  p_topic text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare r public.platform_connector_event_watermarks%rowtype;
begin
  select * into r from public.platform_connector_event_watermarks
  where connection_id=p_connection_id and external_entity_type=p_external_entity_type and external_id=p_external_id for update;
  if not found then
    insert into public.platform_connector_event_watermarks(connection_id,external_entity_type,external_id,last_occurred_at,payload_hash,last_topic)
    values(p_connection_id,p_external_entity_type,p_external_id,p_occurred_at,p_payload_hash,p_topic);
    return jsonb_build_object('accepted',true,'reason','first','occurred_at',p_occurred_at);
  end if;
  if r.payload_hash=p_payload_hash then
    update public.platform_connector_event_watermarks set duplicate_count=duplicate_count+1,updated_at=now()
    where connection_id=p_connection_id and external_entity_type=p_external_entity_type and external_id=p_external_id;
    return jsonb_build_object('accepted',false,'reason','duplicate','last_occurred_at',r.last_occurred_at);
  end if;
  if p_occurred_at < r.last_occurred_at then
    update public.platform_connector_event_watermarks set stale_count=stale_count+1,updated_at=now()
    where connection_id=p_connection_id and external_entity_type=p_external_entity_type and external_id=p_external_id;
    return jsonb_build_object('accepted',false,'reason','stale','last_occurred_at',r.last_occurred_at);
  end if;
  update public.platform_connector_event_watermarks
  set last_occurred_at=p_occurred_at,payload_hash=p_payload_hash,last_topic=p_topic,accepted_count=accepted_count+1,updated_at=now()
  where connection_id=p_connection_id and external_entity_type=p_external_entity_type and external_id=p_external_id;
  return jsonb_build_object('accepted',true,'reason','advanced','occurred_at',p_occurred_at);
end $$;
revoke all on function public.platform_accept_connector_event(uuid,text,text,timestamptz,text,text) from public,anon,authenticated;
grant execute on function public.platform_accept_connector_event(uuid,text,text,timestamptz,text,text) to service_role;
