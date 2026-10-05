// Synthetic auth import test: no real users, credentials, or sessions.
const fs=require('node:fs'),path=require('node:path');
const {buildAuthImport}=require('./build-auth-import.cjs');
const {fixture:base}=require('./build-reviewed-read-policy-fixture.cjs');
const uuid=n=>'00000000-0000-0000-0000-'+String(n).padStart(12,'0');
const users=[901,902].map(n=>({id:uuid(n),instance_id:uuid(0),aud:'authenticated',role:'authenticated',email:`fixture-${n}@example.invalid`,encrypted_password:'synthetic-hash-no-real-credentials',email_confirmed_at:n===901?'2026-10-01T00:00:00Z':null,raw_app_meta_data:{provider:'email',providers:['email']},raw_user_meta_data:{name:"Synthetic ' quoted text only"},is_super_admin:false,is_sso_user:false,is_anonymous:false,created_at:'2026-10-01T00:00:00Z',updated_at:'2026-10-01T00:00:00Z',banned_until:null,deleted_at:null}));
const identities=users.map((u,i)=>({id:uuid(991+i),user_id:u.id,provider_id:u.id,provider:'email',identity_data:{sub:u.id,email:u.email},created_at:'2026-10-01T00:00:00Z',updated_at:'2026-10-01T00:00:00Z'}));
const userColumns=Object.keys(users[0]).concat(['confirmation_token','confirmation_sent_at','recovery_token','recovery_sent_at','email_change_token_new','email_change','email_change_sent_at','last_sign_in_at','phone_change','phone_change_token','phone_change_sent_at','email_change_token_current','email_change_confirm_status','reauthentication_token','reauthentication_sent_at']);
let sql=buildAuthImport({users,identities,userColumns,identityColumns:Object.keys(identities[0]),before:{count:2,users:'BEFORE_USERS',identities:'BEFORE_IDENTITIES'},batchId:uuid(999),sourceRef:'synthetic-source'});
sql=sql.replace(/^BEGIN;/,'').replace(/COMMIT;\s*$/,'').replaceAll("'BEFORE_USERS'",'(SELECT users FROM pre_hashes)').replaceAll("'BEFORE_IDENTITIES'",'(SELECT identities FROM pre_hashes)');
const setup=`CREATE TABLE public.profiles(id uuid PRIMARY KEY,email text,full_name text);
CREATE FUNCTION public.fixture_profile() RETURNS trigger LANGUAGE plpgsql AS $f$ BEGIN INSERT INTO public.profiles VALUES(NEW.id,NEW.email,NEW.raw_user_meta_data->>'name');RETURN NEW;END $f$;
CREATE TRIGGER fixture_new_user AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.fixture_profile();
ALTER TABLE tj.source_auth_users ADD COLUMN email_confirmed_at timestamptz;
ALTER TABLE tj.source_user_identity_map ADD COLUMN verified_by text, ADD COLUMN mapping_reason text, ADD COLUMN updated_at timestamptz, ADD COLUMN candidate_target_user_id uuid;
INSERT INTO tj.source_auth_users(id,email) VALUES('${uuid(901)}','fixture-901@example.invalid'),('${uuid(902)}','fixture-902@example.invalid');
INSERT INTO tj.source_user_identity_map(source_user_id,identity_verified,mapping_status,activation_status) VALUES('${uuid(901)}',false,'no_candidate','not_activated'),('${uuid(902)}',false,'no_candidate','not_activated');
CREATE TEMP TABLE pre_hashes AS SELECT (SELECT md5(coalesce(string_agg(h,'' ORDER BY h COLLATE "C"),'')) FROM (SELECT md5(to_jsonb(t)::text) h FROM auth.users t) x) AS users,(SELECT md5(coalesce(string_agg(h,'' ORDER BY h COLLATE "C"),'')) FROM (SELECT md5(to_jsonb(t)::text) h FROM auth.identities t) x) AS identities;`;
const ledger=fs.readFileSync(path.join(__dirname,'../../supabase/migrations/20261004195015_prepare_tj_auth_import_ledger.sql'),'utf8');
const assertions=`DO $assert$ BEGIN
IF (SELECT count(*) FROM tj_private.auth_import_ledger)<>2 OR (SELECT count(*) FROM tj_private.auth_import_ledger WHERE mapping_activated)<>1 OR (SELECT count(*) FROM public.profiles)<>2 THEN RAISE EXCEPTION 'Auth import fixture counts failed';END IF;
IF EXISTS(SELECT 1 FROM auth.users WHERE id IN ('${uuid(901)}','${uuid(902)}') AND (recovery_token<>'' OR confirmation_token<>'')) THEN RAISE EXCEPTION 'Active sign-in tokens copied'; END IF;
END $assert$; ROLLBACK;`;
const fixture=base.replace(/\bROLLBACK;\s*$/,'')+ledger+setup+sql+assertions;
if(require.main===module)process.stdout.write(fixture);
module.exports={fixture};
