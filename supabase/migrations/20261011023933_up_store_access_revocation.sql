CREATE TABLE tj_private.up_store_access_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id uuid NOT NULL REFERENCES tj.organizations(id),
 location_id uuid NOT NULL REFERENCES tj.org_locations(id), member_user_id uuid NOT NULL,
 action text NOT NULL CHECK(action IN('grant','revoke')), actor_user_id uuid NOT NULL,
 occurred_at timestamptz NOT NULL DEFAULT now());
ALTER TABLE tj_private.up_store_access_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj_private.up_store_access_events FROM PUBLIC,anon,authenticated,service_role;
CREATE INDEX up_store_access_events_org_location_idx ON tj_private.up_store_access_events(organization_id,location_id,occurred_at);

-- Retain every assignment; explicit store revocation precedes broad organization visibility.
ALTER TABLE tj.org_location_members ADD COLUMN is_active boolean NOT NULL DEFAULT true, ADD COLUMN revoked_at timestamptz, ADD COLUMN revoked_by uuid;
CREATE OR REPLACE FUNCTION tj_private.aiq_scope_allows(p_org uuid, p_owner uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
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
        AND a.is_active AND b.is_active AND a.user_id=v_uid AND b.user_id=p_owner);
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
$function$
;

CREATE OR REPLACE FUNCTION tj_private.aiq_store_allows(p_org uuid, p_store uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid:=tj_private.current_source_user_id(); v_me tj.organization_members%ROWTYPE;
BEGIN
  IF v_uid IS NULL OR NOT tj_private.is_org_member(p_org) THEN RETURN false; END IF;
  IF p_store IS NULL OR tj_private.is_platform_admin() THEN RETURN true; END IF;
  IF EXISTS(SELECT 1 FROM tj.org_location_members lm JOIN tj.org_locations l ON l.id=lm.location_id AND l.organization_id=p_org WHERE lm.organization_id=p_org AND lm.user_id=v_uid AND NOT lm.is_active AND (l.id=p_store OR l.iq_store_id=p_store)) THEN RETURN false; END IF;
  SELECT * INTO v_me FROM tj.organization_members
    WHERE organization_id=p_org AND user_id=v_uid AND status='active' LIMIT 1;
  IF v_me.role IN ('owner','admin') OR coalesce(v_me.visibility_scope,'own')='all' THEN RETURN true; END IF;
  RETURN EXISTS(SELECT 1 FROM tj.org_location_members m
    JOIN tj.org_locations l ON l.id=m.location_id AND l.organization_id=p_org
    WHERE m.is_active AND m.organization_id=p_org AND m.user_id=v_uid AND (l.id=p_store OR l.iq_store_id=p_store));
END;
$function$
;

CREATE OR REPLACE FUNCTION tj_private.allowed_store_pairs()
 RETURNS TABLE(organization_id uuid, store_id uuid)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$ DECLARE uid uuid:=tj_private.current_source_user_id(); BEGIN
 IF uid IS NULL THEN RETURN; END IF;
 RETURN QUERY SELECT DISTINCT lm.organization_id,l.id FROM tj.org_location_members lm
 JOIN tj.org_locations l ON l.id=lm.location_id AND l.organization_id=lm.organization_id
 JOIN tj.organization_members m ON m.organization_id=lm.organization_id AND m.user_id=uid AND m.status='active'
 WHERE lm.is_active AND lm.user_id=uid
 UNION SELECT DISTINCT lm.organization_id,l.iq_store_id FROM tj.org_location_members lm
 JOIN tj.org_locations l ON l.id=lm.location_id AND l.organization_id=lm.organization_id
 JOIN tj.organization_members m ON m.organization_id=lm.organization_id AND m.user_id=uid AND m.status='active'
 WHERE lm.is_active AND lm.user_id=uid AND l.iq_store_id IS NOT NULL;
END $function$
;

CREATE OR REPLACE FUNCTION tj_private.check_app_access(p_app text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := tj_private.current_source_user_id();
  v_row record;
  v_stores jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('allowed', false, 'reason', 'not_authenticated');
  END IF;

  IF is_platform_admin() THEN
    RETURN jsonb_build_object('allowed', true, 'reason', 'platform_admin',
      'role', 'super_admin', 'role_level', 0, 'visibility_scope', 'all',
      'store_ids', '[]'::jsonb,
      'permissions', jsonb_build_object(
        'can_manage_users', true, 'can_manage_roles', true,
        'can_view_all_analytics', true, 'can_view_team_analytics', true,
        'can_manage_kpis', true, 'can_manage_targets', true));
  END IF;

  SELECT m.organization_id, o.name AS org_name, m.role, m.visibility_scope,
         e.status AS ent_status, e.tier, e.trial_ends_at,
         r.role_name, r.role_level,
         coalesce(r.can_manage_users,false) mu, coalesce(r.can_manage_roles,false) mr,
         coalesce(r.can_view_all_analytics,false) va, coalesce(r.can_view_team_analytics,false) vt,
         coalesce(r.can_manage_kpis,false) mk, coalesce(r.can_manage_targets,false) mt
  INTO v_row
  FROM organization_members m
  JOIN organizations o ON o.id = m.organization_id AND o.status = 'active' AND o.deleted_at IS NULL
  JOIN org_app_entitlements e ON e.organization_id = m.organization_id AND e.app_key = p_app
  LEFT JOIN org_roles r ON r.id = m.org_role_id AND r.organization_id=m.organization_id AND r.active
  WHERE m.user_id = v_uid AND m.status = 'active'
  ORDER BY (e.status = 'active') DESC, (e.status = 'trial') DESC
  LIMIT 1;

  IF v_row IS NULL THEN
    RETURN jsonb_build_object('allowed', false, 'reason', 'no_entitlement');
  END IF;

  IF v_row.ent_status = 'trial' AND v_row.trial_ends_at IS NOT NULL AND v_row.trial_ends_at < now() THEN
    RETURN jsonb_build_object('allowed', false, 'reason', 'trial_expired',
      'organization_id', v_row.organization_id, 'organization_name', v_row.org_name);
  END IF;

  IF v_row.ent_status NOT IN ('active','trial') THEN
    RETURN jsonb_build_object('allowed', false, 'reason', v_row.ent_status,
      'organization_id', v_row.organization_id, 'organization_name', v_row.org_name);
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'name', l.name, 'primary', lm.is_primary)), '[]'::jsonb)
  INTO v_stores
  FROM org_location_members lm
  JOIN org_locations l ON l.id = lm.location_id AND l.organization_id=lm.organization_id AND l.is_active
  WHERE lm.is_active AND lm.user_id = v_uid AND lm.organization_id = v_row.organization_id;

  RETURN jsonb_build_object('allowed', true, 'reason', v_row.ent_status,
    'organization_id', v_row.organization_id, 'organization_name', v_row.org_name,
    'tier', v_row.tier, 'role', v_row.role,
    'position', v_row.role_name, 'role_level', coalesce(v_row.role_level, 99),
    'visibility_scope', coalesce(v_row.visibility_scope, 'own'),
    'store_ids', v_stores,
    'permissions', jsonb_build_object(
      'can_manage_users', v_row.mu, 'can_manage_roles', v_row.mr,
      'can_view_all_analytics', v_row.va, 'can_view_team_analytics', v_row.vt,
      'can_manage_kpis', v_row.mk, 'can_manage_targets', v_row.mt));
END;
$function$
;

CREATE OR REPLACE FUNCTION tj_private.my_platform_context()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE uid uuid:=tj_private.current_source_user_id(); out_ctx jsonb;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
 SELECT jsonb_build_object('user_id',auth.uid(),'source_user_id',uid,'organization_id',o.id,
 'organization_name',o.name,'organization_role',m.role,'location_id',l.id,
 'location_name',l.name,'location_code',l.code,'entity_type',c.entity_type,
 'entity_id',c.entity_id,'entity_label',c.entity_label,'source_module_key',c.source_module_key,
 'context',coalesce(c.context,'{}'::jsonb),'updated_at',c.updated_at) INTO out_ctx
 FROM tj.platform_user_context c
 JOIN tj.organizations o ON o.id=c.organization_id AND o.deleted_at IS NULL AND o.status='active'
 JOIN tj.organization_members m ON m.organization_id=o.id AND m.user_id=uid AND m.status='active'
 LEFT JOIN tj.org_locations l ON l.id=c.location_id AND l.organization_id=o.id AND l.is_active IS TRUE
 WHERE c.user_id=uid AND (c.location_id IS NULL OR (l.id IS NOT NULL AND tj_private.aiq_store_allows(o.id,l.id)));
 IF out_ctx IS NULL THEN
 SELECT jsonb_build_object('user_id',auth.uid(),'source_user_id',uid,'organization_id',o.id,
 'organization_name',o.name,'organization_role',m.role,'location_id',l.id,
 'location_name',l.name,'location_code',l.code,'entity_type',NULL,'entity_id',NULL,
 'entity_label',NULL,'source_module_key','platform','context','{}'::jsonb,'updated_at',now()) INTO out_ctx
 FROM tj.organization_members m
 JOIN tj.organizations o ON o.id=m.organization_id AND o.deleted_at IS NULL AND o.status='active'
 LEFT JOIN LATERAL (SELECT loc.id,loc.name,loc.code FROM tj.org_location_members lm
 JOIN tj.org_locations loc ON loc.id=lm.location_id AND loc.organization_id=m.organization_id
 AND loc.is_active IS TRUE WHERE lm.is_active AND lm.organization_id=m.organization_id AND lm.user_id=uid
 ORDER BY lm.is_primary DESC,lm.created_at,loc.id LIMIT 1) l ON TRUE
 WHERE m.user_id=uid AND m.status='active' ORDER BY m.created_at,m.id LIMIT 1;
 END IF;
 RETURN coalesce(out_ctx,jsonb_build_object('user_id',auth.uid(),'source_user_id',uid,'context','{}'::jsonb));
END $function$
;

CREATE OR REPLACE FUNCTION tj_private.my_platform_locations(p_organization_id uuid)
 RETURNS TABLE(location_id uuid, location_name text, location_code text, location_type text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$ SELECT l.id,l.name,l.code,l.location_type FROM tj.org_locations l
 JOIN tj.organizations o ON o.id=l.organization_id AND o.deleted_at IS NULL
 WHERE l.organization_id=p_organization_id AND l.is_active IS TRUE AND tj_private.aiq_store_allows(l.organization_id,l.id)
 AND EXISTS (SELECT 1 FROM tj.organization_members m WHERE m.organization_id=p_organization_id
 AND m.user_id=tj_private.current_source_user_id() AND m.status='active') ORDER BY l.name; $function$
;

CREATE OR REPLACE FUNCTION tj_private.set_platform_context(p_organization_id uuid DEFAULT NULL::uuid, p_location_id uuid DEFAULT NULL::uuid, p_entity_type text DEFAULT NULL::text, p_entity_id text DEFAULT NULL::text, p_entity_label text DEFAULT NULL::text, p_source_module_key text DEFAULT NULL::text, p_context jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE uid uuid:=tj_private.current_source_user_id(); org_id uuid;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
 org_id:=p_organization_id;
 IF org_id IS NULL THEN
 SELECT c.organization_id INTO org_id FROM tj.platform_user_context c
 JOIN tj.organizations o ON o.id=c.organization_id AND o.deleted_at IS NULL
 JOIN tj.organization_members m ON m.organization_id=o.id AND m.user_id=uid AND m.status='active'
 WHERE c.user_id=uid;
 END IF;
 IF org_id IS NULL THEN SELECT organization_id INTO org_id FROM tj_private.my_platform_organizations() LIMIT 1; END IF;
 IF org_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM tj.organization_members m
 JOIN tj.organizations o ON o.id=m.organization_id AND o.deleted_at IS NULL
 WHERE m.user_id=uid AND m.organization_id=org_id AND m.status='active')
 THEN RAISE EXCEPTION 'organization_access_denied'; END IF;
 IF p_location_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM tj.org_locations l
 WHERE l.id=p_location_id AND l.organization_id=org_id AND l.is_active IS TRUE AND tj_private.aiq_store_allows(org_id,l.id))
 THEN RAISE EXCEPTION 'location_access_denied'; END IF;
 INSERT INTO tj.platform_user_context(user_id,organization_id,location_id,entity_type,entity_id,entity_label,source_module_key,context,updated_at)
 VALUES(uid,org_id,p_location_id,p_entity_type,p_entity_id,p_entity_label,p_source_module_key,coalesce(p_context,'{}'),now())
 ON CONFLICT(user_id) DO UPDATE SET organization_id=excluded.organization_id,location_id=excluded.location_id,
 entity_type=excluded.entity_type,entity_id=excluded.entity_id,entity_label=excluded.entity_label,
 source_module_key=excluded.source_module_key,context=excluded.context,updated_at=now();
 RETURN tj_private.my_platform_context();
END $function$
;

CREATE OR REPLACE FUNCTION tj_private.up_administration(p_body jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid:=tj_private.current_source_user_id();org uuid;sid uuid;act text;myrole text;m tj.organization_members;newrole text;storeid uuid;prof uuid;mid uuid;mr tj.iq_missed_and_potential_missed_ups;q tj.iq_up_queue_entries;rule text;counted boolean;decision text;otherq uuid;position int;
BEGIN
 IF auth.uid() IS NULL OR actor IS NULL THEN RETURN jsonb_build_object('ok',false,'error','identity_required');END IF;
 IF jsonb_typeof(p_body) IS DISTINCT FROM 'object' OR octet_length(p_body::text)>8000 THEN RAISE EXCEPTION 'invalid_request';END IF;
 org:=(p_body->>'organization_id')::uuid;sid:=nullif(p_body->>'store_id','')::uuid;act:=p_body->>'action';
 SELECT role INTO myrole FROM tj.organization_members WHERE organization_id=org AND user_id=actor AND status='active';
 IF myrole IS NULL OR NOT tj_private.can_read_runtime_org(org) THEN RETURN jsonb_build_object('ok',false,'error','organization_required');END IF;
 SELECT id INTO prof FROM tj.profiles WHERE user_id=actor;
 IF act IN('report_missed','review_missed') THEN
  IF sid IS NULL OR NOT EXISTS(SELECT 1 FROM tj.org_locations WHERE id=sid AND organization_id=org AND is_active) OR NOT tj.aiq_store_allows(org,sid) THEN RAISE EXCEPTION 'store_unavailable';END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('up-floor:'||sid::text,0));
  mid:=(p_body->>'missed_id')::uuid;IF mid IS NULL OR prof IS NULL THEN RAISE EXCEPTION 'invalid_record';END IF;
  SELECT * INTO mr FROM tj.iq_missed_and_potential_missed_ups WHERE id=mid FOR UPDATE;
  IF act='report_missed' THEN
   IF myrole NOT IN('owner','admin','manager','member') THEN RAISE EXCEPTION 'member_required';END IF;
   IF mr.id IS NOT NULL THEN IF mr.organization_id<>org OR mr.store_id<>sid OR mr.reported_by<>prof THEN RAISE EXCEPTION 'record_unavailable';END IF;RETURN jsonb_build_object('ok',true,'changed',false);END IF;
   IF length(btrim(coalesce(p_body->>'reason','')))<1 OR length(p_body->>'reason')>2000 THEN RAISE EXCEPTION 'reason_required';END IF;
   SELECT qe.* INTO q FROM tj.iq_up_queue_entries qe JOIN tj.iq_shift_records sh ON sh.id=qe.shift_id AND sh.is_active JOIN tj.profiles p ON p.id=qe.user_id JOIN tj.organization_members mem ON mem.user_id=p.user_id AND mem.organization_id=org AND mem.status='active' WHERE qe.organization_id=org AND qe.store_id=sid AND qe.user_id=(p_body->>'rep_profile_id')::uuid ORDER BY sh.login_at DESC LIMIT 1;
   IF q.id IS NULL THEN RAISE EXCEPTION 'active_shift_required';END IF;
   INSERT INTO tj.iq_missed_and_potential_missed_ups(id,organization_id,store_id,queue_entry_id,reported_by,employee_user_id,reason,is_potential,affects_kpi) VALUES(mid,org,sid,q.id,prof,q.user_id,btrim(p_body->>'reason'),true,false);
  ELSE
   IF myrole NOT IN('owner','admin','manager') THEN RETURN jsonb_build_object('ok',false,'error','manager_required');END IF;
   IF mr.id IS NULL OR mr.organization_id<>org OR mr.store_id<>sid THEN RAISE EXCEPTION 'record_unavailable';END IF;
   decision:=p_body->>'decision';IF decision IS NULL OR decision NOT IN('confirm','excuse','potential') OR length(coalesce(p_body->>'notes',''))>2000 THEN RAISE EXCEPTION 'invalid_decision';END IF;
   SELECT * INTO q FROM tj.iq_up_queue_entries WHERE id=mr.queue_entry_id AND organization_id=org AND store_id=sid;
   counted:=decision='confirm';IF counted AND q.id IS NULL THEN RAISE EXCEPTION 'shift_evidence_required';END IF;
   IF coalesce(mr.affects_kpi,false) IS DISTINCT FROM counted AND q.id IS NOT NULL THEN UPDATE tj.iq_shift_records SET ups_missed=greatest(0,ups_missed+CASE WHEN counted THEN 1 ELSE -1 END),updated_by=actor WHERE id=q.shift_id AND organization_id=org;END IF;
   IF counted AND NOT coalesce(mr.affects_kpi,false) AND q.is_in_queue THEN
    SELECT missed_up_queue_rule INTO rule FROM tj.iq_store_settings WHERE organization_id=org AND store_id=sid;
    IF coalesce(rule,'back_of_queue')='back_of_queue' THEN SELECT coalesce(max(queue_position),0)+1 INTO position FROM tj.iq_up_queue_entries WHERE organization_id=org AND store_id=sid AND is_in_queue;UPDATE tj.iq_up_queue_entries SET queue_position=position,is_current_up=false,up_offered_at=NULL,updated_by=actor WHERE id=q.id;
    ELSIF rule='skip_once' THEN SELECT id,queue_position INTO otherq,position FROM tj.iq_up_queue_entries WHERE organization_id=org AND store_id=sid AND is_in_queue AND is_available_for_assignment AND queue_position>q.queue_position ORDER BY queue_position LIMIT 1;IF otherq IS NOT NULL THEN UPDATE tj.iq_up_queue_entries SET queue_position=q.queue_position WHERE id=otherq;UPDATE tj.iq_up_queue_entries SET queue_position=position,is_current_up=false,up_offered_at=NULL,updated_by=actor WHERE id=q.id;END IF;END IF;
    PERFORM tj_private.up_recalc_queue(org,sid);
   END IF;
   UPDATE tj.iq_missed_and_potential_missed_ups SET is_potential=decision='potential',is_excused=decision='excuse',affects_kpi=counted,manager_reviewed=true,reviewed_at=now(),reviewed_by=prof,notes=nullif(btrim(p_body->>'notes'),''),queue_consequence=coalesce(queue_consequence,'{}'::jsonb)||jsonb_build_object('decision',decision,'rule',rule,'position_before',q.queue_position,'position_after',(SELECT queue_position FROM tj.iq_up_queue_entries WHERE id=q.id)) WHERE id=mid;
  END IF;
  RETURN jsonb_build_object('ok',true,'missed_id',mid);
 END IF;
 IF myrole NOT IN('owner','admin') THEN RETURN jsonb_build_object('ok',false,'error','administrator_required');END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('up-org-admin:'||org::text,0));
 IF act='team_roster' THEN RETURN jsonb_build_object('ok',true,'members',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',mem.id,'user_id',mem.user_id,'role',mem.role,'status',mem.status,'display_name',coalesce(p.full_name,p.email,'Staff'),'stores',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',loc.id,'name',loc.name,'primary',lm.is_primary,'is_active',lm.is_active,'revoked_at',lm.revoked_at)),'[]'::jsonb) FROM tj.org_location_members lm JOIN tj.org_locations loc ON loc.id=lm.location_id WHERE lm.organization_id=org AND lm.user_id=mem.user_id))),'[]'::jsonb) FROM tj.organization_members mem LEFT JOIN tj.profiles p ON p.user_id=mem.user_id WHERE mem.organization_id=org AND mem.status IN('active','suspended')));END IF;
 IF act IN('set_role','deactivate_member','activate_member','assign_store','revoke_store') THEN
  SELECT * INTO m FROM tj.organization_members WHERE id=(p_body->>'member_id')::uuid AND organization_id=org FOR UPDATE;
  IF m.id IS NULL THEN RAISE EXCEPTION 'member_unavailable';END IF;
  IF m.role IN('owner','admin') AND myrole<>'owner' THEN RAISE EXCEPTION 'owner_required';END IF;
  IF act='set_role' THEN
   newrole:=p_body->>'role';IF newrole IS NULL OR newrole NOT IN('member','manager','admin','owner') OR (myrole<>'owner' AND newrole IN('admin','owner')) THEN RAISE EXCEPTION 'role_not_allowed';END IF;
  END IF;
  IF m.role='owner' AND m.status='active' AND (act='deactivate_member' OR (act='set_role' AND newrole<>'owner')) AND (SELECT count(*) FROM tj.organization_members WHERE organization_id=org AND status='active' AND role='owner')<=1 THEN RETURN jsonb_build_object('ok',false,'error','last_owner_required');END IF;
  SELECT id INTO prof FROM tj.profiles WHERE user_id=m.user_id;
  IF act='deactivate_member' AND EXISTS(SELECT 1 FROM tj.iq_shift_records WHERE organization_id=org AND user_id=prof AND is_active) THEN RETURN jsonb_build_object('ok',false,'error','clock_out_member_first');END IF;
  IF act='set_role' THEN UPDATE tj.organization_members SET role=newrole WHERE id=m.id;
  ELSIF act='deactivate_member' THEN UPDATE tj.organization_members SET status='suspended' WHERE id=m.id;
  ELSIF act='activate_member' THEN IF m.status NOT IN('active','suspended') THEN RAISE EXCEPTION 'membership_review_required';END IF;UPDATE tj.organization_members SET status='active' WHERE id=m.id;
  ELSE
   IF m.status<>'active' OR sid IS NULL OR NOT EXISTS(SELECT 1 FROM tj.org_locations WHERE id=sid AND organization_id=org AND is_active) THEN RAISE EXCEPTION 'active_member_store_required';END IF;
   PERFORM pg_advisory_xact_lock(hashtextextended('up-floor:'||sid::text,0));
   IF act='revoke_store' THEN
    IF EXISTS(SELECT 1 FROM tj.iq_shift_records WHERE organization_id=org AND store_id=sid AND user_id=prof AND is_active) OR EXISTS(SELECT 1 FROM tj.iq_customer_interactions WHERE organization_id=org AND store_id=sid AND salesperson_user_id=prof AND ended_at IS NULL) THEN RETURN jsonb_build_object('ok',false,'error','clock_out_member_first');END IF;
    IF NOT EXISTS(SELECT 1 FROM tj.org_location_members WHERE organization_id=org AND location_id=sid AND user_id=m.user_id AND NOT is_active) THEN INSERT INTO tj_private.up_store_access_events(organization_id,location_id,member_user_id,action,actor_user_id) VALUES(org,sid,m.user_id,'revoke',actor);END IF;
    INSERT INTO tj.org_location_members(organization_id,location_id,user_id,is_primary,is_active,revoked_at,revoked_by) VALUES(org,sid,m.user_id,false,false,now(),actor) ON CONFLICT(location_id,user_id) DO UPDATE SET is_active=false,is_primary=false,revoked_at=coalesce(tj.org_location_members.revoked_at,excluded.revoked_at),revoked_by=coalesce(tj.org_location_members.revoked_by,excluded.revoked_by);
    IF NOT EXISTS(SELECT 1 FROM tj.org_location_members WHERE organization_id=org AND user_id=m.user_id AND is_active AND is_primary) THEN UPDATE tj.org_location_members SET is_primary=true WHERE id=(SELECT lm.id FROM tj.org_location_members lm JOIN tj.org_locations l ON l.id=lm.location_id AND l.is_active WHERE lm.organization_id=org AND lm.user_id=m.user_id AND lm.is_active ORDER BY lm.created_at,lm.id LIMIT 1);END IF;
    RETURN jsonb_build_object('ok',true);
   END IF;
   IF NOT EXISTS(SELECT 1 FROM tj.org_location_members WHERE organization_id=org AND location_id=sid AND user_id=m.user_id AND is_active) THEN INSERT INTO tj_private.up_store_access_events(organization_id,location_id,member_user_id,action,actor_user_id) VALUES(org,sid,m.user_id,'grant',actor);END IF;
   IF coalesce((p_body->>'primary')::boolean,false) THEN UPDATE tj.org_location_members SET is_primary=false WHERE organization_id=org AND user_id=m.user_id;END IF;
   INSERT INTO tj.org_location_members(organization_id,location_id,user_id,is_primary) VALUES(org,sid,m.user_id,coalesce((p_body->>'primary')::boolean,false)) ON CONFLICT(location_id,user_id) DO UPDATE SET is_primary=excluded.is_primary,is_active=true,revoked_at=NULL,revoked_by=NULL;
  END IF;
 ELSIF act='add_store' THEN
  IF length(btrim(coalesce(p_body->>'name','')))<1 OR length(p_body->>'name')>150 OR length(coalesce(p_body->>'city',''))>150 THEN RAISE EXCEPTION 'invalid_store';END IF;
  storeid:=(p_body->>'new_store_id')::uuid;IF storeid IS NULL THEN RAISE EXCEPTION 'store_id_required';END IF;
  IF EXISTS(SELECT 1 FROM tj.org_locations WHERE id=storeid AND organization_id<>org) THEN RAISE EXCEPTION 'store_unavailable';END IF;
  INSERT INTO tj.org_locations(id,organization_id,location_type,name,city,timezone,is_active) VALUES(storeid,org,'store',btrim(p_body->>'name'),nullif(btrim(p_body->>'city'),''),'America/Toronto',true) ON CONFLICT(id) DO NOTHING;
 ELSIF act IN('deactivate_store','activate_store') THEN
  IF sid IS NULL OR NOT EXISTS(SELECT 1 FROM tj.org_locations WHERE id=sid AND organization_id=org AND location_type='store') THEN RAISE EXCEPTION 'store_unavailable';END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('up-floor:'||sid::text,0));
  IF act='deactivate_store' AND (EXISTS(SELECT 1 FROM tj.iq_shift_records WHERE organization_id=org AND store_id=sid AND is_active) OR EXISTS(SELECT 1 FROM tj.iq_customer_interactions WHERE organization_id=org AND store_id=sid AND ended_at IS NULL)) THEN RETURN jsonb_build_object('ok',false,'error','active_store_work_required');END IF;
  IF act='deactivate_store' AND (SELECT count(*) FROM tj.org_locations WHERE organization_id=org AND location_type='store' AND is_active)<=1 THEN RETURN jsonb_build_object('ok',false,'error','last_active_store_required');END IF;
  UPDATE tj.org_locations SET is_active=act='activate_store',closed_at=CASE WHEN act='deactivate_store' THEN coalesce(closed_at,now()) ELSE NULL END,updated_at=now() WHERE id=sid;
 ELSE RAISE EXCEPTION 'invalid_action';END IF;
 RETURN jsonb_build_object('ok',true);
EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('ok',false,'error','administration_failed','sqlstate',SQLSTATE);
END $function$
;

-- Restrictive guard also applies when other read policies allow the organization.
CREATE POLICY consolidation_location_access ON tj.org_locations AS RESTRICTIVE FOR SELECT TO authenticated USING(tj_private.aiq_store_allows(organization_id,id));
ALTER POLICY consolidation_intelligence_store_scope ON tj.intelligence_events USING(tj_private.aiq_store_allows(organization_id,store_id));


CREATE OR REPLACE FUNCTION tj_private.crm_deal_auto_location() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $function$
BEGIN
 IF NEW.owner_user_id IS NOT NULL AND NEW.location_id IS NULL AND (TG_OP='INSERT' OR OLD.owner_user_id IS DISTINCT FROM NEW.owner_user_id) THEN
  SELECT olm.location_id INTO NEW.location_id FROM tj.org_location_members olm JOIN tj.org_locations l ON l.id=olm.location_id AND l.organization_id=olm.organization_id AND l.is_active
  WHERE olm.user_id=NEW.owner_user_id AND olm.organization_id=NEW.organization_id AND olm.is_active ORDER BY olm.is_primary DESC,olm.created_at,olm.id LIMIT 1;
 END IF;
 RETURN NEW;
END $function$;
NOTIFY pgrst,'reload schema';

