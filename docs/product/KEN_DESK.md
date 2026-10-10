# Ken's Desk

**What this is:** Ken's working page for the hackathon. The top holds what needs Ken now. Comment on any item, and Claude answers on the page and updates the work. Hacking ends at **4:30 PM ET**, and the Devpost submission needs a video.

**Last updated:** 2026-10-10 13:30, from the bulletin board through Yuval's 13:24 post.

## Needs your call

Each item says who is waiting and what Claude recommends.

- [ ] **9. The demo RFQ email text.** Workflow step 1 is yours. Yuval asked for it in `docs/product/` so he can confirm every line parses (board, 13:24). *Recommendation:* Claude drafts it from the 25-line test set and Tisch's RudCo catalog (steel shot, aluminum ingot, steel plate, the stainless gauge line), and you approve it. Say "draft it" here.
- [ ] **8. Anthropic API key for Yuval.** Processing runs without one today; the Claude step turns on when a key is in `.env`. Nobody has posted one yet (board, 13:24). If you have a key, send it to Yuval or Hirsh directly, never in the repo or the chat.

## Coming to you soon

- **The working demo, as it is now.** Asked the team at 13:24 for a way to run it or a walkthrough.
- **The app reskin to the style guide, and a shared component library.** Asked the team on the board; Hirsh leads both.

## Where things stand

From the bulletin board through 13:24. Everyone is busy, and nobody has said they are idle.

| Area | Owner | State |
|---|---|---|
| Quote app | Hirsh | Building the final email and PDF (step 8), lead time per line, and protection against stale processing runs. He has spare agents, and asked Yuval what to help with. Yuval named two tasks: wire processing into RFQ intake, and load the API key into the app. 148 tests pass (13:06). |
| RFQ processing | Yuval | The library is on main and runs end to end: email, PDF and CSV in, parsed lines out, with gauge tables and compliance flags (COA, REACH, RoHS). 104 specs pass, including all 25 lines of your test set. W3 guard 4 (run ID and benchmark date per line) is in. Next is guard 1 (an answer about the whole RFQ reruns every line), aimed at 14:15. He owns the parsing side of learn the buyer. |
| Matching and pricing | Tisch | Matcher is on main. Catalogs: 96 RudCo items read from their site, 143 sample metals items, and the bolts as a third. Per-buyer memory tables are built. The catalog matching page landed. **No pricer yet:** metals lines have no price, so they show as waiting until it lands. |
| Email in and out | Hirsh | letter_opener first, then a real email account. Not started; the final email and PDF come first. |
| Product docs | Ken | Brief, workflow, architecture, research, profile, competitive analysis, and brand position shipped. Style guide in review. |
| Demo video | Ken | Not started. Yuval's plan has it recorded between 3:45 and 4:30. |

**Who could use more work.** Nobody asked for any. Two gaps have no one on them yet:

- **Pricing for metals lines.** It is Tisch's area and the next thing the demo needs for a priced quote. Free steel and aluminum price series exist (FRED, per the research).
- **Re-quote on change.** No owner. It comes after the core demo works.

## Chat

Leave a comment anywhere on this page, or add a line here. Claude reads every comment and answers on the page.

## Done

Newest first.

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
