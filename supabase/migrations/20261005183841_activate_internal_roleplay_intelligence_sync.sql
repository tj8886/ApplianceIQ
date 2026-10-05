CREATE OR REPLACE FUNCTION tj_private.intelligence_sync_ai_roleplay()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_entity uuid; v_rec uuid; v_success boolean; v_score numeric;
begin
  if tg_op='DELETE' then return old; end if;
  insert into tj.intelligence_entities(organization_id,entity_type,canonical_name,slug,source_system,source_record_id,status,metadata,created_by,updated_by,created_at,updated_at)
  values(new.organization_id,'conversation',concat('Role-play: ',new.scenario_type),'roleplay-'||new.id::text,'academy_roleplay',new.id::text,case when lower(new.status)='completed' then 'active' else 'inactive' end,
    jsonb_strip_nulls(jsonb_build_object('user_id',new.user_id,'scenario_type',new.scenario_type,'status',new.status,'turns',new.total_turns,'score',new.session_score,'kpi_scores',new.kpi_scores,'feedback',new.feedback)),new.user_id,new.user_id,new.created_at,coalesce(new.completed_at,new.created_at))
  on conflict(organization_id,source_system,source_record_id) do update set canonical_name=excluded.canonical_name,status=excluded.status,metadata=excluded.metadata,updated_at=excluded.updated_at returning id into v_entity;

  v_rec:=tj.intelligence_record_recommendation(new.organization_id,'training_practice','employee',new.user_id::text,new.scenario_type,'sales_coach:'||new.scenario_type,v_entity,null,jsonb_build_object('source','roleplay','scenario',new.scenario_type),'[]'::jsonb,'academy_roleplay',new.id::text);

  UPDATE tj.intelligence_recommendations SET actor_id=new.user_id WHERE id=v_rec;
  if lower(new.status)='completed' and new.session_score is not null then
    v_score:=case when new.session_score>10 then new.session_score/10.0 else new.session_score end;
    v_success:=v_score>=7;
    perform tj.intelligence_record_outcome(v_rec,'roleplay_score',v_success,v_score,'Role-play completed',greatest(0.25,least(2,v_score/5)),jsonb_build_object('kpi_scores',new.kpi_scores,'feedback',new.feedback),'academy_roleplay_outcome',new.id::text,coalesce(new.completed_at,now()));
    UPDATE tj.intelligence_outcomes SET recorded_by=new.user_id WHERE organization_id=new.organization_id AND source_system='academy_roleplay_outcome' AND source_record_id=new.id::text;
    update tj.intelligence_recommendations set status=case when v_success then 'accepted' else 'rejected' end,resolved_at=coalesce(new.completed_at,now()) where id=v_rec;
  end if;
  return new;
end; $function$;
REVOKE ALL ON FUNCTION tj_private.intelligence_sync_ai_roleplay() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER consolidation_roleplay_intelligence_sync AFTER INSERT OR UPDATE ON tj.ai_roleplay_sessions FOR EACH ROW EXECUTE FUNCTION tj_private.intelligence_sync_ai_roleplay();
