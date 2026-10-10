#!/usr/bin/env node
'use strict';
// Owner-side transfer: fresh Canadian public export -> live US East tj.
// Uses existing CLI authentication; never evaluates the CLI dry-run script.
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const crypto = require('node:crypto'), {spawnSync} = require('node:child_process');
const REF = 'jdxslqmgjsuzoisuhvlc';
const CA = 'supabase_db_applianceiq-canada-restore-20261004';
const IMAGE = 'public.ecr.aws/supabase/postgres:17.11.0.002';
const ORDER = ['decision_cases','decision_predictions','field_floor_snapshots','iq_staffing_predictions',
  'mdf_alerts','mdf_mdf_funds','phase6_revenue_opportunities','phase7_automation_policies',
  'phase7_action_runs','phase7_action_audit','platform_connector_alerts','platform_connector_incident_metrics'];
const qi = s => '"'+s.replaceAll('"','""')+'"';
const ql = s => "'"+String(s).replaceAll("'","''")+"'";
const hashSQL = (schema,table) => `SELECT count(*) AS rows,md5(coalesce(string_agg(h,'' ORDER BY h COLLATE "C"),'')) AS checksum FROM (SELECT md5(to_jsonb(t)::text) h FROM ${qi(schema)}.${qi(table)} t) hashes`;
function parseConnection(script) {
  const result = {};
  for (const key of ['PGHOST','PGPORT','PGUSER','PGPASSWORD','PGDATABASE']) {
    const matches = [...script.matchAll(new RegExp('^export '+key+'="(.*)"\\r?$','gm'))];
    if (matches.length !== 1) throw new Error('Cannot safely read CLI connection settings');
    result[key] = matches[0][1].replaceAll('\\"','"');
    if (!result[key] || /[\r\n\0]/.test(result[key])) throw new Error('Invalid CLI connection setting');
  }
  if (!(result.PGHOST === `db.${REF}.supabase.co` || /^[a-z0-9.-]+\.pooler\.supabase\.com$/.test(result.PGHOST)) || result.PGPORT !== '5432' || result.PGDATABASE !== 'postgres')
    throw new Error('Unexpected destination endpoint');
  return {...result, PGSSLMODE:'require', PGGSSENCMODE:'disable', PGCONNECT_TIMEOUT:'30', PGOPTIONS:'', PGAPPNAME:'applianceiq-us-east-consolidation'};
}
function assertDestination(identity, connection) {
  if (connection.PGSSLMODE!=='require' || connection.PGGSSENCMODE!=='disable') throw new Error('Client TLS requirement is missing');
  // pg_stat_ssl observes the pooler-to-Postgres leg, not the client-to-pooler leg.
  // libpq's required SSL mode enforces encryption of the client connection.
  const problems=[];
  if (identity.role!=='postgres') problems.push('database role is not postgres');
  if (identity.tj!==true) problems.push('tj.products is missing');
  if (identity.archive!==true) problems.push('tj.source_auth_users is missing');
  if(problems.length) throw new Error('Destination checks failed: '+problems.join('; '));
}
function safeFailure(stderr, secrets=[]) {
  // Report only a known PostgreSQL error category, never server detail or values.
  let line = (stderr.match(/(?:ERROR|FATAL):\s+([^\n]+)/)||[])[1] || '';
  for (const secret of secrets.filter(Boolean)) line=line.replaceAll(secret,'[redacted]');
  const code = (line.match(/^([0-9A-Z]{5}):/)||[])[1];
  const categories = ['permission denied','must be owner','cannot set parameter','cannot set role',
    'cannot execute','unrecognized configuration parameter','invalid value for parameter',
    'relation .* does not exist','function .* does not exist','column .* does not exist',
    'password authentication failed','no pg_hba.conf entry','SSL connection',
    'Destination changed','Source file mismatch','Unexpected target trigger','Unexpected merge count',
    'Source coverage failed','Foreign keys must remain'];
  if (categories.some(pattern=>new RegExp(pattern,'i').test(line))) {
    return line.replace(/"(?:[^"\\]|\\.)*"|'(?:[^']|'')*'/g,'[quoted value]').slice(0,240);
  }
  return code ? `PostgreSQL SQLSTATE ${code}` : 'Database client failed; no server details were exposed';
}
function scanSQL(schema,tables) {
  return `BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL timezone='UTC'; SET LOCAL bytea_output='hex'; SET LOCAL statement_timeout=0;
DO $scan$ DECLARE name text; n bigint; h text; BEGIN
FOREACH name IN ARRAY ARRAY[${tables.map(ql).join(',')}] LOOP
  IF to_regclass(format('%I.%I',${ql(schema)},name)) IS NULL THEN RAISE EXCEPTION 'Missing table: %',name; END IF;
  EXECUTE format('SELECT count(*),md5(coalesce(string_agg(h,%L ORDER BY h COLLATE "C"),%L)) FROM (SELECT md5(to_jsonb(t)::text) h FROM %I.%I t) x','','',${ql(schema)},name) INTO n,h;
  RAISE NOTICE 'RECON:%',json_build_object('table',name,'rows',n,'checksum',h);
END LOOP; END $scan$; ROLLBACK;`;
}
function mergeSQL(items) {
  let sql = `BEGIN; SET LOCAL timezone='UTC'; SET LOCAL bytea_output='hex'; SET LOCAL lock_timeout='5s'; SET LOCAL statement_timeout=0;
LOCK TABLE ${items.map(i=>'tj.'+qi(i.table)).join(',')} IN ACCESS EXCLUSIVE MODE;
CREATE TEMP TABLE merge_results(table_name text,inserted bigint,updated bigint,preserved bigint) ON COMMIT DROP;
`;
  for (const [index,i] of items.entries()) {
    const target='tj.'+qi(i.table), temp=qi('merge_'+index);
    sql += `DO $guard$ DECLARE n bigint; actual_checksum text; BEGIN
IF current_setting('session_replication_role')<>'origin' THEN RAISE EXCEPTION 'Foreign keys must remain enforced'; END IF;
IF EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid=${ql(target)}::regclass AND NOT tgisinternal) THEN RAISE EXCEPTION 'Unexpected target trigger: ${i.table}'; END IF;
${hashSQL('tj',i.table).replace(' AS rows','').replace(' AS checksum','').replace(' FROM',' INTO n,actual_checksum FROM')};
IF n<>${i.before.rows} OR actual_checksum<>${ql(i.before.checksum)} THEN RAISE EXCEPTION 'Destination changed since preflight: ${i.table}'; END IF;
END $guard$;
CREATE TEMP TABLE ${temp} (LIKE ${target}) ON COMMIT DROP;
\\copy ${temp} (${i.columns.map(qi).join(',')}) FROM '/input/table-${index}.csv' WITH (FORMAT csv)
DO $source$ DECLARE n bigint; actual_checksum text; BEGIN
SELECT count(*),md5(coalesce(string_agg(h,'' ORDER BY h COLLATE "C"),'')) INTO n,actual_checksum FROM (SELECT md5(to_jsonb(t)::text) h FROM ${temp} t) x;
IF n<>${i.source.rows} OR actual_checksum<>${ql(i.source.checksum)} THEN RAISE EXCEPTION 'Source file mismatch: ${i.table}'; END IF;
END $source$;
`;
  }
  for (const [index,i] of items.entries()) {
    const target='tj.'+qi(i.table), temp=qi('merge_'+index), join=i.pk.map(k=>`d.${qi(k)}=s.${qi(k)}`).join(' AND ');
    sql += `DO $merge$ DECLARE additions bigint; updates bigint; extras bigint; affected bigint; BEGIN
SELECT count(*) INTO additions FROM ${temp} s WHERE NOT EXISTS(SELECT 1 FROM ${target} d WHERE ${join});
SELECT count(*) INTO updates FROM ${temp} s JOIN ${target} d ON ${join} WHERE to_jsonb(d) IS DISTINCT FROM to_jsonb(s);
SELECT count(*) INTO extras FROM ${target} d WHERE NOT EXISTS(SELECT 1 FROM ${temp} s WHERE ${join});
INSERT INTO ${target} AS destination (${i.columns.map(qi).join(',')}) OVERRIDING SYSTEM VALUE
SELECT ${i.columns.map(qi).join(',')} FROM ${temp} WHERE true
ON CONFLICT (${i.pk.map(qi).join(',')}) DO UPDATE SET ${i.columns.filter(c=>!i.pk.includes(c)).map(c=>`${qi(c)}=EXCLUDED.${qi(c)}`).join(',')}
WHERE to_jsonb(destination) IS DISTINCT FROM to_jsonb(EXCLUDED);
GET DIAGNOSTICS affected=ROW_COUNT;
IF affected<>additions+updates OR (SELECT count(*) FROM ${target})<>${i.source.rows}+extras THEN RAISE EXCEPTION 'Unexpected merge count: ${i.table}'; END IF;
IF EXISTS(SELECT 1 FROM ${temp} s WHERE NOT EXISTS(SELECT 1 FROM ${target} d WHERE ${join} AND to_jsonb(d)=to_jsonb(s))) THEN RAISE EXCEPTION 'Source coverage failed: ${i.table}'; END IF;
INSERT INTO merge_results VALUES(${ql(i.table)},additions,updates,extras);
END $merge$;
`;
  }
  // Sequences are nontransactional; advance only after all row assertions pass.
  sql += `SET CONSTRAINTS ALL IMMEDIATE;
DO $seq$ DECLARE seq text; previous bigint; maximum bigint; BEGIN
seq:=pg_get_serial_sequence('tj.phase7_action_audit','id');
IF seq IS NOT NULL THEN EXECUTE format('SELECT last_value FROM %s',seq) INTO previous;
SELECT max(id) INTO maximum FROM tj.phase7_action_audit;
IF maximum IS NOT NULL THEN PERFORM setval(seq::regclass,greatest(previous,maximum),true); END IF; END IF; END $seq$;
SELECT coalesce(json_agg(row_to_json(r)),'[]'::json) FROM merge_results r;
COMMIT;
`;
  return sql;
}
const FOREIGN_KEY_CHECK = "BEGIN;\nSET TRANSACTION READ ONLY;\nDO $check$\nDECLARE\n  fk record;\n  nonnull_all text;\n  nonnull_any text;\n  null_any text;\n  equality_sql text;\n  predicate_sql text;\n  broken boolean;\n  checked integer := 0;\n  failures integer := 0;\nBEGIN\n  FOR fk IN\n    SELECT c.* FROM pg_constraint c\n    JOIN pg_namespace n ON n.oid=c.connamespace\n    WHERE c.contype='f' AND c.conparentid=0\n      AND n.nspname IN ('public','tj')\n    ORDER BY c.conrelid,c.conname\n  LOOP\n    SELECT\n      string_agg(format('child.%I IS NOT NULL', a.attname),' AND ' ORDER BY k.position),\n      string_agg(format('child.%I IS NOT NULL', a.attname),' OR ' ORDER BY k.position),\n      string_agg(format('child.%I IS NULL', a.attname),' OR ' ORDER BY k.position),\n      string_agg(format('parent.%I OPERATOR(%I.%s) child.%I',\n        b.attname,onsp.nspname,op.oprname,a.attname),' AND ' ORDER BY k.position)\n    INTO nonnull_all,nonnull_any,null_any,equality_sql\n    FROM generate_subscripts(fk.conkey,1) AS k(position)\n    JOIN pg_attribute a ON a.attrelid=fk.conrelid AND a.attnum=fk.conkey[k.position]\n    JOIN pg_attribute b ON b.attrelid=fk.confrelid AND b.attnum=fk.confkey[k.position]\n    JOIN pg_operator op ON op.oid=fk.conpfeqop[k.position]\n    JOIN pg_namespace onsp ON onsp.oid=op.oprnamespace;\n\n    predicate_sql := format('(%s) AND NOT EXISTS (SELECT 1 FROM %s parent WHERE %s)',\n      nonnull_all,fk.confrelid::regclass,equality_sql);\n    IF fk.confmatchtype='f' THEN\n      predicate_sql := format('(%s) OR ((%s) AND (%s))',\n        predicate_sql,nonnull_any,null_any);\n    ELSIF fk.confmatchtype<>'s' THEN\n      RAISE EXCEPTION 'Unsupported foreign-key match type: %',fk.conname;\n    END IF;\n\n    EXECUTE format('SELECT EXISTS (SELECT 1 FROM %s child WHERE %s)',\n      fk.conrelid::regclass,predicate_sql) INTO broken;\n    checked := checked+1;\n    IF broken THEN\n      failures := failures+1;\n      RAISE NOTICE 'BROKEN REFERENCE: %.%',fk.conrelid::regclass,fk.conname;\n    END IF;\n    IF checked % 100=0 THEN\n      RAISE NOTICE 'Checked % foreign keys...',checked;\n    END IF;\n  END LOOP;\n  RAISE NOTICE 'Foreign-key check complete: % checked, % failures.',checked,failures;\n  IF failures>0 THEN\n    RAISE EXCEPTION 'Restore integrity check failed; investigate % constraints.',failures;\n  END IF;\nEND\n$check$;\nROLLBACK;\n";
function main() {
  process.umask(0o077);
  process.env.PATH=`/Applications/Docker.app/Contents/Resources/bin:${path.join(os.homedir(),'.docker/bin')}:${process.env.PATH}`;
  const root=path.resolve(process.argv[2]||path.join(os.homedir(),'applianceiq-database-backups-20261004-114137'));
  const sourceFile=path.join(root,'Canada','data.live-20261004.sql');
  if (!fs.existsSync(sourceFile) || fs.statSync(sourceFile).size<1000000) throw new Error('Fresh Canada export not found');
  fs.chmodSync(sourceFile,0o600);
  const stage=path.join(root,'live-us-east-'+new Date().toISOString().replace(/[:.]/g,'-'));
  fs.mkdirSync(stage,{mode:0o700});
  let connection;
  function run(command,args,input,fd,extraEnv={}) {
    const r=spawnSync(command,args,{input,encoding:'utf8',maxBuffer:32*1024*1024,env:{...process.env,...extraEnv},...(fd===undefined?{}:{stdio:['pipe',fd,'pipe']})});
    if(r.error) throw new Error(`${command} could not start: ${r.error.code}`);
    if(r.status!==0) {
      // No arbitrary CLI stdout/stderr: dry-run output can contain a password;
      // PostgreSQL error detail can contain customer records.
      const diagnostic=command==='docker' ? safeFailure(r.stderr||'',[connection?.PGPASSWORD]) : 'CLI command failed; credential-bearing output withheld';
      throw new Error(`${command} failed (exit ${r.status}): ${diagnostic}. Stopped without continuing.`);
    }
    return r;
  }
  const docker=(args,input,fd,env)=>run('docker',args,input,fd,env);
  const cli=args=>run('npx',['--yes','supabase@2.119.0',...args,'--agent','no'],undefined);
  function local(sql,fd) {return docker(['exec','-i',CA,'psql','-X','-U','supabase_admin','-d','postgres','-Atq','-v','ON_ERROR_STOP=1'],sql,fd);}
  function remote(sql) {
    const args=['run','--rm','-i','--mount',`type=bind,source=${stage},target=/input,readonly`];
    for(const key of Object.keys(connection)) args.push('-e',key);
    args.push('--entrypoint','psql',IMAGE,'-X','-Atq','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose');
    // Match CLI/pg_dump: authenticate first, then explicitly select postgres.
    // Session role options in the startup packet are not used.
    return docker(args,'SET SESSION ROLE postgres;\n'+sql,undefined,connection);
  }
  function json(query,remoteDB=false) {
    return JSON.parse((remoteDB?remote:local)(`BEGIN READ ONLY; SET LOCAL timezone='UTC'; SET LOCAL bytea_output='hex'; ${query}; ROLLBACK;`).stdout.trim());
  }
  function scan(schema,tables,remoteDB=false) {
    console.log(`Comparing ${tables.length} ${schema} tables${remoteDB?' in live US East':''}...`);
    const r=(remoteDB?remote:local)(scanSQL(schema,tables));
    const rows=r.stderr.split('\n').filter(l=>l.includes('RECON:')).map(l=>JSON.parse(l.slice(l.indexOf('RECON:')+6)));
    if(rows.length!==tables.length) throw new Error('Incomplete comparison');
    return new Map(rows.map(r=>[r.table,r]));
  }
  const writeJSON=(name,data)=>fs.writeFileSync(path.join(stage,name),JSON.stringify(data,null,2)+'\n',{mode:0o600});
  console.log('Destination: live US East jdxslqmgjsuzoisuhvlc, schema tj.');
  console.log('Connecting with your existing Supabase CLI login...');
  connection=parseConnection(cli(['db','dump','--project-ref',REF,'--dry-run']).stdout);
  const identity=json(`SELECT json_build_object('role',current_user,'ssl',coalesce((SELECT ssl FROM pg_stat_ssl WHERE pid=pg_backend_pid()),false),'tj',to_regclass('tj.products') IS NOT NULL,'archive',to_regclass('tj.source_auth_users') IS NOT NULL)`,true);
  assertDestination(identity,connection);
  console.log('Live US East connection and destination checks passed.');
  if(Object.keys(JSON.parse(docker(['inspect','--format','{{json .NetworkSettings.Networks}}',CA]).stdout)).length) throw new Error('Canada export reader must remain network-isolated');
  if(local('SHOW cron.launch_active_jobs;').stdout.trim()!=='off') throw new Error('Local reader cron must remain off');
  const inventorySQL=schema=>`SELECT coalesce(json_agg(c.relname ORDER BY c.relname),'[]'::json) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname=${ql(schema)} AND c.relkind IN ('r','p')`;
  const tables=json(inventorySQL('public'));
  if(tables.length!==542) throw new Error('Unexpected Canadian table inventory');
  // Prevent TRUNCATE CASCADE reaching auth/storage in the local export reader.
  const outside=json(`SELECT count(*) FROM pg_constraint c JOIN pg_class child ON child.oid=c.conrelid JOIN pg_namespace cn ON cn.oid=child.relnamespace JOIN pg_class parent ON parent.oid=c.confrelid JOIN pg_namespace pn ON pn.oid=parent.relnamespace WHERE c.contype='f' AND pn.nspname='public' AND cn.nspname<>'public'`);
  if(outside!==0) throw new Error('Local public tables have external dependents; stopped before refreshing');
  console.log('Reading the fresh Canada export using the existing isolated local database...');
  docker(['cp',sourceFile,`${CA}:/tmp/canada-live-data.sql`]);
  local(`BEGIN; SET LOCAL session_replication_role=replica;
TRUNCATE ${tables.map(t=>'public.'+qi(t)).join(',')} RESTART IDENTITY CASCADE;
\\i /tmp/canada-live-data.sql
COMMIT;`);
  // Credentials stay in process memory and inherited client environment only.
  const targetTables=json(inventorySQL('tj'),true);
  if(tables.some(t=>!targetTables.includes(t))) throw new Error('Destination is missing Canadian tables');
  const source=scan('public',tables), before=scan('tj',tables,true);
  const changed=tables.filter(t=>source.get(t).rows!==before.get(t).rows||source.get(t).checksum!==before.get(t).checksum);
  writeJSON('preflight.json',{destination:REF,source_export:sourceFile,comparisons:tables.map(t=>({table:t,source:source.get(t),destination:before.get(t)}))});
  if(changed.some(t=>!ORDER.includes(t))) throw new Error('Fresh changes include an unreviewed table. Preflight report saved; production records were not changed.');
  if(!changed.length) {console.log('All 542 source tables already match live tj. No transfer needed.');return;}
  console.log(`Saving a fresh live tj backup before transferring ${changed.length} tables...`);
  for(const [name,flags] of [['premerge-schema.sql',['--schema','tj,tj_private']],['premerge-data.sql',['--schema','tj','--data-only','--use-copy']]]) {
    const file=path.join(stage,name);
    cli(['db','dump','--project-ref',REF,...flags,'--file',file]);
    fs.chmodSync(file,0o600);
    if(fs.statSync(file).size<1000) throw new Error('Fresh destination backup is unexpectedly small');
  }
  // Dump commands may rotate the ephemeral login role; acquire its latest value.
  connection=parseConnection(cli(['db','dump','--project-ref',REF,'--dry-run']).stdout);
  const items=[];
  for(const table of ORDER.filter(t=>changed.includes(t))) {
    console.log(`Preparing ${table}...`);
    const colsSQL=schema=>`SELECT json_agg(json_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'generated',a.attgenerated) ORDER BY a.attnum) FROM pg_attribute a WHERE a.attrelid=${ql(schema+'.'+table)}::regclass AND a.attnum>0 AND NOT a.attisdropped`;
    const sourceCols=json(colsSQL('public')), targetCols=json(colsSQL('tj'),true);
    if(sourceCols.some(c=>c.generated)||JSON.stringify(sourceCols)!==JSON.stringify(targetCols)) throw new Error('Column definitions differ: '+table);
    const pkSQL=schema=>`SELECT coalesce(json_agg(a.attname ORDER BY k.ord),'[]'::json) FROM pg_constraint c CROSS JOIN LATERAL unnest(c.conkey) WITH ORDINALITY k(num,ord) JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k.num WHERE c.conrelid=${ql(schema+'.'+table)}::regclass AND c.contype='p'`;
    const pk=json(pkSQL('public'));
    if(!pk.length||JSON.stringify(pk)!==JSON.stringify(json(pkSQL('tj'),true))) throw new Error('Primary keys differ: '+table);
    const item={table,pk,columns:sourceCols.map(c=>c.name),source:source.get(table),before:before.get(table)};
    const fd=fs.openSync(path.join(stage,`table-${items.length}.csv`),'wx',0o600);
    try {local(`BEGIN READ ONLY; SET LOCAL timezone='UTC'; SET LOCAL bytea_output='hex'; COPY (SELECT ${item.columns.map(qi).join(',')} FROM public.${qi(table)}) TO STDOUT WITH (FORMAT csv); ROLLBACK;`,fd);} finally {fs.closeSync(fd);}
    items.push(item);
  }
  const sql=mergeSQL(items);
  fs.writeFileSync(path.join(stage,'merge.sql'),sql,{mode:0o600});
  // Hash large files without loading them into memory.
  const sums=[];
  for(const name of fs.readdirSync(stage).filter(n=>/\.(sql|csv)$/.test(n))) {
    const fd=fs.openSync(path.join(stage,name),'r'), digest=crypto.createHash('sha256'), buf=Buffer.alloc(1024*1024);
    try {let n; while((n=fs.readSync(fd,buf,0,buf.length,null))>0) digest.update(buf.subarray(0,n));} finally {fs.closeSync(fd);}
    sums.push(digest.digest('hex')+'  '+name);
  }
  fs.writeFileSync(path.join(stage,'SHA256SUMS'),sums.join('\n')+'\n',{mode:0o600});
  console.log('Transferring into live US East tj in one transaction; foreign keys remain enforced...');
  const result=remote(sql);
  const merged=JSON.parse(result.stdout.trim());
  writeJSON('merge-results.json',merged);
  console.log('Live transfer committed. Checking final table contents and references...');
  const after=scan('tj',tables,true);
  const untouched=tables.filter(t=>!changed.includes(t));
  if(untouched.some(t=>before.get(t).rows!==after.get(t).rows||before.get(t).checksum!==after.get(t).checksum)) throw new Error('Transfer committed, but an untouched table changed concurrently. Results saved; review before cutover.');
  for(const item of items) {
    const summary=merged.find(r=>r.table_name===item.table), actual=after.get(item.table);
    if(!summary || actual.rows!==item.source.rows+Number(summary.preserved) || (Number(summary.preserved)===0 && actual.checksum!==item.source.checksum)) throw new Error('Transfer committed, but post-transfer content verification failed: '+item.table);
  }
  const fk=remote(FOREIGN_KEY_CHECK);
  fs.writeFileSync(path.join(stage,'foreign-key-check.log'),fk.stderr,{mode:0o600});
  console.log(fk.stderr.split('\n').find(l=>l.includes('Foreign-key check complete:'))||'Foreign-key verification passed.');
  writeJSON('postmerge.json',{committed:true,destination:REF,tables_checked:tables.length,results:merged,table_counts:tables.map(t=>after.get(t))});
  const totals=merged.reduce((a,r)=>({inserted:a.inserted+Number(r.inserted),updated:a.updated+Number(r.updated),preserved:a.preserved+Number(r.preserved)}),{inserted:0,updated:0,preserved:0});
  console.log(`LIVE transfer committed: ${totals.inserted} inserted; ${totals.updated} updated; ${totals.preserved} US-only records preserved in transferred tables.`);
  console.log(`Fresh backup and transfer report: ${stage}`);
  console.log('This completes the staged data transfer. App login, runtime functions, and app cutover remain separate steps.');
}
module.exports={parseConnection,assertDestination,safeFailure,mergeSQL,scanSQL,hashSQL,REF};
if(require.main===module) {try {main();} catch(e) {console.error(e.message);console.error('Do not rerun blindly if a LIVE transfer committed message appeared; share the last output first.');process.exitCode=1;}}
