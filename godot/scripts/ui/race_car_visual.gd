## 3D Fiat Seicento 900 Cup race car.
## The model (models/seicento.glb) is built in Blender by tools/blender/build_seicento.py to the real car's
## dimensions. Its meshes are shared by every car; paint, stripes and tail lights are per-car materials,
## so a car costs a few dozen draw calls and a single shadow-casting shell. Wheels steer and spin from
## the physics model, the sprung body rolls and pitches, and lights follow braking and nightfall.
## The paint is a glossy clear coat (metallic with flake for silver/grey liveries); cars racing near the camera
## throw tyre smoke, wet-road spray and dust/grass/snow kick-up (tuned after WRC 3DS's kickup particles), and
## distant ones drop their cabin.
extends Node3D

const MODEL_PATH := "res://models/seicento.glb"
const WHEEL_RADIUS := 0.2665 ## 145/70 R13
const WHEELBASE := 2.2
const HALF_TRACK := 0.6315
const CABIN_RANGE := 45.0 ## m: farther cars skip the cabin (dash, seat, cage), unseen through the glass
const FX_REACH := [0.0, 35.0, 60.0, 90.0] ## m from the camera within which bots show effects, per quality preset
const FX_AXLE := Vector3(0.0, 0.03, 1.12) ## effects come off the rear contact patches (+Z is backwards)
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
var _door_decal_l: MeshInstance3D
var _door_decal_r: MeshInstance3D
var _sunstrip_decal: MeshInstance3D
var _hood_decal: MeshInstance3D
var _sill_decal_l: MeshInstance3D
var _sill_decal_r: MeshInstance3D
var car_number := 1:
	set(value):
		car_number = value
		if is_instance_valid(number_label):
			number_label.text = str(car_number)
		_update_decals()
var is_player := false

## Smoothed presentation state (radians).
var grade_pitch := 0.0
var _roll := 0.0
var _spins := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _tail_energy := -1.0
var _ghost := false
var _paint := Color.WHITE
var _damage_shown := 0.0
var _previous_throttle := 0.0
var _light_bar: Array[StandardMaterial3D] = [] ## safety car only: left and right lamps
var _beacon: OmniLight3D
var _shell: MeshInstance3D
var _fx_near := false ## this car shows effects: in a race, not a ghost, and the player or near the camera
var _world: Node = null ## the RaceWorld this car races in (effects only there, not for menus or the ghost)
var _fx_checked := false
var _fx := {} ## effect kind -> GPUParticles3D, made the first time the car needs it

func _ready() -> void:
	var sh := _shared_resources()
	paint_material = StandardMaterial3D.new()
	paint_material.vertex_color_use_as_albedo = true
	paint_material.vertex_color_is_srgb = true
	# base coat under a hard, near-mirror clear coat: the coat's Fresnel gives the sky reflection and the rim
	paint_material.roughness = 0.36
	paint_material.metallic = 0.0
	paint_material.metallic_specular = 0.55
	paint_material.clearcoat_enabled = true
	paint_material.clearcoat = 1.0
	paint_material.clearcoat_roughness = 0.03
	paint_material.rim_enabled = true
	paint_material.rim = 0.18
	paint_material.rim_tint = 0.65
	stripe_material = StandardMaterial3D.new()
	stripe_material.roughness = 0.3
	stripe_material.clearcoat_enabled = true # decals sit under the same clear coat
	stripe_material.clearcoat = 0.8
	stripe_material.clearcoat_roughness = 0.05
	tail_material = StandardMaterial3D.new()
	tail_material.albedo_color = Color("#4a0a0a")
	tail_material.roughness = 0.08
	tail_material.emission_enabled = true
	tail_material.emission = Color("#ff1a0c")
	tail_material.emission_energy_multiplier = 0.35

	body_pivot = Node3D.new()
	body_pivot.name = "SuspendedBody"
	add_child(body_pivot)

	var shell := MeshInstance3D.new()
	shell.name = "Shell"
	shell.mesh = sh.shell
	shell.set_surface_override_material(sh.paint_surface, paint_material)
	paint_material.next_pass = sh.coat
	body_pivot.add_child(shell)
	_shell = shell

	var details := MeshInstance3D.new()
	details.name = "Details"
	details.mesh = sh.details
	details.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	details.set_surface_override_material(sh.tail_surface, tail_material)
	body_pivot.add_child(details)

	var cabin := MeshInstance3D.new()
	cabin.name = "Cabin"
	cabin.mesh = sh.cabin
	cabin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cabin.visibility_range_end = CABIN_RANGE
	cabin.visibility_range_end_margin = 4.0
	body_pivot.add_child(cabin)

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

	# Racing decals: door numbers, sunstrip, bonnet plate and sponsor stacks. Each quad sits 6 mm off the body
	# surface, at points and normals measured on models/seicento.glb's Body mesh (doors: centred on the model's
	# white door panel). Re-measure if the car is rebuilt.
	var decal_mat := _decal_material()
	_door_decal_l = _add_decal("DoorDecalL", decal_mat, Vector3(-0.7408, 0.65, -0.02), Vector3(-0.9984, 0.0568, -0.0008), Vector3.UP)
	_door_decal_r = _add_decal("DoorDecalR", decal_mat, Vector3(0.7408, 0.65, -0.02), Vector3(0.9984, 0.0568, -0.0008), Vector3.UP)
	# along the top of the windscreen, reading from the front; "up" runs up the glass towards the roof
	_sunstrip_decal = _add_decal("Sunstrip", decal_mat, Vector3(0.0, 1.25, -0.167), Vector3(0.0, 0.824, -0.566), Vector3(0.0, 0.566, 0.824))
	# on the bonnet, reading from behind (the chase camera)
	_hood_decal = _add_decal("HoodDecal", decal_mat, Vector3(0.0, 0.7935, -1.22), Vector3(-0.0176, 0.9848, -0.1729), Vector3.FORWARD)
	_sill_decal_l = _add_decal("SillDecalL", decal_mat, Vector3(-0.7415, 0.385, 0.25), Vector3(-0.998, -0.065, 0.003), Vector3.UP)
	_sill_decal_r = _add_decal("SillDecalR", decal_mat, Vector3(0.7415, 0.385, 0.25), Vector3(0.998, -0.065, 0.003), Vector3.UP)
	_update_decals()

func _add_decal(label: String, mat: StandardMaterial3D, surface: Vector3, normal: Vector3, up: Vector3) -> MeshInstance3D:
	var z := normal.normalized()
	var x := up.cross(z).normalized()
	var d := MeshInstance3D.new()
	d.name = label
	d.material_override = mat
	d.transform = Transform3D(Basis(x, z.cross(x), z), surface + z * 0.006)
	d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	d.visible = mat.albedo_texture != null # no atlas (models/car_decals.png missing): no blank white quads
	body_pivot.add_child(d)
	return d

func set_paint(color: Color) -> void:
	if not paint_material:
		return
	_paint = color
	# silver, grey and gunmetal liveries are metallic paints: the flakes catch the sun under the coat
	var metal := color.s < 0.3 and color.v > 0.25 and color.v < 0.85
	paint_material.metallic = 0.65 if metal else 0.0
	paint_material.roughness = 0.42 if metal else 0.36
	paint_material.normal_enabled = metal
	if metal:
		paint_material.normal_texture = _shared_resources().flakes
		paint_material.normal_scale = 0.35
		paint_material.uv1_triplanar = true
		paint_material.uv1_scale = Vector3(14.0, 14.0, 14.0)
	_apply_paint()
	stripe_material.albedo_color = Color.WHITE if color.get_luminance() < 0.42 else Color("#202124")

## Crash damage dulls and darkens the paint (scuffs, dirt and bent panels at a glance).
func _apply_paint() -> void:
	var c := _paint.lerp(Color("#3a3632"), _damage_shown * 0.8)
	c.a = 0.55 if _ghost else 1.0
	paint_material.albedo_color = c
	paint_material.clearcoat = 1.0 - 0.9 * _damage_shown
	paint_material.clearcoat_roughness = 0.03 + 0.4 * _damage_shown
	if _shell:
		# Scale clear-coat horizon band per car: richer/darker cars take full reflection,
		# while bright liveries are toned down to preserve highlight headroom and avoid blowout
		var lum := _paint.get_luminance()
		var coat_scale: float = lerpf(1.15, 0.6, smoothstep(0.2, 0.8, lum)) * (1.0 - 0.85 * _damage_shown)
		_shell.set_instance_shader_parameter("coat", coat_scale)

## Dress this car as the safety car: white with yellow stripes and an amber light bar on the roof.
func make_safety_car() -> void:
	set_paint(Color("#f4f4f0"))
	set_stripes(true)
	stripe_material.albedo_color = Color("#ffc400")
	number_label.text = "SAFETY CAR"
	number_label.font_size = 16
	if is_instance_valid(_door_decal_l):
		_door_decal_l.visible = false
		_door_decal_r.visible = false
		_hood_decal.visible = false
		_sill_decal_l.visible = false
		_sill_decal_r.visible = false
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
	sh.head.emission_energy_multiplier = 0.08 + 3.6 * night
	sh.coat.set_shader_parameter("strength", 0.65 * (1.0 - 0.9 * night))
	var amb := Color(0.12, 0.14, 0.20).lerp(Color(0.52, 0.56, 0.62), 1.0 - night)
	var sun_col := Color(0.08, 0.10, 0.15).lerp(Color(1.0, 0.95, 0.88), 1.0 - night)
	FxParticles.set_environment_lighting(amb, sun_col, Vector3(0.3, 0.8, 0.3))

## The clear coat's horizon band follows the sky the world is showing (set from the player's car each frame).
static func set_sky(top: Color, horizon: Color) -> void:
	var coat: ShaderMaterial = _shared_resources().coat
	if coat.get_meta("sky", []) != [top, horizon]:
		coat.set_meta("sky", [top, horizon])
		coat.set_shader_parameter("sky_top", top)
		coat.set_shader_parameter("sky_horizon", horizon)
		var ambient := horizon.lerp(top, 0.45) * 0.75
		var sun_col := Color(1.05, 0.98, 0.92)
		FxParticles.set_environment_lighting(ambient, sun_col, Vector3(0.42, 0.78, 0.46))
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

	# brake lights well over the glow threshold so they bloom; the running lights stay a lit-lens red
	var tail := (4.2 + 1.8 * night) if car.brake_on else (0.35 + 1.4 * night)
	if absf(tail - _tail_energy) > 0.01:
		_tail_energy = tail
		tail_material.emission_energy_multiplier = tail

	if ghost != _ghost:
		_ghost = ghost
		paint_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if ghost else BaseMaterial3D.TRANSPARENCY_DISABLED
		_apply_paint()
		if is_instance_valid(_door_decal_l):
			_door_decal_l.visible = not ghost
			_door_decal_r.visible = not ghost
			_hood_decal.visible = not ghost
			_sunstrip_decal.visible = not ghost
			_sill_decal_l.visible = not ghost
			_sill_decal_r.visible = not ghost
	if car.damage - _damage_shown > 0.035 and _fx_near:
		var q: int = _world.quality
		FxParticles.burst(self, "debris", global_position + Vector3(0.0, 0.35, 0.0), 14, q)
		FxParticles.burst(self, "sparks", global_position + Vector3(0.0, 0.25, 0.0), 10, q)
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
	_update_fx(car)
	if _previous_throttle > 0.6 and car.throttle < 0.08 and car.rpm > 3200.0 and _fx_near:
		# a pop from the tailpipe tip (build_seicento.py: 0.30 m right, 0.18 m up, behind the bumper) on a sharp lift
		FxParticles.burst(self, "backfire", to_global(Vector3(0.30, 0.19, 1.56)), 8, _world.quality)
	_previous_throttle = car.throttle

# ---------------- tyre smoke, spray and kick-up ----------------
## Effect strengths from what the car is doing and what it drives on. Bots only show them near the camera
## (none on the Low preset), and every emitter is made the first time it is needed.
func _update_fx(car: RaceCar) -> void:
	if not _fx_checked:
		_fx_checked = true
		var w := get_node_or_null("../..")
		if get_parent() and get_parent().name == "Cars" and w and "race" in w and "quality" in w:
			_world = w
	if not _world:
		return
	var race = _world.race
	if is_player and "sky_top_color" in _world:
		set_sky(_world.sky_top_color, _world.sky_horizon_color)
	var want := {}
	_fx_near = false
	if race and not _ghost and visible:
		var cam := get_viewport().get_camera_3d()
		var reach: float = FX_REACH[clampi(_world.quality, 0, FX_REACH.size() - 1)]
		if is_player or (cam and cam.global_position.distance_squared_to(global_position) < reach * reach):
			_fx_near = true
			want = _fx_strengths(race, car)
	for kind in want:
		if want[kind] > 0.02 and not _fx.has(kind):
			_fx[kind] = _make_emitter(kind)
	for kind in _fx:
		var k: float = want.get(kind, 0.0)
		var p: GPUParticles3D = _fx[kind]
		p.emitting = k > 0.02
		if p.emitting:
			p.amount_ratio = clampf(k, 0.05, 1.0)

static func _fx_strengths(race, car: RaceCar) -> Dictionary:
	var v := absf(car.speed)
	var out := {}
	if v < 1.5:
		return out
	var wet: float = race.weather.wet
	var snow: float = race.weather.snow
	# what the outer wheels run on: off the tarmac onto grass or gravel, or a loose rally stage
	var tr: Track = race.track
	var side := signf(car.d) if car.d != 0.0 else 1.0
	var surf: int = race.surface_at(car, car.x + tr.sample(tr.NX, car.s) * side * 0.65,
		car.y + tr.sample(tr.NY, car.s) * side * 0.65)
	var loose: bool = race.s != null and race.s.surface != "tarmac"
	var go := smoothstep(3.0, 22.0, v)
	if surf == Physics.SURF_GRAVEL:
		out.gravel = go * (1.0 - 0.7 * wet)
	elif loose and surf != Physics.SURF_GRASS:
		out.dust = go * (1.0 - 0.7 * wet)
	elif surf == Physics.SURF_GRASS:
		out.grass = go
	else:
		out.spray = wet * smoothstep(6.0, 32.0, v)
		if snow > 0.2:
			out.snow = snow * smoothstep(5.0, 25.0, v)
		if wet > 0.35 and v > 9.0:
			out.splash = wet * smoothstep(9.0, 28.0, v)
	# tyre smoke: wheelspin, lock-ups and slides on a dry road (the wet road sprays instead)
	if wet < 0.5 and not loose:
		out.smoke = clampf((car.slip - 0.3) / 0.6, 0.0, 1.0) * smoothstep(2.0, 8.0, v) * (1.0 - wet * 1.6)
	return out

const PRESET_FOR_KIND := {
	"spray": "spray",
	"smoke": "smoke",
	"dust": "kickup_dirt",
	"grass": "kickup_grass",
	"snow": "kickup_snow",
	"gravel": "kickup_gravel",
	"splash": "splash",
}

func _make_emitter(kind: String) -> GPUParticles3D:
	var preset: String = PRESET_FOR_KIND.get(kind, kind)
	if FxParticles.PRESETS.has(preset):
		var q: int = _world.quality if is_instance_valid(_world) and "quality" in _world else 2
		var p := FxParticles.attach(self, preset, q, 1.0 if is_player else 0.7)
		if p:
			p.position = FX_AXLE
			return p
	var sh := _shared_resources()
	var spec: Dictionary = FX_KINDS[kind]
	var p := GPUParticles3D.new()
	p.name = "Fx_" + kind
	p.amount = spec.amount
	p.lifetime = spec.life
	p.randomness = 0.3
	p.local_coords = false # puffs stay where they were thrown while the car drives on
	p.process_material = sh.fx[kind]
	p.draw_pass_1 = sh.puff
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-30, -3, -30), Vector3(60, 14, 90))
	p.position = FX_AXLE
	p.emitting = false
	add_child(p)
	return p

## WRC 3DS kickup_*.lua for reference: 30-60 particles, 1-1.5 s, 0.4-2 m, alpha 0.65-0.75 fading out,
## 25-50 % of the car's speed inherited. Spray and smoke are fuller (and grow) to read from the chase camera.
const FX_KINDS := {
	"spray": {"amount": 44, "life": 0.9, "colour": Color(0.86, 0.89, 0.92, 0.42), "speed": [2.5, 6.0], "up": 0.45,
		"gravity": 5.0, "damp": 2.0, "inherit": 0.3, "scale": [0.7, 1.1], "grow": 2.8},
	"smoke": {"amount": 36, "life": 1.8, "colour": Color(0.93, 0.93, 0.94, 0.5), "speed": [0.6, 2.0], "up": 0.6,
		"gravity": -0.5, "damp": 1.2, "inherit": 0.15, "scale": [0.6, 1.0], "grow": 4.0},
	"dust": {"amount": 40, "life": 1.8, "colour": Color(0.80, 0.71, 0.59, 0.6), "speed": [1.5, 4.0], "up": 0.55,
		"gravity": 0.6, "damp": 1.5, "inherit": 0.25, "scale": [0.7, 1.2], "grow": 3.2},
	"grass": {"amount": 30, "life": 1.0, "colour": Color(0.40, 0.38, 0.26, 0.5), "speed": [2.0, 5.0], "up": 0.7,
		"gravity": 6.0, "damp": 1.0, "inherit": 0.3, "scale": [0.4, 0.7], "grow": 2.0},
	"snow": {"amount": 30, "life": 1.0, "colour": Color(0.97, 0.98, 1.0, 0.7), "speed": [1.5, 3.5], "up": 0.5,
		"gravity": 1.5, "damp": 1.5, "inherit": 0.25, "scale": [0.5, 0.7], "grow": 2.6},
}

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
	var cabin: Mesh = meshes.get("Cabin", ArrayMesh.new())
	var details: Mesh = meshes.get("Details", BoxMesh.new())

	# Glass and headlights are the same on every car, so they live on the shared meshes.
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.05, 0.065, 0.075, 0.38)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.roughness = 0.02
	glass.metallic_specular = 1.0
	var head := StandardMaterial3D.new()
	head.albedo_color = Color("#d8dcdc")
	head.metallic = 0.6
	head.roughness = 0.08
	head.emission_enabled = true
	head.emission = Color("#fff3d6")
	head.emission_energy_multiplier = 0.08
	var glass_surface := _surface(shell, "Glass")
	if glass_surface >= 0:
		shell.surface_set_material(glass_surface, glass)
	var head_surface := _surface(details, "Headlight")
	if head_surface >= 0:
		details.surface_set_material(head_surface, head)

	# Soft dark ellipse under the car keeps it sitting on the road: a dense core under the floor (ambient
	# occlusion) and a wide soft falloff past the sills and bumpers.
	var contact := PlaneMesh.new()
	contact.size = Vector2(2.0, 3.9)
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.5, 0.78, 1.0])
	fade.colors = PackedColorArray([Color(0, 0, 0, 0.82), Color(0, 0, 0, 0.72), Color(0, 0, 0, 0.3), Color(0, 0, 0, 0)])
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

	_shared = {"shell": shell, "details": details, "cabin": cabin, "flakes": _flake_texture(), "coat": _coat_material(),
		"puff": _puff_mesh(), "fx": _fx_materials(), "stripes": meshes.get("Stripes", BoxMesh.new()),
		"wheel": meshes.get("Wheel", BoxMesh.new()), "contact": contact, "head": head,
		"paint_surface": maxi(0, _surface(shell, "Paint")), "tail_surface": maxi(0, _surface(details, "Taillight"))}
	return _shared

## The clear coat's sharp horizon reflection, the line of light that runs along a glossy car's flanks (the
## sky radiance map alone is too smooth to show it). An additive second pass over the paint: a bright band
## just above the reflected horizon, the sky's gradient above it, Fresnel-weighted, kept out of the panel gaps,
## fading with distance, at night (set_night) and on damaged paint (the per-car "coat" instance uniform).
const COAT_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_back, fog_disabled, shadows_disabled;
uniform vec3 sky_top : source_color = vec3(0.38, 0.56, 0.82);
uniform vec3 sky_horizon : source_color = vec3(0.78, 0.84, 0.9);
uniform float strength = 0.75;
instance uniform float coat = 1.0;
void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	vec3 r = (INV_VIEW_MATRIX * vec4(reflect(-v, n), 0.0)).xyz;
	float nv = clamp(dot(n, v), 0.0, 1.0);
	float f = 0.12 + 0.88 * pow(1.0 - nv, 3.0);
	float h = r.y;
	// Crisp FH1-style horizon reflection band: bright crisp waistline stripe with soft sky dome fill
	float horizon_band = smoothstep(-0.015, 0.025, h) * exp(-abs(h - 0.035) * 24.0);
	float sky_sheen = smoothstep(0.0, 0.5, h) * 0.06;
	float band = horizon_band + sky_sheen;
	vec3 sky = mix(sky_horizon, sky_top, smoothstep(0.05, 0.6, max(0.0, h)));
	float fade = 1.0 - smoothstep(45.0, 140.0, length(VERTEX));
	vec3 refl = sky * band * f * strength * coat * fade * COLOR.r;
	// Soft shoulder compression prevents blowing out highlights on bright paint
	ALBEDO = refl / (1.0 + refl * 0.5);
}
"""

static func _coat_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = COAT_SHADER
	var m := ShaderMaterial.new()
	m.shader = shader
	m.render_priority = 1
	return m

## Metallic flake: a fine bumpy normal map, tiled triplanar (the model has no UVs) at a few millimetres a flake.
static func _flake_texture() -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = 0.18
	noise.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	var tex := NoiseTexture2D.new()
	tex.width = 128
	tex.height = 128
	tex.seamless = true
	tex.as_normal_map = true
	tex.bump_strength = 2.0
	tex.noise = noise
	return tex

## One soft, lumpy puff (a billboard quad) shared by every effect; the process materials colour it.
static func _puff_mesh() -> QuadMesh:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.09
	noise.fractal_octaves = 3
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var r := Vector2(x - 31.5, y - 31.5).length() / 31.5
			var a := (1.0 - smoothstep(0.25, 1.0, r)) * clampf(0.7 + 0.6 * noise.get_noise_2d(x, y), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX # lit by sun and sky, dark at night, cheap
	m.disable_receive_shadows = true
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.proximity_fade_enabled = true # soft where a puff meets the road
	m.proximity_fade_distance = 0.5
	var quad := QuadMesh.new()
	quad.material = m
	return quad

static func _fx_materials() -> Dictionary:
	var out := {}
	var fade := Gradient.new() # quick fade in, long fade out (alpha over a puff's life)
	fade.offsets = PackedFloat32Array([0.0, 0.12, 0.45, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	for kind in FX_KINDS:
		var spec: Dictionary = FX_KINDS[kind]
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(0.6, 0.03, 0.12)
		pm.direction = Vector3(0.0, spec.up, 1.0).normalized()
		pm.spread = 24.0
		pm.initial_velocity_min = spec.speed[0]
		pm.initial_velocity_max = spec.speed[1]
		pm.gravity = Vector3(0.0, -spec.gravity, 0.0)
		pm.damping_min = spec.damp * 0.7
		pm.damping_max = spec.damp
		pm.inherit_velocity_ratio = spec.inherit
		pm.angle_min = -180.0
		pm.angle_max = 180.0
		pm.angular_velocity_min = -40.0
		pm.angular_velocity_max = 40.0
		pm.scale_min = spec.scale[0]
		pm.scale_max = spec.scale[1]
		var grow := Curve.new()
		grow.max_value = spec.grow
		grow.add_point(Vector2(0.0, 1.0))
		grow.add_point(Vector2(1.0, spec.grow), 0.0, 0.0)
		var grow_tex := CurveTexture.new()
		grow_tex.curve = grow
		pm.scale_curve = grow_tex
		pm.color = spec.colour
		pm.color_ramp = ramp
		out[kind] = pm
	return out

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

func _update_decals() -> void:
	if not is_instance_valid(_door_decal_l):
		return
	var idx := clampi(car_number - 1, 0, 15)
	var door_m := _door_plate_mesh(idx)
	_door_decal_l.mesh = door_m
	_door_decal_r.mesh = door_m
	_sunstrip_decal.mesh = _sunstrip_mesh(idx % 4)
	_hood_decal.mesh = _hood_plate_mesh(idx % 4)
	var sill_m := _sill_stack_mesh(idx % 4)
	_sill_decal_l.mesh = sill_m
	_sill_decal_r.mesh = sill_m

const DECALS_TEX_PATH := "res://models/car_decals.png"

static func _decal_material() -> StandardMaterial3D:
	var sh := _shared_resources()
	if not sh.has("decal_mat"):
		var m := StandardMaterial3D.new()
		var tex = load(DECALS_TEX_PATH) as Texture2D
		if tex:
			m.albedo_texture = tex
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		# vinyl, not paint: a soft sheen, so the sky reflection doesn't wash the print out
		m.roughness = 0.6
		m.metallic_specular = 0.3
		m.render_priority = 2
		sh["decal_mat"] = m
	return sh["decal_mat"]

static func _door_plate_mesh(idx: int) -> ArrayMesh:
	var sh := _shared_resources()
	var cache: Dictionary = sh.get("door_meshes", {})
	if cache.has(idx):
		return cache[idx]
	var col := idx % 4
	var row := idx / 4
	var uv_min := Vector2(col * 0.125, row * 0.125)
	var uv_max := Vector2((col + 1) * 0.125, (row + 1) * 0.125)
	var m := _decal_quad(Vector2(0.30, 0.30), uv_min, uv_max)
	cache[idx] = m
	sh["door_meshes"] = cache
	return m

static func _sunstrip_mesh(variant: int) -> ArrayMesh:
	var sh := _shared_resources()
	var cache: Dictionary = sh.get("sunstrip_meshes", {})
	if cache.has(variant):
		return cache[variant]
	# the middle of the 16:1 strip, so the 8.6:1 visor keeps the lettering's proportions
	var uv_min := Vector2(0.22, 0.5 + variant * 0.0625)
	var uv_max := Vector2(0.78, 0.5 + (variant + 1) * 0.0625)
	var m := _decal_quad(Vector2(0.86, 0.1), uv_min, uv_max)
	cache[variant] = m
	sh["sunstrip_meshes"] = cache
	return m

static func _hood_plate_mesh(variant: int) -> ArrayMesh:
	var sh := _shared_resources()
	var cache: Dictionary = sh.get("hood_meshes", {})
	if cache.has(variant):
		return cache[variant]
	var col := variant % 2
	var row := variant / 2
	var uv_min := Vector2(0.5 + col * 0.25, row * 0.25)
	var uv_max := Vector2(0.5 + (col + 1) * 0.25, (row + 1) * 0.25)
	var m := _decal_quad(Vector2(0.28, 0.28), uv_min, uv_max)
	cache[variant] = m
	sh["hood_meshes"] = cache
	return m

static func _sill_stack_mesh(variant: int) -> ArrayMesh:
	var sh := _shared_resources()
	var cache: Dictionary = sh.get("sill_meshes", {})
	if cache.has(variant):
		return cache[variant]
	var col := variant % 2
	var row := variant / 2
	var uv_min := Vector2(col * 0.5, 0.75 + row * 0.125)
	var uv_max := Vector2((col + 1) * 0.5, 0.75 + (row + 1) * 0.125)
	var m := _decal_quad(Vector2(0.48, 0.09), uv_min, uv_max)
	cache[variant] = m
	sh["sill_meshes"] = cache
	return m

static func _decal_quad(size: Vector2, uv_min: Vector2, uv_max: Vector2) -> ArrayMesh:
	var half := size * 0.5
	var verts := PackedVector3Array([
		Vector3(-half.x, -half.y, 0.0),
		Vector3(half.x, -half.y, 0.0),
		Vector3(half.x, half.y, 0.0),
		Vector3(-half.x, half.y, 0.0)
	])
	var uvs := PackedVector2Array([
		Vector2(uv_min.x, uv_max.y),
		Vector2(uv_max.x, uv_max.y),
		Vector2(uv_max.x, uv_min.y),
		Vector2(uv_min.x, uv_min.y)
	])
	var normals := PackedVector3Array([Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1)])
	var indices := PackedInt32Array([0, 1, 2, 0, 2, 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_INDEX] = indices
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
