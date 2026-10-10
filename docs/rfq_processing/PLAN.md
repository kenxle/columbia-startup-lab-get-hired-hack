# RFQ Processing: Yuval's Plan and Log

**Owner:** Yuval (`@Yuval`). This is the working document for the RFQ processing domain. It holds the plan, the decisions, the status log, and the open questions for this lane. The contract with the app lives in [RESULT-FORMAT.md](RESULT-FORMAT.md). Data sources and their limits live in [DATA.md](DATA.md).

**Read with:** [the product brief](../product/PRD.md), [the frontend contract](../engineering/FRONTEND_CONTRACT.md), [Tisch's catalog and pricing scope](../data/CATALOG_PRICING.md), and [the bulletin board](../BULLETIN.md).

## Scope

Hirsh's split, agreed 2026-10-10. Yuval builds the part that understands the RFQ:

1. Turn PDFs, spreadsheets, and email text into readable text.
2. Use the LLM to identify material, grade, size, quantity, and requirements.
3. Match each line to items in the supplier catalog.
4. Return the source text for every answer.
5. Flag unclear lines and draft questions instead of guessing.
6. Find catalog and benchmark data, and explain what the benchmarks actually support.

Not in this lane: the Rails app, persistence, screens, the rep's edits, price math, totals, export (Hirsh). Catalog rows and price observations (Tisch, consumed here). Product scope and the demo (Ken).

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

Rules compute normalization, readiness, matching checks and questions. Optional Claude refinement fills evidence-backed blanks and records disagreements; the app currently disables it.

1. **Extract.** Email text passes through. PDFs go through `tools/pdf_text`. Spreadsheets become one text line per row. Page and row positions are kept for evidence.
2. **Parse.** Rules read each extracted item. Optional Claude Opus 5 refinement runs per item through Nicrron or Anthropic. Every accepted field needs exact source words and valid confidence; rules values remain authoritative.
3. **Normalize.** Rules: gauge to inches by material (gauge tables differ by material), feet to inches, "4x8" to 48 by 96, aliases such as SS to stainless, AN part number parsing (family, dash number, A and H designations).
4. **Readiness.** Rules: required fields present for the form, confidence above threshold, no conflicts such as a gauge that disagrees with a stated decimal. A score alone never makes a line Ready when required evidence is missing.
5. **Match.** Hard filters first (material, grade, form, or the exact part number for hardware), then a score on dimensions and standard. Below the threshold the line is No match. The nearest item is never forced.
6. **Compliance.** A rules table from Ken's domain research: explicit mentions (MTR, certs, domestic, DFARS) and requirements implied by a standard. Each flag carries its source words. Unknowns stay unknown.
7. **Clarify.** Rules decide a line is unclear and build its question and choices. Catalog alternates carry labeled prices only when comparable evidence exists.
8. **Result.** One hash per line in the agreed shape.

## Data

- **Catalog:** Tisch's `data/aviation/catalog.json`, 200 cadmium-plated AN bolt part numbers across AN3, AN4, AN5, AN7, and AN8, each with aliases, synthetic RFQ examples, compliance gaps, and two dealer price observations. Labeled sample data. Not confirmed RudCo stock.
- **Benchmarks:** Tisch's `price_observations.json`, two public dealer listings per item, product-only, single-piece basis. These support a two-dealer reference for the same part number. They do not support a delivered price, a bulk tier, or a market index. The benchmark hash on each line says so.
- **Metals test set:** Ken's [domain rules research](../research/20261010.01_rfq_sharper_angle/research_domain_rules.md), section 6, 25 labeled lines with expected readings and questions. No metals catalog exists yet, so metal lines land as No match unless Tisch adds metal items.

## Timeline for 2026-10-10

| When | What |
|---|---|
| By 12:55 | Step 0 done: clone, toolchain, this doc. Step 1: result format and three fixtures, bulletin post to Hirsh, Elad, Ken. |
| 12:55 to 2:00 | Normalizer, readiness rules, parser with recorded fixtures. Specs from Tisch's synthetic RFQ examples and Ken's verbatim lines. |
| 2:00 to 2:45 | Compliance table. Wire in Tisch's matcher through the agreed contract, with a stub until it lands. |
| 2:45 to 3:15 | Clarifier with catalog-grounded choices, benchmark hash per line with honest limits. Check that Ken's sample RFQ email parses. |
| 3:15 to 3:45 | Integration with the app, three fixtures end to end, freeze. |
| 3:45 to 4:30 | Keep `main` green. Ken records the video. |

## Working rules for this lane

- Yuval now authorizes code pushes after teammate inspection, without another personal review. Bulletin coordination updates are authorized for immediate push.
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

- **Demo email is Tisch's** (Ken, 13:32). This lane checks every line parses when it lands in `docs/product/demo_rfq/`. The proposal in `spec/fixtures/demo_rfq_email.txt` stays as a spec.
- **Claude Opus 5 through Nicrron** (Hirsh, 13:39 and 13:40; Ken, 13:36). The hackathon's sponsor gateway is OpenAI-compatible chat at `https://api.nicrron.ai/v1`, model `anthropic/claude-opus-5`; the direct Anthropic model is `claude-opus-5`. Processing owns the provider adapter (Yuval's lane is LLM integration). `LlmParser` gets an OpenAI-compatible client with no new gem, prefers Nicrron when its key exists, and drops any answer from a model other than the one requested. The hash records the provider and model in `revision.llm`.
- **Production data wording** (Ken, 13:31): `sample_data` defaults to false, price sources name the observation and date, benchmark `kind` is `list_price` or `dealer_midpoint`, stocked rows carry the 24 to 48 hour lead time.

## Current open items (2026-10-10, 14:45)

1. Hirsh/Tisch inspect the published review diff before runtime changes are pushed. Yuval approved the first parser batch and authorized teammate review for subsequent pushes.
2. Tisch repairs the committed demo PDF. The current bytes fail PDF::Reader validation. Email and CSV produce eight items; two lane specs remain red because the PDF is malformed.
3. Tisch supplies a matcher contract for vetted buyer terms. Normalized taught thickness is correct, but the matcher reparses the original decimal and ignores the plain given value. Keep Hirsh's `client: nil` intake restriction.
4. Ken/Tisch settle the final screw example: it omits material, so processing correctly holds it instead of showing the desired No match badge. Metals without sourced prices remain held.
5. Nicrron/Anthropic keys are absent. Stub smoke passes with pinned Ruby. A live call still requires Yuval's go. Required Opus 5 independent review is blocked by Claude quota until 16:50 ET; Astra reviews are supplemental.
6. Ken's shorthand worklist is now the parser priority. Glass bead size, stainless shot and Gage dimensions have local regression fixes. Ambiguous short descriptions must use their full source, not invented units.
7. Ken's Jev request is acknowledged. Yuval owns doubtful-compliance diagnostics after the demo correction batch, with all flags retained. Client/key and calibration fixtures are pending. Hirsh owns question routing and explicit answer-scope review; typed choice evidence needs a shared contract.

## Status log

| Date | Time | Entry |
|---|---|---|
| 2026-10-10 | 14:45 | Local review batch: provider model/evidence guards, priced alternates, candidate selection guards, taught-source provenance, bounded PDF item extraction, packaging versus demand, scoped body compliance preserved on answers, and three priority shorthand fixes. 395 Rails tests / 3240 assertions and 12 PDF utility specs pass. Matcher and answer e2e ACCEPTED; 281 lane specs have two failures caused by the malformed upstream demo PDF. Code not pushed. Board requests through 14:40 answered and pushed. |
| 2026-10-10 | 13:53 | New session picked up the lane at 77b9980. Gates green before any change: 150 lane specs, Rails check, e2e through Tisch's matcher (6 lines accepted). Hirsh's intake landed on main (`QuoteWorkspace::ProcessRfq`, `ApplyResult` now keeps `line_id`, `processing`, `revision`). Model switched to Claude Opus 5 by Hirsh. Two workers running: Nicrron provider in `LlmParser`, and `bin/e2e-answers.rb` plus `revision.llm`. Board watcher `bin/watch-board` fetches every 5 minutes and never pulls. Nicrron key not yet in this checkout. |
| 2026-10-10 | 13:40 | Steps 2 to 4 done. Workers delivered `answers.rb` (W3: a buyer answer reruns only the answered lines, whole-RFQ answers rerun all), `llm_parser.rb` (Claude Opus 5.5 through the anthropic gem, structured output, auto-on when a key exists, rules win on numbers), and `TEST-RESULTS.md` (24 of 25 research lines read as expected). Excel intake through roo. Adapter now calls Tisch's `CatalogMatch::Contract` directly. Ken's production-data decision applied: no sample labels, benchmark kinds `list_price` and `dealer_midpoint`, lead time 24 to 48 hours for stocked rows else "to confirm" in `processing.lead_time`. 150 specs green. HANDOFF.md written for the next session. |
| 2026-10-10 | 13:30 | Step 2 and most of step 3 done. Library on main: rules parser with per-material gauge tables, readiness rule, compliance flags (now with COA, REACH, RoHS), extractor, fallback catalog matcher, Tisch matcher adapter, buyer profiles, pipeline. 102 specs green, including all 25 lines of Ken's test set. A six-line sample email ran end to end into `ApplyResult` and was accepted. |
| 2026-10-10 | 12:55 | Step 1 done. RESULT-FORMAT.md written against Hirsh's `ApplyResult` code, not only his doc. Three fixtures pass his validator in the test environment (rollback, nothing stored); the Ready fixture is quotable. Found and recorded: the app drops hardware spec keys and the `processing` key today, and requires a question on No match lines. Bulletin posted to Tisch, Hirsh, Ken. |
| 2026-10-10 | 12:40 | Step 0 done. `script/setup` and `script/check` pass (Rails app boots, 12 PDF specs green). Hirsh's Rails app lives at the repo root; this lane stays under `tools/rfq_processing/`. Mac note: native gems only build with `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk`, because the default 27.0 SDK is unreadable by the installed linker. Ruflo initialized for Yuval's machine only; its files are in the local git exclude and no shared file changed. |
| 2026-10-10 | 12:30 | Step 0 started: cloned, owner file set, Ruby 3.4.11, Bundler 2.4.19, Rails 8.1.4 installed. Read the product brief, frontend contract, engineering review, Tisch's catalog, and Ken's domain research. Plan written. |
