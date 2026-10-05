CREATE FUNCTION tj_private.owns_product_conversation(p_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT tj_private.has_active_mapped_org() AND EXISTS(
 SELECT 1 FROM tj.ai_conversations c WHERE c.id=p_id
 AND c.user_id=tj_private.current_source_user_id()
 AND (c.organization_id IS NULL OR tj_private.can_read_runtime_org(c.organization_id)));
$$;
REVOKE ALL ON FUNCTION tj_private.owns_product_conversation(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.owns_product_conversation(uuid) TO authenticated;
ALTER TABLE tj.ai_conversation_memory ENABLE ROW LEVEL SECURITY;
ALTER TABLE tj.ai_product_comparisons ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj.ai_conversation_memory,tj.ai_product_comparisons FROM anon;
GRANT SELECT ON tj.ai_conversation_memory,tj.ai_product_comparisons TO authenticated;
GRANT UPDATE(recommendations,outstanding_questions,updated_at) ON tj.ai_conversation_memory TO authenticated;
GRANT INSERT(organization_id,conversation_id,title,status,comparison_snapshot,selected_product_ids,winner_product_id,updated_at)
 ON tj.ai_product_comparisons TO authenticated;
GRANT UPDATE(organization_id,conversation_id,title,status,comparison_snapshot,selected_product_ids,winner_product_id,updated_at)
 ON tj.ai_product_comparisons TO authenticated;
CREATE POLICY us_owned_product_memory_read ON tj.ai_conversation_memory FOR SELECT TO authenticated
 USING(tj_private.is_source_self(user_id) AND tj_private.owns_product_conversation(conversation_id));
CREATE POLICY us_owned_product_memory_update ON tj.ai_conversation_memory FOR UPDATE TO authenticated
 USING(tj_private.is_source_self(user_id) AND tj_private.owns_product_conversation(conversation_id))
 WITH CHECK(tj_private.is_source_self(user_id) AND tj_private.owns_product_conversation(conversation_id));
CREATE POLICY us_owned_product_comparison_read ON tj.ai_product_comparisons FOR SELECT TO authenticated
 USING(tj_private.is_source_self(user_id) AND tj_private.can_read_runtime_org(organization_id)
 AND (conversation_id IS NULL OR tj_private.owns_product_conversation(conversation_id)));
CREATE POLICY us_owned_product_comparison_insert ON tj.ai_product_comparisons FOR INSERT TO authenticated
 WITH CHECK(tj_private.is_source_self(user_id) AND tj_private.can_read_runtime_org(organization_id)
 AND (conversation_id IS NULL OR tj_private.owns_product_conversation(conversation_id)));
CREATE POLICY us_owned_product_comparison_update ON tj.ai_product_comparisons FOR UPDATE TO authenticated
 USING(tj_private.is_source_self(user_id) AND tj_private.can_read_runtime_org(organization_id)
 AND (conversation_id IS NULL OR tj_private.owns_product_conversation(conversation_id)))
 WITH CHECK(tj_private.is_source_self(user_id) AND tj_private.can_read_runtime_org(organization_id)
 AND (conversation_id IS NULL OR tj_private.owns_product_conversation(conversation_id)));
CREATE FUNCTION tj_private.validate_product_personal_write() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; allowed uuid[];
BEGIN
 IF current_setting('role',true)<>'authenticated' THEN RETURN NEW; END IF;
 actor:=tj_private.current_source_user_id();
 IF actor IS NULL OR NOT tj_private.has_active_mapped_org() THEN RAISE EXCEPTION 'Mapped active user required' USING ERRCODE='42501'; END IF;
 IF TG_TABLE_NAME='ai_conversation_memory' THEN
  IF NEW.user_id<>actor OR NOT tj_private.owns_product_conversation(NEW.conversation_id) THEN RAISE EXCEPTION 'Conversation ownership required' USING ERRCODE='42501'; END IF;
  IF jsonb_typeof(NEW.recommendations)<>'array' OR jsonb_typeof(NEW.outstanding_questions)<>'array' OR octet_length(NEW.recommendations::text)>100000 OR octet_length(NEW.outstanding_questions::text)>10000 THEN RAISE EXCEPTION 'Invalid recommendation memory' USING ERRCODE='22023'; END IF;
 ELSE
  IF TG_OP='INSERT' THEN NEW.user_id:=actor;
  ELSIF NEW.id IS DISTINCT FROM OLD.id OR NEW.organization_id IS DISTINCT FROM OLD.organization_id OR NEW.user_id IS DISTINCT FROM OLD.user_id OR NEW.conversation_id IS DISTINCT FROM OLD.conversation_id THEN RAISE EXCEPTION 'Comparison identity is immutable' USING ERRCODE='42501'; END IF;
  IF NEW.user_id<>actor OR NOT tj_private.can_read_runtime_org(NEW.organization_id) OR (NEW.conversation_id IS NOT NULL AND NOT tj_private.owns_product_conversation(NEW.conversation_id)) THEN RAISE EXCEPTION 'Comparison access denied' USING ERRCODE='42501'; END IF;
  allowed:=tj_private.allowed_catalog_products();
  IF cardinality(NEW.selected_product_ids)<2 OR cardinality(NEW.selected_product_ids)>12 OR EXISTS(SELECT 1 FROM unnest(NEW.selected_product_ids) p WHERE p IS NULL OR NOT(p=ANY(allowed))) OR (NEW.winner_product_id IS NOT NULL AND NOT(NEW.winner_product_id=ANY(NEW.selected_product_ids))) THEN RAISE EXCEPTION 'Comparison products unavailable' USING ERRCODE='42501'; END IF;
  IF jsonb_typeof(NEW.comparison_snapshot)<>'object' OR octet_length(NEW.comparison_snapshot::text)>1000000 OR NEW.title IS NULL OR length(NEW.title)>500 OR btrim(NEW.title)='' THEN RAISE EXCEPTION 'Invalid comparison snapshot' USING ERRCODE='22023'; END IF;
 END IF;
 NEW.updated_at:=clock_timestamp(); RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION tj_private.validate_product_personal_write() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER us_product_memory_validate BEFORE UPDATE ON tj.ai_conversation_memory
 FOR EACH ROW EXECUTE FUNCTION tj_private.validate_product_personal_write();
CREATE TRIGGER us_product_comparison_validate BEFORE INSERT OR UPDATE ON tj.ai_product_comparisons
 FOR EACH ROW EXECUTE FUNCTION tj_private.validate_product_personal_write();
NOTIFY pgrst,'reload schema';
