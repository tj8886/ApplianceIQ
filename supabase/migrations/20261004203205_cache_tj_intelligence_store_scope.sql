-- Equivalent store authorization as sets, avoiding repeated identity lookups per event.
CREATE FUNCTION tj_private.unrestricted_store_organizations() RETURNS SETOF uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $$ DECLARE uid uuid:=tj_private.current_source_user_id(); BEGIN
 IF uid IS NULL THEN RETURN; END IF;
 IF tj_private.is_platform_admin() THEN RETURN QUERY SELECT o.id FROM tj.organizations o; RETURN; END IF;
 RETURN QUERY SELECT DISTINCT m.organization_id FROM tj.organization_members m
 JOIN tj.organizations o ON o.id=m.organization_id
 WHERE m.user_id=uid AND m.status='active'
 AND (m.role IN ('owner','admin') OR coalesce(m.visibility_scope,'own')='all');
END $$;
CREATE FUNCTION tj_private.allowed_store_pairs() RETURNS TABLE(organization_id uuid,store_id uuid)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $$ DECLARE uid uuid:=tj_private.current_source_user_id(); BEGIN
 IF uid IS NULL THEN RETURN; END IF;
 RETURN QUERY SELECT DISTINCT lm.organization_id,l.id FROM tj.org_location_members lm
 JOIN tj.org_locations l ON l.id=lm.location_id AND l.organization_id=lm.organization_id
 JOIN tj.organization_members m ON m.organization_id=lm.organization_id AND m.user_id=uid AND m.status='active'
 WHERE lm.user_id=uid
 UNION SELECT DISTINCT lm.organization_id,l.iq_store_id FROM tj.org_location_members lm
 JOIN tj.org_locations l ON l.id=lm.location_id AND l.organization_id=lm.organization_id
 JOIN tj.organization_members m ON m.organization_id=lm.organization_id AND m.user_id=uid AND m.status='active'
 WHERE lm.user_id=uid AND l.iq_store_id IS NOT NULL;
END $$;
REVOKE ALL ON FUNCTION tj_private.unrestricted_store_organizations(),tj_private.allowed_store_pairs() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj_private.unrestricted_store_organizations(),tj_private.allowed_store_pairs() TO authenticated;
ALTER POLICY consolidation_intelligence_store_scope ON tj.intelligence_events
USING (store_id IS NULL OR organization_id IN (SELECT tj_private.unrestricted_store_organizations())
 OR (organization_id,store_id) IN (SELECT s.organization_id,s.store_id FROM tj_private.allowed_store_pairs() s));
NOTIFY pgrst,'reload schema';
