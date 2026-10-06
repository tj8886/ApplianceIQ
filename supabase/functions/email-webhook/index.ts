import {createHandler} from './handler.ts';
Deno.serve(createHandler({env:n=>Deno.env.get(n)}));
