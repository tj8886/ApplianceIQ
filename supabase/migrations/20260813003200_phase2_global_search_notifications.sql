create or replace function public.platform_global_search(p_query text, p_limit integer default 30)
returns table(entity_type text,entity_id text,entity_label text,subtitle text,module_key text,organization_id uuid,location_id uuid,rank integer)
language plpgsql security definer set search_path=public,auth as $$
declare uid uuid:=auth.uid(); org_id uuid; q text:=trim(coalesce(p_query,'')); lim integer:=least(greatest(coalesce(p_limit,30),1),50); begin
 if uid is null then raise exception 'authentication_required'; end if;
 if length(q)<2 then return; end if;
 select c.organization_id into org_id from public.platform_user_context c where c.user_id=uid;
 if org_id is null then select om.organization_id into org_id from public.organization_members om where om.user_id=uid and coalesce(om.status,'active')='active' order by om.created_at limit 1; end if;
 if org_id is null or not exists(select 1 from public.organization_members om where om.user_id=uid and om.organization_id=org_id and coalesce(om.status,'active')='active') then return; end if;
 return query with hits as (
  select 'contact'::text,c.id::text,trim(concat_ws(' ',c.first_name,c.last_name))::text,coalesce(c.email,c.phone,'')::text,'crm'::text,c.organization_id,null::uuid,case when lower(trim(concat_ws(' ',c.first_name,c.last_name)))=lower(q) then 100 when lower(trim(concat_ws(' ',c.first_name,c.last_name))) like lower(q)||'%' then 80 else 60 end r from public.contacts c where c.organization_id=org_id and (concat_ws(' ',c.first_name,c.last_name) ilike '%'||q||'%' or c.email ilike '%'||q||'%' or c.phone ilike '%'||q||'%')
  union all
  select 'product',p.id::text,coalesce(nullif(p.name,''),concat_ws(' ',p.brand,p.model)),concat_ws(' · ',p.brand,p.model,p.category),'product_iq',p.organization_id,null::uuid,case when lower(coalesce(p.model,''))=lower(q) then 100 when lower(coalesce(p.model,'')) like lower(q)||'%' then 85 else 55 end from public.products p where p.organization_id=org_id and (p.name ilike '%'||q||'%' or p.brand ilike '%'||q||'%' or p.model ilike '%'||q||'%' or p.category ilike '%'||q||'%')
  union all
  select 'transaction',t.id::text,coalesce(t.pos_transaction_id,t.id::text),concat_ws(' · ',t.source_system,to_char(t.transaction_date,'YYYY-MM-DD'),coalesce(t.currency_code,'')||' '||coalesce(t.transaction_amount,0)::text),'command_center',t.organization_id,t.store_id,case when lower(coalesce(t.pos_transaction_id,''))=lower(q) then 100 else 50 end from public.iq_pos_transactions t where t.organization_id=org_id and (t.pos_transaction_id ilike '%'||q||'%' or t.customer_external_id ilike '%'||q||'%' or t.salesperson_external_id ilike '%'||q||'%')
 ) select h.entity_type,h.entity_id,h.entity_label,h.subtitle,h.module_key,h.organization_id,h.location_id,h.r from hits h order by h.r desc,h.entity_label limit lim;
end $$;
revoke all on function public.platform_global_search(text,integer) from public,anon;
grant execute on function public.platform_global_search(text,integer) to authenticated,service_role;

create or replace function public.platform_mark_notification_read(p_notification_id uuid) returns boolean language plpgsql security definer set search_path=public,auth as $$ begin
 if auth.uid() is null then raise exception 'authentication_required'; end if;
 update public.crm_notifications set is_read=true,read_at=coalesce(read_at,now()) where id=p_notification_id and user_id=auth.uid();
 return found;
end $$;
revoke all on function public.platform_mark_notification_read(uuid) from public,anon;
grant execute on function public.platform_mark_notification_read(uuid) to authenticated,service_role;
