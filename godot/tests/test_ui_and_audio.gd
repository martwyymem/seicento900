## Test suite for RaceAudio, RaceWorld procedural features, and UI/Championship systems.
extends RefCounted

const CampaignData := preload("res://scripts/sim/campaign.gd")

var completed := false

func run() -> Array:
	var errors: Array[String] = []

	# 1. Test RaceAudio
	var audio := RaceAudio.new()
	var dummy_car := {
		"rpm": 4200.0,
		"throttle": 0.85,
		"slip": 0.1,
		"understeer": 0.05,
		"tow": 0.3,
		"gear": 2
	}
	audio.update_car(dummy_car, true)
	if audio.tow != 0.3:
		errors.append("Audio tow should match dummy car tow")
	audio.trigger_shift(true, 0.9)
	audio.beep(880.0, 2)
	if audio.muted:
		errors.append("Default audio should not be muted")
	audio.toggle_mute()
	if not audio.muted:
		errors.append("Audio should be muted after toggle")
	audio.toggle_mute()

	# 2. Test RaceWorld procedural 3D features
	var tr: Track = Race.get_track("gp")
	var world_script: GDScript = load("res://scripts/ui/race_world.gd")
	var world = world_script.new()
	world.set_track(tr)

	var track_node: Node3D = world.track_root
	if not track_node:
		errors.append("Track root should exist")
	elif not track_node.get_node_or_null("Asphalt"):
		errors.append("Asphalt mesh should exist")
	elif not track_node.get_node_or_null("Runoff"):
		errors.append("Runoff mesh should exist")
	elif not track_node.get_node_or_null("Kerbs"):
		errors.append("Kerbs mesh should exist")
	elif not track_node.get_node_or_null("PitLane"):
		errors.append("PitLane mesh should exist")
	elif not track_node.get_node_or_null("PitWall"):
		errors.append("PitWall mesh should exist")
	elif not track_node.get_node_or_null("RacingLine"):
		errors.append("RacingLine mesh should exist")

	if world.start_lights.size() != 5:
		errors.append("Expected 5 start lights on gantry, got %d" % world.start_lights.size())
	if world.tv_cameras.size() < 4:
		errors.append("Expected at least 4 TV camera positions, got %d" % world.tv_cameras.size())

	var initial_mode: int = world.camera_mode
	world.cycle_camera()
	if world.camera_mode == initial_mode:
		errors.append("Camera mode should cycle")
	var rl_on: bool = world.toggle_racing_line()
	if rl_on:
		errors.append("Racing line toggle should flip to false")

	# 3. Test Championship scoring & persistence
	var rs := RaceSettings.new()
	rs.track = "monza"
	rs.laps = 1
	rs.opponents = 4
	var race := Race.new(rs)
	var inp := Race.PlayerInput.new()
	for i in 60:
		race.step(1.0 / 120.0, inp)

	var results := race.results()
	if results.size() != 5:
		errors.append("Expected 5 cars in results, got %d" % results.size())

	# Test player car instant recovery
	race.player.mode = "race"
	race.phase = "racing"
	race.player.d = 45.0
	var reset_success := race.reset_player_car()
	if not reset_success:
		errors.append("Expected reset_player_car to return true")
	if absf(race.player.d) > race.track.half:
		errors.append("Reset car lateral position should be clamped within track boundaries")

	# 4. Test Pillar 1: Dynamic Weather Systems (Snow, Hail, Fog)
	world._build_environment()
	if not world.snow_particles:
		errors.append("RaceWorld should create snow_particles")
	if not world.hail_particles:
		errors.append("RaceWorld should create hail_particles")

	var rs_snow := RaceSettings.new()
	rs_snow.track = "gp"
	rs_snow.weather = "snow"
	var race_snow := Race.new(rs_snow)
	if race_snow.weather.snow != 0.85 or race_snow.weather.wet != 0.65 or race_snow.weather.rain != 0.0:
		errors.append("Snow weather values incorrect: snow=%.2f, wet=%.2f, rain=%.2f" % [race_snow.weather.snow, race_snow.weather.wet, race_snow.weather.rain])
	if race_snow.weather.forecast(0.0) != "Snow all race — icy conditions":
		errors.append("Snow forecast incorrect: %s" % race_snow.weather.forecast(0.0))

	var rs_hail := RaceSettings.new()
	rs_hail.track = "gp"
	rs_hail.weather = "hail"
	var race_hail := Race.new(rs_hail)
	if race_hail.weather.hail != 0.90 or race_hail.weather.wet != 0.75 or race_hail.weather.rain != 0.35:
		errors.append("Hail weather values incorrect: hail=%.2f, wet=%.2f, rain=%.2f" % [race_hail.weather.hail, race_hail.weather.wet, race_hail.weather.rain])
	if race_hail.weather.forecast(0.0) != "Severe hail storm — low traction":
		errors.append("Hail forecast incorrect: %s" % race_hail.weather.forecast(0.0))

	var rs_fog := RaceSettings.new()
	rs_fog.track = "gp"
	rs_fog.weather = "fog"
	var race_fog := Race.new(rs_fog)
	if race_fog.weather.fog != 1.0 or race_fog.weather.wet != 0.15 or race_fog.weather.rain != 0.0:
		errors.append("Fog weather values incorrect: fog=%.2f, wet=%.2f, rain=%.2f" % [race_fog.weather.fog, race_fog.weather.wet, race_fog.weather.rain])
	if race_fog.weather.forecast(0.0) != "Dense fog all race — visibility restricted":
		errors.append("Fog forecast incorrect: %s" % race_fog.weather.forecast(0.0))

	# Test grip scaling
	var rs_dry := RaceSettings.new()
	rs_dry.track = "gp"
	rs_dry.weather = "dry"
	var race_dry := Race.new(rs_dry)
	var grip_dry := race_dry.grip(race_dry.player)
	var grip_snow := race_snow.grip(race_snow.player)
	var grip_hail := race_hail.grip(race_hail.player)
	var grip_fog := race_fog.grip(race_fog.player)

	if grip_snow >= grip_dry:
		errors.append("Snow grip (%.3f) should be lower than dry grip (%.3f)" % [grip_snow, grip_dry])
	if grip_hail >= grip_dry:
		errors.append("Hail grip (%.3f) should be lower than dry grip (%.3f)" % [grip_hail, grip_dry])
	if grip_fog >= grip_dry:
		errors.append("Fog grip (%.3f) should be lower than dry grip (%.3f)" % [grip_fog, grip_dry])

	# Test audio weather update
	audio.update_car(dummy_car, true, race_snow.weather)
	if audio.snow != 0.85:
		errors.append("Audio snow should be 0.85, got %.2f" % audio.snow)
	audio.update_car(dummy_car, true, race_hail.weather)
	if audio.hail != 0.90:
		errors.append("Audio hail should be 0.90, got %.2f" % audio.hail)

	# 5. Test Pillar 4 & 5: Campaign Mode, Stage Settings & FRONT_MENU Architecture
	var game_script: GDScript = load("res://scripts/ui/game.gd")
	var front_menu: Array = game_script.FRONT_MENU
	var expected_ids := ["campaign", "quick_race", "rally", "time_trial", "championship", "options", "quit"]
	if front_menu.size() != expected_ids.size():
		errors.append("FRONT_MENU should have exactly %d items, got %d" % [expected_ids.size(), front_menu.size()])
	for i in mini(front_menu.size(), expected_ids.size()):
		if front_menu[i].id != expected_ids[i]:
			errors.append("FRONT_MENU[%d].id should be '%s', got '%s'" % [i, expected_ids[i], front_menu[i].id])

	for i in CampaignData.STAGES.size():
		var st: Dictionary = CampaignData.get_stage(i)
		for req_field in ["id", "act", "act_name", "title", "track", "laps", "weather", "start_hour", "wear_mult", "fuel_mult", "opponents", "difficulty", "target_pos", "trophy", "desc", "tip"]:
			if not st.has(req_field):
				errors.append("Campaign stage %d missing required field '%s'" % [i, req_field])
		var c_track: Track = Race.get_track(st.track)
		if not c_track:
			errors.append("Campaign stage %d track '%s' failed to load" % [i, st.track])

		# Verify RaceSettings mapping for campaign stage
		var c_settings := RaceSettings.new()
		c_settings.track = st.track
		c_settings.laps = st.laps
		c_settings.format = "laps"
		c_settings.weather = st.weather
		c_settings.opponents = st.opponents
		c_settings.difficulty = st.difficulty
		c_settings.start_hour = st.start_hour
		c_settings.wear_mult = st.get("wear_mult", 2.0)
		c_settings.fuel_mult = st.get("fuel_mult", 1.0)
		if c_settings.track != st.track or c_settings.laps != st.laps or c_settings.weather != st.weather:
			errors.append("Campaign stage %d settings mapping mismatch" % i)

	# Test Campaign progression recording
	var test_res: Dictionary = CampaignData.record_result(0, 1) # P1 on stage 0
	if not test_res.success:
		errors.append("P1 on stage 0 should succeed")
	if test_res.trophy != CampaignData.get_stage(0).trophy:
		errors.append("Expected trophy '%s', got '%s'" % [CampaignData.get_stage(0).trophy, test_res.trophy])

	# a stage that keeps beating the player eases off: one difficulty level per two failed tries, reset on a win
	var ease_idx := 6
	var base_level: String = CampaignData.STAGES[ease_idx].difficulty
	for k in CampaignData.FAILS_PER_EASE:
		CampaignData.record_result(ease_idx, 99)
	var eased_st: Dictionary = CampaignData.get_stage(ease_idx)
	if eased_st.eased != 1 or CampaignData.LEVELS.find(eased_st.difficulty) != maxi(0, CampaignData.LEVELS.find(base_level) - 1):
		errors.append("Stage %d after %d failures: difficulty %s (base %s), eased %d" % [ease_idx, CampaignData.FAILS_PER_EASE, eased_st.difficulty, base_level, eased_st.eased])
	CampaignData.record_result(ease_idx, 1)
	if CampaignData.get_stage(ease_idx).difficulty != base_level:
		errors.append("A win on stage %d should reset its easing" % ease_idx)
	# no stage asks for a win against a Hard field from mid-grid (stage 7 used to: 13 Hard bots, P1 from P7)
	for st in CampaignData.STAGES:
		if st.target_pos == 1 and st.difficulty != "easy" and st.get("grid", "middle") != "pole":
			errors.append("Campaign stage '%s' wants a win against a %s field without pole" % [st.id, st.difficulty])

	_check_menu_modes(errors, game_script)

	race_snow.dispose()
	race_hail.dispose()
	race_fog.dispose()
	race_dry.dispose()

	# neither node joined the tree, so nothing frees them but us
	race.dispose()
	audio.free()
	world.free()
	completed = true
	return errors

## The mode is picked once, on the main menu: the set-up page has no mode toggle, each entry lands on the
## page in its own mode, and a campaign stage's briefing hides what the stage dictates.
func _check_menu_modes(errors: Array[String], game_script: GDScript) -> void:
	for st in CampaignData.STAGES:
		if not (st.track in game_script.TRACK_KEYS):
			errors.append("Campaign stage '%s' track '%s' is not in TRACK_KEYS" % [st.id, st.track])
	if game_script.FRONT_MENU.any(func(e): return e.id == "single_race"):
		errors.append("FRONT_MENU still has a separate single race entry")
	var game = load("res://ui/game.tscn").instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(game)
	if game.has_method("_toggle_mode") or "mode_button" in game:
		errors.append("The set-up page should have no mode toggle")
	var buttons: Array[Node] = game.setup_panel.find_children("*", "Button", true, false)
	for b in buttons:
		if (b as Button).text.begins_with("MODE"):
			errors.append("The set-up page still has a mode button '%s'" % (b as Button).text)
	if not "time trial" in String(game.opponents_picker.tooltip_text).to_lower():
		errors.append("The opponents field should say that 0 opponents is a solo time trial")
	var track_before: int = game.track_picker.selected
	var laps_before: float = game.laps_picker.value
	var opp_before: float = game.opponents_picker.value
	var ids: Array = game_script.FRONT_MENU.map(func(e): return e.id)
	var expect := {
		"quick_race": [false, false, "QUICK RACE"],
		"time_trial": [false, false, "TIME TRIAL"],
		"championship": [false, true, "CHAMPIONSHIP"],
		"campaign": [true, false, "CAMPAIGN"],
	}
	for id in expect:
		game._show_home()
		game._home_select(ids.find(id), false)
		game._activate_home_item()
		var want: Array = expect[id]
		if id == "campaign" and OpenWorld.available():
			# the campaign opens in the open world of Brzeszcze; its pause menu leads to the stage list
			if game.active_menu_page != "world" or game.open_world == null or not game.open_world.active:
				errors.append("Menu 'campaign' should open the open world, got '%s'" % game.active_menu_page)
			elif game.open_world.events.size() != CampaignData.STAGES.size():
				errors.append("The open world shows %d stage beacons for %d stages" % [game.open_world.events.size(), CampaignData.STAGES.size()])
			if game.open_world:
				game.open_world.suspend()
			game._on_world_leave("stages")
		if game.active_menu_page != "setup":
			errors.append("Menu '%s' should open the set-up page, got '%s'" % [id, game.active_menu_page])
		if game.is_campaign_mode != want[0] or game.is_championship_mode != want[1]:
			errors.append("Menu '%s' landed in campaign=%s championship=%s" % [id, game.is_campaign_mode, game.is_championship_mode])
		if not String(game.setup_title_label.text).begins_with(want[2]):
			errors.append("Menu '%s' set-up title should start '%s', got '%s'" % [id, want[2], game.setup_title_label.text])
		var items: Array = game._setup_focus_items()
		if id == "campaign":
			if not game.campaign_side.visible or game.track_picker.visible or game.setup_conditions_row.visible or game.setup_format_row.visible:
				errors.append("The campaign briefing should show the stage and hide circuit, format and conditions")
			if game.setup_race_button.visible or not items.has(game.campaign_start_button):
				errors.append("The campaign stage should start from ENTER STAGE, reachable by keyboard")
			if game.grid_picker.get_parent().visible:
				errors.append("The campaign stage sets the grid; its picker should be hidden")
			for fold in ["driver", "car"]:
				if not game.setup_folds.has(fold) or not (game.setup_folds[fold].head as Control).visible:
					errors.append("The campaign page should keep the %s section (name, paint, car set-up)" % fold)
		else:
			if game.campaign_side.visible or not items.has(game.setup_race_button):
				errors.append("Menu '%s' should show RACE, not the campaign briefing" % id)
		if id == "quick_race" and (not game.track_picker.visible or not game.opponents_picker.is_visible_in_tree()):
			errors.append("Quick race should offer the circuit and the opponents")
		if game.champ_reset_button.visible and id != "championship":
			errors.append("RESET SEASON should only show in a championship")
	if game.track_picker.selected != track_before or game.laps_picker.value != laps_before or game.opponents_picker.value != opp_before:
		errors.append("Opening the campaign should leave the quick-race circuit, laps and opponents alone")
	game.opponents_picker.value = 0
	if not String(game.opponents_picker.suffix).contains("SOLO"):
		errors.append("0 opponents should read as a solo run")
	game.opponents_picker.value = opp_before
	# the front-end pages cover the 3D view: stepping the circuit must not rebuild the world (that froze the menu)
	var shown_root = game.world_view.track_root
	var shown_track = game.world_view.track
	game._show_home()
	game._home_select(ids.find("quick_race"), false)
	game._activate_home_item()
	for i in 3:
		game.track_picker.step(1, true)
	if game.world_view.track != shown_track or game.world_view.track_root != shown_root:
		errors.append("Changing the circuit in the menu should not rebuild the 3D world")
	# back from a race, the world lets go of it but keeps the circuit, and racing there again reuses it
	var rs := RaceSettings.new()
	rs.track = "monaco"
	rs.opponents = 2
	var r1 := Race.new(rs)
	game.world_view.set_race(r1)
	var built = game.world_view.track_root
	game.world_view.release_race()
	if game.world_view.race != null or not game.world_view.visuals.is_empty() or game.world_view.track != r1.track:
		errors.append("release_race should drop the race and its cars but keep the circuit")
	var r2 := Race.new(rs)
	game.world_view.set_race(r2)
	if game.world_view.track_root != built:
		errors.append("A race on the circuit the world still has should not rebuild it")
	game.world_view.release_race()
	r1.dispose()
	r2.dispose()
	game.free()
