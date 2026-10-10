# Real RFQs

**What this is:** a folder of real requests for quote, kept so the team can read them, find patterns, and test the product against how buyers actually write. Ken (product) uses them for product decisions; Yuval and Tisch use them to test parsing and matching.

## How to add one

- One subfolder per RFQ: `YYYYMMDD_source_short-name/`, for example `20210615_iowa_tubing/`.
- Put the files in as received: the PDF, the spreadsheet, the email body as `.txt` or `.eml`.
- Add a `NOTES.md` with: where it came from (link), the date, the buyer type (government, distributor, fabricator), and anything that makes it interesting, such as the gauge trap, a hidden certification, or a contradiction.
- Public documents only. Nothing private, and no customer data.

## Saved so far (Tisch, 2026-10-10)

| Folder | What | Lines public? |
|---|---|---|
| `20210615_iowa_steel_tubing/` | State of Iowa RFQ 245, 2021, 49 lines (sheet, tube, angle, flats, expanded metal) | Yes, full PDF |
| `bidnet_2476672502/` | USAF Gulfport consumable metals RFQ FA302024Q0014, 2024: 80 A36 3/8 plates, 40 A1011 11 ga, 100 HR galvanized 26 ga, 20 5052-32 .063, 20 "2B T-304 16 Gage x 4 x 8" | Yes: full line list in `sam_notice.txt` (from SAM.gov) |
| `bidnet_2403776002/` | USACE Pleasant Valley plates, bars, angles, 2023: "ASTM A-572 G50" | Abstract only |
| `highergov_navy_hy80/` | Navy MIL-S-16216 HY-80 plate | Title and ID only (JavaScript page) |

The current Iowa link serves the same PDF as the 2021 copy (identical SHA-256), so it is saved once. The research's "Army Corps RFQ on SAM.gov" link is in fact the USAF Gulfport notice FA302024Q0014 (same as `bidnet_2476672502/`); its full public text is saved there as `sam_notice.txt`. The Army Corps solicitation is `bidnet_2403776002/`.

## Already found in the research

Tisch's uploaded examples are kept in the dedicated [example RFQ folder](../example_rfqs/README.md). The [Transnet S390 steel-shot RFQ](../example_rfqs/transnet-steel-shot-2024/SOURCE.md) includes the original PDF, extracted text and source notes. Link to that original rather than copying it here.

These public solicitations are cited in the [open-web research](../research/20261010.01_rfq_sharper_angle/research_voice_open_web.md). They are the first ones to save here.

- [State of Iowa RFQ](https://bidopportunities.iowa.gov/Home/GetBidOpportunityDocument/e7ca77d0-dcf9-41e7-ad5c-dc15cca2a45e). Its 2021 version is already saved at [iowa2021.pdf](../research/20261010.01_rfq_sharper_angle/verification_docs/iowa2021.pdf).
- [Army Corps of Engineers RFQ on SAM.gov](https://sam.gov/opp/1be44b842c6e4f8bbbf05ddbc3c61b78/view)
- [Navy RFQ for MIL-S-16216 HY-80 steel plate](https://www.highergov.com/contract-opportunity/mil-s-16216-hy-80-steel-plate-n4215826qe068-o-78f78/)
- [BidNet solicitation 2403776002](https://www.bidnetdirect.com/public/supplier/solicitations/statewide/2403776002/abstract)
- [BidNet solicitation 2476672502](https://www.bidnetdirect.com/public/supplier/solicitations/statewide/2476672502/abstract)
