export function microsoftValidator({jwtVerify,createRemoteJWKSet}:{jwtVerify:any;createRemoteJWKSet:any}){
 const keys=new Map();
 return async(token:string,ctx:any)=>{
  const tenant=ctx.tenant_id;if(!/^[0-9a-f-]{36}$/i.test(tenant))throw Error('invalid_tenant');
  if(!keys.has(tenant)){if(keys.size>=50)keys.clear();keys.set(tenant,createRemoteJWKSet(new URL('https://login.microsoftonline.com/'+tenant+'/discovery/v2.0/keys'),{timeoutDuration:10000,cooldownDuration:30000}));}
  const {payload}=await jwtVerify(token,keys.get(tenant),{issuer:'https://login.microsoftonline.com/'+tenant+'/v2.0',audience:ctx.client_id,algorithms:['RS256'],requiredClaims:['exp','iat','nbf','sub','tid','nonce'],clockTolerance:30,maxTokenAge:'10m'});
  if(payload.tid!==tenant||payload.nonce!==ctx.nonce||typeof payload.sub!=='string'||!payload.sub||payload.sub.length>300)throw Error('invalid_identity_claims');
  return payload;
 };
}
