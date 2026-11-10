## Prints the wall-hit table of test_free_car_collision.gd for FreeCar (and tests/_free_car_old.gd when present).
##   godot --headless --path godot -s tests/_collision_feel_probe.gd
extends SceneTree

func _initialize() -> void:
	var T = load("res://tests/test_free_car_collision.gd")
	var scripts := {"new": null}
	if FileAccess.file_exists("res://tests/_free_car_old.gd"):
		scripts["old"] = load("res://tests/_free_car_old.gd")
	for panels in [true, false]:
		var town = T.wall_town(panels)
		for name in scripts:
			print("--- %s, %s" % [name, "2.5 m panels" if panels else "one segment"])
			for kmh in [30.0, 60.0, 100.0, 160.0, 250.0]:
				for deg in [10.0, 45.0, 90.0]:
					var r: Dictionary = T.measure(town, deg, kmh, scripts[name])
					print("%3.0f km/h %2.0f deg: in %5.1f km/h, out %5.1f km/h (%3.0f%% of coasting), heading %+4.0f deg, pen %.2f m, crossed %s, in contact %.2f s, flips %d" % [
						kmh, deg, float(r.before) * 3.6, float(r.after) * 3.6, 100.0 * float(r.after) / maxf(float(r.free), 0.01),
						r.angle, r.pen, r.crossed, r.stuck, r.flips])
	quit(0)
