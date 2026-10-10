type Dependencies = { configuration: () => Promise<(name: string) => string | undefined>; consume: (origin: string) => Promise<boolean>; fetch?: typeof fetch; now?: () => number };
export function createTurnstileHandler(deps: Dependencies) {
  return async (req: Request): Promise<Response> => {
    const started=(deps.now??Date.now)(),origin=req.headers.get('origin');
    let approved=false;
    const reply=(status:number,body:unknown)=>new Response(JSON.stringify(body),{status,headers:{'content-type':'application/json','cache-control':'no-store',Vary:'Origin',...(approved?{'access-control-allow-origin':origin!,'access-control-allow-methods':'POST, OPTIONS','access-control-allow-headers':'content-type, authorization, apikey'}:{})}});
    if(req.method!=='POST'&&req.method!=='OPTIONS')return reply(405,{ok:false,code:'method_not_allowed'});
    let secret:string|undefined,actions:string[];
    try {
      const env=await deps.configuration();secret=env('TURNSTILE_SECRET_KEY');
      const sites=JSON.parse(env('TURNSTILE_ALLOWED_ORIGINS')??'null');
      if(!secret||!sites||typeof sites!=='object'||Array.isArray(sites)||Object.keys(sites).length>32||!Object.keys(sites).length)throw Error('missing_configuration');
      for(const [site,list] of Object.entries(sites)){
        const u=new URL(site);
        if(u.protocol!=='https:'||u.origin!==site||u.username||u.password||!Array.isArray(list)||!list.length||list.length>16||list.some(a=>typeof a!=='string'||!/^[-\w]{1,32}$/.test(a)))throw Error('invalid_configuration');
      }
      if(!origin||!Object.hasOwn(sites,origin))return reply(403,{ok:false,code:'origin_not_allowed'});
      approved=true;actions=sites[origin];
    }catch{return reply(503,{ok:false,code:'verification_not_configured'});}
    if(req.method==='OPTIONS')return new Response(null,{status:204,headers:{'access-control-allow-origin':origin!,'access-control-allow-methods':'POST, OPTIONS','access-control-allow-headers':'content-type, authorization, apikey',Vary:'Origin'}});
    if(!req.headers.get('content-type')?.toLowerCase().startsWith('application/json'))return reply(415,{ok:false,code:'json_required'});
    // Read a bounded stream rather than materializing an unbounded public request.
    let payload:Record<string,unknown>;
    try {
      const reader=req.body?.getReader();if(!reader)throw Error('empty');
      const chunks:Uint8Array[]=[];let size=0;
      for(;;){const {done,value}=await reader.read();if(done)break;size+=value.byteLength;if(size>8192){await reader.cancel();return reply(413,{ok:false,code:'body_too_large'});}chunks.push(value);}
      const bytes=new Uint8Array(size);let at=0;for(const chunk of chunks){bytes.set(chunk,at);at+=chunk.length;}
      payload=JSON.parse(new TextDecoder().decode(bytes));
      if(!payload||typeof payload!=='object'||Array.isArray(payload)||Object.keys(payload).some(k=>!['token','action','cdata','idempotency_key'].includes(k)))throw Error('invalid');
    }catch{return reply(400,{ok:false,code:'invalid_json'});}
    const {token,action,cdata,idempotency_key}=payload;
    if(typeof token!=='string'||!token.trim()||token.length>2048||typeof action!=='string'||!actions.includes(action)||
      (cdata!==undefined&&(typeof cdata!=='string'||!/^[-\w]{1,255}$/.test(cdata)))||
      (idempotency_key!==undefined&&(typeof idempotency_key!=='string'||! /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(idempotency_key))))return reply(400,{ok:false,code:'invalid_verification_request'});
    try{if(!await deps.consume(origin!))return reply(429,{ok:false,code:'rate_limited',retry_after_minutes:1});}
    catch{return reply(503,{ok:false,code:'rate_limit_unavailable'});}
    const requestId=crypto.randomUUID();
    try{
      const response=await (deps.fetch??fetch)('https://challenges.cloudflare.com/turnstile/v0/siteverify',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({secret,response:token.trim(),idempotency_key:idempotency_key??requestId}),redirect:'error',signal:AbortSignal.timeout(8000)});
      if(!response.ok)throw Error('provider_http_error');
      const raw=await response.text();if(raw.length>16384)throw Error('provider_response_too_large');
      const result=JSON.parse(raw);
      if(!result||typeof result.success!=='boolean')throw Error('malformed_provider_response');
      if(result.success!==true)return reply(403,{ok:false,code:'verification_failed'});
      if(result.hostname!==new URL(origin!).hostname)return reply(403,{ok:false,code:'hostname_mismatch'});
      if(result.action!==action)return reply(403,{ok:false,code:'action_mismatch'});
      if(cdata!==undefined&&result.cdata!==cdata)return reply(403,{ok:false,code:'cdata_mismatch'});
      const timestamp=Date.parse(result.challenge_ts),age=(deps.now??Date.now)()-timestamp;
      if(!Number.isFinite(timestamp)||age < -30000||age>300000)return reply(403,{ok:false,code:'challenge_expired'});
      // This response verifies the challenge only; it is not a reusable authorization credential.
      return reply(200,{ok:true,verification_id:requestId,hostname:result.hostname,action,latency_ms:(deps.now??Date.now)()-started});
    }catch{return reply(503,{ok:false,code:'verification_unavailable'});}
  };
}
