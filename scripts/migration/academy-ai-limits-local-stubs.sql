-- Minimal stand-ins for the production objects the Academy AI limits migration
-- depends on. Load only into an empty, throwaway database (see
-- run-academy-ai-limits-sql.sh); never into Supabase. Helper bodies match the
-- production definitions of tj_private.handoff_source_user,
-- current_source_user_id, is_platform_admin, is_org_member and is_org_admin.
DO $$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
END $$;
CREATE SCHEMA auth; CREATE SCHEMA tj; CREATE SCHEMA tj_private;
GRANT USAGE ON SCHEMA auth,tj,tj_private TO authenticated,service_role;
CREATE TABLE auth.users(id uuid PRIMARY KEY,deleted_at timestamptz,banned_until timestamptz,is_anonymous boolean DEFAULT false,email_confirmed_at timestamptz DEFAULT now());
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
GRANT EXECUTE ON FUNCTION auth.uid() TO authenticated,service_role;
CREATE TABLE tj.source_auth_users(id uuid PRIMARY KEY,deleted_at timestamptz,banned_until timestamptz,is_anonymous boolean DEFAULT false);
CREATE TABLE tj.source_user_identity_map(source_user_id uuid PRIMARY KEY,target_user_id uuid,identity_verified boolean,mapping_status text,approved_at timestamptz,approved_by text,activation_status text,activated_at timestamptz);
CREATE TABLE tj.organizations(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),name text,slug text,status text DEFAULT 'active',deleted_at timestamptz);
CREATE TABLE tj.organization_members(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid,user_id uuid,role text,status text,created_at timestamptz DEFAULT now());
CREATE TABLE tj.platform_admins(user_id uuid PRIMARY KEY);
CREATE TABLE tj.org_app_entitlements(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid,app_key text,tier text,seats_included integer,seats_used integer DEFAULT 0,status text,trial_ends_at timestamptz);
CREATE TABLE tj_private.company_admin_audit(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,actor_source_user_id uuid NOT NULL,action text NOT NULL,record_id uuid,before_data jsonb,after_data jsonb,created_at timestamptz NOT NULL DEFAULT now());
ALTER TABLE tj_private.company_admin_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj_private.company_admin_audit FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION tj_private.handoff_source_user(p_target_user_id uuid) RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$ SELECT CASE WHEN count(*)=1 THEN min(m.source_user_id::text)::uuid ELSE NULL END
FROM tj.source_user_identity_map m JOIN tj.source_auth_users s ON s.id=m.source_user_id
JOIN auth.users u ON u.id=m.target_user_id
WHERE m.target_user_id=p_target_user_id AND m.identity_verified IS TRUE
AND m.mapping_status IN ('approved_map','approved_create','approved_invite')
AND m.approved_at IS NOT NULL AND nullif(btrim(m.approved_by),'') IS NOT NULL
AND m.activation_status='activated' AND m.activated_at IS NOT NULL
AND s.deleted_at IS NULL AND u.deleted_at IS NULL AND u.email_confirmed_at IS NOT NULL
AND (s.banned_until IS NULL OR s.banned_until<=now()) AND (u.banned_until IS NULL OR u.banned_until<=now())
AND NOT coalesce(s.is_anonymous,false) AND NOT coalesce(u.is_anonymous,false); $$;
CREATE FUNCTION tj_private.current_source_user_id() RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$ SELECT tj_private.handoff_source_user((SELECT auth.uid())) $$;
CREATE FUNCTION tj_private.is_platform_admin() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$ SELECT EXISTS (SELECT 1 FROM tj.platform_admins a WHERE a.user_id=(SELECT tj_private.current_source_user_id())); $$;
CREATE FUNCTION tj_private.is_org_member(p_org uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT p_org IS NOT NULL AND EXISTS(SELECT 1 FROM tj.organizations o WHERE o.id=p_org)
    AND (tj_private.is_platform_admin() OR EXISTS (SELECT 1 FROM tj.organization_members m
      WHERE m.organization_id=p_org AND m.user_id=(SELECT tj_private.current_source_user_id()) AND m.status='active')); $$;
CREATE FUNCTION tj_private.is_org_admin(p_org uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT p_org IS NOT NULL AND EXISTS(SELECT 1 FROM tj.organizations o WHERE o.id=p_org)
    AND (tj_private.is_platform_admin() OR EXISTS (SELECT 1 FROM tj.organization_members m
      WHERE m.organization_id=p_org AND m.user_id=(SELECT tj_private.current_source_user_id()) AND m.status='active' AND m.role IN ('admin','owner'))); $$;

-- Five activated identities: four company users and one platform admin.
INSERT INTO auth.users(id) SELECT ('00000000-0000-4000-8000-00000000010'||n)::uuid FROM generate_series(1,5) n;
INSERT INTO tj.source_auth_users(id) SELECT ('00000000-0000-4000-8000-00000000020'||n)::uuid FROM generate_series(1,5) n;
INSERT INTO tj.source_user_identity_map SELECT ('00000000-0000-4000-8000-00000000020'||n)::uuid,('00000000-0000-4000-8000-00000000010'||n)::uuid,true,'approved_map',now(),'fixture','activated',now() FROM generate_series(1,5) n;
INSERT INTO tj.platform_admins VALUES('00000000-0000-4000-8000-000000000205');
