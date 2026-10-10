-- Private audit metadata only; no credentials or public/user access.
CREATE TABLE tj_private.auth_import_ledger (
  source_project_ref text NOT NULL,
  source_user_id uuid NOT NULL,
  target_user_id uuid NOT NULL UNIQUE,
  batch_id uuid NOT NULL,
  source_identity_count integer NOT NULL CHECK(source_identity_count>0),
  source_email_confirmed boolean NOT NULL,
  mapping_activated boolean NOT NULL,
  import_method text NOT NULL CHECK(import_method='preserved_source_credentials'),
  imported_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(source_project_ref,source_user_id)
);
ALTER TABLE tj_private.auth_import_ledger ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj_private.auth_import_ledger FROM PUBLIC,anon,authenticated;
