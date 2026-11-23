## DifficultyProfile (Options → Difficulty & Assists): the seven-step rival ladder against each event's authored
## level (monotonic AI pace, open-world fields, rally crews and drift targets; Average exactly as authored), the aids
## and the accessibility switches on a race (fuel off burns nothing, wear off wears nothing, cosmetic damage never
## retires a car, damage off not even dents), the fan multiplier, saving and loading, and the default profile being
## the game's behaviour before the profile existed.
extends RefCounted

var completed := false
var errors: Array[String] = []

func check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		errors.append("%s %s" % [what, detail])

func run() -> Array:
	var saved := DifficultyProfile.current.duplicate()
	DifficultyProfile.current = DifficultyProfile.defaults()
	_ladder()
	_race_field()
	_open_world_fields()
	_aids()
	_fuel_and_wear()
	_damage()
	_fans()
	_save_load()
	_defaults_are_old_behaviour()
	_rally_event()
	await _game_flow()
	DifficultyProfile.current = saved
	completed = true
	return errors

func _ladder() -> void:
	var n := DifficultyProfile.STEPS.size()
	check("seven rival steps", n == 7 and DifficultyProfile.SHIFT.size() == n and DifficultyProfile.STEP_FANS.size() == n
		and DifficultyProfile.STEP_NOTES.size() == n)
	for base in ["easy", "medium", "hard", "alien"]:
		var avg := DifficultyProfile.resolve(base, DifficultyProfile.AVERAGE)
		check("Average races %s exactly as authored" % base, avg.difficulty == base and float(avg.shift) == 0.0)
		check("no shift is the Race.DIFFICULTY row itself (%s)" % base, DifficultyProfile.race_params(base, 0.0) == Race.DIFFICULTY[base])
		var prev := {}
		var prev_lv := -INF
		for step in n:
			var r := DifficultyProfile.resolve(base, step)
			var lv := float(r.level)
			check("%s step %d: the level never falls" % [base, step], lv >= prev_lv - 1e-9, "(%.2f after %.2f)" % [lv, prev_lv])
			check("%s step %d: level = name + shift" % [base, step], is_equal_approx(DifficultyProfile.level_of(r.difficulty) + float(r.shift), lv))
			var p := DifficultyProfile.race_params(String(r.difficulty), float(r.shift))
			if not prev.is_empty():
				check("%s step %d: rivals no slower" % [base, step], float(p.skill) >= float(prev.skill) - 1e-9, "(%.4f < %.4f)" % [p.skill, prev.skill])
				check("%s step %d: no more mistakes" % [base, step], float(p.mistakes) <= float(prev.mistakes) + 1e-9)
				check("%s step %d: no more rubber band" % [base, step], float(p.band) <= float(prev.band) + 1e-9)
			prev = p
			prev_lv = lv
	# the ends move the field: Novice slower than the authored level, Unbeatable faster (up to alien)
	for base in ["easy", "medium", "hard"]:
		var lo := DifficultyProfile.race_params(String(DifficultyProfile.resolve(base, 0).difficulty), float(DifficultyProfile.resolve(base, 0).shift))
		var hi := DifficultyProfile.race_params(String(DifficultyProfile.resolve(base, 6).difficulty), float(DifficultyProfile.resolve(base, 6).shift))
		check("%s: Novice is easier than authored" % base, float(lo.skill) < float(Race.DIFFICULTY[base].skill))
		check("%s: Unbeatable is harder than authored" % base, float(hi.skill) > float(Race.DIFFICULTY[base].skill))
	check("Novice on an easy event goes under easy", float(DifficultyProfile.resolve("easy", 0).level) < 0.0)
	check("Unbeatable tops out at alien", DifficultyProfile.resolve("hard", 6).difficulty == "alien" and float(DifficultyProfile.resolve("hard", 6).shift) == 0.0)
	# Quick Race's ladder (baseline medium): Casual = Easy, Average = Medium, Expert = Hard, Unbeatable = Alien
	var quick := {1: "easy", 2: "medium", 4: "hard", 6: "alien"}
	for step in quick:
		var r := DifficultyProfile.resolve("medium", step)
		check("Quick Race step %d is %s" % [step, quick[step]], r.difficulty == quick[step] and float(r.shift) == 0.0, str(r))
	for i in 4:
		check("old picker %d keeps its level" % i, DifficultyProfile.resolve("medium", DifficultyProfile.LEGACY_STEP[i]).difficulty == DifficultyProfile.LEVELS[i])
	# drift targets: authored at Average, larger up the ladder
	check("drift tiers as authored at Average", DifficultyProfile.tier_scale(DifficultyProfile.shift_of(DifficultyProfile.AVERAGE)) == 1.0)
	for step in range(1, n):
		check("drift tiers grow at step %d" % step, DifficultyProfile.tier_scale(DifficultyProfile.shift_of(step)) >= DifficultyProfile.tier_scale(DifficultyProfile.shift_of(step - 1)))

## A race's field: the bots' mean skill climbs with the step (the same seed), and no shift is the old field.
func _race_field() -> void:
	var means := []
	for step in DifficultyProfile.STEPS.size():
		var st := RaceSettings.new()
		st.track = "fiat"
		st.opponents = 8
		var r := DifficultyProfile.resolve("medium", step)
		st.difficulty = r.difficulty
		st.difficulty_shift = r.shift
		var race := Race.new(st, null, 3)
		var sum := 0.0
		for c in race.cars:
			if not c.is_player:
				sum += c.skill
		means.append(sum / 8.0)
		if step == DifficultyProfile.AVERAGE:
			check("Average: the field's row is medium's", race.diff_params == Race.DIFFICULTY.medium)
		race.dispose()
	for i in range(1, means.size()):
		check("the field is faster at step %d" % i, float(means[i]) >= float(means[i - 1]) - 1e-9, "(%.4f vs %.4f)" % [means[i], means[i - 1]])
	check("Novice to Unbeatable spans a real gap", float(means[6]) - float(means[0]) > 0.04, "(%.4f .. %.4f)" % [means[0], means[6]])

## Open-world events: the street rivals' pace and drag times, the rally crews' stage times.
func _open_world_fields() -> void:
	var path := PackedVector2Array()
	for i in 60:
		path.append(Vector2(i * 50.0, sin(i * 0.4) * 40.0))
	var prev := -INF
	for step in DifficultyProfile.STEPS.size():
		var sr := StreetRivals.new(path, "stock", 5, 9, {"difficulty": "medium", "difficulty_shift": DifficultyProfile.shift_of(step)})
		var f := 0.0
		for rv in sr.rivals:
			f += float(rv.f)
		f /= 5.0
		check("street rivals no slower at step %d" % step, f >= prev - 0.01, "(%.3f after %.3f)" % [f, prev])
		check("street rivals never beat the reference driver at step %d" % step, sr.rivals.all(func(rv): return float(rv.f) <= 1.013))
		prev = f
	var avg_band: Vector2 = DifficultyProfile.band(StreetRivals.PACE_BANDS, "medium", 0.0)
	check("street band at Average is the authored one", avg_band == StreetRivals.PACE_BANDS.medium)
	var ev := {"difficulty": "medium", "rivals": 4, "stages": [{"path": path}]}
	var last := INF
	for step in DifficultyProfile.STEPS.size():
		ev["difficulty_shift"] = DifficultyProfile.shift_of(step)
		var times := MapMissions.rally_times(ev, "stock", 11)
		var best := INF
		for t in times:
			best = minf(best, float(t[0]))
		check("rally crews no slower at step %d" % step, best <= last + 1e-6, "(%.1f after %.1f)" % [best, last])
		last = best
	ev.erase("difficulty_shift")
	ev["difficulty_shift"] = 0.0
	var a := MapMissions.rally_times(ev, "stock", 11)
	ev.erase("difficulty_shift")
	check("rally crews at Average are as authored", a == MapMissions.rally_times(ev, "stock", 11))
	# a mission's drift target text follows the step
	DifficultyProfile.current.step = 6
	var hard_tiers := LiveEvents.reward({"length": 2000.0, "difficulty": "medium"}, 1, true, true)
	DifficultyProfile.current = DifficultyProfile.defaults()
	var avg_tiers := LiveEvents.reward({"length": 2000.0, "difficulty": "medium"}, 1, true, true)
	check("a live event pays more at Unbeatable", hard_tiers > avg_tiers, "(%d vs %d)" % [hard_tiers, avg_tiers])

func _aids() -> void:
	# each tier, read through RaceSettings.aid, is what the race always gave it
	for tier in ["full", "abs", "off"]:
		var st := RaceSettings.new()
		st.assists = tier
		var want: Dictionary = DifficultyProfile.TIER_AIDS[tier]
		for k in DifficultyProfile.AID_KEYS:
			check("%s tier: %s" % [tier, k], st.aid(k) == bool(want[k]))
		st.aids = DifficultyProfile.aids(DifficultyProfile.from_setup(DifficultyProfile.TIERS.find(tier), 0))
		for k in DifficultyProfile.AID_KEYS:
			check("%s tier as explicit aids: %s" % [tier, k], st.aid(k) == bool(want[k]))
	var full := RaceSettings.new()
	full.brake_assist = false
	check("braking assist still needs brake_assist", not full.aid("brake"))
	# one aid on its own: traction control off, the rest of full on, for the whole field
	var st := RaceSettings.new()
	st.track = "fiat"
	st.opponents = 2
	st.aids = {"tc": false}
	var race := Race.new(st, null, 2)
	check("aids: TC off on its own", not race.aid_tc and race.aid_abs and race.aid_esc and race.aid_steer and race.aid_brake)
	race.dispose()
	# presets
	for i in DifficultyProfile.PRESET_KEYS.size():
		var p := DifficultyProfile.with_preset(DifficultyProfile.defaults(), DifficultyProfile.PRESET_KEYS[i])
		check("preset %s reads back as itself" % DifficultyProfile.PRESET_KEYS[i], DifficultyProfile.preset_index(p) == i)
	var custom := DifficultyProfile.defaults()
	custom.tc = false
	check("a changed aid is Custom", DifficultyProfile.preset_index(custom) == 3 and DifficultyProfile.tier_index(custom) == 3)
	check("Beginner is the old Full assists", DifficultyProfile.tier_index(DifficultyProfile.with_preset(custom, "beginner")) == 0)
	check("Pro is the old Off", DifficultyProfile.tier_index(DifficultyProfile.with_preset(custom, "pro")) == 2)

## A race of a few laps' running with fuel use and tyre wear off: not a litre burnt, not a percent worn.
func _fuel_and_wear() -> void:
	var st := RaceSettings.new()
	st.track = "fiat"
	st.opponents = 3
	st.laps = 3
	var p := DifficultyProfile.defaults()
	p.fuel = false
	p.wear = false
	DifficultyProfile.apply_sim(st, p)
	check("fuel off: no burn, no refuelling", st.fuel_mult == 0.0 and not st.refuel)
	check("wear off: no wear", st.wear_mult == 0.0)
	check("fuel or wear off changes the plan", DifficultyProfile.alters_strategy(p))
	var race := Race.new(st, null, 4)
	race.set_autopilot(true)
	var fuel0 := []
	for c in race.cars:
		fuel0.append(c.fuel)
	var idle := Race.PlayerInput.new()
	for i in 120 * 90: # 90 s of racing, most of a lap of the Fiat track
		race.step(1.0 / 120.0, idle)
	check("the race ran", race.phase == "racing" and race.player.lap + race.player.s / race.track.L > 0.5, "(%s, lap %d s %.0f)" % [race.phase, race.player.lap, race.player.s])
	for i in race.cars.size():
		var c: RaceCar = race.cars[i]
		check("car %d burnt no fuel" % c.id, c.fuel == float(fuel0[i]), "(%.3f -> %.3f)" % [fuel0[i], c.fuel])
		check("car %d wore no tyres" % c.id, float(c.tyre.wear) == 1.0, "(%.4f)" % float(c.tyre.wear))
	race.dispose()
	# the strategist plans such a race with no fuel stops
	var strat := Strategy.new(CarModel.new(), Tyres.new())
	var plans := strat.plan({"track": Race.get_track("gp"), "laps": 12, "wet": 0.0, "wear_mult": 0.0, "fuel_mult": 0.0,
		"rules": {"mandatory_stop": false, "two_compounds": false, "refuel": false}, "crew": "club", "parallel": false})
	check("a no-fuel, no-wear race plans without a stop", not plans.is_empty() and int(plans[0].stops) == 0, str(plans.slice(0, 1)))

func _damage() -> void:
	# cosmetic: even a rally stage (always mechanical by its rules) never slows or retires a car
	var st := RaceSettings.new()
	Rally.configure_stage(st, {"track": "fiat", "from": 0.0, "to": 0.0, "surface": "tarmac", "weather": "dry", "hour": 9.0})
	var p := DifficultyProfile.defaults()
	p.damage = "cosmetic"
	DifficultyProfile.apply_sim(st, p)
	var race := Race.new(st, null, 1)
	check("cosmetic: no mechanical damage on a rally stage", not race.mechanical_damage)
	var wrecked := race.rc.hurt(race.player, 30.0, true, 0.9)
	check("cosmetic: a huge hit neither wrecks nor retires", not wrecked and not race.player.dnf and race.player.damage == 0.0 and race.player.wheel_off < 0)
	check("cosmetic: it still dents", float(race.player.dents.front) > 0.5)
	race.dispose()
	# off: not even a dent
	st = RaceSettings.new()
	st.track = "gp"
	st.opponents = 1
	p.damage = "off"
	DifficultyProfile.apply_sim(st, p)
	race = Race.new(st, null, 1)
	race.rc.hurt(race.player, 25.0, true, 0.9)
	check("off: no dent, no scuff, no bent wheel", race.player.scuff == 0.0 and float(race.player.dents.front) == 0.0 and Array(race.player.wheel_bend).all(func(w): return float(w) == 0.0))
	race.dispose()
	# full: a circuit race gets mechanical damage
	st = RaceSettings.new()
	st.track = "gp"
	st.opponents = 1
	p.damage = "full"
	DifficultyProfile.apply_sim(st, p)
	race = Race.new(st, null, 1)
	check("full: mechanical damage on a circuit", race.mechanical_damage)
	race.dispose()

func _fans() -> void:
	var d := DifficultyProfile.defaults()
	check("the default pays standard fans", DifficultyProfile.fan_multiplier(d) == 1.0 and DifficultyProfile.fan_text(d) == "Standard fans")
	var base := FanLevels.stage_reward(3, 1, 3, true)
	for step in DifficultyProfile.STEPS.size():
		var p := d.duplicate()
		p.step = step
		check("step %d pays its share" % step, is_equal_approx(DifficultyProfile.fan_multiplier(p), float(DifficultyProfile.STEP_FANS[step])))
		if step > 0:
			var q := d.duplicate()
			q.step = step - 1
			check("a harder step pays more (%d)" % step, DifficultyProfile.fan_multiplier(p) > DifficultyProfile.fan_multiplier(q))
	check("the lowest step still pays most of it", float(DifficultyProfile.STEP_FANS[0]) >= 0.75)
	var pro := DifficultyProfile.with_preset(d, "pro")
	check("aids off pay more", DifficultyProfile.fan_multiplier(pro) > 1.3, "(%.2f)" % DifficultyProfile.fan_multiplier(pro))
	var easy := d.duplicate()
	easy.fuel = false
	easy.wear = false
	easy.damage = "off"
	check("accessibility switches never cost fans", DifficultyProfile.fan_multiplier(easy) == 1.0)
	DifficultyProfile.current = d.duplicate()
	DifficultyProfile.current.step = 6
	var hi := FanLevels.stage_reward(3, 1, 3, true)
	DifficultyProfile.current = d.duplicate()
	DifficultyProfile.current.step = 0
	var lo := FanLevels.stage_reward(3, 1, 3, true)
	DifficultyProfile.current = DifficultyProfile.defaults()
	check("a stage pays 1.5x at Unbeatable", hi == int(float(base) * 1.5) or absi(hi - int(float(base) * 1.5)) <= 1, "(%d vs %d)" % [hi, base])
	check("a stage pays 0.8x at Novice", absi(lo - int(float(base) * 0.8)) <= 1, "(%d vs %d)" % [lo, base])
	check("the default pays exactly as before", FanLevels.stage_reward(3, 1, 3, true) == base)

func _save_load() -> void:
	var file := SaveData.path("difficulty_test.cfg")
	DifficultyProfile.current = DifficultyProfile.defaults()
	DifficultyProfile.current.step = 5
	DifficultyProfile.current.tc = false
	DifficultyProfile.current.line = "braking"
	DifficultyProfile.current.fuel = false
	DifficultyProfile.current.damage = "cosmetic"
	var want := DifficultyProfile.current.duplicate()
	DifficultyProfile.save_profile(file)
	DifficultyProfile.current = DifficultyProfile.defaults()
	check("the profile loads", DifficultyProfile.load_profile(file))
	check("it comes back as saved", DifficultyProfile.current == want, str(DifficultyProfile.current))
	# a hand-edited file: only plain values of the right kind are taken, the rest fall back to the default
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "step", 99)
	cfg.set_value("profile", "abs", "yes")
	cfg.set_value("profile", "line", "sideways")
	cfg.set_value("profile", "damage", Vector2(1, 2))
	cfg.set_value("profile", "wear", false)
	cfg.save(file)
	DifficultyProfile.load_profile(file)
	var c := DifficultyProfile.current
	check("a bad file is cleaned", int(c.step) == 6 and bool(c.abs) and String(c.line) == "full" and String(c.damage) == "event" and not bool(c.wear), str(c))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	check("no file: nothing loaded", not DifficultyProfile.load_profile(file))
	DifficultyProfile.current = DifficultyProfile.defaults()

## The default profile, and the one built from an old save's set-up page, change nothing.
func _defaults_are_old_behaviour() -> void:
	var d := DifficultyProfile.defaults()
	check("defaults: Average", int(d.step) == DifficultyProfile.AVERAGE and DifficultyProfile.is_default(d))
	check("an old save on Full assists and automatic is the default", DifficultyProfile.from_setup(0, 0) == d)
	var old := DifficultyProfile.from_setup(2, 1)
	check("an old save on Off and manual keeps them", DifficultyProfile.tier_index(old) == 2 and old.shifting == "manual" and int(old.step) == DifficultyProfile.AVERAGE)
	var a := RaceSettings.new()
	var b := RaceSettings.new()
	DifficultyProfile.apply_sim(b, d)
	for prop in ["fuel_mult", "wear_mult", "refuel", "mechanical_damage", "auto_rejoin", "difficulty", "difficulty_shift", "assists", "aids", "damage_mode"]:
		check("default profile leaves %s" % prop, a.get(prop) == b.get(prop), "(%s vs %s)" % [a.get(prop), b.get(prop)])
	# a rally stage keeps its own mechanical damage under the default
	var r := RaceSettings.new()
	Rally.configure_stage(r, {"track": "fiat", "from": 0.0, "to": 0.0, "surface": "tarmac", "weather": "dry", "hour": 9.0})
	DifficultyProfile.apply_sim(r, d)
	var race := Race.new(r, null, 1)
	check("default: a rally stage still has mechanical damage", race.mechanical_damage)
	race.dispose()
	check("default: the rally field is as before", Rally.make_rivals("hard", 5) == Rally.make_rivals("hard", 5, Rally.RIVALS, 0.0))

func _rally_event() -> void:
	var ev := RallyEvent.new("sprint", 42, "", DifficultyProfile.shift_of(6))
	var back := RallyEvent.from_dict(ev.to_dict())
	check("a rally keeps its crews' shift", is_equal_approx(back.difficulty_shift, ev.difficulty_shift) and back.rivals == ev.rivals)
	var plain := RallyEvent.new("sprint", 42)
	var mean := func(rv: Array) -> float:
		var s := 0.0
		for x in rv:
			s += float(x.skill)
		return s / maxf(rv.size(), 1)
	check("Unbeatable crews are quicker", float(mean.call(ev.rivals)) > float(mean.call(plain.rivals)))
	var old := plain.to_dict()
	old.erase("difficulty_shift")
	check("an old rally save loads as authored", RallyEvent.from_dict(old).difficulty_shift == 0.0)

## The page in the game: reached from Options, every change saved and the set-up pickers following it, a per-race
## override on the set-up page, the campaign on the profile itself, Esc back to Options. The sandbox's saves are
## put back as they were.
func _game_flow() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var files := ["race_settings.cfg", "championship.json", DifficultyProfile.FILE]
	var before := {}
	for f in files:
		var path := SaveData.path(f)
		before[f] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveData.path(DifficultyProfile.FILE)))
	var game = load("res://ui/game.tscn").instantiate()
	tree.root.add_child(game)
	for i in 3:
		await tree.process_frame
	check("game: a sandbox without a profile starts on the defaults", DifficultyProfile.current == DifficultyProfile.defaults())
	check("game: Quick Race starts at Average", game.difficulty_picker.selected == DifficultyProfile.AVERAGE)
	game._show_options_page()
	var button: Button = game.options_column.find_child("DifficultyButton", true, false)
	check("game: Options has the Difficulty & Assists button", button != null)
	if button:
		button.pressed.emit()
	check("game: the button opens the page", game.active_menu_page == "difficulty" and game.difficulty_panel.visible)
	check("game: the page has controls to focus", game._difficulty_focus_items().size() >= 12)
	(game.difficulty_controls.step as MenuSelector).step(1)
	check("game: the step moves the profile", int(DifficultyProfile.current.step) == 3)
	check("game: and Quick Race's picker", game.difficulty_picker.selected == 3)
	check("game: and it is saved", FileAccess.file_exists(SaveData.path(DifficultyProfile.FILE)))
	check("game: the fan reward shows", String(game.difficulty_fans_label.text).contains("+10%"), game.difficulty_fans_label.text)
	(game.difficulty_controls.preset as MenuSelector).select(2)
	game._on_difficulty_changed("preset")
	check("game: Pro puts manual and no aids on the set-up page", game.assists_picker.selected == 2 and game.gearbox_picker.selected == 1)
	check("game: Pro hides the racing line", DifficultyProfile.current.line == "off")
	(game.difficulty_controls.preset as MenuSelector).select(1)
	game._on_difficulty_changed("preset")
	check("game: Default (ABS + TC) is Custom on the set-up picker", game.assists_picker.selected == 3)
	var st := RaceSettings.new()
	game._apply_race_aids(st)
	check("game: Custom races on the profile's own aids", st.aids == DifficultyProfile.aids(DifficultyProfile.current) and st.aid("tc") and not st.aid("esc"))
	game.assists_picker.select(0) # this race only: full assists
	game._apply_race_aids(st)
	check("game: a per-race override wins in Quick Race", st.assists == "full" and st.aids.is_empty())
	check("game: and leaves the profile alone", DifficultyProfile.preset_index(DifficultyProfile.current) == 1)
	var was_campaign: bool = game.is_campaign_mode
	game.is_campaign_mode = true
	game._apply_race_aids(st)
	check("game: the campaign drives on the profile", st.aid("tc") and not st.aid("esc") and st.gearbox == "auto")
	game.is_campaign_mode = was_campaign
	(game.difficulty_controls.fuel as CheckButton).button_pressed = false
	check("game: the fuel switch reaches the profile", not bool(DifficultyProfile.current.fuel))
	check("game: the strategy plans then have no fuel use", float(game._plan_opts(Race.get_track("gp"), 6, 2.0).fuel_mult) == 0.0)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	game._show_difficulty_page("options")
	game._input(esc)
	check("game: Esc goes back to Options", game.active_menu_page == "options", game.active_menu_page)
	game._show_difficulty_page("advanced")
	game._difficulty_go_back()
	check("game: BACK returns to the set-up page it came from", game.active_menu_page == "advanced")
	game._show_difficulty_page("options")
	var reset: Button = game.difficulty_panel.find_child("DifficultyReset", true, false)
	if reset:
		reset.pressed.emit()
	check("game: RESET TO DEFAULTS", DifficultyProfile.current == DifficultyProfile.defaults() and game.assists_picker.selected == 0 and game.difficulty_picker.selected == DifficultyProfile.AVERAGE)
	game.queue_free()
	await tree.process_frame
	for f in files:
		var path := SaveData.path(f)
		if before[f] == null:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		else:
			var fa := FileAccess.open(path, FileAccess.WRITE)
			fa.store_buffer(before[f])
			fa.close()
	DifficultyProfile.current = DifficultyProfile.defaults()
