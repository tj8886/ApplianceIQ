# Non-Deployable Edge Functions

These functions are deployed in the production Supabase project (`fumwwhyozeouoqscolke`)
but cannot be safely redeployed from the repository because they have **missing schema
dependencies** or **incomplete source**.

They are stored here for reference and future resolution. **Do not move them into the
deployable path** (`supabase/functions/<name>/`) until their dependencies are confirmed
and their source is verified complete.

## Function Inventory

### turnstile-verify
- **Source status**: PARTIAL_SOURCE_NON_DEPLOYABLE
- **Auth**: JWT disabled (public CAPTCHA endpoint)
- **Missing dependencies**:
  - `check_turnstile_rate_limit` — RPC does not exist in production
  - `log_turnstile_verification` — RPC does not exist in production
- **Env vars**: `TURNSTILE_SECRET_KEY`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`
- **Notes**: Source retrieved from production is structurally complete but references
  RPCs that do not exist. The function may silently fail on those calls in production.

### email-webhook
- **Source status**: PARTIAL_SOURCE_NON_DEPLOYABLE
- **Auth**: JWT disabled (Resend webhook callbacks)
- **Missing dependencies** (all absent from production):
  - `communication_webhook_events` (table)
  - `communication_email_messages` (table)
  - `communication_email_threads` (table)
  - `communication_email_attachments` (table)
  - `communication_record_links` (table)
  - `communication_audit_events` (table)
- **Env vars**: `RESEND_WEBHOOK_SECRET`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`
- **Notes**: Source is a simplified framework. Full production source (~500 lines) was
  retrieved via `get_edge_function` and is available in conversation history.

### send-push-notification
- **Source status**: PARTIAL_SOURCE_NON_DEPLOYABLE
- **Auth**: JWT enabled
- **Missing dependencies** (all absent from production):
  - `push_subscriptions` (table)
  - `push_delivery_attempts` (table)
  - `mobile_notifications` (table)
- **Env vars**: `WEB_PUSH_PUBLIC_KEY`, `WEB_PUSH_PRIVATE_KEY`, `WEB_PUSH_VAPID_SUBJECT`
- **Notes**: Source is a simplified framework. Full production source was retrieved.

### aicrm-ai-enrichment-runner
- **Source status**: PARTIAL_SOURCE_NON_DEPLOYABLE
- **Auth**: JWT enabled
- **Schema dependencies**: All exist in production (aicrm_accounts, aicrm_ai_enrichment_jobs,
  aicrm_enrichment_runs, aicrm_ai_research, aicrm_account_product_fit, ai_prompt_templates)
- **Missing source**: Full implementation is ~1100 lines. Only a 52-line structural
  placeholder is written. Complete source was retrieved via `get_edge_function` and is
  available in conversation history.
- **External dep**: `packages/elev8-ai-service/index.ts` (not in repo)
- **Env vars**: `ANTHROPIC_API_KEY`, `ANTHROPIC_MODEL`, many others

### file-url-mint
- **Source status**: MISSING_DEPENDENCIES_NON_DEPLOYABLE
- **Missing dependencies**:
  - `signed_url_nonces` (table — does not exist in production)
  - `file_access_events` (table — does not exist in production)
  - `consume_signed_url_nonce` (RPC — does not exist in production)
- **Proposed schema**: See `docs/reconciliation/PROPOSED_FILE_SECURITY_SCHEMA.sql`

### storage-deletion-worker
- **Source status**: MISSING_DEPENDENCIES_NON_DEPLOYABLE
- **Missing dependencies**:
  - `storage_deletion_jobs` (table — does not exist in production)
  - `file_assets` (table — does not exist in production)
  - `file_access_events` (table — does not exist in production)

### file-scanner
- **Source status**: MISSING_DEPENDENCIES_NON_DEPLOYABLE
- **Missing dependencies**:
  - `file_assets` (table — does not exist in production)
  - `file_access_events` (table — does not exist in production)
  - `v_files_pending_scan` (view — does not exist in production)

## Resolution Path

1. For **file-security functions** (file-url-mint, storage-deletion-worker, file-scanner):
   Apply the proposed schema from `PROPOSED_FILE_SECURITY_SCHEMA.sql`, then move to deployable.

2. For **turnstile-verify**: Create the two missing RPCs, then move to deployable.

3. For **email-webhook** and **send-push-notification**: Create the communication/push
   schema, restore full source from conversation history, then move to deployable.

4. For **aicrm-ai-enrichment-runner**: Write the full ~1100-line source from conversation
   history, add `packages/elev8-ai-service/index.ts`, then move to deployable.

US East CRM enrichment checkpoint (2026-10-06): `aicrm-ai-enrichment-runner` now has a deployable native tenant-admin preflight. The historical full runner remains unsuitable for direct deployment: provider errors and invalid output can silently become mock facts, prompts can cross tenant scope, and result writes are not atomic. Run/retry stays blocked; the historical placeholder is superseded.

US East email-webhook checkpoint (2026-10-06): deployable `email-webhook` now verifies bounded raw-body Svix signatures with a fresh destination-only `RESEND_US_WEBHOOK_SECRET`. Every recognized signed event remains retryably blocked with HTTP 503, without acknowledgement, database writes, global contact matching or message/thread fallback. The historical full source remains non-deployable pending reviewed provider-account/tenant routing and atomic replay-safe finalization.

US East file governance checkpoint (2026-10-06): file-scanner and file-url-mint now deploy native tenant-admin readiness only. Source and destination both lack file_assets/file_access_events/signed_url_nonces/v_files_pending_scan and nonce functions. Scanning, clean classifications, legacy nonce adoption and Storage URL issuance remain blocked; the historical implementations are not deployable as live workflows.

MDF billing source is superseded by native tenant-admin readiness in `mdf-billing`. Checkout, billing portal and unsigned subscription-webhook writes remain blocked pending explicit MDF/core identity mapping and verified provider contracts.

MDF email source is superseded by native tenant-admin readiness in `mdf-send-email`. Arbitrary recipient/body submissions, global queue processing and global expiry writes remain blocked pending verified tenant ownership, delivery controls and worker authority.

Performance recording review is superseded by native scoped metadata preflight in `performance-recording-review`. Consent and transcript organization/recording/status links are enforced. No transcript text, provider request, score or review write is enabled.

PIM batch enrichment source is superseded by native tenant-admin readiness in `pim-batch-enrich`. Cross-tenant selection, unverified manufacturer scraping and offer-price-as-MSRP writes remain blocked pending evidence, region/currency/model validation and atomic scoped publishing controls.

Product detail enrichment is superseded by native tenant-admin readiness in `product-detail-enrich`, with JWT verification enabled. Caller URLs, global candidate selection, partial extraction, unchecked multi-table writes and existing-spec overwrites remain blocked pending scoped evidence validation and atomic updates.

Product IQ governance is superseded by native tenant-admin readiness in `product-iq-governance`. Search, edits, validation and related-record writes remain blocked pending destination authority verification, missing tenant-owned schema and atomic audited version checks.

Product video discovery is superseded by native tenant-admin readiness in `product-video-discovery`. Legacy run-key authority, global job claims, unverified source/embed URLs and non-atomic completion are not enabled.

RetailVantage performance bridge is superseded by native scoped connection readiness. Request financial payloads, fallback transaction IDs/dates, unreviewed mappings, cost double counting and partial multi-table writes remain blocked.

RetailVantage sync is superseded by scoped native tenant-admin readiness in `retailvantage-sync`. Credential adoption, arbitrary authenticated endpoint requests, unbounded pagination URLs, 100-page truncation and premature completion markers remain blocked pending verified resumable provider controls.
