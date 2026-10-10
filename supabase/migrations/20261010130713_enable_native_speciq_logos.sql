CREATE TABLE tj_private.speciq_logo_uploads(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL REFERENCES tj.organizations(id),
 native_actor uuid NOT NULL REFERENCES auth.users(id),source_actor uuid NOT NULL REFERENCES tj.source_auth_users(id),
 request_id uuid NOT NULL,body jsonb NOT NULL,storage_path text NOT NULL UNIQUE,mime_type text NOT NULL,
 file_size bigint NOT NULL CHECK(file_size BETWEEN 1 AND 2097152),expected_updated_at timestamptz NOT NULL,
 expires_at timestamptz NOT NULL DEFAULT clock_timestamp()+interval '30 minutes',completed_at timestamptz,
 before_image jsonb,after_image jsonb,UNIQUE(organization_id,native_actor,request_id));
ALTER TABLE tj_private.speciq_logo_uploads ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj_private.speciq_logo_uploads FROM PUBLIC,anon,authenticated,service_role;
CREATE INDEX speciq_logo_native_idx ON tj_private.speciq_logo_uploads(native_actor);
CREATE INDEX speciq_logo_source_idx ON tj_private.speciq_logo_uploads(source_actor);
INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types) VALUES('tj-speciq-logos','tj-speciq-logos',false,2097152,ARRAY['image/png','image/jpeg','image/webp']);
CREATE FUNCTION tj_private.speciq_logo_upload_allowed(p_path text) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM tj_private.speciq_logo_uploads u WHERE u.storage_path=p_path AND u.native_actor=(SELECT auth.uid()) AND u.completed_at IS NULL AND u.expires_at>clock_timestamp() AND tj_private.speciq_actor_role(u.organization_id) IN('owner','admin'));
$$;
CREATE FUNCTION tj_private.speciq_logo_read_allowed(p_path text) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM tj_private.speciq_logo_uploads u WHERE u.storage_path=p_path AND tj_private.speciq_actor_role(u.organization_id) IS NOT NULL AND (u.completed_at IS NOT NULL OR u.native_actor=(SELECT auth.uid()) AND u.expires_at>clock_timestamp()));
$$;
REVOKE ALL ON FUNCTION tj_private.speciq_logo_upload_allowed(text),tj_private.speciq_logo_read_allowed(text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.speciq_logo_upload_allowed(text),tj_private.speciq_logo_read_allowed(text) TO authenticated;
CREATE POLICY native_speciq_logo_upload ON storage.objects FOR INSERT TO authenticated WITH CHECK(bucket_id='tj-speciq-logos' AND owner_id=(SELECT auth.uid())::text AND tj_private.speciq_logo_upload_allowed(name));
CREATE POLICY native_speciq_logo_read ON storage.objects FOR SELECT TO authenticated USING(bucket_id='tj-speciq-logos' AND tj_private.speciq_logo_read_allowed(name));
CREATE FUNCTION tj_private.speciq_logos(p_body jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE org uuid;role_name text;a text;req uuid;item tj_private.speciq_logo_uploads%ROWTYPE;s tj.speciq_retailer_settings%ROWTYPE;size_bytes bigint;mime text;path text;
BEGIN
 IF jsonb_typeof(p_body) IS DISTINCT FROM 'object' OR octet_length(p_body::text)>4096 THEN RETURN jsonb_build_object('ok',false,'error','invalid_request');END IF;
 org:=(p_body->>'organization_id')::uuid;a:=p_body->>'action';role_name:=tj_private.speciq_actor_role(org);
 IF role_name IS NULL THEN RETURN jsonb_build_object('ok',false,'error','organization_access_required');END IF;
 IF a='read' THEN
 SELECT * INTO s FROM tj.speciq_retailer_settings WHERE organization_id=org;
 IF s.logo_url IS NULL OR s.logo_url NOT LIKE 'storage://tj-speciq-logos/%' THEN RETURN jsonb_build_object('ok',true,'storage_path',NULL);END IF;
 path:=substr(s.logo_url,length('storage://tj-speciq-logos/')+1);
 IF NOT tj_private.speciq_logo_read_allowed(path) THEN RETURN jsonb_build_object('ok',false,'error','logo_unavailable');END IF;
 RETURN jsonb_build_object('ok',true,'bucket','tj-speciq-logos','storage_path',path);END IF;
 IF role_name NOT IN('owner','admin') THEN RETURN jsonb_build_object('ok',false,'error','organization_admin_required');END IF;
 IF a='reserve' THEN
 req:=(p_body->>'request_id')::uuid;size_bytes:=(p_body->>'file_size')::bigint;mime:=p_body->>'mime_type';
 IF req IS NULL OR size_bytes IS NULL OR size_bytes NOT BETWEEN 1 AND 2097152 OR mime IS NULL OR mime NOT IN('image/png','image/jpeg','image/webp') THEN RETURN jsonb_build_object('ok',false,'error','invalid_request');END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(org::text||auth.uid()::text||req::text,0));
 SELECT * INTO item FROM tj_private.speciq_logo_uploads WHERE organization_id=org AND native_actor=auth.uid() AND request_id=req;
 IF FOUND THEN
 IF item.body<>p_body THEN RETURN jsonb_build_object('ok',false,'error','request_conflict');END IF;
 IF item.completed_at IS NULL AND item.expires_at<=clock_timestamp() THEN RETURN jsonb_build_object('ok',false,'error','reservation_expired');END IF;
 ELSE
 SELECT * INTO s FROM tj.speciq_retailer_settings WHERE organization_id=org;
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','settings_required');END IF;
 IF s.updated_at IS DISTINCT FROM (p_body->>'expected_updated_at')::timestamptz THEN RETURN jsonb_build_object('ok',false,'error','revision_conflict');END IF;
 path:=org::text||'/'||auth.uid()::text||'/'||gen_random_uuid()::text||CASE mime WHEN 'image/png' THEN '.png' WHEN 'image/jpeg' THEN '.jpg' ELSE '.webp' END;
 INSERT INTO tj_private.speciq_logo_uploads(organization_id,native_actor,source_actor,request_id,body,storage_path,mime_type,file_size,expected_updated_at) VALUES(org,auth.uid(),tj_private.microsoft_actor(auth.uid()),req,p_body,path,mime,size_bytes,s.updated_at) RETURNING * INTO item;
 END IF;
 RETURN jsonb_build_object('ok',true,'upload_id',item.id,'bucket','tj-speciq-logos','storage_path',item.storage_path,'completed',item.completed_at IS NOT NULL);
 ELSIF a='finalize' THEN
 SELECT * INTO item FROM tj_private.speciq_logo_uploads WHERE id=(p_body->>'upload_id')::uuid AND organization_id=org AND native_actor=auth.uid() FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','logo_unavailable');END IF;
 IF item.completed_at IS NOT NULL THEN RETURN jsonb_build_object('ok',true,'replayed',true);END IF;
 IF item.expires_at<=clock_timestamp() THEN RETURN jsonb_build_object('ok',false,'error','reservation_expired');END IF;
 IF NOT EXISTS(SELECT 1 FROM storage.objects o WHERE o.bucket_id='tj-speciq-logos' AND o.name=item.storage_path AND o.owner_id=auth.uid()::text AND (o.metadata->>'size')::bigint=item.file_size AND o.metadata->>'mimetype'=item.mime_type) THEN RETURN jsonb_build_object('ok',false,'error','upload_incomplete');END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('speciq-settings:'||org::text,0));
 SELECT * INTO s FROM tj.speciq_retailer_settings WHERE organization_id=org FOR UPDATE;
 IF NOT FOUND OR s.updated_at IS DISTINCT FROM item.expected_updated_at THEN RETURN jsonb_build_object('ok',false,'error','revision_conflict');END IF;
 UPDATE tj_private.speciq_logo_uploads SET before_image=to_jsonb(s) WHERE id=item.id;
 UPDATE tj.speciq_retailer_settings SET logo_url='storage://tj-speciq-logos/'||item.storage_path,updated_at=clock_timestamp() WHERE organization_id=org RETURNING * INTO s;
 UPDATE tj_private.speciq_logo_uploads SET completed_at=clock_timestamp(),after_image=to_jsonb(s) WHERE id=item.id;
 RETURN jsonb_build_object('ok',true,'replayed',false);
 END IF;
 RETURN jsonb_build_object('ok',false,'error','invalid_request');
EXCEPTION WHEN invalid_text_representation OR invalid_parameter_value OR datetime_field_overflow OR numeric_value_out_of_range THEN RETURN jsonb_build_object('ok',false,'error','invalid_request');
END;
$$;
CREATE FUNCTION public.tj_runtime_speciq_logos(p_body jsonb) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.speciq_logos(p_body); $$;
REVOKE ALL ON FUNCTION tj_private.speciq_logos(jsonb),public.tj_runtime_speciq_logos(jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.speciq_logos(jsonb),public.tj_runtime_speciq_logos(jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';
