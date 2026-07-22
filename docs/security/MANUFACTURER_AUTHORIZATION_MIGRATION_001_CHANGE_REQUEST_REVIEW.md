# Manufacturer Authorization Migration 001 Change Request

## Executive summary

Document baseline: `a3faff3716da8cc7913d5d7d9d9273ce347180df`.

Migration 001 is a staging-only, additive schema foundation for future manufacturer-membership and invitation hardening. It adds nullable lifecycle and provenance fields plus four lookup indexes. It changes neither data nor authorization behavior. The staging change is **READY WITH CONDITIONS**: the one existing global-role record requires a manual platform review before execution.

## Verified current state

SELECT-only verification against `fumwwhyozeouoqscolke` confirmed 0 `mfr_members`, 0 `mfr_invites`, 1 `mfr_user_roles`, and 19 `mfr_vendors` rows. There are no duplicate or orphan memberships or inviter references. All four tables have RLS enabled; Migration 001 leaves every policy unchanged.

`mfr_members` currently has a composite `(user_id, vendor_id)` primary key and a legacy nullable `member_role`. `mfr_invites` currently uses `email`, vendor text fields, `invite_role`, a unique raw legacy `code`, a nullable `status`, and `accepted_at`. These legacy fields remain intact and authoritative behavior does not change in this migration.

### Invitation vendor-binding reconciliation

Live schema inspection found no `vendor_id`, `manufacturer_id`, `organization_id`, `company_id`, `invited_vendor_id`, or equivalent authoritative vendor-binding column. `vendor_slug` and `vendor_name` are nullable display/legacy text, not foreign keys. The approved P1/P2 specification already lists `vendor_id` as the target controller and the data-repair worksheet already includes it. The correct classification is **APPROVED_OMISSION_CORRECTION**: the original validation count omitted an already-approved target field. The authoritative decision count is therefore 15: `vendor_id` plus 14 other invitation-field decisions. Of those, 13 are Migration 001 additions and `status` plus `accepted_at` already exist; none are deferred as fields. This is not a new scope decision.

## Approved boundary

Included: nullable lifecycle/provenance fields, safe empty-object metadata defaults, token version default `1`, and four non-unique lookup indexes.

Deferred: all role and status constraints, every new foreign key, legacy-field retirement, data repair, token issuance/acceptance, helpers, RLS, browser write removal, portal, Storage, vendor, and brand ownership work. No default creates an active member or grants a role.

## Exact proposed changes

`mfr_members` gains the 14 approved target fields: `role`, `status`, `invited_by`, `approved_by`, `invitation_id`, `approved_at`, `activated_at`, `suspended_at`, `revoked_at`, `expires_at`, `updated_at`, `created_by`, `updated_by`, and `metadata`. All are nullable with no default except `metadata`, which receives a non-authoritative empty JSON object default. The legacy `member_role` remains untouched.

`mfr_invites` gains an authoritative nullable `vendor_id` supporting field and 12 of the 14 requested target fields. `status` and `accepted_at` already exist and are unchanged. The additions are `invited_user_id`, `intended_role`, `intended_status`, `approved_by`, `token_hash`, `token_version`, `expires_at`, `accepted_by`, `revoked_at`, `revoked_by`, `superseded_by`, and `metadata`. No raw reusable invitation token is proposed; `token_hash` is only a future one-way verifier and remains unused in Migration 001.

## Index and FK decisions

Migration 001 adds four non-unique btree lookup indexes: membership by invitation, membership by vendor/status, invitation by vendor, and invitation by invited user. The existing composite membership primary key already serves user and user/vendor lookup.

All new foreign keys are intentionally deferred. The new nullable columns document the target relationship, but binding them to users, vendors, or invitations belongs with later authoritative lifecycle and invitation enforcement. Planned delete behavior is `SET NULL` for provenance, `RESTRICT` for invitation vendor ownership, and `SET NULL` for invitation resend lineage.

## Lock, transaction, and snapshot plan

Run one atomic staging schema transaction for columns, safe defaults, and the four indexes. With zero membership and invitation rows, the expected duration is under five minutes, subject to a five-second lock timeout and 30-second statement timeout. Keep concurrent/partial/unique indexes for later phases.

Before execution, capture a restricted schema, row-count, constraints/indexes, RLS/policies, migration-history, and global-role-review snapshot. Observe database and API errors for 30 minutes after checks complete.

## Global-role review

The sole `mfr_user_roles` record is a hard staging blocker. A platform owner must verify identity, business purpose, account ownership, active status, and least privilege, then record one outcome: retain, downgrade, remove, or blocked pending identity/business justification. Migration 001 does not change that record.

## Rollback and validation

Before later features write lifecycle data, reverse schema rollback is possible only with approved snapshots and verification. Once a later release writes audit or lifecycle data, destructive rollback is prohibited; disable the dependent release and forward-fix instead.

Acceptance requires unchanged row counts and legacy data; unchanged RLS, policies, helpers, portal/browser, and Storage behavior; matching fields/defaults/indexes; no active default; and a clean 30-minute staging observation.

## Blocking conditions and readiness

Block execution for baseline or environment mismatch, dirty tree, unresolved global-role review, unexpected rows or integrity failures, schema drift, migration conflict, unapproved field/default/index, absent snapshot or rollback approval, inability to prove RLS unchanged, or inability to restore staging.

**Readiness: READY WITH CONDITIONS.** The next task is human approval of this change request, followed by preparation and peer review of the actual staging Migration 001 implementation package. No implementation is authorized by this document.
