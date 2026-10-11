CREATE TABLE tj_private.academy_record_events(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 organization_id uuid NOT NULL REFERENCES tj.organizations(id),
 source_user_id uuid NOT NULL REFERENCES tj.source_auth_users(id),
 request_id uuid NOT NULL, kind text NOT NULL, payload jsonb NOT NULL,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(source_user_id,request_id));
CREATE INDEX academy_record_events_org_idx ON tj_private.academy_record_events(organization_id);
ALTER TABLE tj_private.academy_record_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj_private.academy_record_events FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj_private.academy_records(p_payload jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=tj_private.current_source_user_id();access jsonb;org uuid;action text:=coalesce(p_payload->>'action','daily_load');day date:=(now() AT TIME ZONE 'America/Toronto')::date;field text;delta int;req uuid;result jsonb;card tj.iq_cards%ROWTYPE;answer text;points int;total int;
BEGIN
 IF actor IS NULL THEN RAISE EXCEPTION 'access_denied' USING ERRCODE='42501';END IF;
 access:=tj_private.check_app_access('iq_academy');
 IF access->>'allowed' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'academy_access_denied' USING ERRCODE='42501';END IF;
 org:=(access->>'organization_id')::uuid;
 IF org IS NULL THEN SELECT m.organization_id INTO org FROM tj.organization_members m JOIN tj.organizations o ON o.id=m.organization_id AND o.status='active' AND o.deleted_at IS NULL WHERE m.user_id=actor AND m.status='active' ORDER BY m.organization_id LIMIT 1;END IF;
 IF org IS NULL THEN RAISE EXCEPTION 'active_membership_required' USING ERRCODE='42501';END IF;
 IF jsonb_typeof(p_payload)<>'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_payload) k WHERE k NOT IN('action','field','delta','request_id','card_id','answer')) THEN RAISE EXCEPTION 'invalid_payload' USING ERRCODE='22023';END IF;
 IF action='daily_load' THEN RETURN jsonb_build_object('metric_date',day,'metrics',(SELECT to_jsonb(d)-'user_id' FROM tj.academy_daily_metrics d WHERE user_id=actor AND metric_date=day));END IF;
 IF action='tracks_load' THEN RETURN jsonb_build_object('tracks',coalesce((SELECT jsonb_agg(jsonb_build_object('track_key',t.track_key,'name',t.name,'started_at',p.started_at,'completed_at',p.completed_at) ORDER BY t.sort_order) FROM tj.academy_tracks t LEFT JOIN tj.academy_track_progress p ON p.track_key=t.track_key AND p.user_id=actor),'[]'::jsonb));END IF;
 IF action NOT IN('daily_delta','card_answer') THEN RAISE EXCEPTION 'invalid_action' USING ERRCODE='22023';END IF;
 BEGIN req:=(p_payload->>'request_id')::uuid;EXCEPTION WHEN invalid_text_representation THEN RAISE EXCEPTION 'invalid_request_id' USING ERRCODE='22023';END;
 IF req IS NULL THEN RAISE EXCEPTION 'request_id_required' USING ERRCODE='22023';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('academy_records:'||actor::text,0));
 SELECT payload INTO result FROM tj_private.academy_record_events WHERE source_user_id=actor AND request_id=req;
 IF FOUND THEN IF result->'request' IS DISTINCT FROM p_payload THEN RAISE EXCEPTION 'request_id_conflict' USING ERRCODE='22023';END IF;RETURN result->'result';END IF;
 IF action='daily_delta' THEN
  field:=p_payload->>'field';IF field NOT IN('opportunities','captures','asks','touches','attach_presentations','sales') OR field IS NULL OR coalesce(p_payload->>'delta','') NOT IN('-1','1') THEN RAISE EXCEPTION 'invalid_metric' USING ERRCODE='22023';END IF;
  delta:=(p_payload->>'delta')::int;
  INSERT INTO tj.academy_daily_metrics(user_id,metric_date) VALUES(actor,day) ON CONFLICT DO NOTHING;
  EXECUTE format('UPDATE tj.academy_daily_metrics SET %I=greatest(0,%I+$1),updated_at=clock_timestamp() WHERE user_id=$2 AND metric_date=$3 RETURNING to_jsonb(academy_daily_metrics)-''user_id''',field,field) INTO result USING delta,actor,day;
  result:=jsonb_build_object('metric_date',day,'metrics',result);
 ELSE
  IF coalesce(p_payload->>'card_id','') !~ '^[0-9]{1,9}$' THEN RAISE EXCEPTION 'invalid_card' USING ERRCODE='22023';END IF;
  SELECT * INTO card FROM tj.iq_cards WHERE id=(p_payload->>'card_id')::int AND card_type='quiz';
  answer:=p_payload->>'answer';
  IF NOT FOUND OR card.correct_option IS NULL OR card.correct_option='' OR jsonb_typeof(card.options)<>'array' OR NOT (card.options ? card.correct_option) OR answer IS NULL OR NOT(card.options ? answer) THEN RAISE EXCEPTION 'unavailable_quiz_or_answer' USING ERRCODE='22023';END IF;
  result:=jsonb_build_object('card_id',card.id,'deck_id',card.deck_id,'correct',answer=card.correct_option,'correct_option',card.correct_option,'source_date',clock_timestamp());
 END IF;
 INSERT INTO tj_private.academy_record_events(organization_id,source_user_id,request_id,kind,payload) VALUES(org,actor,req,action,jsonb_build_object('request',p_payload,'result',result));
 IF action='card_answer' THEN
  WITH latest AS(SELECT DISTINCT ON((payload->'result'->>'card_id')::int) payload FROM tj_private.academy_record_events WHERE source_user_id=actor AND kind='card_answer' AND (payload->'result'->>'deck_id')::int=card.deck_id ORDER BY (payload->'result'->>'card_id')::int,id DESC)
  SELECT count(*) FILTER(WHERE payload->'result'->>'correct'='true'),count(*) INTO points,total FROM latest;
  INSERT INTO tj.academy_quiz_scores(user_id,vol,score,total,updated_at) VALUES(actor,'deck:'||card.deck_id,points,total,(result->>'source_date')::timestamptz) ON CONFLICT(user_id,vol) DO UPDATE SET score=excluded.score,total=excluded.total,updated_at=excluded.updated_at;
 END IF;
 INSERT INTO tj_private.command_centre_refresh_queue(organization_id,requested_at,next_attempt_at) SELECT DISTINCT organization_id,clock_timestamp(),clock_timestamp() FROM tj.organization_members WHERE user_id=actor AND status='active' ON CONFLICT(organization_id) DO UPDATE SET requested_at=excluded.requested_at,next_attempt_at=excluded.next_attempt_at;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION tj_private.academy_records(jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.academy_records(jsonb) TO authenticated;
CREATE FUNCTION public.tj_runtime_academy_records(p_payload jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$SELECT tj_private.academy_records(p_payload);$$;
REVOKE ALL ON FUNCTION public.tj_runtime_academy_records(jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tj_runtime_academy_records(jsonb) TO authenticated;
CREATE FUNCTION tj_private.academy_reconcile_tracks() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE t tj.academy_tracks%ROWTYPE;required int[];expected int;done int;first_date timestamptz;last_date timestamptz;prev tj.academy_track_progress%ROWTYPE;org uuid;after_date timestamptz;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('academy_tracks:'||NEW.user_id::text,0));
 IF TG_OP='UPDATE' AND NEW.completed_at IS NOT DISTINCT FROM OLD.completed_at THEN RETURN NEW;END IF;
 FOR t IN SELECT * FROM tj.academy_tracks WHERE (SELECT chapter_number FROM tj.academy_chapters WHERE id=NEW.chapter_id)=ANY(coalesce(ch_nums,ARRAY(SELECT generate_series(ch_range_min,ch_range_max)))) LOOP
  required:=coalesce(t.ch_nums,ARRAY(SELECT generate_series(t.ch_range_min,t.ch_range_max)));expected:=cardinality(required);
  IF expected IS NULL OR expected=0 THEN CONTINUE;END IF;
  SELECT count(DISTINCT c.chapter_number),min(p.completed_at),max(p.completed_at) INTO done,first_date,last_date FROM tj.academy_chapters c JOIN tj.academy_progress p ON p.chapter_id=c.id AND p.user_id=NEW.user_id AND p.completed_at IS NOT NULL WHERE c.chapter_number=ANY(required);
  SELECT * INTO prev FROM tj.academy_track_progress WHERE user_id=NEW.user_id AND track_key=t.track_key FOR UPDATE;
  IF done=0 AND NOT FOUND THEN CONTINUE;END IF;
  after_date:=CASE WHEN done=expected THEN coalesce(prev.completed_at,last_date) END;
  IF prev.id IS NOT NULL AND prev.completed_at IS NOT DISTINCT FROM after_date THEN CONTINUE;END IF;
  INSERT INTO tj.academy_track_progress(user_id,track_key,started_at,completed_at) VALUES(NEW.user_id,t.track_key,coalesce(prev.started_at,first_date),after_date) ON CONFLICT(user_id,track_key) DO UPDATE SET completed_at=excluded.completed_at;
  SELECT m.organization_id INTO org FROM tj.organization_members m JOIN tj.organizations o ON o.id=m.organization_id AND o.status='active' AND o.deleted_at IS NULL WHERE m.user_id=NEW.user_id AND m.status='active' ORDER BY m.organization_id LIMIT 1;
  IF org IS NOT NULL THEN INSERT INTO tj_private.academy_record_events(organization_id,source_user_id,request_id,kind,payload) VALUES(org,NEW.user_id,gen_random_uuid(),'track_change',jsonb_build_object('track_key',t.track_key,'previous_completed_at',prev.completed_at,'completed_at',after_date,'required_chapters',expected,'completed_chapters',done));END IF;
 END LOOP;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION tj_private.academy_reconcile_tracks() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER academy_reconcile_tracks AFTER INSERT OR UPDATE OF completed_at ON tj.academy_progress FOR EACH ROW EXECUTE FUNCTION tj_private.academy_reconcile_tracks();
NOTIFY pgrst,'reload schema';

CREATE OR REPLACE FUNCTION tj_private.command_centre_academy_evidence(p_org uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
WITH members AS (SELECT DISTINCT user_id FROM tj.organization_members WHERE organization_id=p_org AND status='active'),
 lessons AS (SELECT p.* FROM tj.academy_progress p JOIN members m USING(user_id)),
 tracks AS (SELECT p.* FROM tj.academy_track_progress p JOIN members m USING(user_id)),
 quizzes AS (SELECT q.* FROM tj.academy_quiz_scores q JOIN members m USING(user_id)),
 daily AS (SELECT d.* FROM tj.academy_daily_metrics d JOIN members m USING(user_id) WHERE metric_date=(now() AT TIME ZONE 'America/Toronto')::date),
 dates AS (SELECT greatest((SELECT max(completed_at) FROM lessons),(SELECT max(greatest(started_at,completed_at)) FROM tracks),(SELECT max(updated_at) FROM quizzes),(SELECT max(updated_at) FROM daily)) source_at)
SELECT jsonb_build_object('active_members',(SELECT count(*) FROM members),'lesson_records',(SELECT count(*) FROM lessons),'track_records',(SELECT count(*) FROM tracks),
 'lesson_completions',CASE WHEN EXISTS(SELECT 1 FROM lessons) THEN (SELECT count(DISTINCT(user_id,chapter_id)) FROM lessons WHERE completed_at IS NOT NULL) END,
 'lesson_completions_this_month',CASE WHEN EXISTS(SELECT 1 FROM lessons) THEN (SELECT count(DISTINCT(user_id,chapter_id)) FROM lessons WHERE (completed_at AT TIME ZONE 'America/Toronto')::date BETWEEN date_trunc('month',now() AT TIME ZONE 'America/Toronto')::date AND (now() AT TIME ZONE 'America/Toronto')::date) END,
 'completed_tracks',CASE WHEN EXISTS(SELECT 1 FROM tracks) THEN (SELECT count(DISTINCT(user_id,track_key)) FROM tracks WHERE completed_at IS NOT NULL) END,
 'started_uncompleted_tracks',CASE WHEN EXISTS(SELECT 1 FROM tracks) THEN (SELECT count(DISTINCT(user_id,track_key)) FROM tracks WHERE started_at IS NOT NULL AND completed_at IS NULL) END,
 'daily_five',jsonb_build_object('metric_date',(now() AT TIME ZONE 'America/Toronto')::date,'recorded_members',(SELECT count(*) FROM daily),'opportunities',(SELECT sum(opportunities) FROM daily),'captures',(SELECT sum(captures) FROM daily),'asks',(SELECT sum(asks) FROM daily),'touches',(SELECT sum(touches) FROM daily),'attach_presentations',(SELECT sum(attach_presentations) FROM daily),'sales',(SELECT sum(sales) FROM daily),'latest_source_at',(SELECT max(updated_at) FROM daily)),
 'completion_pct',NULL,'completion_basis','Recorded lesson/track counts of active organization members; assignment denominator is not recorded, so completion percentage is unknown',
 'source',jsonb_build_object('latest_source_at',source_at,'scope','Active-member dated quizzes, lesson completions and track starts/completions and current-day Daily Five; absent progress is unknown')) FROM dates;
$$;
REVOKE ALL ON FUNCTION tj_private.command_centre_academy_evidence(uuid) FROM PUBLIC,anon,authenticated,service_role;

