## In-race HUD (port of the HUD half of js/ui.js) in the style of Colin McRae Rally 2.0: standings as
## light gradient bars top left, a lime pace-note box for the next corner top centre, the segmented lap
## progress and stage-style clock top right, a segmented rev arc with a big gear digit bottom right, plus
## the pit wall, event feed, minimap, start lights, banner, key help and name tags. Each panel is one
## custom-drawn Control; text panels redraw at about 8 Hz like the reference, the dash, pace note,
## minimap and tags every frame. Laid out on the 1600×900 design canvas and scaled with the window.
class_name RaceHud
extends Control

var INK: Color:
	get: return CmrStyle.INK
var TEXT: Color:
	get: return CmrStyle.TEXT
var MUTED: Color:
	get: return CmrStyle.MUTED
var RED: Color:
	get: return CmrStyle.RED
var YELLOW: Color:
	get: return CmrStyle.ORANGE
var GOOD: Color:
	get: return CmrStyle.VIOLET
var PURPLE: Color:
	get: return CmrStyle.PLUM
var BLUE: Color:
	get: return CmrStyle.VIOLET
# Colours: shorthands for the CmrStyle palette (they follow the skin picked in Options / F1)
const METER_BG := Color(0, 0, 0, 0.35)
var CHIP_BG: Color:
	get: return _plate(0.85)
var BAR_HI: Color: ## opaque end of the CMR gradient bars
	get: return Color(CmrStyle.TEXT, 0.9)
var BAR_LO: Color: ## faded end, violet where CMR has blue (the skin's accent elsewhere)
	get: return Color(CmrStyle.BAR_FADE, 0.35)

## The skin's dark HUD plate at alpha a (dark purple in CMR), and a deeper shade of it for outlines.
static func _plate(a: float) -> Color:
	return Color(CmrStyle.PLATE, a)

static func _shade(a: float) -> Color:
	return Color(CmrStyle.PLATE.darkened(0.4), a)
# Layout, in pixels on the 1600×900 design canvas
const REFRESH := 0.12 ## s between redraws of the text panels (about 8 Hz, like the reference)
const ROW_H := 21.0 ## height of one timing-tower row
const TOWER_W := 240.0 ## timing tower (standings) width
const PITWALL_W := 290.0 ## pit-wall panel width
const FEED_W := 330.0 ## event feed width
const CLOCK_W := 300.0 ## lap / clock panel width
const MAP_S := 190.0 ## minimap size (square)
const REPAIR_AT_HUD := 0.3 ## the damage at which the gauge turns red (RaceControl.REPAIR_AT)
var FEED_BORDER: Dictionary:
	get: return {"good": GOOD, "bad": RED, "warn": CmrStyle.ORANGE_SOFT, "box": YELLOW, "pit": Color("#8a8f99"),
	"purple": PURPLE, "ai": Color("#2ec4b6"), "rc": Color("#ffcc00")}
const QUICK_HELP := "W Throttle  ·  S Brake  ·  A / D Steer  ·  R Reset  ·  H Controls"
const QUICK_HELP_SECS := 7.0 ## s of racing the key strip stays up
const GUIDE := [["W / ↑", "Throttle"], ["S / ↓", "Brake, reverse"], ["Space · pad A", "Handbrake"], ["A / D / ← →", "Steer"], ["E / Q", "Gear (manual)"],
	["R / Backspace", "Reset car"], ["C · L", "Camera · line"], ["V", "Speed limiter"], ["O", "Autopilot"],
	["G", "Ghost car"], ["M", "Mute"], ["P", "Request box"], ["[ ]  − =  F", "Tyre · fuel · mix"], ["Esc", "Pause"]]
var _guide: Control
var _feed_cache: Array = []
var _feed_cache_n := -1
const HELP_TEXT := "DRIVING:  W / ↑ Throttle  ·  S / ↓ Brake  ·  Space Handbrake  ·  A / D / ← → Steer  ·  Backspace / R Reset Car  ·  E / Q Gear (Manual)\nVIEW & AIDS:  C Camera  ·  L Racing Line  ·  V Speed Limiter  ·  O Autopilot  ·  G Ghost Car  ·  M Mute  ·  Esc Pause\nPIT & STRATEGY:  P Request Box  ·  [ ] Next Tyre  ·  − / = Fuel  ·  F Fuel Mix  ·  Shift+R Replan  ·  H Toggle Help"

var race: Race
var records: LapRecords ## the player's lap record here, for the gap to it (null: no record row)
var world: Node3D
var audio: RaceAudio
var warp := 1
## Text shown under the banner while the rest of the race is simulated (set by the game).
var skip_note := ""

var tower: Control
var clock: Control
var pacenote: Control
var lights: Control
var banner: Label
var banner_small: Label
var feed: Control
var pitwall: Control
var dash: Control
var minimap: Control
var minimap_base: Control ## the map's backdrop, line and flags under minimap's dots, redrawn only when they change
var tags: Control
var help: PanelContainer
var flagbar: Control
var splitbox: Control ## the split time that comes up beside the clock at each third of the lap
var co_driver: CoDriver ## calls the pace notes (the pace-note boxes show what it called)
var modepanel: Control ## rally / time trial: the stage splits and standings, or the sectors and lap list (in the tower's place)
var deltabar: Control ## rally / time trial: the split against the stage leader, or the live delta to the best lap
var _mode_split := {} ## rally: the split last passed, shown in the delta bar for MODE_SPLIT_SHOW s
var _mode_seen := 0 ## rally: splits already shown; time trial: laps already shown
var _prev_player_pos := -1
var _overtake_timer := 0.0
var _overtake_pos := 0
var _overtake_up := true
var _overtake_control: Control
var _help_full := false
var statusbar: Control ## bottom centre, above the key help: AUTOPILOT, or the co-driver's time warp
var _status_text := ""
var _flag := {} ## race control's board for the player this frame (empty: none)
var _split_beside := true ## the split sits left of the clock (false: no room there, it joins the centre stack)
var _feed_h := 0.0 ## height the event feed's entries take
var _reserved: Array[Rect2] = [] ## HUD areas name tags keep out of (see _layout)
var _help_key := ""
var _stack_bottom := 0.0 ## where the centre column ended last layout
var _last_lit := -1
var _wrong_way_beep_t := 0.0
var _finished_beep := false
var _help_label: Label
var voice_on := true ## the co-driver reads the notes aloud (Options → Co-driver voice)
var _split_lap := -1 ## the lap the split marks below belong to
var _split_prev_s := 0.0
var _split_marks: Array = [] ## times into this lap at the splits passed so far
var _split_ref: Array = [] ## the splits of the player's best lap this session
var _split_show := {} ## {k, t, delta (null: no reference), until}

var _font: Font
var _bold: Font
var _digits: Font
var _panel_style: StyleBoxFlat
var _lights_style: StyleBoxFlat
var _refresh_t := 0.0
var _clock := 0.0
var _event_seen := 0
var _last_flag := ""
var _fitted := {} ## name -> name shortened to fit the tower column
var _sheet: Array = [] ## qualifying: the live time sheet the tower shows
var _map_track: Track
var _map_size := Vector2.ZERO
var _map_points := PackedVector2Array()
var _map_start := PackedVector2Array()
var _map_scale := 1.0
var _map_origin := Vector2.ZERO
var _map_key := "" ## what minimap_base last drew (track, size, flags)
var _map_waters: Array[PackedVector2Array] = []
var _map_buildings: Array[PackedVector2Array] = []
var _dash_key := [] ## what the dash last drew (size, lit segments, gear, speed)
var _note_key := [] ## what the pace note last drew (race, the notes up, the sector between notes)
var _dash_points := PackedVector2Array() ## the rev band's segments and their outlines, built once per size
var _dash_colors := PackedColorArray()
var _dash_indices := PackedInt32Array()
var _dash_size := Vector2.ZERO
## Batching: every polygon, circle, arc and polyline drawn on its own is a separate draw call, and text
## between them breaks the glyph batches too (the HUD came to over 500 draw calls a frame). The busy
## panels gather their flat shapes into one triangle list (_tri_*), draw circles from small textures
## (_round_tex) and queue their text (_q) to draw grouped by font and size once the shapes are down.
var _tri_points := PackedVector2Array()
var _tri_colors := PackedColorArray()
var _tri_indices := PackedInt32Array()
var _queued: Array = [] ## [outline size (0 plain), font, at, text, align, width, size, colour]
var _badges: Array = [] ## [centre, radius, hole / radius, colour] for _flush_badges
var _round_textures := {}

var _nitro_label: Label ## the Nitrous modifier's bottle (CarMods), only while it is switched on

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_nitro_label = Label.new()
	_nitro_label.add_theme_font_override("font", CmrStyle.font(800))
	_nitro_label.add_theme_font_size_override("font_size", 16)
	_nitro_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_nitro_label.add_theme_constant_override("outline_size", 4)
	_nitro_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_nitro_label.offset_top = -64
	_nitro_label.offset_bottom = -40
	_nitro_label.offset_left = -120
	_nitro_label.offset_right = 120
	_nitro_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_nitro_label.hide()
	add_child(_nitro_label)
	visibility_changed.connect(func(): if not visible: CoDriver.silence())
	_font = CmrStyle.font(400)
	_bold = CmrStyle.font(600)
	_digits = CmrStyle.digits()
	_panel_style = CmrStyle.panel(_plate(0.8), Color(CmrStyle.VIOLET, 0.5), 0)
	_lights_style = StyleBoxFlat.new()
	_lights_style.bg_color = Color("#0b0b0d")
	_lights_style.border_color = Color("#222222")
	_lights_style.set_border_width_all(2)

	tags = _canvas(_draw_tags)
	tags.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tower = _canvas(_draw_tower)
	tower.position = Vector2(14, 14)
	tower.size = Vector2(TOWER_W, 40)
	pacenote = _canvas(_draw_pacenote)
	modepanel = _canvas(_draw_mode_panel)
	modepanel.position = Vector2(14, 14)
	modepanel.size = Vector2(MODE_W, 520)
	deltabar = _canvas(_draw_delta_bar)
	_place(deltabar, 0.5, 0.0, 0.5, 0.0, -DELTA_W * 0.5, 156, DELTA_W * 0.5, 156 + 92)
	splitbox = _canvas(_draw_splits)
	_place(splitbox, 1.0, 0.0, 1.0, 0.0, -14 - CLOCK_W - 20 - 250, 32, -14 - CLOCK_W - 20 - 12, 90)
	_place(pacenote, 0.5, 0.0, 0.5, 0.0, -150, 14, 150, 146)
	clock = _canvas(_draw_clock)
	_place(clock, 1.0, 0.0, 1.0, 0.0, -14 - CLOCK_W - 20, 14, -14, 222)
	lights = _canvas(_draw_lights)
	lights.self_modulate.a = 0.0 # no HUD start lights
	lights.visible = false
	flagbar = _canvas(_draw_flag)
	_place(flagbar, 0.5, 0.0, 0.5, 0.0, -210, 150, 210, 204)
	_place(lights, 0.0, 0.0, 1.0, 0.0, 0, 140, 0, 212)
	minimap_base = _canvas(_draw_minimap_base)
	_place(minimap_base, 1.0, 0.0, 1.0, 0.0, -14 - MAP_S, 224, -14, 224 + MAP_S)
	minimap_base.clip_contents = true # rivers and lakes run off the map; keep them inside its box
	minimap = _canvas(_draw_minimap)
	_place(minimap, 1.0, 0.0, 1.0, 0.0, -14 - MAP_S, 224, -14, 224 + MAP_S)
	feed = _canvas(_draw_feed)
	_place(feed, 1.0, 0.0, 1.0, 0.0, -14 - FEED_W, 428, -14, 700)
	pitwall = _canvas(_draw_pitwall)
	_place(pitwall, 0.0, 1.0, 0.0, 1.0, 14, -214, 14 + PITWALL_W, -14)
	dash = _canvas(_draw_dash)
	_place(dash, 1.0, 1.0, 1.0, 1.0, -360, -190, -14, -14)

	_overtake_control = _canvas(_draw_overtake)
	_place(_overtake_control, 0.5, 0.0, 0.5, 0.0, -170, 192, 170, 234)
	statusbar = _canvas(_draw_status)
	_place(statusbar, 0.5, 1.0, 0.5, 1.0, -100, -80, 100, -56)

	# the lights, flag board, split, overtake call, delta bar and banner share one column under the pace
	# notes: _layout() stacks whichever are showing so no two ever cover each other
	banner = _banner_label(46)
	add_child(banner)
	banner_small = _banner_label(18)
	banner_small.add_theme_color_override("font_color", CmrStyle.MUTED)
	add_child(banner_small)

	help = PanelContainer.new()
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var help_style := CmrStyle.box(_plate(0.62), Color.TRANSPARENT, 18, 6)
	help.add_theme_stylebox_override("panel", help_style)
	var help_label := Label.new()
	_help_label = help_label
	help_label.text = QUICK_HELP
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_label.add_theme_font_override("font", _font)
	help_label.add_theme_font_size_override("font_size", 12)
	help_label.add_theme_color_override("font_color", CmrStyle.MUTED)
	help.add_child(help_label)
	_guide = _canvas(_draw_guide)
	remove_child(_guide)
	help.add_child(_guide)
	_guide.visible = false
	help.anchor_left = 0.5
	help.anchor_right = 0.5
	help.anchor_top = 1.0
	help.anchor_bottom = 1.0
	help.grow_horizontal = Control.GROW_DIRECTION_BOTH
	help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	help.offset_bottom = -14
	add_child(help)
	_fit_help()

## Hand the HUD a new race.
func start(race_: Race, world_: Node3D, audio_: RaceAudio) -> void:
	race = race_
	world = world_
	audio = audio_
	warp = 1
	skip_note = ""
	_event_seen = 0
	_feed_cache = []
	_feed_cache_n = -1
	_last_flag = ""
	_refresh_t = 0.0
	_map_track = null
	_map_key = ""
	_dash_key = []
	_fitted.clear()
	_sheet = Qualifying.sheet(race) if race.s.qualifying else []
	co_driver = CoDriver.new(race)
	CoDriver.silence()
	_split_lap = -1
	_split_ref = []
	_split_marks = []
	_split_show = {}
	pitwall.visible = _pit_relevant() # only where a stop is planned or required, or boxing
	var solo_mode := race.s.mode != "race"
	tower.visible = not solo_mode
	modepanel.visible = solo_mode
	deltabar.visible = solo_mode
	_mode_split = {}
	_mode_seen = 0
	_prev_player_pos = -1
	_overtake_timer = 0.0
	_last_lit = -1
	_wrong_way_beep_t = 0.0
	_finished_beep = false
	help.visible = true
	_help_full = false
	if _help_label:
		_help_label.text = QUICK_HELP
	_status_text = ""
	_flag = {}
	_feed_h = 0.0
	_help_key = ""
	show()
	update(0.0)

func toggle_help() -> void:
	if not help.visible:
		help.visible = true
		_help_full = true
		if _help_label: _help_label.text = HELP_TEXT
	elif not _help_full:
		_help_full = true
		if _help_label: _help_label.text = HELP_TEXT
	else:
		help.visible = false
		_help_full = false
	_fit_help()

func _draw_overtake() -> void:
	if _overtake_timer <= 0.0:
		return
	var W := _overtake_control.size.x
	var H := _overtake_control.size.y
	var alpha := clampf(_overtake_timer * 2.0, 0.0, 1.0)
	var bg := Color(CmrStyle.GREEN.darkened(0.45), 0.92 * alpha) if _overtake_up else Color(CmrStyle.AMBER, 0.88 * alpha)
	var ink := Color(1, 1, 1, alpha) if _overtake_up else Color(CmrStyle.INK, alpha)
	var r := Rect2(0, 0, W, H)
	_overtake_control.draw_rect(r, bg)
	_overtake_control.draw_rect(r, Color(1, 1, 1, 0.9 * alpha), false, 2.0)
	var txt := ("▲ OVERTAKE! P%d" % _overtake_pos) if _overtake_up else ("▼ P%d" % _overtake_pos)
	_overtake_control.draw_string(_bold, Vector2(0, 27), txt, HORIZONTAL_ALIGNMENT_CENTER, W, 18, ink)

## Whether a change of place may be called out: never under a safety car, a red flag or yellows (nobody may
## pass there, places only change through the pits or a car stopping), nor while a place must be given back.
func _overtake_allowed() -> bool:
	if not race.rc:
		return true
	if race.rc.flag != "green":
		return false
	return _flag.is_empty() or str(_flag.get("title", "")) == "GREEN FLAG"

## Call once per frame while a race is on screen.
func update(dt: float) -> void:
	if not race:
		return
	_clock += dt
	_nitro_label.visible = race.mods.has("nitro") and visible
	if _nitro_label.visible:
		var bars := int(round(race.nitro * 10.0))
		_nitro_label.text = "N2O  " + "█".repeat(bars) + "░".repeat(10 - bars)
		_nitro_label.add_theme_color_override("font_color", Color("#7fe8ff") if race.nitro_burning else Color("#3aa8ff"))
	var dash_key := _dash_state()
	if dash_key != _dash_key:
		_dash_key = dash_key
		dash.queue_redraw()
	if co_driver:
		co_driver.voice_on = voice_on
		co_driver.update(audio != null and audio.muted, warp)
	_update_splits()
	if help.visible and not _help_full and race.phase == "racing" and race.race_time > QUICK_HELP_SECS:
		help.visible = false
	if race.s.mode != "race":
		_update_mode()
		deltabar.queue_redraw()
	var note_key := _pacenote_key()
	if note_key != _note_key:
		_note_key = note_key
		pacenote.queue_redraw()
	flagbar.queue_redraw()
	if _minimap_key() != _map_key:
		minimap_base.queue_redraw()
	minimap.queue_redraw()

	if _overtake_timer > 0.0:
		_overtake_timer -= dt
		_overtake_control.queue_redraw()
	_flag = race.rc.player_flag() if race.rc and race.phase == "racing" else {}
	if not _overtake_allowed():
		_overtake_timer = 0.0 # a call already up goes as the flag comes out
	var cur_pos: int = race.player.pos if (race and race.player) else -1
	if race and race.phase == "racing" and _prev_player_pos > 0 and cur_pos > 0 and cur_pos != _prev_player_pos and _overtake_allowed():
		if cur_pos < _prev_player_pos:
			_overtake_timer = 2.8
			_overtake_pos = cur_pos
			_overtake_up = true
			if is_instance_valid(audio) and not audio.muted:
				audio.beep(1046.5, 1)
			_overtake_control.queue_redraw()
		elif cur_pos > _prev_player_pos:
			_overtake_timer = 1.8
			_overtake_pos = cur_pos
			_overtake_up = false
			_overtake_control.queue_redraw()
	_prev_player_pos = cur_pos

	if race and not race.s.qualifying:
		if race.phase == "countdown":
			var cur_lit := clampi(int(floorf(race.clock)), 0, 5)
			if cur_lit > _last_lit and cur_lit > 0:
				_last_lit = cur_lit
				if is_instance_valid(audio) and not audio.muted:
					audio.beep(440.0, 1)
		elif race.phase == "racing" and _last_lit >= 0:
			_last_lit = -1
			if is_instance_valid(audio) and not audio.muted:
				audio.beep(880.0, 1)

	var plyr := race.player if race else null
	if plyr and plyr.control == "free" and absf(plyr.speed) > 3.0 and race.track and cos(plyr.heading - race.track.heading(plyr.s)) < -0.35:
		_wrong_way_beep_t -= dt
		if _wrong_way_beep_t <= 0.0:
			_wrong_way_beep_t = 0.85
			if is_instance_valid(audio) and not audio.muted:
				audio.beep(330.0, 2)
	else:
		_wrong_way_beep_t = 0.0

	if plyr and plyr.finished and not _finished_beep:
		_finished_beep = true
		if is_instance_valid(audio) and not audio.muted:
			if plyr.pos == 1:
				audio.beep(1046.5, 3)
			elif plyr.pos <= 3:
				audio.beep(880.0, 2)
	statusbar.queue_redraw()
	_layout()
	tags.queue_redraw()
	_refresh_t -= dt
	if _refresh_t > 0.0:
		return
	_refresh_t = REFRESH
	if race.s.qualifying:
		_sheet = Qualifying.sheet(race)
	pitwall.visible = _pit_relevant()
	tower.size.y = mini(_sheet.size(), _tower_rows()) * (ROW_H + 2.0) if race.s.qualifying else _tower_list().size() * (ROW_H + 2.0) + 3.0
	var pw_h := _pitwall_height()
	pitwall.offset_top = -14.0 - pw_h
	tower.queue_redraw()
	clock.queue_redraw()
	modepanel.queue_redraw()
	splitbox.queue_redraw()
	lights.queue_redraw()
	feed.queue_redraw()
	pitwall.queue_redraw()
	_update_banner()
	_update_event_sounds()

# ---------------- layout ----------------
const EDGE := 14.0 ## margin from the canvas edge
const STACK_TOP := 150.0 ## the centre column starts under the pace notes (14..146)
const STACK_GAP := 6.0
const PACENOTE_HALF := 150.0
const SPLIT_W := 238.0
const LIGHTS_W := 180.0 ## five lamps on their board (see _draw_lights)
const HELP_FONT := 12
const STATUS_FONT := 13

## Places everything that can share screen space, from the canvas size and what is showing: the centre
## column (start lights, flag board, split, overtake call, delta bar, banner) stacks top-down in the band
## between the left panel and the clock; the event feed stops above the dash; the key help wraps between
## the pit wall and the dash with the status chip above it. Name tags keep out of the areas noted in
## _reserved. Called every frame (cheap: a few rects).
func _layout() -> void:
	var W := size.x
	var H := size.y
	if W < 1.0 or H < 1.0:
		return
	_reserved.clear()
	var cx := W * 0.5
	var left_w := MODE_W if modepanel.visible else (TOWER_W if tower.visible else 0.0)
	var band := _band_half()
	# bottom centre first (the column above must stop over it): the key help, the status chip above it
	_fit_help()
	var floor_y := H - EDGE
	if help.visible:
		var hr := help_rect()
		_reserved.append(hr)
		floor_y = hr.position.y
	if _status_text != "":
		var sw := _bold.get_string_size(_status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, STATUS_FONT).x + 36.0
		_place(statusbar, 0.5, 1.0, 0.5, 1.0, -sw * 0.5, floor_y - H - 8.0 - 26.0, sw * 0.5, floor_y - H - 8.0)
		_reserved.append(Rect2(cx - sw * 0.5, floor_y - 8.0 - 26.0, sw, 26.0))
		floor_y -= 8.0 + 26.0
	floor_y -= 8.0
	# the split goes left of the clock, as in CMR, when the pace notes leave it room; else into the column
	_split_beside = W - EDGE - CLOCK_W - 20.0 - SPLIT_W - 12.0 >= cx + PACENOTE_HALF + 12.0
	if _split_beside:
		_place(splitbox, 1.0, 0.0, 1.0, 0.0, -EDGE - CLOCK_W - 20 - 250, 32, -EDGE - CLOCK_W - 20 - 12, 90)
		if _split_showing():
			_reserved.append(Rect2(W - EDGE - CLOCK_W - 20 - 250, 32, SPLIT_W, 44))
	# the centre column, most important first; whatever would run into the chip or the help is left out
	var stack: Array = [] ## [control, width, height]
	if _lights_showing():
		stack.append([lights, LIGHTS_W, 48.0])
	if not _flag.is_empty():
		stack.append([flagbar, minf(420.0, band * 2.0), 54.0])
	if not _split_beside and _split_showing():
		stack.append([splitbox, SPLIT_W, 44.0])
	if _overtake_timer > 0.0:
		stack.append([_overtake_control, minf(340.0, band * 2.0), 42.0])
	if _delta_showing():
		stack.append([deltabar, minf(DELTA_W, band * 2.0), _delta_height()])
	for b: Label in [banner, banner_small]:
		if b.text != "":
			stack.append([b, band * 2.0, _label_height(b, band * 2.0)])
	var y := STACK_TOP
	for item in stack:
		var c: Control = item[0]
		var w: float = item[1]
		var h: float = item[2]
		if y + h > floor_y:
			c.self_modulate.a = 0.0
			continue
		c.self_modulate.a = 1.0
		_place(c, 0.5, 0.0, 0.5, 0.0, -w * 0.5, y, w * 0.5, y + h)
		var used_w := w
		if c is Label:
			used_w = minf(w, _label_width(c as Label))
		_reserved.append(Rect2(cx - used_w * 0.5, y, used_w, h))
		y += h + STACK_GAP
	_stack_bottom = y - STACK_GAP
	_reserved.append(Rect2(cx - PACENOTE_HALF, EDGE, PACENOTE_HALF * 2.0, 132.0))
	# right column: clock, minimap, then the feed down to just above the dash
	feed.offset_bottom = maxf(feed.offset_top + 30.0, minf(700.0, H - 190.0 - 10.0))
	_reserved.append(Rect2(W - EDGE - CLOCK_W, EDGE, CLOCK_W, 208.0))
	_reserved.append(Rect2(minimap.position, minimap.size))
	if _feed_h > 0.0:
		_reserved.append(Rect2(feed.position, Vector2(FEED_W, minf(_feed_h, feed.size.y))))
	_reserved.append(Rect2(dash.position, dash.size))
	# left column
	if tower.visible:
		_reserved.append(Rect2(tower.position, Vector2(TOWER_W, tower.size.y)))
	if modepanel.visible:
		_reserved.append(Rect2(modepanel.position, Vector2(left_w, modepanel.size.y)))
	if pitwall.visible:
		_reserved.append(Rect2(pitwall.position, pitwall.size))

## Where the key help sits: the rect its offsets ask for, grown to the panel's real rect (a label can need
## more height than measured, e.g. another skin's face, and the panel then grows upward over what is above).
func help_rect() -> Rect2:
	var r := Rect2(size.x * 0.5 + help.offset_left, size.y + help.offset_top, help.offset_right - help.offset_left, help.offset_bottom - help.offset_top)
	if help.size.y > 0.0:
		r = r.merge(Rect2(help.position, help.size))
	return r

## Half the width of the free band down the centre, between the left column (timing tower or stage panel)
## and the right one (clock, minimap and the event feed, the widest of them), around the canvas centre.
func _band_half() -> float:
	var cx := size.x * 0.5
	var left_w := MODE_W if modepanel.visible else (TOWER_W if tower.visible else 0.0)
	var left := EDGE + left_w + 12.0
	var right := size.x - EDGE - maxf(CLOCK_W, FEED_W) - 12.0
	return maxf(PACENOTE_HALF, minf(cx - left, right - cx))

## The rows the timing tower may show above the pit wall (the rest are cut, the player's row always kept).
func _tower_rows() -> int:
	if not pitwall.visible:
		return 99
	var room := size.y - EDGE - _pitwall_height() - 10.0 - EDGE
	return maxi(4, int(floorf(room / (ROW_H + 2.0))))

func _label_height(l: Label, width: float) -> float:
	var f := l.get_theme_font("font")
	var fs := l.get_theme_font_size("font_size")
	var sz := f.get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_CENTER, width, fs)
	var lines := maxi(1, roundi(sz.y / maxf(1.0, f.get_height(fs))))
	return ceilf(sz.y + 3.0 * (lines - 1) + l.get_theme_constant("outline_size") * 0.5)

func _label_width(l: Label) -> float:
	var f := l.get_theme_font("font")
	return f.get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_CENTER, -1, l.get_theme_font_size("font_size")).x + l.get_theme_constant("outline_size")

## The key help, centred at the bottom, wrapped to fit between the pit wall and the dash.
## The controls guide: two columns of key and action on the skin's plate.
func _draw_guide() -> void:
	var W := _guide.size.x
	_guide.draw_string(_bold, Vector2(0, 14), "CONTROLS", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, YELLOW)
	_guide.draw_string(_font, Vector2(0, 14), "H  close", HORIZONTAL_ALIGNMENT_RIGHT, W, 11, MUTED)
	_guide.draw_rect(Rect2(0, 19, W, 1), Color(YELLOW, 0.5))
	var rows := ceili(GUIDE.size() / 2.0)
	var colw := W * 0.5
	for i in GUIDE.size():
		var x := (i / rows) * colw
		var y := 36.0 + (i % rows) * 16.0
		_guide.draw_string(_bold, Vector2(x, y), GUIDE[i][0], HORIZONTAL_ALIGNMENT_LEFT, colw * 0.46, 12, TEXT)
		_guide.draw_string(_font, Vector2(x + colw * 0.46, y), GUIDE[i][1], HORIZONTAL_ALIGNMENT_LEFT, colw * 0.54 - 8.0, 12, MUTED)

func _fit_help() -> void:
	if not _help_label or size.x < 1.0:
		return
	var W := size.x
	var key := "%d|%d|%s|%s|%s" % [int(W), int(size.y), pitwall.visible, _help_label.text.hash(), _help_full]
	if key == _help_key:
		return
	_help_key = key
	var left := EDGE + (PITWALL_W if pitwall.visible else 0.0) + 12.0
	var right := W - EDGE - 346.0 - 12.0 # the dash
	var room := 2.0 * minf(W * 0.5 - left, right - W * 0.5) - 36.0
	var natural := _font.get_multiline_string_size(_help_label.text, HORIZONTAL_ALIGNMENT_CENTER, -1, HELP_FONT).x
	var tw := minf(natural, room)
	_help_label.visible = not _help_full
	_guide.visible = _help_full
	if _help_full:
		var gw := clampf(room, 300.0, 600.0)
		var rows := ceili(GUIDE.size() / 2.0)
		_guide.custom_minimum_size = Vector2(gw, 24.0 + rows * 16.0)
		_guide.queue_redraw()
		help.offset_left = -(gw + 36.0) * 0.5
		help.offset_right = (gw + 36.0) * 0.5
		help.offset_top = -EDGE - (24.0 + rows * 16.0) - 12.0
		help.offset_bottom = -EDGE
		return
	_help_label.custom_minimum_size.y = 0.0
	if natural > room:
		_help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_help_label.custom_minimum_size.x = tw
	else:
		_help_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		_help_label.custom_minimum_size.x = 0.0
	var th := _font.get_multiline_string_size(_help_label.text, HORIZONTAL_ALIGNMENT_CENTER, tw + 1.0, HELP_FONT).y
	var lines := maxi(1, roundi(th / maxf(1.0, _font.get_height(HELP_FONT))))
	var spacing := _help_label.get_theme_constant("line_spacing")
	th += spacing * (lines - 1)
	# the label's own measure where it knows better (its lines as shaped, with the line spacing it draws)
	if natural <= room:
		var n := _help_label.text.count("\n") + 1
		th = maxf(th, n * _help_label.get_line_height() + spacing * (n - 1))
	help.offset_left = -(tw + 36.0) * 0.5
	help.offset_right = (tw + 36.0) * 0.5
	help.offset_top = -EDGE - th - 12.0
	help.offset_bottom = -EDGE

func _lights_showing() -> bool:
	return false # the 3D gantry carries the start lights

func _split_showing() -> bool:
	return race != null and race.s.mode == "race" and not _split_show.is_empty() and race.race_time <= float(_split_show.until) and warp <= 1

## Whether the delta bar has something to show this frame (see _draw_delta_bar).
func _delta_showing() -> bool:
	if not race or race.s.mode == "race" or warp > 1:
		return false
	var showing := not _mode_split.is_empty() and _clock < float(_mode_split.until)
	if race.stage:
		return showing
	var tt := race.tt
	if not tt:
		return false
	if showing or tt.out_lap():
		return true
	var d = tt.live_delta()
	if d == null and records:
		d = records.gap()
	return d != null and race.phase == "racing"

func _delta_height() -> float:
	var showing := not _mode_split.is_empty() and _clock < float(_mode_split.until)
	return 50.0 if race.tt and not showing and race.tt.out_lap() else 84.0

## The chip above the key help: AUTOPILOT, or the co-driver driving with the clock sped up.
func _draw_status() -> void:
	if _status_text == "" or not race:
		return
	var r := Rect2(Vector2.ZERO, statusbar.size)
	statusbar.draw_rect(r, _plate(0.82))
	statusbar.draw_rect(Rect2(0, 0, 5, r.size.y), YELLOW)
	statusbar.draw_string(_bold, Vector2(5, 18), _status_text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 5, STATUS_FONT, TEXT)

## CmrStyle.restyle() calls this on a skin change: the plates and outlines built from the palette are rebuilt.
func _skin_changed() -> void:
	_panel_style = CmrStyle.panel(_plate(0.8), Color(CmrStyle.VIOLET, 0.5), 0)
	if help:
		help.add_theme_stylebox_override("panel", CmrStyle.box(_plate(0.62), Color.TRANSPARENT, 18, 6))
	if _help_label:
		_help_label.add_theme_color_override("font_color", CmrStyle.MUTED)
	for b in [banner, banner_small]:
		if b:
			(b as Label).add_theme_color_override("font_outline_color", _shade(0.9))
	_dash_size = Vector2.ZERO
	_dash_key = []
	_note_key = []
	_map_key = ""
	_help_key = ""
	_fitted.clear()
	for c in get_children():
		if c is CanvasItem:
			(c as CanvasItem).queue_redraw()

# ---------------- helpers ----------------
func _canvas(fn: Callable) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(fn)
	add_child(c)
	return c

static func _place(c: Control, al: float, at: float, ar: float, ab: float, ol: float, ot: float, orr: float, ob: float) -> void:
	c.anchor_left = al
	c.anchor_top = at
	c.anchor_right = ar
	c.anchor_bottom = ab
	c.offset_left = ol
	c.offset_top = ot
	c.offset_right = orr
	c.offset_bottom = ob

func _banner_label(size: int) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART # a long line wraps inside the free band, never under a panel
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_font_override("font", _bold)
	l.add_theme_color_override("font_outline_color", _shade(0.9))
	l.add_theme_constant_override("outline_size", 12 if size > 20 else 6)
	return l

func _text(c: Control, at: Vector2, s: String, size: int, color: Color, bold := false, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	_audit_text(c, _bold if bold else _font, at, s, align, width, size)
	c.draw_string(_bold if bold else _font, at, s, align, width, size, color)

## The CMR 2.0 bar: a plain rectangle, bright at one end fading to translucent violet at the other.
func _gbar(c: Control, rect: Rect2, hi := BAR_HI, lo := BAR_LO, flip := false) -> void:
	var a := hi if not flip else lo
	var b := lo if not flip else hi
	var pts := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	c.draw_polygon(pts, PackedColorArray([a, b, b, a]))

## A quad into the panel's triangle list, corners clockwise from the top left with their own colours.
func _tri_quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	var i := _tri_points.size()
	_tri_points.append(a)
	_tri_points.append(b)
	_tri_points.append(c)
	_tri_points.append(d)
	_tri_colors.append(ca)
	_tri_colors.append(cb)
	_tri_colors.append(cc)
	_tri_colors.append(cd)
	_tri_indices.append_array(PackedInt32Array([i, i + 1, i + 2, i, i + 2, i + 3]))

func _tri_rect(rect: Rect2, col: Color) -> void:
	_tri_quad(rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y), col, col, col, col)

## _gbar into the triangle list.
func _tri_gbar(rect: Rect2, hi := BAR_HI, lo := BAR_LO) -> void:
	_tri_quad(rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y), hi, lo, lo, hi)

## A polyline into the triangle list: width wide with a pixel of soft edge each side, like an
## antialiased draw_polyline (which Godot splits into dozens of draw calls). closed when it ends where it starts.
func _tri_strip(pts: PackedVector2Array, width: float, col: Color, closed := false) -> void:
	var n := pts.size()
	if n < 2:
		return
	var clear := Color(col, 0.0)
	var half := width * 0.5
	var base := _tri_points.size()
	for i in n:
		var prev := pts[i - 1] if i > 0 else (pts[n - 2] if closed else pts[0])
		var next := pts[i + 1] if i < n - 1 else (pts[1] if closed else pts[n - 1])
		var n1 := (pts[i] - prev).normalized().orthogonal() if pts[i] != prev else Vector2.ZERO
		var n2 := (next - pts[i]).normalized().orthogonal() if next != pts[i] else Vector2.ZERO
		var m := (n1 + n2).normalized() if n1 + n2 != Vector2.ZERO else (n1 if n1 != Vector2.ZERO else n2)
		# mitre the corner, but not into a spike on a hairpin
		var k := 1.0 / maxf(0.5, m.dot(n1 if n1 != Vector2.ZERO else n2))
		for off in [half + 1.0, half, -half, -half - 1.0]:
			_tri_points.append(pts[i] + m * off * k)
		_tri_colors.append(clear)
		_tri_colors.append(col)
		_tri_colors.append(col)
		_tri_colors.append(clear)
	for i in n - 1:
		var a := base + i * 4
		var b := a + 4
		for band in 3:
			_tri_indices.append_array(PackedInt32Array([a + band, b + band, b + band + 1, a + band, b + band + 1, a + band + 1]))

## A meter (a dark track filled to frac in col) into the triangle list.
func _tri_meter(rect: Rect2, frac: float, col: Color) -> void:
	_tri_rect(rect, METER_BG)
	_tri_rect(Rect2(rect.position, Vector2(rect.size.x * clampf(frac, 0.0, 1.0), rect.size.y)), col)

## An outline width wide centred on rect's edges (draw_rect unfilled) into the triangle list.
func _tri_frame(rect: Rect2, col: Color, width := 1.0) -> void:
	var h := width * 0.5
	_tri_rect(Rect2(rect.position.x - h, rect.position.y - h, rect.size.x + width, width), col)
	_tri_rect(Rect2(rect.position.x - h, rect.end.y - h, rect.size.x + width, width), col)
	_tri_rect(Rect2(rect.position.x - h, rect.position.y + h, width, rect.size.y - width), col)
	_tri_rect(Rect2(rect.end.x - h, rect.position.y + h, width, rect.size.y - width), col)

## Round tyre badge, the compound letter in a ring of the compound's colour on a dark disc: the disc and
## ring go down with _flush_badges, the letter with _q_flush.
func _q_badge(center: Vector2, compound, big := false) -> void:
	var r := 13.0 if big else 8.5
	var key: String = compound if compound else "M"
	var col: Color = race.tyres.compounds[key].color
	_badges.append([center, r, (9.5 if big else 6.0) / r, col])
	var size := 12 if big else 9
	_q(center + Vector2(-r, size * 0.36), key, size, col, _bold, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0)

## The queued badges' dark discs, then their rings: two batched draws.
func _flush_badges(c: Control) -> void:
	for b in _badges:
		_round(c, b[0], b[1], Color("#111111"))
	for b in _badges:
		_round(c, b[0], b[1], b[3], b[2])
	_badges.clear()

## Draws the triangle list in one call and empties it.
func _tri_flush(c: Control) -> void:
	if not _tri_indices.is_empty():
		RenderingServer.canvas_item_add_triangle_array(c.get_canvas_item(), _tri_indices, _tri_points, _tri_colors)
	_tri_points.clear()
	_tri_colors.clear()
	_tri_indices.clear()

## Text for _q_flush. outline gives it the dark edge white type gets straight over the 3D view, as in CMR.
func _q(at: Vector2, s: String, size: int, color: Color, font: Font = null, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, outline := false) -> void:
	var f := font if font else _bold
	if outline:
		_queued.append([maxi(2, size / 9), f, at, s, align, width, size, _shade(0.85 * color.a)])
	_queued.append([0, f, at, s, align, width, size, color])

## Layout tests set this to an Array: every string the panels draw is then recorded as
## [canvas, font, baseline, text, align, width, size] so a test can check each one fits its panel.
var text_audit = null

func _audit_text(c: Control, f: Font, at: Vector2, s: String, align: int, width: float, size: int) -> void:
	if text_audit != null:
		text_audit.append([c, f, at, s, align, width, size])

## The queued text, outlines first, grouped by font and size so each group's glyphs batch together.
func _q_flush(c: Control) -> void:
	var groups := {}
	var keys: Array = []
	for t in _queued:
		var key := Vector3i(-t[0], t[1].get_instance_id() % 1000003, t[6])
		if not groups.has(key):
			groups[key] = []
			keys.append(key)
		groups[key].append(t)
	keys.sort()
	for key in keys:
		for t in groups[key]:
			if t[0] > 0:
				c.draw_string_outline(t[1], t[2], t[3], t[4], t[5], t[6], t[0], t[7])
			else:
				_audit_text(c, t[1], t[2], t[3], t[4], t[5], t[6])
				c.draw_string(t[1], t[2], t[3], t[4], t[5], t[6], t[7])
	_queued.clear()

## A white antialiased disc (inner 0) or ring (inner: hole radius over outer radius) px texels across,
## tinted when drawn with _round.
func _round_tex(px: int, inner: float) -> Texture2D:
	var key := "%d:%.3f" % [px, inner]
	if _round_textures.has(key):
		return _round_textures[key]
	var img := Image.create_empty(px, px, false, Image.FORMAT_RGBA8)
	var half := px * 0.5
	for y in px:
		for x in px:
			var d := Vector2(x + 0.5 - half, y + 0.5 - half).length()
			var a := clampf(half - d + 0.5, 0.0, 1.0)
			if inner > 0.0:
				a = minf(a, clampf(d - inner * half + 0.5, 0.0, 1.0))
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var tex := ImageTexture.create_from_image(img)
	_round_textures[key] = tex
	return tex

## A disc or ring of outer radius r from _round_tex (drawn about two texels per HUD pixel).
func _round(c: Control, center: Vector2, r: float, col: Color, inner := 0.0) -> void:
	var tex := _round_tex(maxi(8, ceili(r) * 4), inner)
	c.draw_texture_rect(tex, Rect2(center - Vector2(r, r), Vector2(r, r) * 2.0), false, col)

func _text_w(s: String, size: int, bold := false) -> float:
	return (_bold if bold else _font).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

func _fit(s: String, size: int, width: float) -> String:
	var key := "%s|%d|%d" % [s, size, int(width)]
	if _fitted.has(key):
		return _fitted[key]
	var out := s
	if _text_w(out, size, true) > width:
		while out.length() > 1 and _text_w(out + "…", size, true) > width:
			out = out.left(-1)
		out += "…"
	_fitted[key] = out
	return out

static func _clock_text(sec: float) -> String:
	var t := maxi(0, int(floorf(sec)))
	var h := t / 3600
	var m := (t % 3600) / 60
	var s := t % 60
	return "%d:%02d:%02d" % [h, m, s] if h > 0 else "%d:%02d" % [m, s]

static func _whole_time(t) -> String:
	var s := Race.fmt_time(t)
	var dot := s.rfind(".")
	return s.left(dot) if dot >= 0 else s

# ---------------- tower ----------------
func _gap_text(car: RaceCar, leader: RaceCar, i: int) -> String:
	var L := race.track.L
	if car.dnf:
		return "OUT"
	if i == 0:
		if car.finished:
			return "FINISH"
		return "LAP %d" % ((car.lap + 1) if race.timed else mini(car.lap + 1, race.R))
	if car.finished and leader.finish_time != null and car.finish_time != null:
		var laps_down := leader.finish_lap - car.finish_lap
		return "+%dL" % laps_down if laps_down > 0 else "+%.1f" % (car.finish_time - leader.finish_time)
	if car.mode == "pit":
		return "PIT"
	var lead: float = leader.finish_lap * L if leader.finished else leader.lap * L + leader.s
	var down := int(floorf((lead - (car.lap * L + car.s)) / L))
	if down >= 1:
		return "+%dL" % down
	return "+%.1f" % maxf(0.0, car.gap)

## Qualifying: the time sheet instead of the running order, pole on top.
func _draw_sheet() -> void:
	for i in mini(_sheet.size(), _tower_rows()):
		var r: Dictionary = _sheet[i]
		var y := i * (ROW_H + 2.0)
		if r.is_player:
			_gbar(tower, Rect2(0, y, TOWER_W, ROW_H), YELLOW, Color(YELLOW, 0.55))
		else:
			_gbar(tower, Rect2(0, y, TOWER_W, ROW_H), BAR_HI, BAR_LO)
		var base := y + 15.5
		_text(tower, Vector2(4, base), str(i + 1), 13, INK, true, HORIZONTAL_ALIGNMENT_RIGHT, 24)
		tower.draw_rect(Rect2(36, y + 3, 4, 15), r.color)
		_text(tower, Vector2(44, base), str(r.number), 11, CmrStyle.INK_SOFT, true, HORIZONTAL_ALIGNMENT_RIGHT, 26)
		var nm: String = str(r.name).to_upper() if r.is_player else str(r.name).split(" ")[-1].to_upper()
		_text(tower, Vector2(78, base), _fit(nm, 12, 64), 12, INK, true)
		var t := "—"
		if r.time != null:
			t = Race.fmt_time(r.time) if i == 0 else "+%.3f" % r.gap
		_text(tower, Vector2(120, base), t, 12, INK, true, HORIZONTAL_ALIGNMENT_RIGHT, 112)

## The compact list: the leader, then the player with two cars ahead and two behind (de-duplicated).
## Each row shows the interval to the car directly ahead; the leader's row shows the lap instead.
func _tower_list() -> Array[int]:
	var out: Array[int] = []
	var order := race.order
	if order.is_empty():
		return out
	var mine := maxi(0, order.find(race.player))
	out.append(0)
	for i in range(maxi(1, mine - 2), mini(order.size(), mine + 3)):
		if i not in out:
			out.append(i)
	if mine <= 1:
		for i in range(1, mini(order.size(), 5)):
			if i not in out and out.size() < 5:
				out.append(i)
		out.sort()
	return out

## The gap to the car directly ahead of order[i] (the lap and the leader for row 0).
func _interval_text(i: int) -> String:
	var order := race.order
	var car: RaceCar = order[i]
	if i == 0 or car.dnf:
		return _gap_text(car, order[0], i)
	var ahead: RaceCar = order[i - 1]
	if car.mode == "pit":
		return "PIT"
	if car.finished and ahead.finished and car.finish_time != null and ahead.finish_time != null:
		var laps_down := ahead.finish_lap - car.finish_lap
		return "+%dL" % laps_down if laps_down > 0 else "+%.1f" % maxf(0.0, car.finish_time - ahead.finish_time)
	var L := race.track.L
	var d: float = (ahead.lap * L + ahead.s) - (car.lap * L + car.s)
	if d >= L:
		return "+%dL" % int(floorf(d / L))
	return "+%.1f" % maxf(0.0, car.gap - ahead.gap)

func _draw_tower() -> void:
	if not race:
		return
	if race.s.qualifying:
		_draw_sheet()
		return
	var order := race.order
	var rows := _tower_list()
	var W := TOWER_W
	var prev := -1
	var y := 0.0
	for i in rows:
		var c: RaceCar = order[i]
		if prev >= 0 and i > prev + 1:
			y += 3.0 # a visible break where cars were left out
		prev = i
		var fade := 0.5 if c.dnf else 1.0
		var base := y + 15.5
		if c.is_player:
			_tri_rect(Rect2(0, y, W, ROW_H), YELLOW)
		else:
			_tri_rect(Rect2(0, y, W, ROW_H), _plate(0.66 * fade))
		_tri_rect(Rect2(0, y, 4, ROW_H), Color(c.color, fade))
		var ink := INK if c.is_player else TEXT
		_q(Vector2(8, base), str(i + 1), 13, Color(ink, fade), _bold, HORIZONTAL_ALIGNMENT_RIGHT, 22)
		var nm := c.name.to_upper() if c.is_player else Brain.short(c).to_upper()
		_q(Vector2(38, base), _fit(nm, 12, 112), 12, Color(ink, fade), _bold)
		var txt := _interval_text(i)
		if i == 0 and not c.finished and not c.dnf:
			txt = "LAP %d/%d" % [(c.lap + 1), race.R] if not race.timed else "LAP %d" % (c.lap + 1)
		var col := Color("#ff9a7a") if c.mode == "pit" and not c.is_player else ink
		_q(Vector2(W - 84, base), txt, 12, Color(col, fade), _bold, HORIZONTAL_ALIGNMENT_RIGHT, 78)
		y += ROW_H + 2.0
	_tri_flush(tower)
	_q_flush(tower)

# ---------------- clock stack (top right) ----------------
## Segmented lap progress, the big clock, then lap / position / lap-time rows fading to the left.
func _draw_clock() -> void:
	if not race:
		return
	if race.s.mode != "race":
		_draw_mode_clock()
		return
	var p := race.player
	var W := CLOCK_W
	var x0 := clock.size.x - W
	# progress through the lap in green blocks, like CMR's stage splits
	var segs := 12
	var frac := clampf(p.s / race.track.L, 0.0, 1.0) if race.phase == "racing" else 0.0
	var sw := (W - (segs - 1) * 3.0) / segs
	for k in segs:
		var r := Rect2(x0 + k * (sw + 3.0), 0, sw, 12)
		var fill := clampf(frac * segs - k, 0.0, 1.0)
		# shapes into the triangle list and text queued, drawn together at the end (see _tri_quad)
		_tri_rect(r, _plate(0.55))
		if fill > 0.0:
			_tri_rect(Rect2(r.position, Vector2(r.size.x * fill, r.size.y)), YELLOW)
		_tri_frame(r, Color(1, 1, 1, 0.35))
	# the clock
	var time_text: String
	var quali := race.s.qualifying
	if quali:
		time_text = Race.fmt_time(maxf(0.0, race.race_time - p.lap_start)) if race.phase == "racing" else "0:00.00"
	elif race.timed:
		if race.phase == "countdown":
			time_text = _clock_text(race.duration)
		else:
			time_text = _clock_text(race.time_left) if race.time_left > 0.0 else "FINAL"
	else:
		time_text = "0:00.00" if race.phase == "countdown" else Race.fmt_time(race.race_time)
	var box := Rect2(x0, 18, W, 58)
	var box_style := CmrStyle.box(BAR_HI, Color.TRANSPARENT, 0, 0)
	box_style.border_color = Color(1, 1, 1, 0.9)
	box_style.border_width_top = 2
	box_style.draw(clock.get_canvas_item(), box)
	var clock_label := "TIME LEFT" if race.timed else "RACE"
	if quali:
		clock_label = "OUT LAP" if p.lap == 0 else "TIMED LAP %d / %d" % [mini(p.lap, race.R - 1), race.R - 1]
	_q(Vector2(x0 + 14, 34), clock_label, 11, CmrStyle.INK_SOFT)
	if not quali and not records:
		var rank_col := Color("#d97706") if p.pos == 1 else (Color("#475569") if p.pos == 2 else (Color("#b45309") if p.pos == 3 else INK))
		_q(Vector2(x0 + 14, 52), "P%d" % p.pos, 22, rank_col, _bold, HORIZONTAL_ALIGNMENT_LEFT, 50)
		_q(Vector2(x0 + 58, 50), "/ %d" % race.cars.size(), 11, CmrStyle.INK_SOFT, _bold, HORIZONTAL_ALIGNMENT_LEFT, 40)
	if records and records.ghost_time != null:
		# under the label: how far behind (+) or ahead (−) of the lap record this lap is, or the record itself
		var gap = records.gap()
		_q(Vector2(x0 + 14, 50), "VS RECORD" if gap != null else "RECORD", 10, CmrStyle.INK_SOFT)
		if gap != null:
			_q(Vector2(x0 + 14, 70), "%s%.2f" % ["+" if gap >= 0.0 else "−", absf(gap)], 18, RED if gap >= 0.0 else PURPLE)
		else:
			_q(Vector2(x0 + 14, 67), Race.fmt_time(records.ghost_time), 13, CmrStyle.INK_SOFT)
	_q(Vector2(x0, 68), time_text, 38, INK, _digits, HORIZONTAL_ALIGNMENT_RIGHT, W - 18)
	# rows
	var lap := str(p.lap + 1) if race.timed else "%d / %d" % [mini(p.lap + 1, race.R), race.R]
	var best_col := PURPLE if race.fastest and race.fastest.car == p else INK
	var current := Race.fmt_time(race.race_time - p.lap_start) if race.phase == "racing" else "—"
	var rows := [["LAP", lap, INK], ["POS", "%d / %d" % [p.pos, race.cars.size()], INK],
		["THIS LAP", current, INK], ["LAST", Race.fmt_time(p.last_lap), INK], ["BEST", Race.fmt_time(p.best_lap), best_col]]
	if quali:
		var pole = _sheet[0].time if not _sheet.is_empty() else null
		var mine := 0
		for k in _sheet.size():
			if _sheet[k].is_player:
				mine = k + 1
		rows = [["LAP", "OUT" if p.lap == 0 else "%d / %d" % [mini(p.lap, race.R - 1), race.R - 1], INK],
			["GRID", "P%d / %d" % [mine, _sheet.size()] if p.best_lap != null else "—", INK],
			["LAST", Race.fmt_time(p.last_lap) if p.lap > 1 else "—", INK], ["BEST", Race.fmt_time(p.best_lap), PURPLE if mine == 1 and p.best_lap != null else INK],
			["POLE", Race.fmt_time(pole), INK]]
	var y := 82.0
	for row in rows:
		_tri_gbar(Rect2(x0 + 40, y, W - 40, 20), Color(BAR_HI, 0.55), BAR_HI)
		_q(Vector2(x0 + 56, y + 15), row[0], 11, CmrStyle.INK_SOFT)
		_q(Vector2(x0 + 60, y + 15.5), row[1], 14, row[2], _bold, HORIZONTAL_ALIGNMENT_RIGHT, W - 72)
		y += 22.0
	# weather and local time, on a dark plate so it reads over a bright sky or a busy background
	var tod := race.time_of_day
	var clock_text := "%02d:%02d" % [int(tod), int(fmod(tod, 1.0) * 60.0)]
	if warp > 1:
		clock_text += "  ×%d" % warp
	var w := race.weather
	var sky := "RAIN" if w.rain > 0.05 else ("DAMP" if w.wet > 0.05 else "DRY")
	var weather_text := "%s %d%% · %s · %s" % [sky, roundi(w.wet * 100.0), w.forecast(maxf(0.0, race.race_time)), clock_text]
	var tw := minf(W, _text_w(weather_text, 12) + 16.0)
	if w.rain > 0.05 or w.wet > 0.05 or warp > 1:
		_tri_rect(Rect2(x0 + W - tw, y + 1, tw, 17), _shade(0.62))
		_q(Vector2(x0, y + 14), weather_text, 12, TEXT, _font, HORIZONTAL_ALIGNMENT_RIGHT, W - 8, true)
	_tri_flush(clock)
	_q_flush(clock)

# ---------------- pace note (top centre) ----------------
## The co-driver's calls, as CMR 2.0 shows them: an orange box per note called and not yet driven, its
## black arrow drawn for the grade (a gentle bend for flat, an elbow for square, a U for a hairpin, a hump
## for a crest) with a red "!" for a caution; the call written underneath, or the corner's name between notes.
func _draw_pacenote() -> void:
	if not race:
		return
	var S := 74.0
	var cx := pacenote.size.x * 0.5
	var live: Array = co_driver.current() if co_driver else []
	var caption := ""
	if not live.is_empty():
		_draw_note_box(Rect2(cx - S * 0.5, 0, S, S), live[0], 1.0)
		if live.size() > 1:
			# the next one already called, smaller beside it
			var s2 := S * 0.62
			_draw_note_box(Rect2(cx + S * 0.5 + 8.0, 0, s2, s2), live[1], 0.8)
		caption = PaceNotes.label(live[0])
	if caption != "":
		caption = _fit(caption, 13, pacenote.size.x - 28.0) # a long corner name ends in "…" inside its plate
		var tw := minf(pacenote.size.x, _text_w(caption, 13, true) + 28.0)
		var r := Rect2(cx - tw * 0.5, S + 8, tw, 22)
		_tri_gbar(r, _plate(0.8), _plate(0.8))
		_q(Vector2(r.position.x, r.position.y + 16), caption, 13, TEXT, _bold, HORIZONTAL_ALIGNMENT_CENTER, tw)

	# Gran Turismo 4 style dynamic corner BRAKE alert
	var p := race.player
	var brake_need: float = race.brake_assist(p) if (race.phase == "racing" and not p.finished) else 0.0
	if brake_need > 0.08 and p.speed > 13.0 and p.brake < 0.25:
		var pulse := int(_clock * 8.0) % 2 == 0
		var bw := 124.0
		var bh := 24.0
		var br := Rect2(cx - bw * 0.5, S + 34, bw, bh)
		_tri_rect(br, Color(RED, 0.95 if pulse else 0.72))
		_tri_frame(br, Color(1, 1, 1, 0.95), 2.0)
		_q(Vector2(br.position.x, br.position.y + 17), "[ ! BRAKE ! ]", 14, Color.WHITE, _bold, HORIZONTAL_ALIGNMENT_CENTER, bw)

	_tri_flush(pacenote)
	_q_flush(pacenote)

## What the pace note shows: it redraws only when this changes (the notes come and go a few times a lap).
func _pacenote_key() -> Array:
	if not race:
		return []
	var live: Array = co_driver.live if co_driver else []
	var p := race.player
	var brake_alert: bool = p != null and race.phase == "racing" and not p.finished and race.brake_assist(p) > 0.08 and p.speed > 13.0 and p.brake < 0.25
	var flash_state := int(_clock * 8.0) % 2 if brake_alert else 0
	var sec_name := race.track.sector_name(p.s) if (race.track and p) else ""
	if live.is_empty():
		return [race.get_instance_id(), sec_name, brake_alert, flash_state]
	return [race.get_instance_id(), live[0], live[1] if live.size() > 1 else -1, brake_alert, flash_state]

## How far each grade's arrow turns (degrees) and the radius of its bend (share of the box).
const NOTE_ARROW := {"flat": [22.0, 0.9], "fast": [38.0, 0.6], "easy": [58.0, 0.42], "medium": [80.0, 0.3],
	"tight": [110.0, 0.2], "square": [90.0, 0.06], "hairpin": [180.0, 0.17]}

## One pace-note box: the arrow for the note's grade and direction inside an orange square, into the
## triangle list.
func _draw_note_box(box: Rect2, note: Dictionary, alpha: float) -> void:
	_tri_rect(box, Color(YELLOW, alpha))
	_tri_frame(box, Color(0, 0, 0, 0.9 * alpha), 3.0 if box.size.x > 60.0 else 2.0)
	var ink := Color(0, 0, 0, alpha)
	var S := box.size.x
	var width := S * 0.08
	var pts := PackedVector2Array()
	if note.dir == 0:
		# crest: a hump with the road running straight over it
		for k in 13:
			var t := k / 12.0
			pts.append(Vector2(lerpf(-0.36, 0.36, t), 0.12 - 0.24 * sin(PI * t)))
		_note_line(box, pts, width * 0.8, ink, false)
		pts = PackedVector2Array([Vector2(0, 0.36), Vector2(0, -0.3)])
		_note_line(box, pts, width, ink, true)
	else:
		var spec: Array = NOTE_ARROW.get(note.grade, [60.0, 0.4])
		var turn := deg_to_rad(spec[0])
		var r: float = spec[1]
		var side := float(note.dir)
		# a stem up from the bottom, the bend, then a short run out of it to the head
		var stem := 0.34 if note.grade != "hairpin" else 0.42
		var p := Vector2(0, 0)
		pts.append(p)
		p += Vector2(0, -stem)
		pts.append(p)
		var centre := p + Vector2(side * r, 0)
		var segs := maxi(2, int(spec[0] / 12.0))
		for k in range(1, segs + 1):
			var a := turn * k / segs
			pts.append(centre + Vector2(-side * r * cos(a), -r * sin(a)))
		var heading := Vector2(side * sin(turn), -cos(turn))
		pts.append(pts[-1] + heading * (0.16 if note.grade != "hairpin" else 0.1))
		_note_line(box, pts, width, ink, true)
	if note.caution:
		# a red tab with a white "!" on the box's outer top corner
		var tab := Rect2(box.position + Vector2(-S * 0.26, 0), Vector2(S * 0.22, S * 0.46))
		_tri_rect(tab, Color(RED, alpha))
		_tri_frame(tab, Color(0, 0, 0, 0.9 * alpha), 2.0)
		var bang := Color(1, 1, 1, alpha)
		var bx := tab.get_center().x - S * 0.035
		_tri_rect(Rect2(bx, tab.position.y + S * 0.07, S * 0.07, S * 0.2), bang)
		_tri_rect(Rect2(bx, tab.position.y + S * 0.31, S * 0.07, S * 0.07), bang)

## A note shape given in box-relative units (centred on the box, fitted inside its margin) into the triangle
## list, with an arrowhead on the last point when head.
func _note_line(box: Rect2, pts: PackedVector2Array, width: float, ink: Color, head: bool) -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for q in pts:
		lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
		hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
	var S := box.size.x
	var room := S * 0.6
	var scale := room / maxf(0.3, maxf(hi.x - lo.x, hi.y - lo.y))
	scale = minf(scale, S * 1.25)
	var mid := (lo + hi) * 0.5
	var out := PackedVector2Array()
	for q in pts:
		out.append(box.get_center() + (q - mid) * scale)
	if head:
		# leave room for the head so the line doesn't poke through its tip
		var tip := out[-1]
		var dir := (tip - out[-2]).normalized()
		out[-1] = tip - dir * width * 0.8
		_tri_strip(out, width, ink)
		var nrm := Vector2(-dir.y, dir.x)
		var hs := width * 1.7
		var point := tip + dir * hs * 0.6
		_tri_quad(point, tip - dir * hs * 0.9 + nrm * hs, tip - dir * hs * 0.9 - nrm * hs, point, ink, ink, ink, ink)
	else:
		_tri_strip(out, width, ink)

# ---------------- split times (beside the clock) ----------------
const SPLITS := 3 ## splits per lap, the last at the line
const SPLIT_SHOW := 4.0 ## s a split stays up

## Marks the player's time at each third of the lap (and the lap at the line) and puts it up against the
## same split on the best lap of the session, like CMR's stage splits.
func _update_splits() -> void:
	if race.s.mode != "race":
		return # a stage has its own splits against the leader, a time trial its sectors (see _update_mode)
	var p := race.player
	var L := race.track.L
	if race.phase != "racing" or p.mode == "pit":
		_split_prev_s = p.s
		_split_lap = p.lap
		_split_marks = []
		return
	if p.lap != _split_lap:
		if _split_lap >= 0 and p.lap == _split_lap + 1 and p.last_lap != null and _split_marks.size() == SPLITS - 1:
			var t: float = p.last_lap
			_show_split(SPLITS - 1, t)
			if p.best_lap != null and is_equal_approx(float(p.best_lap), t):
				_split_ref = _split_marks + [t]
		_split_lap = p.lap
		_split_marks = []
	for k in range(_split_marks.size(), SPLITS - 1):
		var at := L * (k + 1) / SPLITS
		var moved := race.track.rel(p.s - _split_prev_s)
		if moved > 0.0 and moved < 80.0 and _split_prev_s < at and p.s >= at:
			var speed := maxf(1.0, absf(p.speed) if p.control == "free" else p.v)
			var t := race.race_time - p.lap_start - (p.s - at) / speed
			_split_marks.append(t)
			_show_split(k, t)
		break
	_split_prev_s = p.s

func _show_split(k: int, t: float) -> void:
	var delta = t - float(_split_ref[k]) if _split_ref.size() == SPLITS else null
	_split_show = {"k": k, "t": t, "delta": delta, "until": race.race_time + SPLIT_SHOW}

func _draw_splits() -> void:
	if not race or _split_show.is_empty() or race.race_time > _split_show.until or warp > 1:
		return
	var W := splitbox.size.x
	var fade := clampf((_split_show.until - race.race_time) / 0.4, 0.0, 1.0)
	_gbar(splitbox, Rect2(0, 0, W, 44), Color(BAR_HI, BAR_HI.a * fade), Color(BAR_LO, BAR_LO.a * fade))
	var label := "LAP" if _split_show.k == SPLITS - 1 else "SPLIT %d" % (_split_show.k + 1)
	_text(splitbox, Vector2(12, 17), label, 11, Color(CmrStyle.INK_SOFT, fade), true)
	_text(splitbox, Vector2(12, 37), Race.fmt_time(_split_show.t), 18, Color(INK, fade), true)
	if _split_show.delta != null:
		var d: float = _split_show.delta
		_text(splitbox, Vector2(0, 37), "%s%.2f" % ["+" if d >= 0.0 else "−", absf(d)], 18, Color(RED if d >= 0.0 else PURPLE, fade), true, HORIZONTAL_ALIGNMENT_RIGHT, W - 12)

func _draw_lights() -> void:
	pass # no HUD start lights: the 3D gantry lamps are the start sequence

## Race control's flag for the player: a coloured board under the pace notes.
func _draw_flag() -> void:
	if not race or not race.rc or race.phase != "racing":
		return
	var f: Dictionary = _flag
	if f.is_empty():
		return
	var W := flagbar.size.x
	var col: Color = f.color
	var title: String = f.title
	# the safety-car boards flash like the marshals' lights
	var flash := title.begins_with("SAFETY CAR") or title == "DOUBLE YELLOW"
	var a := 0.72 + 0.28 * absf(cos(_clock * PI * 1.5)) if flash else 1.0
	flagbar.draw_rect(Rect2(0, 0, W, 54), _shade(0.72))
	flagbar.draw_rect(Rect2(0, 0, 62, 54), Color(col, a))
	if title == "DOUBLE YELLOW":
		flagbar.draw_rect(Rect2(31, 0, 2, 54), Color(0, 0, 0, 0.5))
	flagbar.draw_rect(Rect2(62, 0, W - 62, 3), Color(col, a))
	_text(flagbar, Vector2(74, 25), _fit(title, 20, W - 84), 20, col.lightened(0.1) if col.get_luminance() > 0.3 else TEXT, true)
	flagbar.draw_string(_font, Vector2(74, 44), f.sub, HORIZONTAL_ALIGNMENT_LEFT, W - 84, 12, TEXT) # clipped to the board

func _update_banner() -> void:
	var p := race.player
	var tr := race.track
	var big := ""
	var small := ""
	var box := false
	if skip_note != "":
		big = "Simulating the rest of the race…"
		small = skip_note
	elif race.phase == "countdown":
		if race.s.qualifying:
			big = "QUALIFYING"
			small = "An out lap to warm the tyres, then %d timed lap%s — the fastest sets your grid slot" % [race.R - 1, "s" if race.R > 2 else ""]
	elif race.race_time < 1.5:
		pass # the start lights carry READY / GO
	elif race.s.qualifying and p.finished:
		big = "QUALIFYING COMPLETE"
	elif race.s.qualifying and p.lap == 0 and race.race_time < 5.0:
		big = "OUT LAP"
		small = "Warm the tyres — the timed laps start at the line"
	elif race.s.qualifying and p.lap >= 1 and race.race_time - p.lap_start < 3.0 and not p.dnf:
		big = "TIMED LAP %d / %d" % [mini(p.lap, race.R - 1), race.R - 1]
		small = "Last lap %s" % Race.fmt_time(p.last_lap) if p.lap > 1 else "Push!"
	elif p.dnf and p.wrecked:
		big = "CRASHED OUT"
		small = "Enter / Ⓐ — skip to results"
	elif p.dnf:
		big = "RETIRED"
		small = "Enter / Ⓐ — skip to results"
	elif p.finished:
		if p.pos == 1:
			big = "VICTORY! P1"
			small = "Winner! Enter / Ⓐ — skip to results"
		elif p.pos <= 3:
			big = "PODIUM! P%d" % p.pos
			small = "Top 3 Finish! Enter / Ⓐ — skip to results"
		else:
			big = "FINISHED P%d" % p.pos
			small = "Enter / Ⓐ — skip to results"
	elif p.mode == "pit" and p.pit and p.pit.phase == "service":
		big = "PIT STOP %.1f s" % p.pit.left
	elif p.out_of_fuel:
		big = "OUT OF FUEL"
	elif p.pit_request:
		big = "BOX  BOX"
		box = true
	elif p.control == "free" and absf(p.speed) > 3.0 and cos(p.heading - tr.heading(p.s)) < -0.35:
		big = "WRONG WAY"
		small = "Turn around! Or press Backspace / R to reset car"
	elif p.control == "free" and (absf(p.d) > tr.half + 1.2 or p.stuck_t > 0.8) and absf(p.speed) < 3.5:
		big = "OFF TRACK"
		small = "Press Backspace or R to reset car to track"
	# the autopilot / time warp note has its own chip at the bottom (_draw_status): over the middle of the
	# screen it covered the name tags of the cars ahead
	_status_text = ""
	if p.autopilot and not p.finished and not p.dnf:
		_status_text = "CO-DRIVER  ·  TIME ×%d  ( , . )" % warp if warp > 1 else "AUTOPILOT  ·  O"
	if race.s.qualifying and p.lap >= 1 and p.invalid_lap and small == "" and not p.finished:
		small = "LAP INVALID — you left the track"
	banner.text = big
	banner_small.text = small
	var is_alert := big in ["WRONG WAY", "OFF TRACK"]
	var is_victory := big.begins_with("VICTORY")
	var is_podium := big.begins_with("PODIUM")
	var col := RED if is_alert else (CmrStyle.AMBER if is_victory else (Color("#38bdf8") if is_podium else (YELLOW if box else TEXT)))
	banner.add_theme_color_override("font_color", col)
	if is_alert:
		banner_small.add_theme_color_override("font_color", CmrStyle.ORANGE_SOFT)
	else:
		banner_small.add_theme_color_override("font_color", CmrStyle.MUTED)
	# BOX BOX and alerts blink (by fading, so the stack under the pace notes keeps its place)
	banner.modulate.a = 1.0 if (not box and not is_alert) or fmod(_clock, 0.7) < 0.42 else 0.0

func _update_event_sounds() -> void:
	for e in race.events:
		if e.id <= _event_seen:
			continue
		_event_seen = e.id
		if not audio:
			continue
		if e.kind == "box":
			audio.beep(880.0, 2)
		elif e.kind == "good":
			audio.beep(660.0, 1)
		elif e.kind == "rc":
			audio.beep(990.0, 1)
	# a new flag from race control: three quick beeps
	var f: String = race.rc.flag if race.rc else "green"
	if f != _last_flag:
		if audio and _last_flag != "":
			audio.beep(990.0, 3)
		_last_flag = f

# ---------------- event feed ----------------
func _feed_events() -> Array:
	if _feed_cache_n != race.events.size() or _feed_cache.is_empty() and race.events.size() > 0:
		_feed_cache_n = race.events.size()
		_feed_cache = race.events.filter(func(e): return not str(e.text).begins_with("Grid set"))
	return _feed_cache

func _draw_feed() -> void:
	if not race:
		return
	var now := race.clock
	var first := _feed_events().size()
	var shown := 0
	while first > 0 and shown < 6 and now - _feed_events()[first - 1].t < 10.0:
		first -= 1
		shown += 1
	var y := 0.0
	# newest at the bottom: drop the oldest that would run past the feed's box (it stops above the dash)
	while first < _feed_events().size():
		var total := 0.0
		for i in range(first, _feed_events().size()):
			total += _font.get_multiline_string_size(_feed_events()[i].text, HORIZONTAL_ALIGNMENT_LEFT, FEED_W - 23.0, 13).y + 14.0
		if total <= feed.size.y + 4.0:
			break
		first += 1
	for i in range(first, _feed_events().size()):
		var e: Dictionary = _feed_events()[i]
		var fade := minf(1.0, (10.0 - (now - e.t)) / 2.0)
		var h := _font.get_multiline_string_size(e.text, HORIZONTAL_ALIGNMENT_LEFT, FEED_W - 23.0, 13).y + 10.0
		_gbar(feed, Rect2(0, y, FEED_W, h), Color(BAR_LO, BAR_LO.a * fade), Color(BAR_HI, BAR_HI.a * fade))
		feed.draw_rect(Rect2(FEED_W - 5, y, 5, h), Color(FEED_BORDER.get(e.kind, Color("#666666")), fade))
		feed.draw_multiline_string(_bold, Vector2(10, y + 18), e.text, HORIZONTAL_ALIGNMENT_RIGHT, FEED_W - 23.0, 13, -1, Color(INK, fade))
		y += h + 4.0
	_feed_h = y

func _service() -> Variant:
	var p := race.player
	if p.service:
		return p.service
	if p.mode == "race" and not p.finished and not p.dnf:
		return race.default_service(p)
	return null

func _pitwall_height() -> float:
	return 8.0 + 30.0 + 30.0 + (24.0 if _damage_row() else 0.0) + 24.0 + 22.0 + (22.0 if _service() else 0.0) + 6.0

## The car's damage and the stewards' time penalties get a row on the pit wall once there are any.
func _damage_row() -> bool:
	var p := race.player
	return race.rc != null and (p.damage > 0.01 or p.penalty > 0.0)

## Whether the pit wall has anything to say: a race with a stop planned or required, a box requested, or the car in the pits.
func _pit_relevant() -> bool:
	if not race or race.s.qualifying or race.s.mode != "race":
		return false
	var p := race.player
	if p.finished or p.dnf:
		return false
	return p.pit_request or p.mode == "pit" or race.player_next_stop_lap() > 0 or (race.rules.mandatory_stop and p.stops == 0)

func _draw_pitwall() -> void:
	if not race:
		return
	var p := race.player
	var w := race.weather
	var W := PITWALL_W
	_tri_rect(Rect2(0, 0, W, pitwall.size.y), _plate(0.7))
	_tri_rect(Rect2(0, 0, 3, pitwall.size.y), YELLOW)
	var x := 12.0
	var y := 8.0
	# tyres: badge, compound and wear, laps left, wear bar
	var t: Dictionary = p.tyre
	var per_lap: float = race.track.L * race.tyres.wear_per_metre(t.c, w.wet, race.s.wear_mult)
	var tyre_laps: float = t.wear / per_lap if per_lap > 0.0 else 0.0
	_q_badge(Vector2(x + 10, y + 12), t.c, true)
	var tx := x + 30.0
	_q(Vector2(tx, y + 12), "%s  %d%%" % [race.tyres.compounds[t.c].display_name, roundi(t.wear * 100.0)], 13, TEXT, _bold)
	_q(Vector2(tx, y + 12), "≈%.1f laps" % tyre_laps, 11, MUTED, _font, HORIZONTAL_ALIGNMENT_RIGHT, W - 12 - tx)
	_tri_meter(Rect2(tx, y + 19, W - 12 - tx, 5), t.wear, RED if t.wear < 0.25 else (YELLOW if t.wear < 0.5 else GOOD))
	y += 30.0
	# fuel
	var fpl := race.car_fpl(p) * p.mix_fuel
	var margin := race.fuel_margin(p)
	var m_col := RED if margin < 0.0 else (YELLOW if margin < fpl * 0.3 else GOOD)
	_q(Vector2(x, y + 12), "FUEL", 11, MUTED, _bold)
	_q(Vector2(tx, y + 12), "%.1f L" % p.fuel, 13, TEXT, _bold)
	_q(Vector2(tx, y + 12), "%s · %+.1f L" % [Strategy.MIXES[p.mix].name.to_upper(), margin], 11, m_col, _font, HORIZONTAL_ALIGNMENT_RIGHT, W - 12 - tx)
	_tri_meter(Rect2(tx, y + 19, W - 12 - tx, 5), p.fuel / race.spec.tank, BLUE)
	y += 30.0
	if _damage_row():
		var pen := "PENALTY +%d s" % roundi(p.penalty) if p.penalty > 0.0 else ""
		if p.damage > 0.01:
			var dcol := RED if p.damage >= RaceControl.REPAIR_AT else (YELLOW if p.damage > 0.12 else TEXT)
			_q(Vector2(x, y + 12), "DMG", 11, MUTED, _bold)
			_q(Vector2(tx, y + 12), "%d%%" % roundi(p.damage * 100.0), 13, dcol, _bold)
			_q(Vector2(tx, y + 12), "≈%.0f s" % race.rc.repair_time(p) + ("  ·  " + pen if pen != "" else ""), 11, MUTED, _font, HORIZONTAL_ALIGNMENT_RIGHT, W - 12 - tx)
			_tri_meter(Rect2(tx, y + 17, W - 12 - tx, 4), p.damage, dcol)
		else:
			_q(Vector2(x, y + 12), pen, 12, YELLOW, _bold)
		y += 24.0
	# the plan: done stints fade, the current one is outlined
	var from := maxi(0, p.stint_idx - 2)
	var cx := x
	if from > 0:
		_q(Vector2(cx, y + 15), "+%d" % from, 11, Color(MUTED, 0.6), _font)
		cx += 22.0
	for k in range(from, mini(p.plan.size(), from + 8)):
		var st: Dictionary = p.plan[k]
		var chip_w := 26.0 + _text_w(str(st.laps), 12, true)
		if cx + chip_w > W - 12:
			break
		var done := k < p.stint_idx
		var chip := Rect2(cx, y + 2, chip_w, 19)
		_tri_rect(chip, Color(CHIP_BG, 0.45 if done else 1.0))
		if k == p.stint_idx:
			_tri_frame(chip, YELLOW)
		_q_badge(Vector2(cx + 10, y + 11.5), st.c)
		_q(Vector2(cx + 21, y + 16), str(st.laps), 12, Color(TEXT, 0.45 if done else 1.0))
		cx += chip_w + 4.0
	y += 24.0
	# status line
	var status := ""
	var status_col := TEXT
	var next_stop := race.player_next_stop_lap()
	if p.mode == "pit" and p.pit:
		if p.pit.phase == "in":
			status = "Pit lane, limiter 60 km/h"
		elif p.pit.phase == "red":
			status = "Red flag, queue at the pit exit"
			status_col = RED
		elif p.pit.phase == "service":
			status = "Crew working %.1f / %.1f s" % [p.pit.total - p.pit.left, p.pit.total]
		else:
			status = "Released, pit exit ahead"
	elif p.pit_request:
		status = "BOX THIS LAP"
		status_col = YELLOW
	elif next_stop > 0:
		if next_stop == p.lap + 1:
			status = "Box this lap (P to confirm)"
			status_col = YELLOW
		else:
			status = "Box after lap %d  ·  P = request" % next_stop
	else:
		status = "Stop required  ·  P = request"
	_q(Vector2(x, y + 13), status, 12, status_col, _bold)
	y += 22.0
	var sv = _service()
	if sv:
		var sx := x
		_q(Vector2(sx, y + 12), "Stop:", 11, MUTED, _font)
		sx += _text_w("Stop: ", 11)
		var tyre_txt := "keep tyres"
		if sv.c:
			_q_badge(Vector2(sx + 8, y + 8), sv.c)
			sx += 20.0
			tyre_txt = race.tyres.compounds[sv.c].display_name
		var rest := tyre_txt
		if race.rules.refuel:
			rest += " · +%.1f L" % sv.litres
		rest += " · ≈%.1f s" % sv.time
		_q(Vector2(sx, y + 12), rest, 11, TEXT, _font)
	_tri_flush(pitwall)
	_flush_badges(pitwall)
	_q_flush(pitwall)

# ---------------- dash ----------------
# ---------------- dash (bottom right) ----------------
## CMR 2.0 rev counter: slanted segments rising along a curve (cyan, amber near the top, red at the
## limiter), rpm figures underneath, the gear as one big digit and the speed beside it.
const DASH_SEGMENTS := 26

## What the dash shows: [size, segments lit, gear, km/h]. It is only redrawn when this changes.
func _dash_state() -> Array:
	if not race:
		return []
	var p := race.player
	var kmh := roundi(absf(p.speed) * 3.6)
	var gear := str(p.gear + 1)
	if p.rev or p.speed < -0.3:
		gear = "R"
	elif kmh < 1 and p.control == "free" and p.throttle < 0.05:
		gear = "N"
	var frac := clampf(p.rpm / race.spec.limiter, 0.0, 1.0)
	# segment i is lit while (i + 0.78) / n <= frac + 0.03
	var lit := clampi(floori((frac + 0.03) * DASH_SEGMENTS - 0.78) + 1, 0, DASH_SEGMENTS)
	var redline: bool = frac >= 0.91 and fmod(_clock * 12.0, 1.0) < 0.5
	var drafting: bool = p.tow > 0.18
	return [dash.size, lit, gear, kmh, redline, drafting]

## The rev band: slanted segments along a curve that rises and thickens toward the redline (CMR's swoosh).
func _build_dash(W: float, H: float) -> void:
	_dash_size = Vector2(W, H)
	var n := DASH_SEGMENTS
	var arc_w := W - 84.0
	var bottom := H - 8.0
	_dash_points = PackedVector2Array()
	_dash_colors = PackedColorArray()
	_dash_indices = PackedInt32Array()
	for i in n:
		var t0 := float(i) / n
		var t1 := (i + 0.78) / n
		var p0 := Vector2(arc_w * t0, bottom - 96.0 * pow(t0, 2.6))
		var p1 := Vector2(arc_w * t1, bottom - 96.0 * pow(t1, 2.6))
		var d := (p1 - p0).normalized()
		var up := Vector2(d.y, -d.x)
		var poly := PackedVector2Array([p0, p1, p1 + up * (10.0 + 22.0 * t1), p0 + up * (10.0 + 22.0 * t0)])
		var k := _dash_points.size()
		_dash_points.append_array(poly)
		for j in 4:
			_dash_colors.append(Color.WHITE)
		_dash_indices.append_array(PackedInt32Array([k, k + 1, k + 2, k, k + 2, k + 3]))

func _draw_dash() -> void:
	if not race:
		return
	var W := dash.size.x
	var H := dash.size.y
	var state := _dash_state()
	var lit: int = state[1]
	var redline: bool = state[4] if state.size() > 4 else false
	var drafting: bool = state[5] if state.size() > 5 else false

	if _dash_size != dash.size:
		_build_dash(W, H)
	var n := DASH_SEGMENTS
	for i in n:
		var t0 := float(i) / n
		var col := Color(CmrStyle.TEXT, 0.2)
		if i < lit:
			if redline and t0 >= 0.85:
				col = Color.WHITE
			else:
				col = RED if t0 >= 0.9 else (YELLOW if t0 >= 0.78 else BLUE)
		for j in 4:
			_dash_colors[i * 4 + j] = col
	RenderingServer.canvas_item_add_triangle_array(dash.get_canvas_item(), _dash_indices, _dash_points, _dash_colors)

	# the speed sits above the low end of the swoosh, the gear in the column its high end leaves free
	_q(Vector2(0, 74), "%d" % state[3], 88, TEXT, _digits, HORIZONTAL_ALIGNMENT_LEFT, W - 90, true)
	_q(Vector2(0, 100), "KM/H", 17, MUTED, _bold, HORIZONTAL_ALIGNMENT_LEFT, 80, true)
	var gear_col := RED if redline else (YELLOW if state[2] != "N" else MUTED)
	_q(Vector2(W - 84, H - 22), state[2], 72, gear_col, _bold, HORIZONTAL_ALIGNMENT_CENTER, 84, true)
	_q(Vector2(W - 84, H - 94), "GEAR", 12, MUTED, _bold, HORIZONTAL_ALIGNMENT_CENTER, 84, true)

	if drafting:
		_q(Vector2(0, 16), "SLIPSTREAM", 12, BLUE, _bold, HORIZONTAL_ALIGNMENT_RIGHT, W, true)

	_q_flush(dash)

func _build_map() -> void:
	var tr := race.track
	_map_track = tr
	_map_size = minimap.size
	var b := tr.bounds
	var pad := 12.0
	_map_scale = minf((_map_size.x - 2.0 * pad) / (b[2] - b[0]), (_map_size.y - 2.0 * pad) / (b[3] - b[1]))
	_map_origin = Vector2((_map_size.x - (b[2] - b[0]) * _map_scale) * 0.5 - b[0] * _map_scale,
		(_map_size.y - (b[3] - b[1]) * _map_scale) * 0.5 - b[1] * _map_scale)
	_map_points = PackedVector2Array()
	var stride := maxi(1, tr.n / 320)
	for i in range(0, tr.n, stride):
		_map_points.append(Vector2(tr.X[i], tr.Y[i]) * _map_scale + _map_origin)
	_map_points.append(_map_points[0])
	var p0 := tr.pos(0.0, 0.0)
	var n0 := tr.pos(0.0, tr.half * 3.0)
	var a := Vector2(p0[0], p0[1])
	var n := Vector2(n0[0], n0[1])
	_map_start = PackedVector2Array([(2.0 * a - n) * _map_scale + _map_origin, n * _map_scale + _map_origin])
	_map_waters.clear()
	_map_buildings.clear()
	if tr.cfg:
		var env_path := "res://data/tracks/%s_env.json" % tr.cfg.key
		if FileAccess.file_exists(env_path):
			var env_json = JSON.parse_string(FileAccess.get_file_as_string(env_path))
			if typeof(env_json) == TYPE_DICTIONARY:
				for w in env_json.get("water", []):
					var pts := PackedVector2Array()
					for k in range(0, w.size() - 1, 2):
						pts.append(Vector2(w[k], w[k + 1]) * _map_scale + _map_origin)
					if pts.size() >= 3:
						_map_waters.append(pts)
				for b_entry in env_json.get("buildings", []):
					var pts := PackedVector2Array()
					for k in range(3, b_entry.size() - 1, 2):
						pts.append(Vector2(b_entry[k], b_entry[k + 1]) * _map_scale + _map_origin)
					if pts.size() >= 3:
						_map_buildings.append(pts)

## What minimap_base shows: the circuit, the map's size and the flags along it.
func _minimap_key() -> String:
	if not race:
		return ""
	var key := "%d:%s" % [race.track.get_instance_id(), minimap.size]
	var rc := race.rc
	if rc:
		key += ":%s:%d" % [rc.flag, hash(rc.yellow)]
	return key

## The map's backdrop, the circuit and its flagged sectors; the cars go on minimap over it.
func _draw_minimap_base() -> void:
	if not race:
		return
	_map_key = _minimap_key()
	var rect := Rect2(Vector2.ZERO, minimap_base.size)
	minimap_base.draw_rect(rect, _plate(0.72))
	minimap_base.draw_rect(Rect2(0, 0, rect.size.x, 2), Color(CmrStyle.VIOLET, 0.7))
	if _map_track != race.track or _map_size != minimap.size:
		_build_map()
	for w in _map_waters:
		minimap_base.draw_colored_polygon(w, Color(0.18, 0.45, 0.72, 0.45))
	for b_poly in _map_buildings:
		minimap_base.draw_colored_polygon(b_poly, Color(0.42, 0.48, 0.58, 0.22))
	_tri_strip(_map_points, 7.0, _shade(0.8), true)
	_tri_strip(_map_points, 3.2, Color("#e8f2ff"), true)
	_tri_strip(_map_start, 3.0, RED)
	if race.rc:
		_draw_map_flags(race.rc)
	_tri_flush(minimap_base)

func _draw_minimap() -> void:
	if not race:
		return
	if _map_track != race.track or _map_size != minimap.size:
		_build_map()
	var rc := race.rc
	var p := race.player
	# all the dots, then all their rims: two batched draws instead of two per car
	var dots: Array = [] ## [centre, colour]
	for car in race.cars:
		if car.stranded and not car.recovered:
			var wp := Vector2(car.x, car.y) * _map_scale + _map_origin
			minimap.draw_line(wp - Vector2(3.5, 3.5), wp + Vector2(3.5, 3.5), RED, 2.0, true)
			minimap.draw_line(wp + Vector2(-3.5, 3.5), wp + Vector2(3.5, -3.5), RED, 2.0, true)
		if car.dnf or car == p:
			continue
		dots.append([Vector2(car.x, car.y) * _map_scale + _map_origin, car.color])
	for d in dots:
		_round(minimap, d[0], 3.2, d[1])
	for d in dots:
		_round(minimap, d[0], 3.7, Color(0, 0, 0, 0.7), 2.7 / 3.7)
	if not p.dnf:
		var pp := Vector2(p.x, p.y) * _map_scale + _map_origin
		_round(minimap, pp, 5.5, YELLOW)
		_round(minimap, pp, 6.5, Color.BLACK, 4.5 / 6.5)
		var fwd := Vector2(cos(p.heading), sin(p.heading)).normalized()
		var tip := pp + fwd * 10.0
		var wing1 := pp - fwd * 3.5 + Vector2(-fwd.y, fwd.x) * 4.5
		var wing2 := pp - fwd * 3.5 - Vector2(-fwd.y, fwd.x) * 4.5
		minimap.draw_colored_polygon(PackedVector2Array([tip, wing1, pp, wing2]), YELLOW)
		minimap.draw_polyline(PackedVector2Array([wing1, tip, wing2]), Color.BLACK, 1.5, true)
	if rc and rc.sc_state in ["out", "in"]:
		var sp := Vector2(rc.sc.x, rc.sc.y) * _map_scale + _map_origin
		var on := fmod(_clock, 0.5) < 0.25
		minimap.draw_rect(Rect2(sp - Vector2(4, 4), Vector2(8, 8)), Color("#ffd21a") if on else Color.WHITE)
		minimap.draw_rect(Rect2(sp - Vector2(4, 4), Vector2(8, 8)), Color.BLACK, false, 1.5)

## Yellow marshal sectors along the minimap line (the whole lap turns red under a red flag).
func _draw_map_flags(rc: RaceControl) -> void:
	var tr := race.track
	var step := maxf(15.0, tr.L / 320.0)
	for k in rc.n_sec:
		var lvl := 3 if rc.flag == "red" else rc.yellow[k]
		if lvl == 0:
			continue
		var col := RED if lvl == 3 else (Color("#ffd21a") if lvl == 2 else Color("#ffe98a"))
		var pts := PackedVector2Array()
		var s := k * rc.sec_len
		while s <= (k + 1) * rc.sec_len + 0.1:
			var q := tr.pos(s, 0.0)
			pts.append(Vector2(q[0], q[1]) * _map_scale + _map_origin)
			s += step
		if pts.size() >= 2:
			_tri_strip(pts, 4.0 if lvl == 2 else 3.2, col)

func _draw_tags() -> void:
	if not race or not is_instance_valid(world) or not world.camera:
		return
	var cam: Camera3D = world.camera
	var focus := race.player
	var shown := [] ## [distance to camera, car, screen point]
	for car in race.cars:
		if car == focus or car.dnf:
			continue
		var dx := car.x - focus.x
		var dy := car.y - focus.y
		if dx * dx + dy * dy > 90.0 * 90.0:
			continue
		var visual = world.visuals.get(car.id)
		if not visual or not visual.visible:
			continue
		var wp: Vector3 = visual.position + Vector3.UP * 2.1
		if cam.is_position_behind(wp):
			continue
		# the camera renders at window pixels; the HUD lives on the scaled design canvas
		var sp := cam.unproject_position(wp) * (size / Vector2(cam.get_viewport().size))
		shown.append([cam.global_position.distance_squared_to(wp), car, sp])
	# nearest first, so they keep their spot; a farther tag that would overlap one already placed moves up
	shown.sort_custom(func(a, b): return a[0] < b[0])
	var placed: Array[Rect2] = []
	for entry in shown:
		var car = entry[1]
		var sp: Vector2 = entry[2]
		var mark := ""
		if car.brain:
			mark = " »" if car.brain.mind == "attack" else (" «" if car.brain.mind == "defend" else "")
		var label := "P%d %s%s" % [car.pos, Brain.short(car), mark]
		var tw := _text_w(label, 11, true) + 14.0
		var r := Rect2(sp.x - tw * 0.5, sp.y - 14.0, tw, 16.0)
		var moved := true
		while moved:
			moved = false
			for other in placed:
				if r.intersects(other):
					r.position.y = other.position.y - 18.0
					moved = true
		# a tag never goes under (or over) a HUD panel or banner: it is left out while it would
		var hidden := false
		for area in _reserved:
			if r.intersects(area):
				hidden = true
				break
		placed.append(r)
		entry.append(label)
		entry.append(r)
		entry.append(hidden)
	# draw far to near so the nearer cars' tags end up on top
	for i in range(shown.size() - 1, -1, -1):
		if shown[i][5]:
			continue
		var car = shown[i][1]
		var label: String = shown[i][3]
		var r: Rect2 = shown[i][4]
		_tri_gbar(r, BAR_HI, Color(BAR_HI, 0.6))
		_tri_rect(Rect2(r.position, Vector2(4, 16)), car.color)
		_q(Vector2(r.position.x + 8.0, r.position.y + 12.0), label, 11, INK)
	_tri_flush(tags)
	_q_flush(tags)

# ---------------- rally stage and time trial ----------------
## Built to be read from the sofa: large type, solid dark plates, the colours that matter (purple a best,
## green ahead, red behind) as filled blocks rather than thin text.
const MODE_W := 380.0 ## mode panel width (top left, where the race's timing tower is)
const DELTA_W := 460.0 ## delta bar width (top centre, under the pace notes)
const MODE_SPLIT_SHOW := 5.0 ## s a rally split or a time-trial lap stays up in the delta bar
## Colours from the live skin (CmrStyle): purple a best, green ahead, red behind, on a dark plate.
var MODE_PLATE: Color:
	get: return Color(CmrStyle.PANEL.darkened(0.55), 0.84)
var AHEAD: Color:
	get: return CmrStyle.GREEN.darkened(0.25)
var BEHIND: Color:
	get: return CmrStyle.RED
var SECTOR_COLORS: Dictionary:
	get: return {"purple": CmrStyle.PURPLE.darkened(0.3), "green": CmrStyle.GREEN.darkened(0.35), "red": CmrStyle.RED.darkened(0.1),
		"invalid": Color(CmrStyle.MUTED.darkened(0.6), 0.9), "none": Color(1, 1, 1, 0.12)}
const TT_RESTART_HINT := "T / Ⓨ  RESTART"

func _mt(c: Control, at: Vector2, s: String, size: int, col: Color, font: Font = null, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	_audit_text(c, font if font else _bold, at, s, align, width, size)
	c.draw_string(font if font else _bold, at, s, align, width, size, col)

static func _signed(x: float) -> String:
	return "%s%.2f" % ["+" if x >= 0.0 else "−", absf(x)]

## Splits passed (rally) and laps closed (time trial) come up in the delta bar for a few seconds.
func _update_mode() -> void:
	if race.stage:
		var n: int = race.stage.split_times.size()
		if n > _mode_seen:
			_mode_seen = n
			_mode_split = race.stage.last_split()
			_mode_split["until"] = _clock + MODE_SPLIT_SHOW
			if is_instance_valid(audio) and not audio.muted:
				var g = _mode_split.get("gap")
				audio.beep(1046.5 if g == null or g <= 0.0 else 660.0, 1)
	elif race.tt:
		var n: int = race.tt.laps.size()
		if n > _mode_seen:
			_mode_seen = n
			_mode_split = {"lap": race.tt.laps[-1], "until": _clock + MODE_SPLIT_SHOW}

## The right-hand clock for a stage or a time trial: progress, the big time, then a few rows.
func _draw_mode_clock() -> void:
	var p := race.player
	var W := CLOCK_W
	var x0 := clock.size.x - W
	var st := race.stage
	var tt := race.tt
	var frac := 0.0
	if race.phase == "racing" or (st and st.time != null):
		frac = clampf(st.progress / st.length, 0.0, 1.0) if st else clampf(p.s / race.track.L, 0.0, 1.0)
		if st and st.time != null:
			frac = 1.0
	var segs := 12
	var sw := (W - (segs - 1) * 3.0) / segs
	for k in segs:
		var r := Rect2(x0 + k * (sw + 3.0), 0, sw, 12)
		var fill := clampf(frac * segs - k, 0.0, 1.0)
		_tri_rect(r, _plate(0.55))
		if fill > 0.0:
			_tri_rect(Rect2(r.position, Vector2(r.size.x * fill, r.size.y)), YELLOW)
		_tri_frame(r, Color(1, 1, 1, 0.35))
	var label := ""
	var time_text := ""
	var rows := []
	if st:
		var n: int = st.event.stage_count() if st.event else 0
		label = ("STAGE %d / %d" % [st.index + 1, n]) if st.event else "STAGE"
		time_text = Race.fmt_time(st.elapsed())
		var pen := st.penalty()
		rows.append(["PENALTY", "+%d s" % roundi(pen) if pen > 0.0 else "—", RED if pen > 0.0 else INK])
		if st.event:
			var before: int = st.event.player_position() if st.event.results.size() else 0
			rows.append(["OVERALL", "P%d / %d" % [before, st.event.rivals.size() + 1] if before > 0 else "—", INK])
		var lead := st.leader_at(Rally.SPLITS)
		rows.append(["STAGE BEST", Race.fmt_time(lead.t) if not lead.is_empty() else "—", INK])
		rows.append(["DAMAGE", "%d %%" % roundi(p.damage * 100.0), RED if p.damage >= REPAIR_AT_HUD else INK])
	else:
		label = "ROLLING START" if tt.out_lap() else "LAP %d" % (tt.laps.size() + 1)
		time_text = Race.fmt_time(maxf(0.0, race.race_time - p.lap_start)) if race.phase == "racing" and not tt.out_lap() else "0:00.000"
		var last = tt.laps[-1] if tt.laps.size() else null
		rows.append(["LAST", ("INVALID" if not last.valid else Race.fmt_time(last.time)) if last else "—", (RED if not last.valid else INK) if last else INK])
		rows.append(["BEST", Race.fmt_time(tt.best_lap), PURPLE if tt.best_lap != null else INK])
		rows.append(["IDEAL", Race.fmt_time(tt.ideal_lap()), INK])
		rows.append(["RECORD", Race.fmt_time(tt.record_time), INK])
	var box := Rect2(x0, 18, W, 64)
	var box_style := CmrStyle.box(BAR_HI, Color.TRANSPARENT, 0, 0)
	box_style.border_color = Color(1, 1, 1, 0.9)
	box_style.border_width_top = 2
	box_style.draw(clock.get_canvas_item(), box)
	_q(Vector2(x0 + 14, 36), label, 13, CmrStyle.INK_SOFT, _bold)
	_q(Vector2(x0, 74), time_text, 42, INK, _digits, HORIZONTAL_ALIGNMENT_RIGHT, W - 16)
	var y := 88.0
	for row in rows:
		_tri_gbar(Rect2(x0 + 30, y, W - 30, 26), Color(BAR_HI, 0.6), BAR_HI)
		_q(Vector2(x0 + 44, y + 19), row[0], 13, CmrStyle.INK_SOFT, _bold)
		_q(Vector2(x0 + 60, y + 20), row[1], 18, row[2], _bold, HORIZONTAL_ALIGNMENT_RIGHT, W - 72)
		y += 29.0
	_tri_flush(clock)
	_q_flush(clock)

## Top left: the stage's splits against the leader and the overall standings, or the time trial's sectors
## and lap list.
func _draw_mode_panel() -> void:
	if not race or race.s.mode == "race":
		return
	if race.stage:
		_draw_stage_panel()
	elif race.tt:
		_draw_tt_panel()

func _draw_stage_panel() -> void:
	var c := modepanel
	var st := race.stage
	var W := MODE_W
	var ev = st.event
	c.draw_rect(Rect2(0, 0, W, 64), MODE_PLATE)
	c.draw_rect(Rect2(0, 0, 6, 64), YELLOW)
	var head := "SS%d" % (st.index + 1) if ev else "SPECIAL STAGE"
	if ev:
		head += "  ·  %s" % str(ev.def.get("short", ev.def.get("name", "")))
	_mt(c, Vector2(18, 28), _fit(head, 22, W - 30), 22, TEXT)
	var sname: String = ev.stage_def(st.index).get("name", "") if ev and st.index >= 0 and st.index < ev.stage_count() else race.track.name
	var surf := " · GRAVEL" if race.s.surface == "gravel" else ""
	_mt(c, Vector2(18, 54), _fit(sname.to_upper() + surf, 16, W - 30), 16, MUTED)
	var y := 72.0
	# splits: time, gap to the stage leader there, stage position
	for k in Rally.SPLITS + 1:
		var passed := k < st.split_times.size()
		c.draw_rect(Rect2(0, y, W, 40), MODE_PLATE)
		_mt(c, Vector2(14, y + 28), "FINISH" if k == Rally.SPLITS else "SPLIT %d" % (k + 1), 17, MUTED)
		var lead := st.leader_at(k)
		if passed:
			var t: float = st.split_times[k] + (st.penalty() if k == Rally.SPLITS else 0.0)
			var ts := Race.fmt_time(t)
			# a long stage's time steps down a size rather than run into the gap box beside it
			var tfs := 22 if _digits.get_string_size(ts, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x <= W - 150 - 116 else 18
			_mt(c, Vector2(110, y + 29), ts, tfs, TEXT, _digits)
			if not lead.is_empty():
				var gap := t - float(lead.t)
				c.draw_rect(Rect2(W - 150, y + 5, 92, 30), AHEAD if gap <= 0.0 else BEHIND)
				_mt(c, Vector2(W - 150, y + 28), _signed(gap), 20, Color.WHITE, _bold, HORIZONTAL_ALIGNMENT_CENTER, 92)
			_mt(c, Vector2(W - 54, y + 29), "P%d" % st.rank_at(k, t), 20, YELLOW, _bold, HORIZONTAL_ALIGNMENT_RIGHT, 44)
		elif not lead.is_empty():
			_mt(c, Vector2(110, y + 28), "leader %s" % Race.fmt_time(lead.t), 17, Color(TEXT, 0.55))
		y += 43.0
	if not st.penalties.is_empty():
		c.draw_rect(Rect2(0, y, W, 34), Color(BEHIND, 0.85))
		var why := ", ".join(st.penalties.map(func(x): return str(x[0])))
		_mt(c, Vector2(14, y + 24), _fit("PENALTY +%d s  %s" % [roundi(st.penalty()), why], 17, W - 24), 17, Color.WHITE)
		y += 38.0
	# overall before this stage: the top five and the player
	if ev and ev.results.size() > 0:
		c.draw_rect(Rect2(0, y, W, 30), Color(YELLOW, 0.9))
		_mt(c, Vector2(14, y + 22), "OVERALL AFTER SS%d" % ev.results.size(), 16, INK)
		y += 32.0
		var table: Array = ev.standings()
		var shown := 0
		for row in table:
			if shown >= 5 and not row.is_player:
				continue
			c.draw_rect(Rect2(0, y, W, 30), Color(YELLOW, 0.35) if row.is_player else MODE_PLATE)
			_mt(c, Vector2(8, y + 22), str(row.pos), 18, TEXT, _bold, HORIZONTAL_ALIGNMENT_RIGHT, 28)
			c.draw_rect(Rect2(44, y + 6, 5, 18), row.color)
			var nm: String = str(row.name) if row.is_player else str(row.name).split(" ")[-1]
			_mt(c, Vector2(58, y + 22), _fit(nm.to_upper(), 17, 170), 17, TEXT)
			_mt(c, Vector2(W - 150, y + 22), Race.fmt_time(row.time) if row.pos == 1 else "+%.1f" % row.gap, 17, TEXT, _bold, HORIZONTAL_ALIGNMENT_RIGHT, 140)
			y += 32.0
			shown += 1
			if shown >= 6:
				break

func _draw_tt_panel() -> void:
	var c := modepanel
	var tt := race.tt
	var W := MODE_W
	c.draw_rect(Rect2(0, 0, W, 64), MODE_PLATE)
	c.draw_rect(Rect2(0, 0, 6, 64), PURPLE)
	_mt(c, Vector2(18, 28), "TIME TRIAL", 22, TEXT)
	_mt(c, Vector2(18, 54), _fit(race.track.name.to_upper(), 16, W - 30), 16, MUTED)
	var y := 72.0
	# this lap's sectors as coloured blocks; the session's best of each underneath
	var bw := (W - 2 * 6.0) / 3.0
	var now: Array = tt.sectors_now
	var cols: Array = tt.current_colors()
	for k in TimeTrial.SECTORS:
		var r := Rect2(k * (bw + 6.0), y, bw, 58)
		var col: Color = SECTOR_COLORS[cols[k]] if k < cols.size() else SECTOR_COLORS.none
		c.draw_rect(r, MODE_PLATE)
		c.draw_rect(r, col)
		_mt(c, Vector2(r.position.x + 8, y + 20), "S%d" % (k + 1), 15, Color(1, 1, 1, 0.85))
		var t = now[k] if k < now.size() else null
		_mt(c, Vector2(r.position.x, y + 48), "%.2f" % t if t != null else "—", 24, Color.WHITE, _digits, HORIZONTAL_ALIGNMENT_CENTER, bw)
		var best = tt.best_sectors[k]
		_mt(c, Vector2(r.position.x, y + 78), "best %.2f" % best if best != null else "", 15, MUTED, _bold, HORIZONTAL_ALIGNMENT_CENTER, bw)
	y += 92.0
	if not tt.valid and not tt.out_lap():
		c.draw_rect(Rect2(0, y, W, 34), Color(BEHIND, 0.9))
		_mt(c, Vector2(0, y + 25), "LAP INVALID — OFF THE TRACK", 18, Color.WHITE, _bold, HORIZONTAL_ALIGNMENT_CENTER, W)
		y += 38.0
	# the lap list, newest first
	c.draw_rect(Rect2(0, y, W, 28), Color(PURPLE, 0.85))
	_mt(c, Vector2(14, y + 21), "LAPS", 16, Color.WHITE)
	_mt(c, Vector2(0, y + 21), TT_RESTART_HINT, 14, Color.WHITE, _bold, HORIZONTAL_ALIGNMENT_RIGHT, W - 12)
	y += 30.0
	var n: int = tt.laps.size()
	for i in range(n - 1, maxi(-1, n - 9), -1):
		var lap: Dictionary = tt.laps[i]
		var best: bool = lap.valid and tt.best_lap != null and is_equal_approx(float(lap.time), float(tt.best_lap))
		c.draw_rect(Rect2(0, y, W, 30), Color(PURPLE, 0.45) if best else MODE_PLATE)
		_mt(c, Vector2(10, y + 22), "L%d" % lap.n, 17, MUTED)
		_mt(c, Vector2(64, y + 22), Race.fmt_time(lap.time), 19, TEXT if lap.valid else Color(TEXT, 0.45), _digits)
		if not lap.valid:
			_mt(c, Vector2(0, y + 22), "INVALID", 16, BEHIND, _bold, HORIZONTAL_ALIGNMENT_RIGHT, W - 10)
		else:
			for k in TimeTrial.SECTORS:
				c.draw_rect(Rect2(W - 96 + k * 30, y + 8, 24, 14), SECTOR_COLORS.get(lap.colors[k], SECTOR_COLORS.none))
		y += 32.0

## Top centre: the live delta to the best lap (time trial), or the split just passed against the stage
## leader (rally).
func _draw_delta_bar() -> void:
	if not race or race.s.mode == "race" or warp > 1:
		return
	var c := deltabar
	var W := c.size.x
	var showing := not _mode_split.is_empty() and _clock < float(_mode_split.until)
	if race.stage:
		if not showing:
			return
		var sp := _mode_split
		var gap = sp.get("gap")
		var col: Color = (AHEAD if gap <= 0.0 else BEHIND) if gap != null else Color(PURPLE, 0.9)
		c.draw_rect(Rect2(0, 0, W, 84), MODE_PLATE)
		c.draw_rect(Rect2(0, 0, W, 6), col)
		var lab := "FINISH" if sp.k == Rally.SPLITS else "SPLIT %d" % (sp.k + 1)
		_mt(c, Vector2(16, 34), lab, 20, MUTED)
		_mt(c, Vector2(16, 72), Race.fmt_time(sp.t), 30, TEXT, _digits)
		if gap != null:
			_mt(c, Vector2(0, 72), _signed(gap), 40, col, _digits, HORIZONTAL_ALIGNMENT_RIGHT, W - 96)
			_mt(c, Vector2(0, 72), "P%d" % sp.pos, 30, YELLOW, _bold, HORIZONTAL_ALIGNMENT_RIGHT, W - 14)
			_mt(c, Vector2(0, 34), "vs %s" % str(sp.leader).split(" ")[-1].to_upper(), 18, MUTED, _bold, HORIZONTAL_ALIGNMENT_RIGHT, W - 14)
		return
	var tt := race.tt
	if not tt:
		return
	if showing:
		var lap: Dictionary = _mode_split.lap
		var best: bool = lap.valid and tt.best_lap != null and is_equal_approx(float(lap.time), float(tt.best_lap))
		var col: Color = BEHIND if not lap.valid else (SECTOR_COLORS.purple if best else Color(TEXT, 0.6))
		c.draw_rect(Rect2(0, 0, W, 84), MODE_PLATE)
		c.draw_rect(Rect2(0, 0, W, 6), col)
		_mt(c, Vector2(16, 34), "LAP %d%s" % [lap.n, "  ·  INVALID" if not lap.valid else ("  ·  BEST LAP" if best else "")], 20, col if not lap.valid or best else MUTED)
		_mt(c, Vector2(0, 74), Race.fmt_time(lap.time), 40, TEXT, _digits, HORIZONTAL_ALIGNMENT_CENTER, W)
		return
	if tt.out_lap():
		c.draw_rect(Rect2(0, 0, W, 50), MODE_PLATE)
		_mt(c, Vector2(0, 34), "ROLLING START — GO FOR IT", 22, TEXT, _bold, HORIZONTAL_ALIGNMENT_CENTER, W)
		return
	var d = tt.live_delta()
	var vs := "vs BEST"
	if d == null and records:
		d = records.gap()
		vs = "vs RECORD"
	if d == null or race.phase != "racing":
		return
	# a bar from the centre: green to the left when ahead, red to the right when behind, full at ±2 s
	var col: Color = AHEAD if d <= 0.0 else BEHIND
	if not tt.valid:
		col = SECTOR_COLORS.invalid
	c.draw_rect(Rect2(0, 0, W, 84), MODE_PLATE)
	var half := W * 0.5 - 8.0
	var bar := clampf(absf(d) / 2.0, 0.0, 1.0) * half
	c.draw_rect(Rect2(W * 0.5 - (bar if d <= 0.0 else 0.0), 6, bar, 18), col)
	c.draw_rect(Rect2(W * 0.5 - 1.5, 2, 3, 26), Color.WHITE)
	_mt(c, Vector2(12, 74), vs, 18, MUTED)
	_mt(c, Vector2(0, 76), _signed(d), 44, col if tt.valid else Color(TEXT, 0.5), _digits, HORIZONTAL_ALIGNMENT_CENTER, W)
	if not tt.valid:
		_mt(c, Vector2(0, 74), "INVALID", 18, BEHIND, _bold, HORIZONTAL_ALIGNMENT_RIGHT, W - 12)
