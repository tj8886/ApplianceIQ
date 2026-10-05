import assert from 'node:assert/strict';
import {readFileSync,readdirSync,statSync} from 'node:fs';
import {join} from 'node:path';
import vm from 'node:vm';
const out=process.argv[2];if(!out)throw Error('Pass bulk build output directory');
const report=JSON.parse(readFileSync(join(out,'batch-readiness.json'),'utf8'));
assert.equal(report.apps.length,11);assert.equal(report.published,false);
function files(d){return readdirSync(d).flatMap(n=>{const p=join(d,n);return statSync(p).isDirectory()?files(p):[p]});}
for(const app of report.apps){
 const dir=join(out,app.key);let routed=0;
 for(const p of files(dir).filter(p=>/\.(html|js|mjs)$/.test(p))){const s=readFileSync(p,'utf8');assert.ok(!s.includes('fumwwhyozeouoqscolke.supabase.co'),p);assert.ok(!s.includes('https://appliance-iq-platform.netlify.app/aiq-module-adapter.js'),p);if(p.endsWith('.html'))assert.ok(s.includes('src="/_aiq/us-client.js"'),p);routed+=(s.match(/window\.AIQ_US\.createClient\(/g)||[]).length;}
 assert.equal(routed,app.clients_routed);
 const network=[];const context={window:{fetch:async(request)=>{network.push(request);return new Response('{}');}},Request,Response,URL,Headers};vm.createContext(context);vm.runInContext(readFileSync(join(dir,'_aiq/us-client.js'),'utf8'),context);
 const auth={},storage={},calls=[];const factory=(url,key,options)=>({supabaseUrl:url,auth,storage,schema:(schema)=>({from:(table)=>({schema,table})}),rpc:async(...args)=>{calls.push(args);return {data:true,error:null}}});
 const client=context.window.AIQ_US.createClient(factory,'https://jdxslqmgjsuzoisuhvlc.supabase.co','public-key');assert.equal(client.from('products').schema,'tj');assert.equal(client.from('products').table,'products');assert.equal(client.from('aiq_products').table,'aiq_products_app');assert.equal(client.from('aiq_product_versions').table,'aiq_product_versions_app');assert.equal(client.auth,auth);assert.equal(client.storage,storage);
 await context.window.fetch('https://jdxslqmgjsuzoisuhvlc.supabase.co/rest/v1/aiq_products?select=*');assert.ok(network.at(-1).url.includes('/aiq_products_app?'));
 await client.rpc('my_platform_context',{});assert.equal(calls[0][0],'tj_runtime_my_platform_context');assert.equal((await client.rpc('not_migrated',{})).error.code,'MIGRATION_RPC_NOT_READY');assert.equal(calls.length,1);
 assert.throws(()=>context.window.AIQ_US.createClient(factory,'https://fumwwhyozeouoqscolke.supabase.co','key'),/destination/);
 await context.window.fetch('https://jdxslqmgjsuzoisuhvlc.supabase.co/rest/v1/products');assert.equal(network.at(-1).headers.get('Accept-Profile'),'tj');
 await context.window.fetch('https://jdxslqmgjsuzoisuhvlc.supabase.co/rest/v1/rpc/my_platform_context',{method:'POST',body:'{}'});assert.ok(network.at(-1).url.endsWith('/rpc/tj_runtime_my_platform_context'));assert.equal(network.at(-1).headers.get('Content-Profile'),'public');
 const prior=network.length;assert.equal((await context.window.fetch('https://jdxslqmgjsuzoisuhvlc.supabase.co/rest/v1/rpc/unreviewed_rpc',{method:'POST',body:'{}'})).status,403);assert.equal(network.length,prior);
 for(const name of ['create_org_invite','revoke_org_invite','get_invite_preview','accept_org_invite']){await client.rpc(name,{});assert.equal(calls.at(-1)[0],'tj_runtime_'+name);}
 await context.window.fetch('https://jdxslqmgjsuzoisuhvlc.supabase.co/rest/v1/rpc/get_invite_preview',{method:'POST',body:'{}'});assert.ok(network.at(-1).url.endsWith('/rpc/tj_runtime_get_invite_preview'));assert.equal(network.at(-1).headers.get('Authorization'),null);
 const adapter=readFileSync(join(dir,'_aiq/aiq-module-adapter.js'),'utf8');assert.ok(!adapter.includes('sb.auth.setSession'));assert.ok(adapter.includes('sb.auth.verifyOtp'));
}
console.log('11 app bundles passed routing, source-endpoint removal, local assets, auth/storage preservation and ticket-only shared handoff checks');
