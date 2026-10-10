import {createClient} from 'npm:@supabase/supabase-js@2.117.2';
import {createHandler} from './handler.ts';
Deno.serve((req:Request)=>createHandler({createClient,env:n=>Deno.env.get(n)})(req));
