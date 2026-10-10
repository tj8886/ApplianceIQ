import assert from 'node:assert/strict';
import {createTurnstileHandler} from '../../supabase/functions/turnstile-verify/handler.ts';
const now=Date.now(),origin='https://applianceiq.com';let calls=0,budgets=0;
let result={success:true,hostname:'applianceiq.com',action:'login',challenge_ts:new Date(now).toISOString(),cdata:'abc'};
const config={TURNSTILE_SECRET_KEY:'synthetic-secret',TURNSTILE_ALLOWED_ORIGINS:JSON.stringify({[origin]:['login']})};
const deps={configuration:async()=>key=>config[key],consume:async()=>{budgets++;return true;},now:()=>now,fetch:async(url,opts)=>{
  calls++;assert.equal(url,'https://challenges.cloudflare.com/turnstile/v0/siteverify');assert.equal(opts.redirect,'error');
  const sent=JSON.parse(opts.body);assert.equal(sent.secret,'synthetic-secret');assert.ok(!('remoteip' in sent));return new Response(JSON.stringify(result));
}};
const handler=createTurnstileHandler(deps);
const req=(payload={token:'synthetic-token',action:'login'},site=origin)=>new Request('https://unused.test',{method:'POST',headers:{origin:site,'content-type':'application/json','x-forwarded-for':'spoofed'},body:JSON.stringify(payload)});
assert.equal((await handler(req({},'https://attacker.netlify.app'))).status,403);
assert.equal((await handler(req({},'https://applianceiq.com.attacker.test'))).status,403);
assert.equal((await handler(req({token:'x'.repeat(2049),action:'login'}))).status,400);
assert.equal((await handler(req({token:'x',action:'signup'}))).status,400);
assert.equal((await handler(req({token:'x',action:'login',idempotency_key:'not-a-uuid'}))).status,400);
assert.equal((await handler(req({token:'x',action:'login',secret:'spoof'}))).status,400);
assert.equal((await handler(req(null))).status,400);
assert.equal((await handler(req({token:'x'.repeat(9000),action:'login'}))).status,413);
assert.equal(calls,0);assert.equal(budgets,0);
const pass=await handler(req());assert.equal(pass.status,200);assert.equal((await pass.json()).ok,true);
assert.equal(pass.headers.get('access-control-allow-origin'),origin);
for(const [field,value,code] of [['hostname','attacker.test','hostname_mismatch'],['action',undefined,'action_mismatch'],['challenge_ts','invalid','challenge_expired'],['challenge_ts',new Date(now-300001).toISOString(),'challenge_expired'],['challenge_ts',new Date(now+30001).toISOString(),'challenge_expired']]){
  const original=result[field];result[field]=value;const r=await handler(req());assert.equal(r.status,403);assert.equal((await r.json()).code,code);result[field]=original;
}
result.success=false;assert.equal((await handler(req())).status,403);result.success=true;
result.success='true';assert.equal((await handler(req())).status,503);result.success=true;
assert.equal((await handler(req({token:'x',action:'login',cdata:'different'}))).status,403);
assert.equal((await createTurnstileHandler({...deps,consume:async()=>false})(req())).status,429);
assert.equal((await createTurnstileHandler({...deps,consume:async()=>{throw Error('secret failure');}})(req())).status,503);
const unavailable=await createTurnstileHandler({...deps,fetch:async()=>{throw Error('secret failure');}})(req());assert.equal(unavailable.status,503);assert.ok(!(await unavailable.text()).includes('secret failure'));
assert.equal((await createTurnstileHandler({...deps,configuration:async()=>()=>undefined})(req())).status,503);
console.log('PASS: valid challenge, exact origin/hostname/action/cdata, timestamp, bounded inputs, public rate limit, fail-closed provider/configuration, no forwarded IP trust');
