## Low-poly ground cover for the open world, planted around the camera as it moves: wheat and maize in the fields,
## a carpet of swaying grass on the meadows and verges (mown short on lawns and in parks, none on the pitches), flowers,
## bushes on the scrub and here and there elsewhere.
##
## Where things grow is read from the same land map the ground shader paints (data/world/<key>_land.png: R paved or
## yard, G field with the crop in its value, B bare earth, A forest floor), so a plant stands exactly where the ground
## looks like its field, and never on a road. The meshes are GrassPatch, WheatPatch (each with a ...Low version for
## the outer ring), Corn, Flower and BushCluster in models/roadside.glb (tools/blender/build_roadside.py); grass and
## wheat are drawn by shaders/grass.gdshader.
##
## The map has ~60 km2 of it, so nothing is baked: the world is cut into CELL squares, the ones within radius() of the
## camera get one MultiMesh per plant kind (built nearest first, within BUDGET_USEC a frame), and the cells left behind
## are freed. A coarser ring of FAR_CELL squares out to far_radius() carries the far layer: sparse GrassTuft clumps
## that keep a meadow reading as grass a couple of hundred metres off (the near patches thin out and sink long before
## that, into tufts that are already there), and the bushes. Every cell is planted LEAD metres before anything in it can
## show, and everything in it comes in plant by plant (grass.gdshader sinks blades by their own distance, shrub.gdshader
## dithers bushes in), so no cell appears all at once.
extends Node3D

const ROADSIDE := "res://models/roadside.glb"
const WORLD_ASSETS := preload("res://scripts/ui/world_assets.gd")
const LAND_RES := 2.5 ## metres per land map texel, as TownBuilder.LAND_RES
const CELL := 32.0 ## m: the near cells (wheat, maize, grass patches, flowers)
const FAR_CELL := 64.0 ## m: the far cells (grass tufts, bushes)
const FAR_KEY := 1 << 30 ## added to a far cell's key in `cells`
const HALF_DIAG := 0.71 ## a square's half diagonal over its side: a cell's nearest plant is this many sides nearer than its centre
## m: a cell is planted this much before its nearest plant can show. The planting runs a few frames behind the camera
## (BUDGET_USEC a frame, nearest first), which at 140 km/h is 15-25 m: planted later, the far chase camera saw a cell's
## grass come up all at once.
const LEAD := 26.0
const LAYERS := 4 ## near: wheat, maize, grass, flowers
const FAR_LAYERS := 2 ## far: grass tufts, bushes
const CORN_STEP := 2.3 ## m between clumps
const FLOWER_STEP := 1.6
const TUFT_STEP := 3.0 ## m between far-layer grass tufts (before thinning)
const BUSH_STEP := 4.0
const GRASS_REACH := 1.0 ## m: a grass patch's blades spread this far from its middle (0.8 m, widened up to 1.25x)
const BUDGET_USEC := 2500 ## planting time per frame
const HANDOVER := 14.0 ## m over which the dense patches give way to the sparse ones (grass.gdshader lod_out/lod_in)
const FAR_FADE := 50.0 ## m over which the blades sink at the far edge (at most half the reach)
const TUFT_FADE := 60.0 ## m over which the tufts sink at the far ring's edge
const TONE_NEAR := 30.0 ## m from which every grass blade starts to take the far colour (to the tufts' edge)
const BUSH_FADE := 35.0 ## m over which a bush dithers in at the far ring's edge
const FIELD_MIN := 100 ## land map G (0-255) from which a pixel is a field
const EDGE_RES := 5.0 ## m per cell of the edge mask (fences, hedges, garden trees, streams: tall grass grows along them)
const GRASS_SHADER := preload("res://shaders/grass.gdshader")
const SHRUB_SHADER := preload("res://shaders/shrub.gdshader")
const RACE_WORLD := preload("res://scripts/ui/race_world.gd")
## The meadow's colour seen from afar: the grass fades to it towards the edge of the planted ring, and the ground shader
## paints the bare meadows beyond with it (TownBuilder.build_terrain), so the ring has no edge of colour
const MEADOW_FAR := Color(0.46, 0.52, 0.22)
const MEADOW_FAR_DRY := Color(0.56, 0.54, 0.25)
const FLOWER_RANGE := 50.0 ## m: a flower cell's centre shows within this, fading out over the next FLOWER_MARGIN
const FLOWER_MARGIN := 18.0
const CORN_MARGIN := 20.0 ## m: a maize cell dithers out over this beyond its range
## per graphics preset (0 Low .. 3 Ultra): m between grass patches (before _block thins them) and wheat patches, how near a cell's centre must be for the
## dense patches (0: never), where the patches have sunk away, where the far layer's tufts have, and where the bushes
## have faded out
const GRASS_QUALITY := [{"step": 2.0, "wheat": 1.6, "near": 0.0, "far": 50.0, "tuft": 150.0, "bush": 130.0},
	{"step": 1.7, "wheat": 1.35, "near": 22.0, "far": 58.0, "tuft": 180.0, "bush": 160.0},
	{"step": 1.45, "wheat": 1.15, "near": 28.0, "far": 66.0, "tuft": 210.0, "bush": 190.0},
	{"step": 1.25, "wheat": 1.0, "near": 34.0, "far": 76.0, "tuft": 240.0, "bush": 220.0}]
const FLOWER_COLOURS := [Color(1.0, 1.0, 0.95), Color(1.0, 0.85, 0.15), Color(0.95, 0.2, 0.18), Color(0.62, 0.38, 0.95),
	Color(1.0, 0.55, 0.12), Color(1.0, 0.62, 0.78)]

var map: TownMap
var land := PackedByteArray() ## RGBA8 of the land map
var land_w := 0
var land_h := 0
var meshes := {} ## kind -> prepared Mesh
var cells := {} ## cell key (+ FAR_KEY for a far cell) -> Node3D
var queue: Array = [] ## [key, cx, cy, layer, cell size], nearest first
var queued := {} ## cell key -> true while it has tasks waiting
var _last_cell := Vector2i(1 << 30, 1 << 30)
var counts := {} ## kind -> instances alive, for the probes
var quality := 2
var grass_mat: ShaderMaterial
var wheat_mat: ShaderMaterial
var grass_near_mat: ShaderMaterial ## the dense patches' copies: their blades leave across the hand-over band
var wheat_near_mat: ShaderMaterial
var bush_mat: ShaderMaterial
var tuft_mat: ShaderMaterial ## the far layer's grass
## Where tall grass grows whatever the meadow around does: one byte per EDGE_RES square over the land map, 1 along a
## fence or hedge, round a garden or field tree, by a stream or ditch (built in setup from the map)
var edge_mask := PackedByteArray()
var edge_w := 0
var edge_h := 0
var _areas := {} ## cell key -> [[kind, ring, rect], ...] of the pitches and parks over that cell
## Tests: when set, every committed plant's position by kind (headless reads MultiMesh transforms back as identity)
var recorded: Dictionary = {}
var record := false

static func hash2(x: float, y: float, salt: float) -> float:
	var v := sin(x * 12.9898 + y * 78.233 + salt * 37.719) * 43758.5453
	return v - floor(v)

## Smooth value noise in 0..1 with features of about `scale` metres.
static func vnoise(x: float, y: float, scale: float, salt: float) -> float:
	var fx := x / scale
	var fy := y / scale
	var ix := floorf(fx)
	var iy := floorf(fy)
	var tx := fx - ix
	var ty := fy - iy
	tx = tx * tx * (3.0 - 2.0 * tx)
	ty = ty * ty * (3.0 - 2.0 * ty)
	var a := hash2(ix, iy, salt)
	var b := hash2(ix + 1.0, iy, salt)
	var c := hash2(ix, iy + 1.0, salt)
	var d := hash2(ix + 1.0, iy + 1.0, salt)
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)

func setup(m: TownMap) -> bool:
	map = m
	_load_land()
	_load_meshes()
	_index_areas()
	grass_mat = ShaderMaterial.new()
	grass_mat.shader = GRASS_SHADER
	wheat_mat = ShaderMaterial.new()
	wheat_mat.shader = GRASS_SHADER
	wheat_mat.set_shader_parameter("root_color", Color(0.3, 0.3, 0.12))
	wheat_mat.set_shader_parameter("mid_color", Color(0.66, 0.6, 0.28))
	wheat_mat.set_shader_parameter("tip_color", Color(0.86, 0.76, 0.42))
	wheat_mat.set_shader_parameter("dry_color", Color(0.82, 0.68, 0.34))
	wheat_mat.set_shader_parameter("far_color", Color(0.78, 0.66, 0.3)) # the ground shader's ripe field (farm_color_a)
	wheat_mat.set_shader_parameter("wind_strength", 0.1)
	grass_mat.set_shader_parameter("far_color", MEADOW_FAR)
	grass_near_mat = grass_mat.duplicate() as ShaderMaterial
	tuft_mat = grass_mat.duplicate() as ShaderMaterial
	bush_mat = ShaderMaterial.new()
	bush_mat.shader = SHRUB_SHADER
	bush_mat.set_shader_parameter("grain", RACE_WORLD.noise_texture("grain"))
	wheat_near_mat = wheat_mat.duplicate() as ShaderMaterial
	_build_edges()
	set_quality(quality)
	return land_w > 0 and not meshes.is_empty()

func _load_land() -> void:
	var tex := load("res://data/world/%s_land.png" % map.key) as Texture2D
	if tex == null:
		return
	var img := tex.get_image()
	if img == null:
		return
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	land = img.get_data()
	land_w = img.get_width()
	land_h = img.get_height()

func _load_meshes() -> void:
	var scene: Node = WORLD_ASSETS._load_model(ROADSIDE)
	if scene == null:
		return
	# the materials the instance colour tints (the others keep their own colours)
	var tinted := {"Corn": [], "BushCluster": [], "Flower": ["Petal"]}
	for kind in ["GrassPatch", "GrassPatchLow", "GrassTuft", "WheatPatch", "WheatPatchLow"]:
		for mi in scene.find_children(kind, "MeshInstance3D", true, false):
			meshes[kind] = (mi as MeshInstance3D).mesh
			break
	for kind in tinted:
		for mi in scene.find_children(kind, "MeshInstance3D", true, false):
			meshes[kind] = _prepare((mi as MeshInstance3D).mesh, tinted[kind])
			break
	scene.free()

## The pitches and parks, by the cells they cover: no grass on a pitch, a mown lawn in a park.
func _index_areas() -> void:
	for a in map.areas:
		var kind := String(a[0])
		if kind != "pitch" and kind != "park":
			continue
		var flat: Array = a[1]
		var ring := PackedVector2Array()
		for k in range(0, flat.size() - 1, 2):
			ring.append(Vector2(float(flat[k]), float(flat[k + 1])))
		if ring.size() < 3:
			continue
		var r := Rect2(ring[0], Vector2.ZERO)
		for q in ring:
			r = r.expand(q)
		for cx in range(floori(r.position.x / CELL), floori(r.end.x / CELL) + 1):
			for cy in range(floori(r.position.y / CELL), floori(r.end.y / CELL) + 1):
				var key := cell_key(cx, cy)
				if not _areas.has(key):
					_areas[key] = []
				_areas[key].append([kind, ring, r])

## The edge mask: the fences and hedges (not the style-4 road-end barriers), the trees that stand alone or in rows,
## gardens, parks and scrub (the woods' edge comes from the land map itself), the generated trees TownBuilder plants
## (map meta "extra_trees") and the streams and ditches.
func _build_edges() -> void:
	edge_w = ceili(land_w * LAND_RES / EDGE_RES)
	edge_h = ceili(land_h * LAND_RES / EDGE_RES)
	edge_mask = PackedByteArray()
	edge_mask.resize(edge_w * edge_h)
	if edge_w == 0:
		return
	var mark := func(x: float, y: float) -> void:
		var u := int(floorf((x - map.tx0) / EDGE_RES))
		var v := int(floorf((y - map.ty0) / EDGE_RES))
		if u >= 0 and v >= 0 and u < edge_w and v < edge_h:
			edge_mask[v * edge_w + u] = 1
	for w in map.raw.get("fences", []):
		if w.size() > 4 and int(w[4]) == 4:
			continue
		var a := Vector2(float(w[0]), float(w[1]))
		var b := Vector2(float(w[2]), float(w[3]))
		var n := maxi(1, ceili(a.distance_to(b) / 2.5))
		for k in n + 1:
			var q := a.lerp(b, float(k) / n)
			mark.call(q.x, q.y)
	var trees: Array = map.raw.get("trees", [])
	for k in range(0, trees.size(), 3):
		var kind := int(trees[k + 2])
		if kind < 2 or kind > 4: # not in a wood
			mark.call(float(trees[k]), float(trees[k + 1]))
	var extra: PackedFloat32Array = map.get_meta("extra_trees", PackedFloat32Array())
	for k in range(0, extra.size(), 3):
		mark.call(extra[k], extra[k + 1])
	for ww in map.raw.get("waterways", []):
		var flat: Array = ww[1]
		var reach := float(ww[0]) * 0.5 + 2.0 # the banks
		for k in range(0, flat.size() - 3, 2):
			var a := Vector2(float(flat[k]), float(flat[k + 1]))
			var b := Vector2(float(flat[k + 2]), float(flat[k + 3]))
			var d := b - a
			var nrm := Vector2(-d.y, d.x).normalized() * reach
			var n := maxi(1, ceili(d.length() / 2.5))
			for j in n + 1:
				var q := a.lerp(b, float(j) / n)
				mark.call(q.x + nrm.x, q.y + nrm.y)
				mark.call(q.x - nrm.x, q.y - nrm.y)

## 0..1: how much p is the kind of place tall grass grows in a mown or grazed landscape: along a fence, hedge or
## stream, round a lone tree (the edge mask), on the rim of a field or a wood, by a pond. `i` is p's land map pixel.
func _edge_at(i: int, x: float, y: float) -> float:
	var u := int(floorf((x - map.tx0) / EDGE_RES))
	var v := int(floorf((y - map.ty0) / EDGE_RES))
	if u >= 0 and v >= 0 and u < edge_w and v < edge_h and edge_mask[v * edge_w + u] != 0:
		return 1.0
	var best := 0.0
	for o in [-8, 8, -land_w * 8, land_w * 8]: # 5 m off: a field, a wood or water next to this grass
		var j: int = i + o
		if j < 0 or j + 3 >= land.size():
			continue
		if land[j + 1] >= FIELD_MIN or land[j + 3] >= 120:
			return 1.0
		if land[j + 3] >= 50 and land[j + 2] >= 60: # water (A 90 and B 120 in the bake)
			return 1.0
		if land[j + 1] >= 40 or land[j + 3] >= 60:
			best = 0.6 # allotments, scrub, the blurred rim of a field
	return best

const BLOCK := 4.0 ## m: _block()'s squares

## How much meadow grass grows round (x, y) and how tall it stands, for the BLOCK square there (the slow noises, the
## edge and the road verge vary over metres, and working them out per patch was most of a cell's planting time):
## [share of the patch grid kept, height scale, the same two on a lawn, dryness, 1 if clear of roads, 1 if clear of
## buildings]. The tall clumps stand along field and
## wood edges, fences, hedges and streams and round the trees; the open meadow is thinner and shin to knee high, lusher
## and taller in broad drifts; lawns, parks, gardens and the verges by the roads are mown short and sparse. Cached in
## `cache` for one cell's planting (_block_cache(): the cell's blocks and one more all round).
func _block(cache: Array, x: float, y: float) -> PackedFloat32Array:
	var bx := floori(x / BLOCK)
	var by := floori(y / BLOCK)
	var n: int = cache[0]
	var slot := 3 + clampi(by - int(cache[2]), 0, n - 1) * n + clampi(bx - int(cache[1]), 0, n - 1)
	var v = cache[slot]
	if v != null:
		return v
	var cx := (bx + 0.5) * BLOCK
	var cy := (by + 0.5) * BLOCK
	var i := _px(cx, cy)
	var edge := _edge_at(i, cx, cy) if i >= 0 else 0.0
	var lush := vnoise(cx, cy, 40.0, 11.0)
	var drift := vnoise(cx, cy, 18.0, 7.0)
	var dens := 0.4 + 0.5 * smoothstep(0.3, 0.75, drift)
	var tall := 0.3 + 0.3 * lush + 0.1 * hash2(cx, cy, 12.0) # of blades up to 1 m: ankle to knee high
	var verge := _near_road(i) if i >= 0 else 0.0
	if verge > 0.0: # by a road: mown shorter and thinner towards the edge
		dens = lerpf(dens, 0.32, verge)
		tall = lerpf(tall, 0.2, verge)
	if edge > 0.0:
		dens = lerpf(dens, 1.0, edge)
		tall = lerpf(tall, 0.68 + 0.24 * lush, edge)
	# a lawn: a taller fringe left along a garden fence or round a tree
	# and whether the whole square is clear of roads, pavements and buildings, so its patches skip those checks
	# (TownMap hashes each road segment into the cells within its half width plus DRIVE_REACH, which covers the
	# pavements and GRASS_REACH: a square over cells holding no segment is clear of them all)
	var half := BLOCK * 0.5 + 0.05
	var clear := 1.0
	for gx in range(floori((cx - half) / TownMap.CELL), floori((cx + half) / TownMap.CELL) + 1):
		for gy in range(floori((cy - half) / TownMap.CELL), floori((cy + half) / TownMap.CELL) + 1):
			if map._seg_cells.has(map._cell_key(gx, gy)):
				clear = 0.0
	var open := 1.0 if map.buildings_near(Vector2(cx, cy), half + 0.1).is_empty() else 0.0
	var b := PackedFloat32Array([dens, tall, lerpf(0.22, 0.75, edge), lerpf(0.12, 0.5, edge) + 0.06 * lush, vnoise(cx, cy, 70.0, 31.0),
		clear, open])
	cache[slot] = b
	return b

## An empty _block() cache for the cell (`size` m) at x0, y0: [blocks across, first block x, first block y, slots...].
static func _block_cache(x0: float, y0: float, size: float) -> Array:
	var n := int(size / BLOCK) + 3
	var c := [n, floori(x0 / BLOCK) - 1, floori(y0 / BLOCK) - 1]
	c.resize(3 + n * n)
	return c

## [share kept, height scale] of grass at land pixel i: _block()'s, or right at a road's edge sparse stubble.
func _grass_at(i: int, x: float, y: float, mown: bool, blk: PackedFloat32Array) -> Vector2:
	if maxi(land[i], land[i + 2]) >= 40:
		return Vector2(0.3, 0.12 + 0.08 * hash2(x, y, 16.0))
	return Vector2(blk[2], blk[3]) if mown else Vector2(blk[0], blk[1])

## "pitch", "park" or "" at p, from the areas over cell `key`.
func _area_at(key: int, p: Vector2) -> String:
	for e in _areas.get(key, []):
		if (e[2] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, e[1]):
			return e[0]
	return ""

## m from the camera within which a near cell's centre is planted: its nearest blades LEAD m beyond where they have
## sunk away.
func radius() -> float:
	return float(GRASS_QUALITY[quality].far) + CELL * HALF_DIAG + LEAD

## The same for the far cells (tufts and bushes).
func far_radius() -> float:
	var q: Dictionary = GRASS_QUALITY[quality]
	return maxf(float(q.tuft), float(q.bush)) + FAR_CELL * HALF_DIAG + LEAD

## Sets the graphics preset (0 Low .. 3 Ultra) and replants: how dense and how far the grass grows.
func set_quality(level: int) -> void:
	quality = clampi(level, 0, GRASS_QUALITY.size() - 1)
	var q: Dictionary = GRASS_QUALITY[quality]
	var band := Vector2(maxf(0.0, float(q.near) - HANDOVER), float(q.near)) if float(q.near) > 0.0 else Vector2.ZERO
	for mat in [grass_mat, wheat_mat, grass_near_mat, wheat_near_mat, tuft_mat]:
		if mat:
			mat.set_shader_parameter("fade_start", float(q.far) - minf(FAR_FADE, float(q.far) * 0.5))
			mat.set_shader_parameter("fade_end", float(q.far))
			# one tone by distance for every grass blade, near patch or far tuft, so the layers never differ in colour
			# (wheat has no far layer: it takes the field's colour as it sinks)
			var grass: bool = mat == grass_mat or mat == grass_near_mat or mat == tuft_mat
			mat.set_shader_parameter("tone_range", Vector2(TONE_NEAR, float(q.tuft)) if grass else Vector2.ZERO)
	if tuft_mat:
		tuft_mat.set_shader_parameter("fade_start", float(q.tuft) - TUFT_FADE)
		tuft_mat.set_shader_parameter("fade_end", float(q.tuft))
	if bush_mat:
		bush_mat.set_shader_parameter("fade_near", float(q.bush) - BUSH_FADE)
		bush_mat.set_shader_parameter("fade_far", float(q.bush))
	for mat in [grass_mat, wheat_mat]:
		if mat:
			mat.set_shader_parameter("lod_in", band)
	for mat in [grass_near_mat, wheat_near_mat]:
		if mat:
			mat.set_shader_parameter("lod_out", band)
	for k in cells.keys():
		_free_cell(k)
	queue.clear()
	queued.clear()
	_last_cell = Vector2i(1 << 30, 1 << 30)

## A copy of mesh whose materials take the instance colour: all of them, or those named in `only`.
func _prepare(mesh: Mesh, only: Array) -> Mesh:
	var out := mesh.duplicate() as Mesh
	for s in out.get_surface_count():
		var mat := out.surface_get_material(s) as BaseMaterial3D
		if mat == null:
			continue
		mat = mat.duplicate() as BaseMaterial3D
		mat.vertex_color_use_as_albedo = only.is_empty() or only.has(mat.resource_name)
		out.surface_set_material(s, mat)
	return out

## Land map pixel byte offset (R) of a world point, or -1 outside the map.
func _px(x: float, y: float) -> int:
	var u := int(floorf((x - map.tx0) / LAND_RES))
	var v := int(floorf((y - map.ty0) / LAND_RES))
	if u < 0 or v < 0 or u >= land_w or v >= land_h:
		return -1
	return (v * land_w + u) * 4

static func cell_key(cx: int, cy: int) -> int:
	return (cx + 4096) * 8192 + (cy + 4096)

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		update_around(Vector2(cam.global_position.x, cam.global_position.z))
	run_budget(BUDGET_USEC)

## Builds queued layers until `usec` have passed (at least one).
func run_budget(usec: int) -> void:
	var t0 := Time.get_ticks_usec()
	while not queue.is_empty():
		run_queue(1)
		if Time.get_ticks_usec() - t0 >= usec:
			return

## Plants the cells around p and frees the far ones; the work is queued, see run_queue().
func update_around(p: Vector2) -> void:
	var here := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
	if here == _last_cell:
		return
	_last_cell = here
	var near_r := radius()
	var far_r := far_radius()
	var near_keep := near_r + CELL * 1.5
	var far_keep := far_r + FAR_CELL * 1.5
	for k in cells.keys():
		var c: Node3D = cells[k]
		if c.has_meta("centre") and (c.get_meta("centre") as Vector2).distance_to(p) > (far_keep if k >= FAR_KEY else near_keep):
			_free_cell(k)
	var want := []
	for grid in [[CELL, near_r, 0, LAYERS], [FAR_CELL, far_r, FAR_KEY, FAR_LAYERS]]:
		var size: float = grid[0]
		var reach: float = grid[1]
		var c0 := Vector2i(floori(p.x / size), floori(p.y / size))
		var r := int(ceil(reach / size)) + 1
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var cx := c0.x + dx
				var cy := c0.y + dy
				var d := Vector2((cx + 0.5) * size, (cy + 0.5) * size).distance_to(p)
				var key := cell_key(cx, cy) + int(grid[2])
				if d <= reach and not cells.has(key) and not queued.has(key):
					want.append([d, key, cx, cy, size, int(grid[3])])
	var keep := []
	for t in queue: # drop queued cells that fell out of range, keep the rest
		var size: float = t[4]
		var centre := Vector2((int(t[1]) + 0.5) * size, (int(t[2]) + 0.5) * size)
		if centre.distance_to(p) <= (far_keep if int(t[0]) >= FAR_KEY else near_keep):
			keep.append(t)
		else:
			queued.erase(int(t[0]))
	queue = keep
	for w in want:
		queued[w[1]] = true
		for layer in int(w[5]):
			queue.append([w[1], w[2], w[3], layer, w[4]])
	# nearest cells first, wherever the camera has got to (a far cell by its nearest corner: its tufts and bushes
	# show from much further than a near cell's grass)
	var dist := func(t: Array) -> float:
		var size: float = t[4]
		var d := Vector2((int(t[1]) + 0.5) * size, (int(t[2]) + 0.5) * size).distance_to(p)
		if int(t[0]) >= FAR_KEY:
			d = maxf(0.0, d - (far_r - near_r))
		return d + float(t[3]) * 0.01
	queue.sort_custom(func(a, b): return dist.call(a) < dist.call(b))

func _free_cell(key: int) -> void:
	var c: Node3D = cells[key]
	for kind in c.get_meta("counts", {}):
		counts[kind] = int(counts.get(kind, 0)) - int(c.get_meta("counts")[kind])
	cells.erase(key)
	c.queue_free()

## Builds the next `n` queued layers.
func run_queue(n: int) -> void:
	for _i in n:
		if queue.is_empty():
			return
		var t: Array = queue.pop_front()
		var key := int(t[0])
		var cx := int(t[1])
		var cy := int(t[2])
		var layer := int(t[3])
		var size: float = t[4]
		var far := key >= FAR_KEY
		if not cells.has(key):
			var node := Node3D.new()
			node.name = ("Far %d %d" if far else "Cell %d %d") % [cx, cy]
			node.set_meta("centre", Vector2((cx + 0.5) * size, (cy + 0.5) * size))
			node.set_meta("counts", {})
			add_child(node)
			cells[key] = node
		var cell: Node3D = cells[key]
		_plant(cell, cx, cy, layer, far)
		if layer == (FAR_LAYERS if far else LAYERS) - 1:
			queued.erase(key)

## Calls run_queue until the queue is empty (the probes and the first frame).
func plant_all() -> void:
	while not queue.is_empty():
		run_queue(64)

func _plant(cell: Node3D, cx: int, cy: int, layer: int, far := false) -> void:
	var size := FAR_CELL if far else CELL
	var x0 := cx * size
	var y0 := cy * size
	if far:
		# a far cell reaches well beyond its centre: plant it if any corner is in play
		var any := false
		for c in [Vector2(x0, y0), Vector2(x0 + size, y0), Vector2(x0, y0 + size), Vector2(x0 + size, y0 + size)]:
			any = any or map.in_play(c)
		if not any:
			return
		match layer:
			0: _plant_tufts(cell, x0, y0)
			1: _plant_bushes(cell, x0, y0)
		return
	if not map.in_play(Vector2(x0 + CELL * 0.5, y0 + CELL * 0.5)):
		return
	match layer:
		0: _plant_wheat(cell, x0, y0)
		1: _plant_corn(cell, x0, y0)
		2: _plant_grass(cell, x0, y0)
		3: _plant_flowers(cell, x0, y0)

## The crop of the field under a pixel: 0 young green (maize), 1 ripe (wheat), 2 ploughed or none.
func _crop_at(i: int) -> int:
	if i < 0:
		return 2
	var g := land[i + 1]
	if g < FIELD_MIN or land[i] > 60 or land[i + 2] > 60 or land[i + 3] > 80:
		return 2
	# the map is blurred, so a field's edge fades through lower values (which read as another crop): take the field's
	# own value from the pixels around, and leave the fading rim bare
	var top := g
	for o in [-4, 4, -land_w * 4, land_w * 4]:
		var j: int = i + o
		if j >= 0 and j < land.size():
			top = maxi(top, land[j + 1])
	if g < top - 24:
		return 2
	var crop := (float(top) / 255.0 - 0.35) / 0.65
	return 0 if crop < 0.45 else (1 if crop < 0.75 else 2)

## True where the ground is plain grass: no yard, field, bare earth or forest floor.
func _is_grass(i: int) -> bool:
	return i >= 0 and land[i] < 40 and land[i + 1] < 40 and land[i + 2] < 40 and land[i + 3] < 30

## 0 away from a road, up to 1 at its edge: how strongly a road's paint (R paved about 150, B a dirt road's earth
## about 200) shows within 5 m.
func _near_road(i: int) -> float:
	var best := 0
	for o in [-8, 8, -land_w * 8, land_w * 8, -4, 4, -land_w * 4, land_w * 4]:
		var j: int = i + o
		if j >= 0 and j < land.size():
			best = maxi(best, maxi(land[j], land[j + 2]))
	return clampf((float(best) - 60.0) / 90.0, 0.0, 1.0)

## False where a plant `r` metres across would reach onto a road at ground level or a pavement. The land map is
## blurred and leaves some tracks unpainted, so it alone let grass patches grow over road edges and dirt tracks.
func _clear_of_road(x: float, y: float, r: float) -> bool:
	var hit := map.road_at(x, y, -INF, r)
	if not hit.is_empty() and float(hit.deck) < 1.0: # a bridge deck high overhead leaves the ground below
		return false
	return map.kerb_at(x, y) <= 0.0

func _place(x: float, y: float, yaw: float, scale: Vector3, lift := 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(scale), Vector3(x, map.ground(x, y) + lift, y))

## One MultiMesh of `kind` in the cell. With a material the colours go to INSTANCE_CUSTOM (grass.gdshader) instead of
## the instance colour; range_begin/range_end are the cell centre's distance from the camera it shows between. `buf`:
## the instance data a _commit of the same plants returned (it is built once and written in one go). Returns it.
func _commit(cell: Node3D, kind: String, xfs: Array, cols: Array, range_end: float, mat: Material = null, range_begin := 0.0,
		buf := PackedFloat32Array()) -> PackedFloat32Array:
	if xfs.is_empty() or not meshes.has(kind):
		return buf
	if record:
		if not recorded.has(kind):
			recorded[kind] = PackedVector3Array()
		for xf in xfs:
			recorded[kind].append((xf as Transform3D).origin)
	if buf.is_empty():
		buf = _instance_buffer(xfs, cols)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = mat == null
	mm.use_custom_data = mat != null
	mm.mesh = meshes[kind]
	mm.instance_count = xfs.size()
	mm.buffer = buf
	var mmi := MultiMeshInstance3D.new()
	mmi.name = kind
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_begin = range_begin
	mmi.visibility_range_end = range_end
	cell.add_child(mmi)
	var c: Dictionary = cell.get_meta("counts")
	c[kind] = int(c.get(kind, 0)) + xfs.size()
	counts[kind] = int(counts.get(kind, 0)) + xfs.size()
	return buf

## A MultiMesh buffer of transforms and one colour (or custom data) each: 12 floats a transform (its 3x4 rows), then
## 4 (as TownBuilder.instance_buffer). One write is much faster than a call per instance.
static func _instance_buffer(xfs: Array, cols: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(xfs.size() * 16)
	var o := 0
	for i in xfs.size():
		var t: Transform3D = xfs[i]
		var c: Color = cols[i]
		out[o] = t.basis.x.x; out[o + 1] = t.basis.y.x; out[o + 2] = t.basis.z.x; out[o + 3] = t.origin.x
		out[o + 4] = t.basis.x.y; out[o + 5] = t.basis.y.y; out[o + 6] = t.basis.z.y; out[o + 7] = t.origin.y
		out[o + 8] = t.basis.x.z; out[o + 9] = t.basis.y.z; out[o + 10] = t.basis.z.z; out[o + 11] = t.origin.z
		out[o + 12] = c.r; out[o + 13] = c.g; out[o + 14] = c.b; out[o + 15] = c.a
		o += 16
	return out

## Grid points of a cell (`size` m square) with the given step and a jitter of up to 0.4 step, as [x, y, hash].
func _grid(x0: float, y0: float, step: float, salt: float, size := CELL) -> Array:
	var out := []
	var n := int(ceil(size / step))
	for gy in n:
		for gx in n:
			var h := hash2(x0 + gx * 0.37, y0 + gy * 0.71, salt)
			var h2 := hash2(y0 + gy * 0.13, x0 + gx * 0.57, salt + 3.0)
			out.append([x0 + (gx + 0.5 + (h - 0.5) * 0.8) * step, y0 + (gy + 0.5 + (h2 - 0.5) * 0.8) * step, h])
	return out

func _plant_wheat(cell: Node3D, x0: float, y0: float) -> void:
	var xfs := []
	var cols := []
	for p in _grid(x0, y0, float(GRASS_QUALITY[quality].wheat), 1.0):
		if _crop_at(_px(p[0], p[1])) != 1:
			continue
		var h: float = p[2]
		xfs.append(_place(p[0], p[1], h * TAU * 7.0, Vector3(1.0, 0.9 + hash2(p[0], p[1], 2.0) * 0.25, 1.0), -0.03))
		var t := 0.9 + hash2(p[0], p[1], 4.0) * 0.2
		cols.append(Color(t, t * (0.97 + 0.05 * h), t * (0.92 + 0.1 * h), 0.2 + 0.3 * vnoise(p[0], p[1], 30.0, 3.0)))
	_commit_patches(cell, "WheatPatch", xfs, cols, wheat_mat)

## A dense near version and a sparse far one of the same patches; Low quality draws only the sparse one.
func _commit_patches(cell: Node3D, kind: String, xfs: Array, cols: Array, mat: Material) -> void:
	var q: Dictionary = GRASS_QUALITY[quality]
	var near := float(q.near)
	var far := float(q.far) + CELL * 0.75 # the cell centre's distance; the shader sinks the blades by their own
	# visibility ranges go by the cell's centre, so both kinds are drawn wherever the cell may reach into the
	# hand-over band; the shader hands each blade over at its own distance
	var buf := PackedFloat32Array()
	if near > 0.0:
		buf = _commit(cell, kind, xfs, cols, near + CELL * 0.75, wheat_near_mat if mat == wheat_mat else grass_near_mat)
	_commit(cell, kind + "Low", xfs, cols, far, mat, maxf(0.0, near - HANDOVER - CELL * 0.75), buf)

func _plant_corn(cell: Node3D, x0: float, y0: float) -> void:
	var xfs := []
	var cols := []
	for p in _grid(x0, y0, CORN_STEP, 5.0):
		if _crop_at(_px(p[0], p[1])) != 0:
			continue
		var h: float = p[2]
		xfs.append(_place(p[0], p[1], h * TAU * 5.0, Vector3(1.0, 0.8 + hash2(p[0], p[1], 6.0) * 0.4, 1.0) * (0.9 + h * 0.2)))
		var t := 0.85 + hash2(p[0], p[1], 8.0) * 0.25
		cols.append(Color(t, t, t * 0.95))
	# a cell's maize dithers out over CORN_MARGIN, all of it within the planted ring's lead
	var end := float(GRASS_QUALITY[quality].far) + CELL * HALF_DIAG - CORN_MARGIN
	_commit(cell, "Corn", xfs, cols, end)
	var mz := cell.get_child(cell.get_child_count() - 1) as GeometryInstance3D if cell.get_child_count() > 0 else null
	if mz and mz.name == "Corn":
		mz.visibility_range_end_margin = CORN_MARGIN
		mz.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

## Meadow grass: thinned and sized by _grass_at (tall clumps along the edges, a thinner, shorter open meadow, mown
## lawns, parks and verges); pitches stay bare.
func _plant_grass(cell: Node3D, x0: float, y0: float) -> void:
	var xfs := []
	var cols := []
	var key := cell_key(floori(x0 / CELL), floori(y0 / CELL))
	var any_area := _areas.has(key)
	var cache := _block_cache(x0, y0, CELL)
	for p in _grid(x0, y0, float(GRASS_QUALITY[quality].step), 9.0):
		var i := _px(p[0], p[1])
		# grass, or the fading edge of a road's paint (R paved, B a dirt road's earth): short grass up to the road
		if i < 0 or land[i + 1] >= 40 or land[i + 3] >= 30:
			continue
		if maxi(land[i], land[i + 2]) >= 110:
			continue
		var pos := Vector2(p[0], p[1])
		var area := _area_at(key, pos) if any_area else ""
		if area == "pitch":
			continue
		var mown := area == "park" or land[i] > 0 # gardens and yards are painted R 25 (or more)
		var blk: PackedFloat32Array = _block(cache, p[0], p[1])
		var g := _grass_at(i, p[0], p[1], mown, blk)
		if hash2(p[0], p[1], 10.0) >= g.x: # cheap: before the road and building checks
			continue
		if (blk[6] == 0.0 and map.inside_building(pos)) or (blk[5] == 0.0 and not _clear_of_road(p[0], p[1], GRASS_REACH)):
			continue
		var wide := 1.0 + hash2(p[0], p[1], 15.0) * 0.25
		xfs.append(_place(p[0], p[1], hash2(p[0], p[1], 13.0) * TAU, Vector3(wide, g.y, wide), -0.02))
		cols.append(_grass_tint(p[0], p[1], mown, blk[4]))
	_commit_patches(cell, "GrassPatch", xfs, cols, grass_mat)

## INSTANCE_CUSTOM of a grass patch or tuft (grass.gdshader): a tint around 1, and how dry it is (A).
func _grass_tint(x: float, y: float, mown: bool, dry: float) -> Color:
	var t := 0.9 + hash2(x, y, 14.0) * 0.2
	return Color(t, t, t * 0.95, 0.08 if mown else clampf(dry * 1.1 - 0.4, 0.0, 0.5))

## The far layer's grass: broad tufts at about a tenth of the patches' blades, wherever the meadow grows tall enough
## to show from afar (none on lawns: they read from the ground's own colour), out to the preset's "tuft" distance. They
## stand near the camera too, among the patches, so as those sink at their far edge the tufts are already there.
func _plant_tufts(cell: Node3D, x0: float, y0: float) -> void:
	var xfs := []
	var cols := []
	var cache := _block_cache(x0, y0, FAR_CELL)
	for p in _grid(x0, y0, TUFT_STEP, 33.0, FAR_CELL):
		var i := _px(p[0], p[1])
		if i < 0 or land[i] > 0 or land[i + 1] >= 40 or land[i + 3] >= 30 or land[i + 2] >= 40:
			continue
		var pos := Vector2(p[0], p[1])
		var blk: PackedFloat32Array = _block(cache, p[0], p[1])
		var g := _grass_at(i, p[0], p[1], false, blk)
		if hash2(p[0], p[1], 34.0) >= (g.x - 0.15) * 0.75 or g.y < 0.35:
			continue
		if _area_at(cell_key(floori(p[0] / CELL), floori(p[1] / CELL)), pos) != "":
			continue
		if (blk[6] == 0.0 and map.inside_building(pos)) or (blk[5] == 0.0 and not _clear_of_road(p[0], p[1], 0.7)):
			continue
		var wide := 1.0 + hash2(p[0], p[1], 35.0) * 0.3
		xfs.append(_place(p[0], p[1], hash2(p[0], p[1], 36.0) * TAU, Vector3(wide, g.y * (0.9 + 0.2 * hash2(p[0], p[1], 37.0)), wide), -0.02))
		cols.append(_grass_tint(p[0], p[1], false, blk[4]))
	var q: Dictionary = GRASS_QUALITY[quality]
	_commit(cell, "GrassTuft", xfs, cols, float(q.tuft) + FAR_CELL * HALF_DIAG, tuft_mat)

## Flowers grow in patches of one or two colours.
func _plant_flowers(cell: Node3D, x0: float, y0: float) -> void:
	var xfs := []
	var cols := []
	for p in _grid(x0, y0, FLOWER_STEP, 15.0):
		var patch := vnoise(p[0], p[1], 14.0, 17.0)
		if patch < 0.64 or float(p[2]) > (patch - 0.5) * 2.2:
			continue
		if not _is_grass(_px(p[0], p[1])):
			continue
		if map.inside_building(Vector2(p[0], p[1])) or not _clear_of_road(p[0], p[1], 0.75):
			continue
		var pid_x := floorf(p[0] / 14.0)
		var pid_y := floorf(p[1] / 14.0)
		var pick := int(hash2(pid_x, pid_y, 19.0) * FLOWER_COLOURS.size())
		if hash2(p[0], p[1], 20.0) < 0.22: # a few of another colour
			pick = int(hash2(p[0], p[1], 21.0) * FLOWER_COLOURS.size())
		var s := 0.7 + hash2(p[0], p[1], 22.0) * 0.5 # knee high at most (the mesh is 0.45 m): just over the meadow grass
		xfs.append(_place(p[0], p[1], hash2(p[0], p[1], 23.0) * TAU, Vector3(s, s * (0.9 + hash2(p[0], p[1], 24.0) * 0.5), s), -0.02))
		cols.append(FLOWER_COLOURS[pick % FLOWER_COLOURS.size()])
	_commit(cell, "Flower", xfs, cols, FLOWER_RANGE)
	var fl := cell.get_child(cell.get_child_count() - 1) as GeometryInstance3D if cell.get_child_count() > 0 else null
	if fl and fl.name == "Flower":
		# the cell's flowers dissolve in over the margin, not all at once when the cell is planted
		fl.visibility_range_end_margin = FLOWER_MARGIN
		fl.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

## Thickets on the scrub (forest floor at about 40% in the land map); bushes in clumps round the houses in their
## gardens; along field edges, fences, hedgerows and streams; a few lone ones on the meadows. Planted in the far
## cells: each dithers in between the preset's "bush" distance and BUSH_FADE nearer (shrub.gdshader).
func _plant_bushes(cell: Node3D, x0: float, y0: float) -> void:
	var xfs := []
	var cols := []
	for p in _grid(x0, y0, BUSH_STEP, 25.0, FAR_CELL):
		var i := _px(p[0], p[1])
		if i < 0 or land[i] > 60 or land[i + 1] > 40 or land[i + 2] > 80:
			continue
		var a := land[i + 3]
		var pos := Vector2(p[0], p[1])
		var chance := 0.0
		var garden := false
		if a >= 80 and a <= 170:
			chance = 0.35 # scrub
		elif a < 30 and land[i] >= 12: # a garden or yard: clumps of shrubs by the houses
			if vnoise(p[0], p[1], 9.0, 61.0) > 0.55:
				chance = 0.42
			else:
				chance = 0.04
			garden = true
		elif a < 30:
			var edge := _edge_at(i, p[0], p[1])
			chance = 0.045 * vnoise(p[0], p[1], 60.0, 26.0) * 3.0 # lone bushes, more in some places
			if edge > 0.0 and vnoise(p[0], p[1], 25.0, 62.0) > 0.42: # hedgerow-like runs along the edges
				chance += 0.2 * edge
		if chance <= 0.0 or float(p[2]) > chance:
			continue
		if map.inside_building(pos) or not _clear_of_road(p[0], p[1], 1.4):
			continue
		if garden:
			if map.buildings_near(pos, 12.0).is_empty():
				continue # a yard with no house near: a car park's verge, a works' fence line
			var wall := false
			for o in [Vector2(1.3, 0.0), Vector2(-1.3, 0.0), Vector2(0.0, 1.3), Vector2(0.0, -1.3)]:
				wall = wall or map.inside_building(pos + o)
			if wall:
				continue
		var s := (0.7 + hash2(p[0], p[1], 27.0) * 0.9) * (0.85 if garden else 1.0)
		xfs.append(_place(p[0], p[1], hash2(p[0], p[1], 28.0) * TAU, Vector3(s, s * (0.8 + hash2(p[0], p[1], 29.0) * 0.4), s), -0.1))
		# a tint around 1 on the shrub shader's greens: some bushes yellower, some bluer, some darker
		var t := 0.8 + hash2(p[0], p[1], 30.0) * 0.4
		var hue := hash2(p[0], p[1], 31.0)
		cols.append(Color(t * lerpf(0.85, 1.15, hue), t, t * lerpf(1.1, 0.8, hue)))
	_commit(cell, "BushCluster", xfs, cols, float(GRASS_QUALITY[quality].bush) + FAR_CELL * HALF_DIAG, bush_mat)
