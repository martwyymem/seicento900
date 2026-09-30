## The smaller things round a circuit, from the Blender pieces in models/furniture.glb
## (tools/blender/build_furniture.py): marshal posts along the lap, braking boards before the corners that
## end a straight, footbridges and road bridges where OpenStreetMap has one over the circuit, and the teams'
## transporters in the paddock behind the pits (in the teams' colours).
## race_world.gd owns one per circuit and builds it after the rest of the scenery.
extends RefCounted

const WORLD_ASSETS := preload("res://scripts/ui/world_assets.gd")
const FURNITURE_PATH := "res://models/furniture.glb"
const BRIDGE_DECK := 6.5 ## footbridge deck height over the road (build_furniture.py DECK)
const POST_SPACING := 320.0
const TRANSPORTER_LENGTH := 16.5

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

# --------------------------------------------------------------------------------------------- hoardings

## Sponsor boards (the grandstands' fascia boards, models/trackside.glb) along the barrier on the outside of
## every corner, where the television cameras look.
func _build_hoardings() -> void:
	var parts: Dictionary = world.trackside_meshes()
	if not parts.has("StandBoard_0"):
		return
	var cfg := track.cfg
	var d0 := track.half + cfg.runoff + 0.65
	var top := 0.9 if cfg.barrier == "tyres" else 1.05
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
		var d: float = side * d0
		var a := track.pos(s - 5.0, d)
		var b := track.pos(s + 5.0, d)
		if not _taken(s, d, d0 - 0.4):
			var mid := Vector3((a[0] + b[0]) * 0.5, 0.0, (a[1] + b[1]) * 0.5)
			var along := Vector3(b[0] - a[0], 0.0, b[1] - a[1]).normalized()
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
	for sgn in [-1.0, 1.0]:
		box.call(centre + side * sgn * 4.8, dir * half_len, side * 0.2, top, top + 1.1)
		var end: Vector3 = centre + dir * sgn * (half_len - 1.0)
		var ground := _ground(end.x + world.world_center.x, end.z + world.world_center.y)
		box.call(end, dir * 1.0, side * 5.4, minf(ground, road_y) - 1.0, top - 1.3)

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
