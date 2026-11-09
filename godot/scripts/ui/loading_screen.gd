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
var _title: HBoxContainer
var _facts: HBoxContainer
var _tip_row: HBoxContainer
var _tip: Label
var _caption: Label
var _value: Label
var _blocks: Array[ColorRect] = []
var _t := 0.0
var BLOCK_ON: Color:
	get: return CmrStyle.TEXT
var BLOCK_OFF: Color:
	get: return Color(CmrStyle.TEXT, 0.28)

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
	add_child(_shade(true, 0.5, 0.0, 0.0, 0.3)) # top: the screen's edge, so the picture sits in a frame
	add_child(_shade(true, 0.0, 0.86, 0.5, 1.0)) # bottom: under the type
	add_child(_shade(false, 0.55, 0.0, 0.0, 0.62)) # left: the title block

	# bottom left: the title, the conditions and a tip
	var left := VBoxContainer.new()
	left.anchor_top = 1.0
	left.anchor_bottom = 1.0
	left.grow_vertical = Control.GROW_DIRECTION_BEGIN
	left.offset_left = MARGIN.x
	left.offset_bottom = -MARGIN.y
	left.add_theme_constant_override("separation", 22)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(left)
	_title = HBoxContainer.new()
	_title.add_theme_constant_override("separation", 14)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(_title)
	_facts = HBoxContainer.new()
	_facts.add_theme_constant_override("separation", 28)
	_facts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(_facts)
	_tip_row = HBoxContainer.new()
	_tip_row.add_theme_constant_override("separation", 12)
	_tip_row.custom_minimum_size.x = 640
	_tip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(_tip_row)
	var tag := PanelContainer.new()
	tag.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tag_box := StyleBoxFlat.new()
	tag_box.bg_color = CmrStyle.ORANGE
	tag_box.content_margin_left = 7
	tag_box.content_margin_right = 7
	tag_box.content_margin_top = 1
	tag_box.content_margin_bottom = 1
	tag.add_theme_stylebox_override("panel", tag_box)
	var tag_text := _text("tip", 14, 800, HORIZONTAL_ALIGNMENT_LEFT, CmrStyle.INK)
	tag_text.add_theme_constant_override("shadow_offset_y", 0)
	tag.add_child(tag_text)
	_tip_row.add_child(tag)
	_tip = _text("", 16, 500, HORIZONTAL_ALIGNMENT_LEFT, Color(CmrStyle.TEXT, 0.92))
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tip_row.add_child(_tip)

	# bottom right: what the circuit is, and the blocks
	var corner := VBoxContainer.new()
	corner.add_theme_constant_override("separation", 2)
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
	_caption = _text("", 17, 700)
	_value = _text("", 17, 400)
	corner.add_child(_caption)
	corner.add_child(_value)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.size_flags_horizontal = Control.SIZE_SHRINK_END
	row.custom_minimum_size.y = 18
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	corner.add_child(row)
	for i in BLOCKS:
		var block := ColorRect.new()
		block.custom_minimum_size = Vector2(12, 16)
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
	for child in _title.get_children():
		child.queue_free()
	var words: Array = ["loading"] + segments
	for i in words.size():
		if i > 0:
			var rule := ColorRect.new()
			rule.color = CmrStyle.TEXT
			rule.custom_minimum_size = Vector2(2, 44)
			rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_title.add_child(rule)
		_title.add_child(_text(str(words[i]).to_lower(), 44, 300, HORIZONTAL_ALIGNMENT_LEFT))
	_caption.text = caption
	_value.text = value
	var hour := float(info.get("hour", -1.0))
	var weather := String(info.get("weather", ""))
	var path := hero_path(String(info.get("track", "")), hour)
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
	set_progress(0.0)
	show()

## 0..1 along the row of blocks.
func set_progress(fraction: float) -> void:
	var lit := roundi(clampf(fraction, 0.0, 1.0) * BLOCKS)
	for i in BLOCKS:
		_blocks[i].color = BLOCK_ON if i < lit else BLOCK_OFF

## The menu skin changed: the plain backdrop behind a missing still follows it.
func restyle() -> void:
	color = CmrStyle.TINT_HOME

func _process(delta: float) -> void:
	if not visible or not _photo.visible:
		return
	# frames can come far apart while a step builds: one must never jump the push-in
	_t += minf(delta, 0.1)
	var k := 1.0 + 0.045 * smoothstep(0.0, 1.0, minf(_t / DRIFT_TIME, 1.0))
	_photo.pivot_offset = size * Vector2(0.6, 0.55)
	_photo.scale = Vector2(k, k)

## The path of a circuit's still (its night one where it has one and the clock says night), "" when there is none.
static func hero_path(key: String, hour := -1.0) -> String:
	if key == "":
		return ""
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
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_text(caption.to_lower(), 15, 700, HORIZONTAL_ALIGNMENT_LEFT, Color(CmrStyle.TEXT, 0.62)))
	col.add_child(_text(value.to_lower(), 28, 300, HORIZONTAL_ALIGNMENT_LEFT))
	return col

## A dark gradient across the screen, `a_start` opaque at the `from` fraction of its length (down for `vertical`, across
## otherwise) fading to `a_end` at `to`, so the type reads on any still.
func _shade(vertical: bool, a_start: float, a_end: float, from: float, to: float) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, a_start))
	g.set_color(1, Color(0, 0, 0, a_end))
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

static func _text(text: String, size: int, weight: int, align := HORIZONTAL_ALIGNMENT_RIGHT, color := CmrStyle.TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", CmrStyle.font(weight))
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", maxi(1, size / 16))
	label.horizontal_alignment = align
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
