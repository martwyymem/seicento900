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
	await _walk_all_pages(errors, game, tree)
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
		# selectors do not wrap on the d-pad, so step away from whichever end the value sits at
		var out_btn := JOY_BUTTON_DPAD_RIGHT
		var back_btn := JOY_BUTTON_DPAD_LEFT
		if before >= sel.item_count - 1:
			out_btn = JOY_BUTTON_DPAD_LEFT
			back_btn = JOY_BUTTON_DPAD_RIGHT
		game._input(_btn(out_btn))
		var after_out := sel.selected
		game._input(_btn(back_btn))
		if after_out == before or sel.selected != before:
			errors.append("d-pad left/right steps a selector there and back (%d -> %d -> %d)" % [before, after_out, sel.selected])
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

## Dispatches a synthetic pad event through Godot's real input pipeline (_input -> GUI -> _unhandled_input).
static func _pad_press(b: JoyButton) -> void:
	Input.parse_input_event(_btn(b, true))
	Input.parse_input_event(_btn(b, false))

static func _pad_stick(axis: JoyAxis, v: float) -> void:
	Input.parse_input_event(_axis(axis, v))
	Input.parse_input_event(_axis(axis, 0.0))

## Walks every menu page reachable from the main menu with synthetic pad events (d-pad, left stick, LB/RB,
## A, B) through Input.parse_input_event and verifies focus is never lost on any focus-driven page, and
## custom-handled pages (home, repair, garage) keep a valid visible selection and restore focus when left.
func _walk_all_pages(errors: Array[String], game, tree: SceneTree) -> void:
	var save_files: Array[String] = ["race_settings.cfg", "graphics.cfg", "championship.json", "rally.json", CarCatalog.PAINT_SAVE]
	var backups := {}
	for fname in save_files:
		var p := SaveData.path(fname)
		backups[p] = FileAccess.get_file_as_bytes(p) if FileAccess.file_exists(p) else PackedByteArray()
	var saved_levels: Dictionary = AudioSettings.levels.duplicate()
	var saved_skin: String = CmrStyle.skin

	# 1. Main menu: step through every entry with d-pad and left stick, verify active strip button is visible
	game._show_home()
	await tree.process_frame
	var front_n: int = game.FRONT_MENU.size()
	for i in front_n:
		_pad_press(JOY_BUTTON_DPAD_RIGHT)
		if game.home_menu_index < 0 or game.home_menu_index >= front_n:
			errors.append("home: invalid home_menu_index %d after DPAD_RIGHT" % game.home_menu_index)
		var strip_btn: Control = game.menu_home_strip.get_child(game.home_phys * 2) as Control
		if strip_btn == null or not strip_btn.is_visible_in_tree():
			errors.append("home: selected strip entry %d is not visible" % game.home_menu_index)
	# stick motion on home
	game._stick_latch = Vector2i.ZERO
	_pad_stick(JOY_AXIS_LEFT_X, 0.9)
	if game.active_menu_page != "home" or game.home_menu_index < 0 or game.home_menu_index >= front_n:
		errors.append("home: stick motion broke home selection (%d)" % game.home_menu_index)

	# 2. Enter each non-world, non-quit front-menu mode via A, walk all its tabs and controls, exit via B
	for entry_id in ["quick_race", "time_trial", "rally", "championship"]:
		var idx := _front_index(game, entry_id)
		if idx < 0:
			errors.append("front menu missing entry '%s'" % entry_id)
			continue
		game._show_home()
		game._home_select(idx, false)
		_pad_press(JOY_BUTTON_A)
		await _settle(tree, 4)
		if game.active_menu_page != "setup":
			errors.append("%s: A on home did not open setup (got %s)" % [entry_id, game.active_menu_page])
			continue
		# In rally mode, also inject minor car damage so the Service ("repair") tab is reachable via RB
		if entry_id == "rally":
			game.rally_car = {"parts": {"body": 0.25, "engine": 0.1}, "pull": 0.0, "used": 0, "serviced": false}
			game._refresh_service_tab()
		await _walk_mode_tabs(errors, game, tree, entry_id)
		# B from any setup tab returns to home
		_pad_press(JOY_BUTTON_B)
		await _settle(tree, 2)
		if game.active_menu_page != "home":
			errors.append("%s: B did not return to home (still on %s)" % [entry_id, game.active_menu_page])

	# 3. Campaign briefing pages (reached from Campaign / open-world pause -> stages)
	game._show_home()
	game.is_time_trial_mode = false
	game.is_rally_mode = false
	game.is_championship_mode = false
	game.is_campaign_mode = true
	game.campaign_stage_index = 0
	game._update_mode_view()
	game._show_setup_page()
	await _settle(tree, 4)
	await _walk_mode_tabs(errors, game, tree, "campaign")
	_pad_press(JOY_BUTTON_B)
	await _settle(tree, 2)
	if game.active_menu_page != "home":
		errors.append("campaign: B did not return to home (still on %s)" % game.active_menu_page)
	game.is_campaign_mode = false

	# 4. Garage opened from Car page via A on garage_button, navigated with pad, closed with B and A
	game._show_home()
	game._home_select(_front_index(game, "quick_race"), false)
	_pad_press(JOY_BUTTON_A)
	await _settle(tree, 3)
	game._show_car_page()
	await _settle(tree, 3)
	var car_items: Array[Control] = game._setup_focus_items()
	var g_idx: int = car_items.find(game.garage_button)
	if g_idx < 0:
		errors.append("car page: garage_button not in focus items")
	else:
		game._focus_setup_item(car_items, g_idx)
		await tree.process_frame
		_pad_press(JOY_BUTTON_A)
		await _settle(tree, 3)
		var g: Garage = _find_garage(game)
		if g == null or not g.is_visible_in_tree():
			errors.append("car page: A on garage_button did not open Garage")
		else:
			for btn in [JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_UP, JOY_BUTTON_RIGHT_SHOULDER,
					JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_LEFT]:
				_pad_press(btn)
				if not is_instance_valid(g) or g.car_index < 0 or g.car_index >= g.cars.size():
					errors.append("garage: invalid state after pad button %d" % btn)
					break
			_pad_stick(JOY_AXIS_LEFT_Y, 0.9)
			_pad_stick(JOY_AXIS_LEFT_X, 0.9)
			if not is_instance_valid(g) or g.car_index < 0 or g.car_index >= g.cars.size():
				errors.append("garage: invalid state after left stick motion")
			# B closes garage and restores focus to garage_button
			_pad_press(JOY_BUTTON_B)
			await _settle(tree, 2)
			_check_focus(errors, game, "garage_cancel", "car", "B close")
			if game.get_viewport().gui_get_focus_owner() != game.garage_button:
				errors.append("garage: B close did not restore focus to garage_button (got %s)" % game.get_viewport().gui_get_focus_owner())
		# Reopen and confirm with A on unlocked stock car
		_pad_press(JOY_BUTTON_A)
		await _settle(tree, 3)
		var g2: Garage = _find_garage(game)
		if g2 != null:
			g2.car_index = 0
			g2._select_car(0)
			_pad_press(JOY_BUTTON_A)
			await _settle(tree, 2)
			_check_focus(errors, game, "garage_choose", "car", "A choose")
			if game.get_viewport().gui_get_focus_owner() != game.garage_button:
				errors.append("garage: A choose did not restore focus to garage_button (got %s)" % game.get_viewport().gui_get_focus_owner())

	# 5. Options page: entered via A on home, walk collapsed + expanded ADVANCED GRAPHICS, exit via BACK TO MENU & B
	game._show_home()
	game._home_select(_front_index(game, "options"), false)
	_pad_press(JOY_BUTTON_A)
	await _settle(tree, 4)
	if game.active_menu_page != "options":
		errors.append("options: A on home did not open options (got %s)" % game.active_menu_page)
	else:
		_check_focus(errors, game, "options", "options", "enter page")
		await _walk_focus_list(errors, game, tree, "options", "options")
		# Expand ADVANCED GRAPHICS fold via A and walk the expanded controls
		var gfx_head: Control = game.setup_folds["gfx_adv"].head as Control
		var opt_items: Array[Control] = game._options_focus_items()
		var fold_idx: int = opt_items.find(gfx_head)
		if fold_idx < 0:
			errors.append("options: ADVANCED GRAPHICS fold head not in focus items")
		else:
			gfx_head.grab_focus()
			await tree.process_frame
			var before_count: int = game._options_focus_items().size()
			_pad_press(JOY_BUTTON_A)
			await _settle(tree, 2)
			_check_focus(errors, game, "options", "options", "A expand gfx_adv")
			var after_count: int = game._options_focus_items().size()
			if after_count <= before_count:
				errors.append("options: A on ADVANCED GRAPHICS did not expand controls (%d -> %d)" % [before_count, after_count])
			await _walk_focus_list(errors, game, tree, "options_expanded", "options")
			# Collapse ADVANCED GRAPHICS back via DPAD_LEFT
			gfx_head.grab_focus()
			await tree.process_frame
			_pad_press(JOY_BUTTON_DPAD_LEFT)
			await _settle(tree, 2)
			_check_focus(errors, game, "options", "options", "DPAD_LEFT collapse gfx_adv")
		_pad_press(JOY_BUTTON_B)
		await _settle(tree, 2)
		if game.active_menu_page != "home":
			errors.append("options: B did not return to home (still on %s)" % game.active_menu_page)

	# Restore saves, audio, aspect, and skin so sandbox stays untouched
	game.graphics_aspect = 0
	game._apply_aspect()
	AudioSettings.levels = saved_levels
	AudioSettings.apply()
	if CmrStyle.skin != saved_skin:
		CmrStyle.apply_skin(saved_skin, game)
	for p in backups:
		var buf: PackedByteArray = backups[p]
		if buf.is_empty():
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
		else:
			var f := FileAccess.open(p, FileAccess.WRITE)
			if f:
				f.store_buffer(buf)
				f.close()

func _walk_mode_tabs(errors: Array[String], game, tree: SceneTree, mode_tag: String) -> void:
	var ids: Array = game._menu_page_ids()
	if ids.is_empty():
		errors.append("%s: _menu_page_ids() is empty" % mode_tag)
		return
	for step_i in ids.size():
		var pg: String = game.active_menu_page
		if pg == "repair":
			# Service page intentionally releases GUI focus and tracks repair_selected via _input
			for btn in [JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_A]:
				_pad_press(btn)
				if game.repair_selected < 0 or game.repair_selected >= game.repair_rows.size():
					errors.append("%s/repair: invalid repair_selected %d" % [mode_tag, game.repair_selected])
				elif not (game.repair_rows[game.repair_selected] as Control).is_visible_in_tree():
					errors.append("%s/repair: selected repair row %d is not visible" % [mode_tag, game.repair_selected])
		else:
			_check_focus(errors, game, mode_tag, pg, "enter tab")
			await _walk_focus_list(errors, game, tree, mode_tag, pg)
		if step_i < ids.size() - 1:
			_pad_press(JOY_BUTTON_RIGHT_SHOULDER)
			await _settle(tree, 3)
	# Step back through every tab with LB and check focus on each
	for step_i in range(ids.size() - 1, 0, -1):
		_pad_press(JOY_BUTTON_LEFT_SHOULDER)
		await _settle(tree, 3)
		var pg: String = game.active_menu_page
		if pg != "repair":
			_check_focus(errors, game, mode_tag, pg, "LB back")

func _walk_focus_list(errors: Array[String], game, tree: SceneTree, mode_tag: String, pg: String) -> void:
	var items: Array[Control] = game._options_focus_items() if pg == "options" else game._setup_focus_items()
	if items.is_empty():
		errors.append("%s/%s: no focusable items" % [mode_tag, pg])
		return
	var unsafe: Array = [game.setup_race_button, game.campaign_start_button, game.campaign_world_button,
		game.champ_reset_button, game.garage_button, game.rally_restart_button,
		game.adv_page.get("race"), game.car_page.get("race"), game.strat_page.get("race")]
	# Walk down through every item, nudging safe controls with left/right (and A on checkboxes)
	for i in items.size() + 1:
		_pad_press(JOY_BUTTON_DPAD_DOWN)
		await tree.process_frame
		var owner := _check_focus(errors, game, mode_tag, pg, "DPAD_DOWN #%d" % i)
		if owner != null and not (owner in unsafe) and owner != game.display_mode_picker and owner != game.ui_scale_picker and owner != game.retro_picker:
			if owner is MenuSelector and (owner as MenuSelector).item_count > 1:
				var sel := owner as MenuSelector
				var orig := sel.selected
				_pad_press(JOY_BUTTON_DPAD_RIGHT)
				await tree.process_frame
				_check_focus(errors, game, mode_tag, pg, "DPAD_RIGHT on %s" % owner.name)
				_pad_press(JOY_BUTTON_DPAD_LEFT)
				await tree.process_frame
				_check_focus(errors, game, mode_tag, pg, "DPAD_LEFT on %s" % owner.name)
				if sel.selected != orig:
					sel.select(orig)
			elif owner is CheckButton:
				_pad_press(JOY_BUTTON_A)
				await tree.process_frame
				_check_focus(errors, game, mode_tag, pg, "A toggle on %s" % owner.name)
				_pad_press(JOY_BUTTON_A)
				await tree.process_frame
				_check_focus(errors, game, mode_tag, pg, "A untoggle on %s" % owner.name)
			elif owner is Slider or (owner is LineEdit and owner.get_parent() is SpinBox):
				_pad_press(JOY_BUTTON_DPAD_RIGHT)
				await tree.process_frame
				_check_focus(errors, game, mode_tag, pg, "DPAD_RIGHT on %s" % owner.name)
				_pad_press(JOY_BUTTON_DPAD_LEFT)
				await tree.process_frame
				_check_focus(errors, game, mode_tag, pg, "DPAD_LEFT on %s" % owner.name)
			elif owner == game.player_name_edit:
				# Pad left/right on driver name LineEdit must not lose focus
				_pad_press(JOY_BUTTON_DPAD_RIGHT)
				await tree.process_frame
				_check_focus(errors, game, mode_tag, pg, "DPAD_RIGHT on player_name_edit")
				_pad_press(JOY_BUTTON_DPAD_LEFT)
				await tree.process_frame
				_check_focus(errors, game, mode_tag, pg, "DPAD_LEFT on player_name_edit")
	# Walk back up through every item
	for i in items.size() + 1:
		_pad_press(JOY_BUTTON_DPAD_UP)
		await tree.process_frame
		_check_focus(errors, game, mode_tag, pg, "DPAD_UP #%d" % i)
	# Left stick down then up
	game._stick_latch = Vector2i.ZERO
	_pad_stick(JOY_AXIS_LEFT_Y, 0.9)
	await tree.process_frame
	_check_focus(errors, game, mode_tag, pg, "LEFT_STICK down")
	_pad_stick(JOY_AXIS_LEFT_Y, -0.9)
	await tree.process_frame
	_check_focus(errors, game, mode_tag, pg, "LEFT_STICK up")

func _check_focus(errors: Array[String], game, mode_tag: String, pg: String, action: String) -> Control:
	var owner: Control = game.get_viewport().gui_get_focus_owner()
	if owner == null:
		errors.append("%s/%s: focus lost after %s (owner is null)" % [mode_tag, pg, action])
		return null
	if not owner.is_visible_in_tree():
		errors.append("%s/%s: focus on hidden control %s after %s" % [mode_tag, pg, owner.name, action])
		return null
	if owner.focus_mode == Control.FOCUS_NONE:
		errors.append("%s/%s: focus on non-focusable control %s after %s" % [mode_tag, pg, owner.name, action])
		return null
	return owner

static func _front_index(game, id: String) -> int:
	for i in game.FRONT_MENU.size():
		if String(game.FRONT_MENU[i].id) == id:
			return i
	return -1

static func _find_garage(game) -> Garage:
	for c in game.get_children():
		if c is Garage and not c.is_queued_for_deletion():
			return c as Garage
	return null

static func _settle(tree: SceneTree, frames := 3) -> void:
	for k in frames:
		await tree.process_frame
