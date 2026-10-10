# Where Jev Fits in RFQ to Quote

**Status:** Draft for Ken's review.

**Answer:** No, we are not using Jev today. Every decision in the system is a fixed rule or a Claude call, and the two lines in the docs that say matching uses "a decision engine like Jev" are not true of the code. The best place to start is the check that decides whether a buyer question sends on its own (Hirsh), and the next best is deciding whether a buyer's free-text answer covers one line or the whole RFQ (Hirsh, with Yuval's `Answers.apply`).

## What Jev is

Jev is TypeSafe's first "System One" model, a hosted service. There is no Jev repo on this machine. What exists is TypeSafe's public docs (docs.typesafe.ai), the installed TypeSafe skill in `~/.claude/plugins/marketplaces/typesafe-ai/skills/typesafe-ai/SKILL.md`, and Ken's Herald app, which already calls Jev to sort email.

Jev does not write text. The caller sends a `state` (the text or record to judge) and a set of typed `questions`. Jev returns a typed answer for each question, all evaluated in parallel against the same state. There are three question types:

- Noul: a yes/no question, answered with the probability of yes (0 to 1).
- Choice: pick one option from a list, answered with the pick, a probability for each option, and a confidence.
- Score: rate against ordered levels, answered with a score, per-level probabilities, and a confidence.

The interface is one HTTP call: `POST https://api.typesafe.ai/v1/systemone` with a bearer key. Python and JavaScript SDKs exist. Herald calls it from Ruby with plain `Net::HTTP` in about 100 lines (`~/Documents/workspace/herald/app/services/classify/jev_client.rb`), which this Rails app could copy. A caller defines a decision by writing the question's `instructions` and, optionally, `criteria` for what each answer means. Code then reads the probability and applies its own threshold.

TypeSafe's own jaggedness page for the current model says to keep arithmetic, counting and date comparison in code, and that Jev reads instructions literally. That rules Jev out for most of our numeric matching.

## Every place the system classifies or decides

| Decision point | Where it lives | How it decides today | Jev fit | Owner |
|---|---|---|---|---|
| Is this text an item line or order prose? | `tools/rfq_processing/lib/rfq_processing/pipeline.rb`, `item_line?` | Keyword and size patterns | Fair. It is a meaning question Jev handles well, but the patterns pass the test set and a miss here is low cost. | Yuval (processing) |
| Reading fields from a line (gauge to inches, units, dimension order, conflicts such as "16 ga" vs "0.060 in") | `rules_parser.rb`, `gauge_table.rb`, `units.rb` | Fixed rules and gauge tables. Claude fills only blanks, and only when a key is set. | Poor. It is table lookup and arithmetic, which TypeSafe says to keep in code. | Yuval (processing) |
| Claude disagrees with the rules on a field | `llm_parser.rb`, `refine` | A conflict is recorded when Claude's own confidence number is 0.9 or higher. The rules' value is kept. | Fair. Jev's probabilities are built to be calibrated, which a model's self-reported number is not. The Claude step is off until a key is set, so there is nothing to compare yet. | Yuval (processing) |
| Line status: ready, needs the buyer, no match | `readiness.rb`, `Readiness.decide` | Fixed rule. Any unknown or conflict means needs the buyer. A confidence score never makes a line ready. | Poor. The trust rules say readiness is a fixed rule, not a score. Keep it. | Yuval (processing) |
| Field check against a catalog item: exact, near, conflict | `app/services/catalog_match/matcher.rb`, `checks_for` | Per-field rules, for example a thickness within a set percent is near. | Poor. Numeric tolerances belong in code. | Tisch (matching) |
| Match outcome: exact, scored, ambiguous, no match | `matcher.rb`, `contract.rb`, `catalog_match_adapter.rb` | Share of the buyer's fields that agree, against a 0.8 threshold. Conflicts rule an item out. Up to 3 candidates. No match is never forced onto the closest item. | Fair. Jev could judge "same product?" for a buyer's wording the reader does not know, as an extra opinion on near-ties. The current score is explainable on screen, which the rep sees, and Jev's would not replace that. | Tisch (matching) |
| Compliance flags (MTR, DFARS, Buy America, origin, EN 10204, ITAR, PMI, NACE, SA, COA, REACH, RoHS) | `compliance.rb`, `Compliance.flags` | Regex tables for words in the line, rules for the spec, and context for ship-to and funding. Each flag quotes its trigger words. | Good, for confirming doubtful hits only. Code keeps finding the words, and Jev answers one yes/no per hit. Examples already named in the code as ambiguous: a bare "3.1", a bare "domestic", "water" or "bridge" as funding words, "SS", "HIC". | Yuval (processing) |
| Choices offered with a question | `readiness.rb`, `choices_for`; `suggest.rb` | Written from gauge tables, spec rules, and catalog candidates | Poor. Jev does not write text, and choices must be tied to evidence. | Yuval (processing), Tisch (matching) |
| Send a question on its own, or hold it for the rep | Not built. Rule is in WORKFLOW.md decisions (send on its own only when every choice is tied to catalog or spec evidence, no unresolved conflict outside the question, and the buyer can write their own answer). `buyer_question_draft.rb` only makes a local draft. | A written rule, no code yet | Good. It is a "does the model think the choices cover what the buyer meant" question, with a human fallback. TypeSafe documents this as confidence-gated routing. | Hirsh (app) |
| Does a buyer's answer cover one line or the whole RFQ | `answers.rb` takes the scope from the caller (`scope: "rfq"` or a `line_id`). Nothing in `app/` decides it yet. | The caller must already know | Good. It is a choice among three: this line, every line, unclear. A wrong "every line" reruns everything, so unclear goes to the rep. | Hirsh (reply handler), Yuval (`Answers.apply`) |
| Quote alternates (show each reading as a priced option) | Described in WORKFLOW.md decisions; no code in `app/` or processing yet | Rule: two or three candidates or readings become options. No match or no benchmark price stays held. | Poor. It is counting candidates and checking for a price. | Hirsh (display), Tisch (pricing each option), Yuval (carries every reading) |

## Recommendation

**1. The check before a question sends on its own (Hirsh).** This is the best first use, for three reasons. The code does not exist yet, so nothing is being replaced. The rule is already decided. A failure has a safe fallback: the rep reviews the question.

What the owner would need:

- A `JEV_API_KEY`, shared by Ken directly.
- A copy of Herald's `JevClient`, or a call from the Python or JavaScript SDK.
- One Noul question. State: the line text, the spec, and the choices with the evidence behind each. Question: do these choices include what the buyer most likely meant?
- The written rule stays first. Jev can only move a question from "send on its own" to "rep reviews". It never approves a question the rule held back.
- If the key is missing or the call fails, the question goes to the rep.
- A threshold set by trying a few real fixtures, not guessed. For example, the "16 ga" vs "0.060 in" line should pass, and a line with no usable choices should not.
- The send path itself. Today there are only local previews, so for the video the decision can show as a label on the question draft, such as "sends on its own: yes, with the probability".

**2. Whether an answer covers one line or the whole RFQ (Hirsh, with Yuval).** This is the cleanest fit, but the demo does not need it. The demo's buyer clicks a choice button, and a click already names its line. Free text such as "all of it needs DFARS" is the case that needs the decision.

What the owner would need:

- The free-text reply path in the app, which does not exist yet.
- One Choice question with three options: this line only, every line, unclear. Unclear, or a low confidence, goes to the rep.
- The result passed to `Answers.apply` as `scope: "rfq"` or a `line_id`. Yuval's code already accepts both.
- The existing guards stay: reruns never overwrite a rep's edit, and any rerun clears approval.

**Next after that, not for today:** the compliance confirmation step, as a note on a flag for the rep to see. Jev should not remove a flag, because a missed hidden requirement is the product's main promise.

## Fix the docs either way

The product brief (`docs/product/PRD.md`, line 185) says matching and scoring use "decision engines like Jev", and the workflow (`docs/product/WORKFLOW.md`, step 4) says matching uses "a decision engine like Jev". The matcher is rules. Either the owners reword those two lines, or Jev is added somewhere real before the demo is described that way. I did not edit them.
