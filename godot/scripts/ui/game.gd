## Main game controller for the Seicento 900 Cup: front-end menus, race setup, the fixed-step race loop
## (with render interpolation and a spiral guard), keyboard/gamepad input, pause menu, results and the
## eight-round championship. The in-race HUD lives in RaceHud.
extends Control

const RaceHud = preload("res://scripts/ui/race_hud.gd")

## Circuits offered in the menus, in menu order; each key needs data/tracks/<key>.tres and .json.
## TRACK_NAMES is the display name for the key at the same index.
const TRACK_KEYS := ["gp", "nordschleife", "monaco", "indy", "lemans", "monza", "silverstone", "spa", "suzuka", "zandvoort", "fiat", "tokyo", "bielsko", "krakow", "oswiecim", "wilamowice", "brzeszcze", "pszczyna", "bor", "goliath"]
const TRACK_NAMES := ["Nürburgring GP", "Nordschleife", "Monaco", "Indianapolis", "Le Mans", "Monza", "Silverstone", "Spa-Francorchamps", "Suzuka", "Zandvoort", "Fiat Track", "Tokyo C1 Expressway", "Bielsko-Biała Szyndzielnia", "Kraków Royal Ring", "Oświęcim Riverfront", "Wilamowice Country Loop", "Brzeszcze Industrial Sprint", "Pszczyna Castle Grounds", "Bór Forest Stage", "The Seicento Goliath"]

## Championship rounds in order (track keys)
const CHAMPIONSHIP_CALENDAR := ["monza", "silverstone", "spa", "gp", "monaco", "indy", "lemans", "nordschleife"]
## Points for 1st, 2nd, ... (F1 scoring); positions past the end score nothing
const CHAMPIONSHIP_POINTS := [25, 18, 15, 12, 10, 8, 6, 4, 2, 1]
## A season is set up before round 1 (champ_data.config) and locked once it is under way. Calendar presets:
const SEASON_PRESETS := [
	{"name": "Classic GP", "tracks": CHAMPIONSHIP_CALENDAR},
	{"name": "Polish Tour", "tracks": ["wilamowice", "brzeszcze", "bor", "pszczyna", "bielsko", "oswiecim", "krakow", "fiat"]},
	{"name": "World Tour", "tracks": ["monza", "suzuka", "silverstone", "zandvoort", "spa", "tokyo", "monaco", "krakow", "indy", "nordschleife"]},
	{"name": "Full", "tracks": TRACK_KEYS},
	{"name": "Custom", "tracks": []}, # whatever is ticked on the calendar list
]
const SEASON_LENGTHS := [{"name": "Sprint (½ laps)", "mult": 0.5}, {"name": "Standard", "mult": 1.0}, {"name": "Long (×1.5 laps)", "mult": 1.5}]
const SEASON_POINTS := [
	{"name": "25-18-15-12-10-8-6-4-2-1", "table": CHAMPIONSHIP_POINTS},
	{"name": "10-8-6-5-4-3-2-1", "table": [10, 8, 6, 5, 4, 3, 2, 1]},
	{"name": "10-6-4-3-2-1", "table": [10, 6, 4, 3, 2, 1]},
]
const WEATHER_KEYS := ["dry", "wet", "snow", "hail", "fog", "variable"]
const SEASON_WEATHERS := ["Dry", "Wet", "Snow", "Hail", "Fog", "Variable", "Random each round"]
const RANDOM_WEATHER_POOL := ["dry", "dry", "dry", "dry", "wet", "variable", "variable", "fog", "snow", "hail"]
## Damage & repairs between events: Off (the car is rebuilt), Realistic (damage carries over, a 60-minute
## service), Hardcore (it carries over and the crew gets half the time).
const SEASON_DAMAGE := [{"name": "Off (rebuilt every round)", "minutes": 0}, {"name": "Realistic (60 min service)", "minutes": 60}, {"name": "Hardcore (30 min service)", "minutes": 30}]
const PROJECT_FINISH_ABOVE := 0.05 ## share of the race left beyond which a DNF projects the finish instead of simulating it
## Tabs across the top of the race front end (set-up, repair, ...)
const TOP_MENU_TABS := ["Set Up", "Advanced", "Car", "Strategy", "Service"]
const MENU_TRACK_ART := preload("res://scripts/ui/menu_track_art.gd")
const MENU_WEATHER_ICON := preload("res://scripts/ui/menu_weather_icon.gd")
const MENU_TEMPERATURE_BAR := preload("res://scripts/ui/menu_temperature_bar.gd")
const MENU_REPAIR_ART := preload("res://scripts/ui/menu_repair_art.gd")
const MENU_REPAIR_STATUS := preload("res://scripts/ui/menu_repair_status.gd")
const MENU_CAR_SCENE := preload("res://scripts/ui/race_car_visual.tscn")
const LOADING_SCREEN := preload("res://scripts/ui/loading_screen.gd")
const RetroPipeline := preload("res://scripts/ui/retro_pipeline.gd")
const CampaignData := preload("res://scripts/sim/campaign.gd")
## Main menu entries: `id` picks the action, `word` is the big sliding word, `desc` the line under it
const FRONT_MENU := [
	{"id": "campaign", "word": "CAMPAIGN", "desc": "The Seicento Odyssey: From Bielsko-Biała across Poland to Tokyo"},
	{"id": "quick_race", "word": "QUICK RACE", "desc": "Pick a circuit and race: the defaults are ready, just press Start"},
	{"id": "rally", "word": "RALLY", "desc": "Special stages against the clock with your co-driver's pace notes"},
	{"id": "time_trial", "word": "TIME TRIAL", "desc": "Hot laps alone on any circuit, against your ghost and your lap records"},
	{"id": "championship", "word": "CHAMPIONSHIP", "desc": "Your own season: pick the calendar, rules and damage, then race for the title"},
	{"id": "options", "word": "OPTIONS", "desc": "Retro shaders (F1), display, audio, driving aids, controls"},
	{"id": "quit", "word": "QUIT", "desc": "Exit the game"},
]
## Per-circuit defaults applied when the track is picked: race laps, tyre wear and fuel use multipliers.
## Indianapolis is flat out all the way round, so tyres hardly matter there; it is a fuel race instead (a
## tank lasts about five laps flat out, six on the save mix), as the 500 is.
const TRACK_DEFAULTS := {
	"gp": {"laps": 6, "wear": 2.0},
	"nordschleife": {"laps": 2, "wear": 1.0},
	"monaco": {"laps": 8, "wear": 2.0},
	"indy": {"laps": 12, "wear": 1.0, "fuel": 15.0},
	"lemans": {"laps": 2, "wear": 1.0},
	"monza": {"laps": 6, "wear": 2.0},
	"silverstone": {"laps": 6, "wear": 2.0},
	"spa": {"laps": 5, "wear": 2.0},
	"suzuka": {"laps": 6, "wear": 2.0},
	"zandvoort": {"laps": 6, "wear": 2.0},
	"fiat": {"laps": 8, "wear": 2.0},
	"tokyo": {"laps": 6, "wear": 2.0},
	"bielsko": {"laps": 5, "wear": 2.0},
	"krakow": {"laps": 6, "wear": 2.0},
	"oswiecim": {"laps": 8, "wear": 2.0},
	"wilamowice": {"laps": 3, "wear": 2.0},
	"brzeszcze": {"laps": 8, "wear": 2.0},
	"pszczyna": {"laps": 6, "wear": 2.0},
	"bor": {"laps": 7, "wear": 2.0},
	"goliath": {"laps": 1, "wear": 1.0},
}

## Stock paints: ◂ ▸ steps through them on the set-up page (Enter on the swatch opens the mixer for any colour)
## and they fill the mixer's swatches: reds, pink, orange to green, blues, purple, then the earthy and neutral shades
const PAINTS := ["#b3121d", "#e53935", "#7b1e2b", "#e91e8c", "#ff7a00", "#f5c400", "#d4e157", "#2e7d32", "#1b4d2e",
	"#00a3b4", "#4fc3f7", "#1f4fa8", "#0d1b4c", "#6a1b9a", "#6d4c33", "#d9cfb4", "#f2f2f2", "#8e9aa6", "#555b62", "#16181d"]
## Pages the header tabs switch between with Q/E (PgUp/PgDn, the shoulder buttons)
const MENU_PAGES := ["Set Up", "Advanced", "Car", "Strategy", "Service"] ## (Strategy: quick race and time trial; Service: where a car is serviced between events)
const MENU_PAGE_IDS := ["setup", "advanced", "car", "strategy", "repair"] ## active_menu_page of each of MENU_PAGES
const SETUP_KEYS := "↑ ↓ choose   ← → change   Q E pages   End race   Esc back"
## The same keys on a gamepad, shown while one is connected (_hint)
const PAD_KEYS := {
	"home": "✚ ← → browse     Ⓐ select",
	"setup": "✚ choose · change   Ⓐ press   LB RB pages   START race   Ⓑ back",
	"advanced": "✚ choose · change   Ⓐ press   LB RB pages   START race   Ⓑ back",
	"car": "✚ choose · change   Ⓐ press   LB RB pages   START race   Ⓑ back",
	"strategy": "✚ choose · change   Ⓐ press   LB RB pages   START race   Ⓑ back",
	"repair": "✚ ↑ ↓ part   Ⓐ repair   LB RB pages   START continue   Ⓑ back",
	"options": "✚ ↑ ↓ choose   ← → change   Ⓐ press   Ⓑ back",
}
const KEY_KEYS := {
	"home": "← → browse     Enter select",
	"setup": SETUP_KEYS,
	"advanced": SETUP_KEYS,
	"car": SETUP_KEYS,
	"strategy": SETUP_KEYS,
	"repair": "↑ ↓ part   Enter repair   Space continue   Q E pages   Esc back",
	"options": "↑ ↓ choose   ← → change   Enter press   Esc back",
}
const WARP_VALUES := [1, 2, 5, 10, 30, 60] ## time-warp steps (, and . keys)
const UI_SCALES := [0.85, 1.0, 1.15, 1.3] ## Options → Interface size, on top of the window scaling
const BASE_SIZE := Vector2i(1600, 900) ## the canvas the interface is laid out on (project.godot)
## Options → Resolution presets (only those that fit the screen are offered, with Native and the window's own).
const RESOLUTIONS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]
## Options → Aspect ratio: Auto fills the window; a ratio letterboxes (or pillarboxes) the game to it.
const ASPECTS := [
	{"name": "Auto (fill the window)", "ratio": 0.0},
	{"name": "16:9", "ratio": 16.0 / 9.0},
	{"name": "16:10", "ratio": 16.0 / 10.0},
	{"name": "21:9", "ratio": 21.0 / 9.0},
	{"name": "4:3", "ratio": 4.0 / 3.0},
]
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
const STILL_FPS := 30 ## cap while the 3D view holds a still image (pause, results)
const BACKGROUND_FPS := 10 ## cap while the window is not in front
const STILL_FRAMES := 3 ## frames the 3D view keeps drawing after it stops changing, so its last image is the current one

const TICK := 1.0 / 120.0 ## fixed simulation step (120 Hz); the parity tests and replays depend on it
const WARP_TICKS := {2: 2, 5: 4, 10: 4, 30: 4, 60: 6} ## ticks the rail model steps at once at each time warp
const WARP_SIM_SHARE := 0.6 ## at most this much of each frame goes on the simulation under time warp
# Shorthands for the CmrStyle palette
var INK: Color:
	get: return CmrStyle.TEXT
var MUTED: Color:
	get: return CmrStyle.MUTED
var ACCENT: Color:
	get: return CmrStyle.ORANGE
var DANGER: Color:
	get: return CmrStyle.RED

var race: Race
var lap_records: LapRecords ## the player's lap records on this circuit, and the lap being recorded
var lap_ghost: LapGhost ## the car that drives the record lap
var accumulator := 0.0
var paused := false
var _starting := false ## a race is being set up (_start_race)
var _player_input := Race.PlayerInput.new() ## reused every frame instead of allocating one per _process call

# Audio
var audio: RaceAudio
var world_audio: WorldAudio ## everything else the race sounds like (it follows the race on its own)

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
var menu_home_track: Label
var options_panel: PanelContainer
var upscaler_picker: MenuSelector
var upscale_preset_picker: MenuSelector
var sharpening_picker: MenuSelector
var render_viewport: SubViewport
var home_menu_index := 0
var home_phys := 0 ## which of the strip's three copies of the words is selected (the middle copy is n..2n-1)
var home_tween: Tween
var information_map: Control ## the circuit map under the car on the Set Up page
var circuit_map_frame: PanelContainer
var circuit_facts: Label ## start time, weather, field and lap record under the circuit's name
var advanced_panel: PanelContainer
var car_panel: PanelContainer
var adv_page := {} ## the Advanced page: {panel, scroll, column, hint, race}
var car_page := {} ## the Car page: same
var strat_page := {} ## the Strategy page: same
var strategy_panel: PanelContainer
var menu_car_preview: TextureRect
var menu_car_viewport: SubViewport
var render_view: TextureRect
var retro_pipeline: RetroPipeline
var retro_picker: MenuSelector
var graphics_retro_mode := 0
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
var repair_selected := 0
var repair_marks: Array = [] ## the condition mark beside each part
var repair_clock: Label ## service time left
var repair_note: Label ## under the clock: what the allocation is for
var repair_button: Button
var repair_art: Control
var last_race_parts := {} ## the player's parts at the end of the last single race, for the Repair page
var menu_scroll: ScrollContainer
var display_mode_picker: MenuSelector
var resolution_picker: MenuSelector
var resolution_note: Label
var aspect_picker: MenuSelector
var audio_pickers := {} ## AudioSettings channel key -> its volume picker
var graphics_resolution := Vector2i(-1, -1) ## Options → Resolution: (-1, -1) as launched, ZERO native
var graphics_aspect := 0 ## index into ASPECTS
var _resolution_choices: Array[Vector2i] = [] ## what resolution_picker's entries stand for
var antialiasing_picker: MenuSelector
var vsync_toggle: CheckButton
var fps_limit_picker: MenuSelector
var reflections_picker: MenuSelector
var ssao_toggle: CheckButton
var shadows_toggle: CheckButton
var codriver_voice_toggle: CheckButton
var graphics_display_mode := 0
var graphics_fps_limit := 1 ## index into FPS_LIMITS
var graphics_antialiasing := 0
var graphics_vsync := true
var graphics_upscaler := 0 ## index into UPSCALERS
var graphics_upscale_preset := 1 ## index into UPSCALE_PRESETS
var graphics_sharpening := 2 ## index into SHARPENING
var graphics_reflections := 0 ## 0 off, 1 screen-space, 2 ray-traced
var graphics_ssao := true
var graphics_quality := 2 ## the world's rendering level, set by the graphics presets (GraphicsPresets)
var graphics_preset := 2 ## index into GraphicsPresets.NAMES, or GraphicsPresets.CUSTOM
var preset_picker: MenuSelector
var preset_note: Label
var graphics_shadows := true
var codriver_voice := true ## Options → Co-driver voice: the pace notes are read aloud
var graphics_ui_scale := 1 ## index into UI_SCALES
var ui_scale_picker: MenuSelector
var menu_tab_buttons: Dictionary = {}
var menu_tab_dividers: Dictionary = {}
var menu_tab_index := 1
var active_menu_page := "home"
var hud: RaceHud
var loading_screen: LoadingScreen
var result_panel: PanelContainer
var result_scroll: ScrollContainer
var pause_panel: PanelContainer
var pause_dim: ColorRect ## darkens the race and its HUD behind the pause menu, so the menu is all you read
var pause_buttons: Array[Button] = []
var skipping := false
var quali_session := false ## the session on screen is a qualifying run, not a race
var _idle_input := Race.PlayerInput.new()

# Setup controls
var setup_title_label: Label ## the set-up page's heading: the mode chosen on the main menu
var setup_subtitle_label: Label
var is_championship_mode := false
var is_campaign_mode := false
var campaign_stage_index := 0
var campaign_side: VBoxContainer
var campaign_act_label: Label
var campaign_stage_picker: MenuSelector
var campaign_title_label: Label
var campaign_circuit_label: Label
var campaign_desc_label: Label
var campaign_target_label: Label
var campaign_trophy_label: Label
var campaign_tip_label: Label
var campaign_start_button: Button
var campaign_cleared := false ## the last campaign race met its target: back at the menu, the briefing moves on
var open_world: OpenWorld = null ## the campaign's free roam round Brzeszcze (scripts/world/open_world.gd), kept once built
var world_return := -1 ## the campaign stage started from the open world: its results lead back to its beacon
var campaign_world_button: Button
var champ_data: Dictionary = {}
var track_picker: MenuSelector
var laps_picker: SpinBox
var format_picker: MenuSelector
var hours_picker: SpinBox
var start_hour_picker: SpinBox
var opponents_picker: SpinBox
var difficulty_picker: MenuSelector
var weather_picker: MenuSelector
var gearbox_picker: MenuSelector
var grid_picker: MenuSelector
var quali_picker: MenuSelector ## championship qualifying: drive it, let the co-driver run it, or skip it
var assists_picker: MenuSelector
var wear_picker: SpinBox
var fuel_picker: SpinBox
var mandatory_stop_toggle: CheckButton
var two_compounds_toggle: CheckButton
var refuel_toggle: CheckButton
var collisions_toggle: CheckButton
var race_control_toggle: CheckButton
var damage_toggle: CheckButton ## crash damage that costs power, grip and parts (off: dents only)
var dynamic_toggle: CheckButton
var draft_toggle: CheckButton
var strategist_toggle: CheckButton
var parallel_toggle: CheckButton
var crew_picker: MenuSelector
var ai_learning_picker: MenuSelector
var bot_physics_picker: MenuSelector
var player_name_edit: LineEdit
var player_number_picker: SpinBox
var player_color_picker: ColorPickerButton
var player_stripes_toggle: CheckButton
var player_finish_picker: MenuSelector
var car_class_picker: MenuSelector
var _hyper_model: CarModel
var _hyper_strategy: Strategy
var setup_format_row: Control
var setup_conditions_row: Control
var setup_driving_row: HBoxContainer
var setup_rule_divider: ColorRect
var champ_reset_button: Button
var setup_column: VBoxContainer ## the settings in the set-up page's scroll, in keyboard order
var setup_race_button: Button
var setup_hint: Label ## under RACE: what the focused setting does, and the menu keys
var setup_folds := {} ## section key -> {head, body, title, summary}
var setup_open := {"driving": false, "race": false, "driver": false, "car": false, "strategy": false, "rules": false, "plan": false, "calendar": false, "mods": false} ## folded sections start shut
var is_time_trial_mode := false ## main menu → TIME TRIAL: the quick-race page for a solo run (no field)
var is_rally_mode := false ## main menu → RALLY: an event of special stages (Rally / RallyEvent)
var rally_event: RallyEvent = null ## the rally being run (saved to user://rally.json between stages)
var rally_car := {} ## the rally car between stages for the service area: {parts, pull, used, serviced}
var _rally_recorded: Race = null ## the stage race already written into rally_event (results or a quit)
var rally_side: VBoxContainer
var rally_event_picker: MenuSelector
var rally_info_label: Label
var rally_restart_button: Button
var tt_start_row: Control ## TIME TRIAL: standing or rolling start
var tt_start_picker: MenuSelector
var options_column: VBoxContainer ## the Options page's settings, in keyboard order
var menu_prompt: Label ## the button prompts along the bottom of the Circuit Info, Car & Service and Options pages
var menu_back_button: Button
var _stick_latch := Vector2i.ZERO ## the left stick works as a d-pad on the menus: one step per push
# championship season set-up (champ_data.config), shown before round 1 and locked once it has been raced
var season_box: VBoxContainer
var season_note: Label
var season_preset_picker: MenuSelector
var season_order_picker: MenuSelector
var season_length_picker: MenuSelector
var season_opponents_picker: MenuSelector
var season_difficulty_picker: MenuSelector
var season_weather_picker: MenuSelector
var season_points_picker: MenuSelector
var season_damage_picker: MenuSelector
var season_track_toggles := {} ## track key -> CheckButton on the custom calendar list
var _season_syncing := false
var repair_continue: Button ## the service area's way on to the next event
var repair_summary: Label ## every unrepaired part and what it will do in the next race
var _setup_focus_at := 0 ## where the keyboard was in the set-up list, for when its control goes away
var _lit_caption: Label ## the field caption picked out for the focused setting
var _lit_caption_color := MUTED
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
var record_label: Label ## the player's lap records on the selected circuit
var record_forget_button: Button
var ai_forget_button: Button
# Car set-up (CMR 2.0's): one per circuit, the page shows the selected circuit's
var car_setups := {} ## track key -> CarSetup notches
var setup_sliders := {} ## setting -> HSlider
var setup_values := {} ## setting -> Label with the notch
var setup_help: Label

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
var handbrake := 0.0 ## Space or the pad's A button
var nitro_held := false ## the Nitrous modifier's button: Shift or the pad's L3
var _time_rate := 1.0 ## the Bullet Time modifier's simulation speed
var mod_toggles := {} ## CarMods id -> CheckButton on the Car page
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

	_map_pad_buttons()
	_load_championship()
	_build_audio()
	add_child(DevHud.new())
	var dev_menu := DevMenu.new()
	dev_menu.game = self
	add_child(dev_menu)
	_build_viewport()
	_build_setup()
	_build_repair_page()
	_build_home_screen()
	_build_options_page()
	_build_hud()
	_build_results()
	loading_screen = LOADING_SCREEN.new()
	add_child(loading_screen)
	_build_menu_prompt()
	Input.joy_connection_changed.connect(func(_device: int, _connected: bool) -> void: _refresh_prompts())
	_show_home()
	_fit_3d_views.call_deferred()

## A and B work the dialogs, the pause menu and the results like Enter and Esc (Godot maps only the keys).
func _map_pad_buttons() -> void:
	for pair in [["ui_accept", JOY_BUTTON_A], ["ui_cancel", JOY_BUTTON_B]]:
		var has := false
		for ev in InputMap.action_get_events(pair[0]):
			has = has or (ev is InputEventJoypadButton and ev.button_index == pair[1])
		if not has:
			var ev := InputEventJoypadButton.new()
			ev.button_index = pair[1]
			ev.device = -1
			InputMap.action_add_event(pair[0], ev)

## A gamepad is plugged in: the prompts show its buttons instead of the keys.
func _pad_connected() -> bool:
	return not Input.get_connected_joypads().is_empty()

## The button prompts for a front-end page (PAD_KEYS / KEY_KEYS).
func _hint(page: String) -> String:
	return str((PAD_KEYS if _pad_connected() else KEY_KEYS).get(page, ""))

func _build_menu_prompt() -> void:
	menu_prompt = _label("", 17, CmrStyle.ORANGE_SOFT)
	menu_prompt.name = "MenuPrompt"
	menu_prompt.anchor_left = 0.045
	menu_prompt.anchor_right = 0.98
	menu_prompt.anchor_top = 0.955
	menu_prompt.anchor_bottom = 0.995
	menu_prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	menu_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(menu_prompt)
	menu_prompt.hide()

## Re-labels every prompt (a pad was plugged in or out, or the page changed).
func _refresh_prompts() -> void:
	if is_instance_valid(menu_back_button):
		menu_back_button.text = "MAIN MENU (Ⓑ)" if _pad_connected() else "MAIN MENU (Esc)"
	if is_instance_valid(menu_prompt):
		menu_prompt.text = _hint(active_menu_page)
		menu_prompt.visible = active_menu_page in ["repair", "options"] and menu_tint.visible
	if active_menu_page == "home" and is_instance_valid(menu_home_desc):
		_home_select(home_menu_index, false)
	if active_menu_page in ["setup", "advanced", "car", "strategy"] and is_instance_valid(setup_hint):
		_setup_focus_changed(get_viewport().gui_get_focus_owner())

func _build_audio() -> void:
	audio = RaceAudio.new()
	add_child(audio)
	world_audio = WorldAudio.new(self)
	add_child(world_audio)

## Battery and heat: the 3D view is only rendered while somebody can see it change. Behind the opaque front-end
## pages it is off; while paused or on the results screen it draws a few more frames and then keeps its last
## image. The frame-rate cap follows the same states, and drops further while the window is in the background.
func _sync_rendering() -> void:
	var covered := menu_tint.visible or (open_world != null and open_world.active)
	var still := not covered and race != null and (paused or race.phase == "finished") and not skipping
	_still_frames = _still_frames + 1 if still else 0
	var live := not covered and _still_frames <= STILL_FRAMES
	if live != _view_live:
		_view_live = live
		render_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if live else SubViewport.UPDATE_DISABLED
		world_view.process_mode = Node.PROCESS_MODE_INHERIT if live else Node.PROCESS_MODE_DISABLED
	# the front-end pages draw only UI (the 3D view is off behind them), so they run at the player's own limit
	var fps: int = FPS_LIMITS[graphics_fps_limit].fps
	if not _app_focused:
		fps = BACKGROUND_FPS
	elif not live and not covered:
		fps = STILL_FPS if fps == 0 else mini(fps, STILL_FPS)
	if Engine.max_fps != fps:
		Engine.max_fps = fps

func _process(delta: float) -> void:
	if retro_pipeline:
		retro_pipeline.update_time(delta)
	_pump_track_prefetch()
	_sync_rendering()
	if _starting:
		return
	if not race:
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
	accumulator += minf(delta, 0.1) * race.warp * _bullet_rate(delta)
	var input := _player_input
	input.throttle = throttle
	input.brake = brake
	input.handbrake = handbrake
	input.nitro = nitro_held
	input.steer = steer
	input.shift_up = shift_up
	input.shift_down = shift_down

	var steps := 0
	var tick := _tick()
	var cap := 40 * race.warp
	# never let a slow machine fall into a spiral at high warp: there the simulation gets at most
	# WARP_SIM_SHARE of a frame at the frame-rate limit, so the picture stays smooth and the warp runs
	# as fast as the machine allows instead of pinning a core
	var budget := 40000
	if race.warp > 1:
		var fps: int = Engine.max_fps if Engine.max_fps > 0 else 60
		budget = int(WARP_SIM_SHARE * 1e6 / fps)
	var t0 := Time.get_ticks_usec()
	while accumulator >= tick and steps < cap and race.phase != "finished":
		race.step(tick, input)
		if lap_records:
			lap_records.tick()
		accumulator -= tick
		steps += 1
		if (steps & 3) == 0 and Time.get_ticks_usec() - t0 > budget:
			break
	if steps >= cap or accumulator > tick * 4.0 * race.warp:
		accumulator = 0.0
	if steps > 0:
		shift_up = false
		shift_down = false
	world_view.render_alpha = accumulator / tick

	if is_instance_valid(audio):
		audio.update_car(p, not p.finished and not p.dnf, race.weather if race else null)
	hud.update(delta)
	if race.phase == "finished":
		_show_results()

## The simulation step. The car physics needs 120 Hz, but under time warp every car is on the rail model,
## which runs the same race at 1/30 s (1/20 s at x60) within the spread the tick rate alone causes; at
## 1/120 s a 30x warp would run 3600 ticks a second and drag the frame rate down. The player's car on its
## own physics keeps the full rate.
func _tick() -> float:
	if race.warp == 1 or race.player.control == "free":
		return TICK
	return TICK * WARP_TICKS.get(race.warp, 4)

## Keyboard driving: pedals and steering ease in and out like the reference instead of snapping.
func _update_input(dt: float) -> void:
	var up := Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)
	var down := Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)
	var left := Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)
	var right := Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)
	var hand := Input.is_physical_key_pressed(KEY_SPACE)
	if up or down or left or right or hand:
		gamepad_active = false
	if gamepad_active:
		return
	handbrake = 1.0 if hand else 0.0
	nitro_held = Input.is_physical_key_pressed(KEY_SHIFT)
	var st := (1.0 if right else 0.0) - (1.0 if left else 0.0)
	var back := st == 0.0 or signf(st) != signf(steer)
	var v_kmh := absf(race.player.speed) * 3.6 if (race and race.player) else 0.0
	var steer_rate := 4.4 if v_kmh < 40.0 else lerpf(4.4, 2.6, clampf((v_kmh - 40.0) / 80.0, 0.0, 1.0))
	steer = move_toward(steer, st, (8.0 if back else steer_rate) * dt)
	throttle = move_toward(throttle, 1.0 if up else 0.0, 6.0 * dt)
	brake = move_toward(brake, 1.0 if down else 0.0, 8.0 * dt)

## Once the player is out of it, the rest of the race runs as fast as the machine allows.
func _begin_skip() -> void:
	if not race or race.phase == "finished" or skipping:
		return
	# out of the race with more than 5% still to run: project the finish instead of simulating it
	if race.player.dnf and race.remaining_fraction() > PROJECT_FINISH_ABOVE:
		race.approximate_finish()
		_show_results()
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
		handbrake = 0.0
		steer = 0.0
		return
	var raw_steer := Input.get_joy_axis(gamepad_device, JOY_AXIS_LEFT_X)
	var deadband := maxf(0.0, (absf(raw_steer) - 0.1) / 0.9)
	steer = signf(raw_steer) * deadband * deadband
	throttle = clampf(Input.get_joy_axis(gamepad_device, JOY_AXIS_TRIGGER_RIGHT), 0.0, 1.0)
	brake = clampf(Input.get_joy_axis(gamepad_device, JOY_AXIS_TRIGGER_LEFT), 0.0, 1.0)
	handbrake = 1.0 if Input.is_joy_button_pressed(gamepad_device, JOY_BUTTON_A) else 0.0
	nitro_held = Input.is_joy_button_pressed(gamepad_device, JOY_BUTTON_LEFT_STICK)

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
	retro_pipeline = RetroPipeline.new()
	retro_pipeline.set_mode(graphics_retro_mode)
	retro_pipeline.apply_to_texture_rect(render_view)
	add_child(render_view)
	move_child(render_view, 0)
	move_child(viewport, 0)

	world_view = load("res://ui/race_world.tscn").instantiate()
	viewport.add_child(world_view)
	# no circuit built yet: the front-end pages cover the 3D view, so the world is built for the first race
	# (set_race) instead of on every circuit change in the menus
	lap_ghost = LapGhost.new()
	world_view.add_child(lap_ghost)
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
		if vp == render_viewport:
			px = _render_resolution(px)
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

	# the settings scroll; the status, RACE and the key hint stay pinned under them
	var page := _column(setup_panel, 8)
	menu_scroll = ScrollContainer.new()
	menu_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	menu_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	menu_scroll.follow_focus = true
	page.add_child(menu_scroll)
	var gutter := MarginContainer.new() # keeps the fields and their focus ring clear of the scroll bar
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_theme_constant_override("margin_right", 16)
	gutter.add_theme_constant_override("margin_left", 3)
	menu_scroll.add_child(gutter)
	var col := _column(gutter, 12)
	setup_column = col
	# the mode is picked on the main menu; the page just says which one it is (Esc goes back to change it)
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 10)
	col.add_child(mode_row)
	var title_col := VBoxContainer.new()
	title_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_row.add_child(title_col)
	_title(title_col, "QUICK RACE", "SEICENTO 900 CUP")
	setup_title_label = title_col.get_child(0)
	setup_subtitle_label = title_col.get_child(1)
	var reset_button := _button("RESET SEASON", DANGER)
	reset_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	reset_button.pressed.connect(func() -> void: champ_reset_dialog.popup_centered())
	mode_row.add_child(reset_button)
	champ_reset_button = reset_button
	champ_reset_dialog = ConfirmationDialog.new()
	champ_reset_dialog.title = "Reset championship"
	champ_reset_dialog.dialog_text = "Discard the saved championship standings and restart at round 1?"
	champ_reset_dialog.confirmed.connect(_reset_championship)
	_refocus_after(champ_reset_dialog)
	add_child(champ_reset_dialog)

	champ_info_label = _label("", 13, CmrStyle.TEXT)
	champ_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(champ_info_label)
	champ_side = VBoxContainer.new()
	champ_side.add_theme_constant_override("separation", 6)
	col.add_child(champ_side)
	# (the season's own settings are on the Advanced page; here the calendar and the standings sit side by side)
	var champ_cols := HBoxContainer.new()
	champ_cols.add_theme_constant_override("separation", 24)
	champ_side.add_child(champ_cols)
	var cal_col := _column(champ_cols, 6)
	cal_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cal_col.size_flags_stretch_ratio = 1.25
	cal_col.add_child(_label("CALENDAR", 13, MUTED))
	champ_calendar = GridContainer.new()
	champ_calendar.columns = 3
	champ_calendar.add_theme_constant_override("h_separation", 10)
	champ_calendar.add_theme_constant_override("v_separation", 2)
	cal_col.add_child(champ_calendar)
	var table_col := _column(champ_cols, 6)
	table_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table_col.add_child(_label("STANDINGS", 13, MUTED))
	champ_table = GridContainer.new()
	champ_table.columns = 4
	champ_table.add_theme_constant_override("h_separation", 10)
	champ_table.add_theme_constant_override("v_separation", 2)
	table_col.add_child(champ_table)
	champ_side.hide()

	campaign_side = VBoxContainer.new()
	campaign_side.add_theme_constant_override("separation", 10)
	col.add_child(campaign_side)

	campaign_act_label = _label("ACT I: SILESIAN GRASSROOTS", 15, ACCENT)
	campaign_act_label.visible = false # the page's subtitle already names the act (it read twice, one above the other)
	campaign_side.add_child(campaign_act_label)

	_field_label(campaign_side, "SELECT CAMPAIGN STAGE")
	campaign_stage_picker = MenuSelector.new()
	campaign_stage_picker.custom_minimum_size.y = 42
	_style_control(campaign_stage_picker)
	campaign_stage_picker.item_selected.connect(_select_campaign_stage)
	campaign_side.add_child(campaign_stage_picker)

	var briefing_card := PanelContainer.new()
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(CmrStyle.PANEL, 0.75)
	card_style.border_color = Color(CmrStyle.ORANGE, 0.6)
	card_style.set_border_width_all(1)
	card_style.set_corner_radius_all(4)
	card_style.content_margin_left = 14
	card_style.content_margin_right = 14
	card_style.content_margin_top = 12
	card_style.content_margin_bottom = 12
	briefing_card.add_theme_stylebox_override("panel", card_style)
	campaign_side.add_child(briefing_card)

	var card_col := VBoxContainer.new()
	card_col.add_theme_constant_override("separation", 8)
	briefing_card.add_child(card_col)

	campaign_title_label = _label("Stage 1: Rookie Shakedown", 20, CmrStyle.TEXT)
	campaign_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART # long Polish stage names wrap, never run off the card
	card_col.add_child(campaign_title_label)

	campaign_circuit_label = _label("📍 Circuit: Wilamowice Country Loop", 14, CmrStyle.ORANGE_SOFT)
	campaign_circuit_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_col.add_child(campaign_circuit_label)

	var obj_row := VBoxContainer.new()
	obj_row.add_theme_constant_override("separation", 4)
	card_col.add_child(obj_row)

	campaign_target_label = _label("★ TARGET: Finish P3 or higher", 14, CmrStyle.GREEN)
	obj_row.add_child(campaign_target_label)

	campaign_trophy_label = _label("🏆 Trophy: Wilamowice Bronze Piston", 13, CmrStyle.AMBER)
	obj_row.add_child(campaign_trophy_label)

	campaign_desc_label = _label("", 13, CmrStyle.TEXT)
	campaign_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_col.add_child(campaign_desc_label)

	campaign_tip_label = _label("", 12, MUTED)
	campaign_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_col.add_child(campaign_tip_label)

	campaign_start_button = _button("ENTER STAGE  ▸", ACCENT)
	campaign_start_button.custom_minimum_size.y = 52
	campaign_start_button.add_theme_font_size_override("font_size", 22)
	campaign_start_button.tooltip_text = "Start this campaign stage immediately"
	campaign_start_button.pressed.connect(_start_race)
	campaign_side.add_child(campaign_start_button)

	campaign_world_button = _button("FREE ROAM IN BRZESZCZE  ▸", CmrStyle.ORANGE_SOFT)
	campaign_world_button.custom_minimum_size.y = 42
	campaign_world_button.tooltip_text = "Drive the open world: every stage is a beacon on the map of Brzeszcze"
	campaign_world_button.pressed.connect(func(): _enter_open_world(campaign_stage_index))
	campaign_world_button.visible = OpenWorld.available()
	campaign_side.add_child(campaign_world_button)

	campaign_side.hide()

	_build_rally_side(col)

	_menu_rule(col)
	setup_rule_divider = col.get_child(-1)

	# the core choices as captioned rows: circuit, laps (or hours), opponents, difficulty, weather
	track_picker = MenuSelector.new()
	for name in TRACK_NAMES:
		track_picker.add_item(name)
	_style_control(track_picker)
	track_picker.item_selected.connect(_select_track)
	_core_row(col, "CIRCUIT", track_picker)
	track_label = track_picker.get_meta("caption")

	tt_start_picker = MenuSelector.new()
	tt_start_picker.add_item("Standing start")
	tt_start_picker.add_item("Rolling start")
	_style_control(tt_start_picker)
	tt_start_picker.item_selected.connect(func(_i: int) -> void: _update_menu_car_summary())
	tt_start_row = _core_row(col, "START", tt_start_picker)
	tt_start_row.visible = false

	var format_rows := VBoxContainer.new() # LAPS or HOURS: the race format is picked on the Advanced page
	format_rows.add_theme_constant_override("separation", 8)
	col.add_child(format_rows)
	setup_format_row = format_rows
	laps_picker = _make_spin(1, 99, 6)
	_core_row(format_rows, "LAPS", laps_picker)
	laps_picker.value_changed.connect(func(_value: float) -> void: _update_menu_car_summary())
	hours_picker = _make_spin(0.25, 24, 1, 0.25)
	_core_row(format_rows, "HOURS", hours_picker)
	hours_picker.value_changed.connect(func(_value: float) -> void: _update_menu_car_summary())
	hours_picker.get_parent().visible = false

	var conditions := VBoxContainer.new()
	conditions.add_theme_constant_override("separation", 8)
	col.add_child(conditions)
	setup_conditions_row = conditions
	opponents_picker = _make_spin(0, 15, 12)
	_core_row(conditions, "OPPONENTS", opponents_picker)
	opponents_picker.tooltip_text = "Cars against you. 0 = solo time trial: hot-lap alone against your ghost and lap records"
	opponents_picker.value_changed.connect(func(_v: float) -> void: _update_opponents_label())
	difficulty_picker = _make_option(["Easy", "Medium", "Hard", "Alien"])
	_core_row(conditions, "DIFFICULTY", difficulty_picker)
	difficulty_picker.selected = 1
	weather_picker = _make_option(["Dry", "Wet", "Snow", "Hail", "Fog", "Variable"])
	_core_row(conditions, "WEATHER", weather_picker)
	weather_picker.item_selected.connect(func(_index: int) -> void: _update_information_page())

	# the rest lives on two more pages, as titled groups that are always open (no accordions)
	adv_page = _page_panel("AdvancedPage", 0.045, 0.98)
	advanced_panel = adv_page.panel
	var adv_cols := HBoxContainer.new()
	adv_cols.add_theme_constant_override("separation", 30)
	(adv_page.column as VBoxContainer).add_child(adv_cols)
	var adv_left := _column(adv_cols, 18)
	adv_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var adv_right := _column(adv_cols, 18)
	adv_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	car_page = _page_panel("CarPage", 0.52, 0.98)
	car_panel = car_page.panel
	var car_col: VBoxContainer = car_page.column
	strat_page = _page_panel("StrategyPage", 0.045, 0.98)
	strategy_panel = strat_page.panel

	var season_body := _group(adv_left, "season", "SEASON SET-UP")
	var calendar_body := _group(adv_right, "calendar", "CALENDAR · TICK THE CIRCUITS")
	_build_season_box(season_body, calendar_body)
	_build_mods_box(_fold_section(adv_right, "mods", "MODIFIERS · FAN LEVEL REWARDS"))
	var race_row := HBoxContainer.new()
	race_row.add_theme_constant_override("separation", 14)
	_group(adv_left, "race", "FORMAT & START TIME").add_child(race_row)
	var format_col := VBoxContainer.new()
	format_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	race_row.add_child(format_col)
	_field_label(format_col, "RACE FORMAT")
	format_picker = MenuSelector.new()
	format_picker.add_item("Lap race")
	format_picker.add_item("Timed endurance")
	format_picker.custom_minimum_size.y = 40
	_style_control(format_picker)
	format_picker.item_selected.connect(_select_format)
	format_col.add_child(format_picker)
	start_hour_picker = _spin(race_row, "START HOUR", 0, 23.75, 14, 0.25)
	start_hour_picker.tooltip_text = "Time of day at the start; a long race runs on into the evening or the night"
	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 14)
	_group(adv_left, "driving", "GEARBOX, AIDS & GRID").add_child(row3)
	setup_driving_row = row3
	gearbox_picker = _option_field(row3, "TRANSMISSION", ["Automatic", "Manual (E/Q)"])
	assists_picker = _option_field(row3, "DRIVING AIDS", ["Full assists", "ABS only", "Off"])
	assists_picker.tooltip_text = "Full assists: ABS, traction and stability control, and help steering and braking for corners. ABS only: just the anti-lock brakes. Off: none"
	grid_picker = _option_field(row3, "GRID POSITION", ["Pole", "Middle", "Back", "Random"])

	var driver := _group(car_col, "driver", "DRIVER & PAINT")
	var profile_row := HBoxContainer.new()
	profile_row.add_theme_constant_override("separation", 14)
	driver.add_child(profile_row)
	var name_col := VBoxContainer.new()
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_col.size_flags_stretch_ratio = 2.0
	profile_row.add_child(name_col)
	_field_label(name_col, "DRIVER NAME")
	player_name_edit = LineEdit.new()
	player_name_edit.text = "You"
	player_name_edit.placeholder_text = "Driver name"
	player_name_edit.custom_minimum_size.y = 40
	player_name_edit.tooltip_text = "Type your name; ↑ ↓ leave the field"
	name_col.add_child(player_name_edit)
	player_number_picker = _spin(profile_row, "CAR NO.", 1, 99, 9)
	var paint_col := VBoxContainer.new()
	paint_col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	profile_row.add_child(paint_col)
	_field_label(paint_col, "PAINT")
	player_color_picker = ColorPickerButton.new()
	player_color_picker.color = Color("#b3121d")
	player_color_picker.custom_minimum_size = Vector2(76, 40)
	player_color_picker.tooltip_text = "◂ ▸ step through the stock paints; Enter picks a swatch or mixes your own"
	for c in PAINTS:
		player_color_picker.get_picker().add_preset(Color(c))
	paint_col.add_child(player_color_picker)
	# the car, its finish and the stripes get a row of their own so the pickers have room for their names
	var livery_row := HBoxContainer.new()
	livery_row.add_theme_constant_override("separation", 14)
	driver.add_child(livery_row)
	car_class_picker = _option_field(livery_row, "CAR", ["Seicento 900", "Hypercar Seicento"])
	car_class_picker.tooltip_text = "The Hypercar Seicento (a Seicento with a Ferrari 499P's power, AWD, in AF Corse's no. 83 yellow) opens at the top fan level"
	car_class_picker.item_selected.connect(_on_car_class_selected)
	player_finish_picker = _option_field(livery_row, "FINISH", ["Gloss", "Metallic", "Martini Racing", "Abarth", "Marlboro"])
	var stripes_col := VBoxContainer.new()
	stripes_col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	livery_row.add_child(stripes_col)
	_field_label(stripes_col, "STRIPES")
	player_stripes_toggle = _check_field(stripes_col, "Twin stripes", true)
	player_stripes_toggle.custom_minimum_size.y = 40
	player_finish_picker.tooltip_text = "Metallic flake paint, or a sponsor livery: Martini Racing or Marlboro on a white car, the Abarth kit over your paint"
	player_finish_picker.item_selected.connect(func(_index: int) -> void: _update_menu_car_summary())
	player_color_picker.color_changed.connect(func(_color: Color) -> void: _update_menu_car_summary())
	player_stripes_toggle.toggled.connect(func(_enabled: bool) -> void: _update_menu_car_summary())
	player_name_edit.text_changed.connect(func(_text: String) -> void: _update_driver_summary())
	player_number_picker.value_changed.connect(func(_value: float) -> void: _update_driver_summary())

	_build_car_setup(_group(car_col, "car", "CAR SET-UP"))
	_build_strategy_section(_group(strat_page.column, "strategy", "PIT STRATEGY"))

	var rules := _group(adv_right, "rules", "RULES & AI")
	var row5 := HBoxContainer.new()
	row5.add_theme_constant_override("separation", 14)
	rules.add_child(row5)
	wear_picker = _spin(row5, "TYRE WEAR ×", 0.5, 5, 2, 0.5)
	wear_picker.tooltip_text = "How fast tyres wear; each circuit sets its own when you pick it"
	fuel_picker = _spin(row5, "FUEL USE ×", 0.5, 20, 1, 0.5)
	fuel_picker.tooltip_text = "How fast the tank empties; each circuit sets its own when you pick it"
	crew_picker = _option_field(row5, "PIT CREW", ["Pro", "Club", "Amateur"])
	crew_picker.tooltip_text = "How quickly the crew changes tyres and refuels"
	var row6 := HBoxContainer.new()
	row6.add_theme_constant_override("separation", 10)
	rules.add_child(row6)
	mandatory_stop_toggle = _check_field(row6, "Mandatory stop", true)
	mandatory_stop_toggle.tooltip_text = "Every car must make at least one pit stop"
	two_compounds_toggle = _check_field(row6, "Two dry tyres", false)
	two_compounds_toggle.tooltip_text = "Every car must race on two different dry compounds"
	refuel_toggle = _check_field(row6, "Refuelling", true)
	refuel_toggle.tooltip_text = "Off: the car starts with all the fuel it needs and stops only for tyres"
	var row7 := HBoxContainer.new()
	row7.add_theme_constant_override("separation", 10)
	rules.add_child(row7)
	collisions_toggle = _check_field(row7, "Car contact", true)
	collisions_toggle.tooltip_text = "Off: cars pass through each other"
	strategist_toggle = _check_field(row7, "Auto strategist", false)
	strategist_toggle.tooltip_text = "On: the strategist boxes you by itself. Off: it only advises and you press P to call the stop"
	parallel_toggle = _check_field(row7, "Parallel service", false)
	parallel_toggle.tooltip_text = "Tyres and fuel go in at the same time instead of one after the other"
	var row8 := HBoxContainer.new()
	row8.add_theme_constant_override("separation", 10)
	rules.add_child(row8)
	draft_toggle = _check_field(row8, "Slipstream", true)
	draft_toggle.tooltip_text = "A car close behind another pulls less air and gains speed; the tow builds and fades over about a second"
	race_control_toggle = _check_field(row8, "Race control", true)
	race_control_toggle.tooltip_text = "Flags, safety car, red flags, stewards' penalties and crash damage"
	dynamic_toggle = _check_field(row8, "Live wear and stops", true)
	dynamic_toggle.tooltip_text = "Tyre wear and fuel follow how hard each car is driven, and pit stops follow the live state of tyres and tank instead of the starting plan"
	var row9 := HBoxContainer.new()
	row9.add_theme_constant_override("separation", 10)
	rules.add_child(row9)
	damage_toggle = _check_field(row9, "Mechanical damage", false)
	damage_toggle.tooltip_text = "Off: crashes only dent and scuff the bodywork. On: they cost power, grip and parts, for you and every rival alike (rally stages and championships with damage always have it)"
	var bot_row := HBoxContainer.new()
	bot_row.add_theme_constant_override("separation", 14)
	rules.add_child(bot_row)
	ai_learning_picker = _option_field(bot_row, "AI LEARNING", ["On", "Off"])
	ai_learning_picker.tooltip_text = "On: the bots study how you drive each circuit and race you accordingly"
	bot_physics_picker = _option_field(bot_row, "BOT PHYSICS", ["Full physics", "Rail model", "Nearby only"])
	bot_physics_picker.tooltip_text = "Rail model and Nearby only use much less CPU (better battery life). Nearby only runs the full physics just for cars near you"
	var memory_row := HBoxContainer.new()
	memory_row.add_theme_constant_override("separation", 10)
	rules.add_child(memory_row)
	ai_memory_label = _label("", 13, CmrStyle.TEXT)
	ai_memory_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ai_memory_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	memory_row.add_child(ai_memory_label)
	ai_forget_button = _button("FORGET", DANGER)
	ai_forget_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ai_forget_button.tooltip_text = "Make the bots forget what they learned about you here"
	ai_forget_button.pressed.connect(_forget_ai_memory)
	memory_row.add_child(ai_forget_button)
	var record_row := HBoxContainer.new()
	record_row.add_theme_constant_override("separation", 10)
	rules.add_child(record_row)
	record_label = _label("", 13, CmrStyle.TEXT)
	record_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	record_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	record_row.add_child(record_label)
	record_forget_button = _button("FORGET", DANGER)
	record_forget_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	record_forget_button.tooltip_text = "Delete your lap records and their ghosts here"
	record_forget_button.pressed.connect(_forget_lap_records)
	record_row.add_child(record_forget_button)

	status_label = _label("", 13, ACCENT)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(status_label)

	setup_race_button = _button("RACE  ▸", ACCENT)
	setup_race_button.custom_minimum_size.y = 52
	setup_race_button.add_theme_font_size_override("font_size", 24)
	setup_race_button.tooltip_text = "Start the race (H shows all the keys while racing)"
	setup_race_button.pressed.connect(_start_race)
	page.add_child(setup_race_button)

	setup_hint = _label("", 12, MUTED)
	setup_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	setup_hint.custom_minimum_size = Vector2(1, 44) # room for a short description over the keys, so RACE stays put
	setup_hint.max_lines_visible = 3
	setup_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	page.add_child(setup_hint)
	get_viewport().gui_focus_changed.connect(_setup_focus_changed)

	for picker in [weather_picker, crew_picker]:
		picker.item_selected.connect(func(_i: int) -> void: _queue_strategy_refresh())
	for spin in [laps_picker, hours_picker, wear_picker, fuel_picker]:
		spin.value_changed.connect(func(_v: float) -> void: _queue_strategy_refresh())
	for toggle in [mandatory_stop_toggle, two_compounds_toggle, refuel_toggle, parallel_toggle]:
		toggle.toggled.connect(func(_on: bool) -> void: _queue_strategy_refresh())
	ai_learning_picker.item_selected.connect(func(_i: int) -> void: _update_ai_memory())
	quali_picker.item_selected.connect(func(_i: int) -> void: _update_championship_view())
	_load_race_settings()
	_update_championship_view()
	_update_menu_car_summary()
	_update_driver_summary()
	_update_ai_memory()
	_queue_strategy_refresh()

## A set-up section that folds away behind its heading: Enter (or ▸ / ◂) on the heading opens or shuts it. The
## heading carries a summary so a shut section still says what it holds; the page remembers which are open.
func _fold_section(parent: VBoxContainer, key: String, title: String, rule := true) -> VBoxContainer:
	if rule:
		_menu_rule(parent)
	var head := Button.new()
	head.flat = true
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.custom_minimum_size = Vector2(1, 34) # a long summary trims instead of widening the column
	head.add_theme_font_size_override("font_size", 16)
	head.add_theme_color_override("font_color", CmrStyle.TEXT)
	head.add_theme_color_override("font_focus_color", CmrStyle.TEXT)
	for c in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		head.add_theme_color_override(c, ACCENT)
	head.tooltip_text = "A / Enter or ◂ ▸ shows or hides these settings"
	head.pressed.connect(func() -> void: _open_section(key, not setup_open[key]))
	parent.add_child(head)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	parent.add_child(body)
	setup_folds[key] = {"head": head, "body": body, "title": title, "summary": ""}
	_open_section(key, setup_open.get(key, false), false)
	return body

## A titled group of settings on the Advanced or Car page: a heading, a rule and the settings, always open.
func _group(parent: Control, key: String, title: String) -> VBoxContainer:
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", 8)
	parent.add_child(group)
	var head := _label(title, 15, ACCENT)
	head.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS # a long summary trims instead of widening the column
	group.add_child(head)
	_menu_rule(group)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	group.add_child(body)
	setup_folds[key] = {"head": head, "body": body, "group": group, "title": title, "summary": "", "fixed": true}
	setup_open[key] = true
	return body

## A page of settings beside the car: the panel holds a scroll (only used when a page runs long), RACE
## and the key hint.
func _page_panel(page_name: String, left: float, right: float) -> Dictionary:
	var panel := _panel(Vector2(0, 0))
	panel.name = page_name
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.anchor_left = left
	panel.anchor_right = right
	panel.anchor_top = 0.17
	panel.anchor_bottom = 0.96
	panel.offset_left = 0
	panel.offset_right = 0
	panel.offset_top = 0
	panel.offset_bottom = 0
	add_child(panel)
	panel.hide()
	var page := _column(panel, 8)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	page.add_child(scroll)
	var gutter := MarginContainer.new()
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_theme_constant_override("margin_right", 16)
	gutter.add_theme_constant_override("margin_left", 3)
	scroll.add_child(gutter)
	var column := _column(gutter, 18)
	var race_button := _button("RACE  ▸", ACCENT)
	race_button.custom_minimum_size.y = 46
	race_button.add_theme_font_size_override("font_size", 22)
	race_button.pressed.connect(_start_race)
	page.add_child(race_button)
	var hint := _label("", 12, MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(1, 44)
	hint.max_lines_visible = 3
	hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	page.add_child(hint)
	return {"panel": panel, "scroll": scroll, "column": column, "hint": hint, "race": race_button}

## A captioned row of the Set Up page: the caption on the left, the setting on the right.
func _core_row(parent: Control, caption: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.custom_minimum_size.y = 42
	parent.add_child(row)
	var cap := _label(caption, 15, MUTED)
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(cap)
	control.size_flags_horizontal = Control.SIZE_SHRINK_END
	control.custom_minimum_size = Vector2(300, 40)
	row.add_child(control)
	control.set_meta("caption", cap) # lit while the setting has the keyboard (_setup_focus_changed)
	return row

func _open_section(key: String, open: bool, save := true) -> void:
	if setup_folds[key].get("fixed", false):
		return # a titled group is always open
	setup_open[key] = open
	(setup_folds[key].body as Control).visible = open
	_fold_heading(key)
	if save:
		_save_race_settings()

func _set_section_summary(key: String, summary: String) -> void:
	if setup_folds.has(key):
		setup_folds[key].summary = summary
		_fold_heading(key)

func _fold_heading(key: String) -> void:
	var f: Dictionary = setup_folds[key]
	var head: Control = f.head
	var arrow := "" if f.get("fixed", false) else ("▾  " if setup_open[key] else "▸  ")
	head.set("text", "%s%s%s" % [arrow, f.title, "" if f.summary == "" else "      " + f.summary])

func _update_driver_summary() -> void:
	if is_instance_valid(player_name_edit):
		var who := player_name_edit.text.strip_edges()
		_set_section_summary("driver", "%s  ·  NO. %d" % [(who if who != "" else "You").to_upper(), int(player_number_picker.value)])

func _update_rules_summary() -> void:
	var rules: Array[String] = ["TYRES ×%.1f" % wear_picker.value, "FUEL ×%.1f" % fuel_picker.value, crew_picker.get_item_text(crew_picker.selected).to_upper() + " CREW"]
	if not refuel_toggle.button_pressed:
		rules.append("NO REFUEL")
	_set_section_summary("rules", "  ·  ".join(rules))

## The set-up page's settings in keyboard order: down each column, left to right across a row, then RACE.
## The Advanced, Car or Strategy page's parts ({} for any other page).
func _extra_page(page: String) -> Dictionary:
	match page:
		"advanced": return adv_page
		"car": return car_page
		"strategy": return strat_page
	return {}

func _setup_focus_items() -> Array[Control]:
	var out: Array[Control] = []
	var root: Control = setup_column
	var race_button := setup_race_button
	var extra := _extra_page(active_menu_page)
	if not extra.is_empty():
		root = extra.column
		race_button = extra.race
	_collect_focusable(root, out)
	if race_button.visible: # a campaign stage starts from its briefing's ENTER STAGE instead
		out.append(race_button)
	return out

func _collect_focusable(node: Node, out: Array[Control]) -> void:
	for child in node.get_children():
		var c := child as Control
		if c == null or not c.visible:
			continue
		if c is SpinBox:
			out.append((c as SpinBox).get_line_edit()) # the box takes the keyboard through its text field
		elif c.focus_mode == Control.FOCUS_ALL:
			if not (c is BaseButton and (c as BaseButton).disabled):
				out.append(c)
		else:
			_collect_focusable(c, out)

func _focus_setup_item(items: Array[Control], index: int) -> void:
	_setup_focus_at = clampi(index, 0, items.size() - 1)
	items[_setup_focus_at].grab_focus()
	_reveal_setting.call_deferred(items[_setup_focus_at])

## Scroll the whole row of a focused setting into view (follow_focus alone shows just the control, so a
## caption above it or a label beside it can stay cut off at the edge).
func _reveal_setting(item: Control) -> void:
	if not is_instance_valid(item) or not item.is_visible_in_tree():
		return
	var scroll: Node = item.get_parent()
	while scroll != null and not scroll is ScrollContainer:
		scroll = scroll.get_parent()
	if scroll == null:
		return
	var target := item
	var up := item.get_parent()
	for i in 3:
		if up is HBoxContainer:
			target = up
			break
		if up == scroll or not up is Control:
			break
		up = up.get_parent()
	if item.has_meta("caption"):
		(scroll as ScrollContainer).ensure_control_visible(item.get_meta("caption"))
	(scroll as ScrollContainer).ensure_control_visible(target)

## Where the keyboard starts on the set-up page: the circuit, or the first setting of a championship.
func _focus_setup_default() -> void:
	if race:
		return
	if active_menu_page in ["advanced", "car", "strategy"]:
		var page_items := _setup_focus_items()
		if not page_items.is_empty():
			_focus_setup_item(page_items, 0)
		return
	if active_menu_page != "setup":
		return
	var items := _setup_focus_items()
	if is_campaign_mode:
		var at := items.find(campaign_start_button)
		if at < 0:
			at = items.find(campaign_stage_picker)
		if at >= 0:
			_focus_setup_item(items, at)
			_show_briefing_top.call_deferred()
			return
	var at := items.find(track_picker)
	if at < 0:
		at = 0
		while at < items.size() - 1 and items[at] == champ_reset_button:
			at += 1
	_focus_setup_item(items, at)

## The briefing from its top (page heading, act, stage), scrolled only as far as ENTER STAGE needs and never
## so far that the page heading ("CAMPAIGN · STAGE 7/9") leaves the view. The briefing's texts were only just set (their wrapped heights
## settle a frame or two later) and focusing ENTER STAGE scrolls the page on its own, deferred: so this waits
## for both before it measures and places the scroll.
func _show_briefing_top(frames := 2) -> void:
	if frames > 0:
		# one-shot frame hooks rather than await: they go away with the node if the page is torn down first
		var next := _show_briefing_top.bind(frames - 1)
		if not get_tree().process_frame.is_connected(next):
			get_tree().process_frame.connect(next, CONNECT_ONE_SHOT)
		return
	if not is_instance_valid(menu_scroll) or not is_campaign_mode or active_menu_page != "setup":
		return
	menu_scroll.scroll_vertical = roundi(_briefing_scroll())

## Where the set-up page's scroll should sit for the campaign briefing (see _show_briefing_top).
func _briefing_scroll() -> float:
	if not is_instance_valid(campaign_start_button) or not campaign_start_button.is_visible_in_tree():
		return 0.0
	var content := menu_scroll.get_child(0) as Control
	var top := content.global_position.y
	var view := menu_scroll.size.y
	var need := campaign_start_button.global_position.y - top + campaign_start_button.size.y + 8.0 - view
	var target_label: Control = campaign_title_label if is_instance_valid(campaign_title_label) else setup_title_label
	var keep := target_label.global_position.y - top # the stage title stays in view
	return clampf(need, 0.0, maxf(0.0, keep))

## ◂ ▸ on a set-up control: step a picker, number, switch, slider or paint, or open/shut a section.
func _nudge_setting(c: Control, d: int, echo: bool) -> void:
	if c is LineEdit and c.get_parent() is SpinBox:
		var spin := c.get_parent() as SpinBox
		spin.apply() # take what was typed first
		spin.value += d * spin.step
		(c as LineEdit).select_all()
	elif c is MenuSelector:
		(c as MenuSelector).step(d) # (a browse-only list just shows the next entry)
	elif c is CheckButton:
		if not echo:
			(c as CheckButton).button_pressed = not (c as CheckButton).button_pressed
	elif c is Slider:
		(c as Slider).value += d * (c as Slider).step
	elif c is ColorPickerButton:
		var pick := c as ColorPickerButton
		var near := 0
		for i in PAINTS.size():
			if _colour_gap(Color(PAINTS[i]), pick.color) < _colour_gap(Color(PAINTS[near]), pick.color):
				near = i
		pick.color = Color(PAINTS[posmod(near + d, PAINTS.size())])
		pick.color_changed.emit(pick.color)
	else:
		for key in setup_folds:
			if setup_folds[key].head == c and setup_open[key] != (d > 0):
				_open_section(key, d > 0)

static func _colour_gap(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)

## A gamepad's A on the focused set-up control (the keyboard's Enter is the GUI's own ui_accept).
func _press_setup_item(c: Control) -> void:
	if c is MenuSelector:
		(c as MenuSelector).activate(0 if (c as MenuSelector).browse_only else 1)
	elif c is ColorPickerButton or (c is LineEdit and c.get_parent() is SpinBox):
		_nudge_setting(c, 1, false)
	elif c is CheckButton:
		(c as CheckButton).button_pressed = not (c as CheckButton).button_pressed
	elif c is BaseButton:
		(c as BaseButton).pressed.emit()

## Menu keys and gamepad buttons, ahead of the controls (a spin box would take ↑ ↓ and a slider ◂ ▸ for
## itself): on every front-end page Esc / B goes back to the main menu, Q E / LB RB switch the header pages,
## START races (or leaves the service area); ↑ ↓ ◂ ▸ and Enter / A work the page's list. The left stick works
## as the d-pad. The main menu's own keys are in _unhandled_input / _unhandled_key_input.
func _input(event: InputEvent) -> void:
	if race or _starting or not menu_tint.visible:
		return
	if not get_viewport().get_embedded_subwindows().filter(func(w: Window) -> bool: return w.visible).is_empty():
		return # a confirmation is open: it has the keys (A and B work it as Enter and Esc)
	if event is InputEventJoypadMotion:
		_stick_as_dpad(event as InputEventJoypadMotion)
		return
	if not (event is InputEventKey or event is InputEventJoypadButton) or not event.is_pressed():
		return
	if event is InputEventKey and (event.ctrl_pressed or event.meta_pressed or event.alt_pressed):
		return # Cmd+Q and the like are the system's
	var page := active_menu_page
	if page == "home" or (page == "setup" and not setup_panel.visible):
		return
	var owner := get_viewport().gui_get_focus_owner()
	var typing := owner == player_name_edit
	var key: Key = event.keycode if event is InputEventKey else KEY_NONE
	var pad: JoyButton = event.button_index if event is InputEventJoypadButton else JOY_BUTTON_INVALID
	var echo: bool = event.is_echo()
	if key == KEY_ESCAPE or pad == JOY_BUTTON_B or (key == KEY_BACKSPACE and not typing and page != "setup"):
		if not echo:
			_show_home()
	elif page in MENU_PAGE_IDS and ((key in [KEY_Q, KEY_PAGEUP] and not typing) or pad == JOY_BUTTON_LEFT_SHOULDER):
		if not echo:
			_step_menu_page(-1)
	elif page in MENU_PAGE_IDS and ((key in [KEY_E, KEY_PAGEDOWN] and not typing) or pad == JOY_BUTTON_RIGHT_SHOULDER):
		if not echo:
			_step_menu_page(1)
	elif pad == JOY_BUTTON_START and page in MENU_PAGE_IDS:
		if page == "repair" and _servicing():
			_continue_from_service()
		else:
			_start_race()
	elif page == "repair":
		match [key, pad]:
			[KEY_UP, _], [_, JOY_BUTTON_DPAD_UP]: _select_repair_part(repair_selected - 1)
			[KEY_DOWN, _], [_, JOY_BUTTON_DPAD_DOWN]: _select_repair_part(repair_selected + 1)
			[KEY_ENTER, _], [KEY_KP_ENTER, _], [_, JOY_BUTTON_A]: _repair_selected()
			[KEY_SPACE, _]:
				if _servicing():
					_continue_from_service()
			_: return
	elif page in ["setup", "advanced", "car", "strategy", "options"]:
		var items := _options_focus_items() if page == "options" else _setup_focus_items()
		if items.is_empty():
			return
		var at := items.find(owner)
		var dy := 0
		var dx := 0
		match [key, pad]:
			[KEY_UP, _], [_, JOY_BUTTON_DPAD_UP]: dy = -1
			[KEY_DOWN, _], [_, JOY_BUTTON_DPAD_DOWN]: dy = 1
			[KEY_LEFT, _], [_, JOY_BUTTON_DPAD_LEFT]: dx = -1
			[KEY_RIGHT, _], [_, JOY_BUTTON_DPAD_RIGHT]: dx = 1
			[KEY_HOME, _]: dy = -items.size()
			[KEY_END, _]: dy = items.size()
			[_, JOY_BUTTON_A]: pass
			_: return
		if typing and (dx != 0 or key in [KEY_HOME, KEY_END]):
			return # the caret's keys while the name is typed
		if at < 0:
			if page != "options":
				_focus_setup_item(items, _setup_focus_at) # nothing picked yet (or it went away): the first press picks
			else:
				items[0].grab_focus()
		elif dy != 0:
			if page != "options":
				_focus_setup_item(items, at + dy)
			else:
				items[clampi(at + dy, 0, items.size() - 1)].grab_focus()
		elif dx != 0:
			_nudge_setting(owner, dx, echo)
		elif pad == JOY_BUTTON_A:
			_press_setup_item(owner)
	else:
		return
	get_viewport().set_input_as_handled()

## The left stick as a d-pad on the menus: one step each time it is pushed past half way.
func _stick_as_dpad(ev: InputEventJoypadMotion) -> void:
	if ev.axis != JOY_AXIS_LEFT_X and ev.axis != JOY_AXIS_LEFT_Y:
		return
	var idx := 0 if ev.axis == JOY_AXIS_LEFT_X else 1
	get_viewport().set_input_as_handled() # (the GUI would move the focus on its own as well)
	if absf(ev.axis_value) < 0.35:
		_stick_latch[idx] = 0
		return
	if absf(ev.axis_value) < 0.6 or _stick_latch[idx] != 0:
		return
	var dir := 1 if ev.axis_value > 0.0 else -1
	_stick_latch[idx] = dir
	var button: JoyButton
	if idx == 0:
		button = JOY_BUTTON_DPAD_RIGHT if dir > 0 else JOY_BUTTON_DPAD_LEFT
	else:
		button = JOY_BUTTON_DPAD_DOWN if dir > 0 else JOY_BUTTON_DPAD_UP
	for pressed in [true, false]:
		var press := InputEventJoypadButton.new()
		press.device = ev.device
		press.button_index = button
		press.pressed = pressed
		Input.parse_input_event(press)

func _step_menu_page(direction: int) -> void:
	var ids := _menu_page_ids()
	var at := ids.find(active_menu_page)
	if at < 0:
		return
	var to := clampi(at + direction, 0, ids.size() - 1)
	if to != at:
		(menu_tab_buttons[MENU_PAGES[MENU_PAGE_IDS.find(ids[to])]] as Button).pressed.emit()

## The pages Q E / LB RB step through (the tabs that are showing).
func _menu_page_ids() -> Array:
	var ids: Array = []
	for t in _menu_tab_titles():
		ids.append(MENU_PAGE_IDS[MENU_PAGES.find(t)])
	return ids

func _menu_tab_titles() -> Array:
	var titles: Array = TOP_MENU_TABS.duplicate()
	if not _servicing():
		titles.erase("Service")
	if is_campaign_mode or is_championship_mode or is_rally_mode:
		titles.erase("Strategy") # the season, stage or event sets the pit rules
	return titles

## Strategy shows for a quick race or time trial, Service where a car carries on to another event
## (a championship with damage on, the rally); a divider only sits between two tabs that are showing.
func _refresh_service_tab() -> void:
	if not menu_tab_buttons.has("Service"):
		return
	var titles := _menu_tab_titles()
	for i in TOP_MENU_TABS.size():
		var title: String = TOP_MENU_TABS[i]
		(menu_tab_buttons[title] as Control).visible = title in titles
		if menu_tab_dividers.has(title):
			var at := titles.find(title)
			(menu_tab_dividers[title] as Control).visible = at >= 0 and at < titles.size() - 1

## The hint under RACE follows the keyboard: the focused setting's description over the menu keys, and the
## setting's caption lit in orange.
func _setup_focus_changed(control: Control) -> void:
	if is_instance_valid(_lit_caption):
		_lit_caption.add_theme_color_override("font_color", _lit_caption_color)
	_lit_caption = null
	var panel: Control = setup_panel
	var hint: Label = setup_hint
	var extra := _extra_page(active_menu_page)
	if not extra.is_empty():
		panel = extra.panel
		hint = extra.hint
	if not is_instance_valid(panel) or not is_instance_valid(hint):
		return
	var keys := _hint(active_menu_page)
	if control == null or not panel.is_ancestor_of(control):
		hint.text = keys
		return
	var setting: Control = control.get_parent() if control.get_parent() is SpinBox else control
	var items := _setup_focus_items()
	if items.has(control):
		_setup_focus_at = items.find(control)
	hint.text = "%s\n%s" % [setting.tooltip_text, keys] if setting.tooltip_text != "" else keys
	var caption: Label = setting.get_meta("caption") if setting.has_meta("caption") else null
	var holder := setting.get_parent()
	if caption == null and holder is VBoxContainer and holder.get_child(0) is Label and holder.get_child_count() == 2:
		caption = holder.get_child(0) # a _spin / _option_field column: caption over the control
	if caption:
		_lit_caption = caption
		_lit_caption_color = caption.get_theme_color("font_color")
		caption.add_theme_color_override("font_color", ACCENT)

func _build_strategy_section(parent: VBoxContainer) -> void:
	strategy_section = VBoxContainer.new()
	strategy_section.add_theme_constant_override("separation", 6)
	parent.add_child(strategy_section)
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
	var plan := _fold_section(custom_box, "plan", "BUILD YOUR OWN PLAN", false)
	custom_rows = VBoxContainer.new()
	custom_rows.add_theme_constant_override("separation", 4)
	plan.add_child(custom_rows)
	var add := _button("+ STINT", CmrStyle.FIELD)
	add.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add.pressed.connect(func() -> void:
		var base := _editor_stints()
		var last: Dictionary = base[-1] if base.size() else {"c": "M", "laps": 1}
		base.append({"c": last.c, "laps": 1})
		_set_custom(base, true)
	)
	plan.add_child(add)
	custom_eval = _label("", 13, CmrStyle.TEXT)
	custom_eval.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	plan.add_child(custom_eval)

## Laps the strategist plans for: the lap count, or the expected laps of a timed race.
func _race_laps(track: Track) -> int:
	if format_picker.selected == 1:
		return strategy.estimate_laps(track, hours_picker.value * 3600.0, {
			"fuel_mult": fuel_picker.value, "weather": ["dry", "wet", "snow", "hail", "fog", "variable"][weather_picker.selected],
			"wear_mult": wear_picker.value, "crew": ["pro", "club", "amateur"][crew_picker.selected],
			"parallel": parallel_toggle.button_pressed, "refuel": refuel_toggle.button_pressed,
		})
	return int(laps_picker.value)

## `weather` is the race's ("dry", "wet", …); empty takes the set-up page's picker.
func _plan_opts(track: Track, laps: int, wear_mult: float, weather := "") -> Dictionary:
	if weather == "":
		weather = ["dry", "wet", "snow", "hail", "fog", "variable"][weather_picker.selected]
	return {
		"track": track, "laps": laps, "wet": 0.85 if weather in ["wet", "snow", "hail"] else (0.15 if weather == "variable" else 0.0),
		"wear_mult": wear_mult, "fuel_mult": fuel_picker.value,
		"rules": {"mandatory_stop": mandatory_stop_toggle.button_pressed, "two_compounds": two_compounds_toggle.button_pressed, "refuel": refuel_toggle.button_pressed},
		"crew": ["pro", "club", "amateur"][crew_picker.selected], "parallel": parallel_toggle.button_pressed,
	}

## Any setting that changes the race drops a hand-built plan and goes back to the fastest option.
func _queue_strategy_refresh(reset_choice := true) -> void:
	if _loading_settings or not is_instance_valid(strategy_list):
		return
	_update_rules_summary()
	if reset_choice:
		strategy_choice = 0
		custom_stints = []
	if _strategy_pending:
		return
	_strategy_pending = true
	_refresh_strategy.call_deferred()

func _refresh_strategy() -> void:
	var hyper := is_instance_valid(car_class_picker) and car_class_picker.selected == 1 and _hypercar_open()
	var models: Dictionary = _models_for("hypercar" if hyper else "stock")
	var strat: Strategy = models.strategy
	var cm: CarModel = models.car_model
	var track := Race.get_track(TRACK_KEYS[track_picker.selected])
	if not hyper and track.cal.is_empty():
		# the first plan on a circuit simulates reference laps (up to a couple of seconds)
		strategy_info.text = "Working out lap times at %s…" % track.name
		current_plan = null
		for child in strategy_list.get_children():
			child.queue_free()
		custom_box.hide()
		await get_tree().process_frame
		await get_tree().process_frame
		# the prefetcher works it out off the main thread: wait for it rather than freeze the page
		_prioritise_track_prefetch(track.key)
		while track.cal.is_empty() and _track_prefetch_pending(track.key) and track == Race.get_track(TRACK_KEYS[track_picker.selected]):
			await get_tree().process_frame
		if track != Race.get_track(TRACK_KEYS[track_picker.selected]):
			_strategy_pending = false
			_queue_strategy_refresh(false)
			return
	_strategy_pending = false
	var cal := strat.calibrate(track)
	var laps := _race_laps(track)
	var po := _plan_opts(track, laps, wear_picker.value)
	var plan_opts := po.duplicate()
	plan_opts["diverse"] = true
	strategy_options = strat.plan(plan_opts).slice(0, 7)
	var fpl: float = cal.fuel_per_lap * fuel_picker.value
	var tank: float = cm.spec.tank
	var lap := Strategy.lap_time(cal, tyre_model.compound_grip("M", po.wet) * 0.95 * 0.95, cm.mass_with_fuel(10.0))
	var stop: float = cal.pit_drive_loss + Strategy.service_time(po.crew, po.parallel, true, fpl * 3.0 if refuel_toggle.button_pressed else 0.0)
	var lives := []
	var all_short := true
	for c in Tyres.KEYS:
		var life := strat.tyre_life_laps(track, c, po.wet, wear_picker.value)
		all_short = all_short and life < 1.0
		lives.append("%s %.1f" % [c, life])
	var info := "Lap ≈ %s · fuel %.2f L/lap (tank %d L = %.1f laps) · pit stop ≈ %d s\nTyre life (laps): %s" % [
		Race.fmt_time(lap), fpl, int(tank), tank / fpl, roundi(stop), "   ".join(lives)]
	if strategy_options.is_empty():
		var why := "No plan satisfies these rules."
		if all_short:
			why = "No tyre survives a single lap — lower the tyre wear."
		elif laps < 2 and (mandatory_stop_toggle.button_pressed or two_compounds_toggle.button_pressed):
			why = "A %s needs a race of at least 2 laps." % ("mandatory pit stop" if mandatory_stop_toggle.button_pressed else "second tyre compound")
		elif not refuel_toggle.button_pressed and Strategy.fuel_need(laps, fpl) > tank:
			why = "Without refuelling the race needs %.1f L — more than the %d L tank." % [Strategy.fuel_need(laps, fpl), int(tank)]
		info += "\n⚠ " + why
	elif strategy_options[0].horizon:
		info += "\nEndurance: the strategist plans the next %d laps and keeps extending the plan (≈ %d stops in all)." % [
			strategy_options[0].horizon, roundi(float(laps) / strategy_options[0].horizon * strategy_options[0].stops)]
	strategy_info.text = info
	if format_picker.selected == 1:
		race_length_label.text = "%s race ≈ %d lap%s · %d km — the winner is whoever leads when the clock runs out" % [
			_fmt_hours(hours_picker.value), laps, "" if laps == 1 else "s", roundi(laps * track.L / 1000.0)]
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
		out.append({"c": "W" if weather_picker.selected in [1, 2, 3] else "M", "laps": _race_laps(Race.get_track(TRACK_KEYS[track_picker.selected]))})
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
		var compound := MenuSelector.new()
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
		_set_section_summary("plan", "")
		return
	var track := Race.get_track(TRACK_KEYS[track_picker.selected])
	var res := strategy.evaluate(_plan_opts(track, _race_laps(track), wear_picker.value), custom_stints)
	if res.errors.size():
		custom_eval.text = "\n".join(res.errors.map(func(e): return "⚠ " + e))
		custom_eval.add_theme_color_override("font_color", CmrStyle.RED)
		current_plan = null
		_set_section_summary("plan", "NOT VALID")
	else:
		var best: float = strategy_options[0].time if strategy_options.size() else res.time
		custom_eval.text = "✓ Valid · est. %s (%s%.1f s vs best)" % [Race.fmt_time(res.time).get_slice(".", 0), "+" if res.time - best >= 0.0 else "", res.time - best]
		custom_eval.add_theme_color_override("font_color", CmrStyle.GREEN)
		current_plan = res
		_set_section_summary("plan", "IN USE")

## What the learning AI remembers about you on the selected circuit.
func _update_ai_memory() -> void:
	if not is_instance_valid(ai_memory_label):
		return
	var key: String = _calendar()[_champ_round()] if is_championship_mode else TRACK_KEYS[track_picker.selected]
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
	_update_lap_records(key, name)

## The player's lap records on the selected circuit, whose ghosts race them there.
func _update_lap_records(key: String, name: String) -> void:
	if not is_instance_valid(record_label):
		return
	var parts: Array[String] = []
	for cond in LapRecords.CONDITIONS:
		var r := LapRecords.record(key, cond)
		if r.has("t"):
			parts.append("%s %s (%s)" % [Race.fmt_time(float(r.t)), cond, r.get("date", "")])
	record_forget_button.visible = not parts.is_empty()
	if parts.is_empty():
		record_label.text = "No lap record at %s yet. Your best flying lap sets one, and its ghost races you from then on." % name
	else:
		record_label.text = "Your lap record at %s: %s. G shows or hides its ghost in the race." % [name, " · ".join(parts)]

func _forget_lap_records() -> void:
	var key: String = _calendar()[_champ_round()] if is_championship_mode else TRACK_KEYS[track_picker.selected]
	var dialog := ConfirmationDialog.new()
	dialog.title = "Forget lap records"
	dialog.dialog_text = "Delete your lap records and their ghosts at %s?" % Race.get_track(key).name
	dialog.confirmed.connect(func() -> void:
		LapRecords.forget(key)
		_update_ai_memory()
		_update_information_page()
	)
	dialog.visibility_changed.connect(func() -> void:
		if not dialog.visible:
			dialog.queue_free()
	)
	_refocus_after(dialog)
	add_child(dialog)
	dialog.popup_centered()

func _forget_ai_memory() -> void:
	var key: String = _calendar()[_champ_round()] if is_championship_mode else TRACK_KEYS[track_picker.selected]
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
	_refocus_after(dialog)
	add_child(dialog)
	dialog.popup_centered()

## The set-up page survives restarts, like the reference's saved settings.
func _race_setting_controls() -> Dictionary:
	return {
		"track": track_picker, "laps": laps_picker, "format": format_picker, "hours": hours_picker,
		"start_hour": start_hour_picker, "opponents": opponents_picker, "difficulty": difficulty_picker,
		"weather": weather_picker, "gearbox": gearbox_picker, "grid": grid_picker, "quali": quali_picker, "assists": assists_picker,
		"wear_mult": wear_picker, "fuel_mult": fuel_picker, "mandatory_stop": mandatory_stop_toggle,
		"two_compounds": two_compounds_toggle, "refuel": refuel_toggle, "collisions": collisions_toggle,
		"race_control": race_control_toggle, "mechanical_damage": damage_toggle, "dynamic_running": dynamic_toggle, "draft": draft_toggle,
		"auto_strategist": strategist_toggle, "parallel": parallel_toggle, "crew": crew_picker,
		"ai_learning": ai_learning_picker, "bot_physics": bot_physics_picker, "player_name": player_name_edit,
		"player_number": player_number_picker, "player_color": player_color_picker, "stripes": player_stripes_toggle, "finish": player_finish_picker, "car_class": car_class_picker,
	}

## The dev menu's actions (§ + 1) for whatever is on screen: [{section, label, do: Callable, close: bool}].
func _dev_entries() -> Array:
	var out: Array = []
	var add := func(section: String, label: String, fn: Callable, close := false) -> void:
		out.append({"section": section, "label": label, "do": fn, "close": close})
	for n in [10000, 100000, 1000000]:
		add.call("FANS & UNLOCKS", "+%s fans" % OpenWorldHud._thousands(n), func() -> void: _dev_fans(n))
	add.call("FANS & UNLOCKS", "Unlock everything (hypercar, final race, modifiers): %s" % ("ON" if FanLevels.dev_unlock else "off"),
		func() -> void: FanLevels.dev_unlock = not FanLevels.dev_unlock)
	add.call("FANS & UNLOCKS", "Fans now: %s (level %d)" % [OpenWorldHud._thousands(_fan_total()), FanLevels.level(_fan_total())], func() -> void: pass)
	if open_world != null and open_world.active:
		for spot in open_world.map.spots.keys():
			add.call("OPEN WORLD · TELEPORT", String(spot), func() -> void: open_world.dev_teleport(String(spot)), true)
		for h in [6.0, 12.0, 18.5, 22.0]:
			add.call("OPEN WORLD · TIME", "%02d:%02d" % [int(h), int(fmod(h, 1.0) * 60.0)], func() -> void: open_world.dev_set_hour(h))
		for kind in ["CarHatch", "CarSedan", "CarVan", "Maluch"]:
			add.call("OPEN WORLD · SPAWN", "Park a %s 22 m ahead" % kind.trim_prefix("Car"), func() -> void: open_world.dev_spawn(kind), true)
		add.call("OPEN WORLD · CAR", "Put the car back on the road", func() -> void: open_world.drive.respawn(), true)
	elif race != null and not menu_tint.visible:
		for w in [["Dry", 0.0, 0.0], ["Rain", 0.7, 0.85], ["Storm", 1.0, 1.0]]:
			add.call("RACE · WEATHER", String(w[0]), func() -> void:
				race.weather.rain = float(w[1])
				race.weather.wet = float(w[2]))
		add.call("RACE · CAR", "Repair the car", func() -> void: Service.fit(race.player, {}, 0.0))
		add.call("RACE · CAR", "Fill the tank", func() -> void: race.player.fuel = race.spec.tank)
		add.call("RACE · RACE", "Finish the race now (projected from the field's pace)", func() -> void:
			race.approximate_finish()
			_show_results(), true)
	return out

func _dev_fans(n: int) -> void:
	if open_world != null and open_world.progress != null:
		open_world.award_fans(n)
	else:
		var wp := WorldProgress.load_progress()
		wp.fans += n
		wp.save()

## The fans the player has earned in the open world (the live game, or the save).
func _fan_total() -> int:
	if open_world != null and open_world.progress != null:
		return open_world.progress.fans
	return WorldProgress.load_progress().fans

## The open-world save holds the modifiers switched on (the open world's own copy while it is loaded).
func _world_progress() -> WorldProgress:
	if open_world != null and open_world.progress != null:
		return open_world.progress
	return WorldProgress.load_progress()

## The modifiers switched on that the fans unlock: every mode uses them on the player's car.
func _active_mods() -> Dictionary:
	var wp := _world_progress()
	return CarMods.active(wp.mods, wp.fans)

## Bullet Time: the race runs slow while the player's car is sliding.
func _bullet_rate(delta: float) -> float:
	var slow := false
	if race and race.mods.has("bullet") and race.player and race.player.control == "free":
		var p := race.player
		var v := Vector2(p.vx, p.vy).length()
		slow = v > 8.0 and absf(wrapf(atan2(p.vy, p.vx) - p.heading, -PI, PI)) > 0.3
	_time_rate = move_toward(_time_rate, CarMods.BULLET_RATE if slow else 1.0, delta * 3.0)
	return _time_rate

## One switch per CarMods entry on the Car page; locked ones name the fan level that opens them.
func _build_mods_box(box: VBoxContainer) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	box.add_child(grid)
	for m in CarMods.LIST:
		var chk := _check_field(grid, m[2], false)
		chk.tooltip_text = m[3]
		chk.toggled.connect(_on_mod_toggled.bind(m[0]))
		mod_toggles[m[0]] = chk
	_refresh_mod_toggles()

func _refresh_mod_toggles() -> void:
	var wp := _world_progress()
	for m in CarMods.LIST:
		var chk: CheckButton = mod_toggles.get(m[0])
		if chk == null:
			continue
		var open := CarMods.unlocked(m[0], wp.fans)
		chk.disabled = not open
		chk.text = m[2] if open else "%s · LEVEL %d" % [m[2], m[1]]
		chk.set_pressed_no_signal(open and wp.mods.has(m[0]))

func _on_mod_toggled(on: bool, id: String) -> void:
	var wp := _world_progress()
	if on and CarMods.unlocked(id, wp.fans):
		wp.mods[id] = true
	else:
		wp.mods.erase(id)
	wp.save()
	_refresh_mod_toggles()

func _hypercar_open() -> bool:
	return FanLevels.hypercar_unlocked(_fan_total())

func _on_car_class_selected(index: int) -> void:
	if index == 1 and not _hypercar_open():
		car_class_picker.select(0)
		status_label.text = "The Hypercar Seicento opens at fan level %d (%s): earn fans in the open world and the campaign." % [FanLevels.THRESHOLDS.size(), FanLevels.title(FanLevels.THRESHOLDS.size())]
		status_label.modulate = DANGER
	_update_menu_car_summary()
	_queue_strategy_refresh()

## The car model and strategist a race runs on: the Hypercar Seicento for a hypercar race, else the stock Seicento.
func _models_for(car_class: String) -> Dictionary:
	if car_class != "hypercar":
		return {"car_model": car_model, "tyres": tyre_model, "strategy": strategy}
	if _hyper_model == null:
		_hyper_model = Hypercar.model()
		_hyper_strategy = Strategy.new(_hyper_model, tyre_model)
	return {"car_model": _hyper_model, "tyres": tyre_model, "strategy": _hyper_strategy}

func _load_race_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SaveData.path("race_settings.cfg")) != OK:
		return
	_loading_settings = true
	var controls := _race_setting_controls()
	for key in controls:
		if not cfg.has_section_key("race", key):
			continue
		var v = cfg.get_value("race", key)
		var control: Control = controls[key]
		if control is MenuSelector:
			(control as MenuSelector).select(clampi(int(v), 0, (control as MenuSelector).item_count - 1))
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
	var opened = cfg.get_value("page", "open", {})
	if opened is Dictionary:
		for key in setup_folds:
			_open_section(key, bool(opened.get(key, setup_open[key])), false)
	car_setups.clear()
	if cfg.has_section("car_setup"):
		for t in cfg.get_section_keys("car_setup"):
			var st := CarSetup.clean(cfg.get_value("car_setup", t))
			if not CarSetup.is_stock(st):
				car_setups[t] = st
	_refresh_car_setup()
	_loading_settings = false

## CMR's car set-up: a five-notch slider per setting, the stock car in the middle. Changes are kept for the
## circuit on the page (the championship round's in a championship).
func _build_car_setup(col: VBoxContainer) -> void:
	for key in CarSetup.SETTINGS:
		var info: Array = CarSetup.SETTINGS[key]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.custom_minimum_size.y = 30
		col.add_child(row)
		var title := _label(info[0], 14, CmrStyle.TEXT)
		title.custom_minimum_size.x = 170
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(title)
		var lo := _label(info[1], 12, MUTED)
		lo.custom_minimum_size.x = 48
		lo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(lo)
		var slider := HSlider.new()
		slider.min_value = -CarSetup.NOTCHES
		slider.max_value = CarSetup.NOTCHES
		slider.step = 1
		slider.tick_count = 2 * CarSetup.NOTCHES + 1
		slider.ticks_on_borders = true
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.tooltip_text = info[3]
		slider.value_changed.connect(_car_setup_changed.bind(key))
		slider.mouse_entered.connect(func() -> void: setup_help.text = info[3])
		slider.focus_entered.connect(func() -> void: setup_help.text = info[3])
		slider.set_meta("caption", title) # lit while the slider has the keyboard (_setup_focus_changed)
		row.add_child(slider)
		setup_sliders[key] = slider
		var hi := _label(info[2], 12, MUTED)
		hi.custom_minimum_size.x = 48
		hi.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(hi)
		var notch := _label("0", 14, CmrStyle.TEXT)
		notch.custom_minimum_size.x = 26
		notch.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		notch.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(notch)
		setup_values[key] = notch
	setup_help = _label("The middle notch is the stock car. Point at a setting, or pick it with ↑ ↓, to see what it does.", 13, MUTED)
	setup_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	setup_help.custom_minimum_size = Vector2(1, 38)
	col.add_child(setup_help)
	var help_row := HBoxContainer.new()
	help_row.add_theme_constant_override("separation", 14)
	col.add_child(help_row)
	# the field's drivers each run their own (Drivers.ROSTER): try one
	var copy := MenuSelector.new()
	copy.browse_only = true # ◂ ▸ browse the drivers; A / Enter applies the one shown
	copy.tooltip_text = "◂ ▸ pick a driver, then A / Enter: their set-up replaces yours on this circuit"
	copy.add_item("COPY A DRIVER'S SET-UP")
	for who in Drivers.ROSTER:
		copy.add_item(who.name)
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.custom_minimum_size.y = 42
	copy.item_selected.connect(func(index: int) -> void:
		if index <= 0:
			return
		var who: Dictionary = Drivers.ROSTER[index - 1]
		var st := CarSetup.clean(who.setup)
		if CarSetup.is_stock(st):
			car_setups.erase(_menu_track_key())
		else:
			car_setups[_menu_track_key()] = st
		_refresh_car_setup()
		setup_help.text = "%s: %s" % [who.name, who.style]
		copy.select(0)
		_save_race_settings()
	)
	help_row.add_child(copy)
	var stock := _button("STOCK SET-UP", CmrStyle.FIELD)
	stock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stock.pressed.connect(func() -> void:
		car_setups.erase(_menu_track_key())
		_refresh_car_setup()
		_save_race_settings()
	)
	help_row.add_child(stock)

## Shows the set-up kept for the circuit on the page.
func _refresh_car_setup() -> void:
	if setup_sliders.is_empty() or not is_instance_valid(track_picker):
		return
	var key := _menu_track_key()
	var st := CarSetup.clean(car_setups.get(key, {}))
	var was := _loading_settings
	_loading_settings = true
	for k in setup_sliders:
		(setup_sliders[k] as HSlider).value = st[k]
		(setup_values[k] as Label).text = "%+d" % st[k] if st[k] != 0 else "0"
	_loading_settings = was
	_set_section_summary("car", "%s  ·  %s" % ["STOCK" if CarSetup.is_stock(st) else "TUNED", Race.get_track(key).name.to_upper()])

func _car_setup_changed(value: float, setting: String) -> void:
	if _loading_settings:
		return
	var key := _menu_track_key()
	var st := CarSetup.clean(car_setups.get(key, {}))
	st[setting] = int(value)
	if CarSetup.is_stock(st):
		car_setups.erase(key)
	else:
		car_setups[key] = st
	setup_help.text = CarSetup.SETTINGS[setting][3]
	_refresh_car_setup()
	_save_race_settings()

func _save_race_settings() -> void:
	if not is_instance_valid(track_picker):
		return
	var cfg := ConfigFile.new()
	var controls := _race_setting_controls()
	for key in controls:
		var control: Control = controls[key]
		var v
		if control is MenuSelector:
			v = (control as MenuSelector).selected
		elif control is SpinBox:
			v = (control as SpinBox).value
		elif control is CheckButton:
			v = (control as CheckButton).button_pressed
		elif control is LineEdit:
			v = (control as LineEdit).text
		elif control is ColorPickerButton:
			v = (control as ColorPickerButton).color
		cfg.set_value("race", key, v)
	for t in car_setups:
		cfg.set_value("car_setup", t, car_setups[t])
	cfg.set_value("page", "open", setup_open)
	cfg.save(SaveData.path("race_settings.cfg"))

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
	menu_car_summary = _label("", 24, INK)
	menu_car_summary.anchor_left = 0.045
	menu_car_summary.anchor_top = 0.675
	menu_car_summary.anchor_right = 0.555
	menu_car_summary.anchor_bottom = 0.79
	menu_car_summary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	menu_car_summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS # a long circuit name stops short of the set-up column
	add_child(menu_car_summary)

	# the circuit's map and facts sit between the car and its name on the Set Up page
	circuit_map_frame = PanelContainer.new()
	circuit_map_frame.name = "CircuitMap"
	_anchor_rect(circuit_map_frame, 0.045, 0.51, 0.555, 0.745)
	circuit_map_frame.clip_contents = true
	var map_style := StyleBoxFlat.new()
	map_style.bg_color = CmrStyle.MAP
	map_style.set_content_margin_all(0)
	circuit_map_frame.add_theme_stylebox_override("panel", map_style)
	add_child(circuit_map_frame)
	information_map = MENU_TRACK_ART.new()
	information_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	circuit_map_frame.add_child(information_map)
	circuit_facts = _label("", 14, CmrStyle.ORANGE_SOFT)
	_anchor_rect(circuit_facts, 0.045, 0.88, 0.555, 0.95)
	circuit_facts.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(circuit_facts)
	_update_menu_car_summary()

## The circuit the front end is currently pointing at: this round's in a championship, otherwise the picked one.
func _menu_track_key() -> String:
	if is_championship_mode:
		return _calendar()[_champ_round()]
	elif is_campaign_mode:
		return CampaignData.get_stage(campaign_stage_index).track
	elif is_rally_mode:
		return str(_rally().stage_def(mini(_rally().stage_index, _rally().stage_count() - 1)).track)
	return TRACK_KEYS[track_picker.selected]

func _update_menu_car_summary() -> void:
	if not is_instance_valid(menu_car_summary) or not is_instance_valid(track_picker):
		return
	var current_track: Track = Race.get_track(_menu_track_key())
	if is_instance_valid(player_color_picker) and is_instance_valid(menu_preview_car):
		menu_preview_car.call("set_paint", player_color_picker.color)
		menu_preview_car.call("set_livery", player_finish_picker.selected)
		menu_preview_car.call("set_stripes", player_stripes_toggle.button_pressed)
		menu_preview_car.set("car_number", int(player_number_picker.value))
	var race_label := "%d LAPS" % int(laps_picker.value)
	if is_championship_mode:
		race_label = "ROUND %02d / %02d" % [_champ_round() + 1, _calendar().size()]
	elif is_campaign_mode:
		var st := CampaignData.get_stage(campaign_stage_index)
		race_label = "STAGE %02d / %02d  ·  %d LAPS" % [campaign_stage_index + 1, CampaignData.STAGES.size(), st.laps]
	elif is_rally_mode:
		var ev := _rally()
		var i := mini(ev.stage_index, ev.stage_count() - 1)
		race_label = "SS%d / %d  ·  %.1f KM STAGE" % [i + 1, ev.stage_count(), Rally.stage_length(ev.stage_def(i), current_track.L) / 1000.0]
	elif is_time_trial_mode:
		race_label = "TIME TRIAL  ·  %s START" % ("ROLLING" if is_instance_valid(tt_start_picker) and tt_start_picker.selected == 1 else "STANDING")
	elif format_picker.selected == 1:
		race_label = "%s ENDURANCE" % _fmt_hours(hours_picker.value).to_upper()
	menu_car_summary.text = "%s    |    %.1f KM\n%s" % [current_track.name.to_upper(), current_track.L / 1000.0, race_label]
	_refresh_car_setup()

func _build_menu_header() -> void:
	menu_header = HBoxContainer.new()
	menu_header.name = "MenuHeader"
	menu_header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	menu_header.offset_left = 58
	menu_header.offset_top = 52
	menu_header.offset_right = -58
	menu_header.offset_bottom = 100
	menu_header.add_theme_constant_override("separation", 16) # room either side of the rule before MAIN MENU
	add_child(menu_header)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 0)
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu_header.add_child(tabs)
	_menu_tab(tabs, "Set Up", _show_setup_page)
	_menu_tab(tabs, "Advanced", _show_advanced_page)
	_menu_tab(tabs, "Car", _show_car_page)
	_menu_tab(tabs, "Strategy", _show_strategy_page)
	_menu_tab(tabs, "Service", _show_repair_page)

	var player := Label.new()
	player.text = "PLAYER 1  │  YOU"
	player.add_theme_font_size_override("font_size", 21)
	player.add_theme_color_override("font_color", MUTED)
	player.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	menu_header.add_child(player)

	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(2, 42)
	sep.color = CmrStyle.DIM
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	menu_header.add_child(sep)

	var back_btn := Button.new()
	back_btn.text = "MAIN MENU (Esc)"
	back_btn.flat = true
	back_btn.focus_mode = Control.FOCUS_NONE
	back_btn.add_theme_font_override("font", CmrStyle.font(400))
	back_btn.add_theme_font_size_override("font_size", 18)
	back_btn.add_theme_color_override("font_color", ACCENT)
	back_btn.pressed.connect(_show_home)
	menu_header.add_child(back_btn)
	menu_back_button = back_btn

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
	if title != TOP_MENU_TABS[-1]:
		var divider := ColorRect.new()
		divider.custom_minimum_size = Vector2(2, 42)
		divider.color = CmrStyle.DIM
		divider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		parent.add_child(divider)
		menu_tab_dividers[title] = divider

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
	repair_note = _label("%d minute time allocation" % _service_allocation(), 18, MUTED)
	column.add_child(repair_note)
	var time_row := HBoxContainer.new()
	time_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	time_row.add_theme_constant_override("separation", 8)
	column.add_child(time_row)
	var time_left := _label("60:00", 70, CmrStyle.TEXT)
	time_left.add_theme_font_override("font", CmrStyle.digits())
	time_row.add_child(time_left)
	repair_clock = time_left
	var minutes := _label("(mins)", 21, MUTED)
	minutes.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	time_row.add_child(minutes)
	var pre_list_gap := Control.new()
	pre_list_gap.custom_minimum_size.y = 8
	column.add_child(pre_list_gap)
	_menu_rule(column)

	var parts: Array = Service.PARTS.keys()
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
		part_button.custom_minimum_size.y = 40
		part_button.add_theme_font_size_override("font_size", 20)
		part_button.pressed.connect(_repair_row_pressed.bind(i))
		row.add_child(part_button)
		var status: Control = MENU_REPAIR_STATUS.new()
		row.add_child(status)
		repair_marks.append(status)
		repair_rows.append(part_button)
		var rule := ColorRect.new()
		rule.custom_minimum_size.y = 2
		column.add_child(rule)
		repair_row_rules.append(rule)
	repair_summary = _label("", 14, CmrStyle.ORANGE_SOFT)
	repair_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	repair_summary.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(repair_summary)
	repair_continue = _button("CONTINUE  ▸", ACCENT)
	repair_continue.custom_minimum_size.y = 52
	repair_continue.add_theme_font_size_override("font_size", 20)
	repair_continue.focus_mode = Control.FOCUS_NONE # START (or Enter on the page) continues
	repair_continue.pressed.connect(_continue_from_service)
	column.add_child(repair_continue)
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
	repair_art = art

	repair_part_name = _label("BODY", 17, MUTED)
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
	repair_button = _button("REPAIR  ▸", ACCENT)
	repair_button.anchor_left = 0.57
	repair_button.anchor_top = 0.64
	repair_button.anchor_right = 0.66
	repair_button.anchor_bottom = 0.7
	repair_button.focus_mode = Control.FOCUS_NONE # Enter / A on the page repairs (_input)
	repair_button.pressed.connect(_repair_selected)
	repair_details.add_child(repair_button)

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
	repair_copy = _label("", 17, CmrStyle.TEXT)
	repair_copy.anchor_left = 0.045
	repair_copy.anchor_top = 0.83
	repair_copy.anchor_right = 0.56
	repair_copy.anchor_bottom = 0.955
	repair_copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	repair_copy.max_lines_visible = 4 # stops above the key hints; a longer note ends in "…"
	repair_copy.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	repair_details.add_child(repair_copy)
	_select_repair_part(repair_selected)
	repair_details.hide()

## The car the Repair page shows: the championship car between rounds ({parts, pull, used}), otherwise the
## state the last single race left it in (nothing carries over from one).
func _service_car() -> Dictionary:
	if _servicing():
		return _carried_car()
	return {"parts": last_race_parts}

## The service area is working on a car that goes on to another event (a championship with damage on, or
## the campaign); a quick race's car is rebuilt for every race, so its page only shows the damage.
func _servicing() -> bool:
	return (is_championship_mode or is_rally_mode) and _service_allocation() > 0

func _service_left() -> int:
	return _service_allocation() - int(_service_car().get("used", 0))

func _part_severity(part: String) -> float:
	var parts = _service_car().get("parts", {})
	return clampf(float(parts.get(part, 0.0)), 0.0, 1.0) if parts is Dictionary else 0.0

## Clicking a part selects it; clicking the selected part again repairs it, as in CMR.
func _repair_row_pressed(index: int) -> void:
	if index == repair_selected and repair_button.visible and not repair_button.disabled:
		_repair_selected()
	else:
		_select_repair_part(index)

## The crew fixes the selected part if the time left covers it.
func _repair_selected() -> void:
	if not _servicing():
		return
	var part: String = Service.PARTS.keys()[repair_selected]
	var need := Service.minutes(part, _part_severity(part))
	var car: Dictionary = _service_car()
	if need <= 0 or need > _service_left() or car.is_empty():
		return
	car.parts.erase(part)
	car["used"] = int(car.get("used", 0)) + need
	car["serviced"] = true
	_store_carried_car(car)
	_select_repair_part(repair_selected)

## Leaves the service area for the next event (whatever is left unrepaired goes with the car).
func _continue_from_service() -> void:
	var car := _carried_car()
	if not car.is_empty():
		car["serviced"] = true
		_store_carried_car(car)
	if is_rally_mode and not car.get("applied", false):
		_rally().apply_service(car.get("parts", {}), int(car.get("used", 0)))
		car["applied"] = true
		_store_carried_car(car)
	_start_race()

## The service area opens on the first broken part (or where it was, if nothing is).
func _first_damaged_part() -> int:
	var names: Array = Service.PARTS.keys()
	for i in names.size():
		if _part_severity(names[i]) >= 0.01:
			return i
	return repair_selected

func _select_repair_part(index: int) -> void:
	repair_selected = clampi(index, 0, repair_rows.size() - 1)
	var names: Array = Service.PARTS.keys()
	var left := _service_left()
	for i in repair_rows.size():
		var style := CmrStyle.box(ACCENT if i == repair_selected else CmrStyle.FIELD_DIM, Color.TRANSPARENT, 14, 4)
		repair_rows[i].add_theme_stylebox_override("normal", style)
		repair_rows[i].add_theme_stylebox_override("hover", style if i == repair_selected else CmrStyle.box(CmrStyle.FIELD, Color.TRANSPARENT, 14, 4))
		repair_row_rules[i].color = Color(0, 0, 0, 0)
		var sev_i := _part_severity(names[i])
		repair_marks[i].state = "ok" if sev_i < 0.01 else ("bad" if sev_i >= 0.5 else "warning")
	if not is_instance_valid(repair_part_name):
		return
	var part: String = names[repair_selected]
	var sev := _part_severity(part)
	var need := Service.minutes(part, sev)
	var servicing := _servicing()
	var next := "stage" if is_campaign_mode or is_rally_mode else "round"
	repair_part_name.text = part.to_upper()
	repair_time_label.text = "%02d:00" % need
	repair_clock.text = "%02d:00" % maxi(0, left)
	repair_art.part = part
	var copy: String = Service.PARTS[part][2]
	if not servicing:
		repair_note.text = "Car rebuilt for every race" if not is_championship_mode else "Damage & repairs off this season"
		if sev >= 0.01:
			copy += " Last race: %s" % Service.symptom(part, sev)
		copy += " In a championship (damage on) or the campaign it carries over, and the crew gets the service time to fix what they can."
	else:
		repair_note.text = "%d minute time allocation" % _service_allocation()
		if need == 0:
			copy += " In working order."
		else:
			copy += " %d%% damaged: %s" % [roundi(sev * 100.0), Service.symptom(part, sev)]
			if need > left:
				copy += " Not enough service time left: it starts the next %s like this." % next
			else:
				copy += " Repair it for %d minute%s of the time left." % [need, "" if need == 1 else "s"]
	repair_copy.text = copy
	repair_button.visible = servicing
	repair_button.disabled = need == 0 or need > left
	var marker := lerpf(0.045, 0.56, sev)
	repair_damage_marker.anchor_left = marker
	repair_damage_marker.anchor_right = marker + 0.005
	if is_instance_valid(repair_summary):
		var parts = _service_car().get("parts", {})
		var unrepaired := _unrepaired_text(parts if parts is Dictionary else {})
		if not servicing:
			repair_summary.text = ""
		elif unrepaired == "":
			repair_summary.text = "The car is in working order for the next %s." % next
		else:
			repair_summary.text = "IF LEFT UNREPAIRED, NEXT %s:\n%s" % [next.to_upper(), unrepaired]
	if is_instance_valid(repair_continue):
		repair_continue.visible = servicing
		if is_championship_mode:
			var nr := _next_round()
			repair_continue.text = "CONTINUE TO ROUND %d  ▸" % (nr + 1) if nr < _calendar().size() else "CONTINUE  ▸"
		else:
			repair_continue.text = "CONTINUE TO THE STAGE  ▸"

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
	menu_home_art.set_track(Race.get_track(_menu_track_key()))
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
	menu_home_track = _label("", 24, MUTED)
	menu_home_track.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(menu_home_track)

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
	# three copies of the words in a row: the strip loops, so QUIT scrolls on to CAMPAIGN with no jump
	for k in FRONT_MENU.size() * 3:
		var i := k % FRONT_MENU.size()
		if k > 0:
			var divider := ColorRect.new()
			divider.custom_minimum_size = Vector2(2, 96)
			divider.color = Color(CmrStyle.TEXT, 0.75)
			divider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			menu_home_strip.add_child(divider)
		var item: Dictionary = FRONT_MENU[i]
		var button := Button.new()
		button.text = str(item.word)
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
	home_phys = FRONT_MENU.size() + home_menu_index
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
	scroll.follow_focus = true
	options_column = column
	_title(column, "OPTIONS", "DISPLAY, GRAPHICS, AUDIO & CO-DRIVER")
	_menu_rule(column)
	_field_label(column, "GRAPHICS")
	var preset_row := HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", 22)
	column.add_child(preset_row)
	preset_picker = _option_field(preset_row, "GRAPHICS PRESET", GraphicsPresets.NAMES + ["Custom"])
	preset_picker.item_selected.connect(_on_preset_selected)
	preset_note = _label("", 14, MUTED)
	preset_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preset_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preset_note.size_flags_stretch_ratio = 2.0
	preset_row.add_child(preset_note)
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
	var resolution_row := HBoxContainer.new()
	resolution_row.add_theme_constant_override("separation", 22)
	column.add_child(resolution_row)
	resolution_picker = _option_field(resolution_row, "RESOLUTION", [])
	resolution_picker.item_selected.connect(_on_resolution_selected)
	aspect_picker = _option_field(resolution_row, "ASPECT RATIO", ASPECTS.map(func(a): return a.name))
	aspect_picker.item_selected.connect(_on_aspect_selected)
	resolution_note = _label("", 14, MUTED)
	resolution_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	resolution_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resolution_row.add_child(resolution_note)
	var frame_row := HBoxContainer.new()
	frame_row.add_theme_constant_override("separation", 22)
	column.add_child(frame_row)
	fps_limit_picker = _option_field(frame_row, "FRAME RATE LIMIT", FPS_LIMITS.map(func(l): return l.name))
	fps_limit_picker.item_selected.connect(_on_fps_limit_selected)
	var frame_note := _label("A lower limit runs cooler and saves battery.", 14, MUTED)
	frame_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	frame_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame_row.add_child(frame_note)
	frame_note.size_flags_stretch_ratio = 2.0
	_menu_rule(column)
	_field_label(column, "LOOK")
	var retro_row := HBoxContainer.new()
	retro_row.add_theme_constant_override("separation", 22)
	column.add_child(retro_row)
	retro_picker = _option_field(retro_row, "RETRO STYLE", RetroPipeline.MODE_NAMES)
	retro_picker.item_selected.connect(_on_retro_selected)
	_grid_spacers(retro_row, 2)
	var retro_note := _label("Pick a look from a classic racing game. F1 cycles styles in a race.", 14, MUTED)
	retro_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(retro_note)
	_menu_rule(column)
	_field_label(column, "AUDIO")
	var volume_row: HBoxContainer = null
	for ch in AudioSettings.CHANNELS:
		if volume_row == null or volume_row.get_child_count() == 3:
			volume_row = HBoxContainer.new()
			volume_row.add_theme_constant_override("separation", 22)
			column.add_child(volume_row)
		var picker := _option_field(volume_row, ch.name, AudioSettings.step_names())
		picker.select(AudioSettings.level(ch.key) / 10)
		picker.item_selected.connect(_on_volume_selected.bind(ch.key))
		audio_pickers[ch.key] = picker
	var audio_note := _label("Off mutes a sound; 100% is the full mix. M mutes everything in a race.", 14, MUTED)
	audio_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	audio_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	audio_note.size_flags_stretch_ratio = 2.0
	volume_row.add_child(audio_note)
	_menu_rule(column)
	_field_label(column, "CO-DRIVER")
	var codriver_row := HBoxContainer.new()
	codriver_row.add_theme_constant_override("separation", 22)
	column.add_child(codriver_row)
	codriver_voice_toggle = _check_field(codriver_row, "Read the pace notes aloud", codriver_voice)
	codriver_voice_toggle.toggled.connect(_on_codriver_voice_toggled)
	var codriver_note := _label("The co-driver calls each corner before you reach it, in your system voice.", 14, MUTED)
	codriver_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	codriver_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	codriver_note.size_flags_stretch_ratio = 2.0
	codriver_row.add_child(codriver_note)
	var adv_col := _fold_section(column, "gfx_adv", "ADVANCED GRAPHICS", true)
	_set_section_summary("gfx_adv", "UPSCALING, ANTI-ALIASING, SHADOWS, REFLECTIONS")
	_field_label(adv_col, "3D UPSCALING")
	var upscaling_row := HBoxContainer.new()
	upscaling_row.add_theme_constant_override("separation", 22)
	adv_col.add_child(upscaling_row)
	upscaler_picker = _option_field(upscaling_row, "UPSCALER", [])
	for i in UPSCALERS.size():
		if _upscaler_available(i):
			upscaler_picker.add_item(UPSCALERS[i].name, i)
	upscaler_picker.item_selected.connect(_on_upscaler_selected)
	upscale_preset_picker = _option_field(upscaling_row, "RENDER RESOLUTION", UPSCALE_PRESETS.map(func(p): return p.name))
	upscale_preset_picker.item_selected.connect(_on_upscale_preset_selected)
	sharpening_picker = _option_field(upscaling_row, "FSR SHARPENING", SHARPENING.map(func(s): return s.name))
	sharpening_picker.item_selected.connect(_on_sharpening_selected)
	var explanation := _label("Lower presets run faster with a softer image.", 14, MUTED)
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	adv_col.add_child(explanation)
	var image_row := HBoxContainer.new()
	image_row.add_theme_constant_override("separation", 22)
	adv_col.add_child(image_row)
	antialiasing_picker = _option_field(image_row, "NATIVE ANTI-ALIASING", ["SMAA", "FXAA", "Off"])
	antialiasing_picker.item_selected.connect(_on_antialiasing_selected)
	_grid_spacers(image_row, 2)
	_menu_rule(adv_col)
	_field_label(adv_col, "LIGHTING & REFLECTIONS")
	var effects_row := HBoxContainer.new()
	effects_row.add_theme_constant_override("separation", 22)
	adv_col.add_child(effects_row)
	ssao_toggle = _check_field(effects_row, "Ambient occlusion", graphics_ssao)
	ssao_toggle.toggled.connect(_on_ssao_toggled)
	shadows_toggle = _check_field(effects_row, "Dynamic shadows", graphics_shadows)
	shadows_toggle.toggled.connect(_on_shadows_toggled)
	var reflections_row := HBoxContainer.new()
	reflections_row.add_theme_constant_override("separation", 22)
	adv_col.add_child(reflections_row)
	reflections_picker = _option_field(reflections_row, "REFLECTIONS", ["Off", "Screen-space", "Ray-traced"])
	reflections_picker.item_selected.connect(_on_reflections_selected)
	_grid_spacers(reflections_row, 2)
	var lighting_note := _label("Ray-traced reflections also mirror what is off screen; screen-space is cheaper.", 14, MUTED)
	lighting_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	adv_col.add_child(lighting_note)
	var back := _button("BACK TO MENU", ACCENT)
	back.pressed.connect(_show_home)
	column.add_child(back)
	options_panel.hide()
	upscaler_picker.select(upscaler_picker.get_item_index(graphics_upscaler))
	upscale_preset_picker.select(graphics_upscale_preset)
	sharpening_picker.select(graphics_sharpening)
	antialiasing_picker.select(graphics_antialiasing)
	display_mode_picker.select(graphics_display_mode)
	aspect_picker.select(graphics_aspect)
	_rebuild_resolution_picker()
	vsync_toggle.button_pressed = graphics_vsync
	fps_limit_picker.select(graphics_fps_limit)
	ssao_toggle.button_pressed = graphics_ssao
	shadows_toggle.button_pressed = graphics_shadows
	reflections_picker.select(graphics_reflections)
	retro_picker.select(graphics_retro_mode)
	_show_preset_state()
	_apply_upscaling()

func _on_retro_selected(index: int) -> void:
	graphics_retro_mode = index
	if retro_pipeline:
		retro_pipeline.set_mode(graphics_retro_mode)
	_apply_ui_skin()
	_save_graphics_settings()

func _cycle_retro_mode() -> void:
	if not retro_pipeline:
		return
	graphics_retro_mode = retro_pipeline.cycle_mode()
	if is_instance_valid(retro_picker):
		retro_picker.select(graphics_retro_mode)
	_apply_ui_skin()
	_save_graphics_settings()

## The menus and HUD take the look of the graphic style (CmrStyle skins), restyled live.
func _apply_ui_skin() -> void:
	var name := CmrStyle.skin_for_mode(graphics_retro_mode)
	if name == CmrStyle.skin:
		return
	CmrStyle.apply_skin(name, self)
	_lit_caption_color = CmrStyle.recolor(_lit_caption_color)
	_refresh_prompts()

func _on_codriver_voice_toggled(enabled: bool) -> void:
	codriver_voice = enabled
	if is_instance_valid(hud):
		hud.voice_on = enabled
	_save_graphics_settings()

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
	_rebuild_resolution_picker()
	_apply_resolution.call_deferred() # once the window has left (or entered) fullscreen
	_save_graphics_settings()

## Options → Resolution's entries: Native, the presets that fit the screen, and the window's own size.
func _resolution_options() -> Array[Vector2i]:
	var out: Array[Vector2i] = [Vector2i.ZERO]
	var screen := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	for r in RESOLUTIONS:
		if screen.x <= 0 or (r.x <= screen.x and r.y <= screen.y):
			out.append(r)
	var current := _current_resolution()
	if current.x > 0 and not out.has(current):
		out.append(current)
		out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x * a.y < b.x * b.y)
	return out

## The resolution the picker shows: the chosen one, or before any choice the window's size (Native in fullscreen).
func _current_resolution() -> Vector2i:
	if graphics_resolution.x >= 0:
		return graphics_resolution
	return DisplayServer.window_get_size() if graphics_display_mode == 0 else Vector2i.ZERO

func _rebuild_resolution_picker() -> void:
	if not is_instance_valid(resolution_picker):
		return
	_resolution_choices = _resolution_options()
	resolution_picker.clear()
	for r in _resolution_choices:
		resolution_picker.add_item("Native (desktop)" if r == Vector2i.ZERO else "%d × %d" % [r.x, r.y])
	resolution_picker.select(maxi(0, _resolution_choices.find(_current_resolution())))
	var caption := resolution_picker.get_parent().get_child(0) as Label
	if caption:
		caption.text = "RENDER RESOLUTION" if graphics_display_mode == 1 else "RESOLUTION"
	_update_resolution_note()

func _update_resolution_note() -> void:
	if not is_instance_valid(resolution_note):
		return
	if graphics_display_mode == 1:
		resolution_note.text = "In fullscreen the 3D view is drawn at this size and scaled up; menus stay sharp."
	else:
		resolution_note.text = "Window size; a fixed ratio adds black bars."

func _on_resolution_selected(index: int) -> void:
	if index < 0 or index >= _resolution_choices.size():
		return
	graphics_resolution = _resolution_choices[index]
	_apply_resolution()
	_save_graphics_settings()

## Windowed: sizes and centres the window (Native maximises it). Fullscreen: the screen keeps the desktop's
## resolution, and _fit_3d_views renders the 3D view at the chosen one instead (_render_resolution).
func _apply_resolution() -> void:
	if graphics_display_mode == 0 and graphics_resolution.x >= 0 and DisplayServer.get_name() != "headless":
		if graphics_resolution == Vector2i.ZERO:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
		else:
			if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
			var win_size := graphics_resolution.min(screen.size) if screen.size.x > 0 else graphics_resolution
			DisplayServer.window_set_size(win_size)
			var outer := DisplayServer.window_get_size_with_decorations().min(screen.size)
			DisplayServer.window_set_position(screen.position + (screen.size - outer) / 2)
	_fit_3d_views()

## The 3D view's render target for px screen pixels: in fullscreen with a resolution chosen, fitted inside it
## (never above the screen's own). The upscaler's render scale then applies on top.
func _render_resolution(px: Vector2i) -> Vector2i:
	var res := graphics_resolution
	if graphics_display_mode != 1 or res.x <= 0:
		return px
	var k := minf(1.0, minf(float(res.x) / px.x, float(res.y) / px.y))
	return Vector2i((Vector2(px) * k).round()).max(Vector2i(2, 2))

func _on_aspect_selected(index: int) -> void:
	graphics_aspect = clampi(index, 0, ASPECTS.size() - 1)
	_apply_aspect()
	_save_graphics_settings()

## Auto: the canvas expands to the window's shape. A ratio: the canvas takes that shape (at least 1600×900, as
## Auto would lay it out in such a window) and the window letterboxes or pillarboxes it with black bars.
func _apply_aspect() -> void:
	var win := get_window()
	var ratio: float = ASPECTS[graphics_aspect].ratio
	win.content_scale_size = aspect_canvas(ratio)
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND if ratio <= 0.0 else Window.CONTENT_SCALE_ASPECT_KEEP
	_fit_3d_views.call_deferred()

## The canvas size for an aspect ratio (0: Auto, the base canvas).
static func aspect_canvas(ratio: float) -> Vector2i:
	if ratio <= 0.0:
		return BASE_SIZE
	return Vector2i(roundi(maxf(BASE_SIZE.x, BASE_SIZE.y * ratio)), roundi(maxf(BASE_SIZE.y, BASE_SIZE.x / ratio)))

func _on_volume_selected(index: int, key: String) -> void:
	AudioSettings.set_level(key, index * 10)
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
	if config.load(SaveData.read_path("graphics.cfg")) == OK:
		graphics_display_mode = clampi(int(config.get_value("graphics", "display_mode", 0)), 0, 1)
		graphics_antialiasing = clampi(int(config.get_value("graphics", "antialiasing", 0)), 0, 2)
		graphics_vsync = bool(config.get_value("graphics", "vsync", true))
		graphics_fps_limit = clampi(int(config.get_value("graphics", "fps_limit", graphics_fps_limit)), 0, FPS_LIMITS.size() - 1)
		# older versions stored an SSR on/off switch
		var reflections = config.get_value("graphics", "reflections", 0)
		graphics_reflections = (1 if reflections else 0) if reflections is bool else int(reflections)
		graphics_reflections = clampi(graphics_reflections, 0, 2)
		graphics_ssao = bool(config.get_value("graphics", "ssao", true))
		graphics_quality = clampi(int(config.get_value("graphics", "quality", graphics_quality)), 0, GraphicsPresets.PRESETS.size() - 1)
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
		var res = config.get_value("graphics", "resolution", Vector2i(-1, -1))
		graphics_resolution = res if res is Vector2i and res.x >= -1 else Vector2i(-1, -1)
		graphics_aspect = clampi(int(config.get_value("graphics", "aspect", 0)), 0, ASPECTS.size() - 1)
		AudioSettings.load_from(config)
		codriver_voice = bool(config.get_value("audio", "co_driver_voice", true))
		graphics_retro_mode = clampi(int(config.get_value("graphics", "retro_mode", 0)), 0, RetroPipeline.MODE_NAMES.size() - 1)
		if retro_pipeline:
			retro_pipeline.set_mode(graphics_retro_mode)
		CmrStyle.apply_skin(CmrStyle.skin_for_mode(graphics_retro_mode)) # before the pages are built
	if not _upscaler_available(graphics_upscaler):
		graphics_upscaler = 0
	graphics_preset = GraphicsPresets.match_index(_graphics_snapshot())
	get_window().content_scale_factor = UI_SCALES[graphics_ui_scale]
	if graphics_display_mode == 1:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	_apply_resolution()
	_apply_aspect()
	AudioSettings.apply()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if graphics_vsync else DisplayServer.VSYNC_DISABLED)
	_apply_upscaling()

## The settings a graphics preset covers, as GraphicsPresets.match_index reads them.
func _graphics_snapshot() -> Dictionary:
	return {"quality": graphics_quality, "upscaler": graphics_upscaler, "upscale_preset": graphics_upscale_preset,
		"antialiasing": graphics_antialiasing, "ssao": graphics_ssao, "shadows": graphics_shadows, "reflections": graphics_reflections}

## Options → Graphics preset: sets every setting the preset covers, then applies them.
func _on_preset_selected(index: int) -> void:
	if index >= GraphicsPresets.PRESETS.size():
		return # Custom: leave the settings as they are
	var p := GraphicsPresets.preset(index)
	graphics_quality = p.quality
	graphics_upscaler = p.upscaler
	graphics_upscale_preset = p.upscale_preset
	graphics_antialiasing = p.antialiasing
	graphics_ssao = p.ssao
	graphics_shadows = p.shadows
	graphics_reflections = p.reflections
	upscaler_picker.select(upscaler_picker.get_item_index(graphics_upscaler))
	upscale_preset_picker.select(graphics_upscale_preset)
	antialiasing_picker.select(graphics_antialiasing)
	ssao_toggle.set_pressed_no_signal(graphics_ssao)
	shadows_toggle.set_pressed_no_signal(graphics_shadows)
	reflections_picker.select(graphics_reflections)
	if is_instance_valid(world_view):
		world_view.apply_graphics(graphics_quality)
	_apply_upscaling()
	_apply_world_graphics_settings()
	if open_world != null:
		open_world.apply_graphics(graphics_quality, graphics_ssao)
	_save_graphics_settings()

func _show_preset_state() -> void:
	if is_instance_valid(preset_picker):
		preset_picker.select(graphics_preset)
	if is_instance_valid(preset_note):
		preset_note.text = GraphicsPresets.describe(graphics_preset)

func _save_graphics_settings() -> void:
	graphics_preset = GraphicsPresets.match_index(_graphics_snapshot())
	_show_preset_state()
	var config := ConfigFile.new()
	config.load(SaveData.read_path("graphics.cfg"))
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
	config.set_value("graphics", "quality", graphics_quality)
	config.set_value("graphics", "ui_scale", graphics_ui_scale)
	config.set_value("graphics", "resolution", graphics_resolution)
	config.set_value("graphics", "aspect", graphics_aspect)
	AudioSettings.save_to(config)
	config.set_value("audio", "co_driver_voice", codriver_voice)
	config.set_value("graphics", "retro_mode", graphics_retro_mode)
	config.save(SaveData.path("graphics.cfg"))

func _layout_home_strip() -> void:
	_home_select(home_menu_index, false)

func _home_select(index: int, animate := true) -> void:
	var n := FRONT_MENU.size()
	var logical := posmod(index, n)
	if is_instance_valid(menu_home_strip) and menu_home_strip.get_child_count() > 0:
		if animate:
			# the shortest way round the loop: QUIT -> CAMPAIGN is one step on
			var delta := posmod(logical - home_menu_index, n)
			if delta > n / 2:
				delta -= n
			home_phys += delta
		else:
			home_phys = n + logical
	home_menu_index = logical
	if not is_instance_valid(menu_home_strip) or menu_home_strip.get_child_count() == 0:
		return
	for k in n * 3:
		var button: Button = menu_home_strip.get_child(k * 2)
		button.add_theme_color_override("font_color", ACCENT if k % n == home_menu_index else CmrStyle.DIM)
	menu_home_desc.text = "%s        %s" % [FRONT_MENU[home_menu_index].desc, _hint("home")]
	var target_x := _home_target_x()
	if home_tween and home_tween.is_running():
		home_tween.kill()
	if animate:
		home_tween = create_tween()
		home_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		home_tween.tween_property(menu_home_strip, "position:x", target_x, 0.32)
		home_tween.tween_callback(_home_recentre)
	else:
		menu_home_strip.position.x = target_x

func _home_target_x() -> float:
	var selected: Control = menu_home_strip.get_child(home_phys * 2)
	return get_viewport_rect().size.x * 0.16 - selected.position.x

## After a scroll: hop to the same word in the middle copy (invisible, the copies look alike).
func _home_recentre() -> void:
	var n := FRONT_MENU.size()
	if home_phys < n or home_phys >= n * 2:
		home_phys = n + home_menu_index
		menu_home_strip.position.x = _home_target_x()

func _home_item_pressed(index: int) -> void:
	if index != home_menu_index:
		_home_select(index)
		return
	_activate_home_item()

func _activate_home_item() -> void:
	match FRONT_MENU[home_menu_index].id:
		"campaign":
			_start_campaign_mode()
		"quick_race", "time_trial":
			is_campaign_mode = false
			is_championship_mode = false
			is_rally_mode = false
			is_time_trial_mode = FRONT_MENU[home_menu_index].id == "time_trial"
			_update_mode_view()
			_show_setup_page()
		"rally":
			is_campaign_mode = false
			is_championship_mode = false
			is_time_trial_mode = false
			is_rally_mode = true
			_load_rally()
			_update_mode_view()
			_show_setup_page()
		"championship":
			is_campaign_mode = false
			is_time_trial_mode = false
			is_rally_mode = false
			is_championship_mode = true
			_update_mode_view()
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
	_refresh_service_tab()
	for tab_name in TOP_MENU_TABS:
		var button: Button = menu_tab_buttons[tab_name]
		button.add_theme_color_override("font_color", ACCENT if tab_name == title else CmrStyle.DIM)

func _show_home() -> void:
	active_menu_page = "home"
	_hide_pages()
	get_viewport().gui_release_focus() # the strip takes ◂ ▸ and A itself
	menu_home.show()
	menu_tint.color = CmrStyle.TINT_HOME
	var backdrop := Race.get_track(_menu_track_key())
	if is_instance_valid(menu_home_art):
		menu_home_art.set_track(backdrop)
	menu_home_track.text = "%s  |  %.1f km" % [backdrop.name, backdrop.L / 1000.0]
	_home_select(home_menu_index, false)

## Hide every front-end page, leaving just the backdrop.
func _hide_pages() -> void:
	for page in [menu_home, menu_header, setup_panel, advanced_panel, car_panel, strategy_panel, repair_panel, repair_details, options_panel,
			circuit_map_frame, circuit_facts, menu_car_preview, menu_car_summary, menu_car_rule, menu_prompt]:
		if is_instance_valid(page):
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
	_refresh_prompts()
	_focus_page.call_deferred()

## (the circuit's map and facts are part of the Set Up page now)
func _show_information_page() -> void:
	_show_setup_page()

func _show_setup_page() -> void:
	active_menu_page = "setup"
	_hide_pages()
	_layout_left_column(true)
	menu_car_preview.show()
	menu_car_summary.show()
	menu_car_rule.show()
	circuit_map_frame.show()
	circuit_facts.show()
	setup_panel.show()
	menu_header.show()
	menu_tint.color = CmrStyle.TINT_SETUP
	_select_menu_tab("Set Up")
	menu_scroll.scroll_vertical = 0
	_update_information_page()
	_update_menu_car_summary()
	_refresh_prompts()
	_focus_setup_default.call_deferred()

## Format & start time, gearbox, aids and grid, pit strategy and the rules: the settings behind the core ones.
func _show_advanced_page() -> void:
	active_menu_page = "advanced"
	_hide_pages()
	advanced_panel.show()
	menu_header.show()
	menu_tint.color = CmrStyle.TINT_SETUP
	_select_menu_tab("Advanced")
	(adv_page.race as Control).visible = setup_race_button.visible
	(adv_page.scroll as ScrollContainer).scroll_vertical = 0
	_refresh_mod_toggles()
	_refresh_prompts()
	_focus_setup_default.call_deferred()

## Driver, paint, number and the car's set-up for the circuit.
func _show_car_page() -> void:
	active_menu_page = "car"
	_hide_pages()
	_layout_left_column(false)
	menu_car_preview.show()
	menu_car_summary.show()
	menu_car_rule.show()
	car_panel.show()
	menu_header.show()
	menu_tint.color = CmrStyle.TINT_SETUP
	_select_menu_tab("Car")
	(car_page.race as Control).visible = setup_race_button.visible
	(car_page.scroll as ScrollContainer).scroll_vertical = 0
	_update_menu_car_summary()
	_refresh_prompts()
	_focus_setup_default.call_deferred()

## Pit strategy plans for a quick race or time trial.
func _show_strategy_page() -> void:
	active_menu_page = "strategy"
	_hide_pages()
	strategy_panel.show()
	menu_header.show()
	menu_tint.color = CmrStyle.TINT_SETUP
	_select_menu_tab("Strategy")
	(strat_page.race as Control).visible = setup_race_button.visible
	(strat_page.scroll as ScrollContainer).scroll_vertical = 0
	_refresh_prompts()
	_focus_setup_default.call_deferred()

## The left column: the car over the circuit's map and name (Set Up), or a larger car (Car).
func _layout_left_column(with_map: bool) -> void:
	if with_map:
		_place_car_preview(0.045, 0.10, 0.555, 0.50)
		_anchor_rect(menu_car_rule, 0.045, 0.757, 0.555, 0.761)
		_anchor_rect(menu_car_summary, 0.045, 0.765, 0.555, 0.865)
	else:
		_place_car_preview(0.045, 0.12, 0.50, 0.64)
		_anchor_rect(menu_car_rule, 0.045, 0.66, 0.50, 0.664)
		_anchor_rect(menu_car_summary, 0.045, 0.675, 0.50, 0.79)

func _anchor_rect(c: Control, left: float, top: float, right: float, bottom: float) -> void:
	c.anchor_left = left
	c.anchor_top = top
	c.anchor_right = right
	c.anchor_bottom = bottom
	c.offset_left = 0
	c.offset_top = 0
	c.offset_right = 0
	c.offset_bottom = 0

func _show_repair_page() -> void:
	active_menu_page = "repair"
	_hide_pages()
	_place_car_preview(0.045, 0.12, 0.555, 0.53)
	menu_car_preview.show()
	repair_panel.show()
	repair_details.show()
	menu_header.show()
	menu_tint.color = CmrStyle.TINT_REPAIR
	_select_menu_tab("Service")
	get_viewport().gui_release_focus() # ↑ ↓ pick the part, A repairs it (_input)
	_select_repair_part(_first_damaged_part())
	_refresh_prompts()

func _set_championship_mode(value: bool) -> void:
	is_championship_mode = value
	if value:
		is_campaign_mode = false
	_update_mode_view()

func _set_race_format(index: int) -> void:
	if format_picker.selected != index:
		format_picker.select(index)
		_select_format(index)
	_update_menu_car_summary()

func _update_information_page() -> void:
	if not is_instance_valid(circuit_facts):
		return
	var track_key := _menu_track_key()
	var race_length := ""
	if is_championship_mode:
		var round_idx: int = _champ_round()
		track_key = _calendar()[round_idx]
		race_length = "Round %d of %d" % [round_idx + 1, _calendar().size()]
	elif is_campaign_mode:
		var st := CampaignData.get_stage(campaign_stage_index)
		track_key = st.track
		race_length = "%s · %d lap%s" % [st.title, st.laps, "" if st.laps == 1 else "s"]
	elif is_rally_mode:
		var ev := _rally()
		race_length = "Rally · stage %d of %d" % [mini(ev.stage_index + 1, ev.stage_count()), ev.stage_count()]
	elif format_picker.selected == 1:
		race_length = "Timed race · %s" % _fmt_hours(hours_picker.value)
	else:
		race_length = "%d lap%s" % [int(laps_picker.value), "" if int(laps_picker.value) == 1 else "s"]
	var current_track: Track = Race.get_track(track_key)
	var weather_options: Array[String] = ["Dry", "Wet", "Snow", "Hail", "Fog", "Variable"]
	var weather_name: String = str(CampaignData.get_stage(campaign_stage_index).weather).capitalize() if is_campaign_mode else weather_options[weather_picker.selected]
	var opponents_count: int = CampaignData.get_stage(campaign_stage_index).opponents if is_campaign_mode else int(opponents_picker.value)
	if is_championship_mode:
		weather_name = _season_weather(_champ_round()).capitalize()
		opponents_count = int(_season().opponents)
	elif is_time_trial_mode:
		opponents_count = 0
	var start_time_val: float = CampaignData.get_stage(campaign_stage_index).start_hour if is_campaign_mode else start_hour_picker.value
	circuit_facts.text = "%s  ·  START %s  ·  %s\n%s" % [weather_name.to_upper(), _format_start_time(start_time_val),
		"SOLO" if opponents_count == 0 else "%d OPPONENT%s" % [opponents_count, "" if opponents_count == 1 else "S"],
		_records_text(track_key).strip_edges().to_upper()]
	if information_map.has_method("set_track"):
		information_map.set_track(current_track, true)
	if is_instance_valid(menu_home_art) and not is_championship_mode and not is_campaign_mode:
		menu_home_art.set_track(current_track)

## The player's lap records on a circuit, for the Information page.
func _records_text(track_key: String) -> String:
	var parts: Array[String] = []
	for cond in LapRecords.CONDITIONS:
		var r := LapRecords.record(track_key, cond)
		if r.has("t"):
			parts.append("%s %s" % [Race.fmt_time(float(r.t)), cond])
	return "\nLap record   %s" % (" · ".join(parts) if parts.size() else "none yet")

## A line under a results heading for the lap records the player set in this session.
func _add_record_note(col: VBoxContainer, session: Race) -> void:
	if not lap_records or lap_records.race != session or lap_records.new_records.is_empty():
		return
	var best := {}
	for r in lap_records.new_records: # each one beats the last, so the latest per conditions is the record
		best[r.conditions] = r.t
	var parts := []
	for cond in best:
		parts.append("%s (%s)" % [Race.fmt_time(best[cond]), cond])
	var note := _label("New lap record at %s: %s. Its ghost will chase you next time." % [session.track.name, ", ".join(parts)], 13, CmrStyle.ORANGE_SOFT)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(note)

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
	pause_dim = ColorRect.new()
	pause_dim.color = Color(0, 0, 0, 0.6)
	pause_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_dim.hide()
	add_child(pause_dim)
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
	pause_dim.visible = on
	pause_buttons[1].text = "RESTART QUALIFYING" if quali_session else "RESTART RACE"
	pause_buttons[2].text = "END SESSION" if quali_session else "RETIRE & SEE RESULTS"
	if on:
		CoDriver.silence()
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
			_start_race(true)
		"retire":
			_set_paused(false)
			race.player.dnf = true
			race.player.dnf_reason = "Retired"
			if quali_session:
				race.phase = "finished" # no time set: the sheet puts you at the back
				_show_results()
			else:
				_begin_skip()
		"menu":
			_quit_race()

func _commit_brain() -> void:
	if race and race.brain:
		race.brain.commit()

# ------------------------------------------------------------------------------------- circuit prefetch
## Building a circuit's Track (spline, racing line, speed profile: 0.1-0.6 s) and calibrating the strategist
## on it (reference laps: 0.3-1.8 s) used to freeze the set-up page on the first visit to each circuit. A
## worker thread does both for every circuit, one at a time, in the background: pure data, on its own Track
## and Strategy copies, handed to the main thread (Race's track cache, the cached Track's cal) once done.
var _prefetch_queue: Array = [] ## [key, phase] still to do; phase "track" builds the Track, "cal" calibrates
var _prefetch_started := false
var _prefetch_task := -1 ## WorkerThreadPool task id, -1 when idle
var _prefetch_job: Array = [] ## the [key, phase] the task is on
var _prefetch_result = null ## the task's Track ("track") or cal Dictionary ("cal"), read once it has finished

func _pump_track_prefetch() -> void:
	if _prefetch_task != -1:
		if not WorkerThreadPool.is_task_completed(_prefetch_task):
			return
		WorkerThreadPool.wait_for_task_completion(_prefetch_task)
		_prefetch_task = -1
		var key: String = _prefetch_job[0]
		if _prefetch_job[1] == "track":
			if not Race._track_cache.has(key) and _prefetch_result is Track:
				Race._track_cache[key] = _prefetch_result
		elif _prefetch_result is Dictionary and not (_prefetch_result as Dictionary).is_empty():
			var cached: Track = Race._track_cache.get(key)
			if cached and cached.cal.is_empty():
				cached.cal = _prefetch_result
		_prefetch_result = null
	if not _prefetch_started:
		_prefetch_started = true
		# outwards from the circuit on the page, the order ◂ ▸ reaches them; every Track first, then the strategist
		var at: int = track_picker.selected if is_instance_valid(track_picker) else 0
		var order: Array = [TRACK_KEYS[at]]
		for d in range(1, TRACK_KEYS.size()):
			for k in [TRACK_KEYS[posmod(at + d, TRACK_KEYS.size())], TRACK_KEYS[posmod(at - d, TRACK_KEYS.size())]]:
				if not order.has(k):
					order.append(k)
		for k in order:
			_prefetch_queue.append([k, "track"])
		for k in order:
			_prefetch_queue.append([k, "cal"])
	if race or _starting:
		return # no background work while a race runs
	while not _prefetch_queue.is_empty():
		var job: Array = _prefetch_queue.pop_front()
		var cached: Track = Race._track_cache.get(job[0])
		if job[1] == "track" and cached:
			continue
		if job[1] == "cal" and cached and not cached.cal.is_empty():
			continue
		_prefetch_job = job
		_prefetch_task = WorkerThreadPool.add_task(_prefetch_work.bind(job[0], job[1]), false, "Prefetch %s %s" % job)
		return

## Worker thread: touches nothing shared (a Track of its own; for "cal", one that is never handed over).
func _prefetch_work(key: String, phase: String) -> void:
	var tr := Track.new(Track.load_def(key))
	if phase == "track":
		_prefetch_result = tr
	else:
		_prefetch_result = Strategy.new(CarModel.new(), Tyres.new()).calibrate(tr)

## Moves a circuit's prefetch to the front of the queue (the page is on it now).
func _prioritise_track_prefetch(key: String) -> void:
	for phase in ["cal", "track"]:
		var job := [key, phase]
		var i := _prefetch_queue.find(job)
		if i > 0:
			_prefetch_queue.remove_at(i)
			_prefetch_queue.push_front(job)

## Whether the prefetcher will still deliver this circuit's strategist calibration.
func _track_prefetch_pending(key: String) -> bool:
	if race or _starting:
		return false
	return _prefetch_queue.has([key, "cal"]) or (_prefetch_task != -1 and _prefetch_job == [key, "cal"])

func _exit_tree() -> void:
	if _prefetch_task != -1:
		WorkerThreadPool.wait_for_task_completion(_prefetch_task)
		_prefetch_task = -1

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

## Sets up and shows a race from the set-up page (or restarts the one running). While it is being set up
## nothing steps (neither the race on screen nor the new one) and further presses are ignored; the race
## shown until now is disposed once the world and the HUD have the new one.
## restart: the pause menu's RESTART (the same event again, so no service stop in between).
func _start_race(restart := false) -> void:
	if _starting:
		return
	if not restart and (is_championship_mode or is_campaign_mode or is_rally_mode) and _service_due():
		# CMR 2.0: between events the car goes through the service area first
		if race:
			_go_to_service()
		else:
			_show_repair_page()
		return
	_starting = true
	var shown: Race = world_view.race
	await _set_up_race()
	_starting = false
	if shown and shown != world_view.race:
		shown.dispose()

func _set_up_race() -> void:
	status_label.text = "Configuring car and optimizing race strategy..."
	status_label.modulate = ACCENT
	campaign_cleared = false
	await get_tree().process_frame

	if _strategy_pending and not is_championship_mode and not is_campaign_mode and not is_rally_mode and not is_time_trial_mode:
		status_label.text = "The strategist is still working out the plans — try again in a moment."
		return
	var settings := RaceSettings.new()
	var plan = current_plan
	var quali_run := false
	if is_championship_mode:
		if _next_round() >= _calendar().size():
			champ_data = {"round": 0, "scored": false, "table": {}, "config": _season()} # a new season on the same settings
		if champ_data.get("scored", false):
			champ_data["round"] = int(champ_data.get("round", 0)) + 1
			champ_data["scored"] = false
		_save_championship()
		quali_run = quali_picker.selected != 2 and _round_quali().is_empty()
		var round_idx := int(champ_data.get("round", 0))
		var t_key: String = _calendar()[round_idx]
		settings.track = t_key
		var defaults: Dictionary = TRACK_DEFAULTS.get(t_key, {"laps": 6, "wear": 2.0})
		var season := _season()
		settings.laps = _season_laps(t_key)
		settings.opponents = clampi(int(season.opponents), 1, 15)
		settings.difficulty = ["easy", "medium", "hard", "alien"][clampi(int(season.difficulty), 0, 3)]
		settings.weather = _season_weather(round_idx)
		settings.wear_mult = defaults.wear
		settings.fuel_mult = defaults.get("fuel", 1.0)
		settings.format = "laps"
		settings.start_hour = start_hour_picker.value
	elif is_campaign_mode:
		var stage: Dictionary = CampaignData.get_stage(campaign_stage_index)
		settings.track = stage.track
		settings.laps = stage.laps
		settings.format = "laps"
		settings.weather = stage.weather
		settings.opponents = stage.opponents
		settings.difficulty = stage.difficulty
		settings.start_hour = stage.start_hour
		settings.wear_mult = stage.get("wear_mult", 2.0)
		settings.fuel_mult = stage.get("fuel_mult", 1.0)
	elif is_rally_mode:
		if _rally().is_over():
			_new_rally(_rally().key) # the rally was finished: run it again from the first stage
		var sd := _rally().stage_def()
		settings.track = sd.track
		settings.laps = 1
		settings.start_hour = float(sd.get("hour", 12.0))
		plan = {} # a stage has no strategy: the race gives the car its one-stint fallback
	else:
		settings.track = TRACK_KEYS[track_picker.selected]
		settings.laps = int(laps_picker.value)
		settings.format = "time" if format_picker.selected == 1 else "laps"
		settings.hours = hours_picker.value
		settings.start_hour = start_hour_picker.value
		settings.opponents = 0 if is_time_trial_mode else int(opponents_picker.value)
		settings.difficulty = ["easy", "medium", "hard", "alien"][difficulty_picker.selected]
		settings.weather = ["dry", "wet", "snow", "hail", "fog", "variable"][weather_picker.selected]
		settings.wear_mult = wear_picker.value
		settings.fuel_mult = fuel_picker.value

	settings.gearbox = "manual" if gearbox_picker.selected == 1 else "auto"
	settings.player_name = player_name_edit.text.strip_edges() if not player_name_edit.text.strip_edges().is_empty() else "You"
	settings.player_number = int(player_number_picker.value)
	settings.player_color = player_color_picker.color
	settings.stripes = player_stripes_toggle.button_pressed
	settings.finish = player_finish_picker.selected
	var stage_class := str(CampaignData.get_stage(campaign_stage_index).get("car_class", "")) if is_campaign_mode else ""
	settings.car_class = "hypercar" if (stage_class == "hypercar" or car_class_picker.selected == 1) and _hypercar_open() else "stock"
	if settings.car_class == "hypercar":
		# AF Corse's Le Mans winner: yellow, black stripes, no. 83
		settings.player_color = Hypercar.PAINT
		settings.player_number = Hypercar.NUMBER
		settings.stripes = true
		settings.finish = 0
	settings.ai_learning = "off" if ai_learning_picker.selected == 1 else "on"
	settings.bot_physics = ["on", "off", "near"][bot_physics_picker.selected]
	settings.grid = str(CampaignData.get_stage(campaign_stage_index).get("grid", "middle")) if is_campaign_mode else ["pole", "middle", "back", "random"][grid_picker.selected] # a stage sets its own grid
	settings.assists = ["full", "abs", "off"][assists_picker.selected]
	settings.mandatory_stop = mandatory_stop_toggle.button_pressed
	settings.two_compounds = two_compounds_toggle.button_pressed
	settings.refuel = refuel_toggle.button_pressed
	settings.collisions = collisions_toggle.button_pressed
	settings.race_control = race_control_toggle.button_pressed
	# mechanical damage is opt-in; a championship with Damage & Repairs on has it (its service area needs it)
	settings.mechanical_damage = damage_toggle.button_pressed or (is_championship_mode and _service_allocation() > 0)
	settings.dynamic_running = dynamic_toggle.button_pressed
	settings.draft = draft_toggle.button_pressed
	settings.auto_strategist = strategist_toggle.button_pressed
	settings.parallel = parallel_toggle.button_pressed
	settings.crew = ["pro", "club", "amateur"][crew_picker.selected]
	settings.car_setup = CarSetup.clean(car_setups.get(settings.track, {}))
	if quali_run:
		Qualifying.configure(settings)
	elif is_championship_mode and not _round_quali().is_empty():
		settings.quali_grid = _round_quali().grid # the round's qualifying sets the grid
	if is_rally_mode:
		Rally.configure_stage(settings, _rally().stage_def(), _rally().difficulty)
	elif is_time_trial_mode:
		TimeTrial.configure(settings, tt_start_picker.selected == 1)
		plan = {}

	await _open_loading_screen(settings, quali_run)
	if quali_run or is_time_trial_mode or is_rally_mode:
		plan = {} # the session builds its own one-run plan
	elif is_championship_mode or is_campaign_mode or settings.car_class == "hypercar":
		# every round is planned by the strategist for that circuit's race length, tyre wear and fuel use
		var opts := _plan_opts(Race.get_track(settings.track), settings.laps, settings.wear_mult, settings.weather if is_campaign_mode or is_championship_mode else "")
		opts.fuel_mult = settings.fuel_mult
		var options: Array = _models_for(settings.car_class).strategy.plan(opts)
		plan = options[0] if options.size() else null

	if plan == null:
		if is_campaign_mode:
			plan = {"stints": [{"c": "soft" if settings.weather == "dry" else ("wet" if settings.weather in ["wet", "snow", "hail"] else "soft"), "laps": settings.laps}]}
		else:
			status_label.text = "No valid pit strategy for these settings — pick a plan or fix the custom one."
			status_label.modulate = DANGER
			loading_screen.hide()
			return
	_save_race_settings()
	await _loading_progress(0.35)
	race = Race.new(settings, (plan as Dictionary).duplicate(true), -1, _models_for(settings.car_class))
	race.set_mods(_active_mods())
	quali_session = quali_run
	if is_rally_mode:
		_rally().begin_stage(race) # the damage carried in, the rivals' runs (the lap model's calibration, once per circuit)
	var carried := _carried_car() if settings.race_control and not is_rally_mode else {}
	if carried.get("parts", {}) is Dictionary and not carried.get("parts", {}).is_empty():
		# what the service crew didn't get to is still broken (the field's cars come rebuilt)
		Service.fit(race.player, carried.parts, float(carried.get("pull", 0.0)))
	if quali_run and quali_picker.selected == 1:
		# the co-driver runs the laps: no session to drive, straight to the sheet
		var sim_race := race
		race = null
		quali_session = false
		_hide_front_end()
		status_label.text = ""
		loading_screen.hide()
		_show_quali_sheet(sim_race, Qualifying.sheet(sim_race, Qualifying.simulated_player_time(sim_race)), true)
		sim_race.dispose()
		return
	await _loading_progress(0.6)
	world_view.mods = race.mods
	world_view.set_race(race)
	lap_records = LapRecords.new(race)
	lap_ghost.start(world_view, lap_records)
	await _loading_progress(1.0)

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

	_hide_front_end()
	result_panel.hide()
	pause_panel.hide()
	pause_dim.hide()
	get_viewport().gui_release_focus()
	hud.voice_on = codriver_voice
	hud.start(race, world_view, audio)
	hud.records = lap_records
	status_label.text = ""
	loading_screen.hide()

	if is_instance_valid(audio):
		audio.beep(880.0, 3)

func _hide_front_end() -> void:
	setup_panel.hide()
	advanced_panel.hide()
	car_panel.hide()
	strategy_panel.hide()
	repair_panel.hide()
	repair_details.hide()
	options_panel.hide()
	circuit_map_frame.hide()
	circuit_facts.hide()
	menu_car_preview.hide()
	menu_car_summary.hide()
	menu_car_rule.hide()
	menu_home.hide()
	menu_tint.hide()
	menu_header.hide()
	menu_prompt.hide()

## Cover the front end with the stage loading screen and let it draw before the race is built on this thread.
func _open_loading_screen(settings: RaceSettings, qualifying := false) -> void:
	var track := Race.get_track(settings.track)
	var race_length := ("%d lap%s" % [settings.laps, "" if settings.laps == 1 else "s"]) if settings.format == "laps" else _fmt_hours(settings.hours)
	if qualifying:
		race_length = "qualifying"
	var segments: Array = [track.name, race_length]
	if is_championship_mode:
		segments.insert(1, "round %d" % (_champ_round() + 1))
	elif is_campaign_mode:
		var st := CampaignData.get_stage(campaign_stage_index)
		segments.insert(0, st.get("title", "Campaign Stage"))
	loading_screen.open(segments, "Circuit Length", "%.2f km" % (track.L / 1000.0))
	await _loading_progress(0.15)

func _loading_progress(fraction: float) -> void:
	loading_screen.set_progress(fraction)
	await RenderingServer.frame_post_draw

func _show_results() -> void:
	if quali_session:
		if is_instance_valid(audio):
			audio.update_car(race.player, false)
		_show_quali_sheet(race, Qualifying.sheet(race), false)
		return
	if is_rally_mode and race.stage:
		_show_rally_results()
		return
	hud.hide()
	pause_panel.hide()
	pause_dim.hide()
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
	var sub := "%s · %s%d lap%s · %s" % [race.track.name, ("%s · " % _fmt_hours(race.duration / 3600.0)) if race.timed else "", laps,
		"" if laps == 1 else "s",
		{"dry": "Dry", "wet": "Wet", "variable": "Variable weather"}.get(race.s.weather, str(race.s.weather).capitalize())]
	if race.projected:
		sub += " · Finish projected from the field's pace"
	if fast:
		sub += " · Fastest lap %s %s" % [fast.car.name, Race.fmt_time(fast.t)]
	col.add_child(_label("CHEQUERED FLAG · %s" % title, 26, INK))
	if is_campaign_mode and me.car.dnf:
		var dnf_res := CampaignData.record_result(campaign_stage_index, 999) # a retirement counts as a failed try
		col.add_child(_label("OBJECTIVE FAILED — you did not finish. Retry to advance!", 14, DANGER))
		col.add_child(_label(_award_stage_fans(int(dnf_res.fans)), 13, CmrStyle.AMBER))
	elif is_campaign_mode:
		var c_res := CampaignData.record_result(campaign_stage_index, me.pos)
		campaign_cleared = c_res.success
		var c_box := VBoxContainer.new()
		c_box.add_theme_constant_override("separation", 3)
		col.add_child(c_box)
		var fan_line := _award_stage_fans(int(c_res.fans))
		if c_res.success:
			c_box.add_child(_label("★ STAGE OBJECTIVE COMPLETED! ★", 18, CmrStyle.GREEN))
			c_box.add_child(_label("🏆 Trophy Awarded: %s" % c_res.trophy, 14, CmrStyle.AMBER))
			if c_res.newly_unlocked:
				var nxt_st := CampaignData.get_stage(c_res.unlocked_stage)
				c_box.add_child(_label("▶ Next Stage Unlocked: %s (%s)" % [nxt_st.title, nxt_st.act_name], 14, ACCENT))
		else:
			var req_pos: int = CampaignData.get_stage(campaign_stage_index).target_pos
			c_box.add_child(_label("OBJECTIVE FAILED — Finished P%d (Target: P%d or better). Retry to advance!" % [me.pos, req_pos], 14, DANGER))
		c_box.add_child(_label(fan_line, 13, CmrStyle.AMBER))
	var sub_label := _label(sub, 13, MUTED)
	sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(sub_label)
	_add_record_note(col, race)
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
	last_race_parts = Service.snapshot(race.player)
	if is_campaign_mode:
		CampaignData.save_car({}) # damage belongs to rally (and a championship that turns it on): a stage always starts with a sound car
	if is_champ:
		_score_championship_round(rows)
	var service_next := _service_due() and (is_campaign_mode or int(champ_data.get("round", 0)) < _calendar().size() - 1)
	if service_next:
		var damaged := Service.total(last_race_parts)
		var svc := _label("Your car is %d%% damaged. The crew has %d minutes in the service area before the next %s; whatever they don't fix is still broken at the start." % [
			roundi(damaged * 100.0), _service_allocation(), "stage" if is_campaign_mode else "round"], 13, CmrStyle.ORANGE_SOFT)
		svc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(svc)
	var headers := ["POS", "NO.", "DRIVER", "LAPS", "TIME / GAP", "BEST LAP", "STOPS", "TYRES"]
	var widths := [46, 44, 250, 50, 210, 100, 56, 120]
	if is_champ:
		headers.append("PTS")
		widths.append(46)
	# leave out the columns that say nothing this time: no lap set (a short race finished on projection), nobody pitted
	var keep: Array[int] = []
	var any_best := rows.any(func(r) -> bool: return (r.car as RaceCar).best_lap != null and float((r.car as RaceCar).best_lap) > 0.0)
	var any_stops := rows.any(func(r) -> bool: return (r.car as RaceCar).stops > 0)
	for k in headers.size():
		if (k == 5 and not any_best) or ((k == 6 or k == 7) and not any_stops):
			continue
		keep.append(k)
	headers = keep.map(func(k: int) -> Variant: return headers[k])
	widths = keep.map(func(k: int) -> Variant: return widths[k])
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
		cells = keep.map(func(k: int) -> Variant: return cells[k])
		var fill: Color = CmrStyle.ORANGE if car.is_player else (CmrStyle.FIELD if r.pos % 2 == 1 else CmrStyle.FIELD_DIM)
		var row := _result_row(cells, widths, CmrStyle.box(fill, Color.TRANSPARENT, 14, 3), CmrStyle.INK, 15, car.color)
		if fast and fast.car == car and keep.has(5):
			(row.get_child(0).get_child(keep.find(5)) as Label).add_theme_color_override("font_color", CmrStyle.PLUM)
		table.add_child(row)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	var primary: Button
	if is_champ:
		_render_championship_standings(col)
		var last := int(champ_data.get("round", 0)) >= _calendar().size() - 1
		if last:
			primary = _button("FINISH CHAMPIONSHIP", ACCENT)
			primary.pressed.connect(_return_to_setup)
		else:
			var next_name: String = Race.get_track(_calendar()[int(champ_data.get("round", 0)) + 1]).name
			var next_label := "NEXT ROUND: %s ▸" % next_name.to_upper()
			if quali_picker.selected != 2:
				next_label = "NEXT: %s QUALIFYING ▸" % next_name.to_upper()
			primary = _button(next_label, ACCENT)
			primary.pressed.connect(_start_race)
	elif is_campaign_mode:
		if campaign_cleared and campaign_stage_index < CampaignData.STAGES.size() - 1:
			primary = _button("NEXT STAGE ▸", ACCENT)
			primary.pressed.connect(func() -> void:
				campaign_stage_index += 1
				_populate_campaign_stages()
				_apply_campaign_stage(campaign_stage_index)
				_start_race()
			)
		elif campaign_cleared:
			primary = _button("RACE THE FINALE AGAIN ▸", ACCENT)
			primary.pressed.connect(_start_race)
		else:
			primary = _button("RETRY STAGE ▸", ACCENT)
			primary.pressed.connect(_start_race)
	else:
		primary = _button("RACE AGAIN", ACCENT)
		primary.pressed.connect(_start_race)
	if service_next:
		# the service area is the way on: the next event starts from there
		primary.text = "SERVICE AREA ▸"
		for c in primary.pressed.get_connections():
			primary.pressed.disconnect(c.callable)
		primary.pressed.connect(_go_to_service)
	primary.custom_minimum_size.y = 44
	buttons.add_child(primary)
	var back := _button("BACK TO MENU", CmrStyle.FIELD)
	back.custom_minimum_size.y = 44
	back.pressed.connect(_return_to_setup)
	buttons.add_child(back)
	col.add_child(buttons)
	primary.grab_focus()
	_fit_result_panel(col)

## This round's saved qualifying ({round, grid, pos, rows, simulated}), or {} when it hasn't been run.
func _round_quali() -> Dictionary:
	var q = champ_data.get("quali", {})
	if q is Dictionary and int(q.get("round", -1)) == _next_round() and q.has("grid"):
		return q
	return {}

## The qualifying time sheet (NASCAR-style: lap, gap to pole, average speed) that sets the grid. It is saved
## with the championship, so the race can be started later from the menu.
func _show_quali_sheet(qrace: Race, rows: Array, simulated: bool) -> void:
	hud.hide()
	pause_panel.hide()
	pause_dim.hide()
	result_panel.show()
	for child in result_scroll.get_children():
		child.queue_free()
	var me: Dictionary = rows[0]
	for r in rows:
		if r.is_player:
			me = r
	var saved_rows := rows.map(func(r: Dictionary) -> Dictionary:
		var d := r.duplicate()
		d.color = (r.color as Color).to_html(false)
		return d)
	champ_data["quali"] = {"round": _next_round(), "grid": Qualifying.grid_from(qrace, rows), "pos": me.pos,
		"simulated": simulated, "rows": saved_rows}
	_save_championship()

	var col := _column(result_scroll, 8)
	col.custom_minimum_size.x = 1060
	var title := "P%d OF %d" % [me.pos, rows.size()] if me.time != null else "NO TIME SET — YOU START FROM THE BACK"
	col.add_child(_label("QUALIFYING · %s" % title, 26, INK))
	var sub := "%s · Round %d of %d" % [qrace.track.name, _next_round() + 1, _calendar().size()]
	if simulated:
		sub += " · Your co-driver ran the laps"
	elif me.time != null:
		var laps: Array = qrace.player.lap_times.slice(1).map(func(x) -> String: return Race.fmt_time(x))
		sub += " · Timed %s: %s" % ["laps" if laps.size() > 1 else "lap", "  ".join(laps)]
	var pole: Dictionary = rows[0]
	if pole.time != null:
		sub += " · Pole: %s %s" % [pole.name, Race.fmt_time(pole.time)]
	var sub_label := _label(sub, 13, MUTED)
	sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(sub_label)
	_add_record_note(col, qrace)

	# data first: position, driver, time, gap (the speed is a muted last column); a long field scrolls
	# inside the table so the header stays up
	var table := ResultTable.new()
	col.add_child(table)
	table.setup(ResultTable.quali_columns(), _table_room(300.0))
	for r in rows:
		table.add_row(ResultTable.quali_cells(r), r.is_player, r.color, r.time == null)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	var primary := _button("START RACE ▸", ACCENT)
	primary.custom_minimum_size.y = 44
	primary.pressed.connect(_start_race)
	buttons.add_child(primary)
	var back := _button("BACK TO MENU", CmrStyle.FIELD)
	back.custom_minimum_size.y = 44
	back.pressed.connect(_return_to_setup)
	buttons.add_child(back)
	col.add_child(buttons)
	primary.grab_focus()
	_fit_result_panel(col)

## Sizes the results sheet to its content (a short field leaves no empty band at the bottom), up to its
## full height, beyond which it scrolls; kept centred on screen.
func _fit_result_panel(col: Control) -> void:
	# until the column is laid out its wrapped lines measure as if it had no width
	for k in 5:
		await get_tree().process_frame
		if not is_instance_valid(col) or not result_panel.visible:
			return
		if col.size.x > 0.0:
			break
	var pad := result_panel.get_theme_stylebox("panel").get_minimum_size().y
	# never taller than the canvas (a large interface size shrinks it): the sheet scrolls instead
	var h := minf(minf(820.0, get_viewport_rect().size.y - 40.0), ceilf(col.get_combined_minimum_size().y + pad))
	result_panel.custom_minimum_size.y = h
	result_panel.offset_top = -h * 0.5
	result_panel.offset_bottom = h * 0.5

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
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS # a cut cell says so ("…")
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
	if r.car.dnf or r.pos > _points_table().size():
		return 0
	return _points_table()[r.pos - 1]

func _sorted_standings() -> Array:
	return ResultTable.rank_standings(champ_data.get("table", {}).values()).map(func(r: Dictionary) -> Dictionary: return r.entry)

func _render_championship_standings(col: VBoxContainer) -> void:
	var list := _sorted_standings()
	var round_idx := int(champ_data.get("round", 0))
	var heading := "STANDINGS AFTER ROUND %d OF %d" % [round_idx + 1, _calendar().size()]
	if round_idx >= _calendar().size() - 1 and not list.is_empty():
		heading = "YOU ARE THE CHAMPION!" if list[0].get("is_player", false) else "CHAMPION: %s" % str(list[0].name).to_upper()
	var div := _label(heading, 16, ACCENT)
	div.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(div)
	var table := ResultTable.new()
	col.add_child(table)
	table.setup(ResultTable.standings_columns(), _table_room(330.0))
	var ranked := ResultTable.rank_standings(list)
	var leader_points: int = int(ranked[0].entry.points) if not ranked.is_empty() else 0
	for r in ranked:
		table.add_row(ResultTable.standings_cells(r, leader_points), r.entry.get("is_player", false), null, false)

## Height a results table may take before it scrolls: what the canvas leaves after the title, notes and
## buttons around it (chrome px).
func _table_room(chrome: float) -> float:
	return clampf(get_viewport_rect().size.y - 40.0 - chrome - 60.0, 160.0, 560.0)

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
		if car.is_player:
			# the car goes to the service area as it finished, with a fresh time allocation
			champ_data["car"] = {"parts": Service.snapshot(car), "pull": Service.pull_rate(car), "used": 0, "serviced": false} \
				if _service_allocation() > 0 else {}
	_save_championship()

## The championship round to drive next: a round whose results were already seen is done.
func _next_round() -> int:
	var r := int(champ_data.get("round", 0))
	return r + 1 if champ_data.get("scored", false) else r

## The round the menus show (a finished championship shows its last round).
func _champ_round() -> int:
	return mini(_next_round(), _calendar().size() - 1)

func _return_to_setup(to_service := false) -> void:
	_commit_brain()
	var shown: Race = world_view.race
	if race and race != shown:
		race.dispose()
	race = null
	lap_records = null
	lap_ghost.start(world_view, null)
	hud.records = null
	paused = false
	skipping = false
	hud.hide()
	pause_panel.hide()
	pause_dim.hide()
	get_viewport().gui_release_focus()
	if is_instance_valid(audio):
		audio.update_car(null, false)
	status_label.text = ""
	status_label.modulate = MUTED
	result_panel.hide()
	var raced := campaign_stage_index
	if is_campaign_mode and campaign_cleared and CampaignData.is_unlocked(campaign_stage_index + 1) and campaign_stage_index < CampaignData.STAGES.size() - 1:
		campaign_stage_index += 1 # stage won: the menu briefs the next one
	campaign_cleared = false
	_update_mode_view()
	_show_setup_page()
	_update_championship_view()
	_update_ai_memory()

	world_view.release_race() # keeps the circuit built: a race there again starts without a rebuild
	if shown:
		shown.dispose() # (after the world has let go of it)
	if is_campaign_mode and world_return >= 0 and not to_service:
		world_return = -1
		_enter_open_world(raced) # a stage started at a beacon in Brzeszcze ends back at its beacon
	elif not to_service:
		world_return = -1 # (through the service area the way back to the open world is kept)

## From the results to the Repair page, to spend the service time before the next round.
func _go_to_service() -> void:
	_return_to_setup(true)
	_show_repair_page()

func _select_track(index: int) -> void:
	var key: String = TRACK_KEYS[index]
	laps_picker.max_value = 200 if key == "indy" else 99
	if not _loading_settings:
		# e.g. a 20.7 km Nordschleife lap needs a shorter race and gentler tyre wear
		var defaults: Dictionary = TRACK_DEFAULTS.get(key, {"laps": 6, "wear": 2.0})
		_loading_settings = true
		laps_picker.value = defaults.laps
		wear_picker.value = defaults.wear
		fuel_picker.value = defaults.get("fuel", 1.0)
		_loading_settings = false
	_prioritise_track_prefetch(key)
	_update_information_page()
	_update_menu_car_summary()
	_update_ai_memory()
	_queue_strategy_refresh()

## Main menu → CAMPAIGN: the briefing of the furthest stage unlocked. The stage dictates the race (circuit,
## laps, weather, field, start time), so the quick-race settings are left as they were.
func _start_campaign_mode() -> void:
	is_time_trial_mode = false
	is_rally_mode = false
	is_campaign_mode = true
	is_championship_mode = false
	campaign_cleared = false
	var prog := CampaignData.load_progress()
	campaign_stage_index = clampi(int(prog.get("unlocked", 0)), 0, CampaignData.STAGES.size() - 1)
	_update_mode_view()
	if OpenWorld.available():
		_enter_open_world("") # the campaign lives in the open world: drive to the next stage's beacon
	else:
		_show_setup_page()

## The campaign's open world (scripts/world/open_world.gd), built on first use and kept for the way back.
## spawn: "" where the car was left, or a stage index to start at that stage's beacon.
func _enter_open_world(spawn) -> void:
	if open_world == null:
		open_world = OpenWorld.new()
		add_child(open_world)
		open_world.stage_requested.connect(_on_world_stage)
		open_world.leave_requested.connect(_on_world_leave)
	_hide_front_end()
	result_panel.hide()
	active_menu_page = "world"
	get_viewport().gui_release_focus()
	await open_world.open(spawn, {
		"gearbox": "manual" if gearbox_picker.selected == 1 else "auto",
		"assists": ["full", "abs", "off"][assists_picker.selected],
		"paint": player_color_picker.color,
		"number": int(player_number_picker.value),
		"retro_material": retro_pipeline.material if retro_pipeline else null,
		"source_viewport": render_viewport,
		"audio": audio,
		"quality": graphics_quality,
		"ssao": graphics_ssao,
	})

## Pays a campaign result's fans into the open-world progress (live if the world is loaded, else the save) and
## returns the line the results show: the fans and the level they brought.
func _award_stage_fans(fans: int) -> String:
	var before := 0
	var after := 0
	if open_world != null and open_world.progress != null:
		before = open_world.progress.fans
		open_world.award_fans(fans)
		after = open_world.progress.fans
	else:
		var wp := WorldProgress.load_progress()
		before = wp.fans
		wp.fans += fans
		wp.save()
		after = wp.fans
	var lv := FanLevels.level(after)
	var line := "+%s FANS" % OpenWorldHud._thousands(fans)
	if lv > FanLevels.level(before):
		line += "  ·  FAN LEVEL UP: LEVEL %d, %s" % [lv, FanLevels.title(lv).to_upper()]
	else:
		line += "  ·  LEVEL %d, %s" % [lv, FanLevels.title(lv).to_upper()]
	return line

## A beacon in the open world starts its campaign stage; the results bring the car back to it.
func _on_world_stage(index: int) -> void:
	is_campaign_mode = true
	is_championship_mode = false
	is_rally_mode = false
	is_time_trial_mode = false
	campaign_stage_index = index
	world_return = index
	open_world.suspend()
	_update_mode_view()
	_start_race()

func _on_world_leave(to: String) -> void:
	if to == "stages":
		_update_mode_view()
		_show_setup_page()
	else:
		_show_home()

func _populate_campaign_stages() -> void:
	if not is_instance_valid(campaign_stage_picker):
		return
	campaign_stage_picker.clear()
	var prog := CampaignData.load_progress()
	var unlocked: int = int(prog.get("unlocked", 0))
	var best_pos: Dictionary = prog.get("best_pos", {})
	var trophies: Array = prog.get("trophies", [])
	for i in CampaignData.STAGES.size():
		var st: Dictionary = CampaignData.STAGES[i]
		var fan_lock: bool = st.get("fan_lock", false)
		var is_un := CampaignData.is_unlocked(i, _fan_total()) if fan_lock else i <= unlocked
		var completed: bool = (st.trophy in trophies) or (best_pos.has(str(i)) and int(best_pos[str(i)]) <= int(st.target_pos)) or (i < unlocked and not fan_lock)
		var prefix := "★ " if completed else ("▶ " if (i == unlocked or fan_lock) and is_un else "🔒 ")
		campaign_stage_picker.add_item("%s%s" % [prefix, st.title])
		campaign_stage_picker.set_item_disabled(i, not is_un)
	campaign_stage_picker.selected = campaign_stage_index

func _select_campaign_stage(index: int) -> void:
	if CampaignData.is_unlocked(index, _fan_total()):
		_apply_campaign_stage(index)
	else:
		campaign_stage_picker.select(campaign_stage_index) # ◂ ▸ can land on a locked stage: stay put

func _apply_campaign_stage(stage_idx: int) -> void:
	campaign_stage_index = stage_idx
	var st: Dictionary = CampaignData.get_stage(stage_idx)
	if is_instance_valid(campaign_stage_picker) and campaign_stage_picker.selected != stage_idx:
		campaign_stage_picker.select(stage_idx)
	_update_campaign_view()
	_update_information_page()
	_update_menu_car_summary()

func _update_campaign_view() -> void:
	if not is_instance_valid(campaign_act_label):
		return
	var st: Dictionary = CampaignData.get_stage(campaign_stage_index)
	var t_idx := TRACK_KEYS.find(st.track)
	var tr_name: String = TRACK_NAMES[t_idx] if t_idx >= 0 else Race.get_track(st.track).name

	campaign_act_label.text = str(st.get("act_name", "")).to_upper()
	if is_instance_valid(campaign_title_label):
		campaign_title_label.text = str(st.get("title", ""))
	var weather_name: String = str(st.get("weather", "dry")).capitalize()
	if is_instance_valid(campaign_circuit_label):
		campaign_circuit_label.text = "📍 %s  ·  %d Laps  ·  %s  ·  %d Rivals (%s)" % [
			tr_name,
			st.get("laps", 3),
			weather_name,
			st.get("opponents", 5),
			str(st.get("difficulty", "medium")).capitalize()
		]
		if int(st.get("eased", 0)) > 0:
			campaign_circuit_label.text += "  ·  eased from %s after %d tries" % [str(st.base_difficulty).capitalize(), int(st.fails)]
	var target_pos: int = int(st.get("target_pos", 3))
	if target_pos == 1:
		campaign_target_label.text = "★ TARGET OBJECTIVE: Win the race (P1)"
	else:
		campaign_target_label.text = "★ TARGET OBJECTIVE: Finish P%d or higher" % target_pos
	campaign_trophy_label.text = "🏆 Trophy: %s" % str(st.get("trophy", ""))
	campaign_desc_label.text = str(st.get("desc", ""))
	campaign_tip_label.text = "💡 Mechanic: \"%s\"" % str(st.get("tip", ""))

## The opponents number says when it means a solo run.
func _update_opponents_label() -> void:
	if is_instance_valid(opponents_picker):
		opponents_picker.suffix = "(SOLO)" if int(opponents_picker.value) == 0 else ""

## The set-up page's heading: the mode picked on the main menu, and where in it the player is.
## Shows or hides a folded section's heading (its body follows the heading's open state).
func _show_fold(key: String, on: bool) -> void:
	if setup_folds.has(key) and setup_folds[key].get("fixed", false):
		(setup_folds[key].group as Control).visible = on
	elif setup_folds.has(key):
		(setup_folds[key].head as Control).visible = on
		(setup_folds[key].body as Control).visible = on and setup_open.get(key, false)
		# (the rule drawn above the heading goes with it)
		var head: Control = setup_folds[key].head
		var at := head.get_index()
		if at > 0 and head.get_parent().get_child(at - 1) is ColorRect:
			(head.get_parent().get_child(at - 1) as ColorRect).visible = on

func _update_setup_title() -> void:
	if not is_instance_valid(setup_title_label):
		return
	if is_campaign_mode:
		var st := CampaignData.get_stage(campaign_stage_index)
		setup_title_label.text = "CAMPAIGN · STAGE %d/%d" % [campaign_stage_index + 1, CampaignData.STAGES.size()]
		setup_subtitle_label.text = str(st.get("act_name", "THE SEICENTO ODYSSEY")).to_upper()
	elif is_championship_mode:
		setup_title_label.text = "CHAMPIONSHIP · ROUND %d/%d" % [_champ_round() + 1, _calendar().size()]
		setup_subtitle_label.text = "SEICENTO 900 CUP"
	elif is_rally_mode:
		var ev := _rally()
		setup_title_label.text = "RALLY · STAGE %d/%d" % [mini(ev.stage_index + 1, ev.stage_count()), ev.stage_count()]
		setup_subtitle_label.text = str(ev.def.name).to_upper()
	else:
		setup_title_label.text = "TIME TRIAL" if is_time_trial_mode else "QUICK RACE"
		setup_subtitle_label.text = "SOLO HOT LAPS · YOUR GHOST AND LAP RECORDS" if is_time_trial_mode else "SEICENTO 900 CUP"

func _update_mode_view() -> void:
	_update_opponents_label()
	_show_fold("season", is_championship_mode) # the season's own settings and calendar are for a championship only
	_show_fold("calendar", is_championship_mode)
	if is_instance_valid(rally_side):
		rally_side.visible = is_rally_mode
	if is_instance_valid(tt_start_row):
		tt_start_row.visible = is_time_trial_mode
	if is_rally_mode:
		_update_rally_view()
	elif is_campaign_mode:
		if is_instance_valid(champ_reset_button):
			champ_reset_button.visible = false
		campaign_side.show()
		champ_side.hide()
		champ_info_label.text = ""
		track_picker.visible = false
		track_label.get_parent().visible = false
		if is_instance_valid(setup_rule_divider):
			setup_rule_divider.visible = false
		if is_instance_valid(setup_format_row):
			setup_format_row.visible = false
		if is_instance_valid(setup_conditions_row):
			setup_conditions_row.visible = false
		if is_instance_valid(grid_picker):
			grid_picker.get_parent().visible = false
		if is_instance_valid(strategy_section):
			strategy_section.visible = false
		_show_fold("strategy", false)
		_show_fold("race", false) # the stage / the season sets format and length
		_show_fold("rules", false)
		if is_instance_valid(setup_race_button):
			setup_race_button.visible = false
		_populate_campaign_stages()
		_apply_campaign_stage(campaign_stage_index)
	elif is_championship_mode:
		campaign_side.hide()
		champ_side.show()
		track_picker.visible = false
		track_label.get_parent().visible = false
		if is_instance_valid(setup_rule_divider):
			setup_rule_divider.visible = true
		if is_instance_valid(setup_format_row):
			setup_format_row.visible = false
		if is_instance_valid(setup_conditions_row):
			setup_conditions_row.visible = false
		if is_instance_valid(grid_picker):
			grid_picker.get_parent().visible = quali_picker.selected == 2
		if is_instance_valid(strategy_section):
			strategy_section.visible = false
		_show_fold("strategy", false)
		_show_fold("race", false) # the stage / the season sets format and length
		_show_fold("rules", false)
		if is_instance_valid(setup_race_button):
			setup_race_button.visible = true
			setup_race_button.text = "RACE  ▸"
		_update_championship_view()
	else:
		if is_instance_valid(champ_reset_button):
			champ_reset_button.visible = false
		campaign_side.hide()
		champ_side.hide()
		champ_info_label.text = ""
		track_picker.visible = true
		track_label.get_parent().visible = true
		if is_instance_valid(setup_rule_divider):
			setup_rule_divider.visible = true
		if is_instance_valid(setup_format_row):
			setup_format_row.visible = true
			laps_picker.get_parent().visible = format_picker.selected == 0
			hours_picker.get_parent().visible = format_picker.selected == 1
		if is_instance_valid(setup_conditions_row):
			setup_conditions_row.visible = true
		if is_instance_valid(grid_picker):
			grid_picker.get_parent().visible = not is_time_trial_mode
		if is_instance_valid(strategy_section):
			strategy_section.visible = true
		_show_fold("strategy", true)
		_show_fold("race", not is_time_trial_mode)
		# a time trial is a solo run: no field, no grid
		opponents_picker.get_parent().visible = not is_time_trial_mode
		difficulty_picker.get_parent().visible = not is_time_trial_mode
		_show_fold("rules", true)
		if is_instance_valid(setup_race_button):
			setup_race_button.visible = true
			setup_race_button.text = "RACE  ▸"
	_update_setup_title()
	_update_information_page()
	_update_menu_car_summary()
	_update_ai_memory()

func _update_championship_view() -> void:
	_show_fold("season", is_championship_mode)
	_show_fold("calendar", is_championship_mode)
	var table: Dictionary = champ_data.get("table", {})
	var saved := not table.is_empty() or int(champ_data.get("round", 0)) > 0
	grid_picker.get_parent().visible = not is_campaign_mode and not is_time_trial_mode and (not is_championship_mode or quali_picker.selected == 2)
	_sync_season_view()
	if is_instance_valid(champ_reset_button):
		champ_reset_button.visible = is_championship_mode and saved
	if is_championship_mode:
		var points := "-".join(_points_table().map(func(x): return str(x)))
		var season := _season()
		var info := "%d round%s · points %s · %d opponents (%s) · %s · damage %s" % [_calendar().size(), "" if _calendar().size() == 1 else "s",
			points, int(season.opponents), ["Easy", "Medium", "Hard", "Alien"][clampi(int(season.difficulty), 0, 3)],
			str(SEASON_WEATHERS[clampi(int(season.weather), 0, SEASON_WEATHERS.size() - 1)]).to_lower(),
			str(SEASON_DAMAGE[clampi(int(season.damage), 0, SEASON_DAMAGE.size() - 1)].name).to_lower()]
		var nxt := _next_round()
		if saved and nxt < _calendar().size():
			info += "\nNext: round %d, %s." % [nxt + 1, Race.get_track(_calendar()[nxt]).name]
			var q := _round_quali()
			if not q.is_empty():
				info += " You qualified P%d: the race is next." % int(q.pos)
		elif saved:
			info += "\nSeason complete: racing again starts a new one."
		else:
			info += "\nSeason set-up is on the Advanced page; it locks once round 1 is raced."
		champ_info_label.text = info
		champ_info_label.show()
		_render_champ_side(nxt if saved else 0)
		champ_side.show()
	else:
		champ_info_label.text = ""
		champ_info_label.hide()
		champ_side.hide()
	_update_setup_title()

## Calendar with progress (done / next) and the saved standings, like the reference's side panel.
func _render_champ_side(done: int) -> void:
	for child in champ_calendar.get_children() + champ_table.get_children():
		child.queue_free()
	var ink := CmrStyle.TEXT
	for i in _calendar().size():
		var is_next := i == done
		var color := MUTED if i < done else (ACCENT if is_next else ink)
		champ_calendar.add_child(_label(str(i + 1), 13, color))
		var name := _label(Race.get_track(_calendar()[i]).name, 13, color)
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

# ---------------- the championship season's set-up (champ_data.config) ----------------
func _default_season() -> Dictionary:
	return {"preset": 0, "custom": CHAMPIONSHIP_CALENDAR.duplicate(), "calendar": CHAMPIONSHIP_CALENDAR.duplicate(), "order": 0,
		"length": 1, "opponents": 12, "difficulty": 1, "weather": 0, "points": 0, "quali": 0, "damage": 1, "seed": randi() % 1000000}

## The season's settings, filled in with the defaults (a season saved before they existed keeps the old rules:
## the classic calendar, F1 points, realistic damage).
func _season() -> Dictionary:
	var c = champ_data.get("config")
	if not (c is Dictionary):
		c = {}
	var d := _default_season()
	for k in d:
		if not c.has(k):
			c[k] = d[k]
	var cal: Array = (c.calendar as Array).filter(func(k) -> bool: return str(k) in TRACK_KEYS) if c.calendar is Array else []
	c.calendar = cal if not cal.is_empty() else CHAMPIONSHIP_CALENDAR.duplicate()
	champ_data["config"] = c
	return c

## The season's rounds, in order (track keys).
func _calendar() -> Array:
	return _season().calendar

func _points_table() -> Array:
	return SEASON_POINTS[clampi(int(_season().points), 0, SEASON_POINTS.size() - 1)].table

## Once the first round (or its qualifying) has been driven the season's settings are fixed.
func _season_locked() -> bool:
	var q = champ_data.get("quali", {})
	return int(champ_data.get("round", 0)) > 0 or bool(champ_data.get("scored", false)) \
		or not (champ_data.get("table", {}) as Dictionary).is_empty() or (q is Dictionary and not q.is_empty())

## The weather of a round: the season's, or a roll per round (fixed by the season's seed) for "Random".
func _season_weather(round_idx: int) -> String:
	var c := _season()
	var w := int(c.weather)
	if w >= WEATHER_KEYS.size():
		return RANDOM_WEATHER_POOL[posmod(hash([int(c.seed), round_idx]), RANDOM_WEATHER_POOL.size())]
	return WEATHER_KEYS[w]

func _season_laps(key: String) -> int:
	var defaults: Dictionary = TRACK_DEFAULTS.get(key, {"laps": 6, "wear": 2.0})
	return maxi(1, roundi(float(defaults.laps) * SEASON_LENGTHS[clampi(int(_season().length), 0, 2)].mult))

## Minutes of service between events (0: damage doesn't carry over).
func _service_allocation() -> int:
	if is_rally_mode:
		return _rally().service_minutes() if not _rally().is_over() else 0
	if is_championship_mode:
		return int(SEASON_DAMAGE[clampi(int(_season().damage), 0, SEASON_DAMAGE.size() - 1)].minutes)
	return Service.ALLOCATION

func _build_season_box(parent: VBoxContainer, cal: VBoxContainer) -> void:
	season_box = VBoxContainer.new()
	season_box.add_theme_constant_override("separation", 10)
	parent.add_child(season_box)
	season_note = _label("", 13, MUTED)
	season_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	season_box.add_child(season_note)
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 14)
	season_box.add_child(row1)
	season_preset_picker = _option_field(row1, "CALENDAR", SEASON_PRESETS.map(func(p): return p.name))
	season_preset_picker.tooltip_text = "Classic GP: the eight great circuits. Polish Tour: the Silesian and Kraków streets. World Tour, Full (every circuit), or Custom: tick your own below"
	season_order_picker = _option_field(row1, "ORDER", ["As listed", "Shuffled"])
	season_order_picker.tooltip_text = "Race the calendar in its order, or shuffle it"
	season_length_picker = _option_field(row1, "RACE LENGTH", SEASON_LENGTHS.map(func(p): return p.name))
	season_length_picker.tooltip_text = "Laps per round, against each circuit's standard race distance"
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 14)
	season_box.add_child(row2)
	var counts := []
	for i in range(1, 16):
		counts.append(str(i))
	season_opponents_picker = _option_field(row2, "OPPONENTS", counts)
	season_opponents_picker.tooltip_text = "Cars against you in every round"
	season_difficulty_picker = _option_field(row2, "DIFFICULTY", ["Easy", "Medium", "Hard", "Alien"])
	season_weather_picker = _option_field(row2, "WEATHER", SEASON_WEATHERS)
	season_weather_picker.tooltip_text = "One weather for the whole season, or a roll of the dice for every round (mostly dry)"
	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 14)
	season_box.add_child(row3)
	season_points_picker = _option_field(row3, "POINTS", SEASON_POINTS.map(func(p): return p.name))
	season_points_picker.tooltip_text = "Points for 1st, 2nd, 3rd … (no points for a retirement)"
	quali_picker = _option_field(row3, "QUALIFYING", ["Drive it", "Simulate", "Skip (use grid position)"])
	quali_picker.tooltip_text = "Each round opens with qualifying for the grid: drive it yourself, let the co-driver set a time, or start from the grid position you pick"
	season_damage_picker = _option_field(row3, "DAMAGE & REPAIRS", SEASON_DAMAGE.map(func(p): return p.name))
	season_damage_picker.tooltip_text = "Realistic: damage carries over to the next round and the crew has 60 minutes of service to fix what they can. Hardcore: only 30. Off: the car is rebuilt for every round"
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	cal.add_child(grid)
	for i in TRACK_KEYS.size():
		var key: String = TRACK_KEYS[i]
		var tick := _check_field(grid, TRACK_NAMES[i], false)
		tick.tooltip_text = "Race at %s this season (picks the Custom calendar)" % TRACK_NAMES[i]
		tick.toggled.connect(_season_track_toggled.bind(key))
		season_track_toggles[key] = tick
	for picker in [season_preset_picker, season_order_picker, season_length_picker, season_opponents_picker,
			season_difficulty_picker, season_weather_picker, season_points_picker, quali_picker, season_damage_picker]:
		(picker as MenuSelector).item_selected.connect(func(_i: int) -> void: _season_changed())

## A season setting was changed on the page (before round 1).
func _season_changed() -> void:
	if _season_syncing or _loading_settings:
		return
	var c := _season()
	if _season_locked():
		_sync_season_view()
		return
	var preset := season_preset_picker.selected
	var order := season_order_picker.selected
	if order == 1 and (int(c.order) != 1 or preset != int(c.preset)):
		c.seed = randi() % 1000000 # a fresh shuffle
	if preset != int(c.preset) and preset < SEASON_PRESETS.size() - 1:
		c.custom = (SEASON_PRESETS[preset].tracks as Array).duplicate()
	c.preset = preset
	c.order = order
	c.length = season_length_picker.selected
	c.opponents = season_opponents_picker.selected + 1
	c.difficulty = season_difficulty_picker.selected
	c.weather = season_weather_picker.selected
	c.points = season_points_picker.selected
	c.quali = quali_picker.selected
	c.damage = season_damage_picker.selected
	_rebuild_calendar(c)
	_save_championship()
	_update_championship_view()

func _season_track_toggled(on: bool, key: String) -> void:
	if _season_syncing or _season_locked():
		return
	var c := _season()
	var ticked: Array = []
	for k in TRACK_KEYS:
		if (season_track_toggles[k] as CheckButton).button_pressed:
			ticked.append(k)
	if ticked.is_empty():
		_season_syncing = true
		(season_track_toggles[key] as CheckButton).button_pressed = true # a season needs a round
		_season_syncing = false
		return
	# keep the order the rounds were in, new ones at the end
	var custom: Array = (c.calendar as Array).filter(func(k) -> bool: return k in ticked)
	for k in ticked:
		if not k in custom:
			custom.append(k)
	c.custom = custom
	c.preset = SEASON_PRESETS.size() - 1
	_rebuild_calendar(c)
	_save_championship()
	_update_championship_view()

## The calendar from the preset (or the ticked circuits) and the order.
func _rebuild_calendar(c: Dictionary) -> void:
	var preset := clampi(int(c.preset), 0, SEASON_PRESETS.size() - 1)
	var base: Array = (SEASON_PRESETS[preset].tracks as Array).duplicate() if preset < SEASON_PRESETS.size() - 1 else (c.custom as Array).duplicate()
	if int(c.order) == 1:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(c.seed)
		for i in range(base.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t = base[i]
			base[i] = base[j]
			base[j] = t
	c.calendar = base

## Shows the season's settings on the page, locked once it is under way.
func _sync_season_view() -> void:
	if not is_instance_valid(season_box):
		return
	var c := _season()
	var locked := _season_locked()
	_season_syncing = true
	season_preset_picker.select(clampi(int(c.preset), 0, SEASON_PRESETS.size() - 1))
	season_order_picker.select(clampi(int(c.order), 0, 1))
	season_length_picker.select(clampi(int(c.length), 0, SEASON_LENGTHS.size() - 1))
	season_opponents_picker.select(clampi(int(c.opponents) - 1, 0, 14))
	season_difficulty_picker.select(clampi(int(c.difficulty), 0, 3))
	season_weather_picker.select(clampi(int(c.weather), 0, SEASON_WEATHERS.size() - 1))
	season_points_picker.select(clampi(int(c.points), 0, SEASON_POINTS.size() - 1))
	quali_picker.select(clampi(int(c.quali), 0, 2))
	season_damage_picker.select(clampi(int(c.damage), 0, SEASON_DAMAGE.size() - 1))
	for k in season_track_toggles:
		var tick: CheckButton = season_track_toggles[k]
		tick.button_pressed = k in c.calendar
		tick.disabled = locked
	for picker in [season_preset_picker, season_order_picker, season_length_picker, season_opponents_picker,
			season_difficulty_picker, season_weather_picker, season_points_picker, quali_picker, season_damage_picker]:
		(picker as MenuSelector).disabled = locked
	_season_syncing = false
	_set_section_summary("calendar", "%d ROUND%s" % [c.calendar.size(), "" if c.calendar.size() == 1 else "S"])
	season_note.text = "This season's settings are locked now that it is under way. RESET SEASON to change them." if locked \
		else "Set up the season, then press %s to race round 1. The settings lock once it has been raced." % ("START" if _pad_connected() else "RACE")

## After a confirmation closes, the keyboard / gamepad goes back to where it was on the page.
func _refocus_after(dialog: Window) -> void:
	dialog.visibility_changed.connect(func() -> void:
		if not dialog.visible:
			_focus_page.call_deferred()
	)

## Puts the focus back on the page shown (it is never left with nothing focused).
func _focus_page() -> void:
	if race or _starting:
		return
	match active_menu_page:
		"setup", "advanced", "car", "strategy":
			var items := _setup_focus_items()
			if not items.is_empty():
				_focus_setup_item(items, _setup_focus_at)
		"options":
			var items := _options_focus_items()
			if not items.is_empty():
				items[0].grab_focus()
		_:
			get_viewport().gui_release_focus()

func _options_focus_items() -> Array[Control]:
	var out: Array[Control] = []
	if is_instance_valid(options_column):
		_collect_focusable(options_column, out)
	return out

# ---------------- the car between events: damage carried over, and the service area ----------------
## The car carried to the next event ({parts, pull, used, serviced}): the championship's (unless its damage
## is off), the campaign's, or {} for a quick race (the car is rebuilt for every race).
func _carried_car() -> Dictionary:
	var car = {}
	if is_championship_mode:
		car = champ_data.get("car", {}) if _service_allocation() > 0 else {}
	elif is_rally_mode:
		car = rally_car
	return car if car is Dictionary else {}

func _store_carried_car(car: Dictionary) -> void:
	if is_championship_mode:
		champ_data["car"] = car
		_save_championship()
	elif is_rally_mode:
		rally_car = car
		_save_rally()

## The car comes to the service area damaged and the crew hasn't been to it yet: the next event waits for it.
func _service_due() -> bool:
	if is_championship_mode and _next_round() >= _calendar().size():
		return false # the season is over: the next one starts with a new car
	var car := _carried_car()
	var parts = car.get("parts", {})
	return parts is Dictionary and Service.total(parts) >= 0.01 and not bool(car.get("serviced", false))

## Every unrepaired part and what it will do in the next race, in plain words.
func _unrepaired_text(parts: Dictionary) -> String:
	var lines: Array[String] = []
	for part in Service.PARTS:
		var sev := clampf(float(parts.get(part, 0.0)), 0.0, 1.0)
		if sev >= 0.01:
			lines.append("%s %d%%: %s" % [part.to_upper(), roundi(sev * 100.0), Service.symptom(part, sev)])
	return "\n".join(lines)

func _reset_championship() -> void:
	champ_data = {"round": 0, "scored": false, "table": {}, "config": _season()} # the settings stay, unlocked
	_save_championship()
	_update_championship_view()
	_update_information_page()
	_update_menu_car_summary()

func _load_championship() -> void:
	champ_data = {"round": 0, "scored": false, "table": {}}
	if not FileAccess.file_exists(SaveData.path("championship.json")):
		return
	var f := FileAccess.open(SaveData.path("championship.json"), FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary) or not (parsed.get("table", {}) is Dictionary):
		return
	var saved_round := int(parsed.get("round", -1))
	champ_data = parsed # (its config, if any, says how long the season is)
	if saved_round < 0 or saved_round >= _calendar().size():
		champ_data = {"round": 0, "scored": false, "table": {}, "config": champ_data.get("config", {})}
		return
	champ_data["round"] = saved_round
	champ_data["scored"] = bool(parsed.get("scored", false))

func _save_championship() -> void:
	var f := FileAccess.open(SaveData.path("championship.json"), FileAccess.WRITE)
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
			JOY_BUTTON_Y:
				if race and race.tt:
					_restart_time_trial() # nobody pits in a time trial: Y restarts the run
				else:
					_pit()
			JOY_BUTTON_X: _cycle_mix()
			JOY_BUTTON_BACK, JOY_BUTTON_MISC1:
				if race: race.reset_player_car()
			JOY_BUTTON_START: _set_paused(not paused)
			JOY_BUTTON_B:
				if paused: _set_paused(false) # B backs out of the pause menu
			JOY_BUTTON_A: # the pad's Enter: once you're home or out, skip to the results
				if race and not paused and not skipping and race.phase != "finished" and (race.player.finished or race.player.dnf):
					_begin_skip()
		return

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var down: bool = event.pressed and not event.echo
	if down and (event.keycode == KEY_F1 or event.physical_keycode == KEY_F1):
		_cycle_retro_mode()
		get_viewport().set_input_as_handled()
		return
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
			if active_menu_page in ["setup", "advanced", "car", "strategy"] and event.keycode not in [KEY_ESCAPE, KEY_BACKSPACE]:
				return # the set-up list has the arrows (_input), and Enter belongs to the focused setting
			match event.keycode:
				KEY_ESCAPE, KEY_BACKSPACE:
					_show_home()
					get_viewport().set_input_as_handled()
					return
				KEY_LEFT, KEY_A:
					menu_tab_index = posmod(menu_tab_index - 1, _menu_tab_titles().size())
					_select_menu_tab(_menu_tab_titles()[menu_tab_index])
					get_viewport().set_input_as_handled()
					return
				KEY_RIGHT, KEY_D:
					menu_tab_index = posmod(menu_tab_index + 1, _menu_tab_titles().size())
					_select_menu_tab(_menu_tab_titles()[menu_tab_index])
					get_viewport().set_input_as_handled()
					return
				KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
					var tab: Button = menu_tab_buttons[_menu_tab_titles()[menu_tab_index]]
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
		KEY_BACKSPACE:
			if race: race.reset_player_car()
		KEY_E: shift_up = true
		KEY_Q: shift_down = true
		KEY_P: _pit()
		KEY_T:
			if race.tt:
				_restart_time_trial()
		KEY_BRACKETLEFT: _cycle_pit_tyre(-1)
		KEY_BRACKETRIGHT: _cycle_pit_tyre(1)
		KEY_MINUS, KEY_KP_SUBTRACT: _adjust_pit_fuel(-1.0)
		KEY_EQUAL, KEY_KP_ADD: _adjust_pit_fuel(1.0)
		KEY_F: _cycle_mix()
		KEY_R:
			if event.shift_pressed:
				_replan()
			elif race:
				race.reset_player_car()
		KEY_O: _toggle_autopilot()
		KEY_C: _cycle_camera()
		KEY_L: _toggle_racing_line()
		KEY_G: _toggle_ghost()
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

func _cycle_mix() -> void:
	if race:
		race.player_cycle_mix()
		if is_instance_valid(audio):
			audio.beep(560.0, 1)

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

func _toggle_ghost() -> void:
	var note := lap_ghost.toggle()
	if race and note != "":
		race.log_event(note, "info")

func _toggle_mute() -> void:
	if is_instance_valid(audio):
		audio.toggle_mute()

func _toggle_pause() -> void:
	_set_paused(not paused)

func _quit_race() -> void:
	if is_rally_mode and race and race.stage and _rally_recorded != race:
		_record_rally_stage() # walking away from a stage is retiring from it: classified at the superrally time
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
	t.add_theme_font_override("font", CmrStyle.title_font())
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
	var spin := _make_spin(low, high, value, step)
	col.add_child(spin)
	return spin

func _make_spin(low: float, high: float, value: float, step := 1.0) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	spin.value = value
	spin.custom_minimum_size.y = 40
	_style_control(spin)
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
		(control as SpinBox).select_all_on_focus = true # a number typed over the focused box replaces it

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


func _option_field(parent: Control, title: String, options: Array) -> MenuSelector:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(col)
	_field_label(col, title)
	var opt := _make_option(options)
	col.add_child(opt)
	return opt

func _make_option(options: Array) -> MenuSelector:
	var opt := MenuSelector.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for o in options:
		opt.add_item(str(o))
	opt.custom_minimum_size.y = 40
	_style_control(opt)
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

# ---------------- rally (RallyEvent) and time trial ----------------
const RALLY_FILE := "rally.json"

## The rally being run, loaded (or started on the first event) on first use.
func _rally() -> RallyEvent:
	if rally_event == null:
		_load_rally()
	return rally_event

func _new_rally(key: String) -> void:
	rally_event = RallyEvent.new(key)
	rally_car = {}
	_rally_recorded = null
	_save_rally()

func _load_rally() -> void:
	if rally_event != null:
		return
	var path := SaveData.path(RALLY_FILE)
	if FileAccess.file_exists(path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary and not Rally.event(str(d.get("key", ""))).is_empty():
			rally_event = RallyEvent.from_dict(d)
			var car = d.get("car", {})
			rally_car = car if car is Dictionary else {}
			return
	_new_rally(Rally.EVENTS[0].key)

func _save_rally() -> void:
	if rally_event == null:
		return
	var d := rally_event.to_dict()
	d["car"] = rally_car
	var f := FileAccess.open(SaveData.path(RALLY_FILE), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))

## The rally block of the set-up page: the event picker, its stages and the standings so far.
func _build_rally_side(col: VBoxContainer) -> void:
	rally_side = VBoxContainer.new()
	rally_side.add_theme_constant_override("separation", 10)
	col.add_child(rally_side)
	_field_label(rally_side, "RALLY")
	var caption: Control = rally_side.get_child(-1)
	rally_event_picker = MenuSelector.new()
	for e in Rally.EVENTS:
		rally_event_picker.add_item("%s  ·  %d stages" % [e.name, e.stages.size()])
	rally_event_picker.custom_minimum_size.y = 42
	_style_control(rally_event_picker)
	rally_event_picker.set_meta("caption", caption)
	rally_event_picker.item_selected.connect(_select_rally_event)
	rally_side.add_child(rally_event_picker)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", CmrStyle.box(Color(CmrStyle.PANEL, 0.75), Color(CmrStyle.ORANGE, 0.6), 14, 12))
	rally_side.add_child(card)
	rally_info_label = _label("", 15, CmrStyle.TEXT)
	rally_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(rally_info_label)
	rally_restart_button = _button("RESTART THIS RALLY", CmrStyle.FIELD)
	rally_restart_button.custom_minimum_size.y = 40
	rally_restart_button.pressed.connect(func() -> void:
		_new_rally(_rally().key)
		_update_mode_view())
	rally_side.add_child(rally_restart_button)
	rally_side.hide()

## Picking another event starts it afresh (the one in progress is dropped).
func _select_rally_event(index: int) -> void:
	var key: String = Rally.EVENTS[clampi(index, 0, Rally.EVENTS.size() - 1)].key
	if _rally().key != key:
		_new_rally(key)
	_update_mode_view()

## The set-up page in rally mode: the event's own stages decide circuit, conditions and length.
func _update_rally_view() -> void:
	var ev := _rally()
	campaign_side.hide()
	champ_side.hide()
	champ_info_label.text = ""
	if is_instance_valid(champ_reset_button):
		champ_reset_button.visible = false
	track_picker.visible = false
	track_label.get_parent().visible = false
	if is_instance_valid(setup_rule_divider):
		setup_rule_divider.visible = true
	if is_instance_valid(setup_format_row):
		setup_format_row.visible = false
	if is_instance_valid(setup_conditions_row):
		setup_conditions_row.visible = false
	if is_instance_valid(grid_picker):
		grid_picker.get_parent().visible = false
	if is_instance_valid(strategy_section):
		strategy_section.visible = false
	_show_fold("strategy", false)
	_show_fold("race", false)
	_show_fold("rules", false)
	rally_event_picker.select(Rally.event_keys().find(ev.key))
	var lines: Array[String] = [str(ev.def.get("blurb", "")), ""]
	for i in ev.stage_count():
		var sd := ev.stage_def(i)
		var tr := Race.get_track(sd.track)
		var mark := "▸ " if i == ev.stage_index else ("✓ " if i < ev.stage_index else "   ")
		var svc := "  (service %d min before)" % int(sd.service) if int(sd.get("service", 0)) > 0 else ""
		lines.append("%sSS%d  %s — %s · %.1f km · %s · %s · %s%s" % [mark, i + 1, sd.name, tr.cfg.short_name if tr.cfg.short_name != "" else tr.name,
			Rally.stage_length(sd, tr.L) / 1000.0, sd.surface, sd.weather, _format_start_time(float(sd.hour)), svc])
	if ev.results.size():
		var table := ev.standings()
		var me: Dictionary = table.filter(func(r): return r.is_player)[0]
		lines.append("")
		lines.append("%s: P%d of %d, %s" % ["Final result" if ev.is_over() else "Overall after SS%d" % ev.results.size(),
			me.pos, table.size(), Race.fmt_time(me.time) if me.pos == 1 else "+%.1f s" % me.gap])
	lines.append("")
	lines.append("Difficulty: %s · Co-driver pace notes on · Damage carries over between stages" % str(ev.difficulty).capitalize())
	rally_info_label.text = "\n".join(lines)
	rally_restart_button.visible = ev.stage_index > 0
	if is_instance_valid(setup_race_button):
		setup_race_button.visible = true
		setup_race_button.text = "RUN IT AGAIN  ▸" if ev.is_over() else "START SS%d  ▸" % (ev.stage_index + 1)

## Writes the stage just driven (or abandoned) into the rally; returns the stage's classification.
func _record_rally_stage() -> Array:
	var ev := _rally()
	if _rally_recorded == race:
		return ev.stage_results(ev.stage_index - 1)
	_rally_recorded = race
	var rows := ev.finish_stage(race)
	rally_car = {"parts": ev.parts.duplicate(), "pull": ev.pull, "used": 0,
		"serviced": ev.is_over() or ev.service_minutes() <= 0}
	_save_rally()
	return rows

## After a stage: its times, the overall classification, and the way on (service, the next stage, or done).
func _show_rally_results() -> void:
	var ev := _rally()
	var rows := _record_rally_stage()
	hud.hide()
	pause_panel.hide()
	pause_dim.hide()
	if is_instance_valid(audio):
		audio.update_car(race.player, false)
	result_panel.show()
	for child in result_scroll.get_children():
		child.queue_free()
	var col := _column(result_scroll, 8)
	col.custom_minimum_size.x = 1060
	var i := ev.stage_index - 1
	var sd := ev.stage_def(i)
	var me: Dictionary = rows.filter(func(r): return r.is_player)[0]
	var title := "SS%d %s · %s" % [i + 1, str(sd.name).to_upper(), "RETIRED" if me.dnf else "P%d OF %d" % [me.pos, rows.size()]]
	col.add_child(_label(title, 26, INK))
	var sub := "%s · %s · %s · %s" % [ev.def.name, race.track.name, sd.surface, str(sd.weather).capitalize()]
	if me.note != "":
		sub += " · " + str(me.note)
	var sub_label := _label(sub, 14, MUTED)
	sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(sub_label)
	var widths := [46, 44, 250, 130, 110, 330]
	var head_style := CmrStyle.box(Color(0, 0, 0, 0.25), Color.TRANSPARENT, 14, 3)
	var stage_table := VBoxContainer.new()
	stage_table.add_theme_constant_override("separation", 3)
	col.add_child(stage_table)
	stage_table.add_child(_result_row(["POS", "NO.", "DRIVER", "STAGE TIME", "GAP", ""], widths, head_style, CmrStyle.ORANGE_SOFT, 13))
	for r in rows:
		var fill: Color = CmrStyle.ORANGE if r.is_player else (CmrStyle.FIELD if r.pos % 2 == 1 else CmrStyle.FIELD_DIM)
		stage_table.add_child(_result_row([str(r.pos), str(r.number), r.name, ("DNF " if r.dnf else "") + Race.fmt_time(r.time),
			"+%.2f" % r.gap if r.pos > 1 else "", r.note], widths, CmrStyle.box(fill, Color.TRANSPARENT, 14, 3), CmrStyle.INK, 16, r.color))
	var table := ev.standings()
	col.add_child(_label("%s AFTER SS%d" % ["FINAL CLASSIFICATION" if ev.is_over() else "OVERALL", ev.results.size()], 20, INK))
	var overall := VBoxContainer.new()
	overall.add_theme_constant_override("separation", 3)
	col.add_child(overall)
	overall.add_child(_result_row(["POS", "NO.", "DRIVER", "TOTAL", "GAP", "STAGE WINS"], widths, head_style, CmrStyle.ORANGE_SOFT, 13))
	for r in table:
		var fill: Color = CmrStyle.ORANGE if r.is_player else (CmrStyle.FIELD if r.pos % 2 == 1 else CmrStyle.FIELD_DIM)
		overall.add_child(_result_row([str(r.pos), str(r.number), r.name, Race.fmt_time(r.time), "+%.1f" % r.gap if r.pos > 1 else "",
			str(r.stage_wins) if r.stage_wins > 0 else ""], widths, CmrStyle.box(fill, Color.TRANSPARENT, 14, 3), CmrStyle.INK, 16, r.color))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	var primary: Button
	if ev.is_over():
		primary = _button("RALLY COMPLETE · BACK TO THE RALLY PAGE", ACCENT)
		primary.pressed.connect(_return_to_setup)
	elif _service_due():
		primary = _button("SERVICE AREA · %d MIN  ▸" % ev.service_minutes(), ACCENT)
		primary.pressed.connect(_go_to_service)
	else:
		primary = _button("NEXT: SS%d %s  ▸" % [ev.stage_index + 1, str(ev.stage_def().name).to_upper()], ACCENT)
		primary.pressed.connect(_start_race)
	primary.custom_minimum_size.y = 44
	buttons.add_child(primary)
	var back := _button("BACK TO MENU", CmrStyle.FIELD)
	back.custom_minimum_size.y = 44
	back.pressed.connect(_return_to_setup)
	buttons.add_child(back)
	col.add_child(buttons)
	primary.grab_focus()
	_fit_result_panel(col)

## TIME TRIAL: T or the pad's Y puts the car back at the start at once (the session's laps stay).
func _restart_time_trial() -> void:
	if not race or not race.tt or paused:
		return
	race.tt.restart()
	accumulator = 0.0
	throttle = 0.0
	brake = 0.0
	steer = 0.0
	hud._mode_split = {}
	hud._mode_seen = race.tt.laps.size()
	if is_instance_valid(audio):
		audio.beep(880.0, 1)
