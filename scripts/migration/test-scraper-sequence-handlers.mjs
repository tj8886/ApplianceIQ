import assert from 'node:assert/strict';
import {createHandler as scraper} from '../../supabase/functions/scraper-write/handler.ts';
import {createHandler as sequence} from '../../supabase/functions/sequence-executor/handler.ts';
import {createHandler as shopify} from '../../supabase/functions/shopify-initial-sync/handler.ts';
import {createHandler as storis} from '../../supabase/functions/storis-sync/handler.ts';
for(const [factory,rpc,limit] of [[scraper,'tj_scraper_write',1048576],[sequence,'tj_sequence_preview',8192],[shopify,'tj_shopify_initial_sync',8192],[storis,'tj_storis_setup',16384]]){
 let valid=true,anonymous=false,calls=0,mode='success';
 const handler=factory({env:n=>({SUPABASE_URL:'https://us.test',SUPABASE_ANON_KEY:'public'}[n]),createClient:(u,k,opts)=>{
  assert.equal(k,'public');assert.equal(opts.global.headers.Authorization,'Bearer caller');
  return {auth:{getUser:async()=>({data:{user:valid?{id:'native',is_anonymous:anonymous}:null}})},rpc:async(name,args)=>{
   calls++;assert.equal(name,rpc);assert.equal(args.p_body.table,'synthetic');
   return mode==='success'?{data:{ok:true,count:1,data:[]}}:mode==='blocked'?{data:{ok:false,error:'verification_required'}}:mode==='missing'?{data:null}:{error:{code:mode,message:'private SQL details',hint:'private hint'}};
  }};
 }});
 const req=(body='{"table":"synthetic"}',headers={Authorization:'Bearer caller'})=>new Request('https://edge.test',{method:'POST',headers,body});
 assert.equal((await handler(new Request('https://edge.test',{method:'OPTIONS'}))).status,204);
 assert.equal((await handler(new Request('https://edge.test'))).status,405);
 assert.equal((await handler(req('{}',{'x-proxy-key':'legacy'}))).status,401);
 valid=false;assert.equal((await handler(req())).status,401);valid=true;anonymous=true;assert.equal((await handler(req())).status,401);anonymous=false;
 for(const body of ['null','[]','invalid'])assert.equal((await handler(req(body))).status,400);
 assert.equal((await handler(req('x'.repeat(limit+1)))).status,413);
 assert.equal(calls,0);assert.equal((await handler(req())).status,200);
 for(const [code,status] of [['42501',403],['22023',400],['22P02',400],['54000',400],['23505',422],['XX000',500],['blocked',409],['missing',500]]){
  mode=code;const r=await handler(req());assert.equal(r.status,status,code);assert(!JSON.stringify(await r.json()).includes('private'));
 }
}
console.log('Governed scraper, sequence, Shopify and Storis handlers passed: native identity, legacy-key rejection, bounded streaming bodies, caller RPC only, safe errors and blocked sends.');
