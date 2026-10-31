## Obstruction handling for the open world's chase camera. The free camera (an eased point behind the car) is swept
## from the car towards where it wants to be: walls, fences and buildings keep a margin round them, and a camera that
## would end up past one is shortened to the clear length or swung to the side that has room, instead of sitting
## inside the wall or being shoved to one side of the car. The chosen spot is eased, and only ever pulled in at once
## when the eased point would be through a wall, so a car pinned against a wall gets a steady view, not a jitter.
## `map` is the TownMap (walls_near, buildings_near, bld_rings).
class_name ChaseCam
extends RefCounted

const MARGIN := 0.7 ## m kept between the camera and any wall or building
const MIN_LEN := 2.2 ## m: the closest the camera comes to the car however tight it gets
const STEP := 0.3 ## m between the samples of a sweep
const SWING := [0.0, 0.35, -0.35, 0.7, -0.7, 1.05, -1.05] ## rad: sideways swings tried when the straight line is blocked
const STICKY := 0.12 ## share of the length a swing to the side used last frame is worth (no flipping between sides)
const EASE := 10.0 ## 1/s

var pos := Vector3.ZERO
var _swing := 0.0
var _ready := false

## The camera position for this frame. pivot: the car (look-at height); desired: the free camera point.
func update(map, pivot: Vector3, desired: Vector3, delta: float, snap := false) -> Vector3:
	var off := Vector2(desired.x - pivot.x, desired.z - pivot.z)
	var want_len := off.length()
	if want_len < 0.01:
		pos = desired
		return pos
	var dir := off / want_len
	var walls: Array[PackedFloat32Array] = map.walls_near(Vector2(pivot.x, pivot.z) + dir * want_len * 0.5, want_len * 0.5 + MARGIN + 1.0)
	var rings: Array = _rings(map, Vector2(pivot.x, pivot.z) + dir * want_len * 0.5, want_len * 0.5 + MARGIN + 1.0)
	var c := Vector2(pivot.x, pivot.z)
	var guards := _guards(c, walls)
	var best_swing := 0.0
	var best_len := -1.0
	var best_score := -INF
	for sw: float in SWING:
		var l := _clear(c, dir.rotated(sw), want_len, guards, rings)
		var score := l * (1.0 - 0.08 * absf(sw)) + (STICKY * want_len if is_equal_approx(sw, _swing) else 0.0)
		if l >= want_len - 0.001 and sw == 0.0:
			best_swing = 0.0
			best_len = l
			break
		if score > best_score:
			best_score = score
			best_swing = sw
			best_len = l
	_swing = best_swing
	var use_dir := dir.rotated(best_swing)
	var use_len := clampf(best_len, minf(MIN_LEN, want_len), want_len)
	var spot := Vector3(c.x + use_dir.x * use_len, desired.y, c.y + use_dir.y * use_len)
	if snap or not _ready:
		pos = spot
		_ready = true
	else:
		pos = pos.lerp(spot, 1.0 - exp(-delta * EASE))
		# the eased point must never be through a wall: pull it in at once along its own line
		var po := Vector2(pos.x - c.x, pos.z - c.y)
		var pl := po.length()
		if pl > 0.01:
			var cl := _clear(c, po / pl, pl, guards, rings)
			if cl < pl - 0.001:
				pos = Vector3(c.x + po.x / pl * cl, pos.y, c.y + po.y / pl * cl)
	return pos

func _rings(map, at: Vector2, r: float) -> Array:
	var out := []
	for bi in map.buildings_near(at, r):
		out.append(map.bld_rings[bi])
	return out

## [wall a, wall b, radius, clearance of the pivot] for each wall; a camera may go no closer to a wall than the
## pivot (the car) already is, so a car against a wall does not block every direction.
func _guards(c: Vector2, walls: Array[PackedFloat32Array]) -> Array:
	var out := []
	for w in walls:
		var a := Vector2(w[0], w[1])
		var b := Vector2(w[2], w[3])
		var d0 := Geometry2D.get_closest_point_to_segment(c, a, b).distance_to(c)
		out.append([a, b, minf(w[4] + MARGIN, maxf(d0 - 0.02, 0.0)), d0])
	return out

## How far (m, up to `limit`) the camera can go from c along dir before it meets a wall or building.
func _clear(c: Vector2, dir: Vector2, limit: float, guards: Array, rings: Array) -> float:
	# only walls and buildings the whole sweep passes near can stop it: test those step by step, skip the rest
	var e := c + dir * limit
	var near_guards := []
	for g in guards:
		var cp := Geometry2D.get_closest_points_between_segments(c, e, g[0], g[1])
		if cp[0].distance_to(cp[1]) < g[2]:
			near_guards.append(g)
	var near_rings := []
	var ring_d0 := []
	for ring: PackedVector2Array in rings:
		if _seg_ring_dist(c, e, ring) < MARGIN or Geometry2D.is_point_in_polygon(e, ring):
			near_rings.append(ring)
			ring_d0.append(_ring_dist(c, ring))
	if near_guards.is_empty() and near_rings.is_empty():
		return limit
	var t := STEP
	var last := 0.0
	while true:
		var tt := minf(t, limit)
		var q := c + dir * tt
		var blocked := false
		for g in near_guards:
			if Geometry2D.get_closest_point_to_segment(q, g[0], g[1]).distance_to(q) < g[2]:
				blocked = true
				break
		if not blocked:
			for k in near_rings.size():
				var ring: PackedVector2Array = near_rings[k]
				if Geometry2D.is_point_in_polygon(q, ring) or _ring_dist(q, ring) < minf(MARGIN, maxf(ring_d0[k] - 0.02, 0.0)):
					blocked = true
					break
		if blocked:
			return last
		last = tt
		if tt >= limit:
			return limit
		t += STEP
	return limit

## Closest approach between the segment a-b and a building outline.
static func _seg_ring_dist(a: Vector2, b: Vector2, ring: PackedVector2Array) -> float:
	var best := INF
	for i in ring.size():
		var cp := Geometry2D.get_closest_points_between_segments(a, b, ring[i], ring[(i + 1) % ring.size()])
		best = minf(best, cp[0].distance_to(cp[1]))
	return best

static func _ring_dist(p: Vector2, ring: PackedVector2Array) -> float:
	var best := INF
	for i in ring.size():
		best = minf(best, Geometry2D.get_closest_point_to_segment(p, ring[i], ring[(i + 1) % ring.size()]).distance_to(p))
	return best
