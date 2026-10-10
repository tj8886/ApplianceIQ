CREATE FUNCTION tj_private.submit_ai_feedback(p_signals jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=tj_private.current_source_user_id(); s jsonb; org uuid; cid uuid; tid uuid; typ text; correction text; snapshot jsonb; metadata jsonb; tier text; keyword text; success boolean; failure boolean; rid uuid; gid uuid; message text; turn_content text; category text; brand text; result jsonb:='[]'; c tj.ai_conversations%rowtype;
BEGIN
 IF actor IS NULL THEN RAISE EXCEPTION 'Verified source identity required' USING ERRCODE='42501'; END IF;
 IF jsonb_typeof(p_signals) IS DISTINCT FROM 'array' OR jsonb_array_length(p_signals) NOT BETWEEN 1 AND 20 OR octet_length(p_signals::text)>65536 THEN RAISE EXCEPTION 'Invalid feedback batch' USING ERRCODE='22023'; END IF;
 -- Serializes counters and per-user routing without broad table locks.
 PERFORM pg_advisory_xact_lock(hashtextextended('tj-feedback:'||actor::text,0));
 FOR s IN SELECT value FROM jsonb_array_elements(p_signals) LOOP
  IF jsonb_typeof(s) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'Invalid signal' USING ERRCODE='22023'; END IF;
  typ:=s->>'signal_type';
  IF typ IS NULL OR typ NOT IN ('thumbs_up','thumbs_down','correction','persona_switch','tier_override','follow_up_clarification','rephrase','abandoned','deterministic_escalation','outcome_positive','outcome_negative','custom') THEN RAISE EXCEPTION 'Invalid signal type' USING ERRCODE='22023'; END IF;
  org:=nullif(s->>'organization_id','')::uuid;cid:=nullif(s->>'conversation_id','')::uuid;tid:=nullif(s->>'turn_id','')::uuid;
  IF cid IS NOT NULL THEN
   SELECT * INTO c FROM tj.ai_conversations WHERE id=cid AND user_id=actor;
   IF NOT FOUND OR c.organization_id IS NULL OR NOT tj_private.can_read_runtime_org(c.organization_id) OR (org IS NOT NULL AND org IS DISTINCT FROM c.organization_id) THEN RAISE EXCEPTION 'Conversation access denied' USING ERRCODE='42501'; END IF;
   org:=c.organization_id;
  END IF;
  IF org IS NULL OR NOT tj_private.can_read_runtime_org(org) THEN RAISE EXCEPTION 'Organization access denied' USING ERRCODE='42501'; END IF;
  IF tid IS NOT NULL AND (cid IS NULL OR NOT EXISTS(SELECT 1 FROM tj.ai_conversation_turns WHERE id=tid AND conversation_id=cid)) THEN RAISE EXCEPTION 'Turn access denied' USING ERRCODE='42501'; END IF;
  correction:=s->>'correction_text';snapshot:=coalesce(s->'routing_snapshot','{}');metadata:=coalesce(s->'metadata','{}');
  IF length(correction)>4000 OR jsonb_typeof(snapshot) IS DISTINCT FROM 'object' OR jsonb_typeof(metadata) IS DISTINCT FROM 'object' OR octet_length(snapshot::text)>8000 OR octet_length(metadata::text)>8000 THEN RAISE EXCEPTION 'Invalid feedback payload' USING ERRCODE='22023'; END IF;
  INSERT INTO tj.ai_feedback_signals(conversation_id,turn_id,user_id,organization_id,signal_type,routing_snapshot,correction_text,metadata) VALUES(cid,tid,actor,org,typ,snapshot,correction,metadata);
  INSERT INTO tj.ai_user_preferences(user_id,organization_id,total_thumbs_up,total_thumbs_down,total_corrections,last_active_at)
   VALUES(actor,org,(typ='thumbs_up')::int,(typ='thumbs_down')::int,(typ='correction')::int,now())
   ON CONFLICT(user_id) DO UPDATE SET total_thumbs_up=tj.ai_user_preferences.total_thumbs_up+excluded.total_thumbs_up,total_thumbs_down=tj.ai_user_preferences.total_thumbs_down+excluded.total_thumbs_down,total_corrections=tj.ai_user_preferences.total_corrections+excluded.total_corrections,last_active_at=now(),updated_at=now();
  tier:=coalesce(snapshot->>'tier',snapshot->>'auto_detected');keyword:=split_part(coalesce(snapshot->>'reason',''),'_',1);
  success:=typ IN ('thumbs_up','outcome_positive');failure:=typ IN ('thumbs_down','correction','rephrase','deterministic_escalation');
  IF tier IN ('fast','standard','strong') AND length(keyword) BETWEEN 1 AND 120 AND (success OR failure) THEN
   SELECT id INTO rid FROM tj.ai_routing_weights WHERE user_id=actor AND organization_id=org AND signal_keyword=keyword AND current_tier=tier ORDER BY created_at,id LIMIT 1 FOR UPDATE;
   IF rid IS NULL THEN INSERT INTO tj.ai_routing_weights(user_id,organization_id,signal_keyword,current_tier,success_count,failure_count) VALUES(actor,org,keyword,tier,success::int,failure::int) RETURNING id INTO rid;
   ELSE UPDATE tj.ai_routing_weights SET success_count=success_count+success::int,failure_count=failure_count+failure::int WHERE id=rid; END IF;
   UPDATE tj.ai_routing_weights SET success_rate=round(success_count::numeric/nullif(success_count+failure_count,0),4),recommended_tier=CASE WHEN success_count+failure_count>=10 AND success_count::numeric/(success_count+failure_count)<0.5 THEN CASE current_tier WHEN 'fast' THEN 'standard' WHEN 'standard' THEN 'strong' END END,confidence=CASE WHEN success_count+failure_count>=10 THEN least(1,(success_count+failure_count-10)::numeric/50)*(1-success_count::numeric/(success_count+failure_count)) ELSE 0 END,last_computed_at=now(),updated_at=now() WHERE id=rid;
  END IF;
  IF cid IS NOT NULL AND typ IN ('thumbs_down','correction') THEN
   SELECT content INTO message FROM tj.ai_conversation_turns WHERE conversation_id=cid AND role='user' ORDER BY created_at DESC,id DESC LIMIT 1;
   SELECT content INTO turn_content FROM tj.ai_conversation_turns WHERE id=tid AND conversation_id=cid;
   IF message IS NOT NULL AND (length(correction)>10 OR lower(coalesce(turn_content,'')) ~ '(no data|not found|couldn.t find|no records|unavailable|don.t have)') THEN
    category:=CASE WHEN lower(message) LIKE '%warranty%' THEN 'warranty' WHEN lower(message) LIKE '%recall%' THEN 'recall' WHEN lower(message) ~ '(spec|dimension)' THEN 'specs' WHEN lower(message) ~ '(contact|phone)' THEN 'contact' WHEN lower(message) LIKE '%install%' THEN 'installation' WHEN lower(message) LIKE '%price%' THEN 'pricing' ELSE 'general' END;
    brand:=(regexp_match(message,'\m(Bosch|Samsung|LG|Whirlpool|KitchenAid|GE|Frigidaire|Maytag|Miele|Wolf|Thermador|Viking|JennAir|Dacor|Electrolux|Smeg|Liebherr|Blomberg|Beko|Haier|Asko|Broan|Zephyr|Faber|Cove)\M','i'))[1];
    -- No cross-user sample identifiers or shared user-controlled routing state.
    SELECT id INTO gid FROM tj.ai_knowledge_gaps WHERE organization_id=org AND status='open' AND brand_name IS NOT DISTINCT FROM brand AND query_category=category AND sample_conversation_ids @> ARRAY[cid] ORDER BY created_at,id LIMIT 1 FOR UPDATE;
    IF gid IS NULL THEN INSERT INTO tj.ai_knowledge_gaps(query_text,query_category,brand_name,topic,sample_conversation_ids,organization_id) VALUES(left(message,500),category,brand,left(coalesce(correction,category),200),ARRAY[cid],org);
    ELSE UPDATE tj.ai_knowledge_gaps SET occurrence_count=occurrence_count+1,last_seen_at=now(),updated_at=now() WHERE id=gid; END IF;
   END IF;
  END IF;
  result:=result||jsonb_build_array(jsonb_build_object('ok',true,'signal_type',typ));
 END LOOP;
 RETURN jsonb_build_object('ok',true,'results',result,'signals_processed',jsonb_array_length(result));
END $$;
REVOKE ALL ON FUNCTION tj_private.submit_ai_feedback(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION tj_private.submit_ai_feedback(jsonb) TO authenticated;
CREATE FUNCTION public.tj_submit_ai_feedback(p_signals jsonb) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$SELECT tj_private.submit_ai_feedback(p_signals);$$;
REVOKE ALL ON FUNCTION public.tj_submit_ai_feedback(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.tj_submit_ai_feedback(jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';
