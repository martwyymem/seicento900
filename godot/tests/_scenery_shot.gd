## Temporary scenery check: builds a circuit and saves screenshots of the grandstands, pits and buildings.
## Env: TRACK (default gp), HOUR, VIEWS (comma list: stands, stands_near, pits, pits_near, gantry, aerial,
## city, casino), OUT (directory).
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
	rs.opponents = 7
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
			"city":
				eye = _pt(world, 300.0, 0.0, 2.0)
				at = _pt(world, 340.0, 12.0, 8.0)
			"casino":
				var c: Dictionary = world._casino_spot()
				eye = _pt(world, c.s - 45.0, -c.side * 2.0, 2.0)
				at = _pt(world, c.s, c.side * 15.0, 8.0)
		cam.position = eye
		cam.look_at(at, Vector3.UP)
		cam.fov = 60.0
		for f in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var path := "%s/%s_%s.png" % [out, key, v]
		root.get_texture().get_image().save_png(path)
		print("saved ", path)
	quit()

func _pt(world: Node, s: float, d: float, h: float) -> Vector3:
	var p: PackedFloat64Array = world.track.pos(s, d)
	return Vector3(p[0] - world.world_center.x, world._road_y(s) + h, p[1] - world.world_center.y)
