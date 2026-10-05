BEGIN; SET LOCAL statement_timeout='45s';
DO $$ DECLARE u uuid;src uuid;org uuid;cid uuid;key text:='rollback-cert-'||gen_random_uuid();BEGIN
 SELECT im.target_user_id,im.source_user_id,m.organization_id INTO u,src,org FROM tj.source_user_identity_map im JOIN tj.organization_members m ON m.user_id=im.source_user_id JOIN tj.organizations o ON o.id=m.organization_id WHERE im.activation_status='activated' AND m.status='active' AND m.role IN ('owner','admin') AND o.status='active' AND o.deleted_at IS NULL LIMIT 1;
 IF u IS NULL THEN RAISE EXCEPTION 'Fixture unavailable';END IF;
 DELETE FROM tj.platform_admins WHERE user_id=src;
 INSERT INTO tj.platform_connectors(key,name,vendor_name) VALUES(key,'Rollback certification','Synthetic') RETURNING id INTO cid;
 INSERT INTO tj.platform_connector_certification_checks(connector_id,check_key,check_name,category,required,weight,status,evidence) VALUES(cid,'fixture_validation','Fixture validation','contract',true,100,'passed','{}'),(cid,'security','Security acceptance','security',true,0,'passed','{}');
 INSERT INTO tj.platform_connector_test_fixtures(connector_key,fixture_key,external_entity_type,payload,expected,active) VALUES(key,'valid','transaction','{"id":"synthetic","lines":[{"id":"line"}],"total":12}','{"should_validate":true,"golden_total":12,"line_count":1}',true),(key,'invalid','transaction','{"lines":[]}','{"should_validate":false,"expected_error":"missing_external_id"}',true),(key,'unsupported','transaction','{"id":"synthetic","lines":[{}]}','{"mapping_expected":true}',true);
 PERFORM set_config('request.jwt.claim.sub',u::text,true);PERFORM set_config('test.source',src::text,true);PERFORM set_config('test.org',org::text,true);PERFORM set_config('test.connector',cid::text,true);
END $$;
SET LOCAL ROLE authenticated;
DO $$ DECLARE b jsonb:=jsonb_build_object('organization_id',current_setting('test.org'),'connector_id',current_setting('test.connector'));r jsonb;BEGIN
 r:=public.tj_connector_certification(b);IF NOT (r->>'ok')::boolean THEN RAISE EXCEPTION 'Summary unavailable';END IF;
 BEGIN PERFORM public.tj_connector_certification(b||'{"action":"run_automation"}');RAISE EXCEPTION 'Tenant admin changed global certification';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN PERFORM public.tj_connector_certification(b||jsonb_build_object('organization_id',gen_random_uuid()));RAISE EXCEPTION 'Foreign organization accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END $$;
RESET ROLE;
INSERT INTO tj.platform_admins(user_id,email) VALUES(current_setting('test.source')::uuid,'rollback-certification@example.invalid');
SET LOCAL ROLE authenticated;
DO $$ DECLARE b jsonb:=jsonb_build_object('organization_id',current_setting('test.org'),'connector_id',current_setting('test.connector'));r jsonb;BEGIN
 r:=public.tj_connector_certification(b||'{"action":"evaluate"}');IF r#>>'{result,lifecycle_status}'='certified' OR (r#>>'{result,required_failures}')::int<>2 THEN RAISE EXCEPTION 'Historical unmarked checks certified';END IF;
 r:=public.tj_connector_certification(b||'{"action":"run_automation"}');IF (r#>>'{result,passed}')::int<>2 OR (r#>>'{result,pending}')::int<>1 THEN RAISE EXCEPTION 'Fixture assertions or unsupported handling failed';END IF;
 IF r#>'{result,security_gate}'<>'null'::jsonb THEN RAISE EXCEPTION 'Unsupported security gate claimed';END IF;
 BEGIN PERFORM public.tj_connector_certification(b||'{"action":"set_check","check_key":"security","status":"passed"}');RAISE EXCEPTION 'Unreviewed check approved';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 r:=public.tj_connector_certification(b||'{"action":"set_check","check_key":"security","status":"passed","evidence":{"review_note":"Synthetic approval for rollback fixture only"}}');
 r:=public.tj_connector_certification(b||'{"action":"evidence"}');IF r::text LIKE '%actual_total%' OR r::text LIKE '%golden_total%' THEN RAISE EXCEPTION 'Raw evidence payload exposed';END IF;
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 BEGIN PERFORM public.tj_connector_certification(b);RAISE EXCEPTION 'Unmapped access accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END $$;
RESET ROLE;
DO $$BEGIN
 IF EXISTS(SELECT 1 FROM tj.platform_connector_certifications WHERE connector_id=current_setting('test.connector')::uuid AND lifecycle_status='certified') THEN RAISE EXCEPTION 'Incomplete live acceptance certified';END IF;
 IF NOT EXISTS(SELECT 1 FROM tj.platform_connector_certification_checks WHERE connector_id=current_setting('test.connector')::uuid AND check_key='security' AND evidence->>'reviewed_by'=current_setting('test.source')) THEN RAISE EXCEPTION 'Review actor incorrect';END IF;
 IF has_function_privilege('anon','public.tj_connector_certification(jsonb)','EXECUTE') OR has_function_privilege('service_role','public.tj_connector_certification(jsonb)','EXECUTE') THEN RAISE EXCEPTION 'Unauthenticated grant';END IF;
END $$;
ROLLBACK;
