CREATE FUNCTION tj_private.ai_manager_register_attachment(p_assignment_id uuid,p_storage_path text,
 p_file_name text,p_mime_type text,p_file_size_bytes bigint,p_attachment_type text DEFAULT 'supporting')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$ DECLARE a tj.ai_manager_assignments; uid uuid:=tj_private.current_source_user_id(); aid uuid;
BEGIN
 SELECT * INTO a FROM tj.ai_manager_assignments WHERE id=p_assignment_id FOR UPDATE;
 IF uid IS NULL OR a.id IS NULL OR NOT EXISTS(SELECT 1 FROM tj_private.my_platform_organizations() o
 WHERE o.organization_id=a.organization_id) THEN RETURN jsonb_build_object('error','access_denied'); END IF;
 IF p_storage_path IS NULL OR split_part(p_storage_path,'/',1)<>a.organization_id::text
 OR split_part(p_storage_path,'/',2)<>a.id::text THEN RETURN jsonb_build_object('error','invalid_storage_path'); END IF;
 IF p_file_size_bytes IS NULL OR p_file_size_bytes<0 OR NOT EXISTS(SELECT 1 FROM storage.objects o
 WHERE o.bucket_id='manager-task-files' AND o.name=p_storage_path
 AND o.metadata->>'mimetype'=p_mime_type AND (o.metadata->>'size')::bigint=p_file_size_bytes)
 THEN RETURN jsonb_build_object('error','stored_object_missing_or_metadata_mismatch'); END IF;
 INSERT INTO tj.ai_manager_task_attachments(organization_id,assignment_id,uploaded_by,storage_path,
 file_name,mime_type,file_size_bytes,attachment_type)
 VALUES(a.organization_id,a.id,uid,p_storage_path,p_file_name,p_mime_type,p_file_size_bytes,p_attachment_type)
 RETURNING id INTO aid;
 INSERT INTO tj.ai_manager_task_history(organization_id,assignment_id,actor_id,event_type,note,metadata)
 VALUES(a.organization_id,a.id,uid,'attachment_added',p_file_name,jsonb_build_object('attachment_type',p_attachment_type));
 RETURN jsonb_build_object('ok',true,'attachment_id',aid);
END $$;
CREATE FUNCTION tj.ai_manager_register_attachment(p_assignment_id uuid,p_storage_path text,p_file_name text,
 p_mime_type text,p_file_size_bytes bigint,p_attachment_type text DEFAULT 'supporting')
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path=''
AS $$ SELECT tj_private.ai_manager_register_attachment(p_assignment_id,p_storage_path,p_file_name,
 p_mime_type,p_file_size_bytes,p_attachment_type); $$;
REVOKE ALL ON FUNCTION tj_private.ai_manager_register_attachment(uuid,text,text,text,bigint,text),
 tj.ai_manager_register_attachment(uuid,text,text,text,bigint,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj_private.ai_manager_register_attachment(uuid,text,text,text,bigint,text),
 tj.ai_manager_register_attachment(uuid,text,text,text,bigint,text) TO authenticated;
NOTIFY pgrst,'reload schema';
