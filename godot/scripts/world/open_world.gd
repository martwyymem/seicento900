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
	"fiat": "exit_tychy", "tokyo": "festival", "goliath": "festival", "monza": "exit_tychy", "nordschleife": "station",
	"lemans": "festival"} ## a stage's own "note" says where a shared spot takes it (Campaign.STAGES)
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
const CLOSURE_CLEAR := 14.0 ## m a spawn keeps back from a road-end barrier at the play edge
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
var aids := {} ## FreeCar.aids: the player's DifficultyProfile aids over `assists`
var no_damage := false ## FreeCar.no_damage: the profile's damage is off
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
var weather_fx: WeatherParticles ## falling rain, splashes, mist, snow, hail and fog wisps round the camera
var golden := 0.0 ## 0..1, how deep in the golden hour the sun is (low, warm, long shadows, sunlit haze)
var _volumetric := false ## the preset affords volumetric fog: sun shafts in the golden hour (Ultra)
var headlights: Array[SpotLight3D] = []
var reflections: CarReflections ## the street mirrored in the car's paint (presets with car_reflections)
var lamp_lights: Array[OmniLight3D] = []
var _lamp_reach := 200.0 ## m: the pooled lamp lights have faded out by here (_place_lamp_lights)
var route_mesh: MeshInstance3D
var route_mat: StandardMaterial3D
var hud: OpenWorldHud
var story: StoryDirector ## the campaign's story: dialogue card, phone messages, journal (scripts/world/story_director.gd)

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
var cam_off := Vector3(0.0, 1.75, 5.0) ## the chase camera's eased offset from the car (cam_pos = car + this)
var cam_vel_dir := Vector2.RIGHT
## Free look (right stick, B / R3 to look back, right-mouse drag); the chase cameras orbit the car with it
var look := CameraLook.new()
var _chase_cam: ChaseCam
var hour := 18.5
var night := 0.0
## 0..1 how wet the streets are (town_road.gdshader puddles, sheen, rain rings). Free roam is dry: a campaign mission
## sets its weather for the run (set_weather); after dark the streets get a little dew of their own (NIGHT_DAMP)
var wet := 0.0
var weather := "dry" ## the weather mode on the map (a mission's while it runs, MapMissions.weather_state)
var rain := 0.0 ## 0..1 falling rain and the road shaders' rain rings
var snow := 0.0 ## 0..1 falling snow and snow on the streets (road shaders)
var hail := 0.0 ## 0..1 falling hail
var fog := 0.0 ## 0..1 fog: the haze thickens to a race's fog (FOG_DENSITY), the sky greys, the sun dims
var wx: WorldWeather ## the free-roam weather cycle (a pure function of the saved seed and the clock); null until the world is built
var _wx_hour := 0.0 ## the clock's hour the cycle was last brought up to
var _sky_hour := -1.0 ## hour and overcast last pushed to sky_mat (gates Sky.PROCESS_MODE_INCREMENTAL updates)
var _sky_overcast := -1.0
var _ref_hour := -1.0 ## hour, overcast, night, snow and fog last seen by CarReflections (refreshes the probe on weather/time changes)
var _ref_overcast := -1.0
var _ref_night := -1.0
var _ref_snow := -1.0
var _ref_fog := -1.0
const FOG_DENSITY := 0.02 ## a race's fog (race_world.gd)
const NIGHT_DAMP := 0.3
const LAMP_POOL_GLOW := 0.7 ## emission at the middle of a lamp's pool on the ground (reads on the dark tarmac)

var events: Array = [] ## [{stage, spot, pos: Vector2, heading, title, ...}]; a live event has "live": its id
var live: LiveEvents ## the generated events round the car (scripts/world/live_events.gd)
var event_dressing: EventDressing ## the driven event's start gantry and spectators, only while it runs (scripts/world/event_dressing.gd)
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
var _saved_hour := -1.0 ## the clock before a mission set its own hour (put back when the run ends), -1 none
var _saved_weather := {} ## the weather before a mission set its own (weather_state(), put back when the run ends), {} none
var _result := {} ## the results card after an event: {pos (where the car finished), mission (index) or live (event)}
var _gate_nodes: Array[Node3D] = [] ## the posts of the next checkpoint gate and, dimmer, the one after
const RESULT_LEAVE := 30.0 ## m the car drives on from the finish before the results card goes (CONTINUE)
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
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if RenderingServer.get_current_rendering_method() != "gl_compatibility" else Viewport.SCREEN_SPACE_AA_DISABLED # Forward+ / Mobile only
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
	_add_view_fx()
	hud.pause_action.connect(_pause_action)
	hud.waypoint_picked.connect(_set_waypoint)
	story = StoryDirector.attach(self)
	hud.map_accept.connect(_map_accept)
	hud.nav.filters_changed.connect(_map_filters_changed)
	hide()

## Rear-view mirror and lens flare (scripts/ui/rear_mirror.gd, lens_flare.gd).
func _add_view_fx() -> void:
	var mirror := RearMirror.new()
	add_child(mirror)
	# own_world_3d: viewport.world_3d itself is null, so the mirror rendered the race scene's world
	mirror.setup(viewport.find_world_3d(), func() -> Node3D:
		# (not over the full-screen map either: it covered the map's title and hint row)
		return car_visual if visible and not paused and not (hud and hud.map_open) and is_instance_valid(car_visual) else null)

static func available() -> bool:
	return FileAccess.file_exists("res://data/world/%s.json" % MAP_KEY)

## Shows the world, building it first if needed. spawn: a spot name, a stage index (int) to come back at that
## stage's beacon, or "" for where the car was left.
func open(spawn = "", opts := {}) -> void:
	gearbox = opts.get("gearbox", gearbox)
	assists = opts.get("assists", assists)
	aids = opts.get("aids", aids)
	no_damage = bool(opts.get("no_damage", no_damage))
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
	hud.set_hints(bool(opts.get("hints", false)))
	show()
	active = true
	paused = false
	hud.show_pause(false)
	_fit_view()
	if not built:
		# (the 3D view stays off behind the loading cover: drawing an empty world there only took time from the build)
		await _build_world()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var t := Time.get_ticks_msec()
	apply_graphics(int(opts.get("quality", quality)), bool(opts.get("ssao", true)), int(opts.get("reflections", -1)))
	if drive:
		drive.gearbox = gearbox
		drive.assists = assists
		drive.aids = aids
		drive.no_damage = no_damage
	if surface_fx:
		surface_fx.reset_car_bus()
	_refresh_events()
	_t_log("graphics and events", t)
	t = Time.get_ticks_msec()
	_spawn(spawn)
	_t_log("spawn", t)
	t = Time.get_ticks_msec()
	_live_open()
	_t_log("live-event board", t)
	t = Time.get_ticks_msec()
	if not CarCatalog.unlocked(CarCatalog.key_at(progress.car_class), progress.fans):
		progress.car_class = 0
	if _fitted_class != progress.car_class:
		_fit_car()
	else:
		_apply_look()
	_t_log("fit car", t)
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
		_end_run()
	_result = {}
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if audio:
		audio.update_car(null, false)
	if surface_fx:
		surface_fx.stop_all()
		surface_fx.silence(car_visual)
	if builder and builder.festival:
		builder.festival.stop_all()
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
	hud.nav.set_hidden(progress.map_hidden)
	var ckey := CarCatalog.key_at(progress.car_class) if CarCatalog.unlocked(CarCatalog.key_at(progress.car_class), progress.fans) else "stock"
	hud.open_loading(CarCatalog.spec(ckey), CarCatalog.display_name(ckey) if ckey != "stock" else "Fiat Seicento", ckey)
	hud.show_loading("Reading the map of Brzeszcze", 0.02)
	hour = progress.hour
	world = Node3D.new()
	world.name = "Brzeszcze"
	var map_tex: Texture2D = null
	if by_frame:
		# the map and the town build on a worker thread into a world that is not in the tree yet, so this thread
		# keeps drawing the cover (its spinner never stalls); the world joins the viewport when it is done. The work
		# starts at once: waiting for the cover's first frame first only added idle time.
		_build_status = ["Reading the map of Brzeszcze", 0.02]
		var task := WorkerThreadPool.add_task(_build_town_threaded, true, "Open world build")
		var fps_was := Engine.max_fps
		Engine.max_fps = 30 # the cover needs few frames; leave the cores to the build
		while not WorkerThreadPool.is_task_completed(task):
			hud.show_loading(String(_build_status[0]), float(_build_status[1]))
			# every RenderingServer call of the worker that returns something (a model's or a texture's load, a mesh
			# read back) waits until this thread flushes the server's queue, which a frame does only once: flushing it
			# here for most of each frame let the build run three times faster (windowed at 30 fps 4.9 s -> 1.4 s)
			var until := Time.get_ticks_usec() + BUILD_PUMP_USEC
			while Time.get_ticks_usec() < until and not WorkerThreadPool.is_task_completed(task):
				RenderingServer.force_sync()
				OS.delay_usec(200)
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
	# the rest runs here, in one go: its pieces take about 20 ms together (a frame for each only added idle time)
	hud.show_loading("Starting the engine", 0.95)
	var t := Time.get_ticks_msec()
	viewport.add_child(world)
	_t_log("add world", t)
	t = Time.get_ticks_msec()
	_build_environment()
	_apply_vegetation_quality()
	_t_log("environment", t)
	t = Time.get_ticks_msec()
	hud.setup(map, map_tex if map_tex else load("res://data/world/%s_map.png" % MAP_KEY) as Texture2D)
	_t_log("hud", t)
	t = Time.get_ticks_msec()
	drive = FreeCar.new(map)
	_start_weather()
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

const BUILD_PUMP_USEC := 22000 ## of each cover frame spent serving the build's RenderingServer calls (the rest draws it)
var _build_status: Array = ["", 0.0] ## [what is building, fraction] the worker reports to the cover
var _build_map_tex: Texture2D

## Reads the map and runs every TownBuilder step into `world` (not yet in the tree, so this may run on a worker
## thread). Nothing here may touch the scene tree; the steps never hand frames back here (frame_budget_usec 0).
func _build_town_threaded() -> void:
	# textures the steps load one after another: read on other threads meanwhile (load() then takes them)
	var prefetch: Array[String] = []
	for path in ["res://data/world/%s_map.png" % MAP_KEY, "res://data/world/%s_land.png" % MAP_KEY, SurfaceTextures.MICRO, SurfaceTextures.MACRO]:
		if ResourceLoader.exists(path) and not ResourceLoader.has_cached(path) and ResourceLoader.load_threaded_request(path, "", true) == OK:
			prefetch.append(path)
	var t := Time.get_ticks_msec()
	map = TownMap.load_map(MAP_KEY, TownBuilder.MESH_CACHE_DIR) # warm starts read a snapshot of the indexed map
	if map == null:
		return
	_t_log("map (TownMap.load_map)", t)
	t = Time.get_ticks_msec()
	builder = TownBuilder.new(map, world)
	_t_log("TownBuilder.new (models)", t)
	builder.mesh_cache_dir = TownBuilder.MESH_CACHE_DIR # warm starts load the slow steps' meshes from disk
	builder.start_ahead() # a cold start builds the terrain, water, buildings and trees alongside the streets
	var steps: Array = builder.steps()
	for i in steps.size():
		_build_status = ["Building %s" % String(steps[i][0]).to_lower(), 0.05 + 0.85 * float(i) / steps.size()]
		var t0 := Time.get_ticks_msec()
		(steps[i][1] as Callable).call()
		if OS.get_environment("OW_BUILD_TIMES") != "":
			print("built %s in %d ms" % [steps[i][0], Time.get_ticks_msec() - t0])
	_build_status = ["Starting the engine", 0.95]
	t = Time.get_ticks_msec()
	builder.wait_for_stores()
	_t_log("mesh cache writes", t)
	t = Time.get_ticks_msec()
	_build_map_tex = load("res://data/world/%s_map.png" % MAP_KEY) as Texture2D
	for path in prefetch:
		ResourceLoader.load_threaded_get(path) # (done by now: this only lets go of the request)
	_t_log("map texture", t)
	if OS.get_environment("OW_BUILD_TIMES") != "":
		print("mesh cache: ", builder.cache_log)

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
		env.ssr_enabled = (int(p.reflections) if reflections_mode < 0 else reflections_mode) > 0 and RenderingServer.get_current_rendering_method() != "gl_compatibility" # SSR is Forward+ only
		env.ssil_enabled = bool(p.get("ssil", false))
	if reflections:
		reflections.visible = bool(p.get("car_reflections", false))
	_volumetric = bool(p.get("volumetric_fog", false))
	if car_visual:
		car_visual.fx_quality = quality
	if weather_fx:
		weather_fx.set_quality(quality)
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
	# REALTIME would redraw all six radiance faces and their mip chain every frame because the shader reads TIME;
	# INCREMENTAL refreshes them when the sky's parameters change (gated in _apply_time), and the visible sky still animates
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.7 # less blue on the white walls
	env.ambient_light_color = Color(0.82, 0.78, 0.72)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	SceneMood.base(env)
	viewport.add_child(SpeedBlur.new()) # inside the 3D view, so it blurs the picture and not the HUD
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
	world.add_child(camera)
	camera.fov = HudLayout.camera_fov_for(camera, 72.0)
	camera.make_current()
	weather_fx = WeatherParticles.new(world, quality)

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
	var overcast := WeatherParticles.overcast_amount(wet, rain, snow, hail)
	# the golden hour: from about 25 degrees down the sun turns gold, deepest a few degrees over the horizon
	var elev_deg := rad_to_deg(elev)
	golden = (1.0 - smoothstep(4.0, 25.0, elev_deg)) * smoothstep(-3.0, 1.5, elev_deg) * (1.0 - overcast)
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
	sun.light_energy = lerpf(0.2, 2.0, day) * lerpf(1.0, 1.05, golden) * (1.0 + 0.12 * midday) * (1.0 - overcast * 0.62)
	sun.shadow_opacity = lerpf(0.6, 1.0, day) * (1.0 - overcast * 0.45)
	var sky_dirty := _sky_hour < 0.0 or absf(hour - _sky_hour) >= 0.005 \
		or absf(overcast - _sky_overcast) >= 0.005 or (overcast == 0.0) != (_sky_overcast == 0.0)
	if sky_dirty:
		_sky_hour = hour
		_sky_overcast = overcast
		sky_mat.set_shader_parameter("sun_dir", dir)
		sky_mat.set_shader_parameter("moon_dir", Vector3(-dir.x, 0.6, -dir.z).normalized())
		sky_mat.set_shader_parameter("night", night)
		sky_mat.set_shader_parameter("overcast", overcast)
		sky_mat.set_shader_parameter("star_amount", clampf(night * 1.4 - 0.3, 0.0, 1.0) * 0.12) # under the night exposure and glow
		# a deep blue night sky (not black), a richer blue overhead by day, greyed under rain or snow (as race_world)
		# (the golden sky stays a clean blue overhead: a pink horizon blended into it went lavender through ACES)
		var top := Color(0.035, 0.065, 0.2).lerp(Color(0.13, 0.33, 0.72).lerp(Color(0.16, 0.4, 0.7), golden), day) \
			.lerp(WORLD.SKY_TOP_OVERCAST, overcast * 0.72 * day)
		var horizon := Color(0.06, 0.1, 0.22).lerp(Color(0.6, 0.73, 0.88).lerp(Color(0.98, 0.78, 0.5), golden * 0.8), day) \
			.lerp(WORLD.HORIZON_OVERCAST, overcast * 0.7 * day)
		sky_mat.set_shader_parameter("top_color", top)
		sky_mat.set_shader_parameter("horizon_color", horizon)
		sky_mat.set_shader_parameter("glow_color", Color(1.0, 0.48, 0.2))
		sky_mat.set_shader_parameter("glow_amount", golden)
		sky_mat.set_shader_parameter("sun_color", day_col.lerp(gold_col, golden))
		sky_mat.set_shader_parameter("sky_energy", lerpf(0.8, 1.0, day))
		# the town's sodium glow low on the night horizon, lighting the cloud bellies from below
		sky_mat.set_shader_parameter("city_glow", Color(0.5, 0.3, 0.16) * 0.22 * night * (1.0 - overcast * 0.5))
		sky_mat.set_shader_parameter("cloud_lit", Color(0.13, 0.15, 0.24).lerp(Color(1, 1, 1).lerp(Color(1.0, 0.68, 0.46), golden), day) \
			.lerp(WORLD.HORIZON_OVERCAST, overcast * 0.5 * day))
		sky_mat.set_shader_parameter("cloud_shade", Color(0.05, 0.06, 0.11).lerp(Color(0.55, 0.6, 0.7).lerp(Color(0.62, 0.5, 0.6), golden), day) \
			.lerp(WORLD.SKY_TOP_OVERCAST.darkened(0.2), overcast * day))
		sky_mat.set_shader_parameter("halo_amount", (0.15 * day + 0.65 * golden) * (1.0 - overcast))
	if reflections and (_ref_hour < 0.0 or absf(overcast - _ref_overcast) >= 0.08 \
			or absf(night - _ref_night) >= 0.08 or absf(hour - _ref_hour) >= 0.25 \
			or absf(snow - _ref_snow) >= 0.08 or absf(fog - _ref_fog) >= 0.08 \
			or (overcast == 0.0) != (_ref_overcast == 0.0)):
		_ref_hour = hour
		_ref_overcast = overcast
		_ref_night = night
		_ref_snow = snow
		_ref_fog = fog
		reflections.refresh()
	# sunlit haze: thicker and gold towards the sun, so the distance glows behind the trees; greyer and thicker in rain/snow
	env.fog_light_color = Color(0.03, 0.05, 0.11).lerp(Color(0.66, 0.75, 0.87).lerp(Color(0.97, 0.64, 0.4), golden), day) \
		.lerp(WORLD.FOG_RAIN * lerpf(0.04, 1.0, day), overcast * 0.6)
	env.fog_sun_scatter = 0.6 * golden
	# plus a daytime haze, so the far blocks and trees fall back into a paler blue and the near ones stand out
	env.fog_density = 0.00028 * lerpf(1.0, 2.4, golden) * lerpf(1.0, 1.6, night) + 0.00045 * midday \
		+ 0.00045 * overcast + 0.0024 * maxf(rain, maxf(snow * 0.75, hail))
	env.fog_aerial_perspective = lerpf(0.6, 0.85, midday) * (1.0 - overcast * 0.6)
	# a mission's fog: the haze thickens to a race's fog, grey and lit by the dimmed sun, and hides the sky's horizon
	env.fog_sky_affect = 0.85 * fog
	if fog > 0.0:
		env.fog_density = lerpf(env.fog_density, FOG_DENSITY, fog)
		# fog has its own grey, not the sky's: aerial perspective would tint it with the clear sky behind (a blue haze
		# under a blue sky, not fog)
		env.fog_aerial_perspective = lerpf(env.fog_aerial_perspective, 0.0, fog)
		env.fog_light_color = env.fog_light_color.lerp(Color(0.6, 0.62, 0.64) * lerpf(0.05, 1.0, day), 0.75 * fog)
		env.fog_sun_scatter *= 1.0 - fog
		sun.light_energy *= lerpf(1.0, 0.55, fog)
		sun.shadow_opacity *= lerpf(1.0, 0.6, fog)
	# the fill: a cool sky blue by day (the shadow colour), lavender at the golden hour, neutral grey under cloud, a dim moonlit blue at night
	env.ambient_light_energy = lerpf(0.95, 0.48, day) * lerpf(1.0, 0.75, golden) * (1.0 - 0.25 * midday) * (1.0 - overcast * 0.2)
	env.ambient_light_color = Color(0.34, 0.42, 0.72).lerp(Color(0.78, 0.8, 0.86).lerp(Color(0.66, 0.66, 0.88), golden * 0.7), day) \
		.lerp(Color(0.66, 0.76, 0.95), 0.5 * midday).lerp(WORLD.FILL_OVERCAST, overcast * day)
	env.ambient_light_sky_contribution = lerpf(0.25, 0.6, day) * lerpf(1.0, 0.6, golden) # the pink sky would wash the shadows out
	SceneMood.by_hour(env, day, golden, night, 1.06) # ACES already deepens the colour
	env.glow_bloom += 0.03 * night * clampf(rain * 1.5, 0.0, 1.0)
	if weather_fx:
		weather_fx.update(rain, snow, hail, fog, weather == "fog", quality)
		weather_fx.place(camera)
	# contact shadows also darken sunlit ground a little by day: under the car, at wall feet, kerbs and fences
	env.ssao_light_affect = lerpf(0.12, 0.3, midday)
	env.ssao_intensity = lerpf(2.2, 2.8, midday)
	# Ultra: sun shafts through the trees and between the houses (volumetric fog lit by the low sun)
	var shafts := _volumetric and golden > 0.05 and day > 0.2 and fog < 0.1
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
		for m in builder.wet_materials:
			var street := m.shader == TOWN_ROAD_SHADER or m.shader == PAVEMENT_SHADER # night dew is on the streets, not the walls
			m.set_shader_parameter("wet", damp if street else wet)
			m.set_shader_parameter("rain", rain)
			m.set_shader_parameter("snow", snow)
	# the beams with the lamp lenses (race_car_visual.gd set_lamps follows the same level)
	var beams: float = CAR_VISUAL.headlamp_level(night)
	for h in headlights: # (a smashed headlamp throws no beam)
		h.light_energy = HEADLIGHT_ENERGY * beams * car_visual.lamp_working(h.position.x < 0.0, true)
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
		s.spot_angle = 16.0 # the beam's top edge 8 degrees up: on a wall 4 m ahead it stops under the roof
		s.spot_angle_attenuation = 0.75 # most of the light in the middle of the beam, a soft edge
		s.spot_attenuation = 1.3 # nearer the inverse square than the old 0.8: 20 m gets a third of 8 m's light
		s.light_specular = 0.15 # no glare off wet tarmac and glazing
		s.light_color = Color(1.0, 0.95, 0.82)
		s.shadow_enabled = false
		s.visible = false
		s.rotation = Vector3(deg_to_rad(-8.0), 0.0, 0.0)
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
		var info := "%s · %s · %s" % [e.title, String(st.get("note", SPOT_NOTE.get(e.spot, ""))), "Done" if e.done else ("Open" if e.open else "Locked")]
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
	live.stats = progress.live # the missed tries per kind ease the next field
	live.set_world(live_world())
	if live.is_running():
		live.abandon()
	_after_run()
	_result = {}
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
		var title := "Live %s: %s" % [LiveEvents.kind_name(lev).to_lower(), lev.title]
		events.append({"live": lev.id, "stage": -1, "spot": "", "pos": lev.pos, "heading": lev.heading, "done": false,
			"open": true, "color": lev.color, "title": title, "act": "Live event"})
		var medal := int(lev.get("best_tier", 0))
		builder.add_beacon("live_%s" % lev.id, lev.pos, lev.color if medal == 0 else LiveEvents.TIER_COLORS[medal],
			"%sLIVE %s" % [("%s " % "★".repeat(medal)) if medal > 0 else "", LiveEvents.kind_name(lev)])

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
	if builder and builder.festival and live:
		builder.festival.sync_live_events(live.board)

## The world's state the gated live events (night race, rain drift, fog sprint) read: night, road wetness, rain, fog, hail.
func live_world() -> Dictionary:
	return {"night": night, "wet": wet, "rain": rain, "fog": fog, "hail": hail}

func _live_marker(e: Dictionary) -> Dictionary:
	var lev := live.find(String(e.live)) if live else {}
	var info := String(e.title)
	if not lev.is_empty():
		info += " · %s" % live.target_text(lev, CarCatalog.key_at(progress.car_class))
		if LiveEvents.gate_tag(lev) != "":
			info += " · %s" % LiveEvents.gate_tag(lev)
	return {"pos": e.pos, "color": e.color, "label": "LIVE %s" % LiveEvents.kind_name(lev) if not lev.is_empty() else "LIVE EVENT",
		"info": info, "kind": "live"}

## Starts a live event from its card (or RESTART) as a campaign mission starts (_start_run): the field on the grid
## on the generated route, the roads closed, the countdown. It runs at the hour and in the weather it is.
func _begin_live(id: String) -> void:
	_begin_live_ev(live.find(id))

func _begin_live_ev(lev: Dictionary) -> void:
	if lev.is_empty():
		return
	if live.is_running():
		live.abandon()
	_after_run() # (a mission's hour put back)
	if not live.board.has(lev): # restarted after it left the board: back up for a while
		lev.expires = maxf(float(lev.expires), live.clock_h + 1.0)
		live.board.append(lev)
		_live_sync()
	live.stats = progress.live
	lev["mu"] = drive.mu # the free-roam weather's grip: the rivals' pace (and so the medals) run on it, as a mission's do
	_start_run(lev)
	hud.notify("LIVE %s" % LiveEvents.kind_name(lev), ("%s · %s" % [lev.title, LiveEvents.gate_tag(lev)]) if LiveEvents.gate_tag(lev) != "" else String(lev.title), lev.color)

## A mission run (a campaign one from MapMissions.event or a live one) put on the map: the field lined up on the
## grid, the car in its slot, the traffic cleared off the closed roads, the checkpoint beacon and the GPS.
func _start_run(lev: Dictionary) -> void:
	_clear_rivals()
	_result = {}
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
	_event_beacons(false)
	_recompute_route()

## The other events' beacons (stages, missions, live events) hidden while a run is driven, as Forza clears its
## markers: their labels show through walls and one near the route covers the view. The run's own checkpoint
## beacon and the player's waypoint stay.
func _event_beacons(on: bool) -> void:
	if builder == null:
		return
	for key in builder.beacon_nodes:
		var n: Variant = builder.beacon_nodes[key]
		if n is Node3D and is_instance_valid(n) and key != "live_cp" and key != "waypoint":
			(n as Node3D).visible = on

## Ends the run being driven (abandoned: nothing recorded) and puts the world back.
func _end_run(title := "", sub := "") -> void:
	if live and live.is_running():
		live.abandon()
	_after_run()
	if title != "":
		hud.notify(title, sub, Color("#ff5a4a"))

## The world after a run, however it ended: no checkpoint beacon, gates, rivals or event HUD; the clock a mission
## moved put back; the GPS back on the next campaign target (traffic returns by itself once the roads reopen).
func _after_run() -> void:
	if event_dressing:
		event_dressing.clear()
	_live_cp_beacon()
	_event_beacons(true)
	if hud:
		hud.set_live("", "", Color.WHITE)
		hud.set_standings([], Color.WHITE)
	if not _saved_weather.is_empty():
		set_weather(_saved_weather)
		_saved_weather = {}
	if _saved_hour >= 0.0:
		hour = _saved_hour
		_saved_hour = -1.0
		if sun:
			_apply_time()
	_wx_hour = hour # the free-roam weather carries on from where the run found it
	if not gps_waypoint and (gps_target < 0 or gps_target >= events.size() or events[gps_target].has("live")):
		gps_target = _next_open_event()
	if hud:
		_recompute_route()

## During an event, R (and a water respawn) puts the car back at the last checkpoint it went through. False outside
## a run (or in a rally liaison): the plain respawn does.
func _reset_in_event() -> bool:
	if live == null or not live.is_running():
		return false
	var pose := live.reset_to_checkpoint()
	if pose.is_empty():
		return false
	drive.place(pose[0], float(pose[1]))
	snap_camera()
	_recompute_route()
	hud.notify("RESET", "Back at the last checkpoint", live.run.ev.color)
	return true

## RESTART: the event being driven (or the one just finished) from the start again.
func _restart_event(target: Dictionary) -> void:
	if target.has("mission"):
		_begin_mission(int(target.mission))
	elif target.has("live"):
		_begin_live_ev(target.live)

## What RESTART would start again for the run being driven.
func _run_target() -> Dictionary:
	if live == null or not live.is_running():
		return {}
	var ev: Dictionary = live.run.ev
	return {"mission": int(ev.mission)} if ev.has("mission") else {"live": ev}

## The results card (Forza's results screen, without stopping): the outcome, ENTER restarts, driving on continues.
func _show_result(sub: String, title: String, body: String, color: Color, target: Dictionary) -> void:
	_result = target.duplicate()
	_result["pos"] = Vector2(drive.car.x, drive.car.y)
	active_event = -1
	hud.show_event(sub, title, body, "ENTER / B  ▸  RESTART     ·     DRIVE ON  ▸  CONTINUE", color)

## The beacon at the next checkpoint (or the finish) while an event runs; none otherwise.
func _live_cp_beacon() -> void:
	if builder == null:
		return
	var old: Variant = builder.beacon_nodes.get("live_cp")
	if old is Node3D:
		(old as Node3D).queue_free()
	builder.beacon_nodes.erase("live_cp")
	_place_gates()
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

## Posts either side of the road at the next checkpoint gate, and dimmer ones at the gate after it.
func _place_gates() -> void:
	for n in _gate_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_gate_nodes.clear()
	if live == null or not live.is_running() or world == null or map == null:
		return
	var lev: Dictionary = live.run.ev
	var ga := live.gates_ahead()
	for k in 2:
		var g: Dictionary = ga[k]
		if g.is_empty():
			continue
		var node := _gate_posts(g, lev.color if k == 0 else (lev.color as Color).darkened(0.55), 4.5 if k == 0 else 3.0)
		node.name = "Gate%d" % k
		world.add_child(node)
		_gate_nodes.append(node)

## A pair of glowing posts either side of the road at a gate {pos, dir, half}: world-placed (top_level), so they can
## hang under any node.
func _gate_posts(g: Dictionary, col: Color, h: float) -> Node3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.disable_fog = true
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.22
	cyl.bottom_radius = 0.32
	cyl.height = h
	var node := Node3D.new()
	node.top_level = true
	var d: Vector2 = g.dir
	for side in [-1.0, 1.0]:
		var q: Vector2 = (g.pos as Vector2) + Vector2(-d.y, d.x) * (float(g.half) - LiveEvents.GATE_MARGIN + 1.4) * side
		var hit := map.road_at(q.x, q.y, -INF, 3.0)
		var y: float = float(hit.height) if not hit.is_empty() else map.ground(q.x, q.y)
		var post := MeshInstance3D.new()
		post.mesh = cyl
		post.material_override = mat
		post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		post.position = Vector3(q.x, y + h * 0.5, q.y)
		node.add_child(post)
	return node

## One frame of the live events: the run (timer, checkpoints, result) or, between runs, the board round the car.
func _update_live(delta: float) -> void:
	if live == null:
		return
	live.set_world(live_world())
	_event_dressing_tick(delta)
	var cp := Vector2(drive.car.x, drive.car.y)
	if live.is_running():
		var car := drive.car
		var v := Vector2(car.vx, car.vy).length()
		var slip := absf(wrapf(atan2(car.vy, car.vx) - car.heading, -PI, PI)) if v > 1.0 else 0.0
		var off := LiveEvents.off_road(map, cp, drive.z)
		var lev: Dictionary = live.run.ev
		var r := live.tick(delta * _time_rate, cp, v, slip, off and not drive.airborne, _crashed_frame, drive.z)
		match r:
			"go":
				hud.notify("GO!", String(lev.title), lev.color)
			"cp":
				_live_cp_beacon()
				_recompute_route()
				hud.notify("CHECKPOINT", LiveEvents.clock_text(float(live.run.t)), lev.color)
			"warn":
				hud.notify(String(LiveEvents.NOTICES.get(live.run.notice, "")), "", Color("#ff5a4a"))
			"stage_done":
				var n := (live.run.stage_times as Array).size()
				hud.notify("SS%d DONE · %s" % [n, LiveEvents.clock_text(float(live.run.stage_times[n - 1]))],
					"P%d overall · drive the liaison to SS%d" % [live.rally_place(), n + 1], lev.color)
				_live_cp_beacon()
				_recompute_route()
			"stage":
				var sp := live.stage_pose(int(live.run.stage)) # on the line, facing down the stage
				drive.place(sp[0], float(sp[1]))
				snap_camera()
				hud.notify("SS%d · %s" % [int(live.run.stage) + 1, String(lev.stages[int(live.run.stage)].name)], "On the line", lev.color)
				_live_cp_beacon()
				_recompute_route()
			"done", "fail":
				_live_finished()
		if live.is_running():
			_update_rivals(delta)
			var lines := live.hud_lines(cp)
			hud.set_live(String(lines[0]), String(lines[1]), lev.color)
			var rv := live.rivals()
			hud.set_standings(rv.standings() if rv else [], lev.color) # the timing list, as a race has
		return
	hud.set_live("", "", Color.WHITE)
	hud.set_standings([], Color.WHITE)
	var before := _live_ids()
	var added := live.update(delta, delta * DAY_RATE, cp, _beacon_points())
	for lev in added:
		var d := (lev.pos as Vector2).distance_to(cp)
		if d < LiveEvents.ANNOUNCE:
			var tag := LiveEvents.gate_tag(lev)
			hud.notify("NEW LIVE EVENT", "%s · %s · %d m%s" % [LiveEvents.kind_name(lev), lev.title, int(d), (" · " + tag) if tag != "" else ""], lev.color)
	if _live_ids() != before:
		_live_sync()

## The driven event's start gantry and spectators (EventDressing): built on the frame a run begins, lit with its countdown,
## freed when it ends or is abandoned (_after_run).
func _event_dressing_tick(delta: float) -> void:
	if world == null or map == null or builder == null:
		return
	if event_dressing == null:
		if not live.is_running():
			return
		event_dressing = EventDressing.new(map, builder)
		world.add_child(event_dressing)
	var pos := car_visual.position if car_visual else Vector3(drive.car.x, drive.z, drive.car.y)
	event_dressing.update(live, delta * _time_rate, pos, Vector3(drive.car.vx, drive.vz, drive.car.vy))

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
	# a live mission: judged as a campaign one is (MapMissions.outcome), its fans and medal on the board, its stats in
	# WorldProgress.live (never the campaign: no trophy, no car, no progress)
	var rec := live.settle(res)
	var tier := int(rec.tier)
	var name := LiveEvents.kind_name(lev)
	progress.record_live(LiveEvents.stat_kind(lev), tier)
	_after_run()
	var target := live.target_text(lev, CarCatalog.key_at(progress.car_class))
	if bool(rec.success):
		hud.notify("%s · LIVE %s CLEARED" % [LiveEvents.TIER_NAMES[tier], name], String(rec.line), LiveEvents.TIER_COLORS[tier])
	else:
		hud.notify("LIVE %s MISSED · %s" % [name, String(lev.title)], "%s · target: %s" % [String(rec.line), target.to_lower()],
			Color("#ff5a4a"))
	if int(rec.fans) > 0:
		_add_fans(int(rec.fans), "LIVE EVENT")
	var next := String(res.get("next", ""))
	var body := "%s%s\nTarget: %s%s\n%s" % [String(rec.line), (" · " + next) if next != "" else "", target.to_lower(),
		(" · %s" % "★".repeat(tier)) if tier > 0 else "",
		("+%s fans" % OpenWorldHud._thousands(int(rec.fans))) if int(rec.fans) > 0 else "The event stays up for another go"]
	_show_result("LIVE %s MISSION" % name, "%s · %s" % ["CLEARED" if bool(rec.success) else "MISSED", String(lev.title)], body,
		OpenWorldHud.GOLD if bool(rec.success) else Color("#ff5a4a"), {"live": lev})
	_live_sync()
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
	if live.is_running():
		live.abandon()
		_clear_rivals()
	_result = {}
	var def: Dictionary = Missions.get_def(index)
	if _saved_hour < 0.0:
		_saved_hour = hour # put back when the run ends
	hour = float(def.get("start_hour", hour))
	if _saved_weather.is_empty():
		_saved_weather = weather_state() # put back when the run ends
	set_weather(MapMissions.weather_state(String(def.get("weather", "dry"))))
	if sun: # (built worlds only: _process applies it every frame anyway)
		_apply_time()
	_start_run(lev)
	hud.notify("%s MISSION" % Missions.KIND_NAMES[def.kind], String(def.title), Missions.COLOR)
	return true

## The map's weather now, in MapMissions.weather_state's form (mu is the driven car's weather grip).
func weather_state() -> Dictionary:
	return {"mode": weather, "wet": wet, "rain": rain, "snow": snow, "hail": hail, "fog": fog, "mu": drive.mu if drive else 1.0}

## Puts a weather (MapMissions.weather_state, or one weather_state() saved) on the map: the road shaders' wet, rain
## and snow, the falling weather particles, overcast sky and fog, and the car's grip (FreeCar.mu, as a race's Race.grip).
func set_weather(st: Dictionary, apply := true) -> void:
	weather = String(st.get("mode", "dry"))
	wet = float(st.get("wet", 0.0))
	rain = float(st.get("rain", 0.0))
	snow = float(st.get("snow", 0.0))
	hail = float(st.get("hail", 0.0))
	fog = float(st.get("fog", 0.0))
	if drive:
		drive.mu = float(st.get("mu", 1.0))
	if sun and apply:
		_apply_time()

## Free roam's weather: the cycle (WorldWeather) starts from the saved seed and clock. A save without a seed gets one
## now; "Always dry" (WorldProgress.weather_dynamic off) leaves the map dry.
func _start_weather() -> void:
	if progress == null:
		return
	var clock := float(progress.weather_day) * 24.0 + hour
	if progress.weather_seed == 0: # a new game: a random seed whose weather is fine at the start
		for _try in 20:
			progress.weather_seed = 1 + (randi() % 0x7ffffffe)
			var first := WorldWeather.new(progress.weather_seed, clock).state()
			if String(first.mode) == "dry":
				break
	wx = WorldWeather.new(progress.weather_seed, clock)
	_wx_hour = hour
	if progress.weather_dynamic:
		set_weather(wx.state(), false)

## Every frame: the cycle follows the clock (a jump of it, the time-of-day skip, re-settles the weather), and its weather
## goes on the map unless a mission is running its own (the cycle waits, the clock having been moved for the run).
func _update_weather() -> void:
	if wx == null or progress == null:
		return
	if not _saved_weather.is_empty():
		_wx_hour = hour
		return
	wx.advance(fposmod(hour - _wx_hour, 24.0))
	_wx_hour = hour
	if progress.weather_dynamic:
		set_weather(wx.state(), false)

## The pause menu's WEATHER switch, and the dev menu's: Dynamic (the cycle) or Always dry. The cycle keeps running
## while it is off, so switching it back on finds the weather where it would have been. A mission's own weather stays
## on until it ends; the free-roam weather it puts back follows the switch.
func set_weather_dynamic(on: bool) -> void:
	if progress == null:
		return
	progress.weather_dynamic = on
	if wx == null:
		return
	var st := wx.state() if on else MapMissions.weather_state("dry")
	if _saved_weather.is_empty():
		set_weather(st)
	else:
		_saved_weather = st

func _weather_text() -> String:
	return "WEATHER  ·  %s" % ("DYNAMIC" if progress.weather_dynamic else "ALWAYS DRY")

## Dev menu: rain, fog or snow now for two game hours (turns Dynamic on); it builds up over 12 to 30 game minutes.
func dev_weather(kind: String) -> void:
	if wx == null:
		return
	wx.force(kind)
	if not progress.weather_dynamic:
		set_weather_dynamic(true)

## A mission (campaign or live) is on: the town's traffic is kept off its roads.
func _roads_closed() -> bool:
	return live != null and live.is_running()

func _spawn_rivals() -> void:
	_clear_rivals()
	var rv := live.rivals()
	if rv == null:
		return
	var ev: Dictionary = live.run.get("ev", {})
	var field_seed := CarCatalog.rival_seed([int(ev.get("mission", -1)), String(ev.get("id", "")), String(ev.get("title", ""))])
	var avoid := _player_paint()
	var seen_models := {}
	for k in rv.rivals.size():
		var rival_key := CarCatalog.rival_model(k, field_seed)
		var occ := int(seen_models.get(rival_key, 0))
		seen_models[rival_key] = occ + 1
		var node: Node3D = CAR_SCENE.instantiate()
		node.car_key = rival_key
		world.add_child(node)
		node.set_paint(CarCatalog.field_color(rival_key, occ, avoid, field_seed + CarCatalog.index_of(rival_key) * 3))
		node.set_stripes(posmod(field_seed + k * 7, 10) < 3)
		if mods.has("monster"):
			node.set_wheel_scale(CarMods.MONSTER_WHEELS)
		var r: Dictionary = rv.rivals[k]
		if r.has("number"):
			node.set("car_number", int(r.number))
		# the driver's name over the car, as a race's field is named on the timing list
		var tag := Label3D.new()
		tag.name = "NameTag"
		tag.text = String(r.get("name", "")).split(" ")[-1].to_upper()
		tag.font = CmrStyle.font(900)
		tag.font_size = 40
		tag.outline_size = 10
		tag.fixed_size = true # the same size on screen near and far (a world-sized tag filled the view a car ahead)
		tag.pixel_size = 0.0006
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.position = Vector3(0, float(CarCatalog.visual(rival_key).roof_number.y) + 0.55, 0)
		tag.modulate = Color(1, 1, 1, 0.9)
		tag.visibility_range_begin = 7.0 # not over a car right in front of the camera
		tag.visibility_range_end = 160.0
		tag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tag.layers = CarReflections.OVERLAY_LAYER # never mirrored in the car's glass
		node.add_child(tag)
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
		if bool(r.get("out", false)) or bool(r.get("gone", false)): # knocked out, or home and turned off out of sight
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
		var rv_speed := float(r.v)
		var prev_v := float(node.get_meta("prev_v", rv_speed))
		var braking := delta > 0.001 and rv_speed > 0.2 and (prev_v - rv_speed) / delta > 1.5
		node.set_meta("prev_v", rv_speed)
		if delta > 0.0 and rv_speed > 0.01:
			var wr := maxf(float(node.get("_wheel_radius")), 0.1)
			var spin := rv_speed * delta / wr
			for w in (node.get("wheels") as Array):
				(w as Node3D).rotation.x = fmod((w as Node3D).rotation.x - spin, TAU)
		node.call("set_lamps", night, braking) # headlamps, position lights and brake lamps like the player's
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
	_after_run()
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
	var body := "%s\nTarget: %s%s%s" % [String(out.line), Missions.target_text(index).to_lower(),
		("\nTrophy: %s" % String(rec.trophy)) if bool(rec.first_clear) else "",
		("\n+%s fans" % OpenWorldHud._thousands(int(rec.fans))) if int(rec.fans) > 0 else ""]
	_show_result("%s MISSION" % Missions.KIND_NAMES[def.kind], "%s · %s" % ["CLEARED" if bool(rec.success) else "MISSED",
		String(def.title)], body, OpenWorldHud.GOLD if bool(rec.success) else Color("#ff5a4a"), {"mission": index})
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
	# never on or just short of a road-end barrier at the play edge: set back along the road, facing away from it
	for c in map.closures:
		if int(c[4]) == 1:
			continue # the S1's turn-around loops, not a dead end
		var cp := Vector2(float(c[0]), float(c[1]))
		var out := Vector2.from_angle(float(c[2]))
		var into := (p - cp).dot(-out) # metres inside the barrier along its road
		if p.distance_to(cp) < CLOSURE_CLEAR and into < CLOSURE_CLEAR:
			p = cp - out * CLOSURE_CLEAR
			h = float(c[2]) + PI
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
	cam_pos = _prev_pos - f * 5.0 + Vector3.UP * 1.75
	cam_off = cam_pos - _prev_pos
	cam_vel_dir = Vector2(f.x, f.z)
	_chase_cam = null # snaps to the car's new spot
	look.reset()
	# every site that moves the car (spawn, respawn, event reset, dev teleport) snaps the camera: the street plate and
	# the area banner catch up now, not at their next 0.5 s / 1.5 s check
	_update_street_name()
	_area_t = 0.0

func _check_events() -> void:
	if live and live.is_running():
		if active_event >= 0:
			active_event = -1
			hud.hide_event()
		return
	var cp := Vector2(drive.car.x, drive.car.y)
	if not _result.is_empty():
		# the results card stays until the car drives on (CONTINUE) or ENTER restarts
		if cp.distance_to(_result.pos) < RESULT_LEAVE:
			return
		_result = {}
		active_event = -1
		hud.hide_event()
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
			live.stats = progress.live
			var c := live.card(lev, CarCatalog.key_at(progress.car_class), FanLevels.level(progress.fans))
			hud.show_event(String(c[0]), String(c[1]), String(c[2]), String(c[3]), ev.color)
		return
	if ev.has("mission"):
		var c := Missions.card(int(ev.stage), FanLevels.level(progress.fans))
		hud.show_event(String(c[0]), String(c[1]), StoryDirector.brief_text(int(ev.stage), String(c[2])), String(c[3]), ev.color)
		return
	var st: Dictionary = Campaign.get_stage(ev.stage)
	var target := "Win the race" if int(st.target_pos) == 1 else "Finish P%d or better" % int(st.target_pos)
	var body := "%s\n\n%s · %d laps · %s · %d rivals (%s)\nTarget: %s · Trophy: %s\nFan level %d recommended (you are level %d) · up to %s fans on a first clear" % [st.desc, String(st.get("note", SPOT_NOTE.get(ev.spot, ""))),
		int(st.laps), String(st.weather).capitalize(), int(st.opponents), String(st.difficulty).capitalize(), target, st.trophy,
		FanLevels.stage_level(int(ev.stage)), FanLevels.level(progress.fans),
		OpenWorldHud._thousands(FanLevels.stage_reward(int(ev.stage), 1, int(st.target_pos), true))]
	var hint := "ENTER / B  ▸  START STAGE" if ev.open else "LOCKED · clear the stages before it first"
	hud.show_event(String(st.act_name).to_upper(), String(st.title), StoryDirector.brief_text(int(ev.stage), body), hint, ev.color)

func _start_active_event() -> void:
	if not _result.is_empty():
		var target := _result
		_result = {}
		_restart_event(target)
		return
	if active_event < 0:
		return
	var ev: Dictionary = events[active_event]
	if not ev.open:
		return
	if ev.has("live"):
		_begin_live(String(ev.live))
		return
	if story and story.before_event(int(ev.stage), _start_active_event): # the event's story beat first, then this again
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
	label.layers = CarReflections.OVERLAY_LAYER # never mirrored in the car's glass
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
		_update_street_name()
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

## The street plate for the road under the car. _check_discovery runs it every 0.5 s and snap_camera (every teleport,
## respawn and event reset) runs it at once, so the plate never shows the street the car was moved from.
func _update_street_name() -> void:
	if hud != null and not drive.road.is_empty():
		hud.set_street(street_label(map.road_name[int(drive.road.road)]))

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
const DRIFT_BANK_SHARE := 0.5 ## share of a banked free-roam drift combo paid into the skill chain
var _drift_view := DriftScore.new() ## free-roam drifts scored for the drift meter; a banked combo pays into the skill chain
var _drift_clock := 0.0
var drift_cam := DriftStyle.new() ## the chase camera's swing and roll through a drift
var _skids: SkidTrail

func _update_skills(dt: float) -> void:
	var car := drive.car
	var v := Vector2(car.vx, car.vy).length()
	if v > 8.0 and not drive.airborne:
		var vel_h := atan2(car.vy, car.vx)
		var slip := absf(wrapf(vel_h - car.heading, -PI, PI))
		if slip > 0.26 and slip < 1.9:
			_skill(dt * DriftScore.rate(v, slip), "DRIFT") # deep and fast slides pay more (DriftScore.rate)
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
	var sliding := DriftStyle.amount(absf(DriftStyle.slip_angle(car.vx, car.vy, car.heading)), v) > 0.2
	for h in drive.hits:
		if float(h[2]) > 6.0:
			crashed = true
		if sliding and float(h[2]) > 0.9: # a kerb or a wall touched mid-drift
			FxParticles.burst(car_visual, "sparks", Vector3(float(h[0]), car_visual.position.y + 0.25, float(h[1])), 12, quality)
	drive.hits.clear()
	for h in traffic.hits:
		if float(h[2]) > 6.0:
			crashed = true
	traffic.hits.clear()
	_crashed_frame = crashed
	_update_drift_style(dt, v, crashed) # before the chain banks: a drift combo banking now joins the chain
	if crashed and chain_points > 0.0:
		var lost := int(chain_points * chain_mult)
		if lost >= 1: # a chain of less than one fan ends quietly (no "0 fans" banner)
			hud.notify("CHAIN LOST", "Crashed with %d fans in the chain" % lost, Color("#ff4d4d"))
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

## The drift meter (a live drift zone's own score, else free-roam drifts for show) and the rear tyres' skid marks.
func _update_drift_style(dt: float, v: float, crashed: bool) -> void:
	var car := drive.car
	var slip := 0.0 if drive.airborne else DriftStyle.slip_angle(car.vx, car.vy, car.heading)
	_drift_clock += dt
	var ds: DriftScore = null
	if live and not live.run.is_empty():
		ds = live.run.get("drift")
	if ds == null:
		var before := _drift_view.event_t
		_drift_view.step(v, absf(slip), false, crashed, dt, _drift_clock)
		ds = _drift_view
		if _drift_view.event_t != before and _drift_view.last_event == "BANKED":
			# a banked drift combo (its held seconds and linked corners multiplied in) goes into the skill chain
			# on top of the slide's own points, so a drift held and linked through the bends pays far more
			# than gripping round them
			var pts := _drift_view.event_points
			_skill_event(pts * DRIFT_BANK_SHARE, String(DriftStyle.LABELS[DriftStyle.label_index(pts)][1]))
	hud.drift_meter.feed(ds, dt)
	if _skids == null or not is_instance_valid(_skids):
		_skids = SkidTrail.new()
		car_visual.get_parent().add_child(_skids)
	var k := maxf(DriftStyle.amount(absf(slip), v), clampf((car.slip - 0.42) / 0.5, 0.0, 1.0) if v > 3.0 else 0.0)
	if k > 0.15 and not drive.airborne and not drive.in_water and not SurfaceFeedback.KICK_ORDER.has(SurfaceFeedback.kick_surface(drive.wheel_surfaces())):
		var fit := CarCatalog.visual(String(car_visual.car_key))
		var hr := float(fit.get("half_track_rear", 0.65))
		var z := float((fit.fx_axle as Vector3).z)
		_skids.lay(car_visual.to_global(Vector3(-hr, 0.0, z)), car_visual.to_global(Vector3(hr, 0.0, z)), k)
	else:
		_skids.lift()

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

## The pause menu's CAR: the garage (Garage) over the paused world; a new car or paint is fitted when it closes.
func _open_garage() -> Garage:
	var g := Garage.open_in(self, CarCatalog.key_at(progress.car_class), _player_paint(), progress.fans, {"number": car_number})
	g.chosen.connect(func(key: String, _col: Color) -> void:
		if key != CarCatalog.key_at(progress.car_class) and live and live.is_running():
			_end_run("EVENT ABANDONED", "Car changed")
		progress.car_class = CarCatalog.index_of(key)
		_fit_car() # (the paint was saved by the garage; _apply_look reads it)
		hud.notify(CarCatalog.display_name(key).to_upper(), CarCatalog.paint_name(key, _player_paint()), OpenWorldHud.GOLD))
	return g

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

## The driven car's paint: its livery, else the factory paint last picked for it in the garage (CarCatalog.saved_paint).
func _player_paint() -> Color:
	return CarCatalog.saved_paint(CarCatalog.key_at(progress.car_class), paint)

## The fitted car's livery and the modifiers switched on (CarMods), on the visual and the physics.
func _apply_look() -> void:
	var hyper := progress.car_class == 1
	var livery := CarCatalog.livery(CarCatalog.key_at(progress.car_class))
	mods = CarMods.active(progress.mods, progress.fans)
	CarMods.apply_to(drive, mods)
	if traffic:
		traffic.set_monster(mods.has("monster"))
	if car_visual:
		car_visual.set_paint(_player_paint())
		car_visual.car_number = livery.get("number", car_number)
		car_visual.set_wheel_scale(CarMods.MONSTER_WHEELS if mods.has("monster") else 1.0)
	hud.set_car_label(hyper, FanLevels.hypercar_unlocked(progress.fans), _car_name())

## The pause menu's MODIFIERS page: one switch per CarMods entry, locked ones name their fan level.
func _show_mods_page() -> void:
	var items := []
	for m in CarMods.LIST:
		items.append(["mod:" + m[0], _mod_text(m), not CarMods.unlocked(m[0], progress.fans)])
	items.append(["weather", _weather_text()])
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
		_end_run("EVENT ABANDONED", "Modifier changed")
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

## Enter / A / a second click on the big map: a waypoint at the cursor, or the route to the selected place.
func _map_accept() -> void:
	var hud_sel: int = hud.map_sel
	if hud.cursor_on:
		_set_waypoint(hud.cursor)
	elif hud_sel >= 0 and hud_sel < hud.markers.size() and hud.markers[hud_sel].get("kind", "") == "poi":
		_route_to_poi(Poi.find(pois, String(hud.markers[hud_sel].id)))
	elif hud_sel >= events.size():
		gps_waypoint = true
		_recompute_route()
		hud.toggle_map(false)
		hud.notify("ROUTE SET", "Your waypoint", OpenWorldHud.PURPLE)
	else:
		gps_waypoint = false
		gps_target = hud_sel
		_recompute_route()
		hud.toggle_map(false)
		hud.notify("ROUTE SET", String(events[gps_target].title), OpenWorldHud.PURPLE)

## The map's filters changed: remembered in the save.
func _map_filters_changed(hidden: Array) -> void:
	if progress:
		progress.map_hidden = hidden
		progress.save()

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
		if builder and builder.festival:
			builder.festival.silence()
		hud.update_drive(drive.speed_kmh(), _gear_shown(), drive.car.rpm, drive.model.spec.limiter, Vector2(drive.car.x, drive.car.y), drive.car.heading, delta, drive.vz)
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
		if not _reset_in_event():
			hud.notify("BACK ON THE ROAD", "New wheel fitted" if drive.respawn_reason == "wheel" else "The Seicento doesn't swim", Color("#4aa3ff"))
			drive.respawn()
			snap_camera()
	builder.update_crossings(delta)
	builder.update_signals()
	hour = fmod(hour + delta * DAY_RATE, 24.0)
	_update_weather()
	_apply_time()
	_sync_car(delta)
	if builder and builder.festival:
		builder.festival.update(delta, car_visual.position, Vector3(drive.car.vx, drive.vz, drive.car.vy), night, true)
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
	hud.update_drive(drive.speed_kmh(), _gear_shown(), drive.car.rpm, drive.model.spec.limiter, Vector2(drive.car.x, drive.car.y), drive.car.heading, delta, drive.vz)
	hud.set_stats(progress.fans, progress.roads.size(), map.road_pts.size(), hour, WorldWeather.word(weather_state()))
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
	# and further through a drift, round to the car's side (DriftStyle), settling back behind it afterwards
	drift_cam.update_camera(car.vx, car.vy, car.heading, delta, look.cut, car.yaw_rate / 4.0)
	want_dir = want_dir.rotated(drift_cam.swing * 0.6 + drift_cam.lead)
	var drift_up := Vector3.UP.rotated(Vector3(want_dir.x, 0.0, want_dir.y), drift_cam.roll)
	# turned through the angle, not lerped: a lerp between near-opposite directions passes through zero, and the
	# normalised zero put the camera straight over the car looking down (a respawn facing the other way)
	cam_vel_dir = Vector2.from_angle(lerp_angle(cam_vel_dir.angle(), want_dir.angle(), 1.0 - exp(-delta * 4.0)))
	var d3 := Vector3(cam_vel_dir.x, 0.0, cam_vel_dir.y)
	var kmh := absf(car.speed) * 3.6
	var fov_extra := GfxFx.update(kmh, delta)
	look.update(delta, not paused and not hud.map_open)
	# swung round the car, the chase camera looks along the view and, more and more, at the car itself
	var view := look.turn(d3)
	var at_car := smoothstep(0.0, 1.2, absf(look.yaw)) * 0.7
	match cam_mode:
		1:
			var target := p - d3 * (8.5 + float(CarCatalog.visual(String(car_visual.car_key)).get("chase_back", 0.0))) + Vector3.UP * 3.2
			cam_off = cam_off.lerp(target - p, 1.0 - exp(-delta * 6.0))
			cam_pos = p + cam_off
			camera.position = _clear_of_walls(p, look.orbit(p, cam_pos), delta, look.cut)
			camera.look_at((p + view * 5.0 * cos(look.pitch) + Vector3.UP * 1.0).lerp(p + Vector3.UP * 0.8, at_car), drift_up)
			camera.fov = HudLayout.camera_fov_for(camera, 58.0 + smoothstep(10.0, 200.0, kmh) * 10.0 + fov_extra)
		2:
			camera.global_transform = car_visual.global_transform * Transform3D(Basis(), Vector3(0.0, 1.22, -0.35))
			camera.rotate_object_local(Vector3.RIGHT, deg_to_rad(-2.0))
			if look.active(): # the driver turns their head
				camera.rotate_object_local(Vector3.UP, -look.yaw)
				camera.rotate_object_local(Vector3.RIGHT, -look.pitch)
			camera.fov = HudLayout.camera_fov_for(camera, 78.0 + kmh * 0.05 + fov_extra)
		_:
			# close in, Forza style: the offset from the car is what eases (a lerp of the world position trailed the
			# car by speed / rate, 7 m more at 180 km/h, and with 8 m of boom and an 84 deg view the car was a dot,
			# 2026-11-21); a longer car sits its own chase_back further out
			var tail := float(CarCatalog.visual(String(car_visual.car_key)).get("chase_back", 0.0))
			var back := 4.1 + tail + kmh * 0.004
			var target := p - d3 * back + Vector3.UP * (1.6 + kmh * 0.0015)
			cam_off = cam_off.lerp(target - p, 1.0 - exp(-delta * 9.0))
			cam_pos = p + cam_off
			# keep it out of the walls and buildings (shortened or swung aside, ChaseCam) and above the ground
			var spot := _clear_of_walls(p, look.orbit(p, cam_pos), delta, look.cut)
			spot.y = maxf(spot.y, map.ground(spot.x, spot.z) + 0.8)
			camera.position = spot
			camera.look_at((p + view * 4.0 * cos(look.pitch) + Vector3.UP * 0.95).lerp(p + Vector3.UP * 0.8, at_car), drift_up)
			camera.fov = lerpf(camera.fov, HudLayout.camera_fov_for(camera, 54.0 + smoothstep(10.0, 200.0, kmh) * 11.0 + fov_extra), 1.0 - exp(-delta * 3.0))
	if weather_fx:
		weather_fx.place(camera)
	_update_beacon_labels()
	_update_area_hold(delta)

## The area banner (SZCZOTKI ...) is 2D, the arches' lettering over the road is 3D: at a gate the two landed on top of each
## other. While the banner is up and an overhead arch is on screen behind it, the banner hides (OpenWorldHud.set_area_hold)
## and comes back when the arch has passed.
const ARCH_BANNER_RANGE := 120.0 ## m: arches further off are too small to clash
const ARCH_HEIGHT := 6.3 ## m: the middle of an arch's lettering (windowed QA 2026-11-23: 5.5 sat 0.8 m below it)
const ARCH_HALF_WIDTH := 7.0 ## m: how far its lettering reaches to the side
var _arch_pts: Array[Vector3] = []
var _arch_scan_t := 0.0
var _arch_sig := -1 ## signature of the arch MultiMeshes last collected (their instance counts + ids)
var _hold_text := ""
var _hold_fsz := -1
var _hold_font: Font
var _hold_tw := 0.0

## Re-collects _arch_pts only when the festival's arch MultiMeshes changed (set, or live arches added/removed);
## the signature walk touches node names and instance counts, not every instance transform.
func _refresh_arch_pts() -> void:
	var sig := [0, 0]
	if builder.festival != null:
		_arch_signature(builder.festival, 0, sig)
	var h: int = sig[0] * 31 + sig[1]
	if h == _arch_sig:
		return
	_arch_sig = h
	_arch_pts.clear()
	if builder.festival != null:
		_collect_arches(builder.festival, 0)

func _arch_signature(n: Node, depth: int, sig: Array) -> void:
	if n is MultiMeshInstance3D:
		var nm := String(n.name)
		if nm.begins_with("InflatableArches") or nm.begins_with("FestivalArches") or nm.begins_with("LiveArches"):
			var mm := (n as MultiMeshInstance3D).multimesh
			sig[0] = sig[0] * 31 + (n as Object).get_instance_id()
			sig[1] += mm.instance_count if mm != null else 0
		return
	if depth < 2:
		for c in n.get_children():
			_arch_signature(c, depth + 1, sig)

func _update_area_hold(delta: float) -> void:
	if hud == null or camera == null or builder == null or viewport == null:
		return
	var label := hud.area_label
	if label == null or label.text == "" or label.modulate.a < 0.02:
		hud.set_area_hold(false)
		return
	_arch_scan_t -= delta
	if _arch_scan_t <= 0.0:
		_arch_scan_t = 1.0 # (the live events' arches come and go)
		_refresh_arch_pts()
	var vp_size := Vector2(viewport.size)
	if vp_size.x <= 1.0 or vp_size.y <= 1.0:
		return
	var to_screen := size / vp_size
	var font := label.get_theme_font("font")
	var fsz := label.get_theme_font_size("font_size")
	if label.text != _hold_text or fsz != _hold_fsz or font != _hold_font:
		_hold_text = label.text
		_hold_fsz = fsz
		_hold_font = font
		_hold_tw = font.get_string_size(_hold_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
	var tw := _hold_tw
	var rect := label.get_global_rect()
	var banner := Rect2(rect.get_center().x - tw * 0.5, rect.position.y, tw, rect.size.y)
	var cam_p := camera.global_position
	var hold := false
	for pt in _arch_pts:
		var d := cam_p.distance_to(pt)
		if d > ARCH_BANNER_RANGE or camera.is_position_behind(pt):
			continue
		var sp := camera.unproject_position(pt) * to_screen
		var reach := absf(camera.unproject_position(pt + camera.global_basis.x * ARCH_HALF_WIDTH).x * to_screen.x - sp.x)
		if arch_behind_banner(banner, sp, reach):
			hold = true
			break
	hud.set_area_hold(hold)

## Whether an arch whose lettering is centred at screen point `sp`, reaching `reach` px to each side (and as much up and
## down), is behind the banner's rect (a margin round it).
static func arch_behind_banner(banner: Rect2, sp: Vector2, reach: float) -> bool:
	# the lettering is ~1.2 m tall on a 14 m span: half-height = reach * 0.6 / ARCH_HALF_WIDTH (treating it as half the span
	# tall hid the banner from ~50 m, so an area entered at a gate never showed its name)
	var half_h := reach * 0.6 / ARCH_HALF_WIDTH
	return banner.grow_individual(40.0, 16.0, 40.0, 16.0).intersects(Rect2(sp - Vector2(reach, half_h), Vector2(reach * 2.0, half_h * 2.0)))

## The points over the festival's overhead arches (its Inflatable / Festival / Live arch MultiMeshes), into _arch_pts.
func _collect_arches(n: Node, depth: int) -> void:
	if n is MultiMeshInstance3D:
		var nm := String(n.name)
		if nm.begins_with("InflatableArches") or nm.begins_with("FestivalArches") or nm.begins_with("LiveArches"):
			var mm := (n as MultiMeshInstance3D).multimesh
			if mm != null:
				var xf := (n as Node3D).global_transform
				for i in mm.instance_count:
					_arch_pts.append(xf * mm.get_instance_transform(i).origin + Vector3.UP * ARCH_HEIGHT)
		return
	if depth < 2:
		for c in n.get_children():
			_collect_arches(c, depth + 1)

## Fades or hides world-space event beacon labels when the car is close enough that the gate/ring itself reads,
## or when the label projects into the top HUD band (rear-view mirror, fans card, or event card).
const BEACON_LABEL_RANGE_SQ := 430.0 * 430.0 ## just past the labels' 420 m visibility range
func _update_beacon_labels() -> void:
	if builder == null or camera == null or viewport == null or drive == null:
		return
	var vp_size := Vector2(viewport.size)
	if vp_size.x <= 1.0 or vp_size.y <= 1.0:
		return
	var car_p := Vector2(drive.car.x, drive.car.y)
	var cam_p := camera.global_position
	var screen_h := maxf(size.y, 1.0)
	var mirror_v := (RearMirror.screen_bottom / screen_h) if RearMirror.screen_bottom > 0.0 else 0.0
	var top_band := maxf(0.24, mirror_v + 0.07)
	var card_up := hud != null and hud.card != null and hud.card.visible
	for key in builder.beacon_nodes:
		var node: Variant = builder.beacon_nodes[key]
		if not is_instance_valid(node) or not (node as Node3D).visible:
			continue
		var bn := node as Node3D
		var label: Label3D = bn.get_meta("label_ref", null) as Label3D
		if label == null or not is_instance_valid(label):
			label = bn.get_node_or_null("Label") as Label3D
			if label == null:
				continue
			bn.set_meta("label_ref", label)
		var lpos := label.global_position
		if cam_p.distance_squared_to(lpos) > BEACON_LABEL_RANGE_SQ:
			if label.visible:
				label.visible = false # out past its visibility range: hidden once, then skipped
			continue
		if camera.is_position_behind(lpos):
			label.visible = false
			continue
		var is_cp := bool(label.get_meta("is_cp", false))
		var d_car := Vector2(bn.position.x - car_p.x, bn.position.z - car_p.y).length()
		var d_cam := cam_p.distance_to(lpos)
		var a_dist := smoothstep(14.0, 26.0, d_car) * smoothstep(12.0, 22.0, d_cam) if is_cp \
			else smoothstep(28.0, 46.0, d_car) * smoothstep(22.0, 38.0, d_cam)
		var sp := camera.unproject_position(lpos)
		var u := sp.x / vp_size.x
		var v := sp.y / vp_size.y
		if u < -0.15 or u > 1.15 or v < -0.05 or v > 1.08:
			label.visible = false
			continue
		var band := top_band
		if u < 0.36:
			band = maxf(band, 0.30) # clear the top-left fans card
		if card_up and u > 0.60:
			band = maxf(band, 0.48) # clear the right-hand event card
		var a_hud := smoothstep(band - 0.03, band + 0.07, v)
		var alpha := a_dist * a_hud
		label.visible = alpha > 0.02
		if label.visible:
			var bc: Color = label.get_meta("base_color", Color.WHITE)
			var bo: Color = label.get_meta("base_outline", Color.BLACK)
			label.modulate = Color(bc.r, bc.g, bc.b, bc.a * alpha)
			label.outline_modulate = Color(bo.r, bo.g, bo.b, bo.a * alpha)

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
	steer = Physics.key_steer(steer, st, drive.speed_kmh(), drive.phys.rear_slide(drive.car), dt) # counter-steer comes fast
	throttle = move_toward(throttle, 1.0 if up else 0.0, 6.0 * dt)
	brake = move_toward(brake, 1.0 if down else 0.0, 8.0 * dt)

func _input(event: InputEvent) -> void:
	if not active or not built:
		return
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if gamepad_device < 0:
			gamepad_device = event.device
	if hud.map_open and not paused and hud.map_event(event):
		get_viewport().set_input_as_handled() # zoom, pan, hop, filters and list (MapNav)
		return
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
				_map_accept()
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
			if not _reset_in_event():
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
		hud.set_pause_page("PAUSED", _pause_items())
	if on:
		hud.set_car_label(progress.car_class == 1, FanLevels.hypercar_unlocked(progress.fans), _car_name())
	if on and audio:
		audio.update_car(null, false)

## The pause menu's main page: RESTART EVENT and ABANDON EVENT under RESUME while an event runs.
func _pause_items() -> Array:
	var run_items := [["restart_live", "RESTART EVENT"], ["abandon_live", "ABANDON EVENT"]] if live and live.is_running() else []
	return OpenWorldHud.PAUSE_ITEMS.slice(0, 1) + run_items + OpenWorldHud.PAUSE_ITEMS.slice(1)

func _pause_action(action: String) -> void:
	if action != "reset_campaign":
		_reset_armed = false
	if action.begins_with("mod:"):
		_toggle_mod(action.substr(4))
		return
	match action:
		"abandon_live":
			if live and live.is_running():
				_end_run("EVENT ABANDONED", "")
			_set_paused(false)
		"restart_live":
			var target := _run_target()
			_set_paused(false)
			if not target.is_empty():
				_restart_event(target)
		"reset_campaign":
			if not _reset_armed:
				_reset_armed = true
				hud.notify("RESET CAMPAIGN?", "Select it again to start over: stages, missions, cars, fans and medals", Color("#ff5a4a"))
				return
			_reset_armed = false
			reset_campaign()
			_set_paused(false)
			hud.notify("CAMPAIGN RESET", "A new campaign: stage 1, no fans, the stock Seicento", OpenWorldHud.PURPLE)
		"resume":
			_set_paused(false)
		"car":
			_open_garage()
		"mods":
			_show_mods_page()
		"weather":
			set_weather_dynamic(not progress.weather_dynamic)
			hud.set_pause_text(CarMods.LIST.size(), _weather_text())
			hud.notify("WEATHER", "Dynamic: showers and fog come and go" if progress.weather_dynamic else "Always dry", OpenWorldHud.GOLD)
		"mods_back":
			hud.set_pause_page("PAUSED", _pause_items())
			hud.set_car_label(progress.car_class == 1, FanLevels.hypercar_unlocked(progress.fans), _car_name())
		"map":
			_set_paused(false)
			hud.map_sel = maxi(gps_target, 0)
			hud.toggle_map(true)
		"story":
			story.open_journal()
		"stages":
			_set_paused(false)
			suspend()
			leave_requested.emit("stages")
		"reset":
			_set_paused(false)
			if not _reset_in_event():
				drive.respawn()
				snap_camera()
		"time":
			hour = fmod(hour + 3.0, 24.0)
			_apply_time()
		"menu":
			_set_paused(false)
			suspend()
			leave_requested.emit("menu")

## A new campaign (the pause menu's RESET CAMPAIGN, or Options from the main menu while this world is kept): the
## campaign save and this world's progress wiped (WorldProgress.wipe_campaign), any run ended, the beacons and GPS
## back on stage 1, the stock car.
func reset_campaign() -> void:
	if live and live.is_running():
		live.abandon()
		_clear_rivals()
		_after_run()
	Campaign.reset_progress()
	if progress == null:
		WorldProgress.reset_campaign()
		return
	progress.wipe_campaign()
	if live:
		live.forget_medals()
		live.stats = progress.live
	if drive and _fitted_class != progress.car_class:
		_fit_car()
	if drive:
		_save()
	else:
		progress.save()
	_refresh_events()
	gps_target = _next_open_event()
	_recompute_route()

func _save() -> void:
	if progress == null or drive == null:
		return
	progress.pos = Vector2(drive.car.x, drive.car.y)
	progress.heading = drive.car.heading
	progress.has_pos = true
	progress.hour = hour
	if wx != null:
		progress.weather_day = maxi(int(roundf((wx.clock - hour) / 24.0)), 0)
	progress.odometer += drive.odometer
	drive.odometer = 0.0
	progress.save()
