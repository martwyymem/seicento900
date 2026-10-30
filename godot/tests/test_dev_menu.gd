## The § + 1 dev menu and the Hypercar Seicento's availability: entries for the screen that is up, the menu freezes and
## releases the game, the hypercar opens at the top fan level (or from the dev menu) and every mode can pick it.
extends RefCounted

var completed := false
var errors: Array[String] = []

func check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		errors.append("%s %s" % [what, detail])

func run() -> Array:
	check("the hypercar is locked at 0 fans", not FanLevels.hypercar_unlocked(0))
	check("the hypercar is locked a level short", not FanLevels.hypercar_unlocked(FanLevels.THRESHOLDS[-1] - 1))
	check("the hypercar opens at the top level", FanLevels.hypercar_unlocked(FanLevels.THRESHOLDS[-1]))
	FanLevels.dev_unlock = true
	check("the dev override opens it", FanLevels.hypercar_unlocked(0))
	FanLevels.dev_unlock = false

	var root := (Engine.get_main_loop() as SceneTree).root
	var game = load("res://ui/game.tscn").instantiate()
	root.add_child(game)
	var menu: DevMenu = game.get_node("DevMenu")
	check("the game carries a dev menu", menu != null and menu.game == game)
	var entries: Array = game._dev_entries()
	check("the menu offers fans and the unlock switch", entries.size() >= 4 and entries.any(func(e): return String(e.label).begins_with("Unlock everything")))
	var before := Engine.time_scale
	menu.toggle()
	check("opening the menu freezes the game", menu.is_open() and Engine.time_scale == 0.0)
	menu.toggle()
	check("closing it lets the game run again", not menu.is_open() and Engine.time_scale == before)

	# the unlock entry flips the override; with it, every mode can pick the hypercar
	var unlock = entries.filter(func(e): return String(e.label).begins_with("Unlock everything"))[0]
	unlock.do.call()
	check("the unlock entry switches the override on", FanLevels.dev_unlock)
	game.car_class_picker.select(1)
	game._on_car_class_selected(1)
	check("the car picker keeps the hypercar once it is open", game.car_class_picker.selected == 1)
	var models: Dictionary = game._models_for("hypercar")
	check("a hypercar race runs on the hypercar's model and its own strategist", models.car_model.spec.awd and models.strategy != game.strategy)
	check("a stock race keeps the stock model", not game._models_for("stock").car_model.spec.awd)
	FanLevels.dev_unlock = false
	game.car_class_picker.select(0)

	# the open world's car swap
	var fc := FreeCar.new(null)
	fc.fit_model(Hypercar.model())
	check("fitting the hypercar swaps the open-world car's model and drivetrain", fc.model.spec.awd and fc.car.model == fc.model
		and fc.car.physics == fc.phys and fc.car.phys == null and fc.car.rpm == fc.model.spec.idle_rpm)
	game.queue_free()
	completed = true
	return errors
