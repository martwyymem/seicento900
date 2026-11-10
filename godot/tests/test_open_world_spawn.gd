## Where the open world puts the car (OpenWorld.spawn_car): every kind of spawn (back at a stage or mission beacon, a
## named spot, the place it was left, the first visit's stadium) stands on a road, faces along it the way the GPS route
## to the next target sets off, at rest in first gear, and drives off forwards with the throttle. A brake held through
## the spawn does not select reverse until it is let go.
extends RefCounted

var completed := false
var errors: Array[String] = []

func check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		errors.append("%s %s" % [what, detail])

func run() -> Array:
	var map := TownMap.load_map(OpenWorld.MAP_KEY)
	if map == null:
		errors.append("data/world/%s.json did not load" % OpenWorld.MAP_KEY)
		completed = true
		return errors
	var drive := FreeCar.new(map)
	var spots: Array = map.spots.keys()
	var festival := Vector2(map.spots.festival[0], map.spots.festival[1])
	var cases := 0
	# back at a stage beacon (the spot's heading + PI, rolled on): towards every other stage spot, and with no target
	for i in spots.size():
		var s: Array = map.spots[spots[i]]
		var p := Vector2(s[0], s[1])
		var to_name: String = spots[(i + 1) % spots.size()]
		var to := Vector2(map.spots[to_name][0], map.spots[to_name][1])
		cases += _spawn(map, drive, "stage at %s (to %s)" % [spots[i], to_name], p, float(s[2]) + PI, to, OpenWorld.SPAWN_ROLL)
		cases += _spawn(map, drive, "spot %s (to the festival)" % spots[i], p, float(s[2]), festival, 0.0)
		cases += _spawn(map, drive, "spot %s (no target)" % spots[i], p, float(s[2]), null, 0.0)
	# back at a mission beacon (its events store the start heading + PI, the spawn adds PI again)
	for k in Missions.MISSIONS.size():
		var mev := MapMissions.event(Missions.BASE + k)
		if mev.is_empty() or not map.in_play(mev.pos):
			continue
		cases += _spawn(map, drive, "mission %d" % k, mev.pos, float(mev.heading), festival, OpenWorld.SPAWN_ROLL)
	# where the car was left: random places on the roads, facing either way, with a target somewhere else
	var rng := RandomNumberGenerator.new()
	rng.seed = 6001
	var placed := 0
	while placed < 40:
		var ri := rng.randi() % map.road_pts.size()
		var pts: PackedVector2Array = map.road_pts[ri]
		if map.road_rank[ri] < 1 or pts.size() < 2:
			continue
		var j := rng.randi() % (pts.size() - 1)
		var p := pts[j].lerp(pts[j + 1], rng.randf())
		if not map.in_play(p):
			continue
		var to_name: String = spots[rng.randi() % spots.size()]
		var to := Vector2(map.spots[to_name][0], map.spots[to_name][1])
		cases += _spawn(map, drive, "saved place %d (to %s)" % [placed, to_name], p, rng.randf() * TAU, to, 0.0)
		placed += 1
	check("spawns tested", cases >= 60, "(only %d)" % cases)
	_brake_held(map, drive)
	completed = true
	return errors

## One spawn: on a road, along it, the way its route sets off (or the way it was asked to face without one), at rest
## in first gear, and the throttle takes it forwards. Returns 1 for the count.
func _spawn(map: TownMap, drive: FreeCar, label: String, p: Vector2, h: float, to: Variant, roll: float) -> int:
	OpenWorld.spawn_car(drive, map, p, h, to, roll)
	var c := drive.car
	var at := Vector2(c.x, c.y)
	var f := Vector2.from_angle(c.heading)
	check("%s stands on a road" % label, not map.road_at(at.x, at.y, -INF, 1.0).is_empty(), "(at %s)" % at)
	# along its road: a few metres ahead and behind are still road (a junction's side street may lie nearer the car)
	var along := not map.road_at(at.x + f.x * 4.0, at.y + f.y * 4.0, -INF, 0.5).is_empty() \
		and not map.road_at(at.x - f.x * 4.0, at.y - f.y * 4.0, -INF, 0.5).is_empty()
	check("%s faces along its road" % label, along, "(at %s heading %.2f)" % [at, c.heading])
	var near := map.nearest_road(at, 30.0, 1)
	if roll > 0.0:
		check("%s stands clear of the beacon" % label, at.distance_to(p) > OpenWorld.BEACON_RADIUS, "(%.1f m from it)" % at.distance_to(p))
	check("%s starts at rest in first gear" % label, not c.rev and c.gear == 0 and Vector2(c.vx, c.vy).length() < 0.01)
	if to is Vector2:
		# the route from where it stands: its first 30 m lie ahead of the car, not behind it
		var r := map.route(at, to)
		var ahead := OpenWorld.point_along(r, 30.0)
		if r.size() >= 2 and ahead.distance_to(at) > 10.0 and at.distance_to(to) > 60.0:
			check("%s has its route ahead" % label, (ahead - at).dot(f) > 0.0, "(30 m along it lies behind)")
	elif near.size() > 0:
		check("%s keeps the way it was asked to face" % label, f.dot(Vector2.from_angle(h)) >= -0.05)
	# a second of throttle: forwards, not backwards
	var x0 := at
	for i in 120:
		drive.step(1.0 / 120.0, 1.0, 0.0, 0.0)
	var moved := Vector2(drive.car.x, drive.car.y) - x0
	check("%s drives off forwards" % label, moved.dot(f) > 0.3 and not drive.car.rev, "(moved %.2f m along, rev %s)" % [moved.dot(f), drive.car.rev])
	return 1

## The brake held through a spawn (a pad trigger or the key still down from the menu) holds the car, it does not reverse
## it; let go and pressed again at a standstill, it selects reverse as before.
func _brake_held(map: TownMap, drive: FreeCar) -> void:
	var s: Array = map.spots.industrial_sprint
	OpenWorld.spawn_car(drive, map, Vector2(s[0], s[1]), float(s[2]))
	var x0 := Vector2(drive.car.x, drive.car.y)
	for i in 240:
		drive.step(1.0 / 120.0, 0.0, 1.0, 0.0)
	var moved := Vector2(drive.car.x, drive.car.y).distance_to(x0)
	check("a brake held through the spawn does not select reverse", not drive.car.rev and moved < 0.3, "(rev %s, moved %.2f m)" % [drive.car.rev, moved])
	for i in 30:
		drive.step(1.0 / 120.0, 0.0, 0.0, 0.0)
	for i in 120:
		drive.step(1.0 / 120.0, 0.0, 1.0, 0.0)
	check("let go and held again at a standstill, the brake selects reverse", drive.car.rev)
