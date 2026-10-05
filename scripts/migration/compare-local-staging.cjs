#!/usr/bin/env node
// Only docker exec into the two known, network-isolated rehearsal containers.
// No database URLs, credentials, remote calls, or record contents are output.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { spawnSync } = require('node:child_process');
process.env.PATH = `/Applications/Docker.app/Contents/Resources/bin:${path.join(os.homedir(), '.docker/bin')}:${process.env.PATH}`;
const root = process.argv[2] || path.join(os.homedir(), 'applianceiq-database-backups-20261004-114137');
const ca = 'supabase_db_applianceiq-canada-restore-20261004';
const us = 'supabase_db_applianceiq-restore-rehearsal-20261004';
function docker(args, input) {
  const result = spawnSync('docker', args, { input, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(result.stderr || `Docker exited ${result.status}`);
  return result;
}
for (const db of [ca, us]) {
  const networks = JSON.parse(docker(['inspect', '--format', '{{json .NetworkSettings.Networks}}', db]).stdout);
  if (Object.keys(networks).length) throw new Error(`${db} must be disconnected from all networks`);
  const cron = docker(['exec', db, 'psql', '-X', '-U', 'supabase_admin', '-d', 'postgres', '-Atc', 'SHOW cron.launch_active_jobs;']).stdout.trim();
  if (cron !== 'off') throw new Error(`${db} cron job launches must be off`);
}
const inventory = docker(['exec', ca, 'psql', '-X', '-U', 'supabase_admin', '-d', 'postgres', '-Atc',
  "SELECT coalesce(json_agg(c.relname ORDER BY c.relname),'[]'::json) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN ('r','p');"]);
const tables = JSON.parse(inventory.stdout.trim());
if (!tables.length) throw new Error('No Canadian public tables found');
function literal(value) { return "'" + value.replaceAll("'", "''") + "'"; }
function scan(db, schema) {
  console.log(`Checking ${tables.length} tables in ${schema} on ${db}. Please wait.`);
  const query = `BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL timezone='UTC';
SET LOCAL bytea_output='hex';
DO $scan$
DECLARE name text; row_count bigint; checksum text; checked integer:=0;
BEGIN
FOREACH name IN ARRAY ARRAY[${tables.map(literal).join(',')}] LOOP
IF to_regclass(format('%I.%I',${literal(schema)},name)) IS NULL THEN
  RAISE NOTICE 'RECON:%',json_build_object('table',name,'missing',true);
ELSE
  EXECUTE format('SELECT count(*),md5(coalesce(string_agg(row_hash, %L ORDER BY row_hash COLLATE "C"),%L)) FROM (SELECT md5(to_jsonb(t)::text) AS row_hash FROM %I.%I t) row_hashes',
    '', '', ${literal(schema)}, name) INTO row_count,checksum;
  RAISE NOTICE 'RECON:%',json_build_object('table',name,'rows',row_count,'checksum',checksum);
END IF;
checked:=checked+1;
END LOOP;
END $scan$;
ROLLBACK;`;
  const result = docker(['exec', '-i', db, 'psql', '-X', '-U', 'supabase_admin', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1'], query);
  const records = result.stderr.split('\n').filter(line => line.includes('RECON:'))
    .map(line => JSON.parse(line.slice(line.indexOf('RECON:') + 6)));
  if (records.length !== tables.length) throw new Error(`Incomplete ${schema} checksum output`);
  return new Map(records.map(record => [record.table, record]));
}
const source = scan(ca, 'public');
const destination = scan(us, 'tj');
const comparisons = tables.map(table => {
  const canadian = source.get(table), staged = destination.get(table);
  return { table, canadian, staged, matches: !staged.missing && canadian.rows === staged.rows && canadian.checksum === staged.checksum };
});
const differences = comparisons.filter(item => !item.matches);
const report = { checked_at: new Date().toISOString(), scope: 'Canadian public tables versus US tj in isolated restored backups; views and logic excluded',
  checksum_method: 'MD5 of sorted per-row JSONB MD5 hashes, with row count; accidental-change comparison, not adversarial proof',
  tables_checked: comparisons.length, matching_tables: comparisons.length - differences.length,
  differing_tables: differences.length, comparisons };
const output = path.join(root, 'staging-reconciliation.json');
fs.writeFileSync(output, JSON.stringify(report, null, 2) + '\n', { mode: 0o600 });
console.log(`Comparison complete: ${report.tables_checked} tables; ${report.matching_tables} match; ${report.differing_tables} differ.`);
for (const item of differences.slice(0, 30)) {
  console.log(`${item.table}: Canada ${item.canadian.rows}; US staged ${item.staged.missing ? 'MISSING' : item.staged.rows}; content differs.`);
}
if (differences.length > 30) console.log('Additional differences are recorded in the report.');
console.log(`Report: ${output}`);
