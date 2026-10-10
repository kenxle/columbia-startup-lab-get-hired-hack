import fs from 'node:fs';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spruceBolts,wicksRows,inches} from './parse_sources.mjs';

const root='data/aviation';
const read=name=>JSON.parse(fs.readFileSync(`${root}/${name}.json`,'utf8'));
const catalog=read('catalog'), observations=read('price_observations'), sources=read('source_manifest'), summary=read('summary');
assert.equal(catalog.length,200); assert.equal(observations.length,400);
assert.equal(new Set(catalog.map(i=>i.part_number)).size,200);
assert.equal(new Set(observations.map(o=>o.observation_id)).size,400);
const parsed=new Map();
for(const sid of summary.sources_used){
  const s=sources.find(s=>s.id===sid); assert.ok(s);
  const html=fs.readFileSync(`${root}/${s.raw_file}`,'utf8');
  assert.equal(crypto.createHash('sha256').update(html).digest('hex'),s.sha256);
  parsed.set(sid,new Map((sid.startsWith('spruce')?spruceBolts(html):wicksRows(html)).map(x=>[x.pn,x])));
}
for(const i of catalog){
  const offers=i.observation_ids.map(id=>observations.find(o=>o.observation_id===id));
  assert.equal(offers.length,2); assert.equal(new Set(offers.map(o=>o.supplier)).size,2);
  assert.equal(i.quote_ready,false); assert.equal(i.suggested_quote_price_usd_each,null);
  assert.ok(i.nominal_length_in>0&&i.grip_length_in>0&&i.nominal_length_in>i.grip_length_in);
  for(const o of offers){
    assert.equal(o.supplier_part_number,i.part_number); assert.ok(o.advertised_price_usd>0);
    assert.equal(o.pack_quantity,1); assert.equal(o.comparison_quantity,1); assert.equal(o.stock_reported,true);
    assert.equal(o.formal_quote,false); assert.equal(o.country_of_origin,null);
    const r=parsed.get(o.source_id).get(i.part_number); assert.ok(r);
    assert.equal(r.price,o.advertised_price_usd);
    assert.equal(inches(o.nominal_length_source),i.nominal_length_in);
    assert.equal(inches(o.grip_length_source),i.grip_length_in);
  }
  assert.equal(i.market_reference.min_usd_each,Math.min(...offers.map(o=>o.advertised_price_usd)));
  assert.equal(i.market_reference.max_usd_each,Math.max(...offers.map(o=>o.advertised_price_usd)));
  assert.equal(i.market_reference.midpoint_usd_each,Math.round(offers.reduce((n,o)=>n+o.advertised_price_usd,0)/2*10000)/10000);
}
const md=fs.readFileSync('docs/data/AVIATION_ITEMS_200.md','utf8');
assert.equal((md.match(/^\| AVI-\d{3} \|/gm)||[]).length,200);
console.log('PASS: 200 unique items, 400 source-verified observations, matched dimensions, stock, units, arithmetic, source hashes, and 200 rendered list rows.');
