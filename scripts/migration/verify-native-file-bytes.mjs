import {readFileSync,writeFileSync} from 'node:fs';
import {createHash,randomUUID} from 'node:crypto';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';

const DESTINATION='jdxslqmgjsuzoisuhvlc';
const uuid=v=>typeof v==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII=','base64');
const digest=b=>createHash('sha256').update(b).digest('hex');
export async function verifyNativeFiles({config,mode='anonymous',token,organizationId,vendorId,requestId=randomUUID(),fetcher=fetch}){
 if(config.project_ref!==DESTINATION||config.url!==`https://${DESTINATION}.supabase.co`||!config.publishable_key?.startsWith('sb_publishable_'))throw Error('US destination configuration required');
 if(!['anonymous','logo','manufacturer'].includes(mode))throw Error('Unknown verification mode');
 const report={verified_at:new Date().toISOString(),destination_project:DESTINATION,mode,checks:[],physical_byte_transfer:'not_exercised',files_deleted:0,files_overwritten:0,production:'Canada'};
 async function call(path,{method='GET',body,mime='application/json',authenticated=false,profile}={}){
  const headers={apikey:config.publishable_key};if(authenticated)headers.Authorization=`Bearer ${token}`;if(body!==undefined)headers['Content-Type']=mime;if(profile)headers['Accept-Profile']=profile;if(mime==='image/png')headers['x-upsert']='false';
  try{return await fetcher(config.url+path,{method,headers,body:body===undefined?undefined:mime==='image/png'?body:JSON.stringify(body),signal:AbortSignal.timeout(20000),redirect:'error'});}catch{throw Error('US file verification request failed; credentials omitted');}
 }
 async function json(path,options){const r=await call(path,options);let d;try{d=await r.json();}catch{throw Error('Unexpected non-JSON verification response');}if(!r.ok||d.ok===false)throw Error('US native request rejected; credentials and response details omitted');return d;}
 const objectPath=(bucket,path)=>`/storage/v1/object/${bucket}/${path.split('/').map(encodeURIComponent).join('/')}`;
 if(mode==='anonymous'){
  const probes=['speciq_logos','manufacturer_assets'].map(name=>({name:`${name}: anonymous RPC denied`,path:`/rest/v1/rpc/tj_runtime_${name}`,method:'POST',body:{p_body:{action:name==='speciq_logos'?'read':'list',organization_id:'00000000-0000-0000-0000-000000000001'}},kind:'rpc'}));
  for(const bucket of ['tj-speciq-logos','tj-mfr-assets']){const path=`migration-file-denial/${randomUUID()}.png`;probes.push({name:`${bucket}: anonymous unreserved upload denied`,path:objectPath(bucket,path),method:'POST',body:png,mime:'image/png',kind:'upload'},{name:`${bucket}: public object URL unavailable`,path:objectPath('public/'+bucket,path),kind:'public'});}
  report.checks=await Promise.all(probes.map(async p=>{const r=await call(p.path,p);let d;try{d=await r.json();}catch{throw Error('Unexpected denial response');}const code=String(d.code||d.error||''),message=String(d.message||'');const valid=p.kind==='rpc'?r.status===401&&code==='42501':p.kind==='upload'?[400,401,403].includes(r.status)&&(/row-level security|unauthorized|jwt/i.test(message+' '+code)):r.status===400&&/bucket not found/i.test(message);if(!valid)throw Error(`Denial check failed: ${p.name}, HTTP ${r.status}`);return {name:p.name,status:r.status,result:'passed'};}));
  report.authenticated_transfer='pending: fresh approved US user session required';return report;
 }
 if(!token||!uuid(organizationId)||!uuid(requestId)||(mode==='manufacturer'&&!uuid(vendorId)))throw Error('Fresh US user token, test organization UUID and required IDs are missing');
 const user=await json('/auth/v1/user',{authenticated:true});if(!uuid(user.id)||!user.email_confirmed_at)throw Error('Confirmed native user required');
 // Use an approved dedicated test organization. Never change production branding.
 const org=await json(`/rest/v1/organizations?id=eq.${organizationId}&select=slug`,{authenticated:true,profile:'tj'});if(!Array.isArray(org)||org.length!==1||!org[0].slug?.startsWith('migration-file-test-'))throw Error('Approved migration-file-test- organization required');
 const rpc=(name,body)=>json(`/rest/v1/rpc/tj_runtime_${name}`,{method:'POST',authenticated:true,body:{p_body:body}});
 let reserved;
 if(mode==='logo'){
  const settings=await rpc('speciq_settings',{action:'get',organization_id:organizationId});if(!settings.stored||!settings.can_edit||!settings.settings?.updated_at)throw Error('Saved test settings and owner/admin role required');
  reserved=await rpc('speciq_logos',{action:'reserve',organization_id:organizationId,request_id:requestId,expected_updated_at:settings.settings.updated_at,mime_type:'image/png',file_size:png.length});
 }else reserved=await rpc('manufacturer_assets',{action:'reserve_upload',organization_id:organizationId,vendor_id:vendorId,category:'product_image',title:'Migration byte verification (unpublished)',description:'Retained test file; do not publish.',audiences:['retailer'],file_name:'migration-byte-check.png',mime_type:'image/png',file_size_bytes:png.length});
 const bucket=mode==='logo'?'tj-speciq-logos':'tj-mfr-assets';if(reserved.bucket!==bucket||typeof reserved.storage_path!=='string'||!reserved.storage_path.startsWith(organizationId+'/')||reserved.storage_path.split('/').some(s=>!s||s==='.'||s==='..'))throw Error('Unexpected reservation path');
 report.retained={bucket,storage_path:reserved.storage_path,upload_id:reserved.upload_id||null,asset_id:reserved.asset_id||null};
 const path=objectPath(bucket,reserved.storage_path),uploaded=await call(path,{method:'POST',authenticated:true,body:png,mime:'image/png'});
 // An ambiguous response can be a lost successful upload. Exact downloaded bytes decide.
 const downloaded=await call(path,{authenticated:true});if(!downloaded.ok)throw Error('Reserved file download denied; retained reservation requires review');const actual=Buffer.from(await downloaded.arrayBuffer());if(!actual.equals(png))throw Error('Downloaded bytes differ; retained file requires review');
 report.checks.push({name:'reserved upload and private download exact bytes',result:'passed',upload_http_status:uploaded.status,bytes:actual.length,sha256:digest(actual)});
 if(mode==='manufacturer'){await rpc('manufacturer_assets',{action:'finalize',asset_id:reserved.asset_id});report.checks.push({name:'file metadata finalized; asset remains unpublished',result:'passed'});}else report.logo_reference='unchanged: finalize deliberately omitted; reserved file retained';
 report.physical_byte_transfer='passed';report.hosted_browser_workflow='pending';return report;
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
 try{const config=JSON.parse(readFileSync(new URL('../../config/us-east-client.json',import.meta.url)));const report=await verifyNativeFiles({config,mode:process.argv[2]||'anonymous',token:process.env.AIQ_US_TEST_ACCESS_TOKEN,organizationId:process.env.AIQ_US_TEST_ORGANIZATION_ID,vendorId:process.env.AIQ_US_TEST_VENDOR_ID,requestId:process.env.AIQ_US_TEST_REQUEST_ID});if(process.argv[3])writeFileSync(process.argv[3],JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report));}catch(e){console.error(e.message);process.exitCode=1;}
}
