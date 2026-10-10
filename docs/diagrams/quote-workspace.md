# Quote workspace flow

```mermaid
graph TD
    A[Rep pastes email or uploads RFQ] --> B[Save session-scoped quote and original source]
    B --> C[Persist processing run and enqueue local job]
    C --> D[ProcessRfqJob captures source and current revision]
    D --> E[Rules extraction and normalization]
    E --> F[Workspace buyer context: rep-taught terms only]
    F --> G[RudCo and metals catalog matching]
    G --> H[Readiness and supported-unit source pricing]
    H --> I{Revision current and no rep edits?}
    I -- No --> J[Stale or conflict: preserve current lines]
    I -- Yes --> K[Validate and apply lines, revision and evidence atomically]
    E --> L[Extraction failure: retain warnings and preserve lines]
    C --> M[Queue failure: retain saved RFQ]
    L --> N[Retry empty RFQ]
    M --> N
    N --> C
    O[Load development RFQs] --> K
    K --> P[Source beside quote lines and extraction evidence]
    J --> P
    L --> P
    P --> Q[Default to Attention needed; clear RFQs show All]
    P --> R[Rep edits a line]
    R --> S[Clear approval and preserve edit context]
    S --> P
    P --> T[Held-line question draft]
    T --> U[Plain text or manual question email preview]
    K --> AF[After commit: queue each drafted held-line question]
    AF --> AG{Current fingerprint and no previous attempt?}
    AG -- Yes --> AH[Local mail preview with placeholder recipient]
    AH --> AI[Record exact question, recipient and preview time]
    AI --> AJ[Waiting on buyer with local-demo label and activity history]
    AJ --> P
    AG -- No --> AK[Skip duplicate or stale work]
    T --> AA[Rep enters a current buyer answer]
    AA --> AB[Recheck revision and preserve rep edits]
    AB --> AC[Answers.apply reruns only that line]
    AC --> S
    P --> AD[Rep explicitly teaches buyer term with source RFQ]
    AD --> F
    P --> AE[Show priced alternates separately from subtotal]
    P --> V[Rep approves current whole-quote revision]
    V --> W[Locked approved snapshot]
    W --> X[PDF, CSV and email text draft]
    W --> Y[Local email preview with PDF and CSV attachments]
```

Saving an RFQ starts processing automatically. Work runs outside the request and
outside the quote lock; result application rechecks revision and rep edits under
that lock. Duplicate active requests reuse one run. The status panel shows queued,
running, succeeded, failed, stale or conflict. Existing lines are not destructively
reprocessed through the manual endpoint. Rep-entered buyer answers selectively rerun one held line under fresh revision guards.

Text-bearing PDF, CSV and pasted text extraction are connected. Unsupported or
textless sources fail visibly. Source filename, page/row counts and bounded warnings
are stored as internal evidence. Rules parsing and RudCo/metals matching are active;
no AI provider is called by this intake path. Rep-taught buyer terms are scoped to
the workspace. Automatically learned memory and aviation matching are excluded from
intake until their contracts are safe.

Held lines never enter the subtotal. Unsupported sale units stay unpriced. Lead
time is sourced or shown as `to confirm`. Filters never change totals or approval
scope. Spec and quantity edits hold lines and clear lead-time evidence. All saved
edits invalidate approval. Downloads and local previews preserve the quote.

Final email text, PDF and CSV use the same approved revision in a local mail preview.
PDF embeds Unicode fonts and rejects unsupported glyphs rather than altering specs.
Constructed provenance stays internal; internal notes and extraction metadata stay out of buyer
exports. Question drafts contain existing held-line questions only. New or changed held questions also queue an automatic local preview after commit. Successful current previews produce a locally labeled waiting state; changed questions clear that state without deleting history. Pending or failed previews never imply success. No quote totals, approval or source bytes change when a preview is recorded.

Email previews use `letter_opener` in development and a test adapter in tests, with
an invalid placeholder recipient. No buyer mail is sent. Real delivery, public choice
responses, confidence-based sending and general re-quote redlines remain pending.

Presentation follows Ken's [style guide](../product/STYLE_GUIDE.md) and the shared
[UI components](../engineering/UI_COMPONENTS.md).
