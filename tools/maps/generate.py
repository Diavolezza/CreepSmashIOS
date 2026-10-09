#!/usr/bin/env python3
"""Generates the own maps of CreepSmash iOS: path (.map in the original's format) and background image.

Usage:  python3 tools/maps/generate.py [map ids]   (writes to tools/maps/out/; no ids = all maps)

Each map is described by the corner points of its path; the cells in between are filled in.
Besides plain corners (x, y) a path can contain the special sections of the original's maps:
  F(x, y, k)  fast lane: straight on to (x, y) with one path point every k cells – creeps are k times as fast there
  J(x, y)     jump: the creeps fly straight to (x, y) in the time of one cell (drawn as two portals)
  (x, y) diagonal from the last point (|dx| = |dy|): one path point per diagonal step
A map with crossings=True may cross or retrace its own path (laps, crossings, dead ends the creeps come back from).
"""
import math, os, random
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

CELLS, PX = 16, 60          # 16 × 16 cells, 60 px per cell -> 960 × 960 image
SIZE = CELLS * PX
OUT = os.path.join(os.path.dirname(__file__), 'out')

def F(x, y, k=2):
    """Fast lane to (x, y): a path point only every k cells."""
    return ('fast', x, y, k)

def J(x, y):
    """Jump to (x, y)."""
    return ('jump', x, y)

def sign(v):
    return (v > 0) - (v < 0)

class Track(list):
    """The path points in walking order (what the .map file lists), plus the sections for drawing.

    segs: (from, to, kind) per path segment, kind = 'walk', 'diag', 'fast' or 'jump'.
    """
    def __init__(self, points, segs):
        super().__init__(points)
        self.segs = segs

    @property
    def strokes(self):
        """Polylines to draw as track: the path split at the jumps."""
        out = [[self[0]]]
        for a, b, kind in self.segs:
            if kind == 'jump':
                out.append([b])
            else:
                out[-1].append(b)
        return [s for s in out if len(s) > 1 or len(out) == 1]

    @property
    def cells(self):
        """All cells the path occupies, including the ones a fast lane skips (as in GameMap.pathCells)."""
        cells = set(self)
        for a, b, kind in self.segs:
            if kind == 'fast':
                dx, dy = sign(b[0] - a[0]), sign(b[1] - a[1])
                c = a
                while c != b:
                    c = (c[0] + dx, c[1] + dy)
                    cells.add(c)
        return cells

def expand(spec, crossings=False):
    points, segs = [tuple(spec[0])], []
    for item in spec[1:]:
        x0, y0 = points[-1]
        if item[0] == 'jump':
            b = (item[1], item[2])
            segs.append(((x0, y0), b, 'jump'))
            points.append(b)
            continue
        if item[0] == 'fast':
            (x1, y1), k = item[1:3], item[3]
        else:
            (x1, y1), k = item, 1
        dx, dy = sign(x1 - x0), sign(y1 - y0)
        n = max(abs(x1 - x0), abs(y1 - y0))
        assert x0 == x1 or y0 == y1 or (abs(x1 - x0) == abs(y1 - y0) and k == 1), \
            f'Corner points not in a line: {(x0, y0)} -> {(x1, y1)}'
        assert n % k == 0, f'Fast lane {(x0, y0)} -> {(x1, y1)} is not a multiple of {k} cells'
        kind = 'fast' if k > 1 else ('diag' if dx and dy else 'walk')
        for i in range(k, n + 1, k):
            p = (x0 + dx * i, y0 + dy * i)
            segs.append((points[-1], p, kind))
            points.append(p)
    track = Track(points, segs)
    if not crossings:
        assert len(points) == len(set(points)), 'Path crosses itself'
    assert all(0 <= x < CELLS and 0 <= y < CELLS for x, y in track.cells)
    return track

def center(c):
    return (c[0] * PX + PX // 2, c[1] * PX + PX // 2)

def noise(seed, scale, octaves=4):
    rng = np.random.default_rng(seed)
    acc = np.zeros((SIZE, SIZE))
    amp, total = 1.0, 0.0
    for o in range(octaves):
        n = max(2, int(SIZE / scale * 2 ** o))
        small = rng.random((n, n))
        img = Image.fromarray((small * 255).astype('uint8')).resize((SIZE, SIZE), Image.BICUBIC)
        acc += np.asarray(img, float) / 255 * amp
        total += amp
        amp *= 0.5
    return acc / total

def gradient(top, bottom):
    t = np.linspace(0, 1, SIZE)[:, None, None]
    g = np.array(top)[None, None, :] * (1 - t) + np.array(bottom)[None, None, :] * t
    return np.repeat(g, SIZE, axis=1)

def to_img(arr):
    return Image.fromarray(np.clip(arr, 0, 255).astype('uint8'), 'RGB')

def edge_extension(cell, neighbour):
    """If the path start/end lies on the border, the track is extended beyond the image edge."""
    x, y = center(cell)
    dx, dy = cell[0] - neighbour[0], cell[1] - neighbour[1]
    on_edge = cell[0] in (0, CELLS - 1) or cell[1] in (0, CELLS - 1)
    return (x + dx * PX, y + dy * PX) if on_edge else None

def path_mask(cells, width_factor=0.86, round_joints=True):
    m = Image.new('L', (SIZE, SIZE), 0)
    d = ImageDraw.Draw(m)
    w = int(PX * width_factor)
    strokes = cells.strokes if isinstance(cells, Track) else [cells]
    for i, stroke in enumerate(strokes):
        pts = [center(c) for c in stroke]
        if i == 0 and edge_extension(stroke[0], stroke[1]):
            pts.insert(0, edge_extension(stroke[0], stroke[1]))
        if i == len(strokes) - 1 and edge_extension(stroke[-1], stroke[-2]):
            pts.append(edge_extension(stroke[-1], stroke[-2]))
        d.line(pts, fill=255, width=w, joint='curve')
        if round_joints:
            for p in pts[1:-1] if len(strokes) == 1 else pts:
                d.ellipse((p[0] - w // 2, p[1] - w // 2, p[0] + w // 2, p[1] + w // 2), fill=255)
    return m

def glow(mask, color, radius, strength=1.0):
    blurred = mask.filter(ImageFilter.GaussianBlur(radius))
    a = np.asarray(blurred, float)[..., None] / 255 * strength
    return a * np.array(color)[None, None, :]

def edge(mask, thickness):
    grown = mask.filter(ImageFilter.MaxFilter(thickness * 2 + 1))
    return Image.fromarray(np.clip(np.asarray(grown, int) - np.asarray(mask, int), 0, 255).astype('uint8'))

def blend(base, color, mask, alpha=1.0):
    a = np.asarray(mask, float)[..., None] / 255 * alpha
    return base * (1 - a) + np.array(color)[None, None, :] * a

def portal(img_arr, cell, color, rings=3):
    img = to_img(img_arr)
    over = Image.new('L', (SIZE, SIZE), 0)
    d = ImageDraw.Draw(over)
    cx, cy = center(cell)
    for i in range(rings):
        r = PX * (0.25 + 0.12 * i)
        d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=255, width=4)
    arr = np.asarray(img, float)
    arr = arr + glow(over, color, 6, 1.5) + blend(np.zeros_like(arr), color, over)
    return arr

# ---------------------------------------------------------------- Marks for fast lanes and jumps

FAST_COLOR = (255, 205, 40)     # chevrons: one per multiple of the speed (>> = twice as fast)
JUMP_COLOR = (235, 90, 255)     # portals and the dotted flight line

def decorate(arr, track):
    if not isinstance(track, Track):
        return arr
    marks = Image.new('L', (SIZE, SIZE), 0)
    d = ImageDraw.Draw(marks)
    for a, b, kind in track.segs:
        if kind != 'fast':
            continue
        k = max(abs(b[0] - a[0]), abs(b[1] - a[1]))
        ux, uy = sign(b[0] - a[0]), sign(b[1] - a[1])
        (ax, ay), (bx, by) = center(a), center(b)
        mx, my = (ax + bx) / 2, (ay + by) / 2
        s = PX * 0.16
        for j in range(k):
            off = (j - (k - 1) / 2) * PX * 0.3
            cx, cy = mx + ux * off, my + uy * off
            tip = (cx + ux * s, cy + uy * s)
            back = (cx - ux * s, cy - uy * s)
            d.line([(back[0] - uy * s * 1.3, back[1] + ux * s * 1.3), tip,
                    (back[0] + uy * s * 1.3, back[1] - ux * s * 1.3)], fill=255, width=6, joint='curve')
    arr = arr + glow(marks, FAST_COLOR, 6, 0.9)
    arr = blend(arr, FAST_COLOR, marks)
    dots = Image.new('L', (SIZE, SIZE), 0)
    dd = ImageDraw.Draw(dots)
    for a, b, kind in track.segs:
        if kind != 'jump':
            continue
        (ax, ay), (bx, by) = center(a), center(b)
        n = int(math.hypot(bx - ax, by - ay) / (PX * 0.45))
        for i in range(2, n - 1):
            x, y = ax + (bx - ax) * i / n, ay + (by - ay) * i / n
            dd.ellipse((x - 4, y - 4, x + 4, y + 4), fill=255)
        arr = portal(arr, a, JUMP_COLOR, 3)
        arr = portal(arr, b, JUMP_COLOR, 3)
    arr = arr + glow(dots, JUMP_COLOR, 5, 0.8)
    arr = blend(arr, JUMP_COLOR, dots, 0.75)
    return arr

# ---------------------------------------------------------------- Themes

def neon(cells, blocked, seed):
    base = gradient((20, 0, 38), (52, 0, 70))
    grid = Image.new('L', (SIZE, SIZE), 0)
    d = ImageDraw.Draw(grid)
    for i in range(CELLS + 1):
        d.line((i * PX, 0, i * PX, SIZE), fill=255, width=2)
        d.line((0, i * PX, SIZE, i * PX), fill=255, width=2)
    base = blend(base, (255, 60, 200), grid, 0.18)
    sun = Image.new('L', (SIZE, SIZE), 0)
    ImageDraw.Draw(sun).ellipse((SIZE * 0.55, SIZE * 0.08, SIZE * 0.95, SIZE * 0.48), fill=255)
    base = base + glow(sun, (255, 120, 40), 60, 0.35)
    m = path_mask(cells)
    base = blend(base, (10, 0, 22), m)
    e = edge(m, 4)
    base = base + glow(e, (255, 40, 220), 10, 1.4)
    base = blend(base, (255, 120, 240), e)
    return base

def spiral(cells, blocked, seed):
    rng = random.Random(seed)
    base = np.zeros((SIZE, SIZE, 3)) + np.array((4, 6, 18))
    n1, n2 = noise(seed, 400), noise(seed + 1, 300)
    base += (n1[..., None] ** 3) * np.array((120, 40, 160)) + (n2[..., None] ** 3) * np.array((20, 120, 140))
    stars = Image.new('L', (SIZE, SIZE), 0)
    d = ImageDraw.Draw(stars)
    for _ in range(700):
        x, y, r = rng.randrange(SIZE), rng.randrange(SIZE), rng.choice((1, 1, 1, 2, 3))
        d.ellipse((x - r, y - r, x + r, y + r), fill=rng.randrange(120, 255))
    base = base + np.asarray(stars, float)[..., None] * np.array((1, 1, 1)) * 0.9
    m = path_mask(cells, 0.8)
    base = blend(base, (6, 8, 20), m, 0.85)
    e = edge(m, 3)
    base = base + glow(e, (90, 220, 255), 8, 1.0)
    base = blend(base, (150, 235, 255), e, 0.9)
    base = portal(base, cells[-1], (200, 120, 255), 4)
    return base

def canyon(cells, blocked, seed):
    n, fine = noise(seed, 240), noise(seed + 7, 40, 3)
    base = gradient((222, 158, 88), (186, 110, 54)) * (0.82 + 0.25 * n[..., None] + 0.12 * fine[..., None])
    strata = (np.sin(np.linspace(0, 55, SIZE) + 3 * n[:, :1].ravel())[:, None] * 0.5 + 0.5) * 22
    base = base - strata[..., None]
    m = path_mask(cells, 0.9)
    # Shadow along the edge, with the dark riverbed inside
    shadow = m.filter(ImageFilter.MaxFilter(13)).filter(ImageFilter.GaussianBlur(6))
    base = blend(base, (90, 50, 24), shadow, 0.55)
    soft = m.filter(ImageFilter.GaussianBlur(2))
    bed = np.array((58, 36, 20)) * (0.8 + 0.4 * noise(seed + 3, 90)[..., None])
    a = np.asarray(soft, float)[..., None] / 255
    base = base * (1 - a) + bed * a
    rim = edge(m, 2)
    base = blend(base, (245, 205, 150), rim, 0.55)
    rocks = Image.new('L', (SIZE, SIZE), 0)
    shade = Image.new('L', (SIZE, SIZE), 0)
    d, ds = ImageDraw.Draw(rocks), ImageDraw.Draw(shade)
    rng = random.Random(seed)
    for (x, y) in blocked:
        cx, cy = center((x, y))
        pts = [(cx + math.cos(t) * PX * rng.uniform(0.36, 0.48), cy + math.sin(t) * PX * rng.uniform(0.36, 0.48))
               for t in np.linspace(0, math.tau, 9)[:-1]]
        d.polygon(pts, fill=255)
        ds.polygon([(px - (px - cx) * 0.45 - 6, py - (py - cy) * 0.45 - 8) for px, py in pts], fill=255)
    base = base + glow(rocks, (-70, -70, -70), 9, 1.0)
    base = blend(base, (112, 88, 72), rocks)
    base = blend(base, (170, 145, 120), shade, 0.7)
    return base

def circuit(cells, blocked, seed):
    rng = random.Random(seed)
    n = noise(seed, 300)
    base = np.zeros((SIZE, SIZE, 3)) + np.array((10, 58, 30)) * (0.85 + 0.3 * n[..., None])
    traces = Image.new('L', (SIZE, SIZE), 0)
    d = ImageDraw.Draw(traces)
    for _ in range(90):
        x, y = rng.randrange(CELLS) * PX + PX // 2, rng.randrange(CELLS) * PX + PX // 2
        for _ in range(rng.randrange(2, 5)):
            if rng.random() < 0.5:
                nx, ny = x + rng.choice((-1, 1)) * rng.randrange(1, 4) * PX // 2, y
            else:
                nx, ny = x, y + rng.choice((-1, 1)) * rng.randrange(1, 4) * PX // 2
            d.line((x, y, nx, ny), fill=255, width=4)
            x, y = nx, ny
        d.ellipse((x - 7, y - 7, x + 7, y + 7), outline=255, width=3)
    base = blend(base, (60, 160, 90), traces, 0.45)
    m = path_mask(cells, 0.84, round_joints=False)
    e = edge(m, 5)
    base = blend(base, (16, 12, 6), m)
    base = blend(base, (205, 135, 60), e)
    chips = Image.new('L', (SIZE, SIZE), 0)
    pins = Image.new('L', (SIZE, SIZE), 0)
    dc, dp = ImageDraw.Draw(chips), ImageDraw.Draw(pins)
    for (x, y) in blocked:
        dc.rectangle((x * PX + 6, y * PX + 6, x * PX + PX - 6, y * PX + PX - 6), fill=255)
        for k in range(3):
            px = x * PX + 15 + k * 15
            dp.rectangle((px - 3, y * PX, px + 3, y * PX + 6), fill=255)
            dp.rectangle((px - 3, y * PX + PX - 6, px + 3, y * PX + PX), fill=255)
    base = blend(base, (20, 20, 22), chips)
    base = blend(base, (200, 200, 200), pins)
    return base

def volcano(cells, blocked, seed):
    n = noise(seed, 200)
    base = np.zeros((SIZE, SIZE, 3)) + np.array((34, 26, 26)) * (0.7 + 0.6 * n[..., None])
    cracks = Image.new('L', (SIZE, SIZE), 0)
    d = ImageDraw.Draw(cracks)
    rng = random.Random(seed)
    for _ in range(40):
        x, y = rng.randrange(SIZE), rng.randrange(SIZE)
        a = rng.uniform(0, math.tau)
        for _ in range(rng.randrange(4, 9)):
            a += rng.uniform(-0.8, 0.8)
            nx, ny = x + math.cos(a) * rng.uniform(20, 50), y + math.sin(a) * rng.uniform(20, 50)
            d.line((x, y, nx, ny), fill=255, width=rng.choice((2, 3, 4)))
            x, y = nx, ny
    pools = Image.new('L', (SIZE, SIZE), 0)
    dp = ImageDraw.Draw(pools)
    for (x, y) in blocked:
        cx, cy = center((x, y))
        r = PX * 0.45
        dp.ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)
    pools = pools.filter(ImageFilter.GaussianBlur(4))
    m = path_mask(cells, 0.86)
    cracks = Image.fromarray((np.asarray(cracks, int) * (1 - np.asarray(m, int) / 255)).astype('uint8'))
    base = base + glow(cracks, (255, 90, 0), 6, 1.2)
    base = blend(base, (255, 140, 30), cracks, 0.9)
    base = base + glow(pools, (255, 80, 0), 14, 1.4)
    base = blend(base, (255, 170, 40), pools, 0.95)
    base = blend(base, (14, 10, 12), m)
    e = edge(m, 3)
    base = base + glow(e, (255, 70, 0), 8, 1.1)
    base = blend(base, (255, 120, 20), e, 0.85)
    return base

def ocean(cells, blocked, seed):
    n1, n2 = noise(seed, 350), noise(seed + 1, 160, 2)
    base = gradient((8, 46, 100), (2, 14, 44)) * (0.75 + 0.35 * n1[..., None])
    # faint light network (caustics) as on a seabed
    caustic = np.abs(np.sin(n2 * 22)) ** 30
    base = base + caustic[..., None] * np.array((20, 60, 90))
    bubbles = Image.new('L', (SIZE, SIZE), 0)
    d = ImageDraw.Draw(bubbles)
    rng = random.Random(seed)
    for _ in range(120):
        x, y, r = rng.randrange(SIZE), rng.randrange(SIZE), rng.choice((3, 4, 6, 8))
        d.ellipse((x - r, y - r, x + r, y + r), outline=255, width=2)
    base = blend(base, (150, 220, 255), bubbles, 0.35)
    m = path_mask(cells, 0.86)
    base = blend(base, (2, 8, 22), m)
    e = edge(m, 3)
    base = base + glow(e, (0, 200, 255), 9, 1.2)
    base = blend(base, (120, 230, 255), e, 0.9)
    reef = Image.new('L', (SIZE, SIZE), 0)
    dr = ImageDraw.Draw(reef)
    for (x, y) in blocked:
        cx, cy = center((x, y))
        for _ in range(7):   # coral colony made of small spheres
            ox, oy, r = rng.uniform(-0.3, 0.3) * PX, rng.uniform(-0.3, 0.3) * PX, rng.uniform(0.1, 0.18) * PX
            dr.ellipse((cx + ox - r, cy + oy - r, cx + ox + r, cy + oy + r), fill=255)
    base = base + glow(reef, (255, 60, 140), 6, 0.8)
    base = blend(base, (255, 110, 170), reef)
    return base

# ---------------------------------------------------------------- Themes of the maps with special sections

def stars(seed, count=600, brightness=0.9):
    rng = random.Random(seed)
    m = Image.new('L', (SIZE, SIZE), 0)
    d = ImageDraw.Draw(m)
    for _ in range(count):
        x, y, r = rng.randrange(SIZE), rng.randrange(SIZE), rng.choice((1, 1, 1, 2, 2, 3))
        d.ellipse((x - r, y - r, x + r, y + r), fill=rng.randrange(110, 255))
    return np.asarray(m, float)[..., None] * brightness

def lane(base, cells, fill, rim, width=0.86, rim_px=3, glow_radius=9, glow_strength=1.1):
    """Dark track with a glowing rim (the common look of the space and neon maps)."""
    m = path_mask(cells, width)
    base = blend(base, fill, m)
    e = edge(m, rim_px)
    base = base + glow(e, rim, glow_radius, glow_strength)
    return blend(base, tuple(min(255, c + 60) for c in rim), e, 0.9), m

def raceway(cells, blocked, seed):
    n = noise(seed, 220)
    mow = ((np.arange(SIZE)[None, :] // (PX * 2)) % 2) * 0.1        # mowing stripes in the grass
    base = np.zeros((SIZE, SIZE, 3)) + np.array((30, 104, 40)) * (0.82 + 0.25 * n[..., None] + mow[..., None])
    m = path_mask(cells, 0.9)
    asphalt = np.array((62, 62, 68)) * (0.8 + 0.35 * noise(seed + 2, 24, 2)[..., None])
    a = np.asarray(m, float)[..., None] / 255
    base = base * (1 - a) + asphalt * a
    kerb = np.asarray(edge(m, 7), float)[..., None] / 255
    xx, yy = np.meshgrid(np.arange(SIZE), np.arange(SIZE))
    red = (((xx + yy) // 22) % 2 == 0)[..., None]
    base = base * (1 - kerb) + np.where(red, np.array((225, 35, 35)), np.array((245, 245, 245))) * kerb
    # chequered start/finish line across the track at the first lap point
    cx, cy = center(cells[1])
    sq = 10
    flag = Image.new('L', (SIZE, SIZE), 0)
    d = ImageDraw.Draw(flag)
    for i in range(-3, 3):
        for j in range(-1, 1):
            if (i + j) % 2 == 0:
                d.rectangle((cx + j * sq, cy + i * sq, cx + j * sq + sq - 1, cy + i * sq + sq - 1), fill=255)
    lines = Image.new('L', (SIZE, SIZE), 0)
    ImageDraw.Draw(lines).rectangle((cx - sq, cy - 3 * sq, cx + sq - 1, cy + 3 * sq - 1), fill=255)
    base = blend(base, (20, 20, 20), lines)
    base = blend(base, (250, 250, 250), flag)
    # grandstand on the blocked cells: a roof with rows of spectators
    stand = Image.new('L', (SIZE, SIZE), 0)
    crowd = np.zeros((SIZE, SIZE, 3))
    crowd_mask = Image.new('L', (SIZE, SIZE), 0)
    ds, dc = ImageDraw.Draw(stand), ImageDraw.Draw(crowd_mask)
    rng = random.Random(seed)
    colors = [(255, 80, 80), (80, 160, 255), (255, 220, 60), (240, 240, 240), (120, 230, 120)]
    for (x, y) in blocked:
        ds.rectangle((x * PX + 2, y * PX + 2, x * PX + PX - 3, y * PX + PX - 3), fill=255)
        for row in range(4):
            for col in range(6):
                px, py = x * PX + 8 + col * 9, y * PX + 9 + row * 12
                dc.ellipse((px - 3, py - 3, px + 3, py + 3), fill=255)
                crowd[py - 3:py + 4, px - 3:px + 4] = rng.choice(colors)
    base = base + glow(stand, (-60, -60, -60), 8, 1.0)
    base = blend(base, (70, 72, 84), stand)
    cm = np.asarray(crowd_mask, float)[..., None] / 255
    return base * (1 - cm) + crowd * cm

def wormhole(cells, blocked, seed):
    base = np.zeros((SIZE, SIZE, 3)) + np.array((5, 4, 14))
    n1, n2 = noise(seed, 380), noise(seed + 1, 260)
    base += (n1[..., None] ** 3) * np.array((170, 70, 30)) + (n2[..., None] ** 3) * np.array((30, 50, 170))
    base = base + stars(seed) * np.array((1, 1, 1))
    base, _ = lane(base, cells, (6, 6, 18), (60, 255, 190), 0.82)
    return base

def aurora(cells, blocked, seed):
    base = gradient((4, 10, 30), (12, 34, 52))
    xs = np.arange(SIZE)
    ny = noise(seed, 300)[0]
    yc = SIZE * 0.3 + 70 * np.sin(xs / 140 + 1.3) + 60 * (ny - 0.5)
    streaks = 0.55 + 0.45 * np.sin(xs / 9 + 6 * ny) * np.sin(xs / 23)
    y = np.arange(SIZE)[:, None]
    below = np.exp(-np.clip(y - yc[None, :], 0, None) / 40) * (y >= yc[None, :] - 0)
    above = np.exp(-np.clip(yc[None, :] - y, 0, None) / 160) * (y < yc[None, :])
    curtain = (below + above) * streaks[None, :]
    mix = np.clip((yc[None, :] - y) / 220 + 0.5, 0, 1)[..., None]   # green below, violet above
    color = np.array((50, 255, 140)) * (1 - mix) + np.array((170, 80, 255)) * mix
    base = base + curtain[..., None] * color * 0.55
    base = base + stars(seed, 300, 0.5) * (y < SIZE * 0.6)[..., None]
    snow = (noise(seed + 4, 30, 2) > 0.62)[..., None] * (y > SIZE * 0.45)[..., None]
    base = base + snow * np.array((14, 22, 30))
    base, _ = lane(base, cells, (12, 30, 50), (150, 230, 255), 0.84)
    crystals = Image.new('L', (SIZE, SIZE), 0)
    d = ImageDraw.Draw(crystals)
    for (x, y0) in blocked:
        cx, cy = center((x, y0))
        for k in range(3):
            a = k * math.pi / 3
            dx, dy = math.cos(a) * PX * 0.38, math.sin(a) * PX * 0.38
            d.line((cx - dx, cy - dy, cx + dx, cy + dy), fill=255, width=5)
            for s in (-1, 1):   # little side branches
                bx, by = cx + s * dx * 0.55, cy + s * dy * 0.55
                for t in (-1, 1):
                    b = a + t * math.pi / 4
                    d.line((bx, by, bx + s * math.cos(b) * PX * 0.14, by + s * math.sin(b) * PX * 0.14), fill=255, width=3)
    base = base + glow(crystals, (120, 210, 255), 7, 1.2)
    return blend(base, (230, 250, 255), crystals)

def crossroads(cells, blocked, seed):
    rng = random.Random(seed)
    base = np.zeros((SIZE, SIZE, 3)) + np.array((12, 12, 18))
    roofs = np.zeros((SIZE, SIZE, 3))
    roof_mask = Image.new('L', (SIZE, SIZE), 0)
    lit = Image.new('L', (SIZE, SIZE), 0)
    dr, dl = ImageDraw.Draw(roof_mask), ImageDraw.Draw(lit)
    for y in range(CELLS):
        for x in range(CELLS):
            g = rng.randrange(34, 62)
            m = rng.randrange(4, 9)
            box = (x * PX + m, y * PX + m, x * PX + PX - m, y * PX + PX - m)
            dr.rectangle(box, fill=255)
            roofs[box[1]:box[3] + 1, box[0]:box[2] + 1] = (g, g, g + 8)
            for wy in range(box[1] + 6, box[3] - 6, 10):
                for wx in range(box[0] + 6, box[2] - 6, 10):
                    if rng.random() < 0.2:
                        dl.rectangle((wx, wy, wx + 4, wy + 4), fill=255)
    rm = np.asarray(roof_mask, float)[..., None] / 255
    base = base * (1 - rm) + roofs * rm
    base = base + glow(lit, (255, 190, 90), 4, 0.5)
    base = blend(base, (230, 195, 120), lit, 0.8)
    m = path_mask(cells, 0.88, round_joints=False)
    base = blend(base, (36, 36, 42), m)
    walk = edge(m, 5)
    base = blend(base, (120, 120, 130), walk)
    dashes = Image.new('L', (SIZE, SIZE), 0)
    dd = ImageDraw.Draw(dashes)
    for a, b in zip(cells, cells[1:]):
        (ax, ay), (bx, by) = center(a), center(b)
        for t in (0.0, 0.5):
            x0, y0 = ax + (bx - ax) * t, ay + (by - ay) * t
            x1, y1 = ax + (bx - ax) * (t + 0.28), ay + (by - ay) * (t + 0.28)
            dd.line((x0, y0, x1, y1), fill=255, width=4)
    return blend(base, (250, 205, 60), dashes, 0.9)

def maelstrom(cells, blocked, seed):
    yy, xx = np.mgrid[0:SIZE, 0:SIZE]
    cx = cy = SIZE / 2
    r = np.hypot(xx - cx, yy - cy) + 1
    theta = np.arctan2(yy - cy, xx - cx)
    n = noise(seed, 200)
    v = 0.5 + 0.5 * np.sin(4 * theta + r / 30 + 4 * n)
    deep, light = np.array((4, 26, 56)), np.array((16, 104, 138))
    base = deep * (1 - v[..., None]) + light * v[..., None]
    base = base * (0.6 + 0.4 * np.clip(r / (SIZE * 0.5), 0, 1))[..., None]   # darker towards the eye
    foam = np.clip((v - 0.93) * 14, 0, 1)[..., None] * np.clip(r / 200 - 0.3, 0, 1)[..., None]
    base = base + foam * np.array((70, 110, 120))
    base, _ = lane(base, cells, (2, 12, 26), (60, 220, 255), 0.84)
    return base

def pendulum(cells, blocked, seed):
    rng = random.Random(seed)
    n = noise(seed, 160)
    base = np.zeros((SIZE, SIZE, 3)) + np.array((40, 44, 52)) * (0.8 + 0.35 * n[..., None])
    seams = Image.new('L', (SIZE, SIZE), 0)
    rivets = Image.new('L', (SIZE, SIZE), 0)
    ds, dv = ImageDraw.Draw(seams), ImageDraw.Draw(rivets)
    for i in range(0, CELLS + 1, 4):
        ds.line((i * PX, 0, i * PX, SIZE), fill=255, width=3)
        ds.line((0, i * PX, SIZE, i * PX), fill=255, width=3)
        for j in range(0, CELLS + 1, 4):
            for ox, oy in ((10, 10), (-10, 10), (10, -10), (-10, -10)):
                x, y = i * PX + ox, j * PX + oy
                dv.ellipse((x - 3, y - 3, x + 3, y + 3), fill=255)
    base = blend(base, (18, 20, 24), seams)
    base = blend(base, (110, 116, 126), rivets)
    bolts = Image.new('L', (SIZE, SIZE), 0)
    db = ImageDraw.Draw(bolts)
    for _ in range(8):
        x, y = rng.randrange(SIZE), rng.randrange(SIZE)
        a = rng.uniform(0, math.tau)
        pts = [(x, y)]
        for _ in range(rng.randrange(5, 9)):
            a += rng.uniform(-0.9, 0.9)
            x, y = x + math.cos(a) * rng.uniform(14, 30), y + math.sin(a) * rng.uniform(14, 30)
            pts.append((x, y))
        db.line(pts, fill=255, width=2)
    base = base + glow(bolts, (90, 140, 255), 5, 0.7)
    base = blend(base, (190, 215, 255), bolts, 0.6)
    base, _ = lane(base, cells, (8, 10, 20), (80, 160, 255), 0.84, 3, 11, 1.4)
    # Tesla coils on the blocked cells: base plate, copper winding, glowing ball on top
    plates = Image.new('L', (SIZE, SIZE), 0)
    coils = Image.new('L', (SIZE, SIZE), 0)
    core = Image.new('L', (SIZE, SIZE), 0)
    dp, dc, dk = ImageDraw.Draw(plates), ImageDraw.Draw(coils), ImageDraw.Draw(core)
    for (x, y) in blocked:
        cx, cy = center((x, y))
        dp.rectangle((x * PX + 4, y * PX + 4, x * PX + PX - 5, y * PX + PX - 5), fill=255)
        for k in range(5):
            yy = cy - 6 + k * 6
            dc.line((cx - 11, yy, cx + 11, yy), fill=255, width=3)
        dk.ellipse((cx - 8, cy - 22, cx + 8, cy - 6), fill=255)
    base = blend(base, (24, 26, 32), plates)
    base = blend(base, (140, 146, 156), edge(plates, 2))
    base = blend(base, (205, 120, 55), coils)
    base = base + glow(core, (120, 180, 255), 10, 1.6)
    return blend(base, (230, 240, 255), core)

def asteroids(cells, blocked, seed):
    base = np.zeros((SIZE, SIZE, 3)) + np.array((7, 7, 13))
    n1, n2 = noise(seed, 330), noise(seed + 1, 180)
    base += (n1[..., None] ** 3) * np.array((170, 60, 25)) + (n2[..., None] ** 4) * np.array((90, 30, 90))
    base = base + stars(seed, 500) * np.array((1, 1, 1))
    base, _ = lane(base, cells, (10, 8, 14), (255, 140, 50), 0.74)
    rng = random.Random(seed)
    rocks = Image.new('L', (SIZE, SIZE), 0)
    craters = Image.new('L', (SIZE, SIZE), 0)
    dr, dc = ImageDraw.Draw(rocks), ImageDraw.Draw(craters)
    for (x, y) in blocked:
        cx, cy = center((x, y))
        pts = [(cx + math.cos(t) * PX * rng.uniform(0.34, 0.47), cy + math.sin(t) * PX * rng.uniform(0.34, 0.47))
               for t in np.linspace(0, math.tau, 10)[:-1]]
        dr.polygon(pts, fill=255)
        for _ in range(3):
            ox, oy, rr = rng.uniform(-0.18, 0.18) * PX, rng.uniform(-0.18, 0.18) * PX, rng.uniform(0.05, 0.1) * PX
            dc.ellipse((cx + ox - rr, cy + oy - rr, cx + ox + rr, cy + oy + rr), outline=255, width=3)
    base = blend(base, (105, 96, 92), rocks)
    base = blend(base, (150, 142, 136), edge(rocks, 2), 0.8)
    return blend(base, (60, 54, 52), craters)

def rapids(cells, blocked, seed):
    rng = random.Random(seed)
    n, fine = noise(seed, 220), noise(seed + 5, 40, 3)
    base = np.zeros((SIZE, SIZE, 3)) + np.array((44, 96, 42)) * (0.75 + 0.3 * n[..., None] + 0.15 * fine[..., None])
    flowers = Image.new('L', (SIZE, SIZE), 0)
    df = ImageDraw.Draw(flowers)
    for _ in range(160):
        x, y = rng.randrange(SIZE), rng.randrange(SIZE)
        df.ellipse((x - 2, y - 2, x + 2, y + 2), fill=255)
    base = blend(base, (235, 225, 150), flowers, 0.7)
    m = path_mask(cells, 0.9)
    bank = m.filter(ImageFilter.MaxFilter(11))
    base = blend(base, (176, 156, 108), bank)
    water = np.array((26, 84, 150)) * (0.8 + 0.4 * noise(seed + 3, 60, 3)[..., None])
    a = np.asarray(m.filter(ImageFilter.GaussianBlur(2)), float)[..., None] / 255
    base = base * (1 - a) + water * a
    # white water on the rapids (the fast lanes)
    fast = Image.new('L', (SIZE, SIZE), 0)
    dfa = ImageDraw.Draw(fast)
    for a_, b_, kind in getattr(cells, 'segs', []):
        if kind == 'fast':
            dfa.line((center(a_), center(b_)), fill=255, width=int(PX * 0.7))
    foam = np.asarray(fast, float)[..., None] / 255 * (noise(seed + 8, 18, 2) > 0.55)[..., None]
    base = base * (1 - foam * 0.6) + np.array((220, 240, 250)) * foam * 0.6
    stones = Image.new('L', (SIZE, SIZE), 0)
    shine = Image.new('L', (SIZE, SIZE), 0)
    ds, dh = ImageDraw.Draw(stones), ImageDraw.Draw(shine)
    for (x, y) in blocked:
        cx, cy = center((x, y))
        r = PX * 0.4
        ds.ellipse((cx - r, cy - r * 0.85, cx + r, cy + r * 0.85), fill=255)
        dh.ellipse((cx - r * 0.5, cy - r * 0.6, cx, cy - r * 0.15), fill=255)
    base = base + glow(stones, (-50, -50, -50), 8, 1.0)
    base = blend(base, (120, 120, 116), stones)
    return blend(base, (175, 175, 170), shine, 0.7)

# ---------------------------------------------------------------- Maps

# One lap of the raceway: fast straights, corners at normal speed.
RACE_LAP = [F(12, 12, 2), (13, 12), (13, 11), F(13, 5, 2), (13, 3), (12, 3), F(4, 3, 2), (2, 3), (2, 4), F(2, 10, 2), (2, 12)]

MAPS = [
    dict(id='blue', name='Blue', theme=ocean, seed=6,
         corners=[(0, 13), (4, 13), (4, 10), (7, 10), (7, 13), (11, 13), (11, 10), (14, 10), (14, 6),
                  (10, 6), (10, 3), (6, 3), (6, 6), (2, 6), (2, 1), (15, 1)],
         blocked=[(1, 9), (9, 11), (13, 13), (12, 4), (4, 4), (8, 8), (15, 4)]),
    dict(id='neon', name='Neon', theme=neon, seed=1,
         corners=[(0, 14), (13, 14), (13, 11), (2, 11), (2, 8), (13, 8), (13, 5), (2, 5), (2, 2), (15, 2)],
         blocked=[]),
    dict(id='spirale', name='Spiral', theme=spiral, seed=2,
         corners=[(0, 13), (13, 13), (13, 2), (2, 2), (2, 10), (10, 10), (10, 5), (5, 5), (5, 7), (7, 7)],
         blocked=[]),
    dict(id='canyon', name='Canyon', theme=canyon, seed=3,
         corners=[(0, 3), (6, 3), (6, 12), (11, 12), (11, 5), (15, 5)],
         blocked=[(2, 6), (3, 6), (2, 7), (9, 8), (9, 9), (13, 9), (14, 9), (13, 10), (3, 13), (4, 14), (8, 1), (13, 1), (14, 2)]),
    dict(id='platine', name='Circuit', theme=circuit, seed=4,
         corners=[(0, 8), (3, 8), (3, 3), (7, 3), (7, 13), (10, 13), (10, 6), (13, 6), (13, 11), (15, 11)],
         blocked=[(1, 1), (1, 2), (5, 6), (5, 7), (5, 10), (11, 2), (12, 2), (11, 9), (15, 14), (14, 14), (1, 13)]),
    dict(id='vulkan', name='Volcano', theme=volcano, seed=5,
         corners=[(1, 15), (1, 1), (4, 1), (4, 14), (7, 14), (7, 1), (10, 1), (10, 14), (13, 14), (13, 1), (15, 1)],
         blocked=[(2, 7), (5, 4), (6, 10), (8, 6), (9, 12), (11, 3), (12, 9), (15, 8), (14, 12)]),
    # --- maps with the special sections of the original (fast lanes, jumps, laps, dead ends, diagonals)
    dict(id='rennbahn', name='Raceway', theme=raceway, seed=11, crossings=True,
         corners=[(0, 12), (2, 12)] + RACE_LAP + RACE_LAP + RACE_LAP[:5] + [(15, 3)],
         blocked=[(6, 7), (7, 7), (8, 7), (9, 7), (6, 8), (7, 8), (8, 8), (9, 8)]),
    dict(id='wurmloch', name='Wormhole', theme=wormhole, seed=12,
         corners=[(0, 2), (5, 2), (5, 6), (1, 6), (1, 10), (6, 10), J(10, 2), (14, 2), (14, 7), (10, 7), (10, 10),
                  J(3, 12), (3, 14), (12, 14), (12, 11), (15, 11)],
         blocked=[]),
    dict(id='polarlicht', name='Aurora', theme=aurora, seed=13, crossings=True,
         corners=[(0, 9), (3, 9), (3, 2), (3, 9), (8, 9), (8, 14), (8, 9), (12, 9), (12, 3), (12, 9), (15, 9)],
         blocked=[(6, 4), (5, 12), (13, 13), (15, 4), (10, 6), (1, 12)]),
    dict(id='kreuzung', name='Crossroads', theme=crossroads, seed=14, crossings=True,
         corners=[(0, 10), (10, 10), (10, 3), (5, 3), (5, 13), (13, 13), (13, 7), (2, 7), (2, 1), (15, 1)],
         blocked=[]),
    dict(id='mahlstrom', name='Maelstrom', theme=maelstrom, seed=15, crossings=True,
         corners=[(0, 1), (14, 1), (14, 14), (1, 14), (1, 4), (11, 4), (11, 11), (4, 11), (4, 7), (8, 7), F(8, 15, 4)],
         blocked=[]),
    dict(id='pendel', name='Pendulum', theme=pendulum, seed=16, crossings=True,
         corners=[(0, 2), (12, 2), (12, 5), (2, 5), (2, 9), (14, 9), F(2, 9, 2), (2, 13), (14, 13), F(2, 13, 3), (2, 15)],
         blocked=[(8, 11), (15, 6), (6, 7)]),
    dict(id='asteroiden', name='Asteroids', theme=asteroids, seed=17,
         corners=[(0, 1), (5, 6), (10, 1), (14, 5), (14, 9), (10, 13), (6, 9), (2, 13), (2, 15)],
         blocked=[(5, 1), (5, 2), (12, 9), (8, 14), (9, 14), (3, 7), (14, 13), (1, 6), (8, 5), (11, 5)]),
    dict(id='stromschnellen', name='Rapids', theme=rapids, seed=18,
         corners=[(3, 0), (3, 3), (8, 3), (8, 1), (13, 1), (13, 4), F(13, 10, 2), (9, 10), (9, 6), (5, 6), F(5, 12, 3),
                  (5, 14), (11, 14), (11, 12), (15, 12)],
         blocked=[(11, 7), (7, 9), (1, 5), (15, 8), (9, 12)]),
]

def write(m):
    cells = expand(m['corners'], m.get('crossings', False))
    if not any(k != 'walk' for _, _, k in cells.segs):
        cells = list(cells)   # plain maps: drawn exactly as before
    blocked = [b for b in m['blocked'] if b not in set(expand(m['corners'], m.get('crossings', False)).cells)]
    img = to_img(decorate(m['theme'](cells, blocked, m['seed']), cells))
    os.makedirs(OUT, exist_ok=True)
    img.save(os.path.join(OUT, f"map_{m['id']}.jpg"), quality=90)
    lines = ['###', f"### {m['name'].upper()} – own map of CreepSmash iOS", '###', '',
             f"map_{m['id']}.jpg", '', 'SET_ALPHA_BACKGROUND_COLOR:OFF', '', '# blocked cells']
    lines += [f'{x};{y}' for x, y in blocked]
    lines += ['', '# path']
    lines += [f'{x},{y}' for x, y in cells]
    open(os.path.join(OUT, f"map_{m['id']}.map"), 'w').write('\n'.join(lines) + '\n')
    print(f"{m['id']:8} path {len(cells):3} cells, blocked {len(blocked)}")

if __name__ == '__main__':
    import sys
    for m in MAPS:
        if len(sys.argv) < 2 or m['id'] in sys.argv[1:]:
            write(m)
