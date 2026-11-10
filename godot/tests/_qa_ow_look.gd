## QA probe (dev tool, run WINDOWED): the open world seen through the real game scene (retro pipeline, graphics
## preset, HUD), at a spot and hour, in every retro style and/or graphics preset. Goes through
## game._enter_open_world(""), so the retro material and preset are the ones a player has.
## Env: SPOT (OpenWorld map spot, default bor_stage), PLACE (a named map place instead, e.g. Wola), AHEAD (m along the road, default 0;
## a comma list shoots each), HOURS (comma, default
## "14,22.5"), MODES (retro styles, default "0"), PRESET (0 Low .. 3 Ultra, default 2), PERF (frames to time, 0 = off),
## ASPECT (index into game.ASPECTS, default 1 = 16:9), OUT, TAG. Saves are backed up and restored (shared sandbox).
## godot --path godot --audio-driver Dummy --always-on-top --resolution 1280x720 --position 2140,1390 -s tests/_qa_ow_look.gd
extends SceneTree

const Guard := preload("res://tests/_qa_save_guard.gd")
var game

func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d

func _wait(frames: int) -> void:
	for k in frames:
		if game:
			game._app_focused = true
			if game.paused:
				game._set_paused(false)
		await process_frame

func _initialize() -> void:
	Brain.use_disk = false
	Guard.backup()
	var out := _env("OUT", "/tmp/qa/ow")
	var tag := _env("TAG", "ow")
	DirAccess.make_dir_recursive_absolute(out)
	game = load("res://ui/game.tscn").instantiate()
	root.add_child(game)
	await _wait(30)
	game._on_aspect_selected(int(_env("ASPECT", "1")))
	game._on_preset_selected(int(_env("PRESET", "2")))
	await _wait(5)
	var t0 := Time.get_ticks_msec()
	await game._enter_open_world("") # returns once the world is built
	await _wait(90)
	var ow: OpenWorld = game.open_world
	print("OWL open world up: %s after %.1f s, preset %d aspect %d" % [ow != null and ow.visible, (Time.get_ticks_msec() - t0) / 1000.0, game.graphics_preset, game.graphics_aspect])
	if ow == null:
		Guard.restore()
		quit(1)
		return
	var spot: Array = ow.map.spots[_env("SPOT", "bor_stage")]
	var p := Vector2(spot[0], spot[1])
	var h := float(spot[2])
	if _env("PLACE", "") != "": # a named place (map.places, e.g. Wola, Rajsko): on the road nearest it, along that road
		for pl in ow.map.places:
			if String(pl.name) == _env("PLACE", ""):
				var near: Dictionary = ow.map.nearest_road(Vector2(float(pl.x), float(pl.y)), 400.0)
				if not near.is_empty():
					p = near.pos
					h = (near.dir as Vector2).angle()
				break
	var ahead_list := _env("AHEAD", "0").split(",")
	for ai in ahead_list.size():
		var pa := p + Vector2(cos(h), sin(h)) * float(ahead_list[ai])
		var near_a: Dictionary = ow.map.nearest_road(pa, 60.0)
		var ha := h
		if not near_a.is_empty():
			pa = near_a.pos
			ha = (near_a.dir as Vector2).angle()
			if cos(ha - h) < 0.0:
				ha += PI
		ow.drive.place(pa, ha)
		ow.drive.respawn()
		await _shoot_hours(ow, out, "%s_a%s" % [tag, ahead_list[ai]] if ahead_list.size() > 1 else tag)
	game.queue_free()
	await process_frame
	Guard.restore()
	quit()

func _shoot_hours(ow: OpenWorld, out: String, tag: String) -> void:
	for hour_s in _env("HOURS", "14,22.5").split(","):
		var hour := float(hour_s)
		ow.hour = hour
		ow.snap_camera()
		for i in 60:
			ow.hour = hour
			await _wait(1)
		if int(_env("PERF", "0")) > 0:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps = 0
			var ts: Array[float] = []
			var tp := Time.get_ticks_usec()
			for k in int(_env("PERF", "0")):
				ow.hour = hour
				await _wait(1)
				var tn := Time.get_ticks_usec()
				ts.append((tn - tp) / 1000.0)
				tp = tn
			ts.sort()
			print("OWL perf preset %s hour %s: median %.2f ms p95 %.2f ms, draws %d, objects %d, prims %.2fM" % [_env("PRESET", "2"), hour_s,
				ts[ts.size() / 2], ts[int(ts.size() * 0.95)], Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1.0e6])
		var modes := _env("MODES", "0").split(",")
		for m in modes:
			game.retro_pipeline.set_mode(int(m))
			if modes.size() > 1:
				Engine.time_scale = 0.0
			await _wait(6)
			await RenderingServer.frame_post_draw
			var path := "%s/%s_h%s_mode%s.png" % [out, tag, hour_s, m]
			root.get_texture().get_image().save_png(path)
			print("OWL saved ", path)
		Engine.time_scale = 1.0
		game.retro_pipeline.set_mode(0)
