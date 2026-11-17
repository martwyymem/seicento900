## The garage: one screen for choosing the car and its factory paint, opened from the race set-up's CAR & PAINT field and
## from the open world's pause menu (CAR). Every catalogue car is listed; the chosen one turns on a stand in its paint,
## with its measured figures as bars (so cars compare at a glance) and its palette as swatches named after the real
## paint. A locked car is shown dimmed with how it is won. Controller first: ↑ ↓ / LB RB car, ◂ ▸ paint, A choose, B back
## (the keys: ↑ ↓ or Q E, ← →, Enter, Esc). The caller hears `chosen(key, color)` or `closed` and the screen frees itself.
class_name Garage
extends Control

signal chosen(car_key: String, paint: Color)
signal closed

const CAR_SCENE := preload("res://scripts/ui/race_car_visual.tscn")
const ROW_H := 44.0
const SPIN := 0.35 ## rad/s of the turntable

var cars: Array[String] = []
var car_index := 0
var paint_index := 0
var fans := -1
var look := {} ## the player's number, finish and stripes for the preview
var _paints := {} ## car key -> the paint index last shown for it here
var _view: SubViewport
var _view_box: SubViewportContainer
var _stand: Node3D
var _car: Node3D
var _name: Label
var _hint: Label
var _rows: VBoxContainer
var _bars: GridContainer
var _swatches: HFlowContainer
var _paint_name: Label
var _keys: Label
var _stick := [0, 0]
static var _figures := {}

## Opens the garage over `parent` on the car `key` in `paint`. look: {number, finish, stripes} for the preview.
static func open_in(parent: Node, key: String, paint: Color, fans_now := -1, look_opts := {}) -> Garage:
	var g := Garage.new()
	g.fans = fans_now
	g.look = look_opts
	g.cars.assign(CarCatalog.KEYS)
	g.car_index = maxi(0, g.cars.find(key))
	g._paints[key] = CarCatalog.nearest_paint(key, paint)
	g.paint_index = int(g._paints[key]) # (_select_car files paint_index under the car it opens on)
	parent.add_child(g)
	return g

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var back := ColorRect.new()
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.color = Color(CmrStyle.TINT_HOME, 0.98)
	add_child(back)
	_build_preview()
	_build_side()
	_select_car(car_index)

# --- the public steps (keys, pad, mouse and tests) ---

func current_key() -> String:
	return cars[car_index]

## The palette the player can pick from: a car with a fixed livery has only that one.
func paints() -> Array:
	var pal := CarCatalog.palette(current_key())
	return pal.slice(0, 1) if not CarCatalog.livery(current_key()).is_empty() else pal

func current_color() -> Color:
	return paints()[paint_index].color

func is_locked() -> bool:
	return not CarCatalog.unlocked(current_key(), fans)

## "The X is won by ...", or "" for an open car.
func hint_text() -> String:
	if not is_locked():
		return ""
	return "LOCKED · The %s %s." % [CarCatalog.display_name(current_key()), CarCatalog.unlock_hint(current_key())]

func step_car(d: int) -> void:
	_select_car(posmod(car_index + d, cars.size()))

func step_paint(d: int) -> void:
	_select_paint(posmod(paint_index + d, paints().size()))

## A: takes the car and paint (a locked car only flashes how it is won).
func choose() -> bool:
	if is_locked():
		_hint.modulate = Color(1.6, 1.6, 1.6)
		create_tween().tween_property(_hint, "modulate", Color.WHITE, 0.4)
		return false
	var col := current_color()
	if CarCatalog.livery(current_key()).is_empty():
		CarCatalog.save_paint(current_key(), col)
	chosen.emit(current_key(), col)
	_close()
	return true

func cancel() -> void:
	closed.emit()
	_close()

func _close() -> void:
	set_process_input(false)
	queue_free()

# --- input: modal, ahead of the menus underneath ---

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventJoypadMotion:
		_stick_motion(event as InputEventJoypadMotion)
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey or event is InputEventJoypadButton):
		return
	if event is InputEventKey and (event.ctrl_pressed or event.meta_pressed or event.alt_pressed):
		return
	get_viewport().set_input_as_handled()
	if not event.is_pressed():
		return
	var key: Key = event.keycode if event is InputEventKey else KEY_NONE
	var pad: JoyButton = event.button_index if event is InputEventJoypadButton else JOY_BUTTON_INVALID
	var echo: bool = event.is_echo()
	if key in [KEY_UP, KEY_Q, KEY_PAGEUP] or pad in [JOY_BUTTON_DPAD_UP, JOY_BUTTON_LEFT_SHOULDER]:
		step_car(-1)
	elif key in [KEY_DOWN, KEY_E, KEY_PAGEDOWN] or pad in [JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_RIGHT_SHOULDER]:
		step_car(1)
	elif key == KEY_LEFT or pad == JOY_BUTTON_DPAD_LEFT:
		step_paint(-1)
	elif key == KEY_RIGHT or pad == JOY_BUTTON_DPAD_RIGHT:
		step_paint(1)
	elif not echo and (key in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] or pad in [JOY_BUTTON_A, JOY_BUTTON_START]):
		choose()
	elif not echo and (key in [KEY_ESCAPE, KEY_BACKSPACE] or pad == JOY_BUTTON_B):
		cancel()

## The left stick as the d-pad: one step each time it is pushed past half way.
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
		step_paint(dir)
	else:
		step_car(dir)

func _process(delta: float) -> void:
	if _stand:
		_stand.rotation.y += SPIN * delta

# --- what is shown ---

func _select_car(i: int) -> void:
	_paints[current_key()] = paint_index
	car_index = i
	var key := current_key()
	if not _paints.has(key):
		_paints[key] = CarCatalog.nearest_paint(key, CarCatalog.saved_paint(key, CarCatalog.palette(key)[0].color))
	paint_index = clampi(int(_paints[key]), 0, paints().size() - 1)
	if _car:
		_car.call("set_car", key)
		var liv := CarCatalog.livery(key)
		_car.set("car_number", int(liv.get("number", look.get("number", 9))))
		_car.call("set_livery", int(liv.get("finish", look.get("finish", 0))))
		_car.call("set_stripes", bool(liv.get("stripes", look.get("stripes", false))))
	_view_box.modulate = Color(0.32, 0.32, 0.38) if is_locked() else Color.WHITE
	_name.text = CarCatalog.display_name(key).to_upper()
	_hint.text = hint_text()
	_hint.visible = is_locked()
	for k in _rows.get_child_count():
		_style_row(_rows.get_child(k) as Button, k == car_index, not CarCatalog.unlocked(cars[k], fans))
	_fill_bars()
	_fill_swatches()
	_select_paint(paint_index)

func _select_paint(i: int) -> void:
	paint_index = i
	_paints[current_key()] = i
	var pal := paints()
	var fixed := not CarCatalog.livery(current_key()).is_empty()
	_paint_name.text = "%s%s" % [String(pal[i].name), "  ·  fixed livery" if fixed else "  ·  %d / %d" % [i + 1, pal.size()]]
	for k in _swatches.get_child_count():
		_style_swatch(_swatches.get_child(k) as Button, pal[k].color, k == i)
	if _car:
		_car.call("set_paint", current_color())

## Power and weight from the spec (OpenWorldCover.car_stats), 0-100 and top speed as measured (CarCatalog.FIGURES).
static func figures(key: String) -> Dictionary:
	if not _figures.has(key):
		var sp := CarCatalog.spec(key)
		var st := OpenWorldCover.car_stats(sp)
		var fig: Array = CarCatalog.FIGURES.get(key, [0.0, float(st.top_kmh)])
		_figures[key] = {"hp": float(st.hp), "kg": float(st.kg), "t100": float(fig[0]), "top": float(fig[1]), "drive": "AWD" if sp.awd else "FWD"}
	return _figures[key]

func _fill_bars() -> void:
	for c in _bars.get_children():
		c.queue_free()
	var best := {"hp": 0.0, "kg": 0.0, "t100": INF, "top": 0.0}
	for k in cars:
		var f := figures(k)
		best.hp = maxf(best.hp, f.hp)
		best.kg = maxf(best.kg, f.kg)
		best.top = maxf(best.top, f.top)
		if f.t100 > 0.0:
			best.t100 = minf(best.t100, f.t100)
	var me := figures(current_key())
	# [caption, value, fill against the best in the catalogue]; power on a square-root scale so road cars still read
	var rows := [["POWER", "%d hp" % roundi(me.hp), sqrt(me.hp / best.hp)], ["WEIGHT", "%d kg" % roundi(me.kg), me.kg / best.kg],
		["0-100 KM/H", "%.1f s" % me.t100, best.t100 / me.t100 if me.t100 > 0.0 else 0.0],
		["TOP SPEED", "%d km/h" % roundi(me.top), me.top / best.top], ["DRIVE", String(me.drive), -1.0]]
	for r in rows:
		_bars.add_child(_text(String(r[0]), 14, CmrStyle.MUTED, 800))
		var bar := _Bar.new()
		bar.fill = float(r[2])
		bar.custom_minimum_size = Vector2(150, 12)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.visible = float(r[2]) >= 0.0
		_bars.add_child(bar)
		var v := _text(String(r[1]), 20, CmrStyle.TEXT, 800)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.custom_minimum_size.x = 96
		_bars.add_child(v)

func _fill_swatches() -> void:
	for c in _swatches.get_children():
		_swatches.remove_child(c)
		c.queue_free()
	var pal := paints()
	for k in pal.size():
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(44, 34)
		b.tooltip_text = String(pal[k].name)
		b.pressed.connect(func() -> void: _select_paint(k))
		_swatches.add_child(b)

func _style_swatch(b: Button, col: Color, on: bool) -> void:
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = col
		sb.border_color = CmrStyle.FOCUS if on else Color(CmrStyle.TEXT, 0.35)
		sb.set_border_width_all(4 if on else 1)
		sb.set_corner_radius_all(int(CmrStyle._skin().radius) / 2)
		b.add_theme_stylebox_override(state, sb)

func _style_row(b: Button, on: bool, locked: bool) -> void:
	var col := CmrStyle.ORANGE if on else Color(0, 0, 0, 0)
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := CmrStyle.box(col, Color(0, 0, 0, 0), 14.0, 4.0)
		b.add_theme_stylebox_override(state, sb)
	var fg := CmrStyle.INK if on else (CmrStyle.DIM if locked else CmrStyle.TEXT)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, fg)
	b.text = CarCatalog.display_name(cars[_rows.get_children().find(b)]) + ("   ·   LOCKED" if locked else "")

# --- building ---

func _build_preview() -> void:
	_view_box = SubViewportContainer.new()
	_view_box.stretch = true
	_view_box.anchor_left = 0.0
	_view_box.anchor_top = 0.1
	_view_box.anchor_right = 0.57
	_view_box.anchor_bottom = 0.8
	_view_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_view_box)
	_view = SubViewport.new()
	_view.own_world_3d = true
	_view.transparent_bg = true
	_view.msaa_3d = Viewport.MSAA_4X
	_view_box.add_child(_view)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#e6e2ee")
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	_view.add_child(env)
	_stand = Node3D.new()
	_stand.rotation.y = deg_to_rad(-30.0)
	_view.add_child(_stand)
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 2.8
	cyl.bottom_radius = 2.8
	cyl.height = 0.02
	cyl.radial_segments = 64
	disc.mesh = cyl
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0, 0, 0, 0.28)
	disc.material_override = m
	disc.position.y = -0.01
	_stand.add_child(disc)
	_car = CAR_SCENE.instantiate()
	_car.set("car_key", current_key())
	_stand.add_child(_car)
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-40, -35, 0)
	key_light.light_energy = 1.1
	key_light.shadow_enabled = true
	_view.add_child(key_light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, 150, 0)
	fill.light_energy = 0.5
	_view.add_child(fill)
	var cam := Camera3D.new()
	cam.fov = 30.0
	_view.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 2.3, 8.2), Vector3(0, 0.5, 0), Vector3.UP)
	cam.current = true

	var title := _text("GARAGE", 40, CmrStyle.TEXT, 900)
	title.add_theme_font_override("font", CmrStyle.title_font())
	title.position = Vector2(64, 30)
	add_child(title)
	# the name and how a locked car is won, under the stand
	var under := VBoxContainer.new()
	under.anchor_left = 0.04
	under.anchor_right = 0.55
	under.anchor_top = 0.8
	under.anchor_bottom = 0.95
	under.add_theme_constant_override("separation", 4)
	add_child(under)
	_name = _text("", 34, CmrStyle.TEXT, 900)
	_name.clip_text = true
	under.add_child(_name)
	_hint = _text("", 17, CmrStyle.AMBER, 700)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	under.add_child(_hint)

func _build_side() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", CmrStyle.panel(CmrStyle.PANEL, CmrStyle.PANEL_EDGE, 24.0))
	panel.anchor_left = 0.585
	panel.anchor_right = 0.96
	panel.anchor_top = 0.07
	panel.anchor_bottom = 0.88
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	col.add_child(_text("CAR", 14, CmrStyle.MUTED, 800))
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 2)
	col.add_child(_rows)
	for k in cars.size():
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = ROW_H
		b.add_theme_font_override("font", CmrStyle.font(800))
		b.add_theme_font_size_override("font_size", 19)
		b.clip_text = true
		b.pressed.connect(func() -> void: _select_car(k))
		_rows.add_child(b)
	col.add_child(_rule())
	_bars = GridContainer.new()
	_bars.columns = 3
	_bars.add_theme_constant_override("h_separation", 14)
	_bars.add_theme_constant_override("v_separation", 8)
	col.add_child(_bars)
	col.add_child(_rule())
	col.add_child(_text("PAINT", 14, CmrStyle.MUTED, 800))
	_swatches = HFlowContainer.new()
	_swatches.add_theme_constant_override("h_separation", 6)
	_swatches.add_theme_constant_override("v_separation", 6)
	col.add_child(_swatches)
	_paint_name = _text("", 20, CmrStyle.TEXT, 800)
	_paint_name.clip_text = true
	col.add_child(_paint_name)
	# the keys along the bottom
	_keys = _text("", 18, CmrStyle.MUTED, 700)
	_keys.anchor_left = 0.585
	_keys.anchor_right = 0.96
	_keys.anchor_top = 0.9
	_keys.anchor_bottom = 0.96
	_keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_keys.text = "LB RB car   ◂ ▸ paint   Ⓐ choose   Ⓑ back" if not Input.get_connected_joypads().is_empty() else "↑ ↓ car   ← → paint   Enter choose   Esc back"
	add_child(_keys)

func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(CmrStyle.TEXT, 0.25)
	r.custom_minimum_size.y = 2
	return r

static func _text(t: String, size: int, color: Color, weight := 700) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", CmrStyle.font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## A figure's bar: the track and the lit part, in the skin's accent.
class _Bar extends Control:
	var fill := 0.0
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(CmrStyle.TEXT, 0.15))
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * clampf(fill, 0.04, 1.0), size.y)), CmrStyle.ORANGE)
