// Extract facts from saved public supplier pages. Never execute supplier scripts.
export function text(html) {
  return html.replace(/<[^>]*>/g, ' ').replace(/&nbsp;|&#160;/g, ' ').replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/\s+/g, ' ').trim();
}
export function inches(value) {
  const s = value.trim().replace(/^(\d+)-(\d+\/\d+)$/, '$1 $2');
  if (/^\d*\.?\d+$/.test(s)) return Number(s);
  const m = s.match(/^(?:(\d+)\s+)?(\d+)\/(\d+)$/);
  if (!m || Number(m[3]) === 0) return null;
  return Number(m[1] || 0) + Number(m[2]) / Number(m[3]);
}
export function scriptObject(html, name) {
  const m = html.match(new RegExp(`var ${name} = (\\{[^\\n]*\\});`));
  if (!m) throw new Error(`Missing ${name} object`);
  return JSON.parse(m[1]);
}
export function spruceBolts(html) {
  const products = scriptObject(html, 'products');
  const stock = scriptObject(html, 'stock');
  const records = [];
  for (const match of html.matchAll(/<tr\b[^>]*>[\s\S]*?<\/tr>/gi)) {
    const cells = [...match[0].matchAll(/<td\b[^>]*>([\s\S]*?)<\/td>/gi)].map(x => x[1]);
    if (!/^-[0-9]+$/.test(text(cells[0] || ''))) continue;
    for (const cell of cells.slice(3)) {
      const pn = cell.match(/\bpn=['"]([^'"]+)['"]/i)?.[1];
      if (!pn || !/^AN[3-8]C?-\d+A?$/.test(pn)) continue;
      const price = Number(cell.match(/\$([\d.]+)/)?.[1]);
      if (!Number.isFinite(price) || price <= 0) continue;
      if (!products[pn] || products[pn][2] !== price || !['Piece', 'Each'].includes(products[pn][27])) throw new Error(`Price or unit mismatch for ${pn}`);
      const warehouses = Object.values(stock[pn] || {}).filter(x => typeof x === 'object' && x !== null && 'avail' in x);
      records.push({pn, price, unit: 'Piece', quantity: 1, length: text(cells[1]), grip: text(cells[2]), title: products[pn][1], in_stock: warehouses.some(x => Number(x.avail) > 0), cofc: stock[pn]?.cofc ?? null, form_8130: stock[pn]?.['8130'] ?? null});
    }
  }
  return records;
}
export function wicksRows(html) {
  const records = [];
  for (const match of html.matchAll(/<tr\b[^>]*>[\s\S]*?<\/tr>/gi)) {
    const row = match[0];
    const pn = row.match(/<span itemprop="sku">([^<]+)<\/span>/)?.[1];
    if (!pn) continue;
    const price = Number(row.match(/<td class="list-price">[\s\S]*?\$([\d.]+)/)?.[1]);
    if (!Number.isFinite(price) || price <= 0) continue;
    const schemaPrice=Number(row.match(/itemprop="lowPrice" content="([\d.]+)"/)?.[1]);
    const variationPrice=Number(row.match(/name="variation_price" value="([\d.]+)"/)?.[1]);
    if((Number.isFinite(schemaPrice)&&schemaPrice!==price)||(Number.isFinite(variationPrice)&&variationPrice!==price))continue;
    const fields = {};
    for (const m of row.matchAll(/data-field-name="([^"]+)"\s+data-field-value="([^"]*)"/g)) fields[m[1]] = m[2];
    records.push({pn, price, fields, price_crosschecked:Number.isFinite(schemaPrice)||Number.isFinite(variationPrice), in_stock: /Qty in Stock:\s*[1-9]/.test(text(row)), stock_text: text(row.match(/class="stockMessage2">([\s\S]*?)<\/span>/)?.[1] || ''), material_cert_fee: Number(row.match(/data-raw-price="([\d.]+)"[^>]*data-label="Materials Cert"/)?.[1]) || null});
  }
  return records;
}

// One-row-per-SKU tables used by screws, nuts and other standard hardware.
// Price must agree with the supplier's embedded product record, and packs
// must never be treated as individual pieces.
export function spruceHardware(html) {
  const products = scriptObject(html, 'products');
  const stock = scriptObject(html, 'stock');
  const records = [];
  for (const match of html.matchAll(/<tr\b[^>]*>[\s\S]*?<\/tr>/gi)) {
    const cells = [...match[0].matchAll(/<td\b[^>]*>([\s\S]*?)<\/td>/gi)].map(x=>x[1]);
    const partInputs = [...match[0].matchAll(/\bpn=['"]([^'"]+)['"]/g)];
    if (partInputs.length !== 1) continue;
    const pn = partInputs[0][1];
    if (!/^(MS|AN)\d/.test(pn)) continue;
    const p = products[pn];
    if (!p || !['Piece','Each'].includes(p[27]) || /\bpack\b|\bbox\b/i.test(p[1])) continue;
    const prices = cells.map(c=>Number(c.match(/\$([\d.]+)/)?.[1])).filter(n=>Number.isFinite(n)&&n>0);
    if (prices.length !== 1 || prices[0] !== p[2]) continue;
    const fields = cells.map(text).filter(x=>x!=='Quantity');
    if (!fields.some(x=>x===pn)) continue; // Do not trust a mislabeled table row.
    const warehouses = Object.values(stock[pn] || {}).filter(x=>typeof x==='object'&&x!==null&&'avail' in x);
    records.push({pn, price:p[2], unit:'Each', quantity:1, title:p[1], table_fields:fields,
      in_stock:warehouses.some(x=>Number(x.avail)>0), cofc:stock[pn]?.cofc??null, form_8130:stock[pn]?.['8130']??null});
  }
  // Different specifications for the same SKU indicate a source problem.
  const byPn = new Map();
  for(const r of records) { const a=byPn.get(r.pn)||[]; a.push(r); byPn.set(r.pn,a); }
  return [...byPn.values()].filter(a=>a.every(r=>JSON.stringify(r.table_fields)===JSON.stringify(a[0].table_fields))).map(a=>a[0]);
}

export function spruceClevis(html) {
  const products=scriptObject(html,'products'), stock=scriptObject(html,'stock'), records=[];
  for(const m of html.matchAll(/<tr\b[^>]*>[\s\S]*?<\/tr>/gi)) {
    const cells=[...m[0].matchAll(/<td\b[^>]*>([\s\S]*?)<\/td>/gi)].map(x=>x[1]);
    if(!/^-[0-9]+$/.test(text(cells[0]||''))) continue;
    for(const cell of cells.slice(3)) {
      const pn=cell.match(/\bpn=['"]([^'"]+)['"]/i)?.[1], price=Number(cell.match(/\$([\d.]+)/)?.[1]);
      if(!pn||!/^AN2[3-5]-\d+A?$/.test(pn)||!Number.isFinite(price)||price<=0) continue;
      const p=products[pn];
      if(!p||p[2]!==price||!['Each','Piece'].includes(p[27])||/surplus|pack/i.test(p[1])) continue;
      const warehouses=Object.values(stock[pn]||{}).filter(x=>typeof x==='object'&&x!==null&&'avail' in x);
      records.push({pn,price,unit:'Each',quantity:1,title:p[1],length:text(cells[2]),grip:text(cells[1]),in_stock:warehouses.some(x=>Number(x.avail)>0),cofc:stock[pn]?.cofc??null,form_8130:stock[pn]?.['8130']??null});
    }
  }
  return records;
}

export function spruceWashers(html) {
  const products=scriptObject(html,'products'),stock=scriptObject(html,'stock'),records=[];
  for(const m of html.matchAll(/<tr\b[^>]*>[\s\S]*?<\/tr>/gi)) {
    const cells=[...m[0].matchAll(/<td\b[^>]*>([\s\S]*?)<\/td>/gi)].map(x=>x[1]);
    const pn=m[0].match(/\bpn=['"]([^'"]+)['"]/i)?.[1];
    if(!pn||!/^AN970/.test(pn))continue;
    const p=products[pn],price=Number(cells[6]?.match(/\$([\d.]+)/)?.[1]);
    if(!p||p[2]!==price||!['Each','Piece'].includes(p[27])||/pack|box/i.test(p[1]))continue;
    const warehouses=Object.values(stock[pn]||{}).filter(x=>typeof x==='object'&&x!==null&&'avail' in x);
    records.push({pn,price,unit:'Each',quantity:1,title:p[1],table_fields:cells.slice(0,6).map(text),in_stock:warehouses.some(x=>Number(x.avail)>0),cofc:stock[pn]?.cofc??null,form_8130:stock[pn]?.['8130']??null});
  }
  return records;
}

export function sprucePlainNuts(html) {
  const products=scriptObject(html,'products'),stock=scriptObject(html,'stock'),records=[];
  for(const m of html.matchAll(/<tr\b[^>]*>[\s\S]*?<\/tr>/gi)) {
    const cells=[...m[0].matchAll(/<td\b[^>]*>([\s\S]*?)<\/td>/gi)].map(x=>x[1]);
    if(!/^AN31[56]-/.test(text(cells[0]||'')))continue;
    for(const index of [3,5]) {
      const pn=cells[index]?.match(/\bpn=['"]([^'"]+)['"]/i)?.[1],price=Number(cells[index-1]?.match(/\$([\d.]+)/)?.[1]);
      if(!pn||!/^AN31[56]-\d+[RL]$/.test(pn))continue;
      const p=products[pn];
      if(!p||p[2]!==price||!['Each','Piece'].includes(p[27])||/pack|box/i.test(p[1]))continue;
      const warehouses=Object.values(stock[pn]||{}).filter(x=>typeof x==='object'&&x!==null&&'avail' in x);
      records.push({pn,price,unit:'Each',quantity:1,title:p[1],table_fields:[text(cells[0]),text(cells[1])],hand:pn.endsWith('R')?'Right':'Left',in_stock:warehouses.some(x=>Number(x.avail)>0),cofc:stock[pn]?.cofc??null,form_8130:stock[pn]?.['8130']??null});
    }
  }
  return records;
}
