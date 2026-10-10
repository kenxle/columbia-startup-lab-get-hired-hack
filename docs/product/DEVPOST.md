# RudCo Quote Desk: Devpost Submission

**Status:** Draft for Ken's review. Paste field by field into Devpost.

**Summary.** The sections below follow the order of the fields the hackathon requires. The extra story sections come after them. The app workflow below reflects the [verified local dry run](../engineering/DRY_RUN-2026-10-10.md); the [build map](KEN_DESK.md#build-map) tracks the wider product scope. Anything partly built or not started is under "What's next".

## Needs Ken

Remove this section before pasting into Devpost.

- [ ] **Video link.** Section 7 says `VIDEO LINK`. Replace it once the video is up.
- [ ] **Block Convey and Jev.** PRISM metadata-only integration is implemented and locally tested; credentials and live trace proof remain pending. Jev has a locally configured key, with client integration pending. Update these claims only after a verified result.
- [ ] **Claude in the demo path.** The Rails app runs intake with model enrichment switched off (`llm: false`). The latest controlled inference check returned HTTP 502 and correctly exited with failure while preserving rules output. A model listing or an earlier teammate result does not establish successful inference on this demo path.
- [ ] **Metals prices.** Your promo video shows a full price on a metals line. The app does not: metals lines stay unpriced until Tisch's pricer has five competitor offers per item. Sections 3 and 4 say metals lines are held. The video and this text should not disagree on screen.
- [ ] **Lead times.** Ken authorized a 24 to 48 hour demo stock assumption for S-330, G-40, S-170 and G-25. If shown, describe it as a demo assumption, not verified inventory. Reconcile the sourced-stock wording in the accuracy section before submission.
- [ ] **Test counts.** The published app dry run records 480 Rails tests, 3,997 assertions and 12 PDF specs passing. Yuval subsequently reported 486 Rails tests, 4,038 assertions and 12 PDF specs passing. Refresh the final submission from the final integrated run; the corrupt-PDF failures are resolved.

## 1. Project name and one-line description

**Project name:** RudCo Quote Desk

**Tagline:** A messy RFQ in, a quote that shows its work out.

**One-line description:** RudCo Quote Desk reads an industrial buyer's messy RFQ and drafts a quote for the rep to check and send, with the source of every field on the screen.

## 2. Track

**Track 2: RudCo, "RFQ to Quote".**

## 3. What we built and why

### Why

RFQs are the lifeblood of RudCo. RudCo supplies metals, abrasives, and aggregates to industrial buyers, and it promises a quote within 24 hours. It also has to be right: one error on a quote can cost hundreds of thousands of dollars.

That is hard, because buyers write the same item many ways. One writes "304 SS sheet 16ga 4x8". Another writes "Stainless 304, 0.060 in, 48 x 96". Today a person decodes every line by hand, against the clock. A wrong guess on grade or thickness becomes a wrong quote, a lost order, or a return.

### What it is

RudCo Quote Desk is a web app for the quoting rep. The rep pastes email text or uploads a PDF or spreadsheet. The app lists every line it found and shows the original RFQ beside the draft quote. The rep reviews, edits, approves, and explicitly saves the reply as a local email preview. The agent prepares the conversation, and the rep owns it.

### What it does today

- **Reads each line into a standard spec.** Material, grade, form, thickness, size, quantity, and standard. "16 ga" on a stainless line reads as 0.0625 in, and the line names the stainless gauge table it used.
- **Shows the evidence on each line.** Extracted fields link to the RFQ words and their source location. Derived values identify the rule or table used. The original RFQ stays beside the draft for review.
- **Matches each line to RudCo's catalog.** A line gets one match, a few candidates with a question, or "No match". A line with no fit is never forced onto the closest item.
- **Prices a line only from a named, dated source.** RudCo abrasive lines (for example steel shot S-330 and steel grit G-40) are priced from RudCo's own website list price, with the source and date on the line. A line with no sourced price is held and left out of the total.
- **Flags the paperwork the buyer needs.** Mill test reports, certificates of analysis, country of origin, DFARS, REACH, and RoHS. Each flag highlights the trigger words, including requirements the buyer never wrote down but the spec implies. A flag records what the buyer needs. It does not certify RudCo's stock.
- **Shows lead time status on each line.** Unknown lead times say "to confirm". Any 24 to 48 hour stock setting added for the demo is a product assumption, not verified supplier inventory.
- **Asks the buyer instead of guessing.** An unclear line becomes a specific question. The app automatically saves a local question email preview and records its time and placeholder recipient. The line shows "Waiting on buyer" with a local-preview label. Clear lines keep moving. When the rep enters the buyer's answer, the affected line reruns and the rep's earlier edits are kept. No email goes to a real buyer.
- **Keeps the rep in charge.** The rep edits the draft and approves the current revision. Later edits clear that approval. An explicit local send saves an email with matching PDF and CSV attachments, then records "Sent (local preview)", its time and its placeholder recipient. Repeating the send for that revision reopens the saved preview. Real external sending is not connected.
- **Remembers how a buyer writes.** The rep can teach the agent a term for one buyer. The reading is saved with the RFQ it was confirmed on and goes to processing on that buyer's next RFQ.
- **Tracks the 24-hour reply.** RudCo's quote form promises a reply within 24 hours. The quotes list shows a countdown for each RFQ and sorts the soonest due first.

The product is built to run on RudCo's real catalog, inventory, and prices.

## 4. How the solution handles accuracy and uncertainty

Rules read the RFQ first. Material-specific gauge tables, dimensions and unit conversions make the reading reproducible. Extracted fields retain the quoted RFQ words and source location; derived values identify the rule or table used. Stainless 16 gauge, for example, reads as 0.0625 inches. If the RFQ also says 0.060 inches, the difference becomes a buyer question.

When enabled, the model can fill only fields the rules left empty, with evidence quoted from the line. It cannot replace a rules value or invent a price. Invalid responses, a different returned model, or gateway failures leave the rules result intact. The current demo runs with model enrichment disabled; recent Nicrron inference checks returned HTTP502, so we do not present them as successful model readings.

Unknown quantities, conflicting specifications and unsuitable catalog matches keep a line held. Clear lines continue. A buyer answer reruns the relevant line while preserving the rep's edits. Explicitly taught terms apply only to the same buyer and workspace, with a validated source RFQ and line. A confirmed meaning may replace the exact taught phrase, but ordinary remembered values cannot override explicit numbers. An untaught buyer does not inherit that interpretation.

Prices need traceable evidence. The abrasive demo uses named, dated RudCo website list prices, not verified acquisition costs or a promise of available stock. Distributor pricing requires its separate acquisition and comparison evidence before release. Lines without a supported price stay unpriced, and lead times without stock evidence stay “to confirm.” The rep must approve the quote; later edits invalidate that approval.

We verified the complete four-line abrasive RFQ, the missing-quantity question and answer, and the persisted teaching path through processing and matching. The taught thickness matches exactly; the untaught buyer remains held and the unpriced sheet stays unpriced. The latest local processing suite passed 332 examples, and the integrated app check passed 480 Rails tests plus 12 PDF specs. The repaired email, PDF and spreadsheet fixtures all retain their eight RFQ lines.

The [app dry run](../engineering/DRY_RUN-2026-10-10.md) also verified the complete local reply flow: a missing 2,000 lb quantity moves from three Ready lines to four after the answer, with COA flags and the other lines preserved. Approval unlocks the documents; explicit local sending records a receipt and produces downloadable PDF/CSV attachments. An edit after approval blocks the final quote until the rep approves again. No external email was sent.

## 5. Tools and technologies used

- **NicrronNinoo.** The hackathon's sponsor model gateway at `api.nicrron.ai`. The integration requests Claude Opus 5 (model `anthropic/claude-opus-5`). Recent local inference checks returned HTTP 502, so successful live model use is not claimed. It is wired into three places:
  - RFQ processing has a Nicrron provider that asks Claude to fill only the fields the rules left empty.
  - Tisch's catalog matcher has a reader for messy wording such as "sixteen gauge, four by eight, twenty sheets".
  - The distributor pricing agent uses the gateway to split an RFQ into lines. The gateway is never a source for prices, stock, or cost.
  - In the demo as shown, the Rails app runs with the model switched off, so lines are read by the rules parser and matcher.
- **Block Convey / PRISMtrace.** An optional background client records bounded model, outcome and timing metadata without RFQ text, buyer details or model responses. Telemetry failure does not block quoting. The local tests use fake HTTP; project credentials and a verified live trace are still pending.
- **Jev.** A key is configured locally. Yuval's additive compliance integration is pending; no live Jev result is claimed.
- **Ruby and Rails 8.** The quote app.
- **SQLite.** App storage.
- **Prawn.** Builds the quote PDF.
- **letter_opener.** Previews the buyer emails in the browser.
- **Plain Ruby libraries.** RFQ processing (`tools/rfq_processing`), PDF text extraction (`tools/pdf_text`, built on pdf-reader), catalog matching, and distributor pricing.
- **Catalog data.** 96 items taken from RudCo's own public site, with RudCo's website list prices, and 143 constructed sample metals items with no prices.
- **FRED.** Published material price series that the pricing agent reads for context.

## 6. Team members and roles

- **Ken St. Clair.** Product design, user research, and product management. Wrote the product brief, the demo workflow, the research, the brand position, and the style guide.
- **Elad Hirsh.** Front end and UI/UX for the quote application. Built intake, side-by-side evidence review, edits, automatic local question previews, buyer-answer entry, approval invalidation, and explicit local sending with a saved receipt and PDF/CSV attachments.
- **Yuval Gerber.** RFQ processing, plus catalog and benchmark data sourcing. Built text extraction from emails, PDFs, and spreadsheets, the line parser, readiness and compliance rules, buyer questions, and answer reruns.
- **Elad Tisch.** Catalog building, the catalog matching agent, and the market-based pricing agent. Built the RudCo and sample-metals catalogs, the matcher, and the pricing agent.

## 7. Video demo

VIDEO LINK

## 8. GitHub repository

https://github.com/kenxle/columbia-startup-lab-get-hired-hack

---

The sections below are the Devpost story fields. Paste them where Devpost asks for them.

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
