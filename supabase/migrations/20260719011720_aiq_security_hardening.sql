-- Hardening per security advisors
revoke execute on function public.ai_submit_request(uuid, text, text, jsonb) from public, anon;
revoke execute on function public.match_products(uuid, public.vector, int) from public, anon;
revoke execute on function public.is_org_member(uuid) from public, anon;
revoke execute on function public.is_org_admin(uuid) from public, anon;
revoke execute on function public.list_available_assistants(uuid) from public, anon;

create or replace function public.touch_updated_at()
returns trigger language plpgsql set search_path to '' as $$
begin new.updated_at = now(); return new; end $$;
