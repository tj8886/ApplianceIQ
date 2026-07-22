# Repository Schema Baseline Status

**Date**: 2026-07-22
**Production**: fumwwhyozeouoqscolke (ApplianceIQ, ca-central-1)

## Can the Repository Recreate Production from Empty State?

**NO.** The repository can **partially track production history** but cannot reproduce the full schema.

### What the repository CAN do:

1. **Track the complete migration version history** — all 54 production migration versions are represented as files (24 with DDL, 30 as historical markers).
2. **Reproduce the first 14 migrations exactly** — these contain full DDL and were committed with matching content.
3. **Reproduce 10 additional migrations** — renamed to match production timestamps, content verified identical.
4. **Document what the remaining 30 migrations created** — historical markers list the tables, functions, and objects each migration introduced.
5. **Provide exact Edge Function source** for 11 of 14 deployed functions.

### What the repository CANNOT do:

1. **Recreate ~100 tables** from the AI CRM, industry intelligence, brand catalog, manufacturer, SpecIQ RLS, or Brand Academy domains — the 30 historical marker files contain no DDL.
2. **Recreate ~40 functions** in the public and private schemas that were created by those 30 migrations.
3. **Recreate ~280 RLS policies** and ~200 indexes created by those migrations.
4. **Recreate the file-security schema** — tables `file_assets`, `signed_url_nonces`, `file_access_events`, `storage_deletion_jobs`, and view `v_files_pending_scan` do not exist in production either (see PROPOSED_FILE_SECURITY_SCHEMA.sql).
5. **Deploy 7 edge functions** — all 7 production-only functions are in `_non_deployable/` due to missing schema dependencies or incomplete source. See `supabase/functions/_non_deployable/README.md`.

### What would be needed to fully reproduce:

Option A: **pg_dump the production schema** and commit the DDL as a baseline migration. This is the most reliable approach but requires database admin access.

Option B: **Extract DDL programmatically** from information_schema and pg_catalog for all 183 tables, 6 views, ~50 functions, ~110 triggers, ~390 policies, and ~350 indexes. This is feasible via the Supabase MCP but would produce a very large file (~5000+ lines).

Option C: **Accept partial reproducibility** and document the gap. New environments would be created by restoring a production backup or by running the 24 DDL migrations and then manually applying the missing objects.

### Current recommendation:

The repository should adopt **Option C** for now: commit the historical markers honestly, ensure all edge function source is preserved, and plan Option A or B as a follow-up task when database admin access is available.

## Production Object Counts

| Category | Count |
|---|---|
| Tables | 183 |
| Views | 6 |
| Enums | 9 |
| Public functions | ~50 (excluding vector extension) |
| Private functions | 12 |
| Triggers | ~110 |
| RLS policies | ~390 |
| Non-primary indexes | ~350 |
| Storage buckets | 5 |
| Storage policies | 10 |
| Edge functions deployed | 14 |
| Extensions | 8 |

## Migration Coverage

| Status | Count | DDL Available |
|---|---|---|
| Exact match (full DDL) | 14 | Yes |
| Renamed (full DDL, timestamp corrected) | 10 | Yes |
| Historical marker (no DDL) | 30 | No |
| **Total** | **54** | **24 of 54** |
