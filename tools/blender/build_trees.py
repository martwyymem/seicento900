"""Builds the trees that stand round the circuits: low-poly but shaped like the real species, in their real
sizes, for the woods, rows and parks that surroundings.gd lays out from OpenStreetMap.

Run from the repository root (Blender 4.2 or newer, headless):

    blender -b -P tools/blender/build_trees.py -- [--renders DIR]

Writes godot/models/trees.glb. Each object is one tree standing on its origin (Blender Z up):

  Spruce      Norway spruce, 17 m: drooping branch whorls down to the ground (Eifel, Ardennes)
  Pine        Scots pine, 16 m: a tall bare trunk, orange near the top, a few flat clumps of needles
  Broadleaf   oak/beech, 14 m: a lumpy round crown on three limbs
  Birch       11 m: a slim white trunk with black marks, a light, open crown
  Poplar      Lombardy poplar, 20 m: a narrow column (France, Italy)
  Cypress     Italian cypress, 13 m: a dark green spire (Monaco, Italy)
  StonePine   umbrella pine, 12 m: a forked trunk under a wide flat crown (Monaco, Italy)
  Palm        Canary palm, 9 m: a ringed trunk and a head of arching fronds (Monaco)

The vertex colour is the colour (linear); its alpha marks foliage (1) against wood (0) for the leaf flutter
in foliage.gdshader. Every tree uses the one material "Foliage".
"""
import bpy
import math
import os
import random
import sys
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit  # noqa: E402
from kit import MB, srgb  # noqa: E402

OUT_GLB = os.path.join(kit.ROOT, "godot", "models", "trees.glb")
kit.MATERIALS.update({"Foliage": ((1.0, 1.0, 1.0), 0.88, 0.0, {})})


def rgba(hex_colour, alpha, shade=1.0):
	r, g, b = srgb(hex_colour)
	return (r * shade, g * shade, b * shade, alpha)


def bark(mb, a, b, r0, r1, colour, segs=7, rings=None):
	"""A tapering trunk or limb from a to b. rings: [(t, colour)] bands (birch marks), else one colour."""
	a, b = Vector(a), Vector(b)
	axis = (b - a).normalized()
	side = axis.cross(Vector((0, 0, 1)) if abs(axis.z) < 0.9 else Vector((1, 0, 0))).normalized()
	up = side.cross(axis)
	steps = [0.0, 1.0] if not rings else sorted({0.0, 1.0, *[t for t, _ in rings]})
	loops = []
	for t in steps:
		c = a.lerp(b, t)
		r = r0 + (r1 - r0) * t
		col = colour
		if rings:
			for rt, rc in rings:
				if t >= rt:
					col = rc
		loops.append([mb.vert(c + (side * math.cos(k * 2 * math.pi / segs) + up * math.sin(k * 2 * math.pi / segs)) * r,
			rgba(col, 0.0)) for k in range(segs)])
	for la, lb in zip(loops, loops[1:]):
		for k in range(segs):
			k1 = (k + 1) % segs
			mb.face([la[k], la[k1], lb[k1], lb[k]], "Foliage", out=lambda q, a=a, axis=axis: q - (a + axis * (q - a).dot(axis)))
	top = mb.vert(b, rgba(colour, 0.0))
	for k in range(segs):
		mb.face([loops[-1][k], loops[-1][(k + 1) % segs], top], "Foliage", out=axis)


def _icosphere():
	t = (1 + 5 ** 0.5) / 2
	v = [Vector(p).normalized() for p in ((-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t),
		(0, -1, -t), (0, 1, -t), (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1))]
	f = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6),
		(7, 1, 8), (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7),
		(9, 8, 1)]
	cache = {}

	def mid(i, j):
		key = (min(i, j), max(i, j))
		if key not in cache:
			v.append((v[i] + v[j]).normalized())
			cache[key] = len(v) - 1
		return cache[key]
	out = []
	for a, b, c in f:
		ab, bc, ca = mid(a, b), mid(b, c), mid(c, a)
		out += [(a, ab, ca), (b, bc, ab), (c, ca, bc), (ab, bc, ca)]
	return v, out


ICO = _icosphere()


def blob(mb, rng, centre, radii, colours, jitter=0.22, alpha=1.0):
	"""A clump of leaves: a lumpy ellipsoid, darker underneath and on the inside, lighter on top."""
	centre = Vector(centre)
	pts, faces = ICO
	idx = []
	for p in pts:
		j = 1.0 + (rng.random() - 0.5) * 2 * jitter
		q = Vector((p.x * radii[0], p.y * radii[1], p.z * radii[2])) * j
		shade = 0.72 + 0.38 * (p.z * 0.5 + 0.5) + (rng.random() - 0.5) * 0.12
		idx.append(mb.vert(centre + q, rgba(rng.choice(colours), alpha, shade)))
	for a, b, c in faces:
		mb.face([idx[a], idx[b], idx[c]], "Foliage", out=lambda q, c0=centre: q - c0)


def spruce():
	rng = random.Random(1)
	mb = MB()
	h = 17.0
	bark(mb, (0, 0, -0.5), (0, 0, h), 0.28, 0.04, "#4a3a2c")
	greens = ["#1d3822", "#22402a", "#1a3320", "#284a30"]
	whorls = 11
	for k in range(whorls):
		t = k / (whorls - 1)
		z = 1.2 + t * (h - 2.2)
		r = 3.4 * (1.0 - t) ** 0.9 + 0.35
		cone_h = 1.9 * (1.0 - t * 0.5)
		m = 9
		apex = mb.vert((0, 0, z + cone_h), rgba(rng.choice(greens), 1.0, 1.1))
		under = mb.vert((0, 0, z + cone_h * 0.35), rgba(greens[2], 1.0, 0.55))
		ring = []
		rot = rng.random() * math.pi
		for j in range(2 * m):
			a = rot + j * math.pi / m
			rr = r * (1.0 if j % 2 == 0 else 0.62) * (0.88 + rng.random() * 0.24)
			droop = -0.45 * rr if j % 2 == 0 else -0.1 * rr
			shade = 1.05 if j % 2 == 0 else 0.8
			ring.append(mb.vert((math.cos(a) * rr, math.sin(a) * rr, z + droop), rgba(rng.choice(greens), 1.0, shade)))
		for j in range(2 * m):
			a, b = ring[j], ring[(j + 1) % (2 * m)]
			mb.face([apex, a, b], "Foliage", out=(0, 0, 1))
			mb.face([under, b, a], "Foliage", out=(0, 0, -1))
	return mb


def pine():
	rng = random.Random(2)
	mb = MB()
	lean = Vector((0.5, 0.2, 0))
	base, top = Vector((0, 0, -0.5)), Vector((0, 0, 12.5)) + lean
	bark(mb, base, base.lerp(top, 0.55), 0.3, 0.2, "#5b4636")
	bark(mb, base.lerp(top, 0.55), top, 0.2, 0.08, "#b8683f")
	greens = ["#2c4a2a", "#335430", "#27432a"]
	for k in range(6):
		a = k * 2.4 + rng.random()
		z = 11.0 + rng.random() * 4.0
		d = 0.6 + rng.random() * 2.0
		c = Vector((math.cos(a) * d, math.sin(a) * d, z)) + lean
		limb_from = base.lerp(top, (z - 3.0) / 13.0)
		bark(mb, limb_from, c, 0.1, 0.05, "#b8683f", segs=5)
		blob(mb, rng, c, (2.0 + rng.random(), 1.8 + rng.random(), 0.9 + rng.random() * 0.4), greens)
	return mb


def broadleaf():
	rng = random.Random(3)
	mb = MB()
	bark(mb, (0, 0, -0.5), (0.1, 0, 4.2), 0.42, 0.32, "#56432f")
	greens = ["#3a5a2b", "#44652f", "#355526", "#4d6e34"]
	centre = Vector((0.1, 0, 9.0))
	for k in range(3):
		a = k * 2.1 + 0.4
		end = centre + Vector((math.cos(a) * 2.4, math.sin(a) * 2.4, -0.6))
		bark(mb, (0.1, 0, 3.9), end, 0.26, 0.1, "#56432f", segs=6)
	for k in range(10):
		a = k * 2.39996
		el = rng.uniform(-0.5, 0.9)
		d = 2.6 + rng.random() * 1.2
		c = centre + Vector((math.cos(a) * math.cos(el) * d, math.sin(a) * math.cos(el) * d, math.sin(el) * d * 0.8))
		r = 2.2 + rng.random() * 0.9
		blob(mb, rng, c, (r, r, r * 0.85), greens)
	return mb


def birch():
	rng = random.Random(4)
	mb = MB()
	marks = [(t, "#1c1c1c" if i % 2 else "#e8e4da") for i, t in enumerate([0.08, 0.12, 0.3, 0.33, 0.52, 0.55, 0.7, 0.72])]
	bark(mb, (0, 0, -0.5), (0.3, 0.1, 9.5), 0.2, 0.06, "#e8e4da", segs=6, rings=marks)
	greens = ["#6b8a3a", "#7a9a44", "#5e7d33"]
	for k in range(6):
		a = k * 2.3
		z = 5.5 + rng.random() * 4.5
		d = 0.8 + rng.random() * 1.1
		blob(mb, rng, (0.2 + math.cos(a) * d, math.sin(a) * d, z), (1.3 + rng.random() * 0.5,) * 2 + (1.6,), greens, jitter=0.3)
	return mb


def poplar():
	rng = random.Random(5)
	mb = MB()
	bark(mb, (0, 0, -0.5), (0, 0, 3.0), 0.35, 0.28, "#6a5a48")
	greens = ["#3f5f2c", "#4a6a32", "#36542a"]
	for k in range(6):
		z = 3.5 + k * 2.7
		r = 2.2 * (1.0 - (k / 6.0) ** 2 * 0.7)
		blob(mb, rng, (rng.uniform(-0.2, 0.2), rng.uniform(-0.2, 0.2), z + 1.2), (r, r, 2.4), greens, jitter=0.18)
	return mb


def cypress():
	rng = random.Random(6)
	mb = MB()
	bark(mb, (0, 0, -0.5), (0, 0, 1.5), 0.25, 0.2, "#5a4a3a")
	greens = ["#22361f", "#2a4226", "#1d301b"]
	for k in range(4):
		z = 2.0 + k * 2.9
		r = 1.45 * (1.0 - k / 4.0 * 0.55)
		blob(mb, rng, (0, 0, z + 1.5), (r, r, 2.3), greens, jitter=0.12)
	return mb


def stone_pine():
	rng = random.Random(7)
	mb = MB()
	fork = Vector((0.3, 0, 6.0))
	bark(mb, (0, 0, -0.5), fork, 0.38, 0.28, "#6a4a38")
	greens = ["#2f4a26", "#38552b", "#2a4222"]
	tops = []
	for k in range(3):
		a = k * 2.1 + 0.5
		tip = fork + Vector((math.cos(a) * 2.2, math.sin(a) * 2.2, 3.4))
		bark(mb, fork, tip, 0.2, 0.1, "#7a5040", segs=6)
		tops.append(tip)
	for k in range(9):
		a = k * 2.39996
		d = 1.0 + (k % 3) * 1.6
		c = Vector((0.3 + math.cos(a) * d, math.sin(a) * d, 10.4 + rng.uniform(-0.3, 0.5)))
		blob(mb, rng, c, (2.4 + rng.random() * 0.6, 2.4 + rng.random() * 0.6, 0.9), greens, jitter=0.15)
	return mb


def palm():
	rng = random.Random(8)
	mb = MB()
	pts = [Vector((0.35 * math.sin(t * 1.4), 0, -0.5 + t * 9.0)) for t in (0.0, 0.25, 0.5, 0.75, 1.0)]
	for i in range(4):
		bark(mb, pts[i], pts[i + 1], 0.42 - i * 0.03, 0.39 - i * 0.03, "#7a6650" if i % 2 else "#6e5b46", segs=8)
	crown = pts[-1]
	greens = ["#4a6a2a", "#557530", "#3f5e24"]
	for k in range(11):
		a = k * 2 * math.pi / 11 + rng.random() * 0.2
		d = Vector((math.cos(a), math.sin(a), 0))
		side = Vector((-d.y, d.x, 0))
		length = 4.2 + rng.random() * 1.0
		rise = 1.4 + rng.random() * 0.8
		col = rng.choice(greens)
		n = 7
		prev = None
		for j in range(n + 1):
			t = j / n
			c = crown + d * (t * length) + Vector((0, 0, rise * math.sin(t * math.pi * 0.8) - t * t * 2.2))
			w = 0.75 * math.sin(math.pi * min(1.0, t * 1.15 + 0.08))
			row = [mb.vert(c - side * w + Vector((0, 0, -0.25 * w)), rgba(col, 1.0, 0.85)),
				mb.vert(c + Vector((0, 0, 0.05)), rgba(col, 1.0, 1.1)),
				mb.vert(c + side * w + Vector((0, 0, -0.25 * w)), rgba(col, 1.0, 0.85))]
			if prev:
				for s in range(2):
					quad = [prev[s], prev[s + 1], row[s + 1], row[s]]
					mb.face(quad, "Foliage", out=(0, 0, 1))
					mb.face(list(reversed(quad)), "Foliage", out=(0, 0, -1))
			prev = row
	# dead fronds hanging under the crown
	for k in range(6):
		a = k * 1.05
		blob(mb, rng, crown + Vector((math.cos(a) * 0.5, math.sin(a) * 0.5, -0.6)), (0.5, 0.5, 0.9), ["#8a7250"], alpha=0.0)
	return mb


TREES = {"Spruce": spruce, "Pine": pine, "Broadleaf": broadleaf, "Birch": birch, "Poplar": poplar,
	"Cypress": cypress, "StonePine": stone_pine, "Palm": palm}


def main():
	for ob in list(bpy.data.objects):
		bpy.data.objects.remove(ob)
	objs = {}
	for name, fn in TREES.items():
		mb = fn()
		print(f"{name}: {mb.tris()} tris")
		objs[name] = mb.emit(name, sharp_deg=60.0)
	kit.export_glb(OUT_GLB, list(objs.values()))
	out = kit.arg("--renders")
	if out:
		cam = kit.setup_preview(ground=120.0, ground_colour=(0.16, 0.2, 0.12))
		for i, ob in enumerate(objs.values()):
			ob.location = ((i - 3.5) * 11.0, 0, 0)
		kit.render(cam, os.path.join(out, "trees.png"), (0, -95, 12), (0, 0, 8), 60)
		kit.render(cam, os.path.join(out, "trees_high.png"), (0, -45, 45), (0, 0, 6), 55)


main()
