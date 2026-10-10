# RFQ Processing Result Format

**Owner:** Yuval (`@Yuval`). **Status:** draft 1, 2026-10-10. Changes bump `schema_version` and get a bulletin post.

This is the hash that RFQ processing hands to the quote app. It adopts the `QuoteLine` shape from Hirsh's [frontend contract](../engineering/FRONTEND_CONTRACT.md) as is, and adds one namespaced key, `processing`, for what the app may ignore. It also fixes the contract between RFQ processing and Tisch's matching agent.

Three fixtures in this shape live in [`tools/rfq_processing/spec/fixtures/results/`](../../tools/rfq_processing/spec/fixtures/results/): one Ready line, one Needs the buyer line, one No match line. Hirsh can build against them now.

## Who does what

| Step | Owner | Input | Output |
|---|---|---|---|
| Extract text from email, PDF, spreadsheet | Yuval | Bytes or text | Text lines with page and row positions |
| Read each line into a spec with evidence | Yuval | Text lines | Spec, evidence, confidence, assumptions |
| Normalize units, gauges, aliases, part numbers | Yuval | Raw spec | Normalized spec, rules used |
| Match a line to a catalog item | Tisch | Normalized spec plus line text | Candidates with scores and reasons |
| Readiness, compliance flags, draft question | Yuval | Normalized spec, match, line text | State, flags, question with choices |
| Assemble the result hash | Yuval | All of the above | The hash below, one per RFQ |
| Store, display, edit, price math, export | Hirsh | The hash | Quote screens |

One integration point: Yuval's library calls Tisch's matcher and produces the whole hash. The app receives it through `QuoteWorkspace::ApplyResult.call(quote:, result:)`.

## Top level

```json
{
  "schema_version": 1,
  "sample_data": true,
  "revision": { "id": "proc-20261010-125000-ab12cd34", "created_at": "2026-10-10T12:50:00-04:00", "processor": "rfq_processing 0.1", "llm": null },
  "source": { "type": "email", "filename": null, "pages": null, "rows": null },
  "warnings": ["page 2 has no extractable text; it may be scanned"],
  "lines": []
}
```

- `revision.id` is new for every processing run, including a rerun after a buyer answers. Hirsh asked for it so a reply can be tied to the run it answers.
- `revision.llm` names the Claude step that ran: `{ "provider": "nicrron", "model": "anthropic/claude-opus-5" }` through the hackathon's Nicrron gateway, or `{ "provider": "anthropic", "model": "claude-opus-5" }` through the Anthropic API. It is `null` when the run was rules only. The model is Claude Opus 5 (Hirsh, 13:40); a gateway answer from any other model is dropped, never substituted.
- `source.type` is `email`, `pdf`, or `spreadsheet`.
- `warnings` carries extraction problems the rep must see. A page with no text is a warning, never a silent skip.
- `sample_data` is true whenever the catalog or prices are ours, not RudCo's.

**What the app keeps today.** `QuoteWorkspace::ApplyResult` stores the `QuoteLine` keys only. It discards `revision`, `line_id`, `processing`, and any spec key outside the eight metals keys. So, until Hirsh extends the app, everything the rep must see goes into the stored keys: the rule used goes in `evidence.explanation`, assumptions go in `notes`, the part number goes in `description` and `catalog_sku`. The extra keys are in the hash now so the app can start keeping them without a format change.

## One line

Keys match `QuoteLine` in the frontend contract. All dimensions are decimal inches. Unknowns are `null`, never invented.

| Key | Type | Meaning |
|---|---|---|
| `line_id` | string | Stable across reruns: `line-<position>-<first 8 hex of sha256(original_text)>`. Hirsh asked for it for replies and re-quotes |
| `position` | integer | 1-based order in the RFQ |
| `description` | string | Normalized one-line description for the quote |
| `original_text` | string | The RFQ words for this line, verbatim |
| `spec` | hash | See spec keys below |
| `quantity` | decimal or null | |
| `quantity_unit` | string or null | `each`, `sheet`, `ft`, `lb`, and so on |
| `catalog_sku` | string or null | Tisch's `item_id`, for example `AVI-001`. Null unless matched |
| `unit_price` | decimal or null | Null unless Ready |
| `price_source` | string or null | Names the observations the price comes from and their basis |
| `state` | string | `ready`, `needs_buyer`, `no_match` |
| `clarification_question` | string or null | One question for the buyer, required when `needs_buyer` |
| `notes` | string or null | Anything the rep should read first |
| `evidence` | hash | Spec key or `quantity` to `{text, location, explanation}` |
| `compliance` | array | `{label, evidence, note}` entries |
| `benchmark` | hash or null | `{name, as_of, unit, kind, explanation}` |
| `unresolved_fields` | array | Spec keys the buyer must settle |
| `edited_fields` | array | Always empty from processing; the app fills it |
| `processing` | hash | Yuval's extension, below. The app may store or ignore it |

### Spec keys

Metals, from the frontend contract: `material`, `grade`, `form`, `thickness`, `width`, `length`, `standard`, `finish`.

Hardware, added for Tisch's catalog: `part_number`, `diameter`, `thread`, `grip`, `drilling`. `length` is reused for nominal length.

Every spec key present gets an `evidence` entry. A value that comes from the catalog rather than the RFQ says so in its `explanation`.

### Evidence

- `text`: the exact RFQ words, copied, not paraphrased.
- `location`: `line 3` for text, `page 2, line 5` for PDFs, `row 4, column C` for spreadsheets.
- `explanation`: how the words became the value, naming the rule or table. Example: `16 gauge on the stainless steel gauge table is 0.0625 in, not 0.060 in`.

### States and the readiness rule

The rule is deterministic. A confidence score never turns a missing field into Ready.

- `ready`: every required field for the form is present with evidence, no conflict between fields, exactly one catalog match at or above the threshold, and a price with a named source.
- `needs_buyer`: a required field is missing, two readings conflict (a gauge that disagrees with a stated decimal), or two catalog items fit equally. `clarification_question` and `unresolved_fields` are filled.
- `no_match`: the line reads cleanly but no catalog item fits above the threshold. The app still requires a `clarification_question` on every held line, because the export sends held lines with their questions. For No match the question is commercial, not a reading question, and it says "no match in the current catalog", never that RudCo lacks stock (Hirsh, 12:52): "No match in the current catalog for X. Quote it from an outside source at a stated lead time, or remove the line?"

App limits that the hash must respect: `description` 500 characters, `original_text` 5,000, `price_source` 200, `clarification_question` 1,000, `notes` 2,000, `catalog_sku` 100, spec values 200. Quantity must be greater than zero when present. A `no_match` line must not carry a `catalog_sku`.

Required fields by form: sheet and plate need material, grade, form, thickness, width, length, quantity. Bar needs material, grade, form, the cross-section dimensions, length, quantity. Hardware needs a full part number or every field that determines one, plus quantity. `standard` and `finish` are recorded as assumptions when absent, not as blockers.

### Compliance entries

`{label, evidence, note}`. `evidence` is the trigger text from the RFQ when the buyer asked outright, or the standard that implies the requirement. `note` says what the catalog knows about availability, or that it is unknown. These record what the buyer needs, never what the stock certifies.

### Benchmark

`{name, as_of, unit, kind, explanation}`. `kind` is `sample` for anything we assembled. `explanation` says what the benchmark supports and what it does not. For Tisch's aviation data: two public dealer listings for the same part number support a single-piece retail reference. They do not support a delivered price, a bulk tier, or a market index. The app shows this text next to the price.

### Question with choices

`clarification_question` is the sentence the buyer reads. `processing.question_choices` lists catalog-grounded choices, each `{id, label, value}`, for Hirsh's one-click flow. `id` is `<line_id>-c<n>` and is stable across reruns. Free text is always allowed. A buyer's answer comes back to processing as `{line_id, choice_id or free_text, revision_id}` and reruns that line only.

### The `processing` extension

```json
{
  "confidence": { "part_number": 0.98, "quantity": 0.97 },
  "assumptions": ["Material and finish come from the AN3 standard, not the RFQ words"],
  "rules_used": ["AN part number parser: family AN3, dash 13, suffix A means undrilled shank"],
  "match": {
    "status": "exact",
    "score": 1.0,
    "reason": "Exact part number match",
    "candidates": []
  },
  "question_choices": []
}
```

- `confidence` is per field, 0 to 1, from the LLM read. It is shown, never used alone to decide readiness.
- `assumptions` is the list Ken's research asks for: what was assumed, what was not stated.
- `rules_used` names every table and conversion applied.
- `match` is the matcher's answer, copied through. `status` is `exact`, `scored`, `ambiguous`, or `no_match`.

## Buyer answers and reruns (workflow W3)

A buyer's answer reruns only the answered lines. The app calls:

```ruby
RfqProcessing::Answers.apply(previous_result: stored_hash, answers: answers, pipeline: pipeline, buyer_terms: terms)
```

`answers` is a list, each one of:

```json
{ "line_id": "line-3-42054807", "choice_id": "line-3-42054807-c2", "revision_id": "proc-20261010-131500-ab12cd34" }
{ "line_id": "line-3-42054807", "free_text": "0.0625 in is fine", "revision_id": "proc-..." }
{ "scope": "rfq", "free_text": "all of it needs DFARS and domestic melt" }
```

- A choice settles the field the choice names (`processing.question_choices[].field`), with evidence that quotes the choice and names the revision it answered. Choosing a catalog candidate makes that item the match.
- Free text for one line is read by the parser as the buyer's words, so the evidence cites them. If the question is still open after the rerun, a warning says so and the rep reviews.
- A whole-RFQ answer (`scope: rfq`, guard 1) reruns every line, and its words are read for compliance flags on each line.
- The result is a new hash with a new `revision.id`, `previous_revision`, and `changed_line_ids`. Unanswered lines are copied unchanged. Every rerun line keeps its `line_id` and records `processing.answered`. Prices keep their `benchmark.as_of` (guard 4).
- Guards 2 and 3 (never overwrite a rep edit, clear approval and highlight changes) are the app's; `edited_fields` on the stored line is the signal.

## Alternates on ambiguous lines (Ken 13:58, fields agreed with Hirsh 14:00 and 14:03)

When the matcher returns two or three candidates, the line stays `needs_buyer` with its question, and `processing.alternates` lists each candidate as an option the review screen and the quote PDF show; the buyer picks one on acceptance. The committed subtotal never includes an option (Hirsh).

```json
"alternates": [
  { "id": "line-1-ab12cd34-o1", "choice_id": "line-1-ab12cd34-c1",
    "label": "Option A: 304 stainless sheet, 16 ga (0.0625 in), 2B finish",
    "catalog_sku": "RC-SS304-SHT-16GA-48X96-2B", "item_id": "RC-SS304-SHT-16GA-48X96-2B",
    "spec": { "material": "stainless steel", "grade": "304", "form": "sheet", "thickness_in": 0.0625, "finish": "2B" },
    "quantity": 20, "quantity_unit": "sheet",
    "unit_price": null, "currency": null, "price_source": null, "benchmark": null,
    "lead_time": "to confirm", "lead_time_source": "no stock confirmation on the catalog row",
    "unresolved_fields": ["unit_price"] }
]
```

- One entry per candidate that reached the threshold, in the matcher's order. `id` is `<line_id>-o<n>` and stable across reruns; `choice_id` names the question choice that picks this option, so a buyer answer and an acceptance point at the same thing.
- `quantity` and `quantity_unit` are the line's. A price appears only from a labeled source, the same rule as the line itself: `unit_price` with `currency` `USD`, `price_source`, and `benchmark` in the line's benchmark shape (`name`, `as_of`, `kind`, `unit`, `explanation`). Otherwise `unit_price`, `currency`, `price_source` and `benchmark` are null and `unresolved_fields` lists `unit_price`, so a missing price never looks quotable. When Tisch's pricer prices each candidate, those fields fill from it.
- `lead_time` is the text (`24 to 48 hours` or `to confirm`) and `lead_time_source` says why: the same two keys the app keeps on a line.
- No match lines and lines with one match carry an empty `alternates`. A no match line's closest items are never options, and a buyer answer can never promote one: only a candidate at or above the threshold can be chosen.
- Fixture: `tools/rfq_processing/spec/fixtures/results/ambiguous_with_options.json` passes `ApplyResult`.

## Buyer terms in (workflow step 9)

`buyer_terms` arrive in Tisch's `ClientTerm` shape with string keys: `term`, `meaning` (`fields`, or `part_number`), `source` (`taught` or `learned`), `client_name`, `times_confirmed`, and `confirmed_on`, the RFQ number the rep taught or confirmed the term on. With `confirmed_on`, the evidence on the line reads "Read as 0.0625 in, as you confirmed on RFQ-0001" (learned) or "as the rep taught on RFQ-0001" (taught). Without it, "Northline (taught by the rep): \"16 ga\" means thickness 0.0625". `RfqProcessing::BuyerProfile.learn(evidence_text:, field:, value:, client_name:, confirmed_on:)` returns a term in this shape for the app to save.

## Contract with the matching agent

Tisch owns the matcher. RFQ processing calls it once per line and copies its answer into `processing.match`. It must be callable from Ruby in-process (a module under `tools/`) or as a command that reads one JSON object on stdin and writes one on stdout.

**Input**

```json
{
  "line_text": "AN3-13A bolts, 100 ea, need C of C",
  "spec": { "part_number": "AN3-13A", "material": "alloy steel", "form": "hex-head bolt" },
  "quantity": 100,
  "quantity_unit": "each"
}
```

**Output**

```json
{
  "status": "exact",
  "threshold": 0.8,
  "best": { "item_id": "AVI-001", "part_number": "AN3-13A", "score": 1.0,
            "matched_on": ["exact part number"], "mismatches": [], "reason": "Exact part number match" },
  "candidates": []
}
```

- `score` is 0 to 1. An exact standard part number is 1.0. Below `threshold`, `best` is null and `status` is `no_match`.
- Two candidates within 0.05 of each other above the threshold give `status: ambiguous` and both appear in `candidates`. Processing turns that into a buyer question with those two as choices.
- Never substitute material, drilling, grade, or length to force a match. A mismatch on any of these is listed in `mismatches` and caps the score below the threshold.
- `candidates` holds up to three entries, best first, each in the same shape as `best`.

## Fixtures

| File | State | What it shows |
|---|---|---|
| `ready_an3_bolt.json` | ready | Exact part number match to `AVI-001`, two-dealer midpoint price with its basis stated, C of C flag |
| `needs_buyer_an3_missing_length.json` | needs_buyer | Family known, dash number missing, one question with catalog choices |
| `no_match_304_sheet.json` | no_match | Clean metals reading with the gauge rule shown, MTR flag, no sheet items in the sample catalog |
