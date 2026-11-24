"""Builds the smaller things round a circuit: marshal posts, braking boards, footbridges over the track and
the teams' transporters in the paddock.

Run from the repository root (Blender 4.2 or newer, headless):

    blender -b -P tools/blender/build_furniture.py -- [--renders DIR]

Writes godot/models/furniture.glb. trackside_furniture.gd places the pieces; keep the object names and the
frames below in step with it.

Frames (Blender; glTF turns +Y into Godot -Z): X along the road, +Y away from it, Z up, origin on the ground.

  MarshalPost          a raised post behind the barrier: platform, open cabin with its number board, a marshal
                       in orange with a yellow flag, an extinguisher
  BrakeBoard_100/200/300  a distance board on two legs, its face towards -Y (the approaching cars see it
                       turned to them by Godot)
  BridgeSpan           10 m of footbridge deck along X centred on the origin at deck level (Godot stretches X
                       over the road), a banner hanging on both sides
  BridgeTower          a stair tower rising to the deck at 6.5 m, origin at its foot, the deck end at +Y
  Transporter          a team's articulated truck, 16.5 m, nose towards -X
  TransporterLivery    the trailer's side panels, white (tinted per team by Godot)
  TyreWall             4 m of tyre barrier along X, its front face at Y = 0: a front stack three tyres high and a
                       rear stack four high, in staggered courses
  TyreWallBelt         its conveyor-belt covers: a cap over each stack and three straps down the front, white
                       (tinted per stretch by Godot)
  StageArchStart       truss start gantry spanning a street or rally stage (legs at +-5.6 m, 5.4 m clear)
  StageArchFinish      chequered truss finish gantry for point-to-point / split rally stages
  StageTapeBarrier     3.0 m section of red-and-white hazard barrier tape on two stakes along X
  StageChevronLeft     1.56 m yellow/black corner chevron board pointing left (-X), face towards -Y
  StageChevronRight    1.56 m yellow/black corner chevron board pointing right (+X), face towards -Y
  StageWarningSign     triangular red/yellow caution hazard board (!), face towards -Y
"""
import random
import bpy
import math
import os
import sys
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit  # noqa: E402
from kit import MB, srgb  # noqa: E402

OUT_GLB = os.path.join(kit.ROOT, "godot", "models", "furniture.glb")
DECK = 6.5  # Godot: trackside_furniture.gd BRIDGE_DECK

kit.MATERIALS.update({
	"Concrete": (srgb("#bdb9b0"), 0.88, 0.0, {}),
	"Steel": (srgb("#a4aaaf"), 0.42, 0.65, {}),
	"SteelPaint": (srgb("#3a3f45"), 0.5, 0.35, {}),
	"White": (srgb("#eceeef"), 0.5, 0.0, {}),
	"Orange": (srgb("#f06a12"), 0.6, 0.0, {}),
	"Skin": (srgb("#c89a7a"), 0.7, 0.0, {}),
	"Flag": (srgb("#ffd21a"), 0.7, 0.0, {"double": True}),
	"SignYellow": (srgb("#ffd21a"), 0.45, 0.0, {}),
	"Red": (srgb("#c01a1a"), 0.4, 0.1, {}),
	"Black": (srgb("#141516"), 0.6, 0.0, {}),
	"Glass": (srgb("#27343d"), 0.06, 0.6, {}),
	"Board": (srgb("#ffffff"), 0.5, 0.0, {}),
	"Banner": (srgb("#c8102e"), 0.6, 0.0, {"double": True}),
	"Livery": (srgb("#ffffff"), 0.35, 0.1, {}),
	"Rubber": (srgb("#141414"), 0.85, 0.0, {}),
	"Chrome": (srgb("#d8dcdf"), 0.2, 0.9, {}),
	"Belt": (srgb("#ffffff"), 0.7, 0.0, {}),
})


def marshal_post():
	"""Marshal post: a raised platform with railings, a ladder, a roofed cabin and a post number board."""
	mb = MB()
	# platform on four legs, 1.1 m up, a ladder at the back
	mb.colour = srgb("#8d8a84")
	mb.box((-1.3, -1.0, 1.0), (1.3, 1.2, 1.12), "Concrete")
	mb.colour = srgb("#3a3f45")
	for x in (-1.2, 1.2):
		for y in (-0.9, 1.1):
			mb.box((x - 0.05, y - 0.05, 0), (x + 0.05, y + 0.05, 1.0), "SteelPaint", skip=("-z", "+z"))
	mb.colour = srgb("#a4aaaf")
	for x in (-0.25, 0.25):
		mb.tube((x, 1.35, 0), (x, 1.2, 1.1), 0.025, "Steel", segs=5)
	for k in range(4):
		z = 0.25 + k * 0.25
		mb.tube((-0.25, 1.35 - z * 0.13, z), (0.25, 1.35 - z * 0.13, z), 0.02, "Steel", segs=4, caps=False)
	# railing on the sides and front
	for a, b in (((-1.3, -1.0), (1.3, -1.0)), ((-1.3, -1.0), (-1.3, 0.3)), ((1.3, -1.0), (1.3, 0.3))):
		mb.tube((*a, 2.1), (*b, 2.1), 0.03, "Steel", segs=5)
		mb.tube((*a, 1.6), (*b, 1.6), 0.02, "Steel", segs=4)
	for x in (-1.3, 0.0, 1.3):
		mb.tube((x, -1.0, 1.12), (x, -1.0, 2.1), 0.025, "Steel", segs=4)
	# cabin at the back: open towards the track, a roof reaching over the platform
	mb.colour = srgb("#eceeef")
	mb.box((-1.3, 0.3, 1.12), (1.3, 1.2, 3.3), "White", skip=("-z", "-y"))
	mb.colour = srgb("#f06a12")
	mb.box((-1.45, -1.15, 3.3), (1.45, 1.3, 3.45), "Orange")
	mb.colour = srgb("#27343d")
	for x in (-1.31, 1.31):
		mb.quad((x, 0.45, 2.0), (x, 1.05, 2.0), (x, 1.05, 2.9), (x, 0.45, 2.9), "Glass", (1 if x > 0 else -1, 0, 0))
	# post number board (orange, a white disc for the number) on the roof edge
	mb.colour = srgb("#f06a12")
	mb.box((-0.45, -1.16, 3.45), (0.45, -1.06, 4.15), "Orange")
	mb.colour = (1, 1, 1)
	mb.disc((0, -1.17, 3.8), 0.27, "White", normal=(0, -1, 0), segs=12)
	# extinguisher by the cabin
	mb.colour = srgb("#c01a1a")
	mb.lathe([(1.12, 0.0), (1.12, 0.1), (1.72, 0.1), (1.8, 0.05), (1.82, 0.0)], 8, "Red", centre=(1.0, 0.1, 0))
	# the marshal: boots, orange overalls, arms, head, a yellow flag held out
	x0 = -0.3
	mb.colour = srgb("#141516")
	for sx in (-0.1, 0.1):
		mb.box((x0 + sx - 0.07, -0.55, 1.12), (x0 + sx + 0.07, -0.35, 1.25), "Black")
	mb.colour = srgb("#f06a12")
	for sx in (-0.1, 0.1):
		mb.box((x0 + sx - 0.075, -0.52, 1.25), (x0 + sx + 0.075, -0.38, 2.0), "Orange")
	mb.box((x0 - 0.2, -0.55, 2.0), (x0 + 0.2, -0.33, 2.62), "Orange")
	mb.box((x0 - 0.28, -0.52, 2.0), (x0 - 0.2, -0.38, 2.58), "Orange")
	mb.tube((x0 + 0.22, -0.45, 2.55), (x0 + 0.62, -0.75, 2.3), 0.05, "Orange", segs=5)
	mb.colour = srgb("#c89a7a")
	mb.box((x0 - 0.09, -0.53, 2.62), (x0 + 0.09, -0.35, 2.86), "Skin")
	mb.colour = srgb("#eceeef")
	mb.box((x0 - 0.1, -0.54, 2.84), (x0 + 0.1, -0.34, 2.92), "White")  # cap
	mb.colour = srgb("#a4aaaf")
	mb.tube((x0 + 0.62, -0.75, 2.0), (x0 + 0.62, -0.75, 3.0), 0.015, "Steel", segs=4)
	mb.colour = srgb("#ffd21a")
	mb.quad((x0 + 0.62, -0.75, 2.95), (x0 + 1.32, -0.95, 2.85), (x0 + 1.3, -0.97, 2.35), (x0 + 0.62, -0.75, 2.45), "Flag", (0, -1, 0))
	return mb


BOARD_DIGITS = 0.8 # text size (m): the three digits span about 1.3 of the 1.5 m face
BOARD_BOLD = 0.035 # outline growth per stroke side (m)


def brake_board(label):
	"""Braking board on two posts, showing label (e.g. "100"). 1.5 m square (a real distance board is 1-1.5 m), the
	digits bold and filling the face: the thin 0.62 m default-face digits on a 1.3 m board melted together beyond 40 m
	(playtest 2026-11-22)."""
	mb = MB()
	w, h, z0 = 1.5, 1.5, 0.9
	mb.colour = srgb("#3a3f45")
	for x in (-0.52, 0.52):
		mb.box((x - 0.045, 0.02, 0), (x + 0.045, 0.1, z0 + h - 0.1), "SteelPaint", skip=("-z",))
	mb.colour = (1, 1, 1)
	mb.quad((-w / 2, 0, z0), (w / 2, 0, z0), (w / 2, 0, z0 + h), (-w / 2, 0, z0 + h), "Board", (0, -1, 0))
	mb.colour = srgb("#141516")
	mb.box((-w / 2 - 0.03, 0.0, z0 - 0.03), (w / 2 + 0.03, 0.04, z0 + h + 0.03), "Black", skip=("-y",))
	# a thin black border and the distance in black
	b = 0.05
	for a, c in (((-w / 2, z0), (w / 2, z0 + b)), ((-w / 2, z0 + h - b), (w / 2, z0 + h)),
			((-w / 2, z0), (-w / 2 + b, z0 + h)), ((w / 2 - b, z0), (w / 2, z0 + h))):
		mb.quad((a[0], -0.003, a[1]), (c[0], -0.003, a[1]), (c[0], -0.003, c[1]), (a[0], -0.003, c[1]), "Black", (0, -1, 0))
	kit.text_mesh(mb, label, (0, -0.006, z0 + h * 0.5), BOARD_DIGITS, "Black", axis_u=(1, 0, 0), axis_v=(0, 0, 1),
		bold=BOARD_BOLD)
	return mb


def bridge_span():
	"""Footbridge deck section over the track (10 m long)."""
	mb = MB()
	L = 10.0
	w = 1.6
	mb.colour = srgb("#8d8a84")
	mb.box((-L / 2, -w, DECK - 0.35), (L / 2, w, DECK), "Concrete", skip=("-x", "+x"))
	mb.colour = srgb("#3a3f45")
	# truss sides: top chord, verticals and diagonals
	for y in (-w, w):
		mb.tube((-L / 2, y, DECK + 1.9), (L / 2, y, DECK + 1.9), 0.08, "SteelPaint", segs=6, caps=False)
		for k in range(5):
			x = -L / 2 + k * L / 4
			mb.tube((x, y, DECK), (x, y, DECK + 1.9), 0.06, "SteelPaint", segs=5, caps=False)
			if k < 4:
				mb.tube((x, y, DECK) if k % 2 == 0 else (x, y, DECK + 1.9),
					(x + L / 4, y, DECK + 1.9) if k % 2 == 0 else (x + L / 4, y, DECK), 0.045, "SteelPaint", segs=4, caps=False)
	# a roof of light sheeting
	mb.colour = srgb("#dcdedf")
	mb.box((-L / 2, -w - 0.2, DECK + 1.95), (L / 2, w + 0.2, DECK + 2.05), "White", skip=("-x", "+x"))
	# banners on both sides, below the deck
	mb.colour = (1, 1, 1)
	for y, n in ((-w - 0.05, -1), (w + 0.05, 1)):
		mb.quad((-L / 2, y, DECK - 1.6), (L / 2, y, DECK - 1.6), (L / 2, y, DECK - 0.35), (-L / 2, y, DECK - 0.35), "Banner", (0, n, 0))
	return mb


def bridge_tower():
	"""Stair tower at each end of a footbridge, its landing at deck level."""
	mb = MB()
	# a stair tower of four flights round a concrete core, the landing at deck level at its +Y side
	s = 2.2
	mb.colour = srgb("#bdb9b0")
	mb.box((-0.8, -0.8, 0), (0.8, 0.8, DECK + 2.0), "Concrete", skip=("-z",))
	mb.colour = srgb("#a4aaaf")
	steps = 26
	for k in range(steps):
		t = k / steps
		a = t * 2 * math.pi * 1.25
		z = t * DECK
		r0, r1 = 0.8, s
		c, sn = math.cos(a), math.sin(a)
		c2, s2 = math.cos(a + 0.33), math.sin(a + 0.33)
		pts = [(r0 * c, r0 * sn, z), (r1 * c, r1 * sn, z), (r1 * c2, r1 * s2, z), (r0 * c2, r0 * sn * 0 + r0 * s2, z)]
		mb.poly([(p[0], p[1], p[2] + 0.08) for p in pts], "Steel", (0, 0, 1))
		mb.poly(list(reversed(pts)), "Steel", (0, 0, -1))
	for k in range(10):
		a = k * 2 * math.pi / 10
		mb.tube((s * math.cos(a), s * math.sin(a), 0), (s * math.cos(a), s * math.sin(a), DECK + 1.1), 0.035, "Steel", segs=4)
	mb.colour = srgb("#8d8a84")
	mb.box((-s, -s, DECK - 0.3), (s, s + 0.4, DECK), "Concrete")
	mb.colour = srgb("#dcdedf")
	mb.box((-s - 0.2, -s - 0.2, DECK + 2.0), (s + 0.2, s + 0.6, DECK + 2.1), "White")
	return mb


def transporter():
	"""Team transporter: tractor unit and trailer for the paddock."""
	mb = MB()
	L = 16.5
	# tractor unit at -X: cab, grille, wheels; trailer behind
	cab_x0, cab_x1 = -L / 2, -L / 2 + 2.4
	mb.colour = srgb("#eceeef")
	mb.box((cab_x0, -1.25, 0.9), (cab_x1, 1.25, 3.6), "Livery")
	mb.colour = srgb("#27343d")
	mb.quad((cab_x0 - 0.01, -1.1, 2.3), (cab_x0 - 0.01, 1.1, 2.3), (cab_x0 - 0.01, 1.1, 3.3), (cab_x0 - 0.01, -1.1, 3.3), "Glass", (-1, 0, 0))
	for y in (-1.26, 1.26):
		mb.quad((cab_x0 + 0.3, y, 2.3), (cab_x0 + 1.3, y, 2.3), (cab_x0 + 1.3, y, 3.2), (cab_x0 + 0.3, y, 3.2), "Glass", (0, 1 if y > 0 else -1, 0))
	mb.colour = srgb("#141516")
	mb.box((cab_x0 - 0.05, -1.0, 1.0), (cab_x0 + 0.02, 1.0, 2.1), "Black")
	mb.colour = srgb("#d8dcdf")
	for y in (-0.85, 0.85):
		mb.box((cab_x0 - 0.06, y - 0.2, 1.15), (cab_x0, y + 0.2, 1.35), "Chrome")
	mb.colour = srgb("#3a3f45")
	mb.box((cab_x1, -1.1, 0.9), (L / 2, 1.1, 1.25), "SteelPaint")
	mb.colour = srgb("#141414")
	for x in (cab_x0 + 1.2, cab_x0 + 3.6, cab_x0 + 4.9, L / 2 - 3.2, L / 2 - 2.0, L / 2 - 0.8):
		for y in (-1.05, 1.05):
			mb.lathe([(0.0, 0.0), (0.0, 0.52), (0.4, 0.52), (0.4, 0.0)], 10, "Rubber", centre=(x, y - 0.2 if y > 0 else y - 0.2, 0.52))
	# trailer box: dark roof and ends, white sides for the livery panel
	tx0 = cab_x1 + 0.4
	mb.colour = srgb("#d8dadc")
	mb.box((tx0, -1.27, 1.25), (L / 2, 1.27, 4.0), "White", skip=("-y", "+y"))
	return mb


def transporter_livery():
	"""The transporter's trailer side panels, white so they can be tinted per team."""
	mb = MB()
	L = 16.5
	tx0 = -L / 2 + 2.8
	mb.colour = (1, 1, 1)
	for y, n in ((-1.28, -1), (1.28, 1)):
		pts = [(tx0, y, 1.25), (L / 2, y, 1.25), (L / 2, y, 4.0), (tx0, y, 4.0)]
		mb.poly(pts if n < 0 else list(reversed(pts)), "Livery", (0, n, 0))
	return mb


WALL_L = 4.0  # Godot: trackside_furniture.gd TYRE_SEGMENT
TYRE_R = 0.333
TYRE_H = 0.25
# the belt covers hide the tops, so a tyre is just its tread with the chamfered rims (12 sides, open ends)
TYRE_PROFILE = [(0.0, 0.3), (0.03, TYRE_R), (TYRE_H - 0.03, TYRE_R), (TYRE_H, 0.3)]
FRONT_LAYERS, REAR_LAYERS = 3, 4


def tyre_wall():
	"""A WALL_L stretch of stacked tyres in front of a barrier."""
	mb = MB()
	rnd = random.Random(11)
	n = 6
	pitch = WALL_L / n
	# the dark core behind the tyres, so the gaps between them don't show the sky
	mb.colour = srgb("#0c0c0d")
	mb.box((-WALL_L / 2, 0.12, 0), (WALL_L / 2, 1.24, FRONT_LAYERS * TYRE_H - 0.02), "Rubber")
	mb.box((-WALL_L / 2, 0.7, 0), (WALL_L / 2, 1.24, REAR_LAYERS * TYRE_H - 0.02), "Rubber")
	# the rear stack only shows over the front one (its lower courses are hidden)
	for y, first, layers in ((TYRE_R, 0, FRONT_LAYERS), (3 * TYRE_R, FRONT_LAYERS, REAR_LAYERS)):
		for layer in range(first, layers):
			# every other course shifted half a tyre; the pattern repeats from one segment to the next
			shift = 0.5 * pitch if layer % 2 else 0.0
			for k in range(n):
				x = -WALL_L / 2 + pitch * (k + 0.5) + shift
				g = rnd.uniform(0.09, 0.2)
				mb.colour = (g * 0.5, g * 0.5, g * 0.5 + 0.004)
				mb.lathe(TYRE_PROFILE, 12, "Rubber", centre=(x, y, layer * TYRE_H))
	return mb


def tyre_wall_belt():
	"""The conveyor-belt cover strapped over the face of a tyre wall."""
	mb = MB()
	mb.colour = (1, 1, 1)
	h1, h2 = FRONT_LAYERS * TYRE_H, REAR_LAYERS * TYRE_H
	t = 0.016
	half = WALL_L / 2
	# a cap belt over each stack, a riser on the step between them, and straps over the front stack
	mb.box((-half, 0.0, h1), (half, 0.68, h1 + t), "Belt")
	mb.box((-half, 0.68, h2), (half, 1.36, h2 + t), "Belt")
	mb.box((-half, 0.66, h1), (half, 0.66 + t, h2), "Belt")
	for x in (-1.33, 0.0, 1.33):
		mb.box((x - 0.09, -0.025, 0.02), (x + 0.09, 0.0, h1), "Belt")
	mb.colour = srgb("#a4aaaf")
	for x in (-1.33, 0.0, 1.33):
		for z in (0.12, h1 - 0.14):
			mb.box((x - 0.035, -0.04, z - 0.035), (x + 0.035, -0.025, z + 0.035), "Steel")
	return mb


def stage_arch(label="START", finish=False):
	"""Street/rally stage portal arch: dark steel lattice legs at +-5.6 m (clear span 10.4 m, clear height 5.4 m)
	with a crisp motorsport header fascia reading START or FINISH on both faces."""
	mb = MB()
	lx = 5.6
	h_clear = 5.4
	h_top = 6.75
	lw, ld = 0.36, 0.32
	for sx in (-1, 1):
		cx = sx * lx
		# weighted concrete ballast base pad
		mb.colour = srgb("#9b9890")
		mb.box((cx - 0.62, -0.52, 0.0), (cx + 0.62, 0.52, 0.28), "Concrete", skip=("-z",))
		# 4 corner steel chords of the leg tower
		mb.colour = srgb("#2c3137")
		for dx in (-lw, lw):
			for dy in (-ld, ld):
				mb.box((cx + dx - 0.04, dy - 0.04, 0.28), (cx + dx + 0.04, dy + 0.04, h_top), "SteelPaint", skip=("-z",))
		# horizontal & diagonal truss bracing up each leg
		mb.colour = srgb("#8f969c")
		bays = 6
		for k in range(bays):
			z0 = 0.35 + k * (h_clear - 0.45) / bays
			z1 = 0.35 + (k + 1) * (h_clear - 0.45) / bays
			for dy in (-ld, ld):
				mb.tube((cx - lw, dy, z0), (cx + lw, dy, z0), 0.022, "Steel", segs=4, caps=False)
				if k % 2 == 0:
					mb.tube((cx - lw, dy, z0), (cx + lw, dy, z1), 0.02, "Steel", segs=4, caps=False)
				else:
					mb.tube((cx + lw, dy, z0), (cx - lw, dy, z1), 0.02, "Steel", segs=4, caps=False)
			for dx in (-lw, lw):
				mb.tube((cx + dx, -ld, z0), (cx + dx, ld, z0), 0.022, "Steel", segs=4, caps=False)
		# crisp sponsor/stage plates mounted on front and back of each leg
		for sy in (-1, 1):
			y0 = sy * (ld + 0.045)
			y1 = y0 + sy * 0.008
			mb.colour = (1, 1, 1)
			mb.quad((cx - 0.42, y0, 1.55), (cx + 0.42, y0, 1.55), (cx + 0.42, y0, 3.55), (cx - 0.42, y0, 3.55), "White", (0, sy, 0))
			bar_mat = "Black" if finish else "Red"
			mb.colour = srgb("#141516") if finish else srgb("#c01a1a")
			for za, zb in ((1.55, 1.85), (3.25, 3.55)):
				mb.quad((cx - 0.42, y1, za), (cx + 0.42, y1, za), (cx + 0.42, y1, zb), (cx - 0.42, y1, zb), bar_mat, (0, sy, 0))
	# overhead header truss box spanning between the legs
	bx = lx + lw + 0.06
	by = ld + 0.04
	mb.colour = srgb("#2c3137")
	mb.box((-bx, -by, h_clear), (bx, by, h_top), "SteelPaint")
	# front (-Y) and rear (+Y) header fascia boards
	for sy in (-1, 1):
		y0 = sy * (by + 0.012)
		y1 = y0 + sy * 0.010
		y2 = y0 + sy * 0.020
		ax_u = (1, 0, 0) if sy < 0 else (-1, 0, 0)
		# base banner face
		if finish:
			mb.colour = (1, 1, 1)
			mb.quad((-bx, y0, h_clear), (bx, y0, h_clear), (bx, y0, h_top), (-bx, y0, h_top), "White", (0, sy, 0))
			# bold two-row chequered wings on left and right, dark centre plaque for FINISH lettering
			sq = 0.45
			for row in range(3):
				zr0 = h_clear + row * ((h_top - h_clear) / 3.0)
				zr1 = h_clear + (row + 1) * ((h_top - h_clear) / 3.0)
				for k in range(26):
					x0 = -bx + k * (2.0 * bx / 26.0)
					x1 = -bx + (k + 1) * (2.0 * bx / 26.0)
					if abs((x0 + x1) * 0.5) < 2.85:
						continue
					if (k + row) % 2 == 0:
						mb.colour = srgb("#141516")
						mb.quad((x0, y1, zr0), (x1, y1, zr0), (x1, y1, zr1), (x0, y1, zr1), "Black", (0, sy, 0))
			# dark centre plaque + yellow motorsport accent bars
			mb.colour = srgb("#141516")
			mb.quad((-2.9, y1, h_clear + 0.08), (2.9, y1, h_clear + 0.08), (2.9, y1, h_top - 0.08), (-2.9, y1, h_top - 0.08), "Black", (0, sy, 0))
			mb.colour = srgb("#ffd21a")
			for za, zb in ((h_clear, h_clear + 0.10), (h_top - 0.10, h_top)):
				mb.quad((-2.9, y2, za), (2.9, y2, za), (2.9, y2, zb), (-2.9, y2, zb), "SignYellow", (0, sy, 0))
			mb.colour = (1, 1, 1)
			kit.text_mesh(mb, label, (0.0, y2, (h_clear + h_top) * 0.5), 0.78, "White", axis_u=ax_u, axis_v=(0, 0, 1), bold=0.025)
		else:
			mb.colour = srgb("#c01a1a")
			mb.quad((-bx, y0, h_clear), (bx, y0, h_clear), (bx, y0, h_top), (-bx, y0, h_top), "Red", (0, sy, 0))
			# crisp white top border and chequered bottom strip
			mb.colour = (1, 1, 1)
			mb.quad((-bx, y1, h_top - 0.11), (bx, y1, h_top - 0.11), (bx, y1, h_top), (-bx, y1, h_top), "White", (0, sy, 0))
			cn = 24
			cw = 2.0 * bx / cn
			for k in range(cn):
				x0 = -bx + k * cw
				x1 = x0 + cw
				mb.colour = (1, 1, 1) if k % 2 == 0 else srgb("#141516")
				mb.quad((x0, y1, h_clear), (x1, y1, h_clear), (x1, y1, h_clear + 0.18), (x0, y1, h_clear + 0.18),
					"White" if k % 2 == 0 else "Black", (0, sy, 0))
			# dark centre panel behind START text for crisp contrast in any lighting
			mb.colour = srgb("#141516")
			mb.quad((-2.7, y1, h_clear + 0.20), (2.7, y1, h_clear + 0.20), (2.7, y1, h_top - 0.12), (-2.7, y1, h_top - 0.12), "Black", (0, sy, 0))
			mb.colour = (1, 1, 1)
			kit.text_mesh(mb, label, (0.0, y2, (h_clear + h_top) * 0.5 + 0.04), 0.78, "White", axis_u=ax_u, axis_v=(0, 0, 1), bold=0.025)
	return mb


def stage_tape_barrier():
	"""3.0 m section of red-and-white rally hazard tape strung between two stakes along X."""
	mb = MB()
	half_l = 1.5
	# two slim stakes with high-visibility red/white top caps
	for sx in (-1, 1):
		px = sx * (half_l - 0.04)
		mb.colour = srgb("#3a3f45")
		mb.box((px - 0.028, -0.028, 0.0), (px + 0.028, 0.028, 0.82), "SteelPaint", skip=("-z",))
		mb.colour = (1, 1, 1)
		mb.box((px - 0.030, -0.030, 0.82), (px + 0.030, 0.030, 0.96), "White", skip=("-z",))
		mb.colour = srgb("#c01a1a")
		mb.box((px - 0.030, -0.030, 0.96), (px + 0.030, 0.030, 1.08), "Red", skip=("-z",))
	# two taut horizontal hazard-tape ribbons (6 alternating red/white bands each, visible from both sides)
	bands = 6
	bw = (2.0 * half_l) / bands
	x_start = -half_l
	for z0, z1, shift in ((0.54, 0.62, 1), (0.86, 0.94, 0)):
		for k in range(bands):
			xa = x_start + k * bw
			xb = xa + bw
			is_red = ((k + shift) % 2) == 0
			mat = "Red" if is_red else "White"
			mb.colour = srgb("#c01a1a") if is_red else (1, 1, 1)
			for sy in (-1, 1):
				y = sy * 0.008
				mb.quad((xa, y, z0), (xb, y, z0), (xb, y, z1), (xa, y, z1), mat, (0, sy, 0))
	return mb


def stage_chevron(direction=1):
	"""Corner chevron board on two posts, face towards -Y (approaching cars).
	direction = +1 points towards +X (driver's right); -1 points towards -X (driver's left)."""
	mb = MB()
	w, h, z0 = 1.56, 0.74, 1.04
	mb.colour = srgb("#3a3f45")
	for x in (-0.54, 0.54):
		mb.box((x - 0.035, 0.02, 0.0), (x + 0.035, 0.09, z0 + h - 0.06), "SteelPaint", skip=("-z",))
	# yellow front face + dark metal backing (starts at y=0.002 to avoid grazing edge artifacts)
	mb.colour = srgb("#ffd21a")
	mb.quad((-w / 2, 0.0, z0), (w / 2, 0.0, z0), (w / 2, 0.0, z0 + h), (-w / 2, 0.0, z0 + h), "SignYellow", (0, -1, 0))
	mb.colour = srgb("#141516")
	mb.box((-w / 2 - 0.02, 0.002, z0 - 0.02), (w / 2 + 0.02, 0.042, z0 + h + 0.02), "Black", skip=("-y",))
	# thin black border
	b = 0.04
	for a, c in (((-w / 2, z0), (w / 2, z0 + b)), ((-w / 2, z0 + h - b), (w / 2, z0 + h)),
			((-w / 2, z0), (-w / 2 + b, z0 + h)), ((w / 2 - b, z0), (w / 2, z0 + h))):
		mb.quad((a[0], -0.003, a[1]), (c[0], -0.003, a[1]), (c[0], -0.003, c[1]), (a[0], -0.003, c[1]), "Black", (0, -1, 0))
	# two bold black chevrons centred symmetrically on the face, pointing along direction (+1 right, -1 left)
	zm = z0 + h * 0.5
	zb = z0 + 0.08
	zt = z0 + h - 0.08
	arm_w = 0.20
	half_span = 0.25  # total horizontal extent of one chevron = 0.50 m
	for cx in (-0.31, 0.31):
		# symmetric around cx: outer tip at cx + half_span*dir, inner tail at cx - half_span*dir
		t_outer = cx + half_span * direction
		t_inner = t_outer - arm_w * direction
		tail_inner = cx - half_span * direction
		tail_outer = tail_inner + arm_w * direction
		mb.quad((tail_inner, -0.006, zt), (tail_outer, -0.006, zt), (t_outer, -0.006, zm), (t_inner, -0.006, zm), "Black", (0, -1, 0))
		mb.quad((t_inner, -0.006, zm), (t_outer, -0.006, zm), (tail_outer, -0.006, zb), (tail_inner, -0.006, zb), "Black", (0, -1, 0))
	return mb


def stage_warning_sign():
	"""Triangular red-and-yellow rally hazard warning sign (!) on a post, face towards -Y."""
	mb = MB()
	z0 = 1.24
	side = 1.12
	h = side * math.sqrt(3.0) * 0.5  # ~0.97 m
	hw = side * 0.5
	# single central steel post
	mb.colour = srgb("#3a3f45")
	mb.box((-0.035, 0.02, 0.0), (0.035, 0.09, z0 + h * 0.78), "SteelPaint", skip=("-z",))
	# dark backing prism (triangle extruded back 0.035 m)
	tri_f = [(-hw, 0.0, z0), (hw, 0.0, z0), (0.0, 0.0, z0 + h)]
	tri_b = [(-hw, 0.035, z0), (hw, 0.035, z0), (0.0, 0.035, z0 + h)]
	mb.colour = srgb("#141516")
	mb.poly(tri_b, "Black", (0, 1, 0))
	for i in range(3):
		j = (i + 1) % 3
		edge = Vector(tri_f[j]) - Vector(tri_f[i])
		out = edge.cross(Vector((0, 1, 0)))
		mb.quad(tri_f[i], tri_f[j], tri_b[j], tri_b[i], "Black", out)
	# outer red triangle face
	mb.colour = srgb("#c01a1a")
	mb.poly(tri_f, "Red", (0, -1, 0))
	# inner yellow triangle inset
	cx, cz = 0.0, z0 + h / 3.0
	inset = 0.72
	inner = [(cx + (p[0] - cx) * inset, -0.003, cz + (p[2] - cz) * inset) for p in tri_f]
	mb.colour = srgb("#ffd21a")
	mb.poly(inner, "SignYellow", (0, -1, 0))
	# bold black exclamation mark (!)
	mb.colour = srgb("#141516")
	mb.quad((-0.042, -0.006, z0 + 0.30), (0.042, -0.006, z0 + 0.30), (0.056, -0.006, z0 + 0.68), (-0.056, -0.006, z0 + 0.68), "Black", (0, -1, 0))
	mb.quad((-0.045, -0.006, z0 + 0.16), (0.045, -0.006, z0 + 0.16), (0.045, -0.006, z0 + 0.25), (-0.045, -0.006, z0 + 0.25), "Black", (0, -1, 0))
	return mb


PIECES = {"MarshalPost": marshal_post, "BrakeBoard_100": lambda: brake_board("100"),
	"BrakeBoard_200": lambda: brake_board("200"), "BrakeBoard_300": lambda: brake_board("300"),
	"BrakeBoard_400": lambda: brake_board("400"), "BrakeBoard_500": lambda: brake_board("500"),
	"BridgeSpan": bridge_span, "BridgeTower": bridge_tower, "Transporter": transporter,
	"TransporterLivery": transporter_livery, "TyreWall": tyre_wall, "TyreWallBelt": tyre_wall_belt,
	"StageArchStart": lambda: stage_arch("START", False),
	"StageArchFinish": lambda: stage_arch("FINISH", True),
	"StageTapeBarrier": stage_tape_barrier,
	"StageChevronLeft": lambda: stage_chevron(-1),
	"StageChevronRight": lambda: stage_chevron(1),
	"StageWarningSign": stage_warning_sign}


def main():
	"""Builds every piece in PIECES and exports them to models/furniture.glb (plus previews with --renders)."""
	for ob in list(bpy.data.objects):
		bpy.data.objects.remove(ob)
	objs = {}
	for name, fn in PIECES.items():
		mb = fn()
		print(f"{name}: {mb.tris()} tris")
		objs[name] = mb.emit(name)
	kit.export_glb(OUT_GLB, list(objs.values()))
	out = kit.arg("--renders")
	if out:
		cam = kit.setup_preview(ground=120.0)
		kit.place(objs["MarshalPost"], (-12, 0, 0))
		for i, k in enumerate(("500", "400", "300", "200", "100")):
			kit.place(objs["BrakeBoard_" + k], (-6 + i * 2.0, -2, 0))
		kit.place(objs["Transporter"], (6, 6, 0))
		kit.place(objs["TransporterLivery"], (6, 6, 0))
		kit.place(objs["BridgeSpan"], (0, 25, 0), scale=(2.0, 1, 1))
		kit.place(objs["BridgeTower"], (-12, 25, 0))
		kit.place(objs["BridgeTower"], (12, 25, 0), rot_z=math.pi)
		for i in range(3):
			kit.place(objs["TyreWall"], (-14 + i * WALL_L, -9, 0))
			kit.place(objs["TyreWallBelt"], (-14 + i * WALL_L, -9, 0))
		for ob in objs.values():
			ob.hide_render = True
		kit.render(cam, os.path.join(out, "furniture.png"), (0, -26, 9), (0, 6, 2.5), 60)
		kit.render(cam, os.path.join(out, "furniture_close.png"), (-9, -7, 3.2), (-12, 0, 2.2), 50)
		kit.render(cam, os.path.join(out, "tyrewall.png"), (-6, -14, 2.4), (-10, -9, 0.6), 50)
		# Dedicated preview of the street/rally stage dressing pieces
		for ob in list(bpy.data.objects):
			if ob.type == "MESH":
				ob.hide_render = True
		kit.place(objs["StageArchStart"], (-7.5, 6, 0))
		kit.place(objs["StageArchFinish"], (7.5, 6, 0))
		kit.place(objs["StageTapeBarrier"], (-4.5, -2.5, 0))
		kit.place(objs["StageTapeBarrier"], (-1.5, -2.5, 0))
		kit.place(objs["StageChevronLeft"], (1.8, -2.5, 0))
		kit.place(objs["StageChevronRight"], (3.9, -2.5, 0))
		kit.place(objs["StageWarningSign"], (5.8, -2.5, 0))
		kit.render(cam, os.path.join(out, "stage_dressing.png"), (0, -18, 4.5), (0, 2, 2.6), 45)
		kit.render(cam, os.path.join(out, "stage_signs.png"), (2.5, -7.8, 1.8), (2.2, -2.5, 1.3), 45)


main()
