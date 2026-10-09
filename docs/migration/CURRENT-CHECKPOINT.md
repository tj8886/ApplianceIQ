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

Next small batch: implement read-only Shopify connection verification and the explicit draft-order scope authorization path. Confirm the actual shop identity, currency and granted permissions against fresh credentials. Do not enable draft creation yet; real response validation/reconciliation and currency/tax/discount handling remain unfinished.

Draft claim batch: applied service-only internal attempt/event journals with one package slot, idempotent request keys, worker fencing, SHA-256 source snapshot guards, expiry/cancel before dispatch, uncertain-state retention and idempotent simulated confirmation. Live rollback lifecycle and preview regression tests passed; persisted attempts/events are zero. No provider call, credential access or package success marker write. Existing advisor WARN/ERROR counts unchanged; two deliberately private RLS-without-policy and three unused-index informational findings documented. The Edge endpoint is still preview-only; the journal is not wired to provider execution. Evidence: shopify-draft-claim-verification.json.

Draft preview batch: ACTIVE v1, JWT required. Native tenant-admin preview uses stored negotiated/promo/MSRP and actual service amounts, decimal strings and an exact subtotal. Missing prices, caller-supplied financial data and foreign/unmapped/nonadmin access are rejected. Handler/live rollback database tests passed; unsigned live probe is 401; advisor counts unchanged. No provider call or business write. Evidence: shopify-draft-preview-verification.json.

Turnstile batch: deployed ACTIVE v1 with strict public challenge verification and distributed private budgets. Handler and live rollback database tests passed; unsigned live probe correctly returns verification_not_configured with no provider call. Fresh namespaced Turnstile secret and site/action configuration, followed by a real widget test, are required for activation. Evidence: turnstile-verification.json. Inventory is 77 archived endpoints deployed, one retired and nine absent; deployed presence includes gates and incomplete provider verification.

Evidence: oct9-append-delta-verification.json, oct9-reviewed-delta-verification.json. Work branch: migration/us-east-consolidation; draft PR #8.
