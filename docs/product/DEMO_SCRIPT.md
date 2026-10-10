# RudCo Quote Desk: Demo Video Script

**Status:** Draft for Ken's review.

**Summary.** This is the spoken script for the Devpost demo video, in the order of [the video demo in WORKFLOW](WORKFLOW.md#the-video-demo-in-order). It opens on RudCo's 24-hour quote promise and closes on the pitch line, and it shows only what the [build map](KEN_DESK.md#build-map) marks built. Where a step is partly built, the script works around it and says so.

**Read with:** [the product brief](PRD.md), [the brand position](BRAND_POSITION.md) (voice, words to use and avoid), [the build map](KEN_DESK.md#build-map). Marks below come from the build map as checked 2026-10-10 13:53. Re-check them against the bulletin board before recording.

## Needs to be working before recording

Recording window is about 3:45 to 4:30 PM ET. Check these on a fresh `script/dev` run, in this order. A beat whose item is not working gets cut or swapped as the "If not working" column says.

| # | What the script depends on | Build map mark | If not working |
|---|---|---|---|
| 1 | The demo RFQ email with its PDF and spreadsheet attachments (Tisch writes it, Yuval checks it parses). Includes the stainless 16 ga line, an SA-240 or similar trigger word, and RudCo lines (steel shot S-330, P1020 ingot, aluminum 356). | 🟡 step 1: intake works, final email not delivered yet | Use Yuval's draft RFQ email. Paste the body and upload the PDF and CSV. |
| 2 | Paste, PDF and CSV intake through the app. | ✅ step 2 | Excel is not in the app. Save the spreadsheet as CSV first. |
| 3 | "16 ga" on stainless reads as 0.0625 in and names the stainless gauge table. | ✅ step 3 (24 of 25 test lines read as expected) | Rehearse with the exact demo email. If a line misreads, change the email, not the script. |
| 4 | One line each of Ready, Needs the buyer, and No match on the same RFQ. | ✅ step 4 | Edit the demo email until all three show. |
| 5 | A compliance flag with its trigger word highlighted. | ✅ step 5 (flags) | Cut beat 4. |
| 6 | Lead time on a stocked line: "24 to 48 hours". | ✅ step 5 (sourced lead times) | Show "to confirm" and say so. |
| 7 | A price with a named source, and a held line with no price. | 🟡 step 5: RudCo website list prices exist; no pricer for metals lines yet | Beat 5 is written for this state. If Tisch's pricer lands, swap in the alternate lines in the beat. |
| 8 | The drafted buyer question, shown in the local mail preview (letter_opener). | ✅ 6a (draft and download); 🟡 6b (gate agreed, not built) | Show the question as the downloaded draft. |
| 9 | Turning a held line Ready after the buyer's answer, in the app. | 🟡 reruns work in processing; the buyer's click is ⬜ (answer endpoints not built) | Test whether the rep entering the answer on the line turns it Ready. If it does not, end beat 6 at the question email. |
| 10 | Rep review: source on every field, edit, approve the whole quote. | ✅ step 7 | None. This is the core of the video. |
| 11 | Approved quote as PDF, CSV and email draft in the local mail preview. | ✅ 8a | None. This is the core of the video. |
| 12 | Learn the buyer: teach a term, then a second short RFQ from the same buyer reads the gauge line resolved. | 🟡 step 9: taught terms reach parsing; the source line and the second-RFQ demo are not built | Test it with the real second RFQ. If it does not resolve, cut beat 8. |
| 13 | The run finishes in minutes, visibly. | Not on the map | Beat 1 promises "minutes". Keep the screen recording unedited from intake to the lines appearing, or show the clock. |

**Not in the video, because the build map marks it not built or not connected (⬜ or 🟡):**

- The question email sending itself to the buyer (6c).
- The buyer clicking a choice in the email (6d).
- The rep clicking send, and the reply landing on the buyer's original thread (8b).
- A real mailbox receiving the RFQ (step 1).
- A price against a named, dated benchmark on metals lines (no pricer yet).
- The learned reading showing its source ("as you confirmed on RFQ-0001").
- Redlines of old and new values.

## The script

Spoken lines are short on purpose. Read the whole script aloud once with a timer before recording. Cut beat 8 first if it runs over 3:00.

| # | On screen | Ken says | App screen or action | Mark |
|---|---|---|---|---|
| 1 | The buyer's RFQ email, with its PDF and spreadsheet attached. Then the Quote Desk home page. | "RudCo promises a quote within 24 hours. A buyer sends this: a messy email, a PDF, a spreadsheet. Today a person decodes every line by hand. Watch the agent draft the quote in minutes." | Show the email text and the two attachment names. Switch to Quote Desk. Paste the body, upload the files, start the run. Let the run finish on screen. | 🟡 |
| 2 | The review screen: the RFQ on one side, the quote on the other. Each line has a status. | "Here is the RFQ beside the quote. Every line is read into a standard spec. Each line is ready, needs the buyer, or has no match." | Pause on the status column. Point at one Ready line, one Needs the buyer line, and one No match line. | ✅ |
| 3 | The stainless line open, with the source words highlighted in the RFQ. The reading "0.0625 in" and the gauge table name. | "This buyer wrote 16 gauge on stainless. The agent reads that as 0.0625 inches and names the stainless gauge table. RudCo's own challenge treats it as 0.060. So the rep can check the table, not take our word." | Click the thickness field. Show the source words and the table name. | ✅ |
| 4 | A compliance flag on a line, with its trigger word highlighted in the RFQ. | "The buyer never asked for a mill test report. This spec implies one. The flag highlights the word that triggered it." | Click the flag on the line. Show the highlighted trigger word (for example "SA-240"). | ✅ |
| 5 | A steel shot S-330 line with its price, its source, and "24 to 48 hours, in stock". Then a metals line shown held, unpriced. Then the No match line. | "Every price has a source. This steel shot line uses RudCo's list price per pound, and ships in 24 to 48 hours. This line has no benchmark, so it has no price. The agent holds it instead of guessing. And this one is not in the catalog, so it says no match." | Click the price to show its source. Click the held line. Click the No match line. | 🟡 |
| 6 | The drafted question email in the local mail preview: "RFQ-0001, line 3: 16 gauge or 0.060 in?" with the choices. Then the line, now Ready. | "Where the agent is unsure, it writes the buyer one question with choices. Here it is. The rep reviews it before it goes. When the answer comes in, the line turns ready. Clear lines keep moving while one line waits." | Open the question draft in the mail preview. Then enter the buyer's answer on the line and show it turn Ready. Cut the second half if checklist item 9 fails. | 🟡 |
| 7 | The approve step, then the approved quote as PDF, CSV and email draft in the mail preview. | "The rep checks every field, then approves the whole quote. The reply carries price, lead time, and paperwork for each line. Any edit after approval clears it, so the rep always signs off on what goes out." | Click Approve. Open the PDF and the email draft in the mail preview. Make one edit to show approval clearing, then approve again (only if it takes a few seconds). | ✅ |
| 8 | Optional. The buyer memory with the taught term. A second, short RFQ from the same buyer, with the gauge line already resolved. | "The rep taught the agent how this buyer writes 16 gauge. On their next RFQ, that line reads right the first time." | Show the taught term. Paste the second RFQ. Show the gauge line resolved. Cut if checklist item 12 fails. | 🟡 |
| 9 | The Quote Desk header with RudCo's logo and the title "Quote Desk". | "The agent prepares the conversation, and the rep owns it. Every line shows its work." | Hold on the review screen for the last line. | ✅ |

## Notes for Ken

- **Length.** The spoken lines total 285 words, or 263 without the optional beat 8 (counted with a script on the table above). Time one read-aloud to confirm it fits under 3 minutes with the screen actions.
- **Order differs from WORKFLOW in one place.** WORKFLOW puts the second RFQ (learn the buyer) after the closing framing. Your brief says to close on the pitch line, so this script puts beat 8 before the close.
- **The "in minutes" line needs a visible run.** The PRD says the line holds only if the video shows the draft in minutes. Beat 1 keeps the run on screen for that reason.
- **Price wording.** Beat 5 calls the steel shot price "RudCo's list price", which is what the catalog holds (RudCo's website list price per pound). The script never says "benchmark" for it. If Tisch's pricer lands before recording, replace the first two sentences of beat 5 with: "Every price sits beside a named, dated benchmark, and the line says why it is competitive. It tracks published metal cost plus RudCo's margin." Then re-read the mark as ✅.
- **Words avoided** from the brand position: "AI-powered", "cheapest", "real-time", "certified", "instant", "guaranteed", "hands-free".
- **The video does not mention Claude.** The Claude reading step had not run on the live API at the last build-map check (the demo runs on the rules parser, which the test set covers). Say it in the Devpost text only if it has run by then.
