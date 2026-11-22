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
const ROW_H := 38.0
const SPIN := 0.35 ## rad/s of the turntable

var cars: Array[String] = []
var car_index := 0
var paint_index := 0
var fans := -1
var look := {} ## the player's number, finish and stripes for the preview
var _paints := {} ## car key -> the paint index last shown for it here
var _back: ColorRect
var _bg_glow: Control
var _view: SubViewport
var _view_box: SubViewportContainer
var _stand: Node3D
var _car: Node3D
var _ring_outer_mat: StandardMaterial3D
var _ring_inner_mat: StandardMaterial3D
var _rim_cyan: OmniLight3D
var _rim_hot: OmniLight3D
var _title_lbl: Label
var _name: Label
var _hint: Label
var _side_panel: PanelContainer
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
	_back = ColorRect.new()
	_back.set_anchors_preset(Control.PRESET_FULL_RECT)
	_back.color = Color(CmrStyle.TINT_HOME, 0.99)
	add_child(_back)
	_bg_glow = Control.new()
	_bg_glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_glow.draw.connect(_draw_backdrop)
	add_child(_bg_glow)
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
	_view_box.modulate = Color(0.42, 0.44, 0.50) if is_locked() else Color.WHITE
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
		_bars.add_child(_text(String(r[0]), 13, HudLayout.neon_primary(), 800, true))
		var bar := _Bar.new()
		bar.fill = float(r[2])
		bar.custom_minimum_size = Vector2(150, 12)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.visible = float(r[2]) >= 0.0
		_bars.add_child(bar)
		var v := _text(String(r[1]), 19, Color.WHITE, 900, true)
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
		b.custom_minimum_size = Vector2(40, 30)
		b.tooltip_text = String(pal[k].name)
		b.pressed.connect(func() -> void: _select_paint(k))
		_swatches.add_child(b)

func _style_swatch(b: Button, col: Color, on: bool) -> void:
	var hot := HudLayout.neon_hot()
	var is_ps1 := CmrStyle.skin == "ps1"
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = col
		sb.border_color = hot if on else Color(HudLayout.neon_primary(), 0.35)
		sb.set_border_width_all(3 if on else 1)
		sb.set_corner_radius_all(0 if is_ps1 else 4)
		if on and not is_ps1:
			sb.shadow_color = Color(hot, 0.55)
			sb.shadow_size = 8
		b.add_theme_stylebox_override(state, sb)

func _style_row(b: Button, on: bool, locked: bool) -> void:
	var neon := HudLayout.neon_primary()
	var hot := HudLayout.neon_hot()
	var is_ps1 := CmrStyle.skin == "ps1"
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		if on and not locked:
			sb.bg_color = neon
			sb.border_color = hot
			sb.border_width_left = 6
			sb.border_width_top = 1
			sb.border_width_right = 1
			sb.border_width_bottom = 1
			if not is_ps1:
				sb.shadow_color = Color(neon, 0.42)
				sb.shadow_size = 10
		elif on and locked:
			sb.bg_color = Color(hot, 0.24)
			sb.border_color = hot
			sb.border_width_left = 6
			sb.border_width_top = 1
			sb.border_width_right = 1
			sb.border_width_bottom = 1
			if not is_ps1:
				sb.shadow_color = Color(hot, 0.36)
				sb.shadow_size = 8
		else:
			sb.bg_color = HudLayout.glass_plate(0.45 if state == "normal" else 0.72)
			sb.border_color = Color(neon, 0.20 if state == "normal" else 0.55)
			sb.border_width_left = 3
			sb.border_width_bottom = 1
		sb.set_corner_radius_all(0 if is_ps1 else 3)
		sb.content_margin_left = 14.0
		sb.content_margin_right = 12.0
		sb.content_margin_top = 3.0
		sb.content_margin_bottom = 3.0
		b.add_theme_stylebox_override(state, sb)
	var fg := CmrStyle.INK if (on and not locked) else (Color.WHITE if on else (Color(CmrStyle.MUTED, 0.78) if locked else CmrStyle.TEXT))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, fg)
	b.add_theme_font_override("font", HudLayout.italic_font(900 if on else 700, -0.10))
	b.text = CarCatalog.display_name(cars[_rows.get_children().find(b)]) + ("   ·   LOCKED" if locked else "")

# --- building ---

func _draw_backdrop() -> void:
	if CmrStyle.skin == "ps1" or size.x < 2.0:
		return
	var neon := HudLayout.neon_primary()
	var hot := HudLayout.neon_hot()
	# silky neon showroom atmospheric wash behind the turntable
	var center := Vector2(size.x * 0.285, size.y * 0.48)
	HudLayout.draw_radial_glow(_bg_glow, center + Vector2(-size.x * 0.10, -size.y * 0.08), size.y * 0.62, Color(neon, 0.20))
	HudLayout.draw_radial_glow(_bg_glow, center + Vector2(size.x * 0.12, size.y * 0.08), size.y * 0.56, Color(hot, 0.22))
	# sleek top/bottom neon accent lines
	_bg_glow.draw_rect(Rect2(0.0, 0.0, size.x, 3.0), Color(neon, 0.75))
	_bg_glow.draw_rect(Rect2(0.0, size.y - 3.0, size.x, 3.0), Color(hot, 0.75))

func _build_preview() -> void:
	var neon := HudLayout.neon_primary()
	var hot := HudLayout.neon_hot()
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
	e.ambient_light_color = Color("#b8c8ee")
	e.ambient_light_energy = 0.52
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = GfxFx.bloom
	e.glow_intensity = 0.7
	e.glow_bloom = 0.25
	e.glow_hdr_threshold = 1.0
	env.environment = e
	_view.add_child(env)
	_stand = Node3D.new()
	_stand.rotation.y = deg_to_rad(145.0)
	_view.add_child(_stand)

	# satin metallic dark showroom turntable podium
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 2.74
	cyl.bottom_radius = 2.86
	cyl.height = 0.09
	cyl.radial_segments = 64
	disc.mesh = cyl
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#080c18")
	m.metallic = 0.55
	m.roughness = 0.42
	disc.material_override = m
	disc.position.y = -0.046
	_stand.add_child(disc)

	# outer glowing neon cyan turntable rim
	var outer_ring := MeshInstance3D.new()
	var outer_torus := TorusMesh.new()
	outer_torus.inner_radius = 2.66
	outer_torus.outer_radius = 2.78
	outer_torus.rings = 64
	outer_torus.ring_segments = 16
	outer_ring.mesh = outer_torus
	_ring_outer_mat = StandardMaterial3D.new()
	_ring_outer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_outer_mat.albedo_color = neon * 2.4
	outer_ring.material_override = _ring_outer_mat
	outer_ring.position.y = 0.002
	_stand.add_child(outer_ring)

	# inner glowing hot-magenta turntable accent ring
	var inner_ring := MeshInstance3D.new()
	var inner_torus := TorusMesh.new()
	inner_torus.inner_radius = 2.02
	inner_torus.outer_radius = 2.07
	inner_torus.rings = 64
	inner_torus.ring_segments = 12
	inner_ring.mesh = inner_torus
	_ring_inner_mat = StandardMaterial3D.new()
	_ring_inner_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_inner_mat.albedo_color = hot * 2.0
	inner_ring.material_override = _ring_inner_mat
	inner_ring.position.y = 0.003
	_stand.add_child(inner_ring)

	_car = CAR_SCENE.instantiate()
	_car.set("car_key", current_key())
	_stand.add_child(_car)

	# studio key light (keeps factory paint colours true) + cyan/magenta neon rim lights
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-44, -32, 0)
	key_light.light_color = Color("#f2f7ff")
	key_light.light_energy = 1.05
	key_light.shadow_enabled = true
	_view.add_child(key_light)

	_rim_cyan = OmniLight3D.new()
	_rim_cyan.position = Vector3(-3.8, 1.9, 2.2)
	_rim_cyan.light_color = neon
	_rim_cyan.light_energy = 4.2
	_rim_cyan.omni_range = 12.0
	_view.add_child(_rim_cyan)

	_rim_hot = OmniLight3D.new()
	_rim_hot.position = Vector3(3.8, 1.8, -2.4)
	_rim_hot.light_color = hot
	_rim_hot.light_energy = 4.2
	_rim_hot.omni_range = 12.0
	_view.add_child(_rim_hot)

	var under_glow := OmniLight3D.new()
	under_glow.position = Vector3(0.0, 0.32, 1.6)
	under_glow.light_color = neon.lerp(hot, 0.35)
	under_glow.light_energy = 1.4
	under_glow.omni_range = 6.0
	_view.add_child(under_glow)

	var cam := Camera3D.new()
	cam.fov = 30.0
	_view.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 2.3, 8.2), Vector3(0, 0.5, 0), Vector3.UP)
	cam.current = true

	_title_lbl = _text("GARAGE", 42, Color.WHITE, 900, true)
	if CmrStyle.skin != "ps1":
		_title_lbl.add_theme_color_override("font_outline_color", Color(neon, 0.40))
		_title_lbl.add_theme_constant_override("outline_size", 6)
	_title_lbl.position = Vector2(56, 26)
	add_child(_title_lbl)
	# the name and how a locked car is won, under the stand
	var under := VBoxContainer.new()
	under.anchor_left = 0.04
	under.anchor_right = 0.55
	under.anchor_top = 0.8
	under.anchor_bottom = 0.95
	under.add_theme_constant_override("separation", 4)
	add_child(under)
	_name = _text("", 34, Color.WHITE, 900, true)
	_name.clip_text = true
	if CmrStyle.skin != "ps1":
		_name.add_theme_color_override("font_outline_color", Color(neon, 0.32))
		_name.add_theme_constant_override("outline_size", 5)
	under.add_child(_name)
	_hint = _text("", 17, HudLayout.neon_boost(), 800, true)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	under.add_child(_hint)

func _build_side() -> void:
	_side_panel = PanelContainer.new()
	_side_panel.add_theme_stylebox_override("panel", _side_panel_style())
	_side_panel.anchor_left = 0.585
	_side_panel.anchor_right = 0.96
	_side_panel.anchor_top = 0.055
	_side_panel.anchor_bottom = 0.895
	add_child(_side_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_side_panel.add_child(col)
	col.add_child(_text("CAR", 13, HudLayout.neon_primary(), 900, true))
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 2)
	col.add_child(_rows)
	for k in cars.size():
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = ROW_H
		b.add_theme_font_override("font", HudLayout.italic_font(800, -0.10))
		b.add_theme_font_size_override("font_size", 18)
		b.clip_text = true
		b.pressed.connect(func() -> void: _select_car(k))
		_rows.add_child(b)
	col.add_child(_rule())
	_bars = GridContainer.new()
	_bars.columns = 3
	_bars.add_theme_constant_override("h_separation", 14)
	_bars.add_theme_constant_override("v_separation", 6)
	col.add_child(_bars)
	col.add_child(_rule())
	col.add_child(_text("PAINT", 13, HudLayout.neon_primary(), 900, true))
	_swatches = HFlowContainer.new()
	_swatches.add_theme_constant_override("h_separation", 6)
	_swatches.add_theme_constant_override("v_separation", 6)
	col.add_child(_swatches)
	_paint_name = _text("", 19, Color.WHITE, 900, true)
	_paint_name.clip_text = true
	col.add_child(_paint_name)
	# the keys along the bottom
	_keys = _text("", 17, HudLayout.neon_primary().lightened(0.32), 700, true)
	_keys.anchor_left = 0.585
	_keys.anchor_right = 0.96
	_keys.anchor_top = 0.91
	_keys.anchor_bottom = 0.97
	_keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_keys.text = "LB RB car   ◂ ▸ paint   Ⓐ choose   Ⓑ back" if not Input.get_connected_joypads().is_empty() else "↑ ↓ car   ← → paint   Enter choose   Esc back"
	add_child(_keys)

func _side_panel_style() -> StyleBoxFlat:
	var sb := HudLayout.neon_box(HudLayout.neon_primary(), 0.90, 5, 0.0, 14, 20.0, 14.0)
	sb.bg_color = HudLayout.glass_plate(0.90)
	return sb

func _skin_changed() -> void:
	var neon := HudLayout.neon_primary()
	var hot := HudLayout.neon_hot()
	if is_instance_valid(_back):
		_back.color = Color(CmrStyle.TINT_HOME, 0.99)
	if is_instance_valid(_bg_glow):
		_bg_glow.queue_redraw()
	if is_instance_valid(_side_panel):
		_side_panel.add_theme_stylebox_override("panel", _side_panel_style())
	if _ring_outer_mat:
		_ring_outer_mat.albedo_color = neon * 2.4
	if _ring_inner_mat:
		_ring_inner_mat.albedo_color = hot * 2.0
	if is_instance_valid(_rim_cyan):
		_rim_cyan.light_color = neon
	if is_instance_valid(_rim_hot):
		_rim_hot.light_color = hot
	var is_ps1 := CmrStyle.skin == "ps1"
	if is_instance_valid(_title_lbl):
		_title_lbl.add_theme_font_override("font", HudLayout.italic_font(900))
		_title_lbl.add_theme_color_override("font_outline_color", Color(neon, 0.40))
		_title_lbl.add_theme_constant_override("outline_size", 0 if is_ps1 else 6)
	if is_instance_valid(_name):
		_name.add_theme_font_override("font", HudLayout.italic_font(900))
		_name.add_theme_color_override("font_outline_color", Color(neon, 0.32))
		_name.add_theme_constant_override("outline_size", 0 if is_ps1 else 5)
	if is_instance_valid(_hint):
		_hint.add_theme_font_override("font", HudLayout.italic_font(800))
		_hint.add_theme_color_override("font_color", HudLayout.neon_boost())
	if is_instance_valid(_paint_name):
		_paint_name.add_theme_font_override("font", HudLayout.italic_font(900))
	if is_instance_valid(_keys):
		_keys.add_theme_font_override("font", HudLayout.italic_font(700))
		_keys.add_theme_color_override("font_color", neon.lightened(0.32))
	if is_instance_valid(_rows):
		for k in _rows.get_child_count():
			_style_row(_rows.get_child(k) as Button, k == car_index, not CarCatalog.unlocked(cars[k], fans))
	if is_instance_valid(_bars):
		_fill_bars()
	if is_instance_valid(_swatches):
		var pal := paints()
		for k in _swatches.get_child_count():
			_style_swatch(_swatches.get_child(k) as Button, pal[k].color, k == paint_index)

func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(HudLayout.neon_primary(), 0.45)
	r.custom_minimum_size.y = 2
	return r

static func _text(t: String, size: int, color: Color, weight := 700, italic := false) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", HudLayout.italic_font(weight) if italic else CmrStyle.font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## A figure's neon bar: dark glass track and glowing cyan-to-magenta fill.
class _Bar extends Control:
	var fill := 0.0
	func _draw() -> void:
		var neon := HudLayout.neon_primary()
		var hot := HudLayout.neon_hot()
		var f := clampf(fill, 0.04, 1.0)
		draw_rect(Rect2(Vector2.ZERO, size), HudLayout.glass_plate(0.85))
		draw_rect(Rect2(Vector2.ZERO, size), Color(neon, 0.35), false, 1.0)
		var w := size.x * f
		if CmrStyle.skin != "ps1":
			draw_rect(Rect2(0.0, -2.0, w, size.y + 4.0), Color(neon, 0.24))
		draw_rect(Rect2(0.0, 0.0, w, size.y), neon.lerp(hot, f * 0.55))
		draw_rect(Rect2(maxf(0.0, w - 3.0), 0.0, minf(3.0, w), size.y), Color.WHITE)
