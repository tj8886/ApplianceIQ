-- Preserve effective defaults from the source request processor and team coach.
-- These model IDs are public configuration, not provider credentials.
-- Native environment variables remain overrideable; handlers contain no model defaults.
DO $$DECLARE n text;v text;sid uuid;BEGIN
 FOR n,v IN SELECT * FROM (VALUES
  ('AI_MODEL_LIGHT','claude-haiku-4-5'),
  ('AI_MODEL_STANDARD','claude-sonnet-4-6'),
  ('AI_REQUEST_MODEL_HEAVY','claude-opus-4-8'),
  ('AI_TEAM_MODEL_STRONG','claude-sonnet-4-6')
 ) defaults(name,value) LOOP
  IF NOT EXISTS(SELECT 1 FROM tj_private.runtime_environment_manifest WHERE name=n) THEN
   sid:=vault.create_secret(v,'aiq_migrated_runtime_'||n,'Source effective runtime default moved to tier configuration');
   INSERT INTO tj_private.runtime_environment_manifest(name,secret_id,value_sha256) VALUES(n,sid,encode(sha256(convert_to(v,'UTF8')),'hex'));
  END IF;
 END LOOP;
END $$;
