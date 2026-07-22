-- Manual rollback for Migration 001 only.
-- Execute only before any later workflow writes the added fields and only with
-- database-owner approval. After dependent writes or migrations, use a forward fix.

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DROP INDEX public.mfr_invites_invited_user_id_idx;
DROP INDEX public.mfr_invites_vendor_id_idx;
DROP INDEX public.mfr_members_vendor_status_idx;
DROP INDEX public.mfr_members_invitation_id_idx;

ALTER TABLE public.mfr_invites
  DROP COLUMN metadata,
  DROP COLUMN superseded_by,
  DROP COLUMN revoked_by,
  DROP COLUMN revoked_at,
  DROP COLUMN accepted_by,
  DROP COLUMN expires_at,
  DROP COLUMN token_version,
  DROP COLUMN token_hash,
  DROP COLUMN approved_by,
  DROP COLUMN intended_status,
  DROP COLUMN intended_role,
  DROP COLUMN invited_user_id,
  DROP COLUMN vendor_id;

ALTER TABLE public.mfr_members
  DROP COLUMN metadata,
  DROP COLUMN updated_by,
  DROP COLUMN created_by,
  DROP COLUMN updated_at,
  DROP COLUMN expires_at,
  DROP COLUMN revoked_at,
  DROP COLUMN suspended_at,
  DROP COLUMN activated_at,
  DROP COLUMN approved_at,
  DROP COLUMN invitation_id,
  DROP COLUMN approved_by,
  DROP COLUMN invited_by,
  DROP COLUMN status,
  DROP COLUMN role;

COMMIT;
