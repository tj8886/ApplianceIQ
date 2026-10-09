// Token stays in a local 0600 file. Checkpoints contain cursors/counts, never source records.
import fs from 'node:fs';
const [tokenPath,statePath,maxBatches='200']=process.argv.slice(2);
if (!tokenPath || !statePath) throw new Error('Usage: run-delta-transfer.mjs TOKEN_FILE CHECKPOINT_FILE [MAX_BATCHES]');
const token=fs.readFileSync(tokenPath,'utf8').trim();
if (!/^[A-Za-z0-9_-]{43}$/.test(token)) throw new Error('Invalid transfer token format');
const state=fs.existsSync(statePath)?JSON.parse(fs.readFileSync(statePath,'utf8')):{};
let batches=0;
for (const table of ['phase7_action_audit','phase7_automation_policies']) {
  state[table]??={cursor:null,received:0,inserted:0,done:false};
  const item=state[table];
  while (!item.done && batches<Number(maxBatches)) {
    const result=await fetch('https://fumwwhyozeouoqscolke.supabase.co/functions/v1/migration-delta-export',{method:'POST',headers:{authorization:`Bearer ${token}`,'content-type':'application/json'},body:JSON.stringify({p_table:table,cursor:item.cursor}),redirect:'error',signal:AbortSignal.timeout(90000)});
    if (!result.ok) throw new Error(`Transfer stopped (${result.status}): ${await result.text()}`);
    const response=await result.json();
    if (!Number.isInteger(response.count) || response.count<0 || response.count>500 || (response.count>0 && (!response.cursor || response.cursor===item.cursor || response.stats?.received!==response.count))) throw new Error('Unexpected relay metadata');
    item.cursor=response.cursor;item.received+=response.count;item.inserted+=response.stats?.inserted??0;item.done=response.count===0;
    fs.writeFileSync(`${statePath}.tmp`,JSON.stringify(state,null,2)+'\n');fs.renameSync(`${statePath}.tmp`,statePath);
    batches++;
    console.log(JSON.stringify({table,...item}));
  }
}
