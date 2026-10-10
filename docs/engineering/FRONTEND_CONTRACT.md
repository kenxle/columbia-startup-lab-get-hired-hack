# Quote workspace: first working slice

Hirsh owns the Rails front end and the minimal supporting persistence in this
slice. Yuval owns real extraction, normalization, matching and provider calls.
This slice implements Ken's approved PRD at `d64cfc8`; it does not pretend to
process an uploaded document. Demo results are explicitly sample data.

## Application routes

- GET `/` and GET `/quotes`: workspace list, scoped to the current browser session.
- GET `/quotes/new`: upload or paste RFQ, with title and buyer name.
- POST `/quotes`: save intake; show Awaiting processing until the real pipeline applies results.
- POST `/quotes/demo`: create an editable sample RFQ for this session, then redirect to it.
- GET `/quotes/:id`: original RFQ beside quote lines, evidence, questions and editing.
- PATCH `/quotes/:quote_id/quote_lines/:id`: save line edits and invalidate quote approval.
- POST `/quotes/:id/approve`: explicit human confirmation of ready lines and held lines/questions.
- GET `/quotes/:id/export`: CSV of approved quote, ready lines priced, held lines unpriced with questions.
- GET `/quotes/:id/source`: original file as a download, never render untrusted HTML inline.

The quote workspace is local development, not production authentication. Scope
records to an opaque token in the Rails session so browsers cannot access one
another's RFQs by guessing IDs.

## Model and view interface

`Quote`: title, buyer_name, source_text, original_filename, source_bytes (binary),
workspace_token, sample_data (boolean), approved_at, created_at. Ordered
`quote_lines` association. Methods: `reference` (RFQ-0001 format), `subtotal`
(BigDecimal sum of quotable lines only), `ready_count`, `held_count`,
`approved?`, `awaiting_processing?` (no lines), `approvable?` (at least one quotable
line and every held line has a question). File intake capped at 10 MB; text at
50,000 characters. Uploaded PDFs/spreadsheets are stored without claimed parsing.

`QuoteLine`: position, description, original_text, spec (JSON hash), quantity
(decimal), quantity_unit, catalog_sku, unit_price (decimal), price_source,
state (`ready`, `needs_buyer`, `no_match`), clarification_question, notes,
evidence (JSON hash), compliance (JSON array), benchmark (JSON hash),
unresolved_fields (JSON array), edited_fields (JSON array).

Spec keys: material, grade, form, thickness, width, length, standard, finish.
Evidence maps a spec key (or quantity) to `{text, location, explanation}`.
Compliance entries: `{label, evidence, note}`. These record requested paperwork,
not certification of actual stock. Benchmark: `{name, as_of, unit, kind,
explanation}`. `kind: sample` must be displayed as sample, never live market data.

Line methods: `quotable?`, `line_total` (nil for held lines), `status_label`,
`display_description`. A quotable line must be in state ready, have positive
quantity, nonnegative price, a price source, a catalog SKU, and no unresolved
fields. Positive quantity and valid decimal prices are model-validated. Null
prices are allowed only for held lines. Unknowns remain empty, not invented.

Manual edits: the UI can update description, spec fields, quantity, quantity_unit,
unit_price, notes and clarification_question. Do not expose a free-text catalog
SKU or arbitrary state input. Editing material/spec/quantity marks a line for
reprocessing (`needs_buyer`), records the changed fields, and adds an explicit
question if none exists. Price/note edits invalidate quote approval but do not
invent a match. A rep-entered price is labeled as such. Do not automatically
clear ambiguity or compliance requirements merely because a text field changed.

Controllers expose `@quote`, `@lines`, `@selected_line` (query parameter `line`,
default first), and `@quotes` on the list. Validation errors render in the page.
Use Rails forms and server redirects; no JavaScript is needed for core actions.
The quote export is unavailable before human approval and invalidated by any
edit. Sample exports must be labeled SAMPLE. Escape spreadsheet formula prefixes
in every user-controlled CSV string. No buyer emails are sent.

## Processing handoff

`QuoteWorkspace::ApplyResult.call(quote:, result:)` is the internal integration
point. It accepts a Ruby hash with string keys: `schema_version: 1`,
`sample_data: boolean`, and `lines: [...]` in the QuoteLine shape above.
Validate all rows, required evidence and statuses before replacing existing
results in one transaction. Never trust an LLM's ready flag without validating
quantity, catalog ID, price and source. This method is not an unauthenticated
HTTP endpoint. Yuval can call it when processing completes; no parser namespace
or provider selection is imposed on his implementation.

The demo factory is `QuoteWorkspace::Demo.create!(workspace_token:)`. It creates
three known lines from a fixed synthetic RFQ: one ready, one missing material,
and one without a catalog match. It does not parse arbitrary input. Use a price
of USD 232.00 per sheet and quantity 20 for the ready line (sample subtotal
USD 4,640.00). A second line has quantity 10, and the third quantity 2. No price
is assigned to either held line. Use fictional buyer Northline Fabrication.

## UI direction

Build a focused industrial quoting workspace, not a chat screen. Warm white,
charcoal typography, restrained rust-orange actions, subtle dividers, clear
green/amber/red status labels. A slim desktop sidebar, spacious header, compact
summary strip, then the original email on the left and the quote on the right.
The selected line shows editable fields, source evidence, pricing basis and a
note. Use the PRD labels Ready, Needs the buyer and No match. Show explicit
sample data labeling, held lines excluded from subtotal, and human review.
Use a responsive stacked layout on narrow screens, real form labels, keyboard
focus, semantic tables, and helpful empty states. No dead navigation or actions.

## Work boundaries

- UI worker: `app/views/**`, `app/assets/stylesheets/**`, `app/helpers/quotes_helper.rb`.
- Supporting app worker: models, quote controllers, `app/services/quote_workspace/**`,
  database migrations, app tests, and `config/routes.rb`.
- Coordinator: dependencies, shared configuration, docs, Git, integration and browser QA.
- Yuval's real parsing/matching/provider code remains outside this assignment.
