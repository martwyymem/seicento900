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


DIGITS = {"100": "100", "200": "200", "300": "300"}


def brake_board(label):
	mb = MB()
	w, h, z0 = 1.3, 1.3, 0.9
	mb.colour = srgb("#3a3f45")
	for x in (-0.45, 0.45):
		mb.box((x - 0.04, 0.02, 0), (x + 0.04, 0.1, z0 + h - 0.1), "SteelPaint", skip=("-z",))
	mb.colour = (1, 1, 1)
	mb.quad((-w / 2, 0, z0), (w / 2, 0, z0), (w / 2, 0, z0 + h), (-w / 2, 0, z0 + h), "Board", (0, -1, 0))
	mb.colour = srgb("#141516")
	mb.box((-w / 2 - 0.03, 0.0, z0 - 0.03), (w / 2 + 0.03, 0.04, z0 + h + 0.03), "Black", skip=("-y",))
	# a black border and the distance in black
	for a, b in (((-w / 2, z0), (w / 2, z0 + 0.06)), ((-w / 2, z0 + h - 0.06), (w / 2, z0 + h)),
			((-w / 2, z0), (-w / 2 + 0.06, z0 + h)), ((w / 2 - 0.06, z0), (w / 2, z0 + h))):
		mb.quad((a[0], -0.003, a[1]), (b[0], -0.003, a[1]), (b[0], -0.003, b[1]), (a[0], -0.003, b[1]), "Black", (0, -1, 0))
	kit.text_mesh(mb, label, (0, -0.006, z0 + h * 0.5 - 0.26), 0.62, "Black", axis_u=(1, 0, 0), axis_v=(0, 0, 1))
	return mb


def bridge_span():
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


PIECES = {"MarshalPost": marshal_post, "BrakeBoard_100": lambda: brake_board("100"),
	"BrakeBoard_200": lambda: brake_board("200"), "BrakeBoard_300": lambda: brake_board("300"),
	"BridgeSpan": bridge_span, "BridgeTower": bridge_tower, "Transporter": transporter,
	"TransporterLivery": transporter_livery, "TyreWall": tyre_wall, "TyreWallBelt": tyre_wall_belt}


def main():
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
		for i, k in enumerate(("300", "200", "100")):
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


main()
