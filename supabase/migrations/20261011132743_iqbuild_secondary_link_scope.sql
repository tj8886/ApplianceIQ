CREATE FUNCTION tj_private.iqbuild_link_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE row_data jsonb:=to_jsonb(NEW);old_data jsonb;ref record;ref_id uuid;ref_org uuid;ref_location uuid;source_package uuid;builder_source uuid;field text;
BEGIN
 IF tj_private.current_source_user_id() IS NULL OR NOT tj_private.iqbuild_access(NEW.organization_id) THEN RAISE EXCEPTION 'organization_access_denied' USING ERRCODE='42501';END IF;
 IF TG_TABLE_NAME='iqbuild_projects' THEN
  IF NEW.crm_contact_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.contacts WHERE id=NEW.crm_contact_id AND organization_id=NEW.organization_id AND deleted_at IS NULL) THEN RAISE EXCEPTION 'crm_contact_access_denied' USING ERRCODE='42501';END IF;
  IF NEW.crm_company_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.companies WHERE id=NEW.crm_company_id AND organization_id=NEW.organization_id AND deleted_at IS NULL) THEN RAISE EXCEPTION 'crm_company_access_denied' USING ERRCODE='42501';END IF;
 END IF;
 IF TG_TABLE_NAME='iqbuild_package_items' AND row_data->>'speciq_product_id' IS NOT NULL THEN
  SELECT package_id INTO source_package FROM tj.speciq_package_products WHERE id=NEW.speciq_product_id AND organization_id=NEW.organization_id;
  IF source_package IS NULL OR NOT tj_private.speciq_package_store_allows(NEW.organization_id,source_package) THEN RAISE EXCEPTION 'speciq_product_access_denied' USING ERRCODE='42501';END IF;
  SELECT speciq_package_id INTO builder_source FROM tj.iqbuild_packages WHERE id=NEW.package_id AND organization_id=NEW.organization_id;
  IF builder_source IS NOT NULL AND builder_source IS DISTINCT FROM source_package THEN RAISE EXCEPTION 'speciq_product_package_mismatch' USING ERRCODE='23514';END IF;
 END IF;
 -- Secondary references also need store checks, including packages without a root project.
 FOR ref IN SELECT * FROM (VALUES ('target_building_id','iqbuild_buildings'),('building_id','iqbuild_buildings'),('floor_id','iqbuild_floors'),('unit_id','iqbuild_units'),('unit_appliance_id','iqbuild_unit_appliances'),('delivery_id','iqbuild_deliveries'),('replaces_appliance_id','iqbuild_unit_appliances'),('replacement_for','iqbuild_unit_appliances'),('package_id','iqbuild_packages'))v(col,tbl) LOOP
  IF row_data->>ref.col IS NOT NULL THEN
   ref_id:=(row_data->>ref.col)::uuid;
   EXECUTE format('SELECT organization_id,location_id FROM tj.%I WHERE id=$1',ref.tbl) INTO ref_org,ref_location USING ref_id;
   IF ref_org IS DISTINCT FROM NEW.organization_id OR NOT tj.aiq_store_allows(ref_org,ref_location) THEN RAISE EXCEPTION 'linked_store_access_denied' USING ERRCODE='42501';END IF;
  END IF;
 END LOOP;
 IF TG_OP='UPDATE' THEN
  old_data:=to_jsonb(OLD);
  IF old_data->>'source_snapshot' IS NOT NULL THEN
   FOREACH field IN ARRAY ARRAY['source_snapshot','source_recorded_at','speciq_package_id','speciq_product_id'] LOOP
    IF old_data->field IS DISTINCT FROM row_data->field THEN RAISE EXCEPTION 'recorded_source_immutable' USING ERRCODE='42501';END IF;
   END LOOP;
  END IF;
  IF TG_TABLE_NAME='iqbuild_projects' AND coalesce((old_data->>'imported_from_crm')::boolean,false) THEN
   FOREACH field IN ARRAY ARRAY['import_summary','imported_from_crm','crm_deal_id','crm_contact_id','crm_company_id','speciq_project_id'] LOOP
    IF old_data->field IS DISTINCT FROM row_data->field THEN RAISE EXCEPTION 'import_source_immutable' USING ERRCODE='42501';END IF;
   END LOOP;
  END IF;
 END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION tj_private.iqbuild_link_guard() FROM PUBLIC,anon,authenticated,service_role;
DO $$DECLARE t text;BEGIN
 FOREACH t IN ARRAY ARRAY['iqbuild_projects','iqbuild_buildings','iqbuild_floors','iqbuild_units','iqbuild_packages','iqbuild_package_items','iqbuild_deliveries','iqbuild_delivery_items','iqbuild_unit_appliances','iqbuild_unit_milestones','iqbuild_project_contacts','iqbuild_team_members','iqbuild_installations','iqbuild_installation_parts','iqbuild_signoffs','iqbuild_activity_log'] LOOP
  EXECUTE format('CREATE TRIGGER iqbuild_link_guard BEFORE INSERT OR UPDATE ON tj.%I FOR EACH ROW EXECUTE FUNCTION tj_private.iqbuild_link_guard()',t);
 END LOOP;
END $$;
ALTER TABLE tj.iqbuild_package_items ALTER COLUMN unit_cost DROP DEFAULT;
ALTER TABLE tj.iqbuild_packages ALTER COLUMN base_cost DROP DEFAULT;
ALTER TABLE tj.iqbuild_unit_appliances ALTER COLUMN original_cost DROP DEFAULT;
NOTIFY pgrst,'reload schema';
