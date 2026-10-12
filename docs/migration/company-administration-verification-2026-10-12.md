# Company administration verification — October 12, 2026

The company-administration backend is applied in the US Supabase project
`jdxslqmgjsuzoisuhvlc`. The admin portal, platform navigation and onboarding
checklist are prepared in source and tested bundles. Netlify publishing remains
paused, so the live website still needs this frontend update.

## Completed

- One checked `company_admin` API provides administrator bootstrap, company
  snapshots, company creation/details, roles, locations, membership changes,
  reporting lines, atomic store assignments and app entitlement changes.
- Bootstrap resolves the migrated source identity server-side. Company admins
  see their administered companies; platform administrators see all active
  companies. Member profiles and invitations are read only inside an authorized
  company snapshot.
- Only platform administrators create companies or change app entitlements.
  Company creation adds the caller as its first owner. Owners and company admins
  manage the existing company structure through checked operations.
- Ownership changes cannot remove the last active owner/administrator. Company
  admins cannot grant owner access. Role assignments must belong to the same
  company and match the member's system role.
- Reporting lines and location parents reject cycles and foreign-company IDs.
- Store selections are replaced in one transaction. Primary stores must be
  selected. Archived locations revoke active assignments; active child locations
  must be moved or archived first. Assigned roles cannot be archived.
- Removed members use the valid `removed` status and lose active location
  assignments. Existing company, role and location records are retained.
- App assignment requires an explicit recorded monthly amount, including an
  explicit zero for approved free access. Seats cannot fall below recorded usage.
  These changes do not initiate Stripe checkout, payments or subscription updates.
- Every successful structural change records its before/after state in a private
  audit table with organization and actor IDs. Client and service table grants
  remain closed; no broad table-write permission was added.
- Admin navigation waits for shared ticket redemption. Direct password login can
  adopt the shared session; token refresh and sign-out update the admin session.
  Old Auth UUID filters were replaced by the checked bootstrap/snapshot API.
- Admin UI now has company details, reporting-line selection and a practical
  readiness checklist for locations, hierarchy, members and app access.
- Unverified platform-administrator provisioning/removal controls are disabled.
  Company-admin controls cannot self-grant paid access or platform access.

## Validation

- Rollback SQL passed before and after applying the migration: successful scoped
  company/role/location/member changes; last-owner protection; manager/location
  cycles; assigned-role protection; foreign-company read/write rejection;
  ordinary-member denial; unmapped identity denial; paid-access escalation
  rejection; atomic store replacement; archival; private audit and grant checks.
- Native invitation and platform runtime rollback regression suites passed.
- Admin behavioral JavaScript tests passed for mapped identities, scoped mutation
  routing, blocked platform-admin writes, role provisioning, shared-session
  adoption and atomic store assignment.
- Root platform and workspace behavioral tests passed.
- All 14 prepared US app bundles passed routing, source-endpoint removal, local
  assets, auth preservation and one-time ticket checks.
- Security advisors: the only count increase is one private RLS-enabled audit
  table with no policies, intentionally inaccessible to client/service roles.
  Other security counts and all performance counts are unchanged.
  [Supabase RLS reference](https://supabase.com/docs/guides/database/postgres/row-level-security)

## Remaining

1. Publish the prepared frontend when Netlify is available, then perform real
   owner/member/mobile acceptance tests. No real company, member or invitation
   was created by the verification suites; all fixture changes rolled back.
2. Extend the checklist into a guided onboarding flow and align the broader app
   registry/plan entitlement rules, especially IQ Build and Field Report.
3. Enforce approved paid/trial entitlement rules in server handoff issuance and
   redemption. Current tenant isolation is tested; frontend app gating is not
   a replacement for authoritative billing enforcement.
4. Configure verified invitation email delivery and Stripe checkout/portal/
   webhooks. Existing invitation links remain the supported path; email delivery
   and payment execution are not claimed complete.
5. Review platform-administrator provisioning separately before enabling those
   controls. This pass did not create administrators or grant platform access.

Icecat remains paused. Canadian recovery data/files and Netlify deployment
settings were not changed.
