## Retro-style capture probe (dev tool, run windowed: headless never draws). Starts a race in the real game
## scene, freezes it, and saves the same frame (HUD included) in every retro post-processing mode, then does
## the same for a wet night race. OUT sets the folder (default /tmp/retro_shots).
## godot --path godot --audio-driver Dummy -s tests/_retro_shots.gd
extends SceneTree

var game

func _wait(frames: int) -> void:
	for k in frames:
		if game and game.paused:
			game._set_paused(false) # a probe window loses focus, which pauses the race
		game._app_focused = true
		await process_frame

func _race(track: String, weather: int, hour: float, run_s: float) -> void:
	game.track_picker.select(game.TRACK_KEYS.find(track))
	game.weather_picker.select(weather)
	game.start_hour_picker.value = hour
	game.opponents_picker.value = 12
	game.grid_picker.select(1)
	game.laps_picker.value = 3
	await _wait(10)
	for k in 3000:
		if not game._strategy_pending:
			break
		await process_frame
	print("start %s pending=%s status=%s" % [track, game._strategy_pending, game.status_label.text])
	game._start_race()
	for k in 3000:
		await _wait(1)
		if game.race != null and not game._starting:
			break
	print("race %s started=%s" % [track, game.race != null])
	game.race.set_autopilot(true)
	var t0 := Time.get_ticks_msec()
	while game.race.race_time < run_s and Time.get_ticks_msec() - t0 < 25000:
		await _wait(1)

func _shoot(out: String, tag: String) -> void:
	Engine.time_scale = 0.0 # the race (and the shimmer clock) stand still while every mode is drawn
	for m in game.retro_pipeline.MODE_NAMES.size():
		game.retro_pipeline.set_mode(m)
		await _wait(4)
		await RenderingServer.frame_post_draw
		var path := "%s/%s_mode%d.png" % [out, tag, m]
		root.get_texture().get_image().save_png(path)
		print("saved ", path)
	game.retro_pipeline.set_mode(0)
	Engine.time_scale = 1.0

func _initialize() -> void:
	Brain.use_disk = false
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "/tmp/retro_shots"
	DirAccess.make_dir_recursive_absolute(out)
	game = load("res://ui/game.tscn").instantiate()
	root.add_child(game)
	await _wait(30)
	if OS.get_environment("DAY") != "0":
		await _race("monza", 0, 14.0, 9.0)
		await _shoot(out, "day")
	if OS.get_environment("NIGHT") != "0":
		await _race("gp", 1, 21.5, 9.0)
		await _shoot(out, "night")
	game.queue_free()
	await process_frame
	quit()
