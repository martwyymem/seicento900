## The loading screens: the race loader's hero stills (one per circuit, a night one where it has one), its clock, its tips and
## its layout at the canvas shapes the Options aspect picker offers; the open-world cover's stills all exist.
extends RefCounted

const GAME := preload("res://scripts/ui/game.gd")
var completed := false

func run() -> Array:
	var errors: Array[String] = []
	# every circuit the game can load has a hero still
	for key in GAME.TRACK_KEYS + ["maly_bor", "kolonia_stawowa", "babudy_gora", "rajsko_wilczkowice", "lipowiec_kobylec"]:
		if LoadingScreen.hero_path(key) == "":
			errors.append("no hero still for %s (textures/loading/hero_%s.jpg)" % [key, key])
	if LoadingScreen.hero_path("") != "" or LoadingScreen.hero_path("no_such_circuit") != "":
		errors.append("a circuit without a still must give an empty path")
	# every catalogue car has its own cover stills (at least 3, all on disk), a car without any falls back to the stock set,
	# and the cover shows the driven car's set and its own figures
	for car in OpenWorldCover.SHOTS:
		for shot in OpenWorldCover.SHOTS[car]:
			if not ResourceLoader.exists(OpenWorldCover.DIR + String(shot[0])):
				errors.append("the %s cover still %s is missing" % [car, shot[0]])
	for car in CarCatalog.KEYS:
		var set := OpenWorldCover.shots_for(car)
		if set.size() < 3 or (car != "stock" and set == OpenWorldCover.SHOTS.stock):
			errors.append("%s has no cover stills of its own (textures/loading/%s_<n>.jpg)" % [car, car])
		var hero := LoadingScreen.hero_path("monza", 13.0, car)
		if hero == "" or (car != "stock" and hero == LoadingScreen.hero_path("monza", 13.0)):
			errors.append("%s: the race loader shows %s at monza (the stock field)" % [car, hero])
	if OpenWorldCover.shots_for("no_such_car") != OpenWorldCover.SHOTS.stock or LoadingScreen.hero_path("monza", 13.0, "no_such_car") != LoadingScreen.hero_path("monza", 13.0):
		errors.append("a car without stills must fall back to the stock set")
	if LoadingScreen.hero_path("no_such_circuit", 13.0, "hypercar") != "":
		errors.append("a circuit without a still must give an empty path for every car")
	var cover := OpenWorldCover.new()
	for car in CarCatalog.KEYS:
		cover.open(CarCatalog.spec(car), CarCatalog.display_name(car), 0, car)
		if cover.shots != OpenWorldCover.shots_for(car) or cover._photo.texture == null:
			errors.append("the cover for %s does not show its own still" % car)
		var top := "%d km/h" % roundi(OpenWorldCover.car_stats(CarCatalog.spec(car)).top_kmh)
		var shown: Label = cover._stats_row.get_child(cover._stats_row.get_child_count() - 5).get_child(1) # the new TOP SPEED (old rows wait on queue_free)
		if shown.text != top:
			errors.append("the cover for %s shows %s, its spec gives %s" % [car, shown.text, top])
	cover.free()
	# the night still is taken after dark only, and only where the circuit has one
	for key in GAME.TRACK_KEYS:
		var night := "res://textures/loading/hero_%s_night.jpg" % key
		var path := LoadingScreen.hero_path(key, 22.0)
		if ResourceLoader.exists(night) != (path == night):
			errors.append("%s: the night still is %s at 22:00" % [key, path])
		if LoadingScreen.hero_path(key, 13.0) == night:
			errors.append("%s: the night still shows at 13:00" % key)
	if LoadingScreen.clock_text(17.5) != "17:30" or LoadingScreen.clock_text(24.0) != "00:00" or LoadingScreen.clock_text(9.999) != "10:00":
		errors.append("clock_text: %s %s %s" % [LoadingScreen.clock_text(17.5), LoadingScreen.clock_text(24.0), LoadingScreen.clock_text(9.999)])
	for weather in ["dry", "wet", "snow", "hail", "fog", "variable"]:
		for hour in [3.0, 12.0, 22.0]:
			for mode in ["race", "rally", "time_trial"]:
				if LoadingScreen.pick_tip(weather, hour, mode) == "":
					errors.append("no tip for %s %s %s" % [weather, hour, mode])
	# the screen opens with and without a picture, and its progress row fills
	var screen := LoadingScreen.new()
	screen.open(["monza", "6 laps"], "Circuit Length", "5.79 km")
	screen.open(["monza", "6 laps"], "Circuit Length", "5.79 km", {"track": "monza", "hour": 17.5, "weather": "wet", "mode": "race", "facts": [["FIELD", "16 cars"]]})
	screen.set_progress(0.5)
	if screen._blocks.filter(func(b: ColorRect) -> bool: return b.color == screen.BLOCK_ON).size() != LoadingScreen.BLOCKS / 2:
		errors.append("half the progress must light half the blocks")
	if not screen._photo.visible:
		errors.append("monza's still is not shown")
	screen.open(["x"], "Circuit Length", "1 km", {"track": "no_such_circuit"})
	if screen._photo.visible:
		errors.append("a circuit without a still must hide the picture")
	screen.free()
	completed = true
	return errors
