# Domain Rules: Specs, Gauges and Hidden Requirements

**Track:** Domain rules (research questions 2, 3 and 4 in the [research brief](brief_rfq_sharper_angle.md)). Written 2026-10-10.

## Summary: what this track found

- **The gauge trap is real, checkable, and already in our own product brief.** The [product brief](../../product/PRD.md) shows "304 SS sheet 16ga" and "Stainless 304, 0.060 in" as the same item. They are not. 16 gauge stainless is 0.0625 in. 0.060 in matches 16 gauge *mild steel* (0.0598 in). The gap is 4.2% of thickness. A demo that gets this right, and says why, is easy to verify live.
- **Hidden requirements are real, but most of them are not in the line.** Three of the five big ones (DFARS, Buy America, ITAR) are triggered by the *contract, the project, the ship-to, or an attached drawing*. The grade only decides whether the rule bites. The one real public metals RFQ I found (State of Iowa, line numbers 1 to 49) names no certification or metal origin requirement on any line. Its only origin wording is a general Iowa-products preference for tied bids. A tool that flags hidden requirements must read the whole RFQ package, and must stay quiet when nothing triggers.
- **Some requirements can be read straight off the line.** A spec prefix or word often implies paperwork: `SA-240` (ASME code material), `A500` (structural tube that ships with a mill test report), `304/304L` (dual chemistry), `NACE`, `DFARS`, `Buy America`, `domestic`, `3.1`, `PMI`. These are the safest flags to show first.
- **The costliest mistakes cannot be fixed with paperwork afterward.** Wrong origin (melted abroad), wrong grade, and wrong spec family (A513 vs A500, A53 vs A500) mean the physical metal is wrong. A wrong gauge table is cheaper but is silent: it is a 4.5% to 24% thickness error that still looks like a clean quote.
- **Public evidence has a ceiling.** ASTM and ANSI pages are paywalled or blocked (403). Most spec facts below come from distributors, trade associations, and forums. Each claim carries a confidence tag. I found no public dollar figure for what a misread RFQ line costs a supplier. The ranking in "Costliest reading errors" is my judgment from the consequences, and says so.

---

## 1. How the same item gets written different ways

### 1.1 Gauge: the number means a different thickness for each metal

**A gauge number is not a thickness. Each material family has its own table.** Metal Supermarkets, a metals distributor, publishes one table per material and says: "when measuring sheet product, gauges are neither standard nor metric, and have independent values." Its example: an 8 gauge aluminum sheet is 0.1285 in, an 8 gauge stainless sheet is 0.17187 in ([Metal Supermarkets, sheet vs plate](https://www.metalsupermarkets.com/the-difference-between-metal-sheet-and-plate/)).

**Gauge values for the common gauges, inches** (source: [Metal Supermarkets sheet metal gauge chart](https://www.metalsupermarkets.com/sheet-metal-gauge-chart/); tube wall column from [Wikipedia, Sheet metal, gauge table](https://en.wikipedia.org/wiki/Sheet_metal)):

| Gauge | Mild (carbon) steel | Galvanized steel | Stainless steel | Aluminum | Steel tube wall |
|---|---|---|---|---|---|
| 10 | 0.1345 | 0.1382 | 0.14062 | 0.1019 | 0.134 |
| 11 | 0.1196 | 0.1233 | 0.125 | 0.09074 | 0.120 |
| 12 | 0.1046 | 0.1084 | 0.10937 | 0.08081 | 0.109 |
| 14 | 0.0747 | 0.0785 | 0.07812 | 0.06408 | 0.083 |
| 16 | 0.0598 | 0.0635 | 0.0625 | 0.05082 | 0.065 |
| 18 | 0.0478 | 0.0516 | 0.050 | 0.04030 | 0.049 |
| 20 | 0.0359 | 0.0396 | 0.0375 | 0.03196 | 0.035 |

- **Two published sources agree to the digit** on the mild steel, galvanized, and stainless columns. They differ on one aluminum cell: 14 gauge aluminum is 0.06408 in at Metal Supermarkets and 0.063 in at Wikipedia (a 1.7% gap). Evidence: both links above. Confidence: high for steel and stainless, medium for aluminum.
- **Metal Supermarkets prints a caveat under its charts:** "Actual thickness will vary due to tolerances." Wikipedia adds that the Manufacturers' Standard Gauge "has no inherent tolerances," and quotes ASTM calling the gauge number an "archaic term of limited usefulness not having general agreement on meaning" ([Wikipedia](https://en.wikipedia.org/wiki/Sheet_metal)). So the table gives the nominal value. The buyer's tolerance is a separate question.
- **Tube is its own table.** 14 gauge tube wall is 0.083 in; 14 gauge mild steel sheet is 0.0747 in. That is 11.1% apart. 16 gauge tube wall (0.065) is 8.7% thicker than 16 gauge sheet (0.0598). The rule must know the *form* (tube or sheet), not only the material.
- **Real suppliers do not always follow the table.** Speedy Metals lists "10ga (0.135") 304 Stainless Steel Sheet" ([Speedy Metals](https://www.speedymetals.com/information/Material58.html)), which is 4.0% under the stainless table value (0.14062) and close to the mild steel value (0.1345). The University of Alberta store lists "0.063 (16 Ga.)" 304 sheet, 1/16 in, 2B ([UAlberta](https://marketplace.ualberta.ca/products/stainless-steel-sheet)): the same item written three ways in one listing, with 0.063 rounding the table's 0.0625 by 0.8%. Confidence: high that suppliers differ; I cannot say which supplier is "right."
- **Sizes of the errors** (computed by [domain_rules_gauge_calc.py](domain_rules_gauge_calc.py) from the table above):

| Wrong-table mistake | Thickness error |
|---|---|
| Stainless read with the mild steel table, gauges 10 to 20 | +4.5% to +4.6% (0.0027 in at 16 gauge) |
| Galvanized read with the mild steel table | +2.8% at 10 gauge, +6.2% at 16, +10.3% at 20 |
| Aluminum read with the mild steel table | -11.0% to -24.2% |
| 16 gauge stainless vs the PRD's "0.060 in" | +4.2% |

**What the product should do:** look the gauge up in a table keyed by material *and* form, show the table name and value on screen, and ask when the material is missing ("16 ga sheet 4x8" with no metal has four candidate answers: 0.0598, 0.0625, 0.0635, 0.0508 in). When the buyer wrote both a gauge and a decimal that disagree under the right table (as in the PRD example), ask which one governs.

### 1.2 Size notation: feet, inches, and positional shorthand

**The same sheet is "4x8", "4' x 8'", "48 x 96", or "48" x 96"".** 4 ft x 8 ft is 48 in x 96 in, which is 1219 mm x 2438 mm. 4 x 10 ft is 48 x 120 in. (Computed in the calc script; the 48 x 96 and 4x8 pairing appears in the [State of Iowa RFQ](https://bidopportunities.iowa.gov/Home/DownloadBidOpportunityDocument/1896a227-c6a4-4be5-8283-11490aefe20a), which writes "Cold Rolled Sheets 4 x 10" on one line and "48" x 120" x 14 Gauge" under it.)

**Unit marks are dropped, so the meaning of a number depends on the product form.** The Iowa RFQ shows it line by line. In "Strips 3 x 20 x 1/8"" the detail line says 3 in wide, 20 *feet* long, 1/8 in thick. In "Structural Angle 3 x 3 x 1/4" the same notation means inches for all three numbers, and the length (20 ft) sits only in the detail line. In "RectangleTubes 2 x 1.5 x 24 x .120", 24 is feet and .120 is a wall in decimal inches. Evidence: [Iowa RFQ 245, lines 1 to 10](https://bidopportunities.iowa.gov/Home/DownloadBidOpportunityDocument/1896a227-c6a4-4be5-8283-11490aefe20a). Confidence: high (one real RFQ, direct text). So the parser needs product-form rules: which number is length, which is thickness, which unit is usual.

**Fractions and decimals both appear.** The same RFQ writes 1/8" and .120 in adjacent lines. Plate is usually fractional, sheet is usually gauge ([Metal Supermarkets](https://www.metalsupermarkets.com/the-difference-between-metal-sheet-and-plate/)).

### 1.3 Grade notation

- **304, 304L, and "304/304L" are three different requests.** 304 allows carbon up to 0.08%; 304L allows 0.03%; the A240 chemistry rows are 304: 0.08 C max, 18.0 to 20.0 Cr, 8.0 to 11.0 Ni and 304L: 0.03 C max, 8.0 to 12.0 Ni ([Saky Steel, A240 grades](https://www.sakysteel.com/news/astm-a240-stainless-steel-plate-grades-finish-and-testing), vendor table, medium confidence).
- **Dual certified 304/304L is one heat that meets both.** Distributors sell it as "meets specifications for both 304 and 304L" ([Speedy Metals](https://www.speedymetals.com/information/Material58.html)). Engineers on Eng-Tips describe it as meeting the mechanicals of straight grade and the chemistry of L grade ([Eng-Tips thread](https://www.eng-tips.com/viewthread.cfm?qid=450930), forum, medium-low confidence). An ASME interpretation quoted there allows dual-stenciled plate to be used as either grade at or below 1000 F.
- **Substitution only runs one way.** A line that says 304 *or* 304L can usually be filled with dual-cert stock. A line that says "304L" cannot be filled with plain 304 stock whose carbon is above 0.03. A line that says "304/304L" asks for the dual cert itself. This is my reading of the chemistry limits above; confirm the buyer's spec before substituting.
- **A36 and A572 Grade 50 can be the same plate.** A36 has no upper yield limit, so producers sell one plate certified to both. A36 minimum yield is 36 ksi; A572 Grade 50 is 50 ksi. If the buyer buys it as A36, they design to 36 ksi; to design at 50 ksi it must be certified to A572 Grade 50 ([AISC Steel Interchange, July 2014](https://www.aisc.org/globalassets/modern-steel/steel-interchange/2014/072014_si.pdf) as summarized in search results; the PDF itself returned 403 to me; supported by [Tampa Steel](https://tampasteel.com/a36-vs-a572-steel/)). Confidence: medium.
- **Aluminum temper is part of the grade.** 6061-T6 and 6061-T651 differ: T651 is the stress-relieved form for plate ([MakeItFrom](https://www.makeitfrom.com/material-properties/6061-T651-Aluminum), medium-low). A buyer who writes "6061-T6 plate" often means T651; ask.

### 1.4 Finish

- **2B is the standard cold-rolled mill finish; No. 4 is a brushed finish.** "No. 2B is the mill finish, meaning it has not been processed further." No. 4 has "a pattern of fine parallel lines" and varies between suppliers, so Metal Supermarkets suggests asking for a sample ([Metal Supermarkets finishing options](https://www.metalsupermarkets.com/stainless-steel-finishing-options/)). Speedy Metals defines 2B as "cold rolled on polished rolls, annealed, pickled, and skin passed" and #4 as "polished with fine abrasive finish" ([Speedy Metals](https://www.speedymetals.com/information/Material58.html)), but its own product list says "#2 Finish" for the same sheets, so even one vendor mixes labels. ASTM A480 is named as the stainless sheet and strip finish standard by a Finishing.com answer, but I did not read its text ([Finishing.com](https://www.finishing.com/128/66.shtml), forum, low confidence).
- **Finish is often missing.** The Iowa line "Type 304-2B" gives it; many lines do not. Missing finish on stainless sheet is a question, not a default.

### 1.5 Form: sheet vs plate vs flat bar

- **The common cutoff is 1/4 in (0.250 in, 6.35 mm).** Plate is 1/4 in or thicker; thinner is sheet. Metal Supermarkets applies this to all metals. Wikipedia says the same: "thicker than 6 mm (0.25 in) are considered plate" ([Metal Supermarkets](https://www.metalsupermarkets.com/the-difference-between-metal-sheet-and-plate/), [Wikipedia](https://en.wikipedia.org/wiki/Sheet_metal)). Confidence: high for the convention.
- **The standards use other lines.** A forum post quotes ASTM A6 (carbon structural steel) as treating hot-rolled material as plate at 0.230 in or thicker for widths 8 to 48 in, and 0.180 in or thicker over 48 in wide; and notes the sheet spec A568 caps hot-rolled sheet at 0.230 in ([Eng-Tips](https://www.eng-tips.com/viewthread.cfm?qid=249559), forum quote of a standard I could not open; low-medium confidence). Other sources use 3 mm (0.118 in) as the line. So a 3/16 in (0.1875 in) item is sheet by the 1/4 in rule and plate by the 3 mm rule. A line in that range needs the buyer's word for what it is.
- **Narrow flat stock is a third category.** A flat 0.230 in or thicker and 6 to 8 in wide is classed as bar in A6 per the same forum and an AISC table cited in search results (secondary; I could not open either). Several Iowa lines are 1 in to 6 in flats; they are bar or flat bar, not sheet or plate.

---

## 2. Common specs by product form

| Form | Common specs | What the spec tells you | Source and confidence |
|---|---|---|---|
| Stainless sheet, strip, plate | **ASTM A240** (ASME twin: SA-240) | Covers chromium, chromium-nickel, and chromium-manganese-nickel plate, sheet and strip "for pressure vessels and for general applications"; does not by itself fix grade, finish or cert type | [Saky Steel](https://www.sakysteel.com/news/astm-a240-stainless-steel-plate-grades-finish-and-testing) (vendor, medium) |
| Carbon structural plate and shapes | **A36**, **A572 Gr 50** (A6 is the general-requirements spec) | A36: 36 ksi min yield. A572-50: 50 ksi. Often dual certified | [AISC via search](https://www.aisc.org/globalassets/modern-steel/steel-interchange/2014/072014_si.pdf) (medium) |
| Structural tube (HSS) | **A500** Gr B/C | Round, square, rectangular; physical properties verified; each bundle ships with a mill test report; Grade C yield 46 ksi | [Atlas Tube](https://atlastube.com/?p=4627), [Steel Tube Institute](https://steeltubeinstitute.org/resource/a500-versus-a53-different-inside/) (manufacturer and trade group, medium-high) |
| Mechanical tube | **A513** | Tighter dimensions; "no physical requirements or structural verification"; no MTR provided in Atlas's comparison | [Atlas Tube](https://atlastube.com/?p=4627) (medium) |
| Carbon pipe | **A53** Gr B | Round only; sold by nominal size and schedule; 21 and 42 ft lengths; hydrotested; pressure and mechanical use | [Steel Tube Institute](https://steeltubeinstitute.org/resource/a500-versus-a53-different-inside/) (medium-high) |
| Austenitic stainless pipe | **A312** | Seamless and welded stainless pipe. I did not find a source for the scope in this session; general industry knowledge | Unverified here |
| Stainless bar | **A276** (general use, machining) and **A479** (boiler and pressure vessel use) | Same chemistry for 304 and 316 in vendor tables; the choice signals the end use and documentation | [Saky Steel](https://www.sakysteel.com/news/astm-a276-vs-astm-a479-stainless-steel-bar-standards/), [MachineMfg](https://shop.machinemfg.com/astm-a276-vs-astm-a479-key-differences) (vendors, medium-low) |
| Aluminum sheet and plate | **ASTM B209** | "Aluminum and aluminum-alloy flat sheet, coiled sheet, and plate" | [ASTM store listing](https://store.astm.org/b0209-14.html) (standards body, scope line, high) |
| Aluminum extrusions (bar, shape, tube) | **B221** | Extruded bars, rods, profiles, tubes. Taken from search summaries; the ASTM page was not reachable | Medium-low |

**Spec mixing is common in real RFQs.** Iowa lines write "Square Tube A513-A500 Grade B" (two different specs, one grade) and "Hot Rolled Strips CQ-A36" (a sheet quality term fused to a structural grade). A500 is structural with verified properties; A513 is mechanical with no property requirements ([Atlas Tube](https://atlastube.com/?p=4627)). These are different products, so the line is a question, not a reading.

**ASME SA vs ASTM A.** The `S` prefix means ASME reviewed and adopted the ASTM spec for Boiler and Pressure Vessel Code use. "Material supplied to an SA specification meets the requirements of the ASME Boiler and Pressure Vessel Code, Section II." Some grades are identical; others carry extra ASME requirements. Many mills dual-mark so one piece serves both ([Wermac](https://wermac.org/societies/ASME_SA_vs_ASTM_A.html), engineering reference site, medium). Chemistry can differ by edition: a forum shows SA-240 Type 304 chromium at 18 to 20% while a later A240 edition listed 17.5 to 19.5% ([CR4 thread via search](https://cr4.globalspec.com/thread/63646/ASME-MATERIAL-ASTM-EDITION-2004-VS-ASTM-2010-MATERIAL), low).

**AMS (aerospace) specs:** not researched in this pass because AMS documents are paid SAE standards and no public source came up. Treat an `AMS` number on a line as a trigger for "aerospace, ask for certs and origin" until someone with access checks.

---

## 3. Hidden requirements: what triggers each one

### 3.1 Summary table

| Requirement | Triggers inside the line | Triggers outside the line | Confidence |
|---|---|---|---|
| **Mill test report (MTR)** | Spec families that ship with one (A500); "MTR", "certs", "cert", "3.1"; pressure and code grades (A240 for vessels, A312, A479, SA-xxx) | Buyer's PO terms, project specs, code work; service-center defaults | High |
| **EN 10204 3.1 / 3.2** | "3.1", "EN 10204", "3.2", "witnessed" | Export orders, EPC and oil and gas buyers | Medium-high |
| **DFARS 252.225-7009 (specialty metals)** | "DFARS", "specialty metals", "melted in USA", "qualifying country"; chemistry that is a specialty metal (any stainless, nickel alloy, titanium) | Defense contract flow-down; defense-contractor ship-to; DPAS rating (DO or DX) on the PO | Medium-high |
| **Buy America / BABA** | "Buy America", "domestic", "American made", "23 CFR 635.410", "melted and manufactured in USA" | Federal or state-DOT-funded project; water or transit infrastructure grants | Medium-high |
| **Country of origin / melt-and-pour** | "Domestic only", "no China", "melted and rolled in USA", "mill origin" | Government buyer, project spec | Medium |
| **ITAR** | "ITAR", "export controlled"; rare in raw metal text | A drawing or spec attached with an ITAR marking; defense program name | Low-medium |
| **PMI (positive material identification)** | "PMI", "100% PMI", "XRF verified" | Refinery, chemical, high-temperature piping, sour service | Medium |
| **NACE MR0175 / ISO 15156** | "NACE", "MR0175", "sour service", "H2S", "HIC" | Oil and gas, refinery project | Medium |
| **ASME SA (code material)** | `SA-240`, `SA-312`, `SA-516`, "ASME", "code material", "U-stamp" | Pressure vessel or boiler fabricator as the buyer | Medium-high |

### 3.2 Detail, one requirement at a time

**Mill test reports (MTR).** **An MTR reports one heat's chemistry and mechanical tests; whether the buyer gets one is set by the order, not by the metal.**
- AISC states the content of an MTR for hot-rolled plates and shapes comes from ASTM A6 Section 14: heat number, grade, sizes, tension and chemistry results. Whether one must be furnished is set by the purchase order or project spec ([AISC Steel Solutions Center](https://aisc.org/steel-solutions-center/engineering-faqs/1.3.-ordering-steel), [AISC Steelwise Aug 2014](https://www.aisc.org/globalassets/modern-steel/steelwise/steelwise-august-2014.pdf), both as summarized by search; the AISC pages returned 403 to me).
- Service centers differ on the default. Ryerson's instructions to its own suppliers say: "Mill test reports are required on all products unless otherwise specified in the Purchase Order" ([Ryerson M200](https://www.centralsteel.com/-/media/files/ryerson-general-instruction-specification-m200-rev-9-2023.ashx), medium). So for RudCo the real question is whether it *keeps heat traceability on cut pieces*, not whether a certificate exists somewhere.
- A500 tube ships with an MTR per bundle; A513 does not ([Atlas Tube](https://atlastube.com/?p=4627)). A buyer who writes `A513` may expect no cert; one who writes `A500` expects one.

**EN 10204 certificate types.** **3.1 is the usual request for critical material; it means test results from the delivered lot, signed by the manufacturer's independent inspector.**
- 2.1: compliance statement only, no test results. 2.2: manufacturer test results from non-specific inspection (not tied to your lot). 3.1: specific test results from the material supplied, signed by an authorized inspector independent of production. 3.2: 3.1 content plus validation by the buyer's representative or a designated third party ([Material Welding](https://www.materialwelding.com/material-test-certificates-explained), [Project Materials](https://blog.projectmaterials.com/quick-answers/epc/en-10204-certificate-types/); vendor and blog sources agree with each other; the standard itself is paid). One of them contradicts itself on who issues a 3.1, so confirm with the buyer's spec. Confidence: medium-high on the four types.
- 3.2 involves a third-party inspector and can add scheduling, so it is a flag that needs a human, not an auto-quote.

**DFARS 252.225-7009 (Restriction on Acquisition of Certain Articles Containing Specialty Metals).** **The clause says specialty metals in delivered items must be melted or produced in the United States, its outlying areas, or a qualifying country. The grade decides whether the rule *can* apply; the contract decides whether it *does*.**
- Specialty metals are defined by chemistry: steel with more than 0.25% of aluminum, chromium, cobalt, molybdenum, nickel, niobium, titanium, tungsten, or vanadium (or above set manganese, silicon, or copper limits); nickel and cobalt alloys above 10% other alloying metals; titanium and zirconium alloys ([DFARS 252.225-7009 on acquisition.gov](https://www.acquisition.gov/dfars/252.225-7009-restriction-acquisition-certain-articles-containing-specialty-metals.)). By that definition 304 and 316 stainless (18% chromium, per the chemistry in section 1.3) are specialty metals; ordinary A36 plate is generally not (my reading; chemistry check needed).
- The clause must flow down to subcontracts, including commercial ones, for items containing specialty metals (paragraph (e)). So a distributor gets the rule from its customer, not from the government.
- Exceptions exist (commercial off-the-shelf items, a 2% minimal-content rule, a government availability determination), each with conditions. "Specialty metal mill products" are carved out of the COTS exception: bare sheet, plate and bar do not get that exemption.
- Triggers outside the line: a defense-contractor ship-to, a DPAS rating (a "DO" or "DX" symbol) on the PO, a government contract number. A DPAS-rated order carries its own duties: written acceptance or rejection within 15 working days for DO and 10 days for DX, and the rating must pass to the supplier's suppliers ([15 CFR 700.13](https://www.law.cornell.edu/cfr/text/15/700.13), [DLA DPAS brochure](https://www.dla.mil/Portals/104/Documents/Warstopper/DPAS%20Program%20Brochure%202026_V5_.pdf), summarized by search).
- Confidence: high on the clause text (primary source via fetch). Medium on the COTS detail.

**Buy America / Build America, Buy America (BABA).** **For federally funded highway work, steel and iron must have all manufacturing processes, including coating, in the United States, and the mill test report must say where it was melted and manufactured.**
- The federal rule: no permanently incorporated iron or steel, or all manufacturing processes, "including application of a coating," must occur in the US. Coating covers galvanizing, epoxy and painting; the coating *material* is not covered ([23 CFR 635.410 on eCFR](https://www.ecfr.gov/current/title-23/chapter-I/subchapter-G/part-635/subpart-D/section-635.410), [FHWA Buy America Q&A](https://www.fhwa.dot.gov/construction/contracts/buyam_qageneral.cfm), both via search summaries). If any bending, drilling, or coating happens abroad, the product becomes foreign.
- State DOTs add paperwork rules. Caltrans says mill test reports must state where steel was melted and manufactured. Montana DOT rejects a bare "meets Buy America" and wants wording like "Melted and Manufactured in the United States" or "Complies with 23 CFR 635.410" ([Caltrans](https://dot.ca.gov/-/media/dot-media/programs/construction/documents/contract-administration/buy-america/6104n081126a11y.pdf), [Montana DOT form](https://mdt.mt.gov/other/webdata/external/materials/forms/f406.pdf)).
- BABA (federal infrastructure grants beyond highways): EPA's FAQ says the key step is the initial melting and pouring, which must be in the US, and raw materials need not be domestic ([Maine SRF reproduction of EPA FAQ](https://www.maine.gov/dep/water/grants/SRF/BABAContractorFAQs.pdf)). Thresholds in these state and agency documents (0.1% or $2,500 minimal use; 50% or 55% manufactured products) differ by document, so I do not list them as rules.
- Confidence: medium-high on the core rule; these are agency summaries, not me reading the regulation in full.

**Country of origin and "melted and manufactured."** Two different questions get blended in RFQs. **Where was it melted and poured** (the furnace), and **where was it rolled or finished**. DFARS asks about melting or producing; Buy America asks about all manufacturing steps including coating. A buyer who writes only "domestic" has not said which. This is a clarifying question, not a guess.

**ITAR.** **Raw metal is rarely ITAR itself; the controlled item is usually the drawing or technical data attached to the RFQ.** I found no public source that settles whether plain mill-form titanium or stainless is on the US Munitions List. The sources I found describe ITAR as covering articles specially designed for military or space use and their technical data ([voestalpine ITAR program](https://www.voestalpine.com/highperformancemetals/canada/en-ca/itar-controlled-goods-compliance/), [Performance Titanium export FAQ](https://performancetitanium.com/faq-exporting-titanium-products-from-the-united-states/), which points to the Export Administration Regulations and end-use checks instead). Confidence: low. The safe product behavior is a flag when an attachment or line says "ITAR" or "export controlled": do not forward the files outside the quoting team, and ask the buyer about handling.

**PMI (positive material identification).** **PMI checks the metal's actual chemistry with a handheld analyzer, not the paperwork.** It is governed by API RP 578 and ASTM E1476; full (100%) checks are typical for critical alloy systems, sour service, and high-temperature piping, with sampling elsewhere ([Mistras](https://www.mistrasgroup.com/field-services/core-ndt-services/positive-material-identification/), [Fabrico](https://www.fabrico.io/blog/positive-material-identification/), vendor pages, medium-low; I did not read API 578). If a line says "PMI," the open question is whether RudCo performs it, supplies a report, or whether the buyer does it on receipt.

**NACE MR0175 / ISO 15156 (sour service).** **For carbon and low-alloy steel the common limit is 22 HRC maximum hardness, which the buyer will usually want shown on the MTR.**
- Several sources give 22 HRC (about 248 HV10 or 237 HBW); one forum quoting the standard says it applies to carbon and low-alloy steels under 1% nickel in normalized, normalized and tempered, or quenched and tempered condition ([Project Materials](https://blog.projectmaterials.com/quick-answers/materials/what-is-nace-mr0175/), [TWI](https://twi-global.com/technical-knowledge/job-knowledge/complying-with-nace-hardness-requirements-119); medium).
- The standard itself does not require a conformance statement on the certificate, according to a NACE interpretation quoted in search results (I could not trace the page; low). So a purchase order should ask for hardness values and heat-treat condition, not just "NACE compliant." Austenitic stainless base metal has no HRC limit per the sources I found, but weld and cold work rules apply.

---

## 4. Costliest reading errors

**My ranking, by whether the mistake can be fixed after the metal ships.** This is judgment from the consequences above. I found no public study that prices misread RFQ lines, and I did not find one gauge-error incident with a published dollar cost.

1. **Wrong or missing origin (DFARS, Buy America).** Metal melted abroad cannot be repaired. The buyer may have to reject it, and a supplier that certifies wrong has legal exposure. Related enforcement example, on the *testing* side: Bradken paid $10,896,924 to resolve False Claims Act allegations that an employee falsified test results on steel components for Navy vessels ([DOJ press release](https://www.justice.gov/opa/pr/bradken-inc-pays-108-million-resolve-false-claims-act-allegations-involving-substandard-naval), [US Attorney, W.D. Wash.](https://www.justice.gov/usao-wdwa/pr/bradken-inc-pays-108-million-settle-false-claims-act-allegations-and-enters-deferred); fetched via search summary). That case is about falsified data, not misreading an RFQ. It shows how seriously certs are treated.
2. **Wrong grade or wrong spec family.** 304 vs 316, A36 vs A572-50, A500 vs A513, A53 vs A500. Paperwork cannot turn one into the other. The cleanest public stake example is a materials failure from chemistry alone: the 2012 Chevron Richmond refinery fire traced to sulfidation corrosion in a carbon steel pipe with low silicon ([CSB](https://www.csb.gov/recommendations/csb-investigations-mechanical-integrity/), [Process Engineering](https://processengineering.co.uk/article/2016120/pipeline-corrosion-c)). That was an inspection and design failure, not an RFQ reading error. I include it only to show that chemistry is not cosmetic.
3. **Missing certification the buyer needed.** Often fixable if the heat was tracked and the mill cert exists; not fixable if cut stock lost its heat number. Depends on RudCo's traceability, which I could not see.
4. **Wrong gauge table.** Silent, because the quote looks normal. 4.5% thick on stainless, up to 24% thin on aluminum read with the steel table. Whether it fails depends on the buyer's tolerance.
5. **Wrong unit or position (x4 as quantity vs dimension; feet vs inches; 4x8 ft vs 4x8 in).** Easy for a rule to catch, and large when missed, so a parser should never guess.
6. **Sheet vs plate at the boundary (3/16 in).** Changes price, flatness, and the spec; usually caught on the first email back.

---

## 5. What this means for the two decisions

- **Put first: reading accuracy with the table shown, then flags.** The gauge table, the unit rules, and the one-way substitution rules are deterministic and checkable. Judges "test it against real cases"; these are the cases they can test.
- **"Catches hidden requirements" can be a strong angle only if it is precise.** Evidence for: the requirements are real, costly, and absent from tools that only parse lines (the existing-tools track covers that). Evidence against: many triggers sit outside the line, the one real RFQ I found shows none, and a tool that flags everything breaks the PRD's own test ("No clear line gets a question it did not need"). Frame each flag as "this implies X because of Y; confirm," never as a legal ruling.
- **A cheaper way to show the same strength:** a flag with its trigger text highlighted (for example "domestic" or `SA-240` or the ship-to) combines the hidden-requirements angle with "the quote shows its work."
- **Fix in the PRD:** the example pair for "the same item written five ways" lists two items that differ by 4.2% in thickness. Use the test set below instead.

---

## 6. Test set

**How to read this.** `V` = verbatim text from a cited public document (the line text is exact; I removed nothing). `C` = constructed by me from cited rules; the text is mine, the facts it tests are cited. Each line gives the standard reading and, when the reading is genuinely open, the question to ask. All thicknesses are inches. Gauge values come from the [Metal Supermarkets chart](https://www.metalsupermarkets.com/sheet-metal-gauge-chart/) unless stated. Unit conversions and gaps come from [domain_rules_gauge_calc.py](domain_rules_gauge_calc.py).

**Sources for verbatim lines:** `Iowa` = [State of Iowa RFQ 245, issued 2018-08-28](https://bidopportunities.iowa.gov/Home/DownloadBidOpportunityDocument/1896a227-c6a4-4be5-8283-11490aefe20a). Its lines (numbered 1 to 49) name no mill test report, certification, or metal origin requirement. The only origin wording is a general preference for Iowa products when bids tie. `SacRT` = [Sacramento Regional Transit District steel road plates solicitation](https://app.govly.com/public/opportunities/16741246). `UAlberta` = [catalog listing](https://marketplace.ualberta.ca/products/stainless-steel-sheet).

### Verbatim lines

**T1. V, Iowa line 20, quantity 19 EA**
`Stainless Steel Sheets Type 304-2B` / `Stainless Sheets 4 x 10` / `48" x 120" long x 16 Gauge`
- Reading: stainless steel, grade 304, finish 2B, sheet, thickness **0.0625** (stainless table; some suppliers list 0.063 or a different decimal, see section 1.1), width 48, length 120 (10 ft), quantity 19, spec not written (A240 is the usual spec family).
- Ask: "Is 16 gauge 0.0625 in nominal, or do you need a specific decimal? Do you accept 304/304L dual cert? Do you need a mill cert?"
- Why it is here: a clean reading with a gauge-table lookup and a quiet, optional cert question.

**T2. V, Iowa line 9, quantity 2 EA**
`Cold Rolled Sheets QC/ A366` / `48" x 120" x 14 Gauge`
- Reading: carbon (mild) steel, cold-rolled sheet, thickness **0.0747** (mild steel table), width 48, length 120, quantity 2. "QC" probably means a quality designation; A366 is an older cold-rolled sheet spec whose current status I did not verify.
- Ask: "Is 'QC / A366' commercial quality? Current specs for cold-rolled sheet are A1008-family; do you accept a current equivalent?" (The A1008 and A366 facts are general knowledge, not checked here; a human should confirm before the demo asserts them.)

**T3. V, Iowa line 1, quantity 24 EA**
`Square Tube A513-A500 Grade B` / `2" x 2" x 24' long x .188 thick`
- Reading: carbon steel, square tube, 2 x 2 in, wall **0.188**, length 288 in (24 ft), quantity 24. Spec is **ambiguous**: A513 (mechanical, no property requirements) and A500 (structural, verified properties, ships with MTR) are written together.
- Ask: "Structural tube (A500 Grade B) or mechanical tube (A513)? Do you need the mill test report?"

**T4. V, Iowa line 11, quantity 10 EA**
`Expanded Stainless 4 x 8` / `Expanded Stainless Flat` / `48" x 96" x 13 GA x 1 1/2" Diamond`
- Reading: expanded stainless steel metal, flat, 48 x 96 in (4 x 8 ft), "13 GA", 1 1/2 in diamond, quantity 10. Grade not stated.
- Cannot resolve: 13 gauge does not appear in the stainless sheet table I cited, and expanded metal sells by its own stock numbers. **Thickness: unknown.**
- Ask: "What is the strand thickness in inches, or the expanded-metal stock number? What stainless grade?" This is a case where the right behavior is to say "I do not know," not to look something up.

**T5. V, Iowa line 6, quantity 10 EA**
`Hot Rolled Strips CQ-A36` / `3" x 20' long x 1/8" thick`
- Reading: carbon steel, hot-rolled flat, width 3, thickness **0.125**, length 240 in (20 ft), quantity 10.
- Ask: "Hot-rolled A36 flat bar, or commercial-quality strip? 'CQ' and 'A36' are different specs." Form is flat bar or strip (0.125 is under the 0.230 in A6 bar line quoted in section 1.5).

**T6. V, Iowa line 13, quantity 10 EA**
`Stainless Tubes Type 304` / `1 1/4" x 1 1/4" x 20' long x .120 thick`
- Reading: stainless 304, square tube, 1.25 x 1.25 in, wall **0.120**, length 240 in, quantity 10. No spec written.
- Ask: "Welded or seamless? Mechanical tubing or pressure? Finish (mill or polished)?" Note .120 is a decimal wall, not a gauge.

**T7. V, Iowa line 23, quantity 5 EA**
`Aluminum Flat 6061-T6` / `1" x 12' Long x 1/8" thick`
- Reading: aluminum 6061, temper T6, flat bar, width 1, thickness **0.125**, length 144 in, quantity 5.
- Ask: "Extruded flat bar, or rolled/cut from sheet?" (B221 covers extrusions; B209 covers flat-rolled sheet and plate.) Low-cost question.

**T8. V, SacRT road plates, quantity two**
`ASTM A36 or A572 Gr. 50 equivalent hot-rolled carbon steel` / `8 feet x 20 feet x 1 inch thick` / `Corrosion-resistant coating (primer plus industrial enamel, galvanized, or equivalent)`
- Reading: carbon steel plate, hot-rolled, thickness **1.000**, width 96 in, length 240 in, quantity 2. Grade: either A36 or A572-50 is acceptable ("or"), so a dual-cert plate fits.
- Ask: "Which coating: primer and enamel, or galvanized?" The "equivalent" wording invites a ruling on what counts as equivalent; the safe answer is dual-certified A36/A572-50.
- Hidden requirements in the listing: none stated. The full PlanetBids document may add some; I did not see it.

**T9. V, UAlberta catalog listing (not an RFQ; one item written three ways)**
`Stainless Steel Sheet 304` / thickness `1/16 in` / `0.063 (16 Ga.)` / `2B Mill Finish` / `12 in x 12 in`
- Reading: 304, sheet, 2B, thickness **0.0625** (1/16 in; also the stainless 16 gauge value), 12 x 12 in, quantity 1. The listing's 0.063 rounds 0.0625 by 0.8%.
- Ask: none. This is the positive control: three notations, one thickness.

### Constructed lines

**T10. C, from the PRD's example, quantity missing**
`304 SS sheet 16ga 4x8`
- Reading: stainless 304, sheet, **0.0625**, 48 x 96 in, spec not written, finish not written, quantity missing.
- Ask: "How many sheets? Finish: 2B, No. 4, or other? Do you accept 304/304L dual cert?"

**T11. C, the PRD's second example**
`Stainless 304, 0.060 in, 48 x 96`
- Reading: stainless 304, **0.060** exact as written, 48 x 96 in. Under the stainless table, 16 gauge is 0.0625 (4.2% thicker). 0.060 matches 16 gauge *mild steel* (0.0598).
- Ask: "Do you need 0.060 in exactly, or is 16 gauge (nominal 0.0625) acceptable?" This is the gauge trap in one line.

**T12. C, material missing**
`16 ga sheet 4x8 qty 20`
- Reading: **cannot be read.** Four tables apply: mild steel 0.0598, galvanized 0.0635, stainless 0.0625, aluminum 0.05082. Width 48, length 96, quantity 20.
- Ask: "What material: carbon steel, galvanized, stainless (which grade), or aluminum (which alloy)?"

**T13. C, galvanized gauge**
`16 ga galv 4x10 x 25`
- Reading: galvanized steel, sheet, **0.0635** (galvanized table; 6.2% thicker than mild 16 gauge), 48 x 120 in, quantity 25.
- Ask: "Which coating weight (for example G60 or G90)?" (Coating designations are general knowledge; not sourced here.)

**T14. C, aluminum gauge and temper**
`14 ga 5052 alum 4x8 x10`
- Reading: aluminum 5052, sheet, 48 x 96, quantity 10, thickness **0.06408** (Metal Supermarkets) or **0.063** (Wikipedia). Spec likely B209.
- Ask: "Which temper (H32, H34, other)? Do you need 0.063 in or 0.064 in, or will either do?" The 1.7% gap between published tables is the reason to ask.

**T15. C, quantity vs dimension**
`3/16 304 plt 4x8 x4`
- Reading: stainless 304, buyer says plate, thickness **0.1875**, 48 x 96 in, and a trailing `x4` that could be quantity 4 or part of a size.
- Ask: "Is 4 the quantity? Hot-rolled plate or cold-rolled 2B sheet at 3/16?" 3/16 sits between the 1/4 in and 3 mm sheet/plate lines. Here the buyer said "plt", so form is plate; confirm finish.

**T16. C, contradiction between grade and strength**
`1/2 A36 PL 5x10 x3 min yield 50 ksi`
- Reading: carbon steel plate, thickness **0.500**, 60 x 120 in, quantity 3, grade A36. A36 guarantees 36 ksi minimum yield.
- Ask: "Do you need A572 Grade 50, or A36/A572-50 dual-certified plate?" Source: [AISC](https://www.aisc.org/globalassets/modern-steel/steel-interchange/2014/072014_si.pdf) via search. A hidden requirement: the stated strength implies a spec change.

**T17. C, ASME code material with a 3.1 cert**
`SA-240 316L 3/8 plt 60x120 x2 w/ 3.1 cert`
- Reading: stainless 316L, plate, thickness **0.375**, 60 x 120 in, quantity 2, ASME code material SA-240, EN 10204 3.1 certificate.
- Ask: "Must the cert show the SA-240 designation (not only A240), and the 316/316L dual cert? Do you need a code stamp or PMI?" Hidden requirements flagged: ASME SA ([Wermac](https://wermac.org/societies/ASME_SA_vs_ASTM_A.html)), 3.1 ([Material Welding](https://www.materialwelding.com/material-test-certificates-explained)).

**T18. C, pipe with PMI**
`2in sch40 304/304L A312 smls 20ft x30 PMI`
- Reading: stainless 304/304L dual, seamless pipe, nominal size 2 in, schedule 40, length 240 in, quantity 30 (lengths? feet?), spec A312. Wall thickness comes from the schedule table, which is not in my sources, so I do not state it.
- Ask: "Is 30 the number of 20 ft lengths, or total feet? Do you need the PMI report with the shipment, or only performed?" Hidden requirement stated: PMI.

**T19. C, contradiction between shape and spec**
`2x2 sq tube A53 Gr B .120 24ft`
- Reading: **cannot be read as written.** A53 is round pipe only ([Steel Tube Institute](https://steeltubeinstitute.org/resource/a500-versus-a53-different-inside/)); square tube is A500 or A513.
- Ask: "Do you need square tube (A500 structural or A513 mechanical), or round A53 pipe?"

**T20. C, DFARS stated**
`304 plate 1/4 48x96 A240 DFARS compliant melted USA 3.1 x3`
- Reading: stainless 304, plate, thickness **0.250**, 48 x 96 in, quantity 3, spec A240, EN 10204 3.1, domestic melt.
- Hidden requirements stated outright: DFARS 252.225-7009 ([acquisition.gov](https://www.acquisition.gov/dfars/252.225-7009-restriction-acquisition-certain-articles-containing-specialty-metals.)), melt origin on the MTR.
- Ask: "Is a qualifying-country melt acceptable, or US only?" (The clause allows the US, outlying areas, or a qualifying country.) And an internal check: does the stock on hand have a heat whose cert shows melt country?

**T21. C, DFARS implied by context**
Context: ship-to is a defense contractor; PO carries a "DO-A1" priority rating. Line: `304 rd bar 2in A276 12ft x10`
- Reading: stainless 304, round bar, 2.000 in diameter, length 144 in, quantity 10, spec A276.
- Hidden requirements implied: 304 is a specialty metal by chemistry (chromium well above 0.25%), a defense ship-to and rating suggest the DFARS clause flows down, and a DPAS rating carries an acceptance deadline.
- Ask: "Does the PO include DFARS 252.225-7009 or a melt-origin requirement?" This tests the context-trigger path with no keyword in the line.

**T22. C, Buy America with a coating step**
`L3x3x1/4 x 20' A36 galv x40 Buy America state DOT bridge`
- Reading: carbon steel angle, 3 x 3 x 0.250 in, length 240 in, quantity 40, A36, galvanized.
- Hidden requirement stated: Buy America. The rule covers the galvanizing step, and the MTR must show melt and manufacture location ([23 CFR 635.410](https://www.ecfr.gov/current/title-23/chapter-I/subchapter-G/part-635/subpart-D/section-635.410), [Caltrans](https://dot.ca.gov/-/media/dot-media/programs/construction/documents/contract-administration/buy-america/6104n081126a11y.pdf)).
- Ask: "Where is the galvanizing done, and does your agency require specific certification wording?"

**T23. C, sour service**
`1/2 A516-70 plate 72x120 NACE MR0175 HIC tested x2`
- Reading: carbon steel plate, thickness **0.500**, 72 x 120 in, quantity 2, spec A516 Grade 70 (pressure vessel plate; general knowledge, not sourced here), NACE MR0175, HIC tested.
- Hidden requirements: hardness limit (22 HRC max for carbon steel), heat-treat condition, HIC test results. The NACE standard does not itself require a certificate statement, so the buyer should say what the MTR must show.
- Ask: "Do you need hardness values and heat-treat condition on the MTR, and a separate HIC test report?"

**T24. C, export-controlled attachment**
Line: `6061-T651 plate 2 x 12 x 24 x4`, with an attached drawing marked "ITAR controlled technical data."
- Reading: aluminum 6061, temper T651, plate, thickness **2.000**, 12 x 24 in, quantity 4.
- Hidden requirement: the attachment is export-controlled data. Confidence is low (see section 3). Flag, do not interpret.
- Ask: "Please confirm handling rules (US persons only, domestic suppliers only) before we circulate the drawing."

**T25. C, a clear line with a gauge on tube (negative control)**
`1-1/2 sq tube A500 C 11ga 24ft x8`
- Reading: carbon steel, square tube, 1.5 x 1.5 in, wall **0.120** (tube wall table, 11 gauge), length 288 in, quantity 8, spec A500 Grade C. A500 tube ships with an MTR ([Atlas Tube](https://atlastube.com/?p=4627)), so the flag is informational.
- Ask: **none.** The right behavior is to read it, show the table used, and not ask.

---

## 7. Gaps and source quality

- **Paid or blocked sources:** ASTM, ANSI, SAE, and API documents were not readable. ASTM store pages and AISC PDFs returned 403 to my fetch tool. Spec claims rest on distributors, trade groups, forums, and search-result summaries of pages I could not open. Where a claim rests only on a search summary, the text says so.
- **Not verified in this session** (general industry knowledge, flagged in the lines that use them): A312 scope, A366 status and its modern equivalent, A516-70 as pressure vessel plate, G60/G90 coating designations, B221 scope, AMS specs, the exact A6 plate definition.
- **Not found:** a public dollar figure for a misread RFQ; a public statement on whether mill-form titanium or stainless is USML-controlled; a standards-body gauge chart (distributor and Wikipedia charts agree with each other).
- **One RFQ source for messy lines.** The Iowa document is a real, public RFQ from 2018 (line numbers 1 to 49), written by a state buyer and not by a plant engineer. It is cleaner than most email RFQs. Anything worse (PDF scans, abbreviations, mixed units) would come from the voice-of-user tracks.
- **Reddit:** not fetched, per instructions.

## Cleanup needed

None. Files I created in the research folder: `research_domain_rules.md` and `domain_rules_gauge_calc.py` (the script behind the percentages and conversions). A scratch copy of the script sits in the session scratchpad and needs no action.
