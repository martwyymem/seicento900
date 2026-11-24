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
	"Alloy": (srgb("#b6bcc4"), 0.24, 0.76, {}),
	"DarkTrim": (srgb("#1a1c20"), 0.58, 0.05, {}),
	"Tyre": (srgb("#131416"), 0.85, 0.0, {}),
	"Plate": (srgb("#eeefe9"), 0.45, 0.0, {}),
	"Spectator": ((1.0, 1.0, 1.0), 0.85, 0.0, {}),
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
	"""3.9 m festival feather flag on a cross-foot base (Banner streams towards +X, face towards +Y)."""
	mb = MB()
	for a in range(4):
		ang = a * math.pi / 2 + math.pi / 4
		bar(mb, (0, 0, 0.04), (0.38 * math.cos(ang), 0.38 * math.sin(ang), 0.04), 0.045, "Trim")
	lathe_p(mb, [(0.0, 0.14), (0.10, 0.14), (0.14, 0.04)], 8, "Trim")
	mb.tube((0, 0, 0.08), (0, 0, 3.15), 0.024, "Steel", segs=6, caps=False)
	top = [Vector((0, 0, 3.15))]
	for k in range(1, 7):
		a = math.pi / 2 * k / 6
		top.append(Vector((0.36 - 0.36 * math.cos(a), 0, 3.15 + 0.75 * math.sin(a))))
	for a, b in zip(top, top[1:]):
		mb.tube(a, b, 0.018, "Steel", segs=5, caps=False)
	# the flag runs along a spine (up the pole, then round the bent top), its width set by w(t)
	spine = [Vector((0.03, 0, 0.85 + 2.30 * k / 8)) for k in range(8)] + [p + Vector((0.03, 0, 0)) for p in top]
	lens = [0.0]
	for a, b in zip(spine, spine[1:]):
		lens.append(lens[-1] + (b - a).length)
	outerp = []
	for k, p in enumerate(spine):
		t = lens[k] / lens[-1]
		d = (spine[min(k + 1, len(spine) - 1)] - spine[max(k - 1, 0)]).normalized()
		w = (0.40 + 0.24 * math.sin(min(1.0, t / 0.35) * math.pi / 2)) * (1.0 if t < 0.7 else max(0.05, 1 - (t - 0.7) / 0.3))
		outerp.append(p + Vector((d.z, 0, -d.x)) * w + Vector((0, 0, -0.20 * (1 - t) if k == 0 else 0)))
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


def crowd_barrier():
	"""2.5 m wide x 1.1 m tall galvanised festival pedestrian barrier with a sponsor banner skirt (Banner).
	Origin centred on the ground; runs along X from -1.25 to +1.25, front facing +Y (Godot -Z)."""
	mb = MB()
	hw, H = 1.25, 1.1
	# outer frame rails & splayed feet
	bar(mb, (-hw, 0, 0.14), (hw, 0, 0.14), 0.04, "Steel")
	bar(mb, (-hw, 0, H), (hw, 0, H), 0.045, "Steel")
	for sx in (-1, 1):
		x = sx * (hw - 0.03)
		bar(mb, (x, 0, 0.12), (x, 0, H), 0.042, "Steel")
		# splayed legs sitting on the ground
		bar(mb, (x - sx * 0.12, -0.28, 0.02), (x - sx * 0.12, 0.28, 0.02), 0.045, "Steel")
		bar(mb, (x - sx * 0.12, -0.22, 0.02), (x - sx * 0.12, 0.0, 0.16), 0.035, "Steel")
		bar(mb, (x - sx * 0.12, 0.22, 0.02), (x - sx * 0.12, 0.0, 0.16), 0.035, "Steel")
	# vertical pickets visible at edges/back
	for k in range(7):
		x = -hw + 0.22 + k * (2.0 * hw - 0.44) / 6.0
		bar(mb, (x, 0, 0.15), (x, 0, H - 0.02), 0.022, "Steel")
	# festival sponsor skirt wrapped over the frame (tintable Banner)
	cube(mb, (-hw + 0.06, -0.028, 0.22), (hw - 0.06, 0.028, H - 0.05), "Banner")
	return mb


def inflatable_arch():
	"""Chunky Forza Horizon style inflatable race arch: 13.4 m clear inner width (legs at +-7.2 m),
	7.2 m top height (5.6 m underside clearance). Curved inflated tube in Banner (tintable) with Trim bases."""
	mb = MB()
	lx = 7.2
	h_leg = 5.4
	r_tube = 0.82
	segs = 8
	# build a smooth arch spine from left foot -> left shoulder -> crown -> right shoulder -> right foot
	spine = [
		(-lx, 0.0, 0.2),
		(-lx, 0.0, 2.8),
		(-lx, 0.0, h_leg - 0.3),
		(-lx + 0.55, 0.0, h_leg + 0.85),
		(-lx + 1.8, 0.0, h_leg + 1.45),
		(0.0, 0.0, h_leg + 1.65),
		(lx - 1.8, 0.0, h_leg + 1.45),
		(lx - 0.55, 0.0, h_leg + 0.85),
		(lx, 0.0, h_leg - 0.3),
		(lx, 0.0, 2.8),
		(lx, 0.0, 0.2),
	]
	radii = [0.92, 0.86, 0.82, 0.84, 0.86, 0.90, 0.86, 0.84, 0.82, 0.86, 0.92]
	rings = []
	for idx, p in enumerate(spine):
		pv = Vector(p)
		if idx == 0:
			t = (Vector(spine[1]) - pv).normalized()
		elif idx == len(spine) - 1:
			t = (pv - Vector(spine[-2])).normalized()
		else:
			t = (Vector(spine[idx + 1]) - Vector(spine[idx - 1])).normalized()
		# cross-section lies in plane spanned by Y and (Y x t)
		v_y = Vector((0, 1, 0))
		v_in = v_y.cross(t).normalized()
		r = radii[idx]
		ring_pts = []
		for k in range(segs):
			a = 2.0 * math.pi * k / segs + math.pi / segs
			ring_pts.append(pv + (v_in * math.cos(a) * r + v_y * math.sin(a) * r * 0.82))
		rings.append(ring_pts)
	ids = [[mb.vert(p) for p in row] for row in rings]
	for i in range(len(rings) - 1):
		c_mid = (Vector(spine[i]) + Vector(spine[i + 1])) * 0.5
		for k in range(segs):
			k2 = (k + 1) % segs
			mb.face([ids[i][k], ids[i][k2], ids[i + 1][k2], ids[i + 1][k]], "Banner", lambda q, c=c_mid: q - c)
	# heavy ballast feet, side blowers, wrapped racing bands & branded sponsor leg panels
	for sx in (-1, 1):
		cube(mb, (sx * lx - 1.05, -0.95, 0.0), (sx * lx + 1.05, 0.95, 0.28), "Trim", skip=("-z",))
		cube(mb, (sx * (lx + 0.85), -0.4, 0.0), (sx * (lx + 1.5), 0.4, 0.65), "Trim", skip=("-z",))
		# contrasting white & dark racing collar stripes wrapping the inflatable legs
		for z0, z1, mat_b in ((0.55, 0.82, "Sign"), (0.82, 1.02, "Trim"), (4.15, 4.40, "Trim"), (4.40, 4.72, "Sign")):
			rb = 0.88 if z0 < 1.5 else 0.85
			band_lo = [mb.vert(Vector((sx * lx + math.cos(2 * math.pi * k / segs + math.pi / segs) * rb,
				math.sin(2 * math.pi * k / segs + math.pi / segs) * rb * 0.82, z0))) for k in range(segs)]
			band_hi = [mb.vert(Vector((sx * lx + math.cos(2 * math.pi * k / segs + math.pi / segs) * rb,
				math.sin(2 * math.pi * k / segs + math.pi / segs) * rb * 0.82, z1))) for k in range(segs)]
			cm = Vector((sx * lx, 0.0, (z0 + z1) * 0.5))
			for k in range(segs):
				k2 = (k + 1) % segs
				mb.face([band_lo[k], band_lo[k2], band_hi[k2], band_hi[k]], mat_b, lambda q, c=cm: q - c)
		# branded sponsor badge plates on both faces of each leg (white panel + dark bars + red stripe + lettering)
		for sy in (-1, 1):
			y = sy * 0.77
			y1 = y + sy * 0.014
			y2 = y + sy * 0.026
			ax_u = (-1, 0, 0) if sy > 0 else (1, 0, 0)
			mb.quad((sx * lx - 0.56, y, 1.25), (sx * lx + 0.56, y, 1.25),
				(sx * lx + 0.56, y, 3.75), (sx * lx - 0.56, y, 3.75), "Sign", (0, sy, 0))
			mb.quad((sx * lx - 0.56, y1, 3.35), (sx * lx + 0.56, y1, 3.35),
				(sx * lx + 0.56, y1, 3.75), (sx * lx - 0.56, y1, 3.75), "Trim", (0, sy, 0))
			mb.quad((sx * lx - 0.56, y1, 1.25), (sx * lx + 0.56, y1, 1.25),
				(sx * lx + 0.56, y1, 1.55), (sx * lx - 0.56, y1, 1.55), "Trim", (0, sy, 0))
			mb.quad((sx * lx - 0.56, y1, 2.96), (sx * lx + 0.56, y1, 2.96),
				(sx * lx + 0.56, y1, 3.24), (sx * lx - 0.56, y1, 3.24), "Red", (0, sy, 0))
			kit.text_mesh(mb, "FEST", (sx * lx, y2, 2.48), 0.34, "Trim", axis_u=ax_u, axis_v=(0, 0, 1))
			kit.text_mesh(mb, "1100", (sx * lx, y2, 1.92), 0.30, "Red", axis_u=ax_u, axis_v=(0, 0, 1))
	# top header banner plaque: high-contrast dark fascia, white racing borders, chequered trim & SEICENTO FEST lettering
	for sy in (-1, 1):
		y = sy * 0.79
		y1 = y + sy * 0.016
		y2 = y + sy * 0.032
		ax_u = (-1, 0, 0) if sy > 0 else (1, 0, 0)
		mb.quad((-4.6, y, h_leg + 0.96), (4.6, y, h_leg + 0.96), (4.6, y, h_leg + 2.24), (-4.6, y, h_leg + 2.24), "Sign", (0, sy, 0))
		mb.quad((-4.42, y1, h_leg + 1.12), (4.42, y1, h_leg + 1.12),
			(4.42, y1, h_leg + 2.08), (-4.42, y1, h_leg + 2.08), "Trim", (0, sy, 0))
		# chequered racing strip along the bottom edge of the header plaque
		cq = 0.44
		cn = 20
		cx0 = -cn * cq * 0.5
		for k in range(cn):
			cm_mat = "Sign" if k % 2 == 0 else "Trim"
			mb.quad((cx0 + k * cq, y2, h_leg + 0.98), (cx0 + (k + 1) * cq, y2, h_leg + 0.98),
				(cx0 + (k + 1) * cq, y2, h_leg + 1.16), (cx0 + k * cq, y2, h_leg + 1.16), cm_mat, (0, sy, 0))
		kit.text_mesh(mb, "SEICENTO FEST", (0.0, y2, h_leg + 1.64), 0.72, "Sign", axis_u=ax_u, axis_v=(0, 0, 1))
	for x in (-3.2, 0.0, 3.2):
		mb.quad((x - 0.25, -0.18, h_leg + 0.74), (x + 0.25, -0.18, h_leg + 0.74),
			(x + 0.25, 0.18, h_leg + 0.74), (x - 0.25, 0.18, h_leg + 0.74), "Lamp", (0, 0, -1))
	return mb


def merch_stall():
	"""4.4 x 2.6 m festival food / merch booth: dark frame, timber counter facing +Y (Godot -Z),
	sloped tintable Banner awning, Sign menu fascia, and warm Lamp counter strip for night."""
	mb = MB()
	hw, hd = 2.2, 1.3
	H_back, H_front = 2.65, 3.05
	# floor deck & rear/side enclosure
	cube(mb, (-hw, -hd, 0.0), (hw, hd, 0.10), "Trim", skip=("-z",))
	cube(mb, (-hw, -hd, 0.10), (hw, -hd + 0.10, H_back), "Trim")
	for sx in (-1, 1):
		x0, x1 = sorted((sx * (hw - 0.10), sx * hw))
		cube(mb, (x0, -hd, 0.10), (x1, hd - 0.35, 1.05), "Trim")
		bar(mb, (sx * (hw - 0.06), hd - 0.08, 0.10), (sx * (hw - 0.06), hd - 0.08, H_front - 0.1), 0.07, "Steel")
		bar(mb, (sx * (hw - 0.06), -hd + 0.06, 0.10), (sx * (hw - 0.06), -hd + 0.06, H_back), 0.07, "Steel")
	# front counter (wood top + Banner apron)
	cube(mb, (-hw + 0.06, hd - 0.55, 0.10), (hw - 0.06, hd - 0.10, 0.96), "Banner")
	cube(mb, (-hw + 0.02, hd - 0.62, 0.96), (hw - 0.02, hd + 0.12, 1.04), "Wood")
	# back menu signboard
	mb.quad((-1.7, -hd + 0.12, 1.45), (1.7, -hd + 0.12, 1.45), (1.7, -hd + 0.12, 2.35), (-1.7, -hd + 0.12, 2.35), "Sign", (0, 1, 0))
	# sloped festival roof & front valance (Banner)
	mb.quad((-hw - 0.22, -hd - 0.18, H_back), (hw + 0.22, -hd - 0.18, H_back),
		(hw + 0.22, hd + 0.45, H_front), (-hw - 0.22, hd + 0.45, H_front), "Banner", (0, -0.15, 1))
	# roof fascia valance + signboard header
	cube(mb, (-hw - 0.22, hd + 0.40, H_front - 0.36), (hw + 0.22, hd + 0.47, H_front + 0.02), "Banner")
	cube(mb, (-hw + 0.15, hd + 0.46, H_front - 0.28), (hw - 0.15, hd + 0.50, H_front - 0.04), "Sign")
	# warm glowing strip under the awning for night atmosphere
	mb.quad((-hw + 0.25, hd - 0.25, H_front - 0.38), (hw - 0.25, hd - 0.25, H_front - 0.38),
		(hw - 0.25, hd + 0.10, H_front - 0.38), (-hw + 0.25, hd + 0.10, H_front - 0.38), "Lamp", (0, 0, -1))
	return mb


def sponsor_flag():
	"""3.3 m angled festival feather flag on a weighted base (origin at pole foot, flag streams +X)."""
	mb = MB()
	lathe_p(mb, [(0.0, 0.20), (0.07, 0.20), (0.10, 0.04)], 8, "Trim")
	mb.tube((0, 0, 0.06), (0, 0, 2.68), 0.022, "Steel", segs=6, caps=False)
	top = [Vector((0, 0, 2.68))]
	for k in range(1, 6):
		a = math.pi / 2 * k / 5
		top.append(Vector((0.32 - 0.32 * math.cos(a), 0, 2.68 + 0.62 * math.sin(a))))
	for a, b in zip(top, top[1:]):
		mb.tube(a, b, 0.016, "Steel", segs=5, caps=False)
	spine = [Vector((0.025, 0, 0.72 + 1.96 * k / 6)) for k in range(6)] + [p + Vector((0.025, 0, 0)) for p in top]
	lens = [0.0]
	for a, b in zip(spine, spine[1:]):
		lens.append(lens[-1] + (b - a).length)
	outerp = []
	for k, p in enumerate(spine):
		t = lens[k] / lens[-1]
		d = (spine[min(k + 1, len(spine) - 1)] - spine[max(k - 1, 0)]).normalized()
		w = (0.36 + 0.20 * math.sin(min(1.0, t / 0.35) * math.pi / 2)) * (1.0 if t < 0.7 else max(0.05, 1.0 - (t - 0.7) / 0.3))
		outerp.append(p + Vector((d.z, 0, -d.x)) * w + Vector((0, 0, -0.16 * (1.0 - t) if k == 0 else 0)))
	for k in range(len(spine) - 1):
		mb.quad(spine[k], spine[k + 1], outerp[k + 1], outerp[k], "Banner", (0, 1, 0))
	return mb


def _spectator_limb(mb, a, b, r0, r1, col_a, col_b, segs=5):
	"""Tapered low-poly limb segment from a to b with per-end vertex colour encoding (part, anim, side)."""
	a, b = Vector(a), Vector(b)
	axis = (b - a).normalized()
	helper = Vector((0, 1, 0)) if abs(axis.y) < 0.9 else Vector((1, 0, 0))
	u = axis.cross(helper).normalized()
	v = axis.cross(u)
	ra = [mb.vert(a + (u * math.cos(2 * math.pi * k / segs) + v * math.sin(2 * math.pi * k / segs)) * r0, col_a) for k in range(segs)]
	rb = [mb.vert(b + (u * math.cos(2 * math.pi * k / segs) + v * math.sin(2 * math.pi * k / segs)) * r1, col_b) for k in range(segs)]
	mid = (a + b) * 0.5
	for k in range(segs):
		k2 = (k + 1) % segs
		mb.face([ra[k], ra[k2], rb[k2], rb[k]], "Spectator", lambda q: (q - mid) - axis * (q - mid).dot(axis))
	mb.face(ra, "Spectator", -axis)
	mb.face(rb, "Spectator", axis)


def spectator(pose="stand"):
	"""Low-poly standing festival spectator (~1.76 m tall, facing +Y -> Godot -Z).
	Vertex colour encodes shader channels:
	  R: body part (0.0 shirt, 0.25 skin, 0.50 trousers/shoes, 0.75 hair/cap, 1.0 phone screen)
	  G: animation weight (0.0 feet/hips, 0.35 torso/head, 0.65..1.0 waving arms/hands)
	  B: lateral side (0.0 left arm, 0.5 centre body, 1.0 right arm)."""
	mb = MB()
	# legs (hip z=0.86 down to ground z=0.0)
	leg_spread = 0.14 if pose == "cheer" else 0.12
	for sx in (-1, 1):
		_spectator_limb(mb, (sx * leg_spread, 0.0, 0.0), (sx * 0.11, 0.0, 0.86), 0.078, 0.095,
			(0.50, 0.0, 0.5), (0.50, 0.05, 0.5), segs=5)
	# torso (shirt: waist z=0.84 to shoulders z=1.43, slightly chunky silhouette for mid-range readability)
	mb.box((-0.23, -0.125, 0.84), (0.23, 0.135, 1.43), "Spectator", col=(0.0, 0.30, 0.5))
	# head (skin: z=1.45..1.69) and hair/cap crown (z=1.62..1.76)
	mb.box((-0.115, -0.115, 1.45), (0.115, 0.115, 1.69), "Spectator", col=(0.25, 0.42, 0.5))
	mb.box((-0.122, -0.122, 1.62), (0.122, 0.13, 1.76), "Spectator", col=(0.75, 0.45, 0.5))
	# cap brim forward (+Y)
	mb.box((-0.105, 0.09, 1.61), (0.105, 0.20, 1.645), "Spectator", col=(0.75, 0.45, 0.5))
	# arms per pose
	if pose == "cheer":
		# both arms raised high in a V cheer
		for sx in (-1, 1):
			side_b = 0.0 if sx < 0 else 1.0
			sh = (sx * 0.24, 0.0, 1.38)
			el = (sx * 0.39, 0.08, 1.69)
			hd = (sx * 0.45, 0.14, 1.98)
			_spectator_limb(mb, sh, el, 0.068, 0.056, (0.0, 0.45, side_b), (0.0, 0.78, side_b), segs=5)
			_spectator_limb(mb, el, hd, 0.054, 0.048, (0.25, 0.82, side_b), (0.25, 1.0, side_b), segs=5)
	elif pose == "wave":
		# left arm relaxed/bent, right arm raised high waving or holding a glowing phone
		_spectator_limb(mb, (-0.24, 0.0, 1.37), (-0.30, 0.05, 1.06), 0.066, 0.054, (0.0, 0.35, 0.0), (0.0, 0.45, 0.0), segs=5)
		_spectator_limb(mb, (-0.30, 0.05, 1.06), (-0.26, 0.12, 0.84), 0.052, 0.046, (0.25, 0.45, 0.0), (0.25, 0.50, 0.0), segs=5)
		_spectator_limb(mb, (0.24, 0.0, 1.38), (0.37, 0.12, 1.66), 0.068, 0.056, (0.0, 0.48, 1.0), (0.0, 0.80, 1.0), segs=5)
		_spectator_limb(mb, (0.37, 0.12, 1.66), (0.39, 0.22, 1.92), 0.052, 0.048, (0.25, 0.84, 1.0), (0.25, 1.0, 1.0), segs=5)
		# smartphone / lightstick in raised right hand (R=1.0 glows softly at night)
		mb.box((0.35, 0.21, 1.90), (0.43, 0.25, 2.02), "Spectator", col=(1.0, 1.0, 1.0))
	else:
		# standing casually, elbows slightly bent ready to clap/cheer
		for sx in (-1, 1):
			side_b = 0.0 if sx < 0 else 1.0
			sh = (sx * 0.24, 0.0, 1.37)
			el = (sx * 0.29, 0.05, 1.06)
			hd = (sx * 0.25, 0.18, 1.14)
			_spectator_limb(mb, sh, el, 0.066, 0.054, (0.0, 0.35, side_b), (0.0, 0.55, side_b), segs=5)
			_spectator_limb(mb, el, hd, 0.052, 0.046, (0.25, 0.60, side_b), (0.25, 0.80, side_b), segs=5)
	return mb


def executive(pose="stand"):
	"""Festival executive in a suit (~1.80 m, facing +Y -> Godot -Z); same vertex-colour encoding as spectator() so the
	spectator shader drives it in suit mode (jacket = instance tint, dark trousers, calmer idle). Part 1.0 is paper
	(clipboard / lanyard badge) and does not glow in suit mode.
	  stand: hands clasped in front; clip: left arm up holding a clipboard; talk: right arm gesturing."""
	mb = MB()
	for sx in (-1, 1):
		_spectator_limb(mb, (sx * 0.11, 0.0, 0.0), (sx * 0.10, 0.0, 0.88), 0.074, 0.088, (0.50, 0.0, 0.5), (0.50, 0.04, 0.5), segs=5)
	# jacket: hip-length box over the trousers, shoulders z=1.43
	mb.box((-0.235, -0.13, 0.66), (0.235, 0.14, 1.43), "Spectator", col=(0.0, 0.25, 0.5))
	# shirt front stripe and tie read as dark trousers colour, lanyard badge as paper
	mb.box((-0.035, 0.139, 0.95), (0.035, 0.152, 1.40), "Spectator", col=(0.50, 0.25, 0.5))
	mb.box((-0.06, 0.139, 0.98), (0.06, 0.158, 1.12), "Spectator", col=(1.0, 0.25, 0.5))
	mb.box((-0.115, -0.115, 1.45), (0.115, 0.115, 1.69), "Spectator", col=(0.25, 0.40, 0.5))
	mb.box((-0.122, -0.122, 1.62), (0.122, 0.12, 1.75), "Spectator", col=(0.75, 0.40, 0.5))
	arms = {
		"stand": [((-1), [(-0.24, 0.0, 1.37), (-0.27, 0.07, 1.08), (-0.07, 0.20, 1.02)]),
			((1), [(0.24, 0.0, 1.37), (0.27, 0.07, 1.08), (0.07, 0.20, 1.02)])],
		"clip": [((-1), [(-0.24, 0.0, 1.37), (-0.30, 0.10, 1.12), (-0.12, 0.26, 1.28)]),
			((1), [(0.24, 0.0, 1.37), (0.28, 0.02, 1.05), (0.27, 0.06, 0.78)])],
		"talk": [((-1), [(-0.24, 0.0, 1.37), (-0.30, 0.03, 1.08), (-0.20, 0.10, 0.92)]),
			((1), [(0.24, 0.0, 1.38), (0.40, 0.12, 1.16), (0.36, 0.30, 1.38)])],
	}[pose]
	for sx, (sh, el, hd) in arms:
		side_b = 0.0 if sx < 0 else 1.0
		_spectator_limb(mb, sh, el, 0.064, 0.054, (0.0, 0.30, side_b), (0.0, 0.45, side_b), segs=5)
		_spectator_limb(mb, el, hd, 0.052, 0.046, (0.25, 0.50, side_b), (0.25, 0.65, side_b), segs=5)
	if pose == "clip":
		mb.box((-0.17, 0.25, 1.15), (0.01, 0.28, 1.43), "Spectator", col=(1.0, 0.8, 0.0))
	return mb


def festival_trailer():
	"""Organisers' trailer, 8.4 x 2.6 x 3.3 m: white box body on a tandem axle with a SEICENTO FEST livery (tintable Banner
	stripe), a serving hatch, awning on two posts and a table on the service side (+Y -> Godot -Z, towards the road),
	door at the +X end and the tow bar beyond it; the long +Y side faces the road."""
	mb = MB()
	hl, hw = 4.2, 1.3
	z0, z1 = 0.55, 3.0
	# chassis, wheels, tow bar, stabiliser feet
	cube(mb, (-hl + 0.4, -hw + 0.2, 0.40), (hl - 0.2, hw - 0.2, z0), "Trim")
	bar(mb, (hl - 0.2, 0, 0.5), (hl + 1.6, 0, 0.62), 0.14, "Trim")
	cube(mb, (hl + 1.45, -0.09, 0.55), (hl + 1.75, 0.09, 0.80), "Steel")
	for ax in (-0.5, 0.45):
		for sy in (-1, 1):
			y0, y1 = sorted((sy * (hw - 0.05), sy * (hw + 0.12)))
			mb.tube((ax, y0, 0.46), (ax, y1, 0.46), 0.46, "Tyre", segs=14)
			mb.tube((ax, sy * (hw + 0.11), 0.46), (ax, sy * (hw + 0.125), 0.46), 0.24, "Alloy", segs=10)
	for x in (-hl + 0.7, hl - 0.7):
		for sy in (-1, 1):
			cube(mb, (x - 0.14, sy * (hw - 0.3) - 0.14, 0.0), (x + 0.14, sy * (hw - 0.3) + 0.14, 0.45), "Steel")
	# body shell with an overhanging roof
	cube(mb, (-hl, -hw, z0), (hl, hw, z1), "Sign")
	cube(mb, (-hl - 0.08, -hw - 0.08, z1), (hl + 0.08, hw + 0.08, z1 + 0.10), "Trim")
	cube(mb, (-2.6, -0.6, z1 + 0.10), (-1.2, 0.6, z1 + 0.42), "Steel")  # roof air conditioning
	cube(mb, (0.3, -0.5, z1 + 0.10), (1.5, 0.5, z1 + 0.22), "Steel")
	# livery stripe along both long sides, plus the SEICENTO FEST lettering
	for sy in (-1, 1):
		y = sy * (hw + 0.012)
		mb.quad((-hl, y, 0.95), (hl, y, 0.95), (hl, y, 1.28), (-hl, y, 1.28), "Banner", (0, sy, 0))
		mb.quad((-hl, y, 1.34), (hl, y, 1.34), (hl, y, 1.40), (-hl, y, 1.40), "Red", (0, sy, 0))
		au = (-1, 0, 0) if sy > 0 else (1, 0, 0)  # reads left to right seen from outside
		# service side: the lettering sits between the awning and the door; the far side has the whole wall
		tx, big, small = (1.45, 0.27, 0.15) if sy > 0 else (0.0, 0.46, 0.26)
		kit.text_mesh(mb, "SEICENTO FEST", (tx, y + sy * 0.004, 2.55), big, "Red", axis_u=au, axis_v=(0, 0, 1))
		kit.text_mesh(mb, "ORGANISERS", (tx, y + sy * 0.004, 2.55 - big * 1.1), small, "Trim", axis_u=au, axis_v=(0, 0, 1))
	# serving hatch (glass) with shutter frame, door and steps at the +X end
	y = hw + 0.012
	mb.quad((-2.9, y + 0.004, 1.50), (-0.3, y + 0.004, 1.50), (-0.3, y + 0.004, 2.30), (-2.9, y + 0.004, 2.30), "Glass", (0, 1, 0))
	cube(mb, (-3.0, hw, 1.44), (-0.2, hw + 0.05, 1.50), "Trim")
	cube(mb, (-3.0, hw, 2.30), (-0.2, hw + 0.05, 2.36), "Trim")
	cube(mb, (-3.0, hw, 1.50), (-2.94, hw + 0.05, 2.30), "Trim")
	cube(mb, (-0.26, hw, 1.50), (-0.2, hw + 0.05, 2.30), "Trim")
	cube(mb, (-3.0, hw, 1.40), (-0.2, hw + 0.45, 1.46), "Wood")  # counter
	mb.quad((3.0, y + 0.004, 0.62), (4.0, y + 0.004, 0.62), (4.0, y + 0.004, 2.45), (3.0, y + 0.004, 2.45), "Trim", (0, 1, 0))
	mb.quad((3.07, y + 0.008, 0.70), (3.93, y + 0.008, 0.70), (3.93, y + 0.008, 2.38), (3.07, y + 0.008, 2.38), "Sign", (0, 1, 0))
	cube(mb, (3.05, hw, 0.62), (3.95, hw + 0.7, 0.70), "Steel")
	cube(mb, (3.05, hw + 0.7, 0.28), (3.95, hw + 1.1, 0.34), "Steel")
	# awning over the hatch on two posts (sloping down away from the wall), tintable Banner
	ax0, ax1, ay = -3.3, 0.1, hw + 1.35
	mb.quad((ax0, hw, 2.85), (ax1, hw, 2.85), (ax1, ay, 2.45), (ax0, ay, 2.45), "Banner", (0, 0.2, 1))
	cube(mb, (ax0, ay - 0.02, 2.30), (ax1, ay + 0.04, 2.46), "Banner")
	for x in (ax0 + 0.1, ax1 - 0.1):
		mb.tube((x, ay - 0.05, 0.0), (x, ay - 0.05, 2.46), 0.04, "Steel", segs=6)
	mb.quad((ax0 + 0.2, hw + 0.25, 2.40), (ax1 - 0.2, hw + 0.25, 2.40), (ax1 - 0.2, ay - 0.2, 2.40), (ax0 + 0.2, ay - 0.2, 2.40), "Lamp", (0, 0, -1))
	# a pavilion table with two stools in front (the executives stand around it)
	tx, ty = -1.6, hw + 2.3
	mb.tube((tx, ty, 0.0), (tx, ty, 0.72), 0.07, "Steel", segs=6)
	mb.tube((tx, ty, 0.72), (tx, ty, 0.76), 0.50, "Wood", segs=12)
	mb.tube((tx, ty, 0.0), (tx, ty, 0.03), 0.30, "Trim", segs=10)
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


def _smoothstep(a, b, x):
	t = min(1.0, max(0.0, (x - a) / max(b - a, 1e-6)))
	return t * t * (3.0 - 2.0 * t)


def _pl_interp(pts, x):
	"""Piecewise-linear interpolation on sorted (x, y) pairs."""
	if x <= pts[0][0]:
		return pts[0][1]
	if x >= pts[-1][0]:
		return pts[-1][1]
	for i in range(len(pts) - 1):
		x0, y0 = pts[i]
		x1, y1 = pts[i + 1]
		if x0 <= x <= x1:
			return kit.lerp(y0, y1, (x - x0) / max(x1 - x0, 1e-6))
	return pts[-1][1]


def _add_real_wheel(mb, cx, cy, cz, r, width, side, segs=20, style="steel"):
	"""Clean round 3D tyre + recessed wheel dish/spokes facing `side` (+1 right, -1 left)."""
	hw = width * 0.5
	r_rim = r * 0.62
	r_sh = r * 0.94
	r_hub = r * 0.18
	# Profile along X in wheel-local coordinates (outer face towards +side)
	prof = [
		(-hw * 0.85, r_rim, "Tyre"),
		(-hw, r_rim + (r - r_rim) * 0.45, "Tyre"),
		(-hw * 0.90, r_sh, "Tyre"),
		(-hw * 0.64, r, "Tyre"),
		(+hw * 0.64, r, "Tyre"),
		(+hw * 0.90, r_sh, "Tyre"),
		(+hw, r_rim + (r - r_rim) * 0.45, "Tyre"),
		(+hw * 0.85, r_rim, "Alloy"),
		(+hw * 0.88, r_rim * 0.91, "Alloy"),
		(+hw * 0.56, r_rim * 0.84, "Alloy" if style == "steel" else "DarkTrim"),
		(+hw * 0.68, r_rim * 0.42, "Alloy"),
		(+hw * 0.74, r_hub, "DarkTrim"),
	]
	rings = []
	for lx, rad, _ in prof:
		x = cx + side * lx
		ring = [mb.vert((x, cy + rad * math.cos(2 * math.pi * k / segs), cz + rad * math.sin(2 * math.pi * k / segs)))
			for k in range(segs)]
		rings.append(ring)
	for i in range(len(prof) - 1):
		mat = prof[i][2]
		r0, r1 = rings[i], rings[i + 1]
		x0, rad0 = prof[i][0], prof[i][1]
		x1, rad1 = prof[i + 1][0], prof[i + 1][1]
		dx, dr = (x1 - x0) * side, rad1 - rad0
		for k in range(segs):
			k2 = (k + 1) % segs
			ang = 2 * math.pi * (k + 0.5) / segs
			# Outward normal from revolved profile tangent
			n_rad = dx * side
			n_x = -dr * side
			out = Vector((n_x, math.cos(ang) * n_rad, math.sin(ang) * n_rad))
			if out.length < 1e-6:
				out = Vector((side, 0, 0))
			mb.face([r0[k], r0[k2], r1[k2], r1[k]], mat, out)
	# Hub cap + inner backing disc
	mb.disc((cx + side * hw * 0.75, cy, cz), r_hub, "DarkTrim", normal=(side, 0, 0), segs=12)
	mb.disc((cx - side * hw * 0.85, cy, cz), r_rim, "DarkTrim", normal=(-side, 0, 0), segs=12)
	# Pressed steel wheel vent slots (classic Fiat 126p / commercial van steelies)
	holes = 8 if style == "steel" else 5
	hr = r_rim * 0.64
	hx = cx + side * hw * 0.62
	for k in range(holes):
		a = 2 * math.pi * k / holes + 0.2
		mb.disc((hx, cy + hr * math.cos(a), cz + hr * math.sin(a)), r_rim * 0.11, "DarkTrim", normal=(side, 0, 0), segs=6)


def _carved_body(mb, stations, prof_fn, face_mat_fn, axles, arch_r, wheel_z):
	"""Loft a smooth symmetric car body shell from nose (+Y) to tail (-Y) with carved wheel arches and dark wheelhouses."""
	# prof_fn(y) returns list of (x >= 0, z) points from bottom-centre -> rocker -> mid-side -> shoulder -> roof-edge -> roof-centre
	# We mirror around X=0 to form a closed cross-section per station.
	ys = sorted(stations, reverse=True)
	grid = []
	n_half = 0
	for y in ys:
		half = list(prof_fn(y))
		# Raise lower rocker points inside the wheel arch circles to carve real wheel openings.
		zb_arch = 0.0
		for ya in axles:
			dy = y - ya
			if abs(dy) < arch_r:
				zb_arch = max(zb_arch, wheel_z + math.sqrt(max(0.0, arch_r * arch_r - dy * dy)))
		if zb_arch > 0.0:
			# Raise rocker/lower-edge points (indices 1, 2) over the wheel arch, keeping floor centre (0) low.
			half_adj = []
			for idx, (x, z) in enumerate(half):
				if idx in (1, 2) and z < zb_arch:
					z = zb_arch
				half_adj.append((x, z))
			half = half_adj
		n_half = len(half)
		# Closed ring: right side bottom->top (0..n_half-1), then left side top->bottom (n_half-2..1)
		ring = [Vector((x, y, z)) for x, z in half] + [Vector((-x, y, z)) for x, z in reversed(half[1:-1])]
		grid.append(ring)

	ids = [[mb.vert(p) for p in row] for row in grid]
	n = len(grid[0])
	czs = [sum(p.z for p in row) / n for row in grid]
	for i in range(len(grid) - 1):
		ym = 0.5 * (ys[i] + ys[i + 1])
		zc = 0.5 * (czs[i] + czs[i + 1])
		for j in range(n):
			j2 = (j + 1) % n
			# Symmetric segment index 0..n_half-2 (0=underbody, 1=lower rocker, ..., n_half-2=roof)
			if j < n_half - 1:
				seg = j
			else:
				seg = n - 1 - j
			mat = face_mat_fn(ym, seg, i, j)
			mb.face([ids[i][j], ids[i][j2], ids[i + 1][j2], ids[i + 1][j]], mat,
				lambda q, zc=zc: Vector((q.x, 0.0, q.z - zc)))
	# Nose & tail caps
	mb.face(ids[0], face_mat_fn(ys[0], -1, 0, -1), (0, 1, 0))
	mb.face(ids[-1], face_mat_fn(ys[-1], -2, len(ys) - 1, -1), (0, -1, 0))

	# Dark wheelhouse liners behind each carved arch so you never see hollow air behind the wheels.
	for ya in axles:
		hw = prof_fn(ya)[3][0]
		for sx in (-1, 1):
			xi = sx * (hw - 0.30)
			xo = sx * (hw - 0.015)
			pts_arch = [(ya + (arch_r - 0.005) * math.cos(math.pi * k / 14),
				wheel_z + (arch_r - 0.005) * math.sin(math.pi * k / 14)) for k in range(15)]
			for k in range(len(pts_arch) - 1):
				y0, z0 = pts_arch[k]
				y1, z1 = pts_arch[k + 1]
				mb.quad((xi, y0, z0), (xi, y1, z1), (xo, y1, z1), (xo, y0, z0), "DarkTrim", (0, 0, -1))
			# Inner vertical wheelhouse backing wall
			back_pts = [(xi, y, z) for y, z in pts_arch] + [(xi, ya - arch_r, wheel_z - 0.08), (xi, ya + arch_r, wheel_z - 0.08)]
			mb.poly(back_pts, "DarkTrim", (sx, 0, 0))


def real_van():
	"""Realistic Polish panel van (Fiat Ducato II / Ford Transit Mk6 style): 4.96 x 2.16 (w/ mirrors) x 2.22 m."""
	mb = MB()
	# Coordinates: nose at +2.46, tail at -2.46 (4.92 m body + bumpers = 4.98 m), axles at +1.56 and -1.56 (3.12 m wb).
	axles = (1.56, -1.56)
	r_wheel = 0.34
	arch_r = 0.415

	# Profile curves along Y (tail -2.46 -> nose +2.46)
	w_pts = [(-2.46, 0.86), (-2.42, 0.94), (-2.30, 0.985), (-1.90, 0.995), (0.95, 0.995),
		(1.55, 0.99), (1.95, 0.975), (2.25, 0.94), (2.40, 0.87), (2.46, 0.78)]
	wsh_pts = [(-2.46, 0.84), (-2.40, 0.925), (-2.25, 0.965), (0.95, 0.965),
		(1.65, 0.955), (2.05, 0.93), (2.30, 0.88), (2.42, 0.82), (2.46, 0.75)]
	wr_pts = [(-2.46, 0.78), (-2.36, 0.85), (-2.15, 0.88), (0.80, 0.88),
		(1.15, 0.86), (1.55, 0.88), (2.00, 0.87), (2.35, 0.82), (2.46, 0.72)]
	zb_pts = [(-2.46, 0.34), (-2.30, 0.28), (-1.80, 0.26), (1.85, 0.26), (2.30, 0.29), (2.46, 0.34)]
	zsh_pts = [(-2.46, 1.18), (-2.30, 1.24), (0.55, 1.24), (1.28, 1.14), (1.56, 1.16),
		(1.80, 1.16), (2.15, 1.07), (2.38, 0.96), (2.46, 0.84)]
	zt_pts = [(-2.46, 2.02), (-2.42, 2.13), (-2.28, 2.20), (-1.80, 2.22), (0.72, 2.22),
		(0.95, 2.18), (1.15, 2.00), (1.42, 1.62), (1.68, 1.22), (1.98, 1.15), (2.28, 1.04), (2.42, 0.92), (2.46, 0.84)]

	def prof(y):
		w = _pl_interp(w_pts, y)
		wsh = _pl_interp(wsh_pts, y)
		wr = _pl_interp(wr_pts, y)
		zb = _pl_interp(zb_pts, y)
		zsh = _pl_interp(zsh_pts, y)
		zt = _pl_interp(zt_pts, y)
		zm = min(zb + 0.34, zsh - 0.08)
		# Segment indices: 0 floor, 1 rocker bevel, 2 lower flank, 3 upper flank, 4 belt step, 5 greenhouse/side, 6 roof rail, 7 roof crown
		z_rail = max(zsh + 0.02, zt - 0.10)
		if y > 1.68:
			# Bonnet region (no greenhouse)
			z_rail = max(zsh + 0.01, zt - 0.04)
		return [
			(0.0, zb),
			(w - 0.07, zb),
			(w - 0.015, zb + 0.07),
			(w, zm),
			(wsh, zsh),
			(kit.lerp(wsh, wr, 0.85), z_rail),
			(wr, zt - 0.03),
			(0.0, zt),
		]

	# Dense stations round the nose, windscreen, wheel arches and tail
	stations = [
		2.46, 2.42, 2.36, 2.26, 2.12, 1.97, 1.86, 1.74, 1.68,
		1.56, 1.44, 1.32, 1.18, 1.04, 0.92, 0.78, 0.62, 0.35, 0.0,
		-0.45, -0.95, -1.14, -1.28, -1.42, -1.56, -1.70, -1.84, -1.98,
		-2.20, -2.35, -2.42, -2.46,
	]
	# Add extra points on arch perimeters for round cutouts
	for ya in axles:
		for k in range(1, 7):
			stations.append(ya + arch_r * math.cos(math.pi * k / 7))
	stations = sorted(set(round(y, 4) for y in stations))

	def face_mat(ym, seg, i, j):
		if seg == 0:
			return "DarkTrim"
		# Windscreen on the sloped front upper face (y between 1.04 and 1.65, crown seg 6)
		if 1.04 <= ym <= 1.65 and seg == 6:
			return "Glass"
		# Cab front door windows (y between 0.66 and 1.44, side greenhouse seg 4)
		if 0.66 <= ym <= 1.44 and seg == 4:
			return "Glass"
		return "Paint"

	_carved_body(mb, stations, prof, face_mat, axles, arch_r, r_wheel)

	# A-pillars framing the windscreen + B-pillar + quarter vent bar + twin wipers
	for sx in (-1, 1):
		bar(mb, (sx * 0.89, 1.66, 1.22), (sx * 0.85, 1.03, 2.09), 0.068, "Paint")
		bar(mb, (sx * 0.94, 0.65, 1.24), (sx * 0.88, 0.65, 2.08), 0.065, "DarkTrim")
		bar(mb, (sx * 0.94, 1.35, 1.18), (sx * 0.90, 1.35, 1.56), 0.028, "DarkTrim")
	# Scuttle & twin wipers at base of windscreen
	cube(mb, (-0.82, 1.64, 1.19), (0.82, 1.74, 1.25), "DarkTrim")
	for x0, x1 in ((-0.65, -0.02), (0.04, 0.68)):
		bar(mb, (x0, 1.66, 1.25), (x1, 1.50, 1.46), 0.022, "DarkTrim")

	# Heavy commercial front bumper (tapered at corners) + lower intake + fog recesses + Polish front plate
	cube(mb, (-0.95, 2.12, 0.25), (0.95, 2.38, 0.62), "DarkTrim")
	cube(mb, (-0.88, 2.34, 0.25), (0.88, 2.50, 0.62), "DarkTrim")
	cube(mb, (-0.52, 2.47, 0.30), (0.52, 2.515, 0.44), "Rubber")  # lower intake
	cube(mb, (-0.27, 2.495, 0.43), (0.27, 2.512, 0.56), "DarkTrim")
	cube(mb, (-0.255, 2.505, 0.44), (0.255, 2.52, 0.55), "Plate")
	for sx in (-1, 1):
		cube(mb, (sx * 0.60, 2.45, 0.33), (sx * 0.78, 2.508, 0.43), "Headlight")

	# Slatted van grille + swept multi-element headlamps + amber outer corners
	cube(mb, (-0.46, 2.36, 0.63), (0.46, 2.465, 0.91), "DarkTrim")
	for z_slat in (0.68, 0.75, 0.82, 0.88):
		cube(mb, (-0.43, 2.455, z_slat - 0.012), (0.43, 2.478, z_slat + 0.012), "Alloy")
	mb.disc((0.0, 2.484, 0.77), 0.055, "Alloy", normal=(0, 1, 0), segs=12)
	for sx in (-1, 1):
		# Headlamp housing + bright inner reflector + outer amber indicator
		cube(mb, (sx * 0.47, 2.28, 0.65), (sx * 0.84, 2.445, 0.90), "Alloy")
		cube(mb, (sx * 0.49, 2.435, 0.67), (sx * 0.74, 2.462, 0.88), "Headlight")
		cube(mb, (sx * 0.74, 2.32, 0.67), (sx * 0.86, 2.452, 0.88), "SignalAmber")

	# Side plastic rubbing strips (classic Ducato/Transit lower body protection), door handles & sliding door rail
	for sx in (-1, 1):
		cube(mb, (sx * 0.99, -1.12, 0.44), (sx * 1.015, 1.12, 0.64), "DarkTrim")
		cube(mb, (sx * 0.975, -2.42, 0.44), (sx * 1.00, -1.98, 0.64), "DarkTrim")
		cube(mb, (sx * 0.985, 1.98, 0.44), (sx * 1.005, 2.26, 0.64), "DarkTrim")
		# Cab door handle + vertical shut line
		cube(mb, (sx * 0.97, 0.72, 1.04), (sx * 1.015, 0.86, 1.09), "DarkTrim")
		# Large commercial wing mirrors on dual arms
		bar(mb, (sx * 0.94, 1.44, 1.24), (sx * 1.07, 1.44, 1.24), 0.025, "DarkTrim")
		bar(mb, (sx * 0.94, 1.44, 1.46), (sx * 1.07, 1.44, 1.46), 0.025, "DarkTrim")
		cube(mb, (sx * 1.04, 1.37, 1.18), (sx * 1.10, 1.47, 1.54), "DarkTrim")
	# Sliding cargo door rail + handle on right (+X) side
	cube(mb, (0.975, -1.25, 1.20), (1.01, -0.10, 1.25), "DarkTrim")
	cube(mb, (0.97, 0.44, 1.04), (1.015, 0.56, 1.09), "DarkTrim")

	# Rear barn doors: twin windows, vertical centre split, tall pillar tail lamps, 3rd brake light, rear step bumper
	yr = -2.46
	for sx in (-1, 1):
		# Rear door window + dark gasket frame
		cube(mb, (sx * 0.06, yr - 0.012, 1.38), (sx * 0.72, yr + 0.02, 1.94), "DarkTrim")
		mb.quad((sx * 0.09, yr - 0.016, 1.41), (sx * 0.69, yr - 0.016, 1.41),
			(sx * 0.69, yr - 0.016, 1.91), (sx * 0.09, yr - 0.016, 1.91), "Glass", (0, -1, 0))
		# Tall Ducato/Transit vertical rear lamp clusters
		cube(mb, (sx * 0.76, yr - 0.03, 0.64), (sx * 0.92, yr + 0.06, 1.26), "Taillight")
		cube(mb, (sx * 0.77, yr - 0.036, 0.86), (sx * 0.91, yr - 0.02, 1.00), "SignalAmber")
		cube(mb, (sx * 0.77, yr - 0.036, 0.66), (sx * 0.91, yr - 0.02, 0.77), "Headlight")  # reverse light
	# Barn-door split line, handle, high 3rd brake light & rear licence plate
	cube(mb, (-0.012, yr - 0.014, 0.52), (0.012, yr + 0.01, 2.04), "DarkTrim")
	cube(mb, (0.06, yr - 0.035, 1.02), (0.14, yr, 1.15), "DarkTrim")
	cube(mb, (-0.18, yr - 0.025, 2.05), (0.18, yr + 0.02, 2.11), "Taillight")
	cube(mb, (-0.655, yr - 0.018, 0.79), (-0.125, yr + 0.01, 0.93), "DarkTrim")
	cube(mb, (-0.64, yr - 0.026, 0.80), (-0.14, yr - 0.01, 0.92), "Plate")
	# Rear step bumper + exhaust pipe
	cube(mb, (-0.93, yr - 0.07, 0.28), (0.93, yr + 0.16, 0.55), "DarkTrim")
	mb.tube((-0.55, yr + 0.15, 0.25), (-0.55, yr - 0.04, 0.24), 0.032, "Alloy", segs=8)

	# 4 commercial steel wheels sitting cleanly inside the carved arches
	for ya in axles:
		for sx in (-1, 1):
			_add_real_wheel(mb, sx * 0.86, ya, r_wheel, r_wheel, 0.21, sx, segs=20, style="steel")
	return mb


def real_maluch():
	"""Realistic Polski Fiat 126p (Maluch FL/EL): 3.06 x 1.50 (w/ mirrors) x 1.34 m, rear-engined classic."""
	mb = MB()
	# Coordinates: nose +1.53, tail -1.53 (3.06 m), wheelbase 1.84 m (axles +0.94, -0.90), 12" wheels (r = 0.255 m).
	axles = (0.94, -0.90)
	r_wheel = 0.255
	arch_r = 0.305

	w_pts = [(-1.53, 0.59), (-1.47, 0.655), (-1.30, 0.685), (-0.90, 0.69), (0.94, 0.69),
		(1.32, 0.68), (1.47, 0.65), (1.53, 0.58)]
	wsh_pts = [(-1.53, 0.57), (-1.45, 0.635), (-1.20, 0.665), (0.95, 0.665),
		(1.35, 0.655), (1.48, 0.625), (1.53, 0.56)]
	wr_pts = [(-1.53, 0.52), (-1.35, 0.57), (-1.12, 0.59), (-0.82, 0.57),
		(-0.20, 0.565), (0.06, 0.565), (0.48, 0.62), (1.05, 0.615), (1.45, 0.58), (1.53, 0.52)]
	zb_pts = [(-1.53, 0.28), (-1.38, 0.22), (-1.15, 0.20), (1.15, 0.20), (1.40, 0.23), (1.53, 0.28)]
	zsh_pts = [(-1.53, 0.72), (-1.45, 0.79), (-1.25, 0.84), (-0.80, 0.855), (0.48, 0.85),
		(0.95, 0.81), (1.35, 0.74), (1.48, 0.68), (1.53, 0.60)]
	zt_pts = [(-1.53, 0.72), (-1.47, 0.80), (-1.32, 0.86), (-1.14, 0.90), (-0.98, 1.11),
		(-0.82, 1.31), (-0.50, 1.335), (-0.15, 1.335), (0.08, 1.305), (0.28, 1.08), (0.48, 0.865),
		(0.95, 0.83), (1.35, 0.76), (1.49, 0.69), (1.53, 0.60)]

	def prof(y):
		w = _pl_interp(w_pts, y)
		wsh = _pl_interp(wsh_pts, y)
		wr = _pl_interp(wr_pts, y)
		zb = _pl_interp(zb_pts, y)
		zsh = _pl_interp(zsh_pts, y)
		zt = _pl_interp(zt_pts, y)
		zm = min(zb + 0.26, zsh - 0.08)
		in_cab = -1.12 <= y <= 0.46
		z_rail = max(zsh + 0.015, zt - (0.055 if in_cab else 0.025))
		return [
			(0.0, zb),
			(w - 0.055, zb),
			(w - 0.012, zb + 0.055),
			(w, zm),
			(wsh, zsh),
			(kit.lerp(wsh, wr, 0.88), z_rail),
			(wr, zt - 0.018),
			(0.0, zt),
		]

	stations = [
		1.53, 1.49, 1.43, 1.33, 1.20, 1.06, 0.94, 0.82, 0.68, 0.56, 0.48,
		0.38, 0.26, 0.14, 0.06, -0.10, -0.35, -0.58, -0.74, -0.82, -0.90,
		-1.02, -1.14, -1.26, -1.38, -1.47, -1.53,
	]
	for ya in axles:
		for k in range(1, 6):
			stations.append(ya + arch_r * math.cos(math.pi * k / 6))
	stations = sorted(set(round(y, 4) for y in stations))

	def face_mat(ym, seg, i, j):
		if seg == 0:
			return "DarkTrim"
		# Windscreen (y between 0.09 and 0.46, crown seg 6)
		if 0.09 <= ym <= 0.46 and seg == 6:
			return "Glass"
		# Rear window (y between -1.12 and -0.83, crown seg 6)
		if -1.12 <= ym <= -0.83 and seg == 6:
			return "Glass"
		# Side door window (-0.48..0.28) and rear quarter window (-0.98..-0.56), side greenhouse seg 4
		if (-0.48 <= ym <= 0.28 or -0.98 <= ym <= -0.56) and seg == 4:
			return "Glass"
		return "Paint"

	_carved_body(mb, stations, prof, face_mat, axles, arch_r, r_wheel)

	# Crisp thin A-pillars, B-pillars, C-pillars, drip rails & wipers (tucked cleanly into roof line)
	for sx in (-1, 1):
		bar(mb, (sx * 0.648, 0.46, 0.86), (sx * 0.578, 0.09, 1.275), 0.038, "Paint")
		bar(mb, (sx * 0.655, -0.52, 0.855), (sx * 0.578, -0.52, 1.285), 0.052, "Paint")
		bar(mb, (sx * 0.648, -1.12, 0.87), (sx * 0.578, -0.83, 1.275), 0.052, "Paint")
		# Quarter vent window bar in the front door
		bar(mb, (sx * 0.625, 0.14, 0.86), (sx * 0.585, 0.14, 1.23), 0.016, "DarkTrim")
		# Roof rain-gutter drip rails
		bar(mb, (sx * 0.575, 0.08, 1.275), (sx * 0.575, -0.82, 1.275), 0.014, "DarkTrim")
		# Lower FL/EL plastic sill/door trim & black door handle
		cube(mb, (sx * 0.685, -0.58, 0.26), (sx * 0.708, 0.62, 0.42), "DarkTrim")
		cube(mb, (sx * 0.675, -0.44, 0.77), (sx * 0.71, -0.32, 0.81), "DarkTrim")
	# Small square black wing mirrors (classic 126p FL/EL)
	for sx in (-1, 1):
		bar(mb, (sx * 0.66, 0.22, 0.87), (sx * 0.73, 0.22, 0.90), 0.018, "DarkTrim")
		cube(mb, (sx * 0.70, 0.19, 0.87), (sx * 0.77, 0.24, 0.96), "DarkTrim")
	# Wipers at windscreen base
	for x0, x1 in ((-0.46, -0.02), (0.04, 0.46)):
		bar(mb, (x0, 0.46, 0.875), (x1, 0.34, 1.02), 0.015, "DarkTrim")

	# Front fascia: classic Fiat 126p rectangular headlamps, amber corner indicators, central Fiat badge, wrap bumper, front plate
	yf = 1.53
	for sx in (-1, 1):
		# Recessed black bezel + rectangular headlamp glass + amber side indicator
		cube(mb, (sx * 0.34, yf - 0.04, 0.47), (sx * 0.58, yf + 0.008, 0.60), "DarkTrim")
		cube(mb, (sx * 0.355, yf - 0.01, 0.485), (sx * 0.53, yf + 0.016, 0.585), "Headlight")
		cube(mb, (sx * 0.53, yf - 0.02, 0.485), (sx * 0.59, yf + 0.014, 0.585), "SignalAmber")
		# Small side indicator repeater on the front wing
		cube(mb, (sx * 0.68, 0.78, 0.58), (sx * 0.70, 0.84, 0.62), "SignalAmber")
	# Classic Polski Fiat nose badge bar
	cube(mb, (-0.11, yf - 0.01, 0.53), (0.11, yf + 0.012, 0.58), "DarkTrim")
	cube(mb, (-0.09, yf + 0.01, 0.542), (0.09, yf + 0.016, 0.568), "Alloy")
	# Chunky black FL/EL front wrap-around bumper + Polish front plate
	cube(mb, (-0.67, yf - 0.20, 0.28), (0.67, yf + 0.06, 0.42), "DarkTrim")
	cube(mb, (-0.23, yf + 0.055, 0.295), (0.23, yf + 0.068, 0.395), "Plate")

	# Rear: horizontal engine-lid cooling louvres, vertical-ish rectangular 126p tail lamps, rear plate, bumper, single exhaust
	yr = -1.53
	# Iconic rear engine-deck louvre vents (angled dark slats on the rear deck below the back window)
	for k in range(6):
		y_v = -1.16 - k * 0.048
		z_v = _pl_interp(zt_pts, y_v) + 0.006
		cube(mb, (-0.42, y_v - 0.014, z_v - 0.008), (0.42, y_v + 0.014, z_v + 0.008), "DarkTrim")
	# Vertical cooling slits on the upper rear valance
	for k in range(5):
		z_s = 0.63 + k * 0.024
		cube(mb, (-0.30, yr - 0.008, z_s), (0.30, yr + 0.01, z_s + 0.012), "DarkTrim")
	# Rear tail lamps (classic Fiat 126p rectangular clusters: red tail/brake + amber outer indicator)
	for sx in (-1, 1):
		cube(mb, (sx * 0.36, yr - 0.025, 0.47), (sx * 0.57, yr + 0.04, 0.62), "Taillight")
		cube(mb, (sx * 0.49, yr - 0.030, 0.54), (sx * 0.565, yr - 0.01, 0.615), "SignalAmber")
		cube(mb, (sx * 0.37, yr - 0.030, 0.475), (sx * 0.45, yr - 0.01, 0.525), "Headlight")  # reverse lamp
	# Rear plate + black lamp brow + rear wrap-around bumper + left exhaust pipe
	cube(mb, (-0.23, yr - 0.016, 0.45), (0.23, yr + 0.01, 0.55), "Plate")
	cube(mb, (-0.16, yr - 0.03, 0.555), (0.16, yr + 0.01, 0.585), "DarkTrim")
	cube(mb, (-0.67, yr - 0.06, 0.29), (0.67, yr + 0.20, 0.43), "DarkTrim")
	mb.tube((-0.34, yr + 0.16, 0.23), (-0.34, yr - 0.04, 0.22), 0.022, "Alloy", segs=8)

	# 4 tiny classic 12-inch steel wheels
	for ya in axles:
		for sx in (-1, 1):
			_add_real_wheel(mb, sx * 0.60, ya, r_wheel, r_wheel, 0.155, sx, segs=18, style="steel")
	return mb


# ---------------------------------------------------------------- assembly
PIECES = {
	"Headframe": headframe, "ChurchSpire": church_spire, "Streetlamp": streetlamp, "StreetlampPark": streetlamp_park,
	"TrafficLight": traffic_light, "BusShelter": bus_shelter, "Billboard": billboard, "FestivalArch": festival_arch,
	"FestivalStage": festival_stage, "FlagPole": flag_pole, "Tent": tent,
	"CrowdBarrier": crowd_barrier, "InflatableArch": inflatable_arch, "MerchStall": merch_stall, "SponsorFlag": sponsor_flag,
	"SpectatorStand": lambda: spectator("stand"), "SpectatorCheer": lambda: spectator("cheer"), "SpectatorWave": lambda: spectator("wave"),
	"FestTrailer": festival_trailer,
	"FestExecStand": lambda: executive("stand"), "FestExecClip": lambda: executive("clip"), "FestExecTalk": lambda: executive("talk"),
	"CarHatch": lambda: car(CAR_HATCH), "CarSedan": lambda: car(CAR_SEDAN), "CarVan": real_van,
	"Maluch": real_maluch,
	"Bench": bench, "Fence": fence, "LevelCrossing": level_crossing,
	"LevelCrossingBoom": level_crossing_boom, "Beacon": beacon,
	"TrainCab": lambda: en57(True), "TrainCar": lambda: en57(False),
}
KEEP_ORIGIN = {"LevelCrossingBoom", "TrainCab", "TrainCar"}  # pivots: neither grounded nor centred
NOT_CENTRED = {"Fence", "LevelCrossing", "Streetlamp", "StreetlampPark", "TrafficLight", "FlagPole", "SponsorFlag", "FestTrailer", "FestExecStand", "FestExecClip", "FestExecTalk"}  # trailer origin = body centre, execs = hip centre
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
	preview_copy(objs["InflatableArch"], (0, 162, 0), tints={"Banner": "#00b4d8"})
	for k, x in enumerate((-14, -8, 8, 14)):
		preview_copy(objs["Tent"], (x, 140, 0), tints=ban if k % 2 else ban2)
	for k, x in enumerate((-13, -7, 7, 13)):
		preview_copy(objs["MerchStall"], (x, 154, 0), tints=ban2 if k % 2 else ban)
	for k, x in enumerate((-11, -5, 5, 11)):
		preview_copy(objs["FlagPole"], (x, 152, 0), tints=ban2 if k % 2 else ban)
	for k, x in enumerate((-9, -3, 3, 9)):
		preview_copy(objs["SponsorFlag"], (x, 166, 0), tints={"Banner": "#ffd166" if k % 2 else "#ff3366"})
	for k in range(6):
		preview_copy(objs["CrowdBarrier"], (-6.25 + k * 2.5, 158, 0), tints=ban if k % 2 else ban2)
	for k, nm in enumerate(("SpectatorStand", "SpectatorCheer", "SpectatorWave", "SpectatorStand", "SpectatorCheer", "SpectatorWave")):
		preview_copy(objs[nm], (-5.0 + k * 2.0, 156.8, 0))
	preview_copy(objs["FestTrailer"], (0, 200, 0), tints={"Banner": "#e8541e"})
	for k, nm in enumerate(("FestExecStand", "FestExecClip", "FestExecTalk")):
		preview_copy(objs[nm], (-3.0 + k * 1.3, 203.6, 0), rot=0.0)
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
	R("trailer.png", (9, 213, 3.6), (0, 200, 1.8), 55)
	R("trailer_rear.png", (-9, 192, 3.6), (0, 200, 1.8), 55)
	R("execs.png", (-1.8, 206.4, 1.9), (-1.7, 203.6, 1.0), 40)
	R("street.png", (2, 262, 3.5), (0, 250, 2.2), 75)
	R("lamps.png", (2.0, 251.5, 7.0), (-6.5, 251.0, 6.0), 55)
	R("crossing.png", (-12, 258, 3.0), (-15, 250, 1.6), 55)
	R("train.png", (-48, 290, 4.5), (-60, 268, 2.0), 55)
	R("train_side.png", (-30, 250, 3.0), (-60, 250, 2.0), 70)
	R("maluch.png", (11, 354.5, 1.8), (7.5, Yc, 0.6), 50)
	R("maluch_rear.png", (4.2, 346.2, 1.5), (7.5, Yc, 0.6), 45)
	R("van_front.png", (6.2, 356.0, 2.2), (2.5, Yc, 1.0), 48)
	R("van_rear.png", (-1.5, 344.2, 2.1), (2.5, Yc, 1.0), 48)
	R("hatch.png", (-11, 345.5, 1.8), (-7.5, Yc, 0.7), 50)
	R("cars_front.png", (8, 360, 2.6), (0, Yc, 0.6), 50)
	R("cars_rear.png", (-8, 340, 2.6), (0, Yc, 0.6), 50)
	R("cars_side.png", (0, Yc + 20 - 15, 1.2), (0, Yc + 20, 0.8), 55)


main()
