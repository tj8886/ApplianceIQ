'use strict';
// Build credential-preserving data SQL in memory only. Never log/store its output.
const ql=s=>"'"+String(s).replaceAll("'","''")+"'";
const qi=s=>'"'+s.replaceAll('"','""')+'"';
const hash=(table,where='')=>`SELECT md5(coalesce(string_agg(h,'' ORDER BY h COLLATE "C"),'')) FROM (SELECT md5(to_jsonb(t)::text) h FROM ${table} t ${where}) x`;
function buildAuthImport({users,identities,userColumns,identityColumns,before,batchId,sourceRef}) {
 if(!users.length||users.some(u=>!u.id||!u.email||!u.encrypted_password||u.role!=='authenticated'||u.aud!=='authenticated'||u.is_super_admin||u.is_anonymous||u.deleted_at||u.is_sso_user||u.raw_app_meta_data?.internal_service||u.raw_app_meta_data?.service))throw Error('Unsupported or non-human source account');
 if(new Set(users.map(u=>u.id)).size!==users.length||new Set(users.map(u=>u.email.trim().toLowerCase())).size!==users.length)throw Error('Ambiguous source users');
 const ids=new Set(users.map(u=>u.id));
 if(identities.some(i=>!ids.has(i.user_id)||i.provider!=='email')||users.some(u=>!identities.some(i=>i.user_id===u.id)))throw Error('Missing or unsupported sign-in identity');
 const clean=users.map(u=>({...u,last_sign_in_at:null,confirmation_token:'',confirmation_sent_at:null,recovery_token:'',recovery_sent_at:null,email_change:'',email_change_token_new:'',email_change_token_current:'',email_change_sent_at:null,email_change_confirm_status:0,phone_change:'',phone_change_token:'',phone_change_sent_at:null,reauthentication_token:'',reauthentication_sent_at:null}));
 return `BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL standard_conforming_strings=on;
LOCK TABLE auth.users,auth.identities,tj.source_user_identity_map,tj_private.auth_import_ledger IN ACCESS EXCLUSIVE MODE;
CREATE TEMP TABLE incoming_users (LIKE auth.users) ON COMMIT DROP;
INSERT INTO incoming_users SELECT * FROM jsonb_populate_recordset(NULL::auth.users,${ql(JSON.stringify(clean))}::jsonb);
CREATE TEMP TABLE incoming_identities (LIKE auth.identities) ON COMMIT DROP;
INSERT INTO incoming_identities SELECT * FROM jsonb_populate_recordset(NULL::auth.identities,${ql(JSON.stringify(identities))}::jsonb);
DO $guard$ DECLARE fingerprint text; BEGIN
 SELECT (${hash('auth.users')}) INTO fingerprint;
 IF fingerprint<>${ql(before.users)} THEN RAISE EXCEPTION 'Destination auth users changed since preflight'; END IF;
 SELECT (${hash('auth.identities')}) INTO fingerprint;
 IF fingerprint<>${ql(before.identities)} THEN RAISE EXCEPTION 'Destination sign-in identities changed since preflight'; END IF;
 IF current_setting('session_replication_role')<>'origin' THEN RAISE EXCEPTION 'Auth constraints must remain enforced'; END IF;
 IF EXISTS(SELECT 1 FROM incoming_users s JOIN auth.users u ON u.id=s.id OR lower(btrim(u.email))=lower(btrim(s.email))) THEN RAISE EXCEPTION 'Existing account collision; no credential overwrite allowed'; END IF;
 IF EXISTS(SELECT 1 FROM incoming_users s JOIN public.profiles p ON p.id=s.id) THEN RAISE EXCEPTION 'Existing destination profile collision'; END IF;
 IF EXISTS(SELECT 1 FROM incoming_identities s JOIN auth.identities i ON i.id=s.id OR (i.provider=s.provider AND i.provider_id=s.provider_id)) THEN RAISE EXCEPTION 'Existing sign-in identity collision'; END IF;
 IF EXISTS(SELECT 1 FROM incoming_users u LEFT JOIN tj.source_auth_users a ON a.id=u.id
   LEFT JOIN tj.source_user_identity_map m ON m.source_user_id=u.id
   WHERE a.id IS NULL OR lower(btrim(a.email)) IS DISTINCT FROM lower(btrim(u.email))
     OR m.source_user_id IS NULL OR m.target_user_id IS NOT NULL OR m.identity_verified IS DISTINCT FROM false
     OR m.candidate_target_user_id IS NOT NULL OR m.approved_at IS NOT NULL OR m.approved_by IS NOT NULL
     OR m.mapping_status<>'no_candidate' OR m.activation_status<>'not_activated')
   THEN RAISE EXCEPTION 'Archive or mapping preflight failed'; END IF;
 IF EXISTS(SELECT 1 FROM incoming_users u JOIN tj_private.auth_import_ledger l ON l.source_user_id=u.id AND l.source_project_ref=${ql(sourceRef)}) THEN RAISE EXCEPTION 'Account already imported'; END IF;
END $guard$;
INSERT INTO auth.users(${userColumns.map(qi).join(',')}) SELECT ${userColumns.map(qi).join(',')} FROM incoming_users;
INSERT INTO auth.identities(${identityColumns.map(qi).join(',')}) SELECT ${identityColumns.map(qi).join(',')} FROM incoming_identities;
UPDATE tj.source_auth_users a SET email_confirmed_at=u.email_confirmed_at,banned_until=u.banned_until,deleted_at=u.deleted_at,is_anonymous=u.is_anonymous FROM incoming_users u WHERE a.id=u.id;
UPDATE tj.source_user_identity_map m SET target_user_id=u.id,identity_verified=true,
 verified_by='preserved-source-auth-user-and-password-identity',mapping_status='approved_create',
 mapping_reason='Original source UUID and credentials preserved; no existing destination account overwritten',
 approved_at=now(),approved_by='owner-authorized-project-consolidation',
 activation_status=CASE WHEN u.email_confirmed_at IS NOT NULL AND (u.banned_until IS NULL OR u.banned_until<=now()) THEN 'activated' ELSE 'not_activated' END,
 activated_at=CASE WHEN u.email_confirmed_at IS NOT NULL AND (u.banned_until IS NULL OR u.banned_until<=now()) THEN now() ELSE NULL END,updated_at=now()
 FROM incoming_users u WHERE m.source_user_id=u.id;
INSERT INTO tj_private.auth_import_ledger(source_project_ref,source_user_id,target_user_id,batch_id,source_identity_count,source_email_confirmed,mapping_activated,import_method)
SELECT ${ql(sourceRef)},u.id,u.id,${ql(batchId)}::uuid,(SELECT count(*) FROM incoming_identities i WHERE i.user_id=u.id),u.email_confirmed_at IS NOT NULL,m.activation_status='activated','preserved_source_credentials'
FROM incoming_users u JOIN tj.source_user_identity_map m ON m.source_user_id=u.id;
DO $verify$ BEGIN
 IF (SELECT count(*) FROM auth.users)<>${before.count+users.length} THEN RAISE EXCEPTION 'Unexpected auth user count'; END IF;
 IF EXISTS(SELECT 1 FROM incoming_users s WHERE NOT EXISTS(SELECT 1 FROM auth.users u WHERE u.id=s.id AND u.encrypted_password=s.encrypted_password AND u.email IS NOT DISTINCT FROM s.email)) THEN RAISE EXCEPTION 'Credential preservation failed'; END IF;
 IF EXISTS(SELECT 1 FROM incoming_identities s WHERE NOT EXISTS(SELECT 1 FROM auth.identities i WHERE i.id=s.id AND i.user_id=s.user_id AND i.provider=s.provider AND i.provider_id=s.provider_id AND i.identity_data=s.identity_data)) THEN RAISE EXCEPTION 'Sign-in identity preservation failed'; END IF;
 IF (SELECT (${hash('auth.users','WHERE NOT EXISTS(SELECT 1 FROM incoming_users s WHERE s.id=t.id)')}))<>${ql(before.users)} THEN RAISE EXCEPTION 'Existing destination users changed'; END IF;
 IF (SELECT (${hash('auth.identities','WHERE NOT EXISTS(SELECT 1 FROM incoming_identities s WHERE s.id=t.id)')}))<>${ql(before.identities)} THEN RAISE EXCEPTION 'Existing destination identities changed'; END IF;
END $verify$;
SELECT json_build_object('imported_users',(SELECT count(*) FROM incoming_users),'imported_identities',(SELECT count(*) FROM incoming_identities),'activated',(SELECT count(*) FROM tj_private.auth_import_ledger WHERE batch_id=${ql(batchId)}::uuid AND mapping_activated),'pending',(SELECT count(*) FROM tj_private.auth_import_ledger WHERE batch_id=${ql(batchId)}::uuid AND NOT mapping_activated)) AS result;
COMMIT;`;
}
module.exports={buildAuthImport};
