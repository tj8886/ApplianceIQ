CREATE OR REPLACE FUNCTION tj_private.audit_crm_deal_write() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=tj_private.current_source_user_id(); prof uuid;
BEGIN
 SELECT id INTO prof FROM tj.profiles WHERE user_id=actor LIMIT 1;
 IF TG_OP='UPDATE' AND NEW.stage IS DISTINCT FROM OLD.stage THEN
 INSERT INTO tj.crm_stage_history(deal_id,organization_id,from_stage,to_stage,changed_by,duration_seconds) VALUES(NEW.id,NEW.organization_id,OLD.stage,NEW.stage,prof,least(2147483647,greatest(0,extract(epoch FROM now()-coalesce(OLD.stage_entered_at,OLD.created_at,now()))))::integer);
 END IF;
 IF TG_OP='UPDATE' AND NEW.temperature IS DISTINCT FROM OLD.temperature AND NEW.temperature IS NOT NULL THEN
 INSERT INTO tj.crm_temperature_history(organization_id,entity_type,entity_id,from_temperature,to_temperature,changed_by,reason) VALUES(NEW.organization_id,'deal',NEW.id,OLD.temperature,NEW.temperature,CASE WHEN prof IS NOT NULL THEN actor ELSE NULL END,NEW.temperature_reason);
 END IF;
 IF TG_OP='UPDATE' AND coalesce(NEW.is_archived,false) IS DISTINCT FROM coalesce(OLD.is_archived,false) THEN
 INSERT INTO tj.crm_archive_log(organization_id,actor_user_id,record_type,record_id,action,reason,record_snapshot) VALUES(NEW.organization_id,actor,'deal',NEW.id,CASE WHEN NEW.is_archived THEN 'archived' ELSE 'restored' END,NEW.archive_reason,to_jsonb(OLD));
 END IF;
 RETURN NEW;
END; $$;
CREATE OR REPLACE FUNCTION tj_private.validate_crm_native_write() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=tj_private.current_source_user_id(); owner_id uuid; prof uuid; native boolean:=current_setting('role',true)='authenticated';
BEGIN
 IF TG_OP='UPDATE' AND (NEW.id IS DISTINCT FROM OLD.id OR NEW.organization_id IS DISTINCT FROM OLD.organization_id) THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Record and organization identity cannot change'; END IF;
 IF native AND actor IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Activated identity required'; END IF;
 IF TG_TABLE_NAME='crm_deals' THEN
 IF native THEN
 IF NEW.owner_user_id IS NULL AND TG_OP='INSERT' THEN NEW.owner_user_id:=actor; END IF;
 IF NOT tj_private.can_write_crm_owner(NEW.organization_id,NEW.owner_user_id) OR NOT tj.aiq_store_allows(NEW.organization_id,NEW.location_id) THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Deal owner or store denied'; END IF;
 IF NEW.location_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.org_locations l WHERE l.id=NEW.location_id AND l.organization_id=NEW.organization_id AND l.is_active) THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Deal location must belong to the organization'; END IF;
 IF NEW.contact_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.contacts p WHERE p.id=NEW.contact_id AND p.organization_id=NEW.organization_id AND p.deleted_at IS NULL) OR NEW.company_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.companies p WHERE p.id=NEW.company_id AND p.organization_id=NEW.organization_id) OR NEW.buying_group_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.crm_buying_groups p WHERE p.id=NEW.buying_group_id AND p.organization_id=NEW.organization_id) THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Deal parent must belong to the organization'; END IF;
 END IF;
 IF nullif(btrim(NEW.title),'') IS NULL OR nullif(btrim(NEW.stage),'') IS NULL THEN RAISE EXCEPTION 'Deal title and stage required'; END IF;
 IF NEW.value_amount IS NOT NULL AND (NEW.value_amount::text IN('NaN','Infinity','-Infinity') OR NEW.value_amount<0) OR NEW.margin_pct IS NOT NULL AND (NEW.margin_pct::text IN('NaN','Infinity','-Infinity') OR NEW.margin_pct NOT BETWEEN -100 AND 100) THEN RAISE EXCEPTION 'Invalid deal amount or margin'; END IF;
 NEW.margin_amount:=CASE WHEN NEW.value_amount IS NOT NULL AND NEW.margin_pct IS NOT NULL THEN round(NEW.value_amount*NEW.margin_pct/100,2) ELSE NULL END;
 NEW.days_inactive:=greatest(0,extract(day FROM now()-coalesce(NEW.last_contact_at,NEW.created_at,now()))::integer);
 IF TG_OP='INSERT' OR NEW.stage IS DISTINCT FROM OLD.stage THEN NEW.stage_entered_at:=now(); END IF;
 IF TG_OP='UPDATE' AND NEW.temperature IS DISTINCT FROM OLD.temperature THEN NEW.temperature_changed_at:=now();NEW.temperature_changed_by:=CASE WHEN EXISTS(SELECT 1 FROM tj.profiles p WHERE p.user_id=actor) THEN actor ELSE NULL END; END IF;
 ELSIF TG_TABLE_NAME='crm_tasks' THEN
 IF native THEN
 IF NEW.assignee_user_id IS NULL AND TG_OP='INSERT' THEN NEW.assignee_user_id:=actor; END IF;
 IF NOT tj_private.can_write_crm_owner(NEW.organization_id,NEW.assignee_user_id) THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Task assignee denied'; END IF;
 IF NEW.deal_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.crm_deals d WHERE d.id=NEW.deal_id AND d.organization_id=NEW.organization_id AND d.deleted_at IS NULL AND tj.aiq_scope_allows(d.organization_id,d.owner_user_id) AND tj.aiq_store_allows(d.organization_id,d.location_id)) OR NEW.contact_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.contacts c WHERE c.id=NEW.contact_id AND c.organization_id=NEW.organization_id AND c.deleted_at IS NULL) OR NEW.company_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.companies c WHERE c.id=NEW.company_id AND c.organization_id=NEW.organization_id) THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Task parent denied'; END IF;
 END IF;
 IF nullif(btrim(NEW.title),'') IS NULL THEN RAISE EXCEPTION 'Task title required'; END IF;
 ELSIF TG_TABLE_NAME='crm_activity_goals' THEN
 IF native AND (NOT tj_private.can_write_crm_owner(NEW.organization_id,NEW.user_id)) THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Goal administration denied'; END IF;
 IF TG_OP='UPDATE' AND NEW.user_id IS DISTINCT FROM OLD.user_id THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Goal user cannot change'; END IF;
 IF least(coalesce(NEW.calls_target,0),coalesce(NEW.emails_target,0),coalesce(NEW.meetings_target,0),coalesce(NEW.deals_target,0))<0 OR NEW.revenue_target IS NOT NULL AND (NEW.revenue_target<0 OR NEW.revenue_target::text IN('NaN','Infinity','-Infinity')) THEN RAISE EXCEPTION 'Invalid activity target'; END IF;
 ELSIF TG_TABLE_NAME='crm_postmortems' AND native THEN
 SELECT p.id INTO prof FROM tj.profiles p WHERE p.user_id=actor AND (NEW.salesperson_id=p.id OR NEW.salesperson_id=p.user_id OR NEW.salesperson_id IS NULL) LIMIT 1;
 IF prof IS NULL OR NOT tj_private.can_write_crm_review(NEW.organization_id,prof) THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Only personal reflections can be written'; END IF;
 NEW.salesperson_id:=prof;
 IF TG_OP='UPDATE' AND (NEW.salesperson_id IS DISTINCT FROM OLD.salesperson_id OR NEW.deal_id IS DISTINCT FROM OLD.deal_id) THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Reflection identity cannot change'; END IF;
 IF NOT EXISTS(SELECT 1 FROM tj.crm_deals d WHERE d.id=NEW.deal_id AND d.organization_id=NEW.organization_id AND d.deleted_at IS NULL AND tj.aiq_scope_allows(d.organization_id,d.owner_user_id) AND tj.aiq_store_allows(d.organization_id,d.location_id)) THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Reflection deal denied'; END IF;
 END IF;
 NEW.updated_at:=now();RETURN NEW;
END; $$;
ALTER POLICY consolidation_native_insert ON tj.crm_activity_goals WITH CHECK(tj_private.can_write_crm_owner(organization_id,user_id));
ALTER POLICY consolidation_native_update ON tj.crm_activity_goals USING(tj_private.can_write_crm_owner(organization_id,user_id)) WITH CHECK(tj_private.can_write_crm_owner(organization_id,user_id));
