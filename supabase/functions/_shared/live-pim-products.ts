// Read through the caller's RLS session, never a service client or a persisted bot snapshot.
export const PIM_PRODUCT_COLUMNS = 'id,brand_name,model,category,short_description,long_description,specs_json,finish,width_inches,height_inches,depth_inches,capacity_cu_ft,fuel_type,market,source_extracted_at,updated_at,source_review_status';
export function applianceRecord(p: any): boolean {
  const category=String(p.category??'').toLowerCase().replace(/[\s_-]+/g,'');
  return /^(refrigerators?|freezers?|dishwashers?|ranges?|cooktops?|wallovens?|ovens?|hoods?|rangehoods?|ventilation|microwaves?|washers?|dryers?|laundry|winestorage|winecoolers?|beveragecenters?|compactappliances)$/.test(category)
    && !/^\s*(this\s+|replacement\s+|genuine\s+|universal\s+|the\s+)?(water filter|filter cartridge|trim kit|stacking kit|pedestal|hose|accessory)\b/i.test(String(p.short_description??''));
}
export function publicSpecs(value: any): any {
  if(Array.isArray(value))return value.slice(0,40).map(publicSpecs);
  if(value&&typeof value==='object')return Object.fromEntries(Object.entries(value).filter(([key])=>!/(cost|margin|dealer|wholesale|token|secret|password|price)/i.test(key)).slice(0,60).map(([key,v])=>[key,publicSpecs(v)]));
  return value;
}
export async function fetchLiveProducts(catalog:any,prompt:string,brands:string[]=[]):Promise<any[]> {
  const tokens=[...new Set(prompt.match(/[A-Za-z0-9][A-Za-z0-9-]{2,59}/g)??[])].filter(t=>/[a-z]/i.test(t)&&/\d/.test(t)).slice(0,8);
  if(!tokens.length&&!brands.length)return [];
  let query=catalog.from('aiq_products_app').select(PIM_PRODUCT_COLUMNS).eq('status','active').eq('approval_status','approved').eq('is_parts_accessory',false).in('source_review_status',['accepted','not_required','approved','pending','pending_review']);
  if(tokens.length)query=query.or(tokens.map(t=>'model.ilike.'+t).join(','));
  else if(brands.length)query=query.in('brand_name',brands);
  else return [];
  const {data,error}=await query.order('source_extracted_at',{ascending:false,nullsFirst:false}).order('updated_at',{ascending:false}).limit(24);
  if(error)throw Error('scoped_catalog_context_failed');
  return (data??[]).filter(applianceRecord).filter((p:any)=>![p.source_extracted_at,p.updated_at].some(d=>d&&new Date(d).getTime()>Date.now()+300000)).slice(0,12).map((p:any)=>({...p,specs_json:publicSpecs(p.specs_json)}));
}
export function productEvidenceText(products:any[]):string {
  if(!products.length)return 'No eligible appliance model evidence matched. Do not infer missing model facts from a brand or old conversation.';
  return products.map(p=>JSON.stringify({...p,long_description:String(p.long_description??'').slice(0,1600)})).join('\n').slice(0,18000);
}
