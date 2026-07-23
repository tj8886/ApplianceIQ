# Baseline generation runbook

Prerequisites: explicit production target, explicit staging exclusion, approved strategy, approved object policy, and a read-only schema-only extraction mechanism. Generate only a candidate outside `supabase/migrations`, for example `docs/security/staging-baseline/generated/applianceiq_schema_baseline_candidate.sql`.

Command pattern only: `pg_dump --schema-only --no-owner --no-privileges --schema=public <PRODUCTION_READ_ONLY_CONNECTION_REFERENCE> > <CANDIDATE_PATH>`. The connection reference must be supplied through an approved secret mechanism and must never appear in Git, output, or documentation.

Before any staging use, remove system-managed, data, secret-bearing, environment-specific, and production-only statements; parse the candidate; inventory statements; review functions, RLS, policies, triggers, ownership, grants, and extensions; then obtain human approval. Never auto-apply the candidate and never target production with it.
