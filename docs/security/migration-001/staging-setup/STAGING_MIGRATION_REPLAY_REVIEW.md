# Staging migration replay review

The repository contains 55 timestamped SQL migrations: 54 precede Manufacturer Authorization Migration 001 (`20260722194405_manufacturer_authorization_migration_001.sql`). The earliest is `20260718131521_academy_seed_v1.sql`; the latest pre-Migration-001 file is `20260722191325_brand_academy_quizzes_and_launch.sql`. There are no duplicate timestamps.

Thirty-one pre-Migration-001 files are historical markers whose original DDL is explicitly unavailable. Twelve files include seed/data statements. Some migrations also depend on Auth, Storage, extensions, functions, triggers, RLS, and external-integration configuration. Therefore an empty staging database cannot be reliably reconstructed by simply replaying repository history.

Recommended method: **E. BLOCKED_MIGRATION_HISTORY_INCOMPLETE**. Require an approved, reproducible baseline schema strategy plus an incremental migration plan before any staging bootstrap. Do not copy production schema or data automatically; do not run Migration 001 until later execution authorization.
