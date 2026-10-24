## Track-switch cost in the front-end, headless (CPU only; headless draws nothing):
##   godot --headless --path godot -s tests/_switch_probe.gd
## WORLD=1: just race_world.set_track per track (env TRACKS, comma list).
## Otherwise: the real game scene, the set-up page's circuit picker stepped like a player would.
extends SceneTree

func _ms(t: int) -> float:
	return (Time.get_ticks_usec() - t) / 1000.0

func _initialize() -> void:
	var keys: PackedStringArray = (OS.get_environment("TRACKS") if OS.get_environment("TRACKS") != "" else "gp,monaco,nordschleife,spa,tokyo,krakow,gp,monaco").split(",")
	if OS.get_environment("WORLD") == "1":
		var world = load("res://ui/race_world.tscn").instantiate()
		root.add_child(world)
		await process_frame
		for key in keys:
			var t := Time.get_ticks_usec()
			var tr: Track = Race.get_track(key)
			var t_track := _ms(t)
			t = Time.get_ticks_usec()
			world.set_track(tr)
			print("WORLD %-14s get_track %7.1f  set_track %7.1f ms" % [key, t_track, _ms(t)])
		quit()
		return
	var game = load("res://ui/game.tscn").instantiate()
	root.add_child(game)
	for i in 30:
		await process_frame
	# WAIT: seconds on the menu before the first step (the background prefetch gets going meanwhile)
	var t_wait := Time.get_ticks_msec() + int(float(OS.get_environment("WAIT") if OS.get_environment("WAIT") != "" else "0") * 1000.0)
	while Time.get_ticks_msec() < t_wait:
		await process_frame
	var picker = game.track_picker
	# a player tapping ▸ through the list: one step every 0.15 s, then resting; the worst frame per step
	var start: int = picker.selected
	for step in int(OS.get_environment("STEPS") if OS.get_environment("STEPS") != "" else "6"):
		var t := Time.get_ticks_usec()
		picker.step(1, true)
		var t_select := _ms(t)
		var worst := 0.0
		var t_end := Time.get_ticks_msec() + 150
		while Time.get_ticks_msec() < t_end:
			t = Time.get_ticks_usec()
			await process_frame
			worst = maxf(worst, _ms(t))
		print("STEP %-14s select %7.1f ms  worst frame after %7.1f ms" % [game.TRACK_KEYS[picker.selected], t_select, worst])
	var worst := 0.0
	var total := Time.get_ticks_usec()
	var t_end := Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < t_end:
		var t := Time.get_ticks_usec()
		await process_frame
		worst = maxf(worst, _ms(t))
	print("REST worst frame %7.1f ms (3D world built for: %s, strategy pending %s)" % [worst,
		game.world_view.track.key if game.world_view.track else "-", game._strategy_pending])
	quit()
