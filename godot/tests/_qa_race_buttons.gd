## QA probe (dev tool, run WINDOWED): every RACE button starts a race, by real key events and by synthetic
## gamepad events. For each entry (quick race, time trial, rally, championship, campaign stage via ENTER STAGE,
## the open world's stage beacon) it opens the mode from the home strip (Enter / pad A), presses the page's
## start button (focused + Enter / pad START), waits for the lights to go out, checks that cars move, saves a
## screenshot, retires, waits for the results, records which button is focused there, presses BACK TO MENU
## and checks where it lands. One line per step, "BTN ..." prefix; "BTN FAIL" lines are bugs.
## Env: PART (comma list of: quick,tt,rally,champ,camp,world; default all), VIA (kb,pad; default both),
## OUT (screenshot dir). Run (muted, parked bottom-right, always on top):
## godot --path godot --audio-driver Dummy --always-on-top --resolution 1280x720 --position 2140,1390 -s tests/_qa_race_buttons.gd
extends SceneTree

const Guard := preload("res://tests/_qa_save_guard.gd")

var game
var out := ""
var fails := 0

func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d

func _wait(frames: int) -> void:
	for k in frames:
		if game and game.paused:
			game._set_paused(false)
		if game:
			game._app_focused = true
		await process_frame

func _fail(msg: String) -> void:
	fails += 1
	print("BTN FAIL ", msg)

func _key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)
		await _wait(2)

func _pad(button: JoyButton) -> void:
	for pressed in [true, false]:
		var e := InputEventJoypadButton.new()
		e.button_index = button
		e.pressed = pressed
		Input.parse_input_event(e)
		await _wait(2)

func _shot(name: String) -> void:
	await _wait(2)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := "%s/%s.png" % [out, name]
	img.save_png(path)
	print("BTN shot ", path)

func _wait_started(label: String) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 40000:
		await _wait(1)
		if game.race != null and not game._starting:
			return true
		if game.result_panel.visible and game.race == null:
			return false
	_fail("%s: race never started (status '%s')" % [label, game.status_label.text])
	return false

## From a started race to the lights going out, cars moving, a shot, then retire to the results.
func _drive_race(label: String) -> void:
	var r: Race = game.race
	r.set_autopilot(true)
	var t0 := Time.get_ticks_msec()
	while r.phase == "countdown" and Time.get_ticks_msec() - t0 < 30000:
		await _wait(1)
	if r.phase != "racing":
		_fail("%s: lights never went out (phase %s)" % [label, r.phase])
	var s_player := r.player.s
	var others: Array = r.cars.filter(func(c: RaceCar) -> bool: return c != r.player)
	var s_other: float = others[0].s if not others.is_empty() else 0.0
	var rt := r.race_time
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 3500:
		await _wait(1)
	var moved: float = r.player.s - s_player
	var moved_other: float = others[0].s - s_other if not others.is_empty() else -1.0
	print("BTN %s: racing, track %s, race_time %.1f->%.1f, player moved %.1f m (speed %.1f m/s), rival moved %.1f m, hud %s, mode camp=%s champ=%s rally=%s tt=%s quali=%s" % [
		label, r.track.name, rt, r.race_time, moved, r.player.speed, moved_other, game.hud.visible,
		game.is_campaign_mode, game.is_championship_mode, game.is_rally_mode, game.is_time_trial_mode, game.quali_session])
	if moved < 5.0 or r.race_time <= rt + 1.0:
		_fail("%s: car not moving (moved %.1f m, race_time %.1f -> %.1f)" % [label, moved, rt, r.race_time])
	if not game.hud.visible:
		_fail("%s: HUD hidden in a running race" % label)
	await _shot(label)
	game._set_paused(true)
	game._pause_action("retire")

func _wait_results(label: String) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 40000:
		await _wait(1)
		if game.result_panel.visible:
			await _wait(20)
			var owner: Control = game.get_viewport().gui_get_focus_owner()
			print("BTN %s: results visible, focus on '%s'" % [label, owner.text if owner is Button else str(owner)])
			await _shot(label + "_results")
			return true
	_fail("%s: results never appeared" % label)
	return false

func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text.contains(text):
		return node
	for c in node.get_children():
		var b := _find_button(c, text)
		if b != null:
			return b
	return null

func _back_to_menu(label: String) -> void:
	var b := _find_button(game.result_panel, "BACK TO MENU")
	if b == null:
		_fail("%s: no BACK TO MENU button on the results" % label)
		return
	b.pressed.emit()
	await _wait(40)
	print("BTN %s: back -> page '%s', race %s, results %s, open world %s" % [label, game.active_menu_page,
		game.race, game.result_panel.visible, game.open_world != null and game.open_world.visible])

func _home_to(id: String, via: String) -> void:
	game._show_home()
	await _wait(10)
	var idx: int = game.FRONT_MENU.map(func(e: Dictionary) -> String: return e.id).find(id)
	game._home_select(idx, false)
	await _wait(5)
	if via == "kb":
		await _key(KEY_ENTER)
	else:
		await _pad(JOY_BUTTON_A)
	await _wait(10)

func _press_start(btn: Button, via: String) -> void:
	if via == "kb":
		btn.grab_focus()
		await _wait(3)
		await _key(KEY_ENTER)
	else:
		await _pad(JOY_BUTTON_START)

func _strategy_idle() -> void:
	for k in 3000:
		if not game._strategy_pending:
			break
		await _wait(1)

func _generic(id: String, via: String, label: String) -> void:
	await _home_to(id, via)
	if game.active_menu_page != "setup":
		_fail("%s: home -> '%s' left page '%s'" % [label, id, game.active_menu_page])
		return
	await _strategy_idle()
	await _press_start(game.setup_race_button, via)
	if not await _wait_started(label):
		return
	await _drive_race(label)
	if await _wait_results(label):
		await _back_to_menu(label)

func _champ(via: String, label: String) -> void:
	await _home_to("championship", via)
	game.quali_picker.select(1) # simulated qualifying: the first press shows the sheet
	await _strategy_idle()
	await _press_start(game.setup_race_button, via)
	await _wait(60)
	print("BTN %s: after first press: race %s quali_session %s results %s page '%s'" % [label, game.race, game.quali_session, game.result_panel.visible, game.active_menu_page])
	await _shot(label + "_first")
	if game.result_panel.visible and game.race == null or (game.race != null and game.quali_session):
		if game.race != null and game.quali_session:
			await _drive_race(label + "_quali")
			await _wait_results(label + "_quali")
		# the quali sheet's primary button starts the race
		var owner: Control = game.get_viewport().gui_get_focus_owner()
		if owner is Button:
			(owner as Button).pressed.emit()
		await _wait(5)
	if not await _wait_started(label):
		return
	await _drive_race(label)
	if await _wait_results(label):
		await _back_to_menu(label)

func _campaign(via: String, label: String) -> void:
	# the briefing page's ENTER STAGE (the open world is bypassed: the page is what a build without the map shows)
	game.is_campaign_mode = true
	game.is_championship_mode = false
	game.is_rally_mode = false
	game.is_time_trial_mode = false
	game.campaign_stage_index = 0
	game._update_mode_view()
	game._show_setup_page()
	await _wait(20)
	print("BTN %s: briefing page '%s', ENTER STAGE visible %s, RACE visible %s" % [label, game.active_menu_page,
		game.campaign_start_button.is_visible_in_tree(), game.setup_race_button.visible])
	await _press_start(game.campaign_start_button, via)
	if not await _wait_started(label):
		return
	await _drive_race(label)
	if await _wait_results(label):
		await _back_to_menu(label)

func _world(label: String) -> void:
	# the open world's stage beacon: OpenWorld emits stage_requested, game starts the race and ends back at the beacon
	game._show_home()
	await _wait(5)
	game._start_campaign_mode()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 60000 and not (game.open_world != null and game.open_world.visible and not game._starting):
		await _wait(1)
	await _wait(60)
	print("BTN %s: open world up %s" % [label, game.open_world != null and game.open_world.visible])
	await _shot(label + "_world")
	game._on_world_stage(0)
	if not await _wait_started(label):
		return
	await _drive_race(label)
	if await _wait_results(label):
		await _back_to_menu(label)
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 60000 and not (game.open_world != null and game.open_world.visible):
		await _wait(1)
	print("BTN %s: after results open world visible %s" % [label, game.open_world != null and game.open_world.visible])

func _initialize() -> void:
	Brain.use_disk = false
	Guard.backup() # the dev sandbox is shared with other agents' tests: put the saves back at the end
	Guard.clear(["championship.json", "rally.json"]) # start from stage 1 / round 1
	out = _env("OUT", "/tmp/qa/buttons")
	DirAccess.make_dir_recursive_absolute(out)
	game = load("res://ui/game.tscn").instantiate()
	root.add_child(game)
	await _wait(40)
	game.opponents_picker.value = 3
	game.laps_picker.value = 2
	var parts := _env("PART", "quick,tt,rally,champ,camp,world").split(",")
	var vias := _env("VIA", "kb,pad").split(",")
	for via in vias:
		for p in parts:
			var label := "%s_%s" % [p, via]
			print("BTN === ", label)
			match p:
				"quick": await _generic("quick_race", via, label)
				"tt": await _generic("time_trial", via, label)
				"rally": await _generic("rally", via, label)
				"champ": await _champ(via, label)
				"camp": await _campaign(via, label)
				"world":
					if via == "kb":
						await _world(label)
	print("BTN done, %d failures" % fails)
	game.queue_free()
	Guard.restore()
	await process_frame
	quit()
