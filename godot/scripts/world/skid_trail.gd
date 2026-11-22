## Rubber laid by the open-world car's rear tyres in a slide: a ring of flat quads in one MultiMesh (the races keep
## their own ring in RaceWorld, the same look), darker the harder the slide, following the ground's slope. The
## oldest marks are reused once CAPACITY run out, so it never allocates while driving.
class_name SkidTrail
extends MultiMeshInstance3D

const CAPACITY := 2400 ## quads kept (two per step, so about 1.4 km of a two-wheel trail)
const WIDTH := 0.24 ## m, one tyre's mark
const STEP := 0.6 ## m driven between marks
const LIFT := 0.025 ## m over the road, clear of z-fighting
const COLOUR := Color(0.02, 0.02, 0.022, 0.78)

var _next := 0
var _used := 0
var _has_last := false
var _last_l := Vector3.ZERO
var _last_r := Vector3.ZERO

func _init() -> void:
	name = "SkidTrail"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var quad := PlaneMesh.new()
	quad.size = Vector2(WIDTH, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color.WHITE
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = -1
	quad.material = mat
	mm.mesh = quad
	mm.instance_count = CAPACITY
	mm.visible_instance_count = 0
	multimesh = mm

## The rear tyres' contact points (world) this frame, sliding this hard (0..1).
func lay(left: Vector3, right: Vector3, k: float) -> void:
	if not _has_last:
		_last_l = left
		_last_r = right
		_has_last = true
		return
	var d := left.distance_to(_last_l)
	if d < STEP:
		return
	if d > 5.0: # teleported or reset: start a new trail
		_last_l = left
		_last_r = right
		return
	var col := Color(COLOUR, COLOUR.a * clampf(0.45 + 0.55 * k, 0.0, 1.0))
	_put(_last_l, left, col)
	_put(_last_r, right, col)
	_last_l = left
	_last_r = right

## The tyres stopped sliding: the next mark starts a new trail rather than bridging the gap.
func lift() -> void:
	_has_last = false

func clear() -> void:
	_has_last = false
	_next = 0
	_used = 0
	multimesh.visible_instance_count = 0

func _put(a: Vector3, b: Vector3, col: Color) -> void:
	var seg := b - a
	var along := seg.normalized()
	var right := Vector3(along.z, 0.0, -along.x).normalized()
	var up := along.cross(right).normalized()
	var xf := Transform3D(Basis(right, up, seg), (a + b) * 0.5 + Vector3.UP * LIFT)
	multimesh.set_instance_transform(_next, xf)
	multimesh.set_instance_color(_next, col)
	_next = (_next + 1) % CAPACITY
	if _used < CAPACITY:
		_used += 1
		multimesh.visible_instance_count = _used
