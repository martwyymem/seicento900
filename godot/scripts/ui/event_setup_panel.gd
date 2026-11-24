## Pre-start event settings pop-up for the open world (campaign stages, A->B sprint stages, Away Races gate,
## campaign missions, and live events): shows the event's header (title, track, distance/laps, weather, time of day,
## expected car class, grid slot, and rival level) and lets the player tune DifficultyProfile.current right before
## launch (rival difficulty, assist preset + expandable individual aids, shifting, racing line, damage, auto-recover;
## fuel and tyre wear shown as "Off in campaign"), saving immediately like Options -> Difficulty & Assists.
## Controller-first per Design Rule #6: opens focused on START, D-pad/stick moves between rows, ◂ ▸ or LB/RB step
## selector values, A / Enter activates, START confirms, B / Esc cancels back to free roam, focus never escapes.
class_name EventSetupPanel
extends Control

signal started
signal cancelled
signal profile_changed

const SHIFTING_NAMES := ["Automatic", "Manual (E/Q)"]
const OFF_ON_NAMES := ["Off", "On"]

var info: Dictionary = {}
var save_file := "" ## "" saves to SaveData.path(DifficultyProfile.FILE); tests may override

var backdrop: ColorRect
var panel: PanelContainer
var scroll: ScrollContainer
var kicker_label: Label
var title_label: Label
var fans_label: Label
var meta_label: Label
var rivals_label: Label
var class_label: Label
var class_note_label: Label
var step_note_label: Label
var fuel_wear_label: Label
var keys_label: Label

var controls: Dictionary = {} ## "step", "preset", "abs", "tc", "esc", "steer", "brake", "shifting", "line", "damage", "recover"
var aids_toggle: Button
var aids_box: VBoxContainer
var aids_expanded := false
var start_button: Button
var cancel_button: Button

var _syncing := false
var _closed := false
var _stick := [0, 0]
var _last_pad := false

## Opens the pop-up over `parent` for the described event `event_info` (from describe_stage / describe_mission /
## describe_live). The panel frees itself after emitting `started` or `cancelled`.
static func open_in(parent: Node, event_info: Dictionary, profile_save_file := "") -> EventSetupPanel:
	var p := EventSetupPanel.new()
	p.info = event_info.duplicate(true)
	p.save_file = profile_save_file
	parent.add_child(p)
	return p

# ------------------------------------------------------------------ event descriptors

## Describes a campaign stage (lap race, A->B sprint, or Away Races stage) for the panel's header.
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
	var advice := Campaign.class_advice(car_key, st) if forced == "" else "Everyone drives the %s." % CarCatalog.display_name(forced)
	var travel_note := ""
	if away:
		var trv := CampaignObjective.travel(stage_index)
		if not trv.is_empty():
			travel_note = CampaignObjective.upper_first(String(trv.get("line", "")))
	return {
		"kind": "stage",
		"index": stage_index,
		"away": away,
		"sprint": Campaign.is_sprint(st),
		"kicker": kicker,
		"title": String(st.get("title", "")),
		"accent": OpenWorldHud.GOLD if done else OpenWorldHud.ORANGE,
		"track": tr_name,
		"length": Campaign.length_label(st),
		"weather": String(st.get("weather", "dry")).capitalize(),
		"time": hour_text(float(st.get("start_hour", st.get("time_of_day", 14.0)))),
		"class_line": Campaign.class_line(st),
		"class_advice": advice,
		"travel_note": travel_note,
		"grid": grid_text(String(st.get("grid", "middle")), opp + 1),
		"opponents": opp,
		"rival_unit": "rivals",
		"base_difficulty": String(st.get("difficulty", "medium")),
		"level_shift": float(st.get("level_shift", 0.0)),
		"base_label": Campaign.level_name(st),
		"eased": int(st.get("eased", 0)),
		"fails": int(st.get("fails", 0)),
		"heat": float(st.get("heat", 0.0)),
		"target": target,
		"car_key": car_key,
	}

## Describes a campaign map mission (Missions.BASE + k) for the panel's header.
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
	var grid := "Solo"
	if kind == "rally":
		grid = "Standing start (stages)"
	elif opp > 0:
		grid = grid_text(String(m.get("grid", "pole")), opp + 1)
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
		"length": Missions.length_text(mission_index),
		"weather": String(m.get("weather", "dry")).capitalize(),
		"time": hour_text(float(m.get("start_hour", 14.0))),
		"class_line": "Driven car: %s (%s)" % [CarCatalog.display_name(car_key), "solo run" if opp == 0 else "field matches your car"],
		"class_advice": advice,
		"travel_note": "",
		"grid": grid,
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
	}

## Describes a live event (from LiveEvents.board) for the panel's header.
static func describe_live(ev: Dictionary, live_events: LiveEvents = null, car_key := "stock", hour := 14.0, weather_word := "Dry") -> Dictionary:
	if live_events != null:
		live_events.ease_field(ev)
	var mkind := String(ev.get("mkind", "sprint"))
	var tag := LiveEvents.gate_tag(ev)
	var kicker := "LIVE %s%s" % [LiveEvents.kind_name(ev), (" · " + tag) if tag != "" else ""]
	var surf := live_events.surface_text(ev) if live_events != null else "Open world"
	var opp := int(ev.get("rivals", 0))
	var grid := "Solo"
	if mkind == "drag":
		grid = "Standing start (side by side)"
	elif mkind == "rally":
		grid = "Standing start (stage)"
	elif opp > 0:
		grid = "P%d of %d" % [opp + 1, opp + 1]
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
		"length": LiveEvents.length_text(ev),
		"weather": weather_word if weather_word != "" else "Dry",
		"time": hour_text(hour),
		"class_line": "Driven car: %s (%s)" % [CarCatalog.display_name(car_key), "solo run" if opp == 0 else "field matches your car"],
		"class_advice": LiveEvents.gate_line(ev),
		"travel_note": "",
		"grid": grid,
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
	}

## A grid slot formatted for display ("P5 of 6", "Pole").
static func grid_text(grid: String, n: int) -> String:
	if grid == "pole":
		return "Pole"
	if grid.begins_with("p") and grid.substr(1).is_valid_int():
		return "P%d of %d" % [clampi(grid.substr(1).to_int(), 1, n), n]
	return grid.capitalize()

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
	_layout()
	resized.connect(_layout)
	start_button.grab_focus()
	start_button.grab_focus.call_deferred()

func _accent() -> Color:
	var c: Variant = info.get("accent", HudLayout.neon_primary())
	return c as Color if c is Color else HudLayout.neon_primary()

func _build() -> void:
	var accent := _accent()
	backdrop = ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(CmrStyle.TINT_OPTIONS, 0.72)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	panel = PanelContainer.new()
	panel.name = "Panel"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _panel_style(accent))
	add_child(panel)

	var root_col := VBoxContainer.new()
	root_col.name = "RootColumn"
	root_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_col.add_theme_constant_override("separation", 10)
	panel.add_child(root_col)

	# --- header ---
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 16)
	root_col.add_child(head_row)

	var title_col := VBoxContainer.new()
	title_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_col.add_theme_constant_override("separation", 2)
	head_row.add_child(title_col)

	kicker_label = _text(String(info.get("kicker", "EVENT")), 13, accent, 900, true)
	kicker_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_col.add_child(kicker_label)

	title_label = _text(String(info.get("title", "")), 28, Color.WHITE, 900, true)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_col.add_child(title_label)

	var fans_col := VBoxContainer.new()
	fans_col.size_flags_horizontal = Control.SIZE_SHRINK_END
	fans_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fans_col.add_theme_constant_override("separation", 0)
	head_row.add_child(fans_col)
	var fans_cap := _text("FAN REWARD", 11, HudLayout.neon_primary(), 800, true)
	fans_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fans_col.add_child(fans_cap)
	fans_label = _text("", 20, CmrStyle.AMBER, 900, true)
	fans_label.name = "FansLabel"
	fans_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fans_col.add_child(fans_label)

	meta_label = _text("", 15, CmrStyle.TEXT, 700)
	meta_label.name = "MetaLabel"
	meta_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_col.add_child(meta_label)

	rivals_label = _text("", 15, HudLayout.neon_boost(), 800)
	rivals_label.name = "RivalsLabel"
	rivals_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_col.add_child(rivals_label)

	class_label = _text("", 14, CmrStyle.MUTED, 700)
	class_label.name = "ClassLabel"
	class_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_col.add_child(class_label)

	class_note_label = _text("", 13, CmrStyle.AMBER, 700)
	class_note_label.name = "ClassNoteLabel"
	class_note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_col.add_child(class_note_label)

	root_col.add_child(_rule(accent))

	# --- scrollable settings body ---
	scroll = ScrollContainer.new()
	scroll.name = "SettingsScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	root_col.add_child(scroll)

	var body := VBoxContainer.new()
	body.name = "SettingsColumn"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	scroll.add_child(body)

	controls["step"] = _selector_row(body, "RIVAL DIFFICULTY", DifficultyProfile.STEPS, "step")
	step_note_label = _text("", 13, CmrStyle.MUTED, 600)
	step_note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(step_note_label)

	var preset_sel := _selector_row(body, "ASSIST PRESET", DifficultyProfile.PRESET_NAMES, "preset")
	preset_sel.set_item_disabled(DifficultyProfile.PRESET_KEYS.size(), true) # Custom is shown when individual aids differ
	controls["preset"] = preset_sel

	aids_toggle = Button.new()
	aids_toggle.name = "AidsToggle"
	aids_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	aids_toggle.focus_mode = Control.FOCUS_ALL
	aids_toggle.custom_minimum_size = Vector2(0, 34)
	aids_toggle.add_theme_font_override("font", CmrStyle.font(700))
	aids_toggle.add_theme_font_size_override("font_size", 14)
	aids_toggle.pressed.connect(toggle_aids)
	body.add_child(aids_toggle)

	aids_box = VBoxContainer.new()
	aids_box.name = "IndividualAids"
	aids_box.add_theme_constant_override("separation", 5)
	aids_box.visible = false
	body.add_child(aids_box)
	for k in DifficultyProfile.AID_KEYS:
		controls[k] = _selector_row(aids_box, "   " + String(DifficultyProfile.AID_NAMES[k]).to_upper(), OFF_ON_NAMES, k, true)

	controls["shifting"] = _selector_row(body, "SHIFTING", SHIFTING_NAMES, "shifting")
	controls["line"] = _selector_row(body, "RACING LINE", DifficultyProfile.LINE_NAMES, "line")
	controls["damage"] = _selector_row(body, "DAMAGE", DifficultyProfile.DAMAGE_NAMES, "damage")
	controls["recover"] = _selector_row(body, "AUTO-RECOVER", OFF_ON_NAMES, "recover")

	# fuel & tyre wear: campaign stages and map events run arcade rules
	var fw_row := HBoxContainer.new()
	fw_row.name = "FuelWearRow"
	fw_row.add_theme_constant_override("separation", 16)
	body.add_child(fw_row)
	var fw_cap := _text("FUEL & TYRE WEAR", 14, CmrStyle.MUTED, 800)
	fw_cap.custom_minimum_size.x = 240.0
	fw_cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fw_row.add_child(fw_cap)
	fuel_wear_label = _text("Off in campaign", 15, CmrStyle.MUTED, 700)
	fuel_wear_label.name = "FuelWearLabel"
	fuel_wear_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fuel_wear_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fw_row.add_child(fuel_wear_label)

	# --- fixed footer: START and CANCEL are always shown ---
	root_col.add_child(_rule(accent))

	var btn_row := HBoxContainer.new()
	btn_row.name = "ActionRow"
	btn_row.add_theme_constant_override("separation", 16)
	root_col.add_child(btn_row)

	start_button = Button.new()
	start_button.name = "StartButton"
	start_button.text = "START"
	start_button.focus_mode = Control.FOCUS_ALL
	start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_button.custom_minimum_size = Vector2(0, 46)
	start_button.add_theme_font_override("font", HudLayout.italic_font(900, -0.10))
	start_button.add_theme_font_size_override("font_size", 20)
	_style_action_button(start_button, accent, true)
	start_button.pressed.connect(confirm)
	btn_row.add_child(start_button)

	cancel_button = Button.new()
	cancel_button.name = "CancelButton"
	cancel_button.text = "CANCEL"
	cancel_button.focus_mode = Control.FOCUS_ALL
	cancel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_button.custom_minimum_size = Vector2(0, 46)
	cancel_button.add_theme_font_override("font", HudLayout.italic_font(800, -0.10))
	cancel_button.add_theme_font_size_override("font_size", 18)
	_style_action_button(cancel_button, accent, false)
	cancel_button.pressed.connect(cancel)
	btn_row.add_child(cancel_button)

	keys_label = _text("", 13, HudLayout.neon_primary().lightened(0.28), 700, true)
	keys_label.name = "KeysLabel"
	keys_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	keys_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_col.add_child(keys_label)
	_refresh_keys_hint()

func _selector_row(parent: Control, label_text: String, options: Array, key: String, sub := false) -> MenuSelector:
	var row := HBoxContainer.new()
	row.name = "Row_" + key
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)
	var lbl := _text(label_text, 13 if sub else 14, CmrStyle.MUTED if sub else CmrStyle.TEXT, 700 if sub else 800)
	lbl.custom_minimum_size.x = 240.0
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lbl)
	var sel := MenuSelector.new()
	sel.name = "Sel_" + key
	sel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sel.custom_minimum_size = Vector2(220.0, 34.0 if sub else 38.0)
	if sub:
		sel.add_theme_font_size_override("font_size", 15)
	for opt in options:
		sel.add_item(String(opt))
	sel.item_selected.connect(func(_idx: int) -> void: _on_setting_changed(key))
	row.add_child(sel)
	return sel

func _panel_style(accent: Color) -> StyleBoxFlat:
	var sb := HudLayout.neon_box(accent, 0.95, 6, 0.0, 14, 24.0, 18.0)
	sb.bg_color = HudLayout.glass_plate(0.95)
	return sb

func _style_action_button(b: Button, accent: Color, primary: bool) -> void:
	var hot := HudLayout.neon_hot()
	var is_ps1 := CmrStyle.skin == "ps1"
	var glow := 0 if is_ps1 else 10
	if primary:
		var n := CmrStyle._neon_ctrl_box(accent.darkened(0.28), accent, 6, 2, glow)
		var h := CmrStyle._neon_ctrl_box(accent, accent.lightened(0.25), 6, 2, glow)
		var p := CmrStyle._neon_ctrl_box(accent.lightened(0.15), Color.WHITE, 6, 2, glow)
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
		var h := CmrStyle._neon_ctrl_box(HudLayout.glass_plate(0.94).lightened(0.08), hot, 5, 2, glow)
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
	var pw := minf(clampf(safe.size.x * 0.64, 680.0, 940.0), safe.size.x - 32.0)
	var ph := minf(clampf(safe.size.y * 0.88, 560.0, 780.0), safe.size.y - 24.0)
	panel.position = Vector2(roundf(safe.position.x + (safe.size.x - pw) * 0.5), roundf(safe.position.y + (safe.size.y - ph) * 0.5))
	panel.size = Vector2(roundf(pw), roundf(ph))

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
	fans_label.text = "×%.2f  %s" % [mult, DifficultyProfile.fan_text(p).to_upper()]
	step_note_label.text = String(DifficultyProfile.STEP_NOTES[int(p.step)])
	_refresh_aids_toggle(p)
	_refresh_header(p)

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

## All visible, enabled focusable controls inside the panel in top-to-bottom order.
func focus_items() -> Array[Control]:
	var out: Array[Control] = []
	var order: Array[Control] = [controls.step as Control, controls.preset as Control, aids_toggle]
	if aids_expanded:
		for k in DifficultyProfile.AID_KEYS:
			order.append(controls[k] as Control)
	order.append(controls.shifting as Control)
	order.append(controls.line as Control)
	order.append(controls.damage as Control)
	order.append(controls.recover as Control)
	order.append(start_button)
	order.append(cancel_button)
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
	if vp != null:
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

func _ensure_focus() -> Control:
	var items := focus_items()
	if items.is_empty():
		return null
	var vp := get_viewport()
	var owner: Control = vp.gui_get_focus_owner() if vp != null else null
	if owner == null or not items.has(owner):
		start_button.grab_focus()
		return start_button
	return owner

func _move_vertical(dir: int) -> void:
	var items := focus_items()
	if items.is_empty():
		return
	var owner := _ensure_focus()
	var footer_start := items.find(start_button)
	if owner == start_button or owner == cancel_button:
		if dir < 0:
			items[maxi(footer_start - 1, 0)].grab_focus()
		else:
			items[0].grab_focus()
		return
	var idx := items.find(owner)
	if dir > 0 and idx == footer_start - 1:
		start_button.grab_focus()
		return
	if dir < 0 and idx == 0:
		start_button.grab_focus()
		return
	items[clampi(idx + dir, 0, footer_start - 1)].grab_focus()

func _move_horizontal(dir: int) -> void:
	var owner := _ensure_focus()
	if owner == null:
		return
	if owner == start_button:
		cancel_button.grab_focus()
		return
	if owner == cancel_button:
		start_button.grab_focus()
		return
	if owner == aids_toggle:
		set_aids_expanded(dir > 0)
		return
	if owner is MenuSelector:
		_step_selector(owner as MenuSelector, dir)

func _step_selector(sel: MenuSelector, dir: int) -> void:
	if sel == controls.preset and sel.selected == DifficultyProfile.PRESET_KEYS.size() and dir > 0:
		# Custom sits at the end (disabled): stepping right wraps cleanly to Beginner
		sel.select(0)
		sel.item_selected.emit(0)
		return
	sel.step(dir, false)

func _activate_focused() -> void:
	var owner := _ensure_focus()
	if owner == null:
		return
	if owner == start_button:
		confirm()
	elif owner == cancel_button:
		cancel()
	elif owner == aids_toggle:
		toggle_aids()
	elif owner is MenuSelector:
		(owner as MenuSelector).activate(1)

func _refresh_keys_hint() -> void:
	if keys_label == null:
		return
	keys_label.text = "↕ move   ◂ ▸ / LB RB change   Ⓐ select   START launch   Ⓑ cancel" if _last_pad \
		else "↑ ↓ move   ← → / Q E change   Enter select / start   Esc cancel"

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
			JOY_BUTTON_B: cancel()
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
			KEY_TAB: _move_vertical(-1 if kev.shift_pressed else 1)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				if not echo:
					_activate_focused()
			KEY_ESCAPE, KEY_BACKSPACE:
				if not echo:
					cancel()

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
