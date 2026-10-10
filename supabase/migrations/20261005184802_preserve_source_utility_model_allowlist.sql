DO $$DECLARE sid uuid;v text:='["claude-sonnet-4-6","claude-haiku-4-5","claude-haiku-4-5-20251001","gpt-5.6-luna","gpt-4.1-mini","gpt-4.1","gpt-4.1-nano","gemini-3.5-flash-lite","gemini-2.5-flash","gemini-2.5-pro"]';BEGIN
 IF NOT EXISTS(SELECT 1 FROM tj_private.runtime_environment_manifest WHERE name='AI_UTILITY_MODELS') THEN
 sid:=vault.create_secret(v,'aiq_migrated_runtime_AI_UTILITY_MODELS','Utility model IDs already named by the source proxy and app clients');
 INSERT INTO tj_private.runtime_environment_manifest(name,secret_id,value_sha256) VALUES('AI_UTILITY_MODELS',sid,encode(sha256(convert_to(v,'UTF8')),'hex'));
 END IF;END $$;
