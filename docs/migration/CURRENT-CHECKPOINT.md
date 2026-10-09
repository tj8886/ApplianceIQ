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
- Nine archived Edge endpoints are absent; several deployed endpoints still provide readiness gates rather than complete workflows.
- Provider credentials/registrations and real integration tests, remaining application writes and browser workflows.
- Final frozen database/Storage delta, destination schedules, hosted cutover and source retirement. Main CI still targets Canada; migration PR must remain unmerged until cutover readiness is established.

Next small batch: continue shopify-draft-order with the duplicate-prevention and uncertain-result recovery contract. The deployed preview is complete; provider draft creation is not. Finish the actual creation workflow before treating the endpoint as fully migrated. A later provider verification requires new Shopify authorization including draft-order permission.

Draft preview batch: ACTIVE v1, JWT required. Native tenant-admin preview uses stored negotiated/promo/MSRP and actual service amounts, decimal strings and an exact subtotal. Missing prices, caller-supplied financial data and foreign/unmapped/nonadmin access are rejected. Handler/live rollback database tests passed; unsigned live probe is 401; advisor counts unchanged. No provider call or business write. Evidence: shopify-draft-preview-verification.json.

Turnstile batch: deployed ACTIVE v1 with strict public challenge verification and distributed private budgets. Handler and live rollback database tests passed; unsigned live probe correctly returns verification_not_configured with no provider call. Fresh namespaced Turnstile secret and site/action configuration, followed by a real widget test, are required for activation. Evidence: turnstile-verification.json. Inventory is 77 archived endpoints deployed, one retired and nine absent; deployed presence includes gates and incomplete provider verification.

Evidence: oct9-append-delta-verification.json, oct9-reviewed-delta-verification.json. Work branch: migration/us-east-consolidation; draft PR #8.
