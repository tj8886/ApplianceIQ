-- Narrow Data API adapter; caller JWT remains authoritative.
CREATE FUNCTION tj_private.edge_floor_recommendation_data(p_org_id uuid,p_store_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM tj_private.assert_runtime_org(p_org_id);
 IF p_store_id IS NULL THEN
  IF NOT EXISTS(SELECT 1 FROM tj_private.unrestricted_store_organizations() AS o(organization_id) WHERE o.organization_id=p_org_id) THEN
   RAISE EXCEPTION 'store_scope_required' USING ERRCODE='42501';
  END IF;
 ELSE
  IF NOT tj.aiq_store_allows(p_org_id,p_store_id) OR NOT EXISTS(
   SELECT 1 FROM tj.org_locations WHERE id=p_store_id AND organization_id=p_org_id AND is_active
  ) THEN RAISE EXCEPTION 'store_access_denied' USING ERRCODE='42501'; END IF;
 END IF;
 RETURN tj_private.get_floor_recommendation_data(p_org_id,p_store_id);
END $$;
REVOKE ALL ON FUNCTION tj_private.edge_floor_recommendation_data(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj_private.edge_floor_recommendation_data(uuid,uuid) TO authenticated;
CREATE FUNCTION public.tj_floor_recommendation_data(p_org_id uuid,p_store_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
 SELECT tj_private.edge_floor_recommendation_data(p_org_id,p_store_id);
$$;
REVOKE ALL ON FUNCTION public.tj_floor_recommendation_data(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_floor_recommendation_data(uuid,uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
