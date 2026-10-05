-- Empty-preview fixtures only; insertion markers filled by the repository runner.
BEGIN;
CREATE SCHEMA tj;
CREATE TABLE tj.source_auth_users(id uuid PRIMARY KEY,email text,deleted_at timestamptz,banned_until timestamptz,is_anonymous boolean);
CREATE TABLE tj.source_user_identity_map(source_user_id uuid PRIMARY KEY,target_user_id uuid,identity_verified boolean,mapping_status text,approved_at timestamptz,approved_by text,activation_status text,activated_at timestamptz);
CREATE TABLE tj.organizations(id uuid PRIMARY KEY);
CREATE TABLE tj.organization_members(id uuid PRIMARY KEY,organization_id uuid,user_id uuid,role text,status text,visibility_scope text,manager_id uuid);
CREATE TABLE tj.platform_admins(user_id uuid);
CREATE TABLE tj.org_locations(id uuid PRIMARY KEY,organization_id uuid,iq_store_id uuid);
CREATE TABLE tj.org_location_members(organization_id uuid,location_id uuid,user_id uuid);
CREATE TABLE tj.field_clients(id uuid PRIMARY KEY,organization_id uuid);
CREATE TABLE tj.field_manufacturer_users(client_id uuid,user_id uuid,status text);
CREATE TABLE tj.mfr_user_roles(user_id uuid,is_admin boolean);
CREATE TABLE tj.mdf_platform_users(email text,role text,org_id uuid,is_active boolean);
INSERT INTO auth.users(id) VALUES('00000000-0000-0000-0000-000000000101'),('00000000-0000-0000-0000-000000000102');
INSERT INTO tj.source_auth_users VALUES('00000000-0000-0000-0000-000000000001','fixture@example.invalid',NULL,NULL,false);
INSERT INTO tj.source_user_identity_map VALUES('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000101',false,'candidate_found',NULL,NULL,'not_activated',NULL);
INSERT INTO tj.organizations VALUES('00000000-0000-0000-0000-000000000201'),('00000000-0000-0000-0000-000000000202');
INSERT INTO tj.organization_members VALUES
 ('00000000-0000-0000-0000-000000000401','00000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000001','member','active','own','00000000-0000-0000-0000-000000000402'),
 ('00000000-0000-0000-0000-000000000402','00000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000002','member','active','own','00000000-0000-0000-0000-000000000401'),
 ('00000000-0000-0000-0000-000000000403','00000000-0000-0000-0000-000000000202','00000000-0000-0000-0000-000000000003','member','active','own','00000000-0000-0000-0000-000000000401');
INSERT INTO tj.org_locations VALUES('00000000-0000-0000-0000-000000000301','00000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000311'),('00000000-0000-0000-0000-000000000302','00000000-0000-0000-0000-000000000202',NULL);
INSERT INTO tj.org_location_members VALUES
 ('00000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000301','00000000-0000-0000-0000-000000000001'),
 ('00000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000301','00000000-0000-0000-0000-000000000002');
INSERT INTO tj.field_clients VALUES('00000000-0000-0000-0000-000000000501','00000000-0000-0000-0000-000000000201'),('00000000-0000-0000-0000-000000000502','00000000-0000-0000-0000-000000000202');
INSERT INTO tj.mfr_user_roles VALUES('00000000-0000-0000-0000-000000000001',true);
INSERT INTO tj.mdf_platform_users VALUES('fixture@example.invalid','admin','00000000-0000-0000-0000-000000000201',true);
-- BASE_HELPERS
-- SCOPE_HELPERS
SET LOCAL request.jwt.claim.sub='00000000-0000-0000-0000-000000000101';
SET LOCAL ROLE authenticated;
DO $test$ BEGIN
 IF tj.aiq_scope_allows('00000000-0000-0000-0000-000000000201',NULL) OR tj.aiq_store_allows('00000000-0000-0000-0000-000000000201',NULL) OR tj.is_admin() OR tj.is_org_manager('00000000-0000-0000-0000-000000000201') OR tj.is_field_client_member('00000000-0000-0000-0000-000000000501') OR tj.mdf_has_access() OR tj.mdf_get_user_role() IS NOT NULL THEN RAISE EXCEPTION 'Unverified identity gained permissions'; END IF;
END $test$;
RESET ROLE;
UPDATE tj.source_user_identity_map SET identity_verified=true,mapping_status='approved_map',approved_at=now(),approved_by='fixture',activation_status='activated',activated_at=now();
SET LOCAL ROLE authenticated;
DO $test$ BEGIN
 IF NOT tj.aiq_scope_allows('00000000-0000-0000-0000-000000000201',NULL) OR NOT tj.aiq_scope_allows('00000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000001') OR NOT tj.aiq_store_allows('00000000-0000-0000-0000-000000000201',NULL) THEN RAISE EXCEPTION 'Valid member own/unassigned access denied'; END IF;
 IF tj.aiq_scope_allows('00000000-0000-0000-0000-000000000202',NULL) OR tj.aiq_scope_allows('00000000-0000-0000-0000-000000000202','00000000-0000-0000-0000-000000000001') OR tj.aiq_store_allows('00000000-0000-0000-0000-000000000202',NULL) OR tj.aiq_store_allows(NULL,NULL) THEN RAISE EXCEPTION 'Cross-organization unassigned shortcut allowed'; END IF;
 IF tj.aiq_scope_allows('00000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000002') THEN RAISE EXCEPTION 'Own visibility saw colleague'; END IF;
 IF NOT tj.aiq_store_allows('00000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000301') OR NOT tj.aiq_store_allows('00000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000311') OR tj.aiq_store_allows('00000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000302') THEN RAISE EXCEPTION 'Store membership boundaries failed'; END IF;
 IF NOT tj.is_admin() OR tj.is_org_manager('00000000-0000-0000-0000-000000000201') OR NOT tj.is_field_client_member('00000000-0000-0000-0000-000000000501') OR tj.is_field_client_member('00000000-0000-0000-0000-000000000502') THEN RAISE EXCEPTION 'Admin/manager/client roles incorrect'; END IF;
 IF tj.mdf_get_user_role() IS DISTINCT FROM 'admin' OR NOT tj.mdf_has_access() THEN RAISE EXCEPTION 'Mapped MDF role denied'; END IF;
END $test$;
RESET ROLE;
UPDATE tj.organization_members SET visibility_scope='store',role='sales_manager' WHERE user_id='00000000-0000-0000-0000-000000000001';
SET LOCAL ROLE authenticated;
DO $test$ BEGIN
 IF NOT tj.aiq_scope_allows('00000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000002') OR NOT tj.is_org_manager('00000000-0000-0000-0000-000000000201') OR tj.is_org_manager('00000000-0000-0000-0000-000000000202') THEN RAISE EXCEPTION 'Store scope/manager role incorrect'; END IF;
END $test$;
RESET ROLE;
UPDATE tj.organization_members SET visibility_scope='team' WHERE user_id='00000000-0000-0000-0000-000000000001';
SET LOCAL statement_timeout='5s';
SET LOCAL ROLE authenticated;
DO $test$ BEGIN
 IF NOT tj.aiq_scope_allows('00000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000002') OR tj.aiq_scope_allows('00000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000003') OR tj.aiq_scope_allows('00000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000999') THEN RAISE EXCEPTION 'Team cycle/cross-org boundaries failed'; END IF;
END $test$;
RESET ROLE;
INSERT INTO tj.field_manufacturer_users VALUES('00000000-0000-0000-0000-000000000502','00000000-0000-0000-0000-000000000001','active');
SET LOCAL ROLE authenticated;
DO $test$ BEGIN IF NOT tj.is_field_client_member('00000000-0000-0000-0000-000000000502') THEN RAISE EXCEPTION 'Explicit active manufacturer client denied'; END IF; END $test$;
RESET ROLE;
UPDATE tj.field_manufacturer_users SET status='inactive';
INSERT INTO tj.mdf_platform_users VALUES('FIXTURE@example.invalid','viewer','00000000-0000-0000-0000-000000000201',true);
SET LOCAL ROLE authenticated;
DO $test$ BEGIN IF tj.mdf_has_access() OR tj.is_field_client_member('00000000-0000-0000-0000-000000000502') THEN RAISE EXCEPTION 'Ambiguous MDF identity or inactive manufacturer allowed'; END IF; END $test$;
RESET ROLE;
DELETE FROM tj.mdf_platform_users WHERE role='viewer';
UPDATE tj.organization_members SET status='inactive' WHERE user_id='00000000-0000-0000-0000-000000000001';
SET LOCAL ROLE authenticated;
DO $test$ BEGIN IF tj.aiq_scope_allows('00000000-0000-0000-0000-000000000201',NULL) OR tj.aiq_store_allows('00000000-0000-0000-0000-000000000201',NULL) OR tj.is_org_manager('00000000-0000-0000-0000-000000000201') OR tj.mdf_has_access() THEN RAISE EXCEPTION 'Inactive org membership allowed'; END IF; END $test$;
RESET ROLE;
SET LOCAL request.jwt.claim.sub='00000000-0000-0000-0000-000000000102';
SET LOCAL request.jwt.claims='{"email":"fixture@example.invalid"}';
SET LOCAL ROLE authenticated;
DO $test$ BEGIN IF tj.mdf_has_access() OR tj.is_admin() THEN RAISE EXCEPTION 'Unmapped JWT email gained permission'; END IF; END $test$;
RESET ROLE;
DO $test$ DECLARE f regprocedure; BEGIN
 FOR f IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('tj','tj_private') LOOP
   IF has_function_privilege('anon',f,'EXECUTE') THEN RAISE EXCEPTION 'Anon can execute helper: %',f; END IF;
 END LOOP;
END $test$;
ROLLBACK;
