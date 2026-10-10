# Ken's Desk

**What this is:** Ken's working page for the hackathon. The top holds what needs Ken now. Comment on any item, and Claude answers on the page and updates the work. Hacking ends at **4:30 PM ET**, and the Devpost submission needs a video.

**Last updated:** 2026-10-10 13:02, from the bulletin board through Hirsh's 13:00 post.

## Needs your call

Each item says who is waiting and what Claude recommends.

- [ ] **2. Who owns the mail connection, and which inbox?** Nobody owns it yet. **Claude recommends** a simulated mailbox inside the app for the demo: a seeded RFQ email comes in, and "sent" emails show in an outbox the buyer can click. It can't fail on stage, and it shows the same flow. A real inbox (Gmail or SMTP) is a stretch. Hirsh is the natural owner, since the outbox sits in the app. *Waiting: Hirsh (board, 12:59).*
- [ ] **3. W3: does a buyer's answer rerun only the answered lines on its own?** **Claude recommends yes,** with the rep still approving the final quote. *Waiting: Hirsh, Yuval (board, 12:46 and 12:59).*
- [ ] **4. The confidence gate for auto-sending questions.** Hirsh proposed: send on its own only when every choice is tied to catalog or spec evidence, there is no unresolved conflict outside the question, and the buyer can always write their own answer. Otherwise the rep reviews it. **Claude recommends accepting it as written.** *Waiting: Hirsh (board, 12:46).*
- [ ] **5. Who builds which pages.** Hirsh heard you were building pages and asked for a split. **Claude recommends:** you own the design direction (the brand position doc, coming soon, uses RudCo's palette), and Hirsh owns all page code. You don't edit `app/views/`. *Waiting: Hirsh (board, 12:56).*
- [ ] **7. A strange line on Devpost.** The profile agent reported that the Devpost page says "Using NicrronNinoo and Block Convey is a must in your project," twice. Claude read the page earlier and did not see it. It may not be a genuine requirement. **Claude recommends** asking an organizer before acting on it.
- [ ] **8. Anthropic API key for Yuval.** Yuval's parser runs on recorded responses until a key is in `.env` on his machine. If you have a key to share with him, send it to him directly, never in the repo or the chat. *Waiting: Yuval (PLAN.md, open question 5).*

## Coming to you soon

- **Competitive analysis images and checks.** An agent is adding competitor screenshots and checking blocked sites in Chrome. Running.
- **W4, which catalog the demo uses.** Tisch is answering. The brief now says the demo RFQ uses RudCo's materials, so Tisch needs metals catalog rows.

## Where things stand

| Area | Owner | State |
|---|---|---|
| Quote app | Hirsh | Review, edit, approve, export, filters, and buyer-question draft work. 125 tests pass (board, 13:00). |
| RFQ processing | Yuval | Result format and three fixtures done. Parser and rules in progress. |
| Matching and pricing | Tisch | 200-item aviation catalog done. Matcher and pricer not in the repo yet. |
| Email in and out | Nobody yet | See item 2. |
| Product docs | Ken | Brief, workflow, architecture, research, profile, and competitive analysis all shipped. |
| Demo video | Ken | Not started. Yuval's plan has it recorded between 3:45 and 4:30. |

## Chat

Leave a comment anywhere on this page, or add a line here. Claude reads every comment and answers on the page.

## Done

Newest first.

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
