## Options → Resolution, Aspect ratio and Audio: the volume buses and where each sound plays, 100 % = 0 dB,
## the settings' round trip through graphics.cfg, the canvas each aspect ratio sets, and the pickers' place in
## the controller's focus order.
extends RefCounted

var completed := false

func run() -> Array:
	var errors: Array[String] = []
	var saved_levels: Dictionary = AudioSettings.levels.duplicate()
	_volumes(errors)
	_routing(errors)
	_presets(errors)
	_hud_layout(errors)
	var hud_width_before := HudLayout.hud_width
	_game_options(errors)
	HudLayout.hud_width = hud_width_before
	AudioSettings.levels = saved_levels
	AudioSettings.apply()
	completed = true
	return errors

func _presets(errors: Array[String]) -> void:
	for i in GraphicsPresets.PRESETS.size():
		var p: Dictionary = GraphicsPresets.preset(i)
		if GraphicsPresets.match_index(p) != i:
			errors.append("preset %s should recognise itself, got %d" % [GraphicsPresets.NAMES[i], GraphicsPresets.match_index(p)])
		var tweaked := p.duplicate()
		tweaked.shadows = not p.shadows
		if GraphicsPresets.match_index(tweaked) != GraphicsPresets.CUSTOM:
			errors.append("switching shadows off the %s preset should read as Custom" % GraphicsPresets.NAMES[i])
	var high := GraphicsPresets.preset(2).duplicate()
	high.upscale_preset = 3 # no upscaler on: the render-resolution step means nothing
	if GraphicsPresets.match_index(high) != 2:
		errors.append("High should not care about the render-resolution step while the upscaler is off")
	var low := GraphicsPresets.preset(0).duplicate()
	low.upscale_preset = 1
	if GraphicsPresets.match_index(low) != GraphicsPresets.CUSTOM:
		errors.append("Low with a different render resolution should read as Custom")
	# first run: a preset picked for the machine (never Ultra, unknown hardware gets the default High)
	var D := RenderingDevice
	for case in [["Apple M4 Pro", D.DEVICE_TYPE_INTEGRATED_GPU, 14, 2], ["Apple M1", D.DEVICE_TYPE_INTEGRATED_GPU, 8, 1],
			["Apple M2 Max", D.DEVICE_TYPE_INTEGRATED_GPU, 12, 2], ["Apple M3", D.DEVICE_TYPE_INTEGRATED_GPU, 8, 2],
			["Intel(R) UHD Graphics 620", D.DEVICE_TYPE_INTEGRATED_GPU, 8, 0], ["Intel(R) Iris(R) Xe Graphics", D.DEVICE_TYPE_INTEGRATED_GPU, 8, 1],
			["Intel(R) Arc(TM) A770 Graphics", D.DEVICE_TYPE_DISCRETE_GPU, 8, 2], ["AMD Radeon 780M", D.DEVICE_TYPE_INTEGRATED_GPU, 16, 1],
			["NVIDIA GeForce RTX 3060", D.DEVICE_TYPE_DISCRETE_GPU, 12, 2], ["llvmpipe (LLVM 15.0.7, 256 bits)", D.DEVICE_TYPE_CPU, 8, 0],
			["NVIDIA GeForce RTX 4090", D.DEVICE_TYPE_DISCRETE_GPU, 2, 0], ["", D.DEVICE_TYPE_OTHER, 8, 2]]:
		var got := GraphicsPresets.auto_pick(case[0], case[1], case[2])
		if got != case[3]:
			errors.append("first-run preset for %s should be %s, got %s" % [case[0], GraphicsPresets.NAMES[case[3]], GraphicsPresets.NAMES[got]])
	var costs := []
	for p in GraphicsPresets.PRESETS:
		costs.append(float(p.quality) + (1.0 if p.reflections > 0 else 0.0) + (1.0 if p.upscaler == 0 else 0.0))
	for i in range(1, costs.size()):
		if costs[i] < costs[i - 1] or GraphicsPresets.preset(i).ow_shadow_distance <= GraphicsPresets.preset(i - 1).ow_shadow_distance:
			errors.append("each preset should cost at least as much as the one below")
	var defaults := GraphicsPresets.preset(2)
	if defaults.upscaler != 0 or not defaults.ssao or not defaults.shadows or defaults.reflections != 0 or defaults.antialiasing != 0:
		errors.append("High should equal the game's defaults")

func _volumes(errors: Array[String]) -> void:
	if AudioSettings.db(100) != 0.0:
		errors.append("100%% should be exactly 0 dB, got %f" % AudioSettings.db(100))
	if AudioSettings.db(0) > -79.0 or absf(AudioSettings.db(50) - linear_to_db(0.5)) > 0.001:
		errors.append("0%% should be silent and 50%% half the amplitude: %f, %f" % [AudioSettings.db(0), AudioSettings.db(50)])
	if AudioSettings.step_names().size() != 11 or AudioSettings.step_names()[0] != "Off" or AudioSettings.step_names()[10] != "100%":
		errors.append("the volume pickers should run Off, 10%% .. 100%%: %s" % [AudioSettings.step_names()])
	AudioSettings.ensure_buses()
	for pair in AudioSettings.BUSES:
		var i := AudioServer.get_bus_index(pair[0])
		if i < 0 or AudioServer.get_bus_send(i) != StringName(pair[1]) or AudioServer.get_bus_index(pair[1]) >= i:
			errors.append("bus %s should exist and send to %s before it" % pair)
	for key in AudioSettings.levels:
		AudioSettings.levels[key] = 100
	AudioSettings.apply()
	for bus in ["Master", "Engine", "CarFx", "World"]:
		var i := AudioServer.get_bus_index(bus)
		if AudioServer.get_bus_volume_db(i) != 0.0 or AudioServer.is_bus_mute(i):
			errors.append("at 100%% the %s bus should be at 0 dB, unmuted" % bus)
	if AudioSettings.voice_volume(CoDriver.VOLUME) != CoDriver.VOLUME:
		errors.append("at 100% the co-driver should speak at his own volume")
	AudioSettings.set_level("effects", 0)
	AudioSettings.set_level("engine", 40)
	AudioSettings.set_level("master", 50)
	AudioSettings.set_level("voice", 50)
	var carfx := AudioServer.get_bus_index("CarFx")
	var world_bus := AudioServer.get_bus_index("World")
	var engine_bus := AudioServer.get_bus_index("Engine")
	var master_bus := AudioServer.get_bus_index("Master")
	if not AudioServer.is_bus_mute(carfx) or not AudioServer.is_bus_mute(world_bus) or not AudioSettings.effects_silent():
		errors.append("Effects at 0% should mute both CarFx and World buses")
	if AudioServer.get_bus_volume_db(carfx) > -79.0 or AudioServer.get_bus_volume_db(world_bus) > -79.0:
		errors.append("Effects at 0% should drop CarFx and World buses to silent dB")
	if absf(AudioServer.get_bus_volume_db(engine_bus) - linear_to_db(0.4)) > 0.001 or AudioServer.is_bus_mute(engine_bus):
		errors.append("Engine at 40% should be linear_to_db(0.4) and unmuted")
	if absf(AudioServer.get_bus_volume_db(master_bus) - linear_to_db(0.5)) > 0.001 or AudioServer.is_bus_mute(master_bus):
		errors.append("Master at 50% should be linear_to_db(0.5) and unmuted")
	if AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Car")) != 0.0:
		errors.append("the Car bus belongs to WorldAudio's camera mix: the options shouldn't touch it")
	if AudioSettings.voice_volume(80) != 20:
		errors.append("voice 50%% under master 50%% should speak at a quarter: %d" % AudioSettings.voice_volume(80))
	AudioSettings.set_level("master", 0)
	AudioSettings.set_level("engine", 0)
	if not AudioServer.is_bus_mute(master_bus) or AudioServer.get_bus_volume_db(master_bus) > -79.0:
		errors.append("Master at 0% should mute the Master bus")
	if not AudioServer.is_bus_mute(engine_bus) or AudioServer.get_bus_volume_db(engine_bus) > -79.0:
		errors.append("Engine at 0% should mute the Engine bus")
	if AudioSettings.voice_volume(CoDriver.VOLUME) != 0:
		errors.append("Master at 0% should silence co-driver voice too")
	AudioSettings.set_level("master", 80)
	AudioSettings.set_level("engine", 60)
	AudioSettings.set_level("effects", 70)
	if AudioServer.is_bus_mute(master_bus) or AudioServer.is_bus_mute(engine_bus) or AudioServer.is_bus_mute(carfx) or AudioServer.is_bus_mute(world_bus):
		errors.append("raising volumes above 0% should unmute every bus")
	AudioSettings.set_level("voice", 0)
	if AudioSettings.voice_volume(CoDriver.VOLUME) != 0:
		errors.append("voice at 0% should be silent")

## Each player on its bus: the engine on Engine, the player's car on CarFx, the world on World.
func _routing(errors: Array[String]) -> void:
	var root := (Engine.get_main_loop() as SceneTree).root
	var audio := RaceAudio.new()
	root.add_child(audio)
	if audio.player.bus != &"Engine":
		errors.append("RaceAudio's engine should play on the Engine bus, not %s" % audio.player.bus)
	var wa := WorldAudio.new(null)
	wa.world = Node3D.new()
	root.add_child(wa.world)
	root.add_child(wa)
	for v in [wa._kerb, wa._gravel, wa._grass, wa._scrape, wa._wind, wa._spray]:
		if v.player.bus != &"CarFx":
			errors.append("the player's car loop %s should play on CarFx" % v.player.stream.resource_path.get_file())
	for p in wa._car_shots:
		if p.bus != &"CarFx":
			errors.append("the player's own hits should play on CarFx")
	if wa._rain.player.bus != &"World":
		errors.append("rain should play on World")
	var spatial := wa._spatial("crowd", 10.0, 100.0)
	if spatial.bus != &"World":
		errors.append("the world's 3D sounds should play on World")
	var bad := []
	for n in wa.find_children("*", "AudioStreamPlayer", true, false) + wa.world.find_children("*", "AudioStreamPlayer3D", true, false):
		if not (n.bus in [&"CarFx", &"World"]):
			bad.append(n.bus)
	if not bad.is_empty():
		errors.append("WorldAudio players on unexpected buses: %s" % [bad])
	var world := wa.world
	wa.free()
	world.free()
	audio.free()

## HudLayout: the safe zone is centred and capped by the setting, the Hor+ FOV keeps 16:9's horizontal view.
func _hud_layout(errors: Array[String]) -> void:
	# safe zone: Full is everything, 21:9 and 16:9 cap the width and centre it, narrower windows are left whole
	for case in [[Vector2(1920, 1080), 0, 1920.0], [Vector2(1920, 1080), 1, 1920.0], [Vector2(1920, 1080), 2, 1920.0],
			[Vector2(1280, 1024), 2, 1280.0], [Vector2(2560, 1080), 1, 2520.0], [Vector2(2560, 1080), 2, 1920.0], [Vector2(2560, 1080), 0, 2560.0],
			[Vector2(5120, 1440), 0, 5120.0], [Vector2(5120, 1440), 1, 3360.0], [Vector2(5120, 1440), 2, 2560.0]]:
		var r := HudLayout.safe_rect(case[0], case[1])
		if absf(r.size.x - case[2]) > 1.0 or r.size.y != case[0].y or absf(r.position.x * 2.0 + r.size.x - case[0].x) > 1.0:
			errors.append("safe_rect(%s, %d) should be %d wide, centred and full height, got %s" % [case[0], case[1], case[2], r])
	# Hor+: the vertical FOV stays from 16:9 up, and grows below it so the horizontal FOV never drops under 16:9's
	var base := 70.0
	var h16 := HudLayout.camera_fov(base, 16.0 / 9.0)
	var h_ref := rad_to_deg(2.0 * atan(tan(deg_to_rad(base) * 0.5) * 16.0 / 9.0))
	for aspect in [16.0 / 9.0, 21.0 / 9.0, 32.0 / 9.0]:
		if absf(HudLayout.camera_fov(base, aspect) - base) > 0.001:
			errors.append("FOV at %.2f:1 should keep the vertical %.0f, got %.2f" % [aspect, base, HudLayout.camera_fov(base, aspect)])
	for aspect in [4.0 / 3.0, 5.0 / 4.0, 16.0 / 10.0]:
		var v := HudLayout.camera_fov(base, aspect)
		var h := rad_to_deg(2.0 * atan(tan(deg_to_rad(v) * 0.5) * aspect))
		if v <= base or absf(h - h_ref) > 0.01:
			errors.append("FOV at %.2f:1 should widen so the horizontal view equals 16:9's (%.2f), got v %.2f h %.2f" % [aspect, h_ref, v, h])
	if absf(h16 - base) > 0.001 or HudLayout.camera_fov(base, 0.0) != base:
		errors.append("FOV at 16:9 (or an unknown aspect) should be unchanged")
	# the camera helper reads its viewport and forces vertical-FOV scaling
	var vp := SubViewport.new()
	vp.size = Vector2i(1600, 1200)
	(Engine.get_main_loop() as SceneTree).root.add_child(vp)
	var cam := Camera3D.new()
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	vp.add_child(cam)
	var got := HudLayout.camera_fov_for(cam, base)
	if cam.keep_aspect != Camera3D.KEEP_HEIGHT or absf(got - HudLayout.camera_fov(base, 4.0 / 3.0)) > 0.001:
		errors.append("camera_fov_for in a 4:3 viewport should be %.2f with KEEP_HEIGHT, got %.2f (keep %d)" % [HudLayout.camera_fov(base, 4.0 / 3.0), got, cam.keep_aspect])
	vp.size = Vector2i(3200, 900)
	if absf(HudLayout.camera_fov_for(cam, base) - base) > 0.001:
		errors.append("camera_fov_for in a 32:9 viewport should keep the vertical FOV")
	vp.free()

## The options page: the settings survive a save and a load, the aspect ratios set the canvas, and the new
## pickers sit in the controller's focus order.
func _game_options(errors: Array[String]) -> void:
	var cfg_path := SaveData.path("graphics.cfg")
	var backup := FileAccess.get_file_as_bytes(cfg_path) if FileAccess.file_exists(cfg_path) else PackedByteArray()
	var root := (Engine.get_main_loop() as SceneTree).root
	var game = load("res://ui/game.tscn").instantiate()
	root.add_child(game)

	for key in ["master", "engine", "effects", "voice"]:
		if not game.audio_pickers.has(key):
			errors.append("Options should have a %s volume picker" % key)
	var items: Array = game._options_focus_items()
	var order := [game.display_mode_picker, game.resolution_picker, game.aspect_picker, game.hud_width_picker]
	for key in ["master", "engine", "effects", "voice"]:
		order.append(game.audio_pickers.get(key))
	var at := -1
	for c in order:
		var i: int = items.find(c)
		if i <= at:
			errors.append("%s should be reachable with the d-pad, after the one before it (%d <= %d)" % [c.name if c else "null", i, at])
		at = i
	if game.resolution_picker.item_count < 3 or not game.resolution_picker.get_item_text(0).begins_with("Auto") \
			or game.resolution_picker.get_item_text(1) != "Native (desktop)":
		errors.append("the resolution picker should list Auto, Native and the window's size")

	# save, scramble, load (including via the Options UI volume pickers and mute at 0%)
	var picker_targets := {"master": 7, "engine": 3, "effects": 0, "voice": 9} # 70%, 30%, Off, 90%
	for key in picker_targets:
		var picker: MenuSelector = game.audio_pickers[key]
		picker.select(picker_targets[key])
		picker.item_selected.emit(picker_targets[key])
	if absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master")) - linear_to_db(0.7)) > 0.001 \
			or AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")):
		errors.append("Options Master picker at 70% should set Master bus to linear_to_db(0.7), unmuted")
	if absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Engine")) - linear_to_db(0.3)) > 0.001 \
			or AudioServer.is_bus_mute(AudioServer.get_bus_index("Engine")):
		errors.append("Options Engine picker at 30% should set Engine bus to linear_to_db(0.3), unmuted")
	if not AudioServer.is_bus_mute(AudioServer.get_bus_index("CarFx")) \
			or not AudioServer.is_bus_mute(AudioServer.get_bus_index("World")):
		errors.append("Options Effects picker at Off should mute both CarFx and World buses")
	# HUD WIDTH: the default is 21:9, the picker sets it, and it survives a save and a load
	if HudLayout.hud_width != HudLayout.WIDTH_21_9 and not FileAccess.file_exists(cfg_path):
		errors.append("the HUD width should default to 21:9, got %d" % HudLayout.hud_width)
	if game.hud_width_picker.item_count != 3 or game.hud_width_picker.get_item_text(0) != "Full" or game.hud_width_picker.get_item_text(1) != "21:9" \
			or game.hud_width_picker.get_item_text(2) != "16:9":
		errors.append("the HUD WIDTH picker should list Full, 21:9 and 16:9")
	game.hud_width_picker.select(2)
	game.hud_width_picker.item_selected.emit(2)
	if HudLayout.hud_width != HudLayout.WIDTH_16_9:
		errors.append("picking 16:9 in HUD WIDTH should set it, got %d" % HudLayout.hud_width)
	game.graphics_resolution = Vector2i(1280, 720)
	game.graphics_aspect = 3
	game._save_graphics_settings()
	game.graphics_resolution = Vector2i(-1, -1)
	game.graphics_aspect = 0
	HudLayout.hud_width = HudLayout.WIDTH_FULL
	AudioSettings.levels = {"master": 100, "engine": 100, "effects": 100, "voice": 100}
	AudioSettings.apply()
	game._load_graphics_settings()
	# Fresh instance loads the saved graphics.cfg into its Options UI pickers and AudioServer buses
	var reloaded = load("res://ui/game.tscn").instantiate()
	root.add_child(reloaded)
	_restore_cfg(cfg_path, backup) # at once: other suites and agents share the sandbox and would load 21:9 from it
	if game.graphics_resolution != Vector2i(1280, 720) or game.graphics_aspect != 3:
		errors.append("resolution and aspect should load back: %s, %d" % [game.graphics_resolution, game.graphics_aspect])
	if HudLayout.hud_width != HudLayout.WIDTH_16_9 or game.hud_width_picker.selected != HudLayout.WIDTH_16_9 \
			or reloaded.hud_width_picker.selected != HudLayout.WIDTH_16_9:
		errors.append("the HUD width should load back as 16:9: %d, pickers %d / %d" % [HudLayout.hud_width, game.hud_width_picker.selected, reloaded.hud_width_picker.selected])
	# applied live: the menu's safe frame follows the setting
	game.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	game.size = Vector2(3200, 900)
	for mode in 3:
		game.hud_width_picker.item_selected.emit(mode)
		var want := HudLayout.safe_rect(game.size, mode)
		if not game.menu_safe_frame.position.is_equal_approx(want.position) or not game.menu_safe_frame.size.is_equal_approx(want.size):
			errors.append("HUD width %d should put the menu frame at %s, it is at %s %s" % [mode, want, game.menu_safe_frame.position, game.menu_safe_frame.size])
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.hud_width_picker.select(HudLayout.WIDTH_16_9)
	HudLayout.hud_width = HudLayout.WIDTH_16_9
	if AudioSettings.levels != {"master": 70, "engine": 30, "effects": 0, "voice": 90}:
		errors.append("the volumes should load back: %s" % [AudioSettings.levels])
	if absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master")) - linear_to_db(0.7)) > 0.001:
		errors.append("loading should apply Master volume to the Master bus")
	if absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Engine")) - linear_to_db(0.3)) > 0.001:
		errors.append("loading should apply Engine volume to the Engine bus")
	if not AudioServer.is_bus_mute(AudioServer.get_bus_index("CarFx")) or not AudioServer.is_bus_mute(AudioServer.get_bus_index("World")):
		errors.append("loading Effects=0% should keep CarFx and World buses muted")
	for key in picker_targets:
		var rp: MenuSelector = reloaded.audio_pickers[key]
		if rp.selected != picker_targets[key]:
			errors.append("reloaded Options %s picker should show %d, got %d" % [key, picker_targets[key], rp.selected])
	reloaded.free()

	# graphics presets: picking one sets what it covers, changing one of those by hand reads as Custom
	game._on_preset_selected(0)
	if game.graphics_preset != 0 or game.preset_picker.selected != 0 or game.graphics_upscaler != 1 or game.graphics_ssao \
			or game.graphics_antialiasing != 1 or game.graphics_quality != 0:
		errors.append("picking Low should set FSR 1, FXAA, no ambient occlusion and level 0: preset %d" % game.graphics_preset)
	if is_instance_valid(game.world_view) and game.world_view.quality != 0:
		errors.append("picking Low should lower the world's rendering level")
	game._on_ssao_toggled(true)
	if game.graphics_preset != GraphicsPresets.CUSTOM or game.preset_picker.selected != GraphicsPresets.CUSTOM:
		errors.append("turning ambient occlusion back on should leave the picker on Custom")
	game._on_preset_selected(3)
	game._load_graphics_settings()
	if game.graphics_preset != 3 or game.graphics_reflections != 1:
		errors.append("Ultra should survive a save and load: preset %d" % game.graphics_preset)
	game._on_preset_selected(2)
	_restore_cfg(cfg_path, backup)

	# fullscreen: the resolution is the 3D view's render target, fitted inside it; windowed leaves it alone
	game.graphics_display_mode = 1
	game.graphics_resolution = Vector2i(1920, 1080)
	if game._render_resolution(Vector2i(3024, 1964)) != Vector2i(1663, 1080):
		errors.append("fullscreen 1920×1080 on a 3024×1964 screen should render 1663×1080, got %s" % game._render_resolution(Vector2i(3024, 1964)))
	if game._render_resolution(Vector2i(1280, 800)) != Vector2i(1280, 800):
		errors.append("the render resolution should never go above the screen's")
	game.graphics_resolution = Vector2i.ZERO
	if game._render_resolution(Vector2i(3024, 1964)) != Vector2i(3024, 1964):
		errors.append("Native should render at the screen's resolution")
	# Auto (the default) caps the 3D view near 1080p's pixel count at the screen's shape, in a window too
	game.graphics_resolution = game.AUTO_RESOLUTION
	var auto_px: Vector2i = game._render_resolution(Vector2i(3024, 1964))
	if absi(auto_px.x - 1787) > 1 or absi(auto_px.y - 1160) > 1:
		errors.append("Auto on a 3024×1964 screen should render about 1787×1160, got %s" % auto_px)
	if game._render_resolution(Vector2i(1600, 900)) != Vector2i(1600, 900):
		errors.append("Auto should leave a view already under 1080p's pixel count alone")
	game.graphics_display_mode = 0
	auto_px = game._render_resolution(Vector2i(3024, 1890))
	if absi(auto_px.x - 1821) > 1 or absi(auto_px.y - 1138) > 1:
		errors.append("Auto should cap a maximised window too, got %s" % auto_px)
	game.graphics_display_mode = 1
	if game._resolution_options()[0] != game.AUTO_RESOLUTION or game._current_resolution() != game.AUTO_RESOLUTION:
		errors.append("Auto should head the resolution picker and be what an untouched setting shows")
	game.graphics_display_mode = 0

	# aspect ratios: the canvas and how it is fitted; the panels stay inside it
	var win: Window = game.get_window()
	var want := {0: [Vector2i(1600, 900), Window.CONTENT_SCALE_ASPECT_EXPAND], 1: [Vector2i(1600, 900), Window.CONTENT_SCALE_ASPECT_KEEP],
		2: [Vector2i(1600, 1000), Window.CONTENT_SCALE_ASPECT_KEEP], 3: [Vector2i(2100, 900), Window.CONTENT_SCALE_ASPECT_KEEP],
		4: [Vector2i(1600, 1200), Window.CONTENT_SCALE_ASPECT_KEEP]}
	for i in want:
		game.graphics_aspect = i
		game._apply_aspect()
		if win.content_scale_size != want[i][0] or win.content_scale_aspect != want[i][1]:
			errors.append("aspect %s should set a %s canvas (mode %d), got %s (mode %d)" % [game.ASPECTS[i].name, want[i][0], want[i][1], win.content_scale_size, win.content_scale_aspect])
		var visible: Rect2 = game.get_viewport().get_visible_rect()
		for panel in [game.menu_home, game.menu_header, game.options_panel, game.setup_panel, game.advanced_panel,
				game.car_panel, game.strategy_panel, game.repair_panel, game.repair_details, game.menu_prompt, game.hud]:
			if is_instance_valid(panel) and not visible.grow(1.0).encloses(panel.get_global_rect()):
				errors.append("at %s %s %s leaves the canvas %s" % [game.ASPECTS[i].name, panel.name, panel.get_global_rect(), visible])
	# 21:9 (2520x1080) and 4:3 (1440x1080) window shapes: letterbox canvas matches exact ratio and panels stay inside
	for pair in [[3, Vector2i(2520, 1080), 21.0 / 9.0], [4, Vector2i(1440, 1080), 4.0 / 3.0]]:
		var aspect_i: int = pair[0]
		var win_sz: Vector2i = pair[1]
		var ratio: float = pair[2]
		game.graphics_aspect = aspect_i
		game._apply_aspect()
		var cs := win.content_scale_size
		if absf(float(cs.x) / float(cs.y) - ratio) > 0.005:
			errors.append("aspect %s canvas %s does not match window %s ratio %.3f" % [game.ASPECTS[aspect_i].name, cs, win_sz, ratio])
		if win.content_scale_aspect != Window.CONTENT_SCALE_ASPECT_KEEP:
			errors.append("aspect %s should keep aspect (letterbox/pillarbox bars), got mode %d" % [game.ASPECTS[aspect_i].name, win.content_scale_aspect])
		var fit_r: Vector2i = game._render_resolution(win_sz)
		if fit_r.x > win_sz.x or fit_r.y > win_sz.y or absf(float(fit_r.x) / float(fit_r.y) - ratio) > 0.02:
			errors.append("render resolution for %s window should preserve ratio, got %s" % [win_sz, fit_r])
	game.graphics_aspect = 0
	game._apply_aspect()
	game.free()
	_restore_cfg(cfg_path, backup)

## Puts graphics.cfg back as it was before the suite (removes it if there was none). Called right after each check
## that saves, never only at the end: the dev sandbox is shared, and a killed run must not leave 21:9 behind.
func _restore_cfg(cfg_path: String, backup: PackedByteArray) -> void:
	if backup.is_empty():
		if FileAccess.file_exists(cfg_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(cfg_path))
	else:
		var f := FileAccess.open(cfg_path, FileAccess.WRITE)
		f.store_buffer(backup)
		f.close()
