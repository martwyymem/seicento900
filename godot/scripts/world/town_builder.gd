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
const TOWN_MODELS := "res://models/town.glb"
const LAND_RES := 2.5 ## metres per texel of data/world/<key>_land.png (tools/build_open_world.py)

const TERRAIN_STEP := 10.0
const TERRAIN_CHUNK := 32 ## quads per chunk side
const CHUNK := 256.0 ## m: buildings and street batches
const TREE_CHUNK := 128.0
const IMPOSTOR_CHUNK := 512.0
const TREE_NEAR := 380.0 ## m: full tree meshes this far, impostors beyond
const TREE_FAR := 1800.0
const ROAD_LIFT := 0.09 ## streets sit this far over the ground; the bigger road wins at a junction
const KERB_H := 0.13
const PAVEMENT_W := 1.5
const HEADFRAME_SHAFT := 10.1 ## m from town.glb's Headframe origin forward (-Z) to its shaft

## Building palettes (sRGB): Polish plaster, brick and roofing
const HOUSE_WALLS := ["#ece2c8", "#e3d3ae", "#efe6b8", "#e8c9a8", "#f0eee6", "#d2cfc6", "#cddcbc", "#e5bba2",
	"#dcbd7c", "#d8d2c4", "#f2dcc0", "#e9e3d3"]
const HOUSE_ROOFS := ["#8f3f2a", "#6b3e2e", "#4a4d52", "#36393d", "#3f4a3d", "#a5523a", "#5a3a2c", "#7a2e22"]
const FLATS_WALLS := ["#efe6d2", "#f3e1b8", "#e9d6c0", "#dfe8cf", "#f4eab0", "#efd2c4", "#ece8dc", "#e6dccb"] ## the bloki, repainted warm
const INDUSTRIAL_WALLS := ["#c9ccd0", "#aeb4b8", "#8d9ba6", "#d8dadc", "#b8b09c", "#8e4b3a", "#9a5840"]
const INDUSTRIAL_ROOFS := ["#7a7f84", "#8a8e92", "#6a6e72", "#5c4a3f"]
const KIND_CODE := {"house": 0, "flats": 1, "commercial": 1, "public": 1, "industrial": 2, "garage": 3, "shed": 3,
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
var water_mask := {} ## terrain vertex index -> water surface height (ponds sink the ground under them)
var festival_pos := Vector3.ZERO
var crossing_points: Array = [] ## [Vector2 position, road index] where a street crosses the railway at grade
var models := {} ## town.glb meshes by object name

func _init(town: TownMap, parent: Node3D) -> void:
	map = town
	root = parent
	assets = WORLD_ASSETS.new()
	_load_models()

func _load_models() -> void:
	if not ResourceLoader.exists(TOWN_MODELS) and not FileAccess.file_exists(TOWN_MODELS):
		return
	var scene: Node = WORLD_ASSETS._load_model(TOWN_MODELS)
	if scene == null:
		return
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

## The steps in order, for the caller to run one per frame: [label, Callable].
func steps() -> Array:
	return [["Terrain", build_terrain], ["Ponds and streams", build_water], ["Streets", build_roads],
		["Railway", build_rail], ["Buildings", build_buildings], ["Woods and gardens", build_trees],
		["Street furniture", build_props], ["Landmarks", build_landmarks], ["Horizon", build_horizon]]

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
	_build_water_mask()
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
	var land := load("res://data/world/%s_land.png" % map.key) as Texture2D
	if land:
		mat.set_shader_parameter("use_land", true)
		mat.set_shader_parameter("land_map", land)
		mat.set_shader_parameter("land_origin", Vector2(map.tx0, map.ty0))
		mat.set_shader_parameter("land_size", Vector2(land.get_width(), land.get_height()) * LAND_RES)
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
			if water_mask.has(k):
				h = minf(h, float(water_mask[k]) - 1.4)
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

## Terrain vertices inside ponds (scanline over each water ring at the terrain's resolution).
func _build_water_mask() -> void:
	var ex := map.extent
	var nx := int(ex.size.x / TERRAIN_STEP) + 1
	for k in map.water_rings.size():
		var ring := map.water_rings[k]
		var level := map.water_level[k]
		var r := map.water_rects[k]
		var j0 := int(ceil((r.position.y - ex.position.y) / TERRAIN_STEP))
		var j1 := int(floor((r.end.y - ex.position.y) / TERRAIN_STEP))
		for j in range(j0 - 1, j1 + 2):
			var y := ex.position.y + j * TERRAIN_STEP
			var xs := PackedFloat32Array()
			for e in ring.size():
				var a := ring[e]
				var b := ring[(e + 1) % ring.size()]
				if (a.y > y) != (b.y > y):
					xs.append(a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x))
			xs.sort()
			for m in range(0, xs.size() - 1, 2):
				var i0 := int(ceil((xs[m] - ex.position.x) / TERRAIN_STEP)) - 1
				var i1 := int(floor((xs[m + 1] - ex.position.x) / TERRAIN_STEP)) + 1
				for i in range(maxi(i0, 0), mini(i1, nx - 1) + 1):
					var kk := j * nx + i
					water_mask[kk] = minf(float(water_mask.get(kk, INF)), level)

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

func _has_pavement(ri: int, mid: Vector2) -> bool:
	var kind := map.road_kind[ri]
	if not kind in ["primary", "secondary", "tertiary", "residential", "unclassified", "living_street"]:
		return false
	if map.road_bridge[ri] or not map.road_z[ri].is_empty():
		return false
	if not map.in_town(mid):
		return false
	return not map.buildings_near(mid, 45.0).is_empty()

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
		# kerbs and pavements in town, broken at the junctions
		var mid := pts[n / 2]
		if _has_pavement(ri, mid):
			var kb: MeshBatch = kerb_b[c]
			for side: float in [-1.0, 1.0]:
				var edge: PackedVector3Array = left if side < 0.0 else right
				for i in n - 1:
					if jd[i] < 2.5 or jd[i + 1] < 2.5:
						continue
					var e0: Vector3 = edge[i]
					var e1: Vector3 = edge[i + 1]
					var t2 := Vector2(e1.x - e0.x, e1.z - e0.z).normalized()
					var out := Vector3(-t2.y, 0.0, t2.x) * side
					var o0 := e0 + out * PAVEMENT_W
					var o1 := e1 + out * PAVEMENT_W
					o0.y = maxf(o0.y, map.ground(o0.x, o0.z) + 0.05)
					o1.y = maxf(o1.y, map.ground(o1.x, o1.z) + 0.05)
					var kc := Color(0.52, 0.51, 0.49)
					var pc := Color(0.38, 0.37, 0.35) if hash2(e0.x, e0.z, 4.0) > 0.5 else Color(0.34, 0.33, 0.32)
					var up := Vector3.UP * KERB_H
					# kerb face, then the pavement top
					kb.flat_quad(e0, e1, e1 + up, e0 + up, -out, kc)
					kb.flat_quad(e0 + up, e1 + up, o1 + up, o0 + up, Vector3.UP, pc)
					kb.flat_quad(o0 + up, o1 + up, o1 + Vector3.DOWN * 0.3, o0 + Vector3.DOWN * 0.3, out, pc)
		# raised stretches: a bridge deck with parapets, or an earth embankment down to the ground
		if not zs.is_empty():
			var db: MeshBatch = deck_b[c]
			var bb: MeshBatch = bank_b[c]
			var bridge := map.road_bridge[ri] == 1
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
						# underside
						db.flat_quad(e0 - Vector3.UP * 0.9, e1 - Vector3.UP * 0.9, e1 - Vector3.UP * 0.9 - out * (half * 2.0 + 0.4),
							e0 - Vector3.UP * 0.9 - out * (half * 2.0 + 0.4), Vector3.DOWN, concrete.darkened(0.3))
						if side > 0.0 and int(s[i] / 22.0) != int(s[i + 1] / 22.0):
							var cpt := (left[i] + right[i]) * 0.5
							db.beam(Vector3(cpt.x, map.ground(cpt.x, cpt.z) - 0.5, cpt.z),
								Vector3(cpt.x + t2.x * 0.01, 0.0, cpt.z + t2.y * 0.01), 1.4, cpt.y - map.ground(cpt.x, cpt.z) - 0.4, concrete.darkened(0.15))
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
		rail_lines.append(pts)
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
			var ya := map.ground(a.x, a.y) + za + 0.05
			var yb := map.ground(b.x, b.y) + zb + 0.05
			var A := Vector3(a.x, ya, a.y)
			var B := Vector3(b.x, yb, b.y)
			var side := Vector3(nrm.x, 0.0, nrm.y)
			ballast.flat_quad(A - side * bw * 0.5, B - side * bw * 0.5, B + side * bw * 0.5, A + side * bw * 0.5, Vector3.UP, ballast_col)
			ballast.flat_quad(A + side * bw * 0.5, B + side * bw * 0.5, B + side * (bw * 0.5 + 0.6) - Vector3.UP * 0.35,
				A + side * (bw * 0.5 + 0.6) - Vector3.UP * 0.35, (side + Vector3.UP).normalized(), ballast_col.darkened(0.1))
			ballast.flat_quad(B - side * bw * 0.5, A - side * bw * 0.5, A - side * (bw * 0.5 + 0.6) - Vector3.UP * 0.35,
				B - side * (bw * 0.5 + 0.6) - Vector3.UP * 0.35, (-side + Vector3.UP).normalized(), ballast_col.darkened(0.1))
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
			if za > 0.3 or zb > 0.3:
				for g: float in [-1.0, 1.0]:
					var o: Vector3 = side * (bw * 0.5 + 0.6) * g
					var e0 := A + o - Vector3.UP * 0.35
					var e1 := B + o - Vector3.UP * 0.35
					var out := side * g
					var w0 := maxf(0.5, za * 1.5)
					var w1 := maxf(0.5, zb * 1.5)
					var b0 := e0 + out * w0
					var b1 := e1 + out * w1
					b0.y = map.ground(b0.x, b0.z) - 0.3
					b1.y = map.ground(b1.x, b1.z) - 0.3
					var nn := (e1 - e0).cross(b0 - e0).normalized()
					if nn.y < 0.0:
						nn = -nn
					bank.flat_quad(e0, e1, b1, b0, nn, Color.WHITE)
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

## Where a street crosses the railway at grade (for the barriers and the crossing signs).
func _find_level_crossings(rail_lines: Array) -> void:
	for pts in rail_lines:
		for i in pts.size() - 1:
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

# ============================================================================================ buildings

func build_buildings() -> void:
	var group := _group("Buildings")
	var mat := ShaderMaterial.new()
	mat.shader = BUILDING_SHADER
	mat.set_shader_parameter("grain", WORLD.noise_texture("grain"))
	# lighter glass that catches the sky, white frames: the bright, clean look of Forza's towns
	mat.set_shader_parameter("glass_color", Color(0.3, 0.38, 0.45))
	mat.set_shader_parameter("frame_color", Color(0.95, 0.94, 0.9))
	wet_materials.append(mat)
	night_materials.append(mat)
	var batches := {}
	for bi in map.buildings.size():
		var b: Array = map.buildings[bi]
		var ring := map.bld_rings[bi]
		if ring.size() < 3:
			continue
		var centre := Vector2.ZERO
		for p in ring:
			centre += p
		centre /= ring.size()
		var c := _chunk_of(centre)
		if not batches.has(c):
			batches[c] = MeshBatch.new(true, true)
		_add_building(batches[c], ring, String(b[0]), float(b[1]), String(b[3]), centre)
	for c in batches:
		_add_mesh(group, (batches[c] as MeshBatch).commit(), mat)

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

func _add_building(mb: MeshBatch, ring: PackedVector2Array, kind: String, height: float, roof_shape: String, centre: Vector2) -> void:
	var r := ring.duplicate()
	# counter-clockwise seen from above (x east, z south) means negative shoelace area here
	if ring_area(r) > 0.0:
		r.reverse()
	var seed := hash2(centre.x, centre.y, 13.0)
	var pal := _palette(kind, seed, centre)
	var wall: Color = pal[0]
	var roof: Color = pal[1]
	var code: int = KIND_CODE.get(kind, 0)
	var lo := INF
	var hi := -INF
	for p in r:
		var g := map.ground(p.x, p.y)
		lo = minf(lo, g)
		hi = maxf(hi, g)
	var base := lo - 0.5
	var eave := hi + height
	# pitched roofs over footprints close to a rectangle
	var rect := []
	var pitched := roof_shape in ["hipped", "gabled", "pyramidal"] and height < 18.0
	if pitched:
		rect = min_rect(r)
		if rect.is_empty() or absf(ring_area(r)) / maxf(float(rect[4]), 1e-3) < 0.78 or float(rect[3]) > 13.0:
			pitched = false
	var uv2_wall := Vector2(seed, code)
	var uv2_roof := Vector2(seed, code + 10.0)
	var along := 0.0
	var n := r.size()
	for i in n:
		var a := r[i]
		var b := r[(i + 1) % n]
		var ln := a.distance_to(b)
		if ln < 0.01:
			continue
		var out := Vector3(-(b.y - a.y), 0.0, b.x - a.x).normalized()
		if out.dot(Vector3((a.x + b.x) * 0.5 - centre.x, 0.0, (a.y + b.y) * 0.5 - centre.y)) < 0.0:
			out = -out
		var v0 := base - hi
		var v1 := eave - hi
		mb.flat_quad(Vector3(a.x, base, a.y), Vector3(b.x, base, b.y), Vector3(b.x, eave, b.y), Vector3(a.x, eave, a.y), out, wall,
			[Vector2(along, v0), Vector2(along + ln, v0), Vector2(along + ln, v1), Vector2(along, v1)], uv2_wall)
		along += ln
	if pitched:
		var cen: Vector2 = rect[0]
		var ax: Vector2 = rect[1]
		var ay := Vector2(-ax.y, ax.x)
		var hl: float = rect[2] + 0.45 # eaves overhang
		var hw: float = rect[3] + 0.45
		var pitch := 0.62 + 0.25 * hash2(centre.x, centre.y, 5.0) # rise per run
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
		elif roof_shape == "hipped":
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
	else:
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
				var inn := Vector2(-t.y, t.x)
				if inn.dot(centre - (a + b) * 0.5) < 0.0:
					inn = -inn
				var ai := a + inn * 0.3
				var bi := b + inn * 0.3
				mb.flat_quad(Vector3(ai.x, eave, ai.y), Vector3(bi.x, eave, bi.y), Vector3(bi.x, eave + parapet, bi.y),
					Vector3(ai.x, eave + parapet, ai.y), Vector3(inn.x, 0.0, inn.y), wall.darkened(0.1),
					[Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], Vector2(seed, 3.0))
				mb.flat_quad(Vector3(a.x, eave + parapet, a.y), Vector3(b.x, eave + parapet, b.y), Vector3(bi.x, eave + parapet, bi.y),
					Vector3(ai.x, eave + parapet, ai.y), Vector3.UP, wall.darkened(0.2),
					[Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], Vector2(seed, 3.0))
				var out := -inn
				mb.flat_quad(Vector3(a.x, eave, a.y), Vector3(b.x, eave, b.y), Vector3(b.x, eave + parapet, b.y),
					Vector3(a.x, eave + parapet, a.y), Vector3(out.x, 0.0, out.y), wall,
					[Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], Vector2(seed, 3.0))

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
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.center_offset = Vector3(0.0, 0.5, 0.0)
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
	for c in near:
		for species in near[c]:
			var lists: Array = near[c][species]
			var mmi := _multimesh(group, meshes[species], lists[0], lists[1], foliage)
			mmi.visibility_range_end = TREE_NEAR
			mmi.visibility_range_end_margin = 40.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	# the far cards: big chunks (few draw calls); the shader drops the cards near the camera, where the
	# real trees stand
	for cf in far:
		var imp := _multimesh(group, quad, far[cf][0], far[cf][1], impostor_mat)
		imp.visibility_range_end = TREE_FAR + IMPOSTOR_CHUNK
		imp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _multimesh(parent: Node3D, mesh: Mesh, xfs: Array, tints: Array, mat: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not tints.is_empty()
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		if mm.use_colors:
			mm.set_instance_color(i, tints[i])
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

## A town.glb mesh by name, or the fallback built here.
func _model(name: String, fallback: Callable) -> Array:
	if models.has(name):
		return models[name]
	return [fallback.call(), Transform3D.IDENTITY]

func _place_many(parent: Node3D, name: String, mesh_xf: Array, xfs: Array, tints := [], mat: Material = null) -> MultiMeshInstance3D:
	if xfs.is_empty():
		return null
	var local: Transform3D = mesh_xf[1]
	var out := []
	for xf in xfs:
		out.append(xf * local)
	var mmi := _multimesh(parent, mesh_xf[0], out, tints, mat)
	mmi.name = name
	return mmi

func build_props() -> void:
	var group := _group("Props")
	_build_lamps(group)
	# traffic signals at the mapped nodes, facing along the road
	var signal_xfs := []
	var sig := TownMap._flat(map.raw.get("signals", []))
	for p in sig:
		var near := map.nearest_road(p, 20.0)
		if near.is_empty():
			continue
		var dir: Vector2 = near.dir
		var side := Vector2(-dir.y, dir.x)
		var half := map.road_w[near.road] * 0.5 + 1.0
		for s: float in [-1.0, 1.0]:
			var q: Vector2 = near.pos + side * half * s
			var face := -dir * s # each head faces the traffic coming at it
			signal_xfs.append(Transform3D(Basis(Vector3.UP, atan2(-face.x, -face.y)), Vector3(q.x, map.ground(q.x, q.y), q.y)))
			map.add_post(q, 0.15)
	_place_many(group, "TrafficLights", _model("TrafficLight", _fallback_signal), signal_xfs)
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
	_place_many(group, "BusShelters", _model("BusShelter", _fallback_shelter), stop_xfs)
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
	_place_many(group, "Streetlamps", [lamp_mesh, mesh_xf[1]], xfs)

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
			# a barrier post on the right of each approach, 5 m back from the rails
			var q := p - road_dir * 5.0 * s + side * (half + 0.9) * s
			var boom_dir := -side * s
			xfs.append(Transform3D(Basis(Vector3.UP, atan2(-boom_dir.y, boom_dir.x)), Vector3(q.x, map.ground(q.x, q.y), q.y)))
			map.add_post(q, 0.2)
	_place_many(group, "LevelCrossings", _model("LevelCrossing", _fallback_crossing), xfs)

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
						_add_parked(lists[kinds[pick]], spot, h)
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
			_place_many(group, "Parked" + k, [_with_surface_material(mesh, "Paint", paint), mesh_xf[1]], lists[k][0], lists[k][1])
		else:
			_place_many(group, "Parked" + k, mesh_xf, lists[k][0], lists[k][1], paint)

func _add_parked(list: Array, p: Vector2, heading: float) -> void:
	var basis := Basis(Vector3.UP, -heading - PI / 2.0)
	list[0].append(Transform3D(basis, Vector3(p.x, map.ground(p.x, p.y) + 0.02, p.y)))
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

func build_landmarks() -> void:
	var group := _group("Landmarks")
	var brick := StandardMaterial3D.new()
	brick.vertex_color_use_as_albedo = true
	brick.roughness = 0.9
	for pl in map.places:
		var p := Vector2(pl.x, pl.y)
		var g := map.ground(p.x, p.y)
		match String(pl.k):
			"mineshaft":
				var mesh_xf := _model("Headframe", _fallback_headframe)
				var near := map.nearest_road(p, 200.0)
				var face := 0.0
				if not near.is_empty():
					var d: Vector2 = (near.pos as Vector2) - p
					face = atan2(-d.x, -d.y)
				var inst := _add_mesh(group, mesh_xf[0], null, String(pl.name))
				# the model's shaft stands HEADFRAME_SHAFT in front of its origin (the winding house is behind)
				var shaft := Transform3D(Basis(), Vector3(0, 0, HEADFRAME_SHAFT if models.has("Headframe") else 0.0))
				inst.transform = Transform3D(Basis(Vector3.UP, face), Vector3(p.x, g, p.y)) * shaft * (mesh_xf[1] as Transform3D)
				map.add_post(p, 6.0)
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
	# a spire on each named church, at the end of the nave nearest the street
	for bi in map.buildings.size():
		var b: Array = map.buildings[bi]
		if String(b[0]) != "church" or map.bld_rings[bi].size() < 4:
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
