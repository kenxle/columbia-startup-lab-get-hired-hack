# Handoff: RFQ processing lane (Yuval)

**For:** the next agent session working for Yuval in this repo. The previous session ran in Claude Code; the next one may be Codex. Everything here is tool-neutral. Read this file first, then do "First ten minutes". The original pickup notes below describe 14:08 on 2026-10-10. Read the latest status log and current-session notes first; the repo and bulletin board are authoritative.

**Owner:** Yuval Gerber (`@Yuval`, GitHub `Yuval-Gerber`). `.agent-owner` in the repo root says `Yuval`. The git identity of this clone is Yuval Gerber. Codex commit scratch files are `.codex-commitYYYYMMDDHHMM` (see AGENTS.md, Git conventions). No AI co-author trailers.

## 1. What this project is

RudCo Quote Desk: an agent that turns a messy industrial RFQ (email, PDF, spreadsheet) into a quote a sales rep can check and send. Every field shows the words it came from. Unclear lines become one buyer question with choices. The hackathon ends at 4:30 PM ET today with a video demo; the demo dry run is at 3:15 PM, recording about 3:45 to 4:30. Read, in this order:

1. [AGENTS.md](../../AGENTS.md): the team rules. One coordinator owns git per checkout; workers never pull, commit, or push. Pull before every task and every commit. Reread [docs/BULLETIN.md](../BULLETIN.md) after every pull. No em dashes in docs. Claude Opus 5 (`claude-opus-5`) for every Claude process, per Hirsh's 13:40 board row.
2. [docs/product/PRD.md](../product/PRD.md): the brief. Commitments: show the source, ask instead of guess, no hallucinated pricing. New core requirement (Ken 13:58): a quote within 24 hours even when lines are unclear.
3. [docs/product/WORKFLOW.md](../product/WORKFLOW.md): the demo steps and decisions. [docs/product/DEMO_SCRIPT.md](../product/DEMO_SCRIPT.md): the video script with the checklist of what must work (rows 3, 4, 9, 12 depend on this lane).
4. [docs/ARCHITECTURE.md](../ARCHITECTURE.md): the four parts and the contracts. Yuval's section is "RFQ processing". Update it in the same commit as any contract or status change.
5. [PLAN.md](PLAN.md), [RESULT-FORMAT.md](RESULT-FORMAT.md) (the hash the app accepts; the matcher contract; buyer answers; alternates; buyer terms), [TEST-RESULTS.md](TEST-RESULTS.md).

## 2. Original pickup ownership (historical, current handoffs are in section 7)

| Person | Handle | Owns | Waiting on Yuval for | Yuval waiting on them for |
|---|---|---|---|---|
| Ken St. Clair | `@Ken` | Product, demo script, Devpost, video | Progress rows on the board (Ken updates the build map on Ken's Desk from them) | Nothing |
| Hirsh | `@Hirsh` | Rails app, all screens, intake (`QuoteWorkspace::ProcessRfq`), answer entry UI, teaching UI, alternates on review and PDF | The code push with `processing.alternates`, the `pick_item` guard, `revision.llm`, and the live Nicrron smoke result | The rep-enters-the-answer endpoint that calls `Answers.apply`; passing `confirmed_on` in `buyer_terms`; his 502 request details (he posted them at 13:59) |
| Tisch | `@Tisch` | Catalog data, `app/services/catalog_match/*`, pricing engine | Nothing | The demo RFQ email in `docs/product/demo_rfq/`; `gauge`, `thickness`, `quantity_unit` in `ClientTerm::TEACHABLE_FIELDS`; a `confirmed_on` field on `client_terms`; priced candidates with a named, dated benchmark. Ken pinged him at 14:06; his last post was 13:30 |
| Yuval | | This lane | | The Nicrron API key, shared privately by Hirsh with the team. Put it in `.env` at the repo root as `NICRRON_API_KEY=...` (gitignored). Not in this checkout at handoff time |

## 3. The library

`tools/rfq_processing/` is plain Ruby, no Rails. Own Gemfile (no new gems were added today). Entry point:

```ruby
RfqProcessing.process(content:, type: "email" | "pdf" | "spreadsheet", filename:, catalog: rows, matcher: nil, buyer_terms: [], context: {}, llm: nil, sample_data: false)
```

Returns the schema-1 hash in [RESULT-FORMAT.md](RESULT-FORMAT.md). Hirsh's intake (`app/services/quote_workspace/process_rfq.rb`) calls it with `IntakeMatcher < RfqProcessing::CatalogMatchAdapter` (`service: CatalogMatch::Matcher`, catalogs rudco and metals only, `llm: false` until the gateway works, `sample_data: true`, which I flagged on the board as against Ken's no-labels decision). The app applies the hash with `QuoteWorkspace::ApplyResult.call(quote:, result:)`, which now keeps `line_id`, `processing`, `lead_time`, `lead_time_source` and the `revision`.

| File under `lib/rfq_processing/` | Does |
|---|---|
| `rules_parser.rb`, `lexicon.rb`, `units.rb`, `gauge_table.rb` | One line in, a Reading out: fields, exact source words, confidence, assumptions, rules used, conflicts, unknowns. Applies answers (overrides) and buyer terms first. Gauge tables by material and form (16 ga stainless is 0.0625 in). |
| `readiness.rb` | ready, needs_buyer, or no_match; one question per held line; choices with the field each settles. |
| `compliance.rb` | MTR, EN 10204, DFARS, Buy America, origin, ITAR, PMI, NACE, ASME SA, COA, REACH, RoHS. Each flag quotes its trigger. |
| `catalog_matcher.rb` | Fallback matcher for JSON catalogs. |
| `catalog_match_adapter.rb` | Tisch's matcher in (`service:` Matcher or Contract, `catalog:`), the contract hash out; enriches entries with price and stock from `Catalog.default`. Puts a no match line's closest items in `candidates` with `total_candidates` 0. |
| `buyer_profile.rb` | Step 9: applies a buyer's taught or learned terms (ClientTerm shape); `learn` turns a rep edit into a term. `confirmed_on` wording was in progress at handoff (section 7). |
| `extractor.rb` | Email, PDF (through `tools/pdf_text`), CSV, Excel (roo). |
| `result_builder.rb` | One line hash in the app's shape; prices only from a labeled source; `benchmark_for`, `price_for`, `lead_time_for`. Alternates were in progress at handoff. |
| `pipeline.rb` | Extract, pick lines, parse, match, decide, flag, assemble. `pick_item` promotes a chosen candidate; the guard against promoting a closest item was in progress. |
| `answers.rb` | W3: a buyer answer reruns only the answered lines; `scope: rfq` reruns all. Public signature `Answers.apply(previous_result:, answers:, pipeline:, buyer_terms: [], context: {})` must stay stable (Hirsh builds on it). |
| `llm_parser.rb`, `openai_compatible_client.rb` | The Claude step, Opus 5. Nicrron gateway (OpenAI-compatible chat, `NICRRON_API_KEY`, `NICRRON_BASE_URL` default `https://api.nicrron.ai/v1`, `NICRRON_MODEL` default `anthropic/claude-opus-5`, Net::HTTP) or the `anthropic` gem (`ANTHROPIC_API_KEY`, `claude-opus-5`). Auto-on when a key exists, Nicrron first; `RFQ_LLM_PROVIDER` forces one. Never overwrites a rules value; drops fields whose quoted evidence is not in the line; drops any answer from a model other than the requested one (Opus 5.5 is rejected on purpose). `describe` feeds `revision.llm`. Never run against the live gateway yet. |

Helpers in `bin/`: `test-set-report`, `apply-fixtures.rb`, `e2e-apply-result.rb`, `e2e-tisch-matcher.rb`, `e2e-answers.rb` (new, buyer answers end to end in the Rails test env), `llm-smoke` (new: rules versus Claude per line; `--models` lists the gateway's models; `RFQ_LLM_SMOKE_STUB=1` runs with a stub), `merge-bulletin.py`, `watch-board` (fetch-only board watcher).

## 4. Commands (copy exactly)

```sh
export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
cd /Users/yuval/columbia-startup-lab-get-hired-hack
git pull --ff-only origin main
script/check                                   # Rails tests + PDF specs
cd tools/rfq_processing && BUNDLE_GEMFILE="$PWD/Gemfile" ../../script/with-ruby bundle _2.4.19_ exec rspec && cd ../..
RAILS_ENV=test BUNDLE_GEMFILE=Gemfile script/with-ruby bin/rails runner tools/rfq_processing/bin/e2e-tisch-matcher.rb
RAILS_ENV=test BUNDLE_GEMFILE=Gemfile script/with-ruby bin/rails runner tools/rfq_processing/bin/e2e-answers.rb
```

Live smoke test, only once the key is in `.env` and Yuval says go:

```sh
# Run from the repo root. dotenv loads .env without shell expansion or logging keys.
BUNDLE_GEMFILE=Gemfile script/with-ruby bundle exec ruby -rdotenv/load tools/rfq_processing/bin/llm-smoke --models
BUNDLE_GEMFILE=Gemfile script/with-ruby bundle exec ruby -rdotenv/load tools/rfq_processing/bin/llm-smoke
```

Commit and push. Commit with explicit paths only. If the working tree has uncommitted lane files that belong to another worker, merge instead of rebase so nothing is stashed:

```sh
git add <explicit paths> && git commit -m "RFQ processing: <what>"
git pull --rebase origin main || (python3 -I tools/rfq_processing/bin/merge-bulletin.py docs/BULLETIN.md && git add docs/BULLETIN.md && GIT_EDITOR=true git rebase --continue)
git push origin main      # if rejected, pull again and retry; check the exit code, not the output
```

Posting on the board: insert a row right under the header line `|------|------|---------------|---------|` in `docs/BULLETIN.md`, newest first: `| 2026-10-10 | HH:MM | Yuval | message |`. No pipe characters inside the message. Time from `date '+%H:%M'`. Post delivered work and real asks.

## 5. Working rules Yuval set

- Updated by Yuval at 14:47: push code after teammate inspection without asking Yuval again. He separately approved the first parser batch. Board rows and lane review docs are authorized for immediate push. Say exactly what landed and what still needs teammate review.
- Answer every question and request on the board aimed at Yuval; ask teammates for what you need there; integrate their answers.
- Give Yuval short reports.
- Agents must not step on each other on this Mac: one git actor (the coordinator), workers on disjoint file sets, a board watcher that only fetches. Keep everything about this lane in `docs/rfq_processing/`.
- `.claude-flow/`, `.claude/settings.json`, `.claude/skills/`, `.mcp.json`, `.claude/proven-config.json`, `.claude/.proven-config-version` are local only, in `.git/info/exclude`. Do not edit `CLAUDE.md`, `AGENTS.md`, or `.claude/agents/` (team files).

## 6. How to divide the agents

| Agent | Owns (paths) | Never does |
|---|---|---|
| Coordinator (the main session) | git, the board, integration, `docs/rfq_processing/*`, the e2e runs | delegate a push or a board post |
| parser worker | `lib/rfq_processing/{rules_parser,lexicon,units,gauge_table,readiness}.rb` and specs | touch pipeline or result shape |
| integration worker | `lib/rfq_processing/{pipeline,result_builder,catalog_match_adapter,answers}.rb`, specs, `bin/e2e-*.rb`, `spec/fixtures/results/*` | change the hash shape without a RESULT-FORMAT.md edit by the coordinator |
| data and flags worker | `lib/rfq_processing/{compliance,buyer_profile,extractor}.rb` and specs | invent domain rules |
| llm worker | `lib/rfq_processing/{llm_parser,openai_compatible_client}.rb`, specs, `bin/llm-smoke` | call the API without the coordinator's go |
| reviewer (read only) | reviews each batch before the push | edit anything |
| board agent | runs `bin/watch-board <state dir> 300 1` in a loop, quotes new rows to the coordinator and to the worker they affect, drafts the reply row | pull, post, commit |

Each worker gets one task, acceptance criteria, owned paths, the starting commit, and the exact rspec command, and returns changed paths and the rspec summary.

## 7. Current handoff and open work (15:24)

The inherited Claude work is finished and pushed after teammate inspection. The new confirmed_terms integration and smoke reliability patch are local, tested and published as an exact review artifact in REVIEW-2026-10-10.md, cleared by Hirsh at 15:30 and being published. The separate matcher consumer and PRISM provider hook still require review. Current local files: pipeline.rb, catalog_match_adapter.rb, e2e-teaching-match.rb, llm-smoke, new confirmed_terms_spec.rb and llm_smoke_spec.rb, plus RESULT-FORMAT.md.

| Batch | Published | Review |
|---|---|---|
| Parser and buyer-term RFQ provenance | `9fa2c86` | Hirsh 14:52 |
| Provider adapters and sanitized diagnostics | `7e3d2c6` | Hirsh 14:58, disabled app paths |
| Extraction, compliance, answers, alternates, selection guards and e2e scripts | `e4ec750` | Hirsh 14:58 and final extraction reproduction 15:07 |

Latest local tree: 332 lane specs, 480 Rails tests / 3967 assertions and 12 PDF specs pass. Matcher, answers, email/PDF/CSV and demo-pair end-to-end checks pass. Teaching safety is a separate blocked diagnostic, not a passing check.

1. Hirsh agreed `confirmed_terms: []` at 15:15. Our implementation forwards only applied token-bounded teaching with complete provenance, exact evidence/value agreement and no remaining conflicts/unknowns; nine tests pass. App forwarding and persisted source-line validation are with Hirsh. Matcher/DescriptionReader implementation is with the Ken/Tisch handoff, owner still requested. The real persisted-teaching diagnostic accepts pipeline-to-adapter delivery, then exits 2 at missing app forwarding/matcher support. Hirsh cleared the corrected processing/smoke subset at 15:30 after 108 isolated targeted examples. Matcher consumer implementation is now local under Tisch’s 15:26 handoff accepted by Hirsh at 15:28; the real persisted teaching diagnostic passes fully with it. Publish that separate consumer after its own review.
2. Hirsh ran the exact eight-line provider smoke at 15:15: every line returned HTTP502 twice, zero fills and no model identity. Our local smoke fix now exits nonzero on failed/rejected/empty/partial inference, labels stub-only runs honestly and uses the bounded PDF selector. Fourteen offline CLI tests pass, including the actual Transnet PDF yielding one item/call rather than 257. Live activation remains off pending a successful inference. Local credentials are absent.
3. Ken is coordinating the catalog/pricing takeover requested by Hirsh at 15:10. Route metals prices, supplier evidence and sourced lead-time needs to Ken; do not silently edit those domains.
4. Jev doubtful-compliance diagnostics await usable local key, Ruby client and calibration inputs. `script/load-jev-key` confirmed no accessible local Keychain entry. All deterministic flags must remain intact.
5. The accepted demo pair works in browser records `/quotes/14` and `/quotes/17`. Buyer-answer transition and taught RFQ wording were verified; safe end-to-end taught matching remains blocked. Unknown lead times stay explicit.
6. Continue pulling, answering the bulletin, and recording every handoff. Do not rerun completed implementation tasks from historical log entries.

## 8. Opening prompt for the new session

> Read docs/rfq_processing/HANDOFF.md and AGENTS.md. You work for Yuval. Pull and read board rows newer than the latest status log. Run the checks in section 4, then work the current open items in section 7. All inherited batches are pushed; do not recreate them. Publish code after teammate inspection and publish coordination rows directly. Keep local Ruflo available, use authorized Astra workers when needed, and do not claim unavailable Opus review. Post on the board at each handoff.

## Current session, 2026-10-10 at 15:09

- Yuval authorizes code pushes after teammate inspection, without personal review. Hirsh cleared parser/BuyerProfile at 14:52, disabled provider and corrected result/answers/adapter at 14:58, and extraction/compliance at 15:07 after reproducing the fixes. Parser is in `9fa2c86`; provider is in `7e3d2c6`; the remaining dependency batch is pushed as `e4ec750`. Latest app verification: 451 Rails tests / 3721 assertions and 12 PDF utility specs pass.
- All 297 processing specs pass after Ken rebuilt the demo PDF. Email/PDF/CSV checks retain eight items, correct demand and source scope. Email and PDF explicitly require MTR on all steel, including shot; CSV contains narrower per-row requirements. Demo pair and buyer-answer end-to-end checks pass: four Ready, or three Ready plus one quantity question, then four Ready after 2000 lb.
- Source evidence, blank-quantity PDF rows, scoped body compliance, selective answer reruns, stable line IDs, compatible priced alternates and candidate-selection guards are implemented. Transnet's bounded table yields its actual 50,000 kg S390 item; Iowa 2021 remains an unsupported fragmented layout and must not be presented as fully parsed.
- Local Ruflo registers workers; actual implementation/review workers run through authorized Astra. Opus independent review remains quota-blocked until 16:50 ET. Do not claim it occurred.
- Ken requested live model activation at 15:06. Local NICRRON_API_KEY and JEV_API_KEY are absent. Hirsh offered his configured machine for the live provider smoke at 15:08. Coordinate activation with him; app ownership stays with Hirsh. Missing/error providers must fall back to rules. No live call has run on Yuval's machine.
- Hirsh took the unsafe matcher numeric override at 15:08. The new `e2e-teaching-match.rb` diagnostic exits 2 until untaught plain given values cannot replace explicit 0.060 thickness or quantity 100. No safe teaching acceptance is claimed. Our adapter currently sends plain given values, so a vetted same-phrase provenance interface remains necessary.
- Jev doubtful-compliance diagnostics remain pending a usable client/key and calibration examples. Never remove deterministic flags or grant readiness from Jev confidence. Hirsh owns the question-checking path.
- Local browser records: `/quotes/14` has four Ready abrasive lines totaling USD1810; `/quotes/17` has three Ready totaling USD1010 plus one Waiting on buyer, explicitly local preview. `/quotes/16` demonstrates taught RFQ provenance, but matcher safety remains blocked. Sourced stock/lead times remain unknown.
- Local server PID 35740 runs with LAUNCHY_DRY_RUN=true after migration and restart. Hirsh's silent preview hotfix is loaded; browser RFQ-0017 is verified. No real buyer email was sent.
- Coordinator alone owns Git. Pull and reread the board before every task/commit. Board watcher fetches only. Keep answering all owner mentions and post a handoff at session end.

## 9. Status log

| Time | State |
|---|---|
| 15:09 | Remaining dependency batch cleared by Hirsh at 15:07. PDF repaired; all 297 processing specs and format/demo-pair checks pass. Live smoke delegated to Hirsh; safe matcher handoff and Jev dependencies remain open. |
| 14:50 | Codex continuation, current notes above. Runtime fixes local; exact diff published for teammate inspection. Updated user authorization: teammate review is the code-push gate. Ken requests two focused demo RFQs. PDF repair and matcher trusted-term interface remain with Tisch; app override arity with Hirsh. |
| 14:08 | Handoff to a new session (Yuval moving to Codex). main at f119852 plus whatever teammates pushed since. Uncommitted worker files in section 7; 202 lane specs green on the tree. Board rows read and answered through 14:04 (Ken's 14:06 ping is for Tisch). Nicrron key not in this checkout. |
| 13:53 | Session 2 at 77b9980. Gates green at pickup. Hirsh's intake and ApplyResult changes pulled, root bundle installed, test database prepared. Workers started: Nicrron provider, answers e2e plus `revision.llm`. |
| 13:36 | Session 1 last push: 57a343a (code) and 8593c8b (board). 150 specs green. `answers.rb`, `llm_parser.rb`, `bin/test-set-report`, Excel intake, Tisch contract adapter, production wording, lead time. |

## PRISM assignment, 15:30

Ken assigned PRISM provider tracing to Yuval at 15:28. Hirsh is publishing his completed metadata-only client/job; reuse it. Our worker adds a listener hook to OpenaiCompatibleClient, one event per HTTP inference attempt including failures, with local run/attempt IDs and no prompts/responses/secrets. User is creating the PRISM account and will add project/key to ignored .env. A real ingestion and dashboard screenshot remain pending credentials; no live trace is claimed.
