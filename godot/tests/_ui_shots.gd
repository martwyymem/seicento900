## Windowed probe: the home strip across the QUIT -> CAMPAIGN wrap, and the race HUD at speed.
##   godot --path godot --audio-driver Dummy --always-on-top -s tests/_ui_shots.gd -- [out dir]
extends SceneTree

func _wait(n: int) -> void:
	for k in n:
		paused = false
		await process_frame

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp/ui_shots"
	DirAccess.make_dir_recursive_absolute(out)
	Brain.use_disk = false
	await process_frame
	root.size = Vector2i(1600, 900)
	var game = load("res://ui/game.tscn").instantiate()
	root.add_child(game)
	await _wait(40)
	game._home_select(game.FRONT_MENU.size() - 1, false)
	await _wait(10)
	await _shot(out + "/home_quit.png")
	game._home_select(game.home_menu_index + 1)
	await _wait(8)
	await _shot(out + "/home_wrap_mid.png")
	await _wait(40)
	await _shot(out + "/home_campaign.png")
	game.opponents_picker.value = 3
	game.laps_picker.value = 2
	await _wait(30)
	game._start_race()
	for k in 3000:
		await process_frame
		if not game._starting and game.race != null:
			break
	await _wait(20)
	await _shot(out + "/race_countdown.png")
	await _wait(40)
	var r: Race = game.race
	if r:
		r.phase = "racing"
	for k in 600:
		game.world_view.get_tree().root.get_viewport().set_input_as_handled()
		await process_frame
	for k in 12:
		if r:
			r.player.rev = false
			r.player.speed = 61.0
			r.player.rpm = r.spec.limiter * 0.85
			r.player.gear = 3
		await _wait(1)
	await _shot(out + "/race_hud.png")
	DisplayServer.window_set_size(Vector2i(1200, 900))
	await _wait(20)
	await _shot(out + "/race_hud_43.png")
	game.hud.toggle_help()
	await _wait(10)
	await _shot(out + "/race_guide_43.png")
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await _wait(20)
	await _shot(out + "/race_guide.png")
	quit()
