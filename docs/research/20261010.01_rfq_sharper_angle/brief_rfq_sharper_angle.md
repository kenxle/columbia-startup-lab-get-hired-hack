# Research Brief: What Matters in RFQ to Quote

**Status:** Draft for Ken's review. Research does not start until Ken approves this brief.

**Feeds:** the [product brief](../../product/PRD.md): what it puts first, and Q2 (our sharper angle).

## Governing question

**What are the real problems and value props in going from an industrial RFQ to a sent quote, and which matter most to quoting reps and buyers?**

And within that: **what part of turning a messy industrial RFQ into a quote hurts quoting reps and buyers the most, and that existing tools do not already solve, so that our demo can win on uniqueness and trust?**

## The decisions this supports

1. **What the product puts first.** Which problems the demo solves, and which value props it shows the RudCo judges: speed, accuracy, win rate, margin, compliance, or something else.
2. **Our sharper angle.** Ken picks one to build into the demo today. The four candidates in the product brief are:

- **The quote shows its work.** Every field links back to the RFQ words it came from.
- **One-click buyer questions.** Unclear lines go back as choices, not "please clarify."
- **Learns the buyer's shorthand.** A confirmed reading carries over to that buyer's next RFQ.
- **Catches hidden requirements.** Flags certifications the spec implies but the buyer never wrote down.

The research may also surface a better angle than these four. That counts as a result.

Go deep only where depth changes either decision. Record everything else as background.

## Why now

Hacking ends at 4:30 PM ET today, Saturday, October 10, 2026. Devpost submissions and a video demo are due then. Uniqueness is one of the four judging criteria, each scored out of 5. The angle has to be picked early enough to build.

## Research questions

0. **The whole job.** What are the steps from receiving an RFQ to sending the quote, who does each step, and where does the time go? What does a faster or better quote win the supplier: more orders, better margin, fewer returns, happier buyers? Which of those value props do suppliers and buyers name themselves?
1. **Pain.** In their own words, what do quoting reps, inside sales, and estimators at metal service centers and industrial distributors say is slowest, most error-prone, or most annoying about quoting from RFQs? What do buyers say is most annoying about receiving quotes?
2. **Messy lines.** What do real RFQ line items look like? Collect real examples of the same item written different ways. These become our demo test cases.
3. **Costly mistakes.** Which reading errors cost the most when they slip through? For example: wrong gauge-to-thickness table, wrong grade, missing certification, wrong unit.
4. **Hidden requirements.** Which certifications and paperwork do buyers expect without asking? Mill test reports, country of origin and domestic-sourcing rules (DFARS, Buy America), and spec certifications. What triggers each one?
5. **Existing tools.** What already automates RFQ intake or quoting for metals and industrial supply? What does each do well, and where do users say it falls short?
6. **Price benchmarks.** Which public price sources for metals (indices, published surcharges) could back a "why this price is competitive" explanation? This overlaps with Yuval's data question (Q1 in the product brief). Report what is public and free, and hand the rest to Yuval.

## Research tracks

| Track | Covers | Who runs it |
|---|---|---|
| Voice of user, Reddit | Questions 0 to 4 | `reddit-researcher` agent. Ken saves the pages it lists. |
| Voice of user, open web | Questions 0 to 4: industry forums (Practical Machinist, Eng-Tips), LinkedIn posts, and trade press for service centers and distributors | web research agent |
| Domain rules | Questions 3 and 4: gauge tables by material, common ASTM specs for sheet, plate, bar and tube, and when mill test reports and origin rules apply | web research agent |
| Existing tools | Question 5 | web research agent |
| Price benchmarks | Question 6 | web research agent |

**Reddit communities to search:** r/sales, r/manufacturing, r/procurement, r/supplychain, r/Machinists, r/metalworking, r/Welding, r/engineering, and any community for industrial distribution or estimators that turns up along the way. Search in the words practitioners use: "RFQ", "quote", "estimating", "inside sales", "service center", "MTR", "certs", "gauge", "takeoff".

## Scope

**In:**

- Metals first (sheet, plate, bar, tube, pipe), since the RudCo examples are metals. Abrasives and aggregates only if they come up.
- Public sources: forums, Reddit, trade press, vendor pages, standards bodies' public pages.

**Out:**

- Paid standards documents and paid price data.
- How to build the agent. That is architecture, not research.

## Method

- Web research by parallel agents, each writing its own findings file.
- A Reddit loop: the agent lists pages, Ken saves them, the agent reads them, repeat.
- Collect real messy line items into one test-case file the builders can use.

## What the report delivers

1. **A map of the RFQ-to-quote job**, with the problems at each step and the value props ranked by how much reps and buyers care.
2. **The four angles ranked**, plus any new one found, each with the evidence for it: how much users hurt, whether a tool already does it, and how it shows trust to the judges.
3. **A test set of real messy RFQ lines**, each with the correct reading where the source makes it clear.
4. **A short list of hidden requirements** and what triggers each one.
5. **Public price sources**, handed to Yuval.
6. **Claude's recommendation** on what to put first and which angle to build, with a confidence rating.

Every claim gets a linked source. Quotes from named people link to their own words. The Reddit track's gaps are stated before its findings, not after.
