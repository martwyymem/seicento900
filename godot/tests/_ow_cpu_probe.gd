## Windowed probe: where the open world's per-frame CPU time goes (OpenWorld.PROF sections), standing still at spots.
##   godot --path godot --audio-driver Dummy --always-on-top -s tests/_ow_cpu_probe.gd
extends SceneTree

const SPOTS := ["bor_stage", "station", "exit_tychy"]

func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await process_frame
	root.size = Vector2i(1600, 900)
	var ow := OpenWorld.new()
	root.add_child(ow)
	await ow.open("industrial_sprint")
	for name in SPOTS:
		var spot: Array = ow.map.spots.get(name, [])
		if spot.is_empty():
			continue
		ow.drive.place(Vector2(spot[0], spot[1]), float(spot[2]))
		ow.drive.respawn()
		ow.active = true
		for i in 60:
			await process_frame
		OpenWorld.PROF.clear()
		var n := 180
		var t0 := Time.get_ticks_usec()
		var proc := 0.0
		for f in n:
			await process_frame
			proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		var total := (Time.get_ticks_usec() - t0) / 1000.0 / n
		var keys: Array = OpenWorld.PROF.keys()
		keys.sort_custom(func(a, b): return OpenWorld.PROF[a] > OpenWorld.PROF[b])
		var sum := 0.0
		var parts := []
		for k in keys:
			var ms: float = OpenWorld.PROF[k] / 1000.0 / n
			sum += ms
			if ms >= 0.05:
				parts.append("%s %.2f" % [k, ms])
		print("RESULT %-12s frame %.2f ms  TIME_PROCESS %.2f  ow sections %.2f  | %s" % [name, total, proc / n, sum, ", ".join(parts)])
	quit()
