-- Phase 5: Adaptive Coaching Engine
-- Mirrors the production Phase 5 schema and governed RPC layer.

create table if not exists public.ai_adaptive_coaching_profiles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null,
  challenge_level smallint not null default 2 check (challenge_level between 1 and 5),
  coaching_intensity text not null default 'standard' check (coaching_intensity in ('light','standard','intensive')),
  learning_velocity numeric,
  roleplay_score numeric,
  skill_score numeric,
  recent_success_rate numeric,
  evidence_count integer not null default 0,
  confidence numeric not null default 0 check (confidence between 0 and 1),
  preferred_sequence jsonb not null default '["lesson","roleplay","floor_challenge","review"]'::jsonb,
  preferred_strategy text not null default 'foundation',
  rationale jsonb not null default '{}'::jsonb,
  last_computed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id,user_id)
);

create table if not exists public.ai_coaching_strategy_performance (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  metric_key text not null default '',
  skill_id uuid references public.ai_skill_definitions(id) on delete set null,
  strategy_key text not null,
  difficulty_level smallint not null check (difficulty_level between 1 and 5),
  attempts integer not null default 0,
  successes integer not null default 0,
  failures integer not null default 0,
  avg_delta numeric,
  posterior_success numeric not null default 0.5,
  confidence numeric not null default 0 check (confidence between 0 and 1),
  last_outcome_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists aiq_strategy_perf_cell_uq
  on public.ai_coaching_strategy_performance(
    organization_id,
    metric_key,
    coalesce(skill_id,'00000000-0000-0000-0000-000000000000'::uuid),
    strategy_key,
    difficulty_level
  );

create table if not exists public.ai_adaptive_coaching_decisions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null,
  intervention_id uuid not null unique references public.ai_coaching_interventions(id) on delete cascade,
  evaluation_id uuid references public.ai_intervention_evaluations(id) on delete set null,
  decision_type text not null default 'coaching_strategy',
  strategy_key text not null,
  difficulty_level smallint not null check (difficulty_level between 1 and 5),
  sequence jsonb not null,
  target_score numeric,
  rationale jsonb not null default '{}'::jsonb,
  confidence numeric not null default 0 check (confidence between 0 and 1),
  exploration boolean not null default false,
  outcome_success boolean,
  outcome_delta numeric,
  outcome_id uuid references public.intelligence_outcomes(id) on delete set null,
  learned_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.ai_adaptive_coaching_profiles enable row level security;
alter table public.ai_coaching_strategy_performance enable row level security;
alter table public.ai_adaptive_coaching_decisions enable row level security;

revoke all on public.ai_adaptive_coaching_profiles from anon, authenticated;
revoke all on public.ai_coaching_strategy_performance from anon, authenticated;
revoke all on public.ai_adaptive_coaching_decisions from anon, authenticated;

create or replace function public.phase5_refresh_profile(p_organization_id uuid, p_user_id uuid)
returns jsonb language plpgsql security definer set search_path='public','pg_temp' as $$
declare v_role numeric; v_skill numeric; v_success numeric; v_velocity numeric; v_evidence int; v_level int; v_intensity text; v_sequence jsonb; v_strategy text; v_conf numeric; v_result jsonb;
begin
 if auth.uid() is not null then
  if not public.is_org_member(p_organization_id) then raise exception 'Not a member of this organization'; end if;
  if auth.uid()<>p_user_id and not public.is_org_admin(p_organization_id) then raise exception 'Not authorized'; end if;
 end if;
 select round(avg(session_score),2),count(*) into v_role,v_evidence from public.ai_roleplay_sessions where organization_id=p_organization_id and user_id=p_user_id and status='completed' and session_score is not null and created_at>=now()-interval '90 days';
 select round(avg(score),2) into v_skill from public.ai_rep_skill_profiles where organization_id=p_organization_id and user_id=p_user_id;
 select round(100.0*count(*) filter(where success is true)/nullif(count(*) filter(where success is not null),0),2),round(avg(delta),2)
 into v_success,v_velocity from (select success,delta from public.ai_intervention_evaluations e join public.ai_coaching_interventions i on i.id=e.intervention_id where e.organization_id=p_organization_id and i.user_id=p_user_id and e.status='measured' order by e.measured_at desc nulls last limit 10)x;
 v_evidence:=coalesce(v_evidence,0)+(select count(*) from public.ai_rep_skill_profiles where organization_id=p_organization_id and user_id=p_user_id)+(select count(*) from public.ai_intervention_evaluations e join public.ai_coaching_interventions i on i.id=e.intervention_id where e.organization_id=p_organization_id and i.user_id=p_user_id and e.status='measured');
 v_level:=case when coalesce(v_role,v_skill,0)>=90 then 5 when coalesce(v_role,v_skill,0)>=80 then 4 when coalesce(v_role,v_skill,0)>=68 then 3 when coalesce(v_role,v_skill,0)>=52 then 2 else 1 end;
 if v_evidence<3 then v_level:=2; end if;
 v_intensity:=case when v_success is not null and v_success<40 then 'intensive' when v_success is not null and v_success>=75 then 'light' else 'standard' end;
 if v_level>=4 then v_strategy:='field_first'; v_sequence:='["roleplay","floor_challenge","lesson","review"]'::jsonb;
 elsif coalesce(v_role,0)<60 and v_role is not null then v_strategy:='practice_heavy'; v_sequence:='["lesson","roleplay","roleplay","review"]'::jsonb;
 elsif v_intensity='intensive' then v_strategy:='reinforce'; v_sequence:='["lesson","roleplay","floor_challenge","review"]'::jsonb;
 else v_strategy:='foundation'; v_sequence:='["lesson","roleplay","floor_challenge","review"]'::jsonb; end if;
 v_conf:=least(0.95,round(coalesce(v_evidence,0)::numeric/12.0,3));
 insert into public.ai_adaptive_coaching_profiles(organization_id,user_id,challenge_level,coaching_intensity,learning_velocity,roleplay_score,skill_score,recent_success_rate,evidence_count,confidence,preferred_sequence,preferred_strategy,rationale,last_computed_at,updated_at)
 values(p_organization_id,p_user_id,v_level,v_intensity,v_velocity,v_role,v_skill,v_success,v_evidence,v_conf,v_sequence,v_strategy,jsonb_strip_nulls(jsonb_build_object('cold_start',v_evidence<3,'roleplay_score',v_role,'skill_score',v_skill,'recent_success_rate',v_success,'learning_velocity',v_velocity)),now(),now())
 on conflict(organization_id,user_id) do update set challenge_level=excluded.challenge_level,coaching_intensity=excluded.coaching_intensity,learning_velocity=excluded.learning_velocity,roleplay_score=excluded.roleplay_score,skill_score=excluded.skill_score,recent_success_rate=excluded.recent_success_rate,evidence_count=excluded.evidence_count,confidence=excluded.confidence,preferred_sequence=excluded.preferred_sequence,preferred_strategy=excluded.preferred_strategy,rationale=excluded.rationale,last_computed_at=now(),updated_at=now();
 select jsonb_build_object('organization_id',organization_id,'user_id',user_id,'challenge_level',challenge_level,'coaching_intensity',coaching_intensity,'learning_velocity',learning_velocity,'roleplay_score',roleplay_score,'skill_score',skill_score,'recent_success_rate',recent_success_rate,'evidence_count',evidence_count,'confidence',confidence,'preferred_sequence',preferred_sequence,'preferred_strategy',preferred_strategy,'rationale',rationale) into v_result from public.ai_adaptive_coaching_profiles where organization_id=p_organization_id and user_id=p_user_id;
 return v_result;
end $$;

create or replace function public.phase5_select_strategy(p_organization_id uuid,p_user_id uuid,p_metric_key text,p_skill_id uuid default null)
returns jsonb language plpgsql security definer set search_path='public','pg_temp' as $$
declare v_profile public.ai_adaptive_coaching_profiles%rowtype; v_best public.ai_coaching_strategy_performance%rowtype; v_strategy text; v_level int; v_sequence jsonb; v_conf numeric; v_explore boolean:=false; v_target numeric;
begin
 perform public.phase5_refresh_profile(p_organization_id,p_user_id);
 select * into v_profile from public.ai_adaptive_coaching_profiles where organization_id=p_organization_id and user_id=p_user_id;
 select * into v_best from public.ai_coaching_strategy_performance where organization_id=p_organization_id and metric_key=coalesce(p_metric_key,'') and (skill_id=p_skill_id or (skill_id is null and p_skill_id is null)) and attempts>=3 order by posterior_success desc,confidence desc,attempts desc limit 1;
 if v_best.id is not null and v_best.posterior_success>=0.55 then v_strategy:=v_best.strategy_key; v_level:=v_best.difficulty_level; v_conf:=greatest(v_profile.confidence,v_best.confidence); else v_strategy:=v_profile.preferred_strategy; v_level:=v_profile.challenge_level; v_conf:=v_profile.confidence; v_explore:=true; end if;
 v_level:=greatest(1,least(5,v_level));
 v_sequence:=case v_strategy when 'field_first' then '["roleplay","floor_challenge","lesson","review"]'::jsonb when 'practice_heavy' then '["lesson","roleplay","roleplay","review"]'::jsonb else '["lesson","roleplay","floor_challenge","review"]'::jsonb end;
 v_target:=case v_level when 1 then 65 when 2 then 72 when 3 then 78 when 4 then 84 else 90 end;
 return jsonb_build_object('strategy_key',v_strategy,'difficulty_level',v_level,'sequence',v_sequence,'target_score',v_target,'confidence',v_conf,'exploration',v_explore,'profile',jsonb_build_object('coaching_intensity',v_profile.coaching_intensity,'learning_velocity',v_profile.learning_velocity,'evidence_count',v_profile.evidence_count));
end $$;

create or replace function public.phase5_apply_adaptation(p_intervention_id uuid)
returns jsonb language plpgsql security definer set search_path='public','pg_temp' as $$
declare v_i public.ai_coaching_interventions%rowtype; v_choice jsonb; v_strategy text; v_level int; v_target numeric; v_seq jsonb; v_eval uuid; v_decision uuid;
begin
 select * into v_i from public.ai_coaching_interventions where id=p_intervention_id;
 if v_i.id is null then raise exception 'Intervention not found'; end if;
 if auth.uid() is not null and auth.uid()<>v_i.user_id and not public.is_org_admin(v_i.organization_id) then raise exception 'Not authorized'; end if;
 v_choice:=public.phase5_select_strategy(v_i.organization_id,v_i.user_id,v_i.metric_key,v_i.skill_id);
 v_strategy:=v_choice->>'strategy_key'; v_level:=(v_choice->>'difficulty_level')::int; v_target:=(v_choice->>'target_score')::numeric; v_seq:=v_choice->'sequence'; v_eval:=v_i.evaluation_id;
 update public.ai_intervention_steps set step_order=step_order+100 where intervention_id=p_intervention_id;
 update public.ai_intervention_steps set step_order=case when v_strategy='field_first' and step_type='roleplay' then 1 when v_strategy='field_first' and step_type='floor_challenge' then 2 when v_strategy='field_first' and step_type='lesson' then 3 when step_type='lesson' then 1 when step_type='roleplay' then 2 when step_type='floor_challenge' then 3 else 4 end,target_score=case when step_type='roleplay' then v_target else target_score end,metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('adaptive_difficulty',v_level,'adaptive_strategy',v_strategy,'repeat_roleplay_recommended',(v_strategy='practice_heavy')),updated_at=now() where intervention_id=p_intervention_id;
 update public.ai_coaching_interventions set evidence=coalesce(evidence,'{}'::jsonb)||jsonb_build_object('phase5_adaptive',v_choice),outcome_metadata=coalesce(outcome_metadata,'{}'::jsonb)||jsonb_build_object('adaptive_strategy',v_strategy,'difficulty_level',v_level),updated_at=now() where id=p_intervention_id;
 insert into public.ai_adaptive_coaching_decisions(organization_id,user_id,intervention_id,evaluation_id,strategy_key,difficulty_level,sequence,target_score,rationale,confidence,exploration)
 values(v_i.organization_id,v_i.user_id,v_i.id,v_eval,v_strategy,v_level,v_seq,v_target,v_choice,coalesce((v_choice->>'confidence')::numeric,0),coalesce((v_choice->>'exploration')::boolean,false))
 on conflict(intervention_id) do update set evaluation_id=excluded.evaluation_id,strategy_key=excluded.strategy_key,difficulty_level=excluded.difficulty_level,sequence=excluded.sequence,target_score=excluded.target_score,rationale=excluded.rationale,confidence=excluded.confidence,exploration=excluded.exploration,updated_at=now() returning id into v_decision;
 return v_choice||jsonb_build_object('intervention_id',p_intervention_id,'decision_id',v_decision);
end $$;

create or replace function public.phase5_generate_adaptive_coaching(p_organization_id uuid,p_user_id uuid,p_focus_date date default current_date)
returns jsonb language plpgsql security definer set search_path='public','pg_temp' as $$
declare v_id uuid; v_choice jsonb;
begin
 if auth.uid() is not null then
  if not public.is_org_member(p_organization_id) then raise exception 'Not a member of this organization'; end if;
  if auth.uid()<>p_user_id and not public.is_org_admin(p_organization_id) then raise exception 'Not authorized'; end if;
 end if;
 v_id:=public.phase4_generate_coaching(p_organization_id,p_user_id,p_focus_date);
 if v_id is null then return jsonb_build_object('status','no_intervention'); end if;
 v_choice:=public.phase5_apply_adaptation(v_id);
 return jsonb_build_object('status','created','intervention_id',v_id,'adaptation',v_choice);
end $$;

create or replace function public.phase5_learn_from_evaluation(p_evaluation_id uuid)
returns jsonb language plpgsql security definer set search_path='public','pg_temp' as $$
declare v_e public.ai_intervention_evaluations%rowtype; v_i public.ai_coaching_interventions%rowtype; v_d public.ai_adaptive_coaching_decisions%rowtype; v_attempts int; v_successes int; v_failures int; v_avg numeric; v_post numeric; v_conf numeric;
begin
 select * into v_e from public.ai_intervention_evaluations where id=p_evaluation_id;
 if v_e.id is null then raise exception 'Evaluation not found'; end if;
 if v_e.status<>'measured' then return jsonb_build_object('status','ignored','reason','evaluation_not_measured'); end if;
 select * into v_i from public.ai_coaching_interventions where id=v_e.intervention_id;
 select * into v_d from public.ai_adaptive_coaching_decisions where intervention_id=v_i.id;
 if v_d.id is null or v_d.learned_at is not null then return jsonb_build_object('status','ignored','reason',case when v_d.id is null then 'no_adaptive_decision' else 'already_learned' end); end if;
 insert into public.ai_coaching_strategy_performance(organization_id,metric_key,skill_id,strategy_key,difficulty_level,attempts,successes,failures,avg_delta,posterior_success,confidence,last_outcome_at)
 values(v_i.organization_id,coalesce(v_i.metric_key,''),v_i.skill_id,v_d.strategy_key,v_d.difficulty_level,1,case when v_e.success is true then 1 else 0 end,case when v_e.success is false then 1 else 0 end,v_e.delta,(1.0+case when v_e.success is true then 1 else 0 end)/(2.0+case when v_e.success is null then 0 else 1 end),0.2,coalesce(v_e.measured_at,now()))
 on conflict(organization_id,metric_key,coalesce(skill_id,'00000000-0000-0000-0000-000000000000'::uuid),strategy_key,difficulty_level) do update set attempts=public.ai_coaching_strategy_performance.attempts+1,successes=public.ai_coaching_strategy_performance.successes+case when v_e.success is true then 1 else 0 end,failures=public.ai_coaching_strategy_performance.failures+case when v_e.success is false then 1 else 0 end,avg_delta=case when v_e.delta is null then public.ai_coaching_strategy_performance.avg_delta else ((coalesce(public.ai_coaching_strategy_performance.avg_delta,0)*public.ai_coaching_strategy_performance.attempts)+v_e.delta)/(public.ai_coaching_strategy_performance.attempts+1) end,posterior_success=(1.0+public.ai_coaching_strategy_performance.successes+case when v_e.success is true then 1 else 0 end)/(2.0+public.ai_coaching_strategy_performance.successes+public.ai_coaching_strategy_performance.failures+case when v_e.success is null then 0 else 1 end),confidence=least(0.95,(public.ai_coaching_strategy_performance.attempts+1)::numeric/10.0),last_outcome_at=coalesce(v_e.measured_at,now()),updated_at=now();
 update public.ai_adaptive_coaching_decisions set outcome_success=v_e.success,outcome_delta=v_e.delta,outcome_id=v_e.outcome_id,learned_at=now(),updated_at=now() where id=v_d.id;
 perform public.phase5_refresh_profile(v_i.organization_id,v_i.user_id);
 select attempts,successes,failures,avg_delta,posterior_success,confidence into v_attempts,v_successes,v_failures,v_avg,v_post,v_conf from public.ai_coaching_strategy_performance where organization_id=v_i.organization_id and metric_key=coalesce(v_i.metric_key,'') and (skill_id=v_i.skill_id or(skill_id is null and v_i.skill_id is null)) and strategy_key=v_d.strategy_key and difficulty_level=v_d.difficulty_level;
 return jsonb_build_object('status','learned','strategy_key',v_d.strategy_key,'difficulty_level',v_d.difficulty_level,'attempts',v_attempts,'successes',v_successes,'failures',v_failures,'avg_delta',v_avg,'posterior_success',v_post,'confidence',v_conf);
end $$;

create or replace function public.phase5_evaluation_learning_trigger()
returns trigger language plpgsql security definer set search_path='public','pg_temp' as $$
begin
 if new.status='measured' and (old.status is distinct from new.status or old.outcome_id is distinct from new.outcome_id) then perform public.phase5_learn_from_evaluation(new.id); end if;
 return new;
end $$;

drop trigger if exists trg_phase5_learn_from_evaluation on public.ai_intervention_evaluations;
create trigger trg_phase5_learn_from_evaluation after update on public.ai_intervention_evaluations for each row execute function public.phase5_evaluation_learning_trigger();

create or replace function public.phase5_rep_plan(p_organization_id uuid,p_user_id uuid)
returns jsonb language plpgsql security definer set search_path='public','pg_temp' as $$
declare v_profile jsonb; v_active jsonb; v_history jsonb;
begin
 if auth.uid() is not null then
  if not public.is_org_member(p_organization_id) then raise exception 'Not a member of this organization'; end if;
  if auth.uid()<>p_user_id and not public.is_org_admin(p_organization_id) then raise exception 'Not authorized'; end if;
 end if;
 v_profile:=public.phase5_refresh_profile(p_organization_id,p_user_id);
 select coalesce(jsonb_agg(x order by x.created_at desc),'[]'::jsonb) into v_active from (select i.id,i.status,i.metric_key,i.diagnosis,i.due_at,d.strategy_key,d.difficulty_level,d.sequence,d.target_score,d.confidence,d.exploration,i.created_at from public.ai_coaching_interventions i left join public.ai_adaptive_coaching_decisions d on d.intervention_id=i.id where i.organization_id=p_organization_id and i.user_id=p_user_id and i.status in('recommended','assigned','in_progress') order by i.created_at desc limit 10)x;
 select coalesce(jsonb_agg(x order by x.learned_at desc),'[]'::jsonb) into v_history from (select d.strategy_key,d.difficulty_level,d.outcome_success,d.outcome_delta,d.learned_at from public.ai_adaptive_coaching_decisions d where d.organization_id=p_organization_id and d.user_id=p_user_id and d.learned_at is not null order by d.learned_at desc limit 10)x;
 return jsonb_build_object('profile',v_profile,'active_interventions',v_active,'recent_learning',v_history);
end $$;

create or replace function public.phase5_manager_dashboard(p_organization_id uuid)
returns jsonb language plpgsql stable security definer set search_path='public','pg_temp' as $$
declare v_result jsonb;
begin
 if auth.uid() is not null and not public.is_org_admin(p_organization_id) then raise exception 'Organization admin required'; end if;
 select jsonb_build_object(
  'profiles',(select coalesce(jsonb_agg(x order by x.confidence desc),'[]'::jsonb) from (select user_id,challenge_level,coaching_intensity,learning_velocity,roleplay_score,skill_score,recent_success_rate,evidence_count,confidence,preferred_strategy,last_computed_at from public.ai_adaptive_coaching_profiles where organization_id=p_organization_id limit 100)x),
  'strategies',(select coalesce(jsonb_agg(x order by x.posterior_success desc,x.attempts desc),'[]'::jsonb) from (select metric_key,skill_id,strategy_key,difficulty_level,attempts,successes,failures,avg_delta,posterior_success,confidence,last_outcome_at from public.ai_coaching_strategy_performance where organization_id=p_organization_id order by posterior_success desc,attempts desc limit 100)x),
  'recent_decisions',(select coalesce(jsonb_agg(x order by x.created_at desc),'[]'::jsonb) from (select id,user_id,intervention_id,strategy_key,difficulty_level,target_score,confidence,exploration,outcome_success,outcome_delta,learned_at,created_at from public.ai_adaptive_coaching_decisions where organization_id=p_organization_id order by created_at desc limit 100)x),
  'summary',jsonb_build_object('adaptive_users',(select count(*) from public.ai_adaptive_coaching_profiles where organization_id=p_organization_id),'decisions',(select count(*) from public.ai_adaptive_coaching_decisions where organization_id=p_organization_id),'learned_decisions',(select count(*) from public.ai_adaptive_coaching_decisions where organization_id=p_organization_id and learned_at is not null),'strategy_cells',(select count(*) from public.ai_coaching_strategy_performance where organization_id=p_organization_id))
 ) into v_result;
 return v_result;
end $$;

create or replace function public.phase5_manager_recommendations(p_organization_id uuid,p_limit integer default 25)
returns jsonb language plpgsql stable security definer set search_path='public','pg_temp' as $$
begin
 if auth.uid() is not null and not public.is_org_admin(p_organization_id) then raise exception 'Organization admin required'; end if;
 return coalesce((select jsonb_agg(x order by x.priority_score desc,x.user_id) from (
  select p.user_id,
    round((case p.coaching_intensity when 'intensive' then 40 when 'standard' then 20 else 5 end + case when p.recent_success_rate is null then 10 when p.recent_success_rate<40 then 35 when p.recent_success_rate<60 then 20 else 0 end + case when p.learning_velocity is not null and p.learning_velocity<0 then 20 else 0 end + case when exists(select 1 from public.ai_coaching_interventions i where i.organization_id=p.organization_id and i.user_id=p.user_id and i.status in('recommended','assigned','in_progress') and i.due_at<now()) then 25 else 0 end)::numeric,2) priority_score,
    p.coaching_intensity,p.challenge_level,p.recent_success_rate,p.learning_velocity,p.confidence,p.preferred_strategy,
    case when exists(select 1 from public.ai_coaching_interventions i where i.organization_id=p.organization_id and i.user_id=p.user_id and i.status in('recommended','assigned','in_progress') and i.due_at<now()) then 'Intervention overdue: manager follow-up recommended' when p.recent_success_rate is not null and p.recent_success_rate<40 then 'Low coaching effectiveness: review strategy and observe live behavior' when p.learning_velocity is not null and p.learning_velocity<0 then 'Performance is moving backward: increase observation and coaching intensity' when p.coaching_intensity='intensive' then 'Intensive coaching profile: schedule manager touchpoint' else 'Continue adaptive coaching and collect more evidence' end recommended_action,
    (select count(*) from public.ai_adaptive_coaching_decisions d where d.organization_id=p.organization_id and d.user_id=p.user_id and d.learned_at is not null) learned_interventions
  from public.ai_adaptive_coaching_profiles p where p.organization_id=p_organization_id order by priority_score desc limit greatest(1,least(coalesce(p_limit,25),100))
 )x),'[]'::jsonb);
end $$;

revoke all on function public.phase5_refresh_profile(uuid,uuid) from public;
revoke all on function public.phase5_select_strategy(uuid,uuid,text,uuid) from public;
revoke all on function public.phase5_apply_adaptation(uuid) from public;
revoke all on function public.phase5_generate_adaptive_coaching(uuid,uuid,date) from public;
revoke all on function public.phase5_learn_from_evaluation(uuid) from public;
revoke all on function public.phase5_rep_plan(uuid,uuid) from public;
revoke all on function public.phase5_manager_dashboard(uuid) from public;
revoke all on function public.phase5_manager_recommendations(uuid,integer) from public;

grant execute on function public.phase5_refresh_profile(uuid,uuid) to authenticated;
grant execute on function public.phase5_select_strategy(uuid,uuid,text,uuid) to authenticated;
grant execute on function public.phase5_apply_adaptation(uuid) to authenticated;
grant execute on function public.phase5_generate_adaptive_coaching(uuid,uuid,date) to authenticated;
grant execute on function public.phase5_rep_plan(uuid,uuid) to authenticated;
grant execute on function public.phase5_manager_dashboard(uuid) to authenticated;
grant execute on function public.phase5_manager_recommendations(uuid,integer) to authenticated;
