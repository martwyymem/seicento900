## Front-end flow check (dev tool): drives the real game scene through a quick race (pause, restart with
## the HUD redrawing mid-load, retire, results, race again, back to the menu) and a championship round
## with simulated qualifying, then reports script errors from the log. Saves go to the dev sandbox.
## godot --headless --path godot -s tests/_ui_flow.gd
extends SceneTree

var game

func _wait(frames: int) -> void:
	for k in frames:
		await process_frame

func _wait_start() -> void:
	for k in 6000:
		await process_frame
		if not game._starting:
			if game.race == null:
				print("FLOW: no race started: ", game.status_label.text)
			return
	print("FLOW: race start never finished")

func _start() -> void:
	await _wait(30)
	for k in 6000:
		if not game._strategy_pending:
			break
		await process_frame
	game._start_race()
	await _wait_start()

func _step(label: String) -> void:
	var r: Race = game.race
	print("FLOW %s: race %s phase %s t=%.1f, world race %s, hud visible %s, results %s" % [label,
		"-" if r == null else str(r.get_instance_id()), "-" if r == null else r.phase, 0.0 if r == null else r.race_time,
		"-" if game.world_view.race == null else str(game.world_view.race.get_instance_id()), game.hud.visible,
		game.result_panel.visible])

func _initialize() -> void:
	Brain.use_disk = false
	game = load("res://ui/game.tscn").instantiate()
	root.add_child(game)
	await _wait(20)
	game.opponents_picker.value = 5
	game.laps_picker.value = 2
	game.race_control_toggle.button_pressed = true
	await _wait(30) # the strategist refresh is queued
	# a quick race, a double press on START RACE
	for k in 6000:
		if not game._strategy_pending:
			break
		await process_frame
	game._start_race()
	await process_frame
	game._start_race() # a second press while it loads does nothing
	await _wait_start()
	await _wait(120)
	_step("racing")
	game._set_paused(true)
	game._pause_action("restart")
	for k in 40:
		game.hud.flagbar.queue_redraw()
		game.hud.pitwall.queue_redraw()
		await process_frame
	await _wait_start()
	await _wait(60)
	_step("restarted")
	if game.race:
		game._set_paused(true)
		game._pause_action("retire")
	await _wait(60)
	_step("retired")
	for k in 3000:
		if game.result_panel.visible:
			break
		await process_frame
	_step("results")
	await _start() # race again
	await _wait(30)
	_step("race again")
	game._return_to_setup()
	await _wait(30)
	_step("menu")
	# a championship round, qualifying simulated
	game._toggle_mode()
	game.quali_picker.select(1)
	await _start()
	await _wait(30)
	_step("quali sheet")
	await _start()
	await _wait(60)
	_step("round 1")
	if game.race:
		game._set_paused(true)
		game._pause_action("retire")
	for k in 3000:
		if game.result_panel.visible:
			break
		await process_frame
	_step("round results")
	game._return_to_setup()
	await _wait(30)
	_step("menu again")
	game._toggle_mode()
	game.queue_free()
	await _wait(5)
	print("FLOW done")
	quit()
