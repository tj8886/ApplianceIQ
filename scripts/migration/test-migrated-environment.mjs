import assert from 'node:assert/strict';
import {migratedEnvironment} from '../../supabase/functions/_shared/migrated-environment.ts';
const base=n=>({SUPABASE_URL:'https://destination.invalid',SUPABASE_SERVICE_ROLE_KEY:'service-test',OPENAI_API_KEY:'existing-destination'})[n];
let calls=0;
const fetchImpl=async(url,options)=>{calls++;assert.equal(url,'https://destination.invalid/rest/v1/rpc/aiq_migrated_runtime_environment');assert.equal(options.headers.Authorization,'Bearer service-test');return new Response(JSON.stringify({OPENAI_API_KEY:'synthetic-migrated',AI_MODEL_LIGHT:'configured-model'}));};
let env=await migratedEnvironment(base,fetchImpl);assert.equal(env('SUPABASE_URL'),'https://destination.invalid');assert.equal(env('OPENAI_API_KEY'),'synthetic-migrated');assert.equal(env('AI_MODEL_LIGHT'),'configured-model');env=await migratedEnvironment(base,fetchImpl);assert.equal(calls,1);assert.equal((await migratedEnvironment(()=>undefined,fetchImpl))('OPENAI_API_KEY'),undefined);
console.log('Migrated environment tests passed: service-only retrieval, cache, preserved managed config, isolated provider config.');
