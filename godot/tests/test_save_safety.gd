## Saves and settings a player may have been handed. ConfigFile.load parses Variant text, which accepts
## `Resource("path")` / `Object(...)`: a shared cfg naming a crafted .tres with an embedded script would run it. Every
## user:// ConfigFile read goes through SaveData.load_cfg/load_cfg_into, which refuses such a file (checked here with a
## real payload script, first loading it the unsafe way to prove the test would notice). The JSON save loaders
## (championship, rally, campaign, open world, the AI's memory, lap records) survive garbage and wrong types.
extends RefCounted

var completed := false
var errors: Array[String] = []

const PAYLOAD := "res://tests/save_safety_payload.gd"
const GARBAGE := ["[]", "\"x\"", "5", "null", "{}", "{\"stages\": 5}", "[1, 2, 3]", "{\"table\": 5}", "{\"tracks\": 7, \"v\": 1}",
	"{\"tracks\": {\"a\": 5}, \"v\": 1}", "{\"v\": [1], \"tracks\": {}}", "{not json at all"]

func check(ok: bool, what: String) -> void:
	if not ok:
		errors.append(what)

func run() -> Array:
	SaveData.sandboxed() # (makes the sandbox folder these files go in)
	_cfg_loading()
	_json_garbage()
	_world_progress()
	_stores()
	_game_loaders()
	completed = true
	return errors

# ---------------- ConfigFile ----------------
func _evil_tres(name: String) -> String:
	var path := SaveData.SANDBOX + name
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("[gd_resource type=\"Resource\" load_steps=2 format=3]\n\n[ext_resource type=\"Script\" path=\"%s\" id=\"1\"]\n\n[resource]\nscript = ExtResource(\"1\")\n" % PAYLOAD)
	f.close()
	return path

func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func _ran() -> bool:
	var r: bool = Engine.has_meta("save_safety_ran")
	Engine.remove_meta("save_safety_ran")
	return r

func _cfg_loading() -> void:
	Engine.remove_meta("save_safety_ran")
	var cfg_path := SaveData.SANDBOX + "save_safety_test.cfg"
	# positive control: the unsafe load really does run a crafted resource's script, so the checks below mean something
	var control := _evil_tres("save_safety_control.tres")
	_write(cfg_path, "[graphics]\nquality=1\nr=Resource(\"%s\")\n" % control)
	var raw := ConfigFile.new()
	raw.load(cfg_path)
	check(_ran(), "positive control: ConfigFile.load should have run the payload script (the test cannot show the fix otherwise)")
	var variants := {
		"Resource": "r=Resource(\"%s\")",
		"spaced": "r = Resource  (\"%s\")",
		"control char": "r=Resource\u0001(\"%s\")",
		"comment between": "r=Resource ; hi\n\t(\"%s\")",
		"ExtResource": "r=ExtResource(\"%s\")",
		"Object": "r=Object(Resource,\"script\":null)",
		"nested": "r={\"a\": [Resource(\"%s\")]}",
	}
	var n := 0
	for label in variants:
		n += 1
		var tres := _evil_tres("save_safety_evil_%d.tres" % n)
		var body: String = variants[label] % tres if "%s" in variants[label] else variants[label]
		_write(cfg_path, "[graphics]\nquality=1\n%s\n" % body)
		check(SaveData.has_object_syntax(FileAccess.get_file_as_string(cfg_path)), "%s: object syntax not detected" % label)
		var cfg := SaveData.load_cfg(cfg_path)
		check(not _ran(), "%s: the payload script ran while loading a settings file" % label)
		check(cfg.get_sections().is_empty(), "%s: a refused file should give an empty ConfigFile" % label)
		var into := ConfigFile.new()
		check(SaveData.load_cfg_into(into, cfg_path) == ERR_INVALID_DATA and into.get_sections().is_empty(), "%s: load_cfg_into should refuse with ERR_INVALID_DATA" % label)
	# normal settings still load, including every value kind the game saves
	var ok := ConfigFile.new()
	ok.set_value("graphics", "quality", 2)
	ok.set_value("graphics", "vsync", true)
	ok.set_value("graphics", "scale", 0.75)
	ok.set_value("paint", "stock", "Rosso Corsa")
	ok.set_value("skies", "res://sky/a.hdr", {"stamp": 5, "sun": Vector3(1, 2, 3), "tint": Color(0.1, 0.2, 0.3), "dir": Vector2(1, 0)})
	ok.set_value("hud", "list", [1, "two", 3.0])
	ok.set_value("note", "text", "Resource is just a word here, and so is Object")
	ok.save(cfg_path)
	var back := SaveData.load_cfg(cfg_path)
	check(int(back.get_value("graphics", "quality", -1)) == 2 and bool(back.get_value("graphics", "vsync", false)) and absf(float(back.get_value("graphics", "scale", 0.0)) - 0.75) < 1e-6,
		"a normal settings file should load")
	check(String(back.get_value("paint", "stock", "")) == "Rosso Corsa", "a saved paint should load")
	var sky: Dictionary = back.get_value("skies", "res://sky/a.hdr", {})
	check(sky.get("sun") == Vector3(1, 2, 3) and sky.get("tint") == Color(0.1, 0.2, 0.3), "cache values (Vector3, Color) should load")
	check(String(back.get_value("note", "text", "")).begins_with("Resource is just a word"), "a string that merely contains the word should load")
	check(SaveData.load_cfg(SaveData.SANDBOX + "save_safety_missing.cfg").get_sections().is_empty(), "a missing file gives an empty ConfigFile")
	check(SaveData.load_cfg_into(ConfigFile.new(), SaveData.SANDBOX + "save_safety_missing.cfg") == ERR_FILE_NOT_FOUND, "a missing file is ERR_FILE_NOT_FOUND")
	# the call sites: a game-side reader given an evil file runs nothing
	var garage := SaveData.path(CarCatalog.PAINT_SAVE)
	var saved_garage = FileAccess.get_file_as_string(garage) if FileAccess.file_exists(garage) else null
	_write(garage, "[paint]\nstock=Resource(\"%s\")\n" % _evil_tres("save_safety_evil_garage.tres"))
	CarCatalog.saved_paint("stock", Color.RED)
	CarCatalog.save_paint("stock", Color.RED)
	check(not _ran(), "CarCatalog's garage.cfg read ran a payload script")
	if saved_garage == null:
		DirAccess.remove_absolute(garage)
	else:
		_write(garage, saved_garage)
	DirAccess.remove_absolute(cfg_path)

# ---------------- JSON loaders ----------------
func _json_garbage() -> void:
	for text in GARBAGE:
		var parsed = SaveData.parse_json(text)
		var c := SaveData.clean_championship(parsed)
		check(c.is_empty() or (c.get("table") is Dictionary and c.get("round") is int), "championship cleaner kept %s" % text)
		if parsed is Dictionary:
			check(Campaign.migrate(Campaign.clean_progress(parsed)) is Dictionary, "campaign cleaner failed on %s" % text)
		check(SaveData.clean_carried_car(parsed) is Dictionary, "carried-car cleaner failed on %s" % text)
	var messy := SaveData.clean_championship({"round": [2], "scored": "yes", "table": {"a": 5, "b": {"points": [1], "name": [], "wins": "3"}},
		"config": 7, "car": {"parts": 3, "pull": {}}})
	check(not messy.is_empty() and int(messy.round) == -1 and messy.scored == false, "a championship with wrong-typed round/scored should clean to defaults (%s)" % [messy])
	check(messy.table.size() == 1 and messy.table.b.points == 0 and messy.table.b.wins == 3 and messy.table.b.name == "?", "table entries should be rebuilt typed (%s)" % [messy.table])
	check(not messy.has("config") and messy.car.parts.is_empty(), "a non-Dictionary config is dropped and the car cleaned (%s)" % [messy])
	var good := {"round": 3, "scored": true, "table": {"7": {"id": 7, "name": "A", "number": 7, "color": "ff0000", "is_player": true, "points": 25, "wins": 1}},
		"config": {"calendar": ["monza"]}, "car": {"parts": {"Engine": 0.5}, "pull": 0.1, "used": 4, "serviced": false}}
	var kept := SaveData.clean_championship(good)
	check(kept.round == 3 and kept.scored and kept.table["7"] == good.table["7"] and kept.config == good.config and kept.car == good.car, "a valid championship should survive cleaning (%s)" % [kept])
	# the campaign file, on a file of this suite's own
	var saved_file := Campaign.save_file
	Campaign.save_file = "test_save_safety_campaign.json"
	for text in GARBAGE + ["{\"unlocked\": [1], \"best_pos\": 3, \"trophies\": 9, \"arc\": {}, \"missions\": []}"]:
		_write(SaveData.path(Campaign.save_file), text)
		var prog := Campaign.load_progress()
		check(prog.get("unlocked", 0) is int and prog.get("trophies", []) is Array and prog.get("best_pos", {}) is Dictionary,
			"campaign progress from %s has wrong types: %s" % [text, prog])
	DirAccess.remove_absolute(SaveData.path(Campaign.save_file))
	Campaign.save_file = saved_file

func _world_progress() -> void:
	for text in GARBAGE + ["{\"pos\": 5, \"roads\": 3, \"mods\": \"x\", \"landmarks\": {}, \"tips\": 1, \"hour\": [1], \"fans\": {}, \"weather_dynamic\": []}",
			"{\"pos\": [\"a\", null, {}], \"roads\": [[1], \"b\"]}"]:
		var w := WorldProgress.from_dict(SaveData.parse_json(text))
		check(w != null and w.roads is Dictionary, "WorldProgress.from_dict failed on %s" % text)
	var w := WorldProgress.from_dict({"pos": [1.5, 2.5, 0.5], "roads": [3, 4], "fans": 12, "hour": 7.5, "weather_dynamic": false, "mods": ["a"]})
	check(w.has_pos and w.pos == Vector2(1.5, 2.5) and w.roads.size() == 2 and w.fans == 12 and w.hour == 7.5 and not w.weather_dynamic and w.mods.has("a"),
		"a valid open-world save should still load")

func _stores() -> void:
	var prev_brain = Brain._store
	var prev_laps = LapRecords._store
	var brain_path := SaveData.path("brain.json")
	var laps_path := SaveData.path(LapRecords.FILE)
	var saved := {}
	for p in [brain_path, laps_path, brain_path + ".bad", laps_path + ".bad"]:
		saved[p] = FileAccess.get_file_as_string(p) if FileAccess.file_exists(p) else null
	var was_brain := Brain.use_disk
	var was_laps := LapRecords.use_disk
	Brain.use_disk = true
	LapRecords.use_disk = true
	for text in GARBAGE + ["{\"v\": %d, \"tracks\": {\"monza\": [1]}}" % Brain.VER, "{\"v\": %d, \"tracks\": {\"monza\": {\"dry\": 5}}}" % LapRecords.VER]:
		var is_laps_only: bool = "\"dry\": 5" in text
		_write(brain_path, text)
		_write(laps_path, text)
		Brain._store = null
		LapRecords._store = null
		var b := Brain.load_store()
		var l := LapRecords.load_store()
		check(b.get("tracks") is Dictionary and ((b.tracks as Dictionary).is_empty() or is_laps_only) and l.get("tracks") is Dictionary and (l.tracks as Dictionary).is_empty(),
			"Brain/LapRecords did not fall back to a fresh store for %s" % text)
		check(LapRecords.record("monza", "dry").is_empty() and Brain.dec([[1], "x", null, 2], 4).size() == 4, "reading a fresh store failed for %s" % text)
	# not even valid JSON: set aside as .bad
	_write(brain_path, "{broken")
	Brain._store = null
	Brain.load_store()
	check(FileAccess.file_exists(brain_path + ".bad") and not FileAccess.file_exists(brain_path), "an unreadable brain.json should be kept as brain.json.bad")
	# a valid store is kept
	_write(laps_path, JSON.stringify({"v": LapRecords.VER, "tracks": {"monza": {"dry": {"t": 81.5, "car": "stock"}}}, "ghost": {"solo": true, "race": false}}))
	LapRecords._store = null
	check(is_equal_approx(float(LapRecords.record("monza", "dry").get("t", 0.0)), 81.5), "a valid lap-records file should load")
	for p in saved:
		if saved[p] == null:
			DirAccess.remove_absolute(p)
		else:
			_write(p, saved[p])
	Brain.use_disk = was_brain
	LapRecords.use_disk = was_laps
	Brain._store = prev_brain
	LapRecords._store = prev_laps

# ---------------- Game: championship, rally, settings ----------------
func _game_loaders() -> void:
	var names := ["championship.json", "championship.json.bad", "rally.json", "rally.json.bad", "graphics.cfg", "race_settings.cfg"]
	var saves := {}
	for f in names:
		var p := SaveData.path(f)
		saves[p] = FileAccess.get_file_as_string(p) if FileAccess.file_exists(p) else null
	var game = load("res://ui/game.tscn").instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(game)
	# an evil graphics.cfg / race_settings.cfg is not run
	Engine.remove_meta("save_safety_ran")
	_write(SaveData.path("graphics.cfg"), "[graphics]\nquality=Resource(\"%s\")\n" % _evil_tres("save_safety_evil_gfx.tres"))
	_write(SaveData.path("race_settings.cfg"), "[race]\nlaps=Resource(\"%s\")\n" % _evil_tres("save_safety_evil_race.tres"))
	game._load_graphics_settings()
	game._load_race_settings()
	game._save_graphics_settings()
	check(not _ran(), "Game's settings loaders ran a payload script")
	# championship
	var cpath := SaveData.path("championship.json")
	for text in GARBAGE + ["{\"round\": [1], \"table\": {}, \"config\": 5, \"car\": 9}",
			"{\"round\": 99, \"table\": {}}", "{\"round\": 1, \"scored\": [], \"table\": {\"a\": {\"points\": {}}}, \"config\": {\"opponents\": [3], \"calendar\": 4}}"]:
		_write(cpath, text)
		game.champ_data = {}
		game._load_championship()
		check(game.champ_data.get("table") is Dictionary and game.champ_data.get("round") is int and game._calendar() is Array and not game._calendar().is_empty(),
			"championship loader left a bad state for %s: %s" % [text, game.champ_data])
		check(game._sorted_standings() is Array and (game._season().opponents is int or game._season().opponents is float), "championship readers failed after loading %s" % text)
		DirAccess.remove_absolute(cpath + ".bad")
	_write(cpath, "[1,")
	game._load_championship()
	check(FileAccess.file_exists(cpath + ".bad") and game.champ_data.round == 0, "an unreadable championship.json should be set aside as .bad")
	# rally
	var rpath := SaveData.path("rally.json")
	var key: String = Rally.EVENTS[0].key
	var rally_garbage := GARBAGE + ["{\"key\": \"%s\", \"results\": 5, \"stage_index\": [1], \"parts\": 3, \"player\": \"x\", \"service_log\": 4, \"car\": 7}" % key,
		"{\"key\": \"%s\", \"stage_index\": 2, \"results\": [{\"player\": 5, \"rivals\": 3}]}" % key,
		"{\"key\": [1]}", "{\"key\": \"%s\", \"results\": [{\"player\": {\"time\": [], \"penalty\": 0, \"penalties\": [], \"dnf\": false, \"splits\": []}, \"rivals\": []}]}" % key]
	for text in rally_garbage:
		_write(rpath, text)
		game.rally_event = null
		game._load_rally()
		var ev: RallyEvent = game.rally_event
		check(ev != null and ev.stage_index <= ev.results.size() and ev.stage_index <= ev.stage_count(), "rally loader left a bad state for %s" % text)
		if ev != null:
			check(ev.standings().size() > 0 and (ev.results.is_empty() or ev.stage_results(0).size() > 0), "rally readers failed after loading %s" % text)
		check(game.rally_car is Dictionary, "rally car is not a Dictionary after %s" % text)
		DirAccess.remove_absolute(rpath + ".bad")
	# a rally save that round-trips
	game.rally_event = null
	game._new_rally(key)
	game._rally().record_stage(100.0, [["cut", 5.0]], false, [30.0, 60.0, 100.0], [{"id": 1, "time": 101.0, "splits": [], "dnf": false, "note": ""}, {"id": 2, "time": null, "splits": [], "dnf": true, "note": "off"}])
	game._save_rally()
	game.rally_event = null
	game._load_rally()
	check(game.rally_event.results.size() == 1 and game.rally_event.stage_index == 1 and game.rally_event.standings().size() > 0, "a valid rally save should round-trip")
	game.free()
	for p in saves:
		if saves[p] == null:
			DirAccess.remove_absolute(p)
		else:
			_write(p, saves[p])
