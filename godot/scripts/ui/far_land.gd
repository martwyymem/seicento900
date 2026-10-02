## The land round a circuit out to 40 km (data/tracks/<key>_far.json, from tools/fetch_horizon.py): the hills,
## mountains and sea on the horizon, past the circuit's own terrain. far_land.gdshader draws it behind the
## whole scene, so it fills the sky line without being clipped by the camera's far plane. Woods stand up from
## it by the height of their trees so even a flat horizon is broken by tree lines; towns, fields and rock
## colour the rest. race_world.gd builds one per circuit and drives its haze with the weather.
extends RefCounted

const SHADER := preload("res://shaders/far_land.gdshader")
const TREE_HEIGHT := 17.0 ## metres a wood stands over the ground
const SEA := Color("#2a4a58")
const ROCK := Color("#7d786e")
const MEADOW := Color("#4f6236")
const WOOD_BROADLEAF := Color("#2f4524")
const WOOD_CONIFER := Color("#223a26")
const TOWN := Color("#9b958a")
const TOWN_WARM := Color("#b39a84") ## tiled roofs and pale walls of the south

var material: ShaderMaterial

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
	var nx := xs.size()
	var nz := zs.size()
	# the circuit's own terrain covers its elevation grid: leave a hole there, overlapping it by a cell
	var g: Dictionary = track.grid
	var step := float(g.step)
	var hole := Rect2(float(g.x0) + step, float(g.y0) + step, (int(g.nx) - 3) * step, (int(g.ny) - 3) * step)
	var c: Vector2 = world.world_center
	var base: float = world.elevation_base
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
	for j in nz:
		for i in nx:
			var k := j * nx + i
			var x := float(xs[i])
			var z := float(zs[j])
			var h := float(hs[k])
			var y := (h - base) * world.ALTITUDE_SCALE - 1.2
			var col := MEADOW
			var farmland := 1.0
			var water := 0.0
			if int(sea[k]) == 1:
				col = SEA
				farmland = 0.0
				water = 1.0
				y = (0.0 - base) * world.ALTITUDE_SCALE - 0.5
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
					y += 6.0
				elif wild > 1.0 - forest_share:
					var conifer := clampf(track.cfg.tree_conifer + (h - 500.0) / 1500.0, 0.0, 1.0)
					col = WOOD_BROADLEAF.lerp(WOOD_CONIFER, conifer)
					farmland = 0.0
					y += TREE_HEIGHT * (0.8 + 0.4 * absf(noise.get_noise_2d(x * 7.0, z * 7.0)))
			var lin := col.srgb_to_linear()
			lin.a = farmland
			verts[k] = Vector3(x - c.x, y, z - c.y)
			colors[k] = lin
			uvs[k] = Vector2(water, 0.0)
	var indices := PackedInt32Array()
	for j in nz - 1:
		for i in nx - 1:
			if hole.has_point(Vector2(xs[i], zs[j])) and hole.has_point(Vector2(xs[i + 1], zs[j + 1])):
				continue
			var a := j * nx + i
			indices.append_array(PackedInt32Array([a, a + nx, a + 1, a + 1, a + nx, a + nx + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var st := SurfaceTool.new()
	st.create_from_arrays(arrays)
	st.generate_normals()
	material = ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("grain", world.noise_texture("grain"))
	var inst := MeshInstance3D.new()
	inst.name = "FarLand"
	inst.mesh = st.commit()
	inst.material_override = material
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	parent.add_child(inst)
	return true

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
