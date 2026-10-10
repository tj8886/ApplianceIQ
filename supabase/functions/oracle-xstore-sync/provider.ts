export async function boundedText(r:Response,max:number){
 if(!r.ok){await r.body?.cancel();throw Error('upstream_failed');}
 const reader=r.body?.getReader();if(!reader)throw Error('empty_response');
 let size=0,text='';const decoder=new TextDecoder();
 try{for(;;){const n=await reader.read();if(n.done)break;size+=n.value.length;if(size>max)throw Error('response_too_large');text+=decoder.decode(n.value,{stream:true});}return text+decoder.decode();}catch(e){await reader.cancel();throw e;}
}
export async function fetchAccessToken(tokenUrl:string,credential:any,fetchImpl:typeof fetch){
 if(!credential||typeof credential!=='object'||Array.isArray(credential)||Object.keys(credential).some(k=>!['client_id','client_secret','scope'].includes(k))||['client_id','client_secret','scope'].some(k=>typeof credential[k]!=='string'||!credential[k]||credential[k].length>(k==='scope'?2000:4096)||/[\r\n]/.test(credential[k])))throw Error('invalid_credential');
 const form=new URLSearchParams({grant_type:'client_credentials',scope:credential.scope});
 const tr=await fetchImpl(tokenUrl,{method:'POST',redirect:'error',signal:AbortSignal.timeout(10000),headers:{'Content-Type':'application/x-www-form-urlencoded',Authorization:'Basic '+btoa(encodeURIComponent(credential.client_id)+':'+encodeURIComponent(credential.client_secret))},body:form});
 if(!tr.headers.get('content-type')?.toLowerCase().includes('application/json')){await tr.body?.cancel();throw Error('invalid_token_type');}
 const tokens=JSON.parse(await boundedText(tr,65536));
 if(typeof tokens.token_type!=='string'||tokens.token_type.toLowerCase()!=='bearer'||typeof tokens.access_token!=='string'||!tokens.access_token||tokens.access_token.length>16000||/[\r\n]/.test(tokens.access_token)||!Number.isInteger(tokens.expires_in)||tokens.expires_in<1||tokens.expires_in>86400)throw Error('invalid_token');
 return tokens.access_token;
}
