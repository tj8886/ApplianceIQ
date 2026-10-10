// Generates synthetic test SQL from the exact immutable migration files.
const fs=require('node:fs'),path=require('node:path');
const read=name=>fs.readFileSync(path.join(__dirname,name),'utf8');
const migration=name=>read('../../supabase/migrations/'+name);
let fixture=read('test-scope-helper-fixtures.sql')
 .replace('-- BASE_HELPERS',migration('20261004173521_prepare_tj_identity_access_helpers.sql'))
 .replace('-- SCOPE_HELPERS',migration('20261004193021_prepare_tj_scope_access_helpers.sql'));
const policies=migration('20261004193946_restore_tj_reviewed_read_policies.sql');
const tables=[...new Set([...policies.matchAll(/CREATE POLICY consolidation_reviewed_read ON tj\."([a-z0-9_]+)"/g)].map(m=>m[1]))];
const existing=['source_auth_users','source_user_identity_map','organizations','organization_members','platform_admins','org_locations','org_location_members','field_clients','field_manufacturer_users','mfr_user_roles','mdf_platform_users'];
const setup=tables.filter(t=>!existing.includes(t)).map(t=>`CREATE TABLE tj."${t}"(id uuid,organization_id uuid,client_id uuid,store_id uuid);`).join('\n')
 +tables.map(t=>`ALTER TABLE tj."${t}" ENABLE ROW LEVEL SECURITY;`).join('\n');
fixture=fixture.replace(/\bROLLBACK;\s*$/,setup+'\n'+policies+'\n'+read('reviewed-read-policy-test-tail.sql')+'\nROLLBACK;');
if(require.main===module)process.stdout.write(fixture);
module.exports={fixture};
