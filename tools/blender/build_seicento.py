"""Builds the game's Fiat Seicento 900 (Type 187, 1998-2000 pre-facelift "S"/"Young"/Trofeo Cup) in Blender.

Run from the repository root (Blender 4.2 or newer, headless):

    blender -b -P tools/blender/build_seicento.py -- [--renders DIR] [--blend FILE]

Writes godot/models/seicento.glb. With --renders it also saves turntable-style previews (PNG) and with
--blend the working .blend file.

Everything is generated from the real-car dimensions below: 3319 mm long, 1508 mm wide, 1420 mm high,
2200 mm wheelbase, 1263/1262 mm track, 145/70 R13 tyres on 13" steel wheels.

Scene objects (Godot looks them up by name):
  Body     painted shell with glass, black trim, underbody, stamped arch lips, panel shut grooves
           and the cabin liner (vertex colours carry the panel gaps; the Paint surface is re-coloured per car)
  Details  bumpers, segmented lamps, fog lights, mirrors, wipers, badges, wheel wells, exhaust, tow hooks
  Stripes  twin bonnet/roof stripes (toggled per car)
  Cabin    sculpted dashboard, instrument binnacle, tachometer pod, center console, gear shifter,
           handbrake, drilled pedals, rearview mirror, bucket seat with 5-point harness, fire extinguisher,
           and multi-point roll cage (Godot hides it on distant cars)
  Wheel    13" steel wheel with 12 stamped oval cooling vents, 4 lug bolts, central grease cap,
           detailed 145/70 R13 directional multi-channel tread with shoulder sipes, and cast steel brake
           disc rotor (one wheel at origin, outer face towards +X; mirror it for the left side)
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

S_START, S_END = 0.0, LENGTH
S_COWL, S_WS_TOP = 1.10, 1.80
S_SCUTTLE = 1.04
S_SAIL = 1.27
S_B0, S_B1 = 2.30, 2.37
S_QR = 2.70  # the quarter light's rear edge curves down from here to S_Q1
S_Q1 = 2.99
S_RG0, S_RG1 = 2.965, 3.135
S_DOOR = (1.06, 2.335)
FRIT = 0.015
PILLAR = 0.07

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
# Plan, elevation and section lines traced from photos of the real car: a rounded nose whose bonnet drops
# steeply to the headlamps, wraparound plastic bumpers proud of the body, a steeply raked windscreen, a flat
# roof and a short tail whose big rear window leans back over horizontal lamps on the bumper.
W = Curve([(0.0, 0.50), (0.03, 0.578), (0.08, 0.642), (0.15, 0.69), (0.25, 0.72), (0.35, 0.734), (0.64, 0.742),
	(1.5, 0.745), (2.84, 0.743), (3.05, 0.733), (3.15, 0.712), (3.22, 0.68), (3.27, 0.64), (3.30, 0.60),
	(LENGTH, 0.535)])
ZM = Curve([(0.0, 0.40), (0.3, 0.44), (1.0, 0.46), (2.8, 0.47), (LENGTH, 0.44)])
WSH = Curve([(0.0, 0.45), (0.05, 0.52), (0.1, 0.575), (0.16, 0.622), (0.25, 0.66), (0.4, 0.684), (0.6, 0.697),
	(1.1, 0.703), (2.0, 0.706), (2.9, 0.702), (3.05, 0.69), (3.15, 0.662), (3.22, 0.625), (3.27, 0.585),
	(LENGTH, 0.51)])
ZSH = Curve([(0.0, 0.52), (0.05, 0.545), (0.08, 0.595), (0.11, 0.64), (0.16, 0.675), (0.25, 0.70), (0.5, 0.735),
	(0.8, 0.785), (1.0, 0.845), (S_COWL, 0.88), (1.3, 0.905), (2.0, 0.93), (2.6, 0.95), (2.9, 0.96), (3.05, 0.958),
	(3.12, 0.948), (3.17, 0.925), (3.22, 0.86), (3.25, 0.74), (3.28, 0.62), (LENGTH, 0.575)])
ZT = Curve([(0.0, 0.54), (0.04, 0.555), (0.075, 0.615), (0.105, 0.668), (0.15, 0.705), (0.25, 0.742), (0.4, 0.772),
	(0.6, 0.808), (0.85, 0.858), (1.05, 0.90), (S_COWL, 0.915), (1.30, 1.058), (1.50, 1.20), (1.70, 1.33),
	(S_WS_TOP, 1.374), (1.90, 1.400), (2.1, 1.414), (2.5, 1.42), (2.8, 1.412), (2.93, 1.395), (2.965, 1.375),
	(3.0, 1.34), (3.06, 1.215), (3.135, 1.03), (3.17, 0.96), (3.2, 0.87), (3.235, 0.75), (3.255, 0.665),
	(3.268, 0.628), (3.29, 0.612), (LENGTH, 0.595)])
ZB = Curve([(0.0, 0.25), (0.06, 0.215), (0.2, 0.205), (0.35, 0.22), (1.0, 0.235), (2.5, 0.235), (3.1, 0.225),
	(3.25, 0.23), (LENGTH, 0.27)])
WR = Curve([(0.0, 0.40), (0.05, 0.47), (0.1, 0.535), (0.2, 0.595), (0.6, 0.62), (S_COWL, 0.625), (1.45, 0.598),
	(S_WS_TOP, 0.566), (2.4, 0.556), (2.9, 0.558), (3.0, 0.572), (3.1, 0.586), (3.17, 0.588), (3.25, 0.55),
	(LENGTH, 0.50)])
DR = Curve([(0.0, 0.015), (0.2, 0.04), (S_COWL, 0.045), (S_WS_TOP, 0.03), (3.17, 0.03), (LENGTH, 0.015)])

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
	B = Vector((w - 0.075, zb))
	C = Vector((w - 0.024, zb + 0.045))
	D = Vector((w, max(ZM(s), zb + 0.10)))
	E = Vector((WSH(s), zsh))
	c = cabin(s)
	F = E + Vector((-lerp(0.012, 0.022, c), lerp(0.006, 0.012, c)))
	hz = max(ZT(s) - DR(s), F.y + 0.012)
	H = Vector((WR(s), hz))
	I = Vector((0.0, max(ZT(s), hz + 0.004)))
	gz = max(F.y + 0.004, H.y - PILLAR)
	if s > S_QR:
		k = min(1.0, (s - S_QR) / (S_Q1 - S_QR))
		gz = F.y + max(0.004, (gz - F.y) * math.sqrt(max(0.0, 1.0 - k * k)))
	G = F + (H - F) * ((gz - F.y) / (H.y - F.y))
	return [A, B, C, D, E, F, G, H, I]


def cr(p0, p1, p2, p3, t):
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
	e = min(s - s0, s1 - s)
	if e >= radius or e < 0:
		return 0.0
	k = (radius - e) / radius
	return depth * (1.0 - math.sqrt(max(0.0, 1.0 - k * k)))


def hi_params(s):
	te = 0.01
	if S_COWL < s < S_WS_TOP:
		te += glass_corner(s, S_COWL, S_WS_TOP, 0.07, 0.12)
	elif S_RG0 < s < S_RG1:
		te += glass_corner(s, S_RG0, S_RG1, 0.06, 0.14)
	fr = 0.035
	rest = [te + fr + (1.0 - te - fr) * k / 6.0 for k in range(1, 7)]
	return [0.0, te, te + fr] + rest


def section(s):
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
	"Paint": ((1.0, 1.0, 1.0), 0.32, 0.05, {"coat": 0.9}),
	"Glass": ((0.06, 0.08, 0.09), 0.04, 0.0, {"alpha": 0.32}),
	"Trim": ((0.018, 0.018, 0.02), 0.42, 0.0, {}),
	"Gasket": ((0.012, 0.012, 0.014), 0.82, 0.0, {}),
	"Under": ((0.012, 0.012, 0.012), 0.9, 0.0, {}),
	"Interior": ((0.045, 0.045, 0.05), 0.85, 0.0, {}),
	"Bumper": ((0.075, 0.077, 0.08), 0.62, 0.0, {}),
	"Grille": ((0.01, 0.01, 0.01), 0.7, 0.0, {}),
	"Chrome": ((0.85, 0.86, 0.88), 0.12, 1.0, {}),
	"Exhaust": ((0.75, 0.76, 0.78), 0.16, 0.95, {}),
	"Headlight": ((0.42, 0.43, 0.44), 0.04, 0.85, {"emit": ((1.0, 0.95, 0.84), 0.2)}),
	"Indicator": ((1.0, 0.42, 0.04), 0.1, 0.0, {"emit": ((1.0, 0.4, 0.02), 0.1)}),
	"Taillight": ((0.30, 0.0, 0.01), 0.08, 0.0, {"emit": ((1.0, 0.05, 0.03), 0.15)}),
	"LampClear": ((0.85, 0.80, 0.80), 0.08, 0.0, {}),
	"Plate": ((0.94, 0.93, 0.89), 0.45, 0.0, {}),
	"Seat": ((0.03, 0.03, 0.035), 0.9, 0.0, {}),
	"Harness": ((0.76, 0.07, 0.07), 0.65, 0.0, {}),
	"Cage": ((0.55, 0.56, 0.58), 0.45, 0.6, {}),
	"Tyre": ((0.03, 0.03, 0.03), 0.8, 0.0, {}),
	"Sidewall": ((0.085, 0.085, 0.085), 0.7, 0.0, {}),
	"Rim": ((0.5, 0.51, 0.53), 0.3, 0.75, {}),
	"Steel": ((0.36, 0.37, 0.38), 0.42, 0.5, {}),
	"BrakeDisc": ((0.62, 0.63, 0.65), 0.28, 0.85, {}),
	"BrakeCaliper": ((0.80, 0.12, 0.09), 0.35, 0.1, {}),
	"TowHook": ((0.92, 0.10, 0.06), 0.35, 0.0, {}),
	"Yellow": ((0.95, 0.76, 0.06), 0.35, 0.0, {}),
	"BadgeBlue": ((0.03, 0.12, 0.35), 0.25, 0.2, {}),
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
		if out is not None:
			pts = [self.v[i] for i in idx]
			ref = out(sum(pts, Vector()) / len(pts)) if callable(out) else out
			if newell(pts).dot(ref) < 0:
				idx = list(reversed(idx))
		self.f.append(list(idx))
		self.m.append(mat)

	def poly(self, pts, mat, out=None, col=1.0):
		return self.face([self.vert(p, col) for p in pts], mat, out)

	def quad(self, a, b, c, d, mat, out=None, col=1.0):
		self.poly([a, b, c, d], mat, out, col)

	def disc(self, centre, r, mat, normal=(0, 0, 1), segs=16, col=1.0):
		c, n = Vector(centre), Vector(normal).normalized()
		helper = Vector((1, 0, 0)) if abs(n.x) < 0.9 else Vector((0, 1, 0))
		u = n.cross(helper).normalized()
		v = n.cross(u)
		self.poly([c + (u * math.cos(2 * math.pi * k / segs) + v * math.sin(2 * math.pi * k / segs)) * r
			for k in range(segs)], mat, n, col=col)

	def ring(self, centre, r_in, r_out, mat, normal=(0, 0, 1), segs=16, col=1.0):
		c, n = Vector(centre), Vector(normal).normalized()
		helper = Vector((1, 0, 0)) if abs(n.x) < 0.9 else Vector((0, 1, 0))
		u = n.cross(helper).normalized()
		v = n.cross(u)
		pts_in = [c + (u * math.cos(2 * math.pi * k / segs) + v * math.sin(2 * math.pi * k / segs)) * r_in for k in range(segs)]
		pts_out = [c + (u * math.cos(2 * math.pi * k / segs) + v * math.sin(2 * math.pi * k / segs)) * r_out for k in range(segs)]
		for k in range(segs):
			k2 = (k + 1) % segs
			self.quad(pts_in[k], pts_out[k], pts_out[k2], pts_in[k2], mat, n, col=col)

	def grid(self, rows, mat, closed=False, out=None, cap_ends=False):
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
	rings = []
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
			# Crisp panel shut lines
			if groove and SEG_ROWS[0] + 1 <= j <= sum(SEG_ROWS[:SEG_EF]):
				x -= 0.0025
				col = 0.08
			if s < S_COWL - 0.015 and j == sum(SEG_ROWS[:SEG_FG]):
				col = 0.15
			if s > S_Q1 + 0.02 and j == sum(SEG_ROWS[:SEG_FG]):
				col = 0.15
			right.append((x, z, col))
		ring = [mb.vert(bl(x, s, z), c) for x, z, c in right]
		ring += [mb.vert(bl(-right[j][0], s, right[j][1]), right[j][2]) for j in range(R - 1, 0, -1)]
		rings.append(ring)
		ring_s.append(s)
	M = 2 * R

	def band_of(k):
		return k if k < R else 2 * R - k - 1

	# Connect station rings with quads
	for i in range(len(rings) - 1):
		smid = (ring_s[i] + ring_s[i + 1]) / 2
		for k in range(M):
			seg, sub = seg_bands[band_of(k)]
			mat = band_material(seg, sub, smid)
			a, b = rings[i], rings[i + 1]
			mb.face([a[k], a[(k + 1) % M], b[(k + 1) % M], b[k]], mat)

	# Clean planar/quad closure of the front face (no pinched dome pole!)
	r_front = rings[0]
	for j in range(R):
		j_next = j + 1
		if j == 0:
			mb.face([r_front[0], r_front[1], r_front[M - 1]], "Under", Vector((0, 1, 0)))
		elif j == R - 1:
			mb.face([r_front[R - 1], r_front[R], r_front[R + 1]], "Paint", Vector((0, 1, 0)))
		else:
			seg = seg_bands[j][0]
			mat = "Paint" if seg in (SEG_DE, SEG_EF, SEG_FG, SEG_GH, SEG_HI) else ("Bumper" if seg == SEG_CD else "Under")
			mb.face([r_front[j], r_front[j_next], r_front[M - j_next], r_front[M - j]], mat, Vector((0, 1, 0)))

	# Clean planar/quad closure of the rear tailgate (no pinched dome pole!)
	r_rear = rings[-1]
	for j in range(R):
		j_next = j + 1
		if j == 0:
			mb.face([r_rear[0], r_rear[M - 1], r_rear[1]], "Under", Vector((0, -1, 0)))
		elif j == R - 1:
			mb.face([r_rear[R - 1], r_rear[R + 1], r_rear[R]], "Paint", Vector((0, -1, 0)))
		else:
			seg = seg_bands[j][0]
			mat = "Paint" if seg in (SEG_DE, SEG_EF, SEG_FG, SEG_GH, SEG_HI) else ("Bumper" if seg == SEG_CD else "Under")
			mb.face([r_rear[j], r_rear[M - j], r_rear[M - j_next], r_rear[j_next]], mat, Vector((0, -1, 0)))

	# Rolled wheel-arch lips: a narrow raised rim, no flare (the real car's arches are plain cut-outs)
	for v in mb.v:
		ax = abs(v.x)
		if ax < 0.45 or v.z < 0.18:
			continue
		s = Y0 - v.y
		for sc in (FRONT_AXLE_S, REAR_AXLE_S):
			d = math.hypot(s - sc, v.z - TYRE_R)
			if d < ARCH_R + 0.03:
				v.x += math.copysign(0.006 * (1.0 - smoothstep(ARCH_R + 0.012, ARCH_R + 0.03, d))
					* (1.0 - smoothstep(0.80, 0.9, v.z)), v.x)
	return mb


def build_liner(body):
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


# ---------------------------------------------------------------- projector & helpers
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

	def star(self, mb, outline, proj, mat, offset=0.003, bulge=0.0, rings=3, skirt=0.005, samples=6):
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


	def band(self, mb, us, vs, off, mat, proj, caps=False):
		"""A moulded strip over the body: rows at heights vs, columns at us, each point pushed off the surface
		by off(u, v) (so a profile can step in and out); mat(u, v) picks each face's material at its centre."""
		pts, nors = [], []
		for u in us:
			row, nrow = [], []
			for v in vs:
				loc, nor = self.hit(*proj(u, v))
				row.append(loc + nor * off(u, v))
				nrow.append(nor)
			pts.append(row)
			nors.append(nrow)
		ids = [[mb.vert(p) for p in row] for row in pts]
		for i in range(len(us) - 1):
			for j in range(len(vs) - 1):
				ref = nors[i][j] + nors[i + 1][j] + nors[i][j + 1] + nors[i + 1][j + 1]
				mb.face([ids[i][j], ids[i + 1][j], ids[i + 1][j + 1], ids[i][j + 1]],
					mat((us[i] + us[i + 1]) / 2, (vs[j] + vs[j + 1]) / 2), ref)
		if caps:
			for i, k in ((0, 1), (len(us) - 1, len(us) - 2)):
				inner = [pts[i][j] - nors[i][j] * 0.004 for j in range(len(vs))]
				ref = pts[i][len(vs) // 2] - pts[k][len(vs) // 2]
				mb.poly(pts[i] + list(reversed(inner)), mat(us[i], vs[len(vs) // 2]), ref)
		return pts


def resample(pts, per_seg):
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
	def f(u, v):
		th = math.radians(u)
		dx = side * math.sin(th)
		ds = math.cos(th) if rear else -math.cos(th)
		target = bl(side * ax, as_, v)
		origin = bl(side * ax + dx * 2.0, as_ + ds * 2.0, v)
		return origin, (target - origin).normalized()
	return f


def side_proj(side):
	def f(u, v):
		return bl(side * 2.0, u, v), Vector((-side, 0.0, 0.0))
	return f


def cyl_proj(as_, rear):
	"""Wraps round the nose or tail: u is the angle (degrees) from the car's axis, seen from a vertical axis at
	station as_ on the centre line; v is the height."""
	def f(u, v):
		th = math.radians(u)
		target = bl(0.0, as_, v)
		origin = bl(math.sin(th) * 3.0, as_ + (math.cos(th) if rear else -math.cos(th)) * 3.0, v)
		return origin, (target - origin).normalized()
	return f


def front_proj(u, v):
	return bl(u, -1.0, v), Vector((0.0, -1.0, 0.0))


def rear_proj(u, v):
	return bl(u, LENGTH + 1.0, v), Vector((0.0, 1.0, 0.0))


def top_proj(u, v):
	return bl(v, u, 3.0), Vector((0.0, 0.0, -1.0))


# ---------------------------------------------------------------- bumpers
FB_AXIS, FB_SPAN = 0.75, 56.0  # front bumper: wraps from arch to arch round this station
RB_AXIS, RB_SPAN = 2.62, 52.0
FB_TOP, RB_TOP = 0.556, 0.608


def spread(a, b, step, extra=()):
	n = max(1, int(round((b - a) / step)))
	return sorted(set([round(a + (b - a) * i / n, 4) for i in range(n + 1)] + [e for e in extra if a < e < b]))


def profile(v, rows):
	"""Piecewise-linear offset profile through (height, offset) rows."""
	if v <= rows[0][0]:
		return rows[0][1]
	for (v0, o0), (v1, o1) in zip(rows, rows[1:]):
		if v <= v1:
			return lerp(o0, o1, (v - v0) / (v1 - v0))
	return rows[-1][1]


def build_bumpers(pj, mb):
	"""Grey wraparound plastic bumpers standing 2 cm proud of the shell, as on the 1998-2000 900/Young/S:
	a smooth upper bar, a full-width recessed intake band with the plate on the front, a plate recess on the
	rear, and a ledge on top where the lamps sit."""
	# front
	fp = cyl_proj(FB_AXIS, False)
	rows = [(0.219, -0.003), (0.223, 0.011), (0.236, 0.02), (0.535, 0.02), (0.548, 0.016), (0.553, 0.008),
		(FB_TOP, -0.003)]
	recess = lambda u: 1.0 - smoothstep(37.0, 40.0, abs(u))

	def f_off(u, v):
		o = profile(v, rows)
		if 0.297 < v < 0.425:
			o = lerp(o, 0.006, recess(u) * smoothstep(0.297, 0.303, v) * (1.0 - smoothstep(0.419, 0.425, v)))
		return o + 0.022 * max(0.0, 1.0 - (u / 38.0) ** 2)  # the face bows forward a little

	def f_mat(u, v):
		return "Grille" if recess(u) > 0.5 and 0.303 < v < 0.419 else "Bumper"
	us = spread(-FB_SPAN, FB_SPAN, 1.5, (-40, -38.5, -37, 37, 38.5, 40))
	vs = sorted(set([r[0] for r in rows] + [0.26, 0.297, 0.303, 0.36, 0.419, 0.425, 0.48]))
	pj.band(mb, us, vs, f_off, f_mat, fp, caps=True)
	# intake grille bars and the number plate on its bracket
	for z in (0.335, 0.37, 0.39):
		pj.strip(mb, -0.50, 0.50, z, z + 0.006, 30, 1, front_proj, "Bumper", offset=0.03)
	pj.star(mb, rounded_rect(-0.262, 0.262, 0.306, 0.416, 0.008), front_proj, "Trim", offset=0.034, rings=1,
		samples=2, skirt=0.01)
	pj.star(mb, rounded_rect(-0.255, 0.255, 0.311, 0.411, 0.006), front_proj, "Plate", offset=0.036, rings=1,
		samples=2, skirt=0.0)

	# rear
	rp = cyl_proj(RB_AXIS, True)
	rows = [(0.238, -0.003), (0.243, 0.011), (0.256, 0.02), (0.50, 0.021), (0.506, 0.015), (0.514, 0.015),
		(0.52, 0.021), (0.585, 0.021), (0.598, 0.016), (0.603, 0.008), (RB_TOP, -0.003)]
	plate = lambda u: 1.0 - smoothstep(20.0, 22.0, abs(u))

	def r_off(u, v):
		o = profile(v, rows)
		if 0.355 < v < 0.485:
			o = lerp(o, 0.006, plate(u) * smoothstep(0.355, 0.361, v) * (1.0 - smoothstep(0.479, 0.485, v)))
		return o + 0.012 * max(0.0, 1.0 - (u / 36.0) ** 2)

	def r_mat(u, v):
		return "Under" if plate(u) > 0.5 and 0.361 < v < 0.479 else "Bumper"
	us = spread(-RB_SPAN, RB_SPAN, 1.5, (-22, -21, -20, 20, 21, 22))
	vs = sorted(set([r[0] for r in rows] + [0.30, 0.355, 0.361, 0.42, 0.479, 0.485, 0.55]))
	pj.band(mb, us, vs, r_off, r_mat, rp, caps=True)
	pj.star(mb, rounded_rect(-0.262, 0.262, 0.364, 0.476, 0.008), rear_proj, "Trim", offset=0.029, rings=1,
		samples=2, skirt=0.01)
	pj.star(mb, rounded_rect(-0.255, 0.255, 0.369, 0.471, 0.006), rear_proj, "Plate", offset=0.031, rings=1,
		samples=2, skirt=0.0)


# ---------------------------------------------------------------- details & cabin
HEADLAMP = [(2.5, 0.556), (0.0, 0.567), (-1.0, 0.592), (0.0, 0.618), (2.5, 0.638), (7.0, 0.657), (16.0, 0.677),
	(27.0, 0.687), (37.0, 0.68), (45.0, 0.663), (50.0, 0.636), (49.5, 0.604), (45.0, 0.58), (34.0, 0.562),
	(18.0, 0.553), (8.0, 0.552)]
HEAD_AMBER = [(38.5, 0.679), (45.0, 0.663), (50.0, 0.636), (49.5, 0.604), (45.0, 0.58), (34.0, 0.562)]
def _hv(v):  # lift the lens's lower edge clear of the bumper ledge (0.556) so no jagged intersection shows
	return 0.576 + (v - 0.552) * (0.687 - 0.576) / (0.687 - 0.552)


HEADLAMP = [(u, _hv(v)) for u, v in HEADLAMP]
HEAD_AMBER = [(u, _hv(v)) for u, v in HEAD_AMBER]
TAILLAMP = [(1.5, 0.80), (0.2, 0.87), (1.5, 0.945), (8.0, 0.975), (22.0, 0.985), (36.0, 0.975), (46.0, 0.95),
	(52.0, 0.915), (53.0, 0.875), (50.0, 0.83), (42.0, 0.805), (28.0, 0.79), (12.0, 0.788)]


def build_details(body):
	mb = MB()
	pj_body = Projector(body)
	build_bumpers(pj_body, mb)
	both = MB()
	both.extend(body)
	both.extend(mb)
	pj = Projector(both)

	for side in (1, -1):
		# Lamps sit on the shell just above the bumper ledge, so they project onto the body alone
		pj, pj_all = pj_body, pj
		# Headlamps: the long rounded lamp on each nose corner with the amber indicator at its outer end
		hp = corner_proj(0.30, 0.62, side, False)
		pj.star(mb, HEADLAMP, hp, "Gasket", offset=0.003, rings=2, samples=3, skirt=0.0)
		inner = [(lerp(u, 21.0, 0.06), lerp(v, _hv(0.628), 0.12)) for u, v in HEADLAMP]
		pj.star(mb, inner, hp, "Headlight", offset=0.006, bulge=0.006, rings=3, samples=3, skirt=0.0)
		pj.star(mb, [(lerp(u, 43.0, 0.1), lerp(v, _hv(0.63), 0.12)) for u, v in HEAD_AMBER], hp, "Indicator",
			offset=0.0105, rings=2, samples=3, skirt=0.0)
		# the round main-beam reflector glinting through the lens
		pj.star(mb, ellipse(10.0, _hv(0.628), 5.5, 0.026, 16), hp, "Chrome", offset=0.0095, bulge=0.003, rings=2,
			samples=1, skirt=0.0)

		# Tail lamps: horizontal, wrapping round the rear corners on the bumper ledge; two round clear lenses
		tp = corner_proj(0.30, 2.85, side, True)
		pj.star(mb, TAILLAMP, tp, "Gasket", offset=0.003, rings=2, samples=3, skirt=0.0)
		pj.star(mb, [(lerp(u, 26.0, 0.05), lerp(v, 0.885, 0.12)) for u, v in TAILLAMP], tp, "Taillight",
			offset=0.006, bulge=0.005, rings=3, samples=3, skirt=0.0)
		for cu in (9.0, 21.0):
			pj.star(mb, ellipse(cu, 0.885, 4.6, 0.04, 16), tp, "LampClear", offset=0.0105, bulge=0.004, rings=2,
				samples=1, skirt=0.0)

		pj = pj_all
		sp = side_proj(side)
		# Front wing side repeater, behind the arch
		pj.star(mb, ellipse(0.985, 0.725, 0.022, 0.011, 12), sp, "Gasket", offset=0.002, rings=1, samples=2)
		pj.star(mb, ellipse(0.985, 0.725, 0.018, 0.008, 12), sp, "Indicator", offset=0.004, bulge=0.002, rings=2,
			samples=2)

		# Black rubbing strip along the door and quarter, arch to arch
		s0, s1 = 1.0, 2.47
		strip_rows = [(0.425, 0.0), (0.429, 0.006), (0.437, 0.011), (0.449, 0.012), (0.457, 0.008), (0.462, 0.0)]

		def rub(u, v, s0=s0, s1=s1):
			return profile(v, strip_rows) * smoothstep(s0, s0 + 0.03, u) * (1.0 - smoothstep(s1 - 0.03, s1, u))
		pj.band(mb, spread(s0, s1, 0.03, S_DOOR), [r[0] for r in strip_rows], rub, lambda u, v: "Trim", sp)

		# Race number panel on the door
		pj.star(mb, rounded_rect(1.57, 1.87, 0.50, 0.80, 0.03), sp, "Plate", offset=0.0022, rings=2, samples=2,
			skirt=0.003)

		# Door pull handle in its recess, with the lock barrel ahead of it
		pj.star(mb, rounded_rect(2.09, 2.21, 0.838, 0.874, 0.016), sp, "Trim", offset=0.0025, rings=2, samples=2)
		pj.star(mb, rounded_rect(2.10, 2.20, 0.845, 0.867, 0.01), sp, "Interior", offset=0.009, bulge=0.003,
			rings=1, samples=2)
		pj.star(mb, ellipse(2.06, 0.80, 0.009, 0.009, 10), sp, "Chrome", offset=0.004, rings=1, samples=1)

		# Door mirror: a black shell on the sail, glass facing back
		loc, _ = pj.hit(*sp(1.21, 0.935))
		mb.box(bl(loc.x + side * 0.03, 1.205, 0.935), (0.06, 0.09, 0.05), "Trim")
		hx = loc.x + side * 0.115
		mb.blob(bl(hx, 1.215, 0.975), (0.075, 0.04, 0.052), "Trim", e=0.5)
		mb.blob(bl(hx, 1.245, 0.975), (0.066, 0.006, 0.044), "Chrome", e=0.35)

		# Wheel-well liners (black arcs sealing the shell)
		for sc in (FRONT_AXLE_S, REAR_AXLE_S):
			rows = []
			for xo in (0.48, 0.735):
				row = []
				for k in range(21):
					a = math.radians(-12 + 204 * k / 20)
					row.append(bl(side * xo, sc - (ARCH_R - 0.006) * math.cos(a), TYRE_R + (ARCH_R - 0.006) * math.sin(a)))
				rows.append(row)
			mb.grid(rows, "Under", out=lambda q, sc=sc: Vector((0, (Y0 - sc) - q.y, TYRE_R - q.z)))

	# Fuel flap on the right rear quarter
	sp_right = side_proj(1)
	pj.star(mb, ellipse(2.70, 0.80, 0.058, 0.058, 20), sp_right, "Gasket", offset=0.0012, rings=1, samples=2,
		skirt=0.002)
	pj.star(mb, ellipse(2.70, 0.80, 0.054, 0.054, 20), sp_right, "Gasket", offset=-0.004, rings=1, samples=2,
		skirt=0.0)

	# Fiat five-bar badge on the nose
	pj.star(mb, rounded_rect(-0.034, 0.034, 0.598, 0.636, 0.008), front_proj, "Chrome", offset=0.003, rings=2,
		samples=2)
	pj.star(mb, rounded_rect(-0.030, 0.030, 0.602, 0.632, 0.006), front_proj, "BadgeBlue", offset=0.0045, rings=2,
		samples=2)
	for k in range(5):
		x = -0.020 + 0.010 * k
		pj.strip(mb, x - 0.0022, x + 0.0022, 0.605, 0.629, 1, 2, front_proj, "Chrome", offset=0.0065)
	# Competition tow eye through the intake
	loc_tow, _ = pj.hit(*front_proj(0.36, 0.33))
	mb.tube(loc_tow + Vector((0, 0.01, 0)), loc_tow + Vector((0, -0.05, 0)), 0.012, "TowHook", segs=8)
	mb.ring(loc_tow + Vector((0, -0.05, 0)), 0.02, 0.034, "TowHook", normal=(0, 1, 0), segs=16)

	# Tailgate: shut lines beside the lamps, lock, FIAT lettering and the Seicento script
	for x in (-0.31, 0.31):
		pj.strip(mb, x + 0.003, x - 0.003, 0.635, 0.955, 1, 12, rear_proj, "Trim", offset=0.0015)
	pj.star(mb, ellipse(0.0, 0.80, 0.016, 0.016, 12), rear_proj, "Trim", offset=0.002, rings=1, samples=1)
	pj.star(mb, ellipse(0.0, 0.80, 0.010, 0.010, 10), rear_proj, "Chrome", offset=0.004, rings=1, samples=1)
	pj.star(mb, rounded_rect(-0.27, -0.15, 0.742, 0.764, 0.004), rear_proj, "Chrome", offset=0.003, rings=1,
		samples=2)
	pj.star(mb, rounded_rect(-0.265, -0.155, 0.746, 0.760, 0.003), rear_proj, "BadgeBlue", offset=0.0042, rings=1,
		samples=2)
	pj.star(mb, rounded_rect(0.17, 0.30, 0.836, 0.852, 0.006), rear_proj, "Chrome", offset=0.003, rings=1,
		samples=2)
	# Rear competition tow eye under the bumper
	mb.tube(bl(-0.35, LENGTH - 0.05, 0.25), bl(-0.35, LENGTH + 0.03, 0.25), 0.012, "TowHook", segs=8)
	mb.ring(bl(-0.35, LENGTH + 0.03, 0.25), 0.020, 0.034, "TowHook", normal=(0, 1, 0), segs=16)

	# Third brake light at the top of the rear glass
	pj.star(mb, rounded_rect(-0.10, 0.10, 1.30, 1.328, 0.006), rear_proj, "Gasket", offset=0.002, rings=1, samples=2)
	pj.star(mb, rounded_rect(-0.092, 0.092, 1.304, 1.324, 0.005), rear_proj, "Taillight", offset=0.0045, bulge=0.002,
		rings=2, samples=2)

	# Scuttle washer jets
	for x in (-0.25, 0.25):
		pj.star(mb, ellipse(1.0, x, 0.012, 0.008, 8), top_proj, "Trim", offset=0.004, rings=1, samples=1)

	# Wipers parked along the scuttle: pivots, arms and blades
	for xp, x1 in ((-0.50, 0.02), (0.06, 0.56)):
		base_p = pj.hit(*top_proj(1.09, xp))[0]
		mb.blob(base_p + Vector((0, 0, 0.010)), (0.018, 0.018, 0.014), "Trim", e=0.3)
		a = base_p + Vector((0, 0, 0.018))
		b = pj.hit(*top_proj(1.16, x1))[0] + Vector((0, 0, 0.016))
		mb.tube(a, b, 0.006, "Trim", segs=6)
		bx0 = pj.hit(*top_proj(1.15, xp + 0.05))[0] + Vector((0, 0, 0.012))
		bx1 = pj.hit(*top_proj(1.18, x1 + 0.02))[0] + Vector((0, 0, 0.012))
		mb.box((bx0 + bx1) / 2, ((bx1 - bx0).length, 0.012, 0.012), "Trim",
			basis=Matrix.Rotation(math.atan2(bx1.y - bx0.y, bx1.x - bx0.x), 3, "Z"))

	# Roof aerial at the front of the roof
	base = pj.hit(*top_proj(1.87, 0.0))[0]
	mb.blob(base + Vector((0, 0, 0.012)), (0.022, 0.04, 0.016), "Trim", e=0.4)
	mb.tube(base + Vector((0, -0.015, 0.02)), base + Vector((0, -0.24, 0.36)), 0.0035, "Trim", segs=6)

	# Rear wiper, parked along the bottom of the glass
	p0 = pj.hit(*rear_proj(0.0, 1.02))[0]
	p1 = pj.hit(*rear_proj(-0.42, 1.05))[0]
	mb.blob(p0 + Vector((0, -0.012, 0)), (0.02, 0.016, 0.02), "Trim", e=0.3)
	mb.tube(p0 + Vector((0, -0.016, 0)), p1 + Vector((0, -0.014, 0)), 0.006, "Trim", segs=6)

	# Exhaust: transverse rear silencer and a plain tailpipe poking out under the right of the bumper
	mb.tube(bl(0.20, 2.86, 0.22), bl(-0.16, 2.86, 0.22), 0.08, "Steel", segs=14)
	mb.tube(bl(0.30, 2.95, 0.215), bl(0.30, LENGTH + 0.02, 0.22), 0.024, "Exhaust", segs=14, caps=False)
	mb.disc(bl(0.30, LENGTH + 0.019, 0.22), 0.021, "Under", normal=(0, 1, 0), segs=12)

	# Underbody: sump guard, engine bay and tail closed off, flat floor
	mb.box(bl(0, 0.62, 0.20), (0.75, 0.6, 0.03), "Steel")
	mb.box(bl(0, 0.62, 0.38), (1.0, 0.80, 0.40), "Under")
	mb.box(bl(0, 2.84, 0.38), (1.0, 0.72, 0.40), "Under")
	mb.box(bl(0, 1.74, 0.195), (0.9, 1.5, 0.07), "Under")

	# ---------------------------------------------------------------- cabin interior
	details = mb
	mb = MB()

	# Sculpted Fiat Seicento curved dashboard & passenger parcel shelf
	mb.blob(bl(0, 1.37, 0.86), (0.62, 0.16, 0.09), "Interior", e=0.3)
	mb.box(bl(0, 1.30, 0.62), (1.2, 0.1, 0.4), "Interior")
	# Center stack & console flowing to floor
	mb.box(bl(0, 1.45, 0.64), (0.24, 0.22, 0.38), "Interior")
	# Instrument binnacle hood over speedometer
	mb.blob(bl(-0.36, 1.44, 0.94), (0.16, 0.09, 0.06), "Interior", e=0.35)
	# Speedometer and gauge cluster dial faces
	mb.disc(bl(-0.36, 1.43, 0.93), 0.055, "Plate", normal=(0, -0.6, 0.8), segs=16)
	mb.tube(bl(-0.36, 1.43, 0.93), bl(-0.36, 1.41, 0.945), 0.003, "Trim", segs=4)
	# Iconic Seicento Sporting auxiliary rev counter / tachometer pod standing on top of dash
	tacho_p = bl(-0.16, 1.34, 0.97)
	mb.tube(tacho_p - Vector((0, 0, 0.04)), tacho_p, 0.014, "Interior", segs=8)
	mb.blob(tacho_p + Vector((0, 0.02, 0.03)), (0.042, 0.042, 0.042), "Interior", e=0.4)
	mb.disc(tacho_p + Vector((0, 0.055, 0.03)), 0.034, "Plate", normal=(0, 0.7, 0.7), segs=14)
	mb.tube(tacho_p + Vector((0, 0.055, 0.03)), tacho_p + Vector((0, 0.045, 0.045)), 0.0025, "Harness", segs=4)

	# Center eyeball air vents, hazard switch and toggle bank
	for sx in (-0.055, 0.055):
		mb.disc(bl(sx, 1.41, 0.83), 0.026, "Trim", normal=(0, -0.4, 0.9), segs=12)
		mb.ring(bl(sx, 1.41, 0.83), 0.023, 0.028, "Chrome", normal=(0, -0.4, 0.9), segs=12)
	# Hazard warning triangle button & race toggle switches
	mb.box(bl(0, 1.42, 0.76), (0.028, 0.015, 0.025), "Harness")
	for k in range(3):
		mb.tube(bl(-0.06 + 0.06 * k, 1.43, 0.71), bl(-0.06 + 0.06 * k, 1.45, 0.72), 0.004, "Chrome", segs=6)

	# Floor-mounted competition gear shift lever with accordion gaiter & round knob
	mb.blob(bl(0, 1.62, 0.32), (0.065, 0.08, 0.045), "Trim", e=0.3)
	mb.tube(bl(0, 1.62, 0.34), bl(0, 1.64, 0.54), 0.009, "Chrome", segs=8)
	mb.blob(bl(0, 1.64, 0.54), (0.022, 0.022, 0.026), "Interior", e=0.35)

	# Handbrake lever between seats
	mb.tube(bl(0.08, 1.80, 0.33), bl(0.08, 1.94, 0.44), 0.010, "Interior", segs=6)
	mb.tube(bl(0.08, 1.94, 0.44), bl(0.08, 1.96, 0.455), 0.006, "Chrome", segs=6)

	# Aluminium drilled racing pedal box (clutch, brake, throttle)
	for k, px in enumerate((-0.44, -0.37, -0.29)):
		mb.box(bl(px, 1.25, 0.30 + k * 0.01), (0.042, 0.01, 0.065), "Steel")
		mb.tube(bl(px, 1.25, 0.30 + k * 0.01), bl(px, 1.20, 0.44), 0.007, "Trim", segs=6)

	# Interior central rearview mirror mounted at windshield top
	mb.box(bl(0, 1.45, 1.32), (0.13, 0.015, 0.045), "Interior")
	mb.box(bl(0, 1.455, 1.32), (0.12, 0.004, 0.038), "Chrome")
	mb.tube(bl(0, 1.45, 1.34), bl(0, 1.44, 1.37), 0.006, "Trim", segs=6)

	# 3-spoke competition dished sports steering wheel with yellow 12 o'clock center stripe
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
		mat_rim = "Yellow" if k == 6 else "Seat"
		mb.tube(ring[k], ring[(k + 1) % 24], 0.014, mat_rim, segs=8, caps=False)
	# 3 drilled aluminium spokes
	mb.tube(sw, sw - v * 0.17, 0.012, "Steel", segs=6)
	mb.tube(sw, sw - u * 0.15 + v * 0.05, 0.012, "Steel", segs=6)
	mb.tube(sw, sw + u * 0.15 + v * 0.05, 0.012, "Steel", segs=6)
	# Central hub boss with horn button
	mb.disc(sw, 0.038, "Interior", normal=n, segs=14)
	mb.disc(sw + n * 0.003, 0.022, "BadgeBlue", normal=n, segs=12)
	mb.tube(sw, sw + n * -0.02 + Vector((0, 0.28, -0.12)), 0.022, "Trim", segs=8)

	# Sparco anatomical racing bucket seat with deep bolsters and harness slots
	lean = math.radians(14)
	rot_lean = Matrix.Rotation(-lean, 3, "X")
	# Seat cushion with thigh bolsters
	mb.blob(bl(-0.36, 2.12, 0.40), (0.22, 0.24, 0.075), "Seat", e=0.38)
	for sx in (-1, 1):
		mb.blob(bl(-0.36 + sx * 0.19, 2.12, 0.46), (0.055, 0.23, 0.09), "Seat", e=0.4)
	# Backrest with flared lateral shoulder wings and integrated headrest
	mb.blob(bl(-0.36, 2.36, 0.80), (0.24, 0.07, 0.36), "Seat", e=0.45, basis=rot_lean)
	for sx in (-1, 1):
		mb.blob(bl(-0.36 + sx * 0.21, 2.32, 0.78), (0.05, 0.08, 0.26), "Seat", e=0.4, basis=rot_lean)
	# Dual harness pass-through slots in headrest
	for sx in (-0.065, 0.065):
		mb.blob(bl(-0.36 + sx, 2.38, 0.98), (0.028, 0.06, 0.020), "Trim", e=0.3, basis=rot_lean)
	# Steel seat mounting rails bolted to floor
	for sx in (-0.22, 0.22):
		mb.box(bl(-0.36 + sx, 2.12, 0.24), (0.025, 0.45, 0.035), "Steel")

	# Sabelt 5-point competition racing harness in bright safety red
	for sx in (-0.065, 0.065):
		mb.tube(bl(-0.36 + sx, 2.48, 1.05), bl(-0.36 + sx, 2.37, 0.98), 0.016, "Harness", segs=6)
		mb.tube(bl(-0.36 + sx, 2.37, 0.98), bl(-0.36 + sx * 0.7, 2.18, 0.64), 0.018, "Harness", segs=6)
	mb.tube(bl(-0.55, 2.14, 0.36), bl(-0.36, 2.14, 0.54), 0.018, "Harness", segs=6)
	mb.tube(bl(-0.17, 2.14, 0.36), bl(-0.36, 2.14, 0.54), 0.018, "Harness", segs=6)
	mb.disc(bl(-0.36, 2.14, 0.54), 0.028, "Chrome", normal=(0, -0.6, 0.8), segs=12)

	# 2 kg on-board competition fire extinguisher on floor tunnel
	ext_p = bl(0.18, 1.95, 0.28)
	mb.tube(ext_p - Vector((0, 0.14, 0)), ext_p + Vector((0, 0.14, 0)), 0.052, "TowHook", segs=12)
	mb.blob(ext_p + Vector((0, 0.17, 0)), (0.025, 0.035, 0.025), "Chrome", e=0.3)
	for dy in (-0.08, 0.08):
		mb.ring(ext_p + Vector((0, dy, 0)), 0.052, 0.058, "Steel", normal=(0, 1, 0), segs=12)

	# Multi-point FIA homologated safety roll cage
	cage = []
	for side in (1, -1):
		leg = [bl(side * 0.63, 2.50, 0.25), bl(side * 0.64, 2.50, 0.95), bl(side * 0.56, 2.50, 1.24), bl(side * 0.46, 2.50, 1.34)]
		cage += list(zip(leg, leg[1:]))
		cage.append((bl(side * 0.62, 1.27, 0.95), bl(side * 0.46, 1.88, 1.33)))
		cage.append((bl(side * 0.46, 1.88, 1.33), bl(side * 0.46, 2.50, 1.34)))
		cage.append((bl(side * 0.46, 2.50, 1.34), bl(side * 0.55, 3.05, 0.62)))
		cage.append((bl(side * 0.62, 1.27, 0.95), bl(side * 0.62, 1.27, 0.25)))
		cage.append((bl(side * 0.63, 1.50, 0.40), bl(side * 0.63, 2.45, 0.70)))
		cage.append((bl(side * 0.63, 1.50, 0.70), bl(side * 0.63, 2.45, 0.40)))
	cage.append((bl(0.46, 2.50, 1.34), bl(-0.46, 2.50, 1.34)))
	cage.append((bl(0.46, 1.88, 1.33), bl(-0.46, 1.88, 1.33)))
	cage.append((bl(0.63, 2.50, 0.28), bl(-0.46, 2.50, 1.33)))
	cage.append((bl(0.56, 2.50, 1.05), bl(-0.56, 2.50, 1.05)))

	for a, b in cage:
		mb.tube(a, b, 0.021, "Cage", segs=8)
	return details, pj, mb


def build_stripes(pj):
	mb = MB()
	for x in (-0.16, 0.16):
		pj.strip(mb, 0.17, S_SCUTTLE - 0.01, x - 0.07, x + 0.07, 40, 2, top_proj, "Stripe", offset=0.0018)
		pj.strip(mb, S_WS_TOP + 0.02, S_RG0 - 0.012, x - 0.07, x + 0.07, 30, 2, top_proj, "Stripe", offset=0.0018)
	return mb


def build_wheel():
	"""13" steel wheel with 145/70 R13 tyre; axle along X, outer face towards +X."""
	mb = MB()
	hw = TYRE_W / 2
	# 145/70 R13 road tyre: rounded shoulders, a bulging sidewall and two circumferential tread grooves
	tyre = [(hw - 0.012, 0.172), (hw + 0.002, 0.185), (hw + 0.007, 0.215), (hw + 0.004, 0.243), (hw - 0.006, 0.258),
		(hw - 0.02, 0.2655), (0.034, 0.2668), (0.030, 0.2668), (0.028, 0.259), (0.020, 0.259), (0.018, 0.2672),
		(-0.018, 0.2672), (-0.020, 0.259), (-0.028, 0.259), (-0.030, 0.2668), (-0.034, 0.2668), (-hw + 0.02, 0.2655),
		(-hw + 0.006, 0.258), (-hw - 0.004, 0.243), (-hw - 0.007, 0.215), (-hw - 0.002, 0.185), (-hw + 0.012, 0.172)]

	def tyre_out(c):
		r = math.hypot(c.y, c.z)
		radial = Vector((0, c.y / r, c.z / r))
		return Vector((c.x, 0, 0)) * 2.0 + radial * (r - 0.22)
	mb.lathe(tyre, 48, "Tyre", out=tyre_out)

	# Tread blocks: shallow transverse slots across each shoulder rib
	for k in range(36):
		a = 2 * math.pi * k / 36
		for x0, x1 in ((0.036, hw - 0.012), (-hw + 0.012, -0.036)):
			r = 0.2671
			pts = [Vector((x, r * math.cos(a + da), r * math.sin(a + da))) for x, da in
				((x0, 0.0), (x1, 0.03), (x1, 0.045), (x0, 0.015))]
			mb.poly(pts, "Grille", lambda q: Vector((0, q.y, q.z)))

	# Raised sidewall lettering: 4 grey arcs on outer face
	for k in range(4):
		a0 = 2 * math.pi * k / 4 + 0.25
		rows = []
		for r in (0.207, 0.231):
			rows.append([Vector((hw + 0.0078 - 0.0034 * (r - 0.207) / 0.024, r * math.cos(a0 + 0.95 * j / 8),
				r * math.sin(a0 + 0.95 * j / 8))) for j in range(9)])
		mb.grid(rows, "Sidewall", out=Vector((1, 0, 0)))

	# Steel wheel rim profile with rolled bead lip and deep dish well
	rim = [(hw - 0.004, 0.178), (hw - 0.012, 0.168), (0.045, 0.163), (0.032, 0.160), (0.028, 0.150), (0.030, 0.125),
		(0.036, 0.10), (0.040, 0.075), (0.041, 0.04), (0.041, 0.0)]
	mb.lathe(rim, 40, "Rim", out=lambda c: Vector((1.0, 0, 0)) - Vector((0, c.y, c.z)) * 2.0)

	# Cast steel brake disc rotor visible behind rim dish
	mb.lathe([(0.012, 0.065), (0.012, 0.126), (0.003, 0.126), (0.003, 0.065)], 32, "BrakeDisc", out=lambda c: Vector((1.0, c.y, c.z)))
	# Brake drum / backing carrier behind disc
	mb.lathe([(0.0, 0.0), (0.0, 0.14), (-0.06, 0.14)], 24, "Under", out=lambda c: Vector((1.0, c.y, c.z)))

	# 12 stamped oval ventilation cooling holes around steel wheel dish
	for k in range(12):
		a = 2 * math.pi * (k + 0.5) / 12
		c = Vector((0.0335, 0.118 * math.cos(a), 0.118 * math.sin(a)))
		ring_pts = [c + Vector((0.0, 0.012 * math.cos(2 * math.pi * j / 10), 0.008 * math.sin(2 * math.pi * j / 10)))
			for j in range(10)]
		rot = Vector((0, math.cos(a), math.sin(a)))
		tang = Vector((0, -math.sin(a), math.cos(a)))
		ring_pts = [c + rot * ((p - c).y) + tang * ((p - c).z) for p in ring_pts]
		mb.poly(ring_pts, "Grille", Vector((1, 0, 0)))

	# 4 chrome hexagonal lug nuts
	for k in range(4):
		a = 2 * math.pi * k / 4 + math.pi / 4
		p = Vector((0.041, 0.049 * math.cos(a), 0.049 * math.sin(a)))
		mb.tube(p, p + Vector((0.013, 0, 0)), 0.0095, "Chrome", segs=6)

	# Central hub grease cap with stepped circular boss & stamped Fiat roundel
	mb.lathe([(0.041, 0.030), (0.050, 0.028), (0.056, 0.018), (0.058, 0.0)], 20, "Steel", out=lambda c: Vector((1, c.y, c.z)))
	mb.disc(Vector((0.0585, 0, 0)), 0.014, "BadgeBlue", normal=(1, 0, 0), segs=12)

	# Valve stem angled out from rim well
	a_valve = 0.82
	v_base = Vector((0.042, 0.155 * math.cos(a_valve), 0.155 * math.sin(a_valve)))
	v_tip = v_base + Vector((0.020, 0.006 * math.cos(a_valve), 0.006 * math.sin(a_valve)))
	mb.tube(v_base, v_tip, 0.004, "Trim", segs=6)
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
		"front34": ((4.4, 4.6, 1.6), 38, None),
		"rear34": ((-4.2, -4.8, 1.8), 38, None),
		"side": ((7.5, 0.0, 0.75), 30, None),
		"front": ((0.0, 8.0, 0.8), 22, None),
		"rear": ((0.0, -8.0, 0.9), 22, None),
		"top": ((0.0, 0.0, 9.0), 30, None),
		"closeup": ((2.4, 3.6, 1.2), 45, None),
		# the angles of the reference photos: low front-left and rear-left, at a standing eye height
		"ref_front": ((-2.9, 5.0, 1.35), 36, (0.0, 0.2, 0.62)),
		"ref_rear": ((-2.6, -5.0, 1.45), 36, (0.0, -0.3, 0.7)),
		"nose": ((-1.2, 3.4, 0.95), 30, (-0.15, Y0 - 0.15, 0.55)),
		"tail": ((1.0, -3.2, 1.0), 30, (0.15, Y0 - LENGTH + 0.1, 0.6)),
	}
	for name, (pos, lens_deg, aim) in views.items():
		cam.location = pos
		target = Vector(aim) if aim else Vector((0, 0, 0.62))
		d = target - Vector(pos)
		cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
		cam.data.angle = math.radians(lens_deg)
		if name == "side" or name == "front" or name == "rear" or name == "top":
			cam.data.type = "ORTHO"
			cam.data.ortho_scale = 4.0 if name != "top" else 3.8
			if name == "top":
				cam.rotation_euler = (0, 0, math.pi / 2)
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
