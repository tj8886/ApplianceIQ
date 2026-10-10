// US bundle fixes based on the existing canonical routes and live FK contract.
export function omitObsoleteWarrantyCleanup(source){
 const pattern=/^[ \t]*await sb\.from\('speciq_package_warranties'\)\.delete\(\)\.eq\('package_id',(?:pkg\.id|editId|pkgId)\);\r?\n/gm;
 if([...source.matchAll(pattern)].length!==3)throw Error('Spec IQ warranty cleanup source contract changed');
 return source.replace(pattern,'');
}
export function routeLegacyProductIq(source){
 const pattern=/<script>\s*const \{createClient\}=supabase;[\s\S]*?\binit\(\);\s*<\/script>/;
 if(!pattern.test(source)||!source.includes("from('aiq_product_specifications')"))throw Error('Legacy Product IQ source contract changed');
 return source.replace(pattern,()=>`<script>
 const target=new URL('/pim.html',location.origin);
 target.search=location.search;
 if(location.hash.startsWith('#aiq_ticket='))target.hash=location.hash;
 location.replace(target.href);
 </script>`).replace('Loading Product IQ…','Opening Product IQ… <a href="/pim.html">Open the dashboard</a>');
}
export function surfaceManufacturerAssetErrors(source){
 const start=source.indexOf('async function loadAssets(){'),end=source.indexOf('function renderCatGroups(){',start);
 if(start<0||end<0)throw Error('Manufacturer library source contract changed');
 return (source.slice(0,start)+`async function loadAssets(){
 try{
 const {data,error}=await sb.from('mfr_assets').select('*').eq('vendor_id',ACTIVE_VENDOR.id).order('created_at',{ascending:false});
 if(error)throw Error('asset_query_failed');
 ASSETS=data||[];renderCatGroups();
 }catch{ASSETS=[];document.getElementById('cat-groups').textContent='The content library could not be loaded. Try again or contact the ApplianceIQ team.';}
}
`+source.slice(end)).replace('${f.title}','${mfrEscape(f.title)}');
}
