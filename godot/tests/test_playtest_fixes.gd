## Playtest fixes of 2026-11-22: the braking boards' digits are big and bold enough to read from far (models/furniture.glb,
## tools/blender/build_furniture.py), the street plate catches up at once after a teleport or respawn (OpenWorld.snap_camera),
## and the area banner steps aside for an overhead arch behind it (OpenWorld._update_area_hold, OpenWorldHud.set_area_hold).
## (The front number plate going with a dropped bumper is tests/test_car_panel_plates.gd.)
extends RefCounted

var completed := false
var errors: Array[String] = []

func check(ok: bool, what: String) -> void:
	if not ok:
		errors.append(what)

func run() -> Array:
	_boards()
	_banner_geometry()
	await _world()
	completed = true
	return errors

## A distance board is 1.5 m square (a real one is 1-1.5 m) and its three digits stand at least 0.55 m tall and span at
## least 0.95 m of the face (they were 0.62 m size in a thin face on a 1.3 m board: melted together beyond 40 m).
func _boards() -> void:
	var scene := load("res://models/furniture.glb") as PackedScene
	check(scene != null, "furniture.glb does not load")
	if scene == null:
		return
	var root := scene.instantiate()
	for label in ["100", "200", "300"]:
		var mi := root.find_child("BrakeBoard_" + label, true, false) as MeshInstance3D
		check(mi != null, "furniture.glb has no BrakeBoard_%s" % label)
		if mi == null:
			continue
		var mesh := mi.mesh
		var face := AABB()
		var digits := AABB()
		var have_face := false
		var have_digits := false
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s)
			var nm: String = m.resource_name if m else ""
			var v: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for p in v:
				if nm == "Board":
					face = face.expand(p) if have_face else AABB(p, Vector3.ZERO)
					have_face = true
				elif nm == "Black" and absf(p.x) < 0.6 and p.y > 0.98 and p.y < 2.32:
					digits = digits.expand(p) if have_digits else AABB(p, Vector3.ZERO)
					have_digits = true
		check(have_face and face.size.x >= 1.4 and face.size.x <= 1.6 and face.size.y >= 1.4 and face.size.y <= 1.6,
			"board %s: the face is %s m, not a 1.5 m square" % [label, face.size])
		check(have_digits and digits.size.y >= 0.55 and digits.size.x >= 0.95,
			"board %s: the digits are %s m, not at least 0.95 x 0.55" % [label, digits.size])
	root.free()

func _banner_geometry() -> void:
	var banner := Rect2(700.0, 170.0, 200.0, 60.0)
	check(OpenWorld.arch_behind_banner(banner, Vector2(800.0, 200.0), 60.0), "an arch right behind the banner was not seen as behind it")
	check(OpenWorld.arch_behind_banner(banner, Vector2(1000.0, 190.0), 80.0), "an arch whose lettering reaches the banner was not seen as behind it")
	check(not OpenWorld.arch_behind_banner(banner, Vector2(300.0, 200.0), 60.0), "an arch far to the side holds the banner")
	check(not OpenWorld.arch_behind_banner(banner, Vector2(800.0, 600.0), 60.0), "an arch low on the screen holds the banner")

func _world() -> void:
	var map := TownMap.load_map(OpenWorld.MAP_KEY)
	check(map != null, "the map did not load")
	if map == null:
		return
	var tree := Engine.get_main_loop() as SceneTree
	var ow := OpenWorld.new()
	ow.size = Vector2(1600, 900)
	tree.root.add_child(ow)
	await tree.process_frame
	ow.map = map
	ow.progress = WorldProgress.new()
	ow.world = Node3D.new()
	ow.add_child(ow.world)
	ow.builder = TownBuilder.new(map, ow.world)
	ow.drive = FreeCar.new(map)
	# two spots on streets of different names
	var spots := []
	var names := {}
	for k in map.spots:
		var sp: Array = map.spots[k]
		if sp.size() < 3:
			continue
		OpenWorld.spawn_car(ow.drive, map, Vector2(sp[0], sp[1]), float(sp[2]))
		if ow.drive.road.is_empty():
			continue
		var nm := OpenWorld.street_label(String(map.road_name[int(ow.drive.road.road)]))
		if nm != "" and not names.has(nm):
			names[nm] = true
			spots.append([Vector2(sp[0], sp[1]), float(sp[2]), nm])
	check(spots.size() >= 2, "fewer than two named streets among the map's spots")
	if spots.size() >= 2:
		for case in [0, 1, 0]:
			var s: Array = spots[case]
			OpenWorld.spawn_car(ow.drive, map, s[0], s[1])
			ow.snap_camera() # what every teleport, respawn and event reset does next
			check(ow.hud.street_label.text == String(OpenWorld.street_label(String(map.road_name[int(ow.drive.road.road)]))).to_upper(),
				"after moving the car the street plate says '%s', not the street it is on" % ow.hud.street_label.text)
		check(ow._area_t == 0.0, "the area check was not brought forward by a teleport")
	# the HUD hides the banner while a hold is on and brings it back, leaving its own fade alone
	var hud := ow.hud
	hud.show_area("Szczotki")
	for i in 5:
		hud.update_drive(0.0, 1, 1000.0, 8000.0, Vector2.ZERO, 0.0, 0.1)
	var shown := hud.area_label.modulate.a
	check(shown > 0.5 and hud.area_label.self_modulate.a > 0.99, "the area banner is not up after show_area (%.2f)" % shown)
	hud.set_area_hold(true)
	for i in 5:
		hud.update_drive(0.0, 1, 1000.0, 8000.0, Vector2.ZERO, 0.0, 0.1)
	check(hud.area_label.self_modulate.a < 0.05, "a held banner still shows (%.2f)" % hud.area_label.self_modulate.a)
	check(hud.area_label.modulate.a > 0.0, "a held banner lost its own fade (layout reads it)")
	hud.set_area_hold(false)
	for i in 5:
		hud.update_drive(0.0, 1, 1000.0, 8000.0, Vector2.ZERO, 0.0, 0.1)
	check(hud.area_label.self_modulate.a > 0.99, "the banner did not come back after the hold")
	# the arch scan finds the festival's arch MultiMeshes by name
	var fest := Node3D.new()
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "InflatableArches"
	mmi.multimesh = MultiMesh.new()
	mmi.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	mmi.multimesh.mesh = BoxMesh.new()
	mmi.multimesh.instance_count = 3
	fest.add_child(mmi)
	var other := MultiMeshInstance3D.new()
	other.name = "SpectatorsStand"
	other.multimesh = MultiMesh.new()
	other.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	other.multimesh.mesh = BoxMesh.new()
	other.multimesh.instance_count = 5
	fest.add_child(other)
	ow.add_child(fest)
	ow._arch_pts.clear()
	ow._collect_arches(fest, 0)
	check(ow._arch_pts.size() == 3, "the arch scan found %d points for 3 arches (and some spectators)" % ow._arch_pts.size())
	ow.queue_free()
