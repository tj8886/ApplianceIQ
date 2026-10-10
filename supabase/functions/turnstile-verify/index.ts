import {createTurnstileHandler} from './handler.ts';
import {migratedEnvironment} from '../_shared/migrated-environment.ts';
const env=(name:string)=>name.startsWith('SUPABASE_')?Deno.env.get(name):undefined;
Deno.serve(createTurnstileHandler({
  configuration:async()=>{
    const imported=await migratedEnvironment(env);
    // Fresh, explicitly namespaced settings never reuse existing US application secrets.
    return name=>imported(name)??Deno.env.get('AIQ_MIGRATED_'+name);
  },
  consume:async origin=>{
    const url=env('SUPABASE_URL'),key=env('SUPABASE_SERVICE_ROLE_KEY');
    if(url!=='https://jdxslqmgjsuzoisuhvlc.supabase.co'||!key)throw Error('runtime_unavailable');
    const r=await fetch(url+'/rest/v1/rpc/aiq_turnstile_consume_budget',{method:'POST',headers:{'content-type':'application/json',apikey:key,authorization:'Bearer '+key},body:JSON.stringify({p_origin:origin}),redirect:'error',signal:AbortSignal.timeout(8000)});
    if(!r.ok)throw Error('budget_unavailable');
    const accepted=await r.json();if(typeof accepted!=='boolean')throw Error('invalid_budget');return accepted;
  }
}));
