## The smaller things round a circuit, from the Blender pieces in models/furniture.glb
## (tools/blender/build_furniture.py): marshal posts along the lap, braking boards before the corners that
## end a straight, footbridges and road bridges where OpenStreetMap has one over the circuit, tyre walls with
## belt covers on the outside of the bends where the barrier is tyres, and the teams' transporters in the
## paddock behind the pits (in the teams' colours).
## race_world.gd owns one per circuit and builds it after the rest of the scenery.
extends RefCounted

const WORLD_ASSETS := preload("res://scripts/ui/world_assets.gd")
const FURNITURE_PATH := "res://models/furniture.glb"
const BRIDGE_DECK := 6.5 ## footbridge deck height over the road (build_furniture.py DECK)
const POST_SPACING := 320.0 ## m of track between marshal posts
const TRANSPORTER_LENGTH := 16.5 ## m: a team transporter in the paddock
const TYRE_SEGMENT := 4.0 ## the TyreWall piece's length, two track samples
const TYRE_DEPTH := 1.36 ## how far it reaches behind the barrier line
## colours of the belt covers, by how many of every 20 stretches wear them
const BELT_COLOURS := [[Color("#1b1c1e"), 11], [Color("#d9d9d6"), 3], [Color("#b3151b"), 3], [Color("#1c3f94"), 3]]

static var _meshes := {}

var world: Node3D ## race_world.gd
var track: Track
var root: Node3D
var _lookup := {}
var _liveries: MultiMesh
var _livery_boxes := PackedInt32Array()

static func meshes() -> Dictionary:
	if _meshes.is_empty():
		var scene: Node = WORLD_ASSETS._load_model(FURNITURE_PATH)
		if scene:
			for mi in scene.find_children("*", "MeshInstance3D", true, false):
				_meshes[mi.name] = (mi as MeshInstance3D).mesh
			scene.free()
	return _meshes

func build(w: Node3D) -> void:
	world = w
	track = w.track
	if meshes().is_empty():
		return
	_lookup = world._track_lookup(24.0)
	root = Node3D.new()
	root.name = "Furniture"
	world.track_root.add_child(root)
	_build_marshal_posts()
	if track.cfg.theme != "oval":
		_build_braking_boards()
	_build_tyre_walls()
	_build_hoardings()
	_build_bridges()
	_build_paddock()

## Colours each transporter's livery after the team that uses those boxes.
func paint(race: Race) -> void:
	if not _liveries or not race:
		return
	var by_box := {}
	for car in race.cars:
		by_box[car.box] = car.color
	for k in _livery_boxes.size():
		_liveries.set_instance_color(k, by_box.get(_livery_boxes[k], Color("#d8dadd")))

# --------------------------------------------------------------------------------------------- helpers

func _ground(x: float, z: float) -> float:
	if world.surroundings:
		return world.surroundings.ground_height(x, z)
	return world._terrain_y(_lookup, x, z)

## World position of track point (x, z) on the ground.
func _at(p: PackedFloat64Array) -> Vector3:
	return Vector3(p[0] - world.world_center.x, _ground(p[0], p[1]), p[1] - world.world_center.y)

## A basis whose local +z points along dir (world x/z), y up.
static func _facing(dir: Vector3) -> Basis:
	var z := Vector3(dir.x, 0.0, dir.z).normalized()
	return Basis(Vector3.UP.cross(z).normalized(), Vector3.UP, z)

func _tangent(s: float) -> Vector3:
	var h := track.heading(s)
	return Vector3(cos(h), 0.0, sin(h))

## Whether s is inside a covered section (Monaco's tunnel).
func _in_tunnel(s: float, margin: float) -> bool:
	for span in world._tunnel_spans():
		if world._in_span(s, span, margin):
			return true
	return false

## Whether the spot at (s, d) is taken by the pits, the main grandstands, a building or another part of the lap.
func _taken(s: float, d: float, clearance: float) -> bool:
	var cfg := track.cfg
	var rel_s := track.rel(s)
	var garages: Vector2 = world._garage_span()
	if garages != Vector2.ZERO and signf(d) == signf(cfg.pit_offset) and rel_s > garages.x - 60.0 and rel_s < garages.y + 60.0:
		return true
	if cfg.grandstands and signf(d) == world._stands_side() and rel_s > cfg.stands.x - 30.0 and rel_s < cfg.stands.y + 30.0:
		return true
	if absf(rel_s) < 40.0 or _in_tunnel(s, 20.0):
		return true
	var p := track.pos(s, d)
	if not world._clear_of_track(_lookup, p[0], p[1], clearance):
		return true
	if world.surroundings and world.surroundings.land_at(p[0], p[1]).r > 0.6:
		return true # a building or yard there
	return world._near_tv_camera(p[0] - world.world_center.x, p[1] - world.world_center.y)

func _add(part: String, xfs: Array[Transform3D], colors: Array[Color] = []) -> MultiMesh:
	var m: Dictionary = meshes()
	if xfs.is_empty() or not m.has(part):
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = m[part]
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	var inst := MultiMeshInstance3D.new()
	inst.name = part
	inst.multimesh = mm
	root.add_child(inst)
	return mm

# --------------------------------------------------------------------------------------------- marshal posts

## A post every POST_SPACING metres, on the outside of the coming bend (where a car would go off), just
## behind the barrier and turned to the road.
func _build_marshal_posts() -> void:
	var edge := track.half + track.cfg.runoff
	var count := maxi(6, roundi(track.L / POST_SPACING))
	var xfs: Array[Transform3D] = []
	for k in count:
		var s := (k + 0.35) * track.L / count
		# the sharpest bend in the next 150 m decides the side
		var k_max := 0.0
		for a in range(0, 160, 10):
			var kc := track.sample(track.KC, s + a)
			if absf(kc) > absf(k_max):
				k_max = kc
		var side := -signf(k_max) if absf(k_max) > 1.0 / 400.0 else (1.0 if k % 2 == 0 else -1.0)
		var placed := false
		for try_side in [side, -side]:
			for shift in [0.0, 25.0, -25.0, 50.0]:
				var d: float = try_side * (edge + 3.2)
				if _taken(s + shift, d, edge + 1.5):
					continue
				var p := track.pos(s + shift, d)
				var toward := track.pos(s + shift, 0.0)
				var dir := Vector3(toward[0] - p[0], 0.0, toward[1] - p[1])
				xfs.append(Transform3D(_facing(dir), _at(p) - Vector3.UP * 0.1))
				placed = true
				break
			if placed:
				break
	_add("MarshalPost", xfs)

# --------------------------------------------------------------------------------------------- braking boards

## 300, 200 and 100 m boards before each corner that ends a straight, on the outside of the corner, turned to
## the cars coming.
func _build_braking_boards() -> void:
	var boards := {"BrakeBoard_100": [] as Array[Transform3D], "BrakeBoard_200": [] as Array[Transform3D], "BrakeBoard_300": [] as Array[Transform3D]}
	var s := 0.0
	var step := 10.0
	while s < track.L:
		# a corner: the curvature averaged over 40 m (OSM lines wobble), tighter than a 130 m radius
		var kc := _curvature(s + 20.0, 20.0)
		if absf(kc) < 1.0 / 130.0:
			s += step
			continue
		# a straight before it (no stretch bending tighter than a 400 m radius), long enough for the boards
		var straight := 0.0
		while straight < 400.0 and absf(_curvature(s - straight - 15.0, 15.0)) < 1.0 / 400.0:
			straight += step
		if straight >= 160.0:
			var side := -signf(kc)
			for dist in [100, 200, 300]:
				if dist + 30 > straight:
					continue
				var bs: float = s - dist
				var d: float = side * (track.half + 2.2)
				if _taken(bs, d, track.half + 1.0):
					continue
				var p := track.pos(bs, d)
				(boards["BrakeBoard_%d" % dist] as Array[Transform3D]).append(Transform3D(_facing(-_tangent(bs)), _at(p) - Vector3.UP * 0.05))
		s += 150.0 # past this corner
	for part in boards:
		_add(part, boards[part])

# --------------------------------------------------------------------------------------------- tyre walls

## Key of the barrier segment (two track samples) that sample i is in, on one side of the road.
static func _cell_key(i: int, side: float) -> int:
	return (i >> 1) * 2 + (1 if side > 0.0 else 0)

## The barrier segments that are tyre walls, as _cell_key()s: the outside of every real bend, from a little before
## it to a little after. Empty unless the barrier is tyres. race_world.gd leaves the plain barrier out there.
static func tyre_cells(w: Node3D) -> Dictionary:
	var t: Track = w.track
	var cfg := t.cfg
	var cells := {}
	if cfg.barrier != "tyres":
		return cells
	var count := t.n >> 1
	var bend := PackedFloat32Array() # signed curvature over 40 m, per segment
	bend.resize(count)
	for k in count:
		var total := 0.0
		for a in range(-20, 21, 5):
			total += t.sample(t.KC, (k * 2 + 1) * t.step + a)
		bend[k] = total / 9.0
	var first := -1
	for k in count:
		if absf(bend[k]) < 1.0 / 400.0:
			first = k
			break
	if first < 0:
		return cells
	var c := 0
	while c < count:
		var c0 := (first + c) % count
		var sign_c := signf(bend[c0])
		if absf(bend[c0]) < 1.0 / 400.0:
			c += 1
			continue
		var run := 1
		while c + run < count and absf(bend[(first + c + run) % count]) >= 1.0 / 400.0 and signf(bend[(first + c + run) % count]) == sign_c:
			run += 1
		if run >= 8: # 32 m of bend
			for k in range(-6, run + 4):
				var cc := (first + c + k + count * 2) % count
				var side := -sign_c
				var s := (cc * 2 + 1) * t.step
				var rel_s := t.rel(s)
				if absf(cfg.pit_offset) > 1.0 and side == signf(cfg.pit_offset) and rel_s > cfg.pit_entry - 20.0 and rel_s < cfg.pit_exit + 20.0:
					continue
				if cfg.grandstands and side == w._stands_side() and rel_s > cfg.stands.x - 30.0 and rel_s < cfg.stands.y + 30.0:
					continue
				cells[_cell_key(cc * 2, side)] = run * 1000 + c0 # the stretch it belongs to
		c += run
	return cells

## A 4 m tyre wall piece for every tyre cell, its front face on the barrier line, with its belt covers in
## the colour of its stretch. Chunked along the lap so the camera only draws the ones it can see.
func _build_tyre_walls() -> void:
	var cells: Dictionary = world.tyre_cells
	var m: Dictionary = meshes()
	if cells.is_empty() or not m.has("TyreWall") or not m.has("TyreWallBelt"):
		return
	var bd := track.half + track.cfg.runoff + 0.3
	var chunks := {}
	for key in cells:
		var side := 1.0 if (key & 1) == 1 else -1.0
		var i0: int = (key >> 1) * 2
		var s0 := i0 * track.step
		var s1 := (i0 + 2) * track.step
		var p0 := track.pos(s0, side * bd)
		var p1 := track.pos(s1, side * bd)
		var along := Vector3(p1[0] - p0[0], 0.0, p1[1] - p0[1])
		var chord := along.length()
		if chord < 0.5:
			continue
		along /= chord
		var centre := track.pos((s0 + s1) * 0.5, 0.0)
		var mid := Vector3((p0[0] + p1[0]) * 0.5, 0.0, (p0[1] + p1[1]) * 0.5)
		var z := along.cross(Vector3.UP) # local +z faces the road
		if z.dot(Vector3(centre[0] - mid.x, 0.0, centre[1] - mid.z)) < 0.0:
			along = -along
			z = -z
		var y := 0.0
		for i in [i0, i0 + 1, i0 + 2]:
			var sm: float = i * track.step
			y += (track.H[i % track.n] - world.elevation_base) * world.ALTITUDE_SCALE + track.bank_rise(sm, side * bd)
		y = y / 3.0 - 0.02
		var basis := Basis(along, Vector3.UP, z).scaled_local(Vector3(chord / TYRE_SEGMENT, 1.0, 1.0))
		var at := Vector3(mid.x - world.world_center.x, y, mid.z - world.world_center.y)
		var chunk: int = floori(s0 / 500.0)
		if not chunks.has(chunk):
			chunks[chunk] = {"xf": [] as Array[Transform3D], "col": [] as Array[Color]}
		var stretch: int = cells[key]
		(chunks[chunk].xf as Array[Transform3D]).append(Transform3D(basis, at))
		(chunks[chunk].col as Array[Color]).append(_belt_colour(stretch))
	var belt_mat := StandardMaterial3D.new()
	belt_mat.vertex_color_use_as_albedo = true
	belt_mat.vertex_color_is_srgb = true # BELT_COLOURS are as written, not linear
	belt_mat.roughness = 0.7
	for chunk in chunks:
		var xfs: Array[Transform3D] = chunks[chunk].xf
		var cols: Array[Color] = chunks[chunk].col
		var tyres := _add("TyreWall", xfs)
		var belts := _add("TyreWallBelt", xfs, cols)
		if tyres:
			(root.get_child(root.get_child_count() - 2) as MultiMeshInstance3D).name = "TyreWall_%d" % chunk
		if belts:
			var inst := root.get_child(root.get_child_count() - 1) as MultiMeshInstance3D
			inst.name = "TyreWallBelt_%d" % chunk
			inst.material_override = belt_mat

## Black belts mostly, with some white, red and blue stretches; every cell of a stretch the same.
func _belt_colour(stretch: int) -> Color:
	var pick := int(absi(stretch * 2654435761) % 20)
	for entry in BELT_COLOURS:
		pick -= entry[1]
		if pick < 0:
			return entry[0]
	return BELT_COLOURS[0][0]

# --------------------------------------------------------------------------------------------- hoardings

## Sponsor boards (the grandstands' fascia boards, models/trackside.glb) along the barrier on the outside of
## every corner, where the television cameras look.
func _build_hoardings() -> void:
	var parts: Dictionary = world.trackside_meshes()
	if not parts.has("StandBoard_0"):
		return
	var cfg := track.cfg
	var d0 := track.half + cfg.runoff + 0.65
	var top := 1.05
	var per_board := {}
	var s := 0.0
	var placed := 0
	var k := 0
	while s < track.L and placed < 160:
		var kc := _curvature(s, 20.0)
		if absf(kc) < 1.0 / 160.0:
			s += 10.0
			continue
		var side := -signf(kc)
		# on a tyre wall the boards stand on its rear stack
		var tyres: bool = world.tyre_cells.has(_cell_key(int(s / track.step), side))
		var d: float = side * (d0 + 0.65 if tyres else d0)
		if not _taken(s, d, d0 - 0.4):
			# a straight 10 m board: round a tight bend its middle would cut inside the barrier's line (onto the road
			# at Monaco's hairpins), so it stands out by the bend's sag over its length, its ends on the line
			var k_here := track.sample(track.KC, s)
			var sag := 0.0
			if signf(k_here) == -side:
				var r := 1.0 / maxf(absf(k_here), 0.001) + absf(d)
				sag = r - sqrt(maxf(r * r - 25.0, 0.0))
			var c := track.pos(s, d + side * sag)
			var mid := Vector3(c[0], 0.0, c[1])
			var along := _tangent(s)
			var toward := -Vector3(track.NX[int(s / track.step) % track.n], 0.0, track.NY[int(s / track.step) % track.n]) * side
			var basis := Basis(along, Vector3.UP, toward.normalized())
			if basis.determinant() < 0.0:
				basis = Basis(-along, Vector3.UP, toward.normalized())
			var at := Vector3(mid.x - world.world_center.x, _ground(mid.x, mid.z) + top, mid.z - world.world_center.y)
			var part := "StandBoard_%d" % ((k * 3 + int(s / 97.0)) % world.STAND_BOARDS)
			if not per_board.has(part):
				per_board[part] = [] as Array[Transform3D]
			(per_board[part] as Array[Transform3D]).append(Transform3D(basis, at))
			placed += 1
			k += 1
		s += 10.5
	for part in per_board:
		var xfs: Array[Transform3D] = per_board[part]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = parts[part]
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var inst := MultiMeshInstance3D.new()
		inst.name = "Hoarding_" + part
		inst.multimesh = mm
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(inst)

## Curvature at s averaged over +-half metres.
func _curvature(s: float, half: float) -> float:
	var total := 0.0
	var n := 0
	var a := -half
	while a <= half:
		total += track.sample(track.KC, s + a)
		n += 1
		a += 5.0
	return total / n

# --------------------------------------------------------------------------------------------- bridges

## Footbridges (a truss on two stair towers) and road bridges (a concrete deck on abutments) where OSM has a
## bridge over the circuit.
func _build_bridges() -> void:
	if not world.surroundings:
		return
	var placed: Array[Vector2] = []
	var spans: Array[Transform3D] = []
	var towers: Array[Transform3D] = []
	var road := SurfaceTool.new()
	road.begin(Mesh.PRIMITIVE_TRIANGLES)
	var roads := 0
	for b in world.surroundings.env.get("bridges", []):
		var at := Vector2(b[1], b[2])
		if placed.any(func(q: Vector2) -> bool: return q.distance_to(at) < 20.0):
			continue
		var near: Vector2 = world._nearest_sample(_lookup, at.x, at.y, 30.0)
		if near.x < 0:
			continue
		var s: float = near.x * track.step
		if _in_tunnel(s, 30.0) or absf(track.rel(s)) < 50.0:
			continue
		placed.append(at)
		var dir := Vector3(b[3], 0.0, b[4]).normalized()
		# centred where its line crosses the game's centreline, which need not be where OSM has it, so neither
		# abutment stands on the road
		var i := int(near.x)
		var normal := Vector2(track.NX[i], track.NY[i])
		var across := Vector2(dir.x, dir.z).dot(normal)
		if absf(across) > 0.3:
			at -= Vector2(dir.x, dir.z) * ((at - Vector2(track.X[i], track.Y[i])).dot(normal) / across)
		var sin_a := maxf(absf(dir.cross(_tangent(s)).y), 0.35)
		var half_len := minf((track.half + track.cfg.runoff + 3.0) / sin_a, 45.0)
		var road_y: float = world._road_y(s) - 0.09
		var centre := Vector3(at.x - world.world_center.x, road_y, at.y - world.world_center.y)
		var along := Basis(dir, Vector3.UP, dir.cross(Vector3.UP).normalized()) # local x along the bridge
		if b[0] == 0:
			spans.append(Transform3D(along.scaled_local(Vector3(half_len * 2.0 / 10.0, 1.0, 1.0)), centre))
			for sgn in [-1.0, 1.0]:
				var foot: Vector3 = centre + dir * sgn * (half_len + 2.0)
				var ground := _ground(foot.x + world.world_center.x, foot.z + world.world_center.y)
				var rise := maxf((road_y + BRIDGE_DECK - ground) / BRIDGE_DECK, 0.3)
				# the landing (tower +Y in Blender, -z here) faces the span
				var tb := _facing(dir * sgn).scaled_local(Vector3(1.0, rise, 1.0))
				towers.append(Transform3D(tb, Vector3(foot.x, ground, foot.z)))
		else:
			# long enough that the abutments (10.8 m walls square to the bridge) keep their nearer ends clear of the
			# run-off where it crosses at a slant or on a bend (Monaco's Portier)
			var cos_a := sqrt(1.0 - sin_a * sin_a)
			half_len = minf((track.half + track.cfg.runoff + 2.0 + 5.4 * cos_a) / sin_a + 2.0, 90.0)
			_road_bridge(road, centre, dir, half_len, road_y)
			roads += 1
	_add("BridgeSpan", spans)
	_add("BridgeTower", towers)
	if roads > 0:
		road.generate_normals()
		var inst := MeshInstance3D.new()
		inst.name = "RoadBridges"
		inst.mesh = road.commit()
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("#a8a39a")
		mat.roughness = 0.88
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		inst.material_override = mat
		root.add_child(inst)

## A concrete road bridge: a deck 10 m wide with parapets 7 m over the road, carried on an abutment wall at
## each end.
func _road_bridge(st: SurfaceTool, centre: Vector3, dir: Vector3, half_len: float, road_y: float) -> void:
	var side := Vector3.UP.cross(dir).normalized()
	var top := road_y + 7.2
	var box := func(c: Vector3, u: Vector3, v: Vector3, lo: float, hi: float) -> void:
		# a box round c spanning +-u and +-v across, from height lo to hi
		var p := [c - u - v, c + u - v, c + u + v, c - u + v]
		var b := p.map(func(q: Vector3) -> Vector3: return Vector3(q.x, lo, q.z))
		var t := p.map(func(q: Vector3) -> Vector3: return Vector3(q.x, hi, q.z))
		for i in 4:
			var j := (i + 1) % 4
			world._quad(st, b[i], b[j], t[j], t[i])
		world._quad(st, t[0], t[1], t[2], t[3])
		world._quad(st, b[3], b[2], b[1], b[0])
	box.call(centre, dir * half_len, side * 5.0, top - 1.3, top)
	# the deck (parapets and all) hides the car from a TV camera looking through it, and so do the abutments
	_occlude(centre, dir * half_len, side * 5.0, top - 1.3, top + 1.1)
	for sgn in [-1.0, 1.0]:
		box.call(centre + side * sgn * 4.8, dir * half_len, side * 0.2, top, top + 1.1)
		var end: Vector3 = centre + dir * sgn * (half_len - 1.0)
		var ground := _ground(end.x + world.world_center.x, end.z + world.world_center.y)
		box.call(end, dir * 1.0, side * 5.4, minf(ground, road_y) - 1.0, top - 1.3)
		_occlude(end, dir * 1.0, side * 5.4, -INF, top - 1.3)

## A box round c spanning +-u and +-v, from height lo to hi, as a TV-camera occluder.
func _occlude(c: Vector3, u: Vector3, v: Vector3, lo: float, hi: float) -> void:
	var foot := PackedVector2Array()
	for q in [c - u - v, c + u - v, c + u + v, c - u + v]:
		foot.append(Vector2(q.x, q.z))
	world.add_block_occluder(foot, hi, lo)

# --------------------------------------------------------------------------------------------- paddock

## A transporter for every two boxes, parked nose-to-tail in a row behind the pit building.
func _build_paddock() -> void:
	var cfg := track.cfg
	var garages: Vector2 = world._garage_span()
	if garages == Vector2.ZERO:
		return
	var sg := signf(cfg.pit_offset)
	var d: float = cfg.pit_offset + sg * (5.4 + world.PIT_DEPTH + 7.0)
	var xfs: Array[Transform3D] = []
	var boxes := PackedInt32Array()
	for i in range(0, 16, 2):
		var s := track.box_s(i) + cfg.box_spacing * 0.5
		if s < garages.x or s > garages.y:
			continue
		for row in 2:
			var dd: float = d + sg * row * 4.2
			var p := track.pos(s, dd)
			if not world._clear_of_track(_lookup, p[0], p[1], absf(cfg.pit_offset) + 5.4 + world.PIT_DEPTH + 3.0):
				continue
			# nose towards the start line, alongside the building
			xfs.append(Transform3D(_facing(Vector3(-_tangent(s).z, 0.0, _tangent(s).x) * sg), _at(p)))
			boxes.append(i + row)
	_add("Transporter", xfs)
	var colors: Array[Color] = []
	for k in xfs.size():
		colors.append(Color("#d8dadd"))
	_liveries = _add("TransporterLivery", xfs, colors)
	_livery_boxes = boxes
	if _liveries:
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.35
		(root.get_child(root.get_child_count() - 1) as MultiMeshInstance3D).material_override = mat
