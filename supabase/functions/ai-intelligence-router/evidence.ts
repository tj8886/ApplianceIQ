const readable=(key:string)=>key.replace(/_/g,' ');
const format=(title:string,rows:any[],columns:string[])=>title+'\n\n'+rows.map(r=>columns.filter(k=>r[k]!==null&&r[k]!==undefined&&r[k]!=='').map(k=>`- ${readable(k)}: ${typeof r[k]==='object'?JSON.stringify(r[k]):String(r[k])}`).join('\n')).join('\n\n');
const read=async(query:any)=>{const r=await query;if(r.error)throw new Error('scoped_evidence_read_failed');return r.data??[];};
export async function deterministicEvidence(type:string,message:string,db:any,country:string){
 const lower=message.toLowerCase();
 const brands=await read(db.from('brand_catalog').select('id,brand_name').eq('is_active',true).limit(1000));
 const matched=brands.filter((b:any)=>lower.includes(b.brand_name.toLowerCase())).sort((a:any,b:any)=>b.brand_name.length-a.brand_name.length).slice(0,3);
 const models=[...message.matchAll(/\b[A-Z]{2,5}[A-Z0-9-]{4,}\b/g)].map(m=>m[0]).slice(0,3);
 let rows:any[]=[],columns:string[]=[],source='';
 if(['recall','warranty','contact','map_policy','selling_angles','lifecycle','cross_reference'].includes(type)&&!matched.length&&!models.length)return {ok:false,data:'Which exact brand or model are you asking about?',source:'clarification'};
 if(['recall','warranty','contact','map_policy'].includes(type)){
  const specs:Record<string,[string,string[]]>={
   recall:['aiq_recalls',['title','hazard','recall_date','units_affected','remedy','url','model_numbers']],
   warranty:['aiq_warranty_policies',['category','full_coverage_years','full_coverage_notes','component_warranties','key_exclusions','last_verified_date']],
   contact:['aiq_vendor_contacts',['country','customer_service_phone','customer_service_phone_label','customer_service_hours','service_repair_phone','warranty_phone','support_email','service_portal_url','confidence_level']],
   map_policy:['brand_map_policies',['brand_name','map_enforced','online_price_display','cart_pricing_allowed','map_policy_notes','violation_consequences']],
  };[source,columns]=specs[type];
  for(const brand of matched){const found=await read(db.from(source).select(columns.join(',')).ilike('brand_name',brand.brand_name).limit(20));rows.push(...found.map((r:any)=>({brand_name:brand.brand_name,...r})));}
  columns=['brand_name',...columns];
 }else if(type==='spec'){
  source='aiq_products_app';columns=['brand_name','model','country_availability','market','category','short_description','width_inches','height_inches','depth_inches','depth_with_handles','capacity_cu_ft','energy_star','installation_type','voltage','amperage','msrp','sale_price','price_currency','price_checked_at','finish'];
  for(const model of models)rows.push(...await read(db.from(source).select(columns.join(',')).ilike('model',model).limit(3)));
  if(!models.length&&matched.length)return {ok:false,data:'Please provide the exact model number for measured specifications.',source:'clarification'};
 }else if(type==='installation'){
  source='installation_requirements';columns=['product_category','subcategory','country','electrical_voltage','electrical_amperage','electrical_circuit','gas_connection','water_connection','drain_required','ventilation_cfm','min_clearances','licensed_trades_required','common_issues','notes'];
  const categories=['range','refrigerator','dishwasher','washer','dryer','cooktop','wall oven','hood','microwave','freezer'];const category=categories.find(c=>lower.includes(c));
  if(!category)return {ok:false,data:'Which appliance category and exact model need installation requirements?',source:'clarification'};
  rows=await read(db.from(source).select(columns.join(',')).eq('country',country).ilike('product_category','%'+category+'%').limit(10));
 }else if(type==='selling_angles'){
  source='mfr_vendors';columns=['name','rightFor','sellingAngles','specGuides'];
  for(const brand of matched)rows.push(...await read(db.from(source).select(columns.join(',')).ilike('name',brand.brand_name).limit(1)));
 }else if(type==='lifecycle'){
  source='product_lifecycle';columns=['brand_name','model_number','product_name','category','lifecycle_status','announced_date','launch_date','discontinued_date','end_of_life_date','predecessor_model','successor_model','changes_from_predecessor','notes'];
  for(const model of models)rows.push(...await read(db.from(source).select(columns.join(',')).ilike('model_number',model).limit(3)));
  if(!models.length)for(const brand of matched)rows.push(...await read(db.from(source).select(columns.join(',')).ilike('brand_name',brand.brand_name).limit(10)));
 }else if(type==='cross_reference'){
  source='competitive_cross_reference';columns=['category','comparison_notes',...Array.from({length:6},(_,i)=>['brand'+(i+1)+'_id','brand'+(i+1)+'_model','brand'+(i+1)+'_notes']).flat()];
  if(!matched.length)return {ok:false,data:'Which brands should I check in the stored comparison guide?',source:'clarification'};
  const filters=matched.flatMap((b:any)=>Array.from({length:6},(_,i)=>'brand'+(i+1)+'_id.eq.'+b.id));
  rows=await read(db.from(source).select(columns.join(',')).or(filters.join(',')).limit(10));
  for(const row of rows)for(let i=1;i<=6;i++){const key='brand'+i+'_id';row['brand'+i]=brands.find((b:any)=>b.id===row[key])?.brand_name??'Unresolved brand';delete row[key];}
  columns=['category','comparison_notes',...Array.from({length:6},(_,i)=>['brand'+(i+1),'brand'+(i+1)+'_model','brand'+(i+1)+'_notes']).flat()];
 }else return {ok:false,data:'This lookup needs a more specific brand, model or category.',source:'clarification'};
 const caveat=type==='recall'?'No matching stored notice does not establish that a product is recall-free. Verify the exact model against the current official notice.':type==='installation'?'These are stored category guidelines. Exact installation and clearance must follow the current manufacturer model-specific guide.':type==='spec'?'Use the stored currency, market and price check date. Current price, market availability and fit require verification.':'Use the stored verification date and confidence; missing evidence is unknown.';
 return {ok:rows.length>0,data:rows.length?format('Stored '+readable(type)+' evidence',rows.slice(0,20),columns)+'\n\n'+caveat:'No matching reviewed evidence is on file. '+caveat,source};
}
export async function crossAppContext(message:string,db:any,org:string,sourceUser:string,user:any){
 const lower=message.toLowerCase();const sections:string[]=[];
 if(/\b(deal|pipeline|customer|lead|follow.?up|crm|close)\b/.test(lower)){
  const rows=await read(db.from('crm_deals').select('title,stage,value_amount,value_currency,updated_at').eq('organization_id',org).is('deleted_at',null).eq('is_archived',false).order('updated_at',{ascending:false}).limit(15));if(rows.length)sections.push(format('Visible CRM deals',rows,['title','stage','value_amount','value_currency','updated_at']));
 }
 if(/\b(training|progress|certification|quiz|academy|course|module)\b/.test(lower)){
  for(const [table,cols,order] of [['academy_brand_progress','brand_id,level,module_key,completed_at','completed_at'],['academy_brand_certifications','brand_id,tier,awarded_at,expires_at','awarded_at'],['academy_brand_quiz_scores','brand_id,level,score,total,passed,completed_at','completed_at']]){
   const rows=await read(db.from(table).select(cols).eq('user_id',sourceUser).order(order,{ascending:false}).limit(10));if(rows.length)sections.push(format(table,rows,cols.split(',')));
  }
 }
 if(/\b(package|quote|proposal|spec iq)\b/.test(lower)){
  const rows=await read(db.from('speciq_packages').select('package_name,status,total_final,approval_status,created_at').eq('organization_id',org).is('deleted_at',null).order('created_at',{ascending:false}).limit(10));if(rows.length)sections.push(format('Visible Spec IQ packages',rows,['package_name','status','total_final','approval_status','created_at']));
 }
 if(/\b(up system|queue|rotation|shift|greeter)\b/.test(lower)){
  const rows=await read(db.from('iq_up_queue_entries').select('user_id,queue_position,is_current_up,is_next_in_line,status_code').eq('organization_id',org).order('queue_position').limit(10));if(rows.length){const profiles=await user.rpc('tj_runtime_get_org_member_profiles',{p_org_id:org});if(profiles.error)throw new Error('scoped_queue_names_unavailable');for(const row of rows)row.staff_name=(profiles.data??[]).find((p:any)=>p.user_id===row.user_id)?.display_name??'Name unavailable';sections.push(format('Visible UP queue',rows,['staff_name','queue_position','is_current_up','is_next_in_line','status_code']));}
 }
 if(/\b(field|store walk|checklist|inspection|audit)\b/.test(lower)){
  const clients=await read(db.from('field_clients').select('id').eq('organization_id',org).limit(100));
  if(clients.length){const visits=await read(db.from('field_visits').select('id').in('client_id',clients.map((r:any)=>r.id)).order('created_at',{ascending:false}).limit(20));if(visits.length){const rows=await read(db.from('field_checklist_responses').select('response,notes,flagged,responded_at').in('visit_id',visits.map((r:any)=>r.id)).order('created_at',{ascending:false}).limit(8));if(rows.length)sections.push(format('Visible field responses',rows,['response','notes','flagged','responded_at']));}}
 }
 return sections.length?'\nVISIBLE ECOSYSTEM EVIDENCE:\n'+sections.join('\n\n').slice(0,8000):'';
}
