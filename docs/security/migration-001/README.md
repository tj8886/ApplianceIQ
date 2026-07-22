# Manufacturer Authorization Migration 001

Status: **staging implementation package only**. Baseline: `59f903533c67bd5c0e8fa7a943bd5f314f4c8109`.

This package implements only the additive foundation approved in the Migration 001 Change Request. It affects `public.mfr_members` and `public.mfr_invites`; it adds 14 membership columns, 13 invitation columns, and four non-unique indexes. Existing `mfr_invites.status` and `accepted_at` are preserved.

Membership additions: `role`, `status`, `invited_by`, `approved_by`, `invitation_id`, `approved_at`, `activated_at`, `suspended_at`, `revoked_at`, `expires_at`, `updated_at`, `created_by`, `updated_by`, and `metadata`.

Invitation additions: `vendor_id`, `invited_user_id`, `intended_role`, `intended_status`, `approved_by`, `token_hash`, `token_version`, `expires_at`, `accepted_by`, `revoked_at`, `revoked_by`, `superseded_by`, and `metadata`.

The only new `NOT NULL` columns are safe-default fields: both `metadata` columns are `jsonb NOT NULL DEFAULT '{}'::jsonb`, and `mfr_invites.token_version` is `integer NOT NULL DEFAULT 1`. No existing column is tightened. All lifecycle, role, status, identity, approval, vendor-binding, and expiry columns are nullable; no default grants access or creates an active state.

The forward migration is `supabase/migrations/20260722194405_manufacturer_authorization_migration_001.sql`. Rollback and verification SQL live here and are never part of the automatic migration directory.

Indexes: `mfr_members_invitation_id_idx` supports invite lineage; `mfr_members_vendor_status_idx` supports future active-member lookup; `mfr_invites_vendor_id_idx` supports authoritative vendor invite lookup; and `mfr_invites_invited_user_id_idx` supports identity-bound invite lookup.

Deferred: eight foreign-key groups, including the future `mfr_invites.vendor_id → mfr_vendors.id` relationship (`ON DELETE RESTRICT`, `ON UPDATE NO ACTION`); role/status checks; unique token hash; active/expiry indexes; RLS; helpers; portal/browser behavior; Storage; and all authorization enforcement.

## Execution boundary

Use one atomic staging transaction, five-second lock timeout, and 30-second statement timeout. The forward migration sets transaction-local timeouts itself. Do not use concurrent indexes. Expected runtime is under five minutes, followed by a 30-minute observation period.

**THIS PACKAGE IS NOT APPROVED FOR EXECUTION UNTIL THE GLOBAL-ROLE MANUAL REVIEW AND ALL STAGING PRECONDITIONS ARE COMPLETE.**

See the runbooks and checklists in this directory. After any dependent workflow writes the added fields, destructive rollback is prohibited; disable the dependent release and forward-fix instead.
