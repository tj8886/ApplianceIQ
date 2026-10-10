BEGIN;
DO $$
DECLARE actor uuid;n uuid;org uuid;r jsonb;body jsonb;upload uuid;path text;stamp timestamptz;
BEGIN
 SELECT im.source_user_id,im.target_user_id INTO actor,n FROM tj.source_user_identity_map im JOIN auth.users u ON u.id=im.target_user_id WHERE tj_private.microsoft_actor(u.id)=im.source_user_id AND u.email_confirmed_at IS NOT NULL LIMIT 1;
 INSERT INTO tj.organizations(name,slug) VALUES('Logo rollback fixture','spec-logo-rollback-'||gen_random_uuid()) RETURNING id INTO org;
 INSERT INTO tj.organization_members(organization_id,user_id,role,status) VALUES(org,actor,'owner','active');
 INSERT INTO tj.speciq_retailer_settings(organization_id,store_name,logo_url) VALUES(org,'Fixture','https://example.invalid/old.png') RETURNING updated_at INTO stamp;
 PERFORM set_config('request.jwt.claim.sub',n::text,true);
 body:=jsonb_build_object('action','reserve','organization_id',org,'request_id',gen_random_uuid(),'expected_updated_at',stamp,'mime_type','image/png','file_size',8);
 r:=public.tj_runtime_speciq_logos(body);IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'reserve failed %',r;END IF;upload:=(r->>'upload_id')::uuid;path:=r->>'storage_path';
 r:=public.tj_runtime_speciq_logos(body);IF (r->>'upload_id')::uuid<>upload THEN RAISE EXCEPTION 'reserve replay failed';END IF;
 r:=public.tj_runtime_speciq_logos(body||jsonb_build_object('file_size',9));IF r->>'error' IS DISTINCT FROM 'request_conflict' THEN RAISE EXCEPTION 'conflicting reserve accepted';END IF;
 r:=public.tj_runtime_speciq_logos(jsonb_build_object('action','finalize','organization_id',org,'upload_id',upload));IF r->>'error' IS DISTINCT FROM 'upload_incomplete' THEN RAISE EXCEPTION 'missing object finalized';END IF;
 INSERT INTO storage.objects(bucket_id,name,owner_id,metadata) VALUES('tj-speciq-logos',path,n::text,jsonb_build_object('size',9,'mimetype','image/png'));
 r:=public.tj_runtime_speciq_logos(jsonb_build_object('action','finalize','organization_id',org,'upload_id',upload));IF r->>'error' IS DISTINCT FROM 'upload_incomplete' THEN RAISE EXCEPTION 'wrong size finalized';END IF;
 UPDATE storage.objects SET metadata=jsonb_build_object('size',8,'mimetype','image/png') WHERE bucket_id='tj-speciq-logos' AND name=path;
 r:=public.tj_runtime_speciq_logos(jsonb_build_object('action','finalize','organization_id',org,'upload_id',upload));IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'finalize failed %',r;END IF;
 r:=public.tj_runtime_speciq_logos(jsonb_build_object('action','finalize','organization_id',org,'upload_id',upload));IF r->>'replayed' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'finalize replay failed';END IF;
 IF NOT EXISTS(SELECT 1 FROM tj_private.speciq_logo_uploads WHERE id=upload AND before_image->>'logo_url'='https://example.invalid/old.png' AND after_image->>'logo_url'='storage://tj-speciq-logos/'||path) THEN RAISE EXCEPTION 'logo history missing';END IF;
 UPDATE tj.organization_members SET role='viewer' WHERE organization_id=org AND user_id=actor;
 r:=public.tj_runtime_speciq_logos(body);IF r->>'error' IS DISTINCT FROM 'organization_admin_required' THEN RAISE EXCEPTION 'viewer upload allowed';END IF;
 r:=public.tj_runtime_speciq_logos(jsonb_build_object('action','read','organization_id',org));IF r->>'storage_path'<>path THEN RAISE EXCEPTION 'member read failed';END IF;
 UPDATE tj.organization_members SET status='suspended' WHERE organization_id=org AND user_id=actor;
 r:=public.tj_runtime_speciq_logos(jsonb_build_object('action','read','organization_id',org));IF r->>'error' IS DISTINCT FROM 'organization_access_required' THEN RAISE EXCEPTION 'suspended read allowed';END IF;
 UPDATE tj.organization_members SET status='active',role='owner' WHERE organization_id=org AND user_id=actor;
 PERFORM set_config('test.logo.native',n::text,true);PERFORM set_config('test.logo.org',org::text,true);PERFORM set_config('test.logo.path',path,true);
 SELECT updated_at INTO stamp FROM tj.speciq_retailer_settings WHERE organization_id=org;
 r:=public.tj_runtime_speciq_logos(jsonb_build_object('action','reserve','organization_id',org,'request_id',gen_random_uuid(),'expected_updated_at',stamp,'mime_type','image/png','file_size',8));IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'second reservation failed';END IF;
 PERFORM set_config('test.logo.pending_path',r->>'storage_path',true);
 IF has_function_privilege('anon','public.tj_runtime_speciq_logos(jsonb)','EXECUTE') THEN RAISE EXCEPTION 'anonymous access';END IF;
END $$;
SET LOCAL ROLE authenticated;
DO $$DECLARE r jsonb;c bigint;BEGIN
 PERFORM set_config('request.jwt.claim.sub',current_setting('test.logo.native'),true);
 r:=public.tj_runtime_speciq_logos(jsonb_build_object('action','read','organization_id',current_setting('test.logo.org')));IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'native wrapper failed';END IF;
 SELECT count(*) INTO c FROM storage.objects WHERE bucket_id='tj-speciq-logos' AND name=current_setting('test.logo.path');IF c<>1 THEN RAISE EXCEPTION 'authenticated storage read denied';END IF;
 INSERT INTO storage.objects(bucket_id,name,owner_id,metadata) VALUES('tj-speciq-logos',current_setting('test.logo.pending_path'),current_setting('test.logo.native'),jsonb_build_object('size',8,'mimetype','image/png'));
 BEGIN
  INSERT INTO storage.objects(bucket_id,name,owner_id,metadata) VALUES('tj-speciq-logos',current_setting('test.logo.pending_path')||'.foreign',current_setting('test.logo.native'),jsonb_build_object('size',8,'mimetype','image/png'));
  RAISE EXCEPTION 'unreserved upload allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 UPDATE storage.objects SET metadata='{}'::jsonb WHERE bucket_id='tj-speciq-logos' AND name=current_setting('test.logo.path');GET DIAGNOSTICS c=ROW_COUNT;IF c<>0 THEN RAISE EXCEPTION 'logo overwrite allowed';END IF;
END $$;
ROLLBACK;
SELECT 'PASS: logo reserve/replay/metadata-finalize/read, owner/viewer/suspended gates, retained before/after and actual authenticated storage SELECT/INSERT, unreserved upload and UPDATE denied and delete policy absent (catalog check); fixtures rolled back; file bytes not exercised' result;
