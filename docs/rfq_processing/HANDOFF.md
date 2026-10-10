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

## 2. The people and what is between us

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
cd tools/rfq_processing
env $(grep -v '^#' ../../.env | xargs) bin/llm-smoke --models     # is anthropic/claude-opus-5 listed?
env $(grep -v '^#' ../../.env | xargs) bin/llm-smoke               # rules versus Claude on the demo email
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

## 7. State at handoff (14:08): read this carefully

**On main (pushed):** all board rows through 14:04 answered. Lane docs updated: Opus 5 and Nicrron decisions, `revision.llm`, the alternates contract (`processing.alternates`, fields agreed with Hirsh at 14:00 and 14:03), the buyer terms contract (`confirmed_on`), `bin/watch-board`.

**In the working tree, UNCOMMITTED, not yet reviewed by Yuval.** Lane spec suite on this tree: 202 examples, 0 failures at 14:06. Three worker agents from the previous session may still have been writing when that session ended, so run the suite first and read `git diff` before trusting any of it:

| Files | By | State |
|---|---|---|
| `lib/rfq_processing/llm_parser.rb`, `lib/rfq_processing/openai_compatible_client.rb` (new), `spec/rfq_processing/llm_parser_spec.rb`, `spec/rfq_processing/openai_compatible_client_spec.rb` (new), `bin/llm-smoke` (new) | llm worker | Done and reported: 192 then 196 green. Two judgment calls to confirm: `RFQ_LLM_PROVIDER` naming a provider with no key returns nil with a warning instead of falling through; the model check rejects `claude-opus-5-5` for `claude-opus-5`. A read-only review of these files was running at handoff; its findings were not received. |
| `lib/rfq_processing/pipeline.rb`, `result_builder.rb`, `answers.rb`, `catalog_match_adapter.rb`, `spec/rfq_processing/answers_spec.rb`, `result_builder_spec.rb`, `bin/e2e-answers.rb` (new) | integration worker | In progress, three tasks in order: (1) `revision.llm` from `@llm.describe` and `bin/e2e-answers.rb` (answers end to end through `ApplyResult` in the Rails test env, plus a report on Tisch's `CatalogMatch::PricingHandoff`); (2) `processing.alternates` per RESULT-FORMAT.md with fixture `spec/fixtures/results/ambiguous_with_options.json`; (3) the `pick_item` guard: only a candidate at or above the threshold on an ambiguous or scored match can be chosen, otherwise the match is unchanged and a conflict is recorded. Not reported at handoff. |
| `lib/rfq_processing/buyer_profile.rb`, `spec/rfq_processing/buyer_profile_spec.rb`, possibly the BuyerProfile evidence lines of `rules_parser.rb` | data worker | In progress: `confirmed_on` on a term gives "Read as thickness 0.0625 in, as you confirmed on RFQ-0001" (learned) or "as the rep taught on RFQ-0001" (taught); `learn(..., confirmed_on:)`. Not reported at handoff; no changes on disk yet at 14:06. |

**What to do with it:** run the suite and `script/check`. Commit each worker's files with explicit paths once green and once Yuval has looked at the diff. Then post one board row listing what landed (Hirsh is waiting for `processing.alternates`, the guard, and `revision.llm`).

**Open, in priority order for the demo:**

1. Finish and push the three worker batches above. Then run `bin/e2e-answers.rb` and `bin/e2e-tisch-matcher.rb` in the Rails test env; both must print ACCEPTED.
2. The live Nicrron smoke test when `NICRRON_API_KEY` is in `.env` (section 4). Hirsh's own minimal request to `/v1/chat/completions` with model `anthropic/claude-opus-5` returned HTTP 502 at 13:47, so first check `--models`. Post the result either way. The demo must stay green on rules alone.
3. Ken's demo checklist row 4 needs one Ready, one Needs the buyer, and one No match line on the same RFQ. With Hirsh's intake (rudco and metals catalogs only) the AN3 bolt line in `spec/fixtures/demo_rfq_email.txt` should be the No match line; confirm in the app at `http://127.0.0.1:3100` (`script/setup`, then `script/dev`, paste the email). Tisch's final demo email, when it lands in `docs/product/demo_rfq/`, must be run through `bin/e2e-tisch-matcher.rb` (edit the text in the script); lead with the gauge line.
4. Beat 6: when Hirsh's answer entry is on main, enter the buyer's answer on a held line in the app and check it turns Ready.
5. Beat 8: when Tisch adds `confirmed_on` and the teachable fields and Hirsh passes them, teach "16 ga" on one RFQ and check the second RFQ shows the source wording.
6. Keep `docs/ARCHITECTURE.md` and `PLAN.md` current with every change, and post on the board at every handoff.

## 8. Opening prompt for the new session

> Read docs/rfq_processing/HANDOFF.md and follow it exactly. You work for Yuval. Pull, read the bulletin board rows newer than 14:04, run the lane specs and script/check, read the uncommitted lane files listed in section 7 and finish or verify them, then post one row on the board and keep working on the open items in order. Yuval reviews code before you push it; board rows and lane docs you post right away. Give Yuval short reports. Run a board agent that fetches every 5 minutes and tells you and the workers what changed.

## Current session, 2026-10-10 at 14:50

- Review artifact: [exact processing diff](REVIEW-2026-10-10.md), based on `981a911`, published in `efd4cbc` and merged/pushed through `ac12fcc`. It contains the runtime changes for Hirsh/Tisch inspection, not an installed code commit. Do not mistake the review artifact for landed implementation.
- Yuval now permits pushes after teammate review, without personal approval. First parser batch already has his approval; it also needs BuyerProfile provenance to make its tests pass. Hirsh/Tisch were asked to review that dependency and the rest of the exact diff at 14:48.
- Local Ruflo registers workers but its spawn command does not execute them without an Anthropic provider. Actual workers are authorized GPT-6 Astra Codex agents. Local config is excluded from Git. Required Opus review is blocked by Claude quota until 16:50 ET, not replaced by claiming Astra is Opus.
- Inherited provider, alternates, selection guard and source-provenance work is finished locally. Additional fixes cover bounded PDF rows/page evidence, Transnet total versus package quantity, numbered schedules, scoped body compliance across answers, stable answer identities, candidate-price validation and Ken's three priority shorthand misreads.
- Tests before the newest app override: 395 Rails tests / 3240 assertions, 12 PDF specs, matcher e2e and answer e2e pass. Latest library: 286 examples, two failures from the malformed upstream demo PDF. New candidate-price/answer tests: 44 pass. Both smoke modes pass with `RFQ_LLM_SMOKE_STUB=1` and pinned Ruby. No live model calls.
- `981a911` changed Hirsh's IntakeMatcher override to one-argument `call_service`, while our inherited adapter supplies three. Hirsh owns the requested app fix; retain `llm: false` and `client: nil`. Rerun app/e2e checks after it lands.
- Tisch must repair final demo PDF and add the narrow trusted-term matcher argument. Taught normalized thickness and RFQ provenance are correct locally; current matcher reparses original 0.060 and stays ambiguous. Do not override all source numbers or restore unconfirmed client memory.
- Ken's latest 14:48 request is a demo walkthrough and two focused RFQs. Local `/quotes/10` is a deliberately unmatched 7075 sheet: no catalog item, price, lead time, finish or standard. We are preparing existing sourced abrasive lines for the mostly-working example, with all stock/pricing claims checked against catalog data. Do not fill empty fields with invented values.
- Local server launched by this session: PID 25953, port 3100. Restart our server after Ruby library changes before browser verification. Local RFQ-0013 demonstrated a held shot becoming Ready after `100 lb`, USD 40, approval still required. Never send to real buyers as part of this test.
- Board watcher is fetch-only in an ignored `.claude-flow/yuval-board` directory. Pull and reread board before every new task/commit and at natural checkpoints. Coordinator owns Git; workers never pull/commit/push.

## 9. Status log

| Time | State |
|---|---|
| 14:50 | Codex continuation, current notes above. Runtime fixes local; exact diff published for teammate inspection. Updated user authorization: teammate review is the code-push gate. Ken requests two focused demo RFQs. PDF repair and matcher trusted-term interface remain with Tisch; app override arity with Hirsh. |
| 14:08 | Handoff to a new session (Yuval moving to Codex). main at f119852 plus whatever teammates pushed since. Uncommitted worker files in section 7; 202 lane specs green on the tree. Board rows read and answered through 14:04 (Ken's 14:06 ping is for Tisch). Nicrron key not in this checkout. |
| 13:53 | Session 2 at 77b9980. Gates green at pickup. Hirsh's intake and ApplyResult changes pulled, root bundle installed, test database prepared. Workers started: Nicrron provider, answers e2e plus `revision.llm`. |
| 13:36 | Session 1 last push: 57a343a (code) and 8593c8b (board). 150 specs green. `answers.rb`, `llm_parser.rb`, `bin/test-set-report`, Excel intake, Tisch contract adapter, production wording, lead time. |
