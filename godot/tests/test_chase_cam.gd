## The open world's chase camera against walls and buildings (ChaseCam): with the car pinned to a wall the camera
## never sits inside or past it, settles instead of oscillating, and keeps the car in frame.
extends RefCounted

var completed := false
var errors: Array[String] = []

func check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		errors.append("%s %s" % [what, detail])

## The three TownMap queries ChaseCam uses, over a few hand-placed walls and building rings.
class StubMap:
	var walls: Array[PackedFloat32Array] = []
	var bld_rings: Array[PackedVector2Array] = []
	func walls_near(p: Vector2, r: float) -> Array[PackedFloat32Array]:
		var out: Array[PackedFloat32Array] = []
		for w in walls:
			if Geometry2D.get_closest_point_to_segment(p, Vector2(w[0], w[1]), Vector2(w[2], w[3])).distance_to(p) < r + w[4]:
				out.append(w)
		return out
	func buildings_near(p: Vector2, r: float) -> PackedInt32Array:
		var out := PackedInt32Array()
		for i in bld_rings.size():
			var lo := Vector2(INF, INF)
			var hi := Vector2(-INF, -INF)
			for q in bld_rings[i]:
				lo = lo.min(q)
				hi = hi.max(q)
			if Rect2(lo, hi - lo).grow(r).has_point(p):
				out.append(i)
		return out

## Runs the camera for `frames` at 60 Hz behind a car at `car` (flat, heading `heading`), the way open_world.gd
## does (free point 6.2 m behind and 2.2 m up, eased). Returns the final spot, the per-frame spots and the free points.
func _drive(map: StubMap, car: Vector3, heading: float, frames: int) -> Dictionary:
	var cam := ChaseCam.new()
	var fwd := Vector3(cos(heading), 0.0, sin(heading))
	var free := car - fwd * 6.2 + Vector3.UP * 2.2
	var spots: Array[Vector3] = []
	for k in frames:
		spots.append(cam.update(map, car + Vector3.UP, free, 1.0 / 60.0, k == 0))
	return {"spot": spots[-1], "spots": spots}

func _dist_to_walls(map: StubMap, p: Vector3) -> float:
	var best := INF
	for w in map.walls:
		best = minf(best, Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z), Vector2(w[0], w[1]), Vector2(w[2], w[3])).distance_to(Vector2(p.x, p.z)) - w[4])
	return best

func run() -> Array:
	# 1. open road: the camera goes where it wants to
	var open := StubMap.new()
	var r0 := _drive(open, Vector3.ZERO, 0.0, 30)
	check("open ground: the camera sits 6.2 m behind", absf((r0.spot as Vector3).x + 6.2) < 0.05, "(%s)" % r0.spot)

	# 2. a wall 3 m behind the car, across the road: shortened, never through the wall, steady
	var behind := StubMap.new()
	behind.walls.append(PackedFloat32Array([-3.0, -20.0, -3.0, 20.0, 0.1]))
	var r1 := _drive(behind, Vector3.ZERO, 0.0, 240)
	var s1: Vector3 = r1.spot
	check("wall behind: the camera stays on the car's side", s1.x > -3.0 + 0.1, "(%s)" % s1)
	check("wall behind: a margin from the wall", _dist_to_walls(behind, s1) >= ChaseCam.MARGIN - 0.05, "(%.2f m)" % _dist_to_walls(behind, s1))
	var moved := 0.0
	var worst := INF
	for k in range(120, 240):
		var spots: Array[Vector3] = r1.spots
		moved = maxf(moved, spots[k].distance_to(spots[k - 1]))
		worst = minf(worst, _dist_to_walls(behind, spots[k]))
	check("wall behind: no jitter once settled", moved < 0.01, "(%.4f m a frame)" % moved)
	check("wall behind: never inside the wall", worst > 0.0, "(%.2f)" % worst)

	# 3. the car pinned along a wall that is 1.2 m to its side, nose angled into it: the camera clears the wall
	var side := StubMap.new()
	side.walls.append(PackedFloat32Array([-30.0, 1.2, 30.0, 1.2, 0.15]))
	var heading := 0.5 # nose 29 degrees into the wall
	var car := Vector3.ZERO
	var r2 := _drive(side, car, heading, 240)
	var spots2: Array[Vector3] = r2.spots
	var min_gap := INF
	var flips := 0
	var last_sign := 0.0
	for k in range(1, spots2.size()):
		min_gap = minf(min_gap, _dist_to_walls(side, spots2[k]))
		if k > 60:
			var dz := spots2[k].z - spots2[k - 1].z
			if absf(dz) > 1e-4:
				if last_sign != 0.0 and signf(dz) != last_sign:
					flips += 1
				last_sign = signf(dz)
	check("wall alongside: never through the wall", min_gap > 0.0, "(%.2f)" % min_gap)
	check("wall alongside: no oscillation", flips <= 1, "(%d reversals)" % flips)
	# the car stays in frame: the look-at point is the car's nose, so its bearing from the camera must be near the middle
	var spot2: Vector3 = r2.spot
	var look := car + Vector3(cos(heading), 0.0, sin(heading)) * 3.5 + Vector3.UP
	var off := rad_to_deg((look - spot2).angle_to(car + Vector3.UP * 0.5 - spot2))
	check("wall alongside: the car stays near the middle of the frame", off < 14.0, "(%.1f degrees off)" % off)

	# 4. a building behind: the camera does not end up inside it
	var bld := StubMap.new()
	bld.bld_rings.append(PackedVector2Array([Vector2(-12, -8), Vector2(-4, -8), Vector2(-4, 8), Vector2(-12, 8)]))
	var r3 := _drive(bld, Vector3.ZERO, 0.0, 120)
	var s3: Vector3 = r3.spot
	check("building behind: the camera stays out of it", s3.x > -4.0, "(%s)" % s3)

	# 5. driving away from a wall releases the camera back to the full distance
	var cam := ChaseCam.new()
	var spot := Vector3.ZERO
	for k in 400:
		var x := -0.05 * k # the car backs away from the wall at x = 2 ... then forward again below
		var car_p := Vector3(x, 0.0, 0.0)
		var wall_map := StubMap.new()
		wall_map.walls.append(PackedFloat32Array([-60.0, -20.0, -60.0, 20.0, 0.1]))
		spot = cam.update(wall_map, car_p + Vector3.UP, car_p - Vector3(6.2, -2.2, 0.0), 1.0 / 60.0, k == 0)
		if k == 399:
			check("far from the wall the camera is back at full distance", absf(spot.x - (car_p.x - 6.2)) < 0.3, "(%.2f vs %.2f)" % [spot.x, car_p.x - 6.2])
	completed = true
	return errors
