CREATE FUNCTION tj_private.product_conversation_state(p_conversation_id uuid DEFAULT NULL,p_organization_id uuid DEFAULT NULL,p_title text DEFAULT 'Product conversation') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=tj_private.current_source_user_id(); c tj.ai_conversations%rowtype; m tj.ai_conversation_memory%rowtype;
BEGIN
 IF actor IS NULL OR NOT tj_private.has_active_mapped_org() THEN RAISE EXCEPTION 'Mapped active user required' USING ERRCODE='42501'; END IF;
 IF p_conversation_id IS NULL THEN
  IF p_organization_id IS NULL OR NOT tj_private.can_read_runtime_org(p_organization_id) THEN RAISE EXCEPTION 'Organization access denied' USING ERRCODE='42501'; END IF;
  IF p_title IS NULL OR btrim(p_title)='' OR length(p_title)>120 THEN RAISE EXCEPTION 'Invalid title' USING ERRCODE='22023'; END IF;
  INSERT INTO tj.ai_conversations(user_id,organization_id,title,stage,status) VALUES(actor,p_organization_id,p_title,'discovery','active') RETURNING * INTO c;
 ELSE
  IF NOT tj_private.owns_product_conversation(p_conversation_id) THEN RAISE EXCEPTION 'Conversation access denied' USING ERRCODE='42501'; END IF;
  SELECT * INTO c FROM tj.ai_conversations WHERE id=p_conversation_id FOR UPDATE;
  IF p_organization_id IS NOT NULL AND p_organization_id IS DISTINCT FROM c.organization_id THEN RAISE EXCEPTION 'Organization mismatch' USING ERRCODE='42501'; END IF;
 END IF;
 INSERT INTO tj.ai_conversation_memory(conversation_id,user_id,memory_version) VALUES(c.id,actor,0) ON CONFLICT(conversation_id) DO NOTHING;
 SELECT * INTO m FROM tj.ai_conversation_memory WHERE conversation_id=c.id;
 IF m.user_id IS DISTINCT FROM actor THEN RAISE EXCEPTION 'Memory ownership mismatch' USING ERRCODE='42501'; END IF;
 RETURN jsonb_build_object('conversation_id',c.id,'stage',c.stage,'memory_version',m.memory_version,'profile',m.profile);
END $$;
CREATE FUNCTION tj_private.commit_product_conversation(p_conversation_id uuid,p_expected_version integer,p_message text,p_facts jsonb,p_models jsonb DEFAULT '[]',p_stage text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=tj_private.current_source_user_id(); m tj.ai_conversation_memory%rowtype; profile jsonb; contradictions jsonb; k text; v jsonb; old jsonb; merged jsonb; score integer; stage text; changed jsonb:='[]';
BEGIN
 IF actor IS NULL OR NOT tj_private.owns_product_conversation(p_conversation_id) THEN RAISE EXCEPTION 'Conversation access denied' USING ERRCODE='42501'; END IF;
 PERFORM 1 FROM tj.ai_conversations WHERE id=p_conversation_id FOR UPDATE;
 SELECT * INTO m FROM tj.ai_conversation_memory WHERE conversation_id=p_conversation_id FOR UPDATE;
 IF NOT FOUND OR m.user_id IS DISTINCT FROM actor THEN RAISE EXCEPTION 'Memory access denied' USING ERRCODE='42501'; END IF;
 IF m.memory_version IS DISTINCT FROM p_expected_version THEN RAISE EXCEPTION 'Conversation changed; reload before retrying' USING ERRCODE='40001'; END IF;
 IF p_message IS NULL OR btrim(p_message)='' OR length(p_message)>4000 OR jsonb_typeof(p_facts) IS DISTINCT FROM 'object' OR octet_length(p_facts::text)>10000 OR jsonb_typeof(p_models) IS DISTINCT FROM 'array' OR jsonb_array_length(p_models)>30 THEN RAISE EXCEPTION 'Invalid conversation input' USING ERRCODE='22023'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_models) x WHERE jsonb_typeof(x)<>'string' OR length(x#>>'{}')>120) THEN RAISE EXCEPTION 'Invalid model list' USING ERRCODE='22023'; END IF;
 profile:=coalesce(m.profile,'{}');
 FOR k,v IN SELECT * FROM jsonb_each(p_facts) LOOP
  IF NOT(k=ANY(ARRAY['category','budget_max','budget_min','opening_width','opening_height','opening_depth','finish','household_size','must_have','deal_breakers','preferred_brands','excluded_brands','installation_type','fuel_type','energy_star','accessibility_needs','timeline','location','use_cases'])) THEN RAISE EXCEPTION 'Unsupported profile key' USING ERRCODE='22023'; END IF;
  IF v='null'::jsonb THEN CONTINUE; END IF;
  IF k=ANY(ARRAY['budget_max','budget_min','opening_width','opening_height','opening_depth','household_size']) THEN
   IF jsonb_typeof(v)<>'number' OR (v#>>'{}')::numeric<=0 OR (v#>>'{}')::numeric>1000000 THEN RAISE EXCEPTION 'Invalid numeric fact' USING ERRCODE='22023'; END IF;
  ELSIF k='energy_star' THEN
   IF jsonb_typeof(v)<>'boolean' THEN RAISE EXCEPTION 'Invalid energy fact' USING ERRCODE='22023'; END IF;
  ELSIF k=ANY(ARRAY['must_have','deal_breakers','preferred_brands','excluded_brands','accessibility_needs','use_cases']) THEN
   IF jsonb_typeof(v)<>'array' THEN RAISE EXCEPTION 'Invalid list fact' USING ERRCODE='22023'; END IF;
   IF jsonb_array_length(v)>30 OR EXISTS(SELECT 1 FROM jsonb_array_elements(v) x WHERE jsonb_typeof(x)<>'string' OR length(x#>>'{}')>120) THEN RAISE EXCEPTION 'Invalid list content' USING ERRCODE='22023'; END IF;
  ELSE
   IF jsonb_typeof(v)<>'string' OR length(v#>>'{}')>200 THEN RAISE EXCEPTION 'Invalid text fact' USING ERRCODE='22023'; END IF;
  END IF;
  IF v='""'::jsonb OR v='[]'::jsonb THEN CONTINUE; END IF;
  old:=profile->k;
  IF old IS NOT NULL AND old<>v THEN changed:=changed||jsonb_build_array(jsonb_build_object('field',k,'previous',old,'current',v,'detected_at',clock_timestamp())); END IF;
  IF jsonb_typeof(v)='array' THEN
   SELECT coalesce(jsonb_agg(DISTINCT x),'[]') INTO merged FROM jsonb_array_elements((CASE WHEN jsonb_typeof(old)='array' THEN old ELSE '[]'::jsonb END)||v) x;
   v:=merged;
  END IF;
  profile:=jsonb_set(profile,ARRAY[k],v,true);
 END LOOP;
 SELECT coalesce(jsonb_agg(value ORDER BY ord),'[]') INTO contradictions FROM (SELECT value,ord FROM jsonb_array_elements(coalesce(m.contradictions,'[]')||changed) WITH ORDINALITY e(value,ord) ORDER BY ord DESC LIMIT 50) q;
 SELECT coalesce(sum(weight),0) INTO score FROM (VALUES('category',18),('budget_max',16),('opening_width',14),('opening_height',10),('opening_depth',10),('must_have',12),('finish',6),('household_size',6),('timeline',4),('installation_type',4)) w(key,weight) WHERE profile->key IS NOT NULL AND profile->key NOT IN('null'::jsonb,'""'::jsonb,'[]'::jsonb);
 stage:=coalesce(p_stage,CASE WHEN score>=80 THEN 'product_selection' WHEN score>=55 THEN 'qualification' ELSE 'discovery' END);
 IF NOT(stage=ANY(ARRAY['discovery','qualification','product_selection','comparison','installation_review','quote_preparation','objection_handling','close','follow_up','post_sale'])) THEN RAISE EXCEPTION 'Invalid stage' USING ERRCODE='22023'; END IF;
 SELECT coalesce(jsonb_agg(DISTINCT x),'[]') INTO merged FROM jsonb_array_elements(coalesce(m.discussed_models,'[]')||p_models) x;
 INSERT INTO tj.ai_conversation_turns(conversation_id,user_id,role,content,extracted_facts) VALUES(p_conversation_id,actor,'user',p_message,p_facts);
 UPDATE tj.ai_conversation_memory SET profile=commit_product_conversation.profile,contradictions=commit_product_conversation.contradictions,discussed_models=merged,completeness_score=score,memory_version=m.memory_version+1,updated_at=clock_timestamp(),outstanding_questions=(SELECT coalesce(jsonb_agg(key),'[]') FROM unnest(ARRAY['category','budget_max','opening_width','opening_height','opening_depth','must_have','finish','household_size','timeline']) key WHERE commit_product_conversation.profile->key IS NULL OR commit_product_conversation.profile->key IN('null'::jsonb,'""'::jsonb,'[]'::jsonb)) WHERE conversation_id=p_conversation_id;
 UPDATE tj.ai_conversations SET stage=commit_product_conversation.stage,last_message_at=clock_timestamp(),updated_at=clock_timestamp() WHERE id=p_conversation_id;
 RETURN jsonb_build_object('conversation_id',p_conversation_id,'stage',stage,'profile',profile,'contradictions',changed,'completeness_score',score,'memory_version',m.memory_version+1);
END $$;
REVOKE ALL ON FUNCTION tj_private.product_conversation_state(uuid,uuid,text),tj_private.commit_product_conversation(uuid,integer,text,jsonb,jsonb,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.product_conversation_state(uuid,uuid,text),tj_private.commit_product_conversation(uuid,integer,text,jsonb,jsonb,text) TO authenticated;
CREATE FUNCTION public.tj_product_conversation_state(p_conversation_id uuid DEFAULT NULL,p_organization_id uuid DEFAULT NULL,p_title text DEFAULT 'Product conversation') RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.product_conversation_state(p_conversation_id,p_organization_id,p_title); $$;
CREATE FUNCTION public.tj_commit_product_conversation(p_conversation_id uuid,p_expected_version integer,p_message text,p_facts jsonb,p_models jsonb DEFAULT '[]',p_stage text DEFAULT NULL) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.commit_product_conversation(p_conversation_id,p_expected_version,p_message,p_facts,p_models,p_stage); $$;
REVOKE ALL ON FUNCTION public.tj_product_conversation_state(uuid,uuid,text),public.tj_commit_product_conversation(uuid,integer,text,jsonb,jsonb,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tj_product_conversation_state(uuid,uuid,text),public.tj_commit_product_conversation(uuid,integer,text,jsonb,jsonb,text) TO authenticated;
NOTIFY pgrst,'reload schema';
