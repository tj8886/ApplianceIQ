-- Team invite system: org admins/owners invite reps by email
create table if not exists public.org_invites (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  invited_email text not null,
  invite_code text not null unique default encode(gen_random_bytes(16), 'hex'),
  role text not null default 'member' check (role in ('owner','admin','member')),
  org_role_id uuid references public.org_roles(id),
  manager_id uuid references auth.users(id),
  invited_by uuid not null references auth.users(id),
  status text not null default 'pending' check (status in ('pending','accepted','expired','revoked')),
  created_at timestamptz not null default now(),
  accepted_at timestamptz,
  expires_at timestamptz not null default (now() + interval '7 days')
);
alter table public.org_invites enable row level security;
create policy org_invites_select on public.org_invites for select using (is_org_member(organization_id));
create policy org_invites_insert on public.org_invites for insert with check (is_org_admin(organization_id));
create policy org_invites_update on public.org_invites for update using (is_org_admin(organization_id));
create policy org_invites_delete on public.org_invites for delete using (is_org_admin(organization_id));
create index org_invites_org_idx on public.org_invites (organization_id, status);
create index org_invites_code_idx on public.org_invites (invite_code) where status = 'pending';
create index org_invites_email_idx on public.org_invites (invited_email, status);

-- RPC: accept an invite
create or replace function public.accept_invite(p_invite_code text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_invite record; v_user_id uuid; v_existing record;
begin
  v_user_id := auth.uid();
  if v_user_id is null then return jsonb_build_object('error', 'not_authenticated'); end if;
  select * into v_invite from public.org_invites where invite_code = p_invite_code and status = 'pending' for update;
  if not found then return jsonb_build_object('error', 'invite_not_found_or_used'); end if;
  if v_invite.expires_at < now() then
    update public.org_invites set status = 'expired' where id = v_invite.id;
    return jsonb_build_object('error', 'invite_expired');
  end if;
  if lower((select email from auth.users where id = v_user_id)) != lower(v_invite.invited_email) then
    return jsonb_build_object('error', 'email_mismatch', 'detail', 'Sign in with the email that was invited.');
  end if;
  select * into v_existing from public.organization_members where organization_id = v_invite.organization_id and user_id = v_user_id;
  if found then
    update public.org_invites set status = 'accepted', accepted_at = now() where id = v_invite.id;
    return jsonb_build_object('ok', true, 'already_member', true);
  end if;
  insert into public.organization_members (organization_id, user_id, role, status, org_role_id, manager_id)
  values (v_invite.organization_id, v_user_id, v_invite.role, 'active', v_invite.org_role_id, v_invite.manager_id);
  update public.org_invites set status = 'accepted', accepted_at = now() where id = v_invite.id;
  return jsonb_build_object('ok', true, 'organization_id', v_invite.organization_id);
end;
$$;
