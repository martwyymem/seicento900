## Frame-cost benchmark for the race world: CPU time per frame (main thread) and GPU time, measured with vsync off.
## Env: W, H (window size), OLD (1 = pre-optimisation MSAA/SSIL/sky settings), VSYNC (1 keeps it on), MAXFPS, TRACK, HOUR, RAIN, RT (0 off, 1 on), QUALITY (0-3), FSR (Viewport.Scaling3DMode), SCALE, FRAMES.
##   godot --path godot -s tests/_perf.gd
extends SceneTree

func _initialize() -> void:
	var env := OS.get_environment
	var key: String = env.call("TRACK") if env.call("TRACK") != "" else "gp"
	if env.call("VSYNC") != "1":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if env.call("MAXFPS") != "":
		Engine.max_fps = int(env.call("MAXFPS"))
	root.size = Vector2i(int(env.call("W")) if env.call("W") != "" else 1600, int(env.call("H")) if env.call("H") != "" else 900)
	var world = load("res://ui/race_world.tscn").instantiate()
	root.add_child(world)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	await process_frame
	if env.call("FSR") != "":
		root.scaling_3d_mode = int(env.call("FSR"))
		root.scaling_3d_scale = float(env.call("SCALE")) if env.call("SCALE") != "" else 0.5
	if env.call("QUALITY") != "":
		world.apply_graphics(int(env.call("QUALITY")))
	if env.call("OLD") == "1": # the settings this file's changes replaced
		root.msaa_3d = Viewport.MSAA_2X
		world.world_environment.ssil_enabled = true
		world.world_environment.sky.process_mode = Sky.PROCESS_MODE_REALTIME
	var rs := RaceSettings.new()
	rs.track = key
	rs.opponents = 15
	rs.start_hour = float(env.call("HOUR")) if env.call("HOUR") != "" else 14.0
	var race := Race.new(rs)
	world.set_race(race)
	world.ray_tracing.enabled = env.call("RT") == "1"
	var rain: float = float(env.call("RAIN")) if env.call("RAIN") != "" else 0.0
	var inp := Race.PlayerInput.new()
	inp.throttle = 1.0
	var frames := int(env.call("FRAMES")) if env.call("FRAMES") != "" else 240
	var times := PackedFloat64Array()
	var cpu := PackedFloat64Array()
	var gpu := PackedFloat64Array()
	for f in frames + 40:
		race.weather.rain = rain
		race.weather.wet = rain
		race.step(1.0 / 60.0, inp)
		var t := Time.get_ticks_usec()
		await process_frame
		await RenderingServer.frame_post_draw
		if f >= 40:
			times.append((Time.get_ticks_usec() - t) / 1000.0)
			cpu.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
	times.sort()
	cpu.sort()
	gpu.sort()
	print("RESULT frame %.2f ms  process %.2f ms  render-cpu %.2f ms  gpu %.2f ms  (draw calls %d)" % [
		times[times.size() / 2], cpu[cpu.size() / 2],
		RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()), gpu[gpu.size() / 2],
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
	quit()
