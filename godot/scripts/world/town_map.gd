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
const BED_STEP := 10.0 ## metres: the drawn terrain mesh's vertex spacing (TownBuilder), which the car rides on
const POND_DEPTH := 1.4 ## m: the terrain sinks this far below a pond's surface
const WATER_DROP := 0.9 ## m: a pond's surface lies this far under the ground it is drawn on (water_surface)
const BANK_SLOPE := 0.25 ## m down per m across a pond's bank (_build_bed_mask)
const BANK_HOLD := 3.0 ## m beyond a road's edge (or its embankment's foot) where the ground is not sunk for water
const EMBANKMENT := 1.5 ## horizontal metres per metre of height of a raised road's earth embankment
const PIER_R := 0.8 ## m: collision radius of a bridge pier (the drawn pier is 1.4 m square)
const PIER_SPACING := 22.0 ## m along a bridge between piers
const RAIL_HALF := 2.4 ## m: half the width of the ballast bed a railway runs on, with its kerb
const TUNNEL_HEADROOM := 4.4 ## m: free height under a railway deck over a street (the bore)
const TUNNEL_VERGE := 1.6 ## m: an underpass's bore is this much wider than the carriageway on each side ...
const TUNNEL_MIN_HALF := 4.0 ## m: ... and at least this wide either side of the street's centre (8 m: two cars and room)
const TUNNEL_AXIS := 12.0 ## m either side of the crossing that the bore's line follows the street over
const TUNNEL_MAX_HALF := 9.0 ## m: the most a cut widens for a street wandering through it
const WING_SOLID := 0.5 ## m: a wing wall at least this high over the ground stops the car (TownMap walls)
const KERB_H := 0.13 ## m: height of a kerb; the pavement behind it is flat at this height (TownBuilder draws the same)
const PAVEMENT_W := 1.5 ## m: width of the pavement beyond a road's edge
const ROAD_LIFT := 0.14 ## m: a street's drawn surface stands this far over the ground (plus ROAD_RANK_LIFT per rank), clear of the terrain mesh
const ROAD_RANK_LIFT := 0.006 ## m per road rank: the bigger road's surface wins at a junction
const PAVEMENT_TOP := ROAD_LIFT + 0.03 + KERB_H ## m over the ground: the drawn pavement's flat top (TownBuilder)
const LIFT_RAMP := 0.6 ## m: the car's ride rises from the ground to a street's drawn surface over this far inside its edge
const PAVE_GAP := 2.5 ## m: pavements stop this far short of a junction's edge
const PARAPET := 0.4 ## m: a bridge deck holds a car up this far beyond its edge (the parapet), then it drops off

var key := ""
var name := ""
var raw: Dictionary = {}
var bounds := Rect2() ## the drivable area
var extent := Rect2() ## everything that is drawn
var boundary := PackedVector2Array() ## the town limit
var play := PackedVector2Array() ## the playable area's outline (not a rectangle); a hard stop sits just inside it
var play_inset := PackedVector2Array() ## play, pulled in by EDGE_INSET
var closures: Array = [] ## road ends at the edge: [x, y, heading out, width m, 1 for the S1 turn-around]
const EDGE_INSET := 1.5 ## m: how far inside the outline the car stops

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
var road_gravel := PackedByteArray() ## 1: an unpaved road of loose stone (OSM surface gravel, fine_gravel, compacted), else dirt
var road_oneway := PackedByteArray()
var road_lanes := PackedInt32Array()
var road_limit := PackedFloat32Array() ## km/h
var road_bridge := PackedByteArray()
var road_len := PackedFloat32Array()
var road_pave := PackedByteArray() ## 1: the street has kerbs and pavements (in town, among buildings)
var pave_polys: Array[PackedVector2Array] = [] ## the pavements: merged, non-overlapping, carriageways and junction gaps cut out
var _pave_rects: Array[Rect2] = []
var _pave_cells := {} ## int cell -> PackedInt32Array of pave_polys indices
var _road_polys := {} ## road -> its carriageway outline polygons (while pavements are built)
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
var bld_faces := {} ## bi -> the walls drawn where they are not the OSM ring (TownBuilder: set_building_faces)
var _bld_cells := {} ## int cell -> PackedInt32Array of building ids
var _post_cells := {} ## int cell -> PackedVector3Array (x, y, radius) of trees, lamps and posts
var _parapet_cells := {} ## int cell -> PackedFloat32Array (ax, ay, bx, by, half thickness, deck height above sea level)
var _pier_cells := {} ## int cell -> PackedFloat32Array (x, y, radius, top height above sea level)
var piers: Array = [] ## [Vector2 position, top height above sea level] of every bridge pier, same ones TownBuilder draws
var _pier_keys := {} ## road * 100000 + segment -> true where TownBuilder draws a pier
var tunnels: Array = [] ## underpasses through railway embankments, see _load_tunnels()
var rail_pts: Array[PackedVector2Array] = []
var _rail_cells := {} ## int cell -> PackedInt32Array of line * 100000 + point index
var _wall_cells := {} ## int cell -> PackedFloat32Array (ax, ay, bx, by, half thickness)
var water_rings: Array[PackedVector2Array] = []
var water_rects: Array[Rect2] = []
var water_level := PackedFloat32Array()
var bed_mask := {} ## terrain vertex index (row-major over extent at BED_STEP) -> water surface height; ponds sink the ground
var trains: Array = [] ## the train's cars: [Vector2 centre, heading (rad, map frame), half length, half width, height,
## Vector2 velocity (m/s, map frame)]
var train_hit := 0.0 ## closing speed of the hardest knock on the train's leading cab this tick (FreeCar sets it, Train reads it)
var booms: Array = [] ## level crossing booms: [Vector2 hinge, Vector2 tip, bool closed, float angle
## (rad, 0 = down)]; TownBuilder swings them
var signal_t := 0.0 ## s: the traffic signals' clock (Traffic.step advances it, TownBuilder.update_signals shows it)
var _signal_heads: Array = [] ## see signal_heads()
var _signal_heads_built := false
var areas: Array = []
var places: Array = []
var spots := {}
var in_town_cache := {}

static var _cache := {}

## cache_dir: a folder to keep a snapshot of the loaded map in (the open world passes TownBuilder.MESH_CACHE_DIR). Reading
## it takes a fraction of the time the 15 MB bake needs to parse and index (see _snapshot_path for what invalidates it).
static func load_map(map_key: String, cache_dir := "") -> TownMap:
	if not _cache.has(map_key):
		var m := TownMap.new()
		if cache_dir == "" or not m._load_snapshot(map_key, cache_dir):
			if not m._load(map_key):
				return null
			if cache_dir != "":
				m._save_snapshot(cache_dir)
		_cache[map_key] = m
	return _cache[map_key]

const CODE_HASH := preload("res://scripts/world/code_hash.gd")
const SNAPSHOT_VERSION := "1"

## Where the snapshot of map `map_key` lives: its name carries what it was made from, the bake's MD5, the code that
## derives the map's state from it (_from_raw and what that names) and the engine version. "" if the bake is missing.
func _snapshot_path(map_key: String, dir: String) -> String:
	var json := "res://data/world/%s.json" % map_key
	if not FileAccess.file_exists(json):
		return ""
	var parts := PackedStringArray([SNAPSHOT_VERSION, map_key, FileAccess.get_md5(json), str(Engine.get_version_info()),
		CODE_HASH.closure("res://scripts/world/town_map.gd", ["_from_raw"], "res://scripts/world/town_map.gd")])
	if not OS.has_feature("editor"): # an exported game has no script sources to fingerprint: its build stands in
		parts.append(str(ProjectSettings.get_setting("application/config/version", "")))
		parts.append(str(FileAccess.get_modified_time(OS.get_executable_path())))
	return "%s/map_%s_%s.bin" % [dir, map_key, "|".join(parts).md5_text().substr(0, 16)]

func _snapshot_vars() -> Array[String]:
	var names: Array[String] = []
	for p in get_property_list():
		if int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(p.name)
	return names

## Fills every member from the snapshot of this bake; false if there is none (or it does not read back).
func _load_snapshot(map_key: String, dir: String) -> bool:
	var path := _snapshot_path(map_key, dir)
	if path == "" or not FileAccess.file_exists(path):
		return false
	var state = bytes_to_var(FileAccess.get_file_as_bytes(path))
	if not state is Dictionary or not (state as Dictionary).has("raw") or (state as Dictionary).get("key", "") != map_key:
		return false
	for n in _snapshot_vars():
		if (state as Dictionary).has(n):
			set(n, (state as Dictionary)[n])
	return true

## Keeps the loaded map's members (all of them are plain data) for the next run, and drops older snapshots of this map.
func _save_snapshot(dir: String) -> void:
	var path := _snapshot_path(key, dir)
	if path == "":
		return
	for sec in raw:
		section_hash(sec) # the mesh cache's stamps read these; computing them once here keeps warm starts from hashing 17 MB
	var state := {}
	for n in _snapshot_vars():
		state[n] = get(n)
	DirAccess.make_dir_recursive_absolute(dir)
	var tmp := "%s.tmp%d" % [path, OS.get_process_id()]
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(var_to_bytes(state))
	f.close()
	if DirAccess.rename_absolute(tmp, path) != OK:
		DirAccess.remove_absolute(tmp)
		return
	for fname in DirAccess.get_files_at(dir):
		if fname.begins_with("map_%s_" % key) and ".tmp" not in fname and dir.path_join(fname) != path:
			DirAccess.remove_absolute(dir.path_join(fname))

func _load(map_key: String) -> bool:
	key = map_key
	var path := "res://data/world/%s.json" % map_key
	if not FileAccess.file_exists(path):
		push_error("Open world map %s is missing (run tools/build_open_world.py)" % path)
		return false
	raw = JSON.parse_string(FileAccess.get_file_as_string(path))
	if raw == null or raw.is_empty():
		return false
	return _from_raw()

## Everything derived from `raw` (the parsed bake): the spatial hashes, roads, pavements, obstacles and so on.
func _from_raw() -> bool:
	name = raw.get("name", key)
	var b: Array = raw.bounds
	bounds = Rect2(b[0], b[1], b[2] - b[0], b[3] - b[1])
	var e: Array = raw.extent
	extent = Rect2(e[0], e[1], e[2] - e[0], e[3] - e[1])
	boundary = _flat(raw.get("boundary", []))
	play = _flat(raw.get("play", []))
	closures = raw.get("closures", [])
	if play.size() >= 3:
		var inset := Geometry2D.offset_polygon(play, -EDGE_INSET)
		play_inset = inset[0] if not inset.is_empty() else play
	var t: Dictionary = raw.terrain
	tx0 = t.x0
	ty0 = t.y0
	tstep = t.step
	tnx = int(t.nx)
	tny = int(t.ny)
	th = PackedFloat32Array(t.h)
	_load_roads()
	_load_buildings()
	_build_pavements()
	_load_obstacles()
	_load_rails()
	_load_tunnels()
	_load_rail_banks()
	_add_tunnel_walls()
	_build_bridge_solids()
	areas = raw.get("areas", [])
	places = raw.get("places", [])
	spots = raw.get("spots", {})
	return true

var _section_hashes := {}

## MD5 of one section of the baked map as parsed ("terrain", "roads", ...), for the open world's mesh cache stamps: a
## cached step is valid while the sections it reads are unchanged.
func section_hash(section: String) -> String:
	if not _section_hashes.has(section):
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_MD5)
		ctx.update(var_to_bytes(raw.get(section)))
		_section_hashes[section] = ctx.finish().hex_encode()
	return _section_hashes[section]

## Whether p lies inside poly (even-odd, a horizontal ray in double precision). Not Geometry2D.is_point_in_polygon: it
## casts its ray to one far point, so along the line from that point through each vertex (fractions of a millimetre
## wide, but crossing the whole map) it miscounts. in_play() said "outside" there, 2 km from the edge, and edge_push()
## threw the car at the outline: an invisible wall about once a minute and a half of driving (_invisible_wall_probe.gd).
static func inside(p: Vector2, poly: PackedVector2Array) -> bool:
	var x: float = p.x
	var y: float = p.y
	var odd := false
	var n := poly.size()
	var j := n - 1
	for i in n:
		var yi: float = poly[i].y
		var yj: float = poly[j].y
		if (yi > y) != (yj > y):
			var xi: float = poly[i].x
			if x < xi + (y - yi) * (float(poly[j].x) - xi) / (yj - yi):
				odd = not odd
		j = i
	return odd

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
		road_gravel.append(int(r.get("g", 0)))
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
		if int(r.get("b", 0)) != 1 and r.has("z"): # decks_at reaches an embankment's foot
			var zmax := 0.0
			for zv in r.z:
				zmax = maxf(zmax, float(zv))
			half = maxf(half, float(r.w) * 0.5 + zmax * EMBANKMENT + CONE_REACH) # (+: a cone's foot downhill)
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
## Which streets have pavements, and the pavements themselves: one band per run of street between junctions,
## with every carriageway and every earlier pavement cut out, so no two pavement shapes overlap. TownBuilder
## draws these same shapes and kerb_at() answers from them.
func _build_pavements() -> void:
	var node_width := {}
	var node_roads := {}
	for ri in road_pts.size():
		for m in road_marks[ri]:
			var nid := str(m[1])
			node_width[nid] = maxf(float(node_width.get(nid, 0.0)), road_w[ri])
			node_roads[nid] = int(node_roads.get(nid, 0)) + 1
	var joins := way_joins()
	road_pave.resize(road_pts.size())
	pave_polys.clear()
	_pave_rects.clear()
	_pave_cells.clear()
	_road_polys.clear()
	for ri in road_pts.size():
		var pts := road_pts[ri]
		var n := pts.size()
		road_pave[ri] = 0
		if n < 2 or not _has_pavement(ri, pts[n / 2]):
			continue
		road_pave[ri] = 1
		var s := PackedFloat32Array()
		s.resize(n)
		for i in range(1, n):
			s[i] = s[i - 1] + pts[i].distance_to(pts[i - 1])
		var jd := PackedFloat32Array()
		jd.resize(n)
		jd.fill(INF)
		for m in road_marks[ri]:
			var nid := str(m[1])
			if int(node_roads.get(nid, 0)) >= 2 and not joins.has(nid): # a way joined to the next runs on unbroken
				var half_j := float(node_width[nid]) * 0.5
				for i in n:
					jd[i] = minf(jd[i], absf(s[i] - s[int(m[0])]) - half_j)
		var i := 0
		while i < n:
			if jd[i] < PAVE_GAP:
				i += 1
				continue
			var j := i
			while j + 1 < n and jd[j + 1] >= PAVE_GAP:
				j += 1
			if j > i:
				_add_pavement_run(ri, pts.slice(i, j + 1), i)
			i = j + 1
	_road_polys.clear()

func _carriageway(ri: int) -> Array:
	if not _road_polys.has(ri):
		if _tapered(ri):
			_road_polys[ri] = [_ribbon_poly(ri, 0, road_pts[ri].size() - 1, 0.0)]
		else:
			_road_polys[ri] = Geometry2D.offset_polyline(road_pts[ri], road_w[ri] * 0.5, Geometry2D.JOIN_ROUND, Geometry2D.END_BUTT)
	return _road_polys[ri]

## Half width of street ri at each of its points: road_w / 2, narrower past building corners (the baker's 'hw'), and
## where it joins a narrower way end to end
## (TownMap.way_joins), where it tapers to that way's width over its last 12-40 m (a lane drop, a widening for a turn
## lane) instead of stepping. TownBuilder.ribbon draws it, the kerbs follow it and road_at() rides it.
var _halves := {}
func road_halves(ri: int) -> PackedFloat32Array:
	if _halves.has(ri):
		return _halves[ri]
	var pts := road_pts[ri]
	var n := pts.size()
	var half := road_w[ri] * 0.5
	var halves := PackedFloat32Array()
	halves.resize(n)
	halves.fill(half)
	# narrowed past the corners of the buildings beside it (the baker's 'hw')
	var hw: Array = raw.roads[ri].get("hw", []) if raw.has("roads") and ri < raw.roads.size() else []
	if hw.size() == n:
		for k in n:
			halves[k] = minf(halves[k], float(hw[k]))
	for e in 2:
		var end_i := 0 if e == 0 else n - 1
		var other := -1
		for m in road_marks[ri]:
			if int(m[0]) == end_i:
				for j: Array in way_joins().get(str(m[1]), []):
					if not (int(j[0]) == ri and int(j[1]) == end_i):
						other = int(j[0])
		if other < 0 or other == ri:
			continue
		var oh := road_w[other] * 0.5
		# (the other way's own end may be narrowed past a building: meet that)
		var ohw: Array = raw.roads[other].get("hw", []) if raw.has("roads") else []
		if not ohw.is_empty():
			for m in road_marks[ri]:
				if int(m[0]) == end_i:
					var oe := road_pts[other]
					var near_end := 0 if oe[0].distance_to(pts[end_i]) < oe[oe.size() - 1].distance_to(pts[end_i]) else oe.size() - 1
					oh = minf(oh, float(ohw[near_end]))
		if oh > halves[end_i] - 0.15:
			continue
		var taper := clampf(12.0 * (half - oh), 12.0, 40.0)
		var run := 0.0
		for k in n:
			var i := k if e == 0 else n - 1 - k
			if k > 0:
				run += pts[i].distance_to(pts[i - 1 if e == 0 else i + 1])
			if run > taper:
				break
			halves[i] = minf(halves[i], lerpf(oh, half, smoothstep(0.0, taper, run)))
	_halves[ri] = halves
	return halves

func _tapered(ri: int) -> bool:
	for h in road_halves(ri):
		if h < road_w[ri] * 0.5 - 0.01:
			return true
	return false

## Half width of street ri at segment i, t of the way to i + 1.
func half_at(ri: int, i: int, t: float) -> float:
	var h := road_halves(ri)
	return lerpf(h[i], h[mini(i + 1, h.size() - 1)], t)

## The outline of street ri from point i0 to i1 at its (tapered) width plus `grow`, as a polygon (its ends square).
func _ribbon_poly(ri: int, i0: int, i1: int, grow: float) -> PackedVector2Array:
	var pts := road_pts[ri]
	var h := road_halves(ri)
	var l := PackedVector2Array()
	var r := PackedVector2Array()
	for i in range(i0, i1 + 1):
		var t := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var nrm := Vector2(-t.y, t.x)
		l.append(pts[i] - nrm * (h[i] + grow))
		r.append(pts[i] + nrm * (h[i] + grow))
	r.reverse()
	l.append_array(r)
	return l

static func _bounds_of(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for q in poly:
		r = r.expand(q)
	return r

static func _area_of(poly: PackedVector2Array) -> float:
	var a := 0.0
	for k in poly.size():
		var p := poly[k]
		var q := poly[(k + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5

## Clips every polygon in `pieces` against `cut`, dropping the holes the result may carry.
static func _subtract(pieces: Array, cut: PackedVector2Array) -> Array:
	var out := []
	for pc in pieces:
		var res := Geometry2D.clip_polygons(pc, cut)
		for r in res:
			if not Geometry2D.is_polygon_clockwise(r):
				out.append(r)
	return out

## Drops the zero-width spikes and repeated points clipping can leave in an outline (an edge out and straight back):
## they triangulate into hair-thin slivers that flicker, and would get kerb faces of their own.
static func _despike(poly: PackedVector2Array) -> PackedVector2Array:
	var out := poly.duplicate()
	var changed := true
	while changed and out.size() >= 3:
		changed = false
		var k := 0
		while k < out.size() and out.size() >= 3:
			var a := out[(k - 1 + out.size()) % out.size()]
			var b := out[k]
			var c := out[(k + 1) % out.size()]
			var ab := b - a
			var bc := c - b
			# b repeats a, or the outline doubles back on itself at b (collinear, turning ~180 degrees)
			if ab.length_squared() < 1e-6 or (absf(ab.cross(bc)) < 1e-3 * maxf(ab.length() * bc.length(), 1e-6) and ab.dot(bc) < 0.0):
				out.remove_at(k)
				changed = true
			else:
				k += 1
	return out

func _add_pavement_run(ri: int, run: PackedVector2Array, i0 := 0) -> void:
	var half := road_w[ri] * 0.5
	var pieces: Array = []
	# the carriageway cut overshoots the run's ends (square caps): a butt cap would end exactly on the band's own
	# end and leave a zero-width slit across the road, which draws as a flickering sliver at every junction
	var inner := Geometry2D.offset_polyline(run, half, Geometry2D.JOIN_ROUND, Geometry2D.END_SQUARE)
	if _tapered(ri):
		# where the street tapers into a narrower way the kerb follows its edge (the pavement widens behind it)
		var h := road_halves(ri)
		var lo := INF
		for k in range(i0, i0 + run.size()):
			lo = minf(lo, h[k])
		if lo < half - 0.01:
			var ext := run.duplicate()
			if ext.size() >= 2:
				ext[0] = ext[0] + (ext[0] - ext[1]).normalized() * half
				ext[ext.size() - 1] = ext[ext.size() - 1] + (ext[ext.size() - 1] - ext[ext.size() - 2]).normalized() * half
			var poly := _ribbon_poly(ri, i0, i0 + run.size() - 1, 0.0)
			var sq := Geometry2D.offset_polyline(ext, 0.05, Geometry2D.JOIN_ROUND, Geometry2D.END_BUTT) # the square overshoot
			inner = Geometry2D.merge_polygons(poly, sq[0]) if not sq.is_empty() else [poly]
	for o in Geometry2D.offset_polyline(run, half + PAVEMENT_W, Geometry2D.JOIN_ROUND, Geometry2D.END_BUTT):
		if Geometry2D.is_polygon_clockwise(o):
			continue
		var cur := [o]
		for ip in inner:
			cur = _subtract(cur, ip)
		pieces.append_array(cur)
	if pieces.is_empty():
		return
	var rect := Rect2(run[0], Vector2.ZERO)
	for q in run:
		rect = rect.expand(q)
	rect = rect.grow(half + PAVEMENT_W + 0.5)
	# every other carriageway near the run (not the raised ones: a bridge does not cut the pavement under it)
	var seen := {}
	for cx in range(int(floor(rect.position.x / CELL)), int(floor(rect.end.x / CELL)) + 1):
		for cy in range(int(floor(rect.position.y / CELL)), int(floor(rect.end.y / CELL)) + 1):
			var ck := _cell_key(cx, cy)
			if not _seg_cells.has(ck):
				continue
			for sid in _seg_cells[ck]:
				var r2 := _seg_road[sid]
				if r2 == ri or seen.has(r2):
					continue
				seen[r2] = true
				if road_bridge[r2] or not road_z[r2].is_empty():
					continue
				for cp in _carriageway(r2):
					if _bounds_of(cp).intersects(rect):
						pieces = _subtract(pieces, cp)
	# pavements already placed: they own what they cover
	var owners := {}
	for cx in range(int(floor(rect.position.x / CELL)), int(floor(rect.end.x / CELL)) + 1):
		for cy in range(int(floor(rect.position.y / CELL)), int(floor(rect.end.y / CELL)) + 1):
			var ck := _cell_key(cx, cy)
			if _pave_cells.has(ck):
				for pid in _pave_cells[ck]:
					owners[pid] = true
	for pid in owners:
		if _pave_rects[pid].intersects(rect):
			pieces = _subtract(pieces, pave_polys[pid])
	for raw_pc: PackedVector2Array in pieces:
		var pc := _despike(raw_pc)
		if pc.size() < 3 or absf(_area_of(pc)) < 0.3 or Geometry2D.triangulate_polygon(pc).is_empty():
			continue
		var id := pave_polys.size()
		var pr := _bounds_of(pc)
		pave_polys.append(pc)
		_pave_rects.append(pr)
		for cx in range(int(floor(pr.position.x / CELL)), int(floor(pr.end.x / CELL)) + 1):
			for cy in range(int(floor(pr.position.y / CELL)), int(floor(pr.end.y / CELL)) + 1):
				var ck2 := _cell_key(cx, cy)
				if not _pave_cells.has(ck2):
					_pave_cells[ck2] = PackedInt32Array()
				_pave_cells[ck2].append(id)

func _has_pavement(ri: int, mid: Vector2) -> bool:
	if not road_kind[ri] in ["primary", "secondary", "tertiary", "residential", "unclassified", "living_street"]:
		return false
	if road_bridge[ri] or not road_z[ri].is_empty():
		return false
	if not in_town(mid):
		return false
	return not buildings_near(mid, 45.0).is_empty()

## Height of street ri's drawn surface over the ground (and its deck): what the tyres stand on, and what TownBuilder draws.
## The nodes where one way simply continues as the next (OSM splits a street wherever a tag changes): exactly two road
## ends meet there and nothing else. Not junctions: TownBuilder runs the ribbon, its markings and its kerbs straight
## through them. node id -> [[road, point index], [road, point index]] (a closed way joins itself).
var _way_joins := {}
var _way_joins_built := false
func way_joins() -> Dictionary:
	if _way_joins_built:
		return _way_joins
	_way_joins_built = true
	var at := {}
	for ri in road_pts.size():
		for m in road_marks[ri]:
			var nid := str(m[1])
			if not at.has(nid):
				at[nid] = []
			at[nid].append([ri, int(m[0])])
	for nid in at:
		var ends: Array = at[nid]
		if ends.size() != 2:
			continue
		var ok := true
		for e: Array in ends:
			var last := road_pts[int(e[0])].size() - 1
			if int(e[1]) != 0 and int(e[1]) != last:
				ok = false
		if ok and ends[0] != ends[1]:
			_way_joins[nid] = ends
	return _way_joins

## The point just beyond end `idx` (0 or the last) of road ri along the way joined to it there, or Vector2.INF: what
## the ribbon's direction at that end is taken from, so the two ways' edges meet.
func joined_beyond(ri: int, idx: int) -> Vector2:
	for m in road_marks[ri]:
		if int(m[0]) != idx:
			continue
		var j: Array = way_joins().get(str(m[1]), [])
		for e: Array in j:
			if int(e[0]) == ri and int(e[1]) == idx:
				continue
			var other := road_pts[int(e[0])]
			if other.size() < 2:
				return Vector2.INF
			return other[1] if int(e[1]) == 0 else other[other.size() - 2]
	return Vector2.INF

func road_lift(ri: int) -> float:
	return ROAD_LIFT + road_rank[ri] * ROAD_RANK_LIFT

## How much of a street's lift the car's ride takes `inside` metres in from the street's edge (half its width minus
## the distance from its centreline): none at the very edge, all of it LIFT_RAMP in, so the car meets no step where
## it drives on or off the tarmac.
func lift_share(inside: float) -> float:
	return smoothstep(0.0, LIFT_RAMP, inside)

## A street on the ground stands ROAD_LIFT proud of it on a gravel shoulder SHOULDER wide (TownBuilder draws it, FreeCar
## rides down it), so the tarmac's edge reads as an edge and not as paint on the grass.
const SHOULDER := 0.9
const SHOULDER_DROP := 0.04 ## m under the ground at the shoulder's foot, so the grass covers its end

## Potholes: a repeating POT_N x POT_N tile of POT_CELL m cells, each with a rank (a hole where it is under
## POT_SHARE x road_wear), a centre and a radius. The car (pothole()) and the road shader (town_road.gdshader, the
## "potholes" texture) read the same bytes, so the hole the wheel drops into is the one drawn.
const POT_CELL := 3.0
const POT_N := 128
const POT_SHARE := 0.12
const POT_DEPTH := 0.05
static var _pot_bytes := PackedByteArray()
static var _pot_texture: ImageTexture

static func pothole_bytes() -> PackedByteArray:
	if _pot_bytes.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = 900
		_pot_bytes.resize(POT_N * POT_N * 4)
		for k in _pot_bytes.size():
			_pot_bytes[k] = rng.randi_range(0, 255)
	return _pot_bytes

static func pothole_texture() -> ImageTexture:
	if _pot_texture == null:
		_pot_texture = ImageTexture.create_from_image(Image.create_from_data(POT_N, POT_N, false, Image.FORMAT_RGBA8, pothole_bytes()))
	return _pot_texture

## How pot-holed street ri is, 0..1: the back streets, lanes and service roads most, the wider local streets a little,
## the main roads not at all (the same classes as TownBuilder._style 0 and 1).
func road_wear(ri: int) -> float:
	if ri >= road_surface.size() or ri >= road_kind.size() or ri >= road_oneway.size() or road_surface[ri] != 0:
		return 0.0
	var kind := road_kind[ri]
	if kind.begins_with("motorway") or kind == "trunk" or kind in ["primary", "secondary", "tertiary"]:
		return 0.0
	if kind in ["unclassified", "residential"] and road_w[ri] >= 5.0 and road_oneway[ri] == 0:
		return 0.4
	return 1.0

## Depth (m) of the pothole under a map point, 0 on sound tarmac and off the streets.
func pothole(x: float, y: float) -> float:
	var b := pothole_bytes()
	var cx := floorf(x / POT_CELL)
	var cy := floorf(y / POT_CELL)
	var k := (posmod(int(cy), POT_N) * POT_N + posmod(int(cx), POT_N)) * 4
	var rank := b[k] / 255.0
	if rank >= POT_SHARE:
		return 0.0
	var c := Vector2(cx + 0.25 + b[k + 1] / 255.0 * 0.5, cy + 0.25 + b[k + 2] / 255.0 * 0.5) * POT_CELL
	var r := 0.3 + 0.3 * b[k + 3] / 255.0
	var shape := 1.0 - smoothstep(r * 0.55, r, Vector2(x, y).distance_to(c))
	if shape <= 0.0:
		return 0.0
	var hit := road_at(x, y)
	if hit.is_empty() or float(hit.deck) > 0.05 or rank >= POT_SHARE * road_wear(int(hit.road)):
		return 0.0
	return POT_DEPTH * shape

## Height over the ground of a pavement's top when (x, y) is on one, else 0 (the kerb is KERB_H above the street).
func pave_top_at(x: float, y: float) -> float:
	return PAVEMENT_TOP if kerb_at(x, y) > 0.0 else 0.0

## Kerb height (KERB_H) when (x, y) is on a pavement, else 0.
func kerb_at(x: float, y: float) -> float:
	var ck := _cell_key(int(floor(x / CELL)), int(floor(y / CELL)))
	if not _pave_cells.has(ck):
		return 0.0
	var p := Vector2(x, y)
	for pid in _pave_cells[ck]:
		if _pave_rects[pid].has_point(p) and inside(p, pave_polys[pid]):
			return KERB_H
	return 0.0

## A raised deck is level across (a bridge or an embankment's top does not lean with the hillside under it): its height
## over the ground at p, beside the centreline point q where the deck is `deck` over the ground. Low ramps (under
## DECK_LEVEL_FROM) still follow the ground across, and DECK_LEVEL_TO up they are level; TownBuilder draws the same.
const DECK_LEVEL_FROM := 0.3
const DECK_LEVEL_TO := 1.5
## A street with no kerbs leans across by at most CROSS_MAX (a track along a hillside): its downhill edge is raised on
## fill until it does (the uphill edge stays on the ground, so nothing is cut into the hill). TownBuilder.ribbon draws
## the same; level_extra() is how far that raises the surface at p over the plain ground-following one.
const CROSS_MAX := 0.04
static func level_pair(gl: float, gr: float, width: float) -> Vector2:
	var cap := CROSS_MAX * width
	if gl - gr > cap:
		gr = gl - cap
	elif gr - gl > cap:
		gl = gr - cap
	return Vector2(gl, gr)

func level_extra(ri: int, p: Vector2, q: Vector2, ab: Vector2, deck: float) -> float:
	if ri < road_pave.size() and road_pave[ri] == 1:
		return 0.0
	var w := 1.0 if deck <= DECK_LEVEL_FROM else 1.0 - smoothstep(DECK_LEVEL_FROM, DECK_LEVEL_TO, deck)
	if w <= 0.0 or ab.length_squared() < 1e-8:
		return 0.0
	var n := Vector2(-ab.y, ab.x).normalized()
	var half := road_w[ri] * 0.5
	var gl := ground(q.x - n.x * half, q.y - n.y * half)
	var gr := ground(q.x + n.x * half, q.y + n.y * half)
	if absf(gl - gr) <= CROSS_MAX * 2.0 * half:
		return 0.0
	var lv := level_pair(gl, gr, 2.0 * half)
	var u := clampf(((p - q).dot(n) + half) / (2.0 * half), 0.0, 1.0)
	return (lerpf(lv.x, lv.y, u) - lerpf(gl, gr, u)) * w
func deck_across(deck: float, p: Vector2, q: Vector2) -> float:
	if deck <= DECK_LEVEL_FROM:
		return deck
	return deck + smoothstep(DECK_LEVEL_FROM, DECK_LEVEL_TO, deck) * (ground(q.x, q.y) - ground(p.x, p.y))

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
		half = half_at(ri, i, t)
		if d > half + reach:
			continue
		var deck := deck_across(deck_at(ri, i, t), p, q)
		var lv := level_extra(ri, p, q, ab, deck)
		var score := d * 0.02 - road_rank[ri] * 0.001
		if z_ref > -INF:
			var h := ground(x, y) + deck + lv + road_lift(ri) # the surface's height, as "height" below and the car's z have it
			score += absf(h - z_ref)
		else:
			score += deck * 10.0
		if score < best_score:
			best_score = score
			var side := signf(ab.x * (p.y - a.y) - ab.y * (p.x - a.x))
			best = {"road": ri, "i": i, "t": t, "dist": d * side, "half": half, "deck": deck,
				"surface": road_surface[ri], "gravel": road_gravel[ri], "level": lv}
	if not best.is_empty():
		best["height"] = ground(x, y) + float(best.deck) + float(best.level) + road_lift(int(best.road))
	return best

## Every road deck under a map point (for the car's vertical contact: it may be on a bridge or under it):
## [road, deck height over ground, distance beyond the edge (< 0 inside), direction, offset from the centreline, bridge
## (or a deck drawn on piers), beyond the road's end, on its first or last segment].
func decks_at(x: float, y: float, reach: float) -> Array:
	var ck := _cell_key(int(floor(x / CELL)), int(floor(y / CELL)))
	var out := []
	if not _seg_cells.has(ck):
		return out
	var p := Vector2(x, y)
	var seen := {} # road * 2 + solid -> index in out: one deck per road and kind, from its nearest segment
	for sid in _seg_cells[ck]:
		var ri := _seg_road[sid]
		if road_z[ri].is_empty():
			continue
		var i := _seg_i[sid]
		var pts := road_pts[ri]
		var a := pts[i]
		var ab := pts[i + 1] - a
		var l2 := ab.length_squared()
		var tr := 0.0 if l2 < 1e-6 else (p - a).dot(ab) / l2
		var t := clampf(tr, 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		# a raised road that is no bridge stands on an earth embankment sloping 1:EMBANKMENT down to the ground (as
		# TownBuilder draws it): its side is a slope the car climbs, not a wall where `reach` ends
		var reach_r := reach
		# (a raised road over 4 m at both ends of the segment is drawn as a deck on piers, as a bridge is: TownBuilder)
		var solid := road_bridge[ri] != 1 and minf(road_z[ri][i], road_z[ri][i + 1]) <= 4.0
		if solid:
			reach_r = maxf(reach, maxf(road_z[ri][i], road_z[ri][i + 1]) * EMBANKMENT)
		var capped := (tr < 0.0 and i == 0) or (tr > 1.0 and i == pts.size() - 2)
		if capped and solid and has_cone(ri, 0 if tr < 0.0 else 1):
			# past a raised embankment's end its drawn cone (cone_height): a side slope, not a stub's flat run-on, out to
			# its foot (the deck is level across, so on falling ground the foot lies further out)
			capped = false
			if d <= road_w[ri] * 0.5 + reach_r + CONE_REACH:
				var dc := deck_across(deck_at(ri, i, t), p, a + ab * t)
				reach_r = maxf(reach_r, (dc + level_extra(ri, p, a + ab * t, ab, dc)) * EMBANKMENT)
		if d <= road_w[ri] * 0.5 + reach_r:
			var dk := deck_across(deck_at(ri, i, t), p, a + ab * t)
			var entry := [ri, dk + level_extra(ri, p, a + ab * t, ab, dk), d - road_w[ri] * 0.5, ab.normalized(), (p - (a + ab * t)), not solid, capped, i == 0 or i == pts.size() - 2]
			# one entry per road and kind: an embankment's slope (or the cone round its end) and the deck on piers it
			# runs on into are both there, or a car beside the abutment drops off the one into the void under the other
			var key := ri * 2 + (1 if solid else 0)
			if seen.has(key):
				if d - road_w[ri] * 0.5 < float(out[seen[key]][2]):
					out[seen[key]] = entry
			else:
				seen[key] = out.size()
				out.append(entry)
	# both kinds of one road stay only beside it: on its carriageway the nearest segment alone decides (a stale slope
	# entry from the segment before a 4 m deck held the car 0.7 m under the S1's surface)
	var by_road := {}
	for e: Array in out:
		by_road[int(e[0])] = by_road.get(int(e[0]), []) + [e]
	for r_: int in by_road:
		var es: Array = by_road[r_]
		if es.size() == 2 and minf(float(es[0][2]), float(es[1][2])) <= 0.0:
			out.erase(es[0] if float(es[0][2]) > float(es[1][2]) else es[1])
	# a raised junction (a ramp meeting a bridge's end, two embankments) is a solid pad as wide as its widest road
	# round its node: the inside of a sharp turn there is no notch down to the ground. Only off every carriageway (on
	# one, that road's own deck decides)
	var on_any := false
	for e: Array in out:
		if float(e[2]) <= 0.0 and not e[6]: # (a stub's run-on past its end is no carriageway: the pad is the node's top)
			on_any = true
	if not on_any:
		for pad: Array in raised_pads_near(p):
			var c: Vector2 = pad[0]
			var dd := p.distance_to(c) - float(pad[1])
			if dd <= maxf(reach, float(pad[2]) * EMBANKMENT):
				var ri: int = pad[3]
				var e := [ri, float(pad[2]), dd, Vector2.RIGHT, p - c, false, false, false]
				var key := ri * 2 + 1
				if seen.has(key):
					var cur: Array = out[seen[key]]
					if float(pad[2]) - maxf(dd, 0.0) / EMBANKMENT > float(cur[1]) - maxf(float(cur[2]), 0.0) / EMBANKMENT:
						out[seen[key]] = e
				else:
					seen[key] = out.size()
					out.append(e)
	# past the end of a road its last deck height only extends flat: where another road's body covers the spot
	# (a junction), that one decides, so the car never follows a stub's frozen height
	if out.size() > 1:
		var solid := out.filter(func(e: Array) -> bool: return not e[6])
		if not solid.is_empty():
			return solid
	return out

## Junction nodes standing raised (a road's deck over PAD_FROM there): [position, radius (the widest road's half
## width), deck (the highest there), that road], hashed by CELL (decks_at).
const PAD_FROM := 0.3
var _pad_cells := {}
var _pads_built := false
func raised_pads_near(p: Vector2) -> Array:
	if not _pads_built:
		_pads_built = true
		var pads := {}
		for ri in road_pts.size():
			var zs := road_z[ri]
			for m in road_marks[ri]:
				var nid := str(m[1])
				var k := int(m[0])
				var deck := zs[k] if not zs.is_empty() else 0.0
				var cur: Array = pads.get(nid, [road_pts[ri][k], 0.0, 0.0, -1, 0])
				cur[1] = maxf(float(cur[1]), road_w[ri] * 0.5 + 0.05)
				if deck > float(cur[2]):
					cur[2] = deck
					cur[3] = ri
				cur[4] = int(cur[4]) + 1
				pads[nid] = cur
		for nid in pads:
			var pad: Array = pads[nid]
			if float(pad[2]) <= PAD_FROM or float(pad[2]) > 4.0 or int(pad[4]) < 2:
				continue # (over 4 m the roads stand on piers, TownBuilder draws no earth under them)
			var c: Vector2 = pad[0]
			var r := float(pad[1]) + DRIVE_REACH + float(pad[2]) * EMBANKMENT
			for cx in range(int(floor((c.x - r) / CELL)), int(floor((c.x + r) / CELL)) + 1):
				for cy in range(int(floor((c.y - r) / CELL)), int(floor((c.y + r) / CELL)) + 1):
					var ck := _cell_key(cx, cy)
					if not _pad_cells.has(ck):
						_pad_cells[ck] = []
					_pad_cells[ck].append(pad.slice(0, 4))
	return _pad_cells.get(_cell_key(int(floor(p.x / CELL)), int(floor(p.y / CELL))), [])

## The earth round a raised embankment's end (a road on solid earth, no bridge, whose deck at its first or last point
## is over CONE_FROM: where a bridge starts, or several ramps meet): past the end a half-disc at deck height as wide as
## the road, then a 1:EMBANKMENT cone down to the ground. Where the end is a raised junction (raised_pads_near) the
## pad's full disc and cone round the node count too. TownBuilder draws it with cone_height (one mound per node: the
## first end there, `lead`, draws it), decks_at returns it as a side slope, so the car rides what is drawn.
## [{road, seg (its end segment), c (the end point), out (unit, away from the road), ab (the end segment), half, deck,
## pad ([] or raised_pads_near's entry at c), lead, ends (indices of every cone at c, itself included)}]
const CONE_FROM := 0.25 ## m: TownBuilder draws no embankment under a deck this low
const CONE_REACH := 4.0 ## m a cone's foot may lie beyond deck * EMBANKMENT where the ground falls away from its end
var _cones: Array = []
var _cone_seg := {} # road * 2 + (0 at its first point, 1 at its last) -> true
var _cones_built := false
func embankment_cones() -> Array:
	if _cones_built:
		return _cones
	_cones_built = true
	var at := {} # end point -> the cones there
	for ri in road_pts.size():
		var zs := road_z[ri]
		var pts := road_pts[ri]
		var n := pts.size()
		if zs.size() < n or n < 2 or road_bridge[ri] == 1:
			continue
		for last: int in [0, 1]:
			var k := n - 1 if last == 1 else 0
			var j := n - 2 if last == 1 else 1
			if zs[k] <= CONE_FROM or minf(zs[k], zs[j]) > 4.0:
				continue # (over 4 m at both ends of the segment the road stands on piers)
			var seg := n - 2 if last == 1 else 0
			var ab := pts[seg + 1] - pts[seg]
			if ab.length_squared() < 1e-6:
				continue
			_cone_seg[ri * 2 + last] = true
			var cone := {"road": ri, "seg": seg, "c": pts[k], "out": (pts[k] - pts[j]).normalized(), "ab": ab,
				"half": road_w[ri] * 0.5, "deck": float(zs[k]), "pad": [], "lead": false}
			for pad: Array in raised_pads_near(pts[k]):
				if (pad[0] as Vector2).distance_to(pts[k]) < 0.05:
					cone.pad = pad
			var key := Vector2i(roundi(pts[k].x * 20.0), roundi(pts[k].y * 20.0))
			if not at.has(key):
				at[key] = []
				cone.lead = true
			at[key].append(_cones.size())
			_cones.append(cone)
	for cone: Dictionary in _cones: # (indices, not the dictionaries: the map's snapshot holds no cycles)
		cone.ends = at[Vector2i(roundi(cone.c.x * 20.0), roundi(cone.c.y * 20.0))]
	return _cones

## True when past end `last` (0 first point, 1 last) of road ri stands an embankment cone (embankment_cones).
func has_cone(ri: int, last: int) -> bool:
	if not _cones_built:
		embankment_cones()
	return _cone_seg.has(ri * 2 + last)

## The height of an embankment mound's surface at p, as FreeCar.support rides it (lift included): the highest of
## the cones at its node (each past its own road's end) and the raised junction's pad there, on the ground.
func cone_height(cone: Dictionary, p: Vector2) -> float:
	# (on a road's footprint, a bridge's over it included, the car's ground is the plain ground, else the drawn terrain)
	var base := ground(p.x, p.y) if not road_at(p.x, p.y).is_empty() else terrain(p.x, p.y) + pave_top_at(p.x, p.y)
	return base + cone_rise(cone, p)

## How far an embankment mound's surface stands over the ground the car finds at p (zero past its foot), -INF where
## nothing of it is (behind every road end at a node without a pad).
func cone_rise(cone: Dictionary, p: Vector2) -> float:
	var c: Vector2 = cone.c
	var best := -INF
	for ei: int in cone.ends:
		var e: Dictionary = _cones[ei]
		if (p - c).dot(e.out) < 0.0:
			continue # (behind this end its road's own body and side slopes decide)
		var ri: int = e.road
		var over := p.distance_to(c) - float(e.half)
		var dk := deck_across(float(e.deck), p, c)
		dk += level_extra(ri, p, c, e.ab, dk)
		best = maxf(best, maxf(0.0, dk - maxf(over, 0.0) / EMBANKMENT) + road_lift(ri) * (1.0 - smoothstep(0.0, LIFT_RAMP, over)))
	var pad: Array = cone.pad
	if not pad.is_empty():
		var dd := p.distance_to(c) - float(pad[1])
		best = maxf(best, maxf(0.0, float(pad[2]) - maxf(dd, 0.0) / EMBANKMENT) + road_lift(int(pad[3])) * (1.0 - smoothstep(0.0, LIFT_RAMP, dd)))
	return best

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

## True inside the playable area (the whole rectangle if the map has no outline).
func in_play(p: Vector2) -> bool:
	return play_inset.size() < 3 or inside(p, play_inset)

## How far to move p to bring it back inside the playable area (zero when it is inside).
func edge_push(p: Vector2) -> Vector2:
	if in_play(p):
		return Vector2.ZERO
	var best := Vector2.ZERO
	var best_d := INF
	for i in play_inset.size():
		var c := Geometry2D.get_closest_point_to_segment(p, play_inset[i], play_inset[(i + 1) % play_inset.size()])
		var d := p.distance_squared_to(c)
		if d < best_d:
			best_d = d
			best = c - p
	return best

func in_town(p: Vector2) -> bool:
	if boundary.size() < 3:
		return true
	return inside(p, boundary)

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
	# only what TownBuilder draws is solid: a doubled segment (a second panel row 0.8 m off a longer one) or a sliver
	# is not drawn
	var walls: Array = raw.get("fences", [])
	var doubled := doubled_fences(walls)
	for wi in walls.size():
		if doubled.has(wi):
			continue
		var wall: Array = walls[wi]
		var style := int(wall[4]) if wall.size() > 4 else 0
		if style == 4:
			add_wall(Vector2(wall[0], wall[1]), Vector2(wall[2], wall[3]), 0.12) # a closure stands across its road
			continue
		if Vector2(wall[0], wall[1]).distance_to(Vector2(wall[2], wall[3])) < 0.35:
			continue # too short to draw a panel or a bush for
		for piece: Array in fence_pieces(Vector2(wall[0], wall[1]), Vector2(wall[2], wall[3])):
			add_wall(piece[0], piece[1], 0.48 if style == 2 else 0.12)
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
		water_level.append(lo - WATER_DROP) # the lowest the surface lies (it follows the ground: water_surface())
	_build_bed_mask()

## A pond's or river's surface at a map point: WATER_DROP under the ground, so it follows the ground's slope (the baked
## ground is a smoothed 40 m grid that leans across terraced fishponds and falls along the rivers by up to 10 m; one
## level per ring cut the high shore into a cliff the car fell down, and sank dykes under their tracks).
func water_surface(x: float, y: float) -> float:
	return ground(x, y) - WATER_DROP

## How far the drawn terrain sinks under the ground at the vertices in and round the ponds (vertex index, row-major over
## extent at BED_STEP -> metres). The bed is WATER_DROP + POND_DEPTH down inside a ring and rises along a 1:4 bank
## (BANK_SLOPE) through the water's surface at the ring's outline, so between the mesh's vertices the shore meets the
## water's edge with no dry pit outside it and no wall inside it. Roads (not bridges) keep the ground within BANK_HOLD of
## their edge (or their embankment's foot) and sink to the bed over the next BED_STEP: a dyke or a lakeside road keeps
## its bank, drawn and driven. TownBuilder sinks exactly these vertices, and terrain() reads them back.
func _build_bed_mask() -> void:
	var nx := int(extent.size.x / BED_STEP) + 1
	var ny := int(extent.size.y / BED_STEP) + 1
	var full := WATER_DROP + POND_DEPTH
	var reach := WATER_DROP / BANK_SLOPE # m outside the outline where the bank reaches the ground
	var depth := {}
	for k in water_rings.size():
		var ring := water_rings[k]
		var r := water_rects[k]
		# the vertices inside the ring, row by row
		var inside := {}
		var j0 := maxi(int(ceil((r.position.y - extent.position.y) / BED_STEP)), 0)
		var j1 := mini(int(floor((r.end.y - extent.position.y) / BED_STEP)), ny - 1)
		for j in range(j0, j1 + 1):
			var y := extent.position.y + j * BED_STEP
			var xs := PackedFloat32Array()
			for e in ring.size():
				var a := ring[e]
				var b := ring[(e + 1) % ring.size()]
				if (a.y > y) != (b.y > y):
					xs.append(a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x))
			xs.sort()
			for m in range(0, xs.size() - 1, 2):
				var i0 := maxi(int(ceil((xs[m] - extent.position.x) / BED_STEP)), 0)
				var i1 := mini(int(floor((xs[m + 1] - extent.position.x) / BED_STEP)), nx - 1)
				for i in range(i0, i1 + 1):
					inside[j * nx + i] = true
		# distance to the outline of the vertices near it (in or out)
		var near := {}
		var span := maxf(reach, full / BANK_SLOPE)
		for e in ring.size():
			var a := ring[e]
			var b := ring[(e + 1) % ring.size()]
			var lo := a.min(b) - Vector2.ONE * span - extent.position
			var hi := a.max(b) + Vector2.ONE * span - extent.position
			for j in range(maxi(int(ceil(lo.y / BED_STEP)), 0), mini(int(floor(hi.y / BED_STEP)), ny - 1) + 1):
				for i in range(maxi(int(ceil(lo.x / BED_STEP)), 0), mini(int(floor(hi.x / BED_STEP)), nx - 1) + 1):
					var p := extent.position + Vector2(i, j) * BED_STEP
					var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))
					var kk := j * nx + i
					if d < float(near.get(kk, INF)):
						near[kk] = d
		for kk in inside:
			var s: float = near.get(kk, INF)
			var dep := minf(full, WATER_DROP + s * BANK_SLOPE)
			if dep > float(depth.get(kk, 0.0)):
				depth[kk] = dep
		for kk in near:
			if inside.has(kk):
				continue
			var dep := WATER_DROP - float(near[kk]) * BANK_SLOPE
			if dep > float(depth.get(kk, 0.0)):
				depth[kk] = dep
	# roads keep their banks
	const COARSE := 8 # vertices per side of the cells that say where any water is
	var wet := {}
	for kk: int in depth:
		wet[Vector2i(kk % nx / COARSE, kk / nx / COARSE)] = true
	for sid in _seg_road.size():
		var ri := _seg_road[sid]
		if road_bridge[ri] == 1:
			continue
		var i := _seg_i[sid]
		var a := road_pts[ri][i]
		var b := road_pts[ri][i + 1]
		var zs := road_z[ri]
		var raise := 0.0 if zs.is_empty() else maxf(zs[i], zs[i + 1])
		var keep := road_w[ri] * 0.5 + raise * EMBANKMENT + BANK_HOLD
		var lo := a.min(b) - Vector2.ONE * (keep + BED_STEP) - extent.position
		var hi := a.max(b) + Vector2.ONE * (keep + BED_STEP) - extent.position
		var any_wet := false
		for cj in range(floori(lo.y / BED_STEP / COARSE), floori(hi.y / BED_STEP / COARSE) + 1):
			for ci in range(floori(lo.x / BED_STEP / COARSE), floori(hi.x / BED_STEP / COARSE) + 1):
				if wet.has(Vector2i(ci, cj)):
					any_wet = true
		if not any_wet:
			continue
		for j in range(maxi(int(ceil(lo.y / BED_STEP)), 0), mini(int(floor(hi.y / BED_STEP)), ny - 1) + 1):
			for ii in range(maxi(int(ceil(lo.x / BED_STEP)), 0), mini(int(floor(hi.x / BED_STEP)), nx - 1) + 1):
				var kk := j * nx + ii
				if not depth.has(kk):
					continue
				var p := extent.position + Vector2(ii, j) * BED_STEP
				var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))
				var f := clampf((d - keep) / BED_STEP, 0.0, 1.0)
				depth[kk] = float(depth[kk]) * f
	for kk in depth:
		if float(depth[kk]) > 0.01:
			bed_mask[kk] = depth[kk]

## Height of the vertex (i, j) of the drawn terrain mesh (TownBuilder draws exactly this).
func bed_vertex(i: int, j: int, nx: int) -> float:
	var h := ground(extent.position.x + i * BED_STEP, extent.position.y + j * BED_STEP)
	return h - float(bed_mask.get(j * nx + i, 0.0))

func _bed_vertex(i: int, j: int, nx: int) -> float:
	return bed_vertex(i, j, nx)

## The drawn terrain surface at a map point: the ground, with ponds and river beds sunk the way the mesh sinks them,
## sloping down the bank over the mesh's own cells (same triangles as TownBuilder.build_terrain).
func terrain(x: float, y: float) -> float:
	if bed_mask.is_empty():
		return ground(x, y)
	var nx := int(extent.size.x / BED_STEP) + 1
	var ny := int(extent.size.y / BED_STEP) + 1
	var fx := (x - extent.position.x) / BED_STEP
	var fy := (y - extent.position.y) / BED_STEP
	if fx < 0.0 or fy < 0.0 or fx >= nx - 1 or fy >= ny - 1:
		return ground(x, y)
	var i := int(fx)
	var j := int(fy)
	if not (bed_mask.has(j * nx + i) or bed_mask.has(j * nx + i + 1) or bed_mask.has((j + 1) * nx + i)
			or bed_mask.has((j + 1) * nx + i + 1)):
		return ground(x, y)
	var u := fx - i
	var v := fy - j
	var h00 := _bed_vertex(i, j, nx)
	var h11 := _bed_vertex(i + 1, j + 1, nx)
	if v >= u:
		var h01 := _bed_vertex(i, j + 1, nx)
		return h00 + (h11 - h01) * u + (h01 - h00) * v
	var h10 := _bed_vertex(i + 1, j, nx)
	return h00 + (h10 - h00) * u + (h11 - h10) * v

## Traffic signals. OSM maps them three ways: on a junction's node, at the stop line of each arm a few tens of metres
## out, or alone at a pedestrian crossing. Signals within SIGNAL_JUNCTION of a junction share its controller and run
## in two phases split by the arms' axis; a lone crossing gives the road most of the cycle. Each controller starts
## its cycle at an offset of its own, so the town's lights aren't in step.
const SIGNAL_CYCLE := 44.0 ## s
const SIGNAL_GREEN := 18.0 ## s each phase of a junction is green
const SIGNAL_GREEN_LONE := 30.0 ## s a lone crossing lets the road go
const SIGNAL_AMBER := 3.0 ## s
const SIGNAL_RED_AMBER := 1.5 ## s of red and amber together before the green (as Polish signals show it)
const SIGNAL_JUNCTION := 35.0 ## m
const SIGNAL_AT_NODE := 6.0 ## m: a signal this near a junction node stands for every arm of it
enum { SIG_GREEN, SIG_AMBER, SIG_RED, SIG_RED_AMBER }

## One entry per signal head: [Vector2 where the head stands (kerb side), Vector2 direction of the traffic it stops,
## Vector2 stop line (on the road's centre line), float cycle offset (s), float green (s), float half road width].
## Built once, on first call, from the baked signal points.
func signal_heads() -> Array:
	if _signal_heads_built:
		return _signal_heads
	_signal_heads_built = true
	var ctrl := {} # controller key -> [ [travel, stop, half width], ... ]
	var order: Array = []
	var pts := _flat(raw.get("signals", []))
	for k in pts.size():
		var p := pts[k]
		var near := nearest_road(p, 20.0)
		if near.is_empty():
			continue
		var jn: Variant = null
		var jd := SIGNAL_JUNCTION
		for nid in node_edges:
			var streets := 0 # arms that are streets (not tracks or service ways, which signals don't control)
			for e in node_edges[nid]:
				if road_rank[e[1]] >= 3:
					streets += 1
			if streets < 3:
				continue
			var d: float = (node_pos[nid] as Vector2).distance_to(p)
			if d < jd:
				jd = d
				jn = nid
		var key: Variant = jn if jn != null else "lone%d" % k
		if not ctrl.has(key):
			ctrl[key] = []
			order.append(key)
		var arms: Array = ctrl[key]
		var half: float = road_w[near.road] * 0.5
		if jn != null and jd < SIGNAL_AT_NODE:
			# on the junction itself: a head on every arm a car can come in by, back from the widest road's edge
			var j: Vector2 = node_pos[jn]
			var back := 0.0
			for e in node_edges[jn]:
				back = maxf(back, road_w[e[1]] * 0.5)
			for e in node_edges[jn]:
				var ri: int = e[1]
				if road_rank[ri] < 3 or (road_oneway[ri] and e[5]):
					continue # a track, or a one-way street that only leads out
				var rp := road_pts[ri]
				var i0: int = e[2]
				var i1: int = i0 + (1 if int(e[3]) > i0 else -1)
				var out := (rp[i1] - rp[i0]).normalized()
				_add_arm(arms, -out, j + out * (back + 2.5), road_w[ri] * 0.5)
		elif jn != null:
			# at an arm's stop line: it stops the traffic heading into the junction
			var dir: Vector2 = near.dir
			var travel := dir if (node_pos[jn] - near.pos).dot(dir) > 0.0 else -dir
			_add_arm(arms, travel, near.pos, half)
		else:
			# a crossing on its own: both ways, a few metres short of the zebra
			for s: float in [-1.0, 1.0]:
				var travel: Vector2 = near.dir * s
				_add_arm(arms, travel, near.pos - travel * 3.0, half)
	for key in order:
		var arms: Array = ctrl[key]
		if arms.is_empty():
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(str(key))
		var start := rng.randf() * SIGNAL_CYCLE
		var ref: Vector2 = arms[0][0]
		var two := false
		for a in arms:
			if absf((a[0] as Vector2).dot(ref)) < 0.7071:
				two = true
		for a in arms:
			var travel: Vector2 = a[0]
			var cross := absf(travel.dot(ref)) < 0.7071
			var stop: Vector2 = a[1]
			var right := Vector2(-travel.y, travel.x) # the lane side (Traffic drives on +side)
			var off := start + (SIGNAL_CYCLE * 0.5 if cross else 0.0)
			_signal_heads.append([stop + right * (float(a[2]) + 1.0), travel, stop, off,
				SIGNAL_GREEN if two else SIGNAL_GREEN_LONE, float(a[2])])
	return _signal_heads

## One arm per direction at a stop line (two signal points mapped on one arm make one head).
static func _add_arm(arms: Array, travel: Vector2, stop: Vector2, half: float) -> void:
	for a in arms:
		if (a[0] as Vector2).dot(travel) > 0.9 and (a[1] as Vector2).distance_to(stop) < 8.0:
			return
	arms.append([travel, stop, half])

## What signal head h shows at clock t (SIG_GREEN, SIG_AMBER, SIG_RED or SIG_RED_AMBER).
static func signal_state(h: Array, t: float) -> int:
	var x := fposmod(t - float(h[3]), SIGNAL_CYCLE)
	var g: float = h[4]
	if x < g:
		return SIG_GREEN
	if x < g + SIGNAL_AMBER:
		return SIG_AMBER
	if x >= SIGNAL_CYCLE - SIGNAL_RED_AMBER:
		return SIG_RED_AMBER
	return SIG_RED

## The nearest signal head ahead of a car at p heading dir, in its lane, within look metres: [head, distance to
## its stop line] or [] if none.
func signal_ahead(p: Vector2, dir: Vector2, look: float) -> Array:
	var best: Array = []
	var bd := look
	for h in signal_heads():
		var travel: Vector2 = h[1]
		if travel.dot(dir) < 0.8:
			continue
		var rel: Vector2 = (h[2] as Vector2) - p
		var d := rel.dot(travel)
		if d < 0.0 or d > bd or absf(rel.cross(travel)) > float(h[5]) + 1.0:
			continue
		bd = d
		best = [h, d]
	return best

## Fence segments (raw "fences" records) that a longer, parallel one within 0.8 m already covers (a mapped barrier next
## to a generated plot boundary): TownBuilder draws only the longer one, and only it is solid. Returns {index: true}.
static func doubled_fences(walls: Array) -> Dictionary:
	var order: Array = []
	var cells := {}
	for wi in walls.size():
		var w: Array = walls[wi]
		var style := int(w[4]) if w.size() > 4 else 0
		if style == 2 or style == 4:
			continue
		var len := Vector2(float(w[2]) - float(w[0]), float(w[3]) - float(w[1])).length()
		if len >= 0.35:
			order.append([len, wi])
	order.sort_custom(func(x: Array, y: Array) -> bool: return x[0] > y[0])
	var skip := {}
	for entry: Array in order:
		var wi: int = entry[1]
		var w: Array = walls[wi]
		var a := Vector2(float(w[0]), float(w[1]))
		var d := Vector2(float(w[2]), float(w[3])) - a
		var ln: float = entry[0]
		var t := d / ln
		var n := Vector2(-t.y, t.x)
		var mid := a + d * 0.5
		var cell := Vector2i(floori(mid.x / 6.0), floori(mid.y / 6.0))
		var covered := false
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for oi: int in cells.get(cell + Vector2i(dx, dy), []):
					var o: Array = walls[oi]
					var oa := Vector2(float(o[0]), float(o[1]))
					var ob := Vector2(float(o[2]), float(o[3]))
					var ot := (ob - oa) / maxf(oa.distance_to(ob), 1e-3)
					if absf(t.cross(ot)) > 0.1:
						continue
					if absf((oa - a).dot(n)) > 0.8 or absf((ob - a).dot(n)) > 0.8:
						continue
					var s0 := clampf((oa - a).dot(t), 0.0, ln)
					var s1 := clampf((ob - a).dot(t), 0.0, ln)
					if absf(s1 - s0) > ln * 0.8:
						covered = true
		if covered:
			skip[wi] = true
		else:
			if not cells.has(cell):
				cells[cell] = []
			cells[cell].append(wi)
	return skip

## The stretches of fence a-b that stand off every street's carriageway, [[a, b], ...] ([[a, b]] when it touches none):
## OSM barriers and plot boundaries that run into a lane (along a service road, across a bend) are cut there, drawn
## (TownBuilder._fence_records) and solid alike, so the car meets no fence on its lane (_invisible_wall_probe.gd).
func fence_pieces(a: Vector2, b: Vector2) -> Array:
	var ln := a.distance_to(b)
	var n := maxi(2, int(ceil(ln / 0.5)) + 1)
	var cut := false
	var outside := PackedByteArray()
	outside.resize(n)
	for k in n:
		var q := a.lerp(b, float(k) / float(n - 1))
		var hit := road_at(q.x, q.y, -INF, 1.5)
		# on the carriageway or its first half metre of verge (a narrow track counts a metre each side of its centre):
		# a car's box swings that far out on a bend
		var on := not hit.is_empty() and float(hit.deck) < 0.5 and absf(float(hit.dist)) < maxf(float(hit.half), 1.0) + 0.5
		outside[k] = 0 if on else 1
		cut = cut or on
	if not cut:
		return [[a, b]]
	var out := []
	var start := -1
	for k in n + 1:
		if k < n and outside[k] == 1:
			if start < 0:
				start = k
		elif start >= 0:
			# the run of samples off the road, pulled back half a step from the first one on it
			var t0 := float(start) / float(n - 1)
			var t1 := float(k - 1) / float(n - 1)
			if start > 0:
				t0 += 0.5 / float(n - 1)
			if k < n:
				t1 -= 0.5 / float(n - 1)
			if (t1 - t0) * ln >= 0.35:
				out.append([a.lerp(b, t0), a.lerp(b, t1)])
			start = -1
	return out

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
				var key := Vector4i(roundi(walls[k] * 10.0), roundi(walls[k + 1] * 10.0), roundi(walls[k + 2] * 10.0), roundi(walls[k + 3] * 10.0))
				if seen.has(key):
					continue
				seen[key] = true
				var wall := PackedFloat32Array([walls[k], walls[k + 1], walls[k + 2], walls[k + 3], walls[k + 4]])
				if Geometry2D.get_closest_point_to_segment(p, Vector2(wall[0], wall[1]), Vector2(wall[2], wall[3])).distance_to(p) < r + wall[4]:
					out.append(wall)
	return out

## Building ids whose box overlaps the circle.
## The walls a car meets on building bi, as drawn: ax, ay, bx, by, outward nx, ny per face. The OSM ring's edges,
## unless TownBuilder drew the building otherwise and said so with set_building_faces() (walls on the measured LoD2
## roof outline, slid up to 4 m off the footprint; a landmark or shaft model's own footprint; nothing).
func building_faces(bi: int) -> PackedFloat32Array:
	if bld_faces.has(bi):
		return bld_faces[bi]
	var out := PackedFloat32Array()
	var ring := bld_rings[bi]
	var m := ring.size()
	if m < 3:
		return out
	var area := 0.0
	for k in m:
		area += ring[k].cross(ring[(k + 1) % m])
	for k in m:
		var a := ring[k]
		var b := ring[(k + 1) % m]
		var t := (b - a).normalized()
		var n := Vector2(t.y, -t.x) if area > 0.0 else Vector2(-t.y, t.x)
		out.append_array(PackedFloat32Array([a.x, a.y, b.x, b.y, n.x, n.y]))
	return out

## Replaces building bi's collision with the walls TownBuilder drew for it (see building_faces), and indexes it where they
## reach beyond its footprint.
func set_building_faces(bi: int, faces: PackedFloat32Array) -> void:
	bld_faces[bi] = faces
	if faces.is_empty():
		return
	var r := bld_rect[bi]
	for k in range(0, faces.size(), 6):
		r = r.expand(Vector2(faces[k], faces[k + 1])).expand(Vector2(faces[k + 2], faces[k + 3]))
	if r == bld_rect[bi]:
		return
	bld_rect[bi] = r
	for cx in range(int(floor(r.position.x / BCELL)), int(floor(r.end.x / BCELL)) + 1):
		for cy in range(int(floor(r.position.y / BCELL)), int(floor(r.end.y / BCELL)) + 1):
			var ck := _cell_key(cx, cy)
			if not _bld_cells.has(ck):
				_bld_cells[ck] = PackedInt32Array()
			if not bi in _bld_cells[ck]:
				_bld_cells[ck].append(bi)

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
		if inside(p, bld_rings[bi]):
			return true
	return false

## The water surface height if p is in a pond, lake or river area, else NAN.
func water_at(p: Vector2) -> float:
	for k in water_rings.size():
		if water_rects[k].has_point(p) and inside(p, water_rings[k]):
			return water_surface(p.x, p.y)
	return NAN

## Physics surface under a point given the road found there ({} off road).
func surface_of(hit: Dictionary) -> int:
	if hit.is_empty():
		return Physics.SURF_GRASS
	if absf(float(hit.dist)) > float(hit.half) + 0.25:
		return Physics.SURF_GRASS
	match int(hit.surface):
		2: return Physics.SURF_GRAVEL_ROAD if int(hit.get("gravel", 0)) else Physics.SURF_DIRT
		1: return Physics.SURF_ASPHALT
	return Physics.SURF_TRACK

# ---------------------------------------------------------------------------------------------- bridges and tunnels

func _load_rails() -> void:
	for li in raw.get("rail", []).size():
		var pts := _flat(raw.rail[li].p)
		rail_pts.append(pts)
		for i in pts.size():
			var ck := _cell_key(int(floor(pts[i].x / CELL)), int(floor(pts[i].y / CELL)))
			if not _rail_cells.has(ck):
				_rail_cells[ck] = PackedInt32Array()
			_rail_cells[ck].append((rail_pts.size() - 1) * 100000 + i)

## Distance from p to the nearest railway centreline within r (INF when none).
func rail_distance(p: Vector2, r: float) -> float:
	var best := INF
	for cx in range(int(floor((p.x - r) / CELL)), int(floor((p.x + r) / CELL)) + 1):
		for cy in range(int(floor((p.y - r) / CELL)), int(floor((p.y + r) / CELL)) + 1):
			var ck := _cell_key(cx, cy)
			if not _rail_cells.has(ck):
				continue
			for code in _rail_cells[ck]:
				var li: int = code / 100000
				var i: int = code % 100000
				var pts := rail_pts[li]
				for j in [i - 1, i]:
					if j >= 0 and j + 1 < pts.size():
						best = minf(best, Geometry2D.get_closest_point_to_segment(p, pts[j], pts[j + 1]).distance_to(p))
	return best

## The drawn cross-section of railway segment a-b with deck heights za, zb over the ground and ballast width bw
## (TownBuilder.build_rail draws exactly these quads, and rail_bank() holds the car up on them): "ballast" the bed's
## top and its two shoulders, "bank" (only on raised track) the two grassy 1:1.5 slopes from the shoulders down to
## 0.3 m under the ground. Each quad is [p0, p1, p2, p3] as MeshBatch.flat_quad takes them.
## prev (when given) is the line's point before a: "joint" then holds the wedge that closes the gap the two segments'
## sections leave on the outside of the bend at a (bed, shoulder and, on raised track, slope), the same way.
func rail_section(a: Vector2, b: Vector2, za: float, zb: float, bw: float, prev := Vector2.INF) -> Dictionary:
	var t := (b - a).normalized()
	var side := Vector3(-t.y, 0.0, t.x)
	var up := Vector3.UP
	var A := Vector3(a.x, ground(a.x, a.y) + za + 0.05, a.y)
	var B := Vector3(b.x, ground(b.x, b.y) + zb + 0.05, b.y)
	var h := bw * 0.5
	var ballast := [
		[A - side * h, B - side * h, B + side * h, A + side * h],
		[A + side * h, B + side * h, B + side * (h + 0.6) - up * 0.35, A + side * (h + 0.6) - up * 0.35],
		[B - side * h, A - side * h, A - side * (h + 0.6) - up * 0.35, B - side * (h + 0.6) - up * 0.35]]
	var bank := []
	if za > 0.3 or zb > 0.3:
		for g: float in [-1.0, 1.0]:
			var o := side * (h + 0.6) * g
			var e0 := A + o - up * 0.35
			var e1 := B + o - up * 0.35
			var b0 := e0 + side * g * maxf(0.5, za * EMBANKMENT)
			var b1 := e1 + side * g * maxf(0.5, zb * EMBANKMENT)
			b0.y = ground(b0.x, b0.z) - 0.3
			b1.y = ground(b1.x, b1.z) - 0.3
			bank.append([e0, e1, b1, b0])
	var joint := []
	if prev != Vector2.INF and prev.distance_to(a) > 0.01:
		var t0 := (a - prev).normalized()
		var turn := t0.cross(t)
		if absf(turn) > 0.002:
			var g := -signf(turn) # the outside of the bend
			var s0 := Vector3(-t0.y, 0.0, t0.x) * g
			var s1 := side * g
			joint.append([A, A + s0 * h, A + s1 * h, A])
			joint.append([A + s0 * h, A + s1 * h, A + s1 * (h + 0.6) - up * 0.35, A + s0 * (h + 0.6) - up * 0.35])
			if za > 0.3:
				var e0 := A + s0 * (h + 0.6) - up * 0.35
				var e1 := A + s1 * (h + 0.6) - up * 0.35
				var b0 := e0 + s0 * maxf(0.5, za * EMBANKMENT)
				var b1 := e1 + s1 * maxf(0.5, za * EMBANKMENT)
				b0.y = ground(b0.x, b0.z) - 0.3
				b1.y = ground(b1.x, b1.z) - 0.3
				joint.append([e0, e1, b1, b0])
	return {"ballast": ballast, "bank": bank, "joint": joint}

## Every raised railway's drawn bed and embankment as triangles in a spatial hash, for rail_bank().
var _bank_tris := PackedFloat32Array() ## x0, y0, h0, x1, y1, h1, x2, y2, h2 per triangle (map x, y and height)
var _bank_cells := {}

func _load_rail_banks() -> void:
	for r in raw.get("rail", []):
		var zs := PackedFloat32Array(r.get("z", []))
		if zs.is_empty():
			continue
		var pts := _flat(r.p)
		var bw := 2.4 if int(r.get("g", 0)) else 3.6
		for i in pts.size() - 1:
			if zs[i] <= 0.3 and zs[i + 1] <= 0.3:
				continue
			var sec := rail_section(pts[i], pts[i + 1], zs[i], zs[i + 1], bw, pts[i - 1] if i > 0 else Vector2.INF)
			for q in sec.ballast + sec.bank + sec.joint:
				for tri in [[q[0], q[1], q[2]], [q[0], q[2], q[3]]]:
					var k := _bank_tris.size() / 9
					var lo := Vector2(INF, INF)
					var hi := Vector2(-INF, -INF)
					for p: Vector3 in tri:
						_bank_tris.append_array(PackedFloat32Array([p.x, p.z, p.y]))
						lo = lo.min(Vector2(p.x, p.z))
						hi = hi.max(Vector2(p.x, p.z))
					for cx in range(int(floor(lo.x / BCELL)), int(floor(hi.x / BCELL)) + 1):
						for cy in range(int(floor(lo.y / BCELL)), int(floor(hi.y / BCELL)) + 1):
							var ck := _cell_key(cx, cy)
							if not _bank_cells.has(ck):
								_bank_cells[ck] = PackedInt32Array()
							_bank_cells[ck].append(k)

## Height (sea level) of the drawn railway bed or embankment over (x, y), -INF where there is none. The cut a
## street's underpass makes through the embankment (in_tunnel_cut) is no bank unless keep_cut.
func rail_bank(x: float, y: float, keep_cut := false) -> float:
	var ck := _cell_key(int(floor(x / BCELL)), int(floor(y / BCELL)))
	if not _bank_cells.has(ck):
		return -INF
	var best := -INF
	var p := Vector2(x, y)
	for k: int in _bank_cells[ck]:
		var o: int = k * 9
		var a := Vector2(_bank_tris[o], _bank_tris[o + 1])
		var b := Vector2(_bank_tris[o + 3], _bank_tris[o + 4])
		var c := Vector2(_bank_tris[o + 6], _bank_tris[o + 7])
		var den := (b - a).cross(c - a)
		if absf(den) < 1e-6:
			continue
		var wb := (p - a).cross(c - a) / den
		var wc := (b - a).cross(p - a) / den
		if wb < -1e-4 or wc < -1e-4 or wb + wc > 1.0001:
			continue
		best = maxf(best, _bank_tris[o + 2] * (1.0 - wb - wc) + _bank_tris[o + 5] * wb + _bank_tris[o + 8] * wc)
	if best > -INF and not keep_cut and in_tunnel_cut(p):
		return -INF
	# the bank's toe runs a little under the ground; where a pond's bed sinks the drawn ground (terrain()) the toe
	# follows it down (fully at the ground's level, not at all 0.5 m up the slope), so it is no ledge to ride onto
	if best > -INF and not keep_cut:
		var sink := ground(x, y) - terrain(x, y)
		if sink > 0.0:
			best -= sink * clampf(1.0 - (best - ground(x, y)) / 0.5, 0.0, 1.0)
	# a street keeps its own level where the embankment's toe runs under or over it (the Kolonia track by Most
	# Bronisław), and where a raised line (a railway bridge) spans it; only at a level crossing, within the ballast's
	# width and at the street's height, does the line's bed win
	if best > -INF and not keep_cut:
		var hit := road_at(x, y)
		if not hit.is_empty() and (rail_distance(p, RAIL_HALF + 1.0) > RAIL_HALF + 0.5 or best > float(hit.height) + 0.5):
			return -INF
	return best

## Whether p lies in the cut an underpass makes through the railway embankment: between its wing walls (cut_half
## either side of the street's centre line), from one foot of the embankment to the other.
func in_tunnel_cut(p: Vector2) -> bool:
	for t in tunnels:
		var rel: Vector2 = p - t.c
		var v: Vector2 = t.v
		if absf(rel.dot(v)) < float(t.cut_len) and absf(rel.dot(Vector2(-v.y, v.x))) < float(t.cut_half):
			return true
	return false

## The baker's underpasses (a street that goes through a railway embankment or under a railway bridge) with the
## geometry TownBuilder and the car need: c centre, u railway direction, v street direction, w street width, z deck
## height of the railway over the ground (m), half_bore (the roofed length either side of c along the street) and
## half_foot (where the embankment's slope ends and the wing walls reach the ground). Side walls keep the car in the bore.
## The baker records one underpass per street and line; the other track of a double line (or a parallel line close
## by) crosses the same street a few metres on, so the bore, the cut and c (the bore's middle) span every raised
## track that crosses the street there, and top is the highest one's rail level (the header beam's top).
## cut_half / cut_len: the strip of the embankment the street's cut takes out (rail_bank(), TownBuilder._bank_quad).
func _load_tunnels() -> void:
	var road_of := {}
	for ri in raw.get("roads", []).size():
		road_of[int(raw.roads[ri].id)] = ri
	for t in raw.get("tunnels", []):
		var u := Vector2(t.u[0], t.u[1])
		var v := Vector2(t.v[0], t.v[1])
		var c := Vector2(t.c[0], t.c[1])
		var ri: int = road_of.get(int(t.road), -1)
		# the bore runs along the street as it is drawn either side of the crossing (the baked direction is one short
		# segment's, so a street that bends near the railway ran into the bore's wall)
		if ri >= 0:
			v = _road_axis(ri, c, TUNNEL_AXIS, v)
		var sin_t := maxf(absf(u.cross(v)), 0.35)
		var z := float(t.z)
		# the raised tracks crossing the street within 14 m of the baked centre: their offsets along it and heights
		var s_lo := 0.0
		var s_hi := 0.0
		var top := ground(c.x, c.y) + z
		var z_max := z
		var a0 := c - v * 14.0
		var a1 := c + v * 14.0
		for r in raw.get("rail", []):
			var zs := PackedFloat32Array(r.get("z", []))
			if zs.is_empty():
				continue
			var pts := _flat(r.p)
			for i in pts.size() - 1:
				if maxf(zs[i], zs[i + 1]) < 3.0:
					continue
				var x = Geometry2D.segment_intersects_segment(pts[i], pts[i + 1], a0, a1)
				if x == null:
					continue
				var f: float = pts[i].distance_to(x) / maxf(pts[i].distance_to(pts[i + 1]), 1e-6)
				var zx := lerpf(zs[i], zs[i + 1], f)
				var y := lerpf(ground(pts[i].x, pts[i].y) + zs[i], ground(pts[i + 1].x, pts[i + 1].y) + zs[i + 1], f)
				var s: float = ((x as Vector2) - c).dot(v)
				s_lo = minf(s_lo, s)
				s_hi = maxf(s_hi, s)
				top = maxf(top, y)
				z_max = maxf(z_max, zx)
		var mid := (s_lo + s_hi) * 0.5
		var span := (s_hi - s_lo) * 0.5
		c += v * mid
		var w := float(t.w)
		# the bore's half width: the carriageway and a generous verge each side (two cars pass with room to spare even
		# in a lane-wide underpass), wider where the street wanders off the bore's line inside the cut
		var half := maxf(w * 0.5 + TUNNEL_VERGE, TUNNEL_MIN_HALF)
		var hf := 0.0
		var skew := absf(u.dot(v)) / sin_t * (half + 0.3)
		hf = span + skew + minf((RAIL_HALF + 0.6 + EMBANKMENT * z_max) / sin_t, 42.0)
		var rec := {"c": c, "u": u, "v": v, "w": w, "z": top - ground(c.x, c.y), "road": int(t.road), "ri": ri,
			"tn": int(t.get("tn", 0)), "half_bore": span + skew + (RAIL_HALF + 0.3) / sin_t, "half_foot": hf, "top": top,
			"cut_half": half, "cut_len": hf + 2.0, "ground": ground(c.x, c.y)}
		tunnels.append(rec)

## The side walls that keep the car in each underpass's bore and cut (two-sided TownMap walls): through the bore, and
## on along the wing walls as far as they stand WING_SOLID over the ground (TownBuilder draws the wing wall's top a
## hand over the embankment, which falls to nothing at its foot: a wall a few centimetres high is no wall to hit).
## Needs the rail banks.
func _add_tunnel_walls() -> void:
	for t in tunnels:
		var c: Vector2 = t.c
		var v: Vector2 = t.v
		var n := Vector2(-v.y, v.x)
		# where the street wanders off the bore's line inside the cut (it bends, or comes in from the side) the cut
		# widens to take it with a verge, wherever the embankment it runs into stands WING_SOLID high or more
		if int(t.ri) >= 0:
			var need := _road_wander(int(t.ri), c, v, float(t.half_foot), float(t.cut_half) - float(t.w) * 0.5 - TUNNEL_VERGE * 0.6)
			if need + float(t.w) * 0.5 + TUNNEL_VERGE * 0.6 > float(t.cut_half):
				var sin_t := maxf(absf((t.u as Vector2).cross(v)), 0.35)
				var half := minf(need + float(t.w) * 0.5 + TUNNEL_VERGE * 0.6, TUNNEL_MAX_HALF)
				var grow := absf((t.u as Vector2).dot(v)) / sin_t * (half - float(t.cut_half))
				t.cut_half = half
				t.half_bore = float(t.half_bore) + grow
				t.half_foot = float(t.half_foot) + grow
				t.cut_len = float(t.half_foot) + 2.0
		var off := float(t.cut_half) + 0.25
		var hb := float(t.half_bore)
		var hf := float(t.half_foot)
		for side in [-1.0, 1.0]:
			var ends := []
			for e in [-1.0, 1.0]:
				var s := hb
				while s + 0.5 <= hf:
					var q: Vector2 = c + v * (s + 0.5) * e + n * float(t.cut_half) * side
					if rail_bank(q.x, q.y, true) + 0.08 - ground(q.x, q.y) < WING_SOLID:
						break
					if not road_at(q.x, q.y, -INF, 0.5).is_empty():
						break # a street that bends back across the cut (the Kolonia track's hairpin under the railway)
					s += 0.5
				ends.append(s)
			add_wall(c - v * float(ends[0]) + n * off * side, c + v * float(ends[1]) + n * off * side, 0.25)

## Unit direction of road ri through point p, measured between the points `reach` m either side of it along the road
## (`hint` gives the sense, and is what comes back for a road too short to say).
func _road_axis(ri: int, p: Vector2, reach: float, hint: Vector2) -> Vector2:
	var pts := road_pts[ri]
	var best := INF
	var s_at := 0.0
	var acc := 0.0
	var cum := PackedFloat32Array([0.0])
	for k in pts.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(p, pts[k], pts[k + 1])
		if q.distance_to(p) < best:
			best = q.distance_to(p)
			s_at = acc + pts[k].distance_to(q)
		acc += pts[k].distance_to(pts[k + 1])
		cum.append(acc)
	var a := _road_point(pts, cum, s_at - reach)
	var b := _road_point(pts, cum, s_at + reach)
	if a.distance_to(b) < 1.0:
		return hint
	var d := (b - a).normalized()
	return d if d.dot(hint) >= 0.0 else -d

static func _road_point(pts: PackedVector2Array, cum: PackedFloat32Array, s: float) -> Vector2:
	s = clampf(s, 0.0, cum[cum.size() - 1])
	for k in pts.size() - 1:
		if s <= cum[k + 1] or k == pts.size() - 2:
			var f := (s - cum[k]) / maxf(cum[k + 1] - cum[k], 1e-6)
			return pts[k].lerp(pts[k + 1], clampf(f, 0.0, 1.0))
	return pts[pts.size() - 1]

## How far (m) road ri's centre line strays to either side of the line through c along v, within `reach` of c along
## it, at the places where the railway embankment (rail_bank) stands at least WING_SOLID over the ground (a street
## that leaves the cut over the embankment's low toe needs no room there). At least `floor`.
func _road_wander(ri: int, c: Vector2, v: Vector2, reach: float, floor_m: float) -> float:
	var n := Vector2(-v.y, v.x)
	var pts := road_pts[ri]
	var worst := floor_m
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var ln := a.distance_to(b)
		if Geometry2D.get_closest_point_to_segment(c, a, b).distance_to(c) > reach + 30.0:
			continue
		var steps := maxi(1, int(ceil(ln / 0.5)))
		for j in steps + 1:
			var p := a.lerp(b, float(j) / float(steps))
			var rel := p - c
			if absf(rel.dot(v)) > reach or absf(rel.dot(n)) <= worst:
				continue
			if rail_bank(p.x, p.y, true) - ground(p.x, p.y) >= WING_SOLID:
				worst = absf(rel.dot(n))
	return worst

## The two portals of a tunnel: [position, heading out of the bore] each.
func tunnel_portals(t: Dictionary) -> Array:
	return [[t.c - t.v * float(t.half_bore), -t.v], [t.c + t.v * float(t.half_bore), t.v]]

## Parapets along bridge decks (they stop a car at the deck's edge, only a car at the deck's height) and the piers
## under them (only a car below the deck), both from the same rule TownBuilder draws them by.
func _build_bridge_solids() -> void:
	for ri in road_pts.size():
		var zs := road_z[ri]
		if zs.is_empty():
			continue
		var pts := road_pts[ri]
		var n := pts.size()
		var half := road_w[ri] * 0.5
		var bridge := road_bridge[ri] == 1
		var s := 0.0
		var edge_l := PackedVector2Array()
		var edge_r := PackedVector2Array()
		for i in n:
			var t := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
			var nrm := Vector2(-t.y, t.x)
			edge_l.append(pts[i] - nrm * (half + 0.2))
			edge_r.append(pts[i] + nrm * (half + 0.2))
		for i in n - 1:
			var s1 := s + pts[i].distance_to(pts[i + 1])
			var d0 := zs[i]
			var d1 := zs[i + 1]
			if (d0 >= 0.25 or d1 >= 0.25) and (bridge or (d0 > 4.0 and d1 > 4.0)):
				var mid := (pts[i] + pts[i + 1]) * 0.5
				var h := ground(mid.x, mid.y) + (d0 + d1) * 0.5
				if not parapet_open(ri, i, -1.0):
					_add_parapet(edge_l[i], edge_l[i + 1], h)
				if not parapet_open(ri, i, 1.0):
					_add_parapet(edge_r[i], edge_r[i + 1], h)
				if int(s / PIER_SPACING) != int(s1 / PIER_SPACING):
					var p := pts[i]
					var under := road_at(p.x, p.y, -INF, 1.5)
					var on_road: bool = not under.is_empty() and int(under.road) != ri and float(under.deck) < 0.5
					if not on_road and rail_distance(p, 4.0) > 3.5:
						var top := ground(p.x, p.y) + d0
						piers.append([p, top])
						_pier_keys[ri * 100000 + i] = true
						var ck := _cell_key(int(floor(p.x / BCELL)), int(floor(p.y / BCELL)))
						if not _pier_cells.has(ck):
							_pier_cells[ck] = PackedFloat32Array()
						_pier_cells[ck].append_array(PackedFloat32Array([p.x, p.y, PIER_R, top]))
			s = s1

## True where segment i of raised road ri has another street running off its side (-1 left, 1 right) at deck height,
## the mouth of a road joining at a bridge's end: no parapet across it (TownBuilder leaves the same gap).
func parapet_open(ri: int, i: int, side: float) -> bool:
	var pts := road_pts[ri]
	var d := (pts[i + 1] - pts[i]).normalized()
	var mid := (pts[i] + pts[i + 1]) * 0.5
	var deck_y := ground(mid.x, mid.y) + (road_z[ri][i] + road_z[ri][i + 1]) * 0.5 + road_lift(ri)
	# a street at the deck's height just beyond the edge, or under the parapet's own line (one meeting the deck at a
	# slant, the Zaborze tracks: the parapet would stand across it)
	for off: float in [0.25, 1.0]:
		for k in 11:
			var q := pts[i].lerp(pts[i + 1], k / 10.0) + Vector2(-d.y, d.x) * side * (road_w[ri] * 0.5 + off)
			var hit := road_at(q.x, q.y, deck_y)
			if not hit.is_empty() and int(hit.road) != ri and absf(float(hit.height) - deck_y) < 0.8 \
					and absf(float(hit.dist)) < float(hit.half) - 0.3:
				return true
	return false

func has_pier(ri: int, i: int) -> bool:
	return _pier_keys.has(ri * 100000 + i)

func _add_parapet(a: Vector2, b: Vector2, deck_y: float) -> void:
	var lo := a.min(b) - Vector2.ONE * 0.3
	var hi := a.max(b) + Vector2.ONE * 0.3
	for cx in range(int(floor(lo.x / BCELL)), int(floor(hi.x / BCELL)) + 1):
		for cy in range(int(floor(lo.y / BCELL)), int(floor(hi.y / BCELL)) + 1):
			var ck := _cell_key(cx, cy)
			if not _parapet_cells.has(ck):
				_parapet_cells[ck] = PackedFloat32Array()
			_parapet_cells[ck].append_array(PackedFloat32Array([a.x, a.y, b.x, b.y, 0.2, deck_y]))

## Parapet segments near p: [ax, ay, bx, by, half thickness, deck height (sea level)] each.
func parapets_near(p: Vector2, r: float) -> Array[PackedFloat32Array]:
	var out: Array[PackedFloat32Array] = []
	var seen := {}
	for cx in range(int(floor((p.x - r) / BCELL)), int(floor((p.x + r) / BCELL)) + 1):
		for cy in range(int(floor((p.y - r) / BCELL)), int(floor((p.y + r) / BCELL)) + 1):
			var ck := _cell_key(cx, cy)
			if not _parapet_cells.has(ck):
				continue
			var w: PackedFloat32Array = _parapet_cells[ck]
			for k in range(0, w.size(), 6):
				var key := "%0.2f,%0.2f,%0.2f,%0.2f" % [w[k], w[k + 1], w[k + 2], w[k + 3]]
				if seen.has(key):
					continue
				seen[key] = true
				if Geometry2D.get_closest_point_to_segment(p, Vector2(w[k], w[k + 1]), Vector2(w[k + 2], w[k + 3])).distance_to(p) < r + w[k + 4]:
					out.append(w.slice(k, k + 6))
	return out

## Bridge piers near p: Vector4(x, y, radius, top height above sea level).
func piers_near(p: Vector2, r: float) -> Array[Vector4]:
	var out: Array[Vector4] = []
	for cx in range(int(floor((p.x - r) / BCELL)), int(floor((p.x + r) / BCELL)) + 1):
		for cy in range(int(floor((p.y - r) / BCELL)), int(floor((p.y + r) / BCELL)) + 1):
			var ck := _cell_key(cx, cy)
			if not _pier_cells.has(ck):
				continue
			var w: PackedFloat32Array = _pier_cells[ck]
			for k in range(0, w.size(), 4):
				if Vector2(w[k], w[k + 1]).distance_to(p) < r + w[k + 2]:
					out.append(Vector4(w[k], w[k + 1], w[k + 2], w[k + 3]))
	return out
