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
const EDGE := 30.0 ## legacy reference constant; _layout() uses HudLayout.hud_inset() (4.5% inward)
const MINIMAP_S := 300.0
const MINIMAP_INNER_FRAC := 0.875 ## inner edge of the dark bezel inside the thick neon ring (minimap.gdshader)
const MINIMAP_CLAMP_FRAC := 0.78 ## marker centres clamp here (fraction of disc radius) so dots, halos & edge arrows sit inside the ring
const MINIMAP_NORTH_FRAC := 0.79 ## North badge centre (fraction of disc radius) so the badge circle sits inside the ring
const MINIMAP_ROUTE_FRAC := 0.835 ## GPS route clip radius (fraction of disc radius) so its glow stops at the inner bezel
const MINIMAP_POI_REACH := 0.78 ## nearby POIs are shown only inside this fraction of map radius so they never sit on the ring
const SPEEDO_W := 330.0 ## bottom-right circular neon dial width
const SPEEDO_H := 276.0 ## bottom-right circular neon dial height
const SPEEDO_RIGHT := 24.0 ## legacy reference constant
const SPEEDO_BOTTOM := 14.0 ## legacy reference constant
const BANNERS_W := 500.0
const CARD_W := 480.0
const TOWER_W := 316.0 ## the race timing list, top right (set_standings)
const TOWER_ROW := 29.0
const TOWER_HEADER := 52.0 ## Unbound-style big P1/8 position readout above the rows

var map: TownMap
var map_tex: Texture2D
var map_rect := Rect2() ## the map picture in map metres
var minimap: ColorRect
var minimap_mat: ShaderMaterial
var overlay: Control
var speedo: DashGauge
var safe_frame: Control ## centred HUD safe zone (capped by HudLayout.hud_width on ultrawide displays)
var corners_group: Control ## g-force sway container for corner panels (satnav, stats, timing list, event card)
var speedo_group: Control ## g-force sway container for the speedometer cluster (moves most)
var _corner_panels: Array[Control] = []
var _motion := HudMotion.new()
var _inset := Vector2(72.0, 42.0) ## active inward margin inside safe_frame
var _ui_s := 1.0 ## responsive panel scale (1.0 at 1600x900+, easing down on compact scaled canvases)
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
var brand_label: Label
var fans_label: Label
var level_label: Label
var roads_label: Label
var clock_label: Label
var stats_plate: Panel ## slanted neon dark-glass plate behind the top-left stats
var street_label: Label
var street_plate: Panel ## the dark plate under the street name, so it reads on bright ground
var area_label: Label
var chain_box: VBoxContainer
var live_plate: Panel ## dark-glass neon pill behind live event header / skill chain
var chain_title: Label
var live_title: Label ## a live event's clock or score, over the skill chain (OpenWorld._update_live)
var live_line: Label
var _live_color := Color.WHITE
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

func _label(text: String, size: int, color: Color, weight := 700, italic := false, outline := -1) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", HudLayout.italic_font(weight) if italic else CmrStyle.font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.82))
	l.add_theme_constant_override("outline_size", outline if outline >= 0 else clampi(size / 8, 2, 5))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _motion_group(group_name: String) -> Control:
	var g := Control.new()
	g.name = group_name
	g.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe_frame.add_child(g)
	return g

func _sync_minimap_colors() -> void:
	if minimap_mat:
		minimap_mat.set_shader_parameter("edge_color", HudLayout.neon_primary())
		minimap_mat.set_shader_parameter("glow_color", HudLayout.neon_hot())

func _build() -> void:
	safe_frame = Control.new()
	safe_frame.name = "SafeFrame"
	safe_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(safe_frame)
	HudLayout.apply_safe_frame(safe_frame, size)
	speedo_group = _motion_group("SpeedoGroup") # first: stats, tower and the event card draw over the speedometer, as before
	corners_group = _motion_group("CornersGroup")
	# satnav disc, bottom left (bigger, pulled inward, thick glowing neon ring)
	minimap = ColorRect.new()
	minimap_mat = ShaderMaterial.new()
	minimap_mat.shader = MINIMAP_SHADER
	_sync_minimap_colors()
	minimap.material = minimap_mat
	minimap.anchor_top = 1.0
	minimap.anchor_bottom = 1.0
	minimap.offset_left = _inset.x
	minimap.offset_right = _inset.x + MINIMAP_S
	minimap.offset_top = -_inset.y - MINIMAP_S
	minimap.offset_bottom = -_inset.y
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	corners_group.add_child(minimap)
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_minimap_overlay)
	minimap.add_child(overlay)
	# speedometer, bottom right (shared glowing circular neon dial with RaceHud)
	speedo = DashGauge.new()
	speedo.reserve_nitro = true
	speedo.anchor_left = 1.0
	speedo.anchor_right = 1.0
	speedo.anchor_top = 1.0
	speedo.anchor_bottom = 1.0
	speedo.offset_left = -(_inset.x + SPEEDO_W)
	speedo.offset_right = -_inset.x
	speedo.offset_top = -(_inset.y + SPEEDO_H)
	speedo.offset_bottom = -_inset.y
	speedo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speedo_group.add_child(speedo)
	_sync_speedo()
	# stats, top left — bold neon dark-glass card pulled inward from the corner
	stats_plate = Panel.new()
	stats_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_plate.add_theme_stylebox_override("panel", _stats_plate_box())
	corners_group.add_child(stats_plate)
	var stats := VBoxContainer.new()
	stats_box = stats
	stats.position = Vector2(_inset.x + 14.0, _inset.y + 8.0)
	stats.add_theme_constant_override("separation", 1)
	corners_group.add_child(stats)
	brand_label = _label("SEICENTO FEST · BRZESZCZE", 16, HudLayout.neon_primary(), 900, true)
	stats.add_child(brand_label)
	fans_label = _label("0 FANS", 36, Color.WHITE, 900, true)
	stats.add_child(fans_label)
	level_label = _label("", 15, HudLayout.neon_boost(), 800, true)
	stats.add_child(level_label)
	roads_label = _label("", 14, Color(0.92, 0.96, 1.0, 0.88), 700)
	stats.add_child(roads_label)
	clock_label = _label("", 14, HudLayout.neon_primary().lightened(0.25), 800, true)
	stats.add_child(clock_label)
	# skill chain & live event readout, top centre — dark neon glass pill + bold italic type
	live_plate = Panel.new()
	live_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	live_plate.anchor_left = 0.5
	live_plate.anchor_right = 0.5
	live_plate.add_theme_stylebox_override("panel", _live_plate_box(HudLayout.neon_primary()))
	live_plate.visible = false
	safe_frame.add_child(live_plate)
	chain_box = VBoxContainer.new()
	chain_box.anchor_left = 0.5
	chain_box.anchor_right = 0.5
	chain_box.offset_left = -320
	chain_box.offset_right = 320
	chain_box.offset_top = _inset.y
	chain_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	chain_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe_frame.add_child(chain_box)
	chain_points = _label("", 48, HudLayout.neon_boost(), 900, true, 4)
	chain_points.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chain_points.visible = false
	chain_box.add_child(chain_points)
	chain_title = _label("", 20, Color.WHITE, 900, true, 3)
	chain_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chain_title.visible = false
	chain_box.add_child(chain_title)
	live_title = _label("", 38, Color.WHITE, 900, true, 4)
	live_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	live_title.visible = false
	chain_box.add_child(live_title)
	chain_box.move_child(live_title, 0)
	live_line = _label("", 20, Color(1, 1, 1, 0.95), 800, true, 3)
	live_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	live_line.visible = false
	chain_box.add_child(live_line)
	chain_box.move_child(live_line, 1)
	# discovery and result banners, left, between the stats and the satnav (_trim_banners keeps them there)
	banners = VBoxContainer.new()
	banners.position = Vector2(_inset.x, _inset.y + 168.0)
	banners.custom_minimum_size = Vector2(BANNERS_W, 0)
	banners.size = Vector2(BANNERS_W, 0)
	banners.add_theme_constant_override("separation", 10)
	banners.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe_frame.add_child(banners)
	# street name, bottom centre (compact neon pill right at the bottom edge so the car stays clear)
	street_plate = Panel.new()
	street_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	street_plate.add_theme_stylebox_override("panel", _street_plate_box())
	street_plate.anchor_left = 0.5
	street_plate.anchor_right = 0.5
	street_plate.anchor_top = 1.0
	street_plate.anchor_bottom = 1.0
	street_plate.modulate.a = 0.0
	safe_frame.add_child(street_plate)
	street_label = _label("", 26, Color.WHITE, 900, true)
	street_label.anchor_left = 0.5
	street_label.anchor_right = 0.5
	street_label.anchor_top = 1.0
	street_label.anchor_bottom = 1.0
	street_label.offset_left = -400
	street_label.offset_right = 400
	street_label.offset_top = -78
	street_label.offset_bottom = -40
	street_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	safe_frame.add_child(street_label)
	area_label = _label("", 52, Color.WHITE, 900, true)
	area_label.anchor_left = 0.5
	area_label.anchor_right = 0.5
	area_label.offset_left = -500
	area_label.offset_right = 500
	area_label.offset_top = 170
	area_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	area_label.modulate.a = 0.0
	safe_frame.add_child(area_label)
	# a race's timing list, top right (Unbound-style big P1/8 header + bold neon rows)
	tower = Control.new()
	tower.anchor_left = 1.0
	tower.anchor_right = 1.0
	tower.offset_left = -_inset.x - TOWER_W
	tower.offset_right = -_inset.x
	tower.offset_top = _inset.y
	tower.offset_bottom = _inset.y + TOWER_HEADER + 11 * (TOWER_ROW + 3.0)
	tower.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tower.draw.connect(_draw_tower)
	tower.visible = false
	corners_group.add_child(tower)
	# event card, right
	card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_box())
	card.anchor_left = 1.0
	card.anchor_right = 1.0
	card.offset_left = -_inset.x - CARD_W
	card.offset_right = -_inset.x
	card.offset_top = _inset.y + 116.0
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	corners_group.add_child(card)
	_corner_panels = [minimap, stats_plate, stats_box, tower, card]
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	card.add_child(col)
	card_sub = _label("", 15, HudLayout.neon_primary(), 900, true)
	col.add_child(card_sub)
	card_title = _label("", 32, Color.WHITE, 900, true)
	card_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_title.max_lines_visible = 2 # the card stays clear of the speedometer under it
	card_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(card_title)
	card_body = _label("", 16, Color(1, 1, 1, 0.90), 600)
	card_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_body.max_lines_visible = 6
	card_body.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(card_body)
	card_hint = _label("", 19, HudLayout.neon_boost(), 900, true)
	col.add_child(card_hint)
	card.hide()
	# controls reminder, faint, bottom centre
	help_label = _label("W/S drive · A/D steer · Space handbrake · R reset · M map · G route to next event · C camera · B look back · Esc menu", 12, Color(1, 1, 1, 0.72), 600)
	help_label.anchor_left = 0.5
	help_label.anchor_right = 0.5
	help_label.anchor_top = 1.0
	help_label.anchor_bottom = 1.0
	help_label.offset_left = -400
	help_label.offset_right = 400
	help_label.offset_top = -28
	help_label.offset_bottom = -8
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_label.visible = false # Options → Control hints (set_hints)
	safe_frame.add_child(help_label)
	resized.connect(_layout)
	_build_big_map()
	_build_pause()
	_build_loading()
	_layout()

func _stats_plate_box() -> StyleBoxFlat:
	var sb := HudLayout.neon_box(HudLayout.neon_primary(), 0.78, 5, -0.08, 10, 14.0, 8.0)
	sb.bg_color = HudLayout.glass_plate(0.76)
	return sb

func _live_plate_box(accent: Color) -> StyleBoxFlat:
	var sb := HudLayout.neon_box(accent, 0.76, 5, -0.10, 12, 18.0, 8.0)
	sb.bg_color = HudLayout.glass_plate(0.76)
	return sb

func _street_plate_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(CmrStyle.PLATE, 0.78)
	sb.border_color = HudLayout.neon_primary()
	sb.border_width_bottom = 3
	sb.border_width_top = 1
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.set_corner_radius_all(5)
	sb.skew = Vector2(0.0 if CmrStyle.skin == "ps1" else -0.10, 0.0)
	sb.shadow_color = Color(HudLayout.neon_primary(), 0.35)
	sb.shadow_size = 0 if CmrStyle.skin == "ps1" else 8
	return sb

func _card_box() -> StyleBoxFlat:
	return HudLayout.neon_box(ORANGE, 0.88, 7, -0.09, 12, 24.0, 16.0)

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
	pause_panel.resized.connect(_fit_pause_skew)
	add_child(pause_panel)
	pause_col = VBoxContainer.new()
	pause_col.add_theme_constant_override("separation", 8)
	pause_panel.add_child(pause_col)
	pause_title = _label("PAUSED", 30, Color.WHITE, 900)
	pause_col.add_child(pause_title)
	set_pause_page("PAUSED", PAUSE_ITEMS)
	pause_panel.hide()

## The plate is sheared (skew), so its corners lean in by skew * half its height: pads the sides by that much so the
## top and bottom buttons (and their focus frames) stay inside the slanted box on pages of any length.
func _fit_pause_skew() -> void:
	var sb := pause_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if sb == null:
		return
	var pad := 24.0 + absf(sb.skew.x) * pause_panel.size.y * 0.5 + 6.0
	if absf(sb.content_margin_left - pad) > 0.5:
		sb.content_margin_left = pad
		sb.content_margin_right = pad
		pause_panel.offset_left = -206.0 - pad
		pause_panel.offset_right = 206.0 + pad

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
	_layout()

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
	if size.x < 1.0:
		return
	var safe := HudLayout.apply_safe_frame(safe_frame, size)
	var W := safe.size.x
	var H := safe.size.y
	if W < 1.0:
		return
	_inset = HudLayout.hud_inset(safe.size)
	_ui_s = HudLayout.hud_scale(safe.size)
	var mx := _inset.x
	var my := _inset.y
	var s := _ui_s
	var cx := W * 0.5
	# bottom-left satnav and bottom-right circular neon dial pulled inward by _inset
	var map_s := roundf(MINIMAP_S * s)
	minimap.offset_left = mx
	minimap.offset_right = mx + map_s
	minimap.offset_top = -my - map_s
	minimap.offset_bottom = -my
	var sp_w := roundf(SPEEDO_W * s)
	var sp_h := roundf(SPEEDO_H * s)
	speedo.offset_left = -mx - sp_w
	speedo.offset_right = -mx
	speedo.offset_top = -my - sp_h
	speedo.offset_bottom = -my
	# top-left stats box & slanted neon plate behind it
	stats_box.position = Vector2(mx + 14.0, my + 8.0)
	var stats_min := stats_box.get_combined_minimum_size()
	var stats_w := maxf(240.0 * s, stats_min.x)
	var stats_h := maxf(104.0 * s, stats_min.y)
	if is_instance_valid(stats_plate):
		stats_plate.position = Vector2(mx, my)
		stats_plate.size = Vector2(stats_w + 26.0, stats_h + 16.0)
	# top-right standings tower
	var tw := roundf(TOWER_W * s)
	var th := roundf(TOWER_HEADER * s) + maxi(1, _standings.size()) * roundf((TOWER_ROW + 3.0) * s) + 8.0
	tower.offset_left = -mx - tw
	tower.offset_right = -mx
	tower.offset_top = my
	tower.offset_bottom = my + th
	# banners and event card pulled inward
	var bw := minf(roundf(BANNERS_W * s), maxf(300.0, floorf(W * 0.34)))
	var cw := minf(roundf(CARD_W * s), maxf(320.0, floorf(W * 0.34)))
	banners.position = Vector2(mx, my + stats_h + 28.0)
	banners.custom_minimum_size.x = bw
	banners.size = Vector2(bw, 0.0) # height back to what the stack needs (a Control only grows on its own)
	card.offset_left = -mx - cw
	card.offset_right = -mx
	card.offset_top = my + roundf(108.0 * s)
	# bottom-centre controls reminder & street plate stay cleanly between satnav and speedometer (car stays clear)
	var low := minf(cx - (mx + map_s + 16.0), (W - mx - sp_w - 16.0) - cx)
	_fit_label(street_label, maxf(80.0, low - 18.0), maxi(18, roundi(26.0 * s)), 15)
	_fit_label(help_label, low, 12, 10)
	var help_h := _line_h(help_label)
	help_label.offset_bottom = -8.0
	help_label.offset_top = -8.0 - help_h
	street_label.offset_bottom = (help_label.offset_top - 6.0) if help_label.visible else -12.0
	street_label.offset_top = street_label.offset_bottom - _line_h(street_label)
	var sf := street_label.get_theme_font("font")
	var sw := minf(maxf(0.0, low * 2.0 - 28.0), sf.get_string_size(street_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, street_label.get_theme_font_size("font_size")).x + street_label.get_theme_constant("outline_size"))
	street_plate.offset_left = -sw * 0.5 - 18.0
	street_plate.offset_right = sw * 0.5 + 18.0
	street_plate.offset_top = street_label.offset_top - 4.0
	street_plate.offset_bottom = street_label.offset_bottom + 4.0
	street_plate.visible = _street != ""
	# top-centre skill chain & live event readout between stats and right column
	var right_top_w := tw if tower.visible else (cw if card.visible else 0.0)
	var chain_half := clampf(minf(cx - (mx + stats_w + 38.0), (W - mx - right_top_w - 16.0) - cx), 150.0, 320.0)
	chain_box.offset_left = -chain_half
	chain_box.offset_right = chain_half
	chain_box.offset_top = my + 6.0
	var inner_w := maxf(160.0, chain_half * 2.0 - 32.0)
	_fit_vbox_label(chain_title, inner_w, maxi(14, roundi(20.0 * s)), 13)
	_fit_vbox_label(chain_points, inner_w, maxi(26, roundi(48.0 * s)), 24)
	if live_title.visible and not live_title.text.is_valid_int():
		_fit_vbox_label(live_title, inner_w, maxi(22, roundi(36.0 * s)), 20)
	if live_line.visible:
		_fit_vbox_label(live_line, inner_w, maxi(14, roundi(19.0 * s)), 13)
	_sync_live_plate(chain_half)
	var right_mid := W - mx - cw - 12.0 if card.visible else (W - mx - tw - 12.0 if tower.visible else W - mx)
	var top_gap := minf(cx - (mx + bw + 12.0), right_mid - cx)
	var live_bottom := (live_plate.offset_bottom + 14.0) if (is_instance_valid(live_plate) and live_plate.visible) else (my + roundf(120.0 * s))
	area_label.offset_top = maxf(my + roundf(120.0 * s), live_bottom)
	_fit_label(area_label, top_gap, maxi(26, roundi(52.0 * s)), 22)
	if H > 0.0:
		_fit_card()
		_trim_banners()

func _sync_live_plate(chain_half: float) -> void:
	if not is_instance_valid(live_plate):
		return
	var show_live := live_title.visible and not live_title.text.is_valid_int()
	var show_chain := chain_points.visible and chain_points.text != ""
	live_plate.visible = show_live or show_chain
	if not live_plate.visible:
		return
	var content_w := 0.0
	var content_h := 0.0
	var sep := chain_box.get_theme_constant("separation")
	var vis_n := 0
	for l: Label in [live_title, live_line, chain_points, chain_title]:
		if l.visible and l.text != "":
			var f := l.get_theme_font("font")
			var fs := l.get_theme_font_size("font_size")
			content_w = maxf(content_w, f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + l.get_theme_constant("outline_size"))
			content_h += ceilf(f.get_height(fs))
			vis_n += 1
	if vis_n > 1:
		content_h += sep * (vis_n - 1)
	var pw := clampf(content_w + 52.0, 200.0, chain_half * 2.0)
	var ph := maxf(46.0, content_h + 16.0)
	live_plate.offset_left = -pw * 0.5
	live_plate.offset_right = pw * 0.5
	live_plate.offset_top = chain_box.offset_top - 6.0
	live_plate.offset_bottom = chain_box.offset_top + ph - 6.0

## Shrinks a label's font inside a VBoxContainer without touching its offsets (the container owns its width).
func _fit_vbox_label(l: Label, max_w: float, hi: int, lo: int) -> void:
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var f := l.get_theme_font("font")
	var fs := hi
	while fs > lo and f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + l.get_theme_constant("outline_size") > max_w:
		fs -= 2
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_constant_override("outline_size", clampi(fs / 8, 2, 5))

func _line_h(l: Label) -> float:
	return ceilf(l.get_theme_font("font").get_height(l.get_theme_font_size("font_size")))

## The event card stops above the speedometer: its description loses lines (ending in "…") until it does.
## (Its size follows a text change a frame later, so this also runs from update_drive.)
func _fit_card() -> void:
	if not card.visible or card_body.max_lines_visible <= 2:
		return
	var sp_h := roundf(SPEEDO_H * _ui_s)
	var limit := size.y - (_inset.y + sp_h) - 14.0
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
	l.add_theme_constant_override("outline_size", clampi(fs / 7, 2, 6))

func set_chain(points: int, label: String) -> void:
	if points <= 0:
		var had := chain_points.visible
		chain_points.text = ""
		chain_title.text = ""
		chain_points.visible = false
		chain_title.visible = false
		if had:
			_layout()
		return
	var was := chain_title.text
	var had_pts := chain_points.visible
	chain_points.text = _thousands(points)
	chain_title.text = label
	chain_points.visible = true
	chain_title.visible = label != ""
	if label != was or not had_pts:
		_layout()

## A run's two lines at the top centre (live event or mission: position and clock, or score; then checkpoints or
## sectors, distance and the gap); "" hides them.
func set_live(title: String, line: String, color: Color) -> void:
	if live_title.text == title and live_line.text == line:
		return
	var shown := live_title.visible
	_live_color = color
	live_title.text = title
	live_line.text = line
	var bright := color.lightened(0.28)
	live_title.add_theme_color_override("font_color", bright)
	# a countdown's number is drawn big, as the lights would be
	live_title.add_theme_font_size_override("font_size", roundi(104.0 * _ui_s) if title.is_valid_int() else roundi(38.0 * _ui_s))
	live_title.visible = title != ""
	live_line.visible = line != ""
	if is_instance_valid(live_plate):
		live_plate.add_theme_stylebox_override("panel", _live_plate_box(color if title != "" else HudLayout.neon_primary()))
	if shown != live_title.visible or title != "":
		_layout()

## The running order of a race on the map (StreetRivals.standings rows), [] hides it.
func set_standings(rows: Array, color: Color) -> void:
	if rows.is_empty() and _standings.is_empty():
		return
	var was_vis := tower.visible
	var old_n := _standings.size()
	_standings = rows
	_standings_color = color
	tower.visible = not rows.is_empty() and not map_open
	if was_vis != tower.visible or old_n != rows.size():
		_layout()
	tower.queue_redraw()

func _draw_tower() -> void:
	if _standings.is_empty():
		return
	var s := _ui_s
	var W := tower.size.x if tower.size.x > 1.0 else roundf(TOWER_W * s)
	var row_h := roundf(TOWER_ROW * s)
	var header_h := roundf(TOWER_HEADER * s)
	var font := CmrStyle.font(800)
	var bold := HudLayout.italic_font(900, -0.14)
	var digits := HudLayout.italic_digits(-0.14)
	var accent := _standings_color if _standings_color.get_luminance() > 0.25 else HudLayout.neon_primary()
	var cyan := HudLayout.neon_primary()

	# Unbound-style HUGE position readout ("P1 / 8") right above the standings rows
	var my_pos := 1
	for i in _standings.size():
		if bool((_standings[i] as Dictionary).get("player", false)):
			my_pos = i + 1
			break
	var hdr := Rect2(0.0, 0.0, W, header_h - 6.0 * s)
	HudLayout.draw_neon_panel(tower, hdr, accent, 0.86, 6.0 * s, true)
	var pos_str := "P%d" % my_pos
	var tot_str := "/ %d" % _standings.size()
	var pos_fs := maxi(16, roundi(38.0 * s))
	var tot_fs := maxi(12, roundi(20.0 * s))
	if CmrStyle.skin != "ps1":
		tower.draw_string_outline(digits, Vector2(16.0 * s, header_h - 14.0 * s), pos_str, HORIZONTAL_ALIGNMENT_LEFT, -1, pos_fs, maxi(4, roundi(8.0 * s)), Color(accent, 0.35))
	tower.draw_string(digits, Vector2(16.0 * s, header_h - 14.0 * s), pos_str, HORIZONTAL_ALIGNMENT_LEFT, -1, pos_fs, Color.WHITE)
	var pw := digits.get_string_size(pos_str, HORIZONTAL_ALIGNMENT_LEFT, -1, pos_fs).x
	tower.draw_string(bold, Vector2(22.0 * s + pw, header_h - 16.0 * s), tot_str, HORIZONTAL_ALIGNMENT_LEFT, -1, tot_fs, Color(cyan.lightened(0.35), 0.95))
	tower.draw_string(bold, Vector2(0.0, header_h - 19.0 * s), "STANDINGS", HORIZONTAL_ALIGNMENT_RIGHT, W - 12.0 * s, maxi(10, roundi(12.0 * s)), Color(1.0, 1.0, 1.0, 0.85))

	var y := header_h
	for i in _standings.size():
		var row: Dictionary = _standings[i]
		var me := bool(row.get("player", false))
		var out := bool(row.get("out", false)) or String(row.get("gap", "")) == "OUT"
		var fade := 0.5 if out else 1.0
		var r := Rect2(0.0, y, W, row_h)
		if me:
			# Glowing neon player highlight row with bold bright left bar
			tower.draw_rect(r.grow(3.0 * s), Color(accent, 0.28 * fade))
			tower.draw_rect(r, Color(accent.lerp(cyan, 0.25), 0.95 * fade))
			tower.draw_rect(Rect2(0.0, y, 7.0 * s, row_h), Color(1.0, 1.0, 1.0, fade))
			tower.draw_rect(r, Color(1.0, 1.0, 1.0, 0.85 * fade), false, 1.5)
		else:
			tower.draw_rect(r, HudLayout.glass_plate(0.84 * fade))
			tower.draw_rect(Rect2(0.0, y, 4.5 * s, row_h), Color(accent, 0.92 * fade))
			tower.draw_rect(r, Color(accent, 0.30 * fade), false, 1.0)
		var ink := Color(0.03, 0.04, 0.08, fade) if me else Color(Color.WHITE, fade)
		var base := y + row_h * 0.72
		tower.draw_string(bold, Vector2(10.0 * s, base), str(i + 1), HORIZONTAL_ALIGNMENT_RIGHT, 26.0 * s, maxi(11, roundi(16.0 * s)), ink)
		var nm := String(row.get("name", ""))
		nm = nm if me else nm.split(" ")[-1]
		var num := int(row.get("number", 0))
		var label := nm.to_upper() if num <= 0 else "%s  #%d" % [nm.to_upper(), num]
		tower.draw_string(bold if me else font, Vector2(46.0 * s, base), label, HORIZONTAL_ALIGNMENT_LEFT, W - 46.0 * s - 88.0 * s, maxi(11, roundi(15.0 * s)), ink)
		var gap := String(row.get("gap", ""))
		if i == 0 and gap == "":
			gap = "LEADER"
		var gap_col := ink if me else Color(cyan.lightened(0.3) if i == 0 else Color.WHITE, fade)
		tower.draw_string(bold if i == 0 or me else font, Vector2(W - 94.0 * s, base), gap, HORIZONTAL_ALIGNMENT_RIGHT, 84.0 * s, maxi(11, roundi(15.0 * s)), gap_col)
		y += row_h + roundf(3.0 * s)

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
	var sb := HudLayout.neon_box(color, 0.90, 7, -0.11, 12, 22.0, 12.0)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	panel.add_child(col)
	var head := _label(title, maxi(18, roundi(26.0 * _ui_s)), Color.WHITE, 900, true)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART # a long name wraps inside the banner column
	col.add_child(head)
	if sub != "":
		var l := _label(sub, maxi(12, roundi(16.0 * _ui_s)), color.lightened(0.38), 800, true)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(l)
	banners.add_child(panel)
	while banners.get_child_count() > 4:
		var old := banners.get_child(0)
		banners.remove_child(old)
		old.queue_free()
	# measured once the new banner is laid out (long lines wrap): a frame on, through a one-shot hook that goes
	# away with the HUD
	_schedule_trim_banners()
	panel.modulate.a = 0.0
	_hold_banner(panel, 0.25)

func _schedule_trim_banners() -> void:
	if is_inside_tree() and not get_tree().process_frame.is_connected(_trim_banners):
		get_tree().process_frame.connect(_trim_banners, CONNECT_ONE_SHOT)

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
	if banners.get_child_count() <= 1:
		return
	# A banner added this frame has not been sorted to banners' width yet (PanelContainer starts at padding + 1 px),
	# so its autowrapped labels report a 1-char-wide vertical column (~600-800 px tall); wait for layout first.
	var want_w := maxf(banners.size.x, banners.custom_minimum_size.x)
	if want_w < 1.0:
		return
	for b in banners.get_children():
		if (b as Control).size.x < want_w - 1.0:
			if banners.visible:
				_schedule_trim_banners()
			return
	var map_s := roundf(MINIMAP_S * _ui_s)
	var room := size.y - _inset.y - map_s - 16.0 - banners.position.y
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
			sb.skew = Vector2(0.0 if CmrStyle.skin == "ps1" else -0.09, 0.0)
			sb.shadow_size = 0 if CmrStyle.skin == "ps1" else 12
	_fit_pause_skew()
	if is_instance_valid(stats_plate):
		stats_plate.add_theme_stylebox_override("panel", _stats_plate_box())
	if is_instance_valid(live_plate):
		live_plate.add_theme_stylebox_override("panel", _live_plate_box(_live_color if live_title.visible else HudLayout.neon_primary()))
	street_plate.add_theme_stylebox_override("panel", _street_plate_box())
	for b in banners.get_children():
		var sb := (b as Control).get_theme_stylebox("panel") as StyleBoxFlat
		if sb:
			sb.bg_color = Color(CmrStyle.PLATE, 0.90)
			sb.skew = Vector2(0.0 if CmrStyle.skin == "ps1" else -0.11, 0.0)
			sb.shadow_size = 0 if CmrStyle.skin == "ps1" else 12
	if is_instance_valid(brand_label):
		brand_label.add_theme_color_override("font_color", HudLayout.neon_primary())
	if is_instance_valid(level_label):
		level_label.add_theme_color_override("font_color", HudLayout.neon_boost())
	if is_instance_valid(clock_label):
		clock_label.add_theme_color_override("font_color", HudLayout.neon_primary().lightened(0.25))
	if is_instance_valid(chain_points):
		chain_points.add_theme_color_override("font_color", HudLayout.neon_boost())
	for pair in [[brand_label, 900], [fans_label, 900], [level_label, 800], [clock_label, 800],
			[chain_points, 900], [chain_title, 900], [live_title, 900], [live_line, 800],
			[street_label, 900], [area_label, 900], [card_sub, 900], [card_title, 900], [card_hint, 900]]:
		var l: Label = pair[0]
		if is_instance_valid(l):
			l.add_theme_font_override("font", HudLayout.italic_font(int(pair[1])))
	_sync_minimap_colors()
	loading.restyle()
	overlay.queue_redraw()
	tower.queue_redraw()
	speedo._skin_changed()
	big_overlay.queue_redraw()

func show_event(sub: String, title: String, body: String, hint: String, color: Color) -> void:
	card_sub.text = sub
	card_sub.add_theme_color_override("font_color", color.lightened(0.25))
	# _fit_card trims this to what fits above the speedometer; 6 cut a mission's Target and fans lines off at 720p (2026-11-10 QA)
	card_body.max_lines_visible = 10
	card_title.text = title
	card_body.text = body
	card_hint.text = hint
	var sb := card.get_theme_stylebox("panel") as StyleBoxFlat
	if sb:
		sb.border_color = color
		sb.shadow_color = Color(color, 0.38)
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

## Options → Control hints: the key line along the bottom of the screen.
func set_hints(on: bool) -> void:
	if help_label.visible != on:
		help_label.visible = on
		_layout()

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

## Map metres -> minimap pixels (heading up), projected isotropically into the inscribed disc of `sz`.
func _mini_xy(p: Vector2, radius: float, sz: Vector2) -> Vector2:
	var disc_d := minf(sz.x, sz.y)
	var disc_sz := Vector2(disc_d, disc_d)
	return sz * 0.5 + (MapMarker.mini_xy(p, car_pos, car_heading, radius, disc_sz) - disc_sz * 0.5)

## Clips `route` (map metres) into contiguous pixel polylines strictly inside `(centre, max_r)`.
func _clip_route_runs(sz: Vector2, radius: float, centre: Vector2, max_r: float) -> Array[PackedVector2Array]:
	var runs: Array[PackedVector2Array] = []
	if route.size() < 2 or max_r <= 0.0:
		return runs
	var max_r2 := max_r * max_r
	var cur := PackedVector2Array()
	var prev_q := _mini_xy(route[0], radius, sz)
	for i in range(1, route.size()):
		var q := _mini_xy(route[i], radius, sz)
		var da := prev_q - centre
		var v := q - prev_q
		var a_k := v.length_squared()
		var lo := 0.0
		var hi := 1.0
		var hit := false
		if a_k < 1e-6:
			hit = da.length_squared() <= max_r2
		else:
			var b_k := 2.0 * da.dot(v)
			var c_k := da.length_squared() - max_r2
			var disc := b_k * b_k - 4.0 * a_k * c_k
			if disc >= 0.0:
				var sq := sqrt(disc)
				lo = maxf(0.0, (-b_k - sq) / (2.0 * a_k))
				hi = minf(1.0, (-b_k + sq) / (2.0 * a_k))
				hit = hi >= lo
		if hit:
			var p0 := prev_q + v * lo
			var p1 := prev_q + v * hi
			if lo > 0.0:
				if cur.size() >= 2:
					runs.append(cur)
				cur = PackedVector2Array([p0, p1])
			else:
				if cur.is_empty():
					cur.append(p0)
				cur.append(p1)
			if hi < 1.0:
				if cur.size() >= 2:
					runs.append(cur)
				cur = PackedVector2Array()
		else:
			if cur.size() >= 2:
				runs.append(cur)
			cur = PackedVector2Array()
		prev_q = q
	if cur.size() >= 2:
		runs.append(cur)
	return runs

## Computes every element drawn on the satnav disc (GPS route runs, event/mission/live/waypoint/POI markers
## and the North badge), clamped strictly inside the inner bezel of the thick neon ring at every zoom, heading
## and window aspect. Shared by `_draw_minimap_overlay` and headless tests so checks verify the exact draw math.
func minimap_draw_plan(sz: Vector2, radius: float) -> Dictionary:
	var centre := sz * 0.5
	var disc_r := minf(sz.x, sz.y) * 0.5
	var ms := disc_r / 150.0 # 1.0 at the 300 px design disc, scaling cleanly on smaller canvases
	var inner_r := disc_r * MINIMAP_INNER_FRAC
	var lim_r := disc_r * MINIMAP_CLAMP_FRAC
	var lim_frac := lim_r / maxf(sz.x, 1.0)
	var route_half_w := 5.0 * ms # outer glow polyline width is 10.0 * ms
	var route_r := minf(disc_r * MINIMAP_ROUTE_FRAC, maxf(0.0, inner_r - route_half_w))
	var route_runs := _clip_route_runs(sz, radius, centre, route_r)
	var arrow_tip_d := 13.0 * ms # clamped centre 0.78*R + 13*ms = 0.867*R < 0.875*R (inside the dark bezel)
	var items: Array[Dictionary] = []
	# nearby non-routed POIs first (under stage, mission, live and GPS pins)
	for m in Poi.minimap_pois(markers, car_pos, radius, 8, MINIMAP_POI_REACH):
		if bool(m.get("routed", false)):
			continue
		var q := _mini_xy(m.pos, radius, sz)
		if q.distance_to(centre) > lim_r + 0.01:
			continue
		var poi_r := 5.0 * ms
		var outer_r := maxf(poi_r * 1.25 + 2.0, (poi_r + 2.0) * 1.25)
		items.append({
			"marker": m, "pos": q, "edge": false, "dir": Vector2.UP, "is_poi": true,
			"pin": false, "poi_r": poi_r, "outer_r": outer_r, "tip": q,
		})
	for m in markers:
		var kind := String(m.get("kind", ""))
		if kind == "poi":
			if not bool(m.get("routed", false)):
				continue
			var rim := MapMarker.rim_clamp(_mini_xy(m.pos, radius, sz), sz, lim_frac)
			var q: Vector2 = rim.pos
			var edge: bool = rim.edge
			var dir: Vector2 = rim.dir
			var poi_r := (4.6 if edge else 5.0) * ms
			var outer_r := maxf(poi_r * 2.0 + 1.25, maxf(poi_r * 1.25 + 2.0, (poi_r + 2.0) * 1.25))
			items.append({
				"marker": m, "pos": q, "edge": edge, "dir": dir, "is_poi": true,
				"pin": false, "poi_r": poi_r, "outer_r": outer_r,
				"tip": q + dir * arrow_tip_d if edge else q,
			})
			continue
		var rim := MapMarker.rim_clamp(_mini_xy(m.pos, radius, sz), sz, lim_frac)
		var q: Vector2 = rim.pos
		var edge: bool = rim.edge
		var dir: Vector2 = rim.dir
		var pin := kind == "waypoint"
		var halo_r := (8.0 if edge else 10.5) * ms
		var ring_r := ((7.6 if edge else 9.5) + 1.1) * ms if pin else 0.0
		items.append({
			"marker": m, "pos": q, "edge": edge, "dir": dir, "is_poi": false,
			"pin": pin, "halo_r": halo_r, "outer_r": maxf(halo_r, ring_r),
			"tip": q + dir * arrow_tip_d if edge else q,
		})
	var f := Vector2(cos(car_heading), sin(car_heading))
	var rt := Vector2(-f.y, f.x)
	var north := Vector2(Vector2(0, -1).dot(rt), -Vector2(0, -1).dot(f)).normalized()
	var nr := 9.5 * ms
	var north_stroke := 1.6 * ms
	var np := centre + north * (disc_r * MINIMAP_NORTH_FRAC)
	return {
		"centre": centre, "disc_r": disc_r, "inner_r": inner_r, "ms": ms,
		"route_runs": route_runs, "route_half_w": route_half_w,
		"items": items,
		"north": {"pos": np, "r": nr, "stroke": north_stroke, "outer_r": nr + north_stroke * 0.5},
	}

func _draw_minimap_overlay() -> void:
	var sz := overlay.size
	if sz.x <= 1.0 or sz.y <= 1.0:
		return
	var radius: float = overlay.get_meta("radius", 250.0)
	var plan := minimap_draw_plan(sz, radius)
	var ms: float = plan.ms
	var cyan := HudLayout.neon_primary()
	var hot := HudLayout.neon_hot()
	var route_col := hot.lerp(PURPLE.lightened(0.2), 0.35)
	for pts: PackedVector2Array in plan.route_runs:
		overlay.draw_polyline(pts, Color(route_col, 0.32), 10.0 * ms, true)
		overlay.draw_polyline(pts, route_col, 4.6 * ms, true)
		overlay.draw_polyline(pts, Color(1.0, 1.0, 1.0, 0.72), 1.6 * ms, true)
	for it: Dictionary in plan.items:
		var m: Dictionary = it.marker
		var q: Vector2 = it.pos
		var edge: bool = it.edge
		var dir: Vector2 = it.dir
		if bool(it.is_poi):
			_draw_poi(overlay, q, m, float(it.poi_r), false)
			if edge:
				var tip: Vector2 = it.tip
				var side := Vector2(-dir.y, dir.x) * (4.0 * ms)
				var base_c := q + dir * (8.6 * ms)
				overlay.draw_colored_polygon(PackedVector2Array([tip, base_c + side, base_c - side]), PURPLE.lightened(0.25))
		else:
			var pin: bool = it.pin
			# glowing halo + dark disc under every marker so it pops on bright water and dark tarmac alike
			overlay.draw_circle(q, float(it.halo_r), Color(m.color, 0.26))
			overlay.draw_circle(q, (6.5 if edge else 8.5) * ms, Color(0, 0, 0, 0.75))
			overlay.draw_circle(q, (4.8 if edge else 6.5) * ms, m.color)
			if pin:
				overlay.draw_arc(q, (7.6 if edge else 9.5) * ms, 0.0, TAU, 20, Color.WHITE, 2.0 * ms, true)
			if edge:
				# beyond the map's range: pinned just inside the ring with a small arrow pointing towards it
				var tip: Vector2 = it.tip
				var side := Vector2(-dir.y, dir.x) * (4.2 * ms)
				var base_c := q + dir * (7.2 * ms)
				overlay.draw_colored_polygon(PackedVector2Array([tip, base_c + side, base_c - side]), Color.WHITE if pin else (m.color as Color))
	# the car: glowing neon arrow at the centre pointing up
	var c: Vector2 = plan.centre
	overlay.draw_circle(c, 15.0 * ms, Color(cyan, 0.25))
	var arrow := PackedVector2Array([
		c + Vector2(0, -13.0) * ms, c + Vector2(9.5, 10.0) * ms,
		c + Vector2(0, 4.5) * ms, c + Vector2(-9.5, 10.0) * ms,
	])
	overlay.draw_colored_polygon(arrow, Color.WHITE)
	overlay.draw_polyline(arrow + PackedVector2Array([arrow[0]]), cyan, 2.0 * ms, true)
	# north badge tucked strictly inside the glowing ring
	var north_d: Dictionary = plan.north
	var np: Vector2 = north_d.pos
	var nr: float = north_d.r
	var nfs := maxi(10, roundi(13.5 * ms))
	overlay.draw_circle(np, nr, HudLayout.glass_plate(0.92))
	overlay.draw_arc(np, nr, 0.0, TAU, 20, cyan, float(north_d.stroke), true)
	overlay.draw_string(HudLayout.italic_font(900), np + Vector2(-nr, nfs * 0.36), "N", HORIZONTAL_ALIGNMENT_CENTER, nr * 2.0, nfs, Color.WHITE)

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
