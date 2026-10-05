-- Field parent inheritance and scoped catalog reads; no write grants or external effects.
CREATE FUNCTION tj_private.can_read_field_record(p_client uuid,p_store uuid,p_owner uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM tj.field_clients c JOIN tj.organizations o ON o.id=c.organization_id
 WHERE c.id=p_client AND c.status='active' AND o.status='active' AND o.deleted_at IS NULL
 AND tj.is_field_client_member(c.id)
 AND (tj_private.can_read_runtime_org(c.organization_id) AND tj.aiq_scope_allows(c.organization_id,p_owner) OR tj_private.is_source_self(p_owner))
 AND (p_store IS NULL OR EXISTS(SELECT 1 FROM tj.field_stores s JOIN tj.org_locations l ON l.id=s.org_location_id
 WHERE s.id=p_store AND l.organization_id=c.organization_id AND l.is_active AND s.status='active'
 AND tj.aiq_store_allows(c.organization_id,l.id))));
$$;
CREATE FUNCTION tj_private.can_read_field_store(p_store uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM tj.field_stores s JOIN tj.org_locations l ON l.id=s.org_location_id
 WHERE s.id=p_store AND s.status='active' AND l.is_active AND tj_private.can_read_runtime_org(l.organization_id) AND tj.aiq_store_allows(l.organization_id,l.id));
$$;
CREATE FUNCTION tj_private.can_read_field_comment(p_action uuid,p_visit uuid,p_finding uuid,p_author uuid,p_visibility text) RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE c uuid; s uuid; u uuid; org uuid;
BEGIN
 IF p_action IS NOT NULL THEN
 SELECT a.client_id,a.store_id,a.assigned_to_user_id INTO c,s,u FROM tj.field_actions a WHERE a.id=p_action;
 ELSIF p_visit IS NOT NULL THEN
 SELECT v.client_id,v.store_id,v.rep_user_id INTO c,s,u FROM tj.field_visits v WHERE v.id=p_visit;
 ELSIF p_finding IS NOT NULL THEN
 SELECT f.client_id,f.store_id,v.rep_user_id INTO c,s,u FROM tj.field_findings f JOIN tj.field_visits v ON v.id=f.visit_id WHERE f.id=p_finding AND v.client_id=f.client_id;
 ELSE RETURN false; END IF;
 IF NOT tj_private.can_read_field_record(c,s,u) THEN RETURN false; END IF;
 IF p_visit IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.field_visits v WHERE v.id=p_visit AND v.client_id=c AND v.store_id IS NOT DISTINCT FROM s) THEN RETURN false; END IF;
 IF p_finding IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.field_findings f WHERE f.id=p_finding AND f.client_id=c AND f.store_id IS NOT DISTINCT FROM s) THEN RETURN false; END IF;
 SELECT organization_id INTO org FROM tj.field_clients WHERE id=c;
 RETURN p_visibility='all' OR tj_private.is_source_self(p_author) OR tj.is_org_admin(org)
 OR (p_visibility='manufacturer' AND EXISTS(SELECT 1 FROM tj.field_manufacturer_users m WHERE m.client_id=c AND m.user_id=tj_private.current_source_user_id() AND m.status='active'));
END; $$;
REVOKE ALL ON FUNCTION tj_private.can_read_field_record(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.can_read_field_record(uuid,uuid,uuid) TO authenticated;
REVOKE ALL ON FUNCTION tj_private.can_read_field_store(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.can_read_field_store(uuid) TO authenticated;
REVOKE ALL ON FUNCTION tj_private.can_read_field_comment(uuid,uuid,uuid,uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.can_read_field_comment(uuid,uuid,uuid,uuid,text) TO authenticated;
DO $guard$ BEGIN IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='tj.field_assignments'::regclass) OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj.field_assignments'::regclass) THEN RAISE EXCEPTION 'Review existing RLS: field_assignments'; END IF; END $guard$;
CREATE POLICY consolidation_app_read ON tj.field_assignments FOR SELECT TO authenticated USING(tj_private.can_read_field_record(client_id,store_id,rep_user_id));
GRANT SELECT ON tj.field_assignments TO authenticated;
DO $guard$ BEGIN IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='tj.field_visits'::regclass) OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj.field_visits'::regclass) THEN RAISE EXCEPTION 'Review existing RLS: field_visits'; END IF; END $guard$;
CREATE POLICY consolidation_app_read ON tj.field_visits FOR SELECT TO authenticated USING(tj_private.can_read_field_record(client_id,store_id,rep_user_id));
GRANT SELECT ON tj.field_visits TO authenticated;
DO $guard$ BEGIN IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='tj.field_stores'::regclass) OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj.field_stores'::regclass) THEN RAISE EXCEPTION 'Review existing RLS: field_stores'; END IF; END $guard$;
CREATE POLICY consolidation_app_read ON tj.field_stores FOR SELECT TO authenticated USING(tj_private.can_read_field_store(id));
GRANT SELECT ON tj.field_stores TO authenticated;
DO $guard$ BEGIN IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='tj.field_checklist_responses'::regclass) OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj.field_checklist_responses'::regclass) THEN RAISE EXCEPTION 'Review existing RLS: field_checklist_responses'; END IF; END $guard$;
CREATE POLICY consolidation_app_read ON tj.field_checklist_responses FOR SELECT TO authenticated USING(EXISTS(SELECT 1 FROM tj.field_visits v WHERE v.id=visit_id));
GRANT SELECT ON tj.field_checklist_responses TO authenticated;
DO $guard$ BEGIN IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='tj.field_competitive_intel'::regclass) OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj.field_competitive_intel'::regclass) THEN RAISE EXCEPTION 'Review existing RLS: field_competitive_intel'; END IF; END $guard$;
CREATE POLICY consolidation_app_read ON tj.field_competitive_intel FOR SELECT TO authenticated USING(EXISTS(SELECT 1 FROM tj.field_visits v WHERE v.id=visit_id AND v.store_id=field_competitive_intel.store_id));
GRANT SELECT ON tj.field_competitive_intel TO authenticated;
DO $guard$ BEGIN IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='tj.field_media'::regclass) OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj.field_media'::regclass) THEN RAISE EXCEPTION 'Review existing RLS: field_media'; END IF; END $guard$;
CREATE POLICY consolidation_app_read ON tj.field_media FOR SELECT TO authenticated USING(EXISTS(SELECT 1 FROM tj.field_visits v WHERE v.id=visit_id));
GRANT SELECT ON tj.field_media TO authenticated;
DO $guard$ BEGIN IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='tj.field_action_status_history'::regclass) OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj.field_action_status_history'::regclass) THEN RAISE EXCEPTION 'Review existing RLS: field_action_status_history'; END IF; END $guard$;
CREATE POLICY consolidation_app_read ON tj.field_action_status_history FOR SELECT TO authenticated USING(EXISTS(SELECT 1 FROM tj.field_actions a WHERE a.id=action_id AND tj_private.can_read_field_record(a.client_id,a.store_id,a.assigned_to_user_id)));
GRANT SELECT ON tj.field_action_status_history TO authenticated;
DO $guard$ BEGIN IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='tj.field_action_comments'::regclass) OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj.field_action_comments'::regclass) THEN RAISE EXCEPTION 'Review existing RLS: field_action_comments'; END IF; END $guard$;
CREATE POLICY consolidation_app_read ON tj.field_action_comments FOR SELECT TO authenticated USING(tj_private.can_read_field_comment(action_id,visit_id,finding_id,author_user_id,visibility));
GRANT SELECT ON tj.field_action_comments TO authenticated;
DO $guard$ BEGIN IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='tj.brand_training_cards'::regclass) OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj.brand_training_cards'::regclass) THEN RAISE EXCEPTION 'Review existing RLS: brand_training_cards'; END IF; END $guard$;
CREATE POLICY consolidation_app_read ON tj.brand_training_cards FOR SELECT TO authenticated USING((organization_id IS NOT NULL AND tj_private.can_read_runtime_org(organization_id) AND (status='published' OR tj.is_org_admin(organization_id))));
GRANT SELECT ON tj.brand_training_cards TO authenticated;
DO $guard$ BEGIN IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='tj.iq_notifications'::regclass) OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj.iq_notifications'::regclass) THEN RAISE EXCEPTION 'Review existing RLS: iq_notifications'; END IF; END $guard$;
CREATE POLICY consolidation_app_read ON tj.iq_notifications FOR SELECT TO authenticated USING(tj_private.can_read_runtime_org(org_id) AND (rep_id IS NULL OR tj_private.is_source_self(rep_id) OR tj.is_org_admin(org_id)));
GRANT SELECT ON tj.iq_notifications TO authenticated;
DO $guard$ BEGIN IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='tj.mfr_vendors'::regclass) OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj.mfr_vendors'::regclass) THEN RAISE EXCEPTION 'Review existing RLS: mfr_vendors'; END IF; END $guard$;
CREATE POLICY consolidation_app_read ON tj.mfr_vendors FOR SELECT TO authenticated USING((SELECT tj_private.has_active_mapped_org()) AND (status='active' OR EXISTS(SELECT 1 FROM tj.mfr_members m WHERE m.vendor_id=mfr_vendors.id AND tj_private.is_source_self(m.user_id))));
GRANT SELECT ON tj.mfr_vendors TO authenticated;
