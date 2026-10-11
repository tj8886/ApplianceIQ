-- Reviewed one-time cutover binding. Runtime authorization uses IDs, never emails.
-- The legacy single-tenant dataset belonged to the only active MDF administrator's
-- Tackline Strategies workspace. Preserve that workspace as a distinct core tenant.
DO $$ BEGIN
 IF (SELECT count(*) FROM tj.mdf_organizations)<>1 OR
    (SELECT count(*) FROM tj.mdf_platform_users)<>1 OR
    NOT EXISTS(SELECT 1 FROM tj.mdf_platform_users u JOIN tj.mdf_organizations o ON o.id=u.org_id
      WHERE u.id='6f1cc7fc-229b-4610-9ad1-d3def7381db3' AND o.id='0f500184-8ed1-49a3-ba22-b8a17e0c11dc'
      AND u.is_active AND u.role='super_admin' AND u.email=o.owner_email AND u.email='tjrobar5@gmail.com') OR
    NOT EXISTS(SELECT 1 FROM tj.source_user_identity_map WHERE source_user_id='ce2145b0-0283-45da-af4c-3a88f84cecae'
      AND target_user_id='ce2145b0-0283-45da-af4c-3a88f84cecae' AND identity_verified
      AND activation_status='activated' AND mapping_status='approved_create' AND approved_at IS NOT NULL)
 THEN RAISE EXCEPTION 'MDF cutover evidence changed; review explicit bindings'; END IF;
END $$;
INSERT INTO tj.organizations(id,name,slug,metadata)
SELECT id,name,'vendorxq-tackline-strategies',jsonb_build_object('source','mdf_organizations','cutover','2026-10-11','provider_billing_verified',false)
FROM tj.mdf_organizations WHERE id='0f500184-8ed1-49a3-ba22-b8a17e0c11dc';
INSERT INTO tj.organization_members(organization_id,user_id,role,status)
VALUES('0f500184-8ed1-49a3-ba22-b8a17e0c11dc','ce2145b0-0283-45da-af4c-3a88f84cecae','owner','active');
ALTER TABLE tj.mdf_platform_users ADD COLUMN source_user_id uuid REFERENCES tj.source_auth_users(id);
UPDATE tj.mdf_platform_users SET source_user_id='ce2145b0-0283-45da-af4c-3a88f84cecae' WHERE id='6f1cc7fc-229b-4610-9ad1-d3def7381db3';
ALTER TABLE tj.mdf_coop_requests ADD COLUMN submitted_by_source_user_id uuid REFERENCES tj.source_auth_users(id);
CREATE INDEX mdf_request_actor_idx ON tj.mdf_coop_requests(submitted_by_source_user_id);
CREATE UNIQUE INDEX mdf_native_binding_idx ON tj.mdf_platform_users(source_user_id,org_id);
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['mdf_brands','mdf_brand_contracts','mdf_sales_data','mdf_vr_calculations','mdf_coop_ledger','mdf_coop_requests','mdf_coop_spend','mdf_mdf_funds','mdf_alerts','mdf_audit_log','mdf_organizations','mdf_platform_users','mdf_email_queue'] LOOP
  EXECUTE format('ALTER TABLE tj.%I ADD COLUMN organization_id uuid REFERENCES tj.organizations(id)',t);
  -- Deferred email receipts have no proven ownership: retain them unassigned, inaccessible.
  IF t<>'mdf_email_queue' THEN EXECUTE format('UPDATE tj.%I SET organization_id=%L::uuid',t,'0f500184-8ed1-49a3-ba22-b8a17e0c11dc'); END IF;
  EXECUTE format('CREATE INDEX %I ON tj.%I(organization_id)',t||'_tenant_idx',t);
  EXECUTE format('ALTER TABLE tj.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON tj.%I FROM anon,authenticated',t);
 END LOOP;
END $$;
-- Restore the launcher for this migrated workspace without creating a payment product.
INSERT INTO tj.platform_modules(key,name,description,app_url,visibility,is_marketplace_listed,manifest)
VALUES('mdf-coop','VendorXQ MDF & Co-op','Vendor funding, co-op requests and recorded funding reports','https://applianceiq-mdf-coop-vr.netlify.app','private',false,
 '{"registry_key":"mdf-coop","source_path":"apps/mdf-coop","billing_execution_enabled":false,"email_delivery_enabled":false,"migration_access_only":true}');
DO $$ DECLARE expression text;BEGIN
 SELECT pg_get_expr(conbin,conrelid) INTO expression FROM pg_constraint WHERE conrelid='tj.org_app_entitlements'::regclass AND conname='org_app_entitlements_app_key_check';
 IF expression IS NULL THEN RAISE EXCEPTION 'App key constraint missing';END IF;
 ALTER TABLE tj.org_app_entitlements DROP CONSTRAINT org_app_entitlements_app_key_check;
 EXECUTE 'ALTER TABLE tj.org_app_entitlements ADD CONSTRAINT org_app_entitlements_app_key_check CHECK(('||expression||') OR app_key=''mdf-coop'')';
END $$;
INSERT INTO tj.org_app_entitlements(organization_id,app_key,status,metadata)
VALUES('0f500184-8ed1-49a3-ba22-b8a17e0c11dc','mdf-coop','active','{"basis":"existing MDF administrator workspace migration","payment_product":false}');
-- No browser table grants. A private, bounded gateway owns tenant/role checks.
CREATE FUNCTION tj_private.mdf_tracker(p_action text,p_table text DEFAULT NULL,p_id uuid DEFAULT NULL,p_data jsonb DEFAULT '{}'::jsonb,p_params jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=tj_private.current_source_user_id();profile tj.mdf_platform_users;org uuid;r text;
 out_rows jsonb;old_row jsonb;payload jsonb:=coalesce(p_data,'{}');k text;v text;cols text;vals text;assigns text;where_sql text;order_sql text;lim int;off int;bid uuid;cid uuid;ref uuid;
 c tj.mdf_brand_contracts;eligible numeric;accrual numeric;sale tj.mdf_sales_data;req tj.mdf_coop_requests;new_status text;period_from date;period_to date;units_sold numeric;units_bought numeric;rate numeric;tier_label text;tier jsonb;
BEGIN
 IF auth.uid() IS NULL OR actor IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501';END IF;
 SELECT * INTO profile FROM tj.mdf_platform_users u WHERE u.source_user_id=actor AND u.is_active AND u.organization_id=u.org_id
 AND EXISTS(SELECT 1 FROM tj.organization_members m JOIN tj.organizations o ON o.id=m.organization_id WHERE m.organization_id=u.organization_id AND m.user_id=actor AND m.status='active' AND o.status='active' AND o.deleted_at IS NULL) ORDER BY u.id LIMIT 1;
 IF profile.id IS NULL OR (SELECT count(*) FROM tj.mdf_platform_users u WHERE u.source_user_id=actor AND u.is_active AND u.organization_id=u.org_id AND EXISTS(SELECT 1 FROM tj.organization_members m JOIN tj.organizations o ON o.id=m.organization_id WHERE m.organization_id=u.organization_id AND m.user_id=actor AND m.status='active' AND o.status='active' AND o.deleted_at IS NULL))<>1 THEN
 RAISE EXCEPTION 'MDF workspace access is not configured' USING ERRCODE='42501';END IF;
 org:=profile.organization_id;r:=profile.role;
 IF p_action='context' THEN RETURN jsonb_build_object('profile',to_jsonb(profile),'organization_id',org,'email_delivery_enabled',false,'billing_execution_enabled',false);END IF;
 IF p_action NOT IN ('read','insert','update') THEN RAISE EXCEPTION 'This action is unavailable. Source records are retained.' USING ERRCODE='42501';END IF;
 IF p_table IS NULL OR p_table NOT IN ('mdf_brands','mdf_brand_contracts','mdf_sales_data','mdf_vr_calculations','mdf_coop_ledger','mdf_coop_requests','mdf_coop_spend','mdf_mdf_funds','mdf_alerts','mdf_audit_log','mdf_platform_users','mdf_organizations','mdf_subscription_tiers') THEN RAISE EXCEPTION 'unsupported_table' USING ERRCODE='42501';END IF;
 IF p_action='read' THEN
  IF p_table IN ('mdf_audit_log','mdf_platform_users','mdf_organizations','mdf_subscription_tiers') AND r NOT IN ('super_admin','admin') THEN RAISE EXCEPTION 'administrator_required' USING ERRCODE='42501';END IF;
  where_sql:=CASE WHEN p_table='mdf_subscription_tiers' THEN 'true' ELSE format('organization_id=%L::uuid',org) END;
  FOR k,v IN SELECT key,value FROM jsonb_each_text(coalesce(p_params,'{}')) LOOP
   IF k IN ('limit','offset','order') THEN CONTINUE;END IF;
   IF k NOT IN ('id','brand_id','email','owner_email','is_active','role','is_dismissed') OR NOT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='tj' AND table_name=p_table AND column_name=k) THEN RAISE EXCEPTION 'unsupported_filter';END IF;
   IF v LIKE 'eq.%' THEN where_sql:=where_sql||format(' AND %I::text=%L',k,substr(v,4));
   ELSIF k='role' AND v LIKE 'in.(%)' THEN where_sql:=where_sql||format(' AND %I=ANY(string_to_array(%L,'',''))',k,substr(v,5,length(v)-5));
   ELSE RAISE EXCEPTION 'unsupported_filter';END IF;
  END LOOP;
  lim:=least(1000,greatest(1,coalesce((p_params->>'limit')::int,1000)));off:=greatest(0,coalesce((p_params->>'offset')::int,0));IF off>10000 THEN RAISE EXCEPTION 'export_size_exceeded';END IF;
  k:=split_part(coalesce(p_params->>'order','id'),'.',1);v:=split_part(coalesce(p_params->>'order','id'),'.',2);
  IF NOT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='tj' AND table_name=p_table AND column_name=k) OR v NOT IN ('','asc','desc') THEN RAISE EXCEPTION 'unsupported_order';END IF;
  order_sql:=format('%I %s NULLS LAST,id',k,CASE WHEN v='desc' THEN 'DESC' ELSE 'ASC' END);
  EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) FROM (SELECT * FROM tj.%I WHERE %s ORDER BY %s LIMIT %s OFFSET %s) x',p_table,where_sql,order_sql,lim,off) INTO out_rows;
  RETURN out_rows;
 END IF;
 IF jsonb_typeof(payload)<>'object' OR length(payload::text)>100000 THEN RAISE EXCEPTION 'invalid_payload';END IF;
 IF p_table IN ('mdf_organizations','mdf_platform_users','mdf_subscription_tiers','mdf_audit_log') THEN RAISE EXCEPTION 'Account access and billing are managed through verified platform bindings.' USING ERRCODE='42501';END IF;
 IF p_table IN ('mdf_brands','mdf_brand_contracts') AND r NOT IN ('super_admin','admin') OR
 p_table IN ('mdf_vr_calculations','mdf_coop_ledger','mdf_coop_spend','mdf_mdf_funds') AND r NOT IN ('super_admin','admin','marketing') OR
 p_table='mdf_sales_data' AND r NOT IN ('super_admin','admin','manager','sales_rep') OR
 p_table='mdf_coop_requests' AND r NOT IN ('super_admin','admin','manager','marketing','sales_rep') OR
 p_table='mdf_alerts' AND r NOT IN ('super_admin','admin','manager','marketing') THEN RAISE EXCEPTION 'role_not_allowed' USING ERRCODE='42501';END IF;
 IF p_table='mdf_alerts' AND (p_action<>'update' OR payload-'is_dismissed'<>'{}') THEN RAISE EXCEPTION 'alert_change_not_allowed';END IF;
 IF p_action='update' THEN
  EXECUTE format('SELECT to_jsonb(x) FROM tj.%I x WHERE id=$1 AND organization_id=$2 FOR UPDATE',p_table) INTO old_row USING p_id,org;
  IF old_row IS NULL THEN RAISE EXCEPTION 'record_not_found' USING ERRCODE='42501';END IF;
 ELSE p_id:=gen_random_uuid();END IF;
 FOR k IN SELECT jsonb_object_keys(payload) LOOP
  IF k IN ('id','organization_id','source_user_id','submitted_by_source_user_id','created_at','updated_at','running_balance','net_sales','import_batch_id') OR NOT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='tj' AND table_name=p_table AND column_name=k AND is_generated='NEVER') THEN
   IF k='import_batch_id' AND p_table='mdf_sales_data' AND p_action='insert' THEN CONTINUE;END IF;
   RAISE EXCEPTION 'protected_or_unknown_field: %',k;END IF;
 END LOOP;
 -- Empty optional dates are NULL, not invalid date strings.
 FOR k IN SELECT column_name FROM information_schema.columns WHERE table_schema='tj' AND table_name=p_table AND data_type IN ('date','timestamp with time zone') LOOP
 IF payload->>k='' THEN payload:=jsonb_set(payload,ARRAY[k],'null');END IF;END LOOP;
 bid:=coalesce((payload->>'brand_id')::uuid,(old_row->>'brand_id')::uuid);
 IF bid IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.mdf_brands WHERE id=bid AND organization_id=org) THEN RAISE EXCEPTION 'brand_scope_mismatch' USING ERRCODE='42501';END IF;
 cid:=coalesce((payload->>'contract_id')::uuid,(old_row->>'contract_id')::uuid);
 IF cid IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.mdf_brand_contracts WHERE id=cid AND brand_id=bid AND organization_id=org) THEN RAISE EXCEPTION 'contract_scope_mismatch' USING ERRCODE='42501';END IF;
 ref:=coalesce((payload->>'request_id')::uuid,(old_row->>'request_id')::uuid);
 IF ref IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.mdf_coop_requests WHERE id=ref AND organization_id=org) THEN RAISE EXCEPTION 'request_scope_mismatch' USING ERRCODE='42501';END IF;
 IF p_table='mdf_coop_ledger' THEN
  IF p_action='update' AND coalesce(old_row->>'reference_type','')<>'manual' THEN RAISE EXCEPTION 'Recorded accruals are immutable; add an adjustment instead.' USING ERRCODE='42501';END IF;
  IF (payload ? 'reference_id' AND payload->>'reference_id' IS NOT NULL) OR (payload ? 'reference_type' AND payload->>'reference_type'<>'manual') THEN RAISE EXCEPTION 'ledger_reference_not_allowed';END IF;
  payload:=payload||'{"reference_type":"manual"}';
 END IF;
 IF p_table='mdf_sales_data' AND p_action='insert' THEN
  IF payload->>'is_verified'='true' THEN RAISE EXCEPTION 'Verification requires source evidence.';END IF;
  payload:=payload||jsonb_build_object('imported_by',profile.display_name,'is_verified',false);
 END IF;
 IF p_table='mdf_sales_data' AND p_action='update' THEN RAISE EXCEPTION 'Recorded sales are retained; import a reviewed correction instead.' USING ERRCODE='42501';END IF;
 IF p_table='mdf_brand_contracts' THEN
  IF payload ? 'coop_pct' AND ((payload->>'coop_pct')::numeric<0 OR (payload->>'coop_pct')::numeric>100) THEN RAISE EXCEPTION 'invalid_coop_rate';END IF;
 END IF;
 IF p_table='mdf_vr_calculations' THEN
  IF p_action<>'insert' THEN RAISE EXCEPTION 'Recorded calculations are retained.' USING ERRCODE='42501';END IF;
  period_from:=(payload->>'period_start')::date;period_to:=(payload->>'period_end')::date;
  SELECT * INTO c FROM tj.mdf_brand_contracts WHERE id=cid AND organization_id=org AND brand_id=bid AND vr_enabled AND effective_date<=period_from AND contract_expiry_date>=period_to AND (end_date IS NULL OR end_date>=period_to);
  IF c.id IS NULL OR period_from IS NULL OR period_to IS NULL OR period_to<period_from THEN RAISE EXCEPTION 'A recorded rebate contract covering the period is required.';END IF;
  SELECT coalesce(sum(CASE WHEN c.vr_includes_accessories THEN net_sales ELSE product_sales END),0),coalesce(sum(s.units_sold),0),coalesce(sum(s.units_purchased),0) INTO eligible,units_sold,units_bought FROM tj.mdf_sales_data s WHERE organization_id=org AND brand_id=bid AND period_start>=period_from AND period_end<=period_to;
  rate:=c.vr_base_pct;tier_label:='Base';
  FOR tier IN SELECT value FROM jsonb_array_elements(coalesce(c.vr_tiers,'[]')) ORDER BY (value->>'threshold')::numeric LOOP
   IF eligible>=(tier->>'threshold')::numeric THEN rate:=(tier->>'pct')::numeric;tier_label:=coalesce(tier->>'label',(tier->>'threshold')||'+');END IF;
  END LOOP;
  IF rate IS NULL OR rate<0 OR rate>100 THEN RAISE EXCEPTION 'Recorded rebate schedule needs review.';END IF;
  payload:=payload||jsonb_build_object('eligible_sales',eligible,'total_units_sold',units_sold,'total_units_purchased',units_bought,'sellthru_pct',CASE WHEN units_bought>0 THEN units_sold*100/units_bought ELSE 0 END,'rebate_pct',rate,'rebate_amount',eligible*rate/100,'tier_reached',tier_label,'status','calculated','calculation_notes','Calculated from recorded sales and contract terms; not provider verification.');
 END IF;
 IF p_table='mdf_coop_requests' THEN
  IF jsonb_array_length(coalesce(nullif(payload->'brand_ids','null'),nullif(old_row->'brand_ids','null'),'[]'))=0 THEN RAISE EXCEPTION 'request_brands_required';END IF;
  FOR k IN SELECT jsonb_object_keys(coalesce(nullif(payload->'brand_split','null'),nullif(old_row->'brand_split','null'),'{}')) LOOP
   IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements_text(coalesce(nullif(payload->'brand_ids','null'),nullif(old_row->'brand_ids','null'),'[]')) x(id) WHERE id=k) THEN RAISE EXCEPTION 'request_split_scope_mismatch' USING ERRCODE='42501';END IF;
  END LOOP;
  FOR k IN SELECT jsonb_array_elements_text(coalesce(nullif(payload->'brand_ids','null'),nullif(old_row->'brand_ids','null'),'[]')) LOOP
   IF NOT EXISTS(SELECT 1 FROM tj.mdf_brands WHERE id=k::uuid AND organization_id=org) THEN RAISE EXCEPTION 'request_brand_scope_mismatch' USING ERRCODE='42501';END IF;
  END LOOP;
  IF payload ? 'estimated_cost' AND ((payload->>'estimated_cost')::numeric IS NULL OR (payload->>'estimated_cost')::numeric<0) THEN RAISE EXCEPTION 'invalid_estimated_cost';END IF;
  IF p_action='insert' THEN
   IF payload ? 'status' OR EXISTS(SELECT 1 FROM jsonb_object_keys(payload) x(key) WHERE key LIKE 'manager_%' OR key LIKE 'marketing_%') THEN RAISE EXCEPTION 'new_request_must_be_submitted';END IF;
   payload:=payload||jsonb_build_object('status','submitted','submitted_by',profile.display_name,'submitted_by_email',profile.email,'submitted_by_role',CASE WHEN r='super_admin' THEN 'admin' WHEN r='manager' THEN 'store_manager' ELSE r END,'submitted_by_source_user_id',actor,'submitted_at',now());
  ELSIF payload ? 'status' THEN
   new_status:=payload->>'status';
   IF old_row->>'status' IN ('approved','denied') THEN RAISE EXCEPTION 'request_already_finalized';END IF;
   IF payload ? 'marketing_decision' THEN
    IF EXISTS(SELECT 1 FROM jsonb_object_keys(payload) x(key) WHERE key LIKE 'manager_%') THEN RAISE EXCEPTION 'mixed_review_stages';END IF;
    IF r NOT IN ('super_admin','admin','marketing') OR old_row->>'status'<>'marketing_review' OR new_status NOT IN ('approved','denied','needs_info') THEN RAISE EXCEPTION 'marketing_review_not_allowed' USING ERRCODE='42501';END IF;
    payload:=payload||jsonb_build_object('marketing_reviewed_by',profile.display_name,'marketing_reviewed_at',now(),'marketing_decision',new_status);
   ELSE
    IF EXISTS(SELECT 1 FROM jsonb_object_keys(payload) x(key) WHERE key LIKE 'marketing_%') THEN RAISE EXCEPTION 'mixed_review_stages';END IF;
    IF r NOT IN ('super_admin','admin','manager') OR old_row->>'status' NOT IN ('submitted','manager_review','needs_info') OR new_status NOT IN ('marketing_review','denied','needs_info') THEN RAISE EXCEPTION 'manager_review_not_allowed' USING ERRCODE='42501';END IF;
    payload:=payload||jsonb_build_object('manager_reviewed_by',profile.display_name,'manager_reviewed_at',now(),'manager_decision',CASE WHEN new_status='marketing_review' THEN 'approved' ELSE new_status END);
   END IF;
   IF EXISTS(SELECT 1 FROM jsonb_object_keys(payload) x(key) WHERE key NOT IN ('status','manager_reviewed_by','manager_reviewed_at','manager_decision','manager_notes','marketing_reviewed_by','marketing_reviewed_at','marketing_decision','marketing_notes')) THEN RAISE EXCEPTION 'review_payload_invalid';END IF;
  ELSE
   IF old_row->>'status' NOT IN ('submitted','needs_info') OR (r NOT IN ('super_admin','admin') AND (old_row->>'submitted_by_source_user_id') IS DISTINCT FROM actor::text) THEN RAISE EXCEPTION 'request_edit_not_allowed' USING ERRCODE='42501';END IF;
   IF EXISTS(SELECT 1 FROM jsonb_object_keys(payload) x(key) WHERE key LIKE 'manager_%' OR key LIKE 'marketing_%') THEN RAISE EXCEPTION 'review_fields_protected';END IF;
   payload:=payload-'submitted_by'-'submitted_by_email'-'submitted_by_role'-'submitted_at';
  END IF;
 END IF;
 payload:=payload||jsonb_build_object('id',p_id,'organization_id',org);
 IF p_table='mdf_brand_contracts' AND p_action='insert' THEN
  IF (payload->>'effective_date')::date IS NULL OR (payload->>'contract_expiry_date')::date IS NULL OR (payload->>'contract_expiry_date')::date<(payload->>'effective_date')::date THEN RAISE EXCEPTION 'invalid_contract_dates';END IF;
  IF EXISTS(SELECT 1 FROM tj.mdf_brand_contracts WHERE organization_id=org AND brand_id=bid AND end_date IS NULL AND effective_date>=(payload->>'effective_date')::date) THEN RAISE EXCEPTION 'New contract must follow the recorded active contract.';END IF;
  UPDATE tj.mdf_brand_contracts SET end_date=(payload->>'effective_date')::date-1 WHERE organization_id=org AND brand_id=bid AND end_date IS NULL;
 END IF;
 IF p_action='insert' THEN
  SELECT string_agg(format('%I',key),','),string_agg(format('x.%I',key),',') INTO cols,vals FROM jsonb_object_keys(payload) x(key);
  EXECUTE format('INSERT INTO tj.%I(%s) SELECT %s FROM jsonb_populate_record(NULL::tj.%I,$1) x RETURNING to_jsonb(%I.*)',p_table,cols,vals,p_table,p_table) INTO out_rows USING payload;
 ELSE
  SELECT string_agg(format('%I=x.%I',key,key),',') INTO assigns FROM jsonb_object_keys(payload) x(key) WHERE key NOT IN ('id','organization_id');
  IF assigns IS NULL THEN RAISE EXCEPTION 'empty_update';END IF;
  EXECUTE format('UPDATE tj.%I t SET %s FROM jsonb_populate_record(NULL::tj.%I,$1) x WHERE t.id=$2 AND t.organization_id=$3 RETURNING to_jsonb(t.*)',p_table,assigns,p_table) INTO out_rows USING payload,p_id,org;
 END IF;
 IF p_table='mdf_sales_data' AND p_action='insert' THEN
  sale:=jsonb_populate_record(NULL::tj.mdf_sales_data,out_rows);
  SELECT * INTO c FROM tj.mdf_brand_contracts WHERE organization_id=org AND brand_id=bid AND coop_enabled AND effective_date<=sale.period_start AND (end_date IS NULL OR end_date>=sale.period_end) AND contract_expiry_date>=sale.period_end ORDER BY effective_date DESC,id LIMIT 1;
  IF c.id IS NOT NULL THEN
   eligible:=CASE WHEN c.coop_includes_accessories THEN sale.net_sales ELSE coalesce(sale.product_sales,sale.net_sales) END;
   accrual:=eligible*(c.coop_pct/100.0);
   IF accrual>0 THEN INSERT INTO tj.mdf_coop_ledger(organization_id,brand_id,entry_type,amount,description,reference_type,reference_id,period_label,transaction_date)
   VALUES(org,bid,'accrual',accrual,'Recorded sales co-op accrual ('||c.coop_pct||'%)','sales',p_id,sale.period_label,coalesce(sale.period_end,sale.period_start));END IF;
  END IF;
 END IF;
 INSERT INTO tj.mdf_audit_log(organization_id,user_email,user_role,action,entity_type,entity_id,details)
 VALUES(org,profile.email,r,p_action,p_table,p_id,jsonb_build_object('changed_fields',(SELECT jsonb_agg(key) FROM jsonb_object_keys(payload) x(key)),'native_user_id',auth.uid()));
 RETURN jsonb_build_array(out_rows);
END $$;
REVOKE ALL ON FUNCTION tj_private.mdf_tracker(text,text,uuid,jsonb,jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION tj_private.mdf_tracker(text,text,uuid,jsonb,jsonb) TO authenticated;
CREATE FUNCTION public.tj_runtime_mdf_tracker(p_action text,p_table text DEFAULT NULL,p_id uuid DEFAULT NULL,p_data jsonb DEFAULT '{}'::jsonb,p_params jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.mdf_tracker(p_action,p_table,p_id,p_data,p_params); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_mdf_tracker(text,text,uuid,jsonb,jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.tj_runtime_mdf_tracker(text,text,uuid,jsonb,jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';
