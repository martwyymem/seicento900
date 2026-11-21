"""The aerial base of the open world's satnav picture (build_open_world.hud_map): the GUGiK orthophoto sheets
(see gugik_buildings.py for the source and terms) resampled onto the baker's local metres, colour-matched sheet to
sheet, and an aerial-looking procedural fill from the landuse areas where there is no photo.

The sheets are untrusted data: they are only decoded as images (PIL), nothing in them is executed."""
import math, os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

import gugik_buildings as gugik

MESH = 64  # output px per mesh cell of the piecewise-bilinear warp (sub-pixel against the exact projection)


def photo_mosaic(box_ll, unproj, proj, x0, y0, res, size):
    """(rgb float32 HxWx3 in 0..1, coverage float32 HxW) of the orthophoto over the rectangle at (x0, y0) metres,
    res metres per output pixel, size (w, h) px. Sheets that are not cached are skipped (no network)."""
    Image.MAX_IMAGE_PIXELS = None
    W, H = size
    acc = np.zeros((H, W, 3), np.float32)
    cov = np.zeros((H, W), np.float32)
    try:
        sheets = gugik.orto_sheets(box_ll, False) if os.path.exists(os.path.join(gugik.RAW, 'orto_index.json')) else []
    except Exception as e:  # a missing sheet would download: keep the map bake offline
        print('  orthophoto unavailable:', e)
        sheets = []
    # older sheets first, so the newest one wins where sheets overlap
    sheets = sorted(sheets, key=lambda t: t[6])
    # exact local -> EPSG:2180 at the mesh nodes
    nu, nv = W // MESH + 2, H // MESH + 2
    en = np.zeros((nv, nu, 2))
    for j in range(nv):
        for i in range(nu):
            lat, lon = unproj(x0 + i * MESH * res, y0 + j * MESH * res)
            en[j, i] = gugik.to_2180(lat, lon)
    stats = []
    layers = []
    for t in sheets:
        e0, n0, e1, n1, path, scale, date = t
        # output-pixel bbox of the sheet (its corners in local metres)
        cs = [proj(*gugik.from_2180(e, n)) for e in (e0, e1) for n in (n0, n1)]
        bx0 = max(0, int((min(c[0] for c in cs) - x0) / res) - 2)
        by0 = max(0, int((min(c[1] for c in cs) - y0) / res) - 2)
        bx1 = min(W, int((max(c[0] for c in cs) - x0) / res) + 3)
        by1 = min(H, int((max(c[1] for c in cs) - y0) / res) + 3)
        if bx1 <= bx0 or by1 <= by0:
            continue
        # snap the bbox to the mesh so every cell maps through exact nodes
        bx0, by0 = bx0 // MESH * MESH, by0 // MESH * MESH
        bx1, by1 = min(W, -(-bx1 // MESH) * MESH), min(H, -(-by1 // MESH) * MESH)
        im = Image.open(path)
        im.draft('RGB', im.size)
        im = im.convert('RGB')
        k = max(1, int(round(res / scale / 1.0)))  # box-filter down to about the output resolution first
        src = im.reduce(k) if k > 1 else im
        im.close()
        sres = scale * k
        mesh = []
        for v in range(by0, by1, MESH):
            for u in range(bx0, bx1, MESH):
                i, j = u // MESH, v // MESH

                def s(ii, jj):
                    e, n = en[jj, ii]
                    return ((e - e0) / sres, (n1 - n) / sres)
                q = s(i, j) + s(i, j + 1) + s(i + 1, j + 1) + s(i + 1, j)
                mesh.append(((u - bx0, v - by0, min(u + MESH, bx1) - bx0, min(v + MESH, by1) - by0), q))
        sub = src.transform((bx1 - bx0, by1 - by0), Image.MESH, mesh, Image.BICUBIC)
        valid = Image.new('L', src.size, 255).transform((bx1 - bx0, by1 - by0), Image.MESH, mesh, Image.BILINEAR)
        a = np.asarray(sub, np.float32) / 255.0
        m = np.asarray(valid, np.float32) / 255.0
        # orthophoto no-data (pure black or white borders) does not count as photo
        m = m * (a.max(axis=2) > 0.01) * (a.min(axis=2) < 0.995)
        m = np.where(m > 0.98, 1.0, 0.0).astype(np.float32)
        layers.append((bx0, by0, a, m, date, os.path.basename(path)))
        sel = m > 0.5
        if sel.sum() > 1000:
            stats.append((a[sel].mean(axis=0), a[sel].std(axis=0), sel.sum()))
        else:
            stats.append(None)
        src.close()
    if not layers:
        return acc, cov
    # sheets flown in different months differ in tone: match each one's mean and spread to the pooled ones
    good = [s for s in stats if s is not None]
    wsum = sum(s[2] for s in good)
    gmean = sum(s[0] * s[2] for s in good) / wsum
    gstd = sum(s[1] * s[2] for s in good) / wsum
    wsum = np.zeros((H, W), np.float32)
    for (bx0, by0, a, m, date, name), st in zip(layers, stats):
        if st is not None:
            mean, std, _ = st
            # only part way: the seasons are real, the seams are not
            gain = 1.0 + 0.6 * (gstd / np.maximum(std, 1e-3) - 1.0)
            a = (a - mean) * gain + mean + 0.75 * (gmean - mean)
        h, w = m.shape
        # feathered weights, normalised below: overlapping sheet edges cross-fade instead of darkening
        mm = Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2))
        f = np.asarray(mm, np.float32) / 255.0 * m
        acc[by0:by0 + h, bx0:bx0 + w] += np.clip(a, 0, 1) * f[..., None]
        wsum[by0:by0 + h, bx0:bx0 + w] += f
        cov[by0:by0 + h, bx0:bx0 + w] = np.maximum(cov[by0:by0 + h, bx0:bx0 + w], m)
        print(f'  orthophoto {name} ({date})', flush=True)
    acc /= np.maximum(wsum, 1e-4)[..., None]
    return acc, cov


def _noise(shape, cell, seed, octaves=3):
    """Smooth value noise in -1..1, cell px per lattice step at the first octave."""
    rng = np.random.default_rng(seed)
    H, W = shape
    out = np.zeros(shape, np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        c = max(1.0, cell / (2 ** o))
        gw, gh = int(W / c) + 3, int(H / c) + 3
        g = Image.fromarray(rng.random((gh, gw), dtype=np.float32) * 255).convert('L')
        g = g.resize((int(gw * c), int(gh * c)), Image.BICUBIC).crop((0, 0, W, H))
        out += (np.asarray(g, np.float32) / 127.5 - 1.0) * amp
        tot += amp
        amp *= 0.5
    return out / tot


def procedural(areas, waterways, buildings, x0, y0, res, size):
    """An aerial-looking fill (HxWx3 float 0..1) from the landuse areas: meadow ground, fields in varied crop colours
    with furrows, forest canopy, built-up ground with roofs, water."""
    W, H = size

    def px(fl):
        return [((fl[i] - x0) / res, (fl[i + 1] - y0) / res) for i in range(0, len(fl), 2)]

    n1 = _noise((H, W), 40 / res, 1)
    n2 = _noise((H, W), 6 / res, 2, 2)
    img = np.empty((H, W, 3), np.float32)
    img[:] = (0.36, 0.42, 0.25)  # meadow
    img += (n1[..., None] * 0.05 + n2[..., None] * 0.02) * np.array([1.0, 1.0, 0.7], np.float32)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    crops = [(0.50, 0.47, 0.33), (0.36, 0.44, 0.24), (0.55, 0.51, 0.38), (0.42, 0.36, 0.28), (0.40, 0.47, 0.27),
             (0.30, 0.40, 0.22), (0.47, 0.45, 0.30)]
    fill_layers = {'park': (0.32, 0.40, 0.24), 'meadow': (0.38, 0.44, 0.27), 'pitch': (0.30, 0.46, 0.25),
                   'residential': (0.36, 0.40, 0.29), 'industrial': (0.44, 0.43, 0.41), 'parking': (0.45, 0.45, 0.44),
                   'cemetery': (0.36, 0.40, 0.30), 'allotments': (0.36, 0.42, 0.26), 'brownfield': (0.50, 0.46, 0.38),
                   'scrub': (0.28, 0.34, 0.20), 'wetland': (0.30, 0.36, 0.26)}
    canopy = _noise((H, W), 8 / res, 3, 3)
    for idx, (kind, ring, holes, _) in enumerate(areas):
        if len(ring) < 6:
            continue
        pts = px(ring)
        bx = [max(0, int(min(p[0] for p in pts)) - 1), max(0, int(min(p[1] for p in pts)) - 1),
              min(W, int(max(p[0] for p in pts)) + 2), min(H, int(max(p[1] for p in pts)) + 2)]
        if bx[2] <= bx[0] or bx[3] <= bx[1]:
            continue
        mk = Image.new('L', (bx[2] - bx[0], bx[3] - bx[1]), 0)
        dm = ImageDraw.Draw(mk)
        dm.polygon([(p[0] - bx[0], p[1] - bx[1]) for p in pts], fill=255)
        for hl in holes:
            if len(hl) >= 6:
                dm.polygon([(p[0] - bx[0], p[1] - bx[1]) for p in px(hl)], fill=0)
        m = np.asarray(mk.filter(ImageFilter.GaussianBlur(0.6)), np.float32)[..., None] / 255.0
        if not m.any():
            continue
        sl = (slice(bx[1], bx[3]), slice(bx[0], bx[2]))
        h = (idx * 2654435761) % 1000 / 999.0
        if kind == 'farmland':
            c = np.array(crops[int(h * len(crops)) % len(crops)], np.float32)
            ang = h * math.pi * 7.3
            per = (3.0 + 2.0 * ((idx * 40503) % 7) / 6.0) / res * 2  # furrow spacing px
            fur = np.sin((xx[sl] * math.cos(ang) + yy[sl] * math.sin(ang)) * (2 * math.pi / per))
            col = c + (fur[..., None] * 0.025 + n1[sl][..., None] * 0.05 + n2[sl][..., None] * 0.02)
        elif kind == 'forest':
            cn = canopy[sl][..., None]
            col = np.array((0.17, 0.24, 0.13), np.float32) + cn * np.array((0.07, 0.09, 0.05), np.float32)
            col = col - np.clip(-cn - 0.25, 0, 1) * 0.15  # gaps between crowns
        elif kind == 'water':
            col = np.array((0.16, 0.24, 0.26), np.float32) + n1[sl][..., None] * 0.02
        elif kind in fill_layers:
            col = np.array(fill_layers[kind], np.float32) + n1[sl][..., None] * 0.04 + n2[sl][..., None] * 0.03
        else:
            continue
        img[sl] = img[sl] * (1 - m) + col * m
    land = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))
    d = ImageDraw.Draw(land)
    for ww, pts in waterways:
        d.line(px(pts), fill=(42, 60, 64), width=max(1, int(ww / res)))
    rng = np.random.default_rng(5)
    roofs = [(132, 78, 64), (110, 68, 58), (94, 92, 92), (140, 132, 124), (78, 74, 76), (118, 98, 82)]
    for b in buildings:
        if len(b[4]) >= 6:
            d.polygon(px(b[4]), fill=roofs[int(rng.integers(len(roofs)))])
    return np.asarray(land, np.float32) / 255.0


def hillshade(terrain, x0, y0, res, size, z_scale=4.0):
    """Lambert shade (HxW, ~1 on the flat) of the terrain grid, lit from the north-west."""
    nx, ny, step = terrain['nx'], terrain['ny'], terrain['step']
    z = np.array(terrain['h'], np.float32).reshape(ny, nx) * z_scale
    gy, gx = np.gradient(z, step)
    lx, ly, lz = -0.6, -0.6, 0.53  # x east, y south: light from the north-west, fairly low
    nrm = np.sqrt(gx * gx + gy * gy + 1)
    sh = (-gx * lx - gy * ly + lz) / nrm / lz
    im = Image.fromarray(sh.astype(np.float32), 'F')
    W, H = size
    # grid node i sits at x0 + i*step: scale the grid so node centres land at the right output pixels
    im = im.transform((W, H), Image.AFFINE, (res / step, 0, -0.0, 0, res / step, 0), Image.BILINEAR)
    return np.asarray(im, np.float32)
