## Rally mode, after Colin McRae Rally 2.0 (and the event lists of WRC on the 3DS): an event is a run of
## special stages, each driven alone against the clock from a standing start to the stage finish, with the
## co-driver calling the pace notes and a service halt between some of them. The rivals start the same
## stage at intervals out of sight: their times come from their pace (the same lap model qualifying uses,
## anchored to what the co-driver really drives), a little form on the day, and now and then a spin, a
## puncture or an off. Stage times plus penalties add up to the overall classification (RallyEvent).
##
## This file holds the events (EVENTS), the settings a stage runs on (configure_stage), the live tracker of
## the stage being driven (Rally.Stage: clock, split checkpoints, jump start and cut penalties, the finish)
## and the rival model (simulate_rivals, deterministic for a seed). RallyEvent keeps the event's state.
class_name Rally
extends RefCounted

## Road grip of a whole stage's surface against tarmac (Race.grip multiplies by it; tarmac leaves it alone).
const SURFACE_GRIP := {"tarmac": 1.0, "gravel": 0.74}
const SPLITS := 2 ## split checkpoints inside a stage (at a third and two thirds), then the finish
const START_BACK := 4.0 ## m behind the start line the car waits
const JUMP_DIST := 0.6 ## m the car may creep before the start before it is a jump start
const JUMP_PENALTY := 10.0 ## s
const CUT_MARGIN := 2.5 ## m beyond the road edge from where leaving the road can be a cut
const CUT_MIN := 25.0 ## m of road skipped before it counts
const CUT_RATIO := 0.75 ## a cut: the path driven off the road is shorter than this share of the road it skipped
const CUT_PENALTY := 10.0 ## s per cut
const SUPERRALLY := 300.0 ## s: a stage not finished is classified at the slowest finisher's time plus this
const START_LOSS := 1.8 ## s a standing start costs against the flying lap the lap model times
const FUEL_MARGIN := 1.4 ## fuel for this much of the stage, on top of the reserve
const RIVALS := 9 ## drivers entered besides the player (Drivers.ROSTER in grid-filling order)
const SERVICE_LATE := 10.0 ## s of penalty per minute the service crew overruns its allocation (as in CMR 2.0)

# rival incidents, per stage (scaled by the driver's mistake rate where it is a driving error)
const SPIN_RATE := 2.5 ## × mistake rate: a spin or a moment, 2–16 s
const PUNCTURE := {"tarmac": 0.015, "gravel": 0.04}
const RETIRE := {"tarmac": 0.004, "gravel": 0.009} ## × (mistake rate / 0.07): off the road for good

## The events. Each stage: name, track (key), from / to (m after the start line; to 0 = back at the line,
## so 0 → 0 is one full lap; a section of a long road splits it into several stages), surface, weather,
## hour (local time at the start), service (minutes of service before this stage; 0 none).
## Running a road in reverse is not supported (the racing line, pace notes and the world are built one way
## round), so a second pass over the same road is a different section or the full loop in other conditions.
const EVENTS := [
	{"key": "sprint", "name": "Rajd Seicento Sprint", "short": "SPRINT", "difficulty": "easy",
		"blurb": "Three short tarmac tests round Wilamowice, Brzeszcze and Pszczyna: the place to learn the notes.",
		"stages": [
			{"name": "Wilamowice", "track": "wilamowice", "from": 0.0, "to": 0.0, "surface": "tarmac", "weather": "dry", "hour": 10.0, "service": 0},
			{"name": "Brzeszcze Kopalnia", "track": "brzeszcze", "from": 0.0, "to": 0.0, "surface": "tarmac", "weather": "dry", "hour": 11.5, "service": 0},
			{"name": "Pszczyna Zamek", "track": "pszczyna", "from": 0.0, "to": 0.0, "surface": "tarmac", "weather": "dry", "hour": 13.0, "service": 30},
		]},
	{"key": "bor", "name": "Rajd Borów", "short": "BÓR", "difficulty": "medium",
		"blurb": "Loose forest roads round Brzeszcze Bór and the Wilamowice lanes, the last stage at dusk in the wet.",
		"stages": [
			{"name": "Bór I", "track": "bor", "from": 0.0, "to": 0.0, "surface": "gravel", "weather": "fog", "hour": 8.5, "service": 0},
			{"name": "Wilamowice Szuter", "track": "wilamowice", "from": 0.0, "to": 0.0, "surface": "gravel", "weather": "dry", "hour": 10.0, "service": 0},
			{"name": "Staw Bór", "track": "bor", "from": 0.0, "to": 1700.0, "surface": "gravel", "weather": "dry", "hour": 12.0, "service": 45},
			{"name": "Bór II", "track": "bor", "from": 0.0, "to": 0.0, "surface": "gravel", "weather": "wet", "hour": 19.5, "service": 0},
		]},
	{"key": "beskidy", "name": "Rajd Beskidów", "short": "BESKIDY", "difficulty": "medium",
		"blurb": "Mountain tarmac above the Seicento's home town: Szyndzielnia in the morning fog, then the rain.",
		"stages": [
			{"name": "Szyndzielnia I", "track": "bielsko", "from": 0.0, "to": 0.0, "surface": "tarmac", "weather": "fog", "hour": 8.0, "service": 0},
			{"name": "Szyndzielnia Zjazd", "track": "bielsko", "from": 400.0, "to": 2400.0, "surface": "tarmac", "weather": "dry", "hour": 9.5, "service": 0},
			{"name": "Wilamowice Mokre", "track": "wilamowice", "from": 0.0, "to": 0.0, "surface": "tarmac", "weather": "wet", "hour": 11.5, "service": 60},
			{"name": "Szyndzielnia II", "track": "bielsko", "from": 0.0, "to": 0.0, "surface": "tarmac", "weather": "wet", "hour": 15.0, "service": 0},
			{"name": "Pszczyna Park", "track": "pszczyna", "from": 0.0, "to": 0.0, "surface": "tarmac", "weather": "dry", "hour": 17.0, "service": 0},
		]},
	{"key": "zima", "name": "Zimowy Rajd Śląska", "short": "ZIMA", "difficulty": "hard",
		"blurb": "Six stages of Silesian winter: snow on the roads all day, gravel under it in the forest.",
		"stages": [
			{"name": "Pszczyna Zima", "track": "pszczyna", "from": 0.0, "to": 0.0, "surface": "tarmac", "weather": "snow", "hour": 9.0, "service": 0},
			{"name": "Wilamowice Zima", "track": "wilamowice", "from": 0.0, "to": 0.0, "surface": "tarmac", "weather": "snow", "hour": 10.0, "service": 0},
			{"name": "Bór Zima", "track": "bor", "from": 0.0, "to": 0.0, "surface": "gravel", "weather": "snow", "hour": 11.0, "service": 45},
			{"name": "Brzeszcze Zima", "track": "brzeszcze", "from": 0.0, "to": 0.0, "surface": "tarmac", "weather": "snow", "hour": 13.0, "service": 0},
			{"name": "Szyndzielnia Zima", "track": "bielsko", "from": 0.0, "to": 0.0, "surface": "tarmac", "weather": "snow", "hour": 14.5, "service": 30},
			{"name": "Bór Noc", "track": "bor", "from": 0.0, "to": 0.0, "surface": "gravel", "weather": "snow", "hour": 17.5, "service": 0},
		]},
	{"key": "eifel", "name": "Eifel Rallye Nordschleife", "short": "EIFEL", "difficulty": "hard",
		"blurb": "The Nordschleife cut into three long stages, fog in the morning and rain by the afternoon.",
		"stages": [
			{"name": "Hatzenbach – Adenauer Forst", "track": "nordschleife", "from": 0.0, "to": 6900.0, "surface": "tarmac", "weather": "fog", "hour": 8.5, "service": 0},
			{"name": "Metzgesfeld – Brünnchen", "track": "nordschleife", "from": 6900.0, "to": 13800.0, "surface": "tarmac", "weather": "dry", "hour": 11.0, "service": 30},
			{"name": "Pflanzgarten – Döttinger Höhe", "track": "nordschleife", "from": 13800.0, "to": 0.0, "surface": "tarmac", "weather": "wet", "hour": 14.0, "service": 0},
		]},
]

static func event_keys() -> Array:
	return EVENTS.map(func(e: Dictionary) -> String: return e.key)

## The event with this key, or {}.
static func event(key: String) -> Dictionary:
	for e in EVENTS:
		if e.key == key:
			return e
	return {}

## Stage length in metres on a circuit of length L.
static func stage_length(stage_def: Dictionary, L: float) -> float:
	var from: float = stage_def.get("from", 0.0)
	var to: float = stage_def.get("to", 0.0)
	return (to if to > from else to + L) - from

## Turns race settings into one special stage: the player alone, no pit rules, race control for crash damage
## only (no flags, stewards or safety car), no learning AI. The player's own choices on st (name, paint,
## gearbox, aids, set-up) are kept.
static func configure_stage(st: RaceSettings, stage_def: Dictionary, difficulty := "medium") -> void:
	st.mode = "rally"
	st.track = stage_def.track
	st.stage_from = float(stage_def.get("from", 0.0))
	st.stage_to = float(stage_def.get("to", 0.0))
	st.surface = stage_def.get("surface", "tarmac")
	st.weather = stage_def.get("weather", "dry")
	st.start_hour = float(stage_def.get("hour", 12.0))
	st.difficulty = difficulty
	st.format = "laps"
	st.laps = 99 # never reached: Rally.Stage finishes the stage at its finish line
	st.opponents = 0
	st.qualifying = false
	st.quali_grid = {}
	st.mandatory_stop = false
	st.two_compounds = false
	st.refuel = false
	st.race_control = true # crash damage, which the service area then repairs
	st.collisions = true
	st.draft = false
	st.auto_strategist = false
	st.ai_learning = "off"
	st.dynamic_running = false
	st.wear_mult = 1.0
	st.fuel_mult = 1.0
	st.rolling_start = false
	st.starting_tyre = "W" if st.weather in ["wet", "snow", "hail"] else "S"

## Time-of-stage factor of the conditions against a dry tarmac road: grip-limited driving (most of a stage)
## takes about 1/√μ longer.
static func conditions_factor(surface: String, weather: String) -> float:
	var mu: float = SURFACE_GRIP.get(surface, 1.0)
	match weather:
		"snow": mu *= 1.0 - 0.85 * 0.42
		"hail": mu *= 1.0 - 0.9 * 0.36
		"fog": mu *= 0.94
	return 0.3 + 0.7 / sqrt(mu)

## The share of a lap's time spent between from and to (m after the line), and of the stage's time at each
## split, from the lap model's time per sample: {frac, splits: [share of the stage time at each split]}.
static func profile(race: Race, from: float, to: float) -> Dictionary:
	var tr := race.track
	var lap := race.strategy.sim_lap(tr, 1.0, race.car_model.mass_with_fuel(15.0), true, 1.0)
	var dts: PackedFloat64Array = lap.dts
	var n := dts.size()
	var cum := PackedFloat64Array()
	cum.resize(n + 1)
	for i in n:
		cum[i + 1] = cum[i] + dts[i]
	var total := cum[n]
	var at := func(dist: float) -> float: # lap time from the line to dist (dist may run past L)
		var laps := floorf(dist / tr.L)
		var f := (dist - laps * tr.L) / tr.L * n
		var i := clampi(int(f), 0, n - 1)
		return laps * total + cum[i] + dts[i] * (f - i)
	var length := (to if to > from else to + tr.L) - from
	var t0: float = at.call(from)
	var span: float = at.call(from + length) - t0
	var splits := []
	for k in SPLITS:
		splits.append((at.call(from + length * (k + 1) / (SPLITS + 1)) - t0) / maxf(1e-6, span))
	return {"frac": span / maxf(1e-6, total), "splits": splits}

## Clean stage times (no incidents) for drivers of these paces on this race's stage: qualifying's lap model,
## anchored to the co-driver (Qualifying.lap_times), cut to the stage and slowed for the surface and weather.
## The first call on a circuit runs the co-driver's calibration lap (cached for the session).
static func base_times(race: Race, paces: Array) -> Dictionary:
	var prof := profile(race, race.s.stage_from, race.s.stage_to)
	var laps := Qualifying.lap_times(race, paces)
	var k := conditions_factor(race.s.surface, race.s.weather)
	var out := []
	for t in laps:
		out.append(float(t) * prof.frac * k + START_LOSS)
	return {"times": out, "splits": prof.splits}

## The rivals' runs on stage i: deterministic for (seed, i). rivals: [{id, mistakes, ...}]; base: their clean
## stage times; split_frac: share of the stage time at each split (profile().splits). Every rival takes the
## same number of draws whatever happens, so one rival's luck never shifts another's.
## Returns [{id, time (null: retired), splits: [s at each split], dnf, note}].
static func simulate_rivals(rivals: Array, base: Array, split_frac: Array, seed_: int, i: int, surface := "tarmac") -> Array:
	var rng := SimUtil.Rng.new((seed_ * 7919 + i * 104729 + 17) & 0x7fffffff)
	var out := []
	for r in rivals.size():
		var who: Dictionary = rivals[r]
		var clean: float = base[r]
		var form := (rng.next() + rng.next() + rng.next() - 1.5) * 0.008 # about ±0.5 %
		var u_spin := rng.next()
		var u_spin_len := rng.next()
		var u_puncture := rng.next()
		var u_puncture_len := rng.next()
		var u_retire := rng.next()
		var u_where := rng.next()
		var mist: float = who.get("mistakes", 0.07)
		var t := clean * (1.0 + form)
		var lost := 0.0
		var notes := []
		if u_spin < clampf(mist * SPIN_RATE * (1.4 if surface != "tarmac" else 1.0), 0.0, 0.6):
			var spin := 2.0 + u_spin_len * u_spin_len * 14.0
			lost += spin
			notes.append("spin +%.0f s" % spin)
		if u_puncture < PUNCTURE.get(surface, 0.015):
			var p := 25.0 + u_puncture_len * 35.0
			lost += p
			notes.append("puncture +%.0f s" % p)
		var dnf: bool = u_retire < float(RETIRE.get(surface, 0.004)) * mist / 0.07
		# the trouble happens somewhere on the stage: splits after it carry the time lost
		var seg := int(u_where * (SPLITS + 1))
		var splits := []
		for k in SPLITS:
			splits.append(t * float(split_frac[k]) + (lost if k >= seg else 0.0))
		if dnf:
			notes = ["off the road, retired"]
			for k in range(seg, SPLITS):
				splits[k] = null
		out.append({"id": who.id, "time": null if dnf else t + lost, "splits": splits, "dnf": dnf, "note": ", ".join(notes)})
	return out

## The rally field for a difficulty, seeded: Drivers.ROSTER in grid order, with Race.build_field's spread of
## pace round the difficulty's level and a little form for the event. [{id, name, number, color, skill, mistakes, wet}]
static func make_rivals(difficulty: String, seed_: int, count := RIVALS) -> Array:
	var diff: Dictionary = Race.DIFFICULTY.get(difficulty, Race.DIFFICULTY.medium)
	var rng := SimUtil.Rng.new((seed_ * 31 + 5) & 0x7fffffff)
	var out := []
	for i in mini(count, Drivers.ROSTER.size()):
		var who: Dictionary = Drivers.ROSTER[i]
		out.append({"id": i + 1, "name": who.name, "number": who.number, "color": who.color,
			"skill": diff.skill + (who.pace - 0.6) * diff.spread * 0.9 + (rng.next() - 0.5) * diff.spread * 0.3,
			"mistakes": diff.mistakes * who.errors, "wet": who.wet})
	return out

## The stage being driven: placed by Race when s.mode == "rally", ticked after every Race.step.
class Stage:
	var race: Race
	var from := 0.0
	var length := 0.0
	var split_at := PackedFloat64Array() ## m from the stage start of each split, the finish last
	var split_times: Array = [] ## the player's stage time at each split passed (the finish last)
	var penalties: Array = [] ## [[why, seconds]]
	var progress := 0.0 ## m of the stage driven
	var time = null ## stage time at the finish (penalties apart), null until then
	var jumped := false
	var cuts := 0
	## Filled by RallyEvent.begin_stage: who else ran it and how, for the splits against the leader.
	var event = null ## RallyEvent
	var index := -1 ## stage number in the event (0-based)
	var rivals: Array = [] ## Rally.simulate_rivals rows
	var names := {} ## rival id -> name
	var _s0 := 0.0 ## where the car waits at the start
	var _off := false
	var _off_prog := 0.0
	var _off_path := 0.0

	func _init(race_: Race) -> void:
		race = race_
		var tr := race.track
		from = race.s.stage_from
		length = (race.s.stage_to if race.s.stage_to > from else race.s.stage_to + tr.L) - from
		for k in SPLITS:
			split_at.append(length * (k + 1) / (SPLITS + 1))
		split_at.append(length)
		# alone at the start line, in the middle of the road
		var p := race.player
		p.s = from - START_BACK
		p.d = 0.0
		var xy := tr.pos(p.s, p.d)
		p.x = xy[0]
		p.y = xy[1]
		p.heading = tr.heading(p.s)
		p.px = p.x
		p.py = p.y
		p.ph = p.heading
		p.ps = p.s
		_s0 = p.s
		p.fuel = minf(race.spec.tank, race.fpl * length / tr.L * FUEL_MARGIN + Strategy.RESERVE)
		progress = -START_BACK

	## The clock: stage time so far (0 before the start), or the finish time.
	func elapsed() -> float:
		if time != null:
			return time
		return maxf(0.0, race.race_time) if race.phase == "racing" else 0.0

	func penalty() -> float:
		var sum := 0.0
		for pe in penalties:
			sum += pe[1]
		return sum

	func add_penalty(why: String, secs: float) -> void:
		penalties.append([why, secs])
		race.player.penalties.append([why, secs])
		race.log_event("%s: +%d s penalty" % [why, roundi(secs)], "bad")

	## The fastest rival time at split k (the finish is k = SPLITS), or {} if nobody got there.
	func leader_at(k: int) -> Dictionary:
		var best := {}
		for r in rivals:
			var t = r.time if k >= SPLITS else r.splits[k]
			if t != null and (best.is_empty() or t < best.t):
				best = {"t": t, "id": r.id, "name": names.get(r.id, "")}
		return best

	## Where a time t at split k would rank among the rivals (1 = fastest).
	func rank_at(k: int, t: float) -> int:
		var pos := 1
		for r in rivals:
			var rt = r.time if k >= SPLITS else r.splits[k]
			if rt != null and rt < t:
				pos += 1
		return pos

	## The split the player passed last: {k, t, gap to the leader there (null without rivals), pos}, or {}.
	func last_split() -> Dictionary:
		if split_times.is_empty():
			return {}
		var k := split_times.size() - 1
		var t: float = split_times[k] + (penalty() if k == SPLITS else 0.0)
		var lead := leader_at(k)
		return {"k": k, "t": t, "gap": t - float(lead.t) if not lead.is_empty() else null, "pos": rank_at(k, t), "leader": lead.get("name", "")}

	func tick(_dt: float, _input) -> void:
		var p := race.player
		var tr := race.track
		if race.phase == "countdown":
			if not jumped and race.track.rel(p.s - _s0) > JUMP_DIST:
				jumped = true
				add_penalty("Jump start", JUMP_PENALTY)
			return
		if race.phase != "racing" or p.finished or p.dnf:
			return
		var prog := p.lap * tr.L + p.s - from
		# splits and the finish, timed where the car crossed them
		while split_times.size() < split_at.size() and prog >= split_at[split_times.size()]:
			var k := split_times.size()
			var v := maxf(1.0, absf(p.speed) if p.control == "free" else p.v)
			split_times.append(maxf(0.0, race.race_time - (prog - split_at[k]) / v))
		# cutting: off the road, and the car came back further along than the path it drove could take it
		var off := absf(p.d) > tr.half + CUT_MARGIN
		if off and not _off:
			_off = true
			_off_prog = progress
			_off_path = 0.0
		if _off:
			_off_path += Vector2(p.x - p.px, p.y - p.py).length()
			if not off:
				_off = false
				var skipped := prog - _off_prog
				if skipped > CUT_MIN and _off_path < skipped * CUT_RATIO:
					cuts += 1
					add_penalty("Cut (%d m)" % roundi(skipped), CUT_PENALTY)
		progress = prog
		if split_times.size() == split_at.size():
			time = split_times[-1]
			if not race.winner:
				race.winner = p
			race.finish(p)
			p.finish_time = time
			race.log_event("Stage finish: %s%s" % [Race.fmt_time(time), (" + %d s penalty" % roundi(penalty())) if penalty() > 0.0 else ""], "good")
