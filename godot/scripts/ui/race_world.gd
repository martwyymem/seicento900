## 3D Circuit World and Visual Simulation for Seicento Cup (port of js/render3d.js).
## Features procedural track and venue scenery, reactive start lights, rain and time-of-day lighting with
## the reference June sun, wet-surface materials, racing line assist, skidmarks, pooled night headlight
## beams and five camera modes. Cars are drawn between simulation ticks so motion stays smooth.
## The sky, road, ground, trees, water and buildings use the shaders in res://shaders, and optional HDRI
## skies, photo textures and tree models from res://assets are picked up when present (godot/ASSETS.md).
extends Node3D

const CAR_SCENE := preload("res://scripts/ui/race_car_visual.tscn")
const CAR_VISUAL := preload("res://scripts/ui/race_car_visual.gd")
const WORLD_ASSETS := preload("res://scripts/ui/world_assets.gd")
const SKY_SHADER := preload("res://shaders/sky.gdshader")
const ROAD_SHADER := preload("res://shaders/road.gdshader")
const GROUND_SHADER := preload("res://shaders/ground.gdshader")
const FOLIAGE_SHADER := preload("res://shaders/foliage.gdshader")
const WATER_SHADER := preload("res://shaders/water.gdshader")
const FACADE_SHADER := preload("res://shaders/facade.gdshader")
const CROWD_SHADER := preload("res://shaders/crowd.gdshader")
const ALTITUDE_SCALE := 0.25
const BEAM_COUNT := 4 ## headlight spotlights handed to the cars nearest the camera after dark
const BEAM_REACH := 180.0
const SKID_CAPACITY := 1600

# Sky and light palette (parsed once, not every frame).
const SKY_TOP_NIGHT := Color("#030611")
const SKY_TOP_DAY := Color("#4a709c")
const SKY_TOP_OVERCAST := Color("#68727e")
const HORIZON_NIGHT := Color("#121b2c")
const HORIZON_DAY := Color("#a2b6cb")
const HORIZON_OVERCAST := Color("#a2a7ad")
const DUSK_GLOW := Color("#e98559")
const GROUND_NIGHT := Color("#090e17")
const GROUND_DAY := Color("#222822")
const AMBIENT_NIGHT := Color("#8093b5")
const SUN_NIGHT := Color("#8295c5")
const SUN_DAY := Color("#fff3dd")
const ASPHALT_DRY := Color("#26292b")
const ASPHALT_WET := Color("#13191f")
const RUNOFF_WET := Color("#687582")
const START_LIGHT_ON := Color("#ff1810")
const START_LIGHT_OFF := Color("#220404")
const CLOUD_LIT := Color("#fbf8f2")
const CLOUD_SHADE := Color("#8f9aa8")
const CLOUD_NIGHT := Color("#1a2130")
const FOG_DAY := Color("#b9c6d3")
const FOG_NIGHT := Color("#0d1420")
const FOG_RAIN := Color("#8d969f")

## Graphics quality presets (apply_graphics): 0 Low, 1 Medium, 2 High, 3 Ultra.
const QUALITY_NAMES := ["LOW", "MEDIUM", "HIGH", "ULTRA"]
const TREE_SCALE := [0.45, 0.75, 1.0, 1.5]

var race: Race
var track: Track
var track_root: Node3D
var cars_root: Node3D
var skidmarks_root: Node3D
var camera: Camera3D

var visuals: Dictionary = {}
var world_center := Vector2.ZERO
var elevation_base := 0.0
var overview_target := Vector3.ZERO
var overview_distance := 1000.0
var overview := true
var world_environment: Environment
var sky_material: ShaderMaterial
var sun: DirectionalLight3D
var asphalt_material: ShaderMaterial
var runoff_material: ShaderMaterial
var rain_particles: GPUParticles3D
var quality := 2
var assets: RefCounted ## world_assets.gd, shared by every track
## Materials that follow the weather ("wet"/"rain") or nightfall ("night") uniforms.
var _wet_materials: Array[ShaderMaterial] = []
var _night_materials: Array[ShaderMaterial] = []
var _sky_textures := {} ## sky uniform -> path currently bound
static var _noise := {}

## Camera modes:
## 0 = Chase | 1 = Far Chase | 2 = Roof cam | 3 = Trackside TV | 4 = Bird's-eye | 5 = full-track overview
var camera_mode := 0
const CAMERA_NAMES := ["CHASE", "FAR CHASE", "ROOF CAM", "TRACKSIDE TV", "BIRD'S-EYE", "FULL TRACK"]
## Fraction of a simulation tick elapsed since the last step (set by the game loop each frame).
var render_alpha := 1.0
## The next camera update jumps straight to its target (race start).
var camera_snap := true
var _cam_head := 0.0
var _focus_pos := Vector3.ZERO
var _focus_heading := 0.0
var _focus_s := 0.0

## Trackside TV camera positions along the track, and their distance along it
var tv_cameras: Array[Vector3] = []
var tv_camera_s := PackedFloat64Array()
var _tv_index := -1

## Start gantry lights
var start_lights: Array[MeshInstance3D] = []
var _lights_lit := -1

## Racing line assist
var racing_line_node: MeshInstance3D
var show_racing_line := true

## Night headlight beams and the per-frame nearest-car ranking that assigns them (reused, no allocation)
var beams: Array[SpotLight3D] = []
var _rank_cars: Array[RaceCar] = []
var _rank_d2 := PackedFloat32Array()

## Skidmarks: a ring of flat quads in one MultiMesh, one instance written per new mark
var skid_multimesh: MultiMesh
var _skid_instance: MultiMeshInstance3D
var _skid_next := 0
var _skid_used := 0
var _skid_last := {} ## car id -> rear-axle position of the car's last mark

var _atmos_key := Vector3(-1.0, -1.0, -1.0)
var night := 0.0

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://graphics.cfg") == OK:
		quality = clampi(int(cfg.get_value("graphics", "quality", quality)), 0, QUALITY_NAMES.size() - 1)
	_build_environment()
	_build_beams()
	apply_graphics(quality)

func _exit_tree() -> void:
	if assets:
		assets.finish()

## Rendering cost preset: 0 Low, 1 Medium, 2 High (default), 3 Ultra. The options page's SSAO, shadow and
## reflection switches still apply on top (they set those Environment/light flags afterwards).
## Tree density follows the preset from the next track that is built.
func apply_graphics(level: int) -> void:
	quality = clampi(level, 0, QUALITY_NAMES.size() - 1)
	var vp := get_viewport()
	if vp:
		vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][quality]
		vp.use_debanding = true
		vp.anisotropic_filtering_level = [Viewport.ANISOTROPY_2X, Viewport.ANISOTROPY_4X, Viewport.ANISOTROPY_8X, Viewport.ANISOTROPY_16X][quality]
		vp.mesh_lod_threshold = [4.0, 2.0, 1.0, 0.5][quality]
	RenderingServer.directional_shadow_atlas_set_size([2048, 4096, 4096, 8192][quality], true)
	RenderingServer.directional_soft_shadow_filter_set_quality([
		RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH][quality])
	if sun:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if quality == 0 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.directional_shadow_max_distance = [220.0, 320.0, 420.0, 560.0][quality]
		# a real sun is half a degree across: soft, contact-hardening shadows on the top preset
		sun.light_angular_distance = 0.5 if quality >= 3 else 0.0
	if world_environment:
		world_environment.ssil_enabled = quality >= 2
		world_environment.sky.radiance_size = Sky.RADIANCE_SIZE_128 if quality < 2 else Sky.RADIANCE_SIZE_256
		world_environment.volumetric_fog_enabled = false
		_atmos_key = Vector3(-1.0, -1.0, -1.0)

func set_track(value: Track) -> void:
	track = value
	race = null
	overview = true

	for n in [track_root, cars_root, skidmarks_root]:
		if is_instance_valid(n):
			n.queue_free()

	track_root = Node3D.new()
	track_root.name = "Track"
	add_child(track_root)

	cars_root = Node3D.new()
	cars_root.name = "Cars"
	add_child(cars_root)

	skidmarks_root = Node3D.new()
	skidmarks_root.name = "Skidmarks"
	add_child(skidmarks_root)

	visuals.clear()
	start_lights.clear()
	tv_cameras.clear()
	tv_camera_s.clear()
	_wet_materials.clear()
	_night_materials.clear()
	_lights_lit = -1
	_skid_instance = null
	_atmos_key = Vector3(-1.0, -1.0, -1.0) # the new materials pick up the current weather

	_build_track()
	_reset_skids()
	position_overview()

func set_race(value: Race) -> void:
	race = value
	if track != value.track:
		set_track(value.track)
		race = value
	# a restart on the same circuit reuses the scenery but not the previous field
	for old in visuals.values():
		old.queue_free()
	visuals.clear()
	_reset_skids()

	for car in value.cars:
		var visual := CAR_SCENE.instantiate()
		visuals[car.id] = visual
		cars_root.add_child(visual)
		visual.set_paint(car.color)
		visual.car_number = car.number
		visual.is_player = car.is_player
		visual.set_stripes(car.stripes)
	_rank_cars.resize(value.cars.size())
	_rank_d2.resize(value.cars.size())

	overview = false
	camera_snap = true
	_tv_index = -1
	_lights_lit = -1

func _process(delta: float) -> void:
	if not track or not camera:
		return

	if overview or not race:
		_update_atmosphere(14.0, 0.0, 0.0)
		_hide_beams()
		camera.global_position = camera.global_position.lerp(overview_target, 1.0 - exp(-2.4 * delta))
		camera.look_at(Vector3(overview_target.x, 0, overview_target.z), Vector3.FORWARD)
		return
	_update_atmosphere(race.time_of_day, race.weather.wet, race.weather.rain)
	CAR_VISUAL.set_night(night)

	var focus := race.player
	var a := clampf(render_alpha, 0.0, 1.0)
	for car in race.cars:
		var visual = visuals.get(car.id)
		if not visual:
			continue
		visual.visible = not car.dnf or car.speed > 0.1
		if not visual.visible:
			continue
		# draw between the last two simulation ticks so motion is smooth at any refresh rate
		var x := car.x
		var y := car.y
		var heading := car.heading
		var s := car.s
		if car.has_prev and a < 1.0:
			var b := 1.0 - a
			x = car.px * b + car.x * a
			y = car.py * b + car.y * a
			heading -= SimUtil.wrap_angle(car.heading - car.ph) * b
			s = track.wrap_s(s - track.rel(s - car.ps) * b)
		var p := _world_pos(x, y, s, car.d)
		visual.position = p
		# pitch with the (height-scaled) road gradient along the car's heading
		var grade := atan(track.sample(track.GRADE, s) * ALTITUDE_SCALE * cos(heading - track.heading(s)))
		visual.grade_pitch += (grade - visual.grade_pitch) * minf(1.0, delta * 8.0)
		visual.basis = _surface_tilt(s, car.d) * Basis(Vector3.UP, -heading - PI / 2.0) * Basis(Vector3.RIGHT, visual.grade_pitch)
		visual.sync(car, delta, track.curvature(s), night, car.finished and car != focus)
		if car == focus:
			_focus_pos = p
			_focus_heading = heading
			_focus_s = s
		if car.control == "free" and (car.slip > 0.42 or (car.brake_on and car.speed > 8.0)):
			_add_skid(car.id, p, heading)
		elif _skid_last.has(car.id):
			_skid_last.erase(car.id)

	_update_start_lights()
	_update_camera(delta)
	_update_beams()

func _update_atmosphere(hour: float, wet: float, rain: float) -> void:
	if not world_environment or not sky_material or not sun:
		return
	if rain_particles and camera:
		rain_particles.global_position = camera.global_position
	# the sky only needs repainting when the hour or the weather has visibly moved on
	var key := Vector3(hour, wet, rain)
	if absf(key.x - _atmos_key.x) < 0.002 and absf(key.y - _atmos_key.y) < 0.002 and absf(key.z - _atmos_key.z) < 0.002:
		return
	var first := _atmos_key.x < 0.0
	_atmos_key = key
	var sun_v := SimUtil.sun_at(hour)
	var el := sun_v[0]
	var day_t := sun_v[2]
	night = 1.0 - day_t
	var dusk := 1.0 - clampf(absf(el) / 12.0, 0.0, 1.0)
	var overcast := clampf(wet * 0.62 + rain * 0.48, 0.0, 1.0)
	var top := SKY_TOP_NIGHT.lerp(SKY_TOP_DAY, day_t).lerp(SKY_TOP_OVERCAST, overcast * 0.72 * day_t)
	var horizon := HORIZON_NIGHT.lerp(HORIZON_DAY, day_t).lerp(HORIZON_OVERCAST, overcast * 0.7 * day_t)
	var glow := dusk * (1.0 - overcast)
	horizon = horizon.lerp(DUSK_GLOW, glow * 0.55)
	var az := deg_to_rad(sun_v[1])
	# the sun where it really is; after dark a high, dim moonlight instead of light from under the ground
	var light_el := deg_to_rad(lerpf(34.0, maxf(el, 10.0), day_t))
	var toward := _sky_dir(light_el, az)
	sun.basis = Basis.looking_at(-toward, Vector3.UP)

	sky_material.set_shader_parameter("top_color", top)
	sky_material.set_shader_parameter("horizon_color", horizon)
	sky_material.set_shader_parameter("ground_color", GROUND_NIGHT.lerp(GROUND_DAY, day_t))
	sky_material.set_shader_parameter("glow_color", DUSK_GLOW)
	sky_material.set_shader_parameter("glow_amount", glow)
	sky_material.set_shader_parameter("night", night)
	sky_material.set_shader_parameter("overcast", overcast)
	sky_material.set_shader_parameter("sun_dir", _sky_dir(deg_to_rad(el), az))
	sky_material.set_shader_parameter("moon_dir", _sky_dir(deg_to_rad(34.0), az))
	sky_material.set_shader_parameter("sun_color", SUN_DAY.lerp(DUSK_GLOW, glow * 0.7))
	sky_material.set_shader_parameter("star_amount", smoothstep(0.35, 0.95, night))
	sky_material.set_shader_parameter("cloud_lit", CLOUD_NIGHT.lerp(CLOUD_LIT, day_t).lerp(HORIZON_OVERCAST, overcast * 0.5 * day_t))
	sky_material.set_shader_parameter("cloud_shade", (CLOUD_NIGHT * 0.6).lerp(CLOUD_SHADE, day_t).lerp(SKY_TOP_OVERCAST.darkened(0.2), overcast * day_t))
	var sky_luma := (top.srgb_to_linear().get_luminance() + horizon.srgb_to_linear().get_luminance() * 2.0) / 3.0
	_update_sky_hdri(el, az, hour, day_t, overcast, sky_luma, first)

	world_environment.ambient_light_energy = lerpf(0.3, 1.0, day_t) * (1.0 - overcast * 0.2)
	world_environment.ambient_light_color = AMBIENT_NIGHT.lerp(Color.WHITE, day_t)
	sun.light_energy = lerpf(0.1, 1.6, day_t) * (1.0 - overcast * 0.62)
	sun.light_color = SUN_NIGHT.lerp(SUN_DAY, day_t).lerp(DUSK_GLOW, glow * 0.45)
	sun.shadow_opacity = lerpf(0.55, 1.0, day_t) * (1.0 - overcast * 0.45)
	# haze thickens in the rain and takes on the horizon colour, so the distance melts into the sky
	world_environment.fog_light_color = FOG_NIGHT.lerp(horizon, day_t).lerp(FOG_RAIN * lerpf(0.15, 1.0, day_t), overcast * 0.6)
	world_environment.fog_density = 0.00032 + 0.00045 * overcast + 0.0024 * rain
	world_environment.fog_sun_scatter = 0.18 * glow + 0.05 * (1.0 - overcast) * day_t
	world_environment.glow_hdr_threshold = lerpf(1.0, 0.75, night)
	# volumetric fog shows the headlight beams in the rain and after dark (High and Ultra only)
	var volumetric := quality >= 2 and (rain > 0.08 or night > 0.45)
	if world_environment.volumetric_fog_enabled != volumetric:
		world_environment.volumetric_fog_enabled = volumetric
	world_environment.volumetric_fog_density = 0.004 + 0.018 * rain + 0.004 * night
	world_environment.volumetric_fog_albedo = Color(0.9, 0.92, 0.95).lerp(Color(0.62, 0.66, 0.72), night)
	for m in _wet_materials:
		m.set_shader_parameter("wet", wet)
		m.set_shader_parameter("rain", rain)
	for m in _night_materials:
		m.set_shader_parameter("night", night)
	if rain_particles:
		rain_particles.emitting = rain > 0.03
		rain_particles.amount_ratio = clampf(rain, 0.0, 1.0)

static func _sky_dir(el: float, az: float) -> Vector3:
	return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))

## Blends the two HDRI skies nearest the sun's elevation (same half of the day where the file names say
## so), each turned so its own sun sits where the game's sun is, and brought to the brightness of the
## procedural sky at that hour. Overcast HDRIs take over in the wet; a night HDRI (if any) after dark.
func _update_sky_hdri(el: float, az: float, hour: float, day_t: float, overcast: float, target: float, wait: bool) -> void:
	if assets == null or not assets.has_skies():
		sky_material.set_shader_parameter("hdri_mix", 0.0)
		sky_material.set_shader_parameter("hdri_o_mix", 0.0)
		return
	var half := "am" if hour < 13.75 else "pm"
	var ladder: Array = []
	for n in assets.skies_of("night"):
		var entry: Dictionary = n.duplicate()
		entry.el = -14.0
		ladder.append(entry)
	var clear: Array = assets.skies_of("clear").filter(func(e): return e.half == "" or e.half == half)
	if clear.is_empty():
		clear = assets.skies_of("clear")
	ladder.append_array(clear)
	var mix := 0.0
	if not ladder.is_empty():
		var a: Dictionary = ladder[0]
		var b: Dictionary = a
		var t := 0.0
		if el <= a.el:
			mix = 1.0 if a.kind == "night" else smoothstep(a.el - 7.0, a.el, el)
		else:
			mix = 1.0
			for i in ladder.size():
				a = ladder[i]
				b = a
				if i + 1 < ladder.size() and el < ladder[i + 1].el:
					b = ladder[i + 1]
					t = (el - a.el) / maxf(b.el - a.el, 0.01)
					break
		if _bind_sky("hdri_a", a.path, wait) and _bind_sky("hdri_b", b.path, wait):
			var gain_boost := lerpf(1.0, 0.6, night) # night HDRIs are kept a little darker than the palette
			sky_material.set_shader_parameter("hdri_rot_a", a.az - az)
			sky_material.set_shader_parameter("hdri_rot_b", b.az - az)
			sky_material.set_shader_parameter("hdri_gain_a", target / maxf(a.mean, 1e-5) * gain_boost)
			sky_material.set_shader_parameter("hdri_gain_b", target / maxf(b.mean, 1e-5) * gain_boost)
			sky_material.set_shader_parameter("hdri_ab", smoothstep(0.0, 1.0, t))
			sky_material.set_shader_parameter("hdri_mix", mix)
	var grey: Array = assets.skies_of("overcast")
	var o_mix := 0.0
	if not grey.is_empty():
		var pick: Dictionary = grey[absi(hash(track.cfg.key if track else "")) % grey.size()]
		o_mix = smoothstep(0.18, 0.7, overcast) * clampf(day_t * 1.5, 0.0, 1.0)
		if o_mix > 0.0 and _bind_sky("hdri_o", pick.path, wait):
			sky_material.set_shader_parameter("hdri_gain_o", target / maxf(pick.mean, 1e-5))
		elif _sky_textures.get("hdri_o", "") != pick.path:
			o_mix = 0.0
	sky_material.set_shader_parameter("hdri_o_mix", o_mix)

func _bind_sky(uniform: String, path: String, wait: bool) -> bool:
	if _sky_textures.get(uniform, "") == path:
		return true
	var tex: Texture2D = assets.sky_texture(path, wait or not _sky_textures.has(uniform))
	if tex == null:
		return false # still loading on a worker thread: bound at a later atmosphere update
	sky_material.set_shader_parameter(uniform, tex)
	_sky_textures[uniform] = path
	return true

## Five red lights come on one per second on the grid and all go out at the start.
func _update_start_lights() -> void:
	if start_lights.is_empty():
		return
	var lit := clampi(int(floorf(race.clock)), 0, 5) if race.phase == "countdown" else 0
	if lit == _lights_lit:
		return
	_lights_lit = lit
	for i in start_lights.size():
		var mat := start_lights[i].material_override as StandardMaterial3D
		if mat:
			var on := i < lit
			mat.albedo_color = START_LIGHT_ON if on else START_LIGHT_OFF
			mat.emission_energy_multiplier = 4.0 if on else 0.0

## Road height (world units) at distance s along the centreline.
func _road_y(s: float) -> float:
	return (track.sample(track.H, s) - elevation_base) * ALTITUDE_SCALE + 0.09

static func _ease(rate: float, delta: float, snap: bool) -> float:
	return 1.0 if snap else 1.0 - exp(-delta * rate)

func _update_camera(delta: float) -> void:
	var player := race.player
	var p := _focus_pos
	var snap := camera_snap
	camera_snap = false
	if camera_mode == 5:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = overview_distance * 1.65
		camera.far = maxf(camera.far, overview_distance * 4.0)
		camera.global_position = Vector3(0.0, overview_distance * 1.7, 0.0)
		camera.look_at(Vector3.ZERO, Vector3.FORWARD)
		return
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE

	# the camera swings round after the car rather than being bolted to it
	_cam_head += wrapf(_focus_heading - _cam_head, -PI, PI) * _ease(30.0 if camera_mode == 2 else 5.0, delta, snap)
	var fwd := Vector3(cos(_cam_head), 0.0, sin(_cam_head))
	var v := Vector2(player.vx, player.vy).length()
	var fov := 60.0 + minf(14.0, v * 0.35)

	match camera_mode:
		0, 1: # chase / far chase
			var far := camera_mode == 1
			var dist := 11.5 if far else 6.2
			var height := 4.6 if far else 2.2
			var want := p - fwd * dist + Vector3.UP * height
			# never dip under the road over a crest
			want.y = maxf(want.y, _road_y(_focus_s - dist) + height * 0.6)
			camera.global_position = camera.global_position.lerp(want, _ease(7.0 if far else 10.0, delta, snap))
			camera.look_at(p + fwd * (10.0 if far else 7.0) + Vector3.UP * (0.6 if far else 1.0), Vector3.UP)
		2: # roof cam
			camera.global_position = p + fwd * 0.25 + Vector3.UP * 1.3
			var ahead := p + fwd * 30.0
			ahead.y = _road_y(_focus_s + 30.0) + 1.0
			camera.look_at(ahead, Vector3.UP)
			fov += 6.0
		3: # trackside TV: a camera ahead of the car picks it up, follows it past, then cuts to the next
			if tv_cameras.is_empty():
				return
			if snap or _tv_index < 0 or track.rel(_focus_s - tv_camera_s[_tv_index]) > 45.0:
				var best := 0
				var best_ahead := INF
				for i in tv_camera_s.size():
					var ahead_m := fposmod(tv_camera_s[i] - _focus_s, track.L)
					if ahead_m >= 40.0 and ahead_m < best_ahead:
						best_ahead = ahead_m
						best = i
				_tv_index = best
			camera.global_position = tv_cameras[_tv_index]
			var target := p + Vector3.UP * 0.8
			camera.look_at(target, Vector3.UP)
			fov = clampf(rad_to_deg(2.0 * atan(12.0 / maxf(1.0, camera.global_position.distance_to(target)))), 16.0, 55.0)
			camera.fov = fov
			return
		4: # bird's-eye, car pointing up the screen
			var want := p + Vector3.UP * (55.0 + v * 0.8)
			camera.global_position = camera.global_position.lerp(want, _ease(8.0, delta, snap))
			camera.look_at(p, fwd)
			fov = 55.0
	camera.fov += (fov - camera.fov) * _ease(4.0, delta, snap)

func cycle_camera() -> String:
	camera_mode = (camera_mode + 1) % 5
	return CAMERA_NAMES[camera_mode]

func _build_beams() -> void:
	for i in BEAM_COUNT:
		var beam := SpotLight3D.new()
		beam.name = "HeadlightBeam%d" % i
		beam.light_color = Color("#fff1d6")
		beam.spot_range = 130.0
		beam.spot_angle = 26.0
		beam.spot_angle_attenuation = 1.8
		beam.shadow_enabled = false
		beam.visible = false
		add_child(beam)
		beams.append(beam)

func _hide_beams() -> void:
	for beam in beams:
		beam.visible = false

## After dark the pooled beams go to the cars nearest the camera.
func _update_beams() -> void:
	if night < 0.05 or beams.is_empty():
		_hide_beams()
		return
	var cam := camera.global_position
	var m := 0
	for car in race.cars:
		if car.dnf or m >= _rank_cars.size():
			continue
		var visual = visuals.get(car.id)
		if not visual:
			continue
		_rank_cars[m] = car
		_rank_d2[m] = cam.distance_squared_to(visual.position)
		m += 1
	# nearly sorted from frame to frame, so an insertion sort settles in about O(m)
	for i in range(1, m):
		var cur := _rank_cars[i]
		var cur_d2 := _rank_d2[i]
		var j := i - 1
		while j >= 0 and _rank_d2[j] > cur_d2:
			_rank_cars[j + 1] = _rank_cars[j]
			_rank_d2[j + 1] = _rank_d2[j]
			j -= 1
		_rank_cars[j + 1] = cur
		_rank_d2[j + 1] = cur_d2
	for i in beams.size():
		var beam := beams[i]
		if i >= m or _rank_d2[i] > BEAM_REACH * BEAM_REACH:
			beam.visible = false
			continue
		var visual: Node3D = visuals[_rank_cars[i].id]
		var fwd := -visual.basis.z
		var from := visual.position + fwd * 1.9 + Vector3.UP * 0.66
		beam.look_at_from_position(from, visual.position + fwd * 26.0 - Vector3.UP * 0.4, Vector3.UP)
		beam.light_energy = 24.0 * night
		beam.visible = true

func toggle_racing_line() -> bool:
	show_racing_line = not show_racing_line
	if is_instance_valid(racing_line_node):
		racing_line_node.visible = show_racing_line
	return show_racing_line

func _build_environment() -> void:
	var env := WorldEnvironment.new()
	world_environment = Environment.new()
	world_environment.background_mode = Environment.BG_SKY

	var sky := Sky.new()
	sky_material = ShaderMaterial.new()
	sky_material.shader = SKY_SHADER
	sky_material.set_shader_parameter("cloud_noise", noise_texture("clouds"))
	sky.sky_material = sky_material
	# drifting clouds and twinkling stars need the sky redrawn every frame
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	world_environment.sky = sky

	world_environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	world_environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	world_environment.ambient_light_energy = 0.65
	# AgX keeps bright skies, headlights and sunsets from clipping to flat white
	world_environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	world_environment.tonemap_exposure = 1.05
	world_environment.tonemap_agx_contrast = 1.25
	world_environment.ssao_enabled = true
	world_environment.ssao_radius = 1.6
	world_environment.ssao_intensity = 1.6
	world_environment.ssao_detail = 0.6
	world_environment.ssil_radius = 4.0
	world_environment.ssil_intensity = 0.8
	world_environment.ssr_max_steps = 48
	world_environment.ssr_fade_in = 0.12
	world_environment.ssr_fade_out = 1.6
	world_environment.ssr_depth_tolerance = 0.3
	world_environment.glow_enabled = true
	world_environment.glow_normalized = true
	world_environment.glow_intensity = 0.55
	world_environment.glow_strength = 1.0
	world_environment.glow_bloom = 0.03
	world_environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	world_environment.glow_hdr_threshold = 1.0
	world_environment.fog_enabled = true
	world_environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	world_environment.fog_density = 0.00035
	world_environment.fog_aerial_perspective = 0.55
	world_environment.fog_sky_affect = 0.0
	world_environment.volumetric_fog_length = 90.0
	world_environment.volumetric_fog_anisotropy = 0.6
	world_environment.volumetric_fog_sky_affect = 0.0
	world_environment.adjustment_enabled = true
	world_environment.adjustment_saturation = 1.1
	world_environment.adjustment_contrast = 1.04
	env.environment = world_environment
	add_child(env)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-46, -32, 0)
	sun.light_color = Color("#fffcf0")
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.shadow_normal_bias = 1.4
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 420.0
	sun.directional_shadow_blend_splits = true
	add_child(sun)

	var rain_mesh := QuadMesh.new()
	rain_mesh.size = Vector2(0.035, 0.7)
	var rain_material := StandardMaterial3D.new()
	rain_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rain_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	rain_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rain_material.albedo_color = Color(0.72, 0.82, 0.94, 0.42)
	rain_mesh.material = rain_material
	var rain_process := ParticleProcessMaterial.new()
	rain_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	rain_process.emission_box_extents = Vector3(34.0, 24.0, 34.0)
	rain_process.direction = Vector3(0.0, -1.0, 0.0)
	rain_process.spread = 4.0
	rain_process.gravity = Vector3(0.0, -24.0, 0.0)
	rain_process.initial_velocity_min = 17.0
	rain_process.initial_velocity_max = 25.0
	rain_particles = GPUParticles3D.new()
	rain_particles.name = "Rain"
	rain_particles.amount = 700
	rain_particles.lifetime = 1.2
	rain_particles.local_coords = true
	rain_particles.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	rain_particles.process_material = rain_process
	rain_particles.draw_pass_1 = rain_mesh
	rain_particles.emitting = false
	add_child(rain_particles)

	camera = Camera3D.new()
	camera.name = "RaceCamera"
	camera.current = true
	camera.fov = 68.0
	add_child(camera)

func _build_track() -> void:
	var b := track.bounds
	world_center = Vector2((b[0] + b[2]) * 0.5, (b[1] + b[3]) * 0.5)
	elevation_base = track.h_min
	var extent := maxf(b[2] - b[0], b[3] - b[1])
	overview_distance = maxf(220.0, extent * 0.78)

	# 1. Base terrain ground plane
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(extent * 2.8, extent * 2.8)
	ground.mesh = plane
	ground.position = Vector3(0, -1.8, 0)
	var far_ground := _surface_material(GROUND_SHADER, "grass" if track.cfg.theme != "city" else "")
	far_ground.set_shader_parameter("base_color", Color("#364a38") if track.cfg.theme != "city" else Color("#aaa18d"))
	ground.material_override = far_ground
	track_root.add_child(ground)
	_build_terrain(ground)

	# 2. Track ribbons (Runoff, Edge line, Asphalt road)
	var ro_width: float = track.width + track.cfg.runoff * 2.0
	var surface := track.cfg.runoff_surface
	runoff_material = _surface_material(ROAD_SHADER if surface == "asphalt" else GROUND_SHADER, surface)
	runoff_material.set_shader_parameter("base_color", track.cfg.runoff_color)
	if surface == "asphalt":
		runoff_material.set_shader_parameter("half_width", ro_width * 0.5)
		runoff_material.set_shader_parameter("rubber", 0.0)
		runoff_material.set_shader_parameter("patches", 0.4)
	else:
		runoff_material.set_shader_parameter("is_runoff", true)
		runoff_material.set_shader_parameter("track_half", track.half)
		runoff_material.set_shader_parameter("tuft", 1.0 if surface == "grass" else 0.35)
		runoff_material.set_shader_parameter("worn_color", Color("#6b6152") if surface == "grass" else track.cfg.runoff_color.darkened(0.15))
	asphalt_material = _surface_material(ROAD_SHADER, "asphalt")
	asphalt_material.set_shader_parameter("base_color", ASPHALT_DRY)
	asphalt_material.set_shader_parameter("half_width", track.half)
	_add_ribbon(ro_width, 0.01, runoff_material, "Runoff")
	_add_ribbon(track.width, 0.04, asphalt_material, "Asphalt")
	_add_edge_lines()

	# 3. Alternating Red & White Kerbs on corner apexes
	_build_kerbs()

	# 4. Start / finish line and overhead gantry with lights
	_build_start_finish_gantry()

	# 5. Pit lane and pit wall
	_build_pit_lane()

	# 6. Armco barriers / guardrails along runoff edges
	_build_barriers()

	# 7. Racing line assist
	_build_racing_line()

	# 8. Roadside trees
	_build_trees(extent)

	# 9. Circuit-specific venue structures
	_build_grandstands()
	if track.cfg.theme == "city":
		_build_city_blocks()
		if track.cfg.sea:
			_build_monaco_harbor(extent)
			_build_casino_landmark()

	# 10. Setup TV cameras around track
	_setup_tv_cameras()

func _build_terrain(ground: MeshInstance3D) -> void:
	if typeof(track.grid) != TYPE_DICTIONARY:
		return
	var grid: Dictionary = track.grid
	var dem: Array = grid.get("h", [])
	var dem_nx := int(grid.get("nx", 0))
	var dem_nz := int(grid.get("ny", 0))
	var dem_step := float(grid.get("step", 0.0))
	if dem.size() != dem_nx * dem_nz or dem_nx < 2 or dem_nz < 2 or dem_step <= 0.0:
		return

	var bounds := track.bounds
	var band := 175.0
	var fine := maxf(track.cfg.terrain_fine * 2.0, 18.0)
	var margin := band + fine * 2.0
	var x0 := bounds[0] - margin
	var z0 := bounds[1] - margin
	var nx := ceili((bounds[2] - bounds[0] + margin * 2.0) / fine)
	var nz := ceili((bounds[3] - bounds[1] + margin * 2.0) / fine)
	var row := nx + 1
	var grid_size := row * (nz + 1)
	var nearest_distance := PackedFloat32Array()
	nearest_distance.resize(grid_size)
	nearest_distance.fill(INF)
	var nearest_index := PackedInt32Array()
	nearest_index.resize(grid_size)
	nearest_index.fill(-1)
	var height_cap := PackedFloat32Array()
	height_cap.resize(grid_size)
	height_cap.fill(INF)
	var radius := ceili(band / fine) + 1
	var radius_squared := float(radius * radius)
	var road_clearance := track.half + track.cfg.runoff + 3.0

	# Splat nearby centreline samples onto a compact grid; this keeps terrain under every road section.
	for sample_index in track.n:
		var cx := roundi((track.X[sample_index] - x0) / fine)
		var cz := roundi((track.Y[sample_index] - z0) / fine)
		for dz in range(-radius, radius + 1):
			var grid_z := cz + dz
			if grid_z < 0 or grid_z > nz or float(dz * dz) > radius_squared:
				continue
			var dx_limit := floori(sqrt(radius_squared - float(dz * dz)))
			for dx in range(-dx_limit, dx_limit + 1):
				var grid_x := cx + dx
				if grid_x < 0 or grid_x > nx:
					continue
				var world_x := x0 + grid_x * fine
				var world_z := z0 + grid_z * fine
				var ddx := world_x - track.X[sample_index]
				var ddz := world_z - track.Y[sample_index]
				var distance_squared := ddx * ddx + ddz * ddz
				var cell := grid_z * row + grid_x
				var distance := sqrt(distance_squared)
				var track_height := track.H[sample_index] - elevation_base
				height_cap[cell] = minf(height_cap[cell], track_height - 0.35 + maxf(0.0, distance - road_clearance) * 0.45)
				if distance_squared < nearest_distance[cell]:
					nearest_distance[cell] = distance_squared
					nearest_index[cell] = sample_index

	var base_color := Color("#52684a")
	if track.cfg.theme == "city":
		base_color = Color("#777466")
	elif track.cfg.theme == "oval":
		base_color = Color("#607a43")
	var terrain_material := _surface_material(GROUND_SHADER, "grass" if track.cfg.theme != "city" else "")
	terrain_material.set_shader_parameter("use_vertex_color", true)
	terrain_material.set_shader_parameter("slope_rock", 0.4 if track.cfg.theme == "city" else 1.0)
	var band_squared := band * band
	var terrain_vertices := PackedVector3Array()
	var terrain_colors := PackedColorArray()
	var terrain_indices := PackedInt32Array()
	for z_idx in nz:
		for x_idx in nx:
			var i00 := z_idx * row + x_idx
			var i10 := i00 + 1
			var i01 := i00 + row
			var i11 := i01 + 1
			if minf(minf(nearest_distance[i00], nearest_distance[i10]), minf(nearest_distance[i01], nearest_distance[i11])) >= band_squared:
				continue
			var cell_base := terrain_vertices.size()
			for point_idx in [i00, i10, i01, i11]:
				var px: float = x0 + (point_idx % row) * fine
				var pz: float = z0 + floori(float(point_idx) / float(row)) * fine
				var distance := sqrt(nearest_distance[point_idx]) if nearest_index[point_idx] >= 0 else INF
				var y := _terrain_height(px, pz, nearest_index[point_idx], distance, height_cap[point_idx], grid) * ALTITUDE_SCALE
				terrain_vertices.append(Vector3(px - world_center.x, y, pz - world_center.y))
				terrain_colors.append(_terrain_color(px, pz, base_color))
			terrain_indices.append_array(PackedInt32Array([cell_base, cell_base + 2, cell_base + 1, cell_base + 1, cell_base + 2, cell_base + 3]))
	if not terrain_vertices.is_empty():
		var terrain_arrays := []
		terrain_arrays.resize(Mesh.ARRAY_MAX)
		terrain_arrays[Mesh.ARRAY_VERTEX] = terrain_vertices
		terrain_arrays[Mesh.ARRAY_COLOR] = terrain_colors
		terrain_arrays[Mesh.ARRAY_INDEX] = terrain_indices
		var terrain_mesh := ArrayMesh.new()
		terrain_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, terrain_arrays)
		var terrain_st := SurfaceTool.new()
		terrain_st.create_from(terrain_mesh, 0)
		terrain_st.index()
		terrain_st.generate_normals()
		var detailed := MeshInstance3D.new()
		detailed.name = "DetailedTerrain"
		detailed.mesh = terrain_st.commit()
		detailed.material_override = terrain_material
		detailed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		track_root.add_child(detailed)

	# Coarse elevation data fills the distance beyond the detailed trackside band.
	var coarse_vertices := PackedVector3Array()
	var coarse_colors := PackedColorArray()
	var coarse_indices := PackedInt32Array()
	var dem_x0 := float(grid.get("x0", 0.0))
	var dem_z0 := float(grid.get("y0", 0.0))
	var dem_min := INF
	for j in dem_nz:
		for i in dem_nx:
			var wx := dem_x0 + i * dem_step
			var wz := dem_z0 + j * dem_step
			var height := float(dem[j * dem_nx + i]) - elevation_base - 1.2
			var fi := clampi(roundi((wx - x0) / fine), 0, nx)
			var fj := clampi(roundi((wz - z0) / fine), 0, nz)
			var near_cell := fj * row + fi
			if nearest_index[near_cell] >= 0 and sqrt(nearest_distance[near_cell]) < band - dem_step * 1.5:
				height -= 40.0
			dem_min = minf(dem_min, height)
			coarse_vertices.append(Vector3(wx - world_center.x, height * ALTITUDE_SCALE, wz - world_center.y))
			coarse_colors.append(_terrain_color(wx, wz, base_color))
			if i < dem_nx - 1 and j < dem_nz - 1:
				var a := j * dem_nx + i
				coarse_indices.append_array(PackedInt32Array([a, a + dem_nx, a + 1, a + 1, a + dem_nx, a + dem_nx + 1]))
	var coarse_arrays := []
	coarse_arrays.resize(Mesh.ARRAY_MAX)
	coarse_arrays[Mesh.ARRAY_VERTEX] = coarse_vertices
	coarse_arrays[Mesh.ARRAY_COLOR] = coarse_colors
	coarse_arrays[Mesh.ARRAY_INDEX] = coarse_indices
	var coarse_mesh := ArrayMesh.new()
	coarse_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, coarse_arrays)
	var coarse_st := SurfaceTool.new()
	coarse_st.create_from(coarse_mesh, 0)
	coarse_st.generate_normals()
	var coarse := MeshInstance3D.new()
	coarse.name = "TerrainDEM"
	coarse.mesh = coarse_st.commit()
	coarse.material_override = terrain_material
	track_root.add_child(coarse)
	ground.position.y = (dem_min - 55.0) * ALTITUDE_SCALE

func _terrain_height(x: float, z: float, nearest: int, distance: float, cap: float, grid: Dictionary) -> float:
	var dem_height := _sample_dem(grid, x, z) - elevation_base
	var height := dem_height - 1.0
	if nearest >= 0 and distance <= 175.0:
		var track_height := track.H[nearest] - elevation_base
		var clear_distance := track.half + track.cfg.runoff + 3.0
		var blend := clampf((distance - clear_distance) / 70.0, 0.0, 1.0)
		blend = blend * blend * (3.0 - 2.0 * blend)
		height = track_height - 0.35 + (dem_height - track_height + 0.35) * blend
	return minf(height, cap)

func _sample_dem(grid: Dictionary, x: float, z: float) -> float:
	var heights: Array = grid["h"]
	var nx := int(grid["nx"])
	var nz := int(grid["ny"])
	var step := float(grid["step"])
	var fx := clampf((x - float(grid["x0"])) / step, 0.0, float(nx) - 1.001)
	var fz := clampf((z - float(grid["y0"])) / step, 0.0, float(nz) - 1.001)
	var ix := floori(fx)
	var iz := floori(fz)
	var u := fx - ix
	var v := fz - iz
	var h00 := float(heights[iz * nx + ix])
	var h10 := float(heights[iz * nx + ix + 1])
	var h01 := float(heights[(iz + 1) * nx + ix])
	var h11 := float(heights[(iz + 1) * nx + ix + 1])
	return h00 * (1.0 - u) * (1.0 - v) + h10 * u * (1.0 - v) + h01 * (1.0 - u) * v + h11 * u * v

func _terrain_color(x: float, z: float, base: Color) -> Color:
	var broad := sin(x * 0.013 + z * 0.009) * cos(z * 0.011 - x * 0.004)
	var detail := sin((x + z) * 0.083) * cos((z - x) * 0.071)
	return base.lerp(base.darkened(0.34), clampf(0.28 + broad * 0.2 + detail * 0.08, 0.0, 0.72))

func _add_ribbon(width: float, lift: float, material: Material, label: String) -> void:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var half := width * 0.5
	# lateral columns: the ribbon edges plus the track edges, where a banked cross-section changes slope
	var cols: Array[float] = [-half]
	if half > track.half + 0.01:
		cols.append_array([-track.half, track.half])
	cols.append(half)
	# extra columns across the road give the shader room for the rubbered line and the edge dust
	if label == "Asphalt":
		cols.clear()
		for k in 13:
			cols.append(lerpf(-half, half, k / 12.0))
	var nc := cols.size()
	# UV: (lateral offset, distance along the lap); UV2.x: lateral distance from the racing line.
	# The last ring repeats the first with s = L so the along-track UV does not jump back to 0.
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	for ring in track.n + 1:
		var i := ring % track.n
		var y := (track.H[i] - elevation_base) * ALTITUDE_SCALE + lift
		var center := Vector3(track.X[i] - world_center.x, y, track.Y[i] - world_center.y)
		var normal := Vector3(-track.TY[i], 0.0, track.TX[i])
		for d in cols:
			vertices.append(center + normal * d + Vector3.UP * track.bank_rise(i * track.step, d))
			uvs.append(Vector2(d, ring * track.step))
			uv2s.append(Vector2(d - track.RLD[i], 0.0))

	for i in track.n:
		for c in nc - 1:
			var a := i * nc + c
			var b := a + 1
			var e := (i + 1) * nc + c
			var f := e + 1
			indices.append_array(PackedInt32Array([a, e, b, b, e, f]))

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var st := SurfaceTool.new()
	st.create_from(mesh, 0)
	st.generate_normals()
	st.generate_tangents()

	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = st.commit()
	instance.material_override = material
	track_root.add_child(instance)

## Painted white lines along both track edges, following the banking.
func _add_edge_lines() -> void:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for side in [-1.0, 1.0]:
		var inner: float = side * (track.half - 0.52)
		var outer: float = side * (track.half - 0.22)
		var base := vertices.size()
		for i in track.n:
			var s := i * track.step
			var y := (track.H[i] - elevation_base) * ALTITUDE_SCALE + 0.05
			var normal := Vector3(-track.TY[i], 0.0, track.TX[i])
			var center := Vector3(track.X[i] - world_center.x, y, track.Y[i] - world_center.y)
			vertices.append(center + normal * inner + Vector3.UP * track.bank_rise(s, inner))
			vertices.append(center + normal * outer + Vector3.UP * track.bank_rise(s, outer))
		for i in track.n:
			var a := base + i * 2
			var c := base + ((i + 1) % track.n) * 2
			if side > 0.0:
				indices.append_array(PackedInt32Array([a, c, a + 1, a + 1, c, c + 1]))
			else:
				indices.append_array(PackedInt32Array([a, a + 1, c, a + 1, c + 1, c]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var st := SurfaceTool.new()
	st.create_from(mesh, 0)
	st.generate_normals()
	var line := MeshInstance3D.new()
	line.name = "EdgeLines"
	line.mesh = st.commit()
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := _material(Color("#e8e5da"), 0.62)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	line.material_override = mat
	track_root.add_child(line)

func _build_kerbs() -> void:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	var red := Color("#cc2218")
	var white := Color("#f5f5f5")
	var half := track.half

	var vert_idx := 0
	for i in track.n:
		var k := track.KC[i]
		if absf(k) < 1.0 / 180.0:
			continue

		var sd := signf(k)
		var nxt := (i + 1) % track.n

		var y0 := (track.H[i] - elevation_base) * ALTITUDE_SCALE + 0.075
		var y1 := (track.H[nxt] - elevation_base) * ALTITUDE_SCALE + 0.075

		var a0_p := track.pos(i * track.step, sd * (half - 0.75))
		var a1_p := track.pos(nxt * track.step, sd * (half - 0.75))
		var b0_p := track.pos(i * track.step, sd * (half + 0.65))
		var b1_p := track.pos(nxt * track.step, sd * (half + 0.65))

		var s0 := i * track.step
		var s1 := nxt * track.step
		var a0 := Vector3(a0_p[0] - world_center.x, y0 + track.bank_rise(s0, sd * (half - 0.75)), a0_p[1] - world_center.y)
		var a1 := Vector3(a1_p[0] - world_center.x, y1 + track.bank_rise(s1, sd * (half - 0.75)), a1_p[1] - world_center.y)
		var b0 := Vector3(b0_p[0] - world_center.x, y0 + 0.03 + track.bank_rise(s0, sd * (half + 0.65)), b0_p[1] - world_center.y)
		var b1 := Vector3(b1_p[0] - world_center.x, y1 + 0.03 + track.bank_rise(s1, sd * (half + 0.65)), b1_p[1] - world_center.y)

		var c := red if (i % 2 == 0) else white

		vertices.append_array(PackedVector3Array([a0, b0, a1, b1]))
		colors.append_array(PackedColorArray([c, c, c, c]))

		if sd > 0:
			indices.append_array(PackedInt32Array([vert_idx, vert_idx + 1, vert_idx + 2, vert_idx + 1, vert_idx + 3, vert_idx + 2]))
		else:
			indices.append_array(PackedInt32Array([vert_idx, vert_idx + 2, vert_idx + 1, vert_idx + 1, vert_idx + 2, vert_idx + 3]))
		vert_idx += 4

	if vertices.size() > 0:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices

		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var st := SurfaceTool.new()
		st.create_from(mesh, 0)
		st.generate_normals()

		var kerb_inst := MeshInstance3D.new()
		kerb_inst.name = "Kerbs"
		kerb_inst.mesh = st.commit()
		var km := StandardMaterial3D.new()
		km.vertex_color_use_as_albedo = true
		km.vertex_color_is_srgb = true
		km.roughness = 0.7
		kerb_inst.material_override = km
		track_root.add_child(kerb_inst)

func _build_start_finish_gantry() -> void:
	var s0_pos := _world_pos(track.X[0], track.Y[0], 0)
	var heading := track.heading(0)

	# 1. Start line: a painted chequered strip
	var line := MeshInstance3D.new()
	line.name = "StartLine"
	var strip := PlaneMesh.new()
	strip.size = Vector2(track.width, 1.4)
	line.mesh = strip
	line.position = s0_pos - Vector3.UP * 0.034
	line.rotation.y = -heading - PI / 2.0
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var squares := maxi(4, roundi(track.width / 0.7))
	var checker := Image.create(squares, 2, false, Image.FORMAT_RGB8)
	for x in squares:
		for y in 2:
			checker.set_pixel(x, y, Color("#efece4") if (x + y) % 2 == 0 else Color("#16181a"))
	var line_mat := _material(Color.WHITE, 0.6)
	line_mat.albedo_texture = ImageTexture.create_from_image(checker)
	line_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	line.material_override = line_mat
	track_root.add_child(line)

	# 2. Overhead steel gantry
	var gantry_root := Node3D.new()
	gantry_root.position = s0_pos
	gantry_root.rotation.y = -heading
	track_root.add_child(gantry_root)

	var steel := _material(Color("#2c3138"), 0.4)
	steel.metallic = 0.7

	# Vertical support posts
	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var pmesh := BoxMesh.new()
		pmesh.size = Vector3(0.5, 7.5, 0.5)
		post.mesh = pmesh
		post.position = Vector3(0, 3.75, side * (track.half + 2.2))
		post.material_override = steel
		gantry_root.add_child(post)

	# Crossbeam
	var beam := MeshInstance3D.new()
	var bmesh := BoxMesh.new()
	bmesh.size = Vector3(1.1, 1.3, track.width + 5.0)
	beam.mesh = bmesh
	beam.position = Vector3(0, 7.2, 0)
	beam.material_override = steel
	gantry_root.add_child(beam)

	# 5 Start light pods
	for i in 5:
		var light := MeshInstance3D.new()
		var lmesh := CylinderMesh.new()
		lmesh.top_radius = 0.32
		lmesh.bottom_radius = 0.32
		lmesh.height = 0.16
		light.mesh = lmesh
		light.rotation.z = PI / 2.0
		light.position = Vector3(-0.6, 7.2, (i - 2) * 1.1)

		var lmat := StandardMaterial3D.new()
		lmat.albedo_color = START_LIGHT_OFF
		# emission stays enabled (energy 0 when off) so switching a light never swaps shaders
		lmat.emission_enabled = true
		lmat.emission = START_LIGHT_ON
		lmat.emission_energy_multiplier = 0.0
		light.material_override = lmat

		gantry_root.add_child(light)
		start_lights.append(light)

func _build_pit_lane() -> void:
	var cfg := track.cfg
	if absf(cfg.pit_offset) < 1.0:
		return

	var po := cfg.pit_offset
	var sg := signf(po)
	var p0 := cfg.pit_entry
	var p1 := cfg.pit_exit

	# Pit lane asphalt ribbon
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()
	var steps := 60
	for step_idx in (steps + 1):
		var s := p0 + (p1 - p0) * (float(step_idx) / float(steps))
		var blend := track.pit_blend(s)
		var center_d := sg * (track.half - 1.5) * (1.0 - blend) + (po + sg * 1.0) * blend
		var y := (track.sample(track.H, s) - elevation_base) * ALTITUDE_SCALE + 0.045

		var p_left := track.pos(s, center_d - 3.2)
		var p_right := track.pos(s, center_d + 3.2)

		vertices.append(Vector3(p_left[0] - world_center.x, y, p_left[1] - world_center.y))
		vertices.append(Vector3(p_right[0] - world_center.x, y, p_right[1] - world_center.y))
		uvs.append_array(PackedVector2Array([Vector2(-3.2, s), Vector2(3.2, s)]))
		uv2s.append_array(PackedVector2Array([Vector2(-3.2, 0.0), Vector2(3.2, 0.0)]))

	for step_idx in steps:
		var a := step_idx * 2
		var b := a + 1
		var c := (step_idx + 1) * 2
		var d := c + 1
		indices.append_array(PackedInt32Array([a, c, b, b, c, d]))

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var pit_st := SurfaceTool.new()
	pit_st.create_from(mesh, 0)
	pit_st.generate_normals()
	pit_st.generate_tangents()
	var inst := MeshInstance3D.new()
	inst.name = "PitLane"
	inst.mesh = pit_st.commit()
	# the pit lane is smoother, newer tarmac with the rubbered line down its middle
	var pit_mat := _surface_material(ROAD_SHADER, "pit_lane|asphalt")
	pit_mat.set_shader_parameter("base_color", Color("#222527"))
	pit_mat.set_shader_parameter("half_width", 3.2)
	pit_mat.set_shader_parameter("patches", 0.3)
	pit_mat.set_shader_parameter("rubber", 0.5)
	inst.material_override = pit_mat
	track_root.add_child(inst)

	# Pit wall concrete barrier
	var wall_s0 := cfg.pit_entry + cfg.pit_ramp * 0.55
	var wall_s1 := cfg.pit_exit - cfg.pit_ramp * 0.55
	var wall_steps := 40
	var wall_verts := PackedVector3Array()
	var wall_indices := PackedInt32Array()

	for step_idx in (wall_steps + 1):
		var s := wall_s0 + (wall_s1 - wall_s0) * (float(step_idx) / float(wall_steps))
		var y := (track.sample(track.H, s) - elevation_base) * ALTITUDE_SCALE
		var pos_bot := track.pos(s, sg * track.wall_d)
		var base_p := Vector3(pos_bot[0] - world_center.x, y, pos_bot[1] - world_center.y)
		wall_verts.append(base_p)
		wall_verts.append(base_p + Vector3.UP * 1.15)

	for step_idx in wall_steps:
		var a := step_idx * 2
		var b := a + 1
		var c := (step_idx + 1) * 2
		var d := c + 1
		wall_indices.append_array(PackedInt32Array([a, b, c, b, d, c]))

	var w_arrays := []
	w_arrays.resize(Mesh.ARRAY_MAX)
	w_arrays[Mesh.ARRAY_VERTEX] = wall_verts
	w_arrays[Mesh.ARRAY_INDEX] = wall_indices
	var w_mesh := ArrayMesh.new()
	w_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, w_arrays)
	var w_st := SurfaceTool.new()
	w_st.create_from(w_mesh, 0)
	w_st.generate_normals()
	var wall_inst := MeshInstance3D.new()
	wall_inst.name = "PitWall"
	wall_inst.mesh = w_st.commit()
	var wall_mat := _material(Color("#82898f"), 0.65)
	wall_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	wall_inst.material_override = wall_mat
	track_root.add_child(wall_inst)

func _build_barriers() -> void:
	var cfg := track.cfg
	var bd := track.half + cfg.runoff + 0.3
	var po := cfg.pit_offset
	var sg := signf(po)
	var kind := cfg.barrier
	var is_armco := kind == "armco" or kind == "armco+fence"
	var has_fence := kind == "safer" or kind == "armco+fence"
	var wall_bottom := 0.3 if is_armco else 0.0
	var wall_top := 1.0 if is_armco else (1.2 if kind == "safer" else 0.9)
	var fence_top := 5.0 if kind == "safer" else 3.2
	var barrier_mat := _material(Color("#7d848a") if is_armco else (Color("#89877f") if kind == "safer" else Color("#242528")), 0.45)
	if is_armco:
		barrier_mat.metallic = 0.65
	# walls are single quads seen from both the road and the infield
	barrier_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var fence_mat := _material(Color(0.2, 0.23, 0.25, 0.42), 0.8)
	fence_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fence_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fence_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var total_turn := 0.0
	for curvature in track.KC:
		total_turn += curvature
	var safer_outside := 1.0 if total_turn < 0.0 else -1.0
	var post_transforms: Array[Transform3D] = []

	for side in [-1.0, 1.0]:
		if kind == "safer" and side != safer_outside:
			continue
		var verts := PackedVector3Array()
		var indices := PackedInt32Array()
		var fence_verts := PackedVector3Array()
		var fence_indices := PackedInt32Array()
		var v_count := 0

		var skip: bool = (side == sg and absf(po) > 1.0)
		for i in track.n:
			var s := i * track.step
			var p_rel := track.rel(s)
			if skip and (p_rel > cfg.pit_entry - 20.0 and p_rel < cfg.pit_exit + 20.0):
				continue

			var nxt := (i + 1) % track.n
			var rise0 := track.bank_rise(s, side * bd)
			var rise1 := track.bank_rise(nxt * track.step, side * bd)
			var y0 := (track.H[i] - elevation_base) * ALTITUDE_SCALE + rise0
			var y1 := (track.H[nxt] - elevation_base) * ALTITUDE_SCALE + rise1

			var p0 := track.pos(s, side * bd)
			var p1 := track.pos(nxt * track.step, side * bd)

			# on a banked turn the solid wall carries on down to the ground behind the raised road
			var drop0 := rise0 + 0.4 if rise0 > 0.0 and not is_armco else 0.0
			var drop1 := rise1 + 0.4 if rise1 > 0.0 and not is_armco else 0.0
			var b0 := Vector3(p0[0] - world_center.x, y0 + wall_bottom - drop0, p0[1] - world_center.y)
			var t0 := Vector3(p0[0] - world_center.x, y0 + wall_top, p0[1] - world_center.y)
			var b1 := Vector3(p1[0] - world_center.x, y1 + wall_bottom - drop1, p1[1] - world_center.y)
			var t1 := Vector3(p1[0] - world_center.x, y1 + wall_top, p1[1] - world_center.y)

			verts.append_array(PackedVector3Array([b0, t0, b1, t1]))
			if side > 0:
				indices.append_array(PackedInt32Array([v_count, v_count + 1, v_count + 2, v_count + 1, v_count + 3, v_count + 2]))
			else:
				indices.append_array(PackedInt32Array([v_count, v_count + 2, v_count + 1, v_count + 1, v_count + 2, v_count + 3]))
			if has_fence:
				var f0 := t0
				var f1 := t1
				var f2 := Vector3(p0[0] - world_center.x, y0 + fence_top, p0[1] - world_center.y)
				var f3 := Vector3(p1[0] - world_center.x, y1 + fence_top, p1[1] - world_center.y)
				fence_verts.append_array(PackedVector3Array([f0, f2, f1, f3]))
				var fence_base := fence_verts.size() - 4
				if side > 0:
					fence_indices.append_array(PackedInt32Array([fence_base, fence_base + 1, fence_base + 2, fence_base + 1, fence_base + 3, fence_base + 2]))
				else:
					fence_indices.append_array(PackedInt32Array([fence_base, fence_base + 2, fence_base + 1, fence_base + 1, fence_base + 2, fence_base + 3]))
			v_count += 4
			if is_armco and i % maxi(1, int(4.0 / track.step)) == 0:
				post_transforms.append(Transform3D(Basis.IDENTITY, Vector3(p0[0] - world_center.x, y0 + 0.48, p0[1] - world_center.y)))

		if verts.size() > 0:
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_INDEX] = indices
			var b_mesh := ArrayMesh.new()
			b_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var st := SurfaceTool.new()
			st.create_from(b_mesh, 0)
			st.generate_normals()

			var b_inst := MeshInstance3D.new()
			b_inst.name = "Barrier_%s" % ("R" if side > 0 else "L")
			b_inst.mesh = st.commit()
			b_inst.material_override = barrier_mat
			track_root.add_child(b_inst)

		if has_fence and not fence_verts.is_empty():
			var f_arrays := []
			f_arrays.resize(Mesh.ARRAY_MAX)
			f_arrays[Mesh.ARRAY_VERTEX] = fence_verts
			f_arrays[Mesh.ARRAY_INDEX] = fence_indices
			var f_mesh := ArrayMesh.new()
			f_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, f_arrays)
			var f_st := SurfaceTool.new()
			f_st.create_from(f_mesh, 0)
			f_st.generate_normals()
			var f_inst := MeshInstance3D.new()
			f_inst.name = "Fence_%s" % ("R" if side > 0 else "L")
			f_inst.mesh = f_st.commit()
			f_inst.material_override = fence_mat
			track_root.add_child(f_inst)

	if is_armco and not post_transforms.is_empty():
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.12, 0.96, 0.12)
		var posts := MultiMesh.new()
		posts.transform_format = MultiMesh.TRANSFORM_3D
		posts.mesh = post_mesh
		posts.instance_count = post_transforms.size()
		for i in post_transforms.size():
			posts.set_instance_transform(i, post_transforms[i])
		var post_instance := MultiMeshInstance3D.new()
		post_instance.name = "ArmcoPosts"
		post_instance.multimesh = posts
		post_instance.material_override = _material(Color("#656b70"), 0.5)
		track_root.add_child(post_instance)

func _build_racing_line() -> void:
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	var green := Color("#38df75")
	var brake_red := Color("#ff3228")

	for i in track.n:
		var s := i * track.step
		var d := track.RLD[i]
		var y := (track.H[i] - elevation_base) * ALTITUDE_SCALE + 0.055

		var p_left := track.pos(s, d - 0.24)
		var p_right := track.pos(s, d + 0.24)

		verts.append(Vector3(p_left[0] - world_center.x, y + track.bank_rise(s, d - 0.24), p_left[1] - world_center.y))
		verts.append(Vector3(p_right[0] - world_center.x, y + track.bank_rise(s, d + 0.24), p_right[1] - world_center.y))

		var is_braking := track.PROF[(i + 6) % track.n] < (track.PROF[i] - 0.42)
		var c := brake_red if is_braking else green
		colors.append(c)
		colors.append(c)

	for i in track.n:
		var a := i * 2
		var b := a + 1
		var c := ((i + 1) % track.n) * 2
		var d := c + 1
		indices.append_array(PackedInt32Array([a, c, b, b, c, d]))

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	racing_line_node = MeshInstance3D.new()
	racing_line_node.name = "RacingLine"
	racing_line_node.mesh = mesh
	var rl_mat := StandardMaterial3D.new()
	rl_mat.vertex_color_use_as_albedo = true
	rl_mat.vertex_color_is_srgb = true
	rl_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rl_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rl_mat.albedo_color = Color(1, 1, 1, 0.72)
	racing_line_node.material_override = rl_mat
	racing_line_node.visible = show_racing_line
	track_root.add_child(racing_line_node)

## Woods and clearings of spruce and broadleaf trees standing on the terrain, kept off every part of the
## circuit. Tree models in assets/models/trees replace the procedural ones when present.
func _build_trees(_extent: float) -> void:
	if track.cfg.theme == "city":
		return # Monaco uses city buildings instead of trees
	var want := mini(int(track.L / 18.0 * track.cfg.tree_density * 2.4 * TREE_SCALE[quality]), int(1500 * TREE_SCALE[quality]))
	if want <= 0:
		return
	var models: Array = _world_assets().tree_variants()
	var kinds := models.size() if not models.is_empty() else 2
	var lookup := _track_lookup(24.0)
	var rng := SimUtil.Rng.new(54321)
	var clear_d := track.half + track.cfg.runoff + 5.0
	var conifer := clampf(track.cfg.tree_conifer, 0.0, 1.0)
	var patch := clampf(track.cfg.tree_patch, 0.0, 1.0)
	var transforms := []
	var tints := []
	for k in kinds:
		transforms.append([])
		tints.append([])
	var placed := 0
	var tries := 0
	while placed < want and tries < want * 8:
		tries += 1
		var s := rng.next() * track.L
		var side := 1.0 if rng.next() > 0.5 else -1.0
		var back := rng.next()
		var dist := clear_d + 1.0 + back * back * 95.0
		# woods and clearings along the lap
		var clump := 0.5 + 0.5 * sin(s * 0.011 + side * 1.7) * cos(s * 0.0043 + side)
		if rng.next() > lerpf(1.0, clump * 1.7, patch):
			continue
		var rel_s := track.rel(s)
		if track.cfg.grandstands and side < 0.0 and dist < 48.0 and rel_s > track.cfg.stands.x - 20.0 and rel_s < track.cfg.stands.y + 20.0:
			continue
		var p := track.pos(s, side * dist)
		if not _clear_of_track(lookup, p[0], p[1], clear_d):
			continue
		var kind := int(rng.next() * kinds) % kinds if not models.is_empty() else (0 if rng.next() < conifer else 1)
		var size := (0.7 + rng.next() * 0.7) * (11.0 if not models.is_empty() else 1.0)
		var basis := Basis(Vector3.UP, rng.next() * TAU).scaled(Vector3(size, size * (0.85 + rng.next() * 0.3), size))
		var y := _ground_y(p[0], p[1], s, dist) - 0.3
		transforms[kind].append(Transform3D(basis, Vector3(p[0] - world_center.x, y, p[1] - world_center.y)))
		var tint := 0.8 + rng.next() * 0.35
		tints[kind].append(Color(tint * (0.94 + rng.next() * 0.12), tint, tint * (0.88 + rng.next() * 0.16)))
		placed += 1

	var root := Node3D.new()
	root.name = "Trees"
	track_root.add_child(root)
	if models.is_empty():
		var meshes := [_spruce_mesh(), _broadleaf_mesh()]
		var foliage := ShaderMaterial.new()
		foliage.shader = FOLIAGE_SHADER
		foliage.set_shader_parameter("grain", noise_texture("grain"))
		_wet_materials.append(foliage)
		for k in kinds:
			_add_tree_instances(root, meshes[k], Transform3D.IDENTITY, transforms[k], tints[k], foliage)
	else:
		for k in kinds:
			for part in models[k]:
				_add_tree_instances(root, part[0], part[1], transforms[k], [], null)

func _add_tree_instances(root: Node3D, mesh: Mesh, local: Transform3D, xfs: Array, tints: Array, material: Material) -> void:
	if xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not tints.is_empty()
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i] * local)
		if mm.use_colors:
			mm.set_instance_color(i, tints[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if material:
		mmi.material_override = material
	if quality < 2:
		mmi.visibility_range_end = [700.0, 1100.0][quality]
		mmi.visibility_range_end_margin = 80.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	root.add_child(mmi)

## A spruce: four stacked cones on a short trunk. Vertex alpha 1 marks foliage for the leaf flutter.
static func _spruce_mesh() -> Mesh:
	var parts := [[_cylinder(0.17, 0.28, 3.0, 7), Vector3(0, 1.5, 0), 0.0, Color("#4a3827", 0.0)]]
	var greens := [Color("#1d3822", 1.0), Color("#21402a", 1.0), Color("#26472c", 1.0), Color("#2b4f31", 1.0)]
	for k in 4:
		var h := 4.4 - k * 0.7
		parts.append([_cylinder(0.0, 2.5 - k * 0.5, h, 10), Vector3(0, 2.4 + k * 1.85 + h * 0.5, 0), 0.0, greens[k]])
	return CAR_VISUAL._merge(parts)

## A broadleaf tree: a trunk under a lumpy crown of overlapping spheres.
static func _broadleaf_mesh() -> Mesh:
	var parts := [[_cylinder(0.2, 0.32, 3.6, 7), Vector3(0, 1.8, 0), 0.0, Color("#54402c", 0.0)]]
	var crown := [[2.4, Vector3(0, 4.9, 0)], [1.9, Vector3(1.3, 4.3, 0.6)], [1.8, Vector3(-1.2, 4.5, -0.7)],
		[1.7, Vector3(0.3, 6.1, 0.3)], [1.5, Vector3(-0.4, 4.2, 1.3)]]
	var greens := [Color("#3a5a2b", 1.0), Color("#44652f", 1.0), Color("#355526", 1.0), Color("#4d6e34", 1.0), Color("#3f5f2c", 1.0)]
	for k in crown.size():
		var ball := SphereMesh.new()
		ball.radius = crown[k][0]
		ball.height = crown[k][0] * 1.7
		ball.radial_segments = 9
		ball.rings = 5
		parts.append([ball, crown[k][1], 0.0, greens[k]])
	return CAR_VISUAL._merge(parts)

static func _cylinder(top: float, bottom: float, height: float, segments: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = segments
	c.rings = 1
	c.cap_top = top > 0.0
	return c

## Centreline samples bucketed on a coarse grid, for "is this spot clear of the circuit" checks.
func _track_lookup(cell: float) -> Dictionary:
	var buckets := {"cell": cell}
	for i in track.n:
		var key := Vector2i(floori(track.X[i] / cell), floori(track.Y[i] / cell))
		if not buckets.has(key):
			buckets[key] = PackedInt32Array()
		buckets[key].append(i)
	return buckets

func _clear_of_track(lookup: Dictionary, x: float, z: float, clearance: float) -> bool:
	var cell: float = lookup.cell
	var reach := ceili(clearance / cell)
	var cx := floori(x / cell)
	var cz := floori(z / cell)
	var c2 := clearance * clearance
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var bucket = lookup.get(Vector2i(cx + dx, cz + dz))
			if bucket == null:
				continue
			for i in bucket:
				var ddx := track.X[i] - x
				var ddz := track.Y[i] - z
				if ddx * ddx + ddz * ddz < c2:
					return false
	return true

## Terrain height (world units) at a point dist metres off the centreline at s, as _build_terrain shapes it.
func _ground_y(x: float, z: float, s: float, dist: float) -> float:
	if typeof(track.grid) != TYPE_DICTIONARY or int(track.grid.get("nx", 0)) < 2:
		return _road_y(s) - 0.09
	var nearest := int(roundf(track.wrap_s(s) / track.step)) % track.n
	return _terrain_height(x, z, nearest, dist, INF, track.grid) * ALTITUDE_SCALE

func _build_grandstands() -> void:
	if not track.cfg.grandstands:
		return
	var start_s: float = track.cfg.stands.x
	var end_s: float = track.cfg.stands.y
	if end_s <= start_s:
		return
	var span: float = end_s - start_s
	var pieces: int = maxi(1, ceili(span / 180.0))
	var tiers: int = clampi(track.cfg.stand_tiers, 3, 14)
	var seat_mat := _material(Color("#b8b5a7"), 0.82)
	var roof_mat := _material(Color("#41464a"), 0.58)
	var support_mat := _material(Color("#777b7a"), 0.7)
	var accents: Array[Color] = [Color("#c82e27"), Color("#e3e0d6"), Color("#2355a0")]
	# one crowd material for every tier; the seat colour is a per-tier instance uniform
	var crowd := ShaderMaterial.new()
	crowd.shader = CROWD_SHADER
	for piece in pieces:
		var s := start_s + (float(piece) + 0.5) * span / float(pieces)
		var side := -1.0
		var center := track.pos(s, side * (track.half + track.cfg.runoff + 10.0))
		var height := 1.4 + float(tiers) * 0.36
		var width := minf(150.0, span / float(pieces) * 0.88)
		var y := (track.sample(track.H, s) - elevation_base) * ALTITUDE_SCALE
		var rot := -track.heading(s) - PI / 2.0
		var root := Node3D.new()
		root.name = "Grandstand_%02d" % piece
		root.position = Vector3(center[0] - world_center.x, y, center[1] - world_center.y)
		root.rotation.y = rot
		track_root.add_child(root)
		for tier in tiers:
			var bench := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(width, 0.34, 1.35)
			bench.mesh = mesh
			bench.position = Vector3(-0.35, 0.55 + tier * 0.36, -tier * 0.92)
			bench.material_override = crowd
			bench.set_instance_shader_parameter("seat_color", accents[tier % accents.size()])
			root.add_child(bench)
		var back := MeshInstance3D.new()
		var back_mesh := BoxMesh.new()
		back_mesh.size = Vector3(width, height, 0.42)
		back.mesh = back_mesh
		back.position = Vector3(-0.3, height * 0.48, -tiers * 0.96)
		back.material_override = seat_mat
		root.add_child(back)
		var canopy := MeshInstance3D.new()
		var canopy_mesh := BoxMesh.new()
		canopy_mesh.size = Vector3(width + 3.0, 0.36, tiers * 1.15 + 4.0)
		canopy.mesh = canopy_mesh
		canopy.position = Vector3(-0.3, height + 1.6, -tiers * 0.38)
		canopy.material_override = roof_mat
		root.add_child(canopy)
		for post_x in [-width * 0.46, width * 0.46]:
			var post := MeshInstance3D.new()
			var post_mesh := BoxMesh.new()
			post_mesh.size = Vector3(0.38, height + 1.4, 0.38)
			post.mesh = post_mesh
			post.position = Vector3(post_x, (height + 1.4) * 0.5, -tiers * 0.38)
			post.material_override = support_mat
			root.add_child(post)

func _build_city_blocks() -> void:
	# Monaco's narrow streets are surrounded by dense blocks, not a flat green field. Windows, shutters
	# and floor bands come from the facade shader, so each block is a single box.
	var walls: Array[Color] = [Color("#d4c4a8"), Color("#c6b7a5"), Color("#e0d5c2"), Color("#b8aa9b"),
		Color("#e3b98f"), Color("#d9a58a"), Color("#efe0c0")]
	var shutters: Array[Color] = [Color("#3f5e48"), Color("#5b6f7a"), Color("#6b4a33"), Color("#7a8a5a")]
	var facade := ShaderMaterial.new()
	facade.shader = FACADE_SHADER
	facade.set_shader_parameter("grain", noise_texture("grain"))
	_wet_materials.append(facade)
	_night_materials.append(facade)
	var rng := SimUtil.Rng.new(92341)
	var blocks := mini(52, int(track.L / 64.0))
	for i in blocks:
		var s := (float(i) + 0.5) * track.L / float(blocks)
		var side := -1.0 if i % 2 == 0 else 1.0
		var lateral := track.half + track.cfg.runoff + 14.0 + rng.next() * 8.0
		var p := track.pos(s, side * lateral)
		var floors := 3 + int(rng.next() * 6.0)
		var h := float(floors) * 3.1 + 0.9
		var w := 9.0 + rng.next() * 10.0
		var depth := 7.0 + rng.next() * 8.0
		var y := (track.sample(track.H, s) - elevation_base) * ALTITUDE_SCALE + h * 0.5
		var building := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(w, h, depth)
		building.mesh = box
		building.position = Vector3(p[0] - world_center.x, y, p[1] - world_center.y)
		building.rotation.y = -track.heading(s) - PI / 2.0
		building.material_override = facade
		building.set_instance_shader_parameter("wall_color", walls[i % walls.size()])
		building.set_instance_shader_parameter("shutter_color", shutters[int(rng.next() * shutters.size()) % shutters.size()])
		building.set_instance_shader_parameter("dims", Vector4(w, h, depth, float(i)))
		building.name = "CityBlock_%03d" % i
		track_root.add_child(building)
		# a projecting cornice and parapet on the roof line
		var cornice := MeshInstance3D.new()
		var cornice_mesh := BoxMesh.new()
		cornice_mesh.size = Vector3(w + 0.8, 0.32, depth + 0.8)
		cornice.mesh = cornice_mesh
		cornice.position = building.position + Vector3.UP * (h * 0.5 + 0.12)
		cornice.rotation.y = building.rotation.y
		cornice.material_override = _material(walls[(i + 1) % walls.size()].lightened(0.1), 0.85)
		track_root.add_child(cornice)

func _build_casino_landmark() -> void:
	# Place the landmark beside the real Casino corner rather than scattering generic blocks there.
	var s := 860.0
	var side := -1.0 if track.curvature(s) > 0.0 else 1.0
	var p := track.pos(s, side * (track.half + 17.0))
	var y := (track.sample(track.H, s) - elevation_base) * ALTITUDE_SCALE
	var root := Node3D.new()
	root.name = "MonteCarloCasino"
	root.position = Vector3(p[0] - world_center.x, y, p[1] - world_center.y)
	root.rotation.y = -track.heading(s) - PI / 2.0
	track_root.add_child(root)
	var stone := _material(Color("#e5d5b7"), 0.88)
	var trim := _material(Color("#f0e7d5"), 0.78)
	var roof := _material(Color("#66736c"), 0.72)
	var window := _material(Color("#435d67"), 0.3)
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(27.0, 12.0, 15.0)
	body.mesh = body_mesh
	body.position.y = 6.0
	body.material_override = stone
	root.add_child(body)
	var upper := MeshInstance3D.new()
	var upper_mesh := BoxMesh.new()
	upper_mesh.size = Vector3(20.0, 5.0, 12.0)
	upper.mesh = upper_mesh
	upper.position = Vector3(0, 14.5, -0.8)
	upper.material_override = trim
	root.add_child(upper)
	for level in 2:
		for col in 7:
			var win := MeshInstance3D.new()
			var win_mesh := BoxMesh.new()
			win_mesh.size = Vector3(1.5, 2.7, 0.12)
			win.mesh = win_mesh
			win.position = Vector3(-10.0 + col * 3.3, 3.1 + level * 3.3, -7.58)
			win.material_override = window
			root.add_child(win)
	var cornice := MeshInstance3D.new()
	var cornice_mesh := BoxMesh.new()
	cornice_mesh.size = Vector3(28.0, 0.65, 16.0)
	cornice.mesh = cornice_mesh
	cornice.position.y = 12.25
	cornice.material_override = trim
	root.add_child(cornice)
	var roof_mesh := PrismMesh.new()
	roof_mesh.size = Vector3(23.0, 2.6, 14.0)
	var cap := MeshInstance3D.new()
	cap.mesh = roof_mesh
	cap.position.y = 18.25
	cap.material_override = roof
	root.add_child(cap)
	# Casino name panel and warm entrance lights give the square a distinct night silhouette.
	var sign := MeshInstance3D.new()
	var sign_mesh := BoxMesh.new()
	sign_mesh.size = Vector3(7.0, 0.7, 0.18)
	sign.mesh = sign_mesh
	sign.position = Vector3(0, 9.3, -7.72)
	var sign_mat := _material(Color("#a78748"), 0.38)
	sign_mat.emission_enabled = true
	sign_mat.emission = Color("#c99d4a")
	sign_mat.emission_energy_multiplier = 0.35
	sign.material_override = sign_mat
	root.add_child(sign)

func _build_monaco_harbor(extent: float) -> void:
	# A sheltered basin sits inside the Port Hercule section of the circuit.
	var s := 1650.0
	var center_p := track.pos(s, -54.0)
	var water := MeshInstance3D.new()
	var water_mesh := PlaneMesh.new()
	water_mesh.size = Vector2(minf(extent * 0.48, 330.0), minf(extent * 0.32, 210.0))
	water.mesh = water_mesh
	water.position = Vector3(center_p[0] - world_center.x, -1.55, center_p[1] - world_center.y)
	var water_mat := ShaderMaterial.new()
	water_mat.shader = WATER_SHADER
	water_mat.set_shader_parameter("ripples", noise_texture("ripples"))
	water.material_override = water_mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	track_root.add_child(water)
	# Marina quays and a compact fleet of white motor yachts.
	var quay_mat := _material(Color("#c9b99e"), 0.86)
	for side in [-1.0, 1.0]:
		var quay := MeshInstance3D.new()
		var quay_mesh := BoxMesh.new()
		quay_mesh.size = Vector3(water_mesh.size.x * 0.9, 1.0, 5.0)
		quay.mesh = quay_mesh
		quay.position = water.position + Vector3(0, 0.2, side * water_mesh.size.y * 0.38)
		quay.material_override = quay_mat
		track_root.add_child(quay)
	var hull_mat := _material(Color("#f4f0e5"), 0.34)
	var deck_mat := _material(Color("#d5c6a8"), 0.55)
	for i in 9:
		var boat_root := Node3D.new()
		boat_root.name = "HarborYacht_%02d" % i
		boat_root.position = water.position + Vector3(-water_mesh.size.x * 0.38 + i * water_mesh.size.x * 0.095, 0.35, -water_mesh.size.y * 0.19 + (i % 3) * 15.0)
		boat_root.rotation.y = -0.18 if i % 2 == 0 else 0.12
		track_root.add_child(boat_root)
		var hull := MeshInstance3D.new()
		var hull_mesh := BoxMesh.new()
		hull_mesh.size = Vector3(18.0 if i % 3 == 0 else 11.0, 1.2, 3.5 if i % 3 == 0 else 2.5)
		hull.mesh = hull_mesh
		hull.material_override = hull_mat
		boat_root.add_child(hull)
		var cabin := MeshInstance3D.new()
		var cabin_mesh := BoxMesh.new()
		cabin_mesh.size = Vector3(5.0, 2.0, 2.2)
		cabin.mesh = cabin_mesh
		cabin.position = Vector3(-1.0, 1.45, 0)
		cabin.material_override = deck_mat
		boat_root.add_child(cabin)

func _setup_tv_cameras() -> void:
	tv_cameras.clear()
	tv_camera_s.clear()
	# a camera every ~140 m, on the outside of the bend
	var num_cams := maxi(4, int(track.L / 140.0))
	for i in num_cams:
		var s := float(i) * (track.L / float(num_cams))
		var k := track.sample(track.KC, s)
		var side := -signf(k) if absf(k) > 1.0 / 300.0 else 1.0
		var lateral := side * (track.half + track.cfg.runoff + 16.0)
		var p := track.pos(s, lateral)
		var y := _road_y(s) + 6.4 + track.bank_rise(s, lateral)
		tv_cameras.append(Vector3(p[0] - world_center.x, y, p[1] - world_center.y))
		tv_camera_s.append(s)

func _reset_skids() -> void:
	_skid_last.clear()
	_skid_next = 0
	_skid_used = 0
	if skid_multimesh == null:
		skid_multimesh = MultiMesh.new()
		skid_multimesh.transform_format = MultiMesh.TRANSFORM_3D
		var quad := PlaneMesh.new()
		quad.size = Vector2(0.2, 1.0)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.04, 0.04, 0.04, 0.5)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		quad.material = mat
		skid_multimesh.mesh = quad
		skid_multimesh.instance_count = SKID_CAPACITY
	skid_multimesh.visible_instance_count = 0
	if not is_instance_valid(_skid_instance) and is_instance_valid(skidmarks_root):
		_skid_instance = MultiMeshInstance3D.new()
		_skid_instance.name = "SkidmarkRing"
		_skid_instance.multimesh = skid_multimesh
		_skid_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		skidmarks_root.add_child(_skid_instance)

## Lays rubber behind both rear wheels once the car has moved far enough since its last mark.
func _add_skid(car_id: int, car_pos: Vector3, heading: float) -> void:
	if skid_multimesh == null:
		return
	var back := Vector3(cos(heading), 0.0, sin(heading))
	var rear := car_pos - back * 1.02 - Vector3.UP * 0.03
	var last = _skid_last.get(car_id)
	if last == null:
		_skid_last[car_id] = rear
		return
	var seg: Vector3 = rear - last
	var length := seg.length()
	if length < 0.7:
		return
	_skid_last[car_id] = rear
	if length > 5.0:
		return
	var along := seg / length
	var right := Vector3(-along.z, 0.0, along.x)
	var basis := Basis(right, Vector3.UP, along * length)
	var mid: Vector3 = (rear + last) * 0.5
	_put_skid(Transform3D(basis, mid - right * 0.66))
	_put_skid(Transform3D(basis, mid + right * 0.66))

func _put_skid(xf: Transform3D) -> void:
	skid_multimesh.set_instance_transform(_skid_next, xf)
	_skid_next = (_skid_next + 1) % SKID_CAPACITY
	if _skid_used < SKID_CAPACITY:
		_skid_used += 1
		skid_multimesh.visible_instance_count = _skid_used

func position_overview() -> void:
	if not track:
		return
	overview_target = Vector3(0, overview_distance, 0)
	if is_instance_valid(camera):
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.position = overview_target
		camera.look_at(Vector3.ZERO, Vector3.FORWARD)

func _world_pos(x: float, y: float, s: float, d := 0.0) -> Vector3:
	var h := track.sample(track.H, s)
	return Vector3(x - world_center.x, (h - elevation_base) * ALTITUDE_SCALE + track.bank_rise(s, d) + 0.09, y - world_center.y)

## Rotation that leans a car over with the banked road surface at (s, d).
func _surface_tilt(s: float, d: float) -> Basis:
	var sl := track.bank_slope(s, d)
	if sl == 0.0:
		return Basis.IDENTITY
	var up := Vector3(-sl * track.sample(track.NX, s), 1.0, -sl * track.sample(track.NY, s)).normalized()
	return Basis(Quaternion(Vector3.UP, up))

func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m

## Shared seamless noise textures for the shaders (generated once on worker threads by Godot).
static func noise_texture(kind: String) -> NoiseTexture2D:
	if _noise.has(kind):
		return _noise[kind]
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	var tex := NoiseTexture2D.new()
	tex.seamless = true
	tex.generate_mipmaps = true
	tex.width = 512
	tex.height = 512
	match kind:
		"clouds":
			n.seed = 7
			n.frequency = 0.006
			n.fractal_octaves = 6
			n.fractal_gain = 0.55
			tex.normalize = true
		"grain":
			n.seed = 3
			n.frequency = 0.018
			n.fractal_octaves = 6
			tex.normalize = true
		"grain_normal":
			n.seed = 11
			n.noise_type = FastNoiseLite.TYPE_CELLULAR
			n.frequency = 0.09
			n.fractal_octaves = 2
			tex.as_normal_map = true
			tex.bump_strength = 4.0
		"ripples":
			n.seed = 21
			n.frequency = 0.02
			n.fractal_octaves = 4
			tex.as_normal_map = true
			tex.bump_strength = 6.0
	tex.noise = n
	_noise[kind] = tex
	return tex

func _world_assets() -> RefCounted:
	if assets == null:
		assets = WORLD_ASSETS.new()
	return assets

## A road / ground ShaderMaterial, with an optional photo texture set from assets/textures/<folder>.
func _surface_material(shader: Shader, folder: String, weather := true) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("grain", noise_texture("grain"))
	m.set_shader_parameter("grain_normal", noise_texture("grain_normal"))
	# folder may list fallbacks: "pit_lane|asphalt"
	var set: Dictionary = {}
	for f in folder.split("|", false):
		set = _world_assets().material_set(f)
		if not set.is_empty():
			break
	if not set.is_empty():
		m.set_shader_parameter("use_textures", true)
		m.set_shader_parameter("albedo_tex", set.albedo)
		m.set_shader_parameter("tex_average", set.average)
		if set.normal:
			m.set_shader_parameter("normal_tex", set.normal)
		if set.roughness:
			m.set_shader_parameter("rough_tex", set.roughness)
			m.set_shader_parameter("has_rough_tex", true)
	if weather:
		_wet_materials.append(m)
	return m
