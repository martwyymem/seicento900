## Campaign rework B1 + B2: the rival car-class ladder (mixed-class fields that simulate and draw each car as what
## it is), back-half grids, the stages' own pace, and the adaptive field (big wins tighten it, failed tries still
## ease it down to Easy), with the save's new fields sanitized and old saves still loading.
extends RefCounted

var completed := false
var errors: Array[String] = []

func check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		errors.append("%s %s" % [what, detail])

func run() -> Array:
	var saved_profile := DifficultyProfile.current.duplicate()
	var saved_file := Campaign.save_file
	DifficultyProfile.current = DifficultyProfile.defaults()
	Campaign.save_file = "campaign_ladder_test.json"
	Campaign.reset_progress()
	_ladder_definitions()
	_field_classes_deal()
	_one_make_unchanged()
	_mixed_field_build()
	_mixed_race_pace()
	_mixed_visual_keys()
	Campaign.reset_progress()
	_failure_easing()
	Campaign.reset_progress()
	_big_win_tightening()
	Campaign.reset_progress()
	_save_sanitizing()
	_win_margin()
	var path := ProjectSettings.globalize_path(SaveData.path(Campaign.save_file))
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	Campaign.save_file = saved_file
	DifficultyProfile.current = saved_profile
	completed = true
	return errors

## Every stage names a class and a field that adds up; classes never go down the campaign; the field is the expected
## class, the one below or the one above, with fewer cars from above than the target place (an expected-class car can
## still make it); a car of the expected class is open by then; stages 1-12 start in the back half, further back
## act by act; the Goliath stays an all-Hypercar grid from pole.
func _ladder_definitions() -> void:
	var last_class := 0
	var act_depth := {}
	for i in Campaign.STAGES.size():
		var st: Dictionary = Campaign.STAGES[i]
		var tag := "stage %d (%s)" % [i + 1, String(st.id)]
		var cls := String(st.get("class", ""))
		check("%s: class is a CAR_CLASSES entry" % tag, Campaign.CAR_CLASSES.has(cls), "(%s)" % cls)
		var ci := Campaign.CLASS_ORDER.find(cls)
		check("%s: the class ladder never steps down" % tag, ci >= last_class, "(%s after %s)" % [cls, Campaign.CLASS_ORDER[last_class]])
		last_class = maxi(last_class, ci)
		var riv: Dictionary = st.get("rivals", {})
		var total := 0
		var above := 0
		for k in riv:
			check("%s: rival car %s is in the catalogue" % [tag, k], CarCatalog.is_key(String(k)))
			total += int(riv[k])
			var rc := Campaign.CLASS_ORDER.find(Campaign.class_of(String(k)))
			check("%s: rival %s within one class of %s" % [tag, k, cls], absi(rc - ci) <= 1)
			if rc > ci:
				above += int(riv[k])
		check("%s: rivals add up to the opponents" % tag, total == int(st.opponents), "(%d vs %d)" % [total, int(st.opponents)])
		check("%s: fewer cars from the class above than the target place" % tag, above < int(st.target_pos), "(%d above, P%d)" % [above, int(st.target_pos)])
		if cls != "city" and cls != "hypercar":
			var open_by := false
			for m in Missions.MISSIONS:
				var car := String(m.get("reward_car", ""))
				if car != "" and Campaign.class_of(car) == cls and Campaign.index_of(String(m.after)) < i:
					open_by = true
			check("%s: a %s car is won by a mission before it" % [tag, cls], open_by)
		var n := int(st.opponents) + 1
		var grid := String(st.grid)
		if i < 12: # stages 1-12 (B2): the back half of the grid
			check("%s: grid is a set slot" % tag, grid.begins_with("p") and grid.substr(1).is_valid_int(), "(%s)" % grid)
			var slot := grid.substr(1).to_int()
			check("%s: starts in the back half" % tag, slot > n / 2.0 and slot <= n, "(P%d of %d)" % [slot, n])
			check("%s: target is ahead of the start" % tag, int(st.target_pos) < slot)
			var act := int(st.act)
			var d: Array = act_depth.get(act, [])
			d.append(float(slot) / n)
			act_depth[act] = d
	for a in [2, 3]:
		check("act %d starts further back than act %d on average" % [a, a - 1], _mean(act_depth.get(a, [])) > _mean(act_depth.get(a - 1, [])),
			"(%.2f vs %.2f)" % [_mean(act_depth.get(a, [])), _mean(act_depth.get(a - 1, []))])
	var gol: Dictionary = Campaign.STAGES[Campaign.index_of("stage_10")]
	check("the Goliath keeps car_class hypercar", String(gol.get("car_class", "")) == "hypercar")
	check("the Goliath is an all-Hypercar field", gol.rivals == {"hypercar": 11})
	check("the Goliath starts from pole", String(gol.grid) == "pole")
	check("the Goliath does not take the heat", not gol.get("adaptive", true))
	# the Nordschleife's field runs past Alien: skill_boost in full at the Alien level, fading a level down, none elsewhere
	var eif := Campaign.get_stage(Campaign.index_of("stage_eifel"))
	check("the Nordschleife is raced at the Alien level", float(eif.level) >= 3.0 - 0.0001, str(eif.level))
	check("skill_boost: full at Alien", is_equal_approx(Campaign.skill_boost(eif), float(eif.boost)), str(Campaign.skill_boost(eif)))
	check("skill_boost: half a level down gives half", is_equal_approx(Campaign.skill_boost({"boost": 0.06, "level": 2.5}), 0.03))
	check("skill_boost: none at Hard or below, or without a boost", Campaign.skill_boost({"boost": 0.06, "level": 2.0}) == 0.0 and Campaign.skill_boost({"level": 3.0}) == 0.0)
	var eset := RaceSettings.new()
	check("RaceSettings.skill_boost defaults to none", eset.skill_boost == 0.0)
	Campaign.configure_stage(eset, eif, DifficultyProfile.AVERAGE)
	check("configure_stage hands the stage's boost to the race", is_equal_approx(eset.skill_boost, float(eif.boost)), str(eset.skill_boost))
	var other := RaceSettings.new()
	Campaign.configure_stage(other, Campaign.get_stage(Campaign.index_of("stage_lemans")), DifficultyProfile.AVERAGE)
	check("a stage without a boost gets none", other.skill_boost == 0.0)
	# the briefing's metadata
	var s4 := Campaign.get_stage(Campaign.index_of("stage_4"))
	check("class_line names the class", Campaign.class_line(s4).contains("Supermini"), Campaign.class_line(s4))
	check("class_line lists the field", Campaign.class_line(s4).contains("Dacia Sandero"), Campaign.class_line(s4))
	check("class_advice warns a Seicento on a Supermini stage", Campaign.class_advice("stock", s4) != "")
	check("class_advice is quiet for a car of the class", Campaign.class_advice("i20", s4) == "")
	check("class_cmp: Focus above Supermini", Campaign.class_cmp("focus", s4) == 1)
	check("class_of: unknown key is a city car", Campaign.class_of("nope") == "city")

func _mean(a: Array) -> float:
	var t := 0.0
	for x in a:
		t += float(x)
	return t / maxf(1.0, a.size())

## The rivals dealt over the roster: the counts, spread (the rarer car not bunched), and a stage without rivals.
func _field_classes_deal() -> void:
	var st := Campaign.get_stage(Campaign.index_of("stage_7")) # Kraków: 11 cars from five models
	var fc := Campaign.field_classes(st)
	check("field_classes: one per opponent", fc.size() == int(st.opponents), "(%d)" % fc.size())
	var counts := {}
	for k in fc:
		counts[k] = int(counts.get(k, 0)) + 1
	check("field_classes: the stage's counts", counts == st.rivals, "(%s vs %s)" % [counts, st.rivals])
	var s2 := Campaign.get_stage(Campaign.index_of("stage_3")) # Bór: 6 Seicentos, 2 Sanderos
	var f2 := Campaign.field_classes(s2)
	var at: Array[int] = []
	for i in f2.size():
		if f2[i] == "sandero":
			at.append(i)
	check("field_classes: the Sanderos are not side by side in the roster", at.size() == 2 and at[1] - at[0] >= 3, str(at))
	check("field_classes: deterministic", Campaign.field_classes(s2) == f2)
	check("field_classes: nothing for a stage without rivals", Campaign.field_classes({"opponents": 5}).is_empty())
	var rs := RaceSettings.new()
	Campaign.configure_stage(rs, st, DifficultyProfile.AVERAGE)
	check("configure_stage sets field_classes", rs.field_classes == fc)

## A one-make race is the race it was: field_classes all of the race's own car (or a bad key) give the same race,
## tick for tick, as none at all, and it is not mixed.
func _one_make_unchanged() -> void:
	var traces: Array = []
	for variant in 3:
		var s := RaceSettings.new()
		s.track = "gp"
		s.laps = 1
		s.opponents = 5
		s.ai_learning = "off"
		if variant == 1:
			s.field_classes = PackedStringArray(["stock", "stock", "stock", "stock", "stock"])
		elif variant == 2:
			s.field_classes = PackedStringArray(["bogus", "", "stock"])
		var race := Race.new(s, null, 4242)
		race.set_autopilot(true)
		check("one-make variant %d is not mixed" % variant, not race.mixed)
		var inp := Race.PlayerInput.new()
		for t in 120 * 40:
			race.step(1.0 / 120.0, inp)
		var tr := PackedFloat64Array()
		for c in race.cars:
			tr.append(c.x)
			tr.append(c.y)
			tr.append(c.v)
			check("one-make variant %d: car %d drives the race's car" % [variant, c.id], c.class_model == race.car_model and c.prof == race.track.PROF and c.car_key == "stock")
		traces.append(tr)
		race.dispose()
	check("field_classes of the race's own car change nothing", traces[1] == traces[0])
	check("bad field_classes keys fall back to the race's car", traces[2] == traces[0])

## A mixed field: each car on its own CarModel, Physics, profile and braking; set-ups of the class; paints from its
## own palette; a stage's field built through configure_stage.
func _mixed_field_build() -> void:
	var s := RaceSettings.new()
	s.track = "gp"
	s.laps = 1
	s.opponents = 4
	s.ai_learning = "off"
	s.field_classes = PackedStringArray(["v50", "stock", "v50", "golf4"])
	var race := Race.new(s, null, 99)
	check("mixed race is mixed", race.mixed)
	for c in race.cars:
		var want := "stock" if c.is_player else String(s.field_classes[c.id - 1])
		check("car %d drives %s" % [c.id, want], c.car_key == want, "(%s)" % c.car_key)
		check("car %d's class model is a %s" % [c.id, want], c.class_model.spec.resource_name == ("" if want == "stock" else want), "(%s)" % c.class_model.spec.resource_name)
		check("car %d's set-up model is of its class" % c.id, c.model.spec.resource_name == c.class_model.spec.resource_name and
			is_equal_approx(c.model.spec.grip_k, c.class_model.spec.grip_k))
		if want == "v50":
			check("car %d: the V50's own profile" % c.id, c.prof != race.track.PROF)
			check("car %d: the V50's own braking" % c.id, not is_equal_approx(c.brake_k, 1.0))
			check("car %d: a V50 paint" % c.id, CarCatalog.palette("v50").any(func(e: Dictionary) -> bool: return e.color == c.color))
		if want == "stock":
			check("car %d: the race's own physics" % c.id, c.class_phys == race.phys)
	var v50s := race.cars.filter(func(c: RaceCar) -> bool: return c.car_key == "v50")
	check("two V50s share one class model", v50s.size() == 2 and v50s[0].class_model == v50s[1].class_model)
	check("the longest car widens the contact reach", race._contact_r2 > 16.0)
	race.dispose()
	# a campaign stage's field through configure_stage
	var st := Campaign.get_stage(Campaign.index_of("stage_4"))
	var rs := RaceSettings.new()
	rs.car_class = "stock"
	Campaign.configure_stage(rs, st, DifficultyProfile.AVERAGE)
	rs.ai_learning = "off"
	var r2 := Race.new(rs, {}, 5)
	var counts := {}
	for c in r2.cars:
		if not c.is_player:
			counts[c.car_key] = int(counts.get(c.car_key, 0)) + 1
	check("stage 4's field drives its rivals", counts == st.rivals, "(%s vs %s)" % [counts, st.rivals])
	check("stage 4 starts the player at its grid slot", r2.player.grid == String(st.grid).substr(1).to_int(), "(P%d)" % r2.player.grid)
	r2.dispose()

## Same driver, same skill, no mistakes and no rubber band: the faster class finishes well ahead of the slower one,
## on the rail model and on the full physics.
func _mixed_race_pace() -> void:
	for physics in ["off", "on"]:
		var s := RaceSettings.new()
		s.track = "gp"
		s.laps = 1
		s.opponents = 4
		s.difficulty = "alien" # band 0: nobody is pulled towards the player
		s.ai_learning = "off"
		s.bot_physics = physics
		s.collisions = false # each car on its own pace
		s.race_control = false
		s.field_classes = PackedStringArray(["stock", "v50", "stock", "v50"])
		var race := Race.new(s, null, 17)
		race.set_autopilot(true)
		for c in race.cars:
			if not c.is_player:
				c.skill = 0.95
				c.mistake_rate = 0.0
				c.agg = 1.0
		var inp := Race.PlayerInput.new()
		var ticks := 0
		while race.phase != "finished" and ticks < 120 * 600:
			race.step(1.0 / 120.0, inp)
			ticks += 1
		check("mixed race (%s) finishes" % physics, race.phase == "finished", "(%s after %d ticks)" % [race.phase, ticks])
		var best := {"stock": INF, "v50": INF}
		var worst := {"stock": -INF, "v50": -INF}
		for c in race.cars:
			if c.is_player or c.finish_time == null:
				continue
			var t := float(c.finish_time)
			best[c.car_key] = minf(best[c.car_key], t)
			worst[c.car_key] = maxf(worst[c.car_key], t)
		check("V50s outpace Seicentos on equal skill (%s)" % physics, worst.v50 < best.stock - 5.0,
			"(slowest V50 %.1f s, fastest Seicento %.1f s)" % [worst.v50, best.stock])
		race.dispose()

## The race's world draws a mixed field as the cars it drives (each car's car_key, in the race's paint), the
## player's own car included; a one-make race as before: the player's car for the player, the real-model deal
## for the rivals, and a one-make (Seicento Cup) field all in the player's car.
func _mixed_visual_keys() -> void:
	var world := load("res://scripts/ui/race_world.gd") as GDScript
	var s := RaceSettings.new()
	s.track = "fiat"
	s.laps = 1
	s.opponents = 4
	s.ai_learning = "off"
	s.car_class = "stock"
	s.field_classes = PackedStringArray(["focus", "stock", "zafira", "i20"])
	var race := Race.new(s, {}, 3)
	var looks: Dictionary = world.field_looks(race)
	for c in race.cars:
		check("a look for car %d" % c.id, looks.has(c.id))
		if looks.has(c.id):
			check("car %d drawn as %s" % [c.id, c.car_key], String(looks[c.id][0]) == c.car_key, "(%s)" % String(looks[c.id][0]))
			check("car %d drawn in its race paint" % c.id, looks[c.id][1] == c.color)
	race.dispose()
	var s1 := RaceSettings.new()
	s1.track = "fiat"
	s1.laps = 1
	s1.opponents = 4
	s1.ai_learning = "off"
	var one := Race.new(s1, {}, 3)
	var dealt: Dictionary = world.field_looks(one)
	var cup: Dictionary = world.field_looks(one, true)
	var models := {}
	for c in one.cars:
		if c.is_player:
			check("one-make: the player drawn in the player's car", String(dealt[c.id][0]) == "stock")
		else:
			models[String(dealt[c.id][0])] = true
		check("Seicento Cup: everyone in the player's car", String(cup[c.id][0]) == "stock")
	check("one-make: the rivals still get the real-model deal", models.size() >= 2, str(models.keys()))
	one.dispose()

## Failure easing still goes down to Easy, also with the field tightened and a stage pace on top, and a clear resets it.
func _failure_easing() -> void:
	var idx := Campaign.index_of("stage_6") # Oświęcim: medium + its pace
	var st := Campaign.get_stage(idx)
	var lv0 := float(st.level)
	check("a fresh stage carries no heat", is_zero_approx(float(st.heat)) and int(st.eased) == 0)
	check("the stage's level is its difficulty and pace", is_equal_approx(lv0, 1.0 + float(Campaign.STAGES[idx].get("pace", 0.0))), "(%.2f)" % lv0)
	Campaign.record_result(idx, 99)
	var s1 := Campaign.get_stage(idx)
	check("one failed try eases a level", is_equal_approx(float(s1.level), maxf(0.0, lv0 - 1.0)) and int(s1.eased) == 1, "(%.2f, eased %d)" % [float(s1.level), int(s1.eased)])
	Campaign.record_result(idx, 1)
	check("a clear resets the easing", is_equal_approx(float(Campaign.get_stage(idx).level), lv0))
	# tightened to the top, then failing: still Easy in the end
	var prog := Campaign.load_progress()
	prog["heat"] = Campaign.HEAT_MAX
	Campaign.save_progress(prog)
	var hot := Campaign.get_stage(idx)
	check("heat raises the stage's level", is_equal_approx(float(hot.level), lv0 + Campaign.HEAT_MAX), "(%.2f)" % float(hot.level))
	var tries := 0
	while Campaign.get_stage(idx).difficulty != "easy" or float(Campaign.get_stage(idx).level) > 0.0:
		Campaign.record_result(idx, 99)
		tries += 1
		if tries > 8:
			break
	var eased := Campaign.get_stage(idx)
	check("failed tries ease even a tightened stage to Easy", eased.difficulty == "easy" and is_zero_approx(float(eased.level)), "(%s %.2f after %d)" % [eased.difficulty, float(eased.level), tries])
	check("failing took the heat back off", float(Campaign.load_progress().heat) < Campaign.HEAT_MAX)
	var rs := RaceSettings.new()
	Campaign.configure_stage(rs, eased, DifficultyProfile.AVERAGE)
	check("an eased stage races an Easy field", rs.difficulty == "easy" and is_zero_approx(rs.difficulty_shift), "(%s %+.2f)" % [rs.difficulty, rs.difficulty_shift])
	# the player's own rival step still goes below Easy (Novice)
	var rn := RaceSettings.new()
	Campaign.configure_stage(rn, eased, 0)
	check("Novice under an eased stage is below Easy", DifficultyProfile.race_params(rn.difficulty, rn.difficulty_shift).skill < Race.DIFFICULTY.easy.skill)

## Big wins tighten the field (the second in a row twice as much, a runaway twice again, capped); a narrow win or a
## podium keeps it and ends the streak; a failure gives some back; a place with no margin (old callers) never
## tightens; the Goliath ignores it; configure_stage turns it into a quicker field.
func _big_win_tightening() -> void:
	var base_skill := _stage_skill(Campaign.index_of("stage_8"))
	var r1 := Campaign.record_result(0, 1, 8.0)
	check("a big win tightens", r1.tightened and is_equal_approx(float(r1.heat), Campaign.HEAT_STEP) and int(r1.streak) == 1, str(r1))
	var r2 := Campaign.record_result(1, 1, 7.0)
	check("a second big win in a row tightens twice as much", is_equal_approx(float(r2.heat), Campaign.HEAT_STEP * 3.0) and int(r2.streak) == 2, str(r2))
	var r3 := Campaign.record_result(2, 1, 30.0)
	check("a runaway tightens to the cap", is_equal_approx(float(r3.heat), Campaign.HEAT_MAX), str(r3))
	var r4 := Campaign.record_result(3, 1, 2.0)
	check("a narrow win keeps the heat and ends the streak", is_equal_approx(float(r4.heat), Campaign.HEAT_MAX) and int(r4.streak) == 0 and not r4.tightened, str(r4))
	var r5 := Campaign.record_result(4, 2, 0.0)
	check("a podium clear keeps the heat", is_equal_approx(float(r5.heat), Campaign.HEAT_MAX) and r5.success, str(r5))
	var r6 := Campaign.record_result(4, 1)
	check("a place without a margin never tightens", not r6.tightened)
	var hot_skill := _stage_skill(Campaign.index_of("stage_8"))
	check("the heat makes a later stage's field quicker", hot_skill > base_skill + 0.005, "(%.4f vs %.4f)" % [hot_skill, base_skill])
	var gol := Campaign.get_stage(Campaign.index_of("stage_10"))
	check("the Goliath is not tightened", is_zero_approx(float(gol.heat)) and is_equal_approx(float(gol.level), 2.0) and gol.difficulty == "hard")
	var f := Campaign.record_result(5, 9)
	check("a failure gives heat back", is_equal_approx(float(f.heat), Campaign.HEAT_MAX - Campaign.HEAT_FAIL) and int(f.streak) == 0, str(f))
	check("next_heat never goes below zero", is_zero_approx(float(Campaign.next_heat(0.1, 0, false, 9, 0.0)[0])))
	check("next_heat never passes the cap", is_equal_approx(float(Campaign.next_heat(0.9, 5, true, 1, 99.0)[0]), Campaign.HEAT_MAX))
	check("P1 by under BIG_WIN is not big", is_equal_approx(float(Campaign.next_heat(0.0, 0, true, 1, Campaign.BIG_WIN - 0.1)[0]), 0.0))

func _stage_skill(idx: int) -> float:
	var rs := RaceSettings.new()
	Campaign.configure_stage(rs, Campaign.get_stage(idx), DifficultyProfile.AVERAGE)
	return float(DifficultyProfile.race_params(rs.difficulty, rs.difficulty_shift).skill)

## clean_progress: heat a number in [0, HEAT_MAX], streak a whole number >= 0, junk dropped to defaults; a save
## from before the adaptive field (no heat, no streak) loads and races as before.
func _save_sanitizing() -> void:
	check("heat junk -> 0", is_zero_approx(float(Campaign.clean_progress({"heat": "hot"}).heat)))
	check("heat over the cap is clamped", is_equal_approx(float(Campaign.clean_progress({"heat": 7}).heat), Campaign.HEAT_MAX))
	check("negative heat -> 0", is_zero_approx(float(Campaign.clean_progress({"heat": -3.5}).heat)))
	check("heat as a numeric string", is_equal_approx(float(Campaign.clean_progress({"heat": "0.5"}).heat), 0.5))
	check("heat as a dictionary -> 0", is_zero_approx(float(Campaign.clean_progress({"heat": {"a": 1}}).heat)))
	check("streak junk -> 0", int(Campaign.clean_progress({"streak": [1]}).streak) == 0)
	check("negative streak -> 0", int(Campaign.clean_progress({"streak": -4}).streak) == 0)
	check("streak kept", int(Campaign.clean_progress({"streak": 2.0}).streak) == 2)
	# an old (0.5.9) save: no heat or streak keys
	var path := SaveData.path(Campaign.save_file)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"unlocked": 5, "best_pos": {"0": 1}, "trophies": ["Wilamowice Bronze Piston"], "arc": 2, "fails": {"3": 1}}))
	f.close()
	var prog := Campaign.load_progress()
	check("an old save has no heat", not prog.has("heat") and not prog.has("streak"))
	var st := Campaign.get_stage(Campaign.index_of("stage_4")) # (arc 2's index 3)
	check("an old save's stage carries no heat", is_zero_approx(float(st.heat)))
	check("an old save's failures still ease", int(st.eased) == 1)
	var r := Campaign.record_result(0, 1, 9.0)
	check("an old save takes the adaptive field from here", r.tightened and is_equal_approx(float(Campaign.load_progress().heat), Campaign.HEAT_STEP))
	# a file with a crafted heat
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{\"unlocked\": 2, \"heat\": \"1e30\", \"streak\": \"lots\"}")
	f.close()
	var crafted := Campaign.load_progress()
	check("crafted heat/streak are sanitized", float(crafted.heat) >= 0.0 and float(crafted.heat) <= Campaign.HEAT_MAX and int(crafted.streak) == 0, str(crafted))
	check("a crafted save still builds its stages", Campaign.get_stage(1).has("level"))

func _win_margin() -> void:
	var me := RaceCar.new()
	me.is_player = true
	var them := RaceCar.new()
	check("win_margin: the gap to P2", is_equal_approx(Campaign.win_margin([{"car": me, "laps": 2, "total": 300.0}, {"car": them, "laps": 2, "total": 312.5}]), 12.5))
	check("win_margin: 0 when not the winner", is_zero_approx(Campaign.win_margin([{"car": them, "laps": 2, "total": 300.0}, {"car": me, "laps": 2, "total": 301.0}])))
	check("win_margin: P2 a lap down is a runaway", is_equal_approx(Campaign.win_margin([{"car": me, "laps": 2, "total": 300.0}, {"car": them, "laps": 1, "total": null}]), Campaign.RUNAWAY_WIN))
	check("win_margin: alone", is_zero_approx(Campaign.win_margin([{"car": me, "laps": 1, "total": 10.0}])))
