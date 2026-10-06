-- Setup and credential rotation only; no outbound provider test or import.
create table tj_private.storis_credentials(
 connection_id uuid primary key references tj.platform_connector_connections(id),
 organization_id uuid not null references tj.organizations(id),
 secret_id uuid unique not null references vault.secrets(id),
 auth_type text not null check(auth_type in ('bearer','basic','api_key'))
);
create index storis_credentials_org_idx on tj_private.storis_credentials(organization_id);
alter table tj_private.storis_credentials enable row level security;
revoke all on tj_private.storis_credentials from public,anon,authenticated,service_role;
create function tj_private.storis_setup(p_body jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=tj_private.current_source_user_id(); conn tj.platform_connector_connections%rowtype;
 act text;cfg jsonb;base text;at text;header text;testpath text;eps jsonb;resource text;path jsonb;cred jsonb;sid uuid;oldtype text;
begin
 if actor is null then raise exception using errcode='42501',message='connection_access_denied';end if;
 if jsonb_typeof(p_body) is distinct from 'object' or octet_length(p_body::text)>16384
  or exists(select 1 from jsonb_object_keys(p_body) k where k not in ('action','connection_id','base_url','auth_type','api_key_header','test_path','endpoints','credential','resources','sync_type')) then raise exception using errcode='22023',message='invalid_request';end if;
 select * into conn from tj.platform_connector_connections where id=(p_body->>'connection_id')::uuid for update;
 if conn.id is null or not exists(select 1 from tj.organization_members m join tj.organizations o on o.id=m.organization_id
  where m.organization_id=conn.organization_id and m.user_id=actor and m.status='active' and m.role in ('owner','admin','super_admin') and o.status='active' and o.deleted_at is null)
 then raise exception using errcode='42501',message='connection_access_denied';end if;
 if not exists(select 1 from tj.platform_connectors p where p.id=conn.connector_id and p.key='storis') then raise exception using errcode='22023',message='not_storis_connection';end if;
 if conn.store_id is not null and not exists(select 1 from tj.org_locations l where l.id=conn.store_id and l.organization_id=conn.organization_id and l.is_active) then raise exception using errcode='42501',message='invalid_connection_store';end if;
 act:=coalesce(p_body->>'action','status');cfg:=coalesce(conn.settings->'storis_api','{}');
 select c.secret_id,c.auth_type into sid,oldtype from tj_private.storis_credentials c where c.connection_id=conn.id and c.organization_id=conn.organization_id and conn.credential_ref=c.secret_id::text;
 if act='configure' then
  if conn.status in ('paused','disconnected') or exists(select 1 from tj.platform_sync_jobs j where j.connection_id=conn.id and j.status in ('queued','running')) then raise exception using errcode='40001',message='connection_busy_or_paused';end if;
  base:=coalesce(p_body->>'base_url',cfg->>'base_url');at:=coalesce(p_body->>'auth_type',cfg->>'auth_type','bearer');header:=coalesce(p_body->>'api_key_header',cfg->>'api_key_header','X-API-Key');testpath:=nullif(p_body->>'test_path','');
  if base is null or length(base)>2048 or base !~ '^https://[a-z0-9]([a-z0-9.-]*[a-z0-9])?(/[A-Za-z0-9._~/-]*)?$'
   or base~'\.\.' or base~'/\.(/|$)' or base~'^https://localhost(/|$)' or base~'^https://[0-9]+(\.[0-9]+){3}(/|$)' or base~'://.+//' then raise exception using errcode='22023',message='https_base_url_required';end if;
  if at not in ('bearer','basic','api_key') then raise exception using errcode='22023',message='unsupported_auth_type';end if;
  if header !~ '^[A-Za-z][A-Za-z0-9-]{0,63}$' or lower(header) in ('host','authorization','cookie','accept','content-type','content-length','connection','proxy-authorization','origin','referer','transfer-encoding','upgrade','te','trailer') then raise exception using errcode='22023',message='invalid_credential_header';end if;
  eps:=p_body->'endpoints';
  if jsonb_typeof(eps) is distinct from 'object' or eps='{}'::jsonb then raise exception using errcode='22023',message='endpoints_required';end if;
  for resource,path in select key,value from jsonb_each(eps) loop
   if resource not in ('customers','products','salespeople','locations','salesOrders','quotes','inventory','prices','payments') or jsonb_typeof(path)<>'string'
    or length(path#>>'{}')>500 or (path#>>'{}') !~ '^/?[A-Za-z0-9_/-]+$' or (path#>>'{}')~'//' then raise exception using errcode='22023',message='relative_endpoint_required';end if;
  end loop;
  if testpath is not null and (length(testpath)>500 or testpath !~ '^/?[A-Za-z0-9_/-]+$' or testpath~'//') then raise exception using errcode='22023',message='relative_test_path_required';end if;
  cred:=p_body->'credential';
  if cred is not null and cred<>'null'::jsonb then
   if jsonb_typeof(cred)<>'object' or exists(select 1 from jsonb_each(cred) x where jsonb_typeof(x.value)<>'string' or length(x.value#>>'{}') not between 1 and 4096 or (x.value#>>'{}')~'[\r\n]')
    or (at='bearer' and (not cred ? 'token' or exists(select 1 from jsonb_object_keys(cred) k where k<>'token')))
    or (at='api_key' and (not cred ? 'api_key' or exists(select 1 from jsonb_object_keys(cred) k where k<>'api_key')))
    or (at='basic' and (not cred ?& array['username','password'] or exists(select 1 from jsonb_object_keys(cred) k where k not in ('username','password')))) then raise exception using errcode='22023',message='invalid_credential';end if;
   if sid is null then
    if exists(select 1 from tj_private.storis_credentials where connection_id=conn.id) then raise exception using errcode='40001',message='credential_provenance_mismatch';end if;
    sid:=vault.create_secret(cred::text,'aiq_us_storis_'||conn.id::text,'US STORIS connection credential');
    insert into tj_private.storis_credentials values(conn.id,conn.organization_id,sid,at);
   else perform vault.update_secret(sid,cred::text);update tj_private.storis_credentials set auth_type=at where connection_id=conn.id;end if;
  elsif sid is not null and oldtype is distinct from at then raise exception using errcode='22023',message='replacement_credential_required';end if;
  cfg:=jsonb_build_object('base_url',base,'auth_type',at,'api_key_header',header,'test_path',testpath,'endpoints',eps,'configured_at',clock_timestamp());
  update tj.platform_connector_connections set settings=(coalesce(conn.settings,'{}')-'destination_connection_verified')||jsonb_build_object('storis_api',cfg,'destination_connection_verified',false),credential_ref=sid::text,auth_status='not_configured',status='pending',last_error=null,updated_at=clock_timestamp() where id=conn.id;
  return jsonb_build_object('ok',true,'configured',true,'credential_stored',sid is not null,'provider_verified',false,'sync_ready',false,'resources',(select jsonb_agg(k order by k) from jsonb_object_keys(eps)k));
 elsif act in ('test','sync') then
  return jsonb_build_object('ok',false,'error',case when act='test' then 'storis_provider_verification_required' else 'storis_import_verification_required' end,'executed',false,'processed',0,'sync_ready',false,'dependencies',jsonb_build_array('destination_provider_contract','resumable_storis_importer','storis-performance-bridge'));
 elsif act<>'status' then raise exception using errcode='22023',message='unknown_action';end if;
 return jsonb_build_object('ok',true,'connection',jsonb_build_object('id',conn.id,'status',conn.status,'auth_status',case when sid is null then 'not_configured' else conn.auth_status end,'last_sync_at',conn.last_sync_at,'last_success_at',conn.last_success_at),
  'configuration',jsonb_build_object('base_url',cfg->>'base_url','auth_type',cfg->>'auth_type','api_key_header',cfg->>'api_key_header','test_path',cfg->>'test_path','endpoints',coalesce(cfg->'endpoints','{}'),'configured',sid is not null and cfg->>'base_url' is not null),
  'credential_stored',sid is not null,'provider_verified',false,'sync_ready',false);
end $$;
revoke all on function tj_private.storis_setup(jsonb) from public,anon,service_role;
grant execute on function tj_private.storis_setup(jsonb) to authenticated;
create function public.tj_storis_setup(p_body jsonb) returns jsonb language sql security invoker set search_path='' as $$select tj_private.storis_setup(p_body);$$;
revoke all on function public.tj_storis_setup(jsonb) from public,anon,service_role;
grant execute on function public.tj_storis_setup(jsonb) to authenticated;
notify pgrst,'reload schema';
