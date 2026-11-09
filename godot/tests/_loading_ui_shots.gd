## Windowed probe: the race loader (LoadingScreen) and the open-world cover (OpenWorldCover) as the player sees them, at 16:9 and
## at other aspect ratios, saved as PNGs.
##   godot --path godot --audio-driver Dummy --always-on-top -s tests/_loading_ui_shots.gd -- [out dir]
## Env: TRACKS (comma list of track keys, default "monza,tokyo"), HOURS (comma list, same length), WEATHERS (same), ASPECTS
## (comma list of ASPECTS indices, default "1,4,3": 16:9, 4:3, 21:9; "0" is Auto, the window's own shape), COVERS (1: also the
## open-world cover's stills 0..SHOTS-1), WIN (window size, default 1600x900), PROGRESS (0..1, default 0.6).
extends SceneTree

func _wait(n: int) -> void:
	for k in n:
		paused = false
		await process_frame

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("saved ", path)

func _initialize() -> void:
	Brain.use_disk = false
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp/loading_ui"
	DirAccess.make_dir_recursive_absolute(out)
	var tracks := (OS.get_environment("TRACKS") if OS.get_environment("TRACKS") != "" else "monza,tokyo").split(",", false)
	var hours := OS.get_environment("HOURS").split(",", false)
	var weathers := OS.get_environment("WEATHERS").split(",", false)
	var aspects := (OS.get_environment("ASPECTS") if OS.get_environment("ASPECTS") != "" else "1,4,3").split(",", false)
	var win := Vector2i(1600, 900)
	if OS.get_environment("WIN") != "":
		var p := OS.get_environment("WIN").split("x")
		win = Vector2i(int(p[0]), int(p[1]))
	var progress := float(OS.get_environment("PROGRESS")) if OS.get_environment("PROGRESS") != "" else 0.6
	await process_frame
	root.size = win
	var game = load("res://ui/game.tscn").instantiate()
	root.add_child(game)
	await _wait(30)
	for a in aspects:
		game._on_aspect_selected(int(a))
		await _wait(6)
		for i in tracks.size():
			var key := String(tracks[i])
			var hour := float(hours[i]) if i < hours.size() else 17.0
			var weather := String(weathers[i]) if i < weathers.size() else "dry"
			var track := Race.get_track(key)
			game.loading_screen.open([track.name, "6 laps"], "Circuit Length", "%.2f km" % (track.L / 1000.0), {
				"track": key, "hour": hour, "weather": weather, "mode": "race", "facts": [["FIELD", "16 cars"]]})
			game.loading_screen.set_progress(progress)
			await _wait(8)
			await _shot("%s/loader_%s_a%s.png" % [out, key, a])
		game.loading_screen.hide()
		if OS.get_environment("COVERS") == "1":
			var cover := OpenWorldCover.new()
			game.add_child(cover)
			var spec: CarSpec = CarModel.new().spec
			for k in OpenWorldCover.SHOTS.size():
				cover.open(spec, "Fiat Seicento", k)
				cover.set_status("building the town", 0.5)
				await _wait(8)
				await _shot("%s/cover_%d_a%s.png" % [out, k + 1, a])
			cover.queue_free()
	quit()
