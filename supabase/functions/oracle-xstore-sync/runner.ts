import {fetchAccessToken} from './provider.ts';
const TYPES:Record<string,string>={customers:'customer',products:'product',employees:'employee',locations:'location',inventory:'inventory',prices:'price',transactions:'transaction'};
const IDS:Record<string,string[]>={customers:['customerId','customerNumber','id'],products:['itemId','productId','sku','id'],employees:['employeeId','associateId','salespersonId','code','id'],locations:['storeId','locationId','storeCode','code','id'],inventory:['id','inventoryId'],prices:['id','priceId'],transactions:['transactionId','receiptId','id','transactionSequence','sequenceNumber']};
export function safePageUrl(endpoint:string,next:unknown){
 if(next===null||next===undefined||next==='')return null;
 if(typeof next!=='string'||next.length>4096)throw Error('invalid_pagination');
 const base=new URL(endpoint),url=new URL(next,base);
 if(url.origin!==base.origin||url.pathname!==base.pathname||url.username||url.password||url.hash||url.protocol!=='https:')throw Error('unsafe_pagination');
 return url.toString();
}
export function parsePage(payload:any){
 let rows;if(Array.isArray(payload))rows=payload;else if(payload&&typeof payload==='object'){
  const candidates=['value','items','data','results'].filter(k=>Array.isArray(payload[k]));
  if(candidates.length!==1)throw Error('invalid_page_shape');rows=payload[candidates[0]];
 }else throw Error('invalid_page_shape');
 if(rows.length>100||rows.some((x:any)=>!x||typeof x!=='object'||Array.isArray(x)))throw Error('invalid_page_rows');
 const links=Array.isArray(payload)?[]:[payload['@odata.nextLink'],payload.nextLink,payload.next,payload.links?.next].filter(x=>x!==null&&x!==undefined&&x!=='');
 if(links.length>1&&new Set(links).size!==1)throw Error('ambiguous_pagination');
 if(links.length&&typeof links[0]!=='string')throw Error('invalid_pagination');
 return {rows,next:links[0]??null};
}
export async function readJson(response:Response){
 if(!response.ok||response.headers.get('content-type')?.split(';')[0].trim().toLowerCase()!=='application/json'){await response.body?.cancel();throw Error('provider_response_failed');}
 const reader=response.body?.getReader();if(!reader)throw Error('empty_response');
 let bytes=0,text='';const decoder=new TextDecoder();
 try{for(;;){const v=await reader.read();if(v.done)break;bytes+=v.value.length;if(bytes>1048576)throw Error('response_too_large');text+=decoder.decode(v.value,{stream:true});}text+=decoder.decode();return JSON.parse(text);}catch(e){await reader.cancel();throw e;}
}
export async function runStep({user,service,native,body,scope,endpoint,tokenUrl,fetchImpl}:{user:any;service:any;native:string;body:any;scope:any;endpoint:string;tokenUrl:string;fetchImpl:typeof fetch}){
 const base={p_connection_id:body.connection_id,p_native_user:native,p_job_id:scope.job_id,p_lease:scope.lease};
 const loaded=await service.rpc('aiq_xstore_sync_context',base);if(loaded.error)return {error:loaded.error};
 if(loaded.data.version!==scope.version||loaded.data.phase!==scope.phase||loaded.data.resource!==scope.resource||loaded.data.next_url!==scope.next_url||JSON.stringify(loaded.data.configuration)!==JSON.stringify(scope.configuration))return {error:{code:'40001'}};
 let result:any;
 try{
  if(scope.phase==='bridge'){
   const bridge=await user.rpc('tj_xstore_performance_bridge',{p_body:{connection_id:body.connection_id,after_external_id:loaded.data.bridge_cursor??undefined,limit:100}});
   if(bridge.error)throw Error('bridge_failed');
   const b=bridge.data;if(!b||typeof b.processed!=='number'||!Array.isArray(b.errors))throw Error('invalid_bridge_response');
   if(!Number.isInteger(b.failed)||b.failed<0||b.failed>100)throw Error('invalid_bridge_response');
   result={kind:'bridge',processed:0,failed:b.failed,next_cursor:b.next_cursor??null,has_more:b.next_cursor!==null&&b.next_cursor!==undefined};
  }else{
   const credential=loaded.data.credential;
   const token=await fetchAccessToken(tokenUrl,credential,fetchImpl),headers:Record<string,string>={Accept:'application/json',Authorization:'Bearer '+token};
   const pageUrl=safePageUrl(endpoint,loaded.data.next_url??endpoint)!;
   const page=parsePage(await readJson(await fetchImpl(pageUrl,{headers,redirect:'error',signal:AbortSignal.timeout(10000)})));
   const next=safePageUrl(endpoint,page.next);if(next===pageUrl)throw Error('pagination_cycle');
   let processed=0,failed=0;const started=Date.now();
   for(const row of page.rows){
    if(Date.now()-started>45000)throw Error('page_budget_exceeded');
    const key=IDS[scope.resource]?.find(k=>(typeof row[k]==='string'||typeof row[k]==='number'&&Number.isSafeInteger(row[k]))&&String(row[k]).trim()!=='');
    if(!key){failed++;continue;}
    const external=String(row[key]);if(external.length>500){failed++;continue;}
    const date=['transactionDate','businessDate','updatedAt','date','createdAt'].map(k=>row[k]).find(v=>v!==null&&v!==undefined&&v!=='');
    const ingest=await user.rpc('tj_connector_ingest',{p_body:{connection_id:body.connection_id,sync_job_id:scope.job_id,external_entity_type:TYPES[scope.resource],external_id:external,payload:row,...(date!==undefined?{occurred_at:date}:{})}});
    if(ingest.error){if(['42501','40001'].includes(ingest.error.code))throw Error('scope_changed');failed++;}else if(ingest.data?.ok===true)processed++;else failed++;
   }
   result={kind:'page',processed,failed,next_url:next,page_url:pageUrl};
  }
 }catch{
  // Preserve the cursor for repeat-safe retry; partial record writes dedupe on replay.
  const saved=await service.rpc('aiq_xstore_sync_finish',{...base,p_result:{kind:'retry'}});
  return {error:saved.error??{code:'502',resumable:saved.data?.resumable??true,done:saved.data?.done??false,status:saved.data?.status??'running'}};
 }
 return service.rpc('aiq_xstore_sync_finish',{...base,p_result:result});
}
