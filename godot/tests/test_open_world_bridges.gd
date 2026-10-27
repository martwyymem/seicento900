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
		# (3) the car drives through at the ground's height without a jump and is not stopped
		var v: Vector2 = t.v
		var start := c - v * (float(t.half_foot) + 8.0)
		var fc := FreeCar.new(map)
		fc.place(start, v.angle())
		fc.z = fc.support(start.x, start.y)
		fc.car.vx = v.x * 8.0
		fc.car.vy = v.y * 8.0
		fc.car.gear = 1
		var last := fc.z
		var worst := 0.0
		var worst_at := Vector2.ZERO
		var through := false
		for i in int(7.0 / DT):
			fc.step(DT, 0.5, 0.0, _steer_to(fc, c + v * 60.0))
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

func _steer_to(fc: FreeCar, target: Vector2) -> float:
	var want := (target - Vector2(fc.car.x, fc.car.y)).angle()
	return clampf(wrapf(want - fc.car.heading, -PI, PI) * 2.0, -1.0, 1.0)
