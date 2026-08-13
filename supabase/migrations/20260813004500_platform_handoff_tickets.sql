create table if not exists public.platform_handoff_tickets (
  id uuid primary key default gen_random_uuid(),
  ticket_hash text not null unique,
  user_id uuid not null references auth.users(id) on delete cascade,
  organization_id uuid references public.organizations(id) on delete cascade,
  location_id uuid references public.org_locations(id) on delete set null,
  entity_type text,
  entity_id uuid,
  entity_label text,
  source_module_key text,
  target_module_key text,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.platform_handoff_tickets enable row level security;
create index if not exists idx_platform_handoff_expiry on public.platform_handoff_tickets(expires_at) where consumed_at is null;
revoke all on public.platform_handoff_tickets from anon, authenticated;
grant all on public.platform_handoff_tickets to service_role;

create or replace function public.consume_platform_handoff_ticket(p_ticket_hash text, p_target_module_key text default null)
returns table(user_id uuid, organization_id uuid, location_id uuid, entity_type text, entity_id uuid, entity_label text, source_module_key text)
language plpgsql
security definer
set search_path=public
as $$
declare v_id uuid;
begin
  update public.platform_handoff_tickets t
  set consumed_at=now()
  where t.ticket_hash=p_ticket_hash
    and t.consumed_at is null
    and t.expires_at>now()
    and (t.target_module_key is null or p_target_module_key is null or t.target_module_key=p_target_module_key)
  returning t.id into v_id;
  if v_id is null then return; end if;
  return query
    select t.user_id,t.organization_id,t.location_id,t.entity_type,t.entity_id,t.entity_label,t.source_module_key
    from public.platform_handoff_tickets t where t.id=v_id;
end $$;
revoke all on function public.consume_platform_handoff_ticket(text,text) from public,anon,authenticated;
grant execute on function public.consume_platform_handoff_ticket(text,text) to service_role;
