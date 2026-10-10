import {readFileSync,readdirSync,statSync} from 'node:fs';
import {resolve,dirname,join} from 'node:path';
const root=resolve('supabase/functions');
const visited=new Set();
function checkFile(path){
 if(visited.has(path))return;visited.add(path);
 if(!path.startsWith(root+'/')||!statSync(path).isFile())throw Error('Missing local Edge module: '+path);
 const source=readFileSync(path,'utf8');
 for(const m of source.matchAll(/(?:from\s*|import\s*)["'](\.[^"']+)["']/g))checkFile(resolve(dirname(path),m[1]));
}
let count=0;
for(const name of readdirSync(root).filter(n=>!n.startsWith('_'))){const path=join(root,name,'index.ts'),source=readFileSync(path,'utf8');if(source.length<80||!/(?:Deno\.serve|\bserve)\s*\(/.test(source))throw Error('Missing Edge HTTP entrypoint: '+name);if(/placeholder|simplified|TODO.full.source|structural.reconstruction|source.pending|not.implemented|not.yet.restored|framework.only/i.test(source))throw Error('Incomplete Edge entrypoint marker: '+name);checkFile(path);count++;}
console.log(`${count} Edge entrypoints and ${visited.size} local modules present; compact handlers and retired 410 endpoints supported`);
