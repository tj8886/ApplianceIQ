-- Workflow applies to native draft packages; archived records and files are retained.
CREATE FUNCTION tj_private.speciq_workflow(p_body jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE native uuid:=auth.uid(); actor uuid; org uuid; role_name text; manager boolean; a text; req uuid;
 pkg tj.speciq_packages%ROWTYPE; replay tj_private.speciq_draft_requests%ROWTYPE;
 decision text; comments text; conditions text; before_state jsonb; history_id uuid;
BEGIN
 actor:=tj_private.microsoft_actor(native);
 IF native IS NULL OR actor IS NULL THEN RETURN jsonb_build_object('ok',false,'error','identity_review_required'); END IF;
 IF NOT EXISTS(SELECT 1 FROM auth.users WHERE id=native AND email_confirmed_at IS NOT NULL) THEN RETURN jsonb_build_object('ok',false,'error','email_confirmation_required'); END IF;
 IF p_body IS NULL OR jsonb_typeof(p_body)<>'object' OR octet_length(p_body::text)>16384 THEN RETURN jsonb_build_object('ok',false,'error','invalid_request'); END IF;
 a:=p_body->>'action';org:=(p_body->>'organization_id')::uuid;role_name:=tj_private.speciq_actor_role(org);
 IF role_name IS NULL THEN RETURN jsonb_build_object('ok',false,'error','organization_access_required'); END IF;
 manager:=role_name IN('owner','admin','manager');
 IF a='list' THEN
 RETURN jsonb_build_object('ok',true,'packages',coalesce((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.created_at DESC) FROM
 (SELECT k.*,to_jsonb(p) AS speciq_projects FROM tj.speciq_packages k JOIN tj.speciq_projects p ON p.id=k.project_id AND p.organization_id=org
 WHERE k.organization_id=org AND k.deleted_at IS NULL AND k.superseded_by IS NULL AND k.status<>'archived'
 AND (manager OR k.created_by=actor) AND EXISTS(SELECT 1 FROM tj_private.speciq_draft_requests d WHERE d.package_id=k.id)
 ORDER BY k.created_at DESC,k.id LIMIT 200) r),'[]'::jsonb)); END IF;
 IF a IS NULL OR a NOT IN('get','submit','decide','archive') THEN RETURN jsonb_build_object('ok',false,'error','invalid_request'); END IF;
 IF a<>'get' THEN
 req:=(p_body->>'request_id')::uuid;
 IF req IS NULL THEN RETURN jsonb_build_object('ok',false,'error','invalid_request'); END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(org::text||native::text||req::text,0));
 END IF;
 SELECT * INTO pkg FROM tj.speciq_packages WHERE id=(p_body->>'package_id')::uuid AND organization_id=org FOR UPDATE;
 IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM tj_private.speciq_draft_requests d WHERE d.package_id=pkg.id)
 OR (pkg.created_by IS DISTINCT FROM actor AND NOT manager) THEN RETURN jsonb_build_object('ok',false,'error','package_unavailable'); END IF;
 IF a='get' THEN
 RETURN jsonb_build_object('ok',true,'package',to_jsonb(pkg),'snapshot',(SELECT snapshot FROM tj.speciq_package_versions WHERE package_id=pkg.id ORDER BY version_number DESC,created_at DESC LIMIT 1),
 'history',coalesce((SELECT jsonb_agg(to_jsonb(h) ORDER BY h.created_at,h.id) FROM tj.speciq_approval_history h WHERE h.package_id=pkg.id AND h.organization_id=org),'[]'::jsonb),
 'can_decide',manager AND actor IS DISTINCT FROM pkg.created_by AND actor IS DISTINCT FROM pkg.submitted_by,
 'can_submit',role_name<>'viewer' AND pkg.status='draft' AND NOT coalesce(pkg.locked,false),'can_archive',role_name<>'viewer'); END IF;
 IF role_name NOT IN('owner','admin','manager','member') THEN RETURN jsonb_build_object('ok',false,'error','forbidden'); END IF;
 IF a='decide' AND (NOT manager OR actor IS NOT DISTINCT FROM pkg.created_by OR actor IS NOT DISTINCT FROM pkg.submitted_by) THEN RETURN jsonb_build_object('ok',false,'error','independent_manager_required'); END IF;
 IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_body) k WHERE k NOT IN('action','organization_id','package_id','request_id','expected_version','expected_updated_at','decision','comments','conditions')) THEN RETURN jsonb_build_object('ok',false,'error','invalid_request'); END IF;
 req:=(p_body->>'request_id')::uuid;
 IF req IS NULL THEN RETURN jsonb_build_object('ok',false,'error','invalid_request'); END IF;
 SELECT * INTO replay FROM tj_private.speciq_draft_requests WHERE organization_id=org AND native_actor=native AND request_id=req;
 IF FOUND THEN
 IF replay.body<>p_body OR replay.package_id<>pkg.id THEN RETURN jsonb_build_object('ok',false,'error','request_conflict'); END IF;
 RETURN jsonb_build_object('ok',true,'package_id',pkg.id,'replayed',true); END IF;
 IF pkg.deleted_at IS NOT NULL OR pkg.superseded_by IS NOT NULL OR pkg.status='archived' OR pkg.sent_at IS NOT NULL OR pkg.shopify_pushed_at IS NOT NULL OR pkg.share_token IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'error','package_not_editable'); END IF;
 IF (p_body->>'expected_version')::integer IS DISTINCT FROM pkg.version OR (p_body->>'expected_updated_at')::timestamptz IS DISTINCT FROM pkg.updated_at THEN RETURN jsonb_build_object('ok',false,'error','revision_conflict'); END IF;
 comments:=nullif(btrim(p_body->>'comments'),'');conditions:=nullif(btrim(p_body->>'conditions'),'');decision:=p_body->>'decision';
 IF length(coalesce(comments,''))>2000 OR length(coalesce(conditions,''))>2000 THEN RETURN jsonb_build_object('ok',false,'error','invalid_request'); END IF;
 before_state:=jsonb_build_object('status',pkg.status,'approval_status',pkg.approval_status,'locked',pkg.locked);
 IF a='submit' THEN
 IF pkg.status<>'draft' OR coalesce(pkg.locked,false) OR coalesce(pkg.approval_status,'unknown') NOT IN('not_required','returned') OR NOT EXISTS(SELECT 1 FROM tj.speciq_package_versions v WHERE v.package_id=pkg.id AND v.version_number=pkg.version) THEN RETURN jsonb_build_object('ok',false,'error','invalid_transition'); END IF;
 UPDATE tj.speciq_packages SET status='ready_for_review',approval_status='pending',approval_required=true,submitted_by=actor,submitted_at=clock_timestamp(),updated_by=actor,updated_at=clock_timestamp(),manager_comments=NULL,approval_conditions=NULL,reviewed_by=NULL,reviewed_at=NULL,approved_at=NULL,approved_by=NULL WHERE id=pkg.id;
 INSERT INTO tj.speciq_approval_history(package_id,organization_id,submission_id,quote_version,submitted_by,approval_trigger,requested_discount,requested_validity_days)
 VALUES(pkg.id,org,req::text,pkg.version,actor,'native_draft_review',NULL,NULL);
 ELSIF a='decide' THEN
 IF pkg.status<>'ready_for_review' OR pkg.approval_status IS DISTINCT FROM 'pending' THEN RETURN jsonb_build_object('ok',false,'error','invalid_transition'); END IF;
 IF decision IS NULL OR decision NOT IN('approved','approved_with_conditions','returned','rejected') OR (decision IN('returned','rejected') AND comments IS NULL) OR (decision='approved_with_conditions' AND conditions IS NULL) THEN RETURN jsonb_build_object('ok',false,'error','invalid_request'); END IF;
 SELECT id INTO history_id FROM tj.speciq_approval_history WHERE package_id=pkg.id AND organization_id=org AND manager_decision IS NULL AND quote_version=pkg.version ORDER BY created_at DESC,id DESC LIMIT 1 FOR UPDATE;
 IF history_id IS NULL THEN RETURN jsonb_build_object('ok',false,'error','invalid_transition'); END IF;
 UPDATE tj.speciq_packages SET approval_status=decision,status=CASE WHEN decision='returned' THEN 'draft' ELSE 'in_progress' END,locked=decision<>'returned',
 reviewed_by=actor,reviewed_at=clock_timestamp(),manager_comments=comments,approval_conditions=conditions,
 approved_by=CASE WHEN decision IN('approved','approved_with_conditions') THEN actor ELSE NULL END,approved_at=CASE WHEN decision IN('approved','approved_with_conditions') THEN clock_timestamp() ELSE NULL END,
 returned_to_rep_at=CASE WHEN decision='returned' THEN clock_timestamp() ELSE NULL END,rejection_reason=CASE WHEN decision='rejected' THEN comments ELSE NULL END,updated_by=actor,updated_at=clock_timestamp() WHERE id=pkg.id;
 UPDATE tj.speciq_approval_history SET manager_decision=decision,assigned_manager=actor,conditions=speciq_workflow.conditions,comments=speciq_workflow.comments,decision_at=clock_timestamp(),returned_to_rep_at=CASE WHEN decision='returned' THEN clock_timestamp() ELSE NULL END WHERE id=history_id;
 ELSE
 IF pkg.status NOT IN('draft','in_progress','ready_for_review') OR (coalesce(pkg.locked,false) AND NOT manager) THEN RETURN jsonb_build_object('ok',false,'error','forbidden'); END IF;
 UPDATE tj.speciq_packages SET status='archived',locked=true,approval_status=CASE WHEN approval_status='pending' THEN 'withdrawn' ELSE approval_status END,updated_by=actor,updated_at=clock_timestamp() WHERE id=pkg.id;
 UPDATE tj.speciq_approval_history SET manager_decision='withdrawn',comments=coalesce(speciq_workflow.comments,'Package archived'),decision_at=clock_timestamp(),assigned_manager=actor WHERE package_id=pkg.id AND organization_id=org AND manager_decision IS NULL;
 END IF;
 INSERT INTO tj.speciq_package_events(package_id,event_type,event_data) VALUES(pkg.id,CASE WHEN a='decide' AND decision='returned' THEN 'revision_requested' ELSE 'created' END,jsonb_build_object('workflow_action',a,'decision',decision,'source_actor',actor,'request_id',req,'before',before_state,'after',(SELECT jsonb_build_object('status',k.status,'approval_status',k.approval_status,'locked',k.locked) FROM tj.speciq_packages k WHERE k.id=pkg.id),'scope','draft_content_review; final tax and sending pending'));
 INSERT INTO tj_private.speciq_draft_requests(organization_id,native_actor,request_id,body,package_id) VALUES(org,native,req,p_body,pkg.id);
 RETURN jsonb_build_object('ok',true,'package_id',pkg.id,'replayed',false);
EXCEPTION WHEN invalid_text_representation OR invalid_parameter_value OR check_violation OR not_null_violation OR foreign_key_violation OR numeric_value_out_of_range OR datetime_field_overflow THEN RETURN jsonb_build_object('ok',false,'error','invalid_request');
END;
$$;
CREATE FUNCTION public.tj_runtime_speciq_workflow(p_body jsonb)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.speciq_workflow(p_body); $$;
REVOKE ALL ON FUNCTION tj_private.speciq_workflow(jsonb),public.tj_runtime_speciq_workflow(jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.speciq_workflow(jsonb),public.tj_runtime_speciq_workflow(jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';
