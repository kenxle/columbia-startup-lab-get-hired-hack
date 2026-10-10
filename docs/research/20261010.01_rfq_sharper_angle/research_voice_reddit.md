# Voice of User: Reddit

Track: Voice of user, Reddit (research questions 0 to 4). Written 2026-10-10 for the RFQ sharper-angle brief. Every quote below is copied from a saved Reddit payload and checked against it by script. Each carries a subreddit, month, score, and link. Typos are the posters' own.

## Coverage gaps (read first)

- **No quoting rep at a service center or distributor appears in this corpus.** The supplier voices are job-shop owners, fabricators, machinists, and one sales rep at a plastics job shop. RudCo's own role is missing. The closest matches are the anonymous poster in the repeat-RFQ thread and the plastics rep in the "who builds your quotes" thread. The open-web track has to cover distributor reps.
- **Reddit gives no measured time-per-step.** The only number is one poster's "10+ hours a week". Where time goes is inferred from what people complain about, and that is labeled as inference below.
- **The costly-error evidence comes from one thread.** The thread "What's the dumbest little thing you've seen get missed on a fab quote" (Aug 2026) holds 19 of the 94 quotes in this file, from 13 commenters. These are unverified self-reports. Dollar figures are the posters' own.
- **Round 1 search pages were mostly noise.** 24 of 25 search pages returned results; item 18 (r/purchasing) returned zero. Most hits were hobbyists, construction takeoff estimators (r/estimators), and unrelated viral threads. r/engineering, r/MechanicalEngineering, r/manufacturing, and r/Welding each gave two or fewer relevant threads.
- **Tool builders posted several of the buyer-side threads.** The flag file lists 13 vendor or promotional items across 4 of the 15 threads (7 of them in the repeat-RFQ thread). Posts by builders are not used as evidence. Their comment sections are, with the builder's account marked where it appears.
- **Reddit's saved files are missing some comments.** The CNC thread reports 256 comments and the file holds 182. The procurement quote-format thread reports 24 and holds 15. See the coverage manifest for every thread.
- **Dates run Aug 2023 to Aug 2026.** Seven of the 15 threads are from 2026. Nothing here predates 2023.
- **Unchecked technical claims.** A commenter says aluminum is exempt from DFARS. One account, score 2, no source. The domain-rules track should check it.
- **Demographic skew.** Reddit skews technical and early-adopter. The people here chose to post a question or a story. People who quietly lose a quote do not.

## Short version

- **The most-named pain is the cost of a mistake that slips into a quote, then the amount of manual re-work per RFQ.** Missed notes, wrong material, and stale prices produce the biggest numbers ($250k job costing about $450k; $15-20k expected profit shrinking to $2-3k). Repeat manual RFQ handling produces the most-repeated complaint (10+ hours a week).
- **Hidden requirements are real, but the evidence comes from four threads of machinists, a welder, and one startup builder, not from distributors.** The most vivid line: the same bolt can come with certs or without them.
- **Buyers say speed and a visible reason matter.** A 225-score post compares US shops that never reply with online tools that quote in 24 hours and give design feedback.
- **Of the four candidate angles, the evidence supports "the quote shows its work" and "catches hidden requirements" most. "Learns the buyer's shorthand" has the thinnest support.** Details in the last section.

## Findings

### RQ0: The job steps, who does them, where time goes

**Claim 0.1. Reps describe the steps as: a request arrives by email, someone digs up past prices and suppliers, someone prices it, a boss approves it, and the rep chases the boss.** Reddit gives the sequence only in pieces; this table is assembled from several posters, so it is a reconstruction.

| Step | Who (as posters describe it) | Evidence |
|---|---|---|
| 1. Request arrives by email | Whoever monitors the inbox | r/procurement, Apr 2025, [link](https://www.reddit.com/r/procurement/comments/1jwtpla/who_else_is_stuck_doing_repetitive_rfqs_manually/) |
| 2. Read the print, spec, and notes; find what is missing | Estimator or rep; sometimes the owner | r/Machinists, Dec 2024, [link](https://www.reddit.com/r/Machinists/comments/1hdrjnz/rfq_turned_part_quantity_1/m2118dm/), r/metalworking, Aug 2026, [link](https://www.reddit.com/r/metalworking/comments/1vtls2e/whats_the_dumbest_little_thing_youve_seen_get/p4yub30/) |
| 3. Look up past prices, material cost, and suppliers | Same person | r/procurement, Apr 2025, [link](https://www.reddit.com/r/procurement/comments/1jwtpla/who_else_is_stuck_doing_repetitive_rfqs_manually/), r/metalworking, Aug 2026, [link](https://www.reddit.com/r/metalworking/comments/1vtls2e/whats_the_dumbest_little_thing_youve_seen_get/p4ulybm/) |
| 4. Price material, labor, outside work, hardware | Estimator, GM, or (at one past employer) temps with a price book | r/sales, Feb 2026, [link](https://www.reddit.com/r/sales/comments/1r8h3io/who_builds_your_quotessets_pricing/o658x6a/), r/sales, Feb 2026, [link](https://www.reddit.com/r/sales/comments/1r8h3io/who_builds_your_quotessets_pricing/o668cbk/), r/metalworking, Aug 2026, [link](https://www.reddit.com/r/metalworking/comments/1vtls2e/whats_the_dumbest_little_thing_youve_seen_get/p4wcuhl/) |
| 5. Approval | GM or owner; margin rules decide who can skip it | r/sales, Feb 2026, [link](https://www.reddit.com/r/sales/comments/1r8h3io/who_builds_your_quotessets_pricing/), r/sales, Feb 2026, [link](https://www.reddit.com/r/sales/comments/1r8h3io/who_builds_your_quotessets_pricing/o65uznt/) |
| 6. Send, then defend against a cheaper quote | Rep or owner | r/metalworking, Aug 2026, [link](https://www.reddit.com/r/metalworking/comments/1vtls2e/whats_the_dumbest_little_thing_youve_seen_get/p4z7xpx/), r/metalworking, Nov 2025, [link](https://www.reddit.com/r/metalworking/comments/1onuh36/welding_table_top_material_choice_hrpo_vs_a36/) |

**Claim 0.2. Manual handling of repeat RFQs is the most direct time complaint, and it comes from the supplier side.** (6 records in 2 threads; 13 records in 4 threads across the manual-work themes.)

- “we constantly get quote requests via email, and it turns into a mess of checking inboxes, digging up previous prices, googling suppliers, and replying manually” (r/procurement, Apr 2025, score 22) [link](https://www.reddit.com/r/procurement/comments/1jwtpla/who_else_is_stuck_doing_repetitive_rfqs_manually/)
- “It ends up eating way more time than it should (sometimes 10+ hours a week)” (r/procurement, Apr 2025, score 22) [link](https://www.reddit.com/r/procurement/comments/1jwtpla/who_else_is_stuck_doing_repetitive_rfqs_manually/)
- “Most exhausting part of the process is feeling like you’re starting from scratch with each RFQ.” (r/procurement, Apr 2025, score 5) [link](https://www.reddit.com/r/procurement/comments/1jwtpla/who_else_is_stuck_doing_repetitive_rfqs_manually/mmlwadk/)
- “quotes were done by an army of untrained temps” (r/sales, Feb 2026, score 3) [link](https://www.reddit.com/r/sales/comments/1r8h3io/who_builds_your_quotessets_pricing/o658x6a/)
- “manually calculate based on pricing guidebooks, physical printouts where you'd match the feature to a price and add it all together with a calculator” (r/sales, Feb 2026, score 1) [link](https://www.reddit.com/r/sales/comments/1r8h3io/who_builds_your_quotessets_pricing/o668cbk/)

Counter-evidence: one commenter says "Googling?" does not match their organization, so the pain varies by size.

- “I think we may have different sized organisations” (r/procurement, Apr 2025, score 14) [link](https://www.reddit.com/r/procurement/comments/1jwtpla/who_else_is_stuck_doing_repetitive_rfqs_manually/mml7ai4/)

Another commenter, who says they manage a large indirect-spend budget, describes the status quo as spreadsheets and email:

- “90% of our RFPs are excel and email.” (r/procurement, Apr 2025, score 3) [link](https://www.reddit.com/r/procurement/comments/1jwtpla/who_else_is_stuck_doing_repetitive_rfqs_manually/mmwbcb7/)

**Claim 0.3. Approval is a bottleneck the rep cannot control, and the rep carries the blame for it.** Single thread (a plastics job shop, not metals), so this is an anecdote with a plausible fit to distributors.

- “I have to prove I'm not at fault by showing when I emailed the RFQ package to him.” (r/sales, Feb 2026, score 2) [link](https://www.reddit.com/r/sales/comments/1r8h3io/who_builds_your_quotessets_pricing/)
- “a delay to the customer is my fault, regardless of reason” (r/sales, Feb 2026, score 2) [link](https://www.reddit.com/r/sales/comments/1r8h3io/who_builds_your_quotessets_pricing/)
- “the expectation is that I follow up with him daily on projects we need to quote” (r/sales, Feb 2026, score 2) [link](https://www.reddit.com/r/sales/comments/1r8h3io/who_builds_your_quotessets_pricing/)

One reply shows how margin rules can remove the approval step, and another says reviewing is easier than writing from scratch:

- “sales people have authority to quote anything with a Contribution Margin (Labor and Materials ONLY cost) of greater than X%” (r/sales, Feb 2026, score 2) [link](https://www.reddit.com/r/sales/comments/1r8h3io/who_builds_your_quotessets_pricing/o65uznt/)
- “It’s easier for someone to review then to do.” (r/sales, Feb 2026, score 11) [link](https://www.reddit.com/r/sales/comments/1r8h3io/who_builds_your_quotessets_pricing/o654ywn/)

**Claim 0.4. The value props people name themselves, in order of how much weight the evidence carries.** This ranking is mine, built from the counts below. It is a judgment call, not a poll.

| Value prop | What posters say | Threads | Source side |
|---|---|---|---|
| Avoiding costly errors and lost margin | Missed notes, wrong material, stale material prices turn into five- and six-figure losses | 15 records in 1 thread | Suppliers |
| Speed to a first response | Buyers pick tools that answer in 24 hours with design feedback; shops admit ghosting | 4 records in 1 thread | Buyers and suppliers |
| Rep time saved on repeat RFQs | "10+ hours a week" | 6 records in 2 threads | Suppliers |
| Comparable, explained quotes | Buyers want the same basis across quotes and the reason behind each number | 11 records in 4 threads | Buyers |
| Compliance paperwork done right | Certs and traceability are what the buyer pays for | 16 records in 4 threads | Both |

No poster ties faster quoting to a measured win rate. That link is assumed, not shown, in this corpus.

**Claim 0.5. Buyers who get no reply describe moving to online tools that answer in a day.** The top-scoring buyer complaint is about response, and a shop-side commenter confirms that shops ghost.

- “90% of the time they don’t even ever reach out to you” (r/CNC, Mar 2026, score 222) [link](https://www.reddit.com/r/CNC/comments/1s81l5g/why_are_us_machine_shops_so_difficult_to_work_with/)
- “send in a quote on an online quoting tool, get quote within 24hours or sometimes instantly. Get dfm analysis that you can view” (r/CNC, Mar 2026, score 222) [link](https://www.reddit.com/r/CNC/comments/1s81l5g/why_are_us_machine_shops_so_difficult_to_work_with/)
- “China will just build a test batch for trials before a Western company has got back in touch on the RFQ.” (r/CNC, Mar 2026, score 33) [link](https://www.reddit.com/r/CNC/comments/1s81l5g/why_are_us_machine_shops_so_difficult_to_work_with/odefcp1/)
- “I am guilty of ghosting such clients.” (r/CNC, Mar 2026, score 26) [link](https://www.reddit.com/r/CNC/comments/1s81l5g/why_are_us_machine_shops_so_difficult_to_work_with/ode0mqa/)

Caveat: this is a buyer shopping one-off machined parts from job shops, not a distributor's customer. Shop owners in the same thread also say cold, badly designed requests earn no reply.

- “Stupid tight tolerances for no reason.” (r/CNC, Mar 2026, score 80) [link](https://www.reddit.com/r/CNC/comments/1s81l5g/why_are_us_machine_shops_so_difficult_to_work_with/oddnkm1/)
- “it's not their job to unfuck your design for a quote.” (r/CNC, Mar 2026, score 27) [link](https://www.reddit.com/r/CNC/comments/1s81l5g/why_are_us_machine_shops_so_difficult_to_work_with/odevvd3/)

### RQ1: Pain, in their words

**Claim 1.1. Buyers say quotes from different suppliers arrive on different bases, so they cannot be compared.** (11 records in 4 threads.)

- “One gives unit price only. Another gives MOQ but no lead time. Another mentions “shipping extra” but doesn’t say how much.” (r/procurement, Jan 2026, score 1) [link](https://www.reddit.com/r/procurement/comments/1qn5ad5/how_do_you_compare_supplier_quotes_when_everyone/)
- “the biggest issue is when suppliers technically answer the RFQ but don’t answer it on the same basis.” (r/procurement, Aug 2026, score 1) [link](https://www.reddit.com/r/procurement/comments/1w1lwdg/what_fields_make_supplier_quotes_comparable/p6t572u/)
- “an EXW and a DDP quote aren't comparable numbers at all” (r/procurement, Aug 2026, score 3) [link](https://www.reddit.com/r/procurement/comments/1w1lwdg/what_fields_make_supplier_quotes_comparable/p6mbmm2/)
- “Spec revision because the silent version is lethal: three suppliers quoting three different revisions look like a price spread but are actually a scope spread” (r/procurement, Aug 2026, score 3) [link](https://www.reddit.com/r/procurement/comments/1w1lwdg/what_fields_make_supplier_quotes_comparable/p6mbmm2/)
- “"quoted per your drawing" with no revision number is the tell” (r/procurement, Aug 2026, score 3) [link](https://www.reddit.com/r/procurement/comments/1w1lwdg/what_fields_make_supplier_quotes_comparable/p6mbmm2/)
- “a minimum comparable-data gate before evaluation: unit price with currency and UOM, lead time definition, MOQ, Incoterms, payment terms, and validity date.” (r/procurement, Feb 2026, score 1) [link](https://www.reddit.com/r/procurement/comments/1qw7fu5/anyone_else_still_manually_comparing_supplier/o7lsyex/)

Account note: the three procurement threads behind these quotes were started by accounts tied to quote tooling. One links its own tool, one discloses working on supplier and quote tooling, and one was called a vendor by another commenter. The commenters quoted above are not flagged in the saved files. The provenance and exceptions-column quotes later in this file come from the account that started the comparable-fields thread.

Buyers' fix on Reddit is a mandatory template, not a tool:

- “Yes we have a standard RFT response template we expect them to fill in and non-negotiable fields.” (r/procurement, Jan 2026, score 9) [link](https://www.reddit.com/r/procurement/comments/1qn5ad5/how_do_you_compare_supplier_quotes_when_everyone/o1repzc/)
- “You also don't need to do something so complex where a formatted (standardized) excel sheet can do the job.” (r/procurement, Feb 2026, score 2) [link](https://www.reddit.com/r/procurement/comments/1qw7fu5/anyone_else_still_manually_comparing_supplier/o3ne9wq/)

**Claim 1.2. Suppliers and buyers describe incomplete requests that need a question before anyone can price, and the question is often asked informally or skipped.** (8 records in 5 threads.)

- “What would you guys do about missing dimensions for angles, lengths radius etc. would you go back to the customer for that info or just go ahead and make them up as it’s all so open?” (r/Machinists, Dec 2024, score 2) [link](https://www.reddit.com/r/Machinists/comments/1hdrjnz/rfq_turned_part_quantity_1/m2118dm/)
- “What angle is needed?” (r/sheetmetal, Dec 2024, score 15) [link](https://www.reddit.com/r/sheetmetal/comments/1hcriy2/looking_for_fab_shop_that_can_make_this_out_of/m1qfp01/)
- “Not a single dimension mentioned” (r/sheetmetal, Dec 2024, score 9) [link](https://www.reddit.com/r/sheetmetal/comments/1hcriy2/looking_for_fab_shop_that_can_make_this_out_of/m1qj3px/)
- “From my end, it is just difficult to gauge a cold-rfq, but I do try to help out people as much as I can if they put in some notes in the email.” (r/Machinists, Apr 2026, score 3) [link](https://www.reddit.com/r/Machinists/comments/1sr80m1/estimating_costs_swiss_lathe/ohd9tve/)
- “instead of asking "can you confirm your quote?" you can ask for the exact missing field that blocks comparability” (r/procurement, Aug 2026, score 1) [link](https://www.reddit.com/r/procurement/comments/1w1lwdg/what_fields_make_supplier_quotes_comparable/p6trxiv/)

The last quote is from a buyer-side thread, but it states the one-click-question idea in plain words: ask for the exact missing field, not for a general confirmation.

**Claim 1.3. Suppliers describe price pressure from a cheaper quote that left things out.** Single thread.

- “it turns out the other supplier hasn't accounted for X, Y or Z.” (r/metalworking, Aug 2026, score 4) [link](https://www.reddit.com/r/metalworking/comments/1vtls2e/whats_the_dumbest_little_thing_youve_seen_get/p4z7xpx/)

**Claim 1.4. Same RFQ, wildly different prices.** One post asked for a price on a one-off long turned part, shown as an image. The commenters guess prices from about $1k to $20k. These are commenters guessing, not real quotes, but the spread shows how much depends on assumptions that the RFQ does not state.

- “Ornamental only? 1k all in.” (r/Machinists, Dec 2024, score 2) [link](https://www.reddit.com/r/Machinists/comments/1hdrjnz/rfq_turned_part_quantity_1/m20ufly/)
- “$3200 labor only” (r/Machinists, Dec 2024, score 19) [link](https://www.reddit.com/r/Machinists/comments/1hdrjnz/rfq_turned_part_quantity_1/m1ybi22/)
- “$20k” (r/Machinists, Dec 2024, score -2) [link](https://www.reddit.com/r/Machinists/comments/1hdrjnz/rfq_turned_part_quantity_1/m1yad40/)

**Claim 1.5. On tools, users say instant online quoting is fast and cheap to try but misses the human feedback and can run high.** Other tool mentions in the corpus are single-line.

- “Xometry is near instantaneous and free, and won’t waste another human’s time.” (r/Machinists, Apr 2026, score 9) [link](https://www.reddit.com/r/Machinists/comments/1sr80m1/estimating_costs_swiss_lathe/ohczx2f/)
- “I've tried Xometry in the past, but they've been over 2-5x the costs I get back.” (r/Machinists, Apr 2026, score 2) [link](https://www.reddit.com/r/Machinists/comments/1sr80m1/estimating_costs_swiss_lathe/ohd0jc4/)
- “QuoteFx, QuoteWin are both SaaS that manage quotes and pricing data” (r/supplychain, Dec 2024, score 3) [link](https://www.reddit.com/r/supplychain/comments/1hqq099/is_there_a_better_tool_than_excel_for_managing/m4rpr61/)

**Claim 1.6. Commenters distrust AI-structured quote output and vendors fishing for product ideas.** One thread, so a signal about trust, not a count.

- “As anything with AI it is highly risky and hit-and-miss, as all models hallucinate AF you still have to check manually so there is no point.” (r/procurement, Jan 2026, score 2) [link](https://www.reddit.com/r/procurement/comments/1qn5ad5/how_do_you_compare_supplier_quotes_when_everyone/o1rvvaq/)
- “I spot ChatGPT answer I stop answering.” (r/procurement, Jan 2026, score 6) [link](https://www.reddit.com/r/procurement/comments/1qn5ad5/how_do_you_compare_supplier_quotes_when_everyone/o1sibkw/)
- “Just another vendor fishing to help build their app” (r/procurement, Jan 2026, score 9) [link](https://www.reddit.com/r/procurement/comments/1qn5ad5/how_do_you_compare_supplier_quotes_when_everyone/o1swrpt/)

### RQ2: Messy line items (test cases)

**Claim 2.1. The same item shows up under several names, and the source often does not resolve which is meant.** Each row is copied from the post or comment. "Reading" is given only where the source makes it clear; otherwise it says so. (17 records in 6 threads.)

| Line as written | Reading, and where it comes from | Source |
|---|---|---|
| “Spec and quote was for 316ss sch80 pipe.” | 316 stainless, Schedule 80 pipe. The same story later says the purchased material was "304ss sch40", so the two lines differ in grade and wall. | r/metalworking, Aug 2026, [link](https://www.reddit.com/r/metalworking/comments/1vtls2e/whats_the_dumbest_little_thing_youve_seen_get/p4w0ody/); r/metalworking, Aug 2026, [link](https://www.reddit.com/r/metalworking/comments/1vtls2e/whats_the_dumbest_little_thing_youve_seen_get/p4w0ody/) |
| “I ordered $80,000 worth of 7” XS seamless pipe to make 700 caps.” | "XS" is not defined in the thread. In general industry use it means extra-strong wall. That meaning is from outside the source. | r/metalworking, Aug 2026, [link](https://www.reddit.com/r/metalworking/comments/1vtls2e/whats_the_dumbest_little_thing_youve_seen_get/p50xm4u/) |
| “made from 3/8" 316 stainless plate” | 3/8 inch thick, 316 stainless plate. | r/metalworking, Aug 2026, [link](https://www.reddit.com/r/metalworking/comments/1vtls2e/whats_the_dumbest_little_thing_youve_seen_get/p4ukw5y/) |
| “steel sqare pipe witz 5mm thickness” | Square pipe (tube), 5mm wall, as written by a non-native English speaker. The story then substitutes 4mm. | r/metalworking, Aug 2026, [link](https://www.reddit.com/r/metalworking/comments/1vtls2e/whats_the_dumbest_little_thing_youve_seen_get/p4u8wte/); r/metalworking, Aug 2026, [link](https://www.reddit.com/r/metalworking/comments/1vtls2e/whats_the_dumbest_little_thing_youve_seen_get/p4u8wte/) |
| “one place wants $685.77 for a 43x67" 1/2" thick plate HRPO plus $150 for plasma cutting it to that size from the stock sheet. Another place which is a huge steel supplier but still deals with the public quoted me $417.24 but it's just A36 and not HRPO.” | The poster treats HRPO and A36 as different products. A commenter's reading is in the next row. | r/metalworking, Nov 2025, [link](https://www.reddit.com/r/metalworking/comments/1onuh36/welding_table_top_material_choice_hrpo_vs_a36/) |
| “As far as I know, HRPO is just acid-dipped hot rolled A36” | This commenter says HRPO is hot rolled A36 that has been acid-dipped to remove mill scale. One commenter's view. | r/metalworking, Nov 2025, [link](https://www.reddit.com/r/metalworking/comments/1onuh36/welding_table_top_material_choice_hrpo_vs_a36/nn438fo/) |
| “301 stainless steel, 26 gauge, brushed finish. 10 units for prototyping, then 100.” | 301 stainless, 26 gauge, brushed finish, 10 then 100 units. A commenter equates the gauge to ".018" thick; another warns about "half hardened 301". Temper is a hidden attribute. | r/sheetmetal, Dec 2024, [link](https://i.redd.it/gnft4qx2mg6e1.png); r/sheetmetal, Dec 2024, [link](https://www.reddit.com/r/sheetmetal/comments/1hcriy2/looking_for_fab_shop_that_can_make_this_out_of/m2m71e0/); r/sheetmetal, Dec 2024, [link](https://www.reddit.com/r/sheetmetal/comments/1hcriy2/looking_for_fab_shop_that_can_make_this_out_of/m2jqjq8/) |
| “It may be 304 versus 301 stainless for hvac ducts.” | A commenter casually swaps 304 for 301. Whether that is acceptable depends on the spec; the thread does not say. | r/sheetmetal, Dec 2024, [link](https://www.reddit.com/r/sheetmetal/comments/1hcriy2/looking_for_fab_shop_that_can_make_this_out_of/m1rr4ru/) |
| “Looking for a supplier for DFARS Compliant 60 series aluminum. Also has to be made in the USA” | The buyer uses "DFARS compliant" and "made in the USA" together. A commenter separates them: domestic is doable, a DFARS statement on the cert is the hard part. The buyer says the customer wants domestic. | r/Machinists, Aug 2023, [link](https://www.reddit.com/r/Machinists/comments/15kudev/looking_for_a_supplier_for_dfars_compliant_60/); r/Machinists, Aug 2023, [link](https://www.reddit.com/r/Machinists/comments/15kudev/looking_for_a_supplier_for_dfars_compliant_60/jv7cto7/) |
| “I need 3:16 7075 round” | Unclear. Possibly 3-1/16 inch diameter 7075 round bar; the source does not say. | r/Machinists, Aug 2023, [link](https://www.reddit.com/r/Machinists/comments/15kudev/looking_for_a_supplier_for_dfars_compliant_60/jv7fe8f/) |
| “Assuming 46" of 4" A36” | A material assumption: 46 inch of 4 inch A36 bar. | r/Machinists, Dec 2024, [link](https://www.reddit.com/r/Machinists/comments/1hdrjnz/rfq_turned_part_quantity_1/m1z32a4/) |
| “Mcmaster had a 3ft bar of 1018 at 3-7/8 dia for $388.” | A different assumption for the same drawing: 1018 bar at 3-7/8 inch. Same RFQ, two bar sizes and two grades. | r/Machinists, Dec 2024, [link](https://www.reddit.com/r/Machinists/comments/1hdrjnz/rfq_turned_part_quantity_1/m1yk101/) |
| “Does not say anywhere that this is cylindrical.” | The drawing does not say the part is cylindrical, so a plasma-cut reading is possible. | r/Machinists, Dec 2024, [link](https://www.reddit.com/r/Machinists/comments/1hdrjnz/rfq_turned_part_quantity_1/m20xm74/) |
| “ePlastics natural ULEM 1000, 10ft.” | Likely a typo of Ultem 1000. The source does not say so outright. | r/Machinists, Apr 2026, [link](https://www.reddit.com/r/Machinists/comments/1sr80m1/estimating_costs_swiss_lathe/ohdab90/) |
| “ULTEM 1000 or Polycarbonate” | Same thread, material named as "ULTEM 1000 or Polycarbonate". | r/Machinists, Apr 2026, [link](https://www.reddit.com/r/Machinists/comments/1sr80m1/estimating_costs_swiss_lathe/ohd7j5d/) |
| “McMaster prices for 5ft of Ultem PEI is like $24.75/bar” | A third name, "Ultem PEI", for what looks like the same plastic. | r/Machinists, Apr 2026, [link](https://www.reddit.com/r/Machinists/comments/1sr80m1/estimating_costs_swiss_lathe/ohd8z5o/) |
| “MILL TEST REPOET FOR SA105 MATERIAL SHOWS CARBON AT .17 AND Mn AT 1.1. HOW DO WE KNOW IT SHOULD BE FLAGGED OR NOT.” | A mill test report for SA105 showing carbon .17 and manganese 1.1. The poster does not know whether to flag it. | r/Welding, Nov 2023, [link](https://www.reddit.com/r/Welding/comments/17rvmhj/mtr_checking_manganese_105_sa105/) |
| “my boss “took off” an entire high school duct job at 1/8” scale instead of 1/4” scale.” | A drawing scale misread (1/8 vs 1/4). | r/metalworking, Aug 2026, [link](https://www.reddit.com/r/metalworking/comments/1vtls2e/whats_the_dumbest_little_thing_youve_seen_get/p4uqigy/) |
| “A decimal point placement on gold plating. 10x too thick” | A decimal point error. | r/metalworking, Aug 2026, [link](https://www.reddit.com/r/metalworking/comments/1vtls2e/whats_the_dumbest_little_thing_youve_seen_get/p4vui51/) |

Three rows (the Ultem ones) are plastic. They are included because the naming problem is the same.

### RQ3: Costly mistakes

**Claim 3.1. The costliest slips are missed notes and callouts, wrong material or spec, and stale material prices.** (15 records in 1 thread, all from the fab-quote thread.) Thirteen commenters in that thread describe separate incidents, so the pattern repeats within the thread, but it is one thread.

Wrong material or grade:

- “Spec and quote was for 316ss sch80 pipe.” (r/metalworking, Aug 2026, score 5) [link](https://www.reddit.com/r/metalworking/comments/1vtls2e/whats_the_dumbest_little_thing_youve_seen_get/p4w0ody/)
- “304ss sch40 was purchased by mistake.” (r/metalworking, Aug 2026, score 5) [link](https://www.reddit.com/r/metalworking/comments/1vtls2e/whats_the_dumbest_little_thing_youve_seen_get/p4w0ody/)
- “it was a $250k job that ended up costing close to $450k.” (r/metalworking, Aug 2026, score 5) [link](https://www.reddit.com/r/metalworking/comments/1vtls2e/whats_the_dumbest_little_thing_youve_seen_get/p4w0ody/)
- “just use the normal 4mm, they will never see it.” (r/metalworking, Aug 2026, score 13) [link](https://www.reddit.com/r/metalworking/comments/1vtls2e/whats_the_dumbest_little_thing_youve_seen_get/p4u8wte/)
- “He misinterpreted the P/O, what the customer actually wanted were shims for those caps.” (r/metalworking, Aug 2026, score 2) [link](https://www.reddit.com/r/metalworking/comments/1vtls2e/whats_the_dumbest_little_thing_youve_seen_get/p50xm4u/)

Missed notes and weld details:

- “Seems like quoting guys don’t understand that the cost between a 3/8” fillet weld and a 1/4” fillet weld can be 3x more.” (r/metalworking, Aug 2026, score 54) [link](https://www.reddit.com/r/metalworking/comments/1vtls2e/whats_the_dumbest_little_thing_youve_seen_get/p4u79mi/)
- “Early in my career I missed a note calling out weld size.” (r/metalworking, Aug 2026, score 54) [link](https://www.reddit.com/r/metalworking/comments/1vtls2e/whats_the_dumbest_little_thing_youve_seen_get/p4u79mi/)
- “Following just the drawings when there were additional written instructions that added way more work.” (r/metalworking, Aug 2026, score 3) [link](https://www.reddit.com/r/metalworking/comments/1vtls2e/whats_the_dumbest_little_thing_youve_seen_get/p4yub30/)
- “Missed the part where it said the welds are to be purged...” (r/metalworking, Aug 2026, score 10) [link](https://www.reddit.com/r/metalworking/comments/1vtls2e/whats_the_dumbest_little_thing_youve_seen_get/p4u4jeg/)
- “They lost money on a big project because of a one liner in the scope.” (r/metalworking, Aug 2026, score 2) [link](https://www.reddit.com/r/metalworking/comments/1vtls2e/whats_the_dumbest_little_thing_youve_seen_get/p4whd7x/)

Units, scale, and numbers:

- “my boss “took off” an entire high school duct job at 1/8” scale instead of 1/4” scale.” (r/metalworking, Aug 2026, score 4) [link](https://www.reddit.com/r/metalworking/comments/1vtls2e/whats_the_dumbest_little_thing_youve_seen_get/p4uqigy/)
- “A decimal point placement on gold plating. 10x too thick” (r/metalworking, Aug 2026, score 17) [link](https://www.reddit.com/r/metalworking/comments/1vtls2e/whats_the_dumbest_little_thing_youve_seen_get/p4vui51/)

Stale price data in the quoting system:

- “the material pricing in the system wasn't getting updated like I thought it was. Labor was good, material was VERY bad and ended up only making, at best, $2-3k on the whole job. Should have been an easy $15-20k in profit.” (r/metalworking, Aug 2026, score 6) [link](https://www.reddit.com/r/metalworking/comments/1vtls2e/whats_the_dumbest_little_thing_youve_seen_get/p4ulybm/)

Hardware with minimum order quantities and long lead times:

- “Not paying attention to hardware requirements and quoting a couple cents each assuming that is going to cover it then finding out there is a 10,000 piece MOQ (or worse)” (r/metalworking, Aug 2026, score 9) [link](https://www.reddit.com/r/metalworking/comments/1vtls2e/whats_the_dumbest_little_thing_youve_seen_get/p4wcuhl/)

**Claim 3.2. No gauge-to-thickness error story appears in the 15 threads read.** The only gauge discussion (r/sheetmetal) is about whether a 26 gauge 301 part can be bent to a sharp angle. No poster reports a gauge table mistake. The round 1 search listings were not read thread by thread, so this is a finding about the pages read, not about Reddit. The domain-rules track covers gauge tables.

### RQ4: Hidden requirements

**Claim 4.1. Buyers expect certs and traceability that cost real money, and the paperwork is the product.** (16 records in 4 threads: 16 records in 4 threads.)

- “Those certs are what you’re paying for.” (r/Machinists, Jul 2024, score 107) [link](https://www.reddit.com/r/Machinists/comments/1e5ga3t/what_extra_testing_do_military_grade_fasteners_go/ldllyym/)
- “The are the same bolt. One has certs and one doesn’t.” (r/Machinists, Jul 2024, score 1) [link](https://www.reddit.com/r/Machinists/comments/1e5ga3t/what_extra_testing_do_military_grade_fasteners_go/ldpdh4t/)
- “It's not military "grade".... it's military "spec".” (r/Machinists, Jul 2024, score 6) [link](https://www.reddit.com/r/Machinists/comments/1e5ga3t/what_extra_testing_do_military_grade_fasteners_go/ldoghrp/)
- “MIL spec requires full traceability.” (r/Machinists, Jul 2024, score 6) [link](https://www.reddit.com/r/Machinists/comments/1e5ga3t/what_extra_testing_do_military_grade_fasteners_go/ldoghrp/)
- “it’s the documentation, certification, record keeping” (r/Machinists, Jul 2024, score 29) [link](https://www.reddit.com/r/Machinists/comments/1e5ga3t/what_extra_testing_do_military_grade_fasteners_go/ldlls91/)

**Claim 4.2. "DFARS" and "made in the USA" get used loosely, and the bottleneck is what the mill test report says.** One thread, low scores.

- “Looking for a supplier for DFARS Compliant 60 series aluminum. Also has to be made in the USA” (r/Machinists, Aug 2023, score 1) [link](https://www.reddit.com/r/Machinists/comments/15kudev/looking_for_a_supplier_for_dfars_compliant_60/)
- “my customer still wants domestic source and will not take anything else” (r/Machinists, Aug 2023, score 1) [link](https://www.reddit.com/r/Machinists/comments/15kudev/looking_for_a_supplier_for_dfars_compliant_60/jv7cto7/)
- “Aluminum is exempt from DFARS, so technically, there is no such thing as DFARS compliant aluminum” (r/Machinists, Aug 2023, score 2) [link](https://www.reddit.com/r/Machinists/comments/15kudev/looking_for_a_supplier_for_dfars_compliant_60/jv7co7a/)
- “Domestic is doable, just having the CMTR state DFARS compliant is the hard part.” (r/Machinists, Aug 2023, score 2) [link](https://www.reddit.com/r/Machinists/comments/15kudev/looking_for_a_supplier_for_dfars_compliant_60/jv7d3fb/)

Commenters in the military-fastener thread tie "military" to domestic supply, and one supplier says domestic material alone can cost more than an overseas finished part:

- “Military grade means no Chinese vendors anywhere in the process.” (r/Machinists, Jul 2024, score 3) [link](https://www.reddit.com/r/Machinists/comments/1e5ga3t/what_extra_testing_do_military_grade_fasteners_go/ldnevf1/)
- “their cost from overseas (complete) was cheaper than just the material cost for me” (r/Machinists, Jul 2024, score 1) [link](https://www.reddit.com/r/Machinists/comments/1e5ga3t/what_extra_testing_do_military_grade_fasteners_go/ldmavo1/)

Distributors a commenter named for domestic aluminum (Aug 2023):

- “Some vendors in my area are EMJ, Clinton Aluminum, Yarde, and Ryerson.” (r/Machinists, Aug 2023, score 4) [link](https://www.reddit.com/r/Machinists/comments/15kudev/looking_for_a_supplier_for_dfars_compliant_60/jv7ozx9/)

**Claim 4.3. Checking a mill test report against the spec is done by hand, and the answer depends on which edition of the spec you hold.** One short thread.

- “MILL TEST REPOET FOR SA105 MATERIAL SHOWS CARBON AT .17 AND Mn AT 1.1. HOW DO WE KNOW IT SHOULD BE FLAGGED OR NOT.” (r/Welding, Nov 2023, score 1) [link](https://www.reddit.com/r/Welding/comments/17rvmhj/mtr_checking_manganese_105_sa105/)
- “I'm using ASTM A105 and my version is different than yours (ASME?).” (r/Welding, Nov 2023, score 2) [link](https://www.reddit.com/r/Welding/comments/17rvmhj/mtr_checking_manganese_105_sa105/k8lror3/)
- “can we pass this MTR according to the code(ASME) or flag it, though the material might be okay ?” (r/Welding, Nov 2023, score 1) [link](https://www.reddit.com/r/Welding/comments/17rvmhj/mtr_checking_manganese_105_sa105/k8lv9i8/)

**Claim 4.4. Export control can be triggered by the part's use, not by the material line.** Single comment.

- “If this is a munitions part this material may be ITAR/ export controlled and you may want to remove this info just as a CYA” (r/Machinists, Apr 2026, score 1) [link](https://www.reddit.com/r/Machinists/comments/1sr80m1/estimating_costs_swiss_lathe/ohdusj5/)

**Claim 4.5. Buyers want exceptions and assumptions (spec revision, substitutions, test and cert assumptions) visible next to every line.** Buyer-side, from the account that started the thread.

- “I like forcing an exceptions column next to every quoted line, not buried in footnotes: spec revision, excluded accessories/packaging, substitute material, test/cert assumptions, warranty/remedy limits, and any Incoterm or freight exclusions.” (r/procurement, Aug 2026, score 1) [link](https://www.reddit.com/r/procurement/comments/1w1lwdg/what_fields_make_supplier_quotes_comparable/p6o93l0/)

What triggers each requirement, as far as the posters say:

| Requirement | What triggers it (per posters) | Source |
|---|---|---|
| Mill test report or cert with traceability back to the material | Military or aerospace spec ("MIL spec") on the part; the bolt example | r/Machinists, Jul 2024, [link](https://www.reddit.com/r/Machinists/comments/1e5ga3t/what_extra_testing_do_military_grade_fasteners_go/ldoghrp/) |
| Domestic source | A customer saying so; the poster does not always say which rule | r/Machinists, Aug 2023, [link](https://www.reddit.com/r/Machinists/comments/15kudev/looking_for_a_supplier_for_dfars_compliant_60/jv7cto7/) |
| DFARS statement on the cert | A defense end use; unclear whether aluminum is covered (one comment says no) | r/Machinists, Aug 2023, [link](https://www.reddit.com/r/Machinists/comments/15kudev/looking_for_a_supplier_for_dfars_compliant_60/jv7d3fb/) |
| ITAR or export control | The part is a munitions component | r/Machinists, Apr 2026, [link](https://www.reddit.com/r/Machinists/comments/1sr80m1/estimating_costs_swiss_lathe/ohdusj5/) |
| Spec revision and edition | A drawing that says "per your drawing" without a revision | r/procurement, Aug 2026, [link](https://www.reddit.com/r/procurement/comments/1w1lwdg/what_fields_make_supplier_quotes_comparable/p6mbmm2/); r/Welding, Nov 2023, [link](https://www.reddit.com/r/Welding/comments/17rvmhj/mtr_checking_manganese_105_sa105/k8lror3/) |
| Notes on the print (weld size, purge) | Written notes that sit apart from the geometry | r/metalworking, Aug 2026, [link](https://www.reddit.com/r/metalworking/comments/1vtls2e/whats_the_dumbest_little_thing_youve_seen_get/p4yub30/); r/metalworking, Aug 2026, [link](https://www.reddit.com/r/metalworking/comments/1vtls2e/whats_the_dumbest_little_thing_youve_seen_get/p4u4jeg/) |

## What this says about the four candidate angles

Counts come from `voc_records.jsonl`, grouped by the `rfq_theme` field. They are counts of quoted records and distinct threads in this corpus, not a survey.

| Angle | What Reddit says | Strength | Caveats |
|---|---|---|---|
| **The quote shows its work** | Buyers want to see where each field came from and what was assumed (3 records in 1 thread). A supplier-side poster says reviewing is easier than writing from scratch. Another quoted a job of almost $100k with a material price the system had not updated, and kept $2-3k instead of an expected $15-20k; a visible price source and date would have exposed it. Readers distrust AI that cannot be checked. | Strong in logic. Thin in count. | The provenance quotes come from an account that discloses working on quote tooling. The stale-price story is one commenter. Trust issue is one thread. |
| **One-click buyer questions** | Shops ask "What angle is needed?", buyers leave out dimensions, and cold RFQs get ghosted or answered with a question. The buyer-side thread says ask for the exact missing field. (8 records in 5 threads) | Moderate | Asking is described as normal and manual. No one says the question step is slow; they say it is skipped or ignored. |
| **Learns the buyer's shorthand** | One poster says every RFQ feels like starting from scratch (a single comment). Items show naming variation (Ultem, ULEM, PEI; HRPO vs A36; "DFARS" vs "domestic"). No poster describes one buyer writing the same shorthand repeatedly. | Weak | Single anecdote about re-work. The naming evidence shows variation across people, which is a different problem from one buyer's habits. |
| **Catches hidden requirements** | Certs and traceability cost money (5 records in 1 thread). DFARS and domestic get conflated (7 records in 2 threads). MTR checks are manual and depend on the spec edition (3 records in 1 thread). Missed notes cause the biggest losses (5 records in 1 thread). | Moderate to strong | The cert evidence is from machinists and inspectors, not from distributor quoting reps. The missed-note stories are about notes on the print, not about requirements the spec only implies. |

**Possible fifth angle the evidence suggests.** Combine the strongest parts of two angles: a quote that lists, next to each line, what it assumed and what it read from the notes on the print (weld size, purge, spec revision, test and cert assumptions), with the source shown. The missed-note stories (5 records in 1 thread) and the exceptions-column quote point to it. The same evidence also names a second candidate: a price source and age shown on every material price, from the stale-price story. Both are single-thread evidence.

**Ranking from Reddit alone, with confidence.** This is my judgment from the counts above.

- 1. Catches hidden requirements, broadened to include notes on the print.
- 2. The quote shows its work.
- 3. One-click buyer questions.
- 4. Learns the buyer's shorthand.

Confidence is low to moderate, because the people closest to RudCo's reps are missing from this corpus and most of the strong evidence is one thread. The open-web track should confirm or overturn this using distributor reps.

## Failure mode notes

- **Tool-builder posts.** 13 flagged items in `vendor_flags.csv`. The most promoted threads are the repeat-RFQ, quote-format, and quote-comparison threads. The poster of the quote-comparison thread links their own tool. One commenter in the quote-format thread says outright that the poster is fishing for an app.
- **Self-reported anecdotes.** Dollar amounts and outcomes in the fab-quote thread cannot be verified.
- **Survivorship.** The posters are people who stayed and answer questions online. Reps who quit or lost accounts are absent.
- **Recency.** The costly-error thread is from Aug 2026. The cert thread is from Jul 2024. The DFARS thread is from Aug 2023, so it may not reflect current rules.
- **Individual makers.** Three of the 15 threads (HRPO vs A36 for a welding table, the one-off turned part, the 301 stainless part) come from individual makers or founders, not industrial buyers.

## Corpus coverage

- Subreddits read: r/procurement, r/supplychain, r/sales, r/Machinists, r/metalworking, r/Welding, r/sheetmetal, r/CNC. Round 1 also pulled search pages from r/manufacturing, r/MetalFabrication, r/engineering, r/MechanicalEngineering, r/estimators, r/purchasing.
- Date range: 2023-08 to 2026-08 (quoted items).
- Threads: 15 read (15 of 15 round-2 threads, none empty); round 1: 24 search pages with results, 1 empty (r/purchasing). Per-thread table in `coverage_manifest.md`.
- Records emitted: 94 in `voc_records.jsonl` from 15 threads, dry-run validated, rejected 0.
- Vocabulary note: the shared warehouse vocabulary has no RFQ themes. Each record carries a generic placeholder theme so it validates, plus a real `rfq_theme` field and an `rfq_questions` field. Counts in this file come from `rfq_theme`. If these records are loaded into the warehouse, the RFQ themes need adding to `~/.claude/voc/schema.sql` and `load.py` first. The side field maps "trainer" to the supplier or quoting side and "client" to the buyer side.
- Suggested next pulls (not run; deadline): the "Anything better than Xometry?" thread in r/CNC, and the job-shop quoting threads in r/CNC and r/Machinists, if the open-web track finds Reddit useful.
