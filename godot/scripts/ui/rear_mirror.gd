class_name RearMirror
extends Control
## Gran Turismo style rear-view mirror: a small SubViewport sharing the main World3D, with a camera on the
## player's roof looking backwards, shown top-centre through a rounded, flipped, bezelled TextureRect.

const SIZE_PX := Vector2i(512, 128)
const ROOF := Vector3(0.0, 1.25, 2.9) ## in the car's frame (front is -Z): just past the tail, so the view behind
## is clear of the cabin and roll cage, as in Gran Turismo

var _vp: SubViewport
var _cam: Camera3D
var _rect: TextureRect
var _target: Callable ## -> Node3D of the player's car, or null when no mirror should show

## Where the mirror on screen ends (global canvas y, px; 0 while none shows): the HUDs lay their top centre out
## below it (RaceHud._layout, OpenWorldHud._layout) so the chain, the pace notes and the drift meter stay clear.
static var screen_bottom := 0.0

func setup(world: World3D, target: Callable) -> void:
	_target = target
	_vp = SubViewport.new()
	_vp.size = SIZE_PX
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.world_3d = world
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.handle_input_locally = false
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.fov = 62.0
	_cam.near = 0.5
	_cam.far = 1500.0
	_vp.add_child(_cam)
	_rect = TextureRect.new()
	_rect.texture = _vp.get_texture()
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/rear_mirror.gdshader")
	_rect.material = mat
	add_child(_rect)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_priority = 1000
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(_delta: float) -> void:
	var car: Node3D = _target.call() if _target.is_valid() else null
	var show_it := GfxFx.rear_mirror and is_instance_valid(car) and car.is_inside_tree()
	if show_it != visible:
		visible = show_it
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if show_it else SubViewport.UPDATE_DISABLED
		if not show_it:
			screen_bottom = 0.0
	if not show_it:
		return
	_cam.global_transform = car.global_transform * Transform3D(Basis(Vector3.UP, PI), ROOF)
	var screen := get_viewport_rect().size
	var w := clampf(screen.x * 0.34, 240.0, 560.0)
	var h := w * float(SIZE_PX.y) / float(SIZE_PX.x)
	_rect.size = Vector2(w, h)
	_rect.position = Vector2((screen.x - w) * 0.5, 10.0)
	screen_bottom = _rect.get_global_rect().end.y
	(_rect.material as ShaderMaterial).set_shader_parameter("aspect", Vector2(w / h, 1.0))

func _exit_tree() -> void:
	if visible:
		screen_bottom = 0.0
