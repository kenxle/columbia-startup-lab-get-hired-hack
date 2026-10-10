# RudCo Quote Desk: Devpost Submission

**Status:** Draft for Ken's review. Paste field by field into Devpost.

**Summary.** The sections below follow the order of the fields the hackathon requires. The extra story sections come after them. Every claim matches the bulletin board as of 14:55 on 2026-10-10 and the [build map](KEN_DESK.md#build-map). Anything partly built or not started is under "What's next".

## Needs Ken

Remove this section before pasting into Devpost.

- [ ] **Video link.** Section 7 says `VIDEO LINK`. Replace it once the video is up.
- [ ] **Block Convey.** I found nothing in the code or docs about how the team used it. It appears only on the Devpost challenge page and in your desk note. Section 5 lists it with no description. How it was used is unknown. Tell me what to write, or ask the team.
- [ ] **Claude in the demo path.** The Rails app runs intake with the language model switched off (`llm: false`), on purpose, so the demo reads lines with the rules parser. The Nicrron connection is built and works (Tisch got HTTP 200 on Opus 5 at 14:53), but no demo screen calls it. Section 5 says so plainly. If you want the model on in the demo, Hirsh has to switch it on, and I will change the text.
- [ ] **Metals prices.** Your promo video shows a full price on a metals line. The app does not: metals lines stay unpriced until Tisch's pricer has five competitor offers per item. Sections 3 and 4 say metals lines are held. The video and this text should not disagree on screen.
- [ ] **Lead times.** All 96 RudCo catalog rows read "to confirm" today. The 24 to 48 hour promise appears only when stock evidence exists. This waits on your answer to desk item 12 (the four SKUs S-330, G-40, S-170, G-25).
- [ ] **Test counts.** Refresh from the latest `script/check` just before submitting. The processing library has two failing examples, both caused by the corrupt demo PDF in the repo. Once Tisch's replacement lands, change that sentence in section 4.

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

RudCo Quote Desk is a web app for the quoting rep. The rep pastes or uploads an RFQ (email text, PDF, or spreadsheet). The app lists every line it found and shows the RFQ beside the draft quote. The rep reviews, edits, approves, and sends. The agent prepares the conversation, and the rep owns it.

### What it does today

- **Reads each line into a standard spec.** Material, grade, form, thickness, size, quantity, and standard. "16 ga" on a stainless line reads as 0.0625 in, and the line names the stainless gauge table it used.
- **Shows where every field came from.** The rep clicks any field and sees the exact words in the RFQ behind it.
- **Matches each line to RudCo's catalog.** A line gets one match, a few candidates with a question, or "No match". A line with no fit is never forced onto the closest item.
- **Prices a line only from a named, dated source.** RudCo abrasive lines (for example steel shot S-330 and steel grit G-40) are priced from RudCo's own website list price, with the source and date on the line. A line with no sourced price is held and left out of the total.
- **Flags the paperwork the buyer needs.** Mill test reports, certificates of analysis, country of origin, DFARS, REACH, and RoHS. Each flag highlights the trigger words, including requirements the buyer never wrote down but the spec implies. A flag records what the buyer needs. It does not certify RudCo's stock.
- **Shows a lead time on each line.** A line shows a lead time only when a sourced stock fact exists. Otherwise it says "to confirm".
- **Asks the buyer instead of guessing.** An unclear line becomes one specific question with choices. Clear lines keep moving. When the rep enters the buyer's answer, only that line reruns, and the rep's earlier edits are kept.
- **Keeps the rep in charge.** The rep edits any field and approves the whole quote. Any edit after approval clears the approval. The agent then builds the buyer's reply: a short email, a PDF, and a spreadsheet. The email opens in a local preview.
- **Remembers how a buyer writes.** The rep can teach the agent a term for one buyer. The reading is saved with the RFQ it was confirmed on and goes to processing on that buyer's next RFQ.
- **Tracks the 24-hour reply.** RudCo's quote form promises a reply within 24 hours. The quotes list shows a countdown for each RFQ and sorts the soonest due first.

The product is built to run on RudCo's real catalog, inventory, and prices.

## 4. How the solution handles accuracy and uncertainty

The design rule is that a number that can be looked up or computed is looked up or computed. The model reads and writes language. It never sets a price.

- **Fixed rules decide the facts.** Gauge tables (one per material), unit conversion, dimension parsing, and the rule for when a line is Ready are all fixed rules. A confidence score never makes a line Ready when evidence is missing.
- **The model fills gaps only under limits.** When a model fills a field, it must quote words from the line, it must be highly confident, and it can never overwrite a value the rules already set.
- **Every field shows its source.** Each field carries the exact RFQ words, their location, and the rule or table used. The rep can check a whole quote by clicking.
- **Unknowns stay empty.** A field the agent cannot read is left empty and becomes a question. It is never filled with a guess.
- **A contradiction becomes a question.** If a line says "16 gauge" and also "0.060 in", the agent asks which one the buyer means. The two numbers are different thicknesses.
- **No match means no match.** The matcher checks each catalog item field by field. A field is an exact match, a near match that becomes a buyer question, or a conflict that rules the item out. A line with no fit says "No match" and is not priced.
- **No source means no price.** A price needs a named, dated source. A line without one is held. Metals sheet and plate lines are held today because the pricer has not found a sourced price for them.
- **Lead times are the same.** No stock evidence means "to confirm".
- **The rep approves every quote.** Approval is explicit, and any edit clears it. A stale approval blocks export.
- **A rerun never overwrites a rep edit.**

How we checked it:

- **Research test set.** 24 of 25 messy lines from Ken's research read as the research expects (report generated 13:32, in `docs/rfq_processing/TEST-RESULTS.md`).
- **App tests.** 418 Rails tests with 3,526 assertions, plus 12 PDF specs, pass (Hirsh, 14:55).
- **Pricing agent.** 98 tests with 594 assertions pass (Tisch, 14:29).
- **Processing library.** 286 examples ran at 14:48. Two fail because the demo PDF in the repo is corrupt, and a replacement is pending.
- **Two demo RFQs.** The first has four abrasive lines, all Ready with RudCo prices and COA flags. In the second, one quantity is missing, so one line asks the buyer and the other three stay Ready. After the answer "2000 lb", all four are Ready again.

## 5. Tools and technologies used

- **NicrronNinoo.** The hackathon's sponsor model gateway at `api.nicrron.ai`. The team uses Claude Opus 5 through it (model `anthropic/claude-opus-5`). It is wired into three places:
  - RFQ processing has a Nicrron provider that asks Claude to fill only the fields the rules left empty.
  - Tisch's catalog matcher has a reader for messy wording such as "sixteen gauge, four by eight, twenty sheets".
  - The distributor pricing agent uses the gateway to split an RFQ into lines. The gateway is never a source for prices, stock, or cost.
  - In the demo as shown, the Rails app runs with the model switched off, so lines are read by the rules parser and matcher.
- **Block Convey.** Sponsor resource named by the hackathon.
- **Ruby and Rails 8.** The quote app.
- **SQLite.** App storage.
- **Prawn.** Builds the quote PDF.
- **letter_opener.** Previews the buyer emails in the browser.
- **Plain Ruby libraries.** RFQ processing (`tools/rfq_processing`), PDF text extraction (`tools/pdf_text`, built on pdf-reader), catalog matching, and distributor pricing.
- **Catalog data.** 96 items taken from RudCo's own public site, with RudCo's website list prices, and 143 constructed sample metals items with no prices.
- **FRED.** Published material price series that the pricing agent reads for context.

## 6. Team members and roles

- **Ken St. Clair.** Product design, user research, and product management. Wrote the product brief, the demo workflow, the research, the brand position, and the style guide.
- **Elad Hirsh.** Front end and UI/UX for the quote application. Built the Rails app: intake, side-by-side review, edits, approval, buyer-question drafts, and the PDF, CSV, and email export.
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

- **Quote app (Hirsh).** A Rails 8 app with SQLite. It holds the review screen, line edits, approval, the buyer-question drafts, and the approved PDF, CSV, and email draft.
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
- **Questions that send themselves.** Each question would go out on its own, and the line would show when it was sent and "Waiting on buyer". A local preview of this is in progress. Sending to a real mailbox is not built.
- **Learning a buyer's reading all the way through.** Teaching "0.060 in means 16 ga" saves and reaches processing. The match still comes back as "close, confirm", so the second RFQ line stays held. The matcher change is not finished.
- **One-click answers from the buyer.** The buyer would click a choice in the email, and the answered line would rerun. The rerun logic is built. The click endpoints are not.
- **Sending the reply on the buyer's original thread.** Today the approved email, PDF, and spreadsheet open in a local preview. A real mailbox is next.
- **Showing where a learned reading came from.** The line would say, for example, "Read as 0.060 in, as you confirmed on RFQ-0001."
- **Redlines.** Old and new values side by side when a rerun changes a line.
- **RudCo's real catalog, inventory, and prices.** The product is written for them. The demo stands in data shaped like theirs.
