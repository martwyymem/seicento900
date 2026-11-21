## Headless: what the race world would draw from the grid of TRACK (default goliath): per group, mesh instances in
## draw range (visibility_range_end, or unlimited), draw-call surfaces and triangles (MultiMesh: instances × mesh).
## QUALITY (0-3) is applied before the track is built.
##   TRACK=goliath godot --headless --path godot -s tests/_scene_cost_probe.gd
extends SceneTree

func _tris(m: Mesh) -> int:
	var t := 0
	if m == null:
		return 0
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		var idx = a[Mesh.ARRAY_INDEX]
		t += (idx.size() if idx != null and idx.size() > 0 else a[Mesh.ARRAY_VERTEX].size()) / 3
	return t

func _initialize() -> void:
	var key := OS.get_environment("TRACK") if OS.get_environment("TRACK") != "" else "goliath"
	var world = load("res://ui/race_world.tscn").instantiate()
	root.add_child(world)
	await process_frame
	var rs := RaceSettings.new()
	rs.track = key
	rs.opponents = 11
	var race := Race.new(rs)
	if OS.get_environment("QUALITY") != "":
		world.apply_graphics(int(OS.get_environment("QUALITY")))
	world.set_race(race)
	for i in 5:
		await process_frame
	var player = race.cars[0]
	var cam := Vector3(player.x - world.world_center.x, 2.0, player.y - world.world_center.y)
	var groups := {}
	var depth := int(OS.get_environment("DEPTH")) if OS.get_environment("DEPTH") != "" else 4
	var cache := {}
	for g: GeometryInstance3D in world.find_children("*", "GeometryInstance3D", true, false):
		if not g.is_visible_in_tree():
			continue
		var d := (g.global_transform * g.get_aabb()).get_center().distance_to(cam) # what visibility ranges measure
		var mesh: Mesh = null
		var count := 1
		if g is MeshInstance3D:
			mesh = (g as MeshInstance3D).mesh
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh:
			mesh = (g as MultiMeshInstance3D).multimesh.mesh
			count = (g as MultiMeshInstance3D).multimesh.visible_instance_count
			if count < 0:
				count = (g as MultiMeshInstance3D).multimesh.instance_count
		if g.visibility_range_end > 0.0 and d > g.visibility_range_end + g.visibility_range_end_margin:
			continue
		if mesh == null:
			continue
		if not cache.has(mesh):
			cache[mesh] = _tris(mesh)
		var parts := String(world.get_path_to(g)).split("/")
		var k := "/".join(parts.slice(0, mini(depth, parts.size() - 1)))
		var e: Array = groups.get(k, [0, 0, 0, 0])
		e[0] += 1
		e[1] += mesh.get_surface_count() * (2 if g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF else 1)
		e[2] += int(cache[mesh]) * count
		e[3] += 1 if g.visibility_range_end <= 0.0 else 0
		groups[k] = e
	var ks := groups.keys()
	ks.sort_custom(func(a, b): return groups[a][2] > groups[b][2])
	print("TRACK ", key, "  (instances in range, surfaces x passes, triangles, no range)")
	for k in ks.slice(0, 25):
		print("  %6d  %6d  %10d  %5d  %s" % [groups[k][0], groups[k][1], groups[k][2], groups[k][3], k])
	quit()
