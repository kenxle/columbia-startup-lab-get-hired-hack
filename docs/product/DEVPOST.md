# RudCo Quote Desk: Devpost Submission

**Status:** Draft for Ken's review.

**Summary.** This is the Devpost text for RudCo Quote Desk, an agent that turns a messy industrial RFQ into a quote the rep can check and send. Every claim matches the [build map](KEN_DESK.md#build-map) as checked 2026-10-10 13:53; anything marked partly built or not started is under "What's next".

## Before you submit

Remove this section before pasting into Devpost.

- **Refresh the numbers.** The test counts (287 app tests, 150 processing specs, 24 of 25 test lines) come from the 13:47 and 13:36 bulletin posts. Update them from the latest `script/check` and [TEST-RESULTS.md](../rfq_processing/TEST-RESULTS.md).
- **Claude on the live gateway.** At the last check the Claude reading step had not run against the live sponsor gateway. If it has not run by submission, replace the Claude sentence in "How we built it" with: "A Claude reading step is built and tested on recorded responses; the demo runs on the rules parser."
- **Which Claude model.** The architecture doc says Opus 5.5. Hirsh's 13:40 bulletin post requires Opus 5 for every process, because the sponsor gateway lists Opus 5 only. This draft says Opus 5.
- **Pricing wording.** The pricer is not built. If Tisch's pricer lands, move "A named, dated benchmark on every metals line" from "What's next" to "What it does".
- **Add the video link and repo link** where Devpost asks for them. The repo is public.
- **The Devpost challenge page asks for NicrronNinoo and Block Convey.** The [RudCo profile](../research/20261010.02_rudco_profile/rudco_profile.md#gaps) flags this as unexplained. Your 13:36 desk note says they are free sponsor resources, not a requirement. The draft names Nicrron because the team used it; confirm the spelling and add Block Convey only if the team used it.

## Inspiration

RudCo supplies metals, abrasives, and aggregates to industrial buyers. Its quote form promises a reply within 24 hours. The challenge says that today a person decodes every line by hand.

That work is slow, and a wrong guess costs real money. One buyer writes "304 SS sheet 16ga 4x8". Another writes "Stainless 304, 0.060 in, 48 x 96". Both mean a sheet, but the rep has to work out the grade, the thickness (a gauge number only implies it, and gauge tables differ by material), the size, the standard, and the paperwork. A wrong read on grade or thickness becomes a wrong quote, a lost order, or a return.

RudCo's founder describes the rep's role this way: "Technology can handle more of the coordination and give those people better information for the conversation." ([Digital Journal, 2026-08-21](https://www.digitaljournal.com/article/ai-infrastructure-boom-reshapes-industrial-materials-procurement/)). We built to that idea. The agent prepares the conversation, and the rep owns it.

## What it does

RudCo Quote Desk reads a buyer's RFQ and drafts a quote for the rep to check and send. The rep sees the RFQ beside the quote, one line at a time.

- **Reads each line into a standard spec.** Material, grade, form, thickness, size, quantity, and standard. "16 ga" on a stainless line reads as 0.0625 in, and the line names the stainless gauge table it used.
- **Shows where every field came from.** The rep clicks any field and sees the exact words in the RFQ behind it.
- **Matches each line to RudCo's catalog.** A line gets one match, a few candidates with a question, or "No match". A line with no fit is never forced onto the closest item.
- **Flags the paperwork the buyer needs.** Mill test reports, certificates of analysis, country of origin, DFARS, REACH, and RoHS. Each flag highlights the trigger words, including requirements the buyer never wrote down but the spec implies. A flag records what the buyer needs. It does not certify RudCo's stock.
- **Shows a lead time on each line.** Stocked lines use RudCo's 24 to 48 hour promise. Anything else says "to confirm".
- **Holds a line it cannot price.** A line with no source for its price is held and left out of the total. The agent does not invent a number.
- **Asks the buyer instead of guessing.** An unclear line becomes one specific question with choices. Clear lines keep moving while one line waits.
- **Keeps the rep in charge.** The rep edits any field and approves the whole quote. Any edit after approval clears the approval. The agent then builds the buyer's reply: a short email, a PDF, and a spreadsheet, with price, lead time, and paperwork on each line.
- **Remembers how a buyer writes.** The rep can teach the agent a term for one buyer, and later RFQs from that buyer use it.

## How we built it

The team built it in one day. Each part has one owner.

- **Quote app (Hirsh).** A Rails 8 app in Ruby with SQLite. It holds the review screen, line edits, approval, the buyer-question drafts, and the approved PDF, CSV, and email draft. Prawn builds the PDF. letter_opener previews the emails in the browser.
- **RFQ processing (Yuval).** A plain Ruby library that extracts text from the email body, PDFs, and spreadsheets, keeping the page and row of every line. It reads each line into fields, applies fixed rules for gauge tables, units, and dimensions, and decides by rule whether a line is ready. Claude (Opus 5, through the hackathon's sponsor gateway) reads the messy text into fields and words the buyer questions. A rule value is never overwritten by the model. When a buyer answers a question, the library reruns only the answered lines.
- **Matching and catalog (Tisch).** A matcher that checks each catalog item field by field. A field is an exact match, a near match that becomes a buyer question, or a conflict that rules the item out. The demo catalog has 96 items taken from RudCo's own public site, with RudCo's website list prices, and 143 constructed sample metals items.
- **Product (Ken).** The brief, the demo workflow, the research, the brand position, and the style guide. The look uses RudCo's own palette and logo.

The split between rules and the model is the main design choice. A number that can be looked up or computed is looked up or computed. The model reads and writes language, and it never sets a price.

**Built with:** Ruby, Rails 8, SQLite, Prawn, letter_opener, Claude through the hackathon's sponsor gateway (Nicrron).

## Challenges we ran into

- **The gauge trap.** The same gauge number means a different thickness for different materials. The challenge example treats 16 gauge as 0.060 in, and the stainless gauge table says 0.0625 in. We keep a table per material and show which one each line used, so the rep can check it.
- **No sample catalog or prices from RudCo.** We built the catalog from RudCo's own public site and added constructed sample metals items. The prices on RudCo items are RudCo's website list prices, not quote prices. The sample metals items have no prices.
- **Pricing without making numbers up.** We hold any line that has no sourced price and leave it unpriced. The metals pricer is not finished, so some metals lines show as held in the demo. We kept the rule.
- **Four people building at once.** We agreed on one result format between processing and the app, with stable line IDs and a revision ID on every run. That let each part change without breaking the others.

## Accomplishments that we're proud of

- **Every field shows its source.** The rep can check the whole quote by clicking, without rereading the email.
- **24 of 25 research test lines read as expected.** The processing library has 150 passing specs, and the app has 287 passing tests.
- **Honest on the hard cases.** A no-match line says "No match". A contradiction between "16 gauge" and "0.060 in" becomes a question. A rerun never overwrites a field the rep edited.
- **It looks and reads like RudCo's tool.** It uses RudCo's palette, its logo unchanged, and its own words for the paperwork it already promises customers.

## What we learned

- **The rep needs the reasoning behind a line.** A confidence number does not help a rep who has to defend a quote. The words in the RFQ and the table used to read them do.
- **Rules first, model second.** Gauge tables, unit conversion, and readiness are fixed rules. The model handles the language around them. That kept the accuracy checkable.
- **Ask, don't guess, and keep the rest moving.** One unclear line should not hold up the clear ones.

## What's next

These are designed and partly built. We list them here so the submission does not claim them.

- **A named, dated benchmark on every metals line.** The pricer is not built yet. Free producer price series for steel and aluminum are the sources we researched. The quote would say the price tracks published metal cost plus RudCo's margin.
- **Questions that send themselves.** The rule for when the agent is confident enough to email a question on its own is agreed. The sending is not built.
- **One-click answers from the buyer.** The buyer would click a choice in the email, and the answered line would rerun. The rerun logic is built in the processing library. The click endpoints are not.
- **Sending the reply on the buyer's original thread.** Today the approved email, PDF, and spreadsheet open in a local preview. A real mailbox is next.
- **Showing where a learned reading came from.** The line would say, for example, "Read as 0.060 in, as you confirmed on RFQ-0001."
- **Redlines.** Old and new values side by side when a rerun changes a line.
- **RudCo's real catalog, inventory, and prices.** The product is written for them. The demo stands in data shaped like theirs.
