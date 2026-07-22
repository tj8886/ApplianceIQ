# Manufacturer Authorization Audit V1

## Executive summary

Manufacturer authorization is not safe to activate for portfolio ownership yet. The database and browser currently permit self-escalation to global administrator, self-membership in arbitrary vendors, role-blind vendor management, and unscoped vendor-asset uploads. These are confirmed, exploitable authorization defects—not UI-only concerns.

## Current architecture and confirmed vulnerabilities

`mfr_members` is a `(user_id, vendor_id)` membership table with nullable free-text `member_role` and no status, approval, invite reference, brand scope, regional scope, or audit fields. `manages_vendor()` is SECURITY DEFINER with an explicit public search path, but returns true for any membership and ignores role/status/scope. `mfr_user_roles` contains global boolean flags, and its own-row ALL policy plus browser upserts permits self-escalation.

| Severity | Finding |
| --- | --- |
| Critical | MFR-AUTH-001 — Self-assignable global portal privileges. |
| Critical | MFR-AUTH-002 — Arbitrary vendor self-membership. |
| High | MFR-AUTH-003 — Role-, status-, brand-, and region-blind vendor management. |
| High | MFR-AUTH-004 — Public and unscoped manufacturer Storage authorization. |
| High | MFR-AUTH-005 — Non-authoritative manufacturer invitation acceptance. |
| High | MFR-AUTH-006 — Training-card writes are not manufacturer-owned. |
| Medium | MFR-AUTH-007 — Product and document writes lack manufacturer/brand scope. |

## Target model and role matrix

Use active, approved, role-controlled vendor memberships with optional brand, country, capability, delegation, and expiry scopes. Keep multi-vendor membership, but assign a role per vendor and never grant a portfolio implicitly. Proposed roles are vendor owner, vendor admin, brand admin, content/product/asset/training editor, and viewer. Owners/admins manage memberships only within their approved scope; editors draft content only; viewers never write; nobody can grant platform administration.

## Brand, region, and portfolio delegation

Controlling vendors may receive a portfolio grant only after a human-approved ownership assignment. A brand delegate receives explicit brands and countries only, not sibling brands. This is essential for BSH, Whirlpool, GE Appliances, Electrolux, Sub-Zero Group, Middleby, Beko/Arçelik, and Fisher & Paykel. Hotpoint is GE Appliances-controlled only in the Americas; European authority must remain blocked. Insignia requires a private-label-owner policy; never infer OEM authority.

## RLS, storage, and portal recommendations

Replace browser mutation of roles, membership, and invite acceptance with narrowly scoped, audited server/RPC operations. RLS must call active role-aware vendor/brand/region helpers and use both `USING` and `WITH CHECK`. Keep service-role credentials server-only. Make `vendor-assets` private; enforce `vendor_id/asset_id/filename` paths, database-object binding, signed reads, scanner/quarantine state, and server-side retryable deletion.

Storage has one confirmed authorization finding, MFR-AUTH-004: the public bucket, bucket-only insert policy, and owner-only update/delete policies are a combined broken authorization boundary. Missing object-key binding and path convention are defense-in-depth gaps. `file-url-mint`, `file-scanner`, and `storage-deletion-worker` are incomplete or unverified components; they are not credited as active protections and are not separately counted as proven exploitable vulnerabilities.

## Safe sequencing, rollback, and tests

First introduce controlled roles/status and secure invitations; then replace helpers, harden RLS, add scopes, and secure storage. Only after staging tests and rollback confirmation may approved controlling entities be created and `brand_catalog.manufacturer_id` become authorization-active. Test anonymous, unaffiliated, viewer, editor, admin, platform admin, cross-vendor, cross-brand, cross-region, expired/reused/wrong-account invite, upload/delete, and signed URL cases. Rollback must preserve memberships and disable new grants rather than delete history.

## Exact next task

Prepare a human-reviewed, staging-only Priority 2 implementation plan for controlled membership status/roles, invitation acceptance, and role-aware helper replacement; do not create vendor entities or backfill brand ownership until its authorization matrix passes.
