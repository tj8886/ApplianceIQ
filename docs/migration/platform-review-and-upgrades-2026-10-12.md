# ApplianceIQ Platform review — October 12, 2026

The live platform root and workspace both connect to the US Supabase project
`jdxslqmgjsuzoisuhvlc`. Netlify publication remains paused. Frontend changes below
are committed source and tested deployment bundles, not newly published pages.

## Completed fixes

| Area | Finding and correction | Status |
| --- | --- | --- |
| Signup | A user object without a confirmed session previously entered the dashboard. Now prompts for email confirmation and company activation/invitation. | Prepared frontend |
| Company context | Root dashboard had no company/location selector and loaded the first subscription/credit record. Added selectors, role display, selected-company queries and context-aware launches. | Prepared frontend |
| App access | Failed or empty entitlement responses fell back to all trial apps; hyphenated module keys bypassed the old mapping. Added explicit mappings, company-scoped entitlements and denial on missing/failed entitlement data. | Prepared frontend |
| Billing display | There are zero platform subscription and credit allocations in US. Missing records previously claimed a trial, one seat and 5,000 credits. Now displays unconfigured values. | Prepared frontend |
| Pricing | Checkout and credit purchases were alerts, annual discounts were advertised as a fixed 20%, and cents were rounded away. Prices are shown to cents; checkout is labelled unavailable and annual pricing uses the actual catalog. | Prepared frontend |
| Company administration | Added a Company & Team Setup launcher for company owners/admins pointing to the existing admin portal. This is navigation, not completion of its underlying workflows. | Prepared frontend |
| Session lifecycle | Clear company state on logout; close pending launches on errors; ignore late root loads after logout. | Prepared frontend |
| Workspace | Removed filtering notifications by new Auth UUID against source-user records. RLS resolves the migrated identity. Filter displayed notifications by selected company. Reload app access on company changes. | Prepared frontend |
| HTML output | Escape catalogue, company, notification and search content; validate launch protocols and credentials in URLs. | Prepared frontend |
| Browser launches | Open a blank tab during the click, then navigate using a one-time ticket; report blocked popups, close on failure, and remove opener access. Same-origin platform pages open directly. | Prepared frontend |
| App registry | Corrected Command Center URL and aligned existing module manifests with canonical deployment keys. US handoff issue/redemption now recognize existing module keys and registry aliases while retaining company/location validation. | Applied to US |
| Mobile | Company/location controls wrap within the root top bar. | Prepared frontend |

## Priority upgrades still needed

1. **Complete US company administration.** The existing admin page writes directly
   to organizations, memberships, roles, locations, location assignments and app
   entitlements. Authenticated users have no INSERT/UPDATE/DELETE grants for these
   tables in US, so those controls cannot presently complete their actions. Build
   membership-checked RPCs, migrate its source-user filters, and connect its legacy
   login storage to the shared handoff session. Do not solve this by broadly
   granting table writes.
2. **Guided onboarding.** Provide company profile → locations → hierarchy/managers
   → invitations → app selection → readiness checklist, using the secure admin
   operations above. Account signup alone does not provision a mapped company
   identity or start a trial. Preserve the verified invitation/migration process.
3. **Authoritative app access.** Current server handoff checks verified identity,
   active module, company membership and location, but does not enforce paid app
   entitlements. Frontend denial improves navigation; it is not a server billing
   gate. Define the approved plan/entitlement rules, including trial expiry,
   Field Report and IQ Build, then enforce issue and redemption server-side.
4. **Billing.** Connect real checkout/customer portal/webhooks and synchronize
   company billing with platform subscriptions, seats and credits. Existing
   admin billing is preview-only. Confirm currency, taxes, renewal and trial
   rules before exposing a purchasing flow. No charge was initiated in this pass.
5. **Unify headquarters.** Root dashboard, workspace and admin currently have
   separate navigation and auth behavior. Bring company setup and the existing
   role hierarchy into a consistent headquarters experience; add an onboarding
   status summary rather than implying setup is complete.
6. **Browser acceptance tests after publication.** Test a confirmed owner, a
   regular member, multiple companies, a new invite and mobile app launch. This
   pass used behavioral JavaScript and rollback SQL tests; it did not create a
   real user/company, send invitation emails, or exercise a production checkout.

## Verification

- Behavioral root tests: signup confirmation, denied entitlements, company query
  filters, missing billing, HTML escaping, ticket-only launch and logout.
- Behavioral workspace tests: company entitlements, migrated notifications,
  escaped content, denied apps and permitted ticket launches.
- Handoff HTTP handler test passed.
- All 14 US bundles passed endpoint routing, local asset and ticket checks.
- Live rollback SQL suites passed: platform runtime, login handoff, registry aliases.
- Security and performance advisor counts unchanged from the previous audit;
  no new advisory category or count was introduced. Existing findings remain
  tracked in the prior migration audit.
- Live HTML still has the old trial/credit fallbacks and workspace notification
  UUID filter. Prepared frontend corrections require the next Netlify publication.
- Icecat remains paused; Canada data and files remain available.
