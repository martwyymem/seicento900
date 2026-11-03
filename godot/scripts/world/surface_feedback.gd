## What the open-world car's tyres say about the ground: dust off dirt and gravel roads, grass and gravel
## kicked up off the road, tyre smoke in a slide on tarmac (race_car_visual.gd surface_fx, the races' rules), and the
## gravel crunch, the grass swish and the wind (the baked loops WorldAudio plays in a race, at its levels).
## The open world has no weather, so the road is always dry.
class_name SurfaceFeedback
extends Node

const CarVisual := preload("res://scripts/ui/race_car_visual.gd")
const KICK_ORDER := [Physics.SURF_GRAVEL, Physics.SURF_GRAVEL_ROAD, Physics.SURF_DIRT, Physics.SURF_GRASS]

var _gravel: WorldAudio.Voice
var _grass: WorldAudio.Voice
var _wind: WorldAudio.Voice

func _ready() -> void:
	AudioSettings.ensure_buses()
	_gravel = _voice("gravel")
	_grass = _voice("grass")
	_wind = _voice("wind")
	reset_car_bus()

func reset_car_bus() -> void:
	# a race leaves the Car bus set for its last camera (quieter, panned, dulled from a trackside one); the open
	# world always rides with the car
	var car_bus := AudioServer.get_bus_index("Car")
	if car_bus >= 0:
		AudioServer.set_bus_volume_db(car_bus, 0.0)
		for e in AudioServer.get_bus_effect_count(car_bus):
			var fx := AudioServer.get_bus_effect(car_bus, e)
			if fx is AudioEffectPanner:
				(fx as AudioEffectPanner).pan = 0.0
			elif fx is AudioEffectLowPassFilter:
				AudioServer.set_bus_effect_enabled(car_bus, e, false)

func _voice(sound: String) -> WorldAudio.Voice:
	var p := AudioStreamPlayer.new()
	p.stream = WorldAudio.stream(sound)
	p.bus = "CarFx"
	add_child(p)
	var v := WorldAudio.Voice.new()
	v.player = p
	return v

## Share of the wheels on each kind of loose ground: [grass, gravel crunch] (0..1). A gravel trap or deep water
## crunches fully, a gravel road at WorldAudio.LOOSE_ROAD_CRUNCH[1] and a dirt road at [0].
static func contact(surfs: PackedInt32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array([0.0, 0.0])
	if surfs.is_empty():
		return out
	var w := 1.0 / surfs.size()
	for s in surfs:
		if s == Physics.SURF_GRASS:
			out[0] += w
		elif s == Physics.SURF_GRAVEL:
			out[1] += w
		elif s == Physics.SURF_DIRT or s == Physics.SURF_GRAVEL_ROAD:
			out[1] += w * WorldAudio.LOOSE_ROAD_CRUNCH[s - Physics.SURF_DIRT]
	return out

## The surface that shows: the loosest any wheel is on (a wheel in the gravel throws gravel whatever the others do).
static func kick_surface(surfs: PackedInt32Array) -> int:
	for k in KICK_ORDER:
		if surfs.has(k):
			return k
	return surfs[0] if not surfs.is_empty() else Physics.SURF_TRACK

## One frame. car: the FreeCar (null or airborne: everything fades), vis: its car visual (or null).
func update(car: FreeCar, vis: Node, delta: float) -> void:
	var live := car != null and not car.airborne
	var v := absf(car.car.speed) if live else 0.0
	var surfs := car.wheel_surfaces() if live and not car.in_water else PackedInt32Array()
	var on := contact(surfs)
	var go := clampf(v / 25.0, 0.0, 1.0)
	var rough := pow(clampf(v / 20.0, 0.0, 1.0), 0.8)
	WorldAudio.drive(_grass, on[0] * rough, WorldAudio.GRASS_DB, 0.8 + 0.4 * go, delta)
	WorldAudio.drive(_gravel, on[1] * rough, WorldAudio.GRAVEL_DB, 0.75 + 0.5 * go, delta)
	var air := clampf((absf(car.car.speed) if car else 0.0) / WorldAudio.WIND_FULL, 0.0, 1.0)
	WorldAudio.drive(_wind, air * air, WorldAudio.WIND_DB, 0.8 + 0.4 * air, delta, 4.0, 4.0)
	if vis and vis.has_method("set_fx"):
		var want := {}
		if not surfs.is_empty():
			want = CarVisual.surface_fx(kick_surface(surfs), v, car.car.slip, 0.0, 0.0, false)
		vis.set_fx(want)

## Out of the drive (paused, a menu, the race takes over): the loops die away and the kick-up stops.
func silence(vis: Node = null) -> void:
	var dt := get_process_delta_time()
	for v in [_gravel, _grass, _wind]:
		if v:
			WorldAudio.fade(v, dt)
	if vis and vis.has_method("set_fx"):
		vis.set_fx({})

func stop_all() -> void:
	for v in [_gravel, _grass, _wind]:
		if v:
			v.gain = 0.0
			v.player.stop()
