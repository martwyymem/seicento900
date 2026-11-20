## The car rides the road it is drawn on: driven along every motorway (S1 ramps and carriageways) it stays within
## MAX_GAP of the drawn surface, and the chase camera's per-frame cost stays small. The earth round each raised
## embankment's end (TownMap.embankment_cones) is drawn, and the car's support there is the drawn surface.
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
	_cones(map, errors)
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
				var dx := fc._slope(fc.support(p.x - 1.5, p.y, false), fc.support(p.x, p.y, false), fc.support(p.x + 1.5, p.y, false)) # the slopes the physics reads
				var dy := fc._slope(fc.support(p.x, p.y - 1.5, false), fc.support(p.x, p.y, false), fc.support(p.x, p.y + 1.5, false))
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

const CONE_ENDS := 23 ## raised embankment ends on the map (10 of them where a bridge starts)
const CONE_TOL := 0.05 ## m: drawn cone against the car's support
const CONE_WORST := 0.2 ## m: no sample further off than this (a clipped vertex next to an unclipped one)
const CONE_OUTLIERS := 0.02 ## share of samples allowed past CONE_TOL

## Every raised embankment end has its drawn mound, and wherever that mound is the top drawn surface (not under another
## road, its side slopes, a railway bank, or the abutment under a low bridge's end span) the car's support is its height.
func _cones(map: TownMap, errors: Array[String]) -> void:
	var cones := map.embankment_cones()
	if cones.size() != CONE_ENDS:
		errors.append("embankment cones: %d raised ends, expected %d" % [cones.size(), CONE_ENDS])
	var parent := Node3D.new()
	var tb := TownBuilder.new(map, parent)
	var recs: Array = tb._street_meshes()
	var drawn: Array = tb.drawn_cones
	# every raised junction pad decks_at rides has its mound drawn: at a raised end's node the cone's full disc, where
	# raised roads meet mid-way (no end there) a mound of its own (TownMap.pad_mounds)
	var mounds := map.pad_mounds()
	var mids := drawn.filter(func(dc: Dictionary) -> bool: return dc.get("mid", false))
	if mids.size() != mounds.size():
		errors.append("raised junction pads: %d with no raised end at their node, %d mounds drawn for them" % [mounds.size(), mids.size()])
	for cone: Dictionary in cones:
		var found := false
		for dc: Dictionary in drawn:
			if (dc.c as Vector2).distance_to(cone.c) < 0.05 and (dc.roads as Array).has(int(cone.road)) and (dc.tris as PackedVector3Array).size() >= 3 * TownBuilder.CONE_RAYS:
				found = true
		if not found:
			errors.append("embankment cone: no mound drawn past road %d's end at %s" % [cone.road, cone.c])
	var fc := FreeCar.new(map)
	var n := 0
	var off := 0
	var worst := 0.0
	var worst_at := ""
	var mid_n := 0
	var mid_worst := 0.0
	for dc: Dictionary in drawn:
		var tris: PackedVector3Array = dc.tris
		var seen := 0
		for k in range(0, tris.size(), 3):
			for w: Vector3 in [Vector3(1.0, 1.0, 1.0) / 3.0, Vector3(0.5, 0.5, 0.0), Vector3(0.5, 0.0, 0.5), Vector3(0.0, 0.5, 0.5), Vector3(1.0, 0.0, 0.0)]:
				var v: Vector3 = tris[k] * w.x + tris[k + 1] * w.y + tris[k + 2] * w.z
				var y := v.y + TownBuilder.CONE_SINK
				if y < map.terrain(v.x, v.z) + 0.02 or _cone_hidden(map, dc, v.x, v.z, y):
					continue
				fc.z = y
				var e := absf(fc.support(v.x, v.z) - y)
				if dc.get("mid", false):
					mid_n += 1
					mid_worst = maxf(mid_worst, e)
				n += 1
				seen += 1
				if e > CONE_TOL:
					off += 1
				if e > worst:
					worst = e
					worst_at = "road %d's end at %s, (%.1f, %.1f)" % [dc.road, dc.c, v.x, v.z]
		if seen < 20:
			errors.append("embankment cone past road %d at %s: only %d samples where it is the drawn surface" % [dc.road, dc.c, seen])
	var seam := cone_seams(map, recs, drawn)
	print("  ramps: %d raised pads (%d mid-road, %d samples, worst %.2f m); mounds %d samples, %d over %.2f m, worst %.2f m; cone/side-slope seam %d samples, %d over %.2f m, worst %.2f m" % [
		map.raised_pads().size(), mids.size(), mid_n, mid_worst, n, off, CONE_TOL, worst, seam[0], seam[1], CONE_TOL, seam[2]])
	if seam[0] < 150:
		errors.append("cone/side-slope seam: only %d samples" % seam[0])
	if seam[2] > SEAM_WORST:
		errors.append("cone/side-slope seam: %.2f m step at %s" % [seam[2], seam[3]])
	parent.free()
	if n < 2000:
		errors.append("embankment cones: only %d samples" % n)
	if worst > CONE_WORST:
		errors.append("embankment cone: the car rides %.2f m off the drawn mound at %s" % [worst, worst_at])
	if off > n * CONE_OUTLIERS:
		errors.append("embankment cones: %d of %d samples more than %.2f m off the drawn mound" % [off, n, CONE_TOL])

const SEAM_WORST := 0.2 ## m: the step where a cone meets its road's side slopes (0.15 where a raised junction's pad stands over one road's slope)
const SEAM_CELL := 2.0

## Where each raised end's cone meets its road's side slopes (the line across the end, either side of the carriageway,
## out to the slope's foot): the drawn bank just behind it against just past it. [samples, over CONE_TOL, worst, where]
func cone_seams(map: TownMap, recs: Array, drawn: Array) -> Array:
	var grid := {}
	for dc: Dictionary in drawn:
		var c: Vector2 = dc.c
		for cx in range(int(floor((c.x - 12.0) / SEAM_CELL)), int(floor((c.x + 12.0) / SEAM_CELL)) + 1):
			for cy in range(int(floor((c.y - 12.0) / SEAM_CELL)), int(floor((c.y + 12.0) / SEAM_CELL)) + 1):
				grid[Vector2i(cx, cy)] = PackedVector3Array()
	for rec: Array in recs:
		if int(rec[1]) != TownBuilder.STREET_BANK:
			continue
		var mesh: Mesh = rec[0]
		for si in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var cnt := idx.size() if not idx.is_empty() else v.size()
			for k in range(0, cnt, 3):
				var a := v[idx[k] if not idx.is_empty() else k]
				var b := v[idx[k + 1] if not idx.is_empty() else k + 1]
				var d := v[idx[k + 2] if not idx.is_empty() else k + 2]
				for cx in range(int(floor(minf(a.x, minf(b.x, d.x)) / SEAM_CELL)), int(floor(maxf(a.x, maxf(b.x, d.x)) / SEAM_CELL)) + 1):
					for cy in range(int(floor(minf(a.z, minf(b.z, d.z)) / SEAM_CELL)), int(floor(maxf(a.z, maxf(b.z, d.z)) / SEAM_CELL)) + 1):
						var ck := Vector2i(cx, cy)
						if grid.has(ck):
							grid[ck].append_array(PackedVector3Array([a, b, d]))
	var n := 0
	var off := 0
	var worst := 0.0
	var worst_at := ""
	for dc: Dictionary in drawn:
		if dc.get("mid", false):
			continue
		var c: Vector2 = dc.c
		for k in (dc.roads as Array).size():
			var ri: int = dc.roads[k]
			var o: Vector2 = dc.outs[k]
			var pts := map.road_pts[ri]
			var zs := map.road_z[ri]
			var deck := float(zs[0]) if pts[0].distance_to(c) < 0.05 else float(zs[zs.size() - 1])
			for side: float in [-1.0, 1.0]:
				var perp := o.orthogonal() * side
				var x := 0.3
				while x < deck * TownMap.EMBANKMENT - 0.3:
					var q := c + perp * (map.road_w[ri] * 0.5 + x)
					x += 0.3
					var hb := _bank_top(grid, q - o * 0.15)
					var ha := _bank_top(grid, q + o * 0.15)
					if hb == -INF or ha == -INF or minf(hb, ha) < map.terrain(q.x, q.y) + 0.02 or _on_other_road(map, ri, q, o):
						continue
					var e := absf(hb - ha)
					n += 1
					if e > CONE_TOL:
						off += 1
					if e > worst:
						worst = e
						worst_at = "road %d's end at %s, (%.1f, %.1f)" % [ri, c, q.x, q.y]
	return [n, off, worst, worst_at]

## True where another road's carriageway (or its bridge's parapet) covers either side of the seam at q: the mound is kept
## under it there, so that is no step between cone and side slope.
func _on_other_road(map: TownMap, ri: int, q: Vector2, o: Vector2) -> bool:
	for p: Vector2 in [q - o * 0.15, q + o * 0.15]:
		for e: Array in map.decks_at(p.x, p.y, TownMap.DRIVE_REACH):
			if int(e[0]) != ri and e[3] != Vector2.RIGHT and float(e[2]) <= (TownMap.PARAPET if e[5] else 0.0):
				return true
	return false

func _bank_top(grid: Dictionary, p: Vector2) -> float:
	var tris: PackedVector3Array = grid.get(Vector2i(int(floor(p.x / SEAM_CELL)), int(floor(p.y / SEAM_CELL))), PackedVector3Array())
	var top := -INF
	for k in range(0, tris.size(), 3):
		var a := tris[k]
		var v0 := Vector2(tris[k + 1].x - a.x, tris[k + 1].z - a.z)
		var v1 := Vector2(tris[k + 2].x - a.x, tris[k + 2].z - a.z)
		var v2 := p - Vector2(a.x, a.z)
		var den := v0.x * v1.y - v1.x * v0.y
		if absf(den) < 1e-9:
			continue
		var u := (v2.x * v1.y - v1.x * v2.y) / den
		var w := (v0.x * v2.y - v2.x * v0.y) / den
		if u < -1e-4 or w < -1e-4 or u + w > 1.0001:
			continue
		top = maxf(top, a.y + (tris[k + 1].y - a.y) * u + (tris[k + 2].y - a.y) * w)
	return top

## True where something else drawn stands over the mound (drawn y high) at map point (x, z), or the car cannot get there (the abutment under a
## low bridge's end span, solid up to its deck).
func _cone_hidden(map: TownMap, dc: Dictionary, x: float, z: float, y: float) -> bool:
	if map.rail_bank(x, z) > y + 0.03:
		return true
	var p := Vector2(x, z)
	for e: Array in map.decks_at(x, z, TownMap.DRIVE_REACH):
		if e[3] == Vector2.RIGHT:
			continue # (a raised junction's pad: the mound itself)
		var k := (dc.roads as Array).find(int(e[0]))
		if k >= 0 and (p - (dc.c as Vector2)).dot(dc.outs[k]) >= 0.0:
			continue # (past that road's end: the mound itself)
		if e[5] and e[7] and float(e[2]) <= 0.0 and map.ground(x, z) + float(e[1]) - map.terrain(x, z) < FreeCar.LOW_BRIDGE:
			return true
		var over := maxf(float(e[2]), 0.0)
		var lift := map.road_lift(int(e[0])) * (1.0 - smoothstep(0.0, TownMap.LIFT_RAMP, float(e[2])))
		var h := -INF
		if e[5]:
			if over <= TownMap.PARAPET:
				h = maxf(map.ground(x, z), map.terrain(x, z)) + float(e[1]) + lift
				if h - y > 1.0:
					h = -INF # (a bridge overhead)
		else:
			h = map.terrain(x, z) + maxf(0.0, float(e[1]) - over / TownMap.EMBANKMENT) + lift
		if h > y + 0.03:
			return true
	var hit := map.road_at(x, z, y)
	return not hit.is_empty() and not (dc.roads as Array).has(int(hit.road)) and float(hit.height) > y - 0.05
