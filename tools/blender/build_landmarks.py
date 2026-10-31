"""Builds the circuits' landmarks: the buildings and structures you'd know a circuit by.

Run from the repository root (Blender 4.2 or newer, headless):

    blender -b -P tools/blender/build_landmarks.py -- [--renders DIR]

Writes godot/models/landmarks.glb. surroundings.gd places the pieces where OpenStreetMap maps them
(build_surroundings.py LANDMARKS); keep the object names and the nominal sizes (surroundings.gd
LANDMARK_SIZE) in step with this script.

Frame (Blender; glTF turns +Y into Godot -Z): X along the footprint's long side, -Y the front (turned
towards the circuit by Godot), Z up, origin on the ground at the footprint's centre.

  IndyPagoda       Indianapolis: the ten-storey Pagoda, a glass tower under stacked white roofs on a
                   two-storey base (57.5 x 33.4 m footprint)
  ScoringPylon     Indianapolis: the timing and scoring pylon, 33 rows of car numbers on its faces
  FerrisWheel      Suzuka: the 50 m Ferris wheel in the park, the wheel in the X-Z plane
  TyreBridge       Le Mans: the tyre-shaped footbridge; the circuit runs through it along Y, the arch
                   (inner radius 11.5 m) spans X
  MonzaPodio       Monza: the podium over the pit straight, the platform at the origin, its
                   cantilever and support at +Y (the pit side)
  CastleKeep       a ruined round keep (Nurburg's Bergfried), 9.5 m across and 20 m tall
  CastleTower      a ruined round wall tower, 6 m across and 9 m tall
  CastleWall       1 m of ruined curtain wall along X (stretched by Godot between the towers)
  Casino           Monaco: the Casino de Monte-Carlo and its Opera (60 x 160 m), the front with the twin
                   towers on the short side to -Y
  SilverstoneWing  Silverstone: the Wing pit and paddock building under its wing roof (374 x 32.6 m)
  Barbakan         Kraków: the brick barbican on ul. Basztowa, a round bastion (24 m across, 10 m walls
                   with a crenellated top) carrying seven turrets with spires, and the neck that led
                   to the Floriańska gate along +X (38 x 31.5 m footprint with the neck)
  FloriaGate       Kraków: the Brama Floriańska, a stone gate tower (10 x 9.2 m, 26 m tall) with a pointed
                   helmet and four corner turrets, a pointed arch through the ground floor along Y
  PszczynaCastle   Pszczyna: the castle (58 x 45 m): a long front block to -Y with a clock tower, two
                   wings back to +Y round the court, hipped slate roofs, cream plaster
  WilamowiceChurch Wilamowice: the parish church of the Holy Trinity (49.6 x 23.2 m, from its OSM footprint): a
                   square west tower with a copper spire at -X, a gabled nave, a wide transept, low side
                   chapels and a lower chancel at +X
  Yacht_S/M/L      motor yachts of 14, 28 and 50 m for Monaco's harbour, bow to +X, waterline at z=0
"""
import bpy
import math
import os
import random
import sys
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit  # noqa: E402
from kit import MB, srgb  # noqa: E402

OUT_GLB = os.path.join(kit.ROOT, "godot", "models", "landmarks.glb")

kit.MATERIALS.update({
	"Concrete": (srgb("#c9c5bc"), 0.88, 0.0, {}),
	"White": (srgb("#f1f2f0"), 0.45, 0.0, {}),
	"Steel": (srgb("#a4aaaf"), 0.4, 0.7, {}),
	"SteelPaint": (srgb("#3a3f45"), 0.5, 0.35, {}),
	"Glass": (srgb("#2b3c48"), 0.05, 0.7, {}),
	"Stone": (srgb("#ffffff"), 0.92, 0.0, {}),
	"Copper": (srgb("#6f9c8a"), 0.55, 0.25, {}),
	"Slate": (srgb("#4e5559"), 0.7, 0.0, {}),
	"Rubber": (srgb("#1a1a1b"), 0.82, 0.0, {}),
	"Paint": (srgb("#ffffff"), 0.4, 0.0, {}),
	"Panel": (srgb("#141618"), 0.35, 0.2, {}),
	"Digit": (srgb("#ffffff"), 0.5, 0.0, {"emit": ((1.0, 0.95, 0.85), 1.2)}),
	"Gold": (srgb("#c9a050"), 0.35, 0.8, {}),
	"Teak": (srgb("#9a6f45"), 0.75, 0.0, {}),
	"ClearGlass": (srgb("#b9d0d8"), 0.08, 0.3, {"alpha": 0.4}),
	"Brick": (srgb("#ffffff"), 0.9, 0.0, {}),
	"Plaster": (srgb("#ffffff"), 0.9, 0.0, {}),
	"Roof": (srgb("#ffffff"), 0.75, 0.0, {}),
})


def rnd(seed):
	return random.Random(seed)


# --------------------------------------------------------------------------- Indianapolis

def mullions(mb, x0, x1, y0, y1, z0, z1, every, mat="White", w=0.18):
	"""White vertical bars round a glass box's walls."""
	for (ax, ay), (bx, by) in (((x0, y0), (x1, y0)), ((x1, y0), (x1, y1)), ((x1, y1), (x0, y1)), ((x0, y1), (x0, y0))):
		ln = math.hypot(bx - ax, by - ay)
		n = max(1, int(ln / every))
		for k in range(n + 1):
			t = k / n
			x, y = ax + (bx - ax) * t, ay + (by - ay) * t
			mb.box((x - w, y - w, z0), (x + w, y + w, z1), mat, skip=("-z", "+z"))


def indy_pagoda():
	"""Indianapolis Pagoda: a glass-banded tower on a wider two-storey base."""
	mb = MB()
	L, W = 57.5, 33.4
	# the base: two storeys, glass between white bands, wider than the tower
	mb.colour = srgb("#2b3c48")
	mb.box((-L / 2 + 1, -W / 2 + 1, 0), (L / 2 - 1, W / 2 - 1, 8.0), "Glass", skip=("-z",))
	mb.colour = (1, 1, 1)
	mullions(mb, -L / 2 + 1, L / 2 - 1, -W / 2 + 1, W / 2 - 1, 0, 8.0, 3.0)
	for z in (3.8, 7.6):
		mb.box((-L / 2, -W / 2, z), (L / 2, W / 2, z + 0.5), "White")
	# the tower: nine more storeys stepping in, each under a wide white roof whose edge turns up
	z = 8.1
	tw, td = 30.0, 19.0
	for k in range(9):
		h = 4.3
		w = tw - k * 0.9
		d = td - k * 0.55
		mb.colour = srgb("#2b3c48")
		mb.box((-w / 2, -d / 2, z), (w / 2, d / 2, z + h), "Glass", skip=("-z", "+z"))
		mb.colour = (1, 1, 1)
		mullions(mb, -w / 2, w / 2, -d / 2, d / 2, z, z + h, 2.4, w=0.12)
		# a balcony rail round the floor
		o = 1.4
		for (ax, ay), (bx, by) in (((-w / 2 - o, -d / 2 - o), (w / 2 + o, -d / 2 - o)),
				((w / 2 + o, -d / 2 - o), (w / 2 + o, d / 2 + o)), ((w / 2 + o, d / 2 + o), (-w / 2 - o, d / 2 + o)),
				((-w / 2 - o, d / 2 + o), (-w / 2 - o, -d / 2 - o))):
			mb.beam((ax, ay, z + 1.05), (bx, by, z + 1.05), 0.08, 0.08, "White")
		# the roof over it: a slab reaching 2.6 m out with a turned-up lip
		r = 2.6 + 0.15 * k
		zr = z + h
		mb.box((-w / 2 - r, -d / 2 - r, zr), (w / 2 + r, d / 2 + r, zr + 0.45), "White")
		lip = [(-w / 2 - r, -d / 2 - r), (w / 2 + r, -d / 2 - r), (w / 2 + r, d / 2 + r), (-w / 2 - r, d / 2 + r)]
		for i in range(4):
			a, b = lip[i], lip[(i + 1) % 4]
			ca = Vector((a[0] * 1.03, a[1] * 1.06, zr + 0.95))
			cb = Vector((b[0] * 1.03, b[1] * 1.06, zr + 0.95))
			mb.quad((a[0], a[1], zr + 0.45), (b[0], b[1], zr + 0.45), cb, ca, "White", lambda q: Vector((q.x, q.y, 0.3)))
			mb.quad(ca, cb, (b[0], b[1], zr + 0.45), (a[0], a[1], zr + 0.45), "White", lambda q: Vector((-q.x, -q.y, 0.3)))
		z = zr + 0.45
	# the top: a small glass cupola under a peaked white roof, and the flag mast
	mb.colour = srgb("#2b3c48")
	mb.box((-6, -4, z), (6, 4, z + 3.2), "Glass", skip=("-z", "+z"))
	mb.colour = (1, 1, 1)
	z += 3.2
	mb.poly([(-9, -6.5, z), (9, -6.5, z), (9, 6.5, z), (-9, 6.5, z)], "White", (0, 0, -1))
	for a, b in (((-9, -6.5), (9, -6.5)), ((9, -6.5), (9, 6.5)), ((9, 6.5), (-9, 6.5)), ((-9, 6.5), (-9, -6.5))):
		mb.poly([(a[0], a[1], z), (b[0], b[1], z), (0, 0, z + 3.5)], "White", lambda q: Vector((q.x, q.y, 1.0)))
	mb.colour = srgb("#a4aaaf")
	mb.tube((0, 0, z + 3.5), (0, 0, z + 12.0), 0.15, "Steel", segs=6)
	mb.colour = srgb("#3a3f45")
	# the stair core at the back and a skybridge stub to the press centre
	mb.box((-3, td / 2 - 1, 8.0), (3, td / 2 + 2.5, z - 3.2), "Concrete")
	return mb


def scoring_pylon():
	"""Indianapolis scoring pylon: a tall slim tower of position numbers."""
	mb = MB()
	W, D, H = 4.4, 2.0, 46.0
	mb.colour = srgb("#2a2d31")
	mb.box((-W / 2, -D / 2, 0), (W / 2, D / 2, H), "SteelPaint")
	mb.colour = srgb("#3a3f45")
	mb.box((-1.0, -0.6, -0.1), (1.0, 0.6, 0.01), "SteelPaint")
	# the head: lap counter and the IMS wing-and-wheel badge
	mb.colour = srgb("#2a2d31")
	mb.box((-W / 2 - 0.5, -D / 2 - 0.3, H), (W / 2 + 0.5, D / 2 + 0.3, H + 4.5), "SteelPaint")
	r = rnd(7)
	for side, n in ((-1, (0, -1, 0)), (1, (0, 1, 0))):
		y = side * (D / 2 + 0.02)
		yh = side * (D / 2 + 0.32)
		u = (1, 0, 0) if side < 0 else (-1, 0, 0)
		mb.colour = srgb("#141618")
		mb.quad((-W / 2, y, 1.5), (W / 2, y, 1.5), (W / 2, y, H - 0.5), (-W / 2, y, H - 0.5), "Panel", n)
		mb.colour = (1, 1, 1)
		kit.text_mesh(mb, "IMS", (0, yh + side * 0.01, H + 2.2), 1.6, "Digit", axis_u=u, axis_v=(0, 0, 1))
		kit.text_mesh(mb, "LAP 200", (0, yh + side * 0.01, H + 0.6), 0.8, "Digit", axis_u=u, axis_v=(0, 0, 1))
		# 33 rows: the position (white) and the car number (yellow)
		cars = r.sample(range(2, 99), 33)
		for i in range(33):
			zr = H - 1.6 - i * 1.3
			mb.colour = (1, 1, 1)
			kit.text_mesh(mb, str(i + 1), (-W / 2 + 0.9 if side < 0 else W / 2 - 0.9, y + side * 0.01, zr), 0.75, "Digit",
				axis_u=u, axis_v=(0, 0, 1))
			mb.colour = srgb("#ffd21a")
			kit.text_mesh(mb, str(cars[i]), (0.8 if side < 0 else -0.8, y + side * 0.01, zr), 0.9, "Digit",
				axis_u=u, axis_v=(0, 0, 1))
	return mb


# --------------------------------------------------------------------------- Suzuka

def ferris_wheel():
	"""Suzuka's Ferris wheel: rim, spokes and gondolas on an A-frame."""
	mb = MB()
	R, hub, gap = 24.0, 27.0, 1.6
	n = 48
	mb.colour = srgb("#e8e9e6")
	# two rims, braced together, with spokes to the hub
	for y in (-gap, gap):
		for k in range(n):
			a0, a1 = 2 * math.pi * k / n, 2 * math.pi * (k + 1) / n
			mb.tube((R * math.cos(a0), y, hub + R * math.sin(a0)), (R * math.cos(a1), y, hub + R * math.sin(a1)), 0.28, "White", segs=6, caps=False)
			r2 = R * 0.9
			mb.tube((r2 * math.cos(a0), y, hub + r2 * math.sin(a0)), (r2 * math.cos(a1), y, hub + r2 * math.sin(a1)), 0.16, "White", segs=5, caps=False)
		for k in range(0, n, 2):
			a = 2 * math.pi * k / n
			mb.tube((0, y * 0.4, hub), (R * math.cos(a), y, hub + R * math.sin(a)), 0.09, "White", segs=4, caps=False)
	for k in range(n):
		a = 2 * math.pi * k / n
		p = (R * math.cos(a), 0, hub + R * math.sin(a))
		mb.tube((p[0], -gap, p[2]), (p[0], gap, p[2]), 0.12, "White", segs=4, caps=False)
	mb.colour = srgb("#a4aaaf")
	mb.tube((0, -3.2, hub), (0, 3.2, hub), 1.0, "Steel", segs=12)
	# A-frame legs on both sides
	mb.colour = srgb("#e8e9e6")
	for y in (-1, 1):
		for x in (-1, 1):
			mb.tube((x * 15.0, y * 9.0, 0), (0, y * 3.0, hub), 0.6, "White", segs=8)
		mb.tube((-9.0, y * 6.0, hub * 0.4), (9.0, y * 6.0, hub * 0.4), 0.3, "White", segs=6)
	# gondolas in four colours, hanging under the rim
	cols = ["#e8483c", "#f2c230", "#3c8fd8", "#4bb06a"]
	for k in range(32):
		a = 2 * math.pi * k / 32
		cx, cz = R * math.cos(a) * 1.02, hub + R * math.sin(a) * 1.02 - 1.6
		mb.colour = srgb(cols[k % 4])
		mb.lathe([(-1.1, 0.0), (-1.0, 0.9), (0.0, 1.25), (0.8, 1.1), (1.1, 0.0)], 10, "Paint", centre=(cx, 0, cz + 0.2))
		mb.colour = srgb("#a4aaaf")
		mb.tube((cx, 0, cz + 1.3), (cx, 0, cz + 1.9), 0.08, "Steel", segs=4)
	# boarding station
	mb.colour = srgb("#d9d4c8")
	mb.box((-8, -6, 0), (8, 6, 2.6), "Concrete")
	mb.colour = srgb("#c8102e")
	mb.box((-8.5, -6.5, 2.6), (8.5, 6.5, 3.0), "Paint")
	return mb


# --------------------------------------------------------------------------- Le Mans

def tyre_section():
	"""The tyre's cross-section as (radial offset, across) points, outside first, closed."""
	pts = []
	# tread (outer, flat with rounded shoulders) -> sidewall -> bead (inner) -> other sidewall
	for t in range(9):
		a = -math.pi / 2 + math.pi * t / 8
		pts.append((2.0 + 0.35 * math.cos(a) - 0.35 + 0.0, 2.5 * math.sin(a) * 0.92))
	return pts


def tyre_bridge():
	"""Le Mans' Dunlop tyre-shaped footbridge arching over the track."""
	mb = MB()
	Rc = 13.5  # the middle of the tyre's section; inner edge at 11.5, outer at 15.5
	n = 64
	a0, a1 = math.radians(-8), math.radians(188)
	# the section: a rounded rectangle 4 m deep (radially) and 5 m wide, bulging a little at the sidewalls
	sec = []
	for k in range(24):
		t = 2 * math.pi * k / 24
		c, s = math.cos(t), math.sin(t)
		dr = 2.0 * math.copysign(abs(c) ** 0.45, c)
		dy = 2.5 * math.copysign(abs(s) ** 0.3, s)
		sec.append((dr, dy))
	rows = []
	for i in range(n + 1):
		a = a0 + (a1 - a0) * i / n
		radial = Vector((math.cos(a), 0, math.sin(a)))
		c = radial * Rc
		rows.append([c + radial * dr + Vector((0, dy, 0)) for dr, dy in sec])
	mb.colour = srgb("#1a1a1b")
	ids = [[mb.vert(p) for p in row] for row in rows]
	m = len(sec)
	for i in range(n):
		a = a0 + (a1 - a0) * (i + 0.5) / n
		cen = Vector((math.cos(a), 0, math.sin(a))) * Rc
		for j in range(m):
			j2 = (j + 1) % m
			mb.face([ids[i][j], ids[i][j2], ids[i + 1][j2], ids[i + 1][j]], "Rubber",
				lambda q, cen=cen, a=a: (q - cen) - Vector((-math.sin(a), 0, math.cos(a))) * (q - cen).dot(Vector((-math.sin(a), 0, math.cos(a)))))
	# tread blocks across the outer face
	for i in range(0, 2 * n):
		a = a0 + (a1 - a0) * (i + 0.5) / (2 * n)
		radial = Vector((math.cos(a), 0, math.sin(a)))
		tang = Vector((-math.sin(a), 0, math.cos(a)))
		for y0, y1 in ((-2.0, -0.3), (0.3, 2.0)):
			off = 0.4 if i % 2 else 0.0
			base = radial * (Rc + 1.98)
			lo, hi = y0 + off * 0.5, y1 + off * 0.5 - 0.2
			p = [base + tang * -0.35 + Vector((0, lo, 0)), base + tang * 0.35 + Vector((0, lo, 0)),
				base + tang * 0.35 + Vector((0, hi, 0)), base + tang * -0.35 + Vector((0, hi, 0))]
			top = [q + radial * 0.18 for q in p]
			mb.poly(top, "Rubber", radial)
			for k in range(4):
				mb.poly([p[k], p[(k + 1) % 4], top[(k + 1) % 4], top[k]], "Rubber", lambda q, c=base + radial * 0.09 + Vector((0, (lo + hi) / 2, 0)): q - c)
	# the lettering round the top of both sidewalls, white
	word = "24 HEURES DU MANS"
	step = math.radians(4.6)
	mid = math.pi / 2
	for side in (-1, 1):
		y = side * 2.62
		for i, ch in enumerate(word):
			if ch == " ":
				continue
			off = (i - (len(word) - 1) / 2) * step
			a = mid - off if side < 0 else mid + off
			radial = Vector((math.cos(a), 0, math.sin(a)))
			u = Vector((math.sin(a), 0, -math.cos(a))) * (1 if side < 0 else -1)
			mb.colour = (1, 1, 1)
			kit.text_mesh(mb, ch, radial * (Rc - 0.55) + Vector((0, y, 0)), 1.7, "Paint", axis_u=tuple(u), axis_v=tuple(radial))
	# the walkway inside the crown, its floor and a glazed slot along each side
	mb.colour = srgb("#3a3f45")
	mb.box((-6.0, -1.3, Rc - 2.1), (6.0, 1.3, Rc - 1.95), "SteelPaint")
	# stair towers down to the ground at both ends, outside the tyre
	for x in (-1, 1):
		cx = x * (Rc + 4.5)
		mb.colour = srgb("#c9c5bc")
		mb.box((cx - 1.6, -1.6, 0), (cx + 1.6, 1.6, Rc - 1.0), "Concrete", skip=("-z",))
		mb.colour = srgb("#3a3f45")
		mb.box((cx - 2.0, -2.0, Rc - 1.0), (cx + 2.0, 2.0, Rc - 0.6), "SteelPaint")
		mb.beam((cx - x * 1.6, 0, Rc - 1.6), (x * (Rc + 1.0), 0, Rc - 1.0), 2.2, 0.5, "SteelPaint")
	return mb


# --------------------------------------------------------------------------- Monza

def monza_podio():
	"""Monza's podium platform that overhangs the main straight."""
	mb = MB()
	Z = 8.5  # platform level over the track
	S = 10.8
	mb.colour = srgb("#e9eaea")
	# the platform, its underside dark
	mb.box((-S / 2, -S / 2, Z - 0.9), (S / 2, S / 2, Z), "White")
	# glass balustrade round the front and the sides, a steel rail on top
	mb.colour = srgb("#9fb6c0")
	for a, b, n in (((-S / 2, -S / 2), (S / 2, -S / 2), (0, -1, 0)), ((-S / 2, -S / 2), (-S / 2, S / 2), (-1, 0, 0)),
			((S / 2, -S / 2), (S / 2, S / 2), (1, 0, 0))):
		mb.quad((a[0], a[1], Z), (b[0], b[1], Z), (b[0], b[1], Z + 1.1), (a[0], a[1], Z + 1.1), "ClearGlass", n)
		mb.colour = srgb("#a4aaaf")
		mb.tube((a[0], a[1], Z + 1.12), (b[0], b[1], Z + 1.12), 0.05, "Steel", segs=5)
		mb.colour = srgb("#9fb6c0")
	# the steps: 2 - 1 - 3 from the left, seen from the track
	mb.colour = srgb("#c8102e")
	for x, h in ((-2.0, 0.6), (0.0, 0.9), (2.0, 0.4)):
		mb.box((x - 0.95, -1.0, Z), (x + 0.95, 0.6, Z + h), "Paint")
	# backdrop wall at the back of the platform, red with a white band
	mb.colour = srgb("#c8102e")
	mb.box((-S / 2, S / 2 - 0.4, Z), (S / 2, S / 2, Z + 4.2), "Paint")
	mb.colour = (1, 1, 1)
	mb.quad((-S / 2, S / 2 - 0.41, Z + 1.5), (S / 2, S / 2 - 0.41, Z + 1.5), (S / 2, S / 2 - 0.41, Z + 1.9), (-S / 2, S / 2 - 0.41, Z + 1.9), "White", (0, -1, 0))
	kit.text_mesh(mb, "MONZA", (0, S / 2 - 0.43, Z + 3.05), 1.1, "White", axis_u=(1, 0, 0), axis_v=(0, 0, 1))
	# the cantilever: two steel box girders reaching back over the pit lane to the support tower
	mb.colour = srgb("#3a3f45")
	back = 30.0
	for x in (-3.5, 3.5):
		mb.beam((x, -S / 2, Z - 0.5), (x, back, Z + 0.5), 0.8, 1.6, "SteelPaint")
		mb.beam((x, S / 2, Z + 0.4), (x, back - 3, Z + 6.0), 0.4, 0.4, "SteelPaint")
	mb.colour = srgb("#e9eaea")
	mb.box((-5.0, back - 4, 0), (5.0, back + 2, Z + 7.0), "White", skip=("-z",))
	mb.colour = srgb("#2b3c48")
	mb.quad((-5.01, back - 3, 2), (-5.01, back + 1, 2), (-5.01, back + 1, Z + 6), (-5.01, back - 3, Z + 6), "Glass", (-1, 0, 0))
	mb.quad((5.01, back - 3, 2), (5.01, back - 3, Z + 6), (5.01, back + 1, Z + 6), (5.01, back + 1, 2), "Glass", (1, 0, 0))
	return mb


# --------------------------------------------------------------------------- castles

STONE = ["#8d8577", "#9b927f", "#7f786c", "#a39a88", "#878074"]


def stone_shaded(mb, r, k):
	mb.colour = srgb(STONE[(k * 7 + r.randrange(5)) % 5])


def round_tower(r, radius, height, ragged, segs=16, windows=3):
	"""A ragged round stone tower (ruined castle), radius x height, with windows."""
	mb = MB()
	rows = 6
	for i in range(rows):
		z0, z1 = height * i / rows, height * (i + 1) / rows
		for k in range(segs):
			a0, a1 = 2 * math.pi * k / segs, 2 * math.pi * (k + 1) / segs
			top0 = z1 if i < rows - 1 else height - ragged * (0.5 + 0.5 * math.sin(k * 2.3 + 1.0))
			top1 = z1 if i < rows - 1 else height - ragged * (0.5 + 0.5 * math.sin((k + 1) * 2.3 + 1.0))
			if i == rows - 1 and k % 3 == 0:
				top0 += 1.0
				top1 += 1.0
			rb = radius * (1.06 if i == 0 else 1.0)
			p = [(rb * math.cos(a0), rb * math.sin(a0), z0), (rb * math.cos(a1), rb * math.sin(a1), z0),
				(radius * math.cos(a1), radius * math.sin(a1), top1), (radius * math.cos(a0), radius * math.sin(a0), top0)]
			stone_shaded(mb, r, i * segs + k)
			mb.poly(p, "Stone", lambda q: Vector((q.x, q.y, 0)))
			# the wall's thickness at the top
			if i == rows - 1:
				ri = radius - 1.6
				mb.poly([(radius * math.cos(a0), radius * math.sin(a0), top0), (radius * math.cos(a1), radius * math.sin(a1), top1),
					(ri * math.cos(a1), ri * math.sin(a1), top1), (ri * math.cos(a0), ri * math.sin(a0), top0)], "Stone", (0, 0, 1))
				mb.poly([(ri * math.cos(a0), ri * math.sin(a0), top0), (ri * math.cos(a1), ri * math.sin(a1), top1),
					(ri * math.cos(a1), ri * math.sin(a1), top0 - 3), (ri * math.cos(a0), ri * math.sin(a0), top0 - 3)], "Stone",
					lambda q: Vector((-q.x, -q.y, 0)))
	# slit windows
	mb.colour = srgb("#1d1b18")
	for w in range(windows):
		a = 2 * math.pi * (w + 0.3) / windows
		z = height * (0.35 + 0.18 * w)
		c = Vector((math.cos(a), math.sin(a), 0)) * (radius + 0.02)
		t = Vector((-math.sin(a), math.cos(a), 0))
		mb.poly([c + t * -0.25 + Vector((0, 0, z)), c + t * 0.25 + Vector((0, 0, z)), c + t * 0.25 + Vector((0, 0, z + 1.4)),
			c + t * -0.25 + Vector((0, 0, z + 1.4))], "Slate", Vector((math.cos(a), math.sin(a), 0)))
	return mb


def castle_keep():
	"""Nürburg castle's keep (Bergfried)."""
	return round_tower(rnd(11), 4.75, 20.0, 0.6, segs=20, windows=4)


def castle_tower():
	"""A smaller ruined tower of Nürburg castle."""
	return round_tower(rnd(12), 3.0, 9.0, 2.2, segs=14, windows=2)


def castle_wall():
	"""A stretch of ruined castle wall."""
	mb = MB()
	r = rnd(13)
	H, T = 7.0, 1.8
	n = 4
	for k in range(n):
		x0, x1 = -0.5 + k / n, -0.5 + (k + 1) / n
		h0 = H - 1.5 * (0.5 + 0.5 * math.sin(k * 2.1))
		h1 = H - 1.5 * (0.5 + 0.5 * math.sin((k + 1) * 2.1))
		stone_shaded(mb, r, k)
		mb.quad((x0, -T / 2, 0), (x1, -T / 2, 0), (x1, -T / 2, h1), (x0, -T / 2, h0), "Stone", (0, -1, 0))
		mb.quad((x1, T / 2, 0), (x0, T / 2, 0), (x0, T / 2, h0), (x1, T / 2, h1), "Stone", (0, 1, 0))
		mb.quad((x0, -T / 2, h0), (x1, -T / 2, h1), (x1, T / 2, h1), (x0, T / 2, h0), "Stone", (0, 0, 1))
	return mb


# --------------------------------------------------------------------------- Kraków

BRICK = ["#8e4632", "#9a5038", "#844030", "#a0563c", "#8a4a36"]


def barbakan():
	"""The Barbakan: a round brick bastion with a crenellated top, seven spired turrets and the neck to the gate."""
	mb = MB()
	r = rnd(21)
	cx, R, H, T = -3.5, 12.2, 10.0, 3.0  # body centre on X, outer radius, wall height, wall thickness
	segs = 40
	neck_half = math.asin(4.6 / R)  # the neck joins the body over this half angle round +X

	def ring_pt(a, rad, z):
		return (cx + rad * math.cos(a), rad * math.sin(a), z)
	for k in range(segs):
		a0, a1 = 2 * math.pi * k / segs, 2 * math.pi * (k + 1) / segs
		mb.colour = srgb(BRICK[(k * 3 + r.randrange(5)) % 5])
		# a slightly battered (sloping) foot, then the straight wall
		mb.poly([ring_pt(a0, R + 0.5, 0), ring_pt(a1, R + 0.5, 0), ring_pt(a1, R, 2.0), ring_pt(a0, R, 2.0)], "Brick",
			lambda q: Vector((q.x - cx, q.y, 0)))
		mb.poly([ring_pt(a0, R, 2.0), ring_pt(a1, R, 2.0), ring_pt(a1, R, H), ring_pt(a0, R, H)], "Brick",
			lambda q: Vector((q.x - cx, q.y, 0)))
		# the wall walk, the inner face and the courtyard floor
		mb.poly([ring_pt(a0, R, H), ring_pt(a1, R, H), ring_pt(a1, R - T, H), ring_pt(a0, R - T, H)], "Brick", (0, 0, 1))
		mb.poly([ring_pt(a0, R - T, H), ring_pt(a1, R - T, H), ring_pt(a1, R - T, 0.1), ring_pt(a0, R - T, 0.1)], "Brick",
			lambda q: Vector((cx - q.x, -q.y, 0)))
		mb.colour = srgb("#6d655a")
		mb.poly([(cx, 0, 0.1), ring_pt(a0, R - T, 0.1), ring_pt(a1, R - T, 0.1)], "Stone", (0, 0, 1))
		# merlons on alternate segments
		if k % 2 == 0:
			mb.colour = srgb(BRICK[(k + 2) % 5])
			mb.poly([ring_pt(a0, R, H), ring_pt(a1, R, H), ring_pt(a1, R, H + 1.3), ring_pt(a0, R, H + 1.3)], "Brick",
				lambda q: Vector((q.x - cx, q.y, 0)))
			mb.poly([ring_pt(a1, R - 0.7, H), ring_pt(a0, R - 0.7, H), ring_pt(a0, R - 0.7, H + 1.3), ring_pt(a1, R - 0.7, H + 1.3)],
				"Brick", lambda q: Vector((cx - q.x, -q.y, 0)))
			mb.poly([ring_pt(a0, R, H + 1.3), ring_pt(a1, R, H + 1.3), ring_pt(a1, R - 0.7, H + 1.3), ring_pt(a0, R - 0.7, H + 1.3)],
				"Brick", (0, 0, 1))
			for a, sgn in ((a0, -1), (a1, 1)):
				t = Vector((-math.sin(a), math.cos(a), 0)) * sgn
				mb.poly([ring_pt(a, R, H), ring_pt(a, R - 0.7, H), ring_pt(a, R - 0.7, H + 1.3), ring_pt(a, R, H + 1.3)], "Brick", t)
		# two rows of loopholes
		mb.colour = srgb("#1d1b18")
		am = (a0 + a1) * 0.5
		if abs(math.atan2(math.sin(am), math.cos(am))) > neck_half + 0.1:
			n = Vector((math.cos(am), math.sin(am), 0))
			tn = Vector((-math.sin(am), math.cos(am), 0))
			for z in (3.4, 6.6) if k % 2 else (5.0,):
				c = Vector(ring_pt(am, R + 0.03, z))
				mb.poly([c - tn * 0.18, c + tn * 0.18, c + tn * 0.18 + Vector((0, 0, 0.9)), c - tn * 0.18 + Vector((0, 0, 0.9))], "Slate", n)
	# seven turrets on the wall, none over the neck
	for i in range(7):
		a = neck_half + 0.35 + (2 * math.pi - 2 * neck_half - 0.7) * i / 6
		tx, ty = cx + (R - 0.6) * math.cos(a), (R - 0.6) * math.sin(a)
		mb.colour = srgb(BRICK[i % 5])
		tr, z0, z1 = 1.5, H - 0.5, H + 4.2
		mb.tube(Vector((tx, ty, z0)), Vector((tx, ty, z1)), tr, "Brick", segs=10)
		# a band of dark windows, then the spire
		mb.colour = srgb("#1d1b18")
		mb.tube(Vector((tx, ty, z1 - 1.6)), Vector((tx, ty, z1 - 0.9)), tr + 0.02, "Slate", segs=10, caps=False)
		mb.colour = srgb("#3d4a44")
		ring = [(tx + (tr + 0.25) * math.cos(2 * math.pi * j / 10), ty + (tr + 0.25) * math.sin(2 * math.pi * j / 10), z1) for j in range(10)]
		tip = (tx, ty, z1 + 4.6)
		for j in range(10):
			mb.poly([ring[j], ring[(j + 1) % 10], tip], "Copper", lambda q, tx=tx, ty=ty: Vector((q.x - tx, q.y - ty, 0.4)))
		mb.colour = srgb("#c9a050")
		mb.tube(Vector(tip), Vector((tx, ty, tip[2] + 0.9)), 0.06, "Gold", segs=4)
	# the neck: two walls to +X with a gateway at the end
	mb.colour = srgb(BRICK[1])
	x0, x1, w, nh = cx + R - 1.2, 19.0, 4.6, 8.0
	mb.box((x0, -w, 0), (x1, -w + 1.4, nh), "Brick")
	mb.box((x0, w - 1.4, 0), (x1, w, nh), "Brick")
	mb.box((x1 - 1.6, -w, 4.6), (x1, w, nh), "Brick")
	mb.colour = srgb("#1d1b18")
	mb.quad((x1 + 0.02, -1.8, 0), (x1 + 0.02, 1.8, 0), (x1 + 0.02, 1.8, 4.6), (x1 + 0.02, -1.8, 4.6), "Slate", (1, 0, 0))
	# the gateway into the bastion facing away from the neck (the barbican's own gate)
	mb.colour = srgb("#1d1b18")
	gx = cx - R - 0.02
	mb.quad((gx, 1.6, 0), (gx, -1.6, 0), (gx, -1.6, 4.2), (gx, 1.6, 4.2), "Slate", (-1, 0, 0))
	return mb


def hip_block(mb, x0, x1, y0, y1, z0, z1, rise, wall, roof, wall_mat="Plaster", windows_every=3.4, win_rows=(1.4,), win_h=1.7):
	"""A plastered box from z0 to z1 under a hipped roof `rise` high, with a row of windows on every side."""
	mb.colour = srgb(wall)
	mb.box((x0, y0, z0), (x1, y1, z1), wall_mat, skip=("+z",))
	mb.colour = srgb("#2a2f36")
	for row in win_rows:
		z = z0 + row
		n = max(1, int((x1 - x0) / windows_every))
		for k in range(n):
			x = x0 + (k + 0.5) * (x1 - x0) / n
			for y, nrm in ((y0 - 0.02, (0, -1, 0)), (y1 + 0.02, (0, 1, 0))):
				mb.quad((x - 0.55, y, z), (x + 0.55, y, z), (x + 0.55, y, z + win_h), (x - 0.55, y, z + win_h), "Slate", nrm)
		m = max(1, int((y1 - y0) / windows_every))
		for k in range(m):
			y = y0 + (k + 0.5) * (y1 - y0) / m
			for x, nrm in ((x0 - 0.02, (-1, 0, 0)), (x1 + 0.02, (1, 0, 0))):
				mb.quad((x, y - 0.55, z), (x, y + 0.55, z), (x, y + 0.55, z + win_h), (x, y - 0.55, z + win_h), "Slate", nrm)
	mb.colour = srgb(roof)
	o = 0.5  # eaves overhang
	a, b, c, d = (x0 - o, y0 - o, z1), (x1 + o, y0 - o, z1), (x1 + o, y1 + o, z1), (x0 - o, y1 + o, z1)
	hw = min((x1 - x0), (y1 - y0)) / 2
	if (x1 - x0) >= (y1 - y0):
		r1, r2 = (x0 + hw, (y0 + y1) / 2, z1 + rise), (x1 - hw, (y0 + y1) / 2, z1 + rise)
	else:
		r1, r2 = ((x0 + x1) / 2, y0 + hw, z1 + rise), ((x0 + x1) / 2, y1 - hw, z1 + rise)
	for q, ctr in (((a, b, r2, r1), (0, -1, 1)), ((b, c, r2), (1, 0, 1)), ((c, d, r1, r2), (0, 1, 1)), ((d, a, r1), (-1, 0, 1))):
		mb.poly(list(q), "Roof", Vector(ctr))
	# soffit
	mb.poly([a, d, c, b], "Roof", (0, 0, -1))


def pointed_arch(mb, x, y, nrm, half_w, h, mat="Slate"):
	"""A dark pointed arch opening in a wall facing nrm (a unit (x, y) vector), standing at (x, y) on the ground."""
	n3 = Vector((nrm[0], nrm[1], 0))
	t = Vector((-nrm[1], nrm[0], 0))
	c = Vector((x, y, 0)) + n3 * 0.03
	spring = h * 0.6
	steps = 6
	left = [c - t * half_w * math.cos(math.pi / 2 * k / steps) + Vector((0, 0, spring + (h - spring) * math.sin(math.pi / 2 * k / steps)))
		for k in range(steps + 1)]
	right = [c + t * half_w * math.cos(math.pi / 2 * k / steps) + Vector((0, 0, spring + (h - spring) * math.sin(math.pi / 2 * k / steps)))
		for k in range(steps + 1)]
	mb.poly([c - t * half_w, c + t * half_w] + right[:-1] + [left[-1]] + list(reversed(left[:-1])), mat, n3)


def floria_gate():
	"""The Brama Floriańska: a stone tower, an arch through it, four turrets and a copper helmet."""
	mb = MB()
	H, w, d = 21.0, 5.0, 4.6
	mb.colour = srgb("#bfb7a4")
	mb.box((-w, -d, 0), (w, d, H), "Plaster")
	# a lighter plinth, a dark band under the roof, and stone window slits
	mb.colour = srgb("#9c9482")
	mb.box((-w - 0.15, -d - 0.15, 0), (w + 0.15, d + 0.15, 2.0), "Plaster")
	mb.colour = srgb("#8b8576")
	mb.box((-w - 0.3, -d - 0.3, H - 1.2), (w + 0.3, d + 0.3, H), "Plaster")
	mb.colour = srgb("#1d1b18")
	for z in (9.0, 14.0):
		for x in (-2.0, 2.0):
			for y, nrm in ((-d - 0.03, (0, -1, 0)), (d + 0.03, (0, 1, 0))):
				mb.quad((x - 0.35, y, z), (x + 0.35, y, z), (x + 0.35, y, z + 1.8), (x - 0.35, y, z + 1.8), "Slate", nrm)
	mb.colour = srgb("#1d1b18")
	pointed_arch(mb, 0, -d, (0, -1), 2.2, 5.2)
	pointed_arch(mb, 0, d, (0, 1), 2.2, 5.2)
	# machicolation balcony round the top, with four small corner turrets
	mb.colour = srgb("#a39c88")
	for sx in (-1, 1):
		for sy in (-1, 1):
			tx, ty = sx * (w - 0.2), sy * (d - 0.2)
			mb.tube(Vector((tx, ty, H - 0.5)), Vector((tx, ty, H + 3.2)), 0.95, "Plaster", segs=8)
			mb.colour = srgb("#3d6e5c")
			ring = [(tx + 1.15 * math.cos(2 * math.pi * j / 8), ty + 1.15 * math.sin(2 * math.pi * j / 8), H + 3.2) for j in range(8)]
			for j in range(8):
				mb.poly([ring[j], ring[(j + 1) % 8], (tx, ty, H + 6.2)], "Copper", lambda q, tx=tx, ty=ty: Vector((q.x - tx, q.y - ty, 0.4)))
			mb.colour = srgb("#a39c88")
	# the central helmet: a copper octagon with a lantern and a spire
	mb.colour = srgb("#3d6e5c")
	base = [(3.4 * math.cos(2 * math.pi * j / 8 + math.pi / 8), 3.0 * math.sin(2 * math.pi * j / 8 + math.pi / 8), H) for j in range(8)]
	mid = [(2.0 * math.cos(2 * math.pi * j / 8 + math.pi / 8), 1.8 * math.sin(2 * math.pi * j / 8 + math.pi / 8), H + 3.0) for j in range(8)]
	top = [(0.9 * math.cos(2 * math.pi * j / 8 + math.pi / 8), 0.9 * math.sin(2 * math.pi * j / 8 + math.pi / 8), H + 5.4) for j in range(8)]
	for j in range(8):
		k = (j + 1) % 8
		mb.poly([base[j], base[k], mid[k], mid[j]], "Copper", lambda q: Vector((q.x, q.y, 0.5)))
		mb.poly([mid[j], mid[k], top[k], top[j]], "Copper", lambda q: Vector((q.x, q.y, 0.5)))
		mb.poly([top[j], top[k], (0, 0, H + 8.4)], "Copper", lambda q: Vector((q.x, q.y, 0.5)))
	mb.colour = srgb("#c9a050")
	mb.tube(Vector((0, 0, H + 8.4)), Vector((0, 0, H + 10.2)), 0.07, "Gold", segs=4)
	return mb


def pszczyna_castle():
	"""Pszczyna castle: a long front block, a clock tower, two back wings round the court, slate hipped roofs."""
	mb = MB()
	cream, slate = "#e3d9bf", "#4a4f55"
	# front block along X to -Y; wings along Y at both ends
	hip_block(mb, -29.0, 29.0, -22.6, -9.0, 0, 9.0, 4.6, cream, slate, win_rows=(1.4, 5.2))
	for sx in (-1, 1):
		x0, x1 = (-29.0, -16.0) if sx < 0 else (16.0, 29.0)
		hip_block(mb, x0, x1, -9.0, 22.6, 0, 8.0, 4.0, cream, slate, win_rows=(1.4, 4.8))
	# the clock tower on the front: a square shaft, a clock face and a copper onion
	mb.colour = srgb(cream)
	mb.box((-4.2, -25.6, 0), (4.2, -17.4, 17.0), "Plaster")
	mb.colour = srgb("#e8e2cf")
	mb.box((-4.6, -25.9, 12.0), (4.6, -17.1, 12.6), "Plaster")
	mb.colour = srgb("#f1efe6")
	c = Vector((0, -25.65, 14.8))
	ring = [c + Vector((1.6 * math.cos(2 * math.pi * j / 16), 0, 1.6 * math.sin(2 * math.pi * j / 16))) for j in range(16)]
	mb.poly(ring, "White", (0, -1, 0))
	mb.colour = srgb("#26282c")
	mb.quad((-0.07, -25.67, 14.8), (0.07, -25.67, 14.8), (0.07, -25.67, 16.1), (-0.07, -25.67, 16.1), "Slate", (0, -1, 0))
	mb.quad((0.0, -25.67, 14.73), (1.0, -25.67, 14.73), (1.0, -25.67, 14.87), (0.0, -25.67, 14.87), "Slate", (0, -1, 0))
	mb.colour = srgb("#3d6e5c")
	prof = [(4.6, 17.0), (4.9, 17.9), (3.6, 19.8), (1.9, 21.2), (2.3, 22.4), (0.5, 24.5), (0.0, 27.5)]
	for j in range(12):
		a0, a1 = 2 * math.pi * j / 12, 2 * math.pi * (j + 1) / 12
		for (r0, z0), (r1, z1) in zip(prof, prof[1:]):
			p = [(r0 * math.cos(a0), -21.5 + r0 * math.sin(a0), z0), (r0 * math.cos(a1), -21.5 + r0 * math.sin(a1), z0),
				(r1 * math.cos(a1), -21.5 + r1 * math.sin(a1), z1), (r1 * math.cos(a0), -21.5 + r1 * math.sin(a0), z1)]
			mb.poly(p, "Copper", lambda q: Vector((q.x, q.y + 21.5, 0.3)))
	# the entrance: a dark portal at the foot of the tower
	pointed_arch(mb, 0, -25.62, (0, -1), 1.7, 4.4)
	return mb


def gable_y(mb, x0, x1, y0, y1, z, rise, roof, o=0.5):
	"""A gabled roof over x0..x1 x y0..y1 whose ridge runs along Y (the cross arm of a church)."""
	mb.colour = srgb(roof)
	xm = (x0 + x1) / 2
	a, b, c, d = (x0 - o, y0 - o, z), (x1 + o, y0 - o, z), (x1 + o, y1 + o, z), (x0 - o, y1 + o, z)
	r0, r1 = (xm, y0 - o, z + rise), (xm, y1 + o, z + rise)
	mb.poly([a, d, r1, r0], "Roof", Vector((-1, 0, 1)))
	mb.poly([b, r0, r1, c], "Roof", Vector((1, 0, 1)))
	mb.poly([a, r0, b], "Roof", (0, -1, 0))
	mb.poly([d, c, r1], "Roof", (0, 1, 0))
	mb.poly([a, d, c, b], "Roof", (0, 0, -1))


def wilamowice_church():
	"""The parish church of the Holy Trinity: tower at -X, nave, transept, side chapels, chancel at +X."""
	mb = MB()
	wall, roof, trim = "#e4d8bd", "#6a3b30", "#f1eadb"
	# the nave: plastered walls under a steep gable running along X
	mb.colour = srgb(wall)
	mb.box((-17.5, -7.2, 0), (13.5, 7.2, 9.5), "Plaster", skip=("+z",))
	mb.colour = srgb(roof)
	mb.prism([(-7.9, 9.4), (7.9, 9.4), (0.0, 16.2)], -18.0, 14.0, "Roof")
	# the transept: a wide cross arm across the nave, ridge along Y
	mb.colour = srgb(wall)
	mb.box((6.0, -11.4, 0), (17.0, 11.4, 9.5), "Plaster", skip=("+z",))
	gable_y(mb, 6.0, 17.0, -11.4, 11.4, 9.5, 6.0, roof)
	# low side chapels either side of the nave, west of the transept
	hip_block(mb, -19.0, -9.0, -9.7, 9.7, 0, 5.8, 2.4, wall, roof, win_rows=(1.6,), win_h=2.2)
	# the chancel: narrower and lower, closing the east end
	hip_block(mb, 16.0, 24.8, -4.7, 4.7, 0, 7.4, 3.2, wall, roof, win_rows=(1.8,), win_h=3.0)
	# the west tower: square shaft, belfry with louvres, clock faces and a tall copper spire
	mb.colour = srgb(wall)
	mb.box((-24.8, -4.2, 0), (-16.8, 4.2, 26.0), "Plaster")
	mb.colour = srgb("#cfc4a8")
	mb.box((-25.0, -4.4, 0), (-16.6, 4.4, 1.6), "Plaster")
	mb.colour = srgb(trim)
	mb.box((-25.0, -4.4, 24.0), (-16.6, 4.4, 24.5), "Plaster")
	mb.colour = srgb("#2a2f36")
	for (x, y, nrm) in ((-24.82, 0.0, (-1, 0, 0)), (-16.78, 0.0, (1, 0, 0))):
		mb.quad((x, y - 0.9, 18.5), (x, y + 0.9, 18.5), (x, y + 0.9, 22.5), (x, y - 0.9, 22.5), "Glass", nrm)
	for (y, nrm) in ((-4.22, (0, -1, 0)), (4.22, (0, 1, 0))):
		mb.quad((-21.8, y, 18.5), (-19.8, y, 18.5), (-19.8, y, 22.5), (-21.8, y, 22.5), "Glass", nrm)
	mb.colour = srgb("#f1efe6")
	for sgn in (-1, 1):
		c = Vector((-24.83 if sgn < 0 else -16.77, 0.0, 14.0))
		ring = [c + Vector((0, 1.3 * math.cos(2 * math.pi * j / 14), 1.3 * math.sin(2 * math.pi * j / 14))) for j in range(14)]
		mb.poly(ring if sgn < 0 else list(reversed(ring)), "White", (sgn, 0, 0))
	# the west portal
	pointed_arch(mb, -24.82, 0.0, (-1, 0), 1.3, 4.0)
	mb.colour = srgb("#3d6e5c")
	mb.lathe([(26.0, 5.6), (26.6, 5.7), (29.0, 4.4), (33.0, 3.0), (33.6, 3.2), (36.0, 2.4), (40.0, 0.9), (46.0, 0.0)], 8, "Copper", centre=(-20.8, 0.0, 0.0))
	mb.tube(Vector((-20.8, 0, 46.0)), Vector((-20.8, 0, 48.4)), 0.07, "Gold", segs=4)
	# tall arched windows along the nave, the chapels and the transept ends
	mb.colour = srgb("#2c3a42")
	for k in range(5):
		x = -13.0 + k * 5.2
		for y, nrm in ((-7.22, (0, -1, 0)), (7.22, (0, 1, 0))):
			if 3.5 < x < 9.0:  # (the transept stands there)
				continue
			mb.quad((x - 0.8, y, 2.6), (x + 0.8, y, 2.6), (x + 0.8, y, 7.4), (x - 0.8, y, 7.4), "Glass", nrm)
	for y, nrm in ((-11.42, (0, -1, 0)), (11.42, (0, 1, 0))):
		for x in (8.8, 14.2):
			mb.quad((x - 0.8, y, 2.6), (x + 0.8, y, 2.6), (x + 0.8, y, 7.4), (x - 0.8, y, 7.4), "Glass", nrm)
		mb.quad((10.7, y, 7.2), (12.3, y, 7.2), (12.3, y, 8.4), (10.7, y, 8.4), "Glass", nrm)
	return mb


# --------------------------------------------------------------------------- Monaco

def casino():
	"""The Casino's front (the twin towers, the clock and the entrance) on the short side at -Y, facing the
	Place du Casino; the gaming rooms behind it and the Opera (Salle Garnier) at the far end, over the sea."""
	mb = MB()
	L, D = 60.0, 160.0
	stone = "#e7d8b9"
	trim = "#f3ead8"
	fy = -D / 2
	x0, x1 = -L / 2 + 2, L / 2 - 2

	def block(ya, yb, h, roof_h, xa=x0, xb=x1):
		mb.colour = srgb(stone)
		mb.box((xa, ya, 0), (xb, yb, h), "Stone", skip=("-z",))
		mb.colour = srgb(trim)
		mb.box((xa - 0.5, ya - 0.5, h - 0.8), (xb + 0.5, yb + 0.5, h + 0.4), "Stone")
		mb.colour = srgb("#6f9c8a")
		ins = 3.0
		top = [(xa + ins, ya + ins, h + 0.4 + roof_h), (xb - ins, ya + ins, h + 0.4 + roof_h), (xb - ins, yb - ins, h + 0.4 + roof_h),
			(xa + ins, yb - ins, h + 0.4 + roof_h)]
		base = [(xa, ya, h + 0.4), (xb, ya, h + 0.4), (xb, yb, h + 0.4), (xa, yb, h + 0.4)]
		cx, cy = (xa + xb) / 2, (ya + yb) / 2
		for i in range(4):
			mb.quad(base[i], base[(i + 1) % 4], top[(i + 1) % 4], top[i], "Copper", lambda q: Vector((q.x - cx, q.y - cy, 4.0)))
		mb.poly(top, "Copper", (0, 0, 1))

	def windows(xa, xb, y, n, rows, face):
		mb.colour = srgb("#2c3a42")
		for k in range(n):
			x = xa + (k + 0.5) * (xb - xa) / n
			for z0, z1 in rows:
				arch = [(x - 1.1, y, z0), (x + 1.1, y, z0), (x + 1.1, y, z1 - 1.1)]
				for j in range(7):
					a = math.pi * j / 6
					arch.append((x + 1.1 * math.cos(a), y, z1 - 1.1 + 1.1 * math.sin(a)))
				arch.append((x - 1.1, y, z1 - 1.1))
				mb.poly(arch if face < 0 else list(reversed(arch)), "Glass", (0, face, 0))

	def side_windows(x, ya, yb, n, rows, face):
		mb.colour = srgb("#2c3a42")
		for k in range(n):
			y = ya + (k + 0.5) * (yb - ya) / n
			for z0, z1 in rows:
				mb.poly([(x, y - 1.1, z0), (x, y + 1.1, z0), (x, y + 1.1, z1), (x, y - 1.1, z1)], "Glass", (face, 0, 0))

	rows = ((2.0, 7.0), (9.5, 14.5))
	# the front block and the gaming rooms behind it, two tall storeys under copper mansards
	block(fy + 3, fy + 45, 17.0, 5.0)
	block(fy + 45, fy + 110, 15.0, 4.0, x0 + 3, x1 - 3)
	# the Opera at the far end, its own front with two small towers looking out to sea
	block(fy + 110, D / 2, 19.0, 4.5)
	for sx in (-1, 1):
		cx = sx * (L / 2 - 7)
		mb.colour = srgb(stone)
		mb.box((cx - 4, D / 2 - 8, 0), (cx + 4, D / 2, 25.0), "Stone", skip=("-z",))
		mb.colour = srgb("#6f9c8a")
		mb.lathe([(25.0, 4.4), (27.0, 3.8), (29.0, 2.0), (30.0, 0.0)], 4, "Copper", centre=(cx, D / 2 - 4, 0))
	windows(x0 + 12, x1 - 12, fy + 2.95, 3, rows, -1)
	for sx in (-1, 1):
		side_windows(sx * (x1 + 0.02), fy + 16, fy + 44, 7, rows, sx)
		side_windows(sx * (x1 - 3 + 0.02), fy + 46, fy + 109, 14, ((2.0, 6.5), (8.5, 13.0)), sx)
		side_windows(sx * (x1 + 0.02), fy + 112, D / 2 - 10, 8, ((3.0, 8.0), (10.5, 16.0)), sx)
	windows(x0 + 10, x1 - 10, D / 2 + 0.02, 6, ((3.0, 8.0), (10.5, 16.0)), 1)
	# the central dome over the atrium
	mb.colour = srgb("#6f9c8a")
	mb.lathe([(21.0, 8.0), (24.0, 7.6), (27.0, 5.6), (29.0, 3.0), (30.0, 0.5), (30.2, 0.0)], 20, "Copper", centre=(0, fy + 30, 0))
	# the two towers at the front corners, with their copper caps and gilded finials
	for sx in (-1, 1):
		cx = sx * (L / 2 - 6)
		cy = fy + 6
		mb.colour = srgb(stone)
		mb.box((cx - 6, cy - 6, 0), (cx + 6, cy + 6, 26.0), "Stone", skip=("-z",))
		mb.colour = srgb(trim)
		mb.box((cx - 6.5, cy - 6.5, 25.5), (cx + 6.5, cy + 6.5, 26.6), "Stone")
		mb.box((cx - 6.3, cy - 6.3, 16.3), (cx + 6.3, cy + 6.3, 17.2), "Stone")
		mb.colour = srgb("#2c3a42")
		for z in (3.0, 10.0, 19.0):
			mb.quad((cx - 1.6, cy - 6.02, z), (cx + 1.6, cy - 6.02, z), (cx + 1.6, cy - 6.02, z + 4), (cx - 1.6, cy - 6.02, z + 4), "Glass", (0, -1, 0))
			fx = cx + sx * 6.02
			mb.quad((fx, cy - 1.6, z), (fx, cy + 1.6, z), (fx, cy + 1.6, z + 4), (fx, cy - 1.6, z + 4), "Glass", (sx, 0, 0))
		mb.colour = srgb("#6f9c8a")
		mb.lathe([(26.6, 6.2), (29.0, 6.0), (31.0, 5.0), (33.0, 3.2), (34.5, 1.2), (35.0, 0.0)], 4, "Copper", centre=(cx, cy, 0))
		mb.colour = srgb("#c9a050")
		mb.tube((cx, cy, 35.0), (cx, cy, 38.0), 0.25, "Gold", segs=6)
		mb.lathe([(37.0, 0.0), (37.4, 0.6), (38.0, 0.0)], 8, "Gold", centre=(cx, cy, 0))
	# the central entrance pavilion with its clock and the big arched window
	mb.colour = srgb(trim)
	mb.box((-8, fy + 1.0, 0), (8, fy + 3.2, 21.0), "Stone", skip=("-z",))
	mb.colour = srgb("#6f9c8a")
	mb.prism([(fy + 1.0, 21.0), (fy + 3.2, 21.0), (fy + 3.2, 23.5)], -8.5, 8.5, "Copper")
	mb.colour = srgb("#2c3a42")
	arch = [(-4.5, fy + 0.95, 6.0), (4.5, fy + 0.95, 6.0), (4.5, fy + 0.95, 13.0)]
	for j in range(9):
		a = math.pi * j / 8
		arch.append((4.5 * math.cos(a), fy + 0.95, 13.0 + 4.5 * math.sin(a)))
	arch.append((-4.5, fy + 0.95, 13.0))
	mb.poly(arch, "Glass", (0, -1, 0))
	mb.colour = srgb("#c9a050")
	mb.disc((0, fy + 0.9, 18.6), 1.3, "Gold", normal=(0, -1, 0), segs=16)
	# glass canopy (marquise) over the doors
	mb.box((-6, fy - 3.5, 4.8), (6, fy + 1.0, 5.2), "Gold")
	return mb


def yacht(L):
	"""A motor yacht L metres long for Monaco harbour."""
	mb = MB()
	B = L * 0.2  # beam
	F = 0.11 * L ** 0.75  # freeboard above the waterline
	n = 12
	# hull from stations: half-width and keel depth along the length, bow at +X
	def half(t):  # t: 0 stern -> 1 bow
		return B / 2 * (1.0 if t < 0.55 else max(0.0, math.cos((t - 0.55) / 0.45 * math.pi / 2)) ** 0.8)
	rows = []
	for i in range(n + 1):
		t = i / n
		x = -L / 2 + L * t
		hw = max(half(t), 0.05)
		deck = F + 0.25 * L ** 0.5 * max(0.0, t - 0.6)
		keel = -0.08 * L ** 0.8 * (1.0 - 0.6 * t)
		rows.append([(x, -hw, deck), (x, -hw * 0.95, 0.0), (x, -hw * 0.5, keel), (x, 0, keel - 0.1),
			(x, hw * 0.5, keel), (x, hw * 0.95, 0.0), (x, hw, deck)])
	mb.colour = srgb("#f6f5f1")
	ids = [[mb.vert(p) for p in row] for row in rows]
	for i in range(n):
		for j in range(6):
			mb.face([ids[i][j], ids[i][j + 1], ids[i + 1][j + 1], ids[i + 1][j]], "White",
				lambda q: Vector((0, q.y, q.z - F * 0.3)))
	# transom and deck
	mb.face(ids[0], "White", (-1, 0, 0))
	mb.colour = srgb("#9a6f45")
	deck_ids = [ids[i][0] for i in range(n + 1)] + [ids[i][6] for i in range(n, -1, -1)]
	mb.face(deck_ids, "Teak", (0, 0, 1))
	# the boot-top stripe and a dark window band on the hull
	mb.colour = srgb("#1f2a33")
	for side in (-1, 1):
		for i in range(2, n - 3):
			t0, t1 = i / n, (i + 1) / n
			x0, x1 = -L / 2 + L * t0, -L / 2 + L * t1
			h0, h1 = half(t0) * 1.005 + 0.02, half(t1) * 1.005 + 0.02
			mb.quad((x0, side * h0, F * 0.45), (x1, side * h1, F * 0.45), (x1, side * h1, F * 0.65), (x0, side * h0, F * 0.65),
				"Glass", (0, side, 0))
	# superstructure: decks stepping back, with dark glazing; more of them on a bigger boat
	tiers = 1 if L < 20 else (2 if L < 40 else 3)
	z = F + 0.25 * L ** 0.5 * 0.0
	for k in range(tiers):
		x0 = -L * (0.36 - 0.06 * k)
		x1 = L * (0.22 - 0.07 * k)
		hw = B / 2 * (0.82 - 0.1 * k)
		h = 2.3
		mb.colour = srgb("#f6f5f1")
		mb.box((x0, -hw, z), (x1, hw, z + h), "White", skip=("-z",))
		# a dark band of windows round it, the hardtop's overhang above
		mb.colour = srgb("#1f2a33")
		for side in (-1, 1):
			y = side * (hw + 0.02)
			pts = [(x0 + 0.5, y, z + 0.8), (x1 - 0.3, y, z + 0.8), (x1 - 0.3, y, z + 1.9), (x0 + 0.5, y, z + 1.9)]
			mb.poly(pts, "Glass", (0, side, 0))
		mb.quad((x1 + 0.02, -hw + 0.3, z + 0.8), (x1 + 0.02, hw - 0.3, z + 0.8), (x1 + 0.02, hw - 0.3, z + 1.9),
			(x1 + 0.02, -hw + 0.3, z + 1.9), "Glass", (1, 0, 0))
		mb.colour = srgb("#f6f5f1")
		mb.box((x0 - 0.8, -hw - 0.2, z + h), (x1 + 0.5, hw + 0.2, z + h + 0.25), "White")
		z += h + 0.25
	# mast with radar and antennae
	mb.colour = srgb("#f6f5f1")
	xm = -L * 0.05
	mb.box((xm - 0.3, -0.2, z), (xm + 0.3, 0.2, z + 0.4 * L ** 0.5), "White")
	mb.colour = srgb("#3a3f45")
	mb.box((xm - 0.9, -0.12, z + 0.4 * L ** 0.5), (xm + 0.9, 0.12, z + 0.4 * L ** 0.5 + 0.15), "SteelPaint")
	return mb


# --------------------------------------------------------------------------- Silverstone

def silverstone_wing():
	"""Silverstone's Wing pit and paddock building (374 m long)."""
	mb = MB()
	L, W = 374.0, 32.6
	front = -W / 2
	n = 34
	# ground floor: the pit garages, open towards the pit lane (-Y)
	mb.colour = srgb("#d9dbdc")
	mb.box((-L / 2, front + 1.5, 0), (L / 2, W / 2, 6.5), "Concrete", skip=("-z", "-y"))
	mb.colour = srgb("#2a2d31")
	for k in range(n * 2):
		x0 = -L / 2 + L * k / (n * 2) + 0.6
		x1 = -L / 2 + L * (k + 1) / (n * 2) - 0.6
		mb.quad((x0, front + 1.52, 0.0), (x1, front + 1.52, 0.0), (x1, front + 1.52, 5.2), (x0, front + 1.52, 5.2), "Panel", (0, -1, 0))
	mb.colour = srgb("#e9eaea")
	for k in range(n * 2 + 1):
		x = -L / 2 + L * k / (n * 2)
		mb.box((x - 0.6, front + 1.5, 0), (x + 0.6, front + 2.0, 6.5), "White", skip=("-z",))
	mb.box((-L / 2, front + 1.0, 5.2), (L / 2, front + 2.0, 6.5), "White")
	# the two hospitality floors above, glazed and leaning out towards the track
	mb.colour = srgb("#2b3c48")
	for x0, x1 in ((-L / 2, L / 2),):
		mb.quad((x0, front + 1.5, 6.5), (x1, front + 1.5, 6.5), (x1, front - 1.5, 15.0), (x0, front - 1.5, 15.0), "Glass", (0, -1, 0.3))
		mb.quad((x1, W / 2 - 2, 6.5), (x0, W / 2 - 2, 6.5), (x0, W / 2 - 2, 15.0), (x1, W / 2 - 2, 15.0), "Glass", (0, 1, 0))
	for x in (-L / 2, L / 2):
		sgn = 1 if x > 0 else -1
		mb.colour = srgb("#e9eaea")
		mb.poly([(x, front + 1.5, 6.5), (x, W / 2 - 2, 6.5), (x, W / 2 - 2, 15.0), (x, front - 1.5, 15.0)], "White", (sgn, 0, 0))
	mb.colour = srgb("#e9eaea")
	for k in range(n * 4 + 1):
		x = -L / 2 + L * k / (n * 4)
		mb.beam((x, front + 1.5, 6.5), (x, front - 1.5, 15.0), 0.25, 0.25, "White")
	mb.box((-L / 2, front - 1.2, 10.5), (L / 2, W / 2 - 2, 10.9), "White")
	mb.box((-L / 2, front + 1.5, 6.5), (L / 2, W / 2 - 2, 6.9), "White")
	# the wing roof: an aerofoil section along the whole building, its leading edge over the pit lane
	sec = [(-W / 2 - 9.0, 0.0), (-W / 2 - 7.5, 1.0), (-W / 2 - 4.0, 2.0), (-W / 2 + 4.0, 2.6), (0.0, 2.3), (W / 2 - 4, 1.2),
		(W / 2 + 2.0, 0.0), (W / 2 - 4, 0.45), (0.0, 0.9), (-W / 2 + 4.0, 0.9), (-W / 2 - 4.0, 0.5)]
	m = 40
	rows = []
	for i in range(m + 1):
		x = -L / 2 - 4 + (L + 8) * i / m
		u = 2 * x / (L + 8)
		z0 = 15.4 + 5.5 * (1 - u * u) ** 2  # rising towards the middle
		tilt = 0.06 * (1 - u * u)
		rows.append([(x, y, z0 + z - y * tilt) for y, z in sec])
	mb.colour = srgb("#9aa1a7")
	ids = [[mb.vert(p) for p in row] for row in rows]
	k = len(sec)
	for i in range(m):
		for j in range(k):
			j2 = (j + 1) % k
			mb.face([ids[i][j], ids[i][j2], ids[i + 1][j2], ids[i + 1][j]], "Steel", lambda q: Vector((0, 0, 1)) if j < 6 else Vector((0, 0, -1)))
	mb.face(ids[0], "Steel", (-1, 0, 0))
	mb.face(ids[-1], "Steel", (1, 0, 0))
	# the struts holding the wing over the glazed floors
	mb.colour = srgb("#e9eaea")
	for k2 in range(n + 1):
		x = -L / 2 + L * k2 / n
		u = 2 * x / (L + 8)
		z0 = 15.4 + 5.5 * (1 - u * u) ** 2
		mb.beam((x, front - 1.5, 15.0), (x, front - 4.0, z0 + 0.6), 0.5, 0.5, "White")
		mb.beam((x, W / 2 - 2, 15.0), (x, W / 2 - 5.0, z0 + 0.8), 0.5, 0.5, "White")
	# the race control and media bridge: a raised glass box over the middle
	mb.colour = srgb("#2b3c48")
	mb.box((-22, -W / 2 + 2, 15.0), (22, W / 2 - 6, 19.5), "Glass")
	return mb


PIECES = {
	"IndyPagoda": indy_pagoda, "ScoringPylon": scoring_pylon, "FerrisWheel": ferris_wheel,
	"TyreBridge": tyre_bridge, "MonzaPodio": monza_podio, "CastleKeep": castle_keep, "CastleTower": castle_tower,
	"CastleWall": castle_wall, "Casino": casino, "SilverstoneWing": silverstone_wing,
	"Barbakan": barbakan, "FloriaGate": floria_gate, "PszczynaCastle": pszczyna_castle, "WilamowiceChurch": wilamowice_church, "Yacht_S": lambda: yacht(14.0), "Yacht_M": lambda: yacht(28.0), "Yacht_L": lambda: yacht(50.0),
}


def main():
	"""Builds the landmarks (or only --only NAME) and exports them to models/landmarks.glb."""
	for ob in list(bpy.data.objects):
		bpy.data.objects.remove(ob)
	only = kit.arg("--only")
	objs = {}
	for name, fn in PIECES.items():
		mb = fn()
		print(f"{name}: {mb.tris()} tris")
		objs[name] = mb.emit(name)
	if not only:
		kit.export_glb(OUT_GLB, list(objs.values()))
	out = kit.arg("--renders")
	if out:
		cam = kit.setup_preview(ground=1200.0)
		views = {
			"IndyPagoda": ((90, -120, 40), (0, 0, 24), 45),
			"ScoringPylon": ((14, -30, 20), (0, 0, 26), 55),
			"FerrisWheel": ((50, -80, 25), (0, 0, 26), 50),
			"TyreBridge": ((18, -45, 6), (0, 0, 9), 50),
			"MonzaPodio": ((25, -30, 8), (0, 8, 7), 55),
			"CastleKeep": ((30, -45, 14), (5, 0, 9), 50),
			"Casino": ((70, -150, 40), (0, -30, 12), 50),
			"SilverstoneWing": ((90, -140, 45), (60, 0, 10), 55),
			"Yacht_L": ((50, -55, 18), (0, 0, 3), 50),
			"Barbakan": ((40, -55, 22), (0, 0, 7), 50),
			"FloriaGate": ((28, -55, 26), (0, 0, 15), 45),
			"PszczynaCastle": ((60, -95, 30), (0, -6, 8), 50),
			"WilamowiceChurch": ((-70, -95, 40), (-3, 0, 17), 50),
		}
		for ob in objs.values():
			ob.hide_render = True
		for name, (eye, target, fov) in views.items():
			if only and name not in only.split(","):
				continue
			v = kit.place(objs[name])
			if name == "CastleKeep":
				kit.place(objs["CastleTower"], (14, 8, 0))
				kit.place(objs["CastleWall"], (7, 4, 0), rot_z=math.atan2(8, 14), scale=(14.0, 1, 1))
			if name == "Yacht_L":
				kit.place(objs["Yacht_M"], (0, 22, 0))
				kit.place(objs["Yacht_S"], (-10, -20, 0))
			kit.render(cam, os.path.join(out, name + ".png"), eye, target, fov)
			for o in list(bpy.context.scene.objects):
				if o.name.endswith(".view"):
					bpy.data.objects.remove(o)


main()
