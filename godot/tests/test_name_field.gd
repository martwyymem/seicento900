## The driver name and the car-number box on the set-up pages: reaching them with the arrows does not start
## typing, Enter does and Enter again finishes, Esc puts the old text back, and Backspace deletes letters
## (it used to fall through to the menu's Backspace = back and leave the page).
extends RefCounted

var completed := false

static func _key(k: Key, uni := 0) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.unicode = uni
	e.pressed = true
	return e

func run() -> Array:
	var errors: Array[String] = []
	Brain.use_disk = false
	LapRecords.use_disk = false
	var tree := Engine.get_main_loop() as SceneTree
	var game = load("res://ui/game.tscn").instantiate()
	tree.root.add_child(game)
	for k in 3:
		await tree.process_frame
	game.is_campaign_mode = false
	game._show_setup_page()
	for k in 4:
		await tree.process_frame
	game._show_car_page() # DRIVER & PAINT is on the car page, folded shut until opened
	game._open_section("driver", true, false)
	for k in 4:
		await tree.process_frame
	var page: String = game.active_menu_page
	var items: Array[Control] = game._setup_focus_items()
	if not game.player_name_edit in items:
		page = ""
	if page == "":
		errors.append("no set-up page lists the driver name field")
		game.queue_free()
		await tree.process_frame
		completed = true
		return errors
	var name_edit: LineEdit = game.player_name_edit
	var spin_edit: LineEdit = game.player_number_picker.get_line_edit()
	name_edit.text = "Kubica"
	game._focus_setup_item(items, items.find(name_edit))
	await tree.process_frame
	if name_edit.is_editing():
		errors.append("arrowing onto the name field starts typing (Enter should)")
	tree.root.push_input(_key(KEY_BACKSPACE))
	await tree.process_frame
	if game.active_menu_page != page or name_edit.text != "Kubica":
		errors.append("Backspace on the name field (not typing) left the page or changed the name: %s %s" % [game.active_menu_page, name_edit.text])
	tree.root.push_input(_key(KEY_ENTER))
	await tree.process_frame
	if not name_edit.is_editing():
		errors.append("Enter on the name field does not start typing")
	for i in 6:
		tree.root.push_input(_key(KEY_BACKSPACE))
		await tree.process_frame
	if game.active_menu_page != page:
		errors.append("Backspace while typing the name left the page")
	if name_edit.text != "":
		errors.append("Backspace while typing should delete the name, left %s" % name_edit.text)
	tree.root.push_input(_key(KEY_BACKSPACE)) # nothing left to delete: still no way out
	await tree.process_frame
	if game.active_menu_page != page:
		errors.append("Backspace in the empty name field left the page")
	tree.root.push_input(_key(KEY_A, 65))
	await tree.process_frame
	tree.root.push_input(_key(KEY_ENTER))
	await tree.process_frame
	if name_edit.is_editing() or name_edit.text != "A":
		errors.append("Enter should finish typing and keep the name, got editing %s text %s" % [name_edit.is_editing(), name_edit.text])
	tree.root.push_input(_key(KEY_ENTER))
	await tree.process_frame
	tree.root.push_input(_key(KEY_B, 66))
	await tree.process_frame
	tree.root.push_input(_key(KEY_ESCAPE))
	await tree.process_frame
	if name_edit.is_editing() or name_edit.text != "A" or game.active_menu_page != page:
		errors.append("Esc while typing should put the old name back and stay on the page, got %s %s %s" % [name_edit.is_editing(), name_edit.text, game.active_menu_page])
	# the number box: the same Enter in, Enter out
	var at := items.find(spin_edit)
	if at < 0:
		errors.append("the car number box is not in the page's list")
	else:
		game._focus_setup_item(items, at)
		await tree.process_frame
		if spin_edit.is_editing():
			errors.append("arrowing onto the number box starts typing")
		tree.root.push_input(_key(KEY_ENTER))
		await tree.process_frame
		tree.root.push_input(_key(KEY_4, 52))
		await tree.process_frame
		tree.root.push_input(_key(KEY_2, 50))
		await tree.process_frame
		tree.root.push_input(_key(KEY_ENTER))
		await tree.process_frame
		if spin_edit.is_editing() or int(game.player_number_picker.value) != 42:
			errors.append("typing 42 and Enter in the number box: editing %s value %d" % [spin_edit.is_editing(), int(game.player_number_picker.value)])
	game.queue_free()
	await tree.process_frame
	completed = true
	return errors
