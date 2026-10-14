#!/usr/bin/env python3
"""Counts the App Store texts in docs/appstore/metadata.md against Apple's limits."""
import re, pathlib

LIMITS = {"Subtitle": 30, "Untertitel": 30, "Promotional text": 170, "Werbetext": 170,
          "Keywords": 100, "Schlüsselwörter": 100, "Description": 4000, "Beschreibung": 4000}
text = (pathlib.Path(__file__).parents[2] / "docs/appstore/metadata.md").read_text()
ok = True
for m in re.finditer(r"\*\*([^*\n]+?)\*\* \(max\. \d+.*?\)\n\n```\n(.*?)\n```", text, re.S):
    name, value = m.group(1), m.group(2)
    limit = LIMITS[name]
    flag = "ok" if len(value) <= limit else "TOO LONG"
    ok &= len(value) <= limit
    print(f"{name:18} {len(value):5} / {limit:4}  {flag}")
    if name.startswith(("Keywords", "Schlüssel")) and " " in value:
        print("  ** keywords contain spaces **"); ok = False
raise SystemExit(0 if ok else 1)
