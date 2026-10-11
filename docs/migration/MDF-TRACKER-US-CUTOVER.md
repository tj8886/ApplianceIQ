# VendorXQ MDF / Co-op tracker US cutover

The maintained source is now `apps/mdf-coop/index.html`, recovered from the published VendorXQ artifact at `https://applianceiq-mdf-coop-vr.netlify.app/`. The related vendor-funding site is a separate marketing page. The tracker is registered as `mdf-coop`; the US batch builder supplies the same reviewed runtime, local adapter and password recovery page as the other US apps.

The legacy tracker connected to Canada and swallowed failed REST writes. The restored US build uses native Supabase Auth and `tj_runtime_mdf_tracker`. This bounded gateway checks an explicit source-identity binding, active core organization membership and active/non-deleted organization on every operation. Browser-stored profiles and JWT email claims do not authorize access. Direct MDF table grants remain revoked with RLS enabled. The SECURITY DEFINER implementation is private, fixes an empty search path, checks the caller before every branch, rejects arbitrary table/filter/order names, and is exposed only through an authenticated SECURITY INVOKER wrapper.

## Reviewed identity and tenant binding

TJ authorized migrating the tracker on October 11, 2026. The sole active MDF administrator record `6f1cc7fc-229b-4610-9ad1-d3def7381db3` belongs to the legacy Tackline Strategies workspace `0f500184-8ed1-49a3-ba22-b8a17e0c11dc`. The confirmed, previously approved and activated source/native identity is `ce2145b0-0283-45da-af4c-3a88f84cecae`. This is a reviewed one-time cutover binding, corroborated by the legacy administrator/organization owner records and the existing identity migration. It is not a general email-to-user mapping procedure.

Tackline Strategies is preserved as a distinct core tenant; its records are not mixed into the existing Appliance IQ or Demo Retail Store organizations. Original MDF organization/user IDs are retained. The previous unpartitioned single-tenant tracker dataset receives this explicit organization scope. New source-actor and tenant columns are additive. All existing original columns, financial amounts, source evidence and dates have matching normalized row fingerprints before and after the migration. The two old email queue receipts lack proven ownership and remain intact, unassigned and inaccessible to the gateway.

New memberships and MDF bindings must be reviewed explicitly; adding an email address in the browser no longer grants access. This initial gateway deliberately accepts only one active bound MDF workspace per actor and fails on ambiguous bindings.

## Functional corrections

- Database failures reject the save; save/import handlers clear their busy state and show the failure.
- New sales and their co-op accrual are committed atomically from recorded contract terms. The destination had no accrual trigger; the old function also used a reference type rejected by the ledger constraint. The gateway uses the supported `sales` reference and prevents clients from modifying automatic accrual entries.
- New contracts archive the preceding active contract and save the replacement in one transaction.
- Rebate records are calculated on the server from recorded sales, an enabled contract covering the requested period, and its stored tier schedule. Client-supplied rebate totals do not determine the saved amount. A calculated record is not provider verification.
- Co-op submissions record the authenticated actor. Manager and marketing approvals require the correct role/stage; finalized requests cannot be silently rewritten. Tenant ownership is checked on brand, contract and request references.
- CSV imports are bounded to 200 rows and report each row's actual success/failure. This is a partial-success import, not an atomic batch.
- Sales, ledger and other report reads paginate rather than silently calculating balances from the old 500-row truncation. The bounded export ceiling is enforced with an error.
- Recorded zero amounts are preserved, including zero net sales and exhausted MDF balances. PDFs include recorded sales, rebates, co-op balance and MDF fund details.
- Source deletions are unavailable. Existing sales and recorded calculations are immutable through the gateway; reviewed corrections/adjustments are needed instead.
- Billing UI labels imported subscription information as recorded evidence. Checkout, billing portal, notifications and automatic expiry execution are not enabled; no provider request or message was sent.

## Verification and publication

The migration file `20261011134645_mdf_us_tracker_access.sql` is applied in US migration history as version `20261011140026`. Before and after applying it, transaction/rollback tests passed for ID-bound context, spoofed JWT email, tenant isolation, protected fields, native role changes, revoked membership, brand scope, generated net sales, atomic co-op accrual, zero sales, server rebate totals, request stages/finalization, audit actor, blocked deletion and blocked arbitrary-email account grants. No test organizations or business records remain.

UI helper/PDF content checks and all 13 US bundle checks pass. The final generated tracker JSX compiles with the same pinned Babel 7.23.9 compiler used by the app. The PDF test checks generated content using a test document adapter; a signed-in visual browser/PDF walkthrough has not been performed.

Security advisor WARN/ERROR categories did not increase. Unindexed foreign keys remain 699. Unused-index INFO findings rose from 942 to 953 for new tenant/actor indexes; these are retained to support access scope and future load, rather than discarded merely because they are new. RLS-without-policy INFO findings are unchanged because the gateway-only MDF tables intentionally remain inaccessible directly.

Publication is recorded separately in `mdf-tracker-us-verification.json`. Do not treat source commit, build tests, or CI dispatch as live publication. Until a new published artifact is observed, the last confirmed live tracker remains the Canadian August 17 deployment `6a824f2bb3a83927ecfe7ffc`.

Password recovery uses the existing isolated recovery controller and same-origin `/password-reset.html` callback. Email delivery and hosted Auth redirect configuration still need independent verification. No password, account credential or source data was changed.
