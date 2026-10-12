import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
const code=stripTypeScriptTypes(fs.readFileSync('supabase/functions/enrich-icecat/index.ts','utf8')).replace(/^import .*$/gm,'');
for(const full of [false,true]) {
 let handler,observed;
 const logged=[];
 const credentials={ICECAT_USERNAME:'fixture-user', ...(full?{ICECAT_APP_KEY:'private-app',ICECAT_API_TOKEN:'private-api',ICECAT_CONTENT_TOKEN:'private-content'}:{})};
 const query={select:()=>query,eq:()=>query,single:async()=>({data:{id:'fixture',brand_name:'Brand & Co',model_number:'MODEL#1'}}),update:()=>({eq:async()=>({error:null})})};
 vm.runInNewContext(code,{Request,Response,URL,URLSearchParams,AbortSignal,console,setTimeout:fn=>fn(),Deno:{env:{get:k=>credentials[k]},serve:fn=>handler=fn},createClient:()=>({from:()=>query}),requireJobAuth:async()=>({ok:true}),beginInvocation:()=>({}),finishInvocation:async(_c,_i,o,d)=>logged.push({o,d}),fetch:async(url,options)=>{observed={url:new URL(url),options};return Response.json({message:'not found'},{status:404});}});
 const response=await handler(new Request('https://example.test',{method:'POST',body:JSON.stringify({product_id:'fixture'})}));
 assert.equal(response.status,200);
 assert.equal(observed.url.searchParams.get('Brand'),'Brand & Co');
 assert.equal(observed.url.searchParams.get('ProductCode'),'MODEL#1');
 assert.equal(observed.url.searchParams.get('content'),'');
 assert.equal(observed.url.searchParams.get('app_key'),full?'private-app':null);
 assert.equal(observed.options.headers['api-token'],full?'private-api':undefined);
 assert.equal(observed.options.headers['content-token'],full?'private-content':undefined);
 assert.equal(observed.options.redirect,'error');
 assert.ok(observed.options.signal);
 assert.equal(JSON.stringify(logged).includes('private-'),false);
}
console.log('Icecat credentials passed: optional token headers, legacy key parameter, encoded identifiers, bounded requests and no credential audit leakage.');
