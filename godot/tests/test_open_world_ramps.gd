## The car rides the road it is drawn on: driven along every motorway (S1 ramps and carriageways) it stays within
## MAX_GAP of the drawn surface, and the chase camera's per-frame cost stays small.
extends RefCounted

var completed := false
const MAX_GAP := 0.3 ## m the car may sit above or below the drawn road
const CAM_AVG_MS := 0.5
const CAM_WORST_MS := 3.0

func run() -> Array:
	var errors: Array[String] = []
	var map := TownMap.load_map("brzeszcze")
	if map == null:
		errors.append("data/world/brzeszcze.json did not load")
		completed = true
		return errors
	_drive(map, errors)
	_edge_tilt(map, errors)
	_camera(map, errors)
	completed = true
	return errors

## Alongside a bridge's parapet the car stays level: its slope samples 1.5 m out land past the deck's edge, on the
## ground metres below, and once rolled the car 60-70 degrees toward the parapet, sinking its side under the deck.
func _edge_tilt(map: TownMap, errors: Array[String]) -> void:
	var fc := FreeCar.new(map)
	var spots := 0
	var tilted := 0
	var worst := 0.0
	for ri in map.road_pts.size():
		if map.road_z[ri].is_empty() or map.road_bridge[ri] != 1:
			continue
		var pts := map.road_pts[ri]
		var zs := map.road_z[ri]
		var half := map.road_w[ri] * 0.5
		for i in pts.size() - 1:
			if minf(zs[i], zs[i + 1]) < 3.0 or absf(zs[i + 1] - zs[i]) > 0.3:
				continue
			var m := (pts[i] + pts[i + 1]) * 0.5
			var d := (pts[i + 1] - pts[i]).normalized()
			for s: float in [-1.0, 1.0]:
				var p := m + Vector2(-d.y, d.x) * s * (half - FreeCar.HALF_W - 0.05)
				fc.z = fc.support(p.x, p.y)
				var dx := fc._slope(fc.support(p.x - 1.5, p.y), fc.z, fc.support(p.x + 1.5, p.y))
				var dy := fc._slope(fc.support(p.x, p.y - 1.5), fc.z, fc.support(p.x, p.y + 1.5))
				var tilt := rad_to_deg(atan(Vector2(dx, dy).length()))
				spots += 1
				worst = maxf(worst, tilt)
				if tilt > 6.0:
					tilted += 1
	if spots < 50:
		errors.append("bridge edge tilt: only %d level deck spots by a parapet" % spots)
	if tilted > 0:
		errors.append("bridge edge tilt: the car leans over %d of %d spots by a parapet (worst %.0f deg)" % [tilted, spots, worst])

func _drive(map: TownMap, errors: Array[String]) -> void:
	var fc := FreeCar.new(map)
	var driven := 0
	var worst := 0.0
	var worst_at := ""
	for ri in map.road_pts.size():
		var pts: PackedVector2Array = map.road_pts[ri]
		if map.road_kind[ri] != "motorway" or pts.size() < 3 or map.road_z[ri].size() < pts.size():
			continue
		driven += 1
		var lo := 0
		for i in pts.size():
			if map.road_z[ri][i] < map.road_z[ri][lo]:
				lo = i
		lo = mini(lo, pts.size() - 3)
		fc.place(pts[lo], (pts[lo + 1] - pts[lo]).angle())
		fc.z = map.ground(pts[lo].x, pts[lo].y) + map.deck_at(ri, lo, 0.0)
		fc.car.vx = cos(fc.car.heading) * 16.0
		fc.car.vy = sin(fc.car.heading) * 16.0
		var k := lo + 1
		for tick in 6000:
			var p := Vector2(fc.car.x, fc.car.y)
			while k < pts.size() - 1 and p.distance_to(pts[k]) < 12.0:
				k += 1
			if k >= pts.size() - 1 and p.distance_to(pts[pts.size() - 1]) < 12.0:
				break
			var steer := clampf(wrapf((pts[k] - p).angle() - fc.car.heading, -PI, PI) * 2.0, -1.0, 1.0)
			fc.step(1.0 / 120.0, 1.0 if fc.speed_kmh() < 60.0 else 0.0, 0.0, steer)
			var hit := map.road_at(p.x, p.y, fc.z)
			if hit.is_empty():
				continue
			var gap := absf(fc.z - float(hit.height))
			if gap > worst:
				worst = gap
				worst_at = "road %d '%s' at %s" % [ri, map.road_name[ri], p]
	if driven < 3:
		errors.append("only %d motorways driven" % driven)
	if worst > MAX_GAP:
		errors.append("car is %.2f m off the drawn road on %s" % [worst, worst_at])

func _camera(map: TownMap, errors: Array[String]) -> void:
	var total := 0
	var worst := 0
	var n := 0
	for ri in range(0, map.road_pts.size(), 7):
		var cc := ChaseCam.new()
		var p2: Vector2 = map.road_pts[ri][0]
		var piv := Vector3(p2.x, map.ground(p2.x, p2.y) + 1.0, p2.y)
		var t := Time.get_ticks_usec()
		cc.update(map, piv, piv + Vector3(-9.0, 2.6, 4.0), 1.0 / 60.0)
		var d := Time.get_ticks_usec() - t
		total += d
		worst = maxi(worst, d)
		n += 1
	if n > 0 and total / 1000.0 / n > CAM_AVG_MS:
		errors.append("chase camera averages %.2f ms per update (budget %.1f)" % [total / 1000.0 / n, CAM_AVG_MS])
	if worst / 1000.0 > CAM_WORST_MS:
		errors.append("chase camera worst update %.2f ms (budget %.1f)" % [worst / 1000.0, CAM_WORST_MS])
