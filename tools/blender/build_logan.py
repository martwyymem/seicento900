"""Builds the game's Dacia Logan (first generation, L90, 2004-2008, four-door saloon, 1.4 MPI) in Blender.

Run from the repository root (Blender 4.2 or newer, headless):

    blender -b -P tools/blender/build_logan.py -- [--renders DIR] [--blend FILE]

Writes godot/models/logan.glb. With --renders it also saves preview PNGs (front, rear, side, top, three-quarters).

The second campaign car, built after build_golf4.py (see AGENTS.md, "Adding the next car"): same object and material
names, so race_car_visual.gd drives it unchanged. Real-car numbers: 4247 mm long, 1735 mm wide (without mirrors),
1525 mm high, 2630 mm wheelbase, 1466/1456 mm track, 185/65 R15 tyres on 15" steel wheels with plain covers.

A three-box saloon: a short, high bonnet, a tall glasshouse over a straight belt, a broad C-pillar, a short high boot
with a near-vertical tail, tall plain flanks with big wheel gaps, unpainted grey bumpers (the base car), large headlamps
that sweep up into the wings (a dark bezel, two chrome reflector bowls and a domed cover), a slim chrome grille with the shield, and tall tail lamps at the corners of the boot.

Scene objects: Body (painted shell with glass, trim, mirrors, handles, underbody and cabin liner; vertex colours carry
the panel gaps), Details (lamps, the grey bumpers, grille, plates, wipers, exhaust, wheel wells), Stripes, Martini,
Abarth, Marlboro (liveries), Cabin (dash, wheel, seats, bench, console; hidden on distant cars), Wheel (steel wheel with
its cover and the tyre, one wheel at the origin, outer face towards +X).
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
OUT_GLB = os.path.join(ROOT, "godot", "models", "logan.glb")

# ---------------------------------------------------------------- real-car numbers
LENGTH = 4.247
WHEELBASE = 2.630
FRONT_AXLE_S = 0.800  # 800 mm front overhang, 817 mm rear: the long boot is mostly behind a long wheelbase
REAR_AXLE_S = FRONT_AXLE_S + WHEELBASE
Y0 = FRONT_AXLE_S + WHEELBASE / 2.0
TRACK_F = 1.466
TRACK_R = 1.456
TYRE_R = 0.3108  # 185/65 R15: 381 mm rim + 2 x 120.25 mm sidewall = 621.5 mm
TYRE_W = 0.185
ARCH_R = 0.385  # the Logan's high ride leaves a big gap over the tyre

S_COWL, S_WS_TOP = 1.22, 1.92
S_SCUTTLE = 1.14
S_SAIL = 1.50
S_B0, S_B1 = 2.30, 2.40
S_QR = 2.98  # the rear door's fixed quarter light: its post, after which the glass's top edge falls to the rear corner
S_Q1 = 3.34  # the side glass's rear corner, under the broad C-pillar
S_RG0, S_RG1 = 3.12, 3.62  # the rear screen, from the roof's end down to the boot lid
S_DECK = 3.68  # the boot lid's leading shut line
S_DOOR = (1.30, 2.35, 3.30)  # front door, B-pillar and the rear door's trailing edge over the rear arch
FRIT = 0.015
PILLAR = 0.07


def bl(x, s, z):
	return Vector((x, Y0 - s, z))


# ---------------------------------------------------------------- body profile curves (metres)
# Plan, elevation and section lines for the L90: an upright face, a short bonnet rising to a high scuttle, a windscreen at
# ~37 deg, a long flat roof highest over the B-pillar, the rear screen at ~34 deg onto a short flat boot deck (the third
# box) and a near-vertical tail; slab flanks with almost no tumblehome under a straight, slightly rising belt.
W = Curve([(0.0, 0.62), (0.03, 0.70), (0.08, 0.765), (0.16, 0.81), (0.30, 0.843), (0.55, 0.862), (0.85, 0.8675),
	(1.3, 0.8675), (3.2, 0.8675), (3.7, 0.865), (3.95, 0.857), (4.08, 0.845), (4.16, 0.825), (4.20, 0.80),
	(4.228, 0.76), (LENGTH, 0.68)])
ZM = Curve([(0.0, 0.45), (0.3, 0.55), (1.0, 0.64), (1.5, 0.66), (3.3, 0.68), (3.9, 0.68), (LENGTH, 0.56)])  # the widest line, under the shoulder
WSH = Curve([(0.0, 0.56), (0.03, 0.64), (0.07, 0.70), (0.14, 0.745), (0.3, 0.778), (0.6, 0.80), (1.0, 0.812),
	(1.5, 0.818), (3.2, 0.818), (3.8, 0.815), (4.0, 0.806), (4.10, 0.79), (4.17, 0.765), (4.21, 0.735),
	(4.232, 0.70), (LENGTH, 0.62)])
ZSH = Curve([(0.0, 0.64), (0.015, 0.725), (0.035, 0.785), (0.07, 0.815), (0.13, 0.830), (0.3, 0.846), (0.6, 0.866),
	(0.9, 0.888), (1.1, 0.904), (S_COWL, 0.918), (1.4, 0.945), (1.7, 0.962), (2.2, 0.975), (3.0, 0.99), (3.5, 1.005),
	(3.9, 1.022), (4.10, 1.03), (4.16, 1.022), (4.195, 0.998), (4.215, 0.95), (4.227, 0.85), (4.234, 0.72), (4.241, 0.64),
	(LENGTH, 0.60)])
ZT = Curve([(0.0, 0.68), (0.015, 0.77), (0.035, 0.828), (0.07, 0.852), (0.13, 0.864), (0.3, 0.877), (0.6, 0.895),
	(0.9, 0.917), (1.1, 0.938), (S_COWL, 0.952), (1.4, 1.075), (1.6, 1.21), (1.8, 1.355), (S_WS_TOP, 1.43), (2.02, 1.477),
	(2.2, 1.507), (2.5, 1.523), (2.8, 1.518), (2.95, 1.505), (S_RG0, 1.473), (3.25, 1.392), (3.40, 1.275), (3.52, 1.168),
	(S_RG1, 1.105), (3.72, 1.08), (3.85, 1.075), (4.05, 1.072), (4.13, 1.064), (4.17, 1.05), (4.20, 1.022), (4.218, 0.97), (4.229, 0.86),
	(4.236, 0.72), (4.242, 0.65), (LENGTH, 0.61)])
ZB = Curve([(0.0, 0.265), (0.07, 0.250), (0.25, 0.24), (0.5, 0.235), (1.0, 0.232), (2.5, 0.23), (3.5, 0.236),
	(3.95, 0.255), (4.15, 0.27), (LENGTH, 0.29)])
WR = Curve([(0.0, 0.50), (0.04, 0.57), (0.09, 0.63), (0.16, 0.67), (0.35, 0.705), (0.7, 0.728), (S_COWL, 0.738),
	(1.5, 0.71), (S_WS_TOP, 0.672), (2.4, 0.662), (3.0, 0.658), (S_RG0, 0.656), (3.35, 0.672), (S_RG1, 0.703), (4.0, 0.715),
	(4.12, 0.705), (4.19, 0.68), (4.225, 0.64), (LENGTH, 0.55)])
DR = Curve([(0.0, 0.012), (0.2, 0.03), (S_COWL, 0.04), (S_WS_TOP - 0.05, 0.05), (3.6, 0.05), (S_RG1, 0.03), (3.9, 0.02),
	(LENGTH, 0.012)])

SEG_ROWS = [3, 2, 5, 5, 1, 4, 2, 8]
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
		gz = F.y + max(0.004, (gz - F.y) * (1.0 - k))
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
		S_Q1, S_RG0, S_RG0 + FRIT, S_RG1 - FRIT, S_RG1, S_DECK]
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
	"Headlight": ((0.30, 0.31, 0.32), 0.10, 0.9, {"emit": ((1.0, 0.95, 0.84), 0.2)}),
	"Indicator": ((1.0, 0.42, 0.04), 0.1, 0.0, {"emit": ((1.0, 0.35, 0.02), 0.7)}),
	"Taillight": ((0.42, 0.01, 0.015), 0.08, 0.0, {"emit": ((1.0, 0.05, 0.03), 0.15)}),
	"LampClear": ((0.85, 0.80, 0.80), 0.08, 0.0, {}),
	"LampBezel": ((0.10, 0.105, 0.11), 0.32, 0.75, {}),  # the headlamp's inner bezel round the reflector bowls
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
	"TailBulb": ((0.55, 0.05, 0.04), 0.15, 0.3, {"emit": ((1.0, 0.08, 0.04), 0.12)}),
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
			# the bonnet's and the boot lid's side shut lines, along the top of the wings
			if (0.12 < s < S_COWL - 0.015 or S_DECK < s < LENGTH - 0.05) and j == sum(SEG_ROWS[:SEG_FG]):
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
	# door mirrors: the base car's black plastic shells on the sail, glass facing back
	for side in (1, -1):
		mb.box(bl(side * 0.84, 1.44, 0.985), (0.06, 0.09, 0.04), "Trim")
		mb.blob(bl(side * 0.905, 1.48, 1.035), (0.072, 0.05, 0.062), "Trim", e=0.5)
		mb.blob(bl(side * 0.905, 1.527, 1.035), (0.064, 0.006, 0.050), "Chrome", e=0.35)
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
def reflector(mb, pj, proj, u, v, r):
	"""A headlamp reflector bowl with depth: a chrome rim standing proud of the lamp's backing, a parabolic bowl falling
	back from it to a lit floor (Headlight) and a clear bulb cap in the middle; no dark cup, which read as a pupil at night."""
	loc, n = pj.hit(*proj(u, v))
	n = (n + Vector((0.0, 1.0, 0.0))).normalized()  # face straight ahead, not along the wrapped surface
	helper = Vector((1, 0, 0)) if abs(n.x) < 0.9 else Vector((0, 1, 0))
	bx = n.cross(helper).normalized()
	by = n.cross(bx)
	basis = Matrix((bx, by, n)).transposed()
	base = loc + n * 0.0150  # on the lamp's backing (the bezel at 0.0135)
	segs = 28
	# the bowl: radius against height off the backing, the rim 16 mm in front of the floor
	prof = [(r, 0.016), (r * 0.96, 0.0135), (r * 0.82, 0.0085), (r * 0.62, 0.0045), (r * 0.42, 0.002), (r * 0.30, 0.001)]
	rows = [[base + n * d + (bx * math.cos(2 * math.pi * k / segs) + by * math.sin(2 * math.pi * k / segs)) * rr
		for k in range(segs)] for rr, d in prof]
	mb.grid(rows[:2], "Chrome", closed=True, out=n)
	mb.grid(rows[1:], "Headlight", closed=True, out=n)
	mb.disc(base + n * 0.001, r * 0.30, "Headlight", normal=n, segs=segs)
	mb.ring(base + n * 0.0162, r * 0.96, r * 1.07, "Chrome", normal=n, segs=segs)


FB_AXIS = 0.55  # the nose's cylinder axis (station): rays at 76 deg reach the flank just ahead of the front arch
RB_AXIS = LENGTH - 0.55

# the headlamp (x across the car, z height, seen from the front): tall against the grille, its top edge following the
# bonnet's shut line out and up into the wing, the outer end wrapping round the corner. The tail lamp likewise, seen from
# behind: an upright block at the corner of the boot, red above, amber and clear below.
# (2026-11-16: taller, down to the bumper, and sweeping up into the wing at the outer end as the real lamp does)
HEADLAMP = [(0.316, 0.643), (0.316, 0.818), (0.328, 0.836), (0.42, 0.840), (0.55, 0.843), (0.64, 0.846), (0.70, 0.850),
	(0.735, 0.855), (0.758, 0.857), (0.772, 0.846), (0.780, 0.815), (0.783, 0.765), (0.779, 0.722), (0.765, 0.688),
	(0.735, 0.660), (0.62, 0.648), (0.45, 0.644), (0.34, 0.643)]
# the indicator: a small amber section low in the lamp's outer corner, under the clear lens (2026-11-20: it was the whole
# outer end, 18 cm tall round the wrap, and read as a yellow headlamp)
HEAD_AMBER = [(0.712, 0.700), (0.712, 0.742), (0.718, 0.752), (0.745, 0.754), (0.758, 0.746), (0.762, 0.725), (0.758, 0.700),
	(0.748, 0.690), (0.722, 0.689)]
TAIL_OUT = [(0.505, 0.668), (0.505, 0.90), (0.515, 0.985), (0.535, 1.025), (0.58, 1.040), (0.70, 1.040), (0.745, 1.028),
	(0.768, 0.995), (0.776, 0.80), (0.770, 0.70), (0.752, 0.668)]
TAIL_RED = [(0.512, 0.828), (0.512, 0.90), (0.522, 0.980), (0.540, 1.017), (0.582, 1.031), (0.698, 1.031), (0.740, 1.020),
	(0.759, 0.992), (0.767, 0.828)]
TAIL_LOW = [(0.512, 0.675), (0.512, 0.828), (0.767, 0.828), (0.769, 0.80), (0.764, 0.705), (0.748, 0.675)]
TAIL_EDGE = [(0.675, 0.748), (0.705, 0.764), (0.80, 0.769), (0.828, 0.767)]  # the lower half's outer edge, x against height


def tail_edge(z):
	pts = TAIL_EDGE
	if z <= pts[0][0]:
		return pts[0][1]
	for (z0, x0), (z1, x1) in zip(pts, pts[1:]):
		if z <= z1:
			return lerp(x0, x1, (z - z0) / (z1 - z0))
	return pts[-1][1]


def tail_section(z0, z1, inset=0.0045):
	"""A section of the tail lamp's lower half between two heights, out to the lamp's own curved outer edge (the amber
	indicator and the reversing lamp used to stop short of it, leaving a notch of gasket at the corner)."""
	zs = [lerp(z0, z1, k / 6) for k in range(7)]
	outer = [(tail_edge(z) - inset, z) for z in zs]
	return [(0.512 + inset, z0), (0.512 + inset, z1)] + list(reversed(outer))


def dense(pts, step=0.03):
	"""An outline with extra points along its long straight edges, so the projector's spline resampling keeps them straight."""
	out = []
	for i, a in enumerate(pts):
		b = pts[(i + 1) % len(pts)]
		n = max(1, int(math.hypot(b[0] - a[0], b[1] - a[1]) / step))
		out += [(lerp(a[0], b[0], k / n), lerp(a[1], b[1], k / n)) for k in range(n)]
	return out


TAIL_OUT, TAIL_RED, TAIL_LOW = dense(TAIL_OUT), dense(TAIL_RED), dense(TAIL_LOW)
SHIELD = [(-0.040, 0.050), (0.040, 0.050), (0.044, 0.010), (0.034, -0.022), (0.0, -0.048), (-0.034, -0.022), (-0.044, 0.010)]


def wrap_limit(pj, proj, sc, front, v, gap=0.004):
	"""How far (degrees round the nose or tail axis) a bumper row at height v wraps before it meets the wheel arch: the
	largest angle whose ray still lands on the outer flank ahead of (front) or behind the arch's cut-out."""
	def ok(u):
		o, d = proj(u, v)
		loc, nor, _, _ = pj.tree.ray_cast(o, d)
		if loc is None or nor.dot(d) > 0 or loc.x < 0.05:
			return False
		s = Y0 - loc.y
		if (s > sc) if front else (s < sc):
			return False
		return math.hypot(s - sc, loc.z - TYRE_R) > ARCH_R + gap
	lo, hi = 40.0, 150.0
	assert ok(lo)
	for _ in range(28):
		mid = (lo + hi) / 2
		if ok(mid):
			lo = mid
		else:
			hi = mid
	return lo


def wrap_band(pj, mb, proj, sc, front, vs, off, mat, reach=1.0, n=96):
	"""A bumper moulding wrapped round the nose or tail to the wheel arches: each row runs out to where it meets the arch,
	so the moulding's end follows the arch's curve instead of a flat vertical cut, and thins over its last fifth so it
	blends into the wing. off(v) is the moulding's section (offset off the shell at height v)."""
	lim = [wrap_limit(pj, proj, sc, front, v) * reach for v in vs]
	# columns: fine near the corners and ends, where the surface turns fast
	ts = sorted(set([round(math.copysign(1.0 - (1.0 - k / n) ** 1.6, 1), 5) for k in range(n + 1)] +
		[round(-math.copysign(1.0 - (1.0 - k / n) ** 1.6, 1), 5) for k in range(n + 1)]))
	pts, nors = [], []
	for t in ts:
		taper = 1.0 - 0.8 * smoothstep(0.82, 1.0, abs(t))
		row, nrow = [], []
		for v, um in zip(vs, lim):
			loc, nor = pj.hit(*proj(t * um, v))
			row.append(loc + nor * off(v) * taper)
			nrow.append(nor)
		pts.append(row)
		nors.append(nrow)
	ids = [[mb.vert(p) for p in row] for row in pts]
	for i in range(len(ts) - 1):
		for j in range(len(vs) - 1):
			ref = nors[i][j] + nors[i + 1][j] + nors[i][j + 1] + nors[i + 1][j + 1]
			mb.face([ids[i][j], ids[i + 1][j], ids[i + 1][j + 1], ids[i][j + 1]], mat, ref)
	for i, k in ((0, 1), (len(ts) - 1, len(ts) - 2)):  # the ends: a short return into the shell, along the arch
		inner = [pts[i][j] - nors[i][j] * 0.006 for j in range(len(vs))]
		ref = pts[i][len(vs) // 2] - pts[k][len(vs) // 2]
		mb.poly(pts[i] + list(reversed(inner)), mat, ref)
	return pts


def build_plastics(pj, mb):
	"""The base car's grey bumpers, moulded over the painted shell's nose and tail and wrapped round to the arches, the
	lower intake and the number plates in them; the slim chrome grille with the shield; shut lines."""
	fp = cyl_proj(FB_AXIS, False)
	rows = [(0.272, -0.002), (0.281, 0.010), (0.297, 0.017), (0.600, 0.017), (0.622, 0.012), (0.636, -0.001)]
	vs = sorted(set([r[0] for r in rows] + spread(0.31, 0.59, 0.02)))  # dense rows: a long chord cuts into the round corners
	wrap_band(pj, mb, fp, FRONT_AXLE_S, True, vs, lambda v, rows=rows: profile(v, rows), "Bumper")
	# a moulded rubbing line along the bumper, and the lower intake: a black grille in a recess under the plate
	rows = [(0.505, 0.017), (0.509, 0.022), (0.523, 0.022), (0.527, 0.017)]
	wrap_band(pj, mb, fp, FRONT_AXLE_S, True, [r[0] for r in rows], lambda v, rows=rows: profile(v, rows), "Bumper", reach=0.97)
	pj.star(mb, rounded_rect(-0.42, 0.42, 0.318, 0.425, 0.035), front_proj, "Trim", offset=0.0185, rings=1, samples=2, skirt=0.0)
	pj.star(mb, rounded_rect(-0.405, 0.405, 0.328, 0.415, 0.028), front_proj, "Grille", offset=0.0195, rings=1, samples=2,
		skirt=0.0)
	for z in (0.355, 0.385):
		pj.strip(mb, -0.40, 0.40, z, z + 0.008, 24, 1, front_proj, "Bumper", offset=0.0215)
	# front number plate over the intake: a European plate 520 x 110 mm
	pj.star(mb, rounded_rect(-0.264, 0.264, 0.439, 0.5557, 0.006), front_proj, "Trim", offset=0.0225, rings=1, samples=2, skirt=0.006)
	pj.star(mb, rounded_rect(-0.2559, 0.2559, 0.445, 0.5497, 0.004), front_proj, "Plate", offset=0.0255, rings=1, samples=2,
		skirt=0.0)  # car_plate.gdshader maps the atlas from these numbers (CarCatalog LOGAN_VISUAL plate_y)
	# the slim grille between the headlamps: a chrome surround, black mesh, one chrome bar and the shield on it
	pj.star(mb, rounded_rect(-0.298, 0.298, 0.660, 0.826, 0.024), front_proj, "Chrome", offset=0.0035, rings=1, samples=2,
		skirt=0.004)
	pj.star(mb, rounded_rect(-0.284, 0.284, 0.671, 0.815, 0.018), front_proj, "Grille", offset=0.0055, rings=1, samples=2,
		skirt=0.0)
	pj.strip(mb, -0.284, 0.284, 0.733, 0.753, 30, 1, front_proj, "Chrome", offset=0.0085)
	# the shield, big enough to read at a distance: a dark backing, the chrome shield and its blue field, standing proud
	pj.star(mb, [(x * 1.55, 0.744 + y * 1.55) for x, y in SHIELD], front_proj, "Gasket", offset=0.0100, rings=2, samples=2,
		skirt=0.004)
	pj.star(mb, [(x * 1.42, 0.744 + y * 1.42) for x, y in SHIELD], front_proj, "Chrome", offset=0.0135, rings=2, samples=2,
		skirt=0.003)
	pj.star(mb, [(x * 1.16, 0.746 + y * 1.16) for x, y in SHIELD], front_proj, "BadgeBlue", offset=0.0155, bulge=0.002, rings=2,
		samples=2, skirt=0.0)
	# the bonnet's leading shut line, over the headlamps and grille
	pj.strip(mb, -0.72, 0.72, 0.861, 0.866, 50, 1, front_proj, "Gasket", offset=0.0012)
	# rear: the bumper, its rubbing line and two reflectors, wrapped round to the rear arches
	rp = cyl_proj(RB_AXIS, True)
	rows = [(0.300, -0.002), (0.309, 0.010), (0.325, 0.018), (0.610, 0.018), (0.630, 0.012), (0.643, -0.001)]
	vs = sorted(set([r[0] for r in rows] + spread(0.34, 0.60, 0.02)))
	wrap_band(pj, mb, rp, REAR_AXLE_S, False, vs, lambda v, rows=rows: profile(v, rows), "Bumper")
	rows = [(0.505, 0.018), (0.509, 0.023), (0.523, 0.023), (0.527, 0.018)]
	wrap_band(pj, mb, rp, REAR_AXLE_S, False, [r[0] for r in rows], lambda v, rows=rows: profile(v, rows), "Bumper", reach=0.97)


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
		# headlamp: gasket frame, reflector backing, amber indicator, two reflector bowls, clear lens
		hp = lambda u, v, side=side: front_proj(side * u, v)
		# a black housing standing proud of the shell (its sides are the skirt), so the lamp reads as a unit set into the
		# nose, not a decal on it
		pj.star(mb, HEADLAMP, hp, "Gasket", offset=0.012, rings=5, samples=3, skirt=0.012)
		cu = sum(p[0] for p in HEADLAMP) / len(HEADLAMP)
		cv = sum(p[1] for p in HEADLAMP) / len(HEADLAMP)
		pj.star(mb, [(lerp(u, cu, 0.05), lerp(v, cv, 0.10)) for u, v in HEADLAMP], hp, "LampBezel", offset=0.0135, bulge=0.0,
			rings=7, samples=3, skirt=0.0)
		pj.star(mb, HEAD_AMBER, hp, "Indicator", offset=0.018, bulge=0.004, rings=6, samples=4, skirt=0.0)
		# the big dipped/main reflector inboard and a smaller one beside it, with a chrome divider between them
		reflector(mb, pj, hp, 0.430, 0.745, 0.068)
		reflector(mb, pj, hp, 0.604, 0.750, 0.056)
		pj.strip(mb, 0.516, 0.524, 0.665, 0.828, 1, 8, hp, "Chrome", offset=0.026)
		# the clear cover: domed well forward of the housing, over the reflectors, its edge closed down to the housing
		pj.star(mb, [(lerp(u, cu, 0.03), lerp(v, cv, 0.05)) for u, v in HEADLAMP], hp, "LampGlass", offset=0.034, bulge=0.012,
			rings=7, samples=3, skirt=0.020)

		# tail lamp: gasket, the red upper half with its bulb, amber indicator and clear reversing lamp below, lenses
		tp = lambda u, v, side=side: rear_proj(side * u, v)
		pj.star(mb, TAIL_OUT, tp, "Gasket", offset=0.003, rings=2, samples=3, skirt=0.0)
		pj.star(mb, TAIL_RED, tp, "Taillight", offset=0.006, bulge=0.002, rings=3, samples=3, skirt=0.0)
		# the stop lamp's reflector behind the red lens: the inner part of the red half, not a bulb disc
		ru = sum(p[0] for p in TAIL_RED) / len(TAIL_RED)
		rv = sum(p[1] for p in TAIL_RED) / len(TAIL_RED)
		pj.star(mb, [(lerp(u, ru, 0.22), lerp(v, rv, 0.22)) for u, v in TAIL_RED], tp, "TailBulb", offset=0.0075, bulge=0.002,
			rings=3, samples=3, skirt=0.0)
		pj.star(mb, dense(tail_section(0.750, 0.826), 0.015), tp, "Indicator", offset=0.0065, rings=6, samples=2, skirt=0.0)
		pj.star(mb, dense(tail_section(0.677, 0.748), 0.015), tp, "LampClear", offset=0.0065, rings=6, samples=2, skirt=0.0)
		pj.star(mb, TAIL_RED, tp, "TailGlass", offset=0.0125, bulge=0.003, rings=3, samples=3, skirt=0.0)
		pj.star(mb, TAIL_LOW, tp, "LampGlass", offset=0.0115, bulge=0.002, rings=3, samples=3, skirt=0.0)

		pj = pj_all
		sp = side_proj(side)
		# the rear door's fixed quarter light: a black post splits it off the drop glass
		pj.strip(mb, S_QR - 0.005, S_QR + 0.02, 0.99, 1.42, 2, 8, sp, "Trim", offset=0.003)
		# front wing side repeater, behind the arch
		pj.star(mb, ellipse(1.11, 0.79, 0.026, 0.012, 12), sp, "Gasket", offset=0.002, rings=1, samples=2)
		pj.star(mb, ellipse(1.11, 0.79, 0.020, 0.008, 12), sp, "Indicator", offset=0.004, bulge=0.002, rings=2, samples=2)

		# black pull handles and the driver's lock barrel
		for hs, hl in ((2.17, 0.925), (3.11, 0.935)):
			pj.star(mb, rounded_rect(hs - 0.065, hs + 0.065, hl - 0.018, hl + 0.018, 0.012), sp, "Trim", offset=0.003, rings=2,
				samples=2)
		pj.star(mb, ellipse(2.17 + 0.095, 0.925, 0.009, 0.009, 10), sp, "Chrome", offset=0.004, rings=1, samples=1)

		# wheel-well liners (black arcs sealing the shell)
		for sc, tr in ((FRONT_AXLE_S, TRACK_F), (REAR_AXLE_S, TRACK_R)):
			rows = []
			for xo in (0.48, 0.75):
				row = []
				for k in range(21):
					a = math.radians(-12 + 204 * k / 20)
					row.append(bl(side * xo, sc - (ARCH_R - 0.006) * math.cos(a), TYRE_R + (ARCH_R - 0.006) * math.sin(a)))
				rows.append(row)
			mb.grid(rows, "Under", out=lambda q, sc=sc: Vector((0, (Y0 - sc) - q.y, TYRE_R - q.z)))
			# the wheelhouse's inner wall, so the arch does not show daylight under the car
			c = bl(side * 0.48, sc, TYRE_R)
			arc = rows[0]
			for k in range(len(arc) - 1):
				mb.poly([c, arc[k], arc[k + 1]], "Under", Vector((side, 0, 0)))

	# fuel flap on the right rear wing, over the arch
	spr = side_proj(1)
	loc, n = pj.hit(*spr(3.74, 0.86))
	mb.ring(loc + n * 0.0012, 0.055, 0.0585, "Gasket", normal=n, segs=28)

	# boot lid: the plate in its recess between the lamps, a chrome strip and the shield over it, the badges, shut lines
	pj.star(mb, rounded_rect(-0.268, 0.268, 0.716, 0.8327, 0.012), rear_proj, "Gasket", offset=0.0015, rings=1, samples=2, skirt=0.0)
	pj.star(mb, rounded_rect(-0.2559, 0.2559, 0.722, 0.8267, 0.004), rear_proj, "Plate", offset=0.004, rings=1, samples=2, skirt=0.0)
	pj.star(mb, rounded_rect(-0.24, 0.24, 0.848, 0.862, 0.006), rear_proj, "Chrome", offset=0.004, rings=1, samples=2, skirt=0.002)
	# the shield and the lettering: chrome over a dark shadow so they read against any paint colour
	pj.star(mb, [(x * 1.40, 0.930 + y * 1.40) for x, y in SHIELD], rear_proj, "Gasket", offset=0.0035, rings=2, samples=2, skirt=0.003)
	pj.star(mb, [(x * 1.28, 0.930 + y * 1.28) for x, y in SHIELD], rear_proj, "Chrome", offset=0.0065, rings=2, samples=2, skirt=0.003)
	pj.star(mb, [(x * 1.04, 0.932 + y * 1.04) for x, y in SHIELD], rear_proj, "BadgeBlue", offset=0.0085, bulge=0.002, rings=2,
		samples=2, skirt=0.0)
	for text, cu, w in (("LOGAN", 0.355, 0.17), ("DACIA", -0.355, 0.16)):
		text_decal(pj, mb, rear_proj, text, cu + 0.004, 0.893 - 0.005, w, "Gasket", 0.0035, 1)  # the drop shadow
		text_decal(pj, mb, rear_proj, text, cu, 0.893, w, "Chrome", 0.0060, 1)
	for x in (-0.498, 0.498):  # down the inner edges of the lamps
		pj.strip(mb, x + 0.003, x - 0.003, 0.660, 1.035, 1, 14, rear_proj, "Gasket", offset=0.0015)
	pj.strip(mb, -0.498, 0.498, 0.657, 0.663, 30, 1, rear_proj, "Gasket", offset=0.0015)  # over the bumper
	pj.strip(mb, S_DECK - 0.003, S_DECK + 0.003, -0.70, 0.70, 1, 40, top_proj, "Gasket", offset=0.0012)  # behind the screen

	# scuttle washer jets and wipers parked along the base of the windscreen
	for x in (-0.30, 0.30):
		pj.star(mb, ellipse(S_SCUTTLE + 0.02, x, 0.012, 0.008, 8), top_proj, "Trim", offset=0.004, rings=1, samples=1)
	for xp, x1 in ((-0.52, 0.00), (0.06, 0.60)):
		base_p = pj.hit(*top_proj(S_SCUTTLE + 0.06, xp))[0]
		mb.blob(base_p + Vector((0, 0, 0.010)), (0.018, 0.018, 0.014), "Trim", e=0.3)
		a = base_p + Vector((0, 0, 0.018))
		b = pj.hit(*top_proj(S_SCUTTLE + 0.20, x1))[0] + Vector((0, 0, 0.016))
		mb.tube(a, b, 0.006, "Trim", segs=6)
		bx0 = pj.hit(*top_proj(S_SCUTTLE + 0.18, xp + 0.05))[0] + Vector((0, 0, 0.012))
		bx1 = pj.hit(*top_proj(S_SCUTTLE + 0.23, x1 + 0.02))[0] + Vector((0, 0, 0.012))
		mb.box((bx0 + bx1) / 2, ((bx1 - bx0).length, 0.012, 0.012), "Trim",
			basis=Matrix.Rotation(math.atan2(bx1.y - bx0.y, bx1.x - bx0.x), 3, "Z"))

	# the roof aerial at the front of the roof, over the windscreen
	base = pj.hit(*top_proj(2.03, 0.0))[0]
	mb.blob(base + Vector((0, 0, 0.012)), (0.022, 0.035, 0.015), "Trim", e=0.4)
	mb.tube(base + Vector((0, 0, 0.02)), base + Vector((0, -0.10, 0.36)), 0.004, "Trim", segs=6)

	# exhaust: a single plain tailpipe under the right of the rear bumper
	mb.tube(bl(0.22, 3.62, 0.27), bl(-0.20, 3.62, 0.27), 0.075, "Steel", segs=14)
	mb.tube(bl(0.40, 3.70, 0.255), bl(0.40, LENGTH + 0.01, 0.262), 0.023, "Exhaust", segs=14, caps=False)
	mb.ring(bl(0.40, LENGTH + 0.01, 0.262), 0.019, 0.024, "Exhaust", normal=(0, -1, 0), segs=14)
	mb.disc(bl(0.40, LENGTH, 0.262), 0.020, "Under", normal=(0, -1, 0), segs=14)

	# underbody: sump guard, engine bay and boot closed off, flat floor
	mb.box(bl(0, 0.80, 0.235), (0.80, 0.8, 0.03), "Steel")
	mb.box(bl(0, 0.72, 0.45), (1.1, 1.0, 0.42), "Under")
	mb.box(bl(0, 3.85, 0.45), (1.1, 0.75, 0.40), "Under")
	mb.box(bl(0, 2.15, 0.24), (0.95, 2.1, 0.07), "Under")

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
		martini_roundel(pj, mb, sp, 1.72, 0.602, 0.10, -side)
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
	"""15" steel wheel with a plastic cover and a 185/65 R15 tyre; axle along X, outer face towards +X."""
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

	# the base car's pressed-steel wheel under a plain silver plastic cover: a shallow dish with a ring of vent slots and
	# the shield in the middle; the steel barrel shows only from inside
	barrel = [(hw - 0.004, rim - 0.004), (hw - 0.012, rim - 0.015), (0.030, rim - 0.030), (-0.060, rim - 0.030)]
	mb.lathe(barrel, 48, "Steel", out=lambda c: Vector((1.0, 0, 0)) - Vector((0, c.y, c.z)) * 2.0)
	cover = [(hw - 0.003, rim + 0.001), (hw + 0.003, rim - 0.004), (hw + 0.008, rim - 0.016), (hw + 0.010, 0.150),
		(hw + 0.010, 0.118), (hw + 0.006, 0.104), (hw + 0.007, 0.080), (hw + 0.013, 0.064), (hw + 0.015, 0.035), (hw + 0.016, 0.0)]
	mb.lathe(cover, 56, "Rim", out=lambda c: Vector((1.0, 0, 0)))
	for k in range(10):  # vent slots round the dish
		a = 2 * math.pi * k / 10
		pts = [Vector((hw + 0.0108, r * math.cos(a + da), r * math.sin(a + da))) for r, da in
			((0.127, -0.15), (0.141, -0.14), (0.141, 0.14), (0.127, 0.15))]
		mb.poly(pts, "Grille", Vector((1, 0, 0)))
	for k in range(4):  # the four wheel-nut dimples under the cover
		a = 2 * math.pi * k / 4 + math.pi / 4
		mb.disc(Vector((hw + 0.0090, 0.091 * math.cos(a), 0.091 * math.sin(a))), 0.010, "Steel", normal=(1, 0, 0), segs=10)
	mb.ring(Vector((hw + 0.0165, 0, 0)), 0.024, 0.029, "Chrome", normal=(1, 0, 0), segs=20)
	mb.disc(Vector((hw + 0.0168, 0, 0)), 0.024, "BadgeBlue", normal=(1, 0, 0), segs=20)
	mb.lathe([(0.012, 0.075), (0.012, 0.150), (0.003, 0.150), (0.003, 0.075)], 36, "BrakeDisc", out=lambda c: Vector((1.0, c.y, c.z)))
	a_valve = 0.82
	v_base = Vector((hw + 0.004, 0.180 * math.cos(a_valve), 0.180 * math.sin(a_valve)))
	mb.tube(v_base, v_base + Vector((0.016, 0.004 * math.cos(a_valve), 0.004 * math.sin(a_valve))), 0.004, "Trim", segs=6)
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


LIVERY_VIEWS = {"stripes": ("Stripes", (0.55, 0.04, 0.05)), "martini": ("Martini", (0.92, 0.92, 0.9)),
	"abarth": ("Abarth", (0.75, 0.03, 0.04)), "marlboro": ("Marlboro", (0.92, 0.92, 0.9))}


def render_liveries(objs, cam, out_dir):
	"""Each livery on the car (DIR/<livery>/front34, rear34, side, top), over the paint the game pairs it with."""
	tint = bpy.data.materials["Paint"].node_tree.nodes["Tint"]
	sock = next(s for s in tint.inputs if s.identifier == "A_Color")
	for key, (obj, paint) in LIVERY_VIEWS.items():
		for name in LIVERY_VIEWS.values():
			objs[name[0]].hide_render = name[0] != obj
		sock.default_value = (*paint, 1)
		views = {
			"front34": ((4.6, 5.2, 1.7), 38, None),
			"rear34": ((-4.6, -5.0, 1.8), 38, None),
			"side": ((8.5, 0.0, 0.72), 30, None),
			"top": ((0.0, 0.0, 9.0), 30, None),
		}
		carkit.render_views(cam, os.path.join(out_dir, key), views, (0, 0, 0.7))


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
		"Stripes": stripes.emit("Stripes"), "Wheel": wheel.emit("Wheel", sharp_deg=30), "Cabin": cabin_mb.emit("Cabin", sharp_deg=40),
		"Martini": martini.emit("Martini", sharp_deg=60), "Abarth": abarth.emit("Abarth", sharp_deg=60),
		"Marlboro": marlboro.emit("Marlboro", sharp_deg=60)}
	total = 0
	for name, ob in objs.items():
		t = sum(len(p.vertices) - 2 for p in ob.data.polygons)
		total += t
		print("%-8s %6d tris" % (name, t))
	print("total    %6d tris" % total)
	sites = carkit.crush_sites(objs["Body"])
	carkit.split_bonnet(objs, Y0, S_SCUTTLE, carkit.material("Trim"))
	carkit.split_damage_parts(objs, Y0, FRONT_AXLE_S, REAR_AXLE_S, ARCH_R, S_DOOR, S_DECK, carkit.material("Trim"))
	for name in carkit.keyed(objs):
		add_damage_keys(objs[name], dent_delta, sites)
	kit.export_glb(OUT_GLB, texcoords=False)
	carkit.sparsify_glb(OUT_GLB)
	if arg("--blend"):
		bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(arg("--blend")))
	if arg("--renders"):
		view = next((k for k in ("martini", "abarth", "marlboro") if "--" + k in sys.argv), "")
		cam = carkit.setup_preview((0.92, 0.92, 0.9) if view in ("martini", "marlboro") else (0.16, 0.30, 0.52))
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
		out = os.path.abspath(arg("--renders"))
		if "--wreck" in sys.argv:
			carkit.pose_wreck(objs, sites)
		render_all(cam, out)
		if not view:
			render_liveries(objs, cam, out)


if __name__ == "__main__":
	main()
