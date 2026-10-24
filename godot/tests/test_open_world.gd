## The open-world town (data/world/brzeszcze.json): the map data, the car's physics on it (roads, collisions,
## height), the GPS, the traffic and a full build of the 3D scene.
extends RefCounted

var completed := false

func run() -> Array:
	var errors: Array[String] = []
	var map := TownMap.load_map(OpenWorld.MAP_KEY)
	if map == null:
		errors.append("data/world/%s.json did not load" % OpenWorld.MAP_KEY)
		completed = true
		return errors
	_data(map, errors)
	_driving(map, errors)
	_walls(map, errors)
	_gps(map, errors)
	_traffic(map, errors)
	_build(map, errors)
	completed = true
	return errors

func _data(map: TownMap, errors: Array[String]) -> void:
	if map.road_pts.size() < 1000:
		errors.append("only %d roads" % map.road_pts.size())
	if map.buildings.size() < 5000:
		errors.append("only %d buildings" % map.buildings.size())
	if map.boundary.size() < 50:
		errors.append("the town limit is missing")
	var lo := INF
	var hi := -INF
	for h in map.th:
		lo = minf(lo, h)
		hi = maxf(hi, h)
	if lo < 200.0 or hi > 320.0:
		errors.append("terrain %.0f-%.0f m is not Brzeszcze's 230-280 m" % [lo, hi])
	for track in OpenWorld.STAGE_SPOTS:
		var spot: String = OpenWorld.STAGE_SPOTS[track]
		if not map.spots.has(spot):
			errors.append("no spot %s for the %s stage" % [spot, track])
			continue
		var s: Array = map.spots[spot]
		if spot != "festival" and map.road_at(s[0], s[1], -INF, 2.0).is_empty():
			errors.append("spot %s (%s) is not on a road" % [spot, s])
		if not map.bounds.has_point(Vector2(s[0], s[1])):
			errors.append("spot %s is outside the drivable area" % spot)
	for st in Campaign.STAGES:
		if not OpenWorld.STAGE_SPOTS.has(st.track):
			errors.append("campaign track %s has no open-world spot" % st.track)
	# the road's own surface, grass in a field
	var s: Array = map.spots.industrial_sprint
	var hit := map.road_at(s[0], s[1])
	if hit.is_empty() or map.surface_of(hit) != Physics.SURF_TRACK:
		errors.append("ul. Dworcowa is not asphalt under the car: %s" % hit)
	var field := map.surface_of(map.road_at(map.bounds.position.x + 5.0, map.bounds.position.y + 5.0))
	if field == Physics.SURF_TRACK:
		errors.append("the map's corner reads as road")

func _driving(map: TownMap, errors: Array[String]) -> void:
	var s: Array = map.spots.industrial_sprint
	var fc := FreeCar.new(map)
	fc.place(Vector2(s[0], s[1]), float(s[2]))
	var top := 0.0
	for i in 720:
		var hit := map.road_at(fc.car.x, fc.car.y)
		# steer back towards the road's centreline so the car stays on Dworcowa
		var st := 0.0
		if not hit.is_empty():
			st = clampf(-float(hit.dist) * 0.15, -0.4, 0.4)
		fc.step(1.0 / 120.0, 1.0, 0.0, st)
		top = maxf(top, fc.speed_kmh())
		if is_nan(fc.car.x) or is_nan(fc.z):
			errors.append("the car's state went NaN at tick %d" % i)
			return
	if top < 45.0:
		errors.append("6 s flat out on Dworcowa only reached %.0f km/h" % top)
	var ground := map.ground(fc.car.x, fc.car.y)
	if absf(fc.z - ground) > 1.5 and not fc.airborne:
		errors.append("the car rides at %.1f m, the ground is at %.1f m" % [fc.z, ground])

## A car driven at a house must stop at its walls, never inside them.
func _walls(map: TownMap, errors: Array[String]) -> void:
	var tested := 0
	for bi in range(0, map.buildings.size(), 97):
		if tested >= 6:
			break
		var ring := map.bld_rings[bi]
		var r := map.bld_rect[bi]
		if r.size.x < 8.0 or r.size.y < 8.0 or r.size.x > 40.0:
			continue
		var c := r.get_center()
		if not Geometry2D.is_point_in_polygon(c, ring):
			continue
		var from := c + Vector2(r.size.x * 0.5 + 9.0, 0.0)
		var fc := FreeCar.new(map)
		fc.place(from, PI)
		fc.car.vx = -16.0
		fc.car.vy = 0.0
		var inside := false
		for i in 360:
			fc.step(1.0 / 120.0, 0.6, 0.0, 0.0)
			for q in fc.corners():
				if Geometry2D.is_point_in_polygon(q, ring):
					var d := INF
					for k in ring.size():
						d = minf(d, q.distance_to(Geometry2D.get_closest_point_to_segment(q, ring[k], ring[(k + 1) % ring.size()])))
					if d > 0.35:
						inside = true
		if inside:
			errors.append("the car drove into building %d at %s" % [bi, c])
		tested += 1
	if tested == 0:
		errors.append("no building to test the walls on")

func _gps(map: TownMap, errors: Array[String]) -> void:
	var a: Array = map.spots.industrial_sprint
	var b: Array = map.spots.bor_stage
	var pa := Vector2(a[0], a[1])
	var pb := Vector2(b[0], b[1])
	var t0 := Time.get_ticks_msec()
	var path := map.route(pa, pb)
	var ms := Time.get_ticks_msec() - t0
	if path.size() < 3:
		errors.append("no route from Dworcowa to ul. Bór")
		return
	var length := 0.0
	for i in path.size() - 1:
		length += path[i].distance_to(path[i + 1])
	var straight := pa.distance_to(pb)
	print("    route Dworcowa -> Bór: %.1f km (%.1f km as the crow flies) in %d ms" % [length / 1000.0, straight / 1000.0, ms])
	if length > straight * 2.2 or length < straight:
		errors.append("route length %.0f m against %.0f m straight" % [length, straight])
	for p in path:
		if map.road_at(p.x, p.y, -INF, 1.0).is_empty():
			errors.append("the route leaves the roads at %s" % p)
			break

func _traffic(map: TownMap, errors: Array[String]) -> void:
	var root := Node3D.new()
	var builder := TownBuilder.new(map, root)
	var tr := Traffic.new(map, root, builder)
	var s: Array = map.spots.industrial_sprint
	var fc := FreeCar.new(map)
	fc.place(Vector2(s[0], s[1]), float(s[2]))
	for i in 1200:
		tr.step(1.0 / 120.0, fc)
	if tr.cars.size() < 5:
		errors.append("only %d traffic cars round the player" % tr.cars.size())
	var moving := 0
	for c in tr.cars:
		var p: Vector2 = c.pos
		if map.road_at(p.x, p.y, -INF, 2.0).is_empty():
			errors.append("a traffic car is off the road at %s" % p)
			break
		if float(c.v) > 2.0:
			moving += 1
	if moving == 0 and tr.cars.size() > 0:
		errors.append("no traffic car is moving")
	tr.clear()
	root.free()

func _build(map: TownMap, errors: Array[String]) -> void:
	var root := Node3D.new()
	var builder := TownBuilder.new(map, root)
	var total := 0
	for step in builder.steps():
		var t0 := Time.get_ticks_msec()
		(step[1] as Callable).call()
		var ms := Time.get_ticks_msec() - t0
		total += ms
		print("    built %s in %d ms" % [step[0], ms])
	print("    open world built in %.1f s, %d nodes" % [total / 1000.0, _count(root)])
	if not builder.has_model("Headframe"):
		errors.append("models/town.glb didn't load (no Headframe)")
	for name in ["Terrain", "Water", "Streets", "Railway", "Buildings", "Trees", "Props", "Landmarks"]:
		var g := root.get_node_or_null(name)
		if g == null or g.get_child_count() == 0:
			errors.append("the %s group is empty" % name)
	if builder.lamp_spots.size() < 500:
		errors.append("only %d street lamps" % builder.lamp_spots.size())
	if builder.crossing_points.is_empty():
		errors.append("no level crossings found on the railway")
	builder.add_beacon("test", Vector2(map.spots.festival[0], map.spots.festival[1]), Color.ORANGE, "TEST")
	if not builder.beacon_nodes.has("test"):
		errors.append("add_beacon didn't register the beacon")
	root.free()

static func _count(n: Node) -> int:
	var c := 1
	for k in n.get_children():
		c += _count(k)
	return c
