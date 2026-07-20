# Final security report — 2026-07-19

## Defects found and fixed
1. **match_products cross-tenant vector query (HIGH, FIXED).** SECURITY DEFINER, accepted arbitrary `p_organization_id`, no caller-membership check — any authenticated user could run similarity search against another org's products. Fixed in migration `20260719232101_closeout_security_fixes` (guard: service_role OR is_org_member). Verified via advisors + function definition re-read.

## Reviewed and intentional
- **19 RLS-enabled tables with no policies** (academy_* backend, app_bundles, consent_ledger, dsr_*, memory_*, foundation audit/disputes/fact_reviews, embedding_worker_runs, privacy_purge_log): deny-by-default; service-role only by design. INFO-level.
- **SECURITY DEFINER RPCs callable by authenticated**: is_admin, is_org_member, is_org_admin (RLS helpers — must be definer), ai_submit_request (verifies membership internally — confirmed), join_demo_org (intentional demo onboarding), manages_vendor (self-scoped helper), match_products (now guarded).
- **verify_jwt=true** on all 4 edge functions; embedding-worker additionally requires service-role token in-body.
- **No secrets in repo**: scanned migrations and source; only the public publishable key ships to frontends.
- **Storage**: crm-media private, org-UUID path-scoped policies, 50 MB bucket cap, 25 MB app cap.

## Accepted risks / deferred
- **vector extension in public schema** (WARN): moving it requires retyping embedding columns; deferred — no privilege escalation path identified at current usage.
- **Leaked-password protection disabled** (WARN): dashboard-only toggle; BLOCKED_EXTERNAL — enable in Supabase Auth settings.
