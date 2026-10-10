# Ken's Desk

**What this is:** Ken's working page for the hackathon. The top holds what needs Ken now. Comment on any item, and Claude answers on the page and updates the work. Hacking ends at **4:30 PM ET**, and the Devpost submission needs a video.

**Last updated:** 2026-10-10 14:06, from the bulletin board through 14:03.

## Needs your call

Each item says who is waiting and what Claude recommends.

Nothing open.

## Coming to you soon

- **The demo RFQ email.** Handed to Tisch, who has been collecting the RFQ and catalog data. Yuval checks that every line parses.
- **The app reskin to the style guide, and a shared component library.** Asked the team on the board; Hirsh leads both.
- **Drafts for your review:** [demo video script](DEMO_SCRIPT.md) and [Devpost write-up](DEVPOST.md), open in your browser.

## Where things stand

From the bulletin board through 14:03. The dry run of the demo script is set for 3:15; recording is about 3:45.

**Biggest risk: Tisch has not posted since 13:30**, and three video beats wait on Tisch: the demo RFQ email, the pricer for metals lines and alternate options, and the teachable gauge fields that learn the buyer needs.

| Workflow step | State | Who | What is left |
|---|---|---|---|
| 1. RFQ arrives | 🟡 | Hirsh, Tisch | Paste, PDF and CSV intake works. Busy Quotes list and due countdown asked of Hirsh. Demo RFQ email still with Tisch. |
| 2. Pull the data | ✅ | Yuval, Hirsh | Excel needs one gem added to the app. |
| 3. Parse | ✅ | Yuval | 24 of 25 test lines read as expected. The Claude step is being moved to the sponsor gateway on Opus 5; Hirsh's first test call got a server error (502), so it runs on rules today. |
| 4. Match | ✅ | Tisch | Done for the demo. |
| 5. Price, flags, lead time | 🟡 | Tisch | Flags and lead times work. **No pricer yet:** metals lines and alternate options have no named, dated price. |
| Alternates | 🟡 | Yuval, Tisch, Hirsh | The data shape is agreed (`processing.alternates`). Yuval is building it; Hirsh shows options apart from the subtotal until the buyer picks. Needs Tisch's prices. |
| 6. Buyer questions | 🟡 | Hirsh, Yuval | The rep entering the buyer's answer on a held line: Hirsh's backend is built locally (29 tests pass), forms built, testing next. Yuval's rerun is stable. Sending email and the buyer's click are not started. |
| 7. Review and approve | ✅ | Hirsh | Reskinned, L3 logo, three test RFQs. Top bar removal asked. |
| 8. Send the reply | 🟡 | Hirsh | Approved PDF, CSV and email draft with local mail preview. Real delivery not started. |
| 9. Learn the buyer | 🟡 | Hirsh, Yuval, Tisch | Hirsh is building teach-on-this-quote; Yuval words the reading "as you confirmed on RFQ-0001". Blocked on Tisch's teachable fields. |

**Roles Hirsh posted at 14:03:** Ken owns product decisions, the demo script, Devpost and the recording story, and keeps the build map current. Hirsh owns every app screen and the dry run. Yuval owns processing and the Opus 5 gateway. Tisch owns the demo email, the catalog, and pricing.

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
