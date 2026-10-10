import fs from 'node:fs';
import {spruceBolts, wicksRows, inches} from './parse_sources.mjs';

const root = 'data/aviation';
const manifest = JSON.parse(fs.readFileSync(`${root}/source_manifest.json`, 'utf8'));
const source = id => { const x = manifest.find(s => s.id === id); if (!x) throw new Error(`Missing source ${id}`); return x; };
const families = {3: {diameter: 3/16, thread: '10-32'}, 4: {diameter: 1/4, thread: '1/4-28'}, 5: {diameter: 5/16, thread: '5/16-24'}, 6: {diameter: 3/8, thread: '3/8-24'}, 7: {diameter: 7/16, thread: '7/16-20'}, 8: {diameter: 1/2, thread: '1/2-20'}};
const pools = [];
const excluded = [];
for (let n = 3; n <= 8; n++) {
  const sid = `spruce-an${n}`, wid = `wicks-an${n}`;
  const a = spruceBolts(fs.readFileSync(`${root}/raw/${sid}.html`, 'utf8'));
  const w = wicksRows(fs.readFileSync(`${root}/raw/${wid}.html`, 'utf8'));
  const wm = new Map(w.map(x => [x.pn, x]));
  const pool = [];
  for (const x of a) {
    const y = wm.get(x.pn);
    const reasons = [];
    if (!y) { excluded.push({part_number: x.pn, reasons: ['No exact Wicks part number in retrieved family table']}); continue; }
    const isStainless = x.pn.includes('C');
    if (isStainless) reasons.push('Initial catalog selects cadmium-plated alloy steel only');
    if (y.fields.material !== 'Cad Plated') reasons.push(`Material not selected: ${y.fields.material}`);
    const drilled = !x.pn.endsWith('A');
    if (y.fields['product type'] !== (drilled ? 'Drilled Shank' : 'Undrilled Shank')) reasons.push('Drilling designation does not agree');
    for (const [attr, field] of [['length','length nominal'], ['grip','length grip']]) {
      const p = inches(x[attr]), q = inches(y.fields[field] || '');
      if (p === null || q === null) reasons.push(`${attr} unreadable: Spruce=${x[attr]}; Wicks=${y.fields[field] || 'missing'}`);
      else if (Math.abs(p - q) > 0.00001) reasons.push(`${attr} conflict: Spruce=${x[attr]}; Wicks=${y.fields[field]}`);
    }
    if (!x.in_stock || !y.in_stock) reasons.push('Stock not reported by both dealers at retrieval');
    if (reasons.length) { excluded.push({part_number:x.pn, reasons}); continue; }
    pool.push({x,y,n,sid,wid});
  }
  pool.sort((a,b) => inches(a.x.length)-inches(b.x.length) || a.x.pn.localeCompare(b.x.pn));
  pools.push(pool);
}
const selected = [];
// Balanced round-robin across available diameter families. No generated SKUs.
while (selected.length < 200) {
  let added = false;
  for (const pool of pools) if (pool.length && selected.length < 200) { selected.push(pool.shift()); added = true; }
  if (!added) throw new Error(`Only ${selected.length} qualifying parts; do not fill with invented rows`);
}
selected.sort((a,b)=>a.n-b.n || inches(a.x.length)-inches(b.x.length) || a.x.pn.localeCompare(b.x.pn));
const observations = [];
const items = selected.map(({x,y,n,sid,wid}, idx) => {
  const id = `AVI-${String(idx+1).padStart(3,'0')}`;
  const offers = [[x,sid,'Aircraft Spruce'],[y,wid,'Wicks Aircraft']].map(([r,supplierSource,supplier]) => {
    const s = source(supplierSource);
    const record = {
      observation_id: `${id}-${supplierSource.startsWith('spruce') ? 'AS' : 'WA'}`,
      item_id:id, supplier, supplier_role:'dealer', source_id:supplierSource,
      source_url:s.url, observed_at:s.retrieved_at, publication_date:s.publication_date,
      price_type:'public_advertised_listing', formal_quote:false, quote_valid_until:null,
      supplier_part_number:r.pn, advertised_price_usd:r.price, currency:'USD',
      sale_unit:'each', pack_quantity:1, comparison_quantity:1, quantity_basis:'single item starting quantity; discounts not applied',
      normalized_price_usd_each:r.price, normalization_formula:'advertised price / 1 piece',
      stock_reported:r.in_stock, stock_scope:supplier==='Aircraft Spruce' ? 'at least one dealer warehouse reports positive quantity' : r.stock_text,
      nominal_length_source:supplier==='Aircraft Spruce' ? r.length : r.fields['length nominal'],
      grip_length_source:supplier==='Aircraft Spruce' ? r.grip : r.fields['length grip'],
      condition:'new retail listing inferred from normal catalog; confirm in formal quote',
      freight_usd:null, tax_usd:null, country_of_origin:null, manufacturer_name:null,
      certificate_addon_displayed_usd:supplier==='Wicks Aircraft' ? r.material_cert_fee : null,
      certificate_fee_scope:'not confirmed; excluded from price comparison',
      cofc_availability_claim:supplier==='Aircraft Spruce' ? r.cofc : 'materials certificate option displayed; document scope unverified',
      faa_8130_availability_claim:supplier==='Aircraft Spruce' ? r.form_8130 : null,
      missing_commercial_fields:['formal quote validity','delivered freight','tax','certificate fee scope','actual manufacturer','origin','lead-time commitment']
    };
    observations.push(record);
    return record.observation_id;
  });
  const low = Math.min(x.price,y.price), high = Math.max(x.price,y.price);
  const midpoint = Math.round((low+high)/2*10000)/10000;
  return {
    item_id:id, part_number:x.pn, category:'airframe hardware / hex-head bolt', family:`AN${n}`,
    catalog_provenance:'constructed sample catalog, not confirmed RudCo inventory',
    normalized_description:`${x.pn}: alloy-steel hex-head airframe bolt, cadmium plated, ${families[n].thread} thread, ${x.length} in nominal length, ${x.grip} in grip, ${x.pn.endsWith('A') ? 'undrilled' : 'drilled'} shank`,
    standard_designation:x.pn, shape:'hex-head bolt', material:'alloy steel',
    grade:'exact steel grade unconfirmed; Aircraft Spruce family description says type 4037 or 8740',
    finish:'cadmium plated', supplier_standard_claims:{
      aircraft_spruce:'QQ-P-416A Type II Class 3 plating, supplier family description',
      wicks_aircraft:'NASM6812 alloy steel; QQ-P-416 Type II finish, supplier family description'
    },
    diameter_in:families[n].diameter, thread:families[n].thread,
    nominal_length_in:inches(x.length), nominal_length_display:x.length,
    grip_length_in:inches(x.grip), grip_length_display:x.grip,
    dimensions_unit:'inch', head_drilled:false, shank_drilled:!x.pn.endsWith('A'),
    tolerance:null, purchase_unit:'each', suggested_initial_comparison_quantity:1,
    match_evidence:['exact dealer part number','nominal length agrees numerically','grip length agrees numerically','cadmium-plated material designation','drilled versus undrilled shank designation','single-item advertised price basis'],
    observation_ids:offers,
    comparison_status:'comparable_public_part_prices; compliance pending',
    market_reference:{source_count:2, min_usd_each:low, max_usd_each:high, midpoint_usd_each:midpoint, spread_percent_of_lower:Math.round((high-low)/low*10000)/100,
      interpretation:'two-dealer product-only reference, not a wholesale index or delivered-price benchmark'},
    suggested_quote_price_usd_each:null,
    pricing_hold_reason:'Supplier cost, margin, order quantity, freight, origin and certificate requirements are unconfirmed',
    compliance:{cofc:'request and verify traceability', country_of_origin:'unknown', spec_certificate:'requested evidence must confirm applicable standard and finish', mtr:'requirement and availability depend on buyer request; not assumed for every fastener', aircraft_eligibility:'not verified against any helicopter illustrated parts catalog', faa_8130_3:'not supplied or assumed', lot_traceability:'unverified'},
    quote_ready:false,
    buyer_clarifying_questions:[`Confirm quantity of ${x.pn}, delivery location and required date.`, 'Confirm required certificate, origin restrictions, lot traceability and aircraft eligibility evidence.'],
    rfq_aliases:[x.pn, x.pn.toLowerCase(), x.pn.replace('-',' dash ')],
    synthetic_rfq_examples:[`Need 1 pc ${x.pn}, quote material cert separately`, `Please price ${x.pn.toLowerCase()} x 1 ea; delivery and origin TBD`]
  };
});
const counts = items.reduce((a,x)=>(a[x.family]=(a[x.family]||0)+1,a),{});
const summary = {created_at:new Date().toISOString(), owner:'Elad Tisch', item_count:items.length, observation_count:observations.length, family_counts:counts, supplier_count:2, public_listing_count:observations.length, formal_quote_count:0, manufacturer_offer_count:0, quote_ready_count:0, specification_or_stock_exclusions:excluded.length, qualified_parts_not_selected:pools.reduce((n,p)=>n+p.length,0), currency:'USD', comparison_basis:'one each; product only; no bulk extrapolation', sources_used:[...new Set(observations.map(o=>o.source_id))]};
for (const [name,data] of [['catalog.json',items],['price_observations.json',observations],['excluded_candidates.json',excluded],['summary.json',summary]]) fs.writeFileSync(`${root}/${name}`,JSON.stringify(data,null,2)+'\n');
let md = '# Aviation Hardware: 200 Comparable Parts\n\nOwner: Elad Tisch. Sources retrieved 2026-10-10. This is a constructed sample supplier catalog for the RFQ-to-quote challenge.\n\nAll 200 distinct part numbers have paired public dealer prices, matching nominal length and grip, matching cadmium-plated material and drilling designation, and stock reported by both dealers at retrieval. These are standardized airframe fasteners, not verified replacement parts for a specific helicopter. Exact grade, tolerances, origin, traceability and required certificates still need confirmation before a quote is ready.\n\nPrices are USD per one piece, product only. Freight, tax, certificate fees, discounts and wholesale cost are excluded. The midpoint is a two-dealer reference, not our selling price. There are no dated formal quotes or manufacturer offers in this list. Retrieval time does not establish when a dealer last revised its price.\n\n';
md += '## Coverage\n\n| Family | Thread | Items |\n|---|---|---:|\n';
for(const [fam,count] of Object.entries(counts)) md+=`| ${fam} | ${families[Number(fam.slice(2))].thread} | ${count} |\n`;
md+='\n## Item list\n\nD = drilled shank; U = undrilled shank. Heads are undrilled. Length and grip are inches. Each row links the two retrieved supplier family tables; identify the exact SKU on those tables.\n\n| ID | Part number | Length | Grip | Shank | Aircraft Spruce USD/ea | Wicks USD/ea | Reference midpoint | Sources |\n|---|---|---:|---:|---|---:|---:|---:|---|\n';
for(const i of items){const [a,w]=i.observation_ids.map(id=>observations.find(o=>o.observation_id===id));md+=`| ${i.item_id} | ${i.part_number} | ${i.nominal_length_display} | ${i.grip_length_display} | ${i.shank_drilled?'D':'U'} | ${a.advertised_price_usd.toFixed(2)} | ${w.advertised_price_usd.toFixed(2)} | ${i.market_reference.midpoint_usd_each.toFixed(3)} | [AS](${a.source_url}) / [WA](${w.source_url}) |\n`;}
md+='\n## Using the data\n\nUse `data/aviation/catalog.json` for matching and `price_observations.json` for source evidence. Match the complete AN part number, including A and C suffixes. Do not substitute drilled and undrilled shanks. RFQ aliases and examples are synthetic test inputs, not observed customer requests.\n\nA matched public price does not make a quote ready. Ask for order quantity, delivery terms, certificate and origin requirements. Compare the same quantity tier and charges before explaining competitiveness. Cost and target margin are still missing, so suggested quote prices remain null.\n';
fs.writeFileSync('docs/data/AVIATION_ITEMS_200.md',md);
console.log(JSON.stringify(summary,null,2));
