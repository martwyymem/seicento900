## The developer menu: § + 1 (the key left of 1, held, then 1; either order). A list of actions for whatever is on screen:
## fans and unlocks everywhere, teleports, time of day and parked cars in the open world, weather, repairs and finishing in a race.
## The game fills it (game.gd `_dev_entries()`); the world freezes (Engine.time_scale 0) while it is open. ↑ ↓ and Enter or a click
## choose, Esc or § + 1 again closes. The ~ performance overlay (DevHud) still toggles on the key's own press and release.
class_name DevMenu
extends CanvasLayer

## Set when § + 1 opened or closed the menu, so DevHud knows the § key was part of a chord, not a tap.
static var chord_used := false

var game: Node
var _panel: PanelContainer
var _list: VBoxContainer
var _scroll: ScrollContainer
var _buttons: Array[Button] = []
var _index := 0
var _open := false
var _saved_scale := 1.0

func _init() -> void:
	name = "DevMenu"
	layer = 101
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

func _ready() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -300
	_panel.offset_right = 300
	_panel.offset_top = -330
	_panel.offset_bottom = 330
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.05, 0.06, 0.09, 0.94)
	box.set_border_width_all(2)
	box.border_color = Color("#ff9d1a")
	box.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", box)
	add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_panel.add_child(col)
	var title := Label.new()
	title.text = "DEV MENU   ·   § + 1 or Esc closes   ·   ↑ ↓ Enter"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color("#ff9d1a"))
	col.add_child(title)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 3)
	_scroll.add_child(_list)

func is_open() -> bool:
	return _open

func _is_section_key(key: InputEventKey) -> bool:
	return key.physical_keycode == KEY_QUOTELEFT or key.physical_keycode == KEY_SECTION or key.keycode == KEY_SECTION

func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null:
		return
	if key.pressed and not key.echo:
		var chord := (key.physical_keycode == KEY_1 and _section_held()) or (_is_section_key(key) and Input.is_physical_key_pressed(KEY_1))
		if chord:
			chord_used = true
			toggle()
			get_viewport().set_input_as_handled()
			return
	if not _open:
		return
	get_viewport().set_input_as_handled() # the game does not see a key while the menu is up
	if not key.pressed:
		return
	match key.physical_keycode:
		KEY_ESCAPE:
			toggle()
		KEY_UP, KEY_W:
			_move(-1)
		KEY_DOWN, KEY_S:
			_move(1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if _index >= 0 and _index < _buttons.size():
				_buttons[_index].pressed.emit()

func _section_held() -> bool:
	return Input.is_physical_key_pressed(KEY_QUOTELEFT) or Input.is_physical_key_pressed(KEY_SECTION)

func toggle() -> void:
	if _open:
		_open = false
		visible = false
		Engine.time_scale = _saved_scale
		return
	_saved_scale = Engine.time_scale if Engine.time_scale > 0.0 else 1.0
	_rebuild()
	_open = true
	visible = true
	Engine.time_scale = 0.0

## Rebuilds the list from the game's current entries (it changes with what is on screen, and after some actions).
func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	_buttons.clear()
	var entries: Array = game._dev_entries() if game and game.has_method("_dev_entries") else []
	var section := ""
	for e in entries:
		if e.section != section:
			section = e.section
			var head := Label.new()
			head.text = section
			head.add_theme_font_size_override("font_size", 13)
			head.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
			_list.add_child(head)
		var b := Button.new()
		b.text = e.label
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_run.bind(e))
		_list.add_child(b)
		_buttons.append(b)
	_index = clampi(_index, 0, maxi(_buttons.size() - 1, 0))
	_mark()

func _run(e: Dictionary) -> void:
	(e.do as Callable).call()
	if e.get("close", false):
		toggle()
	else:
		_rebuild() # labels such as "unlock all: ON" change

func _move(d: int) -> void:
	if _buttons.is_empty():
		return
	_index = posmod(_index + d, _buttons.size())
	_mark()

func _mark() -> void:
	for i in _buttons.size():
		var b := _buttons[i]
		b.modulate = Color("#ffd27a") if i == _index else Color.WHITE
		b.add_theme_stylebox_override("normal", _row_box(i == _index))
	if _index >= 0 and _index < _buttons.size():
		_scroll.ensure_control_visible(_buttons[_index])

func _row_box(selected: bool) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = Color(0.22, 0.16, 0.05, 0.95) if selected else Color(1, 1, 1, 0.05)
	b.set_content_margin_all(5)
	return b
