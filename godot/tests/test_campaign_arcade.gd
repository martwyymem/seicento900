## Campaign arcade rules (roadmap item A): every campaign stage owns its rules instead of inheriting
## Quick Race toggles — no mandatory pit stop, no refuelling, no two-compounds rule, no tyre wear, no
## fuel use, no pit strategy for player or AI, no safety car or red flag (local yellows and stewards'
## penalties stay), pit HUD bits hidden, and Fiat Track (stage_8) at 4 laps. Quick Race stays unchanged.
extends RefCounted

var completed := false
var errors: Array[String] = []

func check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		errors.append("%s %s" % [what, detail])

func run() -> Array:
	var saved_profile := DifficultyProfile.current.duplicate()
	var saved_campaign_file := Campaign.save_file
	DifficultyProfile.current = DifficultyProfile.defaults()
	Campaign.save_file = "campaign_arcade_test.json"
	Campaign.reset_progress()
	_stage_definitions()
	await _game_settings_isolation()
	_sim_one_lap_stage("stage_1", true) # Wilamowice, 1 lap, full physics
	_sim_one_lap_stage("stage_9", false) # Tokyo, 14.3 km 1 lap (fast rail bots)
	_sim_variable_weather_no_pit() # Bór, 2 laps with rain: nobody pits even on weather shift
	_race_control_no_sc()
	await _hud_no_pits()
	var path := ProjectSettings.globalize_path(SaveData.path(Campaign.save_file))
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	Campaign.save_file = saved_campaign_file
	DifficultyProfile.current = saved_profile
	completed = true
	return errors

func _stage_definitions() -> void:
	var fiat_idx := Campaign.index_of("stage_8")
	check("Fiat Track stage exists", fiat_idx >= 0)
	if fiat_idx >= 0:
		var st := Campaign.get_stage(fiat_idx)
		check("Fiat Track stage is 4 laps", int(st.laps) == 4, "(got %s)" % str(st.laps))
	for i in Campaign.STAGES.size():
		var stage := Campaign.get_stage(i)
		var rs := RaceSettings.new()
		# Pre-populate with worst-case Quick Race values to verify configure_stage overwrites all of them.
		rs.mandatory_stop = true
		rs.two_compounds = true
		rs.refuel = true
		rs.pits_enabled = true
		rs.auto_strategist = true
		rs.dynamic_running = true
		rs.wear_mult = 5.0
		rs.fuel_mult = 10.0
		rs.race_control = false
		rs.safety_car = true
		rs.collisions = false
		rs.draft = false
		rs.mechanical_damage = true
		Campaign.configure_stage(rs, stage, DifficultyProfile.AVERAGE)
		DifficultyProfile.apply_sim(rs, DifficultyProfile.defaults())
		_assert_arcade_settings("configure_stage(%s)" % String(stage.id), rs, stage)

func _assert_arcade_settings(tag: String, rs: RaceSettings, stage: Dictionary) -> void:
	check("%s: track/laps/weather match" % tag,
		rs.track == String(stage.track) and rs.laps == int(stage.laps) and rs.weather == String(stage.weather))
	check("%s: mandatory_stop off" % tag, not rs.mandatory_stop)
	check("%s: two_compounds off" % tag, not rs.two_compounds)
	check("%s: refuel off" % tag, not rs.refuel)
	check("%s: pits_enabled off" % tag, not rs.pits_enabled)
	check("%s: auto_strategist off" % tag, not rs.auto_strategist)
	check("%s: tyre wear off" % tag, rs.wear_mult == 0.0, "(wear_mult=%s)" % str(rs.wear_mult))
	check("%s: fuel use off" % tag, rs.fuel_mult == 0.0, "(fuel_mult=%s)" % str(rs.fuel_mult))
	check("%s: race_control on, safety_car off" % tag, rs.race_control and not rs.safety_car)
	check("%s: collisions and draft on" % tag, rs.collisions and rs.draft)
	check("%s: mechanical_damage off under default profile" % tag, not rs.mechanical_damage)

func _game_settings_isolation() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game = load("res://ui/game.tscn").instantiate()
	tree.root.add_child(game)
	for i in 3:
		await tree.process_frame
	# Flip Quick Race toggles to values that used to leak into campaign.
	game.mandatory_stop_toggle.button_pressed = true
	game.two_compounds_toggle.button_pressed = true
	game.refuel_toggle.button_pressed = true
	game.strategist_toggle.button_pressed = true
	game.dynamic_toggle.button_pressed = true
	game.race_control_toggle.button_pressed = false
	game.collisions_toggle.button_pressed = false
	game.draft_toggle.button_pressed = false
	game.damage_toggle.button_pressed = true
	game.wear_picker.value = 4.0
	game.fuel_picker.value = 3.0

	# Every campaign stage ignores those Quick Race toggles.
	game.is_campaign_mode = true
	game.is_championship_mode = false
	game.is_rally_mode = false
	game.is_time_trial_mode = false
	for i in Campaign.STAGES.size():
		game.campaign_stage_index = i
		var stage := Campaign.get_stage(i)
		var rs: RaceSettings = game._build_race_settings(false)
		_assert_arcade_settings("game stage %d (%s)" % [i, String(stage.id)], rs, stage)

	# Quick Race still reads those toggles untouched.
	game.is_campaign_mode = false
	var qr: RaceSettings = game._build_race_settings(false)
	check("Quick Race keeps mandatory_stop", qr.mandatory_stop)
	check("Quick Race keeps two_compounds", qr.two_compounds)
	check("Quick Race keeps refuel", qr.refuel)
	check("Quick Race keeps pits_enabled", qr.pits_enabled)
	check("Quick Race keeps safety_car", qr.safety_car)
	check("Quick Race keeps wear/fuel pickers", is_equal_approx(qr.wear_mult, 4.0) and is_equal_approx(qr.fuel_mult, 3.0))
	check("Quick Race keeps auto_strategist", qr.auto_strategist)
	check("Quick Race keeps race_control toggle", not qr.race_control)

	game.queue_free()
	await tree.process_frame

func _sim_one_lap_stage(stage_id: String, full_bot_physics: bool) -> void:
	var idx := Campaign.index_of(stage_id)
	var stage := Campaign.get_stage(idx)
	var rs := RaceSettings.new()
	Campaign.configure_stage(rs, stage, DifficultyProfile.AVERAGE)
	DifficultyProfile.apply_sim(rs, DifficultyProfile.defaults())
	rs.ai_learning = "off"
	rs.bot_physics = "on" if full_bot_physics else "off"
	var race := Race.new(rs, {}, 7)
	race.set_autopilot(true)
	var fuel0 := []
	for c in race.cars:
		fuel0.append(c.fuel)
		check("%s: car %d has single-stint no-stop plan" % [stage_id, c.id], c.plan.size() == 1, "(plan=%s)" % str(c.plan))

	# Player pit/replan/mix calls must be no-ops when pits are disabled.
	var ev_before := race.events.size()
	race.player_toggle_pit()
	race.player_replan()
	race.player_cycle_mix()
	check("%s: player_toggle_pit is no-op" % stage_id, not race.player.pit_request)
	check("%s: player_cycle_mix keeps normal" % stage_id, race.player.mix == "normal")
	check("%s: pit controls log nothing" % stage_id, race.events.size() == ev_before)

	var inp := Race.PlayerInput.new()
	var entered_pit := false
	var sc_deployed := false
	var max_ticks := 120 * 1200 # 20 min cap (plenty for 1 lap of Tokyo)
	var ticks := 0
	while race.phase != "finished" and ticks < max_ticks:
		race.step(1.0 / 120.0, inp)
		ticks += 1
		if ticks % 60 == 0:
			for c in race.cars:
				if c.mode == "pit" or c.pit_request:
					entered_pit = true
			if race.rc and (race.rc.flag != "green" or race.rc.sc_state != "garage"):
				sc_deployed = true

	check("%s: race finished" % stage_id, race.phase == "finished", "(phase=%s, ticks=%d)" % [race.phase, ticks])
	check("%s: nobody pitted or requested pit" % stage_id, not entered_pit)
	check("%s: safety car / red flag never deployed" % stage_id, not sc_deployed)
	for i in race.cars.size():
		var c: RaceCar = race.cars[i]
		check("%s: car %d made 0 stops" % [stage_id, c.id], c.stops == 0, "(stops=%d)" % c.stops)
		check("%s: car %d burnt no fuel" % [stage_id, c.id], is_equal_approx(c.fuel, float(fuel0[i])), "(%.3f -> %.3f)" % [float(fuel0[i]), c.fuel])
		check("%s: car %d wore no tyres" % [stage_id, c.id], is_equal_approx(float(c.tyre.wear), 1.0), "(wear=%.4f)" % float(c.tyre.wear))
		for pen in c.penalties:
			var reason := String(pen[0])
			check("%s: car %d has no pit/compound penalty" % [stage_id, c.id],
				not reason.contains("pit") and not reason.contains("compound"), "(pen=%s)" % str(pen))
	for e in race.events:
		var txt := String(e.text)
		check("%s: no strategist message" % stage_id, not txt.contains("Strategist:"), "(event=%s)" % txt)
	race.dispose()

func _sim_variable_weather_no_pit() -> void:
	var idx := Campaign.index_of("stage_3") # Bór, 2 laps, variable weather
	var stage := Campaign.get_stage(idx)
	var rs := RaceSettings.new()
	Campaign.configure_stage(rs, stage, DifficultyProfile.AVERAGE)
	DifficultyProfile.apply_sim(rs, DifficultyProfile.defaults())
	rs.ai_learning = "off"
	rs.bot_physics = "off"
	var race := Race.new(rs, {}, 13)
	race.set_autopilot(true)
	# Force heavy rain from the start of lap 1 so weather_shift triggers if decide() were active.
	race.weather.rain = 1.0
	race.weather.wet = 0.9
	var inp := Race.PlayerInput.new()
	var ticks := 0
	while race.phase != "finished" and ticks < 120 * 900:
		race.step(1.0 / 120.0, inp)
		ticks += 1
	check("variable weather 2-lap stage finished", race.phase == "finished")
	for c in race.cars:
		check("variable weather: car %d made 0 stops" % c.id, c.stops == 0 and not c.pit_request, "(stops=%d)" % c.stops)
	for e in race.events:
		check("variable weather: no strategist message", not String(e.text).contains("Strategist:"), String(e.text))
	race.dispose()

func _race_control_no_sc() -> void:
	var rs := RaceSettings.new()
	Campaign.configure_stage(rs, Campaign.get_stage(Campaign.index_of("stage_8")), DifficultyProfile.AVERAGE)
	rs.mechanical_damage = true
	rs.damage_mode = "full"
	rs.ai_learning = "off"
	rs.bot_physics = "off"
	var race := Race.new(rs, {}, 5)
	race.set_autopilot(true)
	var inp := Race.PlayerInput.new()
	# Run past lights out into racing.
	for i in 120 * 12:
		race.step(1.0 / 120.0, inp)
	check("rc test: racing", race.phase == "racing" and race.rc != null)
	# Wreck a car directly on the racing line with a barrier-level impact, and damage another > REPAIR_AT.
	var victim: RaceCar = race.cars[1]
	victim.d = 0.0
	victim.vx = 0.0
	victim.vy = 0.0
	victim.v = 0.0
	race.rc.wreck(victim, RaceControl.RED_IMPACT + 5.0, true)
	var hurt_car: RaceCar = race.cars[2]
	hurt_car.damage = RaceControl.REPAIR_AT + 0.2
	# Also trigger a 3-car pileup wreck count.
	race.rc._wrecks.append(race.clock)
	race.rc._wrecks.append(race.clock)
	# Step 10 seconds: local yellow must activate, SC/red flag must NOT deploy, damaged car must NOT pit,
	# and stranded car's recovery timer must tick down on track without waiting for a safety car.
	var rec_before := victim.recover_left
	for i in 120 * 10:
		race.step(1.0 / 120.0, inp)
	check("no SC/red flag on on-track wreck + barrier RED_IMPACT + pileup",
		race.rc.flag == "green" and race.rc.sc_state == "garage", "(flag=%s sc=%s)" % [race.rc.flag, race.rc.sc_state])
	check("local yellow still activates for stranded car", race.rc.yellow_at(victim.s) > 0, "(yellow=%d)" % race.rc.yellow_at(victim.s))
	check("marshals recover on-track wreck without waiting for SC", victim.recover_left < rec_before - 5.0,
		"(before=%.1f after=%.1f)" % [rec_before, victim.recover_left])
	check("damaged AI does not request pit when pits off", not hurt_car.pit_request)
	# Stewards penalties still work.
	race.rc.penalise(race.player, 5, "causing a collision")
	check("stewards penalties still apply", is_equal_approx(race.player.penalty, 5.0))
	race.dispose()

func _hud_no_pits() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var host := Control.new()
	host.size = Vector2(1600, 900)
	tree.root.add_child(host)

	# Campaign stage HUD: pitwall hidden, pit hints absent from controls guide.
	var rs_camp := RaceSettings.new()
	Campaign.configure_stage(rs_camp, Campaign.get_stage(0), DifficultyProfile.AVERAGE)
	var r_camp := Race.new(rs_camp, {}, 3)
	var hud := RaceHud.new()
	hud.size = Vector2(1600, 900)
	host.add_child(hud)
	hud.start(r_camp, null, null)
	check("campaign HUD: pitwall hidden", not hud.pitwall.visible)
	var entries: Array = hud._guide_entries()
	var has_box_hint := false
	for row in entries:
		if String(row[1]).contains("Request box") or String(row[1]).contains("fuel"):
			has_box_hint = true
	check("campaign HUD: controls guide hides pit/fuel hints", not has_box_hint, str(entries))
	hud.toggle_help()
	check("campaign HUD: full help text hides PIT & STRATEGY", not hud._help_label.text.contains("PIT & STRATEGY"), hud._help_label.text)

	# Quick Race with mandatory stop: pitwall visible, pit hints present.
	var rs_qr := RaceSettings.new()
	rs_qr.track = "gp"
	rs_qr.laps = 6
	rs_qr.mandatory_stop = true
	var r_qr := Race.new(rs_qr, null, 3)
	hud.start(r_qr, null, null)
	check("Quick Race HUD: pitwall visible", hud.pitwall.visible)
	var qr_entries: Array = hud._guide_entries()
	var qr_has_box := false
	for row in qr_entries:
		if String(row[1]).contains("Request box"):
			qr_has_box = true
	check("Quick Race HUD: controls guide keeps Request box", qr_has_box)

	host.free()
	r_camp.dispose()
	r_qr.dispose()
	await tree.process_frame
