## Options → Audio: the volume of each kind of sound, 0..100 % in 10 % steps (0 mutes it, 100 % is the level
## the game was mixed at, 0 dB). Every sound plays on a bus under Master:
##   Car    (WorldAudio turns it with the camera: level, pan, the air's low-pass)
##     Engine  the player's synthesised engine (RaceAudio, with its gear whine and pit beeps)
##     CarFx   the player's car: kerbs, gravel, grass, scrapes, wind, spray, its hits
##   World  the other cars, the crowds, rain and hail, the hits around the circuit, the pit crews
## ENGINE drives the Engine bus, EFFECTS both CarFx and World. The co-driver speaks through the system's
## text-to-speech, outside Godot's mixer, so his volume (with MASTER's) is handed to tts_speak instead.
## The levels are kept in graphics.cfg [audio] (Game._load_graphics_settings / _save_graphics_settings).
class_name AudioSettings
extends RefCounted

const CHANNELS := [
	{"key": "master", "name": "MASTER VOLUME", "buses": ["Master"]},
	{"key": "engine", "name": "ENGINE", "buses": ["Engine"]},
	{"key": "effects", "name": "EFFECTS", "buses": ["CarFx", "World"]},
	{"key": "voice", "name": "CO-DRIVER VOICE", "buses": []},
]
## Each bus and the bus it sends to, in creation order: a bus may only send to one before it.
const BUSES := [["Car", "Master"], ["Engine", "Car"], ["CarFx", "Car"], ["World", "Master"]]
const STEPS := 10 ## 10 % a step
const SILENT_DB := -80.0

static var levels := {"master": 100, "engine": 100, "effects": 100, "voice": 100} ## percent

## The picker's entries, index = level / 10.
static func step_names() -> Array:
	var out := ["Off"]
	for i in range(1, STEPS + 1):
		out.append("%d%%" % (i * 100 / STEPS))
	return out

## Makes the buses (once; WorldAudio adds its effects to Car) and routes them as BUSES says.
static func ensure_buses() -> void:
	for pair in BUSES:
		var i := AudioServer.get_bus_index(pair[0])
		if i < 0:
			AudioServer.add_bus()
			i = AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, pair[0])
		AudioServer.set_bus_send(i, pair[1])

static func level(key: String) -> int:
	return int(levels.get(key, 100))

static func set_level(key: String, percent: int) -> void:
	levels[key] = clampi(snappedi(percent, 100 / STEPS), 0, 100)
	apply()

## dB for a level: 100 % is exactly 0 dB, 0 % is silence.
static func db(percent: int) -> float:
	return SILENT_DB if percent <= 0 else maxf(SILENT_DB, linear_to_db(percent / 100.0))

## Sets every bus's volume (and mute at 0 %) from the levels.
static func apply() -> void:
	ensure_buses()
	for ch in CHANNELS:
		for bus_name in ch.buses:
			var i := AudioServer.get_bus_index(bus_name)
			if i < 0:
				continue
			AudioServer.set_bus_volume_db(i, db(level(ch.key)))
			if bus_name != "World": # WorldAudio mutes World with M itself, and asks effects_silent()
				AudioServer.set_bus_mute(i, level(ch.key) <= 0)

static func effects_silent() -> bool:
	return level("effects") <= 0

## The co-driver's text-to-speech volume (0..100) for a voice mixed at base: scaled by VOICE and MASTER.
static func voice_volume(base: int) -> int:
	return clampi(roundi(base * level("voice") / 100.0 * level("master") / 100.0), 0, 100)

static func load_from(config: ConfigFile) -> void:
	for ch in CHANNELS:
		levels[ch.key] = clampi(snappedi(int(config.get_value("audio", ch.key + "_volume", 100)), 100 / STEPS), 0, 100)

static func save_to(config: ConfigFile) -> void:
	for ch in CHANNELS:
		config.set_value("audio", ch.key + "_volume", level(ch.key))
