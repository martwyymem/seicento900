## Forza Horizon-style sports festival dressing, animated spectators, night string lights,
## fireworks and crowd ambience for the Brzeszcze open world.
## Built data-driven from TownMap (spots, main roads, busy junctions, corners, campaign missions)
## and updated dynamically for live events, player proximity/speed, day/night and audio.
class_name FestivalDressing
extends Node3D

const SPECTATOR_SHADER := preload("res://shaders/spectator.gdshader")
const LIGHTS_SHADER := preload("res://shaders/festival_lights.gdshader")
const WORLD_ASSETS := preload("res://scripts/ui/world_assets.gd")
const ROADSIDE_MODELS := "res://models/roadside.glb"

const CHUNK := 256.0
const SPEC_CHUNK := 128.0
const SPECTATOR_RANGE := 215.0
const PROP_RANGE := 260.0
const ARCH_RANGE := 420.0
const BUNTING_RANGE := 280.0
const FIREWORK_RANGE := 950.0
const CROWD_HEAR := 95.0
const CROWD_NEAR := 18.0
const CROWD_DB := -16.0
const CHEER_DB := -7.0

## Vibrant Forza-style festival banner & pennant colours (sRGB hex)
const FEST_COLORS := ["#ff6a1a", "#e6197b", "#7a3cff", "#00b4d8", "#ffb703", "#38b000", "#e52521"]
## Casual + festival shirt colours for spectators (sRGB hex)
const SHIRT_COLORS := [
	"#e52521", "#ff6a1a", "#ffb703", "#00b4d8", "#7a3cff", "#e6197b", "#2a9d8f", "#f4f1ea",
	"#1d3557", "#2b2d42", "#e76f51", "#457b9d", "#52b788", "#d62828", "#f77f00", "#6c757d",
]
## The organisers' suits (jacket colour, linear via _col_lin) for the executives at every mission start's trailer.
const EXEC_JACKETS := ["#1d2b4a", "#2b2b30", "#4a1d2b", "#1f3a33", "#51575e", "#3a2f27"]
const EXEC_MODELS := ["FestExecStand", "FestExecClip", "FestExecTalk"]
## Mission starts: the grid runs forward from the line (StreetRivals rows 7 m apart), so the barriers keep off it.
const START_GRID_END := 16.0
const START_CROWD_CAP := 380 ## spectators per mission start (frame budget: SPECTATOR_RANGE culls the rest)
const TRAILER_ALONG := [8.0, 12.0, 4.0, 16.0, -8.0, 22.0]
const TRAILER_LAT := [7.9, 9.2, 11.0, 13.0] ## m from the road edge to the trailer's long axis (its table and executives stand in between)
const TRAILER_SAMPLES_X := [-4.4, -2.8, -1.2, 0.4, 2.0, 3.6, 5.2, 6.2]
const TRAILER_SAMPLES_Z := [-5.1, -3.7, -2.3, -0.9, 0.5, 1.7]
## Executives around the trailer's table and hatch in its local (x, z) with a pose index into EXEC_MODELS and the way they face.
const EXEC_SPOTS := [
	[Vector2(-2.5, -3.1), 0, Vector2(1, 0)], [Vector2(-0.75, -3.1), 1, Vector2(-1, 0)],
	[Vector2(-1.6, -4.4), 2, Vector2(0, 1)], [Vector2(-1.9, -1.95), 1, Vector2(0, 1)],
	[Vector2(2.3, -2.7), 0, Vector2(1, 0)], [Vector2(3.5, -2.7), 2, Vector2(-1, 0)],
]
const BULB_COLORS := ["#ffd27a", "#ff8c42", "#ff4d94", "#66e0ff", "#ffe599", "#a3ff7a"]
const FIREWORK_COLORS := [
	Color(1.0, 0.72, 0.18), Color(1.0, 0.22, 0.56), Color(0.18, 0.85, 1.0),
	Color(1.0, 0.42, 0.12), Color(0.55, 0.32, 1.0), Color(0.35, 1.0, 0.42),
]

var map: TownMap
var builder: TownBuilder
var festival_pos := Vector3.ZERO
var festival_face := 0.0

var spectator_mat: ShaderMaterial
var exec_mat: ShaderMaterial ## the spectator shader in suit mode
var lights_mat: ShaderMaterial
var _banner_mat: StandardMaterial3D
var _mesh_cache := {} ## model name -> [mesh, local_xf] with Banner tintable & Lamp driven
var _hay_mesh: Mesh = null
var _hay_local := Transform3D.IDENTITY

## Crowd ambience zones: [{pos: Vector3, weight: float}]
var crowd_zones: Array = []
var _live_crowd_zones: Array = []
var _live_root: Node3D
var _hub_lights: Array[OmniLight3D] = []
var _lamps_shown := -1.0 ## last lamps_on pushed to _hub_lights

## Fireworks state (single MultiMesh, 3 bursts x 56 sparks = 168 instances)
const FW_BURSTS := 3
const FW_SPARKS := 56
var _fw_mmi: MultiMeshInstance3D
var _fw_slots: Array = []
var _fw_rng := RandomNumberGenerator.new()

## Audio state
var _crowd_voice: WorldAudio.Voice
var _cheer_player: AudioStreamPlayer
var _cheer_cd := 0.0
var _crowd_level := 0.0
var _crowd_t := 0.0

## Placement accumulators during build()
var _spec_xfs := [[], [], []] ## per pose: Stand, Cheer, Wave
var _spec_custom := [[], [], []]
var _exec_xfs := [[], [], []] ## per EXEC_MODELS pose
var _exec_custom := [[], [], []]
var _trailer_xfs := []
var _trailer_cols := []
var _barrier_xfs := []
var _barrier_cols := []
var _hay_xfs := []
var _flag_xfs := []
var _flag_cols := []
var _tall_flag_xfs := []
var _tall_flag_cols := []
var _tent_xfs := []
var _tent_cols := []
var _stall_xfs := []
var _stall_cols := []
var _bench_xfs := []
var _inf_arch_xfs := []
var _inf_arch_cols := []
var _fest_arch_xfs := []
var _fest_arch_cols := []
var _bunting_cells := {} ## Vector2i -> MeshBatch
var _bulb_cells := {} ## Vector2i -> MeshBatch
var _placed_zones: Array[Vector2] = [] ## spacing guard for roadside clusters
var _placed_arches: Array[Vector2] = [] ## spacing guard for arches
var _dressed_starts: Array[Vector2] = [] ## mission starts already given crowds and a trailer (this build only)

var stats := {} ## counts for diagnostics / tests


static func _h(x: float, y: float, salt: float) -> float:
	var v := sin(x * 12.9898 + y * 78.233 + salt * 37.719) * 43758.5453
	return v - floorf(v)


static func _col_lin(hex: String) -> Color:
	return Color(hex).srgb_to_linear()


func setup(town: TownMap, bld: TownBuilder) -> void:
	map = town
	builder = bld
	name = "FestivalDressing"
	_init_materials()
	_load_hay_mesh()
	_build_hub()
	var hit := builder._cached_festival()
	if not hit.is_empty():
		_restore_dressing(hit)
	else:
		var caching := builder.mesh_cache_dir != ""
		var mark := _mark_dressing() if caching else {}
		_build_main_road_dressing()
		_build_busy_corners()
		_build_event_gates()
		if caching:
			builder._store_meshes("festival", [_capture_dressing(mark)])
	_commit_batches()
	_build_fireworks()
	_live_root = Node3D.new()
	_live_root.name = "LiveEventDressing"
	add_child(_live_root)


func _mark_dressing() -> Dictionary:
	var post_n := {}
	for ck in map._post_cells:
		post_n[ck] = (map._post_cells[ck] as PackedVector3Array).size()
	var wall_n := {}
	for ck in map._wall_cells:
		wall_n[ck] = (map._wall_cells[ck] as PackedFloat32Array).size()
	var bunt_m := {}
	for c in _bunting_cells:
		bunt_m[c] = (_bunting_cells[c] as MeshBatch).mark()
	var bulb_m := {}
	for c in _bulb_cells:
		bulb_m[c] = (_bulb_cells[c] as MeshBatch).mark()
	return {
		"spec": [(_spec_xfs[0] as Array).size(), (_spec_xfs[1] as Array).size(), (_spec_xfs[2] as Array).size()],
		"exec": [(_exec_xfs[0] as Array).size(), (_exec_xfs[1] as Array).size(), (_exec_xfs[2] as Array).size()],
		"trailer": _trailer_xfs.size(),
		"barrier": _barrier_xfs.size(),
		"hay": _hay_xfs.size(),
		"flag": _flag_xfs.size(),
		"tall_flag": _tall_flag_xfs.size(),
		"tent": _tent_xfs.size(),
		"stall": _stall_xfs.size(),
		"bench": _bench_xfs.size(),
		"inf_arch": _inf_arch_xfs.size(),
		"fest_arch": _fest_arch_xfs.size(),
		"crowd": crowd_zones.size(),
		"zones": _placed_zones.size(),
		"arches": _placed_arches.size(),
		"bunt": bunt_m,
		"bulb": bulb_m,
		"post": post_n,
		"wall": wall_n,
	}


static func _capture_batch_cells(cells: Dictionary, marks: Dictionary) -> Array:
	var out: Array = []
	for c in cells:
		var mb: MeshBatch = cells[c]
		var m: Vector2i = marks.get(c, Vector2i.ZERO)
		if mb.verts.size() == m.x and mb.indices.size() == m.y:
			continue
		out.append([
			c, m.x,
			mb.verts.slice(m.x),
			mb.normals.slice(m.x),
			mb.uvs.slice(m.x),
			mb.colors.slice(m.x),
			mb.indices.slice(m.y),
		])
	return out


static func _restore_batch_cells(cells: Dictionary, recs: Array) -> void:
	for rec in recs:
		var c: Vector2i = rec[0]
		var base_v: int = int(rec[1])
		if not cells.has(c):
			cells[c] = MeshBatch.new(false, true)
		var mb: MeshBatch = cells[c]
		var delta_v: int = mb.verts.size() - base_v
		mb.verts.append_array(rec[2] as PackedVector3Array)
		mb.normals.append_array(rec[3] as PackedVector3Array)
		mb.uvs.append_array(rec[4] as PackedVector2Array)
		mb.colors.append_array(rec[5] as PackedColorArray)
		var inds: PackedInt32Array = rec[6]
		if delta_v == 0:
			mb.indices.append_array(inds)
		else:
			var n0: int = mb.indices.size()
			mb.indices.resize(n0 + inds.size())
			for k in inds.size():
				mb.indices[n0 + k] = inds[k] + delta_v


func _capture_dressing(mark: Dictionary) -> Dictionary:
	var spec_xfs: Array = []
	var spec_custom: Array = []
	var spec_n: Array = mark["spec"]
	for p_i in 3:
		var n0: int = int(spec_n[p_i])
		spec_xfs.append((_spec_xfs[p_i] as Array).slice(n0))
		spec_custom.append((_spec_custom[p_i] as Array).slice(n0))
	var exec_xfs: Array = []
	var exec_custom: Array = []
	var exec_n: Array = mark["exec"]
	for p_i in 3:
		var n0: int = int(exec_n[p_i])
		exec_xfs.append((_exec_xfs[p_i] as Array).slice(n0))
		exec_custom.append((_exec_custom[p_i] as Array).slice(n0))
	var post_n: Dictionary = mark["post"]
	var post_delta: Array = []
	for ck in map._post_cells:
		var arr: PackedVector3Array = map._post_cells[ck]
		var n0: int = int(post_n.get(ck, 0))
		if arr.size() > n0:
			post_delta.append([ck, arr.slice(n0)])
	var wall_n: Dictionary = mark["wall"]
	var wall_delta: Array = []
	for ck in map._wall_cells:
		var arr: PackedFloat32Array = map._wall_cells[ck]
		var n0: int = int(wall_n.get(ck, 0))
		if arr.size() > n0:
			wall_delta.append([ck, arr.slice(n0)])
	return {
		"spec_xfs": spec_xfs,
		"spec_custom": spec_custom,
		"exec_xfs": exec_xfs,
		"exec_custom": exec_custom,
		"trailer_xfs": _trailer_xfs.slice(int(mark["trailer"])),
		"trailer_cols": _trailer_cols.slice(int(mark["trailer"])),
		"barrier_xfs": _barrier_xfs.slice(int(mark["barrier"])),
		"barrier_cols": _barrier_cols.slice(int(mark["barrier"])),
		"hay_xfs": _hay_xfs.slice(int(mark["hay"])),
		"flag_xfs": _flag_xfs.slice(int(mark["flag"])),
		"flag_cols": _flag_cols.slice(int(mark["flag"])),
		"tall_flag_xfs": _tall_flag_xfs.slice(int(mark["tall_flag"])),
		"tall_flag_cols": _tall_flag_cols.slice(int(mark["tall_flag"])),
		"tent_xfs": _tent_xfs.slice(int(mark["tent"])),
		"tent_cols": _tent_cols.slice(int(mark["tent"])),
		"stall_xfs": _stall_xfs.slice(int(mark["stall"])),
		"stall_cols": _stall_cols.slice(int(mark["stall"])),
		"bench_xfs": _bench_xfs.slice(int(mark["bench"])),
		"inf_arch_xfs": _inf_arch_xfs.slice(int(mark["inf_arch"])),
		"inf_arch_cols": _inf_arch_cols.slice(int(mark["inf_arch"])),
		"fest_arch_xfs": _fest_arch_xfs.slice(int(mark["fest_arch"])),
		"fest_arch_cols": _fest_arch_cols.slice(int(mark["fest_arch"])),
		"bunting": _capture_batch_cells(_bunting_cells, mark["bunt"] as Dictionary),
		"bulbs": _capture_batch_cells(_bulb_cells, mark["bulb"] as Dictionary),
		"crowd_zones": crowd_zones.slice(int(mark["crowd"])),
		"placed_zones": PackedVector2Array(_placed_zones.slice(int(mark["zones"]))),
		"placed_arches": PackedVector2Array(_placed_arches.slice(int(mark["arches"]))),
		"stats": stats.duplicate(),
		"posts": post_delta,
		"walls": wall_delta,
	}


func _restore_dressing(data: Dictionary) -> void:
	var sx: Array = data["spec_xfs"]
	var sc: Array = data["spec_custom"]
	for p_i in 3:
		(_spec_xfs[p_i] as Array).append_array(sx[p_i] as Array)
		(_spec_custom[p_i] as Array).append_array(sc[p_i] as Array)
	var ex: Array = data["exec_xfs"]
	var ec: Array = data["exec_custom"]
	for p_i in 3:
		(_exec_xfs[p_i] as Array).append_array(ex[p_i] as Array)
		(_exec_custom[p_i] as Array).append_array(ec[p_i] as Array)
	_trailer_xfs.append_array(data["trailer_xfs"] as Array)
	_trailer_cols.append_array(data["trailer_cols"] as Array)
	_barrier_xfs.append_array(data["barrier_xfs"] as Array)
	_barrier_cols.append_array(data["barrier_cols"] as Array)
	_hay_xfs.append_array(data["hay_xfs"] as Array)
	_flag_xfs.append_array(data["flag_xfs"] as Array)
	_flag_cols.append_array(data["flag_cols"] as Array)
	_tall_flag_xfs.append_array(data["tall_flag_xfs"] as Array)
	_tall_flag_cols.append_array(data["tall_flag_cols"] as Array)
	_tent_xfs.append_array(data["tent_xfs"] as Array)
	_tent_cols.append_array(data["tent_cols"] as Array)
	_stall_xfs.append_array(data["stall_xfs"] as Array)
	_stall_cols.append_array(data["stall_cols"] as Array)
	_bench_xfs.append_array(data["bench_xfs"] as Array)
	_inf_arch_xfs.append_array(data["inf_arch_xfs"] as Array)
	_inf_arch_cols.append_array(data["inf_arch_cols"] as Array)
	_fest_arch_xfs.append_array(data["fest_arch_xfs"] as Array)
	_fest_arch_cols.append_array(data["fest_arch_cols"] as Array)
	_restore_batch_cells(_bunting_cells, data["bunting"] as Array)
	_restore_batch_cells(_bulb_cells, data["bulbs"] as Array)
	crowd_zones.append_array(data["crowd_zones"] as Array)
	for p: Vector2 in (data["placed_zones"] as PackedVector2Array):
		_placed_zones.append(p)
	for p: Vector2 in (data["placed_arches"] as PackedVector2Array):
		_placed_arches.append(p)
	stats.merge(data["stats"] as Dictionary, true)
	for rec in (data["posts"] as Array):
		var ck: int = int(rec[0])
		var add: PackedVector3Array = rec[1]
		if map._post_cells.has(ck):
			var cur: PackedVector3Array = map._post_cells[ck]
			cur.append_array(add)
			map._post_cells[ck] = cur
		else:
			map._post_cells[ck] = add.duplicate()
	for rec in (data["walls"] as Array):
		var ck: int = int(rec[0])
		var add: PackedFloat32Array = rec[1]
		if map._wall_cells.has(ck):
			var cur: PackedFloat32Array = map._wall_cells[ck]
			cur.append_array(add)
			map._wall_cells[ck] = cur
		else:
			map._wall_cells[ck] = add.duplicate()


func _ready() -> void:
	_init_audio()


func _init_materials() -> void:
	spectator_mat = ShaderMaterial.new()
	spectator_mat.shader = SPECTATOR_SHADER
	builder.night_materials.append(spectator_mat)
	exec_mat = ShaderMaterial.new()
	exec_mat.shader = SPECTATOR_SHADER
	exec_mat.set_shader_parameter("suit", 1.0)
	builder.night_materials.append(exec_mat)

	lights_mat = ShaderMaterial.new()
	lights_mat.shader = LIGHTS_SHADER
	builder.night_materials.append(lights_mat)

	_banner_mat = StandardMaterial3D.new()
	_banner_mat.vertex_color_use_as_albedo = true
	_banner_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_banner_mat.roughness = 0.58


func _load_hay_mesh() -> void:
	var scene: Node = WORLD_ASSETS._load_model(ROADSIDE_MODELS)
	if scene == null:
		return
	for mi in scene.find_children("HayBale", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh:
			_hay_mesh = m.mesh
			_hay_local = TownBuilder._global_of(m, scene)
			break
	scene.free()


## Returns [Mesh, local Transform3D] for a town.glb prop with its Banner surface set to tint via MultiMesh
## instance colour, Lamp surface hooked to builder.lamp_material, and all other surfaces insulated from instance colour.
func _prop_mesh(model_name: String, fallback: Callable = Callable()) -> Array:
	if _mesh_cache.has(model_name):
		return _mesh_cache[model_name]
	var raw: Array
	if builder.has_model(model_name):
		raw = builder.models[model_name]
	elif fallback.is_valid():
		raw = [fallback.call(), Transform3D.IDENTITY]
	else:
		return []
	var src: Mesh = raw[0]
	var copy := src.duplicate() as Mesh
	for i in copy.get_surface_count():
		var m := copy.surface_get_material(i)
		var mname := m.resource_name if m else ""
		if mname == "Banner":
			copy.surface_set_material(i, _banner_mat)
		elif mname == "Lamp" and builder.lamp_material != null:
			var lm := builder.lamp_material
			lm.vertex_color_use_as_albedo = false
			copy.surface_set_material(i, lm)
		elif m is StandardMaterial3D:
			var dup := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
			dup.vertex_color_use_as_albedo = false
			copy.surface_set_material(i, dup)
	var out := [copy, raw[1]]
	_mesh_cache[model_name] = out
	return out


func _spectator_mesh(pose_idx: int) -> Array:
	var names := ["SpectatorStand", "SpectatorCheer", "SpectatorWave"]
	var nm: String = names[pose_idx]
	if builder.has_model(nm):
		return builder.models[nm]
	return [_fallback_spectator(), Transform3D.IDENTITY]


func _exec_mesh(pose_idx: int) -> Array:
	var nm: String = EXEC_MODELS[pose_idx]
	return builder.models[nm] if builder.has_model(nm) else []


static func _fallback_spectator() -> Mesh:
	var box := BoxMesh.new()
	box.size = Vector3(0.45, 1.72, 0.28)
	return box


func _init_audio() -> void:
	AudioSettings.ensure_buses()
	var cp := AudioStreamPlayer.new()
	cp.stream = WorldAudio.stream("crowd")
	cp.bus = "World"
	add_child(cp)
	_crowd_voice = WorldAudio.Voice.new()
	_crowd_voice.player = cp

	_cheer_player = AudioStreamPlayer.new()
	_cheer_player.stream = WorldAudio.stream("cheer")
	_cheer_player.bus = "World"
	add_child(_cheer_player)


# ================================================================================================ placement safety

## Ground height at map point p (respecting pavement kerb height when standing on a pavement).
func _ground_y(p: Vector2) -> float:
	return map.ground(p.x, p.y) + map.kerb_at(p.x, p.y)


## True when map point p is strictly inside the play polygon, off every carriageway by road_margin,
## clear of buildings by bld_margin, dry, off railways, outside tunnel cuts, and off bridge decks/embankments.
func _clear_off_road(p: Vector2, road_margin := 1.7, bld_margin := 1.2) -> bool:
	if not map.in_play(p):
		return false
	if not map.road_at(p.x, p.y, -INF, road_margin).is_empty():
		return false
	if map.inside_building(p) or not map.buildings_near(p, bld_margin).is_empty():
		return false
	if not is_nan(map.water_at(p)):
		return false
	if map.rail_distance(p, 5.5) <= 5.0:
		return false
	if map.in_tunnel_cut(p):
		return false
	if not map.decks_at(p.x, p.y, 1.8).is_empty():
		return false
	return true


## Lighter clearance check for individual spectators standing behind barriers (never on a road, in a building or in water).
func _spectator_spot_ok(p: Vector2) -> bool:
	if not map.in_play(p):
		return false
	if not map.road_at(p.x, p.y, -INF, 1.0).is_empty():
		return false
	if map.inside_building(p) or not map.buildings_near(p, 0.45).is_empty():
		return false
	if not is_nan(map.water_at(p)):
		return false
	if map.rail_distance(p, 4.5) <= 4.0:
		return false
	if map.in_tunnel_cut(p):
		return false
	return true


func _add_spectator(p: Vector2, face_dir: Vector2, pose_override := -1, salt := 0.0) -> void:
	var dir := face_dir.normalized() if face_dir.length_squared() > 1e-6 else Vector2(0, -1)
	var yaw := atan2(-dir.x, -dir.y) + (_h(p.x, p.y, 5.1 + salt) - 0.5) * 0.42
	var y := _ground_y(p)
	var pose := pose_override
	if pose < 0:
		var r := _h(p.x, p.y, 1.7 + salt)
		pose = 0 if r < 0.28 else (1 if r < 0.68 else 2)
	var col_idx := int(floorf(_h(p.x * 1.37, p.y * 1.91, 2.9 + salt * 7.3) * float(SHIRT_COLORS.size()))) % SHIRT_COLORS.size()
	var col := _col_lin(SHIRT_COLORS[col_idx])
	var seed_v := clampf(_h(p.x * 1.73, p.y * 1.29, 8.3 + salt * 3.1), 0.01, 0.99)
	_spec_xfs[pose].append(Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, y, p.y)))
	_spec_custom[pose].append(Color(col.r, col.g, col.b, seed_v))


## Places a drawn barrier segment a..b (1:1 with collision wall map.add_wall when register_collision is true)
## and a dense multi-row cheering spectator group standing behind it along `outward`. Returns true if placed.
func _place_barrier_crowd(a: Vector2, b: Vector2, outward: Vector2, rows := 3, palette_idx := 0,
		register_collision := true, add_flank_bales := true, add_flags := true) -> bool:
	var seg := b - a
	var ln := seg.length()
	if ln < 2.2:
		return false
	var t := seg / ln
	var out := outward.normalized()
	var panels := maxi(1, int(round(ln / 2.5)))
	var actual_len := panels * 2.5
	var b_adj := a + t * actual_len
	# Verify entire barrier line is strictly clear of every road, building, water, rail and existing wall/post
	var steps := panels * 2
	for k in steps + 1:
		var q := a.lerp(b_adj, float(k) / float(steps))
		if not _clear_off_road(q, 1.45, 0.85):
			return false
		if not map.walls_near(q, 0.50).is_empty() or not map.posts_near(q, 0.60).is_empty():
			return false
	# Draw panels along a..b_adj (front faces -out, towards the road)
	var face := -out
	var yaw := atan2(-face.x, -face.y)
	for i in panels:
		var mid := a + t * ((float(i) + 0.5) * 2.5)
		var col := _col_lin(FEST_COLORS[(palette_idx + i) % FEST_COLORS.size()])
		_barrier_xfs.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(mid.x, _ground_y(mid), mid.y)))
		_barrier_cols.append(col)
	# Flanking hay bales at barrier ends (checked before adding this barrier's wall so our own wall doesn't reject them)
	if add_flank_bales and _hay_mesh != null:
		for end_p: Vector2 in [a - t * 0.85, b_adj + t * 0.85]:
			if _clear_off_road(end_p, 1.55, 0.85) and map.posts_near(end_p, 0.65).is_empty() and map.walls_near(end_p, 0.45).is_empty():
				var hy := _ground_y(end_p)
				var hrot := _h(end_p.x, end_p.y, 13.0) * TAU
				_hay_xfs.append(Transform3D(Basis(Vector3.UP, hrot), Vector3(end_p.x, hy, end_p.y)))
				if register_collision:
					map.add_post(end_p, 0.52)
	if register_collision:
		map.add_wall(a, b_adj, 0.22)
	# Flanking sponsor flags behind the barrier ends
	if add_flags:
		for idx_f in 2:
			var fp: Vector2 = (a if idx_f == 0 else b_adj) + out * 0.75
			if _clear_off_road(fp, 1.5, 0.85):
				var fy := _ground_y(fp)
				var frot := atan2(-t.y, t.x) + (PI if idx_f == 1 else 0.0)
				_flag_xfs.append(Transform3D(Basis(Vector3.UP, frot), Vector3(fp.x, fy, fp.y)))
				_flag_cols.append(_col_lin(FEST_COLORS[(palette_idx + idx_f * 2) % FEST_COLORS.size()]))
	# Dense multi-row spectators standing behind the barrier (0.58..2.6 m along outward), facing the road (-out)
	var placed_people := 0
	var centre_sum := Vector2.ZERO
	for r in rows:
		var depth := 0.58 + r * 0.62
		var s := 0.32 + (0.30 if r % 2 == 1 else 0.0)
		while s < actual_len - 0.22:
			var jitter_s := (_h(a.x + s, a.y + r, 4.1) - 0.5) * 0.22
			var jitter_d := (_h(a.x + s, a.y + r, 4.9) - 0.5) * 0.16
			var sp := a + t * (s + jitter_s) + out * (depth + jitter_d)
			if _spectator_spot_ok(sp):
				_add_spectator(sp, face, -1, float(r * 17 + placed_people))
				centre_sum += sp
				placed_people += 1
			s += 0.62 + _h(a.x + s, a.y + r, 6.2) * 0.22
	if placed_people > 0:
		var c := centre_sum / float(placed_people)
		crowd_zones.append({"pos": Vector3(c.x, map.ground(c.x, c.y) + 1.5, c.y), "weight": clampf(placed_people / 16.0, 0.45, 1.5)})
	return true


## Tries several lengths and lateral offsets off a road centre point so a single streetlamp or kerb bend
## never leaves a main road or event gate without a crowd.
func _place_barrier_crowd_flex(center: Vector2, dir: Vector2, out: Vector2, half_w: float, pref_len: float,
		rows: int, palette_idx: int, register_collision := true, add_flank_bales := true, add_flags := true) -> bool:
	var lens: Array[float] = [pref_len]
	for cand: float in [7.5, 5.0]:
		if cand < pref_len - 0.5:
			lens.append(cand)
	for run_len in lens:
		for lat_add: float in [1.75, 2.25, 2.9, 3.6]:
			var base := center + out * (half_w + lat_add)
			if _place_barrier_crowd(base - dir * (run_len * 0.5), base + dir * (run_len * 0.5), out, rows,
					palette_idx, register_collision, add_flank_bales, add_flags):
				return true
	return false


## Free-standing spectator cluster (no barrier wall) for tight spots near junctions / event arches.
func _place_crowd_cluster(center: Vector2, dir: Vector2, out: Vector2, width_along: float, rows: int, salt: float) -> int:
	var face := -out.normalized()
	var t := dir.normalized()
	var o := out.normalized()
	var placed := 0
	var csum := Vector2.ZERO
	for r in rows:
		var depth := r * 0.62
		var s := -width_along * 0.5 + (0.30 if r % 2 == 1 else 0.0)
		while s <= width_along * 0.5:
			var js := (_h(center.x + s, center.y + r, 3.3 + salt) - 0.5) * 0.24
			var jd := (_h(center.x + s, center.y + r, 7.1 + salt) - 0.5) * 0.18
			var sp := center + t * (s + js) + o * (depth + jd)
			if _spectator_spot_ok(sp) and map.road_at(sp.x, sp.y, -INF, 1.7).is_empty():
				_add_spectator(sp, face, -1, salt + float(r * 19 + placed))
				csum += sp
				placed += 1
			s += 0.66 + _h(center.x + s, center.y + r, 5.4 + salt) * 0.24
	if placed > 0:
		var c := csum / float(placed)
		crowd_zones.append({"pos": Vector3(c.x, map.ground(c.x, c.y) + 1.5, c.y), "weight": clampf(placed / 16.0, 0.4, 1.3)})
	return placed


## Places an overhead banner arch (FestivalArch or InflatableArch) centred at `p` facing along `dir`.
## Both legs (at +-7.1 m) must be strictly clear of roads, buildings, water and rails.
func _place_road_arch(p: Vector2, dir: Vector2, inflatable: bool, col_idx: int) -> bool:
	for prev in _placed_arches:
		if prev.distance_to(p) < 110.0:
			return false
	var d := dir.normalized()
	var side := Vector2(-d.y, d.x)
	var leg_half := 7.2 if inflatable else 7.0
	var leg_l := p - side * leg_half
	var leg_r := p + side * leg_half
	if not _clear_off_road(leg_l, 1.5, 1.4) or not _clear_off_road(leg_r, 1.5, 1.4):
		return false
	if not map.posts_near(leg_l, 1.1).is_empty() or not map.posts_near(leg_r, 1.1).is_empty():
		return false
	var yl := map.ground(leg_l.x, leg_l.y)
	var yr := map.ground(leg_r.x, leg_r.y)
	if absf(yl - yr) > 1.2:
		return false
	var y := minf(yl, yr) - 0.05
	var yaw := atan2(-d.x, -d.y)
	var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, y, p.y))
	var col := _col_lin(FEST_COLORS[col_idx % FEST_COLORS.size()])
	if inflatable:
		_inf_arch_xfs.append(xf)
		_inf_arch_cols.append(col)
	else:
		_fest_arch_xfs.append(xf)
		_fest_arch_cols.append(col)
	map.add_post(leg_l, 0.72)
	map.add_post(leg_r, 0.72)
	_placed_arches.append(p)
	return true


## Adds a catenary bunting line + night string-light bulbs between map points a and b at height `h_ends`,
## optionally drawing slim dark support poles at each end.
func _add_bunting_span(a: Vector2, b: Vector2, h_ends: float, sag: float, with_poles := true, salt := 0.0) -> void:
	var dist := a.distance_to(b)
	if dist < 4.0 or dist > 38.0:
		return
	var mid := (a + b) * 0.5
	var c := Vector2i(int(floor(mid.x / CHUNK)), int(floor(mid.y / CHUNK)))
	if not _bunting_cells.has(c):
		_bunting_cells[c] = MeshBatch.new(false, true)
	if not _bulb_cells.has(c):
		_bulb_cells[c] = MeshBatch.new(false, true)
	var mb: MeshBatch = _bunting_cells[c]
	var lb: MeshBatch = _bulb_cells[c]
	var ya := map.ground(a.x, a.y)
	var yb := map.ground(b.x, b.y)
	var pa := Vector3(a.x, ya + h_ends, a.y)
	var pb := Vector3(b.x, yb + h_ends, b.y)
	if with_poles:
		var pole_col := Color(0.16, 0.17, 0.19)
		mb.beam(Vector3(a.x, ya - 0.2, a.y), Vector3(a.x, ya - 0.2, a.y + 0.01), 0.11, h_ends + 0.3, pole_col)
		mb.beam(Vector3(b.x, yb - 0.2, b.y), Vector3(b.x, yb - 0.2, b.y + 0.01), 0.11, h_ends + 0.3, pole_col)
		map.add_post(a, 0.10)
		map.add_post(b, 0.10)
	var segs := clampi(int(round(dist / 0.95)), 6, 26)
	var cable_col := Color(0.12, 0.12, 0.14)
	var prev := pa
	var dir_xz := Vector3(b.x - a.x, 0.0, b.y - a.y).normalized()
	var nrm := Vector3(-dir_xz.z, 0.0, dir_xz.x)
	for k in range(1, segs + 1):
		var t := float(k) / float(segs)
		var drop := 4.0 * t * (1.0 - t) * sag
		var cur := pa.lerp(pb, t) - Vector3.UP * drop
		# thin dark cable
		mb.beam(prev, cur, 0.028, 0.028, cable_col)
		# colourful triangular pennant hanging down from each segment
		var p0 := prev.lerp(cur, 0.10)
		var p1 := prev.lerp(cur, 0.90)
		var tip := (p0 + p1) * 0.5 - Vector3.UP * 0.48
		var pcol := _col_lin(FEST_COLORS[(k + int(salt * 11.0)) % FEST_COLORS.size()])
		mb.flat_tri(p0, p1, tip, nrm, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, pcol)
		mb.flat_tri(p1, p0, tip, -nrm, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, pcol)
		# warm/festive string-light bulb at every segment joint
		if k < segs:
			var bcol := _col_lin(BULB_COLORS[(k + int(salt * 7.0)) % BULB_COLORS.size()])
			var phase := _h(cur.x, cur.z, salt + float(k))
			var bc := Color(bcol.r, bcol.g, bcol.b, phase)
			var bcen := cur - Vector3.UP * 0.08
			var r := 0.085
			# two crossed diamond quads (8 tris per bulb, bright from all angles)
			lb.flat_quad(bcen - dir_xz * r - Vector3.UP * r, bcen + dir_xz * r - Vector3.UP * r,
				bcen + dir_xz * r + Vector3.UP * r, bcen - dir_xz * r + Vector3.UP * r, nrm, bc)
			lb.flat_quad(bcen - nrm * r - Vector3.UP * r, bcen + nrm * r - Vector3.UP * r,
				bcen + nrm * r + Vector3.UP * r, bcen - nrm * r + Vector3.UP * r, dir_xz, bc)
		prev = cur


# ================================================================================================ 1. festival hub

func _build_hub() -> void:
	var spot: Array = map.spots.get("festival", [])
	if spot.is_empty():
		return
	var p := Vector2(spot[0], spot[1])
	var g := map.ground(p.x, p.y)
	festival_pos = Vector3(p.x, g, p.y)
	var near := map.nearest_road(p, 300.0)
	festival_face = 0.0
	if not near.is_empty():
		var d: Vector2 = (near.pos as Vector2) - p
		festival_face = atan2(-d.x, -d.y)
	var hub_xf := Transform3D(Basis(Vector3.UP, festival_face), festival_pos)
	var fest := Node3D.new()
	fest.name = "FestivalHub"
	fest.transform = hub_xf
	add_child(fest)

	# Helper: convert hub-local (lx, lz) to map Vector2
	var to_map := func(lx: float, lz: float) -> Vector2:
		var w := hub_xf * Vector3(lx, 0.0, lz)
		return Vector2(w.x, w.z)
	var to_dir := func(dx: float, dz: float) -> Vector2:
		var w := hub_xf.basis * Vector3(dx, 0.0, dz)
		return Vector2(w.x, w.z).normalized()

	# 1) Main FestivalStage at local (0, 0, 22), facing -Z into the plaza
	var stage_m := _prop_mesh("FestivalStage", TownBuilder._fallback_festival.bind("FestivalStage"))
	if not stage_m.is_empty():
		var stage := MeshInstance3D.new()
		stage.name = "FestivalStage"
		stage.mesh = stage_m[0]
		stage.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 22.0)) * (stage_m[1] as Transform3D)
		var sb := StandardMaterial3D.new()
		sb.albedo_color = Color("#ff6a1a")
		sb.emission_enabled = true
		sb.emission = Color("#ff6a1a")
		sb.emission_energy_multiplier = 0.25
		for i in stage.mesh.get_surface_count():
			var m := stage.mesh.surface_get_material(i)
			if m == _banner_mat or (m and m.resource_name == "Banner"):
				stage.set_surface_override_material(i, sb)
		fest.add_child(stage)
		# Collision for stage deck (16 x 10 m centred at local z=22)
		var s0: Vector2 = to_map.call(-8.2, 16.8)
		var s1: Vector2 = to_map.call(8.2, 16.8)
		var s2: Vector2 = to_map.call(8.2, 27.2)
		var s3: Vector2 = to_map.call(-8.2, 27.2)
		map.add_wall(s0, s1, 0.35)
		map.add_wall(s1, s2, 0.35)
		map.add_wall(s2, s3, 0.35)
		map.add_wall(s3, s0, 0.35)

	# Illuminated SEICENTO FEST sign mounted cleanly over the stage peak (never collides with beacon labels)
	var label := Label3D.new()
	label.text = "SEICENTO FEST\nBRZESZCZE"
	label.font_size = 128
	label.pixel_size = 0.015
	label.outline_size = 16
	label.modulate = Color("#ffd166")
	label.outline_modulate = Color("#3a1060")
	label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	label.position = Vector3(0, 13.4, 22.0)
	label.visibility_range_end = 360.0
	fest.add_child(label)

	# 2) Main FestivalArch (z = -16) & outer InflatableArch gateway (z = -34)
	var arch_p: Vector2 = to_map.call(0.0, -16.0)
	var arch_dir: Vector2 = to_dir.call(0.0, 1.0)
	var arch_yaw := atan2(-arch_dir.x, -arch_dir.y)
	_fest_arch_xfs.append(Transform3D(Basis(Vector3.UP, arch_yaw), Vector3(arch_p.x, map.ground(arch_p.x, arch_p.y), arch_p.y)))
	_fest_arch_cols.append(_col_lin("#7a3cff"))
	map.add_post(to_map.call(-7.0, -16.0), 0.72)
	map.add_post(to_map.call(7.0, -16.0), 0.72)

	var gate_p: Vector2 = to_map.call(0.0, -34.0)
	_inf_arch_xfs.append(Transform3D(Basis(Vector3.UP, arch_yaw), Vector3(gate_p.x, map.ground(gate_p.x, gate_p.y), gate_p.y)))
	_inf_arch_cols.append(_col_lin("#00b4d8"))
	map.add_post(to_map.call(-7.2, -34.0), 0.78)
	map.add_post(to_map.call(7.2, -34.0), 0.78)

	# 3) Stage front crowd-control barrier (local z = 10.5, x = -12.5..+12.5) + packed cheering audience behind it!
	var stage_a: Vector2 = to_map.call(-12.5, 10.5)
	var stage_b: Vector2 = to_map.call(12.5, 10.5)
	var stage_out: Vector2 = to_dir.call(0.0, 1.0) # towards stage (+Z local)
	var stage_face: Vector2 = -stage_out
	var bar_yaw := atan2(-stage_face.x, -stage_face.y)
	for i in 10:
		var mid := stage_a.lerp(stage_b, (float(i) + 0.5) / 10.0)
		_barrier_xfs.append(Transform3D(Basis(Vector3.UP, bar_yaw), Vector3(mid.x, map.ground(mid.x, mid.y), mid.y)))
		_barrier_cols.append(_col_lin(FEST_COLORS[i % FEST_COLORS.size()]))
	map.add_wall(stage_a, stage_b, 0.22)
	# Hay bale clusters flanking the stage barrier and outer arch
	if _hay_mesh != null:
		for hp_loc: Vector2 in [Vector2(-13.6, 10.5), Vector2(13.6, 10.5), Vector2(-13.8, 9.4), Vector2(13.8, 9.4),
				Vector2(-9.6, -15.2), Vector2(9.6, -15.2), Vector2(-9.6, -33.2), Vector2(9.6, -33.2)]:
			var hp: Vector2 = to_map.call(hp_loc.x, hp_loc.y)
			_hay_xfs.append(Transform3D(Basis(Vector3.UP, _h(hp.x, hp.y, 19.0) * TAU), Vector3(hp.x, map.ground(hp.x, hp.y), hp.y)))
			map.add_post(hp, 0.52)
	# Packed concert crowd between barrier (z=11.15) and stage deck (z=16.0), 6 dense rows facing the stage (+Z)
	for row in 6:
		var lz := 11.15 + row * 0.78
		var half_x := 12.0 - row * 0.35
		var lx := -half_x + (0.34 if row % 2 == 1 else 0.0)
		while lx <= half_x:
			var jx := (_h(lx, lz, 2.3) - 0.5) * 0.24
			var jz := (_h(lx, lz, 3.7) - 0.5) * 0.20
			var sp: Vector2 = to_map.call(lx + jx, lz + jz)
			# Mix of people facing the stage and turning towards the plaza/player
			var fdir: Vector2 = stage_out if _h(lx, lz, 9.1) < 0.72 else stage_face
			var pose := 1 if _h(lx, lz, 6.4) < 0.45 else (2 if _h(lx, lz, 6.4) < 0.78 else 0)
			_add_spectator(sp, fdir, pose, lx + lz)
			lx += 0.66 + _h(lx, lz, 5.5) * 0.22
	crowd_zones.append({"pos": Vector3(to_map.call(0.0, 13.5).x, g + 2.0, to_map.call(0.0, 13.5).y), "weight": 2.2})

	# 4) Fan Zone Promenade (left & right wings of the plaza: food/merch stalls, pop-up tents, benches, flags, crowds)
	for side_sgn: float in [-1.0, 1.0]:
		var inward: Vector2 = to_dir.call(-side_sgn, 0.0)
		var stall_yaw := atan2(-inward.x, -inward.y)
		# 3 MerchStalls + 3 Tents alternating along x = +-20 m
		for k in 3:
			var lz := -11.0 + k * 9.5
			var sp: Vector2 = to_map.call(side_sgn * 20.5, lz)
			if _clear_off_road(sp, 3.5, 2.5):
				_stall_xfs.append(Transform3D(Basis(Vector3.UP, stall_yaw), Vector3(sp.x, map.ground(sp.x, sp.y), sp.y)))
				_stall_cols.append(_col_lin(FEST_COLORS[(k * 2 + (0 if side_sgn < 0 else 1)) % FEST_COLORS.size()]))
				map.add_post(sp, 2.1)
				# Dense crowd queuing/mingling in front of each food/merch stall
				for c_i in 7:
					var qp: Vector2 = to_map.call(side_sgn * (16.8 + (c_i % 2) * 0.85), lz - 1.8 + c_i * 0.62)
					_add_spectator(qp, -inward if c_i % 2 == 0 else inward, -1, float(c_i * 3 + k))
			var tp: Vector2 = to_map.call(side_sgn * 25.5, lz + 4.5)
			if _clear_off_road(tp, 3.5, 2.5):
				_tent_xfs.append(Transform3D(Basis(Vector3.UP, stall_yaw), Vector3(tp.x, map.ground(tp.x, tp.y), tp.y)))
				_tent_cols.append(_col_lin(FEST_COLORS[(k * 2 + 3 + (0 if side_sgn < 0 else 2)) % FEST_COLORS.size()]))
				map.add_post(tp, 2.4)
			# Picnic bench beside the stalls
			var bp: Vector2 = to_map.call(side_sgn * 16.5, lz + 4.5)
			if _clear_off_road(bp, 2.5, 1.5):
				_bench_xfs.append(Transform3D(Basis(Vector3.UP, stall_yaw), Vector3(bp.x, map.ground(bp.x, bp.y), bp.y)))
				map.add_post(bp, 0.7)
		# Crowd barriers + dense 3-row cheering fans lining the entry avenue (z = -31..-18.5) and plaza flanks (z = -12..+5.5)
		var av_a: Vector2 = to_map.call(side_sgn * 10.2, -31.0)
		var av_b: Vector2 = to_map.call(side_sgn * 10.2, -18.5)
		if not _place_barrier_crowd(av_a, av_b, -inward, 3, 1 if side_sgn > 0 else 3, true, false, true):
			_place_crowd_cluster(to_map.call(side_sgn * 11.2, -24.5), to_dir.call(0.0, 1.0), -inward, 11.0, 3, 21.0 + side_sgn)
		var pl_a: Vector2 = to_map.call(side_sgn * 12.8, -11.5)
		var pl_b: Vector2 = to_map.call(side_sgn * 12.8, 6.0)
		if not _place_barrier_crowd(pl_a, pl_b, -inward, 3, 4 if side_sgn > 0 else 0, true, false, false):
			_place_crowd_cluster(to_map.call(side_sgn * 13.6, -2.5), to_dir.call(0.0, 1.0), -inward, 14.0, 3, 31.0 + side_sgn)
		crowd_zones.append({"pos": Vector3(to_map.call(side_sgn * 14.0, 0.0).x, g + 1.5, to_map.call(side_sgn * 14.0, 0.0).y), "weight": 1.4})

	# 5) Tall FlagPoles framing the plaza & entrance
	for k in 10:
		var lx := -22.5 + k * 5.0
		if absf(lx) < 7.5:
			continue # keep driveway clear
		var fp: Vector2 = to_map.call(lx, -22.0)
		if _clear_off_road(fp, 2.0, 1.5):
			_tall_flag_xfs.append(Transform3D(Basis(Vector3.UP, festival_face), Vector3(fp.x, map.ground(fp.x, fp.y), fp.y)))
			_tall_flag_cols.append(_col_lin(FEST_COLORS[k % FEST_COLORS.size()]))
			map.add_post(fp, 0.25)
	for k in 6:
		var sx := -16.0 if k < 3 else 16.0
		var sz := -28.0 + (k % 3) * 18.0
		var fp: Vector2 = to_map.call(sx, sz)
		if _clear_off_road(fp, 2.0, 1.5):
			_flag_xfs.append(Transform3D(Basis(Vector3.UP, festival_face), Vector3(fp.x, map.ground(fp.x, fp.y), fp.y)))
			_flag_cols.append(_col_lin(FEST_COLORS[(k + 2) % FEST_COLORS.size()]))

	# 6) Criss-crossing overhead bunting & night string lights over the festival plaza
	var spans := [
		[Vector2(-15.5, -15.5), Vector2(15.5, -15.5)],
		[Vector2(-15.5, -6.0), Vector2(15.5, -6.0)],
		[Vector2(-15.5, 4.0), Vector2(15.5, 4.0)],
		[Vector2(-15.5, -15.5), Vector2(15.5, 4.0)],
		[Vector2(15.5, -15.5), Vector2(-15.5, 4.0)],
		[Vector2(-15.5, 4.0), Vector2(-9.0, 16.5)],
		[Vector2(15.5, 4.0), Vector2(9.0, 16.5)],
		[Vector2(-11.0, -33.0), Vector2(11.0, -33.0)],
		[Vector2(-11.0, -24.5), Vector2(11.0, -24.5)],
	]
	for idx_s in spans.size():
		var sa: Vector2 = to_map.call(spans[idx_s][0].x, spans[idx_s][0].y)
		var sb: Vector2 = to_map.call(spans[idx_s][1].x, spans[idx_s][1].y)
		_add_bunting_span(sa, sb, 6.8, 0.85, true, float(idx_s + 1))

	# 7) Night festival stage & plaza OmniLights (3 lights, no shadows, visible only after dusk)
	var light_defs := [
		[Vector3(0.0, 8.5, 16.5), Color(1.0, 0.52, 0.22), 34.0],
		[Vector3(-15.0, 5.5, -1.0), Color(0.95, 0.35, 0.82), 26.0],
		[Vector3(15.0, 5.5, -1.0), Color(0.25, 0.85, 1.0), 26.0],
	]
	for ld in light_defs:
		var l := OmniLight3D.new()
		l.position = ld[0]
		l.light_color = ld[1]
		l.omni_range = ld[2]
		l.omni_attenuation = 1.6
		l.light_energy = 0.0
		l.shadow_enabled = false
		l.visible = false
		fest.add_child(l)
		_hub_lights.append(l)
		_lamps_shown = -1.0


# ================================================================================================ 2. main roads

func _build_main_road_dressing() -> void:
	var hub2 := Vector2(festival_pos.x, festival_pos.z)
	var bunting_count := 0
	var barrier_runs := 0
	var arch_count := 0

	# Process candidate main roads closest to the festival hub first so hub approaches never starve for budget
	var candidates := []
	for ri in map.road_pts.size():
		var kind := map.road_kind[ri]
		if not kind in ["primary", "secondary", "tertiary", "unclassified"]:
			continue
		if map.road_bridge[ri] == 1 or map.road_len[ri] < 45.0:
			continue
		var pts := map.road_pts[ri]
		var mid := pts[pts.size() / 2]
		var dist_hub := mid.distance_to(hub2)
		var is_main := kind in ["primary", "secondary", "tertiary"]
		if not is_main and dist_hub > 700.0:
			continue
		if not map.in_town(mid) and dist_hub > 1250.0:
			continue
		candidates.append([dist_hub, ri, mid, is_main])
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))

	for item in candidates:
		var dist_hub: float = item[0]
		var ri: int = item[1]
		var mid: Vector2 = item[2]
		var is_main: bool = item[3]
		var kind := map.road_kind[ri]

		var near_hub := dist_hub < 950.0
		var half := map.road_w[ri] * 0.5
		var road_len := map.road_len[ri]
		var bunt_step := 34.0 if near_hub else (62.0 if kind == "secondary" else 88.0)
		var bar_step := 26.0 if near_hub else (68.0 if kind == "secondary" else 115.0)
		var next_bunt := 18.0 + _h(mid.x, mid.y, 1.2) * 14.0
		var next_bar := 14.0 + _h(mid.x, mid.y, 2.4) * 12.0

		# Overhead banner arch on long main-road sections near hub / town, flanked by dense crowds on both approaches
		if is_main and road_len >= 110.0 and arch_count < 18 and (near_hub or kind == "secondary"):
			var at_a := map.along(ri, road_len * 0.5)
			var pa: Vector2 = at_a[0]
			var da: Vector2 = at_a[1]
			if map.decks_at(pa.x, pa.y, 2.0).is_empty() and not map.in_tunnel_cut(pa):
				if _place_road_arch(pa, da, not near_hub and (ri % 2 == 1), ri):
					arch_count += 1
					var sa := Vector2(-da.y, da.x)
					for side_s: float in [-1.0, 1.0]:
						var out_a := sa * side_s
						for along_a: float in [-9.5, 9.5]:
							var cp := pa + da * along_a
							if _place_barrier_crowd_flex(cp, da, out_a, half, 7.5, 3, ri + (1 if side_s > 0 else 0)):
								barrier_runs += 1
							else:
								_place_crowd_cluster(cp + out_a * (half + 2.2), da, out_a, 6.5, 3, float(ri) + along_a)

		var s := 14.0
		while s < road_len - 14.0:
			var at := map.along(ri, s)
			var p: Vector2 = at[0]
			var dir: Vector2 = at[1]
			var side := Vector2(-dir.y, dir.x)
			if not map.decks_at(p.x, p.y, 2.0).is_empty() or map.in_tunnel_cut(p):
				s += 14.0
				continue

			# Bunting + night string lights spanning across the street
			if s >= next_bunt and bunting_count < 145:
				var pl := p - side * (half + 2.15)
				var pr := p + side * (half + 2.15)
				if _clear_off_road(pl, 1.5, 0.9) and _clear_off_road(pr, 1.5, 0.9) \
						and map.posts_near(pl, 0.6).is_empty() and map.posts_near(pr, 0.6).is_empty():
					_add_bunting_span(pl, pr, 6.2, 0.65, true, float(ri) + s * 0.03)
					bunting_count += 1
				next_bunt = s + bunt_step

			# Roadside crowd barriers + hay bales + flags + dense multi-row cheering spectators
			if s >= next_bar and barrier_runs < 180:
				var ok_space := true
				for zp in _placed_zones:
					if zp.distance_to(p) < (18.0 if near_hub else 44.0):
						ok_space = false
						break
				if ok_space:
					var run_len := 10.0 if near_hub else 7.5
					var rows := 3 if near_hub else 2
					var placed_any := false
					for side_s: float in ([-1.0, 1.0] if near_hub else ([1.0] if _h(p.x, p.y, 3.3) > 0.5 else [-1.0])):
						var out := side * side_s
						if _place_barrier_crowd_flex(p, dir, out, half, run_len, rows, ri + int(s), true, true, true):
							barrier_runs += 1
							placed_any = true
					if placed_any:
						_placed_zones.append(p)
				next_bar = s + bar_step

			s += 12.0

	stats["bunting_spans"] = bunting_count
	stats["road_arches"] = arch_count
	stats["road_barrier_runs"] = barrier_runs


# ================================================================================================ 3. busy corners

func _build_busy_corners() -> void:
	var hub2 := Vector2(festival_pos.x, festival_pos.z)
	var corner_count := 0

	# Busy junctions: >= 3 street arms with at least one secondary/tertiary road in town or near hub
	for nid in map.node_edges:
		if corner_count >= 28:
			break
		var edges: Array = map.node_edges[nid]
		if edges.size() < 3:
			continue
		var has_main := false
		var max_w := 0.0
		for e in edges:
			var ri: int = e[1]
			if map.road_kind[ri] in ["primary", "secondary", "tertiary"]:
				has_main = true
			max_w = maxf(max_w, map.road_w[ri])
		if not has_main:
			continue
		var jp: Vector2 = map.node_pos[nid]
		if not map.in_town(jp) and jp.distance_to(hub2) > 1300.0:
			continue
		var too_close := false
		for zp in _placed_zones:
			if zp.distance_to(jp) < 55.0:
				too_close = true
				break
		if too_close:
			continue
		# Try placing a barrier + hay bale + spectator corner pocket on one of the 4 diagonal quadrants outside the junction
		var r_off := max_w * 0.5 + 4.8
		for qk in 4:
			var ang := PI * 0.25 + qk * PI * 0.5 + _h(jp.x, jp.y, 1.1) * 0.4
			var out := Vector2(cos(ang), sin(ang))
			var tan := Vector2(-out.y, out.x)
			var c := jp + out * r_off
			if _place_barrier_crowd(c - tan * 2.5, c + tan * 2.5, out, 2, corner_count + qk, true, true, true):
				_placed_zones.append(jp)
				corner_count += 1
				break

	# Sharp corners along main town roads (outside apex spectator pockets + hay bales)
	for ri in map.road_pts.size():
		if corner_count >= 44:
			break
		if not map.road_kind[ri] in ["secondary", "tertiary"] or map.road_bridge[ri] == 1:
			continue
		var pts := map.road_pts[ri]
		if pts.size() < 5:
			continue
		var half := map.road_w[ri] * 0.5
		for i in range(1, pts.size() - 1):
			var d0 := (pts[i] - pts[i - 1]).normalized()
			var d1 := (pts[i + 1] - pts[i]).normalized()
			if d0.dot(d1) > 0.86: # sharper than ~30 degrees
				continue
			var p := pts[i]
			if not map.in_town(p) and p.distance_to(hub2) > 1300.0:
				continue
			var too_close := false
			for zp in _placed_zones:
				if zp.distance_to(p) < 55.0:
					too_close = true
					break
			if too_close:
				continue
			var out := (d0 - d1).normalized() # outside of the bend!
			var tan := Vector2(-out.y, out.x)
			var base := p + out * (half + 2.4)
			if _place_barrier_crowd(base - tan * 2.5, base + tan * 2.5, out, 2, corner_count + ri, true, true, true):
				_placed_zones.append(p)
				corner_count += 1
				break

	stats["busy_corners"] = corner_count


# ================================================================================================ 4. event gates

func _build_event_gates() -> void:
	var gates := 0
	# A) Every named stage spot (except festival hub which has its own full plaza)
	var spot_idx := 0
	for spot_name in map.spots:
		spot_idx += 1
		if spot_name == "festival":
			continue
		var sp: Array = map.spots[spot_name]
		if sp.size() < 3:
			continue
		var p := Vector2(float(sp[0]), float(sp[1]))
		if not map.in_play(p):
			continue
		var dir := Vector2(cos(float(sp[2])), sin(float(sp[2])))
		_dress_gate_point(p, dir, spot_idx, true)
		gates += 1

	# B) Every campaign mission's start and finish on the map
	for k in Missions.MISSIONS.size():
		var mev := MapMissions.event(Missions.BASE + k)
		if mev.is_empty():
			continue
		var p_start: Vector2 = mev.pos
		var dir_start := Vector2(cos(float(mev.heading)), sin(float(mev.heading)))
		if map.in_play(p_start):
			_dress_gate_point(p_start, dir_start, 10 + k, false, true)
			_dress_mission_start(p_start, dir_start, k)
			gates += 1
		var path: PackedVector2Array = mev.get("path", PackedVector2Array())
		if path.size() >= 2:
			var p_end := path[path.size() - 1]
			if map.in_play(p_end) and p_end.distance_to(p_start) > 45.0:
				var dir_end := (p_end - path[path.size() - 2]).normalized()
				_dress_gate_point(p_end, dir_end, 20 + k, false)
				gates += 1

	stats["event_gates"] = gates


# ================================================================================================ 4b. mission starts

func _spec_count() -> int:
	return (_spec_xfs[0] as Array).size() + (_spec_xfs[1] as Array).size() + (_spec_xfs[2] as Array).size()


## Crowds along both sides of the road before and beyond a campaign mission's grid (never on the grid itself, which runs
## START_GRID_END m forward from the line), capped at START_CROWD_CAP spectators, plus the organisers' trailer with its
## executives on the open verge beside the grid. Called after _dress_gate_point, which put the arch and the first barriers.
func _dress_mission_start(p: Vector2, dir: Vector2, k: int) -> void:
	var near := map.nearest_road(p, 25.0)
	var half := 3.6
	if not near.is_empty():
		p = near.pos
		dir = near.dir
		half = map.road_w[int(near.road)] * 0.5
	for q in _dressed_starts:
		if q.distance_to(p) < 40.0:
			return # two missions starting on the same spot share one trailer and crowd
	_dressed_starts.append(p)
	var side := Vector2(-dir.y, dir.x)
	var people0 := _spec_count()
	var trailer := _place_trailer(p, dir, side, half, k)
	var runs := 0
	for sgn: float in [-1.0, 1.0]:
		var out := side * sgn
		for along: float in [-31.0, -42.0, -53.0, -64.0, START_GRID_END + 27.0, START_GRID_END + 38.0, START_GRID_END + 49.0,
				START_GRID_END + 60.0, START_GRID_END + 71.0]:
			if _spec_count() - people0 >= START_CROWD_CAP:
				break
			if _place_barrier_crowd_flex(p + dir * along, dir, out, half, 10.0, 3, k + runs, true, true, true):
				runs += 1
	stats["mission_starts"] = int(stats.get("mission_starts", 0)) + 1
	stats["mission_crowd_runs"] = int(stats.get("mission_crowd_runs", 0)) + runs
	stats["mission_crowd_people"] = int(stats.get("mission_crowd_people", 0)) + _spec_count() - people0
	if trailer:
		stats["mission_trailers"] = int(stats.get("mission_trailers", 0)) + 1


## Trailer-local (x along its length, z from its centre line, -z = the service side facing the road) -> map point.
static func _trailer_pt(c: Vector2, yaw: float, l: Vector2) -> Vector2:
	return c + Vector2(cos(yaw) * l.x + sin(yaw) * l.y, -sin(yaw) * l.x + cos(yaw) * l.y)


## The ground height under a trailer centred at c with `yaw` (the lowest body corner), or NAN when anything of its
## footprint (body, awning, table, tow bar) lands on a road, building, water, rail, wall or post, or the ground is too uneven.
func _trailer_ground(c: Vector2, yaw: float) -> float:
	for lx: float in TRAILER_SAMPLES_X:
		for lz: float in TRAILER_SAMPLES_Z:
			var q := _trailer_pt(c, yaw, Vector2(lx, lz))
			if not _clear_off_road(q, 1.1, 0.8) or not map.walls_near(q, 0.6).is_empty() or not map.posts_near(q, 0.7).is_empty():
				return NAN
	var lo := INF
	var hi := -INF
	for l: Vector2 in [Vector2(-4.2, -1.3), Vector2(4.2, -1.3), Vector2(-4.2, 1.3), Vector2(4.2, 1.3), Vector2(-1.6, -3.6), Vector2.ZERO]:
		var q := _trailer_pt(c, yaw, l)
		var g := _ground_y(q)
		lo = minf(lo, g)
		hi = maxf(hi, g)
	return lo if hi - lo <= 0.9 else NAN


## Parks one organisers' trailer beside the road near a mission start, its serving side towards the road, with the
## executives around its table, wall collision on the body and posts for the awning, table and tow bar.
func _place_trailer(p: Vector2, dir: Vector2, side: Vector2, half: float, k: int) -> bool:
	if not builder.has_model("FestTrailer"):
		return false
	for sgn: float in ([1.0, -1.0] if k % 2 == 0 else [-1.0, 1.0]):
		var out := side * sgn
		var face := -out
		var yaw := atan2(-face.x, -face.y)
		for along: float in TRAILER_ALONG:
			for lat: float in TRAILER_LAT:
				var c := p + dir * along + out * (half + lat)
				var y := _trailer_ground(c, yaw)
				if is_nan(y):
					continue
				_trailer_xfs.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(c.x, y, c.y)))
				_trailer_cols.append(_col_lin(FEST_COLORS[(k + 3) % FEST_COLORS.size()]))
				var cn: Array = [Vector2(-4.2, -1.3), Vector2(4.2, -1.3), Vector2(4.2, 1.3), Vector2(-4.2, 1.3)]
				for i in 4:
					map.add_wall(_trailer_pt(c, yaw, cn[i]), _trailer_pt(c, yaw, cn[(i + 1) % 4]), 0.22)
				map.add_post(_trailer_pt(c, yaw, Vector2(-3.2, -2.6)), 0.14)
				map.add_post(_trailer_pt(c, yaw, Vector2(0.0, -2.6)), 0.14)
				map.add_post(_trailer_pt(c, yaw, Vector2(-1.6, -3.6)), 0.5)
				map.add_post(_trailer_pt(c, yaw, Vector2(5.5, 0.0)), 0.35)
				for e in EXEC_SPOTS.size():
					var spot: Array = EXEC_SPOTS[e]
					var w := _trailer_pt(c, yaw, spot[0])
					var f: Vector2 = spot[2]
					var yaw_e := yaw + atan2(-f.x, -f.y)
					var jc := _col_lin(EXEC_JACKETS[(k + e) % EXEC_JACKETS.size()])
					var seed_v := clampf(_h(w.x * 1.73, w.y * 1.29, 11.3 + float(e)), 0.01, 0.99)
					var pose: int = spot[1]
					_exec_xfs[pose].append(Transform3D(Basis(Vector3.UP, yaw_e), Vector3(w.x, _ground_y(w), w.y)))
					_exec_custom[pose].append(Color(jc.r, jc.g, jc.b, seed_v))
				return true
	return false


## start_grid: a campaign mission's start, where the rivals' grid runs forward from the line (START_GRID_END): the barriers
## stand behind that stretch instead of beside it, and _dress_mission_start adds the longer crowds and the trailer.
func _dress_gate_point(p: Vector2, dir: Vector2, col_idx: int, allow_stall: bool, start_grid := false) -> void:
	var near := map.nearest_road(p, 25.0)
	var half := 3.6
	if not near.is_empty():
		p = near.pos
		dir = near.dir
		half = map.road_w[int(near.road)] * 0.5
	var side := Vector2(-dir.y, dir.x)
	# Overhead inflatable arch when both legs clear; otherwise twin sponsor flags flanking the gate
	var has_arch := _place_road_arch(p, dir, true, col_idx)
	if not has_arch:
		for sgn: float in [-1.0, 1.0]:
			var fp := p + side * sgn * (half + 2.0)
			if _clear_off_road(fp, 1.6, 1.0):
				_flag_xfs.append(Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)), Vector3(fp.x, _ground_y(fp), fp.y)))
				_flag_cols.append(_col_lin(FEST_COLORS[(col_idx + (1 if sgn > 0 else 0)) % FEST_COLORS.size()]))
	# Dense 3-row spectator barrier pockets on BOTH approaches (before and after the gate, clear of arch legs)
	for sgn: float in [-1.0, 1.0]:
		var out := side * sgn
		var placed_side := 0
		var groups := [[-10.5, -14.5, -6.5, -19.0], [10.5, 14.5, 6.5, 19.0]]
		if start_grid:
			groups = [[-9.5, -14.5, -19.5, -24.0], [START_GRID_END + 6.0, START_GRID_END + 11.0, START_GRID_END + 16.0, START_GRID_END + 21.0]]
		for group_offs in groups:
			for along_off: float in group_offs:
				var cp := p + dir * along_off
				if _place_barrier_crowd_flex(cp, dir, out, half, 10.0, 3, col_idx + (1 if sgn > 0 else 0), true, true, true):
					placed_side += 1
					break
		# Tight junction / ramp fallback: still pack cheering spectators on nearby clear verges so no gate looks empty
		if placed_side == 0:
			var fallback_offs: Array = [-10.0, 10.0, -16.0, 16.0, -4.5, 4.5]
			if start_grid:
				fallback_offs = [-10.0, START_GRID_END + 7.0, -16.0, START_GRID_END + 13.0, -5.0, START_GRID_END + 3.0]
			for along_off: float in fallback_offs:
				var got := 0
				for lat_add: float in [2.0, 3.2, 4.6]:
					got = _place_crowd_cluster(p + dir * along_off + out * (half + lat_add), dir, out, 7.5, 3, float(col_idx) + along_off + sgn)
					if got >= 6:
						break
				if got >= 6:
					break
	# Optional mini fan-zone tent/merch stall if open verge exists behind the gate
	if allow_stall:
		for sgn: float in [-1.0, 1.0]:
			var tp := p + side * sgn * (half + 6.5) - dir * 5.0
			if _clear_off_road(tp, 3.6, 2.8) and map.posts_near(tp, 2.5).is_empty() and map.walls_near(tp, 2.0).is_empty():
				var face := -side * sgn
				var yaw := atan2(-face.x, -face.y)
				_stall_xfs.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(tp.x, _ground_y(tp), tp.y)))
				_stall_cols.append(_col_lin(FEST_COLORS[(col_idx + 2) % FEST_COLORS.size()]))
				map.add_post(tp, 2.1)
				break


# ================================================================================================ 5. live events

## Dynamically dresses active LiveEvents starts and finishes (inflatable arches / sponsor flags + cheering spectators
## behind barriers) whenever OpenWorld._live_sync() refreshes the live board.
func sync_live_events(board: Array) -> void:
	if _live_root == null:
		return
	for ch in _live_root.get_children():
		ch.queue_free()
	_live_crowd_zones.clear()
	if board.is_empty():
		return

	var l_arch_xfs := []
	var l_arch_cols := []
	var l_flag_xfs := []
	var l_flag_cols := []
	var l_bar_xfs := []
	var l_bar_cols := []
	var l_spec_xfs := [[], [], []]
	var l_spec_cust := [[], [], []]

	for lev in board:
		var col: Color = (lev.get("color", Color("#ff6a1a")) as Color).srgb_to_linear()
		var pts_list: Array = [[lev.pos as Vector2, Vector2(cos(float(lev.heading)), sin(float(lev.heading)))]]
		var path: PackedVector2Array = lev.get("path", PackedVector2Array())
		if path.size() >= 2:
			var goal := path[path.size() - 1]
			if goal.distance_to(lev.pos as Vector2) > 40.0:
				pts_list.append([goal, (goal - path[path.size() - 2]).normalized()])
		for ep in pts_list:
			var p: Vector2 = ep[0]
			var dir: Vector2 = ep[1]
			var near := map.nearest_road(p, 20.0)
			var half := 3.6
			if not near.is_empty():
				p = near.pos
				dir = near.dir
				half = map.road_w[int(near.road)] * 0.5
			var side := Vector2(-dir.y, dir.x)
			# Arch when legs are clear
			var leg_l := p - side * 7.2
			var leg_r := p + side * 7.2
			if _clear_off_road(leg_l, 1.6, 1.4) and _clear_off_road(leg_r, 1.6, 1.4):
				var y := minf(map.ground(leg_l.x, leg_l.y), map.ground(leg_r.x, leg_r.y)) - 0.05
				l_arch_xfs.append(Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)), Vector3(p.x, y, p.y)))
				l_arch_cols.append(col)
			else:
				for sgn: float in [-1.0, 1.0]:
					var fp := p + side * sgn * (half + 2.0)
					if _clear_off_road(fp, 1.6, 1.0):
						l_flag_xfs.append(Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)), Vector3(fp.x, _ground_y(fp), fp.y)))
						l_flag_cols.append(col)
			# Compact barrier + cheering spectator pocket off-road (no permanent wall mutation for transient events)
			for sgn: float in [-1.0, 1.0]:
				var out := side * sgn
				var bp := p + out * (half + 2.3) + dir * 3.0
				var a := bp - dir * 2.5
				var b := bp + dir * 2.5
				if not (_clear_off_road(a, 1.75, 1.0) and _clear_off_road(b, 1.75, 1.0)):
					continue
				var face := -out
				var byaw := atan2(-face.x, -face.y)
				for i in 2:
					var mid := a.lerp(b, (float(i) + 0.5) * 0.5)
					l_bar_xfs.append(Transform3D(Basis(Vector3.UP, byaw), Vector3(mid.x, _ground_y(mid), mid.y)))
					l_bar_cols.append(col)
				var cnt := 0
				for r in 2:
					for k in 7:
						var sp := a.lerp(b, (float(k) + 0.5) / 7.0) + out * (0.60 + float(r) * 0.62)
						if _spectator_spot_ok(sp):
							var pose := (k + r + (1 if sgn > 0 else 0)) % 3
							var sc := _col_lin(SHIRT_COLORS[int(_h(sp.x, sp.y, 7.1) * 997.0) % SHIRT_COLORS.size()])
							var seed_v := clampf(_h(sp.x, sp.y, 9.4), 0.01, 0.99)
							l_spec_xfs[pose].append(Transform3D(Basis(Vector3.UP, byaw + (_h(sp.x, sp.y, 2.2) - 0.5) * 0.4), Vector3(sp.x, _ground_y(sp), sp.y)))
							l_spec_cust[pose].append(Color(sc.r, sc.g, sc.b, seed_v))
							cnt += 1
				if cnt > 0:
					_live_crowd_zones.append({"pos": Vector3(bp.x, map.ground(bp.x, bp.y) + 1.5, bp.y), "weight": 0.85})

	_add_simple_mm(_live_root, "LiveArches", _prop_mesh("InflatableArch"), l_arch_xfs, l_arch_cols, ARCH_RANGE, false)
	_add_simple_mm(_live_root, "LiveFlags", _prop_mesh("SponsorFlag"), l_flag_xfs, l_flag_cols, PROP_RANGE, false)
	_add_simple_mm(_live_root, "LiveBarriers", _prop_mesh("CrowdBarrier"), l_bar_xfs, l_bar_cols, PROP_RANGE, false)
	for p_i in 3:
		if not l_spec_xfs[p_i].is_empty():
			var sm := _spectator_mesh(p_i)
			var local: Transform3D = sm[1]
			var xfs := []
			for xf in l_spec_xfs[p_i]:
				xfs.append((xf as Transform3D) * local)
			var mmi := _make_custom_mm(_live_root, "LiveSpec%d" % p_i, sm[0], xfs, l_spec_cust[p_i], spectator_mat, SPECTATOR_RANGE)
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.extra_cull_margin = 2.0


# ================================================================================================ 6. commit batches

func _commit_batches() -> void:
	# Spectators: 3 pose variants, chunked per 128 m cell, custom_data enabled, shadows OFF for max FPS
	var total_specs := _commit_people(["SpectatorsStand", "SpectatorsCheer", "SpectatorsWave"], _spec_xfs, _spec_custom, spectator_mat, _spectator_mesh)
	stats["spectators"] = total_specs
	# The organisers' executives (same shader in suit mode) and their trailers
	stats["executives"] = _commit_people(["ExecsStand", "ExecsClip", "ExecsTalk"], _exec_xfs, _exec_custom, exec_mat, _exec_mesh)
	_commit_prop_mm("OrganiserTrailers", _prop_mesh("FestTrailer"), _trailer_xfs, _trailer_cols, ARCH_RANGE, true)
	stats["trailers"] = _trailer_xfs.size()

	# Festival props: all MultiMesh chunked by 256 m cell with visibility ranges
	_commit_prop_mm("CrowdBarriers", _prop_mesh("CrowdBarrier"), _barrier_xfs, _barrier_cols, PROP_RANGE, false)
	_commit_prop_mm("SponsorFlags", _prop_mesh("SponsorFlag"), _flag_xfs, _flag_cols, PROP_RANGE, false)
	_commit_prop_mm("FestivalFlagPoles", _prop_mesh("FlagPole", TownBuilder._fallback_festival.bind("FlagPole")),
		_tall_flag_xfs, _tall_flag_cols, ARCH_RANGE, false)
	_commit_prop_mm("FestivalTents", _prop_mesh("Tent", TownBuilder._fallback_festival.bind("Tent")),
		_tent_xfs, _tent_cols, ARCH_RANGE, true)
	_commit_prop_mm("MerchStalls", _prop_mesh("MerchStall"), _stall_xfs, _stall_cols, ARCH_RANGE, true)
	_commit_prop_mm("InflatableArches", _prop_mesh("InflatableArch"), _inf_arch_xfs, _inf_arch_cols, ARCH_RANGE, true)
	_commit_prop_mm("FestivalArches", _prop_mesh("FestivalArch", TownBuilder._fallback_festival.bind("FestivalArch")),
		_fest_arch_xfs, _fest_arch_cols, ARCH_RANGE, true)
	if not _bench_xfs.is_empty() and builder.has_model("Bench"):
		_commit_prop_mm("FestivalBenches", builder.models["Bench"], _bench_xfs, [], PROP_RANGE, false)
	if not _hay_xfs.is_empty() and _hay_mesh != null:
		_commit_prop_mm("FestivalHayBales", [_hay_mesh, _hay_local], _hay_xfs, [], PROP_RANGE, false)

	stats["barriers"] = _barrier_xfs.size()
	stats["hay_bales"] = _hay_xfs.size()
	stats["flags"] = _flag_xfs.size() + _tall_flag_xfs.size()
	stats["stalls_tents"] = _stall_xfs.size() + _tent_xfs.size()
	stats["arches"] = _inf_arch_xfs.size() + _fest_arch_xfs.size()
	stats["crowd_zones"] = crowd_zones.size()

	# Bunting + cables (vertex-coloured double-sided, shadows OFF)
	var bunt_mat := StandardMaterial3D.new()
	bunt_mat.vertex_color_use_as_albedo = true
	bunt_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bunt_mat.roughness = 0.6
	for c in _bunting_cells:
		var mb: MeshBatch = _bunting_cells[c]
		if mb.is_empty():
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Bunting_%d_%d" % [c.x, c.y]
		mi.mesh = mb.commit()
		mi.material_override = bunt_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = BUNTING_RANGE
		mi.visibility_range_end_margin = 20.0
		builder._ranged.append([mi, BUNTING_RANGE])
		add_child(mi)

	# String-light bulbs (custom night-glow shader, shadows OFF)
	for c in _bulb_cells:
		var lb: MeshBatch = _bulb_cells[c]
		if lb.is_empty():
			continue
		var mi := MeshInstance3D.new()
		mi.name = "StringLights_%d_%d" % [c.x, c.y]
		mi.mesh = lb.commit()
		mi.material_override = lights_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = BUNTING_RANGE + 60.0
		mi.visibility_range_end_margin = 25.0
		builder._ranged.append([mi, BUNTING_RANGE + 60.0])
		add_child(mi)

	# Free temporary accumulators
	_spec_xfs = [[], [], []]
	_spec_custom = [[], [], []]
	_exec_xfs = [[], [], []]
	_exec_custom = [[], [], []]
	_trailer_xfs.clear(); _trailer_cols.clear()
	_barrier_xfs.clear(); _barrier_cols.clear()
	_hay_xfs.clear()
	_flag_xfs.clear(); _flag_cols.clear()
	_tall_flag_xfs.clear(); _tall_flag_cols.clear()
	_tent_xfs.clear(); _tent_cols.clear()
	_stall_xfs.clear(); _stall_cols.clear()
	_bench_xfs.clear()
	_inf_arch_xfs.clear(); _inf_arch_cols.clear()
	_fest_arch_xfs.clear(); _fest_arch_cols.clear()
	_bunting_cells.clear()
	_bulb_cells.clear()


## One animated MultiMesh per pose and 128 m cell (INSTANCE_CUSTOM = tint + seed, see spectator.gdshader); returns the head count.
func _commit_people(node_names: Array, xfs_by_pose: Array, custom_by_pose: Array, mat: ShaderMaterial, mesh_of: Callable) -> int:
	var total := 0
	for p_i in node_names.size():
		var xfs: Array = xfs_by_pose[p_i]
		total += xfs.size()
		if xfs.is_empty():
			continue
		var sm: Array = mesh_of.call(p_i)
		if sm.is_empty():
			continue
		var local: Transform3D = sm[1]
		var placed := []
		for xf in xfs:
			placed.append((xf as Transform3D) * local)
		var cells := _chunk_custom(placed, custom_by_pose[p_i], SPEC_CHUNK)
		for ci in cells.size():
			var cell: Array = cells[ci]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = false
			mm.use_custom_data = true
			mm.mesh = sm[0]
			mm.instance_count = int(cell[1])
			mm.buffer = cell[0]
			var mmi := MultiMeshInstance3D.new()
			mmi.name = node_names[p_i] if ci == 0 else "%s%d" % [node_names[p_i], ci]
			mmi.multimesh = mm
			mmi.material_override = mat
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.extra_cull_margin = 2.0
			mmi.visibility_range_end = SPECTATOR_RANGE
			mmi.visibility_range_end_margin = 20.0
			builder._ranged.append([mmi, SPECTATOR_RANGE])
			add_child(mmi)
	return total


func _commit_prop_mm(node_name: String, mesh_xf: Array, xfs: Array, cols: Array, range_end: float, shadows: bool) -> void:
	if xfs.is_empty() or mesh_xf.is_empty():
		return
	var local: Transform3D = mesh_xf[1]
	var placed := []
	for xf in xfs:
		placed.append((xf as Transform3D) * local)
	var cells := builder._chunk_cells(placed, cols, CHUNK)
	var nodes := builder._multimesh_cells(self, mesh_xf[0], cells, not cols.is_empty(), null, range_end)
	for k in nodes.size():
		nodes[k].name = node_name if k == 0 else "%s%d" % [node_name, k]
		if not shadows:
			nodes[k].cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _add_simple_mm(parent: Node3D, node_name: String, mesh_xf: Array, xfs: Array, cols: Array, range_end: float, shadows: bool) -> void:
	if xfs.is_empty() or mesh_xf.is_empty():
		return
	var local: Transform3D = mesh_xf[1]
	var placed := []
	for xf in xfs:
		placed.append((xf as Transform3D) * local)
	var mmi := builder._multimesh(parent, mesh_xf[0], placed, cols, null)
	mmi.name = node_name
	mmi.visibility_range_end = range_end
	mmi.visibility_range_end_margin = 20.0
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _make_custom_mm(parent: Node3D, node_name: String, mesh: Mesh, xfs: Array, custom: Array, mat: Material, range_end: float) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = false
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	mm.buffer = TownBuilder.instance_buffer(xfs, custom)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.visibility_range_end = range_end
	mmi.visibility_range_end_margin = 20.0
	parent.add_child(mmi)
	return mmi


static func _chunk_custom(xfs: Array, custom: Array, cell_size: float) -> Array:
	var cells := {}
	for i in xfs.size():
		var o: Vector3 = (xfs[i] as Transform3D).origin
		var c := Vector2i(int(floor(o.x / cell_size)), int(floor(o.z / cell_size)))
		if not cells.has(c):
			cells[c] = [[], []]
		cells[c][0].append(xfs[i])
		cells[c][1].append(custom[i])
	var out := []
	for c in cells:
		out.append([TownBuilder.instance_buffer(cells[c][0], cells[c][1]), cells[c][0].size()])
	return out


# ================================================================================================ 7. night fireworks

func _build_fireworks() -> void:
	_fw_rng.seed = 20261122
	var spark := BoxMesh.new()
	spark.size = Vector3(0.46, 0.46, 0.46)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.disable_fog = true
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = spark
	mm.instance_count = FW_BURSTS * FW_SPARKS
	_fw_mmi = MultiMeshInstance3D.new()
	_fw_mmi.name = "HubFireworks"
	_fw_mmi.multimesh = mm
	_fw_mmi.material_override = mat
	_fw_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fw_mmi.visibility_range_end = FIREWORK_RANGE
	_fw_mmi.visible = false
	add_child(_fw_mmi)
	for b in FW_BURSTS:
		_fw_slots.append(_new_burst(float(b) * 0.85))


func _new_burst(start_age := 0.0) -> Dictionary:
	var dirs := PackedVector3Array()
	dirs.resize(FW_SPARKS)
	for k in FW_SPARKS:
		var u := _fw_rng.randf_range(-1.0, 1.0)
		var phi := _fw_rng.randf_range(0.0, TAU)
		var r := sqrt(maxf(0.0, 1.0 - u * u))
		var spd := _fw_rng.randf_range(12.0, 22.0)
		dirs[k] = Vector3(r * cos(phi), u, r * sin(phi)) * spd
	var ox := _fw_rng.randf_range(-28.0, 28.0)
	var oz := _fw_rng.randf_range(-12.0, 32.0)
	var oy := _fw_rng.randf_range(26.0, 46.0)
	return {
		"origin": festival_pos + Vector3(ox, oy, oz),
		"color": FIREWORK_COLORS[_fw_rng.randi() % FIREWORK_COLORS.size()],
		"age": start_age,
		"life": _fw_rng.randf_range(2.2, 3.0),
		"dirs": dirs,
	}


func _update_fireworks(delta: float, car_pos: Vector3, night: float) -> void:
	if _fw_mmi == null:
		return
	var show_fw := night > 0.35 and car_pos.distance_squared_to(festival_pos) < FIREWORK_RANGE * FIREWORK_RANGE
	_fw_mmi.visible = show_fw
	if not show_fw:
		return
	var mm := _fw_mmi.multimesh
	var night_k := clampf((night - 0.35) * 2.5, 0.0, 1.0)
	var idx := 0
	for b in FW_BURSTS:
		var sl: Dictionary = _fw_slots[b]
		sl.age = float(sl.age) + delta
		if float(sl.age) >= float(sl.life):
			_fw_slots[b] = _new_burst(0.0)
			sl = _fw_slots[b]
		var t := float(sl.age)
		var frac := clampf(t / float(sl.life), 0.0, 1.0)
		var fade := pow(1.0 - frac, 1.35) * night_k
		var col: Color = sl.color
		var c_draw := Color(col.r * 3.2 * fade, col.g * 3.2 * fade, col.b * 3.2 * fade, fade)
		var origin: Vector3 = sl.origin
		var dirs: PackedVector3Array = sl.dirs
		var drag_t := (1.0 - exp(-t * 1.15)) / 1.15
		var grav := Vector3(0.0, -4.6 * t * t, 0.0)
		var scale_s := lerpf(1.45, 0.35, frac)
		for k in FW_SPARKS:
			var vel := dirs[k]
			var pos := origin + vel * drag_t + grav
			var cur_v := vel * exp(-t * 1.15) + Vector3(0.0, -9.2 * t, 0.0)
			var stretch := clampf(cur_v.length() * 0.12, 1.0, 4.0)
			var basis := Basis.from_scale(Vector3(scale_s, scale_s * stretch, scale_s))
			mm.set_instance_transform(idx, Transform3D(basis, pos))
			mm.set_instance_color(idx, c_draw)
			idx += 1


# ================================================================================================ 8. per-frame update

## Called every frame from OpenWorld._process: drives spectator shader uniforms, hub night lights,
## fireworks and proximity crowd ambience / passing cheers.
func update(delta: float, car_pos: Vector3, car_vel: Vector3, night: float, active_drive: bool) -> void:
	if spectator_mat:
		spectator_mat.set_shader_parameter("car_pos", car_pos)
		spectator_mat.set_shader_parameter("car_vel", car_vel)
	if exec_mat:
		exec_mat.set_shader_parameter("car_pos", car_pos)
		exec_mat.set_shader_parameter("car_vel", car_vel)
	var lamps_on := clampf((night - 0.35) * 3.0, 0.0, 1.0)
	if lamps_on != _lamps_shown:
		_lamps_shown = lamps_on
		for l in _hub_lights:
			l.visible = lamps_on > 0.02
			l.light_energy = 7.0 * lamps_on
	_update_fireworks(delta, car_pos, night)
	_update_audio(delta, car_pos, car_vel, active_drive)


func _update_audio(delta: float, car_pos: Vector3, car_vel: Vector3, active_drive: bool) -> void:
	if _crowd_voice == null:
		return
	if not active_drive:
		WorldAudio.fade(_crowd_voice, delta)
		return
	_cheer_cd = maxf(0.0, _cheer_cd - delta)
	_crowd_t -= delta
	if _crowd_t <= 0.0:
		_crowd_t = 0.12
		var best := 0.0
		var nearest_d := INF
		for list in [crowd_zones, _live_crowd_zones]:
			for z in list:
				var d: float = (z.pos as Vector3).distance_to(car_pos)
				if d < CROWD_HEAR:
					var falloff := 1.0 - smoothstep(CROWD_NEAR, CROWD_HEAR, d)
					best = maxf(best, falloff * float(z.weight))
					nearest_d = minf(nearest_d, d)
		_crowd_level = clampf(best, 0.0, 1.0)
		var spd := Vector2(car_vel.x, car_vel.z).length()
		if nearest_d < 22.0 and spd > 16.0 and _cheer_cd <= 0.0 and _cheer_player and _cheer_player.stream != null:
			_cheer_cd = 6.5
			_cheer_player.volume_db = CHEER_DB + linear_to_db(clampf(spd / 32.0, 0.45, 1.0))
			_cheer_player.pitch_scale = randf_range(0.94, 1.06)
			_cheer_player.play()
	WorldAudio.drive(_crowd_voice, _crowd_level, CROWD_DB, 1.0, delta, 3.0, 2.5)


func silence() -> void:
	if _crowd_voice:
		WorldAudio.fade(_crowd_voice, get_process_delta_time())


func stop_all() -> void:
	if _crowd_voice:
		_crowd_voice.gain = 0.0
		_crowd_voice.player.stop()
	if _cheer_player:
		_cheer_player.stop()
