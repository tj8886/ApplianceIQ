-- CRM contact workflows; private privileged implementations and authenticated adapters.
CREATE OR REPLACE FUNCTION tj_private.crm_reassign_rep_deals(p_org_id uuid, p_from_user_id uuid, p_to_user_id uuid, p_reason text DEFAULT 'rep_deactivated'::text, p_actor_id uuid DEFAULT NULL::uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_count INT;
BEGIN

  IF p_org_id IS NULL OR NOT tj.is_org_admin(p_org_id)
     OR NOT EXISTS(SELECT 1 FROM tj.organizations WHERE id=p_org_id AND deleted_at IS NULL) THEN
    RAISE EXCEPTION 'access_denied' USING ERRCODE='42501';
  END IF;

  IF p_from_user_id IS NULL OR p_to_user_id IS NULL OR p_from_user_id=p_to_user_id THEN RAISE EXCEPTION 'invalid_reassignment'; END IF;
  IF p_actor_id IS NOT NULL AND p_actor_id<>auth.uid() AND p_actor_id<>tj_private.current_source_user_id() THEN RAISE EXCEPTION 'invalid_actor'; END IF;
  PERFORM 1 FROM tj.organization_members WHERE organization_id=p_org_id AND user_id=p_from_user_id FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'source_not_in_organization'; END IF;
  PERFORM 1 FROM tj.organization_members WHERE organization_id=p_org_id AND user_id=p_to_user_id AND status='active' FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'recipient_not_active_in_organization'; END IF;
  IF p_reason IS NULL OR length(trim(p_reason))=0 OR length(p_reason)>1000 THEN RAISE EXCEPTION 'invalid_reason'; END IF;
  -- Reassign all non-terminal open deals
  WITH reassigned AS (
    UPDATE tj.crm_deals
    SET owner_user_id = p_to_user_id, updated_at = now()
    WHERE organization_id = p_org_id
      AND owner_user_id = p_from_user_id
      AND deleted_at IS NULL
      AND closed_at IS NULL AND stage NOT IN ('Closed Won', 'Closed Lost', 'VIP')
    RETURNING id
  ),
  logged AS (
    INSERT INTO tj.crm_deal_reassignments (organization_id, deal_id, from_user_id, to_user_id, reason, reassigned_by)
    SELECT p_org_id, id, p_from_user_id, p_to_user_id, p_reason, tj_private.current_source_user_id()
    FROM reassigned
  )
  SELECT count(*) INTO v_count FROM reassigned;

  RETURN v_count;
END $function$;
REVOKE ALL ON FUNCTION tj_private.crm_reassign_rep_deals(uuid,uuid,uuid,text,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj_private.crm_reassign_rep_deals(uuid,uuid,uuid,text,uuid) TO authenticated;
CREATE FUNCTION tj.crm_reassign_rep_deals(p_org_id uuid, p_from_user_id uuid, p_to_user_id uuid, p_reason text DEFAULT 'rep_deactivated'::text, p_actor_id uuid DEFAULT NULL::uuid) RETURNS integer LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.crm_reassign_rep_deals(p_org_id,p_from_user_id,p_to_user_id,p_reason,p_actor_id); $$;
REVOKE ALL ON FUNCTION tj.crm_reassign_rep_deals(uuid,uuid,uuid,text,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj.crm_reassign_rep_deals(uuid,uuid,uuid,text,uuid) TO authenticated;
CREATE OR REPLACE FUNCTION tj_private.find_duplicate_contacts(p_org_id uuid)
 RETURNS TABLE(contact_id_1 uuid, contact_id_2 uuid, match_type text, match_value text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN

  IF p_org_id IS NULL OR NOT tj.is_org_member(p_org_id)
     OR NOT EXISTS(SELECT 1 FROM tj.organizations WHERE id=p_org_id AND deleted_at IS NULL) THEN
    RAISE EXCEPTION 'access_denied' USING ERRCODE='42501';
  END IF;
  -- Email matches
  RETURN QUERY
  SELECT c1.id, c2.id, 'email'::text, c1.email
  FROM tj.contacts c1
  JOIN tj.contacts c2 ON c1.email = c2.email AND c1.id < c2.id
  WHERE c1.organization_id = p_org_id AND c2.organization_id = p_org_id AND c1.deleted_at IS NULL AND c2.deleted_at IS NULL
    AND c1.email IS NOT NULL AND c1.email != '';

  -- Phone matches
  RETURN QUERY
  SELECT c1.id, c2.id, 'phone'::text, c1.phone
  FROM tj.contacts c1
  JOIN tj.contacts c2 ON c1.phone = c2.phone AND c1.id < c2.id
  WHERE c1.organization_id = p_org_id AND c2.organization_id = p_org_id AND c1.deleted_at IS NULL AND c2.deleted_at IS NULL
    AND c1.phone IS NOT NULL AND c1.phone != '';

  -- Name matches (first + last)
  RETURN QUERY
  SELECT c1.id, c2.id, 'name'::text, c1.first_name || ' ' || COALESCE(c1.last_name, '')
  FROM tj.contacts c1
  JOIN tj.contacts c2 ON lower(c1.first_name) = lower(c2.first_name)
    AND lower(COALESCE(c1.last_name,'')) = lower(COALESCE(c2.last_name,''))
    AND c1.id < c2.id
  WHERE c1.organization_id = p_org_id AND c2.organization_id = p_org_id AND c1.deleted_at IS NULL AND c2.deleted_at IS NULL
    AND c1.first_name IS NOT NULL AND c1.last_name IS NOT NULL;
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.find_duplicate_contacts(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj_private.find_duplicate_contacts(uuid) TO authenticated;
CREATE FUNCTION tj.find_duplicate_contacts(p_org_id uuid) RETURNS TABLE(contact_id_1 uuid, contact_id_2 uuid, match_type text, match_value text) LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM tj_private.find_duplicate_contacts(p_org_id); $$;
REVOKE ALL ON FUNCTION tj.find_duplicate_contacts(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj.find_duplicate_contacts(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION tj_private.get_anniversary_outreach(p_org_id uuid, p_days_ahead integer DEFAULT 14)
 RETURNS TABLE(deal_id uuid, contact_id uuid, contact_name text, contact_email text, deal_title text, purchase_date date, anniversary_number integer, days_until integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN

  IF p_org_id IS NULL OR NOT tj.is_org_member(p_org_id)
     OR NOT EXISTS(SELECT 1 FROM tj.organizations WHERE id=p_org_id AND deleted_at IS NULL) THEN
    RAISE EXCEPTION 'access_denied' USING ERRCODE='42501';
  END IF;

  IF p_days_ahead IS NULL OR p_days_ahead<0 OR p_days_ahead>366 THEN RAISE EXCEPTION 'invalid_days_ahead'; END IF;
  RETURN QUERY
  SELECT d.id, d.contact_id,
    (c.first_name || ' ' || COALESCE(c.last_name, ''))::text,
    c.email,
    d.title,
    d.purchase_date,
    EXTRACT(YEAR FROM age(CURRENT_DATE, d.purchase_date))::integer + 1,
    (
      (d.purchase_date + ((EXTRACT(YEAR FROM age(CURRENT_DATE, d.purchase_date))::integer + 1) || ' years')::interval)::date
      - CURRENT_DATE
    )::integer
  FROM tj.crm_deals d
  JOIN tj.contacts c ON c.id = d.contact_id AND c.organization_id=p_org_id AND c.deleted_at IS NULL
  WHERE d.organization_id = p_org_id AND d.deleted_at IS NULL AND tj.aiq_scope_allows(p_org_id,d.owner_user_id)
    AND d.purchase_date IS NOT NULL
    AND d.contact_id IS NOT NULL
    AND (d.stage IS NULL OR lower(d.stage) LIKE '%won%')
    AND (
      (d.purchase_date + ((EXTRACT(YEAR FROM age(CURRENT_DATE, d.purchase_date))::integer + 1) || ' years')::interval)::date
      - CURRENT_DATE
    ) BETWEEN 0 AND p_days_ahead;
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.get_anniversary_outreach(uuid,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj_private.get_anniversary_outreach(uuid,integer) TO authenticated;
CREATE FUNCTION tj.get_anniversary_outreach(p_org_id uuid, p_days_ahead integer DEFAULT 14) RETURNS TABLE(deal_id uuid, contact_id uuid, contact_name text, contact_email text, deal_title text, purchase_date date, anniversary_number integer, days_until integer) LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM tj_private.get_anniversary_outreach(p_org_id,p_days_ahead); $$;
REVOKE ALL ON FUNCTION tj.get_anniversary_outreach(uuid,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj.get_anniversary_outreach(uuid,integer) TO authenticated;
CREATE OR REPLACE FUNCTION tj_private.score_leads(p_org_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  scored integer := 0;
BEGIN

  IF p_org_id IS NULL OR NOT tj.is_org_member(p_org_id)
     OR NOT EXISTS(SELECT 1 FROM tj.organizations WHERE id=p_org_id AND deleted_at IS NULL) THEN
    RAISE EXCEPTION 'access_denied' USING ERRCODE='42501';
  END IF;
  UPDATE tj.contacts c SET
    lead_score = LEAST(100, GREATEST(0,
      -- Temperature: hot=30, warm=15, cold=0
      CASE c.temperature WHEN 'hot' THEN 30 WHEN 'warm' THEN 15 ELSE 0 END
      -- Recency: contacted in last 3 days=20, 7 days=15, 14 days=10, 30 days=5
      + CASE
        WHEN c.last_communication_at > now() - interval '3 days' THEN 20
        WHEN c.last_communication_at > now() - interval '7 days' THEN 15
        WHEN c.last_communication_at > now() - interval '14 days' THEN 10
        WHEN c.last_communication_at > now() - interval '30 days' THEN 5
        ELSE 0 END
      -- Has active deal: +15, deal value > 5000: +5
      + CASE WHEN EXISTS (SELECT 1 FROM tj.crm_deals d WHERE d.contact_id = c.id AND d.organization_id=p_org_id AND d.deleted_at IS NULL AND d.closed_at IS NULL) THEN 15 ELSE 0 END
      + CASE WHEN EXISTS (SELECT 1 FROM tj.crm_deals d WHERE d.contact_id = c.id AND d.organization_id=p_org_id AND d.deleted_at IS NULL AND d.closed_at IS NULL AND d.value_amount > 5000) THEN 5 ELSE 0 END
      -- Has email: +5
      + CASE WHEN c.email IS NOT NULL AND c.email != '' THEN 5 ELSE 0 END
      -- Has phone: +5
      + CASE WHEN c.phone IS NOT NULL AND c.phone != '' THEN 5 ELSE 0 END
      -- Decision maker: +10
      + CASE WHEN c.decision_making_role IN ('decision_maker','primary_buyer','budget_holder') THEN 10 ELSE 0 END
      -- In buying group: +5
      + CASE WHEN EXISTS (SELECT 1 FROM tj.crm_buying_group_members bgm JOIN tj.crm_buying_groups bg ON bg.id=bgm.buying_group_id AND bg.organization_id=p_org_id WHERE bgm.contact_id = c.id) THEN 5 ELSE 0 END
      -- IQ Lead: +5
      + CASE WHEN c.is_iq_lead THEN 5 ELSE 0 END
    )),
    lead_score_updated_at = now(), updated_at = now()
  WHERE c.organization_id = p_org_id AND c.deleted_at IS NULL;
  GET DIAGNOSTICS scored = ROW_COUNT;
  RETURN jsonb_build_object('scored', scored);
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.score_leads(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj_private.score_leads(uuid) TO authenticated;
CREATE FUNCTION tj.score_leads(p_org_id uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.score_leads(p_org_id); $$;
REVOKE ALL ON FUNCTION tj.score_leads(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj.score_leads(uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
