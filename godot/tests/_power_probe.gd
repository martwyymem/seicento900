## Windowed power probe (dev tool): runs the real game scene through a 16-car race (co-driver driving) and the open
## world's busiest spot under several graphics set-ups, and prints one PHASE line per set-up for
## tools/power_sampler.py, which adds GPU watts and CPU cores from the same time window.
##   python3 tools/power_sampler.py -- godot --path godot --audio-driver Dummy --always-on-top \
##       --resolution 1600x900 -s tests/_power_probe.gd
## MEASURE=40 (seconds per phase), ONLY=race|world. Saves go to the dev sandbox.
extends SceneTree

const SETTLE := 8.0
## fps: index into game.FPS_LIMITS (0 30, 1 60, 2 120, 3 unlimited); upscaler 0 off, 1 FSR 1, 3 MetalFX spatial;
## upscale_preset 1 67 %, 3 50 %; antialiasing 0 SMAA, 1 FXAA; reflections 0 off, 1 screen-space, 2 ray-traced
const USER := {"upscaler": 3, "upscale_preset": 1, "antialiasing": 0, "ssao": true, "reflections": 1, "shadows": true,
	"quality": 2, "fps": 2}
const LOW := {"upscaler": 1, "upscale_preset": 3, "antialiasing": 1, "ssao": false, "reflections": 0, "shadows": true,
	"quality": 0, "fps": 1}

var game
var measure_s := 40.0

func _v(base: Dictionary, over: Dictionary) -> Dictionary:
	var d := base.duplicate()
	d.merge(over, true)
	return d

var allow_warp := false

func _keep() -> void:
	AudioServer.set_bus_mute(0, true) # silent under a real audio driver too
	if game.race != null and not allow_warp and game.race.warp != 1:
		game.race.warp = 1 # a stray key press must not time-warp the race
	game._app_focused = true
	if game.paused:
		game._set_paused(false)
	if game.open_world != null and game.open_world.paused:
		game.open_world._set_paused(false)

func _wait(seconds: float) -> void:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < seconds * 1000.0:
		_keep()
		await process_frame

func _apply(v: Dictionary) -> void:
	game.graphics_upscaler = v.upscaler
	game.graphics_upscale_preset = v.upscale_preset
	game.graphics_antialiasing = v.antialiasing
	game.graphics_ssao = v.ssao
	game.graphics_reflections = v.reflections
	game.graphics_shadows = v.shadows
	game.graphics_quality = v.quality
	game.graphics_fps_limit = v.fps
	game.graphics_vsync = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if is_instance_valid(game.world_view):
		game.world_view.apply_graphics(v.quality)
	game._apply_upscaling()
	game._apply_world_graphics_settings()
	if game.open_world != null:
		var ow = game.open_world
		var src: SubViewport = game.render_viewport
		ow.viewport.msaa_3d = src.msaa_3d
		ow.viewport.screen_space_aa = src.screen_space_aa
		ow.viewport.use_taa = src.use_taa
		ow.viewport.scaling_3d_mode = src.scaling_3d_mode
		ow.viewport.scaling_3d_scale = src.scaling_3d_scale
		ow.apply_graphics(v.quality, v.ssao)
		if ow.env:
			ow.env.ssr_enabled = v.reflections == 1
	if v.has("scale"): # render-resolution override: 1.27 in a 1600x900 window draws as many pixels as native Retina at 67 %
		game.render_viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		game.render_viewport.scaling_3d_scale = v.scale
		if game.open_world != null:
			game.open_world.viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			game.open_world.viewport.scaling_3d_scale = v.scale

## One line a second for tools/power_sampler.py to join with its GPU samples: what is on screen right now.
func _tick_line() -> void:
	var r: Race = game.race
	var where := "world"
	if game.open_world == null or not game.open_world.active:
		where = "s=%.0f wet=%.2f tod=%.2f cam=%d" % [r.player.s if r else -1.0, r.weather.wet if r else -1.0,
			r.time_of_day if r else -1.0, game.world_view.camera_mode if is_instance_valid(game.world_view) else -1]
	print("TICK %.3f draws=%d prims=%dk objs=%d %s" % [Time.get_unix_time_from_system(),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)) / 1000,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)), where])

## Parks the window in the bottom-right corner of the screen, fully visible (where the user wants probe windows).
func _corner() -> void:
	var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var outer := DisplayServer.window_get_size_with_decorations()
	DisplayServer.window_set_position(screen.end - outer)

func _phase(name: String, v: Dictionary, freeze := false) -> void:
	_apply(v)
	if freeze:
		game.set_process(false)
		if game.open_world != null:
			game.open_world.process_mode = Node.PROCESS_MODE_DISABLED
			game.open_world.viewport.process_mode = Node.PROCESS_MODE_ALWAYS
	if freeze:
		Engine.max_fps = game.FPS_LIMITS[v.fps].fps # _sync_rendering no longer runs
	await _wait(SETTLE)
	var t0 := Time.get_unix_time_from_system()
	var start := Time.get_ticks_msec()
	var frames := 0
	var proc := 0.0
	var phys := 0.0
	var next_tick := start + 1000
	while Time.get_ticks_msec() - start < measure_s * 1000.0:
		_keep()
		await process_frame
		frames += 1
		if Time.get_ticks_msec() >= next_tick:
			next_tick += 1000
			_tick_line()
		proc += Performance.get_monitor(Performance.TIME_PROCESS)
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	var t1 := Time.get_unix_time_from_system()
	var secs := (Time.get_ticks_msec() - start) / 1000.0
	print("PHASE %s %.3f %.3f fps=%.1f proc=%.2fms phys=%.2fms draws=%d prims=%dk scale=%.2f win=%s nodes=%d objs=%d" % [name, t0, t1,
		frames / secs, proc / frames * 1000.0, phys / frames * 1000.0,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)) / 1000,
		game.render_viewport.scaling_3d_scale, str(DisplayServer.window_get_size()).replace(" ", ""),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))])
	if freeze:
		game.set_process(true)
		if game.open_world != null:
			game.open_world.process_mode = Node.PROCESS_MODE_INHERIT

func _race() -> void:
	game.opponents_picker.value = 15
	game.laps_picker.value = 20
	await _wait(1.0)
	for k in 6000:
		if not game._strategy_pending:
			break
		await process_frame
	game._start_race()
	for k in 12000:
		await process_frame
		_keep()
		if not game._starting:
			break
	if game.race == null:
		print("PROBE: no race: ", game.status_label.text)
		return
	game.race.set_autopilot(true)
	print("PROBE race on %s, %d cars" % [game.race.track.name if "name" in game.race.track else "?", game.race.cars.size()])
	await _wait(15.0) # off the grid
	if OS.get_environment("ONLY") == "shots":
		await _shots()
		return
	if OS.get_environment("ONLY") == "stand":
		await _stand()
		return
	if OS.get_environment("ONLY") == "trees":
		await _trees()
		return
	if OS.get_environment("ONLY") == "surr":
		await _surr()
		return
	if OS.get_environment("ONLY") == "spot":
		await _spots()
		return
	if OS.get_environment("ONLY") == "long":
		for i in int(OS.get_environment("PHASES") if OS.get_environment("PHASES") != "" else "12"):
			await _phase("long_%02d_t%ds" % [i, int(game.race.race_time)], USER)
		return
	await _phase("race_user_ssr_120", USER)
	await _phase("race_user_rt_120", _v(USER, {"reflections": 2}))
	await _phase("race_user_ssr_60", _v(USER, {"fps": 1}))
	await _phase("race_user_60_frozen", _v(USER, {"fps": 1}), true)
	await _phase("race_noSSR_noAO_60", _v(USER, {"fps": 1, "reflections": 0, "ssao": false}))
	await _phase("race_low_60", LOW)
	await _phase("race_low_30", _v(LOW, {"fps": 0}))
	await _phase("race_nativepx_120", _v(USER, {"scale": 1.27}))
	await _phase("race_nativepx_60", _v(USER, {"scale": 1.27, "fps": 1}))
	await _phase("race_user_ssr_120_late", USER)
	game._set_paused(true)
	game._pause_action("retire")
	await _wait(3.0)

## Drives (warped) to a point on the lap and freezes the race there, so the view holds still.
func _goto(s_target: float) -> void:
	game.set_process(true)
	allow_warp = true
	var r: Race = game.race
	var lap0: int = r.player.lap
	while not (r.player.s >= s_target and r.player.s < s_target + 400.0):
		r.warp = 10 if absf(r.player.s - s_target) > 600.0 else 1
		await process_frame
		game._app_focused = true
		if game.paused:
			game._set_paused(false)
	r.warp = 1
	allow_warp = false
	await _wait(1.0)
	game.set_process(false)
	Engine.max_fps = 120

## A/B at a frozen view: the cheap stretch, then the expensive one with each world group hidden in turn.
func _spots() -> void:
	MEASURE_SHORT = true
	await _goto(3000.0)
	await _frozen_phase("spot_s3000_base")
	await _goto(8700.0)
	await _frozen_phase("spot_s8700_base")
	var wv = game.world_view
	var groups := []
	for c in wv.get_children():
		if c is Node3D and c.visible and c.name in ["Cars", "Skidmarks"]:
			groups.append(c)
	var track: Node = wv.get_node_or_null("Track")
	if track:
		for c in track.get_children():
			if c is Node3D and c.visible:
				groups.append(c)
	print("PROBE groups: ", ", ".join(groups.map(func(c): return "%s(%d)" % [c.name, c.get_child_count()])))
	for c in groups:
		await _frozen_phase("base_before_" + str(c.name)) # A/B pairs: the GPU's clock and other apps drift
		c.visible = false
		await _frozen_phase("hide_" + str(c.name))
		c.visible = true
	var sun0: DirectionalLight3D = wv.get("sun") as DirectionalLight3D
	if sun0:
		sun0.visible = false
		await _frozen_phase("hide_sun")
		sun0.visible = true
	var env := wv.get("world_environment") as Environment
	if env:
		for key in ["ssao_enabled", "ssr_enabled", "glow_enabled", "fog_enabled", "volumetric_fog_enabled", "sdfgi_enabled", "ssil_enabled"]:
			if env.get(key):
				env.set(key, false)
				await _frozen_phase("env_off_" + key)
				env.set(key, true)
	var sun := wv.get("sun") as DirectionalLight3D
	if sun and sun.shadow_enabled:
		sun.shadow_enabled = false
		await _frozen_phase("sun_shadows_off")
		sun.shadow_enabled = true
	await _frozen_phase("spot_s8700_base_again")

var MEASURE_SHORT := false

func _geoms(n: Node, out: Array) -> Array:
	if n is GeometryInstance3D:
		out.append(n)
	for c in n.get_children():
		_geoms(c, out)
	return out

## Screenshots of the same frozen view with the trees' stand-in shadows and with their real ones (/tmp/trees_*.png).
func _shots() -> void:
	for s_at in [8700.0, 2000.0]:
		await _goto(s_at)
		var sur = game.world_view.surroundings
		for q in [2, 3]:
			sur.set_tree_shadows(q)
			await _wait(1.0)
			await RenderingServer.frame_post_draw
			var img := root.get_viewport().get_texture().get_image()
			img.save_png("/tmp/trees_s%d_%s.png" % [int(s_at), "standins" if q == 2 else "real"])
		sur.set_tree_shadows(game.world_view.quality)
	print("PROBE shots saved")

## The trees' shadow stand-ins (High's default) against the real trees casting (Ultra's) and no tree shadows.
func _stand() -> void:
	await _goto(8700.0)
	var sur = game.world_view.surroundings
	print("PROBE tree tiles: %d" % sur._tree_tiles.size())
	for round in 2:
		sur.set_tree_shadows(2)
		await _frozen_phase("stand_ins_%d" % round)
		sur.set_tree_shadows(3)
		await _frozen_phase("real_trees_%d" % round)
		for t in sur._tree_tiles:
			t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		await _frozen_phase("no_tree_shadows_%d" % round)
	sur.set_tree_shadows(game.world_view.quality)

## Tree fixes at the expensive spot, each against a fresh base: no tree shadows, shorter draw distance.
func _trees() -> void:
	await _goto(8700.0)
	var trees: Node = game.world_view.find_child("Trees", true, false)
	var all: Array = _geoms(trees, []).filter(func(g): return not str(g.name).ends_with("Shadow")) # not the stand-ins
	print("PROBE tree multimeshes: %d, instances %d" % [all.size(), all.reduce(func(a, g): return a + g.multimesh.instance_count, 0)])
	for round in 2:
		await _frozen_phase("base_a%d" % round)
		for g in all:
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		await _frozen_phase("trees_no_shadow_%d" % round)
		for g in all:
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		await _frozen_phase("base_b%d" % round)
		for g in all:
			g.visibility_range_end = 400.0
		await _frozen_phase("trees_400m_%d" % round)
		for g in all:
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		await _frozen_phase("trees_400m_no_shadow_%d" % round)
		for g in all:
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			g.visibility_range_end = 1000.0

## Drill into the Surroundings at the expensive end of the S1 Sprint lap: each part, its shadows, the trees' fade.
func _surr() -> void:
	await _goto(8700.0)
	var surr: Node = game.world_view.find_child("Surroundings", true, false)
	var parts := []
	for c in surr.get_children():
		if c is Node3D and c.visible:
			parts.append(c)
	print("PROBE parts: ", ", ".join(parts.map(func(c): return "%s(%d geoms)" % [c.name, _geoms(c, []).size()])))
	for c in parts:
		await _frozen_phase("base_before_" + str(c.name))
		c.visible = false
		await _frozen_phase("hide_" + str(c.name))
		c.visible = true
	var all: Array = _geoms(surr, [])
	var casts := all.map(func(g): return g.cast_shadow)
	await _frozen_phase("base_before_noshadow")
	for g in all:
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	await _frozen_phase("surr_casts_no_shadow")
	for i in all.size():
		all[i].cast_shadow = casts[i]
	var fades := all.map(func(g): return g.visibility_range_fade_mode)
	await _frozen_phase("base_before_nofade")
	for g in all:
		g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	await _frozen_phase("surr_fade_disabled")
	for i in all.size():
		all[i].visibility_range_fade_mode = fades[i]
	await _frozen_phase("base_end")

func _frozen_phase(name: String) -> void:
	await _wait(2.0)
	var t0 := Time.get_unix_time_from_system()
	await _wait(8.0)
	var t1 := Time.get_unix_time_from_system()
	print("PHASE %s %.3f %.3f s=%.0f draws=%d prims=%dk" % [name, t0, t1, game.race.player.s,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)) / 1000])

func _world() -> void:
	game._return_to_setup()
	await _wait(1.0)
	await game._enter_open_world("station")
	await _wait(10.0)
	print("PROBE open world at station")
	await _phase("world_user_ssr_120", USER)
	await _phase("world_user_ssr_60", _v(USER, {"fps": 1}))
	await _phase("world_user_60_frozen", _v(USER, {"fps": 1}), true)
	await _phase("world_low_60", LOW)
	await _phase("world_nativepx_120", _v(USER, {"scale": 1.27}))

func _initialize() -> void:
	Brain.use_disk = false
	if OS.get_environment("MEASURE") != "":
		measure_s = float(OS.get_environment("MEASURE"))
	game = load("res://ui/game.tscn").instantiate()
	root.add_child(game)
	await _wait(1.0)
	_corner()
	if game.retro_pipeline:
		game.retro_pipeline.set_mode(2) # the player's look (NFS Most Wanted grade)
	var only := OS.get_environment("ONLY")
	if only != "world":
		await _race()
	if only != "race" and only != "long":
		await _world()
	quit()
