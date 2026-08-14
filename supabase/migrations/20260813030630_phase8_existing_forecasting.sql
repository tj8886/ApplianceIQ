-- Phase 8: unify and revive the forecasting assets that already exist.

create index if not exists iq_staffing_predictions_org_store_date_idx
  on public.iq_staffing_predictions(organization_id,store_id,prediction_date,bucket_start);

create or replace function public.phase8_refresh_staffing_forecasts(p_organization_id uuid, p_days integer default 7)
returns jsonb language plpgsql security definer set search_path='public','pg_temp' as $$
declare v_days int:=greatest(1,least(coalesce(p_days,7),14)); v_rows int:=0; v_cases int:=0; r record; v_case uuid; v_peak_groups numeric; v_peak_staff numeric; v_conf numeric;
begin
  if auth.uid() is not null and not public.is_org_member(p_organization_id) then raise exception 'organization_access_denied'; end if;
  delete from public.iq_staffing_predictions where organization_id=p_organization_id and prediction_date between current_date and current_date+v_days and source='historical_forward_v2';
  insert into public.iq_staffing_predictions(organization_id,store_id,prediction_date,bucket_start,bucket_end,predicted_customer_groups,min_sales_staff,recommended_sales_staff,recommended_manager_cover,expected_wait_seconds,open_rotation_probability,confidence,source,model_version,created_at,created_by)
  select h.organization_id,h.store_id,d::date,(d::date+make_interval(hours=>h.hr))::timestamptz,(d::date+make_interval(hours=>h.hr+1))::timestamptz,
    greatest(0,round(avg(h.customer_groups)))::int,greatest(1,round(avg(greatest(h.staffing_minimum,1))))::int,greatest(1,round(avg(greatest(h.staffing_recommended,h.staffing_minimum,1))))::int,
    (avg(h.customer_groups)>=5 or avg(h.avg_wait_seconds)>=180),greatest(0,round(avg(h.avg_wait_seconds)))::int,least(.95,greatest(.50,.50+count(*)*.06)),least(.95,greatest(.50,.50+count(*)*.06)),
    'historical_forward_v2','v2',now(),auth.uid()
  from generate_series(current_date,current_date+v_days-1,interval '1 day') d
  join lateral (select organization_id,store_id,extract(hour from bucket_start)::int hr,customer_groups,staffing_minimum,staffing_recommended,avg_wait_seconds from public.iq_hourly_traffic_summaries where organization_id=p_organization_id and extract(isodow from bucket_start)=extract(isodow from d) and bucket_start>=now()-interval '90 days') h on true
  group by h.organization_id,h.store_id,d::date,h.hr;
  get diagnostics v_rows=row_count;

  for r in select store_id,prediction_date,max(predicted_customer_groups)::numeric peak_groups,max(recommended_sales_staff)::numeric peak_staff,avg(confidence)::numeric confidence,max(expected_wait_seconds)::numeric wait_seconds from public.iq_staffing_predictions where organization_id=p_organization_id and prediction_date between current_date and current_date+v_days-1 and source='historical_forward_v2' group by store_id,prediction_date loop
    v_peak_groups:=coalesce(r.peak_groups,0); v_peak_staff:=coalesce(r.peak_staff,0); v_conf:=coalesce(r.confidence,.5);
    select id into v_case from public.decision_cases where organization_id=p_organization_id and source_system='staffing_forecast_v2' and source_record_id=r.store_id::text||':'||r.prediction_date::text limit 1;
    if v_case is null then
      insert into public.decision_cases(organization_id,module,entity_type,entity_id,title,summary,recommendation,consequence_if_ignored,decision_type,status,severity,customer_impact_score,urgency_score,confidence,evidence_quality,effort_score,priority_score,source_system,source_record_id,metadata,created_by,due_at)
      values(p_organization_id,'up-system','store',r.store_id,'Staffing forecast for '||r.prediction_date::text,format('Peak forecast is %s customer groups with %s recommended sales staff.',v_peak_groups,v_peak_staff),'Align floor coverage to the predicted hourly demand curve and review manager coverage during peak periods.','No direct CAD impact is shown until traffic-to-sales attribution is sufficient.','forecast','open',case when v_peak_groups>=7 then 'high' when v_peak_groups>=5 then 'medium' else 'low' end,least(100,v_peak_groups*12),case when r.prediction_date<=current_date+1 then 85 else 55 end,v_conf,.80,30,public.decision_calculate_priority(null,least(100,v_peak_groups*12),case when r.prediction_date<=current_date+1 then 85 else 55 end,v_conf,.80,30),'staffing_forecast_v2',r.store_id::text||':'||r.prediction_date::text,jsonb_build_object('store_id',r.store_id,'prediction_date',r.prediction_date,'peak_customer_groups',v_peak_groups,'peak_staff',v_peak_staff,'max_wait_seconds',r.wait_seconds),auth.uid(),r.prediction_date::timestamptz) returning id into v_case;
      v_cases:=v_cases+1;
    else
      update public.decision_cases set summary=format('Peak forecast is %s customer groups with %s recommended sales staff.',v_peak_groups,v_peak_staff),confidence=v_conf,metadata=jsonb_build_object('store_id',r.store_id,'prediction_date',r.prediction_date,'peak_customer_groups',v_peak_groups,'peak_staff',v_peak_staff,'max_wait_seconds',r.wait_seconds),updated_at=now(),updated_by=auth.uid() where id=v_case;
    end if;
    delete from public.decision_predictions where decision_case_id=v_case and prediction_type='staffing_demand' and status='active';
    insert into public.decision_predictions(organization_id,decision_case_id,prediction_type,horizon,baseline_value,predicted_value,predicted_delta,unit,probability,lower_bound,upper_bound,assumptions,model_name,model_version,generated_at,expires_at,status)
    values(p_organization_id,v_case,'staffing_demand','daily',greatest(1,v_peak_staff-1),v_peak_staff,1,'sales_staff',v_conf,greatest(1,v_peak_staff-1),v_peak_staff+1,jsonb_build_object('method','same-weekday hourly historical averages','history_window_days',90,'peak_customer_groups',v_peak_groups),'ApplianceIQ staffing forecast','2.0',now(),(r.prediction_date+1)::timestamptz,'active');
  end loop;
  return jsonb_build_object('organization_id',p_organization_id,'forecast_rows',v_rows,'decision_cases_created',v_cases,'days',v_days);
end $$;
revoke all on function public.phase8_refresh_staffing_forecasts(uuid,integer) from public,anon;
grant execute on function public.phase8_refresh_staffing_forecasts(uuid,integer) to authenticated,service_role;

create or replace function public.phase8_simulate_store(p_organization_id uuid,p_store_id uuid,p_traffic_change_pct numeric default 0,p_conversion_change_points numeric default 0,p_avg_order_change_pct numeric default 0,p_margin_change_points numeric default 0,p_staffing_change integer default 0)
returns jsonb language plpgsql stable security definer set search_path='public','pg_temp' as $$
declare v_groups numeric:=0; v_staff numeric:=0; v_wait numeric:=0; v_conv numeric:=null; v_avg numeric:=null; v_margin numeric:=null; s_groups numeric; s_staff numeric; s_conv numeric; s_avg numeric; s_margin numeric; base_rev numeric:=null; scen_rev numeric:=null; base_gp numeric:=null; scen_gp numeric:=null;
begin
  if auth.uid() is null or not public.is_org_member(p_organization_id) then raise exception 'organization_access_denied'; end if;
  if abs(coalesce(p_traffic_change_pct,0))>100 or abs(coalesce(p_conversion_change_points,0))>50 or abs(coalesce(p_avg_order_change_pct,0))>100 or abs(coalesce(p_margin_change_points,0))>50 or abs(coalesce(p_staffing_change,0))>20 then raise exception 'scenario_input_out_of_bounds'; end if;
  select coalesce(avg(customer_groups),0),coalesce(avg(greatest(staffing_recommended,1)),0),coalesce(avg(avg_wait_seconds),0) into v_groups,v_staff,v_wait from public.iq_hourly_traffic_summaries where organization_id=p_organization_id and store_id=p_store_id and bucket_start>=now()-interval '28 days';
  select max(actual_value) filter(where metric_key='floor_conversion'),max(actual_value) filter(where metric_key='avg_order'),max(actual_value) filter(where metric_key='margin_pct') into v_conv,v_avg,v_margin from public.performance_metric_diagnostics where organization_id=p_organization_id;
  s_groups:=v_groups*(1+coalesce(p_traffic_change_pct,0)/100); s_staff:=greatest(1,v_staff+coalesce(p_staffing_change,0)); s_conv:=case when v_conv is null then null else greatest(0,least(100,v_conv+coalesce(p_conversion_change_points,0))) end; s_avg:=case when v_avg is null then null else greatest(0,v_avg*(1+coalesce(p_avg_order_change_pct,0)/100)) end; s_margin:=case when v_margin is null then null else greatest(0,least(100,v_margin+coalesce(p_margin_change_points,0))) end;
  if v_conv is not null and v_avg is not null then base_rev:=v_groups*(v_conv/100)*v_avg; scen_rev:=s_groups*(s_conv/100)*s_avg; end if; if base_rev is not null and v_margin is not null then base_gp:=base_rev*(v_margin/100); scen_gp:=scen_rev*(s_margin/100); end if;
  return jsonb_build_object('scenario_type','simulation','not_actual',true,'organization_id',p_organization_id,'store_id',p_store_id,'baseline',jsonb_build_object('customer_groups_per_hour',round(v_groups,2),'recommended_staff',round(v_staff,1),'avg_wait_seconds',round(v_wait,0),'conversion_pct',v_conv,'avg_order',v_avg,'margin_pct',v_margin,'modeled_hourly_revenue',base_rev,'modeled_hourly_gross_profit',base_gp),'scenario',jsonb_build_object('customer_groups_per_hour',round(s_groups,2),'recommended_staff',s_staff,'conversion_pct',s_conv,'avg_order',s_avg,'margin_pct',s_margin,'modeled_hourly_revenue',scen_rev,'modeled_hourly_gross_profit',scen_gp),'delta',jsonb_build_object('modeled_hourly_revenue',case when scen_rev is null then null else scen_rev-base_rev end,'modeled_hourly_gross_profit',case when scen_gp is null then null else scen_gp-base_gp end,'staffing',coalesce(p_staffing_change,0)),'assumptions',jsonb_build_object('traffic_change_pct',p_traffic_change_pct,'conversion_change_points',p_conversion_change_points,'avg_order_change_pct',p_avg_order_change_pct,'margin_change_points',p_margin_change_points,'staffing_change',p_staffing_change,'traffic_baseline_days',28));
end $$;
revoke all on function public.phase8_simulate_store(uuid,uuid,numeric,numeric,numeric,numeric,integer) from public,anon;
grant execute on function public.phase8_simulate_store(uuid,uuid,numeric,numeric,numeric,numeric,integer) to authenticated;

create or replace function public.phase8_forecast_context(p_organization_id uuid) returns jsonb language sql stable security definer set search_path='public','pg_temp' as $$
select case when public.is_org_member(p_organization_id) then jsonb_build_object('stores',coalesce((select jsonb_agg(jsonb_build_object('store_id',s.store_id,'name',coalesce(l.name,'Store '||left(s.store_id::text,8))) order by coalesce(l.name,s.store_id::text)) from (select distinct store_id from public.iq_hourly_traffic_summaries where organization_id=p_organization_id) s left join public.org_locations l on l.organization_id=p_organization_id and (l.id=s.store_id or l.iq_store_id=s.store_id)),'[]'::jsonb),'forecast_status',jsonb_build_object('staffing_rows',(select count(*) from public.iq_staffing_predictions where organization_id=p_organization_id and prediction_date>=current_date and source='historical_forward_v2'),'latest_staffing_generated_at',(select max(created_at) from public.iq_staffing_predictions where organization_id=p_organization_id and source='historical_forward_v2'),'active_decision_predictions',(select count(*) from public.decision_predictions where organization_id=p_organization_id and status='active'))) else jsonb_build_object('error','organization_access_denied') end;
$$;
revoke all on function public.phase8_forecast_context(uuid) from public,anon;
grant execute on function public.phase8_forecast_context(uuid) to authenticated;

create or replace function public.phase8_run_scheduled_forecasts() returns jsonb language plpgsql security definer set search_path='public','pg_temp' as $$
declare r record; v_orgs int:=0; v_rows int:=0; v_res jsonb;
begin
  for r in select distinct organization_id from public.iq_hourly_traffic_summaries loop v_res:=public.phase8_refresh_staffing_forecasts(r.organization_id,7); v_orgs:=v_orgs+1; v_rows:=v_rows+coalesce((v_res->>'forecast_rows')::int,0); end loop;
  perform public.decision_check_expired_predictions();
  return jsonb_build_object('organizations',v_orgs,'staffing_forecast_rows',v_rows,'ran_at',now());
end $$;
revoke all on function public.phase8_run_scheduled_forecasts() from public,anon,authenticated;
grant execute on function public.phase8_run_scheduled_forecasts() to service_role;

do $$ begin perform cron.unschedule('phase8-existing-forecast-refresh'); exception when others then null; end $$;
select cron.schedule('phase8-existing-forecast-refresh','17 5 * * *',$$select public.phase8_run_scheduled_forecasts();$$);

insert into public.platform_security_rpc_allowlist(function_signature,allow_anon,allow_authenticated,rationale,reviewed_at,metadata) values
('phase8_refresh_staffing_forecasts(uuid,integer)',false,true,'Forward staffing forecast refresh; caller is restricted to organization membership.',now(),jsonb_build_object('phase',8)),
('phase8_simulate_store(uuid,uuid,numeric,numeric,numeric,numeric,integer)',false,true,'Bounded what-if simulator; organization membership required and outputs are explicitly labeled simulated.',now(),jsonb_build_object('phase',8)),
('phase8_forecast_context(uuid)',false,true,'Forecast context read for member organization only.',now(),jsonb_build_object('phase',8))
on conflict(function_signature) do update set allow_authenticated=excluded.allow_authenticated,rationale=excluded.rationale,reviewed_at=now(),metadata=excluded.metadata;
