## A PKP EN57 electric unit shuttling along Brzeszcze's main railway line: it runs end to end at line speed,
## calls at the station, waits and comes back. The level crossings on its way close ahead of it and open behind
## it (TownBuilder swings the booms), and it is a solid, moving obstacle for the player's car (FreeCar reads
## TownMap.trains).
class_name Train
extends RefCounted

const CAR_PITCH := 21.2 ## m between car centres
const CARS := 3
const LENGTH := CAR_PITCH * CARS ## m, buffer to buffer
const BOGIE := 7.5 ## m from a car's centre to each bogie (the car rides on the track points under them)
const HALF_W := 1.45 ## m
const RAIL_TOP := 0.27 ## m over the track bed TownBuilder lays
const LINE_SPEED := 19.5 ## m/s (70 km/h)
const ACCEL := 0.7 ## m/s²
const DECEL := 0.9 ## m/s²
const STATION_WAIT := 25.0 ## s
const END_WAIT := 18.0 ## s at either end of the line before it comes back
const CLOSE_AHEAD := 320.0 ## m: crossings this far ahead of a running train close
const CLEAR_BEHIND := 25.0 ## m: and open again once the last car is this far past them

var map: TownMap
var builder: TownBuilder
var pts := PackedVector2Array() ## the line, end to end
var ys := PackedFloat32Array() ## rail top height at each point
var cum := PackedFloat32Array() ## arc length at each point
var total := 0.0
var tail := 0.0 ## arc length of the unit's rear (lower-s) buffer
var dir := 1.0 ## +1 runs towards the line's end, -1 back
var v := 0.0
var wait := 6.0
var stop_s := -1.0 ## arc length of the station stop (where the unit's middle halts), -1 for none
var _stopped_here := false
var _crossing_s: Array = [] ## [crossing index, arc length] for the crossings on the line
var _cars: Array[MeshInstance3D] = []
var _locals: Array[Transform3D] = []

func _init(town: TownMap, parent: Node3D, b: TownBuilder) -> void:
	map = town
	builder = b
	if not _build_line() or total < LENGTH * 3.0:
		pts = PackedVector2Array()
		return
	var station: Array = map.spots.get("station", [])
	if station.size() >= 2:
		var s := _project(Vector2(station[0], station[1]), 150.0)
		if s >= 0.0:
			stop_s = clampf(s, LENGTH * 0.5, total - LENGTH * 0.5)
	for i in builder.crossing_points.size():
		var s := _project(builder.crossing_points[i][0], 4.0)
		if s >= 0.0:
			_crossing_s.append([i, s])
	tail = total * 0.35
	for k in CARS:
		var name := "TrainCar" if k == 1 else "TrainCab"
		var inst := MeshInstance3D.new()
		inst.name = "EN57_%d" % k
		if builder.has_model(name):
			inst.mesh = builder.models[name][0]
			_locals.append(builder.models[name][1])
		else:
			var box := BoxMesh.new()
			box.size = Vector3(2.9, 2.7, 20.6)
			inst.mesh = box
			_locals.append(Transform3D(Basis(), Vector3(0, 2.2, 0)))
		parent.add_child(inst)
		_cars.append(inst)
	map.trains.resize(CARS)
	_place()

func is_running() -> bool:
	return not pts.is_empty()

## The longest run of connected standard-gauge running lines (no sidings), as one polyline.
func _build_line() -> bool:
	var lines: Array = []
	for r in map.raw.get("rail", []):
		if int(r.get("g", 0)) != 0 or int(r.get("sd", 0)) != 0:
			continue
		var p := TownMap._flat(r.p)
		if p.size() >= 2:
			lines.append([p, PackedFloat32Array(r.get("z", []))])
	# endpoints within 3 m are the same node
	var node_of := {}
	var ends: Array = [] # per line: [node a, node b]
	var adj := {} # node -> [[line, other node]]
	for li in lines.size():
		var p: PackedVector2Array = lines[li][0]
		var e := []
		for q in [p[0], p[p.size() - 1]]:
			var key := Vector2i(roundi(q.x / 3.0), roundi(q.y / 3.0))
			var id: int = -1
			for dx in [-1, 0, 1]:
				for dy in [-1, 0, 1]:
					var k2 := key + Vector2i(dx, dy)
					if node_of.has(k2):
						id = node_of[k2]
			if id < 0:
				id = node_of.size()
				node_of[key] = id
			e.append(id)
		ends.append(e)
		for j in 2:
			if not adj.has(e[j]):
				adj[e[j]] = []
			adj[e[j]].append([li, e[1 - j]])
	var lens := PackedFloat32Array()
	for l in lines:
		var p: PackedVector2Array = l[0]
		var s := 0.0
		for i in p.size() - 1:
			s += p[i].distance_to(p[i + 1])
		lens.append(s)
	# longest simple path (the network is a few dozen lines): depth-first from every node of degree 1
	var best_len := 0.0
	var best: Array = []
	for start in adj:
		if (adj[start] as Array).size() != 1:
			continue
		var stack := [[start, [], 0.0, {}, Vector2.ZERO]]
		var guard := 0
		while not stack.is_empty() and guard < 20000:
			guard += 1
			var top: Array = stack.pop_back()
			var nd: int = top[0]
			var path: Array = top[1]
			var length: float = top[2]
			var used: Dictionary = top[3]
			var heading: Vector2 = top[4]
			if length > best_len:
				best_len = length
				best = path
			for edge in adj.get(nd, []):
				var li: int = edge[0]
				if used.has(li):
					continue
				# a train runs on through a junction; it can't turn back onto the other track at a crossover
				var p: PackedVector2Array = lines[li][0]
				var from_a: bool = ends[li][0] == nd
				var out_dir := (p[1] - p[0]).normalized() if from_a else (p[p.size() - 2] - p[p.size() - 1]).normalized()
				if heading != Vector2.ZERO and heading.dot(out_dir) < 0.7:
					continue
				var arrive := (p[p.size() - 1] - p[p.size() - 2]).normalized() if from_a else (p[0] - p[1]).normalized()
				var u2 := used.duplicate()
				u2[li] = true
				stack.append([edge[1], path + [[li, nd]], length + lens[li], u2, arrive])
	if best.is_empty():
		return false
	for step in best:
		var li: int = step[0]
		var p: PackedVector2Array = lines[li][0]
		var z: PackedFloat32Array = lines[li][1]
		var forward: bool = ends[li][0] == step[1]
		for k in p.size():
			var i := k if forward else p.size() - 1 - k
			var q := p[i]
			if not pts.is_empty() and pts[pts.size() - 1].distance_to(q) < 0.5:
				continue
			pts.append(q)
			ys.append(map.ground(q.x, q.y) + (z[i] if i < z.size() else 0.0) + 0.05 + RAIL_TOP)
	# keep to the built world: the mapped line runs on past the edge of the terrain
	var keep := map.extent.grow(-60.0)
	var first := 0
	while first < pts.size() and not keep.has_point(pts[first]):
		first += 1
	var last := pts.size() - 1
	while last > first and not keep.has_point(pts[last]):
		last -= 1
	pts = pts.slice(first, last + 1)
	ys = ys.slice(first, last + 1)
	cum.resize(pts.size())
	for i in range(1, pts.size()):
		cum[i] = cum[i - 1] + pts[i].distance_to(pts[i - 1])
	total = cum[cum.size() - 1] if cum.size() > 0 else 0.0
	return pts.size() >= 2

## Arc length of the line's point nearest p, if within reach, else -1.
func _project(p: Vector2, reach: float) -> float:
	var best := reach
	var out := -1.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		var d := q.distance_to(p)
		if d < best:
			best = d
			out = cum[i] + a.distance_to(q)
	return out

## Position (x, rail top, y) on the line at arc length s.
func _at(s: float) -> Vector3:
	s = clampf(s, 0.0, total)
	var lo := 0
	var hi := cum.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if cum[mid] <= s:
			lo = mid
		else:
			hi = mid
	var seg := cum[hi] - cum[lo]
	var t := 0.0 if seg < 1e-4 else (s - cum[lo]) / seg
	var p := pts[lo].lerp(pts[hi], t)
	return Vector3(p.x, lerpf(ys[lo], ys[hi], t), p.y)

func step(dt: float) -> void:
	if pts.is_empty():
		return
	if wait > 0.0:
		wait -= dt
		v = 0.0
	else:
		# where it has to stop next: the station (once per pass) or the end of the line
		var front := tail + LENGTH if dir > 0.0 else tail
		var stop_at := total if dir > 0.0 else 0.0
		if stop_s >= 0.0 and not _stopped_here:
			var halt := stop_s + LENGTH * 0.5 * dir
			if (halt - front) * dir > -0.5:
				stop_at = halt
		var gap := (stop_at - front) * dir
		var target := minf(LINE_SPEED, sqrt(maxf(0.0, 2.0 * DECEL * maxf(gap - 1.0, 0.0))))
		v = move_toward(v, target, (ACCEL if target > v else DECEL * 1.6) * dt)
		tail += v * dir * dt
		if gap < 1.5 and v < 0.6:
			v = 0.0
			if is_equal_approx(stop_at, total if dir > 0.0 else 0.0) or gap < -0.5:
				wait = END_WAIT
				dir = -dir
				_stopped_here = false
			else:
				wait = STATION_WAIT
				_stopped_here = true
	tail = clampf(tail, 0.0, total - LENGTH)
	_place()
	_update_crossings()

func _place() -> void:
	for k in CARS:
		var c := tail + CAR_PITCH * (k + 0.5)
		var a := _at(c - BOGIE)
		var b := _at(c + BOGIE)
		var mid := (a + b) * 0.5
		var fwd := (b - a).normalized()
		if fwd.length() < 0.5:
			fwd = Vector3.FORWARD
		# each cab faces its own end of the unit: car 0's towards -s, the last one's towards +s
		var look := -fwd if k == 0 else fwd
		var basis := Basis.looking_at(look, Vector3.UP)
		_cars[k].transform = Transform3D(basis, mid) * _locals[k]
		map.trains[k] = [Vector2(mid.x, mid.z), atan2(fwd.z, fwd.x), CAR_PITCH * 0.5, HALF_W, mid.y]

func _update_crossings() -> void:
	var front := tail + LENGTH if dir > 0.0 else tail
	for cs in _crossing_s:
		var s: float = cs[1]
		var on := s > tail - CLEAR_BEHIND and s < tail + LENGTH + CLEAR_BEHIND
		var ahead := (s - front) * dir
		var coming := ahead >= 0.0 and ahead < CLOSE_AHEAD and (v > 1.0 or wait < 8.0)
		builder.set_crossing(int(cs[0]), on or coming)
