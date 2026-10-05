#!/usr/bin/env node
// Read-only field comparison for shared rows; outputs column names/counts only.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const {spawnSync} = require('node:child_process');
process.env.PATH = `/Applications/Docker.app/Contents/Resources/bin:${path.join(os.homedir(),'.docker/bin')}:${process.env.PATH}`;
const root = process.argv[2] || path.join(os.homedir(),'applianceiq-database-backups-20261004-114137');
const containers = {Canada:'supabase_db_applianceiq-canada-restore-20261004',US:'supabase_db_applianceiq-restore-rehearsal-20261004'};
function docker(args,input) {
  const r=spawnSync('docker',args,{input,encoding:'utf8',maxBuffer:16*1024*1024});
  if(r.error) throw r.error;
  if(r.status!==0) throw new Error(r.stderr||`Docker exited ${r.status}`);
  return r.stdout;
}
function query(db,sql) {
  return docker(['exec','-i',db,'psql','-X','-U','supabase_admin','-d','postgres','-At','-v','ON_ERROR_STOP=1'],
    `BEGIN READ ONLY; SET LOCAL timezone='UTC'; SET LOCAL bytea_output='hex';\n${sql}\nROLLBACK;`)
    .split('\n').filter(line=>line.startsWith('{')).map(line=>JSON.parse(line));
}
const literal=v=>"'"+v.replaceAll("'","''")+"'";
const identifier=v=>'"'+v.replaceAll('"','""')+'"';
for(const db of Object.values(containers)) {
  if(Object.keys(JSON.parse(docker(['inspect','--format','{{json .NetworkSettings.Networks}}',db]))).length) throw new Error('Rehearsal must be network-isolated');
  if(docker(['exec',db,'psql','-X','-U','supabase_admin','-d','postgres','-Atc','SHOW cron.launch_active_jobs;']).trim()!=='off') throw new Error('Cron launches must stay disabled');
}
const classification=JSON.parse(fs.readFileSync(path.join(root,'staging-delta-classification.json'),'utf8'));
const results=[];
for(const item of classification.tables.filter(t=>t.changed_count>0)) {
  function fields(db,schema) {
    const records=query(db,`SELECT json_build_object('key',jsonb_build_array(${item.primary_key.map(k=>'t.'+identifier(k)).join(',')}),
      'fields',(SELECT jsonb_object_agg(k,md5(v::text)) FROM jsonb_each(to_jsonb(t)) AS cell(k,v)))
      FROM ${identifier(schema)}.${identifier(item.table)} t
      WHERE jsonb_build_array(${item.primary_key.map(k=>'t.'+identifier(k)).join(',')}) IN
      (SELECT value FROM jsonb_array_elements(${literal(JSON.stringify(item.changed_keys))}::jsonb));`);
    if(records.length!==item.changed_count) throw new Error(`Changed-key coverage differs for ${item.table}`);
    return new Map(records.map(row=>[JSON.stringify(row.key),row.fields]));
  }
  const ca=fields(containers.Canada,'public'), us=fields(containers.US,'tj');
  const counts={};
  for(const [key,source] of ca) {
    const target=us.get(key);
    if(!target) throw new Error(`Missing shared key in ${item.table}`);
    for(const column of new Set([...Object.keys(source),...Object.keys(target)])) {
      if(source[column]!==target[column]) counts[column]=(counts[column]||0)+1;
    }
  }
  results.push({table:item.table,changed_rows:item.changed_count,changed_columns:counts});
}
const output=path.join(root,'staging-changed-fields.json');
fs.writeFileSync(output,JSON.stringify({checked_at:new Date().toISOString(),scope:'Column names and changed-row counts; no values',tables:results},null,2)+'\n',{mode:0o600});
for(const item of results) console.log(`${item.table} (${item.changed_rows} changed rows): ${Object.entries(item.changed_columns).map(([field,count])=>`${field}=${count}`).join(', ')}`);
console.log(`Report: ${output}`);
