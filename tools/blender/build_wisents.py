"""Low-poly European bison (żubr) and their paddock, for Pszczyna's Pokazowa Zagroda Żubrów (the wisent show
enclosure beside ul. Żorska, seen from the Pszczyna Castle Park street stage).

Run with Blender from the repository root:
    blender -b -P tools/blender/build_wisents.py -- [--renders DIR]

Writes godot/models/wisents.glb. surroundings.gd loads it next to landmarks.glb and finds the pieces by object
name, so keep these stable: WisentBull, WisentCow (grazing, head down), WisentCowLying, WisentCalf,
PaddockFence (one 6 m bay of a three-rail fence, along x), HayRack (a roofed wooden feeding rack). The animals
stand along x with the head at +x, so their flank faces +y in Blender (Godot's +z, which the landmark code turns
to the road). Materials: Fur, FurDark (the shaggy forequarters, mane and beard), FurCalf, Horn, Hoof, Wood, Hay,
Roof.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit  # noqa: E402
from kit import MB, srgb  # noqa: E402

OUT_GLB = os.path.join(kit.ROOT, "godot", "models", "wisents.glb")
kit.MATERIALS.update({
	"Fur": (srgb("#6e4c31"), 0.97, 0.0, {}),
	"FurDark": (srgb("#3b281a"), 0.98, 0.0, {}),
	"FurCalf": (srgb("#9a7046"), 0.97, 0.0, {}),
	"Horn": (srgb("#2a2622"), 0.6, 0.0, {}),
	"Hoof": (srgb("#1d1a17"), 0.7, 0.0, {}),
	"Wood": (srgb("#7a5a3a"), 0.9, 0.0, {}),
	"Hay": (srgb("#c9a95c"), 0.95, 0.0, {}),
	"Roof": (srgb("#4d3a2c"), 0.9, 0.0, {}),
})

RING = 10  # points round each body section


def ring(x, cy, cz, hw, hh, top=1.0, s=1.0, pitch=0.0):
	"""A rounded section in the y-z plane at x: half width hw, half height hh round (cy, cz); `top` squares the
	back (a bison's flat-topped hump), `pitch` tilts the section (radians, for the head)."""
	pts = []
	for k in range(RING):
		a = 2 * math.pi * k / RING
		c, sn = math.cos(a), math.sin(a)
		y = hw * math.copysign(abs(c) ** 0.8, c)
		e = 0.8 if sn < 0 else 0.8 / top
		z = hh * math.copysign(abs(sn) ** e, sn)
		dx = -z * math.sin(pitch)
		dz = z * math.cos(pitch)
		pts.append(Vector(((x + dx) * s, (cy + y) * s, (cz + dz) * s)))
	return pts


def loft(m, rings, mat, cap0=True, cap1=True, shade=True):
	"""Quads between consecutive rings (each RING points, closed); a darker belly via the vertex colour."""
	ids = []
	for r in rings:
		cz = sum(p.z for p in r) / len(r)
		row = []
		for p in r:
			k = 0.72 if (shade and p.z < cz) else 1.0
			row.append(m.vert(p, (k, k, k)))
		ids.append(row)
	cents = [sum(r, Vector()) / len(r) for r in rings]
	for i in range(len(rings) - 1):
		axis = (cents[i + 1] - cents[i]).normalized()
		mid = (cents[i] + cents[i + 1]) / 2
		for j in range(RING):
			j2 = (j + 1) % RING

			def out(q, mid=mid, axis=axis):
				d = q - mid
				return d - axis * d.dot(axis)
			m.face([ids[i][j], ids[i][j2], ids[i + 1][j2], ids[i + 1][j]], mat, out)
	if cap0:
		m.face(ids[0], mat, cents[0] - cents[1])
	if cap1:
		m.face(ids[-1], mat, cents[-1] - cents[-2])


def leg(m, x, y, top, s, mat_upper, shaggy=False, bend=0.0):
	"""A tapered four-sided leg from z=top to the ground with a dark hoof; `bend` (m) sets the hoof forward."""
	def sq(cx, cz, w):
		return [Vector(((cx + dx) * s, (y + dy) * s, cz * s)) for dx, dy in ((-w, -w), (w, -w), (w, w), (-w, w))]
	w0 = 0.17 if shaggy else 0.13
	rows = [sq(x, top, w0), sq(x + bend * 0.5, top * 0.45, 0.085), sq(x + bend, 0.1, 0.07)]
	ids = [[m.vert(p, (0.85, 0.85, 0.85)) for p in r] for r in rows]
	for i in range(2):
		c = (sum(rows[i], Vector()) + sum(rows[i + 1], Vector())) / 8
		for j in range(4):
			j2 = (j + 1) % 4
			m.face([ids[i][j], ids[i][j2], ids[i + 1][j2], ids[i + 1][j]], mat_upper,
				lambda q, c=c: Vector((q.x - c.x, q.y - c.y, 0.0)))
	m.box(((x + bend - 0.08) * s, (y - 0.08) * s, 0.0), ((x + bend + 0.08) * s, (y + 0.08) * s, 0.11 * s), "Hoof")


def horns(m, hx, hz, s, size=1.0, pitch=0.0):
	"""Short horns curving out and up from the poll at (hx, hz)."""
	for side in (-1, 1):
		a = Vector((hx * s, side * 0.2 * s, hz * s))
		b = Vector(((hx + 0.02) * s, side * 0.36 * size * s, (hz + 0.06 * size) * s))
		c = Vector(((hx + 0.1) * s, side * 0.4 * size * s, (hz + 0.15 * size) * s))
		m.tube(a, b, 0.05 * s, "Horn", segs=5)
		m.tube(b, c, 0.032 * s, "Horn", segs=5)


def bison(s=1.0, head="up", lying=False, calf=False):
	"""A wisent ~2.9 m long and ~1.85 m at the shoulder at s=1: the high, flat-topped hump and shaggy dark
	forequarters, slim hindquarters, the head carried low with a beard. head: 'up' (alert, muzzle level with the
	knees) or 'graze' (muzzle on the grass). lying: legs folded, the body on the ground."""
	m = MB()
	fur = "FurCalf" if calf else "Fur"
	dark = "FurCalf" if calf else "FurDark"
	drop = 0.78 if lying else 0.0  # the whole body lowered onto the ground
	z = lambda v: v - drop
	# hindquarters to the waist (slim, lighter coat)
	back = [
		ring(-1.48, 0, z(1.36), 0.12, 0.14, s=s),
		ring(-1.38, 0, z(1.12), 0.32, 0.36, s=s),
		ring(-1.05, 0, z(1.1), 0.42, 0.42, top=1.3, s=s),
		ring(-0.55, 0, z(1.1), 0.46, 0.44, top=1.3, s=s),
		ring(-0.05, 0, z(1.22), 0.53, 0.53, top=1.4, s=s),
	]
	loft(m, back, fur, cap1=False)
	# forequarters: the hump (top ~1.95 m) and chest, in the darker shaggy coat
	front = [
		ring(-0.1, 0, z(1.21), 0.53, 0.52, top=1.4, s=s),
		ring(0.3, 0, z(1.32), 0.6, 0.7, top=1.8, s=s),
		ring(0.6, 0, z(1.34), 0.6, 0.72, top=1.8, s=s),
		ring(0.88, 0, z(1.18), 0.5, 0.6, top=1.4, s=s),
		ring(1.05, 0, z(1.02), 0.38, 0.48, s=s),
	]
	loft(m, front, dark, cap0=False, cap1=False)
	# the head: short, broad and carried low; grazing, it reaches the ground
	if head == "graze":
		hz = [z(0.92), z(0.6), z(0.3), z(0.12) + drop * 0.85]
		hx = [1.12, 1.3, 1.42, 1.48]
		pit = [0.5, 0.9, 1.1, 1.2]
	else:
		hz = [z(0.98), z(0.86), z(0.7), z(0.6)]
		hx = [1.12, 1.36, 1.56, 1.66]
		pit = [0.3, 0.45, 0.6, 0.6]
	head_rings = [ring(hx[0], 0, hz[0], 0.36, 0.42, s=s, pitch=pit[0]),
		ring(hx[1], 0, hz[1], 0.33, 0.36, s=s, pitch=pit[1]),
		ring(hx[2], 0, hz[2], 0.25, 0.26, s=s, pitch=pit[2]),
		ring(hx[3], 0, hz[3], 0.19, 0.16, s=s, pitch=pit[3])]
	loft(m, head_rings, dark, cap0=False, shade=False)
	# beard and the mane hanging under the neck
	bx = hx[1] - 0.05
	bz = hz[1] - 0.25
	m.poly([Vector(((bx - 0.35) * s, -0.12 * s, (z(0.95)) * s)), Vector(((bx + 0.08) * s, -0.1 * s, (hz[1] - 0.1) * s)),
		Vector(((bx + 0.0) * s, 0.0, bz * s)), Vector(((bx - 0.3) * s, 0.0, (z(0.72)) * s))], dark, (0, -1, 0))
	m.poly([Vector(((bx - 0.35) * s, 0.12 * s, (z(0.95)) * s)), Vector(((bx + 0.08) * s, 0.1 * s, (hz[1] - 0.1) * s)),
		Vector(((bx + 0.0) * s, 0.0, bz * s)), Vector(((bx - 0.3) * s, 0.0, (z(0.72)) * s))], dark, (0, 1, 0))
	# ears and horns at the poll
	px, pz = hx[0] + 0.08, hz[0] + 0.3
	for side in (-1, 1):
		m.poly([Vector((px * s, side * 0.26 * s, (pz - 0.05) * s)), Vector(((px - 0.08) * s, side * 0.42 * s, (pz - 0.1) * s)),
			Vector(((px + 0.04) * s, side * 0.4 * s, (pz - 0.16) * s))], dark, (0, side, 0.3))
	if not calf:
		horns(m, px, pz, s, 1.0)
	# legs: shaggy forelegs, slim hind ones; folded under the body when lying
	if lying:
		for x, y in ((0.55, -0.42), (0.55, 0.42)):
			m.beam(Vector((x * s, y * s, 0.12 * s)), Vector(((x + 0.55) * s, y * s, 0.1 * s)), 0.16 * s, 0.16 * s, dark)
			m.box(((x + 0.5) * s, (y - 0.07) * s, 0.02 * s), ((x + 0.64) * s, (y + 0.07) * s, 0.16 * s), "Hoof")
		for x, y in ((-1.0, -0.45), (-1.0, 0.45)):
			m.beam(Vector((x * s, y * s, 0.15 * s)), Vector(((x + 0.6) * s, (y * 1.15) * s, 0.1 * s)), 0.18 * s, 0.18 * s, fur)
			m.box(((x + 0.55) * s, (y * 1.15 - 0.07) * s, 0.02 * s), ((x + 0.69) * s, (y * 1.15 + 0.07) * s, 0.15 * s), "Hoof")
	else:
		for y in (-0.26, 0.26):
			leg(m, 0.62, y, z(0.85), s, dark, shaggy=True, bend=0.04)
			leg(m, -1.02, y, z(0.95), s, fur, bend=-0.06)
	# the tail with its tuft
	tz = z(1.34)
	tail_end = Vector((-1.62 * s, 0.0, (tz - 0.62 if not lying else max(0.08, tz - 0.62)) * s))
	m.tube(Vector((-1.47 * s, 0, tz * s)), tail_end, 0.035 * s, fur, segs=5)
	m.tube(tail_end, tail_end + Vector((0.0, 0.0, -0.18 * s)), 0.07 * s, dark, segs=5)
	return m


def bull():
	return bison(1.0, "up")


def cow():
	return bison(0.86, "graze")


def cow_lying():
	return bison(0.86, "up", lying=True)


def calf():
	return bison(0.5, "up", calf=True)


def paddock_fence():
	"""One 6 m bay of the enclosure fence: three rough rails on stout posts (heavy, a bison fence), along x
	from -3 to 3 (centred, so the game may turn it end for end); the next bay's first post is this one's last."""
	m = MB()
	for x in (-3.0, 0.0, 3.0):
		m.box((x - 0.1, -0.1, 0.0), (x + 0.1, 0.1, 1.85), "Wood")
		m.poly([(x - 0.1, -0.1, 1.85), (x + 0.1, -0.1, 1.85), (x, 0.0, 1.95)], "Wood", (0, -1, 1))
		m.poly([(x + 0.1, 0.1, 1.85), (x - 0.1, 0.1, 1.85), (x, 0.0, 1.95)], "Wood", (0, 1, 1))
	for zr in (0.45, 0.95, 1.45):
		m.beam(Vector((-3.0, -0.14, zr)), Vector((3.0, -0.14, zr + 0.03)), 0.09, 0.16, "Wood")
	return m


def hay_rack():
	"""A wooden paśnik: a V-shaped slatted hay crib on legs under a gabled roof, 3 m long."""
	m = MB()
	L, W = 3.0, 1.6
	for x in (-L / 2, L / 2):
		for y in (-W / 2, W / 2):
			m.box((x - 0.07, y - 0.07, 0.0), (x + 0.07, y + 0.07, 2.1), "Wood")
	# the crib: slats sloping in to a trough
	for x in [(-L / 2 + 0.15) + k * 0.3 for k in range(10)]:
		for side in (-1, 1):
			m.beam(Vector((x, side * 0.12, 0.6)), Vector((x, side * 0.62, 1.45)), 0.05, 0.05, "Wood")
	m.box((-L / 2, -0.25, 0.45), (L / 2, 0.25, 0.62), "Wood")
	m.prism([(-0.5, 1.4), (-0.1, 0.65), (0.1, 0.65), (0.5, 1.4), (0.3, 1.62), (-0.3, 1.62)], -L / 2 + 0.05,
		L / 2 - 0.05, "Hay")
	# gabled roof
	for side in (-1, 1):
		m.poly([(-L / 2 - 0.25, side * (W / 2 + 0.3), 2.0), (L / 2 + 0.25, side * (W / 2 + 0.3), 2.0),
			(L / 2 + 0.25, 0.0, 2.55), (-L / 2 - 0.25, 0.0, 2.55)], "Roof", (0, side, 1))
		m.poly([(-L / 2 - 0.25, side * (W / 2 + 0.3), 1.97), (L / 2 + 0.25, side * (W / 2 + 0.3), 1.97),
			(L / 2 + 0.25, 0.0, 2.52), (-L / 2 - 0.25, 0.0, 2.52)], "Roof", (0, -side, -1))
	for x in (-L / 2, L / 2):
		m.poly([(x, -W / 2, 2.0), (x, W / 2, 2.0), (x, 0.0, 2.5)], "Wood", (math.copysign(1, x), 0, 0))
	# a little hay spilt round it
	for x, y in ((-0.9, 0.9), (0.4, -1.0), (1.1, 0.8)):
		m.poly([(x - 0.4, y - 0.25, 0.03), (x + 0.4, y - 0.2, 0.03), (x + 0.3, y + 0.25, 0.03), (x - 0.35, y + 0.2, 0.03)],
			"Hay", (0, 0, 1))
	return m


PIECES = [("WisentBull", bull), ("WisentCow", cow), ("WisentCowLying", cow_lying), ("WisentCalf", calf),
	("PaddockFence", paddock_fence), ("HayRack", hay_rack)]


def main():
	bpy.ops.object.select_all(action="SELECT")
	bpy.ops.object.delete(use_global=False)
	objects = []
	for name, builder in PIECES:
		m = builder()
		ob = m.emit(name)
		print(name, m.tris(), "tris")
		objects.append(ob)
	kit.export_glb(OUT_GLB, objects)
	render_dir = kit.arg("--renders")
	if render_dir:
		cam = kit.setup_preview(ground=60.0, ground_colour=(0.25, 0.32, 0.16))
		at = {"WisentBull": (0.0, 0.0, 0.0), "WisentCow": (3.6, 2.2, 0.0), "WisentCowLying": (-3.8, 1.6, 0.0),
			"WisentCalf": (1.2, -2.0, 0.0), "HayRack": (-1.0, 5.5, 0.0), "PaddockFence": (-5.0, -4.5, 0.0)}
		rots = {"WisentCow": 0.5, "WisentCowLying": -0.3, "WisentCalf": 0.8}
		for ob in objects:
			ob.hide_render = True  # (the exported originals all stand at the origin)
			kit.place(ob, at[ob.name], rots.get(ob.name, 0.0))
			if ob.name == "PaddockFence":
				kit.place(ob, (1.0, -4.5, 0.0))
				kit.place(ob, (7.0, -4.5, 0.0))
		kit.render(cam, os.path.join(render_dir, "wisents_herd.png"), (6, -14, 4.5), (0, 1, 0.9), 50.0)
		kit.render(cam, os.path.join(render_dir, "wisents_side.png"), (0.3, -6.5, 1.3), (0.3, 0, 1.0), 45.0)
		kit.render(cam, os.path.join(render_dir, "wisents_front.png"), (6.5, -3.0, 1.6), (0, 0, 1.0), 45.0)


if __name__ == "__main__":
	main()
