## Lap-time model + pit strategy planner (port of js/strategy.js).
##
## A quasi-steady lap simulation (same engine/tyre model the cars use) is run per track to learn how
## lap time responds to grip and mass, what a lap costs in fuel and how much time a pit lane
## drive-through loses. The planner then runs a dynamic programme over (laps covered, stops,
## compound, compounds used) to find the fastest stint plans that satisfy the race rules.
class_name Strategy
extends RefCounted

const G := 9.81
const PIT_SPEED := 60.0 / 3.6
const FUEL_MARGIN := 1.04
const RESERVE := 0.4 ## litres left in the tank at the end of a stint
const LONG_RACE := 60 ## laps; longer races are planned over a rolling horizon
const NO_LIMIT := 1 << 30

const CREWS := {
	"pro": {"name": "Pro crew", "fixed": 2.0, "tyres": 6.5, "rate": 2.4},
	"club": {"name": "Club crew", "fixed": 3.0, "tyres": 14.0, "rate": 1.2},
	"amateur": {"name": "Mates with a jack", "fixed": 5.0, "tyres": 32.0, "rate": 0.5},
}

var car: CarModel
var tyres: Tyres

func _init(car_model: CarModel, tyre_model: Tyres) -> void:
	car = car_model
	tyres = tyre_model

static func service_time(crew: String, parallel: bool, with_tyres: bool, litres: float) -> float:
	var c: Dictionary = CREWS[crew]
	var tt: float = c.tyres if with_tyres else 0.0
	var ft: float = 1.5 + litres / c.rate if litres > 0.05 else 0.0
	if not with_tyres and not (litres > 0.05):
		return c.fixed * 0.5
	return c.fixed + (maxf(tt, ft) if parallel else tt + ft)

## Returns {time, fuel, dts, vs} (dts/vs per sample, only when record is set). pace scales the
## cornering speed the way a driver's skill does on the rail model (1 = at the grip limit).
func sim_lap(track: Track, mu: float, mass: float, record := false, pace := 1.0) -> Dictionary:
	var n := track.n
	var sq := sqrt(mu) * pace
	var v := 20.0
	var t := 0.0
	var fuel := 0.0
	var dts := PackedFloat64Array()
	var vs := PackedFloat64Array()
	if record:
		dts.resize(n)
		vs.resize(n)
	var RDS := track.RDS
	var PROF := track.PROF
	var GRADE := track.GRADE
	var RK := track.RK
	var eff := car.spec.efficiency
	var fw := car.spec.front_weight
	for pass_ in 2:
		t = 0.0
		fuel = 0.0
		for i in n:
			var ds := RDS[i]
			var v_allow := PROF[(i + 1) % n] * sq
			var climb := G * GRADE[i] + car.scrub(v, RK[i], mu)
			var a := car.max_accel(v, mass, mu) - climb
			var v2 := sqrt(maxf(0.25, v * v + 2 * a * ds))
			var power: float
			if v2 >= v_allow:
				v2 = v_allow
				var need := mass * 1.05 * (v2 * v2 - v * v) / (2 * ds) + car.resistance(v, mass) + mass * climb
				power = maxf(0.0, need) * v / eff
			else:
				var g := car.best_gear(v)
				power = minf(car.wheel_force(v, g, 1.0), fw * mu * G * mass) * v / eff
			var dt := 2 * ds / (v + v2)
			t += dt
			fuel += car.fuel_rate(power) * dt
			if record:
				dts[i] = dt
				vs[i] = v
			v = v2
	return {"time": t, "fuel": fuel, "dts": dts, "vs": vs}

## Time lost driving through the pit lane (entry to exit) versus staying on track; excludes service.
func pit_lane_loss(track: Track, ref: Dictionary, mass: float) -> float:
	var cfg := track.cfg
	var n := track.n
	var i0 := SimUtil.js_round(track.wrap_s(cfg.pit_entry) / track.step)
	var count := SimUtil.js_round((cfg.pit_exit - cfg.pit_entry) / track.step)
	var box_p := track.box_s(7)
	var cap := PackedFloat64Array()
	cap.resize(count + 1)
	var t_race := 0.0
	var dts: PackedFloat64Array = ref.dts
	for k in count + 1:
		var i := (i0 + k) % n
		var p := cfg.pit_entry + k * track.step
		cap[k] = track.PROF[i]
		if p >= track.lane_start and p <= track.lane_end:
			cap[k] = minf(cap[k], PIT_SPEED)
		if absf(p - box_p) < track.step / 2:
			cap[k] = 0.0
		if k < count:
			t_race += dts[i]
	for k in range(count - 1, -1, -1):
		cap[k] = minf(cap[k], sqrt(cap[k + 1] * cap[k + 1] + 2 * 6 * track.step))
	var v: float = ref.vs[i0]
	var t := 0.0
	for k in count:
		var a := car.max_accel(v, mass, 1.0) - G * track.GRADE[(i0 + k) % n]
		var v2 := minf(cap[k + 1], sqrt(maxf(0.0, v * v + 2 * a * track.step)))
		t += 2 * track.step / maxf(0.5, v + v2)
		v = v2
	return t - t_race

## Per-track calibration, cached on the track: {m_ref, mu_grid [[mu, time]], mass_exp, T0, fuel_per_lap,
## pit_drive_loss, top_speed, vs (the reference lap's speed at each sample)}.
func calibrate(track: Track) -> Dictionary:
	if not track.cal.is_empty():
		return track.cal
	var m_ref := car.mass_with_fuel(15.0)
	var mu_grid := []
	var mu := 0.4
	while mu <= 1.25001:
		mu_grid.append([mu, sim_lap(track, mu, m_ref).time])
		mu += 0.05
	var ref := sim_lap(track, 1.0, m_ref, true)
	var heavy: float = sim_lap(track, 1.0, m_ref + 60.0).time
	var mass_exp := log(heavy / ref.time) / log((m_ref + 60.0) / m_ref)
	var top := -INF
	for x in ref.vs:
		top = maxf(top, x)
	track.cal = {
		"m_ref": m_ref,
		"mu_grid": mu_grid,
		"mass_exp": mass_exp,
		"T0": ref.time,
		"fuel_per_lap": ref.fuel,
		"pit_drive_loss": pit_lane_loss(track, ref, m_ref),
		"top_speed": top,
		"vs": ref.vs,
	}
	return track.cal

static func lap_time(cal: Dictionary, mu_eff: float, mass: float) -> float:
	var g: Array = cal.mu_grid
	var t: float
	if mu_eff <= g[0][0]:
		t = g[0][1] * pow(g[0][0] / mu_eff, 0.5)
	elif mu_eff >= g[-1][0]:
		t = g[-1][1]
	else:
		var k := mini(g.size() - 2, int(floorf((mu_eff - g[0][0]) / 0.05)))
		var f: float = (mu_eff - g[k][0]) / (g[k + 1][0] - g[k][0])
		t = g[k][1] + (g[k + 1][1] - g[k][1]) * f
	return t * pow(mass / cal.m_ref, cal.mass_exp)

static func fuel_need(laps: float, fpl: float) -> float:
	return laps * fpl * FUEL_MARGIN + RESERVE

## Time for `laps` laps on one set of tyres, starting from the given tyre/fuel state.
func stint_time(ctx: Dictionary, c: String, laps: int, fuel_start: float, wear0: float, temp0: float) -> float:
	var track: Track = ctx.track
	var fpl: float = ctx.fpl
	var per_lap: float = track.L * tyres.wear_per_metre(c, ctx.wet, ctx.wear_mult) * ctx.agg
	var w := wear0
	var fuel := fuel_start
	var temp := temp0
	var t := 0.0
	var base := tyres.compound_grip(c, ctx.wet)
	for lap in laps:
		var warm_frac := minf(1.0, (1.0 - temp) * 1500.0 / track.L)
		var temp_f := 1.0 - warm_frac * (1.0 - Tyres.temp_grip((temp + 1.0) / 2))
		var grip := base * Tyres.wear_grip(w - per_lap / 2) * temp_f
		t += lap_time(ctx.cal, grip * ctx.skill2, car.mass_with_fuel(maxf(0.0, fuel - fpl / 2)))
		w -= per_lap
		fuel -= fpl
		temp = 1.0
		if w < 0.04 or fuel < RESERVE * 0.5 - 1e-6:
			return INF
	return t

## opts: {track, laps, wet, wear_mult, fuel_mult, rules: {mandatory_stop, two_compounds, refuel},
##        crew, parallel, skill, agg, max_stops, current: {c, wear, fuel, mask, stops_done},
##        force_pit, diverse}
## Returns plans sorted by estimated time: [{stints: [{c, laps, fuel, cont?}], time, stops, horizon}].
## With `current`, the first stint is the continuation of the current tyres (fuel 0 = no stop).
func plan(opts: Dictionary) -> Array:
	var track: Track = opts.track
	var cal := calibrate(track)
	var rules: Dictionary = opts.rules
	var refuel: bool = rules.refuel
	var fpl: float = cal.fuel_per_lap * opts.fuel_mult
	var tank := car.spec.tank
	# Endurance races are planned over a rolling horizon of about three tanks: the cars extend
	# the plan as they go. Stop counts and compound masks stop mattering there, so the state collapses.
	var long: bool = opts.laps > LONG_RACE and refuel
	var R: int = mini(opts.laps, maxi(LONG_RACE, ceili(3 * tank / fpl))) if long else opts.laps
	var skill: float = opts.get("skill", 1.0)
	var ctx := {
		"cal": cal, "track": track, "fpl": fpl,
		"wet": opts.get("wet", 0.0),
		"wear_mult": opts.wear_mult,
		"skill2": skill * skill,
		"agg": opts.get("agg", 1.0),
	}
	var cur = opts.get("current")
	var stops_done: int = cur.stops_done if cur else 0
	var max_stops: int = NO_LIMIT if long else (opts.max_stops if opts.get("max_stops") != null else mini(6, 2 + ceili(R / 6.0)))
	var start_fuel = cur.fuel if cur else (null if refuel else fuel_need(R, fpl))
	if not cur and not refuel and start_fuel > tank:
		return []
	var diverse: bool = opts.get("diverse", false)
	var two: bool = rules.two_compounds

	var memo := {}
	# cost of a fresh-tyre stint of n laps starting after r laps: [time, fuel]
	var stint := func(c: String, n: int, r: int) -> Array:
		var key := "%s%d" % [c, n] if refuel else "%s%d,%d" % [c, n, r]
		if memo.has(key):
			return memo[key]
		var fuel: float = fuel_need(n, fpl) if refuel else start_fuel - r * fpl
		var res: Array
		if fuel > tank + 1e-6:
			res = [INF, fuel]
		else:
			res = [stint_time(ctx, c, n, fuel, 1.0, 0.3), fuel]
		memo[key] = res
		return res
	var stop_cost := func(fuel_target: float) -> float:
		var litres := maxf(0.0, fuel_target - RESERVE) if refuel else 0.0
		return cal.pit_drive_loss + service_time(opts.crew, opts.parallel, true, litres)

	var buckets := []
	for r in R + 1:
		buckets.append({})
	var relax := func(node: Dictionary) -> void:
		var k: int
		if long:
			k = mini(node.j, 1) * 1000 + node.c * 100 + (node.m * 4 if two else 0) + (node.f if diverse else 0)
		else:
			k = node.j * 1000 + node.c * 100 + node.m * 4 + (node.f if diverse else 0)
		var b: Dictionary = buckets[node.r]
		var e = b.get(k)
		if e == null or node.t < e.t:
			b[k] = node
	var keys := Tyres.KEYS

	if not cur:
		for ci in keys.size():
			var c: String = keys[ci]
			for n in range(1, R + 1):
				var s: Array = stint.call(c, n, 0)
				if not is_finite(s[0]):
					break
				relax.call({"r": n, "j": 0, "c": ci, "m": Tyres.compound_bit(c), "f": ci, "t": s[0], "prev": null,
					"st": {"c": c, "laps": n, "fuel": s[1]}})
	else:
		var n_max: int = 0 if opts.get("force_pit", false) else R
		var cci := keys.find(cur.c)
		for n in n_max + 1:
			var tt := 0.0 if n == 0 else stint_time(ctx, cur.c, n, cur.fuel, cur.wear, 1.0)
			if not is_finite(tt):
				break
			relax.call({"r": n, "j": 0, "c": cci, "m": cur.mask, "f": cci, "t": tt, "prev": null,
				"st": {"c": cur.c, "laps": n, "fuel": 0.0, "cont": true} if n else null})

	for r in R:
		for node in buckets[r].values():
			if node.j >= max_stops:
				continue
			for ci in keys.size():
				var c: String = keys[ci]
				for n in range(1, R - r + 1):
					var s: Array = stint.call(c, n, r)
					if not is_finite(s[0]):
						break
					relax.call({
						"r": r + n,
						"j": node.j + 1,
						"c": ci,
						"m": node.m | Tyres.compound_bit(c),
						"f": node.f,
						"t": node.t + stop_cost.call(s[1]) + s[0],
						"prev": node,
						"st": {"c": c, "laps": n, "fuel": s[1] if refuel else 0.0},
					})

	var dry_mask := Tyres.compound_bit("S") | Tyres.compound_bit("M") | Tyres.compound_bit("H")
	var out := []
	for node in buckets[R].values():
		var stops: int = stops_done + node.j
		if rules.mandatory_stop and stops < 1:
			continue
		if two and not (node.m & Tyres.compound_bit("W")):
			var bits: int = node.m & dry_mask
			var count := 0
			while bits:
				count += bits & 1
				bits >>= 1
			if count < 2:
				continue
		var stints := []
		var q = node
		while q:
			if q.st:
				stints.push_front(q.st)
			q = q.prev
		out.append({"stints": stints, "time": node.t, "stops": node.j, "horizon": R if R < opts.laps else 0, "_i": out.size()})
	# stable sort by time, like JS Array.sort
	out.sort_custom(func(p, q): return p.time < q.time or (p.time == q.time and p._i < q._i))
	# one entry per distinct compound sequence/stop count, best first
	var seen := {}
	var res := []
	for p in out:
		p.erase("_i")
		var k := ""
		for s in p.stints:
			k += s.c
		k += str(p.stops)
		if seen.has(k):
			continue
		seen[k] = true
		res.append(p)
	return res

## Validate and time a hand-built plan. stints: [{c, laps}]. Returns {stints, time, stops, errors}.
func evaluate(opts: Dictionary, stints: Array) -> Dictionary:
	var cal := calibrate(opts.track)
	var R: int = opts.laps
	var fpl: float = cal.fuel_per_lap * opts.fuel_mult
	var rules: Dictionary = opts.rules
	var tank := car.spec.tank
	var ctx := {"cal": cal, "track": opts.track, "fpl": fpl, "wet": opts.get("wet", 0.0), "wear_mult": opts.wear_mult,
		"skill2": 1.0, "agg": 1.0}
	var errors := []
	var total := 0
	for st in stints:
		total += st.laps
	if total != R:
		errors.append("Stints cover %d laps, the race is %d" % [total, R])
	var r := 0
	var time := 0.0
	var out := []
	var start_fuel := 0.0 if rules.refuel else fuel_need(R, fpl)
	for k in stints.size():
		var st: Dictionary = stints[k]
		var fuel: float = fuel_need(st.laps, fpl) if rules.refuel else start_fuel - r * fpl
		if fuel > tank + 1e-6:
			errors.append("Stint %d needs %.1f L — the tank holds %s L" % [k + 1, fuel, str(int(tank)) if tank == floorf(tank) else str(tank)])
		var t := stint_time(ctx, st.c, st.laps, minf(fuel, tank), 1.0, 0.3)
		if not is_finite(t) and fuel <= tank:
			errors.append("Stint %d: %ss won't last %d laps" % [k + 1, tyres.compounds[st.c].display_name, st.laps])
		time += t
		if k > 0:
			time += cal.pit_drive_loss + service_time(opts.crew, opts.parallel, true, maxf(0.0, fuel - RESERVE) if rules.refuel else 0.0)
		out.append({"c": st.c, "laps": st.laps, "fuel": minf(fuel, tank) if rules.refuel or k == 0 else 0.0})
		r += st.laps
	if rules.mandatory_stop and stints.size() < 2:
		errors.append("A pit stop is mandatory")
	if rules.two_compounds:
		var used := {}
		var wet := false
		for st in stints:
			used[st.c] = true
			wet = wet or st.c == "W"
		if not wet and used.size() < 2:
			errors.append("Two different dry compounds are required")
	return {"stints": out, "time": time, "stops": stints.size() - 1, "errors": errors}

## Expected laps for a timed race: typical lap plus the pit time spread over a tank of fuel.
## s: race settings {fuel_mult, weather, wear_mult, crew, parallel, refuel}.
func estimate_laps(track: Track, duration: float, s: Dictionary) -> int:
	var cal := calibrate(track)
	var fpl: float = cal.fuel_per_lap * s.fuel_mult
	var tank := car.spec.tank
	var lap := lap_time(cal, tyres.compound_grip("M", 0.85 if s.weather == "wet" else 0.0) * 0.96 * 0.96, car.mass_with_fuel(tank / 2))
	var stint_laps := maxf(1.0, minf(tank / fpl, tyre_life_laps(track, "H", 0.0, s.wear_mult) * 0.9))
	var stop: float = cal.pit_drive_loss + service_time(s.crew, s.parallel, true, tank * 0.8 if s.refuel else 0.0)
	return maxi(1, SimUtil.js_round(duration / (lap * 1.01 + stop / stint_laps)))

## Laps a fresh set lasts at nominal driving load.
func tyre_life_laps(track: Track, c: String, wet: float, wear_mult: float) -> float:
	return 1.0 / (track.L * tyres.wear_per_metre(c, wet, wear_mult))

static func label(p: Dictionary) -> String:
	var n_stops: int = p.get("stops", maxi(0, p.get("stints", []).size() - 1))
	var stops := "No stop" if n_stops <= 0 else ("1 stop" if n_stops == 1 else "%d stops" % n_stops)
	var parts := []
	for s in p.get("stints", []):
		parts.append("%s%d" % [s.c, s.laps])
	return stops + ": " + " → ".join(parts)
