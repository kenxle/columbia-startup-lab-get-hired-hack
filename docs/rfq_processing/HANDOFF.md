# Handoff: RFQ processing lane (Yuval)

**For:** the next Claude Code session working for Yuval, started in this repo with ruflo. Read this file first, then do the "First ten minutes" steps. Everything here was true at the time in the status log at the bottom. The repo and the bulletin board are the truth after that.

**Owner:** Yuval Gerber (`@Yuval`, GitHub `Yuval-Gerber`). The `.agent-owner` file in the repo root says `Yuval`. The git identity for this clone is set to Yuval Gerber.

## 1. What this project is

RudCo Quote Desk: an agent that turns a messy industrial RFQ (email, PDF, spreadsheet) into a quote a sales rep can check and send. Every field shows the words it came from. Unclear lines become one buyer question with choices. The hackathon ends at 4:30 PM ET on 2026-10-10 with a video demo. Read, in this order:

1. [AGENTS.md](../../AGENTS.md): the team rules. One coordinator owns git per checkout; workers never pull, commit, or push. Pull before every task and every commit, and every 5 to 10 minutes during long work. Reread [docs/BULLETIN.md](../BULLETIN.md) after every pull. No AI co-author trailers on commits. No em dashes in docs. Claude Opus 5.5 for Claude agents.
2. [docs/product/PRD.md](../product/PRD.md): the brief. Commitments: show the source, ask instead of guess, label sample data, no hallucinated pricing.
3. [docs/product/WORKFLOW.md](../product/WORKFLOW.md): the eight demo steps and the decisions (W1 to W4, the confidence gate, the four W3 guards).
4. [docs/ARCHITECTURE.md](../ARCHITECTURE.md): the four parts and the contracts. Yuval's section is "RFQ processing". Update it in the same commit as any contract or status change.
5. [PLAN.md](PLAN.md) (this lane's plan, decisions, log), [RESULT-FORMAT.md](RESULT-FORMAT.md) (the hash the app accepts, the matcher contract, the answers contract), [TEST-RESULTS.md](TEST-RESULTS.md) (what the parser gets right on the research test set).

## 2. Yuval's lane and the people

Yuval builds the part that understands the RFQ: extraction, parsing with evidence, normalization, matching through Tisch's matcher, compliance flags, buyer questions, buyer profiles (workflow step 9, parsing side), and the result hash. Not Yuval's: the Rails app, screens, persistence, price math, export (Hirsh); catalog data, the matcher, pricing (Tisch); scope, demo, video (Ken).

| Person | Handle | Owns | What they are waiting on from Yuval | What Yuval is waiting on from them |
|---|---|---|---|---|
| Ken St. Clair | `@Ken` | Product, docs, demo, video | Confirmation that the demo RFQ email parses | The demo RFQ email text (a proposal is in `tools/rfq_processing/spec/fixtures/demo_rfq_email.txt`) |
| Hirsh (Elad Hirsh) | `@Hirsh` | Rails app at the repo root, all pages, `QuoteWorkspace::*` | Nothing blocking; he took the Rails invocation and the `.env` tasks at 13:28 | The intake call into `RfqProcessing.process`, dotenv and gems in the root Gemfile, a "waiting for price" line state (his call) |
| Tisch (Elad Tisch) | `@Tisch` | `data/*`, `app/services/catalog_match/*`, `tools/catalog_research/*`, pricing | Nothing blocking; the adapter wraps his matcher as is | Add `gauge`, `thickness`, `quantity_unit` to `ClientTerm::TEACHABLE_FIELDS`; prices for metals rows |
| Everyone | | | | An Anthropic API key. Nobody had posted one. Hirsh asked Ken to name an owner (13:28). Credentials never go on the board. |

## 3. The library

`tools/rfq_processing/` is plain Ruby, no Rails. Own Gemfile. Entry point:

```ruby
RfqProcessing.process(content:, type: "email" | "pdf" | "spreadsheet", filename:, catalog: rows, matcher: nil, buyer_terms: [], context: {}, llm: nil)
```

Returns the schema-1 hash in [RESULT-FORMAT.md](RESULT-FORMAT.md). In the app, `matcher:` is `RfqProcessing::CatalogMatchAdapter.new(client:)`, which wraps Tisch's `CatalogMatch::Matcher`. The app applies the hash with `QuoteWorkspace::ApplyResult.call(quote:, result:)`.

| File under `lib/rfq_processing/` | Does |
|---|---|
| `rules_parser.rb` | One line in, a Reading out: fields, exact source words, confidence, assumptions, rules used, conflicts, unknowns. Applies answers (overrides) and buyer terms first. |
| `lexicon.rb`, `units.rb`, `gauge_table.rb` | Materials, grades, specs, forms, finishes, quantities (lb, bag, each), number and unit parsing, gauge tables by material and form. |
| `readiness.rb` | ready, needs_buyer, or no_match; one question per held line; choices with the field each settles. |
| `compliance.rb` | MTR, EN 10204 3.1 and 3.2, DFARS, Buy America, origin, ITAR, PMI, NACE, ASME SA, COA, REACH, RoHS. Each flag quotes its trigger. |
| `catalog_matcher.rb` | Fallback matcher for JSON catalogs (exact part number, family, metals scoring). |
| `catalog_match_adapter.rb` | Tisch's Rails matcher in, the contract hash out. |
| `buyer_profile.rb` | Workflow step 9: applies a buyer's taught or learned terms (ClientTerm shape); `learn` turns a rep edit into a term. |
| `extractor.rb` | Email text, PDF (through `tools/pdf_text`), CSV, Excel (roo). Page, row, and sheet positions are kept. |
| `result_builder.rb` | One line hash in the app's shape, with prices only from a labeled source (dealer midpoint, RudCo list price). Matched lines with no price are held with `unresolved_fields: ["unit_price"]`. |
| `pipeline.rb` | Extract, pick item lines, read body sentences for compliance, parse, match, decide, flag, assemble. `process_line` takes `overrides` and `extra_text`. |
| `answers.rb` | W3: a buyer answer reruns only the answered lines; `scope: rfq` reruns all. See RESULT-FORMAT.md. (Built by a worker; check it landed.) |
| `llm_parser.rb` | The Claude step (Opus 5.5 through the `anthropic` gem, structured output). Off without a key. (Built by a worker; check it landed and smoke test with a real key.) |

Specs: `spec/rfq_processing/*_spec.rb`. Fixtures: `spec/fixtures/test_set.yml` (Ken's 25 lines with expected readings), `spec/fixtures/results/*.json` (three result fixtures that pass `ApplyResult`), `spec/fixtures/demo_rfq_email.txt` (proposed demo email).

Helpers in `tools/rfq_processing/bin/`: `test-set-report` (regenerates TEST-RESULTS.md), `apply-fixtures.rb`, `e2e-apply-result.rb`, `e2e-tisch-matcher.rb` (run through `bin/rails runner` in the test env with a rollback), `merge-bulletin.py` (resolves a bulletin merge conflict by keeping every row, newest first).

## 4. Commands (copy exactly)

Every native gem build on this Mac needs the 26.5 SDK, because the default 27.0 SDK is unreadable by the installed linker:

```sh
export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
cd /Users/yuval/columbia-startup-lab-get-hired-hack
git pull --ff-only origin main
script/check                                   # Rails tests + PDF specs
cd tools/rfq_processing && BUNDLE_GEMFILE="$PWD/Gemfile" ../../script/with-ruby bundle _2.4.19_ exec rspec && cd ../..
RAILS_ENV=test BUNDLE_GEMFILE=Gemfile script/with-ruby bin/rails runner tools/rfq_processing/bin/e2e-tisch-matcher.rb
```

Commit and push (pull with rebase first; the bulletin conflicts often because everyone posts at once):

```sh
git add <explicit paths you own> && git commit -m "RFQ processing: <what>"
git pull --rebase origin main || (python3 -I tools/rfq_processing/bin/merge-bulletin.py docs/BULLETIN.md && git add docs/BULLETIN.md && GIT_EDITOR=true git rebase --continue)
git push origin main
```

Posting on the board: insert a row right under the header line `|------|------|---------------|---------|` in `docs/BULLETIN.md`, newest first, `| 2026-10-10 | HH:MM | Yuval | message with @-mentions and **OPEN:** items |`. Time from `date '+%H:%M'`. Post only delivered work and real asks, not "I am reading".

## 5. Working rules Yuval set

- Yuval reviews before anything is pushed unless Yuval has said "move on" for that kind of change. Yuval said: communicate on the board, ask teammates for what you need, answer their questions, and integrate their answers.
- Keep everything about this lane in `docs/rfq_processing/`.
- Ruflo is for Yuval's machine only. Its files (`.claude-flow/`, `.claude/settings.json`, `.claude/skills/`, `.mcp.json`) are in `.git/info/exclude`, never committed. It must not edit `CLAUDE.md`, `AGENTS.md`, or `.claude/agents/`, which belong to the team.
- Check the repo and the board regularly. Every pull is followed by reading the new rows.

## 6. How to divide the agents in ruflo

Start the session in the repo root. Claude Code will ask to enable the project MCP server `claude-flow` from `.mcp.json`; approve it. If the ruflo tools still do not appear, use Claude Code's own worker agents (the `Agent` tool) the same way; it is the same pattern. Either way:

| Agent | Profile | Owns (paths) | Never does |
|---|---|---|---|
| Coordinator (the main session) | you | git, the bulletin board, integration, `docs/rfq_processing/*`, the e2e runs against the app | delegate a push or a board post |
| parser worker | `rfq-implementer` | `lib/rfq_processing/{rules_parser,lexicon,units,gauge_table,readiness}.rb` and their specs | touch pipeline or result shape |
| integration worker | `rfq-implementer` | `lib/rfq_processing/{pipeline,result_builder,catalog_match_adapter,answers}.rb` and specs | change the hash shape without a RESULT-FORMAT.md edit by the coordinator |
| data and flags worker | `rfq-implementer` | `lib/rfq_processing/{compliance,buyer_profile,extractor}.rb` and specs | invent domain rules not in the research |
| llm worker | `rfq-implementer` | `lib/rfq_processing/llm_parser.rb` and spec; the live smoke test once a key exists | call the API without the coordinator's go |
| reviewer | `rfq-reviewer` (read only) | reviews each batch at a named commit before the coordinator pushes | edit anything |
| board watcher | a small loop: `git pull --ff-only` then print rows newer than the last seen time | reports new rows and @Yuval mentions to the coordinator every 5 minutes | post or commit |

Each worker gets: one task, acceptance criteria, owned paths, the starting commit, and the exact rspec command. Workers return changed paths and the rspec summary. The coordinator runs the full suite, then commits with explicit paths so a worker's half-written file is never swept in.

## 7. What is done, what is open

Done and on main (see the log): the whole library above, 117 or more specs including all 25 research lines, the Tisch adapter verified in the Rails test env, the three result fixtures and a six-line email accepted by `ApplyResult`, buyer profiles, RudCo vocabulary, COA, REACH, RoHS, Excel intake, the proposed demo email with a spec, board posts answering every teammate.

Open, in priority order for the demo:

1. **A real Claude run.** When a key exists: `ANTHROPIC_API_KEY` in `.env` (gitignored), then `RfqProcessing::LlmParser.from_env` in the pipeline, and a smoke test on the demo email. Compare the rules reading and the Claude reading on every line; the rules win on numbers.
2. **Ken's demo email.** When Ken posts it, run it through `bin/e2e-tisch-matcher.rb` (edit the text in the script) and fix any line that does not read as the research expects. Lead with the gauge line: 16 ga stainless is 0.0625 in, not 0.060.
3. **Hirsh's intake call.** When his invocation lands, run a pasted email in the app at `http://127.0.0.1:3100` (`script/dev`) and check the lines, the evidence, and the questions on screen.
4. **Answers end to end.** `Answers.apply` with Hirsh's response handler, once his buyer-answer buttons exist.
5. **Tisch's teachable fields** and metals prices. Until then metals lines are held with `unit_price` unresolved.
6. Keep `docs/ARCHITECTURE.md` and `PLAN.md` current with every change, and post on the board at every handoff.

## 8. First ten minutes for the new session

1. `cat .agent-owner` (expect `Yuval`). `git pull --ff-only origin main`. Read every bulletin row newer than the last time in the log below, especially rows with `@Yuval`.
2. Run the specs and the e2e script from section 4. Both must be green before any change.
3. Check that `answers.rb`, `llm_parser.rb`, `bin/test-set-report`, and `TEST-RESULTS.md` exist and their specs pass (they were being written by workers at handoff time). If any is missing, that is the first task.
4. Spawn the workers from section 6 for the open items in section 7 that have what they need.
5. Post one row on the board: picked up the lane, what is next, what you need. Then work.

## 9. Status log at handoff

| Time | State |
|---|---|
| 13:30 | Commits on main by Yuval: e4d2233 (library), a4e05ad (adapter, buyer profiles, RudCo vocabulary, flags), 437a98b (board post), df4eb25 (demo email, body sentences feed compliance, answers plumbing and contract). 114 specs green before the workers' modules. Three workers running: answers (W3), llm_parser, test-set report. Excel intake written and green locally, not yet pushed. Last board rows read: 13:28 (Hirsh took the Rails invocation and `.env`; asked Ken to name a key owner). |
