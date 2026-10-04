## Race simulation: field, AI drivers, player physics, pit stops, weather, timing and collisions
## (port of js/race.js). Step it at a fixed 120 Hz with step(dt, input).
class_name Race
extends RefCounted

const G := 9.81

const BOTS := [
	["Giancarlo Bianchi", "#1d4fa3"], ["Marek Kowalski", "#f2c318"], ["Luca Ferraro", "#f4f4f4"],
	["Zbigniew Nowak", "#2e8b57"], ["Paolo Esposito", "#ff7f11"], ["Krzysztof Wiśniewski", "#7b2cbf"],
	["Matteo Romano", "#00a6d6"], ["Tomasz Wójcik", "#c9184a"], ["Hans Becker", "#404040"],
	["Jan Kamiński", "#9bd13b"], ["Sofia Greco", "#ff66b3"], ["Agnieszka Lewandowska", "#8d6e63"],
	["Klaus Schmidt", "#1b998b"], ["Andrzej Zieliński", "#b5838d"], ["Francesca Ricci", "#6a994e"],
]

## band: how hard the field is pulled back towards the player when a gap opens (rubber-band pace, ±).
## A single mistake shouldn't hand the win to someone three seconds a lap off your pace, so the bots
## give a little of that back the way real opposition would — pushing harder when they're behind,
## backing off a fraction when they've broken clear. It fades out on Hard and is off on Alien.
const DIFFICULTY := {
	"easy": {"skill": 0.93, "spread": 0.035, "mistakes": 0.12, "band": 0.05},
	"medium": {"skill": 0.955, "spread": 0.028, "mistakes": 0.07, "band": 0.035},
	"hard": {"skill": 0.975, "spread": 0.02, "mistakes": 0.04, "band": 0.015},
	"alien": {"skill": 0.995, "spread": 0.01, "mistakes": 0.02, "band": 0.0},
}
## Share of the racing line's limit speed the full-assist brake lets the player carry into a corner.
const ASSIST_PACE := 0.97
const TOW_MAX := 0.35 ## drag lost in a full slipstream, right behind a car at speed
const RAIL_LOAD_NORM := 0.66 ## mean of 0.45 + 1.1u² over a lap, so a bot's average wear stays at the nominal figure

## Player controls for one tick.
class PlayerInput:
	var throttle := 0.0
	var brake := 0.0
	var steer := 0.0
	var shift_up := false
	var shift_down := false

# ---------------- weather ----------------
class Weather:
	var mode := "dry"
	var rain := 0.0
	var wet := 0.0
	var showers: Array = [] ## [{start, end, intensity}]

	func _init(mode_: String, duration: float, rng: SimUtil.Rng) -> void:
		mode = mode_
		if mode == "wet":
			rain = 0.7
			wet = 0.85
		if mode == "variable":
			if duration < 5400.0:
				var start := duration * (0.22 + 0.3 * rng.next())
				showers.append({"start": start, "end": start + duration * (0.22 + 0.25 * rng.next()), "intensity": 0.6 + 0.4 * rng.next()})
			else:
				# endurance races: a shower every few hours, each 20–80 minutes long
				var t := 1800.0 + rng.next() * 5400.0
				while t < duration - 1200.0:
					var len := 1200.0 + rng.next() * 3600.0
					showers.append({"start": t, "end": minf(duration, t + len), "intensity": 0.45 + 0.55 * rng.next()})
					t += len + 3600.0 * (2.0 + rng.next() * 4.0)

	func update(dt: float, t: float) -> void:
		if mode == "variable":
			var r := 0.0
			for sh in showers:
				r = maxf(r, sh.intensity * SimUtil.smooth01((t - sh.start) / 60.0) * SimUtil.smooth01((sh.end - t) / 60.0))
			rain = r
		if mode == "dry":
			return
		var target := minf(1.0, rain * 1.2)
		if rain > 0.05 and target > wet:
			wet = minf(target, wet + rain * dt / 140.0)
		else:
			wet = maxf(0.0, wet - dt / 420.0)

	func forecast(t: float) -> String:
		if mode == "dry":
			return "Dry all race"
		if mode == "wet":
			return "Rain all race"
		var sh = null
		for x in showers:
			if t < x.end:
				sh = x
				break
		var mins := func(x: float) -> String:
			var m := maxi(1, SimUtil.js_round(x / 60.0))
			return "~%d min" % m if m < 90 else "~%.1f h" % (m / 60.0)
		if sh == null:
			return "Rain has passed — dry to the flag" if showers.size() else "Dry all race"
		if t < sh.start - 20.0:
			return "Rain expected in %s" % mins.call(sh.start - t)
		return "Raining — easing in %s" % mins.call(sh.end - t)

# ---------------- models ----------------
var car_model: CarModel
var tyres: Tyres
var strategy: Strategy
var phys: Physics
var spec: CarSpec

# ---------------- state ----------------
var s: RaceSettings
var track: Track
var cal: Dictionary
var fpl := 0.0
var timed := false
var duration := 0.0
var R := 0 ## race distance in laps (a running estimate for timed races)
var start_hour := 14.0
var rng: SimUtil.Rng
var rules := {}
var clock := 0.0
var green_at := INF
var lights_out_at := 0.0
var phase := "countdown" ## countdown | racing | finished
var events: Array = [] ## [{id, t, text, kind}]
var event_seq := 0
var cp := {} ## checkpoint index -> race time the leader passed it
var cp_step := 25.0
var finish_count := 0
var winner: RaceCar = null
var projected := false ## the finish was projected from the field's pace rather than raced (approximate_finish)
var fastest = null ## {t, car}
var penalty_time := 0.0
var weather: Weather
var plan_wet_start := 0.0
var cars: Array[RaceCar] = []
var order: Array[RaceCar] = []
var _order_idx := {} ## car -> its fixed index in `cars`, used to break order_key ties
var _order_key_cache := {} ## car -> order_key, recomputed once per tick and reused during the sort
var _collide_live: Array[RaceCar] = [] ## scratch for collide(), reused every tick
var player: RaceCar
var phys_bots := true
var quali_bots: Array[RaceCar] = [] ## qualifying session: the field that "ran" elsewhere, kept off the circuit
var quali_times := {} ## bot id -> qualifying lap time
var quali_fuel := 0.0 ## litres in the tank for a qualifying run
var phys_near_only := false ## battery saver: bots far from the player stay on the rail model
var bot_smooth_line := true ## physics bots ease mistakes in (and slew their lateral target, see line_slew); false steers at the raw target, as the JS reference does
## m/s a bot may move its lateral target across the track; 0 leaves it unslewed. Off: at 6 or 12 m/s it cost more
## contacts and cautions than it saved (Monaco's damage doubled over 12 seeds), even with dodges exempt
var line_slew := 0.0
var line_slew_per_m := 0.25 ## and at most this far across per metre it travels
const ERR_RAMP := 0.8 ## s a driving error takes to build up to its full sideways offset
var bot_uturn := true ## a spun bot drives itself round; false lifts it back onto the line within 1.2 s, as the JS reference does (tests/test_race.gd)
var warp := 1
var brain: Brain = null
var limiter := false ## the player has the flag speed limiter switched on (V)
var rc: RaceControl = null ## flags, safety car, stewards and damage (null: contact is just physics, as before)
var last_contact := 0.0

var _env := Physics.Env.new()
var _ctl := Physics.Controls.new()
var _uturn_ctl := Physics.Controls.new()
var _surf_car: RaceCar
var _surface_fn: Callable

## Tracks are built (and calibrated) once per session.
static var _track_cache := {}

static func get_track(key: String) -> Track:
	if not _track_cache.has(key):
		_track_cache[key] = Track.new(Track.load_def(key))
	return _track_cache[key]

## models: {car_model, tyres, strategy} to share them between races (optional).
## seed_: PRNG seed; -1 picks a random one.
func _init(settings: RaceSettings, player_plan = null, seed_ := -1, models := {}) -> void:
	car_model = models.get("car_model", CarModel.new())
	tyres = models.get("tyres", Tyres.new())
	strategy = models.get("strategy", Strategy.new(car_model, tyres))
	spec = car_model.spec
	phys = Physics.new(car_model)
	_surface_fn = func(x: float, y: float) -> int: return surface_at(_surf_car, x, y)
	s = settings
	track = get_track(settings.track)
	cal = strategy.calibrate(track)
	fpl = cal.fuel_per_lap * settings.fuel_mult
	# timed races (up to 24 h) finish when the leader crosses the line after the clock runs out;
	# R is then a running estimate of the leader's total laps
	timed = settings.format == "time"
	duration = settings.hours * 3600.0 if timed else 0.0
	R = strategy.estimate_laps(track, duration, _est_settings()) if timed else settings.laps
	if settings.qualifying:
		R = 1 + Qualifying.timed_laps(cal.T0) # an out lap, then the timed laps
	start_hour = settings.start_hour
	rng = SimUtil.Rng.new(seed_ if seed_ >= 0 else randi() & 0x7fffffff)
	rules = {"mandatory_stop": settings.mandatory_stop, "two_compounds": settings.two_compounds, "refuel": settings.refuel}
	lights_out_at = 6.0 + rng.next() * 2.0
	if settings.qualifying:
		lights_out_at = 2.0 # no start lights: the session opens when the pit lane does
	penalty_time = SimUtil.js_round(cal.pit_drive_loss + 15.0)
	weather = Weather.new(settings.weather, duration if timed else R * cal.T0 * 1.08, rng)
	plan_wet_start = weather.wet
	# bots drive the same four-wheel physics as the player; the UI sets warp, and anything faster than
	# real time (or the menu demo) runs them on the cheaper rail model
	phys_bots = not settings.demo and settings.bot_physics != "off"
	phys_near_only = settings.bot_physics == "near"
	# learning AI (off: every bot drives one fixed pace everywhere, as before)
	brain = Brain.new(self, not settings.demo) if settings.ai_learning != "off" and not settings.qualifying else null
	build_field(player_plan)
	rc = RaceControl.new(self) if settings.race_control and not settings.demo and not settings.qualifying else null
	order = cars.duplicate()
	for i in cars.size():
		_order_idx[cars[i]] = i

func _est_settings() -> Dictionary:
	return {"fuel_mult": s.fuel_mult, "weather": s.weather, "wear_mult": s.wear_mult, "crew": s.crew,
		"parallel": s.parallel, "refuel": s.refuel}

var race_time: float:
	get: return clock - green_at

## Local time of day in hours (0–24): the clock starts at start_hour and runs in real time.
var time_of_day: float:
	get: return fposmod(start_hour + maxf(0.0, race_time) / 3600.0, 24.0)

## Seconds left in a timed race (-1 for a race over laps).
var time_left: float:
	get: return maxf(0.0, duration - maxf(0.0, race_time)) if timed else -1.0

func log_event(text: String, kind := "info") -> void:
	event_seq += 1
	events.append({"id": event_seq, "t": clock, "text": text, "kind": kind})
	if events.size() > 60:
		events.pop_front()

func plan_opts(extra := {}) -> Dictionary:
	var o := {
		"track": track, "laps": R, "wet": weather.wet, "wear_mult": s.wear_mult, "fuel_mult": s.fuel_mult,
		"rules": rules, "crew": s.crew, "parallel": s.parallel,
	}
	o.merge(extra, true)
	return o

## Tyre for a qualifying run: the softest slick, or the wets when the track is soaked.
func quali_compound() -> String:
	return "W" if weather.wet > 0.4 else "S"

func make_car(id: int, name: String, color: Color, number: int, is_player: bool) -> RaceCar:
	var c := RaceCar.new()
	c.id = id
	c.name = name
	c.color = color
	c.number = number
	c.is_player = is_player
	c.control = "free" if is_player else "rail"
	c.plan_wet = weather.wet
	c.rpm = spec.idle_rpm
	return c

func apply_plan(car: RaceCar, p: Dictionary) -> void:
	car.plan = []
	for st in p.stints:
		car.plan.append({"c": st.c, "laps": st.laps})
	car.stint_idx = 0
	var c0: String = p.stints[0].c
	car.tyre = {"c": c0, "wear": 1.0, "temp": 0.6}
	if s.dynamic_running:
		car.tyre.q = _tyre_quality()
	car.used_mask = Tyres.compound_bit(c0)
	car.history = [c0]
	var f: float = p.stints[0].get("fuel", 0.0)
	car.fuel = minf(spec.tank, f if f else Strategy.fuel_need(R, fpl))

## Wear multiplier of one set of tyres: no two sets last exactly as long.
func _tyre_quality() -> float:
	return 0.92 + 0.16 * rng.next()

func build_field(player_plan) -> void:
	var diff: Dictionary = DIFFICULTY[s.difficulty]
	var options := strategy.plan(plan_opts({"diverse": true}))
	var fallback := {"stops": 0, "stints": [{"c": "W" if weather.wet > 0.4 else "M", "laps": R, "fuel": minf(spec.tank, Strategy.fuel_need(R, fpl))}]}
	var bots: Array[RaceCar] = []
	var numbers := [3, 5, 8, 11, 14, 17, 21, 23, 27, 33, 44, 55, 63, 77, 88]
	for i in s.opponents:
		var car := make_car(i + 1, BOTS[i][0], Color(BOTS[i][1]), numbers[i], false)
		car.skill = diff.skill + (rng.next() - 0.6) * diff.spread
		if s.quali_grid.has("skills") and s.quali_grid.skills.has(str(car.id)):
			car.skill = float(s.quali_grid.skills[str(car.id)]) # the field races as it qualified
		car.stripes = rng.next() < 0.3
		car.agg = 0.9 + rng.next() * 0.2
		car.mistake_rate = diff.mistakes
		if s.dynamic_running and rng.next() < 0.3:
			car.pit_bias = 1
		if brain:
			brain.add_bot(car, diff.spread)
		car.wet_threshold = 0.36 + rng.next() * 0.14
		var pick: Dictionary = options[0] if options.size() else fallback
		if options.size() > 1:
			var pool := options.filter(func(o): return o.time < options[0].time * 1.012)
			if rng.next() < 0.2:
				pick = options[int(floorf(rng.next() * mini(4, options.size())))]
			else:
				pick = pool[int(floorf(pow(rng.next(), 1.5) * pool.size()))]
		apply_plan(car, pick)
		car.strategy_label = Strategy.label(pick)
		car.quali = car.skill + (rng.next() - 0.5) * 0.02
		if s.quali_grid.has("quali") and s.quali_grid.quali.has(str(car.id)):
			car.quali = float(s.quali_grid.quali[str(car.id)])
		bots.append(car)
	_stable_sort(bots, func(a: RaceCar, b: RaceCar) -> bool: return b.quali < a.quali)

	var pl := make_car(0, s.player_name, s.player_color, s.player_number, true)
	pl.stripes = s.stripes
	pl.skill = 0.97 # used only while on autopilot
	var pp: Dictionary = player_plan if player_plan else (options[0] if options.size() else fallback)
	if s.qualifying:
		quali_fuel = minf(spec.tank, Strategy.fuel_need(R, fpl))
		pp = {"stops": 0, "stints": [{"c": quali_compound(), "laps": R, "fuel": quali_fuel}]}
	elif not player_plan and not pp.get("stints", []).is_empty():
		pp = pp.duplicate(true)
		pp.stints[0].c = s.starting_tyre
	apply_plan(pl, pp)
	pl.strategy_label = Strategy.label(pp)
	player = pl

	var field: Array[RaceCar] = bots.duplicate()
	if s.qualifying:
		# the player runs alone; the rest of the field only sets times on the sheet
		quali_bots = bots
		field = [pl]
	elif s.quali_grid.has("order"):
		field = _qualified_field(bots, pl)
	else:
		var slot: int
		var n := bots.size() + 1
		if s.grid == "pole":
			slot = 0
		elif s.grid == "back":
			slot = n - 1
		elif s.grid == "middle":
			slot = n / 2
		else:
			slot = int(floorf(rng.next() * n))
		field.insert(slot, pl)

	var tr := track
	for k in field.size():
		var car := field[k]
		car.grid = k + 1
		car.box = k
		car.s = -(9.0 + k * 6.5)
		car.d = (-1.0 if k % 2 == 0 else 1.0) * tr.half * 0.36
		var p := tr.pos(car.s, car.d)
		car.x = p[0]
		car.y = p[1]
		car.heading = tr.heading(car.s)
		car.reaction = 0.18 + rng.next() * 0.35 + (1.0 - car.skill) * 2.0
		car.pace = 1.0
		cars.append(car)
	if s.qualifying:
		var times := Qualifying.lap_times(self, bots.map(func(b: RaceCar) -> float: return b.quali))
		for i in bots.size():
			quali_times[bots[i].id] = times[i]
		log_event("Qualifying — out lap, then %d timed lap%s" % [R - 1, "s" if R > 2 else ""], "info")
	else:
		log_event("Grid set — you start P%d of %d" % [pl.grid, field.size()])

## The grid a championship round's qualifying produced: order is car ids, fastest first. A car missing
## from it (the player when no time was set) starts behind the rest.
func _qualified_field(bots: Array[RaceCar], pl: RaceCar) -> Array[RaceCar]:
	var by_id := {pl.id: pl}
	for b in bots:
		by_id[b.id] = b
	var field: Array[RaceCar] = []
	for id in s.quali_grid.order:
		var car: RaceCar = by_id.get(int(id))
		if car and not field.has(car):
			field.append(car)
	for b in bots:
		if not field.has(b):
			field.append(b)
	if not field.has(pl):
		field.append(pl)
	return field

## Array.sort that keeps equal elements in order (JS sort is stable, sort_custom isn't).
static func _stable_sort(arr: Array, before: Callable) -> void:
	var idx := {}
	for i in arr.size():
		idx[arr[i]] = i
	arr.sort_custom(func(a, b): return before.call(a, b) or (not before.call(b, a) and idx[a] < idx[b]))

# ---------------- main step ----------------
func step(dt: float, input: PlayerInput) -> void:
	clock += dt
	if phase == "countdown" and clock >= lights_out_at:
		phase = "racing"
		green_at = clock
		log_event("Lights out — go go go!", "good")
	if phase == "racing":
		var before := weather.rain
		weather.update(dt, race_time)
		if before <= 0.05 and weather.rain > 0.05:
			log_event("Rain is falling!", "warn")
		if before > 0.05 and weather.rain <= 0.05:
			log_event("Rain has stopped — the track will dry", "info")

	for car in cars:
		car.px = car.x
		car.py = car.y
		car.ph = car.heading
		car.ps = car.s
		car.has_prev = true
		if car.dnf:
			continue
		var prev_p := track.rel(car.s)
		if not car.is_player:
			bot_control(car, dt)
		if car.control == "free":
			if car.is_player:
				if s.auto_rejoin:
					player_rejoin(car, dt)
				var ab := brake_assist(car) if s.brake_assist and s.assists == "full" else 0.0
				step_free(car, dt, input.throttle * (1.0 - ab), maxf(input.brake, ab), input.steer, input)
			else:
				var c := bot_input(car, dt)
				step_free(car, dt, c.throttle, c.brake, c.steer, null)
		else:
			step_rail(car, dt)
		after_move(car, prev_p)
	if s.collisions:
		collide()
	update_order()
	if rc:
		rc.step(dt)
	if brain:
		brain.observe()
	rubber_band(dt)

	if winner and phase == "racing":
		var waiting := cars.filter(func(c): return not c.finished and not c.dnf)
		var cap := maxf(240.0, cal.T0 * 1.6)
		if not waiting.size() or race_time - winner.finish_time > cap:
			for c in waiting:
				finish(c, true)
			phase = "finished"
			if brain:
				brain.commit(true)

## Share of the race still to run: 1 at the start, 0 once the chequered flag is out.
func remaining_fraction() -> float:
	if winner or phase == "finished":
		return 0.0
	if phase != "racing":
		return 1.0
	if timed:
		return time_left / duration if duration > 0.0 else 0.0
	var lead := 0.0
	for c in cars:
		if not c.dnf:
			lead = maxf(lead, c.lap * track.L + c.s)
	return clampf(1.0 - lead / (R * track.L), 0.0, 1.0) if R > 0 else 0.0

## Ends the race at once by projecting every running car to the flag from its recent pace and
## its remaining planned stops, instead of simulating the laps (used once the player is out).
func approximate_finish() -> void:
	if phase == "finished":
		return
	projected = true
	var runs := {} # car -> {t0, lt, p0, stops: [[lap, cost, compound]]}
	var paces := []
	for c in cars:
		if not c.dnf and not c.finished:
			runs[c] = _projection(c)
			if runs[c].n:
				paces.append(runs[c].lt)
	# a few laps say little about a car's real pace: pull thin samples towards the field's
	paces.sort()
	var field: float = paces[paces.size() >> 1] if paces.size() else cal.T0 * 1.05
	for c in runs:
		var r: Dictionary = runs[c]
		r.lt = field + (r.lt - field) * r.n / (r.n + 3.0)
	if not runs.is_empty() and not winner:
		# the winner: first to complete R laps, or in a timed race the leader's first crossing after time
		var best_t := INF
		var best_n := -1
		for c in runs:
			var n: int = R if not timed else c.lap + 1
			if timed:
				while _projected_time(runs[c], n) < duration:
					n += 1
			var t := _projected_time(runs[c], maxi(n, c.lap + 1))
			if (timed and (n > best_n or (n == best_n and t < best_t))) or (not timed and t < best_t):
				best_t = t
				best_n = n
				winner = c
		winner.lap = best_n
	var tw: float = winner.finish_time if winner and winner.finish_time != null else race_time
	if winner and runs.has(winner):
		tw = _projected_time(runs[winner], winner.lap)
		if timed:
			R = winner.lap
	var cap := maxf(240.0, cal.T0 * 1.6)
	var arrivals := []
	for c in runs:
		var n: int = c.lap if c == winner else c.lap + 1
		while _projected_time(runs[c], n) < tw:
			n += 1
		var t := _projected_time(runs[c], n)
		var running := t - tw > cap
		if running:
			t = tw + cap
			n -= 1 # still out on track when the marshals call it
		arrivals.append({"car": c, "lap": n, "t": t, "running": running})
	arrivals.sort_custom(func(a, b): return a.t < b.t)
	for a in arrivals:
		var c: RaceCar = a.car
		for st in runs[c].stops:
			if st[0] < a.lap:
				c.stops += 1
				c.used_mask |= Tyres.compound_bit(st[2])
				c.history.append(st[2])
		if a.running:
			var r: Dictionary = runs[c]
			var p: float = r.p0 + (a.t - r.t0 - _stop_time(r, a.lap)) / r.lt * track.L
			c.lap = maxi(c.lap, floori(p / track.L))
			c.s = clampf(p - c.lap * track.L, 0.0, track.L - 0.01)
		else:
			c.lap = a.lap
			c.s = 0.0
		c.mode = "race"
		c.pit = null
		clock = green_at + a.t
		finish(c, a.running)
	update_order()
	phase = "finished"
	if brain:
		brain.commit(true)

## A running car's recent pace and the stops its plan still has in it.
func _projection(c: RaceCar) -> Dictionary:
	# the median of the last few laps (never the standing start) ignores pit and safety-car laps
	var recent: Array = c.lap_times.slice(maxi(1, c.lap_times.size() - 5))
	recent.sort()
	var lt: float = recent[recent.size() >> 1] if recent.size() else 0.0
	var stops := []
	var start := c.stint_start_lap
	var idx := c.stint_idx
	if c.mode == "pit" and c.pit and (c.pit.phase == "in" or c.pit.phase == "service"):
		# a stop already under way costs what is left of it
		var cost: float = c.pit.left if c.pit.phase == "service" else cal.pit_drive_loss + (c.service.time if c.service else 0.0)
		var nxt: Dictionary = c.service if c.service else {"c": c.tyre.c}
		stops.append([c.lap, cost, nxt.c if nxt.c else c.tyre.c])
		idx += 1
		start = c.lap
	while idx + 1 < c.plan.size():
		start = maxi(start + int(c.plan[idx].laps), c.lap + 1)
		var nxt: Dictionary = c.plan[idx + 1]
		var litres := minf(spec.tank, Strategy.fuel_need(int(nxt.laps), car_fpl(c))) if rules.refuel else 0.0
		var cost: float = cal.pit_drive_loss + Strategy.service_time(s.crew, s.parallel, true, litres)
		if stops.is_empty() and rc:
			cost += rc.repair_time(c)
		stops.append([start, cost, nxt.c])
		idx += 1
	return {"t0": race_time, "lt": lt, "n": recent.size(), "p0": c.lap * track.L + c.s, "stops": stops}

## Race time at which a projected car crosses the line to complete lap n.
func _projected_time(r: Dictionary, n: int) -> float:
	return r.t0 + (n * track.L - r.p0) / track.L * r.lt + _stop_time(r, n)

func _stop_time(r: Dictionary, n: int) -> float:
	var t := 0.0
	for st in r.stops:
		if st[0] < n:
			t += st[1]
	return t

func move_s(car: RaceCar, ds: float) -> void:
	var L := track.L
	car.s += ds
	if car.s >= L:
		car.s -= L
		car.lap += 1
		on_line(car)
	elif car.s < 0.0 and car.lap > 0:
		car.s += L
		car.lap -= 1
		car.invalid_lap = true

func on_line(car: RaceCar) -> void:
	if phase == "countdown":
		return
	var rt := race_time
	var lt := rt - car.lap_start
	car.lap_start = rt
	car.last_lap = lt
	car.lap_times.append(lt)
	if not car.invalid_lap and not (s.qualifying and car.lap <= 1): # the out lap is only a warm-up
		if car.best_lap == null or lt < car.best_lap:
			car.best_lap = lt
		if not fastest or lt < fastest.t:
			fastest = {"t": lt, "car": car}
			if car.lap > 1:
				log_event("Fastest lap: %s %s" % [car.name, fmt_time(lt)], "purple")
	car.invalid_lap = false
	car.pace = 1.0 + (rng.next() - 0.5) * 0.008
	car.mistake_p = rng.next() * track.L if rng.next() < car.mistake_rate else null
	if brain:
		brain.lap(car)
	if rc:
		rc.on_line(car)
	if car.finished:
		return
	if timed and not winner and car == order[0]:
		# re-estimate the race distance from the leader's recent pace
		var recent := car.lap_times.slice(-3)
		var avg := 0.0
		for x in recent:
			avg += x
		avg /= recent.size()
		var left := duration - rt
		R = car.lap if left <= 0.0 else car.lap + maxi(1, ceili(left / avg))
		if left <= 0.0:
			log_event("🏁 Time is up — the leader takes the chequered flag", "good")
	var done := (car == order[0] and rt >= duration) if timed else car.lap >= R
	if rc and rc.flag == "red":
		done = false # nobody takes the flag in the pit lane: the race resumes first
	if not winner and done:
		winner = car
		finish(car)
	elif winner:
		finish(car)

func finish(car: RaceCar, still_running := false) -> void:
	car.finished = true
	car.finish_lap = car.lap
	finish_count += 1
	car.finish_order = finish_count
	car.finish_time = null if still_running else race_time
	car.running = still_running
	if rules.mandatory_stop and car.stops == 0:
		car.penalties.append(["No mandatory pit stop", penalty_time])
	if rules.two_compounds and not (car.used_mask & Tyres.compound_bit("W")):
		var dry := 0
		for c in ["S", "M", "H"]:
			if car.used_mask & Tyres.compound_bit(c):
				dry += 1
		if dry < 2:
			car.penalties.append(["Used only one tyre compound", penalty_time])
	car.penalty = 0.0
	for p in car.penalties:
		car.penalty += p[1]
	if not still_running:
		if car == winner:
			log_event("🏁 You win the race!" if car.is_player else "🏁 %s wins the race!" % car.name, "good")
		if car.is_player:
			log_event("🏁 You finished P%d" % car.pos, "good")
	# the cool-down lap is driven on rails
	if car.control == "free":
		to_rail(car)
		car.v = maxf(car.v, sqrt(car.vx * car.vx + car.vy * car.vy))

func after_move(car: RaceCar, prev_p: float) -> void:
	var tr := track
	var cfg := tr.cfg
	var p := tr.rel(car.s)
	# "crossed x this tick": prev_p < x and p >= x and p - prev_p < 60 (inlined, runs per car per tick)
	if phase == "racing" and car.mode == "race" and not car.finished:
		var x := cfg.pit_entry - 280.0
		if prev_p < x and p >= x and p - prev_p < 60.0:
			decide(car)
		x = cfg.pit_entry
		if (car.pit_request or (rc and rc.flag == "red")) and prev_p < x and p >= x and p - prev_p < 60.0:
			enter_pit(car)
	if car.mode == "pit" and car.pit.phase == "out" and p >= cfg.pit_exit and p - cfg.pit_exit < 60.0:
		exit_pit(car)
	if s.qualifying and car.lap >= 1 and car.mode == "race" and absf(car.d) > tr.half + 1.0:
		car.invalid_lap = true # a timed lap with the car off the tarmac does not count (the out lap is free; the line clears the flag)
	if car.mistake_p != null and absf(tr.wrap_s(car.s) - car.mistake_p) < 3.0:
		car.mistake_p = null
		bot_mistake(car, 1.3)
	if phase == "racing":
		var prog := car.lap * tr.L + car.s
		var k := int(floorf(prog / cp_step))
		if k > car.cp_idx and k >= 0:
			car.cp_idx = k
			if not cp.has(k):
				cp[k] = race_time
			car.gap = race_time - cp[k]
	if car.fuel <= 0.0 and not car.out_of_fuel and not car.finished:
		car.out_of_fuel = true
		log_event("%s has run out of fuel!" % car.name, "bad")
	if car.out_of_fuel and car.v < 0.2 and sqrt(car.vx * car.vx + car.vy * car.vy) < 0.2 and car.mode != "pit" and not car.finished:
		car.dnf = true
		car.dnf_reason = "Out of fuel"
		log_event("%s retires — out of fuel" % car.name, "bad")

# ---------------- strategy decisions ----------------
## Litres a lap costs this car: what it has really burned lately, else the calibrated figure.
func car_fpl(car: RaceCar) -> float:
	return car.fuel_lap if s.dynamic_running and car.fuel_lap > 0.0 else fpl

## Nominal tread fraction a lap costs these tyres at this car's aggression.
func nominal_lap_wear(car: RaceCar, c: String) -> float:
	return track.L * tyres.wear_per_metre(c, weather.wet, s.wear_mult) * car.agg

## Measure what the last lap really cost in tread and fuel. Rises are believed quickly and falls slowly,
## so a few slow laps behind a safety car don't leave a car short of fuel or tyres.
func _observe_rates(car: RaceCar) -> void:
	var m = car.rate_mark
	if m != null and m.stops == car.stops and m.lap == car.lap - 1:
		var dw: float = m.wear - car.tyre.wear
		var df: float = m.fuel - car.fuel
		if dw > 0.0:
			car.obs_wear = dw if car.obs_wear <= 0.0 else lerpf(car.obs_wear, dw, 0.6 if dw > car.obs_wear else 0.3)
		if df > 0.0:
			var f := clampf(df, fpl * 0.7, fpl * 1.6)
			car.fuel_lap = f if car.fuel_lap <= 0.0 else lerpf(car.fuel_lap, f, 0.6 if f > car.fuel_lap else 0.3)
	car.rate_mark = {"lap": car.lap, "stops": car.stops, "wear": car.tyre.wear, "fuel": car.fuel}

func decide(car: RaceCar) -> void:
	if s.qualifying:
		return # nobody pits in a qualifying run
	var dyn := s.dynamic_running
	if dyn:
		_observe_rates(car)
	var rem_after := R - (car.lap + 1)
	if rem_after <= 0 or winner:
		return
	var wet := weather.wet
	var cur: String = car.tyre.c
	var nominal_wear := nominal_lap_wear(car, cur)
	var per_lap_wear := nominal_wear
	var lap_fuel := fpl
	var wear_ratio := 1.0
	var fuel_ratio := 1.0
	if dyn:
		# the stop calls follow what the car is really using, not the figures the plan started from
		if car.obs_wear > 0.0:
			wear_ratio = car.obs_wear / maxf(nominal_wear, 1e-9)
			per_lap_wear = car.obs_wear * 1.05
		if car.fuel_lap > 0.0:
			fuel_ratio = car.fuel_lap / fpl
			lap_fuel = car.fuel_lap * 1.03
	var laps_in_stint := car.lap + 1 - car.stint_start_lap
	var wear_end: float = car.tyre.wear - per_lap_wear * 0.15
	var fuel_end := car.fuel - lap_fuel * 0.15
	var reason := ""

	var cur0 = car.plan[car.stint_idx] if car.stint_idx < car.plan.size() else null
	var planned_now: bool = cur0 != null and car.stint_idx < car.plan.size() - 1 and laps_in_stint >= cur0.laps
	var weather_shift := absf(wet - car.plan_wet) > 0.12 or (cur != "W" and wet > car.wet_threshold) or (cur == "W" and wet < 0.18)
	var tyre_trouble := not planned_now and wear_end - per_lap_wear < 0.02
	var fuel_trouble := not planned_now and fuel_end - lap_fuel < Strategy.RESERVE * 0.5
	# the car is using tyres or fuel noticeably faster or slower than its plan assumed
	var wear_drift := dyn and absf(wear_ratio / car.plan_wear_ratio - 1.0) > 0.1
	var fuel_drift := dyn and absf(fuel_ratio / car.plan_fuel_ratio - 1.0) > 0.08
	var drifted := wear_drift or fuel_drift
	if weather_shift or tyre_trouble or fuel_trouble or car.plan_stale or drifted:
		var next_before := player_next_stop_lap() if car.is_player else -1
		car.plan_stale = false
		car.plan_wet = wet
		var wear_up := wear_ratio > car.plan_wear_ratio
		var fuel_up := fuel_ratio > car.plan_fuel_ratio
		car.plan_wear_ratio = wear_ratio
		car.plan_fuel_ratio = fuel_ratio
		var opts := strategy.plan(plan_opts({
			"laps": rem_after, "wet": wet, "agg": car.agg, "max_stops": 4,
			"wear_mult": s.wear_mult * wear_ratio, "fuel_mult": s.fuel_mult * fuel_ratio,
			"current": {"c": cur, "wear": maxf(0.0, wear_end), "fuel": maxf(0.0, fuel_end), "mask": car.used_mask, "stops_done": car.stops},
		}))
		if opts.size():
			var best: Dictionary = opts[0]
			var first = best.stints[0] if best.stints.size() else null
			_replace_plan(car, best, laps_in_stint)
			if not (first and first.get("cont", false)):
				if weather_shift:
					reason = "Wets — it is raining" if best.stints[0].c == "W" else "Slicks — track drying"
				elif tyre_trouble:
					reason = "tyres are finished"
				elif fuel_trouble:
					reason = "fuel"
				else:
					reason = "new strategy"
			if car.is_player:
				car.service_edited = false
				var next_now := player_next_stop_lap()
				if drifted and not reason and next_now != next_before and next_now > 0:
					log_event("Strategist: %s than planned — stop moved to lap %d" % [
						"tyres wearing faster" if wear_drift and wear_up else ("tyres lasting longer" if wear_drift else
						("fuel use up" if fuel_up else "fuel use down")), next_now], "box")
	var st = car.plan[car.stint_idx] if car.stint_idx < car.plan.size() else null
	var last_stint: bool = car.stint_idx >= car.plan.size() - 1
	if not reason and st and not last_stint and laps_in_stint >= st.laps:
		reason = "planned stop"
		# some bots gamble on one more lap when tyres and tank can take it
		if dyn and car.pit_bias > 0 and laps_in_stint == st.laps and not car.is_player \
				and wear_end - 2.0 * per_lap_wear > 0.05 and fuel_end - 2.0 * lap_fuel > Strategy.RESERVE:
			reason = ""
	if not car.is_player or not car.service_edited:
		car.service = default_service(car)
	if not reason:
		return
	if car.is_player:
		var sv: Dictionary = car.service
		var text := "Strategist: box this lap (%s) → %s%s" % [reason,
			tyres.compounds[sv.c].display_name if sv.c else "no tyres",
			", +%.1f L" % sv.litres if sv.litres > 0.05 else ""]
		if s.auto_strategist or car.autopilot:
			car.pit_request = true
			log_event(text, "box")
		else:
			log_event(text.replace("box this lap", "suggests boxing") + " — press P", "box")
	else:
		car.pit_request = true

## Splice a fresh plan from the planner onto the stints already driven.
func _replace_plan(car: RaceCar, best: Dictionary, laps_in_stint: int) -> void:
	var done := car.plan.slice(0, car.stint_idx)
	var first = best.stints[0] if best.stints.size() else null
	var rest := []
	if first and first.get("cont", false):
		done.append({"c": car.tyre.c, "laps": laps_in_stint + first.laps})
		rest = best.stints.slice(1)
	else:
		done.append({"c": car.tyre.c, "laps": laps_in_stint})
		rest = best.stints
	for x in rest:
		done.append({"c": x.c, "laps": x.laps})
	car.plan = done

## Fuel and tyres for the car's next stop, from its plan.
func default_service(car: RaceCar) -> Dictionary:
	var rem_after := maxi(1, R - (car.lap + 1))
	var next = car.plan[car.stint_idx + 1] if car.stint_idx + 1 < car.plan.size() else {"c": car.tyre.c, "laps": rem_after}
	var is_last := car.stint_idx + 1 >= car.plan.size() - 1
	var laps: int = rem_after if is_last else mini(next.laps, rem_after)
	var fuel_target := minf(spec.tank, Strategy.fuel_need(laps, car_fpl(car)))
	return make_service(car, next.c, fuel_target)

func make_service(car: RaceCar, c, fuel_target: float) -> Dictionary:
	var arrival := maxf(0.0, car.fuel - car_fpl(car) * 0.1)
	var litres := clampf(fuel_target - arrival, 0.0, spec.tank - arrival) if rules.refuel else 0.0
	var sv := {"c": c, "fuel_target": fuel_target, "litres": litres, "time": Strategy.service_time(s.crew, s.parallel, c != null, litres)}
	if rc:
		sv.repair = rc.repair_time(car)
		sv.time += sv.repair
	return sv

func enter_pit(car: RaceCar) -> void:
	car.mode = "pit"
	# under a red flag the field queues at the end of the pit lane instead of stopping at the boxes
	var red := rc != null and rc.flag == "red"
	car.pit = {"phase": "red" if red else "in", "entered_at": race_time, "hold": 0.0, "wait": 0.0}
	car.pit_request = false
	if not car.service:
		car.service = default_service(car)
	if car.control == "free":
		to_rail(car)
	if car.is_player:
		log_event("Pit lane — red flag, queue at the pit exit" if red else "Pit lane — limiter on, the crew is ready", "box")

func start_service(car: RaceCar) -> void:
	car.v = 0.0
	car.s += track.rel(track.box_s(car.box) - car.s)
	var sv := make_service(car, car.service.c, car.service.fuel_target)
	car.service = sv
	car.pit.phase = "service"
	car.pit.left = sv.time
	car.pit.total = sv.time

func finish_service(car: RaceCar) -> void:
	var sv: Dictionary = car.service
	var old: String = car.tyre.c
	if sv.c:
		car.tyre = {"c": sv.c, "wear": 1.0, "temp": 0.3}
		if s.dynamic_running:
			car.tyre.q = _tyre_quality()
			car.obs_wear = 0.0
		car.used_mask |= Tyres.compound_bit(sv.c)
		car.history.append(sv.c)
	car.fuel = minf(spec.tank, car.fuel + sv.litres)
	car.out_of_fuel = false
	car.stops += 1
	var p := track.rel(car.s)
	car.stint_start_lap = car.lap + 1 if p < 0.0 else car.lap
	car.stint_idx += 1
	var planned = car.plan[car.stint_idx] if car.stint_idx < car.plan.size() else null
	if not planned or planned.c != car.tyre.c:
		car.plan = car.plan.slice(0, car.stint_idx)
		car.plan.append({"c": car.tyre.c, "laps": maxi(1, R - car.stint_start_lap)})
		car.plan_stale = true
	elif car.stint_idx >= car.plan.size() - 1 and R - car.stint_start_lap > planned.laps + 1:
		# long races are planned a few stints ahead: extend the plan once its horizon is reached
		car.plan_stale = true
	var tyre_txt := "%s→%s" % [old, sv.c] if sv.c else "no tyres"
	var fuel_txt := ", +%.1f L" % sv.litres if sv.litres > 0.05 else ""
	if sv.get("repair", 0.0) > 0.0:
		rc.repaired(car)
		fuel_txt += ", repairs"
		car.plan_stale = true
	log_event("%s: %s%s — %.1f s" % ["Your stop" if car.is_player else car.name, tyre_txt, fuel_txt, sv.time], "box" if car.is_player else "pit")
	car.service = null
	car.service_edited = false
	car.pit.phase = "out"

func exit_pit(car: RaceCar) -> void:
	car.mode = "race"
	car.pit = null
	if car.is_player and not car.autopilot and not car.finished:
		to_free(car)
	car.service = default_service(car)

func to_rail(car: RaceCar) -> void:
	car.control = "rail"
	car.v = maxf(0.0, car.vx * cos(car.heading) + car.vy * sin(car.heading))
	car.d_kick = 0.0
	car.lat_v = 0.0
	car.err = null

func to_free(car: RaceCar) -> void:
	car.control = "free"
	car.vx = cos(car.heading) * car.v
	car.vy = sin(car.heading) * car.v
	car.yaw_rate = 0.0
	car.phys = null
	car.rev = false
	car.line_off = car.d - track.sample(track.RLD, car.s)

# ---------------- AI / rail driving ----------------
func traffic(car: RaceCar, vT: float, rl: float, dt: float) -> Dictionary:
	var tr := track
	var lim := tr.half - 1.0
	var ahead: RaceCar = null
	var ahead_gap := INF
	var drag := 1.0
	# nearest car up to 45 m ahead within 2 m sideways. Runs for every car every tick, so the cheap
	# tests go first and track.rel() is inlined; all the tests are pure, so the pick is unchanged.
	var cs := car.s
	var cd := car.d
	var L := tr.L
	var hL := L / 2
	for o in cars:
		if o == car or not absf(o.d - cd) < 2.0 or o.dnf or o.finished:
			continue
		var g := fmod(fmod(o.s - cs + hL, L) + L, L) - hL
		if not (g > 0.0 and g < 45.0 and g < ahead_gap):
			continue
		if o.mode == "pit" and tr.pit_blend(o.s) > 0.4:
			continue
		ahead = o
		ahead_gap = g
	var side := side_room(car)
	if not ahead:
		if car.overtake_t > 0.0:
			car.overtake_t -= dt
		if s.draft:
			drag = tow_drag(car, 0.0, dt)
		var t := {"vT": vT, "dT": car.overtake_d if car.overtake_t > 0.0 else rl, "drag": drag}
		if rc:
			t = avoid_wrecks(car, t)
		return apply_side_room(car, t, side)
	var lat0 := ahead.d - car.d
	var ahead_v := sqrt(ahead.vx * ahead.vx + ahead.vy * ahead.vy) if ahead.control == "free" else ahead.v
	if s.draft:
		drag = tow_drag(car, wake_strength(ahead_gap, absf(lat0), ahead_v), dt)
	elif ahead_gap < 30.0 and absf(lat0) < 1.3:
		drag = 1.0 - 0.3 * (1.0 - ahead_gap / 30.0)
	var wants_by := vT > ahead_v + 0.4 or car.v > ahead_v + 0.6
	# under yellow flags or the safety car only a stricken car may be passed
	var no_pass := rc != null and rc.no_pass(car) and not ahead.stranded
	if no_pass:
		wants_by = false
		car.overtake_t = 0.0
	if wants_by and ahead_gap < 24.0 and car.overtake_t <= 0.0:
		var sides := []
		for d in [ahead.d - 2.4, ahead.d + 2.4]:
			if absf(d) > lim:
				continue
			var blocked := false
			for c in cars:
				if c != car and c != ahead and not c.finished and not c.recovered and c.mode != "pit" and absf(c.d - d) < 2.0 and absf(tr.rel(c.s - car.s) - 3.0) < 11.0:
					blocked = true
					break
			if not blocked:
				sides.append(d)
		if sides.size() == 2 and absf(sides[1] - rl) < absf(sides[0] - rl):
			sides.reverse()
		if sides.size():
			car.overtake_d = sides[0]
			car.overtake_t = 3.5
			car.overtake_t0 += 1
	var dT := rl
	if car.overtake_t > 0.0:
		car.overtake_t -= dt
		dT = car.overtake_d
	if absf(lat0) < 1.8:
		vT = minf(vT, ahead_v + maxf(0.0, ahead_gap - 6.0) * 0.7)
		if ahead_gap < 5.0:
			vT = minf(vT, ahead_v - 0.6)
	var tf := {"vT": vT, "dT": dT, "drag": drag}
	if rc:
		tf = avoid_wrecks(car, tf)
	return apply_side_room(car, tf, side)

## Steer round cars lying on the track (wrecks, beached cars): pick the side with room, slow down to
## get past, and stop if there's no way through.
func avoid_wrecks(car: RaceCar, t: Dictionary) -> Dictionary:
	var tr := track
	var lim := tr.half - 1.0
	for o in cars:
		if not o.stranded or o == car or absf(o.d) > tr.half + 1.0:
			continue
		var g := tr.rel(o.s - car.s)
		if g < -8.0 or g > 140.0:
			continue
		if absf(o.d - car.d) > 4.5 and absf(o.d - t.dT) > 4.5:
			continue
		var left := o.d + 3.0
		var right := o.d - 3.0
		var can_l := left <= lim
		var can_r := right >= -lim
		var d := o.d
		if can_l and can_r:
			d = left if lim - o.d > o.d + lim else right
		elif can_l:
			d = left
		elif can_r:
			d = right
		else:
			t.vT = minf(t.vT, sqrt(2.0 * 3.0 * maxf(0.0, g - 10.0)))
			continue
		t.dT = d
		t.urgent = true # bot_input does not ease a swerve round a wreck
		var lat := absf(car.d - o.d)
		if lat < 2.8:
			t.vT = minf(t.vT, clampf(5.0 + maxf(0.0, g - 12.0) * 0.3, 5.0, 30.0))
		elif g < 30.0:
			t.vT = minf(t.vT, 13.0)
	return t

## Lateral space left by cars running alongside: {lo, hi} offsets this car may steer to without
## leaning on anyone, plus the speed of whoever is squeezing it (squeeze_v, NAN if nobody).
func side_room(car: RaceCar) -> Dictionary:
	var tr := track
	var gap_min := spec.width + 0.55
	var lo := -INF
	var hi := INF
	var squeeze_v := NAN
	var reach := spec.length + 1.2
	var cs := car.s
	var L := tr.L
	var hL := L / 2
	for o in cars:
		if o == car:
			continue
		# track.rel() inlined; the distance test rejects most cars before the flag reads
		var g := fmod(fmod(o.s - cs + hL, L) + L, L) - hL
		if absf(g) > reach or (o.dnf and not o.stranded) or o.finished or o.mode == "pit":
			continue
		var lat := o.d - car.d
		var gm := gap_min + (brain.margin(o) if brain else 0.0)
		if absf(lat) > gm + 1.2:
			continue
		if lat >= 0.0:
			hi = minf(hi, o.d - gm)
		else:
			lo = maxf(lo, o.d + gm)
		var ov := sqrt(o.vx * o.vx + o.vy * o.vy) if o.control == "free" else o.v
		if g > -0.5:
			squeeze_v = ov if is_nan(squeeze_v) else minf(squeeze_v, ov)
	return {"lo": lo, "hi": hi, "squeeze_v": squeeze_v}

func apply_side_room(car: RaceCar, t: Dictionary, side: Dictionary) -> Dictionary:
	if brain and car.brain:
		t = brain.adjust(car, t, track.half - 1.0)
	if side.lo == -INF and side.hi == INF:
		return t
	var lim := track.half + track.cfg.runoff - 1.2
	var lo := maxf(side.lo, -lim)
	var hi := minf(side.hi, lim)
	if lo <= hi:
		t.dT = clampf(t.dT, lo, hi)
		t.room = Vector2(lo, hi)
	else:
		# no room alongside: stay in the middle of the gap and drop back rather than lean on anyone
		t.dT = clampf((side.lo + side.hi) / 2.0, -lim, lim)
		t.urgent = true
		if not is_nan(side.squeeze_v):
			t.vT = minf(t.vT, side.squeeze_v - 1.5)
	if car.overtake_t > 0.0 and (car.overtake_d < lo - 0.3 or car.overtake_d > hi + 0.3):
		car.overtake_t = 0.0
	return t

## Follow the car ahead in the pit lane instead of driving through it.
func pit_traffic(car: RaceCar, vT: float) -> float:
	var tr := track
	# under the safety car the queue out of the pit lane also minds the car that has just rejoined
	var queue := rc != null and rc.neutral
	for o in cars:
		if o == car or o.dnf or (o.mode != "pit" and not (queue and o.mode == "race")):
			continue
		var g := tr.rel(o.s - car.s)
		if g <= 0.0 or g > 20.0 or absf(o.d - car.d) > 1.9:
			continue
		if o.mode != "pit":
			vT = minf(vT, maxf(0.0, RaceControl._speed(o) + (g - 8.0) * 0.8))
			continue
		# a car still parked in its box isn't in the way of someone in the fast lane
		if o.pit.phase != "in" and o.v < 0.5 and absf(o.d - tr.cfg.pit_offset) > 2.5:
			continue
		vT = minf(vT, maxf(0.0, o.v + (g - 6.0) * 0.8))
		if g < 4.5:
			vT = minf(vT, maxf(0.0, o.v - 0.8))
	# pulling out of the box: give way to anyone moving down the fast lane beside or just behind,
	# but only while still parked in the box lane, and never for more than a few seconds
	var lane := tr.cfg.pit_offset
	var box_lane := lane + signf(lane) * 3.6
	if car.pit.phase == "out" and absf(car.d - box_lane) < 0.8 and car.pit.wait < 4.0:
		for o in cars:
			if o == car or o.mode != "pit" or o.dnf or o.v < 1.0 or absf(o.d - lane) > 1.5:
				continue
			var behind := tr.rel(car.s - o.s)
			if behind > -4.5 and behind < 14.0:
				vT = 0.0
				break
	return vT

## Unsafe-release check: hold a serviced car while someone is coming down the fast lane.
func pit_lane_clear(car: RaceCar) -> bool:
	var tr := track
	var lane := tr.cfg.pit_offset
	if car.pit.hold > 5.0:
		return true
	for o in cars:
		if o == car or o.mode != "pit" or o.dnf or o.pit.phase == "service" or o.v < 1.0:
			continue
		var behind := tr.rel(car.s - o.s)
		if behind > -4.0 and behind < 28.0 and absf(o.d - lane) < 2.2:
			return false
	return true

func pit_speed(car: RaceCar, v_race: float) -> float:
	var tr := track
	var p := tr.rel(car.s)
	var box_p := tr.box_s(car.box)
	var vT := v_race
	if rc and car.pit.get("go", 0.0) > race_time:
		return 0.0 # red-flag restart: the queue leaves the pit lane one car at a time
	if car.pit.phase == "in" or car.pit.phase == "red":
		var to_lane := tr.lane_start - p
		vT = minf(vT, sqrt(Strategy.PIT_SPEED * Strategy.PIT_SPEED + 2.0 * 5.5 * to_lane) if to_lane > 0.0 else Strategy.PIT_SPEED)
		if car.pit.phase == "red":
			# red flag: line up at the end of the pit lane
			vT = minf(vT, sqrt(maxf(0.0, 2.0 * 4.0 * (rc.red_stop - p - 0.3))))
		else:
			var to_box := box_p - p
			vT = minf(vT, maxf(0.8, sqrt(maxf(0.0, 2.0 * 4.5 * (to_box - 0.3)))))
	elif p < tr.lane_end:
		vT = minf(vT, Strategy.PIT_SPEED)
	return vT

func pit_lateral(car: RaceCar, rl: float) -> float:
	var tr := track
	var po := tr.cfg.pit_offset
	var p := tr.rel(car.s)
	# swing into the box only in the last few metres, clear of the neighbouring boxes
	var near := SimUtil.smooth01(1.0 - maxf(0.0, absf(p - tr.box_s(car.box)) - 1.5) / 6.0)
	if car.pit.phase == "red":
		near = 0.0 # queueing in the fast lane
	var lane := po + signf(po) * 3.6 * near
	return rl + (lane - rl) * tr.pit_blend(car.s)

## What a racing car wants right now: speed, lateral position and slipstream, from its pace, the
## car ahead and anyone alongside. Shared by bots on rails and bots driving the full physics.
func targets(car: RaceCar, dt: float, mu: float, is_phys: bool) -> Dictionary:
	var tr := track
	var rl := tr.sample(tr.RLD, car.s)
	var br: Brain = brain if brain and car.brain else null
	var v := maxf(0.0, car.speed) if is_phys else car.v
	var look := car.s + v * 0.12
	var K := sqrt(mu) * (br.pace_at(car, look) if br else car.skill) * car.pace * car.pace_scale
	if car.err and car.err.kind == "late":
		K *= 1.05
	var vT := tr.sample(tr.PROF, look) * K
	var dT := rl
	var drag := 1.0
	var room := Vector2(-INF, INF) # the lateral room cars alongside leave
	var urgent := false # dT dodges a wreck or a squeeze
	var hindered: bool = car.finished or car.slow_t > 0.0 or car.err != null
	if car.finished:
		vT *= 0.8
	if car.slow_t > 0.0:
		car.slow_t -= dt
		vT *= 0.82
	if not car.finished:
		var t := traffic(car, vT, rl, dt)
		if rc:
			rc.limit_speed(car, t, mu)
			if rc.slowed(car):
				hindered = true
		if t.vT < vT - 0.3 or car.overtake_t > 0.0:
			hindered = true
		vT = t.vT
		dT = t.dT
		drag = t.drag
		room = t.get("room", room)
		urgent = t.get("urgent", false)
	if phase != "racing" or race_time < car.reaction:
		vT = 0.0
	if br:
		br.rail_step(car, dt, hindered)
	return {"vT": vT, "dT": dT, "drag": drag, "K": K, "err": car.err, "rl": rl, "room": room, "urgent": urgent}

func step_rail(car: RaceCar, dt: float) -> void:
	var tr := track
	var wet := weather.wet
	if car.mode == "pit" and car.pit.phase == "service":
		car.v = 0.0
		car.throttle = 0.0
		car.rpm = spec.idle_rpm
		car.pit.left -= dt
		if car.pit.left <= 0.0:
			car.pit.hold += dt
		if car.pit.left <= 0.0 and pit_lane_clear(car):
			finish_service(car)
		return
	var mu := tyres.tyre_grip(car.tyre, wet)
	var mass := car_model.mass_with_fuel(car.fuel)
	var rl := tr.sample(tr.RLD, car.s)
	var vT: float
	var dT: float
	var drag: float
	if car.mode == "pit":
		vT = pit_traffic(car, pit_speed(car, tr.sample(tr.PROF, car.s + car.v * 0.12) * sqrt(mu)))
		dT = pit_lateral(car, rl)
		drag = 1.0
		if car.pit.phase == "out" and car.v < 0.5:
			car.pit.wait += dt
		if car.pit.phase == "in" and tr.rel(car.s) >= tr.box_s(car.box) - 0.6:
			start_service(car)
			return
		if phase != "racing":
			vT = 0.0
		if brain and car.brain:
			brain.rail_step(car, dt, true)
	else:
		var tg := targets(car, dt, mu, false)
		vT = tg.vT
		dT = tg.dT
		drag = tg.drag
		vT *= 1.0 - 0.012 * absf(car.d - rl)
		if absf(car.d) > tr.half + 0.3:
			vT *= 0.75
		if car.damage > 0.0:
			vT *= 1.0 - (0.3 if rc else 0.06) * car.damage
			drag *= 1.0 + 0.5 * car.damage

	var a := 0.0
	var climb := G * tr.sample(tr.GRADE, car.s) + (0.0 if car.mode == "pit" else car_model.scrub(car.v, tr.sample(tr.RK, car.s), mu))
	var a_max := car_model.max_accel(car.v, mass, mu, drag) * (1.0 - 0.3 * car.damage) - climb
	if car.v < vT and car.fuel > 0.0 and a_max > 0.0:
		a = minf(a_max, (vT - car.v) / dt)
	elif car.v > vT:
		a = -minf(mu * G + climb, (car.v - vT) / dt)
	else:
		a = -car_model.resistance(car.v, mass, drag) / mass - climb
	car.brake_on = a < -2.5
	car.v = maxf(0.0, car.v + a * dt)
	var force := mass * 1.05 * a + car_model.resistance(car.v, mass, drag) + mass * climb if a >= -climb else 0.0
	car.gear = car_model.best_gear(car.v)
	var f_max := maxf(1.0, car_model.wheel_force(car.v, car.gear, 1.0))
	car.throttle = clampf(force / f_max, 0.0, 1.0)
	car.rpm = car_model.engine_rpm(car.v, car.gear, car.throttle)
	car.fuel = maxf(0.0, car.fuel - car_model.fuel_rate(force * car.v / spec.efficiency) * dt * s.fuel_mult)

	var in_pit := car.mode == "pit"
	var lat_max := 5.0 if in_pit else 1.2 + 0.1 * car.v
	# follow the line's own sideways drift, correct the error smoothly, and never jerk sideways
	var ff := 0.0 if in_pit else (tr.sample(tr.RLD, car.s + 1.0) - tr.sample(tr.RLD, car.s)) * car.v
	var want := clampf(ff + (dT - car.d) * (5.0 if in_pit else 2.0), -lat_max, lat_max)
	var a_lat := 14.0 if in_pit else 4.0 + 0.12 * car.v
	car.lat_v = car.lat_v + clampf(want - car.lat_v, -a_lat * dt, a_lat * dt)
	var dd := car.lat_v + car.d_kick
	car.d_kick *= exp(-5.0 * dt)
	car.d += dd * dt
	if car.mode != "pit":
		var lim := tr.half + tr.cfg.runoff - 1.0
		car.d = clampf(car.d, -lim, lim)
	move_s(car, car.v * dt * tr.s_rate(car.s, car.d))
	var q := tr.pos(car.s, car.d)
	car.x = q[0]
	car.y = q[1]
	car.heading = tr.heading(car.s) + atan2(dd, maxf(3.0, car.v))
	car.vx = cos(car.heading) * car.v
	car.vy = sin(car.heading) * car.v
	car.speed = car.v
	var factor := 0.3 if car.mode == "pit" else car.agg * (0.85 if car.brain and car.brain.mind == "manage" else 1.0)
	if s.dynamic_running and car.mode != "pit":
		# a bot's tyres wear with the same load the player's do: cornering and braking or accelerating
		# against the grip available, so hard corners, dirty air and a heavy tank all cost tread
		var g_lat := car.v * car.v * absf(tr.sample(tr.RK, car.s))
		var u := minf(1.5, sqrt(g_lat * g_lat + a * a) / (mu * G))
		factor *= (0.45 + 1.1 * u * u) / RAIL_LOAD_NORM
	wear_tyres(car, car.v * dt, factor)

func wear_tyres(car: RaceCar, dist: float, factor: float) -> void:
	var t: Dictionary = car.tyre
	if s.dynamic_running:
		# cold tyres slide and grain, a heavy tank leans on them, and every set wears a little differently
		var load_mass: float = car_model.mass_with_fuel(car.fuel) / cal.m_ref
		factor *= (1.0 + 0.4 * (1.0 - t.temp) * (1.0 - t.temp)) * pow(load_mass, 0.7) * t.get("q", 1.0)
	t.wear = maxf(0.0, t.wear - dist * tyres.wear_per_metre(t.c, weather.wet, s.wear_mult) * factor)
	t.temp = minf(1.0, t.temp + dist / 1500.0)
	if t.wear <= 0.0 and not t.get("dead", false) and not car.finished:
		t.dead = true
		log_event("%s tyres are completely worn out!" % ("Your" if car.is_player else car.name + "'s"), "bad")
		if not car.is_player or s.auto_strategist or car.autopilot:
			car.plan_stale = true

# ---------------- player physics ----------------
## Surface (Physics.SURF_*) under one wheel, from its lateral offset on the track.
func surface_at(car: RaceCar, x: float, y: float) -> int:
	var tr := track
	var d := car.d + (x - car.x) * tr.sample(tr.NX, car.s) + (y - car.y) * tr.sample(tr.NY, car.s)
	var ad := absf(d)
	if ad <= tr.half + 0.3:
		return Physics.SURF_TRACK
	var c := tr.cfg
	var p := tr.rel(car.s)
	if signf(d) == signf(c.pit_offset) and p > c.pit_entry - 20.0 and p < c.pit_exit + 20.0:
		return Physics.SURF_ASPHALT
	match c.runoff_surface:
		"asphalt": return Physics.SURF_ASPHALT
		"gravel": return Physics.SURF_GRAVEL
	return Physics.SURF_GRASS

## input: the player's controls (shift requests are consumed), or null for a bot.
func step_free(car: RaceCar, dt: float, thr: float, brk: float, steer_in: float, input: PlayerInput) -> void:
	var tr := track
	var hold := phase != "racing"
	if car.fuel <= 0.0:
		thr = 0.0
	var mass := car_model.mass_with_fuel(car.fuel)
	var ch := cos(car.heading)
	var sh := sin(car.heading)
	var vF := car.vx * ch + car.vy * sh

	# reverse: hold the brake at a standstill; throttle selects first again
	if not car.rev and brk > 0.3 and thr < 0.05 and absf(vF) < 0.4 and not hold:
		car.rev = true
		car.gear = 0
	elif car.rev and thr > 0.05:
		if vF < -0.5:
			brk = thr
			thr = 0.0
		else:
			car.rev = false
	if car.rev:
		var t := thr
		thr = brk
		brk = t

	if not car.rev and (not car.is_player or s.gearbox == "auto"):
		auto_shift(car, vF, thr, brk)
	elif not car.rev and input:
		if input.shift_up and car.gear < spec.gears.size() - 1:
			car.gear += 1
			car.shift_t = 0.18
		if input.shift_down and car.gear > 0:
			car.gear -= 1
			car.shift_t = 0.18
	if input:
		input.shift_up = false
		input.shift_down = false

	if hold:
		car.rpm += (spec.idle_rpm + thr * 5200.0 - car.rpm) * minf(1.0, dt * 6.0)
		car.throttle = thr
		car.vx = 0.0
		car.vy = 0.0
		car.yaw_rate = 0.0
		car.phys = null
		return

	var grade := G * tr.sample(tr.GRADE, car.s)
	var tx := tr.sample(tr.TX, car.s)
	var ty := tr.sample(tr.TY, car.s)
	# bots run the same driving-aid setting the player chose — no free assist the player didn't pick
	var assists := s.assists
	var drag_mul := slipstream(car, dt) if car.is_player else car.slip_drag
	var mu := tyres.tyre_grip(car.tyre, weather.wet)
	var steer := steer_assist(car, steer_in, mu, assists) if car.is_player else steer_in
	var env := _env
	env.mu = mu
	env.mass = mass
	_surf_car = car
	env.surface = _surface_fn
	# a banked turn pulls the car down the slope, towards the inside
	var bank := tr.bank_slope(car.s, car.d)
	var bank_g := G * bank / sqrt(1.0 + bank * bank)
	env.gx = -grade * tx - bank_g * tr.sample(tr.NX, car.s)
	env.gy = -grade * ty - bank_g * tr.sample(tr.NY, car.s)
	if car.is_player and limiter and rc and not car.rev:
		# the limiter holds the car under the speed the flags allow and short of the car ahead; the driver
		# still steers and brakes
		var cap := rc.limiter_cap(car)
		if cap > 0.0 or rc.neutral:
			var over := vF - (cap - 1.0)
			thr = minf(thr, clampf(-over * 0.5, 0.0, 1.0))
			if over > 0.5:
				brk = maxf(brk, clampf((over - 0.5) * 0.4, 0.0, 0.8))
	if car.damage > 0.0:
		# bent bodywork and suspension: less power, more drag, a pull to one side
		thr *= 1.0 - 0.3 * car.damage
		drag_mul *= 1.0 + 0.5 * car.damage
		steer = clampf(steer + car.dmg_pull, -1.0, 1.0)
	env.drag_mul = drag_mul
	env.abs_on = assists != "off"
	env.tc_on = assists == "full"
	env.esc_on = assists == "full"
	_ctl.throttle = thr
	_ctl.brake = brk
	_ctl.steer = steer
	phys.step(car, _ctl, env, dt)
	car.shift_t = maxf(0.0, car.shift_t - dt)

	var pr := tr.project(car.x, car.y, car.s)
	move_s(car, tr.rel(pr[0] - car.s))
	car.d = pr[1]
	barrier_contact(car, mass)

	car.fuel = maxf(0.0, car.fuel - car_model.fuel_rate(phys.engine_power) * dt * s.fuel_mult)
	# wear follows the energy the tyres dissipate while sliding, on top of normal running
	var mu_g := tyres.tyre_grip(car.tyre, weather.wet) * G
	var acc := sqrt(car.phys.ax_f * car.phys.ax_f + car.phys.ay_f * car.phys.ay_f)
	var u := minf(1.5, acc / mu_g)
	var slide := minf(3.0, phys.slide_power / (mass * mu_g * 1.5))
	var off_track := absf(car.d) > tr.half + 0.5
	var factor := (0.45 + 1.1 * u * u + 0.5 * slide) * (1.4 if off_track else 1.0)
	wear_tyres(car, absf(car.speed) * dt, factor)

## Automatic gearbox, shared by the player's auto option and every bot.
func auto_shift(car: RaceCar, vF: float, thr: float, brk: float) -> void:
	var cm := car_model
	var vp := maxf(0.0, vF)
	var top := spec.gears.size() - 1
	var g := car.gear
	if vF < 1.0:
		g = 0
	# upshift at the point where the next gear pulls harder, or just before the limiter
	elif g < top and (car.rpm > 6150.0 or cm.wheel_force(vp, g + 1, 1.0) > cm.wheel_force(vp, g, 1.0)) and cm.rpm_for(vF, g + 1) > 2800.0:
		g += 1
	# on the power, drop a gear as soon as it pulls clearly harder; on the brakes, keep the revs up for the exit
	elif g > 0 and cm.rpm_for(vF, g - 1) < 5900.0 and (cm.wheel_force(vp, g - 1, 1.0) > cm.wheel_force(vp, g, 1.0) * 1.06 or (brk > 0.1 and cm.rpm_for(vF, g) < 3200.0)):
		g -= 1
	if g != car.gear:
		# part-throttle or braking shifts are quicker to settle than a flat-out upshift
		car.shift_t = 0.15 if g > car.gear else 0.12
		car.gear = g

## A digital key (or a twitchy pad) asks for full lock the instant it's pressed — the bots never do
## that; their pure-pursuit steering only ever asks for exactly the angle the coming curvature needs.
## On the Full driving-aid tier, hold the player to the same standard: cap steering to a bit more than
## that ideal angle, so mashing the key on a gentle bend doesn't ask for more lock than the corner
## wants and throw the car into a slide the bots would never suffer for the same corner. It only caps
## steering that's already pointed the way the line wants — an opposite-lock correction, a deliberate
## drift, anything that isn't "turning the way the corner goes" is left alone.
func steer_assist(car: RaceCar, raw: float, mu: float, assists: String) -> float:
	if assists != "full" or absf(raw) < 1e-3:
		return raw
	var ideal := Driver.line_steer(phys, track, car, mu)
	if signf(raw) != signf(ideal):
		return raw
	var cap := absf(ideal) * 1.35 + 0.05
	return signf(raw) * cap if absf(raw) > cap else raw

## Full assists: brake for the corners ahead the way the bots judge them (Driver.control), but only as
## far as the car is over the speed they allow — the pedal is never eased, and a car on the limit is left alone.
## Returns the brake to add (0–1); step() lifts the throttle by the same amount.
func brake_assist(car: RaceCar) -> float:
	if car.rev or phase != "racing" or car.mode != "race" or car.finished:
		return 0.0
	var v := car.vx * cos(car.heading) + car.vy * sin(car.heading)
	if v < 8.0:
		return 0.0
	var tr := track
	var mu := tyres.tyre_grip(car.tyre, weather.wet)
	var K := sqrt(mu) * ASSIST_PACE
	var aB := 0.86 * mu * G
	var lead := v * 0.12
	var v_ref := INF
	var x := 0.0
	while x < 140.0:
		var va := tr.sample(tr.PROF, car.s + lead + x) * K
		var room := va * va + 2.0 * aB * x
		v_ref = minf(v_ref, sqrt(room))
		if room > v * v + 400.0:
			break
		x += 5.0
	return clampf((v - v_ref - 1.0) * 0.35, 0.0, 1.0)

## A beached player car is set back on the track after a moment — the bots get the same
## (bot_control), so one slide into the gravel doesn't end the race. A car that has merely spun to face
## the wrong way is never moved: the player turns it round themselves (reverse and lock), so this only
## counts time spent stopped while pointing along the track.
func player_rejoin(car: RaceCar, dt: float) -> void:
	if phase != "racing" or race_time < 3.0 or car.mode != "race" or car.finished or car.out_of_fuel:
		car.stuck_t = 0.0
		return
	var tr := track
	var off := absf(SimUtil.wrap_angle(car.heading - tr.heading(car.s)))
	var v := sqrt(car.vx * car.vx + car.vy * car.vy)
	car.stuck_t = car.stuck_t + dt if off <= 1.4 and v < 2.5 else 0.0
	if car.stuck_t < 3.0:
		return
	car.stuck_t = 0.0
	var lim := tr.half - 1.5
	car.d = clampf(car.d, -lim, lim)
	var p := tr.pos(car.s, car.d)
	car.x = p[0]
	car.y = p[1]
	car.heading = tr.heading(car.s)
	car.px = car.x
	car.py = car.y
	car.ph = car.heading
	car.vx = 0.0
	car.vy = 0.0
	car.yaw_rate = 0.0
	car.phys = null
	car.rev = false
	car.gear = 0
	log_event("Back on track — keep going!", "info")

## Strength 0..1 of the wake of a car `gap` m ahead (centre to centre) and `lat` m to one side, moving at `v`.
## It is densest right behind the car, thins out over a few car lengths, widens as it goes and needs the
## car ahead to be moving fast enough to leave one.
static func wake_strength(gap: float, lat: float, v: float) -> float:
	if gap <= 0.0 or gap > 60.0:
		return 0.0
	var behind := maxf(0.0, gap - 3.6) # bumper to bumper
	var x := lat / (0.9 + 0.02 * behind)
	return clampf((v - 8.0) / 22.0, 0.0, 1.0) * exp(-behind / 14.0 - x * x)

## The tow builds up over about 0.7 s once a car tucks in behind another and is lost within 0.4 s of
## leaving the wake, so speed is gained and shed gradually. Returns the drag multiplier.
func tow_drag(car: RaceCar, strength: float, dt: float) -> float:
	car.tow = move_toward(car.tow, strength, (1.5 if strength > car.tow else 2.5) * dt)
	return 1.0 - TOW_MAX * car.tow

## Drag multiplier from the wake of the cars ahead of the player.
func slipstream(car: RaceCar, dt: float) -> float:
	var tr := track
	var cs := car.s
	var L := tr.L
	var hL := L / 2
	if s.draft:
		var best := 0.0
		for o in cars:
			if o == car or not absf(o.d - car.d) < 2.5 or o.dnf or o.finished or o.mode == "pit":
				continue
			var g := fmod(fmod(o.s - cs + hL, L) + L, L) - hL
			if g > 0.0 and g < 60.0:
				var ov := sqrt(o.vx * o.vx + o.vy * o.vy) if o.control == "free" else o.v
				best = maxf(best, wake_strength(g, absf(o.d - car.d), ov))
		return tow_drag(car, best, dt)
	var drag := 1.0
	for o in cars:
		if o == car or not absf(o.d - car.d) < 1.3 or o.dnf or o.finished or o.mode == "pit":
			continue
		var g := fmod(fmod(o.s - cs + hL, L) + L, L) - hL
		if g > 0.0 and g < 30.0:
			drag = minf(drag, 1.0 - 0.3 * (1.0 - g / 30.0))
	return drag

const NEAR_PHYS_PICK_UP := 250.0 ## m along the track: a rail bot this close to the player switches to the physics
const NEAR_PHYS_DROP := 350.0 ## m: a physics bot this far away goes back on the rail model

## Bots drive the full car physics at normal speed. Under time warp, in the pits, after the flag, or
## while recovering from a spin they fall back to the rail model.
func bot_control(car: RaceCar, dt: float) -> void:
	var tr := track
	if car.recover_t > 0.0:
		car.recover_t -= dt
	var want := phys_bots and warp == 1 and car.mode == "race" and not car.finished and not (car.recover_t > 0.0)
	if want and phys_near_only and player:
		# battery saver: the physics only runs within sight of the player (with a margin so a car on the
		# edge does not flip between models every tick)
		want = absf(track.rel(car.s - player.s)) < (NEAR_PHYS_DROP if car.control == "free" else NEAR_PHYS_PICK_UP)
	if not want:
		if car.control == "free":
			to_rail(car)
		return
	if car.control == "rail":
		to_free(car)
		return
	if phase != "racing" or race_time < car.reaction + 3.0:
		return
	# spun or stuck: a car facing the wrong way drives itself round (bot_input) instead of being lifted
	# back onto the line; only one that stays wedged and stopped is put back
	var off := absf(SimUtil.wrap_angle(car.heading - tr.heading(car.s)))
	var v := sqrt(car.vx * car.vx + car.vy * car.vy)
	if bot_uturn:
		if off > 1.4 and v < 14.0:
			car.uturn = true
		elif off < 0.7:
			car.uturn = false
	# without the U-turn a car facing the wrong way counts as stuck at any speed and is put back quickly
	var wrong_way := off > 1.4 and not bot_uturn
	car.stuck_t = car.stuck_t + dt if wrong_way or (v < 2.5 and not car.out_of_fuel and not (rc and rc.neutral)) else 0.0
	if car.stuck_t > ((10.0 if bot_uturn else 1.2) if off > 1.4 else 2.5):
		car.stuck_t = 0.0
		car.uturn = false
		to_rail(car)
		car.v = minf(car.v, 3.0)
		car.recover_t = 4.0
		if absi(car.pos - player.pos) <= 3:
			log_event("%s spins and rejoins" % car.name, "info")

func bot_input(car: RaceCar, dt: float) -> Physics.Controls:
	if car.uturn:
		car.line_off = car.d - track.sample(track.RLD, car.s) # rejoins easing across from wherever it turned round
		# facing the wrong way: creep forwards on full lock towards the direction of the track
		var diff := SimUtil.wrap_angle(track.heading(car.s) - car.heading)
		var v := sqrt(car.vx * car.vx + car.vy * car.vy)
		_uturn_ctl.steer = signf(diff) if diff != 0.0 else 1.0
		_uturn_ctl.throttle = 0.45 if v < 6.0 else 0.0
		_uturn_ctl.brake = 0.3 if v > 9.0 else 0.0
		return _uturn_ctl
	var mu := tyres.tyre_grip(car.tyre, weather.wet)
	var tg := targets(car, dt, mu, true)
	car.slip_drag = tg.drag
	if bot_smooth_line and line_slew > 0.0:
		# targets() can jump (an overtake, a block, the racing line after a squeeze): a driver moves across the
		# track smoothly instead of snapping the wheel to the new line, and no faster than the car is moving
		# (on the grid it holds its slot). Dodging a wreck or a squeeze is not eased, and the room a car
		# alongside leaves is a hard limit either way.
		var rl: float = tg.rl
		if tg.urgent:
			car.line_off = tg.dT - rl
		else:
			var rate := minf(line_slew, line_slew_per_m * maxf(0.0, car.speed)) * dt
			car.line_off += clampf(tg.dT - rl - car.line_off, -rate, rate)
		tg.dT = clampf(rl + car.line_off, tg.room.x, tg.room.y)
		car.line_off = tg.dT - rl
	if car.err:
		if bot_smooth_line:
			car.err.age = car.err.get("age", 0.0) + dt
		car.err.t -= dt
		if car.err.t <= 0.0:
			car.err = null
	return Driver.control(phys, track, car, tg, mu, _ctl)

## A driving error: on rails a sideways twitch, in the physics a braking point missed or a line run wide
## that the car then has to live with.
func bot_mistake(car: RaceCar, severity := 1.0) -> void:
	var tr := track
	var k := tr.sample(tr.KC, car.s + 25.0)
	var outward := -signf(k if k != 0.0 else 1.0)
	if car.control == "free":
		var late := rng.next() < 0.55
		var d := outward * (1.2 + 2.2 * rng.next()) * severity
		car.err = {"kind": "late" if late else "wide", "d": d, "t": 1.6 + rng.next() * 1.4}
	else:
		car.slow_t = maxf(car.slow_t, (0.7 + rng.next() * 0.9) * severity)
		car.d_kick += outward * (1.2 + 2.0 * rng.next())

## Car corners against the barriers: push back out and apply a rigid-body impulse (with scraping friction),
## so a glancing hit spins the car the way the corner struck.
func barrier_contact(car: RaceCar, mass: float) -> void:
	var tr := track
	var lim := tr.limits(car.s)
	var hl := spec.length / 2.0
	var hw := spec.width / 2.0
	# a corner sits at most the half-diagonal from the centre (the interpolated normal is no longer than 1),
	# so with that much room to both walls no corner can touch: skip the corner tests
	var reach := sqrt(hl * hl + hw * hw) + 0.01
	if car.d + reach < lim[1] + hw and car.d - reach > lim[0] - hw:
		return
	var nx := tr.sample(tr.NX, car.s)
	var ny := tr.sample(tr.NY, car.s)
	var ch := cos(car.heading)
	var sh := sin(car.heading)
	var hit := 0.0
	for side in [1.0, -1.0]:
		var wall: float = lim[1] + hw if side > 0.0 else lim[0] - hw
		var pen := 0.0
		var rx := 0.0
		var ry := 0.0
		for c in [[hl, hw], [hl, -hw], [-hl, hw], [-hl, -hw]]:
			var ox: float = c[0] * ch - c[1] * sh
			var oy: float = c[0] * sh + c[1] * ch
			var p: float = (car.d + ox * nx + oy * ny - wall) * side
			if p > pen:
				pen = p
				rx = ox
				ry = oy
		if pen <= 0.0:
			continue
		car.x -= nx * pen * side
		car.y -= ny * pen * side
		car.d -= pen * side
		hit = maxf(hit, phys.barrier_hit(car, nx * side, ny * side, rx, ry, mass))
	if rc and hit > 0.0:
		rc.report_barrier(car, hit)
	if hit > 5.0 and clock - car.last_hit > 1.5 and (car.is_player or not rc):
		car.last_hit = clock
		log_event("Ouch — that was the barrier!", "bad")

# ---------------- contact ----------------
## Separating-axis test between two car rectangles: [nx, ny, depth] (n from a to b) or [] if clear.
func sat(a: RaceCar, b: RaceCar) -> PackedFloat64Array:
	var hl := spec.length / 2.0
	var hw := spec.width / 2.0
	var ca := cos(a.heading)
	var sa := sin(a.heading)
	var cb := cos(b.heading)
	var sb := sin(b.heading)
	var axes := [ca, sa, -sa, ca, cb, sb, -sb, cb]
	var dx := b.x - a.x
	var dy := b.y - a.y
	var best := INF
	var bnx := 0.0
	var bny := 0.0
	for k in 4:
		var ax: float = axes[2 * k]
		var ay: float = axes[2 * k + 1]
		var ra := hl * absf(ca * ax + sa * ay) + hw * absf(-sa * ax + ca * ay)
		var rb := hl * absf(cb * ax + sb * ay) + hw * absf(-sb * ax + cb * ay)
		var dist := dx * ax + dy * ay
		var o := ra + rb - absf(dist)
		if o <= 0.0:
			return PackedFloat64Array()
		if o < best:
			best = o
			bnx = -ax if dist < 0.0 else ax
			bny = -ay if dist < 0.0 else ay
	return PackedFloat64Array([bnx, bny, best])

## Offset from a car's centre to its corner furthest along (nx, ny).
func corner(car: RaceCar, nx: float, ny: float) -> PackedFloat64Array:
	var ch := cos(car.heading)
	var sh := sin(car.heading)
	var fx := (1.0 if ch * nx + sh * ny >= 0.0 else -1.0) * spec.length / 2.0
	var fy := (1.0 if -sh * nx + ch * ny >= 0.0 else -1.0) * spec.width / 2.0
	return PackedFloat64Array([fx * ch - fy * sh, fx * sh + fy * ch])

func collide() -> void:
	# only cars racing on track touch (pit-lane cars are skipped); nothing below changes those flags,
	# so gather them once instead of re-testing every pair. Pairs keep their (i < j) order.
	var live := _collide_live
	live.clear()
	for c in cars:
		if not c.finished and (not c.dnf or c.stranded) and c.mode != "pit":
			live.append(c)
	var n := live.size()
	for i in n:
		var a: RaceCar = live[i]
		for j in range(i + 1, n):
			var b: RaceCar = live[j]
			var dx := a.x - b.x
			var dy := a.y - b.y
			if dx * dx + dy * dy > 16.0:
				continue
			# where the track crosses itself (Suzuka), one car is on the bridge and the other under it
			if absf(track.sample(track.H, a.s) - track.sample(track.H, b.s)) > 3.0:
				continue
			var hit := sat(a, b)
			if hit.is_empty():
				continue
			var nx := hit[0]
			var ny := hit[1]
			var depth := hit[2]
			# share the separation, but a car pinned against its barrier can't give way
			var room_a := room(a, -nx, -ny)
			var room_b := room(b, nx, ny)
			var da := minf(depth * 0.5, room_a)
			var db := minf(depth - da, room_b)
			da = minf(depth - db, room_a)
			shove(a, -nx * da, -ny * da)
			shove(b, nx * db, ny * db)
			var rel_v := (b.vx - a.vx) * nx + (b.vy - a.vy) * ny
			if rel_v < 0.0:
				var jimp := -(1.0 + 0.25) * rel_v / 2.0
				var wa := 0.0 if room_a < 0.05 else (2.0 if room_b < 0.05 else 1.0)
				var wb := 2.0 - wa
				# contact point: midway between each car's corner nearest the other
				var ca := corner(a, nx, ny)
				var cb := corner(b, -nx, -ny)
				var px := (a.x + ca[0] + b.x + cb[0]) / 2.0
				var py := (a.y + ca[1] + b.y + cb[1]) / 2.0
				kick(a, -nx * jimp * wa, -ny * jimp * wa, px - a.x, py - a.y)
				kick(b, nx * jimp * wb, ny * jimp * wb, px - b.x, py - b.y)
				if rc:
					rc.report_contact(a, b, nx, ny, jimp * wa, jimp * wb)
				if brain and jimp > 1.0:
					brain.contact(a, b, nx, ny)
				if (a.is_player or b.is_player) and jimp > 2.5 and clock - last_contact > 1.0:
					last_contact = clock
					log_event("Contact with %s!" % (b.name if a.is_player else a.name), "bad")

## How far a car can be pushed along (ux, uy) before its lateral limit (barrier / run-off edge).
func room(car: RaceCar, ux: float, uy: float) -> float:
	var tr := track
	var un := ux * tr.sample(tr.NX, car.s) + uy * tr.sample(tr.NY, car.s)
	if absf(un) < 0.2:
		return INF
	var lo: float
	var hi: float
	if car.control == "free":
		var lim := tr.limits(car.s)
		lo = lim[0]
		hi = lim[1]
	else:
		hi = tr.half + tr.cfg.runoff - 1.0
		lo = -hi
	var r := (hi - car.d) / un if un > 0.0 else (car.d - lo) / -un
	return maxf(0.0, r)

func shove(car: RaceCar, dx: float, dy: float) -> void:
	var tr := track
	if car.control == "free":
		car.x += dx
		car.y += dy
		var pr := tr.project(car.x, car.y, car.s)
		var lim := tr.limits(car.s)
		var d := clampf(pr[1], lim[0], lim[1])
		if d != pr[1]:
			car.x += tr.sample(tr.NX, car.s) * (d - pr[1])
			car.y += tr.sample(tr.NY, car.s) * (d - pr[1])
		car.d = d
		return
	var lim := tr.half + tr.cfg.runoff - 1.0
	car.d = clampf(car.d + dx * tr.sample(tr.NX, car.s) + dy * tr.sample(tr.NY, car.s), -lim, lim)
	move_s(car, dx * tr.sample(tr.TX, car.s) + dy * tr.sample(tr.TY, car.s))
	var q := tr.pos(car.s, car.d)
	car.x = q[0]
	car.y = q[1]

func kick(car: RaceCar, ix: float, iy: float, rx: float, ry: float) -> void:
	if car.control == "free":
		phys.kick(car, ix, iy, rx, ry)
		return
	var tr := track
	car.v = maxf(0.0, car.v + ix * tr.sample(tr.TX, car.s) + iy * tr.sample(tr.TY, car.s))
	car.d_kick += ix * tr.sample(tr.NX, car.s) + iy * tr.sample(tr.NY, car.s)
	car.vx = cos(car.heading) * car.v
	car.vy = sin(car.heading) * car.v

## Nudge the field's pace a little towards the player's, scaled by difficulty: bots that have broken
## clear ease off a fraction, bots that have fallen behind push a little harder. Small and slow enough
## that it never overturns a real pace difference — it only takes the sting out of a single mistake.
func rubber_band(dt: float) -> void:
	var band: float = DIFFICULTY[s.difficulty].band
	var p := player
	if not band or phase != "racing" or p.dnf:
		return
	var L := track.L
	var v_avg: float = L / cal.T0
	var pp := p.lap * L + p.s
	for c in cars:
		if c.is_player:
			continue
		if c.dnf or c.finished or c.mode != "race":
			c.pace_scale = 1.0
			continue
		var gap_sec := (c.lap * L + c.s - pp) / v_avg
		var over := clampf((absf(gap_sec) - 5.0) / 20.0, 0.0, 1.0)
		var want := 1.0 - signf(gap_sec) * band * over
		c.pace_scale = c.pace_scale + clampf(want - c.pace_scale, -dt * 0.04, dt * 0.04)

# ---------------- ordering + results ----------------
func _order_key(c: RaceCar) -> float:
	var L := track.L
	if c.dnf:
		return -1e12 + c.lap * L + c.s
	if c.finished:
		return c.finish_lap * L + L - 1.0 - c.finish_order * 1e-3
	return c.lap * L + c.s

## Runs every physics tick (120/s), so this sorts `order` in place instead of the
## cars.duplicate() + _stable_sort() combo, which allocated a fresh array, a fresh
## index Dictionary, and two fresh closures every single tick. `cars` never changes
## after the grid is built, and car order only shifts a little tick to tick, so a plain
## insertion sort over the persistent `order` array settles in close to O(n).
func update_order() -> void:
	for c in order:
		_order_key_cache[c] = _order_key(c)
	for i in range(1, order.size()):
		var cur: RaceCar = order[i]
		var cur_key: float = _order_key_cache[cur]
		var cur_idx: int = _order_idx[cur]
		var j := i - 1
		while j >= 0:
			var oj: RaceCar = order[j]
			var oj_key: float = _order_key_cache[oj]
			if oj_key > cur_key or (oj_key == cur_key and _order_idx[oj] < cur_idx):
				break
			order[j + 1] = oj
			j -= 1
		order[j + 1] = cur
	for i in order.size():
		order[i].pos = i + 1

## Final classification: [{pos, car, laps, total, gap, status}].
func results() -> Array:
	var rows := []
	for c in cars:
		rows.append({"car": c, "laps": c.finish_lap if c.finished else c.lap,
			"total": c.finish_time + c.penalty if c.finish_time != null else null})
	var before := func(a: Dictionary, b: Dictionary) -> bool:
		if a.car.dnf != b.car.dnf:
			return not a.car.dnf
		if b.laps != a.laps:
			return a.laps > b.laps
		if a.total != null and b.total != null:
			return a.total < b.total
		if a.total != null:
			return true
		if b.total != null:
			return false
		return a.car.s > b.car.s
	_stable_sort(rows, before)
	var win: Dictionary = rows[0]
	var out := []
	for i in rows.size():
		var r: Dictionary = rows[i]
		var gap := ""
		if i > 0:
			if r.laps < win.laps:
				var dl: int = win.laps - r.laps
				gap = "+%d lap%s" % [dl, "s" if dl > 1 else ""]
			elif r.total != null and win.total != null:
				gap = "+%.3f" % (r.total - win.total)
		var status := ""
		if r.car.dnf:
			status = "DNF — " + r.car.dnf_reason
		elif r.car.running:
			status = "Not classified (still running)"
		out.append({"pos": i + 1, "car": r.car, "laps": r.laps, "total": r.total, "gap": gap, "status": status})
	return out

# ---------------- player pit-wall controls ----------------
func player_toggle_pit() -> void:
	var p := player
	if p.mode == "pit" or p.finished or s.qualifying:
		return
	p.pit_request = not p.pit_request
	if not p.service:
		p.service = default_service(p)
	log_event("Pit request confirmed — box at the end of this lap" if p.pit_request else "Pit request cancelled", "box")

func player_cycle_compound(dir: int) -> void:
	var p := player
	if p.mode == "pit" and p.pit.phase != "in":
		return
	if not p.service:
		p.service = default_service(p)
	var list := ["S", "M", "H", "W", null]
	var i := list.find(p.service.c)
	var c = list[posmod(i + dir, list.size())]
	p.service = make_service(p, c, p.service.fuel_target)
	p.service_edited = true

func player_adjust_fuel(delta: float) -> void:
	var p := player
	if not rules.refuel or (p.mode == "pit" and p.pit.phase != "in"):
		return
	if not p.service:
		p.service = default_service(p)
	p.service = make_service(p, p.service.c, clampf(p.service.fuel_target + delta, 0.0, spec.tank))
	p.service_edited = true

func player_replan() -> void:
	var p := player
	p.plan_stale = true
	p.service_edited = false
	var rem := R - (p.lap + 1)
	if rem <= 0:
		return
	var opts := strategy.plan(plan_opts({
		"laps": rem, "wet": weather.wet, "max_stops": 4,
		"current": {"c": p.tyre.c, "wear": p.tyre.wear, "fuel": p.fuel, "mask": p.used_mask, "stops_done": p.stops},
	}))
	if not opts.size():
		log_event("Strategist: no valid plan found from here", "bad")
		return
	_replace_plan(p, opts[0], p.lap + 1 - p.stint_start_lap)
	p.plan_stale = false
	p.plan_wet = weather.wet
	p.service = default_service(p)
	var nxt = p.plan[p.stint_idx + 1] if p.stint_idx + 1 < p.plan.size() else null
	if nxt:
		log_event("Strategist: box after lap %d for %s" % [p.stint_start_lap + p.plan[p.stint_idx].laps, tyres.compounds[nxt.c].display_name], "box")
	else:
		log_event("Strategist: no more stops, bring it home", "box")

func set_autopilot(on: bool) -> void:
	var p := player
	if p.finished or p.mode == "pit":
		return
	p.autopilot = on
	if on:
		p.control = "rail"
		p.v = maxf(0.0, p.vx * cos(p.heading) + p.vy * sin(p.heading))
		p.d_kick = 0.0
		p.lat_v = 0.0
	else:
		to_free(p)

## Lap the player's next planned stop is after (1-based), or -1.
func player_next_stop_lap() -> int:
	var p := player
	if p.stint_idx >= p.plan.size() - 1:
		return -1
	return p.stint_start_lap + p.plan[p.stint_idx].laps

static func fmt_time(t) -> String:
	if t == null or not is_finite(t):
		return "—"
	var m := int(floorf(t / 60.0))
	var sec: float = t - m * 60
	if m > 0:
		return "%d:%s" % [m, ("%.3f" % sec).lpad(6, "0")]
	return "%.3f" % sec
