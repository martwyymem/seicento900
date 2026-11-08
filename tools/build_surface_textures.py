#!/usr/bin/env python3
"""Bakes the surface detail textures godot/shaders/town_road.gdshader, road.gdshader, pavement.gdshader and
ground.gdshader layer over their procedural patterns: tarmac aggregate, cracks and stains.

Everything is generated here (numpy + Pillow, fixed seeds), so there is no third-party art to license: change this
script and rebuild rather than editing a PNG.  Run: python3 tools/build_surface_textures.py

  surface_micro.png  512 px over 1.0 m (about 2 mm a texel).  R aggregate tone (stones against binder, 0.5 = mean),
                     G and B a tangent-space normal (x, y; z is rebuilt in the shader), A sparkle (sparse pale
                     stone faces that catch the sun and the headlights; mipmaps average it away at a distance)
  surface_macro.png  512 px over 4.0 m (8 mm a texel).  R cloudy tone (older and newer surface), G crack network
                     (1 = open crack: long wandering fissures with branches, and the fine crazing of old tarmac),
                     B stain mask (oil, rubber and damp), A pore and gloss variation

Both wrap in both directions.
"""
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

N = 512
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "godot", "textures", "surfaces")


def tile_noise(rng, cells, octaves=4, persistence=0.55, n=N):
    """Periodic value noise in 0..1 (smooth bilinear lattice, wrapped)."""
    acc = np.zeros((n, n))
    amp = 1.0
    total = 0.0
    for o in range(octaves):
        c = cells * (2 ** o)
        grid = rng.random((c, c))
        xs = np.arange(n) * c / n
        i0 = np.floor(xs).astype(int) % c
        i1 = (i0 + 1) % c
        f = xs - np.floor(xs)
        f = f * f * (3 - 2 * f)
        row0 = grid[i0][:, i0] * (1 - f)[None, :] + grid[i0][:, i1] * f[None, :]
        row1 = grid[i1][:, i0] * (1 - f)[None, :] + grid[i1][:, i1] * f[None, :]
        acc += amp * (row0 * (1 - f)[:, None] + row1 * f[:, None])
        total += amp
        amp *= persistence
    return acc / total


def norm(a):
    return (a - a.min()) / max(a.max() - a.min(), 1e-6)


def blur(a, radius):
    """Wrap-around gaussian blur by tiling 3x3 so the seams stay invisible."""
    img = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8), "L")
    big = Image.new("L", (N * 3, N * 3))
    for i in range(3):
        for j in range(3):
            big.paste(img, (i * N, j * N))
    big = big.filter(ImageFilter.GaussianBlur(radius))
    return np.asarray(big.crop((N, N, 2 * N, 2 * N)), dtype=np.float64) / 255.0


def worley_blobs(rng, cells, jitter=0.9):
    """Periodic cellular noise: returns (F1 distance, cell id hash) in cell units."""
    gx, gy = np.meshgrid(np.arange(N) * cells / N, np.arange(N) * cells / N)
    base = np.floor(gx).astype(int), np.floor(gy).astype(int)
    pts = rng.random((cells, cells, 2))
    idgrid = rng.random((cells, cells))
    f1 = np.full((N, N), 9.0)
    ids = np.zeros((N, N))
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            cx = (base[0] + dx) % cells
            cy = (base[1] + dy) % cells
            px = base[0] + dx + 0.5 + (pts[cy, cx, 0] - 0.5) * jitter
            py = base[1] + dy + 0.5 + (pts[cy, cx, 1] - 0.5) * jitter
            d = np.hypot(gx - px, gy - py)
            closer = d < f1
            f1 = np.where(closer, d, f1)
            ids = np.where(closer, idgrid[cy, cx], ids)
    return f1, ids


def save(name, arr):
    img = Image.fromarray((np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")
    os.makedirs(OUT, exist_ok=True)
    img.save(os.path.join(OUT, name), optimize=True)
    print("wrote", name, img.size)


def normal_from_height(h, strength):
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    nx = -gx * strength
    ny = -gy * strength
    nz = np.ones_like(h)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    return nx / ln * 0.5 + 0.5, ny / ln * 0.5 + 0.5


def micro():
    rng = np.random.default_rng(2701)
    # stones: three sizes of cells (about 14, 7 and 3.5 mm), each with its own tone and a domed height
    height = np.zeros((N, N))
    tone = np.zeros((N, N))
    for cells, weight in ((72, 1.0), (140, 0.8), (260, 0.6)):
        d, ident = worley_blobs(rng, cells)
        dome = np.clip(1.0 - d * 1.5, 0, 1) ** 0.7
        keep = (ident > 0.25).astype(float)  # a quarter of the cells are plain binder
        height += dome * keep * weight * (0.55 + 0.9 * ident)
        tone += keep * weight * (np.clip(1.0 - d * 1.2, 0, 1) * (ident - 0.4))
    height = norm(height + 0.25 * tile_noise(rng, 90, 3))
    tone = norm(tone) * 0.8 + 0.2 * tile_noise(rng, 40, 3)
    tone = 0.5 + (norm(tone) - 0.5) * 0.9
    # sparkle: only the tallest, palest stone faces
    spark = np.clip((height - 0.78) * 6.0, 0, 1) * np.clip((tone - 0.52) * 5.0, 0, 1)
    spark *= (rng.random((N, N)) > 0.55)
    spark = np.clip(spark + 0.0, 0, 1)
    nx, ny = normal_from_height(height, 3.6)
    out = np.stack([tone, nx, ny, spark], axis=-1)
    save("surface_micro.png", out)


def crack_canvas(rng):
    """Wandering fissures with side branches, drawn on a wrapped canvas."""
    img = Image.new("L", (N * 3, N * 3), 0)
    dr = ImageDraw.Draw(img)

    def walk(x, y, ang, length, width, depth):
        pts = [(x, y)]
        for _ in range(length):
            ang += rng.normal(0, 0.28)
            x += np.cos(ang) * 4.5
            y += np.sin(ang) * 4.5
            pts.append((x, y))
            if depth < 2 and rng.random() < 0.035:
                walk(x, y, ang + rng.choice([-1, 1]) * rng.uniform(0.6, 1.2), int(length * rng.uniform(0.25, 0.5)), max(1, width - 1), depth + 1)
        dr.line(pts, fill=255, width=width, joint="curve")

    # five long fissures; each is drawn in all nine wrapped positions
    for k in range(9):
        sx, sy = rng.uniform(0, N), rng.uniform(0, N)
        ang = rng.uniform(0, np.pi * 2)
        state = rng.bit_generator.state
        for ox in range(3):
            for oy in range(3):
                rng.bit_generator.state = state
                walk(sx + ox * N, sy + oy * N, ang, int(rng.integers(40, 100)), 3, 0)
    return np.asarray(img.crop((N, N, 2 * N, 2 * N)), dtype=np.float64) / 255.0


def macro():
    rng = np.random.default_rng(3911)
    cloud = tile_noise(rng, 3, 5, 0.6)
    cloud = norm(cloud)
    # fissures, a little soft, slightly wider where they run deep
    cracks = blur(crack_canvas(rng), 0.9)
    cracks = np.clip(cracks * 1.8, 0, 1)
    # crazing: short thin strokes at random angles, only in worn zones
    craze_img = Image.new("L", (N * 3, N * 3), 0)
    cd = ImageDraw.Draw(craze_img)
    zone = norm(tile_noise(rng, 4, 3))
    for _ in range(700):
        x, y = rng.uniform(0, N), rng.uniform(0, N)
        if zone[int(y) % N, int(x) % N] < 0.58:
            continue
        a = rng.uniform(0, np.pi)
        ln = rng.uniform(10, 26)
        for ox in range(3):
            for oy in range(3):
                cd.line([(x + ox * N, y + oy * N), (x + np.cos(a) * ln + ox * N, y + np.sin(a) * ln + oy * N)], fill=170, width=1)
    craze = np.asarray(craze_img.crop((N, N, 2 * N, 2 * N)), dtype=np.float64) / 255.0
    craze = blur(craze, 0.6) * 1.4
    crack = np.clip(np.maximum(cracks, craze * 0.7) * (0.7 + 0.5 * tile_noise(rng, 18, 2)), 0, 1)
    # stains: oil drips and tyre-dust in blobs
    stain = norm(tile_noise(rng, 4, 4, 0.6))
    stain = np.clip((stain - 0.55) * 3.2, 0, 1) * (0.5 + 0.5 * tile_noise(rng, 24, 2))
    pores = norm(tile_noise(rng, 60, 3, 0.7))
    out = np.stack([cloud, crack, stain, pores], axis=-1)
    save("surface_macro.png", out)


if __name__ == "__main__":
    micro()
    macro()
