## A dialogue card for the campaign's story (Story): the speaker's chip (initial on their colour), name and role,
## one line of text at a time. Enter / pad A shows the next line, Esc / pad B skips the rest. In the journal
## (play(..., true)) ◂ ▸ (arrow keys, D-pad, shoulder buttons) jump a whole beat back or on.
## It reads its own input in _input (before the open world's), only while it is shown, and marks it handled.
## Skinned like the open world's cards (a plate with a coloured left edge, slightly skewed), sized for 4:3.
class_name StoryCard
extends Control

signal finished(skipped: bool)

const TEXT_SIZE := 20
const NAME_SIZE := 18
const CHIP := 58.0
const MAX_W := 900.0
const SIDE := 320.0 ## kept clear each side (the satnav disc on the left, the speedometer on the right)
const BOTTOM := 92.0 ## kept clear below (the street name and the key help)
const PAD_H := 22.0
const GAP := 16.0

var panel: PanelContainer
var chip: Control
var kicker: Label ## the beat's title
var name_label: Label
var role_label: Label
var text_label: Label
var hint_label: Label
var journal := false
var _items: Array = [] ## [{speaker, text, title, beat}]
var _starts: PackedInt32Array = [] ## the index of each beat's first line
var _i := 0
var _done := Callable()
var _speaker := ""

func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	hide()

func _build() -> void:
	panel = PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _box())
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(GAP))
	panel.add_child(row)
	chip = Control.new()
	chip.custom_minimum_size = Vector2(CHIP, CHIP)
	chip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	chip.draw.connect(_draw_chip)
	row.add_child(chip)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)
	kicker = _label(12, 800, Color(1, 1, 1, 0.6))
	col.add_child(kicker)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)
	name_label = _label(NAME_SIZE, 900, Color.WHITE)
	head.add_child(name_label)
	role_label = _label(13, 600, Color(1, 1, 1, 0.65))
	role_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(role_label)
	text_label = _label(TEXT_SIZE, 700, Color.WHITE)
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(text_label)
	hint_label = _label(12, 700, Color(1, 1, 1, 0.55))
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(hint_label)
	resized.connect(_layout)

func _label(fs: int, weight: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", CmrStyle.font(weight))
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("outline_size", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(CmrStyle.PLATE, 0.9)
	sb.border_color = CmrStyle.ORANGE
	sb.border_width_left = 6
	sb.content_margin_left = PAD_H
	sb.content_margin_right = PAD_H
	sb.content_margin_top = 14
	sb.content_margin_bottom = 12
	sb.skew = Vector2(-0.08, 0.0)
	return sb

## The card's width on a canvas this wide (the open world's canvas is 1600 wide at 16:9 and 4:3 alike).
static func card_width(canvas_w: float) -> float:
	return clampf(canvas_w - 2.0 * SIDE, 520.0, MAX_W)

## The width the text wraps in on a canvas this wide.
static func text_width(canvas_w: float) -> float:
	return card_width(canvas_w) - 2.0 * PAD_H - 6.0 - CHIP - GAP

## Lines a text takes in the card on a canvas this wide (measured with the card's font).
static func line_count(text: String, canvas_w: float) -> int:
	var f := CmrStyle.font(700)
	var w := text_width(canvas_w)
	var lines := 1
	var cur := ""
	for word in text.split(" ", false):
		var trial := word if cur == "" else cur + " " + word
		if cur != "" and f.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE).x > w:
			lines += 1
			cur = word
		else:
			cur = trial
	return lines

func _layout() -> void:
	var w := card_width(size.x)
	panel.offset_left = -w * 0.5
	panel.offset_right = w * 0.5
	panel.offset_bottom = -BOTTOM
	panel.offset_top = -BOTTOM - 1.0 # grows upwards to its content

# ------------------------------------------------------------------ playing

func is_open() -> bool:
	return visible and not _items.is_empty()

## Shows beats one line at a time: beats [{title, lines: [[speaker, text], ...]}]. on_done runs once when the last
## line is passed or the card is skipped. in_journal: ◂ ▸ jump between beats, and the hint says so.
func play(beats: Array, on_done := Callable(), in_journal := false) -> void:
	_items.clear()
	_starts.clear()
	for b in beats:
		var bl: Array = (b as Dictionary).get("lines", [])
		if bl.is_empty():
			continue
		_starts.append(_items.size())
		for ln in bl:
			_items.append({"speaker": String(ln[0]), "text": String(ln[1]), "title": String((b as Dictionary).get("title", "")),
				"beat": _starts.size() - 1})
	_done = on_done
	journal = in_journal
	_i = 0
	if _items.is_empty():
		_finish(false)
		return
	show()
	_layout()
	_show_line()

func advance() -> void:
	if not is_open():
		return
	_i += 1
	if _i >= _items.size():
		_finish(false)
	else:
		_show_line()

func skip() -> void:
	if is_open():
		_finish(true)

## Moves a whole beat back (-1) or on (+1); on past the last beat closes the card.
func jump(d: int) -> void:
	if not is_open():
		return
	var b := int(_items[_i].beat) + d
	if b < 0:
		b = 0
	if b >= _starts.size():
		_finish(false)
		return
	_i = _starts[b]
	_show_line()

func line_index() -> int:
	return _i

func line_total() -> int:
	return _items.size()

func current_text() -> String:
	return String(_items[_i].text) if is_open() else ""

func current_speaker() -> String:
	return String(_items[_i].speaker) if is_open() else ""

func _finish(skipped: bool) -> void:
	_items.clear()
	_starts.clear()
	hide()
	var cb := _done
	_done = Callable()
	finished.emit(skipped)
	if cb.is_valid():
		cb.call()

func _show_line() -> void:
	var it: Dictionary = _items[_i]
	_speaker = String(it.speaker)
	var who := Story.character(_speaker)
	var col := Story.color_of(_speaker)
	kicker.text = String(it.title)
	kicker.visible = kicker.text != ""
	name_label.text = String(who.name).to_upper()
	role_label.text = String(who.role)
	name_label.get_parent().visible = _speaker != ""
	name_label.add_theme_color_override("font_color", col.lightened(0.2))
	text_label.text = String(it.text)
	var sb := panel.get_theme_stylebox("panel") as StyleBoxFlat
	if sb:
		sb.border_color = col
		sb.bg_color = Color(CmrStyle.PLATE, 0.9) # follows a skin change
	var keys := "ENTER / Ⓐ  NEXT    ESC / Ⓑ  %s" % ("CLOSE" if journal else "SKIP")
	if journal:
		keys = "◂ ▸  BEAT    " + keys
	hint_label.text = "%s     %d / %d" % [keys, _i + 1, _items.size()]
	chip.queue_redraw()

func _draw_chip() -> void:
	var col := Story.color_of(_speaker)
	var c := chip.size * 0.5
	chip.draw_circle(c, CHIP * 0.5, Color(col, 0.95))
	chip.draw_arc(c, CHIP * 0.5 - 1.5, 0.0, TAU, 40, Color(1, 1, 1, 0.5), 2.0, true)
	var f := CmrStyle.font(900)
	var initial := String(Story.character(_speaker).initial)
	var fs := 28
	var w := f.get_string_size(initial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	chip.draw_string(f, c + Vector2(-w * 0.5, f.get_ascent(fs) * 0.5 - 2.0), initial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, CmrStyle.PLATE)

# ------------------------------------------------------------------ input

## The card's action for an input event: "next", "skip", "prev_beat", "next_beat" or "" (presses only).
func action_of(event: InputEvent) -> String:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).physical_keycode:
			KEY_ENTER, KEY_KP_ENTER: return "next"
			KEY_ESCAPE: return "skip"
			KEY_LEFT: return "prev_beat" if journal else ""
			KEY_RIGHT: return "next_beat" if journal else ""
	elif event is InputEventJoypadButton and event.pressed:
		match (event as InputEventJoypadButton).button_index:
			JOY_BUTTON_A: return "next"
			JOY_BUTTON_B: return "skip"
			JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_LEFT_SHOULDER: return "prev_beat" if journal else ""
			JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_RIGHT_SHOULDER: return "next_beat" if journal else ""
	return ""

## Handles an event while the card is shown; true when it took it.
func handle(event: InputEvent) -> bool:
	if not is_open() or not is_visible_in_tree():
		return false
	var a := action_of(event)
	match a:
		"next": advance()
		"skip": skip()
		"prev_beat": jump(-1)
		"next_beat": jump(1)
		_:
			# the open world's other buttons (START, map, pause keys) wait until the card is gone; driving keys are read
			# from the keyboard state and carry on
			if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index in [JOY_BUTTON_START, JOY_BUTTON_BACK]:
				return event.is_pressed()
			if event is InputEventKey and (event as InputEventKey).physical_keycode in [KEY_M, KEY_TAB, KEY_G]:
				return event.is_pressed()
			return false
	return true

func _input(event: InputEvent) -> void:
	if handle(event):
		get_viewport().set_input_as_handled()
