"""Builds the game's Opel Zafira B (second generation, A05, 2005, 7-seat compact MPV, 1.8 16V 140 PS) in Blender.

Run from the repository root (Blender 4.2 or newer, headless):

    blender -b -P tools/blender/build_zafira.py -- [--renders DIR] [--blend FILE]

Writes godot/models/zafira.glb. With --renders it also saves preview PNGs (front, rear, side, top, three-quarters,
detail close-ups, and liveries).

The seventh campaign car (see AGENTS.md, "Adding the next car"): same object and material names, so race_car_visual.gd
drives it unchanged. Real-car numbers: 4467 mm long, 1801 mm wide (without mirrors), 1635 mm high (over roof rails),
2703 mm wheelbase, 1488/1510 mm track, 205/55 R16 tyres on 16" five-spoke Opel alloys.

An unmistakable 2005 Opel Zafira B compact 7-seat MPV: sleek tall 1.5-box silhouette, short sloped V-creased Opel
bonnet with subtle centre spine crease, steeply raked panoramic windscreen flowing into a long tall roofline with black
roof rails, classic 2005 Opel trapezoid grille with thick horizontal chrome bar and circular Opel lightning-bolt emblem,
large crisp triangular/wedge swept-up headlamps wrapping smoothly around the front corners, clean body-coloured bumper
with wide trapezoidal lower grille and round fog lamps, airy 3-window side glasshouse (front quarter + front door,
rear door, long 3rd-row D-pillar quarter glass), crisp upright tailgate with horizontal chrome trim bar, and tall
vertical wrap-around red/clear tail lamps flanking the rear glass.

Scene objects: Body (painted shell with glass, trim, body-coloured mirrors and handles, black roof rails, underbody
and cabin liner; vertex colours carry the panel gaps), Details (lamps, Opel grille, intakes, plates, wipers, exhaust,
wheel wells), Stripes, Martini, Abarth, Marlboro (liveries), Cabin (high-set MPV dash, centre-stack gearshift, wheel,
front seats, 2nd-row bench, 3rd-row headrests; hidden on distant cars), Wheel (alloy wheel and tyre, one wheel at the
origin, outer face towards +X).
"""
import bpy
import math
import os
import sys
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import carkit
import kit
from carkit import MB, Curve, Projector, add_damage_keys, cr, ellipse, profile, rounded_rect, smoothstep, spread
from carkit import text_decal, text_polys, _nz
from kit import arg, lerp

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_GLB = os.path.join(ROOT, "godot", "models", "zafira.glb")

# ---------------------------------------------------------------- real-car numbers
LENGTH = 4.467
WHEELBASE = 2.703
FRONT_AXLE_S = 0.890  # 890 mm front overhang, 874 mm rear overhang
REAR_AXLE_S = FRONT_AXLE_S + WHEELBASE
Y0 = FRONT_AXLE_S + WHEELBASE / 2.0
TRACK_F = 1.488
TRACK_R = 1.510
TYRE_R = 0.3160  # 205/55 R16: 406.4 mm rim + 2 x 112.75 mm sidewall = 631.9 mm
TYRE_W = 0.205
ARCH_R = 0.372
ROOF = 1.616  # roof sheetmetal crown; low-profile black roof rails reach 1.635 m total height

S_SCUTTLE = 1.04
S_COWL, S_WS_TOP = 1.14, 2.02
S_SAIL = 1.25  # split A-pillar front quarter window starts cleanly behind cowl
S_A2_0, S_A2_1 = 1.48, 1.52  # slim divider post behind the A-pillar front quarter window, just ahead of mirror mount
S_B0, S_B1 = 2.30, 2.40  # black B-pillar
S_C0, S_C1 = 3.26, 3.35  # black C-pillar between rear door glass and long 3rd-row quarter window
S_QR = 3.94  # 3rd-row quarter glass top edge starts sloping down towards the D-pillar
S_Q1 = 4.10  # rear corner of the 3rd-row glass on the belt
S_DECK = 4.11  # tailgate top shut line behind roof
S_RG0, S_RG1 = 4.15, 4.385  # steep MPV rear screen from roof lip down to chrome bar
S_DOOR = (1.36, 2.35, 3.31)  # front door leading edge, B-pillar split, rear door trailing edge
FRIT = 0.015
PILLAR = 0.068


def bl(x, s, z):
	return Vector((x, Y0 - s, z))


# ---------------------------------------------------------------- body profile curves (metres)
# Plan, elevation and section lines for the 2005 Opel Zafira B: rounded V-prow nose (no vertical cliff), short sloping
# bonnet rising smoothly into a long raked panoramic windscreen, tall gently-arched MPV roof with black rails, crisp
# rising beltline and airy 3-window glasshouse, and a clean upright tailgate.
L = LENGTH
W = Curve([
	(0.0, 0.560), (0.03, 0.665), (0.08, 0.745), (0.16, 0.812), (0.30, 0.862), (0.55, 0.888), (0.85, 0.898),
	(1.30, 0.9005), (2.50, 0.9005), (3.55, 0.899), (3.95, 0.892), (4.20, 0.878), (4.34, 0.856), (4.41, 0.824),
	(4.445, 0.778), (4.460, 0.730), (L, 0.665),
])
ZM = Curve([
	(0.0, 0.44), (0.12, 0.48), (0.35, 0.54), (0.90, 0.62), (1.50, 0.66), (3.40, 0.69), (4.10, 0.70), (L, 0.59),
])
WSH = Curve([
	(0.0, 0.495), (0.03, 0.595), (0.08, 0.675), (0.16, 0.745), (0.32, 0.802), (0.60, 0.832), (1.05, 0.846),
	(1.60, 0.850), (2.80, 0.852), (3.70, 0.850), (4.08, 0.842), (4.26, 0.824), (4.36, 0.798), (4.42, 0.766),
	(4.450, 0.728), (L, 0.640),
])
ZSH = Curve([
	(0.0, 0.545), (0.03, 0.590), (0.07, 0.655), (0.13, 0.718), (0.22, 0.780), (0.38, 0.842), (0.62, 0.900),
	(0.86, 0.948), (S_SCUTTLE, 0.985), (S_COWL, 1.005), (1.55, 1.028), (2.15, 1.045), (2.85, 1.064), (3.50, 1.084),
	(4.02, 1.102), (4.24, 1.106), (4.34, 1.095), (4.40, 1.062), (4.435, 0.990), (4.452, 0.880), (4.462, 0.740),
	(L, 0.620),
])
ZT = Curve([
	(0.0, 0.578), (0.03, 0.625), (0.07, 0.692), (0.13, 0.758), (0.22, 0.822), (0.38, 0.886), (0.62, 0.946),
	(0.86, 0.996), (S_SCUTTLE, 1.035), (S_COWL, 1.058), (1.36, 1.185), (1.58, 1.318), (1.80, 1.445), (S_WS_TOP, 1.548),
	(2.18, 1.582), (2.40, 1.600), (2.72, ROOF), (3.30, ROOF - 0.002), (3.72, 1.598), (3.98, 1.588), (S_DECK, 1.578),
	(S_RG0, 1.568), (4.22, 1.460), (4.28, 1.338), (4.335, 1.215), (S_RG1, 1.115), (4.415, 1.065), (4.438, 0.985),
	(4.452, 0.880), (4.461, 0.755), (L, 0.640),
])
ZB = Curve([
	(0.0, 0.258), (0.05, 0.232), (0.20, 0.214), (0.50, 0.205), (1.0, 0.198), (2.8, 0.198), (3.8, 0.212),
	(4.15, 0.245), (4.36, 0.278), (L, 0.308),
])
WR = Curve([
	(0.0, 0.455), (0.04, 0.545), (0.10, 0.620), (0.20, 0.688), (0.45, 0.748), (0.80, 0.778), (S_COWL, 0.790),
	(1.58, 0.742), (S_WS_TOP, 0.688), (2.55, 0.672), (3.35, 0.664), (3.92, 0.652), (S_RG0, 0.630), (4.28, 0.645),
	(S_RG1, 0.668), (4.42, 0.692), (4.452, 0.672), (L, 0.585),
])
DR = Curve([
	(0.0, 0.014), (0.20, 0.032), (S_COWL, 0.042), (S_WS_TOP, 0.056), (3.90, 0.056), (S_RG1, 0.032), (L, 0.014),
])

SEG_ROWS = [3, 2, 5, 5, 1, 4, 2, 8]
SEG_AB, SEG_BC, SEG_CD, SEG_DE, SEG_EF, SEG_FG, SEG_GH, SEG_HI = range(8)


def bonnet_crease_t(s):
	"""Parameter t along H->I for the Opel Zafira B's V-shaped bonnet creases: starts at the trapezoid grille's upper
	outer corners (|x| ~ 0.31 at s = 0.08) and sweeps outward to the base of the A-pillars (|x| ~ 0.64 at S_SCUTTLE)."""
	f = min(1.0, max(0.0, (s - 0.08) / (S_SCUTTLE - 0.08)))
	xc = lerp(0.31, 0.64, f)
	return min(0.66, max(0.16, 1.0 - xc / max(0.30, WR(s))))


def bonnet_crease_dz(s, sub):
	"""Opel signature bonnet sculpting (SEG_HI): crisp V-creases at sub == 4 plus the subtle Opel centre spine crease
	along x = 0 (sub == 7)."""
	if s >= S_COWL:
		return 0.0
	env = smoothstep(0.05, 0.14, s) * (1.0 - smoothstep(S_SCUTTLE - 0.04, S_COWL, s))
	if env <= 0.0:
		return 0.0
	# sub 0..7 -> hi_params[1:]: 0: te, 1: te+fr, 2: foot, 3: outer bevel, 4: V-ridge, 5: inner bevel, 6: inner flat, 7: centre spine
	prof = (0.0, 0.0, -0.0018, 0.0055, 0.0115, 0.0082, 0.0068, 0.0135)
	return prof[sub] * env


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
	C = Vector((w - 0.032, zb + 0.056))
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
	base = te + fr
	uniform = [base + (1.0 - base) * k / 6.0 for k in range(1, 7)]
	if s < S_COWL:
		tc = bonnet_crease_t(s)
		foot = max(base + 0.025, tc - 0.045)
		in_b = tc + 0.028
		creased = [foot, tc - 0.020, tc, in_b, lerp(in_b, 1.0, 0.72), 1.0]
		w = 1.0 - smoothstep(S_SCUTTLE, S_COWL, s)
		rest = [lerp(u, c, w) for u, c in zip(uniform, creased)]
	else:
		rest = uniform
	return [0.0, te, base] + rest


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
			p = cr(p0, p1, p2, p3, t) if t < 1.0 else p2.copy()
			if seg == SEG_HI:
				p.y += bonnet_crease_dz(s, sub)
			pts.append(p)
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
		if S_SAIL <= s <= S_A2_0 or S_A2_1 <= s <= S_B0 or S_B1 <= s <= S_C0 or S_C1 <= s <= S_Q1:
			return "Glass"
		if S_A2_0 < s < S_A2_1 or S_B0 < s < S_B1 or S_C0 < s < S_C1:
			return "Trim"
		if S_COWL <= s <= S_SAIL:
			return "Trim"
		return "Paint"
	if seg == SEG_GH:
		return "Trim" if (S_B0 < s < S_B1 or S_C0 < s < S_C1) else "Paint"
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
	forced = [
		0.0, LENGTH, S_SCUTTLE, S_COWL, S_COWL + FRIT, S_WS_TOP - FRIT, S_WS_TOP, S_SAIL, S_A2_0, S_A2_1,
		S_B0, S_B1, S_C0, S_C1, S_QR, S_Q1, S_DECK, S_RG0, S_RG0 + FRIT, S_RG1 - FRIT, S_RG1,
	]
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
	"Bumper": ((0.068, 0.070, 0.074), 0.62, 0.0, {}),
	"Grille": ((0.01, 0.01, 0.01), 0.7, 0.0, {}),
	"Chrome": ((0.85, 0.86, 0.88), 0.12, 1.0, {}),
	"Exhaust": ((0.75, 0.76, 0.78), 0.16, 0.95, {}),
	"Headlight": ((0.32, 0.33, 0.34), 0.08, 0.9, {"emit": ((1.0, 0.95, 0.84), 0.2)}),
	"Indicator": ((1.0, 0.42, 0.04), 0.1, 0.0, {"emit": ((1.0, 0.35, 0.02), 0.7)}),
	"Taillight": ((0.42, 0.01, 0.015), 0.08, 0.0, {"emit": ((1.0, 0.05, 0.03), 0.15)}),
	"LampClear": ((0.88, 0.88, 0.90), 0.06, 0.0, {}),
	"LampBezel": ((0.16, 0.17, 0.18), 0.24, 0.82, {}),
	"Fog": ((0.70, 0.72, 0.74), 0.08, 0.6, {"emit": ((1.0, 0.95, 0.84), 0.1)}),
	"Plate": ((0.94, 0.93, 0.89), 0.45, 0.0, {}),
	"Seat": ((0.03, 0.03, 0.035), 0.9, 0.0, {}),
	"Fabric": ((0.10, 0.10, 0.105), 0.95, 0.0, {}),
	"Tyre": ((0.03, 0.03, 0.03), 0.8, 0.0, {}),
	"Sidewall": ((0.085, 0.085, 0.085), 0.7, 0.0, {}),
	"Rim": ((0.74, 0.75, 0.78), 0.2, 0.92, {}),
	"Steel": ((0.36, 0.37, 0.38), 0.42, 0.5, {}),
	"BrakeDisc": ((0.20, 0.19, 0.19), 0.5, 0.7, {}),
	"RoofRail": ((0.032, 0.034, 0.038), 0.38, 0.15, {}),  # satin black roof rails (2005 Zafira B)
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
			# crisp door panel shut lines
			if groove and SEG_ROWS[0] + 1 <= j <= sum(SEG_ROWS[:SEG_EF]):
				x -= 0.0025
				col = 0.08
			# bonnet side shut lines along the wing tops
			if 0.12 < s < S_COWL - 0.015 and j == sum(SEG_ROWS[:SEG_FG]):
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

	# rolled wheel-arch lips and crisp Opel shoulder character line along the flanks
	for v in mb.v:
		ax = abs(v.x)
		if ax < 0.45 or v.z < 0.18:
			continue
		s = Y0 - v.y
		for sc in (FRONT_AXLE_S, REAR_AXLE_S):
			d = math.hypot(s - sc, v.z - TYRE_R)
			if d < ARCH_R + 0.035:
				v.x += math.copysign(0.008 * (1.0 - smoothstep(ARCH_R + 0.012, ARCH_R + 0.035, d))
					* (1.0 - smoothstep(0.92, 1.02, v.z)), v.x)
		# crisp horizontal-rising Opel shoulder swage line from front arch to tail lamp corner
		if 1.15 < s < 4.20 and ax > 0.76:
			zc = lerp(0.88, 0.99, (s - 1.15) / 3.05)
			dz = abs(v.z - zc)
			if dz < 0.055:
				v.x += math.copysign(0.0055 * (1.0 - smoothstep(0.0, 0.055, dz))
					* smoothstep(1.15, 1.38, s) * (1.0 - smoothstep(4.00, 4.20, s)), v.x)

	# body-coloured door mirrors mounted cleanly on the front door shoulder behind the A-pillar quarter window, plus body-coloured pull handles
	for side in (1, -1):
		mb.box(bl(side * 0.865, 1.56, 1.045), (0.068, 0.088, 0.042), "Trim")
		mb.blob(bl(side * 0.942, 1.60, 1.095), (0.068, 0.052, 0.060), "Paint", e=0.5)
		mb.blob(bl(side * 0.942, 1.648, 1.095), (0.058, 0.006, 0.048), "Chrome", e=0.35)
		# body-coloured pull handles along the rising swage line
		for hs, hz in ((2.12, 0.925), (3.12, 0.960)):
			x = W(hs) - 0.014
			mb.blob(bl(side * (x + 0.005), hs, hz), (0.010, 0.076, 0.016), "Paint", e=0.4)
	return mb


def build_rails(body):
	"""Low-profile satin black roof rails hugging the long MPV roof contour (roof crown 1.616 m, rail top 1.635 m)."""
	pj = Projector(body)
	mb = MB()
	for side in (1, -1):
		pts = []
		for k in range(25):
			s = lerp(2.22, 3.96, k / 24)
			loc = pj.hit(bl(side * 0.580, s, 3.0), Vector((0, 0, -1)))[0]
			pts.append(loc)
		top = 1.635 - 0.009  # rail radius 0.009 -> top surface right at 1.635 m
		rail = []
		for k, p in enumerate(pts):
			s_cur = Y0 - p.y
			end_drop = 0.015 * (1.0 - smoothstep(2.22, 2.52, s_cur)) + 0.015 * smoothstep(3.66, 3.96, s_cur)
			rz = min(top, p.z + 0.038) - end_drop
			rail.append(Vector((p.x, p.y, max(p.z + 0.008, rz))))
		for a, b in zip(rail, rail[1:]):
			mb.tube(a, b, 0.009, "RoofRail", segs=8, caps=False)
		# Sleek swept-down end caps merging into the roof channels
		mb.tube(pts[0] + Vector((0, 0.055, -0.004)), rail[0], 0.009, "RoofRail", segs=8)
		mb.tube(rail[-1], pts[-1] + Vector((0, -0.055, -0.004)), 0.009, "RoofRail", segs=8)
		for k in (1, 12, 23):
			p = pts[k]
			h = max(0.010, rail[k].z - p.z + 0.004)
			mb.box(Vector((p.x, p.y, (p.z + rail[k].z) / 2 - 0.003)), (0.020, 0.058, h), "Trim")
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
		if s < 0.90 or c.z < 0.2:
			continue
		ids = []
		for i in f:
			if i not in remap:
				remap[i] = mb.vert(body.v[i] - normals[i] * 0.018)
			ids.append(remap[i])
		mb.face(list(reversed(ids)), "Interior")
	return mb


# ---------------------------------------------------------------- projections
def side_proj(side):
	def f(u, v):
		return bl(side * 2.0, u, v), Vector((-side, 0.0, 0.0))
	return f


def cyl_proj(as_, rear):
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


# ---------------------------------------------------------------- geometry helpers
def dense(pts, step=0.03):
	out = []
	for i, a in enumerate(pts):
		b = pts[(i + 1) % len(pts)]
		n = max(1, int(math.hypot(b[0] - a[0], b[1] - a[1]) / step))
		out += [(lerp(a[0], b[0], k / n), lerp(a[1], b[1], k / n)) for k in range(n)]
	return out


def inset(poly, d):
	cu = sum(p[0] for p in poly) / len(poly)
	cv = sum(p[1] for p in poly) / len(poly)
	out = []
	for u, v in poly:
		l = math.hypot(u - cu, v - cv) or 1.0
		out.append((u + (cu - u) / l * d, v + (cv - v) / l * d))
	return out


def reflector(mb, pj, proj, u, v, r):
	"""A headlamp reflector bowl with depth, seated cleanly in front of the sloped bezel."""
	loc, n_surf = pj.hit(*proj(u, v))
	n = (n_surf * 2.2 + Vector((0.0, 1.0, 0.0))).normalized()
	helper = Vector((1, 0, 0)) if abs(n.x) < 0.9 else Vector((0, 1, 0))
	bx = n.cross(helper).normalized()
	by = n.cross(bx)
	tilt = n_surf.cross(n).length
	base = loc + n_surf * (0.0125 + r * tilt + 0.0015)
	segs = 28
	prof = [(r, 0.0115), (r * 0.95, 0.0092), (r * 0.80, 0.0058), (r * 0.60, 0.0030), (r * 0.38, 0.0014), (r * 0.26, 0.0006)]
	rows = [[base + n * d + (bx * math.cos(2 * math.pi * k / segs) + by * math.sin(2 * math.pi * k / segs)) * rr
		for k in range(segs)] for rr, d in prof]
	mb.grid(rows[:2], "Chrome", closed=True, out=n)
	mb.grid(rows[1:], "Headlight", closed=True, out=n)
	mb.disc(base + n * 0.0006, r * 0.26, "Headlight", normal=n, segs=segs)
	mb.ring(base + n * 0.0118, r * 0.94, r * 1.10, "Chrome", normal=n, segs=segs)


def patch_uv(mb, pj, proj, u0, u1, v0_fn, v1_fn, off_fn, mat, nu=22, nv=8, bulge=0.0, skirt_fn=0.0):
	"""A regular (nu+1) x (nv+1) projected patch over u in [u0, u1] and v in [v0_fn(u), v1_fn(u)], with optional dome
	bulge and perimeter skirt oriented outward from each boundary edge."""
	pts, nors = [], []
	for i in range(nu + 1):
		tu = i / nu
		u = lerp(u0, u1, tu)
		va, vb = v0_fn(u), v1_fn(u)
		row, nrow = [], []
		for j in range(nv + 1):
			tv = j / nv
			v = lerp(va, vb, tv)
			loc, nor = pj.hit(*proj(u, v))
			o = off_fn(u, v) if callable(off_fn) else off_fn
			if bulge:
				b = bulge(u, v) if callable(bulge) else bulge
				o += b * math.sin(math.pi * tu) * math.sin(math.pi * tv)
			row.append(loc + nor * o)
			nrow.append(nor)
		pts.append(row)
		nors.append(nrow)
	ids = [[mb.vert(p) for p in row] for row in pts]
	for i in range(nu):
		for j in range(nv):
			ref = nors[i][j] + nors[i + 1][j] + nors[i + 1][j + 1] + nors[i][j + 1]
			mb.face([ids[i][j], ids[i + 1][j], ids[i + 1][j + 1], ids[i][j + 1]], mat, ref)
	if skirt_fn:
		perim = ([(i, 0, i, 1) for i in range(nu)]
			+ [(nu, j, nu - 1, j) for j in range(nv)]
			+ [(i, nv, i, nv - 1) for i in range(nu, 0, -1)]
			+ [(0, j, 1, j) for j in range(nv, 0, -1)])
		low = []
		for i, j, _, _ in perim:
			tu = i / nu
			u = lerp(u0, u1, tu)
			v = lerp(v0_fn(u), v1_fn(u), j / nv)
			sk = skirt_fn(u, v) if callable(skirt_fn) else skirt_fn
			low.append(mb.vert(pts[i][j] - nors[i][j] * sk))
		for k in range(len(perim)):
			k2 = (k + 1) % len(perim)
			i1, j1, ii1, jj1 = perim[k]
			i2, j2, ii2, jj2 = perim[k2]
			out_dir = (pts[i1][j1] - pts[ii1][jj1]) + (pts[i2][j2] - pts[ii2][jj2])
			mb.face([ids[i1][j1], low[k], low[k2], ids[i2][j2]], mat, out_dir)


def patch_vu(mb, pj, proj, v0, v1, u0_fn, u1_fn, off_fn, mat, nu=14, nv=10, bulge=0.0, skirt_fn=0.0):
	"""A regular (nv+1) x (nu+1) projected patch over v in [v0, v1] and u in [u0_fn(v), u1_fn(v)], so horizontal bands
	(tail lamp red/clear/amber sections) have exact, parallel rows around curved corners."""
	pts, nors = [], []
	for j in range(nv + 1):
		tv = j / nv
		v = lerp(v0, v1, tv)
		ua, ub = u0_fn(v), u1_fn(v)
		row, nrow = [], []
		for i in range(nu + 1):
			tu = i / nu
			u = lerp(ua, ub, tu)
			loc, nor = pj.hit(*proj(u, v))
			o = off_fn(u, v) if callable(off_fn) else off_fn
			if bulge:
				b = bulge(u, v) if callable(bulge) else bulge
				o += b * math.sin(math.pi * tu) * math.sin(math.pi * tv)
			row.append(loc + nor * o)
			nrow.append(nor)
		pts.append(row)
		nors.append(nrow)
	ids = [[mb.vert(p) for p in row] for row in pts]
	for j in range(nv):
		for i in range(nu):
			ref = nors[j][i] + nors[j][i + 1] + nors[j + 1][i + 1] + nors[j + 1][i]
			mb.face([ids[j][i], ids[j][i + 1], ids[j + 1][i + 1], ids[j + 1][i]], mat, ref)
	if skirt_fn:
		perim = ([(i, 0, i, 1) for i in range(nu)]
			+ [(nu, j, nu - 1, j) for j in range(nv)]
			+ [(i, nv, i, nv - 1) for i in range(nu, 0, -1)]
			+ [(0, j, 1, j) for j in range(nv, 0, -1)])
		low = []
		for i, j, _, _ in perim:
			v = lerp(v0, v1, j / nv)
			u = lerp(u0_fn(v), u1_fn(v), i / nu)
			sk = skirt_fn(u, v) if callable(skirt_fn) else skirt_fn
			low.append(mb.vert(pts[j][i] - nors[j][i] * sk))
		for k in range(len(perim)):
			k2 = (k + 1) % len(perim)
			i1, j1, ii1, jj1 = perim[k]
			i2, j2, ii2, jj2 = perim[k2]
			out_dir = (pts[j1][i1] - pts[jj1][ii1]) + (pts[j2][i2] - pts[jj2][ii2])
			mb.face([ids[j1][i1], low[k], low[k2], ids[j2][i2]], mat, out_dir)


def wrap_limit(pj, proj, sc, front, v, gap=0.004):
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
	lim = [wrap_limit(pj, proj, sc, front, v) * reach for v in vs]
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
			ref = nors[i][j] + nors[i + 1][j] + nors[i + 1][j + 1] + nors[i][j + 1]
			mb.face([ids[i][j], ids[i + 1][j], ids[i + 1][j + 1], ids[i][j + 1]], mat, ref)
	for i, k in ((0, 1), (len(ts) - 1, len(ts) - 2)):
		inner = [pts[i][j] - nors[i][j] * 0.006 for j in range(len(vs))]
		ref = pts[i][len(vs) // 2] - pts[k][len(vs) // 2]
		mb.poly(pts[i] + list(reversed(inner)), mat, ref)
	return pts


def opel_badge(pj, mb, proj, cu, cv, r, base_off, flip=1.0):
	"""Circular Opel Blitz (lightning bolt) emblem: chrome outer ring, dark recess, and horizontal chrome Z-bolt
	crossing the circle cleanly."""
	pj.star(mb, ellipse(cu, cv, r + 0.0035, r + 0.0035, 28), proj, "Gasket", offset=base_off, rings=2, samples=1, skirt=0.003)
	pj.star(mb, ellipse(cu, cv, r, r, 28), proj, "Chrome", offset=base_off + 0.0022, rings=2, samples=1, skirt=0.002)
	pj.star(mb, ellipse(cu, cv, r * 0.80, r * 0.80, 28), proj, "Trim", offset=base_off + 0.0036, rings=2, samples=1, skirt=0.0)
	# Opel Blitz lightning bolt: upper right-to-centre bar, angled drop, lower centre-to-left bar extending past the ring
	s = flip
	bolt_upper = [
		(cu - s * r * 1.18, cv + r * 0.06), (cu + s * r * 0.34, cv + r * 0.24),
		(cu + s * r * 0.24, cv + r * 0.02), (cu - s * r * 1.12, cv - r * 0.04),
	]
	bolt_lower = [
		(cu - s * r * 0.24, cv - r * 0.02), (cu + s * r * 1.12, cv + r * 0.04),
		(cu + s * r * 1.18, cv - r * 0.06), (cu - s * r * 0.34, cv - r * 0.24),
	]
	bolt_mid = [
		(cu - s * r * 0.30, cv - r * 0.16), (cu + s * r * 0.30, cv + r * 0.16),
		(cu + s * r * 0.20, cv + r * 0.24), (cu - s * r * 0.20, cv - r * 0.24),
	]
	for poly in (bolt_upper, bolt_lower, bolt_mid):
		pj.star(mb, dense(poly, 0.012), proj, "Chrome", offset=base_off + 0.0054, rings=1, samples=1, skirt=0.0012)


# ---------------------------------------------------------------- lamps, grilles, bumper plastics
FB_AXIS = 0.56
HL_AXIS = 0.78  # headlamp wrap axis: rays from 24 to 82 deg sweep smoothly from beside the trapezoid grille up the wing
RB_AXIS = LENGTH - 0.54

# 2005 Opel Zafira B triangular/wedge swept-up headlamps (cyl_proj around HL_AXIS):
# crisp inboard edge angled cleanly beside the trapezoid grille, sweeping sharply up and back along the wing
# to a sleek wedge point at 82 deg.
HL_U0, HL_U1 = 24.0, 82.0
HL_TOP = Curve([
	(24.0, 0.746), (27.0, 0.755), (35.0, 0.776), (47.0, 0.808), (59.0, 0.840), (69.0, 0.868),
	(76.5, 0.884), (80.5, 0.888), (82.0, 0.884),
])
HL_BOT = Curve([
	(24.0, 0.625), (27.0, 0.622), (36.0, 0.626), (48.0, 0.650), (60.0, 0.696), (70.0, 0.760),
	(77.0, 0.826), (80.5, 0.866), (82.0, 0.876),
])

# Classic 2005 Opel Zafira B trapezoid upper grille (wider at top under bonnet, tapering inward at bottom)
UPPER_GRILLE = [
	(-0.314, 0.748), (0.314, 0.748), (0.305, 0.722), (0.268, 0.618),
	(-0.268, 0.618), (-0.305, 0.722),
]
# Wide trapezoidal lower grille below the front number plate
LOWER_GRILLE = [
	(-0.365, 0.402), (0.365, 0.402), (0.435, 0.362), (0.455, 0.296),
	(0.415, 0.268), (-0.415, 0.268), (-0.455, 0.296), (-0.435, 0.362),
]

# Tall vertical wrap-around red/clear tail lamps flanking the rear glass (cyl_proj around RB_AXIS):
# straight vertical inner edge hugging the tailgate & rear screen, crisp chamfered upper corner, wide lower shoulder.
TL_Z0, TL_Z1 = 0.735, 1.225
TL_IN = Curve([
	(0.735, 44.2), (0.850, 44.5), (0.960, 44.8), (1.060, 45.8), (1.140, 47.4),
	(1.195, 49.4), (1.218, 51.4), (1.225, 53.0),
])
TL_OUT = Curve([
	(0.735, 62.5), (0.810, 64.0), (0.940, 64.2), (1.050, 63.2), (1.135, 61.4),
	(1.190, 59.0), (1.216, 56.4), (1.225, 54.4),
])


def build_plastics(pj, mb):
	"""2005 Opel Zafira B nose and tail plastics: trapezoid upper grille with thick horizontal chrome bar and circular
	Opel lightning-bolt emblem, body-coloured bumper beam with plate, wide trapezoidal lower intake, round corner fog
	lamps, chin lip, and rear bumper lower valance."""
	fp = cyl_proj(FB_AXIS, False)

	# Classic 2005 Opel trapezoid upper grille with chrome outer surround, horizontal slats, thick horizontal chrome bar, and Opel Blitz
	pj.star(mb, dense(UPPER_GRILLE, 0.03), front_proj, "Trim", offset=0.0028, rings=1, samples=2, skirt=0.004)
	pj.star(mb, dense(inset(UPPER_GRILLE, 0.010), 0.03), front_proj, "Grille", offset=0.0044, rings=1, samples=2, skirt=0.0)
	for z, hw in ((0.642, 0.265), (0.674, 0.278)):
		pj.strip(mb, -hw, hw, z, z + 0.007, 26, 1, front_proj, "Trim", offset=0.0062)
	# Thick horizontal chrome bar across the upper-middle of the trapezoid grille (signature 2005 Opel grille bar)
	bar = [(-0.302, 0.728), (0.302, 0.728), (0.296, 0.696), (-0.296, 0.696)]
	pj.star(mb, dense(bar, 0.03), front_proj, "Chrome", offset=0.0078, rings=1, samples=2, skirt=0.003)
	opel_badge(pj, mb, front_proj, 0.0, 0.712, 0.044, 0.0088, flip=1.0)

	# Front European number plate (512 x 105 mm) on the body-coloured bumper beam:
	# bottom edge y0_front = 0.440 (matches CarCatalog ZAFIRA_VISUAL plate_y)
	pj.star(mb, rounded_rect(-0.264, 0.264, 0.434, 0.5507, 0.006), front_proj, "Trim", offset=0.0055, rings=1, samples=2, skirt=0.006)
	pj.star(mb, rounded_rect(-0.2559, 0.2559, 0.440, 0.5447, 0.004), front_proj, "Plate", offset=0.0085, rings=1, samples=2, skirt=0.0)

	# Wide trapezoidal lower grille with horizontal slats
	pj.star(mb, dense(LOWER_GRILLE, 0.03), front_proj, "Trim", offset=0.0022, rings=1, samples=2, skirt=0.004)
	pj.star(mb, dense(inset(LOWER_GRILLE, 0.010), 0.03), front_proj, "Grille", offset=0.0038, rings=1, samples=2, skirt=0.0)
	for z, hw in ((0.298, 0.422), (0.332, 0.405), (0.366, 0.380)):
		pj.strip(mb, -hw, hw, z, z + 0.007, 30, 1, front_proj, "Trim", offset=0.0060)

	# Round fog lamps in smooth rounded-rectangle black corner housings flanking the lower grille
	for side in (1, -1):
		hp = lambda u, v, side=side: front_proj(side * u, v)
		pj.star(mb, rounded_rect(0.505, 0.665, 0.282, 0.402, 0.042), hp, "Trim", offset=0.0038, rings=2, samples=2, skirt=0.005)
		pj.star(mb, ellipse(0.585, 0.342, 0.044, 0.044, 22), hp, "Chrome", offset=0.0068, rings=2, samples=1, skirt=0.0)
		pj.star(mb, ellipse(0.585, 0.342, 0.036, 0.036, 22), hp, "Fog", offset=0.0088, bulge=0.003, rings=2, samples=1, skirt=0.0)

	# Subtle black front chin spoiler lip wrapping round to the front arches
	chin_rows = [(0.214, -0.002), (0.222, 0.007), (0.240, 0.009), (0.248, -0.002)]
	wrap_band(pj, mb, fp, FRONT_AXLE_S, True, [r[0] for r in chin_rows], lambda v, rows=chin_rows: profile(v, rows),
		"Bumper", reach=0.92)
	# Bonnet leading shut line cleanly above the trapezoid grille
	pj.strip(mb, -0.320, 0.320, 0.762, 0.767, 26, 1, front_proj, "Gasket", offset=0.0012)

	# Rear lower black bumper valance wrapping round towards the rear arches
	rp = cyl_proj(RB_AXIS, True)
	rows = [(0.298, -0.002), (0.308, 0.008), (0.322, 0.011), (0.378, 0.011), (0.388, 0.006), (0.394, -0.001)]
	vs = sorted(set([r[0] for r in rows] + spread(0.326, 0.376, 0.02)))
	wrap_band(pj, mb, rp, REAR_AXLE_S, False, vs, lambda v, rows=rows: profile(v, rows), "Bumper", reach=0.88)


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
		# Large crisp triangular/wedge swept-up headlamps wrapped around HL_AXIS
		hl_cyl = cyl_proj(HL_AXIS, False)
		hp = lambda u, v, side=side, hl_cyl=hl_cyl: hl_cyl(side * u, v)
		wing_fade = lambda u: 1.0 - smoothstep(50.0, 80.0, u)

		def hl_inset(du_in, du_out, dv):
			u0, u1 = HL_U0 + du_in, HL_U1 - du_out
			def bot(u):
				b, t = HL_BOT(u), HL_TOP(u)
				return min(b + dv, (b + t) * 0.5 - 0.002)
			def top(u):
				b, t = HL_BOT(u), HL_TOP(u)
				return max(t - dv, (b + t) * 0.5 + 0.002)
			return u0, u1, bot, top

		patch_uv(mb, pj, hp, HL_U0, HL_U1, HL_BOT, HL_TOP,
			lambda u, v: lerp(0.003, 0.010, wing_fade(u)), "Gasket", nu=24, nv=8,
			skirt_fn=lambda u, v: lerp(0.006, 0.013, wing_fade(u)))
		bu0, bu1, bbot, btop = hl_inset(0.8, 1.0, 0.005)
		patch_uv(mb, pj, hp, bu0, bu1, bbot, btop,
			lambda u, v: lerp(0.0045, 0.0115, wing_fade(u)), "LampBezel", nu=24, nv=8)
		# Crisp amber turn-signal indicator tucked in the upper-outer wedge corner
		iu0, iu1 = 59.0, 78.5
		def ind_span(u):
			t = min(1.0, max(0.0, (u - iu0) / (iu1 - iu0)))
			w = math.sin(math.pi * t) ** 0.5
			b, tp_ = HL_BOT(u), HL_TOP(u)
			mid = lerp(b, tp_, 0.56)
			half = max(0.002, (tp_ - b) * 0.27 * w)
			return mid - half, mid + half
		patch_uv(mb, pj, hp, iu0, iu1,
			lambda u: ind_span(u)[0],
			lambda u: ind_span(u)[1],
			lambda u, v: lerp(0.0065, 0.015, wing_fade(u)), "Indicator", nu=10, nv=5, bulge=0.0020)
		# Twin bright chrome-rimmed 3D reflector bowls seated fully behind the domed LampGlass
		reflector(mb, pj, hp, 31.5, 0.690, 0.044)
		reflector(mb, pj, hp, 44.5, 0.722, 0.050)
		gu0, gu1, gbot, gtop = hl_inset(0.4, 0.5, 0.0025)
		patch_uv(mb, pj, hp, gu0, gu1, gbot, gtop,
			lambda u, v: lerp(0.0095, 0.040, wing_fade(u)), "LampGlass", nu=24, nv=8,
			bulge=lambda u, v: lerp(0.002, 0.012, wing_fade(u)),
			skirt_fn=lambda u, v: lerp(0.007, 0.028, wing_fade(u)))

		# Tall vertical wrap-around red/clear tail lamps flanking the rear glass (cylindrical patch_vu)
		tl_cyl = cyl_proj(RB_AXIS, True)
		tp = lambda u, v, side=side, tl_cyl=tl_cyl: tl_cyl(side * u, v)

		def tl_u(du_in, du_out):
			def u0(z):
				a, b = TL_IN(z), TL_OUT(z)
				return min(a + du_in, (a + b) * 0.5 - 0.15)
			def u1(z):
				a, b = TL_IN(z), TL_OUT(z)
				return max(b - du_out, (a + b) * 0.5 + 0.15)
			return u0, u1

		patch_vu(mb, pj, tp, TL_Z0, TL_Z1, TL_IN, TL_OUT, 0.004, "Gasket", nu=14, nv=22, skirt_fn=0.008)
		lu0, lu1 = tl_u(0.55, 0.60)
		bu0, bu1 = tl_u(2.1, 2.3)
		# Upper red tail/brake section + lower red tail/fog section
		for z0, z1, nv in ((1.012, 1.218, 10), (0.741, 0.930, 7)):
			patch_vu(mb, pj, tp, z0, z1, lu0, lu1, 0.0095, "Taillight", nu=14, nv=nv)
			patch_vu(mb, pj, tp, z0 + 0.016, z1 - 0.016, bu0, bu1, 0.0112, "TailBulb", nu=10, nv=max(3, nv - 2))
			patch_vu(mb, pj, tp, z0, z1, lu0, lu1, 0.0150, "TailGlass", nu=14, nv=nv, bulge=0.0022, skirt_fn=0.011)
		# Iconic 2005 Zafira B sleek crystal-clear / amber middle band across the red tail lamp
		patch_vu(mb, pj, tp, 0.974, 1.008, lu0, lu1, 0.0115, "Indicator", nu=14, nv=4)
		patch_vu(mb, pj, tp, 0.934, 0.970, lu0, lu1, 0.0115, "LampClear", nu=14, nv=4)
		patch_vu(mb, pj, tp, 0.932, 1.010, lu0, lu1, 0.0155, "LampGlass", nu=14, nv=6, bulge=0.0020, skirt_fn=0.0115)
		# Lower rear bumper reflectors
		rp_flat = lambda u, v, side=side: rear_proj(side * u, v)
		pj.star(mb, rounded_rect(0.56, 0.70, 0.435, 0.456, 0.008), rp_flat, "Taillight", offset=0.006, rings=1, samples=2, skirt=0.0)

		pj = pj_all
		sp = side_proj(side)
		# Front wing side repeater behind front wheel arch
		pj.star(mb, ellipse(1.25, 0.84, 0.025, 0.010, 12), sp, "Gasket", offset=0.002, rings=1, samples=2)
		pj.star(mb, ellipse(1.25, 0.84, 0.019, 0.007, 12), sp, "Indicator", offset=0.004, bulge=0.002, rings=2, samples=2)
		# Dark recesses behind pull handles + front door lock barrel
		for hs, hz in ((2.12, 0.925), (3.12, 0.960)):
			pj.star(mb, rounded_rect(hs - 0.070, hs + 0.070, hz - 0.023, hz + 0.010, 0.011), sp, "Gasket", offset=0.0012,
				rings=1, samples=2)
		pj.star(mb, ellipse(2.12 + 0.090, 0.925, 0.0085, 0.0085, 10), sp, "Chrome", offset=0.004, rings=1, samples=1)
		# Subtle black lower rocker sill edge (cleanly between wheel arches)
		pj.band(mb, spread(1.36, 3.14, 0.05, [S_DOOR[1]]), [0.205, 0.222, 0.238],
			lambda u, v: 0.0035 if 0.215 < v < 0.230 else 0.0, lambda u, v: "Bumper", sp)

		# Closed wheel-well liners
		for sc in (FRONT_AXLE_S, REAR_AXLE_S):
			rows = []
			for xo in (0.50, 0.79):
				row = []
				for k in range(21):
					a = math.radians(-12 + 204 * k / 20)
					row.append(bl(side * xo, sc - (ARCH_R - 0.006) * math.cos(a), TYRE_R + (ARCH_R - 0.006) * math.sin(a)))
				rows.append(row)
			mb.grid(rows, "Under", out=lambda q, sc=sc: Vector((0, (Y0 - sc) - q.y, TYRE_R - q.z)))
			c = bl(side * 0.50, sc, TYRE_R)
			arc = rows[0]
			for k in range(len(arc) - 1):
				mb.poly([c, arc[k], arc[k + 1]], "Under", Vector((side, 0, 0)))

	# Fuel flap on the right rear quarter panel above the rear wheel arch
	spr = side_proj(1)
	for u0, u1, v0, v1, nu, nv in (
		(3.84, 3.98, 0.875, 0.880, 8, 1), (3.84, 3.98, 0.985, 0.990, 8, 1),
		(3.837, 3.842, 0.875, 0.990, 1, 6), (3.978, 3.983, 0.875, 0.990, 1, 6),
	):
		pj.strip(mb, u0, u1, v0, v1, nu, nv, spr, "Gasket", offset=0.0010)

	# Rear tailgate: horizontal chrome trim bar below the rear screen, Opel Blitz emblem, recessed plate, OPEL / ZAFIRA lettering
	# Chrome tailgate trim bar spanning cleanly between the vertical tail lamps
	pj.star(mb, rounded_rect(-0.545, 0.545, 1.008, 1.044, 0.008), rear_proj, "Gasket", offset=0.0022, rings=1, samples=2, skirt=0.002)
	pj.star(mb, rounded_rect(-0.538, 0.538, 1.013, 1.039, 0.006), rear_proj, "Chrome", offset=0.0045, rings=1, samples=2, skirt=0.002)
	# Circular Opel Blitz emblem centred right over the chrome trim bar
	opel_badge(pj, mb, rear_proj, 0.0, 1.026, 0.044, 0.0060, flip=-1.0)
	# Recessed licence plate on the tailgate (y0_rear = 0.695 -> matches CarCatalog ZAFIRA_VISUAL plate_y)
	pj.star(mb, rounded_rect(-0.270, 0.270, 0.688, 0.808, 0.010), rear_proj, "Gasket", offset=0.0018, rings=1, samples=2, skirt=0.0)
	pj.star(mb, rounded_rect(-0.264, 0.264, 0.691, 0.805, 0.006), rear_proj, "Trim", offset=0.0032, rings=1, samples=2, skirt=0.0)
	pj.star(mb, rounded_rect(-0.2559, 0.2559, 0.695, 0.7997, 0.004), rear_proj, "Plate", offset=0.0055, rings=1, samples=2, skirt=0.0)
	# OPEL and ZAFIRA chrome badges on the lower tailgate flanks
	text_decal(pj, mb, rear_proj, "OPEL", -0.394, 0.905 - 0.003, 0.118, "Gasket", 0.0030, 1)
	text_decal(pj, mb, rear_proj, "OPEL", -0.398, 0.905, 0.118, "Chrome", 0.0052, 1)
	text_decal(pj, mb, rear_proj, "ZAFIRA", 0.394, 0.905 - 0.003, 0.155, "Gasket", 0.0030, 1)
	text_decal(pj, mb, rear_proj, "ZAFIRA", 0.390, 0.905, 0.155, "Chrome", 0.0052, 1)
	# Tailgate shut lines beside the tail lamps and along the bumper top
	for x in (-0.562, 0.562):
		pj.strip(mb, x + 0.003, x - 0.003, 0.618, 1.070, 1, 20, rear_proj, "Gasket", offset=0.0020)
	pj.strip(mb, -0.562, 0.562, 0.615, 0.621, 32, 1, rear_proj, "Gasket", offset=0.0018)
	pj.strip(mb, S_DECK - 0.003, S_DECK + 0.003, -0.59, 0.59, 1, 38, top_proj, "Gasket", offset=0.0012)
	# High-mounted third brake lamp in the subtle roof spoiler lip above the rear glass
	pj.strip(mb, -0.52, 0.52, 1.536, 1.564, 36, 1, rear_proj, "Trim", offset=0.0058)
	pj.strip(mb, -0.145, 0.145, 1.543, 1.557, 12, 1, rear_proj, "Taillight", offset=0.0085)
	# Rear wiper parked at the base of the rear screen
	base_p = pj.hit(*rear_proj(0.0, 1.132))[0]
	mb.blob(base_p + Vector((0, -0.012, 0)), (0.020, 0.015, 0.020), "Trim", e=0.3)
	tip = pj.hit(*rear_proj(0.38, 1.158))[0]
	mb.tube(base_p + Vector((0, -0.016, 0.004)), tip + Vector((0, -0.010, 0)), 0.0058, "Trim", segs=6)

	# Scuttle washer jets and front wipers
	for x in (-0.30, 0.30):
		pj.star(mb, ellipse(S_SCUTTLE + 0.02, x, 0.012, 0.008, 8), top_proj, "Trim", offset=0.004, rings=1, samples=1)
	for xp, x1 in ((-0.54, 0.00), (0.06, 0.62)):
		base_p = pj.hit(*top_proj(S_SCUTTLE + 0.05, xp))[0]
		mb.blob(base_p + Vector((0, 0, 0.010)), (0.018, 0.018, 0.014), "Trim", e=0.3)
		a = base_p + Vector((0, 0, 0.018))
		b = pj.hit(*top_proj(S_SCUTTLE + 0.21, x1))[0] + Vector((0, 0, 0.016))
		mb.tube(a, b, 0.0058, "Trim", segs=6)
		bx0 = pj.hit(*top_proj(S_SCUTTLE + 0.19, xp + 0.04))[0] + Vector((0, 0, 0.012))
		bx1 = pj.hit(*top_proj(S_SCUTTLE + 0.24, x1 + 0.02))[0] + Vector((0, 0, 0.012))
		mb.box((bx0 + bx1) / 2, ((bx1 - bx0).length, 0.012, 0.012), "Trim",
			basis=Matrix.Rotation(math.atan2(bx1.y - bx0.y, bx1.x - bx0.x), 3, "Z"))

	# Short roof aerial at the rear of the roof
	base = pj.hit(*top_proj(3.88, 0.0))[0]
	mb.blob(base + Vector((0, 0, 0.010)), (0.019, 0.032, 0.013), "Trim", e=0.4)
	mb.tube(base + Vector((0, 0, 0.015)), base + Vector((0, -0.11, 0.16)), 0.0038, "Trim", segs=6)

	# Single exhaust tailpipe tucked under the left-rear/right-rear valance (placed at right rear +0.40 for uniform FX)
	mb.tube(bl(0.24, 3.92, 0.265), bl(-0.20, 3.92, 0.265), 0.078, "Steel", segs=14)
	mb.tube(bl(0.40, 4.00, 0.258), bl(0.40, LENGTH + 0.005, 0.264), 0.024, "Exhaust", segs=14, caps=False)
	mb.ring(bl(0.40, LENGTH + 0.005, 0.264), 0.020, 0.025, "Exhaust", normal=(0, -1, 0), segs=14)
	mb.disc(bl(0.40, LENGTH - 0.005, 0.264), 0.021, "Under", normal=(0, -1, 0), segs=14)

	# Underbody floor pan and closed engine/load bays
	mb.box(bl(0, 0.88, 0.212), (0.82, 0.78, 0.03), "Steel")
	mb.box(bl(0, 0.78, 0.46), (1.16, 0.96, 0.40), "Under")
	mb.box(bl(0, 4.02, 0.46), (1.16, 0.72, 0.40), "Under")
	mb.box(bl(0, 2.30, 0.222), (0.98, 2.35, 0.07), "Under")

	return mb, pj


def build_cabin():
	"""Tall airy 7-seat MPV cabin silhouette seen through the glass: high-set dashboard with Opel centre stack and
	raised gearshift pod, 3-spoke steering wheel, two front seats, 2nd-row bench (3 headrests), and 3rd-row headrest
	silhouettes visible through the long D-pillar quarter windows."""
	mb = MB()

	def cb(x, s, z):
		return bl(x, s, z)
	# High MPV dashboard and angled centre stack
	mb.blob(cb(0, 1.48, 1.03), (0.68, 0.22, 0.09), "Interior", e=0.3)
	mb.box(cb(0, 1.38, 0.74), (1.42, 0.16, 0.48), "Interior")
	mb.box(cb(0, 1.62, 0.78), (0.28, 0.30, 0.44), "Interior")  # centre stack with high gearshift console
	mb.box(cb(0, 2.00, 0.46), (0.22, 0.74, 0.20), "Interior")
	mb.blob(cb(-0.37, 1.54, 1.15), (0.17, 0.10, 0.06), "Interior", e=0.35)
	mb.disc(cb(-0.37, 1.52, 1.13), 0.054, "Plate", normal=(0, -0.6, 0.8), segs=16)
	# High-mounted MPV gear lever on centre stack
	mb.blob(cb(0, 1.76, 0.78), (0.055, 0.065, 0.04), "Trim", e=0.3)
	mb.tube(cb(0, 1.76, 0.80), cb(0, 1.79, 0.96), 0.0085, "Chrome", segs=8)
	mb.blob(cb(0, 1.79, 0.97), (0.022, 0.022, 0.026), "Seat", e=0.35)
	for px in (-0.46, -0.38, -0.30):
		mb.box(cb(px, 1.44, 0.34), (0.048, 0.012, 0.075), "Steel")
	# Rear-view mirror under the tall windscreen top
	mb.box(cb(0, 1.92, 1.45), (0.13, 0.015, 0.045), "Interior")
	mb.tube(cb(0, 1.93, 1.46), cb(0, 1.95, 1.50), 0.006, "Trim", segs=6)
	# 3-spoke steering wheel
	tilt = math.radians(66)
	n = Vector((0, -math.cos(tilt), math.sin(tilt)))
	u = Vector((1, 0, 0))
	v = n.cross(u)
	sw = cb(-0.37, 1.74, 1.12)
	ring = [sw + (u * math.cos(2 * math.pi * k / 24) + v * math.sin(2 * math.pi * k / 24)) * 0.19 for k in range(24)]
	for k in range(24):
		mb.tube(ring[k], ring[(k + 1) % 24], 0.014, "Seat", segs=8, caps=False)
	mb.tube(sw, sw - v * 0.18, 0.011, "Trim", segs=6)
	mb.tube(sw, sw - u * 0.16 + v * 0.04, 0.011, "Trim", segs=6)
	mb.tube(sw, sw + u * 0.16 + v * 0.04, 0.011, "Trim", segs=6)
	mb.disc(sw, 0.044, "Interior", normal=n, segs=14)
	mb.disc(sw + n * 0.003, 0.025, "Chrome", normal=n, segs=12)
	mb.tube(sw, sw + Vector((0, 0.26, -0.10)), 0.021, "Trim", segs=8)
	# Row 1: two tall upright MPV front seats
	lean = Matrix.Rotation(math.radians(-10), 3, "X")
	for sx in (-0.37, 0.37):
		mb.blob(cb(sx, 2.15, 0.56), (0.23, 0.25, 0.09), "Fabric", e=0.40)
		mb.blob(cb(sx, 2.36, 0.95), (0.24, 0.08, 0.38), "Fabric", e=0.45, basis=lean)
		mb.blob(cb(sx, 2.41, 1.35), (0.105, 0.05, 0.095), "Fabric", e=0.4, basis=lean)
		for rx in (-0.19, 0.19):
			mb.box(cb(sx + rx, 2.15, 0.34), (0.025, 0.44, 0.04), "Steel")
	# Row 2: Flex7 sliding middle bench with 3 headrests
	mb.blob(cb(0, 2.94, 0.58), (0.64, 0.22, 0.085), "Fabric", e=0.35)
	mb.blob(cb(0, 3.16, 0.98), (0.66, 0.07, 0.36), "Fabric", e=0.40)
	for hx in (-0.38, 0.0, 0.38):
		mb.blob(cb(hx, 3.18, 1.35), (0.098, 0.04, 0.085), "Fabric", e=0.4)
	# Row 3: Flex7 twin 3rd-row rear seats + headrests visible through the D-pillar glass
	mb.blob(cb(0, 3.68, 0.56), (0.54, 0.19, 0.075), "Fabric", e=0.35)
	mb.blob(cb(0, 3.88, 0.95), (0.56, 0.065, 0.33), "Fabric", e=0.40)
	for hx in (-0.28, 0.28):
		mb.blob(cb(hx, 3.90, 1.29), (0.090, 0.038, 0.078), "Fabric", e=0.4)
	return mb


def build_stripes(pj):
	mb = MB()
	for x in (-0.16, 0.16):
		pj.strip(mb, 0.15, S_SCUTTLE - 0.01, x - 0.07, x + 0.07, 36, 2, top_proj, "Stripe", offset=0.0018)
		pj.strip(mb, S_WS_TOP + 0.02, S_DECK - 0.03, x - 0.07, x + 0.07, 48, 2, top_proj, "Stripe", offset=0.0018)
	return mb


MARTINI_STRIPES = (
	(-0.20, -0.15, "MartiniDark"), (-0.15, -0.10, "MartiniLight"), (-0.10, 0.10, "MartiniRed"),
	(0.10, 0.15, "MartiniLight"), (0.15, 0.20, "MartiniDark"),
)


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
		pj.strip(mb, 0.15, S_SCUTTLE - 0.01, x0, x1, 36, 1, top_proj, mat, offset=0.0035)
		pj.strip(mb, S_WS_TOP + 0.02, S_DECK - 0.03, x0, x1, 48, 1, top_proj, mat, offset=0.0035)

	def belt(u):
		return 0.78 + 0.04 * smoothstep(1.38, 3.18, u)
	us = [lerp(1.38, 3.18, i / 90) for i in range(91)]
	vs = [-0.075, -0.050, -0.025, 0.045]
	for side in (1, -1):
		sp = side_proj(side)
		pj.band(mb, us, vs, lambda u, v: 0.0045, lambda u, v: "MartiniDark" if v < -0.04 else "MartiniLight" if v < -0.01 else "MartiniRed",
			lambda u, v, sp=sp: sp(u, v + belt(u)))
		martini_roundel(pj, mb, sp, 1.96, 0.650, 0.10, -side)
	martini_roundel(pj, mb, top_proj, 0.64, 0.0, 0.095, 1)
	return mb


def build_abarth(pj):
	mb = MB()
	for side in (1, -1):
		sp = side_proj(side)
		pj.strip(mb, 1.38, 3.16, 0.34, 0.45, 40, 2, sp, "AbarthBlack", offset=0.0035)
		pj.strip(mb, 1.38, 3.16, 0.457, 0.469, 40, 1, sp, "AbarthRed", offset=0.0035)
		text_decal(pj, mb, sp, "ABARTH", 2.27, 0.395, 0.48, "AbarthWhite", 0.0050, -side)

	def plate(pts, mat, off, k=0.14, cu=0.56):
		pj.star(mb, [(cu + x * k, y * k) for x, y in pts], top_proj, mat, offset=off, rings=2, samples=2, skirt=0.0)
	plate([(-0.66, 0.0), (-0.12, 0.56), (0.60, 0.56), (0.60, -0.56), (-0.12, -0.56)], "AbarthWhite", 0.0030)
	plate([(-0.58, 0.0), (-0.10, 0.49), (0.53, 0.49), (0.53, -0.49), (-0.10, -0.49)], "AbarthRed", 0.0036)
	plate([(0.22, 0.49), (0.53, 0.49), (0.53, -0.49), (0.22, -0.49)], "AbarthYellow", 0.0042)
	text_decal(pj, mb, top_proj, "ABARTH", 0.56 + 0.375 * 0.14, 0.0, 0.10, "AbarthBlack", 0.0048, 1)
	return mb


def build_marlboro(pj):
	mb = MB()
	pj.star(mb, [(0.24, -0.48), (0.24, 0.48), (0.98, 0.48), (0.58, 0.0), (0.98, -0.48)], top_proj, "MarlboroRed",
		offset=0.0075, rings=14, samples=16, skirt=0.0)
	for side in (1, -1):
		sp = side_proj(side)
		pj.star(mb, [(1.44, 0.54), (1.44, 0.80), (3.12, 0.80), (2.68, 0.67), (3.12, 0.54)], sp, "MarlboroRed",
			offset=0.005, rings=8, samples=14, skirt=0.0)
		text_decal(pj, mb, sp, "Marlboro", 2.00, 0.67, 0.54, "MarlboroWhite", 0.0065, -side)
	return mb


def dent_delta(key, p):
	"""How far a crash moves the point p (Blender coords) at full damage on one side."""
	s = Y0 - p.y
	d = Vector()
	if key == "front":
		w = smoothstep(1.25, 0.0, s)
		d.y = -0.29 * w ** 1.2 * (1.0 + 0.25 * _nz(p, 0.3))
		d.z = -0.07 * w * (1.0 + _nz(p, 1.1)) + 0.05 * w * w * smoothstep(0.62, 0.84, p.z)
		d.x = 0.05 * w * _nz(p, 2.4)
	elif key == "rear":
		w = smoothstep(LENGTH - 0.95, LENGTH, s)
		d.y = 0.23 * w ** 1.2 * (1.0 + 0.25 * _nz(p, 0.9))
		d.z = -0.05 * w * (1.0 + _nz(p, 2.0))
		d.x = 0.04 * w * _nz(p, 3.1)
	else:
		side = -1.0 if key == "left" else 1.0
		if p.x * side > 0.2:
			g = math.exp(-((s - 2.30) / 0.70) ** 2 - ((p.z - 0.72) / 0.32) ** 2)
			d.x = -side * 0.10 * g * (1.0 + 0.3 * _nz(p, 4.2))
			d.z = -0.02 * g * _nz(p, 5.0)
	return d


def build_wheel():
	"""16" clean 5-spoke Opel alloy (5x110 PCD) with a 205/55 R16 tyre; axle along X, outer face towards +X."""
	mb = MB()
	hw = TYRE_W / 2
	R = TYRE_R
	rim = 0.2032  # 16" bead seat radius
	tyre = [
		(hw - 0.016, rim + 0.005), (hw + 0.002, rim + 0.022), (hw + 0.008, rim + 0.062), (hw + 0.006, R - 0.034),
		(hw - 0.006, R - 0.012), (hw - 0.026, R - 0.0015), (0.040, R), (0.034, R), (0.031, R - 0.008), (0.022, R - 0.008),
		(0.020, R), (-0.020, R), (-0.022, R - 0.008), (-0.031, R - 0.008), (-0.034, R), (-0.040, R), (-hw + 0.026, R - 0.0015),
		(-hw + 0.006, R - 0.012), (-hw - 0.006, R - 0.034), (-hw - 0.008, rim + 0.062), (-hw - 0.002, rim + 0.022),
		(-hw + 0.016, rim + 0.005),
	]

	def tyre_out(c):
		r = math.hypot(c.y, c.z)
		radial = Vector((0, c.y / r, c.z / r))
		return Vector((c.x, 0, 0)) * 2.0 + radial * (r - 0.26)
	mb.lathe(tyre, 56, "Tyre", out=tyre_out)
	for k in range(40):
		a = 2 * math.pi * k / 40
		for x0, x1 in ((0.042, hw - 0.016), (-hw + 0.016, -0.042)):
			pts = [Vector((x, (R + 0.0003) * math.cos(a + da), (R + 0.0003) * math.sin(a + da))) for x, da in
				((x0, 0.0), (x1, 0.034), (x1, 0.050), (x0, 0.016))]
			mb.poly(pts, "Grille", lambda q: Vector((0, q.y, q.z)))
	for k in range(4):
		a0 = 2 * math.pi * k / 4 + 0.25
		rows = []
		for r in (0.236, 0.268):
			rows.append([Vector((hw + 0.0085 - 0.0034 * (r - 0.236) / 0.032, r * math.cos(a0 + 0.8 * j / 8),
				r * math.sin(a0 + 0.8 * j / 8))) for j in range(9)])
		mb.grid(rows, "Sidewall", out=Vector((1, 0, 0)))

	barrel = [
		(hw - 0.004, rim - 0.004), (hw - 0.012, rim - 0.015), (0.062, rim - 0.026), (0.052, rim - 0.040), (0.030, rim - 0.044),
		(-0.04, rim - 0.044), (-0.055, rim - 0.034),
	]
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
			sect = [(-w / 2, 0.0), (w / 2, 0.0), (w / 2, h * 0.62), (w * 0.36, h), (-w * 0.36, h), (-w / 2, h * 0.62)]
			rows.append([Vector((xb + hh, 0, 0)) + c + t * ww for ww, hh in sect])

		def outward(q):
			v = Vector((q.x - (base0 + h0 / 2), q.y - p0.y, q.z - p0.z))
			return v - Vector((0, d.y, d.z)) * (v.y * d.y + v.z * d.z)
		mb.grid(rows, "Rim", closed=True, out=outward, cap_ends=True)

	# 5 clean broad tapered Opel alloy spokes with subtle central rib chamfer
	for k in range(5):
		a = 2 * math.pi * k / 5 + 0.3
		ca, sa = math.cos(a), math.sin(a)
		p_hub = Vector((0, 0.054 * ca, 0.054 * sa))
		p_end = Vector((0, 0.190 * ca, 0.190 * sa))
		bar(p_hub, p_end, 0.048, 0.058, 0.024, 0.018, 0.042, 0.068)
	mb.lathe([(0.042, 0.082), (0.056, 0.075), (0.060, 0.0)], 28, "Rim", out=lambda c: Vector((1, c.y, c.z)))
	for k in range(5):
		a = 2 * math.pi * k / 5 + math.pi / 5 + 0.3
		p = Vector((0.056, 0.0575 * math.cos(a), 0.0575 * math.sin(a)))
		mb.tube(p, p + Vector((0.012, 0, 0)), 0.010, "Chrome", segs=6)
	mb.lathe([(0.012, 0.080), (0.012, 0.150), (0.003, 0.150), (0.003, 0.080)], 36, "BrakeDisc", out=lambda c: Vector((1.0, c.y, c.z)))
	mb.lathe([(0.0, 0.0), (0.0, 0.17), (-0.07, 0.17)], 28, "Under", out=lambda c: Vector((1.0, c.y, c.z)))
	mb.lathe([(0.058, 0.040), (0.066, 0.036), (0.070, 0.022), (0.0715, 0.0)], 24, "Steel", out=lambda c: Vector((1, c.y, c.z)))
	mb.disc(Vector((0.0716, 0, 0)), 0.018, "Chrome", normal=(1, 0, 0), segs=14)
	a_valve = 0.82
	v_base = Vector((0.046, 0.189 * math.cos(a_valve), 0.189 * math.sin(a_valve)))
	mb.tube(v_base, v_base + Vector((0.020, 0.006 * math.cos(a_valve), 0.006 * math.sin(a_valve))), 0.004, "Trim", segs=6)
	return mb


# ---------------------------------------------------------------- previews
def render_all(cam, out_dir):
	views = {
		"front34": ((4.6, 5.2, 1.80), 38, None),
		"rear34": ((-4.6, -5.0, 1.90), 38, None),
		"side": ((8.5, 0.0, 0.80), 30, None),
		"front": ((0.0, 9.0, 0.85), 22, None),
		"rear": ((0.0, -9.0, 0.95), 22, None),
		"top": ((0.0, 0.0, 9.0), 30, None),
		"nose": ((-1.6, 4.4, 1.05), 30, (-0.1, Y0 - 0.2, 0.65)),
		"tail": ((1.4, -3.6, 1.15), 30, (0.1, Y0 - LENGTH + 0.2, 0.88)),
		"wheel": ((-2.0, Y0 - FRONT_AXLE_S + 0.6, 0.55), 30, (-TRACK_F / 2, Y0 - FRONT_AXLE_S, TYRE_R)),
	}
	carkit.render_views(cam, out_dir, views, (0, 0, 0.78))


LIVERY_VIEWS = {
	"stripes": ("Stripes", (0.55, 0.04, 0.05)),
	"martini": ("Martini", (0.92, 0.92, 0.9)),
	"abarth": ("Abarth", (0.75, 0.03, 0.04)),
	"marlboro": ("Marlboro", (0.92, 0.92, 0.9)),
}


def render_liveries(objs, cam, out_dir):
	tint = bpy.data.materials["Paint"].node_tree.nodes["Tint"]
	sock = next(s for s in tint.inputs if s.identifier == "A_Color")
	for key, (obj, paint) in LIVERY_VIEWS.items():
		for name in LIVERY_VIEWS.values():
			objs[name[0]].hide_render = name[0] != obj
		sock.default_value = (*paint, 1)
		views = {
			"front34": ((4.6, 5.2, 1.80), 38, None),
			"rear34": ((-4.6, -5.0, 1.90), 38, None),
			"side": ((8.5, 0.0, 0.80), 30, None),
			"top": ((0.0, 0.0, 9.0), 30, None),
		}
		carkit.render_views(cam, os.path.join(out_dir, key), views, (0, 0, 0.78))


# ---------------------------------------------------------------- main
def main():
	bpy.ops.wm.read_factory_settings(use_empty=True)
	body = build_body()
	body_shell = MB()
	body_shell.extend(body)
	details, pj = build_details(body)
	liner = build_liner(body)
	cabin_mb = build_cabin()
	stripes = build_stripes(pj)
	martini = build_martini(pj)
	abarth = build_abarth(pj)
	marlboro = build_marlboro(pj)
	wheel = build_wheel()
	body.extend(liner)
	body.extend(build_rails(body_shell))
	for i, v in enumerate(body.v):
		low = 1.0 - smoothstep(0.20, 0.66, v.z)
		mottle = 0.5 + 0.5 * math.sin(v.x * 17.0 + v.y * 9.0) * math.sin(v.y * 13.0 - v.z * 11.0)
		body.col[i] *= 1.0 - 0.30 * low * (0.65 + 0.35 * mottle) - 0.025 * mottle
	objs = {
		"Body": body.emit("Body", sharp_deg=55, colors=True),
		"Details": details.emit("Details", sharp_deg=40),
		"Stripes": stripes.emit("Stripes"),
		"Wheel": wheel.emit("Wheel", sharp_deg=30),
		"Cabin": cabin_mb.emit("Cabin", sharp_deg=40),
		"Martini": martini.emit("Martini", sharp_deg=60),
		"Abarth": abarth.emit("Abarth", sharp_deg=60),
		"Marlboro": marlboro.emit("Marlboro", sharp_deg=60),
	}
	total = 0
	for name, ob in objs.items():
		t = sum(len(p.vertices) - 2 for p in ob.data.polygons)
		total += t
		print("%-8s %6d tris" % (name, t))
	print("total    %6d tris" % total)
	# Report Godot-space bounding boxes (X=Blender X, Y=Blender Z, Z=Blender Y) for contract verification
	for name in ("Body", "Wheel"):
		vs = [v.co for v in objs[name].data.vertices]
		xs, ys, zs = [v.x for v in vs], [v.y for v in vs], [v.z for v in vs]
		print("bbox %-5s Godot size=(%.4f, %.4f, %.4f) top_y=%.4f z_range=[%.4f, %.4f]" % (
			name, max(xs) - min(xs), max(zs) - min(zs), max(ys) - min(ys), max(zs), -max(ys), -min(ys)))
	carkit.split_bonnet(objs, Y0, S_SCUTTLE, carkit.material("Trim"))
	for name in [k for k in objs if k in ("Body", "Details", "Stripes", "Martini", "Abarth", "Marlboro") or k.startswith("Bonnet")]:
		add_damage_keys(objs[name], dent_delta)
	kit.export_glb(OUT_GLB, texcoords=False)
	if arg("--blend"):
		bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(arg("--blend")))
	if arg("--renders"):
		view = next((k for k in ("martini", "abarth", "marlboro") if "--" + k in sys.argv), "")
		cam = carkit.setup_preview((0.92, 0.92, 0.9) if view in ("martini", "marlboro") else (0.14, 0.25, 0.42))
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
		render_all(cam, out)
		if not view and "--no-liveries" not in sys.argv:
			render_liveries(objs, cam, out)


if __name__ == "__main__":
	main()
