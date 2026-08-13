import { cpSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync, readdirSync, statSync } from 'node:fs';
import { resolve, join } from 'node:path';

const [sourcePath, moduleKey, target='.aiq-deploy'] = process.argv.slice(2);
if (!sourcePath || !moduleKey) {
  console.error('Usage: node scripts/prepare-aiq-deploy.mjs <source_path> <module_key> [target]');
  process.exit(1);
}
if (!existsSync(sourcePath)) throw new Error(`Source path does not exist: ${sourcePath}`);
rmSync(target,{recursive:true,force:true});
mkdirSync(target,{recursive:true});
cpSync(sourcePath,target,{recursive:true});

if (moduleKey !== 'applianceiq-platform') {
  const adapter = `<script type="module" src="https://appliance-iq-platform.netlify.app/aiq-module-adapter.js" data-aiq-module="${moduleKey}"></script>`;
  const walk = dir => {
    for (const name of readdirSync(dir)) {
      const p=join(dir,name); const st=statSync(p);
      if(st.isDirectory()) walk(p);
      else if(name.endsWith('.html')) {
        let text=readFileSync(p,'utf8');
        if(text.includes('aiq-module-adapter.js')) continue;
        if(text.includes('</body>')) {
          text=text.replace('</body>',`${adapter}\n</body>`);
          writeFileSync(p,text);
        }
      }
    }
  };
  walk(resolve(target));
}
console.log(`Prepared ${moduleKey} from ${sourcePath} into ${target}`);
