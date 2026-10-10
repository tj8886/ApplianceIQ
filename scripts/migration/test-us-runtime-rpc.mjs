import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const expected=JSON.parse(readFileSync(new URL('../../docs/migration/us-runtime-api-map.json',import.meta.url),'utf8')).functions;
import { installUsRuntimeRpc,reviewedRuntimeFunctions } from '../../apps/_shared/us-runtime-rpc.mjs';
assert.deepEqual([...reviewedRuntimeFunctions].sort(),[...expected].sort());
assert.throws(()=>installUsRuntimeRpc({supabaseUrl:'https://fumwwhyozeouoqscolke.supabase.co'}),/US East/);
const calls=[];
const auth={};const storage={};
const client=installUsRuntimeRpc({supabaseUrl:'https://jdxslqmgjsuzoisuhvlc.supabase.co',auth,storage,rpc:async(...args)=>{calls.push(args);return{data:true,error:null}}});
for(const name of reviewedRuntimeFunctions){const args={p_organization_id:'fixture'};const options={count:'exact'};assert.equal((await client.rpc(name,args,options)).data,true);assert.deepEqual(calls.at(-1),[`tj_runtime_${name}`,args,options]);}
assert.equal((await client.rpc('unreviewed_worker',{})).error.code,'MIGRATION_RPC_NOT_READY');assert.equal(calls.length,expected.length);assert.equal(client.auth,auth);assert.equal(client.storage,storage);
console.log(`${expected.length} RPC routes passed; wrong project and unknown workflows blocked; auth/storage preserved`);
