ALTER TABLE tj.academy_brand_quiz_scores ENABLE ROW LEVEL SECURITY;
CREATE POLICY consolidation_owned_quiz_read ON tj.academy_brand_quiz_scores FOR SELECT TO authenticated USING(tj_private.is_source_self(user_id));
GRANT SELECT(user_id,brand_id,level,score,total,passed,completed_at) ON tj.academy_brand_quiz_scores TO authenticated;
NOTIFY pgrst,'reload schema';
