"""Summarizes the exported power tables of build/energy/<label>/ (xctrace export) per scene."""
import sys, glob, os, xml.etree.ElementTree as ET
from collections import defaultdict

def rows(path):
    root = ET.parse(path).getroot()
    node = root.find("node")
    if node is None: return []
    cols = [c.findtext("mnemonic") for c in node.find("schema").findall("col")]
    ids, out = {}, []
    def val(el):
        if "ref" in el.attrib: return ids[el.attrib["ref"]]
        v = (el.text or "").strip()
        sub = list(el)
        if sub and not v: v = {c.tag: val(c) for c in sub}
        if "id" in el.attrib: ids[el.attrib["id"]] = (v, el.attrib.get("fmt"))
        return (v, el.attrib.get("fmt"))
    for r in node.findall("row"):
        cells = [c for c in r if c.tag != "sentinel"]
        out.append({k: val(c) for k, c in zip(cols, cells)})
    return out

def num(v):
    try: return float(v[0])
    except Exception: return None

label = sys.argv[1] if len(sys.argv) > 1 else "before"
D = f"build/energy/{label}"
SKIP = 8e9  # ignore the first 8 s (launch)
for scene in ("menu", "menu-music", "duel", "four"):
    p = f"{D}/{scene}.SystemPowerLevel.xml"
    if not os.path.exists(p): continue
    sp = [r for r in rows(p) if num(r["start"]) and num(r["start"]) > SKIP]
    power = [num(r["power-usage"]) for r in sp if num(r["power-usage"]) is not None]
    imp = defaultdict(float); secs = 0.0
    for r in rows(f"{D}/{scene}.ProcessSubsystemPowerImpact.xml"):
        name = r.get("process-name", ("",))[0]
        if name != "CreepSmash" or (num(r["start"]) or 0) < SKIP: continue
        d = (num(r["duration"]) or 0) / 1e9; secs += d
        for k in ("cpu-impact", "gpu-impact", "display-impact", "networking-impact"):
            imp[k] += (num(r[k]) or 0) * d
    cpu = []
    for r in rows(f"{D}/{scene}.ProcessCPUUsage.xml"):
        proc = r.get("process", ({}, ""))[1] or ""
        if "CreepSmash" in proc and (num(r.get("start", (0,))) or 0) > SKIP:
            for k, v in r.items():
                if k not in ("start", "duration", "process") and num(v) is not None:
                    cpu.append((k, num(v)))
    avg = lambda xs: sum(xs) / len(xs) if xs else float("nan")
    keys = sorted({k for k, _ in cpu})
    cpu_avg = {k: avg([v for kk, v in cpu if kk == k]) for k in keys}
    print(f"{scene:11s} battery {avg(power):5.1f} %/h | impact/s cpu {imp['cpu-impact']/max(secs,1):6.2f} gpu {imp['gpu-impact']/max(secs,1):6.2f}"
          f" display {imp['display-impact']/max(secs,1):6.2f} net {imp['networking-impact']/max(secs,1):5.2f} | {secs:4.0f}s | cpu cols {cpu_avg}")
