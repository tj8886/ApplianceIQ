CREATE OR REPLACE FUNCTION tj_private.sync_ai_roleplay_observations()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  payload jsonb;
  kv record;
  normalized_key text;
  competency_code text;
  raw_score numeric;
  normalized_score numeric;
  competency_uuid uuid;
  perf_scenario_id uuid;
  perf_intervention_id uuid;
begin
  if not (new.status='completed' or new.completed_at is not null) then return new; end if;

  select l.scenario_id,l.intervention_id into perf_scenario_id,perf_intervention_id
  from tj.performance_roleplay_links l
  where l.ai_roleplay_session_id=new.id AND l.organization_id=new.organization_id AND l.user_id=new.user_id
  order by l.created_at desc
  limit 1;

  if jsonb_typeof(new.scoring_breakdown)='object' and new.scoring_breakdown <> '{}'::jsonb then
    payload := new.scoring_breakdown;
  elsif jsonb_typeof(new.kpi_scores)='object' and new.kpi_scores <> '{}'::jsonb then
    payload := new.kpi_scores;
  else
    return new;
  end if;

  for kv in select key,value from jsonb_each(payload)
  loop
    normalized_key := trim(both '_' from lower(regexp_replace(kv.key,'[^a-zA-Z0-9]+','_','g')));
    competency_code := case normalized_key
      when 'discovery' then 'discovery'
      when 'product_knowledge' then 'product_knowledge'
      when 'recommendation' then 'recommendation'
      when 'recommendation_quality' then 'recommendation'
      when 'value' then 'value_building'
      when 'value_building' then 'value_building'
      when 'objection_handling' then 'objection_handling'
      when 'objections' then 'objection_handling'
      when 'closing' then 'closing'
      when 'close' then 'closing'
      when 'attachment' then 'attachment'
      when 'attachment_selling' then 'attachment'
      when 'attach_selling' then 'attachment'
      when 'communication' then 'communication'
      when 'trust' then 'trust'
      when 'trust_credibility' then 'trust'
      when 'process_discipline' then 'process_discipline'
      when 'follow_up' then 'process_discipline'
      else normalized_key end;

    begin
      if jsonb_typeof(kv.value)='number' then raw_score := (kv.value #>> '{}')::numeric;
      elsif jsonb_typeof(kv.value)='object' and kv.value ? 'score' then raw_score := (kv.value->>'score')::numeric;
      else continue;
      end if;
    exception when others then continue;
    end;

    IF raw_score IS NULL OR raw_score<0 OR raw_score>100 THEN CONTINUE;END IF;
    normalized_score := CASE WHEN jsonb_typeof(new.scoring_breakdown)='object' AND new.scoring_breakdown<>'{}'::jsonb THEN raw_score ELSE CASE WHEN raw_score<=10 THEN raw_score*10 ELSE raw_score END END;

    select c.id into competency_uuid
    from tj.performance_competencies c
    where c.code=competency_code and c.active=true
      and (c.organization_id is null or c.organization_id=new.organization_id)
    order by (c.organization_id is not null) desc limit 1;
    if competency_uuid is null then continue; end if;

    insert into tj.performance_observations
      (organization_id,user_id,competency_id,source_type,source_id,score,confidence,evidence,metadata,observed_at)
    values
      (new.organization_id,new.user_id,competency_uuid,'roleplay',new.id,normalized_score,0.85,
       coalesce(new.feedback,'Beat the Bot competency score'),
       jsonb_build_object('channel','beat_the_bot','roleplay_session_id',new.id,'scenario_type',new.scenario_type,
         'performance_scenario_id',perf_scenario_id,'performance_intervention_id',perf_intervention_id,
         'mode',new.mode,'difficulty_level',new.difficulty_level,'source_key',kv.key,
         'raw_score',raw_score,'scoring_version',new.scoring_version),
       coalesce(new.completed_at,now()))
    on conflict (organization_id,user_id,competency_id,source_type,source_id) where source_id is not null
    do update set score=excluded.score,confidence=excluded.confidence,evidence=excluded.evidence,
      metadata=excluded.metadata,observed_at=excluded.observed_at;
  end loop;

  -- Backfill a link for legacy sessions only when one does not exist.
  insert into tj.performance_roleplay_links
    (organization_id,user_id,scenario_id,ai_roleplay_session_id)
  select new.organization_id,new.user_id,null,new.id
  where not exists (select 1 from tj.performance_roleplay_links l where l.ai_roleplay_session_id=new.id);

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION tj_private.process_observation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  prior tj.performance_skill_state%rowtype;
  new_score numeric(5,2);
  new_conf numeric(4,3);
  new_trend text;
  comp_code text;
  scenario_uuid uuid;
  alpha numeric;
begin
  select * into prior from tj.performance_skill_state
  where organization_id=new.organization_id and user_id=new.user_id and competency_id=new.competency_id
  for update;

  alpha := least(0.30, greatest(0.00, 0.30 * new.confidence));
  if found then
    new_score := round((prior.rolling_score*(1-alpha) + new.score*alpha)::numeric,2);
    new_conf := least(1.000,round((prior.confidence + (0.10*new.confidence))::numeric,3));
    new_trend := case when new_score >= prior.rolling_score+3 then 'improving' when new_score <= prior.rolling_score-3 then 'declining' else 'stable' end;
    update tj.performance_skill_state set rolling_score=new_score,confidence=new_conf,sample_size=prior.sample_size+1,trend=new_trend,last_observed_at=new.observed_at,updated_at=now() where id=prior.id;
  else
    new_score := round((75 + ((new.score-75)*new.confidence))::numeric,2);
    new_conf := least(1.000,new.confidence);
    new_trend := 'unknown';
    insert into tj.performance_skill_state (organization_id,user_id,competency_id,rolling_score,confidence,sample_size,trend,last_observed_at)
    values (new.organization_id,new.user_id,new.competency_id,new_score,new_conf,1,new_trend,new.observed_at);
  end if;

  if new_score < 65 then
    select code into comp_code from tj.performance_competencies where id=new.competency_id;
    select s.id into scenario_uuid from tj.performance_scenarios s
    where s.active=true and (s.organization_id is null or s.organization_id=new.organization_id) and s.competency_weights ? comp_code
    order by case when s.organization_id=new.organization_id then 0 else 1 end,coalesce((s.competency_weights->>comp_code)::numeric,0) desc,s.difficulty asc limit 1;
    if not exists (select 1 from tj.performance_interventions i where i.organization_id=new.organization_id and i.user_id=new.user_id and i.competency_id=new.competency_id and i.status in ('prescribed','in_progress','started')) then
      insert into tj.performance_interventions (organization_id,user_id,competency_id,trigger_observation_id,intervention_type,status,reason,prescribed_scenario_id,baseline_score,due_at)
      values (new.organization_id,new.user_id,new.competency_id,new.id,'roleplay','prescribed','Automatically prescribed from the blended Performance Brain because this competency is below 65.',scenario_uuid,new_score,now()+interval '7 days');
    end if;
  end if;
  return new;
end;
$function$;

REVOKE ALL ON FUNCTION tj_private.sync_ai_roleplay_observations(),tj_private.process_observation() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER consolidation_sync_roleplay_observations AFTER INSERT OR UPDATE OF status,completed_at,kpi_scores,scoring_breakdown,feedback ON tj.ai_roleplay_sessions FOR EACH ROW EXECUTE FUNCTION tj_private.sync_ai_roleplay_observations();
CREATE TRIGGER consolidation_process_roleplay_observation AFTER INSERT ON tj.performance_observations FOR EACH ROW WHEN (NEW.source_type='roleplay') EXECUTE FUNCTION tj_private.process_observation();
