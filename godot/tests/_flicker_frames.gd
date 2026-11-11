## Windowed probe: frame-to-frame flicker with the car standing still at night on STREET (default Kosynierów), for the
## upscalers in MODES (game.UPSCALERS indices, default "4,0": MetalFX Temporal, off). Saves FRAMES consecutive frames
## per mode as OUT/<mode>_NN.png for an outside tool to compare, and prints the viewport's AA state. Env: OUT, STREET,
## MODES, FRAMES, HOUR.
## godot --path godot --audio-driver Dummy --always-on-top --resolution 1280x720 --position 2140,1390 -s tests/_flicker_frames.gd
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
	var out := _env("OUT", "/tmp/qa/flicker")
	DirAccess.make_dir_recursive_absolute(out)
	game = load("res://ui/game.tscn").instantiate()
	root.add_child(game)
	await _wait(30)
	game._on_aspect_selected(1)
	game._on_preset_selected(2)
	await _wait(5)
	await game._enter_open_world("")
	await _wait(90)
	var ow: OpenWorld = game.open_world
	var map: TownMap = ow.map
	var street := _env("STREET", "Kosynier")
	var at := Vector2.ZERO
	var heading := 0.0
	var best := 0.0
	for ri in map.road_pts.size():
		if not (street in map.road_name[ri]) or map.road_w[ri] < 5.0:
			continue
		var pts := map.road_pts[ri]
		for i in pts.size() - 1:
			var l := pts[i].distance_to(pts[i + 1])
			if l > best:
				best = l
				at = pts[i].lerp(pts[i + 1], 0.5) + (pts[i + 1] - pts[i]).normalized().orthogonal() * 1.4
				heading = (pts[i + 1] - pts[i]).angle()
	print("FLICKER on %s at %s (segment %.0f m)" % [street, at, best])
	ow.drive.place(at, heading)
	ow.drive.respawn()
	ow.snap_camera()
	var hour := float(_env("HOUR", "23"))
	for mode_s in _env("MODES", "4,0").split(","):
		# the open world copies the game viewport's upscaler when it is made: set its own viewport as the game would
		var mode: int = game.UPSCALERS[int(mode_s)].mode
		ow.viewport.scaling_3d_mode = mode
		ow.viewport.scaling_3d_scale = 1.0 if int(mode_s) == 0 else float(game.UPSCALE_PRESETS[1].scale)
		var temporal := mode in [Viewport.SCALING_3D_MODE_FSR2, Viewport.SCALING_3D_MODE_METALFX_TEMPORAL]
		ow.viewport.msaa_3d = Viewport.MSAA_DISABLED if temporal else Viewport.MSAA_2X
		ow.viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED if temporal else Viewport.SCREEN_SPACE_AA_FXAA
		for i in 150:
			ow.hour = hour
			await _wait(1)
		var vp: Viewport = ow.viewport
		print("FLICKER mode %s: scaling mode %d scale %.2f msaa %d ssaa %d taa %s size %s" % [mode_s, vp.scaling_3d_mode, vp.scaling_3d_scale,
			vp.msaa_3d, vp.screen_space_aa, vp.use_taa, vp.size])
		for k in int(_env("FRAMES", "12")):
			ow.hour = hour
			await _wait(1)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/m%s_%02d.png" % [out, mode_s, k])
	game.queue_free()
	await process_frame
	Guard.restore()
	quit()
