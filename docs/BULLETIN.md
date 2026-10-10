# Bulletin Board

> **This board is for agents to leave messages for each other.** Use @-mentions (`@Ken`, plus each teammate's first name) to direct a message to a teammate's agent. At session start, check for messages that mention you. At session end, leave a note on what you did and @-mention anyone who needs to act on it.
>
> **Timestamps are required:** `YYYY-MM-DD` and `HH:MM` (24-hour, local). **Newest rows go at the top.**
>
> **Resolved messages get archived** to [`BULLETIN-ARCHIVE.md`](BULLETIN-ARCHIVE.md). Full rules are in [`AGENTS.md`](../AGENTS.md) under "Bulletin Board."

| Date | Time | Agent (Owner) | Message |
|------|------|---------------|---------|
| 2026-10-10 | 12:02 | Ken | **Product brief drafted: [docs/product/PRD.md](product/PRD.md).** What we are building for the RudCo track, who it is for, how the judges score it, and the commitments (show the source, ask instead of guess, label sample data). **@everyone:** read it before you build. **OPEN:** catalog and price data source, our uniqueness angle, and whether the user is RudCo's quoting rep, all with @Ken. |
| 2026-10-10 | 11:55 | Ken | **Ken's role: product design, user research, product management.** Ken owns what we build and why: brief, requirements and priorities, user research, UX flows and screens, and the demo story (`docs/product/`, `docs/research/`, `docs/design/`). **@everyone:** check with @Ken before changing scope, user-facing copy, or a screen's flow. |
| 2026-10-10 | 11:55 | Ken | **Added `tools/pdf_text/`: PDF to text, for reading resumes.** Pure Ruby on the `pdf-reader` gem, ported from Steady Thread. Use `bin/pdf-to-text file.pdf`, or `PdfText.extract(bytes)` from Ruby. Errors carry a plain `#reason` you can show a user. 12 specs pass (`bundle exec rspec` in that folder). Limits: scanned PDFs have no text to read (OCR needed), and some fonts drop the spaces between words. Details in [`tools/pdf_text/README.md`](../tools/pdf_text/README.md). |
| 2026-10-10 | 11:49 | Hirsh | Connected the local workspace to the repository, saved the local agent identity, and added Hirsh to Team and Core Domains. **OPEN:** Hirsh's domain is still to be decided. |
| 2026-10-10 | 11:45 | Ken | **Repo set up.** `AGENTS.md` has the team rules; `CLAUDE.md` points to it. **@everyone:** add yourself to the Team and Core Domains tables in `AGENTS.md`, and create your `.agent-owner` file. **OPEN:** team roster, project idea, and stack still to be decided. |
