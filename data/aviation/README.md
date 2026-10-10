# Aviation Catalog and Price Evidence

Owner: Elad Tisch. Data collected 2026-10-10 for the RudCo RFQ-to-quote challenge.

## Files

- [`catalog.json`](catalog.json): 200 distinct cadmium-plated AN bolt part numbers with normalized specifications, aliases, synthetic RFQ examples, compliance gaps, and price references.
- [`price_observations.json`](price_observations.json): 400 public advertised offers, two dealers per item. Each has a source URL, retrieval timestamp, quantity and price basis, stock claim, and unknown charges.
- [`source_manifest.json`](source_manifest.json): retrieved public pages, exact timestamps and SHA-256 hashes. Extra exploratory source pages are present; `summary.json` identifies the ten pages actually used for the catalog.
- [`excluded_candidates.json`](excluded_candidates.json): reasons parts were rejected, including date-corrupted fractions, conflicting dimensions, stock gaps and unselected material types.
- [`summary.json`](summary.json): counts and limits.
- [Readable 200-row item list](../../docs/data/AVIATION_ITEMS_200.md).

Full supplier HTML snapshots are retained locally under `raw/`, which is gitignored. Committed data are extracted product and price facts, not copies of supplier pages or customer reviews. To reproduce the audit, fetch the sources again into `raw/` and rebuild; prices and hashes may change.

## Meaning of the prices

Prices are USD for one piece at the advertised starting quantity. Both offers use the same exact AN part number and agree on the selected published dimensional fields and material/drilling designation. The midpoint is `(offer 1 + offer 2) / 2`; it is a two-dealer reference. It does not measure the whole market or RudCo's costs. Bulk prices must be recollected for the actual order tier.

Freight, taxes, certificate charges, margin and negotiated wholesale pricing are outside this comparison. Wicks shows a materials-certificate add-on; the charge scope and document contents are unconfirmed, so it is recorded separately. A certificate option is not proof that a particular document meets the buyer's requirement.

`observed_at` is the retrieval time. It is not a supplier publication date, quote date, price revision date or validity guarantee. All observations are public listings. No manufacturer price, formal dealer quote, FAA release document, verified origin, lot traceability or specific helicopter applicability has been obtained.

## Integration rules

1. Match the entire standard part number and requested dimensions. Preserve A, C and H designations. Do not silently substitute material or drilling.
2. Resolve missing quantities, delivery terms and compliance requirements with a buyer question. RFQ examples in this dataset are synthetic and explicitly labeled.
3. Show the exact price observations and calculation to explain a proposed price. Do not describe product-only comparisons as delivered-price savings.
4. Keep `quote_ready` false until all buyer-required evidence and commercial terms are confirmed. Suggested selling prices are null because cost, margin and required charges are unknown.
5. Mark the assembled catalog as sample data. It does not claim RudCo stocks these items. A part's presence in dealer catalogs does not establish applicability to a particular helicopter.

This work supports the screenshot's five requirements: normalized specifications and quantity handling, supplier catalog matches, source-backed price comparisons, explicit compliance gaps, and clarifying questions instead of guesses. It creates the data foundation, not the completed RFQ agent or a ready-to-send quote.

## Reproduce and validate

Run commands from the repo root with Node.js:

```powershell
node tools/catalog_research/fetch_sources.mjs spruce-an3 https://www.aircraftspruce.com/catalog/hapages/an3.php wicks-an3 https://www.wicksaircraft.com/shop/bolt-an3-3-16-1032/
# Repeat for the remaining source IDs and URLs in source_manifest.json.
node tools/catalog_research/build_catalog.mjs
node --test tools/catalog_research/parse_sources.test.mjs
node tools/catalog_research/validate_catalog.mjs
```

Build selection requires 200 qualifying parts. It fails rather than inventing entries if the available offers no longer qualify. Tests cover numeric fractions, corrupt source values, conflicting prices and pack-versus-piece mistakes. The full dataset validator checks every selected row against the locally saved pages, source hashes, matching dimensions, units, reported stock and arithmetic.
