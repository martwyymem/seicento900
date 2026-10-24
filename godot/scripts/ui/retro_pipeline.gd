## Manages retro and nostalgia post-processing shader modes (Pillar 2).
## Controls the ShaderMaterial applied to full-screen or viewport TextureRects.
class_name RetroPipeline
extends RefCounted

const MODE_NAMES: Array[String] = [
	"Modern Clean",
	"PS1 / Retro 90s",
	"NFS Most Wanted (2005)",
	"GTA San Andreas (2004)",
	"NFS Carbon (2006)",
	"Colin McRae Rally 2.0",
	"Forza Horizon 1"
]

const SHADER: Shader = preload("res://shaders/retro_postprocess.gdshader")

var material: ShaderMaterial
var current_mode: int = 0
var _time: float = 0.0
var _target_view: TextureRect = null

func _init() -> void:
	material = ShaderMaterial.new()
	material.shader = SHADER
	set_mode(0)

## Set the active retro post-processing mode by index (0..6).
func set_mode(mode: int) -> void:
	current_mode = clampi(mode, 0, MODE_NAMES.size() - 1)
	if material:
		material.set_shader_parameter("retro_mode", current_mode)

## Cycle forward to the next retro post-processing mode.
func cycle_mode() -> int:
	var next := (current_mode + 1) % MODE_NAMES.size()
	set_mode(next)
	return current_mode

## Attach the post-processing material to the target TextureRect.
func apply_to_texture_rect(view: TextureRect) -> void:
	_target_view = view
	if is_instance_valid(view):
		view.material = material

## Update elapsed time for animated effects like summer heat haze distortion.
func update_time(dt: float) -> void:
	_time += dt
	if material:
		material.set_shader_parameter("time", _time)

## Returns the human-readable display name for the current or specified mode.
func get_mode_name(mode: int = -1) -> String:
	var idx := current_mode if mode < 0 else mode
	if idx >= 0 and idx < MODE_NAMES.size():
		return MODE_NAMES[idx]
	return ""
