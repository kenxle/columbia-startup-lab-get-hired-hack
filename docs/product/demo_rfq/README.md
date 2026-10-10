# Demo RFQ: Northline Fabrication

**Owner:** Tisch. **Checked by:** Yuval (parsing). Fictional buyer; sample data.

- [email.txt](email.txt): the RFQ email body. Paste it into the app.
- [northline_rfq_2026-1010.pdf](northline_rfq_2026-1010.pdf) and [northline_rfq_2026-1010.csv](northline_rfq_2026-1010.csv): the same lines as attachments. Rebuild the PDF with `bin/rails runner docs/product/demo_rfq/build_pdf.rb`.
- [second_rfq_email.txt](second_rfq_email.txt): the short second RFQ from the same buyer, for beat 8 (learn the buyer).

## What each line should show

Checked against the catalog matcher (`CatalogMatch::Matcher`) on 2026-10-10 at 14:20.

| # | Line | Matcher | Why it is in the demo |
|---|---|---|---|
| 1 | Stainless 304 sheet, 16 ga, 2B, 48 x 96, 20 sheets | Match `RC-SS304-SHT-16GA-48X96-2B` | The gauge line: 16 ga reads as 0.0625 in from the stainless table. |
| 2 | Stainless 304, 0.060 in, 48 x 96, 10 sheets | **Needs the buyer**: "You wrote 0.060 in. The nearest catalog item is 16 ga (0.0625 in)..." | The gauge trap. Candidates 2B and #4 are the options. |
| 3 | SA-240 316L 3/8 plate 60 x 120, 2 plates, with 3.1 cert | Match `RC-SS316-PLT-375-60X120` | Compliance trigger words: SA-240 and 3.1 cert. |
| 4 | Steel shot S-330, 2,000 lb, in 50 lb bags | Match `RC-STEELSHOT-S330` | RudCo's own product, with RudCo's website list price as a named source. |
| 5 | P1020 aluminum T-bar ingot, 5,000 lb | Match `RC-AL-P1020-TBARINGOT` | RudCo's own product; no price source yet, so it is held. |
| 6 | Aluminum 356 notched ingot, 2,000 lb | Match `RC-AL-356-NOTCHEDINGOT` | RudCo's own product. |
| 7 | 1/2 A36 plate 5x10, 3 plates | Match `RC-A36-PLT-500-60X120` | 5x10 reads as feet (60 x 120 in). |
| 8 | 1/4-20 x 1 in hex cap screws, zinc plated, 500 pcs | **No match** | Nothing in the catalog fits; never forced onto the closest item. |

Body sentences also carry compliance words: "MTRs required on all steel" and "COA with each lot of abrasive".

## Beat 8: learn the buyer

On RFQ-0001, the buyer answers line 2: their "0.060 in" means 16 ga (0.0625 in). The rep teaches it for Northline, recorded with `confirmed_on: "RFQ-0001"`:

```ruby
CatalogMatch::ClientMemory.new(client).teach!(term: "0.060 in", fields: { "gauge" => "16", "thickness" => "0.0625" }, confirmed_on: "RFQ-0001")
```

The second RFQ's line ("Stainless 304, 0.060 in, 48 x 96, 2B, 8 sheets") then matches `RC-SS304-SHT-16GA-48X96-2B` directly, and the reading says "Northline Fabrication (taught by the rep, confirmed on RFQ-0001)". Another buyer writing the same words still gets the question.
