## The open-world car at rest (FreeCar.step): off the pedals it stays put on every slope it is spawned on; the handbrake
## brings a rolling car to a stand and holds it; the throttle still drives it off, and holding the brake still reverses.
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
	var dt := 1.0 / 120.0
	var worst := 0.0
	for name in map.spots:
		var s: Array = map.spots[name]
		OpenWorld.spawn_car(drive, map, Vector2(s[0], s[1]), float(s[2]))
		var p0 := Vector2(drive.car.x, drive.car.y)
		for i in 600:
			drive.step(dt, 0.0, 0.0, 0.0)
		worst = maxf(worst, p0.distance_to(Vector2(drive.car.x, drive.car.y)))
	check("a car left alone stays where it is", worst < 0.02, "(crept %.2f m in 5 s)" % worst)
	var s0: Array = map.spots[map.spots.keys()[0]]
	OpenWorld.spawn_car(drive, map, Vector2(s0[0], s0[1]), float(s0[2]))
	for i in 360:
		drive.step(dt, 1.0, 0.0, 0.0)
	var v_go := drive.speed_kmh()
	check("the throttle drives it off", v_go > 15.0, "(%.1f km/h after 3 s)" % v_go)
	for i in 720:
		drive.step(dt, 0.0, 0.0, 0.0, false, false, 1.0)
	var v_hb := drive.speed_kmh()
	check("the handbrake stops it", v_hb < 0.01, "(%.1f km/h after 6 s on the handbrake from %.0f)" % [v_hb, v_go])
	var p1 := Vector2(drive.car.x, drive.car.y)
	for i in 360:
		drive.step(dt, 0.0, 1.0, 0.0)
	var back := (Vector2(drive.car.x, drive.car.y) - p1).dot(Vector2(cos(drive.car.heading), sin(drive.car.heading)))
	check("holding the brake at a stand still reverses", back < -1.0, "(moved %.2f m)" % back)
	completed = true
	return errors
