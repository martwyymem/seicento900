## QA probe (dev tool, run windowed): boots the game, walks the main menu and every page with keyboard and
## simulated joypad events, saves screenshots to /tmp/qa/menu/ and prints the focus owner after each step.
## godot --path godot --audio-driver Dummy -s tests/_qa_menu.gd
extends SceneTree

var game
const OUT := "/tmp/qa/menu"

func _wait(frames: int) -> void:
	for k in frames:
		if game and game.paused:
			game._set_paused(false)
		if game:
			game._app_focused = true
		await process_frame

func _shot(tag: String) -> void:
	await _wait(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, tag])
	var owner: Control = root.gui_get_focus_owner()
	print("QA shot %s: page %s, focus %s" % [tag, game.active_menu_page, _name(owner)])

func _name(c: Control) -> String:
	if c == null:
		return "<none>"
	var t := ""
	if c is Button:
		t = (c as Button).text
	return "%s '%s' (%s)" % [c.get_class(), t.substr(0, 40), c.name]

func _key(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await process_frame
	await _wait(2)

func _pad(button: JoyButton) -> void:
	for pressed in [true, false]:
		var ev := InputEventJoypadButton.new()
		ev.button_index = button
		ev.pressed = pressed
		ev.device = 0
		Input.parse_input_event(ev)
		await process_frame
	await _wait(2)

func _stick(axis: JoyAxis, v: float) -> void:
	for val in [v, 0.0]:
		var ev := InputEventJoypadMotion.new()
		ev.axis = axis
		ev.axis_value = val
		ev.device = 0
		Input.parse_input_event(ev)
		await process_frame
	await _wait(2)

func _initialize() -> void:
	Brain.use_disk = false
	DirAccess.make_dir_recursive_absolute(OUT)
	game = load("res://ui/game.tscn").instantiate()
	root.add_child(game)
	await _wait(40)
	var f: Font = game.theme.default_font
	for ch in ["Ⓐ", "Ⓑ", "✚", "◂", "▸", "▾", "↑", "↓", "·"]:
		print("QA glyph %s in Nunito: %s, in font chain: %s" % [ch, CmrStyle.FACE.has_char(ch.unicode_at(0)), f.has_char(ch.unicode_at(0))])
	# a label with every pad prompt, to see whether the glyphs render
	var probe := Label.new()
	probe.text = "\n".join(game.PAD_KEYS.values()) + "\nMAIN MENU (Ⓑ)"
	probe.position = Vector2(40, 40)
	probe.add_theme_font_size_override("font_size", 22)
	probe.z_index = 100
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.85)
	bg.size = Vector2(900, 200)
	bg.position = Vector2(30, 30)
	game.add_child(bg)
	game.add_child(probe)
	await _shot("00_pad_glyphs")
	probe.queue_free()
	bg.queue_free()
	for i in game.FRONT_MENU.size():
		game._home_select(i, false)
		await _shot("01_home_%d_%s" % [i, game.FRONT_MENU[i].id])
	game._home_select(0, false)
	# keyboard on home
	await _key(KEY_RIGHT)
	print("QA home after Right: ", game.home_menu_index)
	await _pad(JOY_BUTTON_DPAD_RIGHT)
	print("QA home after pad right: ", game.home_menu_index)
	await _stick(JOY_AXIS_LEFT_X, -1.0)
	print("QA home after stick left: ", game.home_menu_index)
	await _stick(JOY_AXIS_LEFT_X, -1.0)
	print("QA home after stick left x2: ", game.home_menu_index)
	# QUICK RACE via pad A
	game._home_select(1, false)
	await _pad(JOY_BUTTON_A)
	await _wait(10)
	await _shot("02_quick_setup")
	for k in 6:
		await _pad(JOY_BUTTON_DPAD_DOWN)
	await _shot("03_quick_setup_down6")
	await _pad(JOY_BUTTON_DPAD_RIGHT)
	await _shot("04_quick_setup_nudged")
	await _stick(JOY_AXIS_LEFT_Y, 1.0)
	await _stick(JOY_AXIS_LEFT_Y, 1.0)
	await _shot("05_quick_setup_stick")
	await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	await _shot("06_info_page")
	await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	await _shot("07_repair_page")
	await _pad(JOY_BUTTON_LEFT_SHOULDER)
	await _pad(JOY_BUTTON_LEFT_SHOULDER)
	await _shot("08_back_to_setup")
	await _key(KEY_END)
	await _shot("09_setup_end")
	await _pad(JOY_BUTTON_B)
	await _shot("10_home_after_B")
	# TIME TRIAL via keyboard
	game._home_select(3, false)
	await _key(KEY_ENTER)
	await _wait(10)
	await _shot("11_time_trial_setup")
	print("QA time trial opponents: ", game.opponents_picker.value, " title ", game.setup_title_label.text)
	await _key(KEY_ESCAPE)
	# CHAMPIONSHIP
	game._home_select(4, false)
	await _key(KEY_ENTER)
	await _wait(10)
	await _shot("12_champ_setup")
	for k in 12:
		await _key(KEY_DOWN)
	await _shot("13_champ_setup_down12")
	for k in 12:
		await _key(KEY_DOWN)
	await _shot("14_champ_setup_down24")
	await _key(KEY_ESCAPE)
	# RALLY
	game._home_select(2, false)
	await _key(KEY_ENTER)
	await _wait(10)
	await _shot("15_rally_setup")
	await _key(KEY_ESCAPE)
	# OPTIONS
	game._home_select(5, false)
	await _pad(JOY_BUTTON_A)
	await _wait(10)
	await _shot("16_options")
	for k in 10:
		await _pad(JOY_BUTTON_DPAD_DOWN)
	await _shot("17_options_down10")
	for k in 20:
		await _pad(JOY_BUTTON_DPAD_DOWN)
	await _shot("18_options_down30")
	await _pad(JOY_BUTTON_B)
	await _shot("19_home_after_options")
	game.queue_free()
	await process_frame
	print("QA done")
	quit()
