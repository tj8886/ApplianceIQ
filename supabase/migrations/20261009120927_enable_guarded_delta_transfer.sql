-- Fixed append window, insert-only, service-only. No changes to US public tables.
CREATE TABLE tj_private.migration_delta_journal (
  run_id uuid NOT NULL,
  table_name text NOT NULL CHECK (table_name IN ('phase7_action_audit','phase7_automation_policies')),
  row_key text NOT NULL,
  organization_id uuid,
  row_checksum text NOT NULL,
  inserted boolean NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(run_id,table_name,row_key)
);
ALTER TABLE tj_private.migration_delta_journal ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj_private.migration_delta_journal FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON TABLE tj_private.migration_delta_journal IS 'Administrative migration provenance; organization_id copied from source. No client access. Retain for audited, hash-guarded rollback.';

CREATE FUNCTION tj_private.apply_delta_batch(p_table text,p_rows jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' SET timezone='UTC' SET bytea_output='hex' AS $$
DECLARE
  v_run constant uuid := '14f5293c-b01c-48e4-95b5-124ebc617c54';
  v_count integer; v_inserted integer; v_columns text; v_bad integer;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'service_role_required'; END IF;
  IF clock_timestamp() >= '2026-10-09 14:30:00+00'::timestamptz THEN RAISE EXCEPTION 'transfer_closed'; END IF;
  IF p_table NOT IN ('phase7_action_audit','phase7_automation_policies') OR p_table IS NULL THEN RAISE EXCEPTION 'table_not_allowed'; END IF;
  IF jsonb_typeof(p_rows) IS DISTINCT FROM 'array' OR jsonb_array_length(p_rows) NOT BETWEEN 1 AND 500 OR octet_length(p_rows::text)>2000000 THEN RAISE EXCEPTION 'invalid_batch'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('aiq_delta_'||p_table,0));
  EXECUTE format('CREATE TEMP TABLE aiq_delta_input (LIKE tj.%I INCLUDING DEFAULTS) ON COMMIT DROP',p_table);
  SELECT string_agg(quote_ident(a.attname),',' ORDER BY a.attnum) INTO v_columns FROM pg_attribute a WHERE a.attrelid=format('tj.%I',p_table)::regclass AND a.attnum>0 AND NOT a.attisdropped AND a.attgenerated='';
  EXECUTE format('INSERT INTO pg_temp.aiq_delta_input (%s) SELECT %s FROM jsonb_populate_recordset(NULL::tj.%I,$1)',v_columns,v_columns,p_table) USING p_rows;
  SELECT count(*),count(*)-count(DISTINCT id) INTO v_count,v_bad FROM pg_temp.aiq_delta_input;
  IF v_bad<>0 THEN RAISE EXCEPTION 'duplicate_source_key'; END IF;
  -- Reject unknown/missing columns rather than silently discarding source information.
  SELECT count(*) INTO v_bad FROM jsonb_array_elements(p_rows) r WHERE (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(r) k) IS DISTINCT FROM (SELECT array_agg(a.attname::text ORDER BY a.attname::text) FROM pg_attribute a WHERE a.attrelid=format('tj.%I',p_table)::regclass AND a.attnum>0 AND NOT a.attisdropped AND a.attgenerated='');
  IF v_bad<>0 THEN RAISE EXCEPTION 'source_column_mismatch'; END IF;
  IF p_table='phase7_action_audit' THEN
    SELECT count(*) INTO v_bad FROM pg_temp.aiq_delta_input WHERE id IS NULL OR id<=252802 OR id>275452;
  ELSE
    SELECT count(*) INTO v_bad FROM pg_temp.aiq_delta_input WHERE id IS NULL OR created_at IS NULL OR created_at<='2026-10-04 18:45:00.236213+00'::timestamptz OR created_at>'2026-10-09 12:00:00.185084+00'::timestamptz;
  END IF;
  IF v_bad<>0 THEN RAISE EXCEPTION 'outside_transfer_window'; END IF;
  EXECUTE format('SELECT count(*) FROM tj.%I d JOIN pg_temp.aiq_delta_input s USING(id) WHERE to_jsonb(d) IS DISTINCT FROM to_jsonb(s)',p_table) INTO v_bad;
  IF v_bad<>0 THEN RAISE EXCEPTION 'destination_conflict'; END IF;
  -- Record whether each key was already present before the insert. Retry retains original provenance.
  EXECUTE format('INSERT INTO tj_private.migration_delta_journal(run_id,table_name,row_key,organization_id,row_checksum,inserted) SELECT $1,$2,s.id::text,s.organization_id,md5(to_jsonb(s)::text),d.id IS NULL FROM pg_temp.aiq_delta_input s LEFT JOIN tj.%I d USING(id) ON CONFLICT DO NOTHING',p_table) USING v_run,p_table;
  EXECUTE format('INSERT INTO tj.%I(%s) SELECT %s FROM pg_temp.aiq_delta_input ON CONFLICT(id) DO NOTHING',p_table,v_columns,v_columns);
  GET DIAGNOSTICS v_inserted=ROW_COUNT;
  EXECUTE format('SELECT count(*) FROM pg_temp.aiq_delta_input s LEFT JOIN tj.%I d USING(id) JOIN tj_private.migration_delta_journal j ON j.run_id=$1 AND j.table_name=$2 AND j.row_key=s.id::text WHERE d.id IS NULL OR to_jsonb(s) IS DISTINCT FROM to_jsonb(d) OR j.row_checksum IS DISTINCT FROM md5(to_jsonb(s)::text)',p_table) INTO v_bad USING v_run,p_table;
  IF v_bad<>0 THEN RAISE EXCEPTION 'saved_row_mismatch'; END IF;
  -- The staging table has no serial default/owned sequence; preserve that definition.
  DROP TABLE pg_temp.aiq_delta_input;
  RETURN jsonb_build_object('received',v_count,'inserted',v_inserted);
END;
$$;
REVOKE ALL ON FUNCTION tj_private.apply_delta_batch(text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj_private.apply_delta_batch(text,jsonb) TO service_role;
CREATE FUNCTION public.aiq_apply_delta_batch(p_table text,p_rows jsonb) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.apply_delta_batch(p_table,p_rows); $$;
REVOKE ALL ON FUNCTION public.aiq_apply_delta_batch(text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.aiq_apply_delta_batch(text,jsonb) TO service_role;
