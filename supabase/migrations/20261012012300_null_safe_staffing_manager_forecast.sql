CREATE OR REPLACE FUNCTION tj_private.phase8_refresh_staffing_forecasts(p_organization_id uuid, p_days integer DEFAULT 7)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare
  v_days int := greatest(1,least(coalesce(p_days,7),14));
  v_rows int := 0;
  v_cases int := 0;
  r record;
  v_case uuid;
  v_peak_groups numeric;
  v_peak_staff numeric;
  v_conf numeric;
begin
  if tj_private.current_source_user_id() is not null and not tj.is_org_member(p_organization_id) then raise exception 'organization_access_denied'; end if;

  delete from tj.iq_staffing_predictions
  where organization_id=p_organization_id and prediction_date between current_date and current_date+v_days
    and source='historical_forward_v2';

  insert into tj.iq_staffing_predictions(
    organization_id,store_id,prediction_date,bucket_start,bucket_end,predicted_customer_groups,
    min_sales_staff,recommended_sales_staff,recommended_manager_cover,expected_wait_seconds,
    open_rotation_probability,confidence,source,model_version,created_at,created_by
  )
  select
    h.organization_id,
    h.store_id,
    d::date,
    (d::date + make_interval(hours=>h.hr))::timestamptz,
    (d::date + make_interval(hours=>h.hr+1))::timestamptz,
    greatest(0,round(avg(h.customer_groups)))::int,
    greatest(1,round(avg(greatest(h.staffing_minimum,1))))::int,
    greatest(1,round(avg(greatest(h.staffing_recommended,h.staffing_minimum,1))))::int,
    (coalesce(avg(h.customer_groups)>=5,false) or coalesce(avg(h.avg_wait_seconds)>=180,false)),
    greatest(0,round(avg(h.avg_wait_seconds)))::int,
    least(.95,greatest(.50,.50 + count(*)*.06)),
    least(.95,greatest(.50,.50 + count(*)*.06)),
    'historical_forward_v2','v2',now(),tj_private.current_source_user_id()
  from generate_series(current_date,current_date+v_days-1,interval '1 day') d
  join lateral (
    select organization_id,store_id,extract(hour from bucket_start)::int hr,customer_groups,staffing_minimum,staffing_recommended,avg_wait_seconds
    from tj.iq_hourly_traffic_summaries
    where organization_id=p_organization_id
      and extract(isodow from bucket_start)=extract(isodow from d)
      and bucket_start>=now()-interval '90 days'
  ) h on true
  group by h.organization_id,h.store_id,d::date,h.hr;
  get diagnostics v_rows=row_count;

  for r in
    select store_id,prediction_date,max(predicted_customer_groups)::numeric peak_groups,
           max(recommended_sales_staff)::numeric peak_staff,
           avg(confidence)::numeric confidence,
           max(expected_wait_seconds)::numeric wait_seconds
    from tj.iq_staffing_predictions
    where organization_id=p_organization_id and prediction_date between current_date and current_date+v_days-1
      and source='historical_forward_v2'
    group by store_id,prediction_date
  loop
    v_peak_groups:=coalesce(r.peak_groups,0); v_peak_staff:=coalesce(r.peak_staff,0); v_conf:=coalesce(r.confidence,.5);
    select id into v_case from tj.decision_cases
    where organization_id=p_organization_id and source_system='staffing_forecast_v2'
      and source_record_id=r.store_id::text||':'||r.prediction_date::text limit 1;
    if v_case is null then
      insert into tj.decision_cases(
        organization_id,module,entity_type,entity_id,title,summary,recommendation,consequence_if_ignored,
        decision_type,status,severity,customer_impact_score,urgency_score,confidence,evidence_quality,effort_score,
        priority_score,source_system,source_record_id,metadata,created_by,due_at
      ) values (
        p_organization_id,'up-system','store',r.store_id,
        'Staffing forecast for '||r.prediction_date::text,
        format('Peak forecast is %s customer groups with %s recommended sales staff.',v_peak_groups,v_peak_staff),
        'Align floor coverage to the predicted hourly demand curve and review manager coverage during peak periods.',
        'No direct CAD impact is shown until traffic-to-sales attribution is sufficient.',
        'forecast','open',case when v_peak_groups>=7 then 'high' when v_peak_groups>=5 then 'medium' else 'low' end,
        least(100,v_peak_groups*12),case when r.prediction_date<=current_date+1 then 85 else 55 end,v_conf,.80,30,
        tj.decision_calculate_priority(null,least(100,v_peak_groups*12),case when r.prediction_date<=current_date+1 then 85 else 55 end,v_conf,.80,30),
        'staffing_forecast_v2',r.store_id::text||':'||r.prediction_date::text,
        jsonb_build_object('store_id',r.store_id,'prediction_date',r.prediction_date,'peak_customer_groups',v_peak_groups,'peak_staff',v_peak_staff,'max_wait_seconds',r.wait_seconds),tj_private.current_source_user_id(),r.prediction_date::timestamptz
      ) returning id into v_case;
      v_cases:=v_cases+1;
    else
      update tj.decision_cases set
        summary=format('Peak forecast is %s customer groups with %s recommended sales staff.',v_peak_groups,v_peak_staff),
        confidence=v_conf,
        metadata=jsonb_build_object('store_id',r.store_id,'prediction_date',r.prediction_date,'peak_customer_groups',v_peak_groups,'peak_staff',v_peak_staff,'max_wait_seconds',r.wait_seconds),
        updated_at=now(),updated_by=tj_private.current_source_user_id()
      where id=v_case;
    end if;

    delete from tj.decision_predictions where decision_case_id=v_case and prediction_type='staffing_demand' and status='active';
    insert into tj.decision_predictions(
      organization_id,decision_case_id,prediction_type,horizon,baseline_value,predicted_value,predicted_delta,unit,
      probability,lower_bound,upper_bound,assumptions,model_name,model_version,generated_at,expires_at,status
    ) values (
      p_organization_id,v_case,'staffing_demand','daily',greatest(1,v_peak_staff-1),v_peak_staff,1,'sales_staff',
      v_conf,greatest(1,v_peak_staff-1),v_peak_staff+1,
      jsonb_build_object('method','same-weekday hourly historical averages','history_window_days',90,'peak_customer_groups',v_peak_groups),
      'ApplianceIQ staffing forecast','2.0',now(),(r.prediction_date+1)::timestamptz,'active'
    );
  end loop;

  return jsonb_build_object('organization_id',p_organization_id,'forecast_rows',v_rows,'decision_cases_created',v_cases,'days',v_days);
end $function$
;
