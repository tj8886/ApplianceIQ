import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
function json(body:unknown,status=200){return new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json"}})}
function n(v:any){const x=Number(v);return Number.isFinite(x)?x:0}
function iso(v:any){if(!v)return new Date().toISOString();const d=new Date(v);return Number.isNaN(d.valueOf())?new Date().toISOString():d.toISOString()}
function boolMatch(s:string,re:RegExp){return re.test((s||'').toLowerCase())}
function chunks<T>(a:T[],size=200){const out:T[][]=[];for(let i=0;i<a.length;i+=size)out.push(a.slice(i,i+size));return out}

Deno.serve(async(req:Request)=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:cors});
  if(req.method!=='POST')return json({error:'POST required'},405);
  const supabaseUrl=Deno.env.get('SUPABASE_URL')!;
  const anon=Deno.env.get('SUPABASE_ANON_KEY')!;
  const service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const auth=req.headers.get('Authorization')??'';
  const userClient=createClient(supabaseUrl,anon,{global:{headers:{Authorization:auth}}});
  const admin=createClient(supabaseUrl,service);
  const {data:{user}}=await userClient.auth.getUser();
  if(!user)return json({error:'unauthorized'},401);
  let body:any;try{body=await req.json()}catch{return json({error:'invalid_json'},400)}
  const connectionId=String(body.connection_id??'');if(!connectionId)return json({error:'connection_id_required'},400);
  const {data:conn}=await admin.from('platform_connector_connections').select('id,organization_id,store_id,connector_id,variant_id,settings').eq('id',connectionId).maybeSingle();
  if(!conn)return json({error:'connection_not_found'},404);
  const {data:member}=await admin.from('organization_members').select('role,status').eq('organization_id',conn.organization_id).eq('user_id',user.id).eq('status','active').maybeSingle();
  if(!member)return json({error:'organization_access_denied'},403);
  if(!['owner','admin','super_admin'].includes(String(member.role??'')))return json({error:'admin_required'},403);

  let q=admin.from('platform_connector_ingestion_keys').select('external_id,intelligence_event_id,last_seen_at').eq('connection_id',connectionId).eq('external_entity_type','salesInvoice').not('intelligence_event_id','is',null).order('last_seen_at',{ascending:true});
  if(body.since)q=q.gte('last_seen_at',iso(body.since));
  const {data:keys,error:ke}=await q.limit(Math.min(Number(body.limit??1000),5000));
  if(ke)return json({error:'invoice_lookup_failed',detail:ke.message},500);
  const eventIds=(keys??[]).map((x:any)=>x.intelligence_event_id).filter(Boolean);
  if(!eventIds.length)return json({ok:true,processed:0,transactions:0,lines:0,message:'No posted invoices waiting for performance normalization.'});

  const events:any[]=[];
  for(const part of chunks(eventIds,150)){
    const {data,error}=await admin.from('intelligence_events').select('id,organization_id,payload,occurred_at,source_record_id').in('id',part);
    if(error)return json({error:'invoice_event_fetch_failed',detail:error.message},500);
    events.push(...(data??[]));
  }

  const itemIds=new Set<string>();
  for(const ev of events){for(const line of (ev.payload?.salesInvoiceLines??[])){if(line?.itemId)itemIds.add(String(line.itemId));}}
  const itemPayloadById=new Map<string,any>();
  if(itemIds.size){
    const ids=[...itemIds];
    for(const part of chunks(ids,150)){
      const {data:ik}=await admin.from('platform_connector_ingestion_keys').select('external_id,intelligence_event_id').eq('connection_id',connectionId).eq('external_entity_type','item').in('external_id',part).not('intelligence_event_id','is',null);
      const itemEventIds=(ik??[]).map((x:any)=>x.intelligence_event_id).filter(Boolean);
      if(!itemEventIds.length)continue;
      const {data:iev}=await admin.from('intelligence_events').select('id,payload').in('id',itemEventIds);
      const byEvent=new Map((iev??[]).map((x:any)=>[x.id,x.payload]));
      for(const k of (ik??[])){const p=byEvent.get(k.intelligence_event_id);if(p)itemPayloadById.set(String(k.external_id),p);}
    }
  }

  const stats={processed:0,transactions:0,lines:0,sales_transactions:0,mapped_reps:0,failed:0};
  const errors:any[]=[];
  for(const ev of events){
    try{
      const inv=ev.payload??{};const invoiceNo=String(inv.number??ev.source_record_id??inv.id??'');if(!invoiceNo)continue;
      const lines=Array.isArray(inv.salesInvoiceLines)?inv.salesInvoiceLines:[];
      const salesperson=String(inv.salesperson??'').trim()||null;
      const transactionDate=iso(inv.postingDate??inv.invoiceDate??ev.occurred_at);
      let lineCost=0,lineRevenue=0,warrantyValue=0,deliveryValue=0,installValue=0,haulValue=0;
      const enriched:any[]=[];
      for(const line of lines){
        const item=itemPayloadById.get(String(line.itemId??''))??{};
        const qty=n(line.quantity);const unitCost=n(item.unitCost);const cost=qty*unitCost;
        const amount=n(line.netAmount||line.amountExcludingTax||0);const desc=String(line.description??'');const cat=String(item.itemCategoryCode??'');const lt=String(line.lineType??'');
        const isWarranty=boolMatch(`${desc} ${cat}`,/warranty|protection|extended service|service plan/);
        const isDelivery=boolMatch(`${desc} ${cat}`,/delivery|freight|shipping/);
        const isInstall=boolMatch(`${desc} ${cat}`,/install|installation/);
        const isHaul=boolMatch(`${desc} ${cat}`,/haul|removal|take.?away/);
        const isService=lt.toLowerCase()==='resource'||isWarranty||isDelivery||isInstall||isHaul;
        if(isWarranty)warrantyValue+=amount;if(isDelivery)deliveryValue+=amount;if(isInstall)installValue+=amount;if(isHaul)haulValue+=amount;
        lineCost+=cost;lineRevenue+=amount;
        enriched.push({line,item,qty,unitCost,cost,amount,isWarranty,isDelivery,isInstall,isHaul,isService});
      }
      const revenue=n(inv.totalAmountExcludingTax)||lineRevenue;
      const discount=n(inv.discountAmount);
      const gross=revenue-lineCost;const grossPct=revenue?gross/revenue*100:null;
      const posRow={organization_id:conn.organization_id,store_id:conn.store_id,pos_transaction_id:invoiceNo,pos_employee_id:salesperson,transaction_amount:revenue,transaction_date:transactionDate,line_items:lines,warranty_items:enriched.filter(x=>x.isWarranty).map(x=>x.line),synced_at:new Date().toISOString(),source_system:'microsoft_dynamics_365_business_central',source_connection_id:connectionId,customer_external_id:inv.customerId??inv.customerNumber??null,salesperson_external_id:salesperson,currency_code:inv.currencyCode??null,subtotal:revenue,discount_amount:discount,cost_amount:lineCost,gross_margin_amount:gross,gross_margin_pct:grossPct,source_payload:inv};
      const {data:pos,error:pe}=await admin.from('iq_pos_transactions').upsert(posRow,{onConflict:'organization_id,pos_transaction_id'}).select('id').single();if(pe)throw pe;
      stats.transactions++;
      for(const e of enriched){
        const l=e.line;const margin=e.amount-e.cost;const marginPct=e.amount?margin/e.amount*100:null;
        const fact={organization_id:conn.organization_id,transaction_id:pos.id,source_connection_id:connectionId,external_line_id:String(l.id??l.sequence??`${invoiceNo}-${stats.lines}`),external_item_id:l.itemId??null,item_number:l.lineObjectNumber??e.item.number??null,description:l.description??null,brand:e.item.brand??null,product_category:e.item.itemCategoryCode??null,quantity:e.qty,unit_price:n(l.unitPrice),line_amount:e.amount,discount_amount:n(l.discountAmount)+n(l.invoiceDiscountAllocation),unit_cost:e.unitCost||null,line_cost:e.cost||null,gross_margin_amount:margin,gross_margin_pct:marginPct,is_warranty:e.isWarranty,is_service:e.isService,is_delivery:e.isDelivery,is_installation:e.isInstall,is_haul_away:e.isHaul,occurred_at:transactionDate,metadata:{line_type:l.lineType??null,item_category_id:e.item.itemCategoryId??null,item_type:e.item.type??null}};
        const {error:le}=await admin.from('iq_transaction_line_facts').upsert(fact,{onConflict:'organization_id,transaction_id,external_line_id'});if(le)throw le;stats.lines++;
      }
      let mappedUser:string|null=null;
      if(salesperson){const {data:map}=await admin.from('iq_pos_employee_map').select('salesperson_user_id').eq('organization_id',conn.organization_id).eq('pos_employee_id',salesperson).eq('is_active',true).maybeSingle();mappedUser=map?.salesperson_user_id??null;if(mappedUser)stats.mapped_reps++;}
      const salesRow={organization_id:conn.organization_id,location_id:conn.store_id,user_id:mappedUser,transaction_date:transactionDate.slice(0,10),item_count:enriched.filter(x=>String(x.line.lineType??'').toLowerCase()==='item').reduce((a,x)=>a+n(x.qty),0),item_value:revenue,order_total:revenue,warranty_offered:false,warranty_sold:warrantyValue>0,warranty_value:warrantyValue,brand:null,product_category:null,delivery_value:deliveryValue,install_value:installValue,haul_away_value:haulValue,invoice_number:invoiceNo,is_return:revenue<0,metadata:{source:'business_central',source_connection_id:connectionId,pos_transaction_id:pos.id,currency_code:inv.currencyCode??null,cost_amount:lineCost,gross_margin_amount:gross,gross_margin_pct:grossPct,salesperson_external_id:salesperson,customer_external_id:inv.customerId??null}};
      const {data:existing}=await admin.from('sales_transactions').select('id').eq('organization_id',conn.organization_id).eq('invoice_number',invoiceNo).maybeSingle();
      if(existing?.id){const {error}=await admin.from('sales_transactions').update(salesRow).eq('id',existing.id);if(error)throw error;}else{const {error}=await admin.from('sales_transactions').insert(salesRow);if(error)throw error;}
      stats.sales_transactions++;stats.processed++;
    }catch(e){stats.failed++;errors.push({event_id:ev.id,error:String((e as any)?.message??e)});}
  }
  return json({ok:stats.failed===0,connection_id:connectionId,stats,errors:errors.slice(0,20)});
});
