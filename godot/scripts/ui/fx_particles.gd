## Small shared pool for race particle effects. Presets follow the compact, soft-edged emitters in
## WRC 3DS (roughly 20-60 particles, short bursts for grit and longer, slower smoke/dust trails).
class_name FxParticles
extends RefCounted

const SHADER := preload("res://shaders/fx_particle.gdshader")
const MAX_BURST_SYSTEMS_PER_PRESET := 4
const QUALITY_SCALE := [0.35, 0.6, 0.82, 1.0]
const PRESETS := {
	"kickup_grass": {"amount": 36, "life": 1.0, "color": Color(0.40, 0.38, 0.26, 0.35), "speed": Vector2(1.5, 3.8), "up": 0.25, "gravity": 6.0, "drag": 1.4, "scale": Vector2(0.14, 0.26), "grow": 1.8, "spread": 30.0, "inherit": 0.25},
	"kickup_gravel": {"amount": 32, "life": 1.15, "color": Color(0.78, 0.72, 0.63, 0.72), "speed": Vector2(5.0, 11.0), "up": 0.38, "gravity": 10.0, "drag": 2.4, "scale": Vector2(0.045, 0.09), "grow": 1.0, "spread": 25.0, "inherit": 0.25},
	"kickup_dirt": {"amount": 54, "life": 1.6, "color": Color(0.67, 0.57, 0.43, 0.28), "speed": Vector2(0.8, 2.4), "up": 0.12, "gravity": 1.0, "drag": 1.8, "scale": Vector2(0.18, 0.32), "grow": 3.0, "spread": 24.0, "inherit": 0.22},
	"kickup_snow": {"amount": 30, "life": 1.0, "color": Color(0.92, 0.95, 1.0, 0.72), "speed": Vector2(0.25, 0.7), "up": 0.35, "gravity": 0.3, "drag": 0.6, "scale": Vector2(0.12, 0.2), "grow": 1.5, "spread": 20.0, "inherit": 0.2},
	"sparks": {"amount": 22, "life": 0.45, "color": Color(1.0, 0.58, 0.18, 0.95), "speed": Vector2(5.0, 12.0), "up": 0.18, "gravity": 18.0, "drag": 0.4, "scale": Vector2(0.025, 0.055), "grow": 0.35, "spread": 55.0, "emission": true},
	"debris": {"amount": 18, "life": 0.85, "color": Color(0.56, 0.49, 0.39, 0.9), "speed": Vector2(3.0, 9.0), "up": 0.55, "gravity": 13.0, "drag": 0.7, "scale": Vector2(0.04, 0.11), "grow": 0.55, "spread": 65.0},
	"smoke": {"amount": 80, "life": 1.5, "color": Color(0.84, 0.86, 0.89, 0.22), "speed": Vector2(0.4, 1.4), "up": 0.03, "gravity": -0.02, "drag": 1.8, "scale": Vector2(0.26, 0.48), "grow": 3.6, "spread": 18.0, "inherit": 0.22},
	"splash": {"amount": 30, "life": 0.7, "color": Color(0.72, 0.84, 0.91, 0.5), "speed": Vector2(2.0, 5.5), "up": 0.7, "gravity": 8.0, "drag": 2.0, "scale": Vector2(0.08, 0.16), "grow": 1.4, "spread": 38.0, "inherit": 0.25},
	"spray": {"amount": 36, "life": 0.9, "color": Color(0.82, 0.88, 0.93, 0.32), "speed": Vector2(2.0, 5.0), "up": 0.38, "gravity": 1.5, "drag": 1.6, "scale": Vector2(0.12, 0.25), "grow": 2.0, "spread": 24.0, "inherit": 0.3},
	"exhaust": {"amount": 12, "life": 1.0, "color": Color(0.7, 0.72, 0.74, 0.19), "speed": Vector2(0.2, 0.7), "up": 0.08, "gravity": -0.4, "drag": 0.6, "scale": Vector2(0.07, 0.13), "grow": 1.4, "spread": 10.0},
	"backfire": {"amount": 8, "life": 0.2, "color": Color(1.0, 0.34, 0.07, 0.95), "speed": Vector2(1.0, 3.0), "up": 0.05, "gravity": -1.0, "drag": 0.2, "scale": Vector2(0.06, 0.12), "grow": 0.3, "spread": 14.0, "emission": true},
	"leaves": {"amount": 22, "life": 4.0, "color": Color(0.72, 0.48, 0.2, 0.72), "speed": Vector2(0.25, 1.1), "up": 0.0, "gravity": 0.25, "drag": 0.15, "scale": Vector2(0.09, 0.16), "grow": 0.9, "spread": 180.0},
	"dust_motes": {"amount": 16, "life": 3.5, "color": Color(1.0, 0.82, 0.5, 0.22), "speed": Vector2(0.05, 0.35), "up": 0.0, "gravity": -0.03, "drag": 0.05, "scale": Vector2(0.025, 0.06), "grow": 1.0, "spread": 180.0},
	"fog_wisp": {"amount": 12, "life": 5.0, "color": Color(0.8, 0.86, 0.9, 0.15), "speed": Vector2(0.08, 0.35), "up": 0.06, "gravity": -0.04, "drag": 0.08, "scale": Vector2(0.5, 0.9), "grow": 1.8, "spread": 180.0}
}

static var _materials: Dictionary = {}
static var _meshes: Dictionary = {}
static var _pools: Dictionary = {}
static var _current_ambient := Vector3(0.52, 0.56, 0.62)
static var _current_sun := Vector3(1.0, 0.95, 0.88)
static var _current_sun_dir := Vector3(0.42, 0.78, 0.46)

## Update sun and ambient lighting tint across all shared particle materials
static func set_environment_lighting(ambient: Color, sun: Color, sun_dir: Vector3) -> void:
	_current_ambient = Vector3(ambient.r, ambient.g, ambient.b)
	_current_sun = Vector3(sun.r, sun.g, sun.b)
	_current_sun_dir = sun_dir.normalized()
	for key in _meshes:
		var q = _meshes[key]
		if is_instance_valid(q) and q is QuadMesh and q.material is ShaderMaterial:
			var sm: ShaderMaterial = q.material
			sm.set_shader_parameter("ambient_color", _current_ambient)
			sm.set_shader_parameter("sun_color", _current_sun)
			sm.set_shader_parameter("sun_direction", _current_sun_dir)

## Add a continuous, preset-configured emitter beneath parent. Set amount_ratio/emitting from gameplay.
static func attach(parent: Node3D, preset: String, quality: int = 2, density: float = 1.0) -> GPUParticles3D:
	if not is_instance_valid(parent) or not PRESETS.has(preset):
		return null
	var p := _new_system(preset, quality, density)
	p.name = "Fx_" + preset
	parent.add_child(p)
	return p

## Reuse one of at most four systems per preset for short bursts. Returns null when the pool is busy/full.
static func burst(parent: Node3D, preset: String, world_position: Vector3, count: int = -1, quality: int = 2) -> GPUParticles3D:
	if not is_instance_valid(parent) or not PRESETS.has(preset):
		return null
	var pool: Array = _pools.get(preset, [])
	pool = pool.filter(func(candidate): return is_instance_valid(candidate))
	var p: GPUParticles3D
	for candidate in pool:
		if is_instance_valid(candidate) and not candidate.emitting:
			p = candidate
			break
	if p == null:
		if pool.size() >= MAX_BURST_SYSTEMS_PER_PRESET:
			return null
		p = _new_system(preset, quality, 1.0)
		p.one_shot = true
		p.finished.connect(func(): p.emitting = false)
		pool.append(p)
		_pools[preset] = pool
		parent.add_child(p)
	elif p.get_parent() != parent:
		p.reparent(parent)
	p.global_position = world_position
	var cap := maxi(1, int(PRESETS[preset].amount * QUALITY_SCALE[clampi(quality, 0, 3)]))
	p.amount = clampi(count, 1, cap) if count > 0 else cap
	p.restart()
	return p

static func _new_system(preset: String, quality: int, density: float) -> GPUParticles3D:
	if not _materials.has(preset):
		_build_resources()
	var spec: Dictionary = PRESETS[preset]
	var p := GPUParticles3D.new()
	p.amount = maxi(1, int(spec.amount * QUALITY_SCALE[clampi(quality, 0, 3)] * clampf(density, 0.0, 1.5)))
	p.lifetime = spec.life
	p.randomness = 0.35
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-18, -5, -18), Vector3(36, 18, 36))
	p.process_material = _materials[preset]
	p.draw_pass_1 = _meshes[preset]
	p.emitting = false
	return p

static func _build_resources() -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.08, 0.35, 0.7, 1.0])
	gradient.colors = PackedColorArray([
		Color(1, 1, 1, 0.0),
		Color(1, 1, 1, 1.0),
		Color(1, 1, 1, 0.8),
		Color(1, 1, 1, 0.35),
		Color(1, 1, 1, 0.0)
	])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	for key in PRESETS:
		var spec: Dictionary = PRESETS[key]
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(0.58, 0.015, 0.12)
		pm.direction = Vector3(0.0, float(spec.up), 1.0).normalized()
		pm.spread = spec.spread
		pm.initial_velocity_min = spec.speed.x
		pm.initial_velocity_max = spec.speed.y
		pm.gravity = Vector3(0.0, -float(spec.gravity), 0.0)
		pm.damping_min = float(spec.drag) * 0.7
		pm.damping_max = float(spec.drag)
		pm.inherit_velocity_ratio = float(spec.get("inherit", 0.0))
		pm.angle_min = -180.0
		pm.angle_max = 180.0
		pm.angular_velocity_min = -100.0 if key == "leaves" else -40.0
		pm.angular_velocity_max = 100.0 if key == "leaves" else 40.0
		pm.scale_min = spec.scale.x
		pm.scale_max = spec.scale.y
		var curve := Curve.new()
		curve.max_value = maxf(1.0, float(spec.grow))
		curve.add_point(Vector2(0.0, 0.2))
		curve.add_point(Vector2(0.18, 0.8))
		curve.add_point(Vector2(0.5, 1.8))
		curve.add_point(Vector2(1.0, float(spec.grow)))
		var curve_tex := CurveTexture.new()
		curve_tex.curve = curve
		pm.scale_curve = curve_tex
		pm.color = spec.color
		pm.color_ramp = ramp
		var material := ShaderMaterial.new()
		material.shader = SHADER
		material.set_shader_parameter("soft_distance", 0.55)
		material.set_shader_parameter("camera_fade_distance", 3.0)
		material.set_shader_parameter("camera_fade_min", 0.85)
		material.set_shader_parameter("emissive", bool(spec.get("emission", false)))
		material.set_shader_parameter("leaf_shape", key == "leaves")
		material.set_shader_parameter("ambient_color", _current_ambient)
		material.set_shader_parameter("sun_color", _current_sun)
		material.set_shader_parameter("sun_direction", _current_sun_dir)
		var quad := QuadMesh.new()
		quad.size = Vector2(1.0, 1.0)
		quad.material = material
		_materials[key] = pm
		_meshes[key] = quad

static func clear_pools() -> void:
	_pools.clear()
	_materials.clear()
	_meshes.clear()
