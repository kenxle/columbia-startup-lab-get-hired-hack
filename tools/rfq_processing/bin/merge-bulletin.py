"""Resolve a git conflict in docs/BULLETIN.md by keeping every row from both sides, newest first."""
import re, sys
path = sys.argv[1] if len(sys.argv) > 1 else "docs/BULLETIN.md"
text = open(path).read()
pat = re.compile(r"<<<<<<< [^\n]*\n(.*?)\n=======\n(.*?)\n>>>>>>> [^\n]*\n", re.S)
def t(r): return r.split("|")[2].strip()
while True:
    m = pat.search(text)
    if not m:
        break
    rows = [r for r in (m.group(1) + "\n" + m.group(2)).split("\n") if r.startswith("| 2026-")]
    seen = []
    for r in rows:
        if r not in seen:
            seen.append(r)
    seen.sort(key=t, reverse=True)
    text = text[:m.start()] + "\n".join(seen) + "\n" + text[m.end():]
    print("merged", len(seen), "rows:", ", ".join(t(r) + " " + r.split("|")[3].strip() for r in seen))
open(path, "w").write(text)
