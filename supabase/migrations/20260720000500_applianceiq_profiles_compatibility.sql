-- ApplianceIQ compatibility shim for repositories that still reference
-- public.profiles(id) while the live target uses public.profiles(user_id).
-- Additive only.

alter table public.profiles
  add column if not exists id uuid;

update public.profiles
set id = user_id
where id is null;

alter table public.profiles
  alter column id set not null;

create unique index if not exists profiles_id_unique_idx
  on public.profiles (id);

create or replace function private.sync_profiles_id()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.id := coalesce(new.id, new.user_id);
  if new.id is distinct from new.user_id then
    new.id := new.user_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_profiles_sync_id on public.profiles;
create trigger trg_profiles_sync_id
before insert or update on public.profiles
for each row execute function private.sync_profiles_id();

revoke all on function private.sync_profiles_id() from public;
grant execute on function private.sync_profiles_id() to authenticated, service_role;
