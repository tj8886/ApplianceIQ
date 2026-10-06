import {createClient} from 'npm:@supabase/supabase-js@2.117.2';
import {jwtVerify,createRemoteJWKSet} from 'npm:jose@6.2.3';
import {migratedEnvironment} from '../_shared/migrated-environment.ts';
import {microsoftValidator} from './verify.ts';
import {createHandler} from './handler.ts';
Deno.serve(createHandler({createClient,env:n=>Deno.env.get(n),loadEnvironment:migratedEnvironment,verifyIdentity:microsoftValidator({jwtVerify,createRemoteJWKSet})}));
