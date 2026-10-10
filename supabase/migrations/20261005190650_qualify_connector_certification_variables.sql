CREATE OR REPLACE FUNCTION tj_private.run_connector_contract_fixtures(p_connector uuid,p_actor uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_connector_key text;f record;run_id uuid:=gen_random_uuid();passed int:=0;failed int:=0;pending int:=0;total int:=0;payload_valid boolean;ok boolean;expect_valid boolean;external_id text;lines jsonb;line_count int;amount numeric;test_error text;actual jsonb;unsupported boolean;
BEGIN
 SELECT key INTO v_connector_key FROM tj.platform_connectors WHERE id=p_connector FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'connector_not_found' USING ERRCODE='P0002';END IF;
 FOR f IN SELECT * FROM tj.platform_connector_test_fixtures WHERE platform_connector_test_fixtures.connector_key=v_connector_key AND active ORDER BY fixture_key LOOP
  total:=total+1;test_error:=NULL;unsupported:=EXISTS(SELECT 1 FROM jsonb_object_keys(f.expected) k WHERE k NOT IN ('should_validate','golden_total','line_count','has_identity','has_lines','positive_total','expected_error'));
  external_id:=coalesce(f.payload->>'id',f.payload->>'orderNumber',f.payload->>'invoiceNumber',f.payload->>'invoice_number',f.payload->>'transactionId',f.payload->>'transaction_id',f.payload->>'name','');
  lines:=coalesce(f.payload->'lines',f.payload->'lineItems',f.payload->'line_items',f.payload->'items','null'::jsonb);line_count:=CASE WHEN jsonb_typeof(lines)='array' THEN jsonb_array_length(lines) ELSE 0 END;
  payload_valid:=external_id<>'' AND line_count>0;
  IF external_id='' THEN test_error:='missing_external_id';ELSIF line_count=0 THEN test_error:='missing_lines';END IF;
  expect_valid:=coalesce((f.expected->>'should_validate')::boolean,true);ok:=payload_valid=expect_valid;
  BEGIN amount:=coalesce(nullif(f.payload->>'total','')::numeric,nullif(f.payload->>'totalAmount','')::numeric,nullif(f.payload->>'total_price','')::numeric,nullif(f.payload->>'transactionTotal','')::numeric);EXCEPTION WHEN invalid_text_representation THEN amount:=NULL;ok:=false;test_error:='invalid_total';END;
  IF f.expected ? 'golden_total' THEN ok:=ok AND amount IS NOT DISTINCT FROM (f.expected->>'golden_total')::numeric;END IF;
  IF f.expected ? 'line_count' THEN ok:=ok AND line_count=(f.expected->>'line_count')::int;END IF;
  IF f.expected ? 'has_identity' THEN ok:=ok AND (external_id<>'')=(f.expected->>'has_identity')::boolean;END IF;
  IF f.expected ? 'has_lines' THEN ok:=ok AND (line_count>0)=(f.expected->>'has_lines')::boolean;END IF;
  IF f.expected ? 'positive_total' THEN ok:=ok AND coalesce(amount>0,false)=(f.expected->>'positive_total')::boolean;END IF;
  IF f.expected ? 'expected_error' THEN ok:=ok AND test_error IS NOT DISTINCT FROM (f.expected->>'expected_error');END IF;
  IF unsupported THEN pending:=pending+1;ELSIF ok THEN passed:=passed+1;ELSE failed:=failed+1;END IF;
  actual:=jsonb_build_object('passed',CASE WHEN unsupported THEN NULL ELSE ok END,'external_identity_present',external_id<>'','line_count',line_count,'actual_total',amount,'scope','fixture_shape_only','destination_project','jdxslqmgjsuzoisuhvlc','actor_id',p_actor,'unsupported_expectations',unsupported);
  INSERT INTO tj.platform_connector_certification_evidence(connector_id,run_id,check_key,fixture_key,status,expected,actual,error,contract_version) VALUES(p_connector,run_id,'fixture_validation',f.fixture_key,CASE WHEN unsupported THEN 'pending' WHEN ok THEN 'passed' ELSE 'failed' END,f.expected,actual,CASE WHEN unsupported THEN 'additional_adapter_validation_required' WHEN NOT ok THEN coalesce(test_error,'expectation_mismatch') ELSE NULL END,coalesce(f.contract_version,'1.0'));
 END LOOP;
 UPDATE tj.platform_connector_certification_checks SET status=CASE WHEN pending>0 OR total=0 THEN 'pending' WHEN failed=0 THEN 'passed' ELSE 'failed' END,evidence=jsonb_build_object('destination_project','jdxslqmgjsuzoisuhvlc','run_id',run_id,'fixtures_total',total,'fixtures_passed',passed,'fixtures_failed',failed,'fixtures_pending',pending,'scope','fixture_shape_only','actor_id',p_actor),last_run_at=now(),updated_at=now() WHERE connector_id=p_connector AND check_key='fixture_validation';
 -- Fixture shape checks cannot certify duplicate handling, security, schema compatibility or live vendor behavior.
 RETURN jsonb_build_object('run_id',run_id,'connector_key',v_connector_key,'total',total,'passed',passed,'failed',failed,'pending',pending,'contract_version','1.0','idempotency_gate',NULL,'security_gate',NULL,'scope','fixture_shape_only','live_acceptance','not_tested');
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
   'certification',(SELECT to_jsonb(cert)-'metadata'-'notes' FROM tj.platform_connector_certifications cert WHERE cert.connector_id=c.id),
   'checks',(SELECT coalesce(jsonb_agg(to_jsonb(cc)-'evidence' ORDER BY category),'[]'::jsonb) FROM tj.platform_connector_certification_checks cc WHERE cc.connector_id=c.id)) ORDER BY c.name),'[]'::jsonb)) INTO result FROM tj.platform_connectors c;RETURN result;
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
