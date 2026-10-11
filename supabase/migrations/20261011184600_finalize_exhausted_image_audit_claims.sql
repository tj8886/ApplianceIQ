-- Keep the existing three-attempt audit budget; expose exhausted claims as failures.
CREATE OR REPLACE FUNCTION public.claim_image_audit_batch(n integer DEFAULT 8)
RETURNS SETOF uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF n IS NULL OR n NOT BETWEEN 1 AND 20 THEN RAISE EXCEPTION 'invalid_image_audit_batch_size'; END IF;
 WITH exhausted AS (
  SELECT q.product_id FROM public.image_audit_queue q
  WHERE q.status='processing' AND q.claimed_at<now()-interval '1 hour' AND q.attempts>=3
  ORDER BY q.claimed_at,q.product_id LIMIT n FOR UPDATE SKIP LOCKED
 )
 UPDATE public.image_audit_queue q SET status='error',finished_at=clock_timestamp(),
 last_error=coalesce(nullif(q.last_error,''),'Stale image audit claim exhausted its existing three-attempt retry budget; source assets retained.')
 FROM exhausted e WHERE q.product_id=e.product_id;
 RETURN QUERY
 WITH ready AS (
  SELECT q.product_id FROM public.image_audit_queue q
  WHERE q.attempts<3 AND (q.status='pending' OR (q.status='processing' AND q.claimed_at<now()-interval '3 minutes'))
  ORDER BY q.attempts,q.claimed_at NULLS FIRST,q.product_id LIMIT n FOR UPDATE SKIP LOCKED
 )
 UPDATE public.image_audit_queue q SET status='processing',claimed_at=now(),attempts=q.attempts+1
 FROM ready r WHERE q.product_id=r.product_id RETURNING q.product_id;
END $$;
REVOKE ALL ON FUNCTION public.claim_image_audit_batch(integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.claim_image_audit_batch(integer) TO service_role;
