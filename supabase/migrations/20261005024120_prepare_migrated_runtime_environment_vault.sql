CREATE TABLE tj_private.runtime_environment_manifest (
 name text PRIMARY KEY,secret_id uuid UNIQUE NOT NULL REFERENCES vault.secrets(id),value_sha256 text NOT NULL,transferred_at timestamptz NOT NULL DEFAULT now());
ALTER TABLE tj_private.runtime_environment_manifest ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj_private.runtime_environment_manifest FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj_private.ingest_migrated_runtime_environment(p_values jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE n text;v text;sid uuid;hash text;out_values jsonb:='{}';BEGIN
 IF current_user='authenticated' OR current_setting('role',true) IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'Service role required' USING ERRCODE='42501';END IF;
 IF jsonb_typeof(p_values) IS DISTINCT FROM 'object' OR octet_length(p_values::text)>200000 THEN RAISE EXCEPTION 'Invalid environment payload' USING ERRCODE='22023';END IF;
 FOR n,v IN SELECT key,value FROM jsonb_each_text(p_values) LOOP
  IF NOT(n=ANY(ARRAY['AICRM_AI_RESEARCH_PROMPT_VERSION','AICRM_ENRICHMENT_ORG_LIMIT_PER_HOUR','AICRM_ENRICHMENT_USER_LIMIT_PER_HOUR','AI_MODEL','AI_MODEL_FAST','AI_MODEL_HEAVY','AI_MODEL_LIGHT','AI_MODEL_STANDARD','ANTHROPIC_API_KEY','ANTHROPIC_INPUT_COST_PER_MILLION_TOKENS','ANTHROPIC_MAX_TOKENS','ANTHROPIC_MODEL','ANTHROPIC_OUTPUT_COST_PER_MILLION_TOKENS','ANTHROPIC_RETRY_COUNT','ANTHROPIC_TIMEOUT_MS','CRON_SECRET','EMAIL_FROM','EMBEDDING_MODEL','GOOGLE_API_KEY','INVITE_FROM_EMAIL','MICROSOFT_CLIENT_ID','MICROSOFT_CLIENT_SECRET','MICROSOFT_REDIRECT_URI','OPENAI_API_KEY','RESEND_API_KEY','RESEND_FROM_EMAIL','RESEND_WEBHOOK_SECRET','SCRAPER_PROXY_KEY','SHOPIFY_API_KEY','SHOPIFY_API_SECRET','SHOPIFY_APP_URL','STRIPE_SECRET_KEY','STRIPE_WEBHOOK_SECRET','TURNSTILE_RATE_LIMIT_MAX_FAILURES','TURNSTILE_RATE_LIMIT_WINDOW_MINUTES','TURNSTILE_SECRET_KEY','VITE_WEB_PUSH_PUBLIC_KEY','VOYAGE_API_KEY','WEB_PUSH_PRIVATE_KEY','WEB_PUSH_PUBLIC_KEY','WEB_PUSH_VAPID_SUBJECT'])) OR v IS NULL OR v='' OR length(v)>10000 THEN RAISE EXCEPTION 'Unsupported runtime configuration' USING ERRCODE='22023';END IF;
  hash:=encode(sha256(convert_to(v,'UTF8')),'hex');
  SELECT secret_id INTO sid FROM tj_private.runtime_environment_manifest WHERE name=n;
  IF sid IS NULL THEN
   sid:=vault.create_secret(v,'aiq_migrated_runtime_'||n,'Migrated runtime setting; service access only');
   INSERT INTO tj_private.runtime_environment_manifest(name,secret_id,value_sha256) VALUES(n,sid,hash);
  ELSE
   IF NOT EXISTS(SELECT 1 FROM tj_private.runtime_environment_manifest WHERE name=n AND value_sha256=hash) THEN RAISE EXCEPTION 'Existing migrated value differs; explicit refresh required' USING ERRCODE='22023';END IF;
  END IF;
  out_values:=out_values||jsonb_build_object(n,hash);
 END LOOP;
 RETURN out_values;
END $$;
CREATE FUNCTION tj_private.migrated_runtime_environment() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT coalesce(jsonb_object_agg(m.name,s.decrypted_secret),'{}') FROM tj_private.runtime_environment_manifest m JOIN vault.decrypted_secrets s ON s.id=m.secret_id WHERE current_setting('role',true)='service_role';
$$;
REVOKE ALL ON FUNCTION tj_private.ingest_migrated_runtime_environment(jsonb),tj_private.migrated_runtime_environment() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.ingest_migrated_runtime_environment(jsonb),tj_private.migrated_runtime_environment() TO service_role;
CREATE FUNCTION public.aiq_ingest_migrated_runtime_environment(p_values jsonb) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$SELECT tj_private.ingest_migrated_runtime_environment(p_values);$$;
CREATE FUNCTION public.aiq_migrated_runtime_environment() RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$SELECT tj_private.migrated_runtime_environment();$$;
REVOKE ALL ON FUNCTION public.aiq_ingest_migrated_runtime_environment(jsonb),public.aiq_migrated_runtime_environment() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.aiq_ingest_migrated_runtime_environment(jsonb),public.aiq_migrated_runtime_environment() TO service_role;
NOTIFY pgrst,'reload schema';
