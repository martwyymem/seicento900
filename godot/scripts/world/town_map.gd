## The open-world town (data/world/<key>.json, baked by tools/build_open_world.py from OpenStreetMap): ground
## height, the road network with its bridge decks and ramps, what surface lies where, and the solid things a car
## can hit (buildings, trees, posts, the edge of the map). Map frame as everywhere in the game: x east, y south,
## metres; Godot X = x, Z = y, Y = height above sea level.
class_name TownMap
extends RefCounted

const CELL := 12.0 ## metres: spatial hash cell for road segments
const BCELL := 16.0 ## metres: spatial hash cell for building edges and trees
const CLASS_RANK := {"motorway": 9, "trunk": 9, "primary": 8, "secondary": 7, "tertiary": 6, "motorway_link": 6,
	"trunk_link": 6, "primary_link": 6, "secondary_link": 5, "tertiary_link": 5, "unclassified": 4, "residential": 4,
	"living_street": 3, "road": 3, "pedestrian": 2, "service": 2, "track": 1}
## Speed limits (km/h) where the map has none, for the traffic and the GPS
const DEFAULT_LIMIT := {"motorway": 140.0, "trunk": 100.0, "primary": 90.0, "secondary": 80.0, "tertiary": 60.0,
	"unclassified": 50.0, "residential": 40.0, "living_street": 20.0, "service": 20.0, "track": 30.0}
const TOWN_LIMIT := 50.0 ## km/h inside the built-up area, the Polish default
const TREE_RADIUS := 0.35
const DRIVE_REACH := 1.5 ## metres beyond a road's edge where its deck still holds a car up

var key := ""
var name := ""
var raw: Dictionary = {}
var bounds := Rect2() ## the drivable area
var extent := Rect2() ## everything that is drawn
var boundary := PackedVector2Array() ## the town limit

# terrain
var tx0 := 0.0
var ty0 := 0.0
var tstep := 40.0
var tnx := 0
var tny := 0
var th := PackedFloat32Array()

# roads
var road_pts: Array[PackedVector2Array] = []
var road_z: Array[PackedFloat32Array] = [] ## deck height over the ground per point (empty: on the ground)
var road_w := PackedFloat32Array()
var road_kind: PackedStringArray = []
var road_name: PackedStringArray = []
var road_surface := PackedInt32Array() ## 0 asphalt, 1 setts or slabs, 2 unpaved
var road_oneway := PackedByteArray()
var road_lanes := PackedInt32Array()
var road_limit := PackedFloat32Array() ## km/h
var road_bridge := PackedByteArray()
var road_len := PackedFloat32Array()
var road_marks: Array = [] ## per road: [[point index, node id] ...] junctions and ends
var road_rank := PackedInt32Array()
var _seg_road := PackedInt32Array()
var _seg_i := PackedInt32Array()
var _seg_cells := {} ## int cell -> PackedInt32Array of segment ids

# graph (GPS, traffic)
var node_pos := {} ## node id -> Vector2
var node_edges := {} ## node id -> [[other node id, road, from idx, to idx, length, allowed forward]]

# buildings, trees, obstacles
var buildings: Array = [] ## raw entries [kind, height, levels, roof, flat ring, (name)]
var bld_rings: Array[PackedVector2Array] = []
var bld_rect: Array[Rect2] = []
var _bld_cells := {} ## int cell -> PackedInt32Array of building ids
var _post_cells := {} ## int cell -> PackedVector3Array (x, y, radius) of trees, lamps and posts
var _wall_cells := {} ## int cell -> PackedFloat32Array (ax, ay, bx, by, half thickness)
var water_rings: Array[PackedVector2Array] = []
var water_rects: Array[Rect2] = []
var water_level := PackedFloat32Array()
var trains: Array = [] ## the train's cars: [Vector2 centre, heading (rad, map frame), half length, half width, height]
var booms: Array = [] ## level crossing booms: [Vector2 hinge, Vector2 tip, bool closed, float angle
## (rad, 0 = down)]; TownBuilder swings them
var areas: Array = []
var places: Array = []
var spots := {}
var in_town_cache := {}

static var _cache := {}

static func load_map(map_key: String) -> TownMap:
	if not _cache.has(map_key):
		var m := TownMap.new()
		if not m._load(map_key):
			return null
		_cache[map_key] = m
	return _cache[map_key]

func _load(map_key: String) -> bool:
	key = map_key
	var path := "res://data/world/%s.json" % map_key
	if not FileAccess.file_exists(path):
		push_error("Open world map %s is missing (run tools/build_open_world.py)" % path)
		return false
	raw = JSON.parse_string(FileAccess.get_file_as_string(path))
	if raw == null or raw.is_empty():
		return false
	name = raw.get("name", map_key)
	var b: Array = raw.bounds
	bounds = Rect2(b[0], b[1], b[2] - b[0], b[3] - b[1])
	var e: Array = raw.extent
	extent = Rect2(e[0], e[1], e[2] - e[0], e[3] - e[1])
	boundary = _flat(raw.get("boundary", []))
	var t: Dictionary = raw.terrain
	tx0 = t.x0
	ty0 = t.y0
	tstep = t.step
	tnx = int(t.nx)
	tny = int(t.ny)
	th = PackedFloat32Array(t.h)
	_load_roads()
	_load_buildings()
	_load_obstacles()
	areas = raw.get("areas", [])
	places = raw.get("places", [])
	spots = raw.get("spots", {})
	return true

static func _flat(arr: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(arr.size() / 2)
	for i in out.size():
		out[i] = Vector2(arr[2 * i], arr[2 * i + 1])
	return out

func _cell_key(cx: int, cy: int) -> int:
	return (cx + 4096) * 8192 + (cy + 4096)

# ---------------------------------------------------------------------------------------------- terrain

## Ground height (m above sea level) at a map point, bilinear in the baked grid.
func ground(x: float, y: float) -> float:
	var fx := clampf((x - tx0) / tstep, 0.0, tnx - 1.001)
	var fy := clampf((y - ty0) / tstep, 0.0, tny - 1.001)
	var i := int(fx)
	var j := int(fy)
	var u := fx - i
	var v := fy - j
	var k := j * tnx + i
	var a := th[k]
	var b := th[k + 1]
	var c := th[k + tnx]
	var d := th[k + tnx + 1]
	return lerpf(lerpf(a, b, u), lerpf(c, d, u), v)

# ---------------------------------------------------------------------------------------------- roads

func _load_roads() -> void:
	var lanes_default := {"motorway": 2, "secondary": 2, "tertiary": 2, "residential": 2, "unclassified": 2}
	for r in raw.roads:
		var pts := _flat(r.p)
		var ri := road_pts.size()
		road_pts.append(pts)
		road_z.append(PackedFloat32Array(r.get("z", [])))
		road_w.append(float(r.w))
		var kind: String = r.k
		road_kind.append(kind)
		road_name.append(str(r.get("n", "")))
		road_surface.append(int(r.get("s", 0)))
		road_oneway.append(int(r.get("o", 0)))
		road_lanes.append(int(r.get("l", lanes_default.get(kind, 1))))
		road_bridge.append(int(r.get("b", 0)))
		road_rank.append(CLASS_RANK.get(kind, 2))
		var limit := float(r.get("v", 0.0))
		if limit <= 0.0:
			limit = DEFAULT_LIMIT.get(kind, 50.0)
			if limit > TOWN_LIMIT and kind != "motorway" and in_town(pts[pts.size() / 2]):
				limit = TOWN_LIMIT
		road_limit.append(limit)
		var length := 0.0
		for i in pts.size() - 1:
			length += pts[i].distance_to(pts[i + 1])
		road_len.append(length)
		var marks: Array = r.get("e", [])
		road_marks.append(marks)
		var half := float(r.w) * 0.5 + DRIVE_REACH
		for i in pts.size() - 1:
			var sid := _seg_road.size()
			_seg_road.append(ri)
			_seg_i.append(i)
			var a := pts[i]
			var bb := pts[i + 1]
			var cx0 := int(floor((minf(a.x, bb.x) - half) / CELL))
			var cx1 := int(floor((maxf(a.x, bb.x) + half) / CELL))
			var cy0 := int(floor((minf(a.y, bb.y) - half) / CELL))
			var cy1 := int(floor((maxf(a.y, bb.y) + half) / CELL))
			for cx in range(cx0, cx1 + 1):
				for cy in range(cy0, cy1 + 1):
					var ck := _cell_key(cx, cy)
					if not _seg_cells.has(ck):
						_seg_cells[ck] = PackedInt32Array()
					_seg_cells[ck].append(sid)
		# graph edges between consecutive junctions
		for m in range(marks.size() - 1):
			var ia := int(marks[m][0])
			var ib := int(marks[m + 1][0])
			var na := str(marks[m][1])
			var nb := str(marks[m + 1][1])
			if na == nb:
				continue
			var seg_len := 0.0
			for i in range(ia, ib):
				seg_len += pts[i].distance_to(pts[i + 1])
			node_pos[na] = pts[ia]
			node_pos[nb] = pts[ib]
			if not node_edges.has(na):
				node_edges[na] = []
			if not node_edges.has(nb):
				node_edges[nb] = []
			node_edges[na].append([nb, ri, ia, ib, seg_len, true])
			node_edges[nb].append([na, ri, ib, ia, seg_len, road_oneway[ri] == 0])

## Height of a road's deck over the ground at point index i + t towards i + 1.
func deck_at(ri: int, i: int, t: float) -> float:
	var z := road_z[ri]
	if z.is_empty():
		return 0.0
	return lerpf(z[i], z[mini(i + 1, z.size() - 1)], t)

## The road under a map point, picking among overlapping decks the one closest to the height z_ref (a car's
## current height, or -INF for the lowest). {} when on no road. Keys: road, i (segment), t, dist (from the
## centreline, signed + right of travel), half, deck (height over ground), surface, height (absolute).
func road_at(x: float, y: float, z_ref := -INF, reach := 0.0) -> Dictionary:
	var ck := _cell_key(int(floor(x / CELL)), int(floor(y / CELL)))
	if not _seg_cells.has(ck):
		return {}
	var best := {}
	var best_score := INF
	var p := Vector2(x, y)
	for sid in _seg_cells[ck]:
		var ri := _seg_road[sid]
		var i := _seg_i[sid]
		var pts := road_pts[ri]
		var a := pts[i]
		var b := pts[i + 1]
		var ab := b - a
		var l2 := ab.length_squared()
		var t := 0.0 if l2 < 1e-6 else clampf((p - a).dot(ab) / l2, 0.0, 1.0)
		var q := a + ab * t
		var d := p.distance_to(q)
		var half := road_w[ri] * 0.5
		if d > half + reach:
			continue
		var deck := deck_at(ri, i, t)
		var score := d * 0.02 - road_rank[ri] * 0.001
		if z_ref > -INF:
			var h := ground(x, y) + deck
			score += absf(h - z_ref)
		else:
			score += deck * 10.0
		if score < best_score:
			best_score = score
			var side := signf(ab.x * (p.y - a.y) - ab.y * (p.x - a.x))
			best = {"road": ri, "i": i, "t": t, "dist": d * side, "half": half, "deck": deck,
				"surface": road_surface[ri]}
	if not best.is_empty():
		best["height"] = ground(x, y) + float(best.deck)
	return best

## Every road deck under a map point (for the car's vertical contact: it may be on a bridge or under it).
func decks_at(x: float, y: float, reach: float) -> Array:
	var ck := _cell_key(int(floor(x / CELL)), int(floor(y / CELL)))
	var out := []
	if not _seg_cells.has(ck):
		return out
	var p := Vector2(x, y)
	for sid in _seg_cells[ck]:
		var ri := _seg_road[sid]
		if road_z[ri].is_empty():
			continue
		var i := _seg_i[sid]
		var pts := road_pts[ri]
		var a := pts[i]
		var ab := pts[i + 1] - a
		var l2 := ab.length_squared()
		var t := 0.0 if l2 < 1e-6 else clampf((p - a).dot(ab) / l2, 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		if d <= road_w[ri] * 0.5 + reach:
			out.append([ri, deck_at(ri, i, t), d - road_w[ri] * 0.5, ab.normalized(), (p - (a + ab * t))])
	return out

## Point on road ri at arc length s from its start: [Vector2 position, Vector2 direction, point index].
func along(ri: int, s: float) -> Array:
	var pts := road_pts[ri]
	var acc := 0.0
	for i in pts.size() - 1:
		var l := pts[i].distance_to(pts[i + 1])
		if acc + l >= s or i == pts.size() - 2:
			var t := clampf((s - acc) / maxf(l, 1e-6), 0.0, 1.0)
			var dir := (pts[i + 1] - pts[i]) / maxf(l, 1e-6)
			return [pts[i].lerp(pts[i + 1], t), dir, i, t]
		acc += l
	return [pts[0], Vector2.RIGHT, 0, 0.0]

## The nearest point on any road within radius: {road, i, t, pos, dir, dist} or {}.
func nearest_road(p: Vector2, radius := 60.0, min_rank := 0) -> Dictionary:
	var best := {}
	var best_d := radius
	var r := int(ceil(radius / CELL))
	var cx := int(floor(p.x / CELL))
	var cy := int(floor(p.y / CELL))
	var seen := {}
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var ck := _cell_key(cx + dx, cy + dy)
			if not _seg_cells.has(ck):
				continue
			for sid in _seg_cells[ck]:
				if seen.has(sid):
					continue
				seen[sid] = true
				var ri := _seg_road[sid]
				if road_rank[ri] < min_rank:
					continue
				var i := _seg_i[sid]
				var pts := road_pts[ri]
				var a := pts[i]
				var ab := pts[i + 1] - a
				var l2 := ab.length_squared()
				var t := 0.0 if l2 < 1e-6 else clampf((p - a).dot(ab) / l2, 0.0, 1.0)
				var q := a + ab * t
				var d := p.distance_to(q)
				if d < best_d:
					best_d = d
					best = {"road": ri, "i": i, "t": t, "pos": q, "dir": ab.normalized(), "dist": d}
	return best

func in_town(p: Vector2) -> bool:
	if boundary.size() < 3:
		return true
	return Geometry2D.is_point_in_polygon(p, boundary)

# ---------------------------------------------------------------------------------------------- GPS

## Shortest drivable route between two map points along the road graph (A*), as a polyline. Empty if none.
func route(from: Vector2, to: Vector2) -> PackedVector2Array:
	var a := nearest_road(from, 120.0)
	var b := nearest_road(to, 250.0)
	if a.is_empty() or b.is_empty():
		return PackedVector2Array()
	# start and goal: the junctions either side of each projected point
	var starts := _ends_of(a)
	var goals := _ends_of(b)
	var goal_set := {}
	for g in goals:
		goal_set[g[0]] = g
	var open := [] # [f, g, node]
	var came := {}
	var g_score := {}
	for s in starts:
		g_score[s[0]] = s[1]
		came[s[0]] = null
		open.append([s[1] + (node_pos[s[0]] as Vector2).distance_to(to), s[1], s[0]])
	var found := ""
	var guard := 0
	while not open.is_empty() and guard < 60000:
		guard += 1
		var bi := 0
		for k in open.size():
			if open[k][0] < open[bi][0]:
				bi = k
		var cur: Array = open[bi]
		open.remove_at(bi)
		var node: String = cur[2]
		if cur[1] > g_score.get(node, INF) + 1e-6:
			continue
		if goal_set.has(node):
			found = node
			break
		for e in node_edges.get(node, []):
			if not e[5]:
				continue
			var nb: String = e[0]
			var cost: float = cur[1] + e[4] * (1.0 if road_rank[e[1]] >= 4 else 1.6)
			if cost < g_score.get(nb, INF):
				g_score[nb] = cost
				came[nb] = [node, e]
				open.append([cost + (node_pos[nb] as Vector2).distance_to(to), cost, nb])
	if found == "":
		return PackedVector2Array()
	var chain := []
	var n := found
	while came[n] != null:
		chain.push_front(came[n][1])
		n = came[n][0]
	var out := PackedVector2Array()
	out.append(a.pos)
	for e in chain:
		var pts := road_pts[e[1]]
		var i0: int = e[2]
		var i1: int = e[3]
		var stepi := 1 if i1 >= i0 else -1
		var i := i0
		while true:
			out.append(pts[i])
			if i == i1:
				break
			i += stepi
	out.append(b.pos)
	return out

## [[node id, cost from the point]] for the junctions at either end of the stretch a projected point lies on.
func _ends_of(hit: Dictionary) -> Array:
	var ri: int = hit.road
	var marks: Array = road_marks[ri]
	var pts := road_pts[ri]
	var pos := float(hit.i) + float(hit.t)
	var out := []
	for m in range(marks.size() - 1):
		var ia := int(marks[m][0])
		var ib := int(marks[m + 1][0])
		if pos >= ia and pos <= ib:
			var to_a := 0.0
			var to_b := 0.0
			for i in range(ia, ib):
				var l := pts[i].distance_to(pts[i + 1])
				if i + 1 <= pos:
					to_a += l
				elif i >= pos:
					to_b += l
				else:
					var f := pos - i
					to_a += l * f
					to_b += l * (1.0 - f)
			out.append([str(marks[m][1]), to_a])
			out.append([str(marks[m + 1][1]), to_b])
			break
	return out

# ---------------------------------------------------------------------------------------------- solids

func _load_buildings() -> void:
	buildings = raw.get("buildings", [])
	for bi in buildings.size():
		var ring := _flat(buildings[bi][4])
		bld_rings.append(ring)
		var r := Rect2(ring[0], Vector2.ZERO)
		for p in ring:
			r = r.expand(p)
		bld_rect.append(r)
		for cx in range(int(floor(r.position.x / BCELL)), int(floor(r.end.x / BCELL)) + 1):
			for cy in range(int(floor(r.position.y / BCELL)), int(floor(r.end.y / BCELL)) + 1):
				var ck := _cell_key(cx, cy)
				if not _bld_cells.has(ck):
					_bld_cells[ck] = PackedInt32Array()
				_bld_cells[ck].append(bi)

func _load_obstacles() -> void:
	var trees: Array = raw.get("trees", [])
	for k in range(0, trees.size(), 3):
		add_post(Vector2(trees[k], trees[k + 1]), TREE_RADIUS)
	for wall in raw.get("fences", []):
		var style := int(wall[4]) if wall.size() > 4 else 0
		add_wall(Vector2(wall[0], wall[1]), Vector2(wall[2], wall[3]), 0.48 if style == 2 else 0.12)
	var lamps := _flat(raw.get("lamps", []))
	for p in lamps:
		add_post(p, 0.16)
	for a in raw.get("areas", []):
		if a[0] != "water":
			continue
		var ring := _flat(a[1])
		if ring.size() < 3:
			continue
		var r := Rect2(ring[0], Vector2.ZERO)
		var lo := INF
		for p in ring:
			r = r.expand(p)
			lo = minf(lo, ground(p.x, p.y))
		water_rings.append(ring)
		water_rects.append(r)
		water_level.append(lo - 0.9) # well below the dykes and the tracks along them

func add_post(p: Vector2, radius: float) -> void:
	var ck := _cell_key(int(floor(p.x / BCELL)), int(floor(p.y / BCELL)))
	if not _post_cells.has(ck):
		_post_cells[ck] = PackedVector3Array()
	_post_cells[ck].append(Vector3(p.x, p.y, radius))

## Add a solid wall segment to the spatial hash. Hedges use a wider collision radius than panels.
func add_wall(a: Vector2, b: Vector2, half_thickness: float) -> void:
	var lo := a.min(b) - Vector2.ONE * half_thickness
	var hi := a.max(b) + Vector2.ONE * half_thickness
	for cx in range(int(floor(lo.x / BCELL)), int(floor(hi.x / BCELL)) + 1):
		for cy in range(int(floor(lo.y / BCELL)), int(floor(hi.y / BCELL)) + 1):
			var ck := _cell_key(cx, cy)
			if not _wall_cells.has(ck):
				_wall_cells[ck] = PackedFloat32Array()
			_wall_cells[ck].append_array(PackedFloat32Array([a.x, a.y, b.x, b.y, half_thickness]))

## Wall segments in the cells overlapping a circle around p. A wall can occur in several cells.
func walls_near(p: Vector2, r: float) -> Array[PackedFloat32Array]:
	var out: Array[PackedFloat32Array] = []
	var seen := {}
	for cx in range(int(floor((p.x - r) / BCELL)), int(floor((p.x + r) / BCELL)) + 1):
		for cy in range(int(floor((p.y - r) / BCELL)), int(floor((p.y + r) / BCELL)) + 1):
			var ck := _cell_key(cx, cy)
			if not _wall_cells.has(ck):
				continue
			var walls: PackedFloat32Array = _wall_cells[ck]
			for k in range(0, walls.size(), 5):
				var key := "%0.1f,%0.1f,%0.1f,%0.1f" % [walls[k], walls[k + 1], walls[k + 2], walls[k + 3]]
				if seen.has(key):
					continue
				seen[key] = true
				var wall := PackedFloat32Array([walls[k], walls[k + 1], walls[k + 2], walls[k + 3], walls[k + 4]])
				if Geometry2D.get_closest_point_to_segment(p, Vector2(wall[0], wall[1]), Vector2(wall[2], wall[3])).distance_to(p) < r + wall[4]:
					out.append(wall)
	return out

## Building ids whose box overlaps the circle.
func buildings_near(p: Vector2, r: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var seen := {}
	for cx in range(int(floor((p.x - r) / BCELL)), int(floor((p.x + r) / BCELL)) + 1):
		for cy in range(int(floor((p.y - r) / BCELL)), int(floor((p.y + r) / BCELL)) + 1):
			var ck := _cell_key(cx, cy)
			if not _bld_cells.has(ck):
				continue
			for bi in _bld_cells[ck]:
				if not seen.has(bi) and bld_rect[bi].grow(r).has_point(p):
					seen[bi] = true
					out.append(bi)
	return out

func posts_near(p: Vector2, r: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for cx in range(int(floor((p.x - r) / BCELL)), int(floor((p.x + r) / BCELL)) + 1):
		for cy in range(int(floor((p.y - r) / BCELL)), int(floor((p.y + r) / BCELL)) + 1):
			var ck := _cell_key(cx, cy)
			if _post_cells.has(ck):
				for v in _post_cells[ck]:
					if Vector2(v.x, v.y).distance_squared_to(p) < (r + v.z) * (r + v.z):
						out.append(v)
	return out

func inside_building(p: Vector2) -> bool:
	for bi in buildings_near(p, 0.0):
		if Geometry2D.is_point_in_polygon(p, bld_rings[bi]):
			return true
	return false

## The water surface height if p is in a pond, lake or river area, else NAN.
func water_at(p: Vector2) -> float:
	for k in water_rings.size():
		if water_rects[k].has_point(p) and Geometry2D.is_point_in_polygon(p, water_rings[k]):
			return water_level[k]
	return NAN

## Physics surface under a point given the road found there ({} off road).
func surface_of(hit: Dictionary) -> int:
	if hit.is_empty():
		return Physics.SURF_GRASS
	if absf(float(hit.dist)) > float(hit.half) + 0.25:
		return Physics.SURF_GRASS
	match int(hit.surface):
		2: return Physics.SURF_GRAVEL
		1: return Physics.SURF_ASPHALT
	return Physics.SURF_TRACK
