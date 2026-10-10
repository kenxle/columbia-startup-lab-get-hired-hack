# Quote workspace flow

```mermaid
graph TD
    A[Rep pastes email or uploads RFQ] --> B[Session-scoped quote saved]
    B --> C[Awaiting processing]
    C --> D[Yuval processing result]
    D --> E[Validate lines and metadata and apply atomically]
    F[Load labeled synthetic sample] --> E
    E --> G[Source beside quote lines]
    G --> H[Ready lines with sourced prices]
    G --> I[Held lines with buyer questions]
    G --> N[Filter all, attention needed or ready]
    I --> O[Review consolidated buyer-question draft]
    O --> P[Download plain text when all questions exist]
    O --> L
    H --> J[Rep reviews and approves]
    I --> J
    J --> K[CSV: priced ready lines and unpriced held lines]
    G --> L[Rep edits a line]
    L --> M[Invalidate approval]
    M --> G
```

The processing service is an internal handoff, not yet wired to a provider.
Uploads are stored without invented extraction. Held lines never contribute to
the subtotal. Filters do not change totals or approval scope. Hardware specs,
processing metadata, stable line IDs and the processing revision are stored.
The question preview and draft download do not change the quote or approval.
No buyer email is sent. Ken approved email choices and response behavior in the
demo workflow; delivery, response handling and the confidence gate remain pending.
