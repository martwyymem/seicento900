## Windowed probe: open-world frame cost at several spots (frame ms, script ms, draw calls, primitives), vsync off.
##   godot --path godot --audio-driver Dummy --always-on-top -s tests/_ow_perf_probe.gd
extends SceneTree

const SPOTS := ["industrial_sprint", "bor_stage", "station", "festival", "exit_wilamowice", "exit_tychy"]

func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await process_frame
	root.size = Vector2i(1600, 900)
	var t0 := Time.get_ticks_msec()
	var ow := OpenWorld.new()
	root.add_child(ow)
	await ow.open("industrial_sprint")
	print("OPEN %d ms" % (Time.get_ticks_msec() - t0))
	for name in SPOTS:
		var spot: Array = ow.map.spots.get(name, [])
		if spot.is_empty():
			continue
		ow.drive.place(Vector2(spot[0], spot[1]), float(spot[2]))
		ow.drive.respawn()
		ow.active = true
		for i in 60:
			await process_frame
		var ft := PackedFloat64Array()
		var pt := PackedFloat64Array()
		for f in 180:
			var t := Time.get_ticks_usec()
			await RenderingServer.frame_post_draw
			ft.append((Time.get_ticks_usec() - t) / 1000.0)
			pt.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		ft.sort()
		pt.sort()
		print("RESULT %-18s frame med %.2f p95 %.2f ms  script %.2f ms  draws %d  objs %d  prims %dk" % [name,
			ft[ft.size() / 2], ft[int(ft.size() * 0.95)], pt[pt.size() / 2],
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)) / 1000])
	quit()
