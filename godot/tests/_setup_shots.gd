## Windowed probe: the race set-up pages (Set Up / Advanced / Car) at 16:9 and 4:3.
##   godot --path godot --audio-driver Dummy --always-on-top -s tests/_setup_shots.gd -- [out dir]
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
	var out: String = args[0] if args.size() > 0 else "/tmp/setup_shots"
	DirAccess.make_dir_recursive_absolute(out)
	Brain.use_disk = false
	await process_frame
	root.size = Vector2i(1600, 900)
	var game = load("res://ui/game.tscn").instantiate()
	root.add_child(game)
	await _wait(40)
	for size in [Vector2i(1600, 900), Vector2i(1200, 900)]:
		DisplayServer.window_set_size(size)
		await _wait(20)
		var tag := "%dx%d" % [size.x, size.y]
		for mode in ["quick", "champ", "campaign"]:
			game.is_campaign_mode = mode == "campaign"
			game.is_championship_mode = mode == "champ"
			game.is_rally_mode = false
			game.is_time_trial_mode = false
			game._update_mode_view()
			for page in ["setup", "advanced", "car", "strategy"]:
				if (mode != "quick" and page == "strategy") or (mode == "campaign" and page != "setup"):
					continue
				match page:
					"setup": game._show_setup_page()
					"advanced": game._show_advanced_page()
					"car": game._show_car_page()
					"strategy": game._show_strategy_page()
				await _wait(25)
				await _shot("%s/%s_%s_%s.png" % [out, mode, page, tag])
	quit()
