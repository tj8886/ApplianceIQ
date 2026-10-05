import {readFileSync,writeFileSync,mkdirSync,readdirSync,statSync,copyFileSync,existsSync} from 'node:fs';
import {resolve,join,relative} from 'node:path';
import {execFileSync} from 'node:child_process';
const root=resolve(import.meta.dirname,'../..'),out=process.argv[2];
if(!out)throw Error('Usage: node build-us-app-batch.mjs OUTPUT_DIRECTORY');
const output=resolve(out);if(output===root||output.startsWith(root+'/apps/'))throw Error('Build outside source apps');
const reg=JSON.parse(readFileSync(join(root,'config/app-registry.json'),'utf8'));
const config=JSON.parse(readFileSync(join(root,'config/us-east-client.json'),'utf8'));
const map=JSON.parse(readFileSync(join(root,'docs/migration/us-runtime-api-map.json'),'utf8'));
const tableAccess=JSON.parse(readFileSync(join(root,'docs/migration/app-table-access-map.json'),'utf8'));
const rpc=readFileSync(join(root,'apps/_shared/us-runtime-rpc.mjs'),'utf8').replace(/export /g,'');
const runtime=`(()=>{${rpc}\nconst originalFetch=window.fetch.bind(window);window.fetch=async(input,init)=>{const request=new Request(input,init),url=new URL(request.url);if(url.origin===${JSON.stringify(config.url)}&&url.pathname.startsWith('/rest/v1/')){const match=url.pathname.match(/^\\/rest\\/v1\\/rpc\\/([a-z0-9_]+)$/);if(match){if(!REVIEWED.has(match[1]))return new Response(JSON.stringify({code:'MIGRATION_RPC_NOT_READY',message:'This workflow is not yet available on US East.'}),{status:403,headers:{'Content-Type':'application/json'}});url.pathname='/rest/v1/rpc/tj_runtime_'+match[1];request.headers.set('Accept-Profile','public');request.headers.set('Content-Profile','public');}else{if(url.pathname==='/rest/v1/aiq_products')url.pathname='/rest/v1/aiq_products_app';if(url.pathname==='/rest/v1/aiq_product_versions')url.pathname='/rest/v1/aiq_product_versions_app';request.headers.set('Accept-Profile','tj');request.headers.set('Content-Profile','tj');}return originalFetch(new Request(url,request));}return originalFetch(request);};window.AIQ_US={createClient(factory,url,key,options={}){if(url.replace(/\\/$/,'')!==${JSON.stringify(config.url)})throw Error('Unexpected Supabase destination');const client=factory(url,key,options);const tableClient=client.schema('tj');client.from=(table)=>tableClient.from(table==='aiq_products'?'aiq_products_app':table==='aiq_product_versions'?'aiq_product_versions_app':table);return installUsRuntimeRpc(client);}};})();`;
const report={destination:config.project_ref,published:false,apps:[],remaining_gates:['Remaining reviewed table/view permissions and write policies','Unmigrated RPC/Edge dependencies','Mapped-identity table filters and browser login/handoff checks','Final source data/files delta']};
function files(dir){return readdirSync(dir).flatMap(n=>{const p=join(dir,n);return statSync(p).isDirectory()?files(p):[p]});}
for(const app of [reg.platform,...reg.apps].filter(a=>a.deploy_on_main&&a.source_path)){
 const target=join(output,app.key);execFileSync(process.execPath,[join(root,'scripts/prepare-aiq-deploy.mjs'),app.source_path,app.key,target],{cwd:root,stdio:'pipe'});
 mkdirSync(join(target,'_aiq'),{recursive:true});copyFileSync(join(root,'apps/platform/aiq-module-adapter.js'),join(target,'_aiq/aiq-module-adapter.js'));
 const counts={key:app.key,site_id:app.netlify_site_id,files_changed:0,clients_routed:0,rpcs:new Set(),tables:new Set(),edges:new Set(),legacy_relay_files:[]};
 for(const p of files(target).filter(p=>/\.(html|js|mjs)$/.test(p))){let s=readFileSync(p,'utf8'),before=s;
  for(const m of s.matchAll(/\/rest\/v1\/rpc\/([a-z0-9_]+)/g))counts.rpcs.add(m[1]);
  for(const m of s.matchAll(/\.rpc\(\s*['"]([a-z0-9_]+)['"]/g))counts.rpcs.add(m[1]);
  for(const m of s.matchAll(/\.from\(\s*['"]([a-z0-9_]+)['"]\s*\)/g))counts.tables.add(m[1]);
  for(const m of s.matchAll(/\/functions\/v1\/([a-z0-9-]+)/g))counts.edges.add(m[1]);
  if(app.key==='spec-iq' && p.endsWith('comparison.html'))s=s.replace(',p_product_id:winner.product_id,p_selection_reason:`Best overall score: ${winner.overall_score}`','');
  if(p.endsWith('.html'))s=s.replace(/<script>\(function\(\)\{var h=window\.location\.hash;[\s\S]*?<\/script>\s*/g,'');
  if(p.endsWith('gate.js'))s=s.replace(/    \/\/ 1\. Token relay hash[\s\S]*?    \/\/ 2\./,'    // 2.').replace('or #aiq_relay= token relay hash, or igcc_token from Admin Dashboard','or igcc_token from Admin Dashboard');
  s=s.replaceAll('sb-fumwwhyozeouoqscolke-auth-token','sb-jdxslqmgjsuzoisuhvlc-auth-token');
  s=s.replaceAll('https://fumwwhyozeouoqscolke.supabase.co',config.url).replaceAll('sb_publishable_wiP3ouBdS_Qub9EMIYJK7w_eiltZHKV',config.publishable_key);
  s=s.replaceAll('https://appliance-iq-platform.netlify.app/aiq-module-adapter.js','/_aiq/aiq-module-adapter.js');
  s=s.replace(/\b(supabase\.)?createClient\(/g,(_m,namespace)=>{counts.clients_routed++;return `window.AIQ_US.createClient(${namespace??''}createClient,`;});
  if(p.endsWith('aiq-module-adapter.js')){s=s.replace(/  if\(!h\.relay\)[\s\S]*?  return \{session:data\.session,context:null\};/, '  return {session:null,context:null};');if(s.includes('sb.auth.setSession'))throw Error('Legacy adapter relay remains');}
  if(p.endsWith('.html'))s=s.replace(/<head([^>]*)>/i,'<head$1><script src="/_aiq/us-client.js"></script>');
  if(s.includes('#aiq_relay='))counts.legacy_relay_files.push(relative(target,p));
  if(s!==before){writeFileSync(p,s);counts.files_changed++;}
 }
 writeFileSync(join(target,'_aiq/us-client.js'),runtime);
 for(const p of files(target).filter(p=>/\.(html|js|mjs)$/.test(p)))if(readFileSync(p,'utf8').includes('fumwwhyozeouoqscolke.supabase.co'))throw Error(`Canada endpoint remains: ${p}`);
 report.apps.push({...counts,rpcs:[...counts.rpcs].sort(),tables:[...counts.tables].sort(),edges:[...counts.edges].sort(),pending_table_reads:[...counts.tables].filter(n=>tableAccess.relations.some(r=>r.relname===n&&!r.readable)).sort(),unmatched_literal_names:[...counts.tables].filter(n=>tableAccess.unmatched_literal_names.includes(n)).sort(),unmigrated_rpcs:[...counts.rpcs].filter(n=>!map.functions.includes(n)).sort()});
}
writeFileSync(join(output,'batch-readiness.json'),JSON.stringify(report,null,2));
console.log(JSON.stringify({apps:report.apps.length,files_changed:report.apps.reduce((n,a)=>n+a.files_changed,0),clients_routed:report.apps.reduce((n,a)=>n+a.clients_routed,0),report:join(output,'batch-readiness.json'),published:false}));
