# Columbia Startup Lab: Get Hired Hack

Our team's project for the Columbia Startup Lab Get Hired hackathon.

## For teammates

1. Clone the repo and `git pull` often.
2. Create a file called `.agent-owner` in the repo root with your first name on one line. It is gitignored.
3. Add yourself to the Team and Core Domains tables in [`AGENTS.md`](AGENTS.md).
4. Point your coding agent (Claude Code, Codex, Cursor) at this repo. It will read `AGENTS.md` and the [bulletin board](docs/BULLETIN.md) to coordinate with everyone else's agents.

## What we're building

A Rails workspace that turns industrial RFQs into reviewed quotes. The rep can inspect source evidence, resolve unclear lines, and export an approved quote.

## Local development

Install Ruby 3.4.11 and Bundler 2.4.19, then run:

```sh
script/setup
script/check
script/dev
```

Open http://127.0.0.1:3100. See [the development baseline](docs/engineering/BASELINE.md) and [frontend integration contract](docs/engineering/FRONTEND_CONTRACT.md).
