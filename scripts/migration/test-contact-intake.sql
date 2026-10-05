BEGIN;SET LOCAL statement_timeout='30s';
SET LOCAL ROLE service_role;
DO $$DECLARE a jsonb;b jsonb;payload jsonb:=jsonb_build_object('name','Rollback contact','email','rollback-'||gen_random_uuid()||'@example.invalid','message','Synthetic; never emailed');blocked boolean:=false;BEGIN
 a:=public.aiq_submit_contact(payload);b:=public.aiq_submit_contact(payload);IF a->>'id'<>b->>'id' OR NOT (b->>'duplicate')::boolean THEN RAISE EXCEPTION 'Duplicate intake not idempotent';END IF;
 PERFORM set_config('test.contact',a->>'id',true);
 BEGIN PERFORM public.aiq_submit_contact('{"name":true,"email":"invalid"}');RAISE EXCEPTION 'Invalid details accepted';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 PERFORM public.aiq_submit_contact(payload||'{"message":"Synthetic variation 2"}');PERFORM public.aiq_submit_contact(payload||'{"message":"Synthetic variation 3"}');
 BEGIN PERFORM public.aiq_submit_contact(payload||'{"message":"Synthetic variation 4"}');EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'contact_rate_limited' THEN RAISE;END IF;blocked:=true;END;
 IF NOT blocked THEN RAISE EXCEPTION 'Email cap not enforced';END IF;
END $$;
RESET ROLE;
DO $$BEGIN
 IF NOT EXISTS(SELECT 1 FROM tj.contact_submissions WHERE id=current_setting('test.contact')::uuid AND status='new') THEN RAISE EXCEPTION 'Intake row missing';END IF;
 IF has_function_privilege('anon','public.aiq_submit_contact(jsonb)','EXECUTE') OR has_function_privilege('authenticated','public.aiq_submit_contact(jsonb)','EXECUTE') OR has_table_privilege('service_role','tj_private.contact_intake_limits','SELECT') THEN RAISE EXCEPTION 'Intake privilege leak';END IF;
END $$;
ROLLBACK;
