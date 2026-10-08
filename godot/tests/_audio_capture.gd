## World sound capture (dev tool, run in a window): a short race at Monza recorded off the Master, Car and World
## buses, through the start, a chase-cam lap, a trackside camera, rain, a barrier hit and a bump. Writes
## /tmp/audio_cap/{master,car,world}.wav and prints when each part starts (s into the recording), for
## checking the mix's levels without listening to it.
## godot --path godot -s tests/_audio_capture.gd
extends SceneTree

var game
var t0 := 0

func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	var next := Time.get_ticks_msec()
	while Time.get_ticks_msec() < until:
		_resume()
		if game and game.race and Time.get_ticks_msec() >= next and not game.world_audio._engines.is_empty():
			next += 1000
			_report()
		await process_frame

## The game pauses itself when its window loses focus, as a window started from a terminal soon does.
func _resume() -> void:
	if game and game.race and game.paused:
		game._set_paused(false)

func _mark(part: String) -> void:
	print("PART %.2f %s" % [(Time.get_ticks_msec() - t0) / 1000.0, part])

## Once a second: how loud each of WorldAudio's sounds is (0..1 of its full level).
func _report() -> void:
	var wa: WorldAudio = game.world_audio
	var g := func(v): return snappedf(v.gain, 0.01) if v else -1.0
	var p: RaceCar = game.race.player
	print("  t %.1f v %.0f on %s | kerb %s grass %s gravel %s scrape %s wind %s spray %s rain %s | engines %s | crowds %s" % [
		(Time.get_ticks_msec() - t0) / 1000.0, maxf(absf(p.speed), p.v), WorldAudio.wheel_contact(game.race, p),
		g.call(wa._kerb), g.call(wa._grass), g.call(wa._gravel), g.call(wa._scrape), g.call(wa._wind), g.call(wa._spray), g.call(wa._rain),
		wa._engines.map(g), wa._crowds.map(g)])

func _initialize() -> void:
	Brain.use_disk = false
	LapRecords.use_disk = false
	DirAccess.make_dir_recursive_absolute("/tmp/audio_cap")
	game = load("res://ui/game.tscn").instantiate()
	root.add_child(game)
	await _wait(0.5)
	game.track_picker.select(game.TRACK_KEYS.find("monza"))
	game.track_picker.item_selected.emit(game.TRACK_KEYS.find("monza"))
	game.opponents_picker.value = 7
	game.laps_picker.value = 3
	await _wait(0.5)
	for k in 6000:
		if not game._strategy_pending:
			break
		await process_frame
	game._start_race()
	for k in 6000:
		await process_frame
		if not game._starting:
			break
	var race: Race = game.race
	race.set_autopilot(true)
	var recs := {}
	for bus in ["Master", "Car", "World"]:
		var rec := AudioEffectRecord.new()
		AudioServer.add_bus_effect(AudioServer.get_bus_index(bus), rec)
		rec.set_recording_active(true)
		recs[bus] = rec
	t0 = Time.get_ticks_msec()
	_mark("grid")
	var guard := Time.get_ticks_msec() + 20000
	while race.phase == "countdown" and Time.get_ticks_msec() < guard:
		_resume()
		await process_frame
	print("phase %s clock %.1f paused %s race same %s" % [race.phase, race.clock, game.paused, race == game.race])
	_mark("lights out")
	await _wait(8.0)
	_mark("chase")
	await _wait(5.0)
	game.world_view.camera_mode = 3
	_mark("tv")
	await _wait(5.0)
	game.world_view.camera_mode = 6
	_mark("bumper")
	await _wait(4.0)
	game.world_view.camera_mode = 0
	race.weather.mode = "dry" # else a variable race's forecast puts the rain straight back where it was
	race.weather.rain = 0.8
	race.weather.wet = 0.8
	_mark("rain")
	await _wait(5.0)
	race.weather.rain = 0.0
	race.weather.wet = 0.0
	# off the autopilot and into the barrier at an angle
	var p := race.player
	race.set_autopilot(false)
	var tr := race.track
	var s := tr.wrap_s(p.s + 30.0)
	var d: float = tr.limits(s)[1] - 1.2
	var pos := tr.pos(s, d)
	p.s = s
	p.d = d
	p.x = pos[0]
	p.y = pos[1]
	p.heading = tr.heading(s) + 0.3
	p.vx = cos(p.heading) * 30.0
	p.vy = sin(p.heading) * 30.0
	p.speed = 30.0
	_mark("barrier")
	await _wait(3.0)
	race.set_autopilot(true)
	_mark("end")
	for bus in recs:
		var rec: AudioEffectRecord = recs[bus]
		rec.set_recording_active(false)
		var wav := rec.get_recording()
		if wav:
			wav.save_to_wav("/tmp/audio_cap/%s.wav" % bus.to_lower())
			print("saved ", bus, " ", wav.get_length(), " s at ", wav.mix_rate)
	print("mix rate ", AudioServer.get_mix_rate(), " stands ", game.world_audio._stands.size(), " engines ", game.world_audio._engine_car)
	quit()
