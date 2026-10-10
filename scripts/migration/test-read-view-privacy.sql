BEGIN;SET LOCAL statement_timeout='30s';
DO $$ DECLARE u uuid;src uuid;org uuid;other uuid;r uuid:=gen_random_uuid();nr uuid:=gen_random_uuid();fr uuid:=gen_random_uuid();a uuid:=gen_random_uuid(); BEGIN
 SELECT im.target_user_id,im.source_user_id,m.organization_id INTO u,src,org FROM tj.source_user_identity_map im JOIN tj.organization_members m ON m.user_id=im.source_user_id JOIN tj.organizations o ON o.id=m.organization_id WHERE im.activation_status='activated' AND m.status='active' AND o.status='active' AND o.deleted_at IS NULL AND NOT EXISTS(SELECT 1 FROM tj.platform_admins p WHERE p.user_id=im.source_user_id) LIMIT 1;
 SELECT id INTO other FROM tj.source_auth_users WHERE id<>src LIMIT 1;
 IF u IS NULL OR other IS NULL THEN RAISE EXCEPTION 'Fixture unavailable';END IF;
 PERFORM set_config('request.jwt.claim.sub',u::text,true);PERFORM set_config('test.recording',r::text,true);PERFORM set_config('test.no_consent',nr::text,true);PERFORM set_config('test.foreign_recording',fr::text,true);PERFORM set_config('test.activity',a::text,true);
 UPDATE tj.organization_members SET role='member',visibility_scope='own' WHERE organization_id=org AND user_id=src;
 INSERT INTO tj.sales_recordings(id,organization_id,user_id,kind,file_path,consent_confirmed) VALUES(r,org,src,'voice_call','rollback/consented',true),(nr,org,src,'voice_call','rollback/no-consent',false),(fr,org,other,'voice_call','rollback/other-user',true);
 INSERT INTO tj.recording_transcripts(organization_id,recording_id,content) VALUES(org,r,'Synthetic fixture'),(org,nr,'Synthetic fixture'),(org,fr,'Synthetic fixture');
 INSERT INTO tj.activities(id,organization_id,user_id,actor_user_id,activity_type,title,related_recording_id,entity_type,entity_id) VALUES(a,org,src,src,'voice_call','Synthetic fixture',nr,'contact',gen_random_uuid());
END $$;
SET LOCAL ROLE authenticated;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM tj.sales_recordings WHERE id=current_setting('test.recording')::uuid) OR NOT EXISTS(SELECT 1 FROM tj.recording_transcripts WHERE recording_id=current_setting('test.recording')::uuid) THEN RAISE EXCEPTION 'Own consented data hidden';END IF;
 IF EXISTS(SELECT 1 FROM tj.sales_recordings WHERE id=current_setting('test.foreign_recording')::uuid) OR EXISTS(SELECT 1 FROM tj.recording_transcripts WHERE recording_id IN(current_setting('test.no_consent')::uuid,current_setting('test.foreign_recording')::uuid)) THEN RAISE EXCEPTION 'Consent or owner isolation failed';END IF;
 IF NOT EXISTS(SELECT 1 FROM tj.crm_conversation_records WHERE activity_id=current_setting('test.activity')::uuid AND recording_id IS NULL AND transcript IS NULL) THEN RAISE EXCEPTION 'Conversation join consent gate failed';END IF;
END $$;
RESET ROLE;ROLLBACK;
