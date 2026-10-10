# Existing Tools and Price Benchmarks

**Track:** existing tools (question 5) and price benchmarks (question 6) from the [research brief](brief_rfq_sharper_angle.md).
**Written:** 2026-10-10. Every vendor number below is a vendor claim unless a third party is named.

## Needs action and bottom line

- **Two of the four angles look open; one is partly taken.** Across about 15 tools, no vendor page I could read says it shows where each field came from in the buyer's words, sends the buyer a clarifying question, or flags certifications the spec implies. One vendor says it learns customer nicknames.
- **"Learns the buyer's shorthand" is the most contested angle.** [Proton.ai](https://www.proton.ai/order-and-quote-automation) says its system "learns your catalog, your customers' nicknames, and your reps' editing patterns over time." That is a claim on a general distribution tool, not a metals tool, and I found no user evidence either way.
- **"Catches hidden requirements" looks the emptiest.** No tool I read mentions mill test reports, DFARS, Buy America, or spec-implied certifications. The security and compliance badges on vendor pages (SOC 2, ITAR hosting, CMMC) describe the vendor's own software, not the buyer's requirements.
- **"Shows its work" and "one-click buyer questions" are open on the pages I read, but thinly.** A blog post describes the pattern ([Stacksync](https://www.stacksync.com/blog/metal-fabrication-genie-rfq-drawing-intake)), and one vendor lists a Message Center to centralize communication as a planned update ([DigiFabster](https://3dprintingindustry.com/news/digifabsters-new-ai-powered-quote-agent-for-smooth-rfqs-processing-234831/)). Neither ships it as far as the pages say.
- **Big caveat.** I read marketing pages, YC launch posts, and trade press. A feature missing from a page may still exist in the product. No tool was tested. Treat "open" as "not claimed publicly," not "does not exist."
- **For the price explanation, claim less than "cheapest."** Public sources give the metal's market cost, not competitors' delivered prices. The honest sentence is "this price tracks the published base-metal cost plus RudCo's margin." See [Part B](#part-b-public-price-sources).

---

## Part A: Existing tools

### What I searched

- AI RFQ and quote automation for metals service centers, distributors, and fabricators (about 14 searches).
- YC and venture-backed companies in industrial distribution quoting.
- Metals ERP vendors (service center software).
- User complaints, on G2, Capterra, and trade press.
- Per-field source tracing in RFQ tools.
- Reddit was not searched or fetched, per the rules.

### The comparison table

Legend: **Yes (claim)** means the vendor says it. **Not stated** means I read the page and found nothing. **Planned** means the vendor says it is coming.

| Tool | What it does | Who it serves | Field-level provenance | Asks the buyer clarifying questions | Learns per-customer shorthand | Flags compliance or cert needs |
|---|---|---|---|---|---|---|
| [Avent](https://www.ycombinator.com/launches/OC1-avent-ai-agents-for-industrial-commerce) (YC S25) | Watches email, fax, and phone; builds quotes from past pricing; matches POs to quotes; writes into the ERP | Industrial distributors and manufacturers, North America and UK | Not stated | Not stated | Partly: builds quotes from "past pricing and tribal knowledge" (claim) | Not stated |
| [Hexa](https://www.ycombinator.com/launches/Qfd-hexa-autonomous-operations-for-industrial-distributors) (YC, 2026) | Reads RFQs by email, PDF, Excel, fax; matches SKUs and pricing; drafts quotes for rep approval | Mid-market industrial distributors with legacy ERPs | Not stated | Not stated | Not stated | Not stated |
| [Mercura](https://www.ycombinator.com/launches/Mun-mercura-quotes-in-minutes-not-days) (YC W25) | Extracts product details from RFQs and specs; matches to the catalog using the customer's sales history; enters the quote in the ERP | HVAC, electrical, and plumbing distributors (per its YC page); tender and BOQ work per [a profile](https://www.extruct.ai/hub/mercura-ai/) | Not stated | Not stated | Partly: matching uses sales history (claim) | Not stated |
| [Proton.ai](https://www.proton.ai/order-and-quote-automation) | Turns email, PDF, Excel, handwritten notes, and competitor part numbers into draft quotes or orders; rep approves | Wholesale distributors | Not shown; says it flags low-confidence matches and missing fields | Flags missing info for the rep; does not say it asks the customer | **Yes (claim):** learns "your customers' nicknames" | Not stated; lists SOC 2 for itself |
| [CloudForge](https://www.businesswire.com/news/home/20260202589324/en/CloudForge-Secures-%243.95-Million-to-Bring-AI-to-the-Metals-Supply-Chain) | AI sales and procurement platform for metals: outbound sales, CRM, vendor management. Funded $3.95M, Feb 2026 per a [coverage summary](https://pulse2.com/cloudforge-3-95-million-funding/) | Metal service centers, fabricators, machine shops | Not stated | Not stated | Not stated | Not stated |
| [Nox Metals](https://operatorcollective.com/blog-posts/the-metal-shop-that-thinks-like-a-software-company-meet-nox-metals) | A metal service center that built its own instant online quoting and "AI-parsed material lists" (an investor's write-up) | Its own customers | Not stated | Not stated | Not stated | Not stated |
| [Metal Networks.AI (JAQi)](https://pitchbook.com/profiles/company/58352-59) | Paste email inquiry text; the engine "deciphers" it and searches a catalog or inventory | Metals buyers and distributors; company status is unclear (sources conflict) | Not stated | Not stated | Not stated | Not stated |
| [Frankstahl RFQ processor](https://docs.wonderful.cx/agents-hub/manufacturing/frankstahl-rfq-processor) (Wonderful) | German steel seller's agent: parses free-form RFQ emails, classifies lines into about 350 product types, configures variants, posts a priced quote to the CRM. Prefers rules to the model "wherever possible" (per a [search summary of the docs](https://docs.wonderful.cx/agents-hub/manufacturing/frankstahl-rfq-processor); the page needs a login) | One steel seller | Not stated | Not stated | Not stated | Not stated |
| [Invera INVEX "Ivy"](https://aithority.com/robots/automation/invex-ai-introducing-ivy-the-intelligence-layer-for-metal-erp/) | June 2026 AI layer on a metals ERP: help, natural-language questions on ERP data, "agents" | Metal service centers on INVEX | Not stated | Not stated | Not stated | Not stated |
| [Paperless Parts](https://www.paperlessparts.com/processes/metal-service-providers/) | Quoting and estimating; added an AI step that reads forwarded RFQ emails and builds line items ([The Fabricator, via search](https://blog.thefabricator.com/thefabricator/product/cadcamsoftware/software-cuts-quote-setup-time-with-ai-supported-workflow)) | Job shops, fabricators, and some metal service providers | Not stated | Not stated | Not stated | Not stated; "Security and Compliance" is about the vendor |
| [DigiFabster AI Quote Agent](https://3dprintingindustry.com/news/digifabsters-new-ai-powered-quote-agent-for-smooth-rfqs-processing-234831/) | Reads RFQ inbox, drafts a quote for review. Beta as of Dec 2024 | Machine shops and metal fabricators | Not stated | **Planned:** a "Message Center" | Not stated | Not stated; ITAR hosting is about the vendor |
| [SpeedQuoteAI](https://www.capterra.com/p/10049486/SpeedQuoteAI/) | Email monitoring, auto quote "in under 2 minutes" (claim) | CNC and sheet metal fabricators | Not stated | Not stated | Not stated | Not stated |
| [AIQuote](https://aeroxplorer.com/articles/one-company-sold-350000-more-in-90-days-by-automating-their-quotes-with-aiquote) (LogisticsMRO) | Parses RFQs, checks inventory, prices, auto-sends above a confidence threshold, else routes to sales | Aviation parts distributors | Not stated | Not stated | Not stated | Not addressed in the article |
| [Cassidy RFQ agents](https://www.cassidyai.com/solutions/ai-rfq-data-extraction-agent) | Extracts fields from emailed PDFs, BOMs, and Excel; confidence scores for human review | Electronics and pump makers (templates) | Confidence scores only; no source links stated | Not stated | Not stated | Not stated |
| Metals ERPs: [4GL Steel Manager III](https://www.oc-innovation.ca/vendors/4gl-solutions/), [Crowe Metals ERP](https://www.crowe.com/services/consulting/metals/erp/accelerator/metals-erp-solution-for-metal-service-centers), [INVEX](https://www.cbinsights.com/compare/invex-1-vs-metalogic-3), Metalogic | Inventory, quoting, and order modules for service centers. Quoting is a screen in the ERP; RFQ email intake is not described | Metal service centers | Not stated | Not stated | Not stated | Not stated |

### What the table says

- **The basic job is already being sold to general distributors.** Avent, Hexa, Mercura, and Proton all say they turn messy RFQs into draft quotes with a rep approving. The RFQ-to-draft-quote loop is not an unclaimed idea. Our demo cannot win on "AI reads the RFQ and drafts a quote."
- **Almost nobody is metals-specific at the line level.** The metals-named players (CloudForge, Nox, Invera, Metal Networks.AI) do sales, online ordering, ERP help, or catalog search. Frankstahl is the closest to our case, and it is one German seller. I found no public product that handles gauge, grade, and ASTM reading for a US metals supplier.
- **Provenance is rarely named as a feature.** The nearest items are confidence scores ([Cassidy](https://www.cassidyai.com/solutions/ai-rfq-data-extraction-agent)), a note that a low-confidence match gets flagged ([Proton](https://www.proton.ai/order-and-quote-automation)), and a design pattern in a blog post that keeps "source references" so each extracted detail traces to its document ([Stacksync](https://www.stacksync.com/blog/metal-fabrication-genie-rfq-drawing-intake)). A [Softomate FAQ](https://www.softomatesolutions.com/ai-rfq-quotation-automation/) says it shows candidate matches next to the source description when a request is unclear. I found no vendor that links each field to the highlighted words in the RFQ.
- **Buyer-facing questions are unclaimed.** Proton and the Stacksync pattern send open questions to an internal reviewer. DigiFabster lists a Message Center (to centralize communication; the article does not say who uses it) as planned. None says it drafts a multiple-choice question to the buyer.
- **Trust is a stated worry in the sources.** A Forgepoint listing's critics flag that wrong AI quotes cause margin leakage and disputes (per a [search summary](https://simplify.jobs/c/Forgepoint)). An [Infosys BPM piece](https://www.infosysbpm.com/blogs/sales-commercials/ai-cpq-for-faster-quotes.html) argues quoting flows without human review create accountability gaps and compliance exposure. The [DreamzTech case study](https://www.dreamztech.com/ai-procurement-agent-vendor-quotation-intelligence-case-study/) notes that grade, thickness, unit of measure, and delivery location change the right answer.

### Vendor claims, kept separate

All of these are claims. None is independently verified.

- Avent: "over $200,000 worth of quotes every day" ([YC launch](https://www.ycombinator.com/launches/OC1-avent-ai-agents-for-industrial-commerce)); 50% less admin work, per the founder in [HRAI](https://www.hrai.ca/newsletter/ai-in-distribution--an-example-from-the-field-).
- Hexa: revenue growth "over 10%," response "from hours to minutes," "live in days" ([YC launch](https://www.ycombinator.com/launches/Qfd-hexa-autonomous-operations-for-industrial-distributors)). A [YC tier-list review](https://yctierlist.com/s26/hexa/) found no screenshots, demo, or named customers.
- Proton: quotes from "15 minutes to under 60 seconds," "85% first-time match rate on cross-referenced parts" ([Proton](https://www.proton.ai/order-and-quote-automation)).
- Mercura: "process RFQs in minutes instead of days" ([YC launch](https://www.ycombinator.com/launches/Mun-mercura-quotes-in-minutes-not-days)); 60+ customers and a $2.1M seed come from [secondary profiles](https://yespress.io/mercura-yc-w25).
- AIQuote: one unnamed distributor gained "over $630,000" in four months; the article's URL says $350,000 ([article](https://aeroxplorer.com/articles/one-company-sold-350000-more-in-90-days-by-automating-their-quotes-with-aiquote)).
- Paperless Parts: a customer testimonial says quoting time cut by 80% ([Paperless Parts](https://www.paperlessparts.com/processes/metal-service-providers/)).

### User complaints and gaps

- **Avent has no third-party reviews.** Its [G2 profile](https://www.g2.com/sellers/avent) showed 0 reviews in a search summary.
- **Hexa has no independent user reviews** that I could find ([search](https://www.ycombinator.com/companies/hexa)).
- **Paperless Parts reviews are about the quote builder, not the AI.** G2 and Capterra complaints include slow lookup, limited data access for sales analysis, and a quote builder that expands one item at a time ([SaaSworthy summary](https://www.saasworthy.com/product/paperless-parts/reviews)). I found no review that tests AI extraction accuracy.
- **Metals ERP vendors: no user complaints found.** I searched for Capterra and G2 complaints on Steel Manager, INVEX, and Metalogic and got only company profiles.
- **Gap to state plainly:** I found no documented complaint that an AI quote tool misread shorthand or missed a cert. The pain evidence for those belongs to the voice-of-user tracks, not this one.

### What I could not confirm

- **Frankstahl's docs page needs a login.** I relied on a search summary of it.
- **Mercura's YC page names HVAC, electrical, and plumbing.** A profile site says it also does tenders. I treated the YC page as the primary source.
- **Metal Networks.AI's status is unclear.** [PitchBook](https://pitchbook.com/profiles/company/58352-59) lists it as acquired or merged, while [Craft](https://craft.co/metal-networks) lists it as active.
- **No tool was tested.** Several vendor sites returned 403 to my fetches (Proton's MDM write-up, G2 seller pages).

---

## Part B: Public price sources

This feeds Yuval's catalog and price work. Status checked 2026-10-10 where I could open the page.

### Summary table

| Source | Covers | Update frequency | Free and reachable? | How a quote explanation can cite it |
|---|---|---|---|---|
| [FRED / BLS PPI, steel mill products (WPU1017)](https://fred.stlouisfed.org/series/WPU1017) | US producer price index for steel mill products, 1982=100. Latest shown: 381.162 for August 2026 | Monthly; next release Oct 15, 2026 | Free, no login for the page. FRED asks for citation | "Steel mill product prices were at index 381.2 in Aug 2026 (BLS PPI via FRED)" |
| [FRED / BLS PPI, aluminum mill shapes (WPU102501)](https://fred.stlouisfed.org/series/WPU102501) | US producer price index for aluminum mill shapes. Latest shown: 370.902 for August 2026 | Monthly; next release Oct 15, 2026 | Free | Same pattern. There are finer series such as [aluminum sheet and strip](https://fred.stlouisfed.org/series/WPU10250105) |
| [IMF global nickel price on FRED (PNICKUSDM)](https://fred.stlouisfed.org/series/PNICKUSDM) | Monthly average nickel, USD per metric ton. Latest shown: 16,632.36 for July 2026 | Monthly, about 6 weeks lag | Free; IMF copyright, citation required | "Nickel averaged $16,632 per tonne in July 2026 (IMF via FRED)" for a stainless surcharge story |
| [IMF global aluminum price on FRED (PALUMUSDM)](https://fred.stlouisfed.org/series/PALUMUSDM) | Monthly average aluminum, USD per metric ton. Latest shown: 3,158.27 for July 2026 | Monthly | Free; citation required | Same pattern |
| [LME reports and data](https://www.lme.com/en/market-data/reports-and-data) | Official prices for aluminium, nickel, copper, zinc, and others | Daily, next-day delayed on the website | Free **with a registration** on LME.com, per a search summary of its pages; same-day data needs a [paid licence](https://www.lme.com/market-data/accessing-market-data/lmelive) (a delayed tier was listed at USD 210 a month) | "LME official nickel cash price on [date], next-day delayed." Check the LME terms before reusing numbers in a public demo |
| [CME Midwest HRC steel futures (CRU index)](https://www.cmegroup.com/markets/metals/ferrous/hrc-steel.html) | Cash-settled against the [CRU US Midwest hot-rolled coil index](https://www.cmegroup.com/content/dam/cmegroup/rulebook/COMEX/9/920.pdf) | Daily settlements | CME pages show quotes [delayed at least 10 minutes](https://cmegroup.com/markets/metals/ferrous/hrc-steel.calendar.html). A Fastmarkets help page says CME has a free 10-minute delay ([search summary](https://help.fastmarkets.com/introduction-to-exchange-data)). I could not open CME's pages to confirm | "Front-month HRC futures settled at $X on [date] (CME)." CME says web data is reference only |
| [CME Aluminum Midwest premium futures](https://www.cmegroup.com/education/brochures-and-handbooks/aluminum-mw-us-transaction-premium-platts-25mt-futures-aup) | The US Midwest premium on top of the LME aluminum price, settled on a Platts assessment | Daily | Contract page is free. The Platts assessment behind it is paid. Delayed-quote terms not confirmed | "Aluminum price = LME base plus Midwest premium of about X cents per lb" |
| [Nucor Consumer Spot Price](https://nucor.com/news-release/nucor-introduces-new-hot-rolled-coil-spot-pricing-122529) | Nucor's weekly hot-rolled coil spot price, issued Mondays since April 2024 | Weekly | I found no public nucor.com price page. Nucor says sheet price extras are in its NucorNow portal. Weekly values are reported by [SteelOrbis](https://www.steelorbis.com/steel-prices/steel-prices-market-analyses/flats-and-slab/nucor-consumer-spot-price-up-for-14th-week-on-scrap-steady-steel-demand-low-imports-1448920.htm) | "Nucor's posted HRC spot was $X per ton on [date]" if Yuval can find the live number |
| [North American Stainless news page](https://www.northamericanstainless.com/news) | Monthly fuel surcharge notice (58% for flat and long products effective Oct 1, 2026) and base price announcements | Monthly, posted near month end | Free, no login | Cite as a surcharge line on stainless quotes: "NAS fuel surcharge 58% for October 2026." This is a fuel surcharge. I found no alloy surcharge table on the public page |
| [Outokumpu alloy surcharges](https://www-sc10.outokumpu.com/en/surcharges) | Alloy surcharge by grade. The overview page says surcharges are "usually published month by month" and links an Americas page | Monthly | Overview is public. I could not open the Americas table, so I do not know if it is fully free | "Alloy surcharge for 304 is $X per lb for October (Outokumpu)" once Yuval confirms access |
| ATI flat rolled surcharge | Raw material surcharge announcements for stainless | Monthly | ATI posted [notices as PDFs](https://www.atimaterials.com/specialtyrolledproducts/Documents/price_announcements/ATI%20Flat%20Rolled%20Products%20Releases%20Surcharge%20Announcement%20October%2014%202016.pdf) in the past. I found no current-month notice | Same as Outokumpu if reachable |
| [MetalMiner Monthly Metals Index](https://agmetalminer.com/?p=1442) | Direction of price moves for carbon steel, stainless, aluminum, and others | Monthly | A search summary says free. I could not open this page (404), so confirm | "MetalMiner's Stainless MMI rose this month." Gives direction, not dollar prices |
| [USGS Mineral Commodity Summaries 2026](https://pubs.usgs.gov/periodicals/mcs2026/mcs2026.pdf) | Annual supply, trade, and price notes for iron and steel, nickel, aluminum | Yearly, February | Free | Context only. Too coarse for a quote line |
| [World Bank Pink Sheet](https://thedocs.worldbank.org/en/doc/5d903e848db1d1b83e0ec8f744e55570-0350012021/related/CMO-Pink-Sheet-January-2024.pdf) | Monthly commodity prices including nickel and iron ore. I did not confirm aluminum in the editions I saw | Monthly | Free PDFs. I did not find the current edition | Backup for nickel if FRED is down |
| Paid: [Fastmarkets](https://www.fastmarkets.com/metals-and-mining/steel-and-steel-raw-materials/steel-prices/), [CRU](https://crugroup.com/en/data/prices-and-indices/steel-prices), S&P Platts, [Steel Market Update](https://www.steelmarketupdate.com/tag/galvalume/page/66/) | The assessments most buyers and mills actually reference: steel, scrap, premiums | Daily to weekly | **Paid.** No public prices; "talk to us" sales pages | Name them as "the benchmark RudCo would license," not as data we show |

### How to use these in the demo

- **Best two for a free, live-looking demo:** FRED's BLS PPI series (steel mill products, aluminum mill shapes) and the IMF nickel and aluminum prices on FRED. They are free, open pages with named update dates, and they cite cleanly.
- **Best for stainless:** nickel drives the alloy surcharge, so the IMF nickel price plus a mill surcharge notice tells the story. NAS posts a public monthly notice, but it is a fuel surcharge, not the alloy surcharge. The alloy tables I found were third-party reports ([Argus](https://www.argusmedia.com/en/news/2003164-us-stainless-surcharges-nudge-lower), [Kallanish](https://production.kallanish.com/en/news/steel/market-reports/article-details/outokumpu-lifts-us-austenitic-alloy-surcharges-again-0919)).
- **What the sources cannot say.** A PPI is an index with a 1982 base. It tells the rep which way the market moved, not what a competitor would quote on 16 gauge 304 sheet. The IMF prices are monthly averages of the raw metal. So the explanation line should read as market context for RudCo's price, for example "Nickel is X% higher than a year ago, so the 316 surcharge line rises." It should not read as proof RudCo is cheaper. That keeps the trust story honest.
- **Mark sample data on screen.** If the RudCo catalog and price list are made up, say so, per the [product brief](../../product/PRD.md).

### Gaps in Part B

- **LME's exact free terms.** The sources differ: one says next-day delay, another shows 15-minute delayed intraday quotes on price pages. Registration is needed for history. I could not open lme.com directly (403).
- **CME quote access.** I could not open the CME pages (timeouts). The 10-minute free delay comes from a Fastmarkets help page, not CME.
- **Nucor's live CSP.** The most recent figure I saw was April 2026, from SteelOrbis. Yuval needs to confirm where the current weekly number is posted.
- **Mill alloy surcharge tables.** I could not read current NAS, Outokumpu Americas, or ATI tables. A search result mentioned Outokumpu's October 2026 North American surcharges, but I did not verify the figures against Outokumpu's own page.
- **No arithmetic.** I did not compute year-over-year changes. If the demo shows a percentage, run it through a script on the series data.

## Cleanup needed

None. I created only this file and deleted nothing.
