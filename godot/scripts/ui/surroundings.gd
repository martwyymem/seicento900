## A circuit's real surroundings, from OpenStreetMap via tools/build_surroundings.py
## (data/tracks/<key>_env.json and <key>_land.png): the land map that paints roads, fields, forest floor and
## bare ground onto the terrain, the woods (trees one by one near the circuit, a canopy further out), the
## buildings, lakes and rivers, hedges, rows of trees and single trees.
## race_world.gd owns one per circuit (null where there is no data) and calls it while building the track.
extends RefCounted

const BUILDING_SHADER := preload("res://shaders/building.gdshader")
const CANOPY_SHADER := preload("res://shaders/canopy.gdshader")
const FOLIAGE_SHADER := preload("res://shaders/foliage.gdshader")
const WORLD_ASSETS := preload("res://scripts/ui/world_assets.gd")
const TREES_PATH := "res://models/trees.glb"
const WATER_SHADER := preload("res://shaders/water.gdshader")
const CHUNK := 256.0 ## metres: trees, canopy and buildings are split into tiles of this size for culling
const TREE_BAND := [70.0, 90.0, 110.0, 140.0] ## trees one by one this far beyond the run-off, per quality
const TREE_CELL := [8.0, 7.0, 6.2, 5.5] ## one tree per cell of this size in a wood
const TREE_CAP := [9000, 16000, 26000, 40000]
const TREE_VISIBLE := [700.0, 1000.0, 1400.0, 0.0] ## how far the single trees are drawn (0 always)

## Wall and roof colours of the buildings in each country.
const PALETTES := {
	"be": [["#8b8a86", "#e6e1d6", "#9c5a44", "#b9b2a4", "#d8d0c0"], ["#3b3e44", "#45484e", "#5a4a44"]],
	"de": [["#ece6d8", "#d9d2c3", "#e8dfcc", "#c9c0ae", "#f2efe6", "#b7a58c"], ["#3e4146", "#4a4d52", "#7a3b2c", "#6b4033"]],
	"fr": [["#e2d8c0", "#ece6d6", "#d6c8a8", "#c9b99a", "#f0ebe0"], ["#4a4d52", "#9b5a3c", "#a8674a", "#3f4247"]],
	"mc": [["#efe3cc", "#e9d3b0", "#dcbfa0", "#f3efe6", "#e6c2a4", "#d9a98d", "#e8cf8f", "#e3b2a0"], ["#b5613f", "#9c4f35", "#c9c2b4", "#a85a3a"]],
	"it": [["#d9a877", "#e6c9a0", "#c98d6a", "#e8d9bd", "#d4b48c", "#efe4cf"], ["#a5543a", "#b5613f", "#94503a", "#8a8a86"]],
	"uk": [["#8d4b3a", "#cbb58c", "#9a5a44", "#d9cfbd", "#7a4234"], ["#45484d", "#3a3c40", "#6b4a3c"]],
	"jp": [["#dcdcd8", "#b8b8b4", "#e8e6e0", "#c8c4bc", "#a8aaa8"], ["#4a525c", "#3d4a5c", "#5a5e62", "#6e7072"]],
	"nl": [["#7a3f30", "#5a3a30", "#8a4a38", "#e6e2d8", "#a0664e"], ["#3a3a3c", "#2e2f31", "#a2583a", "#4a4a4c"]],
	"us": [["#e6e2d6", "#c9c2b0", "#8f5040", "#d8d4cc", "#b0a898", "#f0ede6"], ["#555a5f", "#4a4440", "#62666a", "#3e4044"]],
	"pl": [["#d6d0c2", "#e2ddd0", "#c8c2b2", "#b9b4a8", "#ece8de"], ["#6e7276", "#9b4a36", "#5a5e62"]],
}
const COUNTRY := {"gp": "de", "nordschleife": "de", "spa": "be", "monaco": "mc", "lemans": "fr", "monza": "it",
	"silverstone": "uk", "suzuka": "jp", "zandvoort": "nl", "indy": "us", "fiat": "pl"}
## The trees of each country (models/trees.glb): [conifers, broadleaves, street and garden trees], each a
## species -> weight mix.
const SPECIES := {
	"de": [{"Spruce": 0.8, "Pine": 0.2}, {"Broadleaf": 0.8, "Birch": 0.2}, {"Broadleaf": 0.8, "Birch": 0.2}],
	"be": [{"Spruce": 0.85, "Pine": 0.15}, {"Broadleaf": 0.85, "Birch": 0.15}, {"Broadleaf": 0.85, "Birch": 0.15}],
	"fr": [{"Pine": 1.0}, {"Broadleaf": 0.75, "Poplar": 0.15, "Birch": 0.1}, {"Broadleaf": 0.7, "Poplar": 0.3}],
	"it": [{"StonePine": 0.5, "Cypress": 0.2, "Pine": 0.3}, {"Broadleaf": 0.8, "Poplar": 0.2}, {"Broadleaf": 0.6, "Poplar": 0.2, "Cypress": 0.2}],
	"mc": [{"StonePine": 0.5, "Cypress": 0.3, "Pine": 0.2}, {"Broadleaf": 0.6, "Palm": 0.4}, {"Palm": 0.45, "StonePine": 0.2, "Broadleaf": 0.35}],
	"uk": [{"Pine": 0.6, "Spruce": 0.4}, {"Broadleaf": 0.8, "Birch": 0.2}, {"Broadleaf": 0.85, "Birch": 0.15}],
	"jp": [{"Pine": 0.6, "Cypress": 0.4}, {"Broadleaf": 1.0}, {"Broadleaf": 0.7, "Pine": 0.3}],
	"nl": [{"Pine": 1.0}, {"Birch": 0.5, "Broadleaf": 0.5}, {"Broadleaf": 0.7, "Birch": 0.3}],
	"us": [{"Pine": 1.0}, {"Broadleaf": 1.0}, {"Broadleaf": 1.0}],
	"pl": [{"Pine": 0.7, "Spruce": 0.3}, {"Birch": 0.4, "Broadleaf": 0.6}, {"Broadleaf": 0.6, "Birch": 0.4}],
}
const INDUSTRIAL_WALLS := ["#c9ccd0", "#aeb4b8", "#8d9ba6", "#d8dadc", "#b8b09c"]
const INDUSTRIAL_ROOFS := ["#7a7f84", "#8a8e92", "#6a6e72"]

var world: Node3D ## race_world.gd
var track: Track
var env := {}
var land: Image
var land_texture: Texture2D
var land_rect := Rect2() ## track metres
var _res := 2.0 ## land map metres per texel
static var _tree_meshes := {} ## Blender tree meshes by species

## Loads the circuit's data; false where there is none.
func setup(w: Node3D) -> bool:
	world = w
	track = w.track
	var key: String = track.cfg.key
	var path := "res://data/tracks/%s_env.json" % key
	var map_path := "res://data/tracks/%s_land.png" % key
	if not FileAccess.file_exists(path) or not ResourceLoader.exists(map_path):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return false
	env = data
	land_texture = load(map_path) as Texture2D
	land = land_texture.get_image()
	if land.is_compressed():
		land.decompress()
	var l: Dictionary = env.land
	land_rect = Rect2(l.x0, l.y0, l.w, l.h)
	_res = land_rect.size.x / land.get_width()
	return true

## World height of the terrain mesh at track point (x, z): on the detailed grid's triangles near the circuit
## (race_world._terrain_grid), from the elevation model (as the coarse terrain has it) further out.
func ground_height(x: float, z: float) -> float:
	var t: Dictionary = world._terrain_grid
	if not t.is_empty():
		var fx: float = (x - t.x0) / t.fine
		var fz: float = (z - t.z0) / t.fine
		var ix := floori(fx)
		var iz := floori(fz)
		if ix >= 0 and iz >= 0 and ix < t.nx and iz < t.nz:
			var h: PackedFloat32Array = t.h
			var row: int = t.row
			var h00 := h[iz * row + ix]
			var h10 := h[iz * row + ix + 1]
			var h01 := h[(iz + 1) * row + ix]
			var h11 := h[(iz + 1) * row + ix + 1]
			if not (is_nan(h00) or is_nan(h10) or is_nan(h01) or is_nan(h11)):
				var u := fx - ix
				var v := fz - iz
				if u + v <= 1.0: # the cell's two triangles, as _build_terrain splits it
					return h00 + (h10 - h00) * u + (h01 - h00) * v
				return h11 + (h01 - h11) * (1.0 - u) + (h10 - h11) * (1.0 - v)
	return (world._sample_dem(track.grid, x, z) - world.elevation_base - 1.2) * world.ALTITUDE_SCALE

## Distance from track point (x, z) to the nearest centreline sample, and that sample: Vector2(index,
## distance); (-1, INF) beyond the detailed terrain band (175 m) round the circuit.
func track_distance(x: float, z: float) -> Vector2:
	var t: Dictionary = world._terrain_grid
	var best := Vector2(-1, INF)
	if t.is_empty():
		return best
	var ix := floori((x - t.x0) / t.fine)
	var iz := floori((z - t.z0) / t.fine)
	var idx: PackedInt32Array = t.i
	for dz in 2:
		for dx in 2:
			var gx := ix + dx
			var gz := iz + dz
			if gx < 0 or gz < 0 or gx > t.nx or gz > t.nz:
				continue
			var k := idx[gz * int(t.row) + gx]
			if k < 0 or k == int(best.x):
				continue
			var d := Vector2(track.X[k] - x, track.Y[k] - z).length()
			if d < best.y:
				best = Vector2(k, d)
	return best

func has_buildings() -> bool:
	return not env.get("buildings", []).is_empty()

## Binds the land map to a ground material (ground.gdshader), with the country's field and soil colours.
func apply_land_map(m: ShaderMaterial) -> void:
	m.set_shader_parameter("use_land", true)
	m.set_shader_parameter("land_map", land_texture)
	m.set_shader_parameter("land_origin", land_rect.position - world.world_center)
	m.set_shader_parameter("land_size", land_rect.size)
	var country: String = COUNTRY.get(track.cfg.key, "de")
	if track.cfg.key == "zandvoort":
		m.set_shader_parameter("bare_color", Color("#d9c9a3")) # dune sand
	elif country == "mc":
		m.set_shader_parameter("bare_color", Color("#b8ad98")) # limestone
	elif country == "jp":
		m.set_shader_parameter("farm_color_b", Color("#5e7a3a")) # rice paddies
	if track.cfg.theme == "city":
		m.set_shader_parameter("paved_color", Color("#8a857a")) # pale paving and asphalt

## The land map at track point (x, z): (paved, farmland, bare, forest), 0-1 each.
func land_at(x: float, z: float) -> Color:
	var u := floori((x - land_rect.position.x) / _res)
	var v := floori((z - land_rect.position.y) / _res)
	if u < 0 or v < 0 or u >= land.get_width() or v >= land.get_height():
		return Color(0, 0, 0, 0)
	return land.get_pixel(u, v)

func build() -> void:
	var root := Node3D.new()
	root.name = "Surroundings"
	world.track_root.add_child(root)
	_build_woods(root)
	_build_buildings(root)
	_build_stands(root)
	_build_water(root)
	_build_hedges(root)

# --------------------------------------------------------------------------------------------- exclusions

## Whether a spot is kept for the circuit's own structures: the run-off (clear metres from the centreline),
## the pit building and race control, the main grandstands and the TV towers.
func _reserved(x: float, z: float, clear: float) -> bool:
	var near: Vector2 = track_distance(x, z)
	if near.x < 0:
		return false
	if near.y < clear:
		return true
	var i := int(near.x)
	var s := i * track.step
	var rel_s := track.rel(s)
	var side := signf((x - track.X[i]) * track.NX[i] + (z - track.Y[i]) * track.NY[i])
	var cfg := track.cfg
	var garages: Vector2 = world._garage_span()
	if garages != Vector2.ZERO and side == signf(cfg.pit_offset) and near.y < absf(cfg.pit_offset) + 32.0 \
			and rel_s > garages.x - 45.0 and rel_s < garages.y + 45.0:
		return true
	if cfg.grandstands and side == world._stands_side() and near.y < world._stands_front() + world._stands_depth() + 6.0 \
			and rel_s > cfg.stands.x - 25.0 and rel_s < cfg.stands.y + 25.0:
		return true
	return world._near_tv_camera(x - world.world_center.x, z - world.world_center.y)

func _clear_distance() -> float:
	return track.half + track.cfg.runoff + 5.0

static func _chunk(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / CHUNK), floori(z / CHUNK))

static func _rand(x: float, z: float, salt: float) -> float:
	return fposmod(sin(x * 12.9898 + z * 78.233 + salt * 37.719) * 43758.5453, 1.0)

# --------------------------------------------------------------------------------------------- woods

## Trees one by one in the woods near the circuit (and the single trees and rows mapped anywhere), and a
## canopy over the rest of each wood.
func _build_woods(root: Node3D) -> void:
	var q: int = world.quality
	var clear := _clear_distance()
	var band: float = clear + TREE_BAND[q]
	# woods near the circuit: how much area, so the trees fit the budget
	var t: Dictionary = world._terrain_grid
	if t.is_empty():
		return
	var d2: PackedFloat32Array = t.d2
	var forest_area := 0.0
	var fine: float = t.fine
	for gz in t.nz + 1:
		for gx in t.nx + 1:
			var dd := d2[gz * t.row + gx]
			if dd < band * band and dd > clear * clear:
				var lm := land_at(t.x0 + gx * fine, t.z0 + gz * fine)
				forest_area += lm.a * (1.0 - lm.r) * fine * fine
	var cell: float = maxf(TREE_CELL[q], sqrt(forest_area / TREE_CAP[q]))
	var chunks := {} # chunk -> {species: [transforms, tints]}
	# the woods: a jittered grid over the detailed terrain's band
	var x0: float = t.x0
	var z0: float = t.z0
	var nx := ceili(t.nx * fine / cell)
	var nz := ceili(t.nz * fine / cell)
	for jz in nz:
		for jx in nx:
			var x := x0 + (jx + _rand(jx, jz, 1.0)) * cell
			var z := z0 + (jz + _rand(jx, jz, 2.0)) * cell
			var gi := roundi((z - z0) / fine) * int(t.row) + roundi((x - x0) / fine)
			if gi < 0 or gi >= d2.size() or d2[gi] > (band + fine) * (band + fine):
				continue
			var lm := land_at(x, z)
			if lm.a < 0.35 or lm.r > 0.25 or _rand(x, z, 3.0) > lm.a * 1.15:
				continue
			var near: Vector2 = track_distance(x, z)
			if near.y > band or _reserved(x, z, clear):
				continue
			_add_tree(chunks, _wood_species(x, z), x, z, 1.0)
	# mapped single trees (streets, gardens, parks) and rows of trees along lanes and fields, anywhere
	var singles: Array = env.get("trees", [])
	for k in range(0, singles.size() - 1, 2):
		if not _reserved(singles[k], singles[k + 1], clear - 2.0):
			_add_tree(chunks, _street_species(singles[k], singles[k + 1]), singles[k], singles[k + 1], 1.0)
	for line in env.get("hedges", []):
		if line.is_empty() or line[0] != -1.0:
			continue
		var row_species := _street_species(line[1], line[2]) # one species all along a row
		for p in _along(line.slice(1), 8.0):
			if not _reserved(p.x, p.y, clear - 2.0):
				_add_tree(chunks, row_species, p.x, p.y, 0.95)
	var trees := Node3D.new()
	trees.name = "Trees"
	root.add_child(trees)
	var meshes := tree_meshes()
	var foliage := ShaderMaterial.new()
	foliage.shader = FOLIAGE_SHADER
	foliage.set_shader_parameter("grain", world.noise_texture("grain"))
	foliage.set_shader_parameter("linear_colors", true)
	world._wet_materials.append(foliage)
	for c in chunks:
		for species in chunks[c]:
			if meshes.has(species):
				var lists: Array = chunks[c][species]
				_add_trees(trees, meshes[species], Transform3D.IDENTITY, lists[0], lists[1], foliage, q)
	_build_canopy(root, band - 25.0)

## The Blender trees (tools/blender/build_trees.py) by species.
static func tree_meshes() -> Dictionary:
	if _tree_meshes.is_empty():
		var scene: Node = WORLD_ASSETS._load_model(TREES_PATH)
		if scene:
			for mi in scene.find_children("*", "MeshInstance3D", true, false):
				_tree_meshes[mi.name] = (mi as MeshInstance3D).mesh
			scene.free()
	return _tree_meshes

## A species for a tree in a wood at (x, z): conifers stand together in plantations (as much of the wood as
## the circuit's tree_conifer says), broadleaves elsewhere, in the country's mix.
func _wood_species(x: float, z: float) -> String:
	var mix: Array = SPECIES.get(COUNTRY.get(track.cfg.key, "de"), SPECIES.de)
	var stand := 0.5 + 0.5 * sin(x * 0.009 + z * 0.004) * cos(z * 0.011 - x * 0.006)
	var conifer := _rand(x, z, 4.0) < clampf(track.cfg.tree_conifer, 0.0, 1.0) * (0.4 + 1.2 * stand)
	return _pick(mix[0] if conifer else mix[1], _rand(x, z, 16.0))

## A species for a mapped single tree or row: the country's street and garden trees.
func _street_species(x: float, z: float) -> String:
	var mix: Array = SPECIES.get(COUNTRY.get(track.cfg.key, "de"), SPECIES.de)
	return _pick(mix[2], _rand(x, z, 17.0))

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

func _add_tree(chunks: Dictionary, species: String, x: float, z: float, scale: float) -> void:
	var c := _chunk(x, z)
	if not chunks.has(c):
		chunks[c] = {}
	if not chunks[c].has(species):
		chunks[c][species] = [[], []]
	var size := (0.72 + _rand(x, z, 5.0) * 0.5) * scale
	var basis := Basis(Vector3.UP, _rand(x, z, 6.0) * TAU).scaled(Vector3(size, size * (0.9 + _rand(x, z, 7.0) * 0.25), size))
	var y: float = ground_height(x, z) - 0.3
	chunks[c][species][0].append(Transform3D(basis, Vector3(x - world.world_center.x, y, z - world.world_center.y)))
	var tint := 0.8 + _rand(x, z, 8.0) * 0.32
	chunks[c][species][1].append(Color(tint * (0.94 + _rand(x, z, 9.0) * 0.12), tint, tint * (0.88 + _rand(x, z, 10.0) * 0.16)))

func _add_trees(parent: Node3D, mesh: Mesh, local: Transform3D, xfs: Array, tints: Array, material: Material, q: int) -> void:
	if xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not tints.is_empty()
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i] * local)
		if mm.use_colors:
			mm.set_instance_color(i, tints[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material
	if TREE_VISIBLE[q] > 0.0:
		mmi.visibility_range_end = TREE_VISIBLE[q]
		mmi.visibility_range_end_margin = 100.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(mmi)

## The canopy: a sheet of crowns 14-24 m over the ground wherever the land map is wood, from inner metres off
## the centreline outwards (the single trees stand in front of its edge). Its rim drops to the ground.
func _build_canopy(root: Node3D, inner: float) -> void:
	var span := maxf(land_rect.size.x, land_rect.size.y)
	var cell := maxf(9.0, span / 560.0)
	var nx := int(land_rect.size.x / cell)
	var nz := int(land_rect.size.y / cell)
	var x0 := land_rect.position.x
	var z0 := land_rect.position.y
	# per grid point: 1 inside a wood (clear of roads and the circuit), else 0
	var inside := PackedByteArray()
	inside.resize((nx + 1) * (nz + 1))
	for jz in nz + 1:
		for jx in nx + 1:
			var x := x0 + jx * cell
			var z := z0 + jz * cell
			var lm := land_at(x, z)
			if lm.a > 0.5 and lm.r < 0.3:
				var near: Vector2 = track_distance(x, z)
				if near.y > inner:
					inside[jz * (nx + 1) + jx] = 1
	var chunks := {} # chunk -> SurfaceTool
	var top := func(jx: int, jz: int, rim: bool) -> Vector3:
		var x := x0 + jx * cell
		var z := z0 + jz * cell
		var lump := _rand(float(jx), float(jz), 11.0)
		var broad := 0.5 + 0.5 * sin(x * 0.013 + z * 0.007) * cos(z * 0.009 - x * 0.005)
		var h := (4.0 + lump * 3.0) if rim else (14.0 + broad * 6.0 + lump * 4.0)
		return Vector3(x - world.world_center.x, ground_height(x, z) + h, z - world.world_center.y)
	var row := nx + 1
	for jz in nz:
		for jx in nx:
			var a := inside[jz * row + jx]
			var b := inside[jz * row + jx + 1]
			var c := inside[(jz + 1) * row + jx]
			var d := inside[(jz + 1) * row + jx + 1]
			if a + b + c + d < 3:
				continue
			# a corner outside the wood is the rim: it comes down towards the ground
			var p00: Vector3 = top.call(jx, jz, a == 0 or _is_rim(inside, row, nx, nz, jx, jz))
			var p10: Vector3 = top.call(jx + 1, jz, b == 0 or _is_rim(inside, row, nx, nz, jx + 1, jz))
			var p01: Vector3 = top.call(jx, jz + 1, c == 0 or _is_rim(inside, row, nx, nz, jx, jz + 1))
			var p11: Vector3 = top.call(jx + 1, jz + 1, d == 0 or _is_rim(inside, row, nx, nz, jx + 1, jz + 1))
			var key := _chunk(x0 + jx * cell, z0 + jz * cell)
			if not chunks.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				chunks[key] = st
			var st: SurfaceTool = chunks[key]
			if a + b + c + d == 4:
				for v in [p00, p10, p01, p10, p11, p01]:
					st.add_vertex(v)
			elif a == 0:
				for v in [p10, p11, p01]:
					st.add_vertex(v)
			elif b == 0:
				for v in [p00, p11, p01]:
					st.add_vertex(v)
			elif c == 0:
				for v in [p00, p10, p11]:
					st.add_vertex(v)
			else:
				for v in [p00, p10, p01]:
					st.add_vertex(v)
	if chunks.is_empty():
		return
	var mat := ShaderMaterial.new()
	mat.shader = CANOPY_SHADER
	mat.set_shader_parameter("grain", world.noise_texture("grain"))
	mat.set_shader_parameter("conifer_share", clampf(track.cfg.tree_conifer, 0.0, 1.0))
	world._wet_materials.append(mat)
	var canopy := Node3D.new()
	canopy.name = "Canopy"
	root.add_child(canopy)
	for key in chunks:
		var inst := MeshInstance3D.new()
		inst.mesh = (chunks[key] as SurfaceTool).commit()
		inst.material_override = mat
		canopy.add_child(inst)

## A wood's grid point next to one outside it.
static func _is_rim(inside: PackedByteArray, row: int, nx: int, nz: int, jx: int, jz: int) -> bool:
	for o in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var x: int = jx + o.x
		var z: int = jz + o.y
		if x < 0 or z < 0 or x > nx or z > nz or inside[z * row + x] == 0:
			return true
	return false

## Points every step metres along a flat [x, y, x, y, ...] line.
static func _along(flat: Array, step: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var carry := 0.0
	for k in range(0, flat.size() - 3, 2):
		var a := Vector2(flat[k], flat[k + 1])
		var b := Vector2(flat[k + 2], flat[k + 3])
		var seg := a.distance_to(b)
		var t := carry
		while t < seg:
			out.append(a.lerp(b, t / seg))
			t += step
		carry = t - seg
	return out

# --------------------------------------------------------------------------------------------- buildings

## Every mapped building, its footprint extruded to its height: a gable roof on houses and farms with a
## four-cornered footprint, flat roofs on the rest. Walls, windows and roofs come from building.gdshader.
func _build_buildings(root: Node3D) -> void:
	var country: String = COUNTRY.get(track.cfg.key, "de")
	var palette: Array = PALETTES[country]
	var city := track.cfg.theme == "city"
	var clear := track.half + track.cfg.runoff + (1.2 if city else 4.0)
	var casino: Dictionary = world._casino_spot()
	var chunks := {}
	for b in env.get("buildings", []):
		var height: float = b[0]
		var kind: int = b[1]
		var ring: Array[Vector2] = []
		for k in range(3, b.size() - 1, 2):
			ring.append(Vector2(b[k], b[k + 1]))
		if ring.size() < 3:
			continue
		var centre := Vector2.ZERO
		for p in ring:
			centre += p
		centre /= ring.size()
		if not casino.is_empty() and centre.distance_to(casino.p) < 32.0:
			continue # the Casino landmark stands there
		var skip := _reserved(centre.x, centre.y, clear)
		if not skip:
			for p in ring:
				if track_distance(p.x, p.y).y < clear:
					skip = true
					break
		if skip:
			continue
		var seed := _rand(centre.x, centre.y, 13.0)
		var walls: Array = INDUSTRIAL_WALLS if kind == 2 else palette[0]
		var roofs: Array = INDUSTRIAL_ROOFS if kind in [2, 6] else palette[1]
		var wall := Color(walls[int(seed * 97.0) % walls.size()])
		var roof := Color(roofs[int(seed * 61.0) % roofs.size()])
		if kind == 1 and city:
			roof = wall.darkened(0.25) # flat roofs in town
		var key := _chunk(centre.x, centre.y)
		if not chunks.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			chunks[key] = st
		# (the shader takes the vertex colours as linear)
		_add_building(chunks[key], ring, height, kind, wall.srgb_to_linear(), roof.srgb_to_linear(), seed)
	if chunks.is_empty():
		return
	var mat := ShaderMaterial.new()
	mat.shader = BUILDING_SHADER
	mat.set_shader_parameter("grain", world.noise_texture("grain"))
	world._wet_materials.append(mat)
	world._night_materials.append(mat)
	var node := Node3D.new()
	node.name = "Buildings"
	root.add_child(node)
	for key in chunks:
		var st: SurfaceTool = chunks[key]
		var inst := MeshInstance3D.new()
		inst.mesh = st.commit()
		inst.material_override = mat
		node.add_child(inst)

func _add_building(st: SurfaceTool, ring: Array[Vector2], height: float, kind: int, wall: Color, roof: Color, seed: float) -> void:
	# counter-clockwise seen from above (x east, z south), so the walls' outsides are known
	var area := 0.0
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		area += a.x * b.y - b.x * a.y
	if area < 0.0:
		ring.reverse()
	var ground := INF
	var ground_hi := -INF
	for p in ring:
		var g: float = ground_height(p.x, p.y)
		ground = minf(ground, g)
		ground_hi = maxf(ground_hi, g)
	var base := ground - 0.6
	var eave := ground_hi + height
	var pitched := (kind == 0 or kind == 4 or kind == 5) and ring.size() == 4 and height < 16.0
	var ridge := 0.0
	var long_axis := 0
	if pitched:
		var e0 := ring[0].distance_to(ring[1])
		var e1 := ring[1].distance_to(ring[2])
		long_axis = 0 if e0 >= e1 else 1
		ridge = clampf(minf(e0, e1) * 0.42, 1.2, 5.0)
		eave = ground_hi + maxf(height - ridge * 0.6, 2.6)
	var c: Vector2 = world.world_center
	var uv2_wall := Vector2(seed, kind)
	var uv2_roof := Vector2(seed, kind + 10.0)
	var along := 0.0
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		var ln := a.distance_to(b)
		var out := Vector3(b.y - a.y, 0.0, a.x - b.x).normalized() # outward for a counter-clockwise ring
		var a0 := Vector3(a.x - c.x, base, a.y - c.y)
		var b0 := Vector3(b.x - c.x, base, b.y - c.y)
		var a1 := Vector3(a.x - c.x, eave, a.y - c.y)
		var b1 := Vector3(b.x - c.x, eave, b.y - c.y)
		var u0 := along
		var u1 := along + ln
		# v is metres up from the highest ground under the building, where the windows start
		var v0 := base - ground_hi
		var v1 := eave - ground_hi
		_tri(st, [a0, b0, b1], [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1)], out, wall, uv2_wall)
		_tri(st, [a0, b1, a1], [Vector2(u0, v0), Vector2(u1, v1), Vector2(u0, v1)], out, wall, uv2_wall)
		along = u1
	if pitched:
		# ridge along the long sides; gables on the short ones
		var p := ring
		var s := long_axis # sides s and s+2 are long
		var m1 := (p[(s + 1) % 4] + p[(s + 2) % 4]) * 0.5
		var m2 := (p[(s + 3) % 4] + p[s]) * 0.5
		var r1 := Vector3(m1.x - c.x, eave + ridge, m1.y - c.y)
		var r2 := Vector3(m2.x - c.x, eave + ridge, m2.y - c.y)
		var q := []
		for v in p:
			q.append(Vector3(v.x - c.x, eave, v.y - c.y))
		var rlen := m1.distance_to(m2)
		# the two slopes
		for side in [[q[s], q[(s + 1) % 4], r1, r2], [q[(s + 2) % 4], q[(s + 3) % 4], r2, r1]]:
			var n: Vector3 = (side[1] - side[0]).cross(side[3] - side[0]).normalized()
			if n.y < 0.0:
				n = -n
			var slope_len: float = (side[0] as Vector3).distance_to(side[3])
			_tri(st, [side[0], side[1], side[2]], [Vector2(0, 0), Vector2(rlen, 0), Vector2(rlen, slope_len)], n, roof, uv2_roof)
			_tri(st, [side[0], side[2], side[3]], [Vector2(0, 0), Vector2(rlen, slope_len), Vector2(0, slope_len)], n, roof, uv2_roof)
		# gables
		for g in [[q[(s + 1) % 4], q[(s + 2) % 4], r1], [q[(s + 3) % 4], q[s], r2]]:
			var n: Vector3 = Vector3((g[1] - g[0]).z, 0.0, -(g[1] - g[0]).x).normalized()
			var w: float = (g[0] as Vector3).distance_to(g[1])
			_tri(st, g, [Vector2(0, eave - ground_hi), Vector2(w, eave - ground_hi), Vector2(w * 0.5, eave - ground_hi + ridge)], n, wall, uv2_wall)
	else:
		var poly := PackedVector2Array(ring)
		var tris := Geometry2D.triangulate_polygon(poly)
		for k in range(0, tris.size(), 3):
			var pts := []
			var uvs := []
			for j in 3:
				var v := ring[tris[k + j]]
				pts.append(Vector3(v.x - c.x, eave, v.y - c.y))
				uvs.append(v)
			_tri(st, pts, uvs, Vector3.UP, roof, uv2_roof)

## One triangle facing n (the winding is fixed to match), with per-vertex UVs and a colour.
static func _tri(st: SurfaceTool, pts: Array, uvs: Array, n: Vector3, col: Color, uv2: Vector2) -> void:
	var a: Vector3 = pts[0]
	var b: Vector3 = pts[1]
	var cc: Vector3 = pts[2]
	var order := [0, 1, 2]
	# Godot's front faces wind clockwise seen from the front
	if (b - a).cross(cc - a).dot(n) > 0.0:
		order = [0, 2, 1]
	for j in order:
		st.set_normal(n)
		st.set_color(col)
		st.set_uv(uvs[j])
		st.set_uv2(uv2)
		st.add_vertex(pts[j])

# --------------------------------------------------------------------------------------------- grandstands

## The mapped grandstands, each built from the trackside pieces on its footprint: the rectangle that fits it
## best, facing the circuit from its nearer long side, as many tiers as its depth holds.
func _build_stands(root: Node3D) -> void:
	var node := Node3D.new()
	node.name = "Grandstands"
	root.add_child(node)
	var clear := track.half + track.cfg.runoff + 1.0
	var c: Vector2 = world.world_center
	var n := 0
	for flat in env.get("stands", []):
		var pts := PackedVector2Array()
		for k in range(0, flat.size() - 1, 2):
			pts.append(Vector2(flat[k], flat[k + 1]))
		var rect := _fit_rect(pts)
		if rect.is_empty():
			continue
		var centre: Vector2 = rect.centre
		var u: Vector2 = rect.u
		var v := Vector2(-u.y, u.x)
		var length: float = rect.length
		var depth: float = rect.depth
		if length < 8.0 or depth < 4.5 or _reserved(centre.x, centre.y, clear):
			continue
		# the front is the long side nearer the track
		var fa := centre + v * depth * 0.5
		var fb := centre - v * depth * 0.5
		var toward := v if track_distance(fa.x, fa.y).y < track_distance(fb.x, fb.y).y else -v
		var front := centre + toward * depth * 0.5
		# the roof overhangs the front: keep all of it clear of the road, set back if need be (the mapped
		# outlines and the circuit's line don't always agree to the metre)
		var nearest := INF
		for k in 9:
			var q: Vector2 = front + u * length * (k / 8.0 - 0.5) + toward * (world.STAND_ROOF_OVERHANG + 0.5)
			nearest = minf(nearest, track_distance(q.x, q.y).y)
		if nearest < clear + 1.0:
			if clear + 1.0 - nearest > 10.0:
				continue
			front -= toward * (clear + 1.0 - nearest)
		var ground := INF
		for p in pts:
			ground = minf(ground, ground_height(p.x, p.y))
		var z := Vector3(toward.x, 0.0, toward.y) # local +z towards the track
		var basis := Basis(Vector3.UP.cross(z).normalized(), Vector3.UP, z)
		var tiers := clampi(floori((depth - 2.1) / world.STAND_TREAD), 3, 14)
		var bays := maxi(1, roundi(length / world.STAND_BAY))
		var xf := Transform3D(basis, Vector3(front.x - c.x, ground, front.y - c.y))
		world.add_stand(node, "Stand_%02d" % n, xf, bays, tiers, n + 7, length / (bays * world.STAND_BAY), 700.0)
		n += 1

## The rectangle of least area round a footprint: {centre, u (unit, along the long side), length, depth}, or
## {} for a degenerate one.
static func _fit_rect(pts: PackedVector2Array) -> Dictionary:
	var hull := Geometry2D.convex_hull(pts)
	if hull.size() < 4:
		return {}
	var best := {}
	var best_area := INF
	for i in hull.size() - 1:
		var e := (hull[i + 1] - hull[i]).normalized()
		if e.length_squared() < 0.5:
			continue
		var f := Vector2(-e.y, e.x)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p in hull:
			var q := Vector2(p.dot(e), p.dot(f))
			lo = lo.min(q)
			hi = hi.max(q)
		var size := hi - lo
		if size.x * size.y < best_area:
			best_area = size.x * size.y
			var mid := (lo + hi) * 0.5
			var centre := e * mid.x + f * mid.y
			best = {"centre": centre, "u": e, "length": size.x, "depth": size.y} if size.x >= size.y \
				else {"centre": centre, "u": f, "length": size.y, "depth": size.x}
	return best

# --------------------------------------------------------------------------------------------- water

## Lakes and ponds as flat water at their lowest shore, rivers as ribbons over the ground.
func _build_water(root: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	var c: Vector2 = world.world_center
	for ring in env.get("water", []):
		var poly := PackedVector2Array()
		var shore := INF
		for k in range(0, ring.size() - 1, 2):
			poly.append(Vector2(ring[k], ring[k + 1]))
		if poly.size() > 1 and poly[0].is_equal_approx(poly[poly.size() - 1]):
			poly.remove_at(poly.size() - 1)
		if poly.size() < 3:
			continue
		var skip := false
		for p in poly:
			shore = minf(shore, ground_height(p.x, p.y))
			if track_distance(p.x, p.y).y < track.half + track.cfg.runoff + 1.0:
				skip = true
		if skip:
			continue
		var tris := Geometry2D.triangulate_polygon(poly)
		for k in range(0, tris.size(), 3):
			var pts := []
			var uvs := []
			for j in 3:
				var v := poly[tris[k + j]]
				pts.append(Vector3(v.x - c.x, shore + 0.35, v.y - c.y))
				uvs.append(Vector2(0.5, 0.5))
			_tri(st, pts, uvs, Vector3.UP, Color.WHITE, Vector2.ZERO)
			any = true
	for river in env.get("rivers", []):
		var width: float = river[0]
		var pts := _along(river.slice(1), 4.0)
		for k in pts.size() - 1:
			var a := pts[k]
			var b := pts[k + 1]
			var side := Vector2(-(b - a).y, (b - a).x).normalized() * width * 0.5
			var ya: float = ground_height(a.x, a.y) + 0.25
			var yb: float = ground_height(b.x, b.y) + 0.25
			var q := [Vector3(a.x - side.x - c.x, ya, a.y - side.y - c.y), Vector3(a.x + side.x - c.x, ya, a.y + side.y - c.y),
				Vector3(b.x + side.x - c.x, yb, b.y + side.y - c.y), Vector3(b.x - side.x - c.x, yb, b.y - side.y - c.y)]
			var uvs := [Vector2(0.5, 0.5), Vector2(0.5, 0.5), Vector2(0.5, 0.5)]
			_tri(st, [q[0], q[1], q[2]], uvs, Vector3.UP, Color.WHITE, Vector2.ZERO)
			_tri(st, [q[0], q[2], q[3]], uvs, Vector3.UP, Color.WHITE, Vector2.ZERO)
			any = true
	if not any:
		return
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	mat.set_shader_parameter("ripples", world.noise_texture("ripples"))
	mat.set_shader_parameter("deep_color", Color("#1d3a3a"))
	mat.set_shader_parameter("shallow_color", Color("#2e5048"))
	mat.set_shader_parameter("choppy", 0.35)
	var inst := MeshInstance3D.new()
	inst.name = "Water"
	inst.mesh = st.commit()
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(inst)

# --------------------------------------------------------------------------------------------- hedges

## Hedgerows: a clipped band of green 1.8 m high along each mapped hedge.
func _build_hedges(root: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	var c: Vector2 = world.world_center
	var clear := _clear_distance() - 2.0
	var green := Color("#3e5a2e")
	for line in env.get("hedges", []):
		if line.is_empty() or line[0] == -1.0:
			continue
		var pts := _along(line, 3.0)
		for k in pts.size() - 1:
			var a := pts[k]
			var b := pts[k + 1]
			if _reserved(a.x, a.y, clear) or _reserved(b.x, b.y, clear):
				continue
			var side := Vector2(-(b - a).y, (b - a).x).normalized() * 0.6
			var ya: float = ground_height(a.x, a.y) - 0.2
			var yb: float = ground_height(b.x, b.y) - 0.2
			var ha := 1.6 + _rand(a.x, a.y, 14.0) * 0.6
			var hb := 1.6 + _rand(b.x, b.y, 14.0) * 0.6
			var tint := green.lightened(_rand(a.x, a.y, 15.0) * 0.12)
			for sgn in [-1.0, 1.0]:
				var o: Vector2 = side * sgn
				var n := Vector3(o.x, 0.0, o.y).normalized()
				var q := [Vector3(a.x + o.x - c.x, ya, a.y + o.y - c.y), Vector3(b.x + o.x - c.x, yb, b.y + o.y - c.y),
					Vector3(b.x + o.x * 0.7 - c.x, yb + hb, b.y + o.y * 0.7 - c.y), Vector3(a.x + o.x * 0.7 - c.x, ya + ha, a.y + o.y * 0.7 - c.y)]
				var uvs := [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
				_tri(st, [q[0], q[1], q[2]], uvs, n, tint, Vector2.ZERO)
				_tri(st, [q[0], q[2], q[3]], uvs, n, tint, Vector2.ZERO)
			var top := [Vector3(a.x - side.x * 0.7 - c.x, ya + ha, a.y - side.y * 0.7 - c.y), Vector3(a.x + side.x * 0.7 - c.x, ya + ha, a.y + side.y * 0.7 - c.y),
				Vector3(b.x + side.x * 0.7 - c.x, yb + hb, b.y + side.y * 0.7 - c.y), Vector3(b.x - side.x * 0.7 - c.x, yb + hb, b.y - side.y * 0.7 - c.y)]
			var uvs := [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
			_tri(st, [top[0], top[1], top[2]], uvs, Vector3.UP, tint.lightened(0.08), Vector2.ZERO)
			_tri(st, [top[0], top[2], top[3]], uvs, Vector3.UP, tint.lightened(0.08), Vector2.ZERO)
			any = true
	if not any:
		return
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.95
	mat.albedo_texture = world.noise_texture("grain")
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE * 0.6
	var inst := MeshInstance3D.new()
	inst.name = "Hedges"
	inst.mesh = st.commit()
	inst.material_override = mat
	root.add_child(inst)
