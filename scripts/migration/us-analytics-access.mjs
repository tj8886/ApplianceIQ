export function summarizeCachedRequests(turns) {
  const groups=new Map();
  for(const turn of turns){
    if(turn?.role!=='assistant'||turn.metadata?.tier!=='cached')continue;
    const persona=typeof turn.persona_name==='string'?turn.persona_name.slice(0,120):'Unknown';
    const type=typeof turn.metadata.deterministic_type==='string'?turn.metadata.deterministic_type.slice(0,80):'Cached';
    const key=JSON.stringify([persona,type]);
    const row=groups.get(key)||{persona_name:persona,deterministic_type:type,request_count:0};
    row.request_count++;groups.set(key,row);
  }
  return [...groups.values()].sort((a,b)=>b.request_count-a.request_count||a.persona_name.localeCompare(b.persona_name)||a.deterministic_type.localeCompare(b.deterministic_type));
}

export function migrateAnalyticsAccess(source){
  const cacheQuery="  const{data:cacheRows}=await sb.from('ai_response_cache').select('cache_key,hit_count,deterministic_type,created_at').order('hit_count',{ascending:false}).limit(50);";
  if(!source.includes(cacheQuery)||!source.includes('  const cache=cacheRows||[];'))throw Error('Analytics cache source contract changed');
  source=source.replace("let period='30d';",summarizeCachedRequests.toString()+"\nlet period='30d';");
  source=source.replace('  // Fetch cache stats','  // Cache usage is counted only from visible conversation responses.').replace(cacheQuery,'');
  source=source.replace('  const cache=cacheRows||[];','  const cache=summarizeCachedRequests(assistant);');
  source=source.replace('const{data:turns}=','const{data:turns,error:turnError}=').replace('const{data:userTurns}=','const{data:userTurns,error:userTurnError}=').replace('const{data:auditRows}=','const{data:auditRows,error:auditError}=');
  source=source.replace('  const assistant=(turns||[])',"  if(turnError||userTurnError||auditError){el.textContent='Analytics could not be loaded. Sign in and try again.';return;}\n  const assistant=(turns||[])");
  source=source.replaceAll('c.hit_count','c.request_count').replace('${esc(c.cache_key?.slice(0,50)||\'\')}','${esc(c.persona_name)}').replace('${c.deterministic_type||\'\'}','${esc(c.deterministic_type)}');
  source=source.replace('<div class="label">Cache Hits</div>','<div class="label">Cached Requests</div>').replace('${cache.length} cached answers','in the loaded visible conversation sample');
  source=source.replace('Top Cached Answers <span class="badge">saves $</span>','Cached Use by Persona <span class="badge">visible sample</span>').replace('No cached answers yet','No cached responses in the loaded sample');
  if(source.includes("from('ai_response_cache')")||source.includes('cacheRows')||source.includes('c.cache_key'))throw Error('Private cache dependency remains');
  return source;
}

export function omitDemoJoin(source){
  // Existing command-center empty-state UI already asks for an administrator invite.
  return source.replace(/^\s*await sb\.rpc\('join_demo_org'\);\s*$/gm,'');
}
