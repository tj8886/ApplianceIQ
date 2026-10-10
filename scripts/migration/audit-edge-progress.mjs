import {readFileSync,writeFileSync,existsSync} from 'node:fs';
import {resolve} from 'node:path';
const root=resolve(import.meta.dirname,'../..');
const read=path=>JSON.parse(readFileSync(resolve(root,path),'utf8'));
const inventory=read('docs/migration/live-edge-inventory.json');
const manifest=read('docs/migration/edge-transfer-manifest.json');
const apps=read('docs/migration/app-edge-cutover-dependencies.json');
for(const functions of [inventory.source,inventory.destination,manifest.snapshots]){
  const slugs=functions.map(f=>f.slug);if(new Set(slugs).size!==slugs.length)throw Error('Duplicate function slug');
}
const source=new Map(inventory.source.map(f=>[f.slug,f])),destination=new Map(inventory.destination.map(f=>[f.slug,f]));
const snapshots=manifest.snapshots.map(snapshot=>{
  const live=source.get(snapshot.slug),target=destination.get(snapshot.slug);
  return {slug:snapshot.slug,source_snapshot_version:snapshot.source_version,live_source_version:live?.version??null,
    source_snapshot_drift:!live||live.version!==snapshot.source_version||live.hash!==snapshot.source_hash,
    destination_version:target?.version??null,destination_jwt:target?.verify_jwt??null,
    deployment:target?.status==='ACTIVE'?'deployed':snapshot.slug==='deploy-host'?'source-retired':'not-deployed',
    repo_entrypoint:existsSync(resolve(root,'supabase/functions',snapshot.slug,'index.ts')),
    recorded_validation:snapshot.deployment_status,
    configuration_blocker:snapshot.slug==='scraper-proxy'?'SCRAPER_PROXY_KEY absent in migrated configuration; endpoint denies use':null};
});
const appNames=[...new Set([...apps.ready_literal_app_dependencies,...apps.pending_literal_app_dependencies])].sort();
const report={captured_at:inventory.captured_at,source_project:inventory.source_project,destination_project:inventory.destination_project,
  live_source_function_count:source.size,live_destination_function_count:destination.size,source_snapshot_count:snapshots.length,
  snapshots_deployed:snapshots.filter(f=>f.deployment==='deployed').length,snapshots_retired:snapshots.filter(f=>f.deployment==='source-retired').length,
  snapshots_not_deployed:snapshots.filter(f=>f.deployment==='not-deployed').length,
  source_snapshot_drift:snapshots.filter(f=>f.source_snapshot_drift).map(f=>f.slug),
  literal_app_dependencies:appNames.map(slug=>({slug,live_deployed:destination.get(slug)?.status==='ACTIVE',
    recorded_ready:apps.ready_literal_app_dependencies.includes(slug)})),
  priority_queue:snapshots.filter(f=>f.deployment==='not-deployed').sort((a,b)=>Number(appNames.includes(b.slug))-Number(appNames.includes(a.slug))||a.slug.localeCompare(b.slug)).map(f=>({slug:f.slug,literal_app_dependency:appNames.includes(f.slug)})),
  snapshots,
  limits:['Deployed presence is not workflow readiness, credential availability or provider/browser verification.',
    'Snapshot drift compares source metadata only; final database and Storage deltas remain separate.',
    'Older migrated/pending counters are historical and may be stale.',
    'No live schedules, hosted app cutover or source retirement are performed by this audit.']};
writeFileSync(resolve(root,'docs/migration/live-edge-progress.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({deployed:report.snapshots_deployed,retired:report.snapshots_retired,not_deployed:report.snapshots_not_deployed,
  source_snapshot_drift:report.source_snapshot_drift.length,next:report.priority_queue.slice(0,12)}));
