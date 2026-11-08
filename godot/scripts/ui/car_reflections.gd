## A reflection probe that follows the player's car, so glossy paint, glass and chrome mirror the street round it
## (houses, lit windows, lamps, other cars, the grandstands) instead of only the sky. It re-renders (Godot's
## UPDATE_ONCE: a cube face a frame) when the car has moved RESNAP metres or MAX_AGE seconds have passed (the light
## changes with the hour). The followed car is moved to its own render layer so the probe, which sits inside it,
## does not see it. Used by the open world and the races on the presets that afford it (GraphicsPresets
## car_reflections).
class_name CarReflections
extends ReflectionProbe

const CAR_LAYER := 1 << 19 ## render layer 20: the followed car, left out of its own reflections
const RESNAP := 14.0 ## m the car moves before the reflections are drawn again
const MAX_AGE := 5.0 ## s between redraws when the car stands still (the hour, lamps switching on)

var target: Node3D
var _last := Vector3.INF
var _age := 0.0
var _nudge := 0.01

func _init() -> void:
	name = "CarReflections"
	update_mode = UPDATE_ONCE
	size = Vector3(140.0, 60.0, 140.0)
	max_distance = 260.0
	ambient_mode = AMBIENT_DISABLED # the fill stays the sky's
	enable_shadows = false
	box_projection = false
	interior = false
	intensity = 1.0
	blend_distance = 30.0
	mesh_lod_threshold = 4.0
	cull_mask = 0xFFFFF & ~CAR_LAYER

## Follows car (null stops). The car before it goes back to the ordinary render layer.
func follow(car: Node3D) -> void:
	if car == target:
		return
	if is_instance_valid(target):
		_set_layers(target, 1)
	target = car
	_last = Vector3.INF
	if car:
		_set_layers(car, CAR_LAYER)

func _process(delta: float) -> void:
	if not is_instance_valid(target) or not visible:
		return
	_age += delta
	var p := target.global_position + Vector3.UP * 1.2
	if p.distance_to(_last) < RESNAP and _age < MAX_AGE:
		return
	# a move is what marks an UPDATE_ONCE probe for a redraw; standing still, a centimetre's nudge does it
	if p.distance_to(_last) < 0.005:
		_nudge = -_nudge
		p.x += _nudge
	_set_layers(target, CAR_LAYER) # parts fitted since (mods, a new body) join the hidden layer too
	global_position = p
	_last = p
	_age = 0.0

static func _set_layers(node: Node, layers: int) -> void:
	if node is VisualInstance3D and not node is Light3D and not node is ReflectionProbe and not node is Decal:
		(node as VisualInstance3D).layers = layers
	for c in node.get_children():
		_set_layers(c, layers)
