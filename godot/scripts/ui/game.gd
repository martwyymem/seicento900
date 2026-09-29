## Main game controller for the Seicento 900 Cup: front-end menus, race setup, the fixed-step race loop
## (with render interpolation and a spiral guard), keyboard/gamepad input, pause menu, results and the
## eight-round championship. The in-race HUD lives in RaceHud.
extends Control

const RaceHud = preload("res://scripts/ui/race_hud.gd")

const TRACK_KEYS := ["gp", "nordschleife", "monaco", "indy", "lemans", "monza", "silverstone", "spa", "suzuka", "zandvoort"]
const TRACK_NAMES := ["Nürburgring GP", "Nordschleife", "Monaco", "Indianapolis", "Le Mans", "Monza", "Silverstone", "Spa-Francorchamps", "Suzuka", "Zandvoort"]

const CHAMPIONSHIP_CALENDAR := ["monza", "silverstone", "spa", "gp", "monaco", "indy", "lemans", "nordschleife"]
const CHAMPIONSHIP_POINTS := [25, 18, 15, 12, 10, 8, 6, 4, 2, 1]
const TOP_MENU_TABS := ["Information", "Set Up", "Repair", "Race", "Save", "Quit"]
const MENU_TRACK_ART := preload("res://scripts/ui/menu_track_art.gd")
const MENU_WEATHER_ICON := preload("res://scripts/ui/menu_weather_icon.gd")
const MENU_TEMPERATURE_BAR := preload("res://scripts/ui/menu_temperature_bar.gd")
const MENU_REPAIR_ART := preload("res://scripts/ui/menu_repair_art.gd")
const MENU_REPAIR_STATUS := preload("res://scripts/ui/menu_repair_status.gd")
const MENU_CAR_SCENE := preload("res://scripts/ui/race_car_visual.tscn")
const FRONT_MENU := [
	{"id": "drivers", "word": "drivers", "desc": "Choose your car and racing setup."},
	{"id": "rally", "word": "rally", "desc": "Choose a circuit, set the conditions and race."},
	{"id": "arcade", "word": "arcade", "desc": "Race an eight-round championship."},
	{"id": "options", "word": "options", "desc": "Graphics and display settings."},
	{"id": "quit", "word": "quit", "desc": "Leave the Seicento Cup."},
]
const TRACK_DEFAULTS := {
	"gp": {"laps": 6, "wear": 2.0},
	"nordschleife": {"laps": 2, "wear": 1.0},
	"monaco": {"laps": 8, "wear": 2.0},
	"indy": {"laps": 12, "wear": 2.0},
	"lemans": {"laps": 2, "wear": 1.0},
	"monza": {"laps": 6, "wear": 2.0},
	"silverstone": {"laps": 6, "wear": 2.0},
	"spa": {"laps": 5, "wear": 2.0},
	"suzuka": {"laps": 6, "wear": 2.0},
	"zandvoort": {"laps": 6, "wear": 2.0},
}

const WARP_VALUES := [1, 2, 5, 10, 30, 60]
const UI_SCALES := [0.85, 1.0, 1.15, 1.3]
## 3D upscalers offered in the options (MetalFX only where the GPU driver supports it).
const UPSCALERS := [
	{"name": "Off (native resolution)", "mode": Viewport.SCALING_3D_MODE_BILINEAR},
	{"name": "AMD FSR 1 (spatial)", "mode": Viewport.SCALING_3D_MODE_FSR},
	{"name": "AMD FSR 2 (temporal)", "mode": Viewport.SCALING_3D_MODE_FSR2},
	{"name": "MetalFX Spatial", "mode": Viewport.SCALING_3D_MODE_METALFX_SPATIAL, "feature": RenderingDevice.SUPPORTS_METALFX_SPATIAL},
	{"name": "MetalFX Temporal", "mode": Viewport.SCALING_3D_MODE_METALFX_TEMPORAL, "feature": RenderingDevice.SUPPORTS_METALFX_TEMPORAL},
]
## Render-resolution presets for the upscalers, AMD's standard ratios.
const UPSCALE_PRESETS := [
	{"name": "Native AA (100%)", "scale": 1.0},
	{"name": "Quality (67%)", "scale": 0.67},
	{"name": "Balanced (59%)", "scale": 0.59},
	{"name": "Performance (50%)", "scale": 0.5},
	{"name": "Ultra performance (33%)", "scale": 0.33},
]
## FSR sharpening strength; Viewport.fsr_sharpness runs from 0 (sharpest) to 2 (softest).
const SHARPENING := [
	{"name": "Off", "value": 2.0},
	{"name": "Low", "value": 0.8},
	{"name": "Medium", "value": 0.4},
	{"name": "High", "value": 0.1},
]

## Frame-rate limits offered in the options (0 is unlimited). A ProMotion display would otherwise be driven at 120 Hz.
const FPS_LIMITS := [
	{"name": "30 fps", "fps": 30},
	{"name": "60 fps", "fps": 60},
	{"name": "120 fps", "fps": 120},
	{"name": "Unlimited", "fps": 0},
]
const MENU_FPS := 30 ## cap while the 3D view is hidden or holding a still image (menus, pause, results)
const BACKGROUND_FPS := 10 ## cap while the window is not in front
const STILL_FRAMES := 3 ## frames the 3D view keeps drawing after it stops changing, so its last image is the current one

const TICK := 1.0 / 120.0
const INK := CmrStyle.TEXT
const MUTED := CmrStyle.MUTED
const ACCENT := CmrStyle.ORANGE
const DANGER := CmrStyle.RED

var race: Race
var accumulator := 0.0
var paused := false
var _player_input := Race.PlayerInput.new() ## reused every frame instead of allocating one per _process call

# Audio
var audio: RaceAudio

# 3D World View
var world_view: Node3D

# UI Panels
var setup_panel: PanelContainer
var menu_tint: ColorRect ## the flat page tint behind every front-end page (one colour per page, as in CMR)
var menu_header: HBoxContainer
var menu_home: Control
var menu_home_art: Control
var menu_home_strip: HBoxContainer
var menu_home_desc: Label
var menu_home_clock: Label
var options_panel: PanelContainer
var upscaler_picker: OptionButton
var upscale_preset_picker: OptionButton
var sharpening_picker: OptionButton
var render_viewport: SubViewport
var home_menu_index := 1
var home_tween: Tween
var menu_clock := 0.0
var information_panel: Control
var information_map: Control
var information_title: Label
var information_facts: Label
var menu_car_preview: TextureRect
var menu_car_viewport: SubViewport
var render_view: TextureRect
var menu_car_summary: Label
var menu_car_rule: ColorRect
var repair_panel: Control
var repair_details: Control
var repair_rows: Array[Button] = []
var repair_row_rules: Array[ColorRect] = []
var repair_part_name: Label
var repair_time_label: Label
var repair_copy: Label
var repair_damage_marker: ColorRect
var repair_selected := 1
var menu_scroll: ScrollContainer
var display_mode_picker: OptionButton
var rules_section: Control
var antialiasing_picker: OptionButton
var vsync_toggle: CheckButton
var fps_limit_picker: OptionButton
var reflections_picker: OptionButton
var ssao_toggle: CheckButton
var shadows_toggle: CheckButton
var graphics_display_mode := 0
var graphics_fps_limit := 1 ## index into FPS_LIMITS
var graphics_antialiasing := 0
var graphics_vsync := true
var graphics_upscaler := 0 ## index into UPSCALERS
var graphics_upscale_preset := 1 ## index into UPSCALE_PRESETS
var graphics_sharpening := 2 ## index into SHARPENING
var graphics_reflections := 0 ## 0 off, 1 screen-space, 2 ray-traced
var graphics_ssao := true
var graphics_shadows := true
var graphics_ui_scale := 1 ## index into UI_SCALES
var ui_scale_picker: OptionButton
var menu_tab_buttons: Dictionary = {}
var menu_tab_dividers: Dictionary = {}
var menu_tab_index := 1
var active_menu_page := "home"
var hud: RaceHud
var result_panel: PanelContainer
var result_scroll: ScrollContainer
var pause_panel: PanelContainer
var pause_buttons: Array[Button] = []
var skipping := false
var _idle_input := Race.PlayerInput.new()

# Setup controls
var mode_button: Button
var is_championship_mode := false
var champ_data: Dictionary = {}
var track_picker: OptionButton
var laps_picker: SpinBox
var format_picker: OptionButton
var hours_picker: SpinBox
var start_hour_picker: SpinBox
var opponents_picker: SpinBox
var difficulty_picker: OptionButton
var weather_picker: OptionButton
var gearbox_picker: OptionButton
var grid_picker: OptionButton
var assists_picker: OptionButton
var wear_picker: SpinBox
var fuel_picker: SpinBox
var mandatory_stop_toggle: CheckButton
var two_compounds_toggle: CheckButton
var refuel_toggle: CheckButton
var collisions_toggle: CheckButton
var race_control_toggle: CheckButton
var dynamic_toggle: CheckButton
var draft_toggle: CheckButton
var strategist_toggle: CheckButton
var parallel_toggle: CheckButton
var crew_picker: OptionButton
var ai_learning_picker: OptionButton
var bot_physics_picker: OptionButton
var player_name_edit: LineEdit
var player_number_picker: SpinBox
var player_color_picker: ColorPickerButton
var player_stripes_toggle: CheckButton
var champ_reset_button: Button
var champ_reset_dialog: ConfirmationDialog
var menu_preview_car: Node3D
var status_label: Label
var champ_info_label: Label
var track_label: Label
var champ_side: VBoxContainer ## championship calendar and standings (the reference's side panel)
var champ_calendar: GridContainer
var champ_table: GridContainer
var strategy_section: VBoxContainer
var strategy_info: Label
var race_length_label: Label
var strategy_list: VBoxContainer
var strategy_group: ButtonGroup
var custom_box: VBoxContainer
var custom_rows: VBoxContainer
var custom_eval: Label
var ai_memory_label: Label
var ai_forget_button: Button

# Pit strategy chosen on the set-up page (the reference's strategy panel)
var car_model := CarModel.new()
var tyre_model := Tyres.new()
var strategy := Strategy.new(car_model, tyre_model)
var strategy_options: Array = []
var strategy_choice := 0 ## index into strategy_options, or -1 while a custom plan is being edited
var custom_stints: Array = [] ## [{c, laps}]
var current_plan = null ## the plan the next single race starts with, null when none is valid
var _strategy_pending := false
var _loading_settings := false

# Player Inputs
var throttle := 0.0
var brake := 0.0
var steer := 0.0
var shift_up := false
var shift_down := false
var gamepad_active := false
var gamepad_device := -1
var warp_index := 0
var _app_focused := true
var _view_live := true ## the 3D view is being rendered (see _sync_rendering)
var _still_frames := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = CmrStyle.build_theme()
	get_viewport().size_changed.connect(_fit_3d_views)

	_load_championship()
	_build_audio()
	add_child(DevHud.new())
	_build_viewport()
	_build_setup()
	_build_information_page()
	_build_repair_page()
	_build_home_screen()
	_build_options_page()
	_build_hud()
	_build_results()
	_show_home()
	_fit_3d_views.call_deferred()

func _build_audio() -> void:
	audio = RaceAudio.new()
	add_child(audio)

## Battery and heat: the 3D view is only rendered while somebody can see it change. Behind the opaque front-end
## pages it is off; while paused or on the results screen it draws a few more frames and then keeps its last
## image. The frame-rate cap follows the same states, and drops further while the window is in the background.
func _sync_rendering() -> void:
	var covered := menu_tint.visible
	var still := not covered and race != null and (paused or race.phase == "finished") and not skipping
	_still_frames = _still_frames + 1 if still else 0
	var live := not covered and _still_frames <= STILL_FRAMES
	if live != _view_live:
		_view_live = live
		render_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if live else SubViewport.UPDATE_DISABLED
		world_view.process_mode = Node.PROCESS_MODE_INHERIT if live else Node.PROCESS_MODE_DISABLED
	var fps: int = FPS_LIMITS[graphics_fps_limit].fps
	if not _app_focused:
		fps = BACKGROUND_FPS
	elif not live:
		fps = MENU_FPS if fps == 0 else mini(fps, MENU_FPS)
	if Engine.max_fps != fps:
		Engine.max_fps = fps

func _process(delta: float) -> void:
	_sync_rendering()
	if not race:
		menu_clock += delta
		if is_instance_valid(menu_home_clock):
			var whole_seconds := int(menu_clock)
			menu_home_clock.text = "%02d:%02d.%02d" % [int(floor(float(whole_seconds) / 60.0)), whole_seconds % 60, int(fmod(menu_clock, 1.0) * 100.0)]
		# the showroom turntable keeps turning, as on the CMR car screens
		if is_instance_valid(menu_preview_car) and menu_car_preview.visible:
			menu_preview_car.rotation.y += delta * 0.3
		return
	if skipping:
		_skip_step()
		world_view.render_alpha = 1.0
		hud.update(delta)
		return
	if paused or race.phase == "finished":
		return
	_poll_gamepad()
	_update_input(delta)
	var p := race.player
	# under time warp the co-driver drives
	if race.warp > 1 and not p.autopilot and p.mode == "race" and not p.finished and not p.dnf:
		race.set_autopilot(true)
	accumulator += minf(delta, 0.1) * race.warp
	var input := _player_input
	input.throttle = throttle
	input.brake = brake
	input.steer = steer
	input.shift_up = shift_up
	input.shift_down = shift_down

	var steps := 0
	var cap := 40 * race.warp
	var t0 := Time.get_ticks_usec()
	while accumulator >= TICK and steps < cap and race.phase != "finished":
		race.step(TICK, input)
		accumulator -= TICK
		steps += 1
		# never let a slow machine fall into a spiral at high warp
		if (steps & 63) == 0 and Time.get_ticks_usec() - t0 > 40000:
			break
	if steps >= cap or accumulator > TICK * 4.0 * race.warp:
		accumulator = 0.0
	if steps > 0:
		shift_up = false
		shift_down = false
	world_view.render_alpha = accumulator / TICK

	if is_instance_valid(audio):
		audio.update_car(p, not p.finished and not p.dnf)
	hud.update(delta)
	if race.phase == "finished":
		_show_results()

## Keyboard driving: pedals and steering ease in and out like the reference instead of snapping.
func _update_input(dt: float) -> void:
	var up := Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)
	var down := Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_SPACE)
	var left := Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)
	var right := Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)
	if up or down or left or right:
		gamepad_active = false
	if gamepad_active:
		return
	var st := (1.0 if right else 0.0) - (1.0 if left else 0.0)
	var back := st == 0.0 or signf(st) != signf(steer)
	steer = move_toward(steer, st, (7.0 if back else 3.2) * dt)
	throttle = move_toward(throttle, 1.0 if up else 0.0, 6.0 * dt)
	brake = move_toward(brake, 1.0 if down else 0.0, 8.0 * dt)

## Once the player is out of it, the rest of the race runs as fast as the machine allows.
func _begin_skip() -> void:
	if not race or race.phase == "finished" or skipping:
		return
	skipping = true
	race.warp = 60 # the field drops to the cheap rail model
	if is_instance_valid(audio):
		audio.update_car(race.player, false)

func _skip_step() -> void:
	var t0 := Time.get_ticks_usec()
	# check the clock every few steps: a GDScript step costs ~0.3 ms, so batches of 200 (as in the
	# reference) would overrun the 25 ms budget several times over and stutter the banner
	while race.phase != "finished" and Time.get_ticks_usec() - t0 < 25000:
		for i in 8:
			race.step(1.0 / 60.0, _idle_input)
			if race.phase == "finished":
				break
	var home := 0
	for c in race.cars:
		if c.finished or c.dnf:
			home += 1
	if race.timed and race.time_left > 0.0:
		hud.skip_note = "%s to go" % RaceHud._clock_text(race.time_left)
	else:
		hud.skip_note = "%d/%d cars home" % [home, race.cars.size()]
	if race.phase == "finished":
		skipping = false
		hud.skip_note = ""
		_show_results()

func _poll_gamepad() -> void:
	if not gamepad_active:
		return
	var connected := Input.get_connected_joypads()
	if not connected.has(gamepad_device):
		gamepad_active = false
		gamepad_device = -1
		throttle = 0.0
		brake = 0.0
		steer = 0.0
		return
	var raw_steer := Input.get_joy_axis(gamepad_device, JOY_AXIS_LEFT_X)
	var deadband := maxf(0.0, (absf(raw_steer) - 0.1) / 0.9)
	steer = signf(raw_steer) * deadband * deadband
	throttle = clampf(Input.get_joy_axis(gamepad_device, JOY_AXIS_TRIGGER_RIGHT), 0.0, 1.0)
	brake = clampf(Input.get_joy_axis(gamepad_device, JOY_AXIS_TRIGGER_LEFT), 0.0, 1.0)

## The 3D views are drawn through TextureRects rather than stretching SubViewportContainers: the UI is laid
## out on a 1600×900 canvas that the window scales (canvas_items stretch), but the 3D renders at the
## window's real pixel size so it stays sharp on high-resolution displays.
func _build_viewport() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1600, 900)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	render_viewport = viewport
	_load_graphics_settings()
	add_child(viewport)
	render_view = _viewport_view(viewport)
	render_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(render_view)
	move_child(render_view, 0)
	move_child(viewport, 0)

	world_view = load("res://ui/race_world.tscn").instantiate()
	viewport.add_child(world_view)
	world_view.set_track(Race.get_track(TRACK_KEYS[0]))
	_apply_world_graphics_settings()

func _viewport_view(viewport: SubViewport) -> TextureRect:
	var view := TextureRect.new()
	view.texture = viewport.get_texture()
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_SCALE
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.resized.connect(_fit_3d_views)
	return view

## Size each 3D viewport to the physical pixels its TextureRect covers on screen.
func _fit_3d_views() -> void:
	var px_scale := get_viewport().get_final_transform().get_scale()
	for pair in [[render_view, render_viewport], [menu_car_preview, menu_car_viewport]]:
		var view: Control = pair[0]
		var vp: SubViewport = pair[1]
		if not is_instance_valid(view) or not is_instance_valid(vp):
			continue
		var px := Vector2i((view.size * px_scale).round()).max(Vector2i(2, 2))
		if vp.size != px:
			vp.size = px
			_still_frames = 0 # a resized target is blank until it is drawn again

func _build_setup() -> void:
	menu_tint = ColorRect.new()
	menu_tint.name = "MenuTint"
	menu_tint.color = CmrStyle.TINT_HOME
	menu_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(menu_tint)
	move_child(menu_tint, 2)

	_build_menu_header()
	_build_menu_car_preview()

	setup_panel = _panel(Vector2(0, 0))
	setup_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	setup_panel.anchor_left = 0.58
	setup_panel.anchor_right = 0.98
	setup_panel.anchor_top = 0.17
	setup_panel.anchor_bottom = 0.96
	setup_panel.offset_left = 0
	setup_panel.offset_right = 0
	setup_panel.offset_top = 0
	setup_panel.offset_bottom = 0
	add_child(setup_panel)

	menu_scroll = ScrollContainer.new()
	menu_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	setup_panel.add_child(menu_scroll)
	var col := _column(menu_scroll, 12)
	_title(col, "SET UP RACE", "SEICENTO 900 CUP")

	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 10)
	col.add_child(mode_row)

	mode_button = _button("SINGLE RACE", CmrStyle.FIELD)
	mode_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_button.add_theme_font_size_override("font_size", 18)
	mode_button.pressed.connect(_toggle_mode)
	mode_row.add_child(mode_button)
	var reset_button := _button("RESET SEASON", DANGER)
	reset_button.pressed.connect(func() -> void: champ_reset_dialog.popup_centered())
	mode_row.add_child(reset_button)
	champ_reset_button = reset_button
	champ_reset_dialog = ConfirmationDialog.new()
	champ_reset_dialog.title = "Reset championship"
	champ_reset_dialog.dialog_text = "Discard the saved championship standings and restart at round 1?"
	champ_reset_dialog.confirmed.connect(_reset_championship)
	add_child(champ_reset_dialog)

	champ_info_label = _label("", 13, CmrStyle.TEXT)
	champ_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(champ_info_label)
	champ_side = VBoxContainer.new()
	champ_side.add_theme_constant_override("separation", 6)
	col.add_child(champ_side)
	champ_side.add_child(_label("CALENDAR", 13, MUTED))
	champ_calendar = GridContainer.new()
	champ_calendar.columns = 3
	champ_calendar.add_theme_constant_override("h_separation", 10)
	champ_calendar.add_theme_constant_override("v_separation", 2)
	champ_side.add_child(champ_calendar)
	champ_side.add_child(_label("STANDINGS", 13, MUTED))
	champ_table = GridContainer.new()
	champ_table.columns = 4
	champ_table.add_theme_constant_override("h_separation", 10)
	champ_table.add_theme_constant_override("v_separation", 2)
	champ_side.add_child(champ_table)
	champ_side.hide()
	_menu_rule(col)

	_field_label(col, "CIRCUIT")
	track_label = col.get_child(-1)
	track_picker = OptionButton.new()
	for name in TRACK_NAMES:
		track_picker.add_item(name)
	track_picker.custom_minimum_size.y = 40
	_style_control(track_picker)
	track_picker.item_selected.connect(_select_track)
	col.add_child(track_picker)

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 14)
	col.add_child(row1)
	laps_picker = _spin(row1, "LAPS", 1, 99, 6)
	laps_picker.value_changed.connect(func(_value: float) -> void: _update_menu_car_summary())
	opponents_picker = _spin(row1, "OPPONENTS", 0, 15, 12)

	var format_row := HBoxContainer.new()
	format_row.add_theme_constant_override("separation", 14)
	col.add_child(format_row)
	var format_col := VBoxContainer.new()
	format_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	format_row.add_child(format_col)
	_field_label(format_col, "RACE FORMAT")
	format_picker = OptionButton.new()
	format_picker.add_item("Lap race")
	format_picker.add_item("Timed endurance")
	format_picker.custom_minimum_size.y = 40
	_style_control(format_picker)
	format_picker.item_selected.connect(_select_format)
	format_col.add_child(format_picker)
	hours_picker = _spin(format_row, "HOURS", 0.25, 24, 1, 0.25)
	hours_picker.value_changed.connect(func(_value: float) -> void: _update_menu_car_summary())
	hours_picker.get_parent().visible = false
	start_hour_picker = _spin(format_row, "START HOUR", 0, 23.75, 14, 0.25)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 14)
	col.add_child(row2)

	var diff_col := VBoxContainer.new()
	diff_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(diff_col)
	_field_label(diff_col, "DIFFICULTY")
	difficulty_picker = OptionButton.new()
	for d in ["Easy", "Medium", "Hard", "Alien"]:
		difficulty_picker.add_item(d)
	difficulty_picker.selected = 1
	difficulty_picker.custom_minimum_size.y = 40
	_style_control(difficulty_picker)
	diff_col.add_child(difficulty_picker)

	var w_col := VBoxContainer.new()
	w_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(w_col)
	_field_label(w_col, "WEATHER")
	weather_picker = OptionButton.new()
	for w in ["Dry", "Wet", "Variable"]:
		weather_picker.add_item(w)
	weather_picker.selected = 0
	weather_picker.custom_minimum_size.y = 40
	_style_control(weather_picker)
	weather_picker.item_selected.connect(func(_index: int) -> void: _update_information_page())
	w_col.add_child(weather_picker)

	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 14)
	col.add_child(row3)

	var gb_col := VBoxContainer.new()
	gb_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row3.add_child(gb_col)
	_field_label(gb_col, "TRANSMISSION")
	gearbox_picker = OptionButton.new()
	gearbox_picker.add_item("Automatic")
	gearbox_picker.add_item("Manual (E/Q)")
	gearbox_picker.custom_minimum_size.y = 40
	_style_control(gearbox_picker)
	gb_col.add_child(gearbox_picker)

	_menu_rule(col)
	_field_label(col, "DRIVER PROFILE")
	var profile_row := HBoxContainer.new()
	profile_row.add_theme_constant_override("separation", 14)
	col.add_child(profile_row)
	var name_col := VBoxContainer.new()
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile_row.add_child(name_col)
	_field_label(name_col, "DRIVER NAME")
	player_name_edit = LineEdit.new()
	player_name_edit.text = "You"
	player_name_edit.placeholder_text = "Driver name"
	player_name_edit.custom_minimum_size.y = 40
	name_col.add_child(player_name_edit)
	player_number_picker = _spin(profile_row, "CAR NO.", 1, 99, 9)
	var paint_col := VBoxContainer.new()
	paint_col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	profile_row.add_child(paint_col)
	_field_label(paint_col, "PAINT")
	player_color_picker = ColorPickerButton.new()
	player_color_picker.color = Color("#b3121d")
	player_color_picker.custom_minimum_size = Vector2(76, 40)
	paint_col.add_child(player_color_picker)
	player_stripes_toggle = _check_field(profile_row, "Twin stripes", true)
	player_color_picker.color_changed.connect(func(_color: Color) -> void: _update_menu_car_summary())
	player_stripes_toggle.toggled.connect(func(_enabled: bool) -> void: _update_menu_car_summary())

	var row4 := HBoxContainer.new()
	row4.add_theme_constant_override("separation", 14)
	col.add_child(row4)
	grid_picker = _option_field(row4, "GRID POSITION", ["Pole", "Middle", "Back", "Random"])
	assists_picker = _option_field(row4, "DRIVING AIDS", ["Full assists", "ABS only", "Off"])
	_menu_rule(col)
	rules_section = _label("RACE RULES & PIT STRATEGY", 16, CmrStyle.TEXT)
	col.add_child(rules_section)
	var row5 := HBoxContainer.new()
	row5.add_theme_constant_override("separation", 14)
	col.add_child(row5)
	wear_picker = _spin(row5, "TYRE WEAR ×", 0.5, 5, 2, 0.5)
	fuel_picker = _spin(row5, "FUEL USE ×", 0.5, 10, 1, 0.5)
	var row6 := HBoxContainer.new()
	row6.add_theme_constant_override("separation", 10)
	col.add_child(row6)
	mandatory_stop_toggle = _check_field(row6, "Mandatory stop", true)
	two_compounds_toggle = _check_field(row6, "Two dry tyres", false)
	refuel_toggle = _check_field(row6, "Refuelling", true)
	var row7 := HBoxContainer.new()
	row7.add_theme_constant_override("separation", 10)
	col.add_child(row7)
	collisions_toggle = _check_field(row7, "Car contact", true)
	strategist_toggle = _check_field(row7, "Auto strategist", false)
	strategist_toggle.tooltip_text = "On: the strategist boxes you by itself. Off: it only advises and you press P to call the stop"
	parallel_toggle = _check_field(row7, "Parallel service", false)
	var row8 := HBoxContainer.new()
	row8.add_theme_constant_override("separation", 10)
	col.add_child(row8)
	draft_toggle = _check_field(row8, "Slipstream", true)
	draft_toggle.tooltip_text = "A car close behind another pulls less air and gains speed; the tow builds and fades over about a second"
	var crew_row := HBoxContainer.new()
	col.add_child(crew_row)
	crew_picker = _option_field(crew_row, "PIT CREW", ["Pro", "Club", "Amateur"])
	race_control_toggle = _check_field(crew_row, "Race control", true)
	race_control_toggle.tooltip_text = "Flags, safety car, red flags, stewards' penalties and crash damage"
	dynamic_toggle = _check_field(crew_row, "Live wear and stops", true)
	dynamic_toggle.tooltip_text = "Tyre wear and fuel follow how hard each car is driven, and pit stops follow the live state of tyres and tank instead of the starting plan"
	var bot_row := HBoxContainer.new()
	col.add_child(bot_row)
	ai_learning_picker = _option_field(bot_row, "AI LEARNING", ["On", "Off"])
	bot_physics_picker = _option_field(bot_row, "BOT PHYSICS", ["Full physics", "Rail model"])
	var memory_row := HBoxContainer.new()
	memory_row.add_theme_constant_override("separation", 10)
	col.add_child(memory_row)
	ai_memory_label = _label("", 13, CmrStyle.TEXT)
	ai_memory_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ai_memory_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	memory_row.add_child(ai_memory_label)
	ai_forget_button = _button("FORGET", DANGER)
	ai_forget_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ai_forget_button.pressed.connect(_forget_ai_memory)
	memory_row.add_child(ai_forget_button)
	_build_strategy_section(col)

	status_label = _label("", 13, ACCENT)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(status_label)

	var start_btn := _button("RACE  ▸", ACCENT)
	start_btn.custom_minimum_size.y = 52
	start_btn.add_theme_font_size_override("font_size", 24)
	start_btn.pressed.connect(_start_race)
	col.add_child(start_btn)

	var foot := _label("W/↑ Drive · S/↓/Space Brake · A/D Steer · E/Q Gear · P Box · [/] Tyres · −/= Fuel · R Replan · C Camera · L Line · O Autopilot · ,/. Time · Esc Pause · Gamepad: stick / triggers", 11, MUTED)
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(foot)

	for picker in [weather_picker, crew_picker]:
		picker.item_selected.connect(func(_i: int) -> void: _queue_strategy_refresh())
	for spin in [laps_picker, hours_picker, wear_picker, fuel_picker]:
		spin.value_changed.connect(func(_v: float) -> void: _queue_strategy_refresh())
	for toggle in [mandatory_stop_toggle, two_compounds_toggle, refuel_toggle, parallel_toggle]:
		toggle.toggled.connect(func(_on: bool) -> void: _queue_strategy_refresh())
	ai_learning_picker.item_selected.connect(func(_i: int) -> void: _update_ai_memory())
	_load_race_settings()
	_update_championship_view()
	_update_menu_car_summary()
	_update_ai_memory()
	_queue_strategy_refresh()

func _build_strategy_section(parent: VBoxContainer) -> void:
	strategy_section = VBoxContainer.new()
	strategy_section.add_theme_constant_override("separation", 6)
	parent.add_child(strategy_section)
	_menu_rule(strategy_section)
	strategy_section.add_child(_label("PIT STRATEGY", 16, CmrStyle.TEXT))
	race_length_label = _label("", 13, MUTED)
	race_length_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	strategy_section.add_child(race_length_label)
	strategy_info = _label("", 13, CmrStyle.TEXT)
	strategy_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	strategy_section.add_child(strategy_info)
	strategy_group = ButtonGroup.new()
	strategy_group.allow_unpress = true
	strategy_list = VBoxContainer.new()
	strategy_list.add_theme_constant_override("separation", 4)
	strategy_section.add_child(strategy_list)

	custom_box = VBoxContainer.new()
	custom_box.add_theme_constant_override("separation", 4)
	strategy_section.add_child(custom_box)
	custom_box.add_child(_label("YOUR PLAN", 13, MUTED))
	custom_rows = VBoxContainer.new()
	custom_rows.add_theme_constant_override("separation", 4)
	custom_box.add_child(custom_rows)
	var add := _button("+ STINT", CmrStyle.FIELD)
	add.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add.pressed.connect(func() -> void:
		var base := _editor_stints()
		var last: Dictionary = base[-1] if base.size() else {"c": "M", "laps": 1}
		base.append({"c": last.c, "laps": 1})
		_set_custom(base, true)
	)
	custom_box.add_child(add)
	custom_eval = _label("", 13, CmrStyle.TEXT)
	custom_eval.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	custom_box.add_child(custom_eval)

## Laps the strategist plans for: the lap count, or the expected laps of a timed race.
func _race_laps(track: Track) -> int:
	if format_picker.selected == 1:
		return strategy.estimate_laps(track, hours_picker.value * 3600.0, {
			"fuel_mult": fuel_picker.value, "weather": ["dry", "wet", "variable"][weather_picker.selected],
			"wear_mult": wear_picker.value, "crew": ["pro", "club", "amateur"][crew_picker.selected],
			"parallel": parallel_toggle.button_pressed, "refuel": refuel_toggle.button_pressed,
		})
	return int(laps_picker.value)

func _plan_opts(track: Track, laps: int, wear_mult: float) -> Dictionary:
	return {
		"track": track, "laps": laps, "wet": 0.85 if weather_picker.selected == 1 else 0.0,
		"wear_mult": wear_mult, "fuel_mult": fuel_picker.value,
		"rules": {"mandatory_stop": mandatory_stop_toggle.button_pressed, "two_compounds": two_compounds_toggle.button_pressed, "refuel": refuel_toggle.button_pressed},
		"crew": ["pro", "club", "amateur"][crew_picker.selected], "parallel": parallel_toggle.button_pressed,
	}

## Any setting that changes the race drops a hand-built plan and goes back to the fastest option.
func _queue_strategy_refresh(reset_choice := true) -> void:
	if _loading_settings or not is_instance_valid(strategy_list):
		return
	if reset_choice:
		strategy_choice = 0
		custom_stints = []
	if _strategy_pending:
		return
	_strategy_pending = true
	_refresh_strategy.call_deferred()

func _refresh_strategy() -> void:
	var track := Race.get_track(TRACK_KEYS[track_picker.selected])
	if track.cal.is_empty():
		# the first plan on a circuit simulates reference laps (up to a couple of seconds)
		strategy_info.text = "Working out lap times at %s…" % track.name
		current_plan = null
		for child in strategy_list.get_children():
			child.queue_free()
		custom_box.hide()
		await get_tree().process_frame
		await get_tree().process_frame
		if track != Race.get_track(TRACK_KEYS[track_picker.selected]):
			_strategy_pending = false
			_queue_strategy_refresh(false)
			return
	_strategy_pending = false
	var cal := strategy.calibrate(track)
	var laps := _race_laps(track)
	var po := _plan_opts(track, laps, wear_picker.value)
	var plan_opts := po.duplicate()
	plan_opts["diverse"] = true
	strategy_options = strategy.plan(plan_opts).slice(0, 7)
	var fpl: float = cal.fuel_per_lap * fuel_picker.value
	var tank: float = car_model.spec.tank
	var lap := Strategy.lap_time(cal, tyre_model.compound_grip("M", po.wet) * 0.95 * 0.95, car_model.mass_with_fuel(10.0))
	var stop: float = cal.pit_drive_loss + Strategy.service_time(po.crew, po.parallel, true, fpl * 3.0 if refuel_toggle.button_pressed else 0.0)
	var lives := []
	var all_short := true
	for c in Tyres.KEYS:
		var life := strategy.tyre_life_laps(track, c, po.wet, wear_picker.value)
		all_short = all_short and life < 1.0
		lives.append("%s %.1f" % [c, life])
	var info := "Lap ≈ %s · fuel %.2f L/lap (tank %d L = %.1f laps) · pit stop ≈ %d s\nTyre life (laps): %s" % [
		Race.fmt_time(lap), fpl, int(tank), tank / fpl, roundi(stop), "   ".join(lives)]
	if strategy_options.is_empty():
		var why := "No plan satisfies these rules."
		if all_short:
			why = "No tyre survives a single lap — lower the tyre wear."
		elif not refuel_toggle.button_pressed and Strategy.fuel_need(laps, fpl) > tank:
			why = "Without refuelling the race needs %.1f L — more than the %d L tank." % [Strategy.fuel_need(laps, fpl), int(tank)]
		info += "\n⚠ " + why
	elif strategy_options[0].horizon:
		info += "\nEndurance: the strategist plans the next %d laps and keeps extending the plan (≈ %d stops in all)." % [
			strategy_options[0].horizon, roundi(float(laps) / strategy_options[0].horizon * strategy_options[0].stops)]
	strategy_info.text = info
	if format_picker.selected == 1:
		race_length_label.text = "%s race ≈ %d laps · %d km — the winner is whoever leads when the clock runs out" % [
			_fmt_hours(hours_picker.value), laps, roundi(laps * track.L / 1000.0)]
	else:
		var mins := laps * lap * 1.02 / 60.0
		race_length_label.text = "≈ %s · %.1f km" % ["%d min" % roundi(mins) if mins < 90.0 else "%.1f h" % (mins / 60.0), laps * track.L / 1000.0]

	for child in strategy_list.get_children():
		child.queue_free()
	if strategy_choice >= strategy_options.size():
		strategy_choice = 0
	for i in strategy_options.size():
		strategy_list.add_child(_plan_button(i))
	custom_box.visible = laps <= Strategy.LONG_RACE
	_render_custom_rows()

func _plan_button(i: int) -> Button:
	var o: Dictionary = strategy_options[i]
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = strategy_group
	b.button_pressed = strategy_choice == i
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = 46
	b.add_theme_stylebox_override("normal", CmrStyle.box(CmrStyle.FIELD_DIM))
	b.add_theme_stylebox_override("hover", CmrStyle.box(CmrStyle.FIELD))
	var on := CmrStyle.box(CmrStyle.ORANGE)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 8
	row.offset_right = -10
	row.add_theme_constant_override("separation", 3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	_stint_chips(row, o.stints, 5)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	var head := Race.fmt_time(o.time).get_slice(".", 0) if i == 0 else "+%.1f s" % (o.time - strategy_options[0].time)
	var right := _label("%s\n%d stop%s · start %.1f L" % [head, o.stops, "" if o.stops == 1 else "s", o.stints[0].fuel], 12, CmrStyle.INK)
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	right.size_flags_vertical = Control.SIZE_FILL
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(right)
	b.pressed.connect(func() -> void:
		strategy_choice = i
		custom_stints = []
		b.set_pressed_no_signal(true)
		_render_custom_rows()
	)
	return b

## Compound badges with lap counts: S 12 → M 14 → …
func _stint_chips(row: HBoxContainer, stints: Array, max_shown: int) -> void:
	var shown := stints.size() if stints.size() <= max_shown + 1 else max_shown
	for k in shown:
		var st: Dictionary = stints[k]
		if k > 0:
			row.add_child(_chip_label("→", CmrStyle.INK_SOFT, 13))
		var badge := _chip_label(st.c, CmrStyle.INK, 13)
		badge.custom_minimum_size = Vector2(22, 22)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var style := StyleBoxFlat.new()
		style.bg_color = tyre_model.compounds[st.c].color
		style.set_corner_radius_all(11)
		badge.add_theme_stylebox_override("normal", style)
		row.add_child(badge)
		row.add_child(_chip_label(str(st.laps), CmrStyle.INK, 15))
	if shown < stints.size():
		row.add_child(_chip_label("→ … %d more" % (stints.size() - shown), CmrStyle.INK_SOFT, 12))

func _chip_label(text: String, color: Color, size: int) -> Label:
	var l := _label(text, size, color)
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## The stints shown in the editor: the hand-built plan, else the selected option.
func _editor_stints() -> Array:
	var src: Array = custom_stints if strategy_choice < 0 else (strategy_options[strategy_choice].stints if strategy_choice < strategy_options.size() else [])
	var out := []
	for st in src:
		out.append({"c": st.c, "laps": int(st.laps)})
	if out.is_empty():
		out.append({"c": "W" if weather_picker.selected == 1 else "M", "laps": _race_laps(Race.get_track(TRACK_KEYS[track_picker.selected]))})
	return out

func _set_custom(stints: Array, rebuild: bool) -> void:
	custom_stints = stints
	strategy_choice = -1
	for b in strategy_list.get_children():
		(b as Button).set_pressed_no_signal(false)
	if rebuild:
		_render_custom_rows()
	else:
		_update_custom_eval()

func _render_custom_rows() -> void:
	for child in custom_rows.get_children():
		child.queue_free()
	var stints := _editor_stints()
	var max_laps := maxi(1, _race_laps(Race.get_track(TRACK_KEYS[track_picker.selected])))
	for k in stints.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		custom_rows.add_child(row)
		var num := _label("%d." % (k + 1), 15, MUTED)
		num.custom_minimum_size.x = 26
		row.add_child(num)
		var compound := OptionButton.new()
		for c in Tyres.KEYS:
			compound.add_item(tyre_model.compounds[c].display_name)
		compound.select(Tyres.KEYS.find(stints[k].c))
		compound.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		compound.custom_minimum_size.y = 36
		_style_control(compound)
		compound.item_selected.connect(func(idx: int) -> void:
			var s2 := _editor_stints()
			s2[k].c = Tyres.KEYS[idx]
			_set_custom(s2, false)
		)
		row.add_child(compound)
		var laps := SpinBox.new()
		laps.min_value = 1
		laps.max_value = max_laps
		laps.value = stints[k].laps
		laps.suffix = "laps"
		laps.custom_minimum_size = Vector2(120, 36)
		_style_control(laps)
		laps.value_changed.connect(func(v: float) -> void:
			var s2 := _editor_stints()
			s2[k].laps = maxi(1, roundi(v))
			_set_custom(s2, false)
		)
		row.add_child(laps)
		var del := _button("✕", DANGER)
		del.tooltip_text = "Remove stint"
		del.custom_minimum_size = Vector2(36, 36)
		del.disabled = stints.size() < 2
		del.pressed.connect(func() -> void:
			var s2 := _editor_stints()
			if s2.size() > 1:
				s2.remove_at(k)
			_set_custom(s2, true)
		)
		row.add_child(del)
	_update_custom_eval()

## Validate the hand-built plan (or adopt the selected option) as the plan the race starts with.
func _update_custom_eval() -> void:
	if strategy_choice >= 0:
		current_plan = strategy_options[strategy_choice] if strategy_choice < strategy_options.size() else null
		custom_eval.text = "Edit any stint to build your own plan." if current_plan else ""
		custom_eval.add_theme_color_override("font_color", MUTED)
		return
	var track := Race.get_track(TRACK_KEYS[track_picker.selected])
	var res := strategy.evaluate(_plan_opts(track, _race_laps(track), wear_picker.value), custom_stints)
	if res.errors.size():
		custom_eval.text = "\n".join(res.errors.map(func(e): return "⚠ " + e))
		custom_eval.add_theme_color_override("font_color", CmrStyle.RED)
		current_plan = null
	else:
		var best: float = strategy_options[0].time if strategy_options.size() else res.time
		custom_eval.text = "✓ Valid · est. %s (%s%.1f s vs best)" % [Race.fmt_time(res.time).get_slice(".", 0), "+" if res.time - best >= 0.0 else "", res.time - best]
		custom_eval.add_theme_color_override("font_color", CmrStyle.GREEN)
		current_plan = res

## What the learning AI remembers about you on the selected circuit.
func _update_ai_memory() -> void:
	if not is_instance_valid(ai_memory_label):
		return
	var key: String = CHAMPIONSHIP_CALENDAR[_champ_round()] if is_championship_mode else TRACK_KEYS[track_picker.selected]
	var track := Race.get_track(key)
	var name: String = track.cfg.short_name if track.cfg and track.cfg.short_name != "" else track.name
	var m := Brain.summary(key)
	ai_forget_button.visible = false
	if ai_learning_picker.selected == 1:
		ai_memory_label.text = "Every bot drives one fixed pace, and nothing is learned."
	elif m.is_empty() or not m.laps:
		ai_memory_label.text = "The bots haven't seen you drive at %s yet. They learn from every lap you drive yourself." % name
	else:
		var text := "The field has studied %d of your laps at %s (%d corners mapped" % [m.laps, name, m.sections]
		if m.pace != null:
			text += ", your pace ≈ %.1f %% of the limit" % (m.pace * 100.0)
		var rough = m.get("rough")
		text += "). You block %d %% of attacks%s." % [roundi(float(m.get("block") if m.get("block") != null else 0.0) * 100.0), " and race rough" if rough != null and rough > 0.3 else ""]
		ai_memory_label.text = text
		ai_forget_button.visible = true

func _forget_ai_memory() -> void:
	var key: String = CHAMPIONSHIP_CALENDAR[_champ_round()] if is_championship_mode else TRACK_KEYS[track_picker.selected]
	var dialog := ConfirmationDialog.new()
	dialog.title = "Forget AI memory"
	dialog.dialog_text = "Make the bots forget everything they learned about you at %s?" % Race.get_track(key).name
	dialog.confirmed.connect(func() -> void:
		Brain.forget(key)
		_update_ai_memory()
	)
	dialog.visibility_changed.connect(func() -> void:
		if not dialog.visible:
			dialog.queue_free()
	)
	add_child(dialog)
	dialog.popup_centered()

const RACE_SETTINGS_PATH := "user://race_settings.cfg"

## The set-up page survives restarts, like the reference's saved settings.
func _race_setting_controls() -> Dictionary:
	return {
		"track": track_picker, "laps": laps_picker, "format": format_picker, "hours": hours_picker,
		"start_hour": start_hour_picker, "opponents": opponents_picker, "difficulty": difficulty_picker,
		"weather": weather_picker, "gearbox": gearbox_picker, "grid": grid_picker, "assists": assists_picker,
		"wear_mult": wear_picker, "fuel_mult": fuel_picker, "mandatory_stop": mandatory_stop_toggle,
		"two_compounds": two_compounds_toggle, "refuel": refuel_toggle, "collisions": collisions_toggle,
		"race_control": race_control_toggle, "dynamic_running": dynamic_toggle, "draft": draft_toggle,
		"auto_strategist": strategist_toggle, "parallel": parallel_toggle, "crew": crew_picker,
		"ai_learning": ai_learning_picker, "bot_physics": bot_physics_picker, "player_name": player_name_edit,
		"player_number": player_number_picker, "player_color": player_color_picker, "stripes": player_stripes_toggle,
	}

func _load_race_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(RACE_SETTINGS_PATH) != OK:
		return
	_loading_settings = true
	var controls := _race_setting_controls()
	for key in controls:
		if not cfg.has_section_key("race", key):
			continue
		var v = cfg.get_value("race", key)
		var control: Control = controls[key]
		if control is OptionButton:
			(control as OptionButton).select(clampi(int(v), 0, (control as OptionButton).item_count - 1))
		elif control is SpinBox:
			if control == laps_picker:
				laps_picker.max_value = 200 if TRACK_KEYS[track_picker.selected] == "indy" else 99
			(control as SpinBox).value = float(v)
		elif control is CheckButton:
			(control as CheckButton).button_pressed = bool(v)
		elif control is LineEdit:
			(control as LineEdit).text = str(v)
		elif control is ColorPickerButton and v is Color:
			(control as ColorPickerButton).color = v
	_select_format(format_picker.selected) # visibility only: the saved refuel/wear values stay
	_loading_settings = false
	if world_view and track_picker.selected != 0:
		world_view.set_track(Race.get_track(TRACK_KEYS[track_picker.selected]))

func _save_race_settings() -> void:
	if not is_instance_valid(track_picker):
		return
	var cfg := ConfigFile.new()
	var controls := _race_setting_controls()
	for key in controls:
		var control: Control = controls[key]
		var v
		if control is OptionButton:
			v = (control as OptionButton).selected
		elif control is SpinBox:
			v = (control as SpinBox).value
		elif control is CheckButton:
			v = (control as CheckButton).button_pressed
		elif control is LineEdit:
			v = (control as LineEdit).text
		elif control is ColorPickerButton:
			v = (control as ColorPickerButton).color
		cfg.set_value("race", key, v)
	cfg.save(RACE_SETTINGS_PATH)

func _build_menu_car_preview() -> void:
	var viewport := SubViewport.new()
	viewport.name = "CarShowcaseViewport"
	viewport.size = Vector2i(920, 650)
	viewport.world_3d = World3D.new()
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_PARENT_VISIBLE
	menu_car_viewport = viewport
	add_child(viewport)
	menu_car_preview = _viewport_view(viewport)
	menu_car_preview.name = "MenuCarPreview"
	add_child(menu_car_preview)

	var showcase := Node3D.new()
	showcase.name = "CarShowcase"
	viewport.add_child(showcase)
	var environment := WorldEnvironment.new()
	var environment_data := Environment.new()
	environment_data.background_mode = Environment.BG_CLEAR_COLOR
	environment_data.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment_data.ambient_light_color = Color("#e6dcf2")
	environment_data.ambient_light_energy = 0.6
	environment.environment = environment_data
	showcase.add_child(environment)

	var car = MENU_CAR_SCENE.instantiate()
	car.name = "MenuSeicento"
	car.scale = Vector3(2.3, 1.8, 2.3)
	car.rotation.y = deg_to_rad(-18.0)
	car.car_number = 3
	showcase.add_child(car)
	menu_preview_car = car

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-42, -32, 0)
	key_light.light_color = Color("#fff7e7")
	key_light.light_energy = 1.05
	key_light.shadow_enabled = true
	showcase.add_child(key_light)
	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-18, 145, 0)
	fill_light.light_color = Color("#c9a8ff")
	fill_light.light_energy = 0.55
	showcase.add_child(fill_light)

	var camera := Camera3D.new()
	camera.position = Vector3(8.4, 3.4, -4.2)
	camera.fov = 39
	camera.look_at_from_position(camera.position, Vector3(0, 0.55, 0), Vector3.UP)
	showcase.add_child(camera)
	camera.current = true

	menu_car_rule = ColorRect.new()
	menu_car_rule.anchor_left = 0.045
	menu_car_rule.anchor_top = 0.66
	menu_car_rule.anchor_right = 0.555
	menu_car_rule.anchor_bottom = 0.664
	menu_car_rule.color = Color(CmrStyle.TEXT, 0.85)
	add_child(menu_car_rule)
	menu_car_summary = _label("", 26, INK)
	menu_car_summary.anchor_left = 0.045
	menu_car_summary.anchor_top = 0.675
	menu_car_summary.anchor_right = 0.555
	menu_car_summary.anchor_bottom = 0.79
	menu_car_summary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(menu_car_summary)
	_update_menu_car_summary()

func _update_menu_car_summary() -> void:
	if not is_instance_valid(menu_car_summary) or not is_instance_valid(track_picker):
		return
	var key: String = TRACK_KEYS[track_picker.selected]
	if is_championship_mode:
		key = CHAMPIONSHIP_CALENDAR[_champ_round()]
	var current_track: Track = Race.get_track(key)
	if is_instance_valid(player_color_picker) and is_instance_valid(menu_preview_car):
		menu_preview_car.call("set_paint", player_color_picker.color)
		menu_preview_car.call("set_stripes", player_stripes_toggle.button_pressed)
		menu_preview_car.set("car_number", int(player_number_picker.value))
	var race_label := "%d LAPS" % int(laps_picker.value)
	if format_picker.selected == 1 and not is_championship_mode:
		race_label = "%s ENDURANCE" % _fmt_hours(hours_picker.value).to_upper()
	if is_championship_mode:
		race_label = "ROUND %02d / %02d" % [_champ_round() + 1, CHAMPIONSHIP_CALENDAR.size()]
	menu_car_summary.text = "%s    |    %.1f KM\n%s" % [current_track.name.to_upper(), current_track.L / 1000.0, race_label]

func _build_menu_header() -> void:
	menu_header = HBoxContainer.new()
	menu_header.name = "MenuHeader"
	menu_header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	menu_header.offset_left = 58
	menu_header.offset_top = 52
	menu_header.offset_right = -58
	menu_header.offset_bottom = 100
	menu_header.add_theme_constant_override("separation", 0)
	add_child(menu_header)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 0)
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu_header.add_child(tabs)
	_menu_tab(tabs, "Information", _show_information_page)
	_menu_tab(tabs, "Set Up", _show_setup_page)
	_menu_tab(tabs, "Repair", _show_repair_page)
	_menu_tab(tabs, "Race", _start_race)
	_menu_tab(tabs, "Save", _save_championship)
	_menu_tab(tabs, "Quit", func() -> void: get_tree().quit())

	var player := Label.new()
	player.text = "PLAYER 1  │  YOU"
	player.add_theme_font_size_override("font_size", 21)
	player.add_theme_color_override("font_color", MUTED)
	player.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	menu_header.add_child(player)

## A CMR header tab: plain text, a hairline between tabs, the current page picked out in orange.
func _menu_tab(parent: Control, title: String, callback: Callable) -> void:
	var tab := Button.new()
	tab.text = title
	tab.flat = true
	tab.focus_mode = Control.FOCUS_NONE
	tab.custom_minimum_size = Vector2(0, 46)
	tab.add_theme_font_override("font", CmrStyle.font(250))
	tab.add_theme_font_size_override("font_size", 27)
	tab.add_theme_color_override("font_color", CmrStyle.DIM)
	tab.add_theme_color_override("font_hover_color", CmrStyle.TEXT)
	tab.add_theme_color_override("font_pressed_color", ACCENT)
	var clear := StyleBoxEmpty.new()
	clear.content_margin_left = 12
	clear.content_margin_right = 12
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		tab.add_theme_stylebox_override(st, clear)
	parent.add_child(tab)
	menu_tab_buttons[title] = tab
	if callback.is_valid():
		tab.pressed.connect(callback)
	if title != "Quit":
		var divider := ColorRect.new()
		divider.custom_minimum_size = Vector2(2, 42)
		divider.color = CmrStyle.DIM
		divider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		parent.add_child(divider)
		menu_tab_dividers[title] = divider

func _build_information_page() -> void:
	information_panel = Control.new()
	information_panel.name = "InformationPage"
	information_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	information_panel.offset_left = 70
	information_panel.offset_top = 157
	information_panel.offset_right = -70
	information_panel.offset_bottom = -115
	add_child(information_panel)

	var columns := HBoxContainer.new()
	columns.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	columns.add_theme_constant_override("separation", 28)
	information_panel.add_child(columns)

	var map_column := _column(columns, 14)
	map_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_column.size_flags_stretch_ratio = 4.0
	var map_heading := _label("CIRCUIT MAP", 18, CmrStyle.TEXT)
	map_column.add_child(map_heading)
	var map_frame := PanelContainer.new()
	map_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_frame.size_flags_vertical = Control.SIZE_FILL
	map_frame.custom_minimum_size.y = 480
	var map_style := StyleBoxFlat.new()
	map_style.bg_color = Color("#8a73b0")
	map_style.set_content_margin_all(0)
	map_frame.add_theme_stylebox_override("panel", map_style)
	map_column.add_child(map_frame)
	information_map = MENU_TRACK_ART.new()
	information_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_frame.add_child(information_map)

	var weather_column := _column(columns, 12)
	weather_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	weather_column.size_flags_stretch_ratio = 0.7
	var weather_heading := _label("WEATHER", 18, CmrStyle.TEXT)
	weather_column.add_child(weather_heading)
	for weather in [["sun", "Bright"], ["partly", "Dry"], ["cloud", "Cloudy"], ["drizzle", "Drizzle"], ["rain", "Rain"], ["storm", "Storm"]]:
		var weather_row := HBoxContainer.new()
		weather_row.add_theme_constant_override("separation", 8)
		weather_column.add_child(weather_row)
		var icon: Control = MENU_WEATHER_ICON.new()
		icon.condition = weather[0]
		weather_row.add_child(icon)
		weather_row.add_child(_label(weather[1], 17, CmrStyle.TEXT))

	var temp_bar: Control = MENU_TEMPERATURE_BAR.new()
	temp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_column.add_child(temp_bar)
	var map_description := _label("Track length, race format and changing weather all shape the challenge. Set up your car for the circuit before taking your place on the grid.", 16, CmrStyle.TEXT)
	map_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	map_column.add_child(map_description)

	var detail_spacer := Control.new()
	detail_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_spacer.size_flags_stretch_ratio = 1.55
	columns.add_child(detail_spacer)

	var detail_column := _column(columns, 18)
	detail_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_column.size_flags_stretch_ratio = 2.5
	var card := _panel(Vector2.ZERO)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_column.add_child(card)
	var detail_content := _column(card, 18)
	var cap := _label("NEXT EVENT", 14, ACCENT)
	detail_content.add_child(cap)
	information_title = _label("", 26, CmrStyle.TEXT)
	information_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_content.add_child(information_title)
	var rule := ColorRect.new()
	rule.color = ACCENT
	rule.custom_minimum_size.y = 3
	detail_content.add_child(rule)
	information_facts = _label("", 19, CmrStyle.TEXT)
	information_facts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_content.add_child(information_facts)
	detail_content.add_spacer(false)
	var setup_link := _button("OPEN SET UP  ▸", ACCENT)
	setup_link.pressed.connect(_show_setup_page)
	detail_content.add_child(setup_link)

	_update_information_page()
	information_panel.hide()

func _build_repair_page() -> void:
	repair_panel = Control.new()
	repair_panel.name = "RepairPage"
	repair_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	repair_panel.anchor_left = 0.70
	repair_panel.anchor_top = 0.17
	repair_panel.anchor_right = 0.98
	repair_panel.anchor_bottom = 0.96
	add_child(repair_panel)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 2)
	repair_panel.add_child(column)
	var title := _label("TIME REMAINING", 26, CmrStyle.TEXT)
	column.add_child(title)
	column.add_child(_label("60 minute time allocation", 18, MUTED))
	var time_row := HBoxContainer.new()
	time_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	time_row.add_theme_constant_override("separation", 8)
	column.add_child(time_row)
	var time_left := _label("00:00", 70, CmrStyle.TEXT)
	time_left.add_theme_font_override("font", CmrStyle.digits())
	time_row.add_child(time_left)
	var minutes := _label("(mins)", 21, MUTED)
	minutes.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	time_row.add_child(minutes)
	var pre_list_gap := Control.new()
	pre_list_gap.custom_minimum_size.y = 8
	column.add_child(pre_list_gap)
	_menu_rule(column)

	var parts := ["Gearbox", "Turbo", "Suspension", "Differential", "Brakes", "Body", "Steering", "Electrics", "Exhaust", "Drive Shaft", "Axles"]
	var states := ["ok", "none", "ok", "ok", "ok", "warning", "ok", "none", "none", "ok", "ok"]
	for i in parts.size():
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 40
		row.add_theme_constant_override("separation", 6)
		column.add_child(row)
		var part_button := Button.new()
		part_button.text = "›  " + parts[i]
		part_button.focus_mode = Control.FOCUS_NONE
		part_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		part_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		part_button.custom_minimum_size.y = 36
		part_button.add_theme_font_size_override("font_size", 20)
		part_button.pressed.connect(_select_repair_part.bind(i))
		row.add_child(part_button)
		var status: Control = MENU_REPAIR_STATUS.new()
		status.state = states[i]
		row.add_child(status)
		repair_rows.append(part_button)
		var rule := ColorRect.new()
		rule.custom_minimum_size.y = 2
		column.add_child(rule)
		repair_row_rules.append(rule)
	_select_repair_part(repair_selected)
	repair_panel.hide()

	repair_details = Control.new()
	repair_details.name = "RepairDetails"
	repair_details.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(repair_details)
	var art_frame := PanelContainer.new()
	art_frame.anchor_left = 0.045
	art_frame.anchor_top = 0.54
	art_frame.anchor_right = 0.36
	art_frame.anchor_bottom = 0.72
	var art_style := StyleBoxFlat.new()
	art_style.bg_color = CmrStyle.PAPER
	art_style.set_content_margin_all(0)
	art_frame.add_theme_stylebox_override("panel", art_style)
	repair_details.add_child(art_frame)
	var art: Control = MENU_REPAIR_ART.new()
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art_frame.add_child(art)

	repair_part_name = _label("TURBO", 17, MUTED)
	repair_part_name.anchor_left = 0.38
	repair_part_name.anchor_top = 0.54
	repair_part_name.anchor_right = 0.56
	repair_part_name.anchor_bottom = 0.575
	repair_details.add_child(repair_part_name)
	var replacement_title := _label("Replacement Time", 24, CmrStyle.TEXT)
	replacement_title.anchor_left = 0.38
	replacement_title.anchor_top = 0.58
	replacement_title.anchor_right = 0.57
	replacement_title.anchor_bottom = 0.625
	repair_details.add_child(replacement_title)
	repair_time_label = _label("08:00", 62, CmrStyle.TEXT)
	repair_time_label.add_theme_font_override("font", CmrStyle.digits())
	repair_time_label.anchor_left = 0.38
	repair_time_label.anchor_top = 0.625
	repair_time_label.anchor_right = 0.57
	repair_time_label.anchor_bottom = 0.72
	repair_details.add_child(repair_time_label)

	var damage_bar := TextureRect.new()
	damage_bar.anchor_left = 0.045
	damage_bar.anchor_top = 0.735
	damage_bar.anchor_right = 0.56
	damage_bar.anchor_bottom = 0.765
	damage_bar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	damage_bar.stretch_mode = TextureRect.STRETCH_SCALE
	var damage_gradient := Gradient.new()
	damage_gradient.set_color(0, CmrStyle.VIOLET)
	damage_gradient.add_point(0.45, CmrStyle.PURPLE)
	damage_gradient.add_point(0.72, CmrStyle.ORANGE_SOFT)
	damage_gradient.set_color(1, CmrStyle.ORANGE)
	var damage_texture := GradientTexture2D.new()
	damage_texture.gradient = damage_gradient
	damage_bar.texture = damage_texture
	repair_details.add_child(damage_bar)
	repair_damage_marker = ColorRect.new()
	repair_damage_marker.color = CmrStyle.TEXT
	repair_damage_marker.anchor_left = 0.09
	repair_damage_marker.anchor_top = 0.733
	repair_damage_marker.anchor_right = 0.095
	repair_damage_marker.anchor_bottom = 0.77
	repair_details.add_child(repair_damage_marker)

	var zero := _label("0", 19, CmrStyle.TEXT)
	zero.anchor_left = 0.045
	zero.anchor_top = 0.77
	zero.anchor_right = 0.11
	zero.anchor_bottom = 0.81
	repair_details.add_child(zero)
	var damage_caption := _label("Damage", 19, CmrStyle.TEXT)
	damage_caption.anchor_left = 0.045
	damage_caption.anchor_top = 0.77
	damage_caption.anchor_right = 0.56
	damage_caption.anchor_bottom = 0.81
	damage_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	repair_details.add_child(damage_caption)
	var hundred := _label("100", 19, CmrStyle.TEXT)
	hundred.anchor_left = 0.50
	hundred.anchor_top = 0.77
	hundred.anchor_right = 0.56
	hundred.anchor_bottom = 0.81
	hundred.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	repair_details.add_child(hundred)
	repair_copy = _label("", 18, CmrStyle.TEXT)
	repair_copy.anchor_left = 0.045
	repair_copy.anchor_top = 0.83
	repair_copy.anchor_right = 0.56
	repair_copy.anchor_bottom = 0.96
	repair_copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	repair_details.add_child(repair_copy)
	_select_repair_part(repair_selected)
	repair_details.hide()

func _select_repair_part(index: int) -> void:
	repair_selected = clampi(index, 0, repair_rows.size() - 1)
	var names := ["Gearbox", "Turbo", "Suspension", "Differential", "Brakes", "Body", "Steering", "Electrics", "Exhaust", "Drive Shaft", "Axles"]
	var times := ["00:00", "08:00", "04:00", "05:00", "03:00", "12:00", "04:00", "02:00", "03:00", "05:00", "06:00"]
	var damage := [0.0, 8.0, 0.0, 0.0, 0.0, 64.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var descriptions := [
		"The gearbox is ready for the next event.",
		"Damage to the turbo reduces effective engine power and acceleration.",
		"The suspension is working within its normal range.",
		"The differential is ready for the next event.",
		"The braking system is ready for the next event.",
		"Body damage can affect the car's stability and aerodynamic balance.",
		"The steering system is ready for the next event.",
		"The electrical system is ready for the next event.",
		"The exhaust system is ready for the next event.",
		"The drive shaft is ready for the next event.",
		"The axles are ready for the next event."
	]
	for i in repair_rows.size():
		var style := CmrStyle.box(ACCENT if i == repair_selected else CmrStyle.FIELD_DIM, Color.TRANSPARENT, 14, 4)
		repair_rows[i].add_theme_stylebox_override("normal", style)
		repair_rows[i].add_theme_stylebox_override("hover", style if i == repair_selected else CmrStyle.box(CmrStyle.FIELD, Color.TRANSPARENT, 14, 4))
		repair_row_rules[i].color = Color(0, 0, 0, 0)
	if is_instance_valid(repair_part_name):
		repair_part_name.text = names[repair_selected].to_upper()
		repair_time_label.text = times[repair_selected]
		repair_copy.text = descriptions[repair_selected]
		var marker := lerpf(0.045, 0.56, damage[repair_selected] / 100.0)
		repair_damage_marker.anchor_left = marker
		repair_damage_marker.anchor_right = marker + 0.005

## CMR 2.0-style title screen: a column of slanted bars running in from the left edge, the lit one in
## lime, with the car turning on its showroom stand to the right.
func _build_home_screen() -> void:
	menu_home = Control.new()
	menu_home.name = "MainMenu"
	menu_home.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(menu_home)

	menu_home_art = MENU_TRACK_ART.new()
	menu_home_art.anchor_left = 0.08
	menu_home_art.anchor_top = 0.14
	menu_home_art.anchor_right = 0.92
	menu_home_art.anchor_bottom = 0.75
	menu_home_art.set_track(Race.get_track(TRACK_KEYS[track_picker.selected]))
	menu_home_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_home.add_child(menu_home_art)

	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 58
	top.offset_top = 52
	top.offset_right = -58
	top.offset_bottom = 100
	top.add_theme_constant_override("separation", 0)
	menu_home.add_child(top)
	var title := _label("Main Menu", 27, CmrStyle.TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(title)
	menu_home_clock = _label("00:00.00", 24, MUTED)
	menu_home_clock.add_theme_font_override("font", CmrStyle.digits())
	menu_home_clock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(menu_home_clock)

	# the strip scrolls sideways so the selected word always sits at the same place
	var clip := Control.new()
	clip.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	clip.anchor_top = 0.77
	clip.anchor_bottom = 0.9
	clip.clip_contents = true
	menu_home.add_child(clip)
	menu_home_strip = HBoxContainer.new()
	menu_home_strip.add_theme_constant_override("separation", 0)
	clip.add_child(menu_home_strip)
	for i in FRONT_MENU.size():
		if i > 0:
			var divider := ColorRect.new()
			divider.custom_minimum_size = Vector2(2, 96)
			divider.color = Color(CmrStyle.TEXT, 0.75)
			divider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			menu_home_strip.add_child(divider)
		var item: Dictionary = FRONT_MENU[i]
		var button := Button.new()
		button.text = str(item.word).to_lower()
		button.flat = true
		button.focus_mode = Control.FOCUS_NONE
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 112
		button.add_theme_font_override("font", CmrStyle.font(250))
		button.add_theme_font_size_override("font_size", 82)
		button.add_theme_color_override("font_hover_color", CmrStyle.TEXT)
		var clear := StyleBoxEmpty.new()
		clear.content_margin_left = 22
		clear.content_margin_right = 22
		for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			button.add_theme_stylebox_override(st, clear)
		button.pressed.connect(_home_item_pressed.bind(i))
		menu_home_strip.add_child(button)
	menu_home_strip.size = menu_home_strip.get_combined_minimum_size()

	# the one-line hint under the strip, in CMR's highlight colour
	menu_home_desc = _label("", 18, CmrStyle.ORANGE_SOFT)
	menu_home_desc.anchor_left = 0.16
	menu_home_desc.anchor_top = 0.905
	menu_home_desc.anchor_right = 0.92
	menu_home_desc.anchor_bottom = 0.96
	menu_home_desc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	menu_home.add_child(menu_home_desc)
	get_viewport().size_changed.connect(_layout_home_strip)
	_layout_home_strip.call_deferred()

func _build_options_page() -> void:
	options_panel = _panel(Vector2.ZERO)
	options_panel.anchor_left = 0.19
	options_panel.anchor_right = 0.81
	options_panel.anchor_top = 0.12
	options_panel.anchor_bottom = 0.93
	options_panel.offset_left = 0
	options_panel.offset_right = 0
	options_panel.offset_top = 0
	options_panel.offset_bottom = 0
	add_child(options_panel)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	options_panel.add_child(scroll)
	var column := _column(scroll, 12)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title(column, "OPTIONS", "DISPLAY & GRAPHICS")
	_menu_rule(column)
	_field_label(column, "DISPLAY")
	var display_row := HBoxContainer.new()
	display_row.add_theme_constant_override("separation", 22)
	column.add_child(display_row)
	display_mode_picker = _option_field(display_row, "WINDOW MODE", ["Windowed", "Fullscreen"])
	display_mode_picker.item_selected.connect(_on_display_mode_selected)
	var vsync_column := VBoxContainer.new()
	vsync_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	display_row.add_child(vsync_column)
	_field_label(vsync_column, "FRAME PACING")
	vsync_toggle = _check_field(vsync_column, "Vertical sync", graphics_vsync)
	vsync_toggle.toggled.connect(_on_vsync_toggled)
	ui_scale_picker = _option_field(display_row, "INTERFACE SIZE", ["Small", "Normal", "Large", "Extra large"])
	ui_scale_picker.select(graphics_ui_scale)
	ui_scale_picker.item_selected.connect(_on_ui_scale_selected)
	var frame_row := HBoxContainer.new()
	frame_row.add_theme_constant_override("separation", 22)
	column.add_child(frame_row)
	fps_limit_picker = _option_field(frame_row, "FRAME RATE LIMIT", FPS_LIMITS.map(func(l): return l.name))
	fps_limit_picker.item_selected.connect(_on_fps_limit_selected)
	var frame_note := _label("A lower limit runs cooler and saves battery. The race view is drawn only while it is changing, so menus, pause and results are cheap whatever this is set to.", 14, MUTED)
	frame_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	frame_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame_row.add_child(frame_note)
	frame_note.size_flags_stretch_ratio = 2.0
	_menu_rule(column)
	_field_label(column, "3D UPSCALING")
	var upscaling_row := HBoxContainer.new()
	upscaling_row.add_theme_constant_override("separation", 22)
	column.add_child(upscaling_row)
	upscaler_picker = _option_field(upscaling_row, "UPSCALER", [])
	for i in UPSCALERS.size():
		if _upscaler_available(i):
			upscaler_picker.add_item(UPSCALERS[i].name, i)
	upscaler_picker.item_selected.connect(_on_upscaler_selected)
	upscale_preset_picker = _option_field(upscaling_row, "RENDER RESOLUTION", UPSCALE_PRESETS.map(func(p): return p.name))
	upscale_preset_picker.item_selected.connect(_on_upscale_preset_selected)
	sharpening_picker = _option_field(upscaling_row, "FSR SHARPENING", SHARPENING.map(func(s): return s.name))
	sharpening_picker.item_selected.connect(_on_sharpening_selected)
	var explanation := _label("Upscalers render the 3D scene at a lower resolution, then rebuild it for your display: lower presets run faster with a softer image. The temporal ones (FSR 2, MetalFX Temporal) also replace anti-aliasing, and at 100% act as a high-quality anti-aliaser.", 14, MUTED)
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(explanation)
	var image_row := HBoxContainer.new()
	image_row.add_theme_constant_override("separation", 22)
	column.add_child(image_row)
	antialiasing_picker = _option_field(image_row, "NATIVE ANTI-ALIASING", ["SMAA", "FXAA", "Off"])
	antialiasing_picker.item_selected.connect(_on_antialiasing_selected)
	_grid_spacers(image_row, 2)
	_menu_rule(column)
	_field_label(column, "LIGHTING & REFLECTIONS")
	var effects_row := HBoxContainer.new()
	effects_row.add_theme_constant_override("separation", 22)
	column.add_child(effects_row)
	ssao_toggle = _check_field(effects_row, "Ambient occlusion", graphics_ssao)
	ssao_toggle.toggled.connect(_on_ssao_toggled)
	shadows_toggle = _check_field(effects_row, "Dynamic shadows", graphics_shadows)
	shadows_toggle.toggled.connect(_on_shadows_toggled)
	var reflections_row := HBoxContainer.new()
	reflections_row.add_theme_constant_override("separation", 22)
	column.add_child(reflections_row)
	reflections_picker = _option_field(reflections_row, "REFLECTIONS", ["Off", "Screen-space", "Ray-traced"])
	reflections_picker.item_selected.connect(_on_reflections_selected)
	_grid_spacers(reflections_row, 2)
	var lighting_note := _label("Ray-traced reflections trace the whole circuit and every car on the GPU, so wet tarmac, puddles and paintwork also mirror what's off screen. Godot doesn't expose Metal's ray-tracing hardware yet, so they run in compute shaders. Screen-space reflections are cheaper but only show what's already on screen.", 14, MUTED)
	lighting_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(lighting_note)
	var back := _button("BACK TO MENU", ACCENT)
	back.pressed.connect(_show_home)
	column.add_child(back)
	options_panel.hide()
	upscaler_picker.select(upscaler_picker.get_item_index(graphics_upscaler))
	upscale_preset_picker.select(graphics_upscale_preset)
	sharpening_picker.select(graphics_sharpening)
	antialiasing_picker.select(graphics_antialiasing)
	display_mode_picker.select(graphics_display_mode)
	vsync_toggle.button_pressed = graphics_vsync
	fps_limit_picker.select(graphics_fps_limit)
	ssao_toggle.button_pressed = graphics_ssao
	shadows_toggle.button_pressed = graphics_shadows
	reflections_picker.select(graphics_reflections)
	_apply_upscaling()

func _upscaler_available(index: int) -> bool:
	if not UPSCALERS[index].has("feature"):
		return true
	var rd := RenderingServer.get_rendering_device()
	return rd != null and rd.has_feature(UPSCALERS[index].feature)

func _on_upscaler_selected(item: int) -> void:
	graphics_upscaler = upscaler_picker.get_item_id(item)
	_apply_upscaling()
	_save_graphics_settings()

func _on_upscale_preset_selected(index: int) -> void:
	graphics_upscale_preset = index
	_apply_upscaling()
	_save_graphics_settings()

func _on_sharpening_selected(index: int) -> void:
	graphics_sharpening = index
	_apply_upscaling()
	_save_graphics_settings()

func _apply_upscaling() -> void:
	if not is_instance_valid(render_viewport):
		return
	var mode: int = UPSCALERS[graphics_upscaler].mode
	render_viewport.scaling_3d_mode = mode
	render_viewport.scaling_3d_scale = 1.0 if graphics_upscaler == 0 else UPSCALE_PRESETS[graphics_upscale_preset].scale
	render_viewport.fsr_sharpness = SHARPENING[graphics_sharpening].value
	if is_instance_valid(world_view):
		world_view.apply_graphics(world_view.quality) # MSAA depends on the upscaler
	if is_instance_valid(upscale_preset_picker):
		upscale_preset_picker.disabled = graphics_upscaler == 0
		sharpening_picker.disabled = mode not in [Viewport.SCALING_3D_MODE_FSR, Viewport.SCALING_3D_MODE_FSR2]
	_apply_antialiasing()

func _on_display_mode_selected(index: int) -> void:
	graphics_display_mode = index
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if index == 1 else DisplayServer.WINDOW_MODE_WINDOWED)
	_save_graphics_settings()

## The interface follows the window size on its own; this scales it further on top.
func _on_ui_scale_selected(index: int) -> void:
	graphics_ui_scale = clampi(index, 0, UI_SCALES.size() - 1)
	get_window().content_scale_factor = UI_SCALES[graphics_ui_scale]
	_save_graphics_settings()

func _on_vsync_toggled(enabled: bool) -> void:
	graphics_vsync = enabled
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if enabled else DisplayServer.VSYNC_DISABLED)
	_save_graphics_settings()

func _on_fps_limit_selected(index: int) -> void:
	graphics_fps_limit = index
	_save_graphics_settings()

func _on_antialiasing_selected(index: int) -> void:
	graphics_antialiasing = index
	_apply_antialiasing()
	_save_graphics_settings()

func _apply_antialiasing() -> void:
	if not is_instance_valid(render_viewport):
		return
	# temporal upscalers anti-alias the image themselves
	var temporal := render_viewport.scaling_3d_mode in [Viewport.SCALING_3D_MODE_FSR2, Viewport.SCALING_3D_MODE_METALFX_TEMPORAL]
	if is_instance_valid(antialiasing_picker):
		antialiasing_picker.disabled = temporal
	if temporal:
		render_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		return
	match graphics_antialiasing:
		0: render_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA
		1: render_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		_: render_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED

func _on_reflections_selected(index: int) -> void:
	graphics_reflections = index
	_apply_world_graphics_settings()
	_save_graphics_settings()

func _on_ssao_toggled(enabled: bool) -> void:
	graphics_ssao = enabled
	_apply_world_graphics_settings()
	_save_graphics_settings()

func _on_shadows_toggled(enabled: bool) -> void:
	graphics_shadows = enabled
	_apply_world_graphics_settings()
	_save_graphics_settings()

func _apply_world_graphics_settings() -> void:
	if not is_instance_valid(world_view):
		return
	var environment := world_view.get("world_environment") as Environment
	if environment:
		environment.ssao_enabled = graphics_ssao
		environment.ssr_enabled = graphics_reflections == 1
	var ray_tracing := world_view.get("ray_tracing") as RayTracing
	if ray_tracing:
		ray_tracing.enabled = graphics_reflections == 2
	var sun := world_view.get("sun") as DirectionalLight3D
	if sun:
		sun.shadow_enabled = graphics_shadows

func _load_graphics_settings() -> void:
	var config := ConfigFile.new()
	if config.load("user://graphics.cfg") == OK:
		graphics_display_mode = clampi(int(config.get_value("graphics", "display_mode", 0)), 0, 1)
		graphics_antialiasing = clampi(int(config.get_value("graphics", "antialiasing", 0)), 0, 2)
		graphics_vsync = bool(config.get_value("graphics", "vsync", true))
		graphics_fps_limit = clampi(int(config.get_value("graphics", "fps_limit", graphics_fps_limit)), 0, FPS_LIMITS.size() - 1)
		# older versions stored an SSR on/off switch
		var reflections = config.get_value("graphics", "reflections", 0)
		graphics_reflections = (1 if reflections else 0) if reflections is bool else int(reflections)
		graphics_reflections = clampi(graphics_reflections, 0, 2)
		graphics_ssao = bool(config.get_value("graphics", "ssao", true))
		graphics_shadows = bool(config.get_value("graphics", "shadows", true))
		if config.has_section_key("graphics", "upscaler"):
			graphics_upscaler = clampi(int(config.get_value("graphics", "upscaler", 0)), 0, UPSCALERS.size() - 1)
			graphics_upscale_preset = clampi(int(config.get_value("graphics", "upscale_preset", 1)), 0, UPSCALE_PRESETS.size() - 1)
			graphics_sharpening = clampi(int(config.get_value("graphics", "sharpening", 2)), 0, SHARPENING.size() - 1)
		else:
			# older versions: render_scale 0 native, then FSR 2 at Quality, Balanced or Performance
			var scale_index := clampi(int(config.get_value("graphics", "render_scale", 0)), 0, 3)
			graphics_upscaler = 2 if scale_index > 0 else 0
			graphics_upscale_preset = maxi(scale_index, 1)
		graphics_ui_scale = clampi(int(config.get_value("graphics", "ui_scale", 1)), 0, UI_SCALES.size() - 1)
	if not _upscaler_available(graphics_upscaler):
		graphics_upscaler = 0
	get_window().content_scale_factor = UI_SCALES[graphics_ui_scale]
	if graphics_display_mode == 1:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if graphics_vsync else DisplayServer.VSYNC_DISABLED)
	_apply_upscaling()

func _save_graphics_settings() -> void:
	var config := ConfigFile.new()
	config.load("user://graphics.cfg")
	if config.has_section_key("graphics", "render_scale"):
		config.erase_section_key("graphics", "render_scale")
	config.set_value("graphics", "upscaler", graphics_upscaler)
	config.set_value("graphics", "upscale_preset", graphics_upscale_preset)
	config.set_value("graphics", "sharpening", graphics_sharpening)
	config.set_value("graphics", "display_mode", graphics_display_mode)
	config.set_value("graphics", "antialiasing", graphics_antialiasing)
	config.set_value("graphics", "vsync", graphics_vsync)
	config.set_value("graphics", "fps_limit", graphics_fps_limit)
	config.set_value("graphics", "reflections", graphics_reflections)
	config.set_value("graphics", "ssao", graphics_ssao)
	config.set_value("graphics", "shadows", graphics_shadows)
	config.set_value("graphics", "ui_scale", graphics_ui_scale)
	config.save("user://graphics.cfg")

func _layout_home_strip() -> void:
	_home_select(home_menu_index, false)

func _home_select(index: int, animate := true) -> void:
	home_menu_index = posmod(index, FRONT_MENU.size())
	if not is_instance_valid(menu_home_strip) or menu_home_strip.get_child_count() == 0:
		return
	for i in FRONT_MENU.size():
		var button: Button = menu_home_strip.get_child(i * 2)
		button.add_theme_color_override("font_color", ACCENT if i == home_menu_index else CmrStyle.DIM)
	menu_home_desc.text = "%s        ◂  ▸  browse     enter  select" % FRONT_MENU[home_menu_index].desc
	var selected: Control = menu_home_strip.get_child(home_menu_index * 2)
	var target_x := get_viewport_rect().size.x * 0.16 - selected.position.x
	if home_tween and home_tween.is_running():
		home_tween.kill()
	if animate:
		home_tween = create_tween()
		home_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		home_tween.tween_property(menu_home_strip, "position:x", target_x, 0.32)
	else:
		menu_home_strip.position.x = target_x

func _home_item_pressed(index: int) -> void:
	if index != home_menu_index:
		_home_select(index)
		return
	_activate_home_item()

func _activate_home_item() -> void:
	match FRONT_MENU[home_menu_index].id:
		"drivers":
			_set_championship_mode(false)
			_show_setup_page()
		"arcade":
			_set_championship_mode(true)
			_show_setup_page()
		"rally":
			_set_championship_mode(false)
			_set_race_format(0)
			_show_setup_page()
		"options":
			_show_options_page()
		"quit":
			get_tree().quit()

func _scroll_to_control(control: Control) -> void:
	if is_instance_valid(control) and is_instance_valid(menu_scroll):
		menu_scroll.ensure_control_visible(control)

func _select_menu_tab(title: String) -> void:
	menu_tab_index = maxi(0, TOP_MENU_TABS.find(title))
	for tab_name in TOP_MENU_TABS:
		var button: Button = menu_tab_buttons[tab_name]
		button.add_theme_color_override("font_color", ACCENT if tab_name == title else CmrStyle.DIM)

func _show_home() -> void:
	active_menu_page = "home"
	_hide_pages()
	menu_home.show()
	menu_tint.color = CmrStyle.TINT_HOME
	if is_instance_valid(menu_home_art):
		menu_home_art.set_track(Race.get_track(TRACK_KEYS[track_picker.selected]))
	_home_select(home_menu_index, false)

## Hide every front-end page, leaving just the backdrop.
func _hide_pages() -> void:
	for page in [menu_home, menu_header, setup_panel, repair_panel, repair_details, options_panel, information_panel,
			menu_car_preview, menu_car_summary, menu_car_rule]:
		page.hide()
	menu_tint.show()

func _place_car_preview(left: float, top: float, right: float, bottom: float) -> void:
	menu_car_preview.anchor_left = left
	menu_car_preview.anchor_top = top
	menu_car_preview.anchor_right = right
	menu_car_preview.anchor_bottom = bottom
	menu_car_preview.offset_left = 0
	menu_car_preview.offset_top = 0
	menu_car_preview.offset_right = 0
	menu_car_preview.offset_bottom = 0

func _show_options_page() -> void:
	active_menu_page = "options"
	_hide_pages()
	options_panel.show()
	menu_tint.color = CmrStyle.TINT_OPTIONS

func _show_information_page() -> void:
	active_menu_page = "information"
	_hide_pages()
	information_panel.show()
	menu_header.show()
	menu_tint.color = CmrStyle.TINT_INFO
	_select_menu_tab("Information")
	_update_information_page()

func _show_setup_page() -> void:
	active_menu_page = "setup"
	_hide_pages()
	_place_car_preview(0.045, 0.12, 0.555, 0.64)
	menu_car_preview.show()
	menu_car_summary.show()
	menu_car_rule.show()
	setup_panel.show()
	menu_header.show()
	menu_tint.color = CmrStyle.TINT_SETUP
	_select_menu_tab("Set Up")
	menu_scroll.scroll_vertical = 0
	_update_menu_car_summary()

func _show_repair_page() -> void:
	active_menu_page = "repair"
	_hide_pages()
	_place_car_preview(0.045, 0.12, 0.555, 0.53)
	menu_car_preview.show()
	repair_panel.show()
	repair_details.show()
	menu_header.show()
	menu_tint.color = CmrStyle.TINT_REPAIR
	_select_menu_tab("Repair")

func _set_championship_mode(value: bool) -> void:
	if is_championship_mode != value:
		_toggle_mode()

func _set_race_format(index: int) -> void:
	if format_picker.selected != index:
		format_picker.select(index)
		_select_format(index)
	_update_menu_car_summary()

func _update_information_page() -> void:
	if not is_instance_valid(information_panel):
		return
	var track_key: String = TRACK_KEYS[track_picker.selected]
	var race_length := ""
	if is_championship_mode:
		var round_idx: int = _champ_round()
		track_key = CHAMPIONSHIP_CALENDAR[round_idx]
		race_length = "Round %d of %d" % [round_idx + 1, CHAMPIONSHIP_CALENDAR.size()]
	elif format_picker.selected == 1:
		race_length = "Timed race · %s" % _fmt_hours(hours_picker.value)
	else:
		race_length = "%d laps" % int(laps_picker.value)
	var current_track: Track = Race.get_track(track_key)
	information_title.text = current_track.name
	var weather_options: Array[String] = ["Dry", "Wet", "Variable"]
	var weather_name: String = weather_options[weather_picker.selected]
	information_facts.text = "Circuit length   %.1f km\n\n%s\nStart time   %s\nWeather   %s\nOpponents   %d" % [
		current_track.L / 1000.0,
		race_length,
		_format_start_time(start_hour_picker.value),
		weather_name,
		int(opponents_picker.value)
	]
	if information_map.has_method("set_track"):
		information_map.set_track(current_track, true)
	if is_instance_valid(menu_home_art) and not is_championship_mode:
		menu_home_art.set_track(current_track)

func _format_start_time(hour: float) -> String:
	var hours := int(floorf(hour))
	var minutes := int(roundf((hour - hours) * 60.0))
	if minutes == 60:
		hours = (hours + 1) % 24
		minutes = 0
	return "%02d:%02d" % [hours % 24, minutes]

func _build_hud() -> void:
	hud = RaceHud.new()
	hud.name = "RaceHud"
	add_child(hud)
	hud.hide()
	_build_pause_menu()

func _build_pause_menu() -> void:
	pause_panel = _sheet(Vector2(380, 0))
	pause_panel.anchor_left = 0.5
	pause_panel.anchor_right = 0.5
	pause_panel.anchor_top = 0.5
	pause_panel.anchor_bottom = 0.5
	pause_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pause_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(pause_panel)
	var col := _column(pause_panel, 10)
	var title := _label("PAUSED", 28, INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	for spec in [["RESUME", "resume"], ["RESTART RACE", "restart"], ["RETIRE & SEE RESULTS", "retire"], ["QUIT TO MENU", "menu"]]:
		var b := _button(spec[0], ACCENT if spec[1] == "resume" else CmrStyle.FIELD)
		b.custom_minimum_size = Vector2(340, 44)
		b.pressed.connect(_pause_action.bind(spec[1]))
		col.add_child(b)
		pause_buttons.append(b)
	pause_panel.hide()

func _set_paused(on: bool) -> void:
	if not race or skipping or race.phase == "finished":
		return
	paused = on
	pause_panel.visible = on
	if on:
		if is_instance_valid(audio):
			audio.update_car(race.player, false)
		pause_buttons[0].grab_focus()
	else:
		get_viewport().gui_release_focus()

func _pause_action(act: String) -> void:
	match act:
		"resume":
			_set_paused(false)
		"restart":
			_set_paused(false)
			_commit_brain()
			_start_race()
		"retire":
			_set_paused(false)
			race.player.dnf = true
			race.player.dnf_reason = "Retired"
			_begin_skip()
		"menu":
			_quit_race()

func _commit_brain() -> void:
	if race and race.brain:
		race.brain.commit()

func _notification(what: int) -> void:
	# keep what the bots learned if the window is closed mid-race
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_commit_brain()
		_save_race_settings()
	# leaving the window stops the race and drops the frame rate instead of burning battery unseen
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_app_focused = false
		_set_paused(true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_app_focused = true

func _build_results() -> void:
	result_panel = _sheet(Vector2(1120, 820))
	result_panel.set_anchors_preset(Control.PRESET_CENTER)
	result_panel.position = Vector2(-560, -410)
	add_child(result_panel)
	result_scroll = ScrollContainer.new()
	result_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	result_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	result_panel.add_child(result_scroll)
	result_panel.hide()

func _start_race() -> void:
	status_label.text = "Configuring car and optimizing race strategy..."
	status_label.modulate = ACCENT
	await get_tree().process_frame

	if _strategy_pending and not is_championship_mode:
		status_label.text = "The strategist is still working out the plans — try again in a moment."
		return
	var settings := RaceSettings.new()
	var plan = current_plan
	if is_championship_mode:
		if _next_round() >= CHAMPIONSHIP_CALENDAR.size():
			champ_data = {"round": 0, "scored": false, "table": {}}
		if champ_data.get("scored", false):
			champ_data["round"] = int(champ_data.get("round", 0)) + 1
			champ_data["scored"] = false
		_save_championship()
		var t_key: String = CHAMPIONSHIP_CALENDAR[int(champ_data.get("round", 0))]
		settings.track = t_key
		var defaults: Dictionary = TRACK_DEFAULTS.get(t_key, {"laps": 6, "wear": 2.0})
		settings.laps = defaults.laps
		settings.wear_mult = defaults.wear
		settings.format = "laps"
		# every round is planned by the strategist for that circuit's race length and tyre wear
		var options := strategy.plan(_plan_opts(Race.get_track(t_key), defaults.laps, defaults.wear))
		plan = options[0] if options.size() else null
	else:
		settings.track = TRACK_KEYS[track_picker.selected]
		settings.laps = int(laps_picker.value)
		settings.format = "time" if format_picker.selected == 1 else "laps"
		settings.hours = hours_picker.value
	settings.start_hour = start_hour_picker.value

	settings.opponents = int(opponents_picker.value)
	settings.difficulty = ["easy", "medium", "hard", "alien"][difficulty_picker.selected]
	settings.weather = ["dry", "wet", "variable"][weather_picker.selected]
	settings.gearbox = "manual" if gearbox_picker.selected == 1 else "auto"
	settings.player_name = player_name_edit.text.strip_edges() if not player_name_edit.text.strip_edges().is_empty() else "You"
	settings.player_number = int(player_number_picker.value)
	settings.player_color = player_color_picker.color
	settings.stripes = player_stripes_toggle.button_pressed
	settings.ai_learning = "off" if ai_learning_picker.selected == 1 else "on"
	settings.bot_physics = "off" if bot_physics_picker.selected == 1 else "on"
	settings.grid = ["pole", "middle", "back", "random"][grid_picker.selected]
	settings.assists = ["full", "abs", "off"][assists_picker.selected]
	if not is_championship_mode:
		settings.wear_mult = wear_picker.value
	settings.fuel_mult = fuel_picker.value
	settings.mandatory_stop = mandatory_stop_toggle.button_pressed
	settings.two_compounds = two_compounds_toggle.button_pressed
	settings.refuel = refuel_toggle.button_pressed
	settings.collisions = collisions_toggle.button_pressed
	settings.race_control = race_control_toggle.button_pressed
	settings.dynamic_running = dynamic_toggle.button_pressed
	settings.draft = draft_toggle.button_pressed
	settings.auto_strategist = strategist_toggle.button_pressed
	settings.parallel = parallel_toggle.button_pressed
	settings.crew = ["pro", "club", "amateur"][crew_picker.selected]

	if plan == null:
		status_label.text = "No valid pit strategy for these settings — pick a plan or fix the custom one."
		status_label.modulate = DANGER
		return
	_save_race_settings()
	race = Race.new(settings, (plan as Dictionary).duplicate(true), -1, {"car_model": car_model, "tyres": tyre_model, "strategy": strategy})
	world_view.set_race(race)

	accumulator = 0.0
	warp_index = 0
	race.warp = 1
	gamepad_active = false
	gamepad_device = -1
	paused = false
	skipping = false
	throttle = 0.0
	brake = 0.0
	steer = 0.0
	shift_up = false
	shift_down = false

	setup_panel.hide()
	repair_panel.hide()
	repair_details.hide()
	options_panel.hide()
	information_panel.hide()
	menu_car_preview.hide()
	menu_car_summary.hide()
	menu_car_rule.hide()
	menu_home.hide()
	menu_tint.hide()
	menu_header.hide()
	result_panel.hide()
	pause_panel.hide()
	get_viewport().gui_release_focus()
	hud.start(race, world_view, audio)
	status_label.text = ""

	if is_instance_valid(audio):
		audio.beep(880.0, 3)

func _show_results() -> void:
	hud.hide()
	pause_panel.hide()
	if is_instance_valid(audio):
		audio.update_car(race.player, false)
	result_panel.show()
	for child in result_scroll.get_children():
		child.queue_free()

	var col := _column(result_scroll, 8)
	col.custom_minimum_size.x = 1060
	var rows := race.results()
	var me: Dictionary = rows[0]
	for r in rows:
		if r.car.is_player:
			me = r
	var fast = race.fastest
	var title := "DNF — %s" % me.car.dnf_reason if me.car.dnf else "P%d OF %d" % [me.pos, rows.size()]
	var laps: int = race.winner.finish_lap if race.winner else race.R
	var sub := "%s · %s%d laps · %s" % [race.track.name, ("%s · " % _fmt_hours(race.duration / 3600.0)) if race.timed else "", laps,
		{"dry": "Dry", "wet": "Wet", "variable": "Variable weather"}.get(race.s.weather, "Dry")]
	if fast:
		sub += " · Fastest lap %s %s" % [fast.car.name, Race.fmt_time(fast.t)]
	col.add_child(_label("CHEQUERED FLAG · %s" % title, 26, INK))
	var sub_label := _label(sub, 13, MUTED)
	sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(sub_label)
	if race.brain:
		var learned := race.brain.progress().filter(func(x): return x.gain > 0.05)
		if not learned.is_empty():
			var parts := []
			for x in learned.slice(0, 3):
				parts.append("%s −%.1f s/lap" % [Brain.short(x.car), x.gain])
			var more := " and %d more" % (learned.size() - 3) if learned.size() > 3 else ""
			var ai := _label("The field learned from you: %s%s." % [", ".join(parts), more], 13, CmrStyle.VIOLET)
			ai.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			col.add_child(ai)

	var is_champ := is_championship_mode
	if is_champ:
		_score_championship_round(rows)
	var headers := ["POS", "NO.", "DRIVER", "LAPS", "TIME / GAP", "BEST LAP", "STOPS", "TYRES"]
	var widths := [46, 44, 250, 50, 210, 100, 56, 120]
	if is_champ:
		headers.append("PTS")
		widths.append(46)
	# classification as CMR-style slanted bars: a dark header strip, light rows, the player's in lime
	var table := VBoxContainer.new()
	table.add_theme_constant_override("separation", 3)
	col.add_child(table)
	table.add_child(_result_row(headers, widths, CmrStyle.box(Color(0, 0, 0, 0.25), Color.TRANSPARENT, 14, 3), CmrStyle.ORANGE_SOFT, 12))
	for r in rows:
		var car: RaceCar = r.car
		var time_txt: String = Race.fmt_time(r.total) if r.pos == 1 and r.total != null else (r.gap if r.gap != "" else ("" if r.status != "" else "—"))
		if r.status != "":
			time_txt = (time_txt + "  " if time_txt != "" else "") + r.status
		for pen in car.penalties:
			time_txt += "  +%d s %s" % [roundi(pen[1]), pen[0]]
		var tyres := ""
		for c in car.history:
			tyres += ("→" if tyres != "" else "") + str(c)
		var cells := ["DNF" if car.dnf else str(r.pos), str(car.number), car.name, str(r.laps), time_txt,
			Race.fmt_time(car.best_lap), str(car.stops), tyres]
		if is_champ:
			cells.append("+%d" % _round_points(r))
		var fill: Color = CmrStyle.ORANGE if car.is_player else (CmrStyle.FIELD if r.pos % 2 == 1 else CmrStyle.FIELD_DIM)
		var row := _result_row(cells, widths, CmrStyle.box(fill, Color.TRANSPARENT, 14, 3), CmrStyle.INK, 15, car.color)
		if fast and fast.car == car:
			(row.get_child(0).get_child(5) as Label).add_theme_color_override("font_color", Color("#6a1fc0"))
		table.add_child(row)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	var primary: Button
	if is_champ:
		_render_championship_standings(col)
		var last := int(champ_data.get("round", 0)) >= CHAMPIONSHIP_CALENDAR.size() - 1
		if last:
			primary = _button("FINISH CHAMPIONSHIP", ACCENT)
			primary.pressed.connect(_return_to_setup)
		else:
			var next_name: String = Race.get_track(CHAMPIONSHIP_CALENDAR[int(champ_data.get("round", 0)) + 1]).name
			primary = _button("NEXT ROUND: %s ▸" % next_name.to_upper(), ACCENT)
			primary.pressed.connect(_start_race)
	else:
		primary = _button("RACE AGAIN", ACCENT)
		primary.pressed.connect(_start_race)
	primary.custom_minimum_size.y = 44
	buttons.add_child(primary)
	var back := _button("BACK TO MENU", CmrStyle.FIELD)
	back.custom_minimum_size.y = 44
	back.pressed.connect(_return_to_setup)
	buttons.add_child(back)
	col.add_child(buttons)
	primary.grab_focus()

## One classification line: fixed-width cells in a slanted bar, with an optional car-colour swatch
## before the driver's name (cell 2).
func _result_row(cells: Array, widths: Array, style: StyleBox, ink: Color, font_size: int, swatch = null) -> PanelContainer:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", style)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	bar.add_child(line)
	for k in cells.size():
		var l := _label(str(cells[k]), font_size, ink)
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
		l.custom_minimum_size.x = widths[k]
		l.clip_text = true
		if k == 2 and swatch != null:
			var name_row := HBoxContainer.new()
			name_row.custom_minimum_size.x = widths[k]
			var sw := ColorRect.new()
			sw.color = swatch
			sw.custom_minimum_size = Vector2(6, 16)
			sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			name_row.add_child(sw)
			l.custom_minimum_size.x = widths[k] - 12
			name_row.add_child(l)
			line.add_child(name_row)
			continue
		line.add_child(l)
	return bar

static func _fmt_hours(h: float) -> String:
	if h < 1.0:
		return "%d min" % roundi(h * 60.0)
	var q := snappedf(h, 0.25)
	return "%d h" % int(q) if q == floorf(q) else "%s h" % q

func _round_points(r: Dictionary) -> int:
	if r.car.dnf or r.pos > CHAMPIONSHIP_POINTS.size():
		return 0
	return CHAMPIONSHIP_POINTS[r.pos - 1]

func _sorted_standings() -> Array:
	var list: Array = champ_data.get("table", {}).values()
	list.sort_custom(func(a, b):
		if a.points != b.points:
			return a.points > b.points
		if a.wins != b.wins:
			return a.wins > b.wins
		return int(a.get("id", 0)) < int(b.get("id", 0))
	)
	return list

func _render_championship_standings(col: VBoxContainer) -> void:
	var list := _sorted_standings()
	var round_idx := int(champ_data.get("round", 0))
	var heading := "STANDINGS AFTER ROUND %d OF %d" % [round_idx + 1, CHAMPIONSHIP_CALENDAR.size()]
	if round_idx >= CHAMPIONSHIP_CALENDAR.size() - 1 and not list.is_empty():
		heading = "YOU ARE THE CHAMPION!" if list[0].get("is_player", false) else "CHAMPION: %s" % str(list[0].name).to_upper()
	var div := _label(heading, 16, ACCENT)
	div.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(div)
	var table := VBoxContainer.new()
	table.add_theme_constant_override("separation", 3)
	col.add_child(table)
	var widths := [46, 44, 250, 60, 70]
	table.add_child(_result_row(["POS", "NO.", "DRIVER", "WINS", "POINTS"], widths, CmrStyle.box(Color(0, 0, 0, 0.25), Color.TRANSPARENT, 14, 3), CmrStyle.ORANGE_SOFT, 12))
	for i in list.size():
		var e: Dictionary = list[i]
		var fill: Color = CmrStyle.ORANGE if e.get("is_player", false) else (CmrStyle.FIELD if i % 2 == 0 else CmrStyle.FIELD_DIM)
		table.add_child(_result_row([str(i + 1), str(int(e.get("number", 0))), str(e.name), str(int(e.wins)), str(int(e.points))],
			widths, CmrStyle.box(fill, Color.TRANSPARENT, 14, 3), CmrStyle.INK, 15))

## Scores a round once, however many times its results are shown. No points for a DNF.
func _score_championship_round(results: Array) -> void:
	if champ_data.get("scored", false):
		return
	champ_data["scored"] = true
	if not champ_data.has("table"):
		champ_data["table"] = {}
	var table: Dictionary = champ_data["table"]
	for row in results:
		var car: RaceCar = row.car
		var cid: String = str(car.id)
		var entry: Dictionary = table.get(cid, {"points": 0, "wins": 0})
		entry.merge({"id": car.id, "name": car.name, "number": car.number, "color": car.color.to_html(false), "is_player": car.is_player}, true)
		entry.points = int(entry.points) + _round_points(row)
		if row.pos == 1 and not car.dnf:
			entry.wins = int(entry.wins) + 1
		table[cid] = entry
	_save_championship()

## The championship round to drive next: a round whose results were already seen is done.
func _next_round() -> int:
	var r := int(champ_data.get("round", 0))
	return r + 1 if champ_data.get("scored", false) else r

## The round the menus show (a finished championship shows its last round).
func _champ_round() -> int:
	return mini(_next_round(), CHAMPIONSHIP_CALENDAR.size() - 1)

func _return_to_setup() -> void:
	_commit_brain()
	race = null
	paused = false
	skipping = false
	hud.hide()
	pause_panel.hide()
	get_viewport().gui_release_focus()
	if is_instance_valid(audio):
		audio.update_car(null, false)
	status_label.text = ""
	status_label.modulate = MUTED
	result_panel.hide()
	_show_setup_page()
	_update_championship_view()
	_update_ai_memory()

	var t_key: String = CHAMPIONSHIP_CALENDAR[_champ_round()] if is_championship_mode else TRACK_KEYS[track_picker.selected]
	world_view.set_track(Race.get_track(t_key))

func _select_track(index: int) -> void:
	var key: String = TRACK_KEYS[index]
	laps_picker.max_value = 200 if key == "indy" else 99
	if not _loading_settings:
		# e.g. a 20.7 km Nordschleife lap needs a shorter race and gentler tyre wear
		var defaults: Dictionary = TRACK_DEFAULTS.get(key, {"laps": 6, "wear": 2.0})
		_loading_settings = true
		laps_picker.value = defaults.laps
		wear_picker.value = defaults.wear
		_loading_settings = false
	if world_view and not is_championship_mode:
		world_view.set_track(Race.get_track(key))
	_update_information_page()
	_update_menu_car_summary()
	_update_ai_memory()
	_queue_strategy_refresh()

func _toggle_mode() -> void:
	is_championship_mode = not is_championship_mode
	mode_button.text = "CHAMPIONSHIP · 8 ROUNDS" if is_championship_mode else "SINGLE RACE"
	track_picker.visible = not is_championship_mode
	track_label.visible = not is_championship_mode
	laps_picker.get_parent().visible = not is_championship_mode and format_picker.selected == 0
	format_picker.get_parent().visible = not is_championship_mode
	hours_picker.get_parent().visible = not is_championship_mode and format_picker.selected == 1
	strategy_section.visible = not is_championship_mode
	_update_championship_view()
	_update_information_page()
	_update_menu_car_summary()
	_update_ai_memory()

	var t_key: String = CHAMPIONSHIP_CALENDAR[_champ_round()] if is_championship_mode else TRACK_KEYS[track_picker.selected]
	world_view.set_track(Race.get_track(t_key))

func _update_championship_view() -> void:
	var table: Dictionary = champ_data.get("table", {})
	var saved := not table.is_empty() or int(champ_data.get("round", 0)) > 0
	if is_instance_valid(champ_reset_button):
		champ_reset_button.visible = is_championship_mode and saved
	if is_championship_mode:
		var points := "-".join(CHAMPIONSHIP_POINTS.map(func(x): return str(x)))
		var info := "%d rounds, one on each circuit, %s points. Race length and tyre wear are set per circuit." % [CHAMPIONSHIP_CALENDAR.size(), points]
		var nxt := _next_round()
		if saved and nxt < CHAMPIONSHIP_CALENDAR.size():
			info += " Saved championship: next is round %d, %s." % [nxt + 1, Race.get_track(CHAMPIONSHIP_CALENDAR[nxt]).name]
		elif saved:
			info += " The last championship is complete — racing again starts a new one."
		champ_info_label.text = info
		champ_info_label.show()
		_render_champ_side(nxt if saved else 0)
		champ_side.show()
	else:
		champ_info_label.text = "Single race on selected track with custom options."
		champ_info_label.hide()
		champ_side.hide()

## Calendar with progress (done / next) and the saved standings, like the reference's side panel.
func _render_champ_side(done: int) -> void:
	for child in champ_calendar.get_children() + champ_table.get_children():
		child.queue_free()
	var ink := CmrStyle.TEXT
	for i in CHAMPIONSHIP_CALENDAR.size():
		var is_next := i == done
		var color := MUTED if i < done else (ACCENT if is_next else ink)
		champ_calendar.add_child(_label(str(i + 1), 13, color))
		var name := _label(Race.get_track(CHAMPIONSHIP_CALENDAR[i]).name, 13, color)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		champ_calendar.add_child(name)
		champ_calendar.add_child(_label("✓" if i < done else ("NEXT" if is_next else ""), 12, CmrStyle.GREEN if i < done else ACCENT))
	var table := _sorted_standings()
	if table.is_empty():
		var none := _label("No rounds driven yet.", 13, MUTED)
		champ_table.add_child(none)
		for k in 3:
			champ_table.add_child(Control.new())
		return
	for i in table.size():
		var e: Dictionary = table[i]
		var color := ACCENT if e.get("is_player", false) else ink
		champ_table.add_child(_label(str(i + 1), 13, color))
		var swatch := ColorRect.new()
		swatch.color = Color.html(str(e.get("color", "#888888")))
		swatch.custom_minimum_size = Vector2(12, 12)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		champ_table.add_child(swatch)
		var name := _label(str(e.get("name", "?")), 13, color)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if e.get("is_player", false):
			name.add_theme_font_size_override("font_size", 14)
		champ_table.add_child(name)
		champ_table.add_child(_label("%d" % int(e.points), 13, color))

func _reset_championship() -> void:
	champ_data = {"round": 0, "scored": false, "table": {}}
	_save_championship()
	_update_championship_view()
	_update_information_page()
	_update_menu_car_summary()

func _load_championship() -> void:
	champ_data = {"round": 0, "scored": false, "table": {}}
	if not FileAccess.file_exists("user://championship.json"):
		return
	var f := FileAccess.open("user://championship.json", FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary) or not (parsed.get("table", {}) is Dictionary):
		return
	var saved_round := int(parsed.get("round", -1))
	if saved_round < 0 or saved_round >= CHAMPIONSHIP_CALENDAR.size():
		return
	champ_data = parsed
	champ_data["round"] = saved_round
	champ_data["scored"] = bool(parsed.get("scored", false))

func _save_championship() -> void:
	var f := FileAccess.open("user://championship.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(champ_data))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventJoypadMotion:
		if race:
			gamepad_device = event.device
			if (event.axis == JOY_AXIS_LEFT_X and absf(event.axis_value) > 0.12) or (event.axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT] and event.axis_value > 0.05):
				gamepad_active = true
		return
	if event is InputEventJoypadButton:
		gamepad_device = event.device
		if not event.pressed:
			return
		if not race:
			if active_menu_page == "home":
				match event.button_index:
					JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_UP: _home_select(home_menu_index - 1)
					JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_DOWN: _home_select(home_menu_index + 1)
					JOY_BUTTON_A, JOY_BUTTON_START: _activate_home_item()
			return
		gamepad_active = true
		match event.button_index:
			JOY_BUTTON_RIGHT_SHOULDER: shift_up = true
			JOY_BUTTON_LEFT_SHOULDER: shift_down = true
			JOY_BUTTON_Y: _pit()
			JOY_BUTTON_START: _set_paused(not paused)
		return

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var down: bool = event.pressed and not event.echo
	if not race:
		if not down:
			return
		if active_menu_page == "home":
			match event.keycode:
				KEY_LEFT, KEY_A, KEY_UP, KEY_W:
					_home_select(home_menu_index - 1)
					get_viewport().set_input_as_handled()
					return
				KEY_RIGHT, KEY_D, KEY_DOWN, KEY_S:
					_home_select(home_menu_index + 1)
					get_viewport().set_input_as_handled()
					return
				KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
					_activate_home_item()
					get_viewport().set_input_as_handled()
					return
		else:
			if active_menu_page == "options":
				if event.keycode == KEY_ESCAPE or event.keycode == KEY_BACKSPACE:
					_show_home()
					get_viewport().set_input_as_handled()
				return
			match event.keycode:
				KEY_ESCAPE, KEY_BACKSPACE:
					_show_home()
					get_viewport().set_input_as_handled()
					return
				KEY_LEFT, KEY_A:
					menu_tab_index = posmod(menu_tab_index - 1, TOP_MENU_TABS.size())
					_select_menu_tab(TOP_MENU_TABS[menu_tab_index])
					get_viewport().set_input_as_handled()
					return
				KEY_RIGHT, KEY_D:
					menu_tab_index = posmod(menu_tab_index + 1, TOP_MENU_TABS.size())
					_select_menu_tab(TOP_MENU_TABS[menu_tab_index])
					get_viewport().set_input_as_handled()
					return
				KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
					var tab: Button = menu_tab_buttons[TOP_MENU_TABS[menu_tab_index]]
					tab.pressed.emit()
					get_viewport().set_input_as_handled()
					return
		return
	if not down:
		return
	if paused:
		if event.physical_keycode == KEY_ESCAPE:
			_set_paused(false)
			get_viewport().set_input_as_handled()
		return
	if skipping or race.phase == "finished":
		return
	match event.physical_keycode:
		KEY_E: shift_up = true
		KEY_Q: shift_down = true
		KEY_P: _pit()
		KEY_BRACKETLEFT: _cycle_pit_tyre(-1)
		KEY_BRACKETRIGHT: _cycle_pit_tyre(1)
		KEY_MINUS, KEY_KP_SUBTRACT: _adjust_pit_fuel(-1.0)
		KEY_EQUAL, KEY_KP_ADD: _adjust_pit_fuel(1.0)
		KEY_R: _replan()
		KEY_O: _toggle_autopilot()
		KEY_C: _cycle_camera()
		KEY_L: _toggle_racing_line()
		KEY_V: race.limiter = not race.limiter
		KEY_H: hud.toggle_help()
		KEY_M: _toggle_mute()
		KEY_COMMA: _change_warp(-1)
		KEY_PERIOD: _change_warp(1)
		KEY_ESCAPE: _set_paused(true)
		KEY_ENTER, KEY_KP_ENTER:
			if race.player.finished or race.player.dnf:
				_begin_skip()
		_:
			return
	get_viewport().set_input_as_handled()

func _cycle_pit_tyre(direction: int) -> void:
	if race:
		race.player_cycle_compound(direction)
		if is_instance_valid(audio):
			audio.beep(780.0, 1)

func _adjust_pit_fuel(delta_litres: float) -> void:
	if race:
		race.player_adjust_fuel(delta_litres)
		if is_instance_valid(audio):
			audio.beep(680.0, 1)

func _change_warp(direction: int) -> void:
	if not race:
		return
	var next_index := clampi(warp_index + direction, 0, WARP_VALUES.size() - 1)
	if next_index == warp_index:
		return
	warp_index = next_index
	race.warp = WARP_VALUES[warp_index]
	hud.warp = race.warp
	var p := race.player
	if race.warp > 1 and not p.autopilot and not p.finished and not p.dnf:
		race.set_autopilot(true)
		if p.autopilot:
			race.log_event("Co-driver takes the wheel — press O to take it back", "info")
	race.log_event("Time warp ×%d" % race.warp if race.warp > 1 else "Real time", "info")

func _pit() -> void:
	if race:
		race.player_toggle_pit()

func _replan() -> void:
	if race:
		race.player_replan()
		if is_instance_valid(audio):
			audio.beep(850.0, 1)

func _toggle_autopilot() -> void:
	if race:
		race.set_autopilot(not race.player.autopilot)

func _cycle_camera() -> void:
	if world_view and world_view.has_method("cycle_camera"):
		var cam_name: String = world_view.cycle_camera()
		if race:
			race.log_event("Camera: %s" % cam_name.to_lower(), "info")

func _toggle_racing_line() -> void:
	if world_view and world_view.has_method("toggle_racing_line"):
		world_view.toggle_racing_line()

func _toggle_mute() -> void:
	if is_instance_valid(audio):
		audio.toggle_mute()

func _toggle_pause() -> void:
	_set_paused(not paused)

func _quit_race() -> void:
	_return_to_setup()

func _panel(min_size := Vector2.ZERO) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = min_size
	return panel

## A panel with its own flat purple sheet, for screens drawn over the race (pause, results).
func _sheet(min_size := Vector2.ZERO) -> PanelContainer:
	var panel := _panel(min_size)
	panel.add_theme_stylebox_override("panel", CmrStyle.panel())
	return panel

func _column(parent: Control, spacing := 12) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", spacing)
	parent.add_child(box)
	return box

func _title(parent: Control, title: String, subtitle: String) -> void:
	var t := _label(title, 30, INK)
	parent.add_child(t)
	var sub := _label(subtitle, 13, ACCENT)
	parent.add_child(sub)

func _field_label(parent: Control, text: String) -> void:
	var l := _label(text, 13, MUTED)
	parent.add_child(l)

func _menu_rule(parent: Control) -> void:
	var line := ColorRect.new()
	line.color = Color(CmrStyle.TEXT, 0.6)
	line.custom_minimum_size.y = 2
	parent.add_child(line)

## step is set before the value: a Range snaps its value to min + k·step, so 2 with min 0.5 and the
## default step of 1 would become 2.5.
func _spin(parent: Control, title: String, low: float, high: float, value: float, step := 1.0) -> SpinBox:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(col)
	_field_label(col, title)
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	spin.value = value
	spin.custom_minimum_size.y = 40
	_style_control(spin)
	col.add_child(spin)
	return spin

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

## A flat CMR box. Orange (ACCENT) is the primary action and red a destructive one; any other colour
## gives the standard light bar.
func _button(text: String, color: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 42
	button.add_theme_font_size_override("font_size", 16)
	if color == ACCENT or color == DANGER:
		button.add_theme_stylebox_override("normal", CmrStyle.box(color, color.darkened(0.3)))
		button.add_theme_stylebox_override("hover", CmrStyle.box(color.lightened(0.2), color.darkened(0.3)))
		if color == DANGER:
			for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
				button.add_theme_color_override(key, INK)
	return button

## Pickers take their look from the theme; spin boxes also need their inner line edit sized.
func _style_control(control: Control) -> void:
	if control is SpinBox:
		(control as SpinBox).get_line_edit().add_theme_font_size_override("font_size", 17)

func _select_format(index: int) -> void:
	if is_instance_valid(hours_picker):
		hours_picker.get_parent().visible = index == 1 and not is_championship_mode
	if is_instance_valid(laps_picker):
		laps_picker.get_parent().visible = index == 0 and not is_championship_mode
	if index == 1 and not _loading_settings:
		# endurance: refuelling on, and tyres that last a stint
		_loading_settings = true
		refuel_toggle.button_pressed = true
		wear_picker.value = minf(wear_picker.value, 1.0)
		_loading_settings = false
	_update_information_page()
	_update_menu_car_summary()
	_queue_strategy_refresh()


func _option_field(parent: Control, title: String, options: Array) -> OptionButton:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(col)
	_field_label(col, title)
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for o in options:
		opt.add_item(str(o))
	opt.custom_minimum_size.y = 40
	_style_control(opt)
	col.add_child(opt)
	return opt

## Empty columns that keep a lone field at the width of the three-column rows around it.
func _grid_spacers(row: HBoxContainer, count: int) -> void:
	for i in count:
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)

func _check_field(parent: Control, title: String, default_val: bool) -> CheckButton:
	var chk := CheckButton.new()
	chk.text = title
	chk.button_pressed = default_val
	chk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_control(chk)
	parent.add_child(chk)
	return chk
