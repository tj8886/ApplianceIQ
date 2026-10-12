-- Narrow administration APIs. No direct client table-write grants.
CREATE TABLE tj_private.company_admin_audit (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id uuid NOT NULL,
 actor_source_user_id uuid NOT NULL, action text NOT NULL, record_id uuid,
 before_data jsonb, after_data jsonb, created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE tj_private.company_admin_audit ENABLE ROW LEVEL SECURITY;
CREATE INDEX company_admin_audit_org_created_idx ON tj_private.company_admin_audit(organization_id,created_at);
REVOKE ALL ON tj_private.company_admin_audit FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION tj_private.company_admin(p_organization_id uuid DEFAULT NULL,p_action text DEFAULT 'bootstrap',p_payload jsonb DEFAULT '{}')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE uid uuid:=tj_private.current_source_user_id(); super boolean; actor_role text;
 row_id uuid; target_org uuid:=p_organization_id; allowed text[]; before_row jsonb; after_row jsonb;
 loc tj.org_locations; position tj.org_roles; member tj.organization_members;
 entitlement tj.org_app_entitlements; company tj.organizations;
 target_user uuid; primary_location uuid; location_ids uuid[]; manager uuid; parent uuid;
 item record; slug text; i integer; names text[]:=ARRAY['CEO / Owner','VP','Director','RSM / Regional','Store Manager','Sales Manager','Sales Rep / Service Rep'];
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
 super:=tj_private.is_platform_admin();
 IF p_payload IS NULL OR jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>16384 THEN RAISE EXCEPTION 'invalid_payload'; END IF;
 IF p_action='bootstrap' THEN
  RETURN jsonb_build_object('source_user_id',uid,'platform_admin',super,'organizations',coalesce((
   SELECT jsonb_agg(to_jsonb(o) ORDER BY o.name) FROM tj.organizations o WHERE o.deleted_at IS NULL AND o.status='active'
   AND (super OR EXISTS(SELECT 1 FROM tj.organization_members m WHERE m.organization_id=o.id AND m.user_id=uid AND m.status='active' AND m.role IN ('owner','admin')))
  ),'[]'::jsonb));
 END IF;
 IF p_action='company_create' THEN
  IF NOT super OR p_organization_id IS NOT NULL THEN RAISE EXCEPTION 'platform_admin_required'; END IF;
 ELSE
  -- Serialize hierarchy, ownership and assignment changes within each company.
  PERFORM 1 FROM tj.organizations o WHERE o.id=target_org AND o.deleted_at IS NULL AND o.status='active' FOR UPDATE;
  IF NOT FOUND OR NOT tj_private.is_org_admin(target_org) THEN RAISE EXCEPTION 'company_admin_required'; END IF;
  SELECT m.role INTO actor_role FROM tj.organization_members m WHERE m.organization_id=target_org AND m.user_id=uid AND m.status='active';
 END IF;
 IF p_action='snapshot' THEN
  RETURN jsonb_build_object(
   'mems',coalesce((SELECT jsonb_agg(to_jsonb(m)||jsonb_build_object('_name',p.full_name,'_email',s.email) ORDER BY m.created_at)
    FROM tj.organization_members m LEFT JOIN tj.source_auth_users s ON s.id=m.user_id LEFT JOIN tj.profiles p ON p.user_id=m.user_id WHERE m.organization_id=target_org),'[]'::jsonb),
   'roles',coalesce((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.role_level,r.role_name) FROM tj.org_roles r WHERE r.organization_id=target_org AND r.active IS TRUE),'[]'::jsonb),
   'ents',coalesce((SELECT jsonb_agg(to_jsonb(e) ORDER BY e.app_key) FROM tj.org_app_entitlements e WHERE e.organization_id=target_org),'[]'::jsonb),
   'invs',coalesce((SELECT jsonb_agg(to_jsonb(v) ORDER BY v.created_at DESC) FROM tj.org_invites v WHERE v.organization_id=target_org),'[]'::jsonb),
   'locs',coalesce((SELECT jsonb_agg(to_jsonb(l) ORDER BY l.location_type,l.name) FROM tj.org_locations l WHERE l.organization_id=target_org),'[]'::jsonb),
   'locmems',coalesce((SELECT jsonb_agg(to_jsonb(l)) FROM tj.org_location_members l WHERE l.organization_id=target_org AND l.is_active IS TRUE),'[]'::jsonb)
  );
 END IF;
 CASE p_action
 WHEN 'company_create' THEN allowed:=ARRAY['name','slug','tenant_type','tier','billing_email','billing_currency'];
 WHEN 'company_save' THEN allowed:=ARRAY['name','billing_email','billing_currency'];
 WHEN 'location_save' THEN allowed:=ARRAY['id','name','location_type','code','address','city','province_state','country','timezone','parent_id','is_active'];
 WHEN 'location_archive' THEN allowed:=ARRAY['id'];
 WHEN 'role_save' THEN allowed:=ARRAY['id','role_name','role_level','description','can_view_team_analytics','can_view_all_analytics','can_manage_targets','can_manage_kpis','can_manage_users','can_manage_roles','active'];
 WHEN 'role_archive' THEN allowed:=ARRAY['id'];
 WHEN 'member_save' THEN allowed:=ARRAY['id','role','status','org_role_id','manager_id','visibility_scope'];
 WHEN 'member_locations' THEN allowed:=ARRAY['user_id','location_ids','primary_location_id'];
 WHEN 'entitlement_save' THEN allowed:=ARRAY['id','app_key','tier','seats_included','price_cents_monthly','status','trial_ends_at'];
 WHEN 'provision_roles' THEN allowed:=ARRAY[]::text[];
 ELSE RAISE EXCEPTION 'unknown_action'; END CASE;
 IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_payload) k WHERE NOT k=ANY(allowed)) THEN RAISE EXCEPTION 'unsupported_field'; END IF;
 row_id:=nullif(p_payload->>'id','')::uuid;

 IF p_action='company_create' THEN
  IF nullif(btrim(p_payload->>'name'),'') IS NULL OR length(p_payload->>'name')>160 THEN RAISE EXCEPTION 'invalid_company_name'; END IF;
  slug:=coalesce(nullif(p_payload->>'slug',''),trim(both '-' from regexp_replace(lower(p_payload->>'name'),'[^a-z0-9]+','-','g')));
  IF slug !~ '^[a-z0-9][a-z0-9-]{0,159}$' THEN RAISE EXCEPTION 'invalid_company_slug'; END IF;
  INSERT INTO tj.organizations(name,slug,tenant_type,tier,billing_email,billing_currency,status)
  VALUES(btrim(p_payload->>'name'),slug,coalesce(p_payload->>'tenant_type','retail_company'),coalesce(p_payload->>'tier','starter'),nullif(p_payload->>'billing_email',''),coalesce(p_payload->>'billing_currency','cad'),'active') RETURNING * INTO company;
  target_org:=company.id;row_id:=company.id;after_row:=to_jsonb(company);
  INSERT INTO tj.organization_members(organization_id,user_id,role,status,visibility_scope) VALUES(target_org,uid,'owner','active','all');
 ELSIF p_action='company_save' THEN
  SELECT * INTO company FROM tj.organizations WHERE id=target_org;
  before_row:=to_jsonb(company);company:=jsonb_populate_record(company,p_payload);
  IF nullif(btrim(company.name),'') IS NULL OR length(company.name)>160 OR length(coalesce(company.billing_email,''))>254 THEN RAISE EXCEPTION 'invalid_company_details'; END IF;
  UPDATE tj.organizations SET name=btrim(company.name),billing_email=company.billing_email,billing_currency=company.billing_currency WHERE id=target_org RETURNING to_jsonb(tj.organizations.*) INTO after_row;row_id:=target_org;
 ELSIF p_action IN ('location_save','location_archive') THEN
  IF row_id IS NOT NULL THEN SELECT * INTO loc FROM tj.org_locations WHERE id=row_id AND organization_id=target_org; IF NOT FOUND THEN RAISE EXCEPTION 'record_not_found'; END IF;before_row:=to_jsonb(loc);
  ELSE IF p_action='location_archive' THEN RAISE EXCEPTION 'record_not_found'; END IF;loc.id:=gen_random_uuid();loc.organization_id:=target_org;loc.is_active:=true;loc.country:='CA';loc.timezone:='America/Toronto'; END IF;
  loc:=jsonb_populate_record(loc,p_payload-'id');
  IF p_action='location_archive' THEN loc.is_active:=false; END IF;
  IF nullif(btrim(loc.name),'') IS NULL OR length(loc.name)>160 OR loc.location_type IS NULL OR loc.is_active IS NULL THEN RAISE EXCEPTION 'invalid_location'; END IF;
  IF loc.parent_id IS NOT NULL THEN
   IF NOT EXISTS(SELECT 1 FROM tj.org_locations l WHERE l.id=loc.parent_id AND l.organization_id=target_org AND l.is_active IS TRUE) THEN RAISE EXCEPTION 'invalid_location_parent'; END IF;
   IF EXISTS(WITH RECURSIVE chain AS(SELECT id,parent_id FROM tj.org_locations WHERE id=loc.parent_id AND organization_id=target_org UNION SELECT l.id,l.parent_id FROM tj.org_locations l JOIN chain c ON l.id=c.parent_id WHERE l.organization_id=target_org) SELECT 1 FROM chain WHERE id=loc.id) THEN RAISE EXCEPTION 'location_cycle'; END IF;
  END IF;
  IF NOT loc.is_active AND EXISTS(SELECT 1 FROM tj.org_locations WHERE parent_id=loc.id AND is_active IS TRUE) THEN RAISE EXCEPTION 'location_has_active_children'; END IF;
  INSERT INTO tj.org_locations(id,organization_id,name,location_type,code,address,city,province_state,country,timezone,parent_id,is_active)
  VALUES(loc.id,target_org,btrim(loc.name),loc.location_type,loc.code,loc.address,loc.city,loc.province_state,loc.country,loc.timezone,loc.parent_id,loc.is_active)
  ON CONFLICT(id) DO UPDATE SET name=excluded.name,location_type=excluded.location_type,code=excluded.code,address=excluded.address,city=excluded.city,province_state=excluded.province_state,country=excluded.country,timezone=excluded.timezone,parent_id=excluded.parent_id,is_active=excluded.is_active,updated_at=now()
  RETURNING to_jsonb(tj.org_locations.*) INTO after_row;row_id:=loc.id;
  IF NOT loc.is_active THEN UPDATE tj.org_location_members SET is_active=false,is_primary=false,revoked_at=now(),revoked_by=uid WHERE location_id=loc.id AND organization_id=target_org AND is_active IS TRUE; END IF;
 ELSIF p_action IN ('role_save','role_archive') THEN
  IF row_id IS NOT NULL THEN SELECT * INTO position FROM tj.org_roles WHERE id=row_id AND organization_id=target_org; IF NOT FOUND THEN RAISE EXCEPTION 'record_not_found'; END IF;before_row:=to_jsonb(position);
  ELSE IF p_action='role_archive' THEN RAISE EXCEPTION 'record_not_found'; END IF;position.id:=gen_random_uuid();position.organization_id:=target_org;position.active:=true; END IF;
  position:=jsonb_populate_record(position,p_payload-'id');IF p_action='role_archive' THEN position.active:=false; END IF;
  IF nullif(btrim(position.role_name),'') IS NULL OR length(position.role_name)>160 OR position.role_level IS NULL OR position.role_level NOT BETWEEN 1 AND 7 OR position.active IS NULL THEN RAISE EXCEPTION 'invalid_role'; END IF;
  IF NOT position.active AND EXISTS(SELECT 1 FROM tj.organization_members WHERE org_role_id=position.id AND organization_id=target_org) THEN RAISE EXCEPTION 'role_in_use'; END IF;
  INSERT INTO tj.org_roles(id,organization_id,role_name,role_level,description,can_view_team_analytics,can_view_all_analytics,can_manage_targets,can_manage_kpis,can_manage_users,can_manage_roles,active)
  VALUES(position.id,target_org,btrim(position.role_name),position.role_level,position.description,coalesce(position.can_view_team_analytics,false),coalesce(position.can_view_all_analytics,false),coalesce(position.can_manage_targets,false),coalesce(position.can_manage_kpis,false),coalesce(position.can_manage_users,false),coalesce(position.can_manage_roles,false),position.active)
  ON CONFLICT(id) DO UPDATE SET role_name=excluded.role_name,role_level=excluded.role_level,description=excluded.description,can_view_team_analytics=excluded.can_view_team_analytics,can_view_all_analytics=excluded.can_view_all_analytics,can_manage_targets=excluded.can_manage_targets,can_manage_kpis=excluded.can_manage_kpis,can_manage_users=excluded.can_manage_users,can_manage_roles=excluded.can_manage_roles,active=excluded.active RETURNING to_jsonb(tj.org_roles.*) INTO after_row;row_id:=position.id;
 ELSIF p_action='member_save' THEN
  SELECT * INTO member FROM tj.organization_members WHERE id=row_id AND organization_id=target_org;IF NOT FOUND THEN RAISE EXCEPTION 'record_not_found'; END IF;
  before_row:=to_jsonb(member);member:=jsonb_populate_record(member,p_payload-'id');
  IF member.role IS NULL OR member.role NOT IN ('owner','admin','manager','member','viewer') OR member.status IS NULL OR member.status NOT IN ('invited','active','suspended','removed') OR member.visibility_scope IS NULL OR member.visibility_scope NOT IN ('own','team','store','all') THEN RAISE EXCEPTION 'invalid_member_details'; END IF;
  IF NOT super AND actor_role<>'owner' AND (before_row->>'role'='owner' OR member.role='owner') THEN RAISE EXCEPTION 'owner_required'; END IF;
  IF before_row->>'role'='owner' AND before_row->>'status'='active' AND (member.role<>'owner' OR member.status<>'active') AND NOT EXISTS(SELECT 1 FROM tj.organization_members WHERE organization_id=target_org AND id<>row_id AND role='owner' AND status='active') THEN RAISE EXCEPTION 'last_owner_required'; END IF;
  IF before_row->>'role' IN ('owner','admin') AND before_row->>'status'='active' AND (member.role NOT IN ('owner','admin') OR member.status<>'active') AND NOT EXISTS(SELECT 1 FROM tj.organization_members WHERE organization_id=target_org AND id<>row_id AND role IN ('owner','admin') AND status='active') THEN RAISE EXCEPTION 'last_admin_required'; END IF;
  IF member.org_role_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.org_roles WHERE id=member.org_role_id AND organization_id=target_org AND active IS TRUE AND role_level>=CASE member.role WHEN 'owner' THEN 1 WHEN 'admin' THEN 2 ELSE 3 END) THEN RAISE EXCEPTION 'invalid_member_role'; END IF;
  IF member.manager_id IS NOT NULL THEN
   IF NOT EXISTS(SELECT 1 FROM tj.organization_members WHERE id=member.manager_id AND organization_id=target_org AND status='active') THEN RAISE EXCEPTION 'invalid_manager'; END IF;
   IF EXISTS(WITH RECURSIVE chain AS(SELECT id,manager_id FROM tj.organization_members WHERE id=member.manager_id AND organization_id=target_org UNION SELECT m.id,m.manager_id FROM tj.organization_members m JOIN chain c ON m.id=c.manager_id WHERE m.organization_id=target_org) SELECT 1 FROM chain WHERE id=row_id) THEN RAISE EXCEPTION 'manager_cycle'; END IF;
  END IF;
  UPDATE tj.organization_members SET role=member.role,status=member.status,org_role_id=member.org_role_id,manager_id=member.manager_id,visibility_scope=member.visibility_scope WHERE id=row_id AND organization_id=target_org RETURNING to_jsonb(tj.organization_members.*) INTO after_row;
  IF member.status<>'active' THEN UPDATE tj.org_location_members SET is_active=false,is_primary=false,revoked_at=now(),revoked_by=uid WHERE organization_id=target_org AND user_id=member.user_id AND is_active IS TRUE; END IF;
 ELSIF p_action='member_locations' THEN
  target_user:=nullif(p_payload->>'user_id','')::uuid;primary_location:=nullif(p_payload->>'primary_location_id','')::uuid;
  IF jsonb_typeof(p_payload->'location_ids') IS DISTINCT FROM 'array' OR jsonb_array_length(p_payload->'location_ids')>200 THEN RAISE EXCEPTION 'invalid_location_selection'; END IF;
  SELECT coalesce(array_agg(value::uuid),'{}'::uuid[]) INTO location_ids FROM jsonb_array_elements_text(p_payload->'location_ids');
  IF cardinality(location_ids)<>(SELECT count(DISTINCT x) FROM unnest(location_ids) x) THEN RAISE EXCEPTION 'duplicate_location'; END IF;
  IF NOT EXISTS(SELECT 1 FROM tj.organization_members WHERE organization_id=target_org AND user_id=target_user AND status='active') THEN RAISE EXCEPTION 'invalid_member'; END IF;
  IF EXISTS(SELECT 1 FROM unnest(location_ids) x WHERE NOT EXISTS(SELECT 1 FROM tj.org_locations l WHERE l.id=x AND l.organization_id=target_org AND l.is_active IS TRUE)) THEN RAISE EXCEPTION 'invalid_member_location'; END IF;
  IF primary_location IS NOT NULL AND NOT primary_location=ANY(location_ids) THEN RAISE EXCEPTION 'primary_location_not_selected'; END IF;
  IF EXISTS(SELECT 1 FROM tj.org_location_members WHERE user_id=target_user AND location_id=ANY(location_ids) AND organization_id<>target_org) THEN RAISE EXCEPTION 'invalid_member_location'; END IF;
  before_row:=coalesce((SELECT jsonb_agg(to_jsonb(l)) FROM tj.org_location_members l WHERE l.organization_id=target_org AND l.user_id=target_user),'[]'::jsonb);
  UPDATE tj.org_location_members SET is_active=false,is_primary=false,revoked_at=now(),revoked_by=uid WHERE organization_id=target_org AND user_id=target_user;
  INSERT INTO tj.org_location_members(organization_id,location_id,user_id,is_primary,is_active) SELECT target_org,x,target_user,coalesce(x=primary_location,false),true FROM unnest(location_ids) x
  ON CONFLICT(location_id,user_id) DO UPDATE SET is_active=true,is_primary=excluded.is_primary,revoked_at=NULL,revoked_by=NULL;
  after_row:=coalesce((SELECT jsonb_agg(to_jsonb(l)) FROM tj.org_location_members l WHERE l.organization_id=target_org AND l.user_id=target_user AND l.is_active IS TRUE),'[]'::jsonb);row_id:=target_user;
 ELSIF p_action='entitlement_save' THEN
  IF NOT super THEN RAISE EXCEPTION 'platform_admin_required'; END IF;
  IF row_id IS NOT NULL THEN SELECT * INTO entitlement FROM tj.org_app_entitlements WHERE id=row_id AND organization_id=target_org;IF NOT FOUND THEN RAISE EXCEPTION 'record_not_found'; END IF;before_row:=to_jsonb(entitlement);
  ELSE IF NOT p_payload ? 'price_cents_monthly' THEN RAISE EXCEPTION 'recorded_price_required'; END IF;entitlement.id:=gen_random_uuid();entitlement.organization_id:=target_org;entitlement.tier:='starter';entitlement.seats_included:=1;entitlement.price_cents_monthly:=0;entitlement.status:='active';entitlement.seats_used:=0; END IF;
  entitlement:=jsonb_populate_record(entitlement,p_payload-'id');
  IF before_row IS NOT NULL AND entitlement.app_key IS DISTINCT FROM before_row->>'app_key' THEN RAISE EXCEPTION 'immutable_app_key'; END IF;
  IF entitlement.seats_included IS NULL OR entitlement.seats_included NOT BETWEEN 1 AND 100000 OR entitlement.seats_included<entitlement.seats_used OR entitlement.price_cents_monthly IS NULL OR entitlement.price_cents_monthly<0 THEN RAISE EXCEPTION 'invalid_entitlement'; END IF;
  IF entitlement.status='trial' AND (entitlement.trial_ends_at IS NULL OR entitlement.trial_ends_at<=now()) THEN RAISE EXCEPTION 'trial_end_required'; END IF;
  INSERT INTO tj.org_app_entitlements(id,organization_id,app_key,tier,seats_included,price_cents_monthly,status,trial_ends_at,canceled_at)
  VALUES(entitlement.id,target_org,entitlement.app_key,entitlement.tier,entitlement.seats_included,entitlement.price_cents_monthly,entitlement.status,entitlement.trial_ends_at,CASE WHEN entitlement.status='canceled' THEN now() ELSE NULL END)
  ON CONFLICT(id) DO UPDATE SET tier=excluded.tier,seats_included=excluded.seats_included,price_cents_monthly=excluded.price_cents_monthly,status=excluded.status,trial_ends_at=excluded.trial_ends_at,canceled_at=excluded.canceled_at,updated_at=now() RETURNING to_jsonb(tj.org_app_entitlements.*) INTO after_row;row_id:=entitlement.id;
 ELSIF p_action='provision_roles' THEN
  FOR i IN 1..7 LOOP
   INSERT INTO tj.org_roles(organization_id,role_name,role_level,can_view_team_analytics,can_view_all_analytics,can_manage_targets,can_manage_kpis,can_manage_users,can_manage_roles)
   VALUES(target_org,names[i],i,i<=6,i<=4,i<=5,i<=4,i<=2,i=1) ON CONFLICT(organization_id,role_name) DO NOTHING;
  END LOOP;
  after_row:=jsonb_build_object('standard_roles_ready',true);
 END IF;
 INSERT INTO tj_private.company_admin_audit(organization_id,actor_source_user_id,action,record_id,before_data,after_data) VALUES(target_org,uid,p_action,row_id,before_row,after_row);
 RETURN jsonb_build_object('ok',true,'record',after_row,'organization_id',target_org);
END $$;
REVOKE ALL ON FUNCTION tj_private.company_admin(uuid,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.company_admin(uuid,text,jsonb) TO authenticated;
CREATE FUNCTION public.tj_runtime_company_admin(p_organization_id uuid DEFAULT NULL,p_action text DEFAULT 'bootstrap',p_payload jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.company_admin(p_organization_id,p_action,p_payload); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_company_admin(uuid,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tj_runtime_company_admin(uuid,text,jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';
