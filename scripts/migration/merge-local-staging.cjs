#!/usr/bin/env node
// Rehearsal only. Copies Canada into US tj; preserves every existing target key.
const fs=require('node:fs'), path=require('node:path'), os=require('node:os');
const {spawnSync}=require('node:child_process');
const ca='supabase_db_applianceiq-canada-restore-20261004';
const us='supabase_db_applianceiq-restore-rehearsal-20261004';
const order=['decision_cases','decision_predictions','field_floor_snapshots','iq_staffing_predictions',
  'mdf_alerts','mdf_mdf_funds','phase6_revenue_opportunities','phase7_automation_policies',
  'phase7_action_runs','phase7_action_audit','platform_connector_alerts','platform_connector_incident_metrics'];
const lit=v=>"'"+String(v).replaceAll("'","''")+"'";
const ident=v=>'"'+v.replaceAll('"','""')+'"';
function hashQuery(schema,table) {
  return `SELECT count(*) AS rows,md5(coalesce(string_agg(h,'' ORDER BY h COLLATE "C"),'')) AS checksum FROM (SELECT md5(to_jsonb(t)::text) h FROM ${ident(schema)}.${ident(table)} t) hashes`;
}
function buildMergeSQL(items) {
  let sql="BEGIN;\nSET LOCAL timezone='UTC';\nSET LOCAL bytea_output='hex';\nSET LOCAL lock_timeout='5s';\n";
  sql+=`LOCK TABLE ${items.map(i=>'tj.'+ident(i.table)).join(',')} IN ACCESS EXCLUSIVE MODE;\n`;
  for(const [index,item] of items.entries()) {
    const target='tj.'+ident(item.table), temp=ident('merge_'+index);
    const columns=item.columns.map(ident).join(',');
    sql+=`DO $guard$ DECLARE n bigint; actual_checksum text; BEGIN
      IF current_setting('cron.launch_active_jobs')<>'off' OR current_setting('session_replication_role')<>'origin' THEN RAISE EXCEPTION 'Unsafe rehearsal settings'; END IF;
      IF EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid=${lit(target)}::regclass AND NOT tgisinternal) THEN RAISE EXCEPTION 'Unexpected target triggers'; END IF;
      ${hashQuery('tj',item.table).replace(' AS rows','').replace(' AS checksum','').replace(' FROM',' INTO n,actual_checksum FROM')};
      IF n<>${item.before.rows} OR actual_checksum<>${lit(item.before.checksum)} THEN RAISE EXCEPTION 'Target changed since audit: ${item.table}'; END IF;
    END $guard$;
    CREATE TEMP TABLE ${temp} (LIKE ${target}) ON COMMIT DROP;
    \\copy ${temp} (${columns}) FROM '/tmp/aiq-merge-${index}.csv' WITH (FORMAT csv)
    DO $source$ DECLARE n bigint; actual_checksum text; BEGIN
      SELECT count(*),md5(coalesce(string_agg(h,'' ORDER BY h COLLATE "C"),'')) INTO n,actual_checksum
      FROM (SELECT md5(to_jsonb(t)::text) h FROM ${temp} t) hashes;
      IF n<>${item.source.rows} OR actual_checksum<>${lit(item.source.checksum)} THEN RAISE EXCEPTION 'Export mismatch: ${item.table}'; END IF;
    END $source$;\n`;
  }
  for(const [index,item] of items.entries()) {
    const target='tj.'+ident(item.table), temp=ident('merge_'+index), columns=item.columns.map(ident).join(',');
    const setters=item.columns.filter(c=>!item.pk.includes(c)).map(c=>`${ident(c)}=EXCLUDED.${ident(c)}`).join(',');
    sql+=`DO $merge$ DECLARE affected bigint; BEGIN
      INSERT INTO ${target} AS destination (${columns}) OVERRIDING SYSTEM VALUE
      SELECT ${columns} FROM ${temp} WHERE true
      ON CONFLICT (${item.pk.map(ident).join(',')}) DO UPDATE SET ${setters}
      WHERE to_jsonb(destination) IS DISTINCT FROM to_jsonb(EXCLUDED);
      GET DIAGNOSTICS affected=ROW_COUNT;
      IF affected<>${item.additions+item.updates} THEN RAISE EXCEPTION 'Unexpected affected row count in ${item.table}: %',affected; END IF;
      IF (SELECT count(*) FROM ${target})<>${item.source.rows+item.extra} THEN RAISE EXCEPTION 'Target count mismatch: ${item.table}'; END IF;
      IF EXISTS(SELECT 1 FROM ${temp} s WHERE NOT EXISTS(SELECT 1 FROM ${target} d
        WHERE ${item.pk.map(k=>`d.${ident(k)}=s.${ident(k)}`).join(' AND ')} AND to_jsonb(d)=to_jsonb(s)))
        THEN RAISE EXCEPTION 'Source rows not preserved: ${item.table}'; END IF;
      RAISE NOTICE '${item.table}: % rows inserted or updated; US-only rows retained',affected;
    END $merge$;\n`;
  }
  return sql+'COMMIT;\n';
}
function main() {
  process.env.PATH=`/Applications/Docker.app/Contents/Resources/bin:${path.join(os.homedir(),'.docker/bin')}:${process.env.PATH}`;
  const root=process.argv[2]||path.join(os.homedir(),'applianceiq-database-backups-20261004-114137');
  function docker(args,input,stdout) {
    const r=spawnSync('docker',args,{input,encoding:'utf8',maxBuffer:16*1024*1024,
      ...(stdout===undefined?{}:{stdio:['pipe',stdout,'pipe']})});
    if(r.error) throw r.error;
    if(r.status!==0) {
      if(stdout!==undefined) fs.writeSync(stdout,r.stderr||'Docker command failed');
      throw new Error((r.stderr||'Docker command failed').split('\n').filter(l=>l.includes('ERROR:')||l.includes('FATAL:')).slice(0,1).join('\n')||'Docker command failed; inspect the local log.');
    }
    return r;
  }
  function query(db,sql) {
    const r=docker(['exec','-i',db,'psql','-X','-U','supabase_admin','-d','postgres','-At','-q','-v','ON_ERROR_STOP=1'],
      `BEGIN READ ONLY; SET LOCAL timezone='UTC'; SET LOCAL bytea_output='hex'; ${sql}; ROLLBACK;`);
    return JSON.parse(r.stdout.trim());
  }
  for(const db of [ca,us]) {
    if(Object.keys(JSON.parse(docker(['inspect','--format','{{json .NetworkSettings.Networks}}',db]).stdout)).length) throw new Error('Both rehearsal databases must remain network-isolated');
    if(docker(['exec',db,'psql','-X','-U','supabase_admin','-d','postgres','-Atc','SHOW cron.launch_active_jobs;']).stdout.trim()!=='off') throw new Error('Cron launches must remain disabled');
  }
  const comparison=JSON.parse(fs.readFileSync(path.join(root,'staging-reconciliation.json'),'utf8'));
  const delta=JSON.parse(fs.readFileSync(path.join(root,'staging-delta-classification.json'),'utf8'));
  const changes=delta.tables;
  if(changes.length!==order.length||changes.some(t=>!order.includes(t.table))) throw new Error('Unexpected table set; review the audit first');
  const items=order.map(table=>{
    const c=comparison.comparisons.find(t=>t.table===table), d=changes.find(t=>t.table===table);
    if(!c||!d||d.primary_key.length!==1) throw new Error('Missing audit metadata');
    return {table,pk:d.primary_key,source:c.canadian,before:c.staged,additions:d.canada_only_count,updates:d.changed_count,extra:d.us_only_count};
  });
  const totals=items.reduce((t,i)=>[t[0]+i.additions,t[1]+i.updates,t[2]+i.extra],[0,0,0]);
  if(JSON.stringify(totals)!=='[404843,116,80]') throw new Error('Delta totals changed; review a fresh plan first');
  const stage=path.join(root,'local-merge-preparation');
  fs.mkdirSync(stage,{mode:0o700});
  for(const [index,item] of items.entries()) {
    console.log(`Preparing ${item.table}...`);
    for(const [db,schema,expected] of [[ca,'public',item.source],[us,'tj',item.before]]) {
      const current=query(db,`SELECT row_to_json(x) FROM (${hashQuery(schema,item.table)}) x`);
      if(current.rows!==expected.rows||current.checksum!==expected.checksum) throw new Error(`${schema}.${item.table} changed since comparison; stop and reassess`);
    }
    const metadata=(db,schema)=>query(db,`SELECT coalesce(json_agg(json_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'generated',a.attgenerated) ORDER BY a.attnum),'[]'::json) FROM pg_attribute a WHERE a.attrelid=${lit(schema+'.'+item.table)}::regclass AND a.attnum>0 AND NOT a.attisdropped`);
    const sourceCols=metadata(ca,'public'), targetCols=metadata(us,'tj');
    if(sourceCols.some(c=>c.generated)||JSON.stringify(sourceCols)!==JSON.stringify(targetCols)) throw new Error(`Column definitions differ in ${item.table}`);
    item.columns=sourceCols.map(c=>c.name);
    const csv=path.join(stage,`table-${index}.csv`), fd=fs.openSync(csv,'wx',0o600);
    try {
      docker(['exec','-i',ca,'psql','-X','-U','supabase_admin','-d','postgres','-q','-v','ON_ERROR_STOP=1'],
        `BEGIN READ ONLY; SET LOCAL timezone='UTC'; SET LOCAL bytea_output='hex'; COPY (SELECT ${item.columns.map(ident).join(',')} FROM public.${ident(item.table)}) TO STDOUT WITH (FORMAT csv); ROLLBACK;`,fd);
    } finally {fs.closeSync(fd);}
    docker(['cp',csv,`${us}:/tmp/aiq-merge-${index}.csv`]);
  }
  const sql=buildMergeSQL(items), sqlPath=path.join(stage,'merge.sql');
  fs.writeFileSync(sqlPath,sql,{mode:0o600});
  docker(['cp',sqlPath,`${us}:/tmp/aiq-local-merge.sql`]);
  console.log('Merging locally in one transaction, with foreign keys enforced.');
  const logPath=path.join(stage,'merge.log'), log=fs.openSync(logPath,'wx',0o600);
  let result;
  try {result=docker(['exec',us,'psql','-X','-U','supabase_admin','-d','postgres','-v','ON_ERROR_STOP=1','--file','/tmp/aiq-local-merge.sql'],undefined,log);}
  finally {fs.closeSync(log);}
  fs.appendFileSync(logPath,result.stderr||'');
  console.log(result.stderr.trim());
  // Repair the identity sequence after commit; never move it backwards.
  docker(['exec','-i',us,'psql','-X','-U','supabase_admin','-d','postgres','-v','ON_ERROR_STOP=1'],
    `DO $sequence$ DECLARE seq text; previous bigint; maximum bigint; BEGIN
     seq:=pg_get_serial_sequence('tj.phase7_action_audit','id');
     IF seq IS NOT NULL THEN
       EXECUTE format('SELECT last_value FROM %s',seq) INTO previous;
       SELECT max(id) INTO maximum FROM tj.phase7_action_audit;
       IF maximum IS NOT NULL THEN PERFORM setval(seq::regclass,greatest(previous,maximum),true); END IF;
     END IF;
     END $sequence$;`);
  console.log('Local merge completed: 404843 inserted; 116 updated; 80 US-only records preserved.');
  console.log(`Preparation and log: ${stage}`);
  console.log('Production and the Canadian rehearsal database were not changed.');
}
module.exports={buildMergeSQL,hashQuery};
if(require.main===module) {try{main();}catch(error){console.error(error.message);process.exitCode=1;}}
