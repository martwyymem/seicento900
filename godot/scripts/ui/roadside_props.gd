## Lightweight roadside vegetation and rally markers built from models/roadside.glb.
## Street stages receive only generic vegetation here; mapped street objects belong in surroundings data.
extends RefCounted

const ASSET_PATH := "res://models/roadside.glb"
const WORLD_ASSETS := preload("res://scripts/ui/world_assets.gd")
const COUNT_PER_KM := [18.0, 28.0, 40.0, 52.0]
const MESH_NAMES := ["BushCluster", "TallGrass", "HayBale", "WaysideCross", "KilometrePost", "RallyBoard"]

static var _meshes := {}
var world: Node3D
var root: Node3D
var _lookup := {}
var _board_mesh: MultiMeshInstance3D

static func meshes() -> Dictionary:
	if _meshes.is_empty():
		var scene: Node = WORLD_ASSETS._load_model(ASSET_PATH)
		if scene:
			for child in scene.find_children("*", "MeshInstance3D", true, false):
				_meshes[child.name] = (child as MeshInstance3D).mesh
			scene.free()
	return _meshes

func build(w: Node3D) -> void:
	world = w
	if meshes().is_empty() or not world.track_root:
		return
	root = Node3D.new()
	root.name = "RoadsideProps"
	world.track_root.add_child(root)
	_lookup = world._track_lookup(24.0)
	var track: Track = world.track
	var rng := RandomNumberGenerator.new()
	rng.seed = int(track.cfg.key.hash())
	var count := mini(240, roundi(track.L / 1000.0 * COUNT_PER_KM[clampi(world.quality, 0, 3)]))
	var bushes: Array[Transform3D] = []
	var grasses: Array[Transform3D] = []
	for i in count:
		var s := (float(i) + rng.randf_range(0.15, 0.85)) * track.L / maxf(1.0, float(count))
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var d := side * (track.half + track.cfg.runoff + rng.randf_range(6.0, 22.0))
		var p: PackedFloat64Array = track.pos(s, d)
		if not world._clear_of_track(_lookup, p[0], p[1], track.half + track.cfg.runoff + 3.0):
			continue
		if world._near_tv_camera(p[0] - world.world_center.x, p[1] - world.world_center.y):
			continue
		if world.surroundings and world.surroundings.land_at(p[0], p[1]).r > 0.6:
			continue
		var ground: float = world.surroundings.ground_height(p[0], p[1]) if world.surroundings else world._ground_at(p[0], p[1])
		var pos := Vector3(p[0] - world.world_center.x, ground, p[1] - world.world_center.y)
		var turn := track.heading(s) + (PI if side < 0.0 else 0.0) + rng.randf_range(-0.5, 0.5)
		var scale := rng.randf_range(0.75, 1.2)
		var xf := Transform3D(Basis(Vector3.UP, turn).scaled(Vector3.ONE * scale), pos)
		if rng.randf() < 0.42:
			bushes.append(xf)
		else:
			grasses.append(xf)
	_add("BushCluster", bushes)
	_add("TallGrass", grasses)
	if not track.cfg.street_stage:
		_add_small_details(rng, track, count)
	if world.race and world.race.settings.mode == "rally":
		set_rally(true)

func _add_small_details(rng: RandomNumberGenerator, track: Track, count: int) -> void:
	var posts: Array[Transform3D] = []
	var crosses: Array[Transform3D] = []
	var bales: Array[Transform3D] = []
	for i in mini(16, maxi(2, count / 10)):
		var s := (float(i) + 0.5) * track.L / maxi(1, mini(16, maxi(2, count / 10)))
		var side := -1.0 if (i % 2 == 0) else 1.0
		var d := side * (track.half + track.cfg.runoff + 5.0)
		var p: PackedFloat64Array = track.pos(s, d)
		if not world._clear_of_track(_lookup, p[0], p[1], track.half + track.cfg.runoff + 3.0):
			continue
		var y: float = world.surroundings.ground_height(p[0], p[1]) if world.surroundings else world._ground_at(p[0], p[1])
		var pos := Vector3(p[0] - world.world_center.x, y, p[1] - world.world_center.y)
		var xf := Transform3D(Basis(Vector3.UP, track.heading(s) + PI * 0.5), pos)
		match i % 5:
			0: crosses.append(xf)
			1, 3: posts.append(xf)
			_: bales.append(xf)
	_add("WaysideCross", crosses)
	_add("KilometrePost", posts)
	_add("HayBale", bales)

func set_rally(enabled: bool) -> void:
	if not root or not world.track:
		return
	if is_instance_valid(_board_mesh):
		_board_mesh.queue_free()
		_board_mesh = null
	if not enabled:
		return
	var track: Track = world.track
	var p: PackedFloat64Array = track.pos(0.0, 0.0)
	var y: float = world.surroundings.ground_height(p[0], p[1]) if world.surroundings else world._ground_at(p[0], p[1])
	var center := Vector3(p[0] - world.world_center.x, y, p[1] - world.world_center.y)
	var tangent := Vector3(cos(track.heading(0.0)), 0.0, sin(track.heading(0.0)))
	var board := Transform3D(Basis(Vector3.UP, atan2(tangent.x, tangent.z)), center + tangent * 8.0)
	var boards: Array[Transform3D] = [board]
	_board_mesh = _add("RallyBoard", boards)

func _add(part: String, transforms: Array[Transform3D]) -> MultiMeshInstance3D:
	if transforms.is_empty() or not meshes().has(part):
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = meshes()[part]
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = part
	instance.multimesh = mm
	instance.visibility_range_end = 650.0
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	root.add_child(instance)
	return instance
