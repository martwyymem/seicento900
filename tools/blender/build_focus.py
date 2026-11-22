"""Builds the game's Ford Focus (Mk3.5 facelift, 2015, five-door hatchback, 1.5 EcoBoost 150 PS) in Blender.

Run from the repository root (Blender 4.2 or newer, headless):

    blender -b -P tools/blender/build_focus.py -- [--renders DIR] [--blend FILE]

Writes godot/models/focus.glb. With --renders it also saves preview PNGs (front, rear, side, top, three-quarters,
detail close-ups, and liveries).

The sixth campaign car (see AGENTS.md, "Adding the next car"): same object and material names as build_golf4.py and
build_i20.py, so race_car_visual.gd drives it unchanged. Real-car numbers: 4358 mm long, 1823 mm wide (without mirrors),
1484 mm high, 2648 mm wheelbase, 1544/1534 mm track, 215/55 R16 tyres on 16" five-twin-spoke Ford alloys.

Iconic 2015 Mk3.5 facelift cues: sleek aerodynamic curved nose with Ford's wide Aston-Martin-style hexagonal front grille
(chrome surround and horizontal chrome slats) and blue Ford oval perched on the nose tip above it, slim sharp swept-back
headlamps wrapping along the front wings with LED DRL brows and twin reflector bowls, twin sculpted bonnet power creases,
sleek elongated rectangular fog lamps in angular black corner recesses, rising sporty beltline with upward-kicking
triangular C-pillar quarter glass, raked tailgate with integrated roof spoiler and slim horizontal-swept wrap-around
red/clear tail lamps, and closed wheelhouses.

Scene objects: Body (painted shell with glass, trim, body-coloured mirrors and handles, underbody and cabin liner;
vertex colours carry the panel gaps), Details (lamps, hexagonal grille, fogs, plates, wipers, exhaust, wheel wells),
Stripes, Martini, Abarth, Marlboro (liveries), Cabin (dash, wheel, seats, bench, console; hidden on distant cars),
Wheel (16" five-twin-spoke alloy and tyre, one wheel at the origin, outer face towards +X).
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
OUT_GLB = os.path.join(ROOT, "godot", "models", "focus.glb")

# ---------------------------------------------------------------- real-car numbers
LENGTH = 4.358
WHEELBASE = 2.648
FRONT_AXLE_S = 0.920  # 920 mm front overhang, 790 mm rear overhang (Mk3.5 Focus proportions)
REAR_AXLE_S = FRONT_AXLE_S + WHEELBASE
Y0 = FRONT_AXLE_S + WHEELBASE / 2.0  # 2.244 m
TRACK_F = 1.544
TRACK_R = 1.534
TYRE_R = 0.321  # 215/55 R16: 406.4 mm rim + 2 x 118.25 mm sidewall = 642.9 mm
TYRE_W = 0.215
ARCH_R = 0.376
ROOF = 1.484

S_SCUTTLE = 1.24
S_COWL, S_WS_TOP = 1.33, 2.16
S_SAIL = 1.66
S_B0, S_B1 = 2.28, 2.38
S_QR = 3.24  # rear door drop glass ends here; upward-kicking triangular quarter glass runs to S_Q1
S_Q1 = 3.66  # pointed rear tip of the Mk3.5 side window graphic
S_DECK = 3.68  # tailgate top shut line behind the roof
S_RG0, S_RG1 = 3.84, 4.22  # rear hatch glass from integrated roof spoiler lip down to the sculpted tailgate
S_DOOR = (1.39, 2.33, 3.50)
FRIT = 0.015
PILLAR = 0.068


def bl(x, s, z):
	return Vector((x, Y0 - s, z))


# ---------------------------------------------------------------- body profile curves (metres)
# Sleek, aerodynamic Mk3.5 Focus shell: smoothly curved pointed nose (no flat vertical cliff), long sculpted bonnet with
# twin power creases, strongly raked windscreen, athletic roof arch peaking at 1484 mm, muscular rising beltline kicking
# up at the C-pillar quarter light, integrated roof spoiler, raked rear screen and taut sculpted hatchback tail.
L = LENGTH
W = Curve([
	(0.00, 0.480), (0.04, 0.625), (0.10, 0.735), (0.20, 0.818), (0.36, 0.872),
	(0.62, 0.902), (0.92, 0.9115), (1.45, 0.9115), (2.40, 0.9115), (3.35, 0.910),
	(3.75, 0.900), (4.02, 0.878), (4.18, 0.842), (4.27, 0.792), (4.325, 0.722),
	(L, 0.620),
])
ZM = Curve([
	(0.00, 0.415), (0.12, 0.460), (0.38, 0.525), (0.95, 0.630), (1.50, 0.655),
	(3.35, 0.695), (3.95, 0.680), (L, 0.560),
])
WSH = Curve([
	(0.00, 0.435), (0.04, 0.560), (0.10, 0.665), (0.20, 0.745), (0.38, 0.802),
	(0.68, 0.836), (1.10, 0.850), (1.70, 0.854), (2.50, 0.854), (3.35, 0.850),
	(3.78, 0.840), (4.05, 0.816), (4.20, 0.778), (4.285, 0.732), (4.335, 0.672),
	(L, 0.575),
])
ZSH = Curve([
	(0.00, 0.505), (0.04, 0.560), (0.09, 0.628), (0.16, 0.688), (0.28, 0.748),
	(0.50, 0.808), (0.85, 0.866), (S_SCUTTLE, 0.912), (S_COWL, 0.924),
	(1.70, 0.952), (2.33, 0.985), (2.95, 1.018), (S_QR, 1.036),
	(3.45, 1.068), (S_Q1, 1.100), (3.92, 1.104), (4.14, 1.072),
	(4.25, 1.012), (4.305, 0.935), (4.335, 0.835), (4.350, 0.720), (L, 0.595),
])
ZT = Curve([
	(0.00, 0.535), (0.04, 0.592), (0.09, 0.662), (0.16, 0.724), (0.28, 0.786),
	(0.50, 0.848), (0.85, 0.904), (S_SCUTTLE, 0.948), (S_COWL, 0.962),
	(1.55, 1.080), (1.78, 1.210), (1.98, 1.330), (S_WS_TOP, 1.425),
	(2.32, 1.468), (2.55, ROOF), (2.88, 1.481), (3.22, 1.470), (3.48, 1.458),
	(S_DECK, 1.448), (3.76, 1.442), (S_RG0, 1.436),
	(3.94, 1.335), (4.04, 1.230), (4.13, 1.125), (S_RG1, 1.035),
	(4.27, 0.992), (4.312, 0.930), (4.336, 0.835), (4.349, 0.725), (L, 0.625),
])
ZB = Curve([
	(0.00, 0.235), (0.06, 0.205), (0.22, 0.188), (0.55, 0.182), (1.10, 0.180),
	(2.80, 0.180), (3.75, 0.194), (4.08, 0.230), (4.26, 0.265), (L, 0.295),
])
WR = Curve([
	(0.00, 0.390), (0.05, 0.505), (0.12, 0.595), (0.24, 0.675), (0.52, 0.735),
	(0.92, 0.766), (S_COWL, 0.778), (1.75, 0.722), (S_WS_TOP, 0.665),
	(2.60, 0.652), (3.25, 0.642), (S_DECK, 0.624), (S_RG0, 0.602),
	(4.02, 0.622), (S_RG1, 0.658), (4.28, 0.684), (4.328, 0.648), (L, 0.530),
])
DR = Curve([
	(0.00, 0.015), (0.22, 0.036), (S_COWL, 0.046), (S_WS_TOP, 0.052),
	(3.55, 0.050), (S_RG1, 0.036), (L, 0.015),
])

SEG_ROWS = [3, 2, 5, 5, 1, 4, 2, 8]
SEG_AB, SEG_BC, SEG_CD, SEG_DE, SEG_EF, SEG_FG, SEG_GH, SEG_HI = range(8)


def bonnet_crease_t(s):
	"""Parameter t along H->I for the Mk3.5 Focus's twin sculpted bonnet power creases: aligned with the outer upper
	corners of the hexagonal grille (|x| ~ 0.32 at s = 0.12) sweeping cleanly back to the A-pillar bases (|x| ~ 0.64)."""
	f = min(1.0, max(0.0, (s - 0.12) / (S_SCUTTLE - 0.12)))
	xc = lerp(0.315, 0.635, f)
	return min(0.66, max(0.16, 1.0 - xc / max(0.32, WR(s))))


def bonnet_crease_dz(s, sub):
	"""Twin sculpted bonnet power creases (SEG_HI): crisp raised ridge along the bonnet flanks plus subtle centre dome."""
	if s >= S_COWL:
		return 0.0
	env = smoothstep(0.10, 0.22, s) * (1.0 - smoothstep(S_SCUTTLE - 0.04, S_COWL, s))
	if env <= 0.0:
		return 0.0
	prof = (0.0, 0.0, -0.0020, 0.0060, 0.0125, 0.0095, 0.0082, 0.0090)
	return prof[sub] * env


def zbottom(s):
	z = ZB(s)
	for sc in (FRONT_AXLE_S, REAR_AXLE_S):
		d = s - sc
		if abs(d) <= ARCH_R:
			z = max(z, TYRE_R + math.sqrt(max(0.0, ARCH_R * ARCH_R - d * d)))
	return z


def cabin(s):
	return smoothstep(S_COWL - 0.10, S_COWL + 0.05, s) * (1.0 - smoothstep(S_RG1 - 0.03, S_RG1 + 0.07, s))


def keys(s):
	w = W(s)
	zb = zbottom(s)
	zsh = ZSH(s)
	A = Vector((0.0, zb))
	B = Vector((w - 0.105, zb))
	C = Vector((w - 0.032, zb + 0.054))
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
	"Bumper": ((0.068, 0.070, 0.074), 0.62, 0.0, {}),
	"Grille": ((0.01, 0.01, 0.01), 0.7, 0.0, {}),
	"Chrome": ((0.86, 0.87, 0.89), 0.10, 1.0, {}),
	"Exhaust": ((0.76, 0.77, 0.79), 0.16, 0.95, {}),
	"Headlight": ((0.32, 0.33, 0.34), 0.08, 0.9, {"emit": ((1.0, 0.95, 0.84), 0.2)}),
	"Indicator": ((1.0, 0.42, 0.04), 0.1, 0.0, {"emit": ((1.0, 0.35, 0.02), 0.7)}),
	"Taillight": ((0.42, 0.01, 0.015), 0.08, 0.0, {"emit": ((1.0, 0.05, 0.03), 0.15)}),
	"LampClear": ((0.88, 0.88, 0.90), 0.08, 0.0, {}),
	"LampBezel": ((0.14, 0.15, 0.16), 0.24, 0.82, {}),
	"Fog": ((0.82, 0.86, 0.92), 0.08, 0.4, {"emit": ((0.94, 0.97, 1.0), 0.45)}),
	"Plate": ((0.94, 0.93, 0.89), 0.45, 0.0, {}),
	"Seat": ((0.03, 0.03, 0.035), 0.9, 0.0, {}),
	"Fabric": ((0.10, 0.10, 0.105), 0.95, 0.0, {}),
	"Tyre": ((0.03, 0.03, 0.03), 0.8, 0.0, {}),
	"Sidewall": ((0.085, 0.085, 0.085), 0.7, 0.0, {}),
	"Rim": ((0.76, 0.77, 0.80), 0.18, 0.92, {}),
	"Steel": ((0.36, 0.37, 0.38), 0.42, 0.5, {}),
	"BrakeDisc": ((0.20, 0.19, 0.19), 0.5, 0.7, {}),
	"BadgeBlue": ((0.015, 0.08, 0.38), 0.18, 0.25, {"coat": 0.9}),
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

	# rolled wheel-arch lips and Focus Mk3.5 sculpted flank character creases (rising shoulder line + lower sill tuck)
	for v in mb.v:
		ax = abs(v.x)
		if ax < 0.45 or v.z < 0.18:
			continue
		s = Y0 - v.y
		for sc in (FRONT_AXLE_S, REAR_AXLE_S):
			d = math.hypot(s - sc, v.z - TYRE_R)
			if d < ARCH_R + 0.036:
				v.x += math.copysign(0.009 * (1.0 - smoothstep(ARCH_R + 0.012, ARCH_R + 0.036, d))
					* (1.0 - smoothstep(0.88, 0.98, v.z)), v.x)
		# crisp upper shoulder crease running from behind the front wheel arch through the door handles into the tail lamp
		if 1.15 < s < 4.10 and ax > 0.76:
			zc = lerp(0.80, 0.955, (s - 1.15) / 2.95)
			dz = abs(v.z - zc)
			if dz < 0.055:
				v.x += math.copysign(0.007 * (1.0 - smoothstep(0.0, 0.055, dz))
					* smoothstep(1.15, 1.40, s) * (1.0 - smoothstep(3.85, 4.10, s)), v.x)
		# sculpted lower door indent sweeping slightly upward towards the rear wheel arch
		if 1.42 < s < 3.18 and ax > 0.80:
			zl = lerp(0.37, 0.43, (s - 1.42) / 1.76)
			dz = abs(v.z - zl)
			if dz < 0.065:
				v.x -= math.copysign(0.008 * (1.0 - smoothstep(0.0, 0.065, dz))
					* smoothstep(1.42, 1.65, s) * (1.0 - smoothstep(2.95, 3.18, s)), v.x)

	# Sleek body-coloured door mirrors on black stalks (Paint only on Body mesh), plus flush body-coloured pull handles
	def body_x_at(s, z):
		pts, _ = section(s)
		best_x = WSH(s)
		for a, b in zip(pts, pts[1:]):
			if (a.y <= z <= b.y) or (b.y <= z <= a.y):
				dy = b.y - a.y
				if abs(dy) > 1e-6:
					t = (z - a.y) / dy
					x = lerp(a.x, b.x, t)
					if x > 0.4:
						best_x = x
						break
		return best_x

	for side in (1, -1):
		mb.box(bl(side * 0.872, 1.67, 0.988), (0.058, 0.095, 0.042), "Trim")
		mb.blob(bl(side * 0.940, 1.71, 1.032), (0.066, 0.048, 0.052), "Paint", e=0.45)
		mb.blob(bl(side * 0.940, 1.755, 1.032), (0.058, 0.006, 0.042), "Chrome", e=0.35)
		# body-coloured pull handles seated tightly flush on the sculpted upper door flank
		for hs, hz in ((2.12, 0.862), (3.08, 0.908)):
			x = body_x_at(hs, hz)
			mb.blob(bl(side * (x + 0.005), hs, hz), (0.009, 0.078, 0.015), "Paint", e=0.4)
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
		if s < 1.05 or c.z < 0.18:
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
		return bl(side * 2.2, u, v), Vector((-side, 0.0, 0.0))
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
	n = (n_surf * 2.4 + Vector((0.0, 1.0, 0.0))).normalized()
	helper = Vector((1, 0, 0)) if abs(n.x) < 0.9 else Vector((0, 1, 0))
	bx = n.cross(helper).normalized()
	by = n.cross(bx)
	tilt = n_surf.cross(n).length
	base = loc + n_surf * (0.0095 + r * tilt + 0.0012)
	segs = 28
	prof = [(r, 0.0095), (r * 0.95, 0.0076), (r * 0.80, 0.0048), (r * 0.60, 0.0024), (r * 0.38, 0.0010), (r * 0.26, 0.0004)]
	rows = [[base + n * d + (bx * math.cos(2 * math.pi * k / segs) + by * math.sin(2 * math.pi * k / segs)) * rr
		for k in range(segs)] for rr, d in prof]
	mb.grid(rows[:2], "Chrome", closed=True, out=n)
	mb.grid(rows[1:], "Headlight", closed=True, out=n)
	mb.disc(base + n * 0.0004, r * 0.26, "Headlight", normal=n, segs=segs)
	mb.ring(base + n * 0.0098, r * 0.94, r * 1.10, "Chrome", normal=n, segs=segs)


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


def ford_oval(pj, mb, proj, cu, cv, rx, ry, base_off, flip=1):
	"""The iconic blue Ford oval badge: dark gasket, chrome oval ring, deep royal blue face, and crisp chrome script."""
	pj.star(mb, ellipse(cu, cv, rx + 0.004, ry + 0.004, 28), proj, "Gasket", offset=base_off, rings=3, samples=1, skirt=0.003)
	pj.star(mb, ellipse(cu, cv, rx, ry, 28), proj, "Chrome", offset=base_off + 0.0020, rings=3, samples=1, skirt=0.002)
	pj.star(mb, ellipse(cu, cv, rx * 0.88, ry * 0.82, 28), proj, "BadgeBlue", offset=base_off + 0.0034, rings=3, samples=1, skirt=0.0)
	# crisp white/chrome Ford lettering across the blue oval
	text_decal(pj, mb, proj, "Ford", cu, cv, rx * 1.15, "Chrome", base_off + 0.0052, flip)


# ---------------------------------------------------------------- lamps, grilles, bumper plastics
FB_AXIS = 0.58
HL_AXIS = 0.78  # headlamp wrap axis: sweeps from sharp inner corner beside the Aston grille back along the front wing
RB_AXIS = LENGTH - 0.58
TL_AXIS = LENGTH - 0.78  # rear wrap axis: sweeps the slim horizontal Mk3.5 tail lamps from tailgate round onto rear wings

# Slim, sharp, swept-back Mk3.5 Focus headlamps (cyl_proj around HL_AXIS: u in degrees from straight ahead, v is z):
# narrow pointed inner nose beside the upper hexagonal grille corner at 29 deg, opening gently for twin reflectors + LED
# DRL brow across the corner, then tapering to a razor-sharp swept point back along the front wing at 80 deg.
HL_U0, HL_U1 = 29.0, 80.0
HL_TOP = Curve([
	(29.0, 0.628), (33.0, 0.650), (41.0, 0.684), (50.0, 0.718),
	(60.0, 0.752), (70.0, 0.784), (77.0, 0.800), (80.0, 0.799),
])
HL_BOT = Curve([
	(29.0, 0.586), (33.0, 0.580), (41.0, 0.588), (50.0, 0.608),
	(60.0, 0.646), (70.0, 0.710), (77.0, 0.774), (80.0, 0.794),
])

# Wide Aston-Martin-style hexagonal front grille (front_proj u = x, v = z):
# Ford's signature 2015 facelift nose: broad chamfered hexagon spanning between the headlamps down into the bumper.
HEX_GRILLE = [
	(-0.345, 0.622), (0.345, 0.622),
	(0.432, 0.542), (0.425, 0.492),
	(0.355, 0.372), (-0.355, 0.372),
	(-0.425, 0.492), (-0.432, 0.542),
]
# Slim lower chin air intake slot below the hexagonal grille
LOWER_INTAKE = [
	(-0.355, 0.322), (0.355, 0.322),
	(0.382, 0.278), (0.362, 0.244),
	(-0.362, 0.244), (-0.382, 0.278),
]

# Slim horizontal-swept wrap-around Mk3.5 Focus tail lamps (cyl_proj around TL_AXIS, rear=True):
# spans from the tailgate (22 deg) horizontally across the rear corner (48 deg) and sweeps forward onto the rear wing (75 deg).
TL_U0, TL_U1 = 22.0, 75.0
TL_TOP = Curve([
	(22.0, 0.922), (28.0, 0.935), (38.0, 0.946), (48.0, 0.962),
	(58.0, 0.986), (67.0, 1.006), (72.5, 1.012), (75.0, 1.006),
])
TL_BOT = Curve([
	(22.0, 0.840), (28.0, 0.824), (38.0, 0.820), (48.0, 0.836),
	(58.0, 0.876), (67.0, 0.935), (72.5, 0.984), (75.0, 0.998),
])


def build_plastics(pj, mb):
	"""Mk3.5 Focus nose & tail plastics: Aston-Martin-style hexagonal grille with chrome frame and horizontal chrome
	slats, front European plate mounted across the lower grille bar, blue Ford oval on the nose tip above the grille,
	angular black corner recesses with elongated rectangular fog lamps, slim lower chin splitter, and rear diffuser."""
	fp = cyl_proj(FB_AXIS, False)

	# 1. Signature wide hexagonal Aston-style front grille: dark gasket, chrome hexagonal surround, deep black grille
	# mesh backing (rings=6 so interior vertices conform tightly to the convex curved nose with zero paint bleed),
	# and crisp horizontal chrome bars across the upper/mid aperture.
	pj.star(mb, dense(HEX_GRILLE, 0.022), front_proj, "Trim", offset=0.0045, rings=6, samples=2, skirt=0.006)
	pj.star(mb, dense(inset(HEX_GRILLE, 0.007), 0.022), front_proj, "Chrome", offset=0.0072, rings=6, samples=2, skirt=0.004)
	pj.star(mb, dense(inset(HEX_GRILLE, 0.020), 0.022), front_proj, "Grille", offset=0.0095, rings=6, samples=2, skirt=0.0)
	# Four crisp horizontal chrome slats spanning inside the hexagonal opening
	for z, hw in ((0.588, 0.358), (0.548, 0.402), (0.508, 0.404), (0.468, 0.382)):
		pj.strip(mb, -hw, hw, z - 0.004, z + 0.004, 32, 1, front_proj, "Chrome", offset=0.0125)
	# Subtle dark lower grille slat behind the plate region
	pj.strip(mb, -0.350, 0.350, 0.398, 0.405, 28, 1, front_proj, "Trim", offset=0.0112)

	# Blue Ford oval badge perched right on the curved nose tip above the hexagonal grille
	ford_oval(pj, mb, front_proj, 0.0, 0.662, 0.062, 0.026, 0.0060, flip=-1)

	# Front European number plate (512 x 105 mm) mounted cleanly on its black plinth across the lower hexagonal grille
	# bottom edge y0_front = 0.382 (matches CarCatalog FOCUS_VISUAL plate_y)
	pj.star(mb, rounded_rect(-0.264, 0.264, 0.376, 0.4927, 0.006), front_proj, "Trim", offset=0.0145, rings=4, samples=2, skirt=0.008)
	pj.star(mb, rounded_rect(-0.2559, 0.2559, 0.382, 0.4867, 0.004), front_proj, "Plate", offset=0.0175, rings=4, samples=2, skirt=0.0)

	# Slim lower black air intake slot below the hexagonal grille
	pj.star(mb, dense(LOWER_INTAKE, 0.025), front_proj, "Trim", offset=0.0035, rings=4, samples=2, skirt=0.005)
	pj.star(mb, dense(inset(LOWER_INTAKE, 0.009), 0.025), front_proj, "Grille", offset=0.0055, rings=4, samples=2, skirt=0.0)
	pj.strip(mb, -0.356, 0.356, 0.280, 0.286, 28, 1, front_proj, "Trim", offset=0.0078)

	# Sleek rectangular lower fog-lamp housings in angular black bumper recesses (wrapped cylindrically round corners!)
	for side in (1, -1):
		cf = lambda u, v, side=side, fp=fp: fp(side * u, v)
		# Angular black bumper recess flanking the hexagonal grille (u = 37..62 deg, z = 0.27..0.42)
		rec_bot = Curve([(37.0, 0.275), (44.0, 0.270), (54.0, 0.276), (62.0, 0.292)])
		rec_top = Curve([(37.0, 0.358), (44.0, 0.402), (54.0, 0.415), (62.0, 0.398)])
		patch_uv(mb, pj, cf, 37.0, 62.0, rec_bot, rec_top, 0.0042, "Trim", nu=14, nv=5, skirt_fn=0.005)
		patch_uv(mb, pj, cf, 38.5, 60.5, lambda u: rec_bot(u) + 0.008, lambda u: rec_top(u) - 0.008, 0.0058, "Grille", nu=12, nv=4)
		# Elongated horizontal rectangular fog lamp with slim chrome accent surround inside the black recess
		fog_bot = Curve([(42.0, 0.305), (50.0, 0.312), (57.5, 0.320)])
		fog_top = Curve([(42.0, 0.355), (50.0, 0.365), (57.5, 0.370)])
		patch_uv(mb, pj, cf, 42.0, 57.5, fog_bot, fog_top, 0.0076, "Chrome", nu=10, nv=4, skirt_fn=0.003)
		patch_uv(mb, pj, cf, 43.0, 56.5, lambda u: fog_bot(u) + 0.005, lambda u: fog_top(u) - 0.005, 0.0094, "Fog",
			nu=10, nv=4, bulge=0.0025)

	# Sporty black front chin splitter lip wrapping round to the front arches
	chin_rows = [(0.190, -0.002), (0.198, 0.008), (0.218, 0.011), (0.228, -0.002)]
	wrap_band(pj, mb, fp, FRONT_AXLE_S, True, [r[0] for r in chin_rows], lambda v, rows=chin_rows: profile(v, rows),
		"Bumper", reach=0.94)
	# Subtle curved bonnet leading shut line arching cleanly above the Ford badge between the headlamps
	patch_uv(mb, pj, front_proj, -0.37, 0.37,
		lambda u: 0.696 - 0.052 * (u / 0.37) ** 2,
		lambda u: 0.699 - 0.052 * (u / 0.37) ** 2,
		0.0012, "Gasket", nu=28, nv=1)

	# Rear lower black bumper diffuser valance wrapping round towards the rear arches
	rp = cyl_proj(RB_AXIS, True)
	rows = [(0.285, -0.002), (0.296, 0.009), (0.314, 0.013), (0.382, 0.013), (0.394, 0.006), (0.402, -0.001)]
	vs = sorted(set([r[0] for r in rows] + spread(0.32, 0.38, 0.02)))
	wrap_band(pj, mb, rp, REAR_AXLE_S, False, vs, lambda v, rows=rows: profile(v, rows), "Bumper", reach=0.90)


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
		# ---- Slim sharp swept-back Mk3.5 headlamps wrapped around HL_AXIS ----
		hl_cyl = cyl_proj(HL_AXIS, False)
		hp = lambda u, v, side=side, hl_cyl=hl_cyl: hl_cyl(side * u, v)
		wing_fade = lambda u: 1.0 - smoothstep(48.0, 78.0, u)

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
			lambda u, v: lerp(0.003, 0.0095, wing_fade(u)), "Gasket", nu=24, nv=8,
			skirt_fn=lambda u, v: lerp(0.006, 0.0125, wing_fade(u)))
		bu0, bu1, bbot, btop = hl_inset(0.8, 1.0, 0.0045)
		patch_uv(mb, pj, hp, bu0, bu1, bbot, btop,
			lambda u, v: lerp(0.0045, 0.0110, wing_fade(u)), "LampBezel", nu=24, nv=8)

		# Signature crisp white LED DRL brow sweeping along the upper headlamp edge
		drl_u0, drl_u1 = 30.0, 74.0
		patch_uv(mb, pj, hp, drl_u0, drl_u1,
			lambda u: max(HL_BOT(u) + 0.006, HL_TOP(u) - lerp(0.014, 0.019, smoothstep(30.0, 52.0, u))),
			lambda u: HL_TOP(u) - 0.0055,
			lambda u, v: lerp(0.0068, 0.0155, wing_fade(u)), "Fog", nu=18, nv=3, bulge=0.0018)

		# Sleek amber turn-signal strip tucked into the outer swept wing corner
		iu0, iu1 = 60.0, 77.0
		def ind_span(u):
			t = min(1.0, max(0.0, (u - iu0) / (iu1 - iu0)))
			w = math.sin(math.pi * t) ** 0.5
			b, tp_ = HL_BOT(u), HL_TOP(u)
			mid = lerp(b, tp_, 0.42)
			half = max(0.002, (tp_ - b) * 0.24 * w)
			return mid - half, mid + half
		patch_uv(mb, pj, hp, iu0, iu1,
			lambda u: ind_span(u)[0], lambda u: ind_span(u)[1],
			lambda u, v: lerp(0.0065, 0.0145, wing_fade(u)), "Indicator", nu=10, nv=4, bulge=0.0018)

		# Twin 3D chrome-rimmed reflector bowls (inboard high beam + outboard projector dipped beam)
		reflector(mb, pj, hp, 38.0, 0.628, 0.034)
		reflector(mb, pj, hp, 49.5, 0.654, 0.042)

		gu0, gu1, gbot, gtop = hl_inset(0.4, 0.5, 0.0022)
		patch_uv(mb, pj, hp, gu0, gu1, gbot, gtop,
			lambda u, v: lerp(0.0085, 0.025, wing_fade(u)), "LampGlass", nu=24, nv=8,
			bulge=lambda u, v: lerp(0.0015, 0.006, wing_fade(u)),
			skirt_fn=lambda u, v: lerp(0.006, 0.017, wing_fade(u)))

		# ---- Slim horizontal-swept wrap-around Mk3.5 tail lamps (cyl_proj around TL_AXIS) ----
		tl_cyl = cyl_proj(TL_AXIS, True)
		tlp = lambda u, v, side=side, tl_cyl=tl_cyl: tl_cyl(side * u, v)
		tl_fade = lambda u: 1.0 - smoothstep(48.0, 73.0, u)

		# Dark gasket surround
		patch_uv(mb, pj, tlp, TL_U0, TL_U1, TL_BOT, TL_TOP,
			lambda u, v: lerp(0.003, 0.006, tl_fade(u)), "Gasket", nu=24, nv=7,
			skirt_fn=lambda u, v: lerp(0.005, 0.009, tl_fade(u)))

		# Split height between the upper/outer red main lens and the lower-inner clear/amber strip
		def tl_split(u):
			b, t = TL_BOT(u), TL_TOP(u)
			return lerp(b, t, 0.36)

		# Upper & outer red tail/brake section (runs the full swept length from 22.8 to 74.2 deg)
		def red_bot(u):
			b = TL_BOT(u) + 0.004
			if u < 54.0:
				return max(b, tl_split(u) + 0.002)
			k = smoothstep(54.0, 62.0, u)
			return lerp(max(b, tl_split(u) + 0.002), b, k)
		def red_top(u):
			return max(red_bot(u) + 0.004, TL_TOP(u) - 0.004)

		patch_uv(mb, pj, tlp, TL_U0 + 0.8, TL_U1 - 0.8, red_bot, red_top,
			lambda u, v: lerp(0.0065, 0.0110, tl_fade(u)), "Taillight", nu=22, nv=6)
		# Glowing brake-light inner bulb strip inside the red lens
		patch_uv(mb, pj, tlp, TL_U0 + 3.0, 64.0,
			lambda u: lerp(red_bot(u), red_top(u), 0.22),
			lambda u: lerp(red_bot(u), red_top(u), 0.78),
			lambda u, v: lerp(0.0080, 0.0128, tl_fade(u)), "TailBulb", nu=16, nv=4)
		# Domed translucent red TailGlass over the red zone
		patch_uv(mb, pj, tlp, TL_U0 + 0.6, TL_U1 - 0.6, red_bot, red_top,
			lambda u, v: lerp(0.0105, 0.0165, tl_fade(u)), "TailGlass", nu=22, nv=6,
			bulge=lambda u, v: lerp(0.0015, 0.0032, tl_fade(u)),
			skirt_fn=lambda u, v: lerp(0.004, 0.007, tl_fade(u)))

		# Lower-inner clear reverse strip (tailgate portion 23.0..41.0 deg) + outer amber turn strip (41.0..53.5 deg)
		patch_uv(mb, pj, tlp, TL_U0 + 1.0, 41.0,
			lambda u: TL_BOT(u) + 0.004, lambda u: max(TL_BOT(u) + 0.008, tl_split(u) - 0.001),
			0.0105, "LampClear", nu=10, nv=3)
		patch_uv(mb, pj, tlp, 41.0, 53.5,
			lambda u: TL_BOT(u) + 0.004, lambda u: max(TL_BOT(u) + 0.008, tl_split(u) - 0.001),
			0.0105, "Indicator", nu=8, nv=3)
		patch_uv(mb, pj, tlp, TL_U0 + 0.8, 53.8,
			lambda u: TL_BOT(u) + 0.0035, lambda u: max(TL_BOT(u) + 0.008, tl_split(u)),
			0.0155, "LampGlass", nu=14, nv=3, bulge=0.0020, skirt_fn=0.005)

		# Sleek slim horizontal red bumper reflectors on the outer rear corners (rear_proj)
		tp = lambda u, v, side=side: rear_proj(side * u, v)
		pj.star(mb, rounded_rect(0.54, 0.70, 0.445, 0.468, 0.008), tp, "Trim", offset=0.004, rings=1, samples=2, skirt=0.003)
		pj.star(mb, rounded_rect(0.548, 0.692, 0.449, 0.464, 0.006), tp, "Taillight", offset=0.0065, rings=1, samples=2, skirt=0.0)

		pj = pj_all
		sp = side_proj(side)
		# Fixed rear quarter-light vertical divider post inside the rear window
		pj.strip(mb, S_QR - 0.006, S_QR + 0.016, 1.035, 1.332, 2, 8, sp, "Trim", offset=0.003)
		# Subtle bright chrome lower window beltline finisher (signature Titanium/Mk3.5 trim) sweeping up the quarter light
		belt_us = spread(S_SAIL, S_Q1 - 0.02, 0.06)
		pj.band(mb, belt_us, [-0.006, 0.0, 0.006],
			lambda u, v: 0.0045 if abs(v) < 0.003 else 0.0015,
			lambda u, v: "Chrome",
			lambda u, v, sp=sp: sp(u, ZSH(u) + 0.009 + v))
		# Dark recesses behind the pull handles + front lock barrel
		for hs, hz in ((2.12, 0.862), (3.08, 0.908)):
			pj.star(mb, rounded_rect(hs - 0.072, hs + 0.072, hz - 0.022, hz + 0.011, 0.011), sp, "Gasket", offset=0.0012,
				rings=1, samples=2)
		pj.star(mb, ellipse(2.12 + 0.092, 0.862, 0.0085, 0.0085, 10), sp, "Chrome", offset=0.004, rings=1, samples=1)
		# Sporty black lower sill trim blade between the wheel arches
		pj.band(mb, spread(1.36, 3.12, 0.05, S_DOOR[:2]), [0.188, 0.208, 0.228],
			lambda u, v: 0.0045 if 0.198 < v < 0.218 else 0.0, lambda u, v: "Bumper", sp)

		# Closed wheel-well liners
		for sc in (FRONT_AXLE_S, REAR_AXLE_S):
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

	# Fuel flap on the right rear quarter panel: clean hollow gasket seam (body-coloured inside!)
	spr = side_proj(1)
	flap_out = rounded_rect(3.75, 3.89, 0.835, 0.945, 0.018)
	flap_in = inset(flap_out, 0.0038)
	for i in range(len(flap_out)):
		i2 = (i + 1) % len(flap_out)
		p0, n0 = pj.hit(*spr(*flap_out[i]))
		p1, n1 = pj.hit(*spr(*flap_out[i2]))
		q1, _ = pj.hit(*spr(*flap_in[i2]))
		q0, _ = pj.hit(*spr(*flap_in[i]))
		n = (n0 + n1).normalized()
		mb.quad(p0 + n * 0.0014, p1 + n * 0.0014, q1 + n * 0.0014, q0 + n * 0.0014, "Gasket", n)

	# ---- Rear end: Focus Mk3.5 tailgate ----
	# Clean plate holder + European plate on the tailgate (y0_rear = 0.625, matches FOCUS_VISUAL plate_y)
	pj.star(mb, rounded_rect(-0.264, 0.264, 0.619, 0.7357, 0.006), rear_proj, "Trim", offset=0.0032, rings=3, samples=2, skirt=0.004)
	pj.star(mb, rounded_rect(-0.2559, 0.2559, 0.625, 0.7297, 0.004), rear_proj, "Plate", offset=0.0058, rings=3, samples=2, skirt=0.0)
	# Slim chrome tailgate grip bar above the plate with dark shadow bevel underneath
	pj.strip(mb, -0.22, 0.22, 0.748, 0.766, 22, 1, rear_proj, "Trim", offset=0.0040)
	pj.strip(mb, -0.21, 0.21, 0.754, 0.765, 22, 1, rear_proj, "Chrome", offset=0.0062)
	# Blue Ford oval badge centred on the tailgate above the chrome grip bar
	ford_oval(pj, mb, rear_proj, 0.0, 0.892, 0.068, 0.028, 0.0042)
	# Chrome FOCUS badge on the lower-left tailgate
	text_decal(pj, mb, rear_proj, "FOCUS", -0.425, 0.750 - 0.003, 0.140, "Gasket", 0.0030, 1)
	text_decal(pj, mb, rear_proj, "FOCUS", -0.429, 0.750, 0.140, "Chrome", 0.0052, 1)
	# Tailgate shut lines meeting the inner tail lamps cleanly and running along the bumper step
	for x in (-0.535, 0.535):
		pj.strip(mb, x + 0.003, x - 0.003, 0.555, 0.835, 1, 14, rear_proj, "Gasket", offset=0.0020)
	pj.strip(mb, -0.535, 0.535, 0.552, 0.558, 30, 1, rear_proj, "Gasket", offset=0.0018)
	pj.strip(mb, S_DECK - 0.003, S_DECK + 0.003, -0.60, 0.60, 1, 36, top_proj, "Gasket", offset=0.0012)
	# Integrated roof spoiler underside trim & high-mounted LED 3rd brake light (tucked cleanly inside spoiler width)
	pj.strip(mb, -0.42, 0.42, 1.402, 1.428, 32, 1, rear_proj, "Trim", offset=0.0035)
	pj.strip(mb, -0.155, 0.155, 1.408, 1.421, 14, 1, rear_proj, "Taillight", offset=0.0062)
	# Rear wiper parked along the base of the raked rear screen
	base_p = pj.hit(*rear_proj(0.0, 1.055))[0]
	mb.blob(base_p + Vector((0, -0.012, 0)), (0.020, 0.015, 0.020), "Trim", e=0.3)
	tip = pj.hit(*rear_proj(0.36, 1.080))[0]
	mb.tube(base_p + Vector((0, -0.016, 0.004)), tip + Vector((0, -0.010, 0)), 0.0055, "Trim", segs=6)

	# Scuttle washer jets and counter-opposed Focus wipers parked at the base of the windscreen
	for x in (-0.30, 0.30):
		pj.star(mb, ellipse(S_SCUTTLE + 0.02, x, 0.011, 0.008, 8), top_proj, "Trim", offset=0.004, rings=1, samples=1)
	for xp, x1 in ((-0.58, -0.04), (0.58, 0.04)):
		base_p = pj.hit(*top_proj(S_SCUTTLE + 0.05, xp))[0]
		mb.blob(base_p + Vector((0, 0, 0.010)), (0.017, 0.017, 0.013), "Trim", e=0.3)
		a = base_p + Vector((0, 0, 0.018))
		b = pj.hit(*top_proj(S_SCUTTLE + 0.20, x1))[0] + Vector((0, 0, 0.016))
		mb.tube(a, b, 0.0055, "Trim", segs=6)
		bx0 = pj.hit(*top_proj(S_SCUTTLE + 0.18, lerp(xp, x1, 0.15)))[0] + Vector((0, 0, 0.012))
		bx1 = pj.hit(*top_proj(S_SCUTTLE + 0.22, x1))[0] + Vector((0, 0, 0.012))
		mb.box((bx0 + bx1) / 2, ((bx1 - bx0).length, 0.011, 0.011), "Trim",
			basis=Matrix.Rotation(math.atan2(bx1.y - bx0.y, bx1.x - bx0.x), 3, "Z"))

	# Short sporty roof aerial at the rear of the roof
	base = pj.hit(*top_proj(3.40, 0.0))[0]
	mb.blob(base + Vector((0, 0, 0.010)), (0.018, 0.032, 0.012), "Trim", e=0.4)
	mb.tube(base + Vector((0, 0, 0.015)), base + Vector((0, -0.10, 0.13)), 0.0038, "Trim", segs=6)

	# Single polished chrome exhaust tailpipe tucked neatly under the right rear diffuser
	mb.tube(bl(0.26, 3.78, 0.245), bl(-0.20, 3.78, 0.245), 0.074, "Steel", segs=14)
	mb.tube(bl(0.40, 3.85, 0.242), bl(0.40, LENGTH - 0.02, 0.248), 0.024, "Exhaust", segs=14, caps=False)
	mb.tube(bl(0.40, LENGTH - 0.02, 0.248), bl(0.40, LENGTH + 0.024, 0.248), 0.030, "Chrome", segs=16, caps=False)
	mb.ring(bl(0.40, LENGTH + 0.024, 0.248), 0.024, 0.031, "Chrome", normal=(0, -1, 0), segs=16)
	mb.disc(bl(0.40, LENGTH + 0.014, 0.248), 0.025, "Under", normal=(0, -1, 0), segs=16)

	# Underbody floor pan and closed engine/boot bays
	mb.box(bl(0, 0.88, 0.195), (0.84, 0.82, 0.03), "Steel")
	mb.box(bl(0, 0.82, 0.42), (1.16, 1.00, 0.38), "Under")
	mb.box(bl(0, 3.85, 0.42), (1.16, 0.72, 0.38), "Under")
	mb.box(bl(0, 2.28, 0.205), (0.98, 2.35, 0.07), "Under")

	return mb, pj


def build_cabin():
	"""The cabin silhouette seen through the glass: sculpted Mk3.5 Focus cockpit dashboard with hooded twin-pod binnacle,
	angled centre stack, three-spoke sporty wheel, bolstered front seats, rear bench and rear-view mirror."""
	mb = MB()

	def cb(x, s, z):
		return bl(x, s, z)

	mb.blob(cb(0, 1.72, 0.92), (0.68, 0.21, 0.09), "Interior", e=0.3)
	mb.box(cb(0, 1.62, 0.65), (1.44, 0.14, 0.44), "Interior")
	mb.box(cb(0, 1.86, 0.68), (0.26, 0.30, 0.42), "Interior")
	mb.box(cb(0, 2.22, 0.40), (0.24, 0.82, 0.18), "Interior")
	mb.blob(cb(-0.38, 1.78, 1.04), (0.17, 0.10, 0.06), "Interior", e=0.35)
	mb.disc(cb(-0.38, 1.76, 1.02), 0.054, "Plate", normal=(0, -0.6, 0.8), segs=16)
	for sx in (-0.07, 0.07):
		mb.disc(cb(sx, 1.82, 0.92), 0.025, "Trim", normal=(0, -0.4, 0.9), segs=12)
		mb.ring(cb(sx, 1.82, 0.92), 0.022, 0.027, "Chrome", normal=(0, -0.4, 0.9), segs=12)
	mb.blob(cb(0, 2.08, 0.50), (0.058, 0.068, 0.04), "Trim", e=0.3)
	mb.tube(cb(0, 2.08, 0.52), cb(0, 2.10, 0.72), 0.0085, "Chrome", segs=8)
	mb.blob(cb(0, 2.10, 0.73), (0.022, 0.022, 0.026), "Seat", e=0.35)
	mb.tube(cb(0.07, 2.42, 0.50), cb(0.07, 2.50, 0.58), 0.010, "Interior", segs=6)
	for px in (-0.46, -0.38, -0.30):
		mb.box(cb(px, 1.68, 0.29), (0.048, 0.012, 0.072), "Steel")
	mb.box(cb(0, 2.18, 1.35), (0.130, 0.015, 0.042), "Interior")
	mb.tube(cb(0, 2.19, 1.36), cb(0, 2.21, 1.40), 0.006, "Trim", segs=6)
	tilt = math.radians(66)
	n = Vector((0, -math.cos(tilt), math.sin(tilt)))
	u = Vector((1, 0, 0))
	v = n.cross(u)
	sw = cb(-0.38, 1.98, 1.00)
	ring = [sw + (u * math.cos(2 * math.pi * k / 24) + v * math.sin(2 * math.pi * k / 24)) * 0.185 for k in range(24)]
	for k in range(24):
		mb.tube(ring[k], ring[(k + 1) % 24], 0.0145, "Seat", segs=8, caps=False)
	mb.tube(sw, sw - v * 0.175, 0.011, "Trim", segs=6)
	mb.tube(sw, sw - u * 0.155 + v * 0.04, 0.011, "Trim", segs=6)
	mb.tube(sw, sw + u * 0.155 + v * 0.04, 0.011, "Trim", segs=6)
	mb.disc(sw, 0.045, "Interior", normal=n, segs=14)
	mb.disc(sw + n * 0.003, 0.022, "BadgeBlue", normal=n, segs=12)
	mb.tube(sw, sw + Vector((0, 0.28, -0.10)), 0.020, "Trim", segs=8)
	lean = Matrix.Rotation(math.radians(-12), 3, "X")
	for sx in (-0.38, 0.38):
		mb.blob(cb(sx, 2.45, 0.43), (0.23, 0.26, 0.085), "Fabric", e=0.40)
		mb.blob(cb(sx, 2.68, 0.81), (0.24, 0.08, 0.36), "Fabric", e=0.45, basis=lean)
		for bx in (-1, 1):
			mb.blob(cb(sx + bx * 0.20, 2.45, 0.48), (0.044, 0.24, 0.088), "Fabric", e=0.4)
			mb.blob(cb(sx + bx * 0.21, 2.66, 0.81), (0.044, 0.08, 0.27), "Fabric", e=0.4, basis=lean)
		mb.blob(cb(sx, 2.74, 1.19), (0.108, 0.05, 0.095), "Fabric", e=0.4, basis=lean)
		for rx in (-0.20, 0.20):
			mb.box(cb(sx + rx, 2.45, 0.25), (0.024, 0.44, 0.034), "Steel")
	mb.blob(cb(0, 3.16, 0.43), (0.64, 0.22, 0.08), "Fabric", e=0.35)
	mb.blob(cb(0, 3.38, 0.83), (0.65, 0.07, 0.34), "Fabric", e=0.40)
	for hx in (-0.38, 0.0, 0.38):
		mb.blob(cb(hx, 3.40, 1.19), (0.098, 0.04, 0.08), "Fabric", e=0.4)
	return mb


def build_stripes(pj):
	mb = MB()
	for x in (-0.16, 0.16):
		pj.strip(mb, 0.20, S_SCUTTLE - 0.01, x - 0.07, x + 0.07, 40, 2, top_proj, "Stripe", offset=0.0018)
		pj.strip(mb, S_WS_TOP + 0.02, S_DECK - 0.02, x - 0.07, x + 0.07, 44, 2, top_proj, "Stripe", offset=0.0018)
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
		pj.strip(mb, 0.20, S_SCUTTLE - 0.01, x0, x1, 40, 1, top_proj, mat, offset=0.0035)
		pj.strip(mb, S_WS_TOP + 0.02, S_DECK - 0.02, x0, x1, 44, 1, top_proj, mat, offset=0.0035)

	def belt(u):
		return 0.72 + 0.05 * smoothstep(1.38, 3.12, u)
	us = [lerp(1.38, 3.12, i / 88) for i in range(89)]
	vs = [-0.075, -0.050, -0.025, 0.045]
	for side in (1, -1):
		sp = side_proj(side)
		pj.band(mb, us, vs, lambda u, v: 0.0045, lambda u, v: "MartiniDark" if v < -0.04 else "MartiniLight" if v < -0.01 else "MartiniRed",
			lambda u, v, sp=sp: sp(u, v + belt(u)))
		martini_roundel(pj, mb, sp, 1.92, 0.59, 0.10, -side)
	martini_roundel(pj, mb, top_proj, 0.76, 0.0, 0.10, 1)
	return mb


def build_abarth(pj):
	mb = MB()
	for side in (1, -1):
		sp = side_proj(side)
		pj.strip(mb, 1.38, 3.12, 0.34, 0.45, 42, 2, sp, "AbarthBlack", offset=0.0035)
		pj.strip(mb, 1.38, 3.12, 0.457, 0.469, 42, 1, sp, "AbarthRed", offset=0.0035)
		text_decal(pj, mb, sp, "ABARTH", 2.25, 0.395, 0.56, "AbarthWhite", 0.0050, -side)

	def plate(pts, mat, off, k=0.15, cu=0.66):
		pj.star(mb, [(cu + x * k, y * k) for x, y in pts], top_proj, mat, offset=off, rings=2, samples=2, skirt=0.0)
	plate([(-0.66, 0.0), (-0.12, 0.56), (0.60, 0.56), (0.60, -0.56), (-0.12, -0.56)], "AbarthWhite", 0.0030)
	plate([(-0.58, 0.0), (-0.10, 0.49), (0.53, 0.49), (0.53, -0.49), (-0.10, -0.49)], "AbarthRed", 0.0036)
	plate([(0.22, 0.49), (0.53, 0.49), (0.53, -0.49), (0.22, -0.49)], "AbarthYellow", 0.0042)
	text_decal(pj, mb, top_proj, "ABARTH", 0.66 + 0.375 * 0.15, 0.0, 0.11, "AbarthBlack", 0.0048, 1)
	return mb


def build_marlboro(pj):
	mb = MB()
	pj.star(mb, [(0.28, -0.50), (0.28, 0.50), (1.12, 0.50), (0.68, 0.0), (1.12, -0.50)], top_proj, "MarlboroRed",
		offset=0.0075, rings=14, samples=16, skirt=0.0)
	for side in (1, -1):
		sp = side_proj(side)
		pj.star(mb, [(1.46, 0.50), (1.46, 0.74), (3.02, 0.74), (2.60, 0.62), (3.02, 0.50)], sp, "MarlboroRed",
			offset=0.005, rings=8, samples=14, skirt=0.0)
		text_decal(pj, mb, sp, "Marlboro", 1.94, 0.62, 0.54, "MarlboroWhite", 0.0065, -side)
	return mb


def dent_delta(key, p):
	"""How far a crash moves the point p (Blender coords) at full damage on one side."""
	s = Y0 - p.y
	d = Vector()
	if key == "front":
		w = smoothstep(1.28, 0.0, s)
		d.y = -0.30 * w ** 1.2 * (1.0 + 0.25 * _nz(p, 0.3))
		d.z = -0.08 * w * (1.0 + _nz(p, 1.1)) + 0.05 * w * w * smoothstep(0.60, 0.80, p.z)
		d.x = 0.05 * w * _nz(p, 2.4)
	elif key == "rear":
		w = smoothstep(LENGTH - 1.00, LENGTH, s)
		d.y = 0.24 * w ** 1.2 * (1.0 + 0.25 * _nz(p, 0.9))
		d.z = -0.05 * w * (1.0 + _nz(p, 2.0))
		d.x = 0.04 * w * _nz(p, 3.1)
	else:
		side = -1.0 if key == "left" else 1.0
		if p.x * side > 0.2:
			g = math.exp(-((s - 2.24) / 0.68) ** 2 - ((p.z - 0.66) / 0.30) ** 2)
			d.x = -side * 0.10 * g * (1.0 + 0.3 * _nz(p, 4.2))
			d.z = -0.02 * g * _nz(p, 5.0)
	return d


def build_wheel():
	"""16" five-twin-spoke Ford alloy with a 215/55 R16 tyre; axle along X, outer face towards +X."""
	mb = MB()
	hw = TYRE_W / 2.0
	R = TYRE_R
	rim = 0.2032  # 16" bead seat radius
	tyre = [(hw - 0.017, rim + 0.005), (hw + 0.002, rim + 0.022), (hw + 0.008, rim + 0.058), (hw + 0.006, R - 0.032),
		(hw - 0.006, R - 0.011), (hw - 0.026, R - 0.0015), (0.044, R), (0.038, R), (0.035, R - 0.008), (0.025, R - 0.008),
		(0.023, R), (-0.023, R), (-0.025, R - 0.008), (-0.035, R - 0.008), (-0.038, R), (-0.044, R), (-hw + 0.026, R - 0.0015),
		(-hw + 0.006, R - 0.011), (-hw - 0.006, R - 0.032), (-hw - 0.008, rim + 0.058), (-hw - 0.002, rim + 0.022),
		(-hw + 0.017, rim + 0.005)]

	def tyre_out(c):
		r = math.hypot(c.y, c.z)
		radial = Vector((0, c.y / r, c.z / r))
		return Vector((c.x, 0, 0)) * 2.0 + radial * (r - 0.262)
	mb.lathe(tyre, 56, "Tyre", out=tyre_out)
	for k in range(42):
		a = 2 * math.pi * k / 42
		for x0, x1 in ((0.046, hw - 0.017), (-hw + 0.017, -0.046)):
			pts = [Vector((x, (R + 0.0003) * math.cos(a + da), (R + 0.0003) * math.sin(a + da))) for x, da in
				((x0, 0.0), (x1, 0.034), (x1, 0.050), (x0, 0.016))]
			mb.poly(pts, "Grille", lambda q: Vector((0, q.y, q.z)))
	for k in range(4):
		a0 = 2 * math.pi * k / 4 + 0.25
		rows = []
		for r in (0.242, 0.274):
			rows.append([Vector((hw + 0.0084 - 0.0032 * (r - 0.242) / 0.032, r * math.cos(a0 + 0.8 * j / 8),
				r * math.sin(a0 + 0.8 * j / 8))) for j in range(9)])
		mb.grid(rows, "Sidewall", out=Vector((1, 0, 0)))

	barrel = [(hw - 0.004, rim - 0.004), (hw - 0.012, rim - 0.015), (0.068, rim - 0.026), (0.056, rim - 0.040), (0.032, rim - 0.044),
		(-0.045, rim - 0.044), (-0.060, rim - 0.034)]
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

	# 5 crisp pairs of twin-spokes (Ford Focus Zetec/Titanium 5-twin-spoke 16" alloy, 5x108 PCD)
	for k in range(5):
		a = 2 * math.pi * k / 5 + 0.28
		for da_in, da_out in ((-0.16, -0.125), (0.16, 0.125)):
			p_hub = Vector((0, 0.056 * math.cos(a + da_in), 0.056 * math.sin(a + da_in)))
			p_end = Vector((0, 0.190 * math.cos(a + da_out), 0.190 * math.sin(a + da_out)))
			bar(p_hub, p_end, 0.023, 0.027, 0.022, 0.017, 0.044, 0.072)
	mb.lathe([(0.044, 0.082), (0.058, 0.076), (0.062, 0.0)], 28, "Rim", out=lambda c: Vector((1, c.y, c.z)))
	for k in range(5):
		a = 2 * math.pi * k / 5 + 0.28 + math.pi / 5
		p = Vector((0.058, 0.056 * math.cos(a), 0.056 * math.sin(a)))
		mb.tube(p, p + Vector((0.012, 0, 0)), 0.0095, "Chrome", segs=6)
	mb.lathe([(0.012, 0.078), (0.012, 0.160), (0.003, 0.160), (0.003, 0.078)], 36, "BrakeDisc", out=lambda c: Vector((1.0, c.y, c.z)))
	mb.lathe([(0.0, 0.0), (0.0, 0.18), (-0.075, 0.18)], 28, "Under", out=lambda c: Vector((1.0, c.y, c.z)))
	mb.lathe([(0.060, 0.038), (0.068, 0.034), (0.072, 0.020), (0.074, 0.0)], 24, "Steel", out=lambda c: Vector((1, c.y, c.z)))
	mb.disc(Vector((0.0742, 0, 0)), 0.020, "BadgeBlue", normal=(1, 0, 0), segs=16)
	a_valve = 0.82
	v_base = Vector((0.048, 0.188 * math.cos(a_valve), 0.188 * math.sin(a_valve)))
	mb.tube(v_base, v_base + Vector((0.020, 0.006 * math.cos(a_valve), 0.006 * math.sin(a_valve))), 0.004, "Trim", segs=6)
	return mb


# ---------------------------------------------------------------- previews
def render_all(cam, out_dir):
	views = {
		"front34": ((4.6, 5.2, 1.68), 38, None),
		"rear34": ((-4.6, -5.0, 1.78), 38, None),
		"side": ((8.5, 0.0, 0.75), 30, None),
		"front": ((0.0, 9.0, 0.80), 22, None),
		"rear": ((0.0, -9.0, 0.90), 22, None),
		"top": ((0.0, 0.0, 9.0), 30, None),
		"nose": ((-1.6, 4.4, 0.95), 30, (-0.1, Y0 - 0.18, 0.56)),
		"tail": ((1.4, -3.7, 1.05), 30, (0.1, Y0 - LENGTH + 0.18, 0.80)),
		"wheel": ((-2.0, Y0 - FRONT_AXLE_S + 0.6, 0.52), 30, (-TRACK_F / 2, Y0 - FRONT_AXLE_S, TYRE_R)),
	}
	carkit.render_views(cam, out_dir, views, (0, 0, 0.72))


LIVERY_VIEWS = {"stripes": ("Stripes", (0.04, 0.16, 0.45)), "martini": ("Martini", (0.92, 0.92, 0.9)),
	"abarth": ("Abarth", (0.75, 0.03, 0.04)), "marlboro": ("Marlboro", (0.92, 0.92, 0.9))}


def render_liveries(objs, cam, out_dir):
	tint = bpy.data.materials["Paint"].node_tree.nodes["Tint"]
	sock = next(s for s in tint.inputs if s.identifier == "A_Color")
	for key, (obj, paint) in LIVERY_VIEWS.items():
		for name in LIVERY_VIEWS.values():
			objs[name[0]].hide_render = name[0] != obj
		sock.default_value = (*paint, 1)
		views = {
			"front34": ((4.6, 5.2, 1.68), 38, None),
			"rear34": ((-4.6, -5.0, 1.78), 38, None),
			"side": ((8.5, 0.0, 0.75), 30, None),
			"top": ((0.0, 0.0, 9.0), 30, None),
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
		low = 1.0 - smoothstep(0.18, 0.64, v.z)
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
	carkit.split_bonnet(objs, Y0, S_SCUTTLE, carkit.material("Trim"))
	for name in [k for k in objs if k in ("Body", "Details", "Stripes", "Martini", "Abarth", "Marlboro") or k.startswith("Bonnet")]:
		add_damage_keys(objs[name], dent_delta)
	kit.export_glb(OUT_GLB, texcoords=False)
	if arg("--blend"):
		bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(arg("--blend")))
	if arg("--renders"):
		view = next((k for k in ("martini", "abarth", "marlboro") if "--" + k in sys.argv), "")
		# Deep Impact Blue for the main hero preview renders
		cam = carkit.setup_preview((0.92, 0.92, 0.9) if view in ("martini", "marlboro") else (0.03, 0.14, 0.42))
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
