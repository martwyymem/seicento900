## Windowed probe: main menu → CAMPAIGN through the real game scene, timing the wait until the car is drivable and the
## first frames drawn after it (pipeline compilation). Quits by itself (watchdog).
##   OW_BUILD_TIMES=1 timeout 180 godot --path godot --audio-driver Dummy --always-on-top -s tests/_ow_load_probe.gd
extends SceneTree

const Guard := preload("res://tests/_qa_save_guard.gd")
var game
var t_start := 0

func _initialize() -> void:
	Brain.use_disk = false
	Guard.backup()
	t_start = Time.get_ticks_msec()
	_watchdog()
	game = load("res://ui/game.tscn").instantiate()
	root.add_child(game)
	for k in 30:
		game._app_focused = true
		await process_frame
	var screen := DisplayServer.screen_get_usable_rect()
	DisplayServer.window_set_position(screen.position + screen.size - Vector2i(1300, 760))
	var t0 := Time.get_ticks_msec()
	print("menu ready at %d ms" % (Time.get_ticks_msec() - t_start))
	game._start_campaign_mode()
	var frames := 0
	while game.open_world == null or not game.open_world.built or game.open_world.building:
		game._app_focused = true
		await process_frame
		frames += 1
	print("CAMPAIGN -> world built: %d ms (%d frames of cover)" % [Time.get_ticks_msec() - t0, frames])
	var t1 := Time.get_ticks_msec()
	var gaps: Array = []
	for k in 12:
		game._app_focused = true
		var a := Time.get_ticks_msec()
		await RenderingServer.frame_post_draw
		gaps.append(Time.get_ticks_msec() - a)
	print("first 12 drawn frames (ms): ", gaps)
	print("CAMPAIGN -> world drawn: %d ms (drawn after build: %d ms)" % [Time.get_ticks_msec() - t0, Time.get_ticks_msec() - t1])
	Guard.restore()
	quit()

func _watchdog() -> void:
	await create_timer(150.0, true, false, true).timeout
	print("WATCHDOG: quitting")
	Guard.restore()
	quit(1)
