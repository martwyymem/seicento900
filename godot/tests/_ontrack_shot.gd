## Dev probe: runs a race with the world attached and saves shots from several cameras at given race times.
## Env: TRACK, SEED, OPP (opponents), TIMES (comma list of race seconds), CAMS (comma list of camera modes), OUT,
## RT (1: ray-traced reflections on), FSR (Viewport.Scaling3DMode), SCALE, HIDE (comma list of node names to hide)
extends SceneTree

func _initialize() -> void:
	Brain.use_disk = false
	var env := OS.get_environment
	var key: String = env.call("TRACK") if env.call("TRACK") != "" else "monza"
	var out: String = env.call("OUT") if env.call("OUT") != "" else "/tmp/seicento_ontrack"
	var times: PackedStringArray = (env.call("TIMES") if env.call("TIMES") != "" else "26").split(",")
	var cams: PackedStringArray = (env.call("CAMS") if env.call("CAMS") != "" else "4,1").split(",")
	root.size = Vector2i(1600, 900)
	var world = load("res://ui/race_world.tscn").instantiate()
	root.add_child(world)
	await process_frame
	var rs := RaceSettings.new()
	rs.track = key
	rs.opponents = int(env.call("OPP")) if env.call("OPP") != "" else 15
	rs.laps = 6
	var race := Race.new(rs, null, int(env.call("SEED")) if env.call("SEED") != "" else 1)
	race.set_autopilot(true)
	world.set_race(race)
	if env.call("FSR") != "":
		root.scaling_3d_mode = int(env.call("FSR"))
		root.scaling_3d_scale = float(env.call("SCALE")) if env.call("SCALE") != "" else 0.67
	world.ray_tracing.enabled = env.call("RT") == "1"
	if env.call("HIDE") != "":
		for nm in env.call("HIDE").split(","):
			var n: Node = world.track_root.find_child(nm, true, false)
			if n:
				n.visible = false
				print("hid ", n.get_path())
	var inp := Race.PlayerInput.new()
	DirAccess.make_dir_recursive_absolute(out)
	var sc_at := float(env.call("SC_AT")) if env.call("SC_AT") != "" else -1.0
	for ts in times:
		var t := float(ts)
		while race.race_time < t and race.phase != "finished":
			for k in 6:
				race.step(1.0 / 120.0, inp)
				if sc_at >= 0.0 and race.race_time >= sc_at and race.rc.flag == "green":
					race.rc.deploy_sc("probe")
			await process_frame
		print("t=%.1f flag=%s player s=%.0f d=%.1f" % [race.race_time, race.rc.flag if race.rc else "-", race.player.s, race.player.d])
		for cm in cams:
			world.camera_mode = int(cm)
			for f in 20:
				race.step(1.0 / 120.0, inp)
				await process_frame
			await RenderingServer.frame_post_draw
			var path := "%s/%s_t%s_cam%s.png" % [out, key, ts, cm]
			root.get_texture().get_image().save_png(path)
			print("saved ", path)
	for e in race.events.slice(-14):
		print("  [%s] %s" % [e.kind, e.text])
	quit()
