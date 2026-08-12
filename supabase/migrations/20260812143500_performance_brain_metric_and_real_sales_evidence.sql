create table if not exists public.performance_metric_competency_map (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid null references public.organizations(id) on delete cascade,
  metric_key text not null,
  competency_id uuid not null references public.performance_competencies(id) on delete cascade,
  causal_weight numeric(4,3) not null check (causal_weight > 0 and causal_weight <= 1),
  direction text not null default 'higher_better' check (direction in ('higher_better','lower_better')),
  rationale text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique nulls not distinct (organization_id,metric_key,competency_id)
);

alter table public.performance_metric_competency_map enable row level security;
create policy performance_metric_map_read on public.performance_metric_competency_map for select to authenticated
using (organization_id is null or public.is_org_member(organization_id));
create policy performance_metric_map_admin_insert on public.performance_metric_competency_map for insert to authenticated
with check (organization_id is not null and public.is_org_admin(organization_id));
create policy performance_metric_map_admin_update on public.performance_metric_competency_map for update to authenticated
using (organization_id is not null and public.is_org_admin(organization_id))
with check (organization_id is not null and public.is_org_admin(organization_id));
create policy performance_metric_map_admin_delete on public.performance_metric_competency_map for delete to authenticated
using (organization_id is not null and public.is_org_admin(organization_id));
grant select on public.performance_metric_competency_map to authenticated;

insert into public.performance_metric_competency_map (metric_key,competency_id,causal_weight,direction,rationale)
select v.metric_key,c.id,v.weight,v.direction,v.rationale
from (values
 ('floor_conversion','discovery',1.00,'higher_better','Discovery quality strongly influences conversion.'),
 ('floor_conversion','value_building',0.75,'higher_better','Value creation supports conversion.'),
 ('floor_conversion','objection_handling',0.80,'higher_better','Objection handling supports conversion.'),
 ('floor_conversion','closing',1.00,'higher_better','Closing skill directly influences conversion.'),
 ('avg_order','recommendation',0.80,'higher_better','Recommendation quality influences average order value.'),
 ('avg_order','value_building',0.90,'higher_better','Value building supports premium mix and larger baskets.'),
 ('avg_order','attachment',0.70,'higher_better','Attachments increase average order value.'),
 ('ipo','discovery',0.65,'higher_better','Discovery reveals multi-item needs.'),
 ('ipo','recommendation',0.80,'higher_better','Recommendation quality supports multi-item solutions.'),
 ('ipo','attachment',1.00,'higher_better','Items per order directly reflects attachment behaviour.'),
 ('item_value','value_building',0.90,'higher_better','Value communication supports higher-value selections.'),
 ('item_value','product_knowledge',0.60,'higher_better','Product knowledge supports confident premium recommendations.'),
 ('margin_pct','value_building',0.90,'higher_better','Value building reduces reliance on discounting.'),
 ('margin_pct','objection_handling',0.80,'higher_better','Objection handling supports margin protection.'),
 ('margin_dollars','value_building',0.70,'higher_better','Value building contributes to margin dollars.'),
 ('margin_dollars','closing',0.55,'higher_better','Closing more qualified opportunities contributes to margin dollars.'),
 ('warranty_attach','attachment',1.00,'higher_better','Warranty attachment directly reflects attachment selling.'),
 ('warranty_attach','value_building',0.75,'higher_better','Protection-plan value must be communicated credibly.'),
 ('warranty_pen_units','attachment',1.00,'higher_better','Unit penetration directly reflects protection-plan attachment.'),
 ('warranty_pen_dollars','attachment',0.90,'higher_better','Dollar penetration reflects protection-plan attachment and mix.'),
 ('greeting_time','communication',0.80,'lower_better','Prompt engagement is part of customer communication discipline.'),
 ('greeting_time','process_discipline',0.70,'lower_better','Greeting-time consistency reflects floor-process discipline.'),
 ('coaching_avg','communication',0.65,'higher_better','Coaching average is direct behavioural evidence where rubric overlap exists.'),
 ('coaching_avg','process_discipline',0.55,'higher_better','Coaching average reflects execution consistency.'),
 ('training_completion','process_discipline',0.80,'higher_better','Training completion reflects learning and process discipline.')
) as v(metric_key,competency_code,weight,direction,rationale)
join public.performance_competencies c on c.code=v.competency_code and c.organization_id is null
on conflict (organization_id,metric_key,competency_id) do update
set causal_weight=excluded.causal_weight,direction=excluded.direction,rationale=excluded.rationale,active=true;

create or replace function performance_private.process_observation()
returns trigger language plpgsql security definer
set search_path='public','performance_private','pg_temp' as $$
declare
  prior public.performance_skill_state%rowtype;
  new_score numeric(5,2); new_conf numeric(4,3); new_trend text; comp_code text; scenario_uuid uuid; alpha numeric;
begin
  select * into prior from public.performance_skill_state
  where organization_id=new.organization_id and user_id=new.user_id and competency_id=new.competency_id for update;
  alpha := least(0.30, greatest(0.00, 0.30 * new.confidence));
  if found then
    new_score := round((prior.rolling_score*(1-alpha) + new.score*alpha)::numeric,2);
    new_conf := least(1.000,round((prior.confidence + (0.10*new.confidence))::numeric,3));
    new_trend := case when new_score >= prior.rolling_score+3 then 'improving' when new_score <= prior.rolling_score-3 then 'declining' else 'stable' end;
    update public.performance_skill_state set rolling_score=new_score,confidence=new_conf,sample_size=prior.sample_size+1,trend=new_trend,last_observed_at=new.observed_at,updated_at=now() where id=prior.id;
  else
    new_score := round((75 + ((new.score-75)*new.confidence))::numeric,2);
    new_conf := least(1.000,new.confidence); new_trend := 'unknown';
    insert into public.performance_skill_state (organization_id,user_id,competency_id,rolling_score,confidence,sample_size,trend,last_observed_at)
    values (new.organization_id,new.user_id,new.competency_id,new_score,new_conf,1,new_trend,new.observed_at);
  end if;
  if new_score < 65 then
    select code into comp_code from public.performance_competencies where id=new.competency_id;
    select s.id into scenario_uuid from public.performance_scenarios s
    where s.active=true and (s.organization_id is null or s.organization_id=new.organization_id) and s.competency_weights ? comp_code
    order by case when s.organization_id=new.organization_id then 0 else 1 end,coalesce((s.competency_weights->>comp_code)::numeric,0) desc,s.difficulty asc limit 1;
    if not exists (select 1 from public.performance_interventions i where i.organization_id=new.organization_id and i.user_id=new.user_id and i.competency_id=new.competency_id and i.status in ('prescribed','in_progress','started')) then
      insert into public.performance_interventions (organization_id,user_id,competency_id,trigger_observation_id,intervention_type,status,reason,prescribed_scenario_id,baseline_score,due_at)
      values (new.organization_id,new.user_id,new.competency_id,new.id,'roleplay','prescribed','Automatically prescribed from the blended Performance Brain because this competency is below 65.',scenario_uuid,new_score,now()+interval '7 days');
    end if;
  end if;
  return new;
end; $$;
revoke all on function performance_private.process_observation() from public,anon,authenticated;

create or replace function performance_private.metric_snapshot_to_observations()
returns trigger language plpgsql security definer
set search_path='public','performance_private','pg_temp' as $$
declare m record; gap_pct numeric; metric_score numeric; obs_score numeric;
begin
  if new.user_id is null or new.target_value is null or new.target_value=0 or new.actual_value is null then return new; end if;
  for m in select map.competency_id,map.causal_weight,map.direction,map.rationale from public.performance_metric_competency_map map
    where map.metric_key=new.metric_key and map.active=true and (map.organization_id is null or map.organization_id=new.organization_id)
    order by (map.organization_id is not null) desc,map.causal_weight desc loop
    gap_pct := case when m.direction='lower_better' then ((new.target_value-new.actual_value)/abs(new.target_value))*100 else ((new.actual_value-new.target_value)/abs(new.target_value))*100 end;
    metric_score := greatest(0,least(100,75+(gap_pct*0.75)));
    obs_score := greatest(0,least(100,75+((metric_score-75)*m.causal_weight)));
    insert into public.performance_observations (organization_id,user_id,competency_id,source_type,source_id,score,confidence,evidence,metadata,observed_at)
    values (new.organization_id,new.user_id,m.competency_id,'transaction',new.id,round(obs_score,2),round((0.45*m.causal_weight)::numeric,3),new.metric_key||' performance: '||new.actual_value::text||coalesce(' vs target '||new.target_value::text,''),jsonb_build_object('channel','metric_coaching','metric_key',new.metric_key,'metric_subtype',new.metric_subtype,'period_type',new.period_type,'period_key',new.period_key,'actual',new.actual_value,'target',new.target_value,'gap_pct',round(gap_pct,2),'causal_weight',m.causal_weight,'rationale',m.rationale),new.computed_at)
    on conflict (organization_id,user_id,competency_id,source_type,source_id) where source_id is not null do nothing;
  end loop;
  return new;
end; $$;
revoke all on function performance_private.metric_snapshot_to_observations() from public,anon,authenticated;
drop trigger if exists trg_metric_snapshot_performance_brain on public.metric_snapshots;
create trigger trg_metric_snapshot_performance_brain after insert on public.metric_snapshots for each row execute function performance_private.metric_snapshot_to_observations();

create or replace function performance_private.coaching_review_to_observations()
returns trigger language plpgsql security definer
set search_path='public','performance_private','pg_temp' as $$
declare kv record; v_user uuid; comp_code text; comp_id uuid; raw_score numeric; normalized_key text; consent_ok boolean:=true;
begin
  if new.recording_id is not null then
    select r.user_id,r.consent_confirmed into v_user,consent_ok from public.sales_recordings r where r.id=new.recording_id;
    if coalesce(consent_ok,false)=false then return new; end if;
  elsif new.activity_id is not null then
    select coalesce(a.user_id,a.actor_user_id) into v_user from public.activities a where a.id=new.activity_id;
  end if;
  if v_user is null or new.kpi_scores is null or jsonb_typeof(new.kpi_scores)<>'object' then return new; end if;
  for kv in select key,value from jsonb_each(new.kpi_scores) loop
    normalized_key:=trim(both '_' from lower(regexp_replace(kv.key,'[^a-zA-Z0-9]+','_','g')));
    comp_code:=case normalized_key when 'discovery' then 'discovery' when 'needs_discovery' then 'discovery' when 'product_knowledge' then 'product_knowledge' when 'recommendation' then 'recommendation' when 'recommendation_quality' then 'recommendation' when 'product_demo' then 'recommendation' when 'feature_benefit_selling' then 'value_building' when 'value_building' then 'value_building' when 'objection_handling' then 'objection_handling' when 'closing' then 'closing' when 'closing_technique' then 'closing' when 'cross_selling' then 'attachment' when 'attachment_selling' then 'attachment' when 'greeting' then 'communication' when 'greeting_rapport' then 'communication' when 'customer_engagement' then 'communication' when 'communication' then 'communication' when 'professionalism' then 'trust' when 'trust' then 'trust' when 'follow_up' then 'process_discipline' when 'follow_up_setup' then 'process_discipline' when 'process_discipline' then 'process_discipline' else null end;
    if comp_code is null then continue; end if;
    begin raw_score:=(kv.value #>> '{}')::numeric; exception when others then continue; end;
    select c.id into comp_id from public.performance_competencies c where c.code=comp_code and c.active=true and (c.organization_id is null or c.organization_id=new.organization_id) order by (c.organization_id is not null) desc limit 1;
    if comp_id is null then continue; end if;
    insert into public.performance_observations (organization_id,user_id,competency_id,source_type,source_id,score,confidence,evidence,metadata,observed_at)
    values (new.organization_id,v_user,comp_id,case when new.recording_id is not null then 'call' else 'crm' end,new.id,greatest(0,least(100,case when raw_score<=10 then raw_score*10 else raw_score end)),0.92,coalesce(new.analysis->>'summary','AI coaching review: '||kv.key),jsonb_build_object('channel','real_sales_coaching','review_id',new.id,'recording_id',new.recording_id,'activity_id',new.activity_id,'review_kind',new.review_kind,'source_key',kv.key,'model',new.model),new.created_at)
    on conflict (organization_id,user_id,competency_id,source_type,source_id) where source_id is not null do nothing;
  end loop;
  return new;
end; $$;
revoke all on function performance_private.coaching_review_to_observations() from public,anon,authenticated;
drop trigger if exists trg_coaching_review_performance_brain on public.ai_coaching_reviews;
create trigger trg_coaching_review_performance_brain after insert on public.ai_coaching_reviews for each row execute function performance_private.coaching_review_to_observations();

create or replace view public.performance_metric_diagnostics with (security_invoker=true) as
with latest as (
 select distinct on (ms.organization_id,ms.user_id,ms.metric_key,coalesce(ms.metric_subtype,'')) ms.*
 from public.metric_snapshots ms where ms.user_id is not null
 order by ms.organization_id,ms.user_id,ms.metric_key,coalesce(ms.metric_subtype,''),ms.computed_at desc
)
select l.organization_id,l.user_id,l.metric_key,l.metric_subtype,l.period_type,l.period_key,l.actual_value,l.target_value,l.variance_pct,l.computed_at,m.competency_id,c.code competency_code,c.name competency_name,m.causal_weight,m.direction,m.rationale,
 case when l.target_value is null or l.target_value=0 then null when m.direction='lower_better' then round(((l.target_value-l.actual_value)/abs(l.target_value)*100)::numeric,2) else round(((l.actual_value-l.target_value)/abs(l.target_value)*100)::numeric,2) end as target_gap_pct
from latest l
join public.performance_metric_competency_map m on m.metric_key=l.metric_key and m.active=true and (m.organization_id is null or m.organization_id=l.organization_id)
join public.performance_competencies c on c.id=m.competency_id;
grant select on public.performance_metric_diagnostics to authenticated;