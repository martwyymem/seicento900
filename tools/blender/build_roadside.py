"""Low-poly roadside details shared by rally and circuit stages.

Run with Blender from the repository root:
    blender -b -P tools/blender/build_roadside.py -- [--renders DIR]

Writes compact, origin-centred meshes to godot/models/roadside.glb.
"""
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit  # noqa: E402
from kit import MB, srgb  # noqa: E402

OUT_GLB = os.path.join(kit.ROOT, "godot", "models", "roadside.glb")
kit.MATERIALS.update({
	"Wood": ((0.43, 0.25, 0.12), 0.9, 0.0, {}),
	"Leaves": ((0.72, 0.86, 0.63), 0.95, 0.0, {}),
	"Grass": ((0.8, 0.92, 0.67), 0.95, 0.0, {}),
	"Straw": ((0.9, 0.72, 0.34), 0.94, 0.0, {}),
	"Paint": ((0.95, 0.92, 0.84), 0.78, 0.0, {}),
	"Red": ((0.78, 0.12, 0.08), 0.72, 0.0, {}),
	"Concrete": ((0.58, 0.58, 0.53), 0.92, 0.0, {}),
	"Dark": ((0.15, 0.17, 0.16), 0.85, 0.0, {}),
	# field crops and meadow flowers (double sided: cards seen from both sides)
	"Wheat": ((0.82, 0.68, 0.3), 0.95, 0.0, {"double": True}),
	"WheatEar": ((0.88, 0.7, 0.28), 0.9, 0.0, {"double": True}),
	"CornStalk": ((0.36, 0.5, 0.17), 0.9, 0.0, {"double": True}),
	"CornLeaf": ((0.28, 0.5, 0.14), 0.88, 0.0, {"double": True}),
	"CornHusk": ((0.5, 0.58, 0.25), 0.9, 0.0, {}),
	"CornTassel": ((0.78, 0.68, 0.38), 0.9, 0.0, {"double": True}),
	"Stem": ((0.22, 0.42, 0.13), 0.9, 0.0, {"double": True}),
	"Petal": ((1.0, 1.0, 1.0), 0.8, 0.0, {"double": True}),
	"Centre": ((0.9, 0.62, 0.08), 0.8, 0.0, {"double": True}),
	# meadow grass and wheat patches: Godot draws them with shaders/grass.gdshader, which reads the vertex colour as
	# data (R per-blade dryness, G height along the blade, B 1 on wheat ears, A per-blade random), so plain white here
	"Blade": ((1.0, 1.0, 1.0), 0.9, 0.0, {"double": True}),
})


def bush():
	m = MB()
	# Three interlocking, faceted crowns read as one low hedge clump at racing speed.
	for x, y, z, r in [(-0.48, 0.0, 0.62, 0.55), (0.05, 0.08, 0.78, 0.67), (0.54, -0.02, 0.6, 0.53)]:
		icosphere(m, (x, y, z), r, "Leaves", 1)
	return m


def icosphere(m, centre, radius, material, subdivisions=1):
	t = (1.0 + math.sqrt(5.0)) / 2.0
	verts = [(-1,t,0),(1,t,0),(-1,-t,0),(1,-t,0),(0,-1,t),(0,1,t),(0,-1,-t),(0,1,-t),(t,0,-1),(t,0,1),(-t,0,-1),(-t,0,1)]
	verts = [[x / math.sqrt(a*a+b*b+c*c), y / math.sqrt(a*a+b*b+c*c), z / math.sqrt(a*a+b*b+c*c)] for x,y,z in verts for a,b,c in [(x,y,z)]]
	faces = [(0,11,5),(0,5,1),(0,1,7),(0,7,10),(0,10,11),(1,5,9),(5,11,4),(11,10,2),(10,7,6),(7,1,8),(3,9,4),(3,4,2),(3,2,6),(3,6,8),(3,8,9),(4,9,5),(2,4,11),(6,2,10),(8,6,7),(9,8,1)]
	for _ in range(subdivisions):
		cache = {}
		def midpoint(i, j):
			key = tuple(sorted((i, j)))
			if key not in cache:
				v = [verts[i][k] + verts[j][k] for k in range(3)]
				n = math.sqrt(sum(x*x for x in v))
				verts.append([x / n for x in v]); cache[key] = len(verts)-1
			return cache[key]
		new_faces = []
		for a,b,c in faces:
			ab,bc,ca = midpoint(a,b),midpoint(b,c),midpoint(c,a)
			new_faces += [(a,ab,ca),(b,bc,ab),(c,ca,bc),(ab,bc,ca)]
		faces = new_faces
		for f in faces:
			m.poly([(centre[0] + verts[i][0]*radius, centre[1] + verts[i][1]*radius, centre[2] + verts[i][2]*radius) for i in f], material)


def grass():
	m = MB()
	# Nine crossed, tapered blades, all in a tight inexpensive tuft.
	for i in range(9):
		a = i * math.pi * 0.618
		x, y = math.cos(a) * 0.13, math.sin(a) * 0.13
		h = 0.42 + (i % 4) * 0.11
		m.prism([(y-0.025,0),(y+0.025,0),(y+0.015,h*0.55),(y+0.006,h)], x-0.012, x+0.012, "Grass")
	return m


def card(m, pts, mat, cols):
	"""One double-sided polygon with a vertex colour per corner (dark at the root, light at the tip)."""
	m.face([m.vert(p, c) for p, c in zip(pts, cols)], mat)


def blade(m, x, y, h, w, yaw, lean, mat, root_col, tip_col):
	"""A tapered, leaning blade card (3 corners wide at the root, a point at the tip)."""
	ca, sa = math.cos(yaw), math.sin(yaw)
	lx, ly = math.cos(yaw + 1.5708) * lean, math.sin(yaw + 1.5708) * lean
	card(m, [(x - ca * w, y - sa * w, 0.0), (x + ca * w, y + sa * w, 0.0),
		(x + ca * w * 0.55 + lx * 0.5, y + sa * w * 0.55 + ly * 0.5, h * 0.62),
		(x + lx, y + ly, h), (x - ca * w * 0.55 + lx * 0.5, y - sa * w * 0.55 + ly * 0.5, h * 0.62)],
		mat, [root_col, root_col, tip_col, tip_col, tip_col])


def wheat():
	"""A clump of wheat about 1 m high: two crossed leafy cards for body and bearded ears over them."""
	m = MB()
	dark, light = (0.55, 0.5, 0.3), (1.0, 0.95, 0.7)
	for k in range(5):
		a = k * math.pi * 0.4 + 0.2
		blade(m, math.cos(a) * 0.12, math.sin(a) * 0.12, 0.78 + (k % 3) * 0.06, 0.2, a, 0.05, "Wheat", dark, light)
	for k in range(9):
		a = k * math.pi * 0.618
		r = 0.1 + 0.26 * ((k * 5) % 9) / 9.0
		x, y = math.cos(a) * r, math.sin(a) * r
		h = 0.84 + ((k * 7) % 5) * 0.045
		lean = 0.04 + 0.03 * (k % 3)
		# thin stalk, then the ear: a narrow spike of grain
		blade(m, x, y, h - 0.12, 0.012, a, lean, "Wheat", dark, light)
		ex, ey = x + math.cos(a + 1.5708) * lean, y + math.sin(a + 1.5708) * lean
		ca, sa = math.cos(a + 0.9), math.sin(a + 0.9)
		for cx, sx in ((ca, sa), (-sa, ca)):
			card(m, [(ex - cx * 0.03, ey - sx * 0.03, h - 0.14), (ex + cx * 0.03, ey + sx * 0.03, h - 0.14),
				(ex + cx * 0.02, ey + sx * 0.02, h + 0.04), (ex, ey, h + 0.17), (ex - cx * 0.02, ey - sx * 0.02, h + 0.04)],
				"WheatEar", [(0.85, 0.7, 0.35)] * 2 + [(1.0, 0.85, 0.45)] * 3)
	return m


def corn():
	"""Maize: three tall plants (1.9 m) with arching leaves, a tassel on top and a cob on the stalk."""
	m = MB()
	for px, py, ph, pa in [(0.0, 0.0, 1.95, 0.3), (0.32, 0.18, 1.75, 1.9), (-0.25, 0.3, 1.85, 4.0)]:
		# the stalk: two crossed thin cards
		for da in (0.0, 1.5708):
			ca, sa = math.cos(pa + da), math.sin(pa + da)
			card(m, [(px - ca * 0.03, py - sa * 0.03, 0.0), (px + ca * 0.03, py + sa * 0.03, 0.0),
				(px + ca * 0.02, py + sa * 0.02, ph * 0.94), (px - ca * 0.02, py - sa * 0.02, ph * 0.94)],
				"CornStalk", [(0.6, 0.6, 0.5)] * 2 + [(1.0, 1.0, 0.85)] * 2)
		# arching leaves in four directions, three segments each
		for k in range(6):
			a = pa + k * 1.047 + 0.3 * (k % 2)
			z0 = 0.35 + 0.28 * k
			if z0 > ph * 0.9:
				z0 = ph * 0.8
			length = 0.9 - 0.06 * k
			ca, sa = math.cos(a), math.sin(a)
			side = (-sa, ca)
			prev = [(px, py, z0)]
			segs = []
			for s in range(1, 4):
				t = s / 3.0
				reach = length * t
				rise = z0 + length * 0.55 * math.sin(t * 1.5) - length * 0.35 * t * t
				w = 0.085 * math.sin(math.pi * (0.2 + 0.8 * t) * 0.9) + 0.01
				segs.append((px + ca * reach, py + sa * reach, rise, w))
			ring = [(px, py, z0, 0.012)] + segs
			for i in range(len(ring) - 1):
				x0, y0, z0_, w0 = ring[i]
				x1, y1, z1, w1 = ring[i + 1]
				c0 = (0.55, 0.62, 0.4) if i == 0 else (0.85, 0.95, 0.65)
				c1 = (0.85, 0.95, 0.65) if i < 2 else (1.0, 1.0, 0.8)
				card(m, [(x0 - side[0] * w0, y0 - side[1] * w0, z0_), (x0 + side[0] * w0, y0 + side[1] * w0, z0_),
					(x1 + side[0] * w1, y1 + side[1] * w1, z1), (x1 - side[0] * w1, y1 - side[1] * w1, z1)],
					"CornLeaf", [c0, c0, c1, c1])
		# the cob, wrapped in husk, on the side of the stalk
		cx, cy = px + math.cos(pa + 0.8) * 0.07, py + math.sin(pa + 0.8) * 0.07
		m.box((cx - 0.035, cy - 0.035, ph * 0.52), (cx + 0.035, cy + 0.035, ph * 0.52 + 0.24), "CornHusk")
		# the tassel: thin pale spikes fanning from the top
		for k in range(5):
			a = pa + k * 1.2566
			ca, sa = math.cos(a), math.sin(a)
			tx, ty = px + ca * 0.2, py + sa * 0.2
			card(m, [(px - sa * 0.012, py + ca * 0.012, ph * 0.9), (px + sa * 0.012, py - ca * 0.012, ph * 0.9),
				(tx, ty, ph + 0.12)], "CornTassel", [(0.8, 0.75, 0.5)] * 2 + [(1.0, 0.9, 0.6)])
	return m


def _rand(k, salt):
	"""A repeatable 0..1 hash of an integer, so the patches come out the same on every build."""
	v = math.sin(k * 12.9898 + salt * 78.233) * 43758.5453
	return v - math.floor(v)


def curved_blade(m, x, y, h, w, yaw, lean, dry, rnd, segs=(0.0, 0.4, 0.75)):
	"""A tapered blade bending away along `yaw`: a quad strip up to a point, 5 triangles. Vertex colour carries
	(dryness, height fraction, 0, random) for grass.gdshader."""
	ca, sa = math.cos(yaw), math.sin(yaw)
	px, py = -sa, ca  # the blade's width runs across its bend
	rows = []
	for t in segs:
		off = lean * h * t * t
		z = h * t * (1.0 - 0.18 * lean * t)
		half = w * (1.0 - t) ** 0.8
		cx, cy = x + ca * off, y + sa * off
		rows.append((m.vert((cx - px * half, cy - py * half, z), (dry, t, 0.0, rnd)),
			m.vert((cx + px * half, cy + py * half, z), (dry, t, 0.0, rnd))))
	off = lean * h
	tip = m.vert((x + ca * off, y + sa * off, h * (1.0 - 0.18 * lean)), (dry, 1.0, 0.0, rnd))
	for (a0, b0), (a1, b1) in zip(rows, rows[1:]):
		m.face([a0, b0, b1, a1], "Blade")
	m.face([rows[-1][0], rows[-1][1], tip], "Blade")


def grass_patch(blades, width_mul=1.0, salt=1.0):
	"""About 1.6 m across of meadow grass: `blades` curved blades 0.3-1.0 m high leaning every way."""
	m = MB()
	for k in range(blades):
		r = 0.8 * math.sqrt(_rand(k, salt))
		a = k * 2.39996 + _rand(k, salt + 1) * 0.6
		x, y = math.cos(a) * r, math.sin(a) * r
		tall = _rand(k, salt + 2)
		h = 0.3 + 0.7 * tall ** 0.7
		w = (0.022 + 0.022 * _rand(k, salt + 3)) * width_mul
		curved_blade(m, x, y, h, w, _rand(k, salt + 4) * math.tau, 0.15 + 0.45 * _rand(k, salt + 5),
			1.0 if _rand(k, salt + 6) < 0.18 else 0.25 * _rand(k, salt + 7), _rand(k, salt + 8))
	return m


def wheat_patch(stalks, width_mul=1.0, salt=7.0):
	"""About 1.6 m across of ripe wheat: upright stalks about 0.9 m with a leaf each and a grain ear on top (B = 1)."""
	m = MB()
	for k in range(stalks):
		r = 0.8 * math.sqrt(_rand(k, salt))
		a = k * 2.39996
		x, y = math.cos(a) * r, math.sin(a) * r
		h = 0.78 + 0.2 * _rand(k, salt + 2)
		yaw = _rand(k, salt + 4) * math.tau
		lean = 0.04 + 0.08 * _rand(k, salt + 5)
		rnd = _rand(k, salt + 8)
		curved_blade(m, x, y, h, 0.012 * width_mul, yaw, lean, 0.6, rnd)
		if k % 3 == 0:  # a drooping leaf half way up
			curved_blade(m, x, y, h * 0.55, 0.02 * width_mul, yaw + 1.6, 0.6, 0.4, rnd)
		# the ear: a narrow spindle, two crossed cards
		ca, sa = math.cos(yaw), math.sin(yaw)
		ex, ey = x + ca * lean * h, y + sa * lean * h
		top = h * (1.0 - 0.18 * lean)
		for da in ((0.0, 1.5708) if width_mul > 1.0 else (0.8,)):
			cx, cy = math.cos(yaw + da), math.sin(yaw + da)
			ear = 0.017 * width_mul
			ids = [m.vert(p, (0.8, f, 1.0, rnd)) for p, f in [((ex - cx * ear, ey - cy * ear, top - 0.11), 0.85),
				((ex + cx * ear, ey + cy * ear, top - 0.11), 0.85), ((ex + cx * ear * 0.8, ey + cy * ear * 0.8, top + 0.02), 0.95),
				((ex + ca * 0.02, ey + sa * 0.02, top + 0.08), 1.0), ((ex - cx * ear * 0.8, ey - cy * ear * 0.8, top + 0.02), 0.95)]]
			m.face(ids, "Blade")
	return m


def flower():
	"""A small meadow flower (0.45 m): a stem, two leaves and a daisy-like head in a white 'Petal' material
	that the MultiMesh instance colour turns red, yellow, violet or white."""
	m = MB()
	m.tube((0, 0, 0), (0.02, 0.01, 0.34), 0.012, "Stem", 4, True)
	for a in (0.5, 3.6):
		blade(m, 0.0, 0.0, 0.2, 0.035, a, 0.12, "Stem", (0.5, 0.55, 0.4), (1.0, 1.0, 0.8))
	cx, cy, cz = 0.02, 0.01, 0.34
	for k in range(7):
		a = k * 2 * math.pi / 7
		ca, sa = math.cos(a), math.sin(a)
		card(m, [(cx, cy, cz), (cx + ca * 0.1 - sa * 0.035, cy + sa * 0.1 + ca * 0.035, cz + 0.045),
			(cx + ca * 0.1 + sa * 0.035, cy + sa * 0.1 - ca * 0.035, cz + 0.045)], "Petal", [(1.0, 1.0, 1.0)] * 3)
	for k in range(7):  # a second ring so the head is not a flat star from above
		a = (k + 0.5) * 2 * math.pi / 7
		ca, sa = math.cos(a), math.sin(a)
		card(m, [(cx, cy, cz + 0.01), (cx + ca * 0.08 - sa * 0.03, cy + sa * 0.08 + ca * 0.03, cz + 0.07),
			(cx + ca * 0.08 + sa * 0.03, cy + sa * 0.08 - ca * 0.03, cz + 0.07)], "Petal", [(0.85, 0.85, 0.85)] * 3)
	m.disc((cx, cy, cz + 0.035), 0.035, "Centre", segs=6)
	return m


def hay_bale():
	m = MB()
	m.lathe([(0.0,0.42),(0.07,0.5),(0.75,0.5),(0.82,0.42)], 10, "Straw")
	# Dark ties on the face distinguish a tied round bale without texturing.
	for angle in (0.8, 2.9, 5.0):
		x, y = math.cos(angle) * 0.505, math.sin(angle) * 0.505
		m.box((x-0.018,y-0.018,0.08),(x+0.018,y+0.018,0.74),"Wood")
	return m


def roadside_cross():
	m = MB()
	m.box((-0.055,-0.055,0.0),(0.055,0.055,1.65),"Wood")
	m.box((-0.38,-0.055,1.22),(0.38,0.055,1.34),"Wood")
	# Small pale cap and stone plinth, a simple Polish wayside cross silhouette.
	m.box((-0.11,-0.1,1.59),(0.11,0.1,1.76),"Paint")
	m.box((-0.24,-0.2,0.0),(0.24,0.2,0.16),"Concrete")
	return m


def kilometre_post():
	m = MB()
	m.box((-0.12,-0.1,0.0),(0.12,0.1,0.8),"Paint")
	m.box((-0.125,-0.105,0.53),(0.125,0.105,0.67),"Red")
	m.box((-0.126,-0.106,0.2),(0.126,0.106,0.27),"Red")
	return m


def rally_board():
	m = MB()
	for x in (-0.62, 0.62):
		m.box((x-0.035,-0.035,0.0),(x+0.035,0.035,1.7),"Wood")
	m.box((-0.7,-0.07,0.95),(0.7,0.07,1.55),"Paint")
	# Broad red bands make the gate visible at distance; deliberately no generated lettering.
	m.box((-0.7,-0.075,0.95),(-0.42,0.075,1.55),"Red")
	m.box((0.42,-0.075,0.95),(0.7,0.075,1.55),"Red")
	return m


def main():
	bpy.ops.object.select_all(action="SELECT")
	bpy.ops.object.delete(use_global=False)
	objects = []
	for name, builder in [("BushCluster", bush), ("TallGrass", grass), ("Wheat", wheat), ("Corn", corn),
		("Flower", flower), ("GrassPatch", lambda: grass_patch(110)), ("GrassPatchLow", lambda: grass_patch(30, 2.2, 3.0)),
		("WheatPatch", lambda: wheat_patch(60)), ("WheatPatchLow", lambda: wheat_patch(22, 2.0, 9.0)), ("HayBale", hay_bale),
		("WaysideCross", roadside_cross), ("KilometrePost", kilometre_post), ("RallyBoard", rally_board)]:
		objects.append(builder().emit(name))
	kit.export_glb(OUT_GLB, objects)
	render_dir = kit.arg("--renders")
	if render_dir:
		cam = kit.setup_preview(ground=30.0)
		# A lineup makes silhouettes and relative scale easy to inspect.
		for i, ob in enumerate(objects):
			kit.place(ob, ((i - 6) * 2.4, 0.0, 0.0))
		kit.render(cam, os.path.join(render_dir, "roadside.png"), (9, -14, 6), (0, 0, 0.8), 55.0)


if __name__ == "__main__":
	main()
