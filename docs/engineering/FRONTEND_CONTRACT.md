# Quote workspace contract

Hirsh owns the Rails workspace and its integration with processing. Yuval owns
RFQ extraction and normalization. Tisch owns catalog matching, pricing and buyer
memory. Follow Ken's approved [product brief](../product/PRD.md) and
[workflow](../product/WORKFLOW.md).

The app now processes saved RFQs asynchronously. It uses rules-based parsing,
the RudCo and metals catalogs, and supported source prices. No AI provider is
called by the current intake path. Provider integration and credentials remain
pending. The demo presentation follows Ken's 13:48 decision: no concept/sample banners.
Internal provenance and pricing evidence remain stored.

## Application routes

All quote and catalog records are scoped to the browser's opaque workspace
session token. This is a local prototype, not production authentication.

| Method and path | Behavior |
|---|---|
| GET `/`, `/quotes` | Workspace quote list |
| GET `/quotes/new` | Paste or upload an RFQ |
| POST `/quotes` | Save intake and enqueue processing; preserve saved intake if queuing fails |
| POST `/quotes/demo` | Create the fixed demonstration RFQ |
| GET `/quotes/:id` | Source, processing status, extraction warnings, quote lines and editing |
| POST `/quotes/:quote_id/processing` | Revision-guarded processing or retry of an empty quote |
| PATCH `/quotes/:quote_id/quote_lines/:id` | Save rep edits and invalidate approval |
| GET `/quotes/:quote_id/buyer_questions` | Consolidated preview of existing held-line questions |
| GET `/quotes/:quote_id/buyer_questions/download` | Plain-text draft when every held line has a question |
| POST `/quotes/:quote_id/buyer_questions/preview_email` | Local question email preview with revision check |
| POST `/quotes/:quote_id/buyer_answers` | Apply one rep-entered buyer answer to its current held line |
| POST `/quotes/:quote_id/buyer_terms` | Explicitly teach a supported field for this buyer, with source RFQ provenance |
| POST `/quotes/:id/approve` | Human approval of the current whole quote |
| GET `/quotes/:quote_id/final_quote` | Approved email draft and export preparation |
| GET `/quotes/:quote_id/final_quote/download` | Approved plain-text email draft |
| GET `/quotes/:quote_id/final_quote/pdf` | Approved PDF quote |
| POST `/quotes/:quote_id/final_quote/preview_email` | Local email preview with actual PDF and CSV attachments |
| GET `/quotes/:id/export` | Approved CSV, with held lines unpriced |
| GET `/quotes/:id/source` | Download original source, never render uploaded HTML inline |

Catalog matching routes are `/catalog_matches` (GET, POST),
`/catalog_matches/:id` (GET), `/catalog_matches/:id/approve` (POST),
`/catalog_matches/teach` (POST), and `/catalog_matches/forget` (DELETE).
Approval is idempotent and only adds offered candidates without near/conflict
checks. It rejects closest-only results, cross-workspace quotes and other buyers'
quotes. Added catalog lines remain unpriced and retain internal catalog provenance.

## Intake and processing

`QuoteWorkspace::ProcessRfq.enqueue(quote:, expected_revision:)` creates a persisted
`ProcessingRun` and enqueues `ProcessRfqJob`. Intake calls it after saving. The
request does not run extraction synchronously. `ProcessRfq.perform(run_id)`
captures source and buyer context, processes outside the quote lock, then checks
the quote revision again before applying results. Development dispatch uses an
in-process async queue; persisted runs do not make that queue durable across
server restarts. A timed-out run can be explicitly retried after five minutes.

Run states are `queued`, `running`, `succeeded`, `failed`, `stale`, and `conflict`.
Duplicate active submissions reuse the same run. Newer revisions or rep edits
prevent a late job from replacing current lines. The manual endpoint only accepts
empty quotes. Failed empty quotes can be retried. Existing reviewed lines need a
future merge workflow, not destructive full reprocessing.

Pasted text, text uploads, text-bearing PDFs and CSV files are supported. Excel
files need conversion to CSV; raw `.eml` files need a pasted body or supported
attachment. Scans without extractable text fail with warnings. Intake is capped
at 10 MB for files and 50,000 characters for pasted text. Original bytes stay
unchanged. Queue and processing failures leave a recoverable RFQ and visible status.

Intake supplies an explicit RudCo and metals catalog to the matcher. Aviation
is excluded from this path while its readiness contract is unresolved. RudCo
per-pound prices apply only to pound quantities; unsupported units stay held.
Explicit known catalog part numbers fail with a rep-review message while the
shared matcher shortcut cannot verify all other stated attributes.
A named buyer resolves to a normalized, case-insensitive client within the same
workspace. Blank buyers have no shared anonymous client. `BuyerContext.for(quote)`
returns `{client:, buyer_terms:}` with only persisted rep-taught terms and client
provenance. Automatically learned terms are excluded, and intake passes no client
memory to the matcher. Automatic learning is not complete.

## Model and view interface

`Quote` holds title, buyer_name, source_text, original_filename, source_bytes,
workspace_token, sample_data, approved_at, processing_revision, processing_source
and processing_warnings. Ordered `quote_lines` and `processing_runs` associations
support review. `reference` uses RFQ-0001 format. `subtotal` sums rounded quotable
line totals. `ready_count`, `held_count`, `approved?`, `awaiting_processing?`,
`approvable?` and `review_revision` drive the UI.

`QuoteLine` holds position, description, original_text, spec, quantity,
quantity_unit, catalog_sku, unit_price, price_source, state, clarification_question,
notes, evidence, compliance, benchmark, unresolved_fields, edited_fields,
line_id, processing, lead_time and lead_time_source.

States are `ready`, `needs_buyer`, and `no_match`. Spec keys are material, grade,
form, thickness, width, length, standard, finish, part_number, diameter, thread,
grip and drilling. Evidence maps a spec key or quantity to
`{text, location, explanation}`. Compliance entries use `{label, evidence, note}`
and describe requested paperwork, not certified stock. Benchmark entries use
`{name, as_of, unit, kind, explanation}`. Benchmark kind remains in stored evidence; the demo omits sample badges.

A quotable line needs positive quantity, nonnegative price, price source, SKU,
state `ready`, and no unresolved fields. Unknowns remain empty. Held lines have
no exported price or total. `display_lead_time` returns sourced lead time only
for a quotable line with both lead_time and lead_time_source; otherwise it returns
`to confirm`. Spec or quantity edits clear lead-time evidence.

Controllers expose `@quote`, whole-quote `@lines`, filtered `@visible_lines`,
`@status` (`all`, `attention`, `ready`) and `@selected_line`. Filters affect the
table only, not totals or approval. Edits preserve allowlisted filter context;
question edits use the fixed `buyer_questions` return marker. Validation errors
retain the selected line and return context.

The rep may edit description, spec, quantity, unit, price, notes and question.
SKU and state are not arbitrary form inputs. Spec or quantity edits hold the line
for reprocessing; price edits are labeled rep-entered and drop prior benchmark
claims. Description edits do not rerun matching. Every saved edit clears approval.

## Result handoff and metadata

`QuoteWorkspace::ApplyResult.call(quote:, result:)` accepts schema_version 1,
sample_data, nonempty lines, and optional revision, source and warnings. It
validates evidence and readiness, then replaces lines and metadata under the quote
lock in one transaction. Invalid results preserve the prior quote. This is an
internal service, not a public result-ingestion endpoint.

Top-level revision maps to processing_revision. Each line may retain a stable
line_id and processing hash. Metadata hashes are limited to 32 KiB, depth 8 and
1,000 nodes. Revisions need a nonblank id; line IDs are at most 200 characters and
unique within a quote. Metadata does not authorize sending or make a line ready.

Source maps to processing_source and accepts only type, filename, pages and rows.
Types are email, pdf, spreadsheet, text and csv. Filename is optional text of up
to 255 characters; counts are optional nonnegative integers. Unknown source keys
or types are rejected. processing_warnings contains at most 100 strings of up to
1,000 characters each. Combined source and warning JSON is capped at 32 KiB.
Omitted or null evidence clears previous values. `assign_processing_evidence`
validates and assigns without saving, so a failed zero-line extraction can retain
warnings without replacing existing quote lines. The evidence panel escapes all
text. This metadata is internal and excluded from buyer exports.

## Approval, exports and local email

Approval requires `reviewed=1` and the current `reviewed_version`. Quote edits and
applied results advance that revision under the same parent quote lock. A stale
review cannot approve newer content.

`FinalQuote` and `PdfExport` reload approval and lines under the quote lock and
reject unapproved or invalid quotes. Unit prices retain up to four decimal places;
line totals round to cents before summing. PDF includes normalized specs, pricing
sources and benchmarks, lead times, requested paperwork and held questions.
Rep overrides do not retain old benchmark claims. Missing benchmarks say so.
Embedded licensed fonts preserve supported Unicode specs; unsupported glyphs fail
explicitly rather than silently changing specifications.

Internal notes, processing metadata and original source bytes stay out of buyer
exports. CSV text escapes spreadsheet formula prefixes. The demo exports omit concept/sample labels while retaining source names and dates.
The question draft needs at least one held line and a question for every held line.
Preview and download actions do not approve the quote or mutate its lines.

`EmailPreview` captures email text, PDF and CSV under one quote lock and revision
check. Development uses `letter_opener`; tests use the test mail adapter. SMTP and
other transports are rejected. Previews use `buyer@example.invalid` and explicitly
say no email was sent to the buyer. Plain-text downloads name files to attach,
without claiming attachments already exist in an email.

Real inbox ingestion, buyer delivery, public choice-response links, confidence-based
automatic sending, general re-quote redlines and production authentication remain pending.
Rep-entered answers bind to the DB line, stable processing ID, current review revision
and current processing revision. Stale answers, target rep edits and active runs are
rejected. Only the answered line changes; other rows and edits keep their IDs and values.
A successful answer clears approval. Explicit teaching stores a trusted source RFQ
reference as `confirmed_on`, scoped to the same buyer and workspace.

## UI direction and ownership

Ken's [style guide](../product/STYLE_GUIDE.md) is the visual source of truth.
Use [UI_COMPONENTS.md](UI_COMPONENTS.md) for shared tokens, status badges, panels,
flags and forms. It replaces earlier ad hoc color and component guidance. Keep
source evidence, status words and human approval visible. Retain
semantic tables, real labels, keyboard focus and responsive layouts.

Hirsh owns workspace controllers, views and minimal integration. Yuval's processor
and Tisch's catalog, matching and memory services remain their domains. Coordinate
contract changes before editing those services. The coordinator owns shared Git,
dependencies, integration checks and browser verification.

### Processing timing bridge

Optional `processing.lead_time` accepts `text`, a boolean `stocked`, and `source`.
Valid sourced timing reaches display and exports only on Ready lines with confirmed
stock; unknown timing and explicit third-party stock remain "to confirm".
Explicit top-level timing fields, including null clears, take precedence. Malformed
nested timing rejects the result atomically. Metadata is producer evidence, not
independent verification of inventory.

## Local review data

In development only, opening an empty Quotes workspace creates twelve persisted
RFQs through `QuoteWorkspace::DemoWorkspace.seed_if_empty!`. Added material
requests use the local rules parser and catalog with `llm: false`; no job, API
call or email is sent. Existing workspaces are unchanged on ordinary visits.
`DemoWorkspace.populate!(workspace_token:)` explicitly tops an older local
workspace up to twelve, without changing its existing RFQs. Production does not
seed. The fixed `Demo` factory remains available for repeatable workflow tests.

## Desk deadlines and priced alternatives

The quote list sorts unsent RFQs by receipt plus 24 hours, followed by sent RFQs.
The badge updates each minute, turns amber at three hours, and turns red overdue.
A current sent revision shows its receipt-to-send duration; approval and local
mail preview never set delivery metadata. Constructed development sent history
is explicitly created by the seed service and never calls a mail transport.

`processing.alternates` follows Yuval's result format. The app shows 2–3 distinct
options with their own specs, prices, benchmarks and lead-time sources. A missing
or invalid price remains held. Quantity/unit mismatches, invalid dates and
unresolved fields cannot produce a quotable price. Mutually exclusive options
are not part of the Ready subtotal. Rep edits suppress stale options.
