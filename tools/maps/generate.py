#!/usr/bin/env python3
"""Generates the own maps of CreepSmash iOS: path (.map in the original's format) and background image.

Usage:  python3 tools/maps/generate.py   (writes to tools/maps/out/)
Each map is described by the corner points of its path; the cells in between are filled in.
"""
import math, os, random
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

CELLS, PX = 16, 60          # 16 × 16 cells, 60 px per cell -> 960 × 960 image
SIZE = CELLS * PX
OUT = os.path.join(os.path.dirname(__file__), 'out')

def expand(corners):
    cells = [corners[0]]
    for (x0, y0), (x1, y1) in zip(corners, corners[1:]):
        assert x0 == x1 or y0 == y1, f'Corner points not in a line: {(x0, y0)} -> {(x1, y1)}'
        dx, dy = (x1 > x0) - (x1 < x0), (y1 > y0) - (y1 < y0)
        x, y = x0, y0
        while (x, y) != (x1, y1):
            x, y = x + dx, y + dy
            cells.append((x, y))
    assert len(cells) == len(set(cells)), 'Path crosses itself'
    assert all(0 <= x < CELLS and 0 <= y < CELLS for x, y in cells)
    return cells

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
    pts = [center(c) for c in cells]
    start, end = edge_extension(cells[0], cells[1]), edge_extension(cells[-1], cells[-2])
    if start: pts.insert(0, start)
    if end: pts.append(end)
    d.line(pts, fill=255, width=w, joint='curve')
    if round_joints:
        for p in pts[1:-1]:
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

# ---------------------------------------------------------------- Maps

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
]

def write(m):
    cells = expand(m['corners'])
    blocked = [b for b in m['blocked'] if b not in cells]
    img = to_img(m['theme'](cells, blocked, m['seed']))
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
    for m in MAPS:
        write(m)
