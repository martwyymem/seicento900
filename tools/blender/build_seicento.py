"""Builds the game's Fiat Seicento 900 (Type 187, 1998-2000 pre-facelift "S"/"Young") in Blender.

Run from the repository root (Blender 4.2 or newer, headless):

    blender -b -P tools/blender/build_seicento.py -- [--renders DIR] [--blend FILE]

Writes godot/models/seicento.glb. With --renders it also saves turntable-style previews (PNG) and with
--blend the working .blend file.

Everything is generated from the numbers below, so tweak a curve and rebuild instead of hand-editing
the GLB. Real dimensions: 3319 mm long, 1508 mm wide, 1420 mm high, 2200 mm wheelbase, 1263/1262 mm
track, 145/70 R13 tyres on 13" steel wheels, unpainted dark-grey bumpers (900 spec). The race-car
extras (roll cage, one bucket seat, door number panels and stripes) are what the game's cup cars wear.

Blender frame: +Y forward, +X right, +Z up, origin on the ground midway between the axles. glTF export
turns this into Godot's frame (-Z forward, +X right, +Y up). "s" below is the distance behind the
front bumper face, so y = Y0 - s.

Scene objects (Godot looks them up by name):
  Body     painted shell with glass, black trim, underbody and the cabin liner (vertex colours carry
           the panel gaps; the Paint surface is re-coloured per car)
  Details  bumpers, lamps, mirrors, wipers, badges, wheel wells, interior and roll cage
  Stripes  twin bonnet/roof stripes (toggled per car)
  Cabin    dashboard, steering wheel, bucket seat and roll cage (Godot hides it on distant cars)
  Wheel    one wheel at the origin, outer face towards +X (mirror it for the left side)
"""
import bpy
import bmesh
import math
import os
import sys
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_GLB = os.path.join(ROOT, "godot", "models", "seicento.glb")

# ---------------------------------------------------------------- real-car numbers
LENGTH = 3.319
WHEELBASE = 2.20
FRONT_AXLE_S = 0.64
REAR_AXLE_S = FRONT_AXLE_S + WHEELBASE
Y0 = FRONT_AXLE_S + WHEELBASE / 2.0
TRACK = 1.263
TYRE_R = 0.2665  # 145/70 R13
TYRE_W = 0.145
ARCH_R = 0.335

S_START, S_END = 0.04, 3.25  # the painted shell; bumpers cover the rest
S_COWL, S_WS_TOP = 1.10, 1.80  # windscreen base and top
S_SCUTTLE = 1.04  # black scuttle panel in front of the windscreen
S_SAIL = 1.27  # door glass starts behind the mirror sail
S_B0, S_B1 = 2.30, 2.37  # B-pillar
S_Q1 = 2.93  # rear quarter glass ends
S_RG0, S_RG1 = 2.955, 3.165  # rear glass
S_DOOR = (1.115, 2.335)  # door shut lines
FRIT = 0.015  # black border round fixed glass
PILLAR = 0.07  # vertical depth of the roof rail / A-pillar band above the side glass
QUARTER_R = 0.09  # rounded rear corner of the quarter window

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def arg(name):
	return ARGS[ARGS.index(name) + 1] if name in ARGS else None


def bl(x, s, z):
	return Vector((x, Y0 - s, z))


def smoothstep(a, b, x):
	t = min(1.0, max(0.0, (x - a) / (b - a)))
	return t * t * (3.0 - 2.0 * t)


def lerp(a, b, t):
	return a + (b - a) * t


class Curve:
	"""Monotone cubic (PCHIP) through (s, value) points, so profiles never overshoot."""

	def __init__(self, pts):
		self.x = [p[0] for p in pts]
		self.y = [p[1] for p in pts]
		n = len(pts)
		h = [self.x[i + 1] - self.x[i] for i in range(n - 1)]
		d = [(self.y[i + 1] - self.y[i]) / h[i] for i in range(n - 1)]
		m = [0.0] * n
		m[0], m[-1] = d[0], d[-1]
		for i in range(1, n - 1):
			if d[i - 1] * d[i] <= 0:
				m[i] = 0.0
			else:
				w1, w2 = 2 * h[i] + h[i - 1], h[i] + 2 * h[i - 1]
				m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])
		self.h, self.m = h, m

	def __call__(self, s):
		x = self.x
		if s <= x[0]:
			return self.y[0]
		if s >= x[-1]:
			return self.y[-1]
		lo, hi = 0, len(x) - 1
		while hi - lo > 1:
			mid = (lo + hi) // 2
			if x[mid] <= s:
				lo = mid
			else:
				hi = mid
		h = self.h[lo]
		t = (s - x[lo]) / h
		t2, t3 = t * t, t * t * t
		return ((2 * t3 - 3 * t2 + 1) * self.y[lo] + (t3 - 2 * t2 + t) * h * self.m[lo]
			+ (-2 * t3 + 3 * t2) * self.y[hi] + (t3 - t2) * h * self.m[hi])


# ---------------------------------------------------------------- body profile curves (metres)
# max half-width; the arch flares add up to 24 mm, which brings the car to its real 1508 mm
W = Curve([(0.04, 0.575), (0.07, 0.645), (0.11, 0.688), (0.18, 0.712), (0.35, 0.724), (0.64, 0.728),
	(1.0, 0.73), (1.8, 0.732), (2.84, 0.732), (3.05, 0.728), (3.15, 0.72), (3.21, 0.708), (3.25, 0.69)])
ZM = Curve([(0.04, 0.45), (0.3, 0.50), (1.0, 0.52), (3.25, 0.54)])  # height of the widest point
WSH = Curve([(0.04, 0.53), (0.07, 0.595), (0.11, 0.645), (0.2, 0.678), (0.5, 0.692), (1.1, 0.697), (2.0, 0.70),
	(2.9, 0.698), (3.1, 0.688), (3.2, 0.68), (3.25, 0.66)])  # shoulder half-width
ZSH = Curve([(0.04, 0.535), (0.07, 0.605), (0.11, 0.655), (0.2, 0.69), (0.5, 0.74), (0.8, 0.795), (1.1, 0.865),
	(1.25, 0.90), (1.6, 0.925), (2.3, 0.95), (2.8, 0.99), (3.0, 1.0), (3.1, 0.975), (3.17, 0.955),
	(3.22, 0.94), (3.25, 0.925)])  # shoulder / waistline height (rises towards the rear)
ZT = Curve([(0.04, 0.56), (0.07, 0.635), (0.11, 0.685), (0.2, 0.73), (0.4, 0.775), (0.7, 0.83), (0.95, 0.88),
	(S_COWL, 0.915), (1.30, 1.058), (1.50, 1.20), (1.70, 1.33), (S_WS_TOP, 1.378), (1.90, 1.405),
	(2.1, 1.418), (2.5, 1.42), (2.8, 1.41), (2.93, 1.392), (2.98, 1.36), (3.05, 1.265), (3.12, 1.125),
	(3.17, 1.015), (3.20, 0.99), (3.23, 0.978), (3.25, 0.965)])  # centre-line top
ZB = Curve([(0.04, 0.31), (0.12, 0.27), (0.25, 0.23), (0.35, 0.21), (3.1, 0.21), (3.18, 0.24), (3.25, 0.30)])
WR = Curve([(0.04, 0.45), (0.07, 0.53), (0.11, 0.585), (0.2, 0.615), (0.6, 0.63), (S_COWL, 0.635), (1.45, 0.60),
	(S_WS_TOP, 0.565), (2.4, 0.555), (2.9, 0.555), (3.0, 0.565), (3.1, 0.59), (3.17, 0.605),
	(3.25, 0.585)])  # roof / bonnet edge half-width
DR = Curve([(0.04, 0.02), (0.2, 0.045), (S_COWL, 0.045), (S_WS_TOP, 0.03), (3.17, 0.03), (3.25, 0.02)])

# Half cross-section key points, bottom centre to top centre:
# A floor centre, B floor edge, C sill lip, D widest point, E shoulder, F glass base (belt step),
# G glass top, H roof edge, I top centre. Rows per segment:
SEG_ROWS = [3, 2, 3, 6, 1, 4, 2, 8]
SEG_AB, SEG_BC, SEG_CD, SEG_DE, SEG_EF, SEG_FG, SEG_GH, SEG_HI = range(8)


def zbottom(s):
	z = ZB(s)
	for sc in (FRONT_AXLE_S, REAR_AXLE_S):
		d = s - sc
		if abs(d) <= ARCH_R:
			z = max(z, TYRE_R + math.sqrt(max(0.0, ARCH_R * ARCH_R - d * d)))
	return z


def cabin(s):
	return smoothstep(1.05, 1.2, s) * (1.0 - smoothstep(3.12, 3.2, s))


def keys(s):
	w = W(s)
	zb = zbottom(s)
	zsh = ZSH(s)
	A = Vector((0.0, zb))
	B = Vector((w - 0.06, zb))
	C = Vector((w - 0.008, zb + 0.035))
	D = Vector((w, max(ZM(s), zb + 0.10)))
	E = Vector((WSH(s), zsh))
	c = cabin(s)
	F = E + Vector((-lerp(0.012, 0.022, c), lerp(0.006, 0.012, c)))
	hz = max(ZT(s) - DR(s), F.y + 0.012)
	H = Vector((WR(s), hz))
	I = Vector((0.0, max(ZT(s), hz + 0.004)))
	gz = max(F.y + 0.004, H.y - PILLAR)
	band = gz - F.y
	if s > S_Q1 - QUARTER_R and band > QUARTER_R:
		dx = min(QUARTER_R, s - (S_Q1 - QUARTER_R))
		band = band - QUARTER_R + math.sqrt(max(0.0, QUARTER_R * QUARTER_R - dx * dx))
		gz = F.y + max(0.004, band)
	G = F + (H - F) * ((gz - F.y) / (H.y - F.y))
	return [A, B, C, D, E, F, G, H, I]


def cr(p0, p1, p2, p3, t):
	"""Centripetal Catmull-Rom between p1 and p2."""
	def nxt(ti, a, b):
		return ti + max((b - a).length, 1e-6) ** 0.5
	t0 = 0.0
	t1 = nxt(t0, p0, p1)
	t2 = nxt(t1, p1, p2)
	t3 = nxt(t2, p2, p3)
	u = t1 + (t2 - t1) * t
	a1 = p0 * ((t1 - u) / (t1 - t0)) + p1 * ((u - t0) / (t1 - t0))
	a2 = p1 * ((t2 - u) / (t2 - t1)) + p2 * ((u - t1) / (t2 - t1))
	a3 = p2 * ((t3 - u) / (t3 - t2)) + p3 * ((u - t2) / (t3 - t2))
	b1 = a1 * ((t2 - u) / (t2 - t0)) + a2 * ((u - t0) / (t2 - t0))
	b2 = a2 * ((t3 - u) / (t3 - t1)) + a3 * ((u - t1) / (t3 - t1))
	return b1 * ((t2 - u) / (t2 - t1)) + b2 * ((u - t1) / (t2 - t1))


def glass_corner(s, s0, s1, radius, depth):
	"""How far the glass edge row moves in near the ends of a glass pane (rounded corners)."""
	e = min(s - s0, s1 - s)
	if e >= radius or e < 0:
		return 0.0
	k = (radius - e) / radius
	return depth * (1.0 - math.sqrt(max(0.0, 1.0 - k * k)))


def hi_params(s):
	"""Sample positions along the roof segment H->I: a paint sliver, the glass frit band, then glass."""
	te = 0.01
	if S_COWL < s < S_WS_TOP:
		te += glass_corner(s, S_COWL, S_WS_TOP, 0.07, 0.12)
	elif S_RG0 < s < S_RG1:
		te += glass_corner(s, S_RG0, S_RG1, 0.06, 0.14)
	fr = 0.035
	rest = [te + fr + (1.0 - te - fr) * k / 6.0 for k in range(1, 7)]
	return [0.0, te, te + fr] + rest


def section(s):
	"""Half cross-section as (x, z) points from the floor centre to the top centre, plus row segment ids."""
	k = keys(s)
	ext = [Vector((-k[1].x, k[1].y))] + k + [Vector((-k[7].x, k[7].y))]
	pts = [k[0]]
	seg_of_band = []
	for seg in range(8):
		p0, p1, p2, p3 = ext[seg], ext[seg + 1], ext[seg + 2], ext[seg + 3]
		if seg == SEG_HI:
			ts = hi_params(s)[1:]
		else:
			n = SEG_ROWS[seg]
			ts = [j / n for j in range(1, n + 1)]
		for sub, t in enumerate(ts):
			pts.append(cr(p0, p1, p2, p3, t) if t < 1.0 else p2.copy())
			seg_of_band.append((seg, sub))
	return pts, seg_of_band


def band_material(seg, sub, s):
	if seg == SEG_AB:
		return "Under"
	if seg in (SEG_BC, SEG_CD, SEG_DE):
		return "Paint"
	in_cabin = S_COWL <= s <= S_Q1
	if seg == SEG_EF:
		return "Trim" if in_cabin else "Paint"
	if seg == SEG_FG:
		if S_SAIL <= s <= S_B0 or S_B1 <= s <= S_Q1:
			return "Glass"
		if S_COWL <= s <= S_B1:
			return "Trim"
		return "Paint"
	if seg == SEG_GH:
		return "Trim" if S_B0 < s < S_B1 else "Paint"
	# roof segment: windscreen, scuttle, roof, rear glass
	if S_SCUTTLE < s < S_COWL:
		return "Trim" if sub > 0 else "Paint"
	for g0, g1 in ((S_COWL, S_WS_TOP), (S_RG0, S_RG1)):
		if g0 < s < g1:
			if sub == 0:
				return "Paint"
			if sub == 1 or s - g0 < FRIT or g1 - s < FRIT:
				return "Trim"
			return "Glass"
	return "Paint"


def body_stations():
	"""Stations along the car, denser wherever the section changes quickly (arches, ends, windscreen)."""
	n = 6000
	step = 0.04
	out = [S_START]
	prev = None
	acc = 0.0
	for i in range(n + 1):
		s = S_START + (S_END - S_START) * i / n
		pts = [Vector((p.x, s, p.y)) for p in keys(s)[1:]]
		if prev is not None:
			acc += max((a - b).length for a, b in zip(pts, prev))
			if acc >= step:
				out.append(s)
				acc = 0.0
		prev = pts
	forced = [S_START, S_END, S_SCUTTLE, S_COWL, S_COWL + FRIT, S_WS_TOP - FRIT, S_WS_TOP, S_SAIL, S_B0, S_B1,
		S_Q1, S_RG0, S_RG0 + FRIT, S_RG1 - FRIT, S_RG1]
	for sc in (FRONT_AXLE_S, REAR_AXLE_S):
		forced += [sc - ARCH_R - 0.004, sc - ARCH_R, sc + ARCH_R, sc + ARCH_R + 0.004]
	for sd in S_DOOR:
		forced += [sd - 0.0035, sd, sd + 0.0035]
	out = [s for s in out if min(abs(s - f) for f in forced) > 0.008] + forced
	return sorted(set(round(s, 6) for s in out))


# ---------------------------------------------------------------- materials
MATERIALS = {
	# name: (base colour, roughness, metallic, extra)
	"Paint": ((1.0, 1.0, 1.0), 0.32, 0.05, {"coat": 0.9}),
	"Glass": ((0.06, 0.08, 0.09), 0.04, 0.0, {"alpha": 0.32}),
	"Trim": ((0.018, 0.018, 0.02), 0.42, 0.0, {}),
	"Under": ((0.012, 0.012, 0.012), 0.9, 0.0, {}),
	"Interior": ((0.045, 0.045, 0.05), 0.85, 0.0, {}),
	"Bumper": ((0.075, 0.077, 0.08), 0.62, 0.0, {}),
	"Grille": ((0.01, 0.01, 0.01), 0.7, 0.0, {}),
	"Chrome": ((0.85, 0.86, 0.88), 0.12, 1.0, {}),
	"Headlight": ((0.62, 0.63, 0.62), 0.06, 0.7, {"emit": ((1.0, 0.95, 0.84), 0.2)}),
	"Indicator": ((1.0, 0.42, 0.04), 0.1, 0.0, {"emit": ((1.0, 0.4, 0.02), 0.1)}),
	"Taillight": ((0.30, 0.0, 0.01), 0.08, 0.0, {"emit": ((1.0, 0.05, 0.03), 0.15)}),
	"LampClear": ((0.85, 0.80, 0.80), 0.08, 0.0, {}),
	"Plate": ((0.94, 0.93, 0.89), 0.45, 0.0, {}),
	"Seat": ((0.03, 0.03, 0.035), 0.9, 0.0, {}),
	"Cage": ((0.55, 0.56, 0.58), 0.45, 0.6, {}),
	"Tyre": ((0.03, 0.03, 0.03), 0.8, 0.0, {}),
	"Sidewall": ((0.085, 0.085, 0.085), 0.7, 0.0, {}),  # raised tyre lettering, so the wheels read as turning
	"Rim": ((0.5, 0.51, 0.53), 0.3, 0.75, {}),  # silver-painted steel wheel dish
	"Steel": ((0.36, 0.37, 0.38), 0.42, 0.5, {}),
	"Stripe": ((1.0, 1.0, 1.0), 0.4, 0.0, {}),
}


def material(name):
	m = bpy.data.materials.get(name)
	if m:
		return m
	col, rough, metal, extra = MATERIALS[name]
	m = bpy.data.materials.new(name)
	m.use_nodes = True
	m.use_backface_culling = "alpha" not in extra
	bsdf = m.node_tree.nodes.get("Principled BSDF")
	bsdf.inputs["Base Color"].default_value = (*col, 1.0)
	bsdf.inputs["Roughness"].default_value = rough
	bsdf.inputs["Metallic"].default_value = metal
	if "coat" in extra:
		bsdf.inputs["Coat Weight"].default_value = extra["coat"]
		bsdf.inputs["Coat Roughness"].default_value = 0.05
	if "emit" in extra:
		bsdf.inputs["Emission Color"].default_value = (*extra["emit"][0], 1.0)
		bsdf.inputs["Emission Strength"].default_value = extra["emit"][1]
	if "alpha" in extra:
		bsdf.inputs["Alpha"].default_value = extra["alpha"]
		if hasattr(m, "surface_render_method"):
			m.surface_render_method = "BLENDED"
		else:
			m.blend_method = "BLEND"
	if name == "Paint":
		# carry the panel-gap vertex colours through to glTF (Godot multiplies them with the paint)
		attr = m.node_tree.nodes.new("ShaderNodeVertexColor")
		attr.layer_name = "Col"
		mix = m.node_tree.nodes.new("ShaderNodeMix")
		mix.data_type = "RGBA"
		mix.blend_type = "MULTIPLY"
		mix.name = "Tint"
		sock = {s.identifier: s for s in mix.inputs}
		sock["Factor_Float"].default_value = 1.0
		sock["A_Color"].default_value = (*col, 1.0)
		m.node_tree.links.new(attr.outputs["Color"], sock["B_Color"])
		out = {s.identifier: s for s in mix.outputs}
		m.node_tree.links.new(out["Result_Color"], bsdf.inputs["Base Color"])
	return m


# ---------------------------------------------------------------- mesh builder
def newell(pts):
	n = Vector((0.0, 0.0, 0.0))
	for i in range(len(pts)):
		a, b = pts[i], pts[(i + 1) % len(pts)]
		n.x += (a.y - b.y) * (a.z + b.z)
		n.y += (a.z - b.z) * (a.x + b.x)
		n.z += (a.x - b.x) * (a.y + b.y)
	return n


class MB:
	"""Collects vertices and faces (with material names) for one object."""

	def __init__(self):
		self.v = []
		self.f = []
		self.m = []
		self.col = []

	def vert(self, p, col=1.0):
		self.v.append(Vector(p))
		self.col.append(col)
		return len(self.v) - 1

	def face(self, idx, mat, out=None):
		"""out: outward reference (Vector or callable(centre)) to fix the winding."""
		if out is not None:
			pts = [self.v[i] for i in idx]
			ref = out(sum(pts, Vector()) / len(pts)) if callable(out) else out
			if newell(pts).dot(ref) < 0:
				idx = list(reversed(idx))
		self.f.append(list(idx))
		self.m.append(mat)

	def grid(self, rows, mat, closed=False, out=None, cap_ends=False):
		"""rows[i][j]: points; quads between consecutive rows (j wraps when closed)."""
		ids = [[self.vert(p) for p in row] for row in rows]
		n = len(rows[0])
		for i in range(len(rows) - 1):
			for j in range(n if closed else n - 1):
				j2 = (j + 1) % n
				self.face([ids[i][j], ids[i][j2], ids[i + 1][j2], ids[i + 1][j]], mat, out)
		if cap_ends and closed:
			for r, sign in ((ids[0], -1), (ids[-1], 1)):
				c = sum((self.v[i] for i in r), Vector()) / n
				ci = self.vert(c)
				for j in range(n):
					other = rows[1] if sign < 0 else rows[-2]
					oc = sum(other, Vector()) / n
					self.face([ci, r[j], r[(j + 1) % n]], mat, c - oc)
		return ids

	def lathe(self, profile, segs, mat, centre=Vector(), out=None, closed_profile=False):
		"""Revolve (axial x, radius) points around the X axis."""
		rows = []
		for ax, r in profile:
			rows.append([centre + Vector((ax, r * math.cos(2 * math.pi * k / segs), r * math.sin(2 * math.pi * k / segs)))
				for k in range(segs)])
		if closed_profile:
			rows.append(rows[0])
		ids = [[self.vert(p) for p in row] for row in rows]
		for i in range(len(rows) - 1):
			for k in range(segs):
				k2 = (k + 1) % segs
				self.face([ids[i][k], ids[i][k2], ids[i + 1][k2], ids[i + 1][k]], mat, out)

	def tube(self, a, b, r, mat, segs=10, caps=True):
		a, b = Vector(a), Vector(b)
		axis = (b - a).normalized()
		helper = Vector((0, 0, 1)) if abs(axis.z) < 0.9 else Vector((1, 0, 0))
		u = axis.cross(helper).normalized()
		v = axis.cross(u)
		rings = []
		for p in (a, b):
			rings.append([p + (u * math.cos(2 * math.pi * k / segs) + v * math.sin(2 * math.pi * k / segs)) * r
				for k in range(segs)])
		mid = (a + b) / 2

		def out(c):
			d = c - mid
			return d - axis * d.dot(axis) if abs(d.dot(axis)) < (b - a).length / 2 - 1e-5 else d
		ids = [[self.vert(p) for p in ring] for ring in rings]
		for k in range(segs):
			k2 = (k + 1) % segs
			self.face([ids[0][k], ids[0][k2], ids[1][k2], ids[1][k]], mat, out)
		if caps:
			self.face(ids[0], mat, -axis)
			self.face(ids[1], mat, axis)

	def blob(self, c, radii, mat, e=0.35, basis=None, nu=12, nv=20):
		"""Superellipsoid (rounded box) with exponent e; basis columns orient its local axes."""
		c = Vector(c)

		def sp(a, k):
			return math.copysign(abs(a) ** k, a)
		rows = []
		for i in range(1, nu):
			la = -math.pi / 2 + math.pi * i / nu
			row = []
			for j in range(nv):
				lo = -math.pi + 2 * math.pi * j / nv
				p = Vector((radii[0] * sp(math.cos(la), e) * sp(math.cos(lo), e),
					radii[1] * sp(math.cos(la), e) * sp(math.sin(lo), e), radii[2] * sp(math.sin(la), e)))
				row.append(c + (basis @ p if basis else p))
			rows.append(row)
		ids = self.grid(rows, mat, closed=True, out=lambda q: q - c)
		for r, z in ((ids[0], -1), (ids[-1], 1)):
			pole = self.vert(c + (basis @ Vector((0, 0, z * radii[2])) if basis else Vector((0, 0, z * radii[2]))))
			for j in range(nv):
				self.face([pole, r[j], r[(j + 1) % nv]], mat, lambda q: q - c)

	def box(self, c, size, mat, basis=None):
		c = Vector(c)
		hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
		corners = [Vector((sx * hx, sy * hy, sz * hz)) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
		ids = [self.vert(c + (basis @ p if basis else p)) for p in corners]
		for f in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
			self.face([ids[i] for i in f], mat, lambda q: q - c)

	def extend(self, other):
		base = len(self.v)
		self.v += other.v
		self.col += other.col
		self.f += [[i + base for i in f] for f in other.f]
		self.m += other.m

	def bvh(self):
		return BVHTree.FromPolygons(self.v, self.f)

	def emit(self, name, sharp_deg=48.0, colors=False):
		me = bpy.data.meshes.new(name)
		me.from_pydata([tuple(p) for p in self.v], [], self.f)
		names = sorted(set(self.m), key=list(MATERIALS).index)
		for n in names:
			me.materials.append(material(n))
		me.polygons.foreach_set("material_index", [names.index(n) for n in self.m])
		if colors:
			attr = me.color_attributes.new("Col", "BYTE_COLOR", "POINT")
			for i, c in enumerate(self.col):
				attr.data[i].color = (c, c, c, 1.0)
		me.update()
		me.validate()
		me.shade_smooth()
		me.set_sharp_from_angle(angle=math.radians(sharp_deg))
		ob = bpy.data.objects.new(name, me)
		bpy.context.scene.collection.objects.link(ob)
		return ob


# ---------------------------------------------------------------- body shell
def build_body():
	st = body_stations()
	mb = MB()
	rings = []  # vertex ids per ring
	ring_s = []
	R = None
	seg_bands = None
	for s in st:
		pts, bands = section(s)
		R = len(pts) - 1
		seg_bands = bands
		groove = any(abs(s - sd) < 1e-5 for sd in S_DOOR)
		right = []
		for j, p in enumerate(pts):
			x, z = p.x, p.y
			col = 1.0
			# door shut lines: a dark 3 mm groove from the sill to the waist
			if groove and SEG_ROWS[0] + 1 <= j <= sum(SEG_ROWS[:SEG_EF]):
				x -= 0.0025
				col = 0.12
			# bonnet shut line along the top of the wings
			if s < S_COWL - 0.02 and j == sum(SEG_ROWS[:SEG_FG]):
				col = 0.3
			right.append((x, z, col))
		ring = [mb.vert(bl(x, s, z), c) for x, z, c in right]
		ring += [mb.vert(bl(-right[j][0], s, right[j][1]), right[j][2]) for j in range(R - 1, 0, -1)]
		rings.append(ring)
		ring_s.append(s)
	M = 2 * R

	def band_of(k):
		return k if k < R else 2 * R - k - 1

	# end caps: shrink the last ring into a gently domed nose / tailgate
	def cap(ring, s, sign, bulge):
		vs = [mb.v[i] for i in ring]
		zc = (min(v.z for v in vs) + max(v.z for v in vs)) / 2
		c = Vector((0.0, vs[0].y, zc))
		out = []
		for sig in (0.85, 0.6, 0.3):
			out.append([mb.vert(c + (v - c) * sig + Vector((0, sign * bulge * (1 - sig * sig), 0))) for v in vs])
		pole = mb.vert(c + Vector((0, sign * bulge, 0)))
		return out, pole

	front_rings, front_pole = cap(rings[0], st[0], 1, 0.02)
	rear_rings, rear_pole = cap(rings[-1], st[-1], -1, 0.028)
	all_rings = list(reversed(front_rings)) + rings + rear_rings
	all_s = [st[0]] * len(front_rings) + ring_s + [st[-1]] * len(rear_rings)
	for i in range(len(all_rings) - 1):
		smid = (all_s[i] + all_s[i + 1]) / 2
		for k in range(M):
			seg, sub = seg_bands[band_of(k)]
			mat = band_material(seg, sub, smid) if smid not in (st[0], st[-1]) else ("Under" if seg == SEG_AB else "Paint")
			a, b = all_rings[i], all_rings[i + 1]
			mb.face([a[k], a[(k + 1) % M], b[(k + 1) % M], b[k]], mat)
	for k in range(M):
		r0, rn = all_rings[0], all_rings[-1]
		mb.face([front_pole, r0[(k + 1) % M], r0[k]], "Paint")
		mb.face([rn[k], rn[(k + 1) % M], rear_pole], "Paint")

	# flared wheel arches
	for v in mb.v:
		ax = abs(v.x)
		if ax < 0.45 or v.z < 0.18:
			continue
		s = Y0 - v.y
		for sc in (FRONT_AXLE_S, REAR_AXLE_S):
			d = math.hypot(s - sc, v.z - TYRE_R)
			if d < ARCH_R + 0.14:
				f = 0.024 * (1.0 - smoothstep(ARCH_R, ARCH_R + 0.14, d)) * (1.0 - smoothstep(0.78, 0.92, v.z))
				v.x += math.copysign(f, v.x)
	return mb


def build_liner(body):
	"""Cabin lining seen through the glass: an inset, inward-facing copy of the shell without the glass."""
	bm = bmesh.new()
	vs = [bm.verts.new(p) for p in body.v]
	for f in body.f:
		bm.faces.new([vs[i] for i in f])
	bm.normal_update()
	normals = [v.normal.copy() for v in bm.verts]
	bm.free()
	mb = MB()
	remap = {}
	for f, mat in zip(body.f, body.m):
		if mat == "Glass":
			continue
		c = sum((body.v[i] for i in f), Vector()) / len(f)
		s = Y0 - c.y
		if s < 1.0 or c.z < 0.2:
			continue
		ids = []
		for i in f:
			if i not in remap:
				remap[i] = mb.vert(body.v[i] - normals[i] * 0.018)
			ids.append(remap[i])
		mb.face(list(reversed(ids)), "Interior")
	return mb


# ---------------------------------------------------------------- projected parts (lamps, badges, decals)
class Projector:
	def __init__(self, mb):
		self.tree = mb.bvh()

	def hit(self, origin, direction):
		loc, nor, _, _ = self.tree.ray_cast(origin, direction)
		if loc is None:
			raise RuntimeError("projection missed the body at %s" % (origin,))
		if nor.dot(direction) > 0:
			nor = -nor
		return loc, nor

	def star(self, mb, outline, proj, mat, offset=0.003, bulge=0.0, rings=3, skirt=0.006, samples=6):
		"""Fill a star-shaped 2D outline, project it onto the surface and lift it off by offset (+bulge)."""
		outline = resample(outline, samples)
		c = sum((Vector(p) for p in outline), Vector((0.0, 0.0))) / len(outline)
		grid = []
		normals = []
		for k in range(1, rings + 1):
			row = []
			for p in outline:
				q = c + (Vector(p) - c) * (k / rings)
				loc, nor = self.hit(*proj(q.x, q.y))
				row.append(loc + nor * (offset + bulge * (1 - (k / rings) ** 2)))
				normals.append(nor)
			grid.append(row)
		loc, nor = self.hit(*proj(c.x, c.y))
		centre = loc + nor * (offset + bulge)
		ref = sum(normals, Vector()).normalized()
		n = len(outline)
		ids = mb.grid(grid, mat, closed=True, out=ref)
		ci = mb.vert(centre)
		for j in range(n):
			mb.face([ci, ids[0][j], ids[0][(j + 1) % n]], mat, ref)
		if skirt:
			low = [mb.vert(mb.v[i] - normals[(rings - 1) * n + j] * (offset + skirt)) for j, i in enumerate(ids[-1])]
			for j in range(n):
				j2 = (j + 1) % n
				a, b = ids[-1][j], ids[-1][j2]
				mb.face([a, low[j], low[j2], b], mat, lambda q, c3=centre: q - c3)

	def strip(self, mb, u0, u1, v0, v1, nu, nv, proj, mat, offset=0.002):
		rows = []
		for i in range(nu + 1):
			u = lerp(u0, u1, i / nu)
			row = []
			for j in range(nv + 1):
				loc, nor = self.hit(*proj(u, lerp(v0, v1, j / nv)))
				row.append(loc + nor * offset)
			rows.append(row)
		_, ref = self.hit(*proj((u0 + u1) / 2, (v0 + v1) / 2))
		mb.grid(rows, mat, out=ref)


def resample(pts, per_seg):
	"""Closed centripetal Catmull-Rom through 2D points."""
	pts = [Vector(p) for p in pts]
	n = len(pts)
	out = []
	for i in range(n):
		p0, p1, p2, p3 = pts[i - 1], pts[i], pts[(i + 1) % n], pts[(i + 2) % n]
		for k in range(per_seg):
			out.append(cr(p0, p1, p2, p3, k / per_seg))
	return out


def ellipse(cu, cv, ru, rv, n=16):
	return [(cu + ru * math.cos(2 * math.pi * k / n), cv + rv * math.sin(2 * math.pi * k / n)) for k in range(n)]


def rounded_rect(u0, u1, v0, v1, r):
	pts = []
	for cu, cv, a0 in ((u1 - r, v1 - r, 0), (u0 + r, v1 - r, 90), (u0 + r, v0 + r, 180), (u1 - r, v0 + r, 270)):
		for k in range(4):
			a = math.radians(a0 + 90 * k / 3)
			pts.append((cu + r * math.cos(a), cv + r * math.sin(a)))
	return pts


def corner_proj(ax, as_, side, rear):
	"""Rays aimed horizontally at a vertical axis (ax, as_): u = degrees from straight ahead (or behind)
	towards the side, v = height."""
	def f(u, v):
		th = math.radians(u)
		dx = side * math.sin(th)
		ds = math.cos(th) if rear else -math.cos(th)
		target = bl(side * ax, as_, v)
		origin = bl(side * ax + dx * 2.0, as_ + ds * 2.0, v)
		return origin, (target - origin).normalized()
	return f


def side_proj(side):
	def f(u, v):  # u = s, v = z
		return bl(side * 2.0, u, v), Vector((-side, 0.0, 0.0))
	return f


def front_proj(u, v):  # u = x, v = z
	return bl(u, -1.0, v), Vector((0.0, -1.0, 0.0))


def rear_proj(u, v):
	return bl(u, LENGTH + 1.0, v), Vector((0.0, 1.0, 0.0))


def top_proj(u, v):  # u = s, v = x
	return bl(v, u, 3.0), Vector((0.0, 0.0, -1.0))


# ---------------------------------------------------------------- bumpers (sweeps)
def build_bumper(mb, path, z_top, z_bot, rear):
	"""Sweep a rounded bumper section along a plan-view path of (x, s) points (right half, centre first)."""
	full = [(-x, s) for x, s in reversed(path[1:])] + path
	pts = [Vector(p) for p in full]
	dense = []
	for i in range(len(pts) - 1):
		p0 = pts[max(0, i - 1)]
		p3 = pts[min(len(pts) - 1, i + 2)]
		for k in range(4):
			dense.append(cr(p0, pts[i], pts[i + 1], p3, k / 4))
	dense.append(pts[-1])
	# (outward offset, height fraction 0 = bottom .. 1 = top)
	prof = [(-0.07, 0.99), (-0.025, 1.0), (0.0, 0.94), (0.009, 0.8), (0.012, 0.6), (0.012, 0.48), (0.01, 0.2), (0.0, 0.08), (-0.025, 0.0), (-0.075, 0.01)]
	rows = []
	n = len(dense)
	for i, p in enumerate(dense):
		a = dense[max(0, i - 1)]
		b = dense[min(n - 1, i + 1)]
		t = (b - a).normalized()
		nrm = Vector((t.y, -t.x)) if not rear else Vector((-t.y, t.x))
		frac = abs(p.x) / 0.75
		zt, zb = z_top(frac), z_bot(frac)
		row = []
		for off, h in prof:
			q = p + nrm * off
			row.append(bl(q.x, q.y, lerp(zb, zt, h)))
		rows.append(row)
	centre = bl(0, (dense[0].y + dense[n // 2].y) / 2 + (0.3 if not rear else -0.3), 0.35)
	ids = mb.grid(rows, "Bumper", closed=True, out=lambda q: Vector((q.x * 0.3, q.y - centre.y, (q.z - 0.35) * 0.5)))
	for r in (ids[0], ids[-1]):
		c = sum((mb.v[i] for i in r), Vector()) / len(r)
		ci = mb.vert(c)
		for j in range(len(r)):
			mb.face([ci, r[j], r[(j + 1) % len(r)]], "Bumper", Vector((math.copysign(1, c.x), 0, 0)))


# ---------------------------------------------------------------- everything else
def build_details(body):
	mb = MB()
	bump = MB()
	# 900-spec unpainted bumpers, wrapping round to the wheel arches
	build_bumper(bump, [(0.0, 0.0), (0.25, 0.005), (0.45, 0.02), (0.58, 0.045), (0.66, 0.08), (0.71, 0.13),
		(0.728, 0.19), (0.745, 0.25), (0.758, 0.30)],
		lambda f: lerp(0.505, 0.535, smoothstep(0.5, 1.0, f)), lambda f: lerp(0.175, 0.215, smoothstep(0.6, 1.0, f)), False)
	build_bumper(bump, [(0.0, LENGTH), (0.3, LENGTH - 0.006), (0.5, LENGTH - 0.024), (0.62, LENGTH - 0.05),
		(0.69, LENGTH - 0.085), (0.738, LENGTH - 0.12), (0.758, LENGTH - 0.145)],
		lambda f: lerp(0.60, 0.61, f), lambda f: lerp(0.20, 0.24, smoothstep(0.6, 1.0, f)), True)
	both = MB()
	both.extend(body)
	both.extend(bump)
	pj = Projector(both)
	mb.extend(bump)

	for side in (1, -1):
		# headlight (teardrop, wrapping round the corner) and the amber indicator at its outer end
		head = [(-4, 0.600), (4, 0.636), (18, 0.656), (32, 0.668), (44, 0.674), (51, 0.671), (55, 0.655),
			(56, 0.62), (52, 0.576), (42, 0.558), (25, 0.553), (8, 0.558), (-2, 0.572)]
		hp = corner_proj(0.40, 0.45, side, False)
		pj.star(mb, head, hp, "Headlight", offset=0.004, bulge=0.012, rings=4)
		ind = [(45, 0.566), (51, 0.578), (55, 0.60), (56.5, 0.622), (56, 0.648), (53, 0.656), (48, 0.632), (44, 0.60)]
		pj.star(mb, ind, hp, "Indicator", offset=0.0165, bulge=0.002, rings=2, samples=3)
		# tail lights sit on the bumper shoulder and wrap round the corner, with two clear round lenses
		tail = [(-8, 0.664), (0, 0.700), (20, 0.718), (38, 0.72), (48, 0.71), (52, 0.69), (52, 0.648),
			(46, 0.628), (32, 0.622), (15, 0.624), (0, 0.632), (-7, 0.646)]
		tp = corner_proj(0.40, 2.98, side, True)
		pj.star(mb, tail, tp, "Taillight", offset=0.004, bulge=0.008, rings=3)
		for cu in (14, 30):
			pj.star(mb, ellipse(cu, 0.666, 6.0, 0.034), tp, "LampClear", offset=0.013, rings=2, samples=2, skirt=0)
		# side repeater on the front wing
		sp = side_proj(side)
		pj.star(mb, ellipse(1.035, 0.735, 0.034, 0.016, 12), sp, "Indicator", offset=0.003, rings=2, samples=2)
		# race number panel on the door
		pj.star(mb, rounded_rect(1.50, 1.94, 0.45, 0.79, 0.05), sp, "Plate", offset=0.0022, rings=2, samples=2, skirt=0.003)
		# door handle and lock
		pj.star(mb, rounded_rect(2.10, 2.21, 0.845, 0.875, 0.012), sp, "Trim", offset=0.008, rings=2, samples=2)
		pj.star(mb, ellipse(2.245, 0.86, 0.009, 0.009, 10), sp, "Chrome", offset=0.004, rings=1, samples=1)
		# mirror: black housing on the sail, glass facing back
		loc, _ = pj.hit(*sp(1.20, 0.955))
		hx = loc.x + side * 0.095
		mb.blob(bl(hx, 1.215, 0.975), (0.085, 0.042, 0.058), "Trim", e=0.45)
		mb.box(bl(loc.x + side * 0.02, 1.21, 0.95), (0.05, 0.05, 0.03), "Trim")
		mb.box(bl(hx, 1.258, 0.975), (0.14, 0.004, 0.085), "Chrome")
		# wheel-well liners (black arcs so you can't see into the shell)
		for sc in (FRONT_AXLE_S, REAR_AXLE_S):
			rows = []
			for xo in (0.50, 0.745):
				row = []
				for k in range(19):
					a = math.radians(-12 + 204 * k / 18)
					row.append(bl(side * xo, sc - (ARCH_R - 0.006) * math.cos(a), TYRE_R + (ARCH_R - 0.006) * math.sin(a)))
				rows.append(row)
			mb.grid(rows, "Under", out=lambda q, sc=sc: Vector((0, (Y0 - sc) - q.y, TYRE_R - q.z)))

	# front: lower intake with slats, Fiat badge on the nose
	pj.strip(mb, -0.43, 0.43, 0.215, 0.335, 40, 4, front_proj, "Grille", offset=0.003)
	for z in (0.252, 0.292):
		pj.strip(mb, -0.41, 0.41, z, z + 0.009, 20, 1, lambda u, v: front_proj(u, v), "Bumper", offset=0.008)
	pj.star(mb, rounded_rect(-0.038, 0.038, 0.565, 0.605, 0.012), front_proj, "Chrome", offset=0.003, rings=2, samples=2)
	for k in range(5):
		x = -0.024 + 0.012 * k
		pj.strip(mb, x - 0.0025, x + 0.0025, 0.571, 0.599, 1, 2, front_proj, "Trim", offset=0.0045)
	# rear: plate recess on the bumper
	pj.strip(mb, 0.27, -0.27, 0.33, 0.46, 24, 3, rear_proj, "Grille", offset=0.003)
	# tailgate shut lines inboard of the lamps (the chase camera looks at this panel all race), its handle
	# strip and the Fiat badge
	for x in (-0.47, 0.47):
		pj.strip(mb, x + 0.003, x - 0.003, 0.625, 0.99, 1, 14, rear_proj, "Trim", offset=0.0015)
	pj.strip(mb, 0.13, -0.13, 0.735, 0.765, 10, 1, rear_proj, "Trim", offset=0.004)
	pj.star(mb, rounded_rect(-0.032, 0.032, 0.79, 0.825, 0.01), rear_proj, "Chrome", offset=0.003, rings=2, samples=2)

	# wipers parked on the scuttle, roof aerial, rear wiper, exhaust
	for x0, x1 in ((-0.62, -0.10), (-0.02, 0.46)):
		a = pj.hit(*top_proj(1.125, x0))[0] + Vector((0, 0, 0.012))
		b = pj.hit(*top_proj(1.10 + 0.05, x1))[0] + Vector((0, 0, 0.012))
		mb.tube(a, b, 0.007, "Trim", segs=6)
	base = pj.hit(*top_proj(1.87, 0.0))[0]
	mb.box(base + Vector((0, 0, 0.012)), (0.03, 0.05, 0.025), "Trim")
	mb.tube(base + Vector((0, 0, 0.02)), base + Vector((0, -0.20, 0.36)), 0.0035, "Trim", segs=6)
	p0 = pj.hit(*rear_proj(0.02, 1.04))[0]
	p1 = pj.hit(*rear_proj(-0.46, 1.16))[0]
	mb.tube(p0 + Vector((0, -0.012, 0)), p1 + Vector((0, -0.012, 0)), 0.006, "Trim", segs=6)
	mb.tube(bl(0.30, 3.08, 0.175), bl(0.30, LENGTH + 0.015, 0.185), 0.022, "Steel", segs=12, caps=False)

	# underbody: engine bay / rear floor blocks between the wheel wells and a flat floor pan
	mb.box(bl(0, 0.62, 0.36), (1.0, 0.80, 0.46), "Under")
	mb.box(bl(0, 2.84, 0.36), (1.0, 0.72, 0.46), "Under")
	mb.box(bl(0, 1.74, 0.175), (0.9, 1.5, 0.07), "Under")

	# interior: dashboard, steering wheel (left-hand drive), bucket seat and a six-point roll cage
	details = mb
	mb = MB()
	mb.blob(bl(0, 1.37, 0.86), (0.62, 0.16, 0.09), "Interior", e=0.3)
	mb.box(bl(0, 1.30, 0.62), (1.2, 0.1, 0.4), "Interior")
	tilt = math.radians(62)
	n = Vector((0, -math.cos(tilt), math.sin(tilt)))
	u = Vector((1, 0, 0))
	v = n.cross(u)
	sw = bl(-0.36, 1.66, 0.93)
	ring = []
	for k in range(24):
		a = 2 * math.pi * k / 24
		ring.append(sw + (u * math.cos(a) + v * math.sin(a)) * 0.175)
	for k in range(24):
		mb.tube(ring[k], ring[(k + 1) % 24], 0.014, "Seat", segs=6, caps=False)
	mb.tube(sw - v * 0.17, sw + v * 0.02, 0.012, "Seat", segs=6)
	mb.tube(sw, sw + n * -0.02 + Vector((0, 0.28, -0.12)), 0.022, "Seat", segs=8)
	mb.blob(bl(-0.36, 2.12, 0.40), (0.23, 0.24, 0.07), "Seat", e=0.4)
	lean = math.radians(14)
	mb.blob(bl(-0.36, 2.36, 0.80), (0.24, 0.07, 0.36), "Seat", e=0.45, basis=Matrix.Rotation(-lean, 3, "X"))
	cage = []
	for side in (1, -1):
		leg = [bl(side * 0.63, 2.50, 0.25), bl(side * 0.64, 2.50, 0.95), bl(side * 0.56, 2.50, 1.24), bl(side * 0.46, 2.50, 1.34)]
		cage += list(zip(leg, leg[1:]))
		cage.append((bl(side * 0.62, 1.27, 0.95), bl(side * 0.46, 1.88, 1.33)))  # A-pillar bar
		cage.append((bl(side * 0.46, 1.88, 1.33), bl(side * 0.46, 2.50, 1.34)))  # roof bar
		cage.append((bl(side * 0.46, 2.50, 1.34), bl(side * 0.55, 3.05, 0.62)))  # rear stay
		cage.append((bl(side * 0.62, 1.27, 0.95), bl(side * 0.62, 1.27, 0.25)))
	cage.append((bl(0.46, 2.50, 1.34), bl(-0.46, 2.50, 1.34)))
	cage.append((bl(0.46, 1.88, 1.33), bl(-0.46, 1.88, 1.33)))
	cage.append((bl(0.63, 2.50, 0.28), bl(-0.46, 2.50, 1.33)))  # diagonal
	cage.append((bl(-0.63, 1.60, 0.55), bl(-0.63, 2.45, 0.62)))  # driver's door bar
	for a, b in cage:
		mb.tube(a, b, 0.02, "Cage", segs=8)
	return details, pj, mb


def build_stripes(pj):
	mb = MB()
	for x in (-0.16, 0.16):
		pj.strip(mb, 0.17, S_SCUTTLE - 0.01, x - 0.07, x + 0.07, 40, 2, top_proj, "Stripe", offset=0.0018)
		pj.strip(mb, S_WS_TOP + 0.02, S_RG0 - 0.012, x - 0.07, x + 0.07, 30, 2, top_proj, "Stripe", offset=0.0018)
	return mb


def build_wheel():
	"""13" steel wheel with a 145/70 R13 tyre; axle along X, outer face towards +X."""
	mb = MB()
	hw = TYRE_W / 2
	tyre = [(hw - 0.012, 0.172), (hw + 0.004, 0.19), (hw + 0.006, 0.22), (hw, 0.245), (hw - 0.012, 0.261),
		(hw - 0.03, 0.2665), (0.0, 0.2672), (-hw + 0.03, 0.2665), (-hw + 0.012, 0.261), (-hw, 0.245),
		(-hw - 0.006, 0.22), (-hw - 0.004, 0.19), (-hw + 0.012, 0.172)]
	cen = Vector((0.0, 0.0, 0.0))

	def tyre_out(c):
		r = math.hypot(c.y, c.z)
		radial = Vector((0, c.y / r, c.z / r))
		return Vector((c.x, 0, 0)) * 2.0 + radial * (r - 0.22)
	mb.lathe(tyre, 40, "Tyre", out=tyre_out)
	# tread grooves: three thin dark rings
	for x in (-0.03, 0.0, 0.03):
		mb.lathe([(x - 0.004, 0.2674), (x + 0.004, 0.2674)], 40, "Grille", out=lambda c: Vector((0, c.y, c.z)))
	# raised sidewall lettering: four grey arcs on the outer face, so a turning wheel reads as turning
	for k in range(4):
		a0 = 2 * math.pi * k / 4 + 0.25
		rows = []
		for r in (0.207, 0.231):
			rows.append([Vector((hw + 0.0078 - 0.0034 * (r - 0.207) / 0.024, r * math.cos(a0 + 0.95 * j / 8),
				r * math.sin(a0 + 0.95 * j / 8))) for j in range(9)])
		mb.grid(rows, "Sidewall", out=Vector((1, 0, 0)))
	rim = [(hw - 0.004, 0.178), (hw - 0.012, 0.168), (0.045, 0.163), (0.032, 0.160), (0.028, 0.150), (0.030, 0.125),
		(0.036, 0.10), (0.040, 0.075), (0.041, 0.04), (0.041, 0.0)]
	mb.lathe(rim, 40, "Rim", out=lambda c: Vector((1.0, 0, 0)) - Vector((0, c.y, c.z)) * 2.0)
	# brake drum behind the dish
	mb.lathe([(0.0, 0.0), (0.0, 0.14), (-0.06, 0.14)], 24, "Under", out=lambda c: Vector((1.0, c.y, c.z)))
	# ventilation holes, wheel nuts and the centre cap
	for k in range(6):
		a = 2 * math.pi * (k + 0.5) / 6
		c = Vector((0.0335, 0.118 * math.cos(a), 0.118 * math.sin(a)))
		ring = [c + Vector((0.0, 0.016 * math.cos(2 * math.pi * j / 12), 0.011 * math.sin(2 * math.pi * j / 12)))
			for j in range(12)]
		rot = Vector((0, math.cos(a), math.sin(a)))
		tang = Vector((0, -math.sin(a), math.cos(a)))
		ring = [c + rot * ((p - c).y) + tang * ((p - c).z) for p in ring]
		ids = [mb.vert(p) for p in ring]
		mb.face(ids, "Grille", Vector((1, 0, 0)))
	for k in range(4):
		a = 2 * math.pi * k / 4 + math.pi / 4
		p = Vector((0.041, 0.049 * math.cos(a), 0.049 * math.sin(a)))
		mb.tube(p, p + Vector((0.013, 0, 0)), 0.0095, "Chrome", segs=6)
	mb.lathe([(0.041, 0.030), (0.050, 0.028), (0.056, 0.018), (0.058, 0.0)], 20, "Steel", out=lambda c: Vector((1, c.y, c.z)))
	return mb


# ---------------------------------------------------------------- previews
def setup_preview(paint):
	scene = bpy.context.scene
	for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
		try:
			scene.render.engine = eng
			break
		except TypeError:
			continue
	scene.render.resolution_x = 1200
	scene.render.resolution_y = 800
	scene.render.film_transparent = False
	world = bpy.data.worlds.new("World")
	world.use_nodes = True
	bg = world.node_tree.nodes["Background"]
	bg.inputs["Color"].default_value = (0.55, 0.62, 0.72, 1)
	bg.inputs["Strength"].default_value = 0.9
	scene.world = world
	sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
	sun.data.energy = 3.5
	sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(35))
	scene.collection.objects.link(sun)
	ground = bpy.data.meshes.new("Ground")
	ground.from_pydata([(-20, -20, 0), (20, -20, 0), (20, 20, 0), (-20, 20, 0)], [], [(0, 1, 2, 3)])
	gm = bpy.data.materials.new("GroundMat")
	gm.use_nodes = True
	gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.25, 0.25, 0.25, 1)
	ground.materials.append(gm)
	scene.collection.objects.link(bpy.data.objects.new("Ground", ground))
	tint = bpy.data.materials["Paint"].node_tree.nodes["Tint"]
	next(s for s in tint.inputs if s.identifier == "A_Color").default_value = (*paint, 1)
	cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
	scene.collection.objects.link(cam)
	scene.camera = cam
	return cam


def render_views(cam, out_dir):
	os.makedirs(out_dir, exist_ok=True)
	views = {
		"front34": ((4.4, 4.6, 1.6), 38),
		"rear34": ((-4.2, -4.8, 1.8), 38),
		"side": ((7.5, 0.0, 0.75), 30),
		"front": ((0.0, 8.0, 0.8), 22),
		"rear": ((0.0, -8.0, 0.9), 22),
		"top": ((0.0, 0.0, 9.0), 30),
		"closeup": ((2.4, 3.6, 1.2), 45),
	}
	for name, (pos, lens_deg) in views.items():
		cam.location = pos
		target = Vector((0, 0, 0.62))
		d = target - Vector(pos)
		cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
		cam.data.angle = math.radians(lens_deg)
		if name == "side" or name == "front" or name == "rear" or name == "top":
			cam.data.type = "ORTHO"
			cam.data.ortho_scale = 4.0 if name != "top" else 3.8
			if name == "top":
				cam.rotation_euler = (0, 0, 0)
		else:
			cam.data.type = "PERSP"
		bpy.context.scene.render.filepath = os.path.join(out_dir, name + ".png")
		bpy.ops.render.render(write_still=True)


# ---------------------------------------------------------------- main
def main():
	bpy.ops.wm.read_factory_settings(use_empty=True)
	body = build_body()
	details, pj, cabin_mb = build_details(body)
	liner = build_liner(body)
	stripes = build_stripes(pj)
	wheel = build_wheel()
	body.extend(liner)
	objs = [body.emit("Body", sharp_deg=55, colors=True), details.emit("Details", sharp_deg=40),
		stripes.emit("Stripes"), wheel.emit("Wheel", sharp_deg=40), cabin_mb.emit("Cabin", sharp_deg=40)]
	for name, ob in (("Body", objs[0]), ("Details", objs[1]), ("Stripes", objs[2]), ("Wheel", objs[3]), ("Cabin", objs[4])):
		print("%-8s %6d tris" % (name, sum(len(p.vertices) - 2 for p in ob.data.polygons)))
	os.makedirs(os.path.dirname(OUT_GLB), exist_ok=True)
	kw = dict(filepath=OUT_GLB, export_format="GLB", use_selection=False, export_apply=True, export_yup=True,
		export_texcoords=False, export_normals=True, export_tangents=False, export_cameras=False,
		export_lights=False, export_extras=False)
	props = bpy.ops.export_scene.gltf.get_rna_type().properties.keys()
	if "export_vertex_color" in props:
		kw["export_vertex_color"] = "ACTIVE"
	elif "export_colors" in props:
		kw["export_colors"] = True
	bpy.ops.export_scene.gltf(**kw)
	print("wrote", OUT_GLB)
	if arg("--blend"):
		bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(arg("--blend")))
	if arg("--renders"):
		cam = setup_preview((0.75, 0.05, 0.04))
		for sx in (1, -1):
			for sc in (FRONT_AXLE_S, REAR_AXLE_S):
				w = bpy.data.objects.new("W", objs[3].data)
				w.location = bl(sx * TRACK / 2, sc, TYRE_R)
				w.scale.x = sx
				bpy.context.scene.collection.objects.link(w)
		objs[3].hide_render = True
		render_views(cam, os.path.abspath(arg("--renders")))


if __name__ == "__main__":
	main()
