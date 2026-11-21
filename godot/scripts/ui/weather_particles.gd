## Shared camera-following weather particles (rain streaks, road splashes, rain mist, snow, hail with
## ground bounce plane, and fog wisps) used by both RaceWorld (circuits) and OpenWorld (Brzeszcze).
class_name WeatherParticles
extends RefCounted

const RAIN_DROP := 0.7 ## m: a rain streak's length
## Share of the picture's height a streak may span before it starts to fade, and at which it is gone
const RAIN_FULL_SPAN := 0.06
const RAIN_GONE_SPAN := 0.16

const RAIN_AMOUNT := [180, 280, 380, 480]
const SPLASH_AMOUNT := [70, 110, 150, 190]
const MIST_AMOUNT := [18, 28, 38, 48]
const SNOW_AMOUNT := [70, 110, 150, 190]
const HAIL_AMOUNT := [120, 190, 260, 320]
const FOG_AMOUNT := [4, 7, 10, 12]

var rain: GPUParticles3D
var rain_material: StandardMaterial3D
var rain_splash: GPUParticles3D
var rain_mist: GPUParticles3D
var snow: GPUParticles3D
var snow_material: StandardMaterial3D
var hail: GPUParticles3D
var hail_material: StandardMaterial3D
var hail_ground: GPUParticlesCollisionBox3D
var fog: GPUParticles3D

func _init(parent: Node3D, quality: int = 2) -> void:
	var q := clampi(quality, 0, 3)

	var rain_mesh := QuadMesh.new()
	rain_mesh.size = Vector2(0.025, RAIN_DROP * 1.35)
	rain_material = StandardMaterial3D.new()
	rain_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rain_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	rain_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rain_material.albedo_color = Color(0.7, 0.8, 0.94, 0.34)
	rain_material.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA # see place()
	rain_mesh.material = rain_material
	var rain_process := ParticleProcessMaterial.new()
	rain_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	rain_process.emission_box_extents = Vector3(30.0, 20.0, 30.0)
	rain_process.direction = Vector3(-0.08, -1.0, 0.015)
	rain_process.spread = 2.0
	rain_process.gravity = Vector3(0.0, -18.0, 0.0)
	rain_process.initial_velocity_min = 25.0
	rain_process.initial_velocity_max = 34.0
	rain = GPUParticles3D.new()
	rain.name = "Rain"
	rain.amount = RAIN_AMOUNT[q]
	rain.lifetime = 0.9
	rain.local_coords = true
	rain.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	rain.process_material = rain_process
	rain.draw_pass_1 = rain_mesh
	rain.emitting = false
	parent.add_child(rain)

	# A low, low-alpha road layer reads as spray kicked off the surface without whitening the racing line.
	var splash_mesh := QuadMesh.new()
	splash_mesh.size = Vector2(0.045, 0.13)
	var splash_mat := StandardMaterial3D.new()
	splash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	splash_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	splash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	splash_mat.albedo_color = Color(0.72, 0.84, 0.93, 0.2)
	splash_mesh.material = splash_mat
	var splash_pm := ParticleProcessMaterial.new()
	splash_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	splash_pm.emission_box_extents = Vector3(22.0, 0.12, 28.0)
	splash_pm.direction = Vector3(0.0, 1.0, 0.0)
	splash_pm.spread = 30.0
	splash_pm.gravity = Vector3(0.0, -5.5, 0.0)
	splash_pm.initial_velocity_min = 0.8
	splash_pm.initial_velocity_max = 2.2
	splash_pm.angular_velocity_min = -90.0
	splash_pm.angular_velocity_max = 90.0
	rain_splash = GPUParticles3D.new()
	rain_splash.name = "RoadSpray"
	rain_splash.amount = SPLASH_AMOUNT[q]
	rain_splash.lifetime = 0.55
	rain_splash.local_coords = true
	rain_splash.visibility_aabb = AABB(Vector3(-30, -10, -35), Vector3(60, 24, 70))
	rain_splash.process_material = splash_pm
	rain_splash.draw_pass_1 = splash_mesh
	rain_splash.emitting = false
	parent.add_child(rain_splash)

	var mist_mesh := QuadMesh.new()
	mist_mesh.size = Vector2(1.2, 0.7)
	var mist_mat := StandardMaterial3D.new()
	mist_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mist_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mist_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mist_mat.albedo_color = Color(0.76, 0.84, 0.92, 0.08)
	mist_mesh.material = mist_mat
	var mist_pm := ParticleProcessMaterial.new()
	mist_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mist_pm.emission_box_extents = Vector3(26.0, 1.5, 30.0)
	mist_pm.direction = Vector3(0.0, 0.08, -1.0)
	mist_pm.spread = 14.0
	mist_pm.initial_velocity_min = 0.15
	mist_pm.initial_velocity_max = 0.55
	mist_pm.gravity = Vector3(0.0, -0.04, 0.0)
	mist_pm.damping_min = 0.1
	mist_pm.damping_max = 0.3
	mist_pm.scale_min = 0.7
	mist_pm.scale_max = 1.35
	rain_mist = GPUParticles3D.new()
	rain_mist.name = "RainMist"
	rain_mist.amount = MIST_AMOUNT[q]
	rain_mist.lifetime = 5.0
	rain_mist.local_coords = true
	rain_mist.visibility_aabb = AABB(Vector3(-34, -6, -38), Vector3(68, 16, 76))
	rain_mist.process_material = mist_pm
	rain_mist.draw_pass_1 = mist_mesh
	rain_mist.emitting = false
	parent.add_child(rain_mist)

	var snow_mesh := QuadMesh.new()
	snow_mesh.size = Vector2(0.08, 0.08)
	snow_material = StandardMaterial3D.new()
	snow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	snow_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	snow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	snow_material.albedo_color = Color(0.95, 0.97, 1.0, 0.85)
	snow_mesh.material = snow_material
	var snow_process := ParticleProcessMaterial.new()
	snow_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	snow_process.emission_box_extents = Vector3(32.0, 20.0, 32.0)
	snow_process.direction = Vector3(0.0, -1.0, 0.0)
	snow_process.spread = 15.0
	snow_process.gravity = Vector3(0.5, -2.5, 0.2)
	snow_process.initial_velocity_min = 1.2
	snow_process.initial_velocity_max = 2.8
	snow_process.angular_velocity_min = -90.0
	snow_process.angular_velocity_max = 90.0
	snow_process.angle_min = -180.0
	snow_process.angle_max = 180.0
	snow = GPUParticles3D.new()
	snow.name = "Snow"
	snow.amount = SNOW_AMOUNT[q]
	snow.lifetime = 2.5
	snow.local_coords = true
	snow.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	snow.process_material = snow_process
	snow.draw_pass_1 = snow_mesh
	snow.emitting = false
	parent.add_child(snow)

	var hail_mesh := QuadMesh.new()
	hail_mesh.size = Vector2(0.045, 0.09)
	hail_material = StandardMaterial3D.new()
	hail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hail_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	hail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hail_material.albedo_color = Color(0.92, 0.95, 1.0, 0.8)
	hail_material.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	hail_mesh.material = hail_material
	var hail_process := ParticleProcessMaterial.new()
	hail_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	hail_process.emission_box_extents = Vector3(34.0, 24.0, 34.0)
	hail_process.direction = Vector3(0.0, -1.0, 0.0)
	hail_process.spread = 4.0
	hail_process.gravity = Vector3(0.0, -32.0, 0.0)
	hail_process.initial_velocity_min = 22.0
	hail_process.initial_velocity_max = 35.0
	hail_process.angular_velocity_min = -280.0
	hail_process.angular_velocity_max = 280.0
	hail_process.angle_min = -180.0
	hail_process.angle_max = 180.0
	hail_process.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	hail_process.collision_friction = 0.15
	hail_process.collision_bounce = 0.58
	hail = GPUParticles3D.new()
	hail.name = "Hail"
	hail.amount = HAIL_AMOUNT[q]
	hail.lifetime = 0.85
	hail.local_coords = true
	hail.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	hail.process_material = hail_process
	hail.draw_pass_1 = hail_mesh
	hail.emitting = false
	parent.add_child(hail)

	hail_ground = GPUParticlesCollisionBox3D.new()
	hail_ground.name = "HailBouncePlane"
	hail_ground.size = Vector3(64.0, 0.25, 64.0)
	hail_ground.position.y = -2.4
	parent.add_child(hail_ground)

	fog = FxParticles.attach(parent, "fog_wisp", q, 0.38)
	if fog:
		fog.amount = FOG_AMOUNT[q]

## Overcast sky factor (0..1) from surface wetness and precipitation (rain, snow, hail).
static func overcast_amount(wet: float, rain_lvl: float, snow_lvl := 0.0, hail_lvl := 0.0) -> float:
	return clampf(wet * 0.62 + maxf(rain_lvl, maxf(snow_lvl, hail_lvl)) * 0.48, 0.0, 1.0)

## Updates particle counts for a graphics quality preset (0 Low .. 3 Ultra).
func set_quality(quality: int) -> void:
	var q := clampi(quality, 0, 3)
	if rain:
		rain.amount = RAIN_AMOUNT[q]
	if rain_splash:
		rain_splash.amount = SPLASH_AMOUNT[q]
	if rain_mist:
		rain_mist.amount = MIST_AMOUNT[q]
	if snow:
		snow.amount = SNOW_AMOUNT[q]
	if hail:
		hail.amount = HAIL_AMOUNT[q]
	if fog:
		fog.amount = FOG_AMOUNT[q]

## Turns emitters on/off and scales amount_ratio to match the active weather and quality preset.
func update(rain_lvl: float, snow_lvl: float, hail_lvl: float, fog_lvl: float, fog_mode: bool, quality: int) -> void:
	if rain:
		rain.emitting = rain_lvl > 0.03
		rain.amount_ratio = clampf(rain_lvl, 0.0, 1.0)
	if rain_splash:
		rain_splash.emitting = rain_lvl > 0.12
		rain_splash.amount_ratio = clampf(rain_lvl * (0.7 if quality < 2 else 1.0), 0.0, 1.0)
	if rain_mist:
		rain_mist.emitting = rain_lvl > 0.2
		rain_mist.amount_ratio = clampf(rain_lvl * (0.6 if quality < 2 else 0.85), 0.0, 1.0)
	if snow:
		snow.emitting = snow_lvl > 0.03
		snow.amount_ratio = clampf(snow_lvl, 0.0, 1.0)
	if hail:
		hail.emitting = hail_lvl > 0.03
		hail.amount_ratio = clampf(hail_lvl, 0.0, 1.0)
	if fog:
		var is_fog := fog_lvl > 0.1 or fog_mode
		fog.emitting = quality >= 1 and is_fog
		fog.amount_ratio = clampf(fog_lvl * 0.65 + (0.25 if fog_mode else 0.0), 0.0, 0.75)

## Keeps active weather showers round the camera. A streak just in front of the lens would cross much
## of the picture, and through a long lens one several metres off still would, so drops fade out nearer
## than where they span RAIN_FULL_SPAN of the picture, and for a long lens the shower moves out ahead.
func place(camera: Camera3D) -> void:
	if not camera or not camera.is_inside_tree():
		return
	var height_per_m := 2.0 * tan(deg_to_rad(camera.fov) * 0.5) # picture height (m) one metre away
	var full := RAIN_DROP / (RAIN_FULL_SPAN * height_per_m)
	var cam_pos := camera.global_position
	var fwd := camera.global_basis.z
	if rain and rain.emitting:
		rain_material.distance_fade_min_distance = RAIN_DROP / (RAIN_GONE_SPAN * height_per_m)
		rain_material.distance_fade_max_distance = full
		rain.global_position = cam_pos - fwd * clampf(full - 10.0, 0.0, 40.0)
	if rain_splash and rain_splash.emitting:
		rain_splash.global_position = cam_pos - fwd * 11.0 + Vector3(0.0, -3.0, 0.0)
	if rain_mist and rain_mist.emitting:
		rain_mist.global_position = cam_pos - fwd * 15.0 + Vector3(0.0, -2.5, 0.0)
	if snow and snow.emitting:
		snow.global_position = cam_pos - fwd * clampf(full - 10.0, 0.0, 30.0)
	if hail and hail.emitting:
		if hail_material:
			hail_material.distance_fade_min_distance = RAIN_DROP / (RAIN_GONE_SPAN * height_per_m)
			hail_material.distance_fade_max_distance = full
		hail.global_position = cam_pos - fwd * clampf(full - 10.0, 0.0, 40.0)
		if hail_ground:
			hail_ground.global_position = cam_pos - fwd * 12.0 + Vector3(0.0, -2.4, 0.0)
	if fog and fog.emitting:
		fog.global_position = cam_pos - fwd * 12.0 + Vector3(0.0, -3.0, 0.0)

## True if any weather particle emitter is currently emitting.
func any_emitting() -> bool:
	for p in [rain, rain_splash, rain_mist, snow, hail, fog]:
		if p and p.emitting:
			return true
	return false
