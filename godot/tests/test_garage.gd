## Factory paints and the garage: every catalogue car has a palette of its real paints (the hypercar's livery first); an old
## free colour lands on the nearest one; the AI field and the street rivals draw theirs from the driven car's palette,
## deterministically, neighbours differing and the player's paint left out; a race's bots wear them. The Garage screen
## steps cars (LB RB, ↑ ↓) and paints (◂ ▸), refuses a locked car with how it is won, B closes it, and it fits at 16:9, 4:3
## and 21:9. The set-up page's CAR & PAINT button opens it and takes what is chosen.
extends RefCounted

var completed := false
var errors: Array[String] = []

func check(ok: bool, what: String) -> void:
	if not ok:
		errors.append(what)

static func _btn(b: JoyButton, pressed := true) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	e.pressed = pressed
	return e

func run() -> Array:
	_palettes()
	_field()
	_race_field()
	await _screen()
	await _setup_button()
	completed = true
	return errors

func _palettes() -> void:
	for key in CarCatalog.KEYS:
		var pal := CarCatalog.palette(key)
		check(pal.size() >= 8 and pal.size() <= 12, "%s has %d factory paints (8-12 expected)" % [key, pal.size()])
		var names := {}
		for i in pal.size():
			names[String(pal[i].name)] = true
			check(CarCatalog.nearest_paint(key, pal[i].color) == i, "%s: %s does not map to itself" % [key, pal[i].name])
		check(names.size() == pal.size(), "%s has a paint name twice" % key)
	check(CarCatalog.palette("hypercar")[0].color == Hypercar.PAINT, "the hypercar's first paint is not its AF Corse livery")
	check(CarCatalog.paint_name("stock", Color("#b3121d")) == "Rosso Corsa", "the old default red is not Rosso Corsa (%s)" % CarCatalog.paint_name("stock", Color("#b3121d")))
	check(CarCatalog.paint_name("golf4", Color("#bfc3c6")) == "Reflex Silver", "a light grey is not the Golf's Reflex Silver")
	check(CarCatalog.paint_name("logan", Color("#0d1b4c")) == "Bleu Navy", "a navy is not the Logan's Bleu Navy (%s)" % CarCatalog.paint_name("logan", Color("#0d1b4c")))
	check(CarCatalog.saved_paint("hypercar", Color.RED) == Hypercar.PAINT, "the hypercar's paint is not its livery")
	var cfg := ConfigFile.new() # (the sandbox's garage.cfg is put back afterwards, so probes keep their own paint)
	var had := cfg.load(SaveData.path(CarCatalog.PAINT_SAVE)) == OK
	CarCatalog.save_paint("logan", Color("#6c7075"))
	check(CarCatalog.saved_paint("logan", Color.WHITE) == Color("#6c7075"), "the garage's paint for the Logan is not kept")
	if had:
		cfg.save(SaveData.path(CarCatalog.PAINT_SAVE))
	else:
		DirAccess.remove_absolute(SaveData.path(CarCatalog.PAINT_SAVE))

func _field() -> void:
	for key in CarCatalog.KEYS:
		var pal: Array = CarCatalog.palette(key).map(func(e: Dictionary) -> Color: return e.color)
		var player: Color = pal[1 % pal.size()]
		var prev := Color(-1, -1, -1)
		for i in 15:
			var c := CarCatalog.field_color(key, i, player)
			check(c in pal, "%s: AI car %d's colour is not a factory paint" % [key, i])
			check(c == CarCatalog.field_color(key, i, player), "%s: AI car %d's colour changes between calls" % [key, i])
			check(c != prev, "%s: AI cars %d and %d share a paint" % [key, i - 1, i])
			check(c != player, "%s: AI car %d wears the player's paint" % [key, i])
			prev = c

func _race_field() -> void:
	var rs := RaceSettings.new()
	rs.track = "gp"
	rs.laps = 1
	rs.opponents = 7
	rs.car_class = "golf4"
	rs.player_color = Color("#c4161c") # Tornado Red
	var cm := CarCatalog.model("golf4")
	var r := Race.new(rs, {"stints": [{"c": "M", "laps": 1}]}, 11, {"car_model": cm, "tyres": Tyres.new(), "strategy": Strategy.new(cm, Tyres.new())})
	var pal: Array = CarCatalog.palette("golf4").map(func(e: Dictionary) -> Color: return e.color)
	for c in r.cars:
		if not c.is_player:
			check(c.color in pal, "a Golf race's bot %s is not in a Golf paint" % c.name)
			check(c.color != rs.player_color, "a Golf race's bot %s wears the player's Tornado Red" % c.name)
	r.dispose()

func _screen() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var host := Control.new()
	host.theme = CmrStyle.build_theme()
	tree.root.add_child(host)
	for canvas in [Vector2(1600, 900), Vector2(1600, 1200), Vector2(2133, 900)]:
		host.size = canvas
		var g := Garage.open_in(host, "stock", Color("#b3121d"), 0)
		var seen := {"chosen": "", "closed": false}
		g.chosen.connect(func(k: String, _c: Color) -> void: seen.chosen = k)
		g.closed.connect(func() -> void: seen.closed = true)
		for k in 4:
			await tree.process_frame
		check(g.current_key() == "stock" and String(g.paints()[g.paint_index].name) == "Rosso Corsa", "the garage does not open on the stock car in Rosso Corsa")
		if canvas.y == 900.0: # opened on another car's paint, it shows that paint, not the first
			var g2 := Garage.open_in(host, "golf4", Color("#c4161c"), 0)
			await tree.process_frame
			check(String(g2.paints()[g2.paint_index].name) == "Tornado Red", "the garage opens the Golf in %s, not the Tornado Red it wears" % g2.paints()[g2.paint_index].name)
			g2.cancel()
		# layout: the side panel's list fits, nothing runs off the canvas or into the stand
		var panel: Control = g._rows.get_parent().get_parent()
		var inner: Control = g._rows.get_parent()
		check(inner.get_combined_minimum_size().y <= panel.size.y + 1.0, "%s: the garage's side panel overflows (%.0f > %.0f)" % [canvas, inner.get_combined_minimum_size().y, panel.size.y])
		check(Rect2(Vector2.ZERO, canvas).encloses(panel.get_global_rect()), "%s: the side panel leaves the canvas" % canvas)
		check(not g._view_box.get_global_rect().grow(-2).intersects(panel.get_global_rect()), "%s: the stand runs under the side panel" % canvas)
		check(not g._name.get_parent().get_global_rect().intersects(panel.get_global_rect()), "%s: the car's name runs under the side panel" % canvas)
		# pad: RB / LB change car, ◂ ▸ the paint
		g._input(_btn(JOY_BUTTON_RIGHT_SHOULDER))
		check(g.current_key() == CarCatalog.KEYS[1], "RB does not step to the next car")
		g._input(_btn(JOY_BUTTON_LEFT_SHOULDER))
		check(g.current_key() == "stock", "LB does not step back")
		g._input(_btn(JOY_BUTTON_DPAD_RIGHT))
		check(g.paint_index == 1 and g.current_color() == CarCatalog.palette("stock")[1].color, "◂ ▸ do not step the paint")
		g._input(_btn(JOY_BUTTON_DPAD_RIGHT, false))
		check(g.paint_index == 1, "a release steps the paint")
		# a locked car (the hypercar at no fans): dimmed, its hint, A refused
		g.car_index = CarCatalog.KEYS.find("hypercar") - 1
		g.step_car(1)
		if not FanLevels.dev_unlock:
			check(g.is_locked() and g.hint_text().contains("fan level"), "the hypercar at no fans is not locked with its hint (%s)" % g.hint_text())
			check(g._view_box.modulate.r < 0.5, "a locked car is not dimmed")
			check(g.paints().size() == 1, "the hypercar offers more than its livery")
			g._input(_btn(JOY_BUTTON_A))
			check(seen.chosen == "" and is_instance_valid(g) and not g.is_queued_for_deletion(), "A on a locked car takes it")
		for k in CarCatalog.KEYS:
			if k != "stock" and k != "hypercar" and not CarCatalog.unlocked(k, 0):
				g.car_index = CarCatalog.KEYS.find(k) - 1
				g.step_car(1)
				check(g.hint_text().contains("campaign mission"), "%s's hint does not name its mission (%s)" % [k, g.hint_text()])
		g._input(_btn(JOY_BUTTON_B))
		check(seen.closed, "B does not close the garage")
		await tree.process_frame
	host.queue_free()
	await tree.process_frame

func _setup_button() -> void:
	Brain.use_disk = false
	LapRecords.use_disk = false
	var tree := Engine.get_main_loop() as SceneTree
	var game = load("res://ui/game.tscn").instantiate()
	tree.root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	game.size = Vector2(1600, 900)
	for k in 3:
		await tree.process_frame
	game.is_campaign_mode = false
	game._show_setup_page()
	game._show_car_page() # DRIVER & CAR: the page CAR & PAINT is on
	for k in 4:
		await tree.process_frame
	var items: Array = game._setup_focus_items()
	check(game.garage_button in items, "CAR & PAINT is not on the set-up page's list")
	check(not (game.car_class_picker in items) and not (game.player_color_picker in items), "the old CAR picker or paint swatch is still on the list")
	game.car_class_picker.select(0)
	game._on_car_class_selected(0)
	game._step_garage_paint(1)
	var pal := CarCatalog.palette("stock")
	check(game.player_color_picker.color in pal.map(func(e: Dictionary) -> Color: return e.color), "◂ ▸ on CAR & PAINT leaves the palette")
	game._update_menu_car_summary()
	check(String(game.garage_button.text).contains(CarCatalog.paint_name("stock", game.player_color_picker.color)), "CAR & PAINT does not name the paint (%s)" % game.garage_button.text)
	var g: Garage = game._open_garage()
	await tree.process_frame
	g.step_paint(1)
	var want := g.current_color()
	g.choose()
	await tree.process_frame
	check(game.player_color_picker.color == want and game._picked_car() == "stock", "the garage's choice is not taken by the set-up")
	game.queue_free()
	await tree.process_frame
