## Lakes and ponds audit (dev tool, headless): where the ground the car rides and the drawn ground disagree beside
## water. A: roads near water (does the road float over a sunk bed, does the car drop off its shoulder into a hole);
## B: the shoreline band (dry land drawn below the water's surface: a pit beside the water; steps on dry land);
## C: bed vertices sunk outside every water ring.
##   timeout 600 godot --headless --path godot -s tests/_lake_probe.gd
extends SceneTree

func _initialize() -> void:
	var map := TownMap.load_map("brzeszcze")
	_roads(map)
	_shores(map)
	_bed(map)
	quit()

func _near_water(map: TownMap, p: Vector2, r: float) -> bool:
	for k in map.water_rings.size():
		if map.water_rects[k].grow(r).has_point(p):
			return true
	return false

func _roads(map: TownMap) -> void:
	var samples := 0
	var floats := 0
	var holes := 0
	var drops := 0
	var worst_float := 0.0
	var worst_hole := 0.0
	var worst_drop := 0.0
	var at_f := ""
	var at_h := ""
	var at_d := ""
	var bad_roads := {}
	for ri in map.road_pts.size():
		var pts := map.road_pts[ri]
		var near := false
		for p in pts:
			if _near_water(map, p, 30.0):
				near = true
				break
		if not near:
			continue
		var half := map.road_w[ri] * 0.5
		var s := 0.0
		while s < map.road_len[ri]:
			var a: Array = map.along(ri, s)
			s += 2.0
			var p: Vector2 = a[0]
			if map.deck_at(ri, a[2], a[3]) > 0.05 or not _near_water(map, p, 12.0):
				continue
			samples += 1
			var f: float = map.ground(p.x, p.y) - map.terrain(p.x, p.y)
			if f > 0.3:
				floats += 1
				bad_roads[ri] = true
			if f > worst_float:
				worst_float = f
				at_f = "road %d '%s' (%.0f, %.0f)" % [ri, map.road_name[ri], p.x, p.y]
			var n := Vector2(-a[1].y, a[1].x)
			for side in [-1.0, 1.0]:
				var foot: Vector2 = p + n * side * (half + TownMap.SHOULDER)
				if not map.road_at(foot.x, foot.y).is_empty() or map.kerb_at(foot.x, foot.y) > 0.0:
					continue
				var gap: float = map.ground(foot.x, foot.y) - TownMap.SHOULDER_DROP - map.terrain(foot.x, foot.y)
				if gap > 0.3:
					holes += 1
					bad_roads[ri] = true
				if gap > worst_hole:
					worst_hole = gap
					at_h = "road %d '%s' (%.0f, %.0f)" % [ri, map.road_name[ri], foot.x, foot.y]
				# a car at the road's height stepping out sideways a metre at a time
				var fc := FreeCar.new(map)
				fc.place(p, 0.0)
				var last := fc.z
				for o in range(1, int(half + 9.0)):
					var q: Vector2 = p + n * side * float(o)
					fc.car.x = q.x
					fc.car.y = q.y
					var h := fc.support(q.x, q.y)
					var d := last - h
					if d > 0.6:
						drops += 1
						bad_roads[ri] = true
						if d > worst_drop:
							worst_drop = d
							at_d = "road %d '%s' (%.0f, %.0f) %.1f m off the centre" % [ri, map.road_name[ri], q.x, q.y, o]
					fc.z = h
					last = h
	print("A roads near water: %d samples, road floats >0.3 m over the drawn bed at %d (worst %.2f at %s)" % [samples, floats, worst_float, at_f])
	print("  shoulder foot >0.3 m over the drawn terrain (a hole beside the road): %d (worst %.2f at %s)" % [holes, worst_hole, at_h])
	print("  car height drops >0.6 m per metre stepping off the road: %d (worst %.2f at %s)" % [drops, worst_drop, at_d])
	print("  roads affected: %d" % bad_roads.size())

func _in_water(map: TownMap, q: Vector2) -> bool:
	return not is_nan(map.water_at(q))

func _shores(map: TownMap) -> void:
	var pits := 0
	var deep_pits := 0
	var steps := 0
	var nan := 0
	var dry := 0
	var worst_pit := 0.0
	var worst_step := 0.0
	var at_p := ""
	var at_s := ""
	var rings_pit := {}
	for k in map.water_rings.size():
		var ring := map.water_rings[k]
		for e in ring.size():
			var a := ring[e]
			var b := ring[(e + 1) % ring.size()]
			var l := a.distance_to(b)
			if l < 0.01:
				continue
			var t := (b - a) / l
			var n := Vector2(-t.y, t.x)
			var probe := a.lerp(b, 0.5) + n * 0.5
			if Geometry2D.is_point_in_polygon(probe, ring):
				n = -n
			var u := 0.0
			while u < l:
				var base := a + t * u
				u += 3.0
				var last := NAN
				for d in range(-3, 26):
					var q := base + n * float(d)
					var h := map.terrain(q.x, q.y)
					if is_nan(h) or is_inf(h):
						nan += 1
						continue
					var wet := _in_water(map, q)
					if not wet and map.road_at(q.x, q.y, -INF, 1.0).is_empty():
						dry += 1
						var lvl := map.water_surface(q.x, q.y)
						if h < lvl - 0.3:
							deep_pits += 1
						if h < lvl - 0.05:
							pits += 1
							rings_pit[k] = true
							if lvl - h > worst_pit:
								worst_pit = lvl - h
								at_p = "pond %d (%.0f, %.0f), %.0f m out" % [k, q.x, q.y, d]
						if not is_nan(last) and absf(h - last) > 0.5:
							steps += 1
							if absf(h - last) > worst_step:
								worst_step = absf(h - last)
								at_s = "pond %d (%.0f, %.0f)" % [k, q.x, q.y]
						last = h
					else:
						last = NAN
	print("B shore band (-3..25 m) on %d rings: %d dry samples; dry land drawn below the water's surface (a pit): %d on %d rings (worst %.2f m at %s)" % [map.water_rings.size(), dry, pits, rings_pit.size(), worst_pit, at_p])
	print("  of them deeper than 0.3 m: %d" % deep_pits)
	print("  dry-land steps >0.5 m per metre: %d (worst %.2f at %s); NaN/INF heights: %d" % [steps, worst_step, at_s, nan])

func _bed(map: TownMap) -> void:
	var nx := int(map.extent.size.x / TownMap.BED_STEP) + 1
	var outside := 0
	var deep := 0.0
	var at := ""
	for kk in map.bed_mask:
		var i: int = kk % nx
		var j: int = kk / nx
		var p := map.extent.position + Vector2(i, j) * TownMap.BED_STEP
		if _in_water(map, p):
			continue
		var sink := map.ground(p.x, p.y) - map.bed_vertex(i, j, nx)
		if sink > TownMap.WATER_DROP + 0.05:
			outside += 1
		if sink > deep:
			deep = sink
			at = "(%.0f, %.0f)" % [p.x, p.y]
	print("C bed vertices: %d, of them outside every water ring and sunk below the water's surface: %d (deepest sunk %.2f m below the ground at %s)" % [map.bed_mask.size(), outside, deep, at])
