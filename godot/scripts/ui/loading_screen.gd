## The stage loading screen, after Colin McRae Rally 2.0's: one flat tint, "loading | circuit | race" in thin
## lowercase type split by hairlines, and the length of the stage over a row of blocks that fill as it loads.
class_name LoadingScreen
extends ColorRect

const BLOCKS := 12
var BLOCK_ON: Color:
	get: return CmrStyle.TEXT
const BLOCK_OFF := Color(0.97, 0.94, 1.0, 0.28)

var _title: HBoxContainer
var _caption: Label
var _value: Label
var _blocks: Array[ColorRect] = []

func _init() -> void:
	name = "LoadingScreen"
	color = CmrStyle.TINT_HOME
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP # nothing behind it can be clicked while the race builds

	_title = HBoxContainer.new()
	_title.add_theme_constant_override("separation", 14)
	_title.anchor_top = 0.5
	_title.anchor_bottom = 0.5
	_title.offset_left = 250
	_title.offset_top = -30
	_title.offset_bottom = 30
	add_child(_title)

	var corner := VBoxContainer.new()
	corner.add_theme_constant_override("separation", 2)
	corner.anchor_left = 1.0
	corner.anchor_right = 1.0
	corner.anchor_top = 1.0
	corner.anchor_bottom = 1.0
	corner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	corner.grow_vertical = Control.GROW_DIRECTION_BEGIN
	corner.offset_right = -250
	corner.offset_bottom = -150
	add_child(corner)
	_caption = _text("", 17, 700)
	_value = _text("", 17, 400)
	corner.add_child(_caption)
	corner.add_child(_value)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.size_flags_horizontal = Control.SIZE_SHRINK_END
	row.custom_minimum_size.y = 16
	corner.add_child(row)
	for i in BLOCKS:
		var block := ColorRect.new()
		block.custom_minimum_size = Vector2(10, 14)
		block.color = BLOCK_OFF
		row.add_child(block)
		_blocks.append(block)
	hide()

## Name the stage and show the screen. `segments` follow "loading" in the title, `caption` and `value` are the
## two lines over the blocks in the corner.
func open(segments: Array, caption: String, value: String) -> void:
	for child in _title.get_children():
		child.queue_free()
	var words: Array = ["loading"] + segments
	for i in words.size():
		if i > 0:
			var rule := ColorRect.new()
			rule.color = CmrStyle.TEXT
			rule.custom_minimum_size = Vector2(2, 44)
			rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			_title.add_child(rule)
		_title.add_child(_text(str(words[i]).to_lower(), 44, 300))
	_caption.text = caption
	_value.text = value
	set_progress(0.0)
	show()

## 0..1 along the row of blocks.
func set_progress(fraction: float) -> void:
	var lit := roundi(clampf(fraction, 0.0, 1.0) * BLOCKS)
	for i in BLOCKS:
		_blocks[i].color = BLOCK_ON if i < lit else BLOCK_OFF

static func _text(text: String, size: int, weight: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", CmrStyle.font(weight))
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", CmrStyle.TEXT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return label
