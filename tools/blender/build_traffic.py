"""Builds low-poly traffic LODs of the game's real car models for the open world's traffic and parked cars.

Run from the repository root (Blender 4.2 or newer, headless):

    /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/blender/build_traffic.py -- [--renders DIR]

Imports each full-detail car GLB (godot/models/{seicento,golf4,logan,v50,i20,sandero,focus,zafira}.glb), strips
hidden interior / race-only geometry, consolidates materials to a compact traffic set (keeping Paint for per-car
tinting and Taillight for braking lights), decimates Body and Details cleanly, fits crisp low-poly 5-spoke alloy
wheels at each car's exact track and wheelbase, grounds and centres each model (~6.5-7.0k tris per car), and
writes godot/models/traffic_cars.glb (one root object per car).
"""
import bmesh
import bpy
import math
import os
import sys
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit  # noqa: E402
from kit import srgb  # noqa: E402

OUT_GLB = os.path.join(kit.ROOT, "godot", "models", "traffic_cars.glb")
MODELS_DIR = os.path.join(kit.ROOT, "godot", "models")

# (object name, source GLB, wheel_radius, tyre_width, wheelbase, half_track_front, half_track_rear, preview hex paint)
# Wheel positions match CarCatalog.*_VISUAL in godot/scripts/data/car_catalog.gd.
CARS = [
	("CarSeicento", "seicento.glb", 0.2665, 0.155, 2.200, 0.6315, 0.6315, "#b5121b"),
	("CarGolf4", "golf4.glb", 0.3172, 0.195, 2.511, 0.7565, 0.7470, "#1d2a5a"),
	("CarLogan", "logan.glb", 0.3108, 0.185, 2.630, 0.7330, 0.7280, "#a8acaf"),
	("CarV50", "v50.glb", 0.3160, 0.205, 2.640, 0.7675, 0.7655, "#24344f"),
	("CarI20", "i20.glb", 0.3015, 0.185, 2.525, 0.7525, 0.7515, "#cc1b22"),
	("CarSandero", "sandero.glb", 0.3100, 0.185, 2.588, 0.7400, 0.7345, "#eef0ee"),
	("CarFocus", "focus.glb", 0.3210, 0.215, 2.648, 0.7720, 0.7670, "#183c7a"),
	("CarZafira", "zafira.glb", 0.3160, 0.205, 2.703, 0.7440, 0.7550, "#6f7479"),
]

# Triangle budgets per sub-part (total ~6.8-7.4k tris per car: watertight panels, crisp lamps and clean round wheels).
BODY_TARGET_TRIS = 3300
DETAILS_TARGET_TRIS = 2400

# Compact shared traffic materials (9 surfaces, all opaque: zero alpha sorting cost, clean PBR).
# Alloy and DarkTrim avoid the names Steel/Trim so PropDetail doesn't rust alloy rims or chip plastic bumpers.
TRAFFIC_MATS = {
	"Paint": (srgb("#ffffff"), 0.28, 0.12, {"coat": 0.9}),
	"Glass": (srgb("#121a22"), 0.06, 0.30, {"coat": 0.85, "plain": True}),
	"Headlight": (srgb("#e4ecf4"), 0.08, 0.25, {"emit": ((1.0, 0.96, 0.88), 0.32), "plain": True}),
	"Taillight": (srgb("#8c0a0d"), 0.10, 0.00, {"emit": ((1.0, 0.04, 0.03), 0.22), "plain": True}),
	"Indicator": (srgb("#d4720c"), 0.14, 0.05, {"emit": ((1.0, 0.50, 0.05), 0.15), "plain": True}),
	"Alloy": (srgb("#b6bcc4"), 0.22, 0.78, {"plain": True}),
	"DarkTrim": (srgb("#1a1c20"), 0.58, 0.05, {"plain": True}),
	"Tyre": (srgb("#131416"), 0.85, 0.00, {"plain": True}),
	"Plate": (srgb("#eeefe9"), 0.45, 0.00, {"plain": True}),
}

# Materials stripped before decimation (hidden cabin liner, race-only gear, double-layered transparent lamp covers).
DROP_MATS = {
	"Interior", "Seat", "TowHook", "Harness", "Cage", "Yellow", "Fabric",
	"LampGlass", "TailBulb",
}

# Source GLB material base name -> traffic material name.
MAT_MAP = {
	"Paint": "Paint",
	"Glass": "Glass",
	"Headlight": "Headlight",
	"Fog": "Headlight",
	"LampClear": "Headlight",
	"Taillight": "Taillight",
	"TailGlass": "Taillight",
	"Indicator": "Indicator",
	"Rim": "Alloy",
	"Chrome": "Alloy",
	"Exhaust": "Alloy",
	"RoofRail": "Alloy",
	"Steel": "Alloy",
	"BrakeDisc": "Alloy",
	"LampBezel": "Alloy",  # silver reflector housing inside headlamps
	"Trim": "DarkTrim",
	"Bumper": "DarkTrim",
	"Gasket": "DarkTrim",
	"Grille": "DarkTrim",
	"Under": "DarkTrim",
	"BadgeBlue": "DarkTrim",
	"Tyre": "Tyre",
	"Sidewall": "Tyre",
	"Plate": "Plate",
}


def base_mat_name(mat):
	return mat.name.split(".")[0] if mat else ""


def ensure_traffic_materials():
	kit.MATERIALS.update(TRAFFIC_MATS)
	return {name: kit.material(name) for name in TRAFFIC_MATS}


def count_tris(mesh):
	return sum(len(p.vertices) - 2 for p in mesh.polygons)


def clean_and_remap(ob, mats, strip_side_plates=False):
	"""Apply transforms, strip shape keys and dropped-material faces, remap remaining faces to TRAFFIC_MATS."""
	me = ob.data
	if me.shape_keys:
		ob.shape_key_clear()

	xf = ob.matrix_world.copy()
	ob.matrix_world = Matrix.Identity(4)

	bm = bmesh.new()
	bm.from_mesh(me)
	bmesh.ops.transform(bm, matrix=xf, verts=bm.verts)

	src_names = [base_mat_name(m) for m in me.materials]
	target_order = list(TRAFFIC_MATS.keys())
	target_idx = {name: i for i, name in enumerate(target_order)}

	to_delete = []
	bezel_verts = set()
	for f in bm.faces:
		src = src_names[f.material_index] if f.material_index < len(src_names) else ""
		if src in DROP_MATS:
			to_delete.append(f)
			continue
		# Drop race door-number squares on the Seicento (real licence plates sit on the nose/tail at |x| < 0.45).
		if strip_side_plates and src == "Plate" and abs(f.calc_center_median().x) > 0.5:
			to_delete.append(f)
			continue
		if src == "LampBezel":
			for v in f.verts:
				bezel_verts.add(v)
		dst = MAT_MAP.get(src, "DarkTrim")
		f.material_index = target_idx[dst]

	if to_delete:
		bmesh.ops.delete(bm, geom=to_delete, context="FACES")

	# Nudge LampBezel slightly forward (+Y) so decimation never lets the curved fender poke through the bezel.
	if bezel_verts:
		for v in bezel_verts:
			if v.is_valid:
				v.co.y += 0.004

	loose_v = [v for v in bm.verts if not v.link_faces]
	if loose_v:
		bmesh.ops.delete(bm, geom=loose_v, context="VERTS")

	# Clean white vertex colour layer on every piece so Paint tints evenly with no smeared decimation seams.
	for layer in list(bm.loops.layers.color):
		bm.loops.layers.color.remove(layer)
	col_layer = bm.loops.layers.color.new("Col")
	for f in bm.faces:
		for loop in f.loops:
			loop[col_layer] = (1.0, 1.0, 1.0, 1.0)

	for uv in list(bm.loops.layers.uv):
		bm.loops.layers.uv.remove(uv)

	# Populate target material slots BEFORE bm.to_mesh so material_index stays intact (clear() resets indices to 0).
	me.materials.clear()
	for name in target_order:
		me.materials.append(mats[name])

	bm.to_mesh(me)
	bm.free()

	if me.color_attributes.get("Col"):
		me.color_attributes.active_color = me.color_attributes["Col"]
	me.update()


def build_wheel_object(name, radius, width, mats, segs=20, spokes=5):
	"""Build a crisp, round low-poly wheel (~360 tris) centred at origin with its outer face towards +X."""
	target_order = list(TRAFFIC_MATS.keys())
	target_idx = {m: i for i, m in enumerate(target_order)}
	i_rub = target_idx["Tyre"]
	i_all = target_idx["Alloy"]
	i_drk = target_idx["DarkTrim"]

	hw = width * 0.5
	r_rim = radius * 0.63
	r_sh = radius * 0.94  # tread shoulder radius
	r_hub = radius * 0.16

	# Cross-section revolved around the X axis: (x, r, material_index of strip to next ring)
	# Walks from inner rim lip -> inner sidewall -> tread -> outer sidewall -> outer rim lip -> recessed dish -> hub.
	prof = [
		(-hw * 0.85, r_rim, i_rub),
		(-hw, r_rim + (radius - r_rim) * 0.45, i_rub),
		(-hw * 0.90, r_sh, i_rub),
		(-hw * 0.65, radius, i_rub),
		(+hw * 0.65, radius, i_rub),
		(+hw * 0.90, r_sh, i_rub),
		(+hw, r_rim + (radius - r_rim) * 0.45, i_rub),
		(+hw * 0.85, r_rim, i_all),
		(+hw * 0.88, r_rim * 0.92, i_all),
		(+hw * 0.52, r_rim * 0.86, i_drk),
		(+hw * 0.48, r_hub, i_all),
		(+hw * 0.72, r_hub, i_all),
	]

	bm = bmesh.new()
	rings = []
	for x, r, _ in prof:
		ring = []
		for k in range(segs):
			a = 2.0 * math.pi * k / segs
			ring.append(bm.verts.new((x, r * math.cos(a), r * math.sin(a))))
		rings.append(ring)

	for i in range(len(prof) - 1):
		mat_i = prof[i][2]
		r0, r1 = rings[i], rings[i + 1]
		for k in range(segs):
			k2 = (k + 1) % segs
			f = bm.faces.new((r0[k], r0[k2], r1[k2], r1[k]))
			f.material_index = mat_i

	# Outer centre cap + inner dark back disc.
	c_out = bm.verts.new((+hw * 0.74, 0.0, 0.0))
	c_in = bm.verts.new((-hw * 0.85, 0.0, 0.0))
	for k in range(segs):
		k2 = (k + 1) % segs
		f_out = bm.faces.new((rings[-1][k], rings[-1][k2], c_out))
		f_out.material_index = i_all
		f_in = bm.faces.new((rings[0][k2], rings[0][k], c_in))
		f_in.material_index = i_drk

	# 5 crisp 3D alloy spokes from the hub out to the rim lip.
	sw0 = radius * 0.052
	sw1 = radius * 0.042
	r0_s = r_hub * 0.85
	r1_s = r_rim * 0.93
	x_back = hw * 0.52
	x_front = hw * 0.78
	for s in range(spokes):
		ang = 2.0 * math.pi * s / spokes + 0.15
		ca, sa = math.cos(ang), math.sin(ang)
		# radial u = (0, ca, sa), tangential v = (0, -sa, ca)
		def pt(x, r_pos, t_pos):
			return (x, r_pos * ca - t_pos * sa, r_pos * sa + t_pos * ca)
		vs = [
			bm.verts.new(pt(x_back, r0_s, -sw0)),
			bm.verts.new(pt(x_back, r0_s, +sw0)),
			bm.verts.new(pt(x_back, r1_s, +sw1)),
			bm.verts.new(pt(x_back, r1_s, -sw1)),
			bm.verts.new(pt(x_front, r0_s, -sw0 * 0.8)),
			bm.verts.new(pt(x_front, r0_s, +sw0 * 0.8)),
			bm.verts.new(pt(x_front, r1_s, +sw1 * 0.8)),
			bm.verts.new(pt(x_front, r1_s, -sw1 * 0.8)),
		]
		for quad in ((4, 5, 6, 7), (0, 4, 7, 3), (1, 2, 6, 5)):
			f = bm.faces.new([vs[j] for j in quad])
			f.material_index = i_all

	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	col_layer = bm.loops.layers.color.new("Col")
	for f in bm.faces:
		for loop in f.loops:
			loop[col_layer] = (1.0, 1.0, 1.0, 1.0)

	me = bpy.data.meshes.new(name)
	for mname in target_order:
		me.materials.append(mats[mname])
	bm.to_mesh(me)
	bm.free()
	if me.color_attributes.get("Col"):
		me.color_attributes.active_color = me.color_attributes["Col"]
	me.update()

	ob = bpy.data.objects.new(name, me)
	bpy.context.scene.collection.objects.link(ob)
	return ob


def decimate_object(ob, target_tris, symmetry=True):
	"""Collapse-decimate ob towards target_tris while respecting material boundaries."""
	tris = count_tris(ob.data)
	if tris <= target_tris or tris == 0:
		return
	ratio = max(0.03, min(1.0, float(target_tris) / float(tris)))
	mod = ob.modifiers.new("Decimate", "DECIMATE")
	mod.decimate_type = "COLLAPSE"
	mod.ratio = ratio
	mod.use_collapse_triangulate = True
	mod.delimit = {"MATERIAL"}
	if symmetry:
		mod.use_symmetry = True
		mod.symmetry_axis = "X"

	bpy.context.view_layer.objects.active = ob
	bpy.ops.object.select_all(action="DESELECT")
	ob.select_set(True)
	bpy.ops.object.modifier_apply(modifier=mod.name)


def build_car(name, glb_file, wheel_r, tyre_w, wheelbase, ht_f, ht_r, mats):
	"""Import one real car GLB, decimate Body + Details, add 4 crisp low-poly wheels, join and ground."""
	before = set(bpy.data.objects)
	path = os.path.join(MODELS_DIR, glb_file)
	bpy.ops.import_scene.gltf(filepath=path)
	imported = [ob for ob in bpy.data.objects if ob not in before]

	by_name = {}
	for ob in imported:
		if ob.type == "MESH":
			by_name[ob.name.split(".")[0]] = ob

	body = by_name["Body"]
	details = by_name["Details"]

	# Remove unused imported objects (Cabin, Stripes, liveries, high-poly Wheel, empties).
	keep_set = {body, details}
	for ob in imported:
		if ob not in keep_set:
			bpy.data.objects.remove(ob, do_unlink=True)

	clean_and_remap(body, mats)
	clean_and_remap(details, mats, strip_side_plates=(name == "CarSeicento"))

	decimate_object(body, BODY_TARGET_TRIS, symmetry=False)
	decimate_object(details, DETAILS_TARGET_TRIS, symmetry=False)

	# Build a clean procedural 5-spoke alloy wheel and place it at the 4 real axle corners.
	wheel = build_wheel_object(f"{name}_WheelSrc", wheel_r, tyre_w, mats)
	half_wb = wheelbase * 0.5
	wheel_spots = [
		(-ht_f, +half_wb, wheel_r, math.pi),
		(+ht_f, +half_wb, wheel_r, 0.0),
		(-ht_r, -half_wb, wheel_r, math.pi),
		(+ht_r, -half_wb, wheel_r, 0.0),
	]
	wheel_objs = []
	for i, (wx, wy, wz, rz) in enumerate(wheel_spots):
		me_copy = wheel.data.copy()
		wob = bpy.data.objects.new(f"{name}_W{i}", me_copy)
		bpy.context.scene.collection.objects.link(wob)
		wob.location = (wx, wy, wz)
		wob.rotation_euler = (0.0, 0.0, rz)
		wheel_objs.append(wob)
	bpy.data.objects.remove(wheel, do_unlink=True)

	# Join Body + Details + 4 wheels into one single mesh object.
	parts = [body, details] + wheel_objs
	bpy.ops.object.select_all(action="DESELECT")
	for ob in parts:
		ob.select_set(True)
	bpy.context.view_layer.objects.active = body
	bpy.ops.object.join()

	ob = body
	ob.name = name
	me = ob.data
	me.name = name

	# Ground (min z = 0) and centre in X and Y so collision and parking are symmetric around the origin.
	verts = [v.co for v in me.vertices]
	mn = Vector((min(p.x for p in verts), min(p.y for p in verts), min(p.z for p in verts)))
	mx = Vector((max(p.x for p in verts), max(p.y for p in verts), max(p.z for p in verts)))
	shift = Vector((-(mn.x + mx.x) * 0.5, -(mn.y + mx.y) * 0.5, -mn.z))
	for v in me.vertices:
		v.co += shift

	# Strip unused material slots so draw calls only cover materials actually present on this car.
	used_slots = sorted({p.material_index for p in me.polygons})
	if len(used_slots) < len(me.materials):
		remap = {old: new for new, old in enumerate(used_slots)}
		kept_mats = [me.materials[i] for i in used_slots]
		new_indices = [remap[p.material_index] for p in me.polygons]
		me.materials.clear()
		for m in kept_mats:
			me.materials.append(m)
		me.polygons.foreach_set("material_index", new_indices)

	if me.color_attributes.get("Col"):
		me.color_attributes.active_color = me.color_attributes["Col"]

	# Smooth shading with sharp panel edges.
	bpy.ops.object.select_all(action="DESELECT")
	ob.select_set(True)
	bpy.context.view_layer.objects.active = ob
	try:
		bpy.ops.mesh.customdata_custom_splitnormals_clear()
	except Exception:
		pass
	me.update()
	me.validate()
	me.shade_smooth()
	me.set_sharp_from_angle(angle=math.radians(42.0))

	size = mx - mn
	return ob, size


def preview_copy(ob, loc, rot=0.0, paint_hex="#c0182a"):
	d = kit.place(ob, loc, rot)
	me = ob.data.copy()
	for i, m in enumerate(me.materials):
		if m and m.name == "Paint":
			m2 = m.copy()
			tint = m2.node_tree.nodes.get("Tint")
			if tint:
				sock = {s.identifier: s for s in tint.inputs}
				sock["A_Color"].default_value = (*srgb(paint_hex), 1.0)
			else:
				bsdf = m2.node_tree.nodes.get("Principled BSDF")
				bsdf.inputs["Base Color"].default_value = (*srgb(paint_hex), 1.0)
			me.materials[i] = m2
	d.data = me
	return d


def main():
	bpy.ops.wm.read_factory_settings(use_empty=True)
	mats = ensure_traffic_materials()

	objs = {}
	total_tris = 0
	print("\ntraffic car      size (Godot X x Y(up) x Z) m      tris   mats")
	for name, glb, wr, tw, wb, htf, htr, _ in CARS:
		ob, size = build_car(name, glb, wr, tw, wb, htf, htr, mats)
		t = count_tris(ob.data)
		total_tris += t
		print(f"{name:16s} {size.x:6.2f} x {size.z:6.2f} x {size.y:6.2f}     {t:6d}   {len(ob.data.materials)}")
		objs[name] = ob
	print(f"{'TOTAL':16s} {'':30s} {total_tris:6d}")

	bpy.ops.outliner.orphans_purge(do_recursive=True)
	kit.export_glb(OUT_GLB, list(objs.values()), texcoords=False)

	out = kit.arg("--renders")
	if not out:
		return
	cam = kit.setup_preview(ground=300.0, ground_colour=(0.20, 0.22, 0.20))
	for ob in objs.values():
		ob.hide_render = True

	for k, (name, _, _, _, _, _, _, hex_col) in enumerate(CARS):
		row = k // 4
		col = k % 4
		x = -6.0 + col * 4.0
		y = row * 7.5
		preview_copy(objs[name], (x, y, 0.0), rot=0.0, paint_hex=hex_col)
		preview_copy(objs[name], (-14.0 + k * 4.0, 24.0, 0.0), rot=-math.pi / 2, paint_hex=hex_col)

	R = lambda f, e, t, fov=45: kit.render(cam, os.path.join(out, f), e, t, fov)  # noqa: E731
	R("lineup_front.png", (10.5, 16.5, 4.2), (0.0, 3.2, 0.65), 48)
	R("lineup_rear.png", (-10.5, -10.5, 4.2), (0.0, 3.8, 0.65), 48)
	R("golf4_close.png", (1.2, 4.2, 1.55), (-2.0, 0.0, 0.65), 40)
	R("focus_close.png", (5.2, 11.7, 1.55), (2.0, 7.5, 0.65), 40)


main()
