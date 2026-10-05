extends SceneTree
# Renders front-end pages (and optionally the race HUD) to /tmp/cmr at a given window size.
# SIZE=3840x2160 PAGES=home,setup,information,repair,options,loading,race,qualisheet godot --path godot -s tests/shot_menu.gd
var game
var frame := 0
var pages: PackedStringArray
var page_i := 0

func _init():
	Brain.use_disk = false
	var sz := (OS.get_environment("SIZE") if OS.get_environment("SIZE") else "1600x900").split("x")
	root.size = Vector2i(int(sz[0]), int(sz[1]))
	DisplayServer.window_set_size(root.size)
	pages = (OS.get_environment("PAGES") if OS.get_environment("PAGES") else "home").split(",")
	game = load("res://ui/game.tscn").instantiate()
	root.add_child(game)

var hold := 0

func _process(_dt) -> bool:
	if hold > 0:
		hold -= 1
		return false
	frame += 1
	var local := frame % 40
	if local == 5:
		match pages[page_i]:
			"home": game._show_home()
			"setup": game._show_setup_page()
			"information": game._show_information_page()
			"repair": game._show_repair_page()
			"options": game._show_options_page()
			"race": game._start_race()
			"loading":
				game.loading_screen.open(["monza", "6 laps"], "Circuit Length", "5.79 km")
				game.loading_screen.set_progress(0.6)
			"pause": game._set_paused(true)
			"results": game._show_results()
			"qualisheet": # a simulated qualifying's time sheet, OPP opponents (default 7)
				var rs := RaceSettings.new()
				rs.track = "monaco"
				rs.opponents = int(OS.get_environment("OPP")) if OS.get_environment("OPP") else 7
				Qualifying.configure(rs)
				var qr := Race.new(rs)
				game._show_quali_sheet(qr, Qualifying.sheet(qr, Qualifying.simulated_player_time(qr)), true)
				qr.dispose()
			"drive": # let the co-driver run a stretch so the HUD shows live values
				game.race.set_autopilot(true)
				hold = int(OS.get_environment("HOLD")) if OS.get_environment("HOLD") else 900
	if local == 39:
		var tag := "%s_%dx%d" % [pages[page_i], root.size.x, root.size.y]
		root.get_texture().get_image().save_png("/tmp/cmr/%s.png" % tag)
		print("saved ", tag)
		page_i += 1
		if page_i >= pages.size():
			quit()
	return false
