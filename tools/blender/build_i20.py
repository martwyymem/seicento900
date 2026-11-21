"""Builds the game's Hyundai i20 (first generation, PB, 2008-2012, five-door supermini, 1.4 16V) in Blender.

Run from the repository root (Blender 4.2 or newer, headless):

    blender -b -P tools/blender/build_i20.py -- [--renders DIR] [--blend FILE]

Writes godot/models/i20.glb. With --renders it also saves preview PNGs (front, rear, side, top, three-quarters).

The fourth campaign car, built after build_v50.py and build_golf4.py (see AGENTS.md, "Adding the next car"): same
object and material names, so race_car_visual.gd drives it unchanged. Real-car numbers: 3940 mm long, 1710 mm wide
(without mirrors), 1490 mm high, 2525 mm wheelbase, 1505/1503 mm track, 185/60 R15 tyres on 15" five-split-spoke alloys.

A compact European-styled 5-door supermini: short sloping nose, swept-back teardrop headlamps climbing the wings,
slim upper badge bar with the Hyundai oval H over a bold hexagonal lower grille and corner fog-lamp pods, cab-forward
raked windscreen, tall airy roof peaking over the B-pillar, rising beltline with black B-pillar and fixed rear quarter
glass, short rear overhang, high stacked tail lamps flanking the rear screen, and the rear plate recessed in the bumper.

Scene objects: Body (painted shell with glass, trim, body-coloured mirrors and handles, underbody and cabin liner;
vertex colours carry the panel gaps), Details (lamps, hexagonal grille, intakes, plates, wipers, exhaust, wheel wells),
Stripes, Martini, Abarth, Marlboro (liveries), Cabin (dash, wheel, seats, bench, console; hidden on distant cars),
Wheel (alloy wheel and tyre, one wheel at the origin, outer face towards +X).
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
OUT_GLB = os.path.join(ROOT, "godot", "models", "i20.glb")

# ---------------------------------------------------------------- real-car numbers
LENGTH = 3.940
WHEELBASE = 2.525
FRONT_AXLE_S = 0.785  # 785 mm front overhang, 630 mm rear overhang (classic tight supermini stance)
REAR_AXLE_S = FRONT_AXLE_S + WHEELBASE
Y0 = FRONT_AXLE_S + WHEELBASE / 2.0
TRACK_F = 1.505
TRACK_R = 1.503
TYRE_R = 0.3015  # 185/60 R15: 381.0 mm rim + 2 x 111.0 mm sidewall = 603.0 mm
TYRE_W = 0.185
ARCH_R = 0.354
ROOF = 1.490

S_SCUTTLE = 1.00
S_COWL, S_WS_TOP = 1.08, 1.86
S_SAIL = 1.38
S_B0, S_B1 = 2.04, 2.14
S_QR = 3.02  # rear door drop glass ends at this black post; small fixed quarter glass behind it to S_Q1
S_Q1 = 3.32  # rear edge of the side window, leaning forward along the C-pillar
S_RG0, S_RG1 = 3.47, 3.81  # rear hatch glass from roof lip spoiler down to the tailgate
S_DECK = 3.43  # tailgate top shut line behind the roof
S_DOOR = (1.16, 2.09, 3.35)
FRIT = 0.015
PILLAR = 0.068


def bl(x, s, z):
	return Vector((x, Y0 - s, z))


# ---------------------------------------------------------------- body profile curves (metres)
# Plan, elevation and section lines for the PB i20: a compact, rounded wedge nose with a protruding bumper beam, raked
# teardrop headlamps and a sloping V-creased bonnet, a raked cab-forward windscreen, a tall arched roof peaking at
# 1490 mm, a rising beltline with clean sculpted flanks, and a short, taut hatchback tail with high shoulder corners.
L = LENGTH
W = Curve([(0.0, 0.54), (0.03, 0.640), (0.08, 0.720), (0.16, 0.782), (0.30, 0.826), (0.55, 0.848), (0.85, 0.855),
	(1.3, 0.855), (2.2, 0.855), (3.1, 0.853), (3.50, 0.846), (3.72, 0.830), (3.83, 0.805), (3.89, 0.768),
	(3.92, 0.720), (L, 0.65)])
ZM = Curve([(0.0, 0.42), (0.10, 0.46), (0.30, 0.52), (0.90, 0.62), (1.40, 0.64), (3.10, 0.67), (3.65, 0.67), (L, 0.56)])
WSH = Curve([(0.0, 0.48), (0.03, 0.570), (0.08, 0.645), (0.16, 0.710), (0.32, 0.758), (0.60, 0.785), (1.0, 0.796),
	(1.5, 0.800), (2.3, 0.800), (3.1, 0.796), (3.55, 0.788), (3.76, 0.772), (3.85, 0.745), (3.90, 0.708),
	(3.925, 0.670), (L, 0.60)])
ZSH = Curve([(0.0, 0.525), (0.03, 0.560), (0.07, 0.618), (0.13, 0.678), (0.22, 0.738), (0.38, 0.795), (0.60, 0.844),
	(0.82, 0.884), (S_SCUTTLE, 0.908), (S_COWL, 0.920), (1.40, 0.942), (1.85, 0.958), (2.40, 0.974), (3.00, 0.992),
	(3.45, 1.008), (3.74, 1.010), (3.83, 0.995), (3.88, 0.960), (3.91, 0.900), (3.928, 0.800), (3.936, 0.680), (L, 0.58)])
ZT = Curve([(0.0, 0.555), (0.03, 0.592), (0.07, 0.652), (0.13, 0.715), (0.22, 0.775), (0.38, 0.830), (0.60, 0.880),
	(0.82, 0.922), (S_SCUTTLE, 0.948), (S_COWL, 0.962), (1.28, 1.078), (1.48, 1.198), (1.68, 1.318), (S_WS_TOP, 1.422),
	(2.02, 1.466), (2.22, 1.485), (2.45, ROOF), (2.75, 1.486), (3.05, 1.472), (3.30, 1.452), (S_DECK, 1.438), (S_RG0, 1.428),
	(3.56, 1.335), (3.65, 1.235), (3.73, 1.132), (S_RG1, 1.032), (3.86, 0.995), (3.895, 0.945), (3.918, 0.865),
	(3.932, 0.755), (L, 0.62)])
ZB = Curve([(0.0, 0.250), (0.05, 0.225), (0.20, 0.208), (0.50, 0.200), (1.0, 0.195), (2.5, 0.195), (3.4, 0.208),
	(3.72, 0.242), (3.88, 0.275), (L, 0.305)])
WR = Curve([(0.0, 0.44), (0.04, 0.520), (0.10, 0.590), (0.20, 0.652), (0.45, 0.705), (0.80, 0.728), (S_COWL, 0.735),
	(1.48, 0.692), (S_WS_TOP, 0.642), (2.35, 0.626), (2.95, 0.616), (3.30, 0.595), (S_RG0, 0.565), (3.64, 0.578),
	(S_RG1, 0.605), (3.88, 0.645), (3.92, 0.630), (L, 0.55)])
DR = Curve([(0.0, 0.014), (0.2, 0.034), (S_COWL, 0.044), (S_WS_TOP, 0.052), (3.35, 0.052), (S_RG1, 0.036), (L, 0.014)])

SEG_ROWS = [3, 2, 5, 5, 1, 4, 2, 8]
SEG_AB, SEG_BC, SEG_CD, SEG_DE, SEG_EF, SEG_FG, SEG_GH, SEG_HI = range(8)


def bonnet_crease_t(s):
	"""Parameter t along H->I for the i20's V-shaped bonnet crease: starts at the upper grille's outer corners
	(|x| ~ 0.255 at s = 0.10) and sweeps outward to the base of the A-pillars (|x| ~ 0.595 at s = S_SCUTTLE)."""
	f = min(1.0, max(0.0, (s - 0.10) / (S_SCUTTLE - 0.10)))
	xc = lerp(0.255, 0.595, f)
	return min(0.66, max(0.16, 1.0 - xc / max(0.30, WR(s))))


def bonnet_crease_dz(s, sub):
	"""Raised V-crease profile on the bonnet (SEG_HI): a crisp ridge along sub == 4 with a gentle step onto the wings."""
	if s >= S_COWL:
		return 0.0
	env = smoothstep(0.08, 0.17, s) * (1.0 - smoothstep(S_SCUTTLE - 0.04, S_COWL, s))
	if env <= 0.0:
		return 0.0
	prof = (0.0, 0.0, -0.0015, 0.0050, 0.0105, 0.0085, 0.0070, 0.0070)
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
	C = Vector((w - 0.030, zb + 0.054))
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
		creased = [foot, tc - 0.020, tc, in_b, (in_b + 1.0) * 0.5, 1.0]
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
		S_Q1, S_DECK, S_RG0, S_RG0 + FRIT, S_RG1 - FRIT, S_RG1]
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
	"Bumper": ((0.070, 0.072, 0.076), 0.62, 0.0, {}),
	"Grille": ((0.01, 0.01, 0.01), 0.7, 0.0, {}),
	"Chrome": ((0.85, 0.86, 0.88), 0.12, 1.0, {}),
	"Exhaust": ((0.75, 0.76, 0.78), 0.16, 0.95, {}),
	"Headlight": ((0.32, 0.33, 0.34), 0.08, 0.9, {"emit": ((1.0, 0.95, 0.84), 0.2)}),
	"Indicator": ((1.0, 0.42, 0.04), 0.1, 0.0, {"emit": ((1.0, 0.35, 0.02), 0.7)}),
	"Taillight": ((0.42, 0.01, 0.015), 0.08, 0.0, {"emit": ((1.0, 0.05, 0.03), 0.15)}),
	"LampClear": ((0.85, 0.80, 0.80), 0.08, 0.0, {}),
	"LampBezel": ((0.18, 0.19, 0.20), 0.24, 0.82, {}),
	"Fog": ((0.70, 0.72, 0.74), 0.08, 0.6, {"emit": ((1.0, 0.95, 0.84), 0.1)}),
	"Plate": ((0.94, 0.93, 0.89), 0.45, 0.0, {}),
	"Seat": ((0.03, 0.03, 0.035), 0.9, 0.0, {}),
	"Fabric": ((0.10, 0.10, 0.105), 0.95, 0.0, {}),
	"Tyre": ((0.03, 0.03, 0.03), 0.8, 0.0, {}),
	"Sidewall": ((0.085, 0.085, 0.085), 0.7, 0.0, {}),
	"Rim": ((0.74, 0.75, 0.78), 0.2, 0.92, {}),
	"Steel": ((0.36, 0.37, 0.38), 0.42, 0.5, {}),
	"BrakeDisc": ((0.20, 0.19, 0.19), 0.5, 0.7, {}),
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
			# crisp panel shut lines on doors
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

	# rolled wheel-arch lips and subtle rising shoulder character line along the flanks
	for v in mb.v:
		ax = abs(v.x)
		if ax < 0.45 or v.z < 0.18:
			continue
		s = Y0 - v.y
		for sc in (FRONT_AXLE_S, REAR_AXLE_S):
			d = math.hypot(s - sc, v.z - TYRE_R)
			if d < ARCH_R + 0.032:
				v.x += math.copysign(0.008 * (1.0 - smoothstep(ARCH_R + 0.012, ARCH_R + 0.032, d))
					* (1.0 - smoothstep(0.86, 0.96, v.z)), v.x)
		# subtle European supermini side crease rising from behind the front arch to the tail lamp corner
		if 1.15 < s < 3.65 and ax > 0.72:
			zc = lerp(0.81, 0.92, (s - 1.15) / 2.50)
			dz = abs(v.z - zc)
			if dz < 0.06:
				v.x += math.copysign(0.005 * (1.0 - smoothstep(0.0, 0.06, dz))
					* smoothstep(1.15, 1.35, s) * (1.0 - smoothstep(3.45, 3.65, s)), v.x)

	# body-coloured door mirrors on black feet at the sail (Paint only on the Body mesh), plus body-coloured pull handles
	for side in (1, -1):
		mb.box(bl(side * 0.822, 1.40, 0.990), (0.055, 0.09, 0.044), "Trim")
		mb.blob(bl(side * 0.892, 1.44, 1.035), (0.065, 0.048, 0.056), "Paint", e=0.5)
		mb.blob(bl(side * 0.892, 1.485, 1.035), (0.057, 0.006, 0.045), "Chrome", e=0.35)
		# body-coloured pull handles aligned with the rising character line
		for hs, hz in ((1.90, 0.880), (2.86, 0.915)):
			x = W(hs) - 0.015
			mb.blob(bl(side * (x + 0.005), hs, hz), (0.010, 0.072, 0.015), "Paint", e=0.4)
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
		if s < 0.85 or c.z < 0.2:
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


def clip_band(poly, z0, z1):
	def clip(pts, keep, cut):
		out = []
		for i, a in enumerate(pts):
			b = pts[(i + 1) % len(pts)]
			ka, kb = keep(a), keep(b)
			if ka:
				out.append(a)
			if ka != kb:
				t = (cut - a[1]) / (b[1] - a[1])
				out.append((lerp(a[0], b[0], t), cut))
		return out
	pts = clip(poly, lambda p: p[1] >= z0, z0)
	return clip(pts, lambda p: p[1] <= z1, z1)


def shrink(poly, k):
	cu = sum(p[0] for p in poly) / len(poly)
	cv = sum(p[1] for p in poly) / len(poly)
	return [(lerp(u, cu, k), lerp(v, cv, k * 0.6)) for u, v in poly]


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
			ref = nors[i][j] + nors[i + 1][j] + nors[i][j + 1] + nors[i + 1][j + 1]
			mb.face([ids[i][j], ids[i + 1][j], ids[i + 1][j + 1], ids[i][j + 1]], mat, ref)
	for i, k in ((0, 1), (len(ts) - 1, len(ts) - 2)):
		inner = [pts[i][j] - nors[i][j] * 0.006 for j in range(len(vs))]
		ref = pts[i][len(vs) // 2] - pts[k][len(vs) // 2]
		mb.poly(pts[i] + list(reversed(inner)), mat, ref)
	return pts


def hyundai_badge(pj, mb, proj, cu, cv, rx, ry, base_off):
	"""The Hyundai oval H emblem: chrome outer oval ring, dark backing, and slanted italic H bars."""
	pj.star(mb, ellipse(cu, cv, rx + 0.004, ry + 0.004, 28), proj, "Gasket", offset=base_off, rings=2, samples=1, skirt=0.003)
	pj.star(mb, ellipse(cu, cv, rx, ry, 28), proj, "Chrome", offset=base_off + 0.0020, rings=2, samples=1, skirt=0.002)
	pj.star(mb, ellipse(cu, cv, rx * 0.82, ry * 0.78, 28), proj, "Trim", offset=base_off + 0.0034, rings=2, samples=1, skirt=0.0)
	# slanted italic H: left leg, right leg and angled crossbar
	dx = rx * 0.34
	dy = ry * 0.64
	lean = rx * 0.14
	w = rx * 0.12
	left_leg = [(cu - dx - lean - w, cv - dy), (cu - dx - lean + w, cv - dy),
		(cu - dx + lean + w, cv + dy), (cu - dx + lean - w, cv + dy)]
	right_leg = [(cu + dx - lean - w, cv - dy), (cu + dx - lean + w, cv - dy),
		(cu + dx + lean + w, cv + dy), (cu + dx + lean - w, cv + dy)]
	bar = [(cu - dx - w * 0.5, cv - ry * 0.16), (cu + dx + w * 0.5, cv + ry * 0.08),
		(cu + dx + w * 0.5, cv + ry * 0.26), (cu - dx - w * 0.5, cv + ry * 0.02)]
	for poly in (left_leg, right_leg, bar):
		pj.star(mb, dense(poly, 0.015), proj, "Chrome", offset=base_off + 0.0048, rings=1, samples=1, skirt=0.001)


# ---------------------------------------------------------------- lamps, grilles, bumper plastics
FB_AXIS = 0.50
HL_AXIS = 0.72  # headlamp wrap axis: rays from 23 to 83 deg sweep smoothly from beside the upper grille back along the wing
RB_AXIS = LENGTH - 0.50

# Swept-back teardrop headlamps of the PB i20 (cyl_proj around HL_AXIS: u is degrees from straight ahead, v is height z):
# tapered inner corner beside the upper grille at 23 deg, opening into a multi-reflector teardrop over the front corner
# and sweeping up and back along the wing towards the wheel arch to a pointed tip at 83 deg.
HL_U0, HL_U1 = 23.0, 83.0
HL_TOP = Curve([(23.0, 0.650), (26.0, 0.665), (34.0, 0.692), (46.0, 0.726), (58.0, 0.754), (68.0, 0.785), (76.0, 0.808),
	(81.0, 0.816), (83.0, 0.814)])
HL_BOT = Curve([(23.0, 0.588), (26.0, 0.584), (34.0, 0.585), (46.0, 0.602), (58.0, 0.635), (68.0, 0.688), (76.0, 0.752),
	(81.0, 0.796), (83.0, 0.808)])

# Slim upper badge grille between the headlamps + full-width body-coloured bumper beam + wide trapezoidal lower air dam
UPPER_GRILLE = [
	(-0.256, 0.654), (0.256, 0.654), (0.264, 0.626), (0.236, 0.586),
	(-0.236, 0.586), (-0.264, 0.626),
]
LOWER_GRILLE = [
	(-0.325, 0.398), (0.325, 0.398),
	(0.395, 0.358), (0.415, 0.292),
	(0.378, 0.264), (-0.378, 0.264),
	(-0.415, 0.292), (-0.395, 0.358),
]

# High, stacked vertical tail lamps of the PB i20: hugging the painted C-pillar shoulder cleanly outside the rear
# screen, wider at the waist and rounding off smoothly at the upper shoulder.
TAIL_OUT = [
	(0.525, 0.815), (0.515, 0.895), (0.535, 0.975), (0.578, 1.055), (0.598, 1.135),
	(0.615, 1.188), (0.642, 1.202), (0.672, 1.178), (0.698, 1.112), (0.724, 1.028),
	(0.744, 0.940), (0.744, 0.855), (0.720, 0.812), (0.625, 0.806),
]
TAIL_OUT = dense(TAIL_OUT, 0.02)
TAIL_RED_TOP = inset(clip_band(TAIL_OUT, 1.026, 1.25), 0.007)
TAIL_AMBER = inset(clip_band(TAIL_OUT, 0.976, 1.020), 0.007)
TAIL_CLEAR = inset(clip_band(TAIL_OUT, 0.922, 0.970), 0.007)
TAIL_RED_LOW = inset(clip_band(TAIL_OUT, 0.800, 0.916), 0.007)


def build_plastics(pj, mb):
	"""Hyundai i20 nose and tail plastics: slim upper grille with chrome top bar and oval H badge, full-width
	body-coloured bumper beam carrying the front plate, wide lower trapezoidal black intake, sculpted corner fog pods,
	rear bumper plate recess and lower valance."""
	fp = cyl_proj(FB_AXIS, False)
	# Upper slim grille opening with sculpted chrome upper wing bar and centred Hyundai oval H
	pj.star(mb, dense(UPPER_GRILLE, 0.03), front_proj, "Trim", offset=0.0025, rings=1, samples=2, skirt=0.004)
	pj.star(mb, dense(inset(UPPER_GRILLE, 0.009), 0.03), front_proj, "Grille", offset=0.0040, rings=1, samples=2, skirt=0.0)
	pj.strip(mb, -0.250, 0.250, 0.638, 0.651, 24, 1, front_proj, "Chrome", offset=0.0068)
	pj.strip(mb, -0.232, 0.232, 0.612, 0.621, 24, 1, front_proj, "Trim", offset=0.0055)
	hyundai_badge(pj, mb, front_proj, 0.0, 0.622, 0.056, 0.030, 0.0074)

	# Front European number plate (512 x 105 mm) on the full-width body-coloured bumper beam:
	# bottom edge y0_front = 0.425 (matches CarCatalog I20_VISUAL plate_y)
	pj.star(mb, rounded_rect(-0.264, 0.264, 0.419, 0.5357, 0.006), front_proj, "Trim", offset=0.0055, rings=1, samples=2, skirt=0.006)
	pj.star(mb, rounded_rect(-0.2559, 0.2559, 0.425, 0.5297, 0.004), front_proj, "Plate", offset=0.0085, rings=1, samples=2, skirt=0.0)

	# Wide trapezoidal lower black air dam below the body-coloured bumper beam
	pj.star(mb, dense(LOWER_GRILLE, 0.03), front_proj, "Trim", offset=0.0022, rings=1, samples=2, skirt=0.004)
	pj.star(mb, dense(inset(LOWER_GRILLE, 0.010), 0.03), front_proj, "Grille", offset=0.0038, rings=1, samples=2, skirt=0.0)
	for z, hw in ((0.292, 0.386), (0.326, 0.372), (0.360, 0.346)):
		pj.strip(mb, -hw, hw, z, z + 0.007, 28, 1, front_proj, "Trim", offset=0.0060)

	# Sculpted corner fog-lamp pods flanking the lower air dam
	for side in (1, -1):
		hp = lambda u, v, side=side: front_proj(side * u, v)
		pod = [(0.455, 0.382), (0.610, 0.402), (0.644, 0.365), (0.624, 0.284), (0.520, 0.270), (0.448, 0.294)]
		pj.star(mb, dense(pod, 0.03), hp, "Trim", offset=0.0040, rings=2, samples=2, skirt=0.005)
		pj.star(mb, ellipse(0.546, 0.336, 0.044, 0.044, 22), hp, "Chrome", offset=0.0068, rings=2, samples=1, skirt=0.0)
		pj.star(mb, ellipse(0.546, 0.336, 0.036, 0.036, 22), hp, "Fog", offset=0.0088, bulge=0.003, rings=2, samples=1, skirt=0.0)

	# Subtle black front chin spoiler lip wrapping round to the front arches
	chin_rows = [(0.205, -0.002), (0.214, 0.007), (0.232, 0.009), (0.240, -0.002)]
	wrap_band(pj, mb, fp, FRONT_AXLE_S, True, [r[0] for r in chin_rows], lambda v, rows=chin_rows: profile(v, rows),
		"Bumper", reach=0.92)
	# Bonnet leading shut line cleanly above the upper grille between the headlamps
	pj.strip(mb, -0.268, 0.268, 0.672, 0.677, 24, 1, front_proj, "Gasket", offset=0.0012)

	# Rear lower black bumper valance wrapping round towards the rear arches
	rp = cyl_proj(RB_AXIS, True)
	rows = [(0.292, -0.002), (0.302, 0.008), (0.316, 0.011), (0.372, 0.011), (0.382, 0.006), (0.388, -0.001)]
	vs = sorted(set([r[0] for r in rows] + spread(0.32, 0.37, 0.02)))
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
		# Swept-back teardrop headlamps wrapped around HL_AXIS: flush gasket surround, metallic inner bezel,
		# bright chrome-rimmed twin reflector bowls, upper-outer amber indicator, and domed clear cover.
		hl_cyl = cyl_proj(HL_AXIS, False)
		hp = lambda u, v, side=side, hl_cyl=hl_cyl: hl_cyl(side * u, v)
		wing_fade = lambda u: 1.0 - smoothstep(46.0, 80.0, u)

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
		# Upper-outer amber turn-signal indicator nestled in the swept wing tip
		iu0, iu1 = 62.0, 79.5
		def ind_span(u):
			t = min(1.0, max(0.0, (u - iu0) / (iu1 - iu0)))
			w = math.sin(math.pi * t) ** 0.5
			b, tp_ = HL_BOT(u), HL_TOP(u)
			mid = lerp(b, tp_, 0.55)
			half = max(0.002, (tp_ - b) * 0.27 * w)
			return mid - half, mid + half
		patch_uv(mb, pj, hp, iu0, iu1,
			lambda u: ind_span(u)[0],
			lambda u: ind_span(u)[1],
			lambda u, v: lerp(0.0065, 0.015, wing_fade(u)), "Indicator", nu=10, nv=5, bulge=0.0020)
		# Twin bright chrome-rimmed reflector bowls (inboard main beam + larger outboard dipped beam)
		reflector(mb, pj, hp, 31.5, 0.638, 0.045)
		reflector(mb, pj, hp, 46.5, 0.672, 0.056)
		gu0, gu1, gbot, gtop = hl_inset(0.4, 0.5, 0.0025)
		patch_uv(mb, pj, hp, gu0, gu1, gbot, gtop,
			lambda u, v: lerp(0.0095, 0.036, wing_fade(u)), "LampGlass", nu=24, nv=8,
			bulge=lambda u, v: lerp(0.002, 0.010, wing_fade(u)),
			skirt_fn=lambda u, v: lerp(0.007, 0.025, wing_fade(u)))

		# High stacked tail lamps flanking the rear screen
		tp = lambda u, v, side=side: rear_proj(side * u, v)
		pj.star(mb, TAIL_OUT, tp, "Gasket", offset=0.004, rings=5, samples=2, skirt=0.004)
		for poly in (TAIL_RED_TOP, TAIL_RED_LOW):
			pj.star(mb, poly, tp, "Taillight", offset=0.010, rings=5, samples=2, skirt=0.0)
			pj.star(mb, shrink(poly, 0.25), tp, "TailBulb", offset=0.0115, rings=4, samples=2, skirt=0.0)
			pj.star(mb, poly, tp, "TailGlass", offset=0.015, bulge=0.0025, rings=5, samples=2, skirt=0.005)
		pj.star(mb, TAIL_AMBER, tp, "Indicator", offset=0.0125, rings=4, samples=2, skirt=0.0)
		pj.star(mb, TAIL_CLEAR, tp, "LampClear", offset=0.0125, rings=4, samples=2, skirt=0.0)
		pj.star(mb, inset(clip_band(TAIL_OUT, 0.920, 1.024), 0.007), tp, "LampGlass", offset=0.0165, rings=4, samples=2, skirt=0.004)
		# Rear bumper reflectors in the lower corners
		pj.star(mb, rounded_rect(0.50, 0.64, 0.415, 0.438, 0.008), tp, "Taillight", offset=0.006, rings=1, samples=2, skirt=0.0)

		pj = pj_all
		sp = side_proj(side)
		# Fixed rear quarter-light vertical divider post inside the rear window (clamped cleanly inside the glass)
		pj.strip(mb, S_QR - 0.006, S_QR + 0.016, 0.99, 1.338, 2, 8, sp, "Trim", offset=0.003)
		# Side repeater on the front wing behind the wheel arch
		pj.star(mb, ellipse(1.19, 0.77, 0.024, 0.010, 12), sp, "Gasket", offset=0.002, rings=1, samples=2)
		pj.star(mb, ellipse(1.19, 0.77, 0.018, 0.007, 12), sp, "Indicator", offset=0.004, bulge=0.002, rings=2, samples=2)
		# Dark recesses behind the pull handles + front lock barrel
		for hs, hz in ((1.90, 0.880), (2.86, 0.915)):
			pj.star(mb, rounded_rect(hs - 0.068, hs + 0.068, hz - 0.022, hz + 0.010, 0.011), sp, "Gasket", offset=0.0012,
				rings=1, samples=2)
		pj.star(mb, ellipse(1.90 + 0.088, 0.880, 0.0085, 0.0085, 10), sp, "Chrome", offset=0.004, rings=1, samples=1)
		# Subtle black lower sill edge
		pj.band(mb, spread(1.18, 2.90, 0.05, S_DOOR[:2]), [0.205, 0.222, 0.238],
			lambda u, v: 0.0035 if 0.215 < v < 0.230 else 0.0, lambda u, v: "Bumper", sp)

		# Closed wheel-well liners
		for sc in (FRONT_AXLE_S, REAR_AXLE_S):
			rows = []
			for xo in (0.48, 0.74):
				row = []
				for k in range(21):
					a = math.radians(-12 + 204 * k / 20)
					row.append(bl(side * xo, sc - (ARCH_R - 0.006) * math.cos(a), TYRE_R + (ARCH_R - 0.006) * math.sin(a)))
				rows.append(row)
			mb.grid(rows, "Under", out=lambda q, sc=sc: Vector((0, (Y0 - sc) - q.y, TYRE_R - q.z)))
			c = bl(side * 0.48, sc, TYRE_R)
			arc = rows[0]
			for k in range(len(arc) - 1):
				mb.poly([c, arc[k], arc[k + 1]], "Under", Vector((side, 0, 0)))

	# Fuel flap on the left rear quarter (Hyundai i20 PB has its fuel door on the left side)
	spl = side_proj(-1)
	loc, n = pj.hit(*spl(3.52, 0.85))
	mb.ring(loc + n * 0.0012, 0.054, 0.0575, "Gasket", normal=n, segs=28)

	# Rear end: bumper licence-plate recess + plate (y0_rear = 0.440, CarCatalog I20_VISUAL plate_y), clean tailgate with
	# Hyundai oval H badge, chrome HYUNDAI and i20 badges, shut lines, roof lip spoiler 3rd brake light and rear wiper.
	recess = [(-0.34, 0.562), (0.34, 0.562), (0.31, 0.422), (-0.31, 0.422)]
	pj.star(mb, dense(recess, 0.04), rear_proj, "Gasket", offset=0.0015, rings=1, samples=2, skirt=0.0)
	pj.star(mb, rounded_rect(-0.264, 0.264, 0.434, 0.5507, 0.006), rear_proj, "Trim", offset=0.0028, rings=1, samples=2, skirt=0.0)
	pj.star(mb, rounded_rect(-0.2559, 0.2559, 0.440, 0.5447, 0.004), rear_proj, "Plate", offset=0.0052, rings=1, samples=2, skirt=0.0)
	# Hyundai oval H badge centred on the tailgate
	hyundai_badge(pj, mb, rear_proj, 0.0, 0.895, 0.062, 0.034, 0.0035)
	# Tailgate release handle recessed under the crease above the bumper
	pj.star(mb, rounded_rect(-0.085, 0.085, 0.678, 0.698, 0.007), rear_proj, "Trim", offset=0.0035, rings=1, samples=2, skirt=0.002)
	# HYUNDAI and i20 chrome lettering on the tailgate
	text_decal(pj, mb, rear_proj, "HYUNDAI", -0.354, 0.770 - 0.003, 0.165, "Gasket", 0.0030, 1)
	text_decal(pj, mb, rear_proj, "HYUNDAI", -0.358, 0.770, 0.165, "Chrome", 0.0052, 1)
	text_decal(pj, mb, rear_proj, "i20", 0.374, 0.770 - 0.003, 0.068, "Gasket", 0.0030, 1)
	text_decal(pj, mb, rear_proj, "i20", 0.370, 0.770, 0.068, "Chrome", 0.0052, 1)
	# Tailgate shut lines beside the high tail lamps and along the bumper top
	for x in (-0.504, 0.504):
		pj.strip(mb, x + 0.003, x - 0.003, 0.640, 0.985, 1, 20, rear_proj, "Gasket", offset=0.0022)
	pj.strip(mb, -0.504, 0.504, 0.637, 0.643, 30, 1, rear_proj, "Gasket", offset=0.0018)
	pj.strip(mb, S_DECK - 0.003, S_DECK + 0.003, -0.54, 0.54, 1, 36, top_proj, "Gasket", offset=0.0012)
	# High-mounted third brake lamp in the spoiler lip over the rear glass
	pj.strip(mb, -0.45, 0.45, 1.395, 1.422, 34, 1, rear_proj, "Trim", offset=0.0055)
	pj.strip(mb, -0.135, 0.135, 1.402, 1.416, 12, 1, rear_proj, "Taillight", offset=0.0080)
	# Rear wiper parked along the base of the rear screen
	base_p = pj.hit(*rear_proj(0.0, 1.055))[0]
	mb.blob(base_p + Vector((0, -0.012, 0)), (0.020, 0.015, 0.020), "Trim", e=0.3)
	tip = pj.hit(*rear_proj(0.36, 1.080))[0]
	mb.tube(base_p + Vector((0, -0.016, 0.004)), tip + Vector((0, -0.010, 0)), 0.0055, "Trim", segs=6)

	# Scuttle washer jets and front wipers
	for x in (-0.28, 0.28):
		pj.star(mb, ellipse(S_SCUTTLE + 0.02, x, 0.011, 0.008, 8), top_proj, "Trim", offset=0.004, rings=1, samples=1)
	for xp, x1 in ((-0.50, 0.00), (0.05, 0.58)):
		base_p = pj.hit(*top_proj(S_SCUTTLE + 0.05, xp))[0]
		mb.blob(base_p + Vector((0, 0, 0.010)), (0.017, 0.017, 0.013), "Trim", e=0.3)
		a = base_p + Vector((0, 0, 0.018))
		b = pj.hit(*top_proj(S_SCUTTLE + 0.19, x1))[0] + Vector((0, 0, 0.016))
		mb.tube(a, b, 0.0055, "Trim", segs=6)
		bx0 = pj.hit(*top_proj(S_SCUTTLE + 0.17, xp + 0.04))[0] + Vector((0, 0, 0.012))
		bx1 = pj.hit(*top_proj(S_SCUTTLE + 0.22, x1 + 0.02))[0] + Vector((0, 0, 0.012))
		mb.box((bx0 + bx1) / 2, ((bx1 - bx0).length, 0.011, 0.011), "Trim",
			basis=Matrix.Rotation(math.atan2(bx1.y - bx0.y, bx1.x - bx0.x), 3, "Z"))

	# Short roof aerial at the rear of the roof
	base = pj.hit(*top_proj(3.22, 0.0))[0]
	mb.blob(base + Vector((0, 0, 0.010)), (0.018, 0.030, 0.012), "Trim", e=0.4)
	mb.tube(base + Vector((0, 0, 0.015)), base + Vector((0, -0.11, 0.15)), 0.0038, "Trim", segs=6)

	# Single exhaust tailpipe tucked under the right rear valance
	mb.tube(bl(0.24, 3.45, 0.255), bl(-0.18, 3.45, 0.255), 0.072, "Steel", segs=14)
	mb.tube(bl(0.36, 3.52, 0.248), bl(0.36, LENGTH + 0.004, 0.254), 0.022, "Exhaust", segs=14, caps=False)
	mb.ring(bl(0.36, LENGTH + 0.004, 0.254), 0.018, 0.023, "Exhaust", normal=(0, -1, 0), segs=14)
	mb.disc(bl(0.36, LENGTH - 0.006, 0.254), 0.019, "Under", normal=(0, -1, 0), segs=14)

	# Underbody floor pan and closed engine/boot bays
	mb.box(bl(0, 0.78, 0.205), (0.76, 0.72, 0.03), "Steel")
	mb.box(bl(0, 0.70, 0.44), (1.08, 0.90, 0.38), "Under")
	mb.box(bl(0, 3.55, 0.44), (1.08, 0.62, 0.38), "Under")
	mb.box(bl(0, 2.05, 0.215), (0.90, 2.15, 0.07), "Under")

	return mb, pj


def build_cabin():
	"""The cabin silhouette seen through the glass: dashboard with instrument binnacle and centre stack, three-spoke
	wheel, two front seats, rear bench and rear-view mirror."""
	mb = MB()

	def cb(x, s, z):
		return bl(x, s - 0.14, z)
	mb.blob(cb(0, 1.56, 0.92), (0.64, 0.19, 0.09), "Interior", e=0.3)
	mb.box(cb(0, 1.47, 0.66), (1.34, 0.14, 0.44), "Interior")
	mb.box(cb(0, 1.69, 0.68), (0.24, 0.28, 0.40), "Interior")
	mb.box(cb(0, 2.00, 0.40), (0.22, 0.74, 0.18), "Interior")
	mb.blob(cb(-0.35, 1.62, 1.04), (0.16, 0.10, 0.06), "Interior", e=0.35)
	mb.disc(cb(-0.35, 1.60, 1.02), 0.052, "Plate", normal=(0, -0.6, 0.8), segs=16)
	for sx in (-0.065, 0.065):
		mb.disc(cb(sx, 1.66, 0.92), 0.024, "Trim", normal=(0, -0.4, 0.9), segs=12)
		mb.ring(cb(sx, 1.66, 0.92), 0.021, 0.026, "Chrome", normal=(0, -0.4, 0.9), segs=12)
	mb.blob(cb(0, 1.90, 0.50), (0.055, 0.065, 0.04), "Trim", e=0.3)
	mb.tube(cb(0, 1.90, 0.52), cb(0, 1.92, 0.72), 0.0085, "Chrome", segs=8)
	mb.blob(cb(0, 1.92, 0.73), (0.021, 0.021, 0.025), "Seat", e=0.35)
	mb.tube(cb(0.065, 2.22, 0.50), cb(0.065, 2.30, 0.58), 0.010, "Interior", segs=6)
	for px in (-0.43, -0.35, -0.27):
		mb.box(cb(px, 1.52, 0.30), (0.048, 0.012, 0.072), "Steel")
	mb.box(cb(0, 2.06, 1.34), (0.125, 0.015, 0.042), "Interior")
	mb.tube(cb(0, 2.07, 1.35), cb(0, 2.09, 1.39), 0.006, "Trim", segs=6)
	tilt = math.radians(66)
	n = Vector((0, -math.cos(tilt), math.sin(tilt)))
	u = Vector((1, 0, 0))
	v = n.cross(u)
	sw = cb(-0.35, 1.82, 1.01)
	ring = [sw + (u * math.cos(2 * math.pi * k / 24) + v * math.sin(2 * math.pi * k / 24)) * 0.185 for k in range(24)]
	for k in range(24):
		mb.tube(ring[k], ring[(k + 1) % 24], 0.014, "Seat", segs=8, caps=False)
	mb.tube(sw, sw - v * 0.175, 0.011, "Trim", segs=6)
	mb.tube(sw, sw - u * 0.155 + v * 0.04, 0.011, "Trim", segs=6)
	mb.tube(sw, sw + u * 0.155 + v * 0.04, 0.011, "Trim", segs=6)
	mb.disc(sw, 0.044, "Interior", normal=n, segs=14)
	mb.disc(sw + n * 0.003, 0.024, "Chrome", normal=n, segs=12)
	mb.tube(sw, sw + Vector((0, 0.26, -0.10)), 0.020, "Trim", segs=8)
	lean = Matrix.Rotation(math.radians(-12), 3, "X")
	for sx in (-0.35, 0.35):
		mb.blob(cb(sx, 2.25, 0.44), (0.22, 0.25, 0.085), "Fabric", e=0.40)
		mb.blob(cb(sx, 2.47, 0.82), (0.23, 0.08, 0.36), "Fabric", e=0.45, basis=lean)
		for bx in (-1, 1):
			mb.blob(cb(sx + bx * 0.19, 2.25, 0.49), (0.042, 0.23, 0.085), "Fabric", e=0.4)
			mb.blob(cb(sx + bx * 0.20, 2.45, 0.82), (0.042, 0.08, 0.26), "Fabric", e=0.4, basis=lean)
		mb.blob(cb(sx, 2.53, 1.20), (0.105, 0.05, 0.095), "Fabric", e=0.4, basis=lean)
		for rx in (-0.19, 0.19):
			mb.box(cb(sx + rx, 2.25, 0.26), (0.024, 0.42, 0.034), "Steel")
	mb.blob(cb(0, 2.92, 0.44), (0.60, 0.21, 0.08), "Fabric", e=0.35)
	mb.blob(cb(0, 3.14, 0.84), (0.61, 0.07, 0.34), "Fabric", e=0.40)
	for hx in (-0.36, 0.0, 0.36):
		mb.blob(cb(hx, 3.16, 1.20), (0.095, 0.04, 0.08), "Fabric", e=0.4)
	return mb


def build_stripes(pj):
	mb = MB()
	for x in (-0.15, 0.15):
		pj.strip(mb, 0.15, S_SCUTTLE - 0.01, x - 0.065, x + 0.065, 36, 2, top_proj, "Stripe", offset=0.0018)
		pj.strip(mb, S_WS_TOP + 0.02, S_DECK - 0.03, x - 0.065, x + 0.065, 42, 2, top_proj, "Stripe", offset=0.0018)
	return mb


MARTINI_STRIPES = ((-0.19, -0.14, "MartiniDark"), (-0.14, -0.095, "MartiniLight"), (-0.095, 0.095, "MartiniRed"),
	(0.095, 0.14, "MartiniLight"), (0.14, 0.19, "MartiniDark"))


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
		pj.strip(mb, S_WS_TOP + 0.02, S_DECK - 0.03, x0, x1, 42, 1, top_proj, mat, offset=0.0035)

	def belt(u):
		return 0.72 + 0.04 * smoothstep(1.18, 2.90, u)
	us = [lerp(1.18, 2.90, i / 86) for i in range(87)]
	vs = [-0.072, -0.048, -0.024, 0.044]
	for side in (1, -1):
		sp = side_proj(side)
		pj.band(mb, us, vs, lambda u, v: 0.0045, lambda u, v: "MartiniDark" if v < -0.04 else "MartiniLight" if v < -0.01 else "MartiniRed",
			lambda u, v, sp=sp: sp(u, v + belt(u)))
		martini_roundel(pj, mb, sp, 1.72, 0.585, 0.095, -side)
	martini_roundel(pj, mb, top_proj, 0.62, 0.0, 0.095, 1)
	return mb


def build_abarth(pj):
	mb = MB()
	for side in (1, -1):
		sp = side_proj(side)
		pj.strip(mb, 1.18, 2.90, 0.35, 0.44, 38, 2, sp, "AbarthBlack", offset=0.0035)
		pj.strip(mb, 1.18, 2.90, 0.447, 0.459, 38, 1, sp, "AbarthRed", offset=0.0035)
		text_decal(pj, mb, sp, "ABARTH", 2.04, 0.395, 0.58, "AbarthWhite", 0.0050, -side)

	def plate(pts, mat, off, k=0.14, cu=0.52):
		pj.star(mb, [(cu + x * k, y * k) for x, y in pts], top_proj, mat, offset=off, rings=2, samples=2, skirt=0.0)
	plate([(-0.66, 0.0), (-0.12, 0.56), (0.60, 0.56), (0.60, -0.56), (-0.12, -0.56)], "AbarthWhite", 0.0030)
	plate([(-0.58, 0.0), (-0.10, 0.49), (0.53, 0.49), (0.53, -0.49), (-0.10, -0.49)], "AbarthRed", 0.0036)
	plate([(0.22, 0.49), (0.53, 0.49), (0.53, -0.49), (0.22, -0.49)], "AbarthYellow", 0.0042)
	text_decal(pj, mb, top_proj, "ABARTH", 0.52 + 0.375 * 0.14, 0.0, 0.10, "AbarthBlack", 0.0048, 1)
	return mb


def build_marlboro(pj):
	mb = MB()
	pj.star(mb, [(0.22, -0.46), (0.22, 0.46), (0.94, 0.46), (0.56, 0.0), (0.94, -0.46)], top_proj, "MarlboroRed",
		offset=0.0075, rings=14, samples=16, skirt=0.0)
	for side in (1, -1):
		sp = side_proj(side)
		pj.star(mb, [(1.30, 0.58), (1.30, 0.84), (2.82, 0.84), (2.42, 0.71), (2.82, 0.58)], sp, "MarlboroRed",
			offset=0.005, rings=8, samples=14, skirt=0.0)
		text_decal(pj, mb, sp, "Marlboro", 1.76, 0.71, 0.52, "MarlboroWhite", 0.0065, -side)
	return mb


def dent_delta(key, p):
	"""How far a crash moves the point p (Blender coords) at full damage on one side."""
	s = Y0 - p.y
	d = Vector()
	if key == "front":
		w = smoothstep(1.15, 0.0, s)
		d.y = -0.28 * w ** 1.2 * (1.0 + 0.25 * _nz(p, 0.3))
		d.z = -0.07 * w * (1.0 + _nz(p, 1.1)) + 0.05 * w * w * smoothstep(0.60, 0.80, p.z)
		d.x = 0.05 * w * _nz(p, 2.4)
	elif key == "rear":
		w = smoothstep(LENGTH - 0.90, LENGTH, s)
		d.y = 0.22 * w ** 1.2 * (1.0 + 0.25 * _nz(p, 0.9))
		d.z = -0.05 * w * (1.0 + _nz(p, 2.0))
		d.x = 0.04 * w * _nz(p, 3.1)
	else:
		side = -1.0 if key == "left" else 1.0
		if p.x * side > 0.2:
			g = math.exp(-((s - 2.05) / 0.65) ** 2 - ((p.z - 0.66) / 0.30) ** 2)
			d.x = -side * 0.10 * g * (1.0 + 0.3 * _nz(p, 4.2))
			d.z = -0.02 * g * _nz(p, 5.0)
	return d


def build_wheel():
	"""15" six-spoke sculpted Hyundai alloy with a 185/60 R15 tyre; axle along X, outer face towards +X."""
	mb = MB()
	hw = TYRE_W / 2
	R = TYRE_R
	rim = 0.1905  # 15" bead seat radius
	tyre = [(hw - 0.015, rim + 0.005), (hw + 0.002, rim + 0.020), (hw + 0.008, rim + 0.058), (hw + 0.006, R - 0.032),
		(hw - 0.006, R - 0.011), (hw - 0.024, R - 0.0015), (0.038, R), (0.032, R), (0.029, R - 0.008), (0.020, R - 0.008),
		(0.018, R), (-0.018, R), (-0.020, R - 0.008), (-0.029, R - 0.008), (-0.032, R), (-0.038, R), (-hw + 0.024, R - 0.0015),
		(-hw + 0.006, R - 0.011), (-hw - 0.006, R - 0.032), (-hw - 0.008, rim + 0.058), (-hw - 0.002, rim + 0.020),
		(-hw + 0.015, rim + 0.005)]

	def tyre_out(c):
		r = math.hypot(c.y, c.z)
		radial = Vector((0, c.y / r, c.z / r))
		return Vector((c.x, 0, 0)) * 2.0 + radial * (r - 0.245)
	mb.lathe(tyre, 56, "Tyre", out=tyre_out)
	for k in range(38):
		a = 2 * math.pi * k / 38
		for x0, x1 in ((0.040, hw - 0.015), (-hw + 0.015, -0.040)):
			pts = [Vector((x, (R + 0.0003) * math.cos(a + da), (R + 0.0003) * math.sin(a + da))) for x, da in
				((x0, 0.0), (x1, 0.034), (x1, 0.050), (x0, 0.016))]
			mb.poly(pts, "Grille", lambda q: Vector((0, q.y, q.z)))
	for k in range(4):
		a0 = 2 * math.pi * k / 4 + 0.25
		rows = []
		for r in (0.222, 0.254):
			rows.append([Vector((hw + 0.0082 - 0.0032 * (r - 0.222) / 0.032, r * math.cos(a0 + 0.8 * j / 8),
				r * math.sin(a0 + 0.8 * j / 8))) for j in range(9)])
		mb.grid(rows, "Sidewall", out=Vector((1, 0, 0)))

	barrel = [(hw - 0.004, rim - 0.004), (hw - 0.012, rim - 0.015), (0.056, rim - 0.025), (0.046, rim - 0.038), (0.026, rim - 0.042),
		(-0.04, rim - 0.042), (-0.052, rim - 0.032)]
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

	# 6 crisp sculpted Hyundai twin-flanged spokes (with 4-lug hub, true to the PB i20's 4x100 PCD)
	for k in range(6):
		a = 2 * math.pi * k / 6 + 0.25
		ca, sa = math.cos(a), math.sin(a)
		p_hub = Vector((0, 0.050 * ca, 0.050 * sa))
		p_end = Vector((0, 0.178 * ca, 0.178 * sa))
		bar(p_hub, p_end, 0.036, 0.044, 0.022, 0.018, 0.036, 0.060)
	mb.lathe([(0.036, 0.074), (0.050, 0.068), (0.054, 0.0)], 28, "Rim", out=lambda c: Vector((1, c.y, c.z)))
	for k in range(4):
		a = 2 * math.pi * k / 4 + math.pi / 4
		p = Vector((0.050, 0.050 * math.cos(a), 0.050 * math.sin(a)))
		mb.tube(p, p + Vector((0.011, 0, 0)), 0.0095, "Chrome", segs=6)
	mb.lathe([(0.010, 0.075), (0.010, 0.140), (0.002, 0.140), (0.002, 0.075)], 36, "BrakeDisc", out=lambda c: Vector((1.0, c.y, c.z)))
	mb.lathe([(0.0, 0.0), (0.0, 0.16), (-0.065, 0.16)], 28, "Under", out=lambda c: Vector((1.0, c.y, c.z)))
	mb.lathe([(0.052, 0.036), (0.060, 0.032), (0.064, 0.020), (0.0655, 0.0)], 24, "Steel", out=lambda c: Vector((1, c.y, c.z)))
	mb.disc(Vector((0.0656, 0, 0)), 0.016, "Chrome", normal=(1, 0, 0), segs=14)
	a_valve = 0.82
	v_base = Vector((0.040, 0.176 * math.cos(a_valve), 0.176 * math.sin(a_valve)))
	mb.tube(v_base, v_base + Vector((0.018, 0.006 * math.cos(a_valve), 0.006 * math.sin(a_valve))), 0.0038, "Trim", segs=6)
	return mb


# ---------------------------------------------------------------- previews
def render_all(cam, out_dir):
	views = {
		"front34": ((4.2, 4.8, 1.65), 38, None),
		"rear34": ((-4.2, -4.6, 1.75), 38, None),
		"side": ((8.0, 0.0, 0.75), 30, None),
		"front": ((0.0, 8.5, 0.8), 22, None),
		"rear": ((0.0, -8.5, 0.9), 22, None),
		"top": ((0.0, 0.0, 8.5), 30, None),
		"nose": ((-1.5, 4.0, 0.95), 30, (-0.1, Y0 - 0.15, 0.58)),
		"tail": ((1.3, -3.4, 1.05), 30, (0.1, Y0 - LENGTH + 0.15, 0.80)),
		"wheel": ((-1.9, Y0 - FRONT_AXLE_S + 0.55, 0.50), 30, (-TRACK_F / 2, Y0 - FRONT_AXLE_S, TYRE_R)),
	}
	carkit.render_views(cam, out_dir, views, (0, 0, 0.72))


LIVERY_VIEWS = {"stripes": ("Stripes", (0.55, 0.04, 0.05)), "martini": ("Martini", (0.92, 0.92, 0.9)),
	"abarth": ("Abarth", (0.75, 0.03, 0.04)), "marlboro": ("Marlboro", (0.92, 0.92, 0.9))}


def render_liveries(objs, cam, out_dir):
	tint = bpy.data.materials["Paint"].node_tree.nodes["Tint"]
	sock = next(s for s in tint.inputs if s.identifier == "A_Color")
	for key, (obj, paint) in LIVERY_VIEWS.items():
		for name in LIVERY_VIEWS.values():
			objs[name[0]].hide_render = name[0] != obj
		sock.default_value = (*paint, 1)
		views = {
			"front34": ((4.2, 4.8, 1.65), 38, None),
			"rear34": ((-4.2, -4.6, 1.75), 38, None),
			"side": ((8.0, 0.0, 0.75), 30, None),
			"top": ((0.0, 0.0, 8.5), 30, None),
		}
		carkit.render_views(cam, os.path.join(out_dir, key), views, (0, 0, 0.72))


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
	for i, v in enumerate(body.v):
		low = 1.0 - smoothstep(0.20, 0.64, v.z)
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
	for name in ("Body", "Details", "Stripes", "Martini", "Abarth", "Marlboro"):
		add_damage_keys(objs[name], dent_delta)
	kit.export_glb(OUT_GLB, texcoords=False)
	if arg("--blend"):
		bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(arg("--blend")))
	if arg("--renders"):
		view = next((k for k in ("martini", "abarth", "marlboro") if "--" + k in sys.argv), "")
		cam = carkit.setup_preview((0.92, 0.92, 0.9) if view in ("martini", "marlboro") else (0.14, 0.32, 0.62))
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
