# Columbia Startup Lab: Get Hired Hack

Our team's project for the Columbia Startup Lab Get Hired hackathon.

## For teammates

1. Clone the repo and `git pull` often.
2. Create a file called `.agent-owner` in the repo root with your first name on one line. It is gitignored.
3. Add yourself to the Team and Core Domains tables in [`AGENTS.md`](AGENTS.md).
4. Point your coding agent (Claude Code, Codex, Cursor) at this repo. It will read `AGENTS.md` and the [bulletin board](docs/BULLETIN.md) to coordinate with everyone else's agents.

## What we're building

A Rails workspace that turns industrial RFQs into reviewed quotes. The rep can inspect source evidence, resolve unclear lines, and export an approved quote.

## Documents

Every document we made for this project, with a PDF where one exists. The [documentation map in AGENTS.md](AGENTS.md#documentation-map) says who owns each and when to read it.

### Product

| Document | What it is | PDF |
|---|---|---|
| [Product brief](docs/product/PRD.md) | What we build, for whom, the value props, and the commitments. Read first. | [PDF](docs/product/rfq_to_quote_product_brief.pdf) |
| [Demo workflow](docs/product/WORKFLOW.md) | The steps from RFQ email to sent quote, the decisions, and the video order. | [PDF](docs/product/demo_workflow.pdf) |
| [Brand position](docs/product/BRAND_POSITION.md) | How we talk: voice, words to use and avoid, taglines, screen text. | [PDF](docs/product/brand_position.pdf) |
| [Style guide](docs/product/STYLE_GUIDE.md) | How it looks: RudCo palette, status colors, type, buttons, layout, logo. | [PDF](docs/product/style_guide.pdf) |
| [Logo workshop](docs/product/logo_workshop.html) | The logo and favicon options, and the decision. | |
| [Demo video script](docs/product/DEMO_SCRIPT.md) | What the video shows and says, beat by beat, and what must work before recording. Draft. | |
| [Devpost write-up](docs/product/DEVPOST.md) | The submission text. Draft. | |

### Research

| Document | What it is | PDF |
|---|---|---|
| [Research report: what matters in RFQ to quote](docs/research/20261010.01_rfq_sharper_angle/report_rfq_sharper_angle.md) | The problems, value props, and the angle we build. Five research tracks are its appendices. | [PDF](docs/research/20261010.01_rfq_sharper_angle/rfq_research_report.pdf) |
| [Research brief](docs/research/20261010.01_rfq_sharper_angle/brief_rfq_sharper_angle.md) | The questions the research set out to answer. | [PDF](docs/research/20261010.01_rfq_sharper_angle/brief_rfq_research.pdf) |
| [Test set of 25 messy RFQ lines](docs/research/20261010.01_rfq_sharper_angle/research_domain_rules.md#6-test-set) | Each line with its correct reading and the buyer question. | |
| [RudCo company profile](docs/research/20261010.02_rudco_profile/rudco_profile.md) | Who RudCo is and what matters to them. | [PDF](docs/research/20261010.02_rudco_profile/rudco_profile.pdf) |
| [RudCo competitive analysis](docs/research/20261010.03_rudco_competitive_analysis/competitive_analysis.md) | What competitors offer, and where the demo puts RudCo ahead. | [PDF](docs/research/20261010.03_rudco_competitive_analysis/rudco_competitive_analysis.pdf) |

### Engineering

| Document | What it is | PDF |
|---|---|---|
| [Architecture](docs/ARCHITECTURE.md) | The four parts, how they connect, the contracts, and open gaps. | [PDF](docs/architecture.pdf) |
| [RFQ processing result format](docs/rfq_processing/RESULT-FORMAT.md) | The hash processing hands to the app. | |
| [Catalog and pricing method](docs/data/CATALOG_PRICING.md) | How catalog items and price benchmarks are admitted. | |
| [Bulletin board](docs/BULLETIN.md) | Where every teammate's agent posts progress and questions. | |

## Local development

Install Ruby 3.4.11 and Bundler 2.4.19, then run:

```sh
script/setup
script/check
script/dev
```

Open http://127.0.0.1:3100. See [the development baseline](docs/engineering/BASELINE.md) and [frontend integration contract](docs/engineering/FRONTEND_CONTRACT.md).
