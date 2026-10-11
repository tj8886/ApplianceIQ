import assert from 'node:assert/strict';
import {fetchLiveProducts,publicSpecs} from '../../supabase/functions/_shared/live-pim-products.ts';
let rows=[],queries=[];
function catalog(){return {from(table){assert.equal(table,'aiq_products_app');let filters=[];const q={select(){return q},eq(k,v){filters.push([k,v]);return q},in(k,v){filters.push([k,v]);return q},or(v){filters.push(['models',v]);return q},order(){return q},async limit(){queries.push(filters);return {data:rows}}};return q}};}
const yesterday=new Date(Date.now()-86400000).toISOString(),now=new Date().toISOString();
rows=[{id:'ca',model:'ABC123',brand_name:'Bosch',category:'dishwashers',market:'CA',source_extracted_at:yesterday,updated_at:now,specs_json:{quiet:false,width:0,dealer_cost:99,nested:{api_secret:'private',cycles:5}}},
 {id:'part',model:'ABC123',category:'parts'}, {id:'future',model:'ABC123',category:'dishwashers',source_extracted_at:new Date(Date.now()+86400000).toISOString()}];
let result=await fetchLiveProducts(catalog(),'Tell me about ABC123');assert.equal(result.length,1);assert.equal(result[0].source_extracted_at,yesterday);assert.deepEqual(result[0].specs_json,{quiet:false,width:0,nested:{cycles:5}});
assert.ok(queries[0].some(([k,v])=>k==='models'&&v==='model.ilike.ABC123'));
assert.ok(queries[0].some(([k,v])=>k==='is_parts_accessory'&&v===false));assert.ok(queries[0].some(([k,v])=>k==='approval_status'&&v==='approved'));
rows[0]={...rows[0],specs_json:{cycles:7}};result=await fetchLiveProducts(catalog(),'ABC123');assert.equal(result[0].specs_json.cycles,7);
assert.deepEqual(await fetchLiveProducts(catalog(),'General sales technique'),[]);
await fetchLiveProducts(catalog(),'Compare Bosch dishwashers',['Bosch']);assert.ok(queries.at(-1).some(([k])=>k==='brand_name'));
assert.equal(publicSpecs({private_price:100,current_price:150,features:{water:false}}).features.water,false);
console.log('Live PIM checks passed: model-only matching, fresh reads on repeated requests, market/source-date preservation, parts/future-date exclusion and private-field removal.');
