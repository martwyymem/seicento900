## QA probe (dev tool, run windowed): the glitter behind cars on a wet road. Starts a wet quick race, lets the co-driver
## drive RUN s, freezes the race and measures the patch behind every car in view (the road from the rear bumper to 7 m
## back, projected to the screen) with one layer switched off at a time: the cars' spray/splash particles, the
## weather particles (rain, road spray, mist), FSR sharpening, the car reflection probe, and the wet road itself.
## Per layer: hf (mean |luma - 3x3 mean|, x1e3), spk (per mille of pixels 0.12 brighter than their 5x5 mean),
## flk (mean |luma frame - previous frame| over FLK frames with the race frozen, x1e3: particles and ripples still move).
## Env: PRESET (1 Medium), HOUR (14), TRACK (gp), OPP (8), RUN (14), FLK (6), TAG, OUT, SHOTS (1: save PNGs).
## godot --path godot --audio-driver Dummy --always-on-top --resolution 1280x720 -s tests/_glitter_probe.gd
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

func _grab() -> Image:
	await _wait(1)
	await RenderingServer.frame_post_draw
	var img: Image = game.render_viewport.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	return img

func _luma(img: Image) -> PackedFloat32Array:
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	var out := PackedFloat32Array()
	out.resize(w * h)
	for i in w * h:
		out[i] = (0.2126 * data[i * 3] + 0.7152 * data[i * 3 + 1] + 0.0722 * data[i * 3 + 2]) / 255.0
	return out

## Screen rectangles of the road behind each car in view (rear bumper to 7 m back, car width).
func _rects() -> Array[Rect2i]:
	var cam: Camera3D = game.render_viewport.get_camera_3d()
	var size: Vector2i = game.render_viewport.size
	var out: Array[Rect2i] = []
	for v in game.world_view.cars_root.get_children():
		if not (v is Node3D) or not v.visible:
			continue
		var xf: Transform3D = v.global_transform
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		var ok := true
		for z in [1.6, 7.0]:
			for x in [-0.9, 0.9]:
				var p: Vector3 = xf * Vector3(x, 0.05, z)
				if cam.is_position_behind(p) or cam.global_position.distance_to(p) > 60.0:
					ok = false
				var q := cam.unproject_position(p)
				lo = lo.min(q)
				hi = hi.max(q)
		if not ok:
			continue
		var r := Rect2i(Vector2i(lo), Vector2i(hi - lo)).intersection(Rect2i(Vector2i(2, 2), size - Vector2i(4, 4)))
		if r.size.x >= 8 and r.size.y >= 4:
			out.append(r)
	return out

func _measure(rects: Array[Rect2i], frames: int) -> Dictionary:
	var imgs: Array[Image] = []
	for k in frames:
		imgs.append(await _grab())
	var w := imgs[0].get_width()
	var lum := _luma(imgs[0])
	var hf := 0.0
	var spk := 0
	var n := 0
	for r in rects:
		for y in range(r.position.y + 2, r.end.y - 2):
			for x in range(r.position.x + 2, r.end.x - 2):
				var m3 := 0.0
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						m3 += lum[(y + dy) * w + x + dx]
				var m5 := 0.0
				for dy in range(-2, 3):
					for dx in range(-2, 3):
						m5 += lum[(y + dy) * w + x + dx]
				var c := lum[y * w + x]
				hf += absf(c - m3 / 9.0)
				if c - m5 / 25.0 > 0.12:
					spk += 1
				n += 1
	var flk := 0.0
	var fn := 0
	for k in range(1, imgs.size()):
		var a := _luma(imgs[k - 1])
		var b := _luma(imgs[k])
		for r in rects:
			for y in range(r.position.y, r.end.y):
				for x in range(r.position.x, r.end.x):
					flk += absf(a[y * w + x] - b[y * w + x])
					fn += 1
	return {"hf": hf / maxf(n, 1) * 1e3, "spk": float(spk) / maxf(n, 1) * 1e3, "flk": flk / maxf(fn, 1) * 1e3, "px": n, "img": imgs[0]}

func _fx_nodes() -> Array:
	var out := []
	for v in game.world_view.cars_root.get_children():
		for c in v.get_children():
			if c is GPUParticles3D:
				out.append(c)
	return out

func _initialize() -> void:
	Brain.use_disk = false
	Guard.backup()
	await process_frame
	var screen := DisplayServer.screen_get_usable_rect()
	DisplayServer.window_set_position(screen.position + screen.size - DisplayServer.window_get_size() - Vector2i(20, 20))
	var out := _env("OUT", "/tmp/qa/glitter")
	var tag := _env("TAG", "glitter")
	DirAccess.make_dir_recursive_absolute(out)
	game = load("res://ui/game.tscn").instantiate()
	root.add_child(game)
	await _wait(30)
	game._on_aspect_selected(1)
	game._on_preset_selected(int(_env("PRESET", "1")))
	await _wait(5)
	game._home_select(1, false)
	game._activate_home_item()
	await _wait(5)
	var track := _env("TRACK", "gp")
	game.track_picker.select(game.TRACK_KEYS.find(track))
	game._select_track(game.TRACK_KEYS.find(track))
	game.weather_picker.select(1) # wet
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
		print("GLITTER race did not start")
		quit(1)
		return
	game.race.set_autopilot(true)
	game.hud.visible = false
	if game.world_view.show_racing_line:
		game.world_view.toggle_racing_line()
	var t0 := Time.get_ticks_msec()
	while game.race.race_time < float(_env("RUN", "14")) and Time.get_ticks_msec() - t0 < 90000:
		await _wait(1)
	var w = game.world_view
	print("GLITTER preset %s hour %s wet %.2f rain %.2f render %s scale %.2f sharp %.2f" % [_env("PRESET", "1"), _env("HOUR", "14"),
		game.race.weather.wet, game.race.weather.rain, game.render_viewport.size, game.render_viewport.scaling_3d_scale, game.render_viewport.fsr_sharpness])
	Engine.time_scale = 0.0
	game.set_process(false) # the race holds still; the 3D keeps drawing
	w.set_process(false) # so the layers switched off below stay off
	await _wait(4)
	var rects := _rects()
	print("GLITTER rects ", rects)
	var frames := int(_env("FLK", "6"))
	var weather: Array = [w.rain_particles, w.rain_splash_particles, w.rain_mist_particles]
	var road_mats: Array = w._wet_materials
	var layers := _env("LAYERS", "base,no_car_fx,no_weather_fx,no_sharpen,no_car_probe,no_fx_all,no_beams,no_sky_refl,no_sun,no_sun_spec,no_detail,dry_road").split(",")
	for layer in layers:
		match layer:
			"no_car_fx":
				for p in _fx_nodes():
					p.visible = false
			"no_weather_fx":
				for p in _fx_nodes():
					p.visible = true
				for p in weather:
					if p:
						p.visible = false
			"no_sharpen":
				for p in weather:
					if p:
						p.visible = true
				game.render_viewport.fsr_sharpness = 2.0
			"no_car_probe":
				game._apply_upscaling()
				if w.reflections:
					w.reflections.visible = false
			"no_fx_all":
				if w.reflections:
					w.apply_graphics(w.quality)
				for p in _fx_nodes() + weather:
					if p:
						p.visible = false
			"no_beams":
				for b in w.beams:
					b.visible = false
			"no_sky_refl":
				w.world_environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
			"no_sun":
				w.world_environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
				w.sun.visible = false
			"no_sun_spec":
				w.world_environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
				w.sun.visible = true
				w.sun.light_specular = 0.0
			"no_detail":
				w.world_environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
				w.sun.visible = true
				for m in road_mats:
					if m.shader and m.shader.resource_path.ends_with("road.gdshader"):
						m.set_shader_parameter("detail", 0.0)
			"dry_road":
				for m in road_mats:
					m.set_shader_parameter("wet", 0.0)
		await _wait(3)
		var r := await _measure(rects, frames)
		print("GLITTER %-14s hf %.2f spk %.2f flk %.2f px %d" % [layer, r.hf, r.spk, r.flk, r.px])
		if _env("SHOTS", "1") == "1":
			var img: Image = r.img
			img.save_png("%s/%s_%s.png" % [out, tag, layer])
	Engine.time_scale = 1.0
	game.queue_free()
	await process_frame
	Guard.restore()
	quit()
