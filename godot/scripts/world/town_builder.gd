## Builds the open-world town's 3D scene from TownMap: the terrain with its land map, ponds and streams, every
## street (markings, kerbs and pavements in town, bridges and embankments), the railway, the buildings with
## the roofs Polish houses have, woods and gardens of trees, lamps, signals, bus shelters, the mine's headframes,
## church spires, chimneys, parked cars, the festival and the event beacons. Each step is a separate call so the
## caller can show progress between them. Godot X = map x, Z = map y, Y = height above sea level.
class_name TownBuilder
extends RefCounted

const WORLD := preload("res://scripts/ui/race_world.gd")
const SURROUNDINGS := preload("res://scripts/ui/surroundings.gd")
const WORLD_ASSETS := preload("res://scripts/ui/world_assets.gd")
const GROUND_SHADER := preload("res://shaders/ground.gdshader")
const ROAD_SHADER := preload("res://shaders/town_road.gdshader")
const BUILDING_SHADER := preload("res://shaders/building.gdshader")
const FOLIAGE_SHADER := preload("res://shaders/foliage.gdshader")
const WATER_SHADER := preload("res://shaders/water.gdshader")
const VEGETATION := preload("res://scripts/world/vegetation.gd")
const TOWN_MODELS := "res://models/town.glb"
const LANDMARK_MODELS := "res://models/brzeszcze_landmarks.glb" ## tools/blender/build_brzeszcze.py
const LAND_RES := 2.5 ## metres per texel of data/world/<key>_land.png (tools/build_open_world.py)

const TERRAIN_STEP := TownMap.BED_STEP
const POND_DEPTH := TownMap.POND_DEPTH ## m: the terrain sinks this far below a pond's surface (FreeCar drives on the same bed)
const TERRAIN_CHUNK := 32 ## quads per chunk side
const CHUNK := 256.0 ## m: buildings and street batches
const TREE_CHUNK := 128.0
const SMALL_CHUNK := 128.0 ## m: cells of the distance-culled small things (fences, garden beds, parked cars)
const IMPOSTOR_CHUNK := 512.0
const TREE_NEAR := 380.0 ## m: full tree meshes this far, impostors beyond
const TREE_FAR := 1800.0
var _ranged: Array = [] ## [instance, its range at draw scale 1] for set_draw_scale
var _impostor_mat: StandardMaterial3D
var draw_scale := 1.0
const ROAD_LIFT := 0.09 ## streets sit this far over the ground; the bigger road wins at a junction
const KERB_H := TownMap.KERB_H
const PAVEMENT_W := TownMap.PAVEMENT_W
const VERGE_W := 1.2 ## m: the grass slope from a pavement's outer edge down to the lawn
const HEADFRAME_SHAFT := 10.1 ## m from town.glb's Headframe origin forward (-Z) to its shaft

## Building palettes (sRGB): Polish plaster, brick and roofing
const HOUSE_WALLS := ["#ece2c8", "#e3d3ae", "#efe6b8", "#e8c9a8", "#f0eee6", "#d2cfc6", "#cddcbc", "#e5bba2",
	"#dcbd7c", "#d8d2c4", "#f2dcc0", "#e9e3d3"]
const HOUSE_ROOFS := ["#8f3f2a", "#6b3e2e", "#4a4d52", "#36393d", "#3f4a3d", "#a5523a", "#5a3a2c", "#7a2e22"]
const FLATS_WALLS := ["#efe6d2", "#f3e1b8", "#e9d6c0", "#dfe8cf", "#f4eab0", "#efd2c4", "#ece8dc", "#e6dccb"] ## the bloki, repainted warm
const INDUSTRIAL_WALLS := ["#c9ccd0", "#aeb4b8", "#8d9ba6", "#d8dadc", "#b8b09c", "#8e4b3a", "#9a5840"]
const INDUSTRIAL_ROOFS := ["#7a7f84", "#8a8e92", "#6a6e72", "#5c4a3f"]
const KIND_CODE := {"house": 0, "flats": 1, "commercial": 7, "public": 1, "industrial": 2, "garage": 3, "shed": 3,
	"farm": 4, "church": 5}
const CAR_PAINTS := ["#c62828", "#f5f5f5", "#1e3a5f", "#2e7d32", "#9e9e9e", "#212121", "#f9a825", "#5d4037",
	"#1565c0", "#ad1457", "#b0bec5", "#e65100", "#00695c", "#8d6e63"]

var map: TownMap
var root: Node3D
var assets: RefCounted
var wet_materials: Array[ShaderMaterial] = []
var night_materials: Array[ShaderMaterial] = []
var lamp_material: StandardMaterial3D ## street lamp heads, glowing after dark
var window_glow := 0.0
var lamp_spots := PackedVector3Array() ## lamp head positions, for the pool of real lights
var lamp_dirs := PackedVector3Array()
var beacon_nodes := {} ## spot name -> Node3D
var festival_pos := Vector3.ZERO
var crossing_points: Array = [] ## [Vector2 position, road index] where a street crosses the railway at grade
var models := {} ## town.glb meshes by object name

func _init(town: TownMap, parent: Node3D) -> void:
	map = town
	root = parent
	assets = WORLD_ASSETS.new()
	_load_models()

## The prop kit (town.glb) and the hand-built Brzeszcze landmarks. Both load before build_buildings(), which
## leaves out the generic mesh of every building a landmark model stands on.
func _load_models() -> void:
	for path in [TOWN_MODELS, LANDMARK_MODELS]:
		if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
			continue
		var scene: Node = WORLD_ASSETS._load_model(path)
		if scene == null:
			continue
		for mi in scene.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh:
				# bake the node's own transform under the root into the mesh's placement
				models[String(m.name)] = [m.mesh, _global_of(m, scene)]
		scene.free()

static func _global_of(n: Node3D, top: Node) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p and p != top:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf

func has_model(name: String) -> bool:
	return models.has(name)

# ============================================================================================ mesh cache

## Set to a folder (the open world uses MESH_CACHE_DIR) to keep the meshes of the slow, mesh-only steps (terrain,
## buildings) between runs: a warm start loads them from disk in tens of milliseconds instead of rebuilding them for
## seconds. Off by default so tests always build. The stamp covers the map, the code that builds them and the models.
const MESH_CACHE_DIR := "user://open_world_cache"
const MESH_CACHE_VERSION := "1"
var mesh_cache_dir := ""
var _cache_stamp := ""

func _cache_path(tag: String) -> String:
	if mesh_cache_dir == "":
		return ""
	if _cache_stamp == "":
		var keys := models.keys()
		keys.sort()
		var parts := PackedStringArray([MESH_CACHE_VERSION, map.key, str(wall_plan_enabled), ",".join(PackedStringArray(keys))])
		# the bake, the code that builds the meshes and the models whose names and meshes they use (trees)
		for f in ["res://data/world/%s.json" % map.key, "res://scripts/world/town_builder.gd",
				"res://scripts/world/town_map.gd", "res://scripts/world/mesh_batch.gd", "res://scripts/ui/surroundings.gd",
				TOWN_MODELS, LANDMARK_MODELS, SURROUNDINGS.TREES_PATH]:
			parts.append(FileAccess.get_md5(f) if FileAccess.file_exists(f) else "-")
		# an exported game keeps neither script sources nor the source GLBs: its build stands in for them
		if not OS.has_feature("editor"):
			parts.append(str(ProjectSettings.get_setting("application/config/version", "")))
			parts.append(str(FileAccess.get_modified_time(OS.get_executable_path())))
			var pck := OS.get_executable_path().get_basename() + ".pck"
			if FileAccess.file_exists(pck):
				parts.append(str(FileAccess.get_modified_time(pck)))
		_cache_stamp = "|".join(parts).md5_text().substr(0, 16)
	return "%s/%s_%s.res" % [mesh_cache_dir, tag, _cache_stamp]

## The meshes cached for step `tag` (in the order they were stored), or [] when there are none for this stamp.
func _cached_meshes(tag: String) -> Array:
	var path := _cache_path(tag)
	if path == "" or not FileAccess.file_exists(path):
		return []
	var res := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if res == null or not res.has_meta("meshes"):
		return []
	return res.get_meta("meshes")

## Keeps step `tag`'s meshes for the next run and drops the files older stamps left for it.
func _store_meshes(tag: String, meshes: Array) -> void:
	var path := _cache_path(tag)
	if path == "":
		return
	DirAccess.make_dir_recursive_absolute(mesh_cache_dir)
	for f in DirAccess.get_files_at(mesh_cache_dir):
		if f.begins_with(tag + "_") and mesh_cache_dir.path_join(f) != path:
			DirAccess.remove_absolute(mesh_cache_dir.path_join(f))
	var res := Resource.new()
	res.set_meta("meshes", meshes)
	if ResourceSaver.save(res, path, ResourceSaver.FLAG_COMPRESS) != OK:
		push_warning("Could not cache the open world's %s at %s" % [tag, path])

## The steps in order, for the caller to run one per frame: [label, Callable].
func steps() -> Array:
	return [["Terrain", build_terrain], ["Ponds and streams", build_water], ["Streets", build_roads],
		["Railway", build_rail], ["Tunnels", build_tunnels], ["Buildings", build_buildings], ["Woods and gardens", build_trees], ["Garden fences", build_fences],
		["Fields and meadows", build_vegetation], ["Street furniture", build_props], ["Road ends", build_closures], ["Landmarks", build_landmarks], ["Horizon", build_horizon]]

static func color_lin(hex: String) -> Color:
	return Color(hex).srgb_to_linear()

static func hash2(x: float, y: float, salt: float) -> float:
	var v := sin(x * 12.9898 + y * 78.233 + salt * 37.719) * 43758.5453
	return v - floor(v)

func _surface_material(shader: Shader, folder: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("grain", WORLD.noise_texture("grain"))
	m.set_shader_parameter("grain_normal", WORLD.noise_texture("grain_normal"))
	if folder != "":
		var set: Dictionary = assets.material_set(folder)
		if not set.is_empty():
			m.set_shader_parameter("use_textures", true)
			m.set_shader_parameter("albedo_tex", set.albedo)
			if set.get("normal"):
				m.set_shader_parameter("normal_tex", set.normal)
			if set.get("roughness") and shader == GROUND_SHADER:
				m.set_shader_parameter("rough_tex", set.roughness)
				m.set_shader_parameter("has_rough_tex", true)
	wet_materials.append(m)
	return m

func _add_mesh(parent: Node3D, mesh: Mesh, mat: Material, name := "", shadows := true) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	if name != "":
		inst.name = name
	inst.mesh = mesh
	inst.material_override = mat
	if not shadows:
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(inst)
	return inst

func _group(name: String) -> Node3D:
	var n := Node3D.new()
	n.name = name
	root.add_child(n)
	return n

# ============================================================================================ terrain

func build_terrain() -> void:
	var group := _group("Terrain")
	var mat := _surface_material(GROUND_SHADER, "grass")
	mat.set_shader_parameter("base_color", Color(0.36, 0.52, 0.2))
	mat.set_shader_parameter("forest_floor_color", Color(0.17, 0.22, 0.1))
	mat.set_shader_parameter("farm_color_a", Color(0.78, 0.66, 0.3)) # ripe wheat
	mat.set_shader_parameter("farm_color_b", Color(0.42, 0.58, 0.2)) # young crops
	mat.set_shader_parameter("farm_color_c", Color(0.45, 0.34, 0.23)) # ploughed
	mat.set_shader_parameter("paved_color", Color(0.46, 0.45, 0.42))
	mat.set_shader_parameter("bare_color", Color(0.58, 0.5, 0.36))
	mat.set_shader_parameter("slope_rock", 0.4)
	# meadows take the grass's olive (vegetation.gd MEADOW_FAR), so the planted grass ends without a change of colour
	mat.set_shader_parameter("meadow_amount", 0.8)
	mat.set_shader_parameter("meadow_color", VEGETATION.MEADOW_FAR)
	mat.set_shader_parameter("meadow_dry_color", VEGETATION.MEADOW_FAR_DRY)
	var land := load("res://data/world/%s_land.png" % map.key) as Texture2D
	if land:
		mat.set_shader_parameter("use_land", true)
		mat.set_shader_parameter("land_map", land)
		mat.set_shader_parameter("land_origin", Vector2(map.tx0, map.ty0))
		mat.set_shader_parameter("land_size", Vector2(land.get_width(), land.get_height()) * LAND_RES)
	var cached := _cached_meshes("terrain")
	if not cached.is_empty():
		for mesh in cached:
			_add_mesh(group, mesh, mat, "", false)
		return
	var ex := map.extent
	var nx := int(ex.size.x / TERRAIN_STEP) + 1
	var ny := int(ex.size.y / TERRAIN_STEP) + 1
	var hs := PackedFloat32Array()
	hs.resize(nx * ny)
	for j in ny:
		for i in nx:
			var x := ex.position.x + i * TERRAIN_STEP
			var y := ex.position.y + j * TERRAIN_STEP
			var h := map.ground(x, y)
			var k := j * nx + i
			if map.bed_mask.has(k):
				h = minf(h, float(map.bed_mask[k]) - POND_DEPTH)
			hs[k] = h
	for cj in range(0, ny - 1, TERRAIN_CHUNK):
		for ci in range(0, nx - 1, TERRAIN_CHUNK):
			var mb := MeshBatch.new()
			var i1 := mini(ci + TERRAIN_CHUNK, nx - 1)
			var j1 := mini(cj + TERRAIN_CHUNK, ny - 1)
			var w := i1 - ci + 1
			for j in range(cj, j1 + 1):
				for i in range(ci, i1 + 1):
					var k := j * nx + i
					var hl := hs[j * nx + maxi(i - 1, 0)]
					var hr := hs[j * nx + mini(i + 1, nx - 1)]
					var hu := hs[maxi(j - 1, 0) * nx + i]
					var hd := hs[mini(j + 1, ny - 1) * nx + i]
					var n := Vector3(hl - hr, 2.0 * TERRAIN_STEP, hu - hd).normalized()
					var p := Vector3(ex.position.x + i * TERRAIN_STEP, hs[k], ex.position.y + j * TERRAIN_STEP)
					mb.vertex(p, n, Vector2(p.x, p.z))
			for j in range(j1 - cj):
				for i in range(i1 - ci):
					var a := j * w + i
					# counter-clockwise seen from above (x east, z south): a, a+w, a+w+1, a+1
					mb.quad(a, a + w, a + w + 1, a + 1)
			var inst := _add_mesh(group, mb.commit(), mat)
			inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if mesh_cache_dir != "":
		_store_meshes("terrain", group.get_children().map(func(n): return (n as MeshInstance3D).mesh))

# ============================================================================================ water

func build_water() -> void:
	var group := _group("Water")
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	mat.set_shader_parameter("ripples", WORLD.noise_texture("ripples"))
	mat.set_shader_parameter("deep_color", Color("#1b4752"))
	mat.set_shader_parameter("shallow_color", Color("#2f6b66"))
	mat.set_shader_parameter("choppy", 0.3)
	var batches := {}
	for k in map.water_rings.size():
		var ring := map.water_rings[k]
		var level := map.water_level[k] + 0.05
		var tris := Geometry2D.triangulate_polygon(ring)
		if tris.is_empty():
			continue
		var c := _chunk_of(ring[0])
		if not batches.has(c):
			batches[c] = MeshBatch.new()
		var mb: MeshBatch = batches[c]
		for t in range(0, tris.size(), 3):
			var p0 := ring[tris[t]]
			var p1 := ring[tris[t + 1]]
			var p2 := ring[tris[t + 2]]
			mb.flat_tri(Vector3(p0.x, level, p0.y), Vector3(p1.x, level, p1.y), Vector3(p2.x, level, p2.y), Vector3.UP,
				Vector2(0.5, 0.5), Vector2(0.5, 0.5), Vector2(0.5, 0.5), Color.WHITE)
	# streams and ditches: a ribbon a little below the banks, following the ground
	for ww in map.raw.get("waterways", []):
		var width: float = ww[0]
		var pts := TownMap._flat(ww[1])
		if pts.size() < 2:
			continue
		var c := _chunk_of(pts[0])
		if not batches.has(c):
			batches[c] = MeshBatch.new()
		var mb: MeshBatch = batches[c]
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var side := Vector2(-(b - a).y, (b - a).x).normalized() * width * 0.5
			var ya := map.ground(a.x, a.y) - 0.35
			var yb := map.ground(b.x, b.y) - 0.35
			mb.flat_quad(Vector3(a.x - side.x, ya, a.y - side.y), Vector3(a.x + side.x, ya, a.y + side.y),
				Vector3(b.x + side.x, yb, b.y + side.y), Vector3(b.x - side.x, yb, b.y - side.y), Vector3.UP, Color.WHITE,
				[Vector2(0.5, 0.5), Vector2(0.5, 0.5), Vector2(0.5, 0.5), Vector2(0.5, 0.5)])
	for c in batches:
		_add_mesh(group, (batches[c] as MeshBatch).commit(), mat, "", false)

func _chunk_of(p: Vector2, size := CHUNK) -> Vector2i:
	return Vector2i(int(floor(p.x / size)), int(floor(p.y / size)))

# ============================================================================================ streets

## Marking style per road class (town_road.gdshader UV2.y).
func _style(ri: int) -> int:
	var kind := map.road_kind[ri]
	if kind.begins_with("motorway") or kind == "trunk":
		return 3
	if kind in ["primary", "secondary", "tertiary"]:
		return 2 if map.road_oneway[ri] == 0 else 3
	if kind in ["unclassified", "residential"] and map.road_w[ri] >= 5.0 and map.road_oneway[ri] == 0:
		return 1
	return 0

const BRIDGE_GIRDER_DEPTH := 0.45 ## m the two girders hang under a road bridge's soffit
const BRIDGE_GIRDER_WIDTH := 0.6
const BRIDGE_GIRDER_CLEAR := 3.0 ## m of deck over the ground before the girders are drawn (lower decks: a plain slab)
const BRIDGE_CAP_DEPTH := 0.6 ## m, the cross-head on a pier

func build_roads() -> void:
	var group := _group("Streets")
	var mat := _surface_material(ROAD_SHADER, "asphalt")
	var kerb_mat := StandardMaterial3D.new()
	kerb_mat.vertex_color_use_as_albedo = true
	kerb_mat.roughness = 0.9
	var deck_mat := StandardMaterial3D.new()
	deck_mat.vertex_color_use_as_albedo = true
	deck_mat.roughness = 0.85
	var bank_mat := _surface_material(GROUND_SHADER, "grass")
	bank_mat.set_shader_parameter("base_color", Color(0.34, 0.5, 0.19))
	bank_mat.set_shader_parameter("slope_rock", 0.0)
	var road_b := {}
	var kerb_b := {}
	var deck_b := {}
	var bank_b := {}
	# the widest road meeting each junction (pavements and markings stop short of it)
	var node_width := {}
	var node_roads := {}
	for ri in map.road_pts.size():
		for m in map.road_marks[ri]:
			var nid := str(m[1])
			node_width[nid] = maxf(float(node_width.get(nid, 0.0)), map.road_w[ri])
			node_roads[nid] = int(node_roads.get(nid, 0)) + 1
	for ri in map.road_pts.size():
		var pts := map.road_pts[ri]
		var n := pts.size()
		if n < 2:
			continue
		var c := _chunk_of(pts[n / 2])
		if not road_b.has(c):
			road_b[c] = MeshBatch.new(true, true)
			kerb_b[c] = MeshBatch.new(false, true)
			deck_b[c] = MeshBatch.new(false, true)
			bank_b[c] = MeshBatch.new()
		var mb: MeshBatch = road_b[c]
		var half := map.road_w[ri] * 0.5
		var lift := ROAD_LIFT + map.road_rank[ri] * 0.006
		var style := _style(ri)
		var surf: float = [0.0, 0.5, 1.0][clampi(map.road_surface[ri], 0, 2)]
		var lanes := float(map.road_lanes[ri]) / 8.0
		var oneway := float(map.road_oneway[ri])
		var zs := map.road_z[ri]
		# arc length, and the distance to the nearest junction for the markings
		var s := PackedFloat32Array()
		s.resize(n)
		for i in range(1, n):
			s[i] = s[i - 1] + pts[i].distance_to(pts[i - 1])
		var jd := PackedFloat32Array()
		jd.resize(n)
		jd.fill(INF)
		var junction_ix := []
		for m in map.road_marks[ri]:
			var nid := str(m[1])
			if int(node_roads.get(nid, 0)) >= 2:
				junction_ix.append([int(m[0]), float(node_width[nid]) * 0.5])
		for i in n:
			for jm in junction_ix:
				jd[i] = minf(jd[i], absf(s[i] - s[jm[0]]) - jm[1])
		var left := PackedVector3Array()
		var right := PackedVector3Array()
		left.resize(n)
		right.resize(n)
		var base := mb.verts.size()
		for i in n:
			var t := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
			var nrm := Vector2(-t.y, t.x) # right of travel (x east, y south)
			var deck := zs[i] if not zs.is_empty() else 0.0
			var lp := pts[i] - nrm * half
			var rp := pts[i] + nrm * half
			var hl: float
			var hr: float
			if deck > 0.3:
				var hc := map.ground(pts[i].x, pts[i].y) + deck + lift
				hl = hc
				hr = hc
			else:
				hl = map.ground(lp.x, lp.y) + deck + lift
				hr = map.ground(rp.x, rp.y) + deck + lift
			left[i] = Vector3(lp.x, hl, lp.y)
			right[i] = Vector3(rp.x, hr, rp.y)
			var show := clampf((jd[i] - 1.5) / 4.0, 0.0, 1.0)
			var col := Color(show, surf, lanes, oneway)
			var up := Vector3(0.0, 1.0, 0.0)
			mb.vertex(left[i], up, Vector2(-half, s[i]), Vector2(half, style), col)
			mb.vertex(right[i], up, Vector2(half, s[i]), Vector2(half, style), col)
		for i in n - 1:
			var a := base + 2 * i
			# seen from above (north up) with travel to the east, left_i is top left and right_i bottom left:
			# left_i, right_i, right_i+1, left_i+1 is the counter-clockwise order quad() wants
			mb.quad(a, a + 1, a + 3, a + 2)
		# raised stretches: a bridge deck with parapets, or an earth embankment down to the ground
		if not zs.is_empty():
			var db: MeshBatch = deck_b[c]
			var bb: MeshBatch = bank_b[c]
			var bridge := map.road_bridge[ri] == 1
			# whether segment k of the deck has girders under it (a deck, not an embankment, standing clear of the ground)
			var has_girders := func(k: int) -> bool:
				if k < 0 or k >= n - 1:
					return false
				var lo := minf(zs[k], zs[k + 1])
				return lo > BRIDGE_GIRDER_CLEAR and (bridge or lo > 4.0)
			for side: float in [-1.0, 1.0]:
				var edge: PackedVector3Array = left if side < 0.0 else right
				for i in n - 1:
					var d0 := zs[i]
					var d1 := zs[i + 1]
					if d0 < 0.25 and d1 < 0.25:
						continue
					var e0: Vector3 = edge[i]
					var e1: Vector3 = edge[i + 1]
					var t2 := Vector2(e1.x - e0.x, e1.z - e0.z).normalized()
					var out := Vector3(-t2.y, 0.0, t2.x) * side
					var g0 := map.ground(e0.x, e0.z) - 0.5
					var g1 := map.ground(e1.x, e1.z) - 0.5
					if bridge or (d0 > 4.0 and d1 > 4.0):
						var concrete := Color(0.62, 0.61, 0.58)
						db.flat_quad(e0 + out * 0.4 - Vector3.UP * 0.9, e1 + out * 0.4 - Vector3.UP * 0.9,
							e1 + out * 0.4 + Vector3.UP * 0.95, e0 + out * 0.4 + Vector3.UP * 0.95, out, concrete)
						db.flat_quad(e0 + Vector3.UP * 0.95, e1 + Vector3.UP * 0.95, e1 + out * 0.4 + Vector3.UP * 0.95,
							e0 + out * 0.4 + Vector3.UP * 0.95, Vector3.UP, concrete)
						db.flat_quad(e1, e0, e0 + Vector3.UP * 0.95, e1 + Vector3.UP * 0.95, -out, concrete.darkened(0.08))
						# underside: each side's half of the soffit, from under its parapet to the centre line (one slab
						# each, not two over the whole width in one plane), and where the deck stands clear of the ground
						# a girder under each half, so from below it reads as a beam bridge, not a floating sheet
						# the inner edge is the centre line's own vertex (shared by both halves and both neighbouring
						# segments), not e - out * half, which on a bend leaves a wedge of sky between the segments
						var down := Vector3.UP * 0.9
						var soffit := concrete.darkened(0.3)
						var m0 := (left[i] + right[i]) * 0.5
						var m1 := (left[i + 1] + right[i + 1]) * 0.5
						# (each slab runs 5 cm into its neighbours: the outer corners, offset per segment, don't meet)
						var lap := Vector3(t2.x, 0.0, t2.y) * 0.05
						db.flat_quad(e0 + out * 0.4 - down - lap, e1 + out * 0.4 - down + lap, m1 - down + lap, m0 - down - lap,
							Vector3.DOWN, soffit)
						var girders: bool = has_girders.call(i)
						if girders:
							var gd := Vector3.UP * BRIDGE_GIRDER_DEPTH
							var gc0 := e0.lerp(m0, 0.5) - down
							var gc1 := e1.lerp(m1, 0.5) - down
							var gw := out * (BRIDGE_GIRDER_WIDTH * 0.5)
							var girder := concrete.darkened(0.22)
							var tuck := Vector3.UP * 0.03 # the sides start inside the slab: no seam of sky along the top
							db.flat_quad(gc0 + gw + tuck, gc1 + gw + tuck, gc1 + gw - gd, gc0 + gw - gd, out, girder)
							db.flat_quad(gc1 - gw + tuck, gc0 - gw + tuck, gc0 - gw - gd, gc1 - gw - gd, -out, girder)
							db.flat_quad(gc0 + gw - gd, gc1 + gw - gd, gc1 - gw - gd, gc0 - gw - gd, Vector3.DOWN, soffit)
							# close the girder's end where the next segment has none
							var t3 := Vector3(t2.x, 0.0, t2.y)
							if not has_girders.call(i - 1):
								db.flat_quad(gc0 - gw, gc0 + gw, gc0 + gw - gd, gc0 - gw - gd, -t3, girder)
							if not has_girders.call(i + 1):
								db.flat_quad(gc1 + gw, gc1 - gw, gc1 - gw - gd, gc1 + gw - gd, t3, girder)
						if side > 0.0 and map.has_pier(ri, i):
							var cpt := (left[i] + right[i]) * 0.5
							var cg := map.ground(cpt.x, cpt.z)
							var cap_top := cpt.y - 0.9 - (BRIDGE_GIRDER_DEPTH if girders else 0.0)
							var cap_lo := maxf(cap_top - BRIDGE_CAP_DEPTH, cg)
							# the pier (its footprint is TownMap's pier collision) up to a cross-head under the girders
							# beam() runs a to b, so the pier spans 0.7 m either side along the road: 1.4 m square, not a 1 cm sheet
							db.beam(Vector3(cpt.x - t2.x * 0.7, cg - 0.5, cpt.z - t2.y * 0.7), Vector3(cpt.x + t2.x * 0.7, cg - 0.5, cpt.z + t2.y * 0.7), 1.4,
								cap_lo - cg + 0.5, concrete.darkened(0.15))
							if cap_top - cap_lo > 0.1:
								var across := (right[i] - left[i])
								across.y = 0.0
								var ha := across.normalized() * (half + 0.2)
								var ca := Vector3(cpt.x - ha.x, cap_lo, cpt.z - ha.z)
								var cb := Vector3(cpt.x + ha.x, cap_lo, cpt.z + ha.z)
								db.beam(ca, cb, 1.2, cap_top - cap_lo, concrete.darkened(0.12))
								var along := Vector3(t2.x, 0.0, t2.y) * 0.6
								db.flat_quad(ca - along, cb - along, cb + along, ca + along, Vector3.DOWN, soffit) # beam() has no bottom
					else:
						# grassy embankment at 1:1.5
						var w0 := maxf(0.5, (e0.y - g0) * 1.5)
						var w1 := maxf(0.5, (e1.y - g1) * 1.5)
						var b0 := e0 + out * w0
						var b1 := e1 + out * w1
						b0.y = map.ground(b0.x, b0.z) - 0.3
						b1.y = map.ground(b1.x, b1.z) - 0.3
						var nrm3 := (e1 - e0).cross(b0 - e0).normalized()
						if nrm3.y < 0.0:
							nrm3 = -nrm3
						bb.flat_quad(e0, e1, b1, b0, nrm3, Color.WHITE)
	for c in road_b:
		_add_mesh(group, (road_b[c] as MeshBatch).commit(), mat, "", false)
		if not (kerb_b[c] as MeshBatch).is_empty():
			_add_mesh(group, (kerb_b[c] as MeshBatch).commit(), kerb_mat)
		if not (deck_b[c] as MeshBatch).is_empty():
			_add_mesh(group, (deck_b[c] as MeshBatch).commit(), deck_mat)
		if not (bank_b[c] as MeshBatch).is_empty():
			_add_mesh(group, (bank_b[c] as MeshBatch).commit(), bank_mat)
	_build_junction_patches(group, mat, node_width, node_roads)
	_build_pavements(group, kerb_mat, bank_mat)

## The pavements: TownMap's merged shapes, flat at kerb height over the street surface. A kerb face drops to the
## carriageway; every other edge runs down to the grass in a short verge (grass material), so the slab never stands
## proud of the lawn like a concrete barrier.
func _build_pavements(group: Node3D, kerb_mat: Material, verge_mat: Material) -> void:
	var batches := {}
	var verges := {}
	var top_y := ROAD_LIFT + 0.03 + KERB_H
	for poly in map.pave_polys:
		var c := _chunk_of(poly[0])
		if not batches.has(c):
			batches[c] = MeshBatch.new(false, true)
		var kb: MeshBatch = batches[c]
		var tris := Geometry2D.triangulate_polygon(poly)
		for t in range(0, tris.size(), 3):
			var v: Array[Vector3] = []
			var cen := Vector2.ZERO
			for k in 3:
				var q := poly[tris[t + k]]
				cen += q / 3.0
				v.append(Vector3(q.x, map.ground(q.x, q.y) + top_y, q.y))
			var pc := Color(0.38, 0.37, 0.35) if hash2(floorf(cen.x / 3.0), floorf(cen.y / 3.0), 4.0) > 0.5 else Color(0.34, 0.33, 0.32)
			kb.flat_tri(v[0], v[1], v[2], Vector3.UP, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, pc)
		var sign_ := 1.0 if TownMap._area_of(poly) > 0.0 else -1.0
		var np := poly.size()
		# each edge: its outward normal and what it gets (0 nothing, 1 kerb face, 2 plain face, 3 grass verge)
		var nrm := PackedVector2Array()
		var kind := PackedByteArray()
		nrm.resize(np)
		kind.resize(np)
		for k in np:
			var a := poly[k]
			var b := poly[(k + 1) % np]
			var d := b - a
			kind[k] = 0
			if d.length_squared() < 1e-4:
				continue
			var n2 := Vector2(d.y, -d.x).normalized() * sign_
			nrm[k] = n2
			var mid := (a + b) * 0.5
			# clipping can leave zero-width slits (an edge out and straight back): no pavement inside, so no face
			var inner := mid - n2 * 0.1
			if map.kerb_at(inner.x, inner.y) == 0.0:
				continue
			if not map.road_at(mid.x, mid.y, -INF, 0.35).is_empty():
				kind[k] = 1
				continue
			var vo := mid + n2 * VERGE_W
			kind[k] = 3 if map.road_at(vo.x, vo.y, -INF, 0.2).is_empty() and map.kerb_at(vo.x, vo.y) == 0.0 else 2
		# where two verge edges meet, both use one mitred foot so the slopes join rather than overlap or gap
		var foot := PackedVector2Array()
		foot.resize(np)
		for k in np:
			var kp := (k - 1 + np) % np
			if kind[k] == 3 and kind[kp] == 3:
				var dir := (nrm[k] + nrm[kp]).normalized()
				foot[k] = poly[k] + dir * VERGE_W / maxf(dir.dot(nrm[k]), 0.6)
			else:
				foot[k] = poly[k] + (nrm[k] if kind[k] == 3 else nrm[kp]) * VERGE_W
		for k in np:
			if kind[k] == 0:
				continue
			var k1 := (k + 1) % np
			var a := poly[k]
			var b := poly[k1]
			var ta := Vector3(a.x, map.ground(a.x, a.y) + top_y, a.y)
			var tb := Vector3(b.x, map.ground(b.x, b.y) + top_y, b.y)
			if kind[k] == 3:
				# a grass verge from the pavement's edge down into the lawn
				if not verges.has(c):
					verges[c] = MeshBatch.new()
				var oa := foot[k] if kind[(k - 1 + np) % np] == 3 else a + nrm[k] * VERGE_W
				var ob := foot[k1] if kind[k1] == 3 else b + nrm[k] * VERGE_W
				var ga := Vector3(oa.x, map.ground(oa.x, oa.y) - 0.04, oa.y)
				var gb := Vector3(ob.x, map.ground(ob.x, ob.y) - 0.04, ob.y)
				var vn := (tb - ta).cross(ga - ta).normalized()
				if vn.y < 0.0:
					vn = -vn
				(verges[c] as MeshBatch).flat_quad(ta, tb, gb, ga, vn, Color.WHITE)
				continue
			var n2 := nrm[k]
			var col := Color(0.5, 0.49, 0.47) if kind[k] == 1 else Color(0.36, 0.35, 0.33)
			var ba := Vector3(a.x, map.ground(a.x, a.y) - 0.2, a.y)
			var bb := Vector3(b.x, map.ground(b.x, b.y) - 0.2, b.y)
			kb.flat_quad(ta, tb, bb, ba, Vector3(n2.x, 0.0, n2.y), col)
	for c in batches:
		_add_mesh(group, (batches[c] as MeshBatch).commit(), kerb_mat)
	for c in verges:
		_add_mesh(group, (verges[c] as MeshBatch).commit(), verge_mat)

## A disc of plain asphalt over each junction, so the meeting streets' ends and corners join up.
func _build_junction_patches(group: Node3D, mat: Material, node_width: Dictionary, node_roads: Dictionary) -> void:
	var batches := {}
	var node_lift := {}
	var node_deck := {}
	for ri in map.road_pts.size():
		for m in map.road_marks[ri]:
			var nid := str(m[1])
			node_lift[nid] = maxf(float(node_lift.get(nid, 0.0)), ROAD_LIFT + map.road_rank[ri] * 0.006)
			if map.road_z[ri].size() > int(m[0]):
				node_deck[nid] = maxf(float(node_deck.get(nid, 0.0)), map.road_z[ri][int(m[0])])
	for nid in node_roads:
		if int(node_roads[nid]) < 2 or not map.node_pos.has(nid):
			continue
		var p: Vector2 = map.node_pos[nid]
		var r := float(node_width[nid]) * 0.5 + 0.6
		var c := _chunk_of(p)
		if not batches.has(c):
			batches[c] = MeshBatch.new(true, true)
		var mb: MeshBatch = batches[c]
		var deck := float(node_deck.get(nid, 0.0))
		var y := map.ground(p.x, p.y) + float(node_lift[nid]) + 0.004 + deck
		var col := Color(0.0, 0.0, 0.125, 0.0)
		var center := mb.vertex(Vector3(p.x, y, p.y), Vector3.UP, Vector2(0.0, 0.0), Vector2(r, 0.0), col)
		var seg := 14
		var first := mb.verts.size()
		for k in seg:
			var a := TAU * k / seg
			var q := p + Vector2(cos(a), sin(a)) * r
			var qy := y if deck > 0.3 else map.ground(q.x, q.y) + float(node_lift[nid]) + 0.004
			mb.vertex(Vector3(q.x, qy, q.y), Vector3.UP, Vector2(cos(a) * r, sin(a) * r), Vector2(r, 0.0), col)
		for k in seg:
			var a := first + k
			var b := first + (k + 1) % seg
			# angles grow clockwise seen from above (y south): centre, b, a is counter-clockwise -> reverse
			mb.tri(center, a, b)
	for c in batches:
		_add_mesh(group, (batches[c] as MeshBatch).commit(), mat, "", false)

# ============================================================================================ railway

func build_rail() -> void:
	var group := _group("Railway")
	var chunks := {} # chunk -> [ballast, steel, sleepers, bank]
	var ballast_col := Color(0.42, 0.39, 0.36)
	var rail_col := Color(0.33, 0.3, 0.28)
	var sleeper_col := Color(0.28, 0.22, 0.17)
	var rail_lines := []
	for r in map.raw.get("rail", []):
		var pts := TownMap._flat(r.p)
		var zs := PackedFloat32Array(r.get("z", []))
		var gauge := 0.75 if int(r.get("g", 0)) else 1.435
		var bw := 2.4 if int(r.get("g", 0)) else 3.6
		rail_lines.append([pts, zs])
		var n := pts.size()
		var acc := 0.0
		for i in n - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var ck := _chunk_of(a)
			if not chunks.has(ck):
				chunks[ck] = [MeshBatch.new(false, true), MeshBatch.new(false, true), MeshBatch.new(false, true), MeshBatch.new()]
			var ballast: MeshBatch = chunks[ck][0]
			var steel: MeshBatch = chunks[ck][1]
			var sleepers: MeshBatch = chunks[ck][2]
			var bank: MeshBatch = chunks[ck][3]
			var t := (b - a).normalized()
			var nrm := Vector2(-t.y, t.x)
			var za := (zs[i] if not zs.is_empty() else 0.0)
			var zb := (zs[i + 1] if not zs.is_empty() else 0.0)
			# the bed and the embankment as TownMap.rail_section gives them (the car rides the same surfaces)
			var sec := map.rail_section(a, b, za, zb, bw)
			var A: Vector3 = (sec.ballast[0][0] + sec.ballast[0][3]) * 0.5
			var B: Vector3 = (sec.ballast[0][1] + sec.ballast[0][2]) * 0.5
			var side := Vector3(nrm.x, 0.0, nrm.y)
			var bq: Array = sec.ballast
			ballast.flat_quad(bq[0][0], bq[0][1], bq[0][2], bq[0][3], Vector3.UP, ballast_col)
			ballast.flat_quad(bq[1][0], bq[1][1], bq[1][2], bq[1][3], (side + Vector3.UP).normalized(), ballast_col.darkened(0.1))
			ballast.flat_quad(bq[2][0], bq[2][1], bq[2][2], bq[2][3], (-side + Vector3.UP).normalized(), ballast_col.darkened(0.1))
			for g: float in [-1.0, 1.0]:
				var o: Vector3 = side * gauge * 0.5 * g
				steel.beam(A + o + Vector3.UP * 0.08, B + o + Vector3.UP * 0.08, 0.08, 0.14, rail_col)
			# sleepers every 0.65 m, as flat dark bars on the ballast
			var seg := a.distance_to(b)
			var d := fmod(0.65 - fmod(acc, 0.65), 0.65)
			while d < seg:
				var f := d / seg
				var q := A.lerp(B, f) + Vector3.UP * 0.02
				var hw := side * (gauge * 0.5 + 0.45)
				var ht := Vector3(t.x, 0.0, t.y) * 0.13
				sleepers.flat_quad(q - hw - ht, q - hw + ht, q + hw + ht, q + hw - ht, Vector3.UP, sleeper_col)
				d += 0.65
			acc += seg
			# embankments under raised track
			for q in sec.bank:
				var e0: Vector3 = q[0]
				var e1: Vector3 = q[1]
				var b0: Vector3 = q[3]
				var nn := (e1 - e0).cross(b0 - e0).normalized()
				if nn.y < 0.0:
					nn = -nn
				_bank_quad(bank, e0, e1, q[2], b0, nn, (a + b) * 0.5)
	var mat_v := StandardMaterial3D.new()
	mat_v.vertex_color_use_as_albedo = true
	mat_v.roughness = 0.95
	var steel_mat := StandardMaterial3D.new()
	steel_mat.vertex_color_use_as_albedo = true
	steel_mat.metallic = 0.85
	steel_mat.roughness = 0.35
	var bank_mat := _surface_material(GROUND_SHADER, "grass")
	bank_mat.set_shader_parameter("base_color", Color(0.34, 0.5, 0.19))
	for ck in chunks:
		var parts: Array = chunks[ck]
		_add_mesh(group, (parts[0] as MeshBatch).commit(), mat_v, "", false)
		var sl := _add_mesh(group, (parts[2] as MeshBatch).commit(), mat_v, "", false)
		sl.visibility_range_end = 260.0
		var rl := _add_mesh(group, (parts[1] as MeshBatch).commit(), steel_mat, "", false)
		rl.visibility_range_end = 700.0
		if not (parts[3] as MeshBatch).is_empty():
			_add_mesh(group, (parts[3] as MeshBatch).commit(), bank_mat)
	_find_level_crossings(rail_lines)

## One slope of a railway embankment, with the cut a street's underpass makes through it (TownMap.in_tunnel_cut:
## between the wing walls, from foot to foot of the embankment) clipped out exactly, so the slope's cut edge lies in
## the wing wall's plane. The quad is drawn as flat_quad draws it (two triangles e0 e1 b1, e0 b1 b0, which is what
## TownMap.rail_bank() holds the car up on), each triangle cut down to the pieces outside the strip.
func _bank_quad(bank: MeshBatch, e0: Vector3, e1: Vector3, b1: Vector3, b0: Vector3, nn: Vector3, mid: Vector2) -> void:
	var cut := []
	for t in map.tunnels:
		if (t.c as Vector2).distance_to(mid) < float(t.cut_len) + 16.0:
			cut.append(t)
	if cut.is_empty():
		bank.flat_quad(e0, e1, b1, b0, nn, Color.WHITE)
		return
	var polys := [[e0, e1, b1], [e0, b1, b0]]
	for t in cut:
		var c: Vector2 = t.c
		var v: Vector2 = t.v
		var n := Vector2(-v.y, v.x)
		var ch := float(t.cut_half)
		var cl := float(t.cut_len)
		# the strip's complement as four convex pieces (keep where (p - c) . dir >= k for each [dir, k])
		var pieces := [[[n, ch]], [[-n, ch]], [[n, -ch], [-n, -ch], [v, cl]], [[n, -ch], [-n, -ch], [-v, cl]]]
		var kept := []
		for poly in polys:
			for piece in pieces:
				var q: Array = poly
				for hp in piece:
					q = _clip_half(q, c, hp[0], float(hp[1]))
					if q.size() < 3:
						break
				if q.size() >= 3:
					kept.append(q)
		polys = kept
	for poly in polys:
		for k in range(1, poly.size() - 1):
			bank.flat_tri(poly[0], poly[k], poly[k + 1], nn, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Color.WHITE)

## Sutherland-Hodgman: the part of polygon poly (Vector3, map x = X, y = Z) where (p - c) . dir >= k, heights
## interpolated along the cut edges (the polygon is planar, so the piece lies in its plane).
func _clip_half(poly: Array, c: Vector2, dir: Vector2, k: float) -> Array:
	var out := []
	var m := poly.size()
	for i in m:
		var p: Vector3 = poly[i]
		var q: Vector3 = poly[(i + 1) % m]
		var fp := (Vector2(p.x, p.z) - c).dot(dir) - k
		var fq := (Vector2(q.x, q.z) - c).dot(dir) - k
		if fp >= 0.0:
			out.append(p)
		if (fp >= 0.0) != (fq >= 0.0):
			out.append(p.lerp(q, fp / (fp - fq)))
	return out

## Where a street crosses the railway at grade (for the barriers and the crossing signs).
func _find_level_crossings(rail_lines: Array) -> void:
	for line in rail_lines:
		var pts: PackedVector2Array = line[0]
		var zs: PackedFloat32Array = line[1]
		for i in pts.size() - 1:
			if not zs.is_empty() and maxf(zs[i], zs[i + 1]) > 0.5:
				continue # the railway is on a bridge or embankment here: the street passes under it
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var mid := (a + b) * 0.5
			var hit := map.road_at(mid.x, mid.y, -INF, 6.0)
			if hit.is_empty():
				continue
			var ri: int = hit.road
			if map.road_rank[ri] < 2 or not map.road_z[ri].is_empty():
				continue
			var rp := map.road_pts[ri]
			var j: int = hit.i
			var cross = Geometry2D.segment_intersects_segment(a, b, rp[j], rp[j + 1])
			if cross == null:
				continue
			var dup := false
			for c in crossing_points:
				if (c[0] as Vector2).distance_to(cross) < 15.0:
					dup = true
			if not dup:
				crossing_points.append([cross, ri, (b - a).normalized(), j])

# ============================================================================================ tunnels

## The underpasses (TownMap.tunnels): the street runs through the railway embankment in a lined concrete bore under the
## deck, with a portal (a header beam over the opening and wing walls that follow the slope down to the ground) at each end.
func build_tunnels() -> void:
	if map.tunnels.is_empty():
		return
	var group := _group("Tunnels")
	var concrete := StandardMaterial3D.new()
	concrete.vertex_color_use_as_albedo = true
	concrete.roughness = 0.92
	concrete.cull_mode = BaseMaterial3D.CULL_DISABLED
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp_mat.albedo_color = Color(1.0, 0.9, 0.62)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.82, 0.45)
	lamp_mat.emission_energy_multiplier = 2.5
	lamp_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mb := MeshBatch.new(false, true)
	var lb := MeshBatch.new()
	var face := Color(0.64, 0.63, 0.6)
	var lining := Color(0.27, 0.27, 0.28)
	for t in map.tunnels:
		var c: Vector2 = t.c
		var v: Vector2 = t.v
		var n := Vector2(-v.y, v.x)
		var hb: float = t.half_bore
		var hf: float = t.half_foot
		var hw: float = float(t.w) * 0.5 + 0.2
		var deck_top: float = t.top # the highest track's rail level: the header beam's top
		var roof: float = deck_top - 0.9
		var at := func(s: float, l: float, y: float) -> Vector3:
			var q := c + v * s + n * l
			return Vector3(q.x, y, q.y)
		var lo := func(s: float, l: float) -> float:
			var q := c + v * s + n * l
			return map.ground(q.x, q.y) - 0.3
		# roof underside and the header beams that close the bore's ends
		mb.flat_quad(at.call(-hb, -hw - 0.3, roof), at.call(hb, -hw - 0.3, roof), at.call(hb, hw + 0.3, roof),
			at.call(-hb, hw + 0.3, roof), Vector3.DOWN, lining.darkened(0.3))
		# the deck's top under the ballast: between the tracks and at the header's edge it is what shows from above,
		# not the open cut
		mb.flat_quad(at.call(-hb, hw + 0.3, deck_top - 0.4), at.call(hb, hw + 0.3, deck_top - 0.4), at.call(hb, -hw - 0.3, deck_top - 0.4),
			at.call(-hb, -hw - 0.3, deck_top - 0.4), Vector3.UP, face.darkened(0.15))
		for e: float in [-1.0, 1.0]:
			mb.flat_quad(at.call(e * hb, -hw - 0.3, roof), at.call(e * hb, hw + 0.3, roof), at.call(e * hb, hw + 0.3, deck_top),
				at.call(e * hb, -hw - 0.3, deck_top), Vector3(v.x, 0.0, v.y) * e, face)
			# a darker band along the lintel: the portal's frame
			mb.flat_quad(at.call(e * (hb + 0.02), -hw - 0.3, roof), at.call(e * (hb + 0.02), hw + 0.3, roof),
				at.call(e * (hb + 0.02), hw + 0.3, roof + 0.35), at.call(e * (hb + 0.02), -hw - 0.3, roof + 0.35),
				Vector3(v.x, 0.0, v.y) * e, face.darkened(0.25))
		# walls: lining inside the bore, concrete wing walls outside it in the plane the embankment is cut along
		# (TownMap.in_tunnel_cut), their top a hand over the slope as drawn (TownMap.rail_bank), down to the foot
		var steps := []
		var k := -hf
		while k < hf - 0.01:
			if absf(absf(k) - hb) > 0.05:
				steps.append(k)
			k += 1.0
		steps.append(-hb)
		steps.append(hb)
		steps.append(hf)
		steps.sort()
		for sd: float in [-1.0, 1.0]:
			var l := hw * sd
			var top_at := func(s: float) -> float:
				var q := c + v * s + n * l
				return maxf(map.rail_bank(q.x, q.y, true) + 0.08, map.ground(q.x, q.y) + 0.1)
			for j in steps.size() - 1:
				var s0: float = steps[j]
				var s1: float = steps[j + 1]
				if s1 - s0 < 0.01:
					continue
				var inside := absf((s0 + s1) * 0.5) < hb
				var top0: float = roof if inside else top_at.call(s0)
				var top1: float = roof if inside else top_at.call(s1)
				var col := lining if inside else face
				var nrm := Vector3(n.x, 0.0, n.y) * -sd
				mb.flat_quad(at.call(s0, l, lo.call(s0, l)), at.call(s1, l, lo.call(s1, l)), at.call(s1, l, top1),
					at.call(s0, l, top0), nrm, col)
		# strip lights along the roof
		var ls := -hb + 1.2
		while ls < hb - 0.5:
			lb.flat_quad(at.call(ls, -0.5, roof - 0.03), at.call(ls + 0.35, -0.5, roof - 0.03), at.call(ls + 0.35, 0.5, roof - 0.03),
				at.call(ls, 0.5, roof - 0.03), Vector3.DOWN, Color.WHITE)
			ls += 2.4
		var light := OmniLight3D.new()
		light.name = "TunnelLight"
		light.light_color = Color(1.0, 0.86, 0.6)
		light.light_energy = 1.6
		light.omni_range = maxf(hb, 6.0) + 6.0
		light.shadow_enabled = false
		light.position = at.call(0.0, 0.0, roof - 0.5)
		group.add_child(light)
	_add_mesh(group, mb.commit(), concrete, "Portals")
	_add_mesh(group, lb.commit(), lamp_mat, "TunnelLamps", false)

# ============================================================================================ buildings

## How far (metres) the current building's walls stand out from their footprint; see _wall_pushes().
var _push := 0.0

## Terraced houses, garages and sheds put walls in one plane facing one way. Both draw, they z-fight, and each
## has its own window layout, so patches of facade flip with every camera move.
## Where two such walls lie within SHARED_TOL of one plane, the lower building (the later one on a tie) does not
## draw its wall over the stretch the taller one covers: it is recorded as a cut in _cuts, which _wall() honours.
## Walls that are close to coplanar but not quite (up to 0.25 m) still stand out: the lower building (the later one
## on a tie) steps a few centimetres out, one step further per building it hides.
const SHARED_TOL := 0.04 ## m: walls this near one plane count as the same face
var wall_plan_enabled := true ## tests switch it off to see the raw overlaps
var log_walls := false ## tests set it to collect every wall rectangle drawn into wall_log
var wall_log: Array = [] ## [building, a, b, bottom at a, bottom at b, top at a, top at b, outward] in map x, y
var _cuts := {} ## building -> [[a, b, s0, s1, y0, y1, covered_to], ...] stretches of its wall edge a-b that are not drawn
var _cur_bi := -1

func _wall_pushes(skip := {}) -> Dictionary:
	return _wall_plan(skip).push

## Absolute base and eave heights of building bi, as _add_building will place them.
func _bld_range(bi: int) -> Vector2:
	var ring := map.bld_rings[bi]
	var lo := INF
	var hi := -INF
	for p in ring:
		var g := map.ground(p.x, p.y)
		lo = minf(lo, g)
		hi = maxf(hi, g)
	var b: Array = map.buildings[bi]
	var extra: Dictionary = b[6] if b.size() > 6 and b[6] is Dictionary else {}
	return Vector2(lo - 0.5, hi + float(extra.get("eh", b[1])))

## skip: {building index: true} for buildings that are not drawn (landmark models, shaft houses): they hide nothing.
func _wall_plan(skip := {}) -> Dictionary:
	_cuts = {}
	if not wall_plan_enabled:
		return {"push": {}, "cuts": _cuts}
	var edges: Array = []
	var cells := {}
	for bi in map.buildings.size():
		var ring := map.bld_rings[bi]
		if ring.size() < 3 or skip.has(bi):
			continue
		for we in _wall_edges(bi, ring):
			var a: Vector2 = we[0]
			var b: Vector2 = we[1]
			var ln := a.distance_to(b)
			if ln < 0.1:
				continue
			var t := (b - a) / ln
			var out: Vector2 = we[2]
			var ei := edges.size()
			edges.append([bi, a, t, ln, out, float(we[3]), float(we[4])])
			# every 10 m cell the edge passes through, so a long wall meets a neighbour beside any part of it
			var steps := int(ln / 5.0) + 1
			var seen := {}
			for k in steps + 1:
				var q := a + t * (ln * float(k) / float(steps))
				var cell := Vector2i(floori(q.x * 0.1), floori(q.y * 0.1))
				if seen.has(cell):
					continue
				seen[cell] = true
				if not cells.has(cell):
					cells[cell] = []
				cells[cell].append(ei)
	var below := {} # building -> buildings that hide part of its wall
	var done := {}
	var ranges := {}
	for cell: Vector2i in cells:
		for ei: int in cells[cell]:
			var e: Array = edges[ei]
			var near: Array = [] # edges sampled in this cell or one beside it (samples are 5 m apart, cells 10 m)
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					near.append_array(cells.get(cell + Vector2i(dx, dy), []))
			for oi: int in near:
				var o: Array = edges[oi]
				if o[0] <= e[0] or (e[4] as Vector2).dot(o[4]) < 0.99:
					continue
				var pair := ei * 1000003 + oi
				if done.has(pair):
					continue
				var ea: Vector2 = e[1]
				var et: Vector2 = e[2]
				var nrm := Vector2(-et.y, et.x)
				var oa: Vector2 = o[1]
				var ob: Vector2 = oa + (o[2] as Vector2) * float(o[3])
				var da := (oa - ea).dot(nrm)
				var db := (ob - ea).dot(nrm)
				if absf(da) > 0.25 or absf(db) > 0.25:
					continue
				var s0: float = (oa - ea).dot(et)
				var s1: float = (ob - ea).dot(et)
				var lo := maxf(0.0, minf(s0, s1))
				var hi := minf(float(e[3]), maxf(s0, s1))
				if hi - lo < 0.1:
					continue
				done[pair] = true
				for bi in [e[0], o[0]]:
					if not ranges.has(bi):
						ranges[bi] = _bld_range(bi)
				# the one whose eave is lower where they stand (equal: the later index)
				var lower: int = e[0] if float((ranges[e[0]] as Vector2).y) < float((ranges[o[0]] as Vector2).y) else o[0]
				var upper: int = o[0] if lower == e[0] else e[0]
				if maxf(absf(da), absf(db)) <= SHARED_TOL:
					# one plane: the lower building leaves the shared stretch out
					var edge_l: Array = e if lower == e[0] else o
					var edge_u: Array = o if lower == e[0] else e
					var pa: Vector2 = ea + et * lo
					var pb: Vector2 = ea + et * hi
					var la: Vector2 = edge_l[1]
					var lt: Vector2 = edge_l[2]
					var sl0 := (pa - la).dot(lt)
					var sl1 := (pb - la).dot(lt)
					if sl0 > sl1:
						var sw := pa
						pa = pb
						pb = sw
						sl0 = (pa - la).dot(lt)
						sl1 = (pb - la).dot(lt)
					var rl: Vector2 = ranges[lower]
					var ru: Vector2 = ranges[upper]
					if not _cuts.has(lower):
						_cuts[lower] = []
					# up to the taller wall's top (it may slope with its roof), or the lower one's own top plus the
					# parapet a flat roof stands on its eave
					var y1a := minf(_edge_top(edge_u, pa), _edge_top(edge_l, pa) + 0.7)
					var y1b := minf(_edge_top(edge_u, pb), _edge_top(edge_l, pb) + 0.7)
					_cuts[lower].append([la, la + lt * float(edge_l[3]), sl0, sl1, maxf(rl.x, ru.x), y1a, y1b])
				else:
					# near but not on one plane: how far the lower wall stands in front of the upper one (negative: behind)
					var sep := (da + db) * 0.5 * signf(nrm.dot(e[4]))
					if lower != e[0]:
						sep = -sep
					if sep > -0.04:
						if not below.has(lower):
							below[lower] = {}
						below[lower][upper] = minf(float(below[lower].get(upper, INF)), sep)
	var push := {}
	for round in 6:
		for lower: int in below:
			var need := 0.0
			for upper: int in below[lower]:
				need = maxf(need, float(push.get(upper, 0.0)) + 0.04 - float(below[lower][upper]))
			push[lower] = need
	return {"push": push, "cuts": _cuts}

## Height of a plan edge's top above its point p (on the edge's line).
func _edge_top(edge: Array, p: Vector2) -> float:
	var f := clampf((p - (edge[1] as Vector2)).dot(edge[2]) / maxf(float(edge[3]), 1e-3), 0.0, 1.0)
	return lerpf(float(edge[5]), float(edge[6]), f)

## The stretches of wall a-b (either direction) of the current building that _wall_plan() leaves out, as
## [[s0, s1, y0, y1 at s0, y1 at s1], ...] with s in metres from a: the wall is not drawn from y0 up to the line y1.
func _wall_cuts_for(a: Vector2, b: Vector2) -> Array:
	var res: Array = []
	var recs: Array = _cuts.get(_cur_bi, [])
	if recs.is_empty():
		return res
	var ln := a.distance_to(b)
	for r in recs:
		var ra: Vector2 = r[0]
		var rb: Vector2 = r[1]
		if ra.distance_to(a) < 0.02 and rb.distance_to(b) < 0.02:
			res.append([r[2], r[3], r[4], r[5], r[6]])
		elif ra.distance_to(b) < 0.02 and rb.distance_to(a) < 0.02:
			res.append([ln - float(r[3]), ln - float(r[2]), r[4], r[6], r[5]])
	return res

## True if the plan leaves the whole of wall a-b out from y_from to y_to because a taller building's wall covers it.
func _parapet_covered(a: Vector2, b: Vector2, y_from: float, y_to: float) -> bool:
	var ln := a.distance_to(b)
	for c in _wall_cuts_for(a, b):
		if float(c[0]) <= 0.05 and float(c[1]) >= ln - 0.05 and float(c[2]) <= y_from + 0.01 and float(c[3]) >= y_to - 0.01 and float(c[4]) >= y_to - 0.01:
			return true
	return false

## One wall a-b (map x, y) from y_lo up to the heights top_a (at a) and top_b (at b): quads standing `_push` out of the
## plane, minus the stretches _wall_plan() cut. UV.x is metres from the wall's start, UV.y metres over `hi`; UV2 carries
## the seed, kind, the wall's length and (when the top is level) its height, which the shader turns into quoins and a
## cornice (see building.gdshader).
func _wall(mb: MeshBatch, a: Vector2, b: Vector2, y_lo: float, top_a: float, top_b: float, out: Vector3, color: Color, hi: float, seed: float, code: float) -> void:
	var ln := a.distance_to(b)
	if ln < 0.01:
		return
	var t := (b - a) / ln
	var level := absf(top_a - top_b) < 0.05
	var uv2 := Vector2(seed + (roundf((top_a - hi) * 10.0) if level else 0.0), code + 20.0 * minf(roundf(ln * 10.0), 4000.0))
	var cuts := _wall_cuts_for(a, b)
	# slice the wall at every cut boundary; within a slice a cut either covers it or it does not
	var marks := [0.0, ln]
	for c in cuts:
		for s: float in [c[0], c[1]]:
			if s > 0.01 and s < ln - 0.01:
				marks.append(s)
	marks.sort()
	var po := out * _push
	for k in marks.size() - 1:
		var s0: float = marks[k]
		var s1: float = marks[k + 1]
		if s1 - s0 < 0.01:
			continue
		var mid := (s0 + s1) * 0.5
		# each cut covering this slice as [y from at s0, at s1, y to at s0, at s1], lowest first
		var gaps: Array = []
		for c in cuts:
			if mid > c[0] and mid < c[1]:
				var span: float = maxf(float(c[1]) - float(c[0]), 1e-3)
				var ya: float = lerpf(float(c[3]), float(c[4]), (s0 - float(c[0])) / span)
				var yb: float = lerpf(float(c[3]), float(c[4]), (s1 - float(c[0])) / span)
				gaps.append([float(c[2]), float(c[2]), ya, yb])
		gaps.sort_custom(func(p, q): return p[0] < q[0])
		var ta0: float = top_a + (top_b - top_a) * s0 / ln
		var ta1: float = top_a + (top_b - top_a) * s1 / ln
		var pa := a + t * s0
		var pb := a + t * s1
		var lo_a := y_lo
		var lo_b := y_lo
		var pieces: Array = [] # [bottom at s0, bottom at s1, top at s0, top at s1]
		for g in gaps:
			if g[0] > lo_a + 0.01 or g[1] > lo_b + 0.01:
				pieces.append([lo_a, lo_b, g[0], g[1]])
			lo_a = maxf(lo_a, g[2])
			lo_b = maxf(lo_b, g[3])
		pieces.append([lo_a, lo_b, ta0, ta1])
		for pc in pieces:
			var y0a: float = pc[0]
			var y0b: float = pc[1]
			var y1a: float = pc[2]
			var y1b: float = pc[3]
			var da := y1a - y0a
			var db := y1b - y0b
			if da < 0.01 and db < 0.01:
				continue
			if da < 0.0 or db < 0.0:
				# the top dips under the bottom across this slice (a sloped cut meets a sloped top): keep the triangle where it does not
				var f := da / (da - db)
				var pcx := a + t * lerpf(s0, s1, f)
				var yc := lerpf(y0a, y0b, f)
				var tri_pts: Array = [Vector3(pcx.x, yc, pcx.y), Vector3(pb.x, y0b, pb.y), Vector3(pb.x, y1b, pb.y)] if da < 0.0 else [Vector3(pa.x, y0a, pa.y), Vector3(pcx.x, yc, pcx.y), Vector3(pa.x, y1a, pa.y)]
				var tri_s: Array = [lerpf(s0, s1, f), s1, s1] if da < 0.0 else [s0, lerpf(s0, s1, f), s0]
				var tri_y: Array = [yc, y0b, y1b] if da < 0.0 else [y0a, yc, y1a]
				mb.flat_tri(tri_pts[0] + po, tri_pts[1] + po, tri_pts[2] + po, out, Vector2(tri_s[0], tri_y[0] - hi), Vector2(tri_s[1], tri_y[1] - hi), Vector2(tri_s[2], tri_y[2] - hi), color, uv2)
				continue
			mb.flat_quad(Vector3(pa.x, y0a, pa.y) + po, Vector3(pb.x, y0b, pb.y) + po, Vector3(pb.x, y1b, pb.y) + po, Vector3(pa.x, y1a, pa.y) + po, out, color,
				[Vector2(s0, y0a - hi), Vector2(s1, y0b - hi), Vector2(s1, y1b - hi), Vector2(s0, y1a - hi)], uv2)
			if log_walls:
				wall_log.append([_cur_bi, Vector2(pa.x, pa.y) + Vector2(po.x, po.z), Vector2(pb.x, pb.y) + Vector2(po.x, po.z), y0a, y0b, y1a, y1b, Vector2(out.x, out.z)])

## The outline walls of building bi as [a, b, outward unit normal on the map, absolute top height at a, at b]: the
## footprint's edges, or for a measured (LoD2) building the roof plane edges that no other plane shares, which is where
## _add_lod2_roof builds walls.
func _wall_edges(bi: int, ring: PackedVector2Array) -> Array:
	var b: Array = map.buildings[bi]
	var extra: Dictionary = b[6] if b.size() > 6 and b[6] is Dictionary else {}
	var planes: Array[PackedVector2Array] = []
	var heights: Array[PackedFloat32Array] = [] # roof corner heights over the building's highest ground
	for face in extra.get("rs", []):
		if not face is Array or face.size() < 9:
			continue
		var pl := PackedVector2Array()
		var zs := PackedFloat32Array()
		for j in range(0, face.size() - 2, 3):
			var q := Vector2(float(face[j]), float(face[j + 1]))
			if pl.is_empty() or pl[pl.size() - 1].distance_to(q) > 0.01:
				pl.append(q)
				zs.append(float(face[j + 2]))
		if pl.size() > 2 and pl[0].distance_to(pl[pl.size() - 1]) < 0.01:
			pl.remove_at(pl.size() - 1)
			zs.remove_at(zs.size() - 1)
		if pl.size() >= 3:
			planes.append(pl)
			heights.append(zs)
	if not planes.is_empty() and extra.has("rh"):
		# the same test as _add_building: a survey that puts the ridge far over the eaves is built from the footprint
		var lod_rect := min_rect(ring)
		if not lod_rect.is_empty() and (float(extra.rh) - float(extra.get("eh", b[1]))) > 1.6 * maxf(float(lod_rect[3]), 0.5):
			planes.clear()
	# _add_building gives up measured planes that cover too little of the footprint and builds footprint walls instead
	if not planes.is_empty() and _lod2_cover(extra.get("rs", []), ring) < LOD2_MIN_COVER:
		planes.clear()
	var ground_hi := -INF
	for p in ring:
		ground_hi = maxf(ground_hi, map.ground(p.x, p.y))
	var res: Array = []
	if planes.is_empty():
		# facing from the winding, as _add_building does: the centre of an L lies outside it and turned walls inward
		var turn := -signf(ring_area(ring))
		var top := _bld_range(bi).y
		for i in ring.size():
			var d := (ring[(i + 1) % ring.size()] - ring[i]).normalized()
			res.append([ring[i], ring[(i + 1) % ring.size()], Vector2(-d.y, d.x) * turn, top, top])
		return res
	# a shared edge (ridge, hip, valley) is judged in 3D, as _add_lod2_roof does: two planes' edges can overlap on
	# the map while one is a gable wall edge far above the other
	var polys: Array[PackedVector3Array] = []
	for pi in planes.size():
		var poly := PackedVector3Array()
		for k in planes[pi].size():
			poly.append(Vector3(planes[pi][k].x, heights[pi][k], planes[pi][k].y))
		polys.append(poly)
	for pi in polys.size():
		var poly := polys[pi]
		var wind := 1.0 if ring_area(planes[pi]) > 0.0 else -1.0
		for k in poly.size():
			var a3 := poly[k]
			var c3 := poly[(k + 1) % poly.size()]
			var e2 := Vector2(c3.x - a3.x, c3.z - a3.z)
			if e2.length() < 0.05:
				continue
			var out2 := Vector2(e2.y, -e2.x).normalized() * wind
			for run in _open_runs(polys, pi, a3, c3, out2):
				var p0 := a3.lerp(c3, float(run[0]))
				var p1 := a3.lerp(c3, float(run[1]))
				res.append([Vector2(p0.x, p0.z), Vector2(p1.x, p1.z), out2, ground_hi + p0.y, ground_hi + p1.y])
	return res

## True if point p (x, height, y) on an edge of plane pi lies on an edge of another plane that continues the roof
## past it (on the side out2, the edge's outward direction on the map): a ridge, hip or valley, not an outer edge.
static func _on_other_plane_edge(polys: Array[PackedVector3Array], pi: int, p: Vector3, out2: Vector2) -> bool:
	var beyond := Vector2(p.x, p.z) + out2 * 0.2
	for pj in polys.size():
		if pj == pi:
			continue
		var other := polys[pj]
		for m in other.size():
			if Geometry3D.get_closest_point_to_segment(p, other[m], other[(m + 1) % other.size()]).distance_to(p) < 0.15:
				var flat := PackedVector2Array()
				for q in other:
					flat.append(Vector2(q.x, q.z))
				if Geometry2D.is_point_in_polygon(beyond, flat):
					return true
				break
	return false

## The stretches of plane pi's edge a-b that no other plane shares, as [[from, to], ...] fractions of a-b, where
## _add_lod2_roof stands walls. Planes need not share corners, so an edge can be a ridge or valley for part of its
## length and an outer wall for the rest; judging it by its midpoint alone left that rest open.
static func _open_runs(polys: Array[PackedVector3Array], pi: int, a: Vector3, b: Vector3, out2: Vector2) -> Array:
	var probe: Array[bool] = []
	for f in [0.05, 0.25, 0.5, 0.75, 0.95]:
		probe.append(_on_other_plane_edge(polys, pi, a.lerp(b, f), out2))
	if not probe.has(true):
		return [[0.0, 1.0]]
	# (all five on another plane's edge is not enough to skip the samples: a metre of open edge between two of them
	# would get no wall, a hole)
	var steps := maxi(4, ceili(Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z)) / 0.5))
	var open: Array[bool] = []
	for s in steps:
		open.append(not _on_other_plane_edge(polys, pi, a.lerp(b, (float(s) + 0.5) / float(steps)), out2))
	# each change between two samples is narrowed down by bisection: a step in the roof, where a higher plane's edge
	# runs over a lower one's and they meet at one corner, otherwise lost up to a whole sample (0.5 m) of wall there,
	# a sliver of sky between the planes
	var runs: Array = []
	var start := 0.0 if open[0] else -1.0
	for s in range(1, steps):
		if open[s] == open[s - 1]:
			continue
		var lo := (float(s) - 0.5) / float(steps)
		var hi := (float(s) + 0.5) / float(steps)
		for _i in 6:
			var mid := (lo + hi) * 0.5
			if (not _on_other_plane_edge(polys, pi, a.lerp(b, mid), out2)) == open[s - 1]:
				lo = mid
			else:
				hi = mid
		var cut := (lo + hi) * 0.5
		if open[s]:
			start = cut
		else:
			runs.append([start, cut])
			start = -1.0
	if start >= 0.0:
		runs.append([start, 1.0])
	return runs

func build_buildings() -> void:
	var group := _group("Buildings")
	var mat := ShaderMaterial.new()
	mat.shader = BUILDING_SHADER
	mat.set_shader_parameter("grain", WORLD.noise_texture("grain"))
	apply_building_textures(mat)
	# lighter glass that catches the sky, white frames: the bright, clean look of Forza's towns
	mat.set_shader_parameter("glass_color", Color(0.3, 0.38, 0.45))
	mat.set_shader_parameter("frame_color", Color(0.95, 0.94, 0.9))
	wet_materials.append(mat)
	night_materials.append(mat)
	var cached := _cached_meshes("buildings")
	if not cached.is_empty():
		for mesh in cached:
			_add_mesh(group, mesh, mat)
		return
	var batches := {}
	var shafts := shaft_towers()
	var not_drawn := {} # landmark models and shaft houses: their walls hide nothing behind them
	for bi in map.buildings.size():
		var b: Array = map.buildings[bi]
		var extra: Dictionary = b[6] if b.size() > 6 and b[6] is Dictionary else {}
		if (extra.has("lm") and has_model(String(extra.lm))) or shafts.hidden.has(bi):
			not_drawn[bi] = true
	var pushes := _wall_pushes(not_drawn)
	for bi in map.buildings.size():
		var b: Array = map.buildings[bi]
		var ring := map.bld_rings[bi]
		if ring.size() < 3 or not_drawn.has(bi):
			continue
		var extra: Dictionary = b[6] if b.size() > 6 and b[6] is Dictionary else {}
		var centre := Vector2.ZERO
		for p in ring:
			centre += p
		centre /= ring.size()
		var c := _chunk_of(centre)
		if not batches.has(c):
			batches[c] = MeshBatch.new(true, true)
		_push = float(pushes.get(bi, 0.0))
		_cur_bi = bi
		_add_building(batches[c], ring, String(b[0]), float(b[1]), String(b[3]), centre, extra)
	_push = 0.0
	_cur_bi = -1
	var built: Array = []
	for c in batches:
		built.append(_add_mesh(group, (batches[c] as MeshBatch).commit(), mat).mesh)
	if mesh_cache_dir != "":
		_store_meshes("buildings", built)

## The baked detail textures (tools/build_building_textures.py) building.gdshader multiplies onto its facades and roofs.
static func apply_building_textures(mat: ShaderMaterial) -> void:
	for pair in [["tex_wall", "building_wall"], ["tex_brick", "building_brick"], ["tex_roof", "building_roof"]]:
		var path := "res://textures/buildings/%s.png" % pair[1]
		if ResourceLoader.exists(path):
			mat.set_shader_parameter(pair[0], load(path))

func _palette(kind: String, seed: float, centre: Vector2) -> Array:
	var wall: String
	var roof: String
	match kind:
		"flats":
			wall = FLATS_WALLS[int(seed * 997.0) % FLATS_WALLS.size()]
			roof = "#6f7276"
		"industrial":
			wall = INDUSTRIAL_WALLS[int(seed * 997.0) % INDUSTRIAL_WALLS.size()]
			roof = INDUSTRIAL_ROOFS[int(seed * 613.0) % INDUSTRIAL_ROOFS.size()]
		"church":
			wall = "#9a4a36"
			roof = "#3d5a50" if seed > 0.5 else "#45484c"
		"commercial", "public":
			wall = ["#e9e4d8", "#dfe6ea", "#efe2c4", "#d6d0c6", "#e8d8b0"][int(seed * 97.0) % 5]
			roof = "#6a6d70"
		"garage", "shed":
			wall = ["#b9b4aa", "#a8a397", "#c9c2b2", "#8f8a80", "#9c6b4a"][int(seed * 97.0) % 5]
			roof = ["#5a5d60", "#7a3a2a", "#4d4f52"][int(seed * 61.0) % 3]
		"farm":
			wall = ["#9b5a3f", "#b8a88c", "#c9bba0", "#8e4b3a"][int(seed * 97.0) % 4]
			roof = HOUSE_ROOFS[int(seed * 61.0) % HOUSE_ROOFS.size()]
		_:
			wall = HOUSE_WALLS[int(seed * 997.0) % HOUSE_WALLS.size()]
			roof = HOUSE_ROOFS[int(seed * 613.0) % HOUSE_ROOFS.size()]
	return [color_lin(wall), color_lin(roof)]

## The minimum-area rectangle round a ring: [centre, axis (unit, along the long side), half long, half short].
static func min_rect(ring: PackedVector2Array) -> Array:
	var best := []
	var best_area := INF
	for k in ring.size():
		var a := ring[k]
		var b := ring[(k + 1) % ring.size()]
		var ax := (b - a)
		if ax.length_squared() < 1e-6:
			continue
		ax = ax.normalized()
		var ay := Vector2(-ax.y, ax.x)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p in ring:
			var q := Vector2(p.dot(ax), p.dot(ay))
			lo = lo.min(q)
			hi = hi.max(q)
		var area := (hi.x - lo.x) * (hi.y - lo.y)
		if area < best_area:
			best_area = area
			var mid := (lo + hi) * 0.5
			var centre := ax * mid.x + ay * mid.y
			var hx := (hi.x - lo.x) * 0.5
			var hy := (hi.y - lo.y) * 0.5
			if hx >= hy:
				best = [centre, ax, hx, hy, area]
			else:
				best = [centre, ay, hy, hx, area]
	return best

static func ring_area(ring: PackedVector2Array) -> float:
	var a := 0.0
	for i in ring.size():
		var p := ring[i]
		var q := ring[(i + 1) % ring.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5

func _add_building(mb: MeshBatch, ring: PackedVector2Array, kind: String, height: float, roof_shape: String, centre: Vector2, extra: Dictionary = {}) -> void:
	var r := ring.duplicate()
	# counter-clockwise seen from above (x east, z south) means negative shoelace area here
	if ring_area(r) > 0.0:
		r.reverse()
	var seed := hash2(centre.x, centre.y, 13.0)
	var pal := _palette(kind, seed, centre)
	var wall: Color = pal[0]
	var roof: Color = pal[1]
	if extra.has("wc"):
		wall = color_lin(String(extra.wc))
	if extra.has("rc"):
		roof = color_lin(String(extra.rc))
	var code: int = KIND_CODE.get(kind, 0)
	var lo := INF
	var hi := -INF
	for p in r:
		var g := map.ground(p.x, p.y)
		lo = minf(lo, g)
		hi = maxf(hi, g)
	var base := lo - 0.5
	var eave_height := float(extra.get("eh", height))
	var eave := hi + eave_height
	var roof_surfaces: Array = extra.get("rs", [])
	if kind == "church" and roof_surfaces.is_empty() and absf(ring_area(r)) < 80.0:
		eave_height = minf(eave_height, 3.5)
		eave = hi + eave_height
		if not extra.has("wc"):
			wall = color_lin("#dfd9cb")
		if not extra.has("rc"):
			roof = color_lin("#38322c")
	var uv2_wall := Vector2(seed, code)
	var uv2_roof := Vector2(seed, code + 10.0)
	# pitched roofs over footprints close to a rectangle
	var rect := []
	var pitched := roof_shape in ["hipped", "gabled", "pyramidal", "half_hipped", "mansard"] and height < 18.0
	if not roof_surfaces.is_empty() and extra.has("rh"):
		# a survey that puts the ridge 5 m over the eaves of a 4 m wide shed raised a tower of wall; build it from the footprint
		var lod_rect := min_rect(r)
		if not lod_rect.is_empty() and (float(extra.rh) - eave_height) > 1.6 * maxf(float(lod_rect[3]), 0.5):
			roof_surfaces = []
	if not roof_surfaces.is_empty():
		# LoD2 roof planes: map x, y and a height over the building's highest ground
		# measured planes that leave a good part of the footprint uncovered would show the sky through the roof
		# (a tall wall with no gable over it): build the OSM walls and a roof of our own instead
		var mark := mb.mark()
		if _lod2_cover(roof_surfaces, r) >= LOD2_MIN_COVER \
				and _add_lod2_roof(mb, roof_surfaces, hi, base, roof, wall, uv2_roof, uv2_wall):
			return
		mb.rollback(mark) # a roof given up half way leaves nothing behind
		roof_surfaces = [] # unusable planes: the OSM walls and a roof of our own
	if roof_surfaces.is_empty() and pitched:
		rect = min_rect(r)
		if rect.is_empty() or absf(ring_area(r)) / maxf(float(rect[4]), 1e-3) < PITCHED_MIN_FIT or float(rect[3]) > 13.0:
			pitched = false
	var n := r.size()
	for i in n:
		var a := r[i]
		var b := r[(i + 1) % n]
		var ln := a.distance_to(b)
		if ln < 0.01:
			continue
		# r runs clockwise on the map (negative shoelace area), so the outside is always on this side of a-b; the
		# centre of a concave (L, U, T) footprint can lie outside it and would turn walls inward, culled from outside
		var out := Vector3(-(b.y - a.y), 0.0, b.x - a.x).normalized()
		_wall(mb, a, b, base, eave, eave, out, wall, hi, seed, float(code))
	if pitched and roof_surfaces.is_empty():
		var cen: Vector2 = rect[0]
		var ax: Vector2 = rect[1]
		var ay := Vector2(-ax.y, ax.x)
		var hl: float = rect[2] + 0.45 # eaves overhang
		var hw: float = rect[3] + 0.45
		var pitch := 0.62 + 0.25 * hash2(centre.x, centre.y, 5.0) # rise per run
		if extra.has("rh") and float(extra.rh) > eave_height:
			pitch = clampf((float(extra.rh) - eave_height) / maxf(hw, 0.5), 0.08, 1.4)
		var rise := hw * pitch
		var c4 := [cen - ax * hl - ay * hw, cen + ax * hl - ay * hw, cen + ax * hl + ay * hw, cen - ax * hl + ay * hw]
		var q := []
		for p in c4:
			q.append(Vector3(p.x, eave, p.y))
		var top := eave + rise
		if roof_shape == "pyramidal" or hl - hw < 0.6:
			var apex := Vector3(cen.x, top, cen.y)
			for k in 4:
				var p0: Vector3 = q[k]
				var p1: Vector3 = q[(k + 1) % 4]
				var nn := (p1 - p0).cross(apex - p0).normalized()
				if nn.y < 0.0:
					nn = -nn
				mb.flat_tri(p0, p1, apex, nn, Vector2(0, 0), Vector2(p0.distance_to(p1), 0), Vector2(p0.distance_to(p1) * 0.5, hw), roof, uv2_roof)
		elif roof_shape in ["hipped", "half_hipped", "mansard"]:
			var r1 := cen - ax * (hl - hw)
			var r2 := cen + ax * (hl - hw)
			var R1 := Vector3(r1.x, top, r1.y)
			var R2 := Vector3(r2.x, top, r2.y)
			for side in [[q[0], q[1], R2, R1], [q[2], q[3], R1, R2]]:
				var nn: Vector3 = (side[1] - side[0]).cross(side[3] - side[0]).normalized()
				if nn.y < 0.0:
					nn = -nn
				var sl: float = (side[0] as Vector3).distance_to(side[1])
				mb.flat_quad(side[0], side[1], side[2], side[3], nn, roof,
					[Vector2(0, 0), Vector2(sl, 0), Vector2(sl - hw, hw * 1.2), Vector2(hw, hw * 1.2)], uv2_roof)
			for tri in [[q[1], q[2], R2], [q[3], q[0], R1]]:
				var nn: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
				if nn.y < 0.0:
					nn = -nn
				mb.flat_tri(tri[0], tri[1], tri[2], nn, Vector2(0, 0), Vector2(hw * 2.0, 0), Vector2(hw, hw * 1.2), roof, uv2_roof)
		else:
			# gabled: ridge along the long axis, walls up into the gable ends
			var m1 := cen - ax * hl
			var m2 := cen + ax * hl
			var R1 := Vector3(m1.x, top, m1.y)
			var R2 := Vector3(m2.x, top, m2.y)
			for side in [[q[0], q[1], R2, R1], [q[2], q[3], R1, R2]]:
				var nn: Vector3 = (side[1] - side[0]).cross(side[3] - side[0]).normalized()
				if nn.y < 0.0:
					nn = -nn
				var sl: float = (side[0] as Vector3).distance_to(side[1])
				mb.flat_quad(side[0], side[1], side[2], side[3], nn, roof,
					[Vector2(0, 0), Vector2(sl, 0), Vector2(sl, hw * 1.2), Vector2(0, hw * 1.2)], uv2_roof)
			for tri in [[q[3], q[0], R1], [q[1], q[2], R2]]:
				var nn: Vector3 = Vector3((tri[1] - tri[0]).z, 0.0, -(tri[1] - tri[0]).x).normalized()
				var mid3: Vector3 = (tri[0] + tri[1]) * 0.5
				if nn.dot(Vector3(mid3.x - cen.x, 0.0, mid3.z - cen.y)) < 0.0:
					nn = -nn
				mb.flat_tri(tri[0], tri[1], tri[2], nn, Vector2(0, eave - hi), Vector2(hw * 2.0, eave - hi), Vector2(hw, eave - hi + rise), wall, uv2_wall)
		# soffit under the overhang so the eaves don't look paper-thin from below
		mb.flat_quad(q[0], q[3], q[2], q[1], Vector3.DOWN, wall.darkened(0.35))
	elif roof_surfaces.is_empty():
		var tris := Geometry2D.triangulate_polygon(r)
		var parapet := 0.0
		if kind in ["flats", "industrial", "commercial", "public"]:
			parapet = 0.6
		for k in range(0, tris.size(), 3):
			var a := r[tris[k]]
			var b := r[tris[k + 1]]
			var cc := r[tris[k + 2]]
			mb.flat_tri(Vector3(a.x, eave, a.y), Vector3(b.x, eave, b.y), Vector3(cc.x, eave, cc.y), Vector3.UP, a, b, cc, roof, uv2_roof)
		if parapet > 0.0:
			for i in n:
				var a := r[i]
				var b := r[(i + 1) % n]
				var t := (b - a).normalized()
				var inn := Vector2(t.y, -t.x) # inward, from the ring's winding (see the walls above)
				var ai := a + inn * 0.3
				var bi := b + inn * 0.3
				mb.flat_quad(Vector3(ai.x, eave, ai.y), Vector3(bi.x, eave, bi.y), Vector3(bi.x, eave + parapet, bi.y),
					Vector3(ai.x, eave + parapet, ai.y), Vector3(inn.x, 0.0, inn.y), wall.darkened(0.1),
					[Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], Vector2(seed, 3.0))
				mb.flat_quad(Vector3(a.x, eave + parapet, a.y), Vector3(b.x, eave + parapet, b.y), Vector3(bi.x, eave + parapet, bi.y),
					Vector3(ai.x, eave + parapet, ai.y), Vector3.UP, wall.darkened(0.2),
					[Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], Vector2(seed, 3.0))
				var out := -inn
				if _parapet_covered(a, b, eave, eave + parapet):
					continue # a taller neighbour's wall stands in this plane right over it
				mb.flat_quad(Vector3(a.x, eave, a.y), Vector3(b.x, eave, b.y), Vector3(b.x, eave + parapet, b.y),
					Vector3(a.x, eave + parapet, a.y), Vector3(out.x, 0.0, out.y), wall,
					[Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], Vector2(seed, 3.0))

const LOD2_MIN_COVER := 0.85 ## share of the footprint (sampled) the measured roof planes must lie over; below it we build our own roof, so no wall is left open to the sky
const PITCHED_MIN_FIT := 0.92 ## footprint area / bounding rectangle area a pitched roof needs; looser fits leave roof overhanging where the walls are not, and gaps where they are

## The share of the footprint `ring` that lies under at least one roof plane (map x, y, height triples), by a
## grid of sample points. Overlapping planes count once, and planes belonging to a neighbour count for nothing.
static func _lod2_cover(faces: Array, ring: PackedVector2Array) -> float:
	var polys: Array[PackedVector2Array] = []
	for face in faces:
		if not face is Array or face.size() < 9:
			continue
		var poly := PackedVector2Array()
		for j in range(0, face.size() - 2, 3):
			poly.append(Vector2(float(face[j]), float(face[j + 1])))
		polys.append(poly)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in ring:
		lo = lo.min(p)
		hi = hi.max(p)
	var step := maxf(maxf(hi.x - lo.x, hi.y - lo.y) / 14.0, 0.4) # ~150 points over the box, so thin or L-shaped houses still get a dozen or more inside
	var inside := 0
	var covered := 0
	var y := lo.y + step * 0.5
	while y < hi.y:
		var x := lo.x + step * 0.5
		while x < hi.x:
			var pt := Vector2(x, y)
			if Geometry2D.is_point_in_polygon(pt, ring):
				inside += 1
				for poly in polys:
					if Geometry2D.is_point_in_polygon(pt, poly):
						covered += 1
						break
			x += step
		y += step
	return float(covered) / float(inside) if inside > 0 else 1.0

## A measured (GUGiK LoD2) roof: each plane triangulated in its own plane, and walls from the ground up to
## every roof edge that no other plane shares, so the walls meet the eaves and gables of the roof exactly.
## False if the planes are unusable (the caller builds the OSM walls and roof instead).
func _add_lod2_roof(mb: MeshBatch, faces: Array, hi: float, base: float, roof: Color, wall: Color, uv2_roof: Vector2, uv2_wall: Vector2) -> bool:
	var polys: Array[PackedVector3Array] = []
	for face in faces:
		if not face is Array or face.size() < 9:
			continue
		var poly := PackedVector3Array()
		for j in range(0, face.size() - 2, 3):
			var q := Vector3(float(face[j]), hi + float(face[j + 2]), float(face[j + 1]))
			if poly.is_empty() or poly[poly.size() - 1].distance_to(q) > 0.01:
				poly.append(q)
		if poly.size() > 2 and poly[0].distance_to(poly[poly.size() - 1]) < 0.01:
			poly.remove_at(poly.size() - 1)
		if poly.size() >= 3:
			polys.append(poly)
	if polys.is_empty():
		return false
	var drawn := 0
	for poly in polys:
		# Newell normal, then a 2D frame in the plane (a steep plane projected on the ground would fold up)
		var nrm := Vector3.ZERO
		for k in poly.size():
			var a := poly[k]
			var b := poly[(k + 1) % poly.size()]
			nrm += Vector3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
		if nrm.length() < 1e-4:
			return false # a degenerate plane: same, fall back
		nrm = nrm.normalized()
		if nrm.y < 0.0:
			nrm = -nrm
		var ax := Vector3.UP.cross(nrm)
		if ax.length() < 0.05:
			ax = Vector3.RIGHT
		ax = ax.normalized()
		var ay := nrm.cross(ax)
		var flat := PackedVector2Array()
		for q in poly:
			flat.append(Vector2(q.dot(ax), q.dot(ay)))
		# tile UVs run along the eave (u) and up the slope (v), both in metres in the plane, from the plane's lowest
		# corner: the roof texture's courses then follow the eave on every plane, whichever way the building faces
		var corner := Vector2(INF, INF)
		for q in flat:
			corner = corner.min(q)
		var tris := Geometry2D.triangulate_polygon(flat)
		if tris.is_empty():
			tris = Geometry2D.triangulate_delaunay(flat)
		if tris.is_empty():
			return false # a plane we cannot draw would leave a hole its walls still reach up to: use our own roof
		for j in range(0, tris.size(), 3):
			var ia: int = tris[j]
			var ib: int = tris[j + 1]
			var ic: int = tris[j + 2]
			var p0 := poly[ia]
			var p1 := poly[ib]
			var p2 := poly[ic]
			if (p1 - p0).cross(p2 - p0).length() < 1e-4:
				continue
			mb.flat_tri(p0, p1, p2, nrm, flat[ia] - corner, flat[ib] - corner, flat[ic] - corner, roof, uv2_roof)
			drawn += 1
	if drawn == 0:
		return false
	# outline edges: the stretches of a plane's edge that no other plane's edge runs along (not ridges, hips or valleys)
	for pi in polys.size():
		var poly := polys[pi]
		# the plane's winding on the map says which side of each edge is outside (its centre can lie outside a concave plane)
		var flat2 := PackedVector2Array()
		for q in poly:
			flat2.append(Vector2(q.x, q.z))
		var wind := 1.0 if ring_area(flat2) > 0.0 else -1.0
		for k in poly.size():
			var a := poly[k]
			var b := poly[(k + 1) % poly.size()]
			var a2 := Vector2(a.x, a.z)
			var b2 := Vector2(b.x, b.z)
			var ln := a2.distance_to(b2)
			if ln < 0.05:
				continue # a vertical edge: the walls either side carry it
			var t := (b2 - a2) / ln
			var out := Vector3(t.y, 0.0, -t.x) * wind
			for run in _open_runs(polys, pi, a, b, Vector2(out.x, out.z)):
				var p0 := a.lerp(b, float(run[0]))
				var p1 := a.lerp(b, float(run[1]))
				_wall(mb, Vector2(p0.x, p0.z), Vector2(p1.x, p1.z), base, p0.y, p1.y, out, wall, hi, uv2_wall.x, uv2_wall.y)
	return true

# ============================================================================================ trees

## Tree kinds from the baker: 0 mapped, 1 row, 2 needle wood, 3 broadleaf wood, 4 mixed wood, 5 park,
## 6 garden, 7 scrub, 8 allotment.
const KIND_SPECIES := {
	0: {"Broadleaf": 0.6, "Birch": 0.4}, 1: {"Poplar": 0.5, "Broadleaf": 0.5},
	2: {"Pine": 0.85, "Spruce": 0.1, "Birch": 0.05}, 3: {"Broadleaf": 0.7, "Birch": 0.3},
	4: {"Pine": 0.45, "Broadleaf": 0.3, "Birch": 0.15, "Spruce": 0.1}, 5: {"Broadleaf": 0.7, "Birch": 0.2, "Spruce": 0.1},
	6: {"Broadleaf": 0.45, "Birch": 0.25, "Spruce": 0.2, "Poplar": 0.1}, 7: {"Broadleaf": 0.6, "Birch": 0.4},
	8: {"Broadleaf": 1.0}}
const KIND_SCALE := {0: 1.0, 1: 1.0, 2: 1.05, 3: 1.0, 4: 1.0, 5: 0.95, 6: 0.75, 7: 0.45, 8: 0.5}

func build_trees() -> void:
	var group := _group("Trees")
	var meshes: Dictionary = SURROUNDINGS.tree_meshes()
	var foliage := ShaderMaterial.new()
	foliage.shader = FOLIAGE_SHADER
	foliage.set_shader_parameter("grain", WORLD.noise_texture("grain"))
	foliage.set_shader_parameter("linear_colors", true)
	wet_materials.append(foliage)
	var impostor_mat := _impostor_material()
	_impostor_mat = impostor_mat
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.center_offset = Vector3(0.0, 0.5, 0.0)
	var cached := _cached_meshes("trees")
	if not cached.is_empty():
		for rec in cached: # [species ("" for the far cards), instance buffer, count]
			_add_trees(group, rec[0], rec[1], rec[2], meshes, foliage, quad, impostor_mat)
		return
	var trees: Array = map.raw.get("trees", [])
	# chunk -> species -> [transforms, tints]; and chunk -> impostor [transforms, tints]
	var near := {}
	var far := {}
	for k in range(0, trees.size(), 3):
		var x: float = trees[k]
		var y: float = trees[k + 1]
		var kind := int(trees[k + 2])
		var r := hash2(x, y, 3.0)
		var species := _pick(KIND_SPECIES.get(kind, KIND_SPECIES[0]), r)
		if not meshes.has(species):
			species = "Broadleaf"
		var size := (0.72 + hash2(x, y, 5.0) * 0.5) * float(KIND_SCALE.get(kind, 1.0))
		var tall := size * (0.9 + hash2(x, y, 7.0) * 0.25)
		var g := map.ground(x, y) - 0.25
		var c := _chunk_of(Vector2(x, y), TREE_CHUNK)
		var cf := _chunk_of(Vector2(x, y), IMPOSTOR_CHUNK)
		if not near.has(c):
			near[c] = {}
		if not far.has(cf):
			far[cf] = [[], []]
		if not near[c].has(species):
			near[c][species] = [[], []]
		var basis := Basis(Vector3.UP, hash2(x, y, 6.0) * TAU).scaled(Vector3(size, tall, size))
		var tint := 0.82 + hash2(x, y, 8.0) * 0.3
		var col := Color(tint * (0.94 + hash2(x, y, 9.0) * 0.12), tint, tint * (0.88 + hash2(x, y, 10.0) * 0.16))
		near[c][species][0].append(Transform3D(basis, Vector3(x, g, y)))
		near[c][species][1].append(col)
		var dims := _tree_dims(species)
		var imp_basis := Basis.from_scale(Vector3(dims.x * 2.0 * size, dims.y * tall, 1.0))
		far[cf][0].append(Transform3D(imp_basis, Vector3(x, g, y)))
		var leaf := _species_colour(species)
		far[cf][1].append(Color(leaf.r * tint, leaf.g * tint, leaf.b * tint, 1.0))
	var recs: Array = []
	for c in near:
		for species in near[c]:
			var lists: Array = near[c][species]
			recs.append([species, instance_buffer(lists[0], lists[1]), lists[0].size()])
	for cf in far:
		recs.append(["", instance_buffer(far[cf][0], far[cf][1]), far[cf][0].size()])
	for rec in recs:
		_add_trees(group, rec[0], rec[1], rec[2], meshes, foliage, quad, impostor_mat)
	if mesh_cache_dir != "":
		_store_meshes("trees", recs)

## One chunk's trees of one species (full meshes near the camera), or with species "" one big chunk's far cards
## (few draw calls; the shader drops the cards near the camera, where the real trees stand).
func _add_trees(group: Node3D, species: String, buf: PackedFloat32Array, count: int, meshes: Dictionary, foliage: Material,
		quad: Mesh, impostor_mat: Material) -> void:
	if species != "":
		var mmi := _multimesh_buffer(group, meshes[species], buf, count, true, foliage)
		mmi.visibility_range_end = TREE_NEAR
		mmi.visibility_range_end_margin = 40.0
		_ranged.append([mmi, TREE_NEAR])
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	else:
		var imp := _multimesh_buffer(group, quad, buf, count, true, impostor_mat)
		imp.visibility_range_end = TREE_FAR + IMPOSTOR_CHUNK
		_ranged.append([imp, TREE_FAR + IMPOSTOR_CHUNK])
		imp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## Plot fences are baked as short independent segments so gaps remain clear for driveways.
## Fence segments that a longer, parallel one within 0.8 m already covers (a mapped barrier next to a generated
## plot boundary): both would draw, and their panels cross like a double fence. Returns {index: true}.
func _doubled_fences(walls: Array) -> Dictionary:
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

func build_fences() -> void:
	var group := _group("Garden Fences")
	var fence := _model("Fence", _fallback_fence)
	var xfs := []
	var walls: Array = map.raw.get("fences", [])
	var doubled := _doubled_fences(walls)
	for wi in walls.size():
		if doubled.has(wi):
			continue
		var w: Array = walls[wi]
		var a := Vector2(float(w[0]), float(w[1]))
		var b := Vector2(float(w[2]), float(w[3]))
		var d := b - a
		var length := d.length()
		if length < 0.35:
			continue
		var style := int(w[4]) if w.size() > 4 else 0
		if style == 2 or style == 4:
			continue # hedge rows use the bush mesh below instead of metal panels
		var piece := 2.5
		var count := maxi(1, int(ceil(length / piece)))
		for i in count:
			var start := length * float(i) / count
			var span := length / count
			var p := a + d.normalized() * start
			var scale_y := 0.68 if style == 2 else (0.9 if style == 3 else 1.0)
			var basis := Basis(Vector3.UP, atan2(-d.y, d.x)).scaled_local(Vector3(span / 2.5, scale_y, 1.0)) # the panel runs along +X
			xfs.append(Transform3D(basis, Vector3(p.x, map.ground(p.x, p.y), p.y)))
	_place_many(group, "PlotFencePanels", fence, xfs, [], null, 280.0)
	# Low shrubs on selected boundaries soften the hard edges and make garden rows read from the street.
	var roadside: Node = WORLD_ASSETS._load_model("res://models/roadside.glb")
	if roadside:
		var bush: Mesh = null
		for mi in roadside.find_children("BushCluster", "MeshInstance3D", true, false):
			bush = (mi as MeshInstance3D).mesh
			break
		if bush:
			var bushes := []
			for wi in range(0, walls.size(), 2):
				var w: Array = walls[wi]
				if int(w[4]) != 2:
					continue
				var a := Vector2(float(w[0]), float(w[1]))
				var b := Vector2(float(w[2]), float(w[3]))
				var d := b - a
				var steps := int(d.length() / 8.0)
				for j in steps:
					var p := a + d * ((float(j) + 0.5) / maxf(1.0, float(steps))) + Vector2(-d.y, d.x).normalized() * 0.9
					var s := 0.7 + hash2(p.x, p.y, 17.0) * 0.45
					bushes.append(Transform3D(Basis(Vector3.UP, hash2(p.x, p.y, 19.0) * TAU).scaled(Vector3.ONE * s), Vector3(p.x, map.ground(p.x, p.y), p.y)))
			_multimesh_chunked(group, bush, bushes, [], null, 320.0)
		roadside.free()
	# Simple dark soil rectangles inside home gardens and the mapped allotments.
	var bed_mesh := BoxMesh.new()
	bed_mesh.size = Vector3.ONE
	var soil := StandardMaterial3D.new()
	soil.albedo_color = Color(0.22, 0.14, 0.075)
	soil.roughness = 1.0
	var beds := []
	for bed in map.raw.get("garden_beds", []):
		var p := Vector2(float(bed[0]), float(bed[1]))
		var basis := Basis(Vector3.UP, float(bed[2])).scaled_local(Vector3(float(bed[3]), 0.12, float(bed[4])))
		beds.append(Transform3D(basis, Vector3(p.x, map.ground(p.x, p.y) + 0.05, p.y)))
	_multimesh_chunked(group, bed_mesh, beds, [], soil, 240.0)

func _fallback_fence() -> Mesh:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.5, 1.0, 0.12)
	return mesh

func _multimesh(parent: Node3D, mesh: Mesh, xfs: Array, tints: Array, mat: Material) -> MultiMeshInstance3D:
	return _multimesh_buffer(parent, mesh, instance_buffer(xfs, tints), xfs.size(), not tints.is_empty(), mat)

## MultiMesh's raw instance data for transforms (and colours): 12 floats a transform (its 3x4 rows), 4 a colour.
## One buffer write is much faster than a set_instance_transform() call per instance.
static func instance_buffer(xfs: Array, tints: Array) -> PackedFloat32Array:
	var stride := 16 if not tints.is_empty() else 12
	var buf := PackedFloat32Array()
	buf.resize(xfs.size() * stride)
	var o := 0
	for i in xfs.size():
		var t: Transform3D = xfs[i]
		buf[o] = t.basis.x.x; buf[o + 1] = t.basis.y.x; buf[o + 2] = t.basis.z.x; buf[o + 3] = t.origin.x
		buf[o + 4] = t.basis.x.y; buf[o + 5] = t.basis.y.y; buf[o + 6] = t.basis.z.y; buf[o + 7] = t.origin.y
		buf[o + 8] = t.basis.x.z; buf[o + 9] = t.basis.y.z; buf[o + 10] = t.basis.z.z; buf[o + 11] = t.origin.z
		if stride == 16:
			var c: Color = tints[i]
			buf[o + 12] = c.r; buf[o + 13] = c.g; buf[o + 14] = c.b; buf[o + 15] = c.a
		o += stride
	return buf

func _multimesh_buffer(parent: Node3D, mesh: Mesh, buf: PackedFloat32Array, count: int, colors: bool, mat: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.mesh = mesh
	mm.instance_count = count
	if count > 0:
		mm.buffer = buf
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	parent.add_child(mmi)
	return mmi

static func _pick(weights: Dictionary, r: float) -> String:
	var total := 0.0
	for k in weights:
		total += weights[k]
	var acc := 0.0
	for k in weights:
		acc += weights[k] / total
		if r <= acc:
			return k
	return weights.keys()[0]

static func _tree_dims(species: String) -> Vector2:
	return {"Pine": Vector2(3.0, 16.0), "Spruce": Vector2(3.0, 17.0), "Broadleaf": Vector2(4.5, 14.0),
		"Birch": Vector2(2.8, 11.0), "Poplar": Vector2(1.8, 20.0)}.get(species, Vector2(3.5, 13.0))

static func _species_colour(species: String) -> Color:
	return {"Pine": Color(0.16, 0.25, 0.13), "Spruce": Color(0.11, 0.2, 0.12), "Broadleaf": Color(0.24, 0.36, 0.14),
		"Birch": Color(0.34, 0.45, 0.2), "Poplar": Color(0.24, 0.36, 0.15)}.get(species, Color(0.22, 0.33, 0.14))

## A camera-facing card with a soft round crown on a short trunk, for the trees past TREE_NEAR.
func _impostor_material() -> StandardMaterial3D:
	var img := Image.create(64, 128, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var noise := FastNoiseLite.new()
	noise.frequency = 0.12
	for y in 128:
		for x in 64:
			var u := (x - 31.5) / 31.5
			var v := y / 127.0 # 0 top
			var crown := 1.0 - Vector2(u, (v - 0.4) / 0.42).length()
			var n := noise.get_noise_2d(x, y) * 0.35
			if crown + n > 0.0:
				var shade := 0.75 + 0.35 * (1.0 - v) + n * 0.4
				img.set_pixel(x, y, Color(shade, shade, shade, 1.0))
			elif absf(u) < 0.08 and v > 0.7:
				img.set_pixel(x, y, Color(0.35, 0.28, 0.22, 1.0))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	m.roughness = 1.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# invisible near the camera, where the real trees stand; dithered in over the hand-over
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
	m.distance_fade_min_distance = TREE_NEAR - 50.0
	m.distance_fade_max_distance = TREE_NEAR - 5.0
	return m

# ============================================================================================ props

## How far the trees and the range-limited props (fences, hedges, garden beds, lamps, signals, shelters, parked
## cars) draw, as a share of their full ranges: the graphics preset's ow_draw_scale. The impostor cards hand over at
## the near trees' new range.
func set_draw_scale(k: float) -> void:
	draw_scale = k
	for pair in _ranged:
		var inst: GeometryInstance3D = pair[0]
		if is_instance_valid(inst):
			inst.visibility_range_end = float(pair[1]) * k
	if _impostor_mat:
		_impostor_mat.distance_fade_min_distance = TREE_NEAR * k - 50.0
		_impostor_mat.distance_fade_max_distance = TREE_NEAR * k - 5.0

## A town.glb mesh by name, or the fallback built here.
func _model(name: String, fallback: Callable) -> Array:
	if models.has(name):
		return models[name]
	return [fallback.call(), Transform3D.IDENTITY]

## With range_end > 0 the instances are split into SMALL_CHUNK cells that each stop drawing past range_end, and
## the first cell's MultiMeshInstance3D is returned (so don't index instances through it).
func _place_many(parent: Node3D, name: String, mesh_xf: Array, xfs: Array, tints := [], mat: Material = null, range_end := 0.0) -> MultiMeshInstance3D:
	if xfs.is_empty():
		return null
	var local: Transform3D = mesh_xf[1]
	var out := []
	for xf in xfs:
		out.append(xf * local)
	if range_end > 0.0:
		var cells := _multimesh_chunked(parent, mesh_xf[0], out, tints, mat, range_end)
		for k in cells.size():
			cells[k].name = name if k == 0 else "%s%d" % [name, k]
		return cells[0]
	var mmi := _multimesh(parent, mesh_xf[0], out, tints, mat)
	mmi.name = name
	return mmi

## One MultiMesh per SMALL_CHUNK cell, each drawn only while the camera is within range_end of the cell's
## centre: a single town-wide MultiMesh of small things (fence panels, parked cars) is drawn whole whenever any
## of it is in view. Things show at least range_end - 91 m away (half a cell's diagonal).
func _multimesh_chunked(parent: Node3D, mesh: Mesh, xfs: Array, tints: Array, mat: Material, range_end: float) -> Array[MultiMeshInstance3D]:
	var cells := {}
	for i in xfs.size():
		var o: Vector3 = (xfs[i] as Transform3D).origin
		var c := _chunk_of(Vector2(o.x, o.z), SMALL_CHUNK)
		if not cells.has(c):
			cells[c] = [[], []]
		cells[c][0].append(xfs[i])
		if not tints.is_empty():
			cells[c][1].append(tints[i])
	var out: Array[MultiMeshInstance3D] = []
	for c in cells:
		var mmi := _multimesh(parent, mesh, cells[c][0], cells[c][1], mat)
		mmi.visibility_range_end = range_end
		mmi.visibility_range_end_margin = 20.0
		_ranged.append([mmi, range_end])
		out.append(mmi)
	return out

## Wheat, maize, grass, flowers and bushes, planted around the camera as it drives (vegetation.gd).
func build_vegetation() -> void:
	var veg: Node3D = VEGETATION.new()
	veg.name = "Vegetation"
	if veg.setup(map):
		root.add_child(veg)
	else:
		veg.free()

## Barriers where a road meets the edge of the playable area: a striped beam across it on posts with a red sign, or
## for the S1's turn-around a long row of concrete blocks. The collision comes from the baked style-4 fence segment.
func build_closures() -> void:
	var group := _group("Road ends")
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	var xfs := []
	var tints := []
	var red := Color(0.78, 0.08, 0.06)
	var white := Color(0.93, 0.93, 0.9)
	var grey := Color(0.62, 0.62, 0.6)
	for c in map.closures:
		var p := Vector2(float(c[0]), float(c[1]))
		var h := float(c[2])
		var w := float(c[3])
		var turn := int(c[4]) == 1
		var side := Vector2(-sin(h), cos(h)) # along the barrier
		var yaw := atan2(-side.y, side.x)
		var g := map.ground(p.x, p.y)
		if turn:
			var n := int(w / 3.0)
			for i in n:
				var q: Vector2 = p + side * ((float(i) + 0.5) / n - 0.5) * w
				xfs.append(Transform3D(Basis(Vector3.UP, yaw).scaled_local(Vector3(3.0, 0.9, 0.5)), Vector3(q.x, map.ground(q.x, q.y) + 0.45, q.y)))
				tints.append(grey)
				xfs.append(Transform3D(Basis(Vector3.UP, yaw).scaled_local(Vector3(3.0, 0.2, 0.52)), Vector3(q.x, map.ground(q.x, q.y) + 1.0, q.y)))
				tints.append(red if i % 2 == 0 else white)
			continue
		for end in [-1.0, 1.0]:
			var q: Vector2 = p + side * end * (w * 0.5)
			xfs.append(Transform3D(Basis().scaled(Vector3(0.18, 1.5, 0.18)), Vector3(q.x, map.ground(q.x, q.y) + 0.75, q.y)))
			tints.append(white)
		var parts := maxi(2, int(w / 1.2) / 2 * 2)
		for row in 2:
			for i in parts:
				var q: Vector2 = p + side * ((float(i) + 0.5) / parts - 0.5) * w
				var y := map.ground(q.x, q.y) + 0.85 + row * 0.4
				xfs.append(Transform3D(Basis(Vector3.UP, yaw).scaled_local(Vector3(w / parts, 0.2, 0.08)), Vector3(q.x, y, q.y)))
				tints.append(red if (i + row) % 2 == 0 else white)
		# a red board on a post at the middle: the road is closed
		xfs.append(Transform3D(Basis().scaled(Vector3(0.1, 1.4, 0.1)), Vector3(p.x, g + 0.7, p.y)))
		tints.append(grey)
		xfs.append(Transform3D(Basis(Vector3.UP, yaw).scaled_local(Vector3(0.9, 0.9, 0.05)), Vector3(p.x, g + 1.75, p.y)))
		tints.append(red)
		xfs.append(Transform3D(Basis(Vector3.UP, yaw).scaled_local(Vector3(0.65, 0.14, 0.06)), Vector3(p.x, g + 1.75, p.y)))
		tints.append(white)
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	if not xfs.is_empty():
		_multimesh(group, box, xfs, tints, mat)

func build_props() -> void:
	var group := _group("Props")
	_build_lamps(group)
	_build_signals(group)
	# bus shelters at the stops, back to the pavement, facing the road
	var stop_xfs := []
	for s in map.raw.get("stops", []):
		var p := Vector2(s[0], s[1])
		var near := map.nearest_road(p, 25.0)
		if near.is_empty():
			continue
		var dir: Vector2 = near.dir
		var side := Vector2(-dir.y, dir.x)
		var sgn := signf((p - near.pos).dot(side))
		if sgn == 0.0:
			sgn = 1.0
		var q: Vector2 = near.pos + side * sgn * (map.road_w[near.road] * 0.5 + 2.6)
		if map.inside_building(q):
			continue
		var face := -side * sgn
		stop_xfs.append(Transform3D(Basis(Vector3.UP, atan2(face.x, face.y) + PI), Vector3(q.x, map.ground(q.x, q.y), q.y)))
		map.add_post(q, 1.1)
	_place_many(group, "BusShelters", _model("BusShelter", _fallback_shelter), stop_xfs, [], null, 450.0)
	_build_level_crossings(group)
	_build_parked_cars(group)

func _build_lamps(group: Node3D) -> void:
	var lamps := TownMap._flat(map.raw.get("lamps", []))
	var xfs := []
	for p in lamps:
		var near := map.nearest_road(p, 14.0)
		var face := Vector2(0, 1)
		if not near.is_empty():
			face = ((near.pos as Vector2) - p).normalized()
			if face == Vector2.ZERO:
				face = Vector2(0, 1)
		var g := map.ground(p.x, p.y)
		# the arm reaches over the road: the model's front (-Z) points at it
		var basis := Basis(Vector3.UP, atan2(-face.x, -face.y))
		xfs.append(Transform3D(basis, Vector3(p.x, g, p.y)))
		lamp_spots.append(Vector3(p.x + face.x * 1.6, g + 8.6, p.y + face.y * 1.6))
		lamp_dirs.append(Vector3(face.x, 0.0, face.y))
	lamp_material = StandardMaterial3D.new()
	lamp_material.albedo_color = Color(0.95, 0.92, 0.82)
	lamp_material.emission_enabled = true
	lamp_material.emission = Color(1.0, 0.82, 0.55)
	lamp_material.emission_energy_multiplier = 0.0
	var mesh_xf := _model("Streetlamp", _fallback_lamp)
	var lamp_mesh := _with_surface_material(mesh_xf[0], "Lamp", lamp_material)
	_place_many(group, "Streetlamps", [lamp_mesh, mesh_xf[1]], xfs, [], null, 900.0)

## A copy of mesh whose surfaces with the material named material_name use mat instead (a MultiMesh can't
## override one surface's material per instance node, so the mesh itself carries it).
static func _with_surface_material(mesh: Mesh, material_name: String, mat: Material) -> Mesh:
	var copy := mesh.duplicate() as Mesh
	for i in copy.get_surface_count():
		var m := copy.surface_get_material(i)
		if m and m.resource_name == material_name:
			copy.surface_set_material(i, mat)
	return copy

func _build_level_crossings(group: Node3D) -> void:
	var xfs := []
	for c in crossing_points:
		var p: Vector2 = c[0]
		var ri: int = c[1]
		var half := map.road_w[ri] * 0.5
		var pts := map.road_pts[ri]
		var j: int = c[3]
		var road_dir := (pts[j + 1] - pts[j]).normalized()
		var side := Vector2(-road_dir.y, road_dir.x)
		for s: float in [-1.0, 1.0]:
			# a barrier post on the right of each approach, 5 m back from the rails, its boom across the lane
			var q := p - road_dir * 5.0 * s + side * (half + 0.9) * s
			var boom_dir := -side * s
			var xf := Transform3D(Basis(Vector3.UP, atan2(-boom_dir.y, boom_dir.x)), Vector3(q.x, map.ground(q.x, q.y), q.y))
			xfs.append(xf)
			map.add_post(q, 0.2)
			# the boom reaches across the approach lane (the road's half), not the oncoming one
			map.booms.append([q, q + boom_dir * minf(6.0, half + 0.9), false, BOOM_UP])
			_boom_posts.append(xf)
	_place_many(group, "LevelCrossings", _model("LevelCrossing", _fallback_crossing), xfs)
	_boom_angle.resize(_boom_posts.size())
	_boom_angle.fill(BOOM_UP)
	var boom_xf := []
	for k in _boom_posts.size():
		boom_xf.append(_boom_transform(k))
	if has_model("LevelCrossingBoom"):
		_boom_local = models["LevelCrossingBoom"][1]
		_boom_mmi = _place_many(group, "LevelCrossingBooms", models["LevelCrossingBoom"], boom_xf)

const BOOM_UP := 1.45 ## rad: a raised boom (0 lies across the road)
const BOOM_RATE := 0.35 ## rad/s: a boom takes about 4 s to come down or go up
const BOOM_HINGE := Vector3(0.0, 1.0, -0.34) ## on the post, in the LevelCrossing model's frame
var _boom_posts: Array = [] ## each boom's post transform (two per crossing, in crossing_points order)
var _boom_angle := PackedFloat32Array()
var _boom_mmi: MultiMeshInstance3D
var _boom_local := Transform3D.IDENTITY

func _boom_transform(k: int) -> Transform3D:
	var post: Transform3D = _boom_posts[k]
	return post * Transform3D(Basis(Vector3(0, 0, 1), _boom_angle[k]), BOOM_HINGE)

## Lowers (closed) or raises the booms of crossing i (an index into crossing_points).
func set_crossing(i: int, closed: bool) -> void:
	for k in [2 * i, 2 * i + 1]:
		if k < map.booms.size():
			map.booms[k][2] = closed

## Swings the booms towards their state; a boom only stops cars once it is nearly down.
func update_crossings(delta: float) -> void:
	if _boom_mmi == null:
		return
	for k in _boom_angle.size():
		var closed: bool = map.booms[k][2]
		var target := 0.0 if closed else BOOM_UP
		if is_equal_approx(_boom_angle[k], target):
			continue
		_boom_angle[k] = move_toward(_boom_angle[k], target, BOOM_RATE * delta)
		map.booms[k][3] = _boom_angle[k]
		_boom_mmi.multimesh.set_instance_transform(k, _boom_transform(k) * _boom_local)

## Traffic signals: one head per arm a signal controls (TownMap.signal_heads), at the kerb beside its stop line,
## facing the traffic it stops. Each is a node of its own so update_signals() can light its lenses.
const SIGNAL_RANGE := 500.0
var _signal_nodes: Array[MeshInstance3D] = []
var _signal_shown := PackedInt32Array()
var _signal_lens := PackedInt32Array() ## surface index of the red, amber and green lens (-1: the fallback mesh has none)
static var _lens_mats := {} ## lens (0 red, 1 amber, 2 green) * 2 + 1 if lit -> material

func _build_signals(group: Node3D) -> void:
	var heads := map.signal_heads()
	if heads.is_empty():
		return
	var parent := Node3D.new()
	parent.name = "TrafficLights"
	group.add_child(parent)
	var mx := _model("TrafficLight", _fallback_signal)
	var mesh: Mesh = mx[0]
	var local: Transform3D = mx[1]
	_signal_lens = PackedInt32Array([-1, -1, -1])
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i)
		var k := ["SignalRed", "SignalAmber", "SignalGreen"].find(m.resource_name if m else "")
		if k >= 0:
			_signal_lens[k] = i
			if not _lens_mats.has(k * 2 + 1) and m is StandardMaterial3D:
				var lit := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
				lit.emission_enabled = true
				lit.emission = lit.albedo_color
				lit.emission_energy_multiplier = 4.0
				var off := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
				off.emission_enabled = false
				off.albedo_color = off.albedo_color.darkened(0.75)
				_lens_mats[k * 2 + 1] = lit
				_lens_mats[k * 2] = off
	for h in heads:
		var q: Vector2 = h[0]
		var face: Vector2 = -(h[1] as Vector2) # the head looks at the traffic coming at it
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.transform = Transform3D(Basis(Vector3.UP, atan2(-face.x, -face.y)), Vector3(q.x, map.ground(q.x, q.y), q.y)) * local
		mi.visibility_range_end = SIGNAL_RANGE
		mi.visibility_range_end_margin = 20.0
		_ranged.append([mi, SIGNAL_RANGE])
		parent.add_child(mi)
		_signal_nodes.append(mi)
		_signal_shown.append(-1)
		map.add_post(q, 0.15)
	update_signals()

## Lights each head's lenses for what it shows at the map's signal clock (only the heads whose state changed).
func update_signals() -> void:
	if _signal_nodes.is_empty() or _signal_lens[0] < 0 or not _lens_mats.has(1):
		return
	var heads := map.signal_heads()
	for i in _signal_nodes.size():
		var st := TownMap.signal_state(heads[i], map.signal_t)
		if st == _signal_shown[i]:
			continue
		_signal_shown[i] = st
		var on := [st == TownMap.SIG_RED or st == TownMap.SIG_RED_AMBER,
			st == TownMap.SIG_AMBER or st == TownMap.SIG_RED_AMBER, st == TownMap.SIG_GREEN]
		for k in 3:
			_signal_nodes[i].set_surface_override_material(_signal_lens[k], _lens_mats[k * 2 + (1 if on[k] else 0)])

## Cars parked along the residential streets and in the car parks: mostly the cars Poles drove, all colours.
func _build_parked_cars(group: Node3D) -> void:
	var kinds := ["CarHatch", "CarSedan", "CarVan", "Maluch"]
	var weights := [0.45, 0.3, 0.1, 0.15]
	var lists := {}
	for k in kinds:
		lists[k] = [[], []]
	for ri in map.road_pts.size():
		var kind := map.road_kind[ri]
		if not kind in ["residential", "living_street", "unclassified"] or map.road_bridge[ri]:
			continue
		var pts := map.road_pts[ri]
		var mid := pts[pts.size() / 2]
		if not map.in_town(mid) or map.buildings_near(mid, 35.0).is_empty():
			continue
		var acc := 0.0
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var ln := a.distance_to(b)
			var t := (b - a) / maxf(ln, 1e-3)
			var side := Vector2(-t.y, t.x)
			var d := 9.0 - fmod(acc, 9.0)
			while d < ln:
				var q := a + t * d
				var r := hash2(q.x, q.y, 21.0)
				if r < 0.16:
					var sgn := 1.0 if hash2(q.x, q.y, 22.0) > 0.5 else -1.0
					var spot := q + side * sgn * (map.road_w[ri] * 0.5 + 1.0)
					if not map.inside_building(spot) and map.posts_near(spot, 2.0).is_empty():
						var pick := _pick_index(weights, hash2(q.x, q.y, 23.0))
						var h := atan2(t.y, t.x) + (PI if sgn < 0.0 else 0.0)
						_add_parked(lists[kinds[pick]], spot + side * sgn * _pavement_nudge(spot, h, side * sgn), h)
				d += 9.0
			acc += ln
	var paint := StandardMaterial3D.new()
	paint.vertex_color_use_as_albedo = true
	paint.metallic = 0.35
	paint.roughness = 0.28
	paint.clearcoat_enabled = true
	for k in kinds:
		var mesh_xf := _model(k, _fallback_car.bind(k))
		var mesh: Mesh = mesh_xf[0]
		if models.has(k):
			_place_many(group, "Parked" + k, [_with_surface_material(mesh, "Paint", paint), mesh_xf[1]], lists[k][0], lists[k][1], null, 400.0)
		else:
			_place_many(group, "Parked" + k, mesh_xf, lists[k][0], lists[k][1], paint, 400.0)

## The four corners of a parked car's footprint (a sedan is about 4 m by 1.8 m).
func _parked_corners(p: Vector2, heading: float) -> PackedVector2Array:
	var f := Vector2(cos(heading), sin(heading)) * 2.0
	var r := Vector2(-f.y, f.x).normalized() * 0.9
	return PackedVector2Array([p + f + r, p + f - r, p - f - r, p - f + r])

## How far to slide a car parked at the kerb along `out` (away from the road) so it stands wholly on the pavement
## rather than straddling the kerb step; 0 when it already does or sits wholly off it.
func _pavement_nudge(p: Vector2, heading: float, out: Vector2) -> float:
	for d in [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]:
		var n := 0
		for q in _parked_corners(p + out * d, heading):
			if map.kerb_at(q.x, q.y) > 0.0:
				n += 1
		if n == 0 or n == 4:
			return d if n == 4 else 0.0
	return 0.0

## Height a parked car rests at: ground, plus the kerb if any wheel stands on the pavement (none sink into it).
func _parked_y(p: Vector2, heading: float) -> float:
	var k := 0.0
	for q in _parked_corners(p, heading):
		k = maxf(k, map.kerb_at(q.x, q.y))
	return map.ground(p.x, p.y) + 0.02 + k

func _add_parked(list: Array, p: Vector2, heading: float) -> void:
	var basis := Basis(Vector3.UP, -heading - PI / 2.0)
	list[0].append(Transform3D(basis, Vector3(p.x, _parked_y(p, heading), p.y)))
	list[1].append(color_lin(CAR_PAINTS[int(hash2(p.x, p.y, 31.0) * 997.0) % CAR_PAINTS.size()]))
	var f := Vector2(cos(heading), sin(heading))
	map.add_post(p + f * 1.0, 0.85)
	map.add_post(p - f * 1.0, 0.85)

static func _pick_index(weights: Array, r: float) -> int:
	var acc := 0.0
	for i in weights.size():
		acc += weights[i]
		if r <= acc:
			return i
	return weights.size() - 1

# ---- fallbacks while models/town.glb is missing

static func _fallback_lamp() -> Mesh:
	var pole := MeshBatch.new(false, true)
	var grey := Color(0.45, 0.47, 0.5)
	pole.beam(Vector3(0, 0, 0), Vector3(0, 0, 0.001), 0.18, 8.8, grey)
	pole.beam(Vector3(0, 8.6, 0), Vector3(0, 8.6, -1.7), 0.1, 0.12, grey)
	var mesh := pole.commit()
	var head := MeshBatch.new(false, true)
	head.beam(Vector3(0, 8.45, -1.2), Vector3(0, 8.45, -1.9), 0.32, 0.18, Color(1, 1, 1))
	head.commit(mesh)
	var m0 := StandardMaterial3D.new()
	m0.vertex_color_use_as_albedo = true
	m0.metallic = 0.5
	m0.roughness = 0.5
	mesh.surface_set_material(0, m0)
	var m1 := StandardMaterial3D.new()
	m1.resource_name = "Lamp"
	mesh.surface_set_material(1, m1)
	return mesh

static func _fallback_signal() -> Mesh:
	var mb := MeshBatch.new(false, true)
	mb.beam(Vector3(0, 0, 0), Vector3(0, 0, 0.001), 0.12, 3.2, Color(0.2, 0.2, 0.2))
	mb.beam(Vector3(0, 2.4, -0.05), Vector3(0, 2.4, -0.25), 0.32, 0.95, Color(0.1, 0.1, 0.1))
	mb.beam(Vector3(0, 3.05, -0.26), Vector3(0, 3.05, -0.27), 0.18, 0.18, Color(1.0, 0.1, 0.05))
	mb.beam(Vector3(0, 2.8, -0.26), Vector3(0, 2.8, -0.27), 0.18, 0.18, Color(1.0, 0.7, 0.05))
	mb.beam(Vector3(0, 2.52, -0.26), Vector3(0, 2.52, -0.27), 0.18, 0.18, Color(0.1, 0.9, 0.3))
	var mesh := mb.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	mesh.surface_set_material(0, m)
	return mesh

static func _fallback_shelter() -> Mesh:
	var mb := MeshBatch.new(false, true)
	var steel := Color(0.3, 0.33, 0.36)
	for x: float in [-1.9, 1.9]:
		for z: float in [-0.7, 0.7]:
			mb.beam(Vector3(x, 0, z), Vector3(x, 0, z + 0.001), 0.08, 2.5, steel)
	mb.beam(Vector3(-2.0, 2.5, 0), Vector3(2.0, 2.5, 0), 1.7, 0.12, steel)
	mb.beam(Vector3(-1.9, 0.2, 0.7), Vector3(1.9, 0.2, 0.7), 0.04, 2.2, Color(0.6, 0.75, 0.8))
	mb.beam(Vector3(-1.5, 0.45, 0.4), Vector3(1.5, 0.45, 0.4), 0.35, 0.06, Color(0.5, 0.35, 0.2))
	var mesh := mb.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	mesh.surface_set_material(0, m)
	return mesh

static func _fallback_crossing() -> Mesh:
	var mb := MeshBatch.new(false, true)
	mb.beam(Vector3(0, 0, 0), Vector3(0, 0, 0.001), 0.25, 1.1, Color(0.85, 0.85, 0.85))
	for k in 6:
		var x0 := 0.2 + k * 1.0
		mb.beam(Vector3(x0, 0.95, 0), Vector3(x0 + 1.0, 0.95, 0), 0.08, 0.08, Color(0.85, 0.08, 0.06) if k % 2 == 0 else Color(0.95, 0.95, 0.95))
	mb.beam(Vector3(-0.3, 0, 0), Vector3(-0.3, 0, 0.001), 0.08, 2.8, Color(0.4, 0.4, 0.4))
	mb.beam(Vector3(-0.85, 2.5, 0.05), Vector3(0.25, 2.9, 0.05), 0.05, 0.18, Color(0.85, 0.08, 0.06))
	mb.beam(Vector3(-0.85, 2.9, 0.05), Vector3(0.25, 2.5, 0.05), 0.05, 0.18, Color(0.95, 0.95, 0.95))
	var mesh := mb.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	mesh.surface_set_material(0, m)
	return mesh

static func _fallback_car(kind: String) -> Mesh:
	var l: float = {"CarHatch": 4.0, "CarSedan": 4.5, "CarVan": 4.6, "Maluch": 3.05}.get(kind, 4.0)
	var w: float = {"CarVan": 1.9, "Maluch": 1.38}.get(kind, 1.72)
	var h: float = {"CarVan": 2.0, "Maluch": 1.33}.get(kind, 1.45)
	var mb := MeshBatch.new(false, true)
	var white := Color.WHITE
	mb.beam(Vector3(0, 0.3, -l * 0.5), Vector3(0, 0.3, l * 0.5), w, h * 0.45, white)
	var cab := l * (0.75 if kind == "CarVan" else 0.5)
	mb.beam(Vector3(0, 0.3 + h * 0.45, -cab * 0.45 + 0.1), Vector3(0, 0.3 + h * 0.45, cab * 0.55 + 0.1), w * 0.9, h * 0.5, white * 0.95)
	for x in [-w * 0.5, w * 0.5]:
		for z in [-l * 0.33, l * 0.33]:
			mb.beam(Vector3(x, 0.0, z - 0.3), Vector3(x, 0.0, z + 0.3), 0.2, 0.6, Color(0.08, 0.08, 0.08))
	return mb.commit()

# ============================================================================================ landmarks

## The landmark model a mapped mine shaft gets: the hand-made Andrzej I, II and V, else the generic headframe.
static func shaft_model(shaft_name: String) -> String:
	if not shaft_name.contains("Andrzej"):
		return "Headframe"
	match shaft_name.get_slice(" ", shaft_name.get_slice_count(" ") - 1):
		"I": return "AndrzejI"
		"II": return "AndrzejII"
		"V": return "AndrzejV"
	return "Headframe"

const SHAFT_TOWER_H := 25.0 ## m: a measured building this tall over a shaft is its tower, kept instead of a headframe
var _shaft_towers := {}

## How the mapped shafts meet the buildings over them: {hidden: {building index: true}} for shaft houses a
## headframe model replaces, {kept: {shaft position: true}} for shafts whose tall tower building stays (no
## generic headframe is put through it). A hand-made shaft model always replaces the building.
func shaft_towers() -> Dictionary:
	if not _shaft_towers.is_empty():
		return _shaft_towers
	var hidden := {}
	var kept := {}
	for pl in map.places:
		if String(pl.k) != "mineshaft":
			continue
		var sp := Vector2(pl.x, pl.y)
		var bespoke := shaft_model(String(pl.name)) != "Headframe" and has_model(shaft_model(String(pl.name)))
		var under: Array[int] = []
		var tall := false
		for bi in map.buildings_near(sp, 0.0):
			if Geometry2D.is_point_in_polygon(sp, map.bld_rings[bi]):
				under.append(bi)
				tall = tall or float(map.buildings[bi][1]) >= SHAFT_TOWER_H
		if tall and not bespoke:
			kept[sp] = true
			continue
		for bi in under:
			hidden[bi] = true
	_shaft_towers = {"hidden": hidden, "kept": kept}
	return _shaft_towers

## Landmark building footprints reserved by tools/open_world/landmarks.json: [model, ring, ridge height, metadata].
func landmark_buildings() -> Array:
	var out: Array = []
	for bi in map.buildings.size():
		var b: Array = map.buildings[bi]
		if b.size() <= 6 or not b[6] is Dictionary or not b[6].has("lm"):
			continue
		out.append([String(b[6].lm), map.bld_rings[bi], float(b[6].get("lmh", b[1])), b[6]])
	return out

func build_landmarks() -> void:
	var group := _group("Landmarks")
	var brick := StandardMaterial3D.new()
	brick.vertex_color_use_as_albedo = true
	brick.roughness = 0.9
	# Named building landmarks use their actual OSM footprint for centre, orientation and scale.
	for record in landmark_buildings():
		var model_name := String(record[0])
		# Leave the baker's generic building and the established church-spire fallback in place
		# when the local landmark GLB has not been imported.
		if not models.has(model_name):
			continue
		var ring: PackedVector2Array = record[1]
		var rect := min_rect(ring)
		if rect.is_empty():
			continue
		var mesh_xf: Array = models[model_name]
		var centre: Vector2 = rect[0]
		var axis: Vector2 = rect[1]
		var long_half := float(rect[2])
		var short_half := float(rect[3])
		var long_is_z := model_name != "DworzecBrzeszcze"
		var angle := atan2(axis.x, axis.y) if long_is_z else atan2(-axis.y, axis.x)
		var sx := clampf((long_half if not long_is_z else short_half) * 2.0 / (34.0 if not long_is_z else 20.0 if model_name == "KosciolUrbana" else 16.8), 0.65, 1.5)
		var sz := clampf((short_half if not long_is_z else long_half) * 2.0 / (14.0 if not long_is_z else 42.1 if model_name == "KosciolUrbana" else 37.0), 0.65, 1.5)
		var h_model := 39.0 if model_name == "KosciolUrbana" else 23.5 if model_name == "KosciolMarcina" else 10.0
		var h_target := float(record[2])
		if model_name == "DworzecBrzeszcze" and h_target < 7.0:
			h_target = 10.0
		var sy := clampf(h_target / h_model, 0.7, 1.35)
		var inst := _add_mesh(group, mesh_xf[0], null, model_name)
		inst.transform = Transform3D(Basis(Vector3.UP, angle).scaled(Vector3(sx, sy, sz)),
			Vector3(centre.x, map.ground(centre.x, centre.y), centre.y)) * (mesh_xf[1] as Transform3D)
	for pl in map.places:
		var p := Vector2(pl.x, pl.y)
		var g := map.ground(p.x, p.y)
		match String(pl.k):
			"mineshaft":
				if shaft_towers().kept.has(Vector2(pl.x, pl.y)):
					continue # a measured shaft tower building stands there already
				var model_name := shaft_model(String(pl.name))
				var mesh_xf := _model(model_name, _fallback_headframe)
				var near := map.nearest_road(p, 200.0)
				var face := 0.0
				if not near.is_empty():
					var d: Vector2 = (near.pos as Vector2) - p
					face = atan2(-d.x, -d.y)
				var inst := _add_mesh(group, mesh_xf[0], null, String(pl.name))
				# Legacy town.glb headframe model places its shaft forward of the origin.
				var shaft := Transform3D(Basis(), Vector3(0, 0, HEADFRAME_SHAFT if model_name == "Headframe" and models.has("Headframe") else 0.0))
				inst.transform = Transform3D(Basis(Vector3.UP, face), Vector3(p.x, g, p.y)) * shaft * (mesh_xf[1] as Transform3D)
				if model_name == "Headframe": map.add_post(p, 6.0)
			"chimney":
				var h := float(pl.get("h", 45.0))
				var mb := MeshBatch.new(false, true)
				_cylinder(mb, Vector3(p.x, g - 0.5, p.y), 2.6, 1.4, h, 12, Color(0.55, 0.3, 0.24))
				_cylinder(mb, Vector3(p.x, g + h - 3.0, p.y), 1.55, 1.5, 3.0, 12, Color(0.25, 0.22, 0.2))
				_add_mesh(group, mb.commit(), brick, "Chimney")
				map.add_post(p, 2.6)
			"water_tower":
				var mb := MeshBatch.new(false, true)
				_cylinder(mb, Vector3(p.x, g - 0.5, p.y), 2.2, 2.2, 24.0, 12, Color(0.75, 0.73, 0.68))
				_cylinder(mb, Vector3(p.x, g + 22.0, p.y), 6.0, 6.5, 8.0, 16, Color(0.8, 0.78, 0.72))
				_add_mesh(group, mb.commit(), brick, "WaterTower")
				map.add_post(p, 2.4)
	# Keep the old spire fallback for unlisted churches; detailed listed churches are placed above.
	for bi in map.buildings.size():
		var b: Array = map.buildings[bi]
		if String(b[0]) != "church" or map.bld_rings[bi].size() < 4:
			continue
		if b.size() > 6 and b[6] is Dictionary and b[6].has("lm") and models.has(String(b[6].lm)):
			continue
		var ring := map.bld_rings[bi]
		var rect := min_rect(ring)
		if rect.is_empty() or float(rect[2]) < 9.0:
			continue
		var cen: Vector2 = rect[0]
		var ax: Vector2 = rect[1]
		var e1: Vector2 = cen + ax * (float(rect[2]) - 3.5)
		var e2: Vector2 = cen - ax * (float(rect[2]) - 3.5)
		var n1 := map.nearest_road(e1, 80.0)
		var n2 := map.nearest_road(e2, 80.0)
		var end := e1
		if not n2.is_empty() and (n1.is_empty() or float(n2.dist) < float(n1.dist)):
			end = e2
		var mesh_xf := _model("ChurchSpire", _fallback_spire)
		var inst := _add_mesh(group, mesh_xf[0], null if models.has("ChurchSpire") else brick, "Spire")
		var face := atan2(-(end - cen).x, -(end - cen).y)
		var scale := clampf(float(rect[3]) / 5.0, 0.6, 1.1)
		inst.transform = Transform3D(Basis(Vector3.UP, face).scaled(Vector3(scale, scale, scale)),
			Vector3(end.x, map.ground(end.x, end.y), end.y)) * (mesh_xf[1] as Transform3D)
	_build_festival(group)
	_build_billboards(group)

func _build_festival(group: Node3D) -> void:
	var spot: Array = map.spots.get("festival", [])
	if spot.is_empty():
		return
	var p := Vector2(spot[0], spot[1])
	var g := map.ground(p.x, p.y)
	festival_pos = Vector3(p.x, g, p.y)
	var fest := Node3D.new()
	fest.name = "Festival"
	group.add_child(fest)
	var near := map.nearest_road(p, 300.0)
	var face := 0.0
	if not near.is_empty():
		var d: Vector2 = (near.pos as Vector2) - p
		face = atan2(-d.x, -d.y)
	fest.transform = Transform3D(Basis(Vector3.UP, face), festival_pos)
	var banner := StandardMaterial3D.new()
	banner.albedo_color = Color("#ff6a1a")
	banner.emission_enabled = true
	banner.emission = Color("#ff6a1a")
	banner.emission_energy_multiplier = 0.15
	var banner2 := banner.duplicate() as StandardMaterial3D
	banner2.albedo_color = Color("#7a3cff")
	banner2.emission = Color("#7a3cff")
	var pieces := [["FestivalStage", Vector3(0, 0, 18), 0.0, banner], ["FestivalArch", Vector3(0, 0, -16), 0.0, banner2]]
	for k in 6:
		var a := -PI * 0.8 + k * PI * 0.32
		pieces.append(["Tent", Vector3(sin(a) * 14.0, 0, cos(a) * 9.0), a, banner if k % 2 == 0 else banner2])
	for k in 10:
		pieces.append(["FlagPole", Vector3(-18.0 + k * 4.0, 0, -22.0), 0.0, banner if k % 2 == 0 else banner2])
	for pc in pieces:
		var mesh_xf := _model(pc[0], _fallback_festival.bind(pc[0]))
		var inst := MeshInstance3D.new()
		inst.mesh = mesh_xf[0]
		inst.transform = Transform3D(Basis(Vector3.UP, pc[2]), pc[1]) * (mesh_xf[1] as Transform3D)
		_tint_banner(inst, pc[3])
		fest.add_child(inst)
	var label := Label3D.new()
	label.text = "SEICENTO FEST\nBRZESZCZE"
	label.font_size = 220
	label.pixel_size = 0.02
	label.outline_size = 24
	label.modulate = Color("#ffd166")
	label.outline_modulate = Color("#3a1060")
	label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	label.position = Vector3(0, 13, 18)
	fest.add_child(label)

func _tint_banner(inst: MeshInstance3D, mat: Material) -> void:
	var mesh := inst.mesh
	if mesh == null:
		return
	var any := false
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i)
		if m and m.resource_name == "Banner":
			inst.set_surface_override_material(i, mat)
			any = true
	if not any and not models.has("FestivalStage"):
		inst.material_override = mat

static func _fallback_festival(kind: String) -> Mesh:
	var mb := MeshBatch.new(false, true)
	match kind:
		"FestivalStage":
			mb.beam(Vector3(-8, 0, 0), Vector3(8, 0, 0), 10.0, 1.5, Color.WHITE)
			for x: float in [-8.0, 8.0]:
				mb.beam(Vector3(x, 1.5, -5), Vector3(x, 1.5, -4.99), 0.4, 8.5, Color(0.2, 0.2, 0.2))
				mb.beam(Vector3(x, 1.5, 5), Vector3(x, 1.5, 5.01), 0.4, 8.5, Color(0.2, 0.2, 0.2))
			mb.beam(Vector3(-8.5, 10, 0), Vector3(8.5, 10, 0), 11.0, 0.5, Color.WHITE)
		"FestivalArch":
			for x: float in [-7.0, 7.0]:
				mb.beam(Vector3(x, 0, 0), Vector3(x, 0, 0.01), 0.8, 8.0, Color(0.25, 0.25, 0.25))
			mb.beam(Vector3(-7.4, 6.5, 0), Vector3(7.4, 6.5, 0), 0.6, 1.8, Color.WHITE)
		"Tent":
			for x: float in [-2.4, 2.4]:
				for z: float in [-2.4, 2.4]:
					mb.beam(Vector3(x, 0, z), Vector3(x, 0, z + 0.01), 0.1, 2.4, Color(0.8, 0.8, 0.8))
			mb.beam(Vector3(-2.5, 2.4, 0), Vector3(2.5, 2.4, 0), 5.0, 0.9, Color.WHITE)
		_:
			mb.beam(Vector3(0, 0, 0), Vector3(0, 0, 0.01), 0.08, 8.0, Color(0.8, 0.8, 0.8))
			mb.beam(Vector3(0.05, 4.5, 0), Vector3(1.0, 4.5, 0), 0.03, 3.3, Color.WHITE)
	return mb.commit()

## Seicento billboards along the main roads (the circuits' trackside advert atlas, when it is there).
func _build_billboards(group: Node3D) -> void:
	var atlas := load("res://models/trackside_seicento_ads_atlas.jpg") as Texture2D
	var face_mat := StandardMaterial3D.new()
	if atlas:
		face_mat.albedo_texture = atlas
	else:
		face_mat.albedo_color = Color("#ff6a1a")
	face_mat.roughness = 0.6
	var frame_mat := StandardMaterial3D.new()
	frame_mat.albedo_color = Color(0.25, 0.26, 0.28)
	frame_mat.metallic = 0.6
	var frames := MeshBatch.new()
	var faces := MeshBatch.new()
	var count := 0
	for ri in map.road_pts.size():
		if not map.road_kind[ri] in ["secondary", "tertiary", "primary"] or count > 40:
			continue
		var pts := map.road_pts[ri]
		if pts.size() < 4 or map.road_len[ri] < 250.0:
			continue
		var at := map.along(ri, map.road_len[ri] * 0.5)
		var p: Vector2 = at[0]
		var dir: Vector2 = at[1]
		var side := Vector2(-dir.y, dir.x) * (1.0 if hash2(p.x, p.y, 2.0) > 0.5 else -1.0)
		var q := p + side * (map.road_w[ri] * 0.5 + 6.0)
		if map.inside_building(q) or not map.buildings_near(q, 6.0).is_empty():
			continue
		count += 1
		var g := map.ground(q.x, q.y)
		var right := Vector3(dir.x, 0, dir.y) * 3.0
		var c3 := Vector3(q.x, g, q.y)
		for s: float in [-0.8, 0.8]:
			frames.beam(c3 + right * s, c3 + right * s + Vector3(0.01, 0, 0), 0.25, 4.2, Color.WHITE)
		var bottom := 4.0
		var top := 7.0
		var face_n := Vector3(-side.x, 0, -side.y)
		var col := int(hash2(q.x, q.y, 9.0) * 4.0)
		var u0 := col * 0.25
		faces.flat_quad(c3 - right + Vector3.UP * bottom, c3 + right + Vector3.UP * bottom, c3 + right + Vector3.UP * top,
			c3 - right + Vector3.UP * top, face_n, Color.WHITE,
			[Vector2(u0, 1.0), Vector2(u0 + 0.25, 1.0), Vector2(u0 + 0.25, 0.0), Vector2(u0, 0.0)])
		map.add_post(q, 0.4)
	if count > 0:
		_add_mesh(group, frames.commit(), frame_mat, "BillboardFrames")
		_add_mesh(group, faces.commit(), face_mat, "BillboardFaces")

static func _cylinder(mb: MeshBatch, base: Vector3, r0: float, r1: float, h: float, seg: int, col: Color) -> void:
	for k in seg:
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		var p0 := base + Vector3(cos(a0) * r0, 0, sin(a0) * r0)
		var p1 := base + Vector3(cos(a1) * r0, 0, sin(a1) * r0)
		var q0 := base + Vector3(cos(a0) * r1, h, sin(a0) * r1)
		var q1 := base + Vector3(cos(a1) * r1, h, sin(a1) * r1)
		var n := Vector3(cos((a0 + a1) * 0.5), (r0 - r1) / h, sin((a0 + a1) * 0.5)).normalized()
		mb.flat_quad(p0, p1, q1, q0, n, col)

static func _fallback_headframe() -> Mesh:
	var mb := MeshBatch.new(false, true)
	var red := Color(0.55, 0.18, 0.12)
	for x: float in [-4.0, 4.0]:
		for z: float in [-3.0, 3.0]:
			mb.beam(Vector3(x, 0, z), Vector3(x * 0.4, 0, z * 0.4 + 0.01), 0.6, 40.0, red)
	mb.beam(Vector3(0, 38, -3), Vector3(0, 38, 3), 6.0, 1.0, red)
	mb.beam(Vector3(-2.5, 0, -14), Vector3(-1.5, 38, -2), 0.8, 0.8, red)
	mb.beam(Vector3(2.5, 0, -14), Vector3(1.5, 38, -2), 0.8, 0.8, red)
	mb.beam(Vector3(-7, 0, -22), Vector3(7, 0, -22), 10.0, 9.0, Color(0.6, 0.32, 0.25))
	return mb.commit()

static func _fallback_spire() -> Mesh:
	var mb := MeshBatch.new(false, true)
	var brick := Color(0.6, 0.29, 0.21)
	mb.beam(Vector3(0, -0.5, -3.5), Vector3(0, -0.5, 3.5), 7.0, 38.5, brick)
	var apex := Vector3(0, 58, 0)
	var c := [Vector3(-3.5, 38, -3.5), Vector3(3.5, 38, -3.5), Vector3(3.5, 38, 3.5), Vector3(-3.5, 38, 3.5)]
	for k in 4:
		var a: Vector3 = c[k]
		var b: Vector3 = c[(k + 1) % 4]
		var n := (b - a).cross(apex - a).normalized()
		if n.dot((a + b) * 0.5) < 0.0:
			n = -n
		mb.flat_tri(a, b, apex, n, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Color(0.24, 0.45, 0.38))
	return mb.commit()

# ============================================================================================ horizon

## Fields beyond the map's edge and the Beskidy on the southern skyline, so the town doesn't end at a cliff.
func build_horizon() -> void:
	var group := _group("Horizon")
	var ex := map.extent
	var mat := _surface_material(GROUND_SHADER, "grass")
	mat.set_shader_parameter("base_color", Color(0.34, 0.48, 0.2))
	mat.set_shader_parameter("slope_rock", 0.0)
	var mb := MeshBatch.new()
	var reach := 9000.0
	var g0 := map.ground(ex.position.x, ex.position.y)
	var ring_in := [ex.position, Vector2(ex.end.x, ex.position.y), ex.end, Vector2(ex.position.x, ex.end.y)]
	var ring_out := [ex.position + Vector2(-reach, -reach), Vector2(ex.end.x + reach, ex.position.y - reach),
		ex.end + Vector2(reach, reach), Vector2(ex.position.x - reach, ex.end.y + reach)]
	for k in 4:
		var a: Vector2 = ring_in[k]
		var b: Vector2 = ring_in[(k + 1) % 4]
		var c: Vector2 = ring_out[(k + 1) % 4]
		var d: Vector2 = ring_out[k]
		var ha := map.ground(a.x, a.y) - 0.4
		var hb := map.ground(b.x, b.y) - 0.4
		mb.flat_quad(Vector3(a.x, ha, a.y), Vector3(b.x, hb, b.y), Vector3(c.x, g0 - 6.0, c.y), Vector3(d.x, g0 - 6.0, d.y),
			Vector3.UP, Color.WHITE)
	_add_mesh(group, mb.commit(), mat, "Fields", false)
	# the Beskid ridge 25-40 km south, a hazy blue silhouette (Bielsko-Biała's Szyndzielnia, Skrzyczne)
	var ridge := MeshBatch.new(false, true)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.00012
	noise.fractal_octaves = 4
	var prev_top := Vector3.ZERO
	var prev_bot := Vector3.ZERO
	var haze := Color(0.47, 0.56, 0.68)
	for k in 121:
		var a := deg_to_rad(-75.0 + k * 1.25) # bearing from south
		var dist := 30000.0 + noise.get_noise_1d(k * 37.0) * 5000.0
		var x := sin(a) * dist
		var y := cos(a) * dist
		var height := 700.0 + 450.0 * (0.5 + 0.5 * noise.get_noise_2d(x, y)) * (1.0 - absf(a) / deg_to_rad(90.0))
		var top := Vector3(x, g0 + height, y)
		var bot := Vector3(x, g0 - 50.0, y)
		if k > 0:
			ridge.flat_quad(prev_bot, bot, top, prev_top, Vector3(-x, 0, -y).normalized(), haze)
		prev_top = top
		prev_bot = bot
	var rmat := StandardMaterial3D.new()
	rmat.vertex_color_use_as_albedo = true
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	rmat.disable_fog = false
	_add_mesh(group, ridge.commit(), rmat, "Beskidy", false)

# ============================================================================================ beacons

## A glowing column and ground ring at each event spot (Forza-style), coloured by kind.
func add_beacon(name: String, p: Vector2, color: Color, label_text: String) -> Node3D:
	var node := Node3D.new()
	node.name = "Beacon_" + name
	var g := map.road_at(p.x, p.y, -INF, 2.0)
	var y: float = float(g.height) if not g.is_empty() else map.ground(p.x, p.y)
	node.position = Vector3(p.x, y, p.y)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	glow.albedo_color = Color(color.r, color.g, color.b, 0.4)
	glow.disable_fog = true
	# the column melts away when the camera is close (or inside it), and shows from afar
	glow.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	glow.distance_fade_min_distance = 12.0
	glow.distance_fade_max_distance = 90.0
	var col := CylinderMesh.new()
	col.top_radius = 2.6
	col.bottom_radius = 3.0
	col.height = 160.0
	col.cap_top = false
	col.cap_bottom = false
	col.radial_segments = 24
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.0))
	grad.set_color(1, Color(1, 1, 1, 1.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	glow.albedo_texture = gt
	var col_inst := MeshInstance3D.new()
	col_inst.mesh = col
	col_inst.material_override = glow
	col_inst.position = Vector3(0, 80.0, 0)
	col_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(col_inst)
	var ring := TorusMesh.new()
	ring.inner_radius = 5.4
	ring.outer_radius = 6.0
	ring.rings = 48
	var ring_mat := glow.duplicate() as StandardMaterial3D
	ring_mat.albedo_texture = null
	ring_mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_DISABLED
	ring_mat.albedo_color = Color(color.r, color.g, color.b, 0.9)
	var ring_inst := MeshInstance3D.new()
	ring_inst.mesh = ring
	ring_inst.material_override = ring_mat
	ring_inst.position = Vector3(0, 0.25, 0)
	ring_inst.scale = Vector3(1, 0.25, 1)
	ring_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(ring_inst)
	var label := Label3D.new()
	label.text = label_text
	label.font_size = 96
	label.pixel_size = 0.03
	label.outline_size = 18
	label.modulate = Color.WHITE
	label.outline_modulate = color.darkened(0.6)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = false
	label.position = Vector3(0, 9.0, 0)
	label.visibility_range_end = 450.0
	node.add_child(label)
	root.add_child(node)
	beacon_nodes[name] = node
	return node
