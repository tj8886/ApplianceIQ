-- Scoped metadata readiness only; caller financial payloads are not verified ingestion evidence.
create function tj_private.retailvantage_bridge_preflight(p_body jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=tj_private.current_source_user_id();c tj.platform_connector_connections%rowtype;
 action text;
begin
 if actor is null then raise exception using errcode='42501',message='connection_access_denied';end if;
 if jsonb_typeof(p_body) is distinct from 'object' or octet_length(p_body::text)>8192
  or exists(select 1 from jsonb_object_keys(p_body)k where k not in ('connection_id','organization_id','action'))
  or exists(select 1 from jsonb_each(p_body)e where jsonb_typeof(e.value)<>'string') then raise exception using errcode='22023',message='invalid_request';end if;
 select * into c from tj.platform_connector_connections where id=(p_body->>'connection_id')::uuid;
 if c.id is null or not exists(select 1 from tj.organization_members m join tj.organizations o on o.id=m.organization_id
  where m.organization_id=c.organization_id and m.user_id=actor and m.status='active' and m.role in ('owner','admin','super_admin') and o.status='active' and o.deleted_at is null)
  or (p_body ? 'organization_id' and (p_body->>'organization_id')::uuid<>c.organization_id) then raise exception using errcode='42501',message='connection_access_denied';end if;
 if not exists(select 1 from tj.platform_connectors p where p.id=c.connector_id and p.key='retailvantage') then raise exception using errcode='22023',message='not_retailvantage_connection';end if;
 action:=coalesce(p_body->>'action','bridge');
 if action not in ('status','bridge') then raise exception using errcode='22023',message='invalid_action';end if;
 return jsonb_build_object('ok',action='status','error',case when action<>'status' then 'retailvantage_bridge_verification_required' else null end,
  'connection_id',c.id,'organization_id',c.organization_id,'preflight_only',true,'bridge_enabled',false,'executed',false,'transactions_processed',0,'line_facts_created',0,'metrics_refreshed',false,
  'blockers',jsonb_build_array('verified_ingestion_event_provenance_and_identity_required','reviewed_connection_scoped_location_and_employee_mappings_required','strict_dates_currency_numeric_and_revenue_cost_contract_required','connection_scoped_idempotent_transaction_and_line_identity_required','atomic_transaction_line_sales_fact_reconciliation_required','unknown_cost_and_warranty_opportunity_semantics_required','reviewed_scoped_metric_refresh_required'));

end $$;
revoke all on function tj_private.retailvantage_bridge_preflight(jsonb) from public,anon,service_role;
grant execute on function tj_private.retailvantage_bridge_preflight(jsonb) to authenticated;
create function public.tj_retailvantage_bridge_preflight(p_body jsonb) returns jsonb language sql security invoker set search_path='' as $$select tj_private.retailvantage_bridge_preflight(p_body);$$;
revoke all on function public.tj_retailvantage_bridge_preflight(jsonb) from public,anon,service_role;
grant execute on function public.tj_retailvantage_bridge_preflight(jsonb) to authenticated;
notify pgrst,'reload schema';
