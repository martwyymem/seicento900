"""Builds the circuit's trackside structures as modular pieces: grandstands, the pit building, race control,
the start/finish gantry and TV camera towers.

Run from the repository root (Blender 4.2 or newer, headless):

    blender -b -P tools/blender/build_trackside.py -- [--renders DIR] [--blend FILE]

Writes godot/models/trackside.glb. race_world.gd lays the pieces out along each circuit, so every piece is
built in its own frame (below) and Godot repeats, stacks or stretches it. Keep the object names and the
layout constants (marked "Godot:") in step with race_world.gd.

Frames (Blender; glTF export turns +Y into Godot -Z):
  Grandstand pieces  X along the road, +Y away from it (up the tiers), Z up. Origin at the front edge of
                     the first tier, on the ground, in the middle of a 10 m bay.
  Pit pieces         X along the pit lane, +Y away from it (into the garages), Z up. Origin on the ground
                     at the garage front, in the middle of a 12 m bay (Godot stretches X to the box spacing).
  Gantry             X along the road (direction of travel), Y across it, Z up. Origin on the road centre.
  TV tower           origin at the camera platform floor, legs reaching 9 m down.

Objects:
  StandRow            one tier of a bay: riser, tread, aisle step and 18 seats (material Seat)
  StandCrowd          18 seated spectators for one tier (material Crowd; the vertex colour's red channel is the
                      body part, green the seat index, for the crowd shader)
  StandFrame_T<n>     the rest of a bay for n tiers (3-14): front wall, glass railing, concourse, back wall,
                      column, roof girder and roof
  StandEndL_T<n>, StandEndR_T<n>  side walls with stairs closing a run of bays (R also carries the last column)
  StandBoard_<k>      sponsor fascia boards, 10 m x 1.1 m, one per sponsor (material Ads)
  PitBay              one garage with its hospitality floor and roof terrace
  PitBayBand          the team-coloured band over that garage (material TeamBand, tinted per team)
  PitEndL, PitEndR    end walls of the pit building
  RaceControl         the race control tower at the pit exit end
  GantryLeg, GantryBeam (10 m long, stretched to the road width), GantryLights (housing for the 5 lights)
  TvTower             scaffold camera tower
"""
import bpy
import math
import os
import sys
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit  # noqa: E402
from kit import MB, srgb  # noqa: E402

OUT_GLB = os.path.join(kit.ROOT, "godot", "models", "trackside.glb")

# ---------------------------------------------------------------- layout (Godot: race_world.gd STAND_*)
BAY = 10.0
RISE = 0.40  # tier rise
TREAD = 0.85  # tier depth
FIRST_Z = 1.6  # top of the first tier above the ground
CONCOURSE = 1.6  # walkway behind the top tier
TIERS = range(3, 15)
SEATS = 18
SEAT_PITCH = 0.5
AISLE = 1.0  # aisle stairs at the bay's -X end
ROOF_BACK = 3.3  # roof height above the top tier at the back
ROOF_FRONT = 4.3  # ... and at its front edge
ROOF_OVERHANG = 1.6  # roof edge in front of the first tier
BOARD_H = 1.1

PIT_BAY = 12.0
PIT_DEPTH = 15.0
PIT_GF = 4.8  # ground floor (garages)
PIT_1F = 9.2  # roof terrace level
PIT_CANOPY = 12.2

MATERIALS = {
	"Concrete": (srgb("#bdb9b0"), 0.88, 0.0, {}),
	"ConcreteDark": (srgb("#8d8a84"), 0.9, 0.0, {}),
	"Steel": (srgb("#a4aaaf"), 0.42, 0.65, {}),
	"SteelPaint": (srgb("#3a3f45"), 0.5, 0.35, {}),
	"White": (srgb("#eceeef"), 0.55, 0.0, {}),
	"Cladding": (srgb("#c9ced2"), 0.55, 0.25, {}),
	"RoofTop": (srgb("#62686e"), 0.55, 0.35, {}),
	"RoofUnder": (srgb("#dcdedf"), 0.7, 0.0, {}),
	"Seat": (srgb("#ffffff"), 0.6, 0.0, {}),
	"Crowd": (srgb("#ffffff"), 0.85, 0.0, {}),
	"Glass": (srgb("#8fa7b3"), 0.05, 0.0, {"alpha": 0.22}),
	"GlassDark": (srgb("#27343d"), 0.06, 0.6, {}),
	"Ads": (srgb("#ffffff"), 0.5, 0.0, {"tex": "ads"}),
	"TeamBand": (srgb("#ffffff"), 0.45, 0.1, {}),
	"PitFloor": (srgb("#a3a8ab"), 0.3, 0.0, {}),
	"PitInterior": (srgb("#e4e6e8"), 0.65, 0.0, {}),
	"LightPanel": (srgb("#fbfaf5"), 0.3, 0.0, {"emit": ((1.0, 0.97, 0.9), 2.0)}),
	"Rubber": (srgb("#141414"), 0.85, 0.0, {}),
	"Red": (srgb("#b3121f"), 0.4, 0.2, {}),
	"Black": (srgb("#121315"), 0.6, 0.0, {}),
	"Sign": (srgb("#ffffff"), 0.4, 0.0, {"emit": ((1.0, 1.0, 1.0), 0.6)}),
}
kit.MATERIALS.update(MATERIALS)

# fictional sponsors: (background, text colour, text, accent stripe colour or None)
ADS = [
	("#c8102e", "#ffffff", "SEICENTO 900 CUP", "tricolore"),
	("#101114", "#ffd200", "OLIO VELOCE", "#ffd200"),
	("#16357a", "#ffffff", "GOMME TORINO", "#e2231a"),
	("#4a2c1d", "#f3e3c3", "CAFFÈ PISTA", "#c9a063"),
	("#ffd400", "#111111", "RADIO CIRCUITO 101.6", None),
	("#0b6b3a", "#ffffff", "BANCA AUTODROMO", "#ffffff"),
	("#f4f6f8", "#0d4fa3", "ACQUA FONTE ALPINA", "#3aa0e8"),
	("#ef6c00", "#ffffff", "CANDELE LAMPO", "#111111"),
]


def ad_uv(k, u, v):
	"""UV of point (u, v) in 0..1 on sponsor k's board in the atlas (8 rows, row 0 at the top)."""
	rows = len(ADS)
	v = 0.03 + 0.94 * v  # stay clear of the neighbouring rows when the texture is filtered
	return (u, 1.0 - (k + 1 - v) / rows)


# ---------------------------------------------------------------- sponsor atlas
def build_ads_atlas(path):
	"""Renders the sponsor boards into one 2048 x 2048 texture (8 rows of 8:1 boards)."""
	sc = bpy.data.scenes.new("Atlas")
	sc.render.resolution_x = 2048
	sc.render.resolution_y = 2048
	sc.view_settings.view_transform = "Standard"
	sc.render.film_transparent = False
	for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
		try:
			sc.render.engine = eng
			break
		except TypeError:
			continue
	world = bpy.data.worlds.new("AtlasWorld")
	world.use_nodes = True
	world.node_tree.nodes["Background"].inputs["Color"].default_value = (0, 0, 0, 1)
	sc.world = world

	def flat(name, hex_colour):
		m = bpy.data.materials.new(name)
		m.use_nodes = True
		nt = m.node_tree
		nt.nodes.clear()
		em = nt.nodes.new("ShaderNodeEmission")
		em.inputs["Color"].default_value = (*srgb(hex_colour), 1)
		out = nt.nodes.new("ShaderNodeOutputMaterial")
		nt.links.new(em.outputs[0], out.inputs[0])
		return m

	def rect(name, x0, y0, x1, y1, mat, z=0.0):
		me = bpy.data.meshes.new(name)
		me.from_pydata([(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)], [], [(0, 1, 2, 3)])
		me.materials.append(mat)
		ob = bpy.data.objects.new(name, me)
		sc.collection.objects.link(ob)

	rows = len(ADS)
	for k, (bg, fg, text, accent) in enumerate(ADS):
		y0 = rows - 1 - k  # row k at the top
		rect("bg%d" % k, 0, y0, 8, y0 + 1, flat("bg%d" % k, bg))
		if accent == "tricolore":
			for j, c in enumerate(("#009246", "#ffffff", "#ce2b37")):
				rect("tri%d_%d" % (k, j), 0.25 + j * 0.18, y0 + 0.2, 0.43 + j * 0.18, y0 + 0.8, flat("tri%d%d" % (k, j), c), 0.001)
				rect("trr%d_%d" % (k, j), 7.21 + j * 0.18, y0 + 0.2, 7.39 + j * 0.18, y0 + 0.8, flat("trr%d%d" % (k, j), c), 0.001)
		elif accent:
			rect("acc%d" % k, 0, y0 + 0.06, 8, y0 + 0.13, flat("acc%d" % k, accent), 0.001)
			rect("acd%d" % k, 0, y0 + 0.87, 8, y0 + 0.94, flat("acd%d" % k, accent), 0.001)
		cu = bpy.data.curves.new("t%d" % k, "FONT")
		cu.body = text
		cu.size = 0.62
		cu.align_x = "CENTER"
		cu.align_y = "CENTER"
		cu.offset = 0.018  # a bolder weight
		cu.space_character = 1.05
		ob = bpy.data.objects.new("t%d" % k, cu)
		ob.location = (4.0, y0 + 0.5, 0.002)
		ob.data.materials.append(flat("fg%d" % k, fg))
		sc.collection.objects.link(ob)
		# keep long names inside the board
		dg = sc.view_layers[0].depsgraph
		dg.update()
		w = ob.evaluated_get(dg).dimensions.x
		if w > 6.6:
			ob.scale.x = 6.6 / w
	cam = bpy.data.objects.new("AtlasCam", bpy.data.cameras.new("AtlasCam"))
	cam.data.type = "ORTHO"
	cam.data.ortho_scale = 8.0
	cam.location = (4.0, rows / 2, 5.0)
	sc.collection.objects.link(cam)
	sc.camera = cam
	# the camera sees 8 x 8 world units: 8 rows of 8 x 1 boards, exactly the atlas
	sc.render.filepath = path
	sc.render.image_settings.file_format = "JPEG"
	sc.render.image_settings.quality = 90
	bpy.ops.render.render(write_still=True, scene=sc.name)
	img = bpy.data.images.load(path)
	img.pack()
	return img


def ads_material(img):
	m = bpy.data.materials.get("Ads")
	nt = m.node_tree
	bsdf = nt.nodes.get("Principled BSDF")
	tex = nt.nodes.new("ShaderNodeTexImage")
	tex.image = img
	tex.interpolation = "Linear"
	nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
	return m


# ---------------------------------------------------------------- grandstand
def seat_x(i):
	return -BAY / 2 + AISLE + SEAT_PITCH * (i + 0.5)


def build_stand_row():
	"""One tier: origin at the tread's front edge (top surface), bay centre."""
	mb = MB()
	x0, x1 = -BAY / 2, BAY / 2
	mb.colour = srgb("#bdb9b0")
	mb.quad((x0, 0, -RISE), (x1, 0, -RISE), (x1, 0, 0), (x0, 0, 0), "Concrete", (0, -1, 0))
	mb.quad((x0, 0, 0), (x1, 0, 0), (x1, TREAD, 0), (x0, TREAD, 0), "Concrete", (0, 0, 1))
	# aisle: a half step on the back half of the tread, yellow nosing
	mb.box((x0, TREAD / 2, 0), (x0 + AISLE, TREAD, RISE / 2), "Concrete", skip=("-z", "+y"))
	mb.box((x0, TREAD / 2 - 0.001, RISE / 2 - 0.05), (x0 + AISLE, TREAD / 2 + 0.05, RISE / 2 + 0.002), "Concrete",
		skip=("-z",), col="#e8c21c")
	mb.box((x0, -0.001, -0.05), (x0 + AISLE, 0.05, 0.002), "Concrete", skip=("-z",), col="#e8c21c")
	# seats: a moulded pan and back on a bracket, with a slight random shade
	for i in range(SEATS):
		x = seat_x(i)
		hw = 0.22
		shade = 0.94 + 0.06 * ((i * 7) % 5) / 4
		mb.colour = (shade, shade, shade)
		pan = [(x - hw, 0.20, 0.43), (x + hw, 0.20, 0.43), (x + hw, 0.58, 0.40), (x - hw, 0.58, 0.40)]
		mb.poly(pan, "Seat", (0, 0, 1))
		mb.quad((x - hw, 0.20, 0.36), (x + hw, 0.20, 0.36), (x + hw, 0.20, 0.43), (x - hw, 0.20, 0.43), "Seat", (0, -1, 0))
		back = [(x - hw, 0.60, 0.40), (x + hw, 0.60, 0.40), (x + hw * 0.92, 0.70, 0.86), (x - hw * 0.92, 0.70, 0.86)]
		mb.poly(back, "Seat", (0, -1, 0.2))
		mb.poly([(p[0], p[1] + 0.04, p[2]) for p in back], "Seat", (0, 1, -0.2))
		mb.quad((x - hw * 0.92, 0.70, 0.86), (x + hw * 0.92, 0.70, 0.86), (x + hw * 0.92, 0.74, 0.86),
			(x - hw * 0.92, 0.74, 0.86), "Seat", (0, 0, 1))
		mb.colour = srgb("#3a3f45")
		mb.box((x - 0.03, 0.38, 0.0), (x + 0.03, 0.46, 0.39), "SteelPaint", skip=("-z", "+z"))
	return mb


# Crowd vertex codes: red = body part, green = seat index / SEATS
SHIRT, SKIN, LEGS, HAIR = 0.0, 0.25, 0.5, 0.75


def build_crowd_row():
	mb = MB()
	for i in range(SEATS):
		x = seat_x(i)
		g = (i + 0.5) / SEATS

		def c(part):
			return (part, g, 0.0)
		# shins in front of the seat, thighs on it
		mb.box((x - 0.17, 0.10, 0.02), (x + 0.17, 0.22, 0.45), "Crowd", skip=("-z", "+y", "+z", "-x", "+x"), col=c(LEGS))
		mb.box((x - 0.18, 0.12, 0.43), (x + 0.18, 0.56, 0.58), "Crowd", skip=("-z", "+y"), col=c(LEGS))
		# torso, a little narrower at the hips
		hip = [(x - 0.17, 0.46, 0.50), (x + 0.17, 0.46, 0.50), (x + 0.17, 0.66, 0.50), (x - 0.17, 0.66, 0.50)]
		sh = [(x - 0.21, 0.50, 1.02), (x + 0.21, 0.50, 1.02), (x + 0.20, 0.68, 1.02), (x - 0.20, 0.68, 1.02)]
		ctr = Vector((x, 0.58, 0.76))
		for a, b in ((0, 1), (1, 2), (2, 3), (3, 0)):
			mb.poly([hip[a], hip[b], sh[b], sh[a]], "Crowd", lambda q: q - ctr, col=c(SHIRT))
		mb.poly(sh, "Crowd", (0, 0, 1), col=c(SHIRT))
		# arms hanging by the torso
		for side in (-1, 1):
			ax = x + side * 0.235
			mb.box((ax - 0.05, 0.50, 0.62), (ax + 0.05, 0.64, 1.0), "Crowd", skip=("-z", "+y"), col=c(SHIRT))
		# head, hair on top and at the back
		hc = Vector((x, 0.585, 1.20))
		hx, hy, hz = 0.09, 0.105, 0.125
		lo = [(x - hx, 0.585 - hy, 1.08), (x + hx, 0.585 - hy, 1.08), (x + hx, 0.585 + hy, 1.08), (x - hx, 0.585 + hy, 1.08)]
		mid = [(x - hx * 1.05, 0.585 - hy * 1.05, 1.22), (x + hx * 1.05, 0.585 - hy * 1.05, 1.22),
			(x + hx * 1.05, 0.585 + hy * 1.05, 1.22), (x - hx * 1.05, 0.585 + hy * 1.05, 1.22)]
		top = [(x - hx * 0.7, 0.585 - hy * 0.7, 1.08 + 2 * hz), (x + hx * 0.7, 0.585 - hy * 0.7, 1.08 + 2 * hz),
			(x + hx * 0.7, 0.585 + hy * 0.7, 1.08 + 2 * hz), (x - hx * 0.7, 0.585 + hy * 0.7, 1.08 + 2 * hz)]
		for a, b in ((0, 1), (1, 2), (2, 3), (3, 0)):
			face_part = SKIN if (a, b) != (2, 3) else HAIR
			mb.poly([lo[a], lo[b], mid[b], mid[a]], "Crowd", lambda q: q - hc, col=c(face_part))
			mb.poly([mid[a], mid[b], top[b], top[a]], "Crowd", lambda q: q - hc, col=c(HAIR if (a, b) != (0, 1) else SKIN))
		mb.poly(top, "Crowd", (0, 0, 1), col=c(HAIR))
	return mb


def stand_dims(t):
	z_top = FIRST_Z + (t - 1) * RISE
	y_back = t * TREAD + CONCOURSE
	return z_top, y_back


def roof_line(t):
	"""(y, z) of the roof's back (at the column) and front edge."""
	z_top, y_back = stand_dims(t)
	return (y_back + 0.25, z_top + ROOF_BACK), (-ROOF_OVERHANG, z_top + ROOF_FRONT)


def build_stand_column(mb, t, x):
	"""Column behind the back wall, the tapered roof girder, the mast above it and its tie rod."""
	z_top, y_back = stand_dims(t)
	(yb, zb), (yf, zf) = roof_line(t)
	mb.colour = srgb("#3a3f45")
	mb.box((x - 0.2, yb - 0.2, 0), (x + 0.2, yb + 0.2, zb + 3.2), "SteelPaint", skip=("-z",))
	# girder: deep at the column, slim at the tip, its top under the roof sheet
	prof = [(yb + 0.2, zb - 1.3), (yf + 0.1, zf - 0.32), (yf + 0.1, zf - 0.06), (yb + 0.2, zb - 0.06)]
	mb.prism([(p[0], p[1]) for p in prof], x - 0.13, x + 0.13, "SteelPaint")
	# tie rod from the mast head to two thirds along the girder
	tip = Vector((x, lerp(yb, yf, 0.66), lerp(zb, zf, 0.66)))
	mb.tube((x, yb, zb + 3.1), tip, 0.045, "Steel", segs=6)
	# column footing
	mb.colour = srgb("#8d8a84")
	mb.box((x - 0.35, yb - 0.35, 0), (x + 0.35, yb + 0.35, 0.25), "ConcreteDark", skip=("-z",))


def lerp(a, b, t):
	return a + (b - a) * t


def build_stand_frame(t):
	mb = MB()
	x0, x1 = -BAY / 2, BAY / 2
	z_top, y_back = stand_dims(t)
	(yb, zb), (yf, zf) = roof_line(t)
	# front wall (its face carries the sponsor boards) and the glass railing on top
	mb.colour = srgb("#bdb9b0")
	mb.box((x0, -0.32, 0), (x1, 0.0, FIRST_Z + 0.08), "Concrete", skip=("-z", "-x", "+x", "+y"))
	for k in range(9):
		px = x0 + 0.1 + k * (BAY - 0.2) / 8
		mb.colour = srgb("#a4aaaf")
		mb.box((px - 0.03, -0.2, FIRST_Z + 0.08), (px + 0.03, -0.14, FIRST_Z + 1.0), "Steel", skip=("-z",))
	mb.colour = (1, 1, 1)
	mb.quad((x0, -0.17, FIRST_Z + 0.1), (x1, -0.17, FIRST_Z + 0.1), (x1, -0.17, FIRST_Z + 0.95), (x0, -0.17, FIRST_Z + 0.95), "Glass", (0, -1, 0))
	mb.colour = srgb("#a4aaaf")
	mb.tube((x0, -0.17, FIRST_Z + 1.0), (x1, -0.17, FIRST_Z + 1.0), 0.03, "Steel", segs=6, caps=False)
	# concourse behind the top tier, back wall with its railing, cladding ribs
	mb.colour = srgb("#bdb9b0")
	mb.quad((x0, t * TREAD, z_top), (x1, t * TREAD, z_top), (x1, y_back, z_top), (x0, y_back, z_top), "Concrete", (0, 0, 1))
	mb.colour = srgb("#c9ced2")
	mb.box((x0, y_back, 0), (x1, y_back + 0.2, z_top + 1.1), "Cladding", skip=("-z", "-x", "+x"))
	for k in range(4):
		rx = x0 + (k + 0.5) * BAY / 4
		mb.box((rx - 0.06, y_back + 0.2, 0), (rx + 0.06, y_back + 0.28, z_top + 1.1), "Cladding", skip=("-z", "-y"),
			col="#b4babf")
	mb.colour = srgb("#8d8a84")
	mb.box((x0, y_back + 0.2, 0), (x1, y_back + 0.3, 0.6), "ConcreteDark", skip=("-z", "-x", "+x", "-y"))
	# vomitory doors in the back wall
	mb.colour = srgb("#3a3f45")
	mb.quad((1.2, y_back + 0.285, 0.05), (3.0, y_back + 0.285, 0.05), (3.0, y_back + 0.285, 2.4), (1.2, y_back + 0.285, 2.4), "SteelPaint", (0, 1, 0))
	# roof: a dark sheet on top, a light soffit underneath, purlins between the girders
	build_stand_column(mb, t, x0)

	def roof_z(y):
		return lerp(zb, zf, (y - yb) / (yf - yb))
	ry0, ry1 = yb + 0.3, yf
	mb.colour = srgb("#62686e")
	mb.quad((x0, ry1, roof_z(ry1)), (x1, ry1, roof_z(ry1)), (x1, ry0, roof_z(ry0)), (x0, ry0, roof_z(ry0)), "RoofTop", (0, 0, 1))
	mb.colour = srgb("#dcdedf")
	mb.quad((x0, ry1, roof_z(ry1) - 0.05), (x1, ry1, roof_z(ry1) - 0.05), (x1, ry0, roof_z(ry0) - 0.05),
		(x0, ry0, roof_z(ry0) - 0.05), "RoofUnder", (0, 0, -1))
	mb.quad((x0, ry0, roof_z(ry0) - 0.05), (x1, ry0, roof_z(ry0) - 0.05), (x1, ry0, roof_z(ry0)), (x0, ry0, roof_z(ry0)),
		"RoofTop", (0, 1, 0))
	mb.colour = srgb("#3a3f45")
	for f in (0.2, 0.45, 0.7, 0.92):
		y = lerp(ry0, ry1, f)
		z = roof_z(y) - 0.05
		mb.box((x0, y - 0.08, z - 0.25), (x1, y + 0.08, z), "SteelPaint", skip=("-x", "+x", "+z"))
	# floodlight strip and loudspeakers under the roof edge
	mb.colour = (1, 1, 1)
	for lx in (-2.5, 2.5):
		mb.box((lx - 0.6, yf + 0.5, roof_z(yf + 0.5) - 0.35), (lx + 0.6, yf + 0.7, roof_z(yf + 0.5) - 0.05), "Black", skip=("+z",))
	return mb


def build_stand_end(t, side):
	"""Side wall closing the bays at x = side * BAY/2, with an open steel stair up to the concourse."""
	mb = MB()
	x = side * BAY / 2
	z_top, y_back = stand_dims(t)
	th = 0.3
	xa, xb = (x, x + th) if side > 0 else (x - th, x)
	# stepped top following the tiers, as a fan of quads (convex pieces)
	mb.colour = srgb("#bdb9b0")
	prof = [(-0.32, 0.0), (-0.32, FIRST_Z + 0.08), (0.0, FIRST_Z + 0.08)]
	for k in range(t):
		yk = k * TREAD
		zk = FIRST_Z + k * RISE
		prof += [(yk, zk + 0.08), (yk + TREAD, zk + 0.08)]
		if k < t - 1:
			prof.append((yk + TREAD, zk + RISE + 0.08))
	prof += [(y_back + 0.2, z_top + 0.08), (y_back + 0.2, z_top + 1.1), (y_back + 0.2, 0.0)]
	# faces: outer and inner walls as vertical strips between the profile and the ground
	for xf, nx in ((xa, -1), (xb, 1)):
		for (ya, za), (yb2, zb2) in zip(prof[2:-2], prof[3:-1]):
			if abs(ya - yb2) < 1e-6:
				continue
			mb.quad((xf, ya, 0), (xf, yb2, 0), (xf, yb2, zb2), (xf, ya, za), "Concrete", (nx, 0, 0))
		mb.quad((xf, -0.32, 0), (xf, 0.0, 0), (xf, 0.0, FIRST_Z + 0.08), (xf, -0.32, FIRST_Z + 0.08), "Concrete", (nx, 0, 0))
		mb.quad((xf, prof[-3][0] - 0.2, 0), (xf, y_back + 0.2, 0), (xf, y_back + 0.2, z_top + 1.1),
			(xf, prof[-3][0] - 0.2, z_top + 1.1), "Concrete", (nx, 0, 0))
	# top edge caps
	for (ya, za), (yb2, zb2) in zip(prof[1:-1], prof[2:]):
		mb.quad((xa, ya, za), (xb, ya, za), (xb, yb2, zb2), (xa, yb2, zb2), "Concrete",
			lambda q: Vector((0, -(zb2 - za), (yb2 - ya))) if abs(yb2 - ya) > 1e-6 else Vector((0, -1 if zb2 > za else 1, 0)))
	mb.quad((xa, -0.32, 0), (xb, -0.32, 0), (xb, -0.32, FIRST_Z + 0.08), (xa, -0.32, FIRST_Z + 0.08), "Concrete", (0, -1, 0))
	# stair tower: flights along the side wall from the ground to the concourse
	sx0 = xb + 0.15 if side > 0 else xa - 1.45
	sx1 = sx0 + 1.3
	flight_len = z_top / 0.18 * 0.28
	y0 = max(0.4, y_back - flight_len)
	steps = max(4, int(z_top / 0.18))
	mb.colour = srgb("#a4aaaf")
	for k in range(steps):
		ys = y0 + (y_back - y0) * k / steps
		zs = z_top * (k + 1) / steps
		mb.box((sx0, ys, zs - 0.05), (sx1, ys + (y_back - y0) / steps + 0.02, zs), "Steel", skip=())
	outer = sx1 if side > 0 else sx0
	mb.tube((outer, y0, 1.0), (outer, y_back, z_top + 1.0), 0.03, "Steel", segs=6)
	for f in (0.0, 0.5, 1.0):
		yy = lerp(y0, y_back, f)
		zz = lerp(0.0, z_top, f)
		mb.tube((outer, yy, 0), (outer, yy, zz + 1.0), 0.04, "Steel", segs=6)
		mb.box(((sx0 + sx1) / 2 - 0.12, yy - 0.12, 0), ((sx0 + sx1) / 2 + 0.12, yy + 0.12, max(0.05, zz - 0.05)), "SteelPaint")
	mb.box((sx0, y_back, z_top - 0.08), (sx1, y_back + 0.5, z_top), "Steel")
	if side > 0:
		build_stand_column(mb, t, x)
	return mb


def build_board(k):
	"""A 10 m sponsor board (fascia or parapet), front face towards -Y, origin at its bottom centre."""
	mb = MB()
	x0, x1 = -BAY / 2, BAY / 2
	mb.quad((x0, 0, 0), (x1, 0, 0), (x1, 0, BOARD_H), (x0, 0, BOARD_H), "Ads", (0, -1, 0),
		uvs=[ad_uv(k, 0, 0), ad_uv(k, 1, 0), ad_uv(k, 1, 1), ad_uv(k, 0, 1)])
	mb.colour = srgb("#3a3f45")
	mb.box((x0, 0.0, -0.04), (x1, 0.12, BOARD_H + 0.04), "SteelPaint", skip=("-y",))
	return mb


# ---------------------------------------------------------------- pit building
def build_pit_bay():
	"""One garage: the open roller door and a lit interior, the glazed hospitality floor above with its
	balcony, and the roof terrace under a canopy."""
	mb = MB()
	hw = PIT_BAY / 2
	pil = 0.4  # half pillars at each end of the bay
	dw0, dw1 = -hw + pil, hw - pil
	door_h = 4.1
	D = PIT_DEPTH
	mb.colour = srgb("#eceeef")
	for sx in (-1, 1):
		xa, xb = sorted((sx * hw, sx * (hw - pil)))
		mb.box((xa, 0, 0), (xb, 0.35, PIT_GF), "White", skip=("-z", "+x" if sx > 0 else "-x", "+y"))
	# lintel over the door (the team band sits in front of it), slab edge
	mb.box((dw0, 0, door_h), (dw1, 0.35, PIT_GF), "White", skip=("-x", "+x", "+y"))
	# interior: floor, walls, ceiling with light panels, the rolled-up door drum
	# (floors 5.5 cm up, over the run-off surface; the apron reaches the pit lane's edge 1.2 m out)
	mb.colour = srgb("#a9aba8")
	mb.quad((-hw, -1.25, 0.055), (hw, -1.25, 0.055), (hw, 0.35, 0.055), (-hw, 0.35, 0.055), "Concrete", (0, 0, 1))
	mb.colour = srgb("#a3a8ab")
	mb.quad((dw0, 0.35, 0.055), (dw1, 0.35, 0.055), (dw1, D - 0.3, 0.055), (dw0, D - 0.3, 0.055), "PitFloor", (0, 0, 1))
	mb.colour = srgb("#e4e6e8")
	mb.quad((dw0, D - 0.3, 0), (dw1, D - 0.3, 0), (dw1, D - 0.3, door_h + 0.5), (dw0, D - 0.3, door_h + 0.5), "PitInterior", (0, -1, 0))
	mb.quad((dw0, 0.35, 0), (dw0, D - 0.3, 0), (dw0, D - 0.3, door_h + 0.5), (dw0, 0.35, door_h + 0.5), "PitInterior", (1, 0, 0))
	mb.quad((dw1, 0.35, 0), (dw1, D - 0.3, 0), (dw1, D - 0.3, door_h + 0.5), (dw1, 0.35, door_h + 0.5), "PitInterior", (-1, 0, 0))
	mb.quad((dw0, 0.35, door_h + 0.5), (dw1, 0.35, door_h + 0.5), (dw1, D - 0.3, door_h + 0.5), (dw0, D - 0.3, door_h + 0.5), "PitInterior", (0, 0, -1))
	# a dark team-coloured dado on the back wall, tool cabinets, tyre stacks, a monitor gantry
	mb.colour = srgb("#2f3439")
	mb.quad((dw0, D - 0.31, 0.02), (dw1, D - 0.31, 0.02), (dw1, D - 0.31, 1.3), (dw0, D - 0.31, 1.3), "PitInterior", (0, -1, 0))
	mb.colour = srgb("#b3121f")
	for cx in (-3.5, -1.2, 1.1):
		mb.box((cx, D - 1.0, 0), (cx + 2.1, D - 0.31, 1.05), "Red", skip=("-z", "+y"))
	mb.colour = srgb("#141414")
	for tx, ty in ((dw0 + 0.6, 4.0), (dw0 + 0.6, 5.2), (dw1 - 0.6, 6.0), (dw1 - 0.6, 7.2)):
		mb.lathe([(0.0, 0.30), (1.1, 0.30), (1.1, 0.16), (1.1, 0.0)], 10, "Rubber", centre=(tx, ty, 0))
	mb.colour = (1, 1, 1)
	for ly in (3.0, 7.0, 11.0):
		mb.quad((-3.0, ly, door_h + 0.49), (3.0, ly, door_h + 0.49), (3.0, ly + 0.5, door_h + 0.49), (-3.0, ly + 0.5, door_h + 0.49),
			"LightPanel", (0, 0, -1))
	mb.colour = srgb("#3a3f45")
	mb.box((dw0, 0.35, door_h - 0.05), (dw1, 0.85, door_h + 0.45), "SteelPaint", skip=("-x", "+x"))
	# hospitality floor: balcony slab, glass balustrade, glazed curtain wall set back, spandrel
	mb.colour = srgb("#eceeef")
	mb.box((-hw, -1.8, PIT_GF), (hw, 0.35, PIT_GF + 0.45), "White", skip=("-x", "+x", "+y"))
	mb.colour = (1, 1, 1)
	mb.quad((-hw, -1.72, PIT_GF + 0.45), (hw, -1.72, PIT_GF + 0.45), (hw, -1.72, PIT_GF + 1.45), (-hw, -1.72, PIT_GF + 1.45), "Glass", (0, -1, 0))
	mb.colour = srgb("#a4aaaf")
	mb.box((-hw, -1.78, PIT_GF + 1.42), (hw, -1.66, PIT_GF + 1.5), "Steel", skip=("-x", "+x"))
	for k in range(4):
		px = -hw + 0.1 + k * PIT_BAY / 4
		mb.box((px - 0.03, -1.76, PIT_GF + 0.45), (px + 0.03, -1.7, PIT_GF + 1.45), "Steel", skip=("-z", "+z"))
	gz0, gz1 = PIT_GF + 0.45, PIT_1F - 0.55
	mb.colour = srgb("#27343d")
	mb.quad((-hw, 0.5, gz0), (hw, 0.5, gz0), (hw, 0.5, gz1), (-hw, 0.5, gz1), "GlassDark", (0, -1, 0))
	mb.colour = srgb("#3a3f45")
	for k in range(9):
		mx = -hw + k * PIT_BAY / 8
		mb.box((mx - 0.05, 0.42, gz0), (mx + 0.05, 0.5, gz1), "SteelPaint", skip=("-z", "+z", "+y"))
	mb.box((-hw, 0.42, gz0 + 1.05), (hw, 0.5, gz0 + 1.12), "SteelPaint", skip=("-x", "+x", "+y"))
	mb.colour = srgb("#eceeef")
	mb.quad((-hw, 0.35, PIT_GF + 0.45), (hw, 0.35, PIT_GF + 0.45), (hw, 0.5, PIT_GF + 0.45), (-hw, 0.5, PIT_GF + 0.45), "White", (0, 0, 1))
	mb.box((-hw, 0.2, gz1), (hw, 0.5, PIT_1F), "White", skip=("-x", "+x", "+y"))
	# roof terrace: floor, glass railing, a light canopy on slim columns
	mb.colour = srgb("#8d8a84")
	mb.quad((-hw, 0.2, PIT_1F), (hw, 0.2, PIT_1F), (hw, D, PIT_1F), (-hw, D, PIT_1F), "ConcreteDark", (0, 0, 1))
	mb.colour = (1, 1, 1)
	mb.quad((-hw, 0.3, PIT_1F), (hw, 0.3, PIT_1F), (hw, 0.3, PIT_1F + 1.05), (-hw, 0.3, PIT_1F + 1.05), "Glass", (0, -1, 0))
	mb.colour = srgb("#a4aaaf")
	mb.box((-hw, 0.26, PIT_1F + 1.02), (hw, 0.34, PIT_1F + 1.1), "Steel", skip=("-x", "+x"))
	mb.colour = srgb("#eceeef")
	for cy in (1.4, D - 2.5):
		mb.tube((0, cy, PIT_1F), (0, cy, PIT_CANOPY - 0.3), 0.12, "White", segs=8, caps=False)
	mb.box((-hw, -0.6, PIT_CANOPY - 0.3), (hw, D - 1.5, PIT_CANOPY), "White", skip=("-x", "+x"))
	mb.box((-hw, -0.6, PIT_CANOPY - 0.3), (hw, D - 1.5, PIT_CANOPY - 0.29), "RoofUnder", skip=("-x", "+x", "+z", "-y", "+y"))
	# paddock side: cladding, windows, a service door
	mb.colour = srgb("#c9ced2")
	mb.box((-hw, D, 0), (hw, D + 0.25, PIT_1F + 1.1), "Cladding", skip=("-x", "+x", "-y", "-z"))
	mb.colour = srgb("#27343d")
	mb.quad((-hw + 0.6, D + 0.26, 6.0), (hw - 0.6, D + 0.26, 6.0), (hw - 0.6, D + 0.26, 7.8), (-hw + 0.6, D + 0.26, 7.8), "GlassDark", (0, 1, 0))
	mb.colour = srgb("#3a3f45")
	mb.quad((2.0, D + 0.26, 0), (5.0, D + 0.26, 0), (5.0, D + 0.26, 3.6), (2.0, D + 0.26, 3.6), "SteelPaint", (0, 1, 0))
	mb.quad((-4.5, D + 0.26, 0.9), (-1.0, D + 0.26, 0.9), (-1.0, D + 0.26, 2.4), (-4.5, D + 0.26, 2.4), "GlassDark", (0, 1, 0))
	return mb


def build_pit_band():
	"""Team colours over the garage door, with a white box-number plate."""
	mb = MB()
	hw = PIT_BAY / 2 - 0.4
	mb.box((-hw, -0.12, 4.15), (hw, 0.0, 4.75), "TeamBand", skip=("+y",))
	return mb


def build_pit_end(side):
	mb = MB()
	x = side * PIT_BAY / 2
	xa, xb = (x, x + 0.4) if side > 0 else (x - 0.4, x)
	D = PIT_DEPTH
	mb.colour = srgb("#eceeef")
	mb.box((xa, -1.8, PIT_GF), (xb, 0.35, PIT_GF + 0.45), "White", skip=("-z",))
	mb.box((xa, 0, 0), (xb, D + 0.25, PIT_1F + 1.1), "White", skip=("-z",))
	mb.box((xa, -0.6, PIT_CANOPY - 0.3), (xb, D - 1.5, PIT_CANOPY), "White")
	mb.colour = srgb("#27343d")
	xf = xb + 0.01 if side > 0 else xa - 0.01
	mb.quad((xf, 2.0, 5.8), (xf, D - 2.0, 5.8), (xf, D - 2.0, 7.9), (xf, 2.0, 7.9), "GlassDark", (side, 0, 0))
	return mb


def build_race_control():
	"""Race control: a four-storey block with a raked glass control room on top, at the pit exit end.
	Origin on the ground at its front (lane side) edge, centred on x; it extends 14 m along the lane."""
	mb = MB()
	w, D = 14.0, 15.0
	hw = w / 2
	mb.colour = srgb("#eceeef")
	mb.box((-hw, 0, 0), (hw, D, 3.2), "White", skip=("-z",))
	mb.colour = srgb("#27343d")
	mb.quad((-hw + 0.8, -0.01, 0.4), (hw - 0.8, -0.01, 0.4), (hw - 0.8, -0.01, 2.8), (-hw + 0.8, -0.01, 2.8), "GlassDark", (0, -1, 0))
	for f in range(3):
		z0 = 3.2 + f * 3.4
		mb.colour = srgb("#27343d")
		mb.box((-hw + 0.3, 0.3, z0), (hw - 0.3, D - 0.3, z0 + 3.0), "GlassDark", skip=("-z", "+z"))
		mb.colour = srgb("#eceeef")
		mb.box((-hw, -0.2, z0 + 3.0), (hw, D, z0 + 3.4), "White", skip=())
		mb.colour = srgb("#3a3f45")
		for k in range(11):
			mx = -hw + 0.3 + k * (w - 0.6) / 10
			mb.box((mx - 0.04, 0.24, z0), (mx + 0.04, 0.3, z0 + 3.0), "SteelPaint", skip=("-z", "+z", "+y"))
	# control room: glass leaning out over the lane, deep roof overhang
	z0 = 3.2 + 3 * 3.4
	mb.colour = srgb("#27343d")
	fr = [(-hw + 0.3, -0.6, z0 + 3.6), (hw - 0.3, -0.6, z0 + 3.6), (hw - 0.3, 0.4, z0), (-hw + 0.3, 0.4, z0)]
	mb.poly(fr, "GlassDark", (0, -1, -0.3))
	mb.box((-hw + 0.3, 0.4, z0), (hw - 0.3, D - 0.3, z0 + 3.6), "GlassDark", skip=("-z", "+z", "-y"))
	for sx in (-1, 1):
		xx = sx * (hw - 0.3)
		mb.poly([(xx, -0.6, z0 + 3.6), (xx, 0.4, z0 + 3.6), (xx, 0.4, z0)], "GlassDark", (sx, 0, 0))
	mb.colour = srgb("#eceeef")
	mb.box((-hw - 0.4, -1.8, z0 + 3.6), (hw + 0.4, D + 0.3, z0 + 4.2), "White")
	# RACE CONTROL lettering on the roof fascia, a timing mast with a wind sock
	mb.colour = (1, 1, 1)
	kit.text_mesh(mb, "RACE CONTROL", (0, -1.82, z0 + 3.9), 0.75, "Sign", axis_u=(1, 0, 0), axis_v=(0, 0, 1))
	mb.colour = srgb("#a4aaaf")
	mb.tube((hw - 1.0, D - 2.0, z0 + 4.2), (hw - 1.0, D - 2.0, z0 + 10.0), 0.06, "Steel", segs=6)
	mb.colour = srgb("#ef6c00")
	mb.tube((hw - 1.0, D - 2.0, z0 + 9.6), (hw - 1.0, D - 3.8, z0 + 9.3), 0.2, "Red", segs=8)
	return mb


# ---------------------------------------------------------------- start / finish gantry
GANTRY_H = 7.2  # beam centre above the road (Godot: race_world.gd GANTRY_BEAM_Y)


def build_gantry_leg():
	"""A square lattice tower on a concrete plinth, origin at its foot (the beam sits on top)."""
	mb = MB()
	s = 0.45
	top = GANTRY_H + 0.7
	mb.colour = srgb("#8d8a84")
	mb.box((-0.8, -0.8, -0.5), (0.8, 0.8, 0.6), "ConcreteDark", skip=("-z",))
	mb.colour = srgb("#2c3138")
	for sx in (-1, 1):
		for sy in (-1, 1):
			mb.tube((sx * s, sy * s, 0.6), (sx * s, sy * s, top), 0.07, "SteelPaint", segs=6)
	n = 8
	for k in range(n):
		z0 = 0.6 + (top - 0.6) * k / n
		z1 = 0.6 + (top - 0.6) * (k + 1) / n
		for (ax, ay), (bx, by) in (((-1, -1), (1, -1)), ((1, -1), (1, 1)), ((1, 1), (-1, 1)), ((-1, 1), (-1, -1))):
			if k % 2:
				ax, ay, bx, by = bx, by, ax, ay
			mb.tube((ax * s, ay * s, z0), (bx * s, by * s, z1), 0.03, "SteelPaint", segs=4, caps=False)
			mb.tube((ax * s, ay * s, z1), (bx * s, by * s, z1), 0.03, "SteelPaint", segs=4, caps=False)
	return mb


def build_gantry_beam():
	"""A 10 m box truss along Y, centred on the origin at beam height, with sponsor boards front and back
	(Godot stretches it across the road)."""
	mb = MB()
	L = 10.0
	h = 0.6
	w = 0.55
	mb.colour = srgb("#2c3138")
	for sx in (-1, 1):
		for sz in (-1, 1):
			mb.tube((sx * w, -L / 2, sz * h), (sx * w, L / 2, sz * h), 0.07, "SteelPaint", segs=6, caps=True)
	n = 8
	for k in range(n + 1):
		y = -L / 2 + L * k / n
		for sx in (-1, 1):
			mb.tube((sx * w, y, -h), (sx * w, y, h), 0.035, "SteelPaint", segs=4, caps=False)
		if k < n:
			y1 = y + L / n
			for sx in (-1, 1):
				mb.tube((sx * w, y, -h), (sx * w, y1, h) if k % 2 == 0 else (sx * w, y1, -h), 0.03, "SteelPaint", segs=4, caps=False)
				if k % 2:
					mb.tube((sx * w, y, h), (sx * w, y1, -h), 0.03, "SteelPaint", segs=4, caps=False)
	# boards: sponsor 0 (SEICENTO 900 CUP) facing the approaching cars, 5 on the far side
	for face, k in ((-1, 0), (1, 5)):
		x = face * (w + 0.1)
		uvs = [ad_uv(k, 0, 0), ad_uv(k, 1, 0), ad_uv(k, 1, 1), ad_uv(k, 0, 1)]
		pts = [(x, -L / 2, -h), (x, L / 2, -h), (x, L / 2, h), (x, -L / 2, h)]
		if face < 0:
			pts = [(x, L / 2, -h), (x, -L / 2, -h), (x, -L / 2, h), (x, L / 2, h)]
		mb.poly(pts, "Ads", (face, 0, 0), uvs=uvs, col=(1, 1, 1))
	return mb


def build_gantry_lights():
	"""The start-light housing under the beam's centre: two rows of five black pods with visors.
	Godot adds its own light discs at x = -0.62, y = (i - 2) * 1.1, z = -1.05 (race_world.gd)."""
	mb = MB()
	mb.colour = srgb("#121315")
	mb.box((-0.5, -3.0, -1.65), (0.45, 3.0, -0.5), "Black")
	for i in range(5):
		y = (i - 2) * 1.1
		for zz in (-0.8, -1.35):
			mb.box((-0.62, y - 0.36, zz - 0.26), (-0.5, y + 0.36, zz + 0.26), "Black", skip=("+x",))
			mb.box((-0.9, y - 0.34, zz + 0.2), (-0.62, y + 0.34, zz + 0.24), "Black")
	mb.colour = srgb("#a4aaaf")
	for y in (-2.6, 2.6):
		mb.tube((0, y, -0.5), (0, y, -0.1), 0.05, "Steel", segs=6)
	return mb


# ---------------------------------------------------------------- TV tower
def build_tv_tower():
	"""A scaffold tower: platform floor at the origin, 9 m legs, rails, a camera on a tripod."""
	mb = MB()
	s = 0.9
	depth = 9.0
	mb.colour = srgb("#a4aaaf")
	for sx in (-1, 1):
		for sy in (-1, 1):
			mb.tube((sx * s, sy * s, -depth), (sx * s, sy * s, 1.1), 0.045, "Steel", segs=5)
	for k in range(6):
		z = -depth + (depth) * k / 6
		z1 = z + depth / 6
		for (ax, ay), (bx, by) in (((-1, -1), (1, -1)), ((1, -1), (1, 1)), ((1, 1), (-1, 1)), ((-1, 1), (-1, -1))):
			mb.tube((ax * s, ay * s, z1), (bx * s, by * s, z1), 0.03, "Steel", segs=4, caps=False)
			mb.tube((ax * s, ay * s, z), (bx * s, by * s, z1), 0.025, "Steel", segs=4, caps=False)
	for (ax, ay), (bx, by) in (((-1, -1), (1, -1)), ((1, -1), (1, 1)), ((1, 1), (-1, 1)), ((-1, 1), (-1, -1))):
		mb.tube((ax * s, ay * s, 1.05), (bx * s, by * s, 1.05), 0.03, "Steel", segs=4, caps=False)
		mb.tube((ax * s, ay * s, 0.55), (bx * s, by * s, 0.55), 0.025, "Steel", segs=4, caps=False)
	mb.colour = srgb("#8d7a5a")
	mb.box((-s - 0.1, -s - 0.1, -0.08), (s + 0.1, s + 0.1, 0.0), "ConcreteDark")
	# camera on a tripod, an umbrella-like sun shade
	mb.colour = srgb("#121315")
	mb.box((-0.35, -0.12, 1.35), (0.25, 0.12, 1.6), "Black")
	mb.tube((0.25, 0, 1.47), (0.55, 0, 1.47), 0.08, "Black", segs=8)
	for a in range(3):
		ang = a * 2 * math.pi / 3
		mb.tube((0, 0, 1.35), (0.45 * math.cos(ang), 0.45 * math.sin(ang), 0.0), 0.02, "Black", segs=4)
	mb.colour = srgb("#a4aaaf")
	mb.tube((-0.4, 0.5, 0.0), (-0.4, 0.5, 2.4), 0.03, "Steel", segs=5)
	mb.colour = srgb("#16357a")
	mb.lathe([(2.4, 0.0), (2.65, 0.0), (2.4, 1.1)], 8, "SteelPaint", centre=(-0.4, 0.5, 0.0))
	return mb


# ---------------------------------------------------------------- previews
def preview(objs, out_dir):
	"""A short grandstand run, a strip of pit garages and the gantry over a road."""
	cam = kit.setup_preview(ground=400.0)
	road = bpy.data.meshes.new("Road")
	road.from_pydata([(-100, -40, 0.01), (100, -40, 0.01), (100, -30, 0.01), (-100, -30, 0.01)], [], [(0, 1, 2, 3)])
	rm = bpy.data.materials.new("RoadMat")
	rm.use_nodes = True
	rm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.03, 0.03, 0.035, 1)
	road.materials.append(rm)
	bpy.context.scene.collection.objects.link(bpy.data.objects.new("Road", road))
	t = 7
	z_top, _ = stand_dims(t)
	(_, _), (yf, zf) = roof_line(t)
	for b in range(4):
		x = -15 + b * BAY
		kit.place(objs["StandFrame_T%02d" % t], (x, -20, 0))
		kit.place(objs["StandBoard_%d" % (b % len(ADS))], (x, -20 - 0.33, 0.3))
		kit.place(objs["StandBoard_%d" % ((b + 3) % len(ADS))], (x, -20 + yf - 0.14, zf - 0.95))
		for k in range(t):
			kit.place(objs["StandRow"], (x, -20 + k * TREAD, FIRST_Z + k * RISE))
			kit.place(objs["StandCrowd"], (x, -20 + k * TREAD, FIRST_Z + k * RISE))
	kit.place(objs["StandEndL_T%02d" % t], (-15, -20, 0))
	kit.place(objs["StandEndR_T%02d" % t], (15, -20, 0))
	# pits on the other side of the road, facing it
	for b in range(4):
		kit.place(objs["PitBay"], (-18 + b * PIT_BAY, -50, 0), rot_z=math.pi)
		kit.place(objs["PitBayBand"], (-18 + b * PIT_BAY, -50, 0), rot_z=math.pi)
	kit.place(objs["PitEndL"], (-18 + 3 * PIT_BAY, -50, 0), rot_z=math.pi)
	kit.place(objs["PitEndR"], (-18, -50, 0), rot_z=math.pi)
	kit.place(objs["RaceControl"], (-18 - PIT_BAY / 2 - 7.2, -50, 0), rot_z=math.pi)
	# gantry across the road at x = 40
	for y in (-42.5, -27.5):
		kit.place(objs["GantryLeg"], (40, y, 0))
	kit.place(objs["GantryBeam"], (40, -35, GANTRY_H), scale=(1, 1.5, 1))
	kit.place(objs["GantryLights"], (40, -35, GANTRY_H))
	kit.place(objs["TvTower"], (60, -15, 6.0))
	views = {
		"stand_front": ((-5, -45, 3.0), (0, -12, 6), 55),
		"stand_34": ((-40, -38, 10.0), (0, -10, 4), 50),
		"stand_back": ((20, 25, 8.0), (0, -12, 5), 55),
		"stand_close": ((6, -24, 3.5), (0, -15, 3.5), 60),
		"pits": ((-10, -22, 4.0), (-5, -55, 5), 60),
		"pits_34": ((30, -20, 14.0), (0, -52, 5), 55),
		"gantry": ((10, -35, 2.0), (40, -35, 6), 55),
		"overview": ((-70, -110, 55.0), (5, -30, 0), 45),
	}
	for name, (eye, target, fov) in views.items():
		kit.render(cam, os.path.join(out_dir, name + ".png"), eye, target, fov)


# ---------------------------------------------------------------- main
def main():
	bpy.ops.wm.read_factory_settings(use_empty=True)
	import tempfile
	atlas_png = os.path.join(tempfile.gettempdir(), "seicento_ads_atlas.jpg")
	img = build_ads_atlas(atlas_png)
	for n in MATERIALS:
		kit.material(n)
	ads_material(img)
	parts = {"StandRow": build_stand_row(), "StandCrowd": build_crowd_row()}
	for t in TIERS:
		parts["StandFrame_T%02d" % t] = build_stand_frame(t)
		parts["StandEndL_T%02d" % t] = build_stand_end(t, -1)
		parts["StandEndR_T%02d" % t] = build_stand_end(t, 1)
	for k in range(len(ADS)):
		parts["StandBoard_%d" % k] = build_board(k)
	parts["PitBay"] = build_pit_bay()
	parts["PitBayBand"] = build_pit_band()
	parts["PitEndL"] = build_pit_end(-1)
	parts["PitEndR"] = build_pit_end(1)
	parts["RaceControl"] = build_race_control()
	parts["GantryLeg"] = build_gantry_leg()
	parts["GantryBeam"] = build_gantry_beam()
	parts["GantryLights"] = build_gantry_lights()
	parts["TvTower"] = build_tv_tower()
	objs = {}
	for name, mb in parts.items():
		objs[name] = mb.emit(name)
		if not name.startswith(("StandFrame", "StandEnd")) or name.endswith("T07"):
			print("%-16s %6d tris" % (name, mb.tris()))
	kit.export_glb(OUT_GLB, list(objs.values()))
	if kit.arg("--blend"):
		bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(kit.arg("--blend")))
	if kit.arg("--renders"):
		preview(objs, os.path.abspath(kit.arg("--renders")))


if __name__ == "__main__":
	main()
