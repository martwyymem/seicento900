"""Builds the prop kit for the Brzeszcze free-roam map: the KWK Brzeszcze shaft headframe, a neo-Gothic church
tower, street furniture, festival-hub pieces, ambient traffic cars and the event beacon. Low-poly, chunky and
readable (Forza Horizon / The Crew style), flat named materials, no image textures.

Run from the repository root (Blender 4.2 or newer, headless):

    /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/blender/build_town.py -- [--renders DIR]

Writes godot/models/town.glb. With --renders it also saves preview PNGs to DIR.

Conventions (Godot finds the meshes by object name and the surfaces by material name; keep both stable):
  * One root-level object per prop, named exactly as below. Transforms are applied (identity), units are metres.
  * Origin on the ground (lowest point at y = 0 in Godot) and centred in plan on the prop's bounding box,
    except: the single-pole props Streetlamp, StreetlampPark, TrafficLight and FlagPole (origin at the foot of
    the pole; the lamp arm / signal head reach towards front, the flag streams towards +X), Fence (origin at
    the post at its left end, the panel runs along +X to x = 2.5 so pieces chain) and LevelCrossing (origin
    at the foot of the barrier post, the 6 m boom runs along +X, the cross sign stands 1 m to -X).
  * FRONT faces Godot -Z, which is Blender +Y (the glTF exporter maps Blender +Y to Godot -Z, as in
    kit.py and build_seicento.py, whose car noses point +Y). So: car noses, the streetlamp arm, the signal
    head, the billboard face, the open side of the bus shelter, the bench seat, the stage audience side, the
    church portal and the headframe's shaft side all point to Godot -Z. Godot +X is the prop's right when
    viewed from behind (Blender +X unchanged).
  * Vertex colours are all white (kit.MB writes a COLOR_0 multiplied into the base colour); the colours come
    from the flat materials only.

Materials (names Godot looks for):
  Paint      car body paint, white base so Godot tints it per car
  Glass      dark glazing (cars, shelter, windows, LED screen)
  Headlight  car head lamps (faint emission)      Taillight  car rear lamps (red, faint emission)
  Lamp       emissive lamp heads / lanterns / the Beacon column (double-sided; Godot drives emission, tint
             and, for the beacon, transparency)
  Steel      galvanised / grey steel (poles, trusses, sheet roofs)
  SteelPaint green-painted steel (headframe lattice, mesh fence)
  Concrete   concrete and light stone trim          Brick   red brick
  Trim       dark plastic / black metal / fabric    Rubber  tyres, speaker cones
  Banner     festival fabric and print faces, white base so Godot tints it (double-sided)
  Wood       timber (bench slats, stage deck, church door)
  Copper     verdigris spire and pinnacle roofs     Sign    white sign faces, plates, lettering
  Red        red paint (sheave wheels, crossing boom stripes)
  SignalRed / SignalAmber / SignalGreen  traffic and crossing signal lenses (faint emission)

Props: Headframe, ChurchSpire, Streetlamp, StreetlampPark, TrafficLight, BusShelter, Billboard, FestivalArch,
FestivalStage, FlagPole, Tent, CarHatch, CarSedan, CarVan, Maluch, Bench, Fence, LevelCrossing, LevelCrossingBoom,
Beacon, TrainCab, TrainCar (a PKP EN57 unit: cab + car + reversed cab, origin at the rail top).
The script prints each prop's bounding box (Godot axes) and triangle count.
"""
import bpy
import math
import os
import sys
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit  # noqa: E402
from kit import MB, srgb  # noqa: E402

OUT_GLB = os.path.join(kit.ROOT, "godot", "models", "town.glb")

kit.MATERIALS.update({
	"Paint": (srgb("#ffffff"), 0.35, 0.1, {}),
	"Glass": (srgb("#1c2731"), 0.08, 0.4, {}),
	"Headlight": (srgb("#e6edf2"), 0.1, 0.2, {"emit": ((1.0, 0.95, 0.85), 0.3)}),
	"Taillight": (srgb("#9a0c0c"), 0.15, 0.0, {"emit": ((1.0, 0.05, 0.03), 0.3)}),
	"Lamp": (srgb("#fff1d0"), 0.4, 0.0, {"emit": ((1.0, 0.86, 0.6), 3.0), "double": True}),
	"Steel": (srgb("#a1a8ad"), 0.45, 0.5, {}),
	"SteelPaint": (srgb("#3f6b52"), 0.6, 0.25, {}),
	"Concrete": (srgb("#c4beb2"), 0.9, 0.0, {}),
	"Brick": (srgb("#9c4630"), 0.85, 0.0, {}),
	"Trim": (srgb("#25282b"), 0.6, 0.0, {}),
	"Rubber": (srgb("#161616"), 0.9, 0.0, {}),
	"Banner": (srgb("#ffffff"), 0.6, 0.0, {"double": True}),
	"Wood": (srgb("#8a5a34"), 0.75, 0.0, {}),
	"Copper": (srgb("#5d9e87"), 0.55, 0.3, {}),
	"Sign": (srgb("#f2f2ee"), 0.5, 0.0, {}),
	"Red": (srgb("#c4161c"), 0.5, 0.0, {}),
	"SignalRed": (srgb("#d01010"), 0.2, 0.0, {"emit": ((1.0, 0.08, 0.05), 0.6)}),
	"SignalAmber": (srgb("#e09010"), 0.2, 0.0, {"emit": ((1.0, 0.6, 0.05), 0.6)}),
	"SignalGreen": (srgb("#10b050"), 0.2, 0.0, {"emit": ((0.1, 1.0, 0.4), 0.6)}),
	"TrainCream": (srgb("#e8dcb4"), 0.45, 0.1, {}),
	"TrainBlue": (srgb("#1f3f78"), 0.45, 0.1, {}),
})

UP = Vector((0, 0, 1))


# ---------------------------------------------------------------- helpers
def cube(mb, a, b, mat, skip=()):
	"""Axis-aligned box between two corners given in any order."""
	mb.box(tuple(min(p, q) for p, q in zip(a, b)), tuple(max(p, q) for p, q in zip(a, b)), mat, skip=skip)


def bar(mb, a, b, w, mat, h=None, up=(0, 0, 1)):
	"""Rectangular bar from a to b without end caps (8 tris)."""
	a, b = Vector(a), Vector(b)
	h = h or w
	axis = (b - a).normalized()
	side = axis.cross(Vector(up))
	if side.length < 1e-4:
		side = axis.cross(Vector((1, 0, 0)))
	side.normalize()
	upv = side.cross(axis)
	cs = [side * sx * w / 2 + upv * sz * h / 2 for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
	ra = [mb.vert(a + c) for c in cs]
	rb = [mb.vert(b + c) for c in cs]
	mid = (a + b) / 2
	for k in range(4):
		k2 = (k + 1) % 4
		mb.face([ra[k], ra[k2], rb[k2], rb[k]], mat, lambda q: (q - mid) - axis * (q - mid).dot(axis))


def truss(mb, a, b, size, mat, chord=0.06, web=0.035, up=(0, 0, 1), panel=None):
	"""Square box truss from a to b: four chords and a zig-zag web on each face."""
	a, b = Vector(a), Vector(b)
	L = (b - a).length
	axis = (b - a) / L
	side = axis.cross(Vector(up))
	if side.length < 1e-4:
		side = axis.cross(Vector((1, 0, 0)))
	side.normalize()
	upv = side.cross(axis)
	h = size / 2
	corners = [side * -h + upv * -h, side * h + upv * -h, side * h + upv * h, side * -h + upv * h]
	for c in corners:
		bar(mb, a + c, b + c, chord, mat, up=upv)
	n = max(1, round(L / (panel or size * 1.4)))
	for f in range(4):
		c0, c1 = corners[f], corners[(f + 1) % 4]
		for k in range(n):
			p0, p1 = a + axis * L * k / n, a + axis * L * (k + 1) / n
			if (k + f) % 2 == 0:
				bar(mb, p0 + c0, p1 + c1, web, mat)
			else:
				bar(mb, p0 + c1, p1 + c0, web, mat)


def lathe_p(mb, profile, segs, mat, centre=(0, 0, 0), phase=0.0):
	"""kit.MB.lathe with an angular phase (radians) so polygonal lathes can be turned square to the axes."""
	c = Vector(centre)
	rows = [[c + Vector((r * math.cos(phase + 2 * math.pi * k / segs), r * math.sin(phase + 2 * math.pi * k / segs), z))
		for k in range(segs)] for z, r in profile]
	ids = [[mb.vert(p) for p in row] for row in rows]
	for i in range(len(rows) - 1):
		dz = profile[i + 1][0] - profile[i][0]
		dr = profile[i + 1][1] - profile[i][1]
		for k in range(segs):
			k2 = (k + 1) % segs

			def out(q, dz=dz, dr=dr):
				radial = Vector((q.x - c.x, q.y - c.y, 0.0))
				radial = radial.normalized() if radial.length > 1e-9 else Vector((1, 0, 0))
				return radial * dz + Vector((0, 0, -dr))
			mb.face([ids[i][k], ids[i][k2], ids[i + 1][k2], ids[i + 1][k]], mat, out)
	return ids


def ring(mb, centre, axis, r_out, r_in, width, mat, segs=24):
	"""A flat-sided wheel rim (annulus extruded along axis)."""
	c, ax = Vector(centre), Vector(axis).normalized()
	helper = Vector((0, 0, 1)) if abs(ax.z) < 0.9 else Vector((1, 0, 0))
	u = ax.cross(helper).normalized()
	v = ax.cross(u)
	dirs = [u * math.cos(2 * math.pi * k / segs) + v * math.sin(2 * math.pi * k / segs) for k in range(segs)]
	loops = [[c + d * r + ax * o for d in dirs] for r, o in
		((r_out, width / 2), (r_out, -width / 2), (r_in, -width / 2), (r_in, width / 2))]
	ids = [[mb.vert(p) for p in lp] for lp in loops]
	for li in range(4):
		l2 = (li + 1) % 4
		for k in range(segs):
			k2 = (k + 1) % segs

			def out(q, li=li):
				radial = (q - c) - ax * (q - c).dot(ax)
				return [radial, -ax, -radial, ax][li]
			mb.face([ids[li][k], ids[li][k2], ids[l2][k2], ids[l2][k]], mat, out)


def tri_prism(mb, pts2, y0, y1, mat):
	"""Extrude a convex (x, z) polygon along Y from y0 to y1, capped."""
	r0 = [mb.vert((x, y0, z)) for x, z in pts2]
	r1 = [mb.vert((x, y1, z)) for x, z in pts2]
	cx = sum(p[0] for p in pts2) / len(pts2)
	cz = sum(p[1] for p in pts2) / len(pts2)
	n = len(pts2)
	for k in range(n):
		k2 = (k + 1) % n
		mb.face([r0[k], r0[k2], r1[k2], r1[k]], mat, lambda q: Vector((q.x - cx, 0, q.z - cz)))
	s = 1 if y1 > y0 else -1
	mb.face(r0, mat, (0, -s, 0))
	mb.face(r1, mat, (0, s, 0))


# ---------------------------------------------------------------- headframe
def headframe():
	"""KWK Brzeszcze style steel headframe: lattice tower over the shaft (front, +Y), two back-leg struts and
	the winding house behind them (-Y), sheave wheels on an open platform near the top."""
	mb = MB()
	S = "SteelPaint"
	H = 36.0
	B, T = (5.0, 3.5), (3.3, 2.5)

	def leg(sx, sy, z):
		t = z / H
		return Vector((sx * kit.lerp(B[0], T[0], t), sy * kit.lerp(B[1], T[1], t), z))
	corners = [(1, 1), (-1, 1), (-1, -1), (1, -1)]
	levels = [H * k / 8 for k in range(9)]
	for sx, sy in corners:
		bar(mb, leg(sx, sy, 0), leg(sx, sy, H), 0.6, S)
		cube(mb, (sx * B[0] - 0.7, sy * B[1] - 0.7, 0), (sx * B[0] + 0.7, sy * B[1] + 0.7, 0.5), "Concrete", skip=("-z",))
	for f in range(4):
		(ax, ay), (bx, by) = corners[f], corners[(f + 1) % 4]
		for k in range(8):
			z0, z1 = levels[k], levels[k + 1]
			if k >= 2:  # the shaft hall covers the bottom two panels
				bar(mb, leg(ax, ay, z0), leg(bx, by, z1), 0.22, S)
				bar(mb, leg(bx, by, z0), leg(ax, ay, z1), 0.22, S)
			bar(mb, leg(ax, ay, z1), leg(bx, by, z1), 0.34, S)
	# shaft hall (nadszybie) in brick round the tower foot
	cube(mb, (-5.6, -4.0, 0), (5.6, 4.6, 8.2), "Brick", skip=("-z",))
	cube(mb, (-5.8, -4.2, 8.2), (5.8, 4.8, 8.6), "Concrete", skip=("-z",))
	cube(mb, (-5.8, -4.2, 0), (5.8, 4.8, 0.6), "Concrete", skip=("-z",))
	for x in (-3.6, -1.2, 1.2, 3.6):
		mb.quad((x - 0.6, 4.61, 3.0), (x + 0.6, 4.61, 3.0), (x + 0.6, 4.61, 7.2), (x - 0.6, 4.61, 7.2), "Glass", (0, 1, 0))
	for y in (-2.0, 0.3, 2.6):
		for sx in (-1, 1):
			x = sx * 5.61
			mb.quad((x, y - 0.6, 3.0), (x, y + 0.6, 3.0), (x, y + 0.6, 7.2), (x, y - 0.6, 7.2), "Glass", (sx, 0, 0))
	# platform with railings
	P = H
	dx, dy = T[0] + 0.8, T[1] + 0.8
	cube(mb, (-dx, -dy, P), (dx, dy, P + 0.35), "Steel")
	rz = P + 0.35
	edges = [((-dx, -dy), (dx, -dy)), ((dx, -dy), (dx, dy)), ((dx, dy), (-dx, dy)), ((-dx, dy), (-dx, -dy))]
	for (x0, y0), (x1, y1) in edges:
		bar(mb, (x0, y0, rz + 1.1), (x1, y1, rz + 1.1), 0.08, S)
		bar(mb, (x0, y0, rz + 0.55), (x1, y1, rz + 0.55), 0.06, S)
		n = max(1, round(math.hypot(x1 - x0, y1 - y0) / 1.8))
		for k in range(n):
			t = k / n
			x, y = kit.lerp(x0, x1, t), kit.lerp(y0, y1, t)
			bar(mb, (x, y, rz), (x, y, rz + 1.1), 0.07, S)
	# sheave wheels (axis along X) and their bearing pedestals
	R = 2.6
	zc = rz + 0.45 + R
	for x in (-1.5, 1.5):
		c = Vector((x, 0, zc))
		ring(mb, c, (1, 0, 0), R, R - 0.3, 0.32, "Red", segs=24)
		for k in range(8):
			a = 2 * math.pi * k / 8 + 0.2
			d = Vector((0, math.cos(a), math.sin(a)))
			bar(mb, c + d * 0.3, c + d * (R - 0.25), 0.14, "Red")
		mb.tube((x - 0.35, 0, zc), (x + 0.35, 0, zc), 0.35, "Steel", segs=8)
		for sxo in (-0.55, 0.55):
			cube(mb, (x + sxo - 0.15, -0.3, rz), (x + sxo + 0.15, 0.3, zc - 0.2), "Steel")
			for sy in (-1, 1):
				bar(mb, (x + sxo, sy * 2.0, rz), (x + sxo, 0, zc - 0.6), 0.16, S)
	# top gantry with the sheave crane
	gx, gy, gz = T[0] + 0.2, T[1] + 0.3, P + 6.6
	for sx in (-1, 1):
		for sy in (-1, 1):
			bar(mb, (sx * gx, sy * gy, rz), (sx * gx, sy * gy, gz), 0.3, S)
	for (x0, y0), (x1, y1) in (((-gx, -gy), (gx, -gy)), ((gx, -gy), (gx, gy)), ((gx, gy), (-gx, gy)), ((-gx, gy), (-gx, -gy))):
		bar(mb, (x0, y0, gz), (x1, y1, gz), 0.36, S)
		bar(mb, (x0, y0, rz + 0.2), ((x0 + x1) / 2, (y0 + y1) / 2, gz - 0.2), 0.14, S)
		bar(mb, (x1, y1, rz + 0.2), ((x0 + x1) / 2, (y0 + y1) / 2, gz - 0.2), 0.14, S)
	bar(mb, (-gx, 0, gz - 0.3), (gx, 0, gz - 0.3), 0.4, "Red", h=0.5)
	cube(mb, (-gx - 0.3, -gy - 0.3, gz + 0.18), (gx + 0.3, gy + 0.3, gz + 0.4), "Steel")
	# back-leg struts (towards -Y) and their bracing
	tops, feet = [], []
	for sx in (-1, 1):
		top = Vector((sx * T[0], -T[1], H - 1.0))
		foot = Vector((sx * 6.2, -13.0, 0.6))
		truss(mb, foot, top, 1.2, S, chord=0.3, web=0.14, panel=2.0)
		cube(mb, (foot.x - 0.9, foot.y - 0.9, 0), (foot.x + 0.9, foot.y + 0.9, 0.6), "Concrete", skip=("-z",))
		tops.append(top)
		feet.append(foot)
	pts = [feet[0].lerp(tops[0], t) for t in (0.15, 0.4, 0.65, 0.88)]
	pts2 = [feet[1].lerp(tops[1], t) for t in (0.15, 0.4, 0.65, 0.88)]
	for k in range(4):
		bar(mb, pts[k], pts2[k], 0.3, S)
		if k < 3:
			bar(mb, pts[k], pts2[k + 1], 0.18, S)
			bar(mb, pts2[k], pts[k + 1], 0.18, S)
	# ropes: down the shaft at the front, back to the winding house drums
	house_y0, house_y1 = -14.5, -24.5
	for x in (-1.5, 1.5):
		bar(mb, (x, R, zc), (x, R, 8.6), 0.08, "Trim")
		tgt = Vector((x, house_y0, 7.6))
		d = Vector((0, tgt.y, tgt.z - zc)).normalized()
		tan = Vector((x, d.z * R, zc - d.y * R))
		bar(mb, tan, tgt, 0.08, "Trim")
	# winding house: brick hall with tall windows and a sheet gable roof
	hx = 7.0
	cube(mb, (-hx, house_y1, 0), (hx, house_y0, 9.0), "Brick", skip=("-z",))
	cube(mb, (-hx - 0.2, house_y1 - 0.2, 0), (hx + 0.2, house_y0 + 0.2, 0.7), "Concrete", skip=("-z",))
	cube(mb, (-hx - 0.15, house_y1 - 0.15, 8.6), (hx + 0.15, house_y0 + 0.15, 9.0), "Concrete")
	mb.prism([(house_y0 + 0.5, 9.0), (house_y1 - 0.5, 9.0), ((house_y0 + house_y1) / 2, 11.2)], -hx - 0.4, hx + 0.4, "Steel")
	for x in (-4.5, -1.5, 1.5, 4.5):
		mb.quad((x - 0.8, house_y0 + 0.01, 2.2), (x + 0.8, house_y0 + 0.01, 2.2), (x + 0.8, house_y0 + 0.01, 7.6),
			(x - 0.8, house_y0 + 0.01, 7.6), "Glass", (0, 1, 0))
		cube(mb, (x - 0.95, house_y0, 2.0), (x + 0.95, house_y0 + 0.18, 2.2), "Concrete")
	for y in (house_y0 - 2.5, house_y0 - 5.0, house_y0 - 7.5):
		for sx in (-1, 1):
			x = sx * (hx + 0.01)
			mb.quad((x, y - 0.8, 2.2), (x, y + 0.8, 2.2), (x, y + 0.8, 7.6), (x, y - 0.8, 7.6), "Glass", (sx, 0, 0))
	for x in (-6.2, -3.0, 0.0, 3.0, 6.2):
		cube(mb, (x - 0.3, house_y0, 0.7), (x + 0.3, house_y0 + 0.25, 8.6), "Brick", skip=("-y",))
	return mb


# ---------------------------------------------------------------- church tower
def lancet_outline(w, h, n=3):
	"""Equilateral pointed arch window outline in (u, v), base centre at the origin."""
	vs = h - w * math.sqrt(3) / 2
	pts = [(-w / 2, 0.0), (w / 2, 0.0), (w / 2, vs)]
	for k in range(1, n + 1):
		a = math.radians(60) * k / n
		pts.append((-w / 2 + w * math.cos(a), vs + w * math.sin(a)))
	for k in range(1, n + 1):
		a = math.radians(120 + 60 * k / n)
		pts.append((w / 2 + w * math.cos(a), vs + w * math.sin(a)))
	return pts


def lancet(mb, origin, u, n_out, w, h, frame=0.3, depth=0.35, glass="Glass", trim="Brick", drop=None):
	"""A pointed window set back inside a projecting frame: glass on the wall, reveals, a frame ring."""
	o, u, nv, zv = Vector(origin), Vector(u), Vector(n_out), Vector((0, 0, 1))
	drop = frame * 0.5 if drop is None else drop
	I = lancet_outline(w, h)
	O = [(x, y - drop) for x, y in lancet_outline(w + 2 * frame, h + frame + drop)]

	def P(p, d):
		return o + u * p[0] + zv * p[1] + nv * d
	cen = o + zv * (h * 0.5)
	mb.poly([P(p, 0.02) for p in I], glass, nv)
	n = len(I)
	for k in range(n):
		k2 = (k + 1) % n
		inward = (lambda q: (cen - q) - nv * (cen - q).dot(nv))
		outward = (lambda q: (q - cen) - nv * (q - cen).dot(nv))
		mb.quad(P(I[k], 0.02), P(I[k2], 0.02), P(I[k2], depth), P(I[k], depth), trim, inward)
		mb.quad(P(I[k], depth), P(I[k2], depth), P(O[k2], depth), P(O[k], depth), trim, nv)
		mb.quad(P(O[k], depth), P(O[k2], depth), P(O[k2], 0.0), P(O[k], 0.0), trim, outward)


def church_spire():
	"""Neo-Gothic red-brick tower, entrance portal at the front (+Y); the nave would join at -Y."""
	mb = MB()
	C = 3.4
	Z = 38.0
	cube(mb, (-C - 0.25, -C - 0.25, 0), (C + 0.25, C + 0.25, 1.2), "Concrete", skip=("-z",))
	cube(mb, (-C, -C, 1.2), (C, C, Z), "Brick", skip=("-z",))
	for z in (12.0, 24.0, 29.6):
		cube(mb, (-C - 0.12, -C - 0.12, z), (C + 0.12, C + 0.12, z + 0.3), "Concrete")
	cube(mb, (-C - 0.3, -C - 0.3, Z - 0.5), (C + 0.3, C + 0.3, Z), "Concrete")
	# stepped corner buttresses (two per corner)
	steps = [(0.0, 12.0, 0.85), (12.0, 24.0, 0.6), (24.0, 34.0, 0.35)]
	for sx in (-1, 1):
		for sy in (-1, 1):
			for z0, z1, d in steps:
				cube(mb, (sx * (C - 0.9), sy * C, z0), (sx * C, sy * (C + d), z1), "Brick", skip=("-z",))
				cube(mb, (sx * C, sy * (C - 0.9), z0), (sx * (C + d), sy * C, z1), "Brick", skip=("-z",))
				cube(mb, (sx * (C - 0.95), sy * C, z1 - 0.15), (sx * (C + 0.05), sy * (C + d + 0.08), z1 + 0.1), "Concrete")
				cube(mb, (sx * C, sy * (C - 0.95), z1 - 0.15), (sx * (C + d + 0.08), sy * (C + 0.05), z1 + 0.1), "Concrete")
	# details of one face (+Y), repeated on the four sides
	face = MB()
	X, N = Vector((1, 0, 0)), Vector((0, 1, 0))
	lancet(face, (0, C, 14.0), X, N, 1.5, 7.5, frame=0.32, depth=0.35, trim="Concrete")
	for x in (-1.2, 1.2):
		lancet(face, (x, C, 30.4), X, N, 1.0, 5.6, frame=0.25, depth=0.3, glass="Trim", trim="Concrete")
	tri_prism(face, [(-2.7, Z), (2.7, Z), (0.0, Z + 4.6)], C - 0.5, C + 0.05, "Brick")
	for sx in (-1, 1):
		bar(face, (sx * 2.85, C - 0.2, Z - 0.05), (0.0, C - 0.2, Z + 4.85), 0.3, "Concrete", h=0.75)
	face.disc((0, C + 0.06, Z + 1.75), 1.0, "Trim", normal=(0, 1, 0), segs=16)
	face.disc((0, C + 0.08, Z + 1.75), 0.86, "Sign", normal=(0, 1, 0), segs=16)
	bar(face, (0, C + 0.1, Z + 1.75), (-0.35, C + 0.1, Z + 2.0), 0.07, "Trim")
	bar(face, (0, C + 0.1, Z + 1.75), (0.2, C + 0.1, Z + 2.45), 0.05, "Trim")
	side = MB()
	lancet(side, (0, C, 5.0), X, N, 0.9, 3.2, frame=0.25, depth=0.3, trim="Concrete")
	front = MB()
	lancet(front, (0, C, 1.2), X, N, 2.4, 5.6, frame=0.55, depth=0.65, glass="Wood", trim="Concrete", drop=0.0)
	cube(front, (-1.7, C, 7.6), (1.7, C + 0.3, 7.9), "Concrete")
	for f in range(4):
		rot = Matrix.Rotation(f * math.pi / 2, 3, "Z")
		mb.extend(face, basis=rot)
		if f:
			mb.extend(side, basis=rot)
	mb.extend(front)
	# corner pinnacles
	for sx in (-1, 1):
		for sy in (-1, 1):
			cx, cy = sx * (C - 0.1), sy * (C - 0.1)
			cube(mb, (cx - 0.5, cy - 0.5, Z - 0.5), (cx + 0.5, cy + 0.5, Z + 3.8), "Brick", skip=("-z",))
			cube(mb, (cx - 0.6, cy - 0.6, Z + 3.6), (cx + 0.6, cy + 0.6, Z + 3.9), "Concrete")
			lathe_p(mb, [(Z + 3.9, 0.6 * math.sqrt(2)), (Z + 7.6, 0.03)], 4, "Copper", (cx, cy, 0), math.pi / 4)
	# octagonal copper spire with lucarnes, a ball and a cross
	lathe_p(mb, [(Z - 0.2, 3.25), (Z + 0.6, 3.0), (Z + 2.4, 2.75), (57.0, 0.06)], 8, "Copper", phase=math.pi / 8)
	luc = MB()
	luc.box((-0.45, 1.1, 45.0), (0.45, 2.05, 46.4), "Copper", skip=("-y",))
	luc.quad((-0.3, 2.06, 45.2), (0.3, 2.06, 45.2), (0.3, 2.06, 46.2), (-0.3, 2.06, 46.2), "Trim", (0, 1, 0))
	tri_prism(luc, [(-0.6, 46.4), (0.6, 46.4), (0.0, 47.2)], 1.0, 2.15, "Copper")
	for f in range(4):
		mb.extend(luc, basis=Matrix.Rotation(f * math.pi / 2, 3, "Z"))
	lathe_p(mb, [(56.9, 0.06), (57.05, 0.25), (57.3, 0.32), (57.55, 0.25), (57.7, 0.05)], 8, "Steel")
	bar(mb, (0, 0, 57.6), (0, 0, 59.2), 0.12, "Steel")
	bar(mb, (-0.45, 0, 58.55), (0.45, 0, 58.55), 0.12, "Steel")
	return mb


# ---------------------------------------------------------------- street furniture
def streetlamp():
	"""9 m tapered steel pole, curved arm reaching 1.6 m forward (+Y), flat head lit underneath (Lamp)."""
	mb = MB()
	lathe_p(mb, [(0.0, 0.17), (0.3, 0.17), (0.34, 0.12)], 8, "Concrete")
	lathe_p(mb, [(0.3, 0.11), (0.7, 0.095), (8.4, 0.055)], 8, "Steel")
	R = 0.6
	pts = [Vector((0, R - R * math.cos(a), 8.4 + R * math.sin(a))) for a in [math.pi / 2 * k / 5 for k in range(6)]]
	pts.append(Vector((0, 1.35, 8.4 + R)))
	for a, b in zip(pts, pts[1:]):
		mb.tube(a, b, 0.05, "Steel", segs=6, caps=False)
	zt = 8.4 + R + 0.06
	prof = [(-0.15, -0.08), (0.15, -0.08), (0.17, -0.02), (0.11, 0.06), (-0.11, 0.06), (-0.17, -0.02)]
	secs = [(1.95, [(x * 0.85, z) for x, z in prof]), (1.25, prof)]
	loft(mb, [(y, [(x, zt + z) for x, z in p]) for y, p in secs], "Steel")
	z = zt - 0.085
	mb.quad((-0.12, 1.32, z), (0.12, 1.32, z), (0.1, 1.88, z), (-0.1, 1.88, z), "Lamp", (0, 0, -1))
	return mb


def streetlamp_park():
	"""4 m cast-iron park lamp with a hexagonal lantern (glass in Lamp)."""
	mb = MB()
	lathe_p(mb, [(0.0, 0.17), (0.32, 0.15), (0.45, 0.09), (0.62, 0.06), (3.3, 0.045), (3.36, 0.08), (3.46, 0.08)], 8, "Trim")
	lathe_p(mb, [(3.46, 0.08), (3.56, 0.17)], 6, "Trim")
	lathe_p(mb, [(3.56, 0.17), (3.98, 0.23)], 6, "Lamp")
	lathe_p(mb, [(3.98, 0.23), (4.0, 0.29), (4.14, 0.15), (4.22, 0.04)], 6, "Trim")
	lathe_p(mb, [(4.22, 0.04), (4.27, 0.05), (4.32, 0.0)], 6, "Trim")
	for k in range(6):
		a = 2 * math.pi * k / 6
		bar(mb, (0.17 * math.cos(a), 0.17 * math.sin(a), 3.56), (0.23 * math.cos(a), 0.23 * math.sin(a), 3.98), 0.025, "Trim")
	return mb


def traffic_light():
	"""3.5 m pole with a three-lamp signal head facing front (+Y)."""
	mb = MB()
	mb.tube((0, 0, 0), (0, 0, 3.5), 0.06, "Steel", segs=10)
	cube(mb, (-0.3, 0.06, 2.3), (0.3, 0.085, 3.45), "Trim")
	cube(mb, (-0.17, 0.085, 2.4), (0.17, 0.36, 3.36), "Trim")
	cube(mb, (-0.04, 0.0, 2.6), (0.04, 0.07, 3.2), "Steel")
	for z, m in ((3.17, "SignalRed"), (2.88, "SignalAmber"), (2.59, "SignalGreen")):
		mb.disc((0, 0.365, z), 0.11, m, normal=(0, 1, 0), segs=12)
		cube(mb, (-0.13, 0.36, z + 0.11), (0.13, 0.52, z + 0.13), "Trim")
		for sx in (-1, 1):
			cube(mb, (sx * 0.12, 0.36, z - 0.04), (sx * 0.13, 0.5, z + 0.11), "Trim")
	return mb


def bus_shelter():
	"""Glass-and-steel shelter, open towards the road (+Y), bench at the back, named fascia."""
	mb = MB()
	hx, y0, y1 = 2.0, -0.75, 0.55
	for x in (-hx, hx):
		for y in (y0, y1):
			bar(mb, (x, y, 0), (x, y, 2.45), 0.08, "Steel")
	cube(mb, (-hx, y0 - 0.02, 0.15), (hx, y0 + 0.02, 2.35), "Glass")
	for x in (-hx, hx):
		cube(mb, (x - 0.02, y0, 0.15), (x + 0.02, 0.2, 2.35), "Glass")
	for z in (0.12, 2.36):
		bar(mb, (-hx, y0, z), (hx, y0, z), 0.06, "Steel")
	cube(mb, (-hx - 0.12, -0.9, 2.45), (hx + 0.12, 0.85, 2.58), "Steel")
	cube(mb, (-hx - 0.12, 0.78, 2.3), (hx + 0.12, 0.88, 2.62), "Trim")
	kit.text_mesh(mb, "PRZYSTANEK", (0, 0.885, 2.46), 0.2, "Sign", axis_u=(-1, 0, 0), axis_v=(0, 0, 1))
	# bench
	for x in (-1.4, 0.0, 1.4):
		bar(mb, (x, -0.6, 0), (x, -0.6, 0.45), 0.06, "Steel")
		bar(mb, (x, -0.72, 0.42), (x, -0.32, 0.42), 0.05, "Steel")
	for y in (-0.66, -0.53, -0.4):
		cube(mb, (-1.7, y - 0.05, 0.44), (1.7, y + 0.05, 0.48), "Wood")
	# timetable and a D-15 style plate on the right end
	mb.quad((1.2, y0 + 0.03, 1.2), (1.8, y0 + 0.03, 1.2), (1.8, y0 + 0.03, 1.9), (1.2, y0 + 0.03, 1.9), "Sign", (0, 1, 0))
	bar(mb, (hx + 0.35, 0.6, 0), (hx + 0.35, 0.6, 2.9), 0.06, "Steel")
	cube(mb, (hx + 0.1, 0.62, 2.3), (hx + 0.6, 0.66, 2.8), "Sign")
	kit.text_mesh(mb, "A", (hx + 0.35, 0.665, 2.55), 0.36, "Trim", axis_u=(-1, 0, 0), axis_v=(0, 0, 1))
	return mb


def billboard():
	"""6 x 3 m billboard on two legs, face (Banner) towards +Y, 4 m clearance, a catwalk and two lamps."""
	mb = MB()
	for x in (-1.9, 1.9):
		bar(mb, (x, -0.4, 0), (x, -0.4, 7.2), 0.28, "Steel")
		cube(mb, (x - 0.4, -0.8, 0), (x + 0.4, 0.0, 0.3), "Concrete", skip=("-z",))
	cube(mb, (-3.1, -0.26, 3.9), (3.1, 0.0, 7.1), "Steel")
	mb.quad((-3.0, 0.005, 4.0), (3.0, 0.005, 4.0), (3.0, 0.005, 7.0), (-3.0, 0.005, 7.0), "Banner", (0, 1, 0))
	cube(mb, (-3.1, 0.0, 3.75), (3.1, 0.7, 3.82), "Steel")
	for x in (-1.6, 1.6):
		bar(mb, (x, 0.0, 7.05), (x, 1.0, 7.4), 0.06, "Steel")
		cube(mb, (x - 0.25, 0.9, 7.3), (x + 0.25, 1.15, 7.45), "Trim")
		mb.quad((x - 0.2, 0.92, 7.29), (x + 0.2, 0.92, 7.29), (x + 0.2, 1.13, 7.29), (x - 0.2, 1.13, 7.29), "Lamp", (0, -0.4, -1))
	return mb


def bench():
	"""Park bench, 1.8 m along X, the seat facing +Y."""
	mb = MB()
	for x in (-0.75, 0.75):
		bar(mb, (x, 0.24, 0), (x, 0.22, 0.44), 0.06, "Trim")
		bar(mb, (x, -0.2, 0), (x, -0.2, 0.44), 0.06, "Trim")
		bar(mb, (x, 0.28, 0.42), (x, -0.25, 0.42), 0.06, "Trim")
		bar(mb, (x, -0.21, 0.42), (x, -0.31, 0.88), 0.06, "Trim")
		bar(mb, (x, 0.26, 0.62), (x, -0.22, 0.62), 0.05, "Trim")
		bar(mb, (x, 0.24, 0.42), (x, 0.26, 0.64), 0.05, "Trim")
	for y in (0.2, 0.08, -0.04, -0.16):
		cube(mb, (-0.9, y - 0.05, 0.45), (0.9, y + 0.05, 0.485), "Wood")
	tilt = math.atan2(0.10, 0.36)
	rot = Matrix.Rotation(tilt, 3, "X")
	for t in (0.25, 0.55, 0.85):
		c = Vector((0, kit.lerp(-0.23, -0.31, t) - 0.04, kit.lerp(0.5, 0.88, t)))
		mb.box((-0.9, -0.0175, -0.05), (0.9, 0.0175, 0.05), "Wood", basis=rot, origin=c)
	return mb


FENCE_L = 2.5


def fence():
	"""Green welded-mesh panel on a concrete plinth with one post at x = 0; runs along +X to FENCE_L."""
	mb = MB()
	L = FENCE_L
	cube(mb, (0, -0.04, 0), (L, 0.04, 0.2), "Concrete")
	cube(mb, (-0.035, -0.03, 0), (0.035, 0.03, 1.55), "SteelPaint", skip=("-z",))
	cube(mb, (-0.045, -0.04, 1.55), (0.045, 0.04, 1.58), "Trim")
	n = 12
	for k in range(n):
		x = 0.08 + k * (L - 0.12) / (n - 1)
		bar(mb, (x, 0, 0.24), (x, 0, 1.5), 0.018, "SteelPaint")
	for z in (0.26, 0.6, 0.66, 1.1, 1.16, 1.48):
		bar(mb, (0.035, 0.012, z), (L, 0.012, z), 0.018, "SteelPaint")
	for z in (0.4, 1.32):
		cube(mb, (0.035, -0.02, z - 0.02), (0.08, 0.02, z + 0.02), "Trim")
	return mb


def level_crossing():
	"""Barrier post at the origin, a 6 m red/white boom along +X, a St Andrew's cross with red lights."""
	mb = MB()
	cube(mb, (-0.5, -0.4, 0), (0.5, 0.4, 0.15), "Concrete", skip=("-z",))
	cube(mb, (-0.25, -0.2, 0.15), (0.25, 0.2, 1.2), "Sign", skip=("-z",))
	cube(mb, (-0.27, -0.22, 1.2), (0.27, 0.22, 1.28), "Trim")
	cube(mb, (-0.26, -0.21, 0.15), (0.26, 0.21, 0.4), "Red")
	mb.tube((0, 0.2, 1.0), (0, 0.32, 1.0), 0.09, "Steel", segs=8)
	# St Andrew's cross on its own post behind the barrier
	px = -1.0
	mb.tube((px, 0, 0), (px, 0, 3.3), 0.05, "Steel", segs=8)
	zc = 2.75
	for ang in (math.radians(35), math.radians(145)):
		d = Vector((math.cos(ang), 0, math.sin(ang)))
		nseg = 6
		for k in range(nseg):
			t0, t1 = -0.65 + 1.3 * k / nseg, -0.65 + 1.3 * (k + 1) / nseg
			a = Vector((px, 0.07 if ang < 1 else 0.08, zc)) + d * t0
			b = Vector((px, 0.07 if ang < 1 else 0.08, zc)) + d * t1
			bar(mb, a, b, 0.2, "Red" if k % 2 == 0 else "Sign", h=0.02, up=(0, 1, 0))
	cube(mb, (px - 0.5, 0.04, 1.85), (px + 0.5, 0.1, 2.2), "Trim")
	for sx in (-1, 1):
		mb.disc((px + sx * 0.3, 0.105, 2.02), 0.12, "SignalRed", normal=(0, 1, 0), segs=12)
		cube(mb, (px + sx * 0.3 - 0.14, 0.1, 2.15), (px + sx * 0.3 + 0.14, 0.25, 2.17), "Trim")
	return mb


def level_crossing_boom():
	"""The crossing's 6 m red/white boom and its counterweight, origin at the hinge on the post (Blender
	(0, 0.34, 1.0) of LevelCrossing, i.e. Godot (0, 1.0, -0.34)). It lies down along +X; Godot raises it by
	turning it about its Z axis."""
	mb = MB()
	seg = 0.5
	for k in range(12):
		x0 = 0.1 + k * seg
		cube(mb, (x0, -0.04, -0.06), (x0 + seg, 0.04, 0.06), "Red" if k % 2 == 0 else "Sign")
	cube(mb, (-0.9, -0.07, -0.14), (-0.2, 0.07, 0.14), "Trim")
	bar(mb, (-0.2, 0.0, 0.0), (0.1, 0.0, 0.0), 0.08, "Trim")
	for x in (2.0, 4.2, 6.0):
		mb.disc((x, 0.045, 0.0), 0.045, "SignalRed", normal=(0, 1, 0), segs=8)
	return mb


# ---------------------------------------------------------------- train
EN57_L = 20.7  # m over the body; the unit is cab + middle car + reversed cab, 0.5 m apart
EN57_W = 2.88


def en57(cab):
	"""One car of a PKP EN57 electric unit in cream and blue: origin at the rail top under the car's centre,
	the cab (if cab) towards +Y (Godot -Z). The middle car carries the pantograph."""
	mb = MB()
	L, W = EN57_L, EN57_W
	hy, hw = L / 2, W / 2
	z0, z1, zr = 1.15, 3.55, 3.85
	cube(mb, (-hw, -hy, z0), (hw, hy, z1), "TrainCream")
	cube(mb, (-hw - 0.01, -hy - 0.01, z0), (hw + 0.01, hy + 0.01, 1.85), "TrainBlue")
	cube(mb, (-hw - 0.012, -hy, 2.95), (hw + 0.012, hy, 3.05), "TrainBlue")
	cube(mb, (-hw + 0.1, -hy + 0.1, 0.85), (hw - 0.1, hy - 0.1, z0), "Trim", skip=("+z",))
	# rounded roof: two stepped slabs
	cube(mb, (-hw + 0.08, -hy, z1), (hw - 0.08, hy, z1 + 0.15), "Steel", skip=("-z",))
	cube(mb, (-hw + 0.45, -hy, z1 + 0.15), (hw - 0.45, hy, zr), "Steel", skip=("-z",))
	# side windows and doors, both sides
	door_y = (hy - 3.4, -hy + 3.4) if cab else (hy - 2.0, -hy + 2.0)
	for side in (-1, 1):
		x = side * (hw + 0.013)
		n = (side, 0, 0)
		y = -hy + 1.6
		while y < hy - 2.0:
			if all(abs(y + 0.55 - dy) > 1.2 for dy in door_y):
				mb.quad((x, y, 2.1), (x, y + 1.1, 2.1), (x, y + 1.1, 2.85), (x, y, 2.85), "Glass", n)
			y += 1.4
		for dy in door_y:
			mb.quad((x, dy - 0.65, 1.2), (x, dy + 0.65, 1.2), (x, dy + 0.65, 3.2), (x, dy - 0.65, 3.2), "Trim", n)
			x2 = x + side * 0.004
			for k in (-1, 1):
				cy = dy + k * 0.32
				mb.quad((x2, cy - 0.22, 2.1), (x2, cy + 0.22, 2.1), (x2, cy + 0.22, 2.95), (x2, cy - 0.22, 2.95), "Glass", n)
	# bogies with a 2.5 m wheelbase; the wheels are dark discs on both sides
	for by in (hy - 3.2, -hy + 3.2):
		cube(mb, (-1.0, by - 1.6, 0.3), (1.0, by + 1.6, 0.85), "Trim")
		for wy in (by - 1.25, by + 1.25):
			for side in (-1, 1):
				mb.disc((side * 1.03, wy, 0.48), 0.48, "Rubber", normal=(side, 0, 0), segs=12)
	if cab:
		# the sloped nose: blue apron, raked windscreen, cream brow; lamps low and on the roof
		ny = hy + 0.35
		mb.quad((-hw, hy, z0), (hw, hy, z0), (hw, hy, 1.85), (-hw, hy, 1.85), "TrainBlue", (0, 1, 0))
		mb.quad((-hw, hy, 1.85), (hw, hy, 1.85), (hw, ny, 2.2), (-hw, ny, 2.2), "TrainBlue", (0, 1, 0))
		mb.quad((-hw, ny, 2.2), (hw, ny, 2.2), (hw, ny - 0.1, 3.15), (-hw, ny - 0.1, 3.15), "Glass", (0, 1, 0.1))
		mb.quad((-hw, ny - 0.1, 3.15), (hw, ny - 0.1, 3.15), (hw - 0.45, hy, zr), (-hw + 0.45, hy, zr), "TrainCream", (0, 1, 0.4))
		for side in (-1, 1):
			mb.quad((side * hw, hy, 1.85), (side * hw, ny, 2.2), (side * hw, ny - 0.1, 3.15), (side * hw, hy, 3.15), "TrainBlue", (side, 0, 0))
			mb.quad((side * hw, hy, 3.15), (side * hw, ny - 0.1, 3.15), (side * (hw - 0.45), hy, zr), (side * hw, hy, zr), "TrainCream", (side, 0, 0))
			mb.disc((side * 0.95, hy + 0.012, 1.55), 0.13, "Headlight", normal=(0, 1, 0), segs=10)
			mb.disc((side * 0.95, hy + 0.012, 1.25), 0.07, "Taillight", normal=(0, 1, 0), segs=8)
		mb.disc((0, ny - 0.05, 3.45), 0.12, "Headlight", normal=(0, 1, 0.3), segs=10)
		cube(mb, (-0.25, hy, 0.75), (0.25, hy + 0.5, 1.05), "Trim")  # coupler
		cube(mb, (-0.5, -hy - 0.2, 1.3), (0.5, -hy, 3.3), "Trim")  # gangway at the inner end
	else:
		for sy in (-1, 1):
			lo, hi_ = sorted((sy * hy, sy * (hy + 0.2)))
			cube(mb, (-0.5, lo, 1.3), (0.5, hi_, 3.3), "Trim")
		for k in (-1, 1):
			cube(mb, (-0.3, k * 1.2 - 0.15, zr), (0.3, k * 1.2 + 0.15, zr + 0.2), "Trim")
		top = zr + 1.4
		for x in (-0.6, 0.6):
			for k in (-1, 1):
				bar(mb, (x, k * 1.0, zr + 0.2), (x, k * 0.15, top), 0.05, "Steel")
		bar(mb, (-0.85, 0, top), (0.85, 0, top), 0.06, "Steel")
	return mb


# ---------------------------------------------------------------- festival hub
def festival_arch():
	"""Start-finish arch: 14 m between truss legs, 8 m tall, a big printed banner box over the top."""
	mb = MB()
	lx, H, s = 7.0, 8.0, 0.6
	for sx in (-1, 1):
		truss(mb, (sx * lx, 0, 0.5), (sx * lx, 0, H - 2.5), s, "Steel", up=(1, 0, 0))
		cube(mb, (sx * lx - 0.8, -0.8, 0), (sx * lx + 0.8, 0.8, 0.5), "Concrete", skip=("-z",))
		cube(mb, (sx * (lx + 0.32), -0.45, 1.2), (sx * (lx + 0.36), 0.45, H - 2.8), "Banner")
	cube(mb, (-lx - 0.6, -0.45, H - 2.5), (lx + 0.6, 0.45, H), "Banner")
	cube(mb, (-lx - 0.65, -0.5, H), (lx + 0.65, 0.5, H + 0.12), "Trim")
	cube(mb, (-lx - 0.65, -0.5, H - 2.62), (lx + 0.65, 0.5, H - 2.5), "Trim")
	q = 0.35
	n = int(round((2 * lx + 1.2) / q))
	x0 = -n * q / 2
	for side in (-1, 1):
		y = side * 0.455
		for row in range(2):
			for k in range(n):
				m = "Sign" if (k + row) % 2 == 0 else "Trim"
				a, b = x0 + k * q, x0 + (k + 1) * q
				z0 = H - 2.48 + row * q
				mb.quad((a, y, z0), (b, y, z0), (b, y, z0 + q), (a, y, z0 + q), m, (0, side, 0))
	for x in (-4.5, -1.5, 1.5, 4.5):
		cube(mb, (x - 0.2, -0.2, H - 2.9), (x + 0.2, 0.2, H - 2.62), "Trim")
		mb.quad((x - 0.15, -0.15, H - 2.91), (x + 0.15, -0.15, H - 2.91), (x + 0.15, 0.15, H - 2.91), (x - 0.15, 0.15, H - 2.91), "Lamp", (0, 0, -1))
	return mb


def speaker(mb, lo, hi, cones):
	"""A speaker cabinet with cone discs on its +Y face."""
	cube(mb, lo, hi, "Trim")
	for cx, cz, r in cones:
		mb.disc((cx, hi[1] + 0.005, cz), r, "Rubber", normal=(0, 1, 0), segs=12)


def festival_stage():
	"""16 x 10 m stage deck 1.5 m high, four truss towers and a 10 m roof, audience side +Y."""
	mb = MB()
	hw, hd, Hd = 8.0, 5.0, 1.5
	cube(mb, (-hw, -hd, 0), (hw, hd, Hd - 0.08), "Trim", skip=("-z",))
	cube(mb, (-hw - 0.05, -hd - 0.05, Hd - 0.08), (hw + 0.05, hd + 0.05, Hd), "Wood")
	tx, ty, Ht, s = hw + 0.4, hd + 0.3, 10.0, 0.45
	zt = Ht - s / 2
	for sx in (-1, 1):
		for sy in (-1, 1):
			truss(mb, (sx * tx, sy * ty, 0.1), (sx * tx, sy * ty, zt - s / 2), s, "Steel", up=(1, 0, 0), panel=0.9)
			cube(mb, (sx * tx - 0.5, sy * ty - 0.5, 0), (sx * tx + 0.5, sy * ty + 0.5, 0.1), "Steel", skip=("-z",))
	for sy in (-1, 1, -0.33, 0.33):
		truss(mb, (-tx - s / 2, sy * ty, zt), (tx + s / 2, sy * ty, zt), s, "Steel", panel=0.9)
	for sx in (-1, 1):
		truss(mb, (sx * tx, -ty + s / 2, zt), (sx * tx, ty - s / 2, zt), s, "Steel", panel=0.9)
	mb.prism([(-(ty + 0.6), Ht + 0.05), ((ty + 0.6), Ht + 0.05), (0.0, Ht + 1.9)], -tx - 0.7, tx + 0.7, "Trim")
	# banners: a header across the front truss and tall side wings
	cube(mb, (-tx + 0.3, ty + 0.25, Ht - 1.75), (tx - 0.3, ty + 0.32, Ht - 0.5), "Banner")
	for sx in (-1, 1):
		cube(mb, (sx * (tx + 0.3), ty - 0.03, 2.4), (sx * (tx + 2.1), ty + 0.03, Ht - 0.6), "Banner")
		bar(mb, (sx * (tx + 0.25), ty, Ht - 0.6), (sx * (tx + 2.1), ty, Ht - 0.6), 0.08, "Steel")
	# LED screen and back drape
	cube(mb, (-5.6, -hd + 0.25, Hd + 0.7), (5.6, -hd + 0.45, Hd + 6.9), "Trim")
	cube(mb, (-5.4, -hd + 0.45, Hd + 0.9), (5.4, -hd + 0.47, Hd + 6.7), "Glass")
	cube(mb, (-tx, -ty - 0.05, 0), (tx, -ty + 0.05, Ht - 0.6), "Trim")
	# ground stacks at the front corners and hanging line arrays
	for sx in (-1, 1):
		x0 = sx * (hw - 0.4)
		for k in range(2):
			xa = x0 - sx * k * 1.25
			speaker(mb, (xa - 0.6, hd + 0.3, 0), (xa + 0.6, hd + 1.2, 0.85), [(xa - 0.27, 0.42, 0.25), (xa + 0.27, 0.42, 0.25)])
			speaker(mb, (xa - 0.6, hd + 0.35, 0.85), (xa + 0.6, hd + 1.15, 1.6), [(xa - 0.27, 1.22, 0.25), (xa + 0.27, 1.22, 0.25)])
		speaker(mb, (x0 - 0.55, hd + 0.4, 1.6), (x0 + 0.55, hd + 1.1, 2.1), [(x0 - 0.3, 1.85, 0.16), (x0 + 0.3, 1.85, 0.16)])
		xl = sx * (tx - 1.3)
		z = zt - 0.5
		bar(mb, (xl, ty, zt), (xl, ty + 0.1, z), 0.05, "Steel")
		for k in range(7):
			ang = math.radians(2 + k * 4)
			rot = Matrix.Rotation(-ang, 3, "X")
			c = Vector((xl, ty + 0.2 + k * 0.035, z - 0.17))
			mb.box((-0.55, -0.3, -0.15), (0.55, 0.3, 0.15), "Trim", basis=rot, origin=c)
			z -= 0.33
	# lights along the front truss
	for k in range(8):
		x = -6.3 + k * 1.8
		mb.tube((x, ty, zt - 0.25), (x, ty + 0.15, zt - 0.6), 0.14, "Trim", segs=8, caps=False)
		mb.disc((x, ty + 0.15, zt - 0.6), 0.13, "Lamp", normal=(0, 0.4, -1), segs=8)
	# stairs at the back right
	for k in range(6):
		z = (k + 1) * Hd / 6
		cube(mb, (hw - 2.4, -hd - 1.8 + k * 0.3, 0), (hw - 1.0, -hd, z), "Steel")
	return mb


def flag_pole():
	"""8 m pole with a tall feather flag (Banner) streaming towards +X, its face towards +Y."""
	mb = MB()
	for a in range(4):
		ang = a * math.pi / 2 + math.pi / 4
		bar(mb, (0, 0, 0.05), (0.55 * math.cos(ang), 0.55 * math.sin(ang), 0.05), 0.06, "Trim")
	lathe_p(mb, [(0.0, 0.18), (0.12, 0.18), (0.16, 0.05)], 8, "Trim")
	mb.tube((0, 0, 0.1), (0, 0, 6.6), 0.035, "Steel", segs=6, caps=False)
	top = [Vector((0, 0, 6.6))]
	for k in range(1, 7):
		a = math.pi / 2 * k / 6
		top.append(Vector((0.55 - 0.55 * math.cos(a), 0, 6.6 + 1.25 * math.sin(a))))
	for a, b in zip(top, top[1:]):
		mb.tube(a, b, 0.025, "Steel", segs=5, caps=False)
	# the flag runs along a spine (up the pole, then round the bent top), its width set by w(t)
	spine = [Vector((0.04, 0, 1.6 + 5.0 * k / 8)) for k in range(8)] + [p + Vector((0.04, 0, 0)) for p in top]
	lens = [0.0]
	for a, b in zip(spine, spine[1:]):
		lens.append(lens[-1] + (b - a).length)
	outerp = []
	for k, p in enumerate(spine):
		t = lens[k] / lens[-1]
		d = (spine[min(k + 1, len(spine) - 1)] - spine[max(k - 1, 0)]).normalized()
		w = (0.62 + 0.4 * math.sin(min(1.0, t / 0.35) * math.pi / 2)) * (1.0 if t < 0.7 else max(0.05, 1 - (t - 0.7) / 0.3))
		outerp.append(p + Vector((d.z, 0, -d.x)) * w + Vector((0, 0, -0.35 * (1 - t) if k == 0 else 0)))
	for k in range(len(spine) - 1):
		mb.quad(spine[k], spine[k + 1], outerp[k + 1], outerp[k], "Banner", (0, 1, 0))
	return mb


def tent():
	"""5 x 5 m pop-up gazebo with a peaked roof and valance (Banner)."""
	mb = MB()
	h, e, pz = 2.45, 2.55, 3.55
	for sx in (-1, 1):
		for sy in (-1, 1):
			bar(mb, (sx * h, sy * h, 0), (sx * h, sy * h, 2.4), 0.05, "Steel")
			bar(mb, (sx * h, sy * h, 2.4), (0, 0, pz - 0.05), 0.04, "Steel")
			cube(mb, (sx * h - 0.12, sy * h - 0.12, 0), (sx * h + 0.12, sy * h + 0.12, 0.02), "Steel")
	cs = [(e, e), (-e, e), (-e, -e), (e, -e)]
	for k in range(4):
		(x0, y0), (x1, y1) = cs[k], cs[(k + 1) % 4]
		mb.poly([(x0, y0, 2.4), (x1, y1, 2.4), (0, 0, pz)], "Banner", lambda q: Vector((q.x, q.y, 1.0)))
		mb.quad((x0, y0, 2.1), (x1, y1, 2.1), (x1, y1, 2.4), (x0, y0, 2.4), "Banner", lambda q: Vector((q.x, q.y, 0)))
	cube(mb, (-1.0, -0.4, 0.72), (1.0, 0.4, 0.76), "Sign")
	for sx in (-0.9, 0.9):
		for sy in (-0.3, 0.3):
			bar(mb, (sx, sy, 0), (sx, sy, 0.72), 0.03, "Trim")
	return mb


def beacon():
	"""Event marker: a 6 m flat ring (Banner) and a 30 m light column (Lamp)."""
	mb = MB()
	mb.lathe([(0.0, 3.0), (0.06, 3.0), (0.06, 2.4), (0.0, 2.4)], 40, "Banner")
	lathe_p(mb, [(0.0, 1.4), (24.0, 1.3), (30.0, 1.0)], 20, "Lamp")
	for k in range(4):
		a = k * math.pi / 2
		d, s = Vector((math.cos(a), math.sin(a), 0)), Vector((-math.sin(a), math.cos(a), 0))
		mb.poly([d * 1.7 + s * 0.45 + Vector((0, 0, 0.02)), d * 2.25 + Vector((0, 0, 0.02)), d * 1.7 - s * 0.45 + Vector((0, 0, 0.02))],
			"Banner", (0, 0, 1))
	return mb


# ---------------------------------------------------------------- cars
def loft(mb, sections, mat):
	"""Loft closed (x, z) profiles placed at stations along Y; capped at both ends. mat: name or callable(i, j).
	Returns (grid, mean centre height) for decals."""
	grid = [[Vector((x, y, z)) for x, z in prof] for y, prof in sections]
	ids = [[mb.vert(p) for p in row] for row in grid]
	n = len(grid[0])
	czs = [sum(p.z for p in row) / n for row in grid]
	for i in range(len(grid) - 1):
		zc = (czs[i] + czs[i + 1]) / 2
		for j in range(n):
			j2 = (j + 1) % n
			m = mat(i, j) if callable(mat) else mat
			mb.face([ids[i][j], ids[i][j2], ids[i + 1][j2], ids[i + 1][j]], m, lambda q, zc=zc: Vector((q.x, 0.0, q.z - zc)))
	sgn = 1.0 if grid[0][0].y > grid[-1][0].y else -1.0
	cm = mat(-1, -1) if callable(mat) else mat
	mb.face(ids[0], cm, (0, sgn, 0))
	mb.face(ids[-1], cm, (0, -sgn, 0))
	return grid, sum(czs) / len(czs)


def decal(mb, grid, s0, s1, p0, p1, mat, cz, off=0.006):
	"""A panel lying on a loft surface over station range s0..s1 and profile range p0..p1 (fractional grid
	coordinates), lifted off the surface by off."""
	n, ns = len(grid[0]), len(grid)
	yc = (grid[0][0].y + grid[-1][0].y) / 2

	def P(s, p):
		i = min(max(int(math.floor(s)), 0), ns - 2)
		fs = s - i
		j = int(math.floor(p))
		fp = p - j
		a = grid[i][j % n].lerp(grid[i][(j + 1) % n], fp)
		b = grid[i + 1][j % n].lerp(grid[i + 1][(j + 1) % n], fp)
		return a.lerp(b, fs)

	def N(s, p):
		e = 0.02
		nv = (P(min(s + e, ns - 1), p) - P(max(s - e, 0), p)).cross(P(s, p + e) - P(s, p - e))
		q = P(s, p)
		ref = Vector((q.x, (q.y - yc) * 0.5, q.z - cz))
		if nv.length < 1e-9:
			return ref.normalized()
		nv.normalize()
		return nv if nv.dot(ref) >= 0 else -nv

	def cuts(a, b):
		return [a] + [float(k) for k in range(math.floor(a) + 1, math.ceil(b))] + [b]
	ss, ps = cuts(s0, s1), cuts(p0, p1)
	vid = {}

	def V(s, p):
		if (s, p) not in vid:
			vid[(s, p)] = mb.vert(P(s, p) + N(s, p) * off)
		return vid[(s, p)]
	for a in range(len(ss) - 1):
		for b in range(len(ps) - 1):
			nm = N((ss[a] + ss[a + 1]) / 2, (ps[b] + ps[b + 1]) / 2)
			mb.face([V(ss[a], ps[b]), V(ss[a + 1], ps[b]), V(ss[a + 1], ps[b + 1]), V(ss[a], ps[b + 1])], mat, nm)


def rounded_section(hw, zb, zt, rb, rt, n=2):
	"""Closed body cross-section with rounded corners: bottom-right, top-right, top-left, bottom-left."""
	rb = max(0.01, min(rb, (zt - zb) * 0.45))
	rt = max(0.01, min(rt, (zt - zb) * 0.45))
	pts = []

	def arc(cx, cz, r, a0, a1):
		for k in range(n + 1):
			a = a0 + (a1 - a0) * k / n
			pts.append((cx + r * math.cos(a), cz + r * math.sin(a)))
	arc(hw - rb, zb + rb, rb, -math.pi / 2, 0)
	arc(hw - rt, zt - rt, rt, 0, math.pi / 2)
	arc(-hw + rt, zt - rt, rt, math.pi / 2, math.pi)
	arc(-hw + rb, zb + rb, rb, math.pi, 3 * math.pi / 2)
	return pts


def cabin_section(hwb, hwt, zb, zt, rr, n=2):
	"""Greenhouse cross-section: belt corners, tumblehome sides, rounded roof corners.
	Edges: 0 right side, 1..2n+1 roof band, 2n+2 left side, 2n+3 bottom."""
	rr = max(0.005, min(rr, (zt - zb) * 0.45, hwt * 0.5))
	pts = [(hwb, zb)]
	for k in range(n + 1):
		a = math.pi / 2 * k / n
		pts.append((hwt - rr + rr * math.cos(a), zt - rr + rr * math.sin(a)))
	for k in range(n + 1):
		a = math.pi / 2 + math.pi / 2 * k / n
		pts.append((-hwt + rr + rr * math.cos(a), zt - rr + rr * math.sin(a)))
	pts.append((-hwb, zb))
	return pts


def s_of_y(ys, y):
	"""Fractional station index of y along descending station positions ys."""
	if y >= ys[0]:
		return 0.0
	for i in range(len(ys) - 1):
		if ys[i] >= y >= ys[i + 1]:
			return i + (ys[i] - y) / (ys[i] - ys[i + 1])
	return float(len(ys) - 1)


def interp(stations, y, idx):
	ys = [s[0] for s in stations]
	s = s_of_y(ys, y)
	i = min(int(s), len(ys) - 2)
	return kit.lerp(stations[i][idx], stations[i + 1][idx], s - i)


def car(sp):
	"""A car from a spec: lower body loft, greenhouse loft, glass decals, lamps, bumpers, wheels."""
	mb = MB()
	low, up = sp["lower"], sp["upper"]
	nc = sp.get("nc", 2)
	gl, czl = loft(mb, [(y, rounded_section(hw, zb, zt, rb, rt, sp.get("nl", 2))) for y, zb, zt, hw, rb, rt in low], "Paint")
	gu, czu = loft(mb, [(y, cabin_section(hwb, hwt, zb, zt, rr, nc)) for y, zb, zt, hwb, hwt, rr in up], "Paint")
	yu = [s[0] for s in up]
	r0, r1 = 1.12, 2 * nc + 2 - 0.12
	left = 2 * nc + 2
	decal(mb, gu, s_of_y(yu, sp["ws"][0]), s_of_y(yu, sp["ws"][1]), r0, r1, "Glass", czu)
	if sp.get("rear"):
		decal(mb, gu, s_of_y(yu, sp["rear"][0]), s_of_y(yu, sp["rear"][1]), r0, r1, "Glass", czu)
	pm = sp.get("side_p", (0.1, 0.88))
	for yf, yr in sp["side"]:
		s0, s1 = s_of_y(yu, yf), s_of_y(yu, yr)
		decal(mb, gu, s0, s1, pm[0], pm[1], "Glass", czu)
		decal(mb, gu, s0, s1, left + 1 - pm[1], left + 1 - pm[0], "Glass", czu)
	# front and rear: lamps, grille, bumpers, plates
	y0, zb0, zt0, hw0 = low[0][:4]
	yr, zbr, ztr, hwr = low[-1][:4]
	hwmax = max(s[3] for s in low)
	for sx in (-1, 1):
		if sp.get("head"):
			x0, x1, z0, z1 = sp["head"]
			cube(mb, (sx * x0, y0 - 0.03, z0), (sx * x1, y0 + 0.015, z1), "Headlight")
		x0, x1, z0, z1 = sp["tail"]
		cube(mb, (sx * x0, yr + 0.03, z0), (sx * x1, yr - 0.015, z1), "Taillight")
	if sp.get("grille"):
		x, z0, z1 = sp["grille"]
		cube(mb, (-x, y0 - 0.03, z0), (x, y0 + 0.01, z1), "Trim")
	bm = sp.get("bumper_mat", "Trim")
	bf, br = sp["bumpers"]
	bw = hwmax - sp.get("bumper_in", 0.01)
	cube(mb, (-bw, y0 - 0.28, bf[0]), (bw, y0 + bf[2], bf[1]), bm)
	cube(mb, (-bw, yr + 0.28, br[0]), (bw, yr - br[2], br[1]), bm)
	pf, prr = sp["plates"]
	if pf is not None:
		mb.quad((-0.26, y0 + bf[2] + 0.004, pf), (0.26, y0 + bf[2] + 0.004, pf), (0.26, y0 + bf[2] + 0.004, pf + 0.11),
			(-0.26, y0 + bf[2] + 0.004, pf + 0.11), "Sign", (0, 1, 0))
	py = prr[1] if len(prr) > 1 else yr - br[2] - 0.004
	mb.quad((-0.26, py, prr[0]), (0.26, py, prr[0]), (0.26, py, prr[0] + 0.11), (-0.26, py, prr[0] + 0.11), "Sign", (0, -1, 0))
	# side strip
	if sp.get("strip"):
		z0, z1 = sp["strip"]
		ya, yb = low[2][0] - 0.05, low[-3][0] + 0.05
		for sx in (-1, 1):
			cube(mb, (sx * hwmax, ya, z0), (sx * (hwmax + 0.018), yb, z1), "Trim")
	# mirrors at the base of the A-pillars
	yA, zA, hwA = up[0][0], up[0][1], up[0][3]
	for sx in (-1, 1):
		cube(mb, (sx * (hwA + 0.01), yA - 0.2, zA + 0.05), (sx * (hwA + 0.12), yA - 0.13, zA + 0.14), sp.get("mirror_mat", "Paint"))
	# wheels with dark wheel wells painted on the body side
	r = sp["r"]
	tw = sp.get("tw", 0.2)
	for ya in sp["axles"]:
		hwb = interp(low, ya, 3)
		zbb = interp(low, ya, 1)
		for sx in (-1, 1):
			R = r + sp.get("arch", 0.06)
			pts = [(sx * (hwb + 0.004), ya + R * math.cos(a), r + R * math.sin(a)) for a in [math.pi * k / 10 for k in range(11)]]
			pts += [(sx * (hwb + 0.004), ya - R, zbb + 0.01), (sx * (hwb + 0.004), ya + R, zbb + 0.01)]
			mb.poly(pts, "Trim", (sx, 0, 0))
			xo, xi = sx * (hwb + 0.014), sx * (hwb - tw)
			mb.tube((xi, ya, r), (xo, ya, r), r, "Rubber", segs=16)
			mb.disc((xo + sx * 0.004, ya, r), r * 0.62, "Steel", normal=(sx, 0, 0), segs=12)
			mb.disc((xo + sx * 0.008, ya, r), r * 0.2, "Trim", normal=(sx, 0, 0), segs=8)
	if sp.get("extra"):
		sp["extra"](mb, gl, czl, gu, czu)
	return mb


CAR_HATCH = {
	"lower": [(2.00, 0.30, 0.72, 0.76, 0.06, 0.10), (1.94, 0.22, 0.80, 0.82, 0.07, 0.12), (1.55, 0.20, 0.88, 0.85, 0.07, 0.13),
		(0.85, 0.20, 0.95, 0.85, 0.07, 0.12), (-1.40, 0.20, 0.99, 0.85, 0.07, 0.12), (-1.90, 0.24, 0.98, 0.83, 0.07, 0.12),
		(-2.00, 0.30, 0.95, 0.78, 0.06, 0.10)],
	"upper": [(0.85, 0.93, 0.95, 0.80, 0.78, 0.01), (0.05, 0.95, 1.45, 0.78, 0.66, 0.10), (-1.35, 0.97, 1.43, 0.79, 0.67, 0.10),
		(-1.94, 0.96, 1.00, 0.79, 0.74, 0.02)],
	"ws": (0.80, 0.09), "rear": (-1.40, -1.86), "side": [(0.62, -0.62), (-0.70, -1.52)],
	"head": (0.40, 0.72, 0.55, 0.68), "grille": (0.34, 0.50, 0.63), "tail": (0.55, 0.77, 0.62, 0.90),
	"bumpers": ((0.24, 0.48, 0.06), (0.24, 0.50, 0.06)), "plates": (0.30, (0.30,)),
	"strip": (0.74, 0.80), "axles": (1.22, -1.28), "r": 0.31,
}

CAR_SEDAN = {
	"lower": [(2.25, 0.30, 0.70, 0.79, 0.06, 0.10), (2.18, 0.22, 0.78, 0.85, 0.07, 0.12), (1.75, 0.20, 0.86, 0.875, 0.07, 0.13),
		(1.05, 0.20, 0.93, 0.875, 0.07, 0.12), (-1.55, 0.20, 1.00, 0.875, 0.07, 0.12), (-2.15, 0.25, 1.00, 0.85, 0.07, 0.12),
		(-2.25, 0.32, 0.97, 0.80, 0.06, 0.10)],
	"upper": [(1.05, 0.91, 0.93, 0.82, 0.80, 0.01), (0.22, 0.93, 1.45, 0.80, 0.67, 0.10), (-0.95, 0.95, 1.43, 0.81, 0.68, 0.10),
		(-1.68, 0.98, 1.01, 0.82, 0.77, 0.02)],
	"ws": (1.00, 0.26), "rear": (-1.00, -1.62), "side": [(0.82, -0.40), (-0.48, -1.30)],
	"head": (0.40, 0.75, 0.53, 0.65), "grille": (0.36, 0.47, 0.63), "tail": (0.48, 0.79, 0.74, 0.92),
	"bumpers": ((0.24, 0.47, 0.06), (0.26, 0.52, 0.06)), "plates": (0.30, (0.58, -2.254)),
	"strip": (0.70, 0.76), "axles": (1.38, -1.30), "r": 0.31,
}


def van_extra(mb, gl, czl, gu, czu):
	"""Rear door windows, the door split and tall rear lamps on the van."""
	y = -2.285
	for sx in (-1, 1):
		mb.quad((sx * 0.06, y, 1.45), (sx * 0.74, y, 1.45), (sx * 0.74, y, 1.9), (sx * 0.06, y, 1.9), "Glass", (0, -1, 0))
	mb.quad((-0.01, -2.306, 0.4), (0.01, -2.306, 0.4), (0.01, -2.306, 1.98), (-0.01, -2.306, 1.98), "Trim", (0, -1, 0))
	# sliding-door rail and roof rack bars
	for sx in (-1, 1):
		cube(mb, (sx * 0.9, -0.35, 1.5), (sx * 0.93, -1.3, 1.53), "Trim")
	for yb in (-0.4, -1.8):
		cube(mb, (-0.82, yb - 0.03, 2.08), (0.82, yb + 0.03, 2.13), "Trim")


CAR_VAN = {
	"lower": [(2.30, 0.34, 0.80, 0.84, 0.06, 0.10), (2.22, 0.26, 0.92, 0.90, 0.07, 0.14), (1.90, 0.24, 1.02, 0.93, 0.07, 0.14),
		(1.45, 0.24, 1.06, 0.93, 0.07, 0.12), (-2.20, 0.26, 1.08, 0.93, 0.07, 0.10), (-2.30, 0.32, 1.06, 0.90, 0.06, 0.08)],
	"upper": [(1.45, 1.04, 1.06, 0.90, 0.88, 0.01), (0.70, 1.06, 2.0, 0.90, 0.85, 0.14), (-2.14, 1.07, 2.08, 0.90, 0.86, 0.14),
		(-2.28, 1.07, 2.00, 0.90, 0.85, 0.10)],
	"ws": (1.40, 0.74), "rear": None, "side": [(1.22, -0.05)], "side_p": (0.12, 0.85),
	"head": (0.45, 0.82, 0.64, 0.80), "grille": (0.40, 0.56, 0.76), "tail": (0.74, 0.89, 0.55, 1.0),
	"bumpers": ((0.26, 0.54, 0.07), (0.26, 0.52, 0.07)), "plates": (0.32, (0.60, -2.304)),
	"strip": (0.60, 0.70), "axles": (1.50, -1.30), "r": 0.33, "mirror_mat": "Trim", "extra": van_extra,
}


def maluch_extra(mb, gl, czl, gu, czu):
	"""Fiat 126p details: round chrome-ringed headlamps, rear engine-lid vents."""
	for sx in (-1, 1):
		mb.tube((sx * 0.4, 1.44, 0.5), (sx * 0.4, 1.545, 0.5), 0.085, "Steel", segs=12, caps=False)
		mb.disc((sx * 0.4, 1.547, 0.5), 0.07, "Headlight", normal=(0, 1, 0), segs=12)
		mb.disc((sx * 0.62, 1.47, 0.42), 0.035, "SignalAmber", normal=(0, 1, 0), segs=6)
	ys = [s[0] for s in MALUCH["lower"]]
	for k in range(5):
		y = -1.08 - k * 0.07
		s = s_of_y(ys, y)
		decal(mb, gl, s, s + 0.06, 5.25, 5.75, "Trim", czl, off=0.004)


MALUCH = {
	"lower": [(1.525, 0.32, 0.58, 0.58, 0.06, 0.08), (1.47, 0.25, 0.70, 0.64, 0.08, 0.14), (1.25, 0.22, 0.78, 0.68, 0.09, 0.18),
		(0.90, 0.22, 0.82, 0.69, 0.09, 0.18), (0.40, 0.22, 0.85, 0.69, 0.09, 0.16), (-1.00, 0.22, 0.86, 0.69, 0.09, 0.16),
		(-1.35, 0.24, 0.84, 0.67, 0.09, 0.18), (-1.48, 0.28, 0.78, 0.63, 0.08, 0.14), (-1.525, 0.34, 0.70, 0.57, 0.06, 0.08)],
	"upper": [(0.40, 0.83, 0.85, 0.65, 0.63, 0.01), (-0.08, 0.84, 1.30, 0.64, 0.55, 0.16), (-0.40, 0.84, 1.33, 0.645, 0.56, 0.17),
		(-0.75, 0.85, 1.30, 0.645, 0.56, 0.16), (-1.15, 0.85, 0.88, 0.64, 0.60, 0.02)],
	"nc": 3,
	"ws": (0.36, -0.05), "rear": (-0.80, -1.10), "side": [(0.22, -0.60), (-0.68, -1.0)],
	"head": None, "grille": None, "tail": (0.36, 0.54, 0.48, 0.64),
	"bumpers": ((0.30, 0.38, 0.05), (0.32, 0.40, 0.05)), "bumper_mat": "Steel", "bumper_in": 0.04,
	"plates": (None, (0.42, -1.529)),
	"axles": (0.975, -0.865), "r": 0.265, "tw": 0.16, "arch": 0.05, "extra": maluch_extra, "mirror_mat": "Trim",
}


# ---------------------------------------------------------------- assembly
PIECES = {
	"Headframe": headframe, "ChurchSpire": church_spire, "Streetlamp": streetlamp, "StreetlampPark": streetlamp_park,
	"TrafficLight": traffic_light, "BusShelter": bus_shelter, "Billboard": billboard, "FestivalArch": festival_arch,
	"FestivalStage": festival_stage, "FlagPole": flag_pole, "Tent": tent,
	"CarHatch": lambda: car(CAR_HATCH), "CarSedan": lambda: car(CAR_SEDAN), "CarVan": lambda: car(CAR_VAN),
	"Maluch": lambda: car(MALUCH),
	"Bench": bench, "Fence": fence, "LevelCrossing": level_crossing,
	"LevelCrossingBoom": level_crossing_boom, "Beacon": beacon,
	"TrainCab": lambda: en57(True), "TrainCar": lambda: en57(False),
}
KEEP_ORIGIN = {"LevelCrossingBoom", "TrainCab", "TrainCar"}  # pivots: neither grounded nor centred
NOT_CENTRED = {"Fence", "LevelCrossing", "Streetlamp", "StreetlampPark", "TrafficLight", "FlagPole"}
CARS = {"CarHatch", "CarSedan", "CarVan", "Maluch"}


def finish(name, mb):
	"""Ground the prop (min z = 0) and centre it in plan unless it keeps a custom origin."""
	if name in KEEP_ORIGIN:
		lo = Vector((min(p.x for p in mb.v), min(p.y for p in mb.v), min(p.z for p in mb.v)))
		hi = Vector((max(p.x for p in mb.v), max(p.y for p in mb.v), max(p.z for p in mb.v)))
		return hi - lo
	lo = Vector((min(p.x for p in mb.v), min(p.y for p in mb.v), min(p.z for p in mb.v)))
	hi = Vector((max(p.x for p in mb.v), max(p.y for p in mb.v), max(p.z for p in mb.v)))
	shift = Vector((0, 0, -lo.z))
	if name not in NOT_CENTRED:
		shift.x, shift.y = -(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2
	mb.v = [p + shift for p in mb.v]
	return hi - lo


def preview_copy(ob, loc, rot=0.0, tints=None):
	"""A preview-only duplicate, optionally with recoloured copies of some materials."""
	d = kit.place(ob, loc, rot)
	if tints:
		me = ob.data.copy()
		for i, m in enumerate(me.materials):
			if m and m.name in tints:
				m2 = m.copy()
				sock = {s.identifier: s for s in m2.node_tree.nodes["Tint"].inputs}
				sock["A_Color"].default_value = (*srgb(tints[m.name]), 1.0)
				me.materials[i] = m2
		d.data = me
	return d


def main():
	for ob in list(bpy.data.objects):
		bpy.data.objects.remove(ob)
	objs = {}
	total = 0
	print("\nprop             size (Godot X x Y(up) x Z) m      tris")
	for name, fn in PIECES.items():
		mb = fn()
		size = finish(name, mb)
		t = mb.tris()
		total += t
		print(f"{name:16s} {size.x:6.2f} x {size.z:6.2f} x {size.y:6.2f}     {t:6d}")
		objs[name] = mb.emit(name, sharp_deg=50.0 if name in CARS else 35.0)
	print(f"{'TOTAL':16s} {'':30s} {total:6d}")
	used = sorted({m.name for ob in objs.values() for m in ob.data.materials}, key=list(kit.MATERIALS).index)
	print("materials:", ", ".join(used))
	kit.export_glb(OUT_GLB, list(objs.values()))
	out = kit.arg("--renders")
	if not out:
		return
	cam = kit.setup_preview(ground=1200.0, ground_colour=(0.16, 0.2, 0.13))
	for ob in objs.values():
		ob.hide_render = True
	ban = {"Banner": "#e8541e"}
	ban2 = {"Banner": "#d61f8c"}
	# landmarks
	preview_copy(objs["Headframe"], (-40, 0, 0))
	preview_copy(objs["ChurchSpire"], (0, 0, 0))
	preview_copy(objs["Beacon"], (30, 10, 0), tints={"Banner": "#ffcc00"})
	# festival
	preview_copy(objs["FestivalStage"], (0, 120, 0), tints=ban)
	preview_copy(objs["FestivalArch"], (0, 148, 0), tints=ban2)
	for k, x in enumerate((-14, -8, 8, 14)):
		preview_copy(objs["Tent"], (x, 140, 0), tints=ban if k % 2 else ban2)
	for k, x in enumerate((-11, -5, 5, 11)):
		preview_copy(objs["FlagPole"], (x, 152, 0), tints=ban2 if k % 2 else ban)
	preview_copy(objs["Billboard"], (22, 138, 0), rot=-0.6, tints={"Banner": "#2a7de1"})
	# street
	Y = 250
	preview_copy(objs["LevelCrossing"], (-17, Y, 0))
	boom = preview_copy(objs["LevelCrossingBoom"], (-17, Y + 0.34, 1.0))
	boom.rotation_euler = (0, math.radians(-80), 0)
	preview_copy(objs["TrainCab"], (-60, Y + 21.2, 0))
	preview_copy(objs["TrainCar"], (-60, Y, 0))
	preview_copy(objs["TrainCab"], (-60, Y - 21.2, 0), rot=math.pi)
	preview_copy(objs["Streetlamp"], (-8, Y, 0))
	preview_copy(objs["StreetlampPark"], (-5, Y, 0))
	preview_copy(objs["TrafficLight"], (-2.5, Y, 0))
	preview_copy(objs["BusShelter"], (1.5, Y, 0))
	preview_copy(objs["Bench"], (5.2, Y, 0))
	for k in range(3):
		preview_copy(objs["Fence"], (7.0 + k * FENCE_L, Y, 0))
	# cars
	Yc = 350
	paints = {"CarHatch": "#c0182a", "CarSedan": "#2c5aa8", "CarVan": "#f0f0f0", "Maluch": "#e2b23a"}
	for k, name in enumerate(("CarHatch", "CarSedan", "CarVan", "Maluch")):
		preview_copy(objs[name], (-7.5 + k * 5.0, Yc, 0), tints={"Paint": paints[name]})
		preview_copy(objs[name], (-9.0 + k * 6.0, Yc + 20, 0), rot=-math.pi / 2, tints={"Paint": paints[name]})
	R = lambda f, e, t, fov=50: kit.render(cam, os.path.join(out, f), e, t, fov)  # noqa: E731
	R("landmarks.png", (5, 95, 14), (-6, 0, 24), 55)
	R("headframe.png", (-8, 50, 16), (-40, 0, 21), 60)
	R("headframe_side.png", (-95, -10, 16), (-40, -2, 20), 55)
	R("church.png", (22, 32, 8), (0, 0, 27), 62)
	R("festival.png", (20, 178, 7), (0, 132, 5), 58)
	R("street.png", (2, 262, 3.5), (0, 250, 2.2), 75)
	R("lamps.png", (2.0, 251.5, 7.0), (-6.5, 251.0, 6.0), 55)
	R("crossing.png", (-12, 258, 3.0), (-15, 250, 1.6), 55)
	R("train.png", (-48, 290, 4.5), (-60, 268, 2.0), 55)
	R("train_side.png", (-30, 250, 3.0), (-60, 250, 2.0), 70)
	R("maluch.png", (11, 354.5, 1.8), (7.5, Yc, 0.6), 50)
	R("hatch.png", (-11, 345.5, 1.8), (-7.5, Yc, 0.7), 50)
	R("cars_front.png", (8, 360, 2.6), (0, Yc, 0.6), 50)
	R("cars_rear.png", (-8, 340, 2.6), (0, Yc, 0.6), 50)
	R("cars_side.png", (0, Yc + 20 - 15, 1.2), (0, Yc + 20, 0.8), 55)


main()
