export const technicalHelpers=`
function speciqTechnicalPayload(p){
 if(p.aiq_product_id)return {};
 const dimension=v=>{if(v==null||v==='')return null;const s=String(v);if(!/^[0-9]{1,3}(\\.[0-9]{1,3})?$/.test(s)||Number(s)<=0||Number(s)>999.999)throw Error('Dimensions must be positive inches, at most 999.999 with three decimals.');return s;};
 const docs=(p.docs||[]).map(d=>({doc_type:d.doc_type||'document',title:d.title||null,file_url:d.file_url}));
 if(p.spec_sheet_url&&!docs.some(d=>d.file_url===p.spec_sheet_url))docs.push({doc_type:'spec_sheet',title:'Specification sheet',file_url:p.spec_sheet_url});
 if(p.install_guide_url&&!docs.some(d=>d.file_url===p.install_guide_url))docs.push({doc_type:'installation_guide',title:'Installation guide',file_url:p.install_guide_url});
 return {finish:p.finish||null,width_inches:dimension(p.width_inches),height_inches:dimension(p.height_inches),depth_inches:dimension(p.depth_inches),electrical_requirements:p.electrical_requirements||null,product_image:p.product_image||null,brand_logo:p.brand_logo||null,specifications:p.specifications||null,docs};
}
function speciqTechnicalPreview(products){
 return '<section><h3>Technical details</h3>'+products.map(p=>{const t=p.spec_snapshot?.technical||{},dims=[['Width',p.width_inches],['Height',p.height_inches],['Depth',p.depth_inches]].filter(([,v])=>v!=null).map(([label,v])=>label+': '+esc(v)+' in').join(' · ');return '<article><h4>'+esc(p.product_name)+'</h4><p>'+esc(p.spec_snapshot?.technical_state||'No technical provenance recorded')+'</p><p>'+esc(p.finish||'')+'</p><p>'+dims+'</p><p>'+esc(p.electrical_requirements||'')+'</p>'+(p.specifications?'<pre>'+esc(JSON.stringify(p.specifications,null,2))+'</pre>':'')+(t.docs||[]).filter(d=>typeof d.file_url==='string'&&/^https:\\/\\//.test(d.file_url)).map(d=>'<p><a rel="noopener noreferrer" target="_blank" href="'+esc(d.file_url)+'">'+esc(d.title||d.doc_type)+'</a></p>').join('')+'</article>';}).join('')+'</section>';
}
`;
export function migrateSpeciqTechnical(source){
 let s=source;const payload='quantity:p.quantity||1,warranty_id:p.warranty_id||null}';if(!s.includes(payload))throw Error('Spec IQ technical payload contract changed');s=s.replace(payload,'quantity:p.quantity||1,warranty_id:p.warranty_id||null,previous_product_id:p.previous_product_id||null,technical:speciqTechnicalPayload(p)}');
 const edit='id:Date.now()+Math.random(),aiq_product_id:p.aiq_product_id||null,';if(!s.includes(edit))throw Error('Spec IQ product edit contract changed');s=s.replace(edit,'id:Date.now()+Math.random(),previous_product_id:p.id,specifications:p.specifications||null,aiq_product_id:p.aiq_product_id||null,');
 s=s.replace('product_image:p.product_image||null,brand_logo:p.brand_logo||null,spec_sheet_url:p.spec_sheet_url||null,install_guide_url:p.install_guide_url||null,docs:[],','product_image:p.image_url||null,brand_logo:p.spec_snapshot?.technical?.brand_logo||null,spec_sheet_url:null,install_guide_url:null,docs:p.spec_snapshot?.technical?.docs||[],');
 s=s.replace('const draftProjectDetailFields=',technicalHelpers+'\nconst draftProjectDetailFields=');
 s=s.replace("'<table><thead><tr><th>Product</th>","speciqTechnicalPreview(products)+'<table><thead><tr><th>Product</th>");
 s=s.replace('preview+draftProjectDetailsPreview(project)+decisions','preview+draftProjectDetailsPreview(project)+speciqTechnicalPreview(snapshot.products||[])+decisions');
 return s;
}
