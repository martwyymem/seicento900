## The open world's loading screen, after Forza Horizon's: a still of the Seicento parked somewhere in Brzeszcze in
## good light (pre-rendered by tests/_cover_shots.gd into textures/loading/), drifting in slowly, with the car's figures
## along the bottom and a spinner in the corner. It is only a picture and some labels, so it is up the moment the
## player asks for the world, while the town builds behind it.
class_name OpenWorldCover
extends Control

## Each car's stills, by CarCatalog key: [file under textures/loading/, place caption]. The stock set is the fallback for a car
## without stills of its own (shots_for), so a new catalogue car never shows an empty cover. Rendered by tests/_cover_shots.gd.
const SHOTS := {
	"stock": [
		["ow_cover_1.jpg", "KWK Brzeszcze · the shaft at sundown"],
		["ow_cover_2.jpg", "ul. Bór · Brzeszcze-Bór"],
		["ow_cover_3.jpg", "S1 · dusk towards Wilamowice"],
	],
	"hypercar": [
		["hypercar_1.jpg", "KWK Brzeszcze · the shaft at sundown"],
		["hypercar_2.jpg", "ul. Bór · Brzeszcze-Bór"],
		["hypercar_3.jpg", "S1 · dusk towards Wilamowice"],
	],
	"golf4": [
		["golf4_1.jpg", "KWK Brzeszcze · the shaft at sundown"],
		["golf4_2.jpg", "ul. Bór · Brzeszcze-Bór"],
		["golf4_3.jpg", "S1 · dusk towards Wilamowice"],
	],
	"logan": [
		["logan_1.jpg", "KWK Brzeszcze · the shaft at sundown"],
		["logan_2.jpg", "ul. Bór · Brzeszcze-Bór"],
		["logan_3.jpg", "S1 · dusk towards Wilamowice"],
	],
	"v50": [
		["v50_1.jpg", "KWK Brzeszcze · the shaft at sundown"],
		["v50_2.jpg", "ul. Bór · Brzeszcze-Bór"],
		["v50_3.jpg", "S1 · dusk towards Wilamowice"],
	],
	"i20": [
		["i20_1.jpg", "KWK Brzeszcze · the shaft at sundown"],
		["i20_2.jpg", "ul. Bór · Brzeszcze-Bór"],
		["i20_3.jpg", "S1 · dusk towards Wilamowice"],
	],
	"sandero": [
		["sandero_1.jpg", "KWK Brzeszcze · the shaft at sundown"],
		["sandero_2.jpg", "ul. Bór · Brzeszcze-Bór"],
		["sandero_3.jpg", "S1 · dusk towards Wilamowice"],
	],
	"focus": [
		["focus_1.jpg", "KWK Brzeszcze · the shaft at sundown"],
		["focus_2.jpg", "ul. Bór · Brzeszcze-Bór"],
		["focus_3.jpg", "S1 · dusk towards Wilamowice"],
	],
	"zafira": [
		["zafira_1.jpg", "KWK Brzeszcze · the shaft at sundown"],
		["zafira_2.jpg", "ul. Bór · Brzeszcze-Bór"],
		["zafira_3.jpg", "S1 · dusk towards Wilamowice"],
	],
}
const DIR := "res://textures/loading/"
const ACCENT := Color("#ff4fa3") ## the festival pink of the open-world HUD's highlights
const DRIFT_TIME := 14.0 ## s for the slow zoom across the still
## Forza-style performance classes by index: [top of the band, letter, colour]
const CLASSES := [[500, "D", Color("#3fa7d6")], [600, "C", Color("#f2c14e")], [700, "B", Color("#f78154")],
	[800, "A", Color("#e4572e")], [900, "S1", Color("#9d4edd")], [998, "S2", Color("#3a86ff")], [999, "X", Color("#2ec4b6")]]

var shot := 0
var shots: Array = SHOTS.stock ## the set the cover is showing (the driven car's, or the stock one)
var _photo: TextureRect
var _fallback: ColorRect
var _vignette: Control
var _title_lbl: Label
var _sub_lbl: Label
var _place_plate: PanelContainer
var _place: Label
var _car_name: Label
var _badge_letter: Label
var _badge_number: Label
var _badge: PanelContainer
var _stats_row: HBoxContainer
var _status: Label
var _spinner: Control
var _spin := 0.0
var _t := 0.0

func _init() -> void:
	name = "OpenWorldCover"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	clip_contents = true
	_fallback = ColorRect.new()
	_fallback.color = CmrStyle.TINT_HOME
	_fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fallback)
	_photo = TextureRect.new()
	_photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_photo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_photo)
	add_child(_shade(true))
	add_child(_shade(false))
	add_child(_side_shade())
	_vignette = Control.new()
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.draw.connect(_draw_vignette)
	add_child(_vignette)

	# top left: where we are
	var top := VBoxContainer.new()
	top.position = Vector2(56, 42)
	top.add_theme_constant_override("separation", 4)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	_title_lbl = _label("BRZESZCZE", 56, Color.WHITE, 900, true)
	top.add_child(_title_lbl)
	_sub_lbl = _label("SEICENTO FEST · OPEN ROAD", 16, HudLayout.neon_hot(), 900, true)
	top.add_child(_sub_lbl)
	_place_plate = PanelContainer.new()
	_place_plate.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_place_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place_plate.add_theme_stylebox_override("panel", _place_box_style())
	top.add_child(_place_plate)
	_place = _label("", 14, Color(0.92, 0.98, 1.0, 0.94), 700, true)
	_place_plate.add_child(_place)

	# bottom left: the car and its figures
	var car := VBoxContainer.new()
	car.anchor_top = 1.0
	car.anchor_bottom = 1.0
	car.grow_vertical = Control.GROW_DIRECTION_BEGIN
	car.offset_left = 56
	car.offset_bottom = -48
	car.add_theme_constant_override("separation", 12)
	car.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(car)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 16)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	car.add_child(name_row)
	_badge = PanelContainer.new()
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var badge_row := HBoxContainer.new()
	badge_row.add_theme_constant_override("separation", 0)
	_badge.add_child(badge_row)
	_badge_letter = _label("D", 20, Color.WHITE, 900, true)
	_badge_letter.custom_minimum_size.x = 38
	_badge_letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge_number = _label("100", 20, Color.BLACK, 800, true)
	_badge_number.custom_minimum_size.x = 54
	_badge_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge_number.add_theme_constant_override("outline_size", 0)
	var number_bg := PanelContainer.new()
	var white := StyleBoxFlat.new()
	white.bg_color = Color.WHITE
	white.content_margin_left = 4
	white.content_margin_right = 4
	number_bg.add_theme_stylebox_override("panel", white)
	number_bg.add_child(_badge_number)
	badge_row.add_child(_badge_letter)
	badge_row.add_child(number_bg)
	name_row.add_child(_badge)
	_car_name = _label("", 42, Color.WHITE, 900, true)
	name_row.add_child(_car_name)
	_stats_row = HBoxContainer.new()
	_stats_row.add_theme_constant_override("separation", 26)
	_stats_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	car.add_child(_stats_row)

	# bottom right: what is building and the glowing neon spinner
	var corner := HBoxContainer.new()
	corner.anchor_left = 1.0
	corner.anchor_right = 1.0
	corner.anchor_top = 1.0
	corner.anchor_bottom = 1.0
	corner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	corner.grow_vertical = Control.GROW_DIRECTION_BEGIN
	corner.offset_right = -56
	corner.offset_bottom = -52
	corner.add_theme_constant_override("separation", 16)
	corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(corner)
	_status = _label("", 15, HudLayout.neon_primary().lightened(0.32), 800, true)
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	corner.add_child(_status)
	_spinner = Control.new()
	_spinner.custom_minimum_size = Vector2(52, 52)
	_spinner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spinner.draw.connect(_draw_spinner)
	corner.add_child(_spinner)

	var credit := _label("Map data © OpenStreetMap contributors · Elevation EU-DEM", 11, Color(0.85, 0.94, 1.0, 0.45), 500, false)
	credit.anchor_left = 1.0
	credit.anchor_right = 1.0
	credit.anchor_top = 1.0
	credit.anchor_bottom = 1.0
	credit.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	credit.grow_vertical = Control.GROW_DIRECTION_BEGIN
	credit.offset_right = -56
	credit.offset_bottom = -20
	add_child(credit)
	hide()

## The stills of a car (CarCatalog key): its own set when every file of it exists, else the stock car's.
static func shots_for(car_key: String) -> Array:
	var own: Array = SHOTS.get(car_key, [])
	if own.is_empty() or own.any(func(s: Array) -> bool: return not ResourceLoader.exists(DIR + String(s[0]))):
		return SHOTS.stock
	return own

## Shows the cover with one of the driven car's stills (-1: pick one at random) and that car's figures (from its spec).
func open(spec: CarSpec, car_name: String, index := -1, car_key := "stock") -> void:
	shots = shots_for(car_key)
	shot = randi() % shots.size() if index < 0 else clampi(index, 0, shots.size() - 1)
	var path := DIR + String(shots[shot][0])
	_photo.texture = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_place.text = String(shots[shot][1])
	_car_name.text = car_name.to_upper()
	var st := car_stats(spec)
	var cls := perf_class(st)
	_badge_letter.text = String(cls[0])
	_badge_number.text = str(cls[1])
	var sb := StyleBoxFlat.new()
	sb.bg_color = cls[2]
	sb.border_color = Color.WHITE
	sb.set_border_width_all(2)
	sb.skew = Vector2(0.0 if CmrStyle.skin == "ps1" else -0.10, 0.0)
	if CmrStyle.skin != "ps1":
		sb.shadow_color = Color(cls[2], 0.48)
		sb.shadow_size = 10
	_badge.add_theme_stylebox_override("panel", sb)
	for child in _stats_row.get_children():
		child.queue_free()
	# [caption, value, bar fill against the hypercar's figures]
	for row in [["TOP SPEED", "%d km/h" % roundi(st.top_kmh), st.top_kmh / 350.0],
			["POWER", "%d hp" % roundi(st.hp), st.hp / 700.0],
			["TORQUE", "%d Nm" % roundi(st.nm), st.nm / 700.0],
			["WEIGHT", "%d kg" % roundi(st.kg), st.kg / 1500.0],
			["DRIVE", "AWD" if spec.awd else "FWD", -1.0]]:
		_stats_row.add_child(_stat(row[0], row[1], row[2]))
	_t = 0.0
	restyle()
	set_status("", 0.0)
	show()

## The menu skin changed: backdrop, accents and italic display fonts follow it.
func restyle() -> void:
	_fallback.color = CmrStyle.TINT_HOME
	if is_instance_valid(_sub_lbl):
		_sub_lbl.add_theme_color_override("font_color", HudLayout.neon_hot())
		_sub_lbl.add_theme_font_override("font", HudLayout.italic_font(900))
	if is_instance_valid(_title_lbl):
		_title_lbl.add_theme_font_override("font", HudLayout.italic_font(900))
	if is_instance_valid(_car_name):
		_car_name.add_theme_font_override("font", HudLayout.italic_font(900))
	if is_instance_valid(_place_plate):
		_place_plate.add_theme_stylebox_override("panel", _place_box_style())
	if is_instance_valid(_status):
		_status.add_theme_color_override("font_color", HudLayout.neon_primary().lightened(0.32))
		_status.add_theme_font_override("font", HudLayout.italic_font(800))
	if is_instance_valid(_vignette):
		_vignette.queue_redraw()
	if is_instance_valid(_spinner):
		_spinner.queue_redraw()

func _skin_changed() -> void:
	restyle()

func _place_box_style() -> StyleBoxFlat:
	var sb := HudLayout.neon_box(HudLayout.neon_primary(), 0.72, 4, -0.09, 8, 12.0, 4.0)
	sb.bg_color = HudLayout.glass_plate(0.75)
	return sb

## The line beside the spinner: the step that is building now.
func set_status(text: String, _fraction: float) -> void:
	_status.text = text.to_upper()

func _process(delta: float) -> void:
	if not visible:
		return
	# frames can come far apart while a step builds: never let one jump the drift or the spinner wildly
	var dt := minf(delta, 0.1)
	_t += dt
	# from the clock, not summed frame times: after a frame that came late the arcs stand where a steady spin
	# would have them
	_spin = float(Time.get_ticks_msec() % 3600000) / 1000.0 * 5.5
	_spinner.queue_redraw()
	var k := 1.0 + 0.06 * smoothstep(0.0, 1.0, minf(_t / DRIFT_TIME, 1.0))
	_photo.pivot_offset = size * Vector2(0.62, 0.55)
	_photo.scale = Vector2(k, k)

func _draw_spinner() -> void:
	var c := _spinner.size * 0.5
	var r := minf(c.x, c.y) - 4.0
	var neon := HudLayout.neon_primary()
	var hot := HudLayout.neon_hot()
	var is_ps1 := CmrStyle.skin == "ps1"
	_spinner.draw_arc(c, r, 0.0, TAU, 48, Color(neon, 0.18), 3.0, true)
	var sweep := 1.7 + 1.1 * sin(_spin * 0.5)
	if not is_ps1:
		_spinner.draw_arc(c, r, _spin, _spin + sweep, 32, Color(neon, 0.28), 9.0, true)
	_spinner.draw_arc(c, r, _spin, _spin + sweep, 32, neon, 4.0, true)
	if not is_ps1:
		_spinner.draw_arc(c, r * 0.58, -_spin * 1.4, -_spin * 1.4 + 1.5, 24, Color(hot, 0.30), 7.0, true)
	_spinner.draw_arc(c, r * 0.58, -_spin * 1.4, -_spin * 1.4 + 1.5, 24, hot, 3.2, true)
	var tip := c + Vector2(cos(_spin + sweep), sin(_spin + sweep)) * r
	_spinner.draw_circle(tip, 3.0, Color.WHITE)

func _draw_vignette() -> void:
	if CmrStyle.skin == "ps1" or size.x < 2.0:
		return
	var neon := HudLayout.neon_primary()
	var hot := HudLayout.neon_hot()
	_vignette.draw_rect(Rect2(0.0, 0.0, size.x, 3.0), Color(neon, 0.72))
	_vignette.draw_rect(Rect2(0.0, 3.0, size.x, 12.0), Color(neon, 0.10))
	_vignette.draw_rect(Rect2(0.0, size.y - 3.0, size.x, 3.0), Color(hot, 0.72))
	_vignette.draw_rect(Rect2(0.0, size.y - 14.0, size.x, 11.0), Color(hot, 0.12))
	HudLayout.draw_radial_glow(_vignette, Vector2(size.x * 0.05, size.y * 0.08), size.y * 0.62, Color(neon, 0.18))
	HudLayout.draw_radial_glow(_vignette, Vector2(size.x * 0.94, size.y * 0.92), size.y * 0.58, Color(hot, 0.18))

## The car's headline figures from its spec: top speed (where the best gear's power at the wheels meets drag and
## rolling resistance, capped by the limiter in top), peak power and torque, and weight with the driver.
static func car_stats(spec: CarSpec) -> Dictionary:
	var kg := spec.mass_empty + spec.driver_mass
	var peak_w := 0.0
	var peak_nm := 0.0
	for p in spec.torque_curve:
		peak_nm = maxf(peak_nm, p.y)
	for rpm in range(int(spec.idle_rpm), int(spec.limiter) + 1, 50):
		peak_w = maxf(peak_w, _torque(spec, rpm) * rpm * TAU / 60.0)
	var top := 0.0
	var v := 1.0
	while v < 150.0:
		var avail := 0.0
		for g in spec.gears:
			var rpm := v / spec.wheel_radius * 60.0 / TAU * g * spec.final_drive
			if rpm <= spec.limiter:
				avail = maxf(avail, _torque(spec, maxf(rpm, spec.idle_rpm)) * rpm * TAU / 60.0 * spec.efficiency)
		var load := kg * 9.81 + maxf(0.0, -spec.lift_a) * 0.5 * 1.225 * v * v
		var resist := 0.5 * 1.225 * spec.cd_a * v * v * v + spec.crr * load * v
		if avail < resist:
			break
		top = v
		v += 0.25
	return {"top_kmh": top * 3.6, "hp": peak_w / 745.7, "kw": peak_w / 1000.0, "nm": peak_nm, "kg": kg}

## Forza's performance index, loosely: from power to weight. [letter, index 100-999, colour]
static func perf_class(st: Dictionary) -> Array:
	var kw_per_t := float(st.kw) / (float(st.kg) / 1000.0)
	var pi := clampi(roundi(100.0 + 900.0 * sqrt(kw_per_t / 600.0)), 100, 999)
	for c in CLASSES:
		if pi <= int(c[0]):
			return [c[1], pi, c[2]]
	return ["X", 999, CLASSES[-1][2]]

static func _torque(spec: CarSpec, rpm: float) -> float:
	var curve := spec.torque_curve
	if rpm <= curve[0].x:
		return curve[0].y
	for i in range(1, curve.size()):
		if rpm <= curve[i].x:
			return lerpf(curve[i - 1].y, curve[i].y, (rpm - curve[i - 1].x) / (curve[i].x - curve[i - 1].x))
	return curve[-1].y

func _stat(caption: String, value: String, fill: float) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_label(caption, 12, HudLayout.neon_primary(), 900, true))
	col.add_child(_label(value, 24, Color.WHITE, 900, true))
	if fill >= 0.0:
		var bar := Control.new()
		bar.custom_minimum_size = Vector2(114, 7)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var clamped := clampf(fill, 0.04, 1.0)
		bar.draw.connect(func() -> void:
			var neon := HudLayout.neon_primary()
			var hot := HudLayout.neon_hot()
			bar.draw_rect(Rect2(Vector2.ZERO, bar.size), HudLayout.glass_plate(0.82))
			bar.draw_rect(Rect2(Vector2.ZERO, bar.size), Color(neon, 0.35), false, 1.0)
			var w := bar.size.x * clamped
			if CmrStyle.skin != "ps1":
				bar.draw_rect(Rect2(0.0, -2.0, w, bar.size.y + 4.0), Color(neon, 0.25))
			bar.draw_rect(Rect2(0.0, 0.0, w, bar.size.y), neon.lerp(hot, clamped * 0.55))
			bar.draw_rect(Rect2(maxf(0.0, w - 3.0), 0.0, minf(3.0, w), bar.size.y), Color.WHITE))
		col.add_child(bar)
	return col

## A dark midnight gradient across the top or bottom so the type reads on any still.
func _shade(bottom: bool) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.03, 0.09, 0.0))
	g.set_color(1, Color(0.02, 0.03, 0.09, 0.86 if bottom else 0.60))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 4
	tex.height = 128
	tex.fill_from = Vector2(0, 0) if bottom else Vector2(0, 1)
	tex.fill_to = Vector2(0, 1) if bottom else Vector2(0, 0)
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.anchor_right = 1.0
	if bottom:
		r.anchor_top = 0.60
		r.anchor_bottom = 1.0
	else:
		r.anchor_bottom = 0.32
	return r

## A dark fade across the left third, under the place name and the car's figures, so the type reads on a bright still.
func _side_shade() -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.03, 0.09, 0.56))
	g.set_color(1, Color(0.02, 0.03, 0.09, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 128
	tex.height = 4
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(1, 0)
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.anchor_bottom = 1.0
	r.anchor_right = 0.55
	return r

static func _label(text: String, size: int, color: Color, weight := 700, italic := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", HudLayout.italic_font(weight) if italic else CmrStyle.font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.72))
	l.add_theme_constant_override("outline_size", maxi(3, size / 8))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
