## Open-world ponds and rivers: the water follows the ground (TownMap.water_surface), the bed sinks along a bank that
## meets the water at the outline, roads beside or across the water keep their banks, and a car driven into the water
## never falls through or under the drawn ground, sinks, is put back on a dry road once and stays there.
extends RefCounted

var completed := false

func run() -> Array:
	var errors: Array[String] = []
	var map := TownMap.load_map("brzeszcze")
	if map == null:
		errors.append("data/world/brzeszcze.json did not load")
		completed = true
		return errors
	_bed(map, errors)
	_roads(map, errors)
	_shores(map, errors)
	_drive_in(map, errors)
	completed = true
	return errors

func _wet(map: TownMap, p: Vector2) -> bool:
	return not is_nan(map.water_at(p))

## No ground outside the water is sunk below the water's surface (a dry pit), none inside more than the bed.
func _bed(map: TownMap, errors: Array[String]) -> void:
	var nx := int(map.extent.size.x / TownMap.BED_STEP) + 1
	var pits := 0
	var deep := 0.0
	for kk: int in map.bed_mask:
		var p := map.extent.position + Vector2(kk % nx, kk / nx) * TownMap.BED_STEP
		var sink := map.ground(p.x, p.y) - map.bed_vertex(kk % nx, kk / nx, nx)
		deep = maxf(deep, sink)
		if sink > TownMap.WATER_DROP + 0.05 and not _wet(map, p):
			pits += 1
	if map.bed_mask.size() < 1000:
		errors.append("only %d pond bed vertices" % map.bed_mask.size())
	if pits > 0:
		errors.append("%d terrain vertices outside the water are sunk below its surface" % pits)
	if deep > TownMap.WATER_DROP + TownMap.POND_DEPTH + 0.01:
		errors.append("the bed sinks %.2f m under the ground (at most %.2f)" % [deep, TownMap.WATER_DROP + TownMap.POND_DEPTH])

## Roads within 12 m of water: the drawn road never floats over the drawn bed, the drawn shoulder meets the drawn
## ground, and a car stepping off the road sideways never drops off a ledge.
func _roads(map: TownMap, errors: Array[String]) -> void:
	var samples := 0
	var worst_float := 0.0
	var holes := 0
	var drops := 0
	var at := ""
	var fc := FreeCar.new(map)
	for ri in map.road_pts.size():
		if map.road_bridge[ri] == 1:
			continue
		var near := false
		for k in map.water_rings.size():
			if map.water_rects[k].grow(12.0).intersects(_rect(map.road_pts[ri])):
				near = true
				break
		if not near:
			continue
		var half := map.road_w[ri] * 0.5
		var s := 0.0
		while s < map.road_len[ri]:
			var a: Array = map.along(ri, s)
			s += 4.0
			var p: Vector2 = a[0]
			if map.deck_at(ri, a[2], a[3]) > 0.05 or map.nearest_road(p, 0.1).is_empty():
				continue
			var wet_near := false
			for o in [Vector2(12, 0), Vector2(-12, 0), Vector2(0, 12), Vector2(0, -12), Vector2.ZERO]:
				if _wet(map, p + o):
					wet_near = true
			if not wet_near:
				continue
			samples += 1
			worst_float = maxf(worst_float, map.ground(p.x, p.y) - map.terrain(p.x, p.y))
			var n := Vector2(-a[1].y, a[1].x)
			for side in [-1.0, 1.0]:
				var foot: Vector2 = p + n * side * (half + TownMap.SHOULDER)
				if map.road_at(foot.x, foot.y).is_empty() and map.kerb_at(foot.x, foot.y) == 0.0:
					if map.ground(foot.x, foot.y) - TownMap.SHOULDER_DROP - map.terrain(foot.x, foot.y) > 0.5:
						holes += 1
				fc.place(p, 0.0)
				var last := fc.z
				for o in range(1, int(half + 9.0)):
					var q: Vector2 = p + n * side * float(o)
					fc.z = last
					var h := fc.support(q.x, q.y)
					if last - h > 0.8:
						drops += 1
						at = "road %d '%s' (%.0f, %.0f)" % [ri, map.road_name[ri], q.x, q.y]
					last = h
	print("  lakes: %d road samples beside water, float %.2f, %d shoulder holes, %d drops" % [samples, worst_float, holes, drops])
	if samples < 500:
		errors.append("only %d road samples beside water" % samples)
	if worst_float > 0.3:
		errors.append("a road beside water floats %.2f m over the drawn bed" % worst_float)
	if holes > 10:
		errors.append("%d holes over 0.5 m between a road's shoulder and the ground beside water" % holes)
	if drops > 5:
		errors.append("%d drops over 0.8 m stepping off a road beside water (last %s)" % [drops, at])

static func _rect(pts: PackedVector2Array) -> Rect2:
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r

## Out from the shoreline every 9 m: no dry land drawn deep under the water's surface, no cliff on dry land.
func _shores(map: TownMap, errors: Array[String]) -> void:
	var dry := 0
	var pits := 0
	var steps := 0
	var worst := 0.0
	var at := ""
	for k in map.water_rings.size():
		var ring := map.water_rings[k]
		for e in ring.size():
			var a := ring[e]
			var b := ring[(e + 1) % ring.size()]
			var l := a.distance_to(b)
			if l < 0.01:
				continue
			var t := (b - a) / l
			var n := Vector2(-t.y, t.x)
			if TownMap.inside(a.lerp(b, 0.5) + n * 0.5, ring):
				n = -n
			var u := 0.0
			while u < l:
				var base := a + t * u
				u += 9.0
				var last := NAN
				for d in range(1, 16):
					var q := base + n * float(d)
					var h := map.terrain(q.x, q.y)
					if _wet(map, q) or not map.road_at(q.x, q.y, -INF, 1.0).is_empty():
						last = NAN
						continue
					dry += 1
					var below := map.water_surface(q.x, q.y) - h
					if below > 0.6:
						pits += 1
					if below > worst:
						worst = below
						at = "(%.0f, %.0f)" % [q.x, q.y]
					if not is_nan(last) and absf(h - last) > 0.6:
						steps += 1
					last = h
	print("  lakes: %d dry shore samples, %d more than 0.6 m under the water's surface (worst %.2f at %s), %d steps" % [dry, pits, worst, at, steps])
	if dry < 10000:
		errors.append("only %d dry shore samples" % dry)
	if worst > 1.3:
		errors.append("dry land drawn %.2f m under the water's surface at %s" % [worst, at])
	if pits * 1000 > dry:
		errors.append("%d of %d dry shore samples more than 0.6 m under the water's surface" % [pits, dry])
	if steps > 10:
		errors.append("%d steps over 0.6 m per metre on dry land by the water" % steps)

## From a road next to water, the car is driven straight into it at several throttles: each frame it stays on or over
## the drawn ground; in the water it sinks and asks to be put back; respawn() puts it on a dry road, once.
func _drive_in(map: TownMap, errors: Array[String]) -> void:
	var tried := 0
	var entered := 0
	for k in map.water_rings.size():
		if tried >= 16:
			break
		var ring := map.water_rings[k]
		if map.water_rects[k].size.x < 25.0 or map.water_rects[k].size.y < 25.0:
			continue
		# a road point 10-40 m from the ring, and the ring's nearest point to it
		var start := Vector2.INF
		var target := Vector2.ZERO
		for v in range(0, ring.size(), maxi(1, ring.size() / 12)):
			var near := map.nearest_road(ring[v], 40.0, 1)
			if near.is_empty() or float(near.dist) < 10.0 or map.road_bridge[int(near.road)] == 1:
				continue
			if not map.road_z[int(near.road)].is_empty():
				continue
			start = near.pos
			target = ring[v] + (ring[v] - near.pos).normalized() * 0.0
			# aim through the vertex into the water: past the outline by 15 m
			var c := map.water_rects[k].get_center()
			target = ring[v] + (c - ring[v]).normalized() * 15.0
			break
		if start == Vector2.INF:
			continue
		for thr: float in [1.0, 0.45]:
			tried += 1
			var fc := FreeCar.new(map)
			var dir := (target - start).normalized()
			fc.place(start, dir.angle())
			var wet := false
			var respawned := 0
			var t := 0.0
			var settle := 0.0
			while t < 25.0:
				var aim := (target - Vector2(fc.car.x, fc.car.y))
				var steer := 0.0
				if respawned == 0 and aim.length() > 3.0:
					steer = clampf(wrapf(aim.angle() - fc.car.heading, -PI, PI) * 2.0, -1.0, 1.0)
				fc.step(1.0 / 60.0, thr if respawned == 0 else 0.0, 0.0, steer)
				t += 1.0 / 60.0
				var g := map.terrain(fc.car.x, fc.car.y)
				if is_nan(fc.z) or is_inf(fc.z) or fc.z < g - 0.1:
					errors.append("pond %d: the car is %.2f m under the drawn ground at (%.1f, %.1f)" % [k, g - fc.z, fc.car.x, fc.car.y])
					break
				if fc.in_water:
					wet = true
				if fc.wants_respawn:
					if respawned > 0:
						errors.append("pond %d: the car asked to be put back again %.1f s after a respawn at (%.1f, %.1f)" % [k, settle, fc.car.x, fc.car.y])
						break
					fc.respawn()
					respawned += 1
					var p := Vector2(fc.car.x, fc.car.y)
					if map.road_at(p.x, p.y, fc.z).is_empty():
						errors.append("pond %d: respawned off the road at %s" % [k, p])
					if _wet(map, p) and fc.z < map.water_surface(p.x, p.y) + 0.6:
						errors.append("pond %d: respawned in the water at %s" % [k, p])
					if fc.z < map.terrain(p.x, p.y) - 0.05:
						errors.append("pond %d: respawned under the ground at %s" % [k, p])
				if respawned > 0:
					settle += 1.0 / 60.0
					if settle > 4.0:
						break
			if wet:
				entered += 1
				if respawned == 0:
					errors.append("pond %d (throttle %.2f): in the water but never put back" % [k, thr])
	print("  lakes: %d drives from a road towards the water, %d reached it and were put back" % [tried, entered])
	if entered < 8:
		errors.append("only %d of %d drives reached the water" % [entered, tried])
