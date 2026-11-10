"""Builds the game's Volkswagen Golf IV (Typ 1J, 1997-2003, five-door hatchback) in Blender.

Run from the repository root (Blender 4.2 or newer, headless):

    blender -b -P tools/blender/build_golf4.py -- [--renders DIR] [--blend FILE]

Writes godot/models/golf4.glb. With --renders it also saves preview PNGs (front, rear, side, top, three-quarters).

The pilot car for the campaign's unlockable cars: same object and material names as build_seicento.py, so
race_car_visual.gd drives it unchanged (see AGENTS.md, "Adding the next car"). Real-car numbers: 4149 mm long,
1735 mm wide (mirrors folded), 1439 mm high, 2511 mm wheelbase, 1513/1494 mm track, 195/65 R15 tyres on 15" alloys.

Scene objects: Body (painted shell with glass, trim, mirrors, handles, underbody and cabin liner; vertex colours carry
the panel gaps), Details (lamps, bumper plastics, grille, plates, wipers, exhaust, wheel wells), Stripes, Martini,
Abarth, Marlboro (liveries), Cabin (dash, wheel, seats, bench, console; hidden on distant cars), Wheel (alloy and
tyre, one wheel at the origin, outer face towards +X).
"""
import bpy
import math
import os
import sys
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import carkit
import kit
from carkit import MB, Curve, Projector, add_damage_keys, cr, ellipse, lamp_bulb, profile, rounded_rect, smoothstep, spread
from carkit import text_decal, text_polys, _nz
from kit import arg, lerp

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_GLB = os.path.join(ROOT, "godot", "models", "golf4.glb")

# ---------------------------------------------------------------- real-car numbers
LENGTH = 4.149
WHEELBASE = 2.511
FRONT_AXLE_S = 0.855
REAR_AXLE_S = FRONT_AXLE_S + WHEELBASE
Y0 = FRONT_AXLE_S + WHEELBASE / 2.0
TRACK_F = 1.513
TRACK_R = 1.494
TYRE_R = 0.3172  # 195/65 R15: 381 mm rim + 2 x 126.75 mm sidewall = 634.5 mm
TYRE_W = 0.195
ARCH_R = 0.385

S_COWL, S_WS_TOP = 1.20, 2.00
S_SCUTTLE = 1.12
S_SAIL = 1.56
S_B0, S_B1 = 2.105, 2.205
S_QR = 2.68  # the rear door glass's top edge starts to fall away here, to its rear corner at S_Q1
S_Q1 = 3.06
S_RG0, S_RG1 = 3.50, 3.985
S_DOOR = (1.27, 2.155, 3.02)
FRIT = 0.015
PILLAR = 0.07


def bl(x, s, z):
	return Vector((x, Y0 - s, z))


# ---------------------------------------------------------------- body profile curves (metres)
# Plan, elevation and section lines for the Typ 1J: a tall rounded nose, a high shoulder, a long raked windscreen,
# a flat roof, the broad C-pillar that tapers the side glass to a wedge, and a steep hatch glass over a short, upright tail.
W = Curve([(0.0, 0.60), (0.03, 0.665), (0.08, 0.725), (0.15, 0.775), (0.30, 0.825), (0.55, 0.857), (0.85, 0.868),
	(1.3, 0.8675), (2.2, 0.8675), (3.1, 0.866), (3.6, 0.858), (3.85, 0.840), (4.0, 0.805), (4.08, 0.76),
	(4.12, 0.71), (LENGTH, 0.62)])
ZM = Curve([(0.0, 0.46), (0.3, 0.50), (1.0, 0.52), (3.5, 0.53), (LENGTH, 0.50)])
WSH = Curve([(0.0, 0.57), (0.05, 0.645), (0.12, 0.70), (0.25, 0.74), (0.5, 0.78), (0.85, 0.80), (1.2, 0.806),
	(1.6, 0.808), (2.2, 0.808), (3.0, 0.803), (3.5, 0.795), (3.9, 0.775), (4.0, 0.755), (4.06, 0.725),
	(4.1, 0.69), (LENGTH, 0.60)])
ZSH = Curve([(0.0, 0.54), (0.04, 0.64), (0.08, 0.72), (0.14, 0.762), (0.3, 0.792), (0.6, 0.826), (0.9, 0.868),
	(1.1, 0.905), (S_COWL, 0.935), (1.35, 0.96), (1.7, 0.985), (2.2, 0.99), (3.0, 1.0), (3.5, 1.0), (3.85, 0.99),
	(3.985, 0.97), (4.04, 0.935), (4.08, 0.88), (4.11, 0.79), (4.13, 0.70), (LENGTH, 0.64)])
ZT = Curve([(0.0, 0.58), (0.03, 0.685), (0.06, 0.748), (0.10, 0.775), (0.3, 0.805), (0.6, 0.845), (0.9, 0.895),
	(1.1, 0.940), (S_COWL, 0.968), (1.4, 1.075), (1.6, 1.185), (1.8, 1.295), (S_WS_TOP, 1.392), (2.12, 1.418),
	(2.3, 1.431), (2.5, 1.4375), (2.8, 1.4375), (3.1, 1.432), (3.3, 1.418), (S_RG0, 1.392), (3.60, 1.352), (3.70, 1.285),
	(3.80, 1.205), (3.90, 1.10), (S_RG1, 1.015), (4.03, 0.955), (4.07, 0.89), (4.10, 0.80), (4.125, 0.71), (4.14, 0.66),
	(LENGTH, 0.64)])
ZB = Curve([(0.0, 0.285), (0.06, 0.235), (0.25, 0.215), (0.5, 0.21), (1.0, 0.21), (2.5, 0.205), (3.5, 0.215),
	(4.0, 0.25), (LENGTH, 0.30)])
WR = Curve([(0.0, 0.50), (0.05, 0.57), (0.12, 0.63), (0.3, 0.69), (0.7, 0.725), (S_COWL, 0.735), (1.5, 0.695),
	(S_WS_TOP, 0.645), (2.4, 0.632), (3.0, 0.625), (S_RG0, 0.612), (3.75, 0.64), (S_RG1, 0.70),
	(4.08, 0.69), (4.12, 0.66), (LENGTH, 0.56)])
DR = Curve([(0.0, 0.015), (0.2, 0.04), (S_COWL, 0.05), (S_WS_TOP, 0.05), (3.6, 0.05), (S_RG1, 0.04), (LENGTH, 0.015)])

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
	return smoothstep(S_COWL - 0.1, S_COWL + 0.05, s) * (1.0 - smoothstep(S_RG1 - 0.03, S_RG1 + 0.07, s))


def keys(s):
	w = W(s)
	zb = zbottom(s)
	zsh = ZSH(s)
	A = Vector((0.0, zb))
	B = Vector((w - 0.10, zb))
	C = Vector((w - 0.032, zb + 0.055))
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
		gz = F.y + max(0.004, (gz - F.y) * (1.0 - k) ** 0.8)
	G = F + (H - F) * ((gz - F.y) / (H.y - F.y))
	return [A, B, C, D, E, F, G, H, I]


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
	out = [0.0]
	prev = None
	acc = 0.0
	for i in range(n + 1):
		s = LENGTH * i / n
		pts = [Vector((p.x, s, p.y)) for p in keys(s)[1:]]
		if prev is not None:
			acc += max((a - b).length for a, b in zip(pts, prev))
			if acc >= step:
				out.append(s)
				acc = 0.0
		prev = pts
	forced = [0.0, LENGTH, S_SCUTTLE, S_COWL, S_COWL + FRIT, S_WS_TOP - FRIT, S_WS_TOP, S_SAIL, S_B0, S_B1, S_QR,
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
	"Indicator": ((1.0, 0.42, 0.04), 0.1, 0.0, {"emit": ((1.0, 0.35, 0.02), 0.7)}),
	"Taillight": ((0.42, 0.01, 0.015), 0.08, 0.0, {"emit": ((1.0, 0.05, 0.03), 0.15)}),
	"LampClear": ((0.85, 0.80, 0.80), 0.08, 0.0, {}),
	"Plate": ((0.94, 0.93, 0.89), 0.45, 0.0, {}),
	"Seat": ((0.03, 0.03, 0.035), 0.9, 0.0, {}),
	"Fabric": ((0.10, 0.10, 0.105), 0.95, 0.0, {}),
	"Tyre": ((0.03, 0.03, 0.03), 0.8, 0.0, {}),
	"Sidewall": ((0.085, 0.085, 0.085), 0.7, 0.0, {}),
	"Rim": ((0.74, 0.75, 0.78), 0.2, 0.92, {}),
	"Steel": ((0.36, 0.37, 0.38), 0.42, 0.5, {}),
	"BrakeDisc": ((0.20, 0.19, 0.19), 0.5, 0.7, {}),
	"BadgeBlue": ((0.03, 0.12, 0.35), 0.25, 0.2, {}),
	"Stripe": ((1.0, 1.0, 1.0), 0.4, 0.0, {}),
	"TailBulb": ((0.9, 0.25, 0.08), 0.2, 0.0, {"emit": ((1.0, 0.2, 0.05), 0.4)}),
	"TailGlass": ((0.55, 0.015, 0.02), 0.03, 0.0, {"alpha": 0.5}),
	"LampGlass": ((0.86, 0.92, 1.0), 0.02, 0.0, {"alpha": 0.08}),
	"MartiniDark": ((0.015, 0.05, 0.24), 0.3, 0.0, {"coat": 1.0}),
	"MartiniLight": ((0.05, 0.36, 0.78), 0.3, 0.0, {"coat": 1.0}),
	"MartiniRed": ((0.72, 0.03, 0.05), 0.3, 0.0, {"coat": 1.0}),
	"MartiniWhite": ((0.95, 0.95, 0.93), 0.3, 0.0, {"coat": 1.0}),
	"MartiniGold": ((0.78, 0.58, 0.16), 0.3, 0.3, {"coat": 1.0}),
	"AbarthBlack": ((0.02, 0.02, 0.022), 0.35, 0.0, {"coat": 1.0}),
	"AbarthRed": ((0.75, 0.03, 0.04), 0.3, 0.0, {"coat": 1.0}),
	"AbarthYellow": ((0.95, 0.72, 0.04), 0.3, 0.0, {"coat": 1.0}),
	"AbarthWhite": ((0.94, 0.94, 0.92), 0.3, 0.0, {"coat": 1.0}),
	"MarlboroRed": ((0.80, 0.02, 0.03), 0.3, 0.0, {"coat": 1.0}),
	"MarlboroWhite": ((0.96, 0.96, 0.95), 0.3, 0.0, {"coat": 1.0}),
}
carkit.MATERIALS.update(MATERIALS)


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
			# crisp panel shut lines
			if groove and SEG_ROWS[0] + 1 <= j <= sum(SEG_ROWS[:SEG_EF]):
				x -= 0.0025
				col = 0.08
			if s < S_COWL - 0.015 and j == sum(SEG_ROWS[:SEG_FG]):
				col = 0.15
			if s > S_RG1 + 0.02 and j == sum(SEG_ROWS[:SEG_FG]):
				col = 0.15
			right.append((x, z, col))
		ring = [mb.vert(bl(x, s, z), c) for x, z, c in right]
		ring += [mb.vert(bl(-right[j][0], s, right[j][1]), right[j][2]) for j in range(R - 1, 0, -1)]
		rings.append(ring)
		ring_s.append(s)
	M = 2 * R

	def band_of(k):
		return k if k < R else 2 * R - k - 1

	for i in range(len(rings) - 1):
		smid = (ring_s[i] + ring_s[i + 1]) / 2
		for k in range(M):
			seg, sub = seg_bands[band_of(k)]
			mat = band_material(seg, sub, smid)
			a, b = rings[i], rings[i + 1]
			mb.face([a[k], a[(k + 1) % M], b[(k + 1) % M], b[k]], mat)

	for ring, sign in ((rings[0], 1), (rings[-1], -1)):
		for j in range(R):
			j_next = j + 1
			ref = Vector((0, sign, 0))
			if j == 0:
				mb.face([ring[0], ring[1], ring[M - 1]] if sign > 0 else [ring[0], ring[M - 1], ring[1]], "Under", ref)
			elif j == R - 1:
				mb.face([ring[R - 1], ring[R], ring[R + 1]] if sign > 0 else [ring[R - 1], ring[R + 1], ring[R]], "Paint", ref)
			else:
				seg = seg_bands[j][0]
				mat = "Paint" if seg in (SEG_CD, SEG_DE, SEG_EF, SEG_FG, SEG_GH, SEG_HI) else "Under"
				quad = [ring[j], ring[j_next], ring[M - j_next], ring[M - j]]
				mb.face(quad if sign > 0 else list(reversed(quad)), mat, ref)

	# rolled wheel-arch lips: a narrow raised rim (the arches are plain cut-outs with a rolled edge)
	for v in mb.v:
		ax = abs(v.x)
		if ax < 0.45 or v.z < 0.18:
			continue
		s = Y0 - v.y
		for sc in (FRONT_AXLE_S, REAR_AXLE_S):
			d = math.hypot(s - sc, v.z - TYRE_R)
			if d < ARCH_R + 0.03:
				v.x += math.copysign(0.007 * (1.0 - smoothstep(ARCH_R + 0.012, ARCH_R + 0.03, d))
					* (1.0 - smoothstep(0.88, 0.98, v.z)), v.x)
	# door mirrors, body-coloured (the Paint surface is re-coloured per car), glass facing back
	for side in (1, -1):
		mb.box(bl(side * 0.835, 1.60, 0.985), (0.06, 0.10, 0.045), "Paint")
		mb.blob(bl(side * 0.900, 1.64, 1.03), (0.070, 0.05, 0.060), "Paint", e=0.5)
		mb.blob(bl(side * 0.900, 1.685, 1.03), (0.062, 0.006, 0.048), "Chrome", e=0.35)
	return mb


def build_liner(body):
	import bmesh
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


# ---------------------------------------------------------------- projections
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


# ---------------------------------------------------------------- lamps, grille, bumper plastics
FB_AXIS = 1.0  # the nose's cylinder axis (station)
RB_AXIS = 3.15

# the one-piece headlamp (x across the car, z height, seen from the front): a swept shape, shallow at the grille and tall
# at the wing, the amber indicator at its outer end. The tail-lamp cluster likewise, seen from behind.
HEADLAMP = [(0.27, 0.615), (0.27, 0.69), (0.36, 0.705), (0.48, 0.72), (0.60, 0.733), (0.69, 0.738), (0.75, 0.728),
	(0.77, 0.70), (0.74, 0.662), (0.67, 0.630), (0.55, 0.610), (0.40, 0.600)]
HEAD_AMBER = [(0.64, 0.732), (0.72, 0.733), (0.755, 0.722), (0.765, 0.70), (0.74, 0.666), (0.67, 0.640), (0.62, 0.64)]
TAILLAMP = [(0.40, 0.70), (0.40, 0.89), (0.50, 0.905), (0.62, 0.905), (0.70, 0.895), (0.735, 0.86), (0.74, 0.79),
	(0.725, 0.735), (0.66, 0.705), (0.52, 0.70)]


def build_plastics(pj, mb):
	"""Black plastics on the body-coloured bumpers: the lower intake with its fog lamps, the chin spoiler and the
	grille; shut lines where bumper meets wing and tailgate."""
	fp = cyl_proj(FB_AXIS, False)
	# front chin spoiler and lower intake band
	rows = [(0.215, -0.004), (0.222, 0.010), (0.240, 0.018), (0.325, 0.018), (0.334, 0.008), (0.338, -0.002)]
	us = spread(-62.0, 62.0, 2.0, (-52, -44, 44, 52))
	pj.band(mb, us, [r[0] for r in rows], lambda u, v: profile(v, rows) * (1.0 - smoothstep(55.0, 62.0, abs(u))),
		lambda u, v: "Bumper", fp, caps=True)
	rows = [(0.338, -0.002), (0.345, 0.011), (0.372, 0.014), (0.446, 0.014), (0.452, 0.006), (0.456, -0.002)]
	pj.band(mb, spread(-46.0, 46.0, 2.0), [r[0] for r in rows],
		lambda u, v: profile(v, rows) * (1.0 - smoothstep(40.0, 46.0, abs(u))),
		lambda u, v: "Grille" if abs(u) < 40.0 else "Bumper", fp, caps=True)
	# intake bars
	for z in (0.375, 0.402, 0.429):
		pj.strip(mb, -0.34, 0.34, z, z + 0.007, 24, 1, front_proj, "Bumper", offset=0.020)
	# fog lamps in round recesses at the ends of the intake
	for side in (1, -1):
		cx = side * 0.52
		pj.star(mb, ellipse(cx, 0.395, 0.064, 0.064, 18), front_proj, "Trim", offset=0.018, rings=1, samples=1, skirt=0.01)
		pj.star(mb, ellipse(cx, 0.395, 0.052, 0.052, 18), front_proj, "Headlight", offset=0.022, bulge=0.004, rings=2,
			samples=1, skirt=0.0)
		pj.star(mb, ellipse(cx, 0.395, 0.056, 0.056, 18), front_proj, "LampGlass", offset=0.030, bulge=0.004, rings=2,
			samples=1, skirt=0.0)
	# the main grille in the nose, a black mesh in a chrome-edged opening, with the roundel above it
	pj.star(mb, rounded_rect(-0.255, 0.255, 0.600, 0.672, 0.012), front_proj, "Chrome", offset=0.0045, rings=1, samples=2,
		skirt=0.004)
	pj.star(mb, rounded_rect(-0.243, 0.243, 0.610, 0.662, 0.008), front_proj, "Grille", offset=0.0085, rings=1, samples=2,
		skirt=0.0)
	for z in (0.623, 0.636, 0.649):
		pj.strip(mb, -0.243, 0.243, z, z + 0.004, 1, 1, front_proj, "Chrome", offset=0.0105)
	pj.star(mb, ellipse(0.0, 0.700, 0.046, 0.046, 24), front_proj, "Chrome", offset=0.004, rings=2, samples=1, skirt=0.003)
	pj.star(mb, ellipse(0.0, 0.700, 0.040, 0.040, 24), front_proj, "BadgeBlue", offset=0.0058, rings=2, samples=1, skirt=0.0)
	# front number plate on the lower bumper (centre, between the intake bars), a European plate 520 x 114 mm
	pj.star(mb, rounded_rect(-0.262, 0.262, 0.272, 0.330, 0.006), front_proj, "Trim", offset=0.0135, rings=1, samples=2, skirt=0.01)
	pj.star(mb, rounded_rect(-0.256, 0.256, 0.275, 0.327, 0.004), front_proj, "Plate", offset=0.0165, rings=1, samples=2, skirt=0.0)
	# shut line where the bumper meets the wings and bonnet
	pj.band(mb, spread(-70.0, 70.0, 2.0), [0.575, 0.581], lambda u, v: 0.0014 * (1.0 - smoothstep(66.0, 70.0, abs(u))),
		lambda u, v: "Gasket", fp)
	# rear: the bumper's lower black apron with the plate in its recess, and a lamp-to-bumper shut line
	rp = cyl_proj(RB_AXIS, True)
	rows = [(0.262, -0.004), (0.272, 0.010), (0.292, 0.018), (0.398, 0.018), (0.408, 0.008), (0.414, -0.002)]
	pj.band(mb, spread(-52.0, 52.0, 2.0), [r[0] for r in rows],
		lambda u, v: profile(v, rows) * (1.0 - smoothstep(46.0, 52.0, abs(u))), lambda u, v: "Bumper", rp, caps=True)
	pj.star(mb, rounded_rect(-0.262, 0.262, 0.420, 0.480, 0.006), rear_proj, "Trim", offset=0.013, rings=1, samples=2, skirt=0.01)
	pj.star(mb, rounded_rect(-0.256, 0.256, 0.423, 0.477, 0.004), rear_proj, "Plate", offset=0.0165, rings=1, samples=2, skirt=0.0)
	pj.band(mb, spread(-70.0, 70.0, 2.0), [0.600, 0.606], lambda u, v: 0.0014 * (1.0 - smoothstep(66.0, 70.0, abs(u))),
		lambda u, v: "Gasket", rp)


def build_details(body):
	mb = MB()
	pj_body = Projector(body)
	build_plastics(pj_body, mb)
	both = MB()
	both.extend(body)
	both.extend(mb)
	pj_all = Projector(both)
	pj = pj_body

	for side in (1, -1):
		# headlamp: gasket frame, reflector bowl, amber indicator, main-beam reflectors, clear lens
		hp = lambda u, v, side=side: front_proj(side * u, v)
		pj.star(mb, HEADLAMP, hp, "Gasket", offset=0.003, rings=2, samples=3, skirt=0.0)
		cu = sum(p[0] for p in HEADLAMP) / len(HEADLAMP)
		cv = sum(p[1] for p in HEADLAMP) / len(HEADLAMP)
		pj.star(mb, [(lerp(u, cu, 0.05), lerp(v, cv, 0.12)) for u, v in HEADLAMP], hp, "Headlight", offset=0.006, bulge=0.006,
			rings=3, samples=3, skirt=0.0)
		pj.star(mb, [(lerp(u, 0.70, 0.1), lerp(v, 0.69, 0.12)) for u, v in HEAD_AMBER], hp, "Indicator", offset=0.0105,
			rings=2, samples=3, skirt=0.0)
		lamp_bulb(mb, pj, hp, 0.42, 0.660, 0.034, "LampClear")
		lamp_bulb(mb, pj, hp, 0.56, 0.672, 0.028, "LampClear")
		pj.star(mb, [(lerp(u, cu, 0.03), lerp(v, cv, 0.06)) for u, v in HEADLAMP], hp, "LampGlass", offset=0.0135, bulge=0.009,
			rings=3, samples=3, skirt=0.0)

		# tail-lamp cluster
		tp = lambda u, v, side=side: rear_proj(side * u, v)
		pj.star(mb, TAILLAMP, tp, "Gasket", offset=0.003, rings=2, samples=3, skirt=0.0)
		tu = sum(p[0] for p in TAILLAMP) / len(TAILLAMP)
		tv = sum(p[1] for p in TAILLAMP) / len(TAILLAMP)
		pj.star(mb, [(lerp(u, tu, 0.05), lerp(v, tv, 0.08)) for u, v in TAILLAMP], tp, "Taillight", offset=0.006, bulge=0.005,
			rings=3, samples=3, skirt=0.0)
		for cu2, cv2, r in ((0.49, 0.79, 0.034), (0.63, 0.79, 0.034), (0.56, 0.865, 0.024)):
			lamp_bulb(mb, pj, tp, cu2, cv2, r, "TailBulb")
		pj.star(mb, [(lerp(u, tu, 0.03), lerp(v, tv, 0.05)) for u, v in TAILLAMP], tp, "TailGlass", offset=0.0135, bulge=0.009,
			rings=3, samples=3, skirt=0.0)

		pj = pj_all
		sp = side_proj(side)
		# front wing side repeater, behind the arch
		pj.star(mb, ellipse(1.34, 0.80, 0.024, 0.011, 12), sp, "Gasket", offset=0.002, rings=1, samples=2)
		pj.star(mb, ellipse(1.34, 0.80, 0.019, 0.008, 12), sp, "Indicator", offset=0.004, bulge=0.002, rings=2, samples=2)

		# side protection strip: a black rubbing strip along the doors
		s0, s1 = 1.34, 2.96
		strip_rows = [(0.505, 0.0), (0.509, 0.006), (0.517, 0.011), (0.531, 0.012), (0.541, 0.008), (0.546, 0.0)]

		def rub(u, v, s0=s0, s1=s1):
			return profile(v, strip_rows) * smoothstep(s0, s0 + 0.03, u) * (1.0 - smoothstep(s1 - 0.03, s1, u))
		pj.band(mb, spread(s0, s1, 0.04, S_DOOR[:2]), [r[0] for r in strip_rows], rub, lambda u, v: "Trim", sp)

		# sill trim
		pj.band(mb, spread(1.30, 2.94, 0.05, S_DOOR[:2]), [0.235, 0.255, 0.275], lambda u, v: 0.004 if 0.25 < v < 0.27 else 0.0,
			lambda u, v: "Bumper", sp)

		# door handles (body colour is in the Body mesh), their lock barrels, and the black door-frame seals
		for hs, hl in ((1.82, 0.935), (2.73, 0.945)):
			pj.star(mb, rounded_rect(hs - 0.07, hs + 0.07, hl - 0.016, hl + 0.016, 0.01), sp, "Trim", offset=0.0025, rings=2,
				samples=2)
		pj.star(mb, ellipse(1.82 + 0.105, 0.935, 0.009, 0.009, 10), sp, "Chrome", offset=0.004, rings=1, samples=1)

		# wheel-well liners (black arcs sealing the shell)
		for sc, tr in ((FRONT_AXLE_S, TRACK_F), (REAR_AXLE_S, TRACK_R)):
			rows = []
			for xo in (0.50, 0.745):
				row = []
				for k in range(21):
					a = math.radians(-12 + 204 * k / 20)
					row.append(bl(side * xo, sc - (ARCH_R - 0.006) * math.cos(a), TYRE_R + (ARCH_R - 0.006) * math.sin(a)))
				rows.append(row)
			mb.grid(rows, "Under", out=lambda q, sc=sc: Vector((0, (Y0 - sc) - q.y, TYRE_R - q.z)))

	# fuel flap on the right rear quarter
	spr = side_proj(1)
	pj.star(mb, ellipse(3.35, 0.90, 0.062, 0.062, 20), spr, "Gasket", offset=0.0012, rings=1, samples=2, skirt=0.002)
	pj.star(mb, ellipse(3.35, 0.90, 0.058, 0.058, 20), spr, "Gasket", offset=-0.004, rings=1, samples=2, skirt=0.0)

	# tailgate: the opening handle above the plate with its badge, shut lines beside the lamps, a wiper and the aerial
	pj.star(mb, rounded_rect(-0.085, 0.085, 0.535, 0.580, 0.012), rear_proj, "Trim", offset=0.004, rings=1, samples=2, skirt=0.003)
	pj.star(mb, ellipse(0.0, 0.557, 0.026, 0.026, 18), rear_proj, "Chrome", offset=0.006, rings=1, samples=1, skirt=0.002)
	pj.star(mb, ellipse(0.0, 0.557, 0.021, 0.021, 18), rear_proj, "BadgeBlue", offset=0.0075, rings=1, samples=1, skirt=0.0)
	for x in (-0.385, 0.385):
		pj.strip(mb, x + 0.003, x - 0.003, 0.70, 1.0, 1, 10, rear_proj, "Trim", offset=0.0015)
	pj.star(mb, rounded_rect(0.20, 0.34, 0.60, 0.620, 0.006), rear_proj, "Chrome", offset=0.003, rings=1, samples=2)
	pj.star(mb, rounded_rect(-0.34, -0.20, 0.60, 0.620, 0.006), rear_proj, "Chrome", offset=0.003, rings=1, samples=2)
	# the third brake light under the roof spoiler lip, seen through the top of the hatch glass
	pj.star(mb, rounded_rect(-0.17, 0.17, 1.30, 1.328, 0.006), rear_proj, "Taillight", offset=-0.045, rings=1, samples=2)
	# rear wiper, parked along the bottom of the glass
	p0 = pj.hit(*rear_proj(0.0, 1.13))[0]
	p1 = pj.hit(*rear_proj(-0.40, 1.15))[0]
	mb.blob(p0 + Vector((0, -0.012, 0)), (0.02, 0.016, 0.02), "Trim", e=0.3)
	mb.tube(p0 + Vector((0, -0.016, 0)), p1 + Vector((0, -0.014, 0)), 0.006, "Trim", segs=6)

	# scuttle washer jets and wipers parked along the base of the windscreen
	for x in (-0.30, 0.30):
		pj.star(mb, ellipse(S_SCUTTLE + 0.02, x, 0.012, 0.008, 8), top_proj, "Trim", offset=0.004, rings=1, samples=1)
	for xp, x1 in ((-0.50, 0.00), (0.06, 0.58)):
		base_p = pj.hit(*top_proj(S_SCUTTLE + 0.06, xp))[0]
		mb.blob(base_p + Vector((0, 0, 0.010)), (0.018, 0.018, 0.014), "Trim", e=0.3)
		a = base_p + Vector((0, 0, 0.018))
		b = pj.hit(*top_proj(S_SCUTTLE + 0.22, x1))[0] + Vector((0, 0, 0.016))
		mb.tube(a, b, 0.006, "Trim", segs=6)
		bx0 = pj.hit(*top_proj(S_SCUTTLE + 0.20, xp + 0.05))[0] + Vector((0, 0, 0.012))
		bx1 = pj.hit(*top_proj(S_SCUTTLE + 0.25, x1 + 0.02))[0] + Vector((0, 0, 0.012))
		mb.box((bx0 + bx1) / 2, ((bx1 - bx0).length, 0.012, 0.012), "Trim",
			basis=Matrix.Rotation(math.atan2(bx1.y - bx0.y, bx1.x - bx0.x), 3, "Z"))

	# a short roof aerial at the rear of the roof
	base = pj.hit(*top_proj(3.45, 0.0))[0]
	mb.blob(base + Vector((0, 0, 0.012)), (0.024, 0.04, 0.016), "Trim", e=0.4)
	mb.tube(base + Vector((0, 0, 0.02)), base + Vector((0, 0.04, 0.115)), 0.006, "Trim", segs=6)

	# exhaust: a single oval tailpipe under the right of the rear bumper
	mb.tube(bl(0.22, 3.15, 0.25), bl(-0.20, 3.15, 0.25), 0.075, "Steel", segs=14)
	mb.tube(bl(0.35, 3.25, 0.235), bl(0.35, LENGTH + 0.01, 0.24), 0.024, "Exhaust", segs=14, caps=False)
	mb.tube(bl(0.35, LENGTH + 0.01, 0.24), bl(0.35, LENGTH + 0.055, 0.24), 0.031, "Chrome", segs=16, caps=False)
	mb.ring(bl(0.35, LENGTH + 0.055, 0.24), 0.025, 0.033, "Chrome", normal=(0, -1, 0), segs=16)
	mb.disc(bl(0.35, LENGTH + 0.045, 0.24), 0.026, "Under", normal=(0, -1, 0), segs=16)

	# underbody: sump guard, engine bay and tail closed off, flat floor
	mb.box(bl(0, 0.85, 0.215), (0.80, 0.8, 0.03), "Steel")
	mb.box(bl(0, 0.80, 0.42), (1.1, 1.0, 0.44), "Under")
	mb.box(bl(0, 3.55, 0.40), (1.1, 1.0, 0.44), "Under")
	mb.box(bl(0, 2.15, 0.215), (0.95, 2.1, 0.07), "Under")

	return mb, pj


def build_cabin():
	"""The cabin silhouette: facia with instrument hood and centre stack, a three-spoke wheel, two front seats, the rear
	bench, the gear lever and the rear-view mirror. Godot drops it on distant cars; it is seen through the glass."""
	mb = MB()
	mb.blob(bl(0, 1.62, 0.90), (0.66, 0.20, 0.09), "Interior", e=0.3)
	mb.box(bl(0, 1.53, 0.64), (1.40, 0.14, 0.44), "Interior")
	mb.box(bl(0, 1.75, 0.66), (0.26, 0.30, 0.40), "Interior")  # centre stack and console
	mb.box(bl(0, 2.08, 0.40), (0.24, 0.78, 0.18), "Interior")  # tunnel console between the seats
	mb.blob(bl(-0.37, 1.68, 1.02), (0.17, 0.10, 0.06), "Interior", e=0.35)  # instrument hood
	mb.disc(bl(-0.37, 1.66, 1.00), 0.055, "Plate", normal=(0, -0.6, 0.8), segs=16)
	for sx in (-0.07, 0.07):
		mb.disc(bl(sx, 1.72, 0.90), 0.026, "Trim", normal=(0, -0.4, 0.9), segs=12)
		mb.ring(bl(sx, 1.72, 0.90), 0.023, 0.028, "Chrome", normal=(0, -0.4, 0.9), segs=12)
	# gear lever and gaiter, handbrake
	mb.blob(bl(0, 1.98, 0.50), (0.06, 0.07, 0.04), "Trim", e=0.3)
	mb.tube(bl(0, 1.98, 0.52), bl(0, 2.00, 0.72), 0.009, "Chrome", segs=8)
	mb.blob(bl(0, 2.00, 0.73), (0.022, 0.022, 0.026), "Seat", e=0.35)
	mb.tube(bl(0.07, 2.30, 0.50), bl(0.07, 2.38, 0.58), 0.010, "Interior", segs=6)
	# pedals
	for px in (-0.46, -0.38, -0.30):
		mb.box(bl(px, 1.58, 0.30), (0.05, 0.012, 0.075), "Steel")
	# the rear-view mirror
	mb.box(bl(0, 1.92, 1.36), (0.13, 0.015, 0.045), "Interior")
	mb.tube(bl(0, 1.93, 1.37), bl(0, 1.95, 1.40), 0.006, "Trim", segs=6)
	# the three-spoke wheel, in front of the driver (left-hand drive: the driver sits on the left as seen from behind)
	tilt = math.radians(66)
	n = Vector((0, -math.cos(tilt), math.sin(tilt)))
	u = Vector((1, 0, 0))
	v = n.cross(u)
	sw = bl(-0.37, 1.90, 0.99)
	ring = [sw + (u * math.cos(2 * math.pi * k / 24) + v * math.sin(2 * math.pi * k / 24)) * 0.19 for k in range(24)]
	for k in range(24):
		mb.tube(ring[k], ring[(k + 1) % 24], 0.0145, "Seat", segs=8, caps=False)
	mb.tube(sw, sw - v * 0.18, 0.012, "Trim", segs=6)
	mb.tube(sw, sw - u * 0.16 + v * 0.04, 0.012, "Trim", segs=6)
	mb.tube(sw, sw + u * 0.16 + v * 0.04, 0.012, "Trim", segs=6)
	mb.disc(sw, 0.045, "Interior", normal=n, segs=14)
	mb.disc(sw + n * 0.003, 0.026, "Chrome", normal=n, segs=12)
	mb.tube(sw, sw + Vector((0, 0.28, -0.10)), 0.022, "Trim", segs=8)
	# front seats: cushion, backrest and headrest with side bolsters, on rails
	lean = Matrix.Rotation(math.radians(-12), 3, "X")
	for sx in (-0.37, 0.37):
		mb.blob(bl(sx, 2.35, 0.43), (0.23, 0.26, 0.085), "Fabric", e=0.40)
		mb.blob(bl(sx, 2.58, 0.80), (0.24, 0.08, 0.37), "Fabric", e=0.45, basis=lean)
		for bx in (-1, 1):
			mb.blob(bl(sx + bx * 0.20, 2.35, 0.48), (0.045, 0.24, 0.09), "Fabric", e=0.4)
			mb.blob(bl(sx + bx * 0.21, 2.55, 0.80), (0.045, 0.08, 0.27), "Fabric", e=0.4, basis=lean)
		mb.blob(bl(sx, 2.64, 1.18), (0.11, 0.05, 0.10), "Fabric", e=0.4, basis=lean)
		for rx in (-0.2, 0.2):
			mb.box(bl(sx + rx, 2.35, 0.26), (0.025, 0.45, 0.035), "Steel")
	# the rear bench: cushion, back and three headrests
	mb.blob(bl(0, 3.0, 0.43), (0.62, 0.22, 0.08), "Fabric", e=0.35)
	mb.blob(bl(0, 3.23, 0.82), (0.64, 0.07, 0.34), "Fabric", e=0.40)
	for hx in (-0.38, 0.0, 0.38):
		mb.blob(bl(hx, 3.25, 1.19), (0.10, 0.04, 0.08), "Fabric", e=0.4)
	return mb


def build_stripes(pj):
	mb = MB()
	for x in (-0.16, 0.16):
		pj.strip(mb, 0.17, S_SCUTTLE - 0.01, x - 0.07, x + 0.07, 40, 2, top_proj, "Stripe", offset=0.0018)
		pj.strip(mb, S_WS_TOP + 0.02, S_RG0 - 0.012, x - 0.07, x + 0.07, 40, 2, top_proj, "Stripe", offset=0.0018)
	return mb


MARTINI_STRIPES = ((-0.20, -0.15, "MartiniDark"), (-0.15, -0.10, "MartiniLight"), (-0.10, 0.10, "MartiniRed"),
	(0.10, 0.15, "MartiniLight"), (0.15, 0.20, "MartiniDark"))


def martini_roundel(pj, mb, proj, cu, cv, scale, flip):
	def at(x, y):
		return (cu + flip * x * scale, cv + y * scale)

	def plate(pts, mat, off):
		pj.star(mb, [at(x, y) for x, y in pts], proj, mat, offset=off, rings=2, samples=2, skirt=0.0)
	plate(ellipse(0.0, 0.0, 0.58, 0.58, 28), "MartiniGold", 0.0030)
	plate(ellipse(0.0, 0.0, 0.54, 0.54, 28), "MartiniRed", 0.0036)
	plate([(-1.2, -0.30), (1.2, -0.30), (1.2, 0.32), (-1.2, 0.32)], "MartiniGold", 0.0042)
	plate([(-1.16, -0.26), (1.16, -0.26), (1.16, 0.28), (-1.16, 0.28)], "MartiniDark", 0.0048)
	for poly in text_polys("MARTINI", 2.0):
		pts = [at(x, y + 0.01) for x, y in poly]
		locs = [pj.hit(*proj(*p)) for p in pts]
		ref = sum((n for _, n in locs), Vector())
		mb.poly([l + n * 0.0056 for l, n in locs], "MartiniWhite", ref)


def build_martini(pj):
	mb = MB()
	for x0, x1, mat in MARTINI_STRIPES:
		pj.strip(mb, 0.17, S_SCUTTLE - 0.01, x0, x1, 40, 1, top_proj, mat, offset=0.0035)
		pj.strip(mb, S_WS_TOP + 0.02, S_RG0 - 0.012, x0, x1, 40, 1, top_proj, mat, offset=0.0035)

	def belt(u):
		return 0.74 - 0.04 * smoothstep(1.3, 3.1, u)
	us = [lerp(1.30, 3.00, i / 90) for i in range(91)]
	vs = [-0.075, -0.05, -0.025, 0.045]
	for side in (1, -1):
		sp = side_proj(side)
		pj.band(mb, us, vs, lambda u, v: 0.0045, lambda u, v: "MartiniDark" if v < -0.04 else "MartiniLight" if v < -0.01 else "MartiniRed",
			lambda u, v, sp=sp: sp(u, v + belt(u)))
		martini_roundel(pj, mb, sp, 1.72, 0.56, 0.12, -side)
	martini_roundel(pj, mb, top_proj, 0.80, 0.0, 0.1, 1)
	return mb


def build_abarth(pj):
	mb = MB()
	for side in (1, -1):
		sp = side_proj(side)
		pj.strip(mb, 1.34, 2.96, 0.38, 0.47, 40, 2, sp, "AbarthBlack", offset=0.0035)
		pj.strip(mb, 1.34, 2.96, 0.477, 0.489, 40, 1, sp, "AbarthRed", offset=0.0035)
		text_decal(pj, mb, sp, "ABARTH", 2.15, 0.425, 0.62, "AbarthWhite", 0.0050, -side)

	def plate(pts, mat, off, k=0.15, cu=0.52):
		pj.star(mb, [(cu + x * k, y * k) for x, y in pts], top_proj, mat, offset=off, rings=2, samples=2, skirt=0.0)
	plate([(-0.66, 0.0), (-0.12, 0.56), (0.60, 0.56), (0.60, -0.56), (-0.12, -0.56)], "AbarthWhite", 0.0030)
	plate([(-0.58, 0.0), (-0.10, 0.49), (0.53, 0.49), (0.53, -0.49), (-0.10, -0.49)], "AbarthRed", 0.0036)
	plate([(0.22, 0.49), (0.53, 0.49), (0.53, -0.49), (0.22, -0.49)], "AbarthYellow", 0.0042)
	text_decal(pj, mb, top_proj, "ABARTH", 0.52 + 0.375 * 0.15, 0.0, 0.11, "AbarthBlack", 0.0048, 1)
	return mb


def build_marlboro(pj):
	mb = MB()
	pj.star(mb, [(0.26, -0.50), (0.26, 0.50), (1.02, 0.50), (0.62, 0.0), (1.02, -0.50)], top_proj, "MarlboroRed",
		offset=0.005, rings=8, samples=14, skirt=0.0)
	for side in (1, -1):
		sp = side_proj(side)
		pj.star(mb, [(1.40, 0.62), (1.40, 0.88), (2.80, 0.88), (2.40, 0.75), (2.80, 0.62)], sp, "MarlboroRed",
			offset=0.005, rings=8, samples=14, skirt=0.0)
		text_decal(pj, mb, sp, "Marlboro", 1.80, 0.75, 0.56, "MarlboroWhite", 0.0065, -side)
	return mb


def dent_delta(key, p):
	"""How far a crash moves the point p (Blender coords) at full damage on one side (see build_seicento.dent_delta)."""
	s = Y0 - p.y
	d = Vector()
	if key == "front":
		w = smoothstep(1.2, 0.0, s)
		d.y = -0.30 * w ** 1.2 * (1.0 + 0.25 * _nz(p, 0.3))
		d.z = -0.08 * w * (1.0 + _nz(p, 1.1)) + 0.05 * w * w * smoothstep(0.62, 0.82, p.z)
		d.x = 0.05 * w * _nz(p, 2.4)
	elif key == "rear":
		w = smoothstep(LENGTH - 1.0, LENGTH, s)
		d.y = 0.24 * w ** 1.2 * (1.0 + 0.25 * _nz(p, 0.9))
		d.z = -0.05 * w * (1.0 + _nz(p, 2.0))
		d.x = 0.04 * w * _nz(p, 3.1)
	else:
		side = -1.0 if key == "left" else 1.0
		if p.x * side > 0.2:
			g = math.exp(-((s - 2.1) / 0.65) ** 2 - ((p.z - 0.68) / 0.30) ** 2)
			d.x = -side * 0.10 * g * (1.0 + 0.3 * _nz(p, 4.2))
			d.z = -0.02 * g * _nz(p, 5.0)
	return d


def build_wheel():
	"""15" five-spoke alloy with a 195/65 R15 tyre; axle along X, outer face towards +X."""
	mb = MB()
	hw = TYRE_W / 2
	R = TYRE_R
	rim = 0.1905  # 15" bead seat radius
	tyre = [(hw - 0.016, rim + 0.005), (hw + 0.002, rim + 0.022), (hw + 0.008, rim + 0.062), (hw + 0.006, R - 0.034),
		(hw - 0.006, R - 0.012), (hw - 0.026, R - 0.0015), (0.040, R), (0.034, R), (0.031, R - 0.008), (0.022, R - 0.008),
		(0.020, R), (-0.020, R), (-0.022, R - 0.008), (-0.031, R - 0.008), (-0.034, R), (-0.040, R), (-hw + 0.026, R - 0.0015),
		(-hw + 0.006, R - 0.012), (-hw - 0.006, R - 0.034), (-hw - 0.008, rim + 0.062), (-hw - 0.002, rim + 0.022),
		(-hw + 0.016, rim + 0.005)]

	def tyre_out(c):
		r = math.hypot(c.y, c.z)
		radial = Vector((0, c.y / r, c.z / r))
		return Vector((c.x, 0, 0)) * 2.0 + radial * (r - 0.26)
	mb.lathe(tyre, 56, "Tyre", out=tyre_out)
	for k in range(40):  # shoulder tread blocks
		a = 2 * math.pi * k / 40
		for x0, x1 in ((0.042, hw - 0.016), (-hw + 0.016, -0.042)):
			pts = [Vector((x, (R + 0.0003) * math.cos(a + da), (R + 0.0003) * math.sin(a + da))) for x, da in
				((x0, 0.0), (x1, 0.034), (x1, 0.050), (x0, 0.016))]
			mb.poly(pts, "Grille", lambda q: Vector((0, q.y, q.z)))
	for k in range(4):  # raised sidewall lettering arcs
		a0 = 2 * math.pi * k / 4 + 0.25
		rows = []
		for r in (0.236, 0.268):
			rows.append([Vector((hw + 0.0085 - 0.0034 * (r - 0.236) / 0.032, r * math.cos(a0 + 0.8 * j / 8),
				r * math.sin(a0 + 0.8 * j / 8))) for j in range(9)])
		mb.grid(rows, "Sidewall", out=Vector((1, 0, 0)))

	# alloy: barrel with a polished lip, five spokes forking towards the rim, hub with five lug nuts and a centre cap
	barrel = [(hw - 0.004, rim - 0.004), (hw - 0.012, rim - 0.015), (0.062, rim - 0.026), (0.052, rim - 0.040), (0.030, rim - 0.044),
		(-0.04, rim - 0.044), (-0.055, rim - 0.034)]
	mb.lathe(barrel, 56, "Rim", out=lambda c: Vector((1.0, 0, 0)) - Vector((0, c.y, c.z)) * 2.0)
	mb.lathe([(hw - 0.004, rim - 0.004), (hw - 0.012, rim - 0.015)], 56, "Chrome", out=lambda c: Vector((1.0, c.y, c.z)))

	def bar(p0, p1, w0, w1, h0, h1, base0, base1):
		d = Vector((0, p1.y - p0.y, p1.z - p0.z)).normalized()
		t = Vector((0, -d.z, d.y))
		rows = []
		for k in range(2):
			f = float(k)
			c = Vector((0, lerp(p0.y, p1.y, f), lerp(p0.z, p1.z, f)))
			w, h, xb = lerp(w0, w1, f), lerp(h0, h1, f), lerp(base0, base1, f)
			sect = [(-w / 2, 0.0), (w / 2, 0.0), (w / 2, h * 0.55), (w * 0.28, h), (-w * 0.28, h), (-w / 2, h * 0.55)]
			rows.append([Vector((xb + hh, 0, 0)) + c + t * ww for ww, hh in sect])

		def outward(q):
			v = Vector((q.x - (base0 + h0 / 2), q.y - p0.y, q.z - p0.z))
			return v - Vector((0, d.y, d.z)) * (v.y * d.y + v.z * d.z)
		mb.grid(rows, "Rim", closed=True, out=outward, cap_ends=True)

	for k in range(5):
		a = 2 * math.pi * k / 5 + 0.3
		ca, sa = math.cos(a), math.sin(a)
		p_hub = Vector((0, 0.05 * ca, 0.05 * sa))
		p_fork = Vector((0, 0.118 * ca, 0.118 * sa))
		bar(p_hub, p_fork, 0.044, 0.034, 0.020, 0.017, 0.042, 0.046)
		for sgn in (-1, 1):
			a2 = a + sgn * 0.16
			p_end = Vector((0, 0.1745 * math.cos(a2), 0.1745 * math.sin(a2)))
			bar(p_fork, p_end, 0.030, 0.026, 0.017, 0.015, 0.046, 0.050)
	mb.lathe([(0.042, 0.080), (0.056, 0.074), (0.060, 0.0)], 28, "Rim", out=lambda c: Vector((1, c.y, c.z)))
	for k in range(5):
		a = 2 * math.pi * k / 5 + math.pi / 5
		p = Vector((0.056, 0.0575 * math.cos(a), 0.0575 * math.sin(a)))
		mb.tube(p, p + Vector((0.012, 0, 0)), 0.0100, "Chrome", segs=6)
	mb.lathe([(0.012, 0.075), (0.012, 0.150), (0.003, 0.150), (0.003, 0.075)], 36, "BrakeDisc", out=lambda c: Vector((1.0, c.y, c.z)))
	mb.lathe([(0.0, 0.0), (0.0, 0.17), (-0.07, 0.17)], 28, "Under", out=lambda c: Vector((1.0, c.y, c.z)))
	mb.lathe([(0.058, 0.040), (0.066, 0.036), (0.070, 0.022), (0.0715, 0.0)], 24, "Steel", out=lambda c: Vector((1, c.y, c.z)))
	mb.disc(Vector((0.0716, 0, 0)), 0.018, "BadgeBlue", normal=(1, 0, 0), segs=14)
	a_valve = 0.82
	v_base = Vector((0.046, 0.176 * math.cos(a_valve), 0.176 * math.sin(a_valve)))
	mb.tube(v_base, v_base + Vector((0.020, 0.006 * math.cos(a_valve), 0.006 * math.sin(a_valve))), 0.004, "Trim", segs=6)
	return mb


# ---------------------------------------------------------------- previews
def render_all(cam, out_dir):
	views = {
		"front34": ((4.6, 5.2, 1.7), 38, None),
		"rear34": ((-4.6, -5.0, 1.8), 38, None),
		"side": ((8.5, 0.0, 0.72), 30, None),
		"front": ((0.0, 9.0, 0.8), 22, None),
		"rear": ((0.0, -9.0, 0.9), 22, None),
		"top": ((0.0, 0.0, 9.0), 30, None),
		"ref_front": ((-3.2, 5.6, 1.35), 36, (0.0, 0.5, 0.7)),
		"ref_rear": ((-3.0, -5.4, 1.45), 36, (0.0, -0.4, 0.75)),
		"side_l": ((-8.5, 0.0, 0.72), 30, None),
		"nose": ((-1.6, 4.4, 1.0), 30, (-0.1, Y0 - 0.2, 0.6)),
		"tail": ((1.4, -3.6, 1.1), 30, (0.1, Y0 - LENGTH + 0.2, 0.75)),
		"wheel": ((-2.0, Y0 - FRONT_AXLE_S + 0.6, 0.55), 30, (-TRACK_F / 2, Y0 - FRONT_AXLE_S, TYRE_R)),
		"cabin": ((2.6, 0.6, 1.9), 40, (0.0, 0.0, 0.85)),
	}
	carkit.render_views(cam, out_dir, views, (0, 0, 0.7))


# ---------------------------------------------------------------- main
def main():
	bpy.ops.wm.read_factory_settings(use_empty=True)
	body = build_body()
	details, pj = build_details(body)
	liner = build_liner(body)
	cabin_mb = build_cabin()
	stripes = build_stripes(pj)
	martini = build_martini(pj)
	abarth = build_abarth(pj)
	marlboro = build_marlboro(pj)
	wheel = build_wheel()
	body.extend(liner)
	for i, v in enumerate(body.v):  # road grime towards the sills and bumpers, and a slight mottle
		low = 1.0 - smoothstep(0.20, 0.66, v.z)
		mottle = 0.5 + 0.5 * math.sin(v.x * 17.0 + v.y * 9.0) * math.sin(v.y * 13.0 - v.z * 11.0)
		body.col[i] *= 1.0 - 0.30 * low * (0.65 + 0.35 * mottle) - 0.025 * mottle
	objs = {"Body": body.emit("Body", sharp_deg=55, colors=True), "Details": details.emit("Details", sharp_deg=40),
		"Stripes": stripes.emit("Stripes"), "Wheel": wheel.emit("Wheel", sharp_deg=40), "Cabin": cabin_mb.emit("Cabin", sharp_deg=40),
		"Martini": martini.emit("Martini", sharp_deg=60), "Abarth": abarth.emit("Abarth", sharp_deg=60),
		"Marlboro": marlboro.emit("Marlboro", sharp_deg=60)}
	total = 0
	for name, ob in objs.items():
		t = sum(len(p.vertices) - 2 for p in ob.data.polygons)
		total += t
		print("%-8s %6d tris" % (name, t))
	print("total    %6d tris" % total)
	for name in ("Body", "Details", "Stripes", "Martini", "Abarth", "Marlboro"):
		add_damage_keys(objs[name], dent_delta)
	kit.export_glb(OUT_GLB, texcoords=False)
	if arg("--blend"):
		bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(arg("--blend")))
	if arg("--renders"):
		view = next((k for k in ("martini", "abarth", "marlboro") if "--" + k in sys.argv), "")
		cam = carkit.setup_preview((0.92, 0.92, 0.9) if view in ("martini", "marlboro") else (0.07, 0.17, 0.42))
		objs["Stripes"].hide_render = True
		for k in ("Martini", "Abarth", "Marlboro"):
			objs[k].hide_render = view != k.lower()
		objs["Cabin"].hide_render = False
		for sc, tr in ((FRONT_AXLE_S, TRACK_F), (REAR_AXLE_S, TRACK_R)):
			for sx in (1, -1):
				w = bpy.data.objects.new("W", objs["Wheel"].data)
				w.location = bl(sx * tr / 2, sc, TYRE_R)
				w.scale.x = sx
				bpy.context.scene.collection.objects.link(w)
		objs["Wheel"].hide_render = True
		render_all(cam, os.path.abspath(arg("--renders")))


if __name__ == "__main__":
	main()
