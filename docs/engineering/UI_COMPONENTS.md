# Quote Desk UI components

Hirsh owns the page components. Follow Ken's [style guide](../product/STYLE_GUIDE.md). Keep screen layouts and product wording separate from presentation changes.

## Tokens

`app/assets/stylesheets/application.css` is the token source. Page-specific stylesheets use its variables. Do not introduce literal colors or pure white surfaces in page styles.

| Role | Token |
|---|---|
| Page | `--paper`, `#f3f5f7` |
| Cards, table, inputs, primary-button text | `--surface`, `#fafbfc` |
| Stripes and recessed surfaces | `--surface-sunk`, `#f6f7f9` |
| Warm header | `--header`, `#f7f5f3` |
| Body and secondary text | `--ink`, `--ink-soft`, `--muted` |
| Actions and keyboard focus | `--accent`, `--accent-strong`, `--focus`, `--focus-ring` |
| Dividers and controls | `--rule`, `--rule-strong`, `--rule-hover` |
| Status | `--ready-*`, `--held-*`, `--nomatch-*` |
| Validation errors | `--error-*`, independent of gray No match |
| Source highlights | `--evidence-wash`, `--accent` |

Cards use `--radius` (6px). Buttons and controls use `--radius-small` (4px). System sans and monospace stacks are `--font-sans` and `--font-mono`. Only the sidebar product rule uses `--brand-gold`.

## Reusable ERB components

All components escape text normally. Do not pass untrusted HTML through `html_safe`.

| Component | Locals | Consumers |
|---|---|---|
| `shared/status_badge` | Required `label`, `state` | Quote line table, quote line detail, catalog outcomes |
| `shared/panel_header` | Required `title`, `id`; optional `eyebrow` | Catalog reading, client memory, recent requests |
| `shared/flag` | Required `label`; optional `tone`, default `source` | Catalog reading and comparison evidence |

Status states are `ready`, `needs_buyer`, `no_match`, and `neutral`. Catalog `match` and `candidates` map to Ready and Needs the buyer colors while retaining the catalog's label. Unknown states use the neutral unknown style. Always include a visible word; color alone is insufficient.

```erb
<%= render "shared/status_badge", label: line.status_label, state: line.state %>
<%= render "shared/panel_header", title: "Source evidence", id: "source-heading" %>
<%= render "shared/flag", label: "Rep edit", tone: "edited" %>
```

Flag tones are `source`, `edited`, and `unresolved`. A panel header renders an `h2`; give its containing section a matching `aria-labelledby`. The existing quote helpers remain compatible for screens not yet migrated and use the same CSS primitives.

## Shared CSS primitives

These classes are the component library for plain Rails links, forms and semantic HTML. Keep page-specific layout in its page stylesheet.

| Primitive | Use |
|---|---|
| `.button` with `.button--primary` | Primary action, including Approve and Send |
| `.button` with `.button--quiet` | Outlined action, including Edit, Export and secondary actions |
| `.button` with `.button--ghost` | Low-emphasis action |
| `.card` | Surface, border and radius only; catalog candidate cards consume it |
| `.panel`, `.panel__head`, `.panel__title`, `.panel__body` | Section card, heading and consistent interior spacing |
| `.page-header`, `.page-title`, `.page-lede`, `.page-actions` | Screen heading and its actions |
| `.table-wrap`, `.data-table`, `.row-link` | Horizontally contained tables, shared striped rows and links |
| `.lines-table`, `.is-selected`, `.is-held` | Quote-specific row layout and review state on top of the shared table |
| `.field-row`, `.field-row__summary`, `.field-row__body` | Native `details` field disclosure used in quote evidence |
| `.evidence-disclosure` | Native `details` disclosure for evidence such as catalog checks |
| `.evidence`, `.evidence__caption`, `.evidence__location`, `.evidence__why` | Evidence content, source location and explanation |
| `.evidence-mark`, `.quote-text` | Highlighted source words and the original excerpt |
| `.flag`, `.status` | Textual metadata and status, preferably rendered through shared partials |
| `.field`, `.field__label`, `.field__hint`, `.input` | Labeled form controls and helper text |
| `.form-errors`, `.callout--held` | Validation errors and buyer clarification holds |

Native `details` and `summary` provide keyboard interaction without JavaScript. Keep visible focus styles, labels, table headers and the skip link. Put wide evidence tables inside `.table-wrap` so mobile scroll stays inside the table. Preserve source evidence and stored provenance when changing presentation. Ken's 13:48 video-demo direction removes concept/sample labels from the visible UI.

The official RudCo logo is served unchanged from `/brand/rudco-mark.png`, per Ken's 13:51 asset handoff. See [asset attribution](../../app/assets/images/README.md). The shared application layout supplies the warm header and sidebar, with no concept footer. Its lockup is the unchanged 32px mark beside RudCo over QUOTE DESK. Attention-first browser titles describe held lines or approval status. The opt-in development-only LAHE review rail stays after the stylesheet.

## Checks

`test/integration/brand_header_test.rb` covers header identity and accessibility hooks, preserved navigation, status words, catalog outcome mapping and escaped component labels. Existing quote and catalog integration tests cover their workflows. Check desktop and narrow mobile widths after changes to these primitives.
