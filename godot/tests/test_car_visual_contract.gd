## The Seicento model and its RaceCarVisual (TASKS.md Phase 0 item 9): the model keeps the surfaces the visual overrides,
## the number plates are white (not tinted), the decal atlas is set and each decal quad lies on the body, and per-car
## tint (paint, stripes, tail lamps, damage) never leaks into the shared meshes or into another car.
## Run through tests/run_qa.gd (not yet listed in run_tests.gd's SUITES).
extends RefCounted

var completed := false
var errors: Array[String] = []

const VISUAL := preload("res://scripts/ui/race_car_visual.gd")

## mesh object -> material names its surfaces must carry (as the visual looks them up with _surface())
const SURFACES := {
	"Body": ["Paint", "Glass"],
	"Details": ["Plate", "Taillight", "Headlight", "LampGlass", "TailGlass", "TailBulb"],
}

func check(ok: bool, what: String) -> void:
	if not ok:
		errors.append(what)

func run() -> Array:
	var parent := Node3D.new()
	Engine.get_main_loop().root.add_child(parent)
	_model()
	_atlas()
	_instances(parent)
	_tint_isolation(parent)
	parent.free()
	completed = true
	return errors

func _surface_names(mesh: Mesh) -> Array:
	var out := []
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i)
		out.append(m.resource_name if m else "")
	return out

## A fresh copy of the model, since the game swaps materials on the cached shared meshes.
func _fresh_meshes() -> Dictionary:
	var scene := ResourceLoader.load(VISUAL.MODEL_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var meshes := {}
	if scene == null:
		errors.append("%s does not load" % VISUAL.MODEL_PATH)
		return meshes
	var root := scene.instantiate()
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		meshes[String(mi.name).split(".")[0]] = (mi as MeshInstance3D).mesh
	root.free()
	return meshes

func _model() -> void:
	var meshes := _fresh_meshes()
	for obj in ["Body", "Details", "Stripes", "Wheel", "Cabin"] + VISUAL.LIVERY_MESHES.values():
		check(meshes.has(obj), "seicento.glb lacks mesh object '%s'" % obj)
	for obj in SURFACES:
		if not meshes.has(obj):
			continue
		var names := _surface_names(meshes[obj])
		for want in SURFACES[obj]:
			check(want in names, "seicento.glb/%s lacks a '%s' surface (has %s)" % [obj, want, names])
		var dupes := {}
		for n in names:
			dupes[n] = int(dupes.get(n, 0)) + 1
		for n in dupes:
			check(n == "" or dupes[n] == 1, "seicento.glb/%s has %d surfaces named '%s'; _surface() would pick only the first" % [obj, dupes[n], n])
	# the plates stay plain white paper-ish: a tint on them (the menu's lavender) would come from code, not the model
	if meshes.has("Details"):
		var s := VISUAL._surface(meshes["Details"], "Plate")
		if s >= 0:
			var m := meshes["Details"].surface_get_material(s) as BaseMaterial3D
			if m:
				check(m.albedo_color.s < 0.12 and m.albedo_color.v > 0.8, "the Plate material is %s, not white" % m.albedo_color)
	# the paint surface is the only one the visual tints per car; it must not be the glass or the plate
	if meshes.has("Body"):
		var names := _surface_names(meshes["Body"])
		var ps := names.find("Paint")
		check(ps >= 0 and ps != names.find("Plate") and ps != names.find("Glass"), "Paint surface index clashes with another slot")
	# dent blend shapes the visual animates exist on every mesh it drives
	for obj in ["Body", "Details", "Stripes"]:
		if not meshes.has(obj):
			continue
		var found := false
		for i in meshes[obj].get_blend_shape_count():
			if String(meshes[obj].get_blend_shape_name(i)).begins_with("dent_"):
				found = true
		check(found, "seicento.glb/%s has no dent_* blend shapes" % obj)

func _atlas() -> void:
	var tex := load(VISUAL.DECALS_TEX_PATH) as Texture2D
	check(tex != null, "%s does not load" % VISUAL.DECALS_TEX_PATH)
	if tex == null:
		return
	var img := tex.get_image()
	if img == null or img.is_empty():
		errors.append("decal atlas has no readable image")
		return
	check(img.get_width() == img.get_height(), "decal atlas is %dx%d, expected square" % [img.get_width(), img.get_height()])
	check(img.get_width() >= 512, "decal atlas is only %d px wide" % img.get_width())
	# every cell the visual maps must hold printed (non-transparent) texels
	var cells := {}
	for i in 16:
		cells["door %d" % i] = Rect2(float(i % 4) * 0.125, float(i / 4) * 0.125, 0.125, 0.125)
	for v in 4:
		cells["hood %d" % v] = Rect2(0.5 + float(v % 2) * 0.25, float(v / 2) * 0.25, 0.25, 0.25)
		cells["sunstrip %d" % v] = Rect2(0.22, 0.5 + float(v) * 0.0625, 0.56, 0.0625)
		cells["sill %d" % v] = Rect2(float(v % 2) * 0.5, 0.75 + float(v / 2) * 0.125, 0.5, 0.125)
	var keys := cells.keys()
	for k in keys:
		var r: Rect2 = cells[k]
		check(Rect2(0, 0, 1, 1).encloses(r), "decal cell '%s' %s leaves the atlas" % [k, r])
		var solid := 0
		var total := 0
		for sy in 12:
			for sx in 12:
				var px := int((r.position.x + r.size.x * (float(sx) + 0.5) / 12.0) * img.get_width())
				var py := int((r.position.y + r.size.y * (float(sy) + 0.5) / 12.0) * img.get_height())
				total += 1
				if img.get_pixel(px, py).a > 0.1:
					solid += 1
		check(solid >= 4, "decal cell '%s' is empty in the atlas (%d of %d samples opaque)" % [k, solid, total])
	# the families must not overlap each other, or two decals would print each other's artwork
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			var a := keys[i] as String
			var b := keys[j] as String
			if a.split(" ")[0] == b.split(" ")[0]:
				continue
			check(not (cells[a] as Rect2).grow(-0.0005).intersects(cells[b]), "atlas cells '%s' and '%s' overlap" % [a, b])

func _instances(parent: Node3D) -> void:
	var car: Node3D = VISUAL.new()
	car.car_number = 7
	parent.add_child(car)
	var mat: StandardMaterial3D = VISUAL._decal_material()
	check(mat.albedo_texture != null, "the shared decal material has no albedo texture")
	check(mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "the decal material is not alpha-blended")
	var decals := {}
	for n in ["DoorDecalL", "DoorDecalR", "Sunstrip", "HoodDecal", "SillDecalL", "SillDecalR"]:
		var d := car.body_pivot.get_node_or_null(n) as MeshInstance3D
		check(d != null, "visual lacks decal node %s" % n)
		if d == null:
			continue
		decals[n] = d
		check(d.mesh != null, "%s has no mesh" % n)
		check(d.material_override == mat, "%s does not use the shared decal material" % n)
		check(d.visible, "%s is hidden on a default car" % n)
	var body: Mesh = VISUAL._shared_resources().shell
	var tri := body.generate_triangle_mesh()
	check(tri != null, "the Body mesh gives no triangle mesh to ray-test decals against")
	if tri != null:
		for n in decals:
			var d: MeshInstance3D = decals[n]
			var normal := d.transform.basis.z.normalized()
			var hit := tri.intersect_ray(d.position + normal * 0.3, -normal)
			if hit.is_empty():
				errors.append("%s: no body surface under the decal (re-measure its point in race_car_visual.gd)" % n)
				continue
			var gap := (d.position - (hit.position as Vector3)).dot(normal)
			print("    decal %-10s sits %.1f mm off the body" % [n, gap * 1000.0])
			check(absf(gap - 0.0) < 0.012, "%s floats %.1f mm off the body (expected ~0 within 12 mm)" % [n, gap * 1000.0])
			check(gap > -0.002, "%s is sunk %.1f mm into the body and would z-fight" % [n, -gap * 1000.0])
			check(normal.dot(hit.normal) > 0.9, "%s faces %s but the body there faces %s" % [n, normal, hit.normal])
	# hood decal: on the bonnet, reading from behind, left-right centred
	var hood := decals.get("HoodDecal") as MeshInstance3D
	if hood != null:
		check(absf(hood.position.x) < 0.01, "the hood decal is off the centre line (x=%.3f)" % hood.position.x)
		check(hood.position.z < -0.9 and hood.position.y > 0.6, "the hood decal is not on the bonnet at %s" % hood.position)
		check(hood.transform.basis.z.y > 0.8, "the hood decal does not face up")
	# the surface slots the visual overrides per car
	var sh := VISUAL._shared_resources()
	check(car._shell.get_surface_override_material(sh.paint_surface) == car.paint_material, "the Paint slot is not this car's paint material")
	check(car._details_node.get_surface_override_material(sh.tail_surface) == car.tail_material, "the Taillight slot is not this car's tail material")
	if sh.bulb_surface >= 0:
		check(car._details_node.get_surface_override_material(sh.bulb_surface) == car.bulb_material, "the TailBulb slot is not this car's bulb material")
	check(sh.paint_surface != sh.tail_surface or car._shell.mesh != car._details_node.mesh, "paint and tail slots coincide")
	# the visual's own Wheel and Cabin nodes
	check(car.wheels.size() == 4 and car.steer_pivots.size() == 4, "the car does not have four wheels")
	car.free()

func _tint_isolation(parent: Node3D) -> void:
	var sh := VISUAL._shared_resources()
	var shared_paint: StandardMaterial3D = sh.shell.surface_get_material(sh.paint_surface) as StandardMaterial3D
	var before_shared: Color = shared_paint.albedo_color if shared_paint else Color.BLACK
	var a: Node3D = VISUAL.new()
	var b: Node3D = VISUAL.new()
	a.car_number = 3
	b.car_number = 9
	parent.add_child(a)
	parent.add_child(b)
	a.set_paint(Color("#c01818"))
	b.set_paint(Color("#1a4fd0"))
	check(a.paint_material != b.paint_material, "two cars share one paint material")
	check(a.stripe_material != b.stripe_material, "two cars share one stripe material")
	check(a.tail_material != b.tail_material, "two cars share one tail-lamp material")
	check(a.bulb_material != b.bulb_material, "two cars share one bulb material")
	check(a.paint_material.albedo_color.is_equal_approx(Color("#c01818")), "car A's paint is %s, not its own red" % a.paint_material.albedo_color)
	check(b.paint_material.albedo_color.is_equal_approx(Color("#1a4fd0")), "car B's paint is %s, not its own blue" % b.paint_material.albedo_color)
	if shared_paint:
		check(shared_paint.albedo_color == before_shared, "set_paint changed the shared mesh's Paint material to %s" % shared_paint.albedo_color)
	# damage, stripes and the safety car dressing stay on their own car
	a._damage_shown = 1.0
	a._apply_paint()
	check(b.paint_material.clearcoat == 1.0 and b.paint_material.albedo_color.is_equal_approx(Color("#1a4fd0")), "car A's damage dulled car B's paint")
	check(float(a._shell.get_instance_shader_parameter("coat")) != float(b._shell.get_instance_shader_parameter("coat")), "the clear-coat strength is not per car (instance uniform shared)")
	var b_stripe: Color = b.stripe_material.albedo_color
	a.make_safety_car()
	check(b.stripe_material.albedo_color == b_stripe, "dressing car A as the safety car changed car B's stripes")
	check(b.number_label.text == "9", "car B's roof number reads '%s'" % b.number_label.text)
	# liveries: A in Abarth, B stays plain
	a.set_livery(3)
	check(not (b.livery_nodes[3] as MeshInstance3D).visible, "car A's livery shows on car B")
	check(b.livery == 0, "car B's livery changed to %d" % b.livery)
	# distinct door numbers print distinct cells
	check(a._door_decal_l.mesh != b._door_decal_l.mesh, "cars 3 and 9 print the same door-number quad")
	# ghosts fade their own paint only
	b._ghost = true
	b._apply_paint()
	check(b.paint_material.albedo_color.a < 1.0 and a.paint_material.albedo_color.a == 1.0, "ghost alpha did not stay on its own car")
	# the shared glass, headlight, lens and livery materials are the model's, same object on both cars
	check(a._shell.mesh == b._shell.mesh and a._details_node.mesh == b._details_node.mesh, "cars do not share the body and detail meshes")
	a.free()
	b.free()
