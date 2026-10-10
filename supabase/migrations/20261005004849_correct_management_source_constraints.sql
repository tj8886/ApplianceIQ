-- Align restored source constraints with source UI/runtime contracts.
ALTER TABLE tj.ai_manager_briefs DROP CONSTRAINT ai_manager_briefs_brief_type_check;
ALTER TABLE tj.ai_manager_briefs ADD CONSTRAINT ai_manager_briefs_brief_type_check CHECK (brief_type IN ('daily','weekly','exception','morning','end_of_day'));
ALTER TABLE tj.speciq_package_events DROP CONSTRAINT speciq_package_events_event_type_check;
ALTER TABLE tj.speciq_package_events ADD CONSTRAINT speciq_package_events_event_type_check CHECK (event_type IN ('created','sent','email_delivered','link_opened','page_viewed','product_clicked','downloaded','pricing_viewed','revision_requested','customer_response','comparison_winner_added'));
CREATE OR REPLACE FUNCTION tj_private.evaluate_sla_rules(p_org_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_rule RECORD;
  v_contact RECORD;
  v_deal RECORD;
  v_events_created integer := 0;
  v_result jsonb := '[]'::jsonb;
BEGIN
  PERFORM tj_private.assert_runtime_org(p_org_id);
  IF NOT tj.is_org_admin(p_org_id) THEN RAISE EXCEPTION 'admin_required' USING ERRCODE='42501'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('evaluate_sla_rules:'||p_org_id::text,0));

  -- Loop through active SLA rules
  FOR v_rule IN 
    SELECT * FROM crm_sla_rules 
    WHERE is_active = true
    AND (p_org_id IS NULL OR organization_id = p_org_id)
    ORDER BY days_threshold ASC
  LOOP
    -- Check contacts with no recent communication
    FOR v_contact IN
      SELECT c.id, c.organization_id, c.first_name, c.last_name, 
             (SELECT p.user_id FROM tj.profiles p JOIN tj.organization_members m ON m.user_id=p.user_id AND m.organization_id=c.organization_id AND m.status='active' WHERE p.id=c.assigned_salesperson_id LIMIT 1) AS assigned_salesperson_id,
             EXTRACT(DAY FROM now() - COALESCE(c.last_communication_at, c.created_at))::integer AS days_idle
      FROM contacts c
      WHERE c.organization_id = v_rule.organization_id
        AND c.lifecycle_stage::text NOT IN ('churn', 'do_not_contact', 'duplicate')
        AND c.relationship_status = 'active'
        AND EXTRACT(DAY FROM now() - COALESCE(c.last_communication_at, c.created_at))::integer >= v_rule.days_threshold
        -- Don't create duplicate events for same contact+rule within 24h
        AND NOT EXISTS (
          SELECT 1 FROM crm_sla_events e
          WHERE e.contact_id = c.id 
            AND e.rule_id = v_rule.id
            AND e.resolved_at IS NULL
            AND e.created_at > now() - interval '24 hours'
        )
    LOOP
      INSERT INTO crm_sla_events (
        organization_id, contact_id, rule_id, event_type,
        days_since_contact, assigned_to
      ) VALUES (
        v_contact.organization_id, v_contact.id, v_rule.id, v_rule.action,
        v_contact.days_idle, v_contact.assigned_salesperson_id
      );
      v_events_created := v_events_created + 1;
    END LOOP;

    -- Check deals with no recent activity
    FOR v_deal IN
      SELECT d.id, d.organization_id, d.title, (SELECT p.user_id FROM tj.profiles p JOIN tj.organization_members m ON m.user_id=p.user_id AND m.organization_id=d.organization_id AND m.status='active' WHERE p.user_id=d.owner_user_id LIMIT 1) AS owner_user_id,
             EXTRACT(DAY FROM now() - COALESCE(d.last_contact_at, d.created_at))::integer AS days_idle
      FROM crm_deals d
      WHERE d.organization_id = v_rule.organization_id
        AND d.is_archived IS NOT TRUE
        AND d.stage NOT IN ('won', 'lost', 'closed')
        AND EXTRACT(DAY FROM now() - COALESCE(d.last_contact_at, d.created_at))::integer >= v_rule.days_threshold
        AND NOT EXISTS (
          SELECT 1 FROM crm_sla_events e
          WHERE e.deal_id = d.id
            AND e.rule_id = v_rule.id
            AND e.resolved_at IS NULL
            AND e.created_at > now() - interval '24 hours'
        )
    LOOP
      INSERT INTO crm_sla_events (
        organization_id, deal_id, rule_id, event_type,
        days_since_contact, assigned_to
      ) VALUES (
        v_deal.organization_id, v_deal.id, v_rule.id, v_rule.action,
        v_deal.days_idle, v_deal.owner_user_id
      );
      v_events_created := v_events_created + 1;
    END LOOP;
  END LOOP;

  RETURN jsonb_build_object('events_created', v_events_created);
END;
$function$;
