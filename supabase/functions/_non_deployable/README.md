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
