import fs from 'node:fs';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spruceBolts,spruceClevis,spruceHardware,spruceWashers,sprucePlainNuts,wicksRows,inches} from './parse_sources.mjs';

const root='data/aviation',read=name=>JSON.parse(fs.readFileSync(`${root}/${name}.json`,'utf8'));
const catalog=read('catalog'),observations=read('price_observations'),sources=read('source_manifest'),summary=read('summary');
assert.equal(catalog.length,500);assert.equal(observations.length,1000);
assert.equal(new Set(catalog.map(i=>i.part_number)).size,500);
assert.equal(new Set(observations.map(o=>o.observation_id)).size,1000);
const parsed=new Map();
for(const sid of summary.sources_used){
  const source=sources.find(s=>s.id===sid);assert.ok(source);
  const html=fs.readFileSync(`${root}/${source.raw_file}`,'utf8');
  assert.equal(crypto.createHash('sha256').update(html).digest('hex'),source.sha256);
  const parse=sid.startsWith('wicks')?wicksRows:/^spruce-an[3-8]$/.test(sid)?spruceBolts:/^spruce-an2[3-5]$/.test(sid)?spruceClevis:sid==='spruce-an970'?spruceWashers:/^spruce-an31[56]$/.test(sid)?sprucePlainNuts:spruceHardware;
  parsed.set(sid,new Map(parse(html).map(r=>[r.pn,r])));
}
const referenced=[];
for(const item of catalog){
  const offers=item.observation_ids.map(id=>observations.find(o=>o.observation_id===id));
  assert.equal(offers.length,2);assert.equal(new Set(offers.map(o=>o.supplier)).size,2);
  assert.equal(item.quote_ready,false);assert.equal(item.suggested_quote_price_usd_each,null);
  assert.equal(item.specification_verification.readable_conflicts.length,0);
  assert.equal(item.specification_verification.dimensions_verified,item.specification_verification.unverified_fields.length===0);
  for(const offer of offers){
    referenced.push(offer.observation_id);
    assert.equal(offer.canonical_part_number,item.part_number);
    const record=parsed.get(offer.source_id).get(offer.supplier_part_number);assert.ok(record);
    assert.equal(record.price,offer.advertised_price_usd);assert.ok(record.price>0);
    assert.equal(record.in_stock,true);assert.equal(offer.stock_reported,true);
    assert.equal(offer.pack_quantity,1);assert.equal(offer.comparison_quantity,1);assert.equal(offer.currency,'USD');
    assert.equal(offer.formal_quote,false);
    const source=sources.find(s=>s.id===offer.source_id);
    assert.equal(offer.observed_at,source.retrieved_at);assert.equal(offer.source_url,source.url);
    if(offer.supplier==='Wicks Aircraft')assert.equal(record.price_crosschecked,true);
    if(offer.supplier_part_number!==item.part_number){
      assert.match(item.part_number,/^AN31[56]-\d+R$/);
      assert.equal(offer.supplier_part_number,item.part_number.slice(0,-1));
      assert.equal(record.fields['product type'],'Right');assert.ok(offer.sku_mapping_evidence);
    }
  }
  assert.equal(item.market_reference.min_usd_each,Math.min(...offers.map(o=>o.advertised_price_usd)));
  assert.equal(item.market_reference.max_usd_each,Math.max(...offers.map(o=>o.advertised_price_usd)));
  assert.equal(item.market_reference.midpoint_usd_each,Math.round(offers.reduce((n,o)=>n+o.advertised_price_usd,0)/2*10000)/10000);
  for(const gap of item.specification_verification.unverified_fields)assert.ok(gap.reason.includes('no repair inferred'));
  if(item.specification_verification.dimensions_verified&&item.shape.includes('bolt')) {
    assert.equal(inches(offers[0].source_specification_fields.length),inches(offers[1].source_specification_fields['length nominal']));
    assert.equal(inches(offers[0].source_specification_fields.grip),inches(offers[1].source_specification_fields['length grip']));
  }
}
assert.equal(new Set(referenced).size,1000);
const historical=fs.readFileSync('docs/data/AVIATION_ITEMS_200.md','utf8');
const original=[...historical.matchAll(/^\| (AVI-\d{3}) \| ([^|]+) \|/gm)];
assert.equal(original.length,200);
for(const m of original)assert.equal(catalog.find(i=>i.part_number===m[2].trim()).item_id,m[1]);
assert.equal(summary.owner,'Tisch');assert.equal(summary.item_count,500);assert.equal(summary.observation_count,1000);
assert.equal(summary.dimensions_verified_item_count,catalog.filter(i=>i.specification_verification.dimensions_verified).length);
const md=fs.readFileSync('docs/data/AVIATION_ITEMS_500.md','utf8');
assert.equal((md.match(/^\| AVI-\d{3} \|/gm)||[]).length,500);
assert.equal((md.match(/ \| SPEC PENDING \| /g)||[]).length,summary.supplier_specification_confirmation_pending_count);
console.log('PASS: 500 unique real items, 1000 source-verified prices, stock, units, explicit SKU mappings, honest specification holds, original IDs, arithmetic and all source hashes.');
