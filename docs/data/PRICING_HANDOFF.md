# Matching to pricing handoff

**Owner:** Tisch (`@Tisch`). For the pricing agent (`tools/distributor_pricing/`, built with Codex) and the catalog matcher (`app/services/catalog_match/`).

## The split

- **The matcher decides which catalog item a line is.** The rep approves it on `/catalog_matches`, and it becomes a held `QuoteLine` with `catalog_sku`, spec, evidence, quantity and `unresolved_fields: ["unit_price"]`.
- **The pricing agent prices that item.** It does not re-match. If pricing matches again on its own, the price can belong to a different item than the one the rep approved.

## For the pricing agent

1. **Get the item from the matcher, not a second matcher.** For a line already approved, read it with `CatalogMatch::PricingHandoff.request_for(line)`:

   ```ruby
   { "item" => { "part_number" => "RC-STEELSHOT-S330", "item_id" => "...", ...catalog row... },
     "quantity" => "40000", "unit" => "lb",
     "requirements" => { "certifications" => ["COA"] } }
   ```

   For raw RFQ text with no approval yet, call the matcher contract: `CatalogMatch::Contract.call("line_text" => text, "spec" => fields)` in Ruby, or `bin/catalog-match` (one JSON object on stdin, one on stdout). It returns `status` (exact, scored, ambiguous, no_match), `best` with `item_id` and `part_number`, up to 3 `candidates`, and a buyer `question`. Price only `exact` or `scored`; for `ambiguous`, ask the question first.

   `DistributorPricing::Catalog#match` today uses `RfqProcessing::CatalogMatcher` plus its own RudCo rule. Please switch it to the contract above so both agents agree on the item.

2. **Return `DistributorPricing::Engine#price_line`'s result unchanged.** `CatalogMatch::PricingHandoff.apply(line:, result:)` writes it to the line:
   - `status: "ready"` with a positive `unit_price`, a `currency` and a future `quote_valid_until`: the line becomes Ready. `price_source` names the selected offer. `benchmark` holds the market low, median and high and the comparison basis, with `kind: "market"`.
   - Anything else (`needs_buyer`, `needs_procurement`, `not_competitive`, or a `ready` result missing any of those): the line stays held, `unit_price` stays unresolved, `reasons` go into the notes, and the first `buyer_questions` entry becomes the line's question when the status is `needs_buyer`.
   - A result whose `part_number` differs from the line's `catalog_sku` is refused.

3. **Catalog rows to know about:**
   - `data/rudco/`: 96 items from RudCo's site. `list_price_usd_per_lb` is RudCo's **website list price**: evidence, not a supplier offer and not a quote price.
   - `data/metals/`: 143 constructed sample items. No prices.
   - `data/aviation/`: 500 items with two public dealer observations each.

## Status

- Matcher side: built, in `main`, with tests (`test/services/catalog_match/pricing_handoff_test.rb` uses the engine's result shape).
- Pricing side: in progress in a separate checkout; not yet in `main`.
