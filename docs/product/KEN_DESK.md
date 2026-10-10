# Ken's Desk

**What this is:** Ken's working page for the hackathon. The top holds what needs Ken now. Comment on any item, and Claude answers on the page and updates the work. Hacking ends at **4:30 PM ET**, and the Devpost submission needs a video.

**Last updated:** 2026-10-10 15:54, from the bulletin board through 15:51.

## Needs your call

- [ ] **19. Record.** A fresh walkthrough passed on Hirsh's machine at 15:46 (RFQ-0023). **Use fresh intake, not the old demo records:** stored RFQs keep the old "to confirm" lead times. Hirsh's walkthrough: 3 Ready and 1 held at USD 1,010, the question goes to the local inbox, answer "2000 lb", 4 Ready at USD 1,810, COA flags, lead times 24 to 48 hours, approve, send, PDF and CSV download, no browser errors.
- [ ] **18. Send the real Jev key in WhatsApp** (`~/Desktop/jev_for_team/JEV_API_KEY_value.txt`). Yuval's agent cannot read WhatsApp, so Yuval saves it into his own git-ignored env file.
- [ ] **17. Devpost.** The About field is pasted from [its page](devpost/ABOUT_THE_PROJECT.md) but not saved: add the video link, then Save & continue. The page now also has everyone's "What we learned" lines; I paste again when you say. Hirsh's caveats are in it (demo lead times are an assumption, live model use not claimed, Jev and PRISM pending). Say if any should go.

## Coming to you soon

- **Recording fixes from the flow walk (15:45).** Hirsh's five are built and publishing (15:51): the sent email says "Approved quote, local preview", plain dates, no internal list-price line, no sideways scroll, PDF warmed. Yuval is fixing the buyer-question wording (a missing price stays with the rep, not the buyer) and the "No match" screw line.
- **The Northline gauge line turning Ready after the buyer picks.** Yuval and Hirsh are agreeing a safe way to pass a buyer's choice to the matcher. Not before 4:00.
- **One-click buyer answers.** Hirsh has a worker on the single-use links.
- **One priced alternate on an abrasive line.** Asked of Yuval.
- **Jev.** Yuval's code is ready; Hirsh found two review fixes (spelled numbers in capitals, and Jev must stay off unless switched on).
- **Block Convey PRISM.** Yuval's hook and Hirsh's client are pushed. Yuval made the account; the key is not moved yet, so no trace yet.
- **Submission deck.** A subagent is building it.

## Where things stand

From the bulletin board through 15:51.

| Workflow step | State | Who | What is left |
|---|---|---|---|
| 1. RFQ arrives | ✅ | Hirsh | Fresh paste into New RFQ works (Tisch, RFQ-0029: 8 lines read). |
| 2. Pull the data | ✅ | Yuval | Email, PDF and CSV give the same eight lines. |
| 3. Parse | ✅ | Yuval | A fix for spelled-out numbers in capitals is in review. |
| 4. Match | 🟡 | Yuval | Taught terms match. A buyer's chosen answer does not reach the matcher yet (Northline gauge line). |
| 5. Price, flags, lead time | ✅ for abrasives | Tisch | S-330 Ready at USD 0.40 per lb, 24 to 48 hours (4067a06). Metals stay unpriced. |
| 6. Buyer questions | 🟡 | Yuval | Fixing: unpriced lines sent the buyer a pricing question. |
| 7. Review and approve | ✅ | Hirsh | Fresh walkthrough passed. |
| 8. Send the reply | ✅ | Hirsh | Local send with PDF and CSV; email wording fixed. |
| 9. Learn the buyer | ✅ | Yuval | Taught 0.060 matches the 304 sheet; held only for price. |
| Real models | 🟡 | | Nicrron still returns 502 (Tisch, 15:41). Rules fallback holds. |

## Build map

Every path through the [demo workflow](WORKFLOW.md), with the loops for buyer questions and the rep checkpoints. [Image to share](build_map.png).

**Checked:** 2026-10-10 13:53, from Hirsh's 13:47 and Yuval's 13:36 posts. Claude updates the marks from the board; owners post progress there.

**Key:**
- ✅ Built and on `main`.
- 🟡 Partly built, or built but not yet connected to the app.
- ⬜ Not started.
- 👤 A rep checkpoint: a person decides here.

### The map

```mermaid
flowchart TD
    A["🟡 1. RFQ arrives<br/>paste, PDF and CSV intake work; no real mailbox yet"] --> B["✅ 2. Pull the data<br/>paste, PDF and CSV run through processing in the app; Excel not yet in the app"]
    B --> C["✅ 3. Parse each line<br/>rules parser, gauge tables; 24 of 25 test lines read as expected"]
    C --> D["✅ 4. Match to the catalog<br/>matcher and RudCo catalog"]
    D --> M{"Match result"}
    M -- "one item" --> E["🟡 5. Price, flags, lead time<br/>flags and sourced lead times built; no pricer yet"]
    M -- "several candidates" --> Q
    M -- "no match" --> NM["✅ Line marked No match<br/>never forced onto the closest item"]
    NM --> R
    E --> F{"Every line clear?"}
    F -- "no" --> Q["✅ 6a. Draft one question with choices"]
    Q --> G{"🟡 6b. Confident the choices cover it?<br/>gate agreed, not built"}
    G -- "yes" --> S["⬜ 6c. Question emails itself to the buyer"]
    G -- "no" --> RQ["👤 ✅ Rep reviews and edits the question<br/>draft download works; send does not"]
    RQ --> S
    S --> BA["⬜ 6d. Buyer clicks a choice in the email<br/>answer endpoints not built"]
    BA --> W{"✅ Answer covers the whole RFQ?"}
    W -- "one line" --> RR["✅ Rerun only the answered lines<br/>in processing"]
    W -- "whole RFQ" --> RA["✅ Rerun every line"]
    RR --> C
    RA --> C
    F -- "yes" --> R["👤 ✅ 7. Rep reviews the quote<br/>source on every field, edit, approve"]
    R -- "rep edits a line" --> R
    R --> AP["👤 ✅ Rep approves the whole quote"]
    AP --> X["✅ 8a. Build the reply<br/>approved PDF, CSV and email draft; local mail preview"]
    X --> SN["👤 ⬜ 8b. Rep clicks send<br/>reply lands on the buyer's thread"]
    SN --> L["🟡 9. Learn the buyer<br/>taught terms reach parsing; confirmed-learning source not shown yet"]
    L -. "next RFQ from this buyer" .-> C
```

A rerun clears approval, so a line that turns Ready after a buyer answer goes back through the rep (W3 guard 3, ✅). A rerun never overwrites a field the rep edited (W3 guard 2, ✅). Each line keeps its run ID and benchmark date (W3 guard 4, ✅). Showing old and new values side by side (redlines) is not built yet.

### Step by step

| Step | Status | What is there | What is missing | Owner |
|---|---|---|---|---|
| 1. RFQ arrives | 🟡 | Paste, PDF or CSV intake runs automatically. Yuval drafted a demo RFQ email. | A real mailbox that receives RFQs. The final demo email (Tisch, from Yuval's draft). | Hirsh, Tisch |
| 2. Pull the data | ✅ | The app sends paste, PDF and CSV through processing, and shows sources and warnings. | Excel in the app (the library reads it). | Yuval, Hirsh |
| 3. Parse | ✅ | Rules parser with per-material gauge tables, plus a Claude step that never overwrites a rules value. 150 specs pass; 24 of 25 test lines read as expected ([test results](../rfq_processing/TEST-RESULTS.md)). | The Claude step has not run on the live API yet (sponsor gateway, Opus 5). | Yuval |
| 4. Match | ✅ | Matcher returns one match, candidates with a question, or no match. 96 RudCo items and 143 metals items. | None for the demo. | Tisch |
| 5. Price, flags, lead time | 🟡 | Compliance flags with trigger words. Lead time per line, with its source. RudCo website list prices on RudCo items. | A pricer that prices metals lines against a named, dated benchmark. | Tisch |
| 6. Buyer questions | 🟡 | Question drafting and download. Reruns for one-line and whole-RFQ answers, in processing. | The confidence gate, sending the email, and click-to-answer buttons. | Hirsh, Yuval |
| 7. Rep review and approve | ✅ | Side-by-side review, source on every field, rep edits protected, approval of the whole quote, cleared by any rerun or later edit. Reskinned to the style guide. | Redlines of old and new values. | Hirsh |
| 8. Send the reply | 🟡 | Approved PDF, CSV and email draft, with a local mail preview (letter_opener). | Real delivery on the buyer's thread. | Hirsh |
| 9. Learn the buyer | 🟡 | Per-buyer memory with teach and forget. Taught terms reach parsing in the app. | Showing where a learned reading came from, and the second-RFQ demo. | Yuval, Tisch, Hirsh |

### The rep checkpoints

1. **Review a question before it sends,** when the agent is not confident the choices cover what the buyer meant.
2. **Review the quote,** line by line, and edit any field.
3. **Approve the whole quote.** Any edit after approval clears it, and so does a rerun.
4. **Click send** on the reply.

## Chat

Leave a comment anywhere on this page, or add a line here. Claude reads every comment and answers on the page.

## Done

Newest first.

- Lead times set for the four abrasive SKUs (Tisch, 4067a06).
- Flow walk done: report and 19 Playwright tests on branch test/e2e-demo-flow.

- Item 15 closed: Yuval owns the matcher (pushed); Tisch's pricing call stands; lead times made up for the demo, as you said.

- Item 16 decided: Block Convey goes in; Yuval sets it up.

- Devpost thumbnail saved: our lockup on navy.
- Devpost "why" rewritten to follow the video (unsaved until the video link is in).
- Hirsh asked to send approved quotes through letter_opener.

- Item 12 closed: demo PDF repaired (15:05); the lead-time part moved to item 15.
- Review rail added to the Product and Compare pages.

- Two clean demo RFQs are in the app (Yuval, 15:10). RFQ-0014: four Ready lines, USD 1,810. RFQ-0017: three Ready, one waiting on the buyer, USD 1,010.

- Question tracking is in: each question records time, recipient and text in a local preview inbox, saved silently (Hirsh, 15:07).

- Promo video v2 rendered from the shot list: [quote_desk_promo_v2.mp4](promo/quote_desk_promo_v2.mp4).

- Demo PDF repaired; it passes text extraction (15:05).

- Jev key and Ruby client sent to the team in WhatsApp (Ken).

- Item 11 decided: the promo shows a full price; it can assume ideal conditions.

- 24-hour quote promise is now a core requirement, and unclear lines get quoted as alternates. Posted to the team; docs being updated.

- Favicon and logo: RudCo's own mark, unchanged, for both. Posted to Hirsh.
- Build map moved here from its own doc, with a shareable image.

- Credentials: use what the hackathon provided, for now. Posted to Hirsh.

- Brand position and style guide approved, posted on the board and in WhatsApp. AGENTS.md now links every ongoing doc.

- W4 answered by Tisch: metals first, bolts second. The demo uses RudCo's own catalog rows plus sample metals.
- Style guide: no pure white. Off-white page, cards and stripes, all measured above 4.5:1.

- Brand position approved and shipped, posted on the board and in WhatsApp. Marketing pages wait for the style guide (fast follow).

- Learn the buyer (workflow step 9) is now in scope, not a stretch goal. Updated the brief, workflow, brand position, competitive analysis, and architecture. Owner asked for on the board.

- Competitive analysis shipped: [PDF](../research/20261010.03_rudco_competitive_analysis/rudco_competitive_analysis.pdf), posted on the board and in WhatsApp.

- W3 approved: a buyer's answer reruns only the answered lines, with four guards (whole-RFQ answers rerun every line, rep edits are never overwritten, a rerun clears approval and highlights changes, each line keeps its run ID and benchmark date). In [WORKFLOW.md](WORKFLOW.md) Decisions. Posted to Hirsh and Yuval.

- The Devpost line about NicrronNinoo and Block Convey: these are free sponsor resources for the project, not a requirement, and teammates are already on it. Other tools are fine too.

- Pages: **Hirsh owns all page code.** Ken owns design direction through the [brand position](BRAND_POSITION.md). Posted to Hirsh.

- Confidence gate: **Hirsh's proposal accepted, and Hirsh owns it.** Posted to Hirsh.

- Mail: start with **letter_opener** (Rails' local email preview), then move to a real email account. Ken: "it's not that hard." Posted to Hirsh.

- Hirsh's next build: **the final email and PDF** (step 8), because it is the core demo. Buyer-answer buttons and re-quote redlines are good extra work after it. Posted to Hirsh.

- Product name decided: **RudCo Quote Desk**.
- Competitive analysis: competitor images added and blocked sites checked in Chrome.
- Brand position drafted: RudCo palette, taglines, alignment with RudCo's own words.

- Brief and workflow updated from the RudCo profile: RudCo materials, COA/REACH/RoHS flags, lead time per line, the founder's framing, and speed in RudCo's terms.
- RudCo profile approved, posted on the board and in WhatsApp.
- Architecture doc approved; each owner has a task to update their section.
- Research report approved, with a PDF in WhatsApp. `AGENTS.md` has a documentation map.
- Demo workflow approved, posted in WhatsApp.
- W1 and W2 decided: confident questions send on their own; the buyer answers by clicking in the email; no logins.
- Product brief approved, PDF posted in WhatsApp.
