import { createClient } from 'npm:@supabase/supabase-js@2.117.2';
import { createHandler } from './handler.ts';
import { migratedEnvironment } from '../_shared/migrated-environment.ts';
Deno.serve(createHandler({createClient,env:n=>Deno.env.get(n),loadEnvironment:migratedEnvironment}));
