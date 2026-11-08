class_name SurfaceTextures
extends RefCounted
## The baked surface detail (tools/build_surface_textures.py) that the road, pavement and ground shaders layer over their
## procedural patterns: `surf_micro` (aggregate, 1 m) and `surf_macro` (cracks, stains and clouds, 4 m).

const MICRO := "res://textures/surfaces/surface_micro.png"
const MACRO := "res://textures/surfaces/surface_macro.png"

static var _micro: Texture2D
static var _macro: Texture2D

static func apply(mat: ShaderMaterial) -> void:
	if _micro == null and ResourceLoader.exists(MICRO):
		_micro = load(MICRO)
	if _macro == null and ResourceLoader.exists(MACRO):
		_macro = load(MACRO)
	if _micro:
		mat.set_shader_parameter("surf_micro", _micro)
	if _macro:
		mat.set_shader_parameter("surf_macro", _macro)
