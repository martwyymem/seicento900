## Time trial: solo hot-lapping on any circuit in the conditions picked, laps until the player quits. No pit
## rules, tyre wear or fuel use, no race control. The lap splits into three timed sectors, each coloured
## against the references: purple the best that sector has ever been (the lap record's ghost, or this
## session), green faster than the same sector on this session's best lap, red slower. A live delta to the
## session's best lap (or, until there is one, the HUD falls back on LapRecords.gap() to the record) and a
## lap list with invalid laps (off the tarmac, |d| > half + 1 m, the rule the lap records use) marked.
## Rolling start: the car begins at speed on a short run-up to the line (that run-up is not a lap).
## restart() puts the car back at the start at once, keeping the session's laps and bests.
## The core (advance / cross) needs no Race, for the tests; tick() feeds it from the race every step.
class_name TimeTrial
extends RefCounted

const SECTORS := 3
const TRACE_STEP := 10.0 ## m between the samples of a lap's time trace (for the live delta)
const RUNUP := 220.0 ## m before the line a rolling start begins
const ROLL_SPEED := 30.0 ## m/s at most for a rolling start (less where the road ahead is slower)
const FUEL := 15.0 ## litres carried, fixed (no fuel is used)
const RESTART_LIGHTS := 3.0 ## s of countdown after a standing restart
const OFF := 1.0 ## m beyond the road edge that invalidates a lap

## Turns race settings into a time trial (track, weather, hour, the player's choices stay as they are).
static func configure(st: RaceSettings, rolling := false) -> void:
	st.mode = "time_trial"
	st.rolling_start = rolling
	st.format = "laps"
	st.laps = 9999 # unlimited: the session ends when the player quits
	st.opponents = 0
	st.qualifying = false
	st.quali_grid = {}
	st.mandatory_stop = false
	st.two_compounds = false
	st.refuel = false
	st.race_control = false
	st.auto_strategist = false
	st.ai_learning = "off"
	st.dynamic_running = false
	st.wear_mult = 0.0
	st.fuel_mult = 0.0
	st.draft = false
	st.surface = "tarmac"
	st.stage_from = 0.0
	st.stage_to = 0.0
	st.starting_tyre = "W" if st.weather in ["wet", "snow", "hail"] else "S"

var race: Race = null
var L := 1.0
var laps: Array = [] ## [{n, time, sectors: [s1, s2, s3] (null where not timed), valid, colors}]
var sectors_now: Array = [] ## the sectors completed on this lap
var valid := true ## this lap is still clean
var best_lap = null ## the session's best valid lap
var best_lap_sectors: Array = [] ## its sectors
var best_sectors: Array = [null, null, null] ## the session's best of each sector, over valid laps
var record_sectors: Array = [] ## the sectors of the lap record's ghost for these conditions ([] none)
var record_time = null
var restarts := 0
var _trace := PackedFloat32Array() ## this lap: time at every TRACE_STEP m
var _best_trace := PackedFloat32Array() ## the best lap's
var _out := false ## on the rolling start's run-up
var _laps_seen := 0
var _lap_seen := 0

## race_: bind to a race (Race does it for s.mode == "time_trial"); null for the bare core (tests: then call
## set_length first).
func _init(race_: Race = null) -> void:
	race = race_
	if race == null:
		return
	L = race.track.L
	var p := race.player
	p.fuel = FUEL
	_load_record()
	_place_start()
	_laps_seen = p.lap_times.size()
	_lap_seen = p.lap

func set_length(L_: float) -> void:
	L = L_

func sector_end(k: int) -> float:
	return L * (k + 1) / SECTORS

# ---------------- core ----------------
## Record the car at distance s along the lap (0..L), lap_t seconds into it.
func advance(s: float, lap_t: float) -> void:
	if s < 0.0:
		return # the standing start's few metres before the line
	while _trace.size() * TRACE_STEP <= s and _trace.size() * TRACE_STEP < L:
		_trace.append(lap_t)
	while sectors_now.size() < SECTORS - 1 and s >= sector_end(sectors_now.size()):
		var done := 0.0
		for x in sectors_now:
			done += x
		sectors_now.append(lap_t - done)

## Close a lap of lap_time (ok: it counts). Returns its entry in laps.
func cross(lap_time: float, ok: bool) -> Dictionary:
	var secs := sectors_now.duplicate()
	if secs.size() == SECTORS - 1:
		var done := 0.0
		for x in secs:
			done += x
		secs.append(lap_time - done)
	while secs.size() < SECTORS:
		secs.append(null)
	var colors := []
	for k in SECTORS:
		colors.append(sector_color(k, secs[k]) if ok and secs[k] != null else "invalid")
	var entry := {"n": laps.size() + 1, "time": lap_time, "sectors": secs, "valid": ok, "colors": colors}
	laps.append(entry)
	if ok:
		for k in SECTORS:
			if secs[k] != null and (best_sectors[k] == null or secs[k] < best_sectors[k]):
				best_sectors[k] = secs[k]
		if best_lap == null or lap_time < best_lap:
			best_lap = lap_time
			best_lap_sectors = secs
			_best_trace = _trace
	_begin_lap()
	return entry

func _begin_lap() -> void:
	_trace = PackedFloat32Array()
	sectors_now = []
	valid = true

## Colour of sector k timed at t: "purple" (the best that sector has been, record included), "green" (faster
## than on the session's best lap), "red" (slower), against the references before this lap closes.
func sector_color(k: int, t) -> String:
	if t == null:
		return "none"
	var ever = best_sectors[k]
	if record_sectors.size() == SECTORS and record_sectors[k] != null:
		ever = record_sectors[k] if ever == null else minf(ever, record_sectors[k])
	if ever == null or t <= ever:
		return "purple"
	if best_lap_sectors.size() == SECTORS and best_lap_sectors[k] != null and t < best_lap_sectors[k]:
		return "green"
	return "red"

## Seconds behind (+) or ahead (−) of the session's best lap at distance s, lap_t into the lap; null with no
## best lap yet.
func delta(s: float, lap_t: float) -> Variant:
	var n := _best_trace.size()
	if n < 2 or s < 0.0:
		return null
	var f := s / TRACE_STEP
	var i := int(f)
	if i >= n - 1:
		return lap_t - float(best_lap) if best_lap != null and s >= L - TRACE_STEP else lap_t - _best_trace[n - 1]
	return lap_t - lerpf(_best_trace[i], _best_trace[i + 1], f - i)

## The lap the best sectors add up to, or null.
func ideal_lap() -> Variant:
	var sum := 0.0
	for x in best_sectors:
		if x == null:
			return null
		sum += x
	return sum

## Sector colours of the lap being driven, so far.
func current_colors() -> Array:
	var out := []
	for k in sectors_now.size():
		out.append(sector_color(k, sectors_now[k]) if valid else "invalid")
	return out

# ---------------- race binding ----------------
## Call after every Race.step (Race does).
func tick() -> void:
	var p := race.player
	if p.lap_times.size() != _laps_seen:
		_laps_seen = p.lap_times.size()
		if _out:
			_out = false # the run-up of a rolling start
			_begin_lap()
		else:
			cross(float(p.last_lap), valid)
	elif p.lap < _lap_seen:
		_invalidate() # backed over the line
	_lap_seen = p.lap
	if race.phase != "racing" or _out:
		return
	if p.mode == "race" and absf(p.d) > race.track.half + OFF:
		_invalidate()
	advance(p.s, race.race_time - p.lap_start)

func _invalidate() -> void:
	valid = false
	race.player.invalid_lap = true # keeps it off best_lap and the lap records too

## Live delta for the HUD: to the session's best lap, else null.
func live_delta() -> Variant:
	if race == null or race.phase != "racing" or _out:
		return null
	var p := race.player
	return delta(p.s, race.race_time - p.lap_start)

## On the run-up of a rolling start.
func out_lap() -> bool:
	return _out

## Back to the start at once: the lap being driven is dropped, the session's laps and bests stay.
func restart() -> void:
	var p := race.player
	restarts += 1
	race.clock = 0.0
	race.green_at = INF
	race.phase = "countdown"
	race.lights_out_at = 0.0 if race.s.rolling_start else RESTART_LIGHTS
	race.cp = {}
	race.winner = null
	p.lap = 0
	p.lap_start = 0.0
	p.cp_idx = -1
	p.finished = false
	p.dnf = false
	p.running = false
	p.invalid_lap = false
	p.mode = "race"
	p.pit = null
	p.pit_request = false
	if p.autopilot:
		race.set_autopilot(false)
	p.control = "free"
	p.fuel = FUEL
	p.tyre.wear = 1.0
	p.damage = 0.0
	p.dmg_pull = 0.0
	_place_start()
	_lap_seen = 0
	_laps_seen = p.lap_times.size()
	_begin_lap()
	race.log_event("Restart", "info")

func _place_start() -> void:
	var p := race.player
	var tr := race.track
	_out = race.s.rolling_start
	p.s = (tr.L - RUNUP) if _out else -9.0
	p.d = tr.sample(tr.RLD, p.s) if _out else 0.0
	var xy := tr.pos(p.s, p.d)
	p.x = xy[0]
	p.y = xy[1]
	p.heading = tr.heading(p.s)
	p.px = p.x
	p.py = p.y
	p.ph = p.heading
	p.ps = p.s
	p.yaw_rate = 0.0
	p.phys = null
	p.rev = false
	p.gear = 0
	p.stuck_t = 0.0
	var v := 0.0
	if _out:
		v = minf(ROLL_SPEED, tr.sample(tr.PROF, p.s) * 0.85)
		p.invalid_lap = true # the run-up to the line is not a lap
		p.gear = 2
		race.lights_out_at = 0.0 # rolling: the clock runs from the first step
	p.v = v
	p.speed = v
	p.vx = cos(p.heading) * v
	p.vy = sin(p.heading) * v

func _load_record() -> void:
	var cond := "wet" if race.weather.wet >= LapRecords.WET_AT else "dry"
	var rec := LapRecords.record(race.s.track, cond)
	var ghost := LapRecords.load_ghost(race.s.track, cond)
	record_sectors = []
	record_time = rec.get("t", null)
	if record_time == null or ghost.is_empty():
		return
	var n := ghost.size() / LapRecords.STRIDE
	var marks := []
	var k := 0
	for i in n:
		if k >= SECTORS - 1:
			break
		if ghost[i * LapRecords.STRIDE + 3] >= sector_end(k):
			marks.append(i * LapRecords.DT)
			k += 1
	if marks.size() != SECTORS - 1:
		return
	record_sectors = [marks[0], marks[1] - marks[0], float(record_time) - marks[1]]
