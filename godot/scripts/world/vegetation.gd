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
## The map has ~60 km2 of it, so nothing is baked: the world is cut into CELL squares, the ones within RADIUS of the
## camera get one MultiMesh per plant kind (built nearest first, within BUDGET_USEC a frame), and the cells left behind
## are freed.
extends Node3D

const ROADSIDE := "res://models/roadside.glb"
const WORLD_ASSETS := preload("res://scripts/ui/world_assets.gd")
const LAND_RES := 2.5 ## metres per land map texel, as TownBuilder.LAND_RES
const CELL := 32.0 ## m
const RADIUS := 100.0 ## m: cells whose centre is this near the camera are planted
const KEEP := RADIUS + CELL * 1.5 ## m: and freed beyond this
const LAYERS := 5 ## wheat, maize, grass, flowers, bushes
const CORN_STEP := 2.3 ## m between clumps
const FLOWER_STEP := 1.6
const BUSH_STEP := 5.0
const GRASS_REACH := 1.0 ## m: a grass patch's blades spread this far from its middle (0.8 m, widened up to 1.25x)
const BUDGET_USEC := 2500 ## planting time per frame
const HANDOVER := 14.0 ## m over which the dense patches give way to the sparse ones (grass.gdshader lod_out/lod_in)
const FAR_FADE := 40.0 ## m over which the blades sink at the far edge (at most 45% of the reach)
const FIELD_MIN := 100 ## land map G (0-255) from which a pixel is a field
const GRASS_SHADER := preload("res://shaders/grass.gdshader")
## per graphics preset (0 Low .. 3 Ultra): m between grass and wheat patches, how near a cell's centre must be for the
## dense patches (0: never), and where the grass has sunk away
const GRASS_QUALITY := [{"step": 1.6, "near": 0.0, "far": 62.0}, {"step": 1.35, "near": 26.0, "far": 74.0},
	{"step": 1.15, "near": 36.0, "far": 88.0}, {"step": 1.0, "near": 46.0, "far": 100.0}]
const FLOWER_COLOURS := [Color(1.0, 1.0, 0.95), Color(1.0, 0.85, 0.15), Color(0.95, 0.2, 0.18), Color(0.62, 0.38, 0.95),
	Color(1.0, 0.55, 0.12), Color(1.0, 0.62, 0.78)]

var map: TownMap
var land := PackedByteArray() ## RGBA8 of the land map
var land_w := 0
var land_h := 0
var meshes := {} ## kind -> prepared Mesh
var cells := {} ## cell key -> Node3D
var queue: Array = [] ## [key, cx, cy, layer], nearest first
var queued := {} ## cell key -> true while it has tasks waiting
var _last_cell := Vector2i(1 << 30, 1 << 30)
var counts := {} ## kind -> instances alive, for the probes
var quality := 2
var grass_mat: ShaderMaterial
var wheat_mat: ShaderMaterial
var grass_near_mat: ShaderMaterial ## the dense patches' copies: their blades leave across the hand-over band
var wheat_near_mat: ShaderMaterial
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
	wheat_mat.set_shader_parameter("wind_strength", 0.1)
	grass_near_mat = grass_mat.duplicate() as ShaderMaterial
	wheat_near_mat = wheat_mat.duplicate() as ShaderMaterial
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
	for kind in ["GrassPatch", "GrassPatchLow", "WheatPatch", "WheatPatchLow"]:
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

## "pitch", "park" or "" at p, from the areas over cell `key`.
func _area_at(key: int, p: Vector2) -> String:
	for e in _areas.get(key, []):
		if (e[2] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, e[1]):
			return e[0]
	return ""

## Sets the graphics preset (0 Low .. 3 Ultra) and replants: how dense and how far the grass grows.
func set_quality(level: int) -> void:
	quality = clampi(level, 0, GRASS_QUALITY.size() - 1)
	var q: Dictionary = GRASS_QUALITY[quality]
	var band := Vector2(maxf(0.0, float(q.near) - HANDOVER), float(q.near)) if float(q.near) > 0.0 else Vector2.ZERO
	for mat in [grass_mat, wheat_mat, grass_near_mat, wheat_near_mat]:
		if mat:
			mat.set_shader_parameter("fade_start", float(q.far) - minf(FAR_FADE, float(q.far) * 0.45))
			mat.set_shader_parameter("fade_end", float(q.far))
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
	var r := int(ceil(KEEP / CELL))
	for k in cells.keys():
		var c: Node3D = cells[k]
		if c.has_meta("centre") and (c.get_meta("centre") as Vector2).distance_to(p) > KEEP:
			_free_cell(k)
	var want := []
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var cx := here.x + dx
			var cy := here.y + dy
			var centre := Vector2((cx + 0.5) * CELL, (cy + 0.5) * CELL)
			var d := centre.distance_to(p)
			var key := cell_key(cx, cy)
			if d <= RADIUS and not cells.has(key) and not queued.has(key):
				want.append([d, key, cx, cy])
	want.sort_custom(func(a, b): return a[0] < b[0])
	var keep := []
	for t in queue: # drop queued cells that fell out of range, keep the rest in front
		var centre := Vector2((int(t[1]) + 0.5) * CELL, (int(t[2]) + 0.5) * CELL)
		if centre.distance_to(p) <= KEEP:
			keep.append(t)
		else:
			queued.erase(cell_key(int(t[1]), int(t[2])))
	queue = keep
	for w in want:
		queued[w[1]] = true
		for layer in LAYERS:
			queue.append([w[1], w[2], w[3], layer])
	# nearest cells first, wherever the camera has got to
	var dist := func(t: Array) -> float:
		return Vector2((int(t[1]) + 0.5) * CELL, (int(t[2]) + 0.5) * CELL).distance_squared_to(p) + float(t[3]) * 0.01
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
		if not cells.has(key):
			var node := Node3D.new()
			node.name = "Cell %d %d" % [cx, cy]
			node.set_meta("centre", Vector2((cx + 0.5) * CELL, (cy + 0.5) * CELL))
			node.set_meta("counts", {})
			add_child(node)
			cells[key] = node
		var cell: Node3D = cells[key]
		_plant(cell, cx, cy, layer)
		if layer == LAYERS - 1:
			queued.erase(key)

## Calls run_queue until the queue is empty (the probes and the first frame).
func plant_all() -> void:
	while not queue.is_empty():
		run_queue(64)

func _plant(cell: Node3D, cx: int, cy: int, layer: int) -> void:
	var x0 := cx * CELL
	var y0 := cy * CELL
	if not map.in_play(Vector2(x0 + CELL * 0.5, y0 + CELL * 0.5)):
		return
	match layer:
		0: _plant_wheat(cell, x0, y0)
		1: _plant_corn(cell, x0, y0)
		2: _plant_grass(cell, x0, y0)
		3: _plant_flowers(cell, x0, y0)
		4: _plant_bushes(cell, x0, y0)

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
## the instance colour; range_begin/range_end are the cell centre's distance from the camera it shows between.
func _commit(cell: Node3D, kind: String, xfs: Array, cols: Array, range_end: float, mat: Material = null, range_begin := 0.0) -> void:
	if xfs.is_empty() or not meshes.has(kind):
		return
	if record:
		if not recorded.has(kind):
			recorded[kind] = PackedVector3Array()
		for xf in xfs:
			recorded[kind].append((xf as Transform3D).origin)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = mat == null
	mm.use_custom_data = mat != null
	mm.mesh = meshes[kind]
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		if mat == null:
			mm.set_instance_color(i, cols[i])
		else:
			mm.set_instance_custom_data(i, cols[i])
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

## Grid points of a cell with the given step and a jitter of up to 0.4 step, as [x, y, hash].
func _grid(x0: float, y0: float, step: float, salt: float) -> Array:
	var out := []
	var n := int(ceil(CELL / step))
	for gy in n:
		for gx in n:
			var h := hash2(x0 + gx * 0.37, y0 + gy * 0.71, salt)
			var h2 := hash2(y0 + gy * 0.13, x0 + gx * 0.57, salt + 3.0)
			out.append([x0 + (gx + 0.5 + (h - 0.5) * 0.8) * step, y0 + (gy + 0.5 + (h2 - 0.5) * 0.8) * step, h])
	return out

func _plant_wheat(cell: Node3D, x0: float, y0: float) -> void:
	var xfs := []
	var cols := []
	for p in _grid(x0, y0, float(GRASS_QUALITY[quality].step), 1.0):
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
	if near > 0.0:
		_commit(cell, kind, xfs, cols, near + CELL * 0.75, wheat_near_mat if mat == wheat_mat else grass_near_mat)
	_commit(cell, kind + "Low", xfs, cols, far, mat, maxf(0.0, near - HANDOVER - CELL * 0.75))

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
	_commit(cell, "Corn", xfs, cols, RADIUS + 12.0)

## A meadow's grass stands knee to waist high, browner in some places than others; lawns, parks and the verges
## by the road (where the land map's paving fades out) are mown short; pitches stay bare.
func _plant_grass(cell: Node3D, x0: float, y0: float) -> void:
	var xfs := []
	var cols := []
	var key := cell_key(floori(x0 / CELL), floori(y0 / CELL))
	for p in _grid(x0, y0, float(GRASS_QUALITY[quality].step), 9.0):
		var i := _px(p[0], p[1])
		# grass, or the fading edge of a road's paint (R paved, B a dirt road's earth): short grass up to the road
		if i < 0 or land[i + 1] >= 40 or land[i + 3] >= 30:
			continue
		var paint := maxi(land[i], land[i + 2])
		if paint >= 110:
			continue
		var pos := Vector2(p[0], p[1])
		var area := _area_at(key, pos)
		if area == "pitch" or map.inside_building(pos) or not _clear_of_road(p[0], p[1], GRASS_REACH):
			continue
		var lush := vnoise(p[0], p[1], 40.0, 11.0)
		var dry := vnoise(p[0], p[1], 70.0, 31.0)
		var mown := area == "park" or land[i] > 0 # gardens and yards are painted R 25 (or more)
		var tall := 0.72 + lush * 0.55 + hash2(p[0], p[1], 12.0) * 0.15
		var verge := _near_road(i)
		if paint >= 40: # right at the road
			mown = false
			tall = 0.18 + 0.1 * hash2(p[0], p[1], 16.0)
		elif verge > 0.0: # by a road: shorter towards the edge
			mown = false
			tall = lerpf(tall, 0.3, verge)
		elif mown:
			tall = 0.25
		var wide := 1.0 + hash2(p[0], p[1], 15.0) * 0.25
		xfs.append(_place(p[0], p[1], hash2(p[0], p[1], 13.0) * TAU, Vector3(wide, tall, wide), -0.02))
		var t := 0.9 + hash2(p[0], p[1], 14.0) * 0.2
		cols.append(Color(t, t, t * 0.95, 0.08 if mown else clampf(dry * 1.1 - 0.4, 0.0, 0.5)))
	_commit_patches(cell, "GrassPatch", xfs, cols, grass_mat)

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
		var s := 1.2 + hash2(p[0], p[1], 22.0) * 0.9 # over the meadow grass
		xfs.append(_place(p[0], p[1], hash2(p[0], p[1], 23.0) * TAU, Vector3(s, s * (0.9 + hash2(p[0], p[1], 24.0) * 0.5), s), -0.02))
		cols.append(FLOWER_COLOURS[pick % FLOWER_COLOURS.size()])
	_commit(cell, "Flower", xfs, cols, RADIUS - 40.0)

## Thickets on the scrub (forest floor at about 40% in the land map), a few lone bushes on the grass.
func _plant_bushes(cell: Node3D, x0: float, y0: float) -> void:
	var xfs := []
	var cols := []
	for p in _grid(x0, y0, BUSH_STEP, 25.0):
		var i := _px(p[0], p[1])
		if i < 0 or land[i] > 40 or land[i + 1] > 40 or land[i + 2] > 80:
			continue
		var a := land[i + 3]
		var chance := 0.0
		if a >= 80 and a <= 170:
			chance = 0.55 # scrub
		elif a < 30:
			chance = 0.035 * vnoise(p[0], p[1], 60.0, 26.0) * 3.0 # lone bushes, more in some places
		if chance <= 0.0 or float(p[2]) > chance:
			continue
		if map.inside_building(Vector2(p[0], p[1])) or not _clear_of_road(p[0], p[1], 1.4):
			continue
		var s := 0.7 + hash2(p[0], p[1], 27.0) * 0.9
		xfs.append(_place(p[0], p[1], hash2(p[0], p[1], 28.0) * TAU, Vector3(s, s * (0.8 + hash2(p[0], p[1], 29.0) * 0.4), s), -0.1))
		var t := 0.4 + hash2(p[0], p[1], 30.0) * 0.3
		cols.append(Color(t * 0.85, t, t * 0.7))
	_commit(cell, "BushCluster", xfs, cols, RADIUS + 40.0)
