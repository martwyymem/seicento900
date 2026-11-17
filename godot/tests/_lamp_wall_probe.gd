## Headless probe: street lamps whose head (where OpenWorld hangs the pooled OmniLight) stands close to a building
## wall. The lamp light falls off as d^-1.8 (OmniLight3D omni_attenuation 1.8) and the road is 8 m below the head, so
## a wall 1.5 m from it is lit ~20x brighter than the road: an over-bright blob on the facade at night.
## Prints the distance histogram, the worst lamps (with the nearest village) and the wall/road ratio.
##   godot --headless --path godot -s tests/_lamp_wall_probe.gd
extends SceneTree

func _initialize() -> void:
	var map := TownMap.load_map("brzeszcze")
	for clear in [0.0, TownBuilder.LAMP_WALL_CLEAR]:
		print("CLEAR %.1f m (0: the drawn head, as before 2026-11-16)" % clear)
		_survey(map, clear)
	quit()

func _survey(map: TownMap, clear: float) -> void:
	var lamps := TownMap._flat(map.raw.get("lamps", []))
	var bins := {"<1": 0, "1-2": 0, "2-3": 0, "3-4": 0, "4-6": 0}
	var worst := []
	var inside := 0
	for p in lamps:
		var head := TownBuilder.lamp_head(map, p, Vector2.INF, NAN, clear)
		var h2 := Vector2(head.x, head.z)
		if map.inside_building(h2):
			inside += 1
		var best := INF
		for bi in map.buildings_near(h2, 8.0):
			var f := map.building_faces(bi)
			for k in range(0, f.size(), 6):
				var a := Vector2(f[k], f[k + 1])
				var b := Vector2(f[k + 2], f[k + 3])
				best = minf(best, Geometry2D.get_closest_point_to_segment(h2, a, b).distance_to(h2))
		if best < 1.0: bins["<1"] += 1
		elif best < 2.0: bins["1-2"] += 1
		elif best < 3.0: bins["2-3"] += 1
		elif best < 4.0: bins["3-4"] += 1
		elif best < 6.0: bins["4-6"] += 1
		if best < 3.0:
			worst.append([best, p, h2])
	worst.sort_custom(func(a, b): return a[0] < b[0])
	print("LAMPS %d, light inside a building %d, head-to-wall %s" % [lamps.size(), inside, bins])
	for w in worst.slice(0, 12):
		var place := ""
		var pd := INF
		for pl in map.places:
			var d := Vector2(float(pl.x), float(pl.y)).distance_to(w[1])
			if d < pd:
				pd = d
				place = String(pl.name)
		print("  wall %.2f m  pole (%.0f, %.0f)  head (%.1f, %.1f)  near %s (%.0f m)  wall/road light x%.0f" % [w[0], w[1].x, w[1].y, w[2].x, w[2].y, place, pd, pow(maxf(w[0], 0.3), -1.8) / pow(8.0, -1.8)])
