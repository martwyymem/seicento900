## Temporary graphics check: renders the race world and saves a screenshot.
## Env: TRACK, HOUR, WET, RAIN, CAM (0-5), QUALITY (0-3), FRAMES, OUT (png path).
extends SceneTree

func _initialize() -> void:
	var env := OS.get_environment
	var key: String = env.call("TRACK") if env.call("TRACK") != "" else "gp"
	var frames: int = int(env.call("FRAMES")) if env.call("FRAMES") != "" else 40
	var out: String = env.call("OUT") if env.call("OUT") != "" else "/tmp/seicento52/%s.png" % key
	root.size = Vector2i(1600, 900)
	var world = load("res://ui/race_world.tscn").instantiate()
	root.add_child(world)
	if env.call("QUALITY") != "":
		world.apply_graphics(int(env.call("QUALITY")))
	var rs := RaceSettings.new()
	rs.track = key
	rs.opponents = 7
	rs.start_hour = float(env.call("HOUR")) if env.call("HOUR") != "" else 14.0
	var race := Race.new(rs)
	world.set_race(race)
	world.camera_mode = int(env.call("CAM")) if env.call("CAM") != "" else 0
	var wet: float = float(env.call("WET")) if env.call("WET") != "" else 0.0
	var rain: float = float(env.call("RAIN")) if env.call("RAIN") != "" else 0.0
	var inp := Race.PlayerInput.new()
	var t0 := Time.get_ticks_msec()
	for f in frames:
		race.weather.wet = wet
		race.weather.rain = rain
		race.step(1.0 / 60.0, inp)
		await process_frame
	print("frames: %d in %d ms" % [frames, Time.get_ticks_msec() - t0])
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	img.save_png(out)
	print("saved ", out)
	quit()
