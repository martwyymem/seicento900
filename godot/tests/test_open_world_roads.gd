## The open world's streets as drawn (TownBuilder.ribbon, the same function _street_meshes draws with): no folded
## (bow-tie) quads on tight bends, no corner pinched narrow, way joins drawn as one continuous street, junction discs
## that look like their biggest road (no potholes on a main road's junction, no tarmac where only dirt tracks meet),
## the car riding the drawn surface, and the two halves of a divided road not drawn over each other.
## tests/_road_audit_probe.gd prints the same measures with the worst places.
extends RefCounted

var completed := false
const FOLD_TOL := 0.05 ## m an edge may run backwards (rounding where a bend's inner points meet)
const NARROW := 0.85 ## share of its width a ribbon keeps across a corner
const MAX_NARROW := 3
const JOIN_TOL := 0.05 ## m between the edges of two equally wide ways where they join
const RIDE_TOL := 0.05 ## m between the car's road height and the drawn surface
const MAX_RIDE_OFF := 40 ## samples allowed beyond RIDE_TOL (of ~250,000)
const ROUTE_STEP := 0.3 ## m the car's ride height may change between samples 1 m apart along a mission route ...
const ROUTE_SLOPE_STEP := 0.7 ## ... or on an embankment's 1:1.5 side, which the car drives up (FreeCar.WALL_STEP is 0.9)
const MAX_DUAL_OVERLAP := 25.0 ## m of a divided road's halves drawn over each other (they meet at junction mouths)

func run() -> Array:
	var errors: Array[String] = []
	var map := TownMap.load_map("brzeszcze")
	if map == null:
		errors.append("data/world/brzeszcze.json did not load")
		completed = true
		return errors
	var ribs := []
	for ri in map.road_pts.size():
		ribs.append(TownBuilder.ribbon(map, ri))
	_shape(map, ribs, errors)
	_joins(map, ribs, errors)
	_discs(map, errors)
	_ride(map, ribs, errors)
	_dual(map, errors)
	_route_steps(map, errors)
	_s1_full_throttle(map, errors)
	completed = true
	return errors

func _shape(map: TownMap, ribs: Array, errors: Array[String]) -> void:
	var folds := 0
	var narrow := 0
	var where := ""
	for ri in map.road_pts.size():
		var pts := map.road_pts[ri]
		var left: PackedVector2Array = ribs[ri].left
		var right: PackedVector2Array = ribs[ri].right
		var halves: PackedFloat32Array = ribs[ri].half
		for i in pts.size() - 1:
			var seg := pts[i + 1] - pts[i]
			if seg.length() < 0.05:
				continue
			var d := seg.normalized()
			if (left[i + 1] - left[i]).dot(d) < -FOLD_TOL or (right[i + 1] - right[i]).dot(d) < -FOLD_TOL:
				folds += 1
				where = "%s at %s" % [map.road_name[ri], pts[i]]
			if i > 0 and pts[i].distance_to(pts[i - 1]) > 0.05:
				var d0 := (pts[i] - pts[i - 1]).normalized()
				if absf((right[i] - left[i]).dot(Vector2(-d0.y, d0.x))) < 2.0 * halves[i] * NARROW:
					narrow += 1
	if folds > 0:
		errors.append("roads: %d ribbon quads fold over on a bend (e.g. '%s')" % [folds, where])
	if narrow > MAX_NARROW:
		errors.append("roads: the ribbon pinches below %d%% of its width at %d corners" % [int(NARROW * 100.0), narrow])

func _joins(map: TownMap, ribs: Array, errors: Array[String]) -> void:
	var joins := map.way_joins()
	if joins.size() < 200:
		errors.append("roads: only %d way joins found" % joins.size())
	var bad := 0
	var where := ""
	for nid in joins:
		var e: Array = joins[nid]
		var a: int = e[0][0]
		var ia: int = e[0][1]
		var b: int = e[1][0]
		var ib: int = e[1][1]
		if absf(map.road_w[a] - map.road_w[b]) > 0.01:
			continue
		var la: Vector2 = ribs[a].left[ia]
		var ra: Vector2 = ribs[a].right[ia]
		var same := (ia == 0) != (ib == 0) # one ends where the other starts: left meets left
		var lb: Vector2 = ribs[b].left[ib] if same else ribs[b].right[ib]
		var rb: Vector2 = ribs[b].right[ib] if same else ribs[b].left[ib]
		if maxf(la.distance_to(lb), ra.distance_to(rb)) > JOIN_TOL:
			bad += 1
			where = "%s at %s" % [map.road_name[a], map.node_pos.get(nid, Vector2.ZERO)]
	if bad > 0:
		errors.append("roads: %d way joins where the two ribbons' edges do not meet (e.g. '%s')" % [bad, where])

func _discs(map: TownMap, errors: Array[String]) -> void:
	var styles := TownBuilder.junction_styles(map)
	var at := {}
	for ri in map.road_pts.size():
		for m in map.road_marks[ri]:
			var nid := str(m[1])
			if not at.has(nid):
				at[nid] = []
			at[nid].append(ri)
	var potholed := 0
	var tarmac := 0
	var joins := map.way_joins()
	for nid in at:
		if (at[nid] as Array).size() < 2 or joins.has(nid):
			continue
		var look: Vector2i = styles.get(nid, Vector2i.ZERO)
		var sound := false
		var dirt := true
		for ri: int in at[nid]:
			if map.road_surface[ri] == 0 and map.road_wear(ri) == 0.0:
				sound = true
			if map.road_surface[ri] != 2:
				dirt = false
		if sound and look.x == 0:
			potholed += 1
		if dirt and look.y != 2:
			tarmac += 1
	if potholed > 0:
		errors.append("roads: %d junction discs drawn pot-holed where a main road crosses" % potholed)
	if tarmac > 0:
		errors.append("roads: %d junction discs drawn as tarmac where only dirt roads meet" % tarmac)

func _ride(map: TownMap, ribs: Array, errors: Array[String]) -> void:
	var off := 0
	var worst := 0.0
	var where := ""
	var samples := 0
	for ri in map.road_pts.size():
		var pts := map.road_pts[ri]
		var left: PackedVector2Array = ribs[ri].left
		var right: PackedVector2Array = ribs[ri].right
		var hl: PackedFloat32Array = ribs[ri].hl
		var hr: PackedFloat32Array = ribs[ri].hr
		for i in pts.size() - 1:
			if pts[i].distance_to(pts[i + 1]) < 0.5:
				continue
			for u: float in [0.15, 0.5, 0.85]:
				var p := left[i].lerp(left[i + 1], 0.5).lerp(right[i].lerp(right[i + 1], 0.5), u)
				var h := lerpf((hl[i] + hl[i + 1]) * 0.5, (hr[i] + hr[i + 1]) * 0.5, u)
				var hit := map.road_at(p.x, p.y, h)
				if hit.is_empty() or int(hit.road) != ri:
					continue
				samples += 1
				var dr := absf(float(hit.height) - h)
				if dr > RIDE_TOL:
					off += 1
				if dr > worst:
					worst = dr
					where = "%s at %s" % [map.road_name[ri], p]
	if samples < 100000:
		errors.append("roads: only %d ride samples" % samples)
	if off > MAX_RIDE_OFF:
		errors.append("roads: the car's height is off the drawn street by over %.2f m at %d of %d samples (worst %.2f m, '%s')" % [RIDE_TOL, off, samples, worst, where])

## Within 15 m of a junction or end of road ri (where the halves of a divided road converge into its mouth).
func _near_end(map: TownMap, ri: int, p: Vector2) -> bool:
	for m in map.road_marks[ri]:
		if map.road_pts[ri][int(m[0])].distance_to(p) < 15.0:
			return true
	return false

func _dual(map: TownMap, errors: Array[String]) -> void:
	var overlap := 0.0
	var where := {}
	for ri in map.road_pts.size():
		if map.road_oneway[ri] == 0 or map.road_name[ri] == "" or map.road_kind[ri].begins_with("motorway"):
			continue
		var pts := map.road_pts[ri]
		for i in pts.size() - 1:
			var p := (pts[i] + pts[i + 1]) * 0.5
			var dir := (pts[i + 1] - pts[i]).normalized()
			var ck := map._cell_key(int(floor(p.x / TownMap.CELL)), int(floor(p.y / TownMap.CELL)))
			for sid in map._seg_cells.get(ck, PackedInt32Array()):
				var rj := map._seg_road[sid]
				if rj == ri or map.road_name[rj] != map.road_name[ri] or map.road_oneway[rj] == 0:
					continue
				var a := map.road_pts[rj][map._seg_i[sid]]
				var b := map.road_pts[rj][map._seg_i[sid] + 1]
				if (b - a).normalized().dot(dir) > -0.94:
					continue
				var t := clampf((p - a).dot(b - a) / maxf((b - a).length_squared(), 1e-6), 0.0, 1.0)
				if p.distance_to(a.lerp(b, t)) < (map.road_w[ri] + map.road_w[rj]) * 0.5 - 0.5 and not _near_end(map, ri, p) \
						and not _near_end(map, rj, p):
					overlap += pts[i].distance_to(pts[i + 1])
					where[map.road_name[ri]] = p
					break
	if overlap > MAX_DUAL_OVERLAP:
		errors.append("roads: %.0f m of divided roads' halves drawn over each other: %s" % [overlap, where])

## Every campaign mission's route (and each rally stage) on the map, driven at 1 m steps the way FreeCar finds its
## ground (support() from the height it had): no step over ROUTE_STEP (a ramp's side, a railway embankment over a track,
## a raised junction's corner it cannot climb). Off the tarmac (an embankment's side) a 1:1.5 slope is allowed.
func _route_steps(map: TownMap, errors: Array[String]) -> void:
	var fc := FreeCar.new(map)
	var samples := 0
	var steps := 0
	var worst := 0.0
	var where := ""
	for k in Missions.MISSIONS.size():
		var ev := MapMissions.event(Missions.BASE + k)
		if ev.is_empty():
			continue
		var paths: Array = [ev.path]
		for st in ev.get("stages", []):
			paths.append(st.path)
		for path: PackedVector2Array in paths:
			if path.size() < 2:
				continue
			var start := map.road_at(path[0].x, path[0].y, -INF, 1.0)
			fc.z = float(start.height) if not start.is_empty() else map.ground(path[0].x, path[0].y)
			fc.z = fc.support(path[0].x, path[0].y)
			for i in path.size() - 1:
				var n := maxi(1, int(ceil(path[i].distance_to(path[i + 1]))))
				for j in range(1, n + 1):
					var p := path[i].lerp(path[i + 1], float(j) / n)
					var h := fc.support(p.x, p.y)
					samples += 1
					var lim := ROUTE_STEP if not map.road_at(p.x, p.y).is_empty() else ROUTE_SLOPE_STEP
					if absf(h - fc.z) > lim:
						steps += 1
						where = "%s %+.2f m at %s" % [ev.id, h - fc.z, p]
					worst = maxf(worst, absf(h - fc.z))
					fc.z = h
	if samples < 5000:
		errors.append("roads: only %d mission route samples" % samples)
	if steps > 0:
		errors.append("roads: %d steps along the mission routes (worst %.2f m, e.g. %s)" % [steps, worst, where])

## Flat out along every S1 carriageway (over its ramps and decks) the car rides the drawn surface within 0.1 m and never
## stalls (a stale embankment entry once held it 0.7 m under a deck's surface and stopped it with no collision).
func _s1_full_throttle(map: TownMap, errors: Array[String]) -> void:
	var dt := 1.0 / 120.0
	var worst := 0.0
	var where := ""
	var stalls := 0
	var driven := 0
	for ri in map.road_pts.size():
		if map.road_kind[ri] != "motorway" or map.road_len[ri] < 200.0:
			continue
		driven += 1
		var pts := map.road_pts[ri]
		var fc := FreeCar.new(map)
		fc.place(pts[0], (pts[1] - pts[0]).angle())
		var s := 0.0
		var t := 0.0
		while t < 40.0 and s < map.road_len[ri] - 30.0:
			t += dt
			var here := Vector2(fc.car.x, fc.car.y)
			var near := map.nearest_road(here, 10.0)
			if not near.is_empty() and int(near.road) == ri:
				var acc := 0.0
				for k in int(near.i):
					acc += pts[k].distance_to(pts[k + 1])
				s = acc + pts[int(near.i)].distance_to(near.pos)
			var aim: Vector2 = map.along(ri, s + 12.0)[0]
			var err := wrapf((aim - here).angle() - fc.car.heading, -PI, PI)
			fc.step(dt, 1.0, 0.0, clampf(err * 2.5, -1.0, 1.0), false, false, 0.0)
			var hit := map.road_at(fc.car.x, fc.car.y, fc.z)
			if not fc.airborne and not hit.is_empty() and int(hit.road) == ri and absf(float(hit.dist)) < float(hit.half) - 1.0:
				var gap := absf(fc.z - float(hit.height))
				if gap > worst:
					worst = gap
					where = "%s at %s" % [map.road_name[ri], Vector2(fc.car.x, fc.car.y)]
			if t > 8.0 and absf(fc.car.speed) < 10.0:
				stalls += 1
				where = "%s stalled at %s" % [map.road_name[ri], Vector2(fc.car.x, fc.car.y)]
				break
	if driven < 4:
		errors.append("roads: only %d S1 carriageways driven" % driven)
	if worst > 0.1 or stalls > 0:
		errors.append("roads: flat out on the S1 the car sits %.2f m off the drawn surface, %d stalls (%s)" % [worst, stalls, where])
