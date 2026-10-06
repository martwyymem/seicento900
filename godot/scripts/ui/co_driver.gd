## The co-driver, as in Colin McRae Rally 2.0: reads the circuit's pace notes (PaceNotes) aloud a few
## seconds before each corner, with the system's text-to-speech voice (a British English one when there is
## one), and keeps the notes it has called until the car is through them, for the HUD's arrow boxes.
## Calls stop under time warp, in the pit lane and once the race is over, and the voice is quiet while the
## co-driver is driving (autopilot); with the voice off the notes still come up on the HUD.
class_name CoDriver
extends RefCounted

const LEAD_TIME := 2.6 ## s before a corner the co-driver calls it, at the speed the car is doing
const LEAD_MIN := 55.0 ## m: never later than this before the corner
const LEAD_MAX := 190.0 ## m: and never earlier than this (the next call would come too long before its corner)
const JUMP := 60.0 ## m the car may move between updates before the calls start over from where it is
const RATE := 1.25 ## speech rate: co-drivers read quickly
const VOLUME := 85 ## 0..100

static var _cache := {} ## track key -> PaceNotes
static var _voice := "" ## the TTS voice picked on first use ("" none)
static var _voice_picked := false

var race: Race
var notes: PaceNotes
var voice_on := true ## speak the calls (the HUD shows them either way)
var live: Array = [] ## indices of the notes called whose corner the car hasn't left yet, in order
var _next := -1
var _last_s := NAN

func _init(race_: Race) -> void:
	race = race_
	var key := race.track.key
	if not _cache.has(key):
		_cache[key] = PaceNotes.new(race.track)
	notes = _cache[key]
	# find the voice now, while the race loads: listing the system's voices takes some 70 ms, a visible
	# stutter if it waited for the first call
	can_speak()

## Whether this machine can speak (the project setting and a voice).
static func can_speak() -> bool:
	if not ProjectSettings.get_setting("audio/general/text_to_speech", false):
		return false
	if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		return false
	return _pick_voice() != ""

static func _pick_voice() -> String:
	if _voice_picked:
		return _voice
	_voice_picked = true
	var best := -1
	for v in DisplayServer.tts_get_voices():
		var lang := str(v.get("language", ""))
		var score := 3 if lang.begins_with("en_GB") or lang.begins_with("en-GB") else (2 if lang.begins_with("en_AU") or lang.begins_with("en-AU") else (1 if lang.begins_with("en") else -1))
		# the default macOS British voice
		if str(v.get("name", "")).begins_with("Daniel"):
			score += 1
		if score > best:
			best = score
			_voice = str(v.get("id", ""))
	return _voice

## The notes for the HUD: the live ones, the nearest first.
func current() -> Array:
	var out: Array = []
	for idx in live:
		out.append(notes.notes[idx])
	return out

## Call every frame while the race is on screen. muted: the game's sound is off.
func update(muted: bool, warp: int) -> void:
	var p := race.player
	if notes.notes.is_empty() or p == null:
		return
	var tr := race.track
	var quiet := race.phase != "racing" or p.finished or p.dnf or p.mode != "race" or warp > 1
	if quiet:
		# start over from wherever the car is when the calls resume
		_next = -1
		live.clear()
		return
	var s := p.s
	if _next < 0 or is_nan(_last_s) or absf(tr.rel(s - _last_s)) > JUMP:
		_next = notes.next_from(s)
		live.clear()
	_last_s = s
	# drop the notes the car is through
	while not live.is_empty():
		var first: Dictionary = notes.notes[live[0]]
		if tr.rel(s - first.e) > 0.0 and tr.rel(s - first.s) > 0.0:
			live.pop_front()
		else:
			break
	var speed := maxf(absf(p.speed), p.v if p.control == "rail" else 0.0)
	var lead := clampf(speed * LEAD_TIME, LEAD_MIN, LEAD_MAX)
	var m := notes.notes.size()
	# call every note now within reach, and a note linked to the one just called straight after it
	for _guard in m:
		var note: Dictionary = notes.notes[_next]
		# how far ahead it starts; a note started a few metres back still counts as just reached
		var ahead := tr.wrap_s(note.s - s)
		if ahead > tr.L - 30.0:
			ahead -= tr.L
		if live.has(_next):
			break
		var prev_linked: bool = not live.is_empty() and notes.notes[live[-1]].link != ""
		if ahead > lead and not (prev_linked and ahead < lead + 120.0):
			break
		if ahead > -10.0:
			live.append(_next)
			if voice_on and not muted and not p.autopilot:
				_say(PaceNotes.spoken(note))
		_next = (_next + 1) % m

func _say(text: String) -> void:
	if not can_speak():
		return
	DisplayServer.tts_speak(text, _voice, VOLUME, 1.0, RATE)

## Stops the co-driver mid-sentence (pause, leaving the race).
static func silence() -> void:
	if _voice_picked and _voice != "":
		DisplayServer.tts_stop()
