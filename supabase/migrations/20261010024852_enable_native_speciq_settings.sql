-- Native organization configuration only. Financial enforcement is a separate workflow.
CREATE TABLE tj_private.speciq_settings_requests(
 organization_id uuid NOT NULL REFERENCES tj.organizations(id),
 native_actor uuid NOT NULL REFERENCES auth.users(id),
 source_actor uuid NOT NULL REFERENCES tj.source_auth_users(id),
 request_id uuid NOT NULL,body jsonb NOT NULL,before_image jsonb,after_image jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),PRIMARY KEY(organization_id,native_actor,request_id));
ALTER TABLE tj_private.speciq_settings_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj_private.speciq_settings_requests FROM PUBLIC,anon,authenticated,service_role;
CREATE INDEX speciq_settings_requests_native_idx ON tj_private.speciq_settings_requests(native_actor);
CREATE INDEX speciq_settings_requests_source_idx ON tj_private.speciq_settings_requests(source_actor);
CREATE FUNCTION tj_private.speciq_settings(p_body jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE n uuid:=auth.uid();actor uuid;org uuid;v_role text;a text;req uuid;d jsonb;k text;v text;had_row boolean;
 row_before tj.speciq_retailer_settings%ROWTYPE;row_after tj.speciq_retailer_settings%ROWTYPE;
 replay tj_private.speciq_settings_requests%ROWTYPE;
BEGIN
 IF p_body IS NULL OR jsonb_typeof(p_body)<>'object' OR octet_length(p_body::text)>32768 THEN RETURN jsonb_build_object('ok',false,'error','invalid_request');END IF;
 org:=(p_body->>'organization_id')::uuid;a:=p_body->>'action';v_role:=tj_private.speciq_actor_role(org);actor:=tj_private.microsoft_actor(n);
 IF v_role IS NULL THEN RETURN jsonb_build_object('ok',false,'error','organization_access_required');END IF;
 IF a='get' THEN
 SELECT * INTO row_after FROM tj.speciq_retailer_settings WHERE organization_id=org;
 RETURN jsonb_build_object('ok',true,'stored',FOUND,'can_edit',v_role IN('owner','admin'),'settings',CASE WHEN row_after.id IS NULL THEN jsonb_build_object('organization_id',org,'updated_at',NULL,'primary_color','#0f1f3d','secondary_color','#2f6fed','default_validity_days',14,'max_rep_validity_days',14,'max_manager_validity_days',30,'max_store_manager_validity_days',60) ELSE to_jsonb(row_after) END);END IF;
 IF v_role NOT IN('owner','admin') THEN RETURN jsonb_build_object('ok',false,'error','organization_admin_required');END IF;
 IF a IS NULL OR a NOT IN('save','clear_logo') OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_body) AS keys(key_name) WHERE key_name NOT IN('action','organization_id','request_id','expected_updated_at','settings')) THEN RETURN jsonb_build_object('ok',false,'error','invalid_request');END IF;
 req:=(p_body->>'request_id')::uuid;IF req IS NULL OR NOT(p_body ? 'expected_updated_at') THEN RETURN jsonb_build_object('ok',false,'error','invalid_request');END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(org::text||n::text||req::text,0));
 PERFORM pg_advisory_xact_lock(hashtextextended('speciq-settings:'||org::text,0));
 SELECT * INTO replay FROM tj_private.speciq_settings_requests WHERE organization_id=org AND native_actor=n AND request_id=req;
 IF FOUND THEN
 IF replay.body<>p_body THEN RETURN jsonb_build_object('ok',false,'error','request_conflict');END IF;
 SELECT * INTO row_after FROM tj.speciq_retailer_settings WHERE organization_id=org;
 RETURN jsonb_build_object('ok',true,'replayed',true,'settings',to_jsonb(row_after));END IF;
 SELECT * INTO row_before FROM tj.speciq_retailer_settings WHERE organization_id=org FOR UPDATE;had_row:=FOUND;
 IF (p_body->>'expected_updated_at')::timestamptz IS DISTINCT FROM row_before.updated_at THEN RETURN jsonb_build_object('ok',false,'error','revision_conflict');END IF;
 IF a='save' THEN
 d:=p_body->'settings';IF jsonb_typeof(d) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'invalid' USING ERRCODE='22023';END IF;
 IF EXISTS(SELECT 1 FROM jsonb_object_keys(d) AS keys(key_name) WHERE key_name NOT IN('store_name','store_phone','store_email','store_website','store_address','store_city','store_province','store_postal','default_welcome_message','default_disclaimer','primary_color','secondary_color','default_validity_days','max_rep_validity_days','max_manager_validity_days','max_store_manager_validity_days','validity_disclaimer','commercial_disclaimer')) THEN RAISE EXCEPTION 'invalid' USING ERRCODE='22023';END IF;
 FOR k,v IN SELECT key,value #>> '{}' FROM jsonb_each(d) LOOP
 IF k IN('default_validity_days','max_rep_validity_days','max_manager_validity_days','max_store_manager_validity_days') THEN
 IF jsonb_typeof(d->k) IS DISTINCT FROM 'number' OR v !~ '^[0-9]{1,3}$' OR v::integer NOT BETWEEN 1 AND 365 THEN RAISE EXCEPTION 'invalid' USING ERRCODE='22023';END IF;
 ELSE
 IF jsonb_typeof(d->k) NOT IN('string','null') OR length(coalesce(v,''))>(CASE WHEN k IN('default_welcome_message','default_disclaimer','validity_disclaimer','commercial_disclaimer') THEN 4000 WHEN k IN('store_address','store_website') THEN 1000 WHEN k='store_email' THEN 254 WHEN k='store_phone' THEN 50 ELSE 200 END) THEN RAISE EXCEPTION 'invalid' USING ERRCODE='22023';END IF;
 END IF;
 END LOOP;
 IF coalesce(d->>'primary_color','') !~ '^#[0-9a-fA-F]{6}$' OR coalesce(d->>'secondary_color','') !~ '^#[0-9a-fA-F]{6}$' OR (coalesce(d->>'store_email','')<>'' AND d->>'store_email' !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$') THEN RAISE EXCEPTION 'invalid' USING ERRCODE='22023';END IF;
 IF coalesce(d->>'store_website','')<>'' AND d->>'store_website' !~ '^https://[^[:space:]/?#]+([/?#][^[:space:]]*)?$' THEN RAISE EXCEPTION 'invalid' USING ERRCODE='22023';END IF;
 IF (d->>'default_validity_days')::integer IS NULL OR (d->>'max_rep_validity_days')::integer IS NULL OR (d->>'max_manager_validity_days')::integer IS NULL OR (d->>'max_store_manager_validity_days')::integer IS NULL OR NOT((d->>'default_validity_days')::integer<=(d->>'max_rep_validity_days')::integer AND (d->>'max_rep_validity_days')::integer<=(d->>'max_manager_validity_days')::integer AND (d->>'max_manager_validity_days')::integer<=(d->>'max_store_manager_validity_days')::integer) THEN RAISE EXCEPTION 'invalid' USING ERRCODE='22023';END IF;
 IF NOT had_row THEN INSERT INTO tj.speciq_retailer_settings(organization_id) VALUES(org);END IF;
 UPDATE tj.speciq_retailer_settings SET store_name=nullif(d->>'store_name',''),store_phone=nullif(d->>'store_phone',''),store_email=nullif(d->>'store_email',''),store_website=nullif(d->>'store_website',''),store_address=nullif(d->>'store_address',''),store_city=nullif(d->>'store_city',''),store_province=nullif(d->>'store_province',''),store_postal=nullif(d->>'store_postal',''),default_welcome_message=nullif(d->>'default_welcome_message',''),default_disclaimer=nullif(d->>'default_disclaimer',''),primary_color=d->>'primary_color',secondary_color=d->>'secondary_color',default_validity_days=(d->>'default_validity_days')::integer,max_rep_validity_days=(d->>'max_rep_validity_days')::integer,max_manager_validity_days=(d->>'max_manager_validity_days')::integer,max_store_manager_validity_days=(d->>'max_store_manager_validity_days')::integer,validity_disclaimer=nullif(d->>'validity_disclaimer',''),commercial_disclaimer=nullif(d->>'commercial_disclaimer',''),updated_at=clock_timestamp() WHERE organization_id=org RETURNING * INTO row_after;
 ELSE
 IF NOT had_row OR p_body ? 'settings' THEN RETURN jsonb_build_object('ok',false,'error','invalid_request');END IF;
 UPDATE tj.speciq_retailer_settings SET logo_url=NULL,updated_at=clock_timestamp() WHERE organization_id=org RETURNING * INTO row_after;
 END IF;
 INSERT INTO tj_private.speciq_settings_requests(organization_id,native_actor,source_actor,request_id,body,before_image,after_image) VALUES(org,n,actor,req,p_body,CASE WHEN had_row THEN to_jsonb(row_before) ELSE NULL END,to_jsonb(row_after));
 RETURN jsonb_build_object('ok',true,'replayed',false,'settings',to_jsonb(row_after));
EXCEPTION WHEN invalid_text_representation OR invalid_parameter_value OR datetime_field_overflow OR invalid_datetime_format OR numeric_value_out_of_range THEN RETURN jsonb_build_object('ok',false,'error','invalid_request');
END;
$$;
CREATE FUNCTION public.tj_runtime_speciq_settings(p_body jsonb)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.speciq_settings(p_body); $$;
REVOKE ALL ON FUNCTION tj_private.speciq_settings(jsonb),public.tj_runtime_speciq_settings(jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.speciq_settings(jsonb),public.tj_runtime_speciq_settings(jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';
