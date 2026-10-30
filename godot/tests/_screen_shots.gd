## Windowed probe (item 8c): screenshots of the screens around a race, in the active skin.
##   godot --path godot --audio-driver Dummy --always-on-top -s tests/_screen_shots.gd -- [out dir] [retro mode]
## Saves pause.png (quick race, paused), results.png (after retiring), quali.png (championship round 1,
## simulated qualifying sheet), champ_pause.png and champ_results.png. Saves go to the dev sandbox.
extends SceneTree

var game
var out := "/tmp/screen_shots"

func _wait(frames: int) -> void:
	for k in frames:
		await process_frame

func _wait_start() -> void:
	for k in 6000:
		await process_frame
		if not game._starting:
			return

func _start() -> void:
	await _wait(30)
	for k in 6000:
		if not game._strategy_pending:
			break
		await process_frame
	game._start_race()
	await _wait_start()

func _shot(name: String) -> void:
	await _wait(20)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("saved ", name)

func _results() -> void:
	if game.race:
		game._set_paused(true)
		game._pause_action("retire")
	for k in 3000:
		if game.result_panel.visible:
			break
		await process_frame

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	Brain.use_disk = false
	root.size = Vector2i(1600, 900)
	game = load("res://ui/game.tscn").instantiate()
	root.add_child(game)
	await _wait(20)
	game.opponents_picker.value = 7
	game.laps_picker.value = 2
	await _start()
	await _wait(240)
	game._set_paused(true)
	await _shot("pause")
	await _results()
	await _shot("results")
	game._return_to_setup()
	await _wait(30)
	game._show_home()
	game._home_select(game.FRONT_MENU.map(func(e): return e.id).find("championship"), false)
	game._activate_home_item()
	game.quali_picker.select(1)
	await _start()
	await _wait(30)
	await _shot("quali")
	await _start()
	await _wait(120)
	game._set_paused(true)
	await _shot("champ_pause")
	await _results()
	await _shot("champ_results")
	game.queue_free()
	await _wait(5)
	quit()
