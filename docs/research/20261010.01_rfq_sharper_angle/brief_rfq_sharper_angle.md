# Research Brief: The Sharper Angle on RFQ to Quote

**Status:** Draft for Ken's review. Research does not start until Ken approves this brief.

**Feeds:** [Product brief, Q2 (our sharper angle)](../../product/PRD.md#open-questions).

## Governing question

**What part of turning a messy industrial RFQ into a quote hurts quoting reps and buyers the most, and that existing tools do not already solve, so that our demo can win on uniqueness and trust?**

## The decision this supports

Ken picks one angle to build into the RudCo demo today. The four candidates in the product brief are:

- **The quote shows its work.** Every field links back to the RFQ words it came from.
- **One-click buyer questions.** Unclear lines go back as choices, not "please clarify."
- **Learns the buyer's shorthand.** A confirmed reading carries over to that buyer's next RFQ.
- **Catches hidden requirements.** Flags certifications the spec implies but the buyer never wrote down.

The research may also surface a better angle than these four. That counts as a result.

Go deep only where depth changes which angle Ken picks. Record everything else as background.

## Why now

Hacking ends at 4:30 PM ET today, Saturday, October 10, 2026. Devpost submissions and a video demo are due then. Uniqueness is one of the four judging criteria, each scored out of 5. The angle has to be picked early enough to build.

## Research questions

1. **Pain.** In their own words, what do quoting reps, inside sales, and estimators at metal service centers and industrial distributors say is slowest, most error-prone, or most annoying about quoting from RFQs? What do buyers say is most annoying about receiving quotes?
2. **Messy lines.** What do real RFQ line items look like? Collect real examples of the same item written different ways. These become our demo test cases.
3. **Costly mistakes.** Which reading errors cost the most when they slip through? For example: wrong gauge-to-thickness table, wrong grade, missing certification, wrong unit.
4. **Hidden requirements.** Which certifications and paperwork do buyers expect without asking? Mill test reports, country of origin and domestic-sourcing rules (DFARS, Buy America), and spec certifications. What triggers each one?
5. **Existing tools.** What already automates RFQ intake or quoting for metals and industrial supply? What does each do well, and where do users say it falls short?
6. **Price benchmarks.** Which public price sources for metals (indices, published surcharges) could back a "why this price is competitive" explanation? This overlaps with Yuval's data question (Q1 in the product brief). Report what is public and free, and hand the rest to Yuval.

## Research tracks

| Track | Covers | Who runs it |
|---|---|---|
| Voice of user, Reddit | Questions 1 to 4 | `reddit-researcher` agent. Ken saves the pages it lists. |
| Voice of user, open web | Questions 1 to 4: industry forums (Practical Machinist, Eng-Tips), LinkedIn posts, and trade press for service centers and distributors | web research agent |
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

1. **The four angles ranked**, plus any new one found, each with the evidence for it: how much users hurt, whether a tool already does it, and how it shows trust to the judges.
2. **A test set of real messy RFQ lines**, each with the correct reading where the source makes it clear.
3. **A short list of hidden requirements** and what triggers each one.
4. **Public price sources**, handed to Yuval.
5. **Claude's recommendation**, with a confidence rating.

Every claim gets a linked source. Quotes from named people link to their own words. The Reddit track's gaps are stated before its findings, not after.
