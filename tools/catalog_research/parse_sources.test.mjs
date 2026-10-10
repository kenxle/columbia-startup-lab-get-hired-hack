import test from 'node:test';
import assert from 'node:assert/strict';
import {inches, spruceBolts, wicksRows} from './parse_sources.mjs';

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
