# Migration Log

**Last reconciliation**: 2026-07-22
**Production migrations**: 54
**Repository migration files**: 54 (aligned by version)
**DDL coverage**: 23 of 54 contain executable SQL; 31 are historical markers

For the full reconciliation matrix, see [docs/reconciliation/MIGRATION_RECONCILIATION.md](reconciliation/MIGRATION_RECONCILIATION.md).
For schema baseline status, see [docs/reconciliation/SCHEMA_BASELINE_STATUS.md](reconciliation/SCHEMA_BASELINE_STATUS.md).

## Migration Summary

| Category | Count | Contains DDL |
|---|---|---|
| Exact match (original commit) | 14 | Yes |
| Renamed to match production timestamp | 8 | Yes |
| Renamed (was already comment-only) | 1 | No |
| Historical marker (production-only, no DDL) | 30 | No |
| **Total** | **54** | **23** |

## Edge Functions

| Function | Deployable | Source Status | Missing Dependencies |
|---|---|---|---|
| activity-analyzer | Yes | EXACT_PRODUCTION_SOURCE | None |
| ai-request-processor | Yes | EXACT_PRODUCTION_SOURCE | None |
| ai-roleplay | Yes | EXACT_PRODUCTION_SOURCE | None |
| deploy-host | Yes | EXACT_PRODUCTION_SOURCE | None |
| email-dispatcher | Yes | EXACT_PRODUCTION_SOURCE | None |
| embedding-worker | Yes | EXACT_PRODUCTION_SOURCE | None |
| stripe-webhooks | Yes | EXACT_PRODUCTION_SOURCE | None |
| aicrm-ai-enrichment-runner | No | PARTIAL_SOURCE_NON_DEPLOYABLE | Full source not written (~1100 lines) |
| email-webhook | No | PARTIAL_SOURCE_NON_DEPLOYABLE | communication_* tables (6) |
| send-push-notification | No | PARTIAL_SOURCE_NON_DEPLOYABLE | push_*, mobile_notifications tables (3) |
| turnstile-verify | No | MISSING_DEPENDENCIES_NON_DEPLOYABLE | check_turnstile_rate_limit, log_turnstile_verification RPCs |
| file-url-mint | No | MISSING_DEPENDENCIES_NON_DEPLOYABLE | signed_url_nonces, file_access_events, consume_signed_url_nonce |
| storage-deletion-worker | No | MISSING_DEPENDENCIES_NON_DEPLOYABLE | storage_deletion_jobs, file_assets, file_access_events |
| file-scanner | No | MISSING_DEPENDENCIES_NON_DEPLOYABLE | file_assets, file_access_events, v_files_pending_scan |

**7 deployable** (all EXACT_PRODUCTION_SOURCE, committed at HEAD)
**7 non-deployable** (in `supabase/functions/_non_deployable/`, see README there)
