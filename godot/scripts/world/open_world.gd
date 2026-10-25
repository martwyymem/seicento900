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
const WORLD := preload("res://scripts/ui/race_world.gd")
## Campaign track -> the map spot its beacon stands at (tools/build_open_world.py names the spots)
const STAGE_SPOTS := {"wilamowice": "exit_wilamowice", "brzeszcze": "industrial_sprint", "bor": "bor_stage",
	"pszczyna": "exit_pszczyna", "bielsko": "exit_bielsko", "oswiecim": "exit_oswiecim", "krakow": "station",
	"fiat": "exit_tychy", "tokyo": "festival"}
const SPOT_NOTE := {"exit_wilamowice": "South on the S1 towards Wilamowice", "industrial_sprint": "ul. Dworcowa by KWK Brzeszcze",
	"bor_stage": "ul. Bór, Brzeszcze-Bór", "exit_pszczyna": "West on the DW933 to Pszczyna",
	"exit_bielsko": "South on ul. Bielska to Bielsko-Biała", "exit_oswiecim": "East on the DW933 to Oświęcim",
	"station": "Brzeszcze Jawiszowice station: the train to Kraków", "exit_tychy": "North on the S1 to Tychy",
	"festival": "Seicento Fest at the KS Górnik stadium: the flight to Tokyo"}
const DISCOVER_KINDS := ["mineshaft", "church", "stadium", "station", "museum", "cinema", "monument", "water_tower", "chimney"]
const AREA_KINDS := ["place_town", "place_village", "place_neighbourhood", "place_hamlet", "place_suburb"]
const DAY_RATE := 1.0 / 80.0 ## game hours per real second: a day in 32 minutes
const BEACON_RADIUS := 9.0
const CHAIN_IDLE := 2.6 ## s without a skill before the chain is banked
const LAMP_LIGHTS := 10

var map: TownMap
var builder: TownBuilder
var traffic: Traffic
var progress: WorldProgress
var drive: FreeCar
var audio = null ## the game's RaceAudio
var gearbox := "auto"
var assists := "abs"
var paint := Color("#c62828")
var car_number := 9

var viewport: SubViewport
var view: TextureRect
var world: Node3D
var camera: Camera3D
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ShaderMaterial
var car_visual: Node3D
var headlights: Array[SpotLight3D] = []
var lamp_lights: Array[OmniLight3D] = []
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
var steer := 0.0
var shift_up := false
var shift_down := false
var gamepad_device := -1
var cam_mode := 0
var cam_pos := Vector3.ZERO
var cam_vel_dir := Vector2.RIGHT
var hour := 18.5
var night := 0.0

var events: Array = [] ## [{stage, spot, pos: Vector2, heading, title, ...}]
var active_event := -1
var gps_target := -1
var route := PackedVector2Array()
var _route_t := 0.0
var traps: Array = [] ## [{id, pos, dir, name}]
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
	show()
	active = true
	paused = false
	hud.show_pause(false)
	_fit_view()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if not built:
		await _build_world()
	if drive:
		drive.gearbox = gearbox
		drive.assists = assists
		if car_visual:
			car_visual.set_paint(paint)
			car_visual.car_number = car_number
	_refresh_events()
	_spawn(spawn)
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
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if audio:
		audio.update_car(null, false)
	if traffic:
		traffic.clear()
	hide()

func _fit_view() -> void:
	if not is_inside_tree():
		return
	var px := Vector2i((view.size * get_viewport().get_final_transform().get_scale()).round()).max(Vector2i(2, 2))
	if viewport.size != px:
		viewport.size = px

## Builds the town a step per frame behind the loading screen (in one go when headless: nothing is drawn there).
func _build_world() -> void:
	building = true
	var by_frame := DisplayServer.get_name() != "headless"
	hud.show_loading("Reading the map of Brzeszcze", 0.02)
	if by_frame:
		await get_tree().process_frame
	map = TownMap.load_map(MAP_KEY)
	if map == null:
		hud.show_loading("The open-world map is missing: run tools/build_open_world.py", 0.0)
		building = false
		return
	progress = WorldProgress.load_progress()
	hour = progress.hour
	world = Node3D.new()
	world.name = "Brzeszcze"
	viewport.add_child(world)
	_build_environment()
	builder = TownBuilder.new(map, world)
	var steps: Array = builder.steps()
	for i in steps.size():
		hud.show_loading("Building %s" % String(steps[i][0]).to_lower(), 0.05 + 0.85 * float(i) / steps.size())
		if by_frame:
			await get_tree().process_frame
		(steps[i][1] as Callable).call()
	hud.show_loading("Starting the engine", 0.95)
	if by_frame:
		await get_tree().process_frame
	hud.setup(map, load("res://data/world/%s_map.png" % MAP_KEY) as Texture2D)
	drive = FreeCar.new(map)
	car_visual = CAR_SCENE.instantiate()
	world.add_child(car_visual)
	car_visual.is_player = true
	_build_headlights()
	_build_lamp_lights()
	_build_route_mesh()
	traffic = Traffic.new(map, world, builder)
	_build_traps()
	built = true
	building = false
	hud.hide_loading()

# ================================================================================================ environment

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
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.08
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.5
	env.glow_enabled = true
	env.glow_normalized = true
	env.glow_intensity = 0.65
	env.glow_bloom = 0.06
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_hdr_threshold = 0.95
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.00028
	env.fog_aerial_perspective = 0.6
	env.fog_sky_affect = 0.0
	# Forza Horizon's festival grade: rich colour, a touch of contrast
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.18
	env.adjustment_contrast = 1.05
	we.environment = env
	world.add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 260.0
	sun.shadow_blur = 1.2
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
	var below := 0.0
	if hour <= 4.75 or hour >= 20.75:
		var h := hour if hour >= 20.75 else hour + 24.0
		below = clampf((h - 20.75) / 2.0, 0.0, 1.0) * clampf((28.75 - h) / 2.0, 0.0, 1.0)
		elev = -deg_to_rad(14.0) * below
	var az := deg_to_rad(lerpf(50.0, 310.0, day_frac))
	var dir := Vector3(sin(az) * cos(elev), sin(elev), -cos(az) * cos(elev)).normalized()
	var day := clampf(elev / deg_to_rad(12.0) + 0.15, 0.0, 1.0)
	var golden := clampf(1.0 - absf(elev - deg_to_rad(6.0)) / deg_to_rad(14.0), 0.0, 1.0) * (1.0 if elev > -0.05 else 0.0)
	night = 1.0 - day
	var sun_dir := dir if elev > -0.02 else Vector3(-dir.x, absf(dir.y) + 0.5, -dir.z).normalized() # moonlight
	sun.basis = Basis.looking_at(-sun_dir, Vector3.UP)
	var day_col := Color(1.0, 0.96, 0.88)
	var gold_col := Color(1.0, 0.62, 0.32)
	var moon_col := Color(0.55, 0.65, 0.9)
	sun.light_color = moon_col.lerp(day_col.lerp(gold_col, golden), day)
	sun.light_energy = lerpf(0.45, 1.25, day) * lerpf(1.0, 0.85, golden)
	sky_mat.set_shader_parameter("sun_dir", dir)
	sky_mat.set_shader_parameter("moon_dir", Vector3(-dir.x, 0.6, -dir.z).normalized())
	sky_mat.set_shader_parameter("night", night)
	sky_mat.set_shader_parameter("star_amount", clampf(night * 1.4 - 0.3, 0.0, 1.0))
	sky_mat.set_shader_parameter("top_color", Color(0.03, 0.05, 0.13).lerp(Color(0.2, 0.42, 0.78), day))
	sky_mat.set_shader_parameter("horizon_color", Color(0.09, 0.11, 0.2).lerp(Color(0.62, 0.74, 0.88).lerp(Color(0.98, 0.62, 0.38), golden * 0.8), day))
	sky_mat.set_shader_parameter("glow_color", Color(1.0, 0.5, 0.25))
	sky_mat.set_shader_parameter("glow_amount", golden)
	sky_mat.set_shader_parameter("sun_color", day_col.lerp(gold_col, golden))
	sky_mat.set_shader_parameter("sky_energy", lerpf(0.25, 1.0, day))
	sky_mat.set_shader_parameter("cloud_lit", Color(1, 1, 1).lerp(Color(1.0, 0.7, 0.5), golden))
	env.fog_light_color = Color(0.06, 0.07, 0.12).lerp(Color(0.68, 0.76, 0.86).lerp(Color(0.95, 0.68, 0.48), golden), day)
	env.fog_sun_scatter = 0.25 * golden
	env.ambient_light_energy = lerpf(0.85, 1.0, day) # Forza's nights stay readable: a blue moonlit town
	env.glow_hdr_threshold = lerpf(0.95, 0.7, night)
	# streetlamps, windows and headlights after dusk
	var lamps_on := clampf((night - 0.35) * 3.0, 0.0, 1.0)
	if builder:
		if builder.lamp_material:
			builder.lamp_material.emission_energy_multiplier = 6.0 * lamps_on
		for m in builder.night_materials:
			m.set_shader_parameter("night", lamps_on)
	for h in headlights:
		h.light_energy = 7.0 * clampf(night * 1.6 - 0.2, 0.0, 1.0)
	for l in lamp_lights:
		l.light_energy = 4.0 * lamps_on
		l.visible = lamps_on > 0.02

func _build_headlights() -> void:
	for x: float in [-0.5, 0.5]:
		var s := SpotLight3D.new()
		s.position = Vector3(x, 0.66, -1.75)
		s.spot_range = 70.0
		s.spot_angle = 28.0
		s.spot_attenuation = 0.8
		s.light_color = Color(1.0, 0.95, 0.82)
		s.shadow_enabled = false
		s.rotation = Vector3(deg_to_rad(-4.0), 0.0, 0.0)
		car_visual.add_child(s)
		headlights.append(s)

func _build_lamp_lights() -> void:
	for i in LAMP_LIGHTS:
		var l := OmniLight3D.new()
		l.omni_range = 20.0
		l.omni_attenuation = 1.4
		l.light_color = Color(1.0, 0.8, 0.52)
		l.shadow_enabled = false
		l.visible = false
		world.add_child(l)
		lamp_lights.append(l)

## The nearest street lamps get real lights (a pool follows the car).
func _place_lamp_lights() -> void:
	if builder == null or builder.lamp_spots.is_empty() or night < 0.3:
		return
	var p := Vector3(drive.car.x, drive.z, drive.car.y)
	var best := []
	for k in builder.lamp_spots.size():
		var q := builder.lamp_spots[k]
		var d := Vector2(q.x - p.x, q.z - p.z).length_squared()
		if d < 160000.0:
			best.append([d, q])
	best.sort_custom(func(a, b): return a[0] < b[0])
	for i in lamp_lights.size():
		if i < best.size():
			lamp_lights[i].position = best[i][1] + Vector3.DOWN * 0.6
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
		var open_ := i <= unlocked
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
	_update_markers()

func _update_markers() -> void:
	var list := []
	for e in events:
		var st: Dictionary = Campaign.get_stage(e.stage)
		var info := "%s · %s · %s" % [e.title, SPOT_NOTE.get(e.spot, ""), "Done" if e.done else ("Open" if e.open else "Locked")]
		list.append({"pos": e.pos, "color": e.color, "label": "%d. %s" % [e.stage + 1, String(st.track).capitalize()], "info": info})
	hud.set_markers(list)

func _next_open_event() -> int:
	var prog := Campaign.load_progress()
	var unlocked := int(prog.get("unlocked", 0))
	for k in events.size():
		if events[k].stage == unlocked:
			return k
	return 0 if not events.is_empty() else -1

func _spawn(spawn) -> void:
	var p := Vector2.ZERO
	var h := 0.0
	var found := false
	if spawn is int:
		for e in events:
			if e.stage == spawn:
				# back at the beacon, rolled a little on, facing the way the stage left
				h = e.heading + PI
				p = (e.pos as Vector2) + Vector2(cos(h), sin(h)) * 14.0
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
	drive.place(p, h)
	drive.respawn() if map.road_at(p.x, p.y, -INF, 2.0).is_empty() else null
	_prev_pos = Vector3(drive.car.x, drive.z, drive.car.y)
	_prev_heading = drive.car.heading
	var f := Vector3(cos(drive.car.heading), 0.0, sin(drive.car.heading))
	cam_pos = _prev_pos - f * 7.0 + Vector3.UP * 2.6
	cam_vel_dir = Vector2(f.x, f.z)
	_apply_time()
	if gps_target < 0:
		gps_target = _next_open_event()
	_recompute_route()

func _check_events() -> void:
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
	var st: Dictionary = Campaign.get_stage(ev.stage)
	var target := "Win the race" if int(st.target_pos) == 1 else "Finish P%d or better" % int(st.target_pos)
	var body := "%s\n\n%s · %d laps · %s · %d rivals (%s)\nTarget: %s · Trophy: %s" % [st.desc, SPOT_NOTE.get(ev.spot, ""),
		int(st.laps), String(st.weather).capitalize(), int(st.opponents), String(st.difficulty).capitalize(), target, st.trophy]
	var hint := "ENTER  ▸  START STAGE" if ev.open else "LOCKED · clear the stages before it first"
	hud.show_event(String(st.act_name).to_upper(), String(st.title), body, hint, ev.color)

func _start_active_event() -> void:
	if active_event < 0:
		return
	var ev: Dictionary = events[active_event]
	if not ev.open:
		return
	_save()
	stage_requested.emit(int(ev.stage))

# ================================================================================================ speed traps, discovery

func _build_traps() -> void:
	# the long straights of the main roads, at least 600 m apart
	var cands := []
	for ri in map.road_pts.size():
		if not map.road_kind[ri] in ["secondary", "tertiary", "primary", "unclassified"]:
			continue
		var pts := map.road_pts[ri]
		var i := 0
		while i < pts.size() - 1:
			var j := i
			var run := 0.0
			var d0 := (pts[i + 1] - pts[i]).normalized()
			while j < pts.size() - 1 and (pts[j + 1] - pts[j]).normalized().dot(d0) > 0.995:
				run += pts[j].distance_to(pts[j + 1])
				j += 1
			if run > 220.0:
				var mid := pts[i].lerp(pts[j], 0.5)
				cands.append([run, mid, d0, ri])
			i = maxi(j, i + 1)
	cands.sort_custom(func(a, b): return a[0] > b[0])
	for c in cands:
		var ok := true
		for t in traps:
			if (t.pos as Vector2).distance_to(c[1]) < 600.0:
				ok = false
		if ok:
			var name := map.road_name[c[3]]
			traps.append({"id": "trap_%d_%d" % [int(c[1].x), int(c[1].y)], "pos": c[1], "dir": c[2],
				"name": street_label(name) if name != "" else "Speed trap"})
			_add_trap_sign(c[1], c[2], c[3])
		if traps.size() >= 9:
			break

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
			var kmh := drive.speed_kmh()
			var best := float(progress.traps.get(t.id, 0.0))
			var stars := 3 if kmh >= 120.0 else (2 if kmh >= 100.0 else (1 if kmh >= 80.0 else 0))
			var star_txt := "★".repeat(stars) + "☆".repeat(3 - stars)
			var sub := "%s · %s%s" % [t.name, star_txt, "  NEW BEST" if kmh > best + 0.5 else "  best %d km/h" % int(best)]
			hud.notify("SPEED TRAP  %d KM/H" % int(round(kmh)), sub, Color("#4aa3ff"))
			if kmh > best:
				progress.traps[t.id] = snappedf(kmh, 0.1)
				_add_fans(int(kmh * 4.0), "")
		_trap_near[t.id] = near

func _check_discovery() -> void:
	var cp := Vector2(drive.car.x, drive.car.y)
	if not drive.road.is_empty():
		var ri: int = drive.road.road
		if not progress.roads.has(ri):
			progress.roads[ri] = true
			if progress.roads.size() % 50 == 0:
				hud.notify("ROADS DRIVEN  %d / %d" % [progress.roads.size(), map.road_pts.size()], "Every street of Brzeszcze, one at a time")
		hud.set_street(street_label(map.road_name[ri]))
	for pl in map.places:
		if not String(pl.k) in DISCOVER_KINDS or String(pl.name) == "":
			continue
		var name := String(pl.name)
		if progress.landmarks.has(name):
			continue
		if Vector2(pl.x, pl.y).distance_to(cp) < 70.0:
			progress.landmarks[name] = true
			hud.notify("DISCOVERED", name, OpenWorldHud.GOLD)
			_add_fans(1000, "")

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
	chain_idle = 0.0
	chain_label = label

func _skill_event(points: float, label: String) -> void:
	_skill(points, label)
	_chain_events += 1
	chain_mult = minf(5.0, 1.0 + _chain_events / 3.0)

func _update_skills(dt: float) -> void:
	var car := drive.car
	var v := Vector2(car.vx, car.vy).length()
	if v > 8.0 and not drive.airborne:
		var vel_h := atan2(car.vy, car.vx)
		var slip := absf(wrapf(vel_h - car.heading, -PI, PI))
		if slip > 0.26 and slip < 1.9:
			_skill(dt * v * 3.6 * slip * 6.0, "DRIFT")
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
	if crashed and chain_points > 0.0:
		hud.notify("CHAIN LOST", "Crashed with %d fans in the chain" % int(chain_points * chain_mult), Color("#ff4d4d"))
		chain_points = 0.0
		_chain_events = 0
		chain_mult = 1.0
	chain_idle += dt
	if chain_points > 0.0 and chain_idle > CHAIN_IDLE:
		var banked := int(chain_points * chain_mult)
		_add_fans(banked, "SKILL CHAIN" if banked >= 500 else "")
		progress.best_chain = maxi(progress.best_chain, banked)
		chain_points = 0.0
		_chain_events = 0
		chain_mult = 1.0
	var shown := int(chain_points * chain_mult)
	hud.set_chain(shown, "%s  ×%.1f" % [chain_label, chain_mult] if shown > 0 else "")

func _add_fans(n: int, banner: String) -> void:
	progress.fans += n
	if banner != "":
		hud.notify("+%s FANS" % OpenWorldHud._thousands(n), banner, OpenWorldHud.GOLD)

# ================================================================================================ GPS

func _recompute_route() -> void:
	if gps_target < 0 or gps_target >= events.size() or drive == null:
		route = PackedVector2Array()
	else:
		route = map.route(Vector2(drive.car.x, drive.car.y), events[gps_target].pos)
	hud.set_route(route)
	_update_route_mesh()

func _off_route() -> bool:
	if route.size() < 2:
		return gps_target >= 0
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
		hud.update_drive(drive.speed_kmh(), _gear_shown(), drive.car.rpm, drive.model.spec.limiter, Vector2(drive.car.x, drive.car.y), drive.car.heading, delta)
		return
	_read_input(delta)
	accumulator += minf(delta, 0.1)
	var steps := 0
	while accumulator >= TICK and steps < 24:
		_prev_pos = Vector3(drive.car.x, drive.z, drive.car.y)
		_prev_heading = drive.car.heading
		drive.step(TICK, throttle, brake, steer, shift_up, shift_down)
		shift_up = false
		shift_down = false
		traffic.step(TICK, drive)
		accumulator -= TICK
		steps += 1
	if steps >= 24:
		accumulator = 0.0
	if drive.wants_respawn:
		hud.notify("BACK ON THE ROAD", "The Seicento doesn't swim", Color("#4aa3ff"))
		drive.respawn()
	hour = fmod(hour + delta * DAY_RATE, 24.0)
	_apply_time()
	_sync_car(delta)
	_update_camera(delta)
	_update_skills(delta)
	_check_events()
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
		_lamp_t = 0.6
		_place_lamp_lights()
	_route_t -= delta
	if _route_t <= 0.0:
		_route_t = 0.5
		if gps_target >= 0 and _off_route():
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
	car_visual.sync(drive.car, delta, 0.0, night, false)

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
	cam_vel_dir = cam_vel_dir.lerp(want_dir, 1.0 - exp(-delta * 4.0)).normalized()
	var d3 := Vector3(cam_vel_dir.x, 0.0, cam_vel_dir.y)
	var kmh := absf(car.speed) * 3.6
	match cam_mode:
		1:
			var target := p - d3 * 10.5 + Vector3.UP * 3.6
			cam_pos = cam_pos.lerp(target, 1.0 - exp(-delta * 5.0))
			camera.position = cam_pos
			camera.look_at(p + d3 * 5.0 + Vector3.UP * 1.0, Vector3.UP)
			camera.fov = 66.0 + kmh * 0.06
		2:
			camera.global_transform = car_visual.global_transform * Transform3D(Basis(), Vector3(0.0, 1.22, -0.35))
			camera.rotate_object_local(Vector3.RIGHT, deg_to_rad(-2.0))
			camera.fov = 78.0 + kmh * 0.05
		_:
			var back := 6.0 + kmh * 0.012
			var target := p - d3 * back + Vector3.UP * (2.15 + kmh * 0.004)
			cam_pos = cam_pos.lerp(target, 1.0 - exp(-delta * 7.0))
			# keep it out of the buildings and above the ground
			var c2 := Vector2(cam_pos.x, cam_pos.z)
			if map.inside_building(c2):
				cam_pos = cam_pos.lerp(p + Vector3.UP * 2.0, 0.5)
			cam_pos.y = maxf(cam_pos.y, map.ground(cam_pos.x, cam_pos.z) + 0.8)
			camera.position = cam_pos
			camera.look_at(p + d3 * 3.5 + Vector3.UP * 1.05, Vector3.UP)
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
		if absf(st_pad) > 0.02 or thr_pad > 0.02 or brk_pad > 0.02:
			steer = st_pad
			throttle = thr_pad
			brake = brk_pad
			return
	var up := Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)
	var down := Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_SPACE)
	var left := Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)
	var right := Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)
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
				hud.toggle_map(false)
			"left", "up":
				hud.map_sel = posmod(hud.map_sel - 1, maxi(events.size(), 1))
				hud.big_overlay.queue_redraw()
			"right", "down":
				hud.map_sel = posmod(hud.map_sel + 1, maxi(events.size(), 1))
				hud.big_overlay.queue_redraw()
			"accept":
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
			gps_target = _next_open_event()
			_recompute_route()
			if gps_target >= 0:
				hud.notify("ROUTE SET", String(events[gps_target].title), OpenWorldHud.PURPLE)
		"camera":
			cam_mode = (cam_mode + 1) % 3
		"reset":
			drive.respawn()
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
			JOY_BUTTON_B: return "back" if (paused or hud.map_open) else ""
			JOY_BUTTON_A: return "accept"
			JOY_BUTTON_BACK: return "map"
			JOY_BUTTON_Y: return "camera"
			JOY_BUTTON_X: return "reset"
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
	if on and audio:
		audio.update_car(null, false)

func _pause_action(action: String) -> void:
	match action:
		"resume":
			_set_paused(false)
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
			drive.respawn()
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
