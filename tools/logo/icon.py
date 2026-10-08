#!/usr/bin/env python3
"""App icon of CreepSmash iOS in the style of the start screen: stars above a glowing horizon, a green
perspective grid, and the monogram "CS" in the arcade lettering of the logo (C green, S orange)."""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = os.path.dirname(__file__)
PIXEL = os.path.join(HERE, 'PressStart2P-Regular.ttf')
S = 1024
GREEN = (51, 255, 51)
HORIZON = int(S * 0.64)
SIZE = 360          # letter size
DEPTH = 30          # extrusion depth


def glow(mask, color, radius, strength):
    a = np.clip(np.asarray(mask.filter(ImageFilter.GaussianBlur(radius)), float) / 255 * strength, 0, 1)
    layer = np.zeros((S, S, 4))
    layer[..., :3] = color
    layer[..., 3] = a * 255
    return Image.fromarray(layer.astype('uint8'), 'RGBA')


def background():
    """Sky with stars, floor with a perspective grid, glow on the horizon – as in RetroBackground.swift."""
    y = np.arange(S)[:, None].repeat(S, 1).astype(float)
    rgb = np.zeros((S, S, 3))
    sky = y < HORIZON
    t = np.clip(y / HORIZON, 0, 1)
    rgb[..., 1] = np.where(sky, 0.12 * 255 * t, 0.10 * 255 * np.clip(1 - (y - HORIZON) / (S - HORIZON), 0, 1))
    rgb[..., 2] = np.where(sky, 0.05 * 255 * t, 0.04 * 255 * np.clip(1 - (y - HORIZON) / (S - HORIZON), 0, 1))
    img = Image.fromarray(rgb.astype('uint8'), 'RGB').convert('RGBA')
    d = ImageDraw.Draw(img)
    # Stars (fixed pseudo random positions)
    rng = np.random.default_rng(3)
    for _ in range(70):
        x, yy = rng.uniform(0, S), rng.uniform(0, HORIZON * 0.9)
        r = 2.5 if rng.uniform() < 0.85 else 4
        a = int(rng.uniform(90, 230))
        d.ellipse((x - r, yy - r, x + r, yy + r), fill=(255, 255, 255, a))
    # Grid: lines to the vanishing point and cross lines getting closer towards the viewer
    grid = Image.new('L', (S, S), 0)
    g = ImageDraw.Draw(grid)
    cx = S / 2
    for i in range(-14, 15):
        g.line((cx + i * S * 0.022, HORIZON, cx + i * S * 0.2, S), fill=150, width=4)
    for n in range(1, 16):
        yy = HORIZON + (S - HORIZON) * 0.9 / (n + 0.3)
        if yy <= S:
            fade = min(1, (yy - HORIZON) / (S - HORIZON) * 2.2)
            g.line((0, yy, S, yy), fill=int(220 * fade), width=4)
    layer = Image.new('RGBA', (S, S), GREEN + (0,))
    layer.putalpha(grid)
    img.alpha_composite(layer)
    # Glow and line on the horizon
    band = Image.new('L', (S, S), 0)
    ImageDraw.Draw(band).rectangle((0, HORIZON - 10, S, HORIZON + 10), fill=255)
    img.alpha_composite(glow(band, GREEN, 40, 0.8))
    ImageDraw.Draw(img).line((0, HORIZON, S, HORIZON), fill=GREEN + (230,), width=5)
    return img


def chrome(mask, top, mid_hi, mid_lo, bottom, y0, y1):
    """Chrome look of the logo: bright upper half, hard horizon in the middle, darker lower half, scanlines."""
    ys = np.arange(S)[:, None].repeat(S, 1).astype(float)
    t = np.clip((ys - y0) / max(1, y1 - y0), 0, 1)
    u = (t / 0.5)[..., None]
    l = ((t - 0.5) / 0.5)[..., None]
    rgb = np.where((t < 0.5)[..., None], np.array(top) * (1 - u) + np.array(mid_hi) * u,
                   np.array(mid_lo) * (1 - l) + np.array(bottom) * l)
    scan = ((ys.astype(int) - int(y0)) % 16 >= 11)[..., None]
    rgb = np.where(scan, rgb * 0.72, rgb)
    layer = np.zeros((S, S, 4))
    layer[..., :3] = rgb
    layer[..., 3] = np.asarray(mask, float)
    return Image.fromarray(layer.astype('uint8'), 'RGBA')


def main():
    img = background()
    font = ImageFont.truetype(PIXEL, SIZE)
    # letter, face colors (top, above horizon, below horizon, bottom), extrusion color, glow color
    letters = [('C', ((235, 255, 235), (90, 255, 110), (20, 170, 60), (120, 255, 140)), (0, 90, 30), (60, 255, 90)),
               ('S', ((255, 255, 225), (255, 220, 60), (230, 110, 20), (255, 200, 80)), (110, 40, 0), (255, 150, 40))]
    gap = 24
    widths = [font.getlength(c) for c, *_ in letters]
    x = (S - sum(widths) - gap - DEPTH) / 2
    y = HORIZON - SIZE - 70
    faces = []
    for (ch, _, side, _), width in zip(letters, widths):
        def mask_at(dx, dy, ch=ch, x=x):
            m = Image.new('L', (S, S), 0)
            ImageDraw.Draw(m).text((x + dx, y + dy), ch, font=font, fill=255)
            return m
        faces.append(mask_at(0, 0))
        extrusion = Image.new('RGBA', (S, S), (0, 0, 0, 0))
        for depth in range(DEPTH, 0, -1):
            k = 0.35 + 0.65 * (DEPTH - depth) / DEPTH
            layer = Image.new('RGBA', (S, S), tuple(int(c * k) for c in side) + (255,))
            layer.putalpha(mask_at(depth, depth))
            extrusion.alpha_composite(layer)
        img.alpha_composite(glow(faces[-1], letters[len(faces) - 1][3], 45, 0.9))
        img.alpha_composite(extrusion)
        x += width + gap
    for face, (ch, colors, side, _) in zip(faces, letters):
        outline = Image.new('RGBA', (S, S), (0, 0, 0, 255))
        outline.putalpha(face.filter(ImageFilter.MaxFilter(13)))
        img.alpha_composite(outline)
        img.alpha_composite(chrome(face, *colors, y, y + SIZE))
    out = os.path.join(HERE, 'AppIcon.png')
    img.convert('RGB').save(out)
    print(out)


if __name__ == '__main__':
    main()
