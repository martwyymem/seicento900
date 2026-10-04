## Scenery check (dev tool): builds a circuit and saves screenshots of its scenery.
## Env: TRACK (default gp), HOUR, OUT (directory), VIEWS (comma list):
##   pos:<x>;<y>[;<dist>;<height>] (a track point from the south-west), lm:<Name> (a landmark from its front), wall<S> (the first tyre wall after S metres), kerb (the kerb of the tightest bend), obj:<Name> (the first, or INDEX-th, of a furniture MultiMesh, from in front), stands, stands_near, stands_back, pits, pits_near, gantry, aerial, high, city, casino,
##   top<S> (from above the road at S metres), down<S> (straight down from 60 m), lap<N> (driver's-eye view N/8 of the way round the lap, e.g. lap3), at<S> (driver's eye at S metres)
##   godot --path godot -s tests/_scenery_shot.gd
extends SceneTree

func _initialize() -> void:
	var env := OS.get_environment
	var key: String = env.call("TRACK") if env.call("TRACK") != "" else "gp"
	var out: String = env.call("OUT") if env.call("OUT") != "" else "/tmp/seicento_scenery"
	var views: PackedStringArray = (env.call("VIEWS") if env.call("VIEWS") != "" else "stands,stands_near,pits,pits_near,gantry,aerial").split(",")
	root.size = Vector2i(1600, 900)
	var world = load("res://ui/race_world.tscn").instantiate()
	root.add_child(world)
	await process_frame
	var rs := RaceSettings.new()
	rs.track = key
	rs.opponents = int(env.call("OPP")) if env.call("OPP") != "" else 7
	if env.call("WEATHER") != "":
		rs.weather = env.call("WEATHER")
	rs.start_hour = float(env.call("HOUR")) if env.call("HOUR") != "" else 14.0
	var race := Race.new(rs)
	world.set_race(race)
	var inp := Race.PlayerInput.new()
	for f in 30:
		race.step(1.0 / 60.0, inp)
		await process_frame
	world.set_process(false)
	var tr: Track = world.track
	var cam: Camera3D = world.camera
	var ps := signf(tr.cfg.pit_offset)
	var ss: float = world._stands_side()
	var sm: float = (tr.cfg.stands.x + tr.cfg.stands.y) * 0.5
	var gs: Vector2 = world._garage_span()
	var gm := (gs.x + gs.y) * 0.5
	DirAccess.make_dir_recursive_absolute(out)
	for v in views:
		var eye := Vector3.ZERO
		var at := Vector3.ZERO
		cam.fov = 60.0
		cam.far = 4000.0
		if v.begins_with("obj:"): # the first of a named furniture piece, from 14 m in front of it
			var mmi: MultiMeshInstance3D = world.track_root.find_child(v.substr(4), true, false)
			if mmi == null or mmi.multimesh.instance_count == 0:
				continue
			var k := mini(int(OS.get_environment("INDEX")), mmi.multimesh.instance_count - 1) if OS.get_environment("INDEX") != "" else 0
			var xf := mmi.global_transform * mmi.multimesh.get_instance_transform(k)
			at = xf.origin + Vector3.UP * 2.0
			eye = at + (xf.basis.z.normalized() * 12.0 + xf.basis.x.normalized() * 5.0) + Vector3.UP * 1.5
		elif v.begins_with("lm:"): # a landmark (MeshInstance3D), from its front and a little above and aside
			var lmi := world.track_root.find_child(v.substr(3), true, false) as MeshInstance3D
			if lmi == null: # a group node (HarborYacht_00): its first mesh
				var group: Node = world.track_root.find_child(v.substr(3), true, false)
				if group:
					lmi = group.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
			if lmi == null:
				continue
			var box := lmi.global_transform * lmi.get_aabb()
			var reach := maxf(box.size.x, box.size.z) * 0.9 + 25.0
			at = box.get_center()
			eye = at + lmi.global_transform.basis.z.normalized() * reach + lmi.global_transform.basis.x.normalized() * reach * 0.4 + Vector3.UP * (box.size.y * 0.5 + reach * 0.25)
		elif v.begins_with("pos:"): # track point x;y (metres) from DIST m away to the south-west and HEIGHT m up
			var a := v.substr(4).split(";")
			var cw: Vector2 = world.world_center
			at = Vector3(float(a[0]) - cw.x, world.surroundings.ground_height(float(a[0]), float(a[1])) + 3.0, float(a[1]) - cw.y)
			var dist := float(a[2]) if a.size() > 2 else 60.0
			eye = at + Vector3(-dist * 0.7, float(a[3]) if a.size() > 3 else 25.0, dist * 0.7)
		elif v.begins_with("wall"): # the first tyre wall at or after S metres, from the run-off in front of it
			var s := float(v.substr(4))
			var best_s := INF
			var best_side := 1.0
			for cell in world.tyre_cells:
				var ks: float = (int(cell) >> 1) * 2 * tr.step
				if ks >= s and ks < best_s:
					best_s = ks
					best_side = 1.0 if (int(cell) & 1) == 1 else -1.0
			var bd := tr.half + tr.cfg.runoff + 0.3
			eye = _pt(world, best_s - 14.0, best_side * (bd - 4.0), 1.6)
			at = _pt(world, best_s + 6.0, best_side * bd, 0.7)
		elif v == "kerb": # the inside kerb of the tightest bend
			var ki := 0
			var best_k := 0.0
			for i in range(0, tr.n, 4):
				var avg := 0.0
				for j in range(-10, 11): # curvature over 40 m, so a kink in the data doesn't win
					avg += tr.KC[posmod(i + j, tr.n)]
				if absf(avg) > best_k:
					best_k = absf(avg)
					ki = i
			var ks := ki * tr.step
			var kd := signf(tr.KC[ki])
			eye = _pt(world, ks - 12.0, kd * (tr.half - 3.0), 1.8)
			at = _pt(world, ks + 6.0, kd * tr.half, 0.0)
		elif v.begins_with("side"): # from beside the road at S metres, level with the road surface (SIDE d, default 40 m to the right)
			var s := float(v.substr(4))
			var sd := float(OS.get_environment("SIDE")) if OS.get_environment("SIDE") != "" else 40.0
			eye = _pt(world, s - 20.0, sd, -2.0)
			at = _pt(world, s, 0.0, 0.0)
		elif v.begins_with("down"): # straight down on the road at S metres from the bird's-eye camera's height
			var s := float(v.substr(4))
			eye = _pt(world, s, 0.0, 60.0)
			at = _pt(world, s, 0.0, 0.0)
			cam.fov = 55.0
		elif v.begins_with("top"): # from above and to the side of the road at S metres
			var s := float(v.substr(3))
			eye = _pt(world, s - 70.0, 60.0, 45.0)
			at = _pt(world, s, 0.0, 0.0)
		elif v.begins_with("lap") or v.begins_with("at"):
			var s := float(v.substr(3)) / 8.0 * tr.L if v.begins_with("lap") else float(v.substr(2))
			eye = _pt(world, s, 0.0, 1.3)
			at = _pt(world, s + 40.0, 0.0, 1.0)
			cam.fov = 70.0
		else:
			match v:
				"stands": # from the pit wall across the track
					eye = _pt(world, sm - 30.0, ps * tr.half, 2.0)
					at = _pt(world, sm + 10.0, ss * (tr.half + tr.cfg.runoff + 8.0), 5.0)
				"stands_near":
					eye = _pt(world, sm, ss * (tr.half + 2.0), 1.4)
					at = _pt(world, sm + 25.0, ss * (tr.half + tr.cfg.runoff + 6.0), 6.0)
				"stands_back":
					eye = _pt(world, sm - 50.0, ss * (tr.half + tr.cfg.runoff + 40.0), 25.0)
					at = _pt(world, sm, ss * (tr.half + tr.cfg.runoff + 5.0), 3.0)
				"pits":
					eye = _pt(world, gm - 40.0, ss * tr.half, 3.0)
					at = _pt(world, gm, tr.cfg.pit_offset + ps * 10.0, 5.0)
				"pits_near":
					eye = _pt(world, gm, tr.cfg.pit_offset - ps * 1.0, 1.7)
					at = _pt(world, gm + 20.0, tr.cfg.pit_offset + ps * 8.0, 4.0)
				"gantry":
					eye = _pt(world, -70.0, 0.0, 2.0)
					at = _pt(world, 0.0, 0.0, 5.0)
				"aerial":
					eye = _pt(world, -140.0, -ss * 90.0, 70.0)
					at = _pt(world, 0.0, ss * 10.0, 0.0)
				"high": # the whole circuit from above
					var dist: float = world.overview_distance
					eye = Vector3(0.0, dist * 0.6, dist * 0.55)
					at = Vector3.ZERO
					cam.far = dist * 4.0
				"city":
					eye = _pt(world, 300.0, 0.0, 2.0)
					at = _pt(world, 340.0, 12.0, 8.0)
				"casino":
					var c: Dictionary = world._casino_spot()
					eye = _pt(world, c.s - 45.0, -c.side * 2.0, 2.0)
					at = _pt(world, c.s, c.side * 15.0, 8.0)
		cam.position = eye
		cam.look_at(at, Vector3.UP if absf((at - eye).normalized().y) < 0.99 else Vector3.FORWARD)
		world._update_lamp_lights() # the lamps' lights go to the ones nearest the camera (the world's _process is off)
		world._update_beams() # likewise the headlight beams after dark
		for f in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var path := "%s/%s_%s.png" % [out, key, v]
		root.get_texture().get_image().save_png(path)
		print("saved ", path)
	quit()

func _pt(world: Node, s: float, d: float, h: float) -> Vector3:
	var p: PackedFloat64Array = world.track.pos(s, d)
	return Vector3(p[0] - world.world_center.x, world._road_y(s) + world.track.bank_rise(s, d) + h, p[1] - world.world_center.y)
