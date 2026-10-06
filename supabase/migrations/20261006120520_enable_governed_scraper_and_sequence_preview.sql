-- Native identities only. Shared raw staging requires a global publisher role;
-- this endpoint does not write curated ProductIQ or the public shopper catalog.
create table tj_private.scraper_write_audit (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references tj.organizations(id),
 source_user_id uuid not null references tj.source_auth_users(id),
 table_name text not null, operation text not null,
 affected_count integer not null check (affected_count between 0 and 100),
 request_hash text not null, created_at timestamptz not null default now()
);
create index scraper_write_audit_org_idx on tj_private.scraper_write_audit(organization_id,created_at);
create index scraper_write_audit_actor_idx on tj_private.scraper_write_audit(source_user_id,created_at);
alter table tj_private.scraper_write_audit enable row level security;
revoke all on tj_private.scraper_write_audit from public,anon,authenticated,service_role;

create function tj_private.scraper_write(p_body jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 actor uuid := tj_private.current_source_user_id(); org uuid;
 tab text; op text; rel regclass; rows jsonb; item jsonb; matches jsonb;
 cols text[]; conflicts text[]; keys text[]; col text; list text; projections text; assignments text;
 suffix text := ''; ids uuid[]; output jsonb := '[]'; changed jsonb; answer jsonb;
begin
 if actor is null or not tj_private.has_active_mapped_org() or not exists (
  select 1 from tj.product_iq_platform_roles r where r.user_id=actor and r.organization_id is null
   and r.status='active' and (r.expires_at is null or r.expires_at>now())
   and r.role in ('data_publisher','product_iq_super_admin','super_admin')
 ) then raise exception using errcode='42501',message='scraper_access_denied'; end if;
 select m.organization_id into org from tj.organization_members m join tj.organizations o on o.id=m.organization_id
 where m.user_id=actor and m.status='active' and o.status='active' and o.deleted_at is null order by m.organization_id limit 1;
 if jsonb_typeof(p_body) is distinct from 'object' or octet_length(p_body::text)>1048576
  or exists(select 1 from jsonb_object_keys(p_body) k where k not in ('table','operation','data','conflict_columns','match'))
 then raise exception using errcode='22023',message='invalid_request'; end if;
 tab := p_body->>'table'; op := p_body->>'operation';
 if tab is null or op is null or op not in ('insert','upsert','update','delete') then raise exception using errcode='22023',message='invalid_operation'; end if;
 if tab not in ('retailer_discovered_products','retailer_crawl_runs','retailer_brand_pages','brand_category_pages','pim_scrape_runs','pim_brand_content','scraper_retailer_sources') then
  return jsonb_build_object('ok',false,'error','governed_catalog_write_required','count',0,'verified_catalog_updated',false);
 end if;
 if (op='delete' and tab<>'retailer_discovered_products') or (tab='scraper_retailer_sources' and op<>'update') then
  raise exception using errcode='22023',message='operation_not_allowed'; end if;
 rel := to_regclass(format('tj.%I',tab));
 select array_agg(a.attname::text) into cols from pg_catalog.pg_attribute a where a.attrelid=rel and a.attnum>0 and not a.attisdropped
  and a.attgenerated='' and a.attidentity='' and a.attname not in ('organization_id','aiq_product_id','created_by','updated_by','user_id');
 matches := p_body->'match';
 -- Validate all match keys and values before locking or mutating rows.
 if op in ('update','delete') then
  if jsonb_typeof(matches) is distinct from 'object' or matches='{}'::jsonb then raise exception using errcode='22023',message='match_required'; end if;
  for col,item in select key,value from jsonb_each(matches) loop
   if not col=any(cols) or col !~ '^[a-z][a-z0-9_]*$' or jsonb_typeof(item)='object' then raise exception using errcode='22023',message='invalid_match'; end if;
   if jsonb_typeof(item)='array' and (jsonb_array_length(item) not between 1 and 100 or exists(select 1 from jsonb_array_elements(item) v where jsonb_typeof(v) in ('object','array'))) then
    raise exception using errcode='22023',message='invalid_match'; end if;
  end loop;
 elsif matches is not null then raise exception using errcode='22023',message='unexpected_match'; end if;
 if op='upsert' then
  if p_body ? 'conflict_columns' and jsonb_typeof(p_body->'conflict_columns')<>'string' then raise exception using errcode='22023',message='invalid_conflict'; end if;
  conflicts := regexp_split_to_array(coalesce(p_body->>'conflict_columns','id'),'\s*,\s*');
  if not exists(select 1 from pg_catalog.pg_index i where i.indrelid=rel and i.indisunique and i.indisvalid and i.indpred is null and i.indexprs is null
   and (select array_agg(a.attname::text order by k.ord) from unnest(i.indkey::smallint[]) with ordinality k(attnum,ord)
    join pg_catalog.pg_attribute a on a.attrelid=rel and a.attnum=k.attnum where k.ord<=i.indnkeyatts)=conflicts)
   or exists(select 1 from unnest(conflicts) c where c !~ '^[a-z][a-z0-9_]*$' or not c=any(cols)) then
   raise exception using errcode='22023',message='invalid_conflict'; end if;
 elsif p_body ? 'conflict_columns' then raise exception using errcode='22023',message='unexpected_conflict'; end if;
 if op<>'delete' then
  rows := case when jsonb_typeof(p_body->'data')='object' then jsonb_build_array(p_body->'data') else p_body->'data' end;
  if jsonb_typeof(rows) is distinct from 'array' or jsonb_array_length(rows) not between 1 and 100 or (op='update' and jsonb_array_length(rows)<>1) then
   raise exception using errcode='22023',message='invalid_data'; end if;
  for item in select value from jsonb_array_elements(rows) loop
   if jsonb_typeof(item)<>'object' or item='{}'::jsonb then raise exception using errcode='22023',message='invalid_data'; end if;
   if exists(select 1 from jsonb_object_keys(item) k where k !~ '^[a-z][a-z0-9_]*$' or not k=any(cols) or (op='update' and k='id')) then
    raise exception using errcode='22023',message='column_not_allowed'; end if;
  end loop;
 end if;
 -- Lock a bounded target set; the entire request and its audit are atomic.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('tj.scraper-write.'||tab,0));
 if op in ('update','delete') then
  execute format('select array_agg(q.id) from (select t.id from tj.%I t where not exists (
   select 1 from jsonb_each($1) m where case when jsonb_typeof(m.value)=''array'' then
    not (m.value @> jsonb_build_array(to_jsonb(t)->m.key)) else (to_jsonb(t)->m.key) is distinct from m.value end)
   order by t.id limit 101 for update) q',tab) into ids using matches;
  if coalesce(cardinality(ids),0)>100 then raise exception using errcode='54000',message='match_too_broad'; end if;
 end if;
 if op='delete' then
  execute format('with changed as (delete from tj.%I t where t.id=any($1) returning to_jsonb(t) j) select coalesce(jsonb_agg(j),''[]''::jsonb) from changed',tab) into output using ids;
 else
  for item in select value from jsonb_array_elements(rows) loop
   select array_agg(k order by k),string_agg(format('%I',k),',' order by k),string_agg(format('x.%I',k),',' order by k)
    into keys,list,projections from jsonb_object_keys(item) k;
   if op='update' then
    select string_agg(format('%I=x.%I',k,k),',' order by k) into assignments from unnest(keys) k;
    execute format('with changed as (update tj.%I t set %s from jsonb_populate_record(null::tj.%I,$1) x where t.id=any($2) returning to_jsonb(t) j) select coalesce(jsonb_agg(j),''[]''::jsonb) from changed',tab,assignments,tab) into changed using item,ids;
   else
    suffix := '';
    if op='upsert' then
     select string_agg(format('%I=excluded.%I',k,k),',' order by k) into assignments from unnest(keys) k where k<>'id' and not k=any(conflicts);
     suffix := format(' on conflict (%s) %s',(select string_agg(format('%I',c),',') from unnest(conflicts)c),case when assignments is null then 'do nothing' else 'do update set '||assignments end);
    end if;
    execute format('with changed as (insert into tj.%I as t (%s) select %s from jsonb_populate_record(null::tj.%I,$1) x %s returning to_jsonb(t) j) select coalesce(jsonb_agg(j),''[]''::jsonb) from changed',tab,list,projections,tab,suffix) into changed using item;
   end if;
   output := output||changed;
  end loop;
 end if;
 answer := jsonb_build_object('ok',true,'table',tab,'operation',op,'count',jsonb_array_length(output),'data',output,'requires_review',true,'verified_catalog_updated',false);
 if octet_length(answer::text)>2097152 then raise exception using errcode='54000',message='response_too_large'; end if;
 insert into tj_private.scraper_write_audit(organization_id,source_user_id,table_name,operation,affected_count,request_hash)
 values(org,actor,tab,op,jsonb_array_length(output),md5(p_body::text));
 return answer;
end $$;
revoke all on function tj_private.scraper_write(jsonb) from public,anon,authenticated,service_role;
grant execute on function tj_private.scraper_write(jsonb) to authenticated;
create function public.tj_scraper_write(p_body jsonb) returns jsonb language sql security invoker set search_path='' as $$ select tj_private.scraper_write(p_body); $$;
revoke all on function public.tj_scraper_write(jsonb) from public,anon,service_role;
grant execute on function public.tj_scraper_write(jsonb) to authenticated;

-- Sequence migration is deliberately a tenant-scoped metadata preview only.
create function tj_private.sequence_preview(p_body jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid := tj_private.current_source_user_id(); org uuid; lim integer; after_id uuid; rows jsonb; action text;
begin
 if actor is null then raise exception using errcode='42501',message='sequence_access_denied'; end if;
 if jsonb_typeof(p_body) is distinct from 'object' or octet_length(p_body::text)>8192
  or exists(select 1 from jsonb_object_keys(p_body) k where k not in ('organization_id','action','limit','cursor')) then
  raise exception using errcode='22023',message='invalid_request'; end if;
 org := (p_body->>'organization_id')::uuid;
 if org is null or not exists(select 1 from tj.organization_members m join tj.organizations o on o.id=m.organization_id
  where m.organization_id=org and m.user_id=actor and m.status='active' and m.role in ('owner','admin','super_admin') and o.status='active' and o.deleted_at is null)
 then raise exception using errcode='42501',message='sequence_access_denied'; end if;
 action := coalesce(p_body->>'action','preview');
 if action='execute' then return jsonb_build_object('ok',false,'error','sequence_sending_verification_required','sent',0,'executed',false,'send_enabled',false); end if;
 if action<>'preview' then raise exception using errcode='22023',message='invalid_action'; end if;
 lim := coalesce((p_body->>'limit')::integer,25); after_id := (p_body->>'cursor')::uuid;
 if lim not between 1 and 100 then raise exception using errcode='22023',message='invalid_limit'; end if;
 select coalesce(jsonb_agg(to_jsonb(q) order by q.enrollment_id),'[]') into rows from (
  select e.id enrollment_id,e.campaign_id,e.contact_id,e.current_step step_number,e.eligibility_status,
   coalesce(s.requires_manual_approval,true) requires_manual_approval
  from tj.aicrm_sequence_enrollments e
  join tj.aicrm_sequence_steps s on s.campaign_id=e.campaign_id and s.step_number=e.current_step and s.organization_id=org
  join tj.aicrm_outreach_campaigns c on c.id=e.campaign_id and c.organization_id=org and c.status='active'
  join tj.aicrm_contacts p on p.id=e.contact_id and p.organization_id=org and p.account_id=e.account_id and p.deleted_at is null and p.archived_at is null
  join tj.aicrm_accounts a on a.id=e.account_id and a.organization_id=org and a.deleted_at is null and not coalesce(a.do_not_contact,false)
  where e.organization_id=org and e.status='active' and e.paused_at is null and e.completed_at is null and e.unenrolled_at is null
   and e.next_action_at is not null and e.next_action_at<=now() and (after_id is null or e.id>after_id)
   and s.delay_days between 0 and 365 and (e.last_contacted_at is null or e.last_contacted_at+make_interval(days=>s.delay_days)<=now())
   and s.channel='email' and length(btrim(coalesce(s.subject_template,'')))>0 and length(btrim(coalesce(s.body_template,'')))>0
   and length(btrim(coalesce(p.email::text,'')))>0
  order by e.id limit lim+1
 ) q;
 return jsonb_build_object('ok',true,'preview_only',true,'send_enabled',false,'sent',0,'executed',false,
  'count',least(jsonb_array_length(rows),lim),'data',(select coalesce(jsonb_agg(v order by ord),'[]') from jsonb_array_elements(rows) with ordinality x(v,ord) where ord<=lim),
  'next_cursor',case when jsonb_array_length(rows)>lim then rows->(lim-1)->>'enrollment_id' else null end);
end $$;
revoke all on function tj_private.sequence_preview(jsonb) from public,anon,authenticated,service_role;
grant execute on function tj_private.sequence_preview(jsonb) to authenticated;
create function public.tj_sequence_preview(p_body jsonb) returns jsonb language sql security invoker set search_path='' as $$ select tj_private.sequence_preview(p_body); $$;
revoke all on function public.tj_sequence_preview(jsonb) from public,anon,service_role;
grant execute on function public.tj_sequence_preview(jsonb) to authenticated;
notify pgrst,'reload schema';
