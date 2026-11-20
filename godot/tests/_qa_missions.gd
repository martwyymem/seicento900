## QA probe (dev tool, run WINDOWED): the Golf IV through the real game scene (the missions run on the open-world map: tests/_live_audit.gd).
## PART=golf    quick race in the Golf IV (CAR picker), shots from the chase/far/bumper/bonnet cameras, a side camera
##              while steering, a rear one braking at night, a dented car; HOUR, TRACK.
## PART=lock    the CAR picker with the Golf still locked: the status line's hint.
## PART=menu    the home screen's turntable with the Golf picked.
## PART=owcar   the open world in the Golf: the pause menu's CAR button.
## Every part writes the campaign progress it needs (all missions open, cars per CARS) and puts the saves back.
## godot --path godot --audio-driver Dummy --always-on-top --resolution 1280x720 --position 2140,1390 -s tests/_qa_missions.gd
extends SceneTree

const Guard := preload("res://tests/_qa_save_guard.gd")

var game
var out := ""
var fails := 0

func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d

func _wait(frames: int) -> void:
	for k in frames:
		if game:
			game._app_focused = true
			if game.paused:
				game._set_paused(false)
			if game.open_world != null and game.open_world.visible and game.open_world.paused and not _keep_pause:
				game.open_world._set_paused(false)
		await process_frame

var _keep_pause := false

func _secs(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < s * 1000.0:
		await _wait(1)

func _fail(msg: String) -> void:
	fails += 1
	print("QAM FAIL ", msg)

func _key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)
		await _wait(2)

func _shot(name: String) -> void:
	await _wait(2)
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [out, name]
	root.get_texture().get_image().save_png(path)
	print("QAM shot ", path)

func _labels(node: Node, acc: Array) -> Array:
	if node is Label and (node as Label).is_visible_in_tree() and (node as Label).text != "":
		acc.append((node as Label).text)
	if node is Button and (node as Button).is_visible_in_tree():
		acc.append("[%s]" % (node as Button).text)
	for c in node.get_children():
		_labels(c, acc)
	return acc

func _set_progress(cars: Array) -> void:
	var prog := Campaign.load_progress()
	prog["unlocked"] = 8 # every mission's stage cleared: all seven open
	prog["cars"] = cars
	prog["missions"] = {}
	Campaign.save_progress(prog)
	var back := Campaign.load_progress()
	print("QAM progress unlocked %s cars %s" % [back.get("unlocked"), back.get("cars")])

func _initialize() -> void:
	Brain.use_disk = false
	Guard.backup()
	out = _env("OUT", "/tmp/qa/missions")
	DirAccess.make_dir_recursive_absolute(out)
	var part := _env("PART", "golf")
	_set_progress([] if part == "lock" or _env("NOCARS", "") != "" else ["golf4"])
	if part == "owcar":
		var wp := WorldProgress.load_progress()
		wp.car_class = CarCatalog.index_of("golf4")
		wp.save()
	game = load("res://ui/game.tscn").instantiate()
	root.add_child(game)
	await _wait(30)
	game._on_aspect_selected(1)
	await _wait(5)
	match part:
		"golf": await _golf()
		"lock": await _lock()
		"menu": await _menu()
		"owcar": await _owcar()
	print("QAM done, %d failures" % fails)
	game.queue_free()
	await process_frame
	Guard.restore()
	quit()

# ------------------------------------------------------------------ the Golf

func _pick_golf() -> void:
	game._home_select(1, false)
	game._activate_home_item()
	await _wait(5)
	game.car_class_picker.select(CarCatalog.index_of(_env("CAR", "golf4")))
	game._on_car_class_selected(CarCatalog.index_of(_env("CAR", "golf4")))
	await _wait(5)
	print("QAM picker selected %d picked '%s' status '%s'" % [game.car_class_picker.selected, game._picked_car(), game.status_label.text])

func _lock() -> void:
	await _pick_golf()
	await _shot("lock_setup")

func _menu() -> void:
	await _pick_golf()
	await _secs(3)
	await _shot("menu_turntable")
	await _secs(4)
	await _shot("menu_turntable2")

func _golf() -> void:
	await _pick_golf()
	var key: String = _env("TRACK", "gp")
	game.track_picker.select(game.TRACK_KEYS.find(key))
	game._select_track(game.TRACK_KEYS.find(key))
	game.weather_picker.select(0)
	game.start_hour_picker.value = float(_env("HOUR", "14"))
	game.opponents_picker.value = 5
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
	var r: Race = game.race
	if r == null:
		_fail("race did not start: " + game.status_label.text)
		return
	print("QAM race car_class '%s' player spec '%s' visual key '%s'" % [r.s.car_class, r.player.model.spec.resource_name if "model" in r.player and r.player.model else "-",
		_player_visual().car_key if _player_visual() else "?"])
	r.set_autopilot(true)
	var tag := "%s_h%s" % [_env("CAR", "golf4"), _env("HOUR", "14")]
	await _secs(9)
	await _shot(tag + "_chase")
	game._cycle_camera()
	await _secs(1.5)
	await _shot(tag + "_far")
	game._cycle_camera()
	await _secs(1.5)
	await _shot(tag + "_bumper")
	game._cycle_camera()
	await _secs(1.5)
	await _shot(tag + "_bonnet")
	for k in 4: # back round to the chase camera
		game._cycle_camera()
	await _secs(float(_env("RUN2", "0")))
	# the race frozen, the other cars hidden, the car posed by hand (steer, brake, dents) for close looks
	var vis: Node3D = _player_visual()
	var cam := Camera3D.new()
	cam.fov = 45.0
	game.world_view.add_child(cam)
	Engine.time_scale = 0.0
	await _wait(2)
	game.world_view.process_mode = Node.PROCESS_MODE_DISABLED
	for id in game.world_view.visuals:
		if game.world_view.visuals[id] != vis:
			game.world_view.visuals[id].visible = false
	var night: float = game.world_view.night
	var pc: RaceCar = r.player
	var ctl := pc.control
	pc.control = "free" if pc.phys != null else ctl
	var b := vis.global_transform.basis # -Z forward, +X right
	var c := vis.global_position
	cam.make_current()
	var views := {
		"profile_r": [c + b.x * 5.0 + Vector3.UP * 1.6, c + Vector3.UP * 0.6],
		"profile_l": [c - b.x * 5.0 + Vector3.UP * 1.6, c + Vector3.UP * 0.6],
		"front34": [c - b.z * 5.5 + b.x * 3.5 + Vector3.UP * 1.5, c + Vector3.UP * 0.6],
		"rear34": [c + b.z * 5.5 - b.x * 3.5 + Vector3.UP * 1.5, c + Vector3.UP * 0.6],
		"rear": [c + b.z * 6.5 + Vector3.UP * 1.1, c + Vector3.UP * 0.7],
		"front": [c - b.z * 6.5 + Vector3.UP * 1.1, c + Vector3.UP * 0.7],
		"top": [c + Vector3.UP * 9.0 + b.z * 0.01, c],
	}
	for v in views:
		cam.global_position = views[v][0]
		cam.look_at(views[v][1])
		await _shot("%s_%s" % [tag, v])
	# the front wheels at lock both ways, seen from the front three-quarter and from above
	for st in [float(_env("LOCK", "0.3")), -float(_env("LOCK", "0.3"))]:
		pc.steer = st
		pc.brake_on = false
		var wb: float = CarCatalog.visual(r.s.car_class).wheelbase
		vis.sync(pc, 0.0, tan(st / 1.4) / wb, night, false) # (a rail car steers by the curvature)
		cam.global_position = c - b.z * 4.2 + b.x * 2.6 * signf(st) + Vector3.UP * 1.0
		cam.look_at(c - b.z * 1.25 + b.x * 0.75 * signf(st) + Vector3.UP * 0.3)
		await _shot("%s_steer%+.2f" % [tag, st])
		cam.global_position = c + Vector3.UP * 5.0 - b.z * 1.26 + b.z * 0.01
		cam.look_at(c - b.z * 1.26)
		await _shot("%s_steer%+.2f_top" % [tag, st])
	pc.steer = 0.0
	# brake lights on and off from behind
	for on in [false, true]:
		pc.brake_on = on
		vis.sync(pc, 0.0, 0.0, night, false)
		cam.global_position = c + b.z * 6.0 + Vector3.UP * 1.3
		cam.look_at(c + Vector3.UP * 0.6)
		await _shot("%s_brake_%s" % [tag, "on" if on else "off"])
	# all four sides dented
	pc.dents = {"front": 1.0, "rear": 1.0, "left": 1.0, "right": 1.0}
	pc.brake_on = false
	vis._show_dents(pc.dents, 10.0)
	vis.sync(pc, 0.0, 0.0, night, false)
	for v in ["front34", "rear34"]:
		cam.global_position = views[v][0]
		cam.look_at(views[v][1])
		await _shot("%s_dented_%s" % [tag, v])
	print("QAM night %.2f control %s phys %s" % [night, ctl, pc.phys != null])
	pc.control = ctl
	cam.queue_free()
	game.world_view.process_mode = Node.PROCESS_MODE_INHERIT
	Engine.time_scale = 1.0

func _player_visual() -> Node3D:
	return game.world_view.visuals.get(game.race.player.id)

func _owcar() -> void:
	await game._enter_open_world("")
	await _wait(60)
	var ow: OpenWorld = game.open_world
	print("QAM open world car_class %d visual key '%s' drive spec '%s'" % [ow.progress.car_class, ow.car_visual.car_key, ow.drive.model.spec.resource_name])
	await _secs(2)
	await _shot("owcar_drive")
	_keep_pause = true
	ow._set_paused(true)
	await _wait(10)
	for b in ow.hud.pause_buttons:
		if b.text.begins_with("CAR:"):
			print("QAM pause CAR button '%s'" % b.text)
	await _shot("owcar_pause")
	ow._toggle_car()
	await _wait(10)
	for b in ow.hud.pause_buttons:
		if b.text.begins_with("CAR:"):
			print("QAM after toggle CAR button '%s' class %d" % [b.text, ow.progress.car_class])
	await _shot("owcar_pause_toggled")
	_keep_pause = false
	ow._set_paused(false)
