## The car between events and the customisable championship: what each damaged part does to the car (and
## that a sound car drives exactly as before), damage carried over between championship rounds and campaign
## stages through the service area, the season's settings saved with it and locked once it is under way,
## and the front end driven by gamepad buttons alone.
extends RefCounted

const CampaignData := preload("res://scripts/sim/campaign.gd")

var completed := false

func run() -> Array:
	var errors: Array[String] = []
	_check_symptoms(errors)
	_check_race_effects(errors)
	var saves := _backup(["championship.json", "campaign.json", "race_settings.cfg"])
	# start the menus from defaults: a race picked by hand or by a QA probe must not steer the checks below
	DirAccess.remove_absolute(SaveData.path("race_settings.cfg"))
	var game = load("res://ui/game.tscn").instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(game)
	_check_season(errors, game)
	_check_carry_over(errors, game)
	_check_pad_menus(errors, game)
	game.free()
	_restore(saves)
	completed = true
	return errors

## Service's per-part factors: neutral on a sound car, each part hitting its own system when damaged.
func _check_symptoms(errors: Array[String]) -> void:
	var car := RaceCar.new()
	Service.sync(car)
	if car.fx_on or car.fx_power != 1.0 or car.fx_brake != 1.0 or car.fx_grip != 1.0 or car.fx_drag != 1.0:
		errors.append("A sound car should have neutral part effects")
	if Service.misfire(car, 3.3, 0.8) != 0.8 or Service.steer_feel(car, 0.3, 1.0) != 0.3 or Service.lamp(car, 2.0) != 1.0:
		errors.append("Undamaged parts should leave throttle, steering and lights alone")
	for part in Service.PARTS:
		if Service.symptom(part, 0.6) == "" or Service.symptom(part, 0.6) == Service.symptom(part, 0.0):
			errors.append("Service.symptom should say in plain words what a damaged %s does" % part)
	var bad := RaceCar.new()
	Service.fit(bad, {"Engine": 0.8, "Gearbox": 0.8, "Brakes": 0.8, "Suspension": 0.8, "Steering": 0.8, "Body": 0.8, "Exhaust": 0.8, "Electrics": 0.8}, 0.0)
	if not bad.fx_on or bad.fx_power >= 1.0 or bad.fx_brake >= 1.0 or bad.fx_grip >= 1.0 or bad.fx_drag <= 1.0:
		errors.append("Damaged engine/brakes/suspension/body should cost power, braking, grip and add drag: %s" % [[bad.fx_power, bad.fx_brake, bad.fx_grip, bad.fx_drag]])
	var cut := 0
	var dim := 0
	for k in 600:
		if Service.misfire(bad, k / 120.0, 1.0) < bad.fx_power * 0.5:
			cut += 1
		if Service.lamp(bad, k / 120.0) < 0.2:
			dim += 1
	if cut == 0 or cut > 300:
		errors.append("A badly damaged engine should misfire now and then (cut %d of 600 ticks)" % cut)
	if dim == 0 or Service.lamp(bad, 0.0) >= 1.0:
		errors.append("Damaged electrics should dim and flicker the headlights")
	if absf(Service.steer_feel(bad, 0.02, 0.0)) > 0.02 + 1e-6 and Service.steer_feel(bad, 0.02, 0.0) == 0.02:
		errors.append("A bent rack should be vague round the centre")
	if absf(Service.steer_feel(bad, 0.0, 1.0)) < 0.03:
		errors.append("Damaged brakes should pull the car to one side under braking")
	bad.gear = 4
	bad.fx_gear = 4
	Service.gearbox(bad, 4, 0.0)
	if bad.gear != 3:
		errors.append("A badly damaged gearbox should lose top gear (gear %d)" % bad.gear)
	var shifts := 0
	var slow := 0
	for k in 40:
		bad.gear = 1
		bad.fx_gear = 2
		bad.shift_t = 0.15
		Service.gearbox(bad, 4, k * 0.0531)
		if bad.gear == 2:
			shifts += 1 # missed: still in the old gear
		elif bad.shift_t > 0.15:
			slow += 1
	if shifts == 0 or slow == 0:
		errors.append("A damaged gearbox should miss some shifts and slow the rest (missed %d, slow %d)" % [shifts, slow])
	var parts := {}
	Service.spread(bad, 0.0, 1.0)
	parts = Service.snapshot(bad)
	if parts.is_empty():
		errors.append("Service.snapshot should keep the damaged parts")

## The same race with a sound car fitted with no parts runs identically; a damaged engine and body cost time.
func _check_race_effects(errors: Array[String]) -> void:
	var pos := []
	for parts in [null, {}, {"Engine": 1.0, "Body": 1.0, "Exhaust": 1.0}]:
		var rs := RaceSettings.new()
		rs.track = "monza"
		rs.laps = 2
		rs.opponents = 2
		var race := Race.new(rs, null, 11)
		if parts != null:
			Service.fit(race.player, parts, 0.0)
		var inp := Race.PlayerInput.new()
		for i in 1500:
			inp.throttle = 1.0
			race.step(1.0 / 120.0, inp)
		pos.append([race.player.s, race.player.x, race.player.y, race.cars[1].s])
		race.dispose()
	if pos[0] != pos[1]:
		errors.append("Fitting an undamaged car should change nothing: %s vs %s" % [pos[0], pos[1]])
	if not (pos[2][0] < pos[0][0] - 1.0):
		errors.append("A damaged engine and body should cost distance (%.1f m vs %.1f m)" % [pos[2][0], pos[0][0]])

## Season settings: picked before round 1, saved with the championship, locked once it is under way.
func _check_season(errors: Array[String], game) -> void:
	game.is_championship_mode = true
	game.is_campaign_mode = false
	game._reset_championship()
	game._update_mode_view()
	if game._season_locked():
		errors.append("A fresh season should be open for set-up")
	if game._calendar() != game.CHAMPIONSHIP_CALENDAR:
		errors.append("The default season should be the classic calendar")
	var polish: Array = game.SEASON_PRESETS[1].tracks
	game.season_preset_picker.select(1)
	game.season_opponents_picker.select(5) # 6 opponents
	game.season_weather_picker.select(game.SEASON_WEATHERS.size() - 1) # random each round
	game.season_damage_picker.select(2) # hardcore
	game.season_points_picker.select(2)
	game.season_length_picker.select(0)
	game._season_changed()
	if game._calendar() != polish:
		errors.append("Picking Polish Tour should make it the calendar, got %s" % [game._calendar()])
	if game._service_allocation() != 30:
		errors.append("Hardcore damage should give 30 minutes of service, got %d" % game._service_allocation())
	if game._points_table()[0] != 10:
		errors.append("The points preset should score 10 for a win")
	if game._season_laps("wilamowice") != maxi(1, roundi(game.TRACK_DEFAULTS.wilamowice.laps * 0.5)):
		errors.append("Sprint length should halve the laps")
	var w0: String = game._season_weather(0)
	if not w0 in game.WEATHER_KEYS or game._season_weather(0) != w0:
		errors.append("Random weather should roll a fixed weather per round")
	# ticking a circuit off makes the calendar custom
	(game.season_track_toggles["bor"] as CheckButton).button_pressed = false
	if "bor" in game._calendar() or game._season().preset != game.SEASON_PRESETS.size() - 1 or game._calendar().size() != polish.size() - 1:
		errors.append("Unticking Bór should drop it from a Custom calendar: %s" % [game._calendar()])
	# saved with the championship
	var cal: Array = game._calendar().duplicate()
	game._load_championship()
	if game._calendar() != cal or int(game._season().opponents) != 6 or int(game._season().damage) != 2:
		errors.append("The season's settings should be saved with the championship: %s" % [game._season()])
	# locked once round 1 is raced
	game.champ_data["round"] = 1
	game._update_championship_view()
	if not game._season_locked() or not game.season_preset_picker.disabled or not (game.season_track_toggles["krakow"] as CheckButton).disabled:
		errors.append("The season's settings should lock once round 1 is raced")
	game.season_preset_picker.select(0)
	game._season_changed()
	if game._calendar() != cal:
		errors.append("A locked season should ignore changes")
	game._reset_championship()
	if game._season_locked() or game._calendar() != cal:
		errors.append("RESET SEASON should unlock the settings and keep them")
	# the round is raced on the season's settings
	game.champ_data["config"]["damage"] = 1
	game._save_championship()

## Damage carries over to the next round / stage, the service area comes first, and repairs take time.
func _check_carry_over(errors: Array[String], game) -> void:
	var rs := RaceSettings.new()
	rs.track = "monza"
	rs.laps = 1
	rs.opponents = 2
	var race := Race.new(rs, null, 3)
	Service.fit(race.player, {"Engine": 0.6, "Brakes": 0.5, "Body": 0.4}, 0.02)
	game.is_championship_mode = true
	game.is_campaign_mode = false
	game._reset_championship()
	game._score_championship_round(race.results())
	var car: Dictionary = game._carried_car()
	if not car.get("parts", {}).has("Engine") or car.get("serviced", true):
		errors.append("The championship car should carry its damaged parts to the service area: %s" % [car])
	if not game._service_due():
		errors.append("A damaged car should be due a service before the next round")
	game._start_race()
	if game.active_menu_page != "repair" or game.race != null:
		errors.append("Starting the next round with a damaged car should open the service area first (page %s)" % game.active_menu_page)
	if not String(game.repair_summary.text).contains("ENGINE") or not String(game.repair_summary.text).contains("power"):
		errors.append("The service area should say what the unrepaired parts will do: '%s'" % game.repair_summary.text)
	if not game.repair_continue.visible:
		errors.append("The service area should offer CONTINUE to the next round")
	var engine := Service.PARTS.keys().find("Engine")
	var before: int = game._service_left()
	game._select_repair_part(engine)
	game._repair_selected()
	car = game._carried_car()
	if car.parts.has("Engine") or game._service_left() >= before:
		errors.append("Repairing the engine should fix it and use service time")
	if not car.parts.has("Brakes"):
		errors.append("Parts the crew didn't repair should still be broken")
	if game._service_due():
		errors.append("After the service area the next round should go ahead")
	var fitted := RaceCar.new()
	Service.fit(fitted, car.parts, float(car.get("pull", 0.0)))
	if fitted.fx_brake >= 1.0 or fitted.fx_power < 1.0 - 0.08:
		errors.append("The next round's car should start with the unrepaired brakes only")
	# the championship with damage off rebuilds the car
	game._reset_championship()
	game.champ_data["config"]["damage"] = 0
	game._score_championship_round(race.results())
	if game._service_due() or not game._carried_car().is_empty():
		errors.append("With damage off the championship car should be rebuilt for every round")
	game.champ_data["config"]["damage"] = 1
	# damage is for rally (and a championship that turns it on): the campaign never carries a car or stops at the service area
	game.is_championship_mode = false
	game.is_campaign_mode = true
	CampaignData.save_car({"parts": {"Suspension": 0.7}, "pull": 0.03, "used": 0, "serviced": false})
	if game._service_due() or not game._carried_car().is_empty() or game._servicing():
		errors.append("The campaign should start every stage with a sound car and no service stop")
	race.dispose()
	game.is_campaign_mode = false

## Every page works from the gamepad: d-pad / stick, A, B, LB / RB; no popup lists left on the front end.
func _check_pad_menus(errors: Array[String], game) -> void:
	if not game.find_children("*", "OptionButton", true, false).is_empty():
		errors.append("The front end should use ◂ ▸ selectors, not OptionButton popups")
	game._show_home()
	var ids: Array = game.FRONT_MENU.map(func(e): return e.id)
	game._home_select(ids.find("quick_race"), false)
	game._unhandled_input(_pad(JOY_BUTTON_DPAD_RIGHT))
	if game.FRONT_MENU[game.home_menu_index].id != "rally":
		errors.append("D-pad right on the main menu should move to RALLY")
	game._unhandled_input(_pad(JOY_BUTTON_A))
	if game.active_menu_page != "setup" or not game.is_rally_mode or game.track_picker.is_visible_in_tree() \
			or not game.rally_event_picker.is_visible_in_tree() or not game._setup_focus_items().has(game.rally_event_picker):
		errors.append("RALLY should open the set-up page with the event picker (on the pad) instead of the circuit")
	game._input(_pad(JOY_BUTTON_B))
	game._home_select(ids.find("rally"), false)
	game._unhandled_input(_pad(JOY_BUTTON_DPAD_RIGHT))
	if game.FRONT_MENU[game.home_menu_index].id != "time_trial":
		errors.append("D-pad right after RALLY should move to TIME TRIAL")
	game._unhandled_input(_pad(JOY_BUTTON_A))
	if game.is_rally_mode or not game.tt_start_picker.is_visible_in_tree():
		errors.append("TIME TRIAL leaves rally mode and offers the standing / rolling start")
	if game.active_menu_page != "setup" or not game.is_time_trial_mode or game.opponents_picker.is_visible_in_tree():
		errors.append("TIME TRIAL should open the set-up page for a solo run (no opponents field)")
	game._input(_pad(JOY_BUTTON_B))
	game._home_select(ids.find("quick_race"), false)
	game._unhandled_input(_pad(JOY_BUTTON_A))
	if game.is_time_trial_mode or not game.opponents_picker.is_visible_in_tree():
		errors.append("QUICK RACE should show the opponents again")
	var items: Array = game._setup_focus_items()
	game._focus_setup_item(items, items.find(game.track_picker))
	var track: int = game.track_picker.selected
	game._input(_pad(JOY_BUTTON_DPAD_RIGHT))
	if game.track_picker.selected != track + 1:
		errors.append("D-pad right on the circuit should pick the next one")
	game._input(_pad(JOY_BUTTON_DPAD_LEFT))
	game._input(_pad(JOY_BUTTON_DPAD_DOWN))
	if game.get_viewport().gui_get_focus_owner() == game.track_picker:
		errors.append("D-pad down should move to the next setting")
	# the essentials up front, the rest in titled groups on the Advanced and Car pages
	for key in ["race", "driving", "driver", "car", "strategy", "rules"]:
		if not game.setup_folds.has(key) or not game.setup_folds[key].get("fixed", false):
			errors.append("'%s' should be a titled group, not a folded section" % key)
	for c in [game.track_picker, game.laps_picker, game.opponents_picker, game.difficulty_picker, game.weather_picker]:
		var up: Node = c
		while up and up != game.setup_column:
			for key in game.setup_folds:
				if game.setup_folds[key].body == up:
					errors.append("%s should be up front, not in the %s group" % [c.get_class(), key])
			up = up.get_parent()
	game._input(_pad(JOY_BUTTON_RIGHT_SHOULDER))
	if game.active_menu_page != "advanced":
		errors.append("RB should switch to Advanced")
	game._input(_pad(JOY_BUTTON_RIGHT_SHOULDER))
	if game.active_menu_page != "car":
		errors.append("RB again should switch to Car")
	game._input(_pad(JOY_BUTTON_RIGHT_SHOULDER))
	if game.active_menu_page != "strategy":
		errors.append("RB again should switch to Strategy")
	game._input(_pad(JOY_BUTTON_RIGHT_SHOULDER))
	if game.active_menu_page != "strategy" or (game.menu_tab_buttons["Service"] as Control).visible:
		errors.append("A quick race has no Service page: RB on Strategy should stay put")
	game._show_repair_page() # a service area (as after a championship round) still works
	var part: int = game.repair_selected
	game._input(_pad(JOY_BUTTON_DPAD_DOWN))
	if game.repair_selected != mini(part + 1, Service.PARTS.size() - 1):
		errors.append("D-pad down should pick the next part in the service area")
	game._input(_pad(JOY_BUTTON_B))
	if game.active_menu_page != "home":
		errors.append("B should go back to the main menu")
	game._home_select(ids.find("options"), false)
	game._unhandled_input(_pad(JOY_BUTTON_A))
	game._focus_page()
	var first: Control = game.get_viewport().gui_get_focus_owner()
	if first == null or not game.options_panel.is_ancestor_of(first):
		errors.append("The Options page should put the focus on its first setting")
	game._input(_pad(JOY_BUTTON_DPAD_DOWN))
	if game.get_viewport().gui_get_focus_owner() == first:
		errors.append("D-pad down should move through the Options")
	game._input(_pad(JOY_BUTTON_B))
	if game.active_menu_page != "home":
		errors.append("B on Options should go back to the main menu")
	if not String(game._hint("setup")).contains("Esc") and not String(game._hint("setup")).contains("Ⓑ"):
		errors.append("The set-up page should show its button prompts")

func _pad(button: JoyButton) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	ev.pressed = true
	return ev

func _backup(files: Array) -> Dictionary:
	var out := {}
	for f in files:
		var p := SaveData.path(f)
		out[p] = FileAccess.get_file_as_string(p) if FileAccess.file_exists(p) else null
	return out

func _restore(saves: Dictionary) -> void:
	for p in saves:
		if saves[p] == null:
			DirAccess.remove_absolute(p)
		else:
			var f := FileAccess.open(p, FileAccess.WRITE)
			f.store_string(saves[p])
