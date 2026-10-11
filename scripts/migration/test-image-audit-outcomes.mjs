import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
const source=fs.readFileSync(new URL('../../supabase/functions/image-audit/index.ts',import.meta.url),'utf8');
const code=stripTypeScriptTypes(source).replace(/^import .*$/gm,'');
for(const scenario of ['success','invalid_image','upsert_error','queue_error','queue_both_error','product_read_error','missing_product','claim_error','pending_error','dispatch_error','bounded','auth_denied']) {
 let handler,claims=0,fetches=0;const pending=[],logs=[],updates=[],claimArgs=[];
 class Img {constructor(){this.width=512;this.height=512;this.bitmap=new Uint8Array(512*512*4).fill(255);} static async decode(){if(scenario==='invalid_image')throw Error('decode');return new Img();}}
 const client={rpc:async(name,args)=>{
  if(name==='claim_image_audit_batch'){claimArgs.push(args);claims++;return {data:scenario==='bounded'||claims===1?['fixture'+claims]:[],error:scenario==='claim_error'?{}:null};}
  return {error:scenario==='dispatch_error'?{}:null};
 },from(table){let action='read',values,options;const predicates=[];
  const q={select(_cols,opts){options=opts;return q;},eq(col,val){predicates.push([col,val]);return q;},lt(){return q;},in(){return q;},update(v){action='update';values=v;return q;},upsert:async()=>({error:scenario==='upsert_error'?{}:null}),then(resolve,reject){
   let result;
   if(table==='products')result={data:scenario==='missing_product'?[]:[{id:'fixture'+claims,image_url:'https://example.test/photo.jpg',gallery_urls:['https://example.test/photo.jpg']}],error:scenario==='product_read_error'?{}:null};
   else if(action==='update'){updates.push({values,predicates});result={data:[{product_id:'fixture'+claims}],error:(scenario==='queue_error'&&values.status==='done')||scenario==='queue_both_error'?{}:null};}
   else if(options?.head)result={count:1,error:scenario==='pending_error'?{}:null};
   else result={data:[{product_id:'fixture'+claims,claimed_at:'2026-10-11T20:00:00Z'}],error:null};
   return Promise.resolve(result).then(resolve,reject);
  }};return q;
 }};
 vm.runInNewContext(code,{Request,Response,URL,AbortSignal,Uint8Array,Date,Math,Set,Error,console,Image:Img,
 Deno:{env:{get:()=> 'fixture'},serve:fn=>handler=fn},createClient:()=>client,
 requireJobAuth:async()=>scenario==='auth_denied'?new Response('',{status:401}):{},
 beginInvocation:()=>({}),finishInvocation:async(_c,_i,outcome,detail)=>logs.push({outcome,detail}),
 EdgeRuntime:{waitUntil:p=>pending.push(p)},fetch:async()=>{fetches++;return new Response(new Uint8Array([1,2,3]),{headers:{'content-type':'image/jpeg'}});}});
 const response=await handler(new Request('https://example.test/audit',{method:'POST',body:JSON.stringify({batch:scenario==='bounded'?20:1,chain:['pending_error','dispatch_error'].includes(scenario)?1:0})}));
 await Promise.all(pending);
 if(scenario==='auth_denied'){assert.equal(response.status,401);assert.equal(claims+fetches+logs.length,0);continue;}
 assert.equal(response.status,202);const log=logs.at(-1);assert.ok(log,scenario);
 const ok=['success','invalid_image','bounded'].includes(scenario);assert.equal(log.outcome,ok?'completed':'failed',scenario);
 if(scenario==='invalid_image'){assert.equal(log.detail.invalid,1);assert.equal(updates[0].values.status,'done');}
 if(scenario==='upsert_error')assert.equal(updates[0].values.status,'error');
 if(scenario==='bounded')assert.equal(claims,1);
 for(const arg of claimArgs)assert.equal(arg.n,1);
 for(const u of updates){assert.ok(u.predicates.some(([c])=>c==='claimed_at'));assert.ok(!('attempts' in u.values));}
 if(!ok)assert.equal(log.detail.errors,1,scenario);
}
console.log('Image audit outcomes passed: bounded claims, persisted success, DB/read/dispatch failures, invalid-image distinction, claim ownership, auth and unchanged retry budgets.');
