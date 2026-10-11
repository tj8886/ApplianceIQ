BEGIN;
DO $test$
DECLARE p uuid; ids uuid[]; q public.image_audit_queue; invalid_rejected boolean:=false;
BEGIN
 SELECT product_id INTO STRICT p FROM public.image_audit_queue ORDER BY product_id LIMIT 1;
 UPDATE public.image_audit_queue SET status='processing',claimed_at=now()-interval '2 hours',attempts=3,last_error=NULL,finished_at=NULL WHERE product_id=p;
 PERFORM * FROM public.claim_image_audit_batch(20);
 SELECT * INTO q FROM public.image_audit_queue WHERE product_id=p;
 IF q.status<>'error' OR q.attempts<>3 OR q.finished_at IS NULL OR q.last_error IS NULL THEN RAISE EXCEPTION 'exhausted_claim_not_terminal'; END IF;
 UPDATE public.image_audit_queue SET status='pending',attempts=0,claimed_at=NULL,finished_at=NULL,last_error=NULL WHERE product_id=p;
 SELECT array_agg(x) INTO ids FROM public.claim_image_audit_batch(1) x;
 IF cardinality(ids)<>1 THEN RAISE EXCEPTION 'batch_not_bounded'; END IF;
 SELECT * INTO q FROM public.image_audit_queue WHERE product_id=ids[1];
 IF q.attempts<>1 OR q.status<>'processing' THEN RAISE EXCEPTION 'claim_not_recorded'; END IF;
 BEGIN PERFORM * FROM public.claim_image_audit_batch(21); EXCEPTION WHEN raise_exception THEN invalid_rejected:=true; END;
 IF NOT invalid_rejected THEN RAISE EXCEPTION 'invalid_batch_accepted'; END IF;
 IF has_function_privilege('anon','public.claim_image_audit_batch(integer)','EXECUTE') OR has_function_privilege('authenticated','public.claim_image_audit_batch(integer)','EXECUTE') THEN RAISE EXCEPTION 'queue_exposed'; END IF;
END $test$;
ROLLBACK;
