## Open-world invisible walls: the play area's inside test is exact (Geometry2D.is_point_in_polygon misfired along lines
## through the outline's corners and edge_push() threw the car kilometres), and a car swept down every road's lanes
## touches no parked car, no fence and no play edge far from the outline (tests/_invisible_wall_probe.gd lists all).
extends RefCounted

var completed := false

func run() -> Array:
	var errors: Array[String] = []
	var map := TownMap.load_map("brzeszcze")
	if map == null:
		errors.append("data/world/brzeszcze.json did not load")
		completed = true
		return errors
	_inside(map, errors)
	_buildings(map, errors)
	_lanes(map, errors)
	completed = true
	return errors

static func _edge_dist(p: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	for i in poly.size():
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])))
	return best

## The point that misfired, and points along the lines from Godot's far ray point through each corner of the outline.
func _inside(map: TownMap, errors: Array[String]) -> void:
	var poly := map.play_inset
	if poly.size() < 3:
		errors.append("the map has no play outline")
		return
	var known := Vector2(507.4503, 1986.1515) # on Franciszka Drobniaka, 2.4 km from the edge
	if not map.in_play(known) or map.edge_push(known) != Vector2.ZERO:
		errors.append("in_play() is false 2.4 km inside the edge at %s" % known)
	var hi := Vector2(-1e20, -1e20)
	var lo := Vector2(1e20, 1e20)
	for p in poly:
		hi = hi.max(p)
		lo = lo.min(p)
	var far := hi + (hi - lo) * Vector2(1.221313, 1.512312) # where is_point_in_polygon casts its ray to
	var bad := 0
	var tested := 0
	for v in poly:
		var dir := (v - far).normalized()
		var t := 5.0
		while t < 9000.0:
			var p := v + dir * t
			t += 3.7
			if not TownMap.inside(p, map.play) or _edge_dist(p, poly) < 2.0:
				continue
			tested += 1
			if not map.in_play(p):
				bad += 1
	if tested < 500:
		errors.append("only %d points tested on the far-ray lines" % tested)
	if bad > 0:
		errors.append("in_play() is false at %d of %d points inside the outline" % [bad, tested])
	# the even-odd test agrees with a winding count on a grid
	var disagree := 0
	for x in range(-4500, 4600, 97):
		for y in range(-4300, 4600, 89):
			var p := Vector2(x + 0.37, y + 0.21)
			var wind := 0.0
			for i in map.play.size():
				wind += (map.play[i] - p).angle_to(map.play[(i + 1) % map.play.size()] - p)
			if (absf(wind) > PI) != TownMap.inside(p, map.play):
				disagree += 1
	if disagree > 0:
		errors.append("TownMap.inside disagrees with the winding number at %d grid points" % disagree)

const PROBE := preload("res://tests/_building_collision_probe.gd")

## What the car meets on a building is what is drawn: walls on the measured LoD2 roof outline (slid up to 4 m off the
## OSM ring), landmark and shaft models (their footprint below 2 m). The real build hands TownMap the faces
## (build_buildings, build_landmarks); a recording builder lists every wall drawn; no collision edge may stand more than
## 0.3 m from a drawn wall, and no drawn wall more than 0.3 m from a collision edge.
func _buildings(map: TownMap, errors: Array[String]) -> void:
	var root := Node3D.new()
	var real := TownBuilder.new(map, root)
	real.build_buildings()
	real.build_landmarks()
	var rec_root := Node3D.new()
	var rec = PROBE.Recorder.new(map, rec_root)
	rec._building_meshes()
	var models: Dictionary = PROBE.ModelRings.drawn(rec, map)
	for bi: int in models:
		var f := map.building_faces(bi)
		var segs := PackedVector2Array()
		for k in range(0, f.size(), 6):
			segs.append_array(PackedVector2Array([Vector2(f[k], f[k + 1]), Vector2(f[k + 2], f[k + 3])]))
		rec.walls[bi] = segs
	var got: Array = PROBE.BuildingAudit.measure(map, rec.walls, rec.lod2, models, 0.3)
	var stats: Dictionary = got[0]
	for kind in stats:
		var st: Array = stats[kind]
		if st[1] > 1.0 or st[3] > 1.0:
			errors.append("%s buildings: %.0f m of collision edge with no wall drawn, %.0f m of wall drawn with no collision" % [kind, st[1], st[3]])
	if not stats.has("lod2") or float(stats.lod2[0]) < 10000.0:
		errors.append("too few LoD2 buildings measured: %s" % [stats.keys()])
	for bi: int in models:
		if not map.bld_faces.has(bi):
			errors.append("building %d (%s) collides as its OSM ring, not its model" % [bi, models[bi]])
	root.free()
	rec_root.free()

## Down every road's lanes every 2 m: no parked car, no fence (closures at the edge aside) and no play edge further than
## 5 m from the outline touches the car's box.
func _lanes(map: TownMap, errors: Array[String]) -> void:
	var root := Node3D.new()
	var builder := TownBuilder.new(map, root)
	builder.build_props() # the parked cars, shelters and signals add their posts
	var trees := {}
	var raw_trees: Array = map.raw.get("trees", [])
	for k in range(0, raw_trees.size(), 3):
		trees[Vector2i(roundi(raw_trees[k] * 10.0), roundi(raw_trees[k + 1] * 10.0))] = true
	var style := {}
	for w in map.raw.get("fences", []):
		style[Vector4i(roundi(w[0] * 10.0), roundi(w[1] * 10.0), roundi(w[2] * 10.0), roundi(w[3] * 10.0))] = int(w[4]) if w.size() > 4 else 0
	var fc := FreeCar.new(map)
	var parked := 0
	var fences := 0
	var edges := 0
	var samples := 0
	var first: Array[String] = []
	for ri in map.road_pts.size():
		var len := map.road_len[ri]
		if len < 14.0:
			continue
		var lanes := [0.0] if map.road_oneway[ri] or map.road_w[ri] < 4.5 else [-map.road_w[ri] * 0.22, map.road_w[ri] * 0.22]
		for lane: float in lanes:
			var s := 6.0
			var prev := Vector2.INF
			while s < len - 6.0:
				var q: Array = map.along(ri, s)
				s += 2.0
				var dir: Vector2 = q[1]
				var p: Vector2 = q[0] + Vector2(-dir.y, dir.x) * lane
				fc.car.x = p.x
				fc.car.y = p.y
				fc.car.heading = dir.angle()
				samples += 1
				for post in map.posts_near(p, FreeCar.HALF_L + 0.6):
					if absf(post.z - 0.85) > 0.01 or trees.has(Vector2i(roundi(post.x * 10.0), roundi(post.y * 10.0))):
						continue
					var hit := fc._round_hit(Vector2(post.x, post.y), post.z)
					if not hit.is_empty() and float(hit[1]) > 0.02:
						parked += 1
						if first.size() < 6:
							first.append("parked car (%.1f, %.1f) in road %d '%s'" % [post.x, post.y, ri, map.road_name[ri]])
				if prev != Vector2.INF:
					for w in map.walls_near(p, FreeCar.HALF_L + 1.0):
						var st: int = style.get(Vector4i(roundi(w[0] * 10.0), roundi(w[1] * 10.0), roundi(w[2] * 10.0), roundi(w[3] * 10.0)), -1)
						if st == 4 or absf(w[4] - 0.25) < 0.01:
							continue # a closure across its road, or a tunnel's side wall (fences cut by TownMap.fence_pieces keep no key)
						var hit := fc._seg_contact(Vector2(w[0], w[1]), Vector2(w[2], w[3]), w[4], prev, Vector2.ZERO, true, true)
						if not hit.is_empty() and float(hit[1]) > 0.02:
							fences += 1
							if first.size() < 6:
								first.append("fence (style %d) (%.1f, %.1f)-(%.1f, %.1f) in road %d '%s'" % [st, w[0], w[1], w[2], w[3], ri, map.road_name[ri]])
				for c in fc.corners():
					if map.edge_push(c) != Vector2.ZERO and _edge_dist(c, map.play) > 5.0:
						edges += 1
						if first.size() < 6:
							first.append("play edge at %s, %.0f m from the outline" % [c, _edge_dist(c, map.play)])
						break
				prev = p
	root.free()
	if samples < 100000:
		errors.append("only %d lane samples" % samples)
	if parked + fences + edges > 0:
		errors.append("down the lanes: %d parked-car, %d fence and %d far-edge contacts, e.g. %s" % [parked, fences, edges, first])
