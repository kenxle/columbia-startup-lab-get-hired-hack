# RFQ Catalog and Market Pricing

**Owner:** Tisch (`@Tisch`).

## Role

Lead catalog development and market-pricing research for the RudCo RFQ-to-quote challenge. Build a structured database of industrial items that the agent can match to buyer requests, collect verifiable prices for comparable products, and develop explainable suggested pricing grounded in those observations. Each comparison must show the source, the matching specification, the unit conversion, and any remaining uncertainty so the quoting rep can review the result.

This supports jobs 2 and 3 in the [product brief](../product/PRD.md): catalog matching and market-backed pricing. Tisch supplied the RudCo challenge explanation directly as an image. It requires parsing material, grade, dimensions, quantity and standards; catalog matching; market-backed pricing; compliance flags; and buyer questions for ambiguous lines. The dataset below follows those requirements. This scope does not resolve the brief's open questions about RudCo data access or product direction.

## Responsibilities

1. Define catalog items using material, grade or alloy, temper, shape, finish, dimensions, tolerances, purchase unit, and applicable standards. Track certification availability separately from buyer requirements.
2. Build the 500-item aviation hardware catalog requested by Tisch, with two real public dealer prices for every item. Preserve the original 200 item IDs. Distinguish price-covered items from fully verified technical comparisons. Collect helicopter-specific OEM spare parts only when part, condition, eligibility, certification and price evidence can be established. Keep raw-material catalogs as a separate direction for the challenge's metal examples.
3. Collect supplier listings and price observations with source URLs, supplier SKUs, observation dates, currency, quantity tiers, availability, and known fees.
4. Normalize comparable offers to the same specification, quantity, and unit. Document every conversion and exclude mismatches from the benchmark calculation.
5. Develop a reproducible market reference and suggested price, with evidence, assumptions, and a clear distinction between observed prices and our own calculations.
6. Supply catalog and benchmark datasets for integration. Coordinate with Ken on scope and Yuval on access to supplier-provided catalog or pricing data.

## Admission rules for price coverage and technical comparison

An item enters the price-covered list when two retrieved independent dealer listings identify the same standardized part, give real numeric prices for one piece, and both report stock. Any readable specification conflict is rejected. An explicit right-hand nut mapping is allowed only when the dealer omits R but states Product Type Right; the actual dealer SKU and mapping evidence are retained.

Price coverage does not establish full technical equivalence. An item enters a fully qualified benchmark set only when material, grade, temper, form, dimensions, units, quantity tier and all buyer-required finish, tolerance, standard, certification and origin fields are confirmed. Unreadable source values are recorded as gaps, never repaired by guessing. Provisional price pairs show the observed prices but block full-equivalence and competitiveness claims until those gaps are resolved.

Keep pricing evidence and technical status separate on every item. All 500 current entries have real price evidence; 275 carry supplier specification holds. Unpriced candidates are excluded from the 500-item list rather than assigned invented prices.

For each item record:

| Field group | Required evidence |
|---|---|
| Identity | Internal item ID, normalized description, RFQ aliases, sample or supplier-provided catalog provenance |
| Specification | Material, grade, temper where applicable, shape, process, finish, dimensions and units, tolerances, applicable standard |
| Commercial basis | Piece or pack size, quantity tier, currency, availability, geography when known |
| Compliance | Buyer-required documents, supplier-stated availability, verified origin when required; unknowns remain explicit |
| Price observation | Supplier and SKU, exact URL, observed price, observation timestamp, retrieval method, selected variant |
| Charges | Freight, cutting, minimum-order, certificate and tax amounts, each marked included, separate, or unknown |
| Comparison | Matched attributes, exclusions, normalized price and formula, freshness, remaining gaps |

## Pricing method for the next stage

Compare product-only prices first. Report a delivered-price comparison only after delivery location and all relevant charges are known. A per-pound conversion does not make different cut lengths or quantity tiers commercially equivalent.

For a qualified set of offers, report the minimum, maximum, and median of normalized prices, together with the source count. With only two sources, the median is their midpoint and is a limited retail reference, not a market-wide estimate. Do not call a price competitive without stating the comparable offers and purchase basis.

A suggested quote can use that reference as a documented starting point. If actual supplier cost and a target gross margin are supplied, calculate `quote price = total attributable cost / (1 - target gross margin)` and compare it with the market reference. Do not invent cost or margin. Without them, label any proposal as a market-based suggestion that still needs the rep's commercial review.

Public supplier prices are external observations. A catalog we assemble is sample data unless RudCo supplies or confirms it. Neither establishes RudCo stock, negotiated wholesale cost, or a binding supplier quote. Never infer bulk prices by multiplying a single-piece price when the applicable quantity tier is unknown.

## Initial feasibility check, 2026-10-10

One candidate for the next session is an extruded **6061-T6511 aluminum flat bar, 0.25 in thick by 1 in wide, cut to 12 in**.

- [Online Metals, part 1143](https://www.onlinemetals.com/en/buy/aluminum/0-25-x-1-aluminum-rectangle-bar-6061-t6511-extruded/pid/1143): fetched product page lists the 12 in option at USD 4.72 for one piece, and states ASTM B221 and AMS QQ-A-200/8. The search result showed USD 4.75, so retain the fetched-page observation and recheck before use. The extracted quantity-discount block is inconsistent with the selected single-piece price and must not be used without variant verification.
- [Speedy Metals, SKU 61f.25x1](https://www.speedymetals.com/ps-2241-28-14-x-1-6061-t6511-aluminum-extruded.aspx): search-indexed supplier content lists the matching nominal specification and a 12 in option at USD 4.36, with a cutting tolerance of plus or minus 0.25 in. Direct retrieval timed out, so this is a discovery lead rather than a verified current price observation.

**Status: pending verification.** Re-fetch Speedy's listing, verify quantity basis and Online Metals' cutting tolerance, and reconcile standards, finish, certification needs, and charges before computing a benchmark. This candidate demonstrates a practical route to comparable products; it is not yet benchmark-ready. No suggested quote has been assigned.

## Aviation catalog, 2026-10-10

At Tisch's request, aviation hardware takes priority and public advertised listings are the price evidence. [The current 500-item list](AVIATION_ITEMS_500.md) has 1,000 source-verified dealer prices from Aircraft Spruce and Wicks Aircraft. It contains 247 hex-head bolts, 48 clevis bolts, 159 machine screws, 26 nuts, 7 large-area washers and 13 copper crush gaskets. These are real standard size and configuration variants across 23 families. The [original 200-item list](AVIATION_ITEMS_200.md) remains a historical subset, with its IDs preserved.

Both dealers report stock for all 500 items. Readable specification conflicts and unavailable stock were excluded. Relevant published dimensional fields agree for 225 items. Another 275 have same-part pricing evidence but missing or unreadable supplier specification fields, each marked SPEC PENDING. Full equivalence is not claimed for those rows. A same-part advertised-price comparison is useful for research but is not sufficient to release an aircraft procurement quote.

The data are in [`data/aviation/`](../../data/aviation/README.md), with a Ruby reader for the Rails app. Every selected item has two source-linked prices, a range and midpoint with a qualification, synthetic RFQ examples and buyer questions. Supplier cost and margin are unknown, so suggested selling prices remain null. All listings were retrieved on 2026-10-10; source publication and price-revision dates are unknown. No formal manufacturer or dealer proposal was obtained.

## Next stage

Resolve supplier specification holds, confirm representative order quantities, delivery terms, grade, tolerances, origin restrictions and certificate requirements. Recollect prices for those commercial terms, establish actual cost and margin where available, and review suggested pricing with Tisch before integration. Use a helicopter illustrated parts catalog to establish applicability before labeling an item as an approved replacement.
