## QA probe (dev tool, run windowed): screenshots every UI skin (main menu, quick race set-up, circuit info,
## options, in-race HUD) into /tmp/qa_skins/, then the fast circuit-flip / race / menu / same circuit again flow.
## godot --path godot --audio-driver Dummy -s tests/_qa_skins.gd
## PART=overlap (the layout pass, into /tmp/qa_skins/overlap/): every skin's menus and campaign briefing; the
## race HUD under green with an overtake call, a split, the autopilot chip and the full key help, then with the
## safety car out and a pass attempted (no overtake call may show); both at 16:9, at the 1.3 interface size
## and at 4:3; then the open world HUD with banners, the event card, a district name and the skill chain.
## PART=overlap godot --path godot --audio-driver Dummy -s tests/_qa_skins.gd
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
	if only == "overlap":
		await _overlap_shots()
	game.queue_free()
	await process_frame
	print("QA done")
	quit()

const OVERLAP_OUT := "/tmp/qa_skins/overlap"
## [tag, interface size index (UI_SCALES), aspect index (ASPECTS)]
const OVERLAP_VIEWS := [["169", 1, 0], ["ui130", 3, 0], ["43", 1, 4]]

func _oshot(tag: String) -> void:
	await _wait(4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [OVERLAP_OUT, tag])
	print("QA shot overlap/", tag)

func _view(v: Array) -> void:
	game._on_ui_scale_selected(v[1])
	game._on_aspect_selected(v[2])
	await _wait(10)

func _overlap_shots() -> void:
	DirAccess.make_dir_recursive_absolute(OVERLAP_OUT)
	# the pickers save to graphics.cfg: put the player's own choices back at the end
	var had := [game.graphics_ui_scale, game.graphics_aspect, game.graphics_retro_mode]
	# menus, the circuit info map and the campaign briefing in every skin and view
	for v in OVERLAP_VIEWS:
		await _view(v)
		for m in MODES:
			game._on_retro_selected(m)
			game._show_home()
			game._home_select(1, false)
			await _oshot("%s_m%d_1_home" % [v[0], m])
			game._activate_home_item()
			await _key(KEY_DOWN)
			await _oshot("%s_m%d_2_setup" % [v[0], m])
			game._show_information_page()
			await _oshot("%s_m%d_3_info" % [v[0], m])
			game._show_repair_page()
			await _oshot("%s_m%d_4_service" % [v[0], m])
			game.is_time_trial_mode = false
			game.is_rally_mode = false
			game.is_championship_mode = false
			game.is_campaign_mode = true
			game.campaign_stage_index = 6
			game._update_mode_view()
			game._show_setup_page()
			await _wait(8)
			await _oshot("%s_m%d_5_briefing" % [v[0], m])
			game.is_campaign_mode = false
			game._update_mode_view()
	await _view(OVERLAP_VIEWS[0])
	# the race HUD
	game._on_retro_selected(0)
	game._show_home()
	game._home_select(1, false)
	game._activate_home_item()
	game.opponents_picker.value = 10
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
		return
	game.race.set_autopilot(true)
	var t0 := Time.get_ticks_msec()
	while game.race.race_time < 20.0 and Time.get_ticks_msec() - t0 < 40000:
		await _wait(1)
	var hud: RaceHud = game.hud
	hud.toggle_help() # the full key help
	for phase in ["green", "sc"]:
		if phase == "sc" and game.race.rc:
			game.race.rc.deploy_sc("QA probe")
			await _wait(30)
		for v in OVERLAP_VIEWS:
			await _view(v)
			for m in MODES:
				game._on_retro_selected(m)
				# a pass: under green it's called, under the safety car it must not be
				hud._prev_player_pos = game.race.player.pos + 1
				hud._split_show = {"k": 1, "t": 61.25, "delta": 0.42, "until": game.race.race_time + 4.0}
				await _wait(3)
				if phase == "sc" and hud._overtake_timer > 0.0:
					print("QA FAIL: an overtake was called under the safety car")
				await _oshot("%s_m%d_hud_%s" % [v[0], m, phase])
	await _view(OVERLAP_VIEWS[0])
	game._on_retro_selected(0)
	game._set_paused(true)
	game._pause_action("menu")
	await _wait(20)
	if game.race:
		game._return_to_setup()
	await _wait(10)
	# the open world HUD with everything up at once
	if OpenWorld.available():
		game._start_campaign_mode()
		for k in 6000:
			if game.open_world and game.open_world.active and game.open_world.hud and not game.open_world.hud.loading.visible:
				break
			await process_frame
		var ow: OpenWorldHud = game.open_world.hud
		for v in OVERLAP_VIEWS:
			await _view(v)
			for m in MODES:
				game._on_retro_selected(m)
				for k in 3:
					ow.notify("DISCOVERED  ·  KOPALNIA WĘGLA KAMIENNEGO BRZESZCZE", "Szyb Andrzej, the old headframe over the Jawiszowice seam", OpenWorldHud.GOLD)
				ow.show_event("ACT II · REGIONAL CHAMPIONSHIP", "Stage 7: Kraków Royal Ring under the Wawel walls",
					"Eleven bots and a tight ring round the Planty. Trams share the road on Basztowa and the cobbles under Wawel are slick in the wet: plan one stop and look after the front tyres.",
					"ENTER  ▸  START STAGE", OpenWorldHud.ORANGE)
				ow.show_area("Osiedle Paderewskiego · Brzeszcze-Jawiszowice")
				ow.set_chain(4321, "DRIFT · NEAR MISS · AIR")
				await _wait(20)
				await _oshot("%s_m%d_world" % [v[0], m])
				ow.hide_event()
		await _view(OVERLAP_VIEWS[0])
		game.open_world.suspend()
		game._show_home()
	game._on_ui_scale_selected(had[0])
	game._on_aspect_selected(had[1])
	game._on_retro_selected(had[2])
