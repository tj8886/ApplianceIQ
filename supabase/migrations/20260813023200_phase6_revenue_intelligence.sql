create table if not exists public.phase6_revenue_opportunities (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  opportunity_key text not null,
  opportunity_type text not null,
  subject_type text not null,
  subject_id uuid,
  metric_key text,
  title text not null,
  diagnosis text not null,
  recommended_action text not null,
  action_module text not null,
  actual_value numeric,
  target_value numeric,
  severity_pct numeric not null default 0,
  estimated_revenue_impact numeric,
  estimated_margin_impact numeric,
  impact_confidence numeric not null default 0 check (impact_confidence between 0 and 1),
  priority_score numeric not null default 0,
  evidence jsonb not null default '{}'::jsonb,
  financial_model jsonb not null default '{}'::jsonb,
  status text not null default 'open' check (status in ('open','accepted','in_progress','resolved','dismissed')),
  manager_assignment_id uuid references public.ai_manager_assignments(id) on delete set null,
  first_detected_at timestamptz not null default now(),
  last_detected_at timestamptz not null default now(),
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(organization_id,opportunity_key)
);

alter table public.phase6_revenue_opportunities enable row level security;
revoke all on public.phase6_revenue_opportunities from anon, authenticated;
create index if not exists phase6_revenue_opportunities_org_priority_idx on public.phase6_revenue_opportunities(organization_id,status,priority_score desc);
create index if not exists phase6_revenue_opportunities_subject_idx on public.phase6_revenue_opportunities(organization_id,subject_type,subject_id);

create or replace function public.phase6_refresh_revenue_opportunities(p_organization_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_now timestamptz:=now(); v_upserts int:=0; v_closed int:=0;
begin
  if auth.uid() is not null and not public.is_org_admin(p_organization_id) then raise exception 'Organization admin required'; end if;
  with latest_diag as (
    select distinct on (d.user_id,d.metric_key) d.user_id,d.metric_key,d.actual_value,d.target_value,d.target_gap_pct,d.competency_name,d.rationale,d.computed_at,
      greatest(0,case when d.target_value is null or d.actual_value is null then 0 when d.direction='lower_is_better' then 100.0*(d.actual_value-d.target_value)/nullif(abs(d.target_value),0) else 100.0*(d.target_value-d.actual_value)/nullif(abs(d.target_value),0) end) severity
    from public.performance_metric_diagnostics d where d.organization_id=p_organization_id order by d.user_id,d.metric_key,d.computed_at desc
  ), gaps as (
    select *, case when metric_key='margin_dollars' and actual_value<target_value then target_value-actual_value else null end margin_impact,
      case when metric_key in ('floor_conversion','warranty_attach','warranty_pen_units','warranty_pen_dollars','margin_pct','margin_dollars','avg_order','ipo') then 'ai-coach' else 'academy' end module_key
    from latest_diag where severity>0
  ), upserted as (
    insert into public.phase6_revenue_opportunities(organization_id,opportunity_key,opportunity_type,subject_type,subject_id,metric_key,title,diagnosis,recommended_action,action_module,actual_value,target_value,severity_pct,estimated_margin_impact,impact_confidence,priority_score,evidence,financial_model,last_detected_at,updated_at)
    select p_organization_id,'performance:'||user_id::text||':'||metric_key,'performance_gap','employee',user_id,metric_key,initcap(replace(metric_key,'_',' '))||' opportunity',coalesce(rationale,'Performance is below target for '||replace(metric_key,'_',' ')),case when module_key='ai-coach' then 'Open adaptive coaching for this employee and address the measured performance gap.' else 'Assign targeted learning and remeasure performance.' end,module_key,actual_value,target_value,round(severity,2),margin_impact,case when margin_impact is not null then 0.90 else 0.45 end,round(least(100,severity+case when margin_impact is not null then least(35,margin_impact/250.0) else 0 end),2),jsonb_strip_nulls(jsonb_build_object('competency',competency_name,'computed_at',computed_at,'source','performance_metric_diagnostics')),case when margin_impact is not null then jsonb_build_object('method','direct_target_gap','currency','CAD','formula','target_value - actual_value') else jsonb_build_object('method','severity_only','reason','Insufficient transactional evidence for defensible dollar estimate') end,v_now,v_now from gaps
    on conflict(organization_id,opportunity_key) do update set title=excluded.title,diagnosis=excluded.diagnosis,recommended_action=excluded.recommended_action,action_module=excluded.action_module,actual_value=excluded.actual_value,target_value=excluded.target_value,severity_pct=excluded.severity_pct,estimated_margin_impact=excluded.estimated_margin_impact,impact_confidence=excluded.impact_confidence,priority_score=excluded.priority_score,evidence=excluded.evidence,financial_model=excluded.financial_model,last_detected_at=v_now,updated_at=v_now,status=case when public.phase6_revenue_opportunities.status in ('resolved','dismissed') then 'open' else public.phase6_revenue_opportunities.status end,resolved_at=null returning 1
  ) select count(*) into v_upserts from upserted;
  with crm as (
    select o.id,o.title,o.opportunity_value,o.probability,o.owner_id,o.stage,o.expected_close_date,coalesce(h.health_score,50) health_score,coalesce(h.reasoning,h.ai_comment,'Open CRM opportunity requiring follow-up') reasoning
    from public.aicrm_opportunities o left join public.aicrm_opportunity_health h on h.opportunity_id=o.id and h.organization_id=o.organization_id
    where o.organization_id=p_organization_id and coalesce(o.status,'open') not in ('won','lost','closed')
  ), u as (
    insert into public.phase6_revenue_opportunities(organization_id,opportunity_key,opportunity_type,subject_type,subject_id,title,diagnosis,recommended_action,action_module,estimated_revenue_impact,impact_confidence,priority_score,evidence,financial_model,last_detected_at,updated_at)
    select p_organization_id,'crm:'||id::text,'crm_pipeline','opportunity',id,title,reasoning,'Open the CRM opportunity, confirm next action and protect the expected close.','crm',opportunity_value*coalesce(probability,50)/100.0,case when probability is null then 0.55 else 0.75 end,round(least(100,(100-health_score)*0.6+coalesce(probability,50)*0.25+least(25,coalesce(opportunity_value,0)/5000.0)),2),jsonb_strip_nulls(jsonb_build_object('stage',stage,'owner_id',owner_id,'expected_close_date',expected_close_date,'health_score',health_score)),jsonb_build_object('method','probability_weighted_pipeline','formula','opportunity_value * probability'),v_now,v_now from crm
    on conflict(organization_id,opportunity_key) do update set title=excluded.title,diagnosis=excluded.diagnosis,recommended_action=excluded.recommended_action,estimated_revenue_impact=excluded.estimated_revenue_impact,impact_confidence=excluded.impact_confidence,priority_score=excluded.priority_score,evidence=excluded.evidence,financial_model=excluded.financial_model,last_detected_at=v_now,updated_at=v_now,status=case when public.phase6_revenue_opportunities.status in ('resolved','dismissed') then 'open' else public.phase6_revenue_opportunities.status end,resolved_at=null returning 1
  ) select v_upserts+count(*) into v_upserts from u;
  update public.phase6_revenue_opportunities set status='resolved',resolved_at=v_now,updated_at=v_now where organization_id=p_organization_id and status in ('open','accepted','in_progress') and last_detected_at<v_now-interval '1 minute';
  get diagnostics v_closed=row_count;
  return jsonb_build_object('status','ok','upserted',v_upserts,'resolved_stale',v_closed,'refreshed_at',v_now);
end $$;
revoke all on function public.phase6_refresh_revenue_opportunities(uuid) from public,anon;
grant execute on function public.phase6_refresh_revenue_opportunities(uuid) to authenticated,service_role;

create or replace function public.phase6_command_center(p_organization_id uuid,p_limit int default 25)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_result jsonb;
begin
  if auth.uid() is not null and not public.is_org_admin(p_organization_id) then raise exception 'Organization admin required'; end if;
  select jsonb_build_object('summary',jsonb_build_object('open_actions',count(*) filter(where status in ('open','accepted','in_progress')),'estimated_revenue_impact',coalesce(sum(estimated_revenue_impact) filter(where status in ('open','accepted','in_progress')),0),'estimated_margin_impact',coalesce(sum(estimated_margin_impact) filter(where status in ('open','accepted','in_progress')),0),'high_priority',count(*) filter(where status in ('open','accepted','in_progress') and priority_score>=50),'financially_quantified',count(*) filter(where status in ('open','accepted','in_progress') and (estimated_revenue_impact is not null or estimated_margin_impact is not null))),'actions',coalesce((select jsonb_agg(x order by x.priority_score desc,x.estimated_margin_impact desc nulls last,x.estimated_revenue_impact desc nulls last) from (select id,opportunity_type,subject_type,subject_id,metric_key,title,diagnosis,recommended_action,action_module,actual_value,target_value,severity_pct,estimated_revenue_impact,estimated_margin_impact,impact_confidence,priority_score,evidence,financial_model,status,manager_assignment_id,last_detected_at from public.phase6_revenue_opportunities where organization_id=p_organization_id and status in ('open','accepted','in_progress') order by priority_score desc limit greatest(1,least(coalesce(p_limit,25),100))) x),'[]'::jsonb)) into v_result from public.phase6_revenue_opportunities where organization_id=p_organization_id;
  return v_result;
end $$;
revoke all on function public.phase6_command_center(uuid,int) from public,anon;
grant execute on function public.phase6_command_center(uuid,int) to authenticated,service_role;

create or replace function public.phase6_accept_action(p_opportunity_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_o public.phase6_revenue_opportunities%rowtype; v_assignment uuid; v_actor uuid:=auth.uid();
begin
  select * into v_o from public.phase6_revenue_opportunities where id=p_opportunity_id;
  if v_o.id is null then raise exception 'Opportunity not found'; end if;
  if v_actor is null or not public.is_org_admin(v_o.organization_id) then raise exception 'Organization admin required'; end if;
  if v_o.manager_assignment_id is not null then return jsonb_build_object('status','already_assigned','assignment_id',v_o.manager_assignment_id); end if;
  insert into public.ai_manager_assignments(organization_id,title,instructions,assigned_by,priority,status,due_at,source,metadata,assigned_role)
  values(v_o.organization_id,v_o.title,v_o.recommended_action,v_actor,case when v_o.priority_score>=70 then 'critical' when v_o.priority_score>=45 then 'high' else 'medium' end,'open',now()+interval '1 day','phase6_revenue_intelligence',jsonb_build_object('phase6_opportunity_id',v_o.id,'estimated_revenue_impact',v_o.estimated_revenue_impact,'estimated_margin_impact',v_o.estimated_margin_impact,'action_module',v_o.action_module,'subject_type',v_o.subject_type,'subject_id',v_o.subject_id),'manager') returning id into v_assignment;
  update public.phase6_revenue_opportunities set status='accepted',manager_assignment_id=v_assignment,updated_at=now() where id=v_o.id;
  return jsonb_build_object('status','accepted','assignment_id',v_assignment);
end $$;
revoke all on function public.phase6_accept_action(uuid) from public,anon;
grant execute on function public.phase6_accept_action(uuid) to authenticated;
