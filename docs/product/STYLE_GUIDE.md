# Style Guide: RudCo Quote Desk

**Status:** Draft for Ken's review, 2026-10-10. Ken owns the design direction; Hirsh owns the page code and applies it.

**What this is:** how Quote Desk looks: colors, status colors, type, buttons, layout and logo use. How we talk (voice, words, taglines, microcopy) lives in the [brand position](BRAND_POSITION.md).

**Synced with the app** on 2026-10-10 against `app/assets/stylesheets/application.css`. The app still uses its first values; the [mapping table](#what-changes-from-hirshs-direction) lists each change.

## Palette

All values come from RudCo's live site, read on 2026-10-10. The CSS stores colors as HSL custom properties on `:root` in [index-A39G_5VS.css](https://www.rud-co.com/assets/index-A39G_5VS.css). The hex values and every contrast ratio below come from [brand_colors.py](brand_colors.py), not by eye.

| Role in Quote Desk | Hex | Source |
|---|---|---|
| Navy: sidebar, dark bands, focus moments | `#0f1f3d` | `--brand-navy: 220 60% 15%` in the CSS. The page's `theme-color` meta is `#0a1e3f` ([rud-co.com HTML](https://www.rud-co.com/)). |
| Navy, share-image background | `#00091e` to `#092347` | Sampled from [og/home.png](https://www.rud-co.com/og/home.png). It is a gradient. |
| Gold rule (navy backgrounds only) | `#eea91f` | Sampled from the thin rule in [og/home.png](https://www.rud-co.com/og/home.png). It is not in the CSS. It fails on white (2.03:1), so use it only on navy (8.05:1). |
| Body text | `#1a212d` | `--foreground: 220 26% 14%` |
| Page background | `#ffffff` | `--background: 0 0% 100%` |
| Header background (warm off-white) | `#f7f5f3` | `bg-[hsl(40,20%,96%)]` on the home-page header ([site code](https://www.rud-co.com/assets/index-B04wKX3n.js)) |
| Panels, table stripes | `#f3f5f7` | `--secondary: 210 20% 96%` |
| Dividers | `#e5e7eb` | `--border: 220 13% 91%` |
| Primary actions and links | `#0063e6` | `--primary-hover: 214 100% 45%`. The site's `--primary` (`#006eff`) gives 4.49:1 with white, just under 4.5:1, so we use the hover shade as the resting color (5.35:1). |
| Secondary text | `#454e5e` | Our shade of `--muted-foreground` (`220 15% 50%`). The site value gives 4.38:1 on white, so we darken it to 8.39:1. |

## Status colors

The site already has status tokens: `--available` (green), `--medium` (amber) and `--unavailable` (gray). We keep those hues and darken the text so each label passes 4.5:1. "No match" uses the site's gray. The site uses gray for unavailable items, and a line RudCo does not carry is that case. Red would read as a fault.

| Status | Text | Tint | Text on tint | Text on white | Based on |
|---|---|---|---|---|---|
| Ready | `#126932` | `#e7f9ed` | 6.20:1 | 6.79:1 | `--available: 142 71% 45%` |
| Needs the buyer | `#7f4205` | `#fdf0d8` | 6.94:1 | 7.82:1 | `--medium: 38 92% 50%` |
| No match | `#454e5e` | `#eaecf0` | 7.09:1 | 8.39:1 | `--unavailable: 220 15% 50%` |

Don't use the site's own solid pairs for status badges. White on `--available` is 2.30:1 and white on `--unavailable` is 4.38:1; both fail. Dark text on solid amber (`#1a212d` on `#f59f0a`) passes at 7.58:1 and is fine for a filled "Needs the buyer" badge. Status must also show as a word, never color alone.

## Type, radii, buttons

- **Type:** the system sans stack. The site loads no web fonts (no `@font-face` in the CSS) and uses Tailwind's default `ui-sans-serif, system-ui, sans-serif`. Numbers and SKUs can use the site's `font-mono` stack: `ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas`.
- **Weights:** 500 for nav, 600 for the wordmark and labels, 700 for headings (`font-medium`, `font-semibold`, `font-bold` in the [site code](https://www.rud-co.com/assets/index-B04wKX3n.js)).
- **Radius:** `--radius: .375rem` (6px). Buttons and inputs use `rounded-md`, which is 4px.
- **Buttons:** the site uses the shadcn button set. Default is blue fill with white text, `h-10 px-4`. Outline is a 1px border on white. A navy variant appears on "Contact Sales": `bg-brand-navy` with white text ([site code](https://www.rud-co.com/assets/index-B04wKX3n.js)). Quote Desk uses blue fill for Approve and Send, outline for Edit and Export, and navy for nothing else.

## How the workspace should look like rud-co.com

- **Header:** match the site header. Warm off-white bar (`#f7f5f3`), with a 1px bottom border once the page scrolls. On the left, RudCo's round logo image at 32px, then "RudCo" in 600 weight, with a small gray line under it. On the right, nav links in 14px, weight 500.
- **Product name:** "Quote Desk" appears as the page title beside the lockup, or as the first nav item. Leave the logo lockup exactly as the site sets it.
- **Sidebar:** navy (`#0f1f3d`) with white and light-slate text. This carries the brand color the way the share images do.
- **Gold:** one thin gold rule under the sidebar's product name, echoing the share image. Nowhere else.
- **Body:** white page, `#f3f5f7` panels, `#e5e7eb` dividers. RFQ on the left, quote on the right, as Hirsh has it now.
- **Footer line:** "Concept built for RudCo · Get Hired Hack, 2026-10-10 · Sample data". See the [honesty guardrails](BRAND_POSITION.md#honesty-guardrails).

## What changes from Hirsh's direction

The [frontend contract](../engineering/FRONTEND_CONTRACT.md#ui-direction) asked for warm white, charcoal type and rust-orange actions. The [current build](../engineering/UI_UX_APPROACH.md#current-implementation) already moved to cobalt actions and cool surfaces, with a navy sidebar. So the layout stays and only the color values change. Mapping from `app/assets/stylesheets/application.css`:

| Hirsh's token | Now | Change to |
|---|---|---|
| `--accent` / `--focus` | `#255bd9` | `#0063e6` |
| `--accent-strong` | `#1744af` | `#0058cc` (`--primary-dark`) |
| `--sidebar` | `#142036` | `#0f1f3d` |
| `--ink` | `#172335` | `#1a212d` |
| `--paper` | `#f2f5f9` | `#f3f5f7` |
| `--rule` | `#dce3ed` | `#e5e7eb` |
| `--ready-ink` / `--ready-wash` | `#24613e` / `#e5f3e9` | `#126932` / `#e7f9ed` |
| `--held-ink` / `--held-wash` | `#785008` / `#fff1cf` | `#7f4205` / `#fdf0d8` |
| `--nomatch-ink` / `--nomatch-wash` | `#a12f39` / `#fce8eb` (red) | `#454e5e` / `#eaecf0` (gray) |
| `--radius-small` | 5px | 4px |
| Header | none matching the site | add the RudCo lockup header described above |

Any rust-orange left over from the first direction goes away. Hirsh owns `app/views/quotes/` and the stylesheets until he and Ken agree a handoff ([bulletin, 12:56](../BULLETIN.md)).

## Logo use

- Use RudCo's logo files exactly as the site serves them. The header uses [this round mark](https://www.rud-co.com/lovable-uploads/b0d20d8b-8065-4321-9736-8c62ec77e728.png) beside the word "RudCo" set as live text. The footer uses [a second mark file](https://www.rud-co.com/lovable-uploads/6cf64f46-a753-4f3b-ae89-c4b015a6e51d.png).
- Never redraw, recolor, stretch or re-letter the mark or the wordmark. Do not build a Quote Desk logo.
- The share image's all-caps "RUDCO" wordmark is part of a picture. Do not trace it into the app.

