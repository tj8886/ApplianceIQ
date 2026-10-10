-- New native library contract. No source/destination files or historical tables are removed.
CREATE TABLE tj.mfr_assets (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization_id uuid NOT NULL REFERENCES tj.organizations(id),
 vendor_id uuid NOT NULL REFERENCES tj.mfr_vendors(id),
 category text NOT NULL CHECK(category IN('spec_sheet','install_guide','owners_manual','warranty','energy_guide','parts_diagram','cad_file','sell_sheet','product_image','comparison','faq_objection','promo','price_map','spiff','coop','launch','discontinuation','service_bulletin','rep_directory','availability','training_video','training_doc','certification','brand_video')),
 title text NOT NULL CHECK(length(title) BETWEEN 1 AND 200),
 description text CHECK(length(description)<=2000),model text CHECK(length(model)<=100),
 audiences text[] NOT NULL CHECK(cardinality(audiences) BETWEEN 1 AND 3 AND audiences<@ARRAY['retailer','builder','designer']::text[]),
 external_url text,storage_path text UNIQUE,file_name text,mime_type text,file_size_bytes bigint,
 upload_state text NOT NULL CHECK(upload_state IN('pending','ready')),
 is_published boolean NOT NULL DEFAULT false,
 uploaded_by uuid NOT NULL REFERENCES tj.source_auth_users(id),
 uploaded_native uuid NOT NULL REFERENCES auth.users(id),
 approved_by uuid REFERENCES tj.source_auth_users(id),approved_at timestamptz,
 archived_at timestamptz,created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK((external_url IS NOT NULL AND storage_path IS NULL AND upload_state='ready') OR (external_url IS NULL AND storage_path IS NOT NULL AND file_name IS NOT NULL AND mime_type IS NOT NULL AND file_size_bytes BETWEEN 1 AND 20971520)),
 CHECK(NOT is_published OR (upload_state='ready' AND approved_by IS NOT NULL AND approved_at IS NOT NULL AND archived_at IS NULL))
);
ALTER TABLE tj.mfr_assets ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj.mfr_assets FROM PUBLIC,anon,authenticated,service_role;
CREATE INDEX mfr_assets_org_vendor_created_idx ON tj.mfr_assets(organization_id,vendor_id,created_at DESC);
CREATE INDEX mfr_assets_vendor_idx ON tj.mfr_assets(vendor_id);
CREATE INDEX mfr_assets_uploader_idx ON tj.mfr_assets(uploaded_by);
CREATE INDEX mfr_assets_native_idx ON tj.mfr_assets(uploaded_native);
CREATE INDEX mfr_assets_approver_idx ON tj.mfr_assets(approved_by);

CREATE FUNCTION tj_private.mfr_asset_org_member(p_org uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM tj.organization_members m JOIN tj.organizations o ON o.id=m.organization_id JOIN auth.users u ON u.id=(SELECT auth.uid())
 WHERE m.organization_id=p_org AND m.user_id=tj_private.microsoft_actor(u.id) AND m.status='active' AND o.status='active' AND o.deleted_at IS NULL AND u.email_confirmed_at IS NOT NULL);
$$;
CREATE FUNCTION tj_private.mfr_asset_vendor_access(p_org uuid,p_vendor uuid,p_mode text DEFAULT 'read')
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT tj_private.mfr_asset_org_member(p_org) AND EXISTS(SELECT 1 FROM tj.mfr_vendors v WHERE v.id=p_vendor AND v.status='active')
 AND (tj_private.manufacturer_invite_admin(tj_private.microsoft_actor((SELECT auth.uid())),p_org) OR EXISTS(
 SELECT 1 FROM tj.mfr_members m WHERE m.user_id=tj_private.microsoft_actor((SELECT auth.uid())) AND m.vendor_id=p_vendor
 AND m.status='active' AND m.role IS NOT NULL AND m.approved_by IS NOT NULL AND m.approved_at IS NOT NULL AND m.activated_at IS NOT NULL
 AND (m.expires_at IS NULL OR m.expires_at>now())
 AND (p_mode='read' OR (p_mode='write' AND m.role IN('vendor_owner','vendor_admin','brand_admin','product_editor','asset_editor'))
 OR (p_mode='review' AND m.role IN('vendor_owner','vendor_admin','brand_admin','product_reviewer')))));
$$;
CREATE FUNCTION tj_private.mfr_asset_read(p_org uuid,p_vendor uuid,p_published boolean,p_audiences text[])
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT tj_private.mfr_asset_vendor_access(p_org,p_vendor,'read') OR (p_published AND tj_private.mfr_asset_org_member(p_org)
 AND EXISTS(SELECT 1 FROM tj.mfr_vendors v WHERE v.id=p_vendor AND v.status='active')
 AND EXISTS(SELECT 1 FROM tj.mfr_user_roles r WHERE r.user_id=tj_private.microsoft_actor((SELECT auth.uid()))
 AND ((r.is_builder AND 'builder'=ANY(p_audiences)) OR (r.is_designer AND 'designer'=ANY(p_audiences)) OR (r.is_retailer AND 'retailer'=ANY(p_audiences)))));
$$;
CREATE FUNCTION tj_private.mfr_asset_storage_upload(p_path text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM tj.mfr_assets a WHERE a.storage_path=p_path AND a.uploaded_native=(SELECT auth.uid()) AND a.upload_state='pending' AND a.archived_at IS NULL AND tj_private.mfr_asset_vendor_access(a.organization_id,a.vendor_id,'write'));
$$;
CREATE FUNCTION tj_private.mfr_asset_storage_read(p_path text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM tj.mfr_assets a WHERE a.storage_path=p_path AND a.upload_state='ready' AND a.archived_at IS NULL AND tj_private.mfr_asset_read(a.organization_id,a.vendor_id,a.is_published,a.audiences));
$$;
REVOKE ALL ON FUNCTION tj_private.mfr_asset_org_member(uuid),tj_private.mfr_asset_vendor_access(uuid,uuid,text),tj_private.mfr_asset_read(uuid,uuid,boolean,text[]),tj_private.mfr_asset_storage_upload(text),tj_private.mfr_asset_storage_read(text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.mfr_asset_read(uuid,uuid,boolean,text[]),tj_private.mfr_asset_storage_upload(text),tj_private.mfr_asset_storage_read(text) TO authenticated;
CREATE POLICY native_manufacturer_asset_read ON tj.mfr_assets FOR SELECT TO authenticated
 USING(archived_at IS NULL AND tj_private.mfr_asset_read(organization_id,vendor_id,is_published,audiences));
GRANT SELECT ON tj.mfr_assets TO authenticated;

INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 VALUES('tj-mfr-assets','tj-mfr-assets',false,20971520,ARRAY['application/pdf','image/jpeg','image/png','image/webp','text/plain','text/csv','application/zip','application/octet-stream','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','application/vnd.openxmlformats-officedocument.presentationml.presentation']);
CREATE POLICY native_manufacturer_file_upload ON storage.objects FOR INSERT TO authenticated
 WITH CHECK(bucket_id='tj-mfr-assets' AND owner_id=(SELECT auth.uid())::text AND tj_private.mfr_asset_storage_upload(name));
CREATE POLICY native_manufacturer_file_read ON storage.objects FOR SELECT TO authenticated
 USING(bucket_id='tj-mfr-assets' AND tj_private.mfr_asset_storage_read(name));
-- No object overwrite/delete policies; archival keeps the file and closes future access.

CREATE FUNCTION tj_private.manufacturer_assets(p_body jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=tj_private.microsoft_actor(auth.uid());action text;org uuid;vendor uuid;aid uuid;item tj.mfr_assets%ROWTYPE;
 choices jsonb;rows jsonb;audiences text[];audience text;size bigint;path text;filename text;url text;vrow tj.mfr_vendors%ROWTYPE;
BEGIN
 IF p_body IS NULL OR jsonb_typeof(p_body)<>'object' OR octet_length(p_body::text)>12000 OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_body) k WHERE k NOT IN('action','organization_id','vendor_id','asset_id','category','title','description','model','audiences','external_url','file_name','mime_type','file_size_bytes','audience')) THEN RETURN jsonb_build_object('ok',false,'error','invalid_request');END IF;
 action:=p_body->>'action';IF action IS NULL OR action NOT IN('list','trade','create_link','reserve_upload','finalize','publish','archive') THEN RETURN jsonb_build_object('ok',false,'error','invalid_request');END IF;
 IF actor IS NULL THEN RETURN jsonb_build_object('ok',false,'error','identity_review_required');END IF;
 IF NOT EXISTS(SELECT 1 FROM auth.users WHERE id=auth.uid() AND email_confirmed_at IS NOT NULL) THEN RETURN jsonb_build_object('ok',false,'error','email_confirmation_required');END IF;
 IF action='trade' THEN
  SELECT CASE WHEN r.is_builder THEN 'builder' WHEN r.is_designer THEN 'designer' END INTO audience FROM tj.mfr_user_roles r WHERE r.user_id=actor;
  IF p_body ? 'audience' THEN audience:=p_body->>'audience';END IF;
  IF audience IS NULL OR audience NOT IN('builder','designer') OR NOT EXISTS(SELECT 1 FROM tj.mfr_user_roles r WHERE r.user_id=actor AND ((audience='builder' AND r.is_builder) OR (audience='designer' AND r.is_designer))) THEN RETURN jsonb_build_object('ok',false,'error','trade_access_required');END IF;
  SELECT coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) INTO rows FROM (
   SELECT a.id,a.vendor_id,a.category,a.title,a.description,a.model,a.audiences,a.external_url,a.storage_path,a.file_name,a.is_published,a.upload_state,a.created_at
   FROM tj.mfr_assets a WHERE a.is_published AND a.upload_state='ready' AND a.archived_at IS NULL AND audience=ANY(a.audiences)
   AND tj_private.mfr_asset_org_member(a.organization_id) AND tj_private.mfr_asset_read(a.organization_id,a.vendor_id,true,a.audiences) ORDER BY a.created_at DESC,a.id LIMIT 200
  ) x;
  RETURN jsonb_build_object('ok',true,'audience',audience,'assets',rows,'vendors',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',v.id,'name',v.name,'slug',v.slug,'tier',v.tier) ORDER BY v.name),'[]'::jsonb) FROM tj.mfr_vendors v WHERE v.status='active' AND v.id IN(SELECT (x->>'vendor_id')::uuid FROM jsonb_array_elements(rows) x)));
 END IF;
 IF action IN('finalize','publish','archive') THEN
  aid:=(p_body->>'asset_id')::uuid;
  SELECT * INTO item FROM tj.mfr_assets WHERE id=aid AND archived_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','asset_unavailable');END IF;
  org:=item.organization_id;vendor:=item.vendor_id;
  IF NOT tj_private.mfr_asset_vendor_access(org,vendor,CASE WHEN action='publish' THEN 'review' ELSE 'write' END) THEN RETURN jsonb_build_object('ok',false,'error','forbidden');END IF;
  IF action='archive' THEN
   UPDATE tj.mfr_assets SET is_published=false,archived_at=now(),updated_at=now() WHERE id=aid;
  ELSIF action='publish' THEN
   IF item.upload_state<>'ready' THEN RETURN jsonb_build_object('ok',false,'error','upload_incomplete');END IF;
   UPDATE tj.mfr_assets SET is_published=true,approved_by=actor,approved_at=now(),updated_at=now() WHERE id=aid;
  ELSE
   IF item.uploaded_native IS DISTINCT FROM auth.uid() OR item.storage_path IS NULL THEN RETURN jsonb_build_object('ok',false,'error','forbidden');END IF;
   IF NOT EXISTS(SELECT 1 FROM storage.objects o WHERE o.bucket_id='tj-mfr-assets' AND o.name=item.storage_path AND o.owner_id=auth.uid()::text AND (o.metadata->>'size')::bigint=item.file_size_bytes AND o.metadata->>'mimetype'=item.mime_type) THEN RETURN jsonb_build_object('ok',false,'error','upload_incomplete');END IF;
   UPDATE tj.mfr_assets SET upload_state='ready',updated_at=now() WHERE id=aid;
  END IF;
  RETURN jsonb_build_object('ok',true,'asset_id',aid);
 END IF;
 vendor:=(p_body->>'vendor_id')::uuid;
 SELECT * INTO vrow FROM tj.mfr_vendors WHERE id=vendor AND status='active';
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','vendor_unavailable');END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',o.id,'name',o.name) ORDER BY o.name),'[]'::jsonb) INTO choices
 FROM tj.organizations o WHERE tj_private.mfr_asset_vendor_access(o.id,vendor,'read');
 IF jsonb_array_length(choices)=0 THEN RETURN jsonb_build_object('ok',false,'error','organization_access_required');END IF;
 org:=coalesce((p_body->>'organization_id')::uuid,(choices->0->>'id')::uuid);
 IF NOT tj_private.mfr_asset_vendor_access(org,vendor,CASE WHEN action='list' THEN 'read' ELSE 'write' END) THEN RETURN jsonb_build_object('ok',false,'error','forbidden');END IF;
 IF action='list' THEN
  SELECT coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) INTO rows FROM (
   SELECT a.id,a.organization_id,a.vendor_id,a.category,a.title,a.description,a.model,a.audiences,a.external_url,a.storage_path,a.file_name,a.is_published,a.upload_state,a.created_at
   FROM tj.mfr_assets a WHERE a.organization_id=org AND a.vendor_id=vendor AND a.archived_at IS NULL ORDER BY a.created_at DESC,a.id LIMIT 200
  ) x;
  RETURN jsonb_build_object('ok',true,'organization_id',org,'organizations',choices,'assets',rows,'can_write',tj_private.mfr_asset_vendor_access(org,vendor,'write'),'can_review',tj_private.mfr_asset_vendor_access(org,vendor,'review'),'bucket','tj-mfr-assets');
 END IF;
 IF length(btrim(coalesce(p_body->>'title',''))) NOT BETWEEN 1 AND 200 OR length(coalesce(p_body->>'description',''))>2000 OR length(coalesce(p_body->>'model',''))>100 OR jsonb_typeof(p_body->'audiences') IS DISTINCT FROM 'array' THEN RETURN jsonb_build_object('ok',false,'error','invalid_request');END IF;
 SELECT array_agg(DISTINCT value) INTO audiences FROM jsonb_array_elements_text(p_body->'audiences');
 IF audiences IS NULL OR cardinality(audiences)>3 OR NOT audiences<@ARRAY['retailer','builder','designer']::text[] THEN RETURN jsonb_build_object('ok',false,'error','invalid_request');END IF;
 IF coalesce(p_body->>'category','') NOT IN('spec_sheet','install_guide','owners_manual','warranty','energy_guide','parts_diagram','cad_file','sell_sheet','product_image','comparison','faq_objection','promo','price_map','spiff','coop','launch','discontinuation','service_bulletin','rep_directory','availability','training_video','training_doc','certification','brand_video') THEN RETURN jsonb_build_object('ok',false,'error','invalid_request');END IF;
 aid:=gen_random_uuid();
 IF action='create_link' THEN
  url:=btrim(p_body->>'external_url');
  IF url IS NULL OR length(url)>2048 OR url !~ '^https://[^/@[:space:]<>"'']+([/?#][^[:space:]<>"'']*)?$' THEN RETURN jsonb_build_object('ok',false,'error','invalid_request');END IF;
  INSERT INTO tj.mfr_assets(id,organization_id,vendor_id,category,title,description,model,audiences,external_url,upload_state,uploaded_by,uploaded_native)
  VALUES(aid,org,vendor,p_body->>'category',btrim(p_body->>'title'),nullif(btrim(p_body->>'description'),''),nullif(btrim(p_body->>'model'),''),audiences,url,'ready',actor,auth.uid());
 ELSE
  filename:=p_body->>'file_name';
  IF filename IS NULL OR filename !~* '^[A-Za-z0-9][A-Za-z0-9._-]{0,119}\.(pdf|jpg|jpeg|png|webp|txt|csv|zip|docx|xlsx|pptx|dwg|dxf|rvt|rfa)$' OR coalesce(p_body->>'file_size_bytes','') !~ '^[0-9]{1,8}$' THEN RETURN jsonb_build_object('ok',false,'error','invalid_request');END IF;
  size:=(p_body->>'file_size_bytes')::bigint;
  IF size NOT BETWEEN 1 AND 20971520 OR NOT coalesce(p_body->>'mime_type','')=ANY(ARRAY['application/pdf','image/jpeg','image/png','image/webp','text/plain','text/csv','application/zip','application/octet-stream','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','application/vnd.openxmlformats-officedocument.presentationml.presentation']) THEN RETURN jsonb_build_object('ok',false,'error','invalid_request');END IF;
  path:=org::text||'/'||vendor::text||'/'||aid::text||'/'||filename;
  INSERT INTO tj.mfr_assets(id,organization_id,vendor_id,category,title,description,model,audiences,storage_path,file_name,mime_type,file_size_bytes,upload_state,uploaded_by,uploaded_native)
  VALUES(aid,org,vendor,p_body->>'category',btrim(p_body->>'title'),nullif(btrim(p_body->>'description'),''),nullif(btrim(p_body->>'model'),''),audiences,path,filename,p_body->>'mime_type',size,'pending',actor,auth.uid());
 END IF;
 RETURN jsonb_build_object('ok',true,'asset_id',aid,'storage_path',path,'bucket','tj-mfr-assets','needs_review',true);
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN RETURN jsonb_build_object('ok',false,'error','invalid_request');
END;
$$;
REVOKE ALL ON FUNCTION tj_private.manufacturer_assets(jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.manufacturer_assets(jsonb) TO authenticated;
CREATE FUNCTION public.tj_runtime_manufacturer_assets(p_body jsonb) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.manufacturer_assets(p_body); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_manufacturer_assets(jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tj_runtime_manufacturer_assets(jsonb) TO authenticated;
