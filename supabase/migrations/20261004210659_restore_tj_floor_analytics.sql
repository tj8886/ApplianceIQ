-- Organization-scoped analytics. No new table grants or production writes.
CREATE OR REPLACE FUNCTION tj_private.get_floor_by_store(p_org_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE result JSONB;
BEGIN
  IF p_org_id IS NULL OR NOT tj.is_org_member(p_org_id) THEN
    RAISE EXCEPTION 'access_denied' USING ERRCODE='42501';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM tj.organizations WHERE id=p_org_id AND deleted_at IS NULL) THEN
    RAISE EXCEPTION 'access_denied' USING ERRCODE='42501';
  END IF;

  SELECT COALESCE(jsonb_agg(store_data ORDER BY store_data->>'store_name'), '[]'::jsonb)
  INTO result
  FROM (
    SELECT jsonb_build_object(
      'store_id', l.id, 'store_name', l.name, 'city', l.city,
      'total_displays', COALESCE(dc.display_count, 0),
      'total_floor_units', COALESCE(dc.floor_units, 0),
      'total_skus', COALESCE(sc.sku_count, 0),
      'configured_units', COALESCE(fc.total_floor_units, 0),
      'unit_label', COALESCE(fc.floor_unit_label, 'bays'),
      'brand_count', COALESCE(dc.brand_count, 0),
      'last_snapshot', (SELECT MAX(snapshot_date) FROM tj.field_floor_snapshots s
                        WHERE s.store_id = l.id AND s.organization_id = p_org_id)
    ) AS store_data
    FROM tj.org_locations l
    LEFT JOIN LATERAL (
      SELECT COUNT(*) AS display_count, SUM(d.floor_units) AS floor_units,
             COUNT(DISTINCT d.brand_name) AS brand_count
      FROM tj.field_floor_displays d
      WHERE d.store_id = l.id AND d.organization_id = p_org_id AND d.is_active = true
    ) dc ON true
    LEFT JOIN LATERAL (
      SELECT COUNT(*) AS sku_count FROM tj.field_floor_display_skus s
      WHERE s.store_id = l.id AND s.organization_id = p_org_id AND s.is_active = true
    ) sc ON true
    LEFT JOIN tj.field_floor_config fc ON fc.store_id = l.id AND fc.organization_id = p_org_id
    WHERE l.organization_id = p_org_id AND l.is_active = true
      AND COALESCE(dc.display_count, 0) > 0
  ) sub;

  RETURN result;
END;
$function$;

REVOKE ALL ON FUNCTION tj_private.get_floor_by_store(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj_private.get_floor_by_store(uuid) TO authenticated;
CREATE FUNCTION tj.get_floor_by_store(p_org_id uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.get_floor_by_store(p_org_id); $$;
REVOKE ALL ON FUNCTION tj.get_floor_by_store(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj.get_floor_by_store(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION tj_private.get_floor_gaps(p_org_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  result JSONB;
  sold_not_floored JSONB;
  floored_not_sold JSONB;
  sku_detail JSONB;
BEGIN
  IF p_org_id IS NULL OR NOT tj.is_org_member(p_org_id) THEN
    RAISE EXCEPTION 'access_denied' USING ERRCODE='42501';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM tj.organizations WHERE id=p_org_id AND deleted_at IS NULL) THEN
    RAISE EXCEPTION 'access_denied' USING ERRCODE='42501';
  END IF;
  -- Brands selling with no floor presence
  WITH floored_brands AS (
    SELECT DISTINCT COALESCE(s.brand_name, d.brand_name) AS brand
    FROM tj.field_floor_displays d
    LEFT JOIN tj.field_floor_display_skus s ON s.display_id = d.id AND s.organization_id = p_org_id AND s.is_active = true
    WHERE d.organization_id = p_org_id AND d.is_active = true
  ),
  sold_brands AS (
    SELECT COALESCE(p.value->>'brand', p.value->>'brand_name', 'Unknown') AS brand,
           SUM(COALESCE((p.value->>'price')::numeric, 0)) AS revenue,
           COUNT(*) AS units
    FROM tj.crm_deals d, jsonb_array_elements(d.won_products) AS p(value)
    WHERE d.organization_id = p_org_id AND d.stage ILIKE '%won%'
    AND d.won_products IS NOT NULL AND jsonb_typeof(d.won_products) = 'array'
    GROUP BY 1
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'brand', sb.brand, 'revenue', sb.revenue, 'units', sb.units
  ) ORDER BY sb.revenue DESC), '[]'::jsonb)
  INTO sold_not_floored
  FROM sold_brands sb
  WHERE NOT EXISTS (SELECT 1 FROM floored_brands fb WHERE fb.brand = sb.brand);

  -- Brands on floor with no sales
  WITH floored_brands AS (
    SELECT COALESCE(s.brand_name, d.brand_name) AS brand,
           SUM(d.floor_units / GREATEST((SELECT COUNT(*) FROM tj.field_floor_display_skus x WHERE x.display_id = d.id AND x.organization_id = p_org_id AND x.is_active = true), 1)) AS units
    FROM tj.field_floor_displays d
    LEFT JOIN tj.field_floor_display_skus s ON s.display_id = d.id AND s.organization_id = p_org_id AND s.is_active = true
    WHERE d.organization_id = p_org_id AND d.is_active = true
    GROUP BY 1
  ),
  sold_brands AS (
    SELECT DISTINCT COALESCE(p.value->>'brand', p.value->>'brand_name', 'Unknown') AS brand
    FROM tj.crm_deals d, jsonb_array_elements(d.won_products) AS p(value)
    WHERE d.organization_id = p_org_id AND d.stage ILIKE '%won%'
    AND d.won_products IS NOT NULL AND jsonb_typeof(d.won_products) = 'array'
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'brand', fb.brand, 'floor_units', fb.units
  ) ORDER BY fb.units DESC), '[]'::jsonb)
  INTO floored_not_sold
  FROM floored_brands fb
  WHERE fb.brand IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM sold_brands sb WHERE sb.brand = fb.brand);

  -- SKU-level: sold products flagged floored / not floored
  WITH sold_skus AS (
    SELECT 
      COALESCE(p.value->>'model', p.value->>'sku', p.value->>'name') AS model,
      COALESCE(p.value->>'brand', p.value->>'brand_name') AS brand,
      COALESCE(p.value->>'category', 'Other') AS category,
      SUM(COALESCE((p.value->>'price')::numeric, 0)) AS revenue,
      COUNT(*) AS units
    FROM tj.crm_deals d, jsonb_array_elements(d.won_products) AS p(value)
    WHERE d.organization_id = p_org_id AND d.stage ILIKE '%won%'
    AND d.won_products IS NOT NULL AND jsonb_typeof(d.won_products) = 'array'
    GROUP BY 1,2,3
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'model', ss.model,
    'brand', ss.brand,
    'category', ss.category,
    'revenue', ss.revenue,
    'units', ss.units,
    'is_floored', EXISTS (
      SELECT 1 FROM tj.field_floor_display_skus fs
      WHERE fs.organization_id = p_org_id AND fs.is_active = true
      AND (LOWER(fs.model_number) = LOWER(ss.model) OR LOWER(fs.sku) = LOWER(ss.model))
    )
  ) ORDER BY ss.revenue DESC), '[]'::jsonb)
  INTO sku_detail
  FROM sold_skus ss;

  result := jsonb_build_object(
    'sold_not_floored', sold_not_floored,
    'floored_not_sold', floored_not_sold,
    'sku_detail', sku_detail
  );

  RETURN result;
END;
$function$;

REVOKE ALL ON FUNCTION tj_private.get_floor_gaps(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj_private.get_floor_gaps(uuid) TO authenticated;
CREATE FUNCTION tj.get_floor_gaps(p_org_id uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.get_floor_gaps(p_org_id); $$;
REVOKE ALL ON FUNCTION tj.get_floor_gaps(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj.get_floor_gaps(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION tj_private.get_floor_holes(p_org_id uuid, p_store_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  result JSONB;
  holes JSONB;
  tasks JSONB;
  v_days_to_order INTEGER;
  v_days_to_fill INTEGER;
  v_grace INTEGER;
  summary JSONB;
BEGIN
  IF p_org_id IS NULL OR NOT tj.is_org_member(p_org_id) THEN
    RAISE EXCEPTION 'access_denied' USING ERRCODE='42501';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM tj.organizations WHERE id=p_org_id AND deleted_at IS NULL) THEN
    RAISE EXCEPTION 'access_denied' USING ERRCODE='42501';
  END IF;
  SELECT COALESCE(days_to_order,3), COALESCE(days_to_fill,14), COALESCE(overdue_grace_days,2)
  INTO v_days_to_order, v_days_to_fill, v_grace
  FROM tj.field_floor_hole_sla WHERE organization_id = p_org_id;

  v_days_to_order := COALESCE(v_days_to_order, 3);
  v_days_to_fill  := COALESCE(v_days_to_fill, 14);
  v_grace         := COALESCE(v_grace, 2);

  -- Build enriched hole list
  WITH enriched AS (
    SELECT
      h.*,
      l.name AS store_name,
      d.display_name,
      d.display_type,
      (CURRENT_DATE - h.removed_at) AS days_open,
      CASE
        WHEN h.expected_arrival IS NOT NULL THEN (CURRENT_DATE - h.expected_arrival)
        ELSE NULL
      END AS days_past_eta,
      CASE
        -- Never ordered and past the order window
        WHEN h.status = 'open' AND (CURRENT_DATE - h.removed_at) > v_days_to_order THEN 'not_ordered'
        -- Ordered but ETA blown
        WHEN h.status IN ('ordered','in_transit') AND h.expected_arrival IS NOT NULL
             AND CURRENT_DATE > (h.expected_arrival + v_grace) THEN 'eta_missed'
        -- Ordered with no ETA at all
        WHEN h.status IN ('ordered','in_transit') AND h.expected_arrival IS NULL THEN 'no_eta'
        -- Received but not put on floor
        WHEN h.status = 'received' THEN 'awaiting_placement'
        -- Open but still inside the order window
        WHEN h.status = 'open' THEN 'needs_order'
        -- Total time on floor exceeded
        WHEN h.status NOT IN ('filled','cancelled') AND (CURRENT_DATE - h.removed_at) > v_days_to_fill THEN 'overdue_fill'
        ELSE 'on_track'
      END AS issue_type
    FROM tj.field_floor_holes h
    JOIN tj.org_locations l ON l.id = h.store_id AND l.organization_id = p_org_id
    LEFT JOIN tj.field_floor_displays d ON d.id = h.display_id AND d.organization_id = p_org_id
    WHERE h.organization_id = p_org_id
      AND h.status NOT IN ('filled','cancelled')
      AND (p_store_id IS NULL OR h.store_id = p_store_id)
  ),
  scored AS (
    SELECT *,
      CASE
        WHEN issue_type IN ('not_ordered','eta_missed') THEN 'critical'
        WHEN issue_type IN ('no_eta','awaiting_placement') THEN 'high'
        WHEN issue_type = 'overdue_fill' THEN 'high'
        WHEN issue_type = 'needs_order' THEN 'normal'
        ELSE 'low'
      END AS urgency,
      CASE
        WHEN issue_type = 'not_ordered' THEN 'No order placed — ' || (CURRENT_DATE - removed_at) || ' days empty'
        WHEN issue_type = 'eta_missed' THEN 'Past expected arrival by ' || (CURRENT_DATE - expected_arrival) || ' days'
        WHEN issue_type = 'no_eta' THEN 'Ordered with no ETA on file'
        WHEN issue_type = 'awaiting_placement' THEN 'Received — needs to go on floor'
        WHEN issue_type = 'overdue_fill' THEN 'Open ' || (CURRENT_DATE - removed_at) || ' days'
        WHEN issue_type = 'needs_order' THEN 'Needs order within ' || (v_days_to_order - (CURRENT_DATE - removed_at)) || ' days'
        ELSE 'On track'
      END AS issue_label
    FROM enriched
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', id,
    'store_id', store_id,
    'store_name', store_name,
    'display_id', display_id,
    'display_name', display_name,
    'slot_label', slot_label,
    'expected_category', expected_category,
    'brand_name', brand_name,
    'removed_product_name', removed_product_name,
    'removed_model_number', removed_model_number,
    'removal_reason', removal_reason,
    'removed_at', removed_at,
    'days_open', days_open,
    'status', status,
    'replacement_product_name', replacement_product_name,
    'replacement_model_number', replacement_model_number,
    'po_number', po_number,
    'ordered_at', ordered_at,
    'expected_arrival', expected_arrival,
    'days_past_eta', days_past_eta,
    'received_at', received_at,
    'priority', priority,
    'notes', notes,
    'issue_type', issue_type,
    'issue_label', issue_label,
    'urgency', urgency
  ) ORDER BY
    CASE urgency WHEN 'critical' THEN 1 WHEN 'high' THEN 2 WHEN 'normal' THEN 3 ELSE 4 END,
    days_open DESC
  ), '[]'::jsonb)
  INTO holes
  FROM scored;

  -- Task list: only actionable issues
  WITH enriched AS (
    SELECT
      h.id, h.store_id, l.name AS store_name, d.display_name, h.slot_label,
      h.removed_product_name, h.removed_model_number, h.expected_category, h.brand_name,
      h.status, h.expected_arrival, h.po_number, h.removed_at,
      (CURRENT_DATE - h.removed_at) AS days_open,
      CASE
        WHEN h.status = 'open' AND (CURRENT_DATE - h.removed_at) > v_days_to_order THEN 'not_ordered'
        WHEN h.status IN ('ordered','in_transit') AND h.expected_arrival IS NOT NULL
             AND CURRENT_DATE > (h.expected_arrival + v_grace) THEN 'eta_missed'
        WHEN h.status IN ('ordered','in_transit') AND h.expected_arrival IS NULL THEN 'no_eta'
        WHEN h.status = 'received' THEN 'awaiting_placement'
        WHEN h.status = 'open' THEN 'needs_order'
        ELSE 'on_track'
      END AS issue_type
    FROM tj.field_floor_holes h
    JOIN tj.org_locations l ON l.id = h.store_id AND l.organization_id = p_org_id
    LEFT JOIN tj.field_floor_displays d ON d.id = h.display_id AND d.organization_id = p_org_id
    WHERE h.organization_id = p_org_id
      AND h.status NOT IN ('filled','cancelled')
      AND (p_store_id IS NULL OR h.store_id = p_store_id)
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'hole_id', id,
    'store_name', store_name,
    'display_name', COALESCE(display_name, slot_label, 'Unassigned slot'),
    'what', COALESCE(removed_product_name, brand_name || ' ' || COALESCE(expected_category,''), 'Empty slot'),
    'action', CASE issue_type
      WHEN 'not_ordered' THEN 'Place replacement order'
      WHEN 'eta_missed' THEN 'Chase vendor on PO ' || COALESCE(po_number, '(no PO)')
      WHEN 'no_eta' THEN 'Get ETA from vendor'
      WHEN 'awaiting_placement' THEN 'Put unit on floor'
      WHEN 'needs_order' THEN 'Order replacement'
      ELSE 'Review'
    END,
    'detail', CASE issue_type
      WHEN 'not_ordered' THEN 'Empty ' || days_open || ' days with no order placed'
      WHEN 'eta_missed' THEN 'Expected ' || expected_arrival || ' — now ' || (CURRENT_DATE - expected_arrival) || ' days late'
      WHEN 'no_eta' THEN 'Order placed but no arrival date recorded'
      WHEN 'awaiting_placement' THEN 'Unit received and sitting in back'
      WHEN 'needs_order' THEN 'Slot opened ' || days_open || ' day(s) ago'
      ELSE ''
    END,
    'urgency', CASE
      WHEN issue_type IN ('not_ordered','eta_missed') THEN 'critical'
      WHEN issue_type IN ('no_eta','awaiting_placement') THEN 'high'
      WHEN issue_type = 'needs_order' THEN 'normal'
      ELSE 'low'
    END,
    'days_open', days_open
  ) ORDER BY
    CASE
      WHEN issue_type IN ('not_ordered','eta_missed') THEN 1
      WHEN issue_type IN ('no_eta','awaiting_placement') THEN 2
      WHEN issue_type = 'needs_order' THEN 3
      ELSE 4
    END,
    days_open DESC
  ), '[]'::jsonb)
  INTO tasks
  FROM enriched
  WHERE issue_type <> 'on_track';

  -- Summary counts
  SELECT jsonb_build_object(
    'total_open', COUNT(*) FILTER (WHERE status NOT IN ('filled','cancelled')),
    'not_ordered', COUNT(*) FILTER (WHERE status = 'open' AND (CURRENT_DATE - removed_at) > v_days_to_order),
    'awaiting_order', COUNT(*) FILTER (WHERE status = 'open'),
    'in_pipeline', COUNT(*) FILTER (WHERE status IN ('ordered','in_transit')),
    'overdue_eta', COUNT(*) FILTER (WHERE status IN ('ordered','in_transit') AND expected_arrival IS NOT NULL AND CURRENT_DATE > (expected_arrival + v_grace)),
    'awaiting_placement', COUNT(*) FILTER (WHERE status = 'received'),
    'avg_days_open', COALESCE(ROUND(AVG(CURRENT_DATE - removed_at) FILTER (WHERE status NOT IN ('filled','cancelled')), 1), 0),
    'filled_last_30', (SELECT COUNT(*) FROM tj.field_floor_holes f2
      WHERE f2.organization_id = p_org_id AND f2.status = 'filled'
      AND f2.filled_at >= CURRENT_DATE - 30
      AND (p_store_id IS NULL OR f2.store_id = p_store_id))
  )
  INTO summary
  FROM tj.field_floor_holes
  WHERE organization_id = p_org_id
    AND (p_store_id IS NULL OR store_id = p_store_id);

  result := jsonb_build_object(
    'summary', COALESCE(summary, '{}'::jsonb),
    'holes', holes,
    'tasks', tasks,
    'sla', jsonb_build_object('days_to_order', v_days_to_order, 'days_to_fill', v_days_to_fill, 'grace', v_grace)
  );

  RETURN result;
END;
$function$;

REVOKE ALL ON FUNCTION tj_private.get_floor_holes(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj_private.get_floor_holes(uuid,uuid) TO authenticated;
CREATE FUNCTION tj.get_floor_holes(p_org_id uuid,p_store_id uuid DEFAULT NULL::uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.get_floor_holes(p_org_id,p_store_id); $$;
REVOKE ALL ON FUNCTION tj.get_floor_holes(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj.get_floor_holes(uuid,uuid) TO authenticated;
CREATE OR REPLACE FUNCTION tj_private.get_floor_vs_sales(p_org_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  result JSONB;
  brand_floor JSONB;
  brand_sales JSONB;
  cat_floor JSONB;
  cat_sales JSONB;
  total_floor_units NUMERIC := 0;
  total_sales NUMERIC := 0;
  total_displays INTEGER := 0;
  total_skus INTEGER := 0;
  store_count INTEGER := 0;
BEGIN
  IF p_org_id IS NULL OR NOT tj.is_org_member(p_org_id) THEN
    RAISE EXCEPTION 'access_denied' USING ERRCODE='42501';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM tj.organizations WHERE id=p_org_id AND deleted_at IS NULL) THEN
    RAISE EXCEPTION 'access_denied' USING ERRCODE='42501';
  END IF;

  SELECT COALESCE(SUM(d.floor_units), 0), COUNT(DISTINCT d.id), COUNT(DISTINCT d.store_id)
  INTO total_floor_units, total_displays, store_count
  FROM tj.field_floor_displays d
  WHERE d.organization_id = p_org_id AND d.is_active = true;

  SELECT COUNT(*) INTO total_skus
  FROM tj.field_floor_display_skus s
  WHERE s.organization_id = p_org_id AND s.is_active = true;

  WITH display_brand_units AS (
    SELECT COALESCE(s.brand_name, d.brand_name, 'Unbranded') AS brand,
           d.floor_units / GREATEST(sku_count.cnt, 1) AS units
    FROM tj.field_floor_displays d
    JOIN tj.field_floor_display_skus s ON s.display_id = d.id AND s.organization_id = p_org_id AND s.is_active = true
    JOIN LATERAL (SELECT COUNT(*) AS cnt FROM tj.field_floor_display_skus
                  WHERE display_id = d.id AND organization_id = p_org_id AND is_active = true) sku_count ON true
    WHERE d.organization_id = p_org_id AND d.is_active = true
    UNION ALL
    SELECT COALESCE(d.brand_name, 'Unbranded'), d.floor_units
    FROM tj.field_floor_displays d
    WHERE d.organization_id = p_org_id AND d.is_active = true
      AND NOT EXISTS (SELECT 1 FROM tj.field_floor_display_skus s
                      WHERE s.display_id = d.id AND s.organization_id = p_org_id AND s.is_active = true)
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'brand', brand, 'floor_units', total_units,
    'floor_pct', CASE WHEN total_floor_units > 0 THEN ROUND((total_units / total_floor_units * 100)::numeric, 1) ELSE 0 END
  ) ORDER BY total_units DESC), '[]'::jsonb)
  INTO brand_floor
  FROM (SELECT brand, SUM(units) AS total_units FROM display_brand_units GROUP BY brand) sub;

  WITH display_cat_units AS (
    SELECT COALESCE(s.product_category, d.primary_category, 'other') AS category,
           d.floor_units / GREATEST(sku_count.cnt, 1) AS units
    FROM tj.field_floor_displays d
    JOIN tj.field_floor_display_skus s ON s.display_id = d.id AND s.organization_id = p_org_id AND s.is_active = true
    JOIN LATERAL (SELECT COUNT(*) AS cnt FROM tj.field_floor_display_skus
                  WHERE display_id = d.id AND organization_id = p_org_id AND is_active = true) sku_count ON true
    WHERE d.organization_id = p_org_id AND d.is_active = true
    UNION ALL
    SELECT COALESCE(d.primary_category, 'other'), d.floor_units
    FROM tj.field_floor_displays d
    WHERE d.organization_id = p_org_id AND d.is_active = true
      AND NOT EXISTS (SELECT 1 FROM tj.field_floor_display_skus s
                      WHERE s.display_id = d.id AND s.organization_id = p_org_id AND s.is_active = true)
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'category', category, 'floor_units', total_units,
    'floor_pct', CASE WHEN total_floor_units > 0 THEN ROUND((total_units / total_floor_units * 100)::numeric, 1) ELSE 0 END
  ) ORDER BY total_units DESC), '[]'::jsonb)
  INTO cat_floor
  FROM (SELECT category, SUM(units) AS total_units FROM display_cat_units GROUP BY category) sub;

  SELECT COALESCE(SUM(COALESCE((p.value->>'price')::numeric, (p.value->>'amount')::numeric, 0)), 0)
  INTO total_sales
  FROM tj.crm_deals d, jsonb_array_elements(d.won_products) AS p(value)
  WHERE d.organization_id = p_org_id AND d.stage ILIKE '%won%'
    AND d.won_products IS NOT NULL AND jsonb_typeof(d.won_products) = 'array';

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'brand', brand, 'sales_amount', total_amt,
    'sales_pct', CASE WHEN total_sales > 0 THEN ROUND((total_amt / total_sales * 100)::numeric, 1) ELSE 0 END
  ) ORDER BY total_amt DESC), '[]'::jsonb)
  INTO brand_sales
  FROM (SELECT COALESCE(p.value->>'brand', p.value->>'brand_name', 'Unknown') AS brand,
               SUM(COALESCE((p.value->>'price')::numeric, (p.value->>'amount')::numeric, 0)) AS total_amt
        FROM tj.crm_deals d, jsonb_array_elements(d.won_products) AS p(value)
        WHERE d.organization_id = p_org_id AND d.stage ILIKE '%won%'
          AND d.won_products IS NOT NULL AND jsonb_typeof(d.won_products) = 'array'
        GROUP BY 1) sub;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'category', category, 'sales_amount', total_amt,
    'sales_pct', CASE WHEN total_sales > 0 THEN ROUND((total_amt / total_sales * 100)::numeric, 1) ELSE 0 END
  ) ORDER BY total_amt DESC), '[]'::jsonb)
  INTO cat_sales
  FROM (SELECT COALESCE(p.value->>'category', 'Other') AS category,
               SUM(COALESCE((p.value->>'price')::numeric, (p.value->>'amount')::numeric, 0)) AS total_amt
        FROM tj.crm_deals d, jsonb_array_elements(d.won_products) AS p(value)
        WHERE d.organization_id = p_org_id AND d.stage ILIKE '%won%'
          AND d.won_products IS NOT NULL AND jsonb_typeof(d.won_products) = 'array'
        GROUP BY 1) sub;

  result := jsonb_build_object(
    'total_floor_units', total_floor_units,
    'total_displays', total_displays,
    'total_skus', total_skus,
    'store_count', store_count,
    'total_sales', total_sales,
    'brand_floor', brand_floor,
    'brand_sales', brand_sales,
    'category_floor', cat_floor,
    'category_sales', cat_sales
  );
  RETURN result;
END;
$function$;

REVOKE ALL ON FUNCTION tj_private.get_floor_vs_sales(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj_private.get_floor_vs_sales(uuid) TO authenticated;
CREATE FUNCTION tj.get_floor_vs_sales(p_org_id uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.get_floor_vs_sales(p_org_id); $$;
REVOKE ALL ON FUNCTION tj.get_floor_vs_sales(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj.get_floor_vs_sales(uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
