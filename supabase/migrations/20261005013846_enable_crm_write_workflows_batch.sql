-- Native CRM writes with immutable tenant identity and explicit business validation.
CREATE FUNCTION tj_private.can_write_crm_owner(p_org uuid,p_owner uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT tj_private.can_read_runtime_org(p_org) AND EXISTS(SELECT 1 FROM tj.organization_members me WHERE me.organization_id=p_org AND me.user_id=(SELECT tj_private.current_source_user_id()) AND me.status='active' AND me.role IN('owner','admin','manager','member'))
 AND (tj_private.is_source_self(p_owner) OR tj.is_org_admin(p_org))
 AND EXISTS(SELECT 1 FROM tj.organization_members target WHERE target.organization_id=p_org AND target.user_id=p_owner AND target.status='active');
$$;
CREATE FUNCTION tj_private.can_write_crm_review(p_org uuid,p_profile uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM tj.profiles p WHERE (p.id=p_profile OR p.user_id=p_profile) AND tj_private.is_source_self(p.user_id) AND tj_private.can_write_crm_owner(p_org,p.user_id));
$$;
REVOKE ALL ON FUNCTION tj_private.can_write_crm_owner(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION tj_private.can_write_crm_review(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.can_write_crm_owner(uuid,uuid),tj_private.can_write_crm_review(uuid,uuid) TO authenticated;
CREATE FUNCTION tj_private.validate_crm_native_write() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
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
 IF native AND (NOT tj_private.can_read_runtime_org(NEW.organization_id) OR NOT tj.is_org_admin(NEW.organization_id) OR NOT EXISTS(SELECT 1 FROM tj.organization_members m WHERE m.organization_id=NEW.organization_id AND m.user_id=NEW.user_id AND m.status='active')) THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='Goal administration denied'; END IF;
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
REVOKE ALL ON FUNCTION tj_private.validate_crm_native_write() FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj_private.audit_crm_deal_write() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=tj_private.current_source_user_id();
BEGIN
 IF TG_OP='UPDATE' AND NEW.stage IS DISTINCT FROM OLD.stage THEN
 INSERT INTO tj.crm_stage_history(deal_id,organization_id,from_stage,to_stage,changed_by,duration_seconds) VALUES(NEW.id,NEW.organization_id,OLD.stage,NEW.stage,actor,least(2147483647,greatest(0,extract(epoch FROM now()-coalesce(OLD.stage_entered_at,OLD.created_at,now()))))::integer);
 END IF;
 IF TG_OP='UPDATE' AND NEW.temperature IS DISTINCT FROM OLD.temperature AND NEW.temperature IS NOT NULL THEN
 INSERT INTO tj.crm_temperature_history(organization_id,entity_type,entity_id,from_temperature,to_temperature,changed_by,reason) VALUES(NEW.organization_id,'deal',NEW.id,OLD.temperature,NEW.temperature,actor,NEW.temperature_reason);
 END IF;
 IF TG_OP='UPDATE' AND coalesce(NEW.is_archived,false) IS DISTINCT FROM coalesce(OLD.is_archived,false) THEN
 INSERT INTO tj.crm_archive_log(organization_id,actor_user_id,record_type,record_id,action,reason,record_snapshot) VALUES(NEW.organization_id,actor,'deal',NEW.id,CASE WHEN NEW.is_archived THEN 'archived' ELSE 'restored' END,NEW.archive_reason,to_jsonb(OLD));
 END IF;
 RETURN NEW;
END; $$;
REVOKE ALL ON FUNCTION tj_private.audit_crm_deal_write() FROM PUBLIC,anon,authenticated,service_role;
DO $guard$ BEGIN IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj.crm_deals'::regclass AND polcmd IN('a','w','*')) OR EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='tj.crm_deals'::regclass AND NOT tgisinternal) THEN RAISE EXCEPTION 'Review existing writes/triggers: crm_deals'; END IF; END $guard$;
CREATE TRIGGER consolidation_validate_write BEFORE INSERT OR UPDATE ON tj.crm_deals FOR EACH ROW EXECUTE FUNCTION tj_private.validate_crm_native_write();
CREATE POLICY consolidation_native_insert ON tj.crm_deals FOR INSERT TO authenticated WITH CHECK(tj_private.can_write_crm_owner(organization_id,owner_user_id) AND tj.aiq_store_allows(organization_id,location_id));
CREATE POLICY consolidation_native_update ON tj.crm_deals FOR UPDATE TO authenticated USING(tj_private.can_write_crm_owner(organization_id,owner_user_id) AND tj.aiq_store_allows(organization_id,location_id)) WITH CHECK(tj_private.can_write_crm_owner(organization_id,owner_user_id) AND tj.aiq_store_allows(organization_id,location_id));
GRANT INSERT(organization_id,owner_user_id,location_id,title,stage,record_type,contact_id,company_id,buying_group_id,value_amount,margin_pct,margin_amount,value_currency,expected_close_date,quote_expiry_date,product_categories,next_action,next_action_date,priority,source,closed_at,temperature,temperature_changed_at,temperature_changed_by,temperature_reason,stage_entered_at,order_number,purchase_date,delivery_date,warranty_status,won_products,lost_reason,lost_competitor,lost_objection,future_followup_permitted,last_contact_at,is_archived,archived_at,archive_reason,quote_sent_at,updated_at),UPDATE(organization_id,owner_user_id,location_id,title,stage,record_type,contact_id,company_id,buying_group_id,value_amount,margin_pct,margin_amount,value_currency,expected_close_date,quote_expiry_date,product_categories,next_action,next_action_date,priority,source,closed_at,temperature,temperature_changed_at,temperature_changed_by,temperature_reason,stage_entered_at,order_number,purchase_date,delivery_date,warranty_status,won_products,lost_reason,lost_competitor,lost_objection,future_followup_permitted,last_contact_at,is_archived,archived_at,archive_reason,quote_sent_at,updated_at) ON tj.crm_deals TO authenticated;
DO $guard$ BEGIN IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj.crm_tasks'::regclass AND polcmd IN('a','w','*')) OR EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='tj.crm_tasks'::regclass AND NOT tgisinternal) THEN RAISE EXCEPTION 'Review existing writes/triggers: crm_tasks'; END IF; END $guard$;
CREATE TRIGGER consolidation_validate_write BEFORE INSERT OR UPDATE ON tj.crm_tasks FOR EACH ROW EXECUTE FUNCTION tj_private.validate_crm_native_write();
CREATE POLICY consolidation_native_insert ON tj.crm_tasks FOR INSERT TO authenticated WITH CHECK(tj_private.can_write_crm_owner(organization_id,assignee_user_id));
CREATE POLICY consolidation_native_update ON tj.crm_tasks FOR UPDATE TO authenticated USING(tj_private.can_write_crm_owner(organization_id,assignee_user_id)) WITH CHECK(tj_private.can_write_crm_owner(organization_id,assignee_user_id));
GRANT INSERT(organization_id,assignee_user_id,deal_id,company_id,contact_id,title,description,due_at,completed_at,priority,metadata,task_type,task_category,source,resolution_note,updated_at),UPDATE(organization_id,assignee_user_id,deal_id,company_id,contact_id,title,description,due_at,completed_at,priority,metadata,task_type,task_category,source,resolution_note,updated_at) ON tj.crm_tasks TO authenticated;
DO $guard$ BEGIN IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj.crm_activity_goals'::regclass AND polcmd IN('a','w','*')) OR EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='tj.crm_activity_goals'::regclass AND NOT tgisinternal) THEN RAISE EXCEPTION 'Review existing writes/triggers: crm_activity_goals'; END IF; END $guard$;
CREATE TRIGGER consolidation_validate_write BEFORE INSERT OR UPDATE ON tj.crm_activity_goals FOR EACH ROW EXECUTE FUNCTION tj_private.validate_crm_native_write();
CREATE POLICY consolidation_native_insert ON tj.crm_activity_goals FOR INSERT TO authenticated WITH CHECK(tj_private.can_read_runtime_org(organization_id) AND tj.is_org_admin(organization_id));
CREATE POLICY consolidation_native_update ON tj.crm_activity_goals FOR UPDATE TO authenticated USING(tj_private.can_read_runtime_org(organization_id) AND tj.is_org_admin(organization_id)) WITH CHECK(tj_private.can_read_runtime_org(organization_id) AND tj.is_org_admin(organization_id));
GRANT INSERT(organization_id,user_id,period,calls_target,emails_target,meetings_target,deals_target,revenue_target),UPDATE(organization_id,user_id,period,calls_target,emails_target,meetings_target,deals_target,revenue_target) ON tj.crm_activity_goals TO authenticated;
DO $guard$ BEGIN IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj.crm_postmortems'::regclass AND polcmd IN('a','w','*')) OR EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='tj.crm_postmortems'::regclass AND NOT tgisinternal) THEN RAISE EXCEPTION 'Review existing writes/triggers: crm_postmortems'; END IF; END $guard$;
CREATE TRIGGER consolidation_validate_write BEFORE INSERT OR UPDATE ON tj.crm_postmortems FOR EACH ROW EXECUTE FUNCTION tj_private.validate_crm_native_write();
CREATE POLICY consolidation_native_insert ON tj.crm_postmortems FOR INSERT TO authenticated WITH CHECK(tj_private.can_write_crm_review(organization_id,salesperson_id));
CREATE POLICY consolidation_native_update ON tj.crm_postmortems FOR UPDATE TO authenticated USING(tj_private.can_write_crm_review(organization_id,salesperson_id)) WITH CHECK(tj_private.can_write_crm_review(organization_id,salesperson_id));
GRANT INSERT(organization_id,deal_id,salesperson_id,review_type,salesperson_reflection,what_went_well,what_to_improve,controllability,is_recoverable,is_private,completed_at),UPDATE(organization_id,deal_id,salesperson_id,review_type,salesperson_reflection,what_went_well,what_to_improve,controllability,is_recoverable,is_private,completed_at) ON tj.crm_postmortems TO authenticated;
CREATE TRIGGER consolidation_deal_audit AFTER UPDATE ON tj.crm_deals FOR EACH ROW EXECUTE FUNCTION tj_private.audit_crm_deal_write();
