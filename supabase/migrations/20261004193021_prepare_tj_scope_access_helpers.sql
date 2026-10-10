-- Destination-only permission helpers. No users, policies or data grants activated.
DO $guard$ BEGIN
  PERFORM 'tj.org_location_members'::regclass;
  PERFORM 'tj.org_locations'::regclass;
  PERFORM 'tj.field_clients'::regclass;
  PERFORM 'tj.field_manufacturer_users'::regclass;
  PERFORM 'tj.mfr_user_roles'::regclass;
  PERFORM 'tj.mdf_platform_users'::regclass;
  IF to_regprocedure('tj_private.current_source_user_id()') IS NULL THEN
    RAISE EXCEPTION 'Verified identity resolver is required';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname=current_user AND (rolsuper OR rolbypassrls)) THEN
    RAISE EXCEPTION 'Helper owner must bypass RLS to avoid policy recursion';
  END IF;
END $guard$;

CREATE OR REPLACE FUNCTION tj_private.is_org_manager(p_org uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
  SELECT p_org IS NOT NULL AND EXISTS(SELECT 1 FROM tj.organizations o WHERE o.id=p_org)
    AND EXISTS(SELECT 1 FROM tj.organization_members m WHERE m.organization_id=p_org
      AND m.user_id=(SELECT tj_private.current_source_user_id()) AND m.status='active'
      AND m.role IN ('sales_manager','store_manager','admin','owner'));
$function$;

CREATE OR REPLACE FUNCTION tj_private.is_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
  SELECT EXISTS(SELECT 1 FROM tj.mfr_user_roles r
    WHERE r.user_id=(SELECT tj_private.current_source_user_id()) AND r.is_admin IS TRUE);
$function$;

CREATE OR REPLACE FUNCTION tj_private.is_field_client_member(p_client_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
  SELECT EXISTS(SELECT 1 FROM tj.field_clients c
    JOIN tj.organizations o ON o.id=c.organization_id
    WHERE c.id=p_client_id AND (
      EXISTS(SELECT 1 FROM tj.organization_members m WHERE m.organization_id=c.organization_id
        AND m.user_id=(SELECT tj_private.current_source_user_id()) AND m.status='active')
      OR EXISTS(SELECT 1 FROM tj.field_manufacturer_users m WHERE m.client_id=c.id
        AND m.user_id=(SELECT tj_private.current_source_user_id()) AND m.status='active')));
$function$;

CREATE OR REPLACE FUNCTION tj_private.aiq_scope_allows(p_org uuid,p_owner uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE v_uid uuid:=tj_private.current_source_user_id(); v_me tj.organization_members%ROWTYPE;
BEGIN
  IF v_uid IS NULL OR NOT tj_private.is_org_member(p_org) THEN RETURN false; END IF;
  IF p_owner IS NULL OR p_owner=v_uid OR tj_private.is_platform_admin() THEN RETURN true; END IF;
  SELECT * INTO v_me FROM tj.organization_members
    WHERE organization_id=p_org AND user_id=v_uid AND status='active' LIMIT 1;
  IF v_me.role IN ('owner','admin') THEN RETURN true; END IF;
  CASE coalesce(v_me.visibility_scope,'own')
    WHEN 'all' THEN RETURN true;
    WHEN 'store' THEN RETURN EXISTS(
      SELECT 1 FROM tj.org_location_members a
      JOIN tj.org_location_members b ON b.location_id=a.location_id
      JOIN tj.org_locations l ON l.id=a.location_id AND l.organization_id=p_org
      WHERE a.organization_id=p_org AND b.organization_id=p_org
        AND a.user_id=v_uid AND b.user_id=p_owner);
    WHEN 'team' THEN RETURN EXISTS(
      WITH RECURSIVE subtree(id) AS (
        SELECT v_me.id
        UNION -- Deduplicate visited IDs: cycles cannot make recursion unbounded.
        SELECT m.id FROM tj.organization_members m JOIN subtree s ON m.manager_id=s.id
          WHERE m.organization_id=p_org
      )
      SELECT 1 FROM tj.organization_members m JOIN subtree s ON s.id=m.id
        WHERE m.organization_id=p_org AND m.user_id=p_owner);
    ELSE RETURN false;
  END CASE;
END;
$function$;

CREATE OR REPLACE FUNCTION tj_private.aiq_store_allows(p_org uuid,p_store uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE v_uid uuid:=tj_private.current_source_user_id(); v_me tj.organization_members%ROWTYPE;
BEGIN
  IF v_uid IS NULL OR NOT tj_private.is_org_member(p_org) THEN RETURN false; END IF;
  IF p_store IS NULL OR tj_private.is_platform_admin() THEN RETURN true; END IF;
  SELECT * INTO v_me FROM tj.organization_members
    WHERE organization_id=p_org AND user_id=v_uid AND status='active' LIMIT 1;
  IF v_me.role IN ('owner','admin') OR coalesce(v_me.visibility_scope,'own')='all' THEN RETURN true; END IF;
  RETURN EXISTS(SELECT 1 FROM tj.org_location_members m
    JOIN tj.org_locations l ON l.id=m.location_id AND l.organization_id=p_org
    WHERE m.organization_id=p_org AND m.user_id=v_uid AND (l.id=p_store OR l.iq_store_id=p_store));
END;
$function$;

-- Lookup MDF access through the verified source identity, never JWT email alone.
CREATE OR REPLACE FUNCTION tj_private.mdf_get_user_role()
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
  SELECT CASE WHEN count(*)=1 THEN min(nullif(btrim(m.role),'')) ELSE NULL END
  FROM tj.mdf_platform_users m JOIN tj.source_auth_users u
    ON u.id=(SELECT tj_private.current_source_user_id())
  WHERE m.is_active IS TRUE AND nullif(btrim(u.email),'') IS NOT NULL
    AND lower(btrim(m.email))=lower(btrim(u.email))
    AND (m.org_id IS NULL OR tj_private.is_org_member(m.org_id));
$function$;
CREATE OR REPLACE FUNCTION tj_private.mdf_has_access()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $function$ SELECT tj_private.mdf_get_user_role() IS NOT NULL; $function$;

CREATE OR REPLACE FUNCTION tj.is_org_manager(p_org uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $function$ SELECT tj_private.is_org_manager(p_org); $function$;
CREATE OR REPLACE FUNCTION tj.is_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $function$ SELECT tj_private.is_admin(); $function$;
CREATE OR REPLACE FUNCTION tj.is_field_client_member(p_client_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $function$ SELECT tj_private.is_field_client_member(p_client_id); $function$;
CREATE OR REPLACE FUNCTION tj.aiq_scope_allows(p_org uuid,p_owner uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $function$ SELECT tj_private.aiq_scope_allows(p_org,p_owner); $function$;
CREATE OR REPLACE FUNCTION tj.aiq_store_allows(p_org uuid,p_store uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $function$ SELECT tj_private.aiq_store_allows(p_org,p_store); $function$;
CREATE OR REPLACE FUNCTION tj.mdf_get_user_role()
RETURNS text LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $function$ SELECT tj_private.mdf_get_user_role(); $function$;
CREATE OR REPLACE FUNCTION tj.mdf_has_access()
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $function$ SELECT tj_private.mdf_has_access(); $function$;

REVOKE ALL ON FUNCTION tj_private.is_org_manager(uuid),tj_private.is_admin(),
  tj_private.is_field_client_member(uuid),tj_private.aiq_scope_allows(uuid,uuid),
  tj_private.aiq_store_allows(uuid,uuid),tj_private.mdf_get_user_role(),tj_private.mdf_has_access(),
  tj.is_org_manager(uuid),tj.is_admin(),tj.is_field_client_member(uuid),
  tj.aiq_scope_allows(uuid,uuid),tj.aiq_store_allows(uuid,uuid),tj.mdf_get_user_role(),tj.mdf_has_access()
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION tj_private.is_org_manager(uuid),tj_private.is_admin(),
  tj_private.is_field_client_member(uuid),tj_private.aiq_scope_allows(uuid,uuid),
  tj_private.aiq_store_allows(uuid,uuid),tj_private.mdf_get_user_role(),tj_private.mdf_has_access(),
  tj.is_org_manager(uuid),tj.is_admin(),tj.is_field_client_member(uuid),
  tj.aiq_scope_allows(uuid,uuid),tj.aiq_store_allows(uuid,uuid),tj.mdf_get_user_role(),tj.mdf_has_access()
  TO authenticated;
