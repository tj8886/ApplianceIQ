CREATE OR REPLACE FUNCTION tj_private.validate_crm_container_write() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
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
 IF TG_TABLE_NAME='companies' THEN
 IF NEW.annual_revenue_potential IS NOT NULL AND (NEW.annual_revenue_potential<0 OR NEW.annual_revenue_potential::text IN('NaN','Infinity','-Infinity')) THEN RAISE EXCEPTION 'Invalid revenue potential';END IF;
 END IF;
 NEW.updated_at:=now();RETURN NEW;
END; $$;
