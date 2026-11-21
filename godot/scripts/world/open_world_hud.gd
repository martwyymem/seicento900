## The open world's HUD, in the Forza Horizon manner: the turning satnav disc with the GPS route and the event
## markers, a big speedometer, the skill chain, discovery banners, the street you are on, the event card when
## you pull into a beacon, the full-screen map (M), the pause menu and the loading screen.
class_name OpenWorldHud
extends Control

signal pause_action(action: String)
signal map_target(index: int)
signal waypoint_picked(pos: Vector2) ## a click on the big map: the player's own route destination
signal map_accept ## a second click on the selected place: set the route to it, as Enter does

const MINIMAP_SHADER := preload("res://shaders/minimap.gdshader")
## Colours from the live UI skin (CmrStyle, Options / F1): the accent, the route, the reward highlight and
## the dark plate under cards and banners.
static var ORANGE: Color:
	get: return CmrStyle.ORANGE
static var PURPLE: Color:
	get: return CmrStyle.VIOLET
static var GOLD: Color:
	get: return CmrStyle.ORANGE_SOFT
static var INK: Color:
	get: return CmrStyle.INK
const EDGE := 30.0 ## margin from the canvas edge
const MINIMAP_S := 250.0
const SPEEDO_W := 320.0 ## bottom-right sweep dash width (fits clear of StoryCard and controls strip)
const SPEEDO_H := 184.0 ## 164 px sweep + DashGauge.NITRO_BAND underneath
const SPEEDO_RIGHT := 24.0 ## margin from the right edge
const SPEEDO_BOTTOM := 14.0 ## margin from the bottom edge
const BANNERS_W := 500.0
const CARD_W := 470.0
const TOWER_W := 250.0 ## the race timing list, top right (set_standings)
const TOWER_ROW := 24.0

var map: TownMap
var map_tex: Texture2D
var map_rect := Rect2() ## the map picture in map metres
var minimap: ColorRect
var minimap_mat: ShaderMaterial
var overlay: Control
var speedo: DashGauge
var corners_group: Control ## g-force sway container for corner panels (satnav, stats, timing list, event card)
var speedo_group: Control ## g-force sway container for the speedometer cluster (moves most)
var _corner_panels: Array[Control] = []
var _motion := HudMotion.new()
var big_map: ColorRect
var big_map_mat: ShaderMaterial
var big_overlay: Control
var map_open := false
var map_sel := 0
var nav: MapNav = MapNav.new() ## the big map's view, filters and list (zoom, pan, hop; see MapNav)
var painter: BigMapDraw = BigMapDraw.new()
var cursor_on: bool: ## the free map cursor (F / pad X) for placing a waypoint anywhere
	get: return nav.cursor_on
	set(v): nav.cursor_on = v
var cursor: Vector2:
	get: return nav.cursor
	set(v): nav.cursor = v
var route := PackedVector2Array()
var markers: Array = [] ## [{pos: Vector2, color: Color, label: String, kind: String}]; kind "poi" is a Poi.marker()
var summary := "" ## the big map's progress line ("Speed traps 3/9 · Landmarks 5/14 · Roads 212/1830")
var car_pos := Vector2.ZERO
var car_heading := 0.0
var speed := 0.0
var gear := 0
var rpm := 0.0
var rpm_max := 6500.0
var nitro := -1.0 ## the Nitrous bottle, 0..1 (-1: the modifier is off)
var nitro_burning := false
var fans_label: Label
var level_label: Label
var roads_label: Label
var clock_label: Label
var street_label: Label
var street_plate: Panel ## the dark plate under the street name, so it reads on bright ground
var area_label: Label
var chain_box: VBoxContainer
var chain_title: Label
var live_title: Label ## a live event's clock or score, over the skill chain (OpenWorld._update_live)
var live_line: Label
var chain_points: Label
var banners: VBoxContainer
var card: PanelContainer
var card_title: Label
var card_sub: Label
var card_body: Label
var card_hint: Label
var pause_panel: PanelContainer
var pause_buttons: Array[Button] = []
var pause_index := 0
var pause_col: VBoxContainer
var pause_title: Label
const PAUSE_ITEMS := [["resume", "RESUME"], ["car", "CAR: SEICENTO"], ["mods", "MODIFIERS"], ["map", "MAP"],
	["story", "STORY"], ["stages", "CAMPAIGN STAGE LIST"], ["reset", "RESET CAR TO ROAD"], ["reset_campaign", "RESET CAMPAIGN"],
	["time", "SKIP TO NEXT TIME OF DAY"], ["menu", "MAIN MENU"]]
var loading: OpenWorldCover ## the Forza-style cover the town builds behind
var help_label: Label
var tower: Control ## a race's running order on the map (StreetRivals.standings), top right
var _standings: Array = []
var _standings_color := Color.WHITE
var stats_box: VBoxContainer
var _street := ""
var _street_t := 0.0
var _area_t := 0.0
var _clock := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()

func setup(town: TownMap, tex: Texture2D) -> void:
	map = town
	map_tex = tex
	if tex:
		map_rect = Rect2(town.tx0, town.ty0, tex.get_width() * TownBuilder.LAND_RES, tex.get_height() * TownBuilder.LAND_RES)
		for m in [minimap_mat, big_map_mat]:
			m.set_shader_parameter("map_tex", tex)
			m.set_shader_parameter("map_origin", map_rect.position)
			m.set_shader_parameter("map_size", map_rect.size)

func _label(text: String, size: int, color: Color, weight := 700) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", CmrStyle.font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("outline_size", maxi(4, size / 6))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _motion_group(group_name: String) -> Control:
	var g := Control.new()
	g.name = group_name
	g.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(g)
	return g

func _build() -> void:
	speedo_group = _motion_group("SpeedoGroup") # first: stats, tower and the event card draw over the speedometer, as before
	corners_group = _motion_group("CornersGroup")
	# satnav disc, bottom left
	minimap = ColorRect.new()
	minimap_mat = ShaderMaterial.new()
	minimap_mat.shader = MINIMAP_SHADER
	minimap.material = minimap_mat
	minimap.anchor_top = 1.0
	minimap.anchor_bottom = 1.0
	minimap.offset_left = 28
	minimap.offset_right = 28 + MINIMAP_S
	minimap.offset_top = -28 - MINIMAP_S
	minimap.offset_bottom = -28
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	corners_group.add_child(minimap)
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_minimap_overlay)
	minimap.add_child(overlay)
	# speedometer, bottom right (shared segmented sweep dash with RaceHud)
	speedo = DashGauge.new()
	speedo.reserve_nitro = true
	speedo.anchor_left = 1.0
	speedo.anchor_right = 1.0
	speedo.anchor_top = 1.0
	speedo.anchor_bottom = 1.0
	speedo.offset_left = -(SPEEDO_RIGHT + SPEEDO_W)
	speedo.offset_right = -SPEEDO_RIGHT
	speedo.offset_top = -(SPEEDO_BOTTOM + SPEEDO_H)
	speedo.offset_bottom = -SPEEDO_BOTTOM
	speedo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speedo_group.add_child(speedo)
	_sync_speedo()
	# stats, top left
	var stats := VBoxContainer.new()
	stats_box = stats
	stats.position = Vector2(30, 24)
	stats.add_theme_constant_override("separation", 0)
	corners_group.add_child(stats)
	var brand := _label("SEICENTO FEST · BRZESZCZE", 15, ORANGE, 800)
	stats.add_child(brand)
	fans_label = _label("0 FANS", 30, Color.WHITE, 900)
	stats.add_child(fans_label)
	level_label = _label("", 14, GOLD, 800)
	stats.add_child(level_label)
	roads_label = _label("", 14, Color(1, 1, 1, 0.8), 600)
	stats.add_child(roads_label)
	clock_label = _label("", 14, Color(1, 1, 1, 0.8), 600)
	stats.add_child(clock_label)
	# skill chain, top centre
	chain_box = VBoxContainer.new()
	chain_box.anchor_left = 0.5
	chain_box.anchor_right = 0.5
	chain_box.offset_left = -300
	chain_box.offset_right = 300
	chain_box.offset_top = 24
	chain_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	chain_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(chain_box)
	chain_points = _label("", 40, GOLD, 900)
	chain_points.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chain_box.add_child(chain_points)
	chain_title = _label("", 18, Color.WHITE, 800)
	chain_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chain_box.add_child(chain_title)
	live_title = _label("", 30, Color.WHITE, 900)
	live_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	live_title.visible = false
	chain_box.add_child(live_title)
	chain_box.move_child(live_title, 0)
	live_line = _label("", 18, Color(1, 1, 1, 0.9), 800) # 16 was hard to read at 800x450 (2026-11-14 shots)
	live_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	live_line.visible = false
	chain_box.add_child(live_line)
	chain_box.move_child(live_line, 1)
	# discovery and result banners, left, between the stats and the satnav (_trim_banners keeps them there)
	banners = VBoxContainer.new()
	banners.position = Vector2(EDGE, 190)
	banners.custom_minimum_size = Vector2(BANNERS_W, 0)
	banners.size = Vector2(BANNERS_W, 0)
	banners.add_theme_constant_override("separation", 8)
	banners.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(banners)
	# street name, bottom centre; district, under the chain
	street_plate = Panel.new()
	street_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	street_plate.add_theme_stylebox_override("panel", _street_plate_box())
	street_plate.anchor_left = 0.5
	street_plate.anchor_right = 0.5
	street_plate.anchor_top = 1.0
	street_plate.anchor_bottom = 1.0
	street_plate.modulate.a = 0.0
	add_child(street_plate)
	street_label = _label("", 24, Color.WHITE, 800)
	street_label.anchor_left = 0.5
	street_label.anchor_right = 0.5
	street_label.anchor_top = 1.0
	street_label.anchor_bottom = 1.0
	street_label.offset_left = -400
	street_label.offset_right = 400
	street_label.offset_top = -78
	street_label.offset_bottom = -40
	street_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(street_label)
	area_label = _label("", 46, Color.WHITE, 900)
	area_label.anchor_left = 0.5
	area_label.anchor_right = 0.5
	area_label.offset_left = -500
	area_label.offset_right = 500
	area_label.offset_top = 150
	area_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	area_label.modulate.a = 0.0
	add_child(area_label)
	# a race's timing list, top right (the event card is hidden while a run is on)
	tower = Control.new()
	tower.anchor_left = 1.0
	tower.anchor_right = 1.0
	tower.offset_left = -EDGE - TOWER_W
	tower.offset_right = -EDGE
	tower.offset_top = 24
	tower.offset_bottom = 24 + 11 * (TOWER_ROW + 2.0)
	tower.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tower.draw.connect(_draw_tower)
	tower.visible = false
	corners_group.add_child(tower)
	# event card, right
	card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_box())
	card.anchor_left = 1.0
	card.anchor_right = 1.0
	card.offset_left = -EDGE - CARD_W
	card.offset_right = -EDGE
	card.offset_top = 150
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	corners_group.add_child(card)
	_corner_panels = [minimap, stats_box, tower, card]
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	card.add_child(col)
	card_sub = _label("", 14, ORANGE, 800)
	col.add_child(card_sub)
	card_title = _label("", 28, Color.WHITE, 900)
	card_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_title.max_lines_visible = 2 # the card stays clear of the speedometer under it
	card_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(card_title)
	card_body = _label("", 15, Color(1, 1, 1, 0.88), 500)
	card_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_body.max_lines_visible = 6
	card_body.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(card_body)
	card_hint = _label("", 18, GOLD, 900)
	col.add_child(card_hint)
	card.hide()
	# controls reminder, faint, bottom centre
	help_label = _label("W/S drive · A/D steer · Space handbrake · R reset · M map · G route to next event · C camera · B look back · Esc menu", 12, Color(1, 1, 1, 0.72), 500)
	help_label.anchor_left = 0.5
	help_label.anchor_right = 0.5
	help_label.anchor_top = 1.0
	help_label.anchor_bottom = 1.0
	help_label.offset_left = -400
	help_label.offset_right = 400
	help_label.offset_top = -30
	help_label.offset_bottom = -10
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(help_label)
	resized.connect(_layout)
	_build_big_map()
	_build_pause()
	_build_loading()

func _street_plate_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(CmrStyle.PLATE, 0.62)
	sb.set_corner_radius_all(6)
	return sb

func _card_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(CmrStyle.PLATE, 0.88)
	sb.border_color = ORANGE
	sb.border_width_left = 6
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	sb.skew = Vector2(-0.08, 0.0)
	return sb

func _build_big_map() -> void:
	big_map = ColorRect.new()
	big_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	big_map_mat = ShaderMaterial.new()
	big_map_mat.shader = MINIMAP_SHADER
	big_map_mat.set_shader_parameter("rotate", false)
	big_map_mat.set_shader_parameter("disc", false)
	big_map.material = big_map_mat
	big_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(big_map)
	big_overlay = Control.new()
	big_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	big_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	big_overlay.gui_input.connect(_big_map_input)
	big_overlay.draw.connect(_draw_big_overlay)
	nav.selected.connect(func(i: int) -> void:
		map_sel = i
		big_overlay.queue_redraw())
	nav.clicked.connect(_big_clicked)
	big_map.add_child(big_overlay)
	big_map.hide()

func _build_pause() -> void:
	pause_panel = PanelContainer.new()
	pause_panel.add_theme_stylebox_override("panel", _card_box())
	pause_panel.anchor_left = 0.5
	pause_panel.anchor_right = 0.5
	pause_panel.anchor_top = 0.5
	pause_panel.anchor_bottom = 0.5
	pause_panel.offset_left = -230
	pause_panel.offset_right = 230
	pause_panel.offset_top = -260
	pause_panel.offset_bottom = 260
	pause_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(pause_panel)
	pause_col = VBoxContainer.new()
	pause_col.add_theme_constant_override("separation", 8)
	pause_panel.add_child(pause_col)
	pause_title = _label("PAUSED", 30, Color.WHITE, 900)
	pause_col.add_child(pause_title)
	set_pause_page("PAUSED", PAUSE_ITEMS)
	pause_panel.hide()

## Fills the pause panel with one page of buttons: [[action, text, (disabled)]]. The main page is PAUSE_ITEMS; the
## MODIFIERS page lists CarMods with "mod:<id>" actions and a "mods_back".
func set_pause_page(title: String, items: Array) -> void:
	pause_title.text = title
	for b in pause_buttons:
		b.queue_free()
	pause_buttons.clear()
	for item in items:
		var b := Button.new()
		b.text = item[1]
		b.custom_minimum_size = Vector2(0, 42)
		b.add_theme_font_override("font", CmrStyle.font(800))
		b.add_theme_font_size_override("font_size", 17)
		if item.size() > 2 and item[2]:
			b.modulate = Color(1, 1, 1, 0.45)
		var action: String = item[0]
		b.pressed.connect(func(): pause_action.emit(action))
		pause_col.add_child(b)
		pause_buttons.append(b)
	pause_index = 0
	if pause_panel.visible:
		pause_buttons[0].grab_focus()

## Relabels one button on the page shown (a modifier switched on or off) and keeps the focus on it.
func set_pause_text(index: int, text: String) -> void:
	if index >= 0 and index < pause_buttons.size():
		pause_buttons[index].text = text

func _build_loading() -> void:
	loading = OpenWorldCover.new()
	add_child(loading)

# ------------------------------------------------------------------------------------------ updates

## Puts up the loading cover: a still of the car somewhere in Brzeszcze and the figures of the one fitted.
func open_loading(spec: CarSpec, car_name: String, car_key := "stock") -> void:
	loading.open(spec, car_name, -1, car_key)

func show_loading(text: String, fraction: float) -> void:
	if not loading.visible:
		loading.open(load("res://data/seicento.tres"), "Fiat Seicento")
	loading.set_status(text, fraction)

func hide_loading() -> void:
	loading.hide()

## The Nitrous bottle under the speedometer; a negative level hides it.
func set_nitro(level: float, burning: bool) -> void:
	if absf(level - nitro) > 0.004 or burning != nitro_burning:
		nitro = level
		nitro_burning = burning
		_sync_speedo()

func update_drive(kmh: float, g: int, r: float, r_max: float, pos: Vector2, heading: float, dt: float, vz := 0.0) -> void:
	_clock += dt
	speed = kmh
	gear = g
	rpm = r
	rpm_max = r_max
	car_pos = pos
	car_heading = heading
	# zoom out with speed, as a satnav does
	var radius := lerpf(170.0, 330.0, clampf(kmh / 120.0, 0.0, 1.0))
	minimap_mat.set_shader_parameter("centre", pos)
	minimap_mat.set_shader_parameter("heading", heading)
	minimap_mat.set_shader_parameter("radius_m", radius)
	overlay.set_meta("radius", radius)
	overlay.queue_redraw()
	_sync_speedo()
	if map_open:
		map_tick(dt)
		big_overlay.queue_redraw()
	_street_t = maxf(0.0, _street_t - dt)
	# bright for the first seconds on a new street, then a calm 70% (it used to fade to 10%: unreadable)
	street_label.modulate.a = 0.7 + clampf(_street_t, 0.0, 1.0) * 0.3 if _street != "" else 0.0
	street_plate.modulate.a = street_label.modulate.a
	if _area_t > 0.0:
		_area_t -= dt
		area_label.modulate.a = clampf(minf(_area_t, 3.2 - _area_t) * 2.0, 0.0, 1.0)
	_fit_card()
	_update_motion(kmh, pos, heading, dt, vz)

func _update_motion(kmh: float, pos: Vector2, heading: float, dt: float, vz: float) -> void:
	if map_open or (pause_panel != null and pause_panel.visible):
		_motion.sync_kinematics(kmh / 3.6, heading, pos, vz)
		_motion.step_accel(0.0, 0.0, dt, size.y)
	else:
		_motion.step_kinematics(kmh / 3.6, heading, pos, dt, size.y, vz)
	_apply_motion()

func _apply_motion() -> void:
	if speedo_group:
		speedo_group.position = _motion.dash_offset
	if speedo:
		speedo.pivot_offset = speedo.size * 0.5
		speedo.rotation = _motion.dash_rot
		speedo.scale = _motion.dash_scale
		speedo.set_tilt(_motion.dash_skew)
	if corners_group:
		corners_group.position = _motion.corner_offset
	var crot := _motion.corner_rot
	for c in _corner_panels:
		c.pivot_offset = c.size * 0.5
		c.rotation = crot

func set_stats(fans: int, roads_found: int, roads_total: int, hour: float) -> void:
	fans_label.text = "%s FANS" % _thousands(fans)
	var lv := FanLevels.level(fans)
	var left := FanLevels.to_next(fans)
	level_label.text = "LEVEL %d · %s%s" % [lv, FanLevels.title(lv).to_upper(), "" if left < 0 else "  ·  %s TO NEXT" % _thousands(left)]
	roads_label.text = "ROADS DRIVEN  %d / %d" % [roads_found, roads_total]
	var h := int(hour) % 24
	clock_label.text = "%02d:%02d" % [h, int(fmod(hour, 1.0) * 60.0)]

static func _thousands(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = " " + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if v < 0 else "") + s + out

func set_street(street: String) -> void:
	if street == _street:
		return
	_street = street
	street_label.text = street.to_upper()
	_street_t = 3.0
	_layout()

func show_area(name: String) -> void:
	area_label.text = name.to_upper()
	_area_t = 3.2
	_layout()

## Keeps the free-floating labels inside the gaps between the panels at any canvas size (interface size,
## aspect ratio): the district name between the banners and the event card, the street and key help between
## the satnav and the speedometer. A label too long for its gap gets a smaller size, then "…".
func _layout() -> void:
	var W := size.x
	if W < 1.0:
		return
	var H := size.y
	var cx := W * 0.5
	var low := minf(cx - (28.0 + MINIMAP_S + 16.0), (W - (SPEEDO_RIGHT + SPEEDO_W) - 16.0) - cx) # satnav left, speedometer right
	_fit_label(street_label, low, 24, 16)
	_fit_label(help_label, low, 12, 10)
	# the key help on the bottom edge, the street name just above it
	var help_h := _line_h(help_label)
	help_label.offset_bottom = -10.0
	help_label.offset_top = -10.0 - help_h
	street_label.offset_bottom = help_label.offset_top - 4.0
	street_label.offset_top = street_label.offset_bottom - _line_h(street_label)
	# the plate hugs the text (at the size _fit_label picked), a little wider and taller
	var sf := street_label.get_theme_font("font")
	var sw := minf(low * 2.0, sf.get_string_size(street_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, street_label.get_theme_font_size("font_size")).x + street_label.get_theme_constant("outline_size"))
	street_plate.offset_left = -sw * 0.5 - 14.0
	street_plate.offset_right = sw * 0.5 + 14.0
	street_plate.offset_top = street_label.offset_top - 3.0
	street_plate.offset_bottom = street_label.offset_bottom + 3.0
	street_plate.visible = _street != ""
	var right := W - EDGE - CARD_W - 12.0 if card.visible else W - EDGE
	var top := minf(cx - (EDGE + BANNERS_W + 12.0), right - cx)
	_fit_label(area_label, top, 46, 24)
	# the skill chain between the stats and the right edge
	var stats_w := stats_box.get_combined_minimum_size().x if is_instance_valid(stats_box) else 300.0
	var chain_half := clampf(cx - (EDGE + stats_w + 16.0), 160.0, 300.0)
	chain_box.offset_left = -chain_half
	chain_box.offset_right = chain_half
	_fit_label(chain_title, chain_half, 18, 13)
	_fit_label(chain_points, chain_half, 40, 26)
	if H > 0.0:
		_fit_card()

func _line_h(l: Label) -> float:
	return ceilf(l.get_theme_font("font").get_height(l.get_theme_font_size("font_size")))

## The event card stops above the speedometer: its description loses lines (ending in "…") until it does.
## (Its size follows a text change a frame later, so this also runs from update_drive.)
func _fit_card() -> void:
	if not card.visible or card_body.max_lines_visible <= 2:
		return
	var limit := size.y - (SPEEDO_BOTTOM + SPEEDO_H) - 12.0
	var over := card.position.y + card.size.y - limit
	if over > 0.5:
		var lh := card_body.get_line_height() + card_body.get_theme_constant("line_spacing")
		card_body.max_lines_visible = maxi(2, card_body.max_lines_visible - ceili(over / maxf(1.0, lh)))

## Centres l in a band half wide and shrinks its font (down to lo) until the text fits.
func _fit_label(l: Label, half: float, hi: int, lo: int) -> void:
	half = maxf(80.0, half)
	l.offset_left = -half
	l.offset_right = half
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var f := l.get_theme_font("font")
	var fs := hi
	while fs > lo and f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + l.get_theme_constant("outline_size") > half * 2.0:
		fs -= 2
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_constant_override("outline_size", maxi(4, fs / 6))

func set_chain(points: int, label: String) -> void:
	if points <= 0:
		chain_points.text = ""
		chain_title.text = ""
		return
	var was := chain_title.text
	chain_points.text = _thousands(points)
	chain_title.text = label
	if label != was:
		_layout()

## A run's two lines at the top centre (live event or mission: position and clock, or score; then checkpoints or
## sectors, distance and the gap); "" hides them.
func set_live(title: String, line: String, color: Color) -> void:
	if live_title.text == title and live_line.text == line:
		return
	var shown := live_title.visible
	live_title.text = title
	live_line.text = line
	live_title.add_theme_color_override("font_color", color.lightened(0.25))
	# a countdown's number is drawn big, as the lights would be
	live_title.add_theme_font_size_override("font_size", 84 if title.is_valid_int() else 30)
	live_title.visible = title != ""
	live_line.visible = line != ""
	if shown != live_title.visible:
		_layout()

## The running order of a race on the map (StreetRivals.standings rows), [] hides it.
func set_standings(rows: Array, color: Color) -> void:
	if rows.is_empty() and _standings.is_empty():
		return
	_standings = rows
	_standings_color = color
	tower.visible = not rows.is_empty() and not map_open
	tower.queue_redraw()

func _draw_tower() -> void:
	var font := CmrStyle.font(800)
	var bold := CmrStyle.font(900)
	var W := TOWER_W
	var y := 0.0
	for i in _standings.size():
		var row: Dictionary = _standings[i]
		var me := bool(row.get("player", false))
		var out := bool(row.get("out", false)) or String(row.get("gap", "")) == "OUT"
		var fade := 0.5 if out else 1.0
		var bg := _standings_color.darkened(0.15) if me else Color(0.04, 0.05, 0.09, 0.72)
		tower.draw_rect(Rect2(0, y, W, TOWER_ROW), Color(bg, (0.95 if me else 0.72) * fade))
		tower.draw_rect(Rect2(0, y, 4, TOWER_ROW), Color(_standings_color if not me else Color.WHITE, fade))
		var ink := Color(Color.WHITE, fade)
		var base := y + 17.0
		tower.draw_string(bold, Vector2(8, base), str(i + 1), HORIZONTAL_ALIGNMENT_RIGHT, 24, 15, ink)
		var nm := String(row.get("name", ""))
		nm = nm if me else nm.split(" ")[-1]
		var num := int(row.get("number", 0))
		var label := nm.to_upper() if num <= 0 else "%s  #%d" % [nm.to_upper(), num]
		tower.draw_string(bold if me else font, Vector2(42, base), label, HORIZONTAL_ALIGNMENT_LEFT, W - 42 - 76, 14, ink)
		var gap := String(row.get("gap", ""))
		if i == 0 and gap == "":
			gap = "LEADER"
		tower.draw_string(font, Vector2(W - 82, base), gap, HORIZONTAL_ALIGNMENT_RIGHT, 76, 14, ink)
		y += TOWER_ROW + 2.0

func notify(title: String, sub: String, color := ORANGE) -> void:
	# the same banner again while it is still up (a key pressed twice, an event reported twice) is not stacked:
	# the one on screen is kept and its time starts over
	var key := title + "\n" + sub
	for b in banners.get_children():
		if b.get_meta("key", "") == key and not b.is_queued_for_deletion():
			_hold_banner(b as Control)
			return
	var panel := PanelContainer.new()
	panel.set_meta("key", key)
	var sb := _card_box()
	sb.border_color = color
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	panel.add_child(col)
	var head := _label(title, 22, Color.WHITE, 900)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART # a long name wraps inside the banner column
	col.add_child(head)
	if sub != "":
		var l := _label(sub, 14, color.lightened(0.35), 700)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(l)
	banners.add_child(panel)
	while banners.get_child_count() > 4:
		var old := banners.get_child(0)
		banners.remove_child(old)
		old.queue_free()
	# measured once the new banner is laid out (long lines wrap): a frame on, through a one-shot hook that goes
	# away with the HUD
	if is_inside_tree() and not get_tree().process_frame.is_connected(_trim_banners):
		get_tree().process_frame.connect(_trim_banners, CONNECT_ONE_SHOT)
	panel.modulate.a = 0.0
	_hold_banner(panel, 0.25)

## A banner's life: fades in over `fade_in` s (it starts from its current opacity), stays 4 s, fades out and goes.
## Called again for the same banner it restarts the 4 s.
func _hold_banner(panel: Control, fade_in := 0.0) -> void:
	if panel.has_meta("tween"):
		var old: Variant = panel.get_meta("tween")
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
	var tw := panel.create_tween()
	panel.set_meta("tween", tw)
	if fade_in > 0.0:
		tw.tween_property(panel, "modulate:a", 1.0, fade_in)
	else:
		panel.modulate.a = 1.0
	tw.tween_interval(4.0)
	tw.tween_property(panel, "modulate:a", 0.0, 0.6)
	tw.tween_callback(panel.queue_free)

## Drops the oldest banners while the stack would run down into the satnav (long lines wrap, so it is
## measured once laid out).
func _trim_banners() -> void:
	var room := size.y - 28.0 - MINIMAP_S - 16.0 - banners.position.y
	while banners.get_child_count() > 1 and banners.get_combined_minimum_size().y > room:
		var old := banners.get_child(0)
		banners.remove_child(old)
		old.queue_free()

## CmrStyle.restyle() calls this on a skin change: the card and banner plates follow the new palette.
func _skin_changed() -> void:
	for p: PanelContainer in [card, pause_panel]:
		var sb := p.get_theme_stylebox("panel") as StyleBoxFlat
		if sb:
			sb.bg_color = Color(CmrStyle.PLATE, 0.88)
	(street_plate.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = Color(CmrStyle.PLATE, 0.62)
	for b in banners.get_children():
		var sb := (b as Control).get_theme_stylebox("panel") as StyleBoxFlat
		if sb:
			sb.bg_color = Color(CmrStyle.PLATE, 0.88)
	loading.restyle()
	overlay.queue_redraw()
	speedo._skin_changed()
	big_overlay.queue_redraw()

func show_event(sub: String, title: String, body: String, hint: String, color: Color) -> void:
	card_sub.text = sub
	# _fit_card trims this to what fits above the speedometer; 6 cut a mission's Target and fans lines off at 720p (2026-11-10 QA)
	card_body.max_lines_visible = 10
	card_title.text = title
	card_body.text = body
	card_hint.text = hint
	var sb := card.get_theme_stylebox("panel") as StyleBoxFlat
	if sb:
		sb.border_color = color
	card.show()
	_layout()

func hide_event() -> void:
	card.hide()
	_layout()

func set_route(points: PackedVector2Array) -> void:
	route = points
	overlay.queue_redraw()

func set_markers(list: Array) -> void:
	markers = list
	nav.markers = list
	map_sel = clampi(map_sel, 0, maxi(markers.size() - 1, 0))
	overlay.queue_redraw()
	if map_open:
		big_overlay.queue_redraw()

## The progress line under the big map's title.
func set_summary(text: String) -> void:
	if text != summary:
		summary = text
		if map_open:
			big_overlay.queue_redraw()

func toggle_map(on: bool) -> void:
	map_open = on
	big_map.visible = on
	tower.visible = not on and not _standings.is_empty()
	if on and map_rect.size.x > 0.0:
		# the car, at a medium zoom; the whole area is a key away
		nav.markers = markers
		nav.sel = map_sel
		nav.car_pos = car_pos
		nav.route = route
		nav.open(map.bounds, big_overlay.size if big_overlay.size.x > 8.0 else size, car_pos)
		_map_sync()
		big_overlay.queue_redraw()

## Pushes the view's centre, radius and aspect into the map picture's shader.
func _map_sync() -> void:
	big_map_mat.set_shader_parameter("centre", nav.centre)
	big_map_mat.set_shader_parameter("radius_m", nav.radius)
	big_map_mat.set_shader_parameter("aspect", nav.aspect)

## One frame of the open map: held keys, stick and triggers, then the glide toward the goals.
func map_tick(dt: float) -> void:
	nav.set_size(big_overlay.size if big_overlay.size.x > 8.0 else size)
	nav.car_pos = car_pos
	nav.route = route
	nav.sel = map_sel
	nav.apply_input(nav.read_input(), dt)
	nav.step(dt)
	_map_sync()

## A key or pad press while the map is open; true when the view took it (zoom, pan, hop, filters, list).
func map_event(event: InputEvent) -> bool:
	nav.markers = markers
	nav.car_pos = car_pos
	nav.route = route
	nav.sel = map_sel
	var used := nav.handle_event(event)
	if used:
		big_overlay.queue_redraw()
	return used

## The pause menu's CAR button shows which car is fitted.
func set_car_label(hyper: bool, unlocked: bool, car_name := "") -> void: # car_name: a catalogue car other than the two Seicentos
	for b in pause_buttons:
		if b.text.begins_with("CAR:"):
			b.text = ("CAR: " + car_name.to_upper()) if car_name != "" else "CAR: HYPERCAR SEICENTO" if hyper else ("CAR: SEICENTO" if unlocked else "CAR: SEICENTO  (HYPERCAR AT LEVEL 10)")

func show_pause(on: bool) -> void:
	if on and not pause_panel.visible:
		set_pause_page("PAUSED", PAUSE_ITEMS)
	pause_panel.visible = on
	if on:
		pause_index = 0
		if not pause_buttons.is_empty():
			pause_buttons[0].grab_focus()

func move_pause(d: int) -> void:
	if pause_buttons.is_empty():
		return
	pause_index = posmod(pause_index + d, pause_buttons.size())
	pause_buttons[pause_index].grab_focus()

func press_pause() -> void:
	if pause_buttons.is_empty():
		return
	for i in pause_buttons.size():
		if pause_buttons[i].has_focus():
			pause_index = i
	pause_buttons[pause_index].pressed.emit()

# ------------------------------------------------------------------------------------------ drawing

## Map metres -> minimap pixels (heading up).
func _mini_xy(p: Vector2, radius: float, sz: Vector2) -> Vector2:
	return MapMarker.mini_xy(p, car_pos, car_heading, radius, sz)

func _draw_minimap_overlay() -> void:
	var sz := overlay.size
	var radius: float = overlay.get_meta("radius", 250.0)
	if route.size() >= 2:
		var pts := PackedVector2Array()
		for p in route:
			if p.distance_to(car_pos) < radius * 1.6:
				var q := _mini_xy(p, radius, sz)
				pts.append(q)
			elif not pts.is_empty():
				break
		if pts.size() >= 2:
			overlay.draw_polyline(pts, Color(CmrStyle.PLATE, 0.7), 7.0, true)
			overlay.draw_polyline(pts, PURPLE.lightened(0.25), 4.0, true)
	for m in markers:
		if m.get("kind", "") == "poi":
			continue # drawn below, small, and only when inside the disc
		var rim := MapMarker.rim_clamp(_mini_xy(m.pos, radius, sz), sz)
		var q: Vector2 = rim.pos
		var edge: bool = rim.edge
		var pin: bool = m.get("kind", "") == "waypoint"
		# a dark disc under every marker and, for the player's own waypoint, a white ring over it: readable on
		# the dark map, on the sky-blue water and in the skins whose violet is close to the map's own colour
		overlay.draw_circle(q, 9.0 if not edge else 7.0, Color(0, 0, 0, 0.6))
		overlay.draw_circle(q, 7.0 if not edge else 5.0, m.color)
		if pin:
			overlay.draw_arc(q, 9.5 if not edge else 7.5, 0.0, TAU, 20, Color.WHITE, 2.0, true)
		if edge:
			# beyond the rim: a small arrow outside the dot says which way it lies
			var dir: Vector2 = rim.dir
			var tip: Vector2 = q + dir * 15.0
			var side := Vector2(-dir.y, dir.x) * 5.0
			overlay.draw_colored_polygon(PackedVector2Array([tip, q + dir * 8.0 + side, q + dir * 8.0 - side]), Color.WHITE if pin else m.color)
	# points of interest: the few nearest inside the disc, small, no labels, under the stage and waypoint pins' weight
	for m in Poi.minimap_pois(markers, car_pos, radius):
		_draw_poi(overlay, _mini_xy(m.pos, radius, sz), m, 5.0, false)
	# the car: an arrow at the centre pointing up
	var c := sz * 0.5
	var arrow := PackedVector2Array([c + Vector2(0, -11), c + Vector2(8, 9), c + Vector2(0, 4), c + Vector2(-8, 9)])
	overlay.draw_colored_polygon(arrow, Color.WHITE)
	overlay.draw_polyline(arrow + PackedVector2Array([arrow[0]]), Color(0, 0, 0, 0.8), 1.5, true)
	# north tick on the rim
	var f := Vector2(cos(car_heading), sin(car_heading))
	var rt := Vector2(-f.y, f.x)
	var north := Vector2(Vector2(0, -1).dot(rt), -Vector2(0, -1).dot(f)).normalized()
	var np := c + north * sz.x * 0.47
	overlay.draw_string(CmrStyle.font(900), np + Vector2(-5, 6), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)

func _big_xy(p: Vector2) -> Vector2:
	return nav.xy(p)

func _big_world(q: Vector2) -> Vector2:
	return nav.world(q)

func _big_map_input(event: InputEvent) -> void:
	if nav.handle_mouse(event):
		_map_sync()
		big_overlay.queue_redraw()

## A click that was not a drag: on a marker it selects it (a second click on the selected one sets the route), on
## the bare map it places the player's own waypoint.
func _big_clicked(world: Vector2, marker: int) -> void:
	if marker >= 0:
		if marker == map_sel:
			map_accept.emit()
		else:
			nav.select(marker, false)
	else:
		waypoint_picked.emit(world)

## Opens the free cursor on the map, starting in the middle of what is in view.
func toggle_cursor(on: bool) -> void:
	cursor_on = on
	if on:
		cursor = nav.centre
	big_overlay.queue_redraw()

## Moves the free cursor by a fraction of the visible map (dir in -1..1 per axis); the view follows at the edges.
func move_cursor(dir: Vector2) -> void:
	cursor += dir * nav.radius * 0.06
	nav.centre = MapNav.clamp_centre(MapNav.push_view(nav.centre, cursor, nav.radius, nav.aspect), nav.radius, nav.aspect, nav.bounds)
	_map_sync()
	big_overlay.queue_redraw()

func _draw_big_overlay() -> void:
	painter.draw(self)

## One point of interest marker on `canvas` (the satnav or the big map) at `q`, `r` px across: a dark backing, the
## kind's shape in its colour, or a dim disc with a ? when the point is still unknown; a white ring when the GPS
## route runs to it and a wider one when selected.
func _draw_poi(canvas: Control, q: Vector2, m: Dictionary, r: float, sel: bool) -> void:
	var unknown: bool = m.get("unknown", false)
	var col: Color = m.color
	if unknown:
		var rr := r * 1.25
		canvas.draw_circle(q, rr + 2.0, Color(0, 0, 0, 0.6))
		canvas.draw_circle(q, rr, Color(CmrStyle.PLATE, 0.85))
		canvas.draw_arc(q, rr, 0.0, TAU, 20, col, 1.5, true)
		var fs := int(rr * 1.7)
		canvas.draw_string(CmrStyle.font(900), q + Vector2(-rr, fs * 0.36), "?", HORIZONTAL_ALIGNMENT_CENTER, rr * 2.0, fs, col.lightened(0.2))
	else:
		var shape := String(m.get("shape", "square"))
		canvas.draw_colored_polygon(MapMarker.shape_points(shape, q, r + 2.0), Color(0, 0, 0, 0.65))
		canvas.draw_colored_polygon(MapMarker.shape_points(shape, q, r), col)
	if m.get("routed", false):
		canvas.draw_arc(q, r * 2.0, 0.0, TAU, 24, PURPLE.lightened(0.25), 2.5, true)
	if sel:
		canvas.draw_arc(q, r * 2.0 + 5.0, 0.0, TAU, 32, Color.WHITE, 2.5, true)

## The big map's key to the point shapes: [shape, colour, text].
const LEGEND_SIZE := 14

static func legend_entries() -> Array:
	return [["diamond", Poi.KINDS[Poi.TRAP].color, "speed trap"], ["square", Poi.KINDS[Poi.LANDMARK].color, "landmark"],
		["?", Poi.UNKNOWN_COLOR, "undiscovered"]]

## How wide the key is (px), so the map's header can check it fits beside the progress line.
static func legend_width() -> float:
	var font := CmrStyle.font(600)
	var w := 0.0
	for e in legend_entries():
		w += 28.0 + font.get_string_size(String(e[2]), HORIZONTAL_ALIGNMENT_LEFT, -1, LEGEND_SIZE).x + 14.0
	return w

func _draw_map_legend(at: Vector2) -> void:
	var font := CmrStyle.font(600)
	var x := at.x
	for entry in legend_entries():
		var c := Vector2(x + 7.0, at.y + 1.0)
		if entry[0] == "?":
			big_overlay.draw_circle(c, 8.0, Color(CmrStyle.PLATE, 0.85))
			big_overlay.draw_arc(c, 8.0, 0.0, TAU, 16, entry[1], 1.5, true)
			big_overlay.draw_string(CmrStyle.font(900), c + Vector2(-8, 5), "?", HORIZONTAL_ALIGNMENT_CENTER, 16.0, 13, entry[1])
		else:
			big_overlay.draw_colored_polygon(MapMarker.shape_points(entry[0], c, 5.5), entry[1])
		big_overlay.draw_string(font, Vector2(x + 20.0, at.y + 6.0), entry[2], HORIZONTAL_ALIGNMENT_LEFT, -1, LEGEND_SIZE, Color(1, 1, 1, 0.8))
		x += 28.0 + font.get_string_size(String(entry[2]), HORIZONTAL_ALIGNMENT_LEFT, -1, LEGEND_SIZE).x + 14.0

func _gear_text() -> String:
	if gear < 0:
		return "R"
	if roundi(absf(speed)) < 1 and rpm <= 1150.0:
		return "N"
	return str(gear + 1)

func _sync_speedo() -> void:
	var frac := clampf(rpm / maxf(rpm_max, 1.0), 0.0, 1.0)
	var red := DashGauge.is_redline(frac, _clock)
	speedo.set_state(roundi(absf(speed)), _gear_text(), frac, red, false, nitro, nitro_burning)
