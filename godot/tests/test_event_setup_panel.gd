## Pre-start event settings pop-up (EventSetupPanel): builds for campaign lap stages, A->B sprint stages,
## Away Races stages, campaign missions and live events; displays stage/event info, expected class, grid and
## live rival level; edits and saves DifficultyProfile.current (rival step, assist preset, expandable individual
## aids, shifting, racing line, damage, auto-recover; fuel/tyre wear shown as "Off in campaign") with live fan
## multiplier; controller-first navigation (focus opens on START, D-pad/stick, LB/RB and ◂ ▸, START/A/B/Esc,
## focus never escapes); pauses OpenWorld behind it (car stops, time doesn't run) and triggers or cancels cleanly.
extends RefCounted

var completed := false
var errors: Array[String] = []

const TEST_PROFILE := "test_event_setup_difficulty.cfg"
const TEST_CAMPAIGN := "test_event_setup_campaign.json"

func check(ok: bool, what: String) -> void:
	if not ok:
		errors.append(what)

static func _key(code: Key, pressed := true, shift := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	e.shift_pressed = shift
	return e

static func _pad(button: JoyButton, pressed := true) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.pressed = pressed
	return e

static func _axis(axis: JoyAxis, v: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = v
	return e

func run() -> Array:
	Brain.use_disk = false
	LapRecords.use_disk = false
	var saved_profile := DifficultyProfile.current.duplicate()
	var saved_camp := Campaign.save_file
	var profile_path := SaveData.path(TEST_PROFILE)
	var real_profile_path := SaveData.path(DifficultyProfile.FILE)
	var real_profile_bytes: Variant = FileAccess.get_file_as_bytes(real_profile_path) if FileAccess.file_exists(real_profile_path) else null
	Campaign.save_file = TEST_CAMPAIGN
	Campaign.reset_progress()
	DifficultyProfile.current = DifficultyProfile.defaults()

	await _test_headers_and_layout(profile_path)
	await _test_profile_editing_and_save(profile_path)
	await _test_callbacks_and_buttons(profile_path)
	await _test_controller_focus_and_stick(profile_path)
	await _test_open_world_integration()

	DifficultyProfile.current = saved_profile
	Campaign.save_file = saved_camp
	DirAccess.remove_absolute(ProjectSettings.globalize_path(profile_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveData.path(TEST_CAMPAIGN)))
	if real_profile_bytes == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(real_profile_path))
	else:
		var fa := FileAccess.open(real_profile_path, FileAccess.WRITE)
		if fa:
			fa.store_buffer(real_profile_bytes as PackedByteArray)
			fa.close()
	completed = true
	return errors

## Builds the panel for a lap stage, an A->B sprint stage, an Away Races stage, a mission, and a live event;
## checks header fields, "Off in campaign" fuel/wear, and layout across 16:9, 4:3, 21:9 and 1.3x scale.
func _test_headers_and_layout(profile_path: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var host := Control.new()
	host.size = Vector2(1600, 900)
	tree.root.add_child(host)

	# 1. Lap stage (Bór, 2 laps)
	var bor_idx := Campaign.index_of("stage_3")
	var bor_st := Campaign.get_stage(bor_idx)
	var p := EventSetupPanel.open_in(host, EventSetupPanel.describe_stage(bor_idx, "stock"), profile_path)
	await tree.process_frame
	check(p.title_label.text == String(bor_st.title), "lap stage title: '%s'" % p.title_label.text)
	check(p.meta_label.text.contains(Campaign.length_label(bor_st)), "lap stage length missing: '%s'" % p.meta_label.text)
	check(p.meta_label.text.contains(String(bor_st.weather).capitalize()), "lap stage weather missing: '%s'" % p.meta_label.text)
	check(p.meta_label.text.contains("16:30"), "lap stage time missing: '%s'" % p.meta_label.text)
	check(p.class_label.text == Campaign.class_line(bor_st), "lap stage class_line mismatch: '%s'" % p.class_label.text)
	check(p.rivals_label.text.contains("P7 of 9"), "lap stage grid slot missing: '%s'" % p.rivals_label.text)
	check(p.rivals_label.text.contains("rivals"), "lap stage rival level missing: '%s'" % p.rivals_label.text)
	check(p.fuel_wear_label.text == "Off in campaign", "fuel/wear label: '%s'" % p.fuel_wear_label.text)
	check(p.start_button.visible and p.cancel_button.visible, "START/CANCEL not visible for lap stage")
	p.cancel()
	await tree.process_frame

	# 2. A->B sprint stage (Wola sprint)
	var wola_idx := Campaign.index_of("stage_wola")
	var wola_st := Campaign.get_stage(wola_idx)
	p = EventSetupPanel.open_in(host, EventSetupPanel.describe_stage(wola_idx, "stock"), profile_path)
	await tree.process_frame
	check(p.kicker_label.text.contains("SPRINT"), "sprint stage kicker: '%s'" % p.kicker_label.text)
	check(p.meta_label.text.contains(Campaign.length_label(wola_st)) and p.meta_label.text.contains("km sprint"),
		"sprint stage length: '%s'" % p.meta_label.text)
	check(p.class_label.text == Campaign.class_line(wola_st), "sprint stage class_line: '%s'" % p.class_label.text)
	p.cancel()
	await tree.process_frame

	# 3. Away Races stage (Monza)
	var monza_idx := Campaign.index_of("stage_monza")
	p = EventSetupPanel.open_in(host, EventSetupPanel.describe_stage(monza_idx, "stock", true), profile_path)
	await tree.process_frame
	check(p.kicker_label.text.contains("AWAY RACES"), "away stage kicker: '%s'" % p.kicker_label.text)
	check(p.class_note_label.visible and p.class_note_label.text.contains("Milan"), "away stage travel note: '%s'" % p.class_note_label.text)
	p.cancel()
	await tree.process_frame

	# 4. Campaign mission (drag + drift)
	var drag_idx := Missions.index_of("drag_quarter")
	p = EventSetupPanel.open_in(host, EventSetupPanel.describe_mission(drag_idx, "stock"), profile_path)
	await tree.process_frame
	check(p.kicker_label.text.contains("DRAG RACE MISSION"), "mission kicker: '%s'" % p.kicker_label.text)
	check(p.title_label.text.contains("Ćwierć Mili"), "mission title: '%s'" % p.title_label.text)
	check(p.meta_label.text.contains("402 m") and p.meta_label.text.contains("21:30"), "mission meta: '%s'" % p.meta_label.text)
	check(p.rivals_label.text.contains("Pole") and p.rivals_label.text.contains("3 rivals"), "mission rivals/grid: '%s'" % p.rivals_label.text)
	p.cancel()
	await tree.process_frame

	var drift_idx := Missions.index_of("drift_babudy")
	p = EventSetupPanel.open_in(host, EventSetupPanel.describe_mission(drift_idx, "stock"), profile_path)
	await tree.process_frame
	var before_drift_rivals := p.rivals_label.text
	(p.controls.step as MenuSelector).step(2) # Average -> Expert scales drift targets
	check(p.rivals_label.text != before_drift_rivals, "drift mission targets did not update on rival step change")
	DifficultyProfile.current = DifficultyProfile.defaults()
	p.cancel()
	await tree.process_frame

	# 5. Live event (sprint)
	var fake_live := {
		"id": "live_99", "kind": "race", "mkind": "sprint", "title": "ul. Dworcowa ▸ ul. Bór",
		"length": 2800.0, "rivals": 6, "target": 3, "difficulty": "medium", "color": Color("#ff3d8b"),
		"path": PackedVector2Array([Vector2.ZERO, Vector2(2800.0, 0.0)]),
	}
	p = EventSetupPanel.open_in(host, EventSetupPanel.describe_live(fake_live, null, "golf4", 22.25, "Wet"), profile_path)
	await tree.process_frame
	check(p.kicker_label.text.contains("LIVE SPRINT"), "live event kicker: '%s'" % p.kicker_label.text)
	check(p.title_label.text == "ul. Dworcowa ▸ ul. Bór", "live event title: '%s'" % p.title_label.text)
	check(p.meta_label.text.contains("2.8 km") and p.meta_label.text.contains("Wet") and p.meta_label.text.contains("22:15"),
		"live event meta: '%s'" % p.meta_label.text)
	check(p.rivals_label.text.contains("6 rivals"), "live event rivals: '%s'" % p.rivals_label.text)
	# Layout across canvases (collapsed and expanded): panel inside canvas, START/CANCEL always inside panel
	for canvas: Vector2 in [Vector2(1600, 900), Vector2(1600, 1200), Vector2(2133, 900), Vector2(1231, 692)]:
		host.size = canvas
		p.size = canvas
		p._layout()
		await tree.process_frame
		var pr := p.panel.get_global_rect()
		check(Rect2(Vector2.ZERO, canvas).grow(1.0).encloses(pr), "%s: panel leaves canvas (%s)" % [canvas, pr])
		check(pr.grow(1.0).encloses(p.start_button.get_global_rect()), "%s: START outside panel" % canvas)
		check(pr.grow(1.0).encloses(p.cancel_button.get_global_rect()), "%s: CANCEL outside panel" % canvas)
		p.set_aids_expanded(true)
		await tree.process_frame
		check(pr.grow(1.0).encloses(p.start_button.get_global_rect()), "%s (expanded): START pushed outside panel" % canvas)
		check(pr.grow(1.0).encloses(p.cancel_button.get_global_rect()), "%s (expanded): CANCEL pushed outside panel" % canvas)
		p.set_aids_expanded(false)
	p.cancel()
	host.queue_free()
	await tree.process_frame

## Changing every selector writes DifficultyProfile.current, saves to disk, and updates the fan multiplier.
func _test_profile_editing_and_save(profile_path: String) -> void:
	DifficultyProfile.current = DifficultyProfile.defaults()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(profile_path))
	var tree := Engine.get_main_loop() as SceneTree
	var host := Control.new()
	host.size = Vector2(1600, 900)
	tree.root.add_child(host)
	var p := EventSetupPanel.open_in(host, EventSetupPanel.describe_stage(0, "stock"), profile_path)
	await tree.process_frame

	check(p.fans_label.text.contains("×1.00") and p.fans_label.text.contains("STANDARD"), "default fan multiplier: '%s'" % p.fans_label.text)
	var base_rivals := p.rivals_label.text

	# Rival step via LB / RB on the step selector
	(p.controls.step as Control).grab_focus()
	p._input(_pad(JOY_BUTTON_RIGHT_SHOULDER))
	check(int(DifficultyProfile.current.step) == DifficultyProfile.AVERAGE + 1, "RB did not increment rival step (%d)" % int(DifficultyProfile.current.step))
	check(p.fans_label.text.contains("+10%"), "fan multiplier after step +1: '%s'" % p.fans_label.text)
	check(p.rivals_label.text != base_rivals, "header rival level did not update with step")
	check(FileAccess.file_exists(profile_path), "changing rival step did not save profile")

	p._input(_pad(JOY_BUTTON_LEFT_SHOULDER))
	check(int(DifficultyProfile.current.step) == DifficultyProfile.AVERAGE, "LB did not decrement rival step")

	# Preset -> Pro via D-pad Right twice (Beginner -> Default -> Pro)
	(p.controls.preset as Control).grab_focus()
	p._input(_pad(JOY_BUTTON_DPAD_RIGHT))
	check(DifficultyProfile.preset_index(DifficultyProfile.current) == 1, "preset did not step to Default")
	p._input(_pad(JOY_BUTTON_DPAD_RIGHT))
	check(DifficultyProfile.preset_index(DifficultyProfile.current) == 2 and String(DifficultyProfile.current.shifting) == "manual" and String(DifficultyProfile.current.line) == "off",
		"preset did not step to Pro: %s" % DifficultyProfile.current)

	# Expand individual aids and toggle ABS back on -> preset switches to Custom
	p.aids_toggle.grab_focus()
	p._input(_pad(JOY_BUTTON_A))
	check(p.aids_expanded and p.aids_box.visible, "A on aids_toggle did not expand individual aids")
	(p.controls.abs as Control).grab_focus()
	p._input(_pad(JOY_BUTTON_DPAD_RIGHT))
	check(bool(DifficultyProfile.current.abs) and DifficultyProfile.preset_index(DifficultyProfile.current) == 3,
		"toggling ABS did not update profile to Custom: %s" % DifficultyProfile.current)
	check((p.controls.preset as MenuSelector).selected == 3, "preset selector did not show Custom")

	# Stepping Right from Custom wraps cleanly to Beginner (does not get stuck on disabled Custom)
	(p.controls.preset as Control).grab_focus()
	p._input(_pad(JOY_BUTTON_DPAD_RIGHT))
	check(DifficultyProfile.preset_index(DifficultyProfile.current) == 0, "stepping right from Custom did not select Beginner")

	# Shifting, racing line, damage, auto-recover
	(p.controls.shifting as Control).grab_focus()
	p._input(_key(KEY_RIGHT))
	check(String(DifficultyProfile.current.shifting) == "manual", "shifting did not switch to manual")

	(p.controls.line as Control).grab_focus()
	p._input(_key(KEY_RIGHT))
	check(String(DifficultyProfile.current.line) == "braking", "line did not switch to braking")

	(p.controls.damage as Control).grab_focus()
	for _i in 3:
		p._input(_key(KEY_RIGHT))
	check(String(DifficultyProfile.current.damage) == "full", "damage did not switch to full")

	(p.controls.recover as Control).grab_focus()
	p._input(_key(KEY_LEFT))
	check(not bool(DifficultyProfile.current.recover), "auto-recover did not switch off")

	# Reload from disk and verify exact round-trip
	var expected := DifficultyProfile.current.duplicate()
	DifficultyProfile.current = DifficultyProfile.defaults()
	check(DifficultyProfile.load_profile(profile_path), "saved profile failed to load back")
	check(DifficultyProfile.current == expected, "reloaded profile differs: %s vs %s" % [DifficultyProfile.current, expected])

	p.cancel()
	host.queue_free()
	await tree.process_frame
	DifficultyProfile.current = DifficultyProfile.defaults()

## START emits started (and not cancelled); CANCEL / Esc / B emits cancelled (and not started).
func _test_callbacks_and_buttons(profile_path: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var host := Control.new()
	host.size = Vector2(1600, 900)
	tree.root.add_child(host)

	# START via Enter (opens focused on START)
	var counts := [0, 0] # [started, cancelled]
	var p := EventSetupPanel.open_in(host, EventSetupPanel.describe_stage(0), profile_path)
	p.started.connect(func(): counts[0] += 1)
	p.cancelled.connect(func(): counts[1] += 1)
	await tree.process_frame
	check(host.get_viewport().gui_get_focus_owner() == p.start_button, "focus did not start on START")
	p._input(_key(KEY_ENTER))
	check(counts == [1, 0] and p.is_queued_for_deletion(), "Enter on START: counts=%s" % [counts])
	await tree.process_frame

	# START via pad A on START
	counts = [0, 0]
	p = EventSetupPanel.open_in(host, EventSetupPanel.describe_stage(0), profile_path)
	p.started.connect(func(): counts[0] += 1)
	p.cancelled.connect(func(): counts[1] += 1)
	await tree.process_frame
	p._input(_pad(JOY_BUTTON_A))
	check(counts == [1, 0], "Pad A on START: counts=%s" % [counts])
	await tree.process_frame

	# Gamepad START button launches from anywhere in the panel
	counts = [0, 0]
	p = EventSetupPanel.open_in(host, EventSetupPanel.describe_stage(0), profile_path)
	p.started.connect(func(): counts[0] += 1)
	p.cancelled.connect(func(): counts[1] += 1)
	await tree.process_frame
	(p.controls.step as Control).grab_focus()
	p._input(_pad(JOY_BUTTON_START))
	check(counts == [1, 0], "Pad START from selector: counts=%s" % [counts])
	await tree.process_frame

	# CANCEL via Esc
	counts = [0, 0]
	p = EventSetupPanel.open_in(host, EventSetupPanel.describe_stage(0), profile_path)
	p.started.connect(func(): counts[0] += 1)
	p.cancelled.connect(func(): counts[1] += 1)
	await tree.process_frame
	p._input(_key(KEY_ESCAPE))
	check(counts == [0, 1] and p.is_queued_for_deletion(), "Esc cancel: counts=%s" % [counts])
	await tree.process_frame

	# CANCEL via pad B
	counts = [0, 0]
	p = EventSetupPanel.open_in(host, EventSetupPanel.describe_stage(0), profile_path)
	p.started.connect(func(): counts[0] += 1)
	p.cancelled.connect(func(): counts[1] += 1)
	await tree.process_frame
	p._input(_pad(JOY_BUTTON_B))
	check(counts == [0, 1], "Pad B cancel: counts=%s" % [counts])
	await tree.process_frame

	# CANCEL by stepping Right from START -> CANCEL and pressing Enter
	counts = [0, 0]
	p = EventSetupPanel.open_in(host, EventSetupPanel.describe_stage(0), profile_path)
	p.started.connect(func(): counts[0] += 1)
	p.cancelled.connect(func(): counts[1] += 1)
	await tree.process_frame
	p._input(_pad(JOY_BUTTON_DPAD_RIGHT))
	check(host.get_viewport().gui_get_focus_owner() == p.cancel_button, "Right from START did not focus CANCEL")
	p._input(_key(KEY_ENTER))
	check(counts == [0, 1], "Enter on CANCEL: counts=%s" % [counts])
	await tree.process_frame

	# Mouse press on START button triggers started
	counts = [0, 0]
	p = EventSetupPanel.open_in(host, EventSetupPanel.describe_stage(0), profile_path)
	p.started.connect(func(): counts[0] += 1)
	p.cancelled.connect(func(): counts[1] += 1)
	await tree.process_frame
	p.start_button.pressed.emit()
	check(counts == [1, 0], "Mouse click START: counts=%s" % [counts])
	await tree.process_frame

	host.queue_free()
	await tree.process_frame

## Focus starts on START, moves with D-pad/stick/Tab, recovers if released or hidden, and never leaves the panel.
func _test_controller_focus_and_stick(profile_path: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var host := Control.new()
	host.size = Vector2(1600, 900)
	tree.root.add_child(host)
	var outside := Button.new()
	outside.text = "OUTSIDE"
	host.add_child(outside)

	var p := EventSetupPanel.open_in(host, EventSetupPanel.describe_stage(0), profile_path)
	await tree.process_frame
	var vp := host.get_viewport()
	check(vp.gui_get_focus_owner() == p.start_button, "focus did not start on START")

	# Down from START wraps to first setting (step); Up from START goes to last setting (recover)
	p._input(_pad(JOY_BUTTON_DPAD_DOWN))
	check(vp.gui_get_focus_owner() == p.controls.step, "Down from START did not land on step")
	p._input(_pad(JOY_BUTTON_DPAD_UP))
	check(vp.gui_get_focus_owner() == p.start_button, "Up from step did not return to START")
	p._input(_pad(JOY_BUTTON_DPAD_UP))
	check(vp.gui_get_focus_owner() == p.controls.recover, "Up from START did not land on recover")

	# Walk through every focusable item via D-pad Down: focus stays inside panel at every step
	var items := p.focus_items()
	for _i in items.size() + 3:
		p._input(_pad(JOY_BUTTON_DPAD_DOWN))
		var cur := vp.gui_get_focus_owner()
		check(cur != null and p.focus_items().has(cur) and cur != outside, "focus escaped panel during Down walk: %s" % cur)

	# Left stick latch & deadzone
	p.start_button.grab_focus()
	p._input(_axis(JOY_AXIS_LEFT_Y, 0.8)) # Down -> step
	check(vp.gui_get_focus_owner() == p.controls.step, "stick down did not move focus")
	p._input(_axis(JOY_AXIS_LEFT_Y, 0.9)) # held -> latched, should not move again
	check(vp.gui_get_focus_owner() == p.controls.step, "held stick moved focus twice")
	p._input(_axis(JOY_AXIS_LEFT_Y, 0.1)) # release
	p._input(_axis(JOY_AXIS_LEFT_Y, 0.8)) # next push -> preset
	check(vp.gui_get_focus_owner() == p.controls.preset, "stick after release did not move to preset")

	# Focus recovery if focus is externally cleared or moved outside
	outside.grab_focus()
	p._input(_pad(JOY_BUTTON_DPAD_DOWN))
	check(p.focus_items().has(vp.gui_get_focus_owner()), "focus did not recover inside panel from outside button")
	vp.gui_release_focus()
	p._input(_key(KEY_TAB))
	check(p.focus_items().has(vp.gui_get_focus_owner()), "Tab did not keep focus inside panel")

	# Collapsing individual aids while an aid has focus moves focus back to aids_toggle
	p.set_aids_expanded(true)
	(p.controls.esc as Control).grab_focus()
	p.set_aids_expanded(false)
	check(vp.gui_get_focus_owner() == p.aids_toggle, "collapsing aids lost focus: %s" % vp.gui_get_focus_owner())

	p.cancel()
	host.queue_free()
	await tree.process_frame

## OpenWorld hooks: Enter at a beacon opens the settings pop-up and pauses sim + clock; Cancel returns to free roam;
## Start applies DifficultyProfile changes and launches the stage / away cutscene / mission / live event.
func _test_open_world_integration() -> void:
	var map := TownMap.load_map(OpenWorld.MAP_KEY)
	check(map != null, "open world map failed to load")
	if map == null:
		return
	var world_file := SaveData.path(WorldProgress.SAVE_FILE)
	var saved_world: Variant = FileAccess.get_file_as_string(world_file) if FileAccess.file_exists(world_file) else null
	DifficultyProfile.current = DifficultyProfile.defaults()
	Campaign.reset_progress()
	Story.mark_seen([Story.before_key(0)]) # focus on the setup pop-up flow

	var tree := Engine.get_main_loop() as SceneTree
	var ow := OpenWorld.new()
	ow.size = Vector2(1600, 900)
	tree.root.add_child(ow)
	await tree.process_frame
	ow.map = map
	ow.progress = WorldProgress.new()
	ow.world = Node3D.new()
	ow.add_child(ow.world)
	ow.route_mesh = MeshInstance3D.new()
	ow.world.add_child(ow.route_mesh)
	ow.builder = TownBuilder.new(map, ow.world)
	ow.drive = FreeCar.new(map)
	ow.car_visual = OpenWorld.CAR_SCENE.instantiate()
	ow.world.add_child(ow.car_visual)
	ow.camera = Camera3D.new()
	ow.world.add_child(ow.camera)
	ow.built = true
	ow.active = true
	ow.set_process(false) # partial headless world (no traffic/train): drive _process explicitly while testing pause
	ow.show()
	ow.hour = 14.0
	ow._refresh_events()

	var asked: Array[int] = []
	ow.stage_requested.connect(func(i: int): asked.append(i))

	# 1. Stage beacon (stage 0 sprint): Enter opens EventSetupPanel, pauses car & clock, Esc cancels, START launches
	var s0 := -1
	for k in ow.events.size():
		if not ow.events[k].has("live") and not ow.events[k].has("mission") and int(ow.events[k].stage) == 0:
			s0 = k
			break
	check(s0 >= 0, "stage 0 beacon not found")
	if s0 >= 0:
		ow.drive.place(ow.events[s0].pos as Vector2, 0.0)
		ow.drive.car.vx = 12.0
		ow._check_events()
		ow._input(_key(KEY_ENTER))
		await tree.process_frame
		check(ow._setup_open() and asked.is_empty(), "Enter at stage beacon did not open EventSetupPanel")
		# Open world is paused behind it: car does not move and hour does not advance
		var pos0 := Vector2(ow.drive.car.x, ow.drive.car.y)
		var hour0 := ow.hour
		ow._process(0.5)
		check(Vector2(ow.drive.car.x, ow.drive.car.y).distance_to(pos0) < 1e-4, "car moved while EventSetupPanel was open")
		check(is_equal_approx(ow.hour, hour0), "clock advanced while EventSetupPanel was open (%.4f -> %.4f)" % [hour0, ow.hour])
		# Cancel closes pop-up without starting stage
		ow.event_setup._input(_key(KEY_ESCAPE))
		await tree.process_frame
		check(not ow._setup_open() and asked.is_empty(), "Esc did not cancel EventSetupPanel cleanly")
		# Open again, change shifting to manual, press Enter on START -> applies to drive & emits stage_requested
		ow._input(_key(KEY_ENTER))
		await tree.process_frame
		(ow.event_setup.controls.shifting as MenuSelector).step(1)
		ow.event_setup._input(_key(KEY_ENTER))
		await tree.process_frame
		check(not ow._setup_open() and asked == [0], "START did not launch stage 0: asked=%s" % [asked])
		check(ow.drive.gearbox == "manual", "profile shifting change did not apply to OpenWorld drive")

	# 2. Live event beacon: Enter opens EventSetupPanel, START launches countdown
	ow.live = LiveEvents.new(map, 42)
	var home := Vector2(map.spots.festival[0], map.spots.festival[1])
	var sp := ow.live.generate(home + Vector2(400.0, 0.0), ow._beacon_points(), "sprint")
	if not sp.is_empty():
		ow.live.board.append(sp)
		ow._live_sync()
		var li := -1
		for k in ow.events.size():
			if String(ow.events[k].get("live", "")) == String(sp.id):
				li = k
				break
		if li >= 0:
			ow.drive.place(ow.events[li].pos as Vector2, 0.0)
			ow._check_events()
			ow._input(_key(KEY_ENTER))
			await tree.process_frame
			check(ow._setup_open() and not ow.live.is_running(), "Enter at live beacon did not open EventSetupPanel")
			ow.event_setup._input(_key(KEY_ENTER))
			await tree.process_frame
			check(not ow._setup_open() and ow.live.holding(), "START on live event did not start countdown")
			ow._end_run()

	# 3. Mission beacon: Enter opens EventSetupPanel, START launches mission on map
	var di := Missions.index_of("drag_quarter")
	Campaign.record_result(0, 1)
	ow.progress.record_live("sprint", 1)
	ow.progress.record_live("drift", 1)
	Story.mark_seen([Story.before_key(di)])
	ow._refresh_events()
	var mi := -1
	for k in ow.events.size():
		if ow.events[k].has("mission") and int(ow.events[k].stage) == di and bool(ow.events[k].open):
			mi = k
			break
	if mi >= 0:
		ow.drive.place(ow.events[mi].pos as Vector2, 0.0)
		ow._check_events()
		ow._input(_key(KEY_ENTER))
		await tree.process_frame
		check(ow._setup_open() and not ow.live.is_running(), "Enter at mission beacon did not open EventSetupPanel")
		ow.event_setup._input(_key(KEY_ENTER))
		await tree.process_frame
		check(not ow._setup_open() and ow.live.holding(), "START on mission did not start countdown")
		ow._end_run()

	ow.queue_free()
	await tree.process_frame
	if saved_world == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(world_file))
	else:
		var f := FileAccess.open(world_file, FileAccess.WRITE)
		if f:
			f.store_string(String(saved_world))
