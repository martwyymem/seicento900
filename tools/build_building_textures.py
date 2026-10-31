#!/usr/bin/env python3
"""Bakes the detail textures godot/shaders/building.gdshader multiplies onto its procedural facades.

Everything is generated here (numpy + Pillow, fixed seeds), so there is no third-party art to license: change
this script and rebuild rather than editing a PNG.  Run: python3 tools/build_building_textures.py

All three textures cover the same 1.5 m square at 240 px (160 px per metre), so plaster, brick and tile have the
same texel density on a wall.  1.5 m holds a whole number of bricks (6 of 0.25 m), brick courses (20 of 0.075 m)
and roof courses (5 of 0.3 m, 6 tiles of 0.25 m), so they repeat without a seam.  Values are detail modulators
centred on about 0.5 (the shader maps them to a 0.85..1.15 brightness factor), not albedo.

  building_wall.png   R roughcast plaster, G smooth plaster with trowel marks and stains, B concrete panel with
                      pores, A reserved (1)
  building_brick.png  RGB per-brick tint (hue varies a little), A mortar mask (1 = mortar, with chipped edges)
  building_roof.png   R tile shading (lit lip, shadowed overlap), G moss and soot mask, B per-tile tint
"""
import os
import sys

import numpy as np
from PIL import Image

N = 240
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "godot", "textures", "buildings")


def tile_noise(rng, cells, octaves=4, persistence=0.55):
    """Periodic value noise in 0..1: sums of bilinear-interpolated random grids with a wrapped lattice."""
    acc = np.zeros((N, N))
    amp = 1.0
    total = 0.0
    for o in range(octaves):
        c = cells * (2 ** o)
        grid = rng.random((c, c))
        xs = np.arange(N) * c / N
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


def save(name, arr):
    img = Image.fromarray((np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")
    os.makedirs(OUT, exist_ok=True)
    img.save(os.path.join(OUT, name), optimize=True)


def wall():
    rng = np.random.default_rng(1601)
    # roughcast: fine grain plus a coarse lumpy relief, lit from the top left
    fine = tile_noise(rng, 60, 2)
    lump = tile_noise(rng, 12, 3)
    relief = norm(fine * 0.6 + lump * 0.4)
    gy, gx = np.gradient(relief)
    rough = norm(0.5 + (-gx - gy) * 6.0 + (relief - 0.5) * 0.8)
    # smooth plaster: broad trowel sweeps and faint stains
    sweep = tile_noise(rng, 5, 3)
    stain = norm(tile_noise(rng, 3, 4))
    smooth = norm(0.55 * sweep + 0.25 * stain + 0.2 * tile_noise(rng, 30, 2))
    smooth = 0.5 + (smooth - 0.5) * 0.7
    # prefab concrete: pores and a few shuttering lines
    pores = tile_noise(rng, 80, 2)
    pit = (pores > 0.78).astype(float) * 0.35
    panel = norm(tile_noise(rng, 16, 3)) * 0.6 + 0.2 - pit
    panel[:, ::80] -= 0.04
    panel[::48, :] -= 0.04
    a = np.ones((N, N))
    save("building_wall.png", np.stack([rough, smooth, panel, a], axis=-1))


def brick():
    rng = np.random.default_rng(1602)
    course_h = N // 20  # 12 px = 7.5 cm
    brick_w = N // 6  # 40 px = 25 cm
    tint = np.zeros((N, N, 3))
    mortar = np.zeros((N, N))
    grain = tile_noise(rng, 90, 2)
    for c in range(20):
        shift = brick_w // 2 if c % 2 else 0
        for b in range(7):
            x0 = b * brick_w - shift
            shade = 0.5 + (rng.random() - 0.5) * 0.55
            hue = (rng.random(3) - 0.5) * np.array([0.14, 0.10, 0.08])
            for yy in range(c * course_h, (c + 1) * course_h):
                for xx in range(x0, x0 + brick_w):
                    tint[yy, xx % N] = shade + hue
    ys, xs = np.mgrid[0:N, 0:N]
    yin = ys % course_h
    mortar_y = (yin < 2).astype(float)
    course = ys // course_h
    xin = (xs + np.where(course % 2 == 1, brick_w // 2, 0)) % brick_w
    mortar_x = (xin < 2).astype(float)
    mortar = np.maximum(mortar_y, mortar_x)
    # chipped, uneven mortar edges
    edge = tile_noise(rng, 70, 2)
    mortar = np.clip(mortar + ((edge > 0.62) & (np.roll(mortar, 1, 0) + np.roll(mortar, 1, 1) > 0)) * 0.6, 0, 1)
    tint = tint * (0.85 + 0.3 * grain[..., None])
    save("building_brick.png", np.concatenate([tint, mortar[..., None]], axis=-1))


def roof():
    rng = np.random.default_rng(1603)
    course_h = N // 5  # 48 px = 30 cm
    tile_w = N // 6  # 40 px = 25 cm
    ys, xs = np.mgrid[0:N, 0:N]
    course = ys // course_h
    yin = (ys % course_h) / course_h  # 0 at the course's lower edge
    xin = ((xs + np.where(course % 2 == 1, tile_w // 2, 0)) % tile_w) / tile_w
    shade = 0.35 + 0.65 * np.clip(yin * 1.6, 0, 1)  # shadow tucked under the course above, lit lip at the top
    shade *= 0.9 + 0.1 * np.sin(xin * np.pi)  # a slightly domed tile
    shade[xin < 0.03] *= 0.7  # the joint between tiles
    tile_id = (course * 7 + ((xs + np.where(course % 2 == 1, tile_w // 2, 0)) // tile_w)) % 97
    per_tile = rng.random(97)[tile_id]
    shade = shade * (0.9 + 0.2 * tile_tint_noise(rng))
    moss = norm(tile_noise(rng, 5, 4))
    moss = np.clip((moss - 0.5) * 2.2, 0, 1)
    save("building_roof.png", np.stack([np.clip(shade * 0.7, 0, 1), moss, per_tile, np.ones((N, N))], axis=-1))


def tile_tint_noise(rng):
    return tile_noise(rng, 50, 2)


if __name__ == "__main__":
    which = sys.argv[1:] or ["wall", "brick", "roof"]
    for w in which:
        {"wall": wall, "brick": brick, "roof": roof}[w]()
    print("wrote", ", ".join(which), "to", os.path.normpath(OUT))
