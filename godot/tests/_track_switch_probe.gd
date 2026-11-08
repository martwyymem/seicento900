## Where a circuit change on the set-up page spends its main-thread time, per circuit, headless:
##   timeout 600 godot --headless --path godot -s tests/_track_switch_probe.gd
## TRACKS: comma list (default: every circuit). WARM=1 prefetches every Track first (the menu's
## background prefetcher would have by then); otherwise the first visit pays for the Track build.
## PICK=1 also times the whole picker step (track_picker.select + the item_selected handler); a cold circuit is
## then built off the main thread, and the probe reports when it lands. ENV=1 prepares every circuit map's
## surroundings first (as the prefetcher leaves them). "map" is always a forced rebuild of the set-up map.
extends SceneTree

func _ms(t: int) -> float:
	return (Time.get_ticks_usec() - t) / 1000.0

func _initialize() -> void:
	var game = load("res://ui/game.tscn").instantiate()
	root.add_child(game)
	for i in 10:
		await process_frame
	game._show_setup_page() # the circuit map draws only while the set-up page shows it
	for i in 3:
		await process_frame
	var keys: Array = game.TRACK_KEYS
	if OS.get_environment("TRACKS") != "":
		keys = Array(OS.get_environment("TRACKS").split(","))
	if OS.get_environment("WARM") == "1":
		for k in game.TRACK_KEYS:
			Race.get_track(k)
	if OS.get_environment("CAL") == "1": # also the strategist's calibration (as the prefetcher leaves it)
		for k in keys:
			var tc: Track = Race.get_track(k)
			if tc.cal.is_empty():
				tc.cal = Strategy.new(CarModel.new(), Tyres.new()).calibrate(tc)
	if OS.get_environment("ENV") == "1":
		for k in keys:
			game.MENU_TRACK_ART.store_env(k, game.MENU_TRACK_ART.prepare_env(k))
	for key in keys:
		var idx: int = game.TRACK_KEYS.find(key)
		var cold: bool = not Race._track_cache.has(key)
		var t := Time.get_ticks_usec()
		var t_pick := 0.0
		if OS.get_environment("PICK") == "1":
			# the picker first, as the player sees it (a cold circuit is then built off the main thread)
			game.track_picker.select(idx)
			game._select_track(idx)
			t_pick = _ms(t)
			if cold:
				var waited := Time.get_ticks_usec()
				while not Race._track_cache.has(key) and _ms(waited) < 10000.0:
					await process_frame
				print("  %s landed after %.0f ms (built on the main thread: %s)" % [key, _ms(waited), "no" if _ms(waited) > 1.0 else "yes"])
		else:
			game.track_picker.select(idx)
		t = Time.get_ticks_usec()
		var tr: Track = Race.get_track(key)
		var t_track := _ms(t)
		game.information_map._built = [] # forced: the same circuit again would rebuild nothing
		t = Time.get_ticks_usec()
		game.information_map.set_track(tr, true)
		var t_map := _ms(t)
		t = Time.get_ticks_usec()
		game.menu_home_art.set_track(tr)
		var t_art := _ms(t)
		t = Time.get_ticks_usec()
		game._update_menu_car_summary()
		var t_sum := _ms(t)
		t = Time.get_ticks_usec()
		game._update_ai_memory()
		var t_ai := _ms(t)
		t = Time.get_ticks_usec()
		game._update_information_page()
		var t_info := _ms(t)
		# the strategist's plan for the page (deferred to the frame after the change in the game)
		var t_strat := -1.0
		if not tr.cal.is_empty():
			t = Time.get_ticks_usec()
			game._strategy_pending = true
			game._strategy_rest_msec = 0 # time the plan, not the picker's rest
			await game._refresh_strategy()
			t_strat = _ms(t)
		# (the map's _draw runs in a later frame; headless frame times are paced, so it is not timed here)
		print("TRACK %-13s %s get_track %7.1f  pick %7.1f  map %7.1f  art %6.1f  summary %6.1f  ai %5.1f  info %7.1f  strategy %7.1f ms" % [
			key, "cold" if cold else "warm", t_track, t_pick, t_map, t_art, t_sum, t_ai, t_info, t_strat])
		await process_frame
	game.queue_free()
	await process_frame
	quit()
