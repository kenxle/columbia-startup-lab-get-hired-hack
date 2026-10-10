import fs from 'node:fs';
import {spruceBolts,spruceClevis,spruceHardware,spruceWashers,sprucePlainNuts,wicksRows,inches} from './parse_sources.mjs';

const root='data/aviation', target=500;
const read=name=>JSON.parse(fs.readFileSync(`${root}/${name}.json`,'utf8'));
const manifest=read('source_manifest'), prior=read('catalog');
const priorIds=new Map(prior.map(i=>[i.part_number,i.item_id]));
let nextId=Math.max(...prior.map(i=>Number(i.item_id.slice(4))))+1;
const sources=new Map(manifest.map(s=>[s.id,s]));
const html=id=>fs.readFileSync(`${root}/raw/${id}.html`,'utf8');
const boltThreads={AN3:'10-32',AN4:'1/4-28',AN5:'5/16-24',AN6:'3/8-24',AN7:'7/16-20',AN8:'1/2-20',AN23:'10-32',AN24:'1/4-28',AN25:'5/16-24'};
const configs=[
  ...[3,4,5,6,7,8].map(n=>({key:`an${n}`,family:`AN${n}`,kind:'hex-head bolt',parse:spruceBolts,wicks:[`an${n}`]})),
  ...[23,24,25].map(n=>({key:`an${n}`,family:`AN${n}`,kind:'clevis bolt',parse:spruceClevis,wicks:[`an${n}`]})),
  ...['ms35206','ms35207','ms35190','ms35214','ms24693','ms24694','ms27039','ms35265','ms35266'].map(key=>({key,family:key.toUpperCase(),kind:'machine screw',parse:spruceHardware,wicks:['ms24693','ms24694'].includes(key)?[key+'s',key+'c']:[key]})),
  {key:'an310',family:'AN310',kind:'castellated nut',parse:spruceHardware,wicks:['an310']},
  {key:'an315',family:'AN315',kind:'plain hex nut',parse:sprucePlainNuts,wicks:['an315']},
  {key:'an316',family:'AN316',kind:'thin check nut',parse:sprucePlainNuts,wicks:['an316']},
  {key:'an900',family:'AN900',kind:'copper crush gasket',parse:spruceHardware,wicks:['an900']},
  {key:'an970',family:'AN970',kind:'large-area washer',parse:spruceWashers,wicks:['an970']}
];
const excluded=[], candidates=[];
function primarySpecs(r,c) {
  if(c.kind.includes('bolt')) return {length:r.length,grip:r.grip,thread:boltThreads[c.family]};
  const f=r.table_fields;
  if(['ms35206','ms35207','ms35190'].includes(c.key)) return {length:f[3],thread:f[2],grip:null};
  if(c.key==='ms35214') return {length:f[1],thread:f[2],grip:null};
  if(['ms24693','ms27039'].includes(c.key)) return {length:f[3],thread:f[2],grip:null};
  if(c.key==='an310') return {length:null,thread:f[2],grip:null};
  if(['an315','an316'].includes(c.key))return {length:null,thread:f[1],grip:null};
  if(c.key==='an900') return {length:null,thread:null,grip:null,id:f[2]};
  if(c.key==='an970') return {length:null,thread:null,grip:null,od:f[2],id:f[3],thickness:f[4]};
  // MS24694's primary table only provides its legacy AN509 callout.
  return {length:null,thread:null,grip:null};
}
function readableThread(s) { return typeof s==='string'&&/^(?:\d+(?:\/\d+)?)-\d+$/.test(s.trim())?s.trim():null; }
function qualify(x,y,c,spec) {
  const conflicts=[], gaps=[], verified=[y.pn===x.pn?'exact_part_number':'explicit_right_hand_sku_mapping','one_piece_price_basis'];
  const relevant=c.kind.includes('bolt')?['length','grip']:c.kind==='machine screw'?['length','thread']:c.key==='an900'?['id']:c.key==='an970'?['od','id','thickness']:['thread'];
  for(const field of relevant) {
    const raw=y.fields[field==='grip'?'length grip':field==='thread'?'thread size':field==='id'?'i d':field==='od'?'o d':field==='thickness'?'thickness':'length nominal']??(field==='length'?y.fields.length:undefined);
    const a=field==='thread'?readableThread(spec[field]):inches(spec[field]||'');
    const b=field==='thread'?readableThread(raw):inches(raw||'');
    if(a===null||b===null) gaps.push({field,aircraft_spruce:spec[field]??null,wicks_aircraft:raw??null,reason:'missing or unreadable supplier specification; no repair inferred'});
    else if(field==='thread'?a!==b:Math.abs(a-b)>0.00001) conflicts.push({field,aircraft_spruce:spec[field],wicks_aircraft:raw});
    else verified.push(field);
  }
  if(c.kind.includes('bolt')) {
    const expected=x.pn.endsWith('A')?'Undrilled Shank':'Drilled Shank';
    if(y.fields['product type']!==expected) conflicts.push({field:'shank drilling',expected,wicks_aircraft:y.fields['product type']});
    else verified.push('shank_drilling');
    if(c.kind==='hex-head bolt') {
      const expectedMaterial=x.pn.includes('C')?'431 Stainless':'Cad Plated';
      if(y.fields.material!==expectedMaterial) conflicts.push({field:'material',expected:expectedMaterial,wicks_aircraft:y.fields.material});
      else verified.push('material_designation');
    }
  }
  return {conflicts,gaps,verified,dimensions_verified:gaps.length===0};
}
for(const c of configs) {
  const sid=`spruce-${c.key}`, a=c.parse(html(sid));
  const w=c.wicks.flatMap(id=>wicksRows(html(`wicks-${id}`)).map(r=>({...r,source_id:`wicks-${id}`})));
  const wm=new Map(w.map(r=>[r.pn,r]));
  for(const x of a) {
    if(['an315','an316'].includes(c.key)&&!x.pn.startsWith(c.family+'-'))continue;
    let y=wm.get(x.pn);
    if(!y&&['an315','an316'].includes(c.key)&&x.pn.endsWith('R')) {
      const bare=wm.get(x.pn.slice(0,-1));
      if(bare?.fields['product type']==='Right')y={...bare,sku_mapping_evidence:'Spruce R suffix and Wicks Product Type Right explicitly agree on handedness'};
    }
    const reasons=[];
    if(!y) reasons.push('No exact second-dealer SKU');
    else {
      if(!x.in_stock||!y.in_stock) reasons.push('Both dealers must report stock for this catalog');
      if(!c.kind.includes('bolt')&&y.fields['sold by']!=='Each') reasons.push('Unconfirmed one-piece second-dealer sale unit');
    }
    if(reasons.length){excluded.push({part_number:x.pn,source_id:sid,reasons});continue;}
    const spec=primarySpecs(x,c), qualification=qualify(x,y,c,spec);
    if(qualification.conflicts.length){excluded.push({part_number:x.pn,source_id:sid,reasons:['Conflicting readable specifications'],conflicts:qualification.conflicts});continue;}
    candidates.push({x,y,c,spec,qualification,sid,wid:y.source_id});
  }
}
const candidateMap=new Map(candidates.map(r=>[r.x.pn,r]));
if(candidateMap.size!==candidates.length) throw Error('Duplicate SKU in candidate sources');
// Preserve IDs and all original items. Append only verified price pairs.
const selected=[];
const original=prior.filter(r=>Number(r.item_id.slice(4))<=200);
if(original.length!==200) throw Error('Original 200-item set missing');
for(const i of original) {
  const r=candidateMap.get(i.part_number);
  if(!r||!r.qualification.dimensions_verified) throw Error(`Original item no longer qualifies: ${i.part_number}`);
  selected.push({...r,id:i.item_id}); candidateMap.delete(i.part_number);
}
let remaining=[...candidateMap.values()];
remaining.sort((a,b)=>Number(b.qualification.dimensions_verified)-Number(a.qualification.dimensions_verified)||a.c.family.localeCompare(b.c.family)||a.x.pn.localeCompare(b.x.pn,{numeric:true}));
// Round-robin across families to include screws, clevis bolts and nuts.
const pools=new Map();
for(const r of remaining){const p=pools.get(r.c.family)||[];p.push(r);pools.set(r.c.family,p);}
while(selected.length<target) {
  let added=false;
  for(const pool of pools.values()) if(pool.length&&selected.length<target){const r=pool.shift();const id=priorIds.get(r.x.pn)??`AVI-${String(nextId++).padStart(3,'0')}`;selected.push({...r,id});added=true;}
  if(!added) throw Error(`Only ${selected.length} real qualifying price pairs; never invent missing parts or prices`);
}
const observations=[];
const items=selected.map(({x,y,c,spec,qualification,sid,wid,id})=>{
  const old=prior.find(i=>i.part_number===x.pn), material=c.kind.includes('bolt')?(x.pn.includes('C')?'stainless steel':'alloy steel'):c.key==='ms35214'?'brass':c.key==='an900'?'copper gasket, filler unverified':x.pn.includes('-C')?'stainless steel':'steel';
  const observation_ids=[[x,sid,'Aircraft Spruce'],[y,wid,'Wicks Aircraft']].map(([r,source_id,supplier])=>{
    const s=sources.get(source_id), o={
      observation_id:`${id}-${supplier==='Aircraft Spruce'?'AS':'WA'}`,item_id:id,supplier,supplier_role:'dealer',source_id,source_url:s.url,observed_at:s.retrieved_at,
      publication_date:null,price_type:'public_advertised_listing',formal_quote:false,quote_valid_until:null,
      supplier_part_number:r.pn,canonical_part_number:x.pn,sku_mapping_evidence:r.sku_mapping_evidence??null,advertised_price_usd:r.price,currency:'USD',sale_unit:'each',pack_quantity:1,comparison_quantity:1,
      quantity_basis:'one piece at starting quantity; no discount or bulk extrapolation',normalized_price_usd_each:r.price,normalization_formula:'advertised price / 1 piece',
      stock_reported:true,stock_scope:supplier==='Aircraft Spruce'?'positive stock at at least one dealer warehouse':r.stock_text,
      source_specification_fields:supplier==='Aircraft Spruce'?{...spec,table_fields:r.table_fields??null}:{...r.fields},
      condition:'normal new retail catalog inferred; confirm in formal quote',freight_usd:null,tax_usd:null,country_of_origin:null,manufacturer_name:null,
      certificate_addon_displayed_usd:supplier==='Wicks Aircraft'?r.material_cert_fee:null,certificate_fee_scope:'unconfirmed and excluded',
      cofc_availability_claim:supplier==='Aircraft Spruce'?r.cofc:'materials certificate option displayed; contents unverified',
      faa_8130_availability_claim:supplier==='Aircraft Spruce'?r.form_8130:null,
      missing_commercial_fields:['formal quote validity','freight','tax','certificate fee scope','actual manufacturer','origin','lead-time commitment']
    };
    observations.push(o);return o.observation_id;
  });
  const min=Math.min(x.price,y.price),max=Math.max(x.price,y.price),midpoint=Math.round((min+max)/2*10000)/10000;
  const desc=old?.normalized_description??`${x.pn}: ${material} ${c.kind}; ${spec.thread?`thread ${spec.thread}; `:''}${spec.length?`published length ${spec.length} in; `:''}confirm remaining specification fields`;
  return {
    ...old,item_id:id,part_number:x.pn,category:`airframe hardware / ${c.kind}`,family:c.family,
    catalog_provenance:'constructed sample catalog, not confirmed RudCo stock',normalized_description:desc,
    standard_designation:x.pn,shape:c.kind,material,grade:old?.grade??'exact grade unconfirmed',finish:old?.finish??null,
    nominal_length_in:inches(spec.length||''),nominal_length_display:spec.length??null,grip_length_in:inches(spec.grip||''),grip_length_display:spec.grip??null,
    thread:spec.thread??null,dimensions_unit:'inch',tolerance:null,purchase_unit:'each',suggested_initial_comparison_quantity:1,
    additional_dimensions:{inside_diameter_in:inches(spec.id||''),outside_diameter_in:inches(spec.od||''),thickness_in:inches(spec.thickness||'')},
    specification_source_url:sources.get(sid).url,price_coverage_status:'two_real_exact_part_number_dealer_prices',
    specification_verification:{verified_fields:qualification.verified,unverified_fields:qualification.gaps,readable_conflicts:[],dimensions_verified:qualification.dimensions_verified},
    match_evidence:qualification.verified,observation_ids,
    comparison_status:qualification.dimensions_verified?'dimensions_verified; compliance pending':'exact_part_number_price_pair; supplier_specification_confirmation_pending',
    market_reference:{source_count:2,min_usd_each:min,max_usd_each:max,midpoint_usd_each:midpoint,spread_percent_of_lower:Math.round((max-min)/min*10000)/100,
      qualification:qualification.dimensions_verified?'published dimensional fields agree; compliance unverified':'provisional same-part-number prices; full supplier specification comparison blocked',
      interpretation:'two-dealer product-only price reference; no wholesale, delivered-price or full-equivalence claim'},
    suggested_quote_price_usd_each:null,quote_ready:false,
    pricing_hold_reason:'Actual quantity, costs, margin, delivery terms, origin and certificate requirements are unconfirmed',
    compliance:{cofc:'request and verify',country_of_origin:'unknown',spec_certificate:'verify against buyer requirements',mtr:'requirement and availability unconfirmed',aircraft_eligibility:'not verified for a specific helicopter',faa_8130_3:'not supplied or assumed',lot_traceability:'unverified'},
    buyer_clarifying_questions:[`Confirm ${x.pn} quantity, destination and required date.`,...qualification.gaps.map(g=>`Confirm ${g.field} for ${x.pn}; one supplier field is missing or unreadable.`),'Confirm certificates, origin restrictions and aircraft eligibility evidence.'],
    rfq_aliases:[x.pn,x.pn.toLowerCase(),x.pn.replace('-',' dash ')],
    synthetic_rfq_examples:[`Need 1 pc ${x.pn}, quote required certs separately`,`Price ${x.pn.toLowerCase()} x 1 ea; confirm delivery and origin`]
  };
});
const family_counts={},category_counts={};
for(const i of items){family_counts[i.family]=(family_counts[i.family]||0)+1;category_counts[i.shape]=(category_counts[i.shape]||0)+1;}
const summary={schema_version:2,created_at:new Date().toISOString(),owner:'Tisch',item_count:items.length,observation_count:observations.length,price_covered_item_count:items.length,
  source_verified_price_count:observations.length,dimensions_verified_item_count:items.filter(i=>i.specification_verification.dimensions_verified).length,
  supplier_specification_confirmation_pending_count:items.filter(i=>!i.specification_verification.dimensions_verified).length,
  original_item_ids_preserved:200,family_counts,category_counts,supplier_count:2,formal_quote_count:0,manufacturer_offer_count:0,quote_ready_count:0,
  excluded_candidate_count:excluded.length,currency:'USD',comparison_basis:'one each; advertised product price only',sources_used:[...new Set(observations.map(o=>o.source_id))]};
for(const [name,value] of [['catalog',items],['price_observations',observations],['excluded_candidates',excluded],['summary',summary]])fs.writeFileSync(`${root}/${name}.json`,JSON.stringify(value,null,2)+'\n');
let md='# Aviation Hardware: 500 Items With Real Dealer Prices\n\nOwner: Tisch. Sources retrieved 2026-10-10. Original AVI-001 through AVI-200 are preserved. The current dataset is a constructed sample catalog for the RudCo RFQ-to-quote challenge.\n\nEvery row has two real public USD prices for the same standardized part and a one-piece sale basis, with stock reported by both dealers at retrieval. Right-hand nut SKU mappings are explicitly recorded where a dealer omits the R suffix but states Product Type Right. No price is invented, extrapolated from an unpriced SKU or taken from a search snippet. Full supplier pages were retrieved and their prices checked against embedded product records.\n\n';
md+=`${summary.dimensions_verified_item_count} items have agreeing readable dimensional fields. ${summary.supplier_specification_confirmation_pending_count} have exact-part-number prices but need specification confirmation because a supplier field is missing or unreadable. Readable conflicts were rejected. The latter are labeled **SPEC PENDING** and must not be described as fully equivalent offers.\n\n`;
md+='Prices exclude freight, taxes, certificate fees and discounts. The midpoint is a two-dealer product-price reference, not our selling price. Formal proposals, manufacturer offers, origin, traceability and helicopter applicability remain unverified. Retrieval time does not establish when a price was revised or how long it is valid.\n\n## Coverage\n\n| Category | Items |\n|---|---:|\n';
for(const [category,count] of Object.entries(category_counts))md+=`| ${category} | ${count} |\n`;
md+='\n## Item list\n\nAll prices are USD per one piece. DIMENSIONS OK means the relevant published dimensional fields agree; compliance remains pending for every row. Each source link identifies the family table containing the exact part number.\n\n| ID | Part number | Category | Aircraft Spruce | Wicks | Midpoint | Specification status | Sources |\n|---|---|---|---:|---:|---:|---|---|\n';
for(const i of items){const [a,w]=i.observation_ids.map(id=>observations.find(o=>o.observation_id===id));md+=`| ${i.item_id} | ${i.part_number} | ${i.shape} | ${a.advertised_price_usd.toFixed(2)} | ${w.advertised_price_usd.toFixed(2)} | ${i.market_reference.midpoint_usd_each.toFixed(3)} | ${i.specification_verification.dimensions_verified?'DIMENSIONS OK':'SPEC PENDING'} | [AS](${a.source_url}) / [WA](${w.source_url}) |\n`;}
md+='\n## Rails integration\n\nThe app can load `data/aviation/catalog.json` and `price_observations.json` using the Ruby reader in `tools/catalog_research/catalog_reader.rb`. Use BigDecimal for price calculations. Items with SPEC PENDING need supplier specification confirmation before any equivalent-offer or competitiveness claim. All rows require buyer quantities, commercial terms and compliance review before release. No Rails models, migrations or application code are changed by this data update.\n';
fs.writeFileSync('docs/data/AVIATION_ITEMS_500.md',md);
console.log(JSON.stringify(summary,null,2));
