"""Gauge comparison math for the domain-rules research file.
Values: Metal Supermarkets gauge chart (mild steel, aluminum, stainless, galvanized).
Prints thickness differences in percent between tables, and unit conversions.
"""

CHART = {
    # gauge: (mild, aluminum, stainless, galvanized)
    10: (0.1345, 0.1019, 0.14062, 0.1382),
    11: (0.1196, 0.09074, 0.125, 0.1233),
    12: (0.1046, 0.08081, 0.10937, 0.1084),
    14: (0.0747, 0.06408, 0.07812, 0.0785),
    16: (0.0598, 0.05082, 0.0625, 0.0635),
    18: (0.0478, 0.04030, 0.050, 0.0516),
    20: (0.0359, 0.03196, 0.0375, 0.0396),
}


def pct(a, b):
    """Percent by which b is thicker than a."""
    return (b - a) / a * 100.0


print("gauge | stainless vs mild | galv vs mild | aluminum vs mild (pct thickness difference)")
for g, (mild, alu, ss, gal) in CHART.items():
    print(f"{g:>5} | {pct(mild, ss):+6.1f}% | {pct(mild, gal):+6.1f}% | {pct(mild, alu):+6.1f}%")

print()
print("PRD example: '16ga stainless' read with mild steel table (0.0598) vs stainless table (0.0625) vs '0.060 in'")
print(f"  stainless 16ga vs 0.060: {pct(0.060, 0.0625):+.1f}%")
print(f"  mild 16ga vs 0.060: {pct(0.060, 0.0598):+.1f}%")
print(f"  stainless 16ga vs mild 16ga: {pct(0.0598, 0.0625):+.1f}%")

print()
print("Iowa RFQ line: 48 x 120 x 16 Ga stainless; 19 sheets")
print(f"  area per sheet sq ft: {48*120/144:.1f}")

print()
print("Size conversions")
print(f"  4 ft x 8 ft = {4*12} in x {8*12} in")
print(f"  48 in x 96 in = {48*25.4:.0f} mm x {96*25.4:.0f} mm")
print(f"  5 ft x 10 ft = {5*12} in x {10*12} in = {60*25.4:.0f} mm x {120*25.4:.0f} mm")
print(f"  4 x 10 ft = 48 in x 120 in; 120 in = {120/12:.0f} ft")
print(f"  0.250 in = {0.25*25.4:.2f} mm; 3/16 in = {3/16:.4f} in = {3/16*25.4:.2f} mm")
print(f"  1/8 in = {1/8:.3f} in; 1/4 in = {1/4:.3f}; 1/2 in = {1/2:.3f}; 3/8 in = {3/8:.3f}")
print(f"  SacRT plate 8 ft x 20 ft x 1 in: {8*12} in x {20*12} in")

print()
print("Fractions vs gauge near-collisions (stainless 11ga 0.125 = 1/8 in): ", 1/8)
print("Stainless 14ga 0.07812 vs mild 14ga 0.0747 pct:", f"{pct(0.0747, 0.07812):+.1f}%")
print("Aluminum 14ga Metal Supermarkets 0.06408 vs Wikipedia 0.063:", f"{pct(0.063, 0.06408):+.1f}%")
print("Speedy 10ga stainless 0.135 vs stainless table 0.14062:", f"{pct(0.14062, 0.135):+.1f}%")
print("UAlberta 0.063 vs stainless table 0.0625:", f"{pct(0.0625, 0.063):+.1f}%")

print()
print("Absolute and relative gaps used in the findings")
print("  16ga stainless 0.0625 minus mild 0.0598 =", round(0.0625 - 0.0598, 4), "in")
print("  14ga tube wall 0.083 vs 14ga mild sheet 0.0747:", f"{pct(0.0747, 0.083):+.1f}%")
print("  16ga tube wall 0.065 vs 16ga mild sheet 0.0598:", f"{pct(0.0598, 0.065):+.1f}%")
print("  11ga stainless 0.125 vs 11ga mild 0.1196:", f"{pct(0.1196, 0.125):+.1f}%")
print("  16ga aluminum 0.05082 vs 16ga stainless 0.0625:", f"{pct(0.0625, 0.05082):+.1f}%")
print("  16ga galv 0.0635 minus mild 0.0598 =", round(0.0635 - 0.0598, 4), "in")
print("  3 mm in inches:", round(3 / 25.4, 4))
print("  0.230 in in mm:", round(0.230 * 25.4, 2), "; 0.180 in in mm:", round(0.180 * 25.4, 2))
print("  1 1/4 in =", 1.25, "; 1 1/2 in =", 1.5)
print("  21 ft in inches:", 21 * 12, "; 20 ft:", 20 * 12, "; 24 ft:", 24 * 12, "; 12 ft:", 12 * 12)
