-- Coaching dashboards and profile computation; no AI calls or notifications.
CREATE OR REPLACE FUNCTION tj_private.phase5_refresh_profile(p_organization_id uuid, p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_role numeric; v_skill numeric; v_success numeric; v_velocity numeric; v_evidence int; v_level int; v_intensity text; v_sequence jsonb; v_strategy text; v_conf numeric; v_result jsonb;
begin

 if not tj.is_org_member(p_organization_id) or not exists(select 1 from tj.organizations where id=p_organization_id and deleted_at is null) then raise exception 'access_denied' using errcode='42501'; end if;
 if p_user_id is null or (p_user_id<>tj_private.current_source_user_id() and not tj.is_org_admin(p_organization_id)) then raise exception 'access_denied' using errcode='42501'; end if;
 if not exists(select 1 from tj.organization_members where organization_id=p_organization_id and user_id=p_user_id and status='active') then raise exception 'rep_not_active_in_organization'; end if;

 select round(avg(session_score),2),count(*) into v_role,v_evidence from tj.ai_roleplay_sessions where organization_id=p_organization_id and user_id=p_user_id and status='completed' and session_score is not null and created_at>=now()-interval '90 days';
 select round(avg(score),2) into v_skill from tj.ai_rep_skill_profiles where organization_id=p_organization_id and user_id=p_user_id;
 select round(100.0*count(*) filter(where success is true)/nullif(count(*) filter(where success is not null),0),2),round(avg(delta),2)
 into v_success,v_velocity from (select success,delta from tj.ai_intervention_evaluations e join tj.ai_coaching_interventions i on i.id=e.intervention_id and i.organization_id=p_organization_id where e.organization_id=p_organization_id and i.user_id=p_user_id and e.status='measured' order by e.measured_at desc nulls last limit 10)x;
 v_evidence:=coalesce(v_evidence,0)+(select count(*) from tj.ai_rep_skill_profiles where organization_id=p_organization_id and user_id=p_user_id)+(select count(*) from tj.ai_intervention_evaluations e join tj.ai_coaching_interventions i on i.id=e.intervention_id and i.organization_id=p_organization_id where e.organization_id=p_organization_id and i.user_id=p_user_id and e.status='measured');
 v_level:=case when coalesce(v_role,v_skill,0)>=90 then 5 when coalesce(v_role,v_skill,0)>=80 then 4 when coalesce(v_role,v_skill,0)>=68 then 3 when coalesce(v_role,v_skill,0)>=52 then 2 else 1 end;
 if v_evidence<3 then v_level:=2; end if;
 v_intensity:=case when v_success is not null and v_success<40 then 'intensive' when v_success is not null and v_success>=75 then 'light' else 'standard' end;
 if v_level>=4 then v_strategy:='field_first'; v_sequence:='["roleplay","floor_challenge","lesson","review"]'::jsonb;
 elsif coalesce(v_role,0)<60 and v_role is not null then v_strategy:='practice_heavy'; v_sequence:='["lesson","roleplay","roleplay","review"]'::jsonb;
 elsif v_intensity='intensive' then v_strategy:='reinforce'; v_sequence:='["lesson","roleplay","floor_challenge","review"]'::jsonb;
 else v_strategy:='foundation'; v_sequence:='["lesson","roleplay","floor_challenge","review"]'::jsonb; end if;
 v_conf:=least(0.95,round(coalesce(v_evidence,0)::numeric/12.0,3));
 insert into tj.ai_adaptive_coaching_profiles(organization_id,user_id,challenge_level,coaching_intensity,learning_velocity,roleplay_score,skill_score,recent_success_rate,evidence_count,confidence,preferred_sequence,preferred_strategy,rationale,last_computed_at,updated_at)
 values(p_organization_id,p_user_id,v_level,v_intensity,v_velocity,v_role,v_skill,v_success,v_evidence,v_conf,v_sequence,v_strategy,jsonb_strip_nulls(jsonb_build_object('cold_start',v_evidence<3,'roleplay_score',v_role,'skill_score',v_skill,'recent_success_rate',v_success,'learning_velocity',v_velocity)),now(),now())
 on conflict(organization_id,user_id) do update set challenge_level=excluded.challenge_level,coaching_intensity=excluded.coaching_intensity,learning_velocity=excluded.learning_velocity,roleplay_score=excluded.roleplay_score,skill_score=excluded.skill_score,recent_success_rate=excluded.recent_success_rate,evidence_count=excluded.evidence_count,confidence=excluded.confidence,preferred_sequence=excluded.preferred_sequence,preferred_strategy=excluded.preferred_strategy,rationale=excluded.rationale,last_computed_at=now(),updated_at=now();
 select jsonb_build_object('organization_id',organization_id,'user_id',user_id,'challenge_level',challenge_level,'coaching_intensity',coaching_intensity,'learning_velocity',learning_velocity,'roleplay_score',roleplay_score,'skill_score',skill_score,'recent_success_rate',recent_success_rate,'evidence_count',evidence_count,'confidence',confidence,'preferred_sequence',preferred_sequence,'preferred_strategy',preferred_strategy,'rationale',rationale) into v_result from tj.ai_adaptive_coaching_profiles where organization_id=p_organization_id and user_id=p_user_id;
 return v_result;
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase5_refresh_profile(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj_private.phase5_refresh_profile(uuid,uuid) TO authenticated;
CREATE FUNCTION tj.phase5_refresh_profile(p_organization_id uuid, p_user_id uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.phase5_refresh_profile(p_organization_id,p_user_id); $$;
REVOKE ALL ON FUNCTION tj.phase5_refresh_profile(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj.phase5_refresh_profile(uuid,uuid) TO authenticated;
CREATE OR REPLACE FUNCTION tj_private.phase4_coaching_dashboard(p_organization_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
select case when tj.is_org_member(p_organization_id) and exists(select 1 from tj.organizations where id=p_organization_id and deleted_at is null) then
 jsonb_build_object(
  'active_interventions',(select count(*) from tj.ai_coaching_interventions i where i.organization_id=p_organization_id and i.status in ('recommended','assigned','in_progress')),
  'completed_interventions',(select count(*) from tj.ai_coaching_interventions i where i.organization_id=p_organization_id and i.status='completed'),
  'evaluations_due',(select count(*) from tj.ai_intervention_evaluations e where e.organization_id=p_organization_id and e.status in ('pending','due') and e.evaluation_due_at<=now()),
  'measured_outcomes',(select count(*) from tj.ai_intervention_evaluations e where e.organization_id=p_organization_id and e.status='measured'),
  'successful_outcomes',(select count(*) from tj.ai_intervention_evaluations e where e.organization_id=p_organization_id and e.status='measured' and e.success is true),
  'effectiveness_pct',(select case when count(*) filter(where e.status='measured' and e.success is not null)>0 then round(100.0*count(*) filter(where e.status='measured' and e.success is true)/count(*) filter(where e.status='measured' and e.success is not null),2) end from tj.ai_intervention_evaluations e where e.organization_id=p_organization_id),
  'latest',(select coalesce(jsonb_agg(x order by x.created_at desc),'[]'::jsonb) from (select i.id,i.user_id,i.status,i.metric_key,i.diagnosis,i.baseline_value,i.target_value,i.outcome_value,i.outcome_delta,i.created_at,e.status evaluation_status,e.evaluation_due_at,e.success from tj.ai_coaching_interventions i left join tj.ai_intervention_evaluations e on e.intervention_id=i.id and e.organization_id=p_organization_id where i.organization_id=p_organization_id order by i.created_at desc limit 50)x)
 ) else null end;
$function$;
REVOKE ALL ON FUNCTION tj_private.phase4_coaching_dashboard(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj_private.phase4_coaching_dashboard(uuid) TO authenticated;
CREATE FUNCTION tj.phase4_coaching_dashboard(p_organization_id uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.phase4_coaching_dashboard(p_organization_id); $$;
REVOKE ALL ON FUNCTION tj.phase4_coaching_dashboard(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj.phase4_coaching_dashboard(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION tj_private.phase5_manager_dashboard(p_organization_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_result jsonb;
begin

 if not tj.is_org_admin(p_organization_id) or not exists(select 1 from tj.organizations where id=p_organization_id and deleted_at is null) then raise exception 'access_denied' using errcode='42501'; end if;

 select jsonb_build_object(
  'profiles',(select coalesce(jsonb_agg(x order by x.confidence desc),'[]'::jsonb) from (select user_id,challenge_level,coaching_intensity,learning_velocity,roleplay_score,skill_score,recent_success_rate,evidence_count,confidence,preferred_strategy,last_computed_at from tj.ai_adaptive_coaching_profiles where organization_id=p_organization_id limit 100)x),
  'strategies',(select coalesce(jsonb_agg(x order by x.posterior_success desc,x.attempts desc),'[]'::jsonb) from (select metric_key,skill_id,strategy_key,difficulty_level,attempts,successes,failures,avg_delta,posterior_success,confidence,last_outcome_at from tj.ai_coaching_strategy_performance where organization_id=p_organization_id order by posterior_success desc,attempts desc limit 100)x),
  'recent_decisions',(select coalesce(jsonb_agg(x order by x.created_at desc),'[]'::jsonb) from (select id,user_id,intervention_id,strategy_key,difficulty_level,target_score,confidence,exploration,outcome_success,outcome_delta,learned_at,created_at from tj.ai_adaptive_coaching_decisions where organization_id=p_organization_id order by created_at desc limit 100)x),
  'summary',jsonb_build_object('adaptive_users',(select count(*) from tj.ai_adaptive_coaching_profiles where organization_id=p_organization_id),'decisions',(select count(*) from tj.ai_adaptive_coaching_decisions where organization_id=p_organization_id),'learned_decisions',(select count(*) from tj.ai_adaptive_coaching_decisions where organization_id=p_organization_id and learned_at is not null),'strategy_cells',(select count(*) from tj.ai_coaching_strategy_performance where organization_id=p_organization_id))
 ) into v_result;
 return v_result;
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase5_manager_dashboard(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj_private.phase5_manager_dashboard(uuid) TO authenticated;
CREATE FUNCTION tj.phase5_manager_dashboard(p_organization_id uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.phase5_manager_dashboard(p_organization_id); $$;
REVOKE ALL ON FUNCTION tj.phase5_manager_dashboard(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj.phase5_manager_dashboard(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION tj_private.phase5_manager_recommendations(p_organization_id uuid, p_limit integer DEFAULT 25)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin

 if not tj.is_org_admin(p_organization_id) or not exists(select 1 from tj.organizations where id=p_organization_id and deleted_at is null) then raise exception 'access_denied' using errcode='42501'; end if;

 return coalesce((select jsonb_agg(x order by x.priority_score desc,x.user_id) from (
  select p.user_id,
    round((case p.coaching_intensity when 'intensive' then 40 when 'standard' then 20 else 5 end
      + case when p.recent_success_rate is null then 10 when p.recent_success_rate<40 then 35 when p.recent_success_rate<60 then 20 else 0 end
      + case when p.learning_velocity is not null and p.learning_velocity<0 then 20 else 0 end
      + case when exists(select 1 from tj.ai_coaching_interventions i where i.organization_id=p.organization_id and i.user_id=p.user_id and i.status in('recommended','assigned','in_progress') and i.due_at<now()) then 25 else 0 end)::numeric,2) priority_score,
    p.coaching_intensity,p.challenge_level,p.recent_success_rate,p.learning_velocity,p.confidence,p.preferred_strategy,
    case
      when exists(select 1 from tj.ai_coaching_interventions i where i.organization_id=p.organization_id and i.user_id=p.user_id and i.status in('recommended','assigned','in_progress') and i.due_at<now()) then 'Intervention overdue: manager follow-up recommended'
      when p.recent_success_rate is not null and p.recent_success_rate<40 then 'Low coaching effectiveness: review strategy and observe live behavior'
      when p.learning_velocity is not null and p.learning_velocity<0 then 'Performance is moving backward: increase observation and coaching intensity'
      when p.coaching_intensity='intensive' then 'Intensive coaching profile: schedule manager touchpoint'
      else 'Continue adaptive coaching and collect more evidence' end recommended_action,
    (select count(*) from tj.ai_adaptive_coaching_decisions d where d.organization_id=p.organization_id and d.user_id=p.user_id and d.learned_at is not null) learned_interventions
  from tj.ai_adaptive_coaching_profiles p where p.organization_id=p_organization_id
  order by priority_score desc limit greatest(1,least(coalesce(p_limit,25),100))
 )x),'[]'::jsonb);
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase5_manager_recommendations(uuid,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj_private.phase5_manager_recommendations(uuid,integer) TO authenticated;
CREATE FUNCTION tj.phase5_manager_recommendations(p_organization_id uuid, p_limit integer DEFAULT 25) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.phase5_manager_recommendations(p_organization_id,p_limit); $$;
REVOKE ALL ON FUNCTION tj.phase5_manager_recommendations(uuid,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj.phase5_manager_recommendations(uuid,integer) TO authenticated;
CREATE OR REPLACE FUNCTION tj_private.phase5_rep_plan(p_organization_id uuid, p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_profile jsonb; v_active jsonb; v_history jsonb;
begin

 if not tj.is_org_member(p_organization_id) or not exists(select 1 from tj.organizations where id=p_organization_id and deleted_at is null) then raise exception 'access_denied' using errcode='42501'; end if;
 if p_user_id is null or (p_user_id<>tj_private.current_source_user_id() and not tj.is_org_admin(p_organization_id)) then raise exception 'access_denied' using errcode='42501'; end if;
 if not exists(select 1 from tj.organization_members where organization_id=p_organization_id and user_id=p_user_id and status='active') then raise exception 'rep_not_active_in_organization'; end if;

 v_profile:=tj_private.phase5_refresh_profile(p_organization_id,p_user_id);
 select coalesce(jsonb_agg(x order by x.created_at desc),'[]'::jsonb) into v_active from (select i.id,i.status,i.metric_key,i.diagnosis,i.due_at,d.strategy_key,d.difficulty_level,d.sequence,d.target_score,d.confidence,d.exploration,i.created_at from tj.ai_coaching_interventions i left join tj.ai_adaptive_coaching_decisions d on d.intervention_id=i.id and d.organization_id=p_organization_id and d.user_id=p_user_id where i.organization_id=p_organization_id and i.user_id=p_user_id and i.status in('recommended','assigned','in_progress') order by i.created_at desc limit 10)x;
 select coalesce(jsonb_agg(x order by x.learned_at desc),'[]'::jsonb) into v_history from (select d.strategy_key,d.difficulty_level,d.outcome_success,d.outcome_delta,d.learned_at from tj.ai_adaptive_coaching_decisions d where d.organization_id=p_organization_id and d.user_id=p_user_id and d.learned_at is not null order by d.learned_at desc limit 10)x;
 return jsonb_build_object('profile',v_profile,'active_interventions',v_active,'recent_learning',v_history);
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase5_rep_plan(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj_private.phase5_rep_plan(uuid,uuid) TO authenticated;
CREATE FUNCTION tj.phase5_rep_plan(p_organization_id uuid, p_user_id uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.phase5_rep_plan(p_organization_id,p_user_id); $$;
REVOKE ALL ON FUNCTION tj.phase5_rep_plan(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj.phase5_rep_plan(uuid,uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
