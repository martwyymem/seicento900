"""Builds the game's Dacia Sandero (first generation, B90, 2008-2012, five-door hatchback, 1.6 MPI) in Blender.

Run from the repository root (Blender 4.2 or newer, headless):

    blender -b -P tools/blender/build_sandero.py -- [--renders DIR] [--blend FILE]

Writes godot/models/sandero.glb. With --renders it also saves preview PNGs (front, rear, side, top, three-quarters).

The fifth campaign car, built after build_i20.py and build_logan.py (see AGENTS.md, "Adding the next car"): same
object and material names, so race_car_visual.gd drives it unchanged. Real-car numbers: 4020 mm long, 1746 mm wide
(without mirrors), 1534 mm high, 2588 mm wheelbase, 1480/1469 mm track, 185/65 R15 tyres on 15" five-spoke alloys.

A chunky, practical European 5-door hatchback: rounded sloped supermini nose, wide trapezoid upper grille crowned by
a thick chrome bar and the Mk1 Dacia shield emblem, large curved wrap-around wedge headlamps with dual reflector bowls
and amber wing-corner indicators, sculpted lower bumper intake flanked by round fog-light pods, prominent rounded
wheel-arch flares, upright 5-door greenhouse with slightly upswept rear quarter glass, sculpted rounded hatchback
tailgate with tall vertical-wedge red/clear tail lamps flanking the rear window and a recessed rear plate.

Scene objects: Body (painted shell with glass, trim, body-coloured mirrors, underbody and cabin liner; vertex colours
carry the panel gaps), Details (lamps, trapezoid grille, Dacia shield badges, intakes, fog pods, plates, side strips,
wipers, exhaust, wheel wells), Stripes, Martini, Abarth, Marlboro (liveries), Cabin (dash, wheel, seats, bench,
console; hidden on distant cars), Wheel (five-spoke alloy and tyre, one wheel at the origin, outer face towards +X).
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
OUT_GLB = os.path.join(ROOT, "godot", "models", "sandero.glb")

# ---------------------------------------------------------------- real-car numbers
LENGTH = 4.020
WHEELBASE = 2.588
FRONT_AXLE_S = 0.815  # 815 mm front overhang, 617 mm rear overhang
REAR_AXLE_S = FRONT_AXLE_S + WHEELBASE
Y0 = FRONT_AXLE_S + WHEELBASE / 2.0
TRACK_F = 1.480
TRACK_R = 1.469
TYRE_R = 0.310  # 185/65 R15: 381 mm rim + 2 x 120 mm sidewall = 620 mm
TYRE_W = 0.185
ARCH_R = 0.370  # practical Dacia ride height over 185/65 R15 tyres
ROOF = 1.534

S_SCUTTLE = 1.05
S_COWL, S_WS_TOP = 1.13, 1.88
S_SAIL = 1.43
S_B0, S_B1 = 2.11, 2.21
S_QR = 3.06  # rear door drop glass ends at this black post; small upswept fixed quarter glass behind it to S_Q1
S_Q1 = 3.38  # rear corner of the side glass, tucked into the chunky C-pillar
S_DECK = 3.49  # tailgate top shut line behind the roof
S_RG0, S_RG1 = 3.53, 3.88  # rear hatch glass from roof edge down to the sculpted tailgate
S_DOOR = (1.22, 2.16, 3.38)
FRIT = 0.015
PILLAR = 0.070


def bl(x, s, z):
	return Vector((x, Y0 - s, z))


# ---------------------------------------------------------------- body profile curves (metres)
# Plan, elevation and section lines for the Mk1 Sandero: rounded sloped nose (never a flat cliff) with a protruding
# bumper beam, sculpted bonnet rising to a tall upright windscreen, airy tall roof peaking at 1534 mm over the B-pillar,
# rising beltline with slightly upswept rear quarter window, and a rounded hatchback tailgate with high corner shoulders.
L = LENGTH
W = Curve([(0.0, 0.55), (0.03, 0.650), (0.08, 0.730), (0.16, 0.794), (0.30, 0.836), (0.55, 0.858), (0.85, 0.864),
	(1.35, 0.864), (2.40, 0.864), (3.20, 0.862), (3.58, 0.854), (3.78, 0.838), (3.90, 0.812), (3.96, 0.774),
	(3.995, 0.725), (L, 0.655)])
ZM = Curve([(0.0, 0.43), (0.10, 0.47), (0.30, 0.53), (0.90, 0.63), (1.45, 0.65), (3.15, 0.68), (3.70, 0.68), (L, 0.56)])
WSH = Curve([(0.0, 0.49), (0.03, 0.580), (0.08, 0.658), (0.16, 0.722), (0.32, 0.770), (0.60, 0.798), (1.0, 0.810),
	(1.5, 0.814), (2.4, 0.814), (3.2, 0.810), (3.62, 0.800), (3.82, 0.782), (3.92, 0.752), (3.975, 0.714),
	(4.00, 0.674), (L, 0.605)])
ZSH = Curve([(0.0, 0.545), (0.03, 0.585), (0.07, 0.648), (0.13, 0.715), (0.22, 0.775), (0.38, 0.830), (0.60, 0.876),
	(0.85, 0.914), (S_SCUTTLE, 0.938), (S_COWL, 0.948), (1.45, 0.968), (1.90, 0.982), (2.45, 0.996), (2.98, 1.012),
	(3.22, 1.032), (3.44, 1.050), (3.78, 1.046), (3.88, 1.028), (3.945, 0.986), (3.982, 0.910), (4.005, 0.795),
	(4.015, 0.685), (L, 0.585)])
ZT = Curve([(0.0, 0.575), (0.03, 0.618), (0.07, 0.682), (0.13, 0.750), (0.22, 0.812), (0.38, 0.868), (0.60, 0.914),
	(0.85, 0.952), (S_SCUTTLE, 0.976), (S_COWL, 0.988), (1.33, 1.112), (1.53, 1.240), (1.71, 1.356), (S_WS_TOP, 1.458),
	(2.05, 1.505), (2.26, 1.526), (2.55, ROOF), (2.86, 1.530), (3.16, 1.515), (3.38, 1.496), (S_DECK, 1.484),
	(S_RG0, 1.474), (3.62, 1.374), (3.71, 1.268), (3.80, 1.160), (S_RG1, 1.058), (3.93, 1.018), (3.968, 0.962),
	(3.992, 0.880), (4.010, 0.768), (L, 0.620)])
ZB = Curve([(0.0, 0.268), (0.05, 0.244), (0.20, 0.228), (0.50, 0.220), (1.0, 0.216), (2.6, 0.216), (3.5, 0.228),
	(3.80, 0.262), (3.95, 0.292), (L, 0.316)])
WR = Curve([(0.0, 0.45), (0.04, 0.530), (0.10, 0.602), (0.20, 0.665), (0.45, 0.718), (0.80, 0.742), (S_COWL, 0.748),
	(1.52, 0.708), (S_WS_TOP, 0.662), (2.40, 0.648), (3.00, 0.638), (3.36, 0.618), (S_RG0, 0.592), (3.70, 0.608),
	(S_RG1, 0.638), (3.94, 0.672), (3.99, 0.652), (L, 0.565)])
DR = Curve([(0.0, 0.014), (0.2, 0.034), (S_COWL, 0.044), (S_WS_TOP, 0.052), (3.40, 0.052), (S_RG1, 0.036), (L, 0.014)])

SEG_ROWS = [3, 2, 5, 5, 1, 4, 2, 8]
SEG_AB, SEG_BC, SEG_CD, SEG_DE, SEG_EF, SEG_FG, SEG_GH, SEG_HI = range(8)


def bonnet_crease_t(s):
	"""Subtle Sandero Mk1 bonnet contour lines sweeping from the wide upper grille corners back toward the A-pillars."""
	f = min(1.0, max(0.0, (s - 0.14) / (S_SCUTTLE - 0.14)))
	xc = lerp(0.30, 0.58, f)
	return min(0.64, max(0.16, 1.0 - xc / max(0.30, WR(s))))


def bonnet_crease_dz(s, sub):
	if s >= S_COWL:
		return 0.0
	env = smoothstep(0.12, 0.22, s) * (1.0 - smoothstep(S_SCUTTLE - 0.04, S_COWL, s))
	if env <= 0.0:
		return 0.0
	prof = (0.0, 0.0, -0.001, 0.0040, 0.0085, 0.0075, 0.0065, 0.0065)
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
	C = Vector((w - 0.030, zb + 0.055))
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
		# gentle convex taper into the chunky C-pillar over the upswept rear quarter beltline
		gz = F.y + max(0.004, (gz - F.y) * (1.0 - k ** 1.25))
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
	"Bumper": ((0.065, 0.067, 0.070), 0.62, 0.0, {}),
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
			if 0.14 < s < S_COWL - 0.015 and j == sum(SEG_ROWS[:SEG_FG]):
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

	# Chunky rounded Dacia Sandero Mk1 wheel-arch flares + lower door wave crease + subtle shoulder line
	for v in mb.v:
		ax = abs(v.x)
		if ax < 0.45 or v.z < 0.18:
			continue
		s = Y0 - v.y
		for sc in (FRONT_AXLE_S, REAR_AXLE_S):
			d = math.hypot(s - sc, v.z - TYRE_R)
			# muscular rounded semicircular arch flare blister (Sandero Mk1 signature)
			if d < ARCH_R + 0.088:
				flare = 0.015 * (1.0 - smoothstep(ARCH_R + 0.028, ARCH_R + 0.088, d))
				lip = 0.006 * (1.0 - smoothstep(ARCH_R + 0.008, ARCH_R + 0.026, d))
				v.x += math.copysign((flare + lip) * (1.0 - smoothstep(0.84, 0.96, v.z)), v.x)
		# sculpted Sandero lower-door wave crease curving gently upward toward the rear arch
		if 1.22 < s < 3.00 and ax > 0.72:
			t = (s - 1.22) / 1.78
			zw = 0.43 + 0.055 * (t ** 1.3)
			dz = abs(v.z - zw)
			if dz < 0.065:
				v.x += math.copysign(0.006 * (1.0 - smoothstep(0.0, 0.065, dz))
					* smoothstep(1.22, 1.38, s) * (1.0 - smoothstep(2.84, 3.00, s)), v.x)
		# subtle upper shoulder highlight line from behind the front arch to the tail lamp
		if 1.18 < s < 3.74 and ax > 0.72:
			zc = lerp(0.85, 0.95, (s - 1.18) / 2.56)
			dz = abs(v.z - zc)
			if dz < 0.055:
				v.x += math.copysign(0.0045 * (1.0 - smoothstep(0.0, 0.055, dz))
					* smoothstep(1.18, 1.38, s) * (1.0 - smoothstep(3.55, 3.74, s)), v.x)

	# Body-coloured door mirrors on black sail feet (Paint only on the Body mesh), plus flush body-coloured pull handles
	def body_x_at(s, z):
		pts, _ = section(s)
		for a, b in zip(pts, pts[1:]):
			if (a.y <= z <= b.y) or (b.y <= z <= a.y):
				t = 0.0 if abs(b.y - a.y) < 1e-6 else (z - a.y) / (b.y - a.y)
				return lerp(a.x, b.x, t)
		return WSH(s)

	for side in (1, -1):
		mb.box(bl(side * 0.835, 1.44, 1.020), (0.056, 0.092, 0.044), "Trim")
		mb.blob(bl(side * 0.905, 1.48, 1.066), (0.068, 0.050, 0.060), "Paint", e=0.48)
		mb.blob(bl(side * 0.905, 1.527, 1.066), (0.059, 0.006, 0.048), "Chrome", e=0.35)
		# body-coloured pull handles seated flush on the upper door surface
		for hs, hz in ((1.96, 0.905), (2.92, 0.935)):
			x = body_x_at(hs, hz)
			mb.blob(bl(side * (x + 0.005), hs, hz), (0.011, 0.074, 0.016), "Paint", e=0.4)
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
		if s < 0.88 or c.z < 0.2:
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
	"""A headlamp reflector bowl with depth, hugging the curved nose cleanly inside the domed headlamp lens."""
	loc, n_surf = pj.hit(*proj(u, v))
	n = (n_surf * 5.5 + Vector((0.0, 1.0, 0.0))).normalized()
	helper = Vector((1, 0, 0)) if abs(n.x) < 0.9 else Vector((0, 1, 0))
	bx = n.cross(helper).normalized()
	by = n.cross(bx)
	tilt = n_surf.cross(n).length
	base = loc + n_surf * (0.0110 + r * tilt * 0.60)
	segs = 28
	prof = [(r, 0.0090), (r * 0.95, 0.0072), (r * 0.80, 0.0045), (r * 0.60, 0.0024), (r * 0.38, 0.0011), (r * 0.26, 0.0005)]
	rows = [[base + n * d + (bx * math.cos(2 * math.pi * k / segs) + by * math.sin(2 * math.pi * k / segs)) * rr
		for k in range(segs)] for rr, d in prof]
	mb.grid(rows[:2], "Chrome", closed=True, out=n)
	mb.grid(rows[1:], "Headlight", closed=True, out=n)
	mb.disc(base + n * 0.0005, r * 0.26, "Headlight", normal=n, segs=segs)
	mb.ring(base + n * 0.0092, r * 0.94, r * 1.08, "Chrome", normal=n, segs=segs)


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
			ref = nors[i][j] + nors[i + 1][j] + nors[i + 1][j + 1] + nors[i][j + 1]
			mb.face([ids[i][j], ids[i + 1][j], ids[i + 1][j + 1], ids[i][j + 1]], mat, ref)
	for i, k in ((0, 1), (len(ts) - 1, len(ts) - 2)):
		inner = [pts[i][j] - nors[i][j] * 0.006 for j in range(len(vs))]
		ref = pts[i][len(vs) // 2] - pts[k][len(vs) // 2]
		mb.poly(pts[i] + list(reversed(inner)), mat, ref)
	return pts


# 2008-2012 Dacia Mk1 chrome shield emblem (introduced on the Sandero Mk1: broad tapered chrome shield with
# dark recessed centre cutout and bold upper crossbar).
DACIA_SHIELD = [
	(-0.048, 0.042), (0.048, 0.042), (0.044, 0.002), (0.032, -0.026),
	(0.0, -0.044), (-0.032, -0.026), (-0.044, 0.002),
]
DACIA_INNER = [
	(-0.032, 0.020), (0.032, 0.020), (0.028, -0.004), (0.018, -0.022),
	(0.0, -0.031), (-0.018, -0.022), (-0.028, -0.004),
]


def dacia_shield_badge(pj, mb, proj, cu, cv, scale, base_off):
	"""The 2008 Mk1 Dacia chrome shield emblem: dark backing, bright chrome shield, dark inner well, and chrome upper bar."""
	pj.star(mb, dense([(cu + x * scale * 1.12, cv + y * scale * 1.12) for x, y in DACIA_SHIELD], 0.018),
		proj, "Gasket", offset=base_off, rings=2, samples=2, skirt=0.004)
	pj.star(mb, dense([(cu + x * scale, cv + y * scale) for x, y in DACIA_SHIELD], 0.018),
		proj, "Chrome", offset=base_off + 0.0026, rings=2, samples=2, skirt=0.003)
	pj.star(mb, dense([(cu + x * scale * 0.92, cv + y * scale * 0.92) for x, y in DACIA_INNER], 0.015),
		proj, "Trim", offset=base_off + 0.0042, rings=2, samples=2, skirt=0.0)
	# characteristic Dacia shield inner chrome arch/notches across top and bottom
	bar = [(-0.036, 0.022), (0.036, 0.022), (0.032, 0.036), (-0.032, 0.036)]
	pj.star(mb, dense([(cu + x * scale, cv + y * scale) for x, y in bar], 0.015),
		proj, "Chrome", offset=base_off + 0.0054, rings=1, samples=1, skirt=0.001)
	notch = [(-0.014, -0.005), (0.014, -0.005), (0.010, 0.016), (-0.010, 0.016)]
	pj.star(mb, dense([(cu + x * scale, cv + y * scale) for x, y in notch], 0.012),
		proj, "Chrome", offset=base_off + 0.0054, rings=1, samples=1, skirt=0.001)


# ---------------------------------------------------------------- lamps, grilles, bumper plastics
FB_AXIS = 0.52
HL_AXIS = 0.74  # headlamp wrap axis: rays from 25 to 80 deg sweep smoothly from beside the wide trapezoid grille into the wing
RB_AXIS = LENGTH - 0.52

# Large curved wrap-around wedge headlamps of the Dacia Sandero Mk1 (cyl_proj around HL_AXIS: u in degrees, v is z):
# bold angled inner edge hugging the trapezoid grille at 26.5 deg (clean painted gap from chrome bar), tall
# twin-reflector housing curving over the corner, and sweeping cleanly up and back into the front wing to 80 deg.
HL_U0, HL_U1 = 26.5, 80.0
HL_TOP = Curve([(26.5, 0.722), (30.5, 0.736), (39.0, 0.764), (50.0, 0.794), (62.0, 0.818), (72.0, 0.834), (78.0, 0.840),
	(80.0, 0.836)])
HL_BOT = Curve([(26.5, 0.622), (30.5, 0.616), (39.0, 0.618), (50.0, 0.634), (62.0, 0.668), (72.0, 0.722), (78.0, 0.785),
	(80.0, 0.824)])

# Wide trapezoid upper grille (wider at top under the thick chrome bar, tapering slightly down toward the bumper beam)
UPPER_GRILLE = [
	(-0.294, 0.720), (0.294, 0.720), (0.274, 0.662), (0.248, 0.618),
	(-0.248, 0.618), (-0.274, 0.662),
]
# Thick upper chrome/silver Sandero bar crowning the trapezoid grille, dipping slightly around the Dacia shield
CHROME_BAR = [
	(-0.296, 0.725), (0.296, 0.725), (0.291, 0.700), (0.084, 0.698),
	(0.064, 0.684), (-0.064, 0.684), (-0.084, 0.698), (-0.291, 0.700),
]
# Sculpted wide trapezoidal lower bumper intake below the front plate
LOWER_GRILLE = [
	(-0.340, 0.402), (0.340, 0.402),
	(0.415, 0.358), (0.432, 0.296),
	(0.395, 0.268), (-0.395, 0.268),
	(-0.432, 0.296), (-0.415, 0.358),
]

# Tall vertical-wedge tail lamps of the Dacia Sandero Mk1: wide at the waist above the rear bumper and tapering cleanly
# upward flanking the rear window, red upper and lower zones bracketing a clear/amber central wedge.
TAIL_OUT = [
	(0.504, 0.725), (0.506, 0.835), (0.528, 0.945), (0.564, 1.045), (0.596, 1.132),
	(0.618, 1.186), (0.648, 1.198), (0.680, 1.176), (0.708, 1.112), (0.734, 1.028),
	(0.755, 0.928), (0.760, 0.820), (0.748, 0.738), (0.718, 0.716), (0.590, 0.714),
]
TAIL_OUT = dense(TAIL_OUT, 0.018)
TAIL_RED_TOP = inset(clip_band(TAIL_OUT, 0.990, 1.24), 0.005)
TAIL_AMBER = inset(clip_band(TAIL_OUT, 0.928, 0.986), 0.004)
TAIL_CLEAR = inset(clip_band(TAIL_OUT, 0.864, 0.924), 0.004)
TAIL_RED_LOW = inset(clip_band(TAIL_OUT, 0.705, 0.858), 0.005)


def build_plastics(pj, mb):
	"""Dacia Sandero Mk1 nose and tail plastics: wide trapezoid upper grille with thick chrome upper bar and Mk1 Dacia
	shield emblem, body-coloured bumper beam carrying the front plate, wide lower black intake with slats, round fog
	light pods in dark corner recesses, black lower chin lip and rear bumper valance."""
	fp = cyl_proj(FB_AXIS, False)
	# Wide trapezoid upper grille with dark surround, mesh, horizontal slat, thick chrome upper bar and Dacia shield
	pj.star(mb, dense(UPPER_GRILLE, 0.03), front_proj, "Trim", offset=0.0025, rings=1, samples=2, skirt=0.004)
	pj.star(mb, dense(inset(UPPER_GRILLE, 0.009), 0.03), front_proj, "Grille", offset=0.0042, rings=1, samples=2, skirt=0.0)
	pj.strip(mb, -0.278, 0.278, 0.654, 0.665, 24, 1, front_proj, "Trim", offset=0.0062)
	pj.star(mb, dense(CHROME_BAR, 0.025), front_proj, "Chrome", offset=0.0072, rings=2, samples=2, skirt=0.003)
	dacia_shield_badge(pj, mb, front_proj, 0.0, 0.688, 1.18, 0.0082)

	# Front European number plate (512 x 105 mm) on the body-coloured front bumper beam:
	# bottom edge y0_front = 0.435 (matches CarCatalog SANDERO_VISUAL plate_y)
	pj.star(mb, rounded_rect(-0.264, 0.264, 0.429, 0.5457, 0.006), front_proj, "Trim", offset=0.0055, rings=1, samples=2, skirt=0.006)
	pj.star(mb, rounded_rect(-0.2559, 0.2559, 0.435, 0.5397, 0.004), front_proj, "Plate", offset=0.0085, rings=1, samples=2, skirt=0.0)

	# Sculpted wide trapezoidal lower black air intake below the bumper beam
	pj.star(mb, dense(LOWER_GRILLE, 0.03), front_proj, "Trim", offset=0.0025, rings=1, samples=2, skirt=0.004)
	pj.star(mb, dense(inset(LOWER_GRILLE, 0.010), 0.03), front_proj, "Grille", offset=0.0042, rings=1, samples=2, skirt=0.0)
	for z, hw in ((0.298, 0.402), (0.332, 0.388), (0.366, 0.360)):
		pj.strip(mb, -hw, hw, z, z + 0.008, 28, 1, front_proj, "Trim", offset=0.0064)

	# Round fog-light pods nestled in sculpted dark corner recesses flanking the lower intake
	for side in (1, -1):
		hp = lambda u, v, side=side: front_proj(side * u, v)
		pod = [(0.472, 0.388), (0.628, 0.404), (0.662, 0.366), (0.642, 0.288), (0.536, 0.274), (0.464, 0.298)]
		pj.star(mb, dense(pod, 0.03), hp, "Trim", offset=0.0042, rings=2, samples=2, skirt=0.005)
		pj.star(mb, ellipse(0.566, 0.340, 0.048, 0.048, 24), hp, "Chrome", offset=0.0072, rings=2, samples=1, skirt=0.0)
		pj.star(mb, ellipse(0.566, 0.340, 0.040, 0.040, 24), hp, "Fog", offset=0.0092, bulge=0.003, rings=2, samples=1, skirt=0.0)

	# Practical black lower front chin valance wrapping round to the front arches
	chin_rows = [(0.222, -0.002), (0.232, 0.008), (0.254, 0.010), (0.264, -0.002)]
	wrap_band(pj, mb, fp, FRONT_AXLE_S, True, [r[0] for r in chin_rows], lambda v, rows=chin_rows: profile(v, rows),
		"Bumper", reach=0.92)
	# Bonnet leading shut line cleanly above the chrome grille bar between the headlamps
	pj.strip(mb, -0.305, 0.305, 0.742, 0.748, 28, 1, front_proj, "Gasket", offset=0.0012)

	# Rear lower black bumper valance wrapping round to the rear wheel arches
	rp = cyl_proj(RB_AXIS, True)
	rows = [(0.305, -0.002), (0.316, 0.009), (0.332, 0.012), (0.410, 0.012), (0.422, 0.006), (0.430, -0.001)]
	vs = sorted(set([r[0] for r in rows] + spread(0.34, 0.40, 0.02)))
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
		# Large curved wrap-around wedge headlamps around HL_AXIS: flush gasket surround, metallic inner bezel,
		# dual bright chrome-rimmed reflector bowls, outer-upper amber corner indicator, and domed clear cover.
		hl_cyl = cyl_proj(HL_AXIS, False)
		hp = lambda u, v, side=side, hl_cyl=hl_cyl: hl_cyl(side * u, v)
		wing_fade = lambda u: 1.0 - smoothstep(52.0, 78.0, u)

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
		# Amber corner indicator tucked into the outer-upper wing sweep of the headlamp
		iu0, iu1 = 59.5, 76.5
		def ind_span(u):
			t = min(1.0, max(0.0, (u - iu0) / (iu1 - iu0)))
			w = math.sin(math.pi * t) ** 0.5
			b, tp_ = HL_BOT(u), HL_TOP(u)
			mid = lerp(b, tp_, 0.56)
			half = max(0.002, (tp_ - b) * 0.28 * w)
			return mid - half, mid + half
		patch_uv(mb, pj, hp, iu0, iu1,
			lambda u: ind_span(u)[0],
			lambda u: ind_span(u)[1],
			lambda u, v: lerp(0.0065, 0.015, wing_fade(u)), "Indicator", nu=10, nv=5, bulge=0.0020)
		# Dual chrome-rimmed reflector bowls (inboard high beam + larger outboard main/dipped beam)
		reflector(mb, pj, hp, 33.5, 0.680, 0.041)
		reflector(mb, pj, hp, 44.5, 0.706, 0.048)
		gu0, gu1, gbot, gtop = hl_inset(0.4, 0.5, 0.0025)
		patch_uv(mb, pj, hp, gu0, gu1, gbot, gtop,
			lambda u, v: lerp(0.0095, 0.036, wing_fade(u)), "LampGlass", nu=24, nv=8,
			bulge=lambda u, v: lerp(0.002, 0.011, wing_fade(u)),
			skirt_fn=lambda u, v: lerp(0.007, 0.025, wing_fade(u)))

		# Tall vertical-wedge tail lamps flanking the rear window and upper tailgate
		tp = lambda u, v, side=side: rear_proj(side * u, v)
		pj.star(mb, TAIL_OUT, tp, "Gasket", offset=0.005, rings=6, samples=2, skirt=0.005)
		for poly in (TAIL_RED_TOP, TAIL_RED_LOW):
			pj.star(mb, poly, tp, "Taillight", offset=0.012, rings=6, samples=2, skirt=0.0)
			pj.star(mb, shrink(poly, 0.25), tp, "TailBulb", offset=0.0135, rings=4, samples=2, skirt=0.0)
			pj.star(mb, poly, tp, "TailGlass", offset=0.0175, bulge=0.0030, rings=6, samples=2, skirt=0.006)
		pj.star(mb, TAIL_AMBER, tp, "Indicator", offset=0.014, rings=5, samples=2, skirt=0.0)
		pj.star(mb, TAIL_CLEAR, tp, "LampClear", offset=0.014, rings=5, samples=2, skirt=0.0)
		pj.star(mb, inset(clip_band(TAIL_OUT, 0.860, 0.988), 0.004), tp, "LampGlass", offset=0.0185, bulge=0.0020, rings=5, samples=2, skirt=0.005)
		# Rear bumper reflectors in the lower corners
		pj.star(mb, rounded_rect(0.51, 0.65, 0.455, 0.478, 0.008), tp, "Taillight", offset=0.006, rings=1, samples=2, skirt=0.0)

		pj = pj_all
		sp = side_proj(side)
		# Fixed rear quarter-light vertical divider post inside the rear window
		pj.strip(mb, S_QR - 0.006, S_QR + 0.016, 1.032, 1.365, 2, 8, sp, "Trim", offset=0.003)
		# Side repeater on the front wing behind the front wheel arch
		pj.star(mb, ellipse(1.25, 0.81, 0.024, 0.011, 12), sp, "Gasket", offset=0.002, rings=1, samples=2)
		pj.star(mb, ellipse(1.25, 0.81, 0.018, 0.0075, 12), sp, "Indicator", offset=0.004, bulge=0.002, rings=2, samples=2)
		# Dark recesses behind the pull handles + front lock barrel
		for hs, hz in ((1.96, 0.905), (2.92, 0.935)):
			pj.star(mb, rounded_rect(hs - 0.068, hs + 0.068, hz - 0.022, hz + 0.010, 0.011), sp, "Gasket", offset=0.0012,
				rings=1, samples=2)
		pj.star(mb, ellipse(1.96 + 0.088, 0.905, 0.0085, 0.0085, 10), sp, "Chrome", offset=0.004, rings=1, samples=1)
		# Practical Dacia slim black lower-door protective strip (low enough to stay clear of Abarth/Sill/Door decals)
		pj.band(mb, spread(1.25, 2.96, 0.05, S_DOOR[:2]), [0.304, 0.312, 0.336, 0.344],
			lambda u, v: 0.0065 if 0.310 < v < 0.338 else 0.0, lambda u, v: "Bumper", sp, caps=True)
		# Subtle black lower sill edge
		pj.band(mb, spread(1.22, 2.98, 0.05, S_DOOR[:2]), [0.224, 0.242, 0.258],
			lambda u, v: 0.0035 if 0.234 < v < 0.250 else 0.0, lambda u, v: "Bumper", sp)

		# Closed wheel-well liners
		for sc in (FRONT_AXLE_S, REAR_AXLE_S):
			rows = []
			for xo in (0.48, 0.75):
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

	# Fuel flap on the right rear wing (Dacia Sandero Mk1 has a circular fuel door on the right rear quarter)
	spr = side_proj(1)
	loc, n = pj.hit(*spr(3.56, 0.87))
	mb.ring(loc + n * 0.0012, 0.055, 0.0585, "Gasket", normal=n, segs=28)

	# Rear end: sculpted rounded tailgate with recessed rear plate (y0_rear = 0.615, CarCatalog SANDERO_VISUAL plate_y),
	# chrome boot handle strip, Dacia Mk1 shield badge, DACIA and SANDERO chrome lettering, shut lines, 3rd brake light
	# and rear wiper.
	pj.star(mb, rounded_rect(-0.278, 0.278, 0.606, 0.731, 0.010), rear_proj, "Gasket", offset=0.0015, rings=1, samples=2, skirt=0.0)
	pj.star(mb, rounded_rect(-0.264, 0.264, 0.609, 0.7257, 0.006), rear_proj, "Trim", offset=0.0028, rings=1, samples=2, skirt=0.0)
	pj.star(mb, rounded_rect(-0.2559, 0.2559, 0.615, 0.7197, 0.004), rear_proj, "Plate", offset=0.0052, rings=1, samples=2, skirt=0.0)
	# Chrome tailgate trim strip above the plate recess + push-button boot lock cylinder
	pj.star(mb, rounded_rect(-0.26, 0.26, 0.744, 0.760, 0.006), rear_proj, "Chrome", offset=0.0045, rings=1, samples=2, skirt=0.002)
	pj.star(mb, ellipse(0.0, 0.790, 0.014, 0.014, 14), rear_proj, "Trim", offset=0.004, rings=1, samples=1, skirt=0.002)
	pj.star(mb, ellipse(0.0, 0.790, 0.009, 0.009, 12), rear_proj, "Chrome", offset=0.006, rings=1, samples=1, skirt=0.0)
	# Dacia Mk1 chrome shield emblem centred on the tailgate
	dacia_shield_badge(pj, mb, rear_proj, 0.0, 0.905, 1.15, 0.0035)
	# DACIA and SANDERO chrome lettering with drop shadow
	for text, cu, w in (("DACIA", -0.345, 0.145), ("SANDERO", 0.340, 0.175)):
		text_decal(pj, mb, rear_proj, text, cu + 0.003, 0.858 - 0.004, w, "Gasket", 0.0030, 1)
		text_decal(pj, mb, rear_proj, text, cu, 0.858, w, "Chrome", 0.0052, 1)
	# Tailgate shut lines beside the tall tail lamps and along the bumper top
	for x in (-0.494, 0.494):
		pj.strip(mb, x + 0.003, x - 0.003, 0.568, 1.045, 1, 22, rear_proj, "Gasket", offset=0.0022)
	pj.strip(mb, -0.492, 0.492, 0.565, 0.571, 30, 1, rear_proj, "Gasket", offset=0.0018)
	pj.strip(mb, S_DECK - 0.003, S_DECK + 0.003, -0.56, 0.56, 1, 36, top_proj, "Gasket", offset=0.0012)
	# High-mounted third brake lamp over the rear glass
	pj.strip(mb, -0.44, 0.44, 1.440, 1.466, 34, 1, rear_proj, "Trim", offset=0.0055)
	pj.strip(mb, -0.130, 0.130, 1.446, 1.460, 12, 1, rear_proj, "Taillight", offset=0.0080)
	# Rear wiper parked along the base of the rear screen
	base_p = pj.hit(*rear_proj(0.0, 1.078))[0]
	mb.blob(base_p + Vector((0, -0.012, 0)), (0.020, 0.015, 0.020), "Trim", e=0.3)
	tip = pj.hit(*rear_proj(0.36, 1.102))[0]
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

	# Signature Dacia front-mounted roof aerial right above the windscreen
	base = pj.hit(*top_proj(2.02, 0.0))[0]
	mb.blob(base + Vector((0, 0, 0.011)), (0.020, 0.032, 0.014), "Trim", e=0.4)
	mb.tube(base + Vector((0, 0, 0.018)), base + Vector((0, -0.11, 0.34)), 0.004, "Trim", segs=6)

	# Single exhaust tailpipe tucked under the right rear valance
	mb.tube(bl(0.24, 3.52, 0.272), bl(-0.18, 3.52, 0.272), 0.072, "Steel", segs=14)
	mb.tube(bl(0.38, 3.60, 0.264), bl(0.38, LENGTH + 0.006, 0.270), 0.022, "Exhaust", segs=14, caps=False)
	mb.ring(bl(0.38, LENGTH + 0.006, 0.270), 0.018, 0.023, "Exhaust", normal=(0, -1, 0), segs=14)
	mb.disc(bl(0.38, LENGTH - 0.004, 0.270), 0.019, "Under", normal=(0, -1, 0), segs=14)

	# Underbody floor pan and closed engine/boot bays
	mb.box(bl(0, 0.80, 0.225), (0.78, 0.74, 0.03), "Steel")
	mb.box(bl(0, 0.72, 0.45), (1.10, 0.92, 0.38), "Under")
	mb.box(bl(0, 3.62, 0.45), (1.10, 0.64, 0.38), "Under")
	mb.box(bl(0, 2.10, 0.235), (0.92, 2.20, 0.07), "Under")

	return mb, pj


def build_cabin():
	"""The cabin silhouette seen through the glass: Dacia dashboard with round centre vents and instrument binnacle,
	three-spoke steering wheel, two front seats, rear bench and rear-view mirror."""
	mb = MB()

	def cb(x, s, z):
		return bl(x, s - 0.10, z)
	mb.blob(cb(0, 1.58, 0.94), (0.65, 0.19, 0.09), "Interior", e=0.3)
	mb.box(cb(0, 1.49, 0.68), (1.36, 0.14, 0.44), "Interior")
	mb.box(cb(0, 1.71, 0.70), (0.25, 0.28, 0.40), "Interior")
	mb.box(cb(0, 2.04, 0.42), (0.23, 0.76, 0.18), "Interior")
	mb.blob(cb(-0.36, 1.64, 1.06), (0.16, 0.10, 0.06), "Interior", e=0.35)
	mb.disc(cb(-0.36, 1.62, 1.04), 0.052, "Plate", normal=(0, -0.6, 0.8), segs=16)
	for sx in (-0.065, 0.065):
		mb.disc(cb(sx, 1.68, 0.94), 0.025, "Trim", normal=(0, -0.4, 0.9), segs=12)
		mb.ring(cb(sx, 1.68, 0.94), 0.022, 0.027, "Chrome", normal=(0, -0.4, 0.9), segs=12)
	mb.blob(cb(0, 1.94, 0.52), (0.055, 0.065, 0.04), "Trim", e=0.3)
	mb.tube(cb(0, 1.94, 0.54), cb(0, 1.96, 0.74), 0.0085, "Chrome", segs=8)
	mb.blob(cb(0, 1.96, 0.75), (0.021, 0.021, 0.025), "Seat", e=0.35)
	mb.tube(cb(0.065, 2.26, 0.52), cb(0.065, 2.34, 0.60), 0.010, "Interior", segs=6)
	for px in (-0.44, -0.36, -0.28):
		mb.box(cb(px, 1.54, 0.32), (0.048, 0.012, 0.072), "Steel")
	mb.box(cb(0, 2.04, 1.38), (0.125, 0.015, 0.042), "Interior")
	mb.tube(cb(0, 2.05, 1.39), cb(0, 2.07, 1.43), 0.006, "Trim", segs=6)
	tilt = math.radians(66)
	n = Vector((0, -math.cos(tilt), math.sin(tilt)))
	u = Vector((1, 0, 0))
	v = n.cross(u)
	sw = cb(-0.36, 1.86, 1.03)
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
	for sx in (-0.36, 0.36):
		mb.blob(cb(sx, 2.29, 0.46), (0.22, 0.25, 0.085), "Fabric", e=0.40)
		mb.blob(cb(sx, 2.51, 0.84), (0.23, 0.08, 0.36), "Fabric", e=0.45, basis=lean)
		for bx in (-1, 1):
			mb.blob(cb(sx + bx * 0.19, 2.29, 0.51), (0.042, 0.23, 0.085), "Fabric", e=0.4)
			mb.blob(cb(sx + bx * 0.20, 2.49, 0.84), (0.042, 0.08, 0.26), "Fabric", e=0.4, basis=lean)
		mb.blob(cb(sx, 2.57, 1.22), (0.105, 0.05, 0.095), "Fabric", e=0.4, basis=lean)
		for rx in (-0.19, 0.19):
			mb.box(cb(sx + rx, 2.29, 0.28), (0.024, 0.42, 0.034), "Steel")
	mb.blob(cb(0, 2.98, 0.46), (0.61, 0.21, 0.08), "Fabric", e=0.35)
	mb.blob(cb(0, 3.20, 0.86), (0.62, 0.07, 0.34), "Fabric", e=0.40)
	for hx in (-0.37, 0.0, 0.37):
		mb.blob(cb(hx, 3.22, 1.22), (0.095, 0.04, 0.08), "Fabric", e=0.4)
	return mb


def build_stripes(pj):
	mb = MB()
	for x in (-0.15, 0.15):
		pj.strip(mb, 0.18, S_SCUTTLE - 0.01, x - 0.065, x + 0.065, 36, 2, top_proj, "Stripe", offset=0.0018)
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
		pj.strip(mb, 0.18, S_SCUTTLE - 0.01, x0, x1, 36, 1, top_proj, mat, offset=0.0035)
		pj.strip(mb, S_WS_TOP + 0.02, S_DECK - 0.03, x0, x1, 42, 1, top_proj, mat, offset=0.0035)

	def belt(u):
		return 0.74 + 0.04 * smoothstep(1.24, 2.96, u)
	us = [lerp(1.24, 2.96, i / 86) for i in range(87)]
	vs = [-0.072, -0.048, -0.024, 0.044]
	for side in (1, -1):
		sp = side_proj(side)
		pj.band(mb, us, vs, lambda u, v: 0.0045, lambda u, v: "MartiniDark" if v < -0.04 else "MartiniLight" if v < -0.01 else "MartiniRed",
			lambda u, v, sp=sp: sp(u, v + belt(u)))
		martini_roundel(pj, mb, sp, 1.76, 0.615, 0.095, -side)
	martini_roundel(pj, mb, top_proj, 0.66, 0.0, 0.095, 1)
	return mb


def build_abarth(pj):
	mb = MB()
	for side in (1, -1):
		sp = side_proj(side)
		pj.strip(mb, 1.24, 2.96, 0.385, 0.475, 38, 2, sp, "AbarthBlack", offset=0.0035)
		pj.strip(mb, 1.24, 2.96, 0.482, 0.494, 38, 1, sp, "AbarthRed", offset=0.0035)
		text_decal(pj, mb, sp, "ABARTH", 2.10, 0.430, 0.58, "AbarthWhite", 0.0050, -side)

	def plate(pts, mat, off, k=0.14, cu=0.56):
		pj.star(mb, [(cu + x * k, y * k) for x, y in pts], top_proj, mat, offset=off, rings=2, samples=2, skirt=0.0)
	plate([(-0.66, 0.0), (-0.12, 0.56), (0.60, 0.56), (0.60, -0.56), (-0.12, -0.56)], "AbarthWhite", 0.0030)
	plate([(-0.58, 0.0), (-0.10, 0.49), (0.53, 0.49), (0.53, -0.49), (-0.10, -0.49)], "AbarthRed", 0.0036)
	plate([(0.22, 0.49), (0.53, 0.49), (0.53, -0.49), (0.22, -0.49)], "AbarthYellow", 0.0042)
	text_decal(pj, mb, top_proj, "ABARTH", 0.56 + 0.375 * 0.14, 0.0, 0.10, "AbarthBlack", 0.0048, 1)
	return mb


def build_marlboro(pj):
	mb = MB()
	pj.star(mb, [(0.24, -0.46), (0.24, 0.46), (0.98, 0.46), (0.60, 0.0), (0.98, -0.46)], top_proj, "MarlboroRed",
		offset=0.0075, rings=14, samples=16, skirt=0.0)
	for side in (1, -1):
		sp = side_proj(side)
		pj.star(mb, [(1.34, 0.59), (1.34, 0.85), (2.88, 0.85), (2.48, 0.72), (2.88, 0.59)], sp, "MarlboroRed",
			offset=0.005, rings=8, samples=14, skirt=0.0)
		text_decal(pj, mb, sp, "Marlboro", 1.80, 0.72, 0.52, "MarlboroWhite", 0.0065, -side)
	return mb


def dent_delta(key, p):
	"""How far a crash moves the point p (Blender coords) at full damage on one side."""
	s = Y0 - p.y
	d = Vector()
	if key == "front":
		w = smoothstep(1.18, 0.0, s)
		d.y = -0.28 * w ** 1.2 * (1.0 + 0.25 * _nz(p, 0.3))
		d.z = -0.07 * w * (1.0 + _nz(p, 1.1)) + 0.05 * w * w * smoothstep(0.62, 0.82, p.z)
		d.x = 0.05 * w * _nz(p, 2.4)
	elif key == "rear":
		w = smoothstep(LENGTH - 0.92, LENGTH, s)
		d.y = 0.22 * w ** 1.2 * (1.0 + 0.25 * _nz(p, 0.9))
		d.z = -0.05 * w * (1.0 + _nz(p, 2.0))
		d.x = 0.04 * w * _nz(p, 3.1)
	else:
		side = -1.0 if key == "left" else 1.0
		if p.x * side > 0.2:
			g = math.exp(-((s - 2.10) / 0.65) ** 2 - ((p.z - 0.68) / 0.30) ** 2)
			d.x = -side * 0.10 * g * (1.0 + 0.3 * _nz(p, 4.2))
			d.z = -0.02 * g * _nz(p, 5.0)
	return d


def build_wheel():
	"""15" chunky five-spoke Dacia Sandero alloy with a 185/65 R15 tyre; axle along X, outer face towards +X."""
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
		return Vector((c.x, 0, 0)) * 2.0 + radial * (r - 0.255)
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
		for r in (0.232, 0.264):
			rows.append([Vector((hw + 0.0085 - 0.0034 * (r - 0.232) / 0.032, r * math.cos(a0 + 0.8 * j / 8),
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

	# 5 chunky Dacia Sandero spokes with 4-lug hub (4x100 PCD), seated cleanly into the rim barrel lip
	for k in range(5):
		a = 2 * math.pi * k / 5 + 0.18
		ca, sa = math.cos(a), math.sin(a)
		p_hub = Vector((0, 0.052 * ca, 0.052 * sa))
		p_end = Vector((0, 0.172 * ca, 0.172 * sa))
		bar(p_hub, p_end, 0.044, 0.052, 0.022, 0.016, 0.036, 0.054)
	mb.lathe([(0.036, 0.076), (0.052, 0.070), (0.056, 0.0)], 28, "Rim", out=lambda c: Vector((1, c.y, c.z)))
	for k in range(4):
		a = 2 * math.pi * k / 4 + math.pi / 4
		p = Vector((0.052, 0.052 * math.cos(a), 0.052 * math.sin(a)))
		mb.tube(p, p + Vector((0.011, 0, 0)), 0.0095, "Chrome", segs=6)
	mb.lathe([(0.010, 0.075), (0.010, 0.142), (0.002, 0.142), (0.002, 0.075)], 36, "BrakeDisc", out=lambda c: Vector((1.0, c.y, c.z)))
	mb.lathe([(0.0, 0.0), (0.0, 0.16), (-0.065, 0.16)], 28, "Under", out=lambda c: Vector((1.0, c.y, c.z)))
	# Dacia centre cap
	mb.lathe([(0.054, 0.036), (0.062, 0.032), (0.066, 0.020), (0.0675, 0.0)], 24, "Steel", out=lambda c: Vector((1, c.y, c.z)))
	mb.ring(Vector((0.0676, 0, 0)), 0.014, 0.019, "Chrome", normal=(1, 0, 0), segs=18)
	mb.disc(Vector((0.0677, 0, 0)), 0.014, "Trim", normal=(1, 0, 0), segs=16)
	a_valve = 0.82
	v_base = Vector((0.040, 0.176 * math.cos(a_valve), 0.176 * math.sin(a_valve)))
	mb.tube(v_base, v_base + Vector((0.018, 0.006 * math.cos(a_valve), 0.006 * math.sin(a_valve))), 0.0038, "Trim", segs=6)
	return mb


# ---------------------------------------------------------------- previews
def render_all(cam, out_dir):
	views = {
		"front34": ((4.3, 4.9, 1.70), 38, None),
		"rear34": ((-4.3, -4.7, 1.80), 38, None),
		"side": ((8.2, 0.0, 0.76), 30, None),
		"front": ((0.0, 8.6, 0.82), 22, None),
		"rear": ((0.0, -8.6, 0.92), 22, None),
		"top": ((0.0, 0.0, 8.6), 30, None),
		"nose": ((-1.5, 4.1, 0.98), 30, (-0.1, Y0 - 0.15, 0.60)),
		"tail": ((1.3, -3.5, 1.08), 30, (0.1, Y0 - LENGTH + 0.15, 0.82)),
		"wheel": ((-1.9, Y0 - FRONT_AXLE_S + 0.55, 0.50), 30, (-TRACK_F / 2, Y0 - FRONT_AXLE_S, TYRE_R)),
	}
	carkit.render_views(cam, out_dir, views, (0, 0, 0.74))


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
			"front34": ((4.3, 4.9, 1.70), 38, None),
			"rear34": ((-4.3, -4.7, 1.80), 38, None),
			"side": ((8.2, 0.0, 0.76), 30, None),
			"top": ((0.0, 0.0, 8.6), 30, None),
		}
		carkit.render_views(cam, os.path.join(out_dir, key), views, (0, 0, 0.74))


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
		# Preview in authentic Mk1 Dacia Sandero Passion Red (or white for white liveries)
		cam = carkit.setup_preview((0.92, 0.92, 0.9) if view in ("martini", "marlboro") else (0.58, 0.04, 0.06))
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
		if not view and "--no-liveries" not in sys.argv:
			render_liveries(objs, cam, out)


if __name__ == "__main__":
	main()
