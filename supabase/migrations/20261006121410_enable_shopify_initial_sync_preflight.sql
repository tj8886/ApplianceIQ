-- Preflight only: Canada and US both currently have zero linked Shopify stores.
-- Never read legacy plaintext tokens or claim that historical reconciliation ran.
create function tj_private.shopify_initial_sync(p_body jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=tj_private.current_source_user_id(); conn tj.platform_connector_connections%rowtype;
 store record; action text; linked integer; blockers jsonb:='[]'; scopes text[]; result jsonb; linked_ok boolean:=false;
begin
 if actor is null then raise exception using errcode='42501',message='connection_access_denied';end if;
 if jsonb_typeof(p_body) is distinct from 'object' or octet_length(p_body::text)>8192
  or exists(select 1 from jsonb_object_keys(p_body) k where k not in ('connection_id','action')) then
  raise exception using errcode='22023',message='invalid_request';end if;
 select * into conn from tj.platform_connector_connections where id=(p_body->>'connection_id')::uuid;
 if conn.id is null or not exists(select 1 from tj.organization_members m join tj.organizations o on o.id=m.organization_id
  where m.organization_id=conn.organization_id and m.user_id=actor and m.status='active' and m.role in ('owner','admin','super_admin')
   and o.status='active' and o.deleted_at is null) then raise exception using errcode='42501',message='connection_access_denied';end if;
 if not exists(select 1 from tj.platform_connectors p where p.id=conn.connector_id and p.key='shopify') then raise exception using errcode='22023',message='not_shopify_connection';end if;
 action:=coalesce(p_body->>'action','sync');
 if action not in ('status','sync') then raise exception using errcode='22023',message='invalid_action';end if;
 select count(*) into linked from tj.shopify_stores s where s.platform_connection_id=conn.id;
 if linked<>1 then blockers:=blockers||jsonb_build_array(case when linked=0 then 'shopify_store_link_missing' else 'shopify_store_link_ambiguous' end);
 else
  select s.id,s.organization_id,s.shop_domain,s.status,s.uninstalled_at,s.scopes into store from tj.shopify_stores s where s.platform_connection_id=conn.id;
  linked_ok:=store.organization_id=conn.organization_id;
  if store.organization_id<>conn.organization_id then blockers:=blockers||'"shopify_store_organization_mismatch"'::jsonb;
  else
   if store.status<>'active' or store.uninstalled_at is not null then blockers:=blockers||'"shopify_store_inactive"'::jsonb;end if;
   if store.shop_domain !~ '^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.myshopify\.com$' then blockers:=blockers||'"shopify_domain_invalid"'::jsonb;end if;
   scopes:=regexp_split_to_array(store.scopes,'\s*,\s*');
  end if;
 end if;
 -- An imported credential reference/settings flag is never destination approval.
 blockers:=blockers||'["shopify_destination_credentials_and_scopes_required","shopify_resumable_importer_required","shopify_nested_pagination_verification_required","shopify_performance_reconciliation_required"]'::jsonb;
 result:=jsonb_build_object('ok',action='status','connection_id',conn.id,'preflight_only',true,'sync_ready',false,'executed',false,'imported_records',0,'performance_orders',0,
  'linked_store',linked_ok,'blockers',blockers,
  'recorded_scope_flags',jsonb_build_object('read_all_orders',coalesce('read_all_orders'=any(scopes),false),'read_users',coalesce('read_users'=any(scopes),false),'provider_verified',false));
 if action='sync' then result:=result||jsonb_build_object('error','shopify_destination_verification_required');end if;
 return result;
end $$;
revoke all on function tj_private.shopify_initial_sync(jsonb) from public,anon,authenticated,service_role;
grant execute on function tj_private.shopify_initial_sync(jsonb) to authenticated;
create function public.tj_shopify_initial_sync(p_body jsonb) returns jsonb language sql security invoker set search_path='' as $$select tj_private.shopify_initial_sync(p_body);$$;
revoke all on function public.tj_shopify_initial_sync(jsonb) from public,anon,service_role;
grant execute on function public.tj_shopify_initial_sync(jsonb) to authenticated;
notify pgrst,'reload schema';
