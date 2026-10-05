-- Destination-only preparation. Apply to the isolated US rehearsal first.
-- No identity is approved/activated, and no table access policy is enabled here.
DO $guard$
BEGIN
  PERFORM 'tj.source_user_identity_map'::regclass;
  PERFORM 'tj.source_auth_users'::regclass;
  PERFORM 'tj.organization_members'::regclass;
  PERFORM 'tj.organizations'::regclass;
  PERFORM 'tj.platform_admins'::regclass;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname=current_user AND (rolsuper OR rolbypassrls)) THEN
    RAISE EXCEPTION 'Access helper owner must bypass RLS to avoid membership-policy recursion';
  END IF;
END $guard$;

CREATE SCHEMA IF NOT EXISTS tj_private;
REVOKE ALL ON SCHEMA tj_private FROM PUBLIC, anon;

CREATE OR REPLACE FUNCTION tj_private.current_source_user_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
  SELECT CASE WHEN count(*)=1 THEN min(m.source_user_id::text)::uuid ELSE NULL END
  FROM tj.source_user_identity_map m
  JOIN tj.source_auth_users s ON s.id=m.source_user_id
  JOIN auth.users u ON u.id=m.target_user_id
  WHERE m.target_user_id=(SELECT auth.uid())
    AND m.identity_verified IS TRUE
    AND m.mapping_status IN ('approved_map','approved_create','approved_invite')
    AND m.approved_at IS NOT NULL AND nullif(btrim(m.approved_by),'') IS NOT NULL
    AND m.activation_status='activated' AND m.activated_at IS NOT NULL
    AND s.deleted_at IS NULL AND u.deleted_at IS NULL
    AND (s.banned_until IS NULL OR s.banned_until<=now())
    AND (u.banned_until IS NULL OR u.banned_until<=now())
    AND NOT coalesce(s.is_anonymous,false) AND NOT coalesce(u.is_anonymous,false);
$function$;
REVOKE ALL ON FUNCTION tj_private.current_source_user_id() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION tj_private.is_platform_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
  SELECT EXISTS (SELECT 1 FROM tj.platform_admins a
    WHERE a.user_id=(SELECT tj_private.current_source_user_id()));
$function$;

CREATE OR REPLACE FUNCTION tj_private.is_org_member(p_org uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
  SELECT p_org IS NOT NULL AND EXISTS(SELECT 1 FROM tj.organizations o WHERE o.id=p_org)
    AND (tj_private.is_platform_admin() OR EXISTS (
      SELECT 1 FROM tj.organization_members m
      WHERE m.organization_id=p_org AND m.user_id=(SELECT tj_private.current_source_user_id())
        AND m.status='active'));
$function$;

CREATE OR REPLACE FUNCTION tj_private.is_org_admin(p_org uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
  SELECT p_org IS NOT NULL AND EXISTS(SELECT 1 FROM tj.organizations o WHERE o.id=p_org)
    AND (tj_private.is_platform_admin() OR EXISTS (
      SELECT 1 FROM tj.organization_members m
      WHERE m.organization_id=p_org AND m.user_id=(SELECT tj_private.current_source_user_id())
        AND m.status='active' AND m.role IN ('admin','owner')));
$function$;

CREATE OR REPLACE FUNCTION tj_private.my_org_ids()
RETURNS SETOF uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
  SELECT DISTINCT m.organization_id FROM tj.organization_members m
  WHERE m.user_id=(SELECT tj_private.current_source_user_id()) AND m.status='active';
$function$;

-- Callable adapters remain invoker functions; privileged logic stays private.
CREATE OR REPLACE FUNCTION tj.is_platform_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $function$ SELECT tj_private.is_platform_admin(); $function$;
CREATE OR REPLACE FUNCTION tj.is_org_member(p_org uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $function$ SELECT tj_private.is_org_member(p_org); $function$;
CREATE OR REPLACE FUNCTION tj.is_org_admin(p_org uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $function$ SELECT tj_private.is_org_admin(p_org); $function$;
CREATE OR REPLACE FUNCTION tj.my_org_ids()
RETURNS SETOF uuid LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $function$ SELECT * FROM tj_private.my_org_ids(); $function$;

REVOKE ALL ON FUNCTION tj_private.is_platform_admin(), tj_private.is_org_member(uuid),
  tj_private.is_org_admin(uuid), tj_private.my_org_ids(), tj.is_platform_admin(),
  tj.is_org_member(uuid), tj.is_org_admin(uuid), tj.my_org_ids() FROM PUBLIC, anon;
GRANT USAGE ON SCHEMA tj, tj_private TO authenticated;
GRANT EXECUTE ON FUNCTION tj_private.is_platform_admin(), tj_private.is_org_member(uuid),
  tj_private.is_org_admin(uuid), tj_private.my_org_ids(), tj.is_platform_admin(),
  tj.is_org_member(uuid), tj.is_org_admin(uuid), tj.my_org_ids() TO authenticated;
