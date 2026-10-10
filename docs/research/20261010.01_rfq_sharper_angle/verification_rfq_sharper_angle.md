# Citation Verification: report_rfq_sharper_angle

**Report:** docs/research/20261010.01_rfq_sharper_angle/report_rfq_sharper_angle.md
**Date checked:** 2026-10-10
**Scope:** Priority 1, every quote in quotation marks in the main report. Priority 2, every number. Priority 3, named-person quotes in the research_*.md appendices.
**Verification artifacts:** verification_docs/ (fetched pages, Iowa PDFs, agent evidence files, and `report_rfq_sharper_angle.before_fixes.md`, the report as it stood before edits)
**Reddit method:** all Reddit quotes checked by script against the saved payloads in `reddit_corpus/raw/`. No reddit.com fetches.

## Summary

- Reddit quotes in the main report: 14 of 14 verbatim, each in the comment or post the link points to. Scores 222 (CNC post) and 107 (top comment) match the saved thread files. "13 commenters" in the fab-quote thread matches.
- Reddit quotes in the appendices: 109 quote strings on lines with a Reddit link, all found in the saved payloads (one was in the post body, not the cited comment).
- Gauge values and percentages: all 12 table values match the Metal Supermarkets chart; 4.2%, 4.5%, and 24.2% match `domain_rules_gauge_calc.py` output (re-run).
- 12 problems found and fixed in the main report. None were fabricated quotes. Most were paraphrases that went past the source.
- The three appendix quotes blocked to curl (Paul Parsons, Shawne O'Connor, Practical Machinist "Neeman") were verified verbatim afterward through a browser.

## Action Required (all fixed in the report)

| # | Where | Problem | Fix |
|---|---|---|---|
| 1 | 6.1, Precision Steel posting | Report said "ten duties". The posting lists 13. | Changed to "thirteen". |
| 2 | 6.2, Distribution Strategy Group | Report said the consultant "estimates quoting staff spend 75% to 80% of their time gathering and checking data". Source gives two separate statements: 75% of time on data preparation; 80% hunting through systems, validating data, assembling quotes. | Reworded to the two statements. |
| 3 | 6.2, Utah Steel | Report said alternative materials or gauges "forced a full manual redo". Source says customers asking for other materials or gauges "would require an entire trigger of changes in the quote". | Reworded with the source phrase. |
| 4 | 6.3 table, Evident | "1,800 pieces of tubing scrapped". Source says 1800 pieces were cut and machined and the material is "unusable"; it never says scrapped. | Reworded. |
| 5 | 6.3 table, USACE RFQ | "proof paperwork". The RFQ text asks for unit pricing, a delivery date estimate, shipping included in price, and SAM registration with FAR and DFARS reps and certs. It does not ask for mill test reports. | Reworded. |
| 6 | 6.3, Paperless Parts | Survey is the 2020 Part Buyer Survey; report gave no year. | Added "2020". |
| 7 | 6.5, aluminum "24.2% thin" | True only at 10 gauge (script output). The table shown covers 14 to 18 gauge, where the range is 14.2% to 15.7%. | Added "(at 10 gauge)" and "about" for stainless. |
| 8 | 6.5, Iowa RFQ | "Stainless Tubing 1 x 1 x .05" and ".065 wall" are in the 2021 Iowa RFQ (DB22245005), not the 2018 RFQ the link pointed to. "A513-A500" (hyphen) and the 49 lines are in the 2018 RFQ. | Split into two sentences with two links; added the 2021 link to Citations; "49 lines" now says "2018 Iowa RFQ". |
| 9 | 6.7, SaaSworthy | Reviewer says the "estimated cycle time feature ... is a little off at times", not the estimate in general. | Reworded. |
| 10 | 6.7 table, Cassidy | Live URL returns 404. Archive copy (2026-04-18) has the confidence-scoring text. | Re-pointed both links to the archive copy. |
| 11 | 6.7 table, DigiFabster | Report said a "buyer message center". Article says "introducing a Message Center to centralize communication" and does not say who uses it. | Removed "buyer". |
| 12 | 6.9 table | "A buyer asks to name 'the exact missing field'". The quote is from a commenter in the buyer-side thread (r/procurement, p6trxiv) giving advice. Exact words verified. | Reworded to "A buyer-side commenter says to ask for". |

The same wording errors were corrected in the appendices where they appeared (research_voice_open_web.md, research_voice_other_sources.md, research_tools_and_prices.md). The built .html files were not regenerated and still carry the old wording.

## Verified: Reddit quotes (main report)

| Line | Quote (start) | Comment id | Result |
|---|---|---|---|
| 70 | "hasn't accounted for X, Y or Z" | p4z7xpx, 1vtls2e | Verified |
| 78, 95 | "sometimes 10+ hours a week" | post 1jwtpla (OP, supplier side) | Verified |
| 92 | "a $250k job that ended up costing close to $450k" | p4w0ody, 1vtls2e (316 spec, 304 bought) | Verified |
| 93 | "within 24hours"; post score 222 | post 1s81l5g | Verified (score 222 in thread file; the search listing file shows 225) |
| 94 | "technically answer the RFQ but don't answer it on the same basis" | p6t572u, 1w1lwdg | Verified |
| 114 | "Early in my career I missed a note calling out weld size" | p4u79mi | Verified |
| 114 | "Missed the part where it said the welds are to be purged" | p4u4jeg | Verified |
| 114 | "wasn't getting updated like I thought it was" | p4ulybm | Verified |
| 29 | $15-20k profit shrank to $2-3k, stale material price | p4ulybm ("at best, $2-3k", "easy $15-20k in profit") | Verified |
| 140 | "Those certs are what you're paying for"; score 107 | ldllyym, 1e5ga3t (top-scoring comment in thread) | Verified |
| 146 | "DFARS Compliant 60 series aluminum. Also has to be made in the USA" | title of 15kudev | Verified |
| 146 | commenter says aluminum is exempt from DFARS | jv7co7a | Verified |
| 165 | "As anything with AI it is highly risky and hit-and-miss, as all models hallucinate AF you still have to check manually so there is no point" | o1rvvaq, 1qn5ad5 | Verified |
| 187 | "the exact missing field" | p6trxiv, 1w1lwdg | Verified (see fix 12) |
| 114 | "13 commenters" in the fab-quote thread | voc_records.jsonl: 13 distinct authors | Verified |

## Verified: other quotes and numbers (main report)

| Claim | Source | Result |
|---|---|---|
| Estimator duties quotes ("Review customer requests, emails, prints, and specifications", "Identify special requirements such as testing, inspection, tolerances, or origin restrictions", "Document assumptions, lead times, and any changes clearly on the quote so the customer is never surprised", "Run a final review of every quote"); Toledo | Precision Steel posting (Workable) | Verified (partial-sentence quotes) |
| "Always ask questions, never guess when something is unclear"; "conflicting cert requirements"; Detroit aluminum | Nox Metals posting (Chrome; posting is now closed but text displays) | Verified |
| Ryerson quote request every 4.5 minutes; "often required multiple clarifying communications" | Concurrency page | Verified |
| Brunswick Steel "limited to a select few" | SecturaFAB | Verified |
| Utah Steel about two days, three people | SecturaFAB | Verified |
| "had to lean on senior folks just to figure out substitutes or where to look"; "tens of thousands of times—and still made mistakes" (Inside Sales Manager) | Canals case study | Verified |
| 67% of buyers expect a quote in under 24 hours | Paperless Parts blog | Verified (2020 survey) |
| 50% of buyers choose the vendor that responds first (consultant, unnamed providers) | Distribution Strategy Group | Verified |
| CloudForge customer: win rate up "over 50 percent" | Modern Metals | Verified |
| Evident: 303 instead of 304, 1800 pieces cut and machined | Evident | Verified (see fix 4) |
| USAF RFQ line "STAINLESS Steel 2B T-304 - 16 Gage x 4 x 8 or similar", FA302024Q0014 | BidNet | Verified |
| Iowa 2018: "Square Tube A513-A500 Grade B", 49 lines, no certification or origin wording | Iowa PDF (pdftotext) | Verified |
| Iowa 2021: "Stainless Tubing 1 x 1 x .05" over ".065 wall thickness" | Iowa PDF 2021 | Verified |
| Navy HY-80 RFQ N4215826QE068: traceability, MTRs, DFARS 252.225-7009 | HigherGov | Verified |
| Stainless is a specialty metal because of chromium | DFARS 252.225-7009 text | Verified (chromium listed in the alloying-element threshold) |
| Gauge table, 12 values (mild, galvanized, stainless, aluminum at 14, 16, 18) | Metal Supermarkets chart | Verified |
| 16 gauge tube wall 0.065 in | Wikipedia Sheet metal | Verified |
| 4.2%, 4.5%, 24.2% | `domain_rules_gauge_calc.py`, re-run | Verified |
| Challenge text: "304 SS sheet 16ga 4x8", "Stainless 304, 0.060 in, 48 x 96", "the same item"; deadline 4:30pm EDT Oct 10; four criteria out of 5 | Devpost page | Verified |
| Proton "your customers' nicknames" | Proton page | Verified |
| Avent, Hexa, Mercura quote-drafting claims | YC launch pages | Verified |
| Cassidy confidence scores, no source linking | Archive copy | Verified (page is pump and flow equipment specific) |
| DigiFabster Message Center planned | 3dprintingindustry | Verified (see fix 11) |
| FRED WPU1017, WPU102501, PNICKUSDM exist and are what the report says | FRED pages | Verified. The saved page text for nickel does not name the IMF. |
| North American Stainless posts a monthly fuel surcharge | NAS news | Verified (Oct 1, 2026 fuel surcharge 58%) |
| SaaSworthy quotes "identifying features of a part that we might overlook", "a little off at times" | G2 reviews on SaaSworthy | Verified (see fix 9) |
| 25 search pages, 15 threads; 25 test lines; 19 verbatim Reddit lines | coverage_manifest.md; research_domain_rules.md (T1 to T25); research_voice_reddit.md RQ2 table (19 rows) | Verified |

## Appendix named-person quotes (checked)

Verified verbatim against fetched pages: Jaden Seely ("Speed is everything in the sales world", "guesstimating to exacting", Utah Steel); Ben Marans (three quotes), Chris Krebs, Phil Henry (Modern Metals); Travis Bryant case-study quotes, Puget Sound page text (Canals); Precision Steel success list and "This is not just math..." sentence; Avent "in inboxes or people's heads"; Proton "learns your catalog..." line; Paul Parsons and Shawne O'Connor (Metal Center News, Feb 27, 2026); Neeman (Practical Machinist, Dec 21, 2020; the appendix quote starts mid-sentence, after "I'm acquiring a company late Feb and"); Metal Supermarkets "neither standard nor metric", "has not been processed further", "fine parallel lines".

## Unverifiable / not rechecked

| Item | Reason |
|---|---|
| "No vendor mentions MTRs, DFARS, Buy America, or implied certs" (6.7 table) | An absence claim across vendor pages; not testable by a source check. The report already says "open means not claimed publicly". |
| Rest of appendix citations (job boards, employee reviews, HN, other vendor pages, ASTM and certification pages) | Out of scope for the time available. Not checked. |

## Notes for the orchestrator

- No claims were deleted.
- Stray line in the report: line 49 is the single word "Claude" between section 5 and section 6. Left in place; it looks like a signature.
- The nickel row says the IMF series; FRED labels it "Global price of Nickel" and the saved page text did not show the IMF credit.
- Chrome: two tabs opened by source-checker agents (ids 530229101 for Nox, 530229104 for Metal Center News) could not be closed because the agents had no close-tab tool. Close them by hand.

## Fetch method summary

| Method | Count | Notes |
|---|---|---|
| Script against saved Reddit payloads | all Reddit quotes | No reddit.com access |
| curl | about 25 pages | Static pages, Iowa PDFs, Concurrency, Canals, YC, USACE, USAF |
| Playwright | SaaSworthy, FRED (3), NAS | JS-rendered or 403 to curl |
| Chrome | Nox | Cloudflare block |
| Archive.org | Cassidy | Live page 404 |
