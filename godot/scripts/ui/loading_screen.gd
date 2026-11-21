## The race and stage loading screen: Colin McRae Rally 2.0's "loading | circuit | race" in thin lowercase type split by
## hairlines and a row of blocks that fill as it loads, over a hero still of the stock Seicento on that circuit's grid at
## a flattering hour (pre-rendered from the race world by tests/_loading_shots.gd into textures/loading/hero_<key>.jpg).
## It is only a picture and some labels, so it is up the moment the race is asked for, while the circuit builds behind it.
## A circuit without a still keeps the flat tint of the menu skin.
class_name LoadingScreen
extends ColorRect

const BLOCKS := 12
const HERO_DIR := "res://textures/loading/"
const DRIFT_TIME := 26.0 ## s for the slow push-in across the still
const NIGHT_FROM := 20.5 ## the clock hours that take a circuit's night still, where it has one
const NIGHT_TO := 5.5
const MARGIN := Vector2(64, 52) ## from the left/right and bottom edge of the canvas
const WEATHER_NAMES := {"dry": "Dry", "wet": "Wet", "snow": "Snow", "hail": "Hail", "fog": "Fog", "variable": "Variable"}

## One line of advice under the title: the general ones, then those for the weather, the night and the rally stages.
const TIPS_ANY := [
	"Sit in a car's slipstream on a straight to save fuel and gain speed; pull out early to pass.",
	"Tyres fade long before they are gone: when the car starts to slide mid-corner, plan your stop.",
	"Brake in a straight line, then ease off the pedal as you turn in; a car on the limit will not take both.",
	"Look through the corner to the exit, not at the kerb in front of you.",
	"A mandatory stop is a chance, not a penalty: a short queue in the pit lane can win a place.",
	"Yellow flags mean a car is stranded ahead: lift, and do not overtake.",
	"The racing line shows where a corner is fastest: brake on the outside, turn in late, clip the apex.",
	"A heavy tank is a slow car. Fuel burns off, and the car gets sharper every lap.",
	"A safety car bunches the field: save the tyres behind it and keep the gap to the car ahead.",
	"Kerbs are free road for a wheel, not for the whole car: a wide line over the paint costs grip.",
]
const TIPS_WET := [
	"Wet tarmac: brake earlier, steer and squeeze the throttle gently, and keep off the painted lines.",
	"The racing line dries first; a puddle in the apex is a good reason to take a different one.",
]
const TIPS_SNOW := [
	"Snow and ice: everything takes longer. Brake in a straight line, and be smooth with every input.",
	"On snow a gentle car goes faster than a fast one that is sliding.",
]
const TIPS_NIGHT := [
	"At night the headlights do not reach the corner: use the braking boards as landmarks.",
]
const TIPS_RALLY := [
	"Gravel and dirt move the car about: flick it into the corner and hold a slide with the throttle.",
	"Trust your co-driver's notes: the call tells you what is behind the crest.",
]

var _photo: TextureRect
var _vignette: Control
var _title: HBoxContainer
var _facts: HBoxContainer
var _tip_panel: PanelContainer
var _tip_tag: PanelContainer
var _tip_row: HBoxContainer
var _tip: Label
var _caption: Label
var _value: Label
var _bar_frame: PanelContainer
var _bar_glow: Control
var _blocks: Array[ColorRect] = []
var _progress := 0.0
var _t := 0.0
var BLOCK_ON: Color:
	get: return HudLayout.neon_primary()
var BLOCK_OFF: Color:
	get: return Color(HudLayout.neon_primary(), 0.16)

func _init() -> void:
	name = "LoadingScreen"
	color = CmrStyle.TINT_HOME
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP # nothing behind it can be clicked while the race builds
	process_mode = Node.PROCESS_MODE_ALWAYS
	clip_contents = true # the push-in scales the still past the screen

	_photo = TextureRect.new()
	_photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED # cropped to any aspect, never stretched
	_photo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_photo)
	add_child(_shade(true, 0.58, 0.0, 0.0, 0.30)) # top: midnight frame edge
	add_child(_shade(true, 0.0, 0.90, 0.48, 1.0)) # bottom: deep midnight glass under the type
	add_child(_shade(false, 0.62, 0.0, 0.0, 0.64)) # left: under the title block

	_vignette = Control.new()
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.draw.connect(_draw_vignette)
	add_child(_vignette)

	# bottom left: the title, the conditions and a tip
	var left := VBoxContainer.new()
	left.anchor_top = 1.0
	left.anchor_bottom = 1.0
	left.grow_vertical = Control.GROW_DIRECTION_BEGIN
	left.offset_left = MARGIN.x
	left.offset_bottom = -MARGIN.y
	left.add_theme_constant_override("separation", 18)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(left)
	_title = HBoxContainer.new()
	_title.add_theme_constant_override("separation", 14)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(_title)
	_facts = HBoxContainer.new()
	_facts.add_theme_constant_override("separation", 26)
	_facts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(_facts)

	_tip_panel = PanelContainer.new()
	_tip_panel.custom_minimum_size.x = 660
	_tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_panel.add_theme_stylebox_override("panel", _tip_box_style())
	left.add_child(_tip_panel)
	_tip_row = HBoxContainer.new()
	_tip_row.add_theme_constant_override("separation", 12)
	_tip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_panel.add_child(_tip_row)
	_tip_tag = PanelContainer.new()
	_tip_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_tip_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_tag.add_theme_stylebox_override("panel", _tip_tag_style())
	var tag_text := _text("TIP", 13, 900, HORIZONTAL_ALIGNMENT_LEFT, CmrStyle.INK, true)
	tag_text.add_theme_constant_override("shadow_offset_y", 0)
	_tip_tag.add_child(tag_text)
	_tip_row.add_child(_tip_tag)
	_tip = _text("", 16, 600, HORIZONTAL_ALIGNMENT_LEFT, Color(0.95, 0.98, 1.0, 0.96), false)
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tip_row.add_child(_tip)

	# bottom right: what the circuit is, and the glowing neon progress bar
	var corner := VBoxContainer.new()
	corner.add_theme_constant_override("separation", 4)
	corner.anchor_left = 1.0
	corner.anchor_right = 1.0
	corner.anchor_top = 1.0
	corner.anchor_bottom = 1.0
	corner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	corner.grow_vertical = Control.GROW_DIRECTION_BEGIN
	corner.offset_right = -MARGIN.x
	corner.offset_bottom = -MARGIN.y
	corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(corner)
	_caption = _text("", 15, 800, HORIZONTAL_ALIGNMENT_RIGHT, HudLayout.neon_primary(), true)
	_value = _text("", 24, 900, HORIZONTAL_ALIGNMENT_RIGHT, Color.WHITE, true)
	corner.add_child(_caption)
	corner.add_child(_value)

	_bar_frame = PanelContainer.new()
	_bar_frame.size_flags_horizontal = Control.SIZE_SHRINK_END
	_bar_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_frame.add_theme_stylebox_override("panel", _bar_frame_style())
	corner.add_child(_bar_frame)
	var bar_host := Control.new()
	bar_host.custom_minimum_size = Vector2(BLOCKS * 16 + (BLOCKS - 1) * 4, 18)
	bar_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_frame.add_child(bar_host)
	_bar_glow = Control.new()
	_bar_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bar_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_glow.draw.connect(_draw_bar_glow)
	bar_host.add_child(_bar_glow)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_host.add_child(row)
	for i in BLOCKS:
		var block := ColorRect.new()
		block.custom_minimum_size = Vector2(16, 18)
		block.color = BLOCK_OFF
		block.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(block)
		_blocks.append(block)
	hide()

## Name the stage and show the screen. `segments` follow "loading" in the title, `caption` and `value` are the two lines
## over the blocks in the corner. `info` (all optional) dresses the picture: "track" (the circuit's key, for its still),
## "hour" (the start time, for the night still and the clock), "weather", "mode" ("race", "rally" ...) and "facts"
## (an array of [caption, value] shown under the title; the weather and the clock are added when they are not in it).
func open(segments: Array, caption: String, value: String, info := {}) -> void:
	var neon := HudLayout.neon_primary()
	var hot := HudLayout.neon_hot()
	for child in _title.get_children():
		child.queue_free()
	var badge := PanelContainer.new()
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bsb := HudLayout.neon_box(hot, 0.94, 4, -0.14, 10, 14.0, 5.0)
	bsb.bg_color = hot
	badge.add_theme_stylebox_override("panel", bsb)
	var blbl := _text("LOADING", 20, 900, HORIZONTAL_ALIGNMENT_CENTER, Color.WHITE, true)
	blbl.add_theme_constant_override("shadow_offset_y", 0)
	badge.add_child(blbl)
	_title.add_child(badge)
	for i in segments.size():
		if i > 0:
			var rule := ColorRect.new()
			rule.color = neon
			rule.custom_minimum_size = Vector2(3, 36)
			rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_title.add_child(rule)
		var seg := _text(str(segments[i]).to_upper(), 40 if i == 0 else 30, 900 if i == 0 else 800,
			HORIZONTAL_ALIGNMENT_LEFT, Color.WHITE if i == 0 else neon.lightened(0.32), true)
		seg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if i == 0 and CmrStyle.skin != "ps1":
			seg.add_theme_color_override("font_outline_color", Color(neon, 0.35))
			seg.add_theme_constant_override("outline_size", 6)
		_title.add_child(seg)
	_caption.text = caption.to_upper()
	_caption.add_theme_color_override("font_color", neon)
	_value.text = value.to_upper()
	var hour := float(info.get("hour", -1.0))
	var weather := String(info.get("weather", ""))
	var path := hero_path(String(info.get("track", "")), hour, String(info.get("car", "stock")))
	_photo.texture = load(path) as Texture2D if path != "" else null
	_photo.visible = _photo.texture != null
	for child in _facts.get_children():
		child.queue_free()
	var facts: Array = (info.get("facts", []) as Array).duplicate()
	if weather != "":
		facts.append(["WEATHER", WEATHER_NAMES.get(weather, weather.capitalize())])
	if hour >= 0.0:
		facts.append(["START", clock_text(hour)])
	for fact in facts:
		_facts.add_child(_fact(String(fact[0]), String(fact[1])))
	_facts.visible = not facts.is_empty()
	_tip.text = pick_tip(weather, hour, String(info.get("mode", "race")))
	_t = 0.0
	restyle()
	set_progress(0.0)
	show()

## 0..1 along the row of blocks.
func set_progress(fraction: float) -> void:
	_progress = clampf(fraction, 0.0, 1.0)
	var lit := roundi(_progress * BLOCKS)
	for i in BLOCKS:
		_blocks[i].color = BLOCK_ON if i < lit else BLOCK_OFF
	if is_instance_valid(_bar_glow):
		_bar_glow.queue_redraw()

## The menu skin changed: backdrop, neon frames, glow and accents follow it.
func restyle() -> void:
	color = CmrStyle.TINT_HOME
	if is_instance_valid(_tip_panel):
		_tip_panel.add_theme_stylebox_override("panel", _tip_box_style())
	if is_instance_valid(_tip_tag):
		_tip_tag.add_theme_stylebox_override("panel", _tip_tag_style())
	if is_instance_valid(_bar_frame):
		_bar_frame.add_theme_stylebox_override("panel", _bar_frame_style())
	if is_instance_valid(_caption):
		_caption.add_theme_color_override("font_color", HudLayout.neon_primary())
		_caption.add_theme_font_override("font", HudLayout.italic_font(800))
	if is_instance_valid(_value):
		_value.add_theme_font_override("font", HudLayout.italic_font(900))
	if is_instance_valid(_vignette):
		_vignette.queue_redraw()
	set_progress(_progress)

func _skin_changed() -> void:
	restyle()

func _tip_box_style() -> StyleBoxFlat:
	var sb := HudLayout.neon_box(HudLayout.neon_primary(), 0.80, 4, -0.05, 8, 14.0, 8.0)
	sb.bg_color = HudLayout.glass_plate(0.82)
	return sb

func _tip_tag_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = HudLayout.neon_boost()
	sb.set_corner_radius_all(0 if CmrStyle.skin == "ps1" else 3)
	sb.skew = Vector2(0.0 if CmrStyle.skin == "ps1" else -0.14, 0.0)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	return sb

func _bar_frame_style() -> StyleBoxFlat:
	var sb := HudLayout.neon_box(HudLayout.neon_primary(), 0.84, 4, -0.10, 12, 10.0, 7.0)
	sb.bg_color = HudLayout.glass_plate(0.86)
	return sb

func _draw_bar_glow() -> void:
	if CmrStyle.skin == "ps1":
		return
	var lit := roundi(_progress * BLOCKS)
	if lit <= 0:
		return
	var neon := HudLayout.neon_primary()
	var hot := HudLayout.neon_hot()
	var step := 20.0
	for i in mini(lit, BLOCKS):
		var r := Rect2(i * step, 0.0, 16.0, 18.0)
		_bar_glow.draw_rect(r.grow(3.5), Color(neon, 0.24))
	var tip_r := Rect2((mini(lit, BLOCKS) - 1) * step, 0.0, 16.0, 18.0)
	_bar_glow.draw_rect(tip_r.grow(5.0), Color(hot, 0.30))

func _draw_vignette() -> void:
	if CmrStyle.skin == "ps1" or size.x < 2.0:
		return
	var neon := HudLayout.neon_primary()
	var hot := HudLayout.neon_hot()
	# subtle street-neon edge glow + thin frame hairlines
	_vignette.draw_rect(Rect2(0.0, 0.0, size.x, 3.0), Color(neon, 0.72))
	_vignette.draw_rect(Rect2(0.0, 3.0, size.x, 10.0), Color(neon, 0.10))
	_vignette.draw_rect(Rect2(0.0, size.y - 3.0, size.x, 3.0), Color(hot, 0.72))
	_vignette.draw_rect(Rect2(0.0, size.y - 14.0, size.x, 11.0), Color(hot, 0.12))
	HudLayout.draw_radial_glow(_vignette, Vector2(size.x * 0.06, size.y * 0.92), size.y * 0.62, Color(neon, 0.18))
	HudLayout.draw_radial_glow(_vignette, Vector2(size.x * 0.94, size.y * 0.08), size.y * 0.56, Color(hot, 0.16))

func _process(delta: float) -> void:
	if not visible or not _photo.visible:
		return
	# frames can come far apart while a step builds: one must never jump the push-in
	_t += minf(delta, 0.1)
	var k := 1.0 + 0.045 * smoothstep(0.0, 1.0, minf(_t / DRIFT_TIME, 1.0))
	_photo.pivot_offset = size * Vector2(0.6, 0.55)
	_photo.scale = Vector2(k, k)

## The path of a circuit's still (its night one where it has one and the clock says night), "" when there is none.
## The stock stills show the stock Seicento's field, so another car (CarCatalog key) takes its own circuit still
## (hero_<key>_<car>.jpg) where one was rendered, else one of its open-world cover stills (the same one for a circuit
## every time), and the stock circuit still only when the car has no stills at all.
static func hero_path(key: String, hour := -1.0, car := "stock") -> String:
	if key == "":
		return ""
	if car != "stock" and CarCatalog.is_key(car):
		var own := "%shero_%s_%s.jpg" % [HERO_DIR, key, car]
		if ResourceLoader.exists(own):
			return own
		var set := OpenWorldCover.shots_for(car)
		if set != OpenWorldCover.SHOTS.stock and (ResourceLoader.exists("%shero_%s.jpg" % [HERO_DIR, key])):
			return OpenWorldCover.DIR + String(set[absi(hash(key)) % set.size()][0])
	if hour >= 0.0 and (hour >= NIGHT_FROM or hour < NIGHT_TO):
		var night := "%shero_%s_night.jpg" % [HERO_DIR, key]
		if ResourceLoader.exists(night):
			return night
	var day := "%shero_%s.jpg" % [HERO_DIR, key]
	return day if ResourceLoader.exists(day) else ""

static func clock_text(hour: float) -> String:
	var minutes := roundi(fposmod(hour, 24.0) * 60.0) % 1440
	return "%02d:%02d" % [minutes / 60, minutes % 60]

## A tip for the conditions: weather ones when it rains or snows, night ones after dark, rally ones on a stage, else a general one.
static func pick_tip(weather: String, hour: float, mode: String) -> String:
	var pool: Array = TIPS_ANY.duplicate()
	if weather in ["wet", "hail"]:
		pool.append_array(TIPS_WET)
		pool.append_array(TIPS_WET)
	elif weather == "snow":
		pool.append_array(TIPS_SNOW)
		pool.append_array(TIPS_SNOW)
	if hour >= NIGHT_FROM or (hour >= 0.0 and hour < NIGHT_TO):
		pool.append_array(TIPS_NIGHT)
	if mode == "rally":
		pool = TIPS_RALLY.duplicate()
		if weather in ["wet", "hail", "snow"]:
			pool.append_array(TIPS_WET if weather != "snow" else TIPS_SNOW)
	return String(pool[randi() % pool.size()])

func _fact(caption: String, value: String) -> Control:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := HudLayout.neon_box(HudLayout.neon_primary(), 0.72, 4, -0.09, 6, 12.0, 6.0)
	sb.bg_color = HudLayout.glass_plate(0.76)
	panel.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_text(caption.to_upper(), 12, 800, HORIZONTAL_ALIGNMENT_LEFT, HudLayout.neon_primary(), true))
	col.add_child(_text(value.to_upper(), 22, 900, HORIZONTAL_ALIGNMENT_LEFT, Color.WHITE, true))
	panel.add_child(col)
	return panel

## A dark midnight gradient across the screen, `a_start` opaque at the `from` fraction of its length (down for `vertical`, across
## otherwise) fading to `a_end` at `to`, so the type reads on any still.
func _shade(vertical: bool, a_start: float, a_end: float, from: float, to: float) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.03, 0.08, a_start))
	g.set_color(1, Color(0.02, 0.03, 0.08, a_end))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 4 if vertical else 128
	tex.height = 128 if vertical else 4
	tex.fill_from = Vector2.ZERO
	tex.fill_to = Vector2(0, 1) if vertical else Vector2(1, 0)
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if vertical:
		r.anchor_right = 1.0
		r.anchor_top = from
		r.anchor_bottom = to
	else:
		r.anchor_bottom = 1.0
		r.anchor_left = from
		r.anchor_right = to
	return r

static func _text(text: String, size: int, weight: int, align := HORIZONTAL_ALIGNMENT_RIGHT, color := CmrStyle.TEXT, italic := false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", HudLayout.italic_font(weight) if italic else CmrStyle.font(weight))
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.72))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", maxi(1, size / 14))
	label.horizontal_alignment = align
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
