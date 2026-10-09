CREATE TABLE tj_private.migration_delta_before_images (
  run_id uuid NOT NULL,
  table_name text NOT NULL,
  row_key text NOT NULL,
  organization_id uuid,
  before_data jsonb,
  source_checksum text NOT NULL,
  after_checksum text,
  transferred_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(run_id,table_name,row_key)
);
CREATE INDEX migration_delta_before_images_organization_idx ON tj_private.migration_delta_before_images(organization_id);
ALTER TABLE tj_private.migration_delta_before_images ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj_private.migration_delta_before_images FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON TABLE tj_private.migration_delta_before_images IS 'Private reviewed Canada delta before images, preserving replaced US staging records for hash-guarded rollback. No client access; no hard deletion of US-only records.';
