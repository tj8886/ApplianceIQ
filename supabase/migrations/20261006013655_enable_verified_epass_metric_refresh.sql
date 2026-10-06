-- A preview is not reconciliation approval. Approval records are private and bound to current facts.
CREATE TABLE tj_private.epass_metric_reconciliation (
 organization_id uuid NOT NULL REFERENCES tj.organizations(id),from_date date NOT NULL,to_date date NOT NULL,timezone text NOT NULL,
 source_digest text NOT NULL CHECK(source_digest~'^[a-f0-9]{64}$'),approved_by uuid NOT NULL,expires_at timestamptz NOT NULL,
 PRIMARY KEY(organization_id,from_date,to_date,timezone));
ALTER TABLE tj_private.epass_metric_reconciliation ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj_private.epass_metric_reconciliation FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj_private.epass_metric_refresh(p_body jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
<<metrics>>
DECLARE conn tj.platform_connector_connections%rowtype;actor uuid:=tj_private.current_source_user_id();from_day date;to_day date;tz text:=coalesce(p_body->>'timezone','UTC');apply boolean:=coalesce((p_body->>'apply')::boolean,false);
 result_rows jsonb;digest text;all_count bigint;eligible_count bigint;written integer:=0;preview_rows jsonb;BEGIN
 IF p_body IS NULL OR jsonb_typeof(p_body)<>'object' OR octet_length(p_body::text)>8192 OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_body)k WHERE k NOT IN('action','connection_id','from','to','timezone','apply')) OR (p_body ? 'apply' AND jsonb_typeof(p_body->'apply')<>'boolean') THEN RAISE EXCEPTION 'invalid_request' USING ERRCODE='22023';END IF;
 conn:=tj_private.epass_connection(nullif(p_body->>'connection_id','')::uuid,actor);
 from_day:=nullif(p_body->>'from','')::date;to_day:=nullif(p_body->>'to','')::date;
 IF from_day IS NULL OR to_day IS NULL OR to_day<from_day OR to_day-from_day>30 OR from_day<'1900-01-01'::date OR NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=tz) THEN RAISE EXCEPTION 'bounded_dates_and_timezone_required' USING ERRCODE='22023';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('epass-metrics:'||conn.organization_id::text,0));
 WITH eligible AS(
  SELECT p.id,p.store_id AS location_id,(p.transaction_date AT TIME ZONE tz)::date AS day,p.transaction_amount AS revenue,p.cost_amount,p.gross_margin_amount AS margin,
   s.item_count AS units,s.warranty_value,s.delivery_value,s.install_value,s.haul_away_value,s.warranty_sold,
   CASE WHEN s.user_id IS NOT NULL AND EXISTS(
    SELECT 1 FROM tj.platform_connector_match_queue q JOIN tj.iq_pos_employee_map em ON em.organization_id=q.organization_id AND em.salesperson_user_id=q.candidate_id AND em.pos_employee_id=p.salesperson_external_id AND em.pos_system=prof.pos_system_key AND em.is_active AND (em.store_id IS NULL OR em.store_id=p.store_id)
    JOIN tj.organization_members om ON om.organization_id=q.organization_id AND om.user_id=q.candidate_id AND om.status='active'
    WHERE q.connection_id=p.source_connection_id AND q.organization_id=conn.organization_id AND q.external_entity_type='employee' AND q.candidate_id=s.user_id AND coalesce(nullif(q.external_code,''),q.external_id)=p.salesperson_external_id AND q.status='confirmed' AND q.metadata->>'us_onboarding_reviewed'='true'
   ) THEN s.user_id END AS person,
   jsonb_build_object('pos_id',p.id,'date',p.transaction_date,'amount',p.transaction_amount,'cost',p.cost_amount,'payload',p.source_payload,'sales',to_jsonb(s)) AS evidence
  FROM tj.iq_pos_transactions p JOIN tj.platform_connector_connections c ON c.id=p.source_connection_id AND c.organization_id=conn.organization_id JOIN tj.platform_connectors connector ON connector.id=c.connector_id AND connector.key='epass'
  JOIN tj.platform_connector_onboarding_profiles prof ON prof.connector_id=c.connector_id AND prof.variant_id IS NOT DISTINCT FROM c.variant_id AND prof.is_active
  JOIN tj.sales_transactions s ON s.organization_id=p.organization_id AND s.invoice_number=p.pos_transaction_id AND s.metadata->>'pos_transaction_id'=p.id::text AND s.metadata->>'source_connection_id'=c.id::text AND s.metadata->>'us_epass_bridge_version'='1' AND s.location_id IS NOT DISTINCT FROM p.store_id
  WHERE p.organization_id=conn.organization_id AND p.source_system='epass' AND p.transaction_date>=from_day::timestamp AT TIME ZONE tz AND p.transaction_date<(to_day+1)::timestamp AT TIME ZONE tz
   AND p.transaction_amount IS NOT NULL AND (p.store_id IS NULL OR EXISTS(SELECT 1 FROM tj.org_locations l WHERE l.id=p.store_id AND l.organization_id=conn.organization_id))
 ), grouped AS(
  SELECT location_id,person,day,count(*) AS transactions,sum(revenue) AS revenue,CASE WHEN bool_and(cost_amount IS NOT NULL) THEN sum(margin) END AS margin,
   sum(units) AS units,sum(warranty_value) AS warranty,sum(delivery_value) AS delivery,sum(install_value) AS install,
   count(*) FILTER(WHERE warranty_sold) AS warranty_n,count(*) FILTER(WHERE delivery_value<>0) AS delivery_n,count(*) FILTER(WHERE install_value<>0) AS install_n,count(*) FILTER(WHERE haul_away_value<>0) AS haul_n
  FROM eligible GROUP BY location_id,person,day
 ), expanded AS(
  SELECT g.location_id,g.person,g.day,v.key,v.actual FROM grouped g CROSS JOIN LATERAL(VALUES
   ('revenue',g.revenue),('transactions',g.transactions::numeric),('units_sold',g.units),('avg_order',g.revenue/nullif(g.transactions,0)),
   ('ipo',g.units/nullif(g.transactions,0)),('item_value',g.revenue/nullif(g.units,0)),('margin_dollars',g.margin),('margin_pct',g.margin/nullif(g.revenue,0)*100),
   ('warranty_attach',g.warranty_n::numeric/nullif(g.transactions,0)*100),('warranty_pen_units',g.warranty_n::numeric/nullif(g.units,0)*100),('warranty_pen_dollars',g.warranty/nullif(g.revenue,0)*100),
   ('delivery_revenue',g.delivery),('install_revenue',g.install),('delivery_attach',g.delivery_n::numeric/nullif(g.transactions,0)*100),('install_attach',g.install_n::numeric/nullif(g.transactions,0)*100),('haul_away_attach',g.haul_n::numeric/nullif(g.transactions,0)*100)
  )v(key,actual) WHERE v.actual IS NOT NULL
 ) SELECT coalesce((SELECT jsonb_agg(jsonb_build_object('location_id',e.location_id,'user_id',e.person,'period_key',e.day::text,'metric_key',e.key,'actual_value',round(e.actual,2)) ORDER BY e.day,e.location_id,e.person,e.key) FROM expanded e),'[]'),
  encode(sha256(convert_to(coalesce((SELECT jsonb_agg(jsonb_build_object('evidence',e.evidence,'effective_person',e.person) ORDER BY e.id)::text FROM eligible e),'[]'),'UTF8')),'hex'),(SELECT count(*) FROM eligible)
  INTO result_rows,digest,eligible_count;
 SELECT count(*) INTO all_count FROM tj.iq_pos_transactions p WHERE p.organization_id=conn.organization_id AND p.transaction_date>=from_day::timestamp AT TIME ZONE tz AND p.transaction_date<(to_day+1)::timestamp AT TIME ZONE tz;
 IF jsonb_array_length(result_rows)>10000 THEN RAISE EXCEPTION 'narrow_metric_date_window' USING ERRCODE='54000';END IF;
 -- Never replace a mixed-provider or unreconciled historical connector total with a partial ePASS subset.
 IF apply THEN
  IF eligible_count<>all_count OR eligible_count=0 THEN RAISE EXCEPTION 'complete_connector_scope_reconciliation_required' USING ERRCODE='40001';END IF;
  IF NOT EXISTS(SELECT 1 FROM tj_private.epass_metric_reconciliation r JOIN tj.organization_members m ON m.organization_id=r.organization_id AND m.user_id=r.approved_by AND m.status='active' AND m.role IN('owner','admin','super_admin') WHERE r.organization_id=conn.organization_id AND r.from_date=from_day AND r.to_date=to_day AND r.timezone=tz AND r.source_digest=digest AND r.expires_at>clock_timestamp()) THEN RAISE EXCEPTION 'fresh_metric_reconciliation_approval_required' USING ERRCODE='40001';END IF;
  -- Replace only this approved date window and derived subtype; unrelated snapshots survive.
  DELETE FROM tj.metric_snapshots s WHERE s.organization_id=conn.organization_id AND s.period_type='daily' AND s.metric_subtype='connector_transaction' AND s.period_key BETWEEN from_day::text AND to_day::text;
  INSERT INTO tj.metric_snapshots(organization_id,location_id,user_id,period_type,period_key,metric_key,metric_subtype,actual_value,computed_at)
   SELECT conn.organization_id,(v->>'location_id')::uuid,(v->>'user_id')::uuid,'daily',v->>'period_key',v->>'metric_key','connector_transaction',(v->>'actual_value')::numeric,clock_timestamp() FROM jsonb_array_elements(result_rows)v;
  GET DIAGNOSTICS written=ROW_COUNT;
 END IF;
 SELECT coalesce(jsonb_agg(v),'[]') INTO preview_rows FROM (SELECT value v FROM jsonb_array_elements(result_rows) LIMIT 200)p;
 RETURN jsonb_build_object('ok',true,'organization_id',conn.organization_id,'from',from_day,'to',to_day,'timezone',tz,'source_digest',digest,'receipts_in_scope',all_count,'verified_receipts',eligible_count,'complete_scope',all_count=eligible_count AND eligible_count>0,'metrics_count',jsonb_array_length(result_rows),'metrics',preview_rows,'preview_truncated',jsonb_array_length(result_rows)>200,'metrics_refreshed',apply,'written',written,'requires_reconciliation_approval',NOT apply,'targets_generated',false);
END $$;
REVOKE ALL ON FUNCTION tj_private.epass_metric_refresh(jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION tj_private.epass_metric_refresh(jsonb) TO authenticated;
CREATE FUNCTION public.tj_epass_metric_refresh(p_body jsonb) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$SELECT tj_private.epass_metric_refresh(p_body);$$;
REVOKE ALL ON FUNCTION public.tj_epass_metric_refresh(jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.tj_epass_metric_refresh(jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';
