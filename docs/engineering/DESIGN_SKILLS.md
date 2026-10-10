# Design skills for the RFQ workspace

Researched for Hirsh on 2026-10-10. This compares guidance from maintainers,
not measured improvements to our application. No additional plugin has been installed.

## Recommended combination

| Resource | Role in our work | Decision |
|---|---|---|
| [Anthropic frontend-design](https://github.com/anthropics/skills/blob/main/skills/frontend-design/SKILL.md) | Establish a distinctive visual direction, type scale and layout grounded in industrial quoting. | Apply the guidance to the Rails interface. |
| [Vercel web-design-guidelines](https://github.com/vercel-labs/agent-skills/blob/main/skills/web-design-guidelines/SKILL.md) | Check interaction, accessibility, responsive layout and content handling. | Apply applicable framework-independent rules during UI review. |
| [Impeccable](https://github.com/pbakaus/impeccable) | Adds structured critique, simplification, polish and responsive auditing commands. | Useful later if repeated design iterations justify another tool. |
| [Figma implement-design](https://github.com/openai/skills/blob/main/skills/.curated/figma-implement-design/SKILL.md) | Translate an existing Figma design into application code. | Use when Ken provides an approved Figma source. No Figma dependency for this slice. |

Anthropic focuses on deliberate visual choices and critique against the brief.
Vercel adds concrete checks for labeled controls, keyboard focus, long content,
numeric alignment, stateful navigation and reduced motion. Some rules assume a
JavaScript framework; equivalent Rails and semantic HTML behavior takes priority.
The guides differ on heading capitalization, so follow one consistent sentence-case
system rather than combining their stylistic rules mechanically.

Impeccable is broader than a simple prompt file. Its current installation can add
hooks and an engine, so the lightweight two-guide workflow is sufficient now.

## Direction for this app

Treat the interface as a precision quoting desk. Use cool paper surfaces,
ink/slate navigation and a cobalt action accent. Reserve green, amber and red
for readiness states. Prices and uncertainties should be easy to compare.
The memorable interaction is seeing the evidence beside the selected quote line.

Keep the RFQ, line status and next action visible together. Show details on demand,
avoid decorative badges and oversized cards, and ensure every action has clear
feedback. Preserve source traceability, explicit sample labels and rep approval.

## Verification and ownership

The running Rails app at http://127.0.0.1:3100 is the interaction test surface.
Inspect desktop and narrow layouts, keyboard focus, field edits, validation,
approval and export. Screenshots complement automated behavior tests.
Hirsh owns implementation; Ken owns product decisions. Proposed changes to the
buyer communication flow remain on the bulletin awaiting Ken's decision.

Use Astra for design decisions and implementation while Fable needs account
usage credits. Use Opus 5.5 for an independent review of a stable snapshot.
