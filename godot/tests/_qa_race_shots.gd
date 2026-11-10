## QA probe (dev tool, run windowed): starts a quick race, lets the co-driver drive, then saves screenshots.
## Env: TRACK (gp), WEATHER (dry|wet|snow|hail|fog|variable), HOUR (14), OPP (8), RUN (8 s of race time before
## the first shot), SHOTS (1: shots RUN_GAP s apart), MODES ("0" or e.g. "0,1,2,3,4,5,6": retro styles shot per
## frame, the race frozen meanwhile), CAM (camera cycles before shooting), ASPECT (aspect picker index),
## CLEAN (1: hide HUD and racing line for pixel measurements), PRESET (0 Low .. 3 Ultra), TELE (lap distance, m), PERF (frames to time),
## WARP (time-warp steps while getting to RUN), TAG, OUT (/tmp/qa/shots), MODS (comma list of CarMods ids put on the player's car without touching the save, e.g. monster,nitro).
## TRACK=gp WEATHER=wet HOUR=22 godot --path godot --audio-driver Dummy -s tests/_qa_race_shots.gd
extends SceneTree

const Guard := preload("res://tests/_qa_save_guard.gd")

var game

func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d

func _wait(frames: int) -> void:
	for k in frames:
		if game and game.paused:
			game._set_paused(false)
		if game:
			game._app_focused = true
		await process_frame

func _flat(img: Image) -> bool:
	# a frame with (nearly) one colour over the 3D area is a failed capture
	var c0 := img.get_pixel(img.get_width() / 2, img.get_height() / 3)
	var diff := 0.0
	for i in 12:
		var c := img.get_pixel(int(img.get_width() * (0.25 + 0.04 * i)), int(img.get_height() * (0.35 + 0.03 * i)))
		diff += absf(c.r - c0.r) + absf(c.g - c0.g) + absf(c.b - c0.b)
	return diff < 0.05

func _save(path: String) -> void:
	for attempt in 6:
		await _wait(2)
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		if not _flat(img) or attempt == 5:
			img.save_png(path)
			print("QA saved %s%s" % [path, " (FLAT)" if _flat(img) else ""])
			return

func _initialize() -> void:
	Brain.use_disk = false
	Guard.backup() # the shared dev sandbox: put the saves back at the end
	var out := _env("OUT", "/tmp/qa/shots")
	var tag := _env("TAG", "shot")
	DirAccess.make_dir_recursive_absolute(out)
	game = load("res://ui/game.tscn").instantiate()
	root.add_child(game)
	await _wait(30)
	game._on_aspect_selected(int(_env("ASPECT", "1"))) # 16:9 unless asked (the sandbox may hold 21:9)
	if _env("PRESET", "") != "":
		game._on_preset_selected(int(_env("PRESET", "2"))) # 0 Low .. 3 Ultra
	if _env("SHARP", "") != "": # FSR sharpening picker index (0 off .. 3 high)
		game._on_sharpening_selected(int(_env("SHARP", "2")))
	await _wait(5)
	game._home_select(1, false)
	game._activate_home_item()
	await _wait(5)
	game.track_picker.select(game.TRACK_KEYS.find(_env("TRACK", "gp")))
	game._select_track(game.TRACK_KEYS.find(_env("TRACK", "gp")))
	game.weather_picker.select(["dry", "wet", "snow", "hail", "fog", "variable"].find(_env("WEATHER", "dry")))
	game.start_hour_picker.value = float(_env("HOUR", "14"))
	game.opponents_picker.value = int(_env("OPP", "8"))
	game.grid_picker.select(int(_env("GRID", "1")))
	game.laps_picker.value = 3
	await _wait(10)
	for k in 3000:
		if not game._strategy_pending:
			break
		await process_frame
	game._start_race()
	for k in 4000:
		await _wait(1)
		if game.race != null and not game._starting:
			break
	if game.race == null:
		print("QA race did not start: ", game.status_label.text)
		quit(1)
		return
	game.race.set_autopilot(true)
	if _env("TELE", "") != "": # move the whole field to this lap distance (m), e.g. to look at a landmark
		var dist: float = float(_env("TELE", "0")) - float(game.race.player.s)
		for c in game.race.cars:
			c.s += dist
		print("QA teleported the field to s=%.0f" % game.race.player.s)
	if _env("CLEAN", "") != "": # no HUD, no racing line: frames for pixel measurements
		game.hud.visible = false
		if game.world_view.show_racing_line:
			game.world_view.toggle_racing_line()
	if _env("MODS", "") != "":
		var on := {}
		for id in _env("MODS", "").split(","):
			on[id] = true
		game.race.set_mods(on)
		game.world_view.mods = on
		game.world_view.set_race(game.race)
		if on.has("nitro"):
			game.race.nitro = 0.6
	for k in int(_env("CAM", "0")):
		game._cycle_camera()
	var run := float(_env("RUN", "8"))
	for k in int(_env("WARP", "0")): # time-warp steps (WARP_VALUES) to get far round a long lap, back to 1x for the shots
		game._change_warp(1)
	var t0 := Time.get_ticks_msec()
	while game.race.race_time < run and Time.get_ticks_msec() - t0 < 90000:
		await _wait(1)
	while game.warp_index > 0:
		game._change_warp(-1)
	if _env("DIAG", "") != "":
		var w = game.world_view
		var e: Environment = w.world_environment
		print("QA diag night %.2f amb %.2f %s sky_contrib %.2f sun %.2f vol %s/%.4f fog %.4f lamp_on %.2f hdri %.2f exposure %.2f" % [w.night, e.ambient_light_energy, e.ambient_light_color, e.ambient_light_sky_contribution, w.sun.light_energy, e.volumetric_fog_enabled, e.volumetric_fog_density, e.fog_density, w._lamp_on, w._hdri_weight, e.tonemap_exposure])
		var lights: Array = w.find_children("*", "Light3D", true, false)
		var on: Array = lights.filter(func(l): return l.visible and l.light_energy > 0.02)
		print("QA diag lights %d visible %d" % [lights.size(), on.size()])
		for l in on.slice(0, 6):
			print("  ", l.get_class(), " e=", l.light_energy, " range=", l.get("omni_range") if l is OmniLight3D else l.get("spot_range"))
		Engine.time_scale = 0.0
		await _save("%s/%s_diag_base.png" % [out, tag])
		var amb := e.ambient_light_energy
		e.ambient_light_energy = 0.0
		await _save("%s/%s_diag_noamb.png" % [out, tag])
		e.ambient_light_energy = amb
		e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
		await _save("%s/%s_diag_norefl.png" % [out, tag])
		e.ambient_light_energy = 0.0
		e.volumetric_fog_enabled = false
		e.fog_enabled = false
		for l in on:
			l.visible = false
		await _save("%s/%s_diag_nothing.png" % [out, tag])
		Engine.time_scale = 1.0
	if _env("PERF", "") != "": # frame time over PERF frames, vsync off
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		await _wait(30)
		var ts: Array[float] = []
		var t_prev := Time.get_ticks_usec()
		for k in int(_env("PERF", "120")):
			await _wait(1)
			var t_now := Time.get_ticks_usec()
			ts.append((t_now - t_prev) / 1000.0)
			t_prev = t_now
		ts.sort()
		print("QA perf preset %s: median %.2f ms p95 %.2f ms, draws %d, objects %d, prims %.2fM" % [_env("PRESET", "-"), ts[ts.size() / 2], ts[int(ts.size() * 0.95)],
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1.0e6])
	if _env("SWEEP", "") != "": # the same frozen frame at each preset in SWEEP (e.g. "1,2"), FSR sharpening index in SHARPS
		Engine.time_scale = 0.0
		for pr in _env("SWEEP", "").split(","):
			game._on_preset_selected(int(pr))
			for sh in _env("SHARPS", "-").split(","):
				if sh != "-":
					game._on_sharpening_selected(int(sh))
				await _wait(4)
				await _save("%s/%s_preset%s_sharp%s.png" % [out, tag, pr, sh])
		Engine.time_scale = 1.0
		game.queue_free()
		await process_frame
		Guard.restore()
		quit()
		return
	if _env("LAYERS", "") != "": # night lighting layers one by one, the race frozen: what lights a glare
		var w = game.world_view
		Engine.time_scale = 0.0
		await _save("%s/%s_layers_base.png" % [out, tag])
		var e0: PackedFloat32Array = w._lamp_energy.duplicate()
		for f in [0.5, 0.25]:
			for i in e0.size():
				if w._lamp_cone[i] < 50.0:
					w._lamp_energy[i] = e0[i] * f
			await _save("%s/%s_layers_masts%d.png" % [out, tag, roundi(f * 100)])
		w._lamp_energy = e0.duplicate()
		var streaks: Array = w.find_children("LampStreaks", "", true, false)
		for n in streaks:
			n.visible = false
		await _save("%s/%s_layers_nostreaks.png" % [out, tag])
		for d in w._lamp_decals:
			if float(d.get_meta("streak", 0.0)) > 2.0:
				d.visible = false # the masts' pools first
		await _save("%s/%s_layers_nomastpools.png" % [out, tag])
		for d in w._lamp_decals:
			d.visible = false
		await _save("%s/%s_layers_nopools.png" % [out, tag])
		for i in w._lamp_energy.size():
			if w._lamp_cone[i] < 50.0:
				w._lamp_energy[i] = 0.0 # the floodlight masts first (the pool's energies are set from these every frame)
		await _save("%s/%s_layers_nomasts.png" % [out, tag])
		for i in w._lamp_energy.size():
			w._lamp_energy[i] = 0.0
		await _save("%s/%s_layers_nolamps.png" % [out, tag])
		Engine.time_scale = 1.0
		game.queue_free()
		await process_frame
		Guard.restore()
		quit()
		return
	var modes := _env("MODES", "0").split(",")
	var shots := int(_env("SHOTS", "1"))
	for n in shots:
		if modes.size() > 1:
			Engine.time_scale = 0.0
		for m in modes:
			game.retro_pipeline.set_mode(int(m))
			await _wait(6)
			await _save("%s/%s_%d_mode%s.png" % [out, tag, n, m])
		Engine.time_scale = 1.0
		game.retro_pipeline.set_mode(0)
		var t1: float = game.race.race_time
		var t2 := Time.get_ticks_msec()
		while game.race.race_time < t1 + float(_env("RUN_GAP", "6")) and Time.get_ticks_msec() - t2 < 30000:
			await _wait(1)
	print("QA race player pos P%d, lap %d" % [game.race.order.find(game.race.player) + 1, game.race.player.lap])
	game.queue_free()
	await process_frame
	Guard.restore()
	quit()
