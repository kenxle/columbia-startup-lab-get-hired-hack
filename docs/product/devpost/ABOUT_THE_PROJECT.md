# About the project (Devpost field)

Copied from the live Devpost field at 15:37, with your edits made there. Edit here; Claude pastes this back into Devpost. Everything below the line is the field.

---

## Track

**Track 2: RudCo, "RFQ to Quote".**

## What we built and why

### Why

RFQs are the lifeblood of RudCo. RudCo supplies metals, abrasives, and aggregates to industrial buyers, and it promises a quote within 24 hours. It also has to be right: one error on a quote can cost hundreds of thousands of dollars.

That is hard, because buyers write the same item many ways. Today a person decodes every line by hand, against the clock. A wrong guess on grade or thickness becomes a wrong quote, a lost order, or a return.

### What it is

RudCo Quote Desk is a web app for the quoting rep. RFQs are found processed, negotiated, quoted, reviewed, approved, and sent. The agent prepares the quote, and the rep owns it.

### What it does today

- **Reads each line into a standard spec.** Material, grade, form, thickness, size, quantity, and standard. 
- **Shows the evidence on each line.** Extracted fields link to the RFQ words and their source location. Derived values identify the rule or table used. The original RFQ stays beside the draft for review.
- **Matches each line to RudCo's catalog.** A line gets one match, a few candidates with a question, or "No match". A line with no fit is never forced onto the closest item.
- **Flags the paperwork the buyer needs.** Mill test reports, certificates of analysis, country of origin, DFARS, REACH, and RoHS. Each flag highlights the trigger words, including requirements the buyer never wrote down but the spec implies. A flag records what the buyer needs. It does not certify RudCo's stock.
- **Shows lead time status on each line.** Unknown lead times say "to confirm". Any 24 to 48 hour stock setting added for the demo is a product assumption, not verified supplier inventory.
- **Asks the buyer for missing info.** An unclear line becomes a specific question saved automatically in a local email preview. The rep enters the buyer's answer, and the affected line reruns. External email and buyer-click answers are not connected.
- **Keeps the rep in charge.** The rep edits the draft and approves the current revision. Later edits clear that approval. An explicit local send saves an email with matching PDF and CSV attachments, then records "Sent (local preview)", its time and its placeholder recipient. Repeating the send for that revision reopens the saved preview. Real external sending is not connected.
- **Remembers how a buyer writes.** The rep can teach the agent a term for one buyer. The reading is saved with the RFQ it was confirmed on and goes to processing on that buyer's next RFQ.
- **Tracks the 24-hour reply.** RudCo's quote form promises a reply within 24 hours. The quotes list shows a countdown for each RFQ and sorts the soonest due first.

The product is built to run on RudCo's real catalog, inventory, and prices.

## How the solution handles accuracy and uncertainty

Every RFQ goes through the same layers, and each layer can say "I don't know".

- **Rules first.** Deterministic rules read what can be computed: dimensions, units, gauge tables, and whether a line is complete.
- **The model fills gaps, under limits.** Claude only fills fields the rules left empty. It must quote the RFQ words it used, and it never overrides a rule or sets a price.
- **Every value keeps its source.** Each field stores the RFQ words and the rule, table, or model call behind it, so the rep can check any line with one click.
- **Uncertainty becomes a question, not a guess.** A missing or conflicting value holds that line and sends the buyer one specific question. The clear lines keep moving.
- **No source, no number.** Prices and lead times appear only with a named, dated source. Otherwise the line says so.
- **The rep signs off.** Nothing goes out until the rep approves, and any later edit clears the approval.
- **Failures fall back safely.** If the model call fails, the rules result stands and the quote still moves.


The [app dry run](../../engineering/DRY_RUN-2026-10-10.md) also verified the complete local reply flow: a missing 2,000 lb quantity moves from three Ready lines to four after the answer, with COA flags and the other lines preserved. Approval unlocks the documents; explicit local sending records a receipt and produces downloadable PDF/CSV attachments. An edit after approval blocks the final quote until the rep approves again. No external email was sent.

## Tools and technologies used

- **NicrronNinoo.** The hackathon's sponsor model gateway at `api.nicrron.ai`. The integration requests Claude Opus 5 (model `anthropic/claude-opus-5`). Recent local inference checks returned HTTP 502, so successful live model use is not claimed. It is wired into three places:
  - RFQ processing has a Nicrron provider that asks Claude to fill only the fields the rules left empty.
  - Tisch's catalog matcher has a reader for messy wording such as "sixteen gauge, four by eight, twenty sheets".
  - The distributor pricing agent uses the gateway to split an RFQ into lines. The gateway is never a source for prices, stock, or cost.
  - In the demo as shown, the Rails app runs with the model switched off, so lines are read by the rules parser and matcher.
- **Block Convey / PRISMtrace.** When configured, the optional background client sends model, outcome and timing metadata to PRISM, so failed calls can be inspected. No prompts, secrets, buyer data or model responses are sent. A tracing failure never stops a quote. Local tests pass; credentials and a verified live trace remain pending.
- **Jev.** A key is configured locally. Yuval's additive compliance integration is pending review; no live Jev result is claimed.
- **Ruby and Rails 8.** The web app.
- **SQLite.** App storage.
- **Prawn.** Builds the quote PDF.
- **letter_opener.** Previews the buyer emails in the browser.
- **Plain Ruby libraries.** RFQ processing (`tools/rfq_processing`), PDF text extraction (`tools/pdf_text`, built on pdf-reader), catalog matching, and distributor pricing.
- **Catalog data.** 96 items taken from RudCo's own public site, with RudCo's website list prices, and 143 constructed sample metals items with no prices.
- **FRED.** Published material price series that the pricing agent reads for context.

## Team members and roles

- **Ken St. Clair.** Product design, user research, and product management. Wrote the product brief, the demo workflow, the research, the brand position, and the style guide.
- **Elad Hirsh.** Front end and UI/UX for the quote application. Built intake, side-by-side evidence review, edits, automatic local question previews, buyer-answer entry, approval invalidation, and explicit local sending with a saved receipt and PDF/CSV attachments.
- **Yuval Gerber.** RFQ processing, plus catalog and benchmark data sourcing. Built text extraction from emails, PDFs, and spreadsheets, the line parser, readiness and compliance rules, buyer questions, and answer reruns.
- **Elad Tisch.** Catalog building, the catalog matching agent, and the market-based pricing agent. Built the RudCo and sample-metals catalogs, the matcher, and the pricing agent.

## Video demo

VIDEO LINK

## GitHub repository

https://github.com/kenxle/columbia-startup-lab-get-hired-hack

## Inspiration

RudCo's quote form promises a reply within 24 hours. We treat that as a requirement: every RFQ gets a quote back within 24 hours, even when some lines are unclear. The challenge says that today a person decodes every line by hand.

A wrong read on grade or thickness costs real money. Gauge numbers only imply a thickness, and gauge tables differ by material. The same "16 ga" is a different thickness on stainless and on mild steel.

RudCo's founder describes the rep's role this way: "Technology can handle more of the coordination and give those people better information for the conversation." ([Digital Journal, 2026-08-21](https://www.digitaljournal.com/article/ai-infrastructure-boom-reshapes-industrial-materials-procurement/)). We built to that idea. The agent prepares the conversation, and the rep owns it.

## How we built it

The team built it in one day. Each part has one owner.

- **Quote app (Hirsh).** A Rails 8 app with SQLite. It connects intake, evidence review, line edits, local question previews and buyer-answer reprocessing. Approval gates the final documents. The explicit local send saves the approved email, PDF and CSV together and records the receipt.
- **RFQ processing (Yuval).** A plain Ruby library that extracts text from the email body, PDFs, and spreadsheets, keeping the page and row of every line. It reads each line into fields, applies fixed rules, and decides by rule whether a line is ready. When a buyer answers a question, the library reruns only the answered lines.
- **Matching and catalog (Tisch).** A matcher that checks each catalog item field by field, plus the RudCo and sample-metals catalogs and a separate pricing agent.
- **Product (Ken).** The brief, the demo workflow, the research, the brand position, and the style guide. The look uses RudCo's own palette and logo.

The split between rules and the model is the main design choice. The teammates agreed on one result format between processing and the app, with stable line IDs and a revision ID on every run. That let each part change without breaking the others.

## Challenges we ran into

- **The gauge trap.** The same gauge number means a different thickness for different materials. The challenge example treats 16 gauge as 0.060 in, and the stainless gauge table says 0.0625 in. We keep a table per material and show which one each line used, so the rep can check it.
- **No sample catalog or prices from RudCo.** We built the catalog from RudCo's own public site and added constructed sample metals items. The prices on RudCo items are RudCo's website list prices, not quote prices. The sample metals items have no prices.
- **Pricing without making numbers up.** We hold any line that has no sourced price and leave it unpriced. The metals pricer is not finished, so metals lines show as held. We kept the rule.
- **Four people building at once.** Parallel work meant constant handoffs. A bulletin board and a shared result format kept the parts connected.

## What worked

- **Every field shows its source.** The rep can check the whole quote by clicking, without rereading the email.
- **24 of 25 research test lines read as expected.**
- **Hard cases stay visible.** A no-match line says "No match". A contradiction between "16 gauge" and "0.060 in" becomes a question. A rerun never overwrites a field the rep edited.
- **It looks and reads like RudCo's tool.** It uses RudCo's palette, its logo unchanged, and its own words for the paperwork it already promises customers.

## What we learned

- **The rep needs the reasoning behind a line.** A confidence number does not help a rep who has to defend a quote. The words in the RFQ and the table used to read them do.
- **Rules first, model second.** Gauge tables, unit conversion, and readiness are fixed rules. The model handles the language around them. That kept the accuracy checkable.
- **Ask, don't guess, and keep the rest moving.** One unclear line should not hold up the clear ones.

## What's next

These are designed and partly built. We list them here so the submission does not claim them.

- **A named, dated benchmark on every metals line.** The pricer for metals is not finished. It needs five delivered competitor offers per item, and none is connected yet. The quote would say the price tracks published metal cost plus RudCo's margin.
- **Alternates on unclear lines.** When the matcher finds two or three candidates for a line, or a line has two readings, the quote would show each one as an option with its own price. Example: "Option A: 16 ga, 0.0625 in" and "Option B: exactly 0.060 in". The buyer picks one when they accept, and the question still goes out. The app can show options when processing supplies them. Processing's option payload is not pushed yet.
- **Questions to a real mailbox.** Automatic local previews and "Waiting on buyer" tracking are built. Connecting them to external email delivery is next.
- **One-click answers from the buyer.** The buyer would click a choice in the email, and the answered line would rerun. The rerun logic is built. The click endpoints are not.
- **Sending the reply on the buyer's original thread.** Today an explicit send records a local receipt and saves the approved email with PDF and CSV attachments. Real mailbox delivery and thread replies are next.
- **Showing where a learned reading came from.** The line would say, for example, "Read as 0.060 in, as you confirmed on RFQ-0001."
- **Redlines.** Old and new values side by side when a rerun changes a line.
- **RudCo's real catalog, inventory, and prices.** The product is written for them. The demo stands in data shaped like theirs.
