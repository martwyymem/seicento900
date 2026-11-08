## Changing the circuit on the set-up page does not hitch: a quick ◂ ▸ run through circuits whose Track is not built
## yet never builds one on the main thread (the name shows at once, the map and length once the worker's Track
## lands), the set-up map is not rebuilt for the same circuit again (a weather change), and the map's surroundings
## come from the shared, prepared cache.
extends RefCounted

const ART := preload("res://scripts/ui/menu_track_art.gd")

var completed := false
var errors: Array[String] = []

func check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		errors.append("%s %s" % [what, detail])

func run() -> Array:
	var tree := Engine.get_main_loop() as SceneTree
	var game = load("res://ui/game.tscn").instantiate()
	tree.root.add_child(game)
	for i in 3:
		await tree.process_frame
	game._show_setup_page()
	await tree.process_frame
	var map = game.information_map

	# three circuits as on a first visit, before the prefetcher got to them
	var keys := ["fiat", "oswiecim", "bor"]
	for k in keys:
		Race._track_cache.erase(k)
		ART._envs.erase(k)
	var worst := 0.0
	for k in keys:
		var i: int = game.TRACK_KEYS.find(k)
		var t := Time.get_ticks_usec()
		game.track_picker.select(i)
		game._select_track(i)
		worst = maxf(worst, (Time.get_ticks_usec() - t) / 1000.0)
		check("picking %s builds no Track on the main thread" % k, not Race._track_cache.has(k))
	check("each press returns well inside a Track build (0.15 s+)", worst < 60.0, "%.1f ms" % worst)
	check("the page waits for the circuit it rests on", game._track_waiting == "bor", game._track_waiting)
	check("the map stays empty until bor's Track lands", map.track == null)
	var bor_name: String = Track.load_def("bor").display_name.to_upper()
	check("the summary names the circuit at once", String(game.menu_car_summary.text).begins_with(bor_name), game.menu_car_summary.text)

	var frames := 0
	while (map.track == null or not ART.has_env("bor")) and frames < 900:
		await tree.process_frame
		frames += 1
	check("bor's Track lands off the main thread and fills the map", map.track != null and map.track == Race._track_cache.get("bor"), "after %d frames" % frames)
	check("the summary then gives the lap length", " KM" in String(game.menu_car_summary.text) and not "…" in String(game.menu_car_summary.text), game.menu_car_summary.text)
	check("the map draws bor's prepared surroundings", map._map_edges.size() > 0 and not map._map_env.is_empty())

	# the strategist waits for the Track and the picker's rest, then plans once
	frames = 0
	while game._strategy_pending and frames < 900:
		await tree.process_frame
		frames += 1
	check("the strategist plans for bor once the selection rests", not game._strategy_pending, "after %d frames" % frames)

	# the same circuit again (a weather change, the page shown again) rebuilds nothing
	var n: int = map.rebuilds
	game.weather_picker.select(1)
	game._update_information_page()
	game._update_information_page()
	check("a weather change does not rebuild the set-up map", map.rebuilds == n, "%d → %d" % [n, map.rebuilds])
	var built_on: Track = map.track
	game._select_track(game.TRACK_KEYS.find("bor"))
	check("re-picking the same circuit keeps its map", map.rebuilds == n and map.track == built_on)

	# an already-built circuit fills in within the press
	var gp: Track = Race.get_track("gp")
	game.track_picker.select(game.TRACK_KEYS.find("gp"))
	game._select_track(game.TRACK_KEYS.find("gp"))
	check("a built circuit's map updates at once", map.track == gp)
	check("a built circuit leaves nothing waiting", game._track_waiting == "" or game._track_waiting == "gp" and not ART.has_env("gp"))

	game.queue_free()
	await tree.process_frame
	completed = true
	return errors
