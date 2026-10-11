-- Correct PL/pgSQL record/SQL alias ambiguity found by rollback tests.
-- Native US sessions, verified source identity, and explicit organization scope.
-- Original field records, dates, and evidence remain unchanged.
CREATE OR REPLACE FUNCTION tj_private.field_report(p_action text,p_organization_id uuid DEFAULT NULL,p_id uuid DEFAULT NULL,p_data jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=tj_private.current_source_user_id(); actor_name text; v_action tj.field_actions;
 result jsonb; payload jsonb:=coalesce(p_data,'{}'); new_status text; note text; client uuid;
BEGIN
 IF auth.uid() IS NULL OR actor IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501';END IF;
 SELECT coalesce(nullif(full_name,''),actor::text) INTO actor_name FROM tj.profiles WHERE user_id=actor;
 actor_name:=coalesce(actor_name,actor::text);
 IF p_action='context' THEN
  RETURN jsonb_build_object('actor_name',actor_name,'organizations',coalesce((
   SELECT jsonb_agg(jsonb_build_object('id',o.id,'name',o.name) ORDER BY o.name,o.id)
   FROM tj.organizations o JOIN tj.organization_members m ON m.organization_id=o.id
   WHERE m.user_id=actor AND m.status='active' AND m.role IN('owner','admin','manager','super_admin')
   AND o.status='active' AND o.deleted_at IS NULL AND EXISTS(SELECT 1 FROM tj.field_clients c WHERE c.organization_id=o.id)
  ),'[]'::jsonb));
 END IF;
 IF p_organization_id IS NULL OR NOT EXISTS(
  SELECT 1 FROM tj.organization_members m JOIN tj.organizations o ON o.id=m.organization_id
  WHERE m.organization_id=p_organization_id AND m.user_id=actor AND m.status='active'
  AND m.role IN('owner','admin','manager','super_admin') AND o.status='active' AND o.deleted_at IS NULL
 ) THEN RAISE EXCEPTION 'field_report_workspace_access_denied' USING ERRCODE='42501';END IF;
 IF jsonb_typeof(payload)<>'object' OR length(payload::text)>20000 THEN RAISE EXCEPTION 'invalid_payload';END IF;
 IF p_action='snapshot' THEN
  WITH clients AS MATERIALIZED(SELECT * FROM tj.field_clients WHERE organization_id=p_organization_id),
  visits AS MATERIALIZED(SELECT v.* FROM tj.field_visits v JOIN clients c ON c.id=v.client_id),
  findings AS MATERIALIZED(SELECT f.* FROM tj.field_findings f JOIN visits v ON v.id=f.visit_id AND v.client_id=f.client_id AND v.store_id=f.store_id),
  actions AS MATERIALIZED(SELECT a.* FROM tj.field_actions a JOIN findings f ON f.id=a.finding_id AND f.visit_id=a.visit_id AND f.client_id=a.client_id AND f.store_id=a.store_id),
  stores AS MATERIALIZED(SELECT s.*,jsonb_build_object('name',r.name) retailer FROM tj.field_stores s JOIN tj.field_retailers r ON r.id=s.retailer_id WHERE EXISTS(SELECT 1 FROM visits v WHERE v.store_id=s.id)),
  training AS MATERIALIZED(SELECT t.* FROM tj.field_training_sessions t JOIN visits v ON v.id=t.visit_id AND v.client_id=t.client_id AND v.store_id=t.store_id),
  competitive AS MATERIALIZED(SELECT t.* FROM tj.field_competitive_intel t JOIN visits v ON v.id=t.visit_id AND v.store_id=t.store_id),
  scores AS MATERIALIZED(SELECT t.* FROM tj.field_store_scores t JOIN visits v ON v.id=t.visit_id AND v.client_id=t.client_id AND v.store_id=t.store_id),
  history AS MATERIALIZED(SELECT h.* FROM tj.field_action_status_history h JOIN actions a ON a.id=h.action_id)
  SELECT jsonb_build_object(
   'clients',coalesce((SELECT jsonb_agg(to_jsonb(c) ORDER BY c.client_name,c.id) FROM clients c),'[]'),
   'stores',coalesce((SELECT jsonb_agg(to_jsonb(s) ORDER BY s.store_name,s.id) FROM stores s),'[]'),
   'visits',coalesce((SELECT jsonb_agg(to_jsonb(v)||jsonb_build_object('store',to_jsonb(s),'client',jsonb_build_object('client_name',c.client_name)) ORDER BY v.visit_date DESC,v.id) FROM visits v JOIN stores s ON s.id=v.store_id JOIN clients c ON c.id=v.client_id),'[]'),
   'findings',coalesce((SELECT jsonb_agg(to_jsonb(f) ORDER BY f.created_at DESC,f.id) FROM findings f),'[]'),
   'actions',coalesce((SELECT jsonb_agg(to_jsonb(a)||jsonb_build_object('store',to_jsonb(s),'client',jsonb_build_object('client_name',c.client_name),'finding',to_jsonb(f)) ORDER BY a.created_at DESC,a.id) FROM actions a JOIN stores s ON s.id=a.store_id JOIN clients c ON c.id=a.client_id JOIN findings f ON f.id=a.finding_id),'[]'),
   'training',coalesce((SELECT jsonb_agg(to_jsonb(t)||jsonb_build_object('store',to_jsonb(s)) ORDER BY t.created_at DESC,t.id) FROM training t JOIN stores s ON s.id=t.store_id),'[]'),
   'competitive',coalesce((SELECT jsonb_agg(to_jsonb(t)||jsonb_build_object('store',to_jsonb(s)) ORDER BY t.created_at DESC,t.id) FROM competitive t JOIN stores s ON s.id=t.store_id),'[]'),
   'scores',coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.score_date DESC,t.id) FROM scores t),'[]'),
   'history',coalesce((SELECT jsonb_agg(to_jsonb(h) ORDER BY h.created_at,h.id) FROM history h),'[]')
  ) INTO result;
  -- Never silently show a partial report as complete.
  IF EXISTS(SELECT 1 FROM jsonb_each(result) x WHERE jsonb_array_length(x.value)>10000) THEN RAISE EXCEPTION 'Report exceeds the supported size; a paginated report is required';END IF;
  RETURN result;
 END IF;
 IF p_action='export' THEN
  IF payload-ARRAY['client_id','export_type','filters']<>'{}'::jsonb THEN RAISE EXCEPTION 'unsupported_export_field';END IF;
  client:=(payload->>'client_id')::uuid;
  IF NOT EXISTS(SELECT 1 FROM tj.field_clients WHERE id=client AND organization_id=p_organization_id) THEN RAISE EXCEPTION 'export_client_scope_denied' USING ERRCODE='42501';END IF;
  IF nullif(btrim(payload->>'export_type'),'') IS NULL OR length(payload->>'export_type')>100 THEN RAISE EXCEPTION 'invalid_export_type';END IF;
  INSERT INTO tj.field_exports(client_id,export_type,export_format,filters,generated_by_user_id)
  VALUES(client,payload->>'export_type','csv',coalesce(payload->'filters','{}'),actor) RETURNING to_jsonb(field_exports.*) INTO result;
  RETURN result;
 END IF;
 SELECT x.* INTO v_action FROM tj.field_actions x
 JOIN tj.field_clients c ON c.id=x.client_id AND c.organization_id=p_organization_id
 JOIN tj.field_visits v ON v.id=x.visit_id AND v.client_id=x.client_id AND v.store_id=x.store_id
 JOIN tj.field_findings f ON f.id=x.finding_id AND f.visit_id=x.visit_id AND f.client_id=x.client_id AND f.store_id=x.store_id
 WHERE x.id=p_id FOR UPDATE OF x;
 IF v_action.id IS NULL THEN RAISE EXCEPTION 'action_scope_denied' USING ERRCODE='42501';END IF;
 IF p_action='comments' THEN
  SELECT coalesce(jsonb_agg(to_jsonb(c) ORDER BY c.created_at,c.id),'[]') INTO result FROM tj.field_action_comments c
  WHERE c.action_id=v_action.id AND (c.visit_id IS NULL OR c.visit_id=v_action.visit_id) AND (c.finding_id IS NULL OR c.finding_id=v_action.finding_id);
  RETURN result;
 ELSIF p_action='status' THEN
  IF payload-ARRAY['status','expected_status','notes']<>'{}'::jsonb THEN RAISE EXCEPTION 'unsupported_status_field';END IF;
  new_status:=payload->>'status';note:=nullif(btrim(payload->>'notes'),'');
  IF payload->>'expected_status' IS DISTINCT FROM v_action.status THEN RAISE EXCEPTION 'Action changed; reload before updating' USING ERRCODE='40001';END IF;
  IF new_status IS NULL OR new_status NOT IN('new','reviewed','action_required','assigned','service_requested','service_deployed','waiting_retailer','waiting_manufacturer','waiting_parts','replacement_approved','replacement_deployed','follow_up_required','resolved','closed','rejected') THEN RAISE EXCEPTION 'invalid_status';END IF;
  IF new_status=v_action.status THEN RETURN to_jsonb(v_action);END IF;
  IF new_status='closed' AND v_action.status<>'resolved' THEN RAISE EXCEPTION 'Resolve the action before closing it';END IF;
  IF length(note)>10000 THEN RAISE EXCEPTION 'note_too_long';END IF;
  UPDATE tj.field_actions SET status=new_status,updated_at=now(),
   resolved_at=CASE WHEN new_status='resolved' THEN coalesce(resolved_at,now()) ELSE resolved_at END,
   closed_at=CASE WHEN new_status='closed' THEN coalesce(closed_at,now()) ELSE closed_at END
  WHERE id=v_action.id RETURNING to_jsonb(field_actions.*) INTO result;
  INSERT INTO tj.field_action_status_history(action_id,old_status,new_status,changed_by_user_id,changed_by_name,notes)
  VALUES(v_action.id,v_action.status,new_status,actor,actor_name,note);
  RETURN result;
 ELSIF p_action='comment' THEN
  IF payload-ARRAY['comment_text','visibility']<>'{}'::jsonb THEN RAISE EXCEPTION 'unsupported_comment_field';END IF;
  note:=nullif(btrim(payload->>'comment_text'),'');
  IF note IS NULL OR length(note)>10000 OR coalesce(payload->>'visibility','') NOT IN('internal','manufacturer','retailer','service_provider','all') THEN RAISE EXCEPTION 'invalid_comment';END IF;
  INSERT INTO tj.field_action_comments(action_id,visit_id,finding_id,author_user_id,author_name,comment_text,visibility)
  VALUES(v_action.id,v_action.visit_id,v_action.finding_id,actor,actor_name,note,payload->>'visibility') RETURNING to_jsonb(field_action_comments.*) INTO result;
  RETURN result;
 END IF;
 RAISE EXCEPTION 'unsupported_field_report_action';
END $$;
NOTIFY pgrst,'reload schema';
