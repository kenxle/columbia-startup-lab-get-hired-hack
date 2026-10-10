# Style Guide: RudCo Quote Desk

**Status:** Draft for Ken's review, 2026-10-10. This is the design direction, built from RudCo's site and our research. Ken owns it; Hirsh owns the page code and reskins the app to match.

**What this is:** how Quote Desk looks: colors, status colors, type, buttons, layout and logo use. How we talk (voice, words, taglines, microcopy) lives in the [brand position](BRAND_POSITION.md).

**Synced with the app** on 2026-10-10 against `app/assets/stylesheets/application.css`. The app still uses its first values; the [mapping table](#reskin-the-app-to-this-direction) lists each change.

## Palette

All values come from RudCo's live site, read on 2026-10-10. The CSS stores colors as HSL custom properties on `:root` in [index-A39G_5VS.css](https://www.rud-co.com/assets/index-A39G_5VS.css). The hex values and every contrast ratio below come from [brand_colors.py](brand_colors.py) and [surface_contrast.py](surface_contrast.py), not by eye.

| Role in Quote Desk | Hex | Source |
|---|---|---|
| Navy: sidebar, dark bands, focus moments | `#0f1f3d` | `--brand-navy: 220 60% 15%` in the CSS. The page's `theme-color` meta is `#0a1e3f` ([rud-co.com HTML](https://www.rud-co.com/)). |
| Navy, share-image background | `#00091e` to `#092347` | Sampled from [og/home.png](https://www.rud-co.com/og/home.png). It is a gradient. |
| Gold rule (navy backgrounds only) | `#eea91f` | Sampled from the thin rule in [og/home.png](https://www.rud-co.com/og/home.png). It is not in the CSS. It fails on white (2.03:1), so use it only on navy (8.05:1). |
| Body text | `#1a212d` | `--foreground: 220 26% 14%` |
| Page background | `#f3f5f7` | `--secondary: 210 20% 96%`. No pure white anywhere: the site's `--background` is `#ffffff`, and we use its off-white tokens instead. |
| Cards, table, inputs | `#fafbfc` | One lighter step of the same hue (`210 20% 98.5%`), so cards lift off the page without pure white. |
| Header background (warm off-white) | `#f7f5f3` | `bg-[hsl(40,20%,96%)]` on the home-page header ([site code](https://www.rud-co.com/assets/index-B04wKX3n.js)) |
| Table stripes, sunk panels | `#f6f7f9` | `--muted: 210 20% 97%` |
| Dividers | `#e5e7eb` | `--border: 220 13% 91%` |
| Primary actions and links | `#0063e6` | `--primary-hover: 214 100% 45%`. The site's `--primary` (`#006eff`) gives 4.49:1 with white, just under 4.5:1, so we use the hover shade as the resting color (5.35:1). |
| Secondary text | `#454e5e` | Our shade of `--muted-foreground` (`220 15% 50%`). The site value gives 4.38:1 on white, so we darken it to 8.39:1. |

## Status colors

The site already has status tokens: `--available` (green), `--medium` (amber) and `--unavailable` (gray). We keep those hues and darken the text so each label passes 4.5:1. "No match" uses the site's gray. The site uses gray for unavailable items, and a line RudCo does not carry is that case. Red would read as a fault.

| Status | Text | Tint | Text on tint | Text on card (`#fafbfc`) | Based on |
|---|---|---|---|---|---|
| Ready | `#126932` | `#e7f9ed` | 6.20:1 | 6.55:1 | `--available: 142 71% 45%` |
| Needs the buyer | `#7f4205` | `#fdf0d8` | 6.94:1 | 7.55:1 | `--medium: 38 92% 50%` |
| No match | `#454e5e` | `#eaecf0` | 7.09:1 | 8.09:1 | `--unavailable: 220 15% 50%` |

Don't use the site's own solid pairs for status badges. White on `--available` is 2.30:1 and white on `--unavailable` is 4.38:1; both fail. Dark text on solid amber (`#1a212d` on `#f59f0a`) passes at 7.58:1 and is fine for a filled "Needs the buyer" badge. Status must also show as a word, never color alone.

## Type, radii, buttons

- **Type:** the system sans stack. The site loads no web fonts (no `@font-face` in the CSS) and uses Tailwind's default `ui-sans-serif, system-ui, sans-serif`. Numbers and SKUs can use the site's `font-mono` stack: `ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas`.
- **Weights:** 500 for nav, 600 for the wordmark and labels, 700 for headings (`font-medium`, `font-semibold`, `font-bold` in the [site code](https://www.rud-co.com/assets/index-B04wKX3n.js)).
- **Radius:** `--radius: .375rem` (6px). Buttons and inputs use `rounded-md`, which is 4px.
- **Buttons:** the site uses the shadcn button set. Default is blue fill with light text, `h-10 px-4`. Quote Desk uses `#fafbfc` for that text (5.16:1 on `#0063e6`). Outline is a 1px border on the card color. A navy variant appears on "Contact Sales": `bg-brand-navy` with white text ([site code](https://www.rud-co.com/assets/index-B04wKX3n.js)). Quote Desk uses blue fill for Approve and Send, outline for Edit and Export, and navy for nothing else.

## How the workspace should look like rud-co.com

- **Header:** match the site header. Warm off-white bar (`#f7f5f3`), with a 1px bottom border once the page scrolls. On the left, RudCo's round logo image at 32px, then "RudCo" in 600 weight, with a small gray line under it. On the right, nav links in 14px, weight 500.
- **Product name:** "Quote Desk" appears as the page title beside the lockup, or as the first nav item. Leave the logo lockup exactly as the site sets it.
- **Sidebar:** navy (`#0f1f3d`) with white and light-slate text. This carries the brand color the way the share images do.
- **Gold:** one thin gold rule under the sidebar's product name, echoing the share image. Nowhere else.
- **Body:** `#f3f5f7` page, `#fafbfc` cards and table, `#f6f7f9` stripes, `#e5e7eb` dividers. No pure white. RFQ on the left, quote on the right, as Hirsh has it now.
- **Footer line:** "Concept built for RudCo · Get Hired Hack, 2026-10-10 · Sample data". See the [honesty guardrails](BRAND_POSITION.md#honesty-guardrails).

## Reskin the app to this direction

This guide is the design direction. It comes from RudCo's own site and our research: the [RudCo profile](../research/20261010.02_rudco_profile/rudco_profile.md), the [competitive analysis](../research/20261010.03_rudco_competitive_analysis/competitive_analysis.md) and the [sharper-angle report](../research/20261010.01_rfq_sharper_angle/report_rfq_sharper_angle.md). The earlier direction in the [frontend contract](../engineering/FRONTEND_CONTRACT.md#ui-direction) was set before that research existed, so this guide replaces it. Hirsh reskins the app to match: the layout stays, and the token values change. Mapping from `app/assets/stylesheets/application.css`:

| Hirsh's token | Now | Change to |
|---|---|---|
| `--accent` / `--focus` | `#255bd9` | `#0063e6` |
| `--accent-strong` | `#1744af` | `#0058cc` (`--primary-dark`) |
| `--sidebar` | `#142036` | `#0f1f3d` |
| `--ink` | `#172335` | `#1a212d` |
| `--paper` | `#f2f5f9` | `#f3f5f7` |
| `--surface` | `#ffffff` | `#fafbfc` |
| `--surface-sunk` | `#edf1f7` | `#f6f7f9` |
| `--rule` | `#dce3ed` | `#e5e7eb` |
| `--ready-ink` / `--ready-wash` | `#24613e` / `#e5f3e9` | `#126932` / `#e7f9ed` |
| `--held-ink` / `--held-wash` | `#785008` / `#fff1cf` | `#7f4205` / `#fdf0d8` |
| `--nomatch-ink` / `--nomatch-wash` | `#a12f39` / `#fce8eb` (red) | `#454e5e` / `#eaecf0` (gray) |
| `--radius-small` | 5px | 4px |
| Header | none matching the site | add the RudCo lockup header described above |

Hirsh owns the page code and does the reskin ([bulletin, 13:15](../BULLETIN.md)).

## Logo use

- Use RudCo's logo files exactly as the site serves them. The header uses [this round mark](https://www.rud-co.com/lovable-uploads/b0d20d8b-8065-4321-9736-8c62ec77e728.png) beside the word "RudCo" set as live text. The footer uses [a second mark file](https://www.rud-co.com/lovable-uploads/6cf64f46-a753-4f3b-ae89-c4b015a6e51d.png).
- Never redraw, recolor, stretch or re-letter the mark or the wordmark. Do not build a Quote Desk logo.
- The share image's all-caps "RUDCO" wordmark is part of a picture. Do not trace it into the app.

