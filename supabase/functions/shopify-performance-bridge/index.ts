import {createClient} from 'npm:@supabase/supabase-js@2.117.2';
import {createHandler} from './handler.js';
Deno.serve(createHandler({createClient,env:n=>Deno.env.get(n)}));
