# Migration log

| Date (2026) | Version | Name | Purpose |
|---|---|---|---|
| Jul 18 | 20260718131521 | academy_seed_v1 | Academy schema + curriculum seed |
| Jul 18 | 20260718131629 | foundation_schema_v1 | Foundation objects/facts/relationships |
| Jul 18 | 20260718131647 | memory_schema_v1 | Memory events/facts/subjects |
| Jul 18 | 20260718131708 | privacy_schema_v1 | Consent ledger, DSR requests, purge log |
| Jul 18 | 20260718131846 | security_hardening_v1 | RLS + helper hardening pass 1 |
| Jul 18 | 20260718140815 | daily_metrics_v1 | Academy daily metrics |
| Jul 18 | 20260718141148 | metrics_import_v1 | academy_api_keys + metric imports |
| Jul 18 | 20260718230316 | aiq_kernel_foundations_crm | Organizations, members, CRM core (companies, contacts, deals, tasks, products) |
| Jul 18 | 20260718230510 | aiq_kernel_ai_layer | ai_assistants/requests/sessions/knowledge/audit/usage + governance RPCs |
| Jul 19 | 20260719011509 | aiq_seeds_branding_assistants | Org seeds, brand tokens, assistant seeds |
| Jul 19 | 20260719011720 | aiq_security_hardening | Hardening pass 2 |
| Jul 19 | 20260719012140 | aiq_join_demo_org | join_demo_org RPC |
| Jul 19 | 20260719115706 | aiq_activity_capture_layer | activities, sales_recordings, transcripts, coaching reviews, crm_emails/presentations scaffolding, crm-media bucket policies |
| Jul 19 | 20260719123219 | sales_recording_capture_fields | Recording consent/source/attachment fields, status lifecycle, bucket size cap |
| Jul 19 | 20260719232101 | closeout_security_fixes | **Security fix**: match_products caller-membership guard (cross-tenant vector query defect) |
| Jul 19 | 20260719232401 | closeout_index_tuning | Drop duplicate index; add recording-pipeline FK indexes |

| Jul 20 | 20260720003822 | kpi_events_v1 | KPI event stream, lifecycle/coaching triggers, backfill, Dashboard support |

Repo `supabase/migrations/` mirrors `supabase_migrations.schema_migrations` in prod exactly (17/17).
