extends SceneTree
func _initialize() -> void:
	root.size = Vector2i(800, 450)
	var keys := OS.get_environment("TRACKS").split(",")
	for key in keys:
		var world = load("res://ui/race_world.tscn").instantiate()
		root.add_child(world)
		await process_frame
		var rs := RaceSettings.new()
		rs.track = key
		var race := Race.new(rs)
		world.set_race(race)
		await process_frame
		var tr: Track = world.track
		var worst := -99.0
		var ws := 0.0
		var wd := 0.0
		var s := 0.0
		while s < tr.L:
			var i := int(roundf(s / tr.step)) % tr.n
			for d in range(-40, 41, 2):
				var x: float = tr.X[i] - tr.TY[i] * d
				var z: float = tr.Y[i] + tr.TX[i] * d
				var inside: bool = absf(d) <= tr.half
				var road: float = (tr.H[i] - world.elevation_base) + tr.bank_rise(s, d)
				var g: float = world.surroundings.ground_height(x, z)
				if g - road > worst and absf(d) > tr.half + 1.0:
					worst = g - road; ws = s; wd = d
			s += 20.0
		print("RES ", key, " worst ground-road=", snappedf(worst, 0.01), " at s=", ws, " d=", wd)
		world.queue_free()
		await process_frame
	quit()
