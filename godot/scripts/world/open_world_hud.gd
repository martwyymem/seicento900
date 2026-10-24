## The open world's HUD, in the Forza Horizon manner: the turning satnav disc with the GPS route and the event
## markers, a big speedometer, the skill chain, discovery banners, the street you are on, the event card when
## you pull into a beacon, the full-screen map (M), the pause menu and the loading screen.
class_name OpenWorldHud
extends Control

signal pause_action(action: String)
signal map_target(index: int)

const MINIMAP_SHADER := preload("res://shaders/minimap.gdshader")
const ORANGE := Color("#ff7a1a")
const PURPLE := Color("#8b5cf6")
const GOLD := Color("#ffd166")
const INK := Color("#0c0a14")

var map: TownMap
var map_tex: Texture2D
var map_rect := Rect2() ## the map picture in map metres
var minimap: ColorRect
var minimap_mat: ShaderMaterial
var overlay: Control
var speedo: Control
var big_map: ColorRect
var big_map_mat: ShaderMaterial
var big_overlay: Control
var map_open := false
var map_sel := 0
var route := PackedVector2Array()
var markers: Array = [] ## [{pos: Vector2, color: Color, label: String, kind: String}]
var car_pos := Vector2.ZERO
var car_heading := 0.0
var speed := 0.0
var gear := 0
var rpm := 0.0
var rpm_max := 6500.0
var fans_label: Label
var roads_label: Label
var clock_label: Label
var street_label: Label
var area_label: Label
var chain_box: VBoxContainer
var chain_title: Label
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
var loading: ColorRect
var loading_label: Label
var loading_bar: ProgressBar
var help_label: Label
var _street := ""
var _street_t := 0.0
var _area_t := 0.0

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

func _build() -> void:
	# satnav disc, bottom left
	minimap = ColorRect.new()
	minimap_mat = ShaderMaterial.new()
	minimap_mat.shader = MINIMAP_SHADER
	minimap.material = minimap_mat
	minimap.anchor_top = 1.0
	minimap.anchor_bottom = 1.0
	minimap.offset_left = 28
	minimap.offset_right = 28 + 250
	minimap.offset_top = -28 - 250
	minimap.offset_bottom = -28
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(minimap)
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_minimap_overlay)
	minimap.add_child(overlay)
	# speedometer, bottom right
	speedo = Control.new()
	speedo.anchor_left = 1.0
	speedo.anchor_right = 1.0
	speedo.anchor_top = 1.0
	speedo.anchor_bottom = 1.0
	speedo.offset_left = -300
	speedo.offset_right = -30
	speedo.offset_top = -230
	speedo.offset_bottom = -30
	speedo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speedo.draw.connect(_draw_speedo)
	add_child(speedo)
	# stats, top left
	var stats := VBoxContainer.new()
	stats.position = Vector2(30, 24)
	stats.add_theme_constant_override("separation", 0)
	add_child(stats)
	var brand := _label("SEICENTO FEST · BRZESZCZE", 15, ORANGE, 800)
	stats.add_child(brand)
	fans_label = _label("0 FANS", 30, Color.WHITE, 900)
	stats.add_child(fans_label)
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
	# discovery and result banners, left
	banners = VBoxContainer.new()
	banners.position = Vector2(30, 190)
	banners.custom_minimum_size = Vector2(520, 0)
	banners.add_theme_constant_override("separation", 8)
	banners.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(banners)
	# street name, bottom centre; district, under the chain
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
	# event card, right
	card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_box())
	card.anchor_left = 1.0
	card.anchor_right = 1.0
	card.offset_left = -500
	card.offset_right = -30
	card.offset_top = 150
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	card.add_child(col)
	card_sub = _label("", 14, ORANGE, 800)
	col.add_child(card_sub)
	card_title = _label("", 28, Color.WHITE, 900)
	card_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(card_title)
	card_body = _label("", 15, Color(1, 1, 1, 0.88), 500)
	card_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(card_body)
	card_hint = _label("", 18, GOLD, 900)
	col.add_child(card_hint)
	card.hide()
	# controls reminder, faint, bottom centre
	help_label = _label("W/S drive · A/D steer · R reset · M map · G route to next event · C camera · Esc menu", 12, Color(1, 1, 1, 0.5), 500)
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
	_build_big_map()
	_build_pause()
	_build_loading()

func _card_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.03, 0.1, 0.86)
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
	big_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	big_overlay.draw.connect(_draw_big_overlay)
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
	pause_panel.offset_top = -210
	pause_panel.offset_bottom = 210
	add_child(pause_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	pause_panel.add_child(col)
	col.add_child(_label("PAUSED", 30, Color.WHITE, 900))
	for item in [["resume", "RESUME"], ["map", "MAP"], ["stages", "CAMPAIGN STAGE LIST"], ["reset", "RESET CAR TO ROAD"],
			["time", "SKIP TO NEXT TIME OF DAY"], ["menu", "MAIN MENU"]]:
		var b := Button.new()
		b.text = item[1]
		b.custom_minimum_size = Vector2(0, 44)
		b.add_theme_font_override("font", CmrStyle.font(800))
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(func(): pause_action.emit(item[0]))
		col.add_child(b)
		pause_buttons.append(b)
	pause_panel.hide()

func _build_loading() -> void:
	loading = ColorRect.new()
	loading.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading.color = Color(0.05, 0.03, 0.09, 1.0)
	add_child(loading)
	var col := VBoxContainer.new()
	col.anchor_left = 0.5
	col.anchor_right = 0.5
	col.anchor_top = 0.5
	col.anchor_bottom = 0.5
	col.offset_left = -420
	col.offset_right = 420
	col.offset_top = -120
	col.offset_bottom = 120
	col.add_theme_constant_override("separation", 14)
	loading.add_child(col)
	var title := _label("BRZESZCZE", 72, Color.WHITE, 900)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var sub := _label("SEICENTO FEST · MAŁOPOLSKA · OPEN ROAD", 18, ORANGE, 800)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	loading_bar = ProgressBar.new()
	loading_bar.max_value = 1.0
	loading_bar.show_percentage = false
	loading_bar.custom_minimum_size = Vector2(0, 10)
	col.add_child(loading_bar)
	loading_label = _label("", 15, Color(1, 1, 1, 0.75), 600)
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(loading_label)
	var credit := _label("Map data © OpenStreetMap contributors · Elevation EU-DEM", 12, Color(1, 1, 1, 0.45), 500)
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(credit)
	loading.hide()

# ------------------------------------------------------------------------------------------ updates

func show_loading(text: String, fraction: float) -> void:
	loading.show()
	loading_label.text = text
	loading_bar.value = fraction

func hide_loading() -> void:
	loading.hide()

func update_drive(kmh: float, g: int, r: float, r_max: float, pos: Vector2, heading: float, dt: float) -> void:
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
	speedo.queue_redraw()
	if map_open:
		big_overlay.queue_redraw()
	_street_t = maxf(0.0, _street_t - dt)
	street_label.modulate.a = clampf(_street_t, 0.0, 1.0) * 0.9 + 0.1 if _street != "" else 0.0
	if _area_t > 0.0:
		_area_t -= dt
		area_label.modulate.a = clampf(minf(_area_t, 3.2 - _area_t) * 2.0, 0.0, 1.0)

func set_stats(fans: int, roads_found: int, roads_total: int, hour: float) -> void:
	fans_label.text = "%s FANS" % _thousands(fans)
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

func show_area(name: String) -> void:
	area_label.text = name.to_upper()
	_area_t = 3.2

func set_chain(points: int, label: String) -> void:
	if points <= 0:
		chain_points.text = ""
		chain_title.text = ""
		return
	chain_points.text = _thousands(points)
	chain_title.text = label

func notify(title: String, sub: String, color := ORANGE) -> void:
	var panel := PanelContainer.new()
	var sb := _card_box()
	sb.border_color = color
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	panel.add_child(col)
	col.add_child(_label(title, 22, Color.WHITE, 900))
	if sub != "":
		var l := _label(sub, 14, color.lightened(0.35), 700)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(l)
	banners.add_child(panel)
	while banners.get_child_count() > 4:
		var old := banners.get_child(0)
		banners.remove_child(old)
		old.queue_free()
	panel.modulate.a = 0.0
	var tw := panel.create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.25)
	tw.tween_interval(4.0)
	tw.tween_property(panel, "modulate:a", 0.0, 0.6)
	tw.tween_callback(panel.queue_free)

func show_event(sub: String, title: String, body: String, hint: String, color: Color) -> void:
	card_sub.text = sub
	card_title.text = title
	card_body.text = body
	card_hint.text = hint
	var sb := card.get_theme_stylebox("panel") as StyleBoxFlat
	if sb:
		sb.border_color = color
	card.show()

func hide_event() -> void:
	card.hide()

func set_route(points: PackedVector2Array) -> void:
	route = points
	overlay.queue_redraw()

func set_markers(list: Array) -> void:
	markers = list
	overlay.queue_redraw()

func toggle_map(on: bool) -> void:
	map_open = on
	big_map.visible = on
	if on and map_rect.size.x > 0.0:
		# fit the drivable area to the screen
		var b := map.bounds
		var aspect := size.x / maxf(size.y, 1.0)
		var half := maxf(b.size.y * 0.5, b.size.x * 0.5 / aspect) * 1.05
		big_map_mat.set_shader_parameter("centre", b.get_center())
		big_map_mat.set_shader_parameter("radius_m", half)
		big_map_mat.set_shader_parameter("aspect", aspect)
		big_overlay.queue_redraw()

func show_pause(on: bool) -> void:
	pause_panel.visible = on
	if on:
		pause_index = 0
		pause_buttons[0].grab_focus()

func move_pause(d: int) -> void:
	pause_index = posmod(pause_index + d, pause_buttons.size())
	pause_buttons[pause_index].grab_focus()

func press_pause() -> void:
	pause_buttons[pause_index].pressed.emit()

# ------------------------------------------------------------------------------------------ drawing

## Map metres -> minimap pixels (heading up).
func _mini_xy(p: Vector2, radius: float, sz: Vector2) -> Vector2:
	var f := Vector2(cos(car_heading), sin(car_heading))
	var rt := Vector2(-f.y, f.x)
	var d := p - car_pos
	var o := Vector2(d.dot(rt), -d.dot(f)) / radius
	return sz * 0.5 + o * sz * 0.5

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
			overlay.draw_polyline(pts, Color(0.1, 0.05, 0.2, 0.7), 7.0, true)
			overlay.draw_polyline(pts, PURPLE.lightened(0.25), 4.0, true)
	for m in markers:
		var q := _mini_xy(m.pos, radius, sz)
		var c := sz * 0.5
		var d := q - c
		var lim := sz.x * 0.44
		var edge := d.length() > lim
		if edge:
			q = c + d.normalized() * lim
		overlay.draw_circle(q, 9.0 if not edge else 7.0, Color(0, 0, 0, 0.6))
		overlay.draw_circle(q, 7.0 if not edge else 5.0, m.color)
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
	var sz := big_overlay.size
	var centre: Vector2 = big_map_mat.get_shader_parameter("centre")
	var radius: float = big_map_mat.get_shader_parameter("radius_m")
	var aspect: float = big_map_mat.get_shader_parameter("aspect")
	var o := (p - centre) / radius
	o.x /= aspect
	return sz * 0.5 + o * sz * 0.5

func _draw_big_overlay() -> void:
	if map == null:
		return
	if map.boundary.size() > 2:
		var b := PackedVector2Array()
		for p in map.boundary:
			b.append(_big_xy(p))
		b.append(b[0])
		big_overlay.draw_polyline(b, Color(1.0, 0.5, 0.2, 0.55), 2.0, true)
	if route.size() >= 2:
		var pts := PackedVector2Array()
		for p in route:
			pts.append(_big_xy(p))
		big_overlay.draw_polyline(pts, PURPLE.lightened(0.25), 4.0, true)
	var font := CmrStyle.font(800)
	for i in markers.size():
		var m: Dictionary = markers[i]
		var q := _big_xy(m.pos)
		var sel := i == map_sel
		big_overlay.draw_circle(q, 13.0 if sel else 10.0, Color(0, 0, 0, 0.7))
		big_overlay.draw_circle(q, 10.0 if sel else 7.0, m.color)
		if sel:
			big_overlay.draw_arc(q, 18.0, 0.0, TAU, 32, Color.WHITE, 2.5, true)
		big_overlay.draw_string(font, q + Vector2(16, 6), String(m.label), HORIZONTAL_ALIGNMENT_LEFT, -1, 16 if sel else 13,
			Color.WHITE if sel else Color(1, 1, 1, 0.75))
	var c := _big_xy(car_pos)
	var f := Vector2(cos(car_heading), sin(car_heading))
	var r := Vector2(-f.y, f.x)
	var arrow := PackedVector2Array([c + f * 14.0, c - f * 9.0 + r * 9.0, c - f * 4.0, c - f * 9.0 - r * 9.0])
	big_overlay.draw_colored_polygon(arrow, Color.WHITE)
	var title := "BRZESZCZE · MAP"
	big_overlay.draw_string(CmrStyle.font(900), Vector2(40, 60), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color.WHITE)
	var hint := "◂ ▸ pick an event · Enter set route · M / Esc close"
	big_overlay.draw_string(CmrStyle.font(600), Vector2(40, 92), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.75))
	if map_sel >= 0 and map_sel < markers.size():
		big_overlay.draw_string(CmrStyle.font(800), Vector2(40, big_overlay.size.y - 40), String(markers[map_sel].get("info", "")),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, GOLD)

func _draw_speedo() -> void:
	var sz := speedo.size
	var c := Vector2(sz.x - 110, sz.y - 100)
	var r := 92.0
	var start := deg_to_rad(140.0)
	var sweep := deg_to_rad(260.0)
	speedo.draw_arc(c, r, start, start + sweep, 64, Color(0, 0, 0, 0.45), 14.0, true)
	var frac := clampf(rpm / maxf(rpm_max, 1.0), 0.0, 1.0)
	var red := frac > 0.88
	speedo.draw_arc(c, r, start, start + sweep * frac, 64, Color("#ff3b3b") if red else ORANGE, 10.0, true)
	for k in 8:
		var a := start + sweep * k / 7.0
		speedo.draw_line(c + Vector2(cos(a), sin(a)) * (r - 16), c + Vector2(cos(a), sin(a)) * (r - 6), Color(1, 1, 1, 0.6), 2.0)
	var digits := CmrStyle.digits()
	var txt := str(int(round(speed)))
	speedo.draw_string(digits, c + Vector2(-90, 18), txt, HORIZONTAL_ALIGNMENT_CENTER, 180, 64, Color.WHITE)
	speedo.draw_string(CmrStyle.font(800), c + Vector2(-90, 44), "KM/H", HORIZONTAL_ALIGNMENT_CENTER, 180, 14, Color(1, 1, 1, 0.7))
	var g := "R" if gear < 0 else str(gear + 1)
	speedo.draw_string(CmrStyle.font(900), c + Vector2(-90, 82), g, HORIZONTAL_ALIGNMENT_CENTER, 180, 30, GOLD)
