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
	for shot in OpenWorldCover.SHOTS:
		if not ResourceLoader.exists("res://textures/loading/%s" % shot[0]):
			errors.append("the cover still %s is missing" % shot[0])
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
