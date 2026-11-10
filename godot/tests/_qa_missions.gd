## QA probe (dev tool, run WINDOWED): the Golf IV and the campaign missions through the real game scene.
## PART=golf    quick race in the Golf IV (CAR picker), shots from the chase/far/bumper/bonnet cameras, a side camera
##              while steering, a rear one braking at night, a dented car; HOUR, TRACK.
## PART=lock    the CAR picker with the Golf still locked: the status line's hint.
## PART=menu    the home screen's turntable with the Golf picked.
## PART=owcar   the open world in the Golf: the pause menu's CAR button.
## PART=mission MISSION=<id> (Missions.MISSIONS): the beacon in the world and on the map, the card, Enter starts it,
##              the mission plate in the live race, warp to the end, the results, back to the beacon. WIN=1 lifts the
##              player to the front before the end (to see the cleared screen), LOSE=1 drops it to the back.
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
		"mission": await _mission(_env("MISSION", "drag_quarter"))
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

# ------------------------------------------------------------------ missions

func _mission(id: String) -> void:
	var idx := Missions.index_of(id)
	var kind := Missions.kind_of(idx)
	game.is_campaign_mode = true
	game.campaign_stage_index = 8
	game._update_mode_view()
	var t0 := Time.get_ticks_msec()
	await game._enter_open_world("") # returns once the world is built
	while Time.get_ticks_msec() - t0 < 60000 and (game.open_world == null or game.open_world.building):
		await _wait(1)
	print("QAM open world built in %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	await _wait(30)
	var ow: OpenWorld = game.open_world
	if ow == null:
		_fail("no open world")
		return
	var ev: Dictionary = {}
	for e in ow.events:
		if int(e.stage) == idx:
			ev = e
	var nm := 0
	for e in ow.events:
		if e.has("mission"):
			nm += 1
	print("QAM %s: %d mission events in the world (%d events)" % [id, nm, ow.events.size()])
	if ev.is_empty():
		_fail("%s: no beacon event" % id)
		return
	var pos: Vector2 = ev.pos
	var h := float(ev.heading)
	# park 25 m short of the beacon facing it, shoot, then drive onto it
	var from := pos - Vector2(cos(h), sin(h)) * 25.0
	var near: Dictionary = ow.map.nearest_road(from, 30.0)
	if not near.is_empty():
		from = near.pos
	ow.drive.place(from, (pos - from).angle())
	ow.drive.respawn()
	ow.snap_camera()
	await _secs(2)
	await _shot(id + "_beacon")
	ow.drive.place(pos, h)
	ow.drive.respawn()
	ow.snap_camera()
	await _secs(1.5)
	print("QAM %s: active_event %d (want %d) card visible %s" % [id, ow.active_event, ow.events.find(ev), ow.hud.card.visible])
	await _shot(id + "_card")
	ow.hud.map_sel = -1
	ow.hud.toggle_map(true)
	await _wait(20)
	await _shot(id + "_map")
	ow.hud.toggle_map(false)
	await _wait(10)
	await _key(KEY_ENTER)
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 40000 and not (game.race != null and not game._starting):
		await _wait(1)
	if game.race == null:
		_fail("%s: Enter at the beacon started no race (status '%s')" % [id, game.status_label.text])
		return
	print("QAM %s: started after %.1f s; campaign %s rally %s mission_rally %d settings.mission '%s' knockout %s finish_distance %.0f drift %s laps %d opp %d car '%s'" % [id,
		(Time.get_ticks_msec() - t0) / 1000.0, game.is_campaign_mode, game.is_rally_mode, game.mission_rally, game.race.s.mission,
		game.race.s.knockout, game.race.s.finish_distance, game.race.s.drift_score, game.race.R, game.race.cars.size() - 1, game.race.s.car_class])
	if kind == "rally":
		await _rally_mission(id)
	else:
		await _race_mission(id, kind)
	# results -> back to the beacon
	var back: Button = null
	for b in _buttons(game.result_panel, []):
		if b.text.contains("BRZESZCZE") or b.text.contains("BACK TO MENU"):
			back = b
			if b.text.contains("BRZESZCZE"):
				break
	if back == null:
		_fail("%s: no way back on the results" % id)
		return
	print("QAM %s: pressing '%s'" % [id, back.text])
	back.pressed.emit()
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 60000 and not (game.open_world != null and game.open_world.visible):
		await _wait(1)
	await _secs(2)
	var cp := Vector2(ow.drive.car.x, ow.drive.car.y)
	var p2 := Missions.progress(Campaign.load_progress(), idx)
	print("QAM %s: back in the world %s, %.1f m from the beacon, progress %s, cars %s" % [id, game.open_world.visible, cp.distance_to(pos), p2,
		Campaign.load_progress().get("cars", [])])
	await _shot(id + "_back")

func _buttons(node: Node, acc: Array) -> Array:
	if node is Button and (node as Button).is_visible_in_tree():
		acc.append(node)
	for c in node.get_children():
		_buttons(c, acc)
	return acc

func _race_mission(id: String, kind: String) -> void:
	var r: Race = game.race
	r.set_autopilot(true)
	var t0 := Time.get_ticks_msec()
	while r.phase == "countdown" and Time.get_ticks_msec() - t0 < 30000:
		await _wait(1)
	if kind == "drag":
		await _shot(id + "_plate_start")
		await _secs(float(_env("RUN", "6")))
	else:
		await _secs(float(_env("RUN", "8")))
	await _shot(id + "_plate")
	_print_state(id, r)
	if kind == "drift":
		await _secs(4)
		await _shot(id + "_plate2")
		_print_state(id, r)
	if kind == "knockout":
		# to the first knock-out at 10x, then a shot at 1x right after it
		game._change_warp(1); game._change_warp(1); game._change_warp(1)
		t0 = Time.get_ticks_msec()
		while r.knocked_out.is_empty() and r.phase != "finished" and Time.get_ticks_msec() - t0 < 40000:
			await _wait(1)
		while game.warp_index > 0:
			game._change_warp(-1)
		await _secs(0.5)
		await _shot(id + "_plate_ko")
		_print_state(id, r)
	if _env("WIN", "") != "" or _env("LOSE", "") != "":
		# lift the player to the front (or drop it behind) so both results screens can be seen
		var lead: RaceCar = r.order[0]
		if _env("WIN", "") != "" and lead != r.player:
			r.player.lap = lead.lap
			r.player.s = lead.s + 25.0
		print("QAM %s: moved the player (WIN/LOSE)" % id)
	t0 = Time.get_ticks_msec()
	for k in 5:
		game._change_warp(1)
	while r.phase != "finished" and not game.result_panel.visible and Time.get_ticks_msec() - t0 < 60000:
		await _wait(1)
		if _env("LOSE", "") != "" and r.phase == "racing":
			r.player.v = minf(r.player.v, 5.0)
	t0 = Time.get_ticks_msec()
	while not game.result_panel.visible and Time.get_ticks_msec() - t0 < 30000:
		await _wait(1)
	await _secs(1)
	print("QAM %s: phase %s, race_time %.1f, player pos %d dnf %s '%s'" % [id, r.phase, r.race_time, r.order.find(r.player) + 1, r.player.dnf, r.player.dnf_reason])
	print("QAM %s results: %s" % [id, " | ".join(_labels(game.result_panel, []).slice(0, 14))])
	await _shot(id + "_results")

func _print_state(id: String, r: Race) -> void:
	var extra := ""
	if r.s.knockout:
		extra = "left %d, knocked %d, zone %s" % [r.cars.filter(func(x: RaceCar) -> bool: return not x.dnf).size(), r.knocked_out.size(), r.knockout_zone().name if r.knockout_zone() else "-"]
	elif r.s.finish_distance > 0.0:
		extra = "run %.0f / %.0f m" % [r.run_distance(r.player), r.s.finish_distance]
	if r.drift:
		extra += " drift total %d combo %.0f x%.1f" % [r.drift.total(), r.drift.combo, r.drift.mult]
	print("QAM %s: t %.1f phase %s P%d speed %.0f km/h, plate visible %s, %s" % [id, r.race_time, r.phase, r.order.find(r.player) + 1,
		absf(r.player.speed) * 3.6, game.hud.missionbar.visible, extra])

func _rally_mission(id: String) -> void:
	var menu_rally_before := FileAccess.get_file_as_string(SaveData.path("rally.json"))
	var stages := 0
	var t_all := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_all < 100000:
		var r: Race = game.race
		if r == null:
			_fail("%s: no race for the next stage" % id)
			return
		r.set_autopilot(true)
		var t0 := Time.get_ticks_msec()
		while r.phase == "countdown" and Time.get_ticks_msec() - t0 < 30000:
			await _wait(1)
		await _secs(3)
		await _shot("%s_ss%d" % [id, stages + 1])
		print("QAM %s SS%d: track %s, %s, rally %s, plate %s" % [id, stages + 1, r.track.name, r.phase, game.is_rally_mode, game.hud.missionbar.visible])
		for k in 5:
			game._change_warp(1)
		t0 = Time.get_ticks_msec()
		while not game.result_panel.visible and Time.get_ticks_msec() - t0 < 60000:
			await _wait(1)
		await _secs(1)
		stages += 1
		var texts := _labels(game.result_panel, [])
		print("QAM %s SS%d results: %s" % [id, stages, " | ".join(texts.slice(0, 10))])
		await _shot("%s_ss%d_results" % [id, stages])
		var ev: RallyEvent = game.rally_event
		if ev == null or ev.is_over():
			print("QAM %s: rally over after %d stages; table %s" % [id, stages, " | ".join(texts.filter(func(t: String) -> bool: return t.contains("MISSION") or t.contains("Trophy") or t.contains("fans") or t.contains("New car")))])
			break
		# the results' primary: the service area or the next stage
		var prim: Button = null
		for b in _buttons(game.result_panel, []):
			if b.text.contains("SERVICE") or b.text.begins_with("NEXT"):
				prim = b
		if prim == null:
			_fail("%s: no next/service button" % id)
			return
		print("QAM %s: pressing '%s'" % [id, prim.text])
		var to_service := prim.text.contains("SERVICE")
		prim.pressed.emit()
		await _wait(30)
		if to_service:
			print("QAM %s: service page '%s', rally %s campaign %s mission_rally %d" % [id, game.active_menu_page, game.is_rally_mode, game.is_campaign_mode, game.mission_rally])
			await _shot("%s_service%d" % [id, stages])
			game.repair_continue.pressed.emit()
		t0 = Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 40000 and not (game.race != null and not game._starting and not game.result_panel.visible):
			await _wait(1)
	var menu_rally_after := FileAccess.get_file_as_string(SaveData.path("rally.json"))
	print("QAM %s: menu rally.json unchanged %s (%d bytes)" % [id, menu_rally_before == menu_rally_after, menu_rally_after.length()])
