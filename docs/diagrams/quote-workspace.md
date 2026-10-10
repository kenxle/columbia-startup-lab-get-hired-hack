# Quote workspace flow

```mermaid
graph TD
    A[Rep pastes email or uploads RFQ] --> B[Session-scoped quote saved]
    B --> C[Awaiting processing]
    C --> D[Yuval processing result]
    D --> E[Validate all lines and apply atomically]
    F[Load labeled synthetic sample] --> E
    E --> G[Source beside quote lines]
    G --> H[Ready lines with sourced prices]
    G --> I[Held lines with buyer questions]
    H --> J[Rep reviews and approves]
    I --> J
    J --> K[CSV: priced ready lines and unpriced held lines]
    G --> L[Rep edits a line]
    L --> M[Invalidate approval]
    M --> G
```

The processing service is an internal handoff, not yet wired to a provider.
Uploads are stored without invented extraction. Held lines never contribute to
the subtotal. No buyer email is sent. Automated clarification delivery and buyer
responses are a separate pending product decision.
