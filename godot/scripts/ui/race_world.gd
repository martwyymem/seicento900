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
const SURROUNDINGS := preload("res://scripts/ui/surroundings.gd")
const FAR_LAND := preload("res://scripts/ui/far_land.gd")
const FURNITURE := preload("res://scripts/ui/trackside_furniture.gd")
const ALTITUDE_SCALE := 1.0 ## heights at their real scale (the physics ignores elevation)
const BEAM_COUNT := 4 ## headlight spotlights handed to the cars nearest the camera after dark
const BEAM_REACH := 180.0
const SKID_CAPACITY := 1600
## Trackside structures built in Blender (tools/blender/build_trackside.py); the layout numbers below match it.
const TRACKSIDE_PATH := "res://models/trackside.glb"
const STAND_BAY := 10.0 ## grandstand bay width along the road
const STAND_RISE := 0.4 ## height and depth of a tier
const STAND_TREAD := 0.85
const STAND_FIRST_Z := 1.6 ## the first tier's top above the ground
const STAND_CONCOURSE := 1.6 ## walkway behind the top tier
const STAND_ROOF_FRONT := 4.3 ## roof front edge above the top tier, and how far it overhangs the first
const STAND_ROOF_OVERHANG := 1.6
const STAND_BOARDS := 8 ## sponsor boards StandBoard_0..7
const PIT_BAY := 12.0 ## a garage's width as built (stretched to the box spacing) and the building's depth
const PIT_DEPTH := 15.0
const GANTRY_BEAM_Y := 7.2
const LAMP_POOL := [4, 8, 12, 16] ## real lights hopping between the lamps nearest the camera, by quality
const LAMP_REACH := 150.0

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
var sky_top_color := SKY_TOP_DAY ## the procedural sky's colours, for the ray-traced reflections
var sky_horizon_color := HORIZON_DAY
var ray_tracing: RayTracing ## ray-traced reflections, off until the options switch them on
var asphalt_material: ShaderMaterial
var runoff_material: ShaderMaterial
var rain_particles: GPUParticles3D
var quality := 2
var assets: RefCounted ## world_assets.gd, shared by every track
## Materials that follow the weather ("wet"/"rain") or nightfall ("night") uniforms.
var _wet_materials: Array[ShaderMaterial] = []
var _night_materials: Array[ShaderMaterial] = []
var _sky_textures := {} ## sky uniform -> path currently bound
## The circuit's real surroundings from OpenStreetMap (surroundings.gd), or null where there is no data
var surroundings: RefCounted
var far_land: RefCounted ## far_land.gd: the hills and sea on the horizon, null where there is no data
## Marshal posts, braking boards, bridges and the paddock (trackside_furniture.gd)
var furniture: RefCounted
## The detailed terrain's grid (_build_terrain): corner, spacing, and per point its height, squared distance to
## the nearest centreline sample and that sample
var _terrain_grid := {}
var _hdri_weight := 0.0 ## how much of the sky is HDRI (its sun then decides the light direction)
static var _noise := {}

## Camera modes:
## 0 = Chase | 1 = Far Chase | 2 = Roof cam | 3 = Trackside TV | 4 = Bird's-eye | 5 = full-track overview
var camera_mode := 0
enum TvKind { TOWER, GROUND, LONG }
## Per kind, how far ahead of the car (m) a camera must be to be cut to and how far ahead it is when the shot
## ends (negative: once the car is past), the width of road (m) to frame, and the lens limits (degrees)
const TV_MIN_AHEAD := [40.0, 130.0, 210.0]
const TV_END_AHEAD := [-45.0, 22.0, 70.0]
const TV_FRAME := [12.0, 9.0, 7.0]
const TV_FOV_MIN := [16.0, 20.0, 5.0]
const TV_FOV_MAX := [55.0, 50.0, 22.0]
## What the director cuts to, in turn
const TV_SEQUENCE := [TvKind.GROUND, TvKind.TOWER, TvKind.LONG, TvKind.GROUND, TvKind.LONG, TvKind.TOWER]
const CAMERA_NAMES := ["CHASE", "FAR CHASE", "ROOF CAM", "TRACKSIDE TV", "BIRD'S-EYE", "FULL TRACK"]
## Fraction of a simulation tick elapsed since the last step (set by the game loop each frame).
var render_alpha := 1.0
## The next camera update jumps straight to its target (race start).
var camera_snap := true
var _cam_head := 0.0
var _focus_pos := Vector3.ZERO
var _focus_heading := 0.0
var _focus_s := 0.0

## Trackside TV camera positions along the track, their distance along it and their kind: a high tower
## camera, a low camera behind the fence that pans with the car, or a low telephoto looking up a straight
var tv_cameras: Array[Vector3] = []
var tv_camera_s := PackedFloat64Array()
var tv_camera_kind := PackedInt32Array()
var _tv_index := -1
var _tv_shot := 0
var _tv_look := Vector3.ZERO
var _tv_prev_pos := Vector3.ZERO

## Start gantry lights
var start_lights: Array[MeshInstance3D] = []
var _lights_lit := -1

## Pit garages: the team-coloured bands over the doors (one instance per garage) and each garage's box
var pit_bands: MultiMesh
var pit_band_boxes := PackedInt32Array()
var race_control_s := NAN ## where race control stands along the lap (NAN when it did not fit)
static var _trackside := {} ## Blender trackside meshes by object name
var _crowd_material: ShaderMaterial ## the grandstands' crowd (_stand_crowd_material), for _crowd_material_track
var _crowd_material_track: Track

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

## Street lamps, floodlights and tunnel lamps: every fixture is a point here; the pooled lights are handed
## to the ones nearest the camera, and the emissive lamp heads follow the hour.
var _lamp_pos := PackedVector3Array()
var _lamp_color := PackedColorArray()
var _lamp_energy := PackedFloat32Array()
var _lamp_range := PackedFloat32Array()
var _lamp_always := PackedByteArray() ## 1 for lamps that burn by day too (the tunnel)
var _lamp_pool: Array[OmniLight3D] = []
var _lamp_material: StandardMaterial3D
var _lamp_pick := PackedInt32Array()
var _lamp_pick_d2 := PackedFloat32Array()
var _lamp_on := 0.0
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
		# MetalFX's temporal upscaler cannot take a multisampled scene
		vp.msaa_3d = Viewport.MSAA_DISABLED if vp.scaling_3d_mode == Viewport.SCALING_3D_MODE_METALFX_TEMPORAL \
			else [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X][quality] # SMAA covers High
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
		world_environment.ssil_enabled = quality >= 3
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
	pit_bands = null
	pit_band_boxes.clear()
	race_control_s = NAN
	tv_cameras.clear()
	tv_camera_s.clear()
	tv_camera_kind.clear()
	_wet_materials.clear()
	_night_materials.clear()
	_lamp_pos.clear()
	_lamp_color.clear()
	_lamp_energy.clear()
	_lamp_range.clear()
	_lamp_always.clear()
	_lamp_pool.clear()
	_lamp_material = null
	_lights_lit = -1
	_skid_instance = null
	_atmos_key = Vector3(-1.0, -1.0, -1.0) # the new materials pick up the current weather

	_build_track()
	_reset_skids()
	position_overview()
	if ray_tracing:
		ray_tracing.invalidate(true)

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
	if value.rc:
		var sc_visual := CAR_SCENE.instantiate()
		visuals[value.rc.sc.id] = sc_visual
		cars_root.add_child(sc_visual)
		sc_visual.make_safety_car()
	if ray_tracing:
		ray_tracing.invalidate(false)
	_rank_cars.resize(value.cars.size())
	_rank_d2.resize(value.cars.size())
	_paint_pit_bands()

	overview = false
	camera_snap = true
	_tv_index = -1
	_tv_shot = 0
	_lights_lit = -1

func _process(delta: float) -> void:
	if not track or not camera:
		return

	if overview or not race:
		_update_atmosphere(14.0, 0.0, 0.0)
		_hide_beams()
		_hide_lamp_lights()
		camera.global_position = camera.global_position.lerp(overview_target, 1.0 - exp(-2.4 * delta))
		camera.look_at(Vector3(overview_target.x, 0, overview_target.z), Vector3.FORWARD)
		return
	_update_atmosphere(race.time_of_day, race.weather.wet, race.weather.rain)
	CAR_VISUAL.set_night(night)

	var focus := race.player
	var a := clampf(render_alpha, 0.0, 1.0)
	var rc := race.rc
	for car in (race.cars + [rc.sc] if rc else race.cars):
		var visual = visuals.get(car.id)
		if not visual:
			continue
		if car.is_safety_car:
			visual.visible = rc.sc_state != "garage"
		else:
			# a crashed car stays where it stopped until the marshals have cleared it
			visual.visible = (not car.dnf or car.speed > 0.1 or car.stranded) and not car.recovered
		if not visual.visible:
			continue
		# draw between the last two simulation ticks so motion is smooth at any refresh rate
		var x: float = car.x
		var y: float = car.y
		var heading: float = car.heading
		var s: float = car.s
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
	_update_lamp_lights()

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
	sky_top_color = top
	sky_horizon_color = horizon
	var az := deg_to_rad(sun_v[1])
	# the sun where it really is; after dark a high, dim moonlight instead of light from under the ground
	var light_deg := lerpf(34.0, maxf(el, 10.0), day_t)

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
	var hdri_el := _update_sky_hdri(el, az, hour, day_t, overcast, sky_luma, first)
	if not is_nan(hdri_el):
		# the light comes from where the panorama's own sun or moon is, so shading matches the sky
		light_deg = lerpf(light_deg, maxf(hdri_el, 8.0), _hdri_weight)
	sun.basis = Basis.looking_at(-_sky_dir(deg_to_rad(light_deg), az), Vector3.UP)
	# the panoramas carry their own clouds, so the procedural layer only adds a faint drift over them
	sky_material.set_shader_parameter("cloud_opacity", lerpf(1.0, 0.3, _hdri_weight))

	world_environment.ambient_light_energy = lerpf(0.3, 1.0, day_t) * (1.0 - overcast * 0.2)
	world_environment.ambient_light_color = AMBIENT_NIGHT.lerp(Color.WHITE, day_t)
	sun.light_energy = lerpf(0.1, 1.6, day_t) * (1.0 - overcast * 0.62)
	sun.light_color = SUN_NIGHT.lerp(SUN_DAY, day_t).lerp(DUSK_GLOW, glow * 0.45)
	sun.shadow_opacity = lerpf(0.55, 1.0, day_t) * (1.0 - overcast * 0.45)
	# haze thickens in the rain and takes on the horizon colour, so the distance melts into the sky
	world_environment.fog_light_color = FOG_NIGHT.lerp(horizon, day_t).lerp(FOG_RAIN * lerpf(0.15, 1.0, day_t), overcast * 0.6)
	world_environment.fog_density = 0.00032 + 0.00045 * overcast + 0.0024 * rain
	world_environment.fog_sun_scatter = 0.18 * glow + 0.05 * (1.0 - overcast) * day_t
	if far_land:
		far_land.material.set_shader_parameter("haze_color", world_environment.fog_light_color)
		far_land.material.set_shader_parameter("haze_density", world_environment.fog_density)
	world_environment.glow_hdr_threshold = lerpf(1.0, 0.75, night)
	# volumetric fog shows the headlight beams in the rain and after dark (High and Ultra only)
	var volumetric := quality >= 2 and (rain > 0.08 or night > 0.45)
	if world_environment.volumetric_fog_enabled != volumetric:
		world_environment.volumetric_fog_enabled = volumetric
	world_environment.volumetric_fog_density = 0.002 + 0.008 * rain + 0.002 * night
	world_environment.volumetric_fog_albedo = Color(0.9, 0.92, 0.95).lerp(Color(0.62, 0.66, 0.72), night)
	for m in _wet_materials:
		m.set_shader_parameter("wet", wet)
		m.set_shader_parameter("rain", rain)
	for m in _night_materials:
		m.set_shader_parameter("night", night)
	_lamp_on = smoothstep(0.08, 0.55, night)
	if _lamp_material:
		_lamp_material.emission_energy_multiplier = 7.0 * _lamp_on
	if rain_particles:
		rain_particles.emitting = rain > 0.03
		rain_particles.amount_ratio = clampf(rain, 0.0, 1.0)

static func _sky_dir(el: float, az: float) -> Vector3:
	return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))

## Blends the two HDRI skies nearest the sun's elevation (same half of the day where the file names say
## so), each turned so its own sun sits where the game's sun is, and brought to the brightness of the
## procedural sky at that hour. Overcast HDRIs take over in the wet; a night HDRI (if any) after dark.
func _update_sky_hdri(el: float, az: float, hour: float, day_t: float, overcast: float, target: float, wait: bool) -> float:
	_hdri_weight = 0.0
	if assets == null or not assets.has_skies():
		sky_material.set_shader_parameter("hdri_mix", 0.0)
		sky_material.set_shader_parameter("hdri_o_mix", 0.0)
		return NAN
	var half := "am" if hour < 13.75 else "pm"
	var ladder: Array = []
	# the night panoramas take distinct steps below the twilight ones (highest moon first), so none of them
	# shares an elevation with another and the sky never switches between two of them in one frame
	var nights: Array = assets.skies_of("night")
	nights.sort_custom(func(x, y): return x.el > y.el)
	for i in nights.size():
		var entry: Dictionary = nights[i].duplicate()
		entry.sky_el = entry.el
		entry.el = lerpf(-8.0, -18.0, float(i) / float(nights.size() - 1)) if nights.size() > 1 else -14.0
		ladder.append(entry)
	var clear: Array = assets.skies_of("clear").filter(func(e): return e.half == "" or e.half == half)
	if clear.is_empty():
		clear = assets.skies_of("clear")
	for c in clear:
		var entry: Dictionary = c.duplicate()
		entry.sky_el = entry.el
		ladder.append(entry)
	var light_el := NAN
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
		# both panoramas must be resident before either is swapped in, otherwise the old pair would be drawn
		# with the new pair's rotation and gain (a visible jump)
		var tex_a: Texture2D = _sky_texture_for("hdri_a", a.path, wait)
		var tex_b: Texture2D = _sky_texture_for("hdri_b", b.path, wait)
		if tex_a and tex_b:
			_apply_sky("hdri_a", a.path, tex_a)
			_apply_sky("hdri_b", b.path, tex_b)
			var ab := smoothstep(0.0, 1.0, t)
			var gain_boost := lerpf(1.0, 0.6, night) # night HDRIs are kept a little darker than the palette
			sky_material.set_shader_parameter("hdri_rot_a", a.az - az)
			sky_material.set_shader_parameter("hdri_rot_b", b.az - az)
			sky_material.set_shader_parameter("hdri_gain_a", target / maxf(a.mean, 1e-5) * gain_boost)
			sky_material.set_shader_parameter("hdri_gain_b", target / maxf(b.mean, 1e-5) * gain_boost)
			sky_material.set_shader_parameter("hdri_ab", ab)
			sky_material.set_shader_parameter("hdri_mix", mix)
			light_el = lerpf(a.sky_el, b.sky_el, ab)
			_hdri_weight = mix
		# warm the next panorama up on the worker thread so the following swap is instant
		var next_i := 0
		for i in ladder.size():
			if ladder[i].path == b.path:
				next_i = i
		for i in [next_i + 1, next_i - 1]:
			if i >= 0 and i < ladder.size():
				assets.sky_texture(ladder[i].path, false)
	var grey: Array = assets.skies_of("overcast")
	var o_mix := 0.0
	if not grey.is_empty():
		var pick: Dictionary = grey[absi(hash(track.cfg.key if track else "")) % grey.size()]
		o_mix = smoothstep(0.18, 0.7, overcast) * clampf(day_t * 1.5, 0.0, 1.0)
		var tex_o: Texture2D = _sky_texture_for("hdri_o", pick.path, wait) if o_mix > 0.0 else null
		if tex_o:
			_apply_sky("hdri_o", pick.path, tex_o)
			sky_material.set_shader_parameter("hdri_gain_o", target / maxf(pick.mean, 1e-5))
		elif _sky_textures.get("hdri_o", "") != pick.path:
			o_mix = 0.0
	sky_material.set_shader_parameter("hdri_o_mix", o_mix)
	return light_el

## The panorama for a uniform: the bound one, or the newly wanted one once it has loaded (null until then).
func _sky_texture_for(uniform: String, path: String, wait: bool) -> Texture2D:
	return assets.sky_texture(path, wait or not _sky_textures.has(uniform))

func _apply_sky(uniform: String, path: String, tex: Texture2D) -> void:
	if _sky_textures.get(uniform, "") == path:
		return
	sky_material.set_shader_parameter(uniform, tex)
	_sky_textures[uniform] = path

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
			var cut := snap or _tv_index < 0 or tv_cameras[_tv_index].distance_to(p) > 450.0
			if not cut:
				var along := track.rel(tv_camera_s[_tv_index] - _focus_s)
				cut = along < TV_END_AHEAD[tv_camera_kind[_tv_index]]
			if cut:
				_tv_index = _pick_tv_camera()
			var kind := tv_camera_kind[_tv_index]
			camera.global_position = tv_cameras[_tv_index]
			# an operator's pan: lead the car by its velocity so it stays framed, but smooth the aim and the zoom
			# so the pan does not whip past when the car is closest and the shot does not pump as it comes and goes
			# capped, since a change of focus to another car moves p a long way in one frame
			var vel := Vector3.ZERO if cut or delta <= 0.0 else ((p - _tv_prev_pos) / delta).limit_length(90.0)
			_tv_prev_pos = p
			var target := p + Vector3.UP * 0.6 + vel * (1.0 / 9.0)
			_tv_look = target if cut else _tv_look.lerp(target, _ease(9.0, delta, false))
			camera.look_at(_tv_look, Vector3.UP)
			var want_fov := clampf(rad_to_deg(2.0 * atan(TV_FRAME[kind] / maxf(1.0, camera.global_position.distance_to(_tv_look)))), TV_FOV_MIN[kind], TV_FOV_MAX[kind])
			camera.fov = want_fov if cut else camera.fov + (want_fov - camera.fov) * _ease(3.0, delta, false)
			return
		4: # bird's-eye, car pointing up the screen
			var want := p + Vector3.UP * (55.0 + v * 0.8)
			camera.global_position = camera.global_position.lerp(want, _ease(8.0, delta, snap))
			camera.look_at(p, fwd)
			fov = 55.0
	camera.fov += (fov - camera.fov) * _ease(4.0, delta, snap)

## The director's next cut: the nearest camera of the next kind in the sequence that is far enough ahead of
## the car, or of any kind if that one has nothing in reach.
func _pick_tv_camera() -> int:
	var want: int = TV_SEQUENCE[_tv_shot % TV_SEQUENCE.size()]
	_tv_shot += 1
	var best := -1
	var best_ahead := INF
	for pass_kind in 2:
		for i in tv_camera_s.size():
			var kind := tv_camera_kind[i]
			if pass_kind == 0 and kind != want:
				continue
			var ahead_m := fposmod(tv_camera_s[i] - _focus_s, track.L)
			if ahead_m >= TV_MIN_AHEAD[kind] and ahead_m < best_ahead:
				best_ahead = ahead_m
				best = i
		if best >= 0:
			return best
	return maxi(0, best)

func cycle_camera() -> String:
	camera_mode = (camera_mode + 1) % 5
	if camera_mode == 3:
		_tv_index = -1 # pick the camera afresh: the car has moved on since the TV view was last used
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
	# REALTIME would redraw all six radiance faces and their mip chain every frame because the shader reads TIME;
	# INCREMENTAL only refreshes the ambient and reflection light when the sky's parameters change (every few
	# seconds of race time), and the visible sky still animates
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
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
	world_environment.volumetric_fog_anisotropy = 0.3
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
	sun.light_volumetric_fog_energy = 0.35 # the fog is there for the headlight beams, not to glow in daylight
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

	ray_tracing = RayTracing.new()
	add_child(ray_tracing)
	var effects: Array[CompositorEffect] = [ray_tracing.effect]
	camera.compositor = Compositor.new()
	camera.compositor.compositor_effects = effects

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
	surroundings = SURROUNDINGS.new()
	if not surroundings.setup(self):
		surroundings = null
	_build_terrain(ground)
	far_land = FAR_LAND.new()
	if far_land.build(self, track_root):
		ground.visible = false # the far land reaches the horizon; the flat plane would only hide it
		_wet_materials.append(far_land.material)
	else:
		far_land = null

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
	_build_pit_garages()

	# 6. Armco barriers / guardrails along runoff edges, and covered sections (Monaco's tunnel)
	_build_barriers()
	_build_tunnels()
	_build_bridges()

	# 7. Racing line assist
	_build_racing_line()

	# 8. Trackside TV cameras (first, so the trees can leave them a clear view), then roadside trees
	_setup_tv_cameras()
	_build_tv_towers()
	_build_trees(extent)

	# 9. Circuit-specific venue structures
	_build_grandstands()
	_build_lighting()
	if surroundings:
		surroundings.build()
	furniture = FURNITURE.new()
	furniture.build(self)
	if track.cfg.theme == "city":
		if not (surroundings and surroundings.has_buildings()):
			_build_city_blocks()
		if track.cfg.sea:
			_build_monaco_harbor(extent)
			_build_casino_landmark()

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
	var point_height := PackedFloat32Array() # world y of each terrain vertex, for things set on the ground
	point_height.resize(grid_size)
	point_height.fill(NAN)
	var radius := ceili(band / fine) + 1
	var radius_squared := float(radius * radius)
	var road_clearance := _terrain_clear_distance()

	# Splat nearby centreline samples onto a compact grid; this keeps terrain under every road section.
	var track_x := track.X
	var track_y := track.Y
	var track_h := track.H
	for sample_index in track.n:
		var sx := track_x[sample_index]
		var sz := track_y[sample_index]
		var cap_base := track_h[sample_index] - elevation_base - 0.35
		var cx := roundi((sx - x0) / fine)
		var cz := roundi((sz - z0) / fine)
		for dz in range(-radius, radius + 1):
			var grid_z := cz + dz
			if grid_z < 0 or grid_z > nz or float(dz * dz) > radius_squared:
				continue
			var dx_limit := floori(sqrt(radius_squared - float(dz * dz)))
			var ddz := z0 + grid_z * fine - sz
			var ddz2 := ddz * ddz
			for grid_x in range(maxi(cx - dx_limit, 0), mini(cx + dx_limit, nx) + 1):
				var ddx := x0 + grid_x * fine - sx
				var distance_squared := ddx * ddx + ddz2
				var cell := grid_z * row + grid_x
				height_cap[cell] = minf(height_cap[cell], cap_base + maxf(0.0, sqrt(distance_squared) - road_clearance) * 0.45)
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
	terrain_material.set_shader_parameter("tex_color_mix", 0.1)
	terrain_material.set_shader_parameter("slope_rock", 0.4 if track.cfg.theme == "city" else 1.0)
	if surroundings:
		surroundings.apply_land_map(terrain_material)
	var band_squared := band * band
	var terrain_vertices := PackedVector3Array()
	var terrain_colors := PackedColorArray()
	var terrain_indices := PackedInt32Array()
	# every grid point is computed once and its vertex shared by the cells round it
	var vertex_of := PackedInt32Array()
	vertex_of.resize(grid_size)
	vertex_of.fill(-1)
	var corners := PackedInt32Array([0, 0, 0, 0])
	for z_idx in nz:
		for x_idx in nx:
			var i00 := z_idx * row + x_idx
			var i10 := i00 + 1
			var i01 := i00 + row
			var i11 := i01 + 1
			if minf(minf(nearest_distance[i00], nearest_distance[i10]), minf(nearest_distance[i01], nearest_distance[i11])) >= band_squared:
				continue
			corners[0] = i00
			corners[1] = i10
			corners[2] = i01
			corners[3] = i11
			for point_idx in corners:
				if vertex_of[point_idx] >= 0:
					continue
				vertex_of[point_idx] = terrain_vertices.size()
				var px: float = x0 + (point_idx % row) * fine
				var pz: float = z0 + floori(float(point_idx) / float(row)) * fine
				var distance := sqrt(nearest_distance[point_idx]) if nearest_index[point_idx] >= 0 else INF
				var y := _terrain_height(px, pz, nearest_index[point_idx], distance, height_cap[point_idx], grid) * ALTITUDE_SCALE
				point_height[point_idx] = y
				terrain_vertices.append(Vector3(px - world_center.x, y, pz - world_center.y))
				terrain_colors.append(_terrain_color(px, pz, base_color))
			var v00 := vertex_of[i00]
			var v10 := vertex_of[i10]
			var v01 := vertex_of[i01]
			var v11 := vertex_of[i11]
			terrain_indices.append_array(PackedInt32Array([v00, v01, v10, v10, v01, v11]))
	_terrain_grid = {"x0": x0, "z0": z0, "fine": fine, "row": row, "nx": nx, "nz": nz, "h": point_height,
		"d2": nearest_distance, "i": nearest_index}
	if not terrain_vertices.is_empty():
		var terrain_arrays := []
		terrain_arrays.resize(Mesh.ARRAY_MAX)
		terrain_arrays[Mesh.ARRAY_VERTEX] = terrain_vertices
		terrain_arrays[Mesh.ARRAY_COLOR] = terrain_colors
		terrain_arrays[Mesh.ARRAY_INDEX] = terrain_indices
		var terrain_st := SurfaceTool.new()
		terrain_st.create_from_arrays(terrain_arrays)
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

## Distance from the centreline out to which the terrain sits just under the road. A terrain cell is `fine` wide,
## so a vertex lifted any nearer would tilt the triangles that span the road edge up through the tarmac.
func _terrain_clear_distance() -> float:
	var fine := maxf(track.cfg.terrain_fine * 2.0, 18.0)
	return track.half + track.cfg.runoff + 3.0 + fine * 1.5

func _terrain_height(x: float, z: float, nearest: int, distance: float, cap: float, grid: Dictionary) -> float:
	var dem_height := _sample_dem(grid, x, z) - elevation_base
	var height := dem_height - 1.0
	if nearest >= 0 and distance <= 175.0:
		var track_height := track.H[nearest] - elevation_base
		var clear_distance := _terrain_clear_distance()
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

	# 2. Overhead gantry (Blender pieces): lattice legs, a box truss stretched across the road and the
	# start-light housing, with two rows of five lights (both rows of a column share one material)
	var gantry_root := Node3D.new()
	gantry_root.name = "Gantry"
	gantry_root.position = s0_pos
	gantry_root.rotation.y = -heading
	track_root.add_child(gantry_root)
	var parts := trackside_meshes()
	var leg_z := track.half + 2.2
	for side in [-1.0, 1.0]:
		_add_part(gantry_root, parts, "GantryLeg", Transform3D(Basis.IDENTITY, Vector3(0, -0.09, side * leg_z)))
	_add_part(gantry_root, parts, "GantryBeam", Transform3D(Basis.from_scale(Vector3(1, 1, leg_z * 2.0 / 10.0)), Vector3(0, GANTRY_BEAM_Y, 0)))
	_add_part(gantry_root, parts, "GantryLights", Transform3D(Basis.IDENTITY, Vector3(0, GANTRY_BEAM_Y, 0)))
	var disc := CylinderMesh.new()
	disc.top_radius = 0.22
	disc.bottom_radius = 0.22
	disc.height = 0.06
	disc.radial_segments = 16
	for i in 5:
		var lmat := StandardMaterial3D.new()
		lmat.albedo_color = START_LIGHT_OFF
		# emission stays enabled (energy 0 when off) so switching a light never swaps shaders
		lmat.emission_enabled = true
		lmat.emission = START_LIGHT_ON
		lmat.emission_energy_multiplier = 0.0
		for row in 2:
			var light := MeshInstance3D.new()
			light.mesh = disc
			light.rotation.z = PI / 2.0
			light.position = Vector3(-0.64, GANTRY_BEAM_Y - (0.8 if row == 0 else 1.35), -(i - 2) * 1.1)
			light.material_override = lmat
			light.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			gantry_root.add_child(light)
			if row == 0:
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
	# three columns: the lane's outer edge, its inner edge, and the point on the track's edge it joins.
	# While the lane leaves or rejoins the track the last two pull apart, paving the wedge between them.
	for step_idx in (steps + 1):
		var s := p0 + (p1 - p0) * (float(step_idx) / float(steps))
		var blend := track.pit_blend(s)
		# where it meets the track the whole lane lies under the track's asphalt, not out on the run-off
		var center_d := sg * (track.half - 3.2) * (1.0 - blend) + (po + sg * 1.0) * blend
		# between the run-off (0.01) and the track's asphalt (0.04), so where the two overlap the track is on top
		var y := (track.sample(track.H, s) - elevation_base) * ALTITUDE_SCALE + 0.025

		var inner_d := center_d - sg * 3.2
		var join_d := lerpf(sg * (track.half - 3.2), inner_d, blend)
		for d_col in [center_d + sg * 3.2, inner_d, join_d]:
			var p := track.pos(s, d_col)
			vertices.append(Vector3(p[0] - world_center.x, y, p[1] - world_center.y))
		uvs.append_array(PackedVector2Array([Vector2(3.2 * sg, s), Vector2(-3.2 * sg, s), Vector2(join_d - center_d, s)]))
		uv2s.append_array(PackedVector2Array([Vector2(3.2 * sg, 0.0), Vector2(-3.2 * sg, 0.0), Vector2(join_d - center_d, 0.0)]))

	for step_idx in steps:
		for col in 2:
			var a := step_idx * 3 + col
			var b := a + 1
			var c := (step_idx + 1) * 3 + col
			var d := c + 1
			# the columns run outer to inner, so the winding follows the side the lane is on
			if sg < 0.0:
				indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
			else:
				indices.append_array(PackedInt32Array([a, b, c, b, d, c]))

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
		# the wall sinks into the ground over its last few metres instead of ending in a blunt face
		var end_gap := minf(s - wall_s0, wall_s1 - s)
		wall_verts.append(base_p)
		wall_verts.append(base_p + Vector3.UP * lerpf(0.1, 1.15, clampf(end_gap / 12.0, 0.0, 1.0)))

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

## The pit building along the lane (Blender pieces): one garage per box, each with its team's colours
## over the door, a glazed hospitality floor with a balcony and a roof terrace; end walls, and race
## control beside the pit exit.
func _build_pit_garages() -> void:
	var span := _garage_span()
	if span == Vector2.ZERO:
		return
	var parts := trackside_meshes()
	if not parts.has("PitBay"):
		return
	var cfg := track.cfg
	var sg := signf(cfg.pit_offset)
	var front := cfg.pit_offset + sg * 5.4
	var spacing := cfg.box_spacing
	var stretch := Basis.from_scale(Vector3(spacing / PIT_BAY, 1.0, 1.0))
	var bays: Array[Transform3D] = []
	var boxes := PackedInt32Array()
	# a garage per box, plus a spare one at each end where the lane is still full width
	for i in range(-1, 17):
		var s := track.box_s(i)
		if i < 0 or i > 15:
			if s - spacing * 0.5 < span.x or s + spacing * 0.5 > span.y:
				continue
		bays.append(_pit_frame(s, front, sg) * Transform3D(stretch, Vector3.ZERO))
		boxes.append(i)
	if bays.is_empty():
		return
	var root := Node3D.new()
	root.name = "PitGarages"
	track_root.add_child(root)
	_add_multimesh(root, "Bays", _multimesh(parts.PitBay, bays, []), null)
	var band_mm := MultiMesh.new()
	band_mm.transform_format = MultiMesh.TRANSFORM_3D
	band_mm.use_colors = true
	band_mm.mesh = parts.PitBayBand
	band_mm.instance_count = bays.size()
	for k in bays.size():
		band_mm.set_instance_transform(k, bays[k])
		band_mm.set_instance_color(k, Color("#d8dadd"))
	pit_bands = band_mm
	pit_band_boxes = boxes
	var band_mat := _material(Color.WHITE, 0.45)
	band_mat.vertex_color_use_as_albedo = true
	_add_multimesh(root, "TeamBands", band_mm, band_mat)
	# end walls: local +x runs along the lane or against it, depending on the side
	var along := _pit_frame(track.box_s(boxes[0]), front, sg).basis.x.dot(_tangent(track.box_s(boxes[0]))) > 0.0
	var first := bays[0]
	var last := bays[bays.size() - 1]
	_add_part(root, parts, "PitEndL" if along else "PitEndR", first)
	_add_part(root, parts, "PitEndR" if along else "PitEndL", last)
	# race control just past the last garage (towards the exit), or before the first one
	var lookup := _track_lookup(24.0)
	var clear := track.half + cfg.runoff * 0.5 + 1.0
	for s in [track.box_s(boxes[boxes.size() - 1]) + spacing * 0.5 + 7.6, track.box_s(boxes[0]) - spacing * 0.5 - 7.6]:
		var xf := _pit_frame(s, front, sg)
		var p := track.pos(s, front)
		if _footprint_clear(lookup, p, xf.basis.get_euler().y, Rect2(-7.4, -PIT_DEPTH - 0.5, 14.8, PIT_DEPTH + 2.5), clear):
			_add_part(root, parts, "RaceControl", xf)
			race_control_s = s
			break

## Frame of a pit piece at s: origin at the garage front line (front metres from the centreline), local
## -z pointing away from the lane.
func _pit_frame(s: float, front: float, side: float) -> Transform3D:
	var p := track.pos(s, front)
	var basis := Basis(Vector3.UP, -track.heading(s) + (PI if side > 0.0 else 0.0))
	return Transform3D(basis, Vector3(p[0] - world_center.x, _road_y(s) - 0.09, p[1] - world_center.y))

## Direction of travel at s, in world x/z.
func _tangent(s: float) -> Vector3:
	var h := track.heading(s)
	return Vector3(cos(h), 0.0, sin(h))

## Paints each garage's band in the colours of the car that uses that box.
func _paint_pit_bands() -> void:
	if furniture and race:
		furniture.paint(race) # the transporters too
	if not pit_bands or not race:
		return
	var by_box := {}
	for car in race.cars:
		by_box[car.box] = car.color
	for k in pit_band_boxes.size():
		pit_bands.set_instance_color(k, by_box.get(pit_band_boxes[k], Color("#d8dadd")))

## Where the pit building runs, as distances from the start line: from before the first box to after the
## sixteenth, kept within the full-width part of the lane. Vector2.ZERO when the track has no pit lane.
func _garage_span() -> Vector2:
	var cfg := track.cfg
	if absf(cfg.pit_offset) < 1.0:
		return Vector2.ZERO
	var g0 := maxf(track.box_s(0) - cfg.box_spacing * 0.5 - 8.0, track.lane_start)
	var g1 := minf(track.box_s(15) + cfg.box_spacing * 0.5 + 8.0, track.lane_end)
	return Vector2(g0, g1) if g1 - g0 > 20.0 else Vector2.ZERO

func _pit_point(s: float, d: float, h: float) -> Vector3:
	var p := track.pos(s, d)
	return Vector3(p[0] - world_center.x, _road_y(s) - 0.09 + h, p[1] - world_center.y)

## The Blender-built trackside pieces (tools/blender/build_trackside.py) by object name.
static func trackside_meshes() -> Dictionary:
	if _trackside.is_empty():
		var root: Node = WORLD_ASSETS._load_model(TRACKSIDE_PATH)
		if root:
			for mi in root.find_children("*", "MeshInstance3D", true, false):
				_trackside[mi.name] = (mi as MeshInstance3D).mesh
			root.free()
	return _trackside

func _add_part(parent: Node3D, parts: Dictionary, part: String, xf: Transform3D) -> MeshInstance3D:
	if not parts.has(part):
		return null
	var inst := MeshInstance3D.new()
	inst.name = part
	inst.mesh = parts[part]
	inst.transform = xf
	parent.add_child(inst)
	return inst

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
	# a see-through chain-link catch fence: the wire texture thins to a faint veil in the distance, as
	# the real thing does, rather than a tinted sheet
	var fence_mat := _material(Color("#b4b9bc"), 0.55)
	fence_mat.metallic = 0.6
	fence_mat.albedo_texture = _chain_link_texture()
	fence_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	fence_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fence_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var rail_verts := PackedVector3Array()
	var fence_posts: Array[Transform3D] = []
	var post_every := maxi(1, roundi(4.0 / track.step))
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
		var fence_uvs := PackedVector2Array()
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
				# texture repeats every 0.25 m along and up the fence
				var u0 := s / 0.25
				var u1 := u0 + track.step / 0.25
				var vt := (fence_top - wall_top) / 0.25
				fence_uvs.append_array(PackedVector2Array([Vector2(u0, vt), Vector2(u0, 0.0), Vector2(u1, vt), Vector2(u1, 0.0)]))
				# a steel top rail, and a post every few metres
				rail_verts.append_array(PackedVector3Array([f2 + Vector3.DOWN * 0.08, f3 + Vector3.DOWN * 0.08, f2 + Vector3.UP * 0.04,
					f3 + Vector3.DOWN * 0.08, f3 + Vector3.UP * 0.04, f2 + Vector3.UP * 0.04]))
				if i % post_every == 0:
					fence_posts.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, fence_top - wall_top, 1.0)), (f0 + f2) * 0.5))
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
			f_arrays[Mesh.ARRAY_TEX_UV] = fence_uvs
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
			f_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			track_root.add_child(f_inst)

	if not rail_verts.is_empty():
		var steel := _material(Color("#8d9296"), 0.45)
		steel.metallic = 0.7
		steel.cull_mode = BaseMaterial3D.CULL_DISABLED
		var r_arrays := []
		r_arrays.resize(Mesh.ARRAY_MAX)
		r_arrays[Mesh.ARRAY_VERTEX] = rail_verts
		var r_st := SurfaceTool.new()
		var r_mesh := ArrayMesh.new()
		r_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, r_arrays)
		r_st.create_from(r_mesh, 0)
		r_st.generate_normals()
		var rail := MeshInstance3D.new()
		rail.name = "FenceRail"
		rail.mesh = r_st.commit()
		rail.material_override = steel
		track_root.add_child(rail)
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.11, 1.0, 0.11)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = post_mesh
		mm.instance_count = fence_posts.size()
		for k in fence_posts.size():
			mm.set_instance_transform(k, fence_posts[k])
		var posts := MultiMeshInstance3D.new()
		posts.name = "FencePosts"
		posts.multimesh = mm
		posts.material_override = steel
		track_root.add_child(posts)

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

## Covered sections from the track data (sample ranges along the OSM chain): walls either side, a roof
## that shades the road, portal faces at both ends and a row of lamps down the middle, as in the JS version.
func _build_tunnels() -> void:
	if track.tunnels.is_empty():
		return
	var off := SimUtil.js_round(track.cfg.start_offset / track.step)
	var wd := track.half + track.cfg.runoff + 0.6 # inner wall
	var wo := wd + 3.0 # outer face of the shell
	var inner_h := 6.2
	var outer_h := 8.0
	var concrete := _material(Color("#9a958b"), 0.9)
	concrete.cull_mode = BaseMaterial3D.CULL_DISABLED
	# the lamps light the tube: a little emission keeps the walls from going black in the roof's shadow
	concrete.emission_enabled = true
	concrete.emission = Color("#3a352c")
	var lamp_mat := _material(Color("#fff0c8"), 0.4)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color("#ffd88a")
	lamp_mat.emission_energy_multiplier = 2.2
	var lamps: Array[Transform3D] = []
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0xFFFFFFFF) # flat faces: square concrete, not a rounded tube
	for range_ab in track.tunnels:
		var s0: float = (float(range_ab[0]) - off) * track.step - 2.0
		var s1: float = (float(range_ab[1]) - off) * track.step + 2.0
		if s1 < s0:
			s1 += track.L
		if s1 - s0 < 30.0:
			continue # short underpasses: nothing to draw
		# cross-section outlines (lateral d, height): the inside of the tube and the outside of the shell
		var inner := [Vector2(-wd, -0.4), Vector2(-wd, inner_h), Vector2(wd, inner_h), Vector2(wd, -0.4)]
		var outer := [Vector2(-wo, -0.6), Vector2(-wo, outer_h), Vector2(wo, outer_h), Vector2(wo, -0.6)]
		var steps := maxi(2, ceili((s1 - s0) / track.step))
		var prev_in: Array = []
		var prev_out: Array = []
		for k in steps + 1:
			var s := s0 + (s1 - s0) * k / steps
			var cur_in := inner.map(func(q: Vector2) -> Vector3: return _tunnel_point(s, q))
			var cur_out := outer.map(func(q: Vector2) -> Vector3: return _tunnel_point(s, q))
			if k > 0:
				for j in inner.size() - 1:
					_quad(st, prev_in[j], prev_in[j + 1], cur_in[j + 1], cur_in[j])
					_quad(st, prev_out[j], prev_out[j + 1], cur_out[j + 1], cur_out[j])
			if k == 0 or k == steps:
				# portal: the face between the tube and the shell
				for j in inner.size() - 1:
					_quad(st, cur_in[j], cur_in[j + 1], cur_out[j + 1], cur_out[j])
			prev_in = cur_in
			prev_out = cur_out
		var p := s0 + 4.0
		while p < s1 - 4.0:
			var c := _tunnel_point(p + 1.75, Vector2(0.0, inner_h - 0.08))
			lamps.append(Transform3D(Basis(Vector3.UP, -track.heading(p + 1.75)), c))
			p += 9.0
	st.generate_normals()
	var shell := MeshInstance3D.new()
	shell.name = "Tunnel"
	shell.mesh = st.commit()
	shell.material_override = concrete
	track_root.add_child(shell)
	if lamps.is_empty():
		return
	var lamp_mesh := BoxMesh.new()
	lamp_mesh.size = Vector3(3.5, 0.08, 0.6)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = lamp_mesh
	mm.instance_count = lamps.size()
	for k in lamps.size():
		mm.set_instance_transform(k, lamps[k])
	var lamp_inst := MultiMeshInstance3D.new()
	lamp_inst.name = "TunnelLamps"
	lamp_inst.multimesh = mm
	lamp_inst.material_override = lamp_mat
	lamp_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	track_root.add_child(lamp_inst)

## A point of a tunnel cross-section: lateral offset q.x (kept inside the curve's centre) and height q.y
## above the road.
func _tunnel_point(s: float, q: Vector2) -> Vector3:
	var p := track.pos(s, track.clamp_d(s, q.x))
	return Vector3(p[0] - world_center.x, _road_y(s) - 0.09 + q.y, p[1] - world_center.y)

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for v in [a, b, c, a, c, d]:
		st.add_vertex(v)

## One 0.25 m tile of chain-link: diamond wires on a clear background, mipmapped so the fence fades to a
## thin haze with distance.
static func _chain_link_texture() -> ImageTexture:
	var size := 32
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in size:
		for y in size:
			# two diagonal wires per tile, each about 2 px wide
			var a := posmod(x + y, size / 2)
			var b := posmod(x - y, size / 2)
			if a < 2 or b < 2:
				img.set_pixel(x, y, Color(0.72, 0.74, 0.76, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## Where the circuit crosses itself (Suzuka's figure of eight): Vector2(upper s, lower s) for each crossing,
## found as the closest pair of centreline samples far apart along the lap and at least 4 m apart in height.
func _crossings() -> Array[Vector2]:
	var lookup := _track_lookup(24.0)
	var cell: float = lookup.cell
	var found: Array[Vector3] = [] # (upper sample, lower sample, distance)
	for i in track.n:
		var key := Vector2i(floori(track.X[i] / cell), floori(track.Y[i] / cell))
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				for j in lookup.get(key + Vector2i(dx, dz), PackedInt32Array()):
					var apart := absi(i - j)
					if mini(apart, track.n - apart) * track.step < 200.0 or track.H[i] - track.H[j] < 4.0:
						continue
					var dist := Vector2(track.X[i] - track.X[j], track.Y[i] - track.Y[j]).length()
					if dist > track.width:
						continue
					# keep the closest pair of each crossing
					var merged := false
					for k in found.size():
						if absi(int(found[k].x) - i) < 60 and absi(int(found[k].y) - j) < 60:
							if dist < found[k].z:
								found[k] = Vector3(i, j, dist)
							merged = true
							break
					if not merged:
						found.append(Vector3(i, j, dist))
	var out: Array[Vector2] = []
	for f in found:
		out.append(Vector2(f.x * track.step, f.y * track.step))
	return out

## A concrete bridge where the circuit crosses itself: a deep deck under the upper road, wide enough for
## its run-off, and an abutment wall along each side of the road passing underneath.
func _build_bridges() -> void:
	var crossings := _crossings()
	if crossings.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0xFFFFFFFF) # flat faces
	var edge := track.half + track.cfg.runoff + 0.8 # deck edge, just outside the upper road's barriers
	var deck_h := 1.6
	for c in crossings:
		var su := c.x
		var sl := c.y
		var sin_a := maxf(absf(sin(track.heading(su) - track.heading(sl))), 0.3)
		# the deck clears the lower road's run-off and abutments; the abutments run under the whole deck
		var half_span := (edge + 2.0) / sin_a + 2.0
		_sweep_box(st, su - half_span, su + half_span, -edge, edge, func(s: float) -> Vector2:
			var top := _road_y(s) - 0.14
			return Vector2(top - deck_h, top))
		var soffit := _road_y(su) - 0.14 - deck_h
		var half_len := (edge + 1.5) / sin_a + 1.5
		for side in [-1.0, 1.0]:
			var d0: float = side * (edge + 0.2)
			_sweep_box(st, sl - half_len, sl + half_len, minf(d0, d0 + side * 1.2), maxf(d0, d0 + side * 1.2), func(s: float) -> Vector2:
				return Vector2(_road_y(s) - 1.0, soffit + 0.02))
	st.generate_normals()
	var mat := _material(Color("#a8a39a"), 0.88)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var inst := MeshInstance3D.new()
	inst.name = "Bridges"
	inst.mesh = st.commit()
	inst.material_override = mat
	track_root.add_child(inst)

## A box swept along the road from s0 to s1 between lateral offsets d0 < d1; y_range(s) gives its (bottom, top).
func _sweep_box(st: SurfaceTool, s0: float, s1: float, d0: float, d1: float, y_range: Callable) -> void:
	var steps := maxi(1, ceili((s1 - s0) / 2.0))
	var prev: Array[Vector3] = []
	for k in steps + 1:
		var s := s0 + (s1 - s0) * k / steps
		var y: Vector2 = y_range.call(s)
		var a := track.pos(s, d0)
		var b := track.pos(s, d1)
		var pa := Vector3(a[0] - world_center.x, 0.0, a[1] - world_center.y)
		var pb := Vector3(b[0] - world_center.x, 0.0, b[1] - world_center.y)
		# ring: bottom-left, top-left, top-right, bottom-right
		var ring: Array[Vector3] = [pa + Vector3.UP * y.x, pa + Vector3.UP * y.y, pb + Vector3.UP * y.y, pb + Vector3.UP * y.x]
		if k > 0:
			for j in 4:
				_quad(st, prev[j], prev[(j + 1) % 4], ring[(j + 1) % 4], ring[j])
		if k == 0:
			_quad(st, ring[0], ring[3], ring[2], ring[1])
		elif k == steps:
			_quad(st, ring[0], ring[1], ring[2], ring[3])
		prev = ring

func _build_racing_line() -> void:
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	# Braking red, cornering amber, flat-out green. The sim's offsets and speed profile are sampled per
	# metre-ish step and jitter, so smooth them circularly before drawing.
	var n: int = track.n
	var win := maxi(2, int(round(6.0 / track.step)))
	var d_s := _smooth_loop(track.RLD, win)
	var y_s := PackedFloat64Array()
	y_s.resize(n)
	var brake := PackedFloat64Array()
	brake.resize(n)
	var slow := PackedFloat64Array()
	slow.resize(n)
	var vtop := 0.0
	for v in track.PROF:
		vtop = maxf(vtop, v)
	for i in n:
		y_s[i] = (track.H[i] - elevation_base) * ALTITUDE_SCALE + 0.055
		var j := (i + 1) % n
		var decel := (track.PROF[i] * track.PROF[i] - track.PROF[j] * track.PROF[j]) / (2.0 * maxf(track.RDS[i], 0.01))
		brake[i] = clampf(decel / (0.35 * 9.81), 0.0, 1.0)
		slow[i] = clampf((0.9 * vtop - track.PROF[i]) / (0.3 * vtop), 0.0, 1.0)
	y_s = _smooth_loop(y_s, win)
	brake = _smooth_loop(brake, win)
	slow = _smooth_loop(slow, win * 2)

	var green := Color("#38df75")
	var amber := Color("#ffc233")
	var brake_red := Color("#ff3228")

	for i in n:
		var s := i * track.step
		var d := d_s[i]
		var p_left := track.pos(s, d - 0.24)
		var p_right := track.pos(s, d + 0.24)

		verts.append(Vector3(p_left[0] - world_center.x, y_s[i] + track.bank_rise(s, d - 0.24), p_left[1] - world_center.y))
		verts.append(Vector3(p_right[0] - world_center.x, y_s[i] + track.bank_rise(s, d + 0.24), p_right[1] - world_center.y))

		var c := green.lerp(amber, slow[i]).lerp(brake_red, minf(brake[i] * 2.0, 1.0))
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

## Circular moving average over +-win samples, repeated twice for a soft, wobble-free curve.
func _smooth_loop(src: PackedFloat64Array, win: int) -> PackedFloat64Array:
	var n := src.size()
	var cur := src
	for _pass in 2:
		var out := PackedFloat64Array()
		out.resize(n)
		for i in n:
			var acc := 0.0
			for q in range(-win, win + 1):
				acc += cur[(i + q + n) % n]
			out[i] = acc / (2 * win + 1)
		cur = out
	return cur

## Woods and clearings of spruce and broadleaf trees standing on the terrain, kept off every part of the
## circuit. Tree models in assets/models/trees replace the procedural ones when present.
func _build_trees(_extent: float) -> void:
	if surroundings:
		return # the real woods come from surroundings.gd
	if track.cfg.theme == "city":
		return # Monaco uses city buildings instead of trees
	var want := mini(int(track.L / 18.0 * track.cfg.tree_density * 2.4 * TREE_SCALE[quality]), int(1500 * TREE_SCALE[quality]))
	if want <= 0:
		return
	var models: Array = _world_assets().tree_variants()
	var kinds := models.size() if not models.is_empty() else 2
	var lookup := _track_lookup(24.0)
	var garages := _garage_span()
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
		if side == signf(track.cfg.pit_offset) and dist < absf(track.cfg.pit_offset) + 26.0 and rel_s > garages.x - 30.0 and rel_s < garages.y + 30.0:
			continue
		if track.cfg.grandstands and side == _stands_side() and dist < 48.0 and rel_s > track.cfg.stands.x - 20.0 and rel_s < track.cfg.stands.y + 20.0:
			continue
		var p := track.pos(s, side * dist)
		if not _clear_of_track(lookup, p[0], p[1], clear_d) or _near_tv_camera(p[0] - world_center.x, p[1] - world_center.y):
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

## Whether a tree at (x, z) would stand in a TV camera's view of the road: round the camera, or on the line
## from it to the centreline.
func _near_tv_camera(x: float, z: float) -> bool:
	var q := Vector2(x, z)
	for i in tv_cameras.size():
		var cam := Vector2(tv_cameras[i].x, tv_cameras[i].z)
		if cam.distance_squared_to(q) < 16.0 * 16.0:
			return true
		var p := track.pos(tv_camera_s[i], 0.0)
		var road := Vector2(p[0] - world_center.x, p[1] - world_center.y)
		if Geometry2D.get_closest_point_to_segment(q, cam, road).distance_squared_to(q) < 9.0 * 9.0:
			return true
	return false

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

## Whether a rectangle (local x, z in metres) of a structure centred at track point p with rotation.y rot
## stays clearance metres from the centreline everywhere, checked on a grid of about 4 m.
func _footprint_clear(lookup: Dictionary, p: PackedFloat64Array, rot: float, rect: Rect2, clearance: float) -> bool:
	var nu := maxi(1, ceili(rect.size.x / 4.0))
	var nv := maxi(1, ceili(rect.size.y / 4.0))
	var c := cos(rot)
	var sn := sin(rot)
	for u in nu + 1:
		for v in nv + 1:
			var lx := rect.position.x + rect.size.x * u / nu
			var lz := rect.position.y + rect.size.y * v / nv
			if not _clear_of_track(lookup, p[0] + lx * c + lz * sn, p[1] - lx * sn + lz * c, clearance):
				return false
	return true

## The centreline sample nearest to (x, z) within reach metres, and its distance: (index, distance),
## or (-1, INF) when there is none.
func _nearest_sample(lookup: Dictionary, x: float, z: float, reach: float) -> Vector2:
	var cell: float = lookup.cell
	var r := ceili(reach / cell)
	var cx := floori(x / cell)
	var cz := floori(z / cell)
	var best := Vector2(-1, INF)
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var bucket = lookup.get(Vector2i(cx + dx, cz + dz))
			if bucket == null:
				continue
			for i in bucket:
				var d := Vector2(track.X[i] - x, track.Y[i] - z).length()
				if d < best.y:
					best = Vector2(i, d)
	return best

## The grandstands face the pits from across the track, as in the JS version.
func _stands_side() -> float:
	return 1.0 if track.cfg.pit_offset < 0.0 else -1.0

## Distance of the grandstands' front row from the centreline, and how deep they are.
func _stands_front() -> float:
	return track.half + track.cfg.runoff + 4.0

func _stands_depth() -> float:
	return _stand_tiers() * STAND_TREAD + STAND_CONCOURSE + 0.5

func _stand_tiers() -> int:
	return clampi(track.cfg.stand_tiers, 3, 14)

## Terrain height (world units) at a point dist metres off the centreline at s, as _build_terrain shapes it.
func _ground_y(x: float, z: float, s: float, dist: float) -> float:
	if typeof(track.grid) != TYPE_DICTIONARY or int(track.grid.get("nx", 0)) < 2:
		return _road_y(s) - 0.09
	var nearest := int(roundf(track.wrap_s(s) / track.step)) % track.n
	return _terrain_height(x, z, nearest, dist, INF, track.grid) * ALTITUDE_SCALE

## Lamps for the dark: street lamps along the city circuit, floodlight masts round the oval and behind the
## grandstands, lamp posts and a light strip along the pit building, and lamps in the tunnel. The fixtures are
## MultiMeshes whose lamp heads glow with the hour; a light per lamp would be hundreds, so a small pool of real
## lights is handed to the lamps nearest the camera each frame (_update_lamp_lights).
func _build_lighting() -> void:
	var cfg := track.cfg
	var lookup := _track_lookup(24.0)
	_lamp_material = _material(Color("#fff4dc"), 0.4)
	_lamp_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_lamp_material.emission_enabled = true
	_lamp_material.emission = Color("#ffe2a8")
	_lamp_material.emission_energy_multiplier = 7.0 * _lamp_on
	var poles: Array[Transform3D] = []
	var arms: Array[Transform3D] = []
	var heads: Array[Transform3D] = []
	var fx := [poles, arms, heads]
	var edge := track.half + cfg.runoff
	var pit_side := signf(cfg.pit_offset)
	var pit_lo := cfg.pit_entry - 10.0
	var pit_hi := cfg.pit_exit + 10.0
	var tunnels := _tunnel_spans()

	# street lamps on alternate sides just behind the barriers
	if cfg.theme == "city":
		var k := 0
		var s := 10.0
		while s < track.L - 5.0:
			var lit := not tunnels.any(func(t: Vector2) -> bool: return _in_span(s, t, 12.0))
			var side := 1.0 if k % 2 == 0 else -1.0
			var rel_s := track.rel(s)
			if absf(cfg.pit_offset) >= 1.0 and side == pit_side and rel_s > pit_lo and rel_s < pit_hi:
				side = -side # the pit building's own lamps stand on that side
			s += 28.0
			k += 1
			if not lit:
				continue
			var c := track.pos(s - 28.0, side * (edge + 1.7))
			if cfg.sea and _sample_dem(track.grid, c[0], c[1]) < 1.0:
				continue # the harbour
			var mid := track.pos(s - 28.0, 0.0)
			_lamp_post(fx, Vector2(c[0], c[1]), _ground_y(c[0], c[1], s - 28.0, edge + 1.7), Vector2(mid[0], mid[1]), false)

	# floodlight masts round the lap, outside the run-off (the city has street lamps instead): on the pit side
	# behind the garages, and alternating sides elsewhere, wherever there is room
	if cfg.theme != "city" and cfg.floodlight_spacing > 0.0:
		var spacing := cfg.floodlight_spacing
		var count := maxi(1, roundi(track.L / spacing))
		for k in count:
			var s := track.L * (k + 0.5) / count
			var rel_s := track.rel(s)
			var in_pits := absf(cfg.pit_offset) >= 1.0 and rel_s > pit_lo and rel_s < pit_hi
			var side := pit_side if in_pits else (1.0 if k % 2 == 0 else -1.0)
			if cfg.theme == "oval" and not in_pits:
				side = -_stands_side()
			if cfg.grandstands and side == _stands_side() and rel_s > cfg.stands.x - 20.0 and rel_s < cfg.stands.y + 20.0:
				continue # the stands have their own masts
			if tunnels.any(func(t: Vector2) -> bool: return _in_span(s, t, 12.0)):
				continue
			var d := side * (absf(cfg.pit_offset) + 24.0 if in_pits else edge + 10.0)
			var c := track.pos(s, d)
			if not _clear_of_track(lookup, c[0], c[1], edge + 6.0):
				d = -d # a bend or another straight in the way: try the other side
				c = track.pos(s, d)
				if not _clear_of_track(lookup, c[0], c[1], edge + 6.0):
					continue
			var mid := track.pos(s, 0.0)
			_lamp_post(fx, Vector2(c[0], c[1]), _ground_y(c[0], c[1], s, absf(d)), Vector2(mid[0], mid[1]), true)

	# floodlight masts behind the grandstands, lighting the crowd and the track in front of them
	if cfg.grandstands and cfg.stands.y > cfg.stands.x:
		var side := _stands_side()
		var d := side * (_stands_front() + _stands_depth() + 3.6)
		var count := maxi(2, ceili((cfg.stands.y - cfg.stands.x) / 90.0))
		for k in count + 1:
			var s := track.wrap_s(cfg.stands.x + (cfg.stands.y - cfg.stands.x) * k / count)
			var c := track.pos(s, d)
			if not _clear_of_track(lookup, c[0], c[1], edge + 6.0):
				continue
			if cfg.sea and _sample_dem(track.grid, c[0], c[1]) < 1.0:
				continue
			var mid := track.pos(s, 0.0)
			_lamp_post(fx, Vector2(c[0], c[1]), _ground_y(c[0], c[1], s, absf(d)), Vector2(mid[0], mid[1]), true)

	# the pit building: a post between the lane and the doors every 30 m, and a light strip under the ledge
	var garages := _garage_span()
	if garages != Vector2.ZERO:
		var sg := pit_side
		var s := garages.x + 8.0
		while s < garages.y - 4.0:
			var c := track.pos(s, cfg.pit_offset + sg * 4.6)
			var lane := track.pos(s, cfg.pit_offset)
			_lamp_post(fx, Vector2(c[0], c[1]), _road_y(s) - 0.09, Vector2(lane[0], lane[1]), false)
			s += 30.0
		var strip := SurfaceTool.new()
		strip.begin(Mesh.PRIMITIVE_TRIANGLES)
		var steps := maxi(2, ceili((garages.y - garages.x) / 6.0))
		var prev: Array = []
		for k in steps + 1:
			var sk := garages.x + (garages.y - garages.x) * k / steps
			var cur := [_pit_point(sk, cfg.pit_offset + sg * 5.5, 6.42), _pit_point(sk, cfg.pit_offset + sg * 6.5, 6.42)]
			if k > 0:
				_quad(strip, prev[0], prev[1], cur[1], cur[0])
			prev = cur
		strip.generate_normals()
		var strip_inst := MeshInstance3D.new()
		strip_inst.name = "PitLightStrip"
		strip_inst.mesh = strip.commit()
		strip_inst.material_override = _lamp_material
		strip_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		track_root.add_child(strip_inst)

	# lamps in the tunnel: the fittings are in _build_tunnels, these are the lights they give
	for t in tunnels:
		var s := t.x + 8.0
		while s < t.y - 8.0:
			_register_lamp(_tunnel_point(s, Vector2(0.0, 5.6)), Color("#ffd28a"), 3.5, 16.0, true)
			s += 16.0

	var root := Node3D.new()
	root.name = "Lighting"
	track_root.add_child(root)
	var unit := BoxMesh.new()
	var steel := _material(Color("#585d62"), 0.6)
	steel.metallic = 0.4
	_add_multimesh(root, "LampPoles", _multimesh(unit, poles, []), steel)
	_add_multimesh(root, "LampArms", _multimesh(unit, arms, []), steel)
	_add_multimesh(root, "LampHeads", _multimesh(unit, heads, []), _lamp_material)
	for inst in root.get_children():
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in LAMP_POOL.max():
		var light := OmniLight3D.new()
		light.name = "LampLight%d" % i
		light.shadow_enabled = false
		light.light_specular = 0.6
		light.visible = false
		root.add_child(light)
		_lamp_pool.append(light)
	_lamp_pick.resize(LAMP_POOL.max() + 1)
	_lamp_pick_d2.resize(LAMP_POOL.max() + 1)

## One lamp post with its foot at track point p (ground height in world units), turned towards track point
## look. A street post is a pole with a short arm and a lantern; a mast is a tall pole carrying a bank of
## floodlights tilted down at the circuit. fx is [poles, arms, heads].
func _lamp_post(fx: Array, p: Vector2, ground: float, look: Vector2, mast: bool) -> void:
	var foot := Vector3(p.x - world_center.x, ground - 0.8, p.y - world_center.y)
	var to := Vector3(look.x - p.x, 0.0, look.y - p.y).normalized()
	var h := 27.0 if mast else 7.6
	var w := 0.7 if mast else 0.2
	var top := foot + Vector3.UP * (h + 0.8)
	fx[0].append(Transform3D(Basis.from_scale(Vector3(w, h + 0.8, w)), top - Vector3.UP * (h + 0.8) * 0.5))
	if mast:
		var dir := (to * cos(0.45) - Vector3.UP * sin(0.45)).normalized()
		var basis := Basis.looking_at(dir)
		var at := top + to * 0.9 + Vector3.UP * 0.2
		fx[1].append(Transform3D(basis.scaled_local(Vector3(5.7, 2.7, 0.3)), at - dir * 0.22))
		fx[2].append(Transform3D(basis.scaled_local(Vector3(5.2, 2.2, 0.25)), at))
		_register_lamp(at + dir * 2.0, Color("#eaf1ff"), 120.0, 110.0, false)
	else:
		var arm := 1.7
		var basis := Basis.looking_at(to)
		fx[1].append(Transform3D(basis.scaled_local(Vector3(0.11, 0.11, arm)), top + to * arm * 0.5))
		var at := top + to * (arm - 0.1) - Vector3.UP * 0.12
		fx[2].append(Transform3D(basis.scaled_local(Vector3(0.42, 0.1, 0.95)), at))
		_register_lamp(at - Vector3.UP * 0.5, Color("#ffd08a"), 10.0, 30.0, false)

func _register_lamp(at: Vector3, color: Color, energy: float, reach: float, always: bool) -> void:
	_lamp_pos.append(at)
	_lamp_color.append(color)
	_lamp_energy.append(energy)
	_lamp_range.append(reach)
	_lamp_always.append(1 if always else 0)

func _hide_lamp_lights() -> void:
	for light in _lamp_pool:
		light.visible = false

## Hands the pooled lights to the lamps nearest the camera. A lamp's light fades out as it becomes the
## farthest of the pool, so a nearer lamp taking its place is not a pop.
func _update_lamp_lights() -> void:
	if _lamp_pool.is_empty() or not camera:
		return
	var count := mini(LAMP_POOL[quality], _lamp_pool.size())
	var cam := camera.global_position
	var reach2 := LAMP_REACH * LAMP_REACH
	var picked := 0
	for i in _lamp_pos.size():
		if _lamp_on < 0.01 and _lamp_always[i] == 0:
			continue
		var d2 := cam.distance_squared_to(_lamp_pos[i])
		if d2 > reach2 or (picked > count and d2 >= _lamp_pick_d2[count]):
			continue
		var j := picked if picked <= count else count
		if picked <= count:
			picked += 1
		while j > 0 and _lamp_pick_d2[j - 1] > d2:
			_lamp_pick[j] = _lamp_pick[j - 1]
			_lamp_pick_d2[j] = _lamp_pick_d2[j - 1]
			j -= 1
		_lamp_pick[j] = i
		_lamp_pick_d2[j] = d2
	var ref := sqrt(_lamp_pick_d2[count]) if picked > count else LAMP_REACH
	for k in _lamp_pool.size():
		var light := _lamp_pool[k]
		if k >= count or k >= picked:
			light.visible = false
			continue
		var i := _lamp_pick[k]
		var d := sqrt(_lamp_pick_d2[k])
		var fade := clampf((ref - d) / (ref * 0.3), 0.0, 1.0) * (1.0 - smoothstep(LAMP_REACH * 0.7, LAMP_REACH, d))
		light.light_energy = _lamp_energy[i] * (1.0 if _lamp_always[i] == 1 else _lamp_on) * fade
		light.visible = light.light_energy > 0.02
		light.position = _lamp_pos[i]
		light.light_color = _lamp_color[i]
		light.omni_range = _lamp_range[i]

## Covered grandstands built from the Blender pieces: 10 m bays of concrete tiers with plastic seats and a
## seated crowd, a cantilever roof with sponsor boards on its fascia and the front wall, closed at each
## end by a side wall and stair. The run is split into straight stands that follow the road round bends.
func _build_grandstands() -> void:
	if not track.cfg.grandstands:
		return
	var start_s: float = track.cfg.stands.x
	var end_s: float = track.cfg.stands.y
	if end_s <= start_s:
		return
	var tiers := _stand_tiers()
	if not trackside_meshes().has("StandFrame_T%02d" % tiers):
		return
	var span: float = end_s - start_s
	var pieces: int = maxi(1, ceili(span / 70.0))
	var side := _stands_side()
	var front := _stands_front()
	var depth := _stands_depth()
	var lookup := _track_lookup(24.0)
	for piece in pieces:
		var s := start_s + (float(piece) + 0.5) * span / float(pieces)
		var center := track.pos(s, side * front)
		var y := (track.sample(track.H, s) - elevation_base) * ALTITUDE_SCALE
		# local x runs along the road and the tiers climb away from it (-z)
		var rot := -track.heading(s) + (PI if side > 0.0 else 0.0)
		# on a bend the ends of a straight stand swing towards the road, and behind it may be another part
		# of the circuit: drop bays until it is clear, or leave it out
		var bays := floori((span / float(pieces) - 6.0) / STAND_BAY)
		while bays >= 2 and not _footprint_clear(lookup, center, rot, Rect2(-bays * STAND_BAY * 0.5 - 2.0, -depth, bays * STAND_BAY + 4.0, depth + 2.0), track.half + track.cfg.runoff + 1.5):
			bays -= 1
		if bays < 2:
			continue
		var xf := Transform3D(Basis(Vector3.UP, rot), Vector3(center[0] - world_center.x, y, center[1] - world_center.y))
		add_stand(track_root, "Grandstand_%02d" % piece, xf, bays, tiers, piece)

## One covered grandstand from the Blender pieces: bays of STAND_BAY metres (stretched along by width_scale)
## and tiers rows, its origin at the front of the first tier in the middle, local -z up the tiers. With a
## crowd_range the spectators are only drawn that close.
func add_stand(parent: Node3D, label: String, xf: Transform3D, bays: int, tiers: int, piece: int, width_scale := 1.0, crowd_range := 0.0) -> Node3D:
	var parts := trackside_meshes()
	var frame_name := "StandFrame_T%02d" % tiers
	if not parts.has(frame_name):
		return null
	var z_top := STAND_FIRST_Z + (tiers - 1) * STAND_RISE
	var fascia := Vector3(0.0, z_top + STAND_ROOF_FRONT - 0.95, STAND_ROOF_OVERHANG + 0.14)
	var parapet := Vector3(0.0, 0.55, 0.33) # its top just under the front wall's
	var root := Node3D.new()
	root.name = label
	root.transform = xf * Transform3D(Basis.from_scale(Vector3(width_scale, 1.0, 1.0)), Vector3.ZERO)
	parent.add_child(root)
	var xfs := {}
	for b in bays:
		var at := Vector3((b - (bays - 1) * 0.5) * STAND_BAY, 0.0, 0.0)
		_append_xf(xfs, frame_name, Transform3D(Basis.IDENTITY, at))
		_append_xf(xfs, "StandBoard_%d" % ((piece * 3 + b * 5) % STAND_BOARDS), Transform3D(Basis.IDENTITY, at + parapet))
		_append_xf(xfs, "StandBoard_%d" % (0 if b % 3 == 1 else (piece + b * 3 + 1) % STAND_BOARDS), Transform3D(Basis.IDENTITY, at + fascia))
		for k in tiers:
			var row := Transform3D(Basis.IDENTITY, at + Vector3(0.0, STAND_FIRST_Z + k * STAND_RISE, -k * STAND_TREAD))
			_append_xf(xfs, "StandRow", row)
			_append_xf(xfs, "StandCrowd", row)
	var half := (bays - 1) * 0.5 * STAND_BAY
	_append_xf(xfs, "StandEndL_T%02d" % tiers, Transform3D(Basis.IDENTITY, Vector3(-half, 0, 0)))
	_append_xf(xfs, "StandEndR_T%02d" % tiers, Transform3D(Basis.IDENTITY, Vector3(half, 0, 0)))
	var crowd := _stand_crowd_material()
	for part in xfs:
		if not parts.has(part):
			continue
		var list: Array[Transform3D] = []
		list.assign(xfs[part])
		var inst := MultiMeshInstance3D.new()
		inst.name = part
		inst.multimesh = _multimesh(parts[part], list, [])
		if part == "StandCrowd":
			inst.material_override = crowd
			if crowd_range > 0.0:
				inst.visibility_range_end = crowd_range
				inst.visibility_range_end_margin = 60.0
				inst.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		if part == "StandCrowd" or part == "StandRow" or part.begins_with("StandBoard"):
			inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(inst)
	return root

## The crowd material shared by every grandstand, and the seats painted in one of the circuit's colours.
func _stand_crowd_material() -> ShaderMaterial:
	if _crowd_material and _crowd_material_track == track:
		return _crowd_material
	var seat_colors: Array[Color] = [Color("#1f4fa0"), Color("#c0262d"), Color("#1d7a47"), Color("#e0a91c"), Color("#5f6a75")]
	var seat_color := seat_colors[absi(hash(track.cfg.resource_path)) % seat_colors.size()]
	var row_mesh: Mesh = trackside_meshes().StandRow
	for i in row_mesh.get_surface_count():
		var m := row_mesh.surface_get_material(i) as StandardMaterial3D
		if m and m.resource_name == "Seat":
			m.albedo_color = seat_color
	_crowd_material = ShaderMaterial.new()
	_crowd_material.shader = CROWD_SHADER
	_crowd_material_track = track
	return _crowd_material

func _append_xf(xfs: Dictionary, part: String, xf: Transform3D) -> void:
	if not xfs.has(part):
		xfs[part] = []
	xfs[part].append(xf)

## Monaco: blocks of flats and hotels behind the barriers, up to four rows deep and stepping up the
## hillside, as in the JS version. Windows, shutters and floor bands come from the facade shader, so every
## block is one instance of a unit box; cornices, terracotta roofs and rooftop plant rooms are three more
## MultiMeshes.
func _build_city_blocks() -> void:
	var walls: Array[Color] = [Color("#efe3cc"), Color("#e9d3b0"), Color("#dcbfa0"), Color("#f3efe6"), Color("#e6c2a4"),
		Color("#d9a98d"), Color("#cdbb98"), Color("#f1dcc4"), Color("#e8cf8f"), Color("#e3b2a0"), Color("#c9c2b4")]
	var facade := ShaderMaterial.new()
	facade.shader = FACADE_SHADER
	facade.set_shader_parameter("grain", noise_texture("grain"))
	facade.set_shader_parameter("instanced", true)
	_wet_materials.append(facade)
	_night_materials.append(facade)
	var rng := SimUtil.Rng.new(99 + track.n)
	var lookup := _track_lookup(24.0)
	var cfg := track.cfg
	var pit_side := signf(cfg.pit_offset)
	var stands_back := _stands_front() + _stands_depth() + 3.0
	var tunnels := _tunnel_spans()
	var tunnel_back := track.half + cfg.runoff + 0.6 + 3.0 + 1.5
	var casino := _casino_spot()
	var clear := track.half + cfg.runoff + 2.0
	var blocks: Array[Transform3D] = []
	var block_data: Array[Color] = []
	var block_custom: Array[Color] = []
	var cornices: Array[Transform3D] = []
	var cornice_colors: Array[Color] = []
	var roofs: Array[Transform3D] = []
	var roof_colors: Array[Color] = []
	var plant: Array[Transform3D] = []
	var i := 0
	while i < track.n:
		var s := i * track.step
		var rel_s := track.rel(s)
		for side in [-1.0, 1.0]:
			for row in 4:
				var skip := rng.next() < 0.3
				var w := 10.0 + rng.next() * 16.0
				var dp := 9.0 + rng.next() * 14.0
				var back := rng.next() * 6.0
				var jx := (rng.next() - 0.5) * 4.0
				var jz := (rng.next() - 0.5) * 4.0
				var tall := pow(rng.next(), 1.7)
				var look := rng.next()
				if skip:
					continue
				# the front row a few metres behind the barrier, or behind the garages, stands and tunnel
				var inner := track.half + cfg.runoff + 2.5
				if side == pit_side and rel_s > cfg.pit_entry - 25.0 and rel_s < cfg.pit_exit + 25.0:
					inner = maxf(inner, absf(cfg.pit_offset) + 24.0)
				if cfg.grandstands and side == _stands_side() and rel_s > cfg.stands.x - 25.0 and rel_s < cfg.stands.y + 25.0:
					inner = maxf(inner, stands_back)
				if tunnels.any(func(t: Vector2) -> bool: return _in_span(s, t, 10.0)):
					inner = maxf(inner, tunnel_back)
				var r := inner + dp * 0.5 + 1.5 + row * 24.0 + back
				var c := track.pos(s, side * r)
				var p := PackedFloat64Array([c[0] + jx, c[1] + jz])
				if cfg.sea and _sample_dem(track.grid, p[0], p[1]) < 1.5:
					continue # harbour
				if not casino.is_empty() and Vector2(p[0], p[1]).distance_to(casino.p) < 30.0 + maxf(w, dp) * 0.5:
					continue
				var rot := -track.heading(s)
				if not _footprint_clear(lookup, p, rot, Rect2(-w * 0.5 - 0.4, -dp * 0.5 - 0.4, w + 0.8, dp + 0.8), clear):
					continue
				var h := 10.0 + tall * 40.0
				var sink := 3.0 # below the ground, for blocks on a slope
				var ground := _terrain_y(lookup, p[0], p[1])
				var basis := Basis(Vector3.UP, rot)
				var at := Vector3(p[0] - world_center.x, ground, p[1] - world_center.y)
				blocks.append(Transform3D(basis.scaled(Vector3(w, h + sink, dp)), at + Vector3.UP * (h - sink) * 0.5))
				var wall := walls[int(look * 97.0) % walls.size()]
				block_data.append(Color(wall.r, wall.g, wall.b, float(int(look * 13.0) % 4) / 4.0))
				block_custom.append(Color(w, h + sink, dp, float(blocks.size())))
				if h < 24.0 and look < 0.35:
					# low villas and older blocks: a terracotta hipped roof
					roofs.append(Transform3D(basis.scaled(Vector3(w + 0.8, 2.2 + w * 0.08, dp + 0.8)), at + Vector3.UP * (h + 1.1 + w * 0.04)))
					roof_colors.append(Color("#b5613f").lerp(Color("#9c4f35"), look * 2.5))
				else:
					cornices.append(Transform3D(basis.scaled(Vector3(w + 0.7, 0.45, dp + 0.7)), at + Vector3.UP * (h + 0.1)))
					cornice_colors.append(wall.lightened(0.12))
					if look > 0.45:
						# a lift and stair housing on the flat roof
						var hx := (look - 0.7) * w * 0.8
						plant.append(Transform3D(basis.scaled(Vector3(3.0 + look * 3.0, 3.0, 2.5 + look * 2.0)), at + basis * Vector3(hx, h + 1.5, 0.0)))
		i += 8
	var root := Node3D.new()
	root.name = "City"
	track_root.add_child(root)
	var unit := BoxMesh.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = unit
	mm.instance_count = blocks.size()
	for k in blocks.size():
		mm.set_instance_transform(k, blocks[k])
		mm.set_instance_color(k, block_data[k])
		mm.set_instance_custom_data(k, block_custom[k])
	_add_multimesh(root, "CityBlocks", mm, facade)
	var painted := _material(Color.WHITE, 0.85)
	painted.vertex_color_use_as_albedo = true
	_add_multimesh(root, "Cornices", _multimesh(unit, cornices, cornice_colors), painted)
	var prism := PrismMesh.new()
	var tiles := _material(Color.WHITE, 0.8)
	tiles.vertex_color_use_as_albedo = true
	_add_multimesh(root, "Roofs", _multimesh(prism, roofs, roof_colors), tiles)
	_add_multimesh(root, "RoofPlant", _multimesh(unit, plant, []), _material(Color("#a8a39a"), 0.9))

func _multimesh(mesh: Mesh, xfs: Array[Transform3D], colors: Array[Color]) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for k in xfs.size():
		mm.set_instance_transform(k, xfs[k])
		if mm.use_colors:
			mm.set_instance_color(k, colors[k])
	return mm

func _add_multimesh(parent: Node3D, label: String, mm: MultiMesh, material: Material) -> void:
	if mm.instance_count == 0:
		return
	var inst := MultiMeshInstance3D.new()
	inst.name = label
	inst.multimesh = mm
	inst.material_override = material
	parent.add_child(inst)

## Terrain height (world units) at track point (x, z), shaped by the nearest part of the circuit.
func _terrain_y(lookup: Dictionary, x: float, z: float) -> float:
	if typeof(track.grid) != TYPE_DICTIONARY or int(track.grid.get("nx", 0)) < 2:
		return 0.0
	var near := _nearest_sample(lookup, x, z, 180.0)
	return _terrain_height(x, z, int(near.x), near.y, INF, track.grid) * ALTITUDE_SCALE

## The covered sections as spans of distance from the start line: Vector2(s0, s1), s1 > s0.
func _tunnel_spans() -> Array[Vector2]:
	var spans: Array[Vector2] = []
	var off := SimUtil.js_round(track.cfg.start_offset / track.step)
	for range_ab in track.tunnels:
		var s0: float = (float(range_ab[0]) - off) * track.step - 2.0
		var s1: float = (float(range_ab[1]) - off) * track.step + 2.0
		if s1 < s0:
			s1 += track.L
		if s1 - s0 >= 30.0: # short underpasses: nothing to draw
			spans.append(Vector2(s0, s1))
	return spans

func _in_span(s: float, span: Vector2, margin: float) -> bool:
	var u := track.wrap_s(s - span.x + margin)
	return u < span.y - span.x + margin * 2.0

## Where the Casino stands (Monaco's Casino Square): {s, side, p (track coordinates)}, or {} elsewhere.
func _casino_spot() -> Dictionary:
	if track.cfg.theme != "city" or not track.cfg.sea:
		return {}
	var s := 860.0
	var side := -1.0 if track.curvature(s) > 0.0 else 1.0
	var p := track.pos(s, side * (track.half + track.cfg.runoff + 12.0))
	return {"s": s, "side": side, "p": Vector2(p[0], p[1])}

func _build_casino_landmark() -> void:
	# Place the landmark beside the real Casino corner rather than scattering generic blocks there.
	var spot := _casino_spot()
	var s: float = spot.s
	var side: float = spot.side
	# its 28 m front (-z, with the windows and the sign) along the road and facing it
	var p := track.pos(s, side * (track.half + track.cfg.runoff + 12.0))
	var y := (track.sample(track.H, s) - elevation_base) * ALTITUDE_SCALE
	var root := Node3D.new()
	root.name = "MonteCarloCasino"
	root.position = Vector3(p[0] - world_center.x, y, p[1] - world_center.y)
	root.rotation.y = -track.heading(s) + (PI if side < 0.0 else 0.0)
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

func _build_monaco_harbor(_extent: float) -> void:
	# The sea is wherever the elevation grid is at sea level (Port Hercule and the open water past the
	# tunnel): one water plane at sea level over all of it, showing where the terrain drops below.
	if typeof(track.grid) != TYPE_DICTIONARY or int(track.grid.get("nx", 0)) < 2:
		return
	var grid: Dictionary = track.grid
	var heights: Array = grid["h"]
	var gx := int(grid["nx"])
	var gstep := float(grid["step"])
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for k in heights.size():
		if float(heights[k]) < 1.0:
			var q := Vector2(float(grid["x0"]) + (k % gx) * gstep, float(grid["y0"]) + (k / gx) * gstep)
			lo = lo.min(q)
			hi = hi.max(q)
	if lo.x > hi.x:
		return
	# a little above the terrain's sea-level cells (which sit at 0 m near the circuit and 1 m lower beyond)
	var sea_y := (0.3 - elevation_base) * ALTITUDE_SCALE
	var water := MeshInstance3D.new()
	water.name = "Sea"
	var water_mesh := PlaneMesh.new()
	water_mesh.size = hi - lo + Vector2(gstep, gstep)
	water.mesh = water_mesh
	water.position = Vector3((lo.x + hi.x) * 0.5 - world_center.x, sea_y, (lo.y + hi.y) * 0.5 - world_center.y)
	var water_mat := ShaderMaterial.new()
	water_mat.shader = WATER_SHADER
	water_mat.set_shader_parameter("ripples", noise_texture("ripples"))
	water.material_override = water_mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	track_root.add_child(water)
	# White motor yachts moored along the harbour side of the circuit, only on open water and clear of the road.
	var hull_mat := _material(Color("#f4f0e5"), 0.34)
	var deck_mat := _material(Color("#d5c6a8"), 0.55)
	var lookup := _track_lookup(24.0)
	var moored: Array[Vector2] = []
	var s := 0.0
	while s < track.L and moored.size() < 14:
		s += 9.0
		var i := moored.size()
		var length := 18.0 if i % 3 == 0 else 11.0
		for side in [-1.0, 1.0]:
			for dist in [45.0, 60.0, 80.0, 100.0]:
				var p := track.pos(s, side * dist)
				var at := Vector2(p[0], p[1])
				if moored.any(func(m: Vector2) -> bool: return m.distance_to(at) < 24.0):
					continue
				if _sample_dem(grid, at.x, at.y) > 0.5:
					continue
				# the terrain rises to whichever part of the circuit is nearest, which need not be the one at s
				var near := _nearest_sample(lookup, at.x, at.y, 180.0)
				if _terrain_height(at.x, at.y, int(near.x), near.y, INF, grid) * ALTITUDE_SCALE > sea_y - 0.05:
					continue
				var rot := -track.heading(s) + (0.15 if i % 2 == 0 else -0.1)
				if not _footprint_clear(lookup, p, rot, Rect2(-length * 0.5 - 4.0, -6.0, length + 8.0, 12.0), 30.0):
					continue
				moored.append(at)
				_add_yacht(i, Vector3(at.x - world_center.x, sea_y + 0.35, at.y - world_center.y), rot, length, hull_mat, deck_mat)
				break
			if moored.size() > i:
				break

func _add_yacht(i: int, at: Vector3, rot: float, length: float, hull_mat: Material, deck_mat: Material) -> void:
	var boat_root := Node3D.new()
	boat_root.name = "HarborYacht_%02d" % i
	boat_root.position = at
	boat_root.rotation.y = rot
	track_root.add_child(boat_root)
	var hull := MeshInstance3D.new()
	var hull_mesh := BoxMesh.new()
	hull_mesh.size = Vector3(length, 1.2, 3.5 if length > 12.0 else 2.5)
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
	tv_camera_kind.clear()
	# a camera every ~110 m: a tower, a ground camera, a telephoto, a ground camera, and so on
	var num_cams := maxi(6, int(track.L / 110.0))
	for i in num_cams:
		var s := float(i) * (track.L / float(num_cams))
		var k := track.sample(track.KC, s)
		# on the outside of the bend, alternating sides on the straights
		var side := -signf(k) if absf(k) > 1.0 / 300.0 else (1.0 if i % 2 == 0 else -1.0)
		var kind := TvKind.TOWER if i % 4 == 0 else (TvKind.LONG if i % 4 == 2 else TvKind.GROUND)
		# low cameras stand behind the barrier, except where it carries a catch fence, which would fill the
		# shot at close range: there they stand on the road side of it
		var edge := track.half + track.cfg.runoff
		if kind == TvKind.TOWER:
			edge += 16.0
		elif track.cfg.barrier in ["safer", "armco+fence"]:
			edge -= minf(1.0, track.cfg.runoff - 0.3)
		else:
			edge += 2.5
		var lateral := side * edge
		var p := track.pos(s, lateral)
		var y := _road_y(s) + track.bank_rise(s, lateral)
		if kind == TvKind.TOWER:
			y += 6.4
		else:
			y = maxf(_ground_y(p[0], p[1], s, absf(lateral)) + 1.5, y + 1.8)
		tv_cameras.append(Vector3(p[0] - world_center.x, y, p[1] - world_center.y))
		tv_camera_s.append(s)
		tv_camera_kind.append(kind)

## A scaffold tower under each trackside TV camera, its camera turned towards the road.
func _build_tv_towers() -> void:
	var parts := trackside_meshes()
	if not parts.has("TvTower"):
		return
	var xfs: Array[Transform3D] = []
	for i in tv_cameras.size():
		if tv_camera_kind[i] != TvKind.TOWER:
			continue
		var eye := tv_cameras[i]
		var p := track.pos(tv_camera_s[i], 0.0)
		var to_road := Vector3(p[0] - world_center.x, 0.0, p[1] - world_center.y) - Vector3(eye.x, 0.0, eye.z)
		var basis := Basis(Vector3.UP, atan2(-to_road.z, to_road.x))
		xfs.append(Transform3D(basis, eye - Vector3(0, 1.6, 0) - basis.x * 0.7))
	var root := Node3D.new()
	root.name = "TvTowers"
	track_root.add_child(root)
	_add_multimesh(root, "Towers", _multimesh(parts.TvTower, xfs, []), null)

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
		if set.normal:
			m.set_shader_parameter("normal_tex", set.normal)
		if set.roughness:
			m.set_shader_parameter("rough_tex", set.roughness)
			m.set_shader_parameter("has_rough_tex", true)
	if weather:
		_wet_materials.append(m)
	return m
