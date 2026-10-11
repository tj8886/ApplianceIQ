import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import {migratePimConsumers} from './us-pim-consumers.mjs';
const academy=migratePimConsumers(readFileSync(new URL('../../apps/iq-training/index.html',import.meta.url),'utf8'),'academy');
const spec=migratePimConsumers(readFileSync(new URL('../../apps/spec-iq/index.html',import.meta.url),'utf8'),'spec-iq');
for(const html of [academy,spec])for(const match of html.matchAll(/<script([^>]*)>([\s\S]*?)<\/script>/g))if(match[2].trim()){if(/type=[\"']module[\"']/.test(match[1]))new vm.SourceTextModule(match[2]);else new vm.Script(match[2]);}
const loader=academy.slice(academy.indexOf('async function loadBrandProducts'),academy.indexOf('\n// ═',academy.indexOf('async function loadBrandProducts')));
let description='Current description';const queries=[];
const sb={from(table){let filters=[];const q={select(){return q},eq(k,v){filters.push([k,v]);return q},in(){return q},ilike(){return q},contains(){return q},order(){return q},limit(){return q},maybeSingle(){return q},then(resolve){queries.push({table,filters});resolve({data:table==='brand_catalog'?{brand_name:'Bosch'}:table==='iq_product_cards'?[{card_type:'brand_intro',content:{brand_story:'Retained lesson'}}]:table==='pim_product_images'?[]:[{id:'one',model:'ABC123',category:'dishwashers',market:'CA',long_description:description,source_extracted_at:'2026-10-10T12:00:00Z',updated_at:'2026-10-10T12:00:00Z'}]});}};return q}};
const ctx=vm.createContext({sb,Date});new vm.Script(loader+';this.read=loadBrandProducts').runInContext(ctx);
let cards=await ctx.read('brand');assert.equal(cards[1].content.long_description,'Current description');assert.equal(cards[1].content.msrp,undefined);assert.equal(cards[0].content.brand_story,'Retained lesson');
description='Updated through PIM';cards=await ctx.read('brand');assert.equal(cards[1].content.long_description,description);assert.equal(cards[1].content.market,'CA');assert.equal(cards[1].content.source_extracted_at,'2026-10-10T12:00:00Z');
assert.ok(queries.some(q=>q.table==='aiq_products'&&q.filters.some(([k,v])=>k==='is_parts_accessory'&&v===false)));
assert.ok(spec.includes('is_parts_accessory=eq.false'));assert.ok(spec.includes('source_extracted_at.desc.nullslast'));assert.ok(!academy.includes('// PIM — latest products'));
console.log('PIM consumer checks passed: full inline script parsing, repeated Academy reads see changed PIM descriptions, brand lessons retained, market/source dates retained, no undated current price, appliance-only Spec IQ search.');
