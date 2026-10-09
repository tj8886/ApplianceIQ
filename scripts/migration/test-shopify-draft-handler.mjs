import assert from 'node:assert/strict';
import {createHandler} from '../../supabase/functions/shopify-draft-order/handler.ts';
let result={data:{ok:true,operation:'preview',lines:[{unit_price:'123456.78'}]},error:null},calls=0,anonymous=false;
const handler=createHandler({env:()=>'',createClient:()=>({auth:{getUser:async()=>({data:{user:{id:'native-fixture',is_anonymous:anonymous}},error:null})},rpc:async(name,args)=>{calls++;assert.equal(name,'tj_shopify_draft_order');assert.equal(args.p_body.action,'preview');return result;}})});
const req=(payload,auth='Bearer synthetic')=>new Request('https://unused.test',{method:'POST',headers:{Authorization:auth},body:JSON.stringify(payload)});
assert.equal((await handler(req({},''))).status,401);anonymous=true;assert.equal((await handler(req({})) ).status,401);anonymous=false;
assert.equal((await handler(req(null))).status,400);
assert.equal((await handler(req({token:'x'.repeat(9000)}))).status,413);assert.equal(calls,0);
const response=await handler(req({action:'preview'}));assert.equal(response.status,200);assert.equal((await response.json()).lines[0].unit_price,'123456.78');
for(const [code,status] of [['42501',403],['22023',400],['XX000',500]]){result={error:{code,message:'private-error'}};const r=await handler(req({action:'preview'}));assert.equal(r.status,status);assert.ok(!(await r.text()).includes('private-error'));}
result={data:{ok:false,executed:false,draft_created:false,blockers:['permission_required']},error:null};assert.equal((await handler(req({action:'preview'}))).status,409);
console.log('PASS: native auth, anonymous denial, body bounds, preview passthrough, blocked create response, redacted errors');
