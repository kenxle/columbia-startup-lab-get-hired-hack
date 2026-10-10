import test from 'node:test';
import assert from 'node:assert/strict';
import {inches, spruceBolts, spruceHardware, wicksRows} from './parse_sources.mjs';

test('mixed fractions normalize but date-corrupted dimensions remain unknown', () => {
  assert.equal(inches('1-9/32'), 1.28125);
  assert.equal(inches('1 9/32'), 1.28125);
  assert.equal(inches('.203'), 0.203);
  for (const x of ['16-jan','1-4-2028','1/5/2008','', '3/0']) assert.equal(inches(x), null);
});
function spruceFixture(price=0.8, unit='Piece') {
  const product = Array(28).fill(null);
  product[1]='Synthetic drilled bolt'; product[2]=0.8; product[27]=unit;
  return `var products = ${JSON.stringify({'AN3-3':product})};\nvar stock = ${JSON.stringify({'AN3-3':{'10':{avail:2},cofc:'Y','8130':'N'}})};\n<tr><td>-3</td><td>15/32</td><td>1/16</td><td><b>$${price}</b><input pn='AN3-3'></td></tr>`;
}
test('supplier table and embedded product price must agree', () => {
  const [record]=spruceBolts(spruceFixture());
  assert.equal(record.price,0.8); assert.equal(record.in_stock,true);
  assert.throws(()=>spruceBolts(spruceFixture(1.2)), /mismatch/);
});
test('pack offers cannot silently become one-piece observations', () => {
  assert.throws(()=>spruceBolts(spruceFixture(0.8,'Pack of 25')), /mismatch/);
});
test('Wicks extraction keeps corrupted source values and out-of-stock status', () => {
  const html='<tr><span itemprop="sku">AN4-3A</span><td data-field-name="length grip" data-field-value="16-jan"></td><td class="list-price">$0.41</td><span class="stockMessage2">Out of Stock</span></tr>';
  const [record]=wicksRows(html);
  assert.equal(record.fields['length grip'],'16-jan');
  assert.equal(record.price,0.41); assert.equal(record.in_stock,false);
});

test('Wicks conflicting embedded price cannot become market evidence',()=>{
  const html='<tr><span itemprop="sku">MS35206-217</span><meta itemprop="lowPrice" content="0.16"><td class="list-price">$0.42</td></tr>';
  assert.equal(wicksRows(html).length,0);
});

test('a mislabeled standard screw table row is rejected',()=>{
  const p=Array(28).fill(null);p[1]='Synthetic screw';p[2]=0.12;p[27]='Each';
  const html=`var products = ${JSON.stringify({'MS35206-217':p})};\nvar stock = {};\n<tr><td>MS35206-218</td><td>1/2</td><td>$0.12</td><td><input pn='MS35206-217'></td></tr>`;
  assert.equal(spruceHardware(html).length,0);
});

test('same screw SKU with conflicting lengths is rejected',()=>{
  const p=Array(28).fill(null);p[1]='Synthetic screw';p[2]=0.12;p[27]='Each';
  const row=length=>`<tr><td>MS35206-217</td><td>${length}</td><td>$0.12</td><td><input pn='MS35206-217'></td></tr>`;
  const html=`var products = ${JSON.stringify({'MS35206-217':p})};\nvar stock = {};\n${row('1/2')}${row('3/4')}`;
  assert.equal(spruceHardware(html).length,0);
});
