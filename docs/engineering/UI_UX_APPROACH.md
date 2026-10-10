# UI/UX approach for the quote workspace

Researched for Hirsh on 2026-10-10 using TinyFish search and page extraction.
Tavily was attempted twice, but its stored OAuth refresh was rejected. No new
credentials were requested or stored. These recommendations are design judgments,
not measured improvements from user testing.

## Recommended approach

Use a compact quote table with the original RFQ beside it. Keep the selected
line's details close to the table, and make unresolved work easy to reach.

| Approach | Strength | Cost | Decision |
|---|---|---|---|
| Spreadsheet-first | Fast comparison of quantity, price and totals | Evidence, explanations and corrections crowd the grid | Use its scanning strength, not a full spreadsheet editor |
| Split-pane review | Original request stays visible while checking extracted values | Needs responsive stacking and careful width allocation | Primary desktop experience |
| Chat-first | Useful for open-ended questions | Harder to compare many rows and revisit exact changes | Optional assistance later, not the main review surface |

This comparison is our synthesis for quoting reps. It does not claim that one
approach is universally faster.

## Evidence behind the recommendation

[IBM Carbon's data-table guidance](https://www.carbondesignsystem.com/building-blocks/core/components/data-table/guidelines)
recommends sufficient space for dense data, expandable supplementary information,
row actions and a toolbar for table-wide controls. It explicitly distinguishes
a data table from a spreadsheet replacement. Applied here: prioritize item,
quantity, price, total and readiness; open source/compliance details on demand.

[Carbon's AI-label guidance](https://www.carbondesignsystem.com/building-blocks/core/components/ai-label/guidelines)
places explainability where AI-generated content appears and distinguishes manual
overrides. Applied here: identify the field's source and explain conversions;
show rep edits separately. An AI badge alone is insufficient evidence.

[SAP's flexible-column layout](https://www.sap.com/design-system/fiori-design-web/v1-108/page-types/page-layouts/flexible-column-layout)
keeps related views together and adapts columns to available space. The extracted
page body was sparse; its official page description supplied the layout behavior.
Applied here: retain source context on desktop and stack clearly on narrow screens.

[Microsoft's human-AI engineering guidance](https://www.microsoft.com/en-us/research/articles/how-to-build-effective-human-ai-interaction-considerations-for-machine-learning-and-software-engineering/)
warns that explanations depend on real system support and that confidence requires
calibration. It also recommends evaluating people working with the system.
Applied here: show concrete blockers such as missing grade or conflicting gauge;
do not invent a percentage confidence score. Source lineage must come from Yuval's
pipeline and catalog/price evidence from Tisch's services.

## Current implementation

- Source text and quote table share the desktop workspace.
- Selecting a row opens its editable fields and supporting evidence.
- Cobalt actions, cool surfaces and semantic status colors establish hierarchy.
- The table has more width; source and long values wrap. Status labels stay visible.
- Source highlighting is scoped to the original line plus compliance trigger text.
- Rep price overrides lose the old benchmark claim. Internal notes stay out of exports.
- Final approval requires explicit confirmation of the displayed revision.

## Next priorities for Ken and the implementation team

1. Add an attention filter and a next-unresolved-line action while preserving original line numbers.
2. Put the clarification action near the summary, with an exact count of affected lines.
3. Show each proposed answer with its catalog/spec evidence, plus a free-text fallback.
4. Keep processing, waiting for buyer, and needs-rep-review states distinct.
5. Make re-quote revisions show old/new values and prices together with their evidence.
6. Offer undo for a rep edit once immutable original and revised values are available.

Ken's W1/W2 decisions allow automatic questions when grounded choices meet an
agreed confidence policy; otherwise the rep reviews. Buyers choose in email or
reply with a choice number. W3 automatic reruns and W4 catalog scope remain open.
The current app sends no email. The confidence policy, mail adapter, choice IDs,
response provenance and stale-response handling need a shared contract before
that integration is presented as working.

## Practical usability check

Give a teammate a clean line, a missing-grade line and a contradictory gauge line.
Ask them to find the blocker, inspect its evidence, draft a question, change a
price and export the reviewed quote. Record completion time, wrong approvals,
unnecessary clicks and whether they can explain each price's source. Compare the
next iteration against this baseline; do not infer usability from appearance alone.
