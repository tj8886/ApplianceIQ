-- Read-only pre-execution report. Run in staging and retain its output with snapshots.
WITH expected_tables(table_name, expected_rows) AS (
  VALUES ('mfr_members', 0::bigint), ('mfr_invites', 0::bigint),
         ('mfr_user_roles', 1::bigint), ('mfr_vendors', 19::bigint)
), current_counts AS (
  SELECT 'mfr_members'::text AS table_name, count(*)::bigint AS actual_rows FROM public.mfr_members
  UNION ALL SELECT 'mfr_invites', count(*) FROM public.mfr_invites
  UNION ALL SELECT 'mfr_user_roles', count(*) FROM public.mfr_user_roles
  UNION ALL SELECT 'mfr_vendors', count(*) FROM public.mfr_vendors
), conflicting_columns AS (
  SELECT table_name, column_name
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND ((table_name = 'mfr_members' AND column_name IN ('role','status','invited_by','approved_by','invitation_id','approved_at','activated_at','suspended_at','revoked_at','expires_at','updated_at','created_by','updated_by','metadata'))
      OR (table_name = 'mfr_invites' AND column_name IN ('vendor_id','invited_user_id','intended_role','intended_status','approved_by','token_hash','token_version','expires_at','accepted_by','revoked_at','revoked_by','superseded_by','metadata')))
), conflicting_indexes AS (
  SELECT indexname
  FROM pg_indexes
  WHERE schemaname = 'public' AND indexname IN ('mfr_members_invitation_id_idx','mfr_members_vendor_status_idx','mfr_invites_vendor_id_idx','mfr_invites_invited_user_id_idx')
)
SELECT
  jsonb_build_object(
    'precheck_pass', NOT EXISTS (SELECT 1 FROM current_counts c JOIN expected_tables e USING (table_name) WHERE c.actual_rows <> e.expected_rows)
      AND NOT EXISTS (SELECT 1 FROM conflicting_columns)
      AND NOT EXISTS (SELECT 1 FROM conflicting_indexes),
    'row_counts', (SELECT jsonb_object_agg(table_name, actual_rows) FROM current_counts),
    'unexpected_new_columns', (SELECT coalesce(jsonb_agg(table_name || '.' || column_name ORDER BY table_name, column_name), '[]'::jsonb) FROM conflicting_columns),
    'conflicting_indexes', (SELECT coalesce(jsonb_agg(indexname ORDER BY indexname), '[]'::jsonb) FROM conflicting_indexes),
    'columns_snapshot', (SELECT jsonb_agg(jsonb_build_object('table',table_name,'column',column_name,'type',data_type,'nullable',is_nullable,'default',column_default) ORDER BY table_name, ordinal_position) FROM information_schema.columns WHERE table_schema='public' AND table_name IN ('mfr_members','mfr_invites','mfr_user_roles','mfr_vendors')),
    'constraints_snapshot', (SELECT jsonb_agg(jsonb_build_object('table',r.relname,'name',c.conname,'definition',pg_get_constraintdef(c.oid)) ORDER BY r.relname,c.conname) FROM pg_constraint c JOIN pg_class r ON r.oid=c.conrelid JOIN pg_namespace n ON n.oid=r.relnamespace WHERE n.nspname='public' AND r.relname IN ('mfr_members','mfr_invites','mfr_user_roles','mfr_vendors')),
    'indexes_snapshot', (SELECT jsonb_agg(jsonb_build_object('table',tablename,'name',indexname,'definition',indexdef) ORDER BY tablename,indexname) FROM pg_indexes WHERE schemaname='public' AND tablename IN ('mfr_members','mfr_invites','mfr_user_roles','mfr_vendors')),
    'rls_snapshot', (SELECT jsonb_agg(jsonb_build_object('table',tablename,'enabled',rowsecurity) ORDER BY tablename) FROM pg_tables WHERE schemaname='public' AND tablename IN ('mfr_members','mfr_invites','mfr_user_roles','mfr_vendors')),
    'policy_snapshot', (SELECT jsonb_agg(jsonb_build_object('table',tablename,'name',policyname,'command',cmd) ORDER BY tablename,policyname) FROM pg_policies WHERE schemaname='public' AND tablename IN ('mfr_members','mfr_invites','mfr_user_roles','mfr_vendors')),
    'global_role_review', 'MANUAL: verify the single mfr_user_roles record outside the database before execution'
  ) AS pre_migration_report;
