## Invisible-wall audit (dev tool, headless): sweeps a car along every road's lanes (and over every bridge and through
## every underpass) and logs everything solid its box touches while it is on its own carriageway, by kind: fence
## segments by style, closures, tunnel walls, parapets, buildings, trees, lamps, props (shelters, signals, parked cars,
## landmarks, billboards), piers, the edge of the play area, and height steps that stop the car (_vertical's WALL_STEP).
## A car driving down its lane should hit nothing but a closure at a road's end.
## Env: STEP (m along, default 1.0), ROADS (max roads, default all), LIST (examples per kind, default 8)
##   timeout 900 godot --headless --path godot -s tests/_invisible_wall_probe.gd
extends SceneTree

var map: TownMap
var fence_kind := {} ## Vector4i of a wall's ends (dm) -> "fence style N" / "closure" / "tunnel wall"
var post_kind := {} ## Vector2i (dm) -> "tree" / "lamp" / "prop"
var counts := {}
var examples := {}
var prims := {} ## kind -> {primitive key: true}
var list_n := 8

func _key4(a: Vector2, b: Vector2) -> Vector4i:
	return Vector4i(roundi(a.x * 10.0), roundi(a.y * 10.0), roundi(b.x * 10.0), roundi(b.y * 10.0))

func _key2(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x * 10.0), roundi(p.y * 10.0))

func _initialize() -> void:
	map = TownMap.load_map("brzeszcze")
	list_n = int(OS.get_environment("LIST")) if OS.get_environment("LIST") != "" else 8
	var step := float(OS.get_environment("STEP")) if OS.get_environment("STEP") != "" else 1.0
	var max_roads := int(OS.get_environment("ROADS")) if OS.get_environment("ROADS") != "" else 1 << 30
	for w in map.raw.get("fences", []):
		var style := int(w[4]) if w.size() > 4 else 0
		var k := "closure" if style == 4 else "fence style %d" % style
		fence_kind[_key4(Vector2(w[0], w[1]), Vector2(w[2], w[3]))] = k
		fence_kind[_key4(Vector2(w[2], w[3]), Vector2(w[0], w[1]))] = k
	var trees: Array = map.raw.get("trees", [])
	for k in range(0, trees.size(), 3):
		post_kind[_key2(Vector2(trees[k], trees[k + 1]))] = "tree"
	for p in TownMap._flat(map.raw.get("lamps", [])):
		post_kind[_key2(p)] = "lamp"
	var root := Node3D.new()
	var builder := TownBuilder.new(map, root)
	builder.build_buildings() # hands TownMap the walls drawn off the OSM rings
	builder.build_props()
	builder.build_closures()
	builder.build_landmarks()
	var t0 := Time.get_ticks_msec()
	var samples := 0
	var roads := 0
	var fc := FreeCar.new(map)
	for ri in map.road_pts.size():
		if roads >= max_roads:
			break
		var len := map.road_len[ri]
		if len < 14.0:
			continue
		roads += 1
		var lanes := [0.0] if map.road_oneway[ri] or map.road_w[ri] < 4.5 else [-map.road_w[ri] * 0.22, map.road_w[ri] * 0.22]
		for lane: float in lanes:
			var a: Array = map.along(ri, 6.0)
			fc.place(a[0], atan2(a[1].y, a[1].x))
			fc.z = map.ground(a[0].x, a[0].y) + map.deck_at(ri, a[2], a[3]) + map.road_lift(ri)
			var s := 6.0
			while s < len - 6.0:
				var q: Array = map.along(ri, s)
				var dir: Vector2 = q[1]
				# a lane keeps inside the street where it is narrowed (TownMap.road_halves: past house corners, tapers)
				var room := maxf(0.0, map.half_at(ri, int(q[2]), float(q[3])) - FreeCar.HALF_W - 0.1)
				var p: Vector2 = q[0] + Vector2(-dir.y, dir.x) * clampf(lane, -room, room)
				var prev := Vector2(fc.car.x, fc.car.y)
				fc.car.x = p.x
				fc.car.y = p.y
				fc.car.heading = atan2(dir.y, dir.x)
				fc.car.speed = 0.0
				fc._vertical(0.05, prev.x, prev.y, 900.0)
				samples += 1
				if Vector2(fc.car.x, fc.car.y).distance_to(p) > 0.01:
					_log("height step", ri, p, "step at s=%.0f" % s, str(_key2(p)))
					fc.car.x = p.x
					fc.car.y = p.y
					fc.z = fc.support(p.x, p.y)
				_diagnose(fc, ri, prev, p, s, len)
				s += step
	print("swept %d roads, %d samples in %.0f s" % [roads, samples, (Time.get_ticks_msec() - t0) / 1000.0])
	var kinds := counts.keys()
	kinds.sort()
	for k in kinds:
		print("%-16s %6d samples, %5d distinct solids" % [k, counts[k], (prims[k] as Dictionary).size()])
		for e in examples[k]:
			print("    ", e)
	root.free()
	quit()

func _log(kind: String, ri: int, p: Vector2, what: String, prim: String) -> void:
	counts[kind] = int(counts.get(kind, 0)) + 1
	if not prims.has(kind):
		prims[kind] = {}
		examples[kind] = []
	if not prims[kind].has(prim) and (examples[kind] as Array).size() < list_n:
		examples[kind].append("road %d '%s' (%s) at (%.1f, %.1f): %s" % [ri, map.road_name[ri], map.road_kind[ri], p.x, p.y, what])
	prims[kind][prim] = true

func _diagnose(fc: FreeCar, ri: int, prev: Vector2, p: Vector2, s: float, len: float) -> void:
	var c := p
	for w in map.walls_near(c, FreeCar.HALF_L + 1.0):
		var hit := fc._seg_contact(Vector2(w[0], w[1]), Vector2(w[2], w[3]), w[4], prev, Vector2.ZERO, true, true)
		if hit.is_empty() or float(hit[1]) < 0.02:
			continue
		var kind: String = fence_kind.get(_key4(Vector2(w[0], w[1]), Vector2(w[2], w[3])), "tunnel wall")
		if kind == "closure" and (s < 20.0 or s > len - 20.0):
			kind = "closure at end"
		_log(kind, ri, p, "seg (%.1f,%.1f)-(%.1f,%.1f) depth %.2f, car z %.1f" % [w[0], w[1], w[2], w[3], hit[1], fc.z], str(_key4(Vector2(w[0], w[1]), Vector2(w[2], w[3]))))
	for w in map.parapets_near(c, FreeCar.HALF_L + 1.0):
		if absf(fc.z - w[5]) >= 2.5:
			continue
		var hit := fc._seg_contact(Vector2(w[0], w[1]), Vector2(w[2], w[3]), w[4], prev, Vector2.ZERO, true, true)
		if not hit.is_empty() and float(hit[1]) > 0.02:
			_log("parapet", ri, p, "seg (%.1f,%.1f)-(%.1f,%.1f) deck %.1f car z %.1f" % [w[0], w[1], w[2], w[3], w[5], fc.z], str(_key4(Vector2(w[0], w[1]), Vector2(w[2], w[3]))))
	for bi in map.buildings_near(c, FreeCar.HALF_L + 0.6):
		var bf := map.building_faces(bi)
		for k in range(0, bf.size(), 6):
			var hit := fc._seg_contact(Vector2(bf[k], bf[k + 1]), Vector2(bf[k + 2], bf[k + 3]), 0.0, prev, Vector2(bf[k + 4], bf[k + 5]), false, false)
			if not hit.is_empty() and float(hit[1]) > 0.02:
				_log("building", ri, p, "building %d (%s%s) face %d depth %.2f" % [bi, map.buildings[bi][0], ", drawn off its ring" if map.bld_faces.has(bi) else "", k / 6, hit[1]], str(bi))
				break
	for post in map.posts_near(c, FreeCar.HALF_L + 0.6):
		var hit := fc._round_hit(Vector2(post.x, post.y), post.z)
		if not hit.is_empty() and float(hit[1]) > 0.02:
			var kind: String = post_kind.get(_key2(Vector2(post.x, post.y)), "prop r%.2f" % post.z)
			_log(kind, ri, p, "post (%.1f, %.1f) r %.2f depth %.2f" % [post.x, post.y, post.z, hit[1]], str(_key2(Vector2(post.x, post.y))))
	for pier in map.piers_near(c, FreeCar.HALF_L + 0.6):
		if fc.z < pier.w - 2.0:
			var hit := fc._round_hit(Vector2(pier.x, pier.y), pier.z)
			if not hit.is_empty() and float(hit[1]) > 0.02:
				_log("pier", ri, p, "pier (%.1f, %.1f) top %.1f car z %.1f" % [pier.x, pier.y, pier.w, fc.z], str(_key2(Vector2(pier.x, pier.y))))
	for q in fc.corners():
		if map.edge_push(q) != Vector2.ZERO:
			_log("play edge", ri, p, "corner %s pushed %.1f m" % [q, map.edge_push(q).length()], str(_key2(p.snapped(Vector2(20, 20)))))
			break
