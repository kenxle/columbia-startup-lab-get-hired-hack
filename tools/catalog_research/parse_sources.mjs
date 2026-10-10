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
    const fields = {};
    for (const m of row.matchAll(/data-field-name="([^"]+)"\s+data-field-value="([^"]*)"/g)) fields[m[1]] = m[2];
    records.push({pn, price, fields, in_stock: /Qty in Stock:\s*[1-9]/.test(text(row)), stock_text: text(row.match(/class="stockMessage2">([\s\S]*?)<\/span>/)?.[1] || ''), material_cert_fee: Number(row.match(/data-raw-price="([\d.]+)"[^>]*data-label="Materials Cert"/)?.[1]) || null});
  }
  return records;
}
