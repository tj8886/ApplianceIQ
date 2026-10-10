CREATE TABLE tj_private.contact_intake_limits(bucket text PRIMARY KEY,requests int NOT NULL CHECK(requests>=0),expires_at timestamptz NOT NULL);
ALTER TABLE tj_private.contact_intake_limits ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE tj_private.contact_intake_limits FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj_private.submit_contact(p_body jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE name_value text:=btrim(p_body->>'name');email_value text:=lower(btrim(p_body->>'email'));company_value text:=nullif(btrim(p_body->>'company'),'');role_value text:=nullif(btrim(p_body->>'role'),'');message_value text:=nullif(btrim(p_body->>'message'),'');source_value text:=coalesce(nullif(btrim(p_body->>'source'),''),'intelligence-group');submission uuid;day_start timestamptz:=date_trunc('day',now());minute_start timestamptz:=date_trunc('minute',now());bucket_key text;maximum int;
BEGIN
 IF jsonb_typeof(p_body) IS DISTINCT FROM 'object' OR octet_length(p_body::text)>16384 OR EXISTS(SELECT 1 FROM jsonb_each(p_body) v WHERE v.key IN ('name','email','company','role','message','source') AND jsonb_typeof(v.value) NOT IN ('string','null')) THEN RAISE EXCEPTION 'invalid_contact' USING ERRCODE='22023';END IF;
 IF name_value IS NULL OR length(name_value)<1 OR length(name_value)>160 OR email_value IS NULL OR length(email_value)>254 OR email_value !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' OR length(coalesce(company_value,''))>240 OR length(coalesce(role_value,''))>120 OR length(coalesce(message_value,''))>8000 OR length(source_value)>80 THEN RAISE EXCEPTION 'invalid_contact' USING ERRCODE='22023';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('tj_contact_intake',0));
 DELETE FROM tj_private.contact_intake_limits WHERE expires_at<now();
 SELECT id INTO submission FROM tj.contact_submissions WHERE email=email_value AND full_name=name_value AND company IS NOT DISTINCT FROM company_value AND role IS NOT DISTINCT FROM role_value AND message IS NOT DISTINCT FROM message_value AND source=source_value AND created_at>=day_start ORDER BY created_at DESC LIMIT 1;
 IF FOUND THEN RETURN jsonb_build_object('id',submission,'duplicate',true);END IF;
 FOR bucket_key,maximum IN SELECT 'minute:'||minute_start::text,20 UNION ALL SELECT 'day:'||day_start::text,200 UNION ALL SELECT 'email:'||day_start::text||':'||encode(extensions.digest(email_value,'sha256'),'hex'),3 LOOP
  INSERT INTO tj_private.contact_intake_limits(bucket,requests,expires_at) VALUES(bucket_key,0,day_start+interval '2 days') ON CONFLICT DO NOTHING;
  IF (SELECT requests FROM tj_private.contact_intake_limits WHERE bucket=bucket_key)>=maximum THEN RAISE EXCEPTION 'contact_rate_limited' USING ERRCODE='P0001';END IF;
 END LOOP;
 UPDATE tj_private.contact_intake_limits SET requests=requests+1 WHERE bucket IN ('minute:'||minute_start::text,'day:'||day_start::text,'email:'||day_start::text||':'||encode(extensions.digest(email_value,'sha256'),'hex'));
 INSERT INTO tj.contact_submissions(full_name,email,company,role,message,source) VALUES(name_value,email_value,company_value,role_value,message_value,source_value) RETURNING id INTO submission;
 RETURN jsonb_build_object('id',submission,'duplicate',false);
END $$;
REVOKE ALL ON FUNCTION tj_private.submit_contact(jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj_private.submit_contact(jsonb) TO service_role;
CREATE FUNCTION public.aiq_submit_contact(p_body jsonb) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.submit_contact(p_body); $$;
REVOKE ALL ON FUNCTION public.aiq_submit_contact(jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.aiq_submit_contact(jsonb) TO service_role;
NOTIFY pgrst,'reload schema';
