## Ghost car screenshots (dev tool, run in a window): drives two laps of Fiat Track on autopilot to record a
## ghost, then shoots the third lap with the ghost and the HUD's record row, the results, the set-up page's
## record line and the Information page. Shots go to /tmp/ghost/.
## godot --path godot -s tests/_ghost_shot.gd
extends SceneTree

var game

func _wait(frames: int) -> void:
	for k in frames:
		await process_frame

func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/ghost/%s.png" % tag)
	print("shot ", tag)

func _initialize() -> void:
	Brain.use_disk = false
	LapRecords.use_disk = false
	LapRecords.count_autopilot = true
	game = load("res://ui/game.tscn").instantiate()
	root.add_child(game)
	await _wait(20)
	game.track_picker.select(game.TRACK_KEYS.find("fiat"))
	game.track_picker.item_selected.emit(game.TRACK_KEYS.find("fiat"))
	game.opponents_picker.value = 0
	game.laps_picker.value = 5
	game.mandatory_stop_toggle.button_pressed = false
	await _wait(30)
	for k in 6000:
		if not game._strategy_pending:
			break
		await process_frame
	game._start_race()
	for k in 6000:
		await process_frame
		if not game._starting:
			break
	var race: Race = game.race
	race.set_autopilot(true)
	game.paused = true
	var input := Race.PlayerInput.new()
	var p := race.player
	while p.lap_times.size() < 2 or race.race_time - p.lap_start < float(OS.get_environment("INTO") if OS.has_environment("INTO") else "25"):
		race.step(game.TICK, input)
		game.lap_records.tick()
	print("record ", game.lap_records.ghost_time, " gap ", game.lap_records.gap())
	game.paused = false
	await _wait(90)
	await _shot("chase")
	game._cycle_camera()
	await _wait(60)
	await _shot("cam2")
	game._cycle_camera()
	game._cycle_camera()
	await _wait(60)
	await _shot("cam4")
	game.paused = true
	while race.phase != "finished":
		race.step(game.TICK, input)
		game.lap_records.tick()
	game._show_results()
	await _wait(30)
	await _shot("results")
	game._return_to_setup()
	await _wait(30)
	var scroll: Node = game.record_label
	while scroll and not scroll is ScrollContainer:
		scroll = scroll.get_parent()
	if scroll:
		scroll.ensure_control_visible(game.record_label)
	await _wait(10)
	await _shot("setup")
	game._show_information_page()
	await _wait(30)
	await _shot("info")
	quit()
