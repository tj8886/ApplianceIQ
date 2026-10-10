-- Appended to scope fixtures after the actual reviewed read migration.
SET LOCAL request.jwt.claim.sub='00000000-0000-0000-0000-000000000102';
SET LOCAL ROLE authenticated;
DO $test$ DECLARE t text; found boolean; BEGIN
 FOR t IN SELECT DISTINCT tablename FROM pg_policies WHERE schemaname='tj' LOOP
   EXECUTE format('SELECT EXISTS(SELECT 1 FROM tj.%I)',t) INTO found;
   IF found THEN RAISE EXCEPTION 'Unmapped account can read %',t; END IF;
 END LOOP;
END $test$;
RESET ROLE;
UPDATE tj.organization_members SET status='active' WHERE user_id='00000000-0000-0000-0000-000000000001';
SET LOCAL request.jwt.claim.sub='00000000-0000-0000-0000-000000000101';
INSERT INTO tj.iq_customer_interactions VALUES
('00000000-0000-0000-0000-000000000601','00000000-0000-0000-0000-000000000201',NULL,'00000000-0000-0000-0000-000000000301'),
('00000000-0000-0000-0000-000000000602','00000000-0000-0000-0000-000000000201',NULL,'00000000-0000-0000-0000-000000000302'),
('00000000-0000-0000-0000-000000000603','00000000-0000-0000-0000-000000000202',NULL,NULL);
SET LOCAL ROLE authenticated;
DO $test$ BEGIN
 IF (SELECT count(*) FROM tj.organizations)<>1 THEN RAISE EXCEPTION 'Organization policy isolation failed'; END IF;
 IF (SELECT count(*) FROM tj.iq_customer_interactions)<>1 THEN RAISE EXCEPTION 'Overlapping member policy bypassed store restriction'; END IF;
 IF has_table_privilege(current_user,'tj.iq_customer_interactions','INSERT') THEN RAISE EXCEPTION 'Read migration granted writes'; END IF;
END $test$;
RESET ROLE;
