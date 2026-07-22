-- Migration 001: additive manufacturer authorization lifecycle foundation.
-- Staging execution only after all documented gates are approved.
-- Intentionally fails on pre-existing/conflicting objects; do not rerun manually.

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

ALTER TABLE public.mfr_members
  ADD COLUMN role text,
  ADD COLUMN status text,
  ADD COLUMN invited_by uuid,
  ADD COLUMN approved_by uuid,
  ADD COLUMN invitation_id uuid,
  ADD COLUMN approved_at timestamptz,
  ADD COLUMN activated_at timestamptz,
  ADD COLUMN suspended_at timestamptz,
  ADD COLUMN revoked_at timestamptz,
  ADD COLUMN expires_at timestamptz,
  ADD COLUMN updated_at timestamptz,
  ADD COLUMN created_by uuid,
  ADD COLUMN updated_by uuid,
  ADD COLUMN metadata jsonb NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE public.mfr_invites
  ADD COLUMN vendor_id uuid,
  ADD COLUMN invited_user_id uuid,
  ADD COLUMN intended_role text,
  ADD COLUMN intended_status text,
  ADD COLUMN approved_by uuid,
  ADD COLUMN token_hash text,
  ADD COLUMN token_version integer NOT NULL DEFAULT 1,
  ADD COLUMN expires_at timestamptz,
  ADD COLUMN accepted_by uuid,
  ADD COLUMN revoked_at timestamptz,
  ADD COLUMN revoked_by uuid,
  ADD COLUMN superseded_by uuid,
  ADD COLUMN metadata jsonb NOT NULL DEFAULT '{}'::jsonb;

CREATE INDEX mfr_members_invitation_id_idx
  ON public.mfr_members USING btree (invitation_id);

CREATE INDEX mfr_members_vendor_status_idx
  ON public.mfr_members USING btree (vendor_id, status);

CREATE INDEX mfr_invites_vendor_id_idx
  ON public.mfr_invites USING btree (vendor_id);

CREATE INDEX mfr_invites_invited_user_id_idx
  ON public.mfr_invites USING btree (invited_user_id);

COMMIT;
