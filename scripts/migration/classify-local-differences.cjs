#!/usr/bin/env node
// Read-only local delta classification. Never transfers row contents.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { spawnSync } = require('node:child_process');
process.env.PATH = `/Applications/Docker.app/Contents/Resources/bin:${path.join(os.homedir(), '.docker/bin')}:${process.env.PATH}`;
const root = process.argv[2] || path.join(os.homedir(), 'applianceiq-database-backups-20261004-114137');
const ca = 'supabase_db_applianceiq-canada-restore-20261004';
const us = 'supabase_db_applianceiq-restore-rehearsal-20261004';
function docker(args, input) {
  const r = spawnSync('docker', args, { input, encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 });
  if (r.error) throw r.error;
  if (r.status !== 0) throw new Error(r.stderr || `Docker exited ${r.status}`);
  return r.stdout;
}
function query(db, sql) {
  return docker(['exec','-i',db,'psql','-X','-U','supabase_admin','-d','postgres','-At','-v','ON_ERROR_STOP=1'],
    `BEGIN READ ONLY; SET LOCAL timezone='UTC'; SET LOCAL bytea_output='hex';\n${sql}\nROLLBACK;`)
    .split('\n').filter(line => line.startsWith('{') || line.startsWith('[')).map(line => JSON.parse(line));
}
const literal = v => "'" + v.replaceAll("'", "''") + "'";
const identifier = v => '"' + v.replaceAll('"','""') + '"';
for (const db of [ca, us]) {
  if (Object.keys(JSON.parse(docker(['inspect','--format','{{json .NetworkSettings.Networks}}',db]))).length)
    throw new Error('Both rehearsal databases must remain network-isolated');
  if (docker(['exec',db,'psql','-X','-U','supabase_admin','-d','postgres','-Atc','SHOW cron.launch_active_jobs;']).trim() !== 'off')
    throw new Error('Both rehearsal databases must keep cron launches off');
}
const previous = JSON.parse(fs.readFileSync(path.join(root,'staging-reconciliation.json'),'utf8'));
const differences = previous.comparisons.filter(item => !item.matches);
function primaryKey(db, schema, table) {
  const result = query(db, `SELECT coalesce(json_agg(a.attname ORDER BY k.position),'[]'::json)
FROM pg_constraint c CROSS JOIN LATERAL generate_subscripts(c.conkey,1) k(position)
JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=c.conkey[k.position]
WHERE c.contype='p' AND c.conrelid=to_regclass(${literal(identifier(schema)+'.'+identifier(table))});`);
  const key = result[0];
  if (!key || !key.length) throw new Error(`Missing primary key for ${schema}.${table}`);
  return key;
}
function rows(db, schema, table, key) {
  const result = query(db, `SELECT json_build_object('key',jsonb_build_array(${key.map(k=>'t.'+identifier(k)).join(',')}),'hash',md5(to_jsonb(t)::text)) FROM ${identifier(schema)}.${identifier(table)} t;`);
  const map = new Map(result.map(row => [JSON.stringify(row.key),row.hash]));
  if (map.size !== result.length) throw new Error(`Duplicate primary keys in ${schema}.${table}`);
  return map;
}
const classifications = [];
for (const item of differences) {
  const table = item.table;
  console.log(`Classifying ${table}...`);
  const key = primaryKey(ca,'public',table);
  if (JSON.stringify(key) !== JSON.stringify(primaryKey(us,'tj',table))) throw new Error(`Primary key differs for ${table}`);
  const source = rows(ca,'public',table,key), target = rows(us,'tj',table,key);
  if (source.size !== item.canadian.rows || target.size !== item.staged.rows)
    throw new Error(`Row counts changed since reconciliation for ${table}; rerun the comparison`);
  const sourceOnly = [], targetOnly = [], changed = [];
  let identical = 0;
  for (const [id,hash] of source) {
    if (!target.has(id)) sourceOnly.push(JSON.parse(id));
    else if (target.get(id) !== hash) changed.push(JSON.parse(id));
    else identical++;
  }
  for (const id of target.keys()) if (!source.has(id)) targetOnly.push(JSON.parse(id));
  classifications.push({table,primary_key:key,identical_rows:identical,
    canada_only_count:sourceOnly.length,us_only_count:targetOnly.length,changed_count:changed.length,
    canada_only_keys:sourceOnly,us_only_keys:targetOnly,changed_keys:changed});
}
const output = path.join(root,'staging-delta-classification.json');
fs.writeFileSync(output,JSON.stringify({checked_at:new Date().toISOString(),scope:'Differing tables in isolated restored backups; identifiers and counts only',tables:classifications},null,2)+'\n',{mode:0o600});
console.log('\nTABLE | CANADA ONLY | US ONLY | CHANGED | IDENTICAL');
for (const item of classifications) console.log(`${item.table} | ${item.canada_only_count} | ${item.us_only_count} | ${item.changed_count} | ${item.identical_rows}`);
console.log(`Report: ${output}`);
