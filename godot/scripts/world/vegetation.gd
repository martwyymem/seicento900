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
const FAR_LAYERS := 4 ## far: grass tufts, bushes, far maize, far wheat
const FLOWER_STEP := 1.6
const TUFT_STEP := 3.0 ## m between far-layer grass tufts (before thinning)
const BUSH_STEP := 4.0
const CORN_FAR_STEP := 5.0 ## m between far-layer maize canopy tufts
const WHEAT_FAR_STEP := 5.0 ## m between far-layer wheat canopy tufts
const GRASS_REACH := 1.0 ## m: a grass patch's blades spread this far from its middle (0.8 m, widened up to 1.25x)
const BUDGET_USEC := 2500 ## planting time per frame
const HANDOVER := 14.0 ## m over which the dense patches give way to the sparse ones (grass.gdshader lod_out/lod_in)
const FAR_FADE := 50.0 ## m over which the blades sink at the far edge (at most half the reach)
const TUFT_FADE := 60.0 ## m over which the tufts sink at the far ring's edge
const CORN_FADE := 22.0 ## m over which near maize sinks as CornFar rises
const CROP_FAR_FADE := 60.0 ## m over which far crop tufts sink into the terrain's field colour
const TONE_NEAR := 30.0 ## m from which every grass blade starts to take the far colour (to the tufts' edge)
const BUSH_FADE := 35.0 ## m over which a bush dithers in at the far ring's edge
const FIELD_MIN := 100 ## land map G (0-255) from which a pixel is a field
const EDGE_RES := 5.0 ## m per cell of the edge mask (fences, hedges, garden trees, streams: tall grass grows along them)
const GRASS_SHADER := preload("res://shaders/grass.gdshader")
const SHRUB_SHADER := preload("res://shaders/shrub.gdshader")
const RACE_WORLD := preload("res://scripts/ui/race_world.gd")
## The meadow's and fields' colours seen from afar: the plants fade to them towards the edge of their ring, and the
## ground shader paints the terrain beyond with the same colours (TownBuilder.build_terrain), so there is no colour seam
const MEADOW_FAR := Color(0.46, 0.52, 0.22)
const MEADOW_FAR_DRY := Color(0.56, 0.54, 0.25)
const CORN_FAR_COLOR := Color(0.28, 0.44, 0.14)
const WHEAT_FAR_COLOR := Color(0.78, 0.66, 0.3)
## Global row axes for planted maize: perpendicular to ground.gdshader's vec2(0.6, 0.8) tractor-row stripes
const CORN_ROW_DIR := Vector2(-0.8, 0.6)
const CORN_ROW_PERP := Vector2(0.6, 0.8)
## Base crop draw ranges at ow_draw_scale = 1.0 (High preset), scaled by draw_scale
const CORN_NEAR_RANGE := 66.0
const CORN_FAR_RANGE := 210.0
const WHEAT_FAR_RANGE := 200.0
const FLOWER_RANGE := 50.0 ## m: a flower cell's centre shows within this, fading out over the next FLOWER_MARGIN
const FLOWER_MARGIN := 18.0
## per graphics preset (0 Low .. 3 Ultra): m between grass patches (before _block thins them), wheat patches, and
## maize row-blocks (corn_u along row, corn_v across 2-row block), how near a cell's centre must be for the
## dense patches (0: never), where the patches have sunk away, where the far layer's tufts have, and where the bushes
## have faded out
const GRASS_QUALITY := [{"step": 2.0, "wheat": 1.6, "corn_u": 2.65, "corn_v": 1.80, "near": 0.0, "far": 50.0, "tuft": 150.0, "bush": 130.0},
	{"step": 1.7, "wheat": 1.35, "corn_u": 2.50, "corn_v": 1.65, "near": 22.0, "far": 58.0, "tuft": 180.0, "bush": 160.0},
	{"step": 1.45, "wheat": 1.15, "corn_u": 2.35, "corn_v": 1.56, "near": 28.0, "far": 66.0, "tuft": 210.0, "bush": 190.0},
	{"step": 1.25, "wheat": 1.0, "corn_u": 2.05, "corn_v": 1.56, "near": 34.0, "far": 76.0, "tuft": 240.0, "bush": 220.0}]
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
var draw_scale := 1.0
var grass_mat: ShaderMaterial
var wheat_mat: ShaderMaterial
var grass_near_mat: ShaderMaterial ## the dense patches' copies: their blades leave across the hand-over band
var wheat_near_mat: ShaderMaterial
var wheat_far_mat: ShaderMaterial ## far-layer wheat tufts
var corn_mat: ShaderMaterial ## near dense maize row-blocks
var corn_far_mat: ShaderMaterial ## far-layer maize canopy tufts
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
	wheat_mat.set_shader_parameter("far_color", WHEAT_FAR_COLOR) # the ground shader's ripe field (farm_color_a)
	wheat_mat.set_shader_parameter("wind_strength", 0.1)
	grass_mat.set_shader_parameter("far_color", MEADOW_FAR)
	grass_near_mat = grass_mat.duplicate() as ShaderMaterial
	tuft_mat = grass_mat.duplicate() as ShaderMaterial
	bush_mat = ShaderMaterial.new()
	bush_mat.shader = SHRUB_SHADER
	bush_mat.set_shader_parameter("grain", RACE_WORLD.noise_texture("grain"))
	wheat_near_mat = wheat_mat.duplicate() as ShaderMaterial
	wheat_far_mat = wheat_mat.duplicate() as ShaderMaterial
	wheat_far_mat.set_shader_parameter("wind_strength", 0.06)
	corn_mat = ShaderMaterial.new()
	corn_mat.shader = GRASS_SHADER
	corn_mat.set_shader_parameter("root_color", Color(0.06, 0.11, 0.04))
	corn_mat.set_shader_parameter("mid_color", Color(0.20, 0.36, 0.10))
	corn_mat.set_shader_parameter("tip_color", Color(0.36, 0.50, 0.16))
	corn_mat.set_shader_parameter("dry_color", Color(0.48, 0.54, 0.22))
	corn_mat.set_shader_parameter("ear_color", Color(0.82, 0.74, 0.44))
	corn_mat.set_shader_parameter("far_color", CORN_FAR_COLOR)
	corn_mat.set_shader_parameter("wind_strength", 0.12)
	corn_mat.set_shader_parameter("translucency", 0.45)
	corn_far_mat = corn_mat.duplicate() as ShaderMaterial
	corn_far_mat.set_shader_parameter("wind_strength", 0.07)
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
	var tinted := {"BushCluster": [], "Flower": ["Petal"]}
	for kind in ["GrassPatch", "GrassPatchLow", "GrassTuft", "WheatPatch", "WheatPatchLow", "WheatFar", "Corn", "CornFar"]:
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
		if (e[2] as Rect2).has_point(p) and TownMap.inside(p, e[1]):
			return e[0]
	return ""

func _corn_near() -> float:
	return CORN_NEAR_RANGE * draw_scale

func _corn_far() -> float:
	return CORN_FAR_RANGE * draw_scale

func _wheat_far() -> float:
	return WHEAT_FAR_RANGE * draw_scale

func _wheat_near_end() -> float:
	var preset_scale := maxf(float(GraphicsPresets.preset(quality).ow_draw_scale), 0.1)
	return float(GRASS_QUALITY[quality].far) * (draw_scale / preset_scale)

## m from the camera within which a near cell's centre is planted: its nearest blades LEAD m beyond where they have
## sunk away.
func radius() -> float:
	return maxf(float(GRASS_QUALITY[quality].far), maxf(_wheat_near_end(), _corn_near())) + CELL * HALF_DIAG + LEAD

## The same for the far cells (tufts, bushes, far crops).
func far_radius() -> float:
	var q: Dictionary = GRASS_QUALITY[quality]
	return maxf(maxf(float(q.tuft), float(q.bush)), maxf(_corn_far(), _wheat_far())) + FAR_CELL * HALF_DIAG + LEAD

## Applies current quality + draw_scale ranges to all shader uniforms and live crop MultiMesh instances.
func _apply_ranges() -> void:
	var q: Dictionary = GRASS_QUALITY[quality]
	var band := Vector2(maxf(0.0, float(q.near) - HANDOVER), float(q.near)) if float(q.near) > 0.0 else Vector2.ZERO
	for mat in [grass_mat, grass_near_mat, tuft_mat]:
		if mat:
			mat.set_shader_parameter("fade_start", float(q.far) - minf(FAR_FADE, float(q.far) * 0.5))
			mat.set_shader_parameter("fade_end", float(q.far))
			mat.set_shader_parameter("tone_range", Vector2(TONE_NEAR, float(q.tuft)))
	if tuft_mat:
		tuft_mat.set_shader_parameter("fade_start", float(q.tuft) - TUFT_FADE)
		tuft_mat.set_shader_parameter("fade_end", float(q.tuft))
	if bush_mat:
		bush_mat.set_shader_parameter("fade_near", float(q.bush) - BUSH_FADE)
		bush_mat.set_shader_parameter("fade_far", float(q.bush))
	var w_end := _wheat_near_end()
	var w_far := _wheat_far()
	var w_fade := minf(FAR_FADE, w_end * 0.5)
	for mat in [wheat_mat, wheat_near_mat]:
		if mat:
			mat.set_shader_parameter("fade_start", w_end - w_fade)
			mat.set_shader_parameter("fade_end", w_end)
			mat.set_shader_parameter("tone_range", Vector2(TONE_NEAR, w_far))
	if wheat_far_mat:
		var w_in_a := maxf(0.0, w_end - w_fade)
		var w_in_b := maxf(w_in_a + 4.0, w_end - 4.0)
		wheat_far_mat.set_shader_parameter("lod_in", Vector2(w_in_a, w_in_b))
		wheat_far_mat.set_shader_parameter("fade_start", maxf(w_in_b + 8.0, w_far - CROP_FAR_FADE * draw_scale))
		wheat_far_mat.set_shader_parameter("fade_end", w_far)
		wheat_far_mat.set_shader_parameter("tone_range", Vector2(TONE_NEAR, w_far))
	var c_near := _corn_near()
	var c_far := _corn_far()
	var c_fade := minf(CORN_FADE, c_near * 0.4)
	if corn_mat:
		corn_mat.set_shader_parameter("fade_start", c_near - c_fade)
		corn_mat.set_shader_parameter("fade_end", c_near)
		corn_mat.set_shader_parameter("tone_range", Vector2(TONE_NEAR, c_far))
	if corn_far_mat:
		var c_in_a := maxf(0.0, c_near - c_fade)
		var c_in_b := maxf(c_in_a + 4.0, c_near - 4.0)
		corn_far_mat.set_shader_parameter("lod_in", Vector2(c_in_a, c_in_b))
		corn_far_mat.set_shader_parameter("fade_start", maxf(c_in_b + 8.0, c_far - CROP_FAR_FADE * draw_scale))
		corn_far_mat.set_shader_parameter("fade_end", c_far)
		corn_far_mat.set_shader_parameter("tone_range", Vector2(TONE_NEAR, c_far))
	for mat in [grass_mat, wheat_mat]:
		if mat:
			mat.set_shader_parameter("lod_in", band)
	for mat in [grass_near_mat, wheat_near_mat]:
		if mat:
			mat.set_shader_parameter("lod_out", band)
	# update live crop MultiMeshes when draw_scale changes without forcing a full replant
	var c_near_mmi_end := c_near + CELL * 0.75
	var c_far_mmi_begin := maxf(0.0, c_near - c_fade - FAR_CELL * HALF_DIAG)
	var c_far_mmi_end := c_far + FAR_CELL * HALF_DIAG
	var w_near_mmi_end := w_end + CELL * 0.75
	var w_far_mmi_begin := maxf(0.0, w_end - w_fade - FAR_CELL * HALF_DIAG)
	var w_far_mmi_end := w_far + FAR_CELL * HALF_DIAG
	for k in cells:
		for ch in (cells[k] as Node3D).get_children():
			var mmi := ch as MultiMeshInstance3D
			if mmi == null:
				continue
			match String(mmi.name):
				"Corn":
					mmi.visibility_range_end = c_near_mmi_end
				"CornFar":
					mmi.visibility_range_begin = c_far_mmi_begin
					mmi.visibility_range_end = c_far_mmi_end
				"WheatPatchLow":
					mmi.visibility_range_end = w_near_mmi_end
				"WheatFar":
					mmi.visibility_range_begin = w_far_mmi_begin
					mmi.visibility_range_end = w_far_mmi_end

## Scales crop draw distances with the preset's ow_draw_scale (forwarded by TownBuilder.set_draw_scale).
func set_draw_scale(k: float) -> void:
	var clamped := clampf(k, 0.25, 2.0)
	if is_equal_approx(draw_scale, clamped):
		return
	var grew := clamped > draw_scale
	draw_scale = clamped
	_apply_ranges()
	if grew:
		_last_cell = Vector2i(1 << 30, 1 << 30)

## Sets the graphics preset (0 Low .. 3 Ultra) and replants: how dense and how far the grass and crops grow.
func set_quality(level: int) -> void:
	quality = clampi(level, 0, GRASS_QUALITY.size() - 1)
	draw_scale = float(GraphicsPresets.preset(quality).ow_draw_scale)
	_apply_ranges()
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
			2: _plant_corn_far(cell, x0, y0)
			3: _plant_wheat_far(cell, x0, y0)
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

## Global row-aligned grid inside [x0, x0 + size) x [y0, y0 + size): seamless across cell boundaries, with small
## organic jitter (jitter_u along dir, jitter_v across perp). Each entry is [x, y, hash].
func _row_grid(x0: float, y0: float, step_u: float, step_v: float, dir: Vector2, perp: Vector2,
		jitter_u: float, jitter_v: float, salt: float, size := CELL) -> Array:
	var umin := INF
	var umax := -INF
	var vmin := INF
	var vmax := -INF
	for c: Vector2 in [Vector2(x0, y0), Vector2(x0 + size, y0), Vector2(x0, y0 + size), Vector2(x0 + size, y0 + size)]:
		var u: float = c.dot(dir)
		var v: float = c.dot(perp)
		umin = minf(umin, u)
		umax = maxf(umax, u)
		vmin = minf(vmin, v)
		vmax = maxf(vmax, v)
	var iu0 := floori(umin / step_u) - 1
	var iu1 := ceili(umax / step_u) + 1
	var iv0 := floori(vmin / step_v) - 1
	var iv1 := ceili(vmax / step_v) + 1
	var out := []
	for iv in range(iv0, iv1 + 1):
		for iu in range(iu0, iu1 + 1):
			var h := hash2(float(iu) * 0.37, float(iv) * 0.71, salt)
			var h2 := hash2(float(iv) * 0.13, float(iu) * 0.57, salt + 3.0)
			var u := (float(iu) + 0.5) * step_u + (h - 0.5) * 2.0 * jitter_u
			var v := (float(iv) + 0.5) * step_v + (h2 - 0.5) * 2.0 * jitter_v
			var p := dir * u + perp * v
			if p.x >= x0 and p.x < x0 + size and p.y >= y0 and p.y < y0 + size:
				out.append([p.x, p.y, h])
	return out

func _plant_wheat(cell: Node3D, x0: float, y0: float) -> void:
	var xfs := []
	var cols := []
	for p in _grid(x0, y0, float(GRASS_QUALITY[quality].wheat), 1.0):
		if _crop_at(_px(p[0], p[1])) != 1:
			continue
		if map.inside_building(Vector2(p[0], p[1])) or not _clear_of_road(p[0], p[1], 0.85):
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
	var far := (_wheat_near_end() if mat == wheat_mat else float(q.far)) + CELL * 0.75 # the cell centre's distance; the shader sinks the blades by their own
	# visibility ranges go by the cell's centre, so both kinds are drawn wherever the cell may reach into the
	# hand-over band; the shader hands each blade over at its own distance
	var buf := PackedFloat32Array()
	if near > 0.0:
		buf = _commit(cell, kind, xfs, cols, near + CELL * 0.75, wheat_near_mat if mat == wheat_mat else grass_near_mat)
	_commit(cell, kind + "Low", xfs, cols, far, mat, maxf(0.0, near - HANDOVER - CELL * 0.75), buf)

## Maize: 2-row patches aligned to CORN_ROW_DIR so rows interlock across cell boundaries (0.78 m row spacing at High/Ultra),
## drawn with grass.gdshader (corn_mat) for wind sway, root darkening, backlight and smooth per-plant sinking into CornFar.
func _plant_corn(cell: Node3D, x0: float, y0: float) -> void:
	var xfs := []
	var cols := []
	var q: Dictionary = GRASS_QUALITY[quality]
	var su := float(q.corn_u)
	var sv := float(q.corn_v)
	var base_yaw := atan2(-CORN_ROW_DIR.y, CORN_ROW_DIR.x)
	for p in _row_grid(x0, y0, su, sv, CORN_ROW_DIR, CORN_ROW_PERP, su * 0.14, 0.08, 5.0):
		if _crop_at(_px(p[0], p[1])) != 0:
			continue
		if map.inside_building(Vector2(p[0], p[1])) or not _clear_of_road(p[0], p[1], 1.2):
			continue
		var h: float = p[2]
		var yaw := base_yaw + (PI if h > 0.5 else 0.0) + (hash2(p[0], p[1], 7.0) - 0.5) * 0.16
		var sy := 0.90 + hash2(p[0], p[1], 6.0) * 0.24
		var sxz := 0.95 + h * 0.14
		xfs.append(_place(p[0], p[1], yaw, Vector3(sxz, sy, sxz), -0.04))
		var t := 0.88 + hash2(p[0], p[1], 8.0) * 0.24
		var dry := 0.08 + 0.22 * vnoise(p[0], p[1], 36.0, 9.0)
		cols.append(Color(t * (0.96 + 0.08 * h), t, t * (0.92 + 0.1 * h), dry))
	_commit(cell, "Corn", xfs, cols, _corn_near() + CELL * 0.75, corn_mat)

## Far-layer maize canopy tufts in FAR_CELL squares: rise smoothly as near Corn sinks, keeping fields a dense 2 m wall out past 200 m.
func _plant_corn_far(cell: Node3D, x0: float, y0: float) -> void:
	var xfs := []
	var cols := []
	for p in _grid(x0, y0, CORN_FAR_STEP, 41.0, FAR_CELL):
		if _crop_at(_px(p[0], p[1])) != 0:
			continue
		if map.inside_building(Vector2(p[0], p[1])) or not _clear_of_road(p[0], p[1], 2.3):
			continue
		var h: float = p[2]
		var sy := 0.92 + hash2(p[0], p[1], 42.0) * 0.20
		var sxz := 0.96 + hash2(p[0], p[1], 43.0) * 0.18
		xfs.append(_place(p[0], p[1], h * TAU * 3.0, Vector3(sxz, sy, sxz), -0.05))
		var t := 0.90 + hash2(p[0], p[1], 44.0) * 0.20
		cols.append(Color(t, t, t * 0.96, 0.12 + 0.2 * vnoise(p[0], p[1], 40.0, 45.0)))
	var c_near := _corn_near()
	var c_fade := minf(CORN_FADE, c_near * 0.4)
	_commit(cell, "CornFar", xfs, cols, _corn_far() + FAR_CELL * HALF_DIAG, corn_far_mat,
		maxf(0.0, c_near - c_fade - FAR_CELL * HALF_DIAG))

## Far-layer wheat canopy tufts in FAR_CELL squares: rise smoothly as WheatPatchLow sinks, keeping ripe fields standing out past 200 m.
func _plant_wheat_far(cell: Node3D, x0: float, y0: float) -> void:
	var xfs := []
	var cols := []
	for p in _grid(x0, y0, WHEAT_FAR_STEP, 51.0, FAR_CELL):
		if _crop_at(_px(p[0], p[1])) != 1:
			continue
		if map.inside_building(Vector2(p[0], p[1])) or not _clear_of_road(p[0], p[1], 2.3):
			continue
		var h: float = p[2]
		var sy := 0.92 + hash2(p[0], p[1], 52.0) * 0.20
		var sxz := 0.96 + hash2(p[0], p[1], 53.0) * 0.18
		xfs.append(_place(p[0], p[1], h * TAU * 3.0, Vector3(sxz, sy, sxz), -0.04))
		var t := 0.90 + hash2(p[0], p[1], 54.0) * 0.20
		cols.append(Color(t, t * (0.97 + 0.05 * h), t * (0.92 + 0.1 * h), 0.2 + 0.3 * vnoise(p[0], p[1], 36.0, 55.0)))
	var w_end := _wheat_near_end()
	var w_fade := minf(FAR_FADE, w_end * 0.5)
	_commit(cell, "WheatFar", xfs, cols, _wheat_far() + FAR_CELL * HALF_DIAG, wheat_far_mat,
		maxf(0.0, w_end - w_fade - FAR_CELL * HALF_DIAG))

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
