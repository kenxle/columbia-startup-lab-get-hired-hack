# Aviation Catalog and Price Evidence

Owner: Tisch. Data collected 2026-10-10 for the RudCo RFQ-to-quote challenge. Application stack: Ruby on Rails.

## Files

- [`catalog.json`](catalog.json): 500 distinct standard hardware parts, including bolts, screws, nuts, washers and gaskets. Original AVI-001 through AVI-200 and their part identities are preserved.
- [`price_observations.json`](price_observations.json): 1,000 real public advertised prices, two dealers per item. Each has a URL, retrieval timestamp, one-piece price basis, stock claim and unknown charges. Actual dealer SKUs and any explicit right-hand mapping evidence are retained.
- [`source_manifest.json`](source_manifest.json): retrieved pages, exact timestamps and SHA-256 hashes. Extra exploratory pages are present; `summary.json` identifies the 46 source records actually used for this catalog.
- [`excluded_candidates.json`](excluded_candidates.json): reasons parts were rejected, including date-corrupted fractions, conflicting dimensions, stock gaps and unselected material types.
- [`summary.json`](summary.json): counts and limits.
- [Readable 500-row item list](../../docs/data/AVIATION_ITEMS_500.md).
- [Original 200-row list](../../docs/data/AVIATION_ITEMS_200.md): historical subset, retained to verify stable item IDs.

Full supplier HTML snapshots are retained locally under `raw/`, which is gitignored. Committed data are extracted product and price facts, not copies of supplier pages or customer reviews. To reproduce the audit, fetch the sources again into `raw/` and rebuild; prices and hashes may change.

## Meaning of the prices

Every item has two real USD prices for one piece of the same standardized part, and both dealers reported stock at retrieval. 225 items have agreeing readable dimensional fields. The other 275 have price evidence but need supplier specification confirmation; they are marked SPEC PENDING. Readable conflicts were rejected. No missing price was invented.

Right-hand nut identifiers are an explicit exception to identical printed dealer SKUs: where Wicks omits R but states Product Type Right, the mapping to the R-suffix standard part is recorded with evidence. No left-hand nut, material, drilled shank or length is silently substituted.

The midpoint is `(offer 1 + offer 2) / 2`. It is a two-dealer product-price reference with a qualification, not a selling price or whole-market estimate. SPEC PENDING rows must not support a full-equivalence or competitiveness claim until their gaps are resolved. Bulk prices must be recollected at the actual order tier.

Freight, taxes, certificate charges, margin and negotiated wholesale pricing are outside this comparison. Wicks shows a materials-certificate add-on; the charge scope and document contents are unconfirmed, so it is recorded separately. A certificate option is not proof that a particular document meets the buyer's requirement.

`observed_at` is the retrieval time. It is not a supplier publication date, quote date, price revision date or validity guarantee. All observations are public listings. No manufacturer price, formal dealer quote, FAA release document, verified origin, lot traceability or specific helicopter applicability has been obtained.

## Integration rules

1. Match the entire standard part number and requested dimensions. Preserve A, C, H and handedness designations. Consult recorded SKU mappings rather than inventing aliases. Do not silently substitute material or drilling.
2. Resolve missing quantities, delivery terms and compliance requirements with a buyer question. RFQ examples in this dataset are synthetic and explicitly labeled.
3. Show the observations, qualification and calculation beside the price. A pending specification blocks full-equivalence claims. Product-only comparisons cannot support delivered-price savings.
4. Keep `quote_ready` false until all buyer-required evidence and commercial terms are confirmed. Suggested selling prices are null because cost, margin and required charges are unknown.
5. Mark the assembled catalog as sample data. It does not claim RudCo stocks these items. A part's presence in dealer catalogs does not establish applicability to a particular helicopter.

This work supports the screenshot's five requirements: normalized specifications and quantity handling, supplier catalog matches, source-backed price comparisons, explicit compliance gaps, and clarifying questions instead of guesses. It creates the data foundation, not the completed RFQ agent or a ready-to-send quote.

## Load in Ruby on Rails

The adapter uses Ruby's standard libraries and BigDecimal. It adds no Rails gem dependencies and does not write to models or the database.

```ruby
require Rails.root.join("tools/catalog_research/catalog_reader").to_s

catalog = RfqCatalog::Reader.new(Rails.root.join("data/aviation"))
catalog.validate!
item = catalog.find("AN3-13A")
offers = catalog.offers_for(item.fetch("part_number"))
reference = catalog.price_reference(item.fetch("part_number"))
# reference[:midpoint] is BigDecimal; suggested selling price remains nil.
# reference[:specification_gaps] and [:qualification] must remain visible.
```

This is a data reader and price-evidence adapter. It does not implement the scored matcher contract, assemble Yuval's processing result or promote a line to Ready. Coordinates with Hirsh and Yuval remain required before application integration. Catalog summary schema is version 2; the application result-hash schema is a separate contract.

Validate the data and adapter on the pinned Ruby:

```sh
script/with-ruby ruby tools/catalog_research/catalog_reader.rb
script/with-ruby ruby tools/catalog_research/catalog_reader_test.rb
```

The nine Ruby tests verify all 500 rows and 1,000 offers, stable original IDs, exact decimal arithmetic, visible specification gaps, duplicate rejection, pack-versus-piece errors and undocumented SKU aliases.

## Reproduce supplier research

Offline source research uses Node.js from the repo root. The Rails app does not require Node to read the committed data:

```powershell
node tools/catalog_research/fetch_sources.mjs spruce-an3 https://www.aircraftspruce.com/catalog/hapages/an3.php wicks-an3 https://www.wicksaircraft.com/shop/bolt-an3-3-16-1032/
# Repeat for the remaining source IDs and URLs in source_manifest.json.
node tools/catalog_research/build_catalog.mjs
node --test tools/catalog_research/parse_sources.test.mjs
node tools/catalog_research/validate_catalog.mjs
```

Build selection requires 500 real two-dealer price pairs and preserves the original 200 parts. It fails rather than inventing entries if the offers no longer qualify. Seven parser tests cover corrupt fractions, mismatched prices, packs, mislabeled rows and contradictory specifications. Full source validation checks every price against retrieved HTML, embedded product prices, source hashes, reported stock, units, documented SKU mappings and arithmetic. Technical holds remain explicit rather than being mislabeled as validated specifications.
