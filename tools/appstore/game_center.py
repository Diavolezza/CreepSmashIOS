#!/usr/bin/env python3
"""Game Center configuration for App Store Connect, generated from the app's own data.

Writes docs/appstore/game-center.md (identifiers, titles, descriptions and points of all leaderboards and
achievements, in English and German) and, with --images, the images Game Center needs (1024 × 1024 PNG)
to build/appstore/game-center/. Run from anywhere:  python3 tools/appstore/game_center.py [--images]

Sources: the tiers in CreepSmashCore/.../Progress.swift (Achievement.all), the titles and requirements in
CreepSmash/ProgressStore.swift and their German texts in CreepSmash/Localizable.xcstrings.
"""
import json, math, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
progress = (ROOT / "CreepSmashCore/Sources/CreepSmashCore/Progress.swift").read_text()
store = (ROOT / "CreepSmash/ProgressStore.swift").read_text()
strings = json.loads((ROOT / "CreepSmash/Localizable.xcstrings").read_text())["strings"]

# Achievements and tiers, in the order of Achievement.all ("allMaps" has one tier: the number of maps)
maps = len(re.findall(r'id: "[a-z]+"', (ROOT / "CreepSmashCore/Sources/CreepSmashCore/BuiltInMaps.swift").read_text()))
achievements = [(m.group(1), [maps if t.strip() == "GameMap.all.count" else int(t.replace("_", "")) for t in m.group(2).split(",")])
                for m in re.finditer(r'Achievement\(id: "(\w+)", tiers: \[([^\]]+)\]', progress)]
constants = {name: int(value) for name, value in re.findall(r"static let (\w+) = (\d+)", progress)}


def block(name):
    """The cases of a switch in ProgressStore.swift: id -> English key (with Swift interpolations)."""
    start = store.index(name)
    end = store.index("\n    }\n", start)
    return {k: v for k, v in re.findall(r'case "(\w+)":(?: return)? L\("((?:[^"\\]|\\.)*)"\)', store[start:end])}


titles, requirements, once = block("var title: String"), block("func requirement("), block("private var requirementOnce")


def localize(key_en, values, lang):
    """English text with Swift interpolations -> the text in `lang` with the values put in."""
    key = re.sub(r"\\\((n|threshold)\)", "%@", key_en)
    key = re.sub(r"\\\([^)]*(?:\([^)]*\))?[^)]*\)", "%lld", key)
    key = re.sub(r"(?<!%)%(?![@l%])", "%%", key)
    text = key if lang == "en" else strings[key]["localizations"]["de"]["stringUnit"]["value"]
    values = list(values)
    text = re.sub(r"%(@|lld)", lambda _: str(values.pop(0)), text)
    return text.replace("%%", "%")


def number(n, lang):
    s = f"{n:,}"
    return s.replace(",", ".") if lang == "de" else s


def args_of(key_en, n, lang):
    """Values for the placeholders of a requirement: the threshold, constants of PlayerRecord."""
    out = []
    for expr in re.findall(r"\\\(([^)]*(?:\([^)]*\))?[^)]*)\)", key_en):
        if expr in ("n", "threshold"):
            out.append(number(n, lang))
        else:
            c = re.search(r"PlayerRecord\.(\w+)\s*/\s*(\d+)", expr)
            out.append(constants[c.group(1)] // int(c.group(2)) if c else expr)
    return out


POINTS = {1: [25], 2: [10, 25], 3: [10, 20, 45]}
SPECIAL_POINTS = {"allMaps": 50}

rows, total = [], 0
for aid, tiers in achievements:
    points = [SPECIAL_POINTS.get(aid, p) for p in POINTS[len(tiers)]]
    for tier, (threshold, pts) in enumerate(zip(tiers, points), start=1):
        total += pts
        row = {"id": f"cs.{aid}.{tier}", "points": pts, "image": f"{aid}-{tier}.png", "tier": tier, "tiers": len(tiers),
               "symbol": aid}
        for lang in ("en", "de"):
            title = localize(titles[aid], [], lang)
            if len(tiers) > 1:
                title += " " + "I" * tier if tier < 4 else str(tier)
            key = once[aid] if threshold == 1 and aid in once else requirements[aid]
            row[f"title_{lang}"] = title
            row[f"desc_{lang}"] = localize(key, args_of(key, threshold, lang), lang)
        rows.append(row)

levels = [("easy", "Easy", "Leicht"), ("normal", "Normal", "Normal"), ("hard", "Hard", "Schwer")]
boards = []
for raw, en, de in levels:
    for n in (1, 2, 3):
        boards.append({"id": f"cs.fastest.{raw}.{n}",
                       "title_en": f"Fastest · {en} · {n} opponent{'s' if n > 1 else ''}",
                       "title_de": f"Bestzeit · {de} · {n} Gegner",
                       "image": f"fastest-{raw}-{n}.png", "level": raw, "n": n})

# Challenges: one per leaderboard (players challenge each other on it); allowed duration three days.
challenges = []
for raw, en, de in levels:
    for n in (1, 2, 3):
        challenges.append({"id": f"cs.challenge.{raw}.{n}", "board": f"cs.fastest.{raw}.{n}",
                           "title_en": f"Race · {en} · {n} opponent{'s' if n > 1 else ''}",
                           "title_de": f"Wettlauf · {de} · {n} Gegner",
                           "desc_en": (f"Who beats the computer on {en} the fastest?" if n == 1
                                       else f"Who beats {n} computers on {en} the fastest?"),
                           "desc_de": (f"Wer schlägt den Computer auf {de} am schnellsten?" if n == 1
                                       else f"Wer schlägt {n} Computer auf {de} am schnellsten?"),
                           "image": f"challenge-{raw}-{n}.png", "level": raw, "n": n})
# Activity: the link from the Games app (and from a challenge) straight to a game against the computer; the
# leaderboards carry the difficulty and the number of opponents as its properties.
activity = {"id": "cs.activity.computer", "title_en": "Vs. computer", "title_de": "Gegen Computer",
            "desc_en": "Beat one to three computers as fast as you can.",
            "desc_de": "Schlag einen bis drei Computer, so schnell du kannst.",
            "image": "activity-computer.png", "fallback": "https://diavolezza.github.io/creepsmash/support.html"}

doc = [
    "# Game Center – configuration for App Store Connect",
    "",
    "Generated by `tools/appstore/game_center.py` from the app's achievements and texts – do not edit by hand.",
    "Images (1024 × 1024 PNG): `python3 tools/appstore/game_center.py --images` → `build/appstore/game-center/`.",
    "",
    "## Steps once the developer account is active",
    "",
    "1. Xcode › target CreepSmash › Signing & Capabilities: add **Game Center** (adds the entitlement).",
    "2. `Config/Info.plist`: set `CSGameCenter` to YES (it is NO now) – this switches on sign-in, leaderboards, achievements and",
    "   the \"Game Center\" button on the multiplayer page (`CreepSmash/GameCenter.swift`).",
    "3. App Store Connect › the app › Game Center: enable it for the version and create the leaderboards and",
    "   achievements below (or in Xcode: File › New › File › GameKit Bundle, then push it to App Store Connect;",
    "   Xcode's Game Progress Manager can test them before).",
    "4. Multiplayer compatibility: Game Center only matches devices with the same protocol version",
    "   (`playerGroup` = `NetMessage.protocolVersion`).",
    "",
    f"## Leaderboards ({len(boards)}, classic)",
    "",
    "Score format: **Elapsed Time – To the Second** (score = seconds of play), sort order **Low to High**,",
    "score range 1 – 36000, submission type **Best Score**. Mirrors the leaderboard on the device (fastest",
    "wins per difficulty and number of computer opponents).",
    "",
    "| ID | Title (en) | Title (de) | Image |",
    "|---|---|---|---|",
] + [f"| `{b['id']}` | {b['title_en']} | {b['title_de']} | {b['image']} |" for b in boards] + [
    "",
    f"## Challenges ({len(challenges)})",
    "",
    "One per leaderboard. Type **Leaderboard**, allowed duration **3 days**, repeatable (the player who challenges",
    "chooses 1, 3 or unlimited tries). Default image 3840 × 2160.",
    "",
    "| ID | Leaderboard | Name (en) | Description (en) | Name (de) | Description (de) | Image |",
    "|---|---|---|---|---|---|---|",
] + [f"| `{c['id']}` | `{c['board']}` | {c['title_en']} | {c['desc_en']} | {c['title_de']} | {c['desc_de']} | {c['image']} |"
     for c in challenges] + [
    "",
    "## Activity (1)",
    "",
    "Opens a game against the computer from the Games app or from a challenge. 1 player, no party code.",
    f"Fallback URL (systems before iOS 26): {activity['fallback']}. Every leaderboard links to it with the",
    "properties `level` (easy, normal, hard) and `opponents` (1–3); the app opens the setup page with them.",
    "Image 3840 × 2160.",
    "",
    "| ID | Name (en) | Description (en) | Name (de) | Description (de) | Image |",
    "|---|---|---|---|---|---|",
    f"| `{activity['id']}` | {activity['title_en']} | {activity['desc_en']} | {activity['title_de']} | {activity['desc_de']} | {activity['image']} |",
] + [
    "",
    f"## Achievements ({len(rows)}, {total} points of max. 1000)",
    "",
    "One Game Center achievement per tier of an app achievement; the app reports the progress of each tier",
    "(percent of its threshold). Not hidden, achievable more than once: no. The pre-earned and the earned",
    "description are the same (the requirement).",
    "",
    "| ID | Points | Title (en) | Description (en) | Title (de) | Description (de) | Image |",
    "|---|---:|---|---|---|---|---|",
] + [f"| `{r['id']}` | {r['points']} | {r['title_en']} | {r['desc_en']} | {r['title_de']} | {r['desc_de']} | {r['image']} |"
     for r in rows]
too_long = [t for x in boards + rows + challenges + [activity] for k, t in x.items() if (k.startswith("title") and len(t) > 30) or (k.startswith("desc") and len(t) > 200)]
if too_long:
    sys.exit(f"** too long for Game Center (names 30, descriptions 200): {too_long}")
(ROOT / "docs/appstore/game-center.md").write_text("\n".join(doc) + "\n")
print(f"{len(boards)} leaderboards, {len(rows)} achievements ({total} points), {len(challenges)} challenges, 1 activity"
      " → docs/appstore/game-center.md")
if total > 1000:
    sys.exit("** more than 1000 points **")

if "--images" not in sys.argv:
    sys.exit(0)

# Images: a neon medal in the color of the tier (green, yellow, red – as the tower levels), a line
# pictogram of the achievement inside; leaderboards: a stopwatch with the number of opponents.
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = ROOT / "build/appstore/game-center"
OUT.mkdir(parents=True, exist_ok=True)
S = 1024
TIER = {1: (57, 255, 122), 2: (255, 213, 74), 3: (255, 82, 82)}
ONE = (120, 200, 255)
font = ImageFont.truetype(str(ROOT / "CreepSmash/Fonts/PressStart2P-Regular.ttf"), 120)


def canvas():
    return Image.new("RGB", (S, S), (8, 10, 14))


def glow(draw_fn, color, width=26):
    """Draws the lines twice: blurred wide for the glow, then sharp."""
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    draw_fn(d, color, width * 2)
    blurred = layer.filter(ImageFilter.GaussianBlur(28))
    sharp = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw_fn(ImageDraw.Draw(sharp), color, width)
    return blurred, sharp


def compose(base, *drawings):
    img = base.convert("RGBA")
    for fn, color in drawings:
        b, s = glow(fn, color)
        img = Image.alpha_composite(img, b)
        img = Image.alpha_composite(img, s)
    return img.convert("RGB")


def ring(d, c, w):
    d.ellipse((92, 92, S - 92, S - 92), outline=c, width=w)


C = S // 2


def poly(d, pts, c, w, closed=True):
    pts = [(C + x, C + y) for x, y in pts]
    d.line(pts + ([pts[0]] if closed else []), fill=c, width=w, joint="curve")


def circle(d, x, y, r, c, w):
    d.ellipse((C + x - r, C + y - r, C + x + r, C + y + r), outline=c, width=w)


def pict(name):
    """Line pictograms, centered, about 520 px."""
    def f(d, c, w):
        if name == "wins":                                             # trophy
            poly(d, [(-150, -190), (150, -190), (120, 0), (40, 60), (40, 150), (110, 190), (-110, 190), (-40, 150), (-40, 60), (-120, 0)], c, w)
            d.arc((C - 260, C - 190, C - 110, C - 30), 90, 270, fill=c, width=w)
            d.arc((C + 110, C - 190, C + 260, C - 30), 270, 90, fill=c, width=w)
        elif name == "winsHard":                                       # the computer: a chip with pins and a lightning
            d.rounded_rectangle((C - 150, C - 150, C + 150, C + 150), radius=24, outline=c, width=w)
            for k in (-90, 0, 90):
                for a, b in (((k, -150), (k, -230)), ((k, 150), (k, 230)), ((-150, k), (-230, k)), ((150, k), (230, k))):
                    poly(d, [a, b], c, w, closed=False)
            poly(d, [(20, -95), (-60, 15), (5, 15), (-20, 95), (60, -15), (-5, -15)], c, w)
        elif name == "onlineWins":                                     # two crossed swords
            for sx in (1, -1):
                poly(d, [(-200 * sx, -200), (150 * sx, 150)], c, w, closed=False)          # blade
                poly(d, [(95 * sx, 185), (185 * sx, 95)], c, w, closed=False)              # cross guard
                poly(d, [(150 * sx, 150), (215 * sx, 215)], c, w, closed=False)            # grip
        elif name in ("flawless", "closeCall"):                       # heart (cracked: close call)
            poly(d, [(0, 190), (-200, -10), (-200, -120), (-130, -190), (-50, -190), (0, -120), (50, -190), (130, -190), (200, -120), (200, -10)], c, w)
            if name == "closeCall":
                poly(d, [(0, -120), (-40, -40), (30, 20), (-20, 110)], c, w, closed=False)
        elif name == "fastWin":                                        # bolt
            poly(d, [(40, -230), (-150, 30), (-10, 30), (-60, 230), (150, -40), (10, -40)], c, w)
        elif name == "efficient":                                      # leaf: two curves and the midrib
            ends = ((-170, 170), (190, -190))
            def side(sign):
                return [(ends[0][0] + (ends[1][0] - ends[0][0]) * t / 20 + sign * 130 * math.sin(math.pi * t / 20) * 0.7071,
                         ends[0][1] + (ends[1][1] - ends[0][1]) * t / 20 + sign * 130 * math.sin(math.pi * t / 20) * 0.7071)
                        for t in range(21)]
            poly(d, side(1) + side(-1)[::-1], c, w)
            poly(d, [(-230, 230), (110, -110)], c, w, closed=False)
        elif name == "lean":                                           # scale
            poly(d, [(0, -200), (0, 190)], c, w, closed=False)
            poly(d, [(-120, 190), (120, 190)], c, w, closed=False)
            poly(d, [(-200, -130), (200, -130)], c, w, closed=False)
            poly(d, [(-200, -130), (-260, 30), (-140, 30)], c, w)
            poly(d, [(200, -130), (140, 30), (260, 30)], c, w)
        elif name == "allMaps":                                        # folded map
            poly(d, [(-240, -170), (-80, -210), (80, -170), (240, -210), (240, 170), (80, 210), (-80, 170), (-240, 210)], c, w)
            poly(d, [(-80, -210), (-80, 170)], c, w, closed=False); poly(d, [(80, -170), (80, 210)], c, w, closed=False)
        elif name == "streak":                                         # flame
            poly(d, [(0, -240), (120, -60), (160, 70), (90, 190), (-90, 190), (-160, 70), (-110, -40), (-60, 30)], c, w)
        elif name == "creepsKilled":                                   # crosshair
            circle(d, 0, 0, 170, c, w)
            for a, b in [((0, -250), (0, -90)), ((0, 90), (0, 250)), ((-250, 0), (-90, 0)), ((90, 0), (250, 0))]:
                poly(d, [a, b], c, w, closed=False)
        elif name == "creepsSent":                                     # arrow up right
            poly(d, [(-180, 180), (170, -170)], c, w, closed=False)
            poly(d, [(-20, -180), (180, -180), (180, 20)], c, w, closed=False)
        elif name == "towersBuilt":                                    # tower: base and barrel
            poly(d, [(-170, 200), (170, 200), (120, 40), (-120, 40)], c, w)
            circle(d, 0, -20, 110, c, w)
            poly(d, [(40, -90), (180, -230)], c, w, closed=False)
        elif name == "income":                                         # coin
            circle(d, 0, 0, 210, c, w)
            d.text((C, C + 8), "$", font=ImageFont.truetype(str(ROOT / "CreepSmash/Fonts/PressStart2P-Regular.ttf"), 230), fill=c, anchor="mm")
        elif name == "ultimate":                                       # star
            pts = [(math.sin(math.radians(36 * k)) * (230 if k % 2 == 0 else 95), -math.cos(math.radians(36 * k)) * (230 if k % 2 == 0 else 95)) for k in range(10)]
            poly(d, pts, c, w)
        elif name == "colossus":                                       # big spaceship
            poly(d, [(0, -230), (190, 120), (90, 70), (0, 200), (-90, 70), (-190, 120)], c, w)
            circle(d, 0, -20, 50, c, w)
        elif name == "games":                                          # controller
            d.rounded_rectangle((C - 250, C - 130, C + 250, C + 150), radius=110, outline=c, width=w)
            poly(d, [(-150, 10), (-70, 10)], c, w, closed=False); poly(d, [(-110, -30), (-110, 50)], c, w, closed=False)
            circle(d, 100, -10, 22, c, w); circle(d, 160, 50, 22, c, w)
        else:
            d.text((C, C), "?", font=font, fill=c, anchor="mm")
    return f


for r in rows:
    color = ONE if r["tiers"] == 1 else TIER[r["tier"]]
    img = compose(canvas(), (ring, color), (pict(r["symbol"]), color))
    if r["tiers"] > 1:  # tier dots below the pictogram
        d = ImageDraw.Draw(img)
        for k in range(r["tiers"]):
            x = C + (k - (r["tiers"] - 1) / 2) * 70
            fill = color if k < r["tier"] else None
            d.ellipse((x - 20, S - 230, x + 20, S - 190), outline=color, width=8, fill=fill)
    img.save(OUT / r["image"])

LEVEL = {"easy": (57, 255, 122), "normal": (255, 213, 74), "hard": (255, 82, 82)}


def stopwatch(n):
    def f(d, c, w):
        circle(d, 0, 40, 230, c, w)
        poly(d, [(0, -190), (0, -250)], c, w, closed=False)
        poly(d, [(-60, -260), (60, -260)], c, w, closed=False)
        poly(d, [(0, 40), (110, -60)], c, w, closed=False)
    return f


for b in boards:
    c = LEVEL[b["level"]]
    img = compose(canvas(), (ring, c), (stopwatch(b["n"]), c))
    d = ImageDraw.Draw(img)
    d.text((C, C + 160), "1v" + str(b["n"]), font=ImageFont.truetype(str(ROOT / "CreepSmash/Fonts/PressStart2P-Regular.ttf"), 64), fill=c, anchor="mm")
    img.save(OUT / b["image"])
# Challenges and the activity: 3840 × 2160, no transparency. The synthwave ground of the app's start screen
# (horizon, perspective grid, stars), the stopwatch of the leaderboard large on it with "1v1" … "1v3",
# on the right (the Games app writes the title over the lower left).
W, H = 3840, 2160
GREEN = (61, 255, 126)


def wide_ground(seed):
    import random
    rnd = random.Random(seed)
    img = Image.new("RGB", (W, H), (5, 7, 10))
    d = ImageDraw.Draw(img)
    horizon = int(H * 0.62)
    for y in range(horizon):                                   # sky: dark to a green haze at the horizon
        t = y / horizon
        d.line([(0, y), (W, y)], fill=(int(5 + 6 * t), int(7 + 40 * t ** 3), int(10 + 14 * t ** 3)))
    for _ in range(260):
        x, y, r = rnd.randrange(W), rnd.randrange(horizon - 80), rnd.choice((2, 3, 3, 4, 5))
        g = rnd.randrange(120, 230)
        d.ellipse((x - r, y - r, x + r, y + r), fill=(g, g, g))
    grid = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    g = ImageDraw.Draw(grid)
    cx = W // 2
    for k in range(-26, 27):                                   # lines to the vanishing point
        g.line([(cx + k * 40, horizon), (cx + k * 520, H)], fill=GREEN + (150,), width=5)
    y, step = horizon, 18
    while y < H:                                               # cross lines, wider apart towards the front
        g.line([(0, y), (W, y)], fill=GREEN + (150,), width=5)
        y += step
        step = int(step * 1.32) + 2
    g.line([(0, horizon), (W, horizon)], fill=GREEN + (255,), width=10)
    img = Image.alpha_composite(img.convert("RGBA"), grid.filter(ImageFilter.GaussianBlur(10)))
    return Image.alpha_composite(img, grid)


def wide_glow(img, draw_fn, color, width):
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw_fn(ImageDraw.Draw(layer), color, width * 2)
    img = Image.alpha_composite(img, layer.filter(ImageFilter.GaussianBlur(40)))
    sharp = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw_fn(ImageDraw.Draw(sharp), color, width)
    return Image.alpha_composite(img, sharp)


def big_stopwatch(cx, cy, r):
    def f(d, c, w):
        d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=c, width=w)
        d.line([(cx, cy - r), (cx, cy - r - 110)], fill=c, width=w)
        d.line([(cx - 120, cy - r - 120), (cx + 120, cy - r - 120)], fill=c, width=w)
        d.line([(cx, cy), (cx + int(r * 0.48), cy - int(r * 0.42))], fill=c, width=w)
        d.line([(cx + int(r * 0.78), cy - int(r * 0.78)), (cx + int(r * 0.9), cy - int(r * 0.9))], fill=c, width=w)
    return f


big = ImageFont.truetype(str(ROOT / "CreepSmash/Fonts/PressStart2P-Regular.ttf"), 210)
for ch in challenges:
    c = LEVEL[ch["level"]]
    # The Games app writes the title over the lower left of the image: the stopwatch stays on the right.
    cx = int(W * 0.74)
    img = wide_glow(wide_ground(ch["id"]), big_stopwatch(cx, 860, 520), c, 34)
    d = ImageDraw.Draw(img)
    d.text((cx, 1150), "1v" + str(ch["n"]), font=big, fill=c, anchor="mm")
    img.convert("RGB").save(OUT / ch["image"])

# The activity: the three difficulties as three stopwatches side by side.
img = wide_ground("activity")
for k, (raw, _, _) in enumerate(levels):
    img = wide_glow(img, big_stopwatch(int(W * 0.74) + (k - 1) * 620, 900, 280), LEVEL[raw], 26)
img.convert("RGB").save(OUT / activity["image"])
print(f"{len(rows) + len(boards) + len(challenges) + 1} images → {OUT.relative_to(ROOT)}")
