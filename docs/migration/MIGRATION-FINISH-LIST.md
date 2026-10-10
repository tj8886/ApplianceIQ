Production app cutover completed on October 10, 2026 under the user's authorization to publish now. All 11 registered production sites serve the US bundle, and PR #8 is merged. Canadian data/files are retained. Remaining items below are follow-up work. See production-cutover.json for actual live deployment evidence.

# ApplianceIQ migration finish list — October 10, 2026 UTC

**Production applications now target US; migration follow-ups remain.** Ready Netlify deploys and live routing are verified for all eleven apps. Signed-in workflow and final reconciliation completion are not claimed.

| Work | Verified state | Completion requirement |
| --- | --- | --- |
| Database transfer | Last full comparison: 542 source tables; 45,909 inserted rows and 114 reviewed updates | Freeze writes only after readiness; compare and reconcile the final delta with retained before images |
| Storage transfer | Earlier source file copy/checksums passed; destination-only objects retained | Actual native uploads/downloads, URL access and final frozen file delta |
| US applications | Eleven bundles published and live US routing verified; 71 native literal RPC references resolve | Hosted native login, approved identity/org roles, invitation and ticket handoff tests across all apps |
| Spec IQ writes | Atomic drafts/revisions, manager content review, archive, CRM links, standalone projects, settings, private logo storage and project/product metadata implemented and rollback-tested | Actual native logo file-byte test; final pricing/tax/discount/expiry enforcement; PDF/share/send and hosted workflows |
| Other application writes | Read/reference checks do not establish complete write workflows | Brand training contracts implemented and rollback-tested; finish other active application writes and hosted role/scope verification |
| Archived Edge functions | Fresh metadata: 91 source and 109 destination functions; 78/87 archived endpoints deployed, one retired, eight absent; no source snapshot metadata drift | Resolve missing coverage and complete restricted implementations; verify transitive dependencies |
| Provider integrations | 33 deployed endpoints recorded as restricted/preview-only; fresh Shopify credentials and verification proofs are zero | Fresh provider registrations/secrets/authorization, webhook authenticity, real integration tests and retry/reconciliation behavior |
| Cutover operations | App publication complete; Netlify Git builds target US; GitHub Actions workflow remains manually disabled; destination schedules and source retirement pending | Review GitHub Actions activation, enable schedules after dependencies pass, monitor US apps and retain rollback path before source retirement |

## Ordered completion work

1. Perform actual native authenticated file-byte tests for logo and manufacturer assets. Logo reservation/upload/finalize/read authorization and client workflow are implemented and rollback-tested; earlier files retained.
2. Finish active application writes, final Spec IQ quote/expiry/financial/send workflows and any remaining training writes. Preserve history and avoid inventing product facts or financial values.
3. Implement missing Edge coverage and turn restricted endpoints into verified working flows. Missing archived endpoints: `shopify-webhooks`, `storage-deletion-worker`, `storis-performance-bridge`, `stripe-webhook`, `stripe-webhooks`, `transaction-performance-bridge`, `windward-performance-bridge`, `windward-sync`. Review deletion-worker behavior against retained-file requirements before any activation.
4. Configure fresh provider authorization and verify provider accounts, scopes, currency, pricing, webhooks and idempotency. No secret values belong in this repository. Shopify fresh credentials/proofs/sessions were confirmed zero in this batch. The previously paused Shopify scope migration remains unapplied; do not bulk-apply it accidentally.
5. Run hosted authenticated browser tests across all eleven applications, including file uploads/downloads and cross-organization denial. Local VM mocks and rollback SQL are supporting tests, not substitutes.
6. Complete final source write coordination and database/Storage reconciliation, review GitHub Actions activation and destination schedules, smoke-test signed-in production workflows and monitor. Hosted apps have already switched to US. Retire the source only after rollback/verification requirements are met.

## Latest batch evidence

`speciq-technical-verification.json`: applied native product technical/asset snapshots, canonical catalog facts and asset eligibility, manual entry provenance, strict types/dimensions/HTTPS metadata, revision inheritance/explicit clearing and retained history. Full client/module tests, eleven bundle checks and live rollback/authenticated tests passed; fixtures zero and advisor counts unchanged. No provider request, file-byte transfer, publication or production switch occurred.

`live-edge-progress.json` is the fresh endpoint-presence audit. Its deployed count does not prove functional completion. The 33 restricted classifications remain based on recorded implementation descriptions.

Private logo batch: 2026-10-10T13:19:09.338Z. See speciq-logos-verification.json. Native authorization/metadata rollback tests, client tests, whole module parse, all eleven bundles and 74 configured routes passed. All 70 literal native wrapper names available. Actual Storage file bytes and hosted workflows remain pending; production remains Canada.

File-transfer verification: six live unauthenticated checks passed; no probe objects persisted. Signed-in file bytes remain pending because an approved US test login is unavailable in this environment. Repeatable US/test-org runner and operating instructions are saved in NATIVE-FILE-VERIFICATION.md; mocked runner tests are not live byte proof. Continue independent remaining application implementation while this prerequisite is unresolved.

Manufacturer training is implemented and rollback-tested: organization-scoped native drafts, stored vendor/brand link, approved editor/reviewer roles, independent publication review, edits invalidate prior approval and history retained. Client/module, all eleven bundles and 75 configured routes passed; 35 existing cards retained. Evidence: brand-training-verification.json. Remaining financial/send and other application workflows can continue independently of the missing test login.
