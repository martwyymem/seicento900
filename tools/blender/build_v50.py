"""Builds the game's Volvo V50 (first generation, P1 platform, 2004-2007 estate, 2.4i) in Blender.

Run from the repository root (Blender 4.2 or newer, headless):

    blender -b -P tools/blender/build_v50.py -- [--renders DIR] [--blend FILE]

Writes godot/models/v50.glb. With --renders it also saves preview PNGs (front, rear, side, top, three-quarters).

The third campaign car, built after build_logan.py (see AGENTS.md, "Adding the next car"): same object and material
names, so race_car_visual.gd drives it unchanged. Real-car numbers: 4515 mm long, 1770 mm wide (without mirrors),
1452 mm high over the roof rails, 2640 mm wheelbase, 1535/1531 mm track, 205/55 R16 tyres on 16" five-spoke alloys.

A compact estate: a rounded nose with a domed, V-creased bonnet, a raked windscreen, a long roof with rails running back
to a small spoiler over a steep, near-vertical tailgate, Volvo's broad shoulders over a rising belt, black B- and
C-pillars and a cargo window whose rear edge leans forward with the D-pillar; body-coloured bumpers with a black lower
intake and round fog lamps, swept-back headlamps, the iron-mark grille (the diagonal bar and the circle-and-arrow), and
the tall tail lamps running up the D-pillars beside the rear screen.

Scene objects: Body (painted shell with glass, trim, body-coloured mirrors and handles, roof rails, underbody and cabin
liner; vertex colours carry the panel gaps), Details (lamps, grille, intakes, plates, wipers, exhaust, wheel wells),
Stripes, Martini, Abarth, Marlboro (liveries), Cabin (dash, wheel, seats, bench, console; hidden on distant cars), Wheel
(alloy wheel and tyre, one wheel at the origin, outer face towards +X).
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
OUT_GLB = os.path.join(ROOT, "godot", "models", "v50.glb")

# ---------------------------------------------------------------- real-car numbers
LENGTH = 4.515
WHEELBASE = 2.640
FRONT_AXLE_S = 0.880  # 880 mm front overhang, 995 mm rear (the estate's load floor runs out behind the rear axle)
REAR_AXLE_S = FRONT_AXLE_S + WHEELBASE
Y0 = FRONT_AXLE_S + WHEELBASE / 2.0
TRACK_F = 1.535
TRACK_R = 1.531
TYRE_R = 0.3160  # 205/55 R16: 406.4 mm rim + 2 x 112.75 mm sidewall = 631.9 mm
TYRE_W = 0.205
ARCH_R = 0.372
ROOF = 1.418  # the roof's crown; the rails stand 34 mm over it (1452 mm)

S_COWL, S_WS_TOP = 1.40, 2.12
S_SCUTTLE = 1.31
S_SAIL = 1.64
S_B0, S_B1 = 2.44, 2.54
S_C0, S_C1 = 3.30, 3.39  # the black C-pillar between the rear door's glass and the cargo window
S_QR = 4.07  # the cargo window's top edge starts to fall here ...
S_Q1 = 4.21  # ... to its rear corner on the belt: the window's rear edge leans forward with the D-pillar
S_RG0, S_RG1 = 4.265, 4.445  # the rear screen, from the spoiler down to the tailgate
S_DECK = 4.235  # the tailgate's top shut line, behind the roof
S_DOOR = (1.47, 2.49, 3.35)  # front door, B-pillar and the rear door's trailing edge in the C-pillar
FRIT = 0.015
PILLAR = 0.07


def bl(x, s, z):
	return Vector((x, Y0 - s, z))


# ---------------------------------------------------------------- body profile curves (metres)
# Plan, elevation and section lines for the V50: a rounded nose and a bonnet rising to the scuttle, a windscreen at
# ~29 deg, a long roof falling gently to the spoiler, a steep rear screen and tailgate; broad flanks with a full shoulder
# over a belt that rises from the A- to the D-pillar.
L = LENGTH
W = Curve([(0.0, 0.63), (0.03, 0.71), (0.08, 0.77), (0.16, 0.81), (0.30, 0.842), (0.55, 0.868), (0.9, 0.880),
	(1.4, 0.885), (3.6, 0.885), (4.05, 0.881), (4.25, 0.872), (4.37, 0.857), (4.44, 0.836), (4.48, 0.81), (4.50, 0.78),
	(4.510, 0.74), (L, 0.68)])
ZM = Curve([(0.0, 0.48), (0.3, 0.54), (1.0, 0.61), (1.5, 0.63), (3.5, 0.66), (4.2, 0.67), (L, 0.58)])  # the widest line
WSH = Curve([(0.0, 0.55), (0.03, 0.63), (0.07, 0.69), (0.14, 0.738), (0.3, 0.775), (0.6, 0.800), (1.0, 0.814),
	(1.5, 0.818), (3.0, 0.826), (3.7, 0.832), (4.1, 0.828), (4.28, 0.815), (4.38, 0.795), (4.44, 0.772), (4.48, 0.745),
	(4.50, 0.715), (4.510, 0.68), (L, 0.62)])
ZSH = Curve([(0.0, 0.64), (0.015, 0.72), (0.035, 0.775), (0.07, 0.805), (0.13, 0.822), (0.3, 0.840), (0.6, 0.862),
	(0.9, 0.886), (1.2, 0.912), (S_COWL, 0.930), (1.6, 0.950), (2.0, 0.963), (2.6, 0.980), (3.2, 1.000), (3.8, 1.025),
	(4.2, 1.042), (4.36, 1.048), (4.43, 1.040), (4.47, 1.015), (4.495, 0.96), (4.505, 0.86), (4.511, 0.74),
	(4.5135, 0.64), (L, 0.58)])
ZT = Curve([(0.0, 0.68), (0.015, 0.765), (0.035, 0.815), (0.07, 0.843), (0.13, 0.858), (0.3, 0.878), (0.6, 0.906),
	(0.9, 0.932), (1.2, 0.955), (S_COWL, 0.972), (1.55, 1.058), (1.70, 1.148), (1.85, 1.232), (2.0, 1.305),
	(S_WS_TOP, 1.352), (2.22, 1.382), (2.40, 1.405), (2.8, ROOF), (3.4, ROOF - 0.003), (3.9, 1.408), (4.15, 1.398),
	(S_RG0, 1.390), (4.30, 1.345), (4.35, 1.262), (4.40, 1.158), (S_RG1, 1.058), (4.465, 1.020), (4.485, 0.975),
	(4.498, 0.915), (4.507, 0.82), (4.512, 0.72), (4.5145, 0.64), (L, 0.60)])
ZB = Curve([(0.0, 0.285), (0.05, 0.262), (0.2, 0.243), (0.5, 0.225), (1.0, 0.205), (2.5, 0.200), (3.6, 0.210),
	(4.1, 0.24), (4.35, 0.27), (L, 0.31)])
WR = Curve([(0.0, 0.50), (0.04, 0.57), (0.09, 0.63), (0.16, 0.67), (0.35, 0.71), (0.7, 0.738), (S_COWL, 0.752),
	(1.6, 0.728), (S_WS_TOP, 0.690), (2.5, 0.672), (3.3, 0.668), (4.0, 0.660), (S_RG0, 0.640), (4.36, 0.636),
	(S_RG1, 0.650), (4.48, 0.668), (4.50, 0.655), (L, 0.56)])
DR = Curve([(0.0, 0.012), (0.2, 0.03), (S_COWL, 0.04), (S_WS_TOP - 0.05, 0.055), (4.2, 0.055), (S_RG1, 0.03), (4.48, 0.02),
	(L, 0.012)])

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
		if S_SAIL <= s <= S_B0 or S_B1 <= s <= S_C0 or S_C1 <= s <= S_Q1:
			return "Glass"
		if S_C0 < s < S_C1:
			return "Trim"
		if S_COWL <= s <= S_B1:
			return "Trim"
		return "Paint"
	if seg == SEG_GH:
		return "Trim" if S_B0 < s < S_B1 or S_C0 < s < S_C1 else "Paint"
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
	forced = [0.0, LENGTH, S_SCUTTLE, S_COWL, S_COWL + FRIT, S_WS_TOP - FRIT, S_WS_TOP, S_SAIL, S_B0, S_B1, S_C0, S_C1, S_QR,
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
	"RoofRail": ((0.50, 0.51, 0.53), 0.32, 0.85, {}),
	"Fog": ((0.70, 0.72, 0.74), 0.08, 0.6, {"emit": ((1.0, 0.95, 0.84), 0.1)}),
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
	# door mirrors: body-coloured shells on a black foot at the sail, glass facing back (Paint only on the Body mesh)
	for side in (1, -1):
		mb.box(bl(side * 0.855, 1.66, 0.985), (0.06, 0.09, 0.045), "Trim")
		mb.blob(bl(side * 0.922, 1.70, 1.035), (0.072, 0.052, 0.060), "Paint", e=0.5)
		mb.blob(bl(side * 0.922, 1.749, 1.035), (0.064, 0.006, 0.048), "Chrome", e=0.35)
		# body-coloured pull handles, proud of the doors under the belt
		for hs in (2.27, 3.24):
			x = W(hs) - 0.012
			mb.blob(bl(side * (x + 0.004), hs, 0.905 + 0.02 * (hs - 2.27)), (0.010, 0.075, 0.016), "Paint", e=0.4)
	return mb


def build_rails(body):
	"""The roof rails: two silver bars on black feet along the roof's edges (the roof's crown is 1418 mm, the rails 1452)."""
	pj = Projector(body)
	mb = MB()
	for side in (1, -1):
		pts = []
		for k in range(25):
			s = lerp(2.34, 4.12, k / 24)
			loc = pj.hit(bl(side * 0.585, s, 3.0), Vector((0, 0, -1)))[0]
			pts.append(loc)
		top = ROOF + 0.034 - 0.011
		rail = [Vector((p.x, p.y, max(p.z + 0.026, top - 0.012 * smoothstep(3.0, 4.12, Y0 - p.y)))) for p in pts]
		for a, b in zip(rail, rail[1:]):
			mb.tube(a, b, 0.011, "RoofRail", segs=8, caps=False)
		mb.tube(rail[0] + Vector((0, 0.03, -0.004)), rail[0], 0.011, "RoofRail", segs=8)
		mb.tube(rail[-1], rail[-1] + Vector((0, -0.03, -0.004)), 0.011, "RoofRail", segs=8)
		for k in (0, 12, 24):
			p = pts[k]
			mb.box(Vector((p.x, p.y + (0.02 if k == 0 else -0.02 if k == 24 else 0.0), (p.z + rail[k].z) / 2 - 0.004)),
				(0.020, 0.06, rail[k].z - p.z + 0.004), "Trim")
	return mb
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

# the headlamp (x across the car, z height, seen from the front): a long lamp swept back into the wing, its inner end
# square beside the grille, the top edge under the bonnet's shut line, the lower edge rising outwards to a point high in
# the wing. The tail lamp, seen from behind: tall, on the body's rear corner, wide at the bumper and narrowing up the
# D-pillar beside the rear screen to its top at the spoiler.
HEADLAMP = [(0.322, 0.650), (0.322, 0.780), (0.334, 0.798), (0.42, 0.804), (0.55, 0.809), (0.66, 0.815), (0.74, 0.821),
	(0.785, 0.824), (0.810, 0.814), (0.816, 0.790), (0.808, 0.762), (0.787, 0.736), (0.747, 0.711), (0.68, 0.690),
	(0.58, 0.672), (0.46, 0.658), (0.36, 0.650)]
HEAD_AMBER = [(0.752, 0.738), (0.752, 0.770), (0.778, 0.790), (0.797, 0.790), (0.801, 0.772), (0.792, 0.752), (0.772, 0.740)]
TAIL_OUT = [(0.570, 0.705), (0.570, 0.95), (0.585, 1.05), (0.610, 1.13), (0.632, 1.20), (0.648, 1.25), (0.670, 1.27),
	(0.695, 1.255), (0.712, 1.20), (0.738, 1.12), (0.772, 1.04), (0.800, 0.95), (0.815, 0.86), (0.812, 0.76), (0.80, 0.705)]


def dense(pts, step=0.03):
	"""An outline with extra points along its long straight edges, so the projector's spline resampling keeps them straight."""
	out = []
	for i, a in enumerate(pts):
		b = pts[(i + 1) % len(pts)]
		n = max(1, int(math.hypot(b[0] - a[0], b[1] - a[1]) / step))
		out += [(lerp(a[0], b[0], k / n), lerp(a[1], b[1], k / n)) for k in range(n)]
	return out


def clip_band(poly, z0, z1):
	"""The part of an outline between two heights (Sutherland-Hodgman against z >= z0 and z <= z1)."""
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
	"""The outline moved in by about d (each point towards the centroid by d)."""
	cu = sum(p[0] for p in poly) / len(poly)
	cv = sum(p[1] for p in poly) / len(poly)
	out = []
	for u, v in poly:
		l = math.hypot(u - cu, v - cv) or 1.0
		out.append((u + (cu - u) / l * d, v + (cv - v) / l * d))
	return out


TAIL_OUT = dense(TAIL_OUT, 0.02)
TAIL_RED = inset(clip_band(TAIL_OUT, 0.952, 2.0), 0.007)  # the red lamp up the pillar ...
TAIL_LOW = inset(clip_band(TAIL_OUT, 0.705, 0.858), 0.007)  # ... and the red foot over the bumper
TAIL_AMBER = inset(clip_band(TAIL_OUT, 0.908, 0.946), 0.007)  # the indicator and the reversing lamp between them
TAIL_CLEAR = inset(clip_band(TAIL_OUT, 0.864, 0.902), 0.007)
# the iron mark's diagonal bar across the grille, from its top corner on the viewer's left to the bottom on the right
IRON_BAR = [(0.262, 0.780), (0.262, 0.757), (-0.236, 0.610), (-0.236, 0.633)]
GRILLE = [(-0.262, 0.797), (0.262, 0.797), (0.270, 0.782), (0.258, 0.660), (0.236, 0.610), (-0.236, 0.610), (-0.258, 0.660),
	(-0.270, 0.782)]


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
	"""The V50's body-coloured bumpers are the shell itself: here only the black parts set into them (the lower intake
	with its mesh and the fog lamps, the number plates), the iron-mark grille between the headlamps, the bonnet's shut
	line, and the rear bumper's black lower valance with its reflectors."""
	fp = cyl_proj(FB_AXIS, False)
	# the lower intake: a wide black mouth with a mesh and a body-coloured bar across it
	mouth = [(-0.45, 0.405), (0.45, 0.405), (0.47, 0.37), (0.43, 0.275), (0.40, 0.262), (-0.40, 0.262), (-0.43, 0.275),
		(-0.47, 0.37)]
	pj.star(mb, dense(mouth, 0.04), front_proj, "Trim", offset=0.0015, rings=1, samples=2, skirt=0.0)
	pj.star(mb, dense(inset(mouth, 0.012), 0.04), front_proj, "Grille", offset=0.0025, rings=1, samples=2, skirt=0.0)
	for z in (0.300, 0.335, 0.370):
		pj.strip(mb, -0.43, 0.43, z, z + 0.006, 30, 1, front_proj, "Trim", offset=0.0045)
	# fog lamps in round black housings at the corners of the bumper
	for side in (1, -1):
		hp = lambda u, v, side=side: front_proj(side * u, v)
		pj.star(mb, rounded_rect(0.57, 0.715, 0.285, 0.405, 0.05), hp, "Trim", offset=0.0015, rings=2, samples=2, skirt=0.0)
		pj.star(mb, ellipse(0.643, 0.345, 0.045, 0.045, 20), hp, "Chrome", offset=0.0040, rings=2, samples=2, skirt=0.0)
		pj.star(mb, ellipse(0.643, 0.345, 0.038, 0.038, 20), hp, "Fog", offset=0.0060, bulge=0.003, rings=2, samples=2, skirt=0.0)
	# front number plate on the bumper under the grille: a European plate 520 x 110 mm
	pj.star(mb, rounded_rect(-0.264, 0.264, 0.439, 0.5557, 0.006), front_proj, "Trim", offset=0.0035, rings=1, samples=2, skirt=0.006)
	pj.star(mb, rounded_rect(-0.2559, 0.2559, 0.445, 0.5497, 0.004), front_proj, "Plate", offset=0.0065, rings=1, samples=2,
		skirt=0.0)  # car_plate.gdshader maps the atlas from these numbers (CarCatalog V50_VISUAL plate_y)
	# the grille: a chrome surround, black mesh with fine vertical bars, the iron mark's chrome diagonal and its circle and arrow
	pj.star(mb, dense(GRILLE, 0.04), front_proj, "Chrome", offset=0.0030, rings=1, samples=2, skirt=0.004)
	pj.star(mb, dense(inset(GRILLE, 0.011), 0.04), front_proj, "Grille", offset=0.0045, rings=1, samples=2, skirt=0.0)
	for k in range(-8, 9):
		x = k * 0.029
		pj.strip(mb, x - 0.003, x + 0.003, 0.622, 0.786, 1, 6, front_proj, "Trim", offset=0.0060)
	pj.star(mb, IRON_BAR, front_proj, "Chrome", offset=0.0090, rings=1, samples=4, skirt=0.003)
	cz = 0.6955
	pj.star(mb, ellipse(0.0, cz, 0.058, 0.058, 28), front_proj, "Gasket", offset=0.0095, rings=2, samples=2, skirt=0.003)
	for poly, mat, off in ((ellipse(0.0, cz, 0.052, 0.052, 28), "Chrome", 0.0120), (ellipse(0.0, cz, 0.040, 0.040, 28), "Grille", 0.0135)):
		pj.star(mb, poly, front_proj, mat, offset=off, rings=2, samples=2, skirt=0.0)
	# the arrow off the circle, pointing up and to the viewer's right (-x)
	ax, az = -0.030, cz + 0.030
	pj.star(mb, [(ax + 0.010, az - 0.010), (ax - 0.006, az + 0.006), (ax - 0.026, az + 0.026), (ax - 0.024, az + 0.004),
		(ax + 0.0, az + 0.004)], front_proj, "Chrome", offset=0.0140, rings=1, samples=2, skirt=0.002)
	pj.strip(mb, -0.032, 0.032, cz - 0.009, cz + 0.009, 6, 1, front_proj, "Chrome", offset=0.0150)  # the VOLVO bar in the ring
	# the bonnet's leading shut line, over the grille and the headlamps
	pj.strip(mb, -0.80, 0.80, 0.826, 0.831, 60, 1, front_proj, "Gasket", offset=0.0012)
	# rear: a black lower valance wrapped round to the rear arches, with a reflector each side
	rp = cyl_proj(RB_AXIS, True)
	rows = [(0.312, -0.002), (0.320, 0.008), (0.332, 0.011), (0.398, 0.011), (0.408, 0.007), (0.414, -0.001)]
	vs = sorted(set([r[0] for r in rows] + spread(0.34, 0.39, 0.02)))
	wrap_band(pj, mb, rp, REAR_AXLE_S, False, vs, lambda v, rows=rows: profile(v, rows), "Bumper", reach=0.9)


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
		# headlamp: a black housing standing proud of the shell, the bezel, amber indicator in the outer point, a big
		# projector bowl inboard and the main-beam reflector beside it, the clear domed cover
		hp = lambda u, v, side=side: front_proj(side * u, v)
		pj.star(mb, dense(HEADLAMP, 0.03), hp, "Gasket", offset=0.012, rings=5, samples=3, skirt=0.012)
		pj.star(mb, dense(shrink(HEADLAMP, 0.05), 0.03), hp, "LampBezel", offset=0.0135, bulge=0.0, rings=7, samples=3, skirt=0.0)
		pj.star(mb, HEAD_AMBER, hp, "Indicator", offset=0.018, bulge=0.003, rings=5, samples=4, skirt=0.0)
		reflector(mb, pj, hp, 0.410, 0.729, 0.058)
		reflector(mb, pj, hp, 0.565, 0.743, 0.052)
		pj.strip(mb, 0.484, 0.492, 0.672, 0.800, 1, 8, hp, "Chrome", offset=0.026)
		pj.star(mb, dense(shrink(HEADLAMP, 0.03), 0.03), hp, "LampGlass", offset=0.034, bulge=0.010, rings=7, samples=3, skirt=0.020)

		# tail lamp: gasket, the red upper part with the reflector behind it, amber indicator and the clear reversing lamp
		# at the foot, then the lenses
		tp = lambda u, v, side=side: rear_proj(side * u, v)
		pj.star(mb, TAIL_OUT, tp, "Gasket", offset=0.004, rings=5, samples=2, skirt=0.004)
		for poly in (TAIL_RED, TAIL_LOW):
			pj.star(mb, poly, tp, "Taillight", offset=0.010, rings=5, samples=2, skirt=0.0)
			pj.star(mb, shrink(poly, 0.25), tp, "TailBulb", offset=0.0115, rings=4, samples=2, skirt=0.0)
			pj.star(mb, poly, tp, "TailGlass", offset=0.015, bulge=0.002, rings=5, samples=2, skirt=0.005)
		pj.star(mb, TAIL_AMBER, tp, "Indicator", offset=0.0125, rings=5, samples=3, skirt=0.0)
		pj.star(mb, TAIL_CLEAR, tp, "LampClear", offset=0.0125, rings=5, samples=3, skirt=0.0)
		pj.star(mb, inset(clip_band(TAIL_OUT, 0.862, 0.948), 0.007), tp, "LampGlass", offset=0.0165, rings=5, samples=3, skirt=0.004)
		# the rear reflector in the black valance
		pj.star(mb, rounded_rect(0.56, 0.70, 0.352, 0.372, 0.008), tp, "Taillight", offset=0.013, rings=1, samples=2, skirt=0.0)

		pj = pj_all
		sp = side_proj(side)
		# front wing side repeater, behind the arch
		pj.star(mb, ellipse(1.36, 0.80, 0.026, 0.011, 12), sp, "Gasket", offset=0.002, rings=1, samples=2)
		pj.star(mb, ellipse(1.36, 0.80, 0.020, 0.007, 12), sp, "Indicator", offset=0.004, bulge=0.002, rings=2, samples=2)
		# the lock barrel at the front of the driver's handle
		pj.star(mb, ellipse(2.27 - 0.095, 0.905, 0.009, 0.009, 10), sp, "Chrome", offset=0.004, rings=1, samples=1)
		# a dark recess behind each handle
		for hs in (2.27, 3.24):
			pj.star(mb, rounded_rect(hs - 0.07, hs + 0.07, 0.905 + 0.02 * (hs - 2.27) - 0.024, 0.905 + 0.02 * (hs - 2.27) + 0.012,
				0.012), sp, "Gasket", offset=0.0012, rings=1, samples=2)

		# wheel-well liners (black arcs sealing the shell)
		for sc, tr in ((FRONT_AXLE_S, TRACK_F), (REAR_AXLE_S, TRACK_R)):
			rows = []
			for xo in (0.50, 0.78):
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

	# fuel flap on the right rear wing, over the arch: its shut line
	spr = side_proj(1)
	for u0, u1, v0, v1, nu, nv in ((3.93, 4.06, 0.832, 0.837, 8, 1), (3.93, 4.06, 0.933, 0.938, 8, 1), (3.927, 3.932, 0.832, 0.938, 1, 6),
			(4.058, 4.063, 0.832, 0.938, 1, 6)):
		pj.strip(mb, u0, u1, v0, v1, nu, nv, spr, "Gasket", offset=0.0010)

	# tailgate: the plate in its recess, a chrome handle strip over it, the VOLVO lettering and the badge, shut lines
	pj.star(mb, rounded_rect(-0.268, 0.268, 0.694, 0.8107, 0.012), rear_proj, "Gasket", offset=0.0015, rings=1, samples=2, skirt=0.0)
	pj.star(mb, rounded_rect(-0.2559, 0.2559, 0.700, 0.8047, 0.004), rear_proj, "Plate", offset=0.004, rings=1, samples=2, skirt=0.0)
	pj.star(mb, rounded_rect(-0.25, 0.25, 0.826, 0.846, 0.008), rear_proj, "Chrome", offset=0.004, rings=1, samples=2, skirt=0.002)
	text_decal(pj, mb, rear_proj, "VOLVO", 0.004, 0.905 - 0.005, 0.24, "Gasket", 0.0035, 1)
	text_decal(pj, mb, rear_proj, "VOLVO", 0.0, 0.905, 0.24, "Chrome", 0.0060, 1)
	text_decal(pj, mb, rear_proj, "V50", 0.404, 0.873 - 0.004, 0.085, "Gasket", 0.0035, 1)
	text_decal(pj, mb, rear_proj, "V50", 0.40, 0.873, 0.085, "Chrome", 0.0060, 1)
	for x in (-0.562, 0.562):  # down the tailgate's edges beside the lamps
		pj.strip(mb, x + 0.003, x - 0.003, 0.630, 1.02, 1, 14, rear_proj, "Gasket", offset=0.0015)
	pj.strip(mb, -0.562, 0.562, 0.627, 0.633, 30, 1, rear_proj, "Gasket", offset=0.0015)  # over the bumper
	pj.strip(mb, S_DECK - 0.003, S_DECK + 0.003, -0.62, 0.62, 1, 40, top_proj, "Gasket", offset=0.0012)  # the roof's end
	# the spoiler's black lip over the rear screen and the high-level brake lamp in it
	pj.strip(mb, -0.56, 0.56, 1.360, 1.388, 40, 1, rear_proj, "Trim", offset=0.006)
	pj.strip(mb, -0.14, 0.14, 1.366, 1.380, 12, 1, rear_proj, "Taillight", offset=0.0085)
	# the rear wiper parked at the foot of the screen
	base_p = pj.hit(*rear_proj(0.0, 1.08))[0]
	mb.blob(base_p + Vector((0, -0.012, 0)), (0.022, 0.016, 0.022), "Trim", e=0.3)
	tip = pj.hit(*rear_proj(0.40, 1.11))[0]
	mb.tube(base_p + Vector((0, -0.016, 0.004)), tip + Vector((0, -0.010, 0)), 0.006, "Trim", segs=6)

	# scuttle washer jets and wipers parked along the base of the windscreen
	for x in (-0.30, 0.30):
		pj.star(mb, ellipse(S_SCUTTLE + 0.02, x, 0.012, 0.008, 8), top_proj, "Trim", offset=0.004, rings=1, samples=1)
	for xp, x1 in ((-0.55, 0.00), (0.06, 0.64)):
		base_p = pj.hit(*top_proj(S_SCUTTLE + 0.06, xp))[0]
		mb.blob(base_p + Vector((0, 0, 0.010)), (0.018, 0.018, 0.014), "Trim", e=0.3)
		a = base_p + Vector((0, 0, 0.018))
		b = pj.hit(*top_proj(S_SCUTTLE + 0.20, x1))[0] + Vector((0, 0, 0.016))
		mb.tube(a, b, 0.006, "Trim", segs=6)
		bx0 = pj.hit(*top_proj(S_SCUTTLE + 0.18, xp + 0.05))[0] + Vector((0, 0, 0.012))
		bx1 = pj.hit(*top_proj(S_SCUTTLE + 0.23, x1 + 0.02))[0] + Vector((0, 0, 0.012))
		mb.box((bx0 + bx1) / 2, ((bx1 - bx0).length, 0.012, 0.012), "Trim",
			basis=Matrix.Rotation(math.atan2(bx1.y - bx0.y, bx1.x - bx0.x), 3, "Z"))

	# the short aerial at the back of the roof
	base = pj.hit(*top_proj(4.02, 0.0))[0]
	mb.blob(base + Vector((0, 0, 0.010)), (0.020, 0.032, 0.013), "Trim", e=0.4)
	mb.tube(base + Vector((0, 0, 0.016)), base + Vector((0, -0.12, 0.16)), 0.004, "Trim", segs=6)

	# exhaust: a single tailpipe under the right of the rear valance
	mb.tube(bl(0.26, 3.95, 0.27), bl(-0.22, 3.95, 0.27), 0.08, "Steel", segs=14)
	mb.tube(bl(0.42, 4.05, 0.262), bl(0.42, LENGTH + 0.005, 0.268), 0.026, "Exhaust", segs=14, caps=False)
	mb.ring(bl(0.42, LENGTH + 0.005, 0.268), 0.022, 0.027, "Exhaust", normal=(0, -1, 0), segs=14)
	mb.disc(bl(0.42, LENGTH - 0.005, 0.268), 0.023, "Under", normal=(0, -1, 0), segs=14)

	# underbody: sump guard, engine bay and load floor closed off, flat floor
	mb.box(bl(0, 0.90, 0.215), (0.80, 0.8, 0.03), "Steel")
	mb.box(bl(0, 0.80, 0.45), (1.15, 1.05, 0.40), "Under")
	mb.box(bl(0, 4.08, 0.45), (1.15, 0.80, 0.40), "Under")
	mb.box(bl(0, 2.30, 0.225), (0.95, 2.3, 0.07), "Under")

	return mb, pj


def build_cabin():
	"""The cabin silhouette: facia with instrument hood and centre stack, a three-spoke wheel, two front seats, the rear
	bench, the gear lever and the rear-view mirror. Godot drops it on distant cars; it is seen through the glass."""
	mb = MB()

	def cb(x, s, z):  # the Logan's cabin moved back to the V50's cowl and down under its lower roof
		return bl(x, s + 0.15, z - 0.06)
	mb.blob(cb(0, 1.62, 0.90), (0.66, 0.20, 0.09), "Interior", e=0.3)
	mb.box(cb(0, 1.53, 0.64), (1.40, 0.14, 0.44), "Interior")
	mb.box(cb(0, 1.75, 0.66), (0.26, 0.30, 0.40), "Interior")  # centre stack and console
	mb.box(cb(0, 2.08, 0.40), (0.24, 0.78, 0.18), "Interior")  # tunnel console between the seats
	mb.blob(cb(-0.37, 1.68, 1.02), (0.17, 0.10, 0.06), "Interior", e=0.35)  # instrument hood
	mb.disc(cb(-0.37, 1.66, 1.00), 0.055, "Plate", normal=(0, -0.6, 0.8), segs=16)
	for sx in (-0.07, 0.07):
		mb.disc(cb(sx, 1.72, 0.90), 0.026, "Trim", normal=(0, -0.4, 0.9), segs=12)
		mb.ring(cb(sx, 1.72, 0.90), 0.023, 0.028, "Chrome", normal=(0, -0.4, 0.9), segs=12)
	# gear lever and gaiter, handbrake
	mb.blob(cb(0, 1.98, 0.50), (0.06, 0.07, 0.04), "Trim", e=0.3)
	mb.tube(cb(0, 1.98, 0.52), cb(0, 2.00, 0.72), 0.009, "Chrome", segs=8)
	mb.blob(cb(0, 2.00, 0.73), (0.022, 0.022, 0.026), "Seat", e=0.35)
	mb.tube(cb(0.07, 2.30, 0.50), cb(0.07, 2.38, 0.58), 0.010, "Interior", segs=6)
	# pedals
	for px in (-0.46, -0.38, -0.30):
		mb.box(cb(px, 1.58, 0.30), (0.05, 0.012, 0.075), "Steel")
	# the rear-view mirror
	mb.box(cb(0, 1.92, 1.36), (0.13, 0.015, 0.045), "Interior")
	mb.tube(cb(0, 1.93, 1.37), cb(0, 1.95, 1.40), 0.006, "Trim", segs=6)
	# the three-spoke wheel, in front of the driver (left-hand drive: the driver sits on the left as seen from behind)
	tilt = math.radians(66)
	n = Vector((0, -math.cos(tilt), math.sin(tilt)))
	u = Vector((1, 0, 0))
	v = n.cross(u)
	sw = cb(-0.37, 1.90, 0.99)
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
		mb.blob(cb(sx, 2.35, 0.43), (0.23, 0.26, 0.085), "Fabric", e=0.40)
		mb.blob(cb(sx, 2.58, 0.80), (0.24, 0.08, 0.37), "Fabric", e=0.45, basis=lean)
		for bx in (-1, 1):
			mb.blob(cb(sx + bx * 0.20, 2.35, 0.48), (0.045, 0.24, 0.09), "Fabric", e=0.4)
			mb.blob(cb(sx + bx * 0.21, 2.55, 0.80), (0.045, 0.08, 0.27), "Fabric", e=0.4, basis=lean)
		mb.blob(cb(sx, 2.64, 1.18), (0.11, 0.05, 0.10), "Fabric", e=0.4, basis=lean)
		for rx in (-0.2, 0.2):
			mb.box(cb(sx + rx, 2.35, 0.26), (0.025, 0.45, 0.035), "Steel")
	# the rear bench: cushion, back and three headrests
	mb.blob(cb(0, 3.0, 0.43), (0.62, 0.22, 0.08), "Fabric", e=0.35)
	mb.blob(cb(0, 3.23, 0.82), (0.64, 0.07, 0.34), "Fabric", e=0.40)
	for hx in (-0.38, 0.0, 0.38):
		mb.blob(cb(hx, 3.25, 1.19), (0.10, 0.04, 0.08), "Fabric", e=0.4)
	return mb


def build_stripes(pj):
	mb = MB()
	for x in (-0.16, 0.16):
		pj.strip(mb, 0.17, S_SCUTTLE - 0.01, x - 0.07, x + 0.07, 40, 2, top_proj, "Stripe", offset=0.0018)
		pj.strip(mb, S_WS_TOP + 0.02, S_DECK - 0.03, x - 0.07, x + 0.07, 48, 2, top_proj, "Stripe", offset=0.0018)
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
		pj.strip(mb, S_WS_TOP + 0.02, S_DECK - 0.03, x0, x1, 48, 1, top_proj, mat, offset=0.0035)

	def belt(u):
		return 0.75 - 0.03 * smoothstep(1.3, 3.1, u)
	us = [lerp(1.30, 3.10, i / 90) for i in range(91)]
	vs = [-0.075, -0.05, -0.025, 0.045]
	for side in (1, -1):
		sp = side_proj(side)
		pj.band(mb, us, vs, lambda u, v: 0.0045, lambda u, v: "MartiniDark" if v < -0.04 else "MartiniLight" if v < -0.01 else "MartiniRed",
			lambda u, v, sp=sp: sp(u, v + belt(u)))
		martini_roundel(pj, mb, sp, 1.90, 0.590, 0.10, -side)
	martini_roundel(pj, mb, top_proj, 0.85, 0.0, 0.1, 1)
	return mb


def build_abarth(pj):
	mb = MB()
	for side in (1, -1):
		sp = side_proj(side)
		pj.strip(mb, 1.30, 3.10, 0.36, 0.45, 40, 2, sp, "AbarthBlack", offset=0.0035)
		pj.strip(mb, 1.30, 3.10, 0.457, 0.469, 40, 1, sp, "AbarthRed", offset=0.0035)
		text_decal(pj, mb, sp, "ABARTH", 2.20, 0.405, 0.62, "AbarthWhite", 0.0050, -side)

	def plate(pts, mat, off, k=0.15, cu=0.60):
		pj.star(mb, [(cu + x * k, y * k) for x, y in pts], top_proj, mat, offset=off, rings=2, samples=2, skirt=0.0)
	plate([(-0.66, 0.0), (-0.12, 0.56), (0.60, 0.56), (0.60, -0.56), (-0.12, -0.56)], "AbarthWhite", 0.0030)
	plate([(-0.58, 0.0), (-0.10, 0.49), (0.53, 0.49), (0.53, -0.49), (-0.10, -0.49)], "AbarthRed", 0.0036)
	plate([(0.22, 0.49), (0.53, 0.49), (0.53, -0.49), (0.22, -0.49)], "AbarthYellow", 0.0042)
	text_decal(pj, mb, top_proj, "ABARTH", 0.60 + 0.375 * 0.15, 0.0, 0.11, "AbarthBlack", 0.0048, 1)
	return mb


def build_marlboro(pj):
	mb = MB()
	pj.star(mb, [(0.30, -0.50), (0.30, 0.50), (1.10, 0.50), (0.68, 0.0), (1.10, -0.50)], top_proj, "MarlboroRed",
		offset=0.005, rings=8, samples=14, skirt=0.0)
	for side in (1, -1):
		sp = side_proj(side)
		pj.star(mb, [(1.52, 0.60), (1.52, 0.86), (3.00, 0.86), (2.58, 0.73), (3.00, 0.60)], sp, "MarlboroRed",
			offset=0.005, rings=8, samples=14, skirt=0.0)
		text_decal(pj, mb, sp, "Marlboro", 1.95, 0.73, 0.56, "MarlboroWhite", 0.0065, -side)
	return mb


def dent_delta(key, p):
	"""How far a crash moves the point p (Blender coords) at full damage on one side (see build_seicento.dent_delta)."""
	s = Y0 - p.y
	d = Vector()
	if key == "front":
		w = smoothstep(1.3, 0.0, s)
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
			g = math.exp(-((s - 2.3) / 0.70) ** 2 - ((p.z - 0.66) / 0.30) ** 2)
			d.x = -side * 0.10 * g * (1.0 + 0.3 * _nz(p, 4.2))
			d.z = -0.02 * g * _nz(p, 5.0)
	return d


def build_wheel():
	"""16" five-double-spoke alloy with a 205/55 R16 tyre; axle along X, outer face towards +X."""
	mb = MB()
	hw = TYRE_W / 2
	R = TYRE_R
	rim = 0.2032  # 16" bead seat radius
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
			sect = [(-w / 2, 0.0), (w / 2, 0.0), (w / 2, h * 0.62), (w * 0.38, h), (-w * 0.38, h), (-w / 2, h * 0.62)]
			rows.append([Vector((xb + hh, 0, 0)) + c + t * ww for ww, hh in sect])

		def outward(q):
			v = Vector((q.x - (base0 + h0 / 2), q.y - p0.y, q.z - p0.z))
			return v - Vector((0, d.y, d.z)) * (v.y * d.y + v.z * d.z)
		mb.grid(rows, "Rim", closed=True, out=outward, cap_ends=True)

	for k in range(5):  # five pairs of slim spokes, each pair splaying from the hub to the rim's lip
		for da in (-0.13, 0.13):
			a = 2 * math.pi * k / 5 + 0.3
			ca, sa = math.cos(a + da * 0.35), math.sin(a + da * 0.35)
			ce, se = math.cos(a + da), math.sin(a + da)
			p_hub = Vector((0, 0.052 * ca, 0.052 * sa))
			p_end = Vector((0, 0.190 * ce, 0.190 * se))
			bar(p_hub, p_end, 0.030, 0.034, 0.022, 0.018, 0.042, 0.068)
	mb.lathe([(0.042, 0.080), (0.056, 0.074), (0.060, 0.0)], 28, "Rim", out=lambda c: Vector((1, c.y, c.z)))
	for k in range(5):
		a = 2 * math.pi * k / 5 + math.pi / 5
		p = Vector((0.056, 0.0575 * math.cos(a), 0.0575 * math.sin(a)))
		mb.tube(p, p + Vector((0.012, 0, 0)), 0.0100, "Chrome", segs=6)
	mb.lathe([(0.012, 0.080), (0.012, 0.150), (0.003, 0.150), (0.003, 0.080)], 36, "BrakeDisc", out=lambda c: Vector((1.0, c.y, c.z)))
	mb.lathe([(0.0, 0.0), (0.0, 0.17), (-0.07, 0.17)], 28, "Under", out=lambda c: Vector((1.0, c.y, c.z)))
	mb.lathe([(0.058, 0.040), (0.066, 0.036), (0.070, 0.022), (0.0715, 0.0)], 24, "Steel", out=lambda c: Vector((1, c.y, c.z)))
	mb.disc(Vector((0.0716, 0, 0)), 0.018, "BadgeBlue", normal=(1, 0, 0), segs=14)
	a_valve = 0.82
	v_base = Vector((0.046, 0.189 * math.cos(a_valve), 0.189 * math.sin(a_valve)))
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
	for name in ("Body", "Details", "Stripes", "Martini", "Abarth", "Marlboro"):
		add_damage_keys(objs[name], dent_delta)
	kit.export_glb(OUT_GLB, texcoords=False)
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
		render_all(cam, out)
		if not view:
			render_liveries(objs, cam, out)


if __name__ == "__main__":
	main()
