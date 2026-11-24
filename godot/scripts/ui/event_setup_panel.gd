## Pre-start event menu for the open world (campaign stages, A->B sprint stages, Away Races gate, campaign missions,
## and live events), styled as a compact Forza Horizon-inspired tile grid over the live parked car:
##   Row 1: [ START RACE EVENT (wide car photo tile) ]  [ OPTIONS ]  [ QUIT EVENT ]
##   Row 2: [ DIFFICULTY ]  [ CAR ]  [ STARTING GRID (wide track photo tile) ]
## Selecting DIFFICULTY or OPTIONS opens the in-place Difficulty & Assists settings page (saving live to
## DifficultyProfile.current with live fan-reward updates; fuel/tyre wear shown as "Off in campaign");
## STARTING GRID opens the grid lineup & event briefing; CAR opens the Garage to swap cars/paint before launch.
## Controller-first per Design Rule #6: opens on the hub focused on START, 2D D-pad/stick/arrow navigation across tiles,
## A / Enter activates, gamepad START launches from any page, B / Esc returns to the hub or cancels to free roam.
class_name EventSetupPanel
extends Control

signal started
signal cancelled
signal profile_changed
signal garage_requested

const SHIFTING_NAMES := ["Automatic", "Manual (E/Q)"]
const OFF_ON_NAMES := ["Off", "On"]

var info: Dictionary = {}
var save_file := "" ## "" saves to SaveData.path(DifficultyProfile.FILE); tests may override
var page := "hub" ## "hub" | "settings" | "grid"

var backdrop: ColorRect
var panel: Control ## fixed-size centered container (never a PanelContainer, so wrapped text can never blow up height)
var hub_page: VBoxContainer
var settings_page: PanelContainer
var grid_page: PanelContainer
var scroll: ScrollContainer

var kicker_label: Label
var title_label: Label
var fans_label: Label
var sub_fans_label: Label
var meta_label: Label
var target_label: Label
var rivals_label: Label
var class_label: Label
var class_note_label: Label
var step_note_label: Label
var fuel_wear_label: Label
var keys_label: Label
var sub_keys_label: Label
var grid_keys_label: Label

# Hub tile buttons (2x3 Forza Horizon grid)
var start_button: Button
var options_button: Button
var cancel_button: Button
var difficulty_button: Button
var car_button: Button
var grid_button: Button

# Dynamic tile captions / photos refreshed when profile or car changes
var _start_photo: TextureRect
var _start_sub: Label
var _options_sub: Label
var _diff_sub: Label
var _car_sub: Label
var _grid_photo: TextureRect
var _grid_rows_box: VBoxContainer
var _grid_brief_box: VBoxContainer
var _grid_preview: TextureRect
var _settings_sub_title: Label
var _grid_sub_title: Label

# Settings controls (DifficultyProfile.current)
var controls: Dictionary = {} ## "step", "preset", "abs", "tc", "esc", "steer", "brake", "shifting", "line", "damage", "recover"
var aids_toggle: Button
var aids_box: VBoxContainer
var aids_expanded := false
var back_button: Button
var sub_start_button: Button
var grid_back_button: Button
var grid_start_button: Button

var _syncing := false
var _closed := false
var _stick := [0, 0]
var _last_pad := false
var _return_tile: Button = null

## Opens the pop-up over `parent` for the described event `event_info` (from describe_stage / describe_mission /
## describe_live). The panel frees itself after emitting `started` or `cancelled`.
static func open_in(parent: Node, event_info: Dictionary, profile_save_file := "") -> EventSetupPanel:
	var p := EventSetupPanel.new()
	p.info = event_info.duplicate(true)
	p.save_file = profile_save_file
	parent.add_child(p)
	return p

# ------------------------------------------------------------------ event descriptors

## Describes a campaign stage (lap race, A->B sprint, or Away Races stage) for the menu.
static func describe_stage(stage_index: int, car_key := "stock", away := false, done := false) -> Dictionary:
	var st: Dictionary = Campaign.get_stage(stage_index)
	var tr_key := String(st.get("track", ""))
	var tr_def := Track.load_def(tr_key)
	var tr_name := tr_def.display_name if tr_def != null else tr_key.capitalize()
	var act := String(st.get("act_name", "")).to_upper()
	var kicker := "%sSTAGE %d/%d · %s" % ["AWAY RACES · " if away else "", stage_index + 1, Campaign.STAGES.size(), act]
	if Campaign.is_sprint(st):
		kicker += " · SPRINT"
	var target_pos := int(st.get("target_pos", 3))
	var target := "Win the race (P1)" if target_pos == 1 else "Finish P%d or better" % target_pos
	var opp := int(st.get("opponents", 5))
	var forced := String(st.get("car_class", ""))
	var effective_car := forced if forced != "" else car_key
	var advice := Campaign.class_advice(car_key, st) if forced == "" else "Everyone drives the %s." % CarCatalog.display_name(forced)
	var travel_note := ""
	if away:
		var trv := CampaignObjective.travel(stage_index)
		if not trv.is_empty():
			travel_note = CampaignObjective.upper_first(String(trv.get("line", "")))
	var grid_raw := String(st.get("grid", "middle"))
	return {
		"kind": "stage",
		"index": stage_index,
		"away": away,
		"sprint": Campaign.is_sprint(st),
		"kicker": kicker,
		"title": String(st.get("title", "")),
		"accent": OpenWorldHud.GOLD if done else OpenWorldHud.ORANGE,
		"track": tr_name,
		"track_key": tr_key,
		"length": Campaign.length_label(st),
		"weather": String(st.get("weather", "dry")).capitalize(),
		"time": hour_text(float(st.get("start_hour", st.get("time_of_day", 14.0)))),
		"class_line": Campaign.class_line(st),
		"class_advice": advice,
		"forced_car": forced,
		"travel_note": travel_note,
		"grid": grid_text(grid_raw, opp + 1),
		"grid_slot": grid_slot_index(grid_raw, opp + 1),
		"field_classes": Campaign.field_classes(st),
		"opponents": opp,
		"rival_unit": "rivals",
		"base_difficulty": String(st.get("difficulty", "medium")),
		"level_shift": float(st.get("level_shift", 0.0)),
		"base_label": Campaign.level_name(st),
		"eased": int(st.get("eased", 0)),
		"fails": int(st.get("fails", 0)),
		"heat": float(st.get("heat", 0.0)),
		"target": target,
		"car_key": effective_car,
		"desc": String(st.get("desc", "")),
		"tip": String(st.get("tip", "")),
	}

## Describes a campaign map mission (Missions.BASE + k) for the menu.
static func describe_mission(mission_index: int, car_key := "stock") -> Dictionary:
	var m: Dictionary = Missions.as_stage(mission_index)
	var kind := String(m.get("kind", "sprint"))
	var tr_key := String(MapMissions.OFF_MAP.get(String(m.get("track", "")), String(m.get("track", ""))))
	var tr_name := ""
	if kind == "rally":
		tr_name = String(Missions.rally_def(mission_index).get("name", ""))
	else:
		var tr_def := Track.load_def(tr_key)
		tr_name = tr_def.display_name if tr_def != null else tr_key.capitalize()
	var opp := int(m.get("opponents", 0))
	var grid_raw := String(m.get("grid", "pole"))
	var grid := "Solo"
	var slot := 1
	if kind == "rally":
		grid = "Standing start (stages)"
	elif opp > 0:
		grid = grid_text(grid_raw, opp + 1)
		slot = grid_slot_index(grid_raw, opp + 1)
	var reward_car := String(m.get("reward_car", ""))
	var advice := ""
	if reward_car != "" and not Missions.is_cleared(mission_index):
		advice = "First clear wins the %s." % CarCatalog.display_name(reward_car)
	return {
		"kind": "mission",
		"index": mission_index,
		"mkind": kind,
		"kicker": "%s MISSION · %s" % [String(Missions.KIND_NAMES.get(kind, "MISSION")), String(m.get("act_name", "")).to_upper()],
		"title": String(m.get("title", "")),
		"accent": Missions.COLOR,
		"track": tr_name,
		"track_key": tr_key,
		"length": Missions.length_text(mission_index),
		"weather": String(m.get("weather", "dry")).capitalize(),
		"time": hour_text(float(m.get("start_hour", 14.0))),
		"class_line": "Driven car: %s (%s)" % [CarCatalog.display_name(car_key), "solo run" if opp == 0 else "field matches your car"],
		"class_advice": advice,
		"forced_car": "",
		"travel_note": "",
		"grid": grid,
		"grid_slot": slot,
		"field_classes": PackedStringArray(),
		"opponents": opp,
		"rival_unit": "crews" if kind == "rally" else "rivals",
		"base_difficulty": String(m.get("difficulty", "medium")),
		"level_shift": 0.0,
		"base_label": String(m.get("difficulty", "medium")).capitalize(),
		"eased": int(m.get("eased", 0)),
		"fails": int(m.get("fails", 0)),
		"heat": 0.0,
		"target": Missions.target_text(mission_index),
		"car_key": car_key,
		"desc": String(m.get("desc", "")),
		"tip": String(m.get("tip", "")),
	}

## Describes a live event (from LiveEvents.board) for the menu.
static func describe_live(ev: Dictionary, live_events: LiveEvents = null, car_key := "stock", hour := 14.0, weather_word := "Dry") -> Dictionary:
	if live_events != null:
		live_events.ease_field(ev)
	var mkind := String(ev.get("mkind", "sprint"))
	var tag := LiveEvents.gate_tag(ev)
	var kicker := "LIVE %s%s" % [LiveEvents.kind_name(ev), (" · " + tag) if tag != "" else ""]
	var surf := live_events.surface_text(ev) if live_events != null else "Open world"
	var opp := int(ev.get("rivals", 0))
	var grid := "Solo"
	var slot := 1
	if mkind == "drag":
		grid = "Standing start (side by side)"
	elif mkind == "rally":
		grid = "Standing start (stage)"
	elif opp > 0:
		grid = "P%d of %d" % [opp + 1, opp + 1]
		slot = opp + 1
	var target := ""
	if live_events != null:
		target = live_events.target_text(ev, car_key)
	else:
		var t := int(ev.get("target", 3))
		target = "Win" if t == 1 else "Finish P%d or better" % t
	var accent: Color = ev.get("color", HudLayout.neon_primary()) as Color
	return {
		"kind": "live",
		"mkind": mkind,
		"live_ev": ev,
		"live_events": live_events,
		"kicker": kicker,
		"title": String(ev.get("title", "Live Event")),
		"accent": accent,
		"track": "Brzeszcze · %s" % surf,
		"track_key": "brzeszcze",
		"length": LiveEvents.length_text(ev),
		"weather": weather_word if weather_word != "" else "Dry",
		"time": hour_text(hour),
		"class_line": "Driven car: %s (%s)" % [CarCatalog.display_name(car_key), "solo run" if opp == 0 else "field matches your car"],
		"class_advice": LiveEvents.gate_line(ev),
		"forced_car": "",
		"travel_note": "",
		"grid": grid,
		"grid_slot": slot,
		"field_classes": PackedStringArray(),
		"opponents": opp,
		"rival_unit": "crews" if mkind == "rally" else "rivals",
		"base_difficulty": String(ev.get("difficulty", "medium")),
		"level_shift": 0.0,
		"base_label": String(ev.get("difficulty", "medium")).capitalize(),
		"eased": int(ev.get("eased", 0)),
		"fails": int(ev.get("fails", 0)),
		"heat": 0.0,
		"target": target,
		"car_key": car_key,
		"desc": "",
		"tip": "",
	}

## A grid slot formatted for display ("P5 of 6", "Pole").
static func grid_text(grid: String, n: int) -> String:
	if grid == "pole":
		return "Pole"
	if grid.begins_with("p") and grid.substr(1).is_valid_int():
		return "P%d of %d" % [clampi(grid.substr(1).to_int(), 1, n), n]
	return grid.capitalize()

## 1-based player grid slot from a stage's grid string.
static func grid_slot_index(grid: String, n: int) -> int:
	if grid == "pole":
		return 1
	if grid == "back":
		return maxi(1, n)
	if grid == "middle":
		return maxi(1, int(ceil(float(n) * 0.5)))
	if grid.begins_with("p") and grid.substr(1).is_valid_int():
		return clampi(grid.substr(1).to_int(), 1, maxi(1, n))
	return maxi(1, n)

## An hour of day formatted as "14:00 (Afternoon)".
static func hour_text(h: float) -> String:
	var wrapped := fposmod(h, 24.0)
	var hi := int(floor(wrapped)) % 24
	var mi := int(round((wrapped - floor(wrapped)) * 60.0))
	if mi >= 60:
		mi = 0
		hi = (hi + 1) % 24
	var period := "Night"
	if wrapped >= 5.0 and wrapped < 8.0:
		period = "Dawn"
	elif wrapped >= 8.0 and wrapped < 12.0:
		period = "Morning"
	elif wrapped >= 12.0 and wrapped < 17.0:
		period = "Afternoon"
	elif wrapped >= 17.0 and wrapped < 20.5:
		period = "Evening"
	return "%02d:%02d (%s)" % [hi, mi, period]

## A continuous rival level (LEVEL_MIN .. LEVEL_MAX) as a concise label ("Under Easy", "Easy+", "Medium", "Alien").
static func level_label(lv: float) -> String:
	if lv < -0.05:
		return "Under Easy"
	var clamped := clampf(lv, 0.0, float(DifficultyProfile.LEVELS.size() - 1))
	var lo := clampi(int(floor(clamped + 0.05)), 0, DifficultyProfile.LEVELS.size() - 1)
	var name := String(DifficultyProfile.LEVELS[lo]).capitalize()
	return (name + "+") if (clamped - float(lo)) >= 0.35 else name

static func _load_tex(path: String) -> Texture2D:
	if path != "" and ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null

static func _car_photo_tex(car_key: String, idx := 0) -> Texture2D:
	var shots: Array = OpenWorldCover.SHOTS.get(car_key, OpenWorldCover.SHOTS.stock)
	if shots.is_empty():
		shots = OpenWorldCover.SHOTS.stock
	var entry: Array = shots[posmod(idx, shots.size())]
	var tex := _load_tex(OpenWorldCover.DIR + String(entry[0]))
	if tex == null:
		tex = _load_tex(OpenWorldCover.DIR + String(OpenWorldCover.SHOTS.stock[0][0]))
	return tex

static func _track_photo_tex(track_key: String, car_key: String) -> Texture2D:
	if track_key != "":
		var hero := _load_tex(OpenWorldCover.DIR + "hero_" + track_key + ".jpg")
		if hero != null:
			return hero
	return _car_photo_tex(car_key, 1)

# ------------------------------------------------------------------ lifecycle & building

func _ready() -> void:
	name = "EventSetupPanel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = CmrStyle.build_theme()
	_last_pad = not Input.get_connected_joypads().is_empty()
	_build()
	_sync_from_profile()
	_show_page("hub", start_button)
	_layout()
	_layout.call_deferred()
	resized.connect(_layout)
	start_button.grab_focus()
	start_button.grab_focus.call_deferred()

## Refreshes event info (e.g. after returning from the Garage with a new car) without closing the menu.
func refresh_info(new_info: Dictionary) -> void:
	info = new_info.duplicate(true)
	_apply_event_art_and_titles()
	_sync_from_profile()
	_rebuild_grid_view()
	_layout()

func _accent() -> Color:
	var c: Variant = info.get("accent", HudLayout.neon_primary())
	return c as Color if c is Color else HudLayout.neon_primary()

func _start_noun() -> String:
	var kind := String(info.get("kind", "stage"))
	if kind == "mission":
		return "MISSION"
	if kind == "live":
		return "LIVE EVENT"
	if bool(info.get("sprint", false)):
		return "SPRINT EVENT"
	return "RACE EVENT"

func _build() -> void:
	var accent := _accent()

	# Light atmospheric scrim: keeps the parked car in Brzeszcze visible behind the tiles (FH3 style)
	backdrop = ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.03, 0.04, 0.07, 0.44)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	# Plain fixed-size Control root (never expands to wrapped children's min size on frame 0!)
	panel = Control.new()
	panel.name = "Panel"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	_build_hub_page(accent)
	_build_settings_page(accent)
	_build_grid_page(accent)
	_apply_event_art_and_titles()
	_rebuild_grid_view()

func _build_hub_page(accent: Color) -> void:
	hub_page = VBoxContainer.new()
	hub_page.name = "HubPage"
	hub_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hub_page.add_theme_constant_override("separation", 6)
	panel.add_child(hub_page)

	# --- FH3 top event title bar ---
	var header := PanelContainer.new()
	header.name = "HeaderBar"
	header.custom_minimum_size = Vector2(0, 56)
	header.add_theme_stylebox_override("panel", _bar_style(Color(0.08, 0.10, 0.14, 0.92), accent, 4))
	hub_page.add_child(header)

	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 12)
	header.add_child(hrow)

	var badge := Control.new()
	badge.name = "EventBadge"
	badge.custom_minimum_size = Vector2(36, 36)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.draw.connect(_draw_event_badge.bind(badge))
	hrow.add_child(badge)

	var title_col := VBoxContainer.new()
	title_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_col.add_theme_constant_override("separation", 0)
	hrow.add_child(title_col)

	kicker_label = _text(String(info.get("kicker", "EVENT")), 11, accent.lightened(0.18), 800, true)
	kicker_label.clip_text = true
	kicker_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_col.add_child(kicker_label)

	title_label = _text(String(info.get("title", "")), 24, Color.WHITE, 900, true)
	title_label.clip_text = true
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_col.add_child(title_label)

	var fans_box := VBoxContainer.new()
	fans_box.size_flags_horizontal = Control.SIZE_SHRINK_END
	fans_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fans_box.add_theme_constant_override("separation", -2)
	hrow.add_child(fans_box)
	var fans_cap := _text("FAN REWARD", 10, HudLayout.neon_primary(), 800, true)
	fans_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fans_box.add_child(fans_cap)
	fans_label = _text("", 18, CmrStyle.AMBER, 900, true)
	fans_label.name = "FansLabel"
	fans_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fans_box.add_child(fans_label)

	# --- compact event metadata strip ---
	var strip := PanelContainer.new()
	strip.name = "MetaStrip"
	strip.custom_minimum_size = Vector2(0, 28)
	strip.add_theme_stylebox_override("panel", _bar_style(Color(0.06, 0.08, 0.11, 0.84), Color(1, 1, 1, 0.08), 0))
	hub_page.add_child(strip)

	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 12)
	strip.add_child(srow)

	meta_label = _text("", 13, Color(0.90, 0.93, 0.98), 700)
	meta_label.name = "MetaLabel"
	meta_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta_label.clip_text = true
	meta_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	srow.add_child(meta_label)

	target_label = _text("", 13, HudLayout.neon_boost(), 800)
	target_label.name = "TargetLabel"
	target_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	srow.add_child(target_label)

	# --- 2-row FH3 tile grid (56/22/22 on row 1, mirrored 22/22/56 on row 2) ---
	var row1 := HBoxContainer.new()
	row1.name = "TileRow1"
	row1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row1.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row1.add_theme_constant_override("separation", 6)
	hub_page.add_child(row1)

	var start_parts := _make_hero_tile("StartButton", "START", _start_noun(), accent, true)
	start_button = start_parts.button as Button
	_start_photo = start_parts.photo as TextureRect
	_start_sub = start_parts.sub as Label
	start_button.size_flags_stretch_ratio = 56.0
	start_button.pressed.connect(confirm)
	row1.add_child(start_button)

	var opt_parts := _make_icon_tile("OptionsButton", "OPTIONS", "", "gear", accent)
	options_button = opt_parts.button as Button
	_options_sub = opt_parts.sub as Label
	options_button.size_flags_stretch_ratio = 22.0
	options_button.pressed.connect(func() -> void: open_settings("preset", options_button))
	row1.add_child(options_button)

	var quit_parts := _make_icon_tile("CancelButton", "QUIT", "EVENT", "quit", CmrStyle.RED)
	cancel_button = quit_parts.button as Button
	(quit_parts.sub as Label).text = "Return to free roam"
	cancel_button.size_flags_stretch_ratio = 22.0
	cancel_button.pressed.connect(cancel)
	row1.add_child(cancel_button)

	var row2 := HBoxContainer.new()
	row2.name = "TileRow2"
	row2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row2.add_theme_constant_override("separation", 6)
	hub_page.add_child(row2)

	var diff_parts := _make_icon_tile("DifficultyButton", "DIFFICULTY", "", "gamepad", accent)
	difficulty_button = diff_parts.button as Button
	_diff_sub = diff_parts.sub as Label
	difficulty_button.size_flags_stretch_ratio = 22.0
	difficulty_button.pressed.connect(func() -> void: open_settings("step", difficulty_button))
	row2.add_child(difficulty_button)

	var car_parts := _make_icon_tile("CarButton", "CAR", "", "sliders", accent)
	car_button = car_parts.button as Button
	_car_sub = car_parts.sub as Label
	car_button.size_flags_stretch_ratio = 22.0
	car_button.pressed.connect(_on_car_tile_pressed)
	row2.add_child(car_button)

	var opp := int(info.get("opponents", 0))
	var grid_parts := _make_hero_tile("GridButton", "STARTING" if opp > 0 else "EVENT", "GRID" if opp > 0 else "BRIEFING", accent, false)
	grid_button = grid_parts.button as Button
	_grid_photo = grid_parts.photo as TextureRect
	grid_button.size_flags_stretch_ratio = 56.0
	grid_button.pressed.connect(func() -> void: open_grid(grid_button))
	# Replace single sub label on STARTING GRID with rich multi-line info overlay (rivals, class, advice)
	(grid_parts.sub as Label).visible = false
	var info_overlay := grid_parts.bottom_box as VBoxContainer
	rivals_label = _text("", 14, HudLayout.neon_boost(), 800)
	rivals_label.name = "RivalsLabel"
	rivals_label.clip_text = true
	rivals_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info_overlay.add_child(rivals_label)

	class_label = _text("", 13, Color(0.92, 0.95, 1.0), 700)
	class_label.name = "ClassLabel"
	class_label.clip_text = true
	class_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info_overlay.add_child(class_label)

	class_note_label = _text("", 12, CmrStyle.AMBER, 700)
	class_note_label.name = "ClassNoteLabel"
	class_note_label.clip_text = true
	class_note_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info_overlay.add_child(class_note_label)
	row2.add_child(grid_button)

	# --- bottom key prompt bar ---
	keys_label = _text("", 13, Color(0.92, 0.96, 1.0, 0.92), 700, true)
	keys_label.name = "KeysLabel"
	keys_label.custom_minimum_size = Vector2(0, 22)
	keys_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hub_page.add_child(keys_label)

func _build_settings_page(accent: Color) -> void:
	settings_page = PanelContainer.new()
	settings_page.name = "SettingsPage"
	settings_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_page.add_theme_stylebox_override("panel", _panel_style(accent))
	settings_page.visible = false
	panel.add_child(settings_page)

	var col := VBoxContainer.new()
	col.name = "SettingsRoot"
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	settings_page.add_child(col)

	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 12)
	col.add_child(hrow)

	var tcol := VBoxContainer.new()
	tcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tcol.add_theme_constant_override("separation", 0)
	hrow.add_child(tcol)
	_settings_sub_title = _text(String(info.get("title", "")).to_upper(), 11, accent.lightened(0.18), 800, true)
	_settings_sub_title.clip_text = true
	_settings_sub_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tcol.add_child(_settings_sub_title)
	tcol.add_child(_text("DIFFICULTY & ASSISTS", 24, Color.WHITE, 900, true))

	var fcol := VBoxContainer.new()
	fcol.size_flags_horizontal = Control.SIZE_SHRINK_END
	fcol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fcol.add_theme_constant_override("separation", -2)
	hrow.add_child(fcol)
	var fcap := _text("FAN REWARD", 10, HudLayout.neon_primary(), 800, true)
	fcap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fcol.add_child(fcap)
	sub_fans_label = _text("", 18, CmrStyle.AMBER, 900, true)
	sub_fans_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fcol.add_child(sub_fans_label)

	col.add_child(_rule(accent))

	scroll = ScrollContainer.new()
	scroll.name = "SettingsScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.clip_contents = true
	col.add_child(scroll)

	var body := VBoxContainer.new()
	body.name = "SettingsColumn"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 5)
	scroll.add_child(body)

	controls["step"] = _selector_row(body, "RIVAL DIFFICULTY", DifficultyProfile.STEPS, "step")
	step_note_label = _text("", 12, CmrStyle.MUTED, 600)
	step_note_label.clip_text = true
	step_note_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	body.add_child(step_note_label)

	var preset_sel := _selector_row(body, "ASSIST PRESET", DifficultyProfile.PRESET_NAMES, "preset")
	preset_sel.set_item_disabled(DifficultyProfile.PRESET_KEYS.size(), true)
	controls["preset"] = preset_sel

	aids_toggle = Button.new()
	aids_toggle.name = "AidsToggle"
	aids_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	aids_toggle.focus_mode = Control.FOCUS_ALL
	aids_toggle.custom_minimum_size = Vector2(0, 30)
	aids_toggle.add_theme_font_override("font", CmrStyle.font(700))
	aids_toggle.add_theme_font_size_override("font_size", 13)
	aids_toggle.pressed.connect(toggle_aids)
	body.add_child(aids_toggle)

	aids_box = VBoxContainer.new()
	aids_box.name = "IndividualAids"
	aids_box.add_theme_constant_override("separation", 4)
	aids_box.visible = false
	body.add_child(aids_box)
	for k in DifficultyProfile.AID_KEYS:
		controls[k] = _selector_row(aids_box, "   " + String(DifficultyProfile.AID_NAMES[k]).to_upper(), OFF_ON_NAMES, k, true)

	controls["shifting"] = _selector_row(body, "SHIFTING", SHIFTING_NAMES, "shifting")
	controls["line"] = _selector_row(body, "RACING LINE", DifficultyProfile.LINE_NAMES, "line")
	controls["damage"] = _selector_row(body, "DAMAGE", DifficultyProfile.DAMAGE_NAMES, "damage")
	controls["recover"] = _selector_row(body, "AUTO-RECOVER", OFF_ON_NAMES, "recover")

	var fw_row := HBoxContainer.new()
	fw_row.name = "FuelWearRow"
	fw_row.add_theme_constant_override("separation", 14)
	body.add_child(fw_row)
	var fw_cap := _text("FUEL & TYRE WEAR", 13, CmrStyle.MUTED, 800)
	fw_cap.custom_minimum_size.x = 220.0
	fw_cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fw_row.add_child(fw_cap)
	fuel_wear_label = _text("Off in campaign", 14, CmrStyle.MUTED, 700)
	fuel_wear_label.name = "FuelWearLabel"
	fuel_wear_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fuel_wear_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fw_row.add_child(fuel_wear_label)

	col.add_child(_rule(accent))

	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", 12)
	col.add_child(frow)

	back_button = Button.new()
	back_button.name = "SettingsBackButton"
	back_button.text = "◂  BACK TO EVENT"
	back_button.focus_mode = Control.FOCUS_ALL
	back_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_button.custom_minimum_size = Vector2(0, 42)
	back_button.add_theme_font_override("font", HudLayout.italic_font(800, -0.10))
	back_button.add_theme_font_size_override("font_size", 16)
	_style_action_button(back_button, accent, false)
	back_button.pressed.connect(func() -> void: open_hub(_return_tile))
	frow.add_child(back_button)

	sub_start_button = Button.new()
	sub_start_button.name = "SettingsStartButton"
	sub_start_button.text = "START " + _start_noun()
	sub_start_button.focus_mode = Control.FOCUS_ALL
	sub_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub_start_button.custom_minimum_size = Vector2(0, 42)
	sub_start_button.add_theme_font_override("font", HudLayout.italic_font(900, -0.10))
	sub_start_button.add_theme_font_size_override("font_size", 17)
	_style_action_button(sub_start_button, accent, true)
	sub_start_button.pressed.connect(confirm)
	frow.add_child(sub_start_button)

	sub_keys_label = _text("", 12, HudLayout.neon_primary().lightened(0.28), 700, true)
	sub_keys_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(sub_keys_label)

func _build_grid_page(accent: Color) -> void:
	grid_page = PanelContainer.new()
	grid_page.name = "GridPage"
	grid_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grid_page.add_theme_stylebox_override("panel", _panel_style(accent))
	grid_page.visible = false
	panel.add_child(grid_page)

	var col := VBoxContainer.new()
	col.name = "GridRoot"
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	grid_page.add_child(col)

	_grid_sub_title = _text(String(info.get("title", "")).to_upper(), 11, accent.lightened(0.18), 800, true)
	_grid_sub_title.clip_text = true
	_grid_sub_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(_grid_sub_title)
	col.add_child(_text("STARTING GRID & EVENT BRIEFING", 24, Color.WHITE, 900, true))
	col.add_child(_rule(accent))

	var split := HBoxContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 16)
	col.add_child(split)

	var gscroll := ScrollContainer.new()
	gscroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gscroll.size_flags_stretch_ratio = 52.0
	gscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	gscroll.clip_contents = true
	split.add_child(gscroll)

	_grid_rows_box = VBoxContainer.new()
	_grid_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid_rows_box.add_theme_constant_override("separation", 4)
	gscroll.add_child(_grid_rows_box)

	var right_col := VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_col.size_flags_stretch_ratio = 48.0
	right_col.add_theme_constant_override("separation", 8)
	split.add_child(right_col)

	var pic_frame := Control.new()
	pic_frame.custom_minimum_size = Vector2(0, 140)
	pic_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pic_frame.clip_contents = true
	right_col.add_child(pic_frame)
	_grid_preview = TextureRect.new()
	_grid_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_grid_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_grid_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_grid_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic_frame.add_child(_grid_preview)

	var bscroll := ScrollContainer.new()
	bscroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bscroll.clip_contents = true
	right_col.add_child(bscroll)

	_grid_brief_box = VBoxContainer.new()
	_grid_brief_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid_brief_box.add_theme_constant_override("separation", 6)
	bscroll.add_child(_grid_brief_box)

	col.add_child(_rule(accent))

	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", 12)
	col.add_child(frow)

	grid_back_button = Button.new()
	grid_back_button.name = "GridBackButton"
	grid_back_button.text = "◂  BACK TO EVENT"
	grid_back_button.focus_mode = Control.FOCUS_ALL
	grid_back_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_back_button.custom_minimum_size = Vector2(0, 42)
	grid_back_button.add_theme_font_override("font", HudLayout.italic_font(800, -0.10))
	grid_back_button.add_theme_font_size_override("font_size", 16)
	_style_action_button(grid_back_button, accent, false)
	grid_back_button.pressed.connect(func() -> void: open_hub(grid_button))
	frow.add_child(grid_back_button)

	grid_start_button = Button.new()
	grid_start_button.name = "GridStartButton"
	grid_start_button.text = "START " + _start_noun()
	grid_start_button.focus_mode = Control.FOCUS_ALL
	grid_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_start_button.custom_minimum_size = Vector2(0, 42)
	grid_start_button.add_theme_font_override("font", HudLayout.italic_font(900, -0.10))
	grid_start_button.add_theme_font_size_override("font_size", 17)
	_style_action_button(grid_start_button, accent, true)
	grid_start_button.pressed.connect(confirm)
	frow.add_child(grid_start_button)

	grid_keys_label = _text("", 12, HudLayout.neon_primary().lightened(0.28), 700, true)
	grid_keys_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(grid_keys_label)

# ------------------------------------------------------------------ FH3 tile factories & custom vector icons

func _make_hero_tile(node_name: String, bold_word: String, light_word: String, accent: Color, left_stripe: bool) -> Dictionary:
	var btn := Button.new()
	btn.name = node_name
	btn.focus_mode = Control.FOCUS_ALL
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn.clip_contents = true
	btn.text = ""
	_clear_button_chrome(btn)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.10, 0.13, 0.19, 1.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(bg)

	var photo := TextureRect.new()
	photo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(photo)

	# Scrim + focus/hover border overlay drawn cleanly over the photo
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_hero_overlay.bind(overlay, btn, accent, left_stripe))
	btn.add_child(overlay)
	for sig in ["focus_entered", "focus_exited", "mouse_entered", "mouse_exited", "button_down", "button_up"]:
		btn.connect(sig, overlay.queue_redraw)

	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 18 if left_stripe else 14)
	pad.add_theme_constant_override("margin_right", 14)
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_theme_constant_override("margin_bottom", 10)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(pad)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)

	var w1 := _text(bold_word, 30, Color.WHITE, 900)
	w1.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	w1.add_theme_constant_override("shadow_offset_x", 1)
	w1.add_theme_constant_override("shadow_offset_y", 2)
	head.add_child(w1)

	if light_word != "":
		var w2 := _text(light_word, 30, Color(1.0, 1.0, 1.0, 0.88), 400)
		w2.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
		w2.add_theme_constant_override("shadow_offset_x", 1)
		w2.add_theme_constant_override("shadow_offset_y", 2)
		head.add_child(w2)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(spacer)

	var bottom_box := VBoxContainer.new()
	bottom_box.add_theme_constant_override("separation", 2)
	bottom_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(bottom_box)

	var sub := _text("", 14, Color(0.95, 0.97, 1.0), 700)
	sub.clip_text = true
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	bottom_box.add_child(sub)

	return {"button": btn, "photo": photo, "sub": sub, "bottom_box": bottom_box}

func _make_icon_tile(node_name: String, bold_word: String, light_word: String, icon_kind: String, accent: Color) -> Dictionary:
	var btn := Button.new()
	btn.name = node_name
	btn.focus_mode = Control.FOCUS_ALL
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn.clip_contents = true
	btn.text = ""
	_clear_button_chrome(btn)

	# Full tile canvas (crisp FH3 light card + vector icon + focus border)
	var canvas := Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.draw.connect(_draw_icon_tile.bind(canvas, btn, icon_kind, accent))
	btn.add_child(canvas)
	for sig in ["focus_entered", "focus_exited", "mouse_entered", "mouse_exited", "button_down", "button_up"]:
		btn.connect(sig, canvas.queue_redraw)

	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_theme_constant_override("margin_bottom", 8)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(pad)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 5)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)

	var ink := Color("#161922")
	var w1 := _text(bold_word, 18, ink, 900)
	head.add_child(w1)
	if light_word != "":
		var w2 := _text(light_word, 18, Color("#404859"), 400)
		head.add_child(w2)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(spacer)

	var sub := _text("", 12, Color("#2f3645"), 700)
	sub.clip_text = true
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(sub)

	return {"button": btn, "sub": sub}

func _clear_button_chrome(b: Button) -> void:
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, empty)

func _draw_hero_overlay(c: Control, btn: Button, accent: Color, left_stripe: bool) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	if r.size.x <= 1.0 or r.size.y <= 1.0:
		return
	var lit := btn.has_focus() or btn.is_hovered()
	# Top gradient for bold headline & bottom gradient for metadata readability
	c.draw_rect(Rect2(0, 0, r.size.x, r.size.y * 0.48), Color(0.03, 0.05, 0.09, 0.42 if lit else 0.56))
	c.draw_rect(Rect2(0, r.size.y * 0.52, r.size.x, r.size.y * 0.48), Color(0.03, 0.05, 0.09, 0.64 if lit else 0.74))
	if lit:
		c.draw_rect(r, Color(1.0, 1.0, 1.0, 0.07))
	if left_stripe:
		c.draw_rect(Rect2(0, 0, 7.0, r.size.y), accent)
	var border_col := Color.WHITE if btn.has_focus() else (accent if btn.is_hovered() else Color(1.0, 1.0, 1.0, 0.16))
	var bw := 3.5 if btn.has_focus() else (2.5 if btn.is_hovered() else 1.0)
	c.draw_rect(r.grow(-bw * 0.5), border_col, false, bw)
	if btn.has_focus():
		c.draw_rect(r.grow(-bw - 1.5), Color(accent, 0.85), false, 2.0)

func _draw_icon_tile(c: Control, btn: Button, kind: String, accent: Color) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	if r.size.x <= 1.0 or r.size.y <= 1.0:
		return
	var focused := btn.has_focus()
	var hovered := btn.is_hovered()
	var fill := Color(1.0, 1.0, 1.0, 0.99) if (focused or hovered) else Color(0.93, 0.95, 0.97, 0.94)
	c.draw_rect(r, fill)
	if focused or hovered:
		c.draw_rect(Rect2(0, 0, r.size.x, 5.0), accent)
	var icon_col := accent.darkened(0.22) if focused else Color("#20242e")
	var ctr := Vector2(r.size.x * 0.5, r.size.y * 0.54)
	var rad := minf(r.size.x, r.size.y) * 0.21
	match kind:
		"gear":
			_draw_gear(c, ctr, rad, icon_col, fill)
		"quit":
			var d := rad * 0.88
			var w := maxf(5.0, rad * 0.34)
			c.draw_line(ctr + Vector2(-d, -d), ctr + Vector2(d, d), icon_col, w, true)
			c.draw_line(ctr + Vector2(d, -d), ctr + Vector2(-d, d), icon_col, w, true)
		"gamepad":
			_draw_gamepad(c, ctr, rad, icon_col, fill)
		"sliders":
			_draw_sliders(c, ctr, rad, icon_col)
	var border_col := accent if (focused or hovered) else Color(0.1, 0.12, 0.18, 0.25)
	var bw := 3.5 if focused else (2.5 if hovered else 1.0)
	c.draw_rect(r.grow(-bw * 0.5), border_col, false, bw)

func _draw_gear(c: Control, ctr: Vector2, rad: float, col: Color, hole: Color) -> void:
	var teeth := 8
	var outer := rad * 1.15
	var inner := rad * 0.78
	for i in teeth:
		var a := float(i) * TAU / float(teeth)
		var da := 0.20
		var pts := PackedVector2Array([
			ctr + Vector2.from_angle(a - da) * (inner - 1.5),
			ctr + Vector2.from_angle(a - da * 0.65) * outer,
			ctr + Vector2.from_angle(a + da * 0.65) * outer,
			ctr + Vector2.from_angle(a + da) * (inner - 1.5),
		])
		c.draw_colored_polygon(pts, col)
	c.draw_circle(ctr, inner, col)
	c.draw_circle(ctr, rad * 0.42, hole)

func _draw_gamepad(c: Control, ctr: Vector2, rad: float, col: Color, hole: Color) -> void:
	var w := rad * 1.35
	var h := rad * 0.72
	# Main pad body + angled handles
	c.draw_rect(Rect2(ctr - Vector2(w * 0.65, h * 0.65), Vector2(w * 1.30, h * 1.15)), col)
	c.draw_circle(ctr + Vector2(-w * 0.58, -h * 0.08), h * 0.62, col)
	c.draw_circle(ctr + Vector2(w * 0.58, -h * 0.08), h * 0.62, col)
	c.draw_circle(ctr + Vector2(-w * 0.74, h * 0.48), h * 0.46, col)
	c.draw_circle(ctr + Vector2(w * 0.74, h * 0.48), h * 0.46, col)
	# D-pad cutout left
	var dp := ctr + Vector2(-w * 0.46, -h * 0.04)
	var ds := maxf(3.0, rad * 0.24)
	var dt := maxf(2.0, rad * 0.11)
	c.draw_line(dp - Vector2(ds, 0), dp + Vector2(ds, 0), hole, dt)
	c.draw_line(dp - Vector2(0, ds), dp + Vector2(0, ds), hole, dt)
	# 4 face button cutouts right
	var fb := ctr + Vector2(w * 0.48, -h * 0.05)
	var fr := maxf(1.8, rad * 0.095)
	var fd := maxf(3.2, rad * 0.20)
	for off: Vector2 in [Vector2(0, -fd), Vector2(0, fd), Vector2(-fd, 0), Vector2(fd, 0)]:
		c.draw_circle(fb + off, fr, hole)

func _draw_sliders(c: Control, ctr: Vector2, rad: float, col: Color) -> void:
	var xs := [-rad * 0.78, 0.0, rad * 0.78]
	var ys := [-rad * 0.30, rad * 0.34, -rad * 0.14]
	var bar_w := maxf(3.0, rad * 0.16)
	var knob_w := maxf(10.0, rad * 0.52)
	var knob_h := maxf(4.5, rad * 0.22)
	for i in 3:
		var x: float = ctr.x + xs[i]
		c.draw_line(Vector2(x, ctr.y - rad * 0.92), Vector2(x, ctr.y + rad * 0.92), col, bar_w)
		c.draw_rect(Rect2(x - knob_w * 0.5, ctr.y + ys[i] - knob_h * 0.5, knob_w, knob_h), col)

func _draw_event_badge(c: Control) -> void:
	var r := minf(c.size.x, c.size.y) * 0.5
	var ctr := c.size * 0.5
	c.draw_circle(ctr, r, Color.WHITE)
	var ink := Color("#161922")
	var kind := String(info.get("kind", "stage"))
	if bool(info.get("away", false)):
		c.draw_arc(ctr, r * 0.58, 0.0, TAU, 24, ink, 2.0, true)
		c.draw_line(ctr - Vector2(r * 0.58, 0), ctr + Vector2(r * 0.58, 0), ink, 1.8)
		c.draw_line(ctr - Vector2(0, r * 0.58), ctr + Vector2(0, r * 0.58), ink, 1.8)
	elif kind == "live":
		var pts := PackedVector2Array([
			ctr + Vector2(2, -r * 0.62), ctr + Vector2(-r * 0.42, 1),
			ctr + Vector2(0, 1), ctr + Vector2(-2, r * 0.62),
			ctr + Vector2(r * 0.42, -1), ctr + Vector2(0, -1),
		])
		c.draw_colored_polygon(pts, ink)
	elif bool(info.get("sprint", false)):
		c.draw_polyline(PackedVector2Array([ctr + Vector2(-r * 0.35, -r * 0.38), ctr + Vector2(r * 0.12, 0), ctr + Vector2(-r * 0.35, r * 0.38)]), ink, 3.0, true)
		c.draw_polyline(PackedVector2Array([ctr + Vector2(0, -r * 0.38), ctr + Vector2(r * 0.46, 0), ctr + Vector2(0, r * 0.38)]), ink, 3.0, true)
	else:
		# Checkered flag motif
		var s := r * 0.32
		for gx in 3:
			for gy in 2:
				if (gx + gy) % 2 == 0:
					c.draw_rect(Rect2(ctr.x - s * 1.5 + gx * s, ctr.y - s + gy * s, s, s), ink)

# ------------------------------------------------------------------ styles & helpers

func _bar_style(bg: Color, accent: Color, left_w: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = accent
	sb.border_width_left = left_w
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb

func _panel_style(accent: Color) -> StyleBoxFlat:
	var sb := HudLayout.neon_box(accent, 0.96, 4, 0.0, 12, 22.0, 16.0)
	sb.bg_color = Color(0.07, 0.09, 0.13, 0.96)
	return sb

func _selector_row(parent: Control, label_text: String, options: Array, key: String, sub := false) -> MenuSelector:
	var row := HBoxContainer.new()
	row.name = "Row_" + key
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)
	var lbl := _text(label_text, 12 if sub else 13, CmrStyle.MUTED if sub else CmrStyle.TEXT, 700 if sub else 800)
	lbl.custom_minimum_size.x = 220.0
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lbl)
	var sel := MenuSelector.new()
	sel.name = "Sel_" + key
	sel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sel.custom_minimum_size = Vector2(200.0, 30.0 if sub else 34.0)
	if sub:
		sel.add_theme_font_size_override("font_size", 14)
	for opt in options:
		sel.add_item(String(opt))
	sel.item_selected.connect(func(_idx: int) -> void: _on_setting_changed(key))
	row.add_child(sel)
	return sel

func _style_action_button(b: Button, accent: Color, primary: bool) -> void:
	var hot := HudLayout.neon_hot()
	var is_ps1 := CmrStyle.skin == "ps1"
	var glow := 0 if is_ps1 else 8
	if primary:
		var n := CmrStyle._neon_ctrl_box(accent.darkened(0.22), accent, 4, 2, glow)
		var h := CmrStyle._neon_ctrl_box(accent, accent.lightened(0.25), 4, 2, glow)
		var p := CmrStyle._neon_ctrl_box(accent.lightened(0.15), Color.WHITE, 4, 2, glow)
		b.add_theme_stylebox_override("normal", n)
		b.add_theme_stylebox_override("hover", h)
		b.add_theme_stylebox_override("pressed", p)
		b.add_theme_stylebox_override("focus", CmrStyle._focus_box())
		b.add_theme_color_override("font_color", Color.WHITE)
		b.add_theme_color_override("font_hover_color", CmrStyle.INK)
		b.add_theme_color_override("font_pressed_color", CmrStyle.INK)
		b.add_theme_color_override("font_focus_color", Color.WHITE)
	else:
		var n := CmrStyle._neon_ctrl_box(HudLayout.glass_plate(0.86), Color(CmrStyle.MUTED, 0.5), 4, 1, 0)
		var h := CmrStyle._neon_ctrl_box(HudLayout.glass_plate(0.94).lightened(0.08), hot, 4, 2, glow)
		b.add_theme_stylebox_override("normal", n)
		b.add_theme_stylebox_override("hover", h)
		b.add_theme_stylebox_override("pressed", h)
		b.add_theme_stylebox_override("focus", CmrStyle._focus_box())
		b.add_theme_color_override("font_color", CmrStyle.TEXT)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_color_override("font_focus_color", Color.WHITE)

func _rule(col: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(col, 0.45)
	r.custom_minimum_size.y = 2.0
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

static func _text(t: String, fsize: int, color: Color, weight := 700, italic := false) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", HudLayout.italic_font(weight) if italic else CmrStyle.font(weight))
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _layout() -> void:
	if panel == null:
		return
	var canvas := size if size.x > 1.0 and size.y > 1.0 else Vector2(1600.0, 900.0)
	var safe := HudLayout.safe_rect(canvas)
	var pw: float
	var ph: float
	if page == "hub":
		pw = minf(clampf(safe.size.x * 0.72, 740.0, 1080.0), safe.size.x - 32.0)
		ph = minf(clampf(safe.size.y * 0.58, 410.0, 510.0), safe.size.y - 32.0)
	else:
		pw = minf(clampf(safe.size.x * 0.66, 680.0, 960.0), safe.size.x - 32.0)
		ph = minf(clampf(safe.size.y * 0.76, 460.0, 620.0), safe.size.y - 32.0)
	panel.position = Vector2(roundf(safe.position.x + (safe.size.x - pw) * 0.5), roundf(safe.position.y + (safe.size.y - ph) * 0.5))
	panel.size = Vector2(roundf(pw), roundf(ph))

# ------------------------------------------------------------------ pages & content sync

func _show_page(next_page: String, focus_target: Control = null) -> void:
	page = next_page
	hub_page.visible = page == "hub"
	settings_page.visible = page == "settings"
	grid_page.visible = page == "grid"
	_layout()
	_refresh_keys_hint()
	if focus_target != null and is_instance_valid(focus_target) and focus_target.visible:
		focus_target.grab_focus()
		focus_target.grab_focus.call_deferred()

func open_hub(focus_tile: Button = null) -> void:
	var target: Control = focus_tile if (focus_tile != null and is_instance_valid(focus_tile)) else start_button
	_show_page("hub", target)

func open_settings(focus_key := "step", from_tile: Button = null) -> void:
	_return_tile = from_tile if from_tile != null else difficulty_button
	var target: Control = controls.get(focus_key, controls.step) as Control
	_show_page("settings", target)

func open_grid(from_tile: Button = null) -> void:
	_return_tile = from_tile if from_tile != null else grid_button
	_rebuild_grid_view()
	_show_page("grid", grid_back_button)

func _on_car_tile_pressed() -> void:
	if String(info.get("forced_car", "")) != "":
		open_grid(car_button)
		return
	garage_requested.emit()

func _apply_event_art_and_titles() -> void:
	var car_key := String(info.get("car_key", "stock"))
	var track_key := String(info.get("track_key", ""))
	kicker_label.text = String(info.get("kicker", "EVENT"))
	title_label.text = String(info.get("title", ""))
	if _settings_sub_title != null:
		_settings_sub_title.text = String(info.get("title", "")).to_upper()
	if _grid_sub_title != null:
		_grid_sub_title.text = String(info.get("title", "")).to_upper()
	if _start_photo != null:
		_start_photo.texture = _car_photo_tex(car_key, 0)
	var track_tex := _track_photo_tex(track_key, car_key)
	if _grid_photo != null:
		_grid_photo.texture = track_tex
	if _grid_preview != null:
		_grid_preview.texture = track_tex
	var car_name := CarCatalog.display_name(car_key)
	var forced := String(info.get("forced_car", ""))
	if _car_sub != null:
		_car_sub.text = "%s · Fixed" % car_name if forced != "" else car_name
	if _start_sub != null:
		var adv := String(info.get("class_advice", ""))
		_start_sub.text = "%s  ·  %s" % [car_name, adv] if adv != "" else car_name

func _rebuild_grid_view() -> void:
	if _grid_rows_box == null or _grid_brief_box == null:
		return
	for ch in _grid_rows_box.get_children():
		ch.queue_free()
	for ch in _grid_brief_box.get_children():
		ch.queue_free()

	var opp := int(info.get("opponents", 0))
	var car_key := String(info.get("car_key", "stock"))
	var player_car := CarCatalog.display_name(car_key)
	var accent := _accent()

	if opp <= 0:
		_grid_rows_box.add_child(_text("SOLO EVENT", 15, accent.lightened(0.2), 800, true))
		_grid_rows_box.add_child(_text("Start: %s" % String(info.get("grid", "Solo")), 14, Color.WHITE, 700))
		_grid_rows_box.add_child(_text("Your car: %s" % player_car, 14, CmrStyle.TEXT, 700))
	else:
		var total := opp + 1
		var p_slot := clampi(int(info.get("grid_slot", total)), 1, total)
		var fclasses: PackedStringArray = info.get("field_classes", PackedStringArray()) as PackedStringArray
		var rival_idx := 0
		for slot in range(1, total + 1):
			var is_player := slot == p_slot
			var row_panel := PanelContainer.new()
			var bg := Color(accent, 0.24) if is_player else Color(1.0, 1.0, 1.0, 0.04 if slot % 2 == 0 else 0.08)
			row_panel.add_theme_stylebox_override("panel", _bar_style(bg, accent if is_player else Color.TRANSPARENT, 4 if is_player else 0))
			_grid_rows_box.add_child(row_panel)
			var rrow := HBoxContainer.new()
			rrow.add_theme_constant_override("separation", 10)
			row_panel.add_child(rrow)
			var pos_l := _text("P%d" % slot, 13, accent.lightened(0.25) if is_player else CmrStyle.MUTED, 900)
			pos_l.custom_minimum_size.x = 34.0
			rrow.add_child(pos_l)
			var driver_name := "YOU" if is_player else String(Drivers.ROSTER[rival_idx % Drivers.ROSTER.size()].name)
			var ckey := car_key if is_player else (String(fclasses[rival_idx]) if rival_idx < fclasses.size() and String(fclasses[rival_idx]) != "" else car_key)
			if not is_player:
				rival_idx += 1
			var drv_l := _text(driver_name, 13, Color.WHITE if is_player else CmrStyle.TEXT, 800 if is_player else 600)
			drv_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			drv_l.clip_text = true
			drv_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			rrow.add_child(drv_l)
			var car_l := _text(CarCatalog.display_name(ckey), 12, HudLayout.neon_boost() if is_player else CmrStyle.MUTED, 700)
			car_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			rrow.add_child(car_l)

	# Briefing details column
	var add_line := func(txt: String, col: Color, fsize := 13, bold := false) -> void:
		if txt == "":
			return
		var l := _text(txt, fsize, col, 800 if bold else 600)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_grid_brief_box.add_child(l)
	add_line.call(meta_label.text if meta_label else "", Color.WHITE, 13, true)
	add_line.call("Target: %s" % String(info.get("target", "")), HudLayout.neon_boost(), 13, true)
	add_line.call(String(info.get("class_line", "")), CmrStyle.TEXT, 13, false)
	add_line.call(String(info.get("travel_note", "")), CmrStyle.AMBER, 13, true)
	add_line.call(String(info.get("class_advice", "")), CmrStyle.AMBER, 13, false)
	add_line.call(String(info.get("desc", "")), CmrStyle.MUTED, 12, false)
	var tip := String(info.get("tip", ""))
	if tip != "":
		add_line.call("Tip: %s" % tip, Color(0.84, 0.90, 0.98), 12, false)

# ------------------------------------------------------------------ profile sync & header refresh

func _on_setting_changed(key: String) -> void:
	if _syncing:
		return
	var p := DifficultyProfile.clean(DifficultyProfile.current)
	var sel := controls[key] as MenuSelector
	match key:
		"step":
			p.step = clampi(sel.selected, 0, DifficultyProfile.STEPS.size() - 1)
		"preset":
			var idx := sel.selected
			if idx < 0 or idx >= DifficultyProfile.PRESET_KEYS.size():
				_sync_from_profile()
				return
			p = DifficultyProfile.with_preset(p, DifficultyProfile.PRESET_KEYS[idx])
		"shifting":
			p.shifting = "manual" if sel.selected == 1 else "auto"
		"line":
			p.line = DifficultyProfile.LINE_MODES[clampi(sel.selected, 0, DifficultyProfile.LINE_MODES.size() - 1)]
		"damage":
			p.damage = DifficultyProfile.DAMAGE_MODES[clampi(sel.selected, 0, DifficultyProfile.DAMAGE_MODES.size() - 1)]
		"recover":
			p.recover = sel.selected == 1
		_:
			p[key] = sel.selected == 1
	DifficultyProfile.current = DifficultyProfile.clean(p)
	DifficultyProfile.save_profile(save_file)
	_sync_from_profile()
	profile_changed.emit()

func _sync_from_profile() -> void:
	var p := DifficultyProfile.clean(DifficultyProfile.current)
	_syncing = true
	(controls.step as MenuSelector).select(int(p.step))
	(controls.preset as MenuSelector).select(DifficultyProfile.preset_index(p))
	(controls.shifting as MenuSelector).select(1 if String(p.shifting) == "manual" else 0)
	(controls.line as MenuSelector).select(maxi(DifficultyProfile.LINE_MODES.find(String(p.line)), 0))
	(controls.damage as MenuSelector).select(maxi(DifficultyProfile.DAMAGE_MODES.find(String(p.damage)), 0))
	(controls.recover as MenuSelector).select(1 if bool(p.recover) else 0)
	for k in DifficultyProfile.AID_KEYS:
		(controls[k] as MenuSelector).select(1 if bool(p[k]) else 0)
	_syncing = false

	var mult := DifficultyProfile.fan_multiplier(p)
	var fan_str := "×%.2f  %s" % [mult, DifficultyProfile.fan_text(p).to_upper()]
	fans_label.text = fan_str
	if sub_fans_label != null:
		sub_fans_label.text = fan_str
	step_note_label.text = String(DifficultyProfile.STEP_NOTES[int(p.step)])
	_refresh_aids_toggle(p)
	_refresh_tile_summaries(p)
	_refresh_header(p)

func _refresh_tile_summaries(p: Dictionary) -> void:
	if _diff_sub != null:
		_diff_sub.text = "%s · %s" % [DifficultyProfile.STEPS[int(p.step)], DifficultyProfile.fan_text(p)]
	if _options_sub != null:
		var preset_i := DifficultyProfile.preset_index(p)
		var preset_name := String(DifficultyProfile.PRESET_NAMES[preset_i])
		var shift_s := "Manual" if String(p.shifting) == "manual" else "Auto"
		var line_i := maxi(DifficultyProfile.LINE_MODES.find(String(p.line)), 0)
		_options_sub.text = "%s · %s · %s" % [preset_name, shift_s, String(DifficultyProfile.LINE_NAMES[line_i])]

func _refresh_aids_toggle(p: Dictionary) -> void:
	var on_list := PackedStringArray()
	var short := {"abs": "ABS", "tc": "TC", "esc": "ESC", "steer": "Steer", "brake": "Brake"}
	for k in DifficultyProfile.AID_KEYS:
		if bool(p[k]):
			on_list.append(String(short[k]))
	var summary := " · ".join(on_list) if not on_list.is_empty() else "All off"
	var glyph := "▾" if aids_expanded else "▸"
	aids_toggle.text = "%s  INDIVIDUAL AIDS   ·   %s" % [glyph, summary]

func _refresh_header(p: Dictionary) -> void:
	var parts := PackedStringArray()
	for k in ["track", "length", "weather", "time"]:
		var v := String(info.get(k, ""))
		if v != "":
			parts.append(v)
	meta_label.text = "  ·  ".join(parts)

	var step := int(p.step)
	var opp := int(info.get("opponents", 0))
	var kind := String(info.get("kind", "stage"))
	var mkind := String(info.get("mkind", ""))
	var target := String(info.get("target", ""))
	if kind == "mission" and mkind == "drift" and info.has("index"):
		target = Missions.target_text(int(info.index))
	elif kind == "live" and mkind == "drift":
		var le: Variant = info.get("live_events", null)
		var lev: Variant = info.get("live_ev", {})
		if le is LiveEvents and lev is Dictionary:
			target = (le as LiveEvents).target_text(lev as Dictionary, String(info.get("car_key", "stock")))
	if target_label != null:
		target_label.text = ("TARGET: " + target) if target != "" else ""

	var r_parts := PackedStringArray()
	var grid := String(info.get("grid", ""))
	if grid != "":
		r_parts.append("Grid: %s" % grid)
	if opp > 0:
		var base_diff := String(info.get("base_difficulty", "medium"))
		var extra := float(info.get("level_shift", 0.0))
		var base_lbl := String(info.get("base_label", base_diff.capitalize()))
		var resolved := Campaign.resolve_level(base_diff, extra, step)
		var eff_lbl := level_label(float(resolved.level))
		var rival_str := "%d %s · %s" % [opp, String(info.get("rival_unit", "rivals")), eff_lbl]
		if step != DifficultyProfile.AVERAGE and eff_lbl != base_lbl:
			rival_str += " (base %s)" % base_lbl
		if int(info.get("eased", 0)) > 0:
			rival_str += " · eased after %d tries" % int(info.get("fails", 0))
		elif float(info.get("heat", 0.0)) > 0.0:
			rival_str += " · field tightened"
		r_parts.append(rival_str)
	else:
		r_parts.append("Solo · %s targets" % DifficultyProfile.STEPS[step])
	if target != "":
		r_parts.append("Target: %s" % target)
	rivals_label.text = "  ·  ".join(r_parts)

	class_label.text = String(info.get("class_line", ""))
	class_label.visible = class_label.text != ""

	var notes := PackedStringArray()
	var trv := String(info.get("travel_note", ""))
	if trv != "":
		notes.append(trv)
	var adv := String(info.get("class_advice", ""))
	if adv != "":
		notes.append(adv)
	class_note_label.text = "  ·  ".join(notes)
	class_note_label.visible = not notes.is_empty()

# ------------------------------------------------------------------ public actions & focus

## All visible, enabled focusable controls on the active page in navigation order.
func focus_items() -> Array[Control]:
	var order: Array[Control] = []
	match page:
		"hub":
			order = [start_button, options_button, cancel_button, difficulty_button, car_button, grid_button]
		"settings":
			order = [controls.step as Control, controls.preset as Control, aids_toggle]
			if aids_expanded:
				for k in DifficultyProfile.AID_KEYS:
					order.append(controls[k] as Control)
			order.append(controls.shifting as Control)
			order.append(controls.line as Control)
			order.append(controls.damage as Control)
			order.append(controls.recover as Control)
			order.append(back_button)
			order.append(sub_start_button)
		"grid":
			order = [grid_back_button, grid_start_button]
	var out: Array[Control] = []
	for c in order:
		if is_instance_valid(c) and c.visible and c.focus_mode != Control.FOCUS_NONE:
			if c is BaseButton and (c as BaseButton).disabled:
				continue
			out.append(c)
	return out

func toggle_aids() -> void:
	set_aids_expanded(not aids_expanded)

func set_aids_expanded(on: bool) -> void:
	aids_expanded = on
	aids_box.visible = on
	_refresh_aids_toggle(DifficultyProfile.clean(DifficultyProfile.current))
	var vp := get_viewport()
	if vp != null and page == "settings":
		var owner := vp.gui_get_focus_owner()
		if owner == null or not focus_items().has(owner):
			aids_toggle.grab_focus()

func confirm() -> void:
	if _closed:
		return
	_closed = true
	set_process_input(false)
	started.emit()
	queue_free()

func cancel() -> void:
	if _closed:
		return
	_closed = true
	set_process_input(false)
	cancelled.emit()
	queue_free()

func _back_action() -> void:
	if page != "hub":
		open_hub(_return_tile)
	else:
		cancel()

func _ensure_focus() -> Control:
	var items := focus_items()
	if items.is_empty():
		return null
	var vp := get_viewport()
	var owner: Control = vp.gui_get_focus_owner() if vp != null else null
	if owner == null or not items.has(owner):
		items[0].grab_focus()
		return items[0]
	return owner

func _move_vertical(dir: int) -> void:
	var owner := _ensure_focus()
	if owner == null:
		return
	if page == "hub":
		# Spatial 2-row FH3 grid: row 1 [start(56%), options(22%), cancel(22%)] <-> row 2 [difficulty(22%), car(22%), grid(56%)]
		match owner:
			start_button: difficulty_button.grab_focus()
			options_button, cancel_button: grid_button.grab_focus()
			difficulty_button, car_button: start_button.grab_focus()
			grid_button: options_button.grab_focus()
		return
	if page == "grid":
		if owner == grid_back_button:
			grid_start_button.grab_focus()
		else:
			grid_back_button.grab_focus()
		return
	var items := focus_items()
	var footer_start := items.find(back_button)
	if owner == back_button or owner == sub_start_button:
		if dir < 0:
			items[maxi(footer_start - 1, 0)].grab_focus()
		else:
			items[0].grab_focus()
		return
	var idx := items.find(owner)
	if dir > 0 and idx == footer_start - 1:
		back_button.grab_focus()
		return
	if dir < 0 and idx == 0:
		back_button.grab_focus()
		return
	items[clampi(idx + dir, 0, footer_start - 1)].grab_focus()

func _move_horizontal(dir: int) -> void:
	var owner := _ensure_focus()
	if owner == null:
		return
	if page == "hub":
		var row1: Array[Button] = [start_button, options_button, cancel_button]
		var row2: Array[Button] = [difficulty_button, car_button, grid_button]
		var i1 := row1.find(owner)
		if i1 >= 0:
			row1[posmod(i1 + dir, row1.size())].grab_focus()
			return
		var i2 := row2.find(owner)
		if i2 >= 0:
			row2[posmod(i2 + dir, row2.size())].grab_focus()
			return
		start_button.grab_focus()
		return
	if page == "grid":
		if owner == grid_back_button:
			grid_start_button.grab_focus()
		else:
			grid_back_button.grab_focus()
		return
	if owner == back_button:
		sub_start_button.grab_focus()
		return
	if owner == sub_start_button:
		back_button.grab_focus()
		return
	if owner == aids_toggle:
		set_aids_expanded(dir > 0)
		return
	if owner is MenuSelector:
		_step_selector(owner as MenuSelector, dir)

func _step_selector(sel: MenuSelector, dir: int) -> void:
	if sel == controls.preset and sel.selected == DifficultyProfile.PRESET_KEYS.size() and dir > 0:
		sel.select(0)
		sel.item_selected.emit(0)
		return
	sel.step(dir, false)

func _activate_focused() -> void:
	var owner := _ensure_focus()
	if owner == null:
		return
	if owner == start_button or owner == sub_start_button or owner == grid_start_button:
		confirm()
	elif owner == cancel_button:
		cancel()
	elif owner == back_button or owner == grid_back_button:
		open_hub(_return_tile)
	elif owner == options_button:
		open_settings("preset", options_button)
	elif owner == difficulty_button:
		open_settings("step", difficulty_button)
	elif owner == car_button:
		_on_car_tile_pressed()
	elif owner == grid_button:
		open_grid(grid_button)
	elif owner == aids_toggle:
		toggle_aids()
	elif owner is MenuSelector:
		(owner as MenuSelector).activate(1)

func _refresh_keys_hint() -> void:
	if keys_label != null:
		keys_label.text = "Ⓐ Select   START Launch   Ⓑ Back to free roam" if _last_pad \
			else "← ↑ ↓ → Move   Enter Select   Esc Back to free roam"
	if sub_keys_label != null:
		sub_keys_label.text = "↕ Move   ◂ ▸ / LB RB Change   Ⓐ Select   START Launch   Ⓑ Back" if _last_pad \
			else "↑ ↓ Move   ← → / Q E Change   Enter Select   Esc Back"
	if grid_keys_label != null:
		grid_keys_label.text = "◂ ▸ Choose   Ⓐ Select   START Launch   Ⓑ Back" if _last_pad \
			else "← → Choose   Enter Select   Esc Back"

# ------------------------------------------------------------------ modal input

func _input(event: InputEvent) -> void:
	if _closed or not is_visible_in_tree():
		return
	if event is InputEventJoypadMotion:
		_last_pad = true
		_refresh_keys_hint()
		_stick_motion(event as InputEventJoypadMotion)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadButton:
		_last_pad = true
		_refresh_keys_hint()
		get_viewport().set_input_as_handled()
		if not event.pressed:
			return
		match (event as InputEventJoypadButton).button_index:
			JOY_BUTTON_DPAD_UP: _move_vertical(-1)
			JOY_BUTTON_DPAD_DOWN: _move_vertical(1)
			JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_LEFT_SHOULDER: _move_horizontal(-1)
			JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_RIGHT_SHOULDER: _move_horizontal(1)
			JOY_BUTTON_A: _activate_focused()
			JOY_BUTTON_START: confirm()
			JOY_BUTTON_B: _back_action()
		return
	if event is InputEventKey:
		var kev := event as InputEventKey
		if kev.ctrl_pressed or kev.meta_pressed or kev.alt_pressed:
			return
		_last_pad = false
		_refresh_keys_hint()
		get_viewport().set_input_as_handled()
		if not kev.pressed:
			return
		var key := kev.physical_keycode if kev.physical_keycode != KEY_NONE else kev.keycode
		var echo := kev.echo
		match key:
			KEY_UP, KEY_W: _move_vertical(-1)
			KEY_DOWN, KEY_S: _move_vertical(1)
			KEY_LEFT, KEY_A, KEY_Q, KEY_PAGEUP: _move_horizontal(-1)
			KEY_RIGHT, KEY_D, KEY_E, KEY_PAGEDOWN: _move_horizontal(1)
			KEY_TAB:
				if page == "hub":
					var items := focus_items()
					var owner := _ensure_focus()
					var i := items.find(owner)
					items[posmod(i + (-1 if kev.shift_pressed else 1), items.size())].grab_focus()
				else:
					_move_vertical(-1 if kev.shift_pressed else 1)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				if not echo:
					_activate_focused()
			KEY_ESCAPE, KEY_BACKSPACE:
				if not echo:
					_back_action()

func _stick_motion(ev: InputEventJoypadMotion) -> void:
	if ev.axis != JOY_AXIS_LEFT_X and ev.axis != JOY_AXIS_LEFT_Y:
		return
	var idx := 0 if ev.axis == JOY_AXIS_LEFT_X else 1
	if absf(ev.axis_value) < 0.35:
		_stick[idx] = 0
		return
	if absf(ev.axis_value) < 0.6 or _stick[idx] != 0:
		return
	var dir := 1 if ev.axis_value > 0.0 else -1
	_stick[idx] = dir
	if idx == 0:
		_move_horizontal(dir)
	else:
		_move_vertical(dir)
