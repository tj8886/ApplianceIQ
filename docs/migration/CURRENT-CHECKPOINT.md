# Current migration checkpoint — October 9, 2026

Status: in progress; production remains in Canada. Do not interpret endpoint deployment as workflow completion.

Completed this batch:
- Shopify OAuth implementation deployed and tested; live provider verification requires fresh Shopify registration/secrets.
- All 542 source tables compared: 532 initially identical, ten reviewed differences.
- Copied 45,753 append rows with exact source checksums and unchanged original prefixes. Temporary relay endpoints closed and service RPC execution revoked.
- Copied 156 smaller missing records and updated 114 stale records; retained private before images, all destination-only rows and existing decision-case trigger behavior.
- Dashboard, floor adapter and reviewed read/privacy regression tests passed with fixtures rolled back. Advisor WARN/ERROR counts unchanged from baseline; two deliberately private journal tables add RLS-without-policy informational notices.
- All 11 generated app bundles passed local routing/asset/auth-storage/handoff checks earlier in this session; hosted authenticated checks and cutover remain pending.

Remaining work:
- Eleven archived Edge endpoints are absent; several deployed endpoints still provide readiness gates rather than complete workflows.
- Provider credentials/registrations and real integration tests, remaining application writes and browser workflows.
- Final frozen database/Storage delta, destination schedules, hosted cutover and source retirement. Main CI still targets Canada; migration PR must remain unmerged until cutover readiness is established.

Next small batch: review and implement one remaining endpoint, starting with turnstile-verify. Read its archived source and destination runtime configuration; test locally, commit before deploying, verify live behavior, and checkpoint. Avoid another broad batch until this endpoint is complete or its exact external blocker is recorded.

Evidence: oct9-append-delta-verification.json, oct9-reviewed-delta-verification.json. Work branch: migration/us-east-consolidation; draft PR #8.
