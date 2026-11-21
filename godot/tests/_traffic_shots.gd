## Windowed probe: daylight screenshots of the real-model traffic and parked cars on Brzeszcze streets,
## plus open-world render/perf stats (draws, objects, primitives, frame ms).
##   godot --path godot --audio-driver Dummy --always-on-top -s tests/_traffic_shots.gd -- [out dir]
extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp/traffic_shots"
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	root.size = Vector2i(1440, 810)

	var ow := OpenWorld.new()
	root.add_child(ow)
	await ow.open("industrial_sprint")
	ow.hour = 13.5
	ow.active = true
	ow.snap_camera()

	# Count parked-car MultiMesh cells and instances + traffic model tri counts.
	var parked_mmi := 0
	var parked_insts := 0
	var parked_tris := 0
	var props := ow.world.get_node_or_null("Props")
	if props:
		for c in props.get_children():
			if c is MultiMeshInstance3D and String(c.name).begins_with("Parked"):
				var mm := (c as MultiMeshInstance3D).multimesh
				parked_mmi += 1
				parked_insts += mm.instance_count
				parked_tris += mm.instance_count * _mesh_tris(mm.mesh)
	print("PARKED: %d MultiMesh cells, %d instances, %dk total tris across map" % [parked_mmi, parked_insts, parked_tris / 1000])
	for kind in Traffic.KINDS:
		var mx: Array = ow.builder._model(kind, TownBuilder._fallback_car.bind(kind))
		var m: Mesh = mx[0]
		print("MODEL %-12s tris=%5d  surfaces=%d  loaded=%s" % [kind, _mesh_tris(m), m.get_surface_count(), str(ow.builder.has_model(kind))])

	# Step traffic for ~180 frames on ul. Dworcowa so ambient traffic populates around the player.
	for i in 120:
		ow.hour = 13.5
		await process_frame

	# Measure live open-world frame cost on ul. Dworcowa with real traffic & parked cars.
	var ft := PackedFloat64Array()
	for i in 60:
		var t0 := Time.get_ticks_usec()
		ow.hour = 13.5
		await RenderingServer.frame_post_draw
		ft.append((Time.get_ticks_usec() - t0) / 1000.0)
	ft.sort()
	print("PERF dworcowa: med %.2f ms  p95 %.2f ms  draws %d  objs %d  prims %dk  traffic_cars %d" % [
		ft[ft.size() / 2], ft[int(ft.size() * 0.95)],
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)) / 1000,
		ow.traffic.cars.size()])

	# Shot 1: Close-up of a live traffic car driving down a Brzeszcze street in daylight.
	var picked: Dictionary = {}
	var p_pos := Vector2(ow.drive.car.x, ow.drive.car.y)
	var best_d := INF
	for c in ow.traffic.cars:
		var d := (c.pos as Vector2).distance_to(p_pos)
		if d < best_d and float(c.v) > 2.0:
			best_d = d
			picked = c
	if not picked.is_empty():
		ow.active = false
		var cn := picked.node as Node3D
		var cp := cn.global_position
		var fwd := -cn.global_transform.basis.z
		var right := cn.global_transform.basis.x
		ow.camera.position = cp + fwd * 5.8 + right * 3.4 + Vector3.UP * 1.9
		ow.camera.look_at(cp + Vector3.UP * 0.75, Vector3.UP)
		ow.camera.fov = 46.0
		await _snap(out, "live_traffic_front")

	# Shot 2: Residential street with naturally parked cars (find the densest parked-car cluster).
	var best_pt := Vector3.ZERO
	var best_n := 0
	var parked_pts: Array[Vector3] = []
	if props:
		for c in props.get_children():
			if c is MultiMeshInstance3D and String(c.name).begins_with("Parked"):
				var mm := (c as MultiMeshInstance3D).multimesh
				for k in mm.instance_count:
					parked_pts.append(mm.get_instance_transform(k).origin)
	for p in parked_pts:
		var n := 0
		for q in parked_pts:
			if p.distance_squared_to(q) < 400.0:
				n += 1
		if n > best_n:
			best_n = n
			best_pt = p
	if best_n > 0:
		var near := ow.map.nearest_road(Vector2(best_pt.x, best_pt.z), 30.0)
		var dir2: Vector2 = near.dir if not near.is_empty() else Vector2(1, 0)
		var road_c := Vector3(near.pos.x, best_pt.y, near.pos.y) if not near.is_empty() else best_pt
		var f3 := Vector3(dir2.x, 0.0, dir2.y).normalized()
		var r3 := Vector3(-f3.z, 0.0, f3.x)
		ow.camera.position = road_c - f3 * 12.0 + r3 * 2.5 + Vector3.UP * 2.4
		ow.camera.look_at(best_pt + f3 * 6.0 + Vector3.UP * 0.8, Vector3.UP)
		ow.camera.fov = 52.0
		await _snap(out, "parked_street")

	# Shot 3 & 4: Full 10-car Polish street showcase parked in two tidy lanes on ul. Dworcowa (front 3/4 + rear 3/4).
	ow.traffic.clear()
	var spot: Array = ow.map.spots["industrial_sprint"]
	var base := Vector2(spot[0], spot[1])
	var h := float(spot[2])
	var fwd2 := Vector2(cos(h), sin(h))
	var side2 := Vector2(-fwd2.y, fwd2.x)
	var showcase := Node3D.new()
	ow.world.add_child(showcase)
	var centers: Array[Vector3] = []
	for i in Traffic.KINDS.size():
		var kind: String = Traffic.KINDS[i]
		var col: Color = Traffic.paint_palette(kind)[i % Traffic.paint_palette(kind).size()]
		var node := ow.traffic._car_node(kind, col)
		var row := i / 5
		var slot := i % 5
		var p2 := base + fwd2 * (14.0 + slot * 6.0) + side2 * (-2.1 + row * 4.2)
		var y := ow.map.ground(p2.x, p2.y) + ow.map.road_lift(0) + 0.04
		var hit := ow.map.road_at(p2.x, p2.y)
		if not hit.is_empty():
			y = float(hit.height)
		node.position = Vector3(p2.x, y, p2.y)
		node.basis = Basis(Vector3.UP, -h - PI / 2.0)
		showcase.add_child(node)
		centers.append(node.position)
	# Hide player car out of the showcase frame
	ow.drive.place(base - fwd2 * 40.0, h)
	var mid := Vector3.ZERO
	for v in centers:
		mid += v
	mid /= maxf(1.0, float(centers.size()))
	var f3 := Vector3(fwd2.x, 0.0, fwd2.y)
	var r3 := Vector3(side2.x, 0.0, side2.y)
	# Front 3/4 of all 10 cars
	ow.camera.position = mid + f3 * 22.0 + r3 * 8.5 + Vector3.UP * 3.8
	ow.camera.look_at(mid + Vector3.UP * 0.7, Vector3.UP)
	ow.camera.fov = 46.0
	await _snap(out, "lineup_dworcowa_front")
	# Rear 3/4 of all 10 cars
	ow.camera.position = mid - f3 * 22.0 - r3 * 8.5 + Vector3.UP * 3.8
	ow.camera.look_at(mid + Vector3.UP * 0.7, Vector3.UP)
	ow.camera.fov = 46.0
	await _snap(out, "lineup_dworcowa_rear")
	# Close street-level view of the front row (Golf4, Seicento, Focus, Van, Maluch)
	var c0 := centers[0] # Golf4
	var c9 := centers[9] # Maluch
	ow.camera.position = centers[8] + f3 * 7.5 + r3 * 5.0 + Vector3.UP * 2.0 # near Van & Maluch
	ow.camera.look_at((centers[8] + c9) * 0.5 + Vector3.UP * 0.85, Vector3.UP)
	ow.camera.fov = 44.0
	await _snap(out, "van_maluch_street")
	ow.camera.position = c0 + f3 * 6.5 - r3 * 4.5 + Vector3.UP * 1.7
	ow.camera.look_at((c0 + centers[1]) * 0.5 + Vector3.UP * 0.7, Vector3.UP)
	ow.camera.fov = 44.0
	await _snap(out, "golf_seicento_street")

	quit()

func _snap(out: String, name: String) -> void:
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := out.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("SAVED ", path)

static func _mesh_tris(m: Mesh) -> int:
	if m == null:
		return 0
	var total := 0
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		var idx = arr[Mesh.ARRAY_INDEX]
		if idx is PackedInt32Array and idx.size() > 0:
			total += idx.size() / 3
		elif arr[Mesh.ARRAY_VERTEX] is PackedVector3Array:
			total += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return total
