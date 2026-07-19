-- Allows any authenticated user to join the Demo Retail Store tenant (demo only).
create or replace function public.join_demo_org()
returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_user uuid := auth.uid(); v_demo uuid := '00000000-0000-0000-0000-000000000002';
begin
  if v_user is null then raise exception 'Authentication required.'; end if;
  insert into public.profiles (user_id, email)
  select v_user, (select email from auth.users where id = v_user)
  on conflict (user_id) do nothing;
  insert into public.organization_members (organization_id, user_id, role, status)
  values (v_demo, v_user, 'member', 'active')
  on conflict (organization_id, user_id) do update set status = 'active';
  return jsonb_build_object('joined', true, 'organization_id', v_demo);
end $$;
revoke execute on function public.join_demo_org() from public, anon;
