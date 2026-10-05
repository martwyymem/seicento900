## Single-car qualifying for a championship round, after NASCAR Racing 2002 Season: the player goes out
## alone, takes an out lap to warm the tyres, then runs the timed laps (the best one counts). The rest of
## the field "ran" before or after: each bot's time is the lap its pace would set on the same tyres and
## fuel, and the sheet sets the starting grid, fastest first.
class_name Qualifying
extends RefCounted

const LONG_LAP := 300.0 ## s: a circuit this long (the Nordschleife) gets a single timed lap

## Timed laps after the out lap, from the circuit's reference lap time.
static func timed_laps(lap_ref: float) -> int:
	return 1 if lap_ref > LONG_LAP else 2

## Turns a set of race settings into a qualifying session: no pit rules, flags or learning, the player
## alone on the circuit with the field's pace kept aside for the sheet.
static func configure(settings: RaceSettings) -> void:
	settings.qualifying = true
	settings.format = "laps"
	settings.mandatory_stop = false
	settings.two_compounds = false
	settings.refuel = false
	settings.race_control = false
	settings.auto_strategist = false
	settings.ai_learning = "off"

## The idealised lap model is faster than any car that has to obey the physics, and by a different amount on
## every circuit, so a sheet built straight from it would be out of reach. The sheet is anchored to what the
## game's own co-driver (the player's car on autopilot, at its 0.97 pace) really laps: a driver as good as the
## co-driver sits where a 0.97 bot would, and difficulty moves the field around that. Measured once per circuit
## and kept on the track; returns the factor from the model's time (see bot_time) to the real one.
static func coach_scale(r: Race) -> float:
	if r.track.cal.has("quali_scale"):
		return r.track.cal.quali_scale
	var st := RaceSettings.new()
	st.track = r.s.track
	st.opponents = 0
	st.weather = "dry"
	st.start_hour = 14.0
	configure(st)
	var cr := Race.new(st, null, 1, {"car_model": r.car_model, "tyres": r.tyres, "strategy": r.strategy})
	cr.set_autopilot(true)
	var inp := Race.PlayerInput.new()
	var guard := 0
	while cr.phase != "finished" and guard < 120 * 3600:
		cr.step(1.0 / 120.0, inp)
		guard += 1
	var best = cr.player.best_lap
	for t in cr.player.lap_times.slice(1):
		best = t if best == null else minf(best, t)
	var scale := 1.0
	if best != null:
		scale = best / bot_time(cr, lap_time(cr, CO_DRIVER), CO_DRIVER, lap_time(cr, 1.0), 1.0)
	cr.dispose()
	r.track.cal["quali_scale"] = scale * FIELD_EASE
	return r.track.cal.quali_scale

const CO_DRIVER := 0.97 ## the pace a player on autopilot drives at (see Race.build_field)
const FIELD_EASE := 1.015 ## the field's laps are this much slower than a co-driver-level lap implies, so a good human lap can reach the grid

## A driver's qualifying lap on the model: its time at this pace, with a small gap by pace kept on a
## circuit that is flat out nearly everywhere (where the model barely separates drivers); times scale.
static func bot_time(_r: Race, model_time: float, pace: float, ref_time: float, scale: float) -> float:
	return maxf(model_time, ref_time * (1.0 + 0.2 * (1.0 - pace))) * scale

## Lap time of a car of this pace (1 = the car's limit) on fresh, warm qualifying tyres and a light tank.
static func lap_time(r: Race, pace: float) -> float:
	var mu := r.tyres.tyre_grip({"c": r.quali_compound(), "wear": 1.0, "temp": 1.0}, r.weather.wet)
	return r.strategy.sim_lap(r.track, mu, r.car_model.mass_with_fuel(r.quali_fuel), false, pace).time

## Qualifying lap times for several paces at once (see bot_time). A lap is a smooth function of pace over the few percent the field
## spans, so three simulated laps and a quadratic through them stand in for one lap per driver.
static func lap_times(r: Race, paces: Array) -> Array:
	if paces.is_empty():
		return []
	var scale := coach_scale(r)
	var ref := lap_time(r, 1.0)
	var raw := _model_times(r, paces)
	var out := []
	for i in paces.size():
		out.append(bot_time(r, raw[i], paces[i], ref, scale))
	return out

static func _model_times(r: Race, paces: Array) -> Array:
	if paces.size() <= 3:
		return paces.map(func(p: float) -> float: return lap_time(r, p))
	var lo: float = paces.min()
	var hi: float = paces.max()
	var mid := (lo + hi) * 0.5
	var t0 := lap_time(r, lo)
	var t1 := lap_time(r, mid)
	var t2 := lap_time(r, hi)
	return paces.map(func(p: float) -> float:
		if hi - lo < 1e-9:
			return t0
		var u := (p - mid) / ((hi - lo) * 0.5) # -1 at the slowest pace, +1 at the fastest
		return t1 + u * (t2 - t0) * 0.5 + u * u * ((t0 + t2) * 0.5 - t1))

## What the player's laps are worth if the co-driver runs them (the "simulate" option).
static func simulated_player_time(r: Race) -> float:
	var pace: float = r.player.skill + (r.rng.next() - 0.5) * 0.02
	return bot_time(r, lap_time(r, pace), pace, lap_time(r, 1.0), coach_scale(r))

## The time sheet, fastest first: [{id, name, number, color, time, speed, gap, is_player}].
## A player without a valid timed lap is listed last with no time (starts from the back).
static func sheet(r: Race, player_time = null) -> Array:
	var rows := []
	for b in r.quali_bots:
		rows.append(_row(r, b, r.quali_times[b.id]))
	rows.append(_row(r, r.player, player_time if player_time != null else r.player.best_lap))
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if (a.time == null) != (b.time == null):
			return b.time == null
		if a.time == null:
			return int(a.id) < int(b.id)
		if a.time != b.time:
			return a.time < b.time
		return int(a.id) < int(b.id))
	var pole = rows[0].time
	for i in rows.size():
		rows[i].pos = i + 1
		rows[i].gap = rows[i].time - pole if rows[i].time != null and pole != null else null
	return rows

static func _row(r: Race, car: RaceCar, time) -> Dictionary:
	return {"id": car.id, "name": car.name, "number": car.number, "color": car.color, "time": time,
		"speed": r.track.L / time * 3.6 if time != null else null, "is_player": car.is_player}

## What the race needs from the sheet: grid order (car ids) and the bots' pace, so they race as they qualified.
## Keys are strings so the dictionary survives a trip through JSON with the saved championship.
static func grid_from(r: Race, rows: Array) -> Dictionary:
	var order := []
	for row in rows:
		order.append(int(row.id))
	var skills := {}
	var quali := {}
	for b in r.quali_bots:
		skills[str(b.id)] = b.skill
		quali[str(b.id)] = b.quali
	return {"order": order, "skills": skills, "quali": quali}
