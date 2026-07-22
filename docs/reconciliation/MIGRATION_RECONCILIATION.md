# Migration Reconciliation Report

**Date**: 2026-07-22
**Supabase project**: fumwwhyozeouoqscolke (ApplianceIQ, ca-central-1)
**Repository**: tj8886/ApplianceIQ
**Current commit**: 4592f79

---

## Executive Summary

Production contains **54 applied migrations**. The repository contains **24 migration files**. Of the 24 local files, 14 are exact matches with production, 10 have timestamp mismatches (same name, different version number), and **30 production migrations have no local file at all**.

The 30 missing migrations cover the entire **AI CRM domain** (phases 3–21), **industry intelligence**, **brand catalog/training**, **AI personas**, **SpecIQ RLS policies**, and the **Brand Academy** feature. These represent the majority of the production database's complexity.

Additionally, **7 of 14 deployed edge functions** have no source in the repository, and the `private` schema contains **12 functions** not represented in any local file.

---

## Migration Reconciliation Matrix

| # | Prod Version | Prod Name | Local File | Classification | Risk | Treatment |
|---|---|---|---|---|---|---|
| 1 | 20260718131521 | academy_seed_v1 | 20260718131521_academy_seed_v1.sql | EXACT_MATCH | None | Keep |
| 2 | 20260718131629 | foundation_schema_v1 | 20260718131629_foundation_schema_v1.sql | EXACT_MATCH | None | Keep |
| 3 | 20260718131647 | memory_schema_v1 | 20260718131647_memory_schema_v1.sql | EXACT_MATCH | None | Keep |
| 4 | 20260718131708 | privacy_schema_v1 | 20260718131708_privacy_schema_v1.sql | EXACT_MATCH | None | Keep |
| 5 | 20260718131846 | security_hardening_v1 | 20260718131846_security_hardening_v1.sql | EXACT_MATCH | None | Keep |
| 6 | 20260718140815 | daily_metrics_v1 | 20260718140815_daily_metrics_v1.sql | EXACT_MATCH | None | Keep |
| 7 | 20260718141148 | metrics_import_v1 | 20260718141148_metrics_import_v1.sql | EXACT_MATCH | None | Keep |
| 8 | 20260718230316 | aiq_kernel_foundations_crm | 20260718230316_aiq_kernel_foundations_crm.sql | EXACT_MATCH | None | Keep |
| 9 | 20260718230510 | aiq_kernel_ai_layer | 20260718230510_aiq_kernel_ai_layer.sql | EXACT_MATCH | None | Keep |
| 10 | 20260719011509 | aiq_seeds_branding_assistants | 20260719011509_aiq_seeds_branding_assistants.sql | EXACT_MATCH | None | Keep |
| 11 | 20260719011720 | aiq_security_hardening | 20260719011720_aiq_security_hardening.sql | EXACT_MATCH | None | Keep |
| 12 | 20260719012140 | aiq_join_demo_org | 20260719012140_aiq_join_demo_org.sql | EXACT_MATCH | None | Keep |
| 13 | 20260719115706 | aiq_activity_capture_layer | 20260719115706_aiq_activity_capture_layer.sql | EXACT_MATCH | None | Keep |
| 14 | 20260719123219 | sales_recording_capture_fields | 20260719123219_sales_recording_capture_fields.sql | EXACT_MATCH | None | Keep |
| 15 | 20260720002359 | closeout_security_fixes | 20260719232101_closeout_security_fixes.sql | TIMESTAMP_MISMATCH | Low | Rename local file |
| 16 | 20260720002435 | closeout_index_tuning | 20260719232401_closeout_index_tuning.sql | TIMESTAMP_MISMATCH | Low | Rename local file |
| 17 | 20260720003822 | kpi_events_v1 | 20260720003822_kpi_events_v1.sql | EXACT_MATCH | None | Keep |
| 18 | 20260720004211 | email_dispatch_v1 | 20260720011501_email_dispatch_v1.sql | TIMESTAMP_MISMATCH | Low | Rename local file |
| 19 | 20260720140201 | applianceiq_access_helpers_recovery | — | PRODUCTION_ONLY | Medium | Add baseline file |
| 20 | 20260720140445 | applianceiq_profiles_compatibility | — | PRODUCTION_ONLY | Medium | Add baseline file |
| 21 | 20260720140606 | phase_3_aicrm_import_foundation_recovery | — | PRODUCTION_ONLY | Medium | Add baseline file |
| 22 | 20260720140746 | phase_4_aicrm_account_views_and_tags_recovery | — | PRODUCTION_ONLY | Medium | Add baseline file |
| 23 | 20260720140952 | phase_6_aicrm_operating_layer_recovery | — | PRODUCTION_ONLY | Medium | Add baseline file |
| 24 | 20260720141106 | phase_7_aicrm_enrichment_framework_recovery | — | PRODUCTION_ONLY | Medium | Add baseline file |
| 25 | 20260720141124 | phase_8_aicrm_scoring_engine_recovery | — | PRODUCTION_ONLY | Medium | Add baseline file |
| 26 | 20260720141318 | phase_9_aicrm_outreach_framework_recovery | — | PRODUCTION_ONLY | Medium | Add baseline file |
| 27 | 20260720141435 | applianceiq_ai_research_expansion | — | PRODUCTION_ONLY | Medium | Add baseline file |
| 28 | 20260720141621 | phase_10_aicrm_executive_dashboard_recovery | — | PRODUCTION_ONLY | Medium | Add baseline file |
| 29 | 20260720141941 | phase_11_aicrm_anthropic_intelligence_recovery | — | PRODUCTION_ONLY | Medium | Add baseline file |
| 30 | 20260720142043 | phase_11_5_aicrm_product_fit_matrix_recovery | — | PRODUCTION_ONLY | Medium | Add baseline file |
| 31 | 20260720142355 | phase_11_6_platform_configuration_engine_recovery | — | PRODUCTION_ONLY | Medium | Add baseline file |
| 32 | 20260720142557 | phase_12_market_intelligence_engine_recovery | — | PRODUCTION_ONLY | Medium | Add baseline file |
| 33 | 20260720142652 | phase_13_relationship_intelligence_engine_recovery | — | PRODUCTION_ONLY | Medium | Add baseline file |
| 34 | 20260720142901 | phase_14_execution_intelligence_engine_recovery | — | PRODUCTION_ONLY | Medium | Add baseline file |
| 35 | 20260720142930 | phase_15_forecasting_revenue_intelligence_recovery | — | PRODUCTION_ONLY | Medium | Add baseline file |
| 36 | 20260720142954 | phase_16_learning_intelligence_engine_recovery | — | PRODUCTION_ONLY | Medium | Add baseline file |
| 37 | 20260720143401 | phase_17_territory_coverage_intelligence_recovery_v2 | — | PRODUCTION_ONLY | Medium | Add baseline file |
| 38 | 20260720143435 | phase_20_industry_knowledge_graph_engine_recovery | — | PRODUCTION_ONLY | Medium | Add baseline file |
| 39 | 20260720143614 | phase_21_ecosystem_collaboration_platform_recovery | — | PRODUCTION_ONLY | Medium | Add baseline file |
| 40 | 20260720144156 | applianceiq_industry_intelligence_recovery | — | PRODUCTION_ONLY | Medium | Add baseline file |
| 41 | 20260720144655 | applianceiq_industry_intelligence_recovery | — | PRODUCTION_ONLY | Medium | Add baseline file |
| 42 | 20260720145408 | applianceiq_industry_intelligence_version_security | — | PRODUCTION_ONLY | Medium | Add baseline file |
| 43 | 20260721020000 | billing_schema_v1 | 20260720015201_billing_schema_v1.sql | TIMESTAMP_MISMATCH | Low | Rename local file |
| 44 | 20260721023123 | custom_kpis_and_roleplay_v1 | 20260720020301_custom_kpis_and_roleplay_v1.sql | TIMESTAMP_MISMATCH | Low | Rename local file |
| 45 | 20260721025031 | ai_personas_v1 | — | PRODUCTION_ONLY | Medium | Add baseline file |
| 46 | 20260721181644 | team_invites_v1 | 20260721_team_invites_v1.sql | TIMESTAMP_MISMATCH | Low | Rename local file |
| 47 | 20260721195759 | budget_metrics_hierarchy_v1 | 20260721_budget_metrics_hierarchy_v1.sql | TIMESTAMP_MISMATCH | Low | Rename local file |
| 48 | 20260721234042 | brands_margin_periods_v1 | — | PRODUCTION_ONLY | Medium | Add baseline file |
| 49 | 20260722002119 | speciq_core_tables | 20260722_speciq_core_tables.sql | TIMESTAMP_MISMATCH | Low | Rename local file |
| 50 | 20260722021852 | speciq_rls_policies | — | PRODUCTION_ONLY | Medium | Add baseline file |
| 51 | 20260722023727 | speciq_retailer_settings | 20260722_speciq_retailer_settings.sql | TIMESTAMP_MISMATCH | Low | Rename local file |
| 52 | 20260722123959 | create_brand_training_cards | — | PRODUCTION_ONLY | Medium | Add baseline file |
| 53 | 20260722142835 | brand_academy_phase1_schema | — | PRODUCTION_ONLY | Medium | Add baseline file |
| 54 | 20260722191325 | brand_academy_quizzes_and_launch | — | PRODUCTION_ONLY | Medium | Add baseline file |

### Summary

| Classification | Count |
|---|---|
| EXACT_MATCH | 14 |
| TIMESTAMP_MISMATCH | 10 |
| PRODUCTION_ONLY | 30 |
| REPOSITORY_ONLY | 0 |
| **Total** | **54** |

---

## Production-Only Objects Not in Repository

### Edge Functions — 7 previously absent from repo, now recovered as non-deployable

All 7 functions below are deployed in production but have **missing schema dependencies**
or **incomplete source**. They are stored in `supabase/functions/_non_deployable/`.

| Function | JWT | Status | Missing Dependencies |
|---|---|---|---|
| email-webhook | false | PARTIAL_SOURCE_NON_DEPLOYABLE | communication_* tables (6, absent from production) |
| send-push-notification | true | PARTIAL_SOURCE_NON_DEPLOYABLE | push_*, mobile_notifications (3, absent from production) |
| file-url-mint | true | MISSING_DEPENDENCIES_NON_DEPLOYABLE | signed_url_nonces, file_access_events, consume_signed_url_nonce (absent) |
| storage-deletion-worker | true | MISSING_DEPENDENCIES_NON_DEPLOYABLE | storage_deletion_jobs, file_assets, file_access_events (absent) |
| file-scanner | true | MISSING_DEPENDENCIES_NON_DEPLOYABLE | file_assets, v_files_pending_scan (absent) |
| turnstile-verify | false | MISSING_DEPENDENCIES_NON_DEPLOYABLE | check_turnstile_rate_limit, log_turnstile_verification RPCs (absent) |
| aicrm-ai-enrichment-runner | true | PARTIAL_SOURCE_NON_DEPLOYABLE | Schema exists; full source (~1100 lines) not written |

See `supabase/functions/_non_deployable/README.md` for full dependency details.

### Private Schema Functions (12)

- `private.set_updated_at()` — generic updated_at trigger
- `private.sync_profiles_id()` — ensures profiles.id = user_id
- `private.user_can_access_organization()` — org permission check
- `private.user_has_org_permission()` — org permission lookup
- `private.aicrm_handle_market_account_change()` — market event trigger on accounts
- `private.aicrm_handle_market_contact_change()` — market event trigger on contacts
- `private.aicrm_queue_market_refresh()` — enqueue market refresh
- `private.aicrm_record_market_event()` — insert market events
- `private.aicrm_record_opportunity_timeline_event()` — opportunity timeline trigger
- `private.aicrm_seed_execution_defaults()` — seed playbooks on org creation
- `private.aicrm_seed_execution_defaults_from_trigger()` — trigger wrapper
- `private.aicrm_sync_person_current_employment()` — sync current employment from history

### Views (6)

- `crm_conversation_records` — joins activities/recordings/transcripts/coaching
- `v_daily_metrics_rollup` — 7d/28d metrics rollup
- `v_memory_current` — non-superseded memory facts
- `v_steward_queue` — candidate/disputed facts queue
- `v_vendors` — vendor list from mfr_vendors
- `v_verified_facts` — verified facts with object names

### Enums (9)

- `aicrm_custom_field_type`
- `aicrm_import_row_status`
- `aicrm_import_source`
- `aicrm_import_status`
- `company_status`
- `iq_customer_wait_status`
- `iq_notification_status`
- `iq_status_type`
- `lifecycle_stage`

### Extensions (non-default)

- `citext`, `pg_trgm`, `pgcrypto`, `uuid-ossp`, `vector` (0.8.2), `supabase_vault`

### Storage Buckets (5)

- `chapter-audio` (public)
- `crm-media` (private, 50MB limit)
- `deploy-drop` (public)
- `retailer-logos` (public)
- `vendor-assets` (public)

### Tables Without RLS Policies (20)

These tables have RLS enabled but no policies defined (access is blocked for anon/authenticated):

academy_api_keys, academy_cohort_members, academy_cohorts, academy_firms,
academy_metric_imports, academy_seats, app_bundles, consent_ledger,
dsr_downstream_notices, dsr_requests, embedding_worker_runs,
foundation_audit_log, foundation_disputes, foundation_fact_reviews,
memory_events, memory_facts, memory_subject_links, memory_subjects,
privacy_purge_log, stripe_events

### Production Statistics

- **183 tables** (all RLS enabled except stripe_events)
- **6 views**
- **9 enums**
- **~50 custom functions** (public schema, excluding vector extension)
- **12 private schema functions**
- **~110 triggers**
- **~390+ RLS policies**
- **~350+ non-primary indexes**
- **14 deployed edge functions**

---

## Recommended Baseline Strategy

### Approach: **Hybrid** (Option 3)

**Why**: The 14 EXACT_MATCH files are trustworthy and should stay as-is. The 10 TIMESTAMP_MISMATCH files contain the correct SQL but have wrong filenames — they should be renamed to match production versions. The 30 PRODUCTION_ONLY migrations cannot be reliably reconstructed from their original SQL (the migration content was applied interactively via MCP and is not recoverable). Instead, we will create **stub baseline files** — one per production migration record — containing a header comment that documents what the migration created, with the actual DDL captured in a single comprehensive production schema snapshot.

### Plan

1. **Rename 10 TIMESTAMP_MISMATCH files** to match their production version numbers.
2. **Create 30 stub files** for PRODUCTION_ONLY migrations — each contains a header comment documenting domain, affected tables, and a note that it was applied to production and should not be replayed.
3. **Create a comprehensive schema snapshot** (`docs/reconciliation/PRODUCTION_SCHEMA_SNAPSHOT.sql`) capturing all production DDL for reference.
4. **Update documentation** (README, migration-log.md, DEPLOYMENT.md).

### Why this is safe

- No SQL is executed against production.
- No production migration history is modified.
- The renamed local files match production version numbers, so `supabase db push` sees them as already-applied.
- Stub files have the same version/name as production records, so they too are seen as already-applied.
- A fresh `supabase db reset` from a clean database will need the full schema snapshot to actually create objects — but that is appropriate for a baseline approach where production is the source of truth.

### How a new environment would be created

A developer would run the complete migration set (which now matches the production migration history) plus apply the schema snapshot to fill in any objects the stubs don't actually create. The schema snapshot is the authoritative DDL reference.

### How future migrations will work

All new migrations follow the standard workflow: create a timestamped file, test locally, commit, deploy via `supabase db push` or MCP `apply_migration`. The reconciliation ensures the migration history is continuous and no version gaps exist.
