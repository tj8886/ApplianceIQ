CREATE SEQUENCE tj_private.academy_learning_event_id_seq AS bigint;
SELECT setval('tj_private.academy_learning_event_id_seq',greatest(coalesce((SELECT max(id) FROM tj.academy_learning_events),0)+1,1),false);
REVOKE ALL ON SEQUENCE tj_private.academy_learning_event_id_seq FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj_private.academy_learning(p_payload jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=tj_private.current_source_user_id();access jsonb;org uuid;action text:=coalesce(p_payload->>'action','feed');req uuid;result jsonb;course tj.iq_courses%ROWTYPE;kind text;content text;event_id bigint;source_date timestamptz;is_admin boolean;
BEGIN
 IF actor IS NULL THEN RAISE EXCEPTION 'access_denied' USING ERRCODE='42501';END IF;
 access:=tj_private.check_app_access('iq_academy');IF access->>'allowed' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'academy_access_denied' USING ERRCODE='42501';END IF;
 org:=(access->>'organization_id')::uuid;
 IF org IS NULL THEN SELECT m.organization_id INTO org FROM tj.organization_members m JOIN tj.organizations o ON o.id=m.organization_id AND o.status='active' AND o.deleted_at IS NULL WHERE m.user_id=actor AND m.status='active' ORDER BY m.organization_id LIMIT 1;END IF;
 IF org IS NULL THEN RAISE EXCEPTION 'active_membership_required' USING ERRCODE='42501';END IF;
 IF jsonb_typeof(p_payload)<>'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_payload) k WHERE k NOT IN('action','request_id','event_type','course_key','content')) THEN RAISE EXCEPTION 'invalid_payload' USING ERRCODE='22023';END IF;
 IF action='feed' THEN
  is_admin:=EXISTS(SELECT 1 FROM tj.organization_members WHERE organization_id=org AND user_id=actor AND status='active' AND role IN('owner','admin'));
  RETURN jsonb_build_object('scope',CASE WHEN is_admin THEN 'Active organization members' ELSE 'Your activity' END,'events',coalesce((SELECT jsonb_agg(x ORDER BY x.created_at DESC,x.id DESC) FROM(SELECT e.id,e.event_type,e.pillar,e.course_key,e.content,e.metadata,e.created_at FROM tj.academy_learning_events e WHERE e.user_id=actor OR (is_admin AND EXISTS(SELECT 1 FROM tj_private.academy_record_events r JOIN tj.organization_members m ON m.organization_id=org AND m.user_id=r.source_user_id AND m.status='active' WHERE r.organization_id=org AND r.kind='learning_event' AND (r.payload->'result'->>'event_id')::bigint=e.id)) ORDER BY e.created_at DESC,e.id DESC LIMIT 100)x),'[]'::jsonb));
 END IF;
 IF action<>'record' OR p_payload->>'event_type' NOT IN('course_open','ai_question') OR p_payload->>'event_type' IS NULL THEN RAISE EXCEPTION 'invalid_event_type' USING ERRCODE='22023';END IF;
 BEGIN req:=(p_payload->>'request_id')::uuid;EXCEPTION WHEN invalid_text_representation THEN RAISE EXCEPTION 'invalid_request_id' USING ERRCODE='22023';END;
 IF req IS NULL THEN RAISE EXCEPTION 'request_id_required' USING ERRCODE='22023';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('academy_records:'||actor::text,0));
 SELECT payload INTO result FROM tj_private.academy_record_events WHERE source_user_id=actor AND request_id=req;
 IF FOUND THEN IF result->'request' IS DISTINCT FROM p_payload THEN RAISE EXCEPTION 'request_id_conflict' USING ERRCODE='22023';END IF;RETURN result->'result';END IF;
 IF nullif(p_payload->>'course_key','') IS NOT NULL THEN SELECT * INTO course FROM tj.iq_courses WHERE course_key=p_payload->>'course_key';IF NOT FOUND THEN RAISE EXCEPTION 'course_unavailable' USING ERRCODE='22023';END IF;END IF;
 kind:=p_payload->>'event_type';content:=CASE WHEN kind='course_open' THEN course.name ELSE nullif(btrim(p_payload->>'content'),'') END;
 IF content IS NULL OR char_length(content)>8000 THEN RAISE EXCEPTION 'invalid_event_content' USING ERRCODE='22023';END IF;
 event_id:=nextval('tj_private.academy_learning_event_id_seq');source_date:=clock_timestamp();
 INSERT INTO tj.academy_learning_events(id,user_id,event_type,pillar,course_key,content,metadata,created_at) VALUES(event_id,actor,kind,course.pillar,course.course_key,content,jsonb_build_object('recording_basis','Authenticated user submitted activity; not provider completion'),source_date);
 result:=jsonb_build_object('event_id',event_id,'created_at',source_date,'saved',true);
 INSERT INTO tj_private.academy_record_events(organization_id,source_user_id,request_id,kind,payload,recorded_at) VALUES(org,actor,req,'learning_event',jsonb_build_object('request',p_payload,'result',result),source_date);
 INSERT INTO tj_private.command_centre_refresh_queue(organization_id,requested_at,next_attempt_at) VALUES(org,source_date,source_date) ON CONFLICT(organization_id) DO UPDATE SET requested_at=excluded.requested_at,next_attempt_at=excluded.next_attempt_at;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION tj_private.academy_learning(jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.academy_learning(jsonb) TO authenticated;
CREATE FUNCTION public.tj_runtime_academy_learning(p_payload jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$SELECT tj_private.academy_learning(p_payload);$$;
REVOKE ALL ON FUNCTION public.tj_runtime_academy_learning(jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tj_runtime_academy_learning(jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';

CREATE OR REPLACE FUNCTION tj_private.command_centre_academy_evidence(p_org uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
WITH members AS (SELECT DISTINCT user_id FROM tj.organization_members WHERE organization_id=p_org AND status='active'),
 lessons AS (SELECT p.* FROM tj.academy_progress p JOIN members m USING(user_id)),
 tracks AS (SELECT p.* FROM tj.academy_track_progress p JOIN members m USING(user_id)),
 quizzes AS (SELECT q.* FROM tj.academy_quiz_scores q JOIN members m USING(user_id)),
 daily AS (SELECT d.* FROM tj.academy_daily_metrics d JOIN members m USING(user_id) WHERE metric_date=(now() AT TIME ZONE 'America/Toronto')::date),
 activity AS (SELECT * FROM tj_private.academy_record_events WHERE organization_id=p_org AND kind='learning_event' AND source_user_id IN(SELECT user_id FROM members)),
 dates AS (SELECT greatest((SELECT max(completed_at) FROM lessons),(SELECT max(greatest(started_at,completed_at)) FROM tracks),(SELECT max(updated_at) FROM quizzes),(SELECT max(updated_at) FROM daily),(SELECT max(recorded_at) FROM activity)) source_at)
SELECT jsonb_build_object('active_members',(SELECT count(*) FROM members),'lesson_records',(SELECT count(*) FROM lessons),'track_records',(SELECT count(*) FROM tracks),
 'lesson_completions',CASE WHEN EXISTS(SELECT 1 FROM lessons) THEN (SELECT count(DISTINCT(user_id,chapter_id)) FROM lessons WHERE completed_at IS NOT NULL) END,
 'lesson_completions_this_month',CASE WHEN EXISTS(SELECT 1 FROM lessons) THEN (SELECT count(DISTINCT(user_id,chapter_id)) FROM lessons WHERE (completed_at AT TIME ZONE 'America/Toronto')::date BETWEEN date_trunc('month',now() AT TIME ZONE 'America/Toronto')::date AND (now() AT TIME ZONE 'America/Toronto')::date) END,
 'completed_tracks',CASE WHEN EXISTS(SELECT 1 FROM tracks) THEN (SELECT count(DISTINCT(user_id,track_key)) FROM tracks WHERE completed_at IS NOT NULL) END,
 'started_uncompleted_tracks',CASE WHEN EXISTS(SELECT 1 FROM tracks) THEN (SELECT count(DISTINCT(user_id,track_key)) FROM tracks WHERE started_at IS NOT NULL AND completed_at IS NULL) END,
 'learning_activity',jsonb_build_object('received_events',(SELECT count(*) FROM activity),'received_today',(SELECT count(*) FROM activity WHERE (recorded_at AT TIME ZONE 'America/Toronto')::date=(now() AT TIME ZONE 'America/Toronto')::date),'latest_source_at',(SELECT max(recorded_at) FROM activity),'basis','Authenticated received activity; AI question submission is not model/provider completion'),
 'daily_five',jsonb_build_object('metric_date',(now() AT TIME ZONE 'America/Toronto')::date,'recorded_members',(SELECT count(*) FROM daily),'opportunities',(SELECT sum(opportunities) FROM daily),'captures',(SELECT sum(captures) FROM daily),'asks',(SELECT sum(asks) FROM daily),'touches',(SELECT sum(touches) FROM daily),'attach_presentations',(SELECT sum(attach_presentations) FROM daily),'sales',(SELECT sum(sales) FROM daily),'latest_source_at',(SELECT max(updated_at) FROM daily)),
 'completion_pct',NULL,'completion_basis','Recorded lesson/track counts of active organization members; assignment denominator is not recorded, so completion percentage is unknown',
 'source',jsonb_build_object('latest_source_at',source_at,'scope','Active-member dated quizzes, lesson completions and track starts/completions and current-day Daily Five and received learning activity; absent progress is unknown')) FROM dates;
$$;
REVOKE ALL ON FUNCTION tj_private.command_centre_academy_evidence(uuid) FROM PUBLIC,anon,authenticated,service_role;

