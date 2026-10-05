-- Creator ownership for CRM containers without a native owner field.
CREATE TABLE tj_private.crm_container_creators(record_kind text NOT NULL CHECK(record_kind IN('companies','crm_buying_groups')),record_id uuid NOT NULL,organization_id uuid NOT NULL REFERENCES tj.organizations(id),source_user_id uuid NOT NULL REFERENCES tj.source_auth_users(id),created_at timestamptz NOT NULL DEFAULT now(),PRIMARY KEY(record_kind,record_id));
ALTER TABLE tj_private.crm_container_creators ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj_private.crm_container_creators FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj_private.can_access_crm_container(p_kind text,p_id uuid,p_org uuid,p_write boolean DEFAULT false) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT tj_private.can_read_runtime_org(p_org) AND (NOT p_write OR EXISTS(SELECT 1 FROM tj.organization_members m WHERE m.organization_id=p_org AND m.user_id=(SELECT tj_private.current_source_user_id()) AND m.status='active' AND m.role IN('owner','admin','manager','member')))
 AND (tj.is_org_admin(p_org) OR EXISTS(SELECT 1 FROM tj_private.crm_container_creators c WHERE c.record_kind=p_kind AND c.record_id=p_id AND c.organization_id=p_org AND c.source_user_id=(SELECT tj_private.current_source_user_id())));
$$;
CREATE FUNCTION tj_private.can_write_crm_relation(p_kind text,p_parent uuid,p_contact uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT CASE WHEN p_kind='crm_deal_participants' THEN EXISTS(SELECT 1 FROM tj.crm_deals d JOIN tj.contacts c ON c.id=p_contact AND c.organization_id=d.organization_id AND c.deleted_at IS NULL WHERE d.id=p_parent AND d.deleted_at IS NULL AND tj_private.can_write_crm_owner(d.organization_id,d.owner_user_id) AND tj.aiq_store_allows(d.organization_id,d.location_id))
 WHEN p_kind='crm_buying_group_members' THEN EXISTS(SELECT 1 FROM tj.crm_buying_groups g JOIN tj.contacts c ON c.id=p_contact AND c.organization_id=g.organization_id AND c.deleted_at IS NULL WHERE g.id=p_parent AND coalesce(g.is_archived,false)=false AND tj_private.can_access_crm_container('crm_buying_groups',g.id,g.organization_id,true))
 ELSE false END;
$$;
REVOKE ALL ON FUNCTION tj_private.can_access_crm_container(text,uuid,uuid,boolean),tj_private.can_write_crm_relation(text,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.can_access_crm_container(text,uuid,uuid,boolean),tj_private.can_write_crm_relation(text,uuid,uuid) TO authenticated;
CREATE FUNCTION tj_private.validate_crm_container_write() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=tj_private.current_source_user_id();native boolean:=current_setting('role',true)='authenticated';
BEGIN
 IF TG_OP='UPDATE' AND (NEW.id IS DISTINCT FROM OLD.id OR NEW.organization_id IS DISTINCT FROM OLD.organization_id) THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Container identity cannot change';END IF;
 IF native THEN
 IF actor IS NULL OR NOT tj_private.can_read_runtime_org(NEW.organization_id) OR NOT EXISTS(SELECT 1 FROM tj.organization_members m WHERE m.organization_id=NEW.organization_id AND m.user_id=actor AND m.status='active' AND m.role IN('owner','admin','manager','member')) THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Writable organization required';END IF;
 IF TG_OP='INSERT' THEN INSERT INTO tj_private.crm_container_creators(record_kind,record_id,organization_id,source_user_id) VALUES(TG_TABLE_NAME,NEW.id,NEW.organization_id,actor);
 ELSIF NOT tj_private.can_access_crm_container(TG_TABLE_NAME,NEW.id,NEW.organization_id,true) THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Container write denied';END IF;
 IF TG_TABLE_NAME='companies' THEN
 IF NOT tj.is_org_admin(NEW.organization_id) AND ((TG_OP='INSERT' AND (NEW.credit_status IS DISTINCT FROM 'not_assessed' OR NEW.account_terms IS NOT NULL)) OR (TG_OP='UPDATE' AND (NEW.credit_status IS DISTINCT FROM OLD.credit_status OR NEW.account_terms IS DISTINCT FROM OLD.account_terms))) THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Credit and account terms require organization administration';END IF;
 ELSIF TG_TABLE_NAME='crm_buying_groups' THEN
 IF NEW.company_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.companies c WHERE c.id=NEW.company_id AND c.organization_id=NEW.organization_id AND c.deleted_at IS NULL) OR NEW.primary_contact_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.contacts c WHERE c.id=NEW.primary_contact_id AND c.organization_id=NEW.organization_id AND c.deleted_at IS NULL) THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Container parent must share organization';END IF;
 END IF;
 END IF;
 IF nullif(btrim(NEW.name),'') IS NULL THEN RAISE EXCEPTION 'Container name required';END IF;
 IF TG_TABLE_NAME='companies' AND NEW.annual_revenue_potential IS NOT NULL AND (NEW.annual_revenue_potential<0 OR NEW.annual_revenue_potential::text IN('NaN','Infinity','-Infinity')) THEN RAISE EXCEPTION 'Invalid revenue potential';END IF;
 NEW.updated_at:=now();RETURN NEW;
END; $$;
CREATE FUNCTION tj_private.validate_crm_relation_write() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE parent uuid;
BEGIN
 IF TG_OP='UPDATE' AND NEW.id IS DISTINCT FROM OLD.id THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Link identity cannot change';END IF;
 IF TG_TABLE_NAME='crm_deal_participants' THEN
 parent:=NEW.deal_id;IF TG_OP='UPDATE' AND NEW.deal_id IS DISTINCT FROM OLD.deal_id THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Link parent cannot change';END IF;
 ELSE parent:=NEW.buying_group_id;IF TG_OP='UPDATE' AND NEW.buying_group_id IS DISTINCT FROM OLD.buying_group_id THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Link parent cannot change';END IF;END IF;
 IF current_setting('role',true)='authenticated' AND NOT tj_private.can_write_crm_relation(TG_TABLE_NAME,parent,NEW.contact_id) THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Link ownership or parent organization denied';END IF;
 RETURN NEW;
END; $$;
REVOKE ALL ON FUNCTION tj_private.validate_crm_container_write(),tj_private.validate_crm_relation_write() FROM PUBLIC,anon,authenticated,service_role;
ALTER POLICY consolidation_app_read ON tj.crm_buying_groups USING(tj_private.can_access_crm_container('crm_buying_groups',id,organization_id,false));
DO $guard$ BEGIN IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj.companies'::regclass AND polcmd IN('a','w','*')) OR EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='tj.companies'::regclass AND NOT tgisinternal) THEN RAISE EXCEPTION 'Review existing container writes';END IF;END $guard$;
CREATE TRIGGER consolidation_validate_related_write BEFORE INSERT OR UPDATE ON tj.companies FOR EACH ROW EXECUTE FUNCTION tj_private.validate_crm_container_write();
CREATE POLICY consolidation_related_insert ON tj.companies FOR INSERT TO authenticated WITH CHECK(tj_private.can_access_crm_container('companies',id,organization_id,true));
CREATE POLICY consolidation_related_update ON tj.companies FOR UPDATE TO authenticated USING(tj_private.can_access_crm_container('companies',id,organization_id,true)) WITH CHECK(tj_private.can_access_crm_container('companies',id,organization_id,true));
GRANT INSERT(organization_id,name,display_name,legal_name,business_type,industry,main_phone,general_email,website,city,region,country_code,account_classification,annual_revenue_potential,credit_status,account_terms,notes,source),UPDATE(organization_id,name,display_name,legal_name,business_type,industry,main_phone,general_email,website,city,region,country_code,account_classification,annual_revenue_potential,credit_status,account_terms,notes,source) ON tj.companies TO authenticated;
DO $guard$ BEGIN IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj.crm_buying_groups'::regclass AND polcmd IN('a','w','*')) OR EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='tj.crm_buying_groups'::regclass AND NOT tgisinternal) THEN RAISE EXCEPTION 'Review existing container writes';END IF;END $guard$;
CREATE TRIGGER consolidation_validate_related_write BEFORE INSERT OR UPDATE ON tj.crm_buying_groups FOR EACH ROW EXECUTE FUNCTION tj_private.validate_crm_container_write();
CREATE POLICY consolidation_related_insert ON tj.crm_buying_groups FOR INSERT TO authenticated WITH CHECK(tj_private.can_access_crm_container('crm_buying_groups',id,organization_id,true));
CREATE POLICY consolidation_related_update ON tj.crm_buying_groups FOR UPDATE TO authenticated USING(tj_private.can_access_crm_container('crm_buying_groups',id,organization_id,true)) WITH CHECK(tj_private.can_access_crm_container('crm_buying_groups',id,organization_id,true));
GRANT INSERT(organization_id,name,group_type,primary_contact_id,communication_default,company_id,notes,is_archived,archived_at),UPDATE(organization_id,name,group_type,primary_contact_id,communication_default,company_id,notes,is_archived,archived_at) ON tj.crm_buying_groups TO authenticated;
DO $guard$ BEGIN IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj.crm_buying_group_members'::regclass AND polcmd IN('a','w','*')) OR EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='tj.crm_buying_group_members'::regclass AND NOT tgisinternal) THEN RAISE EXCEPTION 'Review existing container writes';END IF;END $guard$;
CREATE TRIGGER consolidation_validate_related_write BEFORE INSERT OR UPDATE ON tj.crm_buying_group_members FOR EACH ROW EXECUTE FUNCTION tj_private.validate_crm_relation_write();
CREATE POLICY consolidation_related_insert ON tj.crm_buying_group_members FOR INSERT TO authenticated WITH CHECK(tj_private.can_write_crm_relation('crm_buying_group_members',buying_group_id,contact_id));
CREATE POLICY consolidation_related_update ON tj.crm_buying_group_members FOR UPDATE TO authenticated USING(tj_private.can_write_crm_relation('crm_buying_group_members',buying_group_id,contact_id)) WITH CHECK(tj_private.can_write_crm_relation('crm_buying_group_members',buying_group_id,contact_id));
GRANT INSERT(buying_group_id,contact_id,buying_role,is_primary,communication_preference,share_quotes,share_products_filter,notes),UPDATE(buying_group_id,contact_id,buying_role,is_primary,communication_preference,share_quotes,share_products_filter,notes) ON tj.crm_buying_group_members TO authenticated;
DO $guard$ BEGIN IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj.crm_deal_participants'::regclass AND polcmd IN('a','w','*')) OR EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='tj.crm_deal_participants'::regclass AND NOT tgisinternal) THEN RAISE EXCEPTION 'Review existing container writes';END IF;END $guard$;
CREATE TRIGGER consolidation_validate_related_write BEFORE INSERT OR UPDATE ON tj.crm_deal_participants FOR EACH ROW EXECUTE FUNCTION tj_private.validate_crm_relation_write();
CREATE POLICY consolidation_related_insert ON tj.crm_deal_participants FOR INSERT TO authenticated WITH CHECK(tj_private.can_write_crm_relation('crm_deal_participants',deal_id,contact_id));
CREATE POLICY consolidation_related_update ON tj.crm_deal_participants FOR UPDATE TO authenticated USING(tj_private.can_write_crm_relation('crm_deal_participants',deal_id,contact_id)) WITH CHECK(tj_private.can_write_crm_relation('crm_deal_participants',deal_id,contact_id));
GRANT INSERT(deal_id,contact_id,buying_role,is_primary,communication_preference,notes),UPDATE(deal_id,contact_id,buying_role,is_primary,communication_preference,notes) ON tj.crm_deal_participants TO authenticated;
