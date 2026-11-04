"""Usage: python3 tools/energy/profile_top.py build/energy/<label>/four-time.xml (a time-profile table exported with xctrace)."""
import sys, xml.etree.ElementTree as ET
from collections import Counter
root = ET.parse(sys.argv[1]).getroot()
ids = {}
selfc, incl = Counter(), Counter()
n = 0
for row in root.iter("row"):
    bt = None
    for c in row:
        if c.tag in ("backtrace", "tagged-backtrace"):
            bt = c
    thread = row.find("thread")
    if bt is None: continue
    if "ref" in bt.attrib: frames = ids.get(bt.attrib["ref"], [])
    else:
        frames = []
        for f in bt.iter("frame"):
            if "ref" in f.attrib: name = ids.get("f" + f.attrib["ref"], "?")
            else:
                name = f.attrib.get("name", "?"); ids["f" + f.attrib.get("id", "")] = name
            frames.append(name)
        if "id" in bt.attrib: ids[bt.attrib["id"]] = frames
    if not frames: continue
    n += 1
    selfc[frames[0]] += 1
    for name in set(frames): incl[name] += 1
print("samples", n)
print("== self"); [print(f"{c*100/n:5.1f}%  {k[:110]}") for k, c in selfc.most_common(22)]
print("== inclusive (CreepSmash/SwiftUI)")
for k, c in incl.most_common(400):
    if any(s in k for s in ("Board", "Game", "Bot", "draw", "Render", "Canvas", "step", "frame", "Controller", "think", "update", "Creep", "Tower")):
        print(f"{c*100/n:5.1f}%  {k[:110]}")
