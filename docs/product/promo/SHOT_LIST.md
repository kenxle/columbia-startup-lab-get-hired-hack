# Promo Shot List: RudCo Quote Desk, 30 seconds

**Status:** Draft for Ken's review.

**Summary.** The new cut opens on RudCo's 24-hour quote promise, shows the gauge trap and a compliance flag, and closes on "Every line shows its work." and the pitch line. It swaps the hand-built quote card for real screens from the running app, so the video shows only what the build does today, and it marks the two shots that depend on unfinished work.

**Read with:** [brand position](../BRAND_POSITION.md), [style guide](../STYLE_GUIDE.md), [PRD value props](../PRD.md#the-job-to-be-done), [demo script](../DEMO_SCRIPT.md), [build map and status](../KEN_DESK.md#build-map). Sources for the current cut: [promo.html](promo.html), [vo.py](vo.py), [music.py](music.py), [capture.js](capture.js).

## Needs your call

- [ ] **Metals prices in the promo.** Shot 6 shows a dated benchmark price only if Tisch's pricer lands and you approve the "indicative price" idea (open item 11 on [Ken's Desk](../KEN_DESK.md#needs-your-call)). Without it, shot 6 falls back to RudCo's list price with its source. Both versions are written below.
- [ ] **Blueprint look vs the style guide.** The current cut uses a navy blueprint frame, gold labels and gold rules. The [style guide](../STYLE_GUIDE.md#how-the-workspace-should-look-like-rud-cocom) allows gold in one place only (the rule under the sidebar product name). Keep the blueprint look for the promo, or move gold off the labels and rules? This list keeps the blueprint look and leaves gold on the frame and rules.

## What the current cut has

Read from [promo.html](promo.html) (on-screen text and timing) and [vo.py](vo.py) (voiceover). The mp4 and the music are both 30.0 seconds. The voiceover clips run 3.3 to 6.0 seconds each. The repo files do not say when each clip starts, so each line sits with its scene.

| Time | Shot | On-screen text | Voiceover |
|---|---|---|---|
| 0:00 to 0:05.4 | Sheet 1/5. A messy RFQ email types out. Three phrases get a gold underline. Three numbered notes appear. | "RFQs arrive as shorthand." Email lines: "304 SS sheet 16ga 4x8, qty 20", "Sq tube A513/A500 1x1 .065w", "Plate SA-240 304L 3/16, 6 pcs". Notes: "16ga: which table?", "A513/A500: two specs", "SA-240: unwritten paperwork". | "RFQs arrive as shorthand. Every line hides a trap." (9 words) |
| 0:05.5 to 0:11.1 | Sheet 2/5. Two drawn sheets with thickness arrows, a 4.2% delta box, then a cost line. | "Same line. Two different sheets." "304 SS, 16 GA (STAINLESS TABLE) 0.0625 in" against "STAINLESS 304, 0.060 IN 0.0600 in". "DELTA 4.2%". "$250K to $450K: One wrong stainless grade, caught after purchase." Source: self-reported by a supplier, r/metalworking. | "Sixteen gauge stainless is not point-oh-six-oh inch. And misreads surface after the metal is cut." (17 words) |
| 0:11.2 to 0:15.5 | Sheet 3/5. A large quote on navy. | "Opacity is a tax on industrial procurement." (RudCo, LinkedIn, 2026-04-20). Then "Precision. Transparency. Trust." | "Opacity is a tax on industrial procurement." (7 words) |
| 0:15.6 to 0:25.5 | Sheet 4/5. A hand-built HTML quote card with three rows (Ready, Needs the buyer, Ready), numbered notes, then a "REP APPROVED" stamp. | Headlines in turn: "The same messy email, read right." "Every line shows where it came from." "Unclear lines become one question." "Your rep approves and sends." Card: "Priced vs. dated benchmark", "Ships in 24 to 48 hours", "Mill test report needed, triggered by SA-240", "Approve and send". | "Quote Desk shows where every answer came from, flags the paperwork, and asks when it can't tell. Your rep approves and sends." (22 words) |
| 0:25.6 to 0:30 | Sheet 5/5. RudCo mark with "RudCo / QUOTE DESK", gold rule, tagline, pitch line. | "Every line shows its work." "The agent prepares the conversation. The rep owns it." "PRECISION. TRANSPARENCY. TRUST." | "RudCo Quote Desk. Every line shows its work." (8 words) |

The current voiceover is 61 words (counted with a script). The cut does not mention the 24-hour promise, and the quote card is a mock, not the app.

## Proposed shot list

Eight shots, 30.0 seconds. The voiceover is 66 words (see [Voiceover word count](#voiceover-word-count)). The old cut ran 61 words at about 2.6 words per second, so this one is a little brisker. If a read-through runs long, cut the voiceover on shot 2 (4 words) and keep its picture.

**Status marks** come from the [build map](../KEN_DESK.md#build-map) and [Where things stand](../KEN_DESK.md#where-things-stand), checked 14:26 on 2026-10-10. Built means the running app does it today. Depends means the shot needs work that is not finished.

| # | Time | Shot (what is on screen) | On-screen text | Voiceover | Source | Mark |
|---|---|---|---|---|---|---|
| 1 | 0:00 to 0:03.5 | The Quotes list, cropped to the Due column. Rows show "Due in 1h 00m" style countdowns beside RFQ titles and buyer names. Use rows that are not overdue. | "Quote within 24 hours." Small line: "RudCo's own promise." | "RudCo promises a quote within 24 hours." (7) | Real app: `http://127.0.0.1:3100/` (Quotes list). The promise comes from RudCo's quote form, cited in the [PRD](../PRD.md#the-job-to-be-done). | Built (countdowns are on the list today) |
| 2 | 0:03.5 to 0:07 | The messy RFQ types out, with the three gold underlines on `16ga`, `A513/A500` and `SA-240`. No side notes. | "RFQs arrive as shorthand." | "RFQs arrive as shorthand." (4) | Reuse scene 1 of promo.html. Shorten the typing to about 1.2 seconds and drop the three numbered notes. | Built (it is a drawn scene) |
| 3 | 0:07 to 0:11.5 | The two drawn sheets. Left: 0.0625 in, labeled with the stainless gauge table. Right: 0.0600 in. The 4.2% delta box sits between them. | "304 SS, 16 GA (stainless gauge table) = 0.0625 in" against "0.060 in". "Delta 4.2%". | "Sixteen gauge stainless reads point-oh-six-two-five inch, by the stainless gauge table." (11, counted with the numeral "0.0625") | Reuse scene 2 of promo.html. Trim the timing. Drop the "$250K to $450K" line and its source note. | Built (drawn scene). The 4.2% is (0.0625 - 0.060) / 0.060, computed by script. |
| 4 | 0:11.5 to 0:15.5 | The real review screen on the stainless line. Click the thickness field. The RFQ words `16ga 4x8` light up on the left and the reading "0.0625 in" with "stainless gauge table" shows on the right. | Chip: "Accurate". Caption: "Read from `16ga` using the stainless gauge table." | "Every field shows the words and rule behind it." (9) | Capture from `http://127.0.0.1:3100/`: open the demo RFQ, open the stainless line. | Built (build map step 3 and step 7). Needs the final demo RFQ email, still with Tisch. Use the sample RFQ until it lands. |
| 5 | 0:15.5 to 0:19 | The real compliance flag on the plate line, with `SA-240` highlighted in the RFQ text. | Caption: "Mill test report needed. Triggered by `SA-240`." | "It flags unwritten paperwork and names the trigger word." (9) | Capture from the app: click the flag on the SA-240 line. | Built (build map step 5, flags) |
| 6 | 0:19 to 0:22.5 | The real price and lead time on a Ready line, then the held line beside it. | Chip: "Competitive". Version A (pricer lands): "Priced against a dated benchmark." Version B (fallback): "RudCo list price, source shown." Both: "Ships in 24 to 48 hours." | "Prices show their source and date." (6) | Capture from the app. | Depends. Version A needs Tisch's pricer pushed and your call on indicative prices. Version B is built today (list prices on RudCo items, sourced lead times). On a line with no benchmark, show the held state. |
| 7 | 0:22.5 to 0:25.5 | The drafted buyer question ("RFQ-0001, line 3: 16 gauge or 0.060 in?") in the mail preview. Cut to the rep clicking "Approve quote". A short "REP APPROVED" stamp lands over it. | Chip: "Faster". Caption: "One question. One approval." | "Unclear lines become one question." (5) | Capture the question draft and the Approve quote button from the app. The stamp is a motion overlay from scene 4 of promo.html. | Built for the draft and the approval. The question does not send itself and the buyer cannot click an answer yet, so show the draft only. |
| 8 | 0:25.5 to 0:30 | The L3 lockup on navy: RudCo round mark, "RudCo", "QUOTE DESK". Gold rule. Tagline, then pitch line. Footer: "Precision. Transparency. Trust." | "Every line shows its work." "The agent prepares the conversation, and the rep owns it." | "Every line shows its work. The agent prepares the conversation, and the rep owns it." (15) | Reuse scene 5 of promo.html. Change the pitch text. Hold the final frame for the last half second. | Built (drawn scene) |

### Value props on screen

- **Accurate:** shots 3, 4 and 5 (the gauge table, the source words, the flag with its trigger word).
- **Competitive:** shot 6 (a price with its source and date). We never say cheapest, per the [brand position](../BRAND_POSITION.md#words-to-use-and-avoid).
- **Faster:** shot 1 (24 hours), shot 6 (24 to 48 hour lead time) and shot 7 (one question, one approval).

### Voiceover word count

Counted with a script on these lines.

| Shot | Line | Words |
|---|---|---|
| 1 | RudCo promises a quote within 24 hours. | 7 |
| 2 | RFQs arrive as shorthand. | 4 |
| 3 | Sixteen gauge stainless reads 0.0625 inch, by the stainless gauge table. | 11 |
| 4 | Every field shows the words and rule behind it. | 9 |
| 5 | It flags unwritten paperwork and names the trigger word. | 9 |
| 6 | Prices show their source and date. | 6 |
| 7 | Unclear lines become one question. | 5 |
| 8 | Every line shows its work. The agent prepares the conversation, and the rep owns it. | 15 |
| | **Total** | **66** |

The script prints 69 with the longer shot 7 line ("Unclear lines become one question. The rep approves."). This list uses the shorter line, and the rep's approval is shown on screen instead.

### Music and audio

Keep [music.py](music.py) as the base: it already builds a build on sheet 4 and a held chord on the close. Retime its section changes to the new shots: the beat starts at shot 4 (0:11.5) and the final chord lands at shot 8 (0:25.5). Re-record the voiceover from the new lines with [vo.py](vo.py), same voice and instructions.

## Changes from the current cut

**Keep**
- The blueprint frame, title block and the typed-out email.
- The two-sheet gauge trap, with the 4.2% delta box.
- The closing lockup with the RudCo mark, the tagline "Every line shows its work." and the footer "Precision. Transparency. Trust."
- The music bed and the voice.

**Change**
- Open on the 24-hour promise (new shot 1) instead of the shorthand email.
- Replace the hand-built quote card with real screen captures (shots 4 to 7). The card is a drawing, so it can show things the app does not do.
- Change the pitch line on the close to the brief's wording: "The agent prepares the conversation, and the rep owns it." The current cut splits it into two sentences.
- Change "Your rep approves and sends" and the "Approve and send" button. Sending is not built. The app's button reads "Approve quote".
- Change the card's "Priced vs. dated benchmark" and "Metal cost, 2026-10-10" text. The pricer is not built into the app yet. Use shot 6, version A or B.
- Change the title block from "n/5" sheets to "n/8".
- Check the close lockup against L3 ratios. L3 is a 32 px mark, an 18 px name and an 11 px label. At 4 times the size that is a 128 px mark, a 72 px name and a 44 px label. The current close uses a 128 px mark, a 92 px name and a 34 px label.

**Add**
- The 24-hour promise (shot 1), a requirement in the [PRD](../PRD.md#the-job-to-be-done) and the opener in the [demo script](../DEMO_SCRIPT.md).
- Value-prop chips: Accurate, Competitive, Faster.
- A real compliance flag with its trigger word (shot 5). The current cut shows it only inside the drawn card.
- The drafted buyer question (shot 7).

**Drop**
- The "Opacity is a tax on industrial procurement." scene. There is no room in 30 seconds. The line stays in the [brand position](../BRAND_POSITION.md#how-this-aligns-with-rudcos-brand) and can go in the Devpost text.
- The "$250K to $450K" line. It is self-reported by one supplier on Reddit, and the gauge shot makes the point without it.
- The three side notes on shot 2 and the four side notes on the old quote card. The real screens carry that information.

## How this complements the demo video

The [demo script](../DEMO_SCRIPT.md) is the long walk-through, from intake to the approved PDF. The promo is the trailer for it. It uses the same two proof points (the gauge table and the flagged trigger word) and the same closing lines, and it leaves out intake, the held and No match lines, the learn-the-buyer beat, and the approved PDF. Those stay in the demo.

## Left out because the build does not show it today

- **Alternates:** "Option A: 16 ga, 0.0625 in" and "Option B: exactly 0.060 in", each with its own price. The app shows options apart from the subtotal, but the prices wait on the pricer ([Where things stand](../KEN_DESK.md#where-things-stand)). Add it to a later cut.
- **The question emailing itself, the buyer clicking an answer, and the rep sending the reply.** None of the three is built.
- **"Draft in minutes."** The demo script needs a visible, timed run for this claim. The promo does not show one, so it makes no such claim.
- **Learned buyer terms** with their source ("as you confirmed on RFQ-0001"). Waiting on Yuval's push.

## To capture before editing

1. The Quotes list, Due column, non-overdue rows (shot 1).
2. The stainless line, with the thickness field clicked (shot 4).
3. The SA-240 flag open (shot 5).
4. A Ready line with price and lead time, plus a held line (shot 6).
5. The drafted question in the mail preview, then the Approve quote click (shot 7).

All five come from `http://127.0.0.1:3100`. Capture at 1920 by 1080, on the demo RFQ once Tisch's email lands.
