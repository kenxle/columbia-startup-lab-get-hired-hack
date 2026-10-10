# Columbia Startup Lab: Get Hired Hack (Agent Guide)

This file is the source of truth for any AI agent working in this repo: Claude Code, Codex, Cursor, or anything else. `CLAUDE.md` is a thin pointer to this file. If you are a human teammate, read it too; it is how the team's agents coordinate.

## Start every session here

1. `git pull origin main`.
2. Read `.agent-owner` (see "Know your identity" below).
3. Read [`docs/BULLETIN.md`](docs/BULLETIN.md). Look for messages that @-mention your owner.
4. Archive any resolved messages (see "Archiving" below).
5. Then start work, or take direction from your human.

## Workflow rules

- **Commit and push often.** After a change, commit and push to `main` without being asked. Several agents push to the same repo at once; unpushed work is invisible work. Small commits beat big ones.
- **Test as you go.** The cycle is: write code, write or update tests, run tests, fix failures, commit and push. Every commit should leave tests passing. New function: add a test. Bug fix: add a regression test.
- **Know your identity.** At the start of every session, read `.agent-owner` in the repo root. It holds one line: the name of the teammate you are working for (for example `Ken`). Use that name on the Bulletin Board. If the file does not exist, ask your human who they are right away, then create it. The file is gitignored, so each machine has its own identity.
- **Stay in your lane.** If your work touches another teammate's domain (see Core Domains), do not silently change their code. Leave a Bulletin Board message @-mentioning them with what you need and why. Let them make the change, or at least get their go-ahead first.

## Bulletin Board

The board lives in [`docs/BULLETIN.md`](docs/BULLETIN.md). It is how agents talk to each other across machines.

- **After every pull**, re-read the board. Look for new messages @-mentioning your owner (for example `@Ken`). These are requests or handoffs meant for you. Skim the rest to see what changed.
- **At session end**, add a row with the date, the current time, your owner's name, and a short message covering:
  1. what you got done
  2. anything left unfinished or broken
  3. what the next agent needs to know
- **Use @-mentions** when you need something from someone or are handing off work (for example `@Ken: the API route is ready for the front end`).
- **Timestamps are required.** Date as `YYYY-MM-DD`, time as `HH:MM` (24-hour, local). Use the time from your system clock, not a guess.
- **Mark open items.** End any message that still needs action with `**OPEN:**` and what is outstanding.
- **Newest messages go at the top** of the table, so the freshest news is first.

### Archiving

When a message's action items are all resolved, move it from `docs/BULLETIN.md` to [`docs/BULLETIN-ARCHIVE.md`](docs/BULLETIN-ARCHIVE.md). This keeps the live board short.

- **Archive:** messages whose action items are done; informational notes everyone mentioned has seen; status updates that a later update replaced.
- **Keep:** anything with an open action item, an unfilled request, or an unanswered question.
- **How:** cut the rows from the board and paste them into the archive under a dated header (for example `## Archived 2026-10-10`). Add a `**RESOLVED:**` note saying why. Keep the original message text as written.
- **When:** at session start and at session end.

## Pull constantly

Several agents push to `main` at once. If you go a while without pulling, you will drift and hit merge conflicts. Run `git pull origin main`:

1. At session start, before reading code or making plans.
2. Before starting any new task.
3. Right before committing.
4. Between tasks.
5. Every so often during long stretches of work.
6. Whenever you read the Bulletin Board.
7. When code does not look the way you expect. Someone may have changed it.

## Parallel coding agents

- Pull before assigning work, between integration batches, and immediately before committing. During long tasks, check upstream at natural checkpoints, aiming for every 5 to 10 minutes.
- Re-read the bulletin after each pull. Reconcile new ownership or interface decisions before continuing.
- One coordinating agent owns Git mutations in a shared checkout. Workers do not pull, commit, or push independently. This is the worker exception to the session and commit rules above.
- Assign each worker a concrete task, acceptance criteria, owned files, and a starting commit. Use separate checkouts for overlapping edits. Never overwrite or stash another worker's work to make a pull succeed.
- Run reviewers against a stable revision. Integrate incoming changes at a safe checkpoint and rerun affected checks before publishing. If a push is rejected, reconcile upstream changes before retrying; never force-push shared main.
- Claude profiles live in `.claude/agents/`: `rfq-implementer`, `rfq-reviewer`, and `rfq-debugger`. Reviewers are read-only. The coordinator validates findings and integrates changes.
- Hirsh owns the quote application and Yuval owns RFQ processing. Agree on exact file ownership and the shared result format before concurrent implementation. See `docs/engineering/REVIEW-2026-10-10.md` for the responsibilities and interface refinements.
- Use Fable and GPT-6 Astra for complex implementation, decisions, and debugging. Use Claude Opus 5.5 (`claude-opus-5-5`) for independent review. Fable currently requires usage credits on Hirsh's account, so use the authorized Astra model while blocked. Report model availability issues instead of silently substituting.

## Team

Teammates: add yourself here and in Core Domains when you join. Your @-handle is your first name.

| Name | Handle | Area(s) |
|------|--------|---------|
| Ken | `@Ken` | Product design, user research, product management |
| Hirsh | `@Hirsh` | Front end and UI/UX for the quote application |
| Yuval | `@Yuval` | RFQ processing, catalog and benchmark data sourcing |
| Tisch | `@Tisch` | Catalog building, catalog matching agent, and market-based pricing agent |

## Core Domains

Each teammate owns a domain. Respect these boundaries and use the Bulletin Board for cross-domain requests.

| Name | Core Domain | Owns (files, folders, systems) |
|------|-------------|--------------------------------|
| Ken | Product (design, research, PM) | What we build and why: the product brief, requirements and priorities, user research notes and interviews, UX flows and screen designs, and the demo story. Lives in `docs/product/`, `docs/research/`, `docs/design/`. Agents: check with @Ken before changing scope, user-facing copy, or the flow of a screen. |
| Hirsh | Front end and UI/UX | Intake, side-by-side RFQ/quote review, editing, source evidence, one-click buyer questions and response flow, and export interactions. Own the Rails app shell and minimal supporting integration; coordinate backend contracts with Yuval. Follow Ken's approved product flow. |
| Yuval | RFQ processing | Document extraction, LLM integration, normalized specs and source evidence, catalog matching, compliance flags, draft questions, and catalog/benchmark data sourcing. Agree on exact paths per task. |
| Tisch | Catalog, matching, and market pricing | Builds the catalog from real, sourced items. Owns the matching agent: given an item description, it suggests which catalog item the buyer is looking for. Owns the pricing agent: it prices catalog items from real materials market data and compares the result to real published prices, to show our quotes are competitive. Owns `docs/data/`, `data/aviation/`, and `tools/catalog_research/`. See [catalog and pricing scope](docs/data/CATALOG_PRICING.md). Coordinate with Yuval on data sourcing and RFQ integration, Hirsh on catalog import and pricing math, and Ken on product scope. |

## Catalog and pricing guidance

Tisch leads the data foundation for the RudCo RFQ-to-quote challenge: a catalog of clearly specified industrial items, traceable market-price observations, and reproducible price comparisons that a quoting rep can review. Use RFQ (request for quotation) for this work, consistent with the challenge brief.

- Select benchmark items with public prices from at least two independent suppliers for matching material, grade, temper, shape, dimensions, quantity, and sale unit. Verify tolerances, finish, standards, and certification requirements before calling a comparison equivalent.
- Record supplier, SKU, source URL, observation date, currency, quantity tier, and all known charges. Keep product price and delivered price separate. Mark missing freight, tax, or certification charges as unknown.
- Normalize units with explicit calculations. Do not silently substitute grades, lengths, pack sizes, or certification levels. Commodity indices provide context, not a finished-item price.
- Separate observed market prices, constructed sample catalog entries, and suggested quote prices. Public listings do not establish RudCo inventory or acquisition cost. The rep owns the final quote price.
- Follow [docs/data/CATALOG_PRICING.md](docs/data/CATALOG_PRICING.md) for item admission, benchmark evidence, and pricing methodology.

## Project overview

We are building RudCo's RFQ to Quote track: an agent that turns a messy industrial RFQ into an accurate, competitive quote, faster than competitors. **Read the [product brief](docs/product/PRD.md) before you build anything.** It says who the user is, how the judges score us, and the commitments every part of the build keeps (show the source, ask instead of guess, no hallucinated pricing). Then read the [demo workflow](docs/product/WORKFLOW.md): the eight steps from RFQ email to sent quote, and who owns each.

### Documentation map

Read what your work touches. Each link says what the document is for.

**Product (Ken)**
- [Product brief](docs/product/PRD.md): what we build, for whom, and the commitments. Read first.
- [Demo workflow](docs/product/WORKFLOW.md): the steps from RFQ email to sent quote, what the rep sees, owners, and the video order.

**Research (Ken)**
- [Research report: what matters in RFQ to quote](docs/research/20261010.01_rfq_sharper_angle/report_rfq_sharper_angle.md): the problems, value props, and the angle we build (a quote that shows its work). [PDF](docs/research/20261010.01_rfq_sharper_angle/rfq_research_report.pdf).
- [Test set of 25 messy RFQ lines](docs/research/20261010.01_rfq_sharper_angle/research_domain_rules.md#6-test-set): each with the correct reading and the buyer question. Use it for tests and the demo RFQ.
- [Gauge tables, specs, and hidden requirements](docs/research/20261010.01_rfq_sharper_angle/research_domain_rules.md): the rules parsing and compliance flags follow.
- [Existing tools and public price sources](docs/research/20261010.01_rfq_sharper_angle/research_tools_and_prices.md): competitors' AI quote tools, and free benchmarks for pricing.
- [RudCo company profile](docs/research/20261010.02_rudco_profile/rudco_profile.md): who RudCo is and what matters to them.
- RudCo competitive analysis: in progress, in `docs/research/20261010.03_rudco_competitive_analysis/`.

**Engineering (Hirsh)**
- [Development baseline](docs/engineering/BASELINE.md): setup, run, and check commands.
- [Frontend contract](docs/engineering/FRONTEND_CONTRACT.md): routes, models, and the processing-result shape.
- [UI/UX approach](docs/engineering/UI_UX_APPROACH.md) and [design skills](docs/engineering/DESIGN_SKILLS.md).
- [Quote workspace diagram](docs/diagrams/quote-workspace.md).

**Catalog and pricing (Tisch)**
- [Catalog and pricing method](docs/data/CATALOG_PRICING.md): how items and benchmarks are admitted.
- [Aviation hardware catalog, 200 items](docs/data/AVIATION_ITEMS_200.md).

**Tools**
- [PDF to text](tools/pdf_text/README.md): extracts text from RFQ PDFs.

Add your new documents to this map when you create them.

## Repo structure

```
columbia-startup-lab-get-hired-hack/
├── AGENTS.md              # This file (source of truth for agents)
├── CLAUDE.md              # Pointer to this file
├── README.md              # Public-facing overview
├── docs/
│   ├── product/PRD.md     # Product brief (read before building)
│   ├── product/WORKFLOW.md # Demo workflow, step by step
│   ├── research/          # Research reports and company profile
│   ├── engineering/       # Baseline, frontend contract, UI approach
│   ├── data/              # Catalog and pricing
│   ├── BULLETIN.md        # Live bulletin board (read every pull)
│   ├── BULLETIN-ARCHIVE.md
│   └── diagrams/          # Mermaid diagrams of key flows
└── tools/
    └── pdf_text/          # PDF to text (Ruby, pdf-reader). See its README.
```

Add the code layout here once it exists.

## Development commands

Stack: Ruby on Rails. See `docs/engineering/BASELINE.md` for the pinned local toolchain and setup.

- `script/with-ruby ruby --version`: verify the pinned Ruby.
- `script/with-ruby rails --version`: verify Rails tooling.
- `script/setup`: install app and PDF dependencies and prepare the local database.
- `script/dev`: start the Rails app at http://127.0.0.1:3100.
- `script/check`: prepare the database and run Rails tests and PDF utility specs.

## Git conventions

- Work on `main` and push often (this is a hackathon). Pull right before you commit.
- For a one-line message: `git commit -m "Short summary"`.
- For a longer message, write it to a gitignored scratch file and use `-F`:
  - Claude: `.claude-commitYYYYMMDDHHMM`, then `git commit -F .claude-commitYYYYMMDDHHMM`
  - Codex: `.codex-commitYYYYMMDDHHMM`, then `git commit -F .codex-commitYYYYMMDDHHMM`
- Do not add Codex, Claude, or other AI author marks or co-author trailers to commits. Use the human's configured Git identity.
- Never commit secrets. API keys go in `.env`, which is gitignored. This repo is public.

## Documentation

- All docs are Markdown.
- Diagrams use Mermaid, never ASCII art. Prefer top-down (`graph TD`).
- Keep diagrams in `docs/diagrams/` current. When you change a flow that crosses module boundaries, update its diagram. If a diagram and the code disagree, fix the diagram.

## Writing style

- No em dashes. Use a comma, colon, semicolon, or period.
- Write plainly. One idea per sentence.
