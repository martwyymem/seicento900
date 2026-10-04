## Terrain-over-road check (dev tool): for each TRACKS circuit, where the built terrain stands above the road or
## its run-off (measured against the nearest centreline sample). godot --headless --path godot -s tests/_terrain_probe.gd
extends SceneTree

func _initialize() -> void:
	for key in OS.get_environment("TRACKS").split(","):
		var world = load("res://ui/race_world.tscn").instantiate()
		root.add_child(world)
		await process_frame
		var rs := RaceSettings.new()
		rs.track = key
		world.set_race(Race.new(rs))
		var tr: Track = world.track
		var reach: float = tr.half + tr.cfg.runoff + 3.0
		var base: float = world.elevation_base
		# a hash of the centreline samples, for the nearest one to any point
		var cells := {}
		for i in tr.n:
			var c := Vector2i(floori(tr.X[i] / 20.0), floori(tr.Y[i] / 20.0))
			if not cells.has(c):
				cells[c] = []
			cells[c].append(i)
		var worst := []
		var bad := 0
		var checked := 0
		for i in range(0, tr.n, 2):
			var j1 := (i + 1) % tr.n
			var t := Vector2(tr.X[j1] - tr.X[i], tr.Y[j1] - tr.Y[i]).normalized()
			var nrm := Vector2(-t.y, t.x)
			for side in [-1.0, 1.0]:
				var d := 0.0
				while d <= reach:
					var p: Vector2 = Vector2(tr.X[i], tr.Y[i]) + nrm * d * float(side)
					var best := -1
					var bd := INF
					var pc := Vector2i(floori(p.x / 20.0), floori(p.y / 20.0))
					for dz in range(-2, 3):
						for dx in range(-2, 3):
							for k in cells.get(pc + Vector2i(dx, dz), []):
								var dd: float = p.distance_squared_to(Vector2(tr.X[k], tr.Y[k]))
								if dd < bd:
									bd = dd
									best = k
					if best >= 0 and sqrt(bd) <= reach:
						var over: float = world._ground_at(p.x, p.y) - (tr.H[best] - base)
						checked += 1
						if over > 0.3:
							bad += 1
							worst.append([over, int(best * tr.step), snappedf(sqrt(bd), 0.1)])
					d += 3.0
		worst.sort_custom(func(a, b): return a[0] > b[0])
		print("TERRAIN ", key, " points ", checked, " over 0.3 m: ", bad, " worst [over m, S, from centre m]: ", worst.slice(0, 8).map(func(w): return [snappedf(w[0], 0.1), w[1], w[2]]))
		world.queue_free()
		await process_frame
	quit()
