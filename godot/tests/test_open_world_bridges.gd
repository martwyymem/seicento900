## Bridges and underpasses in the open world: piers and parapets are solid, a street under a railway goes through a
## bore with a portal at each end, and the car follows it without a jump.
extends RefCounted

var completed := false
const DT := 1.0 / 120.0

func run() -> Array:
	var errors: Array[String] = []
	var map := TownMap.load_map("brzeszcze")
	if map == null:
		errors.append("data/world/brzeszcze.json did not load")
		completed = true
		return errors
	_piers(map, errors)
	_parapets(map, errors)
	_tunnels(map, errors)
	_tunnel_banks(map, errors)
	_bank_collision(map, errors)
	completed = true
	return errors

## Drives the car from `from` along heading for `secs` at full throttle; returns the closest approach to `target`
## and the car's final position.
var closest := INF

func _drive(map: TownMap, from: Vector2, heading: float, z: float, secs: float, target := Vector2.ZERO, steer := 0.0) -> FreeCar:
	var fc := FreeCar.new(map)
	fc.place(from, heading)
	fc.z = z
	fc.car.vx = cos(heading) * 8.0
	fc.car.vy = sin(heading) * 8.0
	fc.car.gear = 1
	closest = INF
	for i in int(secs / DT):
		fc.step(DT, 1.0, 0.0, steer)
		closest = minf(closest, Vector2(fc.car.x, fc.car.y).distance_to(target))
	return fc

func _piers(map: TownMap, errors: Array[String]) -> void:
	if map.piers.size() < 10:
		errors.append("only %d bridge piers" % map.piers.size())
		return
	var tested := 0
	for pr in map.piers:
		var p: Vector2 = pr[0]
		var g := map.ground(p.x, p.y)
		if float(pr[1]) - g < 3.0:
			continue
		# approach from a clear side
		for ang: float in [0.0, PI * 0.5, PI, PI * 1.5]:
			var dir := Vector2.from_angle(ang)
			var start := p - dir * 9.0
			if map.road_at(start.x, start.y, g).size() > 0 and float(map.road_at(start.x, start.y, g).deck) > 0.5:
				continue
			if not map.posts_near(p, 12.0).is_empty() or not map.walls_near(p, 12.0).is_empty() or not map.buildings_near(p, 12.0).is_empty():
				continue
			var fc := _drive(map, start, ang, g, 2.2, p)
			tested += 1
			if closest < TownMap.PIER_R + FreeCar.HALF_W * 0.8:
				errors.append("car drove into the pier at %s (came within %.2f m of its centre)" % [p, closest])
			elif Vector2(fc.car.x, fc.car.y).distance_to(start) < 3.0:
				errors.append("car did not move towards the pier at %s" % p)
			break
		if tested >= 6:
			break
	if tested < 3:
		errors.append("could not find clear piers to drive at (%d)" % tested)

func _parapets(map: TownMap, errors: Array[String]) -> void:
	var tested := 0
	for ri in map.road_pts.size():
		if map.road_bridge[ri] != 1 or map.road_len[ri] < 40.0 or map.road_z[ri].is_empty():
			continue
		var mid: Array = map.along(ri, map.road_len[ri] * 0.5)
		var p: Vector2 = mid[0]
		var dir: Vector2 = mid[1]
		var deck := map.deck_at(ri, mid[2], mid[3])
		if deck < 3.0 or map.road_w[ri] > 12.0:
			continue
		var g := map.ground(p.x, p.y)
		var heading := dir.angle()
		# along the deck: the car keeps going and stays up
		var along := _drive(map, p - dir * 12.0, heading, g + deck, 0.9)
		var travelled := (Vector2(along.car.x, along.car.y) - (p - dir * 12.0)).dot(dir)
		if travelled < 5.0 or along.z < g + deck - 1.5:
			errors.append("bridge %d: car cannot drive along its deck (moved %.1f m, z %.1f of %.1f)" % [ri, travelled, along.z, g + deck])
		# sideways at the edge: aim the car across the deck at 10 m/s
		for side: float in [-1.0, 1.0]:
			var sidew := Vector2(-dir.y, dir.x) * side
			var fc := FreeCar.new(map)
			fc.place(p, sidew.angle())
			fc.z = g + deck
			fc.car.vx = sidew.x * 10.0
			fc.car.vy = sidew.y * 10.0
			fc.car.gear = 1
			for i in int(2.0 / DT):
				fc.step(DT, 1.0, 0.0, 0.0)
			var off := absf((Vector2(fc.car.x, fc.car.y) - p).dot(sidew))
			if off > map.road_w[ri] * 0.5 + 0.5 or fc.z < g + deck - 1.0:
				errors.append("bridge %d: car left the deck over the parapet (%.1f m off the centre line, z %.1f of %.1f)" % [ri, off, fc.z, g + deck])
		tested += 1
		if tested >= 5:
			break
	if tested < 2:
		errors.append("only %d bridges to test the parapets on" % tested)

func _tunnels(map: TownMap, errors: Array[String]) -> void:
	if map.tunnels.size() < 5:
		errors.append("only %d underpasses in the data" % map.tunnels.size())
	var tn_roads := 0
	for ri in map.road_pts.size():
		if int(map.raw.roads[ri].get("tn", 0)) == 1:
			tn_roads += 1
	var covered := 0
	for t in map.tunnels:
		if int(t.tn) == 1:
			covered += 1
	if covered < tn_roads - 1:
		errors.append("%d tunnel=yes streets but only %d have an underpass" % [tn_roads, covered])
	for t in map.tunnels:
		var c: Vector2 = t.c
		var label := "street %d at %s" % [t.road, c]
		# (4) a portal at each end, with the street running through it
		var portals := map.tunnel_portals(t)
		if portals.size() != 2:
			errors.append("%s: %d portals" % [label, portals.size()])
		for pt in portals:
			var q: Vector2 = pt[0]
			var hit := map.road_at(q.x, q.y, map.ground(q.x, q.y))
			if hit.is_empty():
				errors.append("%s: portal at %s is not on a street" % [label, q])
		# the slab over the street leaves headroom
		if float(t.z) - 0.9 < TownMap.TUNNEL_HEADROOM - 0.1:
			errors.append("%s: only %.1f m under the deck" % [label, float(t.z) - 0.9])
		# (3) the car drives through along the street (from 8 m before the cut, the way the street comes) at the ground's
		# height without a jump and is not stopped
		var v: Vector2 = t.v
		var ri := int(t.ri)
		var s_c := _road_arc(map, ri, c)
		var sgn := 1.0 if (_road_at_arc(map, ri, s_c + 1.0) - _road_at_arc(map, ri, s_c - 1.0)).dot(v) >= 0.0 else -1.0
		var start := _road_at_arc(map, ri, s_c - sgn * (float(t.half_foot) + 8.0))
		var fc := FreeCar.new(map)
		var dir0 := (_road_at_arc(map, ri, s_c - sgn * (float(t.half_foot) + 5.0)) - start).normalized()
		fc.place(start, dir0.angle())
		fc.z = fc.support(start.x, start.y)
		fc.car.vx = dir0.x * 8.0
		fc.car.vy = dir0.y * 8.0
		fc.car.gear = 1
		var last := fc.z
		var worst := 0.0
		var worst_at := Vector2.ZERO
		var through := false
		for i in int(7.0 / DT):
			fc.step(DT, 0.5, 0.0, _steer_to(fc, _road_at_arc(map, ri, _road_arc(map, ri, Vector2(fc.car.x, fc.car.y)) + sgn * 6.0)))
			if absf(fc.z - last) > worst and Vector2(fc.car.x, fc.car.y).distance_to(c) < float(t.half_foot) + 3.0:
				worst = absf(fc.z - last)
				worst_at = Vector2(fc.car.x, fc.car.y)
			last = fc.z
			if Vector2(fc.car.x, fc.car.y).distance_to(c) < 1.5:
				through = true
		if worst > 0.3:
			errors.append("%s: height jumps %.2f m driving through at %s" % [label, worst, worst_at])
		if not through:
			errors.append("%s: the car could not drive through the bore (ended at %.0f, %.0f)" % [label, fc.car.x, fc.car.y])
		# the embankment above does not push the car up: it stays at road level inside the bore
		var g := map.ground(c.x, c.y)
		if absf(fc.support(c.x, c.y) - g) > 0.6:
			errors.append("%s: support height %.2f in the bore, ground %.2f" % [label, fc.support(c.x, c.y), g])

## Around every underpass the drawn railway (bed, rails and embankment) has no holes and nothing floats: just outside
## each wing wall the embankment mesh is there at the height the car rides it at (TownMap.rail_bank), inside the cut
## beyond the bore nothing of the railway hangs over the street, and every raised track that crosses the street
## there is over the bore (a double line's second track too).
func _tunnel_banks(map: TownMap, errors: Array[String]) -> void:
	var root := Node3D.new()
	var builder := TownBuilder.new(map, root)
	builder.build_rail()
	builder.build_tunnels()
	var tris := PackedVector3Array()
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for si in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ix = arr[Mesh.ARRAY_INDEX]
			var idx := PackedInt32Array(ix) if ix != null else PackedInt32Array()
			var count := idx.size() if not idx.is_empty() else vs.size()
			for k in range(0, count, 3):
				var a := vs[idx[k] if not idx.is_empty() else k]
				var b := vs[idx[k + 1] if not idx.is_empty() else k + 1]
				var c := vs[idx[k + 2] if not idx.is_empty() else k + 2]
				var near := false
				for t in map.tunnels:
					if Vector2(a.x, a.z).distance_to(t.c) < float(t.cut_len) + 12.0:
						near = true
						break
				if near:
					tris.append_array(PackedVector3Array([a, b, c]))
	root.free()
	for t in map.tunnels:
		var c: Vector2 = t.c
		var v: Vector2 = t.v
		var n := Vector2(-v.y, v.x)
		var label := "underpass on street %d at %s" % [t.road, c]
		var hb := float(t.half_bore)
		var holes := 0
		var floating := 0
		var first := ""
		for sd: float in [-1.0, 1.0]:
			var s := hb + 0.5
			while s < float(t.half_foot):
				for e: float in [-1.0, 1.0]:
					var out := c + v * s * e + n * sd * (float(t.cut_half) + 0.15)
					var want := map.rail_bank(out.x, out.y)
					if want > map.ground(out.x, out.y) + 0.2:
						var got := _mesh_top(tris, out)
						if absf(got - want) > 0.06:
							holes += 1
							if first == "":
								first = "at %s the embankment is drawn at %.2f, the car rides it at %.2f" % [out, got, want]
					var inn := c + v * s * e + n * sd * (float(t.cut_half) - 0.15)
					if _mesh_top(tris, inn) > map.ground(inn.x, inn.y) + 0.3:
						floating += 1
						if first == "":
							first = "at %s the railway hangs %.2f m over the cut" % [inn, _mesh_top(tris, inn) - map.ground(inn.x, inn.y)]
				s += 0.5
		if holes > 0:
			errors.append("%s: %d holes beside the wing walls (%s)" % [label, holes, first])
		if floating > 0:
			errors.append("%s: %d spots of railway over the open cut (%s)" % [label, floating, first])
		# over the bore the bed is drawn at the header's height
		var over := _mesh_top(tris, c)
		if over < float(t.top) - 0.5 or over > float(t.top) + 0.4:
			errors.append("%s: the railway over the bore is at %.2f, the header's top at %.2f" % [label, over, float(t.top)])

## Highest point of the triangles over p (map x, y), -INF where none covers it.
func _mesh_top(tris: PackedVector3Array, p: Vector2) -> float:
	var best := -INF
	for k in range(0, tris.size(), 3):
		var a := Vector2(tris[k].x, tris[k].z)
		var b := Vector2(tris[k + 1].x, tris[k + 1].z)
		var c := Vector2(tris[k + 2].x, tris[k + 2].z)
		if p.x < minf(a.x, minf(b.x, c.x)) - 0.01 or p.x > maxf(a.x, maxf(b.x, c.x)) + 0.01:
			continue
		if p.y < minf(a.y, minf(b.y, c.y)) - 0.01 or p.y > maxf(a.y, maxf(b.y, c.y)) + 0.01:
			continue
		var den := (b - a).cross(c - a)
		if absf(den) < 1e-6:
			continue
		var wb := (p - a).cross(c - a) / den
		var wc := (b - a).cross(p - a) / den
		if wb < -1e-4 or wc < -1e-4 or wb + wc > 1.0001:
			continue
		best = maxf(best, tris[k].y * (1.0 - wb - wc) + tris[k + 1].y * wb + tris[k + 2].y * wc)
	return best

## The railway embankment is solid: a car driven off the street at the green slope beside an underpass rides up
## it (never through it, never jumping), and a car in the cut steered at a wing wall stays in the cut.
func _bank_collision(map: TownMap, errors: Array[String]) -> void:
	var climbed := 0
	for t in map.tunnels:
		var c: Vector2 = t.c
		var v: Vector2 = t.v
		var n := Vector2(-v.y, v.x)
		var label := "underpass on street %d at %s" % [t.road, c]
		for e: float in [-1.0, 1.0]:
			for sd: float in [-1.0, 1.0]:
				# beside the street, beyond the foot of the embankment, heading along the street into the slope
				var start := c - v * e * (float(t.half_foot) + 6.0) + n * sd * (float(t.cut_half) + 3.0)
				if not map.buildings_near(start, 6.0).is_empty() or not map.walls_near(start, 4.0).is_empty():
					continue
				if not map.road_at(start.x, start.y, -INF, 3.0).is_empty():
					continue # on (or at the edge of) a street: this is about the grass slope beside the cut
				var fc := FreeCar.new(map)
				fc.place(start, (v * e).angle())
				fc.z = fc.support(start.x, start.y)
				fc.car.vx = v.x * e * 8.0
				fc.car.vy = v.y * e * 8.0
				fc.car.gear = 1
				var worst := 0.0
				var worst_at := Vector2.ZERO
				var top := -INF
				var last := fc.z
				var jump := 0.0
				for i in int(3.0 / DT):
					fc.step(DT, 0.6, 0.0, 0.0)
					var p := Vector2(fc.car.x, fc.car.y)
					var bank := map.rail_bank(p.x, p.y)
					if bank - fc.z > worst:
						worst = bank - fc.z
						worst_at = p
					top = maxf(top, fc.z - map.ground(p.x, p.y))
					if map.road_at(p.x, p.y, -INF, 1.0).is_empty():
						jump = maxf(jump, absf(fc.z - last)) # (a street's edge on the way, beside a pond bank, is its own step)
					last = fc.z
				if worst > 0.4:
					errors.append("%s: a car driven at the embankment beside the cut went %.2f m into it at %s" % [label, worst, worst_at])
				if jump > 0.3:
					errors.append("%s: the car's height jumped %.2f m driving onto the embankment" % [label, jump])
				if top > 1.0:
					climbed += 1
		# in the cut, past the bore's end, steered hard at each wing wall: it never gets through it
		for sd: float in [-1.0, 1.0]:
			var start := c - v * (float(t.half_bore) + 3.0)
			var fc := FreeCar.new(map)
			fc.place(start, v.angle())
			fc.z = fc.support(start.x, start.y)
			fc.car.vx = v.x * 6.0
			fc.car.vy = v.y * 6.0
			fc.car.gear = 1
			var widest := 0.0
			for i in int(2.0 / DT):
				fc.step(DT, 0.7, 0.0, sd)
				var rel := Vector2(fc.car.x, fc.car.y) - c
				if absf(rel.dot(v)) < float(t.half_foot) - 1.0:
					widest = maxf(widest, absf(rel.dot(n)))
			if widest > float(t.cut_half) + 0.3:
				errors.append("%s: a car steered at the wing wall got %.2f m off the centre line (the wall stands at %.2f)" % [label, widest, float(t.cut_half)])
	if climbed < 6:
		errors.append("only %d cars rode up an embankment beside an underpass" % climbed)

## Arc length along road ri of its point nearest p.
func _road_arc(map: TownMap, ri: int, p: Vector2) -> float:
	var pts := map.road_pts[ri]
	var best := INF
	var at := 0.0
	var acc := 0.0
	for k in pts.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(p, pts[k], pts[k + 1])
		if q.distance_to(p) < best:
			best = q.distance_to(p)
			at = acc + pts[k].distance_to(q)
		acc += pts[k].distance_to(pts[k + 1])
	return at

## The point of road ri at arc length s (clamped to the road), straight on past its ends.
func _road_at_arc(map: TownMap, ri: int, s: float) -> Vector2:
	var pts := map.road_pts[ri]
	var acc := 0.0
	if s < 0.0:
		return pts[0] + (pts[0] - pts[1]).normalized() * -s
	for k in pts.size() - 1:
		var d := pts[k].distance_to(pts[k + 1])
		if s <= acc + d:
			return pts[k].lerp(pts[k + 1], (s - acc) / maxf(d, 1e-6))
		acc += d
	var n := pts.size()
	return pts[n - 1] + (pts[n - 1] - pts[n - 2]).normalized() * (s - acc)

func _steer_to(fc: FreeCar, target: Vector2) -> float:
	var want := (target - Vector2(fc.car.x, fc.car.y)).angle()
	return clampf(wrapf(want - fc.car.heading, -PI, PI) * 2.0, -1.0, 1.0)
