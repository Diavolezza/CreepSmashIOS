"""Draws the creep and tower sprites and the button symbols made from them.

All game graphics are our own designs: line drawings with a soft neon glow, in the spirit of the
original's vector look (spaceships, and cannons that shoot at them). They are rendered large and
anti-aliased, so they stay sharp when the app shows them big (on the buttons) or small (on the board).

Colors carry meaning, as in the original:
- Creeps cycle green, gray, yellow, red within each group of four; WHITE means the creep cannot be
  slowed down (Ray, Shark, Phoenix). Slow-immune creeps also carry a shield arc at the nose.
- Towers: the color shows the level – green, yellow, red, white.

The script writes:
- Creeps/creepN.png         128x128, facing right (+x); the app rotates them along the path.
- Towers/towerK[L].png      128x128, barrel pointing up, base in the center (the app turns it).
- Buttons/towerButtonK.png  the level-1 tower, plus the grayed-out ...disable.png.
- Buttons/creepIconN.png    the creep cut to its size (not square), plus ...disable.png.

Usage (from the repository root): python3 tools/sprites/sprites.py [--preview out.png]
"""
import math
import os
import sys
from PIL import Image, ImageDraw, ImageFilter

ASSETS = "CreepSmash/Assets.xcassets"
SIZE = 128          # final image size
SS = 6              # supersampling factor
LINE = 4.2          # line width in drawing units (the drawing area is 100 x 100)

GREEN, GRAY, YELLOW, RED, WHITE = "#3dff5a", "#9da3ad", "#ffd633", "#ff4040", "#ffffff"


# --- drawing --------------------------------------------------------------------------------

class Pen:
    """Collects shapes in 0..100 units and renders them as glowing lines."""

    def __init__(self):
        self.shapes = []

    def poly(self, *pts, closed=True):
        self.shapes.append(("poly", pts, closed))
        return self

    def line(self, *pts):
        return self.poly(*pts, closed=False)

    def circle(self, cx, cy, r):
        self.shapes.append(("circle", (cx, cy, r), True))
        return self

    def arc(self, cx, cy, r, start, end):
        """Arc in degrees, 0 = right (+x), counter-clockwise on screen = negative y."""
        steps = max(6, int(abs(end - start) / 6))
        pts = [(cx + r * math.cos(math.radians(start + (end - start) * i / steps)),
                cy - r * math.sin(math.radians(start + (end - start) * i / steps))) for i in range(steps + 1)]
        return self.poly(*pts, closed=False)

    def mirrored(self, *pts, closed=True):
        """Polygon symmetric to the horizontal center line: pts are the upper half from nose to tail."""
        lower = [(x, 100 - y) for x, y in reversed(pts) if y != 50]
        return self.poly(*(list(pts) + lower), closed=closed)

    def moved(self, dy):
        """The whole drawing shifted vertically."""
        shapes = []
        for kind, data, closed in self.shapes:
            if kind == "circle":
                cx, cy, r = data
                shapes.append((kind, (cx, cy + dy, r), closed))
            else:
                shapes.append((kind, tuple((x, y + dy) for x, y in data), closed))
        self.shapes = shapes
        return self

    def scaled(self, f):
        """The whole drawing enlarged by f around the center (small ships would get lost otherwise)."""
        def q(pt):
            return (50 + (pt[0] - 50) * f, 50 + (pt[1] - 50) * f)
        shapes = []
        for kind, data, closed in self.shapes:
            if kind == "circle":
                cx, cy, r = data
                shapes.append((kind, (*q((cx, cy)), r * f), closed))
            else:
                shapes.append((kind, tuple(q(pt) for pt in data), closed))
        self.shapes = shapes
        return self

    def draw(self, draw, scale, width, color):
        def p(pt):
            return (pt[0] * scale, pt[1] * scale)
        for kind, data, closed in self.shapes:
            if kind == "circle":
                cx, cy, r = data
                draw.ellipse([p((cx - r, cy - r)), p((cx + r, cy + r))], outline=color, width=width)
            else:
                pts = [p(q) for q in data] + ([p(data[0])] if closed else [])
                draw.line(pts, fill=color, width=width, joint="curve")
                for q in pts:  # round line ends and corners
                    rr = width / 2
                    draw.ellipse([q[0] - rr, q[1] - rr, q[0] + rr, q[1] + rr], fill=color)

    def render(self, color, line=LINE):
        big = SIZE * SS
        scale = big / 100
        rgb = Image.new("RGB", (1, 1), color).getpixel((0, 0))
        # Dark halo, so the drawing stands out on any map background.
        halo = Image.new("L", (big, big), 0)
        self.draw(ImageDraw.Draw(halo), scale, int((line + 4.5) * scale), 255)
        # The line itself.
        stroke = Image.new("L", (big, big), 0)
        self.draw(ImageDraw.Draw(stroke), scale, int(line * scale), 255)
        halo, stroke = (im.resize((SIZE, SIZE), Image.LANCZOS) for im in (halo, stroke))
        glow = stroke.filter(ImageFilter.GaussianBlur(2.2))
        out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        out.paste((8, 8, 14, 255), mask=halo.point(lambda v: int(v * 0.8)))
        out.alpha_composite(Image.merge("RGBA", (*(Image.new("L", (SIZE, SIZE), c) for c in rgb), glow.point(lambda v: int(v * 0.7)))))
        out.alpha_composite(Image.merge("RGBA", (*(Image.new("L", (SIZE, SIZE), c) for c in rgb), stroke)))
        return out


# --- creeps (spaceships, nose to the right) --------------------------------------------------

def shield(pen, x, r=16):
    """Shield arc in front of the nose: cannot be slowed down."""
    return pen.arc(x - r * 0.55, 50, r, -55, 55)


def creeps():
    c = []
    # Group 1 – small ships
    c.append((GREEN, Pen().mirrored((70, 50), (34, 37), (40, 50)).line((40, 50), (48, 50))))          # Mercury: dart
    c.append((GRAY, Pen().circle(52, 50, 11).line((41, 50), (63, 50))                                # Mako: pod with fins
              .line((44, 42), (34, 34), (30, 40)).line((44, 58), (34, 66), (30, 60))))
    c.append((YELLOW, Pen().mirrored((76, 50), (40, 45), (30, 47), (30, 50))                          # Fast Nova: needle
              .line((46, 46), (40, 36)).line((46, 54), (40, 64)).line((22, 50), (16, 50))))
    c.append((RED, Pen().mirrored((70, 50), (34, 28), (44, 50))                                       # Large Manta: wide wing
              .circle(58, 50, 4)))
    # Group 2
    c.append((GREEN, Pen().mirrored((74, 40), (30, 34), (30, 44), (74, 44))                           # Demeter: twin hull
              .line((50, 44), (50, 56)).line((60, 44), (60, 56)).line((24, 39), (18, 39)).line((24, 61), (18, 61))))
    c.append((WHITE, shield(Pen().mirrored((72, 50), (52, 34), (30, 42), (36, 50)), 82)               # Ray: (slow immune)
              .line((52, 34), (52, 66))))
    c.append((YELLOW, Pen().mirrored((82, 50), (50, 44), (36, 28), (34, 44), (24, 46), (24, 50))      # Speedy Raider
              .line((18, 50), (10, 50))))
    c.append((RED, Pen().mirrored((84, 50), (68, 42), (52, 30), (26, 32), (20, 42), (20, 50))         # Big Toucan: bulky, big prow
              .line((68, 42), (68, 58)).circle(44, 50, 6)))
    # Group 3 – larger ships
    c.append((GREEN, Pen().mirrored((82, 50), (62, 42), (70, 14), (54, 18), (40, 42), (22, 44), (22, 50))  # Vulture: forward wings
              .line((40, 42), (40, 58))))
    c.append((WHITE, shield(Pen().mirrored((80, 50), (62, 40), (36, 38), (28, 22), (24, 38), (12, 44), (12, 50))  # Shark (immune)
              .line((52, 39), (46, 30), (42, 39)), 90)))
    c.append((YELLOW, Pen().mirrored((90, 50), (78, 44), (20, 44), (12, 38), (12, 50))                # Racing Mamba: long and slim
              .line((32, 44), (32, 56)).line((46, 44), (46, 56)).line((60, 44), (60, 56)).line((60, 44), (52, 30))
              .line((60, 56), (52, 70))))
    c.append((RED, Pen().mirrored((84, 50), (74, 30), (30, 30), (16, 40), (16, 50))                   # Huge Titan: armored block
              .poly((40, 38), (64, 38), (64, 62), (40, 62)).line((30, 30), (30, 70)).line((74, 30), (74, 70))))
    # Group 4 – the big ones
    c.append((GREEN, Pen().circle(50, 50, 30).circle(50, 50, 18)                                      # Zeus: ring ship, "+" = regenerates
              .line((50, 42), (50, 58)).line((42, 50), (58, 50)).line((80, 50), (92, 50)).line((20, 50), (10, 42))
              .line((20, 50), (10, 58))))
    c.append((WHITE, shield(Pen().mirrored((80, 50), (58, 40), (46, 8), (38, 14), (42, 38), (22, 34), (12, 42), (12, 50))  # Phoenix (immune)
              .line((48, 8), (52, 30)), 90)))
    c.append((YELLOW, Pen().mirrored((96, 50), (34, 30), (10, 8), (20, 34), (8, 42), (8, 50))          # Express Raptor: sharp delta
              .line((70, 46), (40, 46)).line((70, 54), (40, 54))))
    c.append((RED, Pen().mirrored((94, 50), (80, 26), (46, 12), (16, 22), (6, 40), (6, 50))           # Fat Colossus: mothership
              .circle(52, 50, 12).line((64, 50), (80, 50)).line((30, 20), (30, 80)).line((14, 34), (14, 66))))
    # Small ships are drawn larger than their real proportions, so they stay recognizable.
    for i, (_, pen) in enumerate(c):
        pen.scaled({0: 1.3, 1: 1.1}.get(i // 4, 1.0))
    return c


# --- towers (top view, barrel pointing up) ---------------------------------------------------

def tower(kind):
    pen = Pen()
    if kind == 1:   # Basic: round turret, one barrel
        pen.circle(50, 58, 26).circle(50, 58, 10).poly((45, 48), (45, 12), (55, 12), (55, 48))
    elif kind == 2:  # Slow: emitter dish sending freezing waves
        pen.circle(50, 64, 22).poly((36, 44), (50, 54), (64, 44)).line((50, 54), (50, 64))
        pen.arc(50, 44, 12, 50, 130).arc(50, 44, 22, 55, 125).arc(50, 44, 32, 60, 120)
    elif kind == 3:  # Splash: octagonal mortar with a wide muzzle
        pts = [(50 + 28 * math.cos(math.radians(22.5 + 45 * i)), 60 + 28 * math.sin(math.radians(22.5 + 45 * i))) for i in range(8)]
        pen.poly(*pts).poly((40, 52), (34, 16), (66, 16), (60, 52)).line((34, 22), (66, 22))
    elif kind == 4:  # Rocket: launcher with two missiles
        pen.poly((24, 44), (76, 44), (76, 86), (24, 86)).line((50, 44), (50, 86))
        for x in (37, 63):
            pen.poly((x - 6, 52), (x - 6, 22), (x, 10), (x + 6, 22), (x + 6, 52))
    elif kind == 5:  # Speed: twin rapid-fire barrels
        pen.circle(50, 62, 24).poly((38, 50), (38, 8), (46, 8), (46, 50)).poly((54, 50), (54, 8), (62, 8), (62, 50))
        pen.line((34, 30), (66, 30))
    elif kind == 6:  # Ultimate: big hexagon base, heavy cannon with muzzle brake, side guns
        pts = [(50 + 34 * math.cos(math.radians(30 + 60 * i)), 58 + 34 * math.sin(math.radians(30 + 60 * i))) for i in range(6)]
        pen.poly(*pts).circle(50, 58, 14).poly((44, 46), (44, 14), (56, 14), (56, 46)).poly((38, 14), (62, 14), (62, 6), (38, 6))
        pen.line((26, 48), (26, 26)).line((74, 48), (74, 26))
    # The app turns the tower around the image center, so the base must sit there.
    base_y, size = {1: (58, 1.0), 2: (64, 0.82), 3: (60, 0.95), 4: (65, 0.8), 5: (62, 0.85), 6: (58, 0.88)}[kind]
    return pen.moved(50 - base_y).scaled(size)


LEVEL_COLORS = [GREEN, YELLOW, RED, WHITE]
TOWER_LEVELS = {1: 4, 2: 4, 3: 4, 4: 4, 5: 4, 6: 2}


def tower_name(kind, level):
    return f"tower{kind}" if level == 1 else f"tower{kind}{level - 1}"


# --- files -----------------------------------------------------------------------------------

def gray(image, brightest=120):
    """Grayed-out button: same drawing without color, darker."""
    r, g, b, a = image.split()
    v = Image.merge("RGB", (r, g, b)).convert("L").point(lambda x: int(x / 255 * brightest))
    return Image.merge("RGBA", (v, v, v, a))


def cut(image, margin=4):
    left, top, right, bottom = image.getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox()
    return image.crop((max(0, left - margin), max(0, top - margin), min(SIZE, right + margin), min(SIZE, bottom + margin)))


def save(image, group, name):
    folder = f"{ASSETS}/{group}/{name}.imageset"
    os.makedirs(folder, exist_ok=True)
    image.save(f"{folder}/{name}.png")
    contents = f"{folder}/Contents.json"
    if not os.path.exists(contents):
        with open(contents, "w") as f:
            f.write('{\n  "images" : [\n    {\n      "filename" : "%s.png",\n      "idiom" : "universal"\n'
                    '    }\n  ],\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n' % name)


def main():
    creep_images = []
    for n, (color, pen) in enumerate(creeps(), 1):
        image = pen.render(color)
        creep_images.append(image)
        save(image, "Creeps", f"creep{n}")
        icon = cut(image)
        save(icon, "Buttons", f"creepIcon{n}")
        save(gray(icon), "Buttons", f"creepIcon{n}disable")

    tower_images = {}
    for kind, levels in TOWER_LEVELS.items():
        for level in range(1, levels + 1):
            image = tower(kind).render(LEVEL_COLORS[level - 1])
            tower_images[(kind, level)] = image
            save(image, "Towers", tower_name(kind, level))
        save(tower_images[(kind, 1)], "Buttons", f"towerButton{kind}")
        save(gray(tower_images[(kind, 1)]), "Buttons", f"towerButton{kind}disable")

    if "--preview" in sys.argv:
        preview(sys.argv[sys.argv.index("--preview") + 1], creep_images, tower_images)
    print(f"✓ {len(creep_images)} creeps, {len(tower_images)} tower images, buttons")


def preview(path, creep_images, tower_images):
    """Overview: creeps large (4 groups of 4) and at board size, towers by level."""
    cell, pad = 136, 16
    sheet = Image.new("RGBA", (8 * cell + 2 * pad, 2 * cell + 4 * cell + 60 + 2 * pad), "#141026")
    for i, image in enumerate(creep_images):
        sheet.alpha_composite(image, (pad + (i % 8) * cell, pad + (i // 8) * cell))
    top = pad + 2 * cell + 20
    for i, image in enumerate(creep_images):  # roughly board size
        small = image.resize((36, 36), Image.LANCZOS)
        sheet.alpha_composite(small, (pad + i * 44, top))
    top += 60
    for (kind, level), image in tower_images.items():
        sheet.alpha_composite(image, (pad + (kind - 1) * cell, top + (level - 1) * cell))
    sheet.save(path)


if __name__ == "__main__":
    main()
