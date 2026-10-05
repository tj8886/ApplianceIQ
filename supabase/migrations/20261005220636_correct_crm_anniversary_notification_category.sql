-- Anniversary notices use the existing contact category constraint.
-- On-demand CRM housekeeping; no email, calendar service or worker schedule is activated.
CREATE OR REPLACE FUNCTION tj_private.run_crm_outreach_tasks(p_org uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=tj_private.current_source_user_id();a record;deal_owner uuid;task_id uuid;anniversaries int:=0;overdue int:=0;holiday_count int:=0;holiday_name text;holiday_days int;current_month int:=extract(month FROM CURRENT_DATE);current_day int:=extract(day FROM CURRENT_DATE);
BEGIN
 IF actor IS NULL OR NOT EXISTS(SELECT 1 FROM tj.organization_members m JOIN tj.organizations o ON o.id=m.organization_id WHERE m.organization_id=p_org AND m.user_id=actor AND m.status='active' AND m.role IN ('owner','admin','manager','super_admin') AND o.status='active' AND o.deleted_at IS NULL) THEN RAISE EXCEPTION 'access_denied' USING ERRCODE='42501';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('crm_outreach:'||p_org::text,0));
 FOR a IN SELECT * FROM tj_private.get_anniversary_outreach(p_org,14) ORDER BY deal_id LIMIT 200 LOOP
  IF EXISTS(SELECT 1 FROM tj.crm_tasks t WHERE t.organization_id=p_org AND t.deal_id=a.deal_id AND t.deleted_at IS NULL AND (t.metadata->>'anniversary_year'=extract(year FROM CURRENT_DATE+a.days_until)::text OR t.title=a.anniversary_number||'-year anniversary: '||a.contact_name)) THEN CONTINUE;END IF;
  SELECT d.owner_user_id INTO deal_owner FROM tj.crm_deals d WHERE d.id=a.deal_id AND d.organization_id=p_org AND d.deleted_at IS NULL;
  IF deal_owner IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.organization_members m WHERE m.organization_id=p_org AND m.user_id=deal_owner AND m.status='active') THEN deal_owner:=NULL;END IF;
  INSERT INTO tj.crm_tasks(organization_id,title,description,deal_id,contact_id,assignee_user_id,due_at,priority,task_type,source,ai_recommended,metadata)
  VALUES(p_org,a.anniversary_number||'-year anniversary: '||a.contact_name,'Purchase anniversary for '||a.deal_title||'. Check in, discuss replacement needs, or ask for a referral.',a.deal_id,a.contact_id,deal_owner,(CURRENT_DATE+a.days_until)::timestamptz,'normal','post_sale','ai_generated',true,jsonb_build_object('anniversary_number',a.anniversary_number,'anniversary_year',extract(year FROM CURRENT_DATE+a.days_until),'purchase_date',a.purchase_date,'auto_generated',true,'created_by',actor)) RETURNING id INTO task_id;
  IF deal_owner IS NOT NULL THEN INSERT INTO tj.crm_notifications(organization_id,user_id,title,body,severity,category,entity_type,entity_id) VALUES(p_org,deal_owner,a.anniversary_number||'-Year Anniversary: '||a.contact_name,a.deal_title||' was purchased '||a.anniversary_number||' year(s) ago.','info','contact','contact',a.contact_id);END IF;
  anniversaries:=anniversaries+1;
 END LOOP;
 INSERT INTO tj.crm_notifications(organization_id,user_id,title,body,severity,category,entity_type,entity_id)
 SELECT t.organization_id,t.assignee_user_id,'Task Overdue: '||left(t.title,60),'Was due '||to_char(t.due_at,'Mon DD')||'.','warning','task','task',t.id
 FROM tj.crm_tasks t WHERE t.organization_id=p_org AND t.deleted_at IS NULL AND t.completed_at IS NULL AND t.due_at<now() AND t.assignee_user_id IS NOT NULL AND tj.aiq_scope_allows(p_org,t.assignee_user_id)
  AND EXISTS(SELECT 1 FROM tj.organization_members m WHERE m.organization_id=p_org AND m.user_id=t.assignee_user_id AND m.status='active')
  AND NOT EXISTS(SELECT 1 FROM tj.crm_notifications n WHERE n.organization_id=p_org AND n.user_id=t.assignee_user_id AND n.entity_id=t.id AND n.category='task' AND n.created_at>now()-interval '24 hours');
 GET DIAGNOSTICS overdue=ROW_COUNT;
 -- Preserve the source outreach windows; these labels are campaign windows, not exact holiday dates.
 SELECT name,days INTO holiday_name,holiday_days FROM (VALUES(12,10,'Holiday Season',15),(11,15,'Black Friday Prep',10),(5,1,'Victoria Day / Mother''s Day',14),(6,1,'Father''s Day',14),(9,1,'Labour Day / Back to School',7)) h(month,day,name,days) WHERE h.month=current_month AND current_day BETWEEN h.day AND h.day+3 LIMIT 1;
 IF holiday_name IS NOT NULL THEN
  FOR a IN SELECT d.id,d.contact_id,d.title,d.owner_user_id,c.first_name,c.last_name FROM tj.crm_deals d JOIN tj.contacts c ON c.id=d.contact_id AND c.organization_id=p_org AND c.deleted_at IS NULL WHERE d.organization_id=p_org AND d.deleted_at IS NULL AND d.purchase_date>=CURRENT_DATE-interval '2 years' AND tj.aiq_scope_allows(p_org,d.owner_user_id) ORDER BY d.purchase_date DESC,d.id LIMIT 50 LOOP
   IF EXISTS(SELECT 1 FROM tj.crm_tasks t WHERE t.organization_id=p_org AND t.deal_id=a.id AND t.deleted_at IS NULL AND t.metadata->>'holiday'=holiday_name AND t.metadata->>'holiday_year'=extract(year FROM CURRENT_DATE)::text) THEN CONTINUE;END IF;
   deal_owner:=a.owner_user_id;IF deal_owner IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.organization_members m WHERE m.organization_id=p_org AND m.user_id=deal_owner AND m.status='active') THEN deal_owner:=NULL;END IF;
   INSERT INTO tj.crm_tasks(organization_id,title,description,contact_id,deal_id,assignee_user_id,due_at,priority,task_type,source,ai_recommended,metadata) VALUES(p_org,holiday_name||' outreach: '||a.first_name||' '||coalesce(a.last_name,''),'Send a '||holiday_name||' greeting after reviewing the customer record.',a.contact_id,a.id,deal_owner,now()+make_interval(days=>holiday_days),'low','post_sale','ai_generated',true,jsonb_build_object('holiday',holiday_name,'holiday_year',extract(year FROM CURRENT_DATE),'auto_generated',true,'created_by',actor));holiday_count:=holiday_count+1;
  END LOOP;
 END IF;
 RETURN jsonb_build_object('ok',true,'anniversaries_created',anniversaries,'overdue_notifications',overdue,'holiday_tasks',holiday_count,'holiday_active',holiday_name);
END $$;
