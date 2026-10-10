"""Convert RudCo CSS HSL tokens to hex, sample the share image, and compute WCAG contrast.

Usage (reads the share image from a temp folder, nothing saved in the repo):
    curl -sL https://www.rud-co.com/og/home.png -o /tmp/og_home.png
    python3 -I docs/product/brand_colors.py /tmp/og_home.png

Token values are copied from :root in https://www.rud-co.com/assets/index-A39G_5VS.css
(read 2026-10-10). Used by BRAND_POSITION.md.
"""
import colorsys
import sys
from PIL import Image

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

tokens = {
    "--background": (0, 0, 100),
    "--foreground": (220, 26, 14),
    "--hero-bg": (40, 40, 96),
    "header home bg hsl(40,20%,96%)": (40, 20, 96),
    "--primary": (214, 100, 50),
    "--primary-hover": (214, 100, 45),
    "--primary-dark": (214, 100, 40),
    "--brand-navy": (220, 60, 15),
    "--available / --success": (142, 71, 45),
    "--medium / --warning": (38, 92, 50),
    "--unavailable / --muted-foreground": (220, 15, 50),
    "--secondary": (210, 20, 96),
    "--muted": (210, 20, 97),
    "--border": (220, 13, 91),
    "--destructive": (0, 84, 60),
    "--steel": (200, 8, 45),
    "--steel-dark": (200, 10, 25),
    "--deep-blue": (220, 70, 35),
}
print("== CSS tokens as hex ==")
H = {}
for k, v in tokens.items():
    H[k] = hsl_hex(*v)
    print(f"{k:40s} hsl({v[0]} {v[1]}% {v[2]}%) -> {H[k]}")

print("\n== Share image samples (og/home.png) ==")
img = Image.open(sys.argv[1]).convert("RGB")
w, h = img.size
def px(x, y):
    return "#{:02x}{:02x}{:02x}".format(*img.getpixel((x, y)))
print("size", w, h)
for (x, y) in [(10, 10), (600, 20), (1190, 10), (600, 200), (20, 620)]:
    print(f"background at ({x},{y}): {px(x, y)}")
# find the gold rule row: the most saturated-yellow row in the band y=140..170
best = None
for y in range(130, 180):
    r, g, b = img.getpixel((600, y))
    score = (r + g) / 2 - b
    if best is None or score > best[0]:
        best = (score, y)
gy = best[1]
print(f"gold rule row y={gy}: samples", [px(x, gy) for x in (100, 400, 600, 900, 1100)])
for y in range(gy - 2, gy + 3):
    print(f"  y={y} at x=600: {px(600, y)}")
# headline white
print("headline text sample (white?) near (100,300):", px(100, 300))

print("\n== Contrast checks (WCAG 2.x) ==")
navy = H["--brand-navy"]
white = "#ffffff"
fg = H["--foreground"]
checks = [
    ("white on --brand-navy (header)", white, navy),
    ("white on --primary (default button)", white, H["--primary"]),
    ("white on --primary-dark", white, H["--primary-dark"]),
    ("--primary text on white (links)", H["--primary"], white),
    ("--foreground on white (body)", fg, white),
    ("--muted-foreground on white", H["--unavailable / --muted-foreground"], white),
    ("site pair: white on --available (success)", white, H["--available / --success"]),
    ("site pair: --foreground on --warning", fg, H["--medium / --warning"]),
    ("site pair: white on --unavailable", white, H["--unavailable / --muted-foreground"]),
]
# Proposed status pairs: same hues as the site's status tokens, darkened text on light tint
proposed = {
    "Ready text":  hsl_hex(142, 71, 24),
    "Ready tint":  hsl_hex(142, 60, 94),
    "Needs text":  hsl_hex(30, 92, 26),
    "Needs tint":  hsl_hex(38, 92, 92),
    "NoMatch text": hsl_hex(220, 15, 32),
    "NoMatch tint": hsl_hex(220, 15, 93),
    "Gold rule (navy only)": None,
}
for k, v in proposed.items():
    if v:
        print(f"proposed {k:14s} {v}")
checks += [
    ("Ready text on Ready tint", proposed["Ready text"], proposed["Ready tint"]),
    ("Ready text on white", proposed["Ready text"], white),
    ("Needs text on Needs tint", proposed["Needs text"], proposed["Needs tint"]),
    ("Needs text on white", proposed["Needs text"], white),
    ("NoMatch text on NoMatch tint", proposed["NoMatch text"], proposed["NoMatch tint"]),
    ("NoMatch text on white", proposed["NoMatch text"], white),
    ("--foreground on --warning (solid amber badge)", fg, H["--medium / --warning"]),
]
gold = px(600, gy)
checks += [
    ("sampled gold on sampled navy", gold, px(10, 10)),
    ("sampled gold on white", gold, white),
    ("sampled gold on --brand-navy", gold, navy),
    ("white on --primary-hover (button fix)", white, H["--primary-hover"]),
    ("--primary-hover as link on white", H["--primary-hover"], white),
    ("--primary-hover on header warm bg", H["--primary-hover"], H["header home bg hsl(40,20%,96%)"]),
    ("--foreground on header warm bg", fg, H["header home bg hsl(40,20%,96%)"]),
    ("white on theme-color #0a1e3f", white, "#0a1e3f"),
]
for name, a, b in checks:
    r = ratio(a, b)
    print(f"{name:48s} {a} on {b}: {r:5.2f}:1  {'PASS' if r >= 4.5 else 'FAIL'} (4.5)")
