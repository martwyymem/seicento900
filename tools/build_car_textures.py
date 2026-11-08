#!/usr/bin/env python3
"""Bakes the textures godot/shaders/car_plate.gdshader puts on the cars' number plates.

Pillow + numpy only, fixed seeds, fonts from godot/fonts (OFL), so there is no third-party art: change this script
and rebuild rather than editing the PNG.   Run: python3 tools/build_car_textures.py

  godot/textures/car/plate_pl.png   a stack of ROWS Polish plates (white, black embossed letters, blue EU strip with the
                                    twelve stars and PL), each 1024 x 224 px for the 520 x 114 mm plate. The shader
                                    picks a row per car. Also carries a faint dirt and a rolled pressed-metal rim.
"""
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "godot", "textures", "car")
FONT = os.path.join(HERE, "..", "godot", "fonts", "Archivo.ttf")
W, H = 1024, 224
PLATES = ["KOS 8U214", "KOS 41250", "SB 7K3R2", "KRA 92E31", "KOS 5C730", "KPS 61047", "SB 38D90", "KOS 17Y58"]
ROWS = len(PLATES)


def font(size, weight=700, width=100):
    f = ImageFont.truetype(FONT, size)
    try:
        axes = f.get_variation_axes()
        vals = []
        for a in axes:
            nm = a.get("name", b"")
            nm = nm.decode() if isinstance(nm, bytes) else nm
            vals.append(weight if "eight" in nm else width if "idth" in nm else a["default"])
        f.set_variation_by_axes(vals)
    except Exception:
        pass
    return f


def plate(text, seed):
    rng = random.Random(seed)
    img = Image.new("RGB", (W, H), (236, 235, 228))
    d = ImageDraw.Draw(img)
    # blue EU strip on the left with the ring of stars and PL
    strip = 118
    d.rectangle([0, 0, strip, H], fill=(18, 56, 160))
    cx, cy, r = strip // 2, 84, 40
    for k in range(12):
        a = 2 * math.pi * k / 12
        x, y = cx + r * math.sin(a), cy - r * math.cos(a)
        s = 7
        pts = [(x + (s if i % 2 == 0 else s * 0.4) * math.sin(i * math.pi / 5),
                y - (s if i % 2 == 0 else s * 0.4) * math.cos(i * math.pi / 5)) for i in range(10)]
        d.polygon(pts, fill=(255, 210, 20))
    d.text((cx, 176), "PL", font=font(58, 800, 90), fill=(250, 250, 250), anchor="mm")
    # characters: the group ahead of the space is the district, the rest the serial
    ft = font(176, 800, 82)
    left, right = text.split(" ")
    gap = 40
    wl = d.textlength(left, font=ft)
    wr = d.textlength(right, font=ft)
    x0 = strip + (W - strip - (wl + gap + wr)) / 2
    y = H / 2 + 6
    # embossed look: a pale edge below-right, a dark body
    for (dx, dy, col) in ((3, 3, (250, 250, 246)), (0, 0, (14, 14, 16))):
        d.text((x0 + dx, y + dy), left, font=ft, fill=col, anchor="lm")
        d.text((x0 + wl + gap + dx, y + dy), right, font=ft, fill=col, anchor="lm")
    # pressed rim: a dark border line, rounded corners are cut by the mesh
    d.rounded_rectangle([5, 5, W - 6, H - 6], radius=18, outline=(20, 20, 22), width=7)
    d.rounded_rectangle([14, 14, W - 15, H - 15], radius=12, outline=(214, 213, 206), width=3)
    # two screw heads on the left of the strip's top and bottom
    for (sx, sy) in ((W - 26, 30), (W - 26, H - 30)):
        d.ellipse([sx - 8, sy - 8, sx + 8, sy + 8], fill=(150, 150, 150))
        d.line([sx - 6, sy, sx + 6, sy], fill=(60, 60, 60), width=2)
    a = np.asarray(img).astype(np.float32) / 255.0
    # a little grime: darker towards the lower edge, speckle, a slight vertical streak or two
    yy = np.linspace(0, 1, H)[:, None, None]
    a *= 1.0 - 0.10 * yy ** 2
    nrng = np.random.default_rng(seed)
    a *= 1.0 - 0.05 * nrng.random((H, W, 1))
    for _ in range(3):
        sx = nrng.integers(strip, W)
        w = nrng.integers(4, 16)
        a[:, max(0, sx - w):sx + w] *= 0.975
    a = np.clip(a, 0, 1)
    out = Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.6))
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    atlas = Image.new("RGB", (W, H * ROWS))
    for i, t in enumerate(PLATES):
        atlas.paste(plate(t, 100 + i), (0, H * i))
    path = os.path.join(OUT, "plate_pl.png")
    atlas.save(path, optimize=True)
    print("wrote", path, atlas.size)


if __name__ == "__main__":
    main()
