-- Synthetic CRM fixtures and any recalculated scores roll back together.
BEGIN;
SET LOCAL statement_timeout='25s';
DO $$ DECLARE target_u uuid; source_u uuid; org uuid; foreign_org uuid; recipient uuid;
 c1 uuid:=gen_random_uuid(); c2 uuid:=gen_random_uuid(); gone uuid:=gen_random_uuid();
 open_deal uuid:=gen_random_uuid(); terminal uuid:=gen_random_uuid(); anniversary uuid:=gen_random_uuid(); foreign_deal uuid:=gen_random_uuid();
 BEGIN
 SELECT im.target_user_id,im.source_user_id,m.organization_id INTO target_u,source_u,org
 FROM tj.source_user_identity_map im JOIN tj.organization_members m ON m.user_id=im.source_user_id
 JOIN tj.organizations o ON o.id=m.organization_id AND o.deleted_at IS NULL
 WHERE im.activation_status='activated' AND m.status='active' AND m.role IN('owner','admin')
 AND NOT EXISTS(SELECT 1 FROM tj.platform_admins a WHERE a.user_id=im.source_user_id) LIMIT 1;
 SELECT o.id INTO foreign_org FROM tj.organizations o WHERE o.deleted_at IS NULL AND o.id<>org
 AND NOT EXISTS(SELECT 1 FROM tj.organization_members m WHERE m.user_id=source_u AND m.organization_id=o.id AND m.status='active') LIMIT 1;
 SELECT id INTO recipient FROM tj.source_auth_users WHERE id<>source_u LIMIT 1;
 IF target_u IS NULL OR foreign_org IS NULL OR recipient IS NULL THEN RAISE EXCEPTION 'CRM fixture identities unavailable'; END IF;
 INSERT INTO tj.organization_members(organization_id,user_id,role,status) VALUES(org,recipient,'member','active')
 ON CONFLICT(organization_id,user_id) DO UPDATE SET status='active';
 PERFORM set_config('request.jwt.claim.sub',target_u::text,true);
 PERFORM set_config('test.org',org::text,true); PERFORM set_config('test.foreign',foreign_org::text,true);
 PERFORM set_config('test.source',source_u::text,true); PERFORM set_config('test.recipient',recipient::text,true);
 PERFORM set_config('test.c1',c1::text,true); PERFORM set_config('test.c2',c2::text,true); PERFORM set_config('test.gone',gone::text,true);
 PERFORM set_config('test.open',open_deal::text,true); PERFORM set_config('test.terminal',terminal::text,true); PERFORM set_config('test.anniversary',anniversary::text,true); PERFORM set_config('test.foreign_deal',foreign_deal::text,true);
 INSERT INTO tj.contacts(id,organization_id,first_name,last_name,email,phone,temperature,last_communication_at,decision_making_role,is_iq_lead)
 VALUES(c1,org,'Migration','Fixture',c1::text||'@example.invalid','fixture-'||c1,'hot',now(),'decision_maker',true),
 (c2,org,'Migration','Fixture',c1::text||'@example.invalid','fixture-'||c1,'cold',NULL,NULL,false);
 INSERT INTO tj.contacts(id,organization_id,first_name,email,deleted_at,lead_score)
 VALUES(gone,org,'Deleted fixture',c1::text||'@example.invalid',now(),23);
 INSERT INTO tj.crm_deals(id,organization_id,contact_id,owner_user_id,title,stage,value_amount,purchase_date)
 VALUES(open_deal,org,c1,source_u,'Migration fixture','Lead',6001,NULL),
 (terminal,org,c1,source_u,'Terminal fixture','Closed Won',1,NULL),
 (anniversary,org,c1,recipient,'Anniversary fixture','Closed Won',1,(CURRENT_DATE-interval '1 year'+interval '1 day')::date),
 (foreign_deal,foreign_org,NULL,source_u,'Foreign fixture','Lead',1,NULL);
END $$;
SET LOCAL ROLE authenticated;
DO $$ DECLARE org uuid:=current_setting('test.org')::uuid; other uuid:=current_setting('test.foreign')::uuid; c1 uuid:=current_setting('test.c1')::uuid; c2 uuid:=current_setting('test.c2')::uuid; n int; BEGIN
 SELECT count(*) INTO n FROM tj.find_duplicate_contacts(org) WHERE (contact_id_1=c1 AND contact_id_2=c2) OR (contact_id_1=c2 AND contact_id_2=c1);
 IF n<>3 THEN RAISE EXCEPTION 'Email/phone/name duplicate matching failed'; END IF;
 IF EXISTS(SELECT 1 FROM tj.find_duplicate_contacts(org) WHERE contact_id_1=current_setting('test.gone')::uuid OR contact_id_2=current_setting('test.gone')::uuid) THEN RAISE EXCEPTION 'Deleted contact exposed'; END IF;
 IF NOT EXISTS(SELECT 1 FROM tj.get_anniversary_outreach(org,30) WHERE deal_id=current_setting('test.anniversary')::uuid AND days_until=1 AND anniversary_number=1) THEN RAISE EXCEPTION 'Anniversary lookup failed'; END IF;
 PERFORM tj.score_leads(org);
 BEGIN PERFORM tj.crm_reassign_rep_deals(org,current_setting('test.source')::uuid,current_setting('test.recipient')::uuid,p_actor_id=>gen_random_uuid());
 RAISE EXCEPTION 'Forged actor accepted'; EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'invalid_actor' THEN RAISE; END IF; END;
 PERFORM tj.crm_reassign_rep_deals(org,current_setting('test.source')::uuid,current_setting('test.recipient')::uuid,p_actor_id=>auth.uid());
 BEGIN PERFORM tj.find_duplicate_contacts(other); RAISE EXCEPTION 'Foreign duplicate lookup allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM tj.get_anniversary_outreach(other); RAISE EXCEPTION 'Foreign anniversary lookup allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM tj.score_leads(other); RAISE EXCEPTION 'Foreign score update allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM tj.crm_reassign_rep_deals(other,current_setting('test.source')::uuid,current_setting('test.recipient')::uuid); RAISE EXCEPTION 'Foreign reassignment allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
DO $$ BEGIN
 IF (SELECT lead_score FROM tj.contacts WHERE id=current_setting('test.c1')::uuid)<>95 THEN RAISE EXCEPTION 'Lead score formula mismatch'; END IF;
 IF (SELECT lead_score FROM tj.contacts WHERE id=current_setting('test.gone')::uuid)<>23 THEN RAISE EXCEPTION 'Deleted lead scored'; END IF;
 IF (SELECT owner_user_id FROM tj.crm_deals WHERE id=current_setting('test.open')::uuid)<>current_setting('test.recipient')::uuid THEN RAISE EXCEPTION 'Open deal not reassigned'; END IF;
 IF EXISTS(SELECT 1 FROM tj.crm_deals WHERE id IN(current_setting('test.terminal')::uuid,current_setting('test.foreign_deal')::uuid) AND owner_user_id<>current_setting('test.source')::uuid) THEN RAISE EXCEPTION 'Terminal/foreign deal changed'; END IF;
 IF NOT EXISTS(SELECT 1 FROM tj.crm_deal_reassignments WHERE deal_id=current_setting('test.open')::uuid AND reassigned_by=current_setting('test.source')::uuid AND to_user_id=current_setting('test.recipient')::uuid) THEN RAISE EXCEPTION 'Reassignment audit missing'; END IF;
 UPDATE tj.organization_members SET role='member' WHERE organization_id=current_setting('test.org')::uuid AND user_id=current_setting('test.source')::uuid;
END $$;
SET LOCAL ROLE authenticated;
DO $$ BEGIN
 BEGIN PERFORM tj.crm_reassign_rep_deals(current_setting('test.org')::uuid,current_setting('test.source')::uuid,current_setting('test.recipient')::uuid); RAISE EXCEPTION 'Ordinary member reassignment allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 BEGIN PERFORM tj.score_leads(current_setting('test.org')::uuid); RAISE EXCEPTION 'Unmapped score update allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
DO $$ DECLARE fn text; BEGIN
 FOREACH fn IN ARRAY ARRAY['tj.find_duplicate_contacts(uuid)','tj.get_anniversary_outreach(uuid,integer)','tj.score_leads(uuid)','tj.crm_reassign_rep_deals(uuid,uuid,uuid,text,uuid)'] LOOP
 IF has_function_privilege('anon',fn,'EXECUTE') THEN RAISE EXCEPTION 'Anonymous CRM execution allowed'; END IF;
 END LOOP;
END $$;
ROLLBACK;
