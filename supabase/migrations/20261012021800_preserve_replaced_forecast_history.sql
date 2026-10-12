CREATE TABLE tj_private.source_forecast_history (
 source_project text NOT NULL,
 source_table text NOT NULL CHECK (source_table IN ('decision_predictions','iq_staffing_predictions')),
 source_key uuid NOT NULL,
 organization_id uuid NOT NULL,
 source_row jsonb NOT NULL,
 source_checksum text NOT NULL,
 preservation_reason text NOT NULL,
 recorded_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(source_project,source_table,source_key)
);
ALTER TABLE tj_private.source_forecast_history ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj_private.source_forecast_history FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON TABLE tj_private.source_forecast_history IS 'Exact Canadian forecast rows superseded by native US regeneration; retain history without reactivating stale predictions. No browser or service-role access.';
