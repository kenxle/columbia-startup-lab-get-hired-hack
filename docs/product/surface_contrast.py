"""Contrast of Quote Desk text colors on the off-white surfaces (no pure white).

Usage:
    python3 -I docs/product/surface_contrast.py

Surfaces are RudCo CSS tokens (https://www.rud-co.com/assets/index-A39G_5VS.css,
read 2026-10-10) plus one lighter step of the same hue. Used by STYLE_GUIDE.md.
"""
import colorsys

def hsl_hex(h, s, l):
    r, g, b = colorsys.hls_to_rgb(h / 360, l / 100, s / 100)
    return "#{:02x}{:02x}{:02x}".format(round(r * 255), round(g * 255), round(b * 255))

def lum(hexc):
    hexc = hexc.lstrip("#")
    out = []
    for i in (0, 2, 4):
        c = int(hexc[i:i + 2], 16) / 255
        out.append(c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4)
    return 0.2126 * out[0] + 0.7152 * out[1] + 0.0722 * out[2]

def ratio(a, b):
    la, lb = sorted([lum(a), lum(b)], reverse=True)
    return (la + 0.05) / (lb + 0.05)

surfaces = {
    "page (--secondary, 210 20% 96%)": hsl_hex(210, 20, 96),
    "cards and table (210 20% 98.5%)": hsl_hex(210, 20, 98.5),
    "table stripes (--muted, 210 20% 97%)": hsl_hex(210, 20, 97),
    "header (hsl 40 20% 96%)": hsl_hex(40, 20, 96),
}
texts = {
    "body text": "#1a212d",
    "secondary text": "#454e5e",
    "actions and links": "#0063e6",
    "ready": "#126932",
    "needs the buyer": "#7f4205",
    "no match": "#454e5e",
}
for name, s in surfaces.items():
    print(f"{name}: {s}")
print()
for sname, s in surfaces.items():
    for tname, t in texts.items():
        r = ratio(t, s)
        print(f"{tname:18s} {t} on {sname:38s} {s}: {r:.2f}:1 {'pass' if r >= 4.5 else 'FAIL'}")
print()
# white button text on the action blue stays (it is text, not a surface)
print(f"button text {hsl_hex(210, 20, 98.5)} on #0063e6: {ratio(hsl_hex(210, 20, 98.5), '#0063e6'):.2f}:1")
