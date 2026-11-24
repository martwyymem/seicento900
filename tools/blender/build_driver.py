"""A low-poly seated racing driver (~1 k triangles) for every car's cockpit: a helmet with a visor, a race suit, gloved
hands on a steering wheel. Run with Blender from the repository root:

    blender -b -P tools/blender/build_driver.py -- [--renders DIR] [--blend FILE]
    blender -b -P tools/blender/build_driver.py -- --renders DIR --car godot/models/golf4.glb \
        --seat -0.37,0.495,0.2765 --wheel -0.37,0.99,-0.2235 --scale 0.92

Writes godot/models/driver.glb. race_car_visual.gd (RaceCarVisual._build_driver) finds the pieces by object name and
animates them, so keep these stable (each object's origin is its pivot):
  DriverBody   suit torso, pelvis, legs and boots; origin at the hip (the seat contact point, on the centreline)
  DriverHead   helmet with its visor; origin at the neck, the pivot the head turns and leans about
  DriverArmL / DriverArmR   sleeve and glove in one piece, origin at the shoulder, built straight ahead (+Y) so the visual
               can aim it at the hand's place on the wheel and stretch it along its length
  SteeringWheel   a 3-spoke wheel, origin at the hub, the rim in the XZ plane facing back (-Y here, +Z in Godot): the
               visual spins it about that axis and rakes it
Materials: Suit and Helmet (white by vertex colour: the visual tints each per car; boots and gloves are dark vertex
colours), Visor (dark gloss), Wheel. Blender frame: +X right, +Y forward, +Z up; the origin is the driver's hip on the seat,
standing for a ~1.75 m man (head top 0.86 m above the seat), the visual scales it per car (driver_scale).
"""
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit  # noqa: E402
from kit import MB, srgb  # noqa: E402

OUT_GLB = os.path.join(kit.ROOT, "godot", "models", "driver.glb")
kit.MATERIALS.update({
	"Suit": (srgb("#ffffff"), 0.82, 0.0, {}),
	"Helmet": (srgb("#ffffff"), 0.30, 0.0, {}),
	"Visor": (srgb("#0c1014"), 0.08, 0.2, {}),
	"Wheel": (srgb("#ffffff"), 0.55, 0.0, {}),
})

DARK = (0.012, 0.012, 0.014)  # vertex colour of boots, gloves and the collar: the tint multiplies it to nothing
GREY = (0.03, 0.03, 0.034)  # the wheel's rim and spokes (the Wheel material is white)
LEAN = math.radians(12)  # the seat back's rake: the torso lies back by this
T = Vector((0.0, -math.sin(LEAN), math.cos(LEAN)))  # up the spine
HIP = Vector((0.0, 0.02, 0.12))  # centre of the pelvis
SHOULDER_A = 0.41  # along the spine from the hip centre to the shoulder joint
NECK_A = 0.50  # ... to the neck's base, the head's pivot
SHOULDER_X = 0.215
THIGH_LEN, SHIN_LEN = 0.44, 0.42
ARM_UP, ARM_FORE, ARM_HAND = 0.30, 0.28, 0.09
WHEEL_R = 0.19  # the rim's radius the visual scales to each car's wheel

NECK = HIP + T * NECK_A
SHOULDER = {s: HIP + T * SHOULDER_A + Vector((s * SHOULDER_X, 0.0, 0.0)) for s in (-1, 1)}


def ring_pts(c, ax, ay, hx, hy, n):
	"""n points round an ellipse centred c in the plane spanned by ax (x-ish) and ay (y-ish) unit vectors."""
	return [c + ax * (hx * math.cos(2 * math.pi * k / n)) + ay * (hy * math.sin(2 * math.pi * k / n)) for k in range(n)]


def loft(mb, rings, mat, cols=None, cap0=True, cap1=True):
	"""Quads between consecutive closed rings; flat caps at the ends."""
	n = len(rings[0])
	ids = []
	for ri, r in enumerate(rings):
		col = cols[ri] if cols else None
		ids.append([mb.vert(p, col) for p in r])
	cen = sum((p for r in rings for p in r), Vector()) / (len(rings) * n)
	for i in range(len(rings) - 1):
		for k in range(n):
			k2 = (k + 1) % n
			mb.face([ids[i][k], ids[i][k2], ids[i + 1][k2], ids[i + 1][k]], mat,
				lambda q, i=i: q - (sum(rings[i], Vector()) / n + sum(rings[i + 1], Vector()) / n) / 2)
	if cap0:
		mb.face(ids[0], mat, sum(rings[0], Vector()) / n - sum(rings[1], Vector()) / n)
	if cap1:
		mb.face(ids[-1], mat, sum(rings[-1], Vector()) / n - sum(rings[-2], Vector()) / n)
	return ids


def ellipsoid(mb, c, r, mat, segs=10, rings=5, col=None, basis=None):
	"""A UV sphere of radii r about c."""
	c = Vector(c)
	rows = []
	for i in range(1, rings):
		la = -math.pi / 2 + math.pi * i / rings
		row = []
		for j in range(segs):
			lo = 2 * math.pi * j / segs
			p = Vector((r[0] * math.cos(la) * math.cos(lo), r[1] * math.cos(la) * math.sin(lo), r[2] * math.sin(la)))
			row.append(c + (basis @ p if basis else p))
		rows.append(row)
	ids = [[mb.vert(p, col) for p in row] for row in rows]
	for i in range(len(rows) - 1):
		for j in range(segs):
			j2 = (j + 1) % segs
			mb.face([ids[i][j], ids[i][j2], ids[i + 1][j2], ids[i + 1][j]], mat, lambda q: q - c)
	for row, z in ((ids[0], -1), (ids[-1], 1)):
		pole = mb.vert(c + Vector((0, 0, z * r[2])), col)
		for j in range(segs):
			if z < 0:
				mb.face([pole, row[(j + 1) % segs], row[j]], mat, lambda q: q - c)
			else:
				mb.face([pole, row[j], row[(j + 1) % segs]], mat, lambda q: q - c)


def limb(mb, pts, radii, mat, col, segs=6, caps=True):
	"""A tapered tube through pts with a radius at each."""
	rings = []
	for i, p in enumerate(pts):
		a = pts[max(i - 1, 0)]
		b = pts[min(i + 1, len(pts) - 1)]
		axis = (b - a).normalized()
		helper = Vector((0, 0, 1)) if abs(axis.z) < 0.9 else Vector((1, 0, 0))
		u = axis.cross(helper).normalized()
		v = axis.cross(u)
		rings.append(ring_pts(p, u, v, radii[i], radii[i], segs))
	loft(mb, rings, mat, cols=[col] * len(rings), cap0=caps, cap1=caps)


# ---------------------------------------------------------------- body
def build_body():
	mb = MB()
	white = (1.0, 1.0, 1.0)
	# pelvis and torso: a loft of rounded sections up the leaning spine (half width, half depth)
	ax, ay = Vector((1, 0, 0)), Vector((0, math.cos(LEAN), math.sin(LEAN)))  # across, and front-to-back along the lean
	sections = [(-0.06, 0.16, 0.13), (0.00, 0.175, 0.14), (0.14, 0.155, 0.115), (0.28, 0.185, 0.125), (0.38, 0.205, 0.115),
		(0.45, 0.17, 0.09), (0.50, 0.075, 0.07)]
	rings = [ring_pts(HIP + T * a, ax, ay, hx, hy, 10) for a, hx, hy in sections]
	loft(mb, rings, "Suit", cols=[white] * 5 + [white, DARK], cap0=True, cap1=False)
	# the legs: thigh to the knee, shin to the ankle, a boot flat on the pedal
	for s in (-1, 1):
		hip = Vector((s * 0.10, 0.04, 0.10))
		knee = Vector((s * 0.115, 0.46, 0.16))
		ankle = Vector((s * 0.115, 0.66, -0.22))
		limb(mb, [hip, (hip + knee) / 2, knee], [0.082, 0.072, 0.06], "Suit", white, segs=6)
		limb(mb, [knee, (knee + ankle) / 2, ankle], [0.058, 0.05, 0.043], "Suit", white, segs=6)
		mb.box(Vector((s * 0.115 - 0.045, 0.62, -0.285)), Vector((s * 0.115 + 0.045, 0.86, -0.20)), "Suit", col=DARK)
	return mb


# ---------------------------------------------------------------- head (origin at the neck)
def build_head():
	mb = MB()
	c = Vector((0.0, 0.015, 0.105))
	rx, ry, rz = 0.148, 0.172, 0.150
	segs, rings = 14, 8
	rows = []
	for i in range(1, rings):
		la = -math.pi / 2 + math.pi * i / rings
		row = []
		for j in range(segs):
			lo = 2 * math.pi * j / segs
			x = rx * math.cos(la) * math.cos(lo)
			y = ry * math.cos(la) * math.sin(lo)
			z = rz * math.sin(la)
			if y > 0 and z < 0:  # the chin bar sticks out ahead of the face
				y += 0.045 * (-z / rz) * max(0.0, math.sin(lo))
			row.append(c + Vector((x, y, z)))
		rows.append(row)
	ids = [[mb.vert(p) for p in row] for row in rows]
	for i in range(len(rows) - 1):
		for j in range(segs):
			j2 = (j + 1) % segs
			quad = [ids[i][j], ids[i][j2], ids[i + 1][j2], ids[i + 1][j]]
			centre = sum((mb.v[k] for k in quad), Vector()) / 4 - c
			# the visor: a band across the face, from the eyes down to the cheeks
			vis = centre.y > 0.5 * ry and abs(centre.x) < 0.095 and -0.01 < centre.z < 0.075
			mb.face(quad, "Visor" if vis else "Helmet", lambda q: q - c)
	for row, z in ((ids[0], -1), (ids[-1], 1)):
		pole = mb.vert(c + Vector((0, 0, z * rz)))
		for j in range(segs):
			if z < 0:
				mb.face([pole, row[(j + 1) % segs], row[j]], "Helmet", lambda q: q - c)
			else:
				mb.face([pole, row[j], row[(j + 1) % segs]], "Helmet", lambda q: q - c)
	return mb


# ---------------------------------------------------------------- arms (origin at the shoulder, built forward along +Y)
def build_arm(side):
	mb = MB()
	white = (1.0, 1.0, 1.0)
	s = side
	elbow = Vector((s * 0.03, 0.165, -0.249))
	wrist = elbow + Vector((0.0, 0.98, 0.20)).normalized() * ARM_FORE
	glove = wrist + Vector((0.0, 0.98, 0.20)).normalized() * 0.05
	ellipsoid(mb, (0, 0, 0), (0.065, 0.065, 0.065), "Suit", segs=8, rings=4, col=white)  # the shoulder
	limb(mb, [Vector((0, 0, 0)), elbow], [0.056, 0.047], "Suit", white, segs=6, caps=False)
	limb(mb, [elbow, wrist], [0.047, 0.037], "Suit", white, segs=6, caps=False)
	ellipsoid(mb, elbow, (0.05, 0.05, 0.05), "Suit", segs=6, rings=3, col=white)
	# the glove: a short fat fist round the rim, with a darker cuff
	fist = wrist + Vector((0.0, 0.98, 0.20)).normalized() * 0.01
	limb(mb, [fist, glove + Vector((0.0, 0.01, 0.0))], [0.043, 0.047], "Suit", DARK, segs=6)
	return mb, elbow, glove


# ---------------------------------------------------------------- the steering wheel (origin at the hub)
def build_wheel():
	mb = MB()
	n_ring, n_tube = 18, 5
	R, r = WHEEL_R, 0.0155
	rim = []
	for k in range(n_ring):
		a = 2 * math.pi * k / n_ring
		centre = Vector((R * math.cos(a), 0.0, R * math.sin(a)))
		radial = centre.normalized()
		ring = []
		for m in range(n_tube):
			b = 2 * math.pi * m / n_tube
			ring.append(centre + radial * (r * math.cos(b)) + Vector((0, 1, 0)) * (r * math.sin(b)))
		rim.append(ring)
	grey = GREY
	top = (0.8, 0.62, 0.02)  # a yellow marker at 12 o'clock, so the turning shows
	ids = []
	for k, ring in enumerate(rim):
		col = top if k == n_ring // 4 else grey
		ids.append([mb.vert(p, col) for p in ring])
	for k in range(n_ring):
		k2 = (k + 1) % n_ring
		for m in range(n_tube):
			m2 = (m + 1) % n_tube
			mid = (mb.v[ids[k][m]] + mb.v[ids[k2][m2]]) / 2
			cen = Vector((R * math.cos(2 * math.pi * (k + 0.5) / n_ring), 0, R * math.sin(2 * math.pi * (k + 0.5) / n_ring)))
			mb.face([ids[k][m], ids[k2][m], ids[k2][m2], ids[k][m2]], "Wheel", lambda q, cen=cen: q - cen)
	# three spokes (left, right, down) and a hub boss
	for ang in (180.0, 0.0, 270.0):
		a = math.radians(ang)
		tip = Vector((math.cos(a), 0.0, math.sin(a))) * (R - 0.01)
		mb.beam(Vector((0, 0, 0)), tip, 0.026, 0.014, "Wheel", up=(0, 1, 0), col=grey)
	mb.disc(Vector((0, -0.012, 0)), 0.048, "Wheel", normal=(0, -1, 0), segs=12, col=grey)
	mb.tube(Vector((0, -0.012, 0)), Vector((0, 0.04, 0)), 0.045, "Wheel", segs=10, caps=False, col=grey)
	return mb


PIECES = ["DriverBody", "DriverHead", "DriverArmL", "DriverArmR", "SteeringWheel"]


def build():
	"""{name: (MB, pivot)}: each mesh is in its pivot's frame, the pivot in the driver frame (origin the hip)."""
	armL, _, _ = build_arm(-1)
	armR, _, _ = build_arm(1)
	return {
		"DriverBody": (build_body(), Vector((0, 0, 0))),
		"DriverHead": (build_head(), NECK),
		"DriverArmL": (armL, SHOULDER[-1]),
		"DriverArmR": (armR, SHOULDER[1]),
		"SteeringWheel": (build_wheel(), HIP + Vector((-0.02, 0.50, 0.40))),  # a stand-in position: the car's own hub replaces it
	}


def vec3(text):
	return Vector(tuple(float(t) for t in text.split(",")))


def main():
	bpy.ops.object.select_all(action="SELECT")
	bpy.ops.object.delete(use_global=False)
	pieces = build()
	objects = {}
	total = 0
	for name, (mb, pivot) in pieces.items():
		ob = mb.emit(name, sharp_deg=50)
		ob.location = pivot
		objects[name] = ob
		t = mb.tris()
		total += t
		print("%-14s %5d tris" % (name, t))
	print("total          %5d tris" % total)
	kit.export_glb(OUT_GLB, list(objects.values()), texcoords=False)
	if kit.arg("--blend"):
		bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(kit.arg("--blend")))
	out = kit.arg("--renders")
	if not out:
		return
	cam = kit.setup_preview(size=(1000, 800), ground=6.0, ground_colour=(0.3, 0.3, 0.3))
	suit = kit.arg("--suit") or "#e8c500"
	helmet = kit.arg("--helmet") or "#f4f4f4"
	for nm, hexc in (("Suit", suit), ("Helmet", helmet)):
		tint = bpy.data.materials[nm].node_tree.nodes["Tint"]
		next(s for s in tint.inputs if s.identifier == "A_Color").default_value = (*srgb(hexc), 1)
	car = kit.arg("--car")
	seat = vec3(kit.arg("--seat")) if kit.arg("--seat") else None
	if car:
		render_in_car(cam, out, objects, car, seat, vec3(kit.arg("--wheel")), float(kit.arg("--scale") or 1.0),
			float(kit.arg("--rake") or 22.0), float(kit.arg("--turn") or 0.0), float(kit.arg("--yaw") or 0.0))
	else:
		render_alone(cam, out, objects)


def arm_rest(side):
	"""Where the glove's centre sits relative to the shoulder in the arm mesh (the aim line the visual turns at the hand)."""
	return Vector((side * 0.03, 0.478, -0.185))


def pose_arm(ob, side, shoulder, target):
	"""Turns an arm object about its shoulder so its glove reaches the target, scaled to the distance."""
	d = target - shoulder
	rest = arm_rest(side)
	ob.location = shoulder
	ob.rotation_mode = "QUATERNION"
	ob.rotation_quaternion = rest.rotation_difference(d)
	k = d.length / rest.length
	ob.scale = (k, k, k)


def render_alone(cam, out, objects):
	wheel_pos = HIP + Vector((-0.02, 0.52, 0.42))
	wheel = objects["SteeringWheel"]
	wheel.location = wheel_pos
	wheel.rotation_euler = (math.radians(-22), 0, 0)  # the face back and up
	bpy.context.view_layer.update()
	for side, key in ((-1, "DriverArmL"), (1, "DriverArmR")):
		rim = wheel.matrix_world.to_3x3() @ Vector((side * WHEEL_R, 0, 0))
		pose_arm(objects[key], side, SHOULDER[side], wheel_pos + rim)
	# a seat to sit on, for the eye
	seat = bpy.data.meshes.new("Seat")
	seat.from_pydata([(-0.3, -0.2, -0.02), (0.3, -0.2, -0.02), (0.3, 0.3, -0.02), (-0.3, 0.3, -0.02)], [], [(0, 1, 2, 3)])
	sob = bpy.data.objects.new("Seat", seat)
	bpy.context.scene.collection.objects.link(sob)
	views = {"side": ((3.2, 0.3, 0.6), (0, 0.3, 0.5)), "front": ((0.0, 3.2, 0.9), (0, 0, 0.45)), "q34": ((1.6, 2.1, 1.3), (0, 0.2, 0.45)),
		"back34": ((-1.5, -1.8, 1.3), (0, 0.2, 0.45)), "top": ((0.0, 0.3, 3.4), (0, 0.3, 0.0))}
	for name, (eye, target) in views.items():
		kit.render(cam, os.path.join(out, "driver_%s.png" % name), eye, target, 28.0)


def render_in_car(cam, out, objects, car, seat, hub, scale, rake, turn, yaw):
	"""The driver in a car's GLB (imported, Godot frame -> Blender), seat/hub in the visual's (Godot) frame."""
	before = set(bpy.data.objects)
	bpy.ops.import_scene.gltf(filepath=os.path.abspath(car))
	car_obs = [o for o in bpy.data.objects if o not in before]

	def g(v):  # Godot (x, y, z) -> Blender (x, -z, y)
		return Vector((v.x, -v.z, v.y))
	h = g(seat)
	hub_b = g(hub)
	for k, ob in objects.items():
		ob.hide_render = True
	vis = {}
	for k, ob in objects.items():
		d = bpy.data.objects.new(k + ".view", ob.data)
		bpy.context.scene.collection.objects.link(d)
		vis[k] = d
	body = vis["DriverBody"]
	body.location = h
	body.scale = (scale,) * 3
	head = vis["DriverHead"]
	head.location = h + NECK * scale
	head.scale = (scale,) * 3
	head.rotation_euler = (0, 0, math.radians(-yaw))
	wheel = vis["SteeringWheel"]
	wheel.location = hub_b
	ang = math.radians(turn)
	from mathutils import Matrix
	rake_m = Matrix.Rotation(math.radians(-rake), 3, "X")
	spin = Matrix.Rotation(ang, 3, "Y")
	wheel.matrix_world = Matrix.Translation(hub_b) @ (rake_m @ spin).to_4x4()
	for side, key in ((-1, "DriverArmL"), (1, "DriverArmR")):
		rim = (rake_m @ spin) @ Vector((side * WHEEL_R, 0, 0))
		sh = h + (SHOULDER[side] * scale)
		pose_arm(vis[key], side, sh, hub_b + rim)
	for o in car_obs:
		n = o.name.split(".")[0]
		if n in ("Body", "Windscreen", "WindowL", "WindowR", "RearWindow") or n.startswith(("Door", "Bonnet", "Bumper", "Boot")):
			o.hide_render = False
		if n in ("Martini", "Abarth", "Marlboro", "Stripes"):
			o.hide_render = True
	cutaway = "--cutaway" in sys.argv
	if cutaway:
		for o in car_obs:
			n = o.name.split(".")[0]
			if n in ("Body", "DoorL", "WindowL", "DoorR", "WindowR", "Windscreen", "RearWindow", "Stripes", "Martini", "Abarth", "Marlboro", "Details") or n.startswith(("DoorL", "DoorR")):
				o.hide_render = True
	cx, cy, cz = h.x, h.y, h.z
	views = {"side_l": ((cx - 3.0, cy, cz + 0.4), (cx, cy, cz + 0.4)), "q34_l": ((cx - 2.6, cy - 2.6, cz + 1.2), (cx, cy, cz + 0.45)),
		"behind": ((0.0, cy - 3.0, cz + 0.9), (cx * 0.5, cy, cz + 0.4)), "top": ((cx, cy + 0.2, cz + 2.6), (cx, cy + 0.2, cz)),
		"front_in": ((cx + 0.2, cy + 1.7, cz + 0.55), (cx, cy, cz + 0.4))}
	tag = os.path.splitext(os.path.basename(car))[0]
	for name, (eye, target) in views.items():
		kit.render(cam, os.path.join(out, "%s_%s%s.png" % (tag, name, "_cut" if cutaway else "")), eye, target, 38.0)


if __name__ == "__main__":
	main()
