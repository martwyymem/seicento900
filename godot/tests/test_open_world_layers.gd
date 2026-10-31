## Layers in the open world: a car (the player's and traffic) stays on the deck it arrived on and on the ground when it
## drives under a bridge, in both directions, with no height jumps; bridge decks are solid.
extends RefCounted

var completed := false
var _climb := 0.0 ## highest the last driven car rose above the ground
const DT := 1.0 / 120.0
const MAX_BRIDGES := 14
const MAX_RUN := 160.0 ## m of a long bridge to drive from each end
const JUMP := 0.25 ## m per tick (or per traffic step) that counts as a jump

func run() -> Array:
	var errors: Array[String] = []
	var map := TownMap.load_map("brzeszcze")
	if map == null:
		errors.append("data/world/brzeszcze.json did not load")
		completed = true
		return errors
	var bridges := _bridges(map)
	if bridges.size() < 4:
		errors.append("only %d real bridges to test" % bridges.size())
	var n_deck := 0
	var n_under := 0
	var n_traffic := 0
	for b in bridges:
		for rev in [false, true]:
			n_deck += _player_over(map, b, rev, errors)
			n_traffic += _traffic_over(map, b, rev, errors)
		var under := _road_under(map, b)
		if not under.is_empty():
			for rev in [false, true]:
				n_under += _player_under(map, b, under, rev, errors)
				_traffic_under(map, under, rev, errors)
	for b in bridges:
		_respawn(map, b, errors)
	_profile(map, errors)
	_level_crossings(map, errors)
	_traffic_underpasses(map, errors)
	if n_deck < 6 or n_under < 2 or n_traffic < 6:
		errors.append("too few layer drives: %d on decks, %d under, %d traffic" % [n_deck, n_under, n_traffic])
	completed = true
	return errors

## Bridge roads with a real deck, longest first.
func _bridges(map: TownMap) -> Array:
	var out := []
	for ri in map.road_pts.size():
		if map.road_bridge[ri] != 1 or map.road_z[ri].is_empty() or map.road_len[ri] < 30.0:
			continue
		var top := 0.0
		for z in map.road_z[ri]:
			top = maxf(top, z)
		if top < 2.5 or map.road_w[ri] > 14.0:
			continue
		out.append(ri)
	return out.slice(0, MAX_BRIDGES)

func _poly(map: TownMap, ri: int, rev: bool) -> PackedVector2Array:
	var pts := map.road_pts[ri]
	var out := PackedVector2Array()
	var acc := 0.0
	for k in pts.size():
		var i := pts.size() - 1 - k if rev else k
		if k > 0:
			acc += pts[i].distance_to(pts[i + 1 if rev else i - 1])
		out.append(pts[i])
		if acc > MAX_RUN:
			break
	return out

## Pure pursuit along a polyline: steering toward the point `look` ahead of the nearest one.
func _steer(fc: FreeCar, pts: PackedVector2Array, look: float) -> float:
	var p := Vector2(fc.car.x, fc.car.y)
	var best := 0
	var bd := INF
	for i in pts.size():
		var d := p.distance_to(pts[i])
		if d < bd:
			bd = d
			best = i
	var target := pts[pts.size() - 1]
	var acc := 0.0
	for i in range(best, pts.size() - 1):
		acc += pts[i].distance_to(pts[i + 1])
		if acc >= look:
			target = pts[i + 1]
			break
	var want := (target - p).angle()
	return clampf(wrapf(want - fc.car.heading, -PI, PI) * 2.0, -1.0, 1.0)

## Drives the player's car along pts (extended by `lead` metres before the start); records the worst height step and the
## lowest/highest clearance above the expected height. `expect` is called with the car's position and gives the height it
## must be at, or NAN where it does not matter.
func _drive_line(map: TownMap, pts: PackedVector2Array, lead: float, expect: Callable, errors: Array[String], label: String) -> bool:
	var d0 := (pts[1] - pts[0]).normalized()
	var start := pts[0] - d0 * lead
	var fc := FreeCar.new(map)
	fc.place(start, d0.angle())
	fc.z = fc.support(start.x, start.y)
	fc.car.vx = d0.x * 7.0
	fc.car.vy = d0.y * 7.0
	fc.car.gear = 1
	var last := fc.z
	var worst := 0.0
	var worst_at := Vector2.ZERO
	var off := 0.0
	var off_at := Vector2.ZERO
	var end := pts[pts.size() - 1]
	var reached := false
	_climb = 0.0
	for i in int(70.0 / DT):
		fc.step(DT, 0.45, 0.0, _steer(fc, pts, 8.0))
		var p := Vector2(fc.car.x, fc.car.y)
		if absf(fc.z - last) > worst:
			worst = absf(fc.z - last)
			worst_at = p
		last = fc.z
		_climb = maxf(_climb, fc.z - map.ground(p.x, p.y))
		var want: float = expect.call(p)
		if not is_nan(want) and absf(fc.z - want) > off:
			off = absf(fc.z - want)
			off_at = p
		if p.distance_to(end) < 3.0:
			reached = true
			break
	var ok := true
	if worst > JUMP:
		errors.append("%s: height jumps %.2f m in a tick at %s" % [label, worst, worst_at])
		ok = false
	if off > 1.0:
		errors.append("%s: car %.2f m off its layer at %s" % [label, off, off_at])
		ok = false
	if not reached:
		errors.append("%s: car stopped at %.0f, %.0f before the end" % [label, fc.car.x, fc.car.y])
		ok = false
	return ok

## The car drives the bridge's own centre line on the deck: it must follow the deck's height in the middle stretch.
func _player_over(map: TownMap, ri: int, rev: bool, errors: Array[String]) -> int:
	var pts := _poly(map, ri, rev)
	var z := map.road_z[ri]
	var len_total := map.road_len[ri]
	var expect := func(p: Vector2) -> float:
		var hit := map.road_at(p.x, p.y, 1000.0, 0.0) # the highest deck under the point
		if hit.is_empty() or int(hit.road) != ri:
			return NAN
		# only well inside the bridge: where it is raised above the ground
		var s := _arc(map, ri, hit.i, hit.t)
		if s < 5.0 or s > len_total - 5.0 or float(hit.deck) < 1.0:
			return NAN
		return float(hit.height)
	var label := "player over bridge %d%s" % [ri, " (reverse)" if rev else ""]
	_drive_line(map, pts, 14.0, expect, errors, label)
	# the car really rode up onto the deck (it reaches most of the height of the stretch it drove)
	var top := 0.0
	for i in pts.size():
		var hit := map.road_at(pts[i].x, pts[i].y, 1000.0, 0.0)
		if not hit.is_empty() and int(hit.road) == ri:
			top = maxf(top, float(hit.deck))
	if _climb < top * 0.8:
		errors.append("%s: car reached only %.1f m above the ground of a %.1f m deck" % [label, _climb, top])
	return 1

func _arc(map: TownMap, ri: int, i: int, t: float) -> float:
	var pts := map.road_pts[ri]
	var s := 0.0
	for k in i:
		s += pts[k].distance_to(pts[k + 1])
	return s + pts[i].distance_to(pts[i + 1]) * t

## A ground-level road that passes under the bridge ri: [road, crossing point] or [].
func _road_under(map: TownMap, ri: int) -> Array:
	var pts := map.road_pts[ri]
	var len_total := map.road_len[ri]
	var s := 6.0
	while s < len_total - 6.0:
		var at := map.along(ri, s)
		var p: Vector2 = at[0]
		if map.deck_at(ri, at[2], at[3]) > 3.5:
			var low := map.road_at(p.x, p.y, -INF, 0.0)
			if not low.is_empty() and int(low.road) != ri and float(low.deck) < 0.4 and map.road_z[int(low.road)].is_empty() \
					and map.road_len[int(low.road)] > 40.0 and map.road_rank[int(low.road)] >= 2:
				return [int(low.road), p]
		s += 3.0
	return []

## The slice of road ri within 45 m of p (in travel order, or reversed).
func _slice(map: TownMap, ri: int, p: Vector2, rev: bool) -> PackedVector2Array:
	var pts := map.road_pts[ri]
	var out := PackedVector2Array()
	for q in pts:
		if q.distance_to(p) < 45.0:
			out.append(q)
	if out.size() < 2:
		return out
	# order matters only for direction: reverse when asked
	if rev:
		var r := PackedVector2Array()
		for i in range(out.size() - 1, -1, -1):
			r.append(out[i])
		return r
	return out

func _player_under(map: TownMap, ri: int, under: Array, rev: bool, errors: Array[String]) -> int:
	var road: int = under[0]
	var cross: Vector2 = under[1]
	var pts := _slice(map, road, cross, rev)
	if pts.size() < 2:
		return 0
	var expect := func(p: Vector2) -> float:
		# on the ground road: height must stay at the ground, whatever the deck overhead
		if p.distance_to(cross) < 30.0:
			return map.ground(p.x, p.y)
		return NAN
	_drive_line(map, pts, 6.0, expect, errors, "player under bridge %d on street %d%s" % [ri, road, " (reverse)" if rev else ""])
	return 1

## Traffic: steps a car along the bridge's edges and checks its height never jumps and follows the deck.
func _traffic_over(map: TownMap, ri: int, rev: bool, errors: Array[String]) -> int:
	var edges := _edges_of(map, ri, rev)
	if edges.is_empty():
		return 0
	var tr := Traffic.new(map, Node3D.new(), null)
	var n := 0
	for e in edges:
		var pts := tr._edge_points(e)
		var c := {"edge": e, "pts": pts, "len": Traffic._poly_len(pts), "s": 0.0, "i0": int(e[2]),
			"istep": 1 if int(e[3]) >= int(e[2]) else -1, "push": Vector2.ZERO, "spin": 0.0, "node": Node3D.new(), "y": 0.0}
		var last := NAN
		var s := 0.0
		while s < float(c.len):
			c.s = s
			tr._place(c)
			var y: float = c.y
			var p: Vector2 = c.pos
			var dk := map.deck_at(ri, e[2], 0.0) # sanity only
			if not is_nan(last) and absf(y - last) > JUMP * 4.0 * 0.5:
				errors.append("traffic on bridge %d%s: height jumps %.2f m at %s" % [ri, " (reverse)" if rev else "", absf(y - last), p])
				break
			last = y
			s += 0.5
		n += 1
	return n

func _edges_of(map: TownMap, ri: int, rev: bool) -> Array:
	var out := []
	for nid in map.node_edges:
		for e in map.node_edges[nid]:
			if int(e[1]) == ri and bool(e[5]) and (int(e[3]) < int(e[2])) == rev and float(e[4]) > 5.0:
				out.append(e)
	return out

func _traffic_under(map: TownMap, under: Array, rev: bool, errors: Array[String]) -> void:
	var road: int = under[0]
	var tr := Traffic.new(map, Node3D.new(), null)
	for e in _edges_of(map, road, rev):
		var pts := tr._edge_points(e)
		var c := {"edge": e, "pts": pts, "len": Traffic._poly_len(pts), "s": 0.0, "i0": int(e[2]),
			"istep": 1 if int(e[3]) >= int(e[2]) else -1, "push": Vector2.ZERO, "spin": 0.0, "node": Node3D.new(), "y": 0.0}
		var s := 0.0
		while s < float(c.len):
			c.s = s
			tr._place(c)
			var p: Vector2 = c.pos
			if absf(float(c.y) - map.ground(p.x, p.y)) > 0.5:
				errors.append("traffic under a bridge on street %d: %.2f m above the ground at %s" % [road, float(c.y) - map.ground(p.x, p.y), p])
				break
			s += 0.5

## Respawning on a bridge puts the car on its deck, not on the street below.
func _respawn(map: TownMap, ri: int, errors: Array[String]) -> void:
	var at := map.along(ri, map.road_len[ri] * 0.5)
	var p: Vector2 = at[0]
	var deck := map.deck_at(ri, at[2], at[3])
	var fc := FreeCar.new(map)
	fc.place(p, 0.0)
	fc.respawn()
	var near := map.nearest_road(p, 5.0, 1)
	if near.is_empty() or int(near.road) != ri:
		return # a different road is nearer at this spot, nothing to say
	if absf(fc.z - (map.ground(fc.car.x, fc.car.y) + deck)) > 1.0:
		errors.append("respawn on bridge %d: car at %.1f, deck at %.1f" % [ri, fc.z, map.ground(fc.car.x, fc.car.y) + deck])

## The baked height profile: ramps are gentle and roads that meet agree on the deck height where they meet.
func _profile(map: TownMap, errors: Array[String]) -> void:
	var steep := 0.0
	var steep_at := ""
	var at_node := {} # node id -> [lowest, highest] deck height there
	for ri in map.road_pts.size():
		var z := map.road_z[ri]
		if z.is_empty():
			continue
		var pts := map.road_pts[ri]
		for k in range(1, z.size()):
			var l := pts[k].distance_to(pts[k - 1])
			if l > 1.5 and absf(z[k] - z[k - 1]) / l > steep:
				steep = absf(z[k] - z[k - 1]) / l
				steep_at = "road %d point %d" % [ri, k]
		for m in map.road_marks[ri]:
			var h := z[int(m[0])]
			var rec: Array = at_node.get(str(m[1]), [h, h])
			at_node[str(m[1])] = [minf(rec[0], h), maxf(rec[1], h)]
	if steep > 0.085:
		errors.append("ramp grade %.1f %% at %s (max 8.5)" % [steep * 100.0, steep_at])
	var mismatched := 0
	for nid in at_node:
		if float(at_node[nid][1]) - float(at_node[nid][0]) > 0.1:
			mismatched += 1
	if mismatched > 0:
		errors.append("%d junctions where roads meet at different deck heights" % mismatched)

## OSM railway=level_crossing nodes stay at the ground: neither the road nor the railway through them is raised.
func _level_crossings(map: TownMap, errors: Array[String]) -> void:
	var lc: Array = map.raw.get("level_crossings", [])
	if lc.size() < 20:
		errors.append("only %d level crossings in the data" % (lc.size() / 2))
	for k in range(0, lc.size(), 2):
		var q := Vector2(lc[k], lc[k + 1])
		var hit := map.road_at(q.x, q.y, -INF, 3.0)
		if not hit.is_empty() and float(hit.deck) > 0.3:
			errors.append("level crossing at %s: the road is raised %.1f m" % [q, float(hit.deck)])
		for li in map.rail_pts.size():
			var z: Array = map.raw.rail[li].get("z", [])
			if z.is_empty():
				continue
			var pts := map.rail_pts[li]
			for i in pts.size():
				if pts[i].distance_to(q) < 4.0 and float(z[i]) > 0.3:
					errors.append("level crossing at %s: the railway is raised %.1f m" % [q, float(z[i])])
					break

## Traffic drives through every underpass without stopping for good.
func _traffic_underpasses(map: TownMap, errors: Array[String]) -> void:
	var road_of := {}
	for ri in map.raw.roads.size():
		road_of[int(map.raw.roads[ri].id)] = ri
	var player := FreeCar.new(map)
	player.place(Vector2(100000.0, 100000.0), 0.0)
	var passed := 0
	for t in map.tunnels:
		var ri: int = road_of.get(int(t.road), -1)
		if ri < 0:
			continue
		var tr := Traffic.new(map, Node3D.new(), null)
		var found := false
		for nid in map.node_edges:
			if found:
				break
			for e in map.node_edges[nid]:
				if int(e[1]) != ri or not bool(e[5]):
					continue
				var pts := tr._edge_points(e)
				# arc length of the closest point of this edge to the bore's centre
				var best := INF
				var s_c := 0.0
				var acc := 0.0
				for k in pts.size() - 1:
					var q := Geometry2D.get_closest_point_to_segment(t.c, pts[k], pts[k + 1])
					if q.distance_to(t.c) < best:
						best = q.distance_to(t.c)
						s_c = acc + pts[k].distance_to(q)
					acc += pts[k].distance_to(pts[k + 1])
				if best > 3.0:
					continue
				var c := {"node": Node3D.new(), "from": nid, "edge": e, "pts": pts, "len": Traffic._poly_len(pts), "s": maxf(0.0, s_c - 40.0),
					"i0": int(e[2]), "istep": 1 if int(e[3]) >= int(e[2]) else -1, "v": 5.0, "want": map.road_limit[ri] / 3.6,
					"pos": Vector2.ZERO, "dir": Vector2.RIGHT, "heading": 0.0, "knock": 0.0, "push": Vector2.ZERO, "spin": 0.0,
					"near": false, "kind": "CarHatch", "y": 0.0}
				tr._place(c)
				tr.cars.append(c)
				var limit_t := 90.0
				var t_now := 0.0
				var last_y := float(c.y)
				var done := false
				while t_now < limit_t:
					tr._drive(c, 0.05, player)
					t_now += 0.05
					if absf(float(c.y) - last_y) > 0.6:
						errors.append("traffic jumps %.1f m in the underpass of street %d" % [absf(float(c.y) - last_y), ri])
						break
					last_y = c.y
					if c.edge != e or float(c.s) > s_c + 5.0:
						done = true
						break
				if not done:
					errors.append("traffic car stuck before the underpass of street %d at %s (s %.0f of %.0f)" % [ri, t.c, float(c.s), s_c])
				else:
					passed += 1
				found = true
				break
	if passed < 4:
		errors.append("only %d underpasses traversed by traffic" % passed)
