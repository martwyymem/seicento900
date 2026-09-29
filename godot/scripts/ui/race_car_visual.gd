## 3D Fiat Seicento 900 Cup race car.
## The model (models/seicento.glb) is built in Blender by tools/blender/build_seicento.py to the real car's
## dimensions. Its meshes are shared by every car; paint, stripes and tail lights are per-car materials,
## so a car costs a few dozen draw calls and a single shadow-casting shell. Wheels steer and spin from
## the physics model, the sprung body rolls and pitches, and lights follow braking and nightfall.
extends Node3D

const MODEL_PATH := "res://models/seicento.glb"
const WHEEL_RADIUS := 0.2665 ## 145/70 R13
const WHEELBASE := 2.2
const HALF_TRACK := 0.6315
const WHEEL_SPOTS := [Vector3(-HALF_TRACK, WHEEL_RADIUS, -1.1), Vector3(HALF_TRACK, WHEEL_RADIUS, -1.1),
	Vector3(-HALF_TRACK, WHEEL_RADIUS, 1.1), Vector3(HALF_TRACK, WHEEL_RADIUS, 1.1)] ## FL, FR, RL, RR like the physics

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
var _paint := Color.WHITE
var _damage_shown := 0.0
var _light_bar: Array[StandardMaterial3D] = [] ## safety car only: left and right lamps
var _beacon: OmniLight3D

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
	shell.set_surface_override_material(sh.paint_surface, paint_material)
	body_pivot.add_child(shell)

	var details := MeshInstance3D.new()
	details.name = "Details"
	details.mesh = sh.details
	details.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	details.set_surface_override_material(sh.tail_surface, tail_material)
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
		var wheel := Node3D.new() # spins about X
		pivot.add_child(wheel)
		var tyre := MeshInstance3D.new()
		tyre.mesh = sh.wheel
		tyre.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if spot.x < 0.0:
			tyre.rotation.y = PI # the model's outer face points +X
		wheel.add_child(tyre)
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
	number_label.position = Vector3(0, 1.428, 0.6)
	number_label.rotation.x = -PI / 2.0
	number_label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body_pivot.add_child(number_label)

func set_paint(color: Color) -> void:
	if not paint_material:
		return
	_paint = color
	_apply_paint()
	stripe_material.albedo_color = Color.WHITE if color.get_luminance() < 0.42 else Color("#202124")

## Crash damage dulls and darkens the paint (scuffs, dirt and bent panels at a glance).
func _apply_paint() -> void:
	var c := _paint.lerp(Color("#3a3632"), _damage_shown * 0.8)
	c.a = 0.55 if _ghost else 1.0
	paint_material.albedo_color = c
	paint_material.clearcoat = 0.9 * (1.0 - _damage_shown)

## Dress this car as the safety car: white with yellow stripes and an amber light bar on the roof.
func make_safety_car() -> void:
	set_paint(Color("#f4f4f0"))
	set_stripes(true)
	stripe_material.albedo_color = Color("#ffc400")
	number_label.text = "SAFETY CAR"
	number_label.font_size = 16
	var bar := MeshInstance3D.new()
	bar.name = "LightBar"
	bar.mesh = _box(Vector3(1.1, 0.1, 0.22))
	var base := StandardMaterial3D.new()
	base.albedo_color = Color("#1c1c1c")
	bar.material_override = base
	bar.position = Vector3(0, 1.47, 0.3)
	body_pivot.add_child(bar)
	for side in [-1.0, 1.0]:
		var lamp := MeshInstance3D.new()
		lamp.mesh = _box(Vector3(0.44, 0.12, 0.2))
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("#ff9d00")
		m.emission_enabled = true
		m.emission = Color("#ff9000")
		m.emission_energy_multiplier = 0.0
		lamp.material_override = m
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lamp.position = Vector3(0.28 * side, 1.49, 0.3)
		body_pivot.add_child(lamp)
		_light_bar.append(m)
	_beacon = OmniLight3D.new()
	_beacon.light_color = Color("#ff9a10")
	_beacon.omni_range = 9.0
	_beacon.light_energy = 0.0
	_beacon.position = Vector3(0, 1.76, 0.3)
	_beacon.shadow_enabled = false
	body_pivot.add_child(_beacon)

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
		_apply_paint()
	if absf(car.damage - _damage_shown) > 0.02:
		_damage_shown = car.damage
		_apply_paint()

	if not _light_bar.is_empty():
		# alternating amber flashes while the safety car is on duty
		var t := Time.get_ticks_msec() / 1000.0
		var phase := fmod(t * 2.5, 1.0)
		for i in _light_bar.size():
			var on: bool = car.sc_lights and ((phase < 0.5) == (i == 0))
			_light_bar[i].emission_energy_multiplier = (3.5 + 3.0 * night) if on else 0.0
		_beacon.light_energy = (1.2 + 1.8 * night) if car.sc_lights else 0.0

# ---------------- shared geometry ----------------
static func _shared_resources() -> Dictionary:
	if not _shared.is_empty():
		return _shared
	# Local frame: -Z forward, +X right, +Y up; the model's origin is on the ground midway between the axles.
	var meshes := {}
	var root := _load_model()
	if root:
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			meshes[mi.name] = (mi as MeshInstance3D).mesh
		root.free()
	var shell: Mesh = meshes.get("Body", BoxMesh.new())
	var details: Mesh = meshes.get("Details", BoxMesh.new())

	# Glass and headlights are the same on every car, so they live on the shared meshes.
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.05, 0.065, 0.075, 0.38)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.roughness = 0.04
	glass.metallic_specular = 0.8
	var head := StandardMaterial3D.new()
	head.albedo_color = Color("#d8dcdc")
	head.metallic = 0.6
	head.roughness = 0.08
	head.emission_enabled = true
	head.emission = Color("#fff3d6")
	head.emission_energy_multiplier = 0.05
	var glass_surface := _surface(shell, "Glass")
	if glass_surface >= 0:
		shell.surface_set_material(glass_surface, glass)
	var head_surface := _surface(details, "Headlight")
	if head_surface >= 0:
		details.surface_set_material(head_surface, head)

	# Soft dark ellipse under the car keeps it sitting on the road.
	var contact := PlaneMesh.new()
	contact.size = Vector2(1.9, 3.7)
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

	_shared = {"shell": shell, "details": details, "stripes": meshes.get("Stripes", BoxMesh.new()),
		"wheel": meshes.get("Wheel", BoxMesh.new()), "contact": contact, "head": head,
		"paint_surface": maxi(0, _surface(shell, "Paint")), "tail_surface": maxi(0, _surface(details, "Taillight"))}
	return _shared

## The imported model when the editor has imported it, otherwise the GLB read directly (fresh checkouts).
static func _load_model() -> Node:
	if ResourceLoader.exists(MODEL_PATH):
		var packed := load(MODEL_PATH) as PackedScene
		if packed:
			return packed.instantiate()
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(MODEL_PATH), state) != OK:
		push_error("Car model %s could not be read" % MODEL_PATH)
		return null
	return doc.generate_scene(state)

## Index of the surface whose material has this name (from Blender), or -1.
static func _surface(mesh: Mesh, material_name: String) -> int:
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i)
		if m and m.resource_name == material_name:
			return i
	return -1

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
