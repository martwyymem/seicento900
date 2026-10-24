## Campaign flow check (dev tool, run windowed: headless never draws, so the race never loads):
## main menu → CAMPAIGN (Enter) → ENTER STAGE (Enter) → a race of the stage runs → retire → results →
## progress saved. Keys go in through Input like a player's. Saves go to the dev sandbox.
## godot --path godot --audio-driver Dummy -s tests/_campaign_flow.gd
extends SceneTree

var game
var t0 := 0

func _key(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		root.push_input(ev)
		await process_frame

func _wait(frames: int) -> void:
	for k in frames:
		if game and game.paused:
			game._set_paused(false) # a probe window loses focus, which pauses the race
		await process_frame

func _say(label: String) -> void:
	var r: Race = game.race
	print("CAMPAIGN %s (%.1f s): page %s, campaign %s, champ %s, stage %d, race %s, track %s, laps %s, weather %s, opponents %s, phase %s, t=%.1f, results %s" % [
		label, (Time.get_ticks_msec() - t0) / 1000.0, game.active_menu_page, game.is_campaign_mode, game.is_championship_mode,
		game.campaign_stage_index, r != null, "-" if r == null else r.s.track, "-" if r == null else str(r.s.laps),
		"-" if r == null else r.s.weather, "-" if r == null else str(r.s.opponents), "-" if r == null else r.phase,
		0.0 if r == null else r.race_time, game.result_panel.visible])

func _initialize() -> void:
	t0 = Time.get_ticks_msec()
	Brain.use_disk = false
	var f := FileAccess.open(SaveData.path("campaign.json"), FileAccess.WRITE) # a fresh campaign, at stage 1
	f.store_string(JSON.stringify({"unlocked": 0, "best_pos": {}, "trophies": []}))
	f.close()
	game = load("res://ui/game.tscn").instantiate()
	root.add_child(game)
	await _wait(30)
	game._home_select(game.FRONT_MENU.map(func(e): return e.id).find("campaign"), false)
	await _key(KEY_ENTER)
	await _wait(10)
	var owner: Control = game.get_viewport().gui_get_focus_owner()
	_say("briefing (focus %s)" % ("-" if owner == null else (owner.text if owner is Button else owner.get_class())))
	await _key(KEY_ENTER)
	for k in 1500:
		await _wait(1)
		if game.race != null and not game._starting:
			break
	await _wait(180)
	_say("racing")
	if game.race:
		game.race.approximate_finish() # project the rest of the race from the pace so far, still running
		game._show_results()
	await _wait(5)
	_say("results")
	var heads: Array = game.result_scroll.find_children("*", "Label", true, false).slice(0, 3).map(func(l): return l.text)
	print("CAMPAIGN results text: ", heads)
	var btns: Array = game.result_scroll.find_children("*", "Button", true, false).map(func(b): return b.text)
	print("CAMPAIGN results buttons: ", btns)
	print("CAMPAIGN progress: ", load("res://scripts/sim/campaign.gd").load_progress())
	game._return_to_setup()
	await _wait(10)
	_say("back to briefing")
	game.campaign_stage_picker.select(1)
	game._select_campaign_stage(1) # locked: the briefing stays on stage 1
	print("CAMPAIGN locked stage refused: ", game.campaign_stage_index == 0 and game.campaign_stage_picker.selected == 0, ", title ", game.setup_title_label.text)
	await _key(KEY_ESCAPE)
	await _wait(5)
	_say("after Esc")
	game.queue_free()
	await process_frame
	print("CAMPAIGN done")
	quit()

