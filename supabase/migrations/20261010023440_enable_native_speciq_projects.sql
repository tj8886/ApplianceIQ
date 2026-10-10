-- Private provenance and replay journal; archive never removes business rows.
CREATE TABLE tj_private.speciq_project_requests(
 organization_id uuid NOT NULL REFERENCES tj.organizations(id),
 native_actor uuid NOT NULL REFERENCES auth.users(id),
 source_actor uuid NOT NULL REFERENCES tj.source_auth_users(id),
 request_id uuid NOT NULL, project_id uuid NOT NULL REFERENCES tj.speciq_projects(id),
 body jsonb NOT NULL,before_image jsonb,after_image jsonb NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(organization_id,native_actor,request_id));
ALTER TABLE tj_private.speciq_project_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj_private.speciq_project_requests FROM PUBLIC,anon,authenticated,service_role;
CREATE INDEX speciq_project_requests_native_idx ON tj_private.speciq_project_requests(native_actor);
CREATE INDEX speciq_project_requests_source_idx ON tj_private.speciq_project_requests(source_actor);
CREATE INDEX speciq_project_requests_project_idx ON tj_private.speciq_project_requests(project_id);
CREATE FUNCTION tj_private.speciq_project_native(p_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM tj_private.speciq_project_requests WHERE project_id=p_id)
 OR EXISTS(SELECT 1 FROM tj.speciq_packages p JOIN tj_private.speciq_draft_requests r ON r.package_id=p.id WHERE p.project_id=p_id);
$$;
CREATE FUNCTION tj_private.speciq_projects(p_body jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE n uuid:=auth.uid();actor uuid;org uuid;v_role text;a text;req uuid;proj uuid;
 row_before tj.speciq_projects%ROWTYPE;row_after tj.speciq_projects%ROWTYPE;
 replay tj_private.speciq_project_requests%ROWTYPE;d jsonb;k text;v text;purchase date;delivery date;
BEGIN
 IF p_body IS NULL OR jsonb_typeof(p_body)<>'object' OR octet_length(p_body::text)>16384 THEN RETURN jsonb_build_object('ok',false,'error','invalid_request');END IF;
 org:=(p_body->>'organization_id')::uuid;a:=p_body->>'action';v_role:=tj_private.speciq_actor_role(org);actor:=tj_private.microsoft_actor(n);
 IF v_role IS NULL THEN RETURN jsonb_build_object('ok',false,'error','organization_access_required');END IF;
 IF a='list' THEN
 RETURN jsonb_build_object('ok',true,'projects',coalesce((SELECT jsonb_agg(to_jsonb(r)) FROM (
 SELECT p.*,tj_private.speciq_project_native(p.id) AND p.status<>'archived' AND (p.created_by=actor OR v_role IN('owner','admin','manager')) AND NOT EXISTS(SELECT 1 FROM tj.speciq_packages WHERE project_id=p.id) AND v_role<>'viewer' can_edit,
 tj_private.speciq_project_native(p.id) AND p.status<>'archived' AND (p.created_by=actor OR v_role IN('owner','admin','manager')) AND NOT EXISTS(SELECT 1 FROM tj.speciq_packages WHERE project_id=p.id AND status<>'archived') AND v_role<>'viewer' can_archive
 FROM tj.speciq_projects p WHERE p.organization_id=org AND p.deleted_at IS NULL ORDER BY p.created_at DESC,p.id LIMIT 200) r),'[]'::jsonb));END IF;
 IF v_role NOT IN('owner','admin','manager','member') THEN RETURN jsonb_build_object('ok',false,'error','organization_write_required');END IF;
 IF a IS NULL OR a NOT IN('create','update','archive') THEN RETURN jsonb_build_object('ok',false,'error','invalid_request');END IF;
 req:=(p_body->>'request_id')::uuid;IF req IS NULL OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_body) AS keys(key_name) WHERE key_name NOT IN('action','organization_id','request_id','project_id','expected_updated_at','project')) THEN RETURN jsonb_build_object('ok',false,'error','invalid_request');END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(org::text||n::text||req::text,0));
 SELECT * INTO replay FROM tj_private.speciq_project_requests WHERE organization_id=org AND native_actor=n AND request_id=req;
 IF FOUND THEN
 IF replay.body<>p_body THEN RETURN jsonb_build_object('ok',false,'error','request_conflict');END IF;
 RETURN jsonb_build_object('ok',true,'project_id',replay.project_id,'replayed',true);END IF;
 IF a<>'create' THEN
 proj:=(p_body->>'project_id')::uuid;
 SELECT * INTO row_before FROM tj.speciq_projects WHERE id=proj AND organization_id=org AND deleted_at IS NULL FOR UPDATE;
 IF NOT FOUND OR (row_before.created_by IS DISTINCT FROM actor AND v_role NOT IN('owner','admin','manager')) THEN RETURN jsonb_build_object('ok',false,'error','project_unavailable');END IF;
 IF NOT tj_private.speciq_project_native(proj) THEN RETURN jsonb_build_object('ok',false,'error','historical_project_read_only');END IF;
 IF row_before.status='archived' THEN RETURN jsonb_build_object('ok',false,'error','project_archived');END IF;
 IF (p_body->>'expected_updated_at')::timestamptz IS DISTINCT FROM row_before.updated_at THEN RETURN jsonb_build_object('ok',false,'error','revision_conflict');END IF;
 IF a='update' AND EXISTS(SELECT 1 FROM tj.speciq_packages WHERE project_id=proj) THEN RETURN jsonb_build_object('ok',false,'error','package_revision_required');END IF;
 IF a='archive' AND EXISTS(SELECT 1 FROM tj.speciq_packages WHERE project_id=proj AND status<>'archived') THEN RETURN jsonb_build_object('ok',false,'error','archive_packages_first');END IF;
 END IF;
 IF a IN('create','update') THEN
 d:=p_body->'project';IF jsonb_typeof(d) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'invalid' USING ERRCODE='22023';END IF;
 IF EXISTS(SELECT 1 FROM jsonb_object_keys(d) AS keys(key_name) WHERE key_name NOT IN('project_name','customer_name','customer_email','customer_phone','property_address','room_name','builder_name','designer_name','expected_purchase_date','delivery_date','notes')) THEN RAISE EXCEPTION 'invalid' USING ERRCODE='22023';END IF;
 FOR k,v IN SELECT key,value #>> '{}' FROM jsonb_each(d) LOOP
 IF jsonb_typeof(d->k) NOT IN('string','null') OR length(coalesce(v,''))>(CASE k WHEN 'notes' THEN 4000 WHEN 'property_address' THEN 1000 WHEN 'customer_email' THEN 254 WHEN 'customer_phone' THEN 50 WHEN 'room_name' THEN 100 WHEN 'expected_purchase_date' THEN 10 WHEN 'delivery_date' THEN 10 ELSE 200 END) THEN RAISE EXCEPTION 'invalid' USING ERRCODE='22023';END IF;
 END LOOP;
 IF length(btrim(coalesce(d->>'project_name',''))) NOT BETWEEN 1 AND 200 OR length(btrim(coalesce(d->>'customer_name',''))) NOT BETWEEN 1 AND 200 OR (coalesce(d->>'customer_email','')<>'' AND d->>'customer_email' !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$') THEN RAISE EXCEPTION 'invalid' USING ERRCODE='22023';END IF;
 FOREACH k IN ARRAY ARRAY['expected_purchase_date','delivery_date'] LOOP
 v:=nullif(d->>k,'');IF v IS NOT NULL AND (v !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' OR v::date::text<>v) THEN RAISE EXCEPTION 'invalid' USING ERRCODE='22023';END IF;
 END LOOP;
 purchase:=nullif(d->>'expected_purchase_date','')::date;delivery:=nullif(d->>'delivery_date','')::date;
 IF a='create' THEN
 INSERT INTO tj.speciq_projects(organization_id,created_by,project_name,customer_name) VALUES(org,actor,btrim(d->>'project_name'),btrim(d->>'customer_name')) RETURNING id INTO proj;
 END IF;
 UPDATE tj.speciq_projects SET project_name=btrim(d->>'project_name'),customer_name=btrim(d->>'customer_name'),customer_email=nullif(d->>'customer_email',''),customer_phone=nullif(d->>'customer_phone',''),property_address=nullif(d->>'property_address',''),room_name=nullif(d->>'room_name',''),builder_name=nullif(d->>'builder_name',''),designer_name=nullif(d->>'designer_name',''),expected_purchase_date=purchase,delivery_date=delivery,notes=nullif(d->>'notes',''),updated_at=clock_timestamp() WHERE id=proj RETURNING * INTO row_after;
 ELSE
 UPDATE tj.speciq_projects SET status='archived',updated_at=clock_timestamp() WHERE id=proj RETURNING * INTO row_after;
 END IF;
 INSERT INTO tj_private.speciq_project_requests(organization_id,native_actor,source_actor,request_id,project_id,body,before_image,after_image) VALUES(org,n,actor,req,proj,p_body,CASE WHEN a='create' THEN NULL ELSE to_jsonb(row_before) END,to_jsonb(row_after));
 RETURN jsonb_build_object('ok',true,'project_id',proj,'replayed',false);
EXCEPTION WHEN invalid_text_representation OR invalid_parameter_value OR datetime_field_overflow OR invalid_datetime_format OR not_null_violation OR check_violation THEN RETURN jsonb_build_object('ok',false,'error','invalid_request');
END;
$$;
CREATE FUNCTION public.tj_runtime_speciq_projects(p_body jsonb)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.speciq_projects(p_body); $$;
REVOKE ALL ON FUNCTION tj_private.speciq_project_native(uuid),tj_private.speciq_projects(jsonb),public.tj_runtime_speciq_projects(jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.speciq_projects(jsonb),public.tj_runtime_speciq_projects(jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';
