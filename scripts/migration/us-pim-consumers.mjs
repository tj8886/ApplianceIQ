// Generated US clients keep the existing workflows but read appliance facts live.
const eligiblePimAppliance=p=>/^(refrigerators?|freezers?|dishwashers?|ranges?|cooktops?|wallovens?|ovens?|hoods?|rangehoods?|ventilation|microwaves?|washers?|dryers?|laundry|winestorage|winecoolers?|beveragecenters?|compactappliances)$/.test(String(p.category||'').toLowerCase().replace(/[\s_-]+/g,''))&&!/^\s*(this\s+|replacement\s+|genuine\s+|universal\s+|the\s+)?(water filter|filter cartridge|trim kit|stacking kit|pedestal|hose|accessory)\b/i.test(p.short_description||p.long_description||'')&&![p.source_extracted_at,p.updated_at].some(d=>d&&new Date(d).getTime()>Date.now()+300000);
export function migratePimConsumers(source,app){
 if(app==='spec-iq'){
  source=source.replace("var cols='id,brand_name,model,short_description,category,finish,msrp,width_inches,height_inches,depth_inches,voltage,amperage';", "var cols='id,brand_name,model,short_description,long_description,category,finish,msrp,width_inches,height_inches,depth_inches,voltage,amperage,source_extracted_at,updated_at';");
  source=source.replace("var params='select='+cols+'&limit=12';", "var params='select='+cols+'&status=eq.active&approval_status=eq.approved&is_parts_accessory=eq.false&source_review_status=in.(accepted,not_required,approved,pending,pending_review)&order=source_extracted_at.desc.nullslast,updated_at.desc&limit=12';");
  source=source.replace("_searchResults=data||[];", "_searchResults=(data||[]).filter("+eligiblePimAppliance.toString()+");");
  source=source.replace("el('ap-name').value=p.short_description||'';", "el('ap-name').value=p.short_description||p.long_description||p.brand_name+' '+p.model;");
  source=source.replace(".eq('product_id',p.id).order('is_primary'", ".eq('product_id',p.id).eq('approved',true).eq('embargoed',false).contains('audience_tiers',['public']).order('is_primary'");
  source=source.replace(".eq('product_id',p.id),", ".eq('product_id',p.id).eq('approved',true).eq('is_current',true).eq('embargoed',false).eq('requires_auth',false),");
 }
 if(app==='academy'){
  const start=source.indexOf('async function loadBrandProducts(brandId) {'),end=source.indexOf('\n// ═',start);
  if(start<0||end<0)throw Error('Academy live PIM loader contract changed');
  source=source.slice(0,start)+`async function loadBrandProducts(brandId) {
  var cards=await sb.from('iq_product_cards').select('*').eq('brand_id',brandId).eq('is_active',true).eq('card_type','brand_intro');
  var brand=await sb.from('brand_catalog').select('brand_name').eq('id',brandId).eq('is_active',true).maybeSingle();
  if(brand.error||!brand.data)throw Error('brand_context_unavailable');
  var result=await sb.from('aiq_products').select('id,model,category,short_description,long_description,finish,width_inches,height_inches,depth_inches,capacity_cu_ft,fuel_type,specs_json,source_extracted_at,updated_at,market').ilike('brand_name',brand.data.brand_name).eq('status','active').eq('approval_status','approved').eq('is_parts_accessory',false).in('source_review_status',['accepted','not_required','approved','pending','pending_review']).order('source_extracted_at',{ascending:false,nullsFirst:false}).order('updated_at',{ascending:false}).limit(60);
  if(result.error)throw Error('pim_products_unavailable');
  var products=(result.data||[]).filter(${eligiblePimAppliance.toString()});
  var assets=products.length?await sb.from('pim_product_images').select('product_id,file_url,cdn_url,is_primary').in('product_id',products.map(p=>p.id)).eq('approved',true).eq('embargoed',false).contains('audience_tiers',['public']).order('is_primary',{ascending:false}).limit(300):{data:[]};
  return (cards.data||[]).concat(products.map(p=>{var image=(assets.data||[]).find(x=>x.product_id===p.id&&/^https:\\/\\//i.test(x.cdn_url||x.file_url||''));return {product_id:p.id,card_type:'product_spotlight',title:p.model,content:{...p,image_url:image?(image.cdn_url||image.file_url).replaceAll('&amp;','&'):null}};}));
}
`+source.slice(end);
  source=source.replace('  var products = await loadBrandProducts(brand.brand_id);', "  var products;try{products=await loadBrandProducts(brand.brand_id);}catch{el.textContent='Live product information could not be loaded. Please try again.';return;}");
  source=source.replace("      + (sellingPoints.length ?", "      + '<p style=\"font-size:13px;color:var(--text2)\">'+esc(c.short_description||c.long_description||'')+'</p>'\n      + '<div style=\"font-size:11px;color:var(--text3);margin-bottom:8px\">'+esc(c.market||'')+' · Source date: '+esc(c.source_extracted_at?new Date(c.source_extracted_at).toLocaleDateString():'not recorded')+'</div>'\n      + (sellingPoints.length ?");
  // Product facts are retrieved server-side for every bot turn, including model-only questions.
  const from=source.indexOf('    // PIM — latest products'),to=source.indexOf('    // CCR',from);
  if(from<0||to<0)throw Error('Academy cached PIM context contract changed');
  source=source.slice(0,from)+"    ctx.push('Appliance model facts must come from the live server PIM lookup for this turn. Static lessons and old chat are not current evidence.');\n"+source.slice(to);
  source=source.replace("  var c = coaches[rpState.coach];\n  var sysPrompt = '';", "  var c = coaches[rpState.coach];\n  try{rpState.context=await loadCrossAppContext();}catch{rpState.context='Context unavailable; do not guess.';}\n  var sysPrompt = '';");
 }
 return source;
}
