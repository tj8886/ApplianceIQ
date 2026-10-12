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

  if (basename(filePath) === 'index.html' && (!text.includes('handoffUrl(') || text.includes('#aiq_relay='))) {
    throw new Error('Platform must use the secure source launcher');
  }

  return text;
}

function hardenCommandCenterAuth(text, filePath) {
  if (moduleKey !== 'command-center') return text;

  // Retire the pre-Phase-2 browser bootstrap that accepted reusable refresh tokens.
  if (text.includes('#aiq_relay=')) {
    const before = text;
    text = text.replace(/<script>\(function\(\)\{var h=window\.location\.hash;[\s\S]*?<\/script>\s*/m, '');
    if (text === before || text.includes('#aiq_relay=')) {
      throw new Error(`Command Center legacy relay bootstrap could not be removed safely from ${filePath}`);
    }
  }

  // Wait for the injected Platform adapter to redeem aiq_ticket before booting.
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
  if(!platformIndex.includes('handoffUrl(')) throw new Error('Secure ticket launcher missing from built Platform shell');
  if(!workspace.includes('manifest?.registry_key||key')) throw new Error('Workspace is not using registry_key for secure handoff targets');
} else {
  const adapter = `<script type="module" src="https://appliance-iq-platform.netlify.app/aiq-module-adapter.js" data-aiq-module="${moduleKey}"></script>`;
  walkHtml(resolve(target),(text,p)=>{
    text=hardenCommandCenterAuth(text,p);
    if(!text.includes('aiq-module-adapter.js') && text.includes('</body>')) {
      text=text.replace('</body>',`${adapter}\n</body>`);
    }
    if(moduleKey==='command-center') {
      if(text.includes('#aiq_relay=')) throw new Error(`Legacy aiq_relay remains in built Command Center file: ${p}`);
      if(basename(p)==='index.html' && !text.includes('aiq:intelligence-ready')) throw new Error('Command Center secure handoff boot listener missing');
      if(!text.includes('aiq-module-adapter.js')) throw new Error(`Shared Platform adapter missing from built Command Center file: ${p}`);
    }
    return text;
  });
}
console.log(`Prepared ${moduleKey} from ${sourcePath} into ${target}`);