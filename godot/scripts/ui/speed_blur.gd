class_name SpeedBlur
extends CanvasLayer
## Fake motion blur: a full-screen radial blur beneath the HUD, strength from GfxFx.blur (rises above ~80 km/h).

var _rect := ColorRect.new()
var _mat := ShaderMaterial.new()

func _ready() -> void:
	layer = -1
	_mat.shader = load("res://shaders/speed_blur.gdshader")
	_rect.material = _mat
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.visible = false
	add_child(_rect)

func _process(_delta: float) -> void:
	var on := GfxFx.speed_blur and GfxFx.blur > 0.01
	_rect.visible = on
	if on:
		_mat.set_shader_parameter("strength", GfxFx.blur)
