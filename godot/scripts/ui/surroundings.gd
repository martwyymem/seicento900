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
const BANK_WIDTH := 12.0 ## metres across the disused banking (Monza's Sopraelevata), from its inner edge
const BANK_RISE := 7.0 ## metres the banking climbs to its outer edge, on a curve steepening to about 40 degrees
const BANK_BRIDGE := 6.5 ## metres the ring is lifted where it passes over a road
const BANK_EASE := 80.0 ## metres over which the banking climbs from flat, at either end of a stretch
const LANDMARKS_PATH := "res://models/landmarks.glb"
## Footprint (length along the model's x, width along z; metres) each Blender landmark (build_landmarks.py) is
## modelled at. The mapped footprint stretches it to fit; pieces not listed keep their size.
const LANDMARK_SIZE := {
	"IndyPagoda": Vector2(57.5, 33.4), "SilverstoneWing": Vector2(374.0, 32.6), "Casino": Vector2(60.0, 160.0),
	"CastleKeep": Vector2(9.5, 9.5), "CastleTower": Vector2(6.0, 6.0), "CastleWall": Vector2(1.0, 1.8),
	"Barbakan": Vector2(38.0, 31.5), "FloriaGate": Vector2(10.0, 9.2), "PszczynaCastle": Vector2(58.0, 45.2),
	"WilamowiceChurch": Vector2(49.6, 23.2),
}
const WATER_SHADER := preload("res://shaders/water.gdshader")
const CHUNK := 256.0 ## metres: trees, canopy and buildings are split into tiles of this size for culling
const STAND_SECTION := 60.0 ## m: a grandstand bending round a corner is built as straight stands about this long
const STAND_FILL := 0.7 ## share of its best rectangle a straight stand's outline fills; less, and it bends
const TREE_BAND := [70.0, 90.0, 110.0, 140.0] ## trees one by one this far beyond the run-off, per quality
const TREE_CELL := [8.0, 7.0, 6.2, 5.5] ## one tree per cell of this size in a wood
const TREE_CAP := [9000, 16000, 26000, 40000]
const TREE_VISIBLE := [700.0, 1000.0, 1000.0, 0.0] ## how far the single trees are drawn (0 always); past 1 km they barely show but cost a fifth of the GPU frame at Monza

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
	"silverstone": "uk", "suzuka": "jp", "zandvoort": "nl", "indy": "us", "fiat": "pl",
	"tokyo": "jp", "bielsko": "pl", "krakow": "pl", "oswiecim": "pl", "wilamowice": "pl", "brzeszcze": "pl", "pszczyna": "pl", "bor": "pl", "goliath": "pl"}
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
static var _tree_sizes := {} ## species -> Vector2(crown radius, height) of its mesh, for the TV cameras' sightlines
static var _tree_reaches := {} ## species -> how far its mesh reaches from the trunk at scale 1, turned any way
var _bank_cells := {} ## 16 m cells (Vector2i) within reach of the banking, kept clear of trees
static var _landmark_meshes := {} ## Blender landmark meshes (and yachts) by name

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

## race_world._terrain_grid's layout, copied out of its dictionary once it exists: ground_height and
## track_distance run for every tree, canopy point and sightline step, and the lookups were most of their cost
var _grid_ready := false
var _gx0 := 0.0
var _gz0 := 0.0
var _gfine := 1.0
var _gnx := 0
var _gnz := 0
var _grow := 0
var _gh := PackedFloat32Array()
var _gi := PackedInt32Array()

func _grid() -> bool:
	if not _grid_ready:
		var t: Dictionary = world._terrain_grid
		if t.is_empty():
			return false
		_gx0 = t.x0
		_gz0 = t.z0
		_gfine = t.fine
		_gnx = t.nx
		_gnz = t.nz
		_grow = t.row
		_gh = t.h
		_gi = t.i
		_grid_ready = true
	return true

## World height of the terrain mesh at track point (x, z): on the detailed grid's triangles near the circuit
## (race_world._terrain_grid), from the elevation model (as the coarse terrain has it) further out.
func ground_height(x: float, z: float) -> float:
	if _grid_ready or _grid():
		var fx: float = (x - _gx0) / _gfine
		var fz: float = (z - _gz0) / _gfine
		var ix := floori(fx)
		var iz := floori(fz)
		if ix >= 0 and iz >= 0 and ix < _gnx and iz < _gnz:
			var row := _grow
			var h00 := _gh[iz * row + ix]
			var h10 := _gh[iz * row + ix + 1]
			var h01 := _gh[(iz + 1) * row + ix]
			var h11 := _gh[(iz + 1) * row + ix + 1]
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
	var best := Vector2(-1, INF)
	if not (_grid_ready or _grid()):
		return best
	var ix := floori((x - _gx0) / _gfine)
	var iz := floori((z - _gz0) / _gfine)
	for dz in 2:
		for dx in 2:
			var gx := ix + dx
			var gz := iz + dz
			if gx < 0 or gz < 0 or gx > _gnx or gz > _gnz:
				continue
			var k := _gi[gz * _grow + gx]
			if k < 0 or k == int(best.x):
				continue
			var d := Vector2(track.X[k] - x, track.Y[k] - z).length()
			if d < best.y:
				best = Vector2(k, d)
	return best

func has_buildings() -> bool:
	return not env.get("buildings", []).is_empty()

## Whether the circuit has the mapped landmark of this name (and its model).
func has_landmark(part: String) -> bool:
	if not landmark_meshes().has(part):
		return false
	for lm in env.get("landmarks", []):
		if lm[0] == part:
			return true
	return false

## The Blender landmarks and yachts (tools/blender/build_landmarks.py) by name.
static func landmark_meshes() -> Dictionary:
	if _landmark_meshes.is_empty():
		var scene: Node = WORLD_ASSETS._load_model(LANDMARKS_PATH)
		if scene:
			for mi in scene.find_children("*", "MeshInstance3D", true, false):
				_landmark_meshes[mi.name] = (mi as MeshInstance3D).mesh
			scene.free()
	return _landmark_meshes

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
	_build_surroundings(root)

func _build_surroundings(root: Node3D) -> void:
	_build_banking(root) # first: it keeps the trees off its ground
	_build_woods(root)
	_build_buildings(root)
	_build_stands(root)
	_build_water(root)
	_build_hedges(root)
	_build_landmarks(root)
	_build_pools(root)
	_build_road_blockages(root)
	TramRails.build(root, world, track, env.get("tram_rails", []))

# --------------------------------------------------------------------------------------------- exclusions

## Whether a spot is kept for the circuit's own structures: the run-off (clear metres from the centreline),
## the pit building and race control, the main grandstands and the TV towers.
func _reserved(x: float, z: float, clear: float) -> bool:
	if not _bank_cells.is_empty() and _bank_cells.has(Vector2i(floori(x / 16.0), floori(z / 16.0))):
		return true
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
	foliage.set_shader_parameter("variety", 1.0)
	foliage.set_shader_parameter("translucency", 0.5)
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

## What a species' tree hides at scale 1: Vector2(radius, height). A crown is lumpy and gappy, so its
## solid part is taken as three quarters of its spread.
static func _tree_size(species: String) -> Vector2:
	if not _tree_sizes.has(species):
		var mesh: Mesh = tree_meshes().get(species)
		var box := mesh.get_aabb() if mesh else AABB(Vector3(-3.0, 0.0, -3.0), Vector3(6.0, 14.0, 6.0))
		_tree_sizes[species] = Vector2(0.75 * 0.5 * maxf(box.size.x, box.size.z), box.end.y)
	return _tree_sizes[species]

## How far a species' tree reaches out from its trunk at scale 1 (its farthest vertex), whichever way it is
## turned: what has to stay out of the run-off.
static func _tree_reach(species: String) -> float:
	if not _tree_reaches.has(species):
		var mesh: Mesh = tree_meshes().get(species)
		var r := 3.0
		if mesh:
			r = 0.0
			for k in mesh.get_surface_count():
				for v in mesh.surface_get_arrays(k)[Mesh.ARRAY_VERTEX]:
					r = maxf(r, Vector2(v.x, v.z).length())
		_tree_reaches[species] = r
	return _tree_reaches[species]

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
	var size := (0.72 + _rand(x, z, 5.0) * 0.5) * scale
	var tall := size * (0.9 + _rand(x, z, 7.0) * 0.25)
	var dims := _tree_size(species)
	# the trunk stands clear of the run-off; keep the crown (its full spread) out of it too. track_distance is
	# a coarse lookup, a couple of metres out, so a crown near the edge is measured from the centreline itself.
	var near: Vector2 = track_distance(x, z)
	if near.x >= 0:
		var edge: float = track.half + track.cfg.runoff
		var crown := _tree_reach(species)
		var room: float = near.y - edge
		if crown * size > room - 4.0:
			room = minf(room, track.project(x, z, near.x * track.step)[2] - edge)
		if crown * size > room:
			var fit := maxf(0.0, room) / (crown * size)
			if fit * size < 0.45 * scale:
				return # too small to look like a tree there
			size *= fit
			tall *= fit
	var c := _chunk(x, z)
	if not chunks.has(c):
		chunks[c] = {}
	if not chunks[c].has(species):
		chunks[c][species] = [[], []]
	var basis := Basis(Vector3.UP, _rand(x, z, 6.0) * TAU).scaled(Vector3(size, tall, size))
	var y: float = ground_height(x, z) - 0.3
	chunks[c][species][0].append(Transform3D(basis, Vector3(x - world.world_center.x, y, z - world.world_center.y)))
	world.add_occluder(x - world.world_center.x, z - world.world_center.y, dims.x * size, y + dims.y * tall)
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
				if near.y > inner and not _bank_cells.has(Vector2i(floori(x / 16.0), floori(z / 16.0))):
					inside[jz * (nx + 1) + jx] = 1
	# the cells drawn (three or four corners in the wood), by chunk, and the grid points they need
	var row := nx + 1
	var chunks := {} # chunk -> [index of the cell's first corner, ...]
	var need := PackedByteArray()
	need.resize(inside.size())
	for jz in nz:
		for jx in nx:
			var k := jz * row + jx
			if inside[k] + inside[k + 1] + inside[k + row] + inside[k + row + 1] < 3:
				continue
			need[k] = 1
			need[k + 1] = 1
			need[k + row] = 1
			need[k + row + 1] = 1
			var key := _chunk(x0 + jx * cell, z0 + jz * cell)
			if not chunks.has(key):
				chunks[key] = []
			chunks[key].append(k)
	if chunks.is_empty():
		return
	# the crown's top at each of those points, once: a point outside the wood or on its edge is the rim,
	# which comes down towards the ground
	var tops := PackedVector3Array()
	tops.resize(inside.size())
	for jz in nz + 1:
		for jx in nx + 1:
			var k := jz * row + jx
			if need[k] == 0:
				continue
			var x := x0 + jx * cell
			var z := z0 + jz * cell
			var lump := _rand(float(jx), float(jz), 11.0)
			var h := 4.0 + lump * 3.0
			if inside[k] == 1 and not _is_rim(inside, row, nx, nz, jx, jz):
				var broad := 0.5 + 0.5 * sin(x * 0.013 + z * 0.007) * cos(z * 0.009 - x * 0.005)
				h = 14.0 + broad * 6.0 + lump * 4.0
			tops[k] = Vector3(x - world.world_center.x, ground_height(x, z) + h, z - world.world_center.y)
	var mat := ShaderMaterial.new()
	mat.shader = CANOPY_SHADER
	mat.set_shader_parameter("grain", world.noise_texture("grain"))
	mat.set_shader_parameter("conifer_share", clampf(track.cfg.tree_conifer, 0.0, 1.0))
	world._wet_materials.append(mat)
	var canopy := Node3D.new()
	canopy.name = "Canopy"
	root.add_child(canopy)
	for key in chunks:
		var verts := PackedVector3Array()
		for k in chunks[key]:
			var p00 := tops[k]
			var p10 := tops[k + 1]
			var p01 := tops[k + row]
			var p11 := tops[k + row + 1]
			# a corner outside the wood drops its triangle
			if inside[k] == 0:
				verts.append_array(PackedVector3Array([p10, p11, p01]))
			elif inside[k + 1] == 0:
				verts.append_array(PackedVector3Array([p00, p11, p01]))
			elif inside[k + row] == 0:
				verts.append_array(PackedVector3Array([p00, p10, p11]))
			elif inside[k + row + 1] == 0:
				verts.append_array(PackedVector3Array([p00, p10, p01]))
			else:
				verts.append_array(PackedVector3Array([p00, p10, p01, p10, p11, p01]))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var inst := MeshInstance3D.new()
		inst.mesh = mesh
		inst.material_override = mat
		canopy.add_child(inst)

## A wood's grid point next to one outside it (or on the grid's edge).
static func _is_rim(inside: PackedByteArray, row: int, nx: int, nz: int, jx: int, jz: int) -> bool:
	if jx == 0 or jz == 0 or jx == nx or jz == nz:
		return true
	var k := jz * row + jx
	return inside[k - 1] == 0 or inside[k + 1] == 0 or inside[k - row] == 0 or inside[k + row] == 0

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
	# (on a street stage the old houses stand right behind the barrier, as they do by the real road)
	var clear := track.half + track.cfg.runoff + (0.3 if track.cfg.street_stage else (1.2 if city else 4.0))
	var casino: Dictionary = {} if has_landmark("Casino") else world._casino_spot()
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
		if track.cfg.street_stage: # real houses stay, whatever a TV camera would like to see
			var near := track_distance(centre.x, centre.y)
			skip = near.x >= 0 and near.y < clear
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
	TownBuilder.apply_building_textures(mat)
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
	var footprint := PackedVector2Array()
	for p in ring:
		footprint.append(p - c)
	world.add_block_occluder(footprint, eave)
	var uv2_wall := Vector2(seed, kind)
	var uv2_roof := Vector2(seed, kind + 10.0)
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		var ln := a.distance_to(b)
		var out := Vector3(b.y - a.y, 0.0, a.x - b.x).normalized() # outward for a counter-clockwise ring
		var a0 := Vector3(a.x - c.x, base, a.y - c.y)
		var b0 := Vector3(b.x - c.x, base, b.y - c.y)
		var a1 := Vector3(a.x - c.x, eave, a.y - c.y)
		var b1 := Vector3(b.x - c.x, eave, b.y - c.y)
		# UV.x restarts at each wall's start and UV2 carries the wall's length and level top (corner quoins and a
		# cornice in building.gdshader, same encoding as TownBuilder._wall)
		var u0 := 0.0
		var u1 := ln
		var wall_uv2 := Vector2(seed + roundf((eave - ground_hi) * 10.0), kind + 20.0 * minf(roundf(ln * 10.0), 4000.0))
		# v is metres up from the highest ground under the building, where the windows start
		var v0 := base - ground_hi
		var v1 := eave - ground_hi
		_tri(st, [a0, b0, b1], [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1)], out, wall, wall_uv2)
		_tri(st, [a0, b1, a1], [Vector2(u0, v0), Vector2(u1, v1), Vector2(u0, v1)], out, wall, wall_uv2)
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
	var batch := {} # every stand's parts in one MultiMesh each (RaceWorld.flush_stands)
	for flat in env.get("stands", []):
		var pts := PackedVector2Array()
		for k in range(0, flat.size() - 1, 2):
			pts.append(Vector2(flat[k], flat[k + 1]))
		var rect := _fit_rect(pts)
		if rect.is_empty() or rect.length < 8.0 or rect.depth < 4.5:
			continue
		# the side of the road the outline stands on, from the stretch nearest its middle
		var mid := Vector2.ZERO
		for p in pts:
			mid += p
		mid /= pts.size()
		var near := track_distance(mid.x, mid.y)
		if near.x < 0:
			continue
		var i := int(near.x)
		var normal := Vector2(track.NX[i], track.NY[i])
		var side := 1.0 if (mid - Vector2(track.X[i], track.Y[i])).dot(normal) >= 0.0 else -1.0
		var pieces: Array = []
		if absf(_polygon_area(pts)) >= STAND_FILL * rect.length * rect.depth:
			# a straight stand: its rectangle, the long side towards the road in front
			var u: Vector2 = rect.u
			var v := Vector2(-u.y, u.x)
			var toward := v if v.dot(normal * -side) > 0.0 else -v
			pieces.append({"front": rect.centre + toward * rect.depth * 0.5, "u": u, "toward": toward,
				"length": rect.length, "depth": rect.depth, "s": i * track.step})
		else:
			# one bending round a corner fills little of its rectangle, whose long side can lie across the road
			# (Indianapolis): straight stands that follow the road instead
			pieces = _stand_sections(pts, i * track.step, side)
		for piece in pieces:
			var placed := _place_stand(piece, side, clear)
			if placed.is_empty() or _reserved(placed.middle.x, placed.middle.y, clear):
				continue
			var toward: Vector2 = placed.toward
			var z := Vector3(toward.x, 0.0, toward.y) # local +z towards the track
			var basis := Basis(Vector3.UP.cross(z).normalized(), Vector3.UP, z)
			var length: float = placed.length
			var bays := maxi(1, roundi(length / world.STAND_BAY))
			var front: Vector2 = placed.front
			var xf := Transform3D(basis, Vector3(front.x - c.x, placed.ground, front.y - c.y))
			world.add_stand(node, "Stand_%02d" % n, xf, bays, placed.tiers, n + 7, length / (bays * world.STAND_BAY), 700.0, batch)
			n += 1
	world.flush_stands(node, batch)

## The straight stands an outline bending round a corner becomes: pieces of about STAND_SECTION m along the road,
## each parallel to it, from the outline's inner edge to its outer edge (their medians over the piece), found by
## walking out from the centreline on the stand's side.
func _stand_sections(pts: PackedVector2Array, s_mid: float, side: float) -> Array:
	var lo := INF
	var hi := -INF
	for p in pts:
		var near := track_distance(p.x, p.y)
		if near.x >= 0:
			var rel := track.rel(near.x * track.step - s_mid)
			lo = minf(lo, rel)
			hi = maxf(hi, rel)
	if hi - lo < 8.0:
		return []
	var count := maxi(1, roundi((hi - lo) / STAND_SECTION))
	var span := (hi - lo) / count
	var out := []
	for j in count:
		var s0 := s_mid + lo + j * span
		var inner := PackedFloat32Array()
		var outer := PackedFloat32Array()
		var s := s0 + 2.5
		while s < s0 + span:
			var first := -1.0
			var last := -1.0
			var d := 0.0
			while d <= 120.0:
				var q := track.pos(s, side * d)
				if Geometry2D.is_point_in_polygon(Vector2(q[0], q[1]), pts):
					if first < 0.0:
						first = d
					last = d
				d += 1.5
			if first >= 0.0:
				inner.append(first)
				outer.append(last)
			s += 5.0
		if inner.size() < 2:
			continue
		inner.sort()
		outer.sort()
		var front_d: float = inner[inner.size() >> 1]
		var back_d: float = outer[outer.size() >> 1]
		var sm := s0 + span * 0.5
		var a := track.pos(sm, 0.0)
		var b := track.pos(sm, side)
		var away := Vector2(b[0] - a[0], b[1] - a[1]).normalized()
		out.append({"front": Vector2(a[0], a[1]) + away * front_d, "u": Vector2(-away.y, away.x), "toward": -away,
			"length": span, "depth": back_d - front_d + 1.5, "s": sm})
	return out

## Sets a stand ({front, u along it, toward the road, length, depth, s}) back until all of it, from the roof's
## overhang in front to the concourse behind and end to end, is clear of the road and run-off on its own side of
## the road (a point across the road falls short by the whole width); {} when that takes more than 10 m. Returns it
## with tiers, middle (of the footprint) and ground (its lowest point).
func _place_stand(piece: Dictionary, side: float, clear: float) -> Dictionary:
	var front: Vector2 = piece.front
	var u: Vector2 = piece.u
	var toward: Vector2 = piece.toward
	var length: float = piece.length
	var tiers := clampi(floori((float(piece.depth) - 2.1) / world.STAND_TREAD), 3, 14)
	var back: float = tiers * world.STAND_TREAD + world.STAND_CONCOURSE # as add_stand builds it
	var along := maxi(2, ceili(length / 8.0))
	var moved := 0.0
	for _pass in 4:
		var deficit := 0.0
		var ground := INF
		for k in along + 1:
			for a in [world.STAND_ROOF_OVERHANG + 0.5, 0.0, -back * 0.5, -back]:
				var q: Vector2 = front + u * length * (float(k) / along - 0.5) + toward * a
				var near := track_distance(q.x, q.y)
				ground = minf(ground, ground_height(q.x, q.y))
				if near.x < 0:
					continue
				var i := int(near.x)
				var off := near.y
				# measured across this stretch of road on the stand's side; another stretch by its distance alone
				if absf(track.rel(i * track.step - float(piece.s))) < 200.0:
					off = (q - Vector2(track.X[i], track.Y[i])).dot(Vector2(track.NX[i], track.NY[i])) * side
				deficit = maxf(deficit, clear + 1.0 - off)
		if deficit <= 0.05:
			return {"front": front, "toward": toward, "length": length, "tiers": tiers, "ground": ground,
				"middle": front - toward * back * 0.5}
		moved += deficit
		if moved > 10.0:
			return {}
		front -= toward * deficit
	return {}

## Signed area of a polygon (positive anticlockwise).
static func _polygon_area(pts: PackedVector2Array) -> float:
	var area := 0.0
	for k in pts.size():
		var a := pts[k]
		var b := pts[(k + 1) % pts.size()]
		area += a.x * b.y - b.x * a.y
	return area * 0.5

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

## Lakes and ponds as flat water at their lowest shore, rivers mapped as areas and rivers mapped as lines as
## ribbons over the ground. The areas are cut to the circuit's own terrain: past it is only the far land
## (far_land.gd, which has the lakes and rivers from its land cover), drawn behind everything, so water carried
## on out there would lie over the hills as a flat sheet.
func _build_water(root: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	var c: Vector2 = world.world_center
	var r := land_rect.grow(-2.0)
	var terrain := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	for ring in env.get("water", []):
		var poly := PackedVector2Array()
		for k in range(0, ring.size() - 1, 2):
			poly.append(Vector2(ring[k], ring[k + 1]))
		if poly.size() > 1 and poly[0].is_equal_approx(poly[poly.size() - 1]):
			poly.remove_at(poly.size() - 1)
		if poly.size() < 3:
			continue
		var skip := false
		for p in poly:
			if track_distance(p.x, p.y).y < track.half + track.cfg.runoff + 1.0:
				skip = true
		if skip:
			continue
		for part in Geometry2D.intersect_polygons(poly, terrain):
			var shore := INF
			var top := -INF
			for p in part:
				var h := ground_height(p.x, p.y)
				shore = minf(shore, h)
				top = maxf(top, h)
			# a river's banks fall along it (1 is 4 m): it follows the ground rather than lying flat
			var flowing := top - shore > 1.0
			var tris := Geometry2D.triangulate_polygon(part)
			for k in range(0, tris.size(), 3):
				var pts := []
				var uvs := []
				for j in 3:
					var v := part[tris[k + j]]
					pts.append(Vector3(v.x - c.x, (ground_height(v.x, v.y) + 0.25) if flowing else shore + 0.35, v.y - c.y))
					uvs.append(Vector2(0.5, 0.5))
				_tri(st, pts, uvs, Vector3.UP, Color.WHITE, Vector2.ZERO)
				any = true
	for river in env.get("rivers", []):
		var width: float = river[0]
		var pts := _along(river.slice(1), 4.0)
		for k in pts.size() - 1:
			var a := pts[k]
			var b := pts[k + 1]
			if not (r.has_point(a) and r.has_point(b)):
				continue
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

# --------------------------------------------------------------------------------------------- landmarks

## The mapped landmarks (env "landmarks": [model, x, y, length, width, angle, height]) as their Blender models,
## stretched to the mapped footprint, on the ground, and turned so the front faces the nearest track.
func _build_landmarks(root: Node3D) -> void:
	var meshes := landmark_meshes()
	var c: Vector2 = world.world_center
	for lm in env.get("landmarks", []):
		var part: String = lm[0]
		if not meshes.has(part):
			continue
		var at := Vector2(lm[1], lm[2])
		var length: float = lm[3]
		var width: float = lm[4]
		var angle: float = lm[5]
		var height: float = lm[6]
		var nominal: Vector2 = LANDMARK_SIZE.get(part, Vector2.ZERO)
		var scale := Vector3.ONE
		if nominal != Vector2.ZERO:
			if (nominal.x >= nominal.y) != (length >= width): # the mapped long side is the model's short one
				var t := length
				length = width
				width = t
				angle += PI * 0.5
			scale.x = length / nominal.x
			scale.z = width / nominal.y
			if part == "CastleKeep" and height > 0.0:
				scale.y = height / 20.0
		# turned to the track from where it is mapped: moved back clear of the circuit below, it would often be
		# nearer another stretch (the Casino the tunnel, behind it, instead of Casino Square in front)
		var rot := -angle
		var near := _nearest_track_point(at)
		var to_track := near - at
		var front := Vector2(-sin(angle), cos(angle)) # the model's +z
		if part != "TyreBridge" and to_track.dot(front) < 0.0:
			rot += PI
		if part not in ["TyreBridge", "MonzaPodio"]: # those two span the road on purpose
			# the footprint as drawn (the model stretched to the mapped one, or at its own size) round its middle
			var box: AABB = (meshes[part] as Mesh).get_aabb()
			var mid := box.get_center() * scale
			var off := Vector2(mid.x, mid.z).rotated(-rot)
			at = _clear_of_circuit(at + off, Vector2(box.size.x * scale.x, box.size.z * scale.z), angle) - off
		var y := INF
		var low := INF
		var half := Vector2(length, width) * 0.5
		var cs := cos(angle)
		var sn := sin(angle)
		# the ground over the footprint: a long building (the Casino) stands across a slope of tens of metres
		var heights: Array[float] = []
		for gx in range(-2, 3):
			for gz in range(-2, 3):
				var q := Vector2(gx * 0.5 * half.x, gz * 0.5 * half.y)
				heights.append(ground_height(at.x + q.x * cs - q.y * sn, at.y + q.x * sn + q.y * cs))
		heights.sort()
		low = heights[0]
		if nominal != Vector2.ZERO:
			# stand on the upper ground, not the lowest corner (which buries the uphill half), and carry the
			# walls down to the lowest ground on a stone terrace
			y = heights[int(heights.size() * 0.75)]
		else:
			y = low
		if part == "TyreBridge": # arches over the road, wide enough for the run-off
			var k := clampf((track.half + track.cfg.runoff + 1.5) / 11.5, 1.0, 2.2)
			scale.x = k
			scale.y = k
			y = ground_height(at.x, at.y)
		var mi := MeshInstance3D.new()
		mi.name = part
		mi.mesh = meshes[part]
		mi.transform = Transform3D(Basis(Vector3.UP, rot) * Basis.from_scale(scale),
				Vector3(at.x - c.x, y, at.y - c.y))
		root.add_child(mi)
		if part not in ["TyreBridge", "MonzaPodio"]: # the TV cameras see under those
			var box: AABB = (meshes[part] as Mesh).get_aabb()
			var foot := half if half.x > 0.0 and half.y > 0.0 else Vector2(box.size.x, box.size.z) * 0.5
			var corners := PackedVector2Array()
			for q in [Vector2(-foot.x, -foot.y), Vector2(foot.x, -foot.y), foot, Vector2(-foot.x, foot.y)]:
				corners.append(Vector2(at.x + q.x * cs - q.y * sn, at.y + q.x * sn + q.y * cs) - c)
			world.add_block_occluder(corners, y + box.end.y * scale.y)
		if nominal != Vector2.ZERO and y - low > 0.4:
			var terrace := MeshInstance3D.new()
			terrace.name = part + "Terrace"
			var box := BoxMesh.new()
			box.size = Vector3(length + 0.6, y - low + 1.0, width + 0.6)
			terrace.mesh = box
			terrace.material_override = _terrace_material()
			terrace.transform = Transform3D(Basis(Vector3.UP, rot), Vector3(at.x - c.x, (y + low) * 0.5 - 0.4, at.y - c.y))
			root.add_child(terrace)

func _terrace_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#a39b8b")
	m.roughness = 0.95
	return m

## A landmark moved straight back from the circuit until its footprint (extent along `angle` and across it)
## keeps clear of the run-off, and of the pit lane where that runs alongside: the game's road and lane do not
## lie exactly where the mapped ones do (Indianapolis' scoring pylon was mapped onto the front stretch, the
## Monaco Casino's corner onto Casino Square). Where it is squeezed between two stretches, the nearest clear
## spot round the mapped one.
func _clear_of_circuit(at: Vector2, extent: Vector2, angle: float) -> Vector2:
	var axis := Vector2(cos(angle), sin(angle))
	var across := Vector2(-axis.y, axis.x)
	# the outline every 2 m or so (a road across the footprint crosses it) and the centre
	var outline: Array[Vector2] = [Vector2.ZERO]
	var nu := maxi(1, ceili(extent.x / 2.0))
	var nv := maxi(1, ceili(extent.y / 2.0))
	for k in nu:
		var u := (float(k) / nu - 0.5) * extent.x
		outline.append(axis * u - across * (0.5 * extent.y))
		outline.append(-axis * u + across * (0.5 * extent.y))
	for k in nv:
		var v := (float(k) / nv - 0.5) * extent.y
		outline.append(axis * (0.5 * extent.x) + across * v)
		outline.append(-axis * (0.5 * extent.x) - across * v)
	var mapped := at
	for _pass in 12:
		var push := _intrusion(at, outline)
		if push == Vector2.ZERO:
			return at
		at += push
	for r in range(4, 81, 4):
		for k in 24:
			var p := mapped + Vector2.from_angle(k * TAU / 24.0) * r
			if _intrusion(p, outline) == Vector2.ZERO:
				return p
	return at

## How far, and which way, a footprint (outline points round `at`) must move to clear the run-off, and the pit
## lane where that runs alongside, at its worst point; Vector2.ZERO when it is clear. Each stretch of road pushes
## it towards the side its centre is on, so a corner that has crossed the road is pulled back over it rather than
## dragging the rest across.
func _intrusion(at: Vector2, outline: Array[Vector2]) -> Vector2:
	var po: float = track.cfg.pit_offset
	var lane_clear: float = absf(po) + world.PIT_FENCE_D + 1.5
	var worst := 0.0 # how far the footprint reaches into the space it must keep clear of
	var away := Vector2.ZERO
	for q in outline:
		var p := at + q
		var near := track_distance(p.x, p.y)
		if near.x < 0:
			continue
		var i := int(near.x)
		var centre := Vector2(track.X[i], track.Y[i])
		var normal := Vector2(track.NX[i], track.NY[i])
		var side := -1.0 if (at - centre).dot(normal) < 0.0 else 1.0
		var off := (p - centre).dot(normal) * side # below zero once past the centreline
		var need := _clear_distance()
		if absf(po) > 1.0 and side == signf(po) and track.pit_blend(i * track.step) > 0.0:
			need = maxf(need, lane_clear)
		if need - off > worst:
			worst = need - off
			away = normal * side
	return away * (worst + 0.5) if worst > 0.0 else Vector2.ZERO

## The nearest centreline sample to a track point.
func _nearest_track_point(p: Vector2) -> Vector2:
	var best := INF
	var out := p
	for i in track.X.size():
		var d := (track.X[i] - p.x) * (track.X[i] - p.x) + (track.Y[i] - p.y) * (track.Y[i] - p.y)
		if d < best:
			best = d
			out = Vector2(track.X[i], track.Y[i])
	return out

## Swimming pools in the gardens (env "pools": flat rings of x, y), a flat blue surface just above the ground.
func _build_pools(root: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	var c: Vector2 = world.world_center
	for ring in env.get("pools", []):
		var poly := PackedVector2Array()
		for k in range(0, ring.size() - 1, 2):
			poly.append(Vector2(ring[k], ring[k + 1]))
		if poly.size() > 1 and poly[0].is_equal_approx(poly[poly.size() - 1]):
			poly.remove_at(poly.size() - 1)
		if poly.size() < 3:
			continue
		var centre := Vector2.ZERO
		for p in poly:
			centre += p
		centre /= poly.size()
		if track_distance(centre.x, centre.y).y < _clear_distance():
			continue
		var tris := Geometry2D.triangulate_polygon(poly)
		if tris.is_empty():
			continue
		var y := INF
		for p in poly:
			y = minf(y, ground_height(p.x, p.y))
		y += 0.08
		for i in tris:
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(poly[i].x - c.x, y, poly[i].y - c.y))
		any = true
	if not any:
		return
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#3fb5d0")
	m.roughness = 0.12
	m.metallic_specular = 0.8
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.name = "Pools"
	mi.mesh = st.commit()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 600.0
	root.add_child(mi)

# --------------------------------------------------------------------------------------------- banking

## The disused banked ring (env "banking": [banked, x, y, bridge, ...] chains; Monza's Sopraelevata): a concrete
## slab climbing to the outside of each bend, an earth bank behind it, and lifted where it crosses a road.
## Scenery only: the road course does not use it. Flat chains (the ring's straight) are painted on the land map.
func _build_banking(root: Node3D) -> void:
	var slab := SurfaceTool.new()
	slab.begin(Mesh.PRIMITIVE_TRIANGLES)
	var earth := SurfaceTool.new()
	earth.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	var c: Vector2 = world.world_center
	var clear := _clear_distance()
	for chain in env.get("banking", []):
		if int(chain[0]) != 1:
			continue
		var raw: Array[Vector2] = []
		var bridge: Array[float] = []
		for k in range(1, chain.size() - 2, 3):
			raw.append(Vector2(chain[k], chain[k + 1]))
			bridge.append(float(chain[k + 2]))
		var line := _smooth_line(raw, bridge, 5.0)
		var pts: Array[Vector2] = line.pts
		var lift: Array[float] = line.lift
		if pts.size() < 3:
			continue
		var turn := 0.0
		for i in range(1, pts.size() - 1):
			turn += (pts[i] - pts[i - 1]).cross(pts[i + 1] - pts[i])
		var out_sign := -1.0 if turn > 0.0 else 1.0 # the outside of the bend, as a side of the heading's normal
		var count := pts.size()
		var normals: Array[Vector2] = []
		var near: Array[bool] = [] # over the circuit's run-off and its margin
		for i in count:
			var t := (pts[mini(i + 1, count - 1)] - pts[maxi(i - 1, 0)]).normalized()
			var n := Vector2(-t.y, t.x) * out_sign
			normals.append(n)
			var on := false
			for u in [-0.5, 0.0, 0.5]:
				var p: Vector2 = pts[i] + n * BANK_WIDTH * u
				on = on or track_distance(p.x, p.y).y < clear
			near.append(on)
		# where the ring crosses the circuit, the whole stretch over the run-off is bridge; elsewhere the ring is
		# left out over it (Monza's runs beside the first chicane before it climbs)
		var bridged := PackedByteArray()
		bridged.resize(count)
		var i0 := 0
		while i0 < count:
			var i1 := i0
			while i1 < count and near[i1] == near[i0]:
				i1 += 1
			var crosses := false
			for k in range(i0, i1):
				crosses = crosses or (near[k] and lift[k] > 0.5)
			for k in range(i0, i1):
				bridged[k] = int(crosses)
			i0 = i1
		var keep: Array[bool] = []
		var dropped := PackedByteArray()
		var to_bridge := _distance_along(pts, bridged, false)
		for i in count:
			keep.append(not near[i] or bridged[i] == 1)
			dropped.append(int(not keep[i]))
			lift[i] = maxf(lift[i], 1.0 - smoothstep(0.0, 25.0, to_bridge[i]))
		# the rise eases in and out at the ends of each stretch, which would otherwise stop in a 7 m cliff
		var to_end := _distance_along(pts, dropped, true)
		var rows := []
		for i in count:
			var n := normals[i]
			var inner := pts[i] - n * BANK_WIDTH * 0.5
			var g := ground_height(inner.x, inner.y) + lift[i] * BANK_BRIDGE
			var rise := BANK_RISE * smoothstep(0.0, BANK_EASE, to_end[i])
			var row := []
			for j in 7: # across the slab: height follows a curve that steepens towards the top
				var u := float(j) / 6.0
				var p := inner + n * BANK_WIDTH * u
				row.append(Vector3(p.x - c.x, g + rise * pow(u, 1.5), p.y - c.y))
			var top: Vector3 = row[6]
			var foot := Vector2(top.x + c.x, top.z + c.y) + n * 9.0
			var grounded := false
			for back in [9.0, 6.0, 4.0, 2.0]: # the earth bank stops short of the circuit's run-off
				foot = Vector2(top.x + c.x, top.z + c.y) + n * back
				if track_distance(foot.x, foot.y).y > clear:
					grounded = true
					break
			var gf := minf(ground_height(foot.x, foot.y), g) - 0.3
			row.append(Vector3(foot.x - c.x, maxf(gf, g - rise * 1.1), foot.y - c.y)) # [7] foot of the earth bank
			# none over the road: a bridge is open underneath
			row.append(grounded and not near[i]) # [8] whether the earth bank stands here
			rows.append(row)
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					_bank_cells[Vector2i(floori(pts[i].x / 16.0) + dx, floori(pts[i].y / 16.0) + dz)] = true
		for i in rows.size() - 1:
			if not keep[i] or not keep[i + 1]:
				continue
			# slabs every 10 m, each a little different, mossy and stained towards the inner edge where water runs
			var slab_tint := 0.9 + 0.12 * _rand(float(i / 2), float(chain.size()), 5.0)
			for j in 6:
				var moss := clampf(1.0 - float(j) / 4.0, 0.0, 1.0) * (0.35 + 0.5 * _rand(float(i), float(j), 9.0))
				var col := Color(0.62, 0.61, 0.57).lerp(Color(0.42, 0.5, 0.3), moss) * slab_tint
				_bank_quad(slab, rows[i][j], rows[i][j + 1], rows[i + 1][j + 1], rows[i + 1][j], col)
			if rows[i][8] and rows[i + 1][8]:
				_bank_quad(earth, rows[i][6], rows[i][7], rows[i + 1][7], rows[i + 1][6], Color(0.42, 0.5, 0.28))
			any = true
	if not any:
		return
	slab.generate_normals()
	earth.generate_normals()
	for part in [["BankingSlab", slab, Color("#9a9890"), 0.95], ["BankingEarth", earth, Color("#6a7a46"), 1.0]]:
		var m := StandardMaterial3D.new()
		m.albedo_color = part[2]
		m.vertex_color_use_as_albedo = true
		m.roughness = part[3]
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		var mi := MeshInstance3D.new()
		mi.name = part[0]
		mi.mesh = (part[1] as SurfaceTool).commit()
		mi.material_override = m
		root.add_child(mi)

## Per point of a line, the distance along it to the nearest point flagged 1 in `to` (INF if none); with `ends`,
## the line's two ends count as flagged.
static func _distance_along(pts: Array[Vector2], to: PackedByteArray, ends: bool) -> PackedFloat32Array:
	var n := pts.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var run := 0.0 if ends else INF
	for i in n:
		if i > 0:
			run += pts[i].distance_to(pts[i - 1])
		if to[i] == 1:
			run = 0.0
		out[i] = run
	run = 0.0 if ends else INF
	for i in range(n - 1, -1, -1):
		if i < n - 1:
			run += pts[i].distance_to(pts[i + 1])
		if to[i] == 1:
			run = 0.0
		out[i] = minf(out[i], run)
	return out

func _bank_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	for v in [a, b, c, a, c, d]:
		st.set_color(col)
		st.add_vertex(v)

## A polyline smoothed (Chaikin) and resampled every `step` metres, with a 0-1 lift where the mapped bridge flags
## are, eased over 25 m either side.
func _smooth_line(raw: Array[Vector2], flags: Array[float], step: float) -> Dictionary:
	var pts: Array[Vector2] = raw.duplicate()
	var fl: Array[float] = flags.duplicate()
	for _it in 3:
		var np: Array[Vector2] = [pts[0]]
		var nf: Array[float] = [fl[0]]
		for i in pts.size() - 1:
			np.append(pts[i].lerp(pts[i + 1], 0.25))
			np.append(pts[i].lerp(pts[i + 1], 0.75))
			nf.append(fl[i])
			nf.append(fl[i + 1])
		np.append(pts[pts.size() - 1])
		nf.append(fl[fl.size() - 1])
		pts = np
		fl = nf
	var out_pts: Array[Vector2] = []
	var out_fl: Array[float] = []
	var carry := 0.0
	out_pts.append(pts[0])
	out_fl.append(fl[0])
	for i in pts.size() - 1:
		var seg := pts[i].distance_to(pts[i + 1])
		var pos := step - carry
		while pos <= seg:
			out_pts.append(pts[i].lerp(pts[i + 1], pos / seg))
			out_fl.append(maxf(fl[i], fl[i + 1]))
			pos += step
		carry = seg - (pos - step)
	var lift: Array[float] = []
	var reach := int(25.0 / step)
	for i in out_fl.size():
		var best := 0.0
		for q in range(-reach, reach + 1):
			var k := i + q
			if k >= 0 and k < out_fl.size() and out_fl[k] > 0.0:
				best = maxf(best, smoothstep(0.0, 1.0, 1.0 - absf(q) / float(reach + 1) * 0.9))
		lift.append(best)
	return {"pts": out_pts, "lift": lift}


# --------------------------------------------------------------------------------------------- road blockages

static var _hazard_stripe_texture: Texture2D = null
static var _no_entry_texture: Texture2D = null

static func _get_hazard_stripe_texture() -> Texture2D:
	if _hazard_stripe_texture != null:
		return _hazard_stripe_texture
	var w := 128
	var h := 32
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var red := Color("#d62020")
	var white := Color("#f8f8f8")
	var border := Color("#1a1a1a")
	for x in w:
		for y in h:
			if y == 0 or y == h - 1:
				img.set_pixel(x, y, border)
			else:
				# 45-degree diagonal chevron hazard stripes
				var stripe := ((x + y * 2) % 32) < 16
				img.set_pixel(x, y, red if stripe else white)
	img.generate_mipmaps()
	_hazard_stripe_texture = ImageTexture.create_from_image(img)
	return _hazard_stripe_texture

static func _get_no_entry_texture() -> Texture2D:
	if _no_entry_texture != null:
		return _no_entry_texture
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var red := Color("#d62020")
	var white := Color("#ffffff")
	var dark := Color("#1a1a1a")
	var r_outer := s * 0.48
	var r_inner := s * 0.45
	var center := Vector2(s * 0.5, s * 0.5)
	for x in s:
		for y in s:
			var d := center.distance_to(Vector2(x + 0.5, y + 0.5))
			if d > r_outer:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
			elif d > r_inner:
				img.set_pixel(x, y, dark)
			else:
				if absf(y + 0.5 - center.y) < s * 0.11 and absf(x + 0.5 - center.x) < s * 0.36:
					img.set_pixel(x, y, white)
				else:
					img.set_pixel(x, y, red)
	img.generate_mipmaps()
	_no_entry_texture = ImageTexture.create_from_image(img)
	return _no_entry_texture

func _build_road_blockages(root: Node3D) -> void:
	var blockages: Array = env.get("road_blockages", [])
	if blockages.is_empty():
		return

	var blockages_root := Node3D.new()
	blockages_root.name = "RoadBlockages"
	root.add_child(blockages_root)

	var c: Vector2 = world.world_center
	var stripe_tex := _get_hazard_stripe_texture()
	var no_entry_tex := _get_no_entry_texture()

	var foot_mat := StandardMaterial3D.new()
	foot_mat.albedo_color = Color("#757572")
	foot_mat.roughness = 0.95

	var steel_mat := StandardMaterial3D.new()
	steel_mat.albedo_color = Color("#c0c5ca")
	steel_mat.metallic = 0.7
	steel_mat.roughness = 0.3

	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color("#ff6200")
	post_mat.roughness = 0.3

	var reflector_mat := StandardMaterial3D.new()
	reflector_mat.albedo_color = Color("#f0f4f8")
	reflector_mat.metallic = 0.3
	reflector_mat.roughness = 0.15

	var sign_mat := StandardMaterial3D.new()
	sign_mat.albedo_texture = no_entry_tex
	sign_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sign_mat.roughness = 0.4

	var foot_mesh := BoxMesh.new()
	foot_mesh.size = Vector3(0.45, 0.22, 0.65)
	foot_mesh.material = foot_mat

	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.035
	post_mesh.bottom_radius = 0.035
	post_mesh.height = 1.05
	post_mesh.material = steel_mat

	var marker_mesh := CylinderMesh.new()
	marker_mesh.top_radius = 0.065
	marker_mesh.bottom_radius = 0.075
	marker_mesh.height = 0.95
	marker_mesh.material = post_mat

	var ring_mesh := CylinderMesh.new()
	ring_mesh.top_radius = 0.076
	ring_mesh.bottom_radius = 0.076
	ring_mesh.height = 0.09
	ring_mesh.material = reflector_mat

	var sign_mesh := QuadMesh.new()
	sign_mesh.size = Vector2(0.48, 0.48)
	sign_mesh.material = sign_mat

	for i in blockages.size():
		var entry: Array = blockages[i]
		if entry.size() < 4:
			continue
		var x: float = float(entry[0])
		var y: float = float(entry[1])
		var angle: float = float(entry[2])
		var width: float = float(entry[3])

		var pos_y := ground_height(x, y)
		var b_node := Node3D.new()
		b_node.name = "Blockage_%d" % i
		b_node.position = Vector3(x - c.x, pos_y, y - c.y)
		b_node.rotation.y = -angle
		blockages_root.add_child(b_node)

		var b_mat := StandardMaterial3D.new()
		b_mat.albedo_texture = stripe_tex
		b_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		b_mat.uv1_scale = Vector3(maxf(1.0, width / 1.0), 1.0, 1.0)
		b_mat.roughness = 0.35

		var upper_board := MeshInstance3D.new()
		var upper_mesh := BoxMesh.new()
		upper_mesh.size = Vector3(width, 0.32, 0.05)
		upper_mesh.material = b_mat
		upper_board.mesh = upper_mesh
		upper_board.position = Vector3(0.0, 0.72, 0.0)
		b_node.add_child(upper_board)

		var lower_board := MeshInstance3D.new()
		var lower_mesh := BoxMesh.new()
		lower_mesh.size = Vector3(width, 0.22, 0.05)
		lower_mesh.material = b_mat
		lower_board.mesh = lower_mesh
		lower_board.position = Vector3(0.0, 0.32, 0.0)
		b_node.add_child(lower_board)

		var span_half := width * 0.42
		for sgn: float in [-1.0, 1.0]:
			var foot := MeshInstance3D.new()
			foot.mesh = foot_mesh
			foot.position = Vector3(span_half * sgn, 0.11, 0.0)
			b_node.add_child(foot)

			var post := MeshInstance3D.new()
			post.mesh = post_mesh
			post.position = Vector3(span_half * sgn, 0.525, 0.0)
			b_node.add_child(post)

		if width > 5.2:
			var mid_foot := MeshInstance3D.new()
			mid_foot.mesh = foot_mesh
			mid_foot.position = Vector3(0.0, 0.11, 0.0)
			b_node.add_child(mid_foot)

			var mid_post := MeshInstance3D.new()
			mid_post.mesh = post_mesh
			mid_post.position = Vector3(0.0, 0.525, 0.0)
			b_node.add_child(mid_post)

		for sgn: float in [-1.0, 1.0]:
			var marker_x: float = (width * 0.5 + 0.36) * sgn
			var marker := MeshInstance3D.new()
			marker.mesh = marker_mesh
			marker.position = Vector3(marker_x, 0.475, 0.0)
			b_node.add_child(marker)

			for ry: float in [0.55, 0.75]:
				var ring := MeshInstance3D.new()
				ring.mesh = ring_mesh
				ring.position = Vector3(marker_x, ry, 0.0)
				b_node.add_child(ring)

		var sign_inst := MeshInstance3D.new()
		sign_inst.mesh = sign_mesh
		sign_inst.position = Vector3(0.0, 0.72, 0.035)
		b_node.add_child(sign_inst)
