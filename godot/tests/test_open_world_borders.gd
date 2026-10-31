## Open-world borders (TASKS.md Phase 0 item 5), checked on the baked data: every road that reaches the play area's edge
## ends in a barrier closure, no road runs past the edge, no content lies beyond the baker's CONTENT_MARGIN, and each S1
## turn-around loop joins the two carriageways. Also times a cold map load.
## Run through tests/run_qa.gd (not yet listed in run_tests.gd's SUITES).
extends RefCounted

var completed := false

## Must match CONTENT_MARGIN in tools/build_open_world.py; the slack covers rounding to 0.1 m and polygon-offset noise.
const CONTENT_MARGIN := 240.0
const SLACK := 3.0
## A dead end this close to the outline (the baker's own 40 m) must carry a closure within CLOSURE_REACH of its barrier.
const END_REACH := 40.0
const CLOSURE_REACH := 12.0
## Known baker defect (tools/build_open_world.py, "the barrier stands a few metres inside"): it puts the barrier on the
## first road vertex at least 4 m from the end, so on a sparsely noded road it stands up to ~170 m inside the edge and
## leaves a dead stub of road beyond it. Reported as a warning; the test only fails if it gets worse than today's data.
const STUB_MAX := 45.0
const KNOWN_FAR_CLOSURES := 40
const KNOWN_OUTSIDE_CLOSURES := 1
const KNOWN_WORST_STUB := 175.0
## The places whose edges the user asked for, and how far from each a closure must exist
const REGIONS := ["Wola", "Rajsko", "Jawiszowice", "Góra", "Gilowice"]
const REGION_REACH := 2400.0
## Known baker defects, frozen so they cannot grow (set to 0 once tools/build_open_world.py is fixed): fences (OSM barrier ways
## and generated plot boundaries) and garden beds are not cut to CONTENT_MARGIN like buildings and trees are, so some stand
## up to 2 km out in the countryside the player can never reach; and a few edge road ends get no barrier because the baker
## skips a closure within 12 m of another or a node shared more than once.
const KNOWN_BEYOND_MARGIN := {"fence": 542, "garden bed": 309}
const KNOWN_UNCAPPED_ENDS := 6

static func poly_dist(p: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	for i in poly.size():
		var c := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
		best = minf(best, p.distance_to(c))
	return best

static func path_dist(p: Vector2, path: PackedVector2Array) -> float:
	var best := INF
	for i in path.size() - 1:
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, path[i], path[i + 1])))
	return best

## Distance beyond the polygon (0 inside).
static func outside_by(p: Vector2, poly: PackedVector2Array) -> float:
	return 0.0 if Geometry2D.is_point_in_polygon(p, poly) else poly_dist(p, poly)

var _stub_report := ""

func check_max(errors: Array[String], what: String, got: int, ceiling: int) -> void:
	if got > ceiling:
		errors.append("%s: %d, worse than the known %d" % [what, got, ceiling])

func run() -> Array:
	var errors: Array[String] = []
	var t0 := Time.get_ticks_msec()
	var map := TownMap.new()
	var ok := map._load(OpenWorld.MAP_KEY)
	print("    cold TownMap load of %s: %d ms" % [OpenWorld.MAP_KEY, Time.get_ticks_msec() - t0])
	if not ok or map.play.size() < 3:
		errors.append("the map did not load, or has no play outline")
		completed = true
		return errors
	_closures(map, errors)
	_dead_ends(map, errors)
	_roads_inside(map, errors)
	_regions(map, errors)
	_content(map, errors)
	_loops(map, errors)
	completed = true
	return errors

func _closures(map: TownMap, errors: Array[String]) -> void:
	_stub_report = ""
	if map.closures.size() < 20:
		errors.append("only %d closures" % map.closures.size())
	var fence_ends := PackedVector2Array()
	for f in map.raw.get("fences", []):
		if int(f[4]) == 4: # style 4: the barrier segment the car collides with
			fence_ends.append(Vector2(f[0], f[1]))
			fence_ends.append(Vector2(f[2], f[3]))
	var far := 0
	var worst_far := 0.0
	var outside := 0
	for c in map.closures:
		var p := Vector2(float(c[0]), float(c[1]))
		var turn := int(c[4]) == 1
		var d := poly_dist(p, map.play)
		if not turn and d > STUB_MAX:
			far += 1
			worst_far = maxf(worst_far, d)
		if outside_by(p, map.play) > 0.0 and not turn:
			outside += 1
		if float(c[3]) < 0.0:
			errors.append("closure at %s has width %.1f" % [p, float(c[3])])
		var near := false
		for q in fence_ends:
			if p.distance_to(q) < 20.0:
				near = true
				break
		if not near:
			errors.append("closure at %s has no collision barrier (style-4 fence) within 20 m" % p)
	print("    WARN %d closures stand more than %.0f m inside the outline (worst %.0f m), %d outside it" % [far, STUB_MAX, worst_far, outside])
	check_max(errors, "closures more than %.0f m inside the outline" % STUB_MAX, far, KNOWN_FAR_CLOSURES)
	check_max(errors, "closures outside the play outline", outside, KNOWN_OUTSIDE_CLOSURES)
	check_max(errors, "m of the worst road stub beyond a barrier", int(worst_far), int(KNOWN_WORST_STUB))

## Every road end near the outline that no other road meets is capped by a closure.
func _dead_ends(map: TownMap, errors: Array[String]) -> void:
	var seen := 0
	var uncapped := 0
	for ri in map.road_pts.size():
		var marks: Array = map.road_marks[ri]
		var pts := map.road_pts[ri]
		if marks.size() < 2 or pts.size() < 2:
			continue
		for end in 2:
			var node := str(marks[0][1] if end == 0 else marks[marks.size() - 1][1])
			var q: Vector2 = pts[0] if end == 0 else pts[pts.size() - 1]
			if map.node_edges.has(node) and (map.node_edges[node] as Array).size() > 1:
				continue # joined to another stretch
			if poly_dist(q, map.play) > END_REACH and Geometry2D.is_point_in_polygon(q, map.play):
				continue # an ordinary dead end inside the play area
			seen += 1
			var capped := false
			for c in map.closures:
				var cp := Vector2(float(c[0]), float(c[1]))
				if q.distance_to(cp) > KNOWN_WORST_STUB + 10.0:
					continue
				if int(c[4]) == 1 or path_dist(cp, map.road_pts[ri]) < 3.0: # a turn-around, or a barrier standing on this very road
					capped = true
					break
			if not capped:
				uncapped += 1
				if uncapped > KNOWN_UNCAPPED_ENDS:
					errors.append("road %s '%s' (%s) ends at %s on the edge with no closure" % [map.raw.roads[ri].id, map.road_name[ri], map.road_kind[ri], q])
	print("    WARN %d of %d edge road ends have no barrier on their road (known: %d)" % [uncapped, seen, KNOWN_UNCAPPED_ENDS])
	if seen < 40:
		errors.append("only %d edge road ends found; expected dozens" % seen)

func _roads_inside(map: TownMap, errors: Array[String]) -> void:
	var worst := 0.0
	var bad := 0
	for ri in map.road_pts.size():
		for p in map.road_pts[ri]:
			var o := outside_by(p, map.play)
			if o > 2.0:
				bad += 1
				worst = maxf(worst, o)
				if bad <= 3:
					errors.append("road '%s' (%s) runs %.0f m past the play outline at %s" % [map.road_name[ri], map.road_kind[ri], o, p])
	if bad > 3:
		errors.append("%d road points in all lie past the outline (worst %.0f m)" % [bad, worst])

func _regions(map: TownMap, errors: Array[String]) -> void:
	for want in REGIONS:
		var pos := Vector2.INF
		for pl in map.places:
			if pl.name == want and String(pl.k).begins_with("place_"):
				pos = Vector2(float(pl.x), float(pl.y))
				break
		if pos == Vector2.INF:
			errors.append("place %s is not in the map" % want)
			continue
		var n := 0
		for c in map.closures:
			if pos.distance_to(Vector2(float(c[0]), float(c[1]))) < REGION_REACH:
				n += 1
		if n < 3:
			errors.append("only %d closures within %.0f m of %s" % [n, REGION_REACH, want])
		if not map.in_play(pos):
			errors.append("%s lies outside the play area" % want)

func _content(map: TownMap, errors: Array[String]) -> void:
	var lim := CONTENT_MARGIN + SLACK
	var worst := {}
	var count := {}
	var check := func(kind: String, p: Vector2) -> void:
		var o := outside_by(p, map.play)
		if o > lim:
			count[kind] = int(count.get(kind, 0)) + 1
			worst[kind] = maxf(float(worst.get(kind, 0.0)), o)
	for b in map.buildings:
		var ring: Array = b[4]
		check.call("building", Vector2(ring[0], ring[1]))
	var trees: Array = map.raw.get("trees", [])
	for k in range(0, trees.size(), 3):
		check.call("tree", Vector2(trees[k], trees[k + 1]))
	for key in ["lamps", "signals"]:
		var a: Array = map.raw.get(key, [])
		for k in range(0, a.size(), 2):
			check.call(key, Vector2(a[k], a[k + 1]))
	for s in map.raw.get("stops", []):
		check.call("stop", Vector2(s[0], s[1]))
	for f in map.raw.get("fences", []):
		check.call("fence", Vector2(f[0], f[1]))
	for pt in map.raw.get("garden_beds", []):
		check.call("garden bed", Vector2(pt[0], pt[1]))
	for k in count:
		var known: int = KNOWN_BEYOND_MARGIN.get(k, 0)
		print("    WARN %d %s(s) lie beyond the %.0f m content margin (worst %.0f m out); known: %d" % [count[k], k, CONTENT_MARGIN, worst[k], known])
		if count[k] > known:
			errors.append("%d %s(s) lie beyond the %.0f m content margin (worst %.0f m out), more than the known %d" % [count[k], k, CONTENT_MARGIN, worst[k], known])
	# the tree belt really sits on the edge: trees close to the outline, outside as well as inside
	var near_out := 0
	for k in range(0, trees.size(), 3):
		var p := Vector2(trees[k], trees[k + 1])
		if not Geometry2D.is_point_in_polygon(p, map.play) and poly_dist(p, map.play) < 30.0:
			near_out += 1
	if near_out < 500:
		errors.append("only %d trees stand just outside the outline; the edge belt is missing" % near_out)

## Each turn-around closure belongs to an S1 link whose two ends are the outbound carriageway's last node and the inbound
## one's first, and the graph lets a car from the outbound side reach the inbound side through it.
func _loops(map: TownMap, errors: Array[String]) -> void:
	var turns := 0
	for c in map.closures:
		if int(c[4]) != 1:
			continue
		turns += 1
		var p := Vector2(float(c[0]), float(c[1]))
		var link := -1
		for ri in map.road_pts.size():
			if map.road_kind[ri] != "motorway_link":
				continue
			var pts := map.road_pts[ri]
			var md := INF
			for q in pts:
				md = minf(md, q.distance_to(p))
			if md < 30.0:
				link = ri
				break
		if link < 0:
			errors.append("S1 turn-around at %s has no motorway_link loop within 30 m" % p)
			continue
		var marks: Array = map.road_marks[link]
		var a := str(marks[0][1])
		var b := str(marks[marks.size() - 1][1])
		var out_ri := -1 # the motorway stretch that ends at the loop's start node
		var in_ri := -1 # the motorway stretch that starts at its end node
		for ri in map.road_pts.size():
			if map.road_kind[ri] != "motorway":
				continue
			var m: Array = map.road_marks[ri]
			if str(m[m.size() - 1][1]) == a:
				out_ri = ri
			if str(m[0][1]) == b:
				in_ri = ri
		if out_ri < 0 or in_ri < 0:
			errors.append("S1 loop at %s does not meet a carriageway at both ends (out %d, in %d)" % [p, out_ri, in_ri])
			continue
		if out_ri == in_ri:
			errors.append("S1 loop at %s joins one carriageway to itself" % p)
		var d_out := map.road_pts[out_ri][map.road_pts[out_ri].size() - 1].distance_to(map.road_pts[in_ri][0])
		if d_out > 80.0:
			errors.append("S1 loop at %s: carriageway ends are %.0f m apart" % [p, d_out])
		if map.road_oneway[link] == 0:
			errors.append("S1 loop at %s is two-way; it must be one-way" % p)
		if not _reaches(map, str((map.road_marks[out_ri][0])[1]), str((map.road_marks[in_ri][map.road_marks[in_ri].size() - 1])[1])):
			errors.append("S1 loop at %s: no driveable path from the outbound carriageway's start to the inbound one's end" % p)
	if turns != 2:
		errors.append("expected an S1 turn-around at each end (2), found %d" % turns)

## Breadth-first over the one-way aware road graph.
func _reaches(map: TownMap, from: String, to: String) -> bool:
	if not map.node_edges.has(from) or not map.node_edges.has(to):
		return false
	var seen := {from: true}
	var queue := [from]
	while not queue.is_empty():
		var n: String = queue.pop_front()
		if n == to:
			return true
		for e in map.node_edges.get(n, []):
			if e[5] and not seen.has(e[0]):
				seen[e[0]] = true
				queue.append(e[0])
	return false
