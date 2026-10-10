# Buyer Shorthand: How Buyers Write the Same Item

**Status:** Draft for Ken's review.

**Summary.** Buyers write one item many ways, and this file lists real strings from the team's research and RudCo's catalogs, grouped by kind, with what each means and whether buyer memory can hold it. Three of them make a clear learn-the-buyer beat: a bare "16 ga" that means stainless, an "SS304" code, and a "0.060 in" that means 16 gauge (see [Best for the demo](#best-for-the-demo)).

**Read with:** [DEMO_SCRIPT, beat 8 (learn the buyer)](DEMO_SCRIPT.md), [WORKFLOW, step 9 (save what was learned about this buyer)](WORKFLOW.md#9-learn-the-buyer), [the research test set](../research/20261010.01_rfq_sharper_angle/research_domain_rules.md#6-test-set).

**Checked:** 2026-10-10 at 14:28, against commit e2a65c1. The buyer-memory code was still changing that afternoon, so re-check a cell before you rely on it.

## How to read the table

- **Buyer wrote.** Text in backticks is copied from the source and was checked against the saved copy by script. A row marked **Illustration** is our own wording, built to show a point. It is not from a source.
- **Intake and Catalog** are the two readers. Intake is the RFQ processing rules (`tools/rfq_processing`, Yuval). Catalog is the catalog reader (`app/services/catalog_match`, Tisch). "Reads it" and "misses it" come from running both readers on the line at the commit above, outside Rails.
- **Could memory hold it?** uses three labels, defined in the next section: **Typed**, **Stored**, and **No field**.
- **Means.** Where the buyer's own long description sits next to a short code (the State of Iowa RFQs), the meaning comes from the buyer's words. Elsewhere the meaning comes from the research doc named in the Source column.

## What buyer memory can hold today

| Label | What it covers | Where it is in the code |
|---|---|---|
| **Typed** | The rep types it in the "Teach a buyer phrase" form on a quote line: material, grade, temper, form, finish, standard, quantity_unit | `ClientTerm::TEACHABLE_FIELDS` in [client_term.rb](../../app/models/client_term.rb); form in [_buyer_term.html.erb](../../app/views/quotes/_buyer_term.html.erb) |
| **Stored** | Memory and both readers accept it, but the form does not offer it: gauge, thickness (a number in inches), and a part number for a whole phrase | `ClientTerm::STORABLE_FIELDS`; `ClientMemory#teach!(fields:)` and `teach!(part_number:)` in [client_memory.rb](../../app/services/catalog_match/client_memory.rb). The form refuses numbers: "Price, quantity and gauge cannot be taught here." |
| **No field** | Nothing in memory holds it: size order and units, wall, schedule, process (hot rolled, seamless), quality (CQ), bags to pounds, paperwork (3.1, DFARS), "or similar" | Not in `ClientTerm` |

Four behaviors that matter for the demo:

- The form saves one field per phrase. Saving the same phrase again replaces the first meaning ([teach_buyer_term.rb](../../app/services/quote_workspace/teach_buyer_term.rb)).
- RFQ processing receives only phrases a rep taught. Phrases learned from approvals are held back until their source is recorded safely ([buyer_context.rb](../../app/services/quote_workspace/buyer_context.rb)).
- A taught meaning replaces the reading of the same words, and no others. This was added in commit 9d774c2, so a confirmed "0.060 in" can replace the generic reading of "0.060 in". I checked it with a stand-in term.
- Catalog already words the source as `Northline (taught by the rep, confirmed on RFQ-0001): "16 ga" means material stainless steel`. Intake words it as "taught by the rep" without the RFQ number.

## Examples

### 1. Gauge and decimal thickness

| # | Buyer wrote | Means | Source | Could memory hold it? |
|---|---|---|---|---|
| 1.1 | `48" x 120" long x 16 Gauge` under `Stainless Steel Sheets Type 304-2B` | 304 stainless, 2B finish, 16 gauge on the stainless table: 0.0625 in. | [State of Iowa RFQ 245, 2018, line 20][iowa18]; [test line T1][dr-t] | Nothing to teach: intake reads 0.0625. A confirmed decimal would be **Stored** (thickness). |
| 1.2 | `0.063 (16 Ga.)` next to `1/16 in` | One sheet written three ways, all 0.0625 in. The 0.063 rounds it by 0.8%. A seller's listing, not a buyer. | [University of Alberta listing][ualberta]; [domain rules, T9][dr-t] | **Stored** (thickness). |
| 1.3 | `10ga (0.135") 304 Stainless Steel Sheet` | The seller prints 0.135 in. The stainless table gives 0.14062 in for 10 gauge, so the decimal is 4.0% low and close to mild steel (0.1345). A seller's listing. | Speedy Metals, quoted in [domain rules 1.1][dr-11] | **Stored** (thickness), after the buyer says which number governs. |
| 1.4 | `304 SS sheet 16ga 4x8` and `Stainless 304, 0.060 in, 48 x 96` | The challenge calls them the same item. 16 gauge stainless is 0.0625 in, which is 4.2% thicker than 0.060 in. 0.060 in matches 16 gauge mild steel (0.0598). | Devpost challenge text, in [report 6.5][report-65]; [T10 and T11][dr-t] | Intake reads the first at 0.0625 and flags the second ("decimal near gauge"). The buyer's answer is **Stored** (thickness). |
| 1.5 | `Aluminum Plate, 5052-32 - .063 x 4' x 8' or similar`, `STAINLESS Steel 2B T-304 - 16 Gage x 4 x 8 or similar`, `(40 Each) Steel Plate (Low Carbon), A1011- 11 Gage x 4' x 8' or similar` | One RFQ gives the aluminum thickness as a decimal and the steels as "Gage". Each gauge number needs its own metal's table. | [USAF RFQ FA302024Q0014][ow-a] | **Stored** (gauge, thickness). |
| 1.6 | `Stainless Tubing 1 x 1 x .05` over `Stainless Steel Tubing Type 304, 1" x 1" x .065 wall thickness x 20' Long` | The short name says .05 and the long one says .065 wall. They disagree, so the rep asks. | [Iowa 2021, line 6][iowa21]; [open web, C][ow-c] | **No field** for wall thickness. |
| 1.7 | `301 stainless steel, 26 gauge, brushed finish. 10 units for prototyping, then 100.` | 301 stainless, 26 gauge, brushed finish, two quantities. A commenter equates 26 gauge with .018 in. Our gauge table stops before 26. | [r/sheetmetal, Dec 2024][r-1hcriy2]; [Reddit track, claim 2.1][rd-rq2] | Intake asks ("gauge not in table"). **Stored** (thickness) would hold the buyer's decimal. |
| 1.8 | **Illustration:** `16 ga sheet 4x8 qty 20` | Gauge with no metal. Four tables apply (0.0598, 0.0625, 0.0635, 0.05082), so the line cannot be read. | [Research test line T12][dr-t] (constructed there too); line 7 of the [draft demo email](../../tools/rfq_processing/spec/fixtures/demo_rfq_email.txt) | **Typed** (material). Teach "stainless steel" and intake reads 0.0625 (checked). |
| 1.9 | `Stainless Steel Sheets Type 304-2B, 60" x 120" x 14 Gauge` | 304 stainless, 2B finish, 14 gauge on the stainless table: 0.07812 in. The heading above this line reads `Steel, Mild: Bars, Plates, Rods, Sheets, Strips, Tubes, etc.`, so the heading and the line name different metals. | [Iowa 2021, line 14, PDF page 3][iowa21p] | Nothing to teach for the line: both read stainless, 304, 2B and 14 gauge (checked). I ran the line alone, so the heading is not checked. |
| 1.10 | `Flattened Mild Expanded Metal, 3/4", 13 Gauge, 48" x 120"` and `Stainless Steel Flattened Expanded, 3/4", 13 Gauge, 48" x 96"` | Expanded metal ordered by gauge. The sheet gauge tables have no row for it, and the line does not say what the 3/4" is (probably the diamond size; my reading, not stated). | [Iowa 2021, line 15 and 16, PDF page 3][iowa21p] | Intake reads the 3/4 in as thickness and also says 13 gauge is not in the sheet tables. Catalog reads gauge 13 and the size, and leaves "expanded" unread (checked). **Stored** (gauge, thickness) once the buyer answers. **No field** for the 3/4". |

### 2. Grade names

| # | Buyer wrote | Means | Source | Could memory hold it? |
|---|---|---|---|---|
| 2.1 | `Stainless Steel Sheets Type 304-2B` | Grade 304 and finish 2B in one string. | [Iowa 2018, line 20][iowa18] | Nothing to teach: both read grade 304 and finish 2B. |
| 2.2 | `STAINLESS Steel 2B T-304 - 16 Gage x 4 x 8 or similar` | "T-304" is grade 304. The finish comes first. | [USAF RFQ][ow-a] | Nothing to teach for the grade: both read 304 and 2B. The size is a separate problem (see the no-units row in section 3). |
| 2.3 | `316ss sch80 pipe` and `304ss sch40` | "ss" glued after the grade: 316 stainless and 304 stainless. One story: the spec said 316, 304 was bought, and "a $250k job" cost about $450k. | [r/metalworking, Aug 2026][r-vtls-w0ody]; [Reddit track, claim 3.1][rd-rq3] | Both miss the metal (checked). **Typed** (material). The form keeps one field per phrase, so the grade stays unread. |
| 2.4 | `304SS`, `SS303`, `SS316 plates` | The "ss" before or after the grade, from three different posters. "304 SS" with a space is already read (checked). | [r/Machinists, May 2025][r-1ks1tt8]; [r/CNC, Jun 2022][r-v57bt9]; [r/MechanicalEngineering, Feb 2025][r-1iz6o3v]. All three come from saved search pages and are not quoted in the Reddit track. | Both miss all three (checked). **Typed** (material). |
| 2.5 | `8-32 x3/8 flat head socket caps in 18-8ss` | "18-8" is an older name for 300-series stainless. What the digits stand for is general knowledge, not in the research. The research does not say which grade this buyer means. | [r/Machinists, Jul 2024][r-1e5ga3t] | Both miss it, and intake reads the line as a flat bar (checked). **Typed** (material). |
| 2.6 | `ASTM A-572 G50 1.25" x 96" x 144" 3 EA` | "G50" is Grade 50 of A572 plate. RudCo also sells steel grit sized G-50, which gives the catalog reader a wrong match. | [USACE RFQ][ow-b]; grit size in [RudCo catalog](../../data/rudco/catalog.json) (`RC-STEELGRIT-G50`) | Intake reads standard A572 and plate. Catalog reads steel grit G-50 (checked). **Typed** (grade, standard): a taught phrase replaces the grit reading (checked). |
| 2.7 | `Hot Rolled Strips CQ-A36`, `Cold Rolled Sheets QC/ A366`, `Hot Rolled Sheets CQ/A569, 48" x 96" x 10 Gauge` | A sheet quality term (CQ, commercial quality) fused to a spec or a structural grade. "QC" is probably CQ reversed. The research thinks A366 and A569 are older specs, from recall, not verified. | [Iowa 2018, lines 6 and 9][iowa18]; [Iowa 2021, line 13][iowa21]; [open web, C][ow-c] | Intake reads A36 and commercial quality, then raises a spec conflict. Catalog leaves "CQ" and "QC" unread. **Typed** (standard). **No field** for quality. |
| 2.8 | `ASTM A36 or A572 Gr. 50 equivalent hot-rolled carbon steel` | The buyer accepts either. One plate certified to both fits. RudCo's sample metals catalog names that plate `A36/A572-50` (a constructed sample, not RudCo's stock list). | [SacRT solicitation, in domain rules T8][dr-t]; [metals catalog](../../data/metals/catalog.json) | Intake reads "A36 or A572 Grade 50". Catalog keeps only A572-50. **Typed** (grade). |
| 2.9 | `Square Tube A513-A500 Grade B`, `SquareTubing A513/A500 Grade B, 1 x 1" x .065 wall thickness x 24' Long`, `hot rolled welded a500/a513` | Two spec families on one line. A500 is structural tube that ships with a mill test report; A513 is mechanical tube. These are different products. | [Iowa 2018, line 1][iowa18]; [Iowa 2021, line 8][iowa21]; [r/metalworking, Mar 2024][r-1b6wixv]; [domain rules 2][dr-2] | Both raise the conflict (checked). **Typed** (standard), only after the buyer says which one they mean. |
| 2.10 | `Aluminum Flat 6061-T6` and `Aluminum Plate, 5052-32 - .063 x 4' x 8' or similar` | The temper rides with the alloy. The research says a buyer who writes 6061-T6 plate often means T651; ask. A bare "-32" is probably H32 (my reading, no source). | [Iowa 2018, line 23][iowa18]; [USAF RFQ][ow-a]; [domain rules 1.3][dr-13] | Both read 6061 and T6. For 5052, intake flags the missing temper (checked). **Typed** (temper). |
| 2.11 | `ULTEM 1000`, `ePlastics natural ULEM 1000`, `McMaster prices for 5ft of Ultem PEI is like $24.75/bar` | Three names for what looks like one plastic. Off RudCo's range, kept because the naming problem is the same. | [r/Machinists, Apr 2026][r-1sr80m1]; [Reddit track, claim 2.1][rd-rq2] | Neither reader knows the plastic (checked). **Typed** (material). |
| 2.12 | `Cold Rolled Sheets CQ/A366, 48" x 96" x 18 Gauge` | Cold rolled carbon steel sheet, commercial quality, spec A366, 18 gauge (0.0478 in on intake's table). Same fusing of a quality term and a spec as row 2.7. Intake's rules call A366 an older spec. | [Iowa 2021, line 12, PDF page 3][iowa21p] | Intake reads A366, cold rolled, commercial quality and 18 gauge, then raises an "obsolete spec" conflict. Catalog reads A366 and 18 gauge and leaves "CQ" unread (checked). **Typed** (standard). **No field** for quality. |
| 2.13 | `The ability of the bidder to supply the grinding stones as per purchase order text.` | Scoring text in a steel shot tender that asks for grinding stones. The item is steel shot. [SOURCE.md](../example_rfqs/transnet-steel-shot-2024/SOURCE.md) flags this as a mismatch to ask the buyer about. | [Transnet, PDF page 10][tn-txt] (also page 34) | Not checked: it is evaluation text, not an item line. **No field**. It is a question for the buyer, not a meaning to store. |

### 3. Dimension order and units

The State of Iowa RFQs are the best real evidence of one buyer's habit. Each line has a short code and the buyer's own long description under it, so the meaning is in the buyer's words. No field holds any of these habits.

| # | Buyer wrote | Means | Source | Could memory hold it? |
|---|---|---|---|---|
| 3.1 | `Stainless Sheets 4 x 10` over `48" x 120" long x 16 Gauge`; `Cold Rolled Sheets 4 x 10` over `48" x 120" x 14 Gauge` | In the short name, "4 x 10" is feet. The long form gives inches. | [Iowa 2018, lines 20 and 9][iowa18]; [domain rules 1.2][dr-12] | Nothing to teach: both read "4 x 10" as 48 x 120 (checked). |
| 3.2 | `Strips 3 x 20 x 1/8"` over `3" x 20' long x 1/8" thick` | 3 in wide, 20 **feet** long, 1/8 in thick. | [Iowa 2018, line 6][iowa18]; [domain rules 1.2][dr-12] | Intake reads the length as 20 in (checked, wrong). **No field.** |
| 3.3 | `Stainless Flat 2 x 1/8` over `2" x 12' long x 1/8" thick`; `Square Tube 2 x 2 x.188` over `2" x 2" x 24' long x .188 thick` | The short names leave out the stock length. It appears only in the long form. | [Iowa 2018, lines 16 and 1][iowa18] | Catalog reads the flat as width 0.125 and length 2 (checked, wrong). **No field.** |
| 3.4 | `Structural Channel 4 x 1.584 x 40 x .184` over `4" deep x 1.584 wide x .184 thick x 40' long` | The long form reorders the numbers: length is third in the short name and last in the long one. | [Iowa 2018, line 4][iowa18] | Intake reads only the form. Catalog reads wrong numbers (checked). **No field.** |
| 3.5 | `RectangleTubes 2 x 1.5 x 24 x .120` (2018) and `Tubing 3 x 2 x .120` (2021) | The same issuer writes tubes two ways. The 2018 short name includes the length (24 is feet). The 2021 one drops it. A learned order would be per buyer and per edition. | [Iowa 2018, line 5][iowa18]; [Iowa 2021, line 5][iowa21] | Intake reads length 24 in. Catalog reads "3 x 2" as feet (checked, both wrong). **No field.** |
| 3.6 | `STAINLESS Steel 2B T-304 - 16 Gage x 4 x 8 or similar` | "4 x 8" has no unit, while the same RFQ writes `A36 3/8" x 4' x 8'` with feet marks. Feet are implied: 48 x 96 in. | [USAF RFQ][ow-a] | Catalog reads 48 x 96. Intake reads quantity 4 and drops the size (checked). **No field.** |
| 3.7 | `ASTM A-36 Angle 0.75" x 8" x 6" x 20' 4 EA` | Four numbers for an angle. Which leg is which is not written. | [USACE RFQ][ow-b] | Catalog reads thickness 6 in (wrong). Intake leaves thickness unread (checked). **No field.** |
| 3.8 | `ASTM A-36 W12 x 79 Beam 20' 3 EA` | A wide-flange beam, 12 in deep and 79 lb per foot. That meaning is general knowledge, not in the research. | [USACE RFQ][ow-b] | Intake reads a length of 79 in (checked, wrong). **No field.** |
| 3.9 | `1 x 1" x .065 wall thickness x 24' Long` and `43x67" 1/2" thick plate HRPO` | The inch mark sits on one number only. The second line has no spaces around the "x". | [Iowa 2021, line 8][iowa21]; [r/metalworking, Nov 2025][r-1onuh36] | Catalog reads the first right; intake reads width 1 and length 1 (checked). **No field.** |
| 3.10 | `steel sqare pipe witz 5mm thickness` | Square tube, 5 mm wall, written by a non-native English speaker. The story then swaps in 4 mm. | [r/metalworking, Aug 2026][r-vtls-u8wte]; [Reddit track, claim 2.1][rd-rq2] | Neither reader reads the 5 mm (checked). **No field** for wall. |
| 3.11 | `I need 3:16 7075 round` | Unclear. Possibly 3-1/16 in diameter round bar; the source does not say. | [r/Machinists, Aug 2023][r-15kudev-fe8f] | Catalog reads quantity 3 and diameter 16 (checked, wrong). **No field.** |
| 3.12 | **Illustration:** `1/2 A36 PL 5x10 x3 min yield 50 ksi` | "5x10" is feet (60 x 120 in). "x3" is the quantity. The 50 ksi asks for more than A36 gives. | [Research test line T16][dr-t] (constructed there too); line 4 of the [draft demo email](../../tools/rfq_processing/spec/fixtures/demo_rfq_email.txt) | Both read the size and quantity (checked). **No field.** |
| 3.13 | `Stainless Angle 1 1/2 x 1 1/2 x 1/8` over `Stainless Steel Angle Type 304, 1 1/2" x 1 1/2" x 1/8" x 20' Long` | Mixed-number legs and a 1/8 in thickness. The 20 ft length appears only in the long line, the same habit as row 3.3. | [Iowa 2021, line 4, PDF page 2][iowa21p] | Nothing to teach: both read the legs and thickness from either line. The short line leaves length open, and the long line gives 240 in (checked). |
| 3.14 | `Tubing 1 1/2 x 1 x .083` over `Rectangular Tubing A513/A500 Grade B, 1 1/2" x 1" x .083 wall thickness x 24' Long` | A 1 1/2 in by 1 in rectangle with a .083 wall; the long line adds 24 ft. The short name is the one that gets misread. | [Iowa 2021, line 11, PDF page 3][iowa21p] | Intake reads the trailing "x 1" as quantity 1. Catalog reads "1 1/2 x 1" as feet, width 12 and length 18. Both wrong on the short name (checked). Catalog also reads the long line as a square tube of width 1. **No field.** |
| 3.15 | `Rectangular Tubing A513/A500 Grade B, 3" x 2" x .120 wall thickness x 24' Long` | 3 in by 2 in, .120 wall, 24 ft. | [Iowa 2021, line 5, PDF page 2][iowa21p] | Intake reads a rectangular tube, 3 by 2. Catalog reads a square tube of width 2 and drops the 3 (checked, wrong). **No field.** |
| 3.16 | `Cold Rolled Squares, Mild Steel 3/4 x 12' Lengths` and `Stainless Steel Squares, Type 304, 3/4 x 12' Lengths` | "Squares" with no product form named. Probably solid square bar, 3/4 in on a side, in 12 ft lengths (my reading; the lines do not say bar). | [Iowa 2021, line 17 and 18, PDF page 3 and 4][iowa21p] | Intake reads 0.75 in and 144 in, and asks for the product form. Catalog reads 0.75 as a thickness and leaves "squares" unread (checked). **Typed** (form) could say bar. |

### 4. Quantity units

| # | Buyer wrote | Means | Source | Could memory hold it? |
|---|---|---|---|---|
| 4.1 | `(80 Each) Steel Plate (Low Carbon), A36 3/8" x 4' x 8' or similar` | The quantity comes first, in brackets, with "Each". | [USAF RFQ][ow-a] | Nothing to teach: both read 80 each. |
| 4.2 | `ASTM A-36 0.75" x 8" x 20' 10 EA` and `ASTM A-572 G50 1.25" x 96" x 144" 3 EA` | The quantity comes last, with "EA". | [USACE RFQ][ow-b] | Nothing to teach: both read the quantity and unit (checked). |
| 4.3 | `100pcs of 14' stock` | 100 pieces, each a 14 ft length of stock. The unit says "pcs" but the piece is a stock length. | [r/metalworking, May 2018][r-8jmd8p]. Saved search page, not quoted in the Reddit track. | Both read 100 pieces and a 14 ft length (checked). **Typed** (quantity_unit) could say "length". |
| 4.4 | `$263 a 4x8 sheet. 4 sheets would be over $1000.` | "4x8" is a size and "4 sheets" is a count, in the same sentence. | [r/sheetmetal, Jul 2023][r-1521np9]. Saved search page, not quoted in the Reddit track. | Nothing to teach: both read "4 sheets" as a count of sheets (checked). |
| 4.5 | `50 lb bags`, `2,000 lb bulk bags`, `Palletized skids`, `Pallet of T-bar (~2,000 lb)`, `Truckload (44,000 lb)` | RudCo's own pack names. It prices abrasives and ingot by the pound. "40 bags" is 2,000 lb only if the bag is 50 lb. These are RudCo's words, not a buyer's. | `packaging` fields in the [RudCo catalog](../../data/rudco/catalog.json) | Both read "40 bags" as a unit of bags (checked). **Typed** (quantity_unit) names the unit. **No field** turns bags into pounds. |
| 4.6 | **Illustration:** `3/16 304 plt 4x8 x4` | The trailing "x4" could be the quantity or part of the size. | [Research test line T15][dr-t] (constructed there too) | Intake reads quantity 4 and flags sheet versus plate. The quantity itself is **No field**. |
| 4.7 | `CONTAINER SIZE: 1000 KG PER BOX`, with quantity `50 000` and unit `KG` in the price schedule | The pack size is in kilograms per box, and the order is in kilograms. [SOURCE.md](../example_rfqs/transnet-steel-shot-2024/SOURCE.md) works out 50 boxes. | [Transnet, PDF page 6][tn-txt] (item row) and [PDF page 17][tn-pdf] (price schedule) | Intake reads the container size as the quantity: 1000 kg (checked, wrong). Catalog leaves "container", "kg" and "box" unread. **Typed** (quantity_unit) names kg. **No field** turns boxes into kg. |
| 4.8 | `10.00000 EA 57064` | Quantity with five decimals, the unit EA, then a state commodity code. In the PDF these sit in three columns on the line above the description, so I ran them joined as one string, which is not how the app would see them. | [Iowa 2021, line 3, PDF page 2][iowa21p] | Intake reads no quantity. Catalog reads quantity 0 each (checked as one string, wrong). **Typed** (quantity_unit). **No field** for the commodity code. |

### 5. Abbreviations

| # | Buyer wrote | Means | Source | Could memory hold it? |
|---|---|---|---|---|
| 5.1 | `43x67" 1/2" thick plate HRPO` and `As far as I know, HRPO is just acid-dipped hot rolled A36` | The poster treats HRPO and A36 as two products, with quotes of $685.77 and $417.24. The only expansion in the research is one commenter's: acid-dipped hot rolled A36. | [r/metalworking, Nov 2025][r-1onuh36] and [comment][r-1onuh36-c]; [Reddit track, claim 2.1][rd-rq2] | Both miss the metal (checked). **Typed** (material, grade, finish). The rep decides the meaning. |
| 5.2 | `HR Angle 1 x 1 x 1/8` over `Stainless Steel Angle Type 304, 1" x 1" x 1/8" x 20' Long` | "HR" in the short name against a stainless description. | [Iowa 2021, line 2][iowa21]; [open web, C][ow-c] | Catalog reads "HR" as carbon steel (checked), which contradicts the long line. Do not teach; ask. |
| 5.3 | `(100 Each) HR Galvanized Sheet 26 Gage x 4' x 10' or similar` | HR means hot rolled (general knowledge). The notice uses it as a bare code. | [USAF RFQ][ow-a] | Intake reads process "hot rolled" (checked). **No field** for process. |
| 5.4 | `I ordered $80,000 worth of 7" XS seamless pipe to make 700 caps.` | "XS" is not defined in the thread. In general use it means extra-strong wall. That meaning is outside the source. | [r/metalworking, Aug 2026][r-vtls-50xm4u]; [Reddit track, claim 2.1][rd-rq2] | Neither reader reads XS (checked). **No field** for wall or schedule. |
| 5.5 | `cold rolled 1026 DOM tubes` and `I'd settle for DOM instead of CDS, as well` | DOM and CDS are tube-making codes. Neither thread defines them. | [r/metalworking, Mar 2024][r-1b6wixv]; [r/metalworking, May 2018][r-8jmd8p]. Saved search pages, not quoted in the Reddit track. | Catalog reads 1026 as a size (checked, wrong). **No field** for process. |
| 5.6 | `Domestic is doable, just having the CMTR state DFARS compliant is the hard part.` and `Looking for a supplier for DFARS Compliant 60 series aluminum. Also has to be made in the USA` | CMTR is a certified mill test report. "DFARS compliant" and "made in the USA" are two asks used as one. | [r/Machinists, Aug 2023][r-15kudev]; [Reddit track, claim 4.2][rd-rq4]; [domain rules 3.2][dr-32] | **No field.** This is a paperwork flag, not a meaning. |
| 5.7 | `(20 Each) Aluminum Plate, 5052-32 - .063 x 4' x 8' or similar` | "or similar" invites a substitute. The rep writes the substitute on the quote as an assumption. | [USAF RFQ][ow-a] | **No field.** |
| 5.8 | `Material Safety Data Sheet (MSDS)` and `Technical Data Sheet (TDS) – Chemical Composition` | Two documents the bidder must send, scored 30 points. They are paperwork, not products. | [Transnet, PDF page 10][tn-txt] (also page 19) | Both readers read "Data Sheet" as the product form "sheet" (checked, wrong). The compliance rules have no entry for MSDS or TDS. **No field**. This is a paperwork flag. |

No source in the research uses "CRS", "HRS" or "CRCA". The intake lexicon has CRS and HRS, but no saved source does, so they are not listed above.

### 6. Abrasive sizes (RudCo's own words)

| # | Buyer wrote | Means | Source | Could memory hold it? |
|---|---|---|---|---|
| 6.1 | `S-330`, `S330`, `steel shot S-330` | RudCo's three spellings of one size: 0.033 in (0.84 mm). | `rfq_aliases` of `RC-STEELSHOT-S330` in the [RudCo catalog](../../data/rudco/catalog.json) | Catalog reads S-330 and S330 alone. Intake needs the words "steel shot" for the metal (checked). **Typed** (grade). |
| 6.2 | `S-330 (304)`, `S330 (304)`, `stainless steel shot S-330 (304)` | The grade of the stainless is in brackets after the size. | `RC-STAINLESSSTEELSHOT-S330304` in the [RudCo catalog](../../data/rudco/catalog.json) | Intake reads "steel shot" and drops "stainless" (checked, wrong). Catalog reads stainless steel shot. **Typed** (material, grade). |
| 6.3 | `60 grit` (aluminum oxide), `80 mesh` (garnet), `G-40` (steel grit), `20/40 mesh`, `+8 mesh` (corn cob) | Four size words for blast media: grit, mesh, a G- number and a mesh range. The catalog gives each a mesh size, such as US Mesh 60. | `grade` and `size` fields in the [RudCo catalog](../../data/rudco/catalog.json) | Catalog reads grit and mesh as the grade. Intake leaves the grade unread for "60 grit" (checked). **Typed** (grade). |
| 6.4 | `A (Potters)` and `#4` | Two names for the same range, US Mesh 6 to 10, on RudCo's glass bead list. They are separate part numbers. | `RC-GLASSBEADS-APOTTERS` and `RC-GLASSBEADS-4` in the [RudCo catalog](../../data/rudco/catalog.json) | Both readers read "glass bead #4" as the **finish** No. 4 (checked, wrong for beads). **Typed** (grade). |
| 6.5 | **Illustration:** `330 shot 40 bags` | A buyer's own words for S-330 steel shot. No source shows a buyer writing this. | Built from row 6.1 | Both readers miss the size and the metal (checked). **Typed** (material or grade). One field per phrase leaves the other open. |
| 6.6 | `STEEL SHOT; TYPE: S 390, MATERIAL: CAST STEEL, MATERIAL GRADE: HRC 40-50, APPLICATION: ABRASIVE SANDING, SHOT LOAD SIZE DESIGNATOR:1.2 MM; CONTAINER SIZE: 1000 KG PER BOX` | RudCo sells S-390 steel shot (`RC-STEELSHOT-S390`, 0.039 in or 0.99 mm). Here the size designator says 1.2 MM, which is not 0.99 mm, and a hardness range (HRC 40-50) sits in the "MATERIAL GRADE" field. SOURCE.md says to keep the buyer's size and not substitute. | [Transnet, PDF page 6][tn-txt] (lines 222 to 224, item 006828999); [RudCo catalog](../../data/rudco/catalog.json) | Intake reads steel shot and S-390, then reads the container size as quantity 1000 kg and drops HRC and 1.2 mm. Catalog reads steel shot and S-390, then reads "40-50" as a thread and 1.2 as a thickness (checked, wrong). **Typed** (grade) for S 390. **No field** for hardness, size designator or container. |
| 6.7 | `SUPPLY AND DELIVER OF STEEL SHOT; S 390, CS, HRC 40-50, 1.2MM – 50 000KG` | The tender title squeezes the item into one line. "CS" is cast steel, going by the item row (`CAST STEEL`). `50 000KG` is 50,000 kg, with a space inside the number and the unit glued to it. | [Transnet, PDF page 1][tn-txt] (line 7) | Intake reads steel shot, S-390 and quantity 0 kg. Catalog reads steel shot and S-390, "40-50" as a thread and a thickness of 1.0, and leaves "cs", "hrc" and "000kg" unread (checked, wrong). **No field** for a number with a space inside. |

About the standard name: Ken's note says "SAE J444". The intake parser and the [competitive analysis](../research/20261010.03_rudco_competitive_analysis/competitive_analysis.md) say J444. RudCo's catalog (`SAE J827 / AMS-S-13165`) and the catalog reader's comment say J827. I found no independent source for either. Settle which one before the demo says a standard number out loud.

### 7. Part numbers

| # | Buyer wrote | Means | Source | Could memory hold it? |
|---|---|---|---|---|
| 7.1 | `8-32 x3/8 flat head socket caps in 18-8ss` with two links, `https://www.mcmaster.com/94518A310` and `https://www.mcmaster.com/92210A192` | The buyer names the item by another supplier's catalog number, pasted as a link. | [r/Machinists, Jul 2024][r-1e5ga3t] | **Stored** (part number for the whole phrase), once a RudCo item matches. |
| 7.2 | `PL3848 ST Plate 3/8 X 4' X8' A36` | A code that may hold plate, 3/8 in, 48 in (my guess). Seen only in a search summary; the notice was never opened. Low confidence. | [open web, E][ow-e] | Catalog reads the line but not "PL3848" (checked). **Stored** (part number) if a rep confirms it. |
| 7.3 | `3044-16gx48x96` | A retailer's web address ends with grade, gauge and size run together. The research does not decode the extra "4". Read from the web address only. | [Zoro listing, in open web E][ow-e] | **Stored** (part number for the phrase). |
| 7.4 | **Illustration:** `AN3-13A`, `an3 dash 13a`, `AN315-3L`, `MS35206-245` | Spellings of aviation part numbers the catalog reader is written to handle. `AN3-13A` is a real row in Tisch's aviation list. | Comment in [description_reader.rb](../../app/services/catalog_match/description_reader.rb); [AVIATION_ITEMS_200](../data/AVIATION_ITEMS_200.md) | Intake reads `AN3-13A` but not "an3 dash 13a" (checked). **Stored** (part number). |
| 7.5 | `006828999` | Transnet Engineering's own item number for the steel shot, written before the description in the item row and the price schedule. It is the buyer's number, not RudCo's. | [Transnet, PDF page 6][tn-txt] and [PDF page 17][tn-pdf] | Neither reader returns a part number for it (checked on the full item row). **Stored** (part number for the whole phrase), once a rep confirms the RudCo item. |

### 8. Finish codes

| # | Buyer wrote | Means | Source | Could memory hold it? |
|---|---|---|---|---|
| 8.1 | `Stainless Steel Sheets Type 304-2B`, `STAINLESS Steel 2B T-304`, `2B Mill Finish` | 2B written three ways. | [Iowa 2018, line 20][iowa18]; [USAF RFQ][ow-a]; [University of Alberta listing][ualberta] | Nothing to teach: both read 2B. |
| 8.2 | `#2 Finish` | A vendor label for sheets its own text calls 2B. | Speedy Metals, quoted in [domain rules 1.4][dr-14] | Intake reads "No. 2" and notes it may mean 2B. Catalog misses it (checked). **Typed** (finish), once the buyer says so. |
| 8.3 | `brushed finish` | The research says No. 4 is a brushed finish that varies between suppliers. | [Reddit track, claim 2.1][rd-rq2]; [domain rules 1.4][dr-14] | Catalog reads "brushed" as #4. Intake leaves it unread (checked). **Typed** (finish). |
| 8.4 | `2B`, `#4`, `HRAP #1`, `mill` | The finish words in RudCo's sample metals catalog. This is the vocabulary a taught finish has to land on. A constructed sample, not RudCo's stock list. | `finish` field in the [metals catalog](../../data/metals/catalog.json) | **Typed** (finish). |
| 8.5 | **Illustration:** `KB` | A buyer's two-letter code for a finish. The code comments use it as the standing example: "KB" can mean a #4 finish for one company and 316L for another. | Comment in [client_memory.rb](../../app/services/catalog_match/client_memory.rb); [buyer_profile_spec.rb](../../tools/rfq_processing/spec/rfq_processing/buyer_profile_spec.rb) | Both treat "KB" as an unknown word (checked). **Typed** (finish). |

## Best for the demo

**Answer first.** Use the bare "16 ga" example now, because it matches the script's gauge story and the teach form accepts it as it is. Add the "0.060 in" example if the form gets a thickness field before recording. Keep "SS304" as a second example when the demo needs a code that works on a different gauge.

All three use the draft demo buyer, Northline Fabrication, from the [draft demo email](../../tools/rfq_processing/spec/fixtures/demo_rfq_email.txt). The "line shows" wording is what the code printed when I ran it with a stand-in taught phrase.

### Pick 1: a bare "16 ga" means stainless (row 1.8)

- **Teach with today's form:** phrase `16 ga`, field material, value stainless steel.
- **RFQ-0001 line:** `16 ga sheet 4x8 qty 20`, line 7 of the draft email. No metal is named, so four gauge tables apply and the line is held.
- **RFQ-0002 line (illustration):** `16 ga sheet 4x10 qty 6`. Spell it "16 ga" again. Intake needs the space, so "16ga" would not fire (checked). Catalog accepts both.
- **Line shows:** `Northline (taught by the rep, confirmed on RFQ-0001): "16 ga" means material stainless steel`. Intake then reads `16 gauge on the stainless steel table is 0.0625 in`.
- **Caveat:** the research never shows a buyer who leaves the metal out twice. The repeat is our illustration.

### Pick 2: "SS304" is the buyer's code for stainless (row 2.4)

- **Teach with today's form:** phrase `SS304`, field material, value stainless steel. The grade stays open, because the form saves one field per phrase.
- **RFQ-0001 line (illustration):** `SS304 16ga 4x8, 20 sheets`. Both readers miss the metal, and intake holds the line ("material missing with gauge").
- **RFQ-0002 line (illustration):** `SS304 14ga 4x8, 6 sheets`.
- **Line shows:** stainless steel, and 14 gauge on the stainless table is 0.07812 in. The phrase worked on a different gauge, so the audience sees a code and not a one-off.
- **Real strings in this style:** `304SS`, `SS303`, `SS316 plates`, `316ss sch80 pipe` and `18-8ss`. They come from different posters, so they show variety across buyers, not one buyer's habit.
- **Caveat:** 304 versus 316 is still unread, so the catalog match may ask about the grade.

### Pick 3: "0.060 in" means 16 gauge (row 1.4)

- **Teach with:** thickness 0.0625, phrase `0.060 in`. Memory and both readers accept it, but today's form does not offer thickness. Someone has to add it to the form or the buyer-answer path.
- **RFQ-0001 line:** `Stainless 304, 0.060 in, 48 x 96, 10 sheets`, line 6 of the draft email and the challenge's own wording. The question email asks "16 gauge or 0.060 in?" and the buyer's answer is the confirmation.
- **RFQ-0002 line (illustration):** `Stainless 304, 0.060 in, 48 x 120, 6 sheets`.
- **Line shows:** `Northline (taught by the rep, confirmed on RFQ-0001): "0.060 in" means thickness 0.0625`. That is close to your wording, "Read as 0.0625 in, as you confirmed on RFQ-0001."
- **Caveat:** the research shows sellers printing a gauge and a decimal that disagree (rows 1.2 and 1.3). It does not show this buyer repeating 0.060. Teach it only after the buyer has confirmed, as the question email does.

**Runner-up:** "HRPO" (row 5.1) is the best-sourced fight over an abbreviation. The only expansion in the research is one commenter's, and RudCo does not list the product, so it makes a weaker beat.

## Cautions

- **The research ranks this angle last.** The Reddit track found names that vary across people but no poster who describes one buyer writing the same shorthand repeatedly. The closest real case is the State of Iowa RFQs in section 3, and no field holds dimension order.
- **Two readers disagree.** Some lines read right in one and wrong in the other (rows 2.6, 3.3, 3.6, 3.7, 6.2). The demo email should pass through both before recording.
- **Misreads I found while checking** (not a full list), for Yuval and Tisch:
  - Intake: `Strips 3 x 20 x 1/8"` reads length 20 in, not 20 ft.
  - Intake: `STAINLESS Steel 2B T-304 - 16 Gage x 4 x 8 or similar` reads quantity 4 and loses the size.
  - Intake: `stainless steel shot S-330 (304)` reads plain steel shot.
  - Catalog: `ASTM A-572 G50 ...` reads steel grit G-50 (row 2.6).
  - Both: `glass bead #4` reads finish No. 4 (row 6.4).
  - Catalog: `Tubing 3 x 2 x .120` reads "3 x 2" as feet.
- **Sources I could not close.** The meanings of "18-8" digits, "W12 x 79", "XS", "DOM", "CDS" and "PL3848" are general knowledge or a guess. The research does not define them.
- **This file changes no code.**

## Sources checked

- Research: [domain rules](../research/20261010.01_rfq_sharper_angle/research_domain_rules.md), [Reddit voice](../research/20261010.01_rfq_sharper_angle/research_voice_reddit.md), [open web voice](../research/20261010.01_rfq_sharper_angle/research_voice_open_web.md), [other sources voice](../research/20261010.01_rfq_sharper_angle/research_voice_other_sources.md), [report](../research/20261010.01_rfq_sharper_angle/report_rfq_sharper_angle.md), [RudCo profile](../research/20261010.02_rudco_profile/rudco_profile.md).
- Saved copies: the State of Iowa RFQ text files in [verification_docs](../research/20261010.01_rfq_sharper_angle/verification_docs/), and the normalized Reddit threads and search pages in [reddit_corpus](../research/20261010.01_rfq_sharper_angle/reddit_corpus/normalized/).
- Catalogs: [RudCo](../../data/rudco/catalog.json) and [metals](../../data/metals/catalog.json).
- Code: [buyer_profile.rb](../../tools/rfq_processing/lib/rfq_processing/buyer_profile.rb), [rules_parser.rb](../../tools/rfq_processing/lib/rfq_processing/rules_parser.rb), [client_term.rb](../../app/models/client_term.rb), [client_memory.rb](../../app/services/catalog_match/client_memory.rb), [description_reader.rb](../../app/services/catalog_match/description_reader.rb), [teach_buyer_term.rb](../../app/services/quote_workspace/teach_buyer_term.rb), [buyer_context.rb](../../app/services/quote_workspace/buyer_context.rb).

[iowa18]: ../research/20261010.01_rfq_sharper_angle/verification_docs/iowa.txt
[iowa21p]: ../rfqs/20210615_iowa_steel_tubing/iowa_rfq_2021.pdf
[tn-txt]: ../example_rfqs/transnet-steel-shot-2024/extracted.txt
[tn-pdf]: ../example_rfqs/transnet-steel-shot-2024/source.pdf
[iowa21]: ../research/20261010.01_rfq_sharper_angle/verification_docs/iowa2021.txt
[dr-t]: ../research/20261010.01_rfq_sharper_angle/research_domain_rules.md#6-test-set
[dr-2]: ../research/20261010.01_rfq_sharper_angle/research_domain_rules.md#2-common-specs-by-product-form
[dr-11]: ../research/20261010.01_rfq_sharper_angle/research_domain_rules.md#11-gauge-the-number-means-a-different-thickness-for-each-metal
[dr-12]: ../research/20261010.01_rfq_sharper_angle/research_domain_rules.md#12-size-notation-feet-inches-and-positional-shorthand
[dr-13]: ../research/20261010.01_rfq_sharper_angle/research_domain_rules.md#13-grade-notation
[dr-14]: ../research/20261010.01_rfq_sharper_angle/research_domain_rules.md#14-finish
[dr-32]: ../research/20261010.01_rfq_sharper_angle/research_domain_rules.md#32-detail-one-requirement-at-a-time
[report-65]: ../research/20261010.01_rfq_sharper_angle/report_rfq_sharper_angle.md#65-messy-lines-and-the-gauge-trap
[ow-a]: ../research/20261010.01_rfq_sharper_angle/research_voice_open_web.md#a-usaf-consumable-metals-rfq-verbatim-read-directly
[ow-b]: ../research/20261010.01_rfq_sharper_angle/research_voice_open_web.md#b-usace-steel-rfq-verbatim-read-directly
[ow-c]: ../research/20261010.01_rfq_sharper_angle/research_voice_open_web.md#c-state-of-iowa-rfq-2021-verbatim-read-directly-from-the-pdf-the-fetch-tool-saved
[ow-e]: ../research/20261010.01_rfq_sharper_angle/research_voice_open_web.md#e-other-leads-search-summary-only-check-before-use
[rd-rq2]: ../research/20261010.01_rfq_sharper_angle/research_voice_reddit.md#rq2-messy-line-items-test-cases
[rd-rq3]: ../research/20261010.01_rfq_sharper_angle/research_voice_reddit.md#rq3-costly-mistakes
[rd-rq4]: ../research/20261010.01_rfq_sharper_angle/research_voice_reddit.md#rq4-hidden-requirements
[ualberta]: https://marketplace.ualberta.ca/products/stainless-steel-sheet
[r-1hcriy2]: https://www.reddit.com/r/sheetmetal/comments/1hcriy2/looking_for_fab_shop_that_can_make_this_out_of/
[r-vtls-w0ody]: https://www.reddit.com/r/metalworking/comments/1vtls2e/whats_the_dumbest_little_thing_youve_seen_get/p4w0ody/
[r-vtls-u8wte]: https://www.reddit.com/r/metalworking/comments/1vtls2e/whats_the_dumbest_little_thing_youve_seen_get/p4u8wte/
[r-vtls-50xm4u]: https://www.reddit.com/r/metalworking/comments/1vtls2e/whats_the_dumbest_little_thing_youve_seen_get/p50xm4u/
[r-1ks1tt8]: https://www.reddit.com/r/Machinists/comments/1ks1tt8/theading_od_and_id_and_drilling_inconel_718/
[r-v57bt9]: https://www.reddit.com/r/CNC/comments/v57bt9/putter_quote/
[r-1iz6o3v]: https://www.reddit.com/gallery/1iz6o3v
[r-1e5ga3t]: https://www.reddit.com/r/Machinists/comments/1e5ga3t/what_extra_testing_do_military_grade_fasteners_go/
[r-1b6wixv]: https://www.reddit.com/r/metalworking/comments/1b6wixv/hot_rolled_vs_cold_rolled_tubing/
[r-8jmd8p]: https://www.reddit.com/r/metalworking/comments/8jmd8p/small_quantity_supplier_of_metric_alloy_steel/
[r-1521np9]: https://www.reddit.com/r/sheetmetal/comments/1521np9/what_kind_of_rivet_gun_do_you_need_for_solid_head/
[r-1onuh36]: https://www.reddit.com/r/metalworking/comments/1onuh36/welding_table_top_material_choice_hrpo_vs_a36/
[r-1onuh36-c]: https://www.reddit.com/r/metalworking/comments/1onuh36/welding_table_top_material_choice_hrpo_vs_a36/nn438fo/
[r-15kudev]: https://www.reddit.com/r/Machinists/comments/15kudev/looking_for_a_supplier_for_dfars_compliant_60/
[r-15kudev-fe8f]: https://www.reddit.com/r/Machinists/comments/15kudev/looking_for_a_supplier_for_dfars_compliant_60/jv7fe8f/
[r-1sr80m1]: https://www.reddit.com/r/Machinists/comments/1sr80m1/estimating_costs_swiss_lathe/
