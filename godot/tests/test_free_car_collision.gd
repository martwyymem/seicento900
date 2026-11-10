## The open-world car against walls (FreeCar's contacts): driven into a fence at 30, 60 and 100 km/h at 10, 45 and 90
## degrees it never ends up in or through it, a glancing hit slides on along the wall keeping most of its speed and
## turns towards the wall's direction, a head-on hit stops with a small bounce, nothing sticks or jitters, a fence
## made of short joined panels is as smooth as one long one, and a fast car never passes a thin fence.
##   godot --headless --path godot -s tests/_one_suite.gd -- res://tests/test_free_car_collision.gd
extends RefCounted

var completed := false
const DT := 1.0 / 120.0
const WALL_Y := 6.0 ## the wall's line; the car starts on the y < WALL_Y side
const WALL_R := 0.12 ## half thickness (a plot fence)

## A flat endless road with one straight fence along x at WALL_Y, either one segment or many 2.5 m panels.
class WallTown extends TownMap:
	var segs: Array[PackedFloat32Array] = []
	var rings: Array[PackedVector2Array] = []
	var round_posts := PackedVector3Array()
	func ground(_x: float, _y: float) -> float:
		return 0.0
	func terrain(_x: float, _y: float) -> float:
		return 0.0
	func road_at(_x: float, _y: float, _z_ref := -INF, _reach := 0.0) -> Dictionary:
		return {"road": 0, "i": 0, "t": 0.0, "dist": 0.0, "half": 500.0, "deck": 0.0, "surface": 0, "height": 0.0, "gravel": 0}
	func surface_of(hit: Dictionary) -> int:
		return Physics.SURF_GRASS if hit.is_empty() else Physics.SURF_ASPHALT
	func road_lift(_ri: int) -> float:
		return 0.0
	func decks_at(_x: float, _y: float, _reach: float) -> Array:
		return []
	func water_at(_p: Vector2) -> float:
		return NAN
	func edge_push(_p: Vector2) -> Vector2:
		return Vector2.ZERO
	func buildings_near(p: Vector2, r: float) -> PackedInt32Array:
		var out := PackedInt32Array()
		for i in rings.size():
			var lo := Vector2(INF, INF)
			var hi := -lo
			for q in rings[i]:
				lo = lo.min(q)
				hi = hi.max(q)
			if Rect2(lo, hi - lo).grow(r).has_point(p):
				out.append(i)
		return out
	func posts_near(p: Vector2, r: float) -> PackedVector3Array:
		var out := PackedVector3Array()
		for v in round_posts:
			if Vector2(v.x, v.y).distance_to(p) < r + v.z:
				out.append(v)
		return out
	func walls_near(p: Vector2, r: float) -> Array[PackedFloat32Array]:
		var out: Array[PackedFloat32Array] = []
		for w in segs:
			if Geometry2D.get_closest_point_to_segment(p, Vector2(w[0], w[1]), Vector2(w[2], w[3])).distance_to(p) < r + w[4]:
				out.append(w)
		return out
	func parapets_near(_p: Vector2, _r: float) -> Array[PackedFloat32Array]:
		return []
	func piers_near(_p: Vector2, _r: float) -> Array[Vector4]:
		return []

static func wall_town(panels: bool) -> WallTown:
	var town := WallTown.new()
	if panels:
		var x := -200.0
		while x < 400.0:
			town.segs.append(PackedFloat32Array([x, WALL_Y, x + 2.5, WALL_Y, WALL_R]))
			x += 2.5
	else:
		town.segs.append(PackedFloat32Array([-200.0, WALL_Y, 400.0, WALL_Y, WALL_R]))
	town.bld_rings = town.rings
	return town

## Drives a car (coasting, wheel straight) at `kmh` towards the wall at `deg` degrees and measures it: speed just
## before the first touch and 0.4 s after it, the heading's angle to the wall then (degrees, positive: still pointing
## into it), the deepest the box got past the wall's face, whether its centre crossed the line, how long it stayed in
## contact after the hit, and how often its speed across the wall changed sign after the hit (jitter).
static func measure(town: TownMap, deg: float, kmh: float, script: Script = null) -> Dictionary:
	var fc = (script if script else FreeCar).new(town)
	var free_run = (script if script else FreeCar).new(WallTown.new()) # the same car with no wall: what coasting alone costs
	var a := deg_to_rad(deg)
	var v := kmh / 3.6
	# start so the leading corner reaches the wall after about 0.3 s
	var start := Vector2(0.0, WALL_Y - WALL_R - 2.0 - v * 0.3 * sin(a))
	fc.place(start, a)
	fc.assists = "abs"
	fc.car.vx = cos(a) * v
	fc.car.vy = sin(a) * v
	fc.car.gear = clampi(int(kmh / 30.0), 0, 4)
	free_run.place(start, a)
	free_run.assists = "abs"
	free_run.car.vx = fc.car.vx
	free_run.car.vy = fc.car.vy
	free_run.car.gear = fc.car.gear
	var res := {"before": 0.0, "after": -1.0, "free": 1.0, "angle": 0.0, "pen": 0.0, "crossed": false, "stuck": 0.0, "flips": 0, "touch_t": -1.0}
	var t := 0.0
	var last_vy := 0.0
	var hit_t := -1.0
	for i in int(2.5 / DT):
		var spd := Vector2(fc.car.vx, fc.car.vy).length()
		fc.hits.clear()
		fc.step(DT, 0.0, 0.0, 0.0)
		free_run.step(DT, 0.0, 0.0, 0.0)
		t += DT
		var deepest := -INF
		for q in fc.corners():
			deepest = maxf(deepest, q.y - (WALL_Y - WALL_R))
		res.pen = maxf(float(res.pen), deepest)
		if fc.car.y > WALL_Y:
			res.crossed = true
		var touching: bool = deepest > -0.02 or not fc.hits.is_empty()
		if touching and hit_t < 0.0:
			hit_t = t
			res.before = spd
			res.touch_t = t
		if hit_t >= 0.0:
			if touching and t - hit_t > 0.05:
				res.stuck = float(res.stuck) + DT
			var vy: float = fc.car.vy
			if t - hit_t > 0.05 and signf(vy) != signf(last_vy) and absf(vy - last_vy) > 0.05 and absf(vy) > 0.02:
				res.flips = int(res.flips) + 1
			last_vy = vy
			if float(res.after) < 0.0 and t - hit_t >= 0.4:
				res.after = Vector2(fc.car.vx, fc.car.vy).length()
				res.free = Vector2(free_run.car.vx, free_run.car.vy).length()
				var f := Vector2.from_angle(fc.car.heading)
				# the angle between the heading and the wall's nearer direction, positive when it points into the wall
				res.angle = rad_to_deg(asin(clampf(f.y, -1.0, 1.0)))
	return res

func run() -> Array:
	var errors: Array[String] = []
	var panels := wall_town(true)
	var solid := wall_town(false)
	for kmh: float in [30.0, 60.0, 100.0]:
		for deg: float in [10.0, 45.0, 90.0]:
			var r := measure(panels, deg, kmh)
			var label := "%.0f km/h at %.0f deg:" % [kmh, deg]
			if float(r.touch_t) < 0.0:
				errors.append("%s never reached the wall" % label)
				continue
			if r.crossed:
				errors.append("%s the car went through the wall" % label)
			if float(r.pen) > 0.06:
				errors.append("%s the box went %.2f m into the wall" % [label, r.pen])
			var keep := float(r.after) / maxf(float(r.free), 0.1) # against the same car coasting with no wall
			if deg <= 10.0 and keep < 0.85:
				errors.append("%s a glancing hit kept only %.0f%% of the speed" % [label, keep * 100.0])
			if deg == 45.0 and (keep < 0.35 or keep > 0.85):
				errors.append("%s a 45 degree hit kept %.0f%% of the speed (want 35-85%%)" % [label, keep * 100.0])
			if deg >= 90.0 and keep > 0.3:
				errors.append("%s a head-on hit kept %.0f%% of the speed" % [label, keep * 100.0])
			if deg < 90.0 and (float(r.angle) > deg + 1.0 or float(r.angle) < -40.0):
				errors.append("%s the heading went from %.0f to %.0f deg to the wall (want turned along it, not spun)" % [label, deg, r.angle])
			if deg <= 10.0 and float(r.stuck) > 1.5:
				errors.append("%s stuck to the wall for %.2f s after a glancing hit" % [label, r.stuck])
			if int(r.flips) > 3:
				errors.append("%s the speed across the wall flipped sign %d times after the hit (jitter)" % [label, r.flips])
			# the same hit on one long segment: joints between panels change nothing
			var s := measure(solid, deg, kmh)
			if absf(float(s.after) - float(r.after)) > 0.5 or absf(float(s.angle) - float(r.angle)) > 3.0:
				errors.append("%s panels and one long wall differ: %.1f vs %.1f m/s, %.0f vs %.0f deg" % [label, r.after, s.after, r.angle, s.angle])
	# a fast car at a thin fence never passes it
	for kmh: float in [160.0, 250.0]:
		for deg: float in [30.0, 90.0]:
			var r := measure(panels, deg, kmh)
			if r.crossed or float(r.pen) > 0.1:
				errors.append("%.0f km/h at %.0f deg: through the thin fence (%.2f m in)" % [kmh, deg, r.pen])
	# a building's corner and a post: deflected, not stuck or pushed through
	var town := WallTown.new()
	town.rings.append(PackedVector2Array([Vector2(10, 2), Vector2(20, 2), Vector2(20, 12), Vector2(10, 12)]))
	town.bld_rings = town.rings
	town.round_posts.append(Vector3(30.0, 0.0, 0.35))
	var fc := FreeCar.new(town)
	fc.place(Vector2(0.0, 0.0), deg_to_rad(15.0))
	fc.car.vx = cos(deg_to_rad(15.0)) * 16.7
	fc.car.vy = sin(deg_to_rad(15.0)) * 16.7
	fc.car.gear = 2
	var worst := 0.0
	for i in int(2.0 / DT):
		fc.step(DT, 0.0, 0.0, 0.0)
		for q in fc.corners():
			if Geometry2D.is_point_in_polygon(q, town.rings[0]):
				worst = maxf(worst, minf(minf(q.x - 10.0, 20.0 - q.x), minf(q.y - 2.0, 12.0 - q.y)))
	if worst > 0.06:
		errors.append("building: a corner of the car went %.2f m into it" % worst)
	if fc.car.x > 10.0 and fc.car.x < 20.0 and fc.car.y > 2.0 and fc.car.y < 12.0:
		errors.append("building: the car ended inside it")
	# traffic: rear-ending a car doing 50 at 54 is a tap in its frame, not a 54 km/h wall; a parked one takes its share
	var tap := FreeCar.new(WallTown.new())
	tap.place(Vector2.ZERO, 0.0)
	tap.car.vx = 15.0
	tap.bump(Vector2(-1.0, 0.0), 0.02, Vector2(FreeCar.HALF_L, 0.0), 1150.0, Vector2(13.9, 0.0))
	if tap.car.vx < 13.5:
		errors.append("rear-ending a car 4 km/h slower dropped the speed from 15.0 to %.1f m/s" % tap.car.vx)
	var shunt := FreeCar.new(WallTown.new())
	shunt.place(Vector2.ZERO, 0.0)
	shunt.car.vx = 15.0
	shunt.bump(Vector2(-1.0, 0.0), 0.02, Vector2(FreeCar.HALF_L, 0.0), 1150.0)
	if shunt.car.vx > 9.0 or shunt.car.vx < -2.0:
		errors.append("hitting a standing car at 15 m/s left %.1f m/s (want it to take its share, not a wall's)" % shunt.car.vx)
	completed = true
	return errors
