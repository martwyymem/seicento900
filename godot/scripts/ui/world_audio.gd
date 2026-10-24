## The race's sounds besides the player's own engine (RaceAudio):
## - the other cars nearest the camera, their engines and sliding tyres, pitched by their revs and by Doppler;
## - the player's car on kerbs, grass and gravel, scraping a barrier, the wind and the spray off a wet road;
## - bumps and crashes between cars and into barriers, from Race.impacts;
## - the rain, the crowd in the grandstands (roaring at the start and for the winner), and the pit crews' wheel
##   guns and jacks.
## The sounds are baked by tools/build_sounds.py into res://audio, so this node only places, pitches and fades
## them: Godot's mixer does the per-sample work, not the script.
## The player's car is heard through the "Car" bus, with RaceAudio's engine. Riding with the car it is plain;
## from a trackside or overhead camera the bus is turned down, panned and dulled with the car's distance from the
## camera. Everything else is in the race world (its SubViewport listens through the race camera), or, for the
## rain, all around.
class_name WorldAudio
extends Node

const DIR := "res://audio/"
const LOOPS := ["engine", "kerb", "gravel", "grass", "wind", "rain", "spray", "scrape", "squeal", "crowd"]
const SHOTS := ["impact_0", "impact_1", "impact_2", "bump", "gun", "jack", "cheer"]
const ENGINE_RPM := 4500.0 ## the engine loop is recorded at this speed (ENGINE_RPM in tools/build_sounds.py)
const KERB_RATE := 20.0 ## bumps a second in the kerb loop (KERB_RATE there)
const KERB_RIPPLE := 1.0 ## m between a kerb's ridges
const SOUND_SPEED := 343.0 ## m/s
const ENGINE_SLOTS := 6 ## the nearest other cars are heard; further ones are drowned out anyway
const CROWD_SLOTS := 3 ## grandstands heard at once, the nearest
const SHOT_SLOTS := 8 ## one-shots (hits, wheel guns, cheers) playing at once in the world
const CAR_SHOT_SLOTS := 4 ## ... and on the player's car
const HEAR := 260.0 ## m: a car further from the camera than this is not heard
const HEAR_CROWD := 320.0
const HEAR_HIT := 420.0
const HEAR_PIT := 90.0 ## m: another crew's pit stop is heard this close
const ONBOARD := [0, 1, 2, 6, 7] ## camera modes that ride with the car (RaceWorld.camera_mode)
const IN_CAR := [2, 6, 7] ## ... and of those, the ones on the car itself, where the wind is loudest
const BARRIER_HIT := 1.5 ## m/s closing speed from which a barrier contact is a crash, not a scrape
const CAR_HIT := 0.8 ## ... and a car-to-car contact a bump
const CAR_CRASH := 4.5 ## ... and from which it is a crash, not a bump
const REPEAT := 0.25 ## s: the same two things hitting again this soon are still the same hit

# levels (dB) at full strength; a loop is levelled at -18 dBFS RMS, a one-shot at a -1 dBFS peak, and the
# player's own engine (RaceAudio) runs at about -28 dBFS RMS
## m: a car this close to the camera is heard at its full level, and further off it fades as sound does (-6 dB for
## each doubling). The player's car (the Car bus, from a camera off the car) and the others alike, so the field
## sounds the same from a trackside camera as it does when racing in it
const NEAR := 15.0
const ENGINE_DB := -20.0 ## another car at full throttle, within NEAR of the camera; with a pack round you, your own car stays on top
const SQUEAL_DB := -22.0
const KERB_DB := -9.0
const GRAVEL_DB := -9.0
const GRASS_DB := -13.0
const SCRAPE_DB := -8.0
const WIND_DB := -17.0 ## at WIND_FULL, from a chase camera ...
const WIND_IN_CAR := 4.0 ## ... and this much louder on the car
const WIND_FULL := 45.0 ## m/s
const SPRAY_DB := -13.0
const RAIN_DB := -15.0
const CROWD_DB := -14.0 ## within CROWD_NEAR of a grandstand
const CROWD_NEAR := 18.0
const CHEER_DB := -2.0
const IMPACT_DB := -5.0 ## the hardest hit
const BUMP_DB := -10.0
const GUN_DB := -11.0
const JACK_DB := -9.0
const CAR_BUS_FLOOR := -30.0 ## dB: from a camera off the car, the player's car is never quieter than this

static var _streams := {}

var game: Node ## the Game, which owns the race, the world and RaceAudio
var world: Node3D
var _race: Race = null
var _car_bus := -1
var _world_bus := -1
var _engines: Array[Voice] = []
var _squeals: Array[Voice] = []
var _engine_car: Array[int] = [] ## car id per engine slot, -1 free
var _engine_last := PackedVector3Array() ## each slot's position last frame, for its speed
var _engine_doppler := PackedFloat32Array()
var _crowds: Array[Voice] = []
var _crowd_stand: Array[int] = []
var _stands := PackedVector3Array() ## where each grandstand's crowd sits
var _stands_root: Node = null ## the track the stands were found on
var _shots: Array[AudioStreamPlayer3D] = []
var _car_shots: Array[AudioStreamPlayer] = []
var _shot_i := 0
var _car_shot_i := 0
var _kerb: Voice
var _gravel: Voice
var _grass: Voice
var _scrape: Voice
var _wind: Voice
var _spray: Voice
var _rain: Voice
var _last_hit := {} ## pair key -> [time, closing speed]
var _pits := {} ## car id -> {start, events: [[t, sound, pitch]], next}
var _cam_last := Vector3.ZERO
var _cam_vel := Vector3.ZERO
var _cam_mode := -1
var _bus_db := 0.0
var _phase := ""
var _winner_cheered := false
var _player_cheered := false
var _clock := 0.0

## A looping sound, how loud it is now (0..1 of its full level, db) and its pitch.
class Voice:
	var player: Node ## AudioStreamPlayer or AudioStreamPlayer3D
	var gain := 0.0
	var db := 0.0
	var pitch := 1.0

func _init(game_: Node = null) -> void:
	game = game_

func _ready() -> void:
	AudioSettings.ensure_buses() # Car, Engine and CarFx under it, World (Options → Audio)
	_car_bus = _bus("Car")
	_world_bus = _bus("World")
	if AudioServer.get_bus_effect_count(_car_bus) == 0:
		AudioServer.add_bus_effect(_car_bus, AudioEffectPanner.new())
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(_car_bus, lp)
		AudioServer.set_bus_effect_enabled(_car_bus, 1, false)
	_kerb = _flat("kerb", "CarFx")
	_gravel = _flat("gravel", "CarFx")
	_grass = _flat("grass", "CarFx")
	_scrape = _flat("scrape", "CarFx")
	_wind = _flat("wind", "CarFx")
	_spray = _flat("spray", "CarFx")
	_rain = _flat("rain", "World")
	for i in CAR_SHOT_SLOTS:
		var p := AudioStreamPlayer.new()
		p.bus = "CarFx"
		add_child(p)
		_car_shots.append(p)

## The bus called bus_name, made the first time (sent to Master).
static func _bus(bus_name: String) -> int:
	var i := AudioServer.get_bus_index(bus_name)
	if i < 0:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, bus_name)
		AudioServer.set_bus_send(i, "Master")
	return i

## A baked sound, or null if it is missing (then that sound is simply not heard).
static func stream(sound: String) -> AudioStream:
	if not _streams.has(sound):
		var path := DIR + sound + ".wav"
		var st: AudioStream = load(path) if ResourceLoader.exists(path) else null
		if st == null:
			push_warning("WorldAudio: %s is missing; run tools/build_sounds.py" % path)
		elif st is AudioStreamWAV and sound in LOOPS:
			# the importer takes the loop from the file's smpl chunk; make sure of it all the same
			var wav := st as AudioStreamWAV
			if wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
				wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
				wav.loop_begin = 0
				wav.loop_end = roundi(wav.get_length() * wav.mix_rate)
		_streams[sound] = st
	return _streams[sound]

func _flat(sound: String, bus: String) -> Voice:
	var p := AudioStreamPlayer.new()
	p.stream = stream(sound)
	p.bus = bus
	add_child(p)
	var v := Voice.new()
	v.player = p
	return v

func _spatial(sound: String, unit: float, reach: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream(sound) if sound != "" else null
	p.bus = "World"
	p.unit_size = unit
	p.max_db = 0.0
	p.max_distance = reach
	p.attenuation_filter_cutoff_hz = 6000.0
	p.attenuation_filter_db = -18.0
	world.add_child(p)
	return p

func _spatial_voice(sound: String, unit: float, reach: float) -> Voice:
	var v := Voice.new()
	v.player = _spatial(sound, unit, reach)
	return v

## Fades a loop towards level (0..1 of full_db) at pitch: it starts playing (somewhere in the loop) when it
## becomes audible and stops once it is silent, so a quiet loop costs the mixer nothing.
static func drive(v: Voice, level: float, full_db: float, pitch: float, delta: float, attack := 14.0, release := 7.0) -> void:
	v.db = full_db
	v.pitch = pitch
	v.gain += (level - v.gain) * minf(1.0, delta * (attack if level > v.gain else release))
	var p = v.player
	if v.gain < 0.004 or p.stream == null:
		if p.playing:
			p.stop()
		return
	p.volume_db = full_db + linear_to_db(v.gain)
	p.pitch_scale = clampf(pitch, 0.05, 4.0)
	if not p.playing:
		p.play(randf() * p.stream.get_length())

## Fades a loop out at its own level and pitch.
static func fade(v: Voice, delta: float, release := 20.0) -> void:
	drive(v, 0.0, v.db, v.pitch, delta, 14.0, release)

## Pitch factor of a sound from a source at src moving at src_v (m/s), heard at lis by a listener moving at lis_v.
static func doppler(src: Vector3, src_v: Vector3, lis: Vector3, lis_v: Vector3) -> float:
	var u := lis - src
	if u.length_squared() < 0.01:
		return 1.0
	u = u.normalized()
	var toward_listener := src_v.dot(u)
	var toward_source := -lis_v.dot(u)
	return clampf((SOUND_SPEED + toward_source) / maxf(1.0, SOUND_SPEED - toward_listener), 0.6, 1.6)

## What a car's wheels are on: [kerb, grass, gravel], each the share of the four wheels (0..1).
static func wheel_contact(race: Race, car: RaceCar) -> PackedFloat32Array:
	var out := PackedFloat32Array([0.0, 0.0, 0.0])
	var tr := race.track
	var wx := race.phys.WX # where the wheels sit on the car (no set-up moves them)
	var wy := race.phys.WY
	var ch := cos(car.heading)
	var sh := sin(car.heading)
	var nx := tr.sample(tr.NX, car.s)
	var ny := tr.sample(tr.NY, car.s)
	var kerbs := tr.cfg.kerb_style != "none"
	var inner := tr.half - tr.cfg.kerb_width * 0.54
	var outer := tr.half + tr.cfg.kerb_width * 0.46
	for i in 4:
		var ox := wx[i] * ch - wy[i] * sh
		var oy := wx[i] * sh + wy[i] * ch
		var surf := race.surface_at(car, car.x + ox, car.y + oy)
		if surf == Physics.SURF_GRASS:
			out[1] += 0.25
			continue
		if surf == Physics.SURF_GRAVEL:
			out[2] += 0.25
			continue
		if not kerbs:
			continue
		# the kerbs line the inside of every bend (RaceWorld._build_kerbs), a sample at a time
		var s := tr.wrap_s(car.s + wx[i] * cos(car.heading - tr.heading(car.s)))
		var k := tr.KC[int(s / tr.step) % tr.n]
		if absf(k) < 1.0 / 180.0:
			continue
		var d := (car.d + ox * nx + oy * ny) * signf(k)
		if d >= inner and d <= outer:
			out[0] += 0.25
	return out

## Whether a car is up against a barrier (within a few centimetres of it, where Race.barrier_contact leaves it).
static func touching_barrier(race: Race, car: RaceCar) -> bool:
	if car.control != "free":
		return false
	var tr := race.track
	var lim := tr.limits(car.s)
	var hl := race.spec.length / 2.0
	var hw := race.spec.width / 2.0
	var nx := tr.sample(tr.NX, car.s)
	var ny := tr.sample(tr.NY, car.s)
	var ch := cos(car.heading)
	var sh := sin(car.heading)
	for c in [[hl, hw], [hl, -hw], [-hl, hw], [-hl, -hw]]:
		var ox: float = c[0] * ch - c[1] * sh
		var oy: float = c[0] * sh + c[1] * ch
		var d: float = car.d + ox * nx + oy * ny
		if d > lim[1] + hw - 0.04 or d < lim[0] - hw + 0.04:
			return true
	return false

## A pit crew's work on one stop, as [[seconds into the stop, sound, pitch]] in order: the jack going up, then
## with new tyres the wheel guns undoing the four wheels and, once the tyres are on, doing them up again.
static func pit_events(crew: String, tyres: bool) -> Array:
	var c: Dictionary = Strategy.CREWS.get(crew, Strategy.CREWS.club)
	var out: Array = [[0.0, "jack", 1.15]]
	if tyres:
		var start: float = float(c.fixed) * 0.5
		var tight := maxf(start + 2.2, start + float(c.tyres) - 1.8)
		for i in 4:
			out.append([start + i * 0.45, "gun", 0.97 + 0.02 * i])
		for i in 4:
			out.append([tight + i * 0.45, "gun", 1.03 - 0.02 * i])
	return out

# ---------------- every frame ----------------
func _process(delta: float) -> void:
	if world == null and game:
		world = game.world_view
	var race: Race = game.race if game else null
	if race != _race:
		_start(race)
	var shown: bool = race != null and world != null and world.race == race and not game._starting
	var on: bool = shown and not game.paused and not game.skipping and race.phase != "finished"
	if shown and not _shots.is_empty() and not game.paused:
		# the last car home ends the race: its cheer still rings out over the results
		_update_cheers(race, world.camera.global_position)
	if not on:
		if race:
			race.impacts.clear()
		_silence()
		return
	if _engines.is_empty():
		_build_world_voices()
	var muted: bool = game.audio.muted if is_instance_valid(game.audio) else false
	AudioServer.set_bus_mute(_car_bus, muted)
	AudioServer.set_bus_mute(_world_bus, muted or AudioSettings.effects_silent())
	_clock += delta

	var cam: Camera3D = world.camera
	var cam_pos := cam.global_position
	# a cut (or a new camera) is not the camera flying through the air: no Doppler from it
	if cam_pos.distance_to(_cam_last) > 25.0 or world.camera_mode != _cam_mode or delta <= 0.0:
		_cam_vel = Vector3.ZERO
	else:
		_cam_vel = _cam_vel.lerp((cam_pos - _cam_last) / delta, minf(1.0, delta * 10.0))
	_cam_last = cam_pos

	var vis = world.visuals.get(race.player.id)
	_update_car_bus(cam, vis.global_position if vis else cam_pos, delta)
	_cam_mode = world.camera_mode
	_update_player_car(race, delta)
	_update_engines(race, cam_pos, delta)
	_update_crowd(cam_pos, delta)
	if race.weather.hail > 0.1:
		var hail_level := clampf(race.weather.hail, 0.0, 1.0)
		drive(_rain, hail_level, RAIN_DB + 3.0, 1.45, delta, 4.0, 2.0)
	else:
		drive(_rain, clampf(race.weather.rain / 0.7, 0.0, 1.0), RAIN_DB, 1.0, delta, 2.0, 1.0)
	_hear_impacts(race, cam_pos)
	_update_pits(race, cam_pos)

## A new race on screen (or none): forget the last one's sounds and listen for this one's hits.
func _start(race: Race) -> void:
	_race = race
	if race:
		race.hear_impacts = true
		race.impacts.clear()
	_last_hit.clear()
	_pits.clear()
	_phase = race.phase if race else ""
	_winner_cheered = false
	_player_cheered = false
	_engine_car.fill(-1)
	_crowd_stand.fill(-1)
	for v in _engines + _squeals + _crowds:
		v.gain = 0.0
		v.player.stop()
	for p in _shots:
		p.stop()
	for p in _car_shots:
		p.stop()

func _exit_tree() -> void:
	_start(null)
	for v in [_kerb, _gravel, _grass, _scrape, _wind, _spray, _rain]:
		if v:
			v.player.stop()

## Out of the race (paused, on a menu, the race over): the loops die away quickly; a pause also stops the
## one-shots.
func _silence() -> void:
	var dt := get_process_delta_time()
	for v in [_kerb, _gravel, _grass, _scrape, _wind, _spray, _rain]:
		if v:
			fade(v, dt)
	for v in _engines + _squeals + _crowds:
		fade(v, dt)
	if game and game.paused:
		for p in _shots:
			p.stop()
		for p in _car_shots:
			p.stop()

func _build_world_voices() -> void:
	world.get_viewport().audio_listener_enable_3d = true
	for i in ENGINE_SLOTS:
		_engines.append(_spatial_voice("engine", NEAR, HEAR))
		_squeals.append(_spatial_voice("squeal", NEAR, HEAR * 0.6))
		_engine_car.append(-1)
		_engine_last.append(Vector3.ZERO)
		_engine_doppler.append(1.0)
	for i in CROWD_SLOTS:
		_crowds.append(_spatial_voice("crowd", CROWD_NEAR, HEAR_CROWD))
		_crowd_stand.append(-1)
	for i in SHOT_SLOTS:
		_shots.append(_spatial("", 8.0, HEAR_HIT))
	if is_instance_valid(game.audio):
		game.audio.player.bus = "Engine"

## The player's car is heard from where the camera is: plain when riding with it, else turned down with its
## distance, panned to its side of the picture and dulled by the air in between.
func _update_car_bus(cam: Camera3D, car_pos: Vector3, delta: float) -> void:
	var onboard: bool = world.camera_mode in ONBOARD and not world.overview
	var db := 0.0
	var pan := 0.0
	var cutoff := 20000.0
	if not onboard:
		var to_car := car_pos - cam.global_position
		var dist := to_car.length()
		db = maxf(CAR_BUS_FLOOR, -20.0 * log(maxf(1.0, dist / NEAR)) / log(10.0))
		if dist > 0.1:
			pan = clampf(cam.global_transform.basis.x.dot(to_car / dist), -1.0, 1.0) * 0.8
		cutoff = lerpf(16000.0, 2500.0, clampf((dist - 20.0) / 300.0, 0.0, 1.0))
	# a camera change jumps to the new level; within a shot the level eases
	_bus_db = db if world.camera_mode != _cam_mode else _bus_db + (db - _bus_db) * minf(1.0, delta * 8.0)
	AudioServer.set_bus_volume_db(_car_bus, _bus_db)
	var panner := AudioServer.get_bus_effect(_car_bus, 0) as AudioEffectPanner
	if panner:
		panner.pan = pan
	var lp := AudioServer.get_bus_effect(_car_bus, 1) as AudioEffectLowPassFilter
	if lp:
		lp.cutoff_hz = cutoff
		AudioServer.set_bus_effect_enabled(_car_bus, 1, not onboard)

func _update_player_car(race: Race, delta: float) -> void:
	var p := race.player
	var live := not p.finished and not p.dnf
	var v := maxf(absf(p.speed), p.v if p.control == "rail" else 0.0) if live else 0.0
	var on := wheel_contact(race, p) if live else PackedFloat32Array([0.0, 0.0, 0.0])
	var go := clampf(v / 25.0, 0.0, 1.0)
	var rough := pow(clampf(v / 20.0, 0.0, 1.0), 0.8)
	drive(_kerb, minf(1.0, on[0] * 2.0) * pow(go, 0.7), KERB_DB, clampf(v / KERB_RIPPLE / KERB_RATE, 0.4, 2.6), delta, 30.0, 18.0)
	drive(_grass, on[1] * rough, GRASS_DB, 0.8 + 0.4 * go, delta)
	if race.weather.snow > 0.1 and live and (p.slip > 0.12 or absf(p.lat_v) > 0.8):
		var snow_slip := clampf(maxf(p.slip * 1.4, absf(p.lat_v) / 4.0) * race.weather.snow, 0.0, 1.0)
		drive(_gravel, maxf(on[2] * rough, snow_slip * 0.75), GRAVEL_DB - 2.0, 0.58 + 0.25 * go, delta, 25.0, 12.0)
	else:
		drive(_gravel, on[2] * rough, GRAVEL_DB, 0.75 + 0.5 * go, delta)
	var scraping := live and v > 1.5 and touching_barrier(race, p)
	drive(_scrape, pow(clampf(v / 20.0, 0.0, 1.0), 0.7) if scraping else 0.0, SCRAPE_DB, 0.85 + 0.3 * go, delta, 30.0, 12.0)
	var air := clampf(v / WIND_FULL, 0.0, 1.0)
	var onboard: bool = world.camera_mode in ONBOARD and not world.overview
	var wind_db := WIND_DB + (WIND_IN_CAR if world.camera_mode in IN_CAR else 0.0)
	drive(_wind, air * air if onboard else 0.0, wind_db, 0.8 + 0.4 * air, delta, 4.0, 4.0)
	drive(_spray, race.weather.wet * pow(clampf(v / 30.0, 0.0, 1.0), 1.2), SPRAY_DB, 0.8 + 0.4 * air, delta, 6.0, 4.0)

## The other cars nearest the camera get the engine slots. A car keeps its slot until another is clearly nearer,
## so a slot doesn't flap between two cars at much the same distance.
func _update_engines(race: Race, cam_pos: Vector3, delta: float) -> void:
	var cand: Array = []
	var cars: Array = race.cars
	if race.rc and race.rc.sc_state != "garage":
		cars = cars + [race.rc.sc]
	for car in cars:
		if car.is_player or car.recovered or (car.dnf and absf(car.speed) < 0.1):
			continue
		var vis = world.visuals.get(car.id)
		if not vis or not vis.visible:
			continue
		var dist: float = vis.global_position.distance_to(cam_pos)
		if dist > HEAR:
			continue
		cand.append([dist * (0.85 if _engine_car.has(car.id) else 1.0), car, vis])
	cand.sort_custom(func(a, b): return a[0] < b[0])
	if cand.size() > ENGINE_SLOTS:
		cand.resize(ENGINE_SLOTS)
	var wanted := {}
	for c in cand:
		wanted[c[1].id] = c
	# free the slots of cars no longer among the nearest, then give the newcomers the free slots
	for i in ENGINE_SLOTS:
		if _engine_car[i] >= 0 and not wanted.has(_engine_car[i]):
			_engine_car[i] = -1
	for c in cand:
		if _engine_car.has(c[1].id):
			continue
		var free := _engine_car.find(-1)
		if free < 0:
			break
		_engine_car[free] = c[1].id
		_engines[free].gain = 0.0
		_squeals[free].gain = 0.0
		_engine_last[free] = c[2].global_position + Vector3.UP * 0.4
		_engine_doppler[free] = 1.0
	for i in ENGINE_SLOTS:
		var ev := _engines[i]
		var sv := _squeals[i]
		if _engine_car[i] < 0:
			fade(ev, delta)
			fade(sv, delta)
			continue
		var c: Array = wanted[_engine_car[i]]
		var car: RaceCar = c[1]
		var pos: Vector3 = c[2].global_position + Vector3.UP * 0.4
		var vel := Vector3.ZERO
		if delta > 0.0 and pos.distance_to(_engine_last[i]) < 30.0:
			vel = ((pos - _engine_last[i]) / delta).limit_length(120.0)
		_engine_last[i] = pos
		_engine_doppler[i] = lerpf(_engine_doppler[i], doppler(pos, vel, cam_pos, _cam_vel), minf(1.0, delta * 10.0))
		ev.player.global_position = pos
		sv.player.global_position = pos
		var rev := clampf((car.rpm - 1000.0) / 5500.0, 0.0, 1.0)
		var level := (0.35 + 0.65 * clampf(car.throttle, 0.0, 1.0)) * (0.55 + 0.45 * rev)
		drive(ev, level, ENGINE_DB, car.rpm / ENGINE_RPM * _engine_doppler[i], delta, 10.0, 6.0)
		var slide := clampf((car.slip - 0.42) / 0.6, 0.0, 1.0) if car.control == "free" else 0.0
		drive(sv, slide, SQUEAL_DB, _engine_doppler[i], delta, 20.0, 8.0)

## The crowd chattering in the grandstands nearest the camera.
func _update_crowd(cam_pos: Vector3, delta: float) -> void:
	if world.track_root != _stands_root:
		_find_stands()
	var near: Array = []
	for i in _stands.size():
		var dist := _stands[i].distance_to(cam_pos)
		if dist < HEAR_CROWD:
			near.append([dist, i])
	near.sort_custom(func(a, b): return a[0] < b[0])
	var keep := {}
	for k in mini(CROWD_SLOTS, near.size()):
		keep[near[k][1]] = true
	for j in CROWD_SLOTS:
		if _crowd_stand[j] >= 0 and not keep.has(_crowd_stand[j]):
			_crowd_stand[j] = -1
	for stand in keep:
		if _crowd_stand.has(stand):
			continue
		var free := _crowd_stand.find(-1)
		if free < 0:
			break
		_crowd_stand[free] = stand
		_crowds[free].gain = 0.0
		_crowds[free].player.stop() # it starts again somewhere else in the loop, so neighbouring stands don't phase
		_crowds[free].player.global_position = _stands[stand]
	for j in CROWD_SLOTS:
		drive(_crowds[j], 1.0 if _crowd_stand[j] >= 0 else 0.0, CROWD_DB, 1.0, delta, 3.0, 3.0)

## Where the crowds sit: the circuit's own grandstands and those of its surroundings, a few metres up the tiers.
func _find_stands() -> void:
	_stands_root = world.track_root
	_stands = PackedVector3Array()
	if world.track_root == null:
		return
	for pattern in ["Grandstand_*", "Stand_*"]:
		for n in world.find_children(pattern, "Node3D", true, false):
			var xf: Transform3D = n.global_transform
			_stands.append(xf.origin - xf.basis.z.normalized() * 4.0 + Vector3.UP * 3.0)

## The hits since the last frame: the hardest between each pair of things that touched, a bump or a crash by
## how hard. The player's own come through the Car bus, the rest from where they happened.
func _hear_impacts(race: Race, cam_pos: Vector3) -> void:
	var imp := race.impacts
	var n := imp.size() / Race.IMPACT_STRIDE
	if n == 0:
		return
	var hardest := {}
	for i in n:
		var o := i * Race.IMPACT_STRIDE
		var dv := imp[o + 2]
		var kind := int(imp[o + 3])
		if dv < (BARRIER_HIT if kind == 0 else CAR_HIT):
			continue
		var a := int(imp[o + 4])
		var b := int(imp[o + 5])
		var key := mini(a, b) * 256 + maxi(a, b) if kind == 1 else a * 256 + 255
		if not hardest.has(key) or hardest[key][0] < dv:
			hardest[key] = [dv, kind, a, b]
	race.impacts.clear()
	for key in hardest:
		var h: Array = hardest[key]
		var dv: float = h[0]
		var last = _last_hit.get(key)
		if last and _clock - last[0] < REPEAT and dv < last[1] * 1.5:
			continue
		_last_hit[key] = [_clock, dv]
		var crash: bool = h[1] == 0 or dv >= CAR_CRASH
		var size := clampf((dv - BARRIER_HIT) / 12.0, 0.0, 1.0) if crash else clampf(dv / CAR_CRASH, 0.0, 1.0)
		var sound := "impact_%d" % randi_range(0, 2) if crash else "bump"
		var db := (IMPACT_DB if crash else BUMP_DB) + linear_to_db(lerpf(0.25, 1.0, size))
		var pitch := randf_range(0.92, 1.08) * (1.1 - 0.25 * size if crash else 1.0)
		var pid := race.player.id
		if h[2] == pid or h[3] == pid:
			_shot_car(sound, db, pitch)
			continue
		var va = world.visuals.get(h[2])
		var vb = world.visuals.get(h[3]) if h[3] >= 0 else null
		if not va:
			continue
		var pos: Vector3 = va.global_position if not vb else (va.global_position + vb.global_position) * 0.5
		if pos.distance_to(cam_pos) < HEAR_HIT:
			_shot_at(pos + Vector3.UP * 0.5, sound, db, pitch)

## The pit crews at work: the player's own (through the Car bus), and any other car's stop near the camera.
func _update_pits(race: Race, cam_pos: Vector3) -> void:
	for car in race.cars:
		var serving: bool = car.mode == "pit" and car.pit != null and car.pit.phase == "service"
		var job = _pits.get(car.id)
		if serving and job == null:
			var tyres := false
			if car.service and car.service.c:
				tyres = true
			job = {"start": race.race_time, "events": pit_events(race.s.crew, tyres), "next": 0}
			_pits[car.id] = job
		elif not serving and job != null:
			_pits.erase(car.id)
			if race.warp == 1:
				_pit_sound(car, cam_pos, "jack", 0.95) # done: the car drops off the jack
			continue
		if job == null:
			continue
		var t: float = race.race_time - float(job.start)
		var events: Array = job.events
		while job.next < events.size() and float(events[job.next][0]) <= t:
			# under time warp a stop is over in a blink: the crew's sounds would only pile up
			if race.warp == 1:
				_pit_sound(car, cam_pos, events[job.next][1], events[job.next][2])
			job.next += 1

func _pit_sound(car: RaceCar, cam_pos: Vector3, sound: String, pitch: float) -> void:
	var db := GUN_DB if sound == "gun" else JACK_DB
	pitch *= randf_range(0.98, 1.02)
	if car.is_player:
		_shot_car(sound, db, pitch)
		return
	var vis = world.visuals.get(car.id)
	if vis and vis.global_position.distance_to(cam_pos) < HEAR_PIT:
		_shot_at(vis.global_position + Vector3.UP * 0.3, sound, db, pitch)

## The crowd roars as the lights go out, and as the winner and then the player take the flag.
func _update_cheers(race: Race, cam_pos: Vector3) -> void:
	if _phase == "countdown" and race.phase == "racing":
		_cheer(cam_pos)
	_phase = race.phase
	if race.winner and not _winner_cheered:
		_winner_cheered = true
		_player_cheered = _player_cheered or race.winner == race.player
		_cheer(cam_pos)
	if race.player.finished and not _player_cheered:
		_player_cheered = true
		_cheer(cam_pos)

## A cheer from the two grandstands nearest the camera, if there are any within earshot.
func _cheer(cam_pos: Vector3) -> void:
	var near: Array = []
	for i in _stands.size():
		var dist := _stands[i].distance_to(cam_pos)
		if dist < HEAR_CROWD * 1.5:
			near.append([dist, i])
	near.sort_custom(func(a, b): return a[0] < b[0])
	for k in mini(2, near.size()):
		_shot_at(_stands[near[k][1]], "cheer", CHEER_DB, randf_range(0.94, 1.06))

## A one-shot from a place in the world.
func _shot_at(pos: Vector3, sound: String, db: float, pitch: float) -> void:
	var st := stream(sound)
	if st == null or _shots.is_empty():
		return
	var p := _shots[_shot_i]
	_shot_i = (_shot_i + 1) % SHOT_SLOTS
	p.stream = st
	p.global_position = pos
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()

## A one-shot from the player's car (through the Car bus).
func _shot_car(sound: String, db: float, pitch: float) -> void:
	var st := stream(sound)
	if st == null:
		return
	var p := _car_shots[_car_shot_i]
	_car_shot_i = (_car_shot_i + 1) % CAR_SHOT_SLOTS
	p.stream = st
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()
