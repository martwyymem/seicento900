## The player's best lap on each circuit, one for dry and one for wet running, and the ghost of the lap that
## set it. During a race it records every flying lap the player drives themself (from one crossing of the line
## to the next, with no autopilot, no pit stop and the car on the tarmac throughout, as qualifying requires) at
## DT intervals. Such a lap faster than the record replaces it and its ghost. It also gives the live gap to the record at the player's point on the lap.
## Kept in user://lap_records.json, with each ghost in user://ghosts/<track>_<dry|wet>.ghost.
class_name LapRecords
extends RefCounted

const VER := 1
const FILE := "lap_records.json"
const GHOST_DIR := "ghosts"
const DT := 0.05 ## s between ghost samples (every 6th tick at 120 Hz)
const STRIDE := 7 ## floats per sample: x, y, heading, s, d, speed, brake
const WET_AT := 0.25 ## mean track wetness over a lap from which it counts as a wet lap
const CONDITIONS := ["dry", "wet"]

static var _store = null
## Off in tests: records then live in memory only.
static var use_disk := true
## Tests drive their laps on autopilot; the game never counts those.
static var count_autopilot := false
static var _memory_ghosts := {} ## track -> {cond: samples} when use_disk is off

var race: Race
var track_key := ""
var conditions := "dry" ## of the ghost being chased (taken from the track at the start of each lap)
var ghost := PackedFloat32Array() ## samples of the record lap for those conditions (empty = none yet)
var ghost_time = null ## its lap time, or null
var new_records: Array = [] ## [{t, conditions}] set in this race
var _rec := PackedFloat32Array()
var _rec_flying := false
var _rec_clean := true
var _rec_wet := 0.0
var _next_t := 0.0
var _laps_seen := 0
var _lap_seen := 0

func _init(race_: Race) -> void:
	race = race_
	track_key = race.s.track
	var p := race.player
	_laps_seen = p.lap_times.size()
	_lap_seen = p.lap
	_use_ghost(_track_conditions())

# ---------------- store ----------------
static func load_store() -> Dictionary:
	if _store != null:
		return _store
	var s = null
	if use_disk and FileAccess.file_exists(SaveData.path(FILE)):
		s = JSON.parse_string(FileAccess.get_file_as_string(SaveData.path(FILE)))
	if not (s is Dictionary) or s.get("v") != float(VER):
		s = {"v": VER, "tracks": {}, "ghost": {"solo": true, "race": false}}
	_store = s
	return _store

static func _save_store() -> void:
	if not use_disk:
		return
	var f := FileAccess.open(SaveData.path(FILE), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_store))

## {t, date, tyre, assists, gearbox} of the record for these conditions, or {} if there is none.
static func record(track: String, cond: String) -> Dictionary:
	return load_store().tracks.get(track, {}).get(cond, {})

## Drops a circuit's records and ghosts.
static func forget(track: String) -> void:
	load_store().tracks.erase(track)
	_save_store()
	for cond in CONDITIONS:
		if use_disk and FileAccess.file_exists(_ghost_path(track, cond)):
			DirAccess.remove_absolute(_ghost_path(track, cond))
	_memory_ghosts.erase(track)

## Whether the ghost is drawn: one preference for driving alone (qualifying, or no opponents) and one for racing.
static func ghost_shown(solo: bool) -> bool:
	return bool(load_store().get("ghost", {}).get("solo" if solo else "race", solo))

static func set_ghost_shown(solo: bool, on: bool) -> void:
	var st := load_store()
	if not st.has("ghost"):
		st.ghost = {"solo": true, "race": false}
	st.ghost["solo" if solo else "race"] = on
	_save_store()

static func _ghost_path(track: String, cond: String) -> String:
	return SaveData.path("%s/%s_%s.ghost" % [GHOST_DIR, track, cond])

static func load_ghost(track: String, cond: String) -> PackedFloat32Array:
	if not use_disk:
		return _memory_ghosts.get(track, {}).get(cond, PackedFloat32Array())
	var path := _ghost_path(track, cond)
	if not FileAccess.file_exists(path):
		return PackedFloat32Array()
	var f := FileAccess.open(path, FileAccess.READ)
	var v = f.get_var() if f else null
	return v if v is PackedFloat32Array and v.size() % STRIDE == 0 else PackedFloat32Array()

static func _save_ghost(track: String, cond: String, samples: PackedFloat32Array) -> void:
	if not use_disk:
		if not _memory_ghosts.has(track):
			_memory_ghosts[track] = {}
		_memory_ghosts[track][cond] = samples
		return
	DirAccess.make_dir_recursive_absolute(SaveData.path(GHOST_DIR))
	var f := FileAccess.open(_ghost_path(track, cond), FileAccess.WRITE)
	if f:
		f.store_var(samples)

# ---------------- recording ----------------
func _track_conditions() -> String:
	return "wet" if race.weather.wet >= WET_AT else "dry"

func _use_ghost(cond: String) -> void:
	conditions = cond
	ghost = load_ghost(track_key, cond)
	var r := record(track_key, cond)
	ghost_time = r.t if r.has("t") and not ghost.is_empty() else null

## Call after every Race.step.
func tick() -> void:
	var p := race.player
	if p.lap_times.size() != _laps_seen:
		# the player has crossed the line: close the lap just driven and start recording the next
		_laps_seen = p.lap_times.size()
		_lap_done(p)
		_start_lap(p)
	elif p.lap < _lap_seen:
		_rec_flying = false # backed over the line: this lap no longer runs line to line
	_lap_seen = p.lap
	if not _rec_flying:
		return
	if p.finished or p.dnf:
		_rec_flying = false
		return
	if (p.autopilot and not count_autopilot) or p.mode == "pit" or p.invalid_lap or absf(p.d) > race.track.half + 1.0:
		_rec_clean = false
	var t := race.race_time - p.lap_start
	if t + 1e-4 >= _next_t:
		_rec.append(p.x)
		_rec.append(p.y)
		_rec.append(p.heading)
		_rec.append(p.s)
		_rec.append(p.d)
		_rec.append(p.speed)
		_rec.append(1.0 if p.brake_on else 0.0)
		_rec_wet += race.weather.wet
		_next_t += DT

func _start_lap(p: RaceCar) -> void:
	_rec = PackedFloat32Array()
	_rec_flying = p.lap >= 1 and not p.finished and not p.dnf # lap 1 starts from the grid
	_rec_clean = count_autopilot or not p.autopilot
	_rec_wet = 0.0
	_next_t = 0.0
	var cond := _track_conditions()
	if cond != conditions:
		_use_ghost(cond)

func _lap_done(p: RaceCar) -> void:
	var n := _rec.size() / STRIDE
	if not _rec_flying or not _rec_clean or n < 2 or p.last_lap == null:
		return
	var lt: float = p.last_lap
	if n * DT < lt - 2.0 * DT:
		return # not recorded right through
	var cond := "wet" if _rec_wet / n >= WET_AT else "dry"
	var old := record(track_key, cond)
	if old.has("t") and lt >= float(old.t):
		return
	var st := load_store()
	if not st.tracks.has(track_key):
		st.tracks[track_key] = {}
	st.tracks[track_key][cond] = {"t": lt, "date": Time.get_date_string_from_system(), "tyre": p.tyre.c,
		"assists": race.s.assists, "gearbox": race.s.gearbox}
	_save_store()
	_save_ghost(track_key, cond, _rec)
	new_records.append({"t": lt, "conditions": cond})
	var was := " (was %s)" % Race.fmt_time(float(old.t)) if old.has("t") else ""
	race.log_event("New %s lap record at %s: %s%s" % [cond, race.track.name, Race.fmt_time(lt), was], "purple")
	if cond == conditions:
		ghost = _rec
		ghost_time = lt

# ---------------- playback ----------------
## Whether the player is on a lap the ghost can be raced against.
func chasing() -> bool:
	var p := race.player
	return _rec_flying and not ghost.is_empty() and race.phase == "racing" and not p.finished and not p.dnf

## Number of samples in the ghost.
func samples() -> int:
	return ghost.size() / STRIDE

## The ghost's state lap_t seconds into its lap, interpolated: [x, y, heading, s, d, speed, brake],
## or [] once it has finished the lap.
func pose(lap_t: float) -> Array:
	var n := samples()
	var f := maxf(0.0, lap_t) / DT
	var i := int(f)
	if i + 1 >= n:
		return []
	var a := f - i
	var o := i * STRIDE
	var q := o + STRIDE
	var heading := ghost[o + 2] + SimUtil.wrap_angle(ghost[q + 2] - ghost[o + 2]) * a
	var s := ghost[o + 3] + (ghost[q + 3] - ghost[o + 3]) * a
	return [lerpf(ghost[o], ghost[q], a), lerpf(ghost[o + 1], ghost[q + 1], a), heading, s,
		lerpf(ghost[o + 4], ghost[q + 4], a), lerpf(ghost[o + 5], ghost[q + 5], a), ghost[o + 6] if a < 0.5 else ghost[q + 6]]

## Seconds the player is behind (+) or ahead (−) of the record at their point on this lap, or null.
func gap() -> Variant:
	if not chasing():
		return null
	var p := race.player
	var n := samples()
	# the ghost's distance along the lap only grows, so search it for the player's s
	var lo := 0
	var hi := n - 1
	if p.s <= ghost[3]:
		return race.race_time - p.lap_start
	if p.s >= ghost[hi * STRIDE + 3]:
		return null
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if ghost[mid * STRIDE + 3] <= p.s:
			lo = mid
		else:
			hi = mid
	var s0 := ghost[lo * STRIDE + 3]
	var s1 := ghost[hi * STRIDE + 3]
	var a := (p.s - s0) / (s1 - s0) if s1 > s0 else 0.0
	return (race.race_time - p.lap_start) - (lo + a) * DT
