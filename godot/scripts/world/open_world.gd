## The campaign's open world: the whole town of Brzeszcze (Małopolska) rebuilt from OpenStreetMap, to drive
## freely in the Seicento between the campaign's events, Forza Horizon style. Each campaign stage is a beacon
## where it really starts (the Bór stage on ul. Bór, the industrial sprint by Szyb Andrzej on Dworcowa) or on
## the road out of town towards its venue (Pszczyna west on the DW933, Oświęcim east, Bielsko-Biała south,
## Wilamowice down the S1, Tychy's Fiat test track up it, Kraków by train from the station, Tokyo from the
## festival). Pull into a beacon and press Enter to race the stage; the results bring you back to the same spot.
## Between events: traffic, speed traps, landmarks to discover, every road to drive, a skill chain (drifts,
## jumps off the embankments, near misses, speed) that earns fans, and a day that turns to night.
class_name OpenWorld
extends Control

signal stage_requested(index: int)
signal leave_requested(to: String) ## "menu" or "stages"

const MAP_KEY := "brzeszcze"
const TICK := 1.0 / 120.0
const SKY_SHADER := preload("res://shaders/sky.gdshader")
const CAR_SCENE := preload("res://scripts/ui/race_car_visual.tscn")
const CAR_VISUAL := preload("res://scripts/ui/race_car_visual.gd")
const WORLD := preload("res://scripts/ui/race_world.gd")
## Campaign track -> the map spot its beacon stands at (tools/build_open_world.py names the spots)
const STAGE_SPOTS := {"wilamowice": "exit_wilamowice", "brzeszcze": "industrial_sprint", "bor": "bor_stage",
	"pszczyna": "exit_pszczyna", "bielsko": "exit_bielsko", "oswiecim": "exit_oswiecim", "krakow": "station",
	"fiat": "exit_tychy", "tokyo": "festival", "goliath": "festival"}
const SPOT_NOTE := {"exit_wilamowice": "South on the S1 towards Wilamowice", "industrial_sprint": "ul. Dworcowa by KWK Brzeszcze",
	"bor_stage": "ul. Bór, Brzeszcze-Bór", "exit_pszczyna": "West on the DW933 to Pszczyna",
	"exit_bielsko": "South on ul. Bielska to Bielsko-Biała", "exit_oswiecim": "East on the DW933 to Oświęcim",
	"station": "Brzeszcze Jawiszowice station: the train to Kraków", "exit_tychy": "North on the S1 to Tychy",
	"festival": "Seicento Fest at the KS Górnik stadium: the flight to Tokyo"}
const DISCOVER_KINDS := ["mineshaft", "church", "stadium", "station", "museum", "cinema", "monument", "water_tower", "chimney"]
const AREA_KINDS := ["place_town", "place_village", "place_neighbourhood", "place_hamlet", "place_suburb"]
const DAY_RATE := 1.0 / 80.0 ## game hours per real second: a day in 32 minutes
const BEACON_RADIUS := 9.0
const HEADLIGHT_ENERGY := 26.0 ## each dipped beam at full night (see _build_headlights)
const SPAWN_ROLL := 14.0 ## m a car put back at a stage beacon stands on along its road, clear of the beacon
const CHAIN_IDLE := 2.6 ## s without a skill before the chain is banked
const LAMP_LIGHTS := 14
const NOON_CAP := deg_to_rad(40.0) ## soft cap on the sun's elevation (see _apply_time)
const TOWN_ROAD_SHADER := preload("res://shaders/town_road.gdshader")
const PAVEMENT_SHADER := preload("res://shaders/pavement.gdshader")

var map: TownMap
var builder: TownBuilder
var traffic: Traffic
var train: Train
var progress: WorldProgress
var drive: FreeCar
var audio = null ## the game's RaceAudio
## The game's Options → Resolution rule for a 3D view (game.gd _render_resolution: Auto's pixel cap, or the
## fullscreen render resolution), screen pixels in, render target out; unset: the view's own pixels
var render_size := Callable()
var gearbox := "auto"
var assists := "abs"
var paint := Color("#c62828")
var car_number := 9

var viewport: SubViewport
var view: TextureRect
var world: Node3D
var camera: Camera3D
var sun: DirectionalLight3D
var quality := 2 ## graphics preset level (GraphicsPresets): 0 Low .. 3 Ultra
var env: Environment
var sky_mat: ShaderMaterial
var car_visual: Node3D
var surface_fx: SurfaceFeedback ## dust, kick-up, tyre smoke and the gravel/grass/wind loops
var golden := 0.0 ## 0..1, how deep in the golden hour the sun is (low, warm, long shadows, sunlit haze)
var _volumetric := false ## the preset affords volumetric fog: sun shafts in the golden hour (Ultra)
var headlights: Array[SpotLight3D] = []
var reflections: CarReflections ## the street mirrored in the car's paint (presets with car_reflections)
var lamp_lights: Array[OmniLight3D] = []
var _lamp_reach := 200.0 ## m: the pooled lamp lights have faded out by here (_place_lamp_lights)
var route_mesh: MeshInstance3D
var route_mat: StandardMaterial3D
var hud: OpenWorldHud

var built := false
var building := false
var active := false
var paused := false
var accumulator := 0.0
var throttle := 0.0
var brake := 0.0
var handbrake := 0.0 ## Space or the pad's A button
var steer := 0.0
var shift_up := false
var shift_down := false
var gamepad_device := -1
var cam_mode := 0
var cam_pos := Vector3.ZERO
var cam_vel_dir := Vector2.RIGHT
## Free look (right stick, B / R3 to look back, right-mouse drag); the chase cameras orbit the car with it
var look := CameraLook.new()
var _chase_cam: ChaseCam
var hour := 18.5
var night := 0.0
## 0..1 how wet the streets are (town_road.gdshader puddles, sheen, rain rings). Nothing rains in the open world yet:
## set it from a weather system; after dark the streets get a little dew of their own (NIGHT_DAMP)
var wet := 0.0
const NIGHT_DAMP := 0.3
const LAMP_POOL_GLOW := 0.7 ## emission at the middle of a lamp's pool on the ground (reads on the dark tarmac)

var events: Array = [] ## [{stage, spot, pos: Vector2, heading, title, ...}]; a live event has "live": its id
var live: LiveEvents ## the generated events round the car (scripts/world/live_events.gd)
var _crashed_frame := false
var _rival_nodes: Array[Node3D] = [] ## the field of a mission raced on the map (StreetRivals), drawn
const RIVAL_PAINTS := ["#1565c0", "#f9a825", "#2e7d32", "#6a1b9a", "#ef6c00", "#00838f", "#ad1457", "#4e342e", "#eceff1"]
const RIVAL_MASS := 900.0 ## the car hit something hard this frame (a live drift zone loses its combo)
var active_event := -1
var gps_target := -1
var gps_waypoint := false ## the route runs to the player's own waypoint instead of a stage
var wp_pos := Vector2.ZERO
var wp_on := false
const WAYPOINT_REACH := 18.0 ## m from the waypoint that counts as having arrived
var _reset_armed := false ## RESET CAMPAIGN was pressed once and waits for its confirmation
var route := PackedVector2Array()
var _route_t := 0.0
var traps: Array = [] ## [{id, pos, dir, name}]
var pois: Array[Poi] = [] ## the speed traps and landmarks the map and the satnav show (scripts/world/poi.gd)
var wp_poi := "" ## the Poi id the waypoint route runs to ("" for the player's own waypoint)
var _trap_near := {}
var chain_points := 0.0
var chain_mult := 1.0
var chain_idle := 0.0
var chain_label := ""
var _chain_events := 0
var area_name := ""
var _area_t := 0.0
var _disc_t := 0.0
var _lamp_t := 0.0
var _save_t := 0.0
var _prev_pos := Vector3.ZERO
var _prev_heading := 0.0

# ================================================================================================ lifecycle

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	viewport = SubViewport.new()
	viewport.size = Vector2i(1600, 900)
	# its own 3D world: sharing the game's would let the race scene's sky, sun and environment take over
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	viewport.positional_shadow_atlas_size = 2048
	add_child(viewport)
	view = TextureRect.new()
	view.texture = viewport.get_texture()
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_SCALE
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.resized.connect(_fit_view)
	add_child(view)
	hud = OpenWorldHud.new()
	add_child(hud)
	hud.pause_action.connect(_pause_action)
	hud.waypoint_picked.connect(_set_waypoint)
	hide()

static func available() -> bool:
	return FileAccess.file_exists("res://data/world/%s.json" % MAP_KEY)

## Shows the world, building it first if needed. spawn: a spot name, a stage index (int) to come back at that
## stage's beacon, or "" for where the car was left.
func open(spawn = "", opts := {}) -> void:
	gearbox = opts.get("gearbox", gearbox)
	assists = opts.get("assists", assists)
	paint = opts.get("paint", paint)
	car_number = int(opts.get("number", car_number))
	if opts.has("retro_material") and opts.retro_material:
		view.material = opts.retro_material
	if opts.has("source_viewport") and opts.source_viewport:
		var src: SubViewport = opts.source_viewport
		viewport.msaa_3d = src.msaa_3d
		viewport.screen_space_aa = src.screen_space_aa
		viewport.use_taa = src.use_taa
		viewport.scaling_3d_mode = src.scaling_3d_mode
		viewport.scaling_3d_scale = src.scaling_3d_scale
	audio = opts.get("audio", audio)
	render_size = opts.get("render_size", render_size)
	show()
	active = true
	paused = false
	hud.show_pause(false)
	_fit_view()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if not built:
		await _build_world()
	apply_graphics(int(opts.get("quality", quality)), bool(opts.get("ssao", true)), int(opts.get("reflections", -1)))
	if drive:
		drive.gearbox = gearbox
		drive.assists = assists
	if surface_fx:
		surface_fx.reset_car_bus()
	_refresh_events()
	_spawn(spawn)
	_live_open()
	if not CarCatalog.unlocked(CarCatalog.key_at(progress.car_class), progress.fans):
		progress.car_class = 0
	if _fitted_class != progress.car_class:
		_fit_car()
	else:
		_apply_look()
	accumulator = 0.0
	throttle = 0.0
	brake = 0.0
	steer = 0.0

## Hides the world and stops it (the race or the menu takes over). The scene stays built for the way back.
func suspend() -> void:
	if not active:
		return
	_save()
	active = false
	if live and live.is_running():
		live.abandon()
		_live_cp_beacon()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if audio:
		audio.update_car(null, false)
	if surface_fx:
		surface_fx.stop_all()
		surface_fx.silence(car_visual)
	if traffic:
		traffic.clear()
	hide()

func _fit_view() -> void:
	if not is_inside_tree():
		return
	var px := Vector2i((view.size * get_viewport().get_final_transform().get_scale()).round()).max(Vector2i(2, 2))
	if render_size.is_valid():
		px = render_size.call(px)
	if viewport.size != px:
		viewport.size = px

## Builds the town a step per frame behind the loading screen (in one go when headless: nothing is drawn there).
func _build_world() -> void:
	building = true
	var by_frame := DisplayServer.get_name() != "headless"
	progress = WorldProgress.load_progress()
	var ckey := CarCatalog.key_at(progress.car_class) if CarCatalog.unlocked(CarCatalog.key_at(progress.car_class), progress.fans) else "stock"
	hud.open_loading(CarCatalog.spec(ckey), CarCatalog.display_name(ckey) if ckey != "stock" else "Fiat Seicento")
	hud.show_loading("Reading the map of Brzeszcze", 0.02)
	hour = progress.hour
	world = Node3D.new()
	world.name = "Brzeszcze"
	var map_tex: Texture2D = null
	if by_frame:
		# twice: the frame that shows the cover must be drawn before the work starts
		await get_tree().process_frame
		await get_tree().process_frame
		# the map and the town build on a worker thread into a world that is not in the tree yet, so this thread
		# keeps drawing the cover (its spinner never stalls); the world joins the viewport when it is done
		_build_status = ["Reading the map of Brzeszcze", 0.02]
		var task := WorkerThreadPool.add_task(_build_town_threaded, true, "Open world build")
		var fps_was := Engine.max_fps
		Engine.max_fps = 30 # the cover needs few frames; leave the cores to the build
		while not WorkerThreadPool.is_task_completed(task):
			hud.show_loading(String(_build_status[0]), float(_build_status[1]))
			await get_tree().process_frame
		WorkerThreadPool.wait_for_task_completion(task)
		Engine.max_fps = fps_was
		map_tex = _build_map_tex
		_build_map_tex = null
	else:
		_build_town_threaded()
	if map == null:
		hud.show_loading("The open-world map is missing: run tools/build_open_world.py", 0.0)
		world.free()
		world = null
		building = false
		return
	# the rest runs here, a piece a frame so the cover keeps drawing between them
	hud.show_loading("Starting the engine", 0.95)
	var t := Time.get_ticks_msec()
	viewport.add_child(world)
	_t_log("add world", t)
	if by_frame:
		await get_tree().process_frame
	t = Time.get_ticks_msec()
	_build_environment()
	_apply_vegetation_quality()
	_t_log("environment", t)
	if by_frame:
		await get_tree().process_frame
	t = Time.get_ticks_msec()
	hud.setup(map, map_tex if map_tex else load("res://data/world/%s_map.png" % MAP_KEY) as Texture2D)
	_t_log("hud", t)
	if by_frame:
		await get_tree().process_frame
	t = Time.get_ticks_msec()
	drive = FreeCar.new(map)
	car_visual = CAR_SCENE.instantiate()
	if CarCatalog.unlocked(CarCatalog.key_at(progress.car_class), progress.fans):
		car_visual.car_key = CarCatalog.key_at(progress.car_class)
	world.add_child(car_visual)
	car_visual.is_player = true
	car_visual.fx_quality = quality
	surface_fx = SurfaceFeedback.new()
	surface_fx.name = "SurfaceFeedback"
	add_child(surface_fx)
	_build_headlights()
	_build_lamp_lights()
	reflections = CarReflections.new()
	world.add_child(reflections)
	reflections.follow(car_visual)
	_build_route_mesh()
	_t_log("car and lights", t)
	if by_frame:
		await get_tree().process_frame
	t = Time.get_ticks_msec()
	traffic = Traffic.new(map, world, builder)
	train = Train.new(map, world, builder)
	_build_traps()
	_t_log("traffic", t)
	built = true
	building = false
	hud.hide_loading()

## OW_BUILD_TIMES=1 prints how long each part of the build took.
func _t_log(what: String, since: int) -> void:
	if OS.get_environment("OW_BUILD_TIMES") != "":
		print("built %s in %d ms" % [what, Time.get_ticks_msec() - since])

var _build_status: Array = ["", 0.0] ## [what is building, fraction] the worker reports to the cover
var _build_map_tex: Texture2D

## Reads the map and runs every TownBuilder step into `world` (not yet in the tree, so this may run on a worker
## thread). Nothing here may touch the scene tree; the steps never hand frames back here (frame_budget_usec 0).
func _build_town_threaded() -> void:
	map = TownMap.load_map(MAP_KEY, TownBuilder.MESH_CACHE_DIR) # warm starts read a snapshot of the indexed map
	if map == null:
		return
	builder = TownBuilder.new(map, world)
	builder.mesh_cache_dir = TownBuilder.MESH_CACHE_DIR # warm starts load the slow steps' meshes from disk
	var steps: Array = builder.steps()
	for i in steps.size():
		_build_status = ["Building %s" % String(steps[i][0]).to_lower(), 0.05 + 0.85 * float(i) / steps.size()]
		var t0 := Time.get_ticks_msec()
		(steps[i][1] as Callable).call()
		if OS.get_environment("OW_BUILD_TIMES") != "":
			print("built %s in %d ms" % [steps[i][0], Time.get_ticks_msec() - t0])
	_build_status = ["Starting the engine", 0.95]
	_build_map_tex = load("res://data/world/%s_map.png" % MAP_KEY) as Texture2D

# ================================================================================================ environment

## Applies a graphics preset's open-world parts: how far and how finely the sun's shadows reach, ambient occlusion,
## the car's reflections and the screen-space effects. reflections: the Options page's choice (0 off, 1 screen-space,
## 2 ray-traced, which the open world draws as screen-space), -1 for the preset's own.
func apply_graphics(level: int, ssao := true, reflections_mode := -1) -> void:
	quality = clampi(level, 0, GraphicsPresets.PRESETS.size() - 1)
	var p := GraphicsPresets.preset(quality)
	if sun:
		sun.directional_shadow_max_distance = p.ow_shadow_distance
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if int(p.ow_shadow_splits) <= 2 \
			else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	if env:
		env.ssao_enabled = ssao
		env.ssr_enabled = (int(p.reflections) if reflections_mode < 0 else reflections_mode) > 0
		env.ssil_enabled = bool(p.get("ssil", false))
	if reflections:
		reflections.visible = bool(p.get("car_reflections", false))
	_volumetric = bool(p.get("volumetric_fog", false))
	if car_visual:
		car_visual.fx_quality = quality
	if sky_mat:
		_apply_time()
	_apply_vegetation_quality()
	if builder:
		builder.set_draw_scale(float(p.get("ow_draw_scale", 1.0)))

## The grass's density and reach follow the preset (vegetation.gd).
func _apply_vegetation_quality() -> void:
	var veg := world.find_child("Vegetation", true, false) if world else null
	if veg and veg.has_method("set_quality") and int(veg.get("quality")) != quality:
		veg.set_quality(quality)

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky_mat.set_shader_parameter("cloud_noise", WORLD.noise_texture("clouds"))
	sky_mat.set_shader_parameter("cloud_cover", 0.32)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.7 # less blue on the white walls
	env.ambient_light_color = Color(0.82, 0.78, 0.72)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	SceneMood.base(env)
	env.ssao_enabled = true
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.12
	env.ssr_fade_out = 1.6
	env.ssr_depth_tolerance = 0.3
	env.ssil_radius = 4.0
	env.ssil_intensity = 0.7
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.00028
	env.fog_aerial_perspective = 0.6
	env.fog_sky_affect = 0.0
	we.environment = env
	world.add_child(we)
	# the sun's lens flare (the races' LensFlare), drawn in this viewport under the HUD
	var flare := LensFlare.new()
	flare.source = self
	viewport.add_child(flare)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 260.0
	sun.shadow_blur = 1.2
	# a wall edge-on to the high sun self-shadowed in blocky patches that flipped as the sun crept (TASKS 14)
	sun.shadow_bias = 0.3
	sun.shadow_normal_bias = 3.0
	world.add_child(sun)
	camera = Camera3D.new()
	camera.near = 0.25
	camera.far = 42000.0
	camera.fov = 72.0
	world.add_child(camera)
	camera.make_current()

## Sun, sky, fog and lights for the hour: Brzeszcze in early summer, sunrise ~4:45, sunset ~20:45.
func _apply_time() -> void:
	var day_frac := clampf((hour - 4.75) / 16.0, 0.0, 1.0)
	var elev := deg_to_rad(63.0) * sin(PI * day_frac) if hour > 4.75 and hour < 20.75 else 0.0
	# the midday sun is held down to about 37 degrees (a September sun): a near-overhead sun lit every wall and road
	# alike and cast no shadows worth seeing. A soft cap, so a sun below about 20 degrees (the golden hour) is as before
	elev = NOON_CAP * tanh(elev / NOON_CAP)
	var below := 0.0
	if hour <= 4.75 or hour >= 20.75:
		var h := hour if hour >= 20.75 else hour + 24.0
		below = clampf((h - 20.75) / 2.0, 0.0, 1.0) * clampf((28.75 - h) / 2.0, 0.0, 1.0)
		elev = -deg_to_rad(14.0) * below
	var az := deg_to_rad(lerpf(50.0, 310.0, day_frac))
	var dir := Vector3(sin(az) * cos(elev), sin(elev), -cos(az) * cos(elev)).normalized()
	var day := clampf(elev / deg_to_rad(12.0) + 0.15, 0.0, 1.0)
	# the golden hour: from about 25 degrees down the sun turns gold, deepest a few degrees over the horizon
	var elev_deg := rad_to_deg(elev)
	golden = (1.0 - smoothstep(4.0, 25.0, elev_deg)) * smoothstep(-3.0, 1.5, elev_deg)
	night = 1.0 - day
	var sun_dir := dir if elev > -0.02 else Vector3(-dir.x, absf(dir.y) + 0.5, -dir.z).normalized() # moonlight
	sun.basis = Basis.looking_at(-sun_dir, Vector3.UP)
	var day_col := Color(1.0, 0.95, 0.86)
	var gold_col := Color(1.0, 0.55, 0.24)
	var moon_col := Color(0.6, 0.7, 1.0)
	sun.light_color = moon_col.lerp(day_col.lerp(gold_col, golden), day)
	# a strong sun against a cooler, dimmer fill (about 3:1): crisp shadows by day, warm faces and long lavender
	# shadows at the golden hour; after dark a faint blue moon, so the lamps and headlights make the light
	# midday: the sun up a little and the fill down, so faces turned from the sun drop to about a quarter of the lit
	# ones; the fill's sky share cools those shadows
	var midday := smoothstep(22.0, 32.0, elev_deg) # 0 through the golden hour and the night, which keep their look
	sun.light_energy = lerpf(0.2, 2.0, day) * lerpf(1.0, 1.05, golden) * (1.0 + 0.12 * midday)
	sun.shadow_opacity = lerpf(0.6, 1.0, day)
	sky_mat.set_shader_parameter("sun_dir", dir)
	sky_mat.set_shader_parameter("moon_dir", Vector3(-dir.x, 0.6, -dir.z).normalized())
	sky_mat.set_shader_parameter("night", night)
	sky_mat.set_shader_parameter("star_amount", clampf(night * 1.4 - 0.3, 0.0, 1.0) * 0.12) # under the night exposure and glow
	# a deep blue night sky (not black), a richer blue overhead by day
	# (the golden sky stays a clean blue overhead: a pink horizon blended into it went lavender through ACES)
	sky_mat.set_shader_parameter("top_color", Color(0.035, 0.065, 0.2).lerp(Color(0.13, 0.33, 0.72).lerp(Color(0.16, 0.4, 0.7), golden), day))
	sky_mat.set_shader_parameter("horizon_color", Color(0.06, 0.1, 0.22).lerp(Color(0.6, 0.73, 0.88).lerp(Color(0.98, 0.78, 0.5), golden * 0.8), day))
	sky_mat.set_shader_parameter("glow_color", Color(1.0, 0.48, 0.2))
	sky_mat.set_shader_parameter("glow_amount", golden)
	sky_mat.set_shader_parameter("sun_color", day_col.lerp(gold_col, golden))
	sky_mat.set_shader_parameter("sky_energy", lerpf(0.8, 1.0, day))
	# the town's sodium glow low on the night horizon, lighting the cloud bellies from below
	sky_mat.set_shader_parameter("city_glow", Color(0.5, 0.3, 0.16) * 0.22 * night)
	sky_mat.set_shader_parameter("cloud_lit", Color(0.13, 0.15, 0.24).lerp(Color(1, 1, 1).lerp(Color(1.0, 0.68, 0.46), golden), day))
	sky_mat.set_shader_parameter("cloud_shade", Color(0.05, 0.06, 0.11).lerp(Color(0.55, 0.6, 0.7).lerp(Color(0.62, 0.5, 0.6), golden), day))
	sky_mat.set_shader_parameter("halo_amount", 0.15 * day + 0.65 * golden)
	# sunlit haze: thicker and gold towards the sun, so the distance glows behind the trees
	env.fog_light_color = Color(0.03, 0.05, 0.11).lerp(Color(0.66, 0.75, 0.87).lerp(Color(0.97, 0.64, 0.4), golden), day)
	env.fog_sun_scatter = 0.6 * golden
	# plus a daytime haze, so the far blocks and trees fall back into a paler blue and the near ones stand out
	env.fog_density = 0.00028 * lerpf(1.0, 2.4, golden) * lerpf(1.0, 1.6, night) + 0.00045 * midday
	env.fog_aerial_perspective = lerpf(0.6, 0.85, midday)
	# the fill: a cool sky blue by day (the shadow colour), lavender at the golden hour, a dim moonlit blue at night
	env.ambient_light_energy = lerpf(0.95, 0.48, day) * lerpf(1.0, 0.75, golden) * (1.0 - 0.25 * midday)
	env.ambient_light_color = Color(0.34, 0.42, 0.72).lerp(Color(0.78, 0.8, 0.86).lerp(Color(0.66, 0.66, 0.88), golden * 0.7), day) \
		.lerp(Color(0.66, 0.76, 0.95), 0.5 * midday)
	env.ambient_light_sky_contribution = lerpf(0.25, 0.6, day) * lerpf(1.0, 0.6, golden) # the pink sky would wash the shadows out
	SceneMood.by_hour(env, day, golden, night, 1.06) # ACES already deepens the colour
	# contact shadows also darken sunlit ground a little by day: under the car, at wall feet, kerbs and fences
	env.ssao_light_affect = lerpf(0.12, 0.3, midday)
	env.ssao_intensity = lerpf(2.2, 2.8, midday)
	# Ultra: sun shafts through the trees and between the houses (volumetric fog lit by the low sun)
	var shafts := _volumetric and golden > 0.05 and day > 0.2
	if env.volumetric_fog_enabled != shafts:
		env.volumetric_fog_enabled = shafts
	if shafts:
		env.volumetric_fog_density = 0.0045 * golden
		env.volumetric_fog_albedo = Color(1.0, 0.86, 0.7)
		env.volumetric_fog_length = 160.0
		env.volumetric_fog_anisotropy = 0.7 # forward scattering: the shafts glow looking into the sun
		sun.light_volumetric_fog_energy = 1.6
	# streetlamps, windows and headlights after dusk
	var lamps_on := clampf((night - 0.35) * 3.0, 0.0, 1.0)
	if builder:
		if builder.lamp_material:
			builder.lamp_material.emission_energy_multiplier = 14.0 * lamps_on # bright enough to bloom
		var damp := maxf(wet, NIGHT_DAMP * lamps_on)
		for m in builder.night_materials:
			m.set_shader_parameter("night", lamps_on)
			if m.shader == TOWN_ROAD_SHADER or m.shader == PAVEMENT_SHADER: # the streets, not the walls
				m.set_shader_parameter("wet", damp)
	# the beams with the lamp lenses (race_car_visual.gd set_lamps follows the same level)
	var beams: float = CAR_VISUAL.headlamp_level(night)
	for h in headlights:
		h.light_energy = HEADLIGHT_ENERGY * beams
		h.visible = beams > 0.0
	# each pooled lamp fades out towards the farthest one's distance, so a lamp never snaps on or off as the pool
	# moves from one to the next (_place_lamp_lights); the tarmac is dark, so its pool is mostly the decal's glow
	var here := Vector2(drive.car.x, drive.car.y) if drive else Vector2.ZERO
	for l in lamp_lights:
		var d := Vector2(l.position.x, l.position.z).distance_to(here)
		var near := (1.0 - smoothstep(_lamp_reach * 0.7, _lamp_reach, d)) * lamps_on
		l.light_energy = 4.5 * near
		(l.get_child(0) as Decal).emission_energy = LAMP_POOL_GLOW * near * (1.0 + 0.4 * wet)
		l.visible = lamps_on > 0.02

## Dipped beams: aimed down onto the road, brightest in the middle of the cone and fading with distance, so the road
## ahead is lit and a wall 20 m off gets a soft pool up to the first floor, not a white sheet over the whole facade
## (70 m reach, a 0.8 distance falloff and a 28 degree cone tilted 4 degrees down lit a 5-storey block at full power).
func _build_headlights() -> void:
	for x: float in [-0.5, 0.5]:
		var s := SpotLight3D.new()
		s.position = Vector3(x, 0.66, -1.75)
		s.spot_range = 50.0
		s.spot_angle = 24.0
		s.spot_angle_attenuation = 0.75 # most of the light in the middle of the beam, a soft edge
		s.spot_attenuation = 1.3 # nearer the inverse square than the old 0.8: 20 m gets a third of 8 m's light
		s.light_specular = 0.15 # no glare off wet tarmac and glazing
		s.light_color = Color(1.0, 0.95, 0.82)
		s.shadow_enabled = false
		s.visible = false
		s.rotation = Vector3(deg_to_rad(-6.0), 0.0, 0.0)
		car_visual.add_child(s)
		headlights.append(s)

func _build_lamp_lights() -> void:
	for i in LAMP_LIGHTS:
		var l := OmniLight3D.new()
		l.omni_range = 22.0
		l.omni_attenuation = 1.8 # a bright pool under the lamp that falls off quickly: light and dark between lamps
		l.light_color = Color(1.0, 0.72, 0.4) # sodium
		l.shadow_enabled = false
		l.visible = false
		# a pool of warm light on the ground under it, so the road shows light and dark between the lamps
		var pool := Decal.new()
		pool.name = "Pool"
		pool.size = Vector3(18.0, 6.0, 18.0)
		pool.position = Vector3(0.0, -8.0, 0.0)
		pool.texture_emission = _lamp_pool_texture()
		pool.albedo_mix = 0.0
		pool.modulate = Color(1.0, 0.68, 0.36)
		pool.emission_energy = 0.0
		pool.upper_fade = 0.5
		pool.lower_fade = 0.5
		pool.normal_fade = 0.5 # the ground, not the cars and walls
		l.add_child(pool)
		world.add_child(l)
		lamp_lights.append(l)

static func _lamp_pool_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1), Color(0.42, 0.42, 0.42), Color(0, 0, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	return t

## The nearest street lamps get real lights (a pool follows the car).
func _place_lamp_lights() -> void:
	if builder == null or builder.lamp_spots.is_empty() or night < 0.3:
		return
	var p := Vector3(drive.car.x, drive.z, drive.car.y)
	# from the builder's lamp grid: a few dozen candidates however many lamps the town has
	var best := builder.lamps_near(p.x, p.z, lamp_lights.size(), 200.0)
	# the farthest lamp of a full pool is where the lights have faded to nothing (less the ground covered until the
	# next placing)
	_lamp_reach = 200.0
	if best.size() >= lamp_lights.size():
		var far := best[best.size() - 1]
		_lamp_reach = maxf(Vector2(far.x - p.x, far.z - p.z).length() - 12.0, 25.0)
	for i in lamp_lights.size():
		if i < best.size():
			lamp_lights[i].position = best[i] + Vector3.DOWN * 0.6
			lamp_lights[i].visible = true
		else:
			lamp_lights[i].visible = false

func _build_route_mesh() -> void:
	route_mesh = MeshInstance3D.new()
	route_mat = StandardMaterial3D.new()
	route_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	route_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	route_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	route_mat.albedo_color = Color(0.55, 0.36, 1.0, 0.55)
	route_mat.disable_fog = true
	route_mesh.material_override = route_mat
	route_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(route_mesh)

## Chevrons on the road along the next stretch of the GPS route.
func _update_route_mesh() -> void:
	if route.size() < 2:
		route_mesh.mesh = null
		return
	var mb := MeshBatch.new()
	var cp := Vector2(drive.car.x, drive.car.y)
	# from the route point nearest the car, 320 m on
	var start := 0
	var best := INF
	for i in route.size():
		var d := route[i].distance_squared_to(cp)
		if d < best:
			best = d
			start = i
	var run := 0.0
	var next_mark := 6.0
	var i := start
	while i < route.size() - 1 and run < 320.0:
		var a := route[i]
		var b := route[i + 1]
		var l := a.distance_to(b)
		var t := (b - a) / maxf(l, 1e-3)
		while next_mark < run + l:
			var p := a + t * (next_mark - run)
			var side := Vector2(-t.y, t.x)
			var hit := map.road_at(p.x, p.y, drive.z)
			var y: float = (float(hit.height) if not hit.is_empty() else map.ground(p.x, p.y)) + 0.22
			var tip := p + t * 1.1
			var l0 := p - t * 0.4 + side * 1.0
			var r0 := p - t * 0.4 - side * 1.0
			mb.flat_tri(Vector3(tip.x, y, tip.y), Vector3(l0.x, y, l0.y), Vector3(p.x, y, p.y), Vector3.UP,
				Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Color.WHITE)
			mb.flat_tri(Vector3(tip.x, y, tip.y), Vector3(p.x, y, p.y), Vector3(r0.x, y, r0.y), Vector3.UP,
				Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Color.WHITE)
			next_mark += 7.0
		run += l
		i += 1
	route_mesh.mesh = mb.commit() if not mb.is_empty() else null

# ================================================================================================ events

## The campaign stages as beacons, coloured by state: gold done, orange open, hidden while locked.
func _refresh_events() -> void:
	for n in builder.beacon_nodes.values():
		(n as Node3D).queue_free()
	builder.beacon_nodes.clear()
	events.clear()
	var prog := Campaign.load_progress()
	var unlocked := int(prog.get("unlocked", 0))
	var trophies: Array = prog.get("trophies", [])
	for i in Campaign.STAGES.size():
		var st: Dictionary = Campaign.get_stage(i)
		var spot_name: String = STAGE_SPOTS.get(st.track, "festival")
		var spot: Array = map.spots.get(spot_name, [])
		if spot.is_empty():
			continue
		var done: bool = st.trophy in trophies
		var open_ := Campaign.is_unlocked(i, progress.fans) if st.get("fan_lock", false) else i <= unlocked
		var colour := OpenWorldHud.GOLD if done else (OpenWorldHud.ORANGE if open_ else Color(0.5, 0.5, 0.55))
		var pos := Vector2(spot[0], spot[1])
		# two stages on one spot stand a little apart
		for e in events:
			if (e.pos as Vector2).distance_to(pos) < 14.0:
				var h := float(spot[2])
				pos += Vector2(-sin(h), cos(h)) * 16.0
		var ev := {"stage": i, "spot": spot_name, "pos": pos, "heading": float(spot[2]), "done": done, "open": open_,
			"color": colour, "title": String(st.title), "act": String(st.act_name)}
		events.append(ev)
		if open_:
			var label := "%s%s" % ["★ " if done else "", String(st.title).to_upper()]
			builder.add_beacon("stage_%d" % i, pos, colour, label)
	_add_mission_events(prog)
	_add_live_events()
	_live_cp_beacon()
	_update_markers()

func _update_markers() -> void:
	var list := []
	for e in events:
		if e.has("mission"):
			list.append(_mission_marker(e))
			continue
		if e.has("live"):
			list.append(_live_marker(e))
			continue
		var st: Dictionary = Campaign.get_stage(e.stage)
		var info := "%s · %s · %s" % [e.title, SPOT_NOTE.get(e.spot, ""), "Done" if e.done else ("Open" if e.open else "Locked")]
		list.append({"pos": e.pos, "color": e.color, "label": "%d. %s" % [e.stage + 1, String(st.track).capitalize()], "info": info})
	if wp_on and wp_poi == "":
		list.append({"pos": wp_pos, "color": OpenWorldHud.PURPLE, "label": "WAYPOINT", "kind": "waypoint", "info": "Your waypoint"})
	list.append_array(Poi.markers(pois, progress, wp_poi if wp_on else ""))
	hud.set_markers(list)
	hud.set_summary(Poi.summary(pois, progress, progress.roads.size(), map.road_pts.size()))
	_place_waypoint_beacon()

## The campaign missions (Missions) as beacons of their own colour at the places they start, once open; their
## events carry stage = Missions.BASE + k, so the route, spawn and start code takes them like stages.
func _add_mission_events(prog: Dictionary) -> void:
	for k in Missions.MISSIONS.size():
		var idx := Missions.BASE + k
		# where the mission starts on the map (MapMissions: the knockout and the rally start off the old Bór circuit)
		var mev := MapMissions.event(idx)
		if mev.is_empty(): # raced on the map or not at all
			continue
		var pose := [mev.pos.x, mev.pos.y, float(mev.heading)]
		if pose.is_empty() or not map.in_play(Vector2(pose[0], pose[1])):
			continue
		var open_ := Missions.is_unlocked(idx, prog)
		var done := Missions.is_cleared(idx, prog)
		var m: Dictionary = Missions.MISSIONS[k]
		var pos := Vector2(pose[0], pose[1])
		for e in events:
			if (e.pos as Vector2).distance_to(pos) < 14.0:
				pos += Vector2(cos(float(pose[2])), sin(float(pose[2]))) * 18.0 # along the road, not into the verge
		var colour := Missions.DONE_COLOR if done else (Missions.COLOR if open_ else Color(0.5, 0.5, 0.55))
		var title := "%s: %s" % [String(Missions.KIND_NAMES[m.kind]).capitalize(), m.title]
		# heading points back along the road, as a stage spot's does: the car comes back facing on down the route
		events.append({"stage": idx, "mission": k, "spot": "", "pos": pos, "heading": float(pose[2]) + PI, "done": done,
			"open": open_, "color": colour, "title": title, "act": Missions.ACT_NAMES[clampi(int(m.act) - 1, 0, 2)]})
		if open_:
			builder.add_beacon("mission_%d" % k, pos, colour, "%s%s" % ["★ " if done else "", title.to_upper()])

func _mission_marker(e: Dictionary) -> Dictionary:
	var m: Dictionary = Missions.MISSIONS[int(e.mission)]
	var info := "%s · %s · %s" % [e.title, Missions.target_text(int(e.stage)), "Done" if e.done else ("Open" if e.open else "Locked")]
	return {"pos": e.pos, "color": e.color, "label": "%s · %s" % [Missions.KIND_NAMES[m.kind], m.title], "info": info, "kind": "mission"}

# ------------------------------------------------------------------------------------------ live events

## Live events (LiveEvents): generated round the car on the map's own roads and raced right here. They sit at the
## end of `events` with "live" set (so the GPS, the map, the beacons and the cards take them like the stages) and
## come and go as the board changes (_live_sync).
func _live_open() -> void:
	if live == null:
		live = LiveEvents.new(map)
	if live.is_running():
		live.abandon()
	_live_cp_beacon()
	var cp := Vector2(drive.car.x, drive.car.y)
	live.update(0.0, 0.0, cp, _beacon_points(), live.board.size() < LiveEvents.MAX_LIVE)
	_live_sync()

## Where the stage and mission beacons stand, which live events keep clear of.
func _beacon_points() -> PackedVector2Array:
	var out := PackedVector2Array()
	for e in events:
		if not e.has("live"):
			out.append(e.pos)
	return out

func _add_live_events() -> void:
	if live == null:
		return
	for lev in live.board:
		var title := "%s: %s" % [String(LiveEvents.KIND_NAMES[lev.kind]).capitalize(), lev.title]
		events.append({"live": lev.id, "stage": -1, "spot": "", "pos": lev.pos, "heading": lev.heading, "done": false,
			"open": true, "color": lev.color, "title": title, "act": "Live event"})
		builder.add_beacon("live_%s" % lev.id, lev.pos, lev.color, String(LiveEvents.KIND_NAMES[lev.kind]))

## Rebuilds the live entries of `events` (and their beacons) from the board, keeping the GPS on the same event.
func _live_sync() -> void:
	var keep := ""
	if gps_target >= 0 and gps_target < events.size() and events[gps_target].has("live"):
		keep = String(events[gps_target].live)
	var active_live_id := ""
	if active_event >= 0 and active_event < events.size() and events[active_event].has("live"):
		active_live_id = String(events[active_event].live)
	for k in range(events.size() - 1, -1, -1):
		if events[k].has("live"):
			var key := "live_%s" % events[k].live
			var n: Variant = builder.beacon_nodes.get(key)
			if n is Node3D:
				(n as Node3D).queue_free()
			builder.beacon_nodes.erase(key)
			events.remove_at(k)
	_add_live_events()
	if keep != "":
		gps_target = -1
		for k in events.size():
			if String(events[k].get("live", "")) == keep:
				gps_target = k
				break
		if gps_target < 0 and not gps_waypoint:
			gps_target = _next_open_event()
			_recompute_route()
	if active_live_id != "":
		active_event = -1
		for k in events.size():
			if String(events[k].get("live", "")) == active_live_id:
				active_event = k
				break
		if active_event < 0:
			hud.hide_event()
	elif active_event >= events.size():
		active_event = -1
		hud.hide_event()
	_update_markers()

func _live_marker(e: Dictionary) -> Dictionary:
	var lev := live.find(String(e.live)) if live else {}
	var info := String(e.title)
	if not lev.is_empty():
		info += " · %s" % live.target_text(lev, CarCatalog.key_at(progress.car_class))
	return {"pos": e.pos, "color": e.color, "label": String(LiveEvents.KIND_NAMES.get(lev.get("kind", ""), "LIVE EVENT")),
		"info": info, "kind": "live"}

## Puts the car on the event's line, facing down the route, and starts the countdown.
func _begin_live(id: String) -> void:
	var lev := live.find(id)
	if lev.is_empty():
		return
	drive.place(lev.pos, float(lev.heading))
	snap_camera()
	live.begin(lev, CarCatalog.key_at(progress.car_class))
	active_event = -1
	hud.hide_event()
	gps_waypoint = false
	_live_cp_beacon()
	_recompute_route()
	hud.notify(String(LiveEvents.KIND_NAMES[lev.kind]), String(lev.title), lev.color)

## The beacon at the next checkpoint (or the finish) while an event runs; none otherwise.
func _live_cp_beacon() -> void:
	if builder == null:
		return
	var old: Variant = builder.beacon_nodes.get("live_cp")
	if old is Node3D:
		(old as Node3D).queue_free()
	builder.beacon_nodes.erase("live_cp")
	if live == null or not live.is_running():
		_clear_rivals()
		return
	var lev: Dictionary = live.run.ev
	if live.run.state == "liaison":
		var st: Dictionary = lev.stages[int(live.run.stage)]
		builder.add_beacon("live_cp", live.next_target(), lev.color, "SS%d START · %s" % [int(live.run.stage) + 1, String(st.name).to_upper()])
		return
	var cps: PackedVector2Array = live.run.cps
	var i := int(live.run.cp)
	var label := "FINISH" if i >= cps.size() - 1 else "CHECKPOINT %d/%d" % [i + 1, cps.size()]
	builder.add_beacon("live_cp", cps[i], lev.color, label)

## One frame of the live events: the run (timer, checkpoints, result) or, between runs, the board round the car.
func _update_live(delta: float) -> void:
	if live == null:
		return
	var cp := Vector2(drive.car.x, drive.car.y)
	if live.is_running():
		var car := drive.car
		var v := Vector2(car.vx, car.vy).length()
		var slip := absf(wrapf(atan2(car.vy, car.vx) - car.heading, -PI, PI)) if v > 1.0 else 0.0
		var off := map.road_at(cp.x, cp.y, drive.z, DriftScore.OFF_ROAD).is_empty()
		var lev: Dictionary = live.run.ev
		var r := live.tick(delta * _time_rate, cp, v, slip, off and not drive.airborne, _crashed_frame, drive.z)
		match r:
			"go":
				hud.notify("GO!", String(lev.title), lev.color)
			"cp":
				_live_cp_beacon()
				_recompute_route()
				hud.notify("CHECKPOINT", LiveEvents.clock_text(float(live.run.t)), lev.color)
			"stage_done":
				var n := (live.run.stage_times as Array).size()
				hud.notify("SS%d DONE · %s" % [n, LiveEvents.clock_text(float(live.run.stage_times[n - 1]))],
					"P%d overall · drive the liaison to SS%d" % [live.rally_place(), n + 1], lev.color)
				_live_cp_beacon()
				_recompute_route()
			"stage":
				hud.notify("SS%d · %s" % [int(live.run.stage) + 1, String(lev.stages[int(live.run.stage)].name)], "On the line", lev.color)
				_live_cp_beacon()
				_recompute_route()
			"done", "fail":
				_live_finished()
		if live.is_running():
			_update_rivals(delta)
		var lines := live.hud_lines(cp)
		hud.set_live(String(lines[0]), String(lines[1]), lev.color)
		return
	hud.set_live("", "", Color.WHITE)
	var before := _live_ids()
	var added := live.update(delta, delta * DAY_RATE, cp, _beacon_points())
	for lev in added:
		var d := (lev.pos as Vector2).distance_to(cp)
		if d < LiveEvents.ANNOUNCE:
			hud.notify("NEW LIVE EVENT", "%s · %s · %d m" % [LiveEvents.KIND_NAMES[lev.kind], lev.title, int(d)], lev.color)
	if _live_ids() != before:
		_live_sync()

func _live_ids() -> String:
	var ids := PackedStringArray()
	for lev in live.board:
		ids.append(String(lev.id))
	return ",".join(ids)

func _live_finished() -> void:
	var res := live.last_result
	var lev: Dictionary = res.get("ev", {})
	if lev.has("mission"):
		_mission_finished(res)
		return
	var kind := String(lev.get("kind", ""))
	var tier := int(res.get("tier", 0))
	progress.record_live(kind, tier)
	_live_cp_beacon()
	hud.set_live("", "", Color.WHITE)
	if tier > 0:
		var sub := "%s · %s" % [String(res.line), String(res.get("next", ""))] if String(res.get("next", "")) != "" else String(res.line)
		hud.notify("%s · %s" % [LiveEvents.TIER_NAMES[tier], LiveEvents.KIND_NAMES[kind]], sub, LiveEvents.TIER_COLORS[tier])
		_add_fans(int(res.fans), "LIVE EVENT")
	else:
		var why := String(res.line) if not res.has("next") else "%s · %s" % [String(res.line), String(res.get("next", ""))]
		hud.notify("NO MEDAL · %s" % LiveEvents.KIND_NAMES.get(kind, "EVENT"), why + " · the event stays up for another go", LiveEvents.TIER_COLORS[0])
	_live_sync()
	if not gps_waypoint and (gps_target < 0 or gps_target >= events.size() or events[gps_target].has("live")):
		gps_target = _next_open_event()
	_recompute_route()
	_save()

# ------------------------------------------------------------------------------------------ missions on the map

## A campaign mission raced where it stands (MapMissions): the car goes on the grid, the clock is set to the
## mission's hour, the roads close to traffic and the field lines up. False when its route is not on the map (the
## caller then loads it as a race as before).
func _begin_mission(index: int) -> bool:
	if live == null:
		return false
	var lev := MapMissions.event(index)
	if lev.is_empty():
		return false
	var def: Dictionary = Missions.get_def(index)
	hour = float(def.get("start_hour", hour))
	if sun: # (built worlds only: _process applies it every frame anyway)
		_apply_time()
	live.begin(lev, CarCatalog.key_at(progress.car_class))
	var g: Array = live.grid_pose(lev)
	drive.place(g[0], float(g[1]))
	snap_camera()
	if traffic:
		traffic.clear()
	active_event = -1
	hud.hide_event()
	gps_waypoint = false
	_spawn_rivals()
	_live_cp_beacon()
	_recompute_route()
	hud.notify("%s MISSION" % Missions.KIND_NAMES[def.kind], String(def.title), Missions.COLOR)
	return true

## A mission is on: the town's traffic is kept off its roads.
func _roads_closed() -> bool:
	return live != null and live.is_running() and live.run.ev.has("mission")

func _spawn_rivals() -> void:
	_clear_rivals()
	var rv := live.rivals()
	if rv == null:
		return
	for k in rv.rivals.size():
		var node: Node3D = CAR_SCENE.instantiate()
		node.car_key = CarCatalog.key_at(progress.car_class)
		world.add_child(node)
		node.set_paint(Color(RIVAL_PAINTS[k % RIVAL_PAINTS.size()]))
		_rival_nodes.append(node)
	_update_rivals(0.0)

func _clear_rivals() -> void:
	for n in _rival_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_rival_nodes.clear()

## The field drawn where StreetRivals has it, out of the race once knocked out, and pushed by the player's car.
func _update_rivals(delta: float) -> void:
	var rv := live.rivals()
	if rv == null or _rival_nodes.size() != rv.rivals.size():
		return
	var me := Vector2(drive.car.x, drive.car.y)
	for k in rv.rivals.size():
		var r: Dictionary = rv.rivals[k]
		var node := _rival_nodes[k]
		if bool(r.get("out", false)):
			node.visible = false
			continue
		var pose: Array = rv.pose(float(r.s), float(r.lat))
		var p: Vector2 = pose[0]
		var dir: Vector2 = pose[1]
		var hit := map.road_at(p.x, p.y, drive.z, 2.0)
		var y: float = float(hit.height) if not hit.is_empty() else map.ground(p.x, p.y)
		node.visible = true
		node.position = Vector3(p.x, y, p.y)
		node.basis = Basis(Vector3.UP, -dir.angle() - PI / 2.0)
		node.call("set_lamps", night) # headlamps and position lights after dark, like the player's
		# contact: two cars' worth of circles, the player shoved out and the rival knocked across
		var d := me.distance_to(p)
		if d < 2.1 and d > 0.01:
			var n_out := (me - p) / d
			var rel := Vector2(drive.car.vx, drive.car.vy) - dir * float(r.v)
			drive.bump(n_out, 2.1 - d, Vector2.ZERO, RIVAL_MASS, dir * float(r.v))
			var side := signf(Vector2(-dir.y, dir.x).dot(p - me))
			rv.knock(k, 0.5 * (side if side != 0.0 else 1.0), clampf(rel.length() * 0.3, 0.0, 6.0))

## A mission run over: recorded in the campaign save like a raced one (Missions.record), its result as banners,
## the beacons recoloured, the traffic back.
func _mission_finished(res: Dictionary) -> void:
	var lev: Dictionary = res.get("ev", {})
	var index := int(lev.mission)
	_live_cp_beacon()
	hud.set_live("", "", Color.WHITE)
	var out := MapMissions.outcome(res)
	var rec := Missions.record(index, out)
	var def: Dictionary = Missions.get_def(index)
	if bool(rec.success):
		hud.notify("MISSION CLEARED%s" % (" · " + String(rec.trophy).to_upper() if bool(rec.first_clear) else ""),
			String(out.line), OpenWorldHud.GOLD)
	else:
		hud.notify("MISSION MISSED · %s" % String(def.title), "%s · target: %s" % [String(out.line),
			Missions.target_text(index).to_lower()], Color("#ff5a4a"))
	if int(rec.fans) > 0:
		_add_fans(int(rec.fans), "MISSION")
	if String(rec.get("reward_car", "")) != "":
		hud.notify("NEW CAR WON", CarCatalog.display_name(String(rec.reward_car)).to_upper(), OpenWorldHud.GOLD)
	_refresh_events()
	if not gps_waypoint:
		gps_target = _next_open_event()
	_recompute_route()
	_save()

## The waypoint stands in the world too: a purple light column like the stages', so it can be found by eye.
func _place_waypoint_beacon() -> void:
	if builder == null:
		return
	var old: Variant = builder.beacon_nodes.get("waypoint")
	if old != null and is_instance_valid(old):
		var at: Vector3 = (old as Node3D).position
		if wp_on and wp_poi == "" and Vector2(at.x, at.z).distance_to(wp_pos) < 0.5:
			return
		(old as Node3D).queue_free()
	builder.beacon_nodes.erase("waypoint")
	if wp_on and wp_poi == "": # a route to a point of interest leaves the beacon off: the point has its own marker
		builder.add_beacon("waypoint", wp_pos, OpenWorldHud.PURPLE, "WAYPOINT")

## Driving up to the waypoint clears it, as reaching a stage beacon does: the route and the column go.
func _check_waypoint_reached() -> void:
	if not wp_on or drive == null:
		return
	if wp_poi != "":
		if Vector2(drive.car.x, drive.car.y).distance_to(wp_pos) <= WAYPOINT_REACH:
			_clear_poi_route()
		return
	if Vector2(drive.car.x, drive.car.y).distance_to(wp_pos) > WAYPOINT_REACH:
		return
	wp_on = false
	if gps_waypoint:
		gps_waypoint = false
		_recompute_route()
	_update_markers()
	hud.notify("WAYPOINT REACHED", "Set another on the map", OpenWorldHud.PURPLE)

## The first open stage that isn't cleared yet (the unlock cap stays on the last stage once the campaign is
## finished, so "unlocked" alone would point at stage 9 for ever); -1 when everything is done.
func _next_open_event() -> int:
	for k in events.size():
		if not events[k].has("live") and events[k].open and not events[k].done:
			return k
	return -1

func _spawn(spawn) -> void:
	var p := Vector2.ZERO
	var h := 0.0
	var roll := 0.0
	var found := false
	if spawn is int:
		for e in events:
			if e.stage == spawn:
				# back at the beacon, rolled a little on (clear of its trigger), facing on towards the next target
				h = e.heading + PI
				p = e.pos
				roll = SPAWN_ROLL
				found = true
	elif spawn is String and spawn != "" and map.spots.has(spawn):
		var s: Array = map.spots[spawn]
		p = Vector2(s[0], s[1])
		h = float(s[2])
		found = true
	if not found and progress.has_pos:
		p = progress.pos
		h = progress.heading
		found = true
	if not found:
		var s: Array = map.spots.get("festival", [0.0, 0.0, 0.0])
		p = Vector2(s[0], s[1])
		h = float(s[2])
	# the GPS target first: the car is put on its road facing the way the route there sets off
	if not gps_waypoint and (gps_target < 0 or gps_target >= events.size() or events[gps_target].done):
		gps_target = _next_open_event()
	var to: Variant = null
	if _has_target():
		to = _target_pos()
	spawn_car(drive, map, p, h, to, roll)
	snap_camera()
	_apply_time()
	_recompute_route()

## Puts the car at rest in first gear on the road nearest p (its right-hand lane), facing along that road: the way the
## GPS route to `to` sets off when there is one, else the way h points (a stage spot's road, the saved heading), and
## `roll` metres on along that way. Every spawn goes through here (tests/test_open_world_spawn.gd).
static func spawn_car(drive: FreeCar, map: TownMap, p: Vector2, h: float, to: Variant = null, roll := 0.0) -> void:
	drive.place(p, h)
	drive.respawn()
	var d := Vector2.ZERO
	if to is Vector2:
		d = route_dir(map, Vector2(drive.car.x, drive.car.y), to)
		if d != Vector2.ZERO:
			drive.respawn(d)
	if roll > 0.0:
		var at := Vector2(drive.car.x, drive.car.y)
		var f := Vector2.from_angle(drive.car.heading)
		var q := at + f * roll
		if d != Vector2.ZERO:
			# rolled on down the route itself, so a turn just past the beacon is taken, not driven past
			var r := map.route(at, to)
			var q2 := point_along(r, roll + 4.0)
			q = point_along(r, roll)
			if q2.distance_to(q) > 1.0:
				f = (q2 - q).normalized()
		drive.place(q, f.angle())
		drive.respawn(f)

## The point dist metres along the polyline r (its end when it is shorter).
static func point_along(r: PackedVector2Array, dist: float) -> Vector2:
	if r.is_empty():
		return Vector2.ZERO
	var run := 0.0
	for k in range(1, r.size()):
		var l := r[k].distance_to(r[k - 1])
		if run + l >= dist:
			return r[k - 1].lerp(r[k], (dist - run) / maxf(l, 1e-6))
		run += l
	return r[r.size() - 1]

## The way along its road the GPS route from p to `to` sets off (a unit vector); zero when there is no route or p is
## already there. TownMap.route starts at p's projection on the nearest road and goes straight to the junction the
## route leaves by, so the first route point off the start, found on that road, says which way along it to go.
static func route_dir(map: TownMap, p: Vector2, to: Vector2) -> Vector2:
	var r := map.route(p, to)
	if r.size() < 2:
		return Vector2.ZERO
	var a := map.nearest_road(p, 120.0) # the projection the route starts from
	if a.is_empty():
		return Vector2.ZERO
	var length := 0.0
	for k in range(1, r.size()):
		length += r[k].distance_to(r[k - 1])
	if length < 4.0:
		return Vector2.ZERO # the target is right here
	var pts: PackedVector2Array = map.road_pts[int(a.road)]
	var at := float(a.i) + float(a.t)
	for k in range(1, r.size()):
		if r[k].distance_to(r[0]) < 1.0:
			continue
		for j in pts.size():
			if pts[j].distance_squared_to(r[k]) < 0.01 and absf(float(j) - at) > 0.001:
				return (a.dir as Vector2) * signf(float(j) - at)
		return (r[k] - r[0]).normalized() # not on the start road (a junction right at the start): the chord
	return Vector2.ZERO

## Cuts the chase camera to its place behind the car after the car was put somewhere new (spawn, reset, teleport),
## so it neither sweeps across the map nor swings round from the old heading.
func snap_camera() -> void:
	_prev_pos = Vector3(drive.car.x, drive.z, drive.car.y)
	_prev_heading = drive.car.heading
	var f := Vector3(cos(drive.car.heading), 0.0, sin(drive.car.heading))
	cam_pos = _prev_pos - f * 7.0 + Vector3.UP * 2.6
	cam_vel_dir = Vector2(f.x, f.z)
	_chase_cam = null # snaps to the car's new spot
	look.reset()

func _check_events() -> void:
	if live and live.is_running():
		if active_event >= 0:
			active_event = -1
			hud.hide_event()
		return
	var cp := Vector2(drive.car.x, drive.car.y)
	var found := -1
	for k in events.size():
		if (events[k].pos as Vector2).distance_to(cp) < BEACON_RADIUS:
			found = k
	if found == active_event:
		return
	active_event = found
	if found < 0:
		hud.hide_event()
		return
	var ev: Dictionary = events[found]
	if ev.has("live"):
		var lev := live.find(String(ev.live))
		if not lev.is_empty():
			var c := live.card(lev, CarCatalog.key_at(progress.car_class))
			hud.show_event(String(c[0]), String(c[1]), String(c[2]), String(c[3]), ev.color)
		return
	if ev.has("mission"):
		var c := Missions.card(int(ev.stage), FanLevels.level(progress.fans))
		hud.show_event(String(c[0]), String(c[1]), String(c[2]), String(c[3]), ev.color)
		return
	var st: Dictionary = Campaign.get_stage(ev.stage)
	var target := "Win the race" if int(st.target_pos) == 1 else "Finish P%d or better" % int(st.target_pos)
	var body := "%s\n\n%s · %d laps · %s · %d rivals (%s)\nTarget: %s · Trophy: %s\nFan level %d recommended (you are level %d) · up to %s fans on a first clear" % [st.desc, SPOT_NOTE.get(ev.spot, ""),
		int(st.laps), String(st.weather).capitalize(), int(st.opponents), String(st.difficulty).capitalize(), target, st.trophy,
		FanLevels.stage_level(int(ev.stage)), FanLevels.level(progress.fans),
		OpenWorldHud._thousands(FanLevels.stage_reward(int(ev.stage), 1, int(st.target_pos), true))]
	var hint := "ENTER / B  ▸  START STAGE" if ev.open else "LOCKED · clear the stages before it first"
	hud.show_event(String(st.act_name).to_upper(), String(st.title), body, hint, ev.color)

func _start_active_event() -> void:
	if active_event < 0:
		return
	var ev: Dictionary = events[active_event]
	if not ev.open:
		return
	if ev.has("live"):
		_begin_live(String(ev.live))
		return
	if ev.has("mission"): # only ever on the map
		_begin_mission(int(ev.stage))
		return
	_save()
	stage_requested.emit(int(ev.stage))

# ================================================================================================ speed traps, discovery

func _build_traps() -> void:
	traps = Poi.find_traps(map)
	for t in traps:
		_add_trap_sign(t.pos, t.dir, t.road)
	pois = Poi.build(map, traps)

func _add_trap_sign(p: Vector2, dir: Vector2, ri: int) -> void:
	var side := Vector2(-dir.y, dir.x)
	var q := p + side * (map.road_w[ri] * 0.5 + 1.6)
	var node := Node3D.new()
	node.position = Vector3(q.x, map.ground(q.x, q.y), q.y)
	var mb := MeshBatch.new(false, true)
	mb.beam(Vector3(0, 0, 0), Vector3(0, 0, 0.01), 0.12, 2.6, Color(0.6, 0.6, 0.62))
	mb.beam(Vector3(-0.6, 2.4, 0), Vector3(0.6, 2.4, 0), 0.06, 0.9, Color(0.1, 0.35, 0.95))
	var inst := MeshInstance3D.new()
	inst.mesh = mb.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.emission_enabled = true
	m.emission = Color(0.1, 0.3, 1.0)
	m.emission_energy_multiplier = 0.4
	inst.material_override = m
	node.add_child(inst)
	var label := Label3D.new()
	label.text = "SPEED TRAP"
	label.font_size = 64
	label.pixel_size = 0.012
	label.outline_size = 10
	label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	label.position = Vector3(0, 3.7, 0)
	label.modulate = Color("#9ecbff")
	label.visibility_range_end = 220.0
	node.add_child(label)
	world.add_child(node)
	map.add_post(q, 0.15)

func _check_traps() -> void:
	var cp := Vector2(drive.car.x, drive.car.y)
	for t in traps:
		var d: Vector2 = cp - (t.pos as Vector2)
		var along := d.dot(t.dir)
		var across := absf(d.dot(Vector2(-t.dir.y, t.dir.x)))
		var near := absf(along) < 4.0 and across < 12.0
		if near and not _trap_near.get(t.id, false):
			_trap_driven(t, drive.speed_kmh())
		_trap_near[t.id] = near

## One run through a trap: the banner (the first-ever run explains traps in the same banner), the best speed kept,
## fans for a new best, and the trap shown as driven on the map.
func _trap_driven(t: Dictionary, kmh: float) -> void:
	var p := Poi.find(pois, String(t.id))
	var best := float(progress.traps.get(t.id, 0.0))
	var first: bool = not progress.traps.has(t.id)
	var star_txt := Poi.star_text(Poi.stars(kmh))
	var sub := "%s · %s%s" % [t.name, star_txt, "  NEW BEST" if kmh > best + 0.5 else "  best %d km/h" % int(best)]
	if p != null:
		p.record_run(progress, kmh)
		if first:
			sub += "\n%s %d / %d driven. %s" % [Poi.KINDS[Poi.TRAP].plural, Poi.counts(pois, progress)[Poi.TRAP][0], Poi.TRAP_COUNT, Poi.take_intro(progress, Poi.TRAP)]
	elif kmh > best:
		progress.traps[t.id] = snappedf(kmh, 0.1)
	hud.notify("SPEED TRAP  %d KM/H" % int(round(kmh)), sub, Color("#4aa3ff"))
	if kmh > best:
		_add_fans(int(kmh * 4.0), "")
	if first or kmh > best:
		_update_markers()
	if wp_poi == t.id:
		_clear_poi_route()

func _check_discovery() -> void:
	var cp := Vector2(drive.car.x, drive.car.y)
	if not drive.road.is_empty():
		var ri: int = drive.road.road
		if not progress.roads.has(ri):
			progress.roads[ri] = true
			hud.set_summary(Poi.summary(pois, progress, progress.roads.size(), map.road_pts.size()))
			if progress.roads.size() % 50 == 0:
				hud.notify("ROADS DRIVEN  %d / %d" % [progress.roads.size(), map.road_pts.size()], "Every street of Brzeszcze, one at a time")
		hud.set_street(street_label(map.road_name[ri]))
	var found := Poi.discover_near(pois, progress, cp)
	for p in found:
		var c: Array = Poi.counts(pois, progress)[Poi.LANDMARK]
		var sub := "%s\n%s · %d / %d landmarks · +%s fans" % [p.name, p.sub, c[0], c[1], OpenWorldHud._thousands(Poi.LANDMARK_FANS)]
		if found.find(p) == 0:
			var tip := Poi.take_intro(progress, Poi.LANDMARK)
			if tip != "":
				sub += "\n" + tip
		hud.notify("DISCOVERED", sub, Poi.KINDS[Poi.LANDMARK].color)
		_add_fans(Poi.LANDMARK_FANS, "")
		if wp_poi == p.id:
			_clear_poi_route()
	if not found.is_empty():
		_update_markers()

## How a street is signed: "ul. Dworcowa", "Rondo NSZZ Solidarność", the S1, the DW933.
static func street_label(name: String) -> String:
	if name == "":
		return ""
	if name.is_valid_int():
		return "DW" + name
	var re := RegEx.create_from_string("^[ASD]?\\d+$")
	if re.search(name):
		return name
	for prefix in ["Rondo", "Plac", "Aleja", "Al.", "Osiedle", "os."]:
		if name.begins_with(prefix):
			return name
	return "ul. " + name

func _check_area() -> void:
	var cp := Vector2(drive.car.x, drive.car.y)
	var best := ""
	var best_d := 700.0
	for pl in map.places:
		if not String(pl.k) in AREA_KINDS:
			continue
		var d := Vector2(pl.x, pl.y).distance_to(cp)
		if String(pl.k) == "place_town":
			d *= 0.6 # the town centre claims a wider area
		if d < best_d:
			best_d = d
			best = String(pl.name)
	if best != "" and best != area_name:
		area_name = best
		hud.show_area(best)

# ================================================================================================ skills

func _skill(points: float, label: String) -> void:
	if chain_idle > CHAIN_IDLE or chain_points <= 0.0:
		chain_points = 0.0
		_chain_events = 0
		chain_mult = 1.0
	chain_points += points
	nitro = minf(1.0, nitro + points * CarMods.NITRO_REFILL)
	chain_idle = 0.0
	chain_label = label

func _skill_event(points: float, label: String) -> void:
	_skill(points, label)
	_chain_events += 1
	chain_mult = minf(5.0, 1.0 + _chain_events / 3.0)

var _fitted_class := -1 ## the car class currently on the player's car
var mods := {} ## CarMods switched on and unlocked (id -> true)
var _time_rate := 1.0 ## bullet time's simulation speed
var _rainbow_t := 0.0
var nitro := 1.0 ## CarMods' Nitrous: the bottle, 0..1
var nitro_on := false ## the boost button is held
var _drift_t := 0.0 ## seconds the current slide has lasted
var _drift_paid := 0.0

func _update_skills(dt: float) -> void:
	var car := drive.car
	var v := Vector2(car.vx, car.vy).length()
	if v > 8.0 and not drive.airborne:
		var vel_h := atan2(car.vy, car.vx)
		var slip := absf(wrapf(vel_h - car.heading, -PI, PI))
		if slip > 0.26 and slip < 1.9:
			_skill(dt * v * 3.6 * slip * 6.0, "DRIFT")
			_drift_t += dt
			if _drift_t > 1.0 and absf(_drift_t - _drift_paid) >= 1.0:
				_drift_paid = floorf(_drift_t) # every second of a held slide adds to the chain's multiplier
				_skill_event(150.0 * _drift_paid, "LONG DRIFT  %.0f s" % _drift_paid)
		else:
			_drift_t = 0.0
			_drift_paid = 0.0
	else:
		_drift_t = 0.0
		_drift_paid = 0.0
	if v * 3.6 > 105.0:
		_skill(dt * 50.0, "SPEED")
	if drive.landed > 0.0:
		if drive.last_air > 0.35:
			_skill_event(400.0 * drive.last_air, "AIR  %.1f s" % drive.last_air)
		drive.landed = 0.0
	for rel in traffic.near_misses:
		_skill_event(250.0 + rel * 10.0, "NEAR MISS")
	traffic.near_misses.clear()
	var crashed := false
	for h in drive.hits:
		if float(h[2]) > 6.0:
			crashed = true
	drive.hits.clear()
	for h in traffic.hits:
		if float(h[2]) > 6.0:
			crashed = true
	traffic.hits.clear()
	_crashed_frame = crashed
	if crashed and chain_points > 0.0:
		hud.notify("CHAIN LOST", "Crashed with %d fans in the chain" % int(chain_points * chain_mult), Color("#ff4d4d"))
		chain_points = 0.0
		_chain_events = 0
		chain_mult = 1.0
	chain_idle += dt
	if chain_points > 0.0 and chain_idle > CHAIN_IDLE:
		var banked := int(chain_points * chain_mult * (CarMods.DRIFT_FANS if mods.has("drift") else 1.0))
		_add_fans(banked, "SKILL CHAIN" if banked >= 500 else "")
		progress.best_chain = maxi(progress.best_chain, banked)
		chain_points = 0.0
		_chain_events = 0
		chain_mult = 1.0
	var shown := int(chain_points * chain_mult)
	hud.set_chain(shown, "%s  ×%.1f" % [chain_label, chain_mult] if shown > 0 else "")

## Nitrous: the held button opens the bottle for extra engine output until it runs dry; skills refill it.
func _update_nitro(dt: float) -> void:
	var has := mods.has("nitro")
	var burning := has and nitro_on and nitro > 0.0 and throttle > 0.1
	if burning:
		nitro = maxf(0.0, nitro - CarMods.NITRO_BURN * dt)
	drive.power_mul = CarMods.NITRO_POWER if burning else 1.0
	hud.set_nitro(nitro if has else -1.0, burning)

func _add_fans(n: int, banner: String) -> void:
	var before := FanLevels.level(progress.fans)
	progress.fans += n
	var after := FanLevels.level(progress.fans)
	if after > before:
		hud.notify("FAN LEVEL %d" % after, FanLevels.title(after).to_upper(), OpenWorldHud.GOLD)
	elif banner != "":
		hud.notify("+%s FANS" % OpenWorldHud._thousands(n), banner, OpenWorldHud.GOLD)

# ================================================================================================ GPS

func _has_target() -> bool:
	if live and live.is_running():
		return true
	return wp_on if gps_waypoint else (gps_target >= 0 and gps_target < events.size())

func _target_pos() -> Vector2:
	if live and live.is_running():
		return live.next_target()
	return wp_pos if gps_waypoint else (events[gps_target].pos as Vector2)

func _recompute_route() -> void:
	if not _has_target() or drive == null:
		route = PackedVector2Array()
	else:
		route = map.route(Vector2(drive.car.x, drive.car.y), _target_pos())
	hud.set_route(route)
	_update_route_mesh()

## Cycles through the open cars (CarCatalog): the stock Seicento, the Hypercar Seicento once the top fan level has unlocked it
## (AF Corse's no. 83), and every car the campaign has awarded.
func _toggle_car() -> void:
	var open := CarCatalog.open_keys(progress.fans)
	if open.size() < 2:
		hud.notify("HYPERCAR LOCKED", "Reach fan level %d: %s" % [FanLevels.THRESHOLDS.size(), FanLevels.title(FanLevels.THRESHOLDS.size()).to_upper()], Color("#ff5a4a"))
		return
	var next: String = open[(open.find(CarCatalog.key_at(progress.car_class)) + 1) % open.size()]
	progress.car_class = CarCatalog.index_of(next)
	_fit_car()
	hud.notify("STOCK SEICENTO" if next == "stock" else CarCatalog.display_name(next).to_upper(), "Fitted", OpenWorldHud.GOLD)

## The catalogue car's name when it is neither Seicento, for the pause menu's CAR button.
func _car_name() -> String:
	var key := CarCatalog.key_at(progress.car_class)
	return "" if key == "stock" or key == "hypercar" else CarCatalog.display_name(key)

## Puts the chosen car's model and livery on the player's car.
func _fit_car() -> void:
	_fitted_class = progress.car_class
	var key := CarCatalog.key_at(progress.car_class)
	drive.fit_model(CarCatalog.model(key))
	if car_visual:
		car_visual.set_car(key)
		# set_car frees the visual's children, the beams among them: without new ones the next car drove dark
		if headlights.any(func(h: SpotLight3D) -> bool: return not is_instance_valid(h) or h.get_parent() != car_visual):
			headlights.clear()
			_build_headlights()
	_apply_look()

## The fitted car's livery and the modifiers switched on (CarMods), on the visual and the physics.
func _apply_look() -> void:
	var hyper := progress.car_class == 1
	var livery := CarCatalog.livery(CarCatalog.key_at(progress.car_class))
	mods = CarMods.active(progress.mods, progress.fans)
	CarMods.apply_to(drive, mods)
	if traffic:
		traffic.set_monster(mods.has("monster"))
	if car_visual:
		car_visual.set_paint(livery.get("color", paint))
		car_visual.car_number = livery.get("number", car_number)
		car_visual.set_wheel_scale(CarMods.MONSTER_WHEELS if mods.has("monster") else 1.0)
	hud.set_car_label(hyper, FanLevels.hypercar_unlocked(progress.fans), _car_name())

## The pause menu's MODIFIERS page: one switch per CarMods entry, locked ones name their fan level.
func _show_mods_page() -> void:
	var items := []
	for m in CarMods.LIST:
		items.append(["mod:" + m[0], _mod_text(m), not CarMods.unlocked(m[0], progress.fans)])
	items.append(["mods_back", "BACK"])
	hud.set_pause_page("MODIFIERS", items)

func _mod_text(m: Array) -> String:
	if not CarMods.unlocked(m[0], progress.fans):
		return "%s  ·  LEVEL %d" % [m[2], m[1]]
	return "%s  ·  %s" % [m[2], "ON" if progress.mods.get(m[0], false) else "OFF"]

func _toggle_mod(id: String) -> void:
	var i := -1
	for k in CarMods.LIST.size():
		if CarMods.LIST[k][0] == id:
			i = k
	if i < 0:
		return
	var m: Array = CarMods.LIST[i]
	if not CarMods.unlocked(id, progress.fans):
		hud.notify("%s LOCKED" % m[2], "Reach fan level %d: %s" % [m[1], FanLevels.title(m[1]).to_upper()], Color("#ff5a4a"))
		return
	if live and live.is_running():
		live.abandon()
		_live_cp_beacon()
		_recompute_route()
		hud.set_live("", "", Color.WHITE)
		hud.notify("EVENT ABANDONED", "Modifier changed", Color("#ff5a4a"))
	if progress.mods.get(id, false):
		progress.mods.erase(id)
	else:
		progress.mods[id] = true
	_apply_look()
	hud.set_pause_text(i, _mod_text(m))
	hud.notify(m[2], m[3] if progress.mods.has(id) else "Off", OpenWorldHud.GOLD)

## Dev menu: teleport to a named map spot, set the hour, park a car ahead.
func dev_teleport(spot_name: String) -> void:
	var sp: Array = map.spots.get(spot_name, [])
	if sp.size() >= 3:
		drive.place(Vector2(sp[0], sp[1]), float(sp[2]))
		drive.respawn()
		snap_camera()

func dev_set_hour(h: float) -> void:
	hour = h
	_apply_time()

func dev_spawn(kind: String) -> void:
	traffic.spawn_ahead(drive, kind)

## Fans earned outside the open world (a campaign stage's result): added, announced and saved.
func award_fans(n: int) -> void:
	_add_fans(n, "")
	_save()

## The GPS route runs to a point of interest (Enter on it in the big map): the waypoint machinery carries the
## route, the point keeps its own marker.
func _route_to_poi(p: Poi) -> void:
	if p == null:
		return
	wp_poi = p.id
	wp_pos = p.pos
	wp_on = true
	gps_waypoint = true
	_update_markers()
	_recompute_route()
	hud.toggle_map(false)
	hud.notify("ROUTE SET", p.name if p.state(progress) != Poi.State.UNKNOWN else "Undiscovered landmark", OpenWorldHud.PURPLE)

## Arrived at (or found) the point the route ran to: the route and the highlight go; the point's own banner has
## said everything there is to say.
func _clear_poi_route() -> void:
	wp_poi = ""
	wp_on = false
	if gps_waypoint:
		gps_waypoint = false
		_recompute_route()
	_update_markers()

## Drops the player's own waypoint (map click or cursor) and routes there.
func _set_waypoint(pos: Vector2) -> void:
	wp_poi = ""
	wp_pos = MapMarker.keep_inside(pos, map.play) # a click on the dimmed ground beyond the edge has no route
	wp_on = true
	gps_waypoint = true
	hud.cursor_on = false
	_update_markers()
	_recompute_route()
	if hud.map_open:
		hud.toggle_map(false)
	hud.notify("WAYPOINT SET", "Your own destination", OpenWorldHud.PURPLE)

func _off_route() -> bool:
	if route.size() < 2:
		return _has_target()
	var cp := Vector2(drive.car.x, drive.car.y)
	var best := INF
	for i in route.size() - 1:
		best = minf(best, Geometry2D.get_closest_point_to_segment(cp, route[i], route[i + 1]).distance_to(cp))
		if best < 30.0:
			return false
	return true

# ================================================================================================ frame

func _process(delta: float) -> void:
	if not active or not built:
		return
	if paused or hud.map_open:
		_update_camera(delta)
		if surface_fx:
			surface_fx.silence(car_visual)
		hud.update_drive(drive.speed_kmh(), _gear_shown(), drive.car.rpm, drive.model.spec.limiter, Vector2(drive.car.x, drive.car.y), drive.car.heading, delta)
		return
	nitro_on = false
	_read_input(delta)
	if live and live.holding(): # on the line until the lights go (handbrake: the auto box reverses on a held brake)
		throttle = 0.0
		brake = 0.0
		handbrake = 1.0
	var slow := mods.has("bullet") and (drive.airborne or _drift_t > 0.3)
	_time_rate = move_toward(_time_rate, CarMods.BULLET_RATE if slow else 1.0, delta * 3.0)
	accumulator += minf(delta, 0.1) * _time_rate
	var steps := 0
	while accumulator >= TICK and steps < 24:
		_prev_pos = Vector3(drive.car.x, drive.z, drive.car.y)
		_prev_heading = drive.car.heading
		drive.step(TICK, throttle, brake, steer, shift_up, shift_down, handbrake)
		shift_up = false
		shift_down = false
		if not _roads_closed():
			traffic.step(TICK, drive)
		train.step(TICK)
		accumulator -= TICK
		steps += 1
	if steps >= 24:
		accumulator = 0.0
	if drive.wants_respawn:
		if live and live.is_running():
			live.abandon()
			_live_cp_beacon()
			_recompute_route()
			hud.set_live("", "", Color.WHITE)
			hud.notify("EVENT ABANDONED", "Car respawned", Color("#ff5a4a"))
		hud.notify("BACK ON THE ROAD", "The Seicento doesn't swim", Color("#4aa3ff"))
		drive.respawn()
		snap_camera()
	builder.update_crossings(delta)
	builder.update_signals()
	hour = fmod(hour + delta * DAY_RATE, 24.0)
	_apply_time()
	_sync_car(delta)
	surface_fx.update(drive, car_visual, delta)
	_update_camera(delta)
	_update_skills(delta * _time_rate)
	_update_nitro(delta * _time_rate) # simulation time, so bullet time doesn't farm drift points
	_check_events()
	_update_live(delta)
	_check_traps()
	_disc_t -= delta
	if _disc_t <= 0.0:
		_disc_t = 0.5
		_check_discovery()
	_area_t -= delta
	if _area_t <= 0.0:
		_area_t = 1.5
		_check_area()
	_lamp_t -= delta
	if _lamp_t <= 0.0:
		_lamp_t = 0.25
		_place_lamp_lights()
	_route_t -= delta
	if _route_t <= 0.0:
		_route_t = 0.5
		_check_waypoint_reached()
		if _has_target() and _off_route():
			_recompute_route()
		else:
			_update_route_mesh()
	_save_t -= delta
	if _save_t <= 0.0:
		_save_t = 15.0
		_save()
	hud.update_drive(drive.speed_kmh(), _gear_shown(), drive.car.rpm, drive.model.spec.limiter, Vector2(drive.car.x, drive.car.y), drive.car.heading, delta)
	hud.set_stats(progress.fans, progress.roads.size(), map.road_pts.size(), hour)
	if audio:
		audio.update_car(drive.car, true, null)

func _gear_shown() -> int:
	return -1 if drive.car.rev else drive.car.gear

func _sync_car(delta: float) -> void:
	var a := clampf(accumulator / TICK, 0.0, 1.0)
	var p := _prev_pos.lerp(Vector3(drive.car.x, drive.z, drive.car.y), a)
	var h := _prev_heading + wrapf(drive.car.heading - _prev_heading, -PI, PI) * a
	car_visual.position = p
	car_visual.basis = drive.tilt * Basis(Vector3.UP, -h - PI / 2.0)
	if mods.has("tiny"):
		car_visual.basis = car_visual.basis * Basis.from_scale(Vector3.ONE * CarMods.TINY_SCALE)
	car_visual.sync(drive.car, delta, 0.0, night, false)
	if mods.has("rainbow"):
		var before := int(_rainbow_t * 12.0)
		_rainbow_t += delta
		if int(_rainbow_t * 12.0) != before:
			car_visual.set_paint(Color.from_hsv(fmod(_rainbow_t * 0.12, 1.0), 0.85, 0.92))
	elif _rainbow_t > 0.0:
		_rainbow_t = 0.0
		_apply_look()

## The chase camera's spot with walls, fences and buildings between it and the car taken out (ChaseCam).
func _clear_of_walls(p: Vector3, free: Vector3, delta: float, snap := false) -> Vector3:
	if _chase_cam == null:
		_chase_cam = ChaseCam.new()
	return _chase_cam.update(map, p + Vector3.UP * 1.0, free, delta, snap)

func _update_camera(delta: float) -> void:
	if drive == null:
		return
	var car := drive.car
	var p := car_visual.position
	var f := Vector3(cos(car.heading), 0.0, sin(car.heading))
	var v := Vector2(car.vx, car.vy)
	# the chase camera swings towards the direction of travel when the car slides
	var want_dir := Vector2(f.x, f.z)
	if v.length() > 4.0 and car.speed > 0.0:
		want_dir = want_dir.lerp(v.normalized(), 0.45).normalized()
	# turned through the angle, not lerped: a lerp between near-opposite directions passes through zero, and the
	# normalised zero put the camera straight over the car looking down (a respawn facing the other way)
	cam_vel_dir = Vector2.from_angle(lerp_angle(cam_vel_dir.angle(), want_dir.angle(), 1.0 - exp(-delta * 4.0)))
	var d3 := Vector3(cam_vel_dir.x, 0.0, cam_vel_dir.y)
	var kmh := absf(car.speed) * 3.6
	look.update(delta, not paused and not hud.map_open)
	# swung round the car, the chase camera looks along the view and, more and more, at the car itself
	var view := look.turn(d3)
	var at_car := smoothstep(0.0, 1.2, absf(look.yaw)) * 0.7
	match cam_mode:
		1:
			var target := p - d3 * 10.5 + Vector3.UP * 3.6
			cam_pos = cam_pos.lerp(target, 1.0 - exp(-delta * 5.0))
			camera.position = _clear_of_walls(p, look.orbit(p, cam_pos), delta, look.cut)
			camera.look_at((p + view * 5.0 * cos(look.pitch) + Vector3.UP * 1.0).lerp(p + Vector3.UP * 0.8, at_car), Vector3.UP)
			camera.fov = 66.0 + kmh * 0.06
		2:
			camera.global_transform = car_visual.global_transform * Transform3D(Basis(), Vector3(0.0, 1.22, -0.35))
			camera.rotate_object_local(Vector3.RIGHT, deg_to_rad(-2.0))
			if look.active(): # the driver turns their head
				camera.rotate_object_local(Vector3.UP, -look.yaw)
				camera.rotate_object_local(Vector3.RIGHT, -look.pitch)
			camera.fov = 78.0 + kmh * 0.05
		_:
			var back := 6.0 + kmh * 0.012
			var target := p - d3 * back + Vector3.UP * (2.15 + kmh * 0.004)
			cam_pos = cam_pos.lerp(target, 1.0 - exp(-delta * 7.0))
			# keep it out of the walls and buildings (shortened or swung aside, ChaseCam) and above the ground
			var spot := _clear_of_walls(p, look.orbit(p, cam_pos), delta, look.cut)
			spot.y = maxf(spot.y, map.ground(spot.x, spot.z) + 0.8)
			camera.position = spot
			camera.look_at((p + view * 3.5 * cos(look.pitch) + Vector3.UP * 1.05).lerp(p + Vector3.UP * 0.8, at_car), Vector3.UP)
			camera.fov = lerpf(camera.fov, 70.0 + clampf(kmh, 0.0, 140.0) * 0.1, 1.0 - exp(-delta * 3.0))

# ================================================================================================ input

func _read_input(dt: float) -> void:
	var pads := Input.get_connected_joypads()
	if gamepad_device >= 0 and pads.has(gamepad_device):
		var raw := Input.get_joy_axis(gamepad_device, JOY_AXIS_LEFT_X)
		var dead := maxf(0.0, (absf(raw) - 0.1) / 0.9)
		var st_pad := signf(raw) * dead * dead
		var thr_pad := clampf(Input.get_joy_axis(gamepad_device, JOY_AXIS_TRIGGER_RIGHT), 0.0, 1.0)
		var brk_pad := clampf(Input.get_joy_axis(gamepad_device, JOY_AXIS_TRIGGER_LEFT), 0.0, 1.0)
		var hb_pad := Input.is_joy_button_pressed(gamepad_device, JOY_BUTTON_A)
		nitro_on = Input.is_joy_button_pressed(gamepad_device, JOY_BUTTON_LEFT_STICK)
		if absf(st_pad) > 0.02 or thr_pad > 0.02 or brk_pad > 0.02 or hb_pad:
			steer = st_pad
			throttle = thr_pad
			brake = brk_pad
			handbrake = 1.0 if hb_pad else 0.0
			return
	var up := Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)
	var down := Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)
	var left := Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)
	var right := Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)
	handbrake = 1.0 if Input.is_physical_key_pressed(KEY_SPACE) else 0.0
	nitro_on = nitro_on or Input.is_physical_key_pressed(KEY_SHIFT)
	var st := (1.0 if right else 0.0) - (1.0 if left else 0.0)
	var back := st == 0.0 or signf(st) != signf(steer)
	var kmh := drive.speed_kmh()
	var rate := 4.4 if kmh < 40.0 else lerpf(4.4, 2.6, clampf((kmh - 40.0) / 80.0, 0.0, 1.0))
	steer = move_toward(steer, st, (8.0 if back else rate) * dt)
	throttle = move_toward(throttle, 1.0 if up else 0.0, 6.0 * dt)
	brake = move_toward(brake, 1.0 if down else 0.0, 8.0 * dt)

func _input(event: InputEvent) -> void:
	if not active or not built:
		return
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if gamepad_device < 0:
			gamepad_device = event.device
	var act := _action_of(event)
	if act == "":
		return
	get_viewport().set_input_as_handled()
	if paused:
		match act:
			"back", "pause":
				if hud.pause_title.text == "MODIFIERS":
					_pause_action("mods_back")
				else:
					_set_paused(false)
			"up":
				hud.move_pause(-1)
			"down":
				hud.move_pause(1)
			"accept":
				hud.press_pause()
		return
	if hud.map_open:
		match act:
			"back", "map", "pause":
				if hud.cursor_on and act == "back":
					hud.toggle_cursor(false)
				else:
					hud.cursor_on = false
					hud.toggle_map(false)
			"left", "up", "right", "down":
				if hud.cursor_on:
					hud.move_cursor({"left": Vector2.LEFT, "right": Vector2.RIGHT, "up": Vector2.UP, "down": Vector2.DOWN}[act])
				else:
					var n := maxi(hud.markers.size(), 1)
					hud.map_sel = posmod(hud.map_sel + (-1 if act in ["left", "up"] else 1), n)
					hud.big_overlay.queue_redraw()
			"cursor":
				hud.toggle_cursor(not hud.cursor_on)
			"accept":
				if hud.cursor_on:
					_set_waypoint(hud.cursor)
				elif hud.map_sel >= 0 and hud.map_sel < hud.markers.size() and hud.markers[hud.map_sel].get("kind", "") == "poi":
					_route_to_poi(Poi.find(pois, String(hud.markers[hud.map_sel].id)))
				elif hud.map_sel >= events.size():
					gps_waypoint = true
					_recompute_route()
					hud.toggle_map(false)
					hud.notify("ROUTE SET", "Your waypoint", OpenWorldHud.PURPLE)
				else:
					gps_waypoint = false
					gps_target = hud.map_sel
					_recompute_route()
					hud.toggle_map(false)
					hud.notify("ROUTE SET", String(events[gps_target].title), OpenWorldHud.PURPLE)
		return
	match act:
		"pause", "back":
			_set_paused(true)
		"accept":
			_start_active_event()
		"map":
			hud.map_sel = maxi(gps_target, 0)
			hud.toggle_map(true)
		"gps":
			if wp_poi != "":
				wp_poi = ""
				wp_on = false
				_update_markers()
			gps_waypoint = false
			gps_target = _next_open_event()
			_recompute_route()
			if gps_target >= 0:
				hud.notify("ROUTE SET", String(events[gps_target].title), OpenWorldHud.PURPLE)
		"camera":
			cam_mode = (cam_mode + 1) % 3
		"reset":
			drive.respawn()
			snap_camera()
			hud.notify("BACK ON THE ROAD", "", Color("#4aa3ff"))
		"shift_up":
			shift_up = true
		"shift_down":
			shift_down = true
		"time":
			hour = fmod(hour + 3.0, 24.0)
			_apply_time()

## The action a key or pad press stands for, or "" (only presses, not releases or repeats).
func _action_of(event: InputEvent) -> String:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE: return "back"
			KEY_ENTER, KEY_KP_ENTER: return "accept"
			KEY_E: return "shift_up" # as in a race (E / Q shift a manual gearbox)
			KEY_M, KEY_TAB: return "map"
			KEY_G: return "gps"
			KEY_F: return "cursor" if hud.map_open else ""
			KEY_C: return "camera"
			KEY_R, KEY_BACKSPACE: return "reset"
			KEY_T: return "time"
			KEY_Q: return "shift_down"
			KEY_PAGEUP: return "shift_up"
			KEY_PAGEDOWN: return "shift_down"
		if paused or hud.map_open:
			match event.physical_keycode:
				KEY_UP, KEY_W: return "up"
				KEY_DOWN, KEY_S: return "down"
				KEY_LEFT, KEY_A: return "left"
				KEY_RIGHT, KEY_D: return "right"
	elif event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_START: return "pause"
			JOY_BUTTON_B: return "back" if (paused or hud.map_open) else "accept" # A is the handbrake while driving
			JOY_BUTTON_A: return "accept" if (paused or hud.map_open) else ""
			JOY_BUTTON_BACK: return "map"
			JOY_BUTTON_Y: return "camera"
			JOY_BUTTON_X: return "cursor" if hud.map_open else "reset"
			JOY_BUTTON_RIGHT_SHOULDER: return "shift_up"
			JOY_BUTTON_LEFT_SHOULDER: return "shift_down"
			JOY_BUTTON_DPAD_UP: return "up" if (paused or hud.map_open) else "gps"
			JOY_BUTTON_DPAD_DOWN: return "down" if (paused or hud.map_open) else ""
			JOY_BUTTON_DPAD_LEFT: return "left" if hud.map_open else ""
			JOY_BUTTON_DPAD_RIGHT: return "right" if hud.map_open else ""
	return ""

func _set_paused(on: bool) -> void:
	paused = on
	hud.show_pause(on)
	if on and live and live.is_running():
		hud.set_pause_page("PAUSED", OpenWorldHud.PAUSE_ITEMS.slice(0, 1) + [["abandon_live", "ABANDON EVENT"]] + OpenWorldHud.PAUSE_ITEMS.slice(1))
	if on:
		hud.set_car_label(progress.car_class == 1, FanLevels.hypercar_unlocked(progress.fans), _car_name())
	if on and audio:
		audio.update_car(null, false)

func _pause_action(action: String) -> void:
	if action != "reset_campaign":
		_reset_armed = false
	if action.begins_with("mod:"):
		_toggle_mod(action.substr(4))
		return
	match action:
		"abandon_live":
			if live and live.is_running():
				live.abandon()
				_live_cp_beacon()
				_recompute_route()
				hud.set_live("", "", Color.WHITE)
				hud.notify("EVENT ABANDONED", "", Color("#ff5a4a"))
			_set_paused(false)
		"reset_campaign":
			if not _reset_armed:
				_reset_armed = true
				hud.notify("RESET CAMPAIGN?", "Select it again to wipe all stage progress", Color("#ff5a4a"))
				return
			_reset_armed = false
			Campaign.reset_progress()
			_refresh_events()
			gps_target = _next_open_event()
			_recompute_route()
			_set_paused(false)
			hud.notify("CAMPAIGN RESET", "Back to stage 1", OpenWorldHud.PURPLE)
		"resume":
			_set_paused(false)
		"car":
			if live and live.is_running():
				live.abandon()
				_live_cp_beacon()
				_recompute_route()
				hud.set_live("", "", Color.WHITE)
				hud.notify("EVENT ABANDONED", "Car changed", Color("#ff5a4a"))
			_toggle_car()
		"mods":
			_show_mods_page()
		"mods_back":
			hud.set_pause_page("PAUSED", OpenWorldHud.PAUSE_ITEMS.slice(0, 1) + ([["abandon_live", "ABANDON EVENT"]] if live and live.is_running() else []) + OpenWorldHud.PAUSE_ITEMS.slice(1))
			hud.set_car_label(progress.car_class == 1, FanLevels.hypercar_unlocked(progress.fans), _car_name())
		"map":
			_set_paused(false)
			hud.map_sel = maxi(gps_target, 0)
			hud.toggle_map(true)
		"stages":
			_set_paused(false)
			suspend()
			leave_requested.emit("stages")
		"reset":
			_set_paused(false)
			if live and live.is_running():
				live.abandon()
				_live_cp_beacon()
				_recompute_route()
				hud.set_live("", "", Color.WHITE)
				hud.notify("EVENT ABANDONED", "Car reset", Color("#ff5a4a"))
			drive.respawn()
			snap_camera()
		"time":
			hour = fmod(hour + 3.0, 24.0)
			_apply_time()
		"menu":
			_set_paused(false)
			suspend()
			leave_requested.emit("menu")

func _save() -> void:
	if progress == null or drive == null:
		return
	progress.pos = Vector2(drive.car.x, drive.car.y)
	progress.heading = drive.car.heading
	progress.has_pos = true
	progress.hour = hour
	progress.odometer += drive.odometer
	drive.odometer = 0.0
	progress.save()
