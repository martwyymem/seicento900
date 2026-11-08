## The EN57 against cars: the player's car can't pass through a train car (side-on, slow or fast, or at an angle),
## a moving train throws a car standing on the line off it instead of pushing it ahead or passing through it, and
## the driver brakes to a stand after the hit. Traffic stops short of a closed crossing and of the train.
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
	var root := Node3D.new()
	var builder := TownBuilder.new(map, root)
	var train := Train.new(map, root, builder)
	if not train.is_running():
		errors.append("the train has no line to run on")
	else:
		_side_hits(map, train, errors)
		_run_down(map, train, errors)
		_traffic(map, train, root, builder, errors)
	root.free()
	completed = true
	return errors

## Arc length of a stretch of line at about ground height (not on an embankment or a bridge), at least `from` in.
func _flat_s(map: TownMap, train: Train, from: float) -> float:
	var s := from
	while s < train.total - 200.0:
		var p := train._at(s)
		if absf(p.y - map.ground(p.x, p.z)) < 1.2 and map.buildings_near(Vector2(p.x, p.z), 12.0).is_empty() \
				and not _bank_near(map, Vector2(p.x, p.z)):
			return s
		s += 25.0
	return -1.0

## Whether a railway embankment (solid, TownMap.rail_bank) lies within 10 m of p: the side hits' cars must reach
## the train on the flat, not climb a bank on the way.
func _bank_near(map: TownMap, p: Vector2) -> bool:
	for r: float in [0.0, 3.0, 6.0, 10.0]:
		for k in 16:
			var q := p + Vector2.from_angle(k * TAU / 16.0) * r
			if map.rail_bank(q.x, q.y) > map.ground(q.x, q.y) + 0.1:
				return true
	return false

func _stand(train: Train, tail: float) -> void:
	train.tail = tail
	train.v = 0.0
	train.wait = 1000.0
	train.braking = false
	train._place()

## Car driven square into a standing car's side (and at 45°), at town and at flat-out speed: it stays on its side.
func _side_hits(map: TownMap, train: Train, errors: Array[String]) -> void:
	var s := _flat_s(map, train, 300.0)
	if s < 0.0:
		errors.append("no stretch of line at ground height to test on")
		return
	_stand(train, s - Train.CAR_PITCH * 1.5)
	var tc: Array = map.trains[1]
	var cen: Vector2 = tc[0]
	var f := Vector2.from_angle(float(tc[1]))
	var r := Vector2(-f.y, f.x)
	for speed: float in [12.0, 45.0]:
		for angle: float in [0.0, 0.8]:
			for side: float in [-1.0, 1.0]:
				var toward := (-r * side).rotated(angle * side)
				var start := cen + r * side * 9.0
				var fc := FreeCar.new(map)
				fc.place(start, toward.angle())
				fc.z = fc.support(start.x, start.y)
				fc.car.vx = toward.x * speed
				fc.car.vy = toward.y * speed
				fc.car.gear = 3
				var worst := INF
				var hit := 0.0
				for i in int(1.5 / DT):
					fc.step(DT, 0.6, 0.0, 0.0)
					worst = minf(worst, (Vector2(fc.car.x, fc.car.y) - cen).dot(r) * side)
					for h in fc.hits:
						hit = maxf(hit, float(h[2]))
					fc.hits.clear()
				# the centre never gets nearer the train's axis than its half width plus a sliver of the car
				if worst < Train.HALF_W + 0.35:
					errors.append("car at %.0f m/s, %.0f° hit the train's side and got %.2f m from its axis (inside it)" % [speed, rad_to_deg(angle), worst])
				if hit < speed * 0.4:
					errors.append("car at %.0f m/s, %.0f° hit the train's side with a %.1f m/s knock: the hit didn't register" % [speed, rad_to_deg(angle), hit])
	print("    train: side hits at 12 and 45 m/s, square and 45°, stay out")

## A car parked across the line in front of a running unit: thrown off the line, the train brakes to a stand.
func _run_down(map: TownMap, train: Train, errors: Array[String]) -> void:
	var s := _flat_s(map, train, 600.0)
	if s < 0.0 or s + 300.0 > train.total:
		errors.append("no stretch of line to run the car down on")
		return
	_stand(train, s - Train.LENGTH - 60.0)
	train.wait = 0.0
	train.dir = 1.0
	train.v = Train.LINE_SPEED
	train._stopped_here = true # no station stop in the way
	var p3 := train._at(s)
	var p := Vector2(p3.x, p3.z)
	var p2 := train._at(s + 2.0)
	var along := Vector2(p2.x - p3.x, p2.z - p3.z).normalized()
	var fc := FreeCar.new(map)
	fc.place(p, along.angle() + PI * 0.5)
	fc.z = fc.support(p.x, p.y)
	var hit := 0.0
	var thrown := 0.0
	var stopped_at := -1.0
	var v_hit := -1.0
	for i in int(20.0 / DT):
		fc.step(DT, 0.0, 0.0, 0.0)
		train.step(DT)
		for h in fc.hits:
			hit = maxf(hit, float(h[2]))
		fc.hits.clear()
		if hit > 0.0 and v_hit < 0.0:
			v_hit = train.v
		var q := Vector2(fc.car.x, fc.car.y)
		var s_car := train._project(q, 30.0)
		if s_car >= 0.0:
			var on := train._at(s_car)
			thrown = maxf(thrown, q.distance_to(Vector2(on.x, on.z)))
		if stopped_at < 0.0 and hit > 0.0 and train.v == 0.0:
			stopped_at = train.tail + Train.LENGTH
	if hit < 8.0:
		errors.append("the train ran into a car on the line with only a %.1f m/s knock" % hit)
	if thrown < Train.HALF_W + FreeCar.HALF_W + 0.3:
		errors.append("the car hit by the train stayed on the line (%.1f m off it)" % thrown)
	var front := train.tail + Train.LENGTH
	var q := Vector2(fc.car.x, fc.car.y)
	var s_end := train._project(q, 30.0)
	if s_end >= 0.0 and s_end < front - 0.5 and q.distance_to(Vector2(train._at(s_end).x, train._at(s_end).z)) < Train.HALF_W:
		errors.append("the car ended up inside the train")
	if stopped_at < 0.0:
		errors.append("the train didn't brake to a stand after hitting the car")
	elif stopped_at - s > 220.0:
		errors.append("the train ran on %.0f m past the car before stopping" % (stopped_at - s))
	print("    train: hit a car at %.1f m/s, threw it %.1f m off the line, stopped %.0f m on" % [hit, thrown, stopped_at - s])
	# then it carries on
	for i in int((Train.STRUCK_WAIT + 3.0) / DT):
		train.step(DT)
	if train.v <= 0.0:
		errors.append("the train never set off again after its emergency stop")

## Traffic watches the line: a closed boom across its lane and a standing train car both stop it short.
func _traffic(map: TownMap, train: Train, root: Node3D, builder: TownBuilder, errors: Array[String]) -> void:
	var traffic := Traffic.new(map, root, builder)
	var p := Vector2(100.0, 100.0)
	var dir := Vector2.RIGHT
	var y := map.ground(p.x, p.y)
	map.booms.append([p + Vector2(30.0, 3.0), p + Vector2(30.0, -3.0), true, 0.0])
	var d := traffic._rail_ahead(p, dir, y)
	if absf(d - 30.0) > 0.1:
		errors.append("traffic sees a closed boom 30 m ahead at %.1f m" % d)
	map.booms[map.booms.size() - 1][2] = false
	if traffic._rail_ahead(p, dir, y) < INF:
		errors.append("traffic stops for an open boom")
	map.booms.pop_back()
	var tc: Array = map.trains[1]
	var cen: Vector2 = tc[0]
	var f := Vector2.from_angle(float(tc[1]))
	var r := Vector2(-f.y, f.x)
	var from := cen + r * 40.0
	var dt := traffic._rail_ahead(from, -r, float(tc[4]) - 0.3)
	if absf(dt - (40.0 - Train.HALF_W - 0.6)) > 0.5:
		errors.append("traffic sees the train car 40 m ahead at %.1f m" % dt)
	if traffic._rail_ahead(from, -r, float(tc[4]) + 6.0) < INF:
		errors.append("traffic on a bridge over the line brakes for the train under it")
