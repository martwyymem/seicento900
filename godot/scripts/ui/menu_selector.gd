## A controller-friendly "◂ value ▸" picker for the front end, in place of OptionButton (whose popup list is
## awkward on a gamepad). ◂ ▸ (the d-pad or stick, via game.gd) step through the values; A / Enter / a click
## in the middle steps forward (wrapping); a click on either end steps that way. It keeps OptionButton's API
## (add_item, select, selected, item_selected, get_item_text, item_count, ids, disabled items), so the menus
## treat it as one. browse_only: stepping only shows the next value and pressing applies it (item_selected).
class_name MenuSelector
extends Button

signal item_selected(index: int)

var selected := -1:
	set(v):
		selected = v
		_show()
var browse_only := false
var _texts: Array[String] = []
var _ids: Array[int] = []
var _off: Array[bool] = []

var item_count: int:
	get: return _texts.size()

func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	clip_text = true
	add_theme_font_size_override("font_size", 17)

func add_item(label: String, id := -1) -> void:
	_texts.append(label)
	_ids.append(id if id >= 0 else _texts.size() - 1)
	_off.append(false)
	if selected < 0:
		selected = 0
	_show()

func clear() -> void:
	_texts.clear()
	_ids.clear()
	_off.clear()
	selected = -1
	_show()

func select(index: int) -> void:
	selected = clampi(index, -1, _texts.size() - 1)
	_show()

func get_item_text(index: int) -> String:
	return _texts[index] if index >= 0 and index < _texts.size() else ""

func set_item_text(index: int, label: String) -> void:
	if index >= 0 and index < _texts.size():
		_texts[index] = label
		_show()

func get_item_id(index: int) -> int:
	return _ids[index] if index >= 0 and index < _ids.size() else -1

func get_item_index(id: int) -> int:
	return _ids.find(id)

func get_selected_id() -> int:
	return get_item_id(selected)

func set_item_disabled(index: int, off: bool) -> void:
	if index >= 0 and index < _off.size():
		_off[index] = off

func is_item_disabled(index: int) -> bool:
	return index >= 0 and index < _off.size() and _off[index]

## Steps d values on (skipping disabled ones). wrap: past the ends goes round. Returns whether it moved;
## item_selected is emitted unless browse_only (or emit is false).
func step(d: int, wrap := false, emit := true) -> bool:
	var n := _texts.size()
	if n == 0 or disabled:
		return false
	var i := selected
	for k in n:
		i += signi(d)
		if wrap:
			i = posmod(i, n)
		elif i < 0 or i >= n:
			return false
		if not _off[i]:
			break
	if i == selected or _off[i]:
		return false
	selected = i
	_show()
	if emit and not browse_only:
		item_selected.emit(selected)
	return true

## A press (A, Enter, or a click): browse_only applies the shown value, otherwise steps forward, or back for
## a click on the left end.
func activate(direction := 1) -> void:
	if browse_only and direction == 0:
		item_selected.emit(selected)
	else:
		step(direction if direction != 0 else 1, true)

func _pressed() -> void:
	var dir := 0 if browse_only else 1 # Enter / A: apply (browse_only) or step on
	if _clicked:
		var x := get_local_mouse_position().x
		if x < size.x * 0.25:
			dir = -1
		elif x > size.x * 0.75:
			dir = 1
	_clicked = false
	activate(dir)

var _clicked := false ## the press came from the mouse, so where it landed says which way to step

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_clicked = true

func _show() -> void:
	var label := get_item_text(selected)
	text = "◂   %s   ▸" % label if label != "" else ""
