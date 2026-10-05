import {createClient} from 'npm:@supabase/supabase-js@2.117.2';
import {createHandler} from './handler.ts';
import {migratedEnvironment} from '../_shared/migrated-environment.ts';
Deno.serve(async(req:Request)=>{try{const env=req.method==='OPTIONS'?(n:string)=>Deno.env.get(n):await migratedEnvironment(n=>Deno.env.get(n));return createHandler({createClient,env})(req);}catch{return new Response(JSON.stringify({error:'runtime_configuration_unavailable'}),{status:503,headers:{'Content-Type':'application/json','Access-Control-Allow-Origin':'*'}});}});
