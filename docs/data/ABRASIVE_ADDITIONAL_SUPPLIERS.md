# Additional abrasive supplier evidence

Owner: Tisch. Observed 2026-10-10, 15:35-15:36 America/New_York.

This extends [the initial supplier check](ABRASIVE_SUPPLIER_CHECK_2026-10-10.md). Direct read-only requests used `Cache-Control: no-cache`. These observations are research references. They are not a live pricing cache, a supplier commitment, or evidence of RudCo inventory. No supplier was contacted and no order was placed.

## Two additional numeric dealer references

| Requested item | Source and SKU | Current product amount | Evidence and limitations |
|---|---|---|---|
| G40 | [National Blast Supply NBS-SG40-50](https://nationalblastsupply.com/products/nbs-steel-grit-50-lb-bag-g40-medium) | USD 54.99 per 50 lb bag; 54.99 / 50 = USD 1.0998/lb | Direct HTTP 200 at 19:35:46Z. USD is present in page structured data. Page specifies high-carbon angular grit, 60-66 HRC. This hardness cannot be silently substituted for a softer grit. Exact SAE screening compliance and batch COA remain unconfirmed. Manufacturer-direct shipment is advertised, but no allocated quantity is shown. |
| G25 | [AmericanHawk Industrial Products, part 4000](https://americanhawkindustrialproducts.com/product/steel-grit/) | USD 116.00 per 50 lb bag; 116 / 50 = USD 2.32/lb | Direct HTTP 200 at 19:36:17Z. Embedded variant 450 explicitly maps `g-25-steel-grit` to SKU 4000 and `display_price: 116`; structured currency is USD. Variant 451 is G50 at USD 117 and must not be assigned to G25. Hardness, material standard and batch COA are absent. |

AmericanHawk's variant declares `is_in_stock: true`, `min_qty: 1` and no backorders. It does not give an available quantity. A 20-bag requirement therefore remains unallocated. No delivery date or applicable freight charge was verified.

National Blast Supply gives a general manufacturer dispatch estimate of 3-5 business days, transit of 5-7 business days, and total delivery of 8-10 business days. Those ranges are inconsistent: summing the component maxima gives 12 business days. Record the published estimates separately and ask the supplier to confirm destination-specific timing. Do not turn them into a firm promise. Its contiguous-US free-freight threshold is USD 2,500. Twenty G40 bags total USD 1,099.80 before unknown charges, so the requested line alone does not qualify. No bulk discount was verified.

The earlier dealer candidates plus these additions give **three numeric dealer references per grit size**, subject to specification and commercial checks. The two shot sizes remain at three previously identified dealer businesses. All four sizes still have **zero fully qualified delivered comparisons**. Five independent competitive offers per item have not yet been established.

Business identities were checked beyond the domain names. National Blast Supply's fresh page names that business at 429 5th Ave, Worthington, KY 41183, with telephone (304) 840-1445. AmericanHawk's refreshed page identifies AmericanHawk Industrial Products, LLC and telephone (269) 468-0308. These are distinct named seller/contact records. The inspected pages did not establish ultimate beneficial ownership or exclude common ownership; qualify supplier independence before promoting these research candidates into the five-offer comparison.

## Additional quote and manufacturer routes

| Supplier | Applicable item evidence | Verified state | Required next evidence |
|---|---|---|---|
| RockRidge Abrasives | [G25](https://rockridgeabrasives.com/product/steel-grit-g25/) and [G40](https://rockridgeabrasives.com/product/steel-grit-g40/) | Direct HTTP 200 at 19:36:18Z and 19:35:47Z respectively. Exact SAE J444 screening tables, high-carbon cast grit, 50 lb bags and 40 bags per pallet. No public numeric price. | Choose hardness explicitly: SG 40-51, MG 47-56, LG 54-61 or HG minimum 60 HRC. Request batch COA, buy price, available quantity, all charges and delivery. This is one supplier, not one per hardness or page. |
| Ervin Industries | [AMASTEEL grit manufacturer](https://ervinindustries.com/amasteel-grit/) | Direct HTTP 200 at 19:35:47Z. SAE J444/J1993, high-carbon tempered martensite, multiple hardness classes and 50 lb bags. No numeric offer. | Obtain exact G25/G40 commercial offer and batch documentation. Ervin is the manufacturer behind Kleen Blast's AMASTEEL listing, so shared manufacturer provenance must be retained even if dealer offers are independently priced. |
| Miles Supply | [S170, AC000014, 50 lb bag](https://www.milessupply.com/product/steel-shot-s170/) | Web-index page shows an exact S170 quote route; direct refresh returned HTTP 403. No numeric price admitted. | Refresh through a permitted channel and obtain current offer, hardness, COA, stock and delivery. |
| BlastOne | [Steel shot, AMS17050 and AMS330DRUM](https://www.blastone.com/product/steel-shot/) | Indexed catalog has S170 50 lb bag and S330 2,000 lb drum quote rows. Direct web fetch returned HTTP 403. No numeric price admitted. | Confirm exact product, hardness, pack, offer and current availability. |

## Rejected stale or unsuitable findings

[TSS Supply ERVIBs-330](https://tsssupply.com/product/ervibs330shot/) appears in the search index at USD 49.99 with a 50 lb weight and 39 units in stock. The direct current request returned HTTP 404. It is excluded from current numeric coverage and stock evidence. Even the indexed 39-package quantity would be below the 40 bags needed for 2,000 lb, assuming the weight described the sale package.

Clemtex's indexed steel-shot page is explicitly an archive and warns that prices and information may be outdated. It is not a current offer. Search results for other RudCo-branded sites are not counted as independent competitors of this project. Marketplace price ranges and manufacturer blog ranges are not exact executable offers. No invented fifth supplier was added.

## Procurement handoff

Prioritize RockRidge and Ervin for qualified grit quotations, and Miles Supply and BlastOne for shot quotations. First refresh the public pages in the actual quote run. Then obtain matched hardness, SAE standard, quantity, pack, COA, allocation, acquisition cost, currency, payment terms, freight, other landed charges, expiry and lead time. Public product prices alone cannot establish 15% target or 8% minimum gross margin for a delivered order.
