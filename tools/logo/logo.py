#!/usr/bin/env python3
"""Logo of CreepSmash iOS: arcade lettering in a pixel font (Press Start 2P, SIL Open Font License) with a
3D extrusion, chrome gradient, scanlines and neon glow."""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = os.path.dirname(__file__)
PIXEL = os.path.join(HERE, 'PressStart2P-Regular.ttf')
W, H = 1700, 520
SIZE = 132          # title font size
DEPTH = 14          # extrusion depth in pixels


def mask_of(text, font, xy):
    m = Image.new('L', (W, H), 0)
    ImageDraw.Draw(m).text(xy, text, font=font, fill=255)
    return m


def glow(mask, color, radius, strength):
    a = np.clip(np.asarray(mask.filter(ImageFilter.GaussianBlur(radius)), float) / 255 * strength, 0, 1)
    layer = np.zeros((H, W, 4))
    layer[..., :3] = color
    layer[..., 3] = a * 255
    return Image.fromarray(layer.astype('uint8'), 'RGBA')


def gradient_fill(mask, top, mid_hi, mid_lo, bottom, y0, y1):
    """Chrome look: bright upper half, a hard horizon in the middle, darker lower half; plus scanlines."""
    ys = np.arange(H)[:, None].repeat(W, 1).astype(float)
    t = np.clip((ys - y0) / max(1, y1 - y0), 0, 1)
    u = (t / 0.5)[..., None]
    l = ((t - 0.5) / 0.5)[..., None]
    rgb = np.where((t < 0.5)[..., None], np.array(top) * (1 - u) + np.array(mid_hi) * u,
                   np.array(mid_lo) * (1 - l) + np.array(bottom) * l)
    scan = ((ys.astype(int) - int(y0)) % 6 >= 4)[..., None]   # every 6th/7th pixel row darker
    rgb = np.where(scan, rgb * 0.72, rgb)
    layer = np.zeros((H, W, 4))
    layer[..., :3] = rgb
    layer[..., 3] = np.asarray(mask, float)
    return Image.fromarray(layer.astype('uint8'), 'RGBA')


def main(subtitle, name):
    img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    big = ImageFont.truetype(PIXEL, SIZE)
    # word, face colors (top, above horizon, below horizon, bottom), extrusion color
    words = [('CREEP', ((235, 255, 235), (90, 255, 110), (20, 170, 60), (120, 255, 140)), (0, 90, 30)),
             ('SMASH', ((255, 255, 225), (255, 220, 60), (230, 110, 20), (255, 200, 80)), (110, 40, 0))]
    gap = 34
    widths = [big.getlength(w) for w, _, _ in words]
    x = (W - sum(widths) - gap - DEPTH) / 2
    y = 70
    faces = []
    for (word, colors, side), width in zip(words, widths):
        faces.append(mask_of(word, big, (x, y)))
        # extrusion: copies shifted to the bottom right, dark at the back, lighter towards the front
        for d in range(DEPTH, 0, -1):
            k = 0.35 + 0.65 * (DEPTH - d) / DEPTH
            layer = Image.new('RGBA', (W, H), tuple(int(c * k) for c in side) + (255,))
            layer.putalpha(mask_of(word, big, (x + d, y + d)))
            img.alpha_composite(layer)
        x += width + gap
    under = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    for face, color in zip(faces, ((60, 255, 90), (255, 150, 40))):
        under.alpha_composite(glow(face, color, 30, 0.9))
    img = Image.alpha_composite(under, img)
    for face, (word, colors, side) in zip(faces, words):
        outline = Image.new('RGBA', (W, H), (0, 0, 0, 255))
        outline.putalpha(face.filter(ImageFilter.MaxFilter(7)))
        img.alpha_composite(outline)
        img.alpha_composite(gradient_fill(face, *colors, y, y + SIZE))
    # subtitle with fading lines left and right
    small = ImageFont.truetype(PIXEL, 30)
    sw = small.getlength(subtitle)
    sx = (W - sw) / 2
    sy = y + SIZE + DEPTH + 58
    img.alpha_composite(glow(mask_of(subtitle, small, (sx, sy)), (60, 255, 90), 10, 0.8))
    d = ImageDraw.Draw(img)
    d.text((sx, sy), subtitle, font=small, fill=(190, 255, 190, 255))
    for x0, x1 in ((sx - 260, sx - 30), (sx + sw + 30, sx + sw + 260)):
        for i, a in enumerate((255, 160, 90)):
            d.line((x0, sy + 12 + i * 8, x1, sy + 12 + i * 8), fill=(60, 255, 90, a), width=3)
    # crop to the visible part with a margin
    alpha = img.split()[3].point(lambda a: 255 if a > 8 else 0)
    x0, y0, x1, y1 = alpha.getbbox()
    img = img.crop((max(0, x0 - 10), max(0, y0 - 10), min(W, x1 + 10), min(H, y1 + 10)))
    out = os.path.join(HERE, name)
    img.save(out)
    print(out, img.size)


if __name__ == '__main__':
    # The subtitle reads the same in English and German, so one logo serves both languages.
    main('MULTIPLAYER TOWER DEFENSE', 'logo.png')
