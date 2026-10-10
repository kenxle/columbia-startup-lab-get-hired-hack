# RFQ Processing: Yuval's Plan and Log

**Owner:** Yuval (`@Yuval`). This is the working document for the RFQ processing domain. It holds the plan, the decisions, the status log, and the open questions for this lane. The contract with the app lives in [RESULT-FORMAT.md](RESULT-FORMAT.md). Data sources and their limits live in [DATA.md](DATA.md).

**Read with:** [the product brief](../product/PRD.md), [the frontend contract](../engineering/FRONTEND_CONTRACT.md), [Elad's catalog and pricing scope](../data/CATALOG_PRICING.md), and [the bulletin board](../BULLETIN.md).

## Scope

Hirsh's split, agreed 2026-10-10. Yuval builds the part that understands the RFQ:

1. Turn PDFs, spreadsheets, and email text into readable text.
2. Use the LLM to identify material, grade, size, quantity, and requirements.
3. Match each line to items in the supplier catalog.
4. Return the source text for every answer.
5. Flag unclear lines and draft questions instead of guessing.
6. Find catalog and benchmark data, and explain what the benchmarks actually support.

Not in this lane: the Rails app, persistence, screens, the rep's edits, price math, totals, export (Hirsh). Catalog rows and price observations (Elad, consumed here). Product scope and the demo (Ken).

## Owned paths

| Path | Contents |
|---|---|
| `tools/rfq_processing/` | The library: `lib/`, `spec/`, `spec/fixtures/`, its own `Gemfile`. Same pattern as `tools/pdf_text/`. |
| `docs/rfq_processing/` | This plan, the result format, the data notes. |

The library is plain Ruby with no Rails dependency. The app loads it as a path gem and calls one entry point. Nothing here reads the database or sends anything to a buyer.

## The contract with the app

Hirsh's [frontend contract](../engineering/FRONTEND_CONTRACT.md) defines the integration point: `QuoteWorkspace::ApplyResult.call(quote:, result:)` takes a hash with `schema_version: 1`, `sample_data`, and `lines` in the `QuoteLine` shape. This lane produces exactly that hash. The full shape, plus the extensions this lane needs (match score and reason, confidence per field, candidate items), is in [RESULT-FORMAT.md](RESULT-FORMAT.md).

Three fixtures ship with the format so the app can be built against them before the parser exists: one Ready line, one Needs the buyer line, one No match line.

## How it works

Rules do everything that can be computed. The LLM only reads messy text into fields and words the buyer questions.

1. **Extract.** Email text passes through. PDFs go through `tools/pdf_text`. Spreadsheets become one text line per row. Page and row positions are kept for evidence.
2. **Parse.** One Claude call per RFQ (Claude Opus 5.5, structured output against the result schema). Every field returns a value, the exact source words, and a confidence.
3. **Normalize.** Rules: gauge to inches by material (gauge tables differ by material), feet to inches, "4x8" to 48 by 96, aliases such as SS to stainless, AN part number parsing (family, dash number, A and H designations).
4. **Readiness.** Rules: required fields present for the form, confidence above threshold, no conflicts such as a gauge that disagrees with a stated decimal. A score alone never makes a line Ready when required evidence is missing.
5. **Match.** Hard filters first (material, grade, form, or the exact part number for hardware), then a score on dimensions and standard. Below the threshold the line is No match. The nearest item is never forced.
6. **Compliance.** A rules table from Ken's domain research: explicit mentions (MTR, certs, domestic, DFARS) and requirements implied by a standard. Each flag carries its source words. Unknowns stay unknown.
7. **Clarify.** Rules decide a line is unclear. A second Claude call only words the question and offers two or three catalog-grounded choices.
8. **Result.** One hash per line in the agreed shape.

## Data

- **Catalog:** Elad's `data/aviation/catalog.json`, 200 cadmium-plated AN bolt part numbers across AN3, AN4, AN5, AN7, and AN8, each with aliases, synthetic RFQ examples, compliance gaps, and two dealer price observations. Labeled sample data. Not confirmed RudCo stock.
- **Benchmarks:** Elad's `price_observations.json`, two public dealer listings per item, product-only, single-piece basis. These support a two-dealer reference for the same part number. They do not support a delivered price, a bulk tier, or a market index. The benchmark hash on each line says so.
- **Metals test set:** Ken's [domain rules research](../research/20261010.01_rfq_sharper_angle/research_domain_rules.md), section 6, 25 labeled lines with expected readings and questions. No metals catalog exists yet, so metal lines land as No match unless Elad adds metal items.

## Timeline for 2026-10-10

| When | What |
|---|---|
| By 12:55 | Step 0 done: clone, toolchain, this doc. Step 1: result format and three fixtures, bulletin post to Hirsh, Elad, Ken. |
| 12:55 to 2:00 | Normalizer, readiness rules, parser with recorded fixtures. Specs from Elad's synthetic RFQ examples and Ken's verbatim lines. |
| 2:00 to 2:45 | Compliance table. Wire in Tisch's matcher through the agreed contract, with a stub until it lands. |
| 2:45 to 3:15 | Clarifier with catalog-grounded choices, benchmark hash per line with honest limits. Check that Ken's sample RFQ email parses. |
| 3:15 to 3:45 | Integration with the app, three fixtures end to end, freeze. |
| 3:45 to 4:30 | Keep `main` green. Ken records the video. |

## Working rules for this lane

- Nothing is pushed before Yuval has reviewed it.
- Pull and reread the bulletin board before every task, before every commit, and every ten minutes during long work.
- Post to the bulletin board at every handoff and at session end, with @-mentions.
- Commits use Yuval's git identity, no AI co-author trailers (team rule).
- Worker agents (ruflo on Yuval's machine only) get one task, acceptance criteria, owned paths, and a starting commit. They never pull, commit, or push. Their generated files stay out of the shared repo.

## Decisions

- **Tisch owns the matcher** (2026-10-10, 12:45). Tisch asked for it on the bulletin and Ken's [workflow](../product/WORKFLOW.md) lists step 4 under Tisch. Two conditions, recorded in [RESULT-FORMAT.md](RESULT-FORMAT.md): the matcher is callable from Ruby in-process or as a JSON command, and this lane stays the single assembler of the result hash for the app. Step 3 of this plan shrinks to wiring the matcher in and testing the handoff.
- **Pricing is Tisch's** (Ken's workflow, step 5). This lane supplies benchmark inputs and the honest explanation text, not the price math.

- **Buyer profiles, workflow step 9** (2026-10-10, 13:25, Yuval's call). Each buyer writes the same thing their own way ("20 gate steel", "20G steel"). The parsing side is this lane: `RfqProcessing.process(..., buyer_terms:)` applies the buyer's taught or learned terms before the rules and the evidence says so ("Northline (taught by the rep): 20G means gauge 20"). The store is Tisch's `Client` and `ClientTerm` tables. `BuyerProfile.learn` turns a rep edit into a term the app saves as learned.
- **Tisch's matcher, through an adapter** (13:25). Tisch's `CatalogMatch::Matcher` is a Rails service that takes text. `RfqProcessing::CatalogMatchAdapter` wraps it in the contract (0 to 1 scores, exact, scored, ambiguous, no_match), so this lane stays the single assembler. The library's own `CatalogMatcher` remains the fallback for plain JSON catalogs and specs.
- **Ken's brief update (13:00) is in:** COA, REACH, RoHS compliance flags; lb and bag units; steel shot, grit, bead, garnet, aluminum oxide, and aluminum ingot (P1020, 356, A356) vocabulary.

## Open questions

1. **@Ken @Tisch:** the demo catalog. Ken's workflow W4 recommends a metals demo RFQ with bolts as a second RFQ. Today's only catalog is 200 aviation bolts. A metals demo needs metal catalog items, or every metal line lands as No match. This lane parses both kinds either way, and the gauge example is a parser showcase even without a catalog.
2. **@Hirsh:** the `spec` hash is metals-shaped. Hardware lines add part_number, diameter, thread, grip, drilling. Can the review screen show extra spec keys as they come? Also, the `processing` key on each line: store it, or ignore it?
3. **@Hirsh:** who sets `unit_price` on a Ready line. Proposal: this lane copies Tisch's suggested price when one exists, with `price_source` naming the observations, and the rep edits it. Until Tisch's pricer exists, the fixtures use the two-dealer midpoint.
4. **@Ken:** re-quote on change (bulletin 12:42). Detection of a change request on a quote thread would sit in this lane after the core pipeline works. Not before 3:15.
5. An Anthropic API key for `.env`. Until one exists, specs run against recorded responses.

## Status log

| Date | Time | Entry |
|---|---|---|
| 2026-10-10 | 13:30 | Step 2 and most of step 3 done. Library on main: rules parser with per-material gauge tables, readiness rule, compliance flags (now with COA, REACH, RoHS), extractor, fallback catalog matcher, Tisch matcher adapter, buyer profiles, pipeline. 102 specs green, including all 25 lines of Ken's test set. A six-line sample email ran end to end into `ApplyResult` and was accepted. |
| 2026-10-10 | 12:55 | Step 1 done. RESULT-FORMAT.md written against Hirsh's `ApplyResult` code, not only his doc. Three fixtures pass his validator in the test environment (rollback, nothing stored); the Ready fixture is quotable. Found and recorded: the app drops hardware spec keys and the `processing` key today, and requires a question on No match lines. Bulletin posted to Tisch, Hirsh, Ken. |
| 2026-10-10 | 12:40 | Step 0 done. `script/setup` and `script/check` pass (Rails app boots, 12 PDF specs green). Hirsh's Rails app lives at the repo root; this lane stays under `tools/rfq_processing/`. Mac note: native gems only build with `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk`, because the default 27.0 SDK is unreadable by the installed linker. Ruflo initialized for Yuval's machine only; its files are in the local git exclude and no shared file changed. |
| 2026-10-10 | 12:30 | Step 0 started: cloned, owner file set, Ruby 3.4.11, Bundler 2.4.19, Rails 8.1.4 installed. Read the product brief, frontend contract, engineering review, Tisch's catalog, and Ken's domain research. Plan written. |
