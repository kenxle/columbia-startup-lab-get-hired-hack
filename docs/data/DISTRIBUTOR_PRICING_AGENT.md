# Live distributor pricing agent

Owner: Tisch. RFQ text or document bytes go in; each matched item returns its quoted price or a specific buyer/procurement hold. Every invocation refreshes market and supplier sources. Historical catalog prices identify source URLs only. No failed lookup falls back to an old price.

## Commercial policy

Target gross margin is 15%; minimum gross margin is 8%. Destination country and postal code are required for each RFQ. Five independent, specification-compatible competitor prices are required for each item before a competitiveness claim or firm price is released. Duplicate rows from one seller count once. Comparisons use the median of delivered offers for the same quantity, unit, currency, condition, certificates, destination and required charge scope.

Public retail prices provide product evidence. They do not confirm wholesale acquisition cost, allocated stock, freight or certifications. RudCo's own website selling prices are not treated as acquisition costs. Missing costs stay unknown. Quotes stay held when the current supplier terms cannot support procurement and delivery.

The price includes purchased packs and MOQ surplus, inbound freight, duty/brokerage, supplier paperwork, outbound freight, handling, financing/risk reserve, nonrecoverable tax, payment fees and profit. Every cost requires evidence, including an explicit zero. Payment fees apply to revenue. Before rounding, unit price is `total line cost / requested quantity / (1 - gross margin - payment fee rate)`. Decimal calculations round up cents and check the realized margin again. The agent may reduce a target price to the competitor median while preserving the 8% floor; otherwise it returns `not_competitive`.

Identical items with the same requirements are consolidated into one purchase lot. Original RFQ lines remain attached. Confirmed stock is also checked across separate requirement groups. Quote validity is capped by source freshness, supplier/benchmark expiries and the last acceptance time that permits delivery.

## Live sources and coverage

The 500 aviation catalog rows have two researched public dealers: Aircraft Spruce and Wicks. Each hardware item additionally checks Airfasco, Pegasus and Monroe Aerospace. Exact SKU evidence is required to extract a price; a search page, missing price, pack uncertainty or a 404 is a recorded gap. Five complete prices for every catalog row have not been established.

The current parsers preserve Airfasco's MOQ/pack, Pegasus's published tiers and Monroe's unknown sale unit. Extra prices remain public product observations and cannot become delivered benchmarks without commercial confirmation. Four bounded workers fetch independent pages in parallel and deduplicate a page only inside the current RFQ.

Material context uses current downloads of official BLS indices via FRED: [Steel Mill Products](https://fred.stlouisfed.org/series/WPU1017) and [Aluminum Mill Shapes](https://fred.stlouisfed.org/series/WPU102501). These are monthly indices with publication lag, not spot $/lb or finished-item prices. The output separates retrieval time from observation date and blocks overdue observations. Unsupported materials need an applicable, same-request verified material-price source from procurement.

Industrial sourcing routes include Ervin, Tech Aluminum, Cambridge Metal, Online Metals and Speedy Metals. These are quote routes, not numeric purchase offers. See `data/distributor_pricing/supplier_directory.json` for scope. Online Metals explicitly offers personalized quotes on its [official contact page](https://www.onlinemetals.com/en/contact-us); Speedy Metals lists forms and a sales route on its [official branch page](https://www.speedymetals.com/t-rockford.aspx).

## Run and Rails entry point

`ruby tools/distributor_pricing/bin/quote` reads one JSON request on stdin and returns one result. Example input:

```json
{"rfq":"AN3-13A qty 1 ea","destination":{"country":"US","postal_code":"10027"},"currency":"USD"}
```

Use `type: "pdf"`, `encoding: "base64"` and `filename` for encoded PDF input. The PDF reader must be installed. Intake is limited to 2 MB and 100 item lines. No quantity is silently set to one. Unknown or contradictory specifications need buyer clarification.

Rails calls `DistributorPricing::QuoteAgent.call(rfq:, destination:, **options)`. Its result is `distributor_pricing/v1`, with `request`, `quote`, `lines`, live source checks, material context, procurement requests and evidence. Each line's `pricing` is the existing `CatalogMatch::PricingHandoff.apply` input. The agent itself performs no database writes. RFQ processing remains the shared result assembler.

`ready` exposes `unit_price`, `quote_total`, `quote_valid_until`, margin analysis and selected supplier evidence. `needs_buyer`, `needs_procurement`, `not_competitive` and `no_match` hold the selling price. A full quote total is emitted only when every item is ready and extraction has no warnings. Confirmed partial lines remain visible separately. Rep approval is required; nothing is purchased, emailed or submitted automatically.

## Provider configuration

The ignored `.env` or server environment may contain `NINOO_API_KEY`, `NINOO_MODEL` and `DISTRIBUTOR_PROCUREMENT_FEED`. The confirmed Nicrron gateway handles RFQ interpretation only. It cannot produce factual prices, stock or costs. Its output is restricted to exact RFQ substrings and quantity evidence. A gateway failure leaves deterministic intake available.

The procurement feed is an operator-configured HTTPS adapter, not the LLM gateway. No executable procurement feed is connected yet. It must query current supplier commercial terms and five competing delivered offers for the request; a historical quote database alone is insufficient.

The feed receives a fresh `request_id`, `started_at`, destination, currency, deadline, item quantities/specs and per-line requirements. It returns `{request_id, checked_at, lines: {line_id: {offers, benchmarks, specifications_verified, material_price_evidence}}}`. Response `checked_at` must lie inside the current run. Every offer/benchmark also needs `revalidated_for_request_id` and `revalidated_at` for this run. The agent preserves the original observation time separately.

Offer fields are validated by `Engine`: supplier identity/SKU, part, source/quote/buy URLs, retrieval/expiry, currency, unit/product price, pack/MOQ/tier, confirmed stock, delivered lead time, exact destination/specs/certifications/origin/condition, commercial evidence, confirmed order conditions, all seven cost fields and payment fee. Benchmarks also require exact requested `quantity`, `total_price`, `price_scope: delivered_ex_tax` and `charge_scope: all_required_charges_ex_tax`. Material evidence needs exact material/grade, source URL, value/currency/unit, observation date and current request/time proof.

Operator-side adapters must preserve supplier quote identifiers, evidence and line-level freight allocations. The service checks structural/freshness claims; it cannot authenticate a supplier's inventory from arbitrary JSON. Approval must include verifying that adapter and the underlying quotes.

## Verification

Run `ruby -Itools/distributor_pricing/test -e 'Dir["tools/distributor_pricing/test/*_test.rb"].each { |path| require_relative path }'`. Tests use clearly synthetic commercial evidence and do not pretend that fixtures are real offers. Live runs retrieve actual public listings and material publications; absent executable terms produce a procurement hold.

The authentic [Transnet RFQ example](../example_rfqs/transnet-steel-shot-2024/SOURCE.md) is an archival demand document with blank price fields. Complex public tender tables and boilerplate still require processor item-boundary work; this agent does not claim that its current intake understands every tender page.
