# Ken's Desk

**What this is:** Ken's working page for the hackathon. The top holds what needs Ken now. Comment on any item, and Claude answers on the page and updates the work. Hacking ends at **4:30 PM ET**, and the Devpost submission needs a video.

**Last updated:** 2026-10-10 13:02, from the bulletin board through Hirsh's 13:00 post.

## Needs your call

Each item says who is waiting and what Claude recommends.

- [ ] **8. Anthropic API key for Yuval.** Yuval's parser runs on recorded responses until a key is in `.env` on his machine. If you have a key to share with him, send it to him directly, never in the repo or the chat. *Waiting: Yuval (PLAN.md, open question 5).*

## Coming to you soon

- **The working demo, as it is now.** Asked the team at 13:24 for a way to run it or a walkthrough.
- **The app reskin to the style guide.** Asked Hirsh at 13:27.
- **W4, which catalog the demo uses.** Tisch is answering. The brief now says the demo RFQ uses RudCo's materials, so Tisch needs metals catalog rows.

## Where things stand

| Area | Owner | State |
|---|---|---|
| Quote app | Hirsh | Review, edit, approve, export, filters, and buyer-question draft work. 125 tests pass (board, 13:00). |
| RFQ processing | Yuval | Result format and three fixtures done. Parser and rules in progress. |
| Matching and pricing | Tisch | 200-item aviation catalog done. Matcher and pricer not in the repo yet. |
| Email in and out | Hirsh (proposed) | letter_opener first, then a real email account. |
| Product docs | Ken | Brief, workflow, architecture, research, profile, and competitive analysis all shipped. |
| Demo video | Ken | Not started. Yuval's plan has it recorded between 3:45 and 4:30. |

## Chat

Leave a comment anywhere on this page, or add a line here. Claude reads every comment and answers on the page.

## Done

Newest first.

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
