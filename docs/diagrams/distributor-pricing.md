# Live distributor pricing

```mermaid
flowchart TD
    RFQ[RFQ and delivery destination] --> INTAKE[Extract lines and verify specifications]
    INTAKE --> GROUP[Consolidate identical purchase lots]
    GROUP --> PUBLIC[Refresh five competitor sources in parallel]
    GROUP --> MATERIAL[Refresh applicable published material context]
    GROUP --> TERMS[Request live supplier and delivered competitor terms]
    PUBLIC --> CHECK[Validate current evidence and missing fields]
    MATERIAL --> CHECK
    TERMS --> CHECK
    CHECK --> GATE{Deliverable supply and five valid comparisons?}
    GATE -- No --> HOLD[Buyer questions or procurement tasks, price held]
    GATE -- Yes --> MATH[Decimal landed-cost pricing, target 15%, floor 8%]
    MATH --> COMP{Competitive at a profitable price?}
    COMP -- No --> HOLD
    COMP -- Yes --> QUOTE[Per-item quote price, supplier evidence and expiry]
    QUOTE --> REP[Rep review and approval]
```

Public price listings and material indices never establish wholesale cost or confirmed delivery on their own. Rep approval is required; this service does not send or purchase.
