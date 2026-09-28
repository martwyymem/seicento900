## 3D Fiat Seicento Sporting Cup race car.
## The body is one merged mesh shared by every car (paint, stripes and tail lights are per-car materials),
## so a car costs about a dozen draw calls and a single shadow-casting surface. Wheels steer and spin
## from the physics model, the sprung body rolls and pitches, and lights follow braking and nightfall.
extends Node3D

const WHEEL_RADIUS := 0.33
const WHEELBASE := 2.04
const WHEEL_SPOTS := [Vector3(-0.78, WHEEL_RADIUS, -1.02), Vector3(0.78, WHEEL_RADIUS, -1.02),
	Vector3(-0.78, WHEEL_RADIUS, 1.02), Vector3(0.78, WHEEL_RADIUS, 1.02)] ## FL, FR, RL, RR like the physics

static var _shared := {}

var paint_material: StandardMaterial3D
var stripe_material: StandardMaterial3D
var tail_material: StandardMaterial3D
var body_pivot: Node3D
var number_label: Label3D
var stripes_node: MeshInstance3D
var steer_pivots: Array[Node3D] = []
var wheels: Array[Node3D] = []
var car_number := 1:
	set(value):
		car_number = value
		if is_instance_valid(number_label):
			number_label.text = str(car_number)
var is_player := false

## Smoothed presentation state (radians).
var grade_pitch := 0.0
var _roll := 0.0
var _spins := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _tail_energy := -1.0
var _ghost := false

func _ready() -> void:
	var sh := _shared_resources()
	paint_material = StandardMaterial3D.new()
	paint_material.vertex_color_use_as_albedo = true
	paint_material.vertex_color_is_srgb = true
	paint_material.roughness = 0.34
	paint_material.metallic = 0.08
	paint_material.clearcoat_enabled = true
	paint_material.clearcoat = 0.9
	paint_material.clearcoat_roughness = 0.08
	stripe_material = StandardMaterial3D.new()
	stripe_material.roughness = 0.44
	tail_material = StandardMaterial3D.new()
	tail_material.albedo_color = Color("#5a1111")
	tail_material.roughness = 0.35
	tail_material.emission_enabled = true
	tail_material.emission = Color("#ff2211")
	tail_material.emission_energy_multiplier = 0.25

	body_pivot = Node3D.new()
	body_pivot.name = "SuspendedBody"
	add_child(body_pivot)

	var shell := MeshInstance3D.new()
	shell.name = "Shell"
	shell.mesh = sh.shell
	shell.material_override = paint_material
	body_pivot.add_child(shell)

	var details := MeshInstance3D.new()
	details.name = "Details"
	details.mesh = sh.details
	details.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	details.set_surface_override_material(3, tail_material)
	body_pivot.add_child(details)

	stripes_node = MeshInstance3D.new()
	stripes_node.name = "Stripes"
	stripes_node.mesh = sh.stripes
	stripes_node.material_override = stripe_material
	stripes_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body_pivot.add_child(stripes_node)

	for spot in WHEEL_SPOTS:
		var pivot := Node3D.new()
		pivot.position = spot
		add_child(pivot)
		var wheel := MeshInstance3D.new()
		wheel.mesh = sh.wheel
		wheel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(wheel)
		steer_pivots.append(pivot)
		wheels.append(wheel)

	var contact := MeshInstance3D.new()
	contact.name = "ContactShadow"
	contact.mesh = sh.contact
	contact.position.y = 0.025
	contact.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(contact)

	number_label = Label3D.new()
	number_label.name = "RoofNumber"
	number_label.text = str(car_number)
	number_label.font_size = 34
	number_label.outline_size = 8
	number_label.modulate = Color("#202124")
	number_label.position = Vector3(0, 1.262, 0.18)
	number_label.rotation.x = -PI / 2.0
	number_label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body_pivot.add_child(number_label)

func set_paint(color: Color) -> void:
	if not paint_material:
		return
	paint_material.albedo_color = color
	stripe_material.albedo_color = Color.WHITE if color.get_luminance() < 0.42 else Color("#202124")

func set_stripes(enabled: bool) -> void:
	if is_instance_valid(stripes_node):
		stripes_node.visible = enabled

## Headlight glow is the same for every car, so it lives on the shared material.
static func set_night(night: float) -> void:
	var sh := _shared_resources()
	sh.head.emission_energy_multiplier = 0.05 + 3.2 * night

## Per-frame presentation. curvature is the road curvature under the car (for rail-driven cars).
func sync(car: RaceCar, dt: float, curvature: float, night: float, ghost: bool) -> void:
	var physical: bool = car.control == "free" and car.phys != null
	if physical:
		# the physics model's own sprung-body roll and pitch
		_roll = car.body_roll
		body_pivot.rotation = Vector3(car.body_pitch, 0.0, -_roll)
	else:
		var lat: float = car.v * car.v * curvature
		_roll += (clampf(-lat * 0.006, -0.07, 0.07) - _roll) * minf(1.0, dt * 5.0)
		var accel := -1.0 if car.brake_on else (0.5 if car.throttle > 0.3 else 0.0)
		body_pivot.rotation = Vector3(accel * 0.012, 0.0, -_roll)

	# each wheel turns at its own speed under physics, so lock-ups and wheelspin show
	for i in 4:
		if physical:
			_spins[i] = fmod(_spins[i] - car.phys.w[i] * dt, TAU)
		else:
			_spins[i] = fmod(_spins[i] - car.speed * dt / WHEEL_RADIUS, TAU)
		wheels[i].rotation.x = _spins[i]
	var steer_angle: float = car.steer if car.control == "free" else atan(WHEELBASE * curvature) * 1.4
	steer_pivots[0].rotation.y = -steer_angle
	steer_pivots[1].rotation.y = -steer_angle

	var tail := (2.4 + 1.5 * night) if car.brake_on else (0.25 + 1.4 * night)
	if absf(tail - _tail_energy) > 0.01:
		_tail_energy = tail
		tail_material.emission_energy_multiplier = tail

	if ghost != _ghost:
		_ghost = ghost
		paint_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if ghost else BaseMaterial3D.TRANSPARENCY_DISABLED
		paint_material.albedo_color.a = 0.55 if ghost else 1.0

# ---------------- shared geometry ----------------
static func _shared_resources() -> Dictionary:
	if not _shared.is_empty():
		return _shared
	# Local frame: -Z forward, +X right, +Y up.
	var trim := Color(0.1, 0.1, 0.1)
	var shell := _merge([
		[_box(Vector3(1.54, 0.44, 3.32)), Vector3(0, 0.46, 0.0), 0.0, Color.WHITE], # lower body
		[_box(Vector3(1.48, 0.22, 1.15)), Vector3(0, 0.65, -0.98), 0.0, Color.WHITE], # bonnet and wings
		[_box(Vector3(1.36, 0.52, 1.58)), Vector3(0, 0.98, 0.22), 0.0, Color.WHITE], # upright hatchback cabin
		[_box(Vector3(1.32, 0.08, 0.24)), Vector3(0, 1.25, 0.98), 0.0, trim], # roof spoiler
		[_box(Vector3(1.40, 0.20, 0.16)), Vector3(0, 0.34, -1.68), 0.0, trim], # front bumper / grille
		[_box(Vector3(1.40, 0.18, 0.14)), Vector3(0, 0.33, 1.68), 0.0, trim], # rear bumper
		[_box(Vector3(1.56, 0.08, 3.1)), Vector3(0, 0.25, 0.0), 0.0, trim], # sills
	])
	var glass_parts := _merge([
		[_box(Vector3(1.34, 0.44, 0.08)), Vector3(0, 0.94, -0.58), deg_to_rad(-28.0), Color.WHITE],
		[_box(Vector3(1.30, 0.42, 0.08)), Vector3(0, 0.96, 0.98), deg_to_rad(18.0), Color.WHITE],
		[_box(Vector3(0.04, 0.38, 1.42)), Vector3(-0.69, 0.96, 0.24), 0.0, Color.WHITE],
		[_box(Vector3(0.04, 0.38, 1.42)), Vector3(0.69, 0.96, 0.24), 0.0, Color.WHITE],
	])
	var plate := Color("#f0ede4")
	var bits := _merge([
		[_box(Vector3(0.02, 0.34, 0.44)), Vector3(-0.78, 0.58, 0.15), 0.0, plate], # door number plates
		[_box(Vector3(0.02, 0.34, 0.44)), Vector3(0.78, 0.58, 0.15), 0.0, plate],
		[_box(Vector3(0.10, 0.10, 0.32)), Vector3(-0.46, 0.28, 1.72), 0.0, Color("#4a5054")], # exhaust
	])
	var heads := _merge([
		[_box(Vector3(0.26, 0.14, 0.08)), Vector3(-0.54, 0.58, -1.67), 0.0, Color.WHITE],
		[_box(Vector3(0.26, 0.14, 0.08)), Vector3(0.54, 0.58, -1.67), 0.0, Color.WHITE],
	])
	var tails := _merge([
		[_box(Vector3(0.24, 0.16, 0.08)), Vector3(-0.54, 0.62, 1.67), 0.0, Color.WHITE],
		[_box(Vector3(0.24, 0.16, 0.08)), Vector3(0.54, 0.62, 1.67), 0.0, Color.WHITE],
	])
	var details := ArrayMesh.new()
	for part in [glass_parts, bits, heads, tails]:
		details.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, part.surface_get_arrays(0))

	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color("#0f1316")
	glass.roughness = 0.08
	glass.metallic = 0.6
	var bits_mat := StandardMaterial3D.new()
	bits_mat.vertex_color_use_as_albedo = true
	bits_mat.vertex_color_is_srgb = true
	bits_mat.roughness = 0.55
	var head := StandardMaterial3D.new()
	head.albedo_color = Color("#fffce8")
	head.roughness = 0.1
	head.emission_enabled = true
	head.emission = Color("#fff3d6")
	head.emission_energy_multiplier = 0.05
	details.surface_set_material(0, glass)
	details.surface_set_material(1, bits_mat)
	details.surface_set_material(2, head)

	var stripes := _merge([
		[_box(Vector3(0.14, 0.014, 0.98)), Vector3(-0.16, 0.77, -0.98), 0.0, Color.WHITE],
		[_box(Vector3(0.14, 0.014, 0.98)), Vector3(0.16, 0.77, -0.98), 0.0, Color.WHITE],
		[_box(Vector3(0.14, 0.014, 1.20)), Vector3(-0.16, 1.245, 0.22), 0.0, Color.WHITE],
		[_box(Vector3(0.14, 0.014, 1.20)), Vector3(0.16, 1.245, 0.22), 0.0, Color.WHITE],
	])

	# Wheel: tyre, alloy and a dark hub cross (so the spin reads), axle along X.
	var axle := Basis(Vector3.BACK, PI / 2.0)
	var tyre := CylinderMesh.new()
	tyre.top_radius = WHEEL_RADIUS
	tyre.bottom_radius = WHEEL_RADIUS
	tyre.height = 0.2
	tyre.radial_segments = 20
	tyre.rings = 1
	var rim := CylinderMesh.new()
	rim.top_radius = 0.21
	rim.bottom_radius = 0.21
	rim.height = 0.206
	rim.radial_segments = 16
	rim.rings = 1
	var hub := Color("#2a2d30")
	var wheel := _merge([
		[tyre, Vector3.ZERO, axle, Color("#181a1b")],
		[rim, Vector3.ZERO, axle, Color("#d8dde0")],
		[_box(Vector3(0.214, 0.36, 0.05)), Vector3.ZERO, 0.0, hub],
		[_box(Vector3(0.214, 0.05, 0.36)), Vector3.ZERO, 0.0, hub],
	])
	var wheel_mat := StandardMaterial3D.new()
	wheel_mat.vertex_color_use_as_albedo = true
	wheel_mat.vertex_color_is_srgb = true
	wheel_mat.roughness = 0.6
	wheel_mat.metallic = 0.3
	wheel.surface_set_material(0, wheel_mat)

	# Soft dark ellipse under the car keeps it sitting on the road.
	var contact := PlaneMesh.new()
	contact.size = Vector2(2.1, 3.9)
	var fade := Gradient.new()
	fade.set_color(0, Color(0, 0, 0, 0.6))
	fade.set_color(1, Color(0, 0, 0, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = fade
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	var contact_mat := StandardMaterial3D.new()
	contact_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	contact_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	contact_mat.albedo_texture = tex
	contact_mat.albedo_color = Color.WHITE
	contact.material = contact_mat

	_shared = {"shell": shell, "details": details, "stripes": stripes, "wheel": wheel, "contact": contact, "head": head}
	return _shared

static func _box(size: Vector3) -> BoxMesh:
	var box := BoxMesh.new()
	box.size = size
	return box

## One vertex-coloured surface from [primitive, position, rotation (x angle or Basis), colour] parts.
static func _merge(parts: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for part in parts:
		var basis: Basis = part[2] if part[2] is Basis else Basis(Vector3.RIGHT, part[2])
		var arrays: Array = (part[0] as PrimitiveMesh).get_mesh_arrays()
		var pv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var pn: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var pi: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var xf := Transform3D(basis, part[1])
		var base := verts.size()
		for i in pv.size():
			verts.append(xf * pv[i])
			normals.append((basis * pn[i]).normalized())
			colors.append(part[3])
		for i in pi:
			indices.append(base + i)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_COLOR] = colors
	out[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return mesh
