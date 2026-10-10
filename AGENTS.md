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
- Use Claude Opus 5.5 (`claude-opus-5-5`) for Claude work. If unavailable, report the blocker instead of silently selecting another model.

## Team

Teammates: add yourself here and in Core Domains when you join. Your @-handle is your first name.

| Name | Handle | Area(s) |
|------|--------|---------|
| Ken | `@Ken` | Product design, user research, product management |
| Hirsh | `@Hirsh` | Quote application development |
| Yuval | `@Yuval` | RFQ processing, catalog and benchmark data sourcing |

## Core Domains

Each teammate owns a domain. Respect these boundaries and use the Bulletin Board for cross-domain requests.

| Name | Core Domain | Owns (files, folders, systems) |
|------|-------------|--------------------------------|
| Ken | Product (design, research, PM) | What we build and why: the product brief, requirements and priorities, user research notes and interviews, UX flows and screen designs, and the demo story. Lives in `docs/product/`, `docs/research/`, `docs/design/`. Agents: check with @Ken before changing scope, user-facing copy, or the flow of a screen. |
| Hirsh | Quote application | Upload/pasted-email UI, persistence, catalog storage/import, quote review, deterministic price math, human approval, and export. Agree on exact paths per task. |
| Yuval | RFQ processing | Document extraction, LLM integration, normalized specs and source evidence, catalog matching, compliance flags, draft questions, and catalog/benchmark data sourcing. Agree on exact paths per task. |

## Project overview

TBD. Fill in once the team picks what to build: the problem, the user, and the demo.

## Repo structure

```
columbia-startup-lab-get-hired-hack/
├── AGENTS.md              # This file (source of truth for agents)
├── CLAUDE.md              # Pointer to this file
├── README.md              # Public-facing overview
├── docs/
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
- `script/check`: run the existing PDF utility tests.
- The Rails application has not been scaffolded yet.

## Git conventions

- Work on `main` and push often (this is a hackathon). Pull right before you commit.
- For a one-line message: `git commit -m "Short summary"`.
- For a longer message, write it to a gitignored scratch file and use `-F`:
  - Claude: `.claude-commitYYYYMMDDHHMM`, then `git commit -F .claude-commitYYYYMMDDHHMM`
  - Codex: `.codex-commitYYYYMMDDHHMM`, then `git commit -F .codex-commitYYYYMMDDHHMM`
- End commit messages with a co-author trailer naming the model that did the work.
- Never commit secrets. API keys go in `.env`, which is gitignored. This repo is public.

## Documentation

- All docs are Markdown.
- Diagrams use Mermaid, never ASCII art. Prefer top-down (`graph TD`).
- Keep diagrams in `docs/diagrams/` current. When you change a flow that crosses module boundaries, update its diagram. If a diagram and the code disagree, fix the diagram.

## Writing style

- No em dashes. Use a comma, colon, semicolon, or period.
- Write plainly. One idea per sentence.
