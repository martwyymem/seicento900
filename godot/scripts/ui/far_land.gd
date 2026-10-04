## The land round a circuit out to 40 km (data/tracks/<key>_far.json, from tools/fetch_horizon.py): the hills,
## mountains and sea on the horizon, past the circuit's own terrain, with the woods, towns, fields and lakes
## where the land cover ("cover", from tools/fetch_landcover.py) has them. far_land.gdshader draws it behind the
## whole scene, so it fills the sky line without being clipped by the camera's far plane. Woods stand up from
## it by the height of their trees so even a flat horizon is broken by tree lines; towns, fields and rock
## colour the rest. race_world.gd builds one per circuit and drives its haze with the weather.
extends RefCounted

const SHADER := preload("res://shaders/far_land.gdshader")
const TREE_HEIGHT := 17.0 ## metres a wood stands over the ground
const SINK := 60.0 ## metres the land is sunk under the circuit's own terrain, fading out over SINK_REACH beyond it
const SINK_REACH := 3000.0
const SKYLINE_FROM := 400.0 ## metres beyond the circuit's own terrain where the towns' blocks begin (surroundings.gd builds nearer)
const MAX_BLOCKS := 6000
static var BLOCK_UVS := _block_uvs()
const SEA := Color("#2a4a58")
const ROCK := Color("#7d786e")
const MEADOW := Color("#4f6236")
const WOOD_BROADLEAF := Color("#2f4524")
const WOOD_CONIFER := Color("#223a26")
const TOWN := Color("#837d74")
const TOWN_WARM := Color("#94806e") ## tiled roofs and pale walls of the south
const WETLAND := Color("#465a3c")
const SNOW := Color("#e8ecef")

var material: ShaderMaterial

## sky.gdshader's uniforms that make up its horizon, which far_land.gdshader matches its haze to
const SKY_UNIFORMS := ["horizon_color", "glow_color", "glow_amount", "sun_dir", "sky_energy", "hdri_a", "hdri_b",
	"hdri_o", "hdri_rot_a", "hdri_rot_b", "hdri_rot_o", "hdri_gain_a", "hdri_gain_b", "hdri_gain_o", "hdri_ab",
	"hdri_mix", "hdri_o_mix", "hdri_clamp"]

## Adds the far land under parent; false where the circuit has no data.
func build(world: Node3D, parent: Node3D) -> bool:
	var track: Track = world.track
	var path := "res://data/tracks/%s_far.json" % track.cfg.key
	if not FileAccess.file_exists(path) or typeof(track.grid) != TYPE_DICTIONARY:
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var xs: Array = data.xs
	var zs: Array = data.zs
	var hs: Array = data.h
	var sea: Array = data.sea
	var cover: String = data.get("cover", "")
	var nx := xs.size()
	var nz := zs.size()
	var c: Vector2 = world.world_center
	var base: float = world.elevation_base
	# the circuit's own terrain is drawn in front of this land, which must stay below it: its coarse heights and
	# tree tops stand tens of metres over the circuit, so near the circuit it is sunk and rises back to level
	var g: Dictionary = track.grid
	var step := float(g.step)
	var own := Rect2(float(g.x0), float(g.y0), int(g.nx) * step, int(g.ny) * step)
	var city: bool = track.cfg.theme == "city"
	var south: bool = track.cfg.key in ["monaco", "monza"]
	var forest_share := clampf(0.3 + 0.15 * track.cfg.tree_density, 0.2, 0.55) * (0.6 if track.cfg.theme == "oval" else 1.0)
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.00035
	noise.fractal_octaves = 4
	var towns := FastNoiseLite.new()
	towns.seed = 31
	towns.noise_type = FastNoiseLite.TYPE_CELLULAR
	towns.frequency = 0.00045
	towns.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	verts.resize(nx * nz)
	colors.resize(nx * nz)
	uvs.resize(nx * nz)
	var ground := PackedFloat32Array() # the ground under each town point, where _skyline() stands its buildings
	ground.resize(nx * nz)
	var built_at := PackedByteArray()
	built_at.resize(nx * nz)
	var outs := PackedFloat32Array() # how far each point is beyond the circuit's own terrain
	outs.resize(nx * nz)
	for j in nz:
		for i in nx:
			var k := j * nx + i
			var x := float(xs[i])
			var z := float(zs[j])
			var h := float(hs[k])
			var y: float = (h - base) * world.ALTITUDE_SCALE - 1.2
			var out := Vector2(maxf(maxf(own.position.x - x, x - own.end.x), 0.0), maxf(maxf(own.position.y - z, z - own.end.y), 0.0)).length()
			var sink := SINK * (1.0 - smoothstep(0.0, SINK_REACH, out))
			var col := MEADOW
			var farmland := 1.0
			var water := 0.0
			var built := 0.0
			# open sea, though not the polders below sea level that the land cover has as dry land
			if int(sea[k]) == 1 and (cover.is_empty() or cover[k] == "w"):
				col = SEA
				farmland = 0.0
				water = 1.0
				y = (0.0 - base) * world.ALTITUDE_SCALE - 0.5
			elif not cover.is_empty():
				# the real land cover (ESA WorldCover, tools/fetch_landcover.py)
				match cover[k]:
					"f":
						var conifer := clampf(track.cfg.tree_conifer + (h - 500.0) / 1500.0, 0.0, 1.0)
						col = WOOD_BROADLEAF.lerp(WOOD_CONIFER, conifer)
						farmland = 0.0
						y += TREE_HEIGHT * (0.8 + 0.4 * absf(noise.get_noise_2d(x * 7.0, z * 7.0)))
					"t":
						col = TOWN_WARM if south else TOWN
						farmland = 0.0
						built = 1.0
						y += 6.0
					"g":
						farmland = 0.25
					"m":
						col = WETLAND
						farmland = 0.0
					"r":
						col = ROCK
						farmland = 0.0
					"s":
						col = SNOW
						farmland = 0.0
					"w": # a lake: the elevation model already has its surface
						col = SEA
						farmland = 0.0
						water = 1.0
			else:
				# steep ground and high ground are wooded, then rock above the tree line
				var slope := _slope(xs, zs, hs, i, j)
				var wild := noise.get_noise_2d(x, z) * 0.5 + 0.5 + slope * 1.6 + smoothstep(300.0, 900.0, h) * 0.25
				var town := 1.0 - clampf(towns.get_noise_2d(x, z) * 1.6 + 0.9, 0.0, 1.0)
				# towns gather on the gentle low ground near the coast and the circuits of the city theme
				var urban := town > 0.55 and slope < 0.12 and h < 900.0
				var near_city := city and Vector2(x - c.x, z - c.y).length() < 4500.0 and h < 500.0
				if h > 2100.0 + noise.get_noise_2d(z, x) * 250.0:
					col = ROCK
					farmland = 0.0
				elif urban or near_city:
					col = TOWN_WARM if south else TOWN
					farmland = 0.0
					built = 1.0
					y += 6.0
				elif wild > 1.0 - forest_share:
					var conifer := clampf(track.cfg.tree_conifer + (h - 500.0) / 1500.0, 0.0, 1.0)
					col = WOOD_BROADLEAF.lerp(WOOD_CONIFER, conifer)
					farmland = 0.0
					y += TREE_HEIGHT * (0.8 + 0.4 * absf(noise.get_noise_2d(x * 7.0, z * 7.0)))
			if water < 1.0:
				y -= sink
			ground[k] = y - 6.0 * built # the land as drawn, sunk near the circuit, so buildings stand on what is seen
			built_at[k] = int(built > 0.5 and out > SKYLINE_FROM)
			outs[k] = out
			var lin := col.srgb_to_linear()
			lin.a = farmland
			verts[k] = Vector3(x - c.x, y, z - c.y)
			colors[k] = lin
			uvs[k] = Vector2(water, built)
	# no hole under the circuit's own terrain: that is drawn in front wherever it is, and where the camera's
	# far plane cuts it off (looking across the circuit from up high) the far land shows instead of the sky.
	# Wound clockwise seen from above, so the faces (and the normals generate_normals gives them) point up.
	var indices := PackedInt32Array()
	for j in nz - 1:
		for i in nx - 1:
			var a := j * nx + i
			indices.append_array(PackedInt32Array([a, a + 1, a + nx, a + 1, a + nx + 1, a + nx]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var st := SurfaceTool.new()
	st.create_from_arrays(arrays)
	st.generate_normals()
	var mesh := st.commit()
	var blocks := _skyline(xs, zs, ground, built_at, outs, data.get("places", []), c, south, track.cfg.key.hash())
	if not blocks.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, blocks)
	material = ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("grain", world.noise_texture("grain"))
	var inst := MeshInstance3D.new()
	inst.name = "FarLand"
	inst.mesh = mesh
	inst.material_override = material
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	parent.add_child(inst)
	return true

## The towns' buildings as blocks standing on the land, so a flat horizon has a skyline: low blocks over the
## built-up land, coarser with distance where single houses could not be seen anyway, and the towers of each
## city centre ("places", from tools/fetch_places.py) round its centre, as many and as tall as the city is big.
## Returns mesh arrays (empty where there are no towns).
static func _skyline(xs: Array, zs: Array, ground: PackedFloat32Array, built_at: PackedByteArray,
		outs: PackedFloat32Array, places: Array, c: Vector2, south: bool, seed_value: int) -> Array:
	var nx := xs.size()
	var nz := zs.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var count := 0
	var town: Color = TOWN_WARM if south else TOWN
	for j in nz:
		for i in nx:
			var k := j * nx + i
			if built_at[k] == 0:
				continue
			var x := float(xs[i])
			var z := float(zs[j])
			var spacing := 100.0 + Vector2(x - c.x, z - c.y).length() * 0.02 # a block every so many metres
			var w := _span(xs, i)
			var l := _span(zs, j)
			var n := mini(int(w * l / (spacing * spacing) * 0.5 + rng.randf()), 24) # a block on a share of the small cells
			for b in n:
				if count >= MAX_BLOCKS:
					return _arrays(verts, normals, colors, uvs)
				var size := spacing * rng.randf_range(0.35, 0.7)
				_block(verts, normals, colors, uvs, Vector3(x + rng.randf_range(-0.5, 0.5) * w - c.x, ground[k] - 10.0,
					z + rng.randf_range(-0.5, 0.5) * l - c.y), size * rng.randf_range(0.6, 1.0), size,
					lerpf(7.0, 22.0, rng.randf() * rng.randf()) + 10.0, rng.randf() * TAU,
					town.lerp(Color("#d9d4c8"), rng.randf() * 0.6).srgb_to_linear())
				count += 1
	for p in places:
		var pop := float(p[2])
		var towers := mini(int((pop - 20000.0) / 22000.0), 70)
		var reach := clampf(500.0 * sqrt(pop / 100000.0), 400.0, 2600.0)
		var tallest := clampf(30.0 + 75.0 * log(pop / 15000.0) / log(10.0), 35.0, 240.0)
		for t in towers:
			var r := reach * pow(rng.randf(), 1.4)
			var at := Vector2(float(p[0]), float(p[1])) + Vector2.from_angle(rng.randf() * TAU) * r
			var i := _nearest(xs, at.x)
			var j := _nearest(zs, at.y)
			var k := j * nx + i
			if outs[k] < SKYLINE_FROM or count >= MAX_BLOCKS + 600:
				continue
			# tallest at the very centre, stepping down outwards
			var height := lerpf(28.0, tallest, pow(rng.randf(), 1.8) * (1.0 - 0.6 * r / reach))
			var size := rng.randf_range(24.0, 48.0) + Vector2(at.x - c.x, at.y - c.y).length() * 0.002
			_block(verts, normals, colors, uvs, Vector3(at.x - c.x, ground[k] - 10.0, at.y - c.y),
				size * rng.randf_range(0.7, 1.0), size, height + 10.0, rng.randf() * TAU,
				Color("#7f8e9c").lerp(Color("#cfd0c9"), rng.randf()).srgb_to_linear())
			count += 1
	return _arrays(verts, normals, colors, uvs)

## The index of the grid line nearest v.
static func _nearest(axis: Array, v: float) -> int:
	var i := clampi(axis.bsearch(v), 1, axis.size() - 1)
	return i - 1 if v - float(axis[i - 1]) < float(axis[i]) - v else i

## The spacing of the grid at index i: half the gaps to its neighbours on either side.
static func _span(v: Array, i: int) -> float:
	var a := float(v[maxi(i - 1, 0)])
	var b := float(v[mini(i + 1, v.size() - 1)])
	return (b - a) / (2.0 if i > 0 and i < v.size() - 1 else 1.0)

## A block's four walls and roof (its floor is never seen), turned by yaw about its foot.
static func _block(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray,
		uvs: PackedVector2Array, foot: Vector3, sx: float, sz: float, height: float, yaw: float, col: Color) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var hx := basis.x * sx * 0.5
	var hz := basis.z * sz * 0.5
	var up := Vector3.UP * height
	var c0 := foot - hx - hz
	var c1 := foot + hx - hz
	var c2 := foot + hx + hz
	var c3 := foot - hx + hz
	var t0 := c0 + up
	var t1 := c1 + up
	var t2 := c2 + up
	var t3 := c3 + up
	# four walls round the corners the other way (each faces out), wound clockwise from outside as the land
	# is, then the roof; its floor is never seen
	verts.append_array(PackedVector3Array([c0, t0, c3, c3, t0, t3, c3, t3, c2, c2, t3, t2,
		c2, t2, c1, c1, t2, t1, c1, t1, c0, c0, t1, t0, t0, t1, t3, t1, t2, t3]))
	var w := -basis.x
	var n := basis.z
	normals.append_array(PackedVector3Array([w, w, w, w, w, w, n, n, n, n, n, n,
		-w, -w, -w, -w, -w, -w, -n, -n, -n, -n, -n, -n, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP]))
	var roof := col.lerp(Color(0.18, 0.17, 0.16), 0.25)
	roof.a = 0.0
	col.a = 0.0
	var start := colors.size()
	colors.resize(start + 30)
	_fill(colors, start, start + 24, col)
	_fill(colors, start + 24, start + 30, roof)
	uvs.append_array(BLOCK_UVS)

static func _fill(a: PackedColorArray, from: int, to: int, col: Color) -> void:
	for i in range(from, to):
		a[i] = col

static func _arrays(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray,
		uvs: PackedVector2Array) -> Array:
	if verts.is_empty():
		return []
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	return arrays

static func _block_uvs() -> PackedVector2Array:
	var uv := PackedVector2Array()
	uv.resize(30)
	uv.fill(Vector2(0.0, 1.0)) # UV.y 1: town, lit at night
	return uv

## Rise over run at grid point (i, j), from its neighbours.
static func _slope(xs: Array, zs: Array, hs: Array, i: int, j: int) -> float:
	var nx := xs.size()
	var i0 := maxi(i - 1, 0)
	var i1 := mini(i + 1, nx - 1)
	var j0 := maxi(j - 1, 0)
	var j1 := mini(j + 1, zs.size() - 1)
	var dx := (float(hs[j * nx + i1]) - float(hs[j * nx + i0])) / maxf(float(xs[i1]) - float(xs[i0]), 1.0)
	var dz := (float(hs[j1 * nx + i]) - float(hs[j0 * nx + i])) / maxf(float(zs[j1]) - float(zs[j0]), 1.0)
	return sqrt(dx * dx + dz * dz)

## Matches the haze to the sky and the scene's fog; race_world.gd calls it whenever the atmosphere changes.
func match_sky(sky: ShaderMaterial, env: Environment) -> void:
	for u in SKY_UNIFORMS:
		var v = sky.get_shader_parameter(u)
		if v != null:
			material.set_shader_parameter(u, v)
	material.set_shader_parameter("haze_color", env.fog_light_color)
	material.set_shader_parameter("haze_density", env.fog_density)
	material.set_shader_parameter("aerial", env.fog_aerial_perspective)
	material.set_shader_parameter("mist", env.volumetric_fog_density if env.volumetric_fog_enabled else 0.0)
