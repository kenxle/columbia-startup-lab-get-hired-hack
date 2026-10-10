# Demo flow walk, 2026-10-10

**Walked by:** Claude, for Ken. Branch `test/e2e-demo-flow`, on `origin/main` at `0a9d977`. Fresh worktree database, server on port 3210, models off, no real email.

**What I walked:** every beat of [the demo script](DEMO_SCRIPT.md#the-script), as a rep would. I used three RFQs:

- The abrasive demo pair from `tools/rfq_processing/spec/fixtures/demo_pair/`. The complete one matches RFQ-0014 (four Ready, USD 1,810). The quantity-missing one matches RFQ-0017 (three Ready, one held, USD 1,010).
- The Northline RFQ in [demo_rfq/](demo_rfq/README.md): email body pasted, PDF attached.
- The second Northline RFQ, for beat 8 (learn the buyer).

RFQ numbers differ from Ken's machine. Each new browser session gets 12 sample RFQs first, so my pair became RFQ-0013 and RFQ-0014. RFQ-0014 and RFQ-0017 exist only in the database on the machine that made them.

## Top findings

1. **No line shows "No match" on the Northline RFQ.** Beats 2 and 5 point at one. Line 8 (hex cap screws) reads as "screw, 0.25 in". The app holds it with the question "Please give the material." Its status is Question to send, then Waiting on buyer. The demo RFQ README expects No match. [Beat 2](#beat-2-the-review-screen), [beat 5](#beat-5-price-held-line-no-match).
2. **The question email tells the buyer about our internal pricing.** Six of the seven Northline questions say "The price is to be confirmed by the rep before this line can be quoted." Questions also go to the local preview on their own about a second after intake, before the rep looks. Beat 6 says "The rep reviews it before it goes." [Beat 6](#beat-6-the-buyer-question).
3. **Every line says "Lead time: to confirm".** Beat 5 says the steel shot "ships in 24 to 48 hours". Nothing on screen supports that line. The checklist marks item 6 (sourced lead times) as working. In this build it is not. [Beat 5](#beat-5-price-held-line-no-match).
4. **"The line turns Ready" works only on the abrasive RFQ.** On RFQ-0017 (quantity missing), answering "2000 lb" makes the line Ready and the total USD 1,810. On Northline, the gauge line never reaches Ready. Picking "0.0625 in" leads to a second question about which SKU. Picking the SKU is refused with "This catalog choice needs rep review". Metals lines have no price anyway. So beat 6 has to use RFQ-0017 for its second half. [Beat 6](#beat-6-the-buyer-question).
5. **Learn the buyer works halfway.** On the second RFQ, "0.060 in" reads as 0.0625 in. The source note says "as the rep taught on RFQ-0017". Another buyer with the same words still gets the question, which is right. But the line stays held with "No catalog item". It asks the buyer "fits 1 catalog items ... Which one do you mean?". The script says the line "reads right the first time". [Beat 8](#beat-8-learn-the-buyer).
6. **The sent email and PDF read like internal notes.** The sent email starts "Draft, not sent". Prices carry raw timestamps like "As of: 2026-10-10T17:04:39Z". Every line says "A list price, not a quote". The local email page scrolls sideways: the page is 1760 px wide in a 1440 px window. [Beat 7](#beat-7-approve-pdf-csv-email).

Speed is not a problem. Every step answered in under a second, apart from one cold start (see beat 1).

## Beat 1: the RFQ comes in

**Works, with two rough spots.**

- Pasting the Northline email and attaching the PDF reads all eight lines. The source panel shows the email and the PDF text one after the other. A CSV upload on its own also reads eight lines.
- The form takes one file. The script says "upload the files" (PDF and spreadsheet). Paste the body and attach one file.
- My first Northline run after server start showed "Status: Running" and needed a click on "Refresh processing status". Every later run finished before the page loaded, in under a second. The page does not refresh itself. Do one warm-up run before recording.
- The message after saving always says "Processing is queued. Refresh the quote to see the results." It says this even when the results are already on screen below it. On camera this reads as if something is still pending.

Screenshots: [form](flow_walk/b1_new_rfq_form.png), [form filled](flow_walk/b1_new_rfq_filled.png), [after save](flow_walk/b1_after_save.png), [first run still running](flow_walk/b1_first_run_still_running.png), [home](flow_walk/00_home.png).

## Beat 2: the review screen

**Works for Ready and held. Broken for No match.**

- The RFQ sits on the left and the quote lines on the right, with a status on each line.
- Northline: one Ready (line 4, steel shot), seven held, USD 800.00. Line 2 (0.060 in) is the "needs the buyer" line.
- No line has the status No match (top finding 1).
- The status of held lines changes on its own. On first load they say "Question to send". After a refresh they say "Waiting on buyer", because the questions went to the local preview on their own.
- The abrasive pair is clean: four Ready and USD 1,810, or three Ready plus one held and USD 1,010.
- On the home page the reference wraps onto two lines ("RFQ-" then "0001"). There are two names for one button: "Load RFQ example" in the page and "Load demo RFQ" in the sidebar.

Screenshots: [Northline review](flow_walk/b2_northline_review.png), [quantity-missing review](flow_walk/b2_incomplete_review.png).

## Beat 3: 16 gauge on stainless

**Works.**

- Line 1 reads thickness 0.0625. Opening the field shows the source words "16 ga", "page 1, line 12, chars 22-26", and "16 gauge on the stainless steel table is 0.0625 in".
- The table name reads oddly on camera: "(Metal Supermarkets sheet metal gauge chart (tube wall: Wikipedia, Sheet metal))". It has nested brackets and mentions tube wall and Wikipedia.
- The source panel is narrow. The PDF text loses its column layout and wraps.

Screenshot: [thickness source](flow_walk/b3_gauge_thickness_source.png).

## Beat 4: compliance flag

**Works.**

- Line 3 (SA-240 316L plate) shows three flags: ASME SA code material, EN 10204 3.1 certificate, and mill test report. "SA-240" is highlighted in the RFQ.
- The mill test report flag quotes the word "cert" as its trigger, which looks odd next to the others.
- The steel shot line also gets "Mill test report required", from "MTRs required on all steel". Earlier notes say this is intended. An MTR on an abrasive may still look wrong to a viewer who knows the trade.

Screenshots: [flags](flow_walk/b4_compliance_flags.png), [highlight in the RFQ](flow_walk/b4_source_highlight.png).

## Beat 5: price, held line, no match

**Price works. Lead time and No match are broken.**

- Steel shot S-330: USD 0.40 per lb, USD 800.00. The price source reads "RudCo website list price, rud-co.com, fetched 2026-10-10".
- The pricing box shows "As of 2026-10-10T17:04:39Z" as a raw timestamp.
- The P1020 ingot line is held and unpriced: "Not priced. Held lines carry no price until they are ready and matched."
- Lead time reads "to confirm" on every line, steel shot included (top finding 3).
- The screw line shows "No catalog item" but not the No match status (top finding 1).
- When a line is selected, the RFQ panel also highlights words in other lines. For example, line 1 of the abrasive RFQ highlights "Steel shot" on line 3 and every "COA".

Screenshots: [steel shot price](flow_walk/b5_steel_shot_price.png), [held ingot](flow_walk/b5_held_ingot.png), [screw line](flow_walk/b5_no_match_screws.png).

## Beat 6: the buyer question

**Works on RFQ-0017. Confusing on Northline.**

On the abrasive RFQ with the quantity missing:

- "Review buyer questions (1)" opens one draft. "Open local email preview" saves it and shows it, with "No email was sent to the buyer".
- The question reads "Line 1: Please give the quantity, quantity unit." The wording is clumsy, and there are no choices to click.
- Entering "2000 lb" as the buyer's answer makes the line Ready. The total goes to USD 1,810, and approval resets.

On Northline:

- The script's question "RFQ-0001, line 3: 16 gauge or 0.060 in?" does not match the app. The gauge question is on line 2. The RFQ number depends on the database.
- The line 2 question is good: "0.06 in is written. 16 gauge stainless steel is 0.0625 in. Is 0.06 in exact, or is 16 gauge acceptable?" It offers four choices. It shows "0.06 in" where the buyer wrote "0.060 in".
- The other six questions are about our price, not the buyer's words (top finding 2).
- Line 2 never reaches Ready (top finding 4).

Screenshots: [questions page](flow_walk/b6_questions_page.png), [question email](flow_walk/b6_question_email_preview.png), [line Ready after answer](flow_walk/b6_line_ready.png), [Northline questions](flow_walk/b6_northline_questions.png), [line 2 choices](flow_walk/b6_line2_answer_choices.png), [after choosing 16 ga](flow_walk/b6_line2_after_choosing_16ga.png), [after choosing the 2B SKU](flow_walk/b6_line2_after_choosing_2B.png).

## Beat 7: approve, PDF, CSV, email

**Works. The documents need polish.**

- Tick the review box and click "Approve quote". "Prepare email and PDF" opens the email, PDF and CSV.
- The PDF has two pages, shows USD 1810.00 and the price source on each line. The CSV has every line and the subtotal 1810.00.
- "Send approved quote (local preview)" saves the email with both files attached. The quote then shows "Sent (local preview)".
- An internal note saved after approval clears the approval. The final quote page then sends you back to review. Re-approving takes one click.
- Copy issues that will show on camera:
  - the sent email still says "Draft, not sent" near the top
  - "As of: 2026-10-10T17:04:39Z" on every line, and "Approved: 2026-10-10T19:37:29Z" on the PDF
  - "A list price, not a quote" on every line of a quote
  - the full catalog description on every line ("High-carbon cast steel shot for cleaning, peening, and surface preparation")
  - money without a thousands comma ("USD 1810.00") in the email and PDF, but with one ("USD 1,810.00") on screen
- The local email page scrolls sideways. Long lines run past the panel edge.

Screenshots: [approve box](flow_walk/b7_approve_form.png), [approved](flow_walk/b7_approved.png), [email and documents](flow_walk/b7_final_quote.png), [PDF page 1](flow_walk/b7_quote_pdf_page-1.png), [sent email](flow_walk/b7_sent_email.png), [local inbox](flow_walk/b7_local_previews.png), [edit clears approval](flow_walk/b7_edit_clears_approval.png).

## Beat 8: learn the buyer

**Half works.**

- "Teach a buyer phrase" on Northline line 2 saves "0.060 in" as thickness 0.0625 for Northline Fabrication.
- The second RFQ reads 0.0625 with the note "Read as thickness 0.0625 in, as the rep taught on RFQ-0017".
- The same words from Harbor Fabrication still read 0.06 and get the question.
- The line stays held with no catalog item. It asks the buyer to pick from one SKU (top finding 5). The choice label reads "Agrees on grade, material, finish, size, size, form. to confirm: thickness: close, confirm."
- The form teaches one field at a time. The README example teaches gauge and thickness together.

Screenshots: [teach form](flow_walk/b8_teach_form.png), [taught](flow_walk/b8_taught.png), [second RFQ](flow_walk/b8_second_rfq.png), [second RFQ thickness](flow_walk/b8_second_rfq_thickness.png).

## Beat 9: the close

**Works.** The sidebar shows the RudCo mark with "RudCo" and "QUOTE DESK" on every screen. The review screen also fits a phone-width window (390 px) with no sideways scroll.

Screenshots: [closing review](flow_walk/b9_closing_review.png), [home after the walk](flow_walk/b9_home_after.png), [phone width](flow_walk/x_mobile_review.png).

## Tests

The Playwright tests in [test/e2e/](../../test/e2e/README.md) walk these beats. Tests named `GAP:` describe top findings 1, 2, 3 and 5. They pass while the gap exists and will start failing once it is fixed.
