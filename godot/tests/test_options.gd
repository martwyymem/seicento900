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
	_game_options(errors)
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
	if not AudioServer.is_bus_mute(carfx) or not AudioSettings.effects_silent():
		errors.append("Effects at 0% should mute the player's car effects (and the World bus, through WorldAudio)")
	if absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Engine")) - linear_to_db(0.4)) > 0.001:
		errors.append("Engine at 40% should be linear_to_db(0.4)")
	if AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Car")) != 0.0:
		errors.append("the Car bus belongs to WorldAudio's camera mix: the options shouldn't touch it")
	if AudioSettings.voice_volume(80) != 20:
		errors.append("voice 50%% under master 50%% should speak at a quarter: %d" % AudioSettings.voice_volume(80))
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
	var order := [game.display_mode_picker, game.resolution_picker, game.aspect_picker]
	for key in ["master", "engine", "effects", "voice"]:
		order.append(game.audio_pickers.get(key))
	var at := -1
	for c in order:
		var i: int = items.find(c)
		if i <= at:
			errors.append("%s should be reachable with the d-pad, after the one before it (%d <= %d)" % [c.name if c else "null", i, at])
		at = i
	if game.resolution_picker.item_count < 2 or game.resolution_picker.get_item_text(0) != "Native (desktop)":
		errors.append("the resolution picker should list Native and the window's size")

	# save, scramble, load
	game.graphics_resolution = Vector2i(1280, 720)
	game.graphics_aspect = 3
	AudioSettings.levels = {"master": 70, "engine": 30, "effects": 0, "voice": 90}
	game._save_graphics_settings()
	game.graphics_resolution = Vector2i(-1, -1)
	game.graphics_aspect = 0
	AudioSettings.levels = {"master": 100, "engine": 100, "effects": 100, "voice": 100}
	game._load_graphics_settings()
	if game.graphics_resolution != Vector2i(1280, 720) or game.graphics_aspect != 3:
		errors.append("resolution and aspect should load back: %s, %d" % [game.graphics_resolution, game.graphics_aspect])
	if AudioSettings.levels != {"master": 70, "engine": 30, "effects": 0, "voice": 90}:
		errors.append("the volumes should load back: %s" % [AudioSettings.levels])
	if absf(AudioServer.get_bus_volume_db(0) - linear_to_db(0.7)) > 0.001:
		errors.append("loading should apply the volumes to the buses")

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
		for panel in [game.options_panel, game.setup_panel, game.hud]:
			if is_instance_valid(panel) and not visible.grow(1.0).encloses(panel.get_global_rect()):
				errors.append("at %s %s %s leaves the canvas %s" % [game.ASPECTS[i].name, panel.name, panel.get_global_rect(), visible])
	game.graphics_aspect = 0
	game._apply_aspect()
	game.free()

	if backup.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(cfg_path))
	else:
		var f := FileAccess.open(cfg_path, FileAccess.WRITE)
		f.store_buffer(backup)
		f.close()
