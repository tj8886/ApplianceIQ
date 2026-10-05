CREATE OR REPLACE FUNCTION tj_private.evaluate_connector_certification(p_connector uuid,p_actor uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE total numeric;earned numeric;blockers int;score numeric;life text;run_id uuid;live_ok boolean;security_ok boolean;required_score numeric;
BEGIN
 SELECT live_acceptance_passed,platform_security_passed,c.required_score INTO live_ok,security_ok,required_score FROM tj.platform_connector_certifications c WHERE connector_id=p_connector FOR UPDATE;
 IF NOT FOUND THEN INSERT INTO tj.platform_connector_certifications(connector_id) VALUES(p_connector);live_ok:=false;security_ok:=false;required_score:=85;END IF;
 SELECT coalesce(sum(weight),0),coalesce(sum(weight) FILTER(WHERE status='passed' AND evidence->>'destination_project'='jdxslqmgjsuzoisuhvlc'),0),count(*) FILTER(WHERE required AND NOT(status IN ('passed','not_applicable') AND evidence->>'destination_project'='jdxslqmgjsuzoisuhvlc')) INTO total,earned,blockers FROM tj.platform_connector_certification_checks WHERE connector_id=p_connector;
 -- A NULL evidence marker must block required checks as well.
 SELECT count(*) INTO blockers FROM tj.platform_connector_certification_checks WHERE connector_id=p_connector AND required AND (status NOT IN ('passed','not_applicable') OR evidence->>'destination_project' IS DISTINCT FROM 'jdxslqmgjsuzoisuhvlc');
 SELECT EXISTS(SELECT 1 FROM tj.platform_connector_certification_checks WHERE connector_id=p_connector AND check_key='live_acceptance' AND status='passed' AND evidence->>'destination_project'='jdxslqmgjsuzoisuhvlc'),EXISTS(SELECT 1 FROM tj.platform_connector_certification_checks WHERE connector_id=p_connector AND check_key='security' AND status='passed' AND evidence->>'destination_project'='jdxslqmgjsuzoisuhvlc') INTO live_ok,security_ok;
 score:=CASE WHEN total>0 THEN round(100*earned/total,2) ELSE 0 END;
 life:=CASE WHEN total>0 AND score>=coalesce(required_score,85) AND blockers=0 AND live_ok IS TRUE AND security_ok IS TRUE THEN 'certified' WHEN score>=55 THEN 'beta' ELSE 'development' END;
 INSERT INTO tj.platform_connector_certification_runs(connector_id,status,completed_at,score,triggered_by,results) VALUES(p_connector,CASE WHEN life='certified' THEN 'passed' ELSE 'partial' END,now(),score,p_actor,jsonb_build_object('required_failures',blockers,'destination_project','jdxslqmgjsuzoisuhvlc','live_acceptance_passed',live_ok,'platform_security_passed',security_ok)) RETURNING id INTO run_id;
 UPDATE tj.platform_connector_certifications SET certification_score=score,lifecycle_status=life,live_acceptance_passed=live_ok,platform_security_passed=security_ok,metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('destination_project','jdxslqmgjsuzoisuhvlc'),last_evaluated_at=now(),updated_at=now(),certified_at=CASE WHEN life='certified' THEN now() ELSE NULL END,certified_by=CASE WHEN life='certified' THEN p_actor ELSE NULL END WHERE connector_id=p_connector;
 RETURN jsonb_build_object('connector_id',p_connector,'score',score,'required_failures',blockers,'lifecycle_status',life,'run_id',run_id,'live_acceptance_passed',live_ok,'platform_security_passed',security_ok);
END $$;
CREATE OR REPLACE FUNCTION tj_private.connector_certification(p_body jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=tj_private.current_source_user_id();org uuid;member_role text;action text:=coalesce(p_body->>'action','summary');cid uuid;result jsonb;ev jsonb;v_status text;limit_n int;
BEGIN
 IF actor IS NULL THEN RAISE EXCEPTION 'access_denied' USING ERRCODE='42501';END IF;
 IF jsonb_typeof(p_body) IS DISTINCT FROM 'object' OR octet_length(p_body::text)>16384 THEN RAISE EXCEPTION 'invalid_body' USING ERRCODE='22023';END IF;
 org:=nullif(p_body->>'organization_id','')::uuid;
 SELECT m.role INTO member_role FROM tj.organization_members m JOIN tj.organizations o ON o.id=m.organization_id WHERE m.organization_id=org AND m.user_id=actor AND m.status='active' AND o.status='active' AND o.deleted_at IS NULL;
 IF member_role IS NULL OR member_role NOT IN ('owner','admin','super_admin','manager') THEN RAISE EXCEPTION 'access_denied' USING ERRCODE='42501';END IF;
 IF action='summary' THEN
  SELECT jsonb_build_object('ok',true,'connectors',coalesce(jsonb_agg(jsonb_build_object('id',c.id,'key',c.key,'name',c.name,'status',c.status,
   'certification',(SELECT (to_jsonb(cert)-'metadata'-'notes')||CASE WHEN cert.metadata->>'destination_project'='jdxslqmgjsuzoisuhvlc' THEN '{}'::jsonb ELSE jsonb_build_object('lifecycle_status','development','certification_score',NULL,'live_acceptance_passed',false,'platform_security_passed',false,'provenance','source_history_requires_destination_review') END FROM tj.platform_connector_certifications cert WHERE cert.connector_id=c.id),
   'checks',(SELECT coalesce(jsonb_agg((to_jsonb(cc)-'evidence')||CASE WHEN cc.evidence->>'destination_project'='jdxslqmgjsuzoisuhvlc' THEN '{}'::jsonb ELSE jsonb_build_object('status','pending','provenance','source_history_requires_destination_review') END ORDER BY category),'[]'::jsonb) FROM tj.platform_connector_certification_checks cc WHERE cc.connector_id=c.id)) ORDER BY c.name),'[]'::jsonb)) INTO result FROM tj.platform_connectors c;RETURN result;
 END IF;
 cid:=nullif(p_body->>'connector_id','')::uuid;IF cid IS NULL OR NOT EXISTS(SELECT 1 FROM tj.platform_connectors WHERE id=cid) THEN RAISE EXCEPTION 'connector_not_found' USING ERRCODE='P0002';END IF;
 IF action='evidence' THEN
  limit_n:=coalesce((p_body->>'limit')::int,100);IF limit_n<1 OR limit_n>250 THEN RAISE EXCEPTION 'invalid_limit' USING ERRCODE='22023';END IF;
 ELSE
  IF NOT tj_private.is_platform_admin() THEN RAISE EXCEPTION 'platform_admin_required_for_global_certification' USING ERRCODE='42501';END IF;
  PERFORM 1 FROM tj.platform_connectors WHERE id=cid FOR UPDATE;
  IF action='run_automation' THEN result:=tj_private.run_connector_contract_fixtures(cid,actor);PERFORM tj_private.evaluate_connector_certification(cid,actor);
  ELSIF action='evaluate' THEN result:=tj_private.evaluate_connector_certification(cid,actor);
  ELSIF action='set_check' THEN
   v_status:=p_body->>'status';ev:=coalesce(p_body->'evidence','{}'::jsonb);
   IF v_status IS NULL OR v_status NOT IN ('passed','failed','warning','pending','not_applicable') OR jsonb_typeof(ev)<>'object' OR octet_length(ev::text)>8192 OR (v_status IN ('passed','not_applicable') AND length(coalesce(ev->>'review_note',''))<10) THEN RAISE EXCEPTION 'review_evidence_required' USING ERRCODE='22023';END IF;
   UPDATE tj.platform_connector_certification_checks SET status=v_status,evidence=ev||jsonb_build_object('destination_project','jdxslqmgjsuzoisuhvlc','reviewed_by',actor,'reviewed_at',now(),'organization_id',org),last_run_at=now(),updated_at=now() WHERE connector_id=cid AND check_key=p_body->>'check_key';
   IF NOT FOUND THEN RAISE EXCEPTION 'check_not_found' USING ERRCODE='P0002';END IF;
   PERFORM tj_private.evaluate_connector_certification(cid,actor);RETURN jsonb_build_object('ok',true);
  ELSE RAISE EXCEPTION 'unknown_action' USING ERRCODE='22023';END IF;
  limit_n:=100;
 END IF;
 SELECT coalesce(jsonb_agg(e),'[]'::jsonb) INTO ev FROM (SELECT id,connector_id,run_id,check_key,fixture_key,status,contract_version,created_at FROM tj.platform_connector_certification_evidence WHERE connector_id=cid ORDER BY created_at DESC LIMIT limit_n) e;
 RETURN jsonb_build_object('ok',true,'result',result,'evidence',ev);
END $$;
