## Windowed probe: open-world frame time through the real game scene with the player's settings, switching the
## upscaler and retro style. godot --path godot --audio-driver Dummy --always-on-top --resolution 1920x1080 -s tests/_ow_game_perf.gd
extends SceneTree

const Guard := preload("res://tests/_qa_save_guard.gd")
var game

func _wait(frames: int) -> void:
	for k in frames:
		game._app_focused = true
		if game.paused:
			game._set_paused(false)
		await process_frame

func _measure(n := 150) -> String:
	await _wait(40)
	var ft := PackedFloat64Array()
	var vrid: RID = game.open_world.viewport.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vrid, true)
	var cpu := 0.0
	var gpu := 0.0
	var setup := 0.0
	for f in n:
		game._app_focused = true
		var t := Time.get_ticks_usec()
		await RenderingServer.frame_post_draw
		ft.append((Time.get_ticks_usec() - t) / 1000.0)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vrid)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vrid)
		setup += RenderingServer.get_frame_setup_time_cpu()
	ft.sort()
	return "%.1f (p95 %.1f) [3d cpu %.1f gpu %.1f setup %.1f]" % [ft[ft.size() / 2], ft[int(ft.size() * 0.95)], cpu / n, gpu / n, setup / n]

func _initialize() -> void:
	Brain.use_disk = false
	Guard.backup()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	game = load("res://ui/game.tscn").instantiate()
	root.add_child(game)
	await _wait(30)
	game._on_preset_selected(1)
	root.size = Vector2i(2560, 1440)
	await game._enter_open_world("")
	await _wait(60)
	var ow: OpenWorld = game.open_world
	var spot: Array = ow.map.spots["station"]
	ow.drive.place(Vector2(spot[0], spot[1]), float(spot[2]))
	ow.drive.respawn()
	game.graphics_fps_limit = 3
	game._on_upscaler_selected(1)
	game._on_upscale_preset_selected(1)
	game._on_retro_selected(0)
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var veg: Node = ow.world.find_child("Vegetation", true, false)
	var tests := {
		"base": [func(): pass, func(): pass],
		"no car refl": [func(): ow.reflections.visible = false, func(): ow.reflections.visible = true],
		"2 splits": [func(): ow.sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, func(): ow.sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS],
		"no shadows": [func(): ow.sun.shadow_enabled = false, func(): ow.sun.shadow_enabled = true],
		"no ssao": [func(): ow.env.ssao_enabled = false, func(): ow.env.ssao_enabled = true],
		"no veg": [func(): veg.visible = false, func(): veg.visible = true],
		"metalfx temporal": [func(): game._on_upscaler_selected(4), func(): game._on_upscaler_selected(1)],
		"metalfx spatial": [func(): game._on_upscaler_selected(3), func(): game._on_upscaler_selected(1)],
		"retro 6": [func(): game._on_retro_selected(6), func(): game._on_retro_selected(0)],
		"base again": [func(): pass, func(): pass],
	}
	for k in tests:
		tests[k][0].call()
		var r: String = await _measure()
		var tp := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		tests[k][1].call()
		print("RESULT %-18s %s ms  TIME_PROCESS %.1f draws %d" % [k, r, tp, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
	Guard.restore()
	quit()
