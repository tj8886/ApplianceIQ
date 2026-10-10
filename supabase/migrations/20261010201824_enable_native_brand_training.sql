-- Organization-scoped manufacturer training writes; prior images retained privately.
CREATE TABLE tj_private.brand_training_requests(
 organization_id uuid NOT NULL REFERENCES tj.organizations(id),native_actor uuid NOT NULL REFERENCES auth.users(id),source_actor uuid NOT NULL REFERENCES tj.source_auth_users(id),request_id uuid NOT NULL,body jsonb NOT NULL,before_image jsonb,after_image jsonb NOT NULL,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),PRIMARY KEY(organization_id,native_actor,request_id));
ALTER TABLE tj_private.brand_training_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj_private.brand_training_requests FROM PUBLIC,anon,authenticated,service_role;
CREATE INDEX brand_training_requests_native_idx ON tj_private.brand_training_requests(native_actor);
CREATE INDEX brand_training_requests_source_idx ON tj_private.brand_training_requests(source_actor);
CREATE FUNCTION tj_private.brand_training_access(p_org uuid,p_vendor uuid,p_mode text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT tj_private.mfr_asset_vendor_access(p_org,p_vendor,'read') AND (p_mode='read' OR tj_private.manufacturer_invite_admin(tj_private.microsoft_actor(auth.uid()),p_org) OR EXISTS(
 SELECT 1 FROM tj.mfr_members m WHERE m.user_id=tj_private.microsoft_actor(auth.uid()) AND m.vendor_id=p_vendor AND m.status='active' AND m.approved_by IS NOT NULL AND m.approved_at IS NOT NULL AND m.activated_at IS NOT NULL AND (m.expires_at IS NULL OR m.expires_at>now())
 AND ((p_mode='write' AND m.role IN('vendor_owner','vendor_admin','brand_admin','product_editor')) OR (p_mode='review' AND m.role IN('vendor_owner','vendor_admin','brand_admin','product_reviewer')))));
$$;
REVOKE ALL ON FUNCTION tj_private.brand_training_access(uuid,uuid,text) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj_private.brand_training(p_body jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=tj_private.microsoft_actor(auth.uid());n uuid:=auth.uid();org uuid;vendor uuid;brand uuid;req uuid;a text;choices jsonb;row_before tj.brand_training_cards%ROWTYPE;row_after tj.brand_training_cards%ROWTYPE;r tj_private.brand_training_requests%ROWTYPE;d jsonb;k text;v jsonb;obj jsonb;brand_name text;had boolean;
BEGIN
 IF actor IS NULL OR NOT EXISTS(SELECT 1 FROM auth.users WHERE id=n AND email_confirmed_at IS NOT NULL) THEN RETURN jsonb_build_object('ok',false,'error','identity_review_required');END IF;
 IF p_body IS NULL OR jsonb_typeof(p_body)<>'object' OR octet_length(p_body::text)>131072 OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_body) keys(key_name) WHERE keys.key_name NOT IN('action','organization_id','vendor_id','request_id','expected_updated_at','fields')) THEN RETURN jsonb_build_object('ok',false,'error','invalid_request');END IF;
 a:=p_body->>'action';vendor:=(p_body->>'vendor_id')::uuid;org:=(p_body->>'organization_id')::uuid;
 IF a IS NULL OR a NOT IN('get','create','save','approve') THEN RETURN jsonb_build_object('ok',false,'error','invalid_request');END IF;
 SELECT v.brand_id,b.brand_name INTO brand,brand_name FROM tj.mfr_vendors v JOIN tj.brand_catalog b ON b.id=v.brand_id WHERE v.id=vendor AND v.status='active' AND b.is_active;
 IF brand IS NULL THEN RETURN jsonb_build_object('ok',false,'error','brand_link_required');END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',o.id,'name',o.name) ORDER BY o.name,o.id),'[]'::jsonb) INTO choices FROM tj.organizations o WHERE tj_private.brand_training_access(o.id,vendor,'read');
 IF org IS NULL AND a='get' THEN
 IF jsonb_array_length(choices)=1 THEN org:=(choices->0->>'id')::uuid;ELSE RETURN jsonb_build_object('ok',true,'organizations',choices,'organization_id',NULL,'card',NULL,'brand',jsonb_build_object('id',brand,'brand_name',brand_name),'can_write',false,'can_review',false);END IF;END IF;
 IF NOT tj_private.brand_training_access(org,vendor,'read') THEN RETURN jsonb_build_object('ok',false,'error','forbidden');END IF;
 IF a='get' THEN
 SELECT * INTO row_after FROM tj.brand_training_cards WHERE organization_id=org AND brand_id=brand;
 RETURN jsonb_build_object('ok',true,'organization_id',org,'organizations',choices,'brand',jsonb_build_object('id',brand,'brand_name',brand_name),'card',CASE WHEN row_after.id IS NULL THEN NULL ELSE to_jsonb(row_after) END,'can_write',tj_private.brand_training_access(org,vendor,'write'),'can_review',tj_private.brand_training_access(org,vendor,'review'));END IF;
 IF NOT tj_private.brand_training_access(org,vendor,CASE WHEN a='approve' THEN 'review' ELSE 'write' END) THEN RETURN jsonb_build_object('ok',false,'error','forbidden');END IF;
 req:=(p_body->>'request_id')::uuid;IF req IS NULL OR NOT(p_body?'expected_updated_at') THEN RETURN jsonb_build_object('ok',false,'error','invalid_request');END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(org::text||n::text||req::text,0));PERFORM pg_advisory_xact_lock(hashtextextended('brand-training:'||org::text||brand::text,0));
 SELECT * INTO r FROM tj_private.brand_training_requests WHERE organization_id=org AND native_actor=n AND request_id=req;
 IF FOUND THEN IF r.body IS DISTINCT FROM p_body THEN RETURN jsonb_build_object('ok',false,'error','request_conflict');END IF;RETURN jsonb_build_object('ok',true,'replayed',true,'card',r.after_image);END IF;
 SELECT * INTO row_before FROM tj.brand_training_cards WHERE organization_id=org AND brand_id=brand FOR UPDATE;had:=FOUND;
 IF (a='create' AND had) OR (a<>'create' AND NOT had) OR (p_body->>'expected_updated_at')::timestamptz IS DISTINCT FROM row_before.updated_at THEN RETURN jsonb_build_object('ok',false,'error','revision_conflict');END IF;
 IF a='create' THEN
 IF p_body?'fields' THEN RETURN jsonb_build_object('ok',false,'error','invalid_request');END IF;
 INSERT INTO tj.brand_training_cards(organization_id,brand_id,status,version,editor_id,manufacturer_approved,updated_at) VALUES(org,brand,'draft',1,actor,false,clock_timestamp()) RETURNING * INTO row_after;
 ELSIF a='save' THEN
 d:=p_body->'fields';IF jsonb_typeof(d) IS DISTINCT FROM 'object' OR d='{}'::jsonb THEN RETURN jsonb_build_object('ok',false,'error','invalid_request');END IF;
 FOR k,v IN SELECT * FROM jsonb_each(d) LOOP
 IF k IN('heritage','brand_positioning','customer_profile','price_position','competitive_advantage','competitive_weakness','known_for','parent_company','country_of_origin','founded_year') THEN
 IF jsonb_typeof(v) NOT IN('null','string') OR length(v#>>'{}')>10000 THEN RETURN jsonb_build_object('ok',false,'error','invalid_request');END IF;
 ELSIF k='floor_talking_points' THEN
 IF jsonb_typeof(v)<>'array' OR jsonb_array_length(v)>50 THEN RETURN jsonb_build_object('ok',false,'error','invalid_request');END IF;
 FOR obj IN SELECT value FROM jsonb_array_elements(v) LOOP IF jsonb_typeof(obj)<>'string' OR length(btrim(obj#>>'{}')) NOT BETWEEN 1 AND 2000 THEN RETURN jsonb_build_object('ok',false,'error','invalid_request');END IF;END LOOP;
 ELSIF k='common_objections' THEN
 IF jsonb_typeof(v)<>'array' OR jsonb_array_length(v)>50 THEN RETURN jsonb_build_object('ok',false,'error','invalid_request');END IF;
 FOR obj IN SELECT value FROM jsonb_array_elements(v) LOOP
 IF jsonb_typeof(obj)<>'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(obj) x WHERE x NOT IN('objection','response')) OR jsonb_typeof(obj->'objection') IS DISTINCT FROM 'string' OR jsonb_typeof(obj->'response') IS DISTINCT FROM 'string' OR length(btrim(obj->>'objection')) NOT BETWEEN 1 AND 2000 OR length(btrim(obj->>'response')) NOT BETWEEN 1 AND 2000 THEN RETURN jsonb_build_object('ok',false,'error','invalid_request');END IF;END LOOP;
 ELSE RETURN jsonb_build_object('ok',false,'error','invalid_request');END IF;END LOOP;
 row_after:=jsonb_populate_record(row_before,d);
 UPDATE tj.brand_training_cards SET heritage=row_after.heritage,brand_positioning=row_after.brand_positioning,customer_profile=row_after.customer_profile,price_position=row_after.price_position,competitive_advantage=row_after.competitive_advantage,competitive_weakness=row_after.competitive_weakness,known_for=row_after.known_for,parent_company=row_after.parent_company,country_of_origin=row_after.country_of_origin,founded_year=row_after.founded_year,floor_talking_points=row_after.floor_talking_points,common_objections=row_after.common_objections,status='draft',manufacturer_approved=false,reviewed_by=NULL,last_reviewed_at=NULL,next_review_at=NULL,confidence_score=0,editor_id=actor,version=coalesce(row_before.version,0)+1,updated_at=clock_timestamp() WHERE id=row_before.id RETURNING * INTO row_after;
 ELSE
 IF p_body?'fields' THEN RETURN jsonb_build_object('ok',false,'error','invalid_request');END IF;
 IF row_before.editor_id IS NULL OR row_before.editor_id=actor OR row_before.status<>'draft' OR NOT EXISTS(SELECT 1 FROM tj_private.brand_training_requests h WHERE h.organization_id=org AND h.after_image->>'id'=row_before.id::text AND h.after_image->>'updated_at'=to_jsonb(row_before)->>'updated_at' AND h.body->>'action'='save') THEN RETURN jsonb_build_object('ok',false,'error','independent_saved_review_required');END IF;
 UPDATE tj.brand_training_cards SET manufacturer_approved=true,reviewed_by=actor,last_reviewed_at=clock_timestamp(),status='published',updated_at=clock_timestamp() WHERE id=row_before.id RETURNING * INTO row_after;
 END IF;
 INSERT INTO tj_private.brand_training_requests(organization_id,native_actor,source_actor,request_id,body,before_image,after_image) VALUES(org,n,actor,req,p_body,CASE WHEN had THEN to_jsonb(row_before) ELSE NULL END,to_jsonb(row_after));
 RETURN jsonb_build_object('ok',true,'replayed',false,'card',to_jsonb(row_after));
EXCEPTION WHEN invalid_text_representation OR invalid_parameter_value OR datetime_field_overflow OR numeric_value_out_of_range THEN RETURN jsonb_build_object('ok',false,'error','invalid_request');
END $$;
REVOKE ALL ON FUNCTION tj_private.brand_training(jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.brand_training(jsonb) TO authenticated;
CREATE FUNCTION public.tj_runtime_brand_training(p_body jsonb) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.brand_training(p_body); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_brand_training(jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.tj_runtime_brand_training(jsonb) TO authenticated;
