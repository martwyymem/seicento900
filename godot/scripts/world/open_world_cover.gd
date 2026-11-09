## The open world's loading screen, after Forza Horizon's: a still of the Seicento parked somewhere in Brzeszcze in
## good light (pre-rendered by tests/_cover_shots.gd into textures/loading/), drifting in slowly, with the car's figures
## along the bottom and a spinner in the corner. It is only a picture and some labels, so it is up the moment the
## player asks for the world, while the town builds behind it.
class_name OpenWorldCover
extends Control

## [file under textures/loading/, place caption]
const SHOTS := [
	["ow_cover_1.jpg", "KWK Brzeszcze · the shaft at sundown"],
	["ow_cover_2.jpg", "ul. Bór · Brzeszcze-Bór"],
	["ow_cover_3.jpg", "S1 · dusk towards Wilamowice"],
]
const ACCENT := Color("#ff4fa3") ## the festival pink of the open-world HUD's highlights
const DRIFT_TIME := 14.0 ## s for the slow zoom across the still
## Forza-style performance classes by index: [top of the band, letter, colour]
const CLASSES := [[500, "D", Color("#3fa7d6")], [600, "C", Color("#f2c14e")], [700, "B", Color("#f78154")],
	[800, "A", Color("#e4572e")], [900, "S1", Color("#9d4edd")], [998, "S2", Color("#3a86ff")], [999, "X", Color("#2ec4b6")]]

var shot := 0
var _photo: TextureRect
var _fallback: ColorRect
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

	# top left: where we are
	var top := VBoxContainer.new()
	top.position = Vector2(56, 44)
	top.add_theme_constant_override("separation", 0)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	top.add_child(_label("BRZESZCZE", 54, Color.WHITE, 900))
	top.add_child(_label("SEICENTO FEST · OPEN ROAD", 16, ACCENT, 800))
	_place = _label("", 15, Color(1, 1, 1, 0.8), 600)
	top.add_child(_place)

	# bottom left: the car and its figures
	var car := VBoxContainer.new()
	car.anchor_top = 1.0
	car.anchor_bottom = 1.0
	car.grow_vertical = Control.GROW_DIRECTION_BEGIN
	car.offset_left = 56
	car.offset_bottom = -48
	car.add_theme_constant_override("separation", 10)
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
	_badge_letter = _label("D", 20, Color.WHITE, 900)
	_badge_letter.custom_minimum_size.x = 38
	_badge_letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge_number = _label("100", 20, Color.BLACK, 800)
	_badge_number.custom_minimum_size.x = 52
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
	_car_name = _label("", 40, Color.WHITE, 900)
	name_row.add_child(_car_name)
	_stats_row = HBoxContainer.new()
	_stats_row.add_theme_constant_override("separation", 30)
	_stats_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	car.add_child(_stats_row)

	# bottom right: what is building and the spinner
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
	_status = _label("", 15, Color(1, 1, 1, 0.75), 600)
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	corner.add_child(_status)
	_spinner = Control.new()
	_spinner.custom_minimum_size = Vector2(46, 46)
	_spinner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spinner.draw.connect(_draw_spinner)
	corner.add_child(_spinner)

	var credit := _label("Map data © OpenStreetMap contributors · Elevation EU-DEM", 11, Color(1, 1, 1, 0.4), 500)
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

## Shows the cover with one of the stills (-1: pick one at random) and the figures of the car the player drives.
func open(spec: CarSpec, car_name: String, index := -1) -> void:
	shot = randi() % SHOTS.size() if index < 0 else clampi(index, 0, SHOTS.size() - 1)
	var path := "res://textures/loading/%s" % SHOTS[shot][0]
	_photo.texture = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_place.text = String(SHOTS[shot][1])
	_car_name.text = car_name.to_upper()
	var st := car_stats(spec)
	var cls := perf_class(st)
	_badge_letter.text = String(cls[0])
	_badge_number.text = str(cls[1])
	var sb := StyleBoxFlat.new()
	sb.bg_color = cls[2]
	sb.border_color = cls[2]
	sb.set_border_width_all(2)
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
	set_status("", 0.0)
	show()

## The menu skin changed: the plain backdrop behind a missing still follows it.
func restyle() -> void:
	_fallback.color = CmrStyle.TINT_HOME

## The line beside the spinner: the step that is building now.
func set_status(text: String, _fraction: float) -> void:
	_status.text = text.to_lower()

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
	var r := minf(c.x, c.y) - 3.0
	_spinner.draw_arc(c, r, 0.0, TAU, 48, Color(1, 1, 1, 0.18), 3.0, true)
	var sweep := 1.6 + 1.1 * sin(_spin * 0.5)
	_spinner.draw_arc(c, r, _spin, _spin + sweep, 32, ACCENT, 4.0, true)
	_spinner.draw_arc(c, r * 0.55, -_spin * 1.4, -_spin * 1.4 + 1.4, 24, Color.WHITE, 3.0, true)

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
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_label(caption, 12, Color(1, 1, 1, 0.65), 800))
	col.add_child(_label(value, 24, Color.WHITE, 800))
	if fill >= 0.0:
		var bar := ColorRect.new()
		bar.color = Color(1, 1, 1, 0.2)
		bar.custom_minimum_size = Vector2(110, 4)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lit := ColorRect.new()
		lit.color = ACCENT
		lit.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lit.size = Vector2(110.0 * clampf(fill, 0.04, 1.0), 4)
		bar.add_child(lit)
		col.add_child(bar)
	return col

## A dark gradient across the top or bottom so the type reads on any still.
func _shade(bottom: bool) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.0))
	g.set_color(1, Color(0, 0, 0, 0.82 if bottom else 0.55))
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
		r.anchor_top = 0.62
		r.anchor_bottom = 1.0
	else:
		r.anchor_bottom = 0.3
	return r

## A dark fade across the left third, under the place name and the car's figures, so the type reads on a bright still.
func _side_shade() -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.5))
	g.set_color(1, Color(0, 0, 0, 0.0))
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

static func _label(text: String, size: int, color: Color, weight := 700) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", CmrStyle.font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("outline_size", maxi(3, size / 8))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
