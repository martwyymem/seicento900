## Ray-tracing check: renders the race world with ray-traced reflections and saves a screenshot.
## Env: TRACK, HOUR, WET, RAIN, CAM, RT (0 off, 1 on), DEBUG (0-2), FSR (Viewport.Scaling3DMode), SCALE (default 0.59), OUT.
extends SceneTree

func _initialize() -> void:
	var env := OS.get_environment
	var key: String = env.call("TRACK") if env.call("TRACK") != "" else "gp"
	var out: String = env.call("OUT") if env.call("OUT") != "" else "/tmp/seicento_rt/%s.png" % key
	root.size = Vector2i(1600, 900)
	var world = load("res://ui/race_world.tscn").instantiate()
	root.add_child(world)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	await process_frame
	if env.call("FSR") != "":
		root.scaling_3d_mode = int(env.call("FSR"))
		root.scaling_3d_scale = float(env.call("SCALE")) if env.call("SCALE") != "" else 0.59
	var rs := RaceSettings.new()
	rs.track = key
	rs.opponents = 7
	rs.start_hour = float(env.call("HOUR")) if env.call("HOUR") != "" else 14.0
	var race := Race.new(rs)
	world.set_race(race)
	world.camera_mode = int(env.call("CAM")) if env.call("CAM") != "" else 0
	world.ray_tracing.enabled = env.call("RT") != "0"
	world.ray_tracing.debug_view = int(env.call("DEBUG")) if env.call("DEBUG") != "" else 0
	var wet: float = float(env.call("WET")) if env.call("WET") != "" else 0.0
	var rain: float = float(env.call("RAIN")) if env.call("RAIN") != "" else 0.0
	var inp := Race.PlayerInput.new()
	var frames := 40
	var times := PackedFloat64Array()
	for f in frames:
		race.weather.wet = wet
		race.weather.rain = rain
		race.step(1.0 / 60.0, inp)
		var t := Time.get_ticks_usec()
		await process_frame
		times.append((Time.get_ticks_usec() - t) / 1000.0)
	await RenderingServer.frame_post_draw
	times.sort()
	print("median frame %.2f ms, GPU %.2f ms" % [times[times.size() / 2], RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())])
	var img := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	img.save_png(out)
	print("saved ", out)
	quit()
