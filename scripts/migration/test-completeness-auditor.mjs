import assert from 'node:assert/strict';
import {createHandler} from '../../supabase/functions/pim-completeness-auditor/handler.ts';
const env=n=>({SUPABASE_URL:'https://destination.invalid',SUPABASE_ANON_KEY:'public-key'})[n];
const req=(body,auth=true)=>new Request('https://example.invalid',{method:'POST',headers:{'Content-Type':'application/json',...(auth?{Authorization:'Bearer native-session'}:{})},body:JSON.stringify(body)});
function mock({signedIn=true,mapped=true,errorTable=null}={}){
 const calls=[];const createClient=(url,key,options)=>{
  assert.equal(key,'public-key');assert.equal(options.global.headers.Authorization,'Bearer native-session');
  return {auth:{getUser:async()=>({data:{user:signedIn?{}:null},error:null})},rpc:async name=>{assert.equal(name,'tj_runtime_my_platform_context');return{data:mapped?{organization_id:'organization'}:{},error:null}},schema:s=>{assert.equal(s,'tj');return {from:table=>{
   const call={table,steps:[]};calls.push(call);
   const b=new Proxy({}, {get(_,k){if(k==='then')return resolve=>{
    let data=[],count=0;
    if(table==='aiq_products_app'){data=[{id:'product',model:'M1',width_inches:0,height_inches:null,depth_inches:-1,msrp:0,sale_price:null,source_confidence:Infinity,status:'draft',approval_status:'draft',public_visible:false}];count=2;}
    else {const range=call.steps.find(x=>x[0]==='range');const offset=range?.[1]??0;count=table==='pim_product_features'?1001:1;data=Array.from({length:Math.min(500,count-offset)},(_,i)=>({id:String(offset+i),product_id:'product',approved:null,is_current:true}));}
    resolve({data,count,error:table===errorTable?{code:'denied'}:null});
   };return(...args)=>{call.steps.push([k,...args]);return b};}});return b;
  }};}};
 };return{createClient,calls};
}
let m=mock(),h=createHandler({...m,env});assert.equal((await h(req({},false))).status,401);assert.equal((await h(req(null))).status,400);
m=mock({signedIn:false});assert.equal((await createHandler({...m,env})(req({}))).status,401);
m=mock({mapped:false});assert.equal((await createHandler({...m,env})(req({}))).status,403);
m=mock();h=createHandler({...m,env});assert.equal((await h(req({organization_id:'wrong'}))).status,403);
let r=await h(req({}));assert.equal(r.status,200);let body=await r.json();assert.equal(body.next_cursor,'product');assert.equal(body.scanned_products,1);assert.equal(body.products[0].counts.feature_count,1001);assert.equal(body.products[0].counts.image_count,0);assert.equal(body.products[0].counts.document_count,0);for(const field of ['width','height','depth','price','source_confidence'])assert(body.products[0].missing.includes(field));assert.notEqual(body.products[0].readiness,'ready');
assert(m.calls[0].steps.some(x=>x[0]==='eq'&&x[1]==='organization_id'&&x[2]==='organization'));assert(m.calls[0].table==='aiq_products_app');
m=mock({errorTable:'pim_product_images'});assert.equal((await createHandler({...m,env})(req({}))).status,502);
console.log('Completeness auditor tests passed: auth, organization scope, child pagination/count caps, approval gates, missing/invalid numbers and failed dependencies.');
