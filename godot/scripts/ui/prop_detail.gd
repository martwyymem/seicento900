## Gives the Blender prop kits (furniture, town, roadside, landmarks) surface detail: swaps each flat
## StandardMaterial3D that names a real material (concrete, wood, steel, brick, stone, roof tiles, rubber,
## plaster, straw...) for a ShaderMaterial running shaders/prop_detail.gdshader. The colour, roughness and
## metalness come from the old material, and its resource_name is kept (town_builder finds surfaces by it).
## Lit, see-through, emissive and per-car-tinted materials (Paint, Lamp, Banner, Glass, Signal*...) are left alone.
## WorldAssets._load_model calls upgrade() for every model it loads.
extends RefCounted

const SHADER := preload("res://shaders/prop_detail.gdshader")

## material name -> the shader's `kind`
const KINDS := {
	"Concrete": 1, "ConcreteTrim": 1,
	"Wood": 2, "Teak": 2, "Timber": 2,
	"Steel": 3, "SteelPaint": 3,
	"Stone": 4, "Slate": 6,
	"Brick": 5,
	"Roof": 6, "Shingle": 6,
	"Rubber": 7,
	"White": 8, "Plaster": 8, "Trim": 8, "Red": 8, "Orange": 8, "SignBlue": 8, "Dark": 8,
	"Straw": 9,
	"Copper": 10,
}

static var _noise: NoiseTexture2D
static var _cache := {} ## source material -> ShaderMaterial

static func grain() -> NoiseTexture2D:
	if _noise == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.seed = 3
		n.frequency = 0.018
		n.fractal_octaves = 6
		_noise = NoiseTexture2D.new()
		_noise.noise = n
		_noise.seamless = true
		_noise.generate_mipmaps = true
		_noise.width = 512
		_noise.height = 512
		_noise.normalize = true
	return _noise

## Upgrade every mesh surface under `root` in place (the meshes are the loaded resources, so each is done once).
static func upgrade(root: Node) -> void:
	if root == null:
		return
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var m := mesh.surface_get_material(i) as StandardMaterial3D
			if m == null:
				continue
			var up := _upgraded(m)
			if up != null:
				mesh.surface_set_material(i, up)

static func _upgraded(m: StandardMaterial3D) -> ShaderMaterial:
	if _cache.has(m):
		return _cache[m]
	var kind: int = KINDS.get(m.resource_name, 0)
	if kind == 0 or m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or m.emission_enabled \
			or m.albedo_texture != null or m.cull_mode != BaseMaterial3D.CULL_BACK:
		_cache[m] = null
		return null
	var sm := ShaderMaterial.new()
	sm.shader = SHADER
	sm.resource_name = m.resource_name
	sm.set_shader_parameter("grain", grain())
	sm.set_shader_parameter("base_color", m.albedo_color)
	sm.set_shader_parameter("base_roughness", m.roughness)
	sm.set_shader_parameter("base_metallic", m.metallic)
	sm.set_shader_parameter("use_vertex_color", m.vertex_color_use_as_albedo)
	sm.set_shader_parameter("kind", kind)
	_cache[m] = sm
	return sm
