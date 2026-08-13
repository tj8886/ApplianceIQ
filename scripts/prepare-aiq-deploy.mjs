import { cpSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync, readdirSync, statSync } from 'node:fs';
import { resolve, join, basename } from 'node:path';

const [sourcePath, moduleKey, target='.aiq-deploy'] = process.argv.slice(2);
if (!sourcePath || !moduleKey) {
  console.error('Usage: node scripts/prepare-aiq-deploy.mjs <source_path> <module_key> [target]');
  process.exit(1);
}
if (!existsSync(sourcePath)) throw new Error(`Source path does not exist: ${sourcePath}`);
rmSync(target,{recursive:true,force:true});
mkdirSync(target,{recursive:true});
cpSync(sourcePath,target,{recursive:true});

function hardenPlatformLaunchers(text, filePath) {
  if (moduleKey !== 'applianceiq-platform') return text;

  if (basename(filePath) === 'workspace.html') {
    const oldTarget = "target_module_key:key";
    const newTarget = "target_module_key:(m.manifest?.registry_key||key)";
    if (!text.includes(oldTarget)) {
      throw new Error(`Workspace handoff target contract changed unexpectedly in ${filePath}`);
    }
    text = text.replace(oldTarget,newTarget);
  }

  if (basename(filePath) === 'index.html') {
    const oldLauncher = `// Get current session for token relay\n  const { data: { session } } = await sb.auth.getSession();\n  let url = mod.app_url;\n  if (session?.access_token && session?.refresh_token) {\n    const payload = btoa(JSON.stringify({\n      access_token: session.access_token,\n      refresh_token: session.refresh_token,\n      expires_at: session.expires_at\n    }));\n    url += '#aiq_relay=' + payload;\n  }\n  window.open(url, '_blank');`;
    const secureLauncher = `// Phase 2 secure one-time handoff. Never place refresh tokens in URLs.\n  const { data: { session } } = await sb.auth.getSession();\n  if (!session?.access_token) { alert('Your session expired. Please sign in again.'); return; }\n  const { data: ctx } = await sb.rpc('my_platform_context');\n  const targetModuleKey = mod.manifest?.registry_key || key;\n  const handoff = await fetch(SB_URL + '/functions/v1/platform-handoff', {\n    method:'POST',\n    headers:{'Content-Type':'application/json',apikey:SB_KEY,Authorization:'Bearer ' + session.access_token},\n    body:JSON.stringify({\n      action:'issue',\n      organization_id:ctx?.organization_id||null,\n      location_id:ctx?.location_id||null,\n      entity_type:ctx?.entity_type||null,\n      entity_id:ctx?.entity_id||null,\n      entity_label:ctx?.entity_label||null,\n      source_module_key:'applianceiq-platform',\n      target_module_key:targetModuleKey\n    })\n  });\n  if(!handoff.ok){ alert('Unable to create secure app handoff.'); return; }\n  const { ticket } = await handoff.json();\n  window.open(mod.app_url + '#aiq_ticket=' + encodeURIComponent(ticket), '_blank');`;
    if (!text.includes(oldLauncher)) {
      throw new Error(`Legacy Platform module launcher changed unexpectedly in ${filePath}; refusing automatic cleanup`);
    }
    text = text.replace(oldLauncher,secureLauncher);
  }

  return text;
}

function hardenCommandCenterAuth(text, filePath) {
  if (moduleKey !== 'command-center') return text;

  // Transitional rule: preserve the legacy #aiq_relay bootstrap until the
  // secure one-time aiq_ticket path is verified end-to-end on this reconciled build.
  // The shared adapter understands both paths, while Platform launches use aiq_ticket.

  if (basename(filePath) === 'index.html') {
    const oldBoot = `// BOOT\n(async()=>{\n  const{data:{session}}=await sb.auth.getSession();\n  if(session) bootApp();\n})();`;
    const newBoot = `// BOOT — Phase 2 secure handoff aware\nlet ccBootStarted=false;\nasync function bootWhenSessionReady(){\n  if(ccBootStarted) return true;\n  const{data:{session}}=await sb.auth.getSession();\n  if(!session) return false;\n  ccBootStarted=true;\n  await bootApp();\n  return true;\n}\nwindow.addEventListener('aiq:intelligence-ready',()=>{bootWhenSessionReady().catch(console.error)},{once:true});\nbootWhenSessionReady().catch(console.error);`;
    if (!text.includes(oldBoot)) {
      throw new Error(`Command Center auth boot contract changed unexpectedly in ${filePath}; refusing automatic cleanup`);
    }
    text = text.replace(oldBoot,newBoot);
  }
  return text;
}

function injectBeforeBody(text,scriptTag){
  if(text.includes(scriptTag)) return text;
  if(!text.includes('</body>')) throw new Error(`Cannot inject Command Center integration into HTML without </body>`);
  return text.replace('</body>',`${scriptTag}\n</body>`);
}

function integrateCommandCenterBundle(targetRoot){
  if(moduleKey!=='command-center') return;
  const root=resolve(targetRoot);
  const indexPath=join(root,'index.html');
  const governedPath=join(root,'governed-ai-insights.function.js');
  if(!existsSync(indexPath) || !existsSync(governedPath)) throw new Error('Command Center governed AI integration files are missing');

  let indexText=readFileSync(indexPath,'utf8');
  const governed=readFileSync(governedPath,'utf8').trim();
  const pattern=/async function renderAI\(\)\{[\s\S]*?\n\}\n\nfunction renderInsightCards/;
  const replaced=indexText.replace(pattern,`${governed}\n\nfunction renderInsightCards`);
  if(replaced===indexText) throw new Error('Could not locate exactly one legacy Command Center renderAI function');
  if(replaced.includes('ai_budget_predictions')) throw new Error('Legacy ai_budget_predictions operating path remains in prepared Command Center');
  indexText=replaced;
  writeFileSync(indexPath,indexText);

  const nav='<script src="./manager-os-nav.js"></script>';
  for(const filename of ['index.html','manager.html','my-work.html','decisions.html','predictions.html','executive.html','briefs.html']){
    const p=join(root,filename);
    if(!existsSync(p)) throw new Error(`Expected Command Center surface missing: ${filename}`);
    let text=readFileSync(p,'utf8');
    text=injectBeforeBody(text,nav);
    writeFileSync(p,text);
  }

  const managerPath=join(root,'manager.html');
  let managerText=readFileSync(managerPath,'utf8');
  managerText=injectBeforeBody(managerText,'<script type="module" src="./phase6-revenue-intelligence.js"></script>');
  managerText=injectBeforeBody(managerText,'<script type="module" src="./phase7-automation.js"></script>');
  writeFileSync(managerPath,managerText);

  const predictionsPath=join(root,'predictions.html');
  let predictionsText=readFileSync(predictionsPath,'utf8');
  predictionsText=injectBeforeBody(predictionsText,'<script type="module" src="./phase8-forecasting.js"></script>');
  writeFileSync(predictionsPath,predictionsText);
}

function walkHtml(dir, transform) {
  for (const name of readdirSync(dir)) {
    const p=join(dir,name); const st=statSync(p);
    if(st.isDirectory()) walkHtml(p,transform);
    else if(name.endsWith('.html')) {
      let text=readFileSync(p,'utf8');
      text=transform(text,p);
      writeFileSync(p,text);
    }
  }
}

if (moduleKey === 'applianceiq-platform') {
  walkHtml(resolve(target),hardenPlatformLaunchers);
  const platformIndex=readFileSync(join(resolve(target),'index.html'),'utf8');
  const workspace=readFileSync(join(resolve(target),'workspace.html'),'utf8');
  if(platformIndex.includes('#aiq_relay=')) throw new Error('Legacy token relay remains in built Platform shell');
  if(!platformIndex.includes('#aiq_ticket=')) throw new Error('Secure ticket launcher missing from built Platform shell');
  if(!workspace.includes('manifest?.registry_key||key')) throw new Error('Workspace is not using registry_key for secure handoff targets');
} else {
  integrateCommandCenterBundle(target);
  const adapter = `<script type="module" src="https://appliance-iq-platform.netlify.app/aiq-module-adapter.js" data-aiq-module="${moduleKey}"></script>`;
  walkHtml(resolve(target),(text,p)=>{
    text=hardenCommandCenterAuth(text,p);
    if(!text.includes('aiq-module-adapter.js') && text.includes('</body>')) {
      text=text.replace('</body>',`${adapter}\n</body>`);
    }
    if(moduleKey==='command-center') {
      if(basename(p)==='index.html' && !text.includes('aiq:intelligence-ready')) throw new Error('Command Center secure handoff boot listener missing');
      if(!text.includes('aiq-module-adapter.js')) throw new Error(`Shared Platform adapter missing from built Command Center file: ${p}`);
    }
    return text;
  });

  if(moduleKey==='command-center'){
    const ccIndex=readFileSync(join(resolve(target),'index.html'),'utf8');
    const ccManager=readFileSync(join(resolve(target),'manager.html'),'utf8');
    const ccPredictions=readFileSync(join(resolve(target),'predictions.html'),'utf8');
    if(ccIndex.includes('ai_budget_predictions')) throw new Error('Retired AI Insights operating path returned in prepared Command Center');
    if(!ccIndex.includes('phase6_command_center') || !ccIndex.includes('phase7_command_center')) throw new Error('Governed Phase 6-7 intelligence is missing from prepared Command Center');
    if(!ccManager.includes('phase6-revenue-intelligence.js') || !ccManager.includes('phase7-automation.js')) throw new Error('AI Manager Phase 6-7 integrations are missing');
    if(!ccPredictions.includes('phase8-forecasting.js')) throw new Error('Predictive Intelligence Phase 8 integration is missing');
    if(!ccIndex.includes('manager-os-nav.js')) throw new Error('Command Center manager navigation is missing');
  }
}
console.log(`Prepared ${moduleKey} from ${sourcePath} into ${target}`);
