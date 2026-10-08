## World sounds (WorldAudio): the baked sounds, the race's impact log, what the player's wheels are on, Doppler,
## the pit crews' timing, and the node following a race in the world (engine slots, crowds, hits, the Car bus).
extends RefCounted

var completed := false

func run() -> Array:
	var errors: Array[String] = []
	_sounds(errors)
	_impact_log(errors)
	_wheels(errors)
	_doppler_and_pits(errors)
	_in_the_world(errors)
	completed = true
	return errors

func _sounds(errors: Array[String]) -> void:
	for sound in WorldAudio.LOOPS + WorldAudio.SHOTS:
		var st := WorldAudio.stream(sound) as AudioStreamWAV
		if st == null:
			errors.append("%s should be baked into res://audio (tools/build_sounds.py)" % sound)
			continue
		var frames := roundi(st.get_length() * st.mix_rate)
		if sound in WorldAudio.LOOPS:
			if st.loop_mode != AudioStreamWAV.LOOP_FORWARD or st.loop_begin != 0 or absi(st.loop_end - frames) > 1:
				errors.append("%s should loop over all of its %d frames, not %d..%d (mode %d)" % [sound, frames, st.loop_begin, st.loop_end, st.loop_mode])
		elif st.loop_mode != AudioStreamWAV.LOOP_DISABLED:
			errors.append("%s is a one-shot and should not loop" % sound)
		if st.get_length() < 0.3:
			errors.append("%s is too short: %.2f s" % [sound, st.get_length()])

## The race logs hits only while asked to, and logging them leaves the race exactly as it would have run.
func _impact_log(errors: Array[String]) -> void:
	var st := RaceSettings.new()
	st.track = "monaco"
	st.opponents = 7
	st.laps = 1
	var heard := Race.new(st, null, 3)
	var quiet := Race.new(st, null, 3)
	heard.hear_impacts = true
	heard.set_autopilot(true)
	quiet.set_autopilot(true)
	var idle := Race.PlayerInput.new()
	for i in 120 * 25:
		heard.step(1.0 / 120.0, idle)
		quiet.step(1.0 / 120.0, idle)
		heard.impacts.clear()
	if not quiet.impacts.is_empty():
		errors.append("a race nobody listens to should log no hits")
	for i in heard.cars.size():
		var a: RaceCar = heard.cars[i]
		var b: RaceCar = quiet.cars[i]
		if a.x != b.x or a.y != b.y or a.s != b.s or a.damage != b.damage:
			errors.append("logging hits changed the race: car %d at (%f, %f) instead of (%f, %f)" % [i, a.x, a.y, b.x, b.y])
			break
	quiet.dispose()

	# drive the player into the barrier, then run into the back of another car
	var p := heard.player
	var tr := heard.track
	heard.set_autopilot(false)
	var s := _straight(tr)
	_place(heard, p, s, tr.limits(s)[1] - 0.4, 0.35, 25.0)
	heard.impacts.clear()
	for i in 12:
		heard.step(1.0 / 120.0, idle)
	var wall := _find(heard.impacts, 0, p.id)
	if wall.is_empty() or wall[2] < 3.0:
		errors.append("driving into the barrier at an angle should log a hard barrier hit, got %s" % [wall])
	var other: RaceCar = heard.cars[1]
	heard.to_free(other)
	_place(heard, p, s + 40.0, 0.0, 0.0, 30.0)
	_place(heard, other, s + 43.2, 0.0, 0.0, 15.0)
	heard.impacts.clear()
	heard.step(1.0 / 120.0, idle)
	heard.step(1.0 / 120.0, idle)
	var hit := _find(heard.impacts, 1, p.id)
	if hit.is_empty() or not (int(hit[4]) == other.id or int(hit[5]) == other.id):
		errors.append("running into another car should log a car hit naming both cars, got %s" % [hit])
	heard.dispose()

## The middle of the longest straight on the circuit.
func _straight(tr: Track) -> float:
	var best := 0
	var best_len := 0
	var run := 0
	for i in tr.n * 2:
		if absf(tr.KC[i % tr.n]) < 1.0 / 400.0:
			run += 1
			if run > best_len:
				best_len = run
				best = i % tr.n
		else:
			run = 0
	return tr.wrap_s((best - best_len / 2) * tr.step)

## Puts a car at (s, d) heading off the track's direction by angle (+ towards the right), at speed.
func _place(race: Race, car: RaceCar, s: float, d: float, angle: float, speed: float) -> void:
	var tr := race.track
	s = tr.wrap_s(s)
	var pos := tr.pos(s, d)
	car.s = s
	car.d = d
	car.x = pos[0]
	car.y = pos[1]
	car.heading = tr.heading(s) + angle
	car.vx = cos(car.heading) * speed
	car.vy = sin(car.heading) * speed
	car.speed = speed
	car.v = speed
	car.yaw_rate = 0.0

## The first logged hit of a kind involving a car: [x, y, dv, kind, id_a, id_b], or [] if none.
func _find(imp: PackedFloat32Array, kind: int, id: int) -> Array:
	for o in range(0, imp.size(), Race.IMPACT_STRIDE):
		if int(imp[o + 3]) == kind and (int(imp[o + 4]) == id or int(imp[o + 5]) == id):
			return Array(imp.slice(o, o + Race.IMPACT_STRIDE))
	return []

func _wheels(errors: Array[String]) -> void:
	var st := RaceSettings.new()
	st.track = "monza"
	st.opponents = 0
	var race := Race.new(st, null, 1)
	var tr := race.track
	var p := race.player
	var s := _straight(tr)
	_place(race, p, s, 0.0, 0.0, 20.0)
	if WorldAudio.wheel_contact(race, p) != PackedFloat32Array([0.0, 0.0, 0.0]):
		errors.append("on the middle of a straight no wheel should be on a kerb, grass or gravel")
	if WorldAudio.touching_barrier(race, p):
		errors.append("in the middle of the road the car touches no barrier")
	# away from the pits, well off the road, every wheel is on the run-off
	var side := -signf(tr.cfg.pit_offset) if tr.cfg.pit_offset != 0.0 else 1.0
	_place(race, p, s, side * (tr.half + 3.5), 0.0, 20.0)
	var off := WorldAudio.wheel_contact(race, p)
	var want := 2 if tr.cfg.runoff_surface == "gravel" else (1 if tr.cfg.runoff_surface != "asphalt" else -1)
	if want > 0 and off[want] != 1.0:
		errors.append("well off the road all four wheels should be on the %s, got %s" % [tr.cfg.runoff_surface, off])
	# on the inside of a bend, the inside wheels ride the kerb
	var bend := -1
	for i in range(3, tr.n - 3):
		var ok := true
		for j in range(i - 3, i + 4):
			if absf(tr.KC[j]) < 1.5 / 180.0 or signf(tr.KC[j]) != signf(tr.KC[i]):
				ok = false
				break
		if ok:
			bend = i
			break
	if bend < 0:
		errors.append("Monza should have a bend with kerbs")
	else:
		var k := signf(tr.KC[bend])
		var wy := absf(race.phys.WY[0])
		_place(race, p, (bend + 0.5) * tr.step, k * (tr.half - wy - 0.1), 0.0, 20.0)
		var kerb := WorldAudio.wheel_contact(race, p)
		if kerb[0] < 0.5:
			errors.append("with the inside wheels on the kerb, half the wheels should be on it, got %s" % kerb)
	_place(race, p, s, tr.limits(s)[1], 0.0, 20.0)
	p.control = "free"
	if not WorldAudio.touching_barrier(race, p):
		errors.append("a car pushed up to its limit is against the barrier")
	race.dispose()

func _doppler_and_pits(errors: Array[String]) -> void:
	var c := WorldAudio.SOUND_SPEED
	var src := Vector3(0, 0, 0)
	var lis := Vector3(100, 0, 0)
	var coming := WorldAudio.doppler(src, Vector3(30, 0, 0), lis, Vector3.ZERO)
	var going := WorldAudio.doppler(src, Vector3(-30, 0, 0), lis, Vector3.ZERO)
	var towards := WorldAudio.doppler(src, Vector3.ZERO, lis, Vector3(-30, 0, 0))
	if absf(coming - c / (c - 30.0)) > 1e-4 or absf(going - c / (c + 30.0)) > 1e-4 or absf(towards - (c + 30.0) / c) > 1e-4:
		errors.append("Doppler: a car coming at 30 m/s is %.4f (want %.4f), going away %.4f (want %.4f), the camera closing %.4f" % [coming, c / (c - 30.0), going, c / (c + 30.0), towards])
	if WorldAudio.doppler(src, Vector3(0, 0, 30), lis, Vector3.ZERO) != 1.0:
		errors.append("a car crossing in front of the camera is at its own pitch at that moment")
	if WorldAudio.doppler(src, Vector3(1000, 0, 0), lis, Vector3.ZERO) > 1.6:
		errors.append("Doppler should be capped (a cut is not a car at supersonic speed)")

	for crew in Strategy.CREWS:
		var ev := WorldAudio.pit_events(crew, true)
		var guns := ev.filter(func(e): return e[1] == "gun")
		var total := Strategy.service_time(crew, false, true, 0.0)
		if ev[0][1] != "jack" or guns.size() != 8:
			errors.append("a %s tyre stop should start with the jack and have eight wheel-gun bursts: %s" % [crew, ev])
		for i in range(1, ev.size()):
			if ev[i][0] < ev[i - 1][0]:
				errors.append("the %s crew's sounds should be in order" % crew)
				break
		if not guns.is_empty() and (guns[4][0] - guns[3][0] < 1.0 or guns[-1][0] > total - 0.2):
			errors.append("the %s crew should do the wheels up after the tyres are on and before the stop ends (%.1f s): %s" % [crew, total, guns])
	if WorldAudio.pit_events("club", false).size() != 1:
		errors.append("a stop without tyres is only the jack")

## The node following a race on screen, with a stand-in for the Game.
func _in_the_world(errors: Array[String]) -> void:
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var world = load("res://ui/race_world.tscn").instantiate()
	root.add_child(world)
	var st := RaceSettings.new()
	st.track = "monza"
	st.opponents = 7
	st.laps = 1
	var race := Race.new(st, null, 2)
	race.set_autopilot(true)
	world.set_race(race)
	world.overview = false
	world.camera_mode = 0
	var stub := GDScript.new()
	stub.source_code = "extends Node\nvar race\nvar world_view\nvar audio\nvar _starting := false\nvar paused := false\nvar skipping := false\n"
	stub.reload()
	var game: Node = stub.new()
	game.world_view = world
	game.audio = RaceAudio.new()
	game.add_child(game.audio)
	root.add_child(game)
	var wa := WorldAudio.new(game)
	game.add_child(wa)

	# the race is not on screen yet: nothing listens to it
	wa._process(1.0 / 60.0)
	if race.hear_impacts:
		errors.append("a race that isn't on screen should not be listened to")
	game.race = race
	var idle := Race.PlayerInput.new()
	for f in 30:
		race.step(1.0 / 60.0, idle)
		world._process(1.0 / 60.0)
		wa._process(1.0 / 60.0)
	if not race.hear_impacts:
		errors.append("the race on screen should log its hits for the sound")
	if AudioServer.get_bus_index("Car") < 0 or AudioServer.get_bus_index("World") < 0:
		errors.append("the Car and World buses should exist")
	if game.audio.player.bus != &"Car":
		errors.append("the player's engine should go through the Car bus")
	if not world.get_viewport().audio_listener_enable_3d:
		errors.append("the race view should listen to sounds in the world")
	# the engine slots go to the cars nearest the camera
	var cam: Vector3 = world.camera.global_position
	var by_dist: Array = race.cars.filter(func(c): return not c.is_player)
	by_dist.sort_custom(func(a, b): return world.visuals[a.id].global_position.distance_to(cam) < world.visuals[b.id].global_position.distance_to(cam))
	var heard := {}
	for id in wa._engine_car:
		if id >= 0:
			heard[id] = true
	var nearest: Array = by_dist.slice(0, WorldAudio.ENGINE_SLOTS)
	for c in nearest:
		if not heard.has(c.id):
			errors.append("car %d, among the %d nearest the camera, should be heard (slots %s)" % [c.id, WorldAudio.ENGINE_SLOTS, wa._engine_car])
			break
	var playing := 0
	for v in wa._engines:
		if v.player.playing:
			playing += 1
	if playing < mini(WorldAudio.ENGINE_SLOTS, by_dist.size()):
		errors.append("the engines in their slots should be playing (%d)" % playing)
	if wa._stands.is_empty():
		errors.append("Monza's grandstands should be found for the crowd")

	# a hit between two other cars near the camera is heard from where they are
	var a: RaceCar = nearest[0]
	var b: RaceCar = nearest[1]
	race._heard(a.x, a.y, 9.0, 1, a.id, b.id)
	var busy := _busy(wa._shots)
	wa._process(1.0 / 60.0)
	if _busy(wa._shots) != busy + 1 or not race.impacts.is_empty():
		errors.append("a crash nearby should play once, from the world, and empty the log")
	# ... and the player's own through the Car bus
	race._heard(race.player.x, race.player.y, 2.0, 1, race.player.id, a.id)
	wa._process(1.0 / 60.0)
	if _busy(wa._car_shots) != 1:
		errors.append("the player's own bump should be heard on the car")
	# the same two cars still touching a moment later is the same hit
	race._heard(race.player.x, race.player.y, 2.2, 1, race.player.id, a.id)
	wa._process(1.0 / 60.0)
	if _busy(wa._car_shots) != 1:
		errors.append("two cars leaning on each other should not rattle off a bump every frame")

	# a trackside camera hears the player's car from where it stands
	world.camera.global_position = world.visuals[race.player.id].global_position + Vector3(120, 20, 0)
	world.camera_mode = 3
	wa._process(1.0 / 60.0)
	var far_db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Car"))
	if far_db > -15.0:
		errors.append("from 120 m the player's car should be much quieter, got %.1f dB" % far_db)
	world.camera_mode = 0
	world._process(1.0 / 60.0)
	wa._process(1.0 / 60.0)
	if AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Car")) != 0.0:
		errors.append("riding with the car its sounds are at full volume")

	# pausing silences the world; leaving the race forgets it
	game.paused = true
	for f in 60:
		wa._process(1.0 / 60.0)
	for v in wa._engines + wa._crowds:
		if v.player.playing:
			errors.append("paused, the engines and crowds should fall silent")
			break
	game.paused = false
	game.race = null
	wa._process(1.0 / 60.0)
	if wa._race != null:
		errors.append("back on the menus the sound should let go of the race")

	# a stream still playing when its node goes outlives it: stop them all and let the mixer see that
	game.audio.player.stop()
	wa._exit_tree()
	OS.delay_msec(120)
	game.free()
	world.free()
	race.dispose()

func _busy(players: Array) -> int:
	var n := 0
	for p in players:
		if p.playing:
			n += 1
	return n
