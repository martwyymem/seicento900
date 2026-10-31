## Gamepad navigation in the front-end menus, driven by synthetic joypad events (no controller needed):
## the main menu strip and its wrap-round, the set-up list (first press picks an item, up/down move, focus
## comes back after the focused control vanishes or the page changes), left/right on a selector, LB/RB page
## steps, B going home, the stick as a d-pad (latch and dead zone) and the keys being ignored under a
## confirmation or in a race. Starting a race (START), real stick feel and rumble need hardware.
extends RefCounted

var completed := false

static func _btn(b: JoyButton, pressed := true) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	e.pressed = pressed
	return e

static func _axis(axis: JoyAxis, v: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = v
	return e

func run() -> Array:
	var errors: Array[String] = []
	Brain.use_disk = false
	LapRecords.use_disk = false
	var tree := Engine.get_main_loop() as SceneTree
	var game = load("res://ui/game.tscn").instantiate()
	tree.root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	game.size = Vector2(1600, 900)
	for k in 3:
		await tree.process_frame
	await _home(errors, game, tree)
	await _setup_list(errors, game, tree)
	await _pages(errors, game, tree)
	await _stick(errors, game, tree)
	game.queue_free()
	await tree.process_frame
	completed = true
	return errors

func _home(errors: Array[String], game, tree: SceneTree) -> void:
	game._show_home()
	game._home_select(0, false)
	var n: int = game.FRONT_MENU.size()
	game._unhandled_input(_btn(JOY_BUTTON_DPAD_LEFT))
	if game.home_menu_index != n - 1:
		errors.append("d-pad left from the first entry wraps to the last (%d), got %d" % [n - 1, game.home_menu_index])
	game._unhandled_input(_btn(JOY_BUTTON_DPAD_RIGHT))
	if game.home_menu_index != 0:
		errors.append("d-pad right from the last entry wraps to the first, got %d" % game.home_menu_index)
	game._unhandled_input(_btn(JOY_BUTTON_DPAD_DOWN))
	game._unhandled_input(_btn(JOY_BUTTON_DPAD_UP))
	if game.home_menu_index != 0:
		errors.append("d-pad down then up returns to the same entry")
	game._unhandled_input(_btn(JOY_BUTTON_DPAD_RIGHT, false))
	if game.home_menu_index != 0:
		errors.append("a button release moves nothing")
	game._unhandled_input(_btn(JOY_BUTTON_B))
	if game.active_menu_page != "home":
		errors.append("B on the main menu stays on the main menu")
	game._home_select(1, false)
	game._unhandled_input(_btn(JOY_BUTTON_A))
	await tree.process_frame
	if game.active_menu_page == "home":
		errors.append("A on a menu entry opens it")
	game._show_home()

func _setup_list(errors: Array[String], game, tree: SceneTree) -> void:
	game.is_campaign_mode = false
	game._show_setup_page()
	for k in 4:
		await tree.process_frame
	var items: Array = game._setup_focus_items()
	if items.size() < 4:
		errors.append("the set-up page should offer a list to navigate, got %d controls" % items.size())
		return
	game.get_viewport().gui_release_focus()
	game._input(_btn(JOY_BUTTON_DPAD_DOWN))
	var owner = game.get_viewport().gui_get_focus_owner()
	if owner != items[0]:
		errors.append("with nothing focused the first d-pad press picks the first control, got %s" % owner)
	game._input(_btn(JOY_BUTTON_DPAD_DOWN))
	if game.get_viewport().gui_get_focus_owner() != items[1]:
		errors.append("d-pad down moves to the next control")
	game._input(_btn(JOY_BUTTON_DPAD_UP))
	if game.get_viewport().gui_get_focus_owner() != items[0]:
		errors.append("d-pad up moves back")
	game._input(_btn(JOY_BUTTON_DPAD_UP))
	if game.get_viewport().gui_get_focus_owner() != items[0]:
		errors.append("d-pad up on the first control stays on it")
	# the end of the list holds
	game._focus_setup_item(items, items.size() - 1)
	game._input(_btn(JOY_BUTTON_DPAD_DOWN))
	if game.get_viewport().gui_get_focus_owner() != items[items.size() - 1]:
		errors.append("d-pad down on the last control stays on it")
	# left/right change a selector
	var sel: MenuSelector = null
	for c in items:
		if c is MenuSelector and not (c as MenuSelector).browse_only and (c as MenuSelector).item_count > 1:
			sel = c
			break
	if sel != null:
		game._focus_setup_item(items, items.find(sel))
		var before := sel.selected
		game._input(_btn(JOY_BUTTON_DPAD_RIGHT))
		var after_right := sel.selected
		game._input(_btn(JOY_BUTTON_DPAD_LEFT))
		if after_right == before or sel.selected != before:
			errors.append("d-pad right/left steps a selector there and back (%d -> %d -> %d)" % [before, after_right, sel.selected])
	# focus recovery: the focused control goes away (a section folds, a mode hides it); the next press picks again
	var victim: Control = items[2]
	var hider: Control = victim.get_parent() if victim is LineEdit else victim # (a spin box's field is listed through its box)
	game._focus_setup_item(items, 2)
	hider.hide()
	await tree.process_frame
	if game.get_viewport().gui_get_focus_owner() == victim:
		errors.append("a hidden control should have lost the focus")
	game._input(_btn(JOY_BUTTON_DPAD_DOWN))
	var now = game.get_viewport().gui_get_focus_owner()
	if now == null or now == victim or not game._setup_focus_items().has(now):
		errors.append("after the focused control vanished the next press lands on a visible one, got %s" % now)
	hider.show()
	# a freed focus after leaving and coming back to the page
	game._show_home()
	game._show_setup_page()
	for k in 3:
		await tree.process_frame
	game.get_viewport().gui_release_focus()
	game._input(_btn(JOY_BUTTON_A))
	if game.get_viewport().gui_get_focus_owner() == null:
		errors.append("A with nothing focused picks a control instead of doing nothing")

func _pages(errors: Array[String], game, tree: SceneTree) -> void:
	game._show_setup_page()
	for k in 3:
		await tree.process_frame
	var ids: Array = game._menu_page_ids()
	var start: String = game.active_menu_page
	var at := ids.find(start)
	game._input(_btn(JOY_BUTTON_RIGHT_SHOULDER))
	for k in 3:
		await tree.process_frame
	if at < ids.size() - 1 and game.active_menu_page != ids[at + 1]:
		errors.append("RB steps to the next page (%s -> %s, expected %s)" % [start, game.active_menu_page, ids[at + 1]])
	game._input(_btn(JOY_BUTTON_LEFT_SHOULDER))
	for k in 3:
		await tree.process_frame
	if game.active_menu_page != start:
		errors.append("LB steps back (%s, expected %s)" % [game.active_menu_page, start])
	# a repeat (held) RB must not run through the pages
	var held := _btn(JOY_BUTTON_RIGHT_SHOULDER)
	game._input(held)
	var once: String = game.active_menu_page
	game._input(held)
	game._input(held)
	# (a joypad button has no echo flag, so each press counts; the keys do)
	game._show_setup_page()
	game._input(_btn(JOY_BUTTON_B))
	if game.active_menu_page != "home":
		errors.append("B goes back to the main menu, on page %s" % game.active_menu_page)
	# an open confirmation owns the pad: B must not leave the page under it
	game._show_setup_page()
	for k in 2:
		await tree.process_frame
	var dialog := ConfirmationDialog.new()
	game.add_child(dialog)
	dialog.popup_centered()
	await tree.process_frame
	var page_before: String = game.active_menu_page
	if not dialog.visible or game.get_viewport().get_embedded_subwindows().filter(func(w: Window) -> bool: return w.visible).is_empty():
		# (headless windows may not embed: the check only runs where the dialog is embedded)
		pass
	else:
		game._input(_btn(JOY_BUTTON_B))
		if game.active_menu_page != page_before:
			errors.append("B under an open confirmation left the page")
	dialog.queue_free()
	game._show_home()

func _stick(errors: Array[String], game, tree: SceneTree) -> void:
	game._show_home() # (the page's own keys ignore the pad here, so the synthesised d-pad presses do no harm)
	game._stick_latch = Vector2i.ZERO
	game._stick_as_dpad(_axis(JOY_AXIS_LEFT_Y, 0.5))
	if game._stick_latch.y != 0:
		errors.append("a push under 0.6 does not step (the dead zone)")
	game._stick_as_dpad(_axis(JOY_AXIS_LEFT_Y, 0.9))
	if game._stick_latch.y != 1:
		errors.append("a push past 0.6 steps once and latches down")
	game._stick_as_dpad(_axis(JOY_AXIS_LEFT_Y, 1.0))
	if game._stick_latch.y != 1:
		errors.append("holding the stick does not step again")
	game._stick_as_dpad(_axis(JOY_AXIS_LEFT_Y, 0.5))
	if game._stick_latch.y != 1:
		errors.append("easing to 0.5 stays latched (hysteresis, no stutter near the edge)")
	game._stick_as_dpad(_axis(JOY_AXIS_LEFT_Y, 0.1))
	if game._stick_latch.y != 0:
		errors.append("letting go below 0.35 releases the latch")
	game._stick_as_dpad(_axis(JOY_AXIS_LEFT_X, -0.9))
	if game._stick_latch.x != -1:
		errors.append("left on the stick latches -1")
	game._stick_as_dpad(_axis(JOY_AXIS_LEFT_X, 0.0))
	game._stick_as_dpad(_axis(JOY_AXIS_RIGHT_X, 1.0))
	if game._stick_latch.x != 0:
		errors.append("the right stick does nothing in the menus")
	await tree.process_frame
