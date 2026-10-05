// Ephemeral transfer entrypoints are generated with hash-only authentication.
// The permanent repository/deployed endpoint is inert after the transfer.
Deno.serve(()=>new Response(JSON.stringify({error:'gone'}),{status:410,headers:{'Content-Type':'application/json'}}));
