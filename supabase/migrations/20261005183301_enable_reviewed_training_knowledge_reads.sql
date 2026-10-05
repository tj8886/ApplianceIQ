ALTER TABLE tj.ai_knowledge_chunks ENABLE ROW LEVEL SECURITY;
CREATE POLICY consolidation_training_knowledge_read ON tj.ai_knowledge_chunks FOR SELECT TO authenticated USING(status='active' AND visibility='global' AND ((organization_id IS NULL AND (SELECT tj_private.has_active_mapped_org())) OR tj_private.can_read_runtime_org(organization_id)));
GRANT SELECT(chunk_key,title,content,organization_id,status,visibility) ON tj.ai_knowledge_chunks TO authenticated;
NOTIFY pgrst,'reload schema';
