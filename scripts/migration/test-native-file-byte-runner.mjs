import assert from 'node:assert/strict';
import {verifyNativeFiles} from './verify-native-file-bytes.mjs';
const config={project_ref:'jdxslqmgjsuzoisuhvlc',url:'https://jdxslqmgjsuzoisuhvlc.supabase.co',publishable_key:'sb_publishable_fixture'};
const id='11111111-1111-4111-8111-111111111111',vendor='22222222-2222-4222-8222-222222222222',token='private-test-token';
let calls=[],uploaded;
const response=(d,status=200)=>new Response(JSON.stringify(d),{status});
function transport({wrongBytes=false,wrongOrg=false}={}){return async(url,options)=>{
 const p=new URL(url).pathname;calls.push({p,...options});assert.ok(url.startsWith(config.url));assert.ok(!['DELETE','PUT'].includes(options.method));assert.equal(options.headers.Authorization,`Bearer ${token}`);
 if(p==='/auth/v1/user')return response({id,email_confirmed_at:'2026-10-10T00:00:00Z'});
 if(p==='/rest/v1/organizations')return response([{slug:wrongOrg?'production-org':'migration-file-test-fixture'}]);
 if(p.endsWith('tj_runtime_speciq_settings'))return response({ok:true,stored:true,can_edit:true,settings:{updated_at:'stamp'}});
 if(p.includes('/rpc/')){const body=JSON.parse(options.body).p_body;if(body.action==='reserve'||body.action==='reserve_upload')return response({ok:true,bucket:body.action==='reserve'?'tj-speciq-logos':'tj-mfr-assets',storage_path:id+'/native/fixture.png',upload_id:id,asset_id:vendor});assert.equal(body.action,'finalize');return response({ok:true});}
 if(options.method==='POST'){assert.equal(options.headers['x-upsert'],'false');uploaded=options.body;return response({error:'Duplicate'},409);}
 return new Response(wrongBytes?new Uint8Array([1,2]):uploaded,{status:200});
};}
const options={config,token,organizationId:id,vendorId:vendor,requestId:id};
let report=await verifyNativeFiles({...options,mode:'logo',fetcher:transport()});assert.equal(report.physical_byte_transfer,'passed');assert.ok(!JSON.stringify(report).includes(token));assert.ok(!calls.some(c=>c.p.includes('logos')&&c.body?.includes?.('finalize')));assert.ok(report.logo_reference.startsWith('unchanged'));
calls=[];report=await verifyNativeFiles({...options,mode:'manufacturer',fetcher:transport()});assert.equal(report.physical_byte_transfer,'passed');assert.equal(calls.filter(c=>c.body?.includes?.('"action":"finalize"')).length,1);assert.ok(!calls.some(c=>c.body?.includes?.('"action":"publish"')));
calls=[];await assert.rejects(verifyNativeFiles({...options,mode:'manufacturer',fetcher:transport({wrongBytes:true})}),/bytes differ/);assert.ok(!calls.some(c=>c.body?.includes?.('"action":"finalize"')));
calls=[];await assert.rejects(verifyNativeFiles({...options,mode:'logo',fetcher:transport({wrongOrg:true})}),/test-/);assert.equal(calls.length,2);
await assert.rejects(verifyNativeFiles({...options,config:{...config,project_ref:'Canada'},fetcher:transport()}),/US destination/);
await assert.rejects(verifyNativeFiles({config,fetcher:async()=>response({message:'Upstream unavailable'},503)}),/Denial check failed/);
console.log('PASS: exact bytes and lost-response recovery, altered bytes rejected before finalize, unpublished manufacturer finalization, production org/destination guards, no overwrite/delete/publish/logo change, token redaction and failed denial response rejection');
