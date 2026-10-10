DROP FUNCTION IF EXISTS public.aiq_ingest_migrated_runtime_environment(jsonb);
DROP FUNCTION IF EXISTS tj_private.ingest_migrated_runtime_environment(jsonb);
NOTIFY pgrst, 'reload schema';
