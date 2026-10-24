## QA probe (dev tool, run windowed): screenshots every UI skin (main menu, quick race set-up, circuit info,
## options, in-race HUD) into /tmp/qa_skins/, then the fast circuit-flip / race / menu / same circuit again flow.
## godot --path godot --audio-driver Dummy -s tests/_qa_skins.gd
extends SceneTree

var game
const OUT := "/tmp/qa_skins"
const MODES := [0, 1, 2, 3, 4, 6]

func _wait(frames: int) -> void:
	for k in frames:
		if game and game.paused:
			game._set_paused(false)
		if game:
			game._app_focused = true
		await process_frame

func _shot(tag: String) -> void:
	await _wait(4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, tag])
	print("QA shot ", tag)

func _key(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await process_frame

func _race_ready() -> bool:
	for k in 4000:
		await _wait(1)
		if game.race != null and not game._starting:
			return true
	return false

func _initialize() -> void:
	Brain.use_disk = false
	DirAccess.make_dir_recursive_absolute(OUT)
	game = load("res://ui/game.tscn").instantiate()
	root.add_child(game)
	await _wait(30)
	var only := OS.get_environment("PART")
	if only == "" or only == "menus":
		for m in MODES:
			game._on_retro_selected(m)
			game._show_home()
			game._home_select(1, false)
			await _shot("m%d_1_home" % m)
			game._activate_home_item()
			game.track_picker.select(game.TRACK_KEYS.find("krakow"))
			game._select_track(game.TRACK_KEYS.find("krakow"))
			await _wait(4)
			await _key(KEY_DOWN) # focus ring on a selector
			await _shot("m%d_2_setup" % m)
			game._show_information_page()
			await _shot("m%d_3_info" % m)
			game._show_repair_page()
			await _shot("m%d_4_service" % m)
			game._show_options_page()
			await _shot("m%d_5_options" % m)
	if only == "" or only == "race":
		game._on_retro_selected(0)
		game._show_home()
		game._home_select(1, false)
		game._activate_home_item()
		game.opponents_picker.value = 8
		game.track_picker.select(game.TRACK_KEYS.find("monza"))
		game._select_track(game.TRACK_KEYS.find("monza"))
		await _wait(10)
		for k in 3000:
			if not game._strategy_pending:
				break
			await process_frame
		game._start_race()
		if not await _race_ready():
			print("QA race did not start: ", game.status_label.text)
		else:
			game.race.set_autopilot(true)
			var t0 := Time.get_ticks_msec()
			while game.race.race_time < 14.0 and Time.get_ticks_msec() - t0 < 40000:
				await _wait(1)
			for m in MODES:
				game._on_retro_selected(m)
				await _wait(8)
				await _shot("m%d_6_hud" % m)
			game._set_paused(true)
			await _wait(4)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/m6_7_pause.png" % OUT)
			game._pause_action("retire")
			for k in 600:
				if game.result_panel.visible:
					break
				await process_frame
			await _shot("m6_8_results")
			game._on_retro_selected(0)
	if only == "" or only == "flip":
		# priority 3: flip fast through the circuits, race, back to the menu, race the same circuit again
		game._return_to_setup()
		game._show_home()
		game._home_select(1, false)
		game._activate_home_item()
		await _wait(5)
		game.track_picker.grab_focus()
		var t0 := Time.get_ticks_msec()
		var worst := 0
		for k in game.TRACK_KEYS.size():
			var t1 := Time.get_ticks_msec()
			await _key(KEY_RIGHT)
			worst = maxi(worst, Time.get_ticks_msec() - t1)
		print("QA flip %d circuits in %d ms, slowest step %d ms, on %s" % [game.TRACK_KEYS.size(), Time.get_ticks_msec() - t0, worst, game.TRACK_KEYS[game.track_picker.selected]])
		await _shot("flip_1_setup")
		for k in 3000:
			if not game._strategy_pending:
				break
			await process_frame
		var key: String = game.TRACK_KEYS[game.track_picker.selected]
		for n in 2:
			t0 = Time.get_ticks_msec()
			game._start_race()
			var ok := await _race_ready()
			print("QA flip race %d on %s: started %s in %d ms" % [n + 1, key, ok, Time.get_ticks_msec() - t0])
			if ok:
				game.race.set_autopilot(true)
				await _wait(90)
				await _shot("flip_%d_race" % (n + 2))
				game._set_paused(true)
				game._pause_action("menu")
				await _wait(20)
				if game.race:
					game._return_to_setup()
				await _wait(20)
				print("QA flip back in menu: page %s, race %s, track %s" % [game.active_menu_page, game.race != null, game.TRACK_KEYS[game.track_picker.selected]])
	game.queue_free()
	await process_frame
	print("QA done")
	quit()
